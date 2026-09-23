"""Experimental, user-selection-only nutrition candidates from local Vision text.

The frozen v1 binder and gate artefacts are deliberately not changed. This
module may be tuned on their observed failures, but those panels cannot become
an untouched v2 acceptance test.
"""

from __future__ import annotations

import re
from copy import deepcopy
from typing import Any

from geometry import bind
from parser import parse_value

UNITS = {"g", "mg", "µg", "ug", "kj", "kcal", "ml", "%"}
REQUIRED_ROWS = {"fat", "saturates", "carbohydrate", "sugars", "protein", "salt"}
ENERGY_SLASH = re.compile(r"^(kJ|kcal)/(\d+(?:[.,]\d+)?)$", re.IGNORECASE)


def _joined_box(first: dict[str, Any], last: dict[str, Any]) -> dict[str, float]:
    left = first["boundingBox"]
    right = last["boundingBox"]
    return {
        "x": left["x"],
        "y": min(left["y"], right["y"]),
        "width": max(left["x"] + left["width"], right["x"] + right["width"]) - left["x"],
        "height": max(left["y"] + left["height"], right["y"] + right["height"]) - min(left["y"], right["y"]),
    }


def _close(first: dict[str, Any], second: dict[str, Any]) -> bool:
    a, b = first["boundingBox"], second["boundingBox"]
    gap = b["x"] - a["x"] - a["width"]
    vertical = abs((a["y"] + a["height"] / 2) - (b["y"] + b["height"] / 2))
    return -0.005 <= gap <= 0.025 and vertical <= max(a["height"], b["height"]) * 0.5


def _merge(first: dict[str, Any], last: dict[str, Any], text: str) -> dict[str, Any]:
    return {"text": text, "boundingBox": _joined_box(first, last)}


def _expand_token(token: dict[str, Any]) -> list[dict[str, Any]]:
    text = token["text"]
    if text.startswith("(") and text.endswith(")") and parse_value(text[1:-1]):
        return [{**deepcopy(token), "text": text[1:-1]}]
    match = ENERGY_SLASH.fullmatch(text)
    if not match:
        return [deepcopy(token)]
    box = token["boundingBox"]
    # Vision supplied one combined box. Partition it only to keep the two
    # printed values in reading order; these are not source-accurate boxes.
    unit_width = box["width"] * len(match.group(1)) / len(text)
    number_x = box["x"] + box["width"] * (len(match.group(1)) + 1) / len(text)
    return [
        {"text": match.group(1), "boundingBox": {**box, "width": unit_width}},
        {"text": match.group(2), "boundingBox": {**box, "x": number_x,
                                                   "width": box["x"] + box["width"] - number_x}},
    ]


def join_value_tokens(tokens: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Join only adjacent comparator/value/unit pieces within one observation.

    Do not change a value across a gap or across observations: either can be a
    different table column. Geometry remains tied to the source observation.
    """
    tokens = [part for token in tokens for part in _expand_token(token)]
    result: list[dict[str, Any]] = []
    index = 0
    while index < len(tokens):
        first = tokens[index]
        value = first["text"]
        end = index
        if value in ("<", "<=", "≤") and index + 1 < len(tokens):
            following = tokens[index + 1]
            if _close(first, following) and parse_value(value + following["text"]):
                value += following["text"]
                end += 1
        if end + 1 < len(tokens):
            following = tokens[end + 1]
            parsed = parse_value(value)
            if (parsed is not None and parsed.unit is None
                    and following["text"].casefold() in UNITS
                    and _close(tokens[end], following)):
                value += following["text"]
                end += 1
        result.append(_merge(first, tokens[end], value) if end > index else deepcopy(first))
        index = end + 1
    return result


def candidate_review(raw: dict[str, Any]) -> dict[str, Any]:
    """Return OCR suggestions, never a complete or savable table."""
    prepared = deepcopy(raw)
    for observation in prepared.get("observations", []):
        observation["tokens"] = join_value_tokens(observation.get("tokens", []))
    bound = bind(prepared)
    reasons = set(bound["unresolved_reasons"])
    candidates = []
    for cell in bound["cells"]:
        item = dict(cell)
        if item["unit"] == "kj":
            item["unit"] = "kJ"
        if item["row_id"] == "energy" or (item["row_id"].startswith("energy") and item["unit"] is None):
            reasons.add("energy unit is not explicit")
            continue
        item["persistence_authorized"] = False
        item["requires_user_selection"] = True
        candidates.append(item)

    found = {cell["row_id"] for cell in candidates}
    if not ({"energy_kj", "energy_kcal"} & found):
        reasons.add("energy value or unit not established")
    missing = REQUIRED_ROWS - found
    if missing:
        reasons.add("unresolved core rows: " + ", ".join(sorted(missing)))
    if any(header["basis"] == "per_serving" for header in bound["headers"]):
        reasons.add("serving conversion is not established")
    bound_markers = sum(
        token["text"].lstrip().startswith(("<", "≤"))
        for observation in raw.get("observations", []) for token in observation.get("tokens", [])
    )
    bound_candidates = sum(cell["comparator"] is not None for cell in candidates)
    if bound_markers > bound_candidates:
        reasons.add("printed bound marker not bound to a candidate")

    # Even apparently complete OCR is only a suggestion. The v1 false-ready
    # cases prove that absence of a warning is not evidence of table coverage.
    reasons.add("field-by-field image comparison and user selection required")
    return {
        "schema_version": 2,
        "image_sha256": raw.get("imageSHA256"),
        "status": "user_selection_only",
        "candidates": candidates,
        "unresolved_reasons": sorted(reasons),
        "ready_for_confirmation": False,
        "unresolved_warning": True,
        "declined": True,
        "automatic_save": False,
    }
