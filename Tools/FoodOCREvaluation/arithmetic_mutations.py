"""Frozen real-label mutation probes for the arithmetic safety policy."""

from __future__ import annotations

import hashlib
from decimal import Decimal
from typing import Any

from arithmetic import serving_consistency

ORDINARY_ROWS = {"energy_kj", "energy_kcal", "fat", "saturates", "carbohydrate", "sugars", "fibre", "protein", "salt", "sodium"}
MUTATIONS = (
    "multiply one per-serving ordinary nutrient by 10",
    "swap per-100 and per-serving header bindings",
    "replace one bounded value with an exact value",
)


def mutation_probes(manifest: dict[str, Any], seed: str) -> dict[str, list[dict[str, Any]]]:
    gate = [panel for panel in manifest["panels"] if panel["split"] == "untouched_gate"]
    result: dict[str, list[dict[str, Any]]] = {}
    for mutation in MUTATIONS:
        candidates: list[tuple[str, dict[str, Any], str, int, int | None]] = []
        for panel in gate:
            cells = panel["ground_truth"]["cells"]
            if mutation != MUTATIONS[2] and serving_consistency(cells)["status"] != "consistent":
                continue
            if mutation == MUTATIONS[2]:
                for index, cell in enumerate(cells):
                    if cell.get("comparator") is not None:
                        key = hashlib.sha256(f"{seed}:{mutation}:{panel['panel_id']}:{cell['row_id']}:{index}".encode()).hexdigest()
                        candidates.append((key, panel, cell["row_id"], index, None))
                continue
            by_row: dict[str, dict[str, int]] = {}
            for index, cell in enumerate(cells):
                if cell["row_id"] in ORDINARY_ROWS and cell.get("comparator") is None:
                    by_row.setdefault(cell["row_id"], {})[cell["basis"]] = index
            for row_id, indices in by_row.items():
                if "per_100g" not in indices or "per_serving" not in indices:
                    continue
                key = hashlib.sha256(f"{seed}:{mutation}:{panel['panel_id']}:{row_id}".encode()).hexdigest()
                candidates.append((key, panel, row_id, indices["per_serving"], indices["per_100g"]))
        if not candidates:
            raise ValueError(f"no real-label candidate for arithmetic mutation: {mutation}")
        _, panel, row_id, index, other = min(candidates, key=lambda item: item[0])
        mutated = [dict(cell) for cell in panel["ground_truth"]["cells"]]
        if mutation == MUTATIONS[0]:
            value = Decimal(mutated[index]["decimal_text"].replace(",", "."))
            mutated[index]["decimal_text"] = str(value * 10)
        elif mutation == MUTATIONS[1]:
            assert other is not None
            mutated[index]["basis"], mutated[other]["basis"] = mutated[other]["basis"], mutated[index]["basis"]
        else:
            mutated[index]["comparator"] = None
        check = serving_consistency(mutated)
        result.setdefault(panel["panel_id"], []).append({
            "mutation": mutation,
            "row_id": row_id,
            "detected": check["status"] == "inconsistent",
            "check_status": check["status"],
        })
    return result
