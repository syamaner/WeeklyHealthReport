"""Deterministic cross-column arithmetic checks for printed nutrition tables."""

from __future__ import annotations

import statistics
from decimal import Decimal
from typing import Any


def inferred_serving_masses(cells: list[dict[str, Any]]) -> list[tuple[str, Decimal]]:
    by_row: dict[str, dict[str, dict[str, Any]]] = {}
    for cell in cells:
        if cell.get("comparator") is not None:
            continue
        if cell.get("basis") not in ("per_100g", "per_serving"):
            continue
        by_row.setdefault(cell["row_id"], {})[cell["basis"]] = cell
    masses = []
    for row_id, values in sorted(by_row.items()):
        if set(values) != {"per_100g", "per_serving"}:
            continue
        per_100 = Decimal(values["per_100g"]["decimal_text"].replace(",", "."))
        per_serving = Decimal(values["per_serving"]["decimal_text"].replace(",", "."))
        if per_100 > 0:
            masses.append((row_id, Decimal(100) * per_serving / per_100))
    return masses


def serving_consistency(cells: list[dict[str, Any]]) -> dict[str, Any]:
    masses = inferred_serving_masses(cells)
    if len(masses) < 4:
        return {"status": "insufficient_evidence", "detected": False, "usable_rows": len(masses)}
    median = Decimal(str(statistics.median(float(value) for _, value in masses)))
    tolerance = max(Decimal("0.5"), abs(median) * Decimal("0.05"))
    outliers = [row_id for row_id, value in masses if abs(value - median) > tolerance]
    return {
        "status": "inconsistent" if outliers else "consistent",
        "detected": bool(outliers),
        "usable_rows": len(masses),
        "median_serving_mass": str(median),
        "outlier_rows": outliers,
    }
