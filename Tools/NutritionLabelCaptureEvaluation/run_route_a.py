#!/usr/bin/env python3
"""Run route A on the DEVELOPMENT pasted-text cases through Inspect and summarise.

Builds nothing itself: pass the built `NutritionLabelTextParse` binary. The Inspect
`.eval` log goes to `--log-dir` (outside the repository); only the summary is written to
`results/`. Route A makes no model or network call (Inspect's `mockllm/model` is the
nominal model; the solver never calls generate).

`--direct` skips Inspect and scores with the same pure functions, for quick iteration.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import arithmetic  # noqa: E402
import cases as case_loading  # noqa: E402
import score as scoring  # noqa: E402


def run_parser(binary: Path, loaded: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    payload = json.dumps([{"id": c["id"], "text": c["input"]["text"]} for c in loaded])
    output = subprocess.run([str(binary)], input=payload.encode("utf-8"), capture_output=True, check=True).stdout
    return {item["id"]: item for item in json.loads(output)}


def summarise(per_case: list[dict[str, Any]], thresholds: dict[str, float], loaded: list[dict[str, Any]]) -> dict[str, Any]:
    by_corpus: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for case, result in zip(loaded, per_case, strict=True):
        by_corpus[case["metadata"]["corpus"]].append(result)
    truths = [c["truth"] for c in loaded if not c["truth"]["requires_decline"]]
    mutation = arithmetic.mutation_detection(truths)
    overall = scoring.aggregate(per_case, thresholds)
    detected, applicable = mutation["overall"]["detected"], mutation["overall"]["applicable"]
    overall["metrics"]["arithmetic_mutation_detection"] = {
        "numerator": detected,
        "denominator": applicable,
        "rate": round(detected / applicable, 4) if applicable else None,
        "bar": thresholds["arithmetic_detection_minimum"],
        "verdict": ("pass" if detected == applicable else "fail") if applicable else "no_denominator",
        "by_mutation": {k: v for k, v in mutation.items() if k != "overall"},
    }
    return {
        "overall": overall,
        "by_corpus": {name: scoring.aggregate(results, thresholds) for name, results in sorted(by_corpus.items())},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parser-binary", type=Path, required=True)
    parser.add_argument("--dataset", type=Path, default=HERE / "synthetic" / "development-cases-v1.jsonl")
    parser.add_argument("--log-dir", type=Path, help="Inspect log directory outside the repository")
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--direct", action="store_true", help="score without Inspect (iteration only)")
    parser.add_argument("--show-failures", type=int, default=0)
    args = parser.parse_args()

    loaded = case_loading.load_development_text(args.dataset)
    thresholds = scoring.load_thresholds()
    eval_log = None
    per_case: list[dict[str, Any]] = []
    if args.direct:
        outputs = run_parser(args.parser_binary, loaded)
        per_case = [scoring.score_case(outputs[c["id"]]["candidate"], c["truth"]) for c in loaded]
        parser_version = next(iter(outputs.values()))["parser_version"]
    else:
        from inspect_ai import eval as inspect_eval

        from inspect_task import label_capture_development_text

        if not args.log_dir or HERE.parents[1] in args.log_dir.resolve().parents:
            raise SystemExit("--log-dir must be outside the repository")
        logs = inspect_eval(
            label_capture_development_text(parser_binary=str(args.parser_binary), dataset=str(args.dataset)),
            model="mockllm/model",
            log_dir=str(args.log_dir),
            display="none",
            max_samples=8,
        )
        log = logs[0]
        if log.status != "success":
            raise SystemExit(f"Inspect run status {log.status}: {log.error}")
        by_id = {sample.id: sample for sample in log.samples or []}
        per_case = []
        for case in loaded:
            scores = by_id[case["id"]].scores or {}
            metadata = scores["label_capture_scorer"].metadata if "label_capture_scorer" in scores else None
            if metadata is None:
                raise SystemExit(f"{case['id']} has no label_capture_scorer result in the Inspect log")
            per_case.append(metadata)
        parser_version = by_id[loaded[0]["id"]].metadata.get("parser_version")
        results = log.results.scores if log.results else []
        eval_log = {
            "location": Path(log.location).name,
            "inspect_metrics": {name: round(float(m.value), 4) for score in results for name, m in score.metrics.items()},
        }
    summary = summarise(per_case, thresholds, loaded)
    summary.update(
        {
            "route": "A",
            "split": "development",
            "dataset_sha256": case_loading.sha256_file(args.dataset),
            "parser_version": parser_version,
            "cases": len(loaded),
            "inspect": eval_log,
            "declines": dict(
                Counter(r for res, c in zip(per_case, loaded, strict=True) for r in ([] if not res["declined"] else ["declined"]))
            ),
        }
    )
    if args.show_failures:
        shown = 0
        for case, result in zip(loaded, per_case, strict=True):
            good = result["declines_correct"] if case["truth"]["requires_decline"] else result["tables_exact"]
            if not good and shown < args.show_failures:
                shown += 1
                print(
                    "FAIL",
                    case["id"],
                    {
                        k: result[k]
                        for k in (
                            "declined",
                            "cells_exact",
                            "product_cells",
                            "extra_cells",
                            "conversions_exact",
                            "conversions",
                            "servings_per_pack_exact",
                        )
                    },
                )
    text = json.dumps(summary, indent=2, ensure_ascii=False)
    if args.summary:
        args.summary.write_text(text + "\n", encoding="utf-8")
    print(json.dumps({k: v.get("rate", v.get("count")) for k, v in summary["overall"]["metrics"].items()}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
