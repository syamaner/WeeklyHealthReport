"""Route C and drafting spend stops (plan section 8.3, decision 9). Pure apart from the ledger file.

Inspect's native `cost_limit` is per sample and priced from a model-cost table;
the plan's stops use the cost OpenRouter reports per response and span the whole
evaluation, so this small guard enforces them around each attempt:

- stop a model's run if any single attempt reports more than the per-call stop ($0.05 in
  the plan; $0.20 for route C from the owner's decisions of 17 October 2026). The stop is
  checked per attempt, not on the sum of a retried call's attempts;
- stop the whole evaluation at the total stop ($25 in the plan; $65 from the owner's
  decisions of 17 October 2026, after an intermediate $60);
- stop at the first unknown-cost call beyond three (errors that returned no generation,
  `retryable_error_unknown_cost` and `rejected_no_generation_unknown_cost`, are recorded
  but do not count; an HTTP 200 answer without a cost does);
- reserve the sealed run's 200 calls (now at $0.20 each, $40) out of the total before any
  development call, so the stop can never be reached with the untouched set unrun.

The ledger's limits change only through `LedgerBudget.amend_limits`, which records the
change in `limits_history`; a ledger whose limits differ from the caller's is refused.
Relabelling, pausing and closing an interrupted call are recorded in `amendments`.

Unknown costs are counted and reported as unknown, never as zero. Calls in flight are
counted at the current per-call stop until their cost is recorded, so concurrent
requests cannot overrun a stop.

`LedgerBudget` persists the same state in one JSON ledger outside the repository, so the
total and the 200-call sealed reservation hold across separate Inspect runs, models and
the untouched truth drafting. The ledger records each attempt's purpose, model, case id
and reported cost; it never holds a key, a header, a prompt or a response.
"""

from __future__ import annotations

import fcntl
import json
import os
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path
from typing import Any

LEDGER_SCHEMA = "label-capture-spend-ledger-v1"
# An attempt that ended in a retryable error with no generation returned (transport error,
# timeout, 408, 429 or 5xx). Its cost is unknown, but it does not count toward the
# three-unknown stop (owner, 17 October 2026); an HTTP 200 answer without a cost still does.
RETRYABLE_ERROR_KIND = "retryable_error_unknown_cost"
# A non-retryable rejection (HTTP 4xx) that returned no generation (no `id` and no `usage`),
# for example "reasoning is mandatory for this endpoint". Also recorded as unknown and also
# excluded from the three-unknown stop (owner, 17 October 2026).
REJECTED_ERROR_KIND = "rejected_no_generation_unknown_cost"
NOT_COUNTED_UNKNOWN_KINDS = frozenset({RETRYABLE_ERROR_KIND, REJECTED_ERROR_KIND})


class BudgetStop(RuntimeError):
    """Raised when a pre-registered spend stop is reached."""


def contract_limits(contract: dict[str, Any]) -> dict[str, Any]:
    """The ledger limits from `frozen-contract-v1.json`'s route_c block."""
    route_c = contract["route_c"]
    return {
        "per_call_usd": route_c["per_call_stop_usd"],
        "total_usd": route_c["total_stop_usd"],
        "unknown_cost_calls_allowed": route_c["unknown_cost_calls_allowed"],
        "sealed_reserved_calls": route_c["sealed_run_reserved_calls"],
        "sealed_reserved_per_call_usd": route_c["sealed_reservation_per_call_usd"],
    }


def sealed_projection_check(
    reported_spend_usd: Decimal, open_calls_usd: Decimal, total_usd: Decimal, projected_per_call_usd: Decimal, calls: int
) -> Decimal:
    """Before any sealed run: spend so far plus the projected sealed cost must fit the total.

    Returns the projected sealed cost; raises BudgetStop otherwise, so the owner decides
    whether to raise the total. A sealed run is never cut short silently.
    """
    projected = projected_per_call_usd * calls
    if reported_spend_usd + open_calls_usd + projected > total_usd:
        raise BudgetStop(
            f"spend {reported_spend_usd + open_calls_usd} plus the projected sealed cost {projected} exceeds the {total_usd} total; "
            "the owner decides whether to raise it"
        )
    return projected


@dataclass
class RunBudget:
    per_call_usd: Decimal = Decimal("0.05")
    total_usd: Decimal = Decimal("25")
    unknown_cost_calls_allowed: int = 3
    sealed_reserved_calls: int = 200
    sealed_run: bool = False
    spent_usd: Decimal = Decimal("0")
    unknown_cost_calls: int = 0
    sealed_calls_made: int = 0
    stopped_models: set[str] = field(default_factory=set)
    in_flight: int = 0

    @property
    def reserved_usd(self) -> Decimal:
        """Spend held back for the sealed calls not yet made."""
        remaining = max(self.sealed_reserved_calls - self.sealed_calls_made, 0)
        return Decimal(remaining) * self.per_call_usd

    def _limit(self) -> Decimal:
        # Development calls may not touch the sealed reservation; sealed calls may.
        return self.total_usd if self.sealed_run else self.total_usd - self.reserved_usd

    def before_call(self, model: str) -> None:
        if model in self.stopped_models:
            raise BudgetStop(f"{model} was stopped by the per-call limit")
        if self.sealed_run and self.sealed_calls_made + self.in_flight >= self.sealed_reserved_calls:
            raise BudgetStop("the sealed run has used its reserved calls")
        if self.unknown_cost_calls >= self.unknown_cost_calls_allowed:  # at most three: the fourth is never made
            raise BudgetStop("more than three unknown-cost calls")
        if self.spent_usd + (self.in_flight + 1) * self.per_call_usd > self._limit():
            raise BudgetStop("total stop reached (the sealed-run reservation is held back)")
        self.in_flight += 1

    def record(self, model: str, reported_cost_usd: Decimal | None) -> None:
        self.in_flight = max(self.in_flight - 1, 0)
        if self.sealed_run:
            self.sealed_calls_made += 1
        if reported_cost_usd is None:
            self.unknown_cost_calls += 1
            if self.unknown_cost_calls > self.unknown_cost_calls_allowed:
                raise BudgetStop("more than three unknown-cost calls")
            return
        self.spent_usd += reported_cost_usd
        if reported_cost_usd > self.per_call_usd:
            self.stopped_models.add(model)
            raise BudgetStop(f"{model} call cost {reported_cost_usd} exceeds the per-call stop")
        if self.spent_usd >= self.total_usd:
            raise BudgetStop("total stop reached")


class LedgerBudget:
    """The same stops as `RunBudget`, with their state in a JSON ledger outside the repository.

    The ledger is created once with the contract's limits and refuses to load if they
    ever differ. Every `before_call` and `record_call` takes an exclusive `fcntl.flock`
    on a sibling lock file, reloads the ledger, checks the stops, updates it and saves it
    atomically before releasing the lock, so separate processes (another model, another
    Inspect run, the drafting) always see one true total. A call that started but was not
    recorded (in flight elsewhere, or lost to a crash) stays in `open_calls`, is charged
    at the per-call ceiling and, for a sealed call, counts against the 200-call sealed cap.
    """

    def __init__(self, path: Path, *, sealed_run: bool = False, limits: dict[str, Any] | None = None) -> None:
        limits = limits or {}
        self.per_call_usd = Decimal(str(limits.get("per_call_usd", "0.05")))
        self.total_usd = Decimal(str(limits.get("total_usd", "25")))
        self.unknown_cost_calls_allowed = int(limits.get("unknown_cost_calls_allowed", 3))
        self.sealed_reserved_calls = int(limits.get("sealed_reserved_calls", 200))
        # The reservation is priced per call separately from the per-call stop (owner, 17 October
        # 2026): provisional during development, then the projected sealed cost.
        self.sealed_reserved_per_call_usd = Decimal(str(limits.get("sealed_reserved_per_call_usd", self.per_call_usd)))
        self.sealed_run = sealed_run
        self.path = path
        self.lock_path = path.with_name(path.name + ".lock")
        self.entries: list[dict[str, Any]] = []
        self.limits_history: list[dict[str, Any]] = []
        self.amendments: list[dict[str, Any]] = []
        self.open_calls = 0
        self.open_sealed_calls = 0
        self.stopped_models: set[str] = set()
        with self._locked():
            if path.exists():
                self._load()
            else:
                self._save()

    @contextmanager
    def _locked(self) -> Iterator[None]:
        with self.lock_path.open("a+") as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

    def _limits(self) -> dict[str, Any]:
        return {
            "per_call_usd": str(self.per_call_usd),
            "total_usd": str(self.total_usd),
            "unknown_cost_calls_allowed": self.unknown_cost_calls_allowed,
            "sealed_reserved_calls": self.sealed_reserved_calls,
            "sealed_reserved_per_call_usd": str(self.sealed_reserved_per_call_usd),
        }

    def _load(self) -> None:
        data = json.loads(self.path.read_text(encoding="utf-8"))
        if data.get("schema_version") != LEDGER_SCHEMA:
            raise BudgetStop("the spend ledger has an unknown schema")
        stored = dict(data.get("limits") or {})
        stored.setdefault("sealed_reserved_per_call_usd", stored.get("per_call_usd"))  # ledgers from before phase 3
        if stored != self._limits():
            raise BudgetStop("the spend ledger limits differ from the contract; refusing to continue")
        self.limits_history = list(data.get("limits_history", []))
        self.amendments = list(data.get("amendments", []))
        self.entries = list(data.get("entries", []))
        self.open_calls = int(data.get("open_calls", 0))
        self.open_sealed_calls = int(data.get("open_sealed_calls", 0))
        self.stopped_models = set(data.get("stopped_models", []))

    def _save(self) -> None:
        payload = {
            "schema_version": LEDGER_SCHEMA,
            "limits": self._limits(),
            "reported_spend_usd": str(self.reported_spend_usd),
            "unknown_cost_calls": self.unknown_cost_calls,
            "sealed_calls_made": self.sealed_calls_made,
            "sealed_reservation_remaining_calls": max(self.sealed_reserved_calls - self.sealed_calls_made, 0),
            "open_calls": self.open_calls,
            "open_sealed_calls": self.open_sealed_calls,
            "stopped_models": sorted(self.stopped_models),
            "limits_history": self.limits_history,
            "amendments": self.amendments,
            "entries": self.entries,
        }
        temporary = self.path.with_name(self.path.name + ".tmp")
        temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(temporary, self.path)

    @property
    def reported_spend_usd(self) -> Decimal:
        return sum((Decimal(e["cost_usd"]) for e in self.entries if e.get("cost_usd") is not None), Decimal("0"))

    @property
    def spent_usd(self) -> Decimal:
        """Reported spend plus every open call at the per-call ceiling."""
        return self.reported_spend_usd + self.open_calls * self.per_call_usd

    @property
    def unknown_cost_calls(self) -> int:
        """Unknown-cost calls that count toward the stop: errors that returned no generation do not."""
        return sum(1 for e in self.entries if e.get("cost_usd") is None and e.get("kind") not in NOT_COUNTED_UNKNOWN_KINDS)

    def set_paused(self, model: str, paused: bool, *, at: str, reason: str) -> None:
        """Pause (or resume) new calls for one model label by a recorded owner decision.

        A paused label is held in `stopped_models`, so `before_call` refuses new calls in every
        process at once, while calls already in flight are still recorded by `record_call`.
        """
        with self._locked():
            self._load()
            if paused:
                self.stopped_models.add(model)
            else:
                self.stopped_models.discard(model)
            self.amendments.append({"at": at, "reason": reason, "model": model, "paused": paused})
            self._save()

    @staticmethod
    def relabel_entries(path: Path, indices: list[int], kind: str, *, at: str, reason: str, evidence: list[dict[str, Any]]) -> None:
        """Relabel existing unknown-cost entries by an explicit, recorded owner decision (kept in `amendments`).

        Only entries with no reported cost may be relabelled, only to a kind that is excluded
        from the unknown-cost stop, and only by valid indices. An entry that carries a
        `generation_id` is refused unless the evidence records a generation lookup for it
        (`{"entry": index, "generation_lookup": ...}`), since a generation may have been charged.
        The cost itself is never changed here, and the derived counters are recomputed on write.
        """
        if kind not in NOT_COUNTED_UNKNOWN_KINDS:
            raise BudgetStop(f"refusing to relabel to {kind!r}")
        looked_up = {item.get("entry") for item in evidence if item.get("generation_lookup")}
        ledger = LedgerBudget.__new__(LedgerBudget)
        ledger.path, ledger.lock_path = path, path.with_name(path.name + ".lock")
        with ledger._locked():
            data = json.loads(path.read_text(encoding="utf-8"))
            entries = data["entries"]
            for index in indices:
                if not isinstance(index, int) or isinstance(index, bool) or not 0 <= index < len(entries):
                    raise BudgetStop(f"entry index {index!r} is out of range; refusing to relabel")
                if entries[index].get("cost_usd") is not None:
                    raise BudgetStop(f"entry {index} has a reported cost; refusing to relabel")
                if entries[index].get("generation_id") and index not in looked_up:
                    raise BudgetStop(f"entry {index} carries a generation id but no lookup result in the evidence; refusing to relabel")
            for index in indices:
                entries[index]["kind"] = kind
            amendments = list(data.get("amendments", []))
            amendments.append({"at": at, "reason": reason, "relabelled_entries": indices, "kind": kind, "evidence": evidence})
            data["amendments"] = amendments
            _recount(data)
            temporary = path.with_name(path.name + ".tmp")
            temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            os.replace(temporary, path)

    @property
    def sealed_calls_made(self) -> int:
        """Recorded sealed calls plus open ones, so a lost sealed call still uses the cap."""
        return sum(1 for e in self.entries if e.get("sealed")) + self.open_sealed_calls

    @property
    def reserved_usd(self) -> Decimal:
        return Decimal(max(self.sealed_reserved_calls - self.sealed_calls_made, 0)) * self.sealed_reserved_per_call_usd

    def _limit(self) -> Decimal:
        return self.total_usd if self.sealed_run else self.total_usd - self.reserved_usd

    @staticmethod
    def amend_limits(path: Path, new_limits: dict[str, Any], *, at: str, reason: str) -> None:
        """Change the ledger's limits only by an explicit, recorded owner decision (kept in `limits_history`)."""
        ledger = LedgerBudget.__new__(LedgerBudget)
        ledger.path, ledger.lock_path = path, path.with_name(path.name + ".lock")
        # Store the limits in the same normalised form a LedgerBudget compares against.
        ledger.per_call_usd = Decimal(str(new_limits["per_call_usd"]))
        ledger.total_usd = Decimal(str(new_limits["total_usd"]))
        ledger.unknown_cost_calls_allowed = int(new_limits["unknown_cost_calls_allowed"])
        ledger.sealed_reserved_calls = int(new_limits["sealed_reserved_calls"])
        ledger.sealed_reserved_per_call_usd = Decimal(str(new_limits.get("sealed_reserved_per_call_usd", ledger.per_call_usd)))
        new_limits = ledger._limits()
        with ledger._locked():
            data = json.loads(path.read_text(encoding="utf-8"))
            history = list(data.get("limits_history", []))
            history.append({"at": at, "reason": reason, "from": data.get("limits"), "to": new_limits})
            data["limits"], data["limits_history"] = new_limits, history
            temporary = path.with_name(path.name + ".tmp")
            temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            os.replace(temporary, path)

    CLOSE_KINDS = frozenset({"unreconciled_in_flight_ceiling_charge", "reconciled_by_generation_lookup"})

    def close_open_call(self, model: str, cost_usd: Decimal | None, *, purpose: str, case_id: str, at: str, kind: str) -> None:
        """Close one call left open by an interrupted run, with the charge decided on reconciliation.

        `kind` is one of CLOSE_KINDS, and the closure is also recorded in `amendments`.
        """
        if kind not in self.CLOSE_KINDS:
            raise BudgetStop(f"refusing to close an open call as {kind!r}")
        with self._locked():
            self._load()
            if self.open_calls < 1:
                raise BudgetStop("there is no open call to close")
            self.open_calls -= 1
            self.entries.append(
                {
                    "at": at,
                    "purpose": purpose,
                    "model": model,
                    "returned_model": None,
                    "case_id": case_id,
                    "sealed": False,
                    "cost_usd": None if cost_usd is None else str(cost_usd),
                    "kind": kind,
                }
            )
            self.amendments.append(
                {
                    "at": at,
                    "reason": "closed an open call",
                    "model": model,
                    "kind": kind,
                    "cost_usd": None if cost_usd is None else str(cost_usd),
                }
            )
            self._save()

    def before_call(self, model: str) -> None:
        with self._locked():
            self._load()
            if model in self.stopped_models:
                raise BudgetStop(f"{model} was stopped by the per-call limit")
            if self.sealed_run and self.sealed_calls_made >= self.sealed_reserved_calls:
                raise BudgetStop("the sealed run has used its reserved calls")
            if self.unknown_cost_calls >= self.unknown_cost_calls_allowed:  # at most three: the fourth is never made
                raise BudgetStop("more than three unknown-cost calls")
            if self.spent_usd + self.per_call_usd > self._limit():
                raise BudgetStop("total stop reached (the sealed-run reservation is held back)")
            self.open_calls += 1
            if self.sealed_run:
                self.open_sealed_calls += 1
            self._save()  # the open call is on disk before the request is sent

    def record_call(
        self,
        model: str,
        reported_cost_usd: Decimal | None,
        *,
        purpose: str,
        case_id: str,
        at: str,
        returned_model: str | None = None,
        kind: str | None = None,
        attempt: int | None = None,
        generation_id: str | None = None,
    ) -> None:
        """Record one completed attempt; `at` is supplied by the caller (no clock here).

        `kind` RETRYABLE_ERROR_KIND marks a retryable error with no generation returned: its
        unknown cost does not count toward the three-unknown stop.
        """
        stop: BudgetStop | None = None
        with self._locked():
            self._load()
            self.open_calls = max(self.open_calls - 1, 0)
            if self.sealed_run:
                self.open_sealed_calls = max(self.open_sealed_calls - 1, 0)
            self.entries.append(
                {
                    "at": at,
                    "purpose": purpose,
                    "model": model,
                    "returned_model": returned_model,
                    "case_id": case_id,
                    "sealed": self.sealed_run,
                    "cost_usd": None if reported_cost_usd is None else str(reported_cost_usd),
                    **({"kind": kind} if kind else {}),
                    **({"attempt": attempt} if attempt is not None else {}),
                    **({"generation_id": generation_id} if generation_id else {}),
                }
            )
            if reported_cost_usd is None:
                if self.unknown_cost_calls > self.unknown_cost_calls_allowed:
                    stop = BudgetStop("more than three unknown-cost calls")
            elif reported_cost_usd > self.per_call_usd:
                self.stopped_models.add(model)
                stop = BudgetStop(f"{model} call cost {reported_cost_usd} exceeds the per-call stop")
            elif self.spent_usd >= self.total_usd:
                stop = BudgetStop("total stop reached")
            self._save()
        if stop is not None:
            raise stop


def _recount(data: dict[str, Any]) -> None:
    """Recompute a raw ledger's derived counters from its entries (after a relabel)."""
    entries = data.get("entries", [])
    data["reported_spend_usd"] = str(sum((Decimal(e["cost_usd"]) for e in entries if e.get("cost_usd") is not None), Decimal("0")))
    data["unknown_cost_calls"] = sum(1 for e in entries if e.get("cost_usd") is None and e.get("kind") not in NOT_COUNTED_UNKNOWN_KINDS)
    sealed = sum(1 for e in entries if e.get("sealed")) + int(data.get("open_sealed_calls", 0))
    data["sealed_calls_made"] = sealed
    data["sealed_reservation_remaining_calls"] = max(int((data.get("limits") or {}).get("sealed_reserved_calls", 200)) - sealed, 0)
