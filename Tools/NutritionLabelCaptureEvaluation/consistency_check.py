#!/usr/bin/env python3
"""Mechanical per-serving against per-100 consistency check of a truth file (phase 5, #255). Offline.

For every usable record with a printed serving size in g or ml and both a per-serving and a
per-100 g or per-100 ml column, each nutrient printed as an exact value in both columns is
checked: per-100 should be about per-serving x 100 / serving size. Labels round each column
on its own, so the tolerance is the rounding of the per-serving value scaled up (half a unit
of its last printed digit, x 100 / serving size), plus half a unit of the per-100 value's last
digit, plus 5% of the expected value. Bounds and unknowns are not checked.

Limits: a comma is read as a decimal separator, so a thousands separator (`1,234`) would be
misread; a serving in ml against a per-100 g column (or the reverse) is compared without any
density, so a mixed pair is no real check; and an error that keeps both columns consistent is
invisible. It only lists inconsistencies; it never changes a value (the owner decides). With saved
untouched outputs it also reports whether each route C arm read the same two values as the truth.
"""

from __future__ import annotations

import argparse
import json
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent


def _decimal(text: Any) -> Decimal | None:
    try:
        return Decimal(str(text).replace(",", "."))
    except (InvalidOperation, ValueError):
        return None


def _half_unit(text: str) -> Decimal:
    digits = text.replace(",", ".").split(".")[1] if "." in text.replace(",", ".") else ""
    return Decimal(5) * Decimal(10) ** (-(len(digits) + 1))


def check_record(record: dict[str, Any]) -> list[dict[str, Any]]:
    """Pure: the inconsistent nutrient pairs of one truth record."""
    serving = record.get("serving_size")
    if not isinstance(serving, dict) or serving.get("canonical_unit") not in ("g", "ml"):
        return []
    size = _decimal(serving.get("decimal_text"))
    if not size:
        return []
    cells = [c for c in record.get("cells") or [] if (c.get("comparator") or "=") == "="]
    per_serving = {c["nutrient"]: c for c in cells if c.get("basis") == "per_serving"}
    per_100 = {c["nutrient"]: c for c in cells if c.get("basis") in ("per_100g", "per_100ml")}
    found = []
    for nutrient in sorted(set(per_serving) & set(per_100)):
        if nutrient == "unrecognised":
            continue
        s_text, h_text = str(per_serving[nutrient]["decimal_text"]), str(per_100[nutrient]["decimal_text"])
        s_value, h_value = _decimal(s_text), _decimal(h_text)
        if s_value is None or h_value is None:
            continue
        expected = s_value * Decimal(100) / size
        tolerance = _half_unit(s_text) * Decimal(100) / size + _half_unit(h_text) + abs(expected) * Decimal("0.05")
        if abs(h_value - expected) > tolerance:
            found.append(
                {
                    "case_id": record["case_id"],
                    "nutrient": nutrient,
                    "serving_size": serving.get("printed_text"),
                    "per_serving": per_serving[nutrient]["printed_text"],
                    "per_100": per_100[nutrient]["printed_text"],
                    "expected_per_100": str(expected.quantize(Decimal("0.01"))),
                    "tolerance": str(tolerance.quantize(Decimal("0.01"))),
                }
            )
    return found


def pairs(record: dict[str, Any]) -> int:
    """How many nutrients the check compares in one record (exact values in both columns)."""
    cells = [c for c in record.get("cells") or [] if (c.get("comparator") or "=") == "=" and c.get("nutrient") != "unrecognised"]
    serving = {c["nutrient"] for c in cells if c.get("basis") == "per_serving"}
    per_100 = {c["nutrient"] for c in cells if c.get("basis") in ("per_100g", "per_100ml")}
    return len(serving & per_100)


def model_readings(runs: Path, arms: tuple[str, ...]) -> dict[str, dict[str, Any]]:
    from rescore_untouched import saved_outputs

    readings = {}
    for arm in arms:
        (log,) = sorted((runs / arm / "untouched").glob("*.eval"))
        readings[arm] = saved_outputs(log)
    return readings


def agreement(issue: dict[str, Any], readings: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Whether each arm read the same per-serving and per-100 values as the truth for this nutrient."""
    out = {}
    for arm, outputs in readings.items():
        candidate = outputs.get(issue["case_id"]) or {}
        if candidate.get("declined") or not candidate.get("cells"):
            out[arm] = "declined or no table"
            continue
        values = {c.get("basis"): c.get("printed_text") for c in candidate["cells"] if c.get("nutrient") == issue["nutrient"]}
        per_100 = values.get("per_100g") or values.get("per_100ml")
        same = values.get("per_serving") == issue["per_serving"] and per_100 == issue["per_100"]
        out[arm] = "agrees with the truth" if same else f"reads per serving {values.get('per_serving')!r}, per 100 {per_100!r}"
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--truth", type=Path, default=HERE / "fixtures" / "ground-truth-off-taiwan-untouched-v1.json")
    parser.add_argument("--runs", type=Path, help="saved untouched runs, for model agreement")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    records = [r for r in json.loads(args.truth.read_text(encoding="utf-8"))["records"] if not r.get("excluded")]
    checked = [r for r in records if isinstance(r.get("serving_size"), dict) and r["serving_size"].get("canonical_unit") in ("g", "ml")]
    issues = [issue for record in records for issue in check_record(record)]
    if args.runs:
        readings = model_readings(args.runs, ("gemini-on", "sol-on", "luna-off"))
        for issue in issues:
            issue["models"] = agreement(issue, readings)
    summary = {
        "note": "Lists inconsistencies only; no value was changed (the owner decides).",
        "records_usable": len(records),
        "records_with_a_mass_or_volume_serving": len(checked),
        "records_with_both_columns": sum(1 for r in checked if pairs(r)),
        "nutrient_pairs_checked": sum(pairs(r) for r in checked),
        "inconsistencies": issues,
    }
    args.out.write_text(json.dumps(summary, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"records": len(records), "checked": len(checked), "inconsistencies": len(issues)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
