"""Route C wire output (`label-image-wire-schema-v1`) to `label-capture-candidate-v1`. Pure; no I/O.

The model returns printed text only. This mapping reads each printed value with the same
closed value grammar as the truth drafting (`draft_untouched_truth.parse_value`): a
comparator, a decimal and a printed unit, with the canonical unit taken from a closed
table. It never converts, infers or fills a value:

- a value printed as `unknown`, or text that is not a printed amount (such as `*`), is
  left out as a cell and recorded in `warnings`; nothing stands in for it;
- a value whose header the model did not declare is left out the same way;
- a parent is kept only when it names another row of the same table (a self-parent or a
  parent absent from the table is no parent).

`would_mark_ready` (what route C would offer as ready; the shared arithmetic policy can
still block it) is true only when the model did not decline, the language is English or
Traditional Chinese, at least one amount cell was read, no amount value was left out,
no two cells share a row and column, and every per-serving column has a printed serving
quantity. `ready_for_confirmation` and `automatic_save` stay false.
"""

from __future__ import annotations

import re
from typing import Any

from draft_untouched_truth import SERVING, SERVINGS, UNITS, parse_value

SCHEMA_VERSION = "label-capture-candidate-v1"
SERVINGS_EN = re.compile(r"(about|approx\.?|approximately)?\s*(\d+(?:\.\d+)?)\s*servings?", re.IGNORECASE)
SERVINGS_EN_TRAILING = re.compile(r"servings?\s+per\s+(?:container|pack(?:age)?)\D*?(about\s+)?(\d+(?:\.\d+)?)", re.IGNORECASE)
LANGUAGES = {"en", "zh-Hant", "mixed"}


def _serving_size(text: str) -> dict[str, Any] | str:
    if not text or text.strip().lower() == "unknown":
        return "unknown"
    match = SERVING.search(text)
    if not match:
        return {"printed_text": text, "decimal_text": None, "unit": None, "canonical_unit": None}
    unit = match.group(2)
    return {
        "printed_text": text,
        "decimal_text": match.group(1),
        "unit": unit,
        "canonical_unit": UNITS.get(unit) or UNITS.get(unit.lower()),
    }


def _servings_per_pack(text: str) -> dict[str, Any] | str:
    if not text or text.strip().lower() == "unknown":
        return "unknown"
    match = SERVINGS.search(text)
    if match:
        return {"printed_text": text, "decimal_text": match.group(2), "approximate": match.group(1) is not None}
    match = SERVINGS_EN_TRAILING.search(text) or SERVINGS_EN.search(text)
    if match:
        return {"printed_text": text, "decimal_text": match.group(2), "approximate": match.group(1) is not None}
    return "unknown"


def declined_candidate(
    input_sha256: str, reasons: list[str], language: str = "unknown", warnings: list[str] | None = None
) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "route": "C",
        "input_sha256": input_sha256,
        "status": "user_selection_only",
        "declined": True,
        "decline_reasons": reasons or ["declined_without_reason"],
        "ready_for_confirmation": False,
        "would_mark_ready": False,
        "automatic_save": False,
        "language": language if language in LANGUAGES | {"unknown"} else "unknown",
        "serving_size": "unknown",
        "servings_per_pack": "unknown",
        "headers": [],
        "cells": [],
        "warnings": warnings or [],
    }


def map_wire(wire: dict[str, Any], input_sha256: str) -> dict[str, Any]:
    """One candidate from one schema-valid wire response."""
    language = str(wire.get("language") or "unknown")
    if wire.get("declined"):
        return declined_candidate(input_sha256, [str(r) for r in wire.get("decline_reasons") or []], language)
    warnings: list[str] = []
    serving = _serving_size(str(wire.get("serving_size_text") or "unknown"))
    pack = _servings_per_pack(str(wire.get("servings_per_pack_text") or "unknown"))
    serving_quantity = f"{serving['decimal_text']}{serving['unit']}" if isinstance(serving, dict) and serving.get("decimal_text") else None
    headers: dict[str, dict[str, Any]] = {}
    for header in wire.get("headers") or []:
        if header["header_id"] in headers:
            warnings.append(f"duplicate_header_id: {header['header_id']}")
            continue
        headers[header["header_id"]] = {
            "header_id": header["header_id"],
            "printed_text": header["printed_text"],
            "basis": header["basis"],
            "serving_conversion": serving_quantity if header["basis"] == "per_serving" else None,
        }
    rows = wire.get("rows") or []
    row_ids: list[str] = []
    seen: dict[str, int] = {}
    for index, row in enumerate(rows, start=1):
        base = row["nutrient"] if row["nutrient"] != "unrecognised" else f"row_{index}"
        seen[base] = seen.get(base, 0) + 1
        row_ids.append(base if seen[base] == 1 else f"{base}_{seen[base]}")
    present = set(row_ids)
    cells: list[dict[str, Any]] = []
    left_out_amounts = 0
    for row, row_id in zip(rows, row_ids, strict=True):
        parent = str(row.get("parent_nutrient") or "").strip()
        parent_row = parent if parent and parent not in ("none", "unknown", row_id, row["nutrient"]) and parent in present else None
        for value in row.get("values") or []:
            header = headers.get(value["header_id"])
            printed = str(value.get("printed_text") or "")
            if header is None:
                warnings.append(f"value_without_header: {row_id} {value['header_id']}")
                left_out_amounts += 1
                continue
            parsed = None if printed.strip().lower() == "unknown" else parse_value(printed)
            if parsed is None:
                warnings.append(f"value_not_read: {row_id} {header['header_id']} {printed!r}")
                if header["basis"] != "reference_intake":
                    left_out_amounts += 1
                continue
            cells.append(
                {
                    "row_id": row_id,
                    "parent_row_id": parent_row,
                    "nutrient": row["nutrient"],
                    "printed_label": row["printed_label"],
                    "header_id": header["header_id"],
                    "basis": header["basis"],
                    "printed_text": printed,
                    **parsed,
                    "serving_conversion": (serving_quantity or "unknown") if header["basis"] == "per_serving" else "not_applicable",
                    "persistence_authorized": False,
                    "requires_user_selection": True,
                }
            )
    pairs = [(c["row_id"], c["header_id"]) for c in cells]
    duplicates = len(pairs) != len(set(pairs))
    if duplicates:
        warnings.append("duplicate_cells")
    serving_missing = any(h["basis"] == "per_serving" for h in headers.values()) and serving_quantity is None
    if serving_missing:
        warnings.append("per_serving_without_printed_serving_quantity")
    amount_cells = [c for c in cells if c["basis"] != "reference_intake"]
    ready = (
        language in LANGUAGES
        and bool(amount_cells)
        and left_out_amounts == 0
        and not duplicates
        and not serving_missing
        and not any(w.startswith("duplicate_header_id") for w in warnings)
    )
    return {
        "schema_version": SCHEMA_VERSION,
        "route": "C",
        "input_sha256": input_sha256,
        "status": "user_selection_only",
        "declined": False,
        "decline_reasons": [],
        "ready_for_confirmation": False,
        "would_mark_ready": ready,
        "automatic_save": False,
        "language": language if language in LANGUAGES | {"unknown"} else "unknown",
        "serving_size": serving,
        "servings_per_pack": pack,
        "headers": list(headers.values()),
        "cells": cells,
        "warnings": warnings,
    }
