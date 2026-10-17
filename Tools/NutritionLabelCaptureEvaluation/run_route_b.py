#!/usr/bin/env python3
"""Run route B on DEVELOPMENT photos through Inspect and summarise per stratum.

Strata: `taiwan_zh_hant` (the 22 Open Food Facts Taiwan development photos less the two
excluded English-only ones), `uk_en` (the 40 exposed v2 public development review images,
less any owner exclusion) and `muesli` (the owner photo, only with `local_routes`
consent). Nothing here reads a sealed folder: the Taiwan loader reads `development/` only
and the solver refuses any non-development case or any path under `sealed/`.

Route B makes no network call (Inspect's `mockllm/model` is the nominal model; the solver
never calls generate). The Inspect `.eval` log, which holds the recognised lines and the
serialised text, goes to `--log-dir` outside the repository; only aggregate counts and
per-case outcome flags are written to `results/`.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import arithmetic  # noqa: E402
import cases as case_loading  # noqa: E402
import score as scoring  # noqa: E402

PRIVATE = Path.home() / "WHR-label-eval-private"
TAIWAN_MANIFEST = HERE / "fixtures" / "off-taiwan-manifest-v1.json"
TAIWAN_TRUTH = HERE / "fixtures" / "ground-truth-off-taiwan-development-v1.json"
UK_REVIEW = HERE.parents[1] / "Tools" / "FoodOCREvaluation" / "review_workspace" / "v2_public_development"
MUESLI_MASTER = PRIVATE / "owner" / "masters" / "b360d49e8934b4d2-stripped.jpg"
MUESLI_CONSENT = PRIVATE / "owner" / "consent" / "4c4a2d790ebe85a3.json"


def outside_repository(path: Path) -> bool:
    resolved = path.expanduser().resolve()
    return HERE.parents[1] not in resolved.parents and resolved != HERE.parents[1]


def muesli_truth() -> dict[str, Any]:
    typed = next(
        c
        for c in case_loading.load_development_text(HERE / "synthetic" / "development-cases-v1.jsonl")
        if c["id"] == "owner:muesli-6-grain:typed"
    )
    return typed["truth"]


def build_cases(taiwan_root: Path, uk_workspace: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    notes: dict[str, Any] = {}
    taiwan = case_loading.load_development_photos(TAIWAN_MANIFEST, taiwan_root, TAIWAN_TRUTH)
    for case in taiwan:
        case["metadata"]["stratum"] = "taiwan_zh_hant"
        if case["truth"] is None:
            raise SystemExit(f"{case['id']} has no development truth")
    manifest = json.loads(TAIWAN_MANIFEST.read_text(encoding="utf-8"))
    notes["taiwan_excluded"] = [
        {"order": p["order"], "barcode13": p["barcode13"], "reason": p.get("exclusion_reason") or p.get("excluded_reason") or "excluded"}
        for p in manifest["photos"]
        if p["split"] == "development" and p.get("excluded")
    ]
    uk, uk_exclusions = case_loading.load_uk_development_review(uk_workspace)
    notes["uk_excluded"] = uk_exclusions
    loaded = taiwan + uk
    try:
        loaded.append(case_loading.load_owner_photo(MUESLI_MASTER, MUESLI_CONSENT, muesli_truth()))
        notes["muesli"] = "run"
    except PermissionError as error:
        notes["muesli"] = f"not run: {error}"
    return loaded, notes


def summarise(loaded: list[dict[str, Any]], per_case: list[dict[str, Any]], thresholds: dict[str, float]) -> dict[str, Any]:
    strata: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for case, result in zip(loaded, per_case, strict=True):
        strata[case["metadata"]["stratum"]].append(result)
    by_stratum = {}
    for name, results in sorted(strata.items()):
        summary = scoring.aggregate(results, thresholds)
        truths = [c["truth"] for c in loaded if c["metadata"]["stratum"] == name and not c["truth"]["requires_decline"]]
        mutation = arithmetic.mutation_detection(truths)["overall"]
        summary["metrics"]["arithmetic_mutation_detection"] = {
            "numerator": mutation["detected"],
            "denominator": mutation["applicable"],
            "verdict": ("pass" if mutation["detected"] == mutation["applicable"] else "fail")
            if mutation["applicable"]
            else "no_denominator",
        }
        summary["decline_reasons"] = dict(sorted(Counter(r for res in results for r in res.get("candidate_decline_reasons", [])).items()))
        by_stratum[name] = summary
    return {"overall": scoring.aggregate(per_case, thresholds), "by_stratum": by_stratum}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vision-binary", type=Path, required=True)
    parser.add_argument("--parser-binary", type=Path, required=True)
    parser.add_argument("--taiwan-root", type=Path, default=PRIVATE / "off-taiwan-v1")
    parser.add_argument("--uk-workspace", type=Path, default=UK_REVIEW)
    parser.add_argument("--log-dir", type=Path, required=True, help="Inspect log directory outside the repository")
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()
    if not outside_repository(args.log_dir):
        raise SystemExit("--log-dir must be outside the repository")

    from inspect_ai import eval as inspect_eval

    from inspect_task import label_capture_development_photos

    loaded, notes = build_cases(args.taiwan_root, args.uk_workspace)
    args.log_dir.mkdir(parents=True, exist_ok=True)
    cases_file = args.log_dir / "route-b-development-cases.json"
    cases_file.write_text(json.dumps(loaded, ensure_ascii=False), encoding="utf-8")
    logs = inspect_eval(
        label_capture_development_photos(
            cases_file=str(cases_file), vision_binary=str(args.vision_binary), parser_binary=str(args.parser_binary)
        ),
        model="mockllm/model",
        log_dir=str(args.log_dir),
        display="none",
        max_samples=4,
    )
    log = logs[0]
    if log.status != "success":
        raise SystemExit(f"Inspect run status {log.status}: {log.error}")
    by_id = {sample.id: sample for sample in log.samples or []}
    per_case, rows = [], []
    vision = None
    for case in loaded:
        sample = by_id[case["id"]]
        metadata = (sample.scores or {})["label_capture_scorer"].metadata
        if metadata is None:
            raise SystemExit(f"{case['id']} has no scorer result")
        candidate = json.loads(sample.output.completion) if sample.output and sample.output.completion else {}
        metadata = {**metadata, "candidate_decline_reasons": candidate.get("decline_reasons", [])}
        per_case.append(metadata)
        vision = vision or sample.metadata.get("vision")
        truth = case["truth"]
        rows.append(
            {
                "id": case["id"],
                "stratum": case["metadata"]["stratum"],
                "requires_decline": truth["requires_decline"],
                "declined": bool(metadata["declined"]),
                "decline_reasons": candidate.get("decline_reasons", []),
                "cells_exact": metadata["cells_exact"],
                "product_cells": metadata["product_cells"],
                "cells_bound": metadata["cells_bound"],
                "all_cells": metadata["all_cells"],
                "extra_cells": metadata["extra_cells"],
                "table_exact": metadata["tables_exact"],
                "false_ready": metadata["false_ready"],
                "serialiser": sample.metadata.get("serialiser_report"),
            }
        )
    summary = summarise(loaded, per_case, scoring.load_thresholds())
    summary.update(
        {
            "route": "B",
            "split": "development",
            "inspect_log": Path(log.location).name,
            "vision": vision,
            "serialiser_version": next((s.metadata.get("serialiser_version") for s in by_id.values()), None),
            "parser_version": next((s.metadata.get("parser_version") for s in by_id.values()), None),
            "cases": len(loaded),
            "notes": notes,
            "per_case": rows,
        }
    )
    text = json.dumps(summary, indent=2, ensure_ascii=False)
    if args.summary:
        args.summary.write_text(text + "\n", encoding="utf-8")
    for name, stratum in summary["by_stratum"].items():
        print(
            name,
            json.dumps(
                {
                    k: (v.get("rate"), v.get("numerator", v.get("count")), v.get("denominator"), v["verdict"])
                    for k, v in stratum["metrics"].items()
                }
            ),
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
