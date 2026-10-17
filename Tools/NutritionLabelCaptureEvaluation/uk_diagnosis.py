"""Offline diagnosis of the UK development stratum for route C (phase 4, #255).

No API call. It reads the saved route C development logs outside the repository and
separates, per arm, the UK losses that come from scoring or ground-truth conventions
from genuine model errors. It also scores three **proposed, not applied** amendments as
counterfactuals so the owner can see what each would change:

- S1 serving conversions compared on the printed mass or volume (decimal and canonical
  unit) instead of the literal header text, with count-only portions ("2 sausages",
  "1 cracker"), which print no mass or volume, left out of the denominator;
- M1 route C mapping leaves an absolute reference-intake value ("8400kJ" in an "RI for an
  average adult" column) out as unread, instead of failing the whole candidate;
- M2 route C mapping takes the unit from the row label when the label prints exactly one
  energy unit and the value prints none ("Energy kJ" with "704").

Nothing here changes the scorer, the mapping or any truth. The summary written to
`results/` holds counts and case ids only, never a model answer.

    .venv/bin/python uk_diagnosis.py --runs ~/WHR-label-eval-private/runs --out results/uk-diagnosis-v1.json
"""

from __future__ import annotations

import argparse
import copy
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

import route_c_mapping
import score as scoring
from candidate import validate_candidate
from draft_untouched_truth import SERVING, UNITS, parse_value
from rescore_development import ROUTE_C_ARMS

MASS = re.compile(r"(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)\b")


def _load(log_path: Path, cases: list[dict[str, Any]]) -> list[dict[str, Any]]:
    from inspect_ai.log import read_eval_log

    log = read_eval_log(str(log_path))
    by_id = {str(s.id): s for s in log.samples or []}
    rows = []
    for case in cases:
        if case["metadata"].get("split") != "development":
            raise SystemExit(f"{case['id']} is not a development case; refusing")
        if case["metadata"].get("stratum") != "uk_en":
            continue
        sample = by_id.get(case["id"])
        candidate = None
        if sample is not None and sample.output and sample.output.completion:
            candidate = json.loads(sample.output.completion)
        answer = (sample.metadata or {}).get("route_c_answer") if sample is not None else None
        rows.append({"id": case["id"], "truth": case["truth"], "candidate": candidate, "answer": answer})
    return rows


def printed_mass(text: Any) -> tuple[str, str] | None:
    match = MASS.search(str(text or ""))
    if not match:
        return None
    unit = match.group(2)
    return match.group(1), UNITS.get(unit) or UNITS.get(unit.lower()) or unit


def conversion_outcomes(truth: dict[str, Any], candidate: dict[str, Any] | None) -> Counter:
    """Classify every scored truth conversion for one table."""
    out: Counter = Counter()
    if truth.get("requires_decline"):
        return out
    usable = candidate is not None and not validate_candidate(candidate) and not candidate.get("declined")
    found, _ = scoring.keyed_cells(candidate) if usable and candidate else ({}, set())
    expected, _ = scoring.keyed_cells(truth)
    for key, cell in expected.items():
        conversion = cell.get("serving_conversion")
        if cell.get("basis") != "per_serving" or conversion in scoring.NOT_A_CONVERSION:
            continue
        got = found.get(key)
        got_conversion = got.get("serving_conversion") if got else None
        truth_mass = printed_mass(conversion)
        if scoring.compact(got_conversion) == scoring.compact(conversion):
            out["exact_as_scored"] += 1
        elif truth_mass is None:
            out["count_only_portion_no_mass_printed"] += 1
        elif got is None:
            out["cell_not_matched"] += 1
        elif printed_mass(got_conversion) == truth_mass:
            out["same_mass_header_wording_differs"] += 1
        elif got_conversion in (None, "unknown"):
            out["candidate_unknown_mass_printed"] += 1
        else:
            out["different_mass"] += 1
    return out


def cell_outcomes(truth: dict[str, Any], candidate: dict[str, Any] | None) -> Counter:
    """Classify every product cell miss for one usable table."""
    out: Counter = Counter()
    if truth.get("requires_decline"):
        return out
    expected, _ = scoring.keyed_cells(truth)
    product = {k: c for k, c in expected.items() if c.get("basis") != "reference_intake"}
    if candidate is None:
        out["no_candidate"] += len(product)
        return out
    errors = validate_candidate(candidate)
    if errors:
        reason = "failed_ri_absolute_amount" if any("reference-intake cell is never" in e for e in errors) else "failed_other"
        out[reason] += len(product)
        return out
    if candidate.get("declined"):
        out["model_declined_usable_table"] += len(product)
        return out
    found, ambiguous = scoring.keyed_cells(candidate)
    unread = " ".join(candidate.get("warnings") or [])
    for key, cell in product.items():
        got = None if key in ambiguous else found.get(key)
        if scoring.strict_equal(cell, got):
            out["exact"] += 1
        elif got is None and cell["nutrient"].startswith("energy") and f"'{cell['decimal_text']}'" in unread:
            out["unit_in_row_label_value_unread"] += 1
        elif got is None and key in ambiguous:
            out["duplicate_cells"] += 1
        elif got is None:
            out["missing_cell"] += 1
        elif got.get("decimal_text") != cell.get("decimal_text"):
            out["value_misread"] += 1
        elif (got.get("comparator") or "=") != (cell.get("comparator") or "="):
            out["comparator_differs"] += 1
        else:
            out["unit_or_basis_differs"] += 1
    return out


def table_outcomes(truth: dict[str, Any], candidate: dict[str, Any] | None) -> Counter:
    """Why a non-exact usable table missed full-table credit (several reasons may apply)."""
    out: Counter = Counter()
    if truth.get("requires_decline"):
        return out
    result = scoring.score_case(candidate, truth)
    if result["tables_exact"]:
        out["exact"] += 1
        return out
    if result["failed"]:
        out["failed"] += 1
        return out
    if candidate is None or candidate.get("declined"):
        out["declined"] += 1
        return out
    expected, _ = scoring.keyed_cells(truth)
    found, ambiguous = scoring.keyed_cells(candidate)
    product_misses = sum(
        1 for k, c in expected.items() if c.get("basis") != "reference_intake" and not scoring.strict_equal(c, found.get(k))
    )
    ri_extra = [k for k in found if k not in expected and k[2] == "reference_intake"]
    other_extra = [k for k in found if k not in expected and k[2] != "reference_intake"]
    truth_has_ri = any(h.get("basis") == "reference_intake" for h in truth.get("headers") or [])
    if product_misses:
        out["product_cell_miss"] += 1
    if ri_extra and not truth_has_ri:
        out["ri_column_read_but_not_in_truth"] += 1
    elif ri_extra:
        out["ri_cells_keyed_differently"] += 1
    if other_extra or ambiguous:
        out["extra_or_duplicate_amount_cells"] += 1
    if result["conversions"] != result["conversions_exact"]:
        out["serving_conversion"] += 1
    return out


def amended_conversions(truth: dict[str, Any], candidate: dict[str, Any] | None) -> tuple[int, int]:
    """S1 counterfactual: compare printed mass or volume; count-only portions leave the denominator."""
    if truth.get("requires_decline"):
        return 0, 0
    usable = candidate is not None and not validate_candidate(candidate) and not candidate.get("declined")
    found, _ = scoring.keyed_cells(candidate) if usable and candidate else ({}, set())
    expected, _ = scoring.keyed_cells(truth)
    numerator = denominator = 0
    for key, cell in expected.items():
        conversion = cell.get("serving_conversion")
        if cell.get("basis") != "per_serving" or conversion in scoring.NOT_A_CONVERSION or printed_mass(conversion) is None:
            continue
        denominator += 1
        got = found.get(key)
        numerator += int(got is not None and printed_mass(got.get("serving_conversion")) == printed_mass(conversion))
    return numerator, denominator


def amended_wire(wire: dict[str, Any]) -> dict[str, Any]:
    """M1 and M2 counterfactuals applied to the saved wire answer (simulation only)."""
    wire = copy.deepcopy(wire)
    ri_headers = {h["header_id"] for h in wire.get("headers") or [] if h.get("basis") == "reference_intake"}
    for row in wire.get("rows") or []:
        label = str(row.get("printed_label") or "")
        label_units = [u for u in ("kJ", "kcal") if re.search(rf"\b{u}\b", label, re.IGNORECASE)]
        for value in row.get("values") or []:
            printed = str(value.get("printed_text") or "")
            parsed = parse_value(printed)
            if value.get("header_id") in ri_headers and parsed is not None and parsed["canonical_unit"] != "%":
                value["printed_text"] = "unknown"  # M1: an absolute RI value is left out, never a failure
            elif (
                parsed is None
                and row.get("nutrient") in ("energy_kj", "energy_kcal")
                and len(label_units) == 1
                and re.fullmatch(r"\s*\d+(?:[.,]\d+)?\s*", printed)
            ):
                value["printed_text"] = f"{printed.strip()}{label_units[0]}"  # M2: unit printed in the row label
    return wire


def diagnose(rows: list[dict[str, Any]]) -> dict[str, Any]:
    cells: Counter = Counter()
    conversions: Counter = Counter()
    tables: Counter = Counter()
    s1 = [0, 0]
    m_cells = [0, 0]
    m_tables = [0, 0]
    examples: dict[str, list[str]] = {}
    for row in rows:
        truth, candidate = row["truth"], row["candidate"]
        for name, counter, found in (
            ("cells", cells, cell_outcomes(truth, candidate)),
            ("conversions", conversions, conversion_outcomes(truth, candidate)),
            ("tables", tables, table_outcomes(truth, candidate)),
        ):
            counter.update(found)
            for reason in found:
                if reason not in ("exact", "exact_as_scored"):
                    examples.setdefault(f"{name}:{reason}", [])
                    if row["id"] not in examples[f"{name}:{reason}"] and len(examples[f"{name}:{reason}"]) < 3:
                        examples[f"{name}:{reason}"].append(row["id"])
        n, d = amended_conversions(truth, candidate)
        s1[0] += n
        s1[1] += d
        if truth.get("requires_decline"):
            continue
        remapped = candidate
        if row["answer"]:
            try:
                remapped = route_c_mapping.map_wire(
                    amended_wire(json.loads(row["answer"])), (candidate or {}).get("input_sha256", "0" * 64)
                )
            except (json.JSONDecodeError, KeyError, TypeError):
                remapped = candidate
        result = scoring.score_case(remapped, truth)
        m_cells[0] += result["cells_exact"]
        m_cells[1] += result["product_cells"]
        m_tables[0] += result["tables_exact"]
        m_tables[1] += result["usable_tables"]
    return {
        "product_cells": dict(sorted(cells.items())),
        "serving_conversions": dict(sorted(conversions.items())),
        "non_exact_tables": dict(sorted(tables.items())),
        "counterfactual_s1_conversions": {"numerator": s1[0], "denominator": s1[1]},
        "counterfactual_m1_m2_strict_cells": {"numerator": m_cells[0], "denominator": m_cells[1]},
        "counterfactual_m1_m2_full_table": {"numerator": m_tables[0], "denominator": m_tables[1]},
        "examples": examples,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--route-c-dir", default="route-c-dev")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    folder = args.runs / args.route_c_dir
    arms = {}
    for arm in ROUTE_C_ARMS:
        summary = json.loads((folder / f"{arm}-summary.json").read_text(encoding="utf-8"))
        cases = json.loads((folder / arm / "development-cases.json").read_text(encoding="utf-8"))
        arms[arm] = diagnose(_load(folder / arm / summary["inspect_log"], cases))
    result = {
        "stratum": "uk_en",
        "split": "development",
        "note": "Offline diagnosis; no API call. Counterfactuals are proposed amendments, not applied. Counts and case ids only.",
        "serving_regex": SERVING.pattern,
        "arms": arms,
    }
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    for arm, block in arms.items():
        print(arm, json.dumps({k: v for k, v in block.items() if k != "examples"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
