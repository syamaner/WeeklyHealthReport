"""Route C and drafting spend stops (plan section 8.3, decision 9). Pure apart from the ledger file.

Inspect's native `cost_limit` is per sample and priced from a model-cost table;
the plan's stops use the cost OpenRouter reports per response and span the whole
evaluation, so this small guard enforces them around each call:

- stop a model's run if any single call reports more than $0.05;
- stop the whole evaluation at $25 of reported cost;
- stop at the first unknown-cost call beyond three;
- reserve the sealed run's 200 calls (at the $0.05 per-call ceiling, $10) out of the
  total before any development call, so the stop can never be reached with the
  untouched set unrun.

Unknown costs are counted and reported as unknown, never as zero. Calls in flight are
counted at the per-call ceiling until their cost is recorded, so concurrent requests
cannot overrun a stop.

`LedgerBudget` persists the same state in one JSON ledger outside the repository, so the
$25 total and the 200-call sealed reservation hold across separate Inspect runs, models
and the untouched truth drafting. The ledger records each call's purpose, model, case id
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


class BudgetStop(RuntimeError):
    """Raised when a pre-registered spend stop is reached."""


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
        self.sealed_run = sealed_run
        self.path = path
        self.lock_path = path.with_name(path.name + ".lock")
        self.entries: list[dict[str, Any]] = []
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
        }

    def _load(self) -> None:
        data = json.loads(self.path.read_text(encoding="utf-8"))
        if data.get("schema_version") != LEDGER_SCHEMA:
            raise BudgetStop("the spend ledger has an unknown schema")
        if data.get("limits") != self._limits():
            raise BudgetStop("the spend ledger limits differ from the contract; refusing to continue")
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
        return sum(1 for e in self.entries if e.get("cost_usd") is None)

    @property
    def sealed_calls_made(self) -> int:
        """Recorded sealed calls plus open ones, so a lost sealed call still uses the cap."""
        return sum(1 for e in self.entries if e.get("sealed")) + self.open_sealed_calls

    @property
    def reserved_usd(self) -> Decimal:
        return Decimal(max(self.sealed_reserved_calls - self.sealed_calls_made, 0)) * self.per_call_usd

    def _limit(self) -> Decimal:
        return self.total_usd if self.sealed_run else self.total_usd - self.reserved_usd

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
    ) -> None:
        """Record one completed call; `at` is supplied by the caller (no clock here)."""
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
