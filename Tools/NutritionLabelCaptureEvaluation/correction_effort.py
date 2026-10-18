#!/usr/bin/env python3
"""Correction-effort analysis of the saved label-capture outputs (#255, owner approval 18 October 2026).

Offline: no model, provider or Vision call, and nothing is rerun. It reads the saved outputs and
the frozen, corrected truth, and asks how much a user would have to edit on Confirm if a route's
output only pre-filled the table: recognition pre-fills, the user validates and optionally
corrects, and estimates and exceptions are visible.

This is a post-freeze analysis addition. It does not change the scorer, the gate, the mapping,
the truth or any pinned file, it is not a pass or fail, and it does not change the pre-registered
verdict. The truth is model-drafted and owner-verified, with the anchoring caveat; whether a real
user catches an error is not measured.

The pure part (`label_effort`, `assisted_view`, `summarise`) has no I/O. `main` loads the saved
outputs the same way `rescore_untouched.py` and `rescore_development.py` do and writes counts and
case ids only.

Edit model, per usable table (a truth record that is neither excluded nor a required decline):

- Slots are matched with the scorer's own semantic key (`score.keyed_cells`: nutrient, parent,
  basis and, for duplicate same-basis columns, the printed header).
- **Correction:** a pre-filled value in a slot the truth has, which is not strictly equal (value,
  comparator, unit). Also one correction, not a fill plus a removal, for a right value bound to the
  wrong column or parent (same nutrient and value, different basis, header or parent), and for a
  value in the right column under the wrong parent.
- **Fill:** a gradable truth cell with no pre-filled value (left out, unread or `unknown`).
- **Removal:** a pre-filled value where the truth has no printed cell. Reference-intake cells are
  not removals when the truth did not transcribe that column (amendment T1), and a value in a slot
  the truth keeps as ungradable (`unscored_cells`) is neither credited nor removed.
- **Serving lines:** the serving size and the servings per pack, each `ok`, `correction`, `fill`,
  `removal` or `not_scored` (truth `not_recorded`, or nothing printed and nothing pre-filled).
- **Edits** per label = cell corrections + fills + removals + serving-line edits.
- **Hard decline on a usable table:** the whole table is typed or pasted by hand; it is counted
  separately and left out of the edit distribution, with the number of cells it would need.
- **Silent error:** a correction or removal in a row the Confirm flags (gate G3 and G4 rows) would
  not draw attention to, or a wrong or invented serving line (G6 flags only a missing line). These
  are the errors the user must spot unaided.
- **Silent omission** (reported separately, not a wrong value): a row the route left out entirely,
  with no value in any column and no flag on it, so the row is absent from Confirm.

Two views of the same saved outputs:

- `as_run`: the outputs as gated by `label-capture-decline-gate-v2` (untouched: the saved gated
  output; development: the gate applied offline to the saved output, as `rescore_development.py`
  does, because those runs predate the gate). Every gate decline is a whole table by hand.
- `assisted`: the ungated output with only the hard declines of the assisted design re-applied:
  the route's own decline (no table, the parser's binding failures, a model decline), a failed
  output, and gate G1 (`unsupported_script`) and G2 (`not_a_food_nutrition_panel`). G3 to G6
  become flags, never declines.

    .venv/bin/python correction_effort.py --runs ~/WHR-label-eval-private/runs --out results/correction-effort-v1.json
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import re
import statistics
from pathlib import Path
from typing import Any

import arithmetic
import decline_gate
import score as scoring
from candidate import validate_candidate

HERE = Path(__file__).resolve().parent
ANALYSIS_VERSION = "label-capture-correction-effort-v1"
HARD_GATE_DECLINES = ("unsupported_script", "not_a_food_nutrition_panel")
VIEWS = ("as_run", "assisted")
BUCKETS = ("0", "1-2", "3-5", "6+")
UNTOUCHED_ARMS = ("gemini-on", "sol-on", "luna-off", "route-b")
DEVELOPMENT_ARMS = ("gemini-on", "sol-on", "luna-off")
CODE = re.compile(r"^[a-z0-9_:]{1,64}$")
SERVING_FIELDS = ("serving_size", "servings_per_pack")


# ---------------------------------------------------------------- views


def assisted_view(candidate: dict[str, Any] | None, label_format: str) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    """The ungated candidate with only the assisted design's hard declines applied. Pure.

    Returns (candidate, report). A hard decline withholds every cell, as the gate does; anything
    else is passed through byte for byte, with the gate's G3 to G6 findings reported as flags.
    """
    if candidate is None or validate_candidate(candidate):
        return candidate, {"hard_decline": "failed_output", "flags": [], "details": []}
    if candidate.get("declined"):
        return candidate, {"hard_decline": "route_declined", "flags": [], "details": []}
    found = decline_gate.evaluate(candidate, label_format)
    hard = [reason for reason in found["declines"] if reason in HARD_GATE_DECLINES]
    flags = [reason for reason in found["declines"] + found["blocks"] if reason not in HARD_GATE_DECLINES]
    if hard:
        declined = copy.deepcopy(candidate)
        declined.update(
            {
                "declined": True,
                "decline_reasons": [*candidate.get("decline_reasons", []), *(f"gate:{r}" for r in hard)],
                "would_mark_ready": False,
                "serving_size": "unknown",
                "servings_per_pack": "unknown",
                "headers": [],
                "cells": [],
            }
        )
        return declined, {"hard_decline": "gate:" + "+".join(hard), "flags": flags, "details": found["details"]}
    return candidate, {"hard_decline": None, "flags": flags, "details": found["details"]}


def as_run_view(candidate: dict[str, Any] | None, label_format: str) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    """The candidate under gate v2 as frozen: every gate decline counts. Pure."""
    if candidate is None or validate_candidate(candidate):
        return candidate, {"hard_decline": "failed_output", "flags": [], "details": []}
    if candidate.get("declined"):
        return candidate, {"hard_decline": "route_declined", "flags": [], "details": []}
    gated, report = decline_gate.apply_gate(candidate, label_format)
    if report["declines"]:
        return gated, {"hard_decline": "gate:" + "+".join(report["declines"]), "flags": [], "details": report["details"]}
    return gated, {"hard_decline": None, "flags": list(report["blocks"]), "details": report["details"]}


def flagged_rows(details: list[str]) -> set[str]:
    """Rows the Confirm flags would mark (G3 rows with no amount, G4 rows missing a per 100 column)."""
    rows: set[str] = set()
    for detail in details:
        for prefix in ("required_rows_without_amount: ", "required_rows_missing_a_column: "):
            if detail.startswith(prefix):
                rows.update(part.strip() for part in detail[len(prefix) :].split(","))
    return rows


# ---------------------------------------------------------------- one label


def _key(cell: dict[str, Any], table: dict[str, Any]) -> tuple:
    return scoring.keyed_key(cell, table)


def _value_known(cell: dict[str, Any]) -> bool:
    return cell.get("decimal_text") not in (None, "")


def _row_name(cell: dict[str, Any]) -> str:
    nutrient = cell.get("nutrient")
    return str(nutrient) if nutrient in scoring.NUTRIENTS else "other_row"


def _correction_type(truth_cell: dict[str, Any], found: dict[str, Any]) -> str:
    if found.get("decimal_text") != truth_cell.get("decimal_text") or (found.get("comparator") or "=") != (
        truth_cell.get("comparator") or "="
    ):
        return "value"
    return "unit"


def _serving_status(field: str, truth: dict[str, Any], output: dict[str, Any]) -> str:
    expected, found = truth.get(field), output.get(field)
    known_truth = isinstance(expected, dict) and bool(expected.get("decimal_text"))
    if expected == scoring.NOT_RECORDED or (not known_truth and truth.get("servings_per_pack") == scoring.NOT_RECORDED):
        # The UK v2 development review transcribed no serving lines (`cases.uk_truth_from_review`):
        # its `unknown` serving size means not recorded, not "nothing printed".
        return "not_scored"
    known_found = isinstance(found, dict) and bool(found.get("decimal_text"))
    if not known_truth:
        return "removal" if known_found else "not_scored"
    if not known_found:
        return "fill"
    equal = scoring.serving_size_equal if field == "serving_size" else scoring.servings_equal
    return "ok" if equal(expected, found) else "correction"


def gradable_truth_cells(truth: dict[str, Any]) -> list[dict[str, Any]]:
    return list(truth.get("cells") or [])


def label_effort(output: dict[str, Any] | None, truth: dict[str, Any], view_report: dict[str, Any]) -> dict[str, Any]:
    """The edits one pre-filled table needs against its truth. Pure.

    `output` is the candidate as the view presents it; `view_report` is from `as_run_view` or
    `assisted_view` (its `hard_decline` and `details`).
    """
    truth_cells = gradable_truth_cells(truth)
    serving_lines = sum(1 for field in SERVING_FIELDS if _serving_status(field, truth, {}) == "fill")
    if view_report["hard_decline"] is not None or output is None:
        return {
            "hard_decline": view_report["hard_decline"] or "failed_output",
            "cells_to_type": len(truth_cells),
            "serving_lines_to_type": serving_lines,
            "corrections": 0,
            "corrections_by_type": {"value": 0, "unit": 0, "binding": 0},
            "fills": 0,
            "removals": 0,
            "serving_size": "whole_table",
            "servings_per_pack": "whole_table",
            "serving_line_edits": 0,
            "edits": None,
            "silent_error": False,
            "silent_rows": [],
            "silent_omission": False,
            "unflagged_missing_rows": [],
            "arithmetic_status": None,
        }

    by_type = {"value": 0, "unit": 0, "binding": 0}
    silent_rows: list[str] = []
    flagged = flagged_rows(view_report.get("details") or [])
    cand_cells = [c for c in output.get("cells") or [] if _value_known(c)]
    if truth.get("reference_intake_transcribed") is False:
        cand_cells = [c for c in cand_cells if c.get("basis") != "reference_intake"]
    unscored = {(scoring.nutrient_key(c), c.get("basis")) for c in truth.get("unscored_cells") or []}

    truth_groups: dict[tuple, list[dict[str, Any]]] = {}
    for cell in truth_cells:
        truth_groups.setdefault(_key(cell, truth), []).append(cell)
    cand_groups: dict[tuple, list[dict[str, Any]]] = {}
    for cell in cand_cells:
        cand_groups.setdefault(_key(cell, output), []).append(cell)

    def wrong(cell: dict[str, Any], kind: str) -> None:
        by_type[kind] += 1
        row = _row_name(cell)
        if cell.get("nutrient") not in flagged:
            silent_rows.append(row)

    left_truth: list[dict[str, Any]] = []
    left_cand: list[dict[str, Any]] = []
    # Stage 1: the scorer's key. Exact matches first, then the rest in order.
    for key in sorted(set(truth_groups) | set(cand_groups), key=repr):
        expected, found = list(truth_groups.get(key, [])), list(cand_groups.get(key, []))
        for cell in list(expected):
            match = next((c for c in found if scoring.strict_equal(cell, c)), None)
            if match is not None:
                expected.remove(cell)
                found.remove(match)
        while expected and found:
            cell, match = expected.pop(0), found.pop(0)
            wrong(match, _correction_type(cell, match))
        left_truth.extend(expected)
        left_cand.extend(found)

    # Stage 2: the right value bound to the wrong column or parent (same nutrient, value and unit).
    # Stage 3: the right column under the wrong parent (same nutrient, basis and header).
    def pair(same: Any, kind: str) -> None:
        for cell in list(left_truth):
            match = next((c for c in left_cand if same(cell, c)), None)
            if match is not None:
                left_truth.remove(cell)
                left_cand.remove(match)
                wrong(match, kind)

    def same_row(a: dict[str, Any], b: dict[str, Any]) -> bool:
        return scoring.nutrient_key(a) == scoring.nutrient_key(b)

    pair(
        lambda t, c: (
            same_row(t, c)
            and t.get("decimal_text") == c.get("decimal_text")
            and t.get("canonical_unit") == c.get("canonical_unit")
            and (t.get("comparator") or "=") == (c.get("comparator") or "=")
        ),
        "binding",
    )
    # Stage 2 already took every pair whose value was right, so a stage 3 pair has a wrong value too.
    pair(lambda t, c: same_row(t, c) and _key(t, truth)[2:] == _key(c, output)[2:], "value")

    fills = len(left_truth)
    # A fill in a row the route left out entirely (no value in any column) and no flag marks: the
    # row is simply absent from Confirm, so the user must notice the omission from the label.
    present_rows = {scoring.nutrient_key(c) for c in cand_cells}
    missing_rows = sorted(
        {_row_name(cell) for cell in left_truth if scoring.nutrient_key(cell) not in present_rows and cell.get("nutrient") not in flagged}
    )
    removed = [c for c in left_cand if (scoring.nutrient_key(c), c.get("basis")) not in unscored]
    for cell in removed:
        if cell.get("nutrient") not in flagged:
            silent_rows.append(_row_name(cell))

    serving = {field: _serving_status(field, truth, output) for field in SERVING_FIELDS}
    serving_edits = sum(1 for status in serving.values() if status in ("correction", "fill", "removal"))
    silent_serving = [field for field, status in serving.items() if status in ("correction", "removal")]
    corrections = sum(by_type.values())
    return {
        "hard_decline": None,
        "cells_to_type": 0,
        "serving_lines_to_type": 0,
        "corrections": corrections,
        "corrections_by_type": by_type,
        "fills": fills,
        "removals": len(removed),
        "serving_size": serving["serving_size"],
        "servings_per_pack": serving["servings_per_pack"],
        "serving_line_edits": serving_edits,
        "edits": corrections + fills + len(removed) + serving_edits,
        "silent_error": bool(silent_rows or silent_serving),
        "silent_rows": sorted(set(silent_rows) | set(silent_serving)),
        "silent_omission": bool(missing_rows),
        "unflagged_missing_rows": missing_rows,
        "arithmetic_status": arithmetic.check_table(output)["status"],
    }


# ---------------------------------------------------------------- summaries


def bucket(edits: int) -> str:
    if edits == 0:
        return "0"
    if edits <= 2:
        return "1-2"
    if edits <= 5:
        return "3-5"
    return "6+"


def nearest_rank(values: list[int], share: float) -> int | None:
    """The nearest-rank percentile (the smallest value with at least `share` of values at or below it)."""
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(share * len(ordered)) - 1)]


def _number(value: float) -> int | float:
    return int(value) if float(value).is_integer() else float(value)


def summarise(labels: list[dict[str, Any]]) -> dict[str, Any]:
    """Distribution and totals over one arm's usable tables. Pure."""
    prefilled = [label for label in labels if label["effort"]["hard_decline"] is None]
    declined = [label for label in labels if label["effort"]["hard_decline"] is not None]
    edits = [label["effort"]["edits"] for label in prefilled]
    counts = {name: 0 for name in BUCKETS}
    for value in edits:
        counts[bucket(value)] += 1
    total = len(labels)

    def share(n: int) -> float | None:
        return round(n / total, 4) if total else None

    def summed(field: str) -> int:
        return sum(label["effort"][field] for label in prefilled)

    def serving(field: str, status: str) -> int:
        return sum(1 for label in prefilled if label["effort"][field] == status)

    silent = [label["id"] for label in prefilled if label["effort"]["silent_error"]]
    reasons: dict[str, int] = {}
    for label in declined:
        reasons[label["effort"]["hard_decline"]] = reasons.get(label["effort"]["hard_decline"], 0) + 1
    return {
        "usable_tables": total,
        "prefilled_tables": len(prefilled),
        "distribution": {
            **{name: {"tables": counts[name], "share": share(counts[name])} for name in BUCKETS},
            "whole_table_by_hand": {"tables": len(declined), "share": share(len(declined))},
        },
        "median_edits_per_prefilled_table": _number(statistics.median(edits)) if edits else None,
        "p90_edits_per_prefilled_table": nearest_rank(edits, 0.9),
        "total_edits_prefilled": sum(edits),
        "corrections": summed("corrections"),
        "corrections_by_type": {
            kind: sum(label["effort"]["corrections_by_type"][kind] for label in prefilled) for kind in ("value", "unit", "binding")
        },
        "fills": summed("fills"),
        "removals": summed("removals"),
        "serving_size": {status: serving("serving_size", status) for status in ("correction", "fill", "removal")},
        "servings_per_pack": {status: serving("servings_per_pack", status) for status in ("correction", "fill", "removal")},
        "hard_declines": {
            "tables": len(declined),
            "reasons": dict(sorted(reasons.items())),
            "cells_to_type": sum(label["effort"]["cells_to_type"] for label in declined),
            "serving_lines_to_type": sum(label["effort"]["serving_lines_to_type"] for label in declined),
            "ids": sorted(label["id"] for label in declined),
        },
        "silent_error_tables": {
            "tables": len(silent),
            "ids": sorted(silent),
            "of_which_arithmetic_check_did_not_fail": sorted(
                label["id"]
                for label in prefilled
                if label["effort"]["silent_error"] and label["effort"]["arithmetic_status"] != arithmetic.FAIL
            ),
        },
        "silent_omission_tables": {
            "note": "reported separately: a row left out entirely that no flag marks (an omission, not a wrong value)",
            "tables": sum(1 for label in prefilled if label["effort"]["silent_omission"]),
            "ids": sorted(label["id"] for label in prefilled if label["effort"]["silent_omission"]),
        },
        "zero_edit_ids": sorted(label["id"] for label in prefilled if label["effort"]["edits"] == 0),
    }


def analyse(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Both views over one arm. Each row: id, truth, label_format, candidate (ungated). Pure."""
    out: dict[str, Any] = {}
    for view, apply in (("as_run", as_run_view), ("assisted", assisted_view)):
        labels = []
        for row in rows:
            presented, report = apply(row["candidate"], row["label_format"])
            labels.append({"id": row["id"], "effort": label_effort(presented, row["truth"], report), "flags": report["flags"]})
        out[view] = {"summary": summarise(labels), "labels": labels}
    return out


def usable(truth: dict[str, Any]) -> bool:
    return not truth.get("excluded") and not truth.get("requires_decline") and not truth.get("excluded_from_scoring")


# ---------------------------------------------------------------- loading (I/O)


def untouched_rows(runs: Path, arm: str) -> tuple[list[dict[str, Any]], int]:
    """Ungated untouched outputs for one arm, checked against the saved gated output.

    Returns the rows and the number of samples whose saved gated output matched the gate re-applied
    to the ungated output (it must be every sample).
    """
    from inspect_ai.log import read_eval_log

    import rescore_untouched

    truths = rescore_untouched.frozen_truth()
    (log_path,) = sorted((runs / "untouched-v1" / arm / "untouched").glob("*.eval"))
    log = read_eval_log(str(log_path))
    rows, matched = [], 0
    for sample in log.samples or []:
        case_id = str(sample.id)
        truth = truths[case_id]
        completion = sample.output.completion if sample.output else ""
        saved = json.loads(completion) if completion else None
        metadata = sample.metadata or {}
        ungated = metadata.get("pre_gate_candidate", saved)
        regated, _ = decline_gate.apply_gate(ungated, decline_gate.TAIWAN)
        matched += int(regated == saved)
        if usable(truth):
            rows.append({"id": case_id, "truth": truth, "label_format": decline_gate.TAIWAN, "candidate": ungated})
    expected = {cid for cid, record in truths.items() if usable(record)}
    if {row["id"] for row in rows} != expected:
        raise SystemExit(f"{arm}: the saved outputs do not cover exactly the usable untouched records")
    return rows, matched


def development_rows(runs: Path, arm: str) -> dict[str, list[dict[str, Any]]]:
    """Ungated development outputs per stratum, loaded as `rescore_development.py` does."""
    import rescore_development

    if arm == "route-b":
        folder = runs / "route-b-dev" / "phase3"
        (log,) = sorted(folder.glob("*.eval"))
        cases = json.loads((folder / "route-b-development-cases.json").read_text(encoding="utf-8"))
    else:
        folder = runs / "route-c-dev"
        summary = json.loads((folder / f"{arm}-summary.json").read_text(encoding="utf-8"))
        log = folder / arm / summary["inspect_log"]
        cases = json.loads((folder / arm / "development-cases.json").read_text(encoding="utf-8"))
    strata: dict[str, list[dict[str, Any]]] = {}
    for row in rescore_development.load_arm(log, cases):
        if usable(row["truth"]):
            strata.setdefault(str(row["stratum"]), []).append(row)
    return strata


def _public(analysis: dict[str, Any]) -> dict[str, Any]:
    """Counts and case ids only; reason codes are kept only when they are plain codes."""
    out: dict[str, Any] = {}
    for view, block in analysis.items():
        labels = []
        for label in block["labels"]:
            effort = dict(label["effort"])
            reason = effort["hard_decline"]
            if reason is not None and not CODE.match(reason.replace("+", "_")):
                effort["hard_decline"] = "other"
            labels.append({"id": label["id"], "flags": [f for f in label["flags"] if CODE.match(f)], **effort})
        out[view] = {"summary": block["summary"], "labels": labels}
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runs", type=Path, default=Path.home() / "WHR-label-eval-private" / "runs")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)

    untouched: dict[str, Any] = {}
    for arm in UNTOUCHED_ARMS:
        rows, matched = untouched_rows(args.runs, arm)
        if matched != 40:
            raise SystemExit(f"{arm}: re-applying gate v2 reproduces {matched} of 40 saved gated outputs; refusing")
        untouched[arm] = {"gate_v2_reproduces_saved_outputs": f"{matched}/40", **_public(analyse(rows))}

    development: dict[str, Any] = {}
    for arm in (*DEVELOPMENT_ARMS, "route-b"):
        development[arm] = {stratum: _public(analyse(rows)) for stratum, rows in sorted(development_rows(args.runs, arm).items())}

    result = {
        "analysis": ANALYSIS_VERSION,
        "status": (
            "post-freeze analysis addition (owner approval 18 October 2026); not a pass or fail; the pre-registered verdict is unchanged"
        ),
        "truth": {
            "untouched": (
                "fixtures/ground-truth-off-taiwan-untouched-v1.json (the contract's current pin, after the three owner corrections)"
            ),
            "development": "as rescore_development.py loads it (round-3 Taiwan truth, amendment T1 for UK)",
            "caveat": "model-drafted, owner-verified truth with the anchoring caveat: cell-level figures are approximate",
        },
        "not_measured": "whether a user actually catches a wrong pre-filled value",
        "views": {
            "as_run": "outputs under gate v2 as frozen (untouched: the saved gated outputs; development: gate v2 applied offline)",
            "assisted": "ungated outputs with only the assisted design's hard declines: route decline, failed output, G1, G2",
        },
        "untouched_taiwan": untouched,
        "development": development,
    }
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    for split, block in (("untouched", {arm: {"taiwan_zh_hant": v} for arm, v in untouched.items()}), ("development", development)):
        for arm, strata in block.items():
            for stratum, views in strata.items():
                for view in VIEWS:
                    s = views[view]["summary"]
                    d = s["distribution"]
                    print(
                        f"{split:11} {arm:9} {stratum:15} {view:8} n={s['usable_tables']:>3} "
                        f"0:{d['0']['tables']:>3} 1-2:{d['1-2']['tables']:>3} 3-5:{d['3-5']['tables']:>3} 6+:{d['6+']['tables']:>3} "
                        f"hand:{d['whole_table_by_hand']['tables']:>3} median {s['median_edits_per_prefilled_table']} "
                        f"p90 {s['p90_edits_per_prefilled_table']} total {s['total_edits_prefilled']} "
                        f"silent {s['silent_error_tables']['tables']}"
                    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
