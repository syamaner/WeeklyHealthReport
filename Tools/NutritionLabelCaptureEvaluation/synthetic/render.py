"""Frozen, deterministic pasted-text renderers (plan section 3.1). Pure; no I/O.

Every case is synthetic: it is rendered from verified ground truth (English) or from
manufacturer-supplied Taiwan FDA dataset 188 rows that pass an internal-consistency
check, in a closed set of paste shapes. Route A on these cases measures the parser
against clean text in known shapes, not real-world copy and paste.

Rendering rules that touch values:
- A value is rendered as `<comparator><decimal_text><unit>` from the truth fields, so
  the printed unit is always present even where the panel printed it elsewhere; the
  truth record's `printed_text` is the rendered text.
- Panels whose ground truth cannot be rendered unambiguously (a blank cell in an amount
  column, or two same-basis columns whose printed headers were not recorded) are
  excluded with a logged reason, never repaired.
"""

from __future__ import annotations

import hashlib
import re
from collections import Counter, OrderedDict
from decimal import Decimal
from typing import Any

GENERATOR_VERSION = "label-pasted-text-renderer-v1"
SEED = "nutrition-label-capture-v1"
ENGLISH_SHAPES = ("tab", "spaced", "one_per_line", "wrapped")
CHINESE_SHAPES = ("fullwidth", "tab", "one_per_line", "spaced_units")

KNOWN = {"energy_kj", "energy_kcal", "fat", "saturates", "trans_fat", "carbohydrate", "sugars", "fibre", "protein", "salt", "sodium"}
ENGLISH_LABELS = {
    "energy": "Energy",
    "fat": "Fat",
    "saturates": "saturates",
    "trans_fat": "trans fat",
    "carbohydrate": "Carbohydrate",
    "sugars": "sugars",
    "fibre": "Fibre",
    "protein": "Protein",
    "salt": "Salt",
    "sodium": "Sodium",
}
UNIT_PRINT = {"kj": "kJ", "kJ": "kJ", "kcal": "kcal", "cal": "cal", "g": "g", "mg": "mg", "µg": "µg", "%": "%"}
CANONICAL = {
    "kJ": "kJ",
    "kcal": "kcal",
    "cal": "cal",
    "g": "g",
    "mg": "mg",
    "µg": "µg",
    "ml": "ml",
    "%": "%",
    "大卡": "kcal",
    "公克": "g",
    "毫克": "mg",
    "毫升": "ml",
}
CHINESE_ROWS = [
    ("熱量", "energy_kcal", None, "大卡"),
    ("蛋白質", "protein", None, "公克"),
    ("脂肪", "fat", None, "公克"),
    ("飽和脂肪", "saturates", "fat", "公克"),
    ("反式脂肪", "trans_fat", "fat", "公克"),
    ("碳水化合物", "carbohydrate", None, "公克"),
    ("糖", "sugars", "carbohydrate", "公克"),
    ("膳食纖維", "fibre", "carbohydrate", "公克"),
    ("鈉", "sodium", None, "毫克"),
]
SIMPLIFIED = {"營養標示": "营养标示", "熱量": "热量", "蛋白質": "蛋白质", "飽和脂肪": "饱和脂肪", "膳食纖維": "膳食纤维", "鈉": "钠"}


def digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def choose(options: tuple[str, ...], *parts: str) -> str:
    return options[int(digest(":".join((SEED,) + parts))[:8], 16) % len(options)]


# --- English, from reviewed ground truth -------------------------------------------


def _nutrient(row_id: str) -> tuple[str, bool]:
    """Map a v1/v2 ground-truth row id to (nutrient key or label stem, is_reference_row)."""
    base, reference = row_id, False
    for suffix in ("_ri", "_nrv"):
        if row_id.endswith(suffix):
            base, reference = row_id[: -len(suffix)], True
    if base in ("energy_cal", "energy"):
        base = "energy_kcal"
    return base, reference


def _english_label(stem: str) -> str:
    if stem in ENGLISH_LABELS:
        return ENGLISH_LABELS[stem]
    words = stem.replace("_", " ").split()
    return " ".join(w.upper() if re.fullmatch(r"b\d+", w) else w.capitalize() for w in words)


def _value_text(cell: dict[str, Any]) -> str:
    unit = UNIT_PRINT.get(cell.get("unit") or "", cell.get("unit") or "")
    comparator = cell.get("comparator") or ""
    return f"{comparator}{cell['decimal_text']}{unit}"


def english_truth(panel_id: str, ground_truth: dict[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    """Build an English truth record and its row model, or (None, exclusion reason)."""
    cells = ground_truth.get("cells") or []
    if ground_truth.get("requires_decline") or not cells:
        return None, "panel requires a decline in the image ground truth"
    header_cells: dict[str, list[dict[str, Any]]] = OrderedDict()
    for cell in sorted(cells, key=lambda c: int(re.sub(r"\D", "", c["header_id"]) or 0)):
        header_cells.setdefault(cell["header_id"], []).append(cell)
    headers = []
    for header_id, group in header_cells.items():
        bases = {c["basis"] for c in group}
        if len(bases) != 1:
            return None, "a ground-truth header mixes bases"
        basis = bases.pop()
        conversions = Counter(c["serving_conversion"] for c in group if c.get("serving_conversion"))
        conversion = conversions.most_common(1)[0][0] if conversions else None
        printed = {"per_100g": "Per 100g", "per_100ml": "Per 100ml", "reference_intake": "%RI*"}.get(basis)
        if basis == "per_serving":
            printed = f"Per serving ({conversion})" if conversion else "Per serving"
        headers.append({"header_id": header_id, "printed_text": printed, "basis": basis, "serving_conversion": conversion})
    texts = Counter((h["basis"], h["printed_text"]) for h in headers)
    if any(count > 1 for count in texts.values()):
        return None, "two same-basis columns whose printed headers were not recorded"
    amount_headers = [h["header_id"] for h in headers if h["basis"] != "reference_intake"]

    rows: OrderedDict[str, dict[str, Any]] = OrderedDict()
    truth_cells = []
    conversion_by_header = {h["header_id"]: h["serving_conversion"] for h in headers}
    # A reference-intake cell sits in the same printed row as its product cells, so it
    # takes that row's parent; the v1/v2 reviews recorded RI rows without a parent.
    row_parents = {}
    for cell in cells:
        stem, reference = _nutrient(cell["row_id"])
        if not reference and cell.get("parent_row_id"):
            row_parents[stem] = _nutrient(cell["parent_row_id"])[0]
    has_kcal = any(_nutrient(c["row_id"])[0] == "energy_kcal" and c["basis"] != "reference_intake" for c in cells)
    for cell in cells:
        stem, reference = _nutrient(cell["row_id"])
        reference = reference or cell["basis"] == "reference_intake"
        if reference and stem in ("energy_kj", "energy_kcal") and has_kcal:
            stem = "energy_kcal"  # convention: one energy %RI per row, keyed to kcal when printed
        row_stem = "energy" if stem in ("energy_kj", "energy_kcal") else stem
        parent_stem = _nutrient(cell["parent_row_id"])[0] if cell.get("parent_row_id") else None
        if reference and parent_stem is None:
            parent_stem = row_parents.get(stem)
        row = rows.setdefault(row_stem, {"stem": row_stem, "parent": parent_stem, "cells": []})
        row["cells"].append(cell)
        label = _english_label(row_stem)
        if parent_stem:
            label = f"of which {label}"
        truth_cells.append(
            {
                "row_id": stem if stem in KNOWN else f"row_{row_stem}",
                "parent_row_id": parent_stem,
                "nutrient": stem if stem in KNOWN else "unrecognised",
                "printed_label": label,
                "header_id": cell["header_id"],
                "basis": cell["basis"],
                "printed_text": _value_text(cell),
                "comparator": cell.get("comparator") or "=",
                "decimal_text": cell["decimal_text"],
                "unit": UNIT_PRINT.get(cell.get("unit") or "", cell.get("unit") or ""),
                "canonical_unit": CANONICAL.get(UNIT_PRINT.get(cell.get("unit") or "", ""), cell.get("unit")),
                # The rendered header prints one serving quantity per column; truth follows the rendered text.
                "serving_conversion": (conversion_by_header.get(cell["header_id"]) or "unknown")
                if cell["basis"] == "per_serving"
                else "not_applicable",
            }
        )
    for row in rows.values():
        unit_groups: dict[str, list[str]] = {}
        for cell in row["cells"]:
            if cell["basis"] == "reference_intake":
                continue
            unit_groups.setdefault(CANONICAL.get(UNIT_PRINT.get(cell.get("unit") or "", ""), "?"), []).append(cell["header_id"])
        for header_ids in unit_groups.values():
            if sorted(header_ids) != sorted(amount_headers):
                return None, "a row has a blank cell in an amount column"
        if any(c.get("unit") in (None, "") for c in row["cells"]):
            return None, "a ground-truth cell has no unit"
    truth = {
        "case_id": panel_id,
        "requires_decline": False,
        "decline_reason": None,
        "language": "en",
        "headers": headers,
        "serving_size": "unknown",
        "servings_per_pack": "unknown",
        "cells": truth_cells,
    }
    truth["_rows"] = list(rows.values())
    return truth, None


def render_english(truth: dict[str, Any], shape: str) -> str:
    headers = truth["headers"]
    amount = [h for h in headers if h["basis"] != "reference_intake"]
    reference = [h for h in headers if h["basis"] == "reference_intake"]
    lines: list[str] = []
    separator = "\t" if shape in ("tab", "wrapped") else "    "
    if shape == "one_per_line":
        lines.append("Typical values")
        lines.extend(h["printed_text"] for h in headers)
    else:
        lines.append(separator.join(["Typical values"] + [h["printed_text"] for h in headers]))
    for row in truth["_rows"]:
        label = _english_label(row["stem"])
        if row["parent"]:
            label = f"of which {label}"
        by_header = {}
        for cell in row["cells"]:
            by_header.setdefault(cell["header_id"], []).append(cell)
        groups: list[list[str]] = []
        if row["stem"] == "energy":
            order = []
            for cell in row["cells"]:
                unit = UNIT_PRINT.get(cell.get("unit") or "", "")
                if cell["basis"] != "reference_intake" and unit not in order:
                    order.append(unit)
            for unit in order:
                groups.append(
                    [
                        _value_text(c)
                        for h in amount
                        for c in by_header.get(h["header_id"], [])
                        if UNIT_PRINT.get(c.get("unit") or "", "") == unit
                    ]
                )
        else:
            groups.append([_value_text(c) for h in amount for c in by_header.get(h["header_id"], [])])
        percents = [_value_text(c) for h in reference for c in by_header.get(h["header_id"], [])]
        if shape == "one_per_line":
            lines.append(label)
            lines.extend(value for group in groups for value in group)
            lines.extend(percents)
            continue
        if shape == "wrapped" and " " in label and len(label) > 10:
            first, rest = label.split(" ", 1)
            if label.startswith("of which "):
                first, rest = "of which", label[len("of which ") :]
            lines.append(first)
            label = rest
        for index, group in enumerate(groups):
            tail = percents if index == len(groups) - 1 else []
            lines.append(separator.join([label if index == 0 else ""] + group + tail))
    return "\n".join(lines) + "\n"


# --- Taiwan, from FDA dataset 188 ---------------------------------------------------

FDA_VALUE = re.compile(r"^(\d+(?:\.\d+)?)(大卡|公克|毫克)$")
FDA_SERVING = re.compile(r"^(\d+(?:\.\d+)?)(公克|毫升)$")
FDA_PACK = re.compile(r"^(\d+(?:\.\d+)?)份$")
FDA_COLUMNS = {"每份": "per_serving", "每100公克": "per_100g", "每100毫升": "per_100ml"}
FDA_ROWS = ["熱量", "蛋白質", "脂肪", "飽和脂肪", "反式脂肪", "碳水化合物", "糖", "鈉"]


def fda_identity(row: dict[str, str]) -> str:
    return digest("|".join((row.get("產品追溯系統串接碼", ""), row.get("產品名稱", ""), row.get("包裝規格", ""))))


def fda_order_key(row: dict[str, str]) -> str:
    return digest(f"fda188-v1:{fda_identity(row)}")


def fda_split(order_key: str) -> str:
    return "development" if int(order_key[:8], 16) % 2 == 0 else "untouched"


def fda_truth(row: dict[str, str]) -> tuple[dict[str, Any] | None, str | None]:
    """Truth for a structured 營養標示 row, or (None, reason) when it is unusable."""
    serving = FDA_SERVING.match(row.get("每一份量", "").strip())
    pack = FDA_PACK.match(row.get("本包裝含", "").strip())
    if not serving or not pack:
        return None, "serving size or servings per pack not structured"
    columns = []
    for prefix, basis in FDA_COLUMNS.items():
        values = [row.get(f"{prefix}{name}", "").strip() for name in FDA_ROWS]
        if all(values):
            columns.append((prefix, basis, values))
        elif any(values) and prefix == "每份":
            return None, "incomplete per-serving column"
    if not columns or columns[0][0] != "每份":
        return None, "no complete per-serving column"
    expected_units = {"熱量": "大卡", "鈉": "毫克"}
    headers, cells = [], []
    for index, (prefix, basis, values) in enumerate(columns, start=1):
        header_id = f"header_{index}"
        conversion = f"{serving.group(1)}{serving.group(2)}" if basis == "per_serving" else None
        headers.append({"header_id": header_id, "printed_text": prefix, "basis": basis, "serving_conversion": conversion})
        for name, value in zip(FDA_ROWS, values, strict=True):
            match = FDA_VALUE.match(value)
            if not match or match.group(2) != expected_units.get(name, "公克"):
                return None, f"unstructured or wrongly united value for {name}"
            label, nutrient, parent, _ = next(r for r in CHINESE_ROWS if r[0] == name)
            cells.append(
                {
                    "row_id": nutrient,
                    "parent_row_id": parent,
                    "nutrient": nutrient,
                    "printed_label": label,
                    "header_id": header_id,
                    "basis": basis,
                    "printed_text": value,
                    "comparator": "=",
                    "decimal_text": match.group(1),
                    "unit": match.group(2),
                    "canonical_unit": CANONICAL[match.group(2)],
                    "serving_conversion": conversion if basis == "per_serving" else "not_applicable",
                }
            )
    return {
        "case_id": f"fda188:{fda_identity(row)[:16]}",
        "requires_decline": False,
        "decline_reason": None,
        "language": "zh-Hant",
        "headers": headers,
        "serving_size": {
            "printed_text": f"每一份量{serving.group(1)}{serving.group(2)}",
            "decimal_text": serving.group(1),
            "unit": serving.group(2),
            "canonical_unit": CANONICAL[serving.group(2)],
        },
        "servings_per_pack": {"printed_text": f"本包裝含{pack.group(1)}份", "decimal_text": pack.group(1), "approximate": False},
        "cells": cells,
    }, None


def select_columns(truth: dict[str, Any], layout: str) -> dict[str, Any] | None:
    """Apply a closed layout variant by keeping a subset of printed columns (never new values)."""
    keep = {
        "two_column": {"per_serving", "per_100g", "per_100ml"},
        "single_column_serving": {"per_serving"},
        "single_column_100": {"per_100g", "per_100ml"},
    }[layout]
    headers = [dict(h) for h in truth["headers"] if h["basis"] in keep]
    if not headers or (layout == "two_column" and len(headers) < 2):
        return None
    renumber = {h["header_id"]: f"header_{i}" for i, h in enumerate(headers, start=1)}
    for header in headers:
        header["header_id"] = renumber[header["header_id"]]
    cells = []
    for cell in truth["cells"]:
        if cell["header_id"] in renumber:
            copy = dict(cell)
            copy["header_id"] = renumber[cell["header_id"]]
            cells.append(copy)
    result = dict(truth, headers=headers, cells=cells)
    return result


def _zh_value(cell: dict[str, Any], spaced: bool) -> str:
    comparator = {"=": "", "<": "<", "<=": "≤"}[cell.get("comparator", "=")]
    gap = " " if spaced else ""
    return f"{comparator}{gap if comparator else ''}{cell['decimal_text']}{gap}{cell['unit']}"


def render_chinese(
    truth: dict[str, Any], shape: str, *, simplified: bool = False, strip_energy_unit: bool = False
) -> tuple[str, dict[str, Any]]:
    """Render a Taiwan table; returns (text, truth with rendered printed_text)."""
    spaced = shape == "spaced_units"
    truth = dict(truth, cells=[dict(c) for c in truth["cells"]])
    headers = truth["headers"]
    rows: OrderedDict[str, list[dict[str, Any]]] = OrderedDict()
    for label, nutrient, _, _ in CHINESE_ROWS:
        for cell in truth["cells"]:
            if cell["nutrient"] == nutrient or (cell["nutrient"] == "unrecognised" and cell["printed_label"] == label):
                rows.setdefault(label, []).append(cell)
    for cell in truth["cells"]:
        if cell["printed_label"] not in rows:
            rows.setdefault(cell["printed_label"], []).append(cell)
    for cell in truth["cells"]:
        cell["printed_text"] = _zh_value(cell, spaced)
    title = "營養標示"
    serving = truth["serving_size"]["printed_text"] if isinstance(truth["serving_size"], dict) else None
    pack = truth["servings_per_pack"]["printed_text"] if isinstance(truth["servings_per_pack"], dict) else None
    if spaced and serving:
        serving = f"每一份量 {truth['serving_size']['decimal_text']} {truth['serving_size']['unit']}"
        pack = f"本包裝含 {truth['servings_per_pack']['decimal_text']} 份" if pack else None
    lines = [title] + [line for line in (serving, pack) if line]
    if shape == "one_per_line":
        lines.extend(h["printed_text"] for h in headers)
    else:
        separator = "\t" if shape == "tab" else ("　　" if shape == "fullwidth" else "  ")
        lines.append(
            separator.join([""] + [h["printed_text"] for h in headers])
            if shape == "tab"
            else "　　　　" + separator.join(h["printed_text"] for h in headers)
        )
    for label, cells in rows.items():
        ordered = [c for h in headers for c in cells if c["header_id"] == h["header_id"]]
        values = []
        for cell in ordered:
            text = cell["printed_text"]
            if strip_energy_unit and cell["nutrient"] == "energy_kcal":
                text = cell["decimal_text"]
            values.append(text)
        indent = "　" if any(c.get("parent_row_id") for c in cells) else ""
        if shape == "one_per_line":
            lines.append(indent + label)
            lines.extend(values)
        elif shape == "tab":
            lines.append("\t".join([indent + label] + values))
        elif shape == "fullwidth":
            lines.append(indent + label + "　　" + "　　".join(values))
        else:
            lines.append(indent + label + "  " + "  ".join(values))
    text = "\n".join(lines) + "\n"
    if simplified:
        for traditional, simple in SIMPLIFIED.items():
            text = text.replace(traditional, simple)
    return text, truth


MUESLI_TRUTH_VALUES = [
    ("熱量", "367.2", "大卡"),
    ("蛋白質", "11", "公克"),
    ("脂肪", "8.8", "公克"),
    ("飽和脂肪", "1.2", "公克"),
    ("反式脂肪", "0", "公克"),
    ("碳水化合物", "67", "公克"),
    ("糖", "9.1", "公克"),
    ("膳食纖維", "12", "公克"),
    ("鈉", "8", "毫克"),
]


def muesli_truth(input_sha256: str | None = None) -> dict[str, Any]:
    """Owner's hand-checked muesli values (plan section 3.4, pass 1): 每份 equals 每100公克."""
    headers = [
        {"header_id": "header_1", "printed_text": "每份", "basis": "per_serving", "serving_conversion": "100公克"},
        {"header_id": "header_2", "printed_text": "每100公克", "basis": "per_100g", "serving_conversion": None},
    ]
    cells = []
    for header in headers:
        for label, value, unit in MUESLI_TRUTH_VALUES:
            _, nutrient, parent, _ = next(r for r in CHINESE_ROWS if r[0] == label)
            cells.append(
                {
                    "row_id": nutrient,
                    "parent_row_id": parent,
                    "nutrient": nutrient,
                    "printed_label": label,
                    "header_id": header["header_id"],
                    "basis": header["basis"],
                    "printed_text": f"{value}{unit}",
                    "comparator": "=",
                    "decimal_text": value,
                    "unit": unit,
                    "canonical_unit": CANONICAL[unit],
                    "serving_conversion": "100公克" if header["basis"] == "per_serving" else "not_applicable",
                }
            )
    truth = {
        "case_id": "owner:muesli-6-grain",
        "requires_decline": False,
        "decline_reason": None,
        "language": "zh-Hant",
        "headers": headers,
        "serving_size": {"printed_text": "每一份量100公克", "decimal_text": "100", "unit": "公克", "canonical_unit": "g"},
        "servings_per_pack": {"printed_text": "本包裝含5份", "decimal_text": "5", "approximate": False},
        "cells": cells,
    }
    if input_sha256:
        truth["input_sha256"] = input_sha256
    return truth


def is_number(text: str) -> bool:
    try:
        Decimal(text)
        return True
    except Exception:  # noqa: BLE001 - any parse failure means not a number
        return False
