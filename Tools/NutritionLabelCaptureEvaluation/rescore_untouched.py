#!/usr/bin/env python3
"""Correction path for the untouched truth (phase 5, #255): a recorded deviation, then an offline re-score.

The untouched run is never rerun. Owner corrections of untouched truth cells go in a separate
corrections file (`fixtures/untouched-truth-corrections-v1.json`), and this script:

1. checks the truth file it is given against an expected SHA-256 (by default the contract's
   current `ground_truth.untouched_sha256`);
2. applies each correction in memory, refusing a correction that does not match exactly one
   truth cell (by case id, nutrient and basis) or whose recorded `was` text is not the current
   printed text;
3. re-scores the saved, already gated outputs of every untouched arm (route B and the three
   route C arms) from their Inspect logs with the frozen scorer, before and after the
   corrections, with no model, provider or Vision call.

With no corrections file it reproduces the run's own numbers. History: on 18 October 2026 the
owner's three corrections of `off-taiwan:3228022000311` were applied this way to the truth as
run, and then, by owner decision, written into the truth file itself with only its hash re-pinned
(contract `untouched_truth_deviations.applied`). The truth as run is the file at commit 32f59aff
(SHA-256 d40a56b7...). To reproduce the committed before and after exactly:

    git show 32f59aff:Tools/NutritionLabelCaptureEvaluation/fixtures/ground-truth-off-taiwan-untouched-v1.json > /tmp/truth-as-run.json
    .venv/bin/python rescore_untouched.py --truth /tmp/truth-as-run.json \
        --expected-sha256 d40a56b7b35aad65a26338ded755bb22475520ccf1dd6fc2a26150c64e5b57a3 \
        --corrections fixtures/untouched-truth-corrections-v1.json --out results/untouched-truth-correction-rescore-v1.json

Run with the current truth file and no corrections, it reproduces the corrected figures.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any

import score as scoring

HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "frozen-contract-v1.json"
TRUTH = HERE / "fixtures" / "ground-truth-off-taiwan-untouched-v1.json"
ARMS = ("route-b", "luna-off", "gemini-on", "sol-on")
CELL_FIELDS = ("printed_text", "comparator", "decimal_text", "unit", "canonical_unit")


def current_pin(contract_path: Path = CONTRACT) -> str:
    return json.loads(contract_path.read_text(encoding="utf-8"))["ground_truth"]["untouched_sha256"]


def frozen_truth(path: Path = TRUTH, contract_path: Path = CONTRACT, expected_sha256: str | None = None) -> dict[str, dict[str, Any]]:
    """The truth records, after checking the file against the expected hash (default: the contract's current pin)."""
    expected = expected_sha256 or json.loads(contract_path.read_text(encoding="utf-8"))["ground_truth"]["untouched_sha256"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit("the untouched truth does not match the expected hash")
    return {record["case_id"]: record for record in json.loads(path.read_text(encoding="utf-8"))["records"]}


def apply_corrections(
    truths: dict[str, dict[str, Any]], corrections: list[dict[str, Any]]
) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    """Pure: the corrected truth (a copy) and a log of every changed cell. Refuses anything ambiguous."""
    corrected = copy.deepcopy(truths)
    log: list[dict[str, Any]] = []
    for correction in corrections:
        record = corrected.get(correction["case_id"])
        if record is None or record.get("excluded"):
            raise ValueError(f"{correction['case_id']} is not a usable untouched record")
        for change in correction["cells"]:
            matches = [c for c in record["cells"] if c["nutrient"] == change["nutrient"] and c["basis"] == change["basis"]]
            if len(matches) != 1:
                raise ValueError(f"{correction['case_id']}: {change['nutrient']} {change['basis']} matches {len(matches)} cells")
            cell = matches[0]
            if cell["printed_text"] != change["was"]:
                raise ValueError(
                    f"{correction['case_id']}: {change['nutrient']} {change['basis']} is {cell['printed_text']!r}, not {change['was']!r}"
                )
            before = {field: cell.get(field) for field in CELL_FIELDS}
            for field in CELL_FIELDS:
                if field in change["now"]:
                    cell[field] = change["now"][field]
            log.append(
                {
                    "case_id": correction["case_id"],
                    "nutrient": change["nutrient"],
                    "basis": change["basis"],
                    "before": before,
                    "after": {f: cell.get(f) for f in CELL_FIELDS},
                }
            )
    return corrected, log


def saved_outputs(log_path: Path) -> dict[str, dict[str, Any] | None]:
    """The gated candidate each untouched sample produced, from its saved Inspect log."""
    from inspect_ai.log import read_eval_log

    log = read_eval_log(str(log_path))
    found: dict[str, dict[str, Any] | None] = {}
    for sample in log.samples or []:
        completion = sample.output.completion if sample.output else ""
        found[str(sample.id)] = json.loads(completion) if completion else None
    return found


def score_arm(outputs: dict[str, dict[str, Any] | None], truths: dict[str, dict[str, Any]]) -> dict[str, Any]:
    usable = {cid: record for cid, record in truths.items() if not record.get("excluded")}
    if set(outputs) != set(usable):
        raise SystemExit("the saved outputs do not cover exactly the usable untouched records")
    results = [scoring.score_case(outputs[cid], usable[cid]) for cid in sorted(usable)]
    aggregated = scoring.aggregate(results, scoring.load_thresholds())
    aggregated["false_ready_ids"] = [cid for cid, result in zip(sorted(usable), results, strict=True) if result["false_ready"]]
    return aggregated


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runs", type=Path, default=Path.home() / "WHR-label-eval-private" / "runs" / "untouched-v1")
    parser.add_argument(
        "--corrections", type=Path, help="owner answers: {'corrections': [{case_id, cells: [{nutrient, basis, was, now}]}]}"
    )
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--truth", type=Path, default=TRUTH, help="the truth file to start from (default: the current pinned file)")
    parser.add_argument("--expected-sha256", help="the hash --truth must have (default: the contract's current untouched pin)")
    args = parser.parse_args(argv)
    truths = frozen_truth(args.truth, expected_sha256=args.expected_sha256)
    corrections = json.loads(args.corrections.read_text(encoding="utf-8"))["corrections"] if args.corrections else []
    corrected, change_log = apply_corrections(truths, corrections)
    arms = {}
    for arm in ARMS:
        (log_path,) = sorted((args.runs / arm / "untouched").glob("*.eval"))
        outputs = saved_outputs(log_path)
        arms[arm] = {"log": log_path.name, "frozen_truth": score_arm(outputs, truths), "corrected_truth": score_arm(outputs, corrected)}
    summary = {
        "note": (
            "Offline re-score of the saved untouched outputs; no rerun and no API call. "
            "frozen_truth is the truth file given; corrected_truth is that file with the corrections applied in memory."
        ),
        "truth_sha256": hashlib.sha256(args.truth.read_bytes()).hexdigest(),
        "truth_sha256_note": (
            "the current pinned truth"
            if hashlib.sha256(args.truth.read_bytes()).hexdigest() == current_pin()
            else f"superseded: this is an earlier truth file; the contract now pins {current_pin()}"
        ),
        "corrections_applied": change_log,
        "arms": arms,
    }
    args.out.write_text(json.dumps(summary, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    for arm, block in arms.items():
        before, after = block["frozen_truth"]["metrics"], block["corrected_truth"]["metrics"]
        print(
            arm,
            {
                name: (before[name].get("numerator", before[name].get("count")), after[name].get("numerator", after[name].get("count")))
                for name in ("strict_cells", "full_table", "false_ready")
            },
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
