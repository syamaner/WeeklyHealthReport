#!/usr/bin/env python3
"""Run route C on DEVELOPMENT photos through Inspect, one pinned model and one reasoning setting at a time.

Route C runs only while the contract sets `route_c.enabled` true, and only for a model
pinned in `route_c.models` with a passed catalogue gate (slug, endpoint and returned
provider name recorded on the run day); the runner refuses any other value. When it runs:

- the Inspect log directory must be outside the repository, and `log_images=False`;
- the key is read from the environment, or that one variable from `--env-file` into this
  process only, and is never printed, logged or written; before the first call the free
  `GET /api/v1/key` lookup reports the key's remaining credit, with a warning when it is
  below what the run could spend;
- requests go to OpenRouter through `openrouter_client` (one retry loop, every attempt in
  the persistent spend ledger) with the evaluation-only provider block (one pinned
  provider, no fallbacks, parameters required) and reasoning off or on;
- two fictional qualification labels go first (plan section 8.2); a model that does not
  return an accepted, schema-valid answer for both is sent no real image;
- development photos only: the Taiwan development photos, the UK development review
  images and the muesli photo (only with `send_to_openrouter` consent). Nothing here reads
  a sealed folder, untouched truth or drafts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import statistics
import sys
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

from openrouter_route import RouteCModel  # noqa: E402

CONTRACT = HERE / "frozen-contract-v1.json"
QUALIFICATION_FILES = ("qualification-zh-hant.png", "qualification-en-uk.png")
KEY_URL = "https://openrouter.ai/api/v1/key"


def outside_repository(path: Path) -> bool:
    resolved = path.expanduser().resolve()
    return resolved != REPO and REPO not in resolved.parents


def eval_kwargs(log_dir: Path) -> dict[str, Any]:
    """Keyword arguments for `inspect_ai.eval`; pure, so the logging rules are testable.

    The solver posts to OpenRouter itself, so Inspect's model is `mockllm/model` and its
    `generate` is never called; there is no second retry loop.
    """
    if not outside_repository(log_dir):
        raise SystemExit("--log-dir must be outside the repository")
    return {"model": "mockllm/model", "log_dir": str(log_dir), "log_images": False, "display": "none", "max_samples": 4}


def pinned_target(contract: dict[str, Any], label: str, reasoning: str = "off") -> RouteCModel:
    """The contract's pinned model for a run label and reasoning setting; refuses anything unpinned."""
    models = contract["route_c"].get("models") or {}
    pin = models.get(label)
    if not pin or pin.get("gate") != "passed":
        raise SystemExit(f"route C model {label!r} is not pinned with a passed catalogue gate in the contract")
    if reasoning not in (pin.get("reasoning_settings") or {}):
        raise SystemExit(f"reasoning {reasoning!r} is not a pinned setting for {label}")
    return RouteCModel(
        label=f"{label}-reasoning-{reasoning}",
        model=pin["slug"],
        endpoint=pin["endpoint"],
        provider_name=pin["provider_name"],
        reasoning=reasoning,
    )


def percentile(values: list[float], fraction: float) -> float | None:
    """Nearest-rank percentile; None for no values."""
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def call_stats(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Cost, latency and retries per call; unknown costs are counted, never zero."""
    costs = [Decimal(r["cost_usd"]) for r in rows if r.get("cost_usd") is not None]
    latencies = [float(r["latency_seconds"]) for r in rows if r.get("latency_seconds") is not None]
    return {
        "calls": len(rows),
        "attempts": sum(int(r.get("attempts") or 1) for r in rows),
        "retries": sum(int(r.get("retries") or 0) for r in rows),
        "reported_cost_usd": str(sum(costs, Decimal(0))),
        "unknown_cost_calls": sum(1 for r in rows if r.get("cost_usd") is None),
        "cost_median_usd": str(statistics.median(costs)) if costs else None,
        "cost_p90_usd": str(percentile([float(c) for c in costs], 0.9)) if costs else None,
        "cost_max_usd": str(max(costs)) if costs else None,
        "latency_p50_seconds": round(statistics.median(latencies), 2) if latencies else None,
        "latency_p90_seconds": round(percentile(latencies, 0.9) or 0, 2) if latencies else None,
        "latency_max_seconds": round(max(latencies), 2) if latencies else None,
    }


CREDITS_URL = "https://openrouter.ai/api/v1/credits"


def _get(url: str, key: str) -> dict[str, Any]:
    import openrouter_client

    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {key}"}, method="GET")
    try:
        with openrouter_client.OPENER.open(request, timeout=20) as response:
            return json.loads(response.read()).get("data") or {}
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as error:
        return {"error": type(error).__name__}


def key_credit(key: str) -> dict[str, Any]:
    """The key's remaining limit (`GET /api/v1/key`) and the account's balance (`GET /api/v1/credits`), both free.

    Both matter: on 17 October 2026 the key had $58 of its limit left while the account balance
    was $0.76, and OpenRouter answered HTTP 402. `available` is the smaller of the two. The key
    itself is never returned.
    """
    return credit_from(_get(KEY_URL, key), _get(CREDITS_URL, key))


def _number(value: Any) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool)


def credit_from(key_data: dict[str, Any], credits: dict[str, Any]) -> dict[str, Any]:
    """Pure: the credit summary from the two lookups. `available` is None (so the gate refuses) when
    either lookup errored or returned a non-numeric value; a key with an explicit null limit has no
    key-side cap, so only the account balance applies."""
    result: dict[str, Any] = {k: key_data.get(k) for k in ("limit", "limit_remaining", "usage", "is_free_tier")}
    total, used = credits.get("total_credits"), credits.get("total_usage")
    account_ok = "error" not in credits and _number(total) and _number(used)
    account = float(Decimal(str(total)) - Decimal(str(used))) if account_ok else None
    result["account_remaining"] = account
    if "error" in key_data or "error" in credits:
        result["lookup_error"] = key_data.get("error") or credits.get("error")
    unlimited_key = "error" not in key_data and "limit" in key_data and key_data.get("limit") is None
    key_ok = "error" not in key_data and (unlimited_key or (_number(key_data.get("limit")) and _number(key_data.get("limit_remaining"))))
    if account is None or not key_ok:
        result["available"] = None
    elif unlimited_key:
        result["available"] = account
    else:
        result["available"] = min(float(key_data["limit_remaining"]), account)
    return result


CREDIT_MARGIN_FRACTION = Decimal("0.25")
CREDIT_MARGIN_MIN_USD = Decimal("1")


def credit_gate(credit: dict[str, Any], projected_usd: Decimal, *, reserve_usd: Decimal = Decimal(0)) -> tuple[bool, Decimal]:
    """Whether an arm may start: available credit (the smaller of the key's remaining limit and the
    account balance) must cover its projected cost plus a margin (the larger of 25% and $1) plus any
    reserve. Unknown credit refuses. Returns (allowed, needed)."""
    needed = projected_usd + max(projected_usd * CREDIT_MARGIN_FRACTION, CREDIT_MARGIN_MIN_USD) + reserve_usd
    available = credit.get("available")
    if not isinstance(available, int | float) or isinstance(available, bool):
        return False, needed
    return Decimal(str(available)) >= needed, needed


def qualification_cases(folder: Path) -> list[dict[str, Any]]:
    loaded = []
    for name in QUALIFICATION_FILES:
        path = folder / name
        loaded.append(
            {
                "id": f"qualification:{name}",
                "input": {"kind": "image", "path": str(path)},
                "truth": {"requires_decline": False, "cells": [], "headers": [], "serving_size": "unknown", "servings_per_pack": "unknown"},
                "metadata": {
                    "corpus": "qualification",
                    "stratum": "qualification",
                    "split": "development",
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "fictional": True,
                },
            }
        )
    return loaded


def run(target: RouteCModel, loaded: list[dict[str, Any]], ledger: Path, log_dir: Path, name: str) -> Any:
    from inspect_ai import eval as inspect_eval

    from inspect_task import label_capture_route_c_development

    log_dir.mkdir(parents=True, exist_ok=True)
    cases_file = log_dir / f"{name}-cases.json"
    cases_file.write_text(json.dumps(loaded, ensure_ascii=False), encoding="utf-8")
    task = label_capture_route_c_development(
        cases_file=str(cases_file),
        ledger=str(ledger),
        model=target.model,
        endpoint=target.endpoint,
        provider_name=target.provider_name,
        label=target.label,
        enabled=True,
        reasoning=target.reasoning,
    )
    return inspect_eval(task, **eval_kwargs(log_dir))[0]


CALL_FIELDS = (
    "cost_usd",
    "attempts",
    "retries",
    "retry_causes",
    "unknown_cost_attempts",
    "latency_seconds",
    "returned_model",
    "returned_provider",
    "prompt_tokens",
    "completion_tokens",
    "reasoning_tokens",
)


def per_case_rows(log: Any, loaded: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id = {sample.id: sample for sample in log.samples or []}
    rows = []
    for case in loaded:
        sample = by_id.get(case["id"])
        meta = (sample.metadata or {}) if sample else {}
        score = ((sample.scores or {}).get("label_capture_scorer") if sample else None) or None
        call = meta.get("route_c") or {}
        candidate = {}
        if sample and sample.output and sample.output.completion:
            try:
                candidate = json.loads(sample.output.completion)
            except json.JSONDecodeError:
                candidate = {}
        rows.append(
            {
                "id": case["id"],
                "stratum": case["metadata"].get("stratum"),
                "attempted": sample is not None and bool(call),
                "error": str(sample.error.message)[:300] if sample is not None and sample.error else None,
                "failed": meta.get("route_c_failed"),
                "declined": bool(candidate.get("declined")),
                "decline_reasons": candidate.get("decline_reasons", []),
                "would_mark_ready": bool(candidate.get("would_mark_ready")),
                "warnings": candidate.get("warnings", []),
                "score": score.metadata if score is not None else None,
                **{k: call.get(k) for k in CALL_FIELDS},
            }
        )
    return rows


def summarise(target: RouteCModel, loaded: list[dict[str, Any]], rows: list[dict[str, Any]], log: Any) -> dict[str, Any]:
    import run_route_b
    import score as scoring

    scored = [(case, row) for case, row in zip(loaded, rows, strict=True) if row["score"] is not None]
    summary = (
        run_route_b.summarise(
            [c for c, _ in scored],
            [{**r["score"], "candidate_decline_reasons": r["decline_reasons"]} for _, r in scored],
            scoring.load_thresholds(),
        )
        if scored
        else {}
    )
    strata: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        strata[row["stratum"]].append(row)
    calls = {
        name: {
            **call_stats([r for r in group if r["attempted"]]),
            "cases": len(group),
            "unattempted": [r["id"] for r in group if not r["attempted"]],
            "failed": sum(1 for r in group if r["failed"]),
            "failure_reasons": dict(Counter(reason.split(":")[0] for r in group for reason in (r["failed"] or []))),
        }
        for name, group in sorted(strata.items())
    }
    return {
        "route": "C",
        "split": "development",
        "model": {"label": target.label, "slug": target.model, "endpoint": target.endpoint, "reasoning": target.reasoning},
        "inspect_status": log.status,
        "inspect_error": str(log.error.message)[:300] if log.error else None,
        "inspect_log": Path(log.location).name,
        "calls_overall": call_stats([r for r in rows if r["attempted"]]),
        "calls_by_stratum": calls,
        "returned_models": dict(Counter(r["returned_model"] for r in rows if r["attempted"])),
        "returned_providers": dict(Counter(r["returned_provider"] for r in rows if r["attempted"])),
        **summary,
        "per_case": [
            {k: v for k, v in r.items() if k != "score"}
            | {"table_exact": (r["score"] or {}).get("tables_exact"), "false_ready": (r["score"] or {}).get("false_ready")}
            for r in rows
        ],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--label", required=True, help="run label pinned in the contract's route_c.models (luna, grok, sol, gemini, opus)")
    parser.add_argument("--reasoning", choices=("off", "on"), required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--log-dir", type=Path, required=True)
    parser.add_argument("--qualification-dir", type=Path, required=True, help="folder with the two rendered fictional labels")
    parser.add_argument("--taiwan-root", type=Path, default=Path.home() / "WHR-label-eval-private" / "off-taiwan-v1")
    parser.add_argument("--uk-workspace", type=Path, required=True)
    parser.add_argument("--env-file", type=Path, help="dotenv file to take OPENROUTER_API_KEY from (only that variable, into this process)")
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--projected-cost-usd", type=float, required=True, help="this arm's projected cost, from measured per-call costs")
    parser.add_argument(
        "--reserve-usd",
        type=float,
        default=0.0,
        help="credit that must stay available after the arm (for example the $40 sealed reservation)",
    )
    parser.add_argument("--qualification-only", action="store_true")
    args = parser.parse_args(argv)

    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract["route_c"].get("enabled") is not True:
        raise SystemExit("route C is disabled in the contract; no call is made")
    target = pinned_target(contract, args.label, args.reasoning)
    for path in (args.log_dir, args.ledger):
        if not outside_repository(path):
            raise SystemExit(f"refusing a path inside the repository: {path}")
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        from draft_untouched_truth import key_from_env_file

        key = key_from_env_file(args.env_file) if args.env_file else None
        if not key:
            raise SystemExit("OPENROUTER_API_KEY is not set")

    import openrouter_client
    from inspect_task import configure_route_c_transport

    credit = key_credit(key)
    ledger = json.loads(args.ledger.read_text(encoding="utf-8"))
    could_spend = Decimal(str(contract["route_c"]["total_stop_usd"])) - Decimal(ledger["reported_spend_usd"])
    available = credit.get("available")
    credit["warning"] = (
        f"available credit {available} is below the {could_spend} the run could still spend under the total stop"
        if isinstance(available, int | float) and Decimal(str(available)) < could_spend
        else None
    )
    allowed, needed = credit_gate(credit, Decimal(str(args.projected_cost_usd)), reserve_usd=Decimal(str(args.reserve_usd)))
    credit["gate"] = {"projected_cost_usd": str(args.projected_cost_usd), "reserve_usd": str(args.reserve_usd), "needed_usd": str(needed)}
    print(json.dumps({"key_credit": credit}))
    if not allowed:
        raise SystemExit(
            f"refusing to start: available credit {available} is below the {needed} this arm needs (projection, margin, reserve)"
        )
    configure_route_c_transport(
        openrouter_client.http_post(key, "WeeklyHealthReport label evaluation route C"),
        lambda generation: openrouter_client.generation_cost(key, generation),
    )

    qualifying = qualification_cases(args.qualification_dir)
    log = run(target, qualifying, args.ledger, args.log_dir, "qualification")
    rows = per_case_rows(log, qualifying)
    passed = all(r["attempted"] and not r["failed"] and not r["error"] and not r["declined"] for r in rows)
    result: dict[str, Any] = {
        "key_credit": credit,
        "qualification": {
            "passed": passed,
            "cases": [
                {
                    k: r[k]
                    for k in (
                        "id",
                        "failed",
                        "error",
                        "declined",
                        "cost_usd",
                        "attempts",
                        "latency_seconds",
                        "returned_model",
                        "returned_provider",
                    )
                }
                for r in rows
            ],
        },
    }
    print(json.dumps(result["qualification"], ensure_ascii=False))
    if passed and not args.qualification_only:
        import run_route_b

        loaded, notes = run_route_b.build_cases(args.taiwan_root, args.uk_workspace)
        for case in loaded:
            if case["metadata"].get("corpus") == "owner" and case["metadata"].get("consent_send_to_openrouter") is not True:
                raise SystemExit("the muesli photo has no send_to_openrouter consent")
        log = run(target, loaded, args.ledger, args.log_dir, "development")
        rows = per_case_rows(log, loaded)
        result.update(summarise(target, loaded, rows, log))
        result["notes"] = notes
    if args.summary:
        args.summary.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0 if passed else 3


if __name__ == "__main__":
    sys.exit(main())
