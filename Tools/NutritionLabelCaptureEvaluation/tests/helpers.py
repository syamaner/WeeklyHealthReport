"""Shared synthetic fixtures for the offline unit tests."""

from __future__ import annotations

import copy
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parents[1]
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from synthetic import render  # noqa: E402

HASH = "0" * 64


def muesli_truth() -> dict[str, Any]:
    return render.muesli_truth(HASH)


def candidate_from_truth(truth: dict[str, Any], *, ready: bool = True, route: str = "A") -> dict[str, Any]:
    """A schema-valid candidate that reproduces the truth exactly."""
    cells = []
    for cell in truth["cells"]:
        item = {
            k: cell[k]
            for k in (
                "row_id",
                "parent_row_id",
                "nutrient",
                "printed_label",
                "header_id",
                "basis",
                "printed_text",
                "comparator",
                "decimal_text",
                "unit",
                "canonical_unit",
                "serving_conversion",
            )
        }
        item.update({"persistence_authorized": False, "requires_user_selection": True})
        cells.append(item)
    return {
        "schema_version": "label-capture-candidate-v1",
        "route": route,
        "input_sha256": HASH,
        "status": "user_selection_only",
        "declined": False,
        "decline_reasons": [],
        "ready_for_confirmation": False,
        "would_mark_ready": ready,
        "automatic_save": False,
        "language": truth.get("language", "zh-Hant"),
        "serving_size": copy.deepcopy(truth["serving_size"]),
        "servings_per_pack": copy.deepcopy(truth["servings_per_pack"]),
        "headers": [{k: h[k] for k in ("header_id", "printed_text", "basis", "serving_conversion")} for h in truth["headers"]],
        "cells": cells,
        "warnings": [],
    }


def declined_candidate(reason: str = "no_table") -> dict[str, Any]:
    return {
        "schema_version": "label-capture-candidate-v1",
        "route": "A",
        "input_sha256": HASH,
        "status": "user_selection_only",
        "declined": True,
        "decline_reasons": [reason],
        "ready_for_confirmation": False,
        "would_mark_ready": False,
        "automatic_save": False,
        "language": "unknown",
        "serving_size": "unknown",
        "servings_per_pack": "unknown",
        "headers": [],
        "cells": [],
        "warnings": [],
    }
