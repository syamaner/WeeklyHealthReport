#!/usr/bin/env python3
"""Run route C on DEVELOPMENT photos through Inspect, under the logging rules.

Route C runs only while the contract sets `route_c.enabled` true, and only for a model
pinned in `route_c.models` (slug, endpoint, returned provider name and reasoning effort,
recorded from the catalogue on the run day); the runner refuses any other value. When it
runs:

- the Inspect log directory must be outside the repository (a `.eval` log holds model
  requests and responses), and `log_images=False`, so image bytes are never written into
  the log;
- `GenerateConfig.extra_headers` is left empty, and the solver refuses any configured or
  logged header that looks like a credential; the key is read from the environment, or
  that one variable from `--env-file` into this process only, and is never printed,
  logged or written;
- the model is `openrouter/<slug>` with the pinned provider block (one endpoint, no
  fallbacks, ZDR, data collection denied), no streaming, and the persistent spend ledger;
- two fictional qualification labels go first (plan section 8.2); a model that does not
  return an accepted, schema-valid answer for both is not sent any real image;
- development photos only: the Taiwan development photos, the UK development review
  images and the muesli photo (only with `send_to_openrouter` consent). Nothing here reads
  a sealed folder, untouched truth or drafts.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import sys
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import openrouter_route  # noqa: E402
from openrouter_route import RouteCModel  # noqa: E402

CONTRACT = HERE / "frozen-contract-v1.json"
QUALIFICATION_FILES = ("qualification-zh-hant.png", "qualification-en-uk.png")


def outside_repository(path: Path) -> bool:
    resolved = path.expanduser().resolve()
    return resolved != REPO and REPO not in resolved.parents


def eval_kwargs(target: RouteCModel, log_dir: Path) -> dict[str, Any]:
    """Keyword arguments for `inspect_ai.eval`; pure, so the logging rules are testable."""
    if not outside_repository(log_dir):
        raise SystemExit("--log-dir must be outside the repository")
    return {
        "model": f"openrouter/{target.model}",
        "model_args": openrouter_route.model_args(target),
        "log_dir": str(log_dir),
        "log_images": False,
        "display": "none",
        "max_samples": 1,
    }


def pinned_target(contract: dict[str, Any], label: str) -> RouteCModel:
    """The contract's pinned model for a run label; refuses an unknown or unpinned label."""
    models = contract["route_c"].get("models") or {}
    pin = models.get(label)
    if not pin or pin.get("gate") != "passed":
        raise SystemExit(f"route C model {label!r} is not pinned with a passed catalogue gate in the contract")
    return RouteCModel(
        label=label,
        model=pin["slug"],
        endpoint=pin["endpoint"],
        provider_name=pin["provider_name"],
        reasoning_effort=pin.get("reasoning_effort"),
    )


def percentile(values: list[float], fraction: float) -> float | None:
    """Nearest-rank percentile; None for no values."""
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def call_stats(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Cost and latency per call from the solver's metadata; unknown costs are counted, never zero."""
    costs = [Decimal(r["cost_usd"]) for r in rows if r.get("cost_usd") is not None]
    latencies = [float(r["latency_seconds"]) for r in rows if r.get("latency_seconds") is not None]
    return {
        "calls": len(rows),
        "reported_cost_usd": str(sum(costs, Decimal(0))),
        "unknown_cost_calls": sum(1 for r in rows if r.get("cost_usd") is None),
        "cost_median_usd": str(statistics.median(costs)) if costs else None,
        "cost_p90_usd": str(percentile([float(c) for c in costs], 0.9)) if costs else None,
        "cost_max_usd": str(max(costs)) if costs else None,
        "latency_p50_seconds": round(statistics.median(latencies), 2) if latencies else None,
        "latency_p90_seconds": round(percentile(latencies, 0.9) or 0, 2) if latencies else None,
        "latency_max_seconds": round(max(latencies), 2) if latencies else None,
    }


def qualification_cases(folder: Path) -> list[dict[str, Any]]:
    import hashlib

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


def run(target: RouteCModel, loaded: list[dict[str, Any]], ledger: Path, log_dir: Path, name: str) -> tuple[Any, Path]:
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
        reasoning_effort=target.reasoning_effort,
    )
    return inspect_eval(task, **eval_kwargs(target, log_dir))[0], cases_file


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
                **{
                    k: call.get(k)
                    for k in ("cost_usd", "latency_seconds", "returned_model", "returned_provider", "prompt_tokens", "completion_tokens")
                },
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
        "model": {"label": target.label, "slug": target.model, "endpoint": target.endpoint, "reasoning_effort": target.reasoning_effort},
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
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--log-dir", type=Path, required=True)
    parser.add_argument("--qualification-dir", type=Path, required=True, help="folder with the two rendered fictional labels")
    parser.add_argument("--taiwan-root", type=Path, default=Path.home() / "WHR-label-eval-private" / "off-taiwan-v1")
    parser.add_argument("--uk-workspace", type=Path, required=True)
    parser.add_argument("--env-file", type=Path, help="dotenv file to take OPENROUTER_API_KEY from (only that variable, into this process)")
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--qualification-only", action="store_true")
    args = parser.parse_args(argv)

    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract["route_c"].get("enabled") is not True:
        raise SystemExit("route C is disabled in the contract; no call is made")
    target = pinned_target(contract, args.label)
    for path in (args.log_dir, args.ledger):
        if not outside_repository(path):
            raise SystemExit(f"refusing a path inside the repository: {path}")
    if not os.environ.get("OPENROUTER_API_KEY"):
        from draft_untouched_truth import key_from_env_file

        key = key_from_env_file(args.env_file) if args.env_file else None
        if not key:
            raise SystemExit("OPENROUTER_API_KEY is not set")
        os.environ["OPENROUTER_API_KEY"] = key  # this process only; never printed or written

    qualifying = qualification_cases(args.qualification_dir)
    log, _ = run(target, qualifying, args.ledger, args.log_dir, "qualification")
    rows = per_case_rows(log, qualifying)
    passed = all(r["attempted"] and not r["failed"] and not r["error"] and not r["declined"] for r in rows)
    result: dict[str, Any] = {
        "qualification": {
            "passed": passed,
            "cases": [
                {
                    k: r[k]
                    for k in ("id", "failed", "error", "declined", "cost_usd", "latency_seconds", "returned_model", "returned_provider")
                }
                for r in rows
            ],
        }
    }
    print(json.dumps(result["qualification"], ensure_ascii=False))
    if passed and not args.qualification_only:
        import run_route_b

        loaded, notes = run_route_b.build_cases(args.taiwan_root, args.uk_workspace)
        for case in loaded:
            if case["metadata"].get("corpus") == "owner" and case["metadata"].get("consent_send_to_openrouter") is not True:
                raise SystemExit("the muesli photo has no send_to_openrouter consent")
        log, _ = run(target, loaded, args.ledger, args.log_dir, "development")
        rows = per_case_rows(log, loaded)
        result.update(summarise(target, loaded, rows, log))
        result["notes"] = notes
    if args.summary:
        args.summary.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0 if passed else 3


if __name__ == "__main__":
    sys.exit(main())
