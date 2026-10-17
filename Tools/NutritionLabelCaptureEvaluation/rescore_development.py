"""Re-score saved DEVELOPMENT outputs with and without the decline gate (phase 4, #255).

Offline: no model, provider or Vision call. It reads the saved Inspect logs outside the
repository (route A pasted text, route B photos, the ten route C arms), takes each
candidate as the route produced it, applies `decline_gate.apply_gate` with the label
format the case declares, and scores both versions with the same `score.score_case`.
Everything uses the code at the current commit: route C candidates are re-mapped from the
saved wire answer with the current mapping, and saved UK photo truths are brought to the
current convention (amendment T1). Only development cases are read; any other split stops
the run. The summary written to `results/` holds aggregate counts and case ids only, never
a model answer.

    .venv/bin/python rescore_development.py --runs ~/WHR-label-eval-private/runs \
        --out results/amendments-rescore-v1.json

`results/decline-gate-rescore-v1.json` was written by this script at commit f313578c,
before the owner amendments of 18 October 2026; `results/amendments-rescore-v1.json` after.
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

import cases as case_loading
import decline_gate
import route_c_mapping
import score as scoring

HERE = Path(__file__).resolve().parent
ROUTE_C_ARMS = ("luna-off", "luna-on", "luna_pro-off", "luna_pro-on", "grok-on", "gemini-on", "sol-on", "sol_pro-on", "opus-on", "fable-on")
SUMMARY_FIELDS = (
    "strict_cells",
    "binding",
    "unit_and_basis",
    "full_table",
    "serving_conversions",
    "servings_per_pack",
    "bounds",
    "correct_decline",
    "false_ready",
)


def _candidates(log_path: Path) -> dict[str, dict[str, Any] | None]:
    from inspect_ai.log import read_eval_log

    log = read_eval_log(str(log_path))
    found: dict[str, dict[str, Any] | None] = {}
    for sample in log.samples or []:
        candidate = None
        if sample.output and sample.output.completion:
            try:
                candidate = json.loads(sample.output.completion)
            except json.JSONDecodeError:
                candidate = None
        answer = (sample.metadata or {}).get("route_c_answer")
        if candidate is not None and answer:
            # Route C is re-mapped from the saved wire answer with the current mapping
            # (amendments M1 to M3); the answer was schema-valid when it was first mapped.
            candidate = route_c_mapping.map_wire(json.loads(answer), str(candidate.get("input_sha256")))
        found[str(sample.id)] = candidate
    return found


def current_truth(truth: dict[str, Any], metadata: dict[str, Any]) -> dict[str, Any]:
    """The saved truth under the current convention: amendment T1 for the UK photo stratum."""
    if metadata.get("corpus") == "uk_v2_development_review":
        return case_loading.apply_uk_truth_convention_t1(truth)[0]
    return truth


def load_arm(log_path: Path, cases: list[dict[str, Any]]) -> list[dict[str, Any]]:
    outputs = _candidates(log_path)
    rows = []
    for case in cases:
        metadata = case["metadata"]
        if metadata.get("split") != "development":
            raise SystemExit(f"{case['id']} is not a development case; refusing")
        rows.append(
            {
                "id": case["id"],
                "stratum": metadata.get("stratum") or metadata.get("corpus"),
                "label_format": decline_gate.format_for_case(metadata),
                "truth": current_truth(case["truth"], metadata),
                "candidate": outputs.get(case["id"]),
            }
        )
    return rows


def _summary(results: list[dict[str, Any]], thresholds: dict[str, float]) -> dict[str, Any]:
    aggregated = scoring.aggregate(results, thresholds)
    metrics = aggregated["metrics"]
    out: dict[str, Any] = {}
    for name in SUMMARY_FIELDS:
        metric = metrics[name]
        out[name] = (
            {"count": metric["count"], "verdict": metric["verdict"]}
            if "count" in metric
            else {"numerator": metric["numerator"], "denominator": metric["denominator"], "verdict": metric["verdict"]}
        )
    out["false_declines"] = aggregated["false_declines"]
    out["would_mark_ready_after_arithmetic"] = aggregated["would_mark_ready_after_arithmetic"]
    out["cases"] = aggregated["cases"]
    return out


def rescore(rows: list[dict[str, Any]], thresholds: dict[str, float]) -> dict[str, Any]:
    before: dict[str, list[dict[str, Any]]] = defaultdict(list)
    after: dict[str, list[dict[str, Any]]] = defaultdict(list)
    changes: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        gated, report = decline_gate.apply_gate(row["candidate"], row["label_format"])
        old = scoring.score_case(row["candidate"], row["truth"])
        new = scoring.score_case(gated, row["truth"])
        before[row["stratum"]].append(old)
        after[row["stratum"]].append(new)
        if report["declines"] or (report["blocks"] and gated is not row["candidate"]):
            changes[row["stratum"]].append(
                {
                    "id": row["id"],
                    "requires_decline": bool(row["truth"].get("requires_decline")),
                    "gate_declines": report["declines"],
                    "gate_blocks": report["blocks"] if not report["declines"] else [],
                    "was_false_ready": old["false_ready"],
                    "was_table_exact": old["tables_exact"],
                }
            )
    strata = sorted(before)
    return {
        stratum: {
            "before": _summary(before[stratum], thresholds),
            "after": _summary(after[stratum], thresholds),
            "gate_changes": changes[stratum],
        }
        for stratum in strata
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runs", type=Path, required=True, help="the private runs folder (outside the repository)")
    parser.add_argument("--route-a-log-dir", default="inspect-route-a-p3")
    parser.add_argument("--route-b-run-dir", default="route-b-dev/phase3")
    parser.add_argument("--route-c-dir", default="route-c-dev")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--t1-log", type=Path, help="write every UK truth record amendment T1 changes (case ids, row ids, parents)")
    args = parser.parse_args(argv)
    thresholds = scoring.load_thresholds()
    arms: dict[str, Any] = {}

    text_cases = [
        json.loads(line) for line in (HERE / "synthetic" / "development-cases-v1.jsonl").read_text(encoding="utf-8").splitlines() if line
    ]
    (a_log,) = sorted((args.runs / args.route_a_log_dir).glob("*.eval"))
    arms["A"] = {"log": a_log.name, "strata": rescore(load_arm(a_log, text_cases), thresholds)}

    b_dir = args.runs / args.route_b_run_dir
    (b_log,) = sorted(b_dir.glob("*.eval"))
    b_cases = json.loads((b_dir / "route-b-development-cases.json").read_text(encoding="utf-8"))
    arms["B"] = {"log": b_log.name, "strata": rescore(load_arm(b_log, b_cases), thresholds)}

    for arm in ROUTE_C_ARMS:
        folder = args.runs / args.route_c_dir
        summary = json.loads((folder / f"{arm}-summary.json").read_text(encoding="utf-8"))
        log = folder / arm / summary["inspect_log"]
        cases = json.loads((folder / arm / "development-cases.json").read_text(encoding="utf-8"))
        arms[f"C:{arm}"] = {"log": log.name, "strata": rescore(load_arm(log, cases), thresholds)}

    if args.t1_log is not None:
        folder = args.runs / args.route_c_dir
        uk = [
            c
            for c in json.loads((folder / ROUTE_C_ARMS[0] / "development-cases.json").read_text(encoding="utf-8"))
            if c["metadata"].get("corpus") == "uk_v2_development_review"
        ]
        changes = [change for case in uk for change in case_loading.apply_uk_truth_convention_t1(case["truth"])[1]]
        args.t1_log.write_text(
            json.dumps(
                {
                    "amendment": "T1 (owner, 18 October 2026)",
                    "scope": "UK v2 development review truth as loaded by cases.load_uk_development_review; the frozen review is unchanged",
                    "records": len(uk),
                    "records_changed": len({c["case_id"] for c in changes}),
                    "changes": changes,
                },
                ensure_ascii=False,
                indent=1,
            )
            + "\n",
            encoding="utf-8",
        )

    result = {
        "gate_version": decline_gate.GATE_VERSION,
        "split": "development",
        "note": "Offline re-score of saved development outputs; no API call. Counts and case ids only.",
        "arms": arms,
    }
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    for name, arm in arms.items():
        for stratum, block in arm["strata"].items():
            b, a = block["before"], block["after"]

            def show(m: dict[str, Any]) -> str:
                return str(m["count"]) if "count" in m else f"{m['numerator']}/{m['denominator']}"

            print(
                f"{name:16} {stratum:16} decline {show(b['correct_decline']):>6} -> {show(a['correct_decline']):>6}  "
                f"false-ready {show(b['false_ready']):>3} -> {show(a['false_ready']):>3}  "
                f"false-declines {b['false_declines']:>3} -> {a['false_declines']:>3}  "
                f"full {show(b['full_table']):>6} -> {show(a['full_table']):>6}  "
                f"ready {b['would_mark_ready_after_arithmetic']:>3} -> {a['would_mark_ready_after_arithmetic']:>3}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
