"""Validate a candidate against `candidate-schema-v1.json` without third-party packages.

Implements only the JSON Schema keywords that file uses (type, enum, const,
required, properties, additionalProperties false, items, $ref, oneOf, pattern),
so CI can validate offline. An invalid candidate is scored as `failed`, a state
distinct from declined, and stays in every denominator.
"""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

SCHEMA_PATH = Path(__file__).resolve().parent / "candidate-schema-v1.json"
TYPES = {
    "object": dict, "array": list, "string": str, "boolean": bool, "null": type(None),
}


@lru_cache(maxsize=1)
def schema() -> dict[str, Any]:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def _resolve(node: dict[str, Any]) -> dict[str, Any]:
    while "$ref" in node:
        ref = node["$ref"]
        if not ref.startswith("#/$defs/"):
            raise ValueError(f"unsupported reference {ref}")
        node = schema()["$defs"][ref.removeprefix("#/$defs/")]
    return node


def _type_ok(value: Any, expected: str | list[str]) -> bool:
    names = [expected] if isinstance(expected, str) else expected
    for name in names:
        if name == "boolean" and isinstance(value, bool):
            return True
        if name != "boolean" and isinstance(value, TYPES[name]) and not isinstance(value, bool):
            return True
    return False


def _validate(value: Any, node: dict[str, Any], path: str, errors: list[str]) -> None:
    node = _resolve(node)
    if "oneOf" in node:
        passing = [option for option in node["oneOf"] if not _collect(value, option, path)]
        if len(passing) != 1:
            errors.append(f"{path}: matches {len(passing)} of oneOf")
        return
    if "const" in node and (value != node["const"] or type(value) is not type(node["const"])):
        errors.append(f"{path}: must be {node['const']!r}")
        return
    if "enum" in node and value not in node["enum"]:
        errors.append(f"{path}: {value!r} not in enum")
        return
    if "type" in node and not _type_ok(value, node["type"]):
        errors.append(f"{path}: wrong type")
        return
    if "pattern" in node and isinstance(value, str) and not re.search(node["pattern"], value):
        errors.append(f"{path}: does not match pattern")
    if isinstance(value, dict):
        for key in node.get("required", []):
            if key not in value:
                errors.append(f"{path}.{key}: required")
        properties = node.get("properties", {})
        for key, item in value.items():
            if key in properties:
                _validate(item, properties[key], f"{path}.{key}", errors)
            elif node.get("additionalProperties") is False:
                errors.append(f"{path}.{key}: not allowed")
    if isinstance(value, list) and "items" in node:
        for index, item in enumerate(value):
            _validate(item, node["items"], f"{path}[{index}]", errors)


def _collect(value: Any, node: dict[str, Any], path: str) -> list[str]:
    errors: list[str] = []
    _validate(value, node, path, errors)
    return errors


def validate_candidate(candidate: Any) -> list[str]:
    """Return schema and policy errors; an empty list means valid."""
    errors = _collect(candidate, schema(), "$")
    if errors or not isinstance(candidate, dict):
        return errors
    if candidate["declined"] and candidate["cells"]:
        errors.append("$.cells: a declined candidate keeps every cell unknown (no cells)")
    if candidate["declined"] and not candidate["decline_reasons"]:
        errors.append("$.decline_reasons: a decline must list its reasons")
    if candidate["declined"] and candidate["would_mark_ready"]:
        errors.append("$.would_mark_ready: a declined table can never be ready")
    header_ids = {h["header_id"]: h["basis"] for h in candidate["headers"]}
    for index, cell in enumerate(candidate["cells"]):
        if header_ids.get(cell["header_id"]) != cell["basis"]:
            errors.append(f"$.cells[{index}]: header and basis do not agree")
        if cell["basis"] == "reference_intake" and cell["canonical_unit"] != "%":
            errors.append(f"$.cells[{index}]: a reference-intake cell is never a product amount")
        if cell["basis"] != "per_serving" and cell["serving_conversion"] not in ("not_applicable", "unknown"):
            errors.append(f"$.cells[{index}]: only per-serving cells carry a serving conversion")
    return errors
