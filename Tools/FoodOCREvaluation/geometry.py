"""Pure geometry-aware baseline binding for Vision nutrition-panel tokens."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from arithmetic import serving_consistency
from parser import ParsedValue, classify_basis, normalize_label, parse_value

NUTRIENTS = (
    (re.compile(r"\benergy\b"), "energy"),
    (re.compile(r"\b(?:saturates|saturated fat|of which saturates)\b"), "saturates"),
    (re.compile(r"\b(?:fat|total fat)\b"), "fat"),
    (re.compile(r"\bcarbohydrate\b"), "carbohydrate"),
    (re.compile(r"\b(?:sugars|of which sugars)\b"), "sugars"),
    (re.compile(r"\bfib(?:re|er)\b"), "fibre"),
    (re.compile(r"\bprotein\b"), "protein"),
    (re.compile(r"\bsalt\b"), "salt"),
    (re.compile(r"\bsodium\b"), "sodium"),
)
PARENTS = {"saturates": "fat", "sugars": "carbohydrate"}


@dataclass(frozen=True)
class Token:
    text: str
    x: float
    y: float
    width: float
    height: float

    @property
    def mid_x(self) -> float:
        return self.x + self.width / 2


def tokens_from_raw(raw: dict[str, Any]) -> list[Token]:
    tokens = []
    for observation in raw.get("observations", []):
        for item in observation.get("tokens", []):
            box = item["boundingBox"]
            tokens.append(Token(item["text"], box["x"], box["y"], box["width"], box["height"]))
    return tokens


def cluster_lines(tokens: list[Token]) -> list[list[Token]]:
    lines: list[list[Token]] = []
    for token in sorted(tokens, key=lambda item: (-item.y, item.x)):
        matching = next(
            (line for line in lines if abs(sum(item.y for item in line) / len(line) - token.y) <= max(token.height, 0.012) * 0.55),
            None,
        )
        if matching is None:
            lines.append([token])
        else:
            matching.append(token)
    return [sorted(line, key=lambda item: item.x) for line in lines]


def nutrient_for(label: str, unit: str | None) -> str | None:
    normalized = normalize_label(label)
    for pattern, nutrient in NUTRIENTS:
        if pattern.search(normalized):
            if nutrient == "energy" and unit in ("kj", "kcal"):
                return f"energy_{unit}"
            return nutrient
    return None


def clean_numeric_token(value: str) -> str:
    return value.strip("*†‡,;:")


def header_candidates(line: list[Token]) -> list[tuple[str, str, float]]:
    candidates: list[tuple[str, str, float]] = []
    for index, token in enumerate(line):
        current = normalize_label(token.text).replace(" ", "")
        following = normalize_label(line[index + 1].text).replace(" ", "") if index + 1 < len(line) else ""
        phrase = f"{current}{following}"
        basis = None
        if current == "per" and following == "100g":
            basis = "per_100g"
        elif current == "per" and following == "100ml":
            basis = "per_100ml"
        elif current == "per" and following in ("serving", "portion", "pack"):
            basis = "per_serving"
        elif "%ri" in current or "referenceintake" in phrase:
            basis = "reference_intake"
        if basis:
            partner = line[index + 1] if current == "per" and index + 1 < len(line) else token
            candidates.append((basis, f"{token.text} {partner.text}".strip(), (token.mid_x + partner.mid_x) / 2))
    return candidates


def bind(raw: dict[str, Any]) -> dict[str, Any]:
    lines = cluster_lines(tokens_from_raw(raw))
    headers: list[dict[str, Any]] = []
    header_line_ids: set[int] = set()
    for observation in raw.get("observations", []):
        candidates = observation.get("candidates", [])
        text = candidates[0]["text"] if candidates else ""
        basis = classify_basis(text)
        if not basis:
            continue
        box = observation["boundingBox"]
        x = box["x"] + box["width"] / 2
        if any(item["basis"] == basis and abs(item["x"] - x) < 0.08 for item in headers):
            continue
        headers.append({
            "header_id": f"header_{len(headers) + 1}",
            "basis": basis,
            "text": text,
            "x": x,
        })
    for line_index, line in enumerate(lines):
        candidates = header_candidates(line)
        if not candidates:
            text = " ".join(token.text for token in line)
            basis = classify_basis(text)
            if basis:
                candidates = [(basis, text, sum(token.mid_x for token in line) / len(line))]
        for basis, text, x in candidates:
            if any(item["basis"] == basis and abs(item["x"] - x) < 0.08 for item in headers):
                continue
            headers.append({
                "header_id": f"header_{len(headers) + 1}",
                "basis": basis,
                "text": text,
                "x": x,
            })
        if candidates:
            header_line_ids.add(line_index)

    cells: list[dict[str, Any]] = []
    unresolved: list[str] = []
    seen: set[tuple[str, str]] = set()
    for line_index, line in enumerate(lines):
        if line_index in header_line_ids:
            continue
        parsed = [(token, parse_value(clean_numeric_token(token.text))) for token in line]
        values: list[tuple[Token, ParsedValue]] = [(token, value) for token, value in parsed if value is not None]
        if not values:
            continue
        first_value_x = min(token.x for token, _ in values)
        label = " ".join(token.text for token in line if token.x < first_value_x and parse_value(clean_numeric_token(token.text)) is None)
        for token, value in values:
            explicit_unit = value.unit
            normalized_label = normalize_label(label)
            if explicit_unit is None and "energy" in normalized_label:
                if "kcal" in normalized_label:
                    explicit_unit = "kcal"
                elif "kj" in normalized_label:
                    explicit_unit = "kj"
            nutrient = nutrient_for(label, explicit_unit)
            if nutrient is None:
                unresolved.append(f"unbound nutrient label: {label or '<empty>'}")
                continue
            if not headers:
                unresolved.append(f"no explicit basis header for {nutrient}")
                continue
            header = min(headers, key=lambda item: abs(item["x"] - token.mid_x))
            if len(headers) > 1:
                distances = sorted(abs(item["x"] - token.mid_x) for item in headers)
                if distances[1] - distances[0] < 0.02:
                    unresolved.append(f"ambiguous header binding for {nutrient}")
                    continue
            key = (nutrient, header["header_id"])
            if key in seen:
                unresolved.append(f"duplicate cell for {nutrient}/{header['header_id']}")
                continue
            seen.add(key)
            cells.append({
                "row_id": nutrient,
                "parent_row_id": PARENTS.get(nutrient),
                "header_id": header["header_id"],
                "basis": header["basis"],
                "printed_text": token.text,
                "comparator": value.comparator,
                "decimal_text": value.decimal_text,
                "unit": explicit_unit,
                "serving_conversion": None,
                "persistence_authorized": False,
            })
    if not cells:
        unresolved.append("no nutrition cells bound")
    arithmetic = serving_consistency(cells)
    if arithmetic["status"] == "inconsistent":
        unresolved.append("inconsistent per-100g/per-serving relationship")
    return {
        "headers": headers,
        "cells": cells,
        "arithmetic": arithmetic,
        "ready_for_confirmation": bool(cells) and not unresolved,
        "unresolved_warning": bool(unresolved),
        "declined": bool(unresolved),
        "unresolved_reasons": sorted(set(unresolved)),
    }
