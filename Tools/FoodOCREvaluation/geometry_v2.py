"""Experimental, user-selection-only nutrition candidates from local Vision text.

The frozen v1 binder and gate artefacts are deliberately not changed. This
module may be tuned on their observed failures, but those panels cannot become
an untouched v2 acceptance test.
"""

from __future__ import annotations

import re
from copy import deepcopy
from typing import Any

from geometry import PARENTS, bind, nutrient_for
from parser import classify_basis, normalize_label, parse_value

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


def _mid_y(token: dict[str, Any]) -> float:
    box = token["boundingBox"]
    return box["y"] + box["height"] / 2


def _mid_x(token: dict[str, Any]) -> float:
    box = token["boundingBox"]
    return box["x"] + box["width"] / 2


def _supplemental_rows(prepared: dict[str, Any], headers: list[dict[str, Any]],
                       existing: set[tuple[str, str]]) -> tuple[list[dict[str, Any]], set[str]]:
    """Recover explicit label/value pairs split into nearby observations.

    A value must have one closest label and one unambiguous explicit basis. The
    extra candidates remain unapproved and are never used to infer coverage.
    """
    if not headers:
        return [], set()
    observations = prepared.get("observations", [])
    header_y = [
        max((_mid_y(token) for token in obs.get("tokens", [])), default=0)
        for obs in observations
        if classify_basis(" ".join(token["text"] for token in obs.get("tokens", [])))
    ]
    if not header_y:
        return [], set()
    table_top = max(header_y) + 0.025
    boundaries = [
        max((_mid_y(token) for token in obs.get("tokens", [])), default=0)
        for obs in observations
        if normalize_label(" ".join(token["text"] for token in obs.get("tokens", []))).startswith("ingredients")
    ]
    table_bottom = max(boundaries) if boundaries else 0
    labels: list[tuple[float, float, str, str]] = []
    values: list[dict[str, Any]] = []
    for obs in observations:
        tokens = obs.get("tokens", [])
        if not tokens:
            continue
        line_y = sum(_mid_y(token) for token in tokens) / len(tokens)
        if not table_bottom + 0.01 < line_y < table_top:
            continue
        line_text = " ".join(token["text"] for token in tokens)
        label = nutrient_for(line_text, None)
        if label:
            label_tokens = [token for token in tokens if parse_value(token["text"]) is None]
            if label_tokens:
                labels.append((line_y, max(_mid_x(token) for token in label_tokens), label, line_text))
        values.extend(token for token in tokens if parse_value(token["text"]) is not None)

    supplemental: list[dict[str, Any]] = []
    warnings: set[str] = set()
    for token in values:
        parsed = parse_value(token["text"])
        assert parsed is not None
        nearest = sorted(
            (abs(_mid_y(token) - y), row, label_text)
            for y, label_x, row, label_text in labels
            if _mid_x(token) > label_x and abs(_mid_y(token) - y) <= 0.045
        )
        if not nearest or (len(nearest) > 1 and nearest[1][0] - nearest[0][0] < 0.008):
            continue
        _, row, label_text = nearest[0]
        unit = parsed.unit
        if row == "energy" and unit is None:
            normalized = normalize_label(label_text)
            if "kcal" in normalized:
                unit = "kcal"
            elif "kj" in normalized:
                unit = "kj"
        if row == "energy":
            if unit not in ("kj", "kcal"):
                warnings.add("energy unit is not explicit")
                continue
            row = f"energy_{unit}"
        header_distance = sorted(
            ((abs(item["x"] - _mid_x(token)), item) for item in headers),
            key=lambda pair: pair[0],
        )
        if len(header_distance) > 1 and header_distance[1][0] - header_distance[0][0] < 0.02:
            warnings.add(f"ambiguous header binding for {row}")
            continue
        header = header_distance[0][1]
        if sum(item["basis"] == header["basis"] for item in headers) != 1:
            warnings.add(f"repeated header basis for {row}")
            continue
        key = (row, header["basis"])
        if key in existing:
            continue
        existing.add(key)
        supplemental.append({
            "row_id": row,
            "parent_row_id": PARENTS.get(row),
            "header_id": header["header_id"],
            "basis": header["basis"],
            "printed_text": token["text"],
            "comparator": parsed.comparator,
            "decimal_text": parsed.decimal_text,
            "unit": "kJ" if unit == "kj" else unit,
            "serving_conversion": None,
            "persistence_authorized": False,
            "requires_user_selection": True,
        })
    return supplemental, warnings


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

    existing = {(cell["row_id"], cell["basis"]) for cell in candidates}
    extra, extra_warnings = _supplemental_rows(prepared, bound["headers"], existing)
    candidates.extend(extra)
    reasons.update(extra_warnings)

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
