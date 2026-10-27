#!/usr/bin/env python3
"""Score the E13 qualification run against its bars (docs/label-photo-ai-prefill-v1.md E13, 17.21).

Offline: reads the runner's private records (`Tools/LabelPhotoE13`, `e13-records.jsonl` outside
the repository) and the pinned truth, and writes counts and case ids only. No model answer, image or
key is written.

Bars, on the approved route (`google/gemini-4-argon` on `google-vertex/us`, E3 preparation):

- zero identity mismatches: every reply names the requested model (or a pinned dated slug, which
  this run reports for pinning) and the route's provider;
- median cost per photo at most $0.02 (each attempt's reported cost, or W when none was reported);
- p90 latency per photo at most 20 s (the whole tap, retries included);
- tables needing no edit at least 80% of usable tables, in the assisted view of the
  correction-effort analysis (`correction_effort.py`), development and untouched separately;
- silent-error tables reported case by case.

Answers are mapped with the evaluation's `route_c_mapping.map_wire`, which the app's wire mapping
matches (contract test 1, mapping parity). The refills have no truth yet; they count for identity,
cost, latency and declines only.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from decimal import Decimal
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import correction_effort  # noqa: E402
import decline_gate  # noqa: E402
import route_c_mapping  # noqa: E402

MODEL = "google/gemini-4-argon"
PROVIDER = "google"
TRUTH = {
    "development": HERE / "fixtures" / "ground-truth-off-taiwan-development-v1.json",
    "untouched": HERE / "fixtures" / "ground-truth-off-taiwan-untouched-v1.json",
}
BARS = {"median_cost_usd": Decimal("0.02"), "p90_latency_s": 20.0, "no_edit_share": 0.80}


def nearest_rank(values: list[float], share: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(share * len(ordered)) - 1)]


def identity(records: list[dict[str, Any]], pinned: set[str]) -> dict[str, Any]:
    """Every reply's model and provider, from the transport's per-attempt record."""
    observed: dict[str, int] = {}
    mismatches = []
    for record in records:
        for attempt in record.get("attempts", []):
            model, provider = attempt.get("model"), attempt.get("provider")
            if model is None and provider is None:
                continue
            observed[f"{model} @ {provider}"] = observed.get(f"{model} @ {provider}", 0) + 1
            normalised = (provider or "").strip().lower().replace(" ", "-")
            if (model != MODEL and model not in pinned) or normalised != PROVIDER:
                mismatches.append({"id": record["id"], "model": model, "provider": provider})
        if record.get("failure") in ("wrongModel", "wrongProvider"):
            mismatches.append({"id": record["id"], "failure": record["failure"]})
    dated = sorted({key.split(" @ ")[0] for key in observed} - {MODEL, "None"})
    return {"observed": observed, "dated_slugs": dated, "mismatches": mismatches}


def failure_counts(rows: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in rows:
        if row.get("failure"):
            counts[row["failure"]] = counts.get(row["failure"], 0) + 1
    return dict(sorted(counts.items()))


def candidate(record: dict[str, Any]) -> dict[str, Any] | None:
    if record.get("outcome") != "answered" or not record.get("wireText"):
        return None
    return route_c_mapping.map_wire(json.loads(record["wireText"]), record["sourceSHA256"])


def effort(records: list[dict[str, Any]], split: str) -> dict[str, Any]:
    truths = {r["case_id"]: r for r in json.loads(TRUTH[split].read_text(encoding="utf-8"))["records"]}
    rows = []
    for record in records:
        truth = truths.get(record["id"])
        if truth is None or not correction_effort.usable(truth):
            continue
        rows.append({"id": record["id"], "truth": truth, "label_format": decline_gate.TAIWAN, "candidate": candidate(record)})
    summary = correction_effort.analyse(rows)["assisted"]["summary"]
    usable = summary["usable_tables"]
    no_edit = summary["distribution"]["0"]["tables"]
    return {
        "usable_tables": usable,
        "no_edit_tables": no_edit,
        "no_edit_share": round(no_edit / usable, 4) if usable else None,
        "whole_table_by_hand": summary["hard_declines"],
        "silent_error_tables": summary["silent_error_tables"],
        "silent_omission_tables": summary["silent_omission_tables"],
        "median_edits_per_prefilled_table": summary["median_edits_per_prefilled_table"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--records", type=Path, default=Path.home() / "WHR-label-eval-private" / "runs" / "e13-v1" / "e13-records.jsonl")
    parser.add_argument("--pinned", action="append", default=[], help="a dated slug already pinned for the model")
    parser.add_argument("--out", type=Path, required=True, help="counts and case ids only (may be in the repository)")
    parser.add_argument(
        "--overlay",
        type=Path,
        help="a partial re-run's records (runner --only/--records): each replaces the full run's record with the same id",
    )
    args = parser.parse_args(argv)
    records = [json.loads(line) for line in args.records.read_text(encoding="utf-8").splitlines() if line.strip()]
    if args.overlay:
        rerun = {r["id"]: r for r in (json.loads(line) for line in args.overlay.read_text(encoding="utf-8").splitlines() if line.strip())}
        if set(rerun) - {r["id"] for r in records}:
            raise SystemExit("the overlay names a case the full run does not have")
        records = [rerun.get(r["id"], r) for r in records]
    sent = [r for r in records if r.get("attempts")]
    costs = [Decimal(r["chargedUSD"]) for r in sent]
    latencies = [float(r["tapSeconds"]) for r in sent if r.get("tapSeconds") is not None]
    ident = identity(records, set(args.pinned))
    by_split = {split: [r for r in records if r["split"] == split] for split in ("development", "untouched", "e13_refill")}
    scored = {split: effort(by_split[split], split) for split in ("development", "untouched")}
    median_cost = statistics.median(costs) if costs else None
    p90 = nearest_rank(latencies, 0.9)
    result = {
        "route": f"{MODEL} on google-vertex/us",
        "photos": {split: len(rows) for split, rows in by_split.items()},
        "not_sent": {"prepare_refused": sorted(r["id"] for r in records if r.get("prepareError"))},
        "outcomes": {
            split: {
                "answered": sum(r["outcome"] == "answered" for r in rows),
                "failed": failure_counts(rows),
            }
            for split, rows in by_split.items()
        },
        "attempts": {
            "total": sum(len(r.get("attempts", [])) for r in records),
            "retried_photos": sorted(r["id"] for r in records if len(r.get("attempts", [])) > 1),
        },
        "prompt_tokens_max": max((a.get("promptTokens") or 0 for r in records for a in r.get("attempts", [])), default=None),
        "truncated": sorted(r["id"] for r in records if r.get("failure") == "truncated"),
        "identity": ident,
        "cost_usd": {
            "total": str(sum(costs, Decimal(0))),
            "median": str(median_cost) if median_cost is not None else None,
            "max": str(max(costs)) if costs else None,
        },
        "latency_s": {"p50": nearest_rank(latencies, 0.5), "p90": p90, "max": max(latencies) if latencies else None},
        "tables": scored,
        "bars": {
            "zero_identity_mismatches": not ident["mismatches"],
            "median_cost": median_cost is not None and median_cost <= BARS["median_cost_usd"],
            "p90_latency": p90 is not None and p90 <= BARS["p90_latency_s"],
            "no_edit_untouched": (scored["untouched"]["no_edit_share"] or 0) >= BARS["no_edit_share"],
            "no_edit_development": (scored["development"]["no_edit_share"] or 0) >= BARS["no_edit_share"],
        },
    }
    args.out.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result["bars"]), json.dumps(result["cost_usd"]), json.dumps(result["latency_s"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
