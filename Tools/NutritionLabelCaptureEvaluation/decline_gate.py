"""Deterministic decline gate `label-capture-decline-gate-v1` (phase 4, #255). Pure; no I/O.

The gate runs on every candidate from every route (A, B and C) after extraction and
before scoring. It only reads the candidate and the label format the case declares
(the stratum: a Taiwan 營養標示 label or a UK nutrition declaration). It can do exactly
two things:

- **decline** the table: `declined` becomes true, the reasons are appended, and every
  cell is withheld as unknown (plan section 6: a declined table keeps no cells);
- **block ready**: `would_mark_ready` becomes false and a warning is appended.

It never edits, fills, converts or reorders a value, header or serving line; a candidate
that passes keeps every field byte for byte. A failed (schema-invalid) candidate is
passed through untouched, so failed stays a state distinct from declined. A candidate the
route already declined is passed through as well.

Rules and their reasons (contract `decline_gate`; each rule comes from the label
regulations or the plan's own decline rules, not from a development case):

G1 `unsupported_script` (decline). Plan section 6 limits v1 to `en` and `zh-Hant`.
   Kana and Hangul are never part of either. A Han character is Simplified-only when it
   is in GB 2312 (the Simplified Chinese national character set) but not in CP950 (the
   Big5 Traditional Chinese set used in Taiwan); both codecs ship with Python, so the
   distinction needs no hand-made list. The CJK middle dot (U+30FB) and the prolonged
   sound mark (U+30FC) sit in the Katakana block but are punctuation in Chinese text too,
   so they are not counted as kana.
G2 `not_a_food_nutrition_panel` (decline). Food supplements are exempt from the
   nutrition declaration of retained Regulation (EU) No 1169/2011 (Article 29(1)(a)) and
   are labelled per daily dose under the Food Supplements (England) Regulations 2003;
   Taiwan's capsule and tablet foods follow a separate labelling rule
   (膠囊錠狀食品營養標示應遵行事項). A panel that names itself a supplement or gives a
   softgel, caplet or 錠 (tablet) dose is not the label format the case declares.
   `capsule` and 膠囊 are deliberately not markers, because coffee capsules are ordinary
   food, and neither is English `tablet`, because Scottish tablet is a confection. Such a
   supplement still fails G3, because it declares no energy or macronutrient rows.
G3 `required_row_missing` (decline). Each declared format has a mandatory set of rows:
   UK, Annex XV and Article 30(1) of 1169/2011 (energy in kJ and kcal, fat, saturates,
   carbohydrate, sugars, protein, salt); Taiwan, 包裝食品營養標示應遵行事項 (熱量, 蛋白質,
   脂肪, 飽和脂肪, 反式脂肪, 碳水化合物, 糖, 鈉). A mandatory row with no readable amount
   in any amount column means the table was cut off, obscured or is not this format;
   plan section 6 declines a table whose values cannot be bound to its rows.
G4 `column_count_mismatch` (decline). Plan section 6 declines a table whose column
   values cannot be bound one to one to the row labels. Here: a mandatory row that has an
   amount in one amount column but not in another amount column. Reference-intake
   columns are left out, because Taiwan labels print `*` where no reference value exists.
G5 `required_basis_missing` (block ready, UK only). Article 32(2) of 1169/2011 requires
   per 100 g or per 100 ml. No Taiwan column rule is encoded: the plan's own coverage
   (section 3.1) treats single-column Taiwan tables as usable, and the gate does not
   overrule the contract's corpus.
G6 `required_serving_declaration_missing` (block ready, Taiwan only). Taiwan requires
   the serving size (每一份量) and servings per pack (本包裝含…份) lines.

Development data was used to motivate the rules (phase 3 route C results: most
false-ready tables came from images that should have been declined). The rules were
written from the regulations and plan section 6 and then run once over the saved
development outputs; no rule or marker was added or changed to fit a development case.
"""

from __future__ import annotations

import copy
import re
from typing import Any

from candidate import validate_candidate

GATE_VERSION = "label-capture-decline-gate-v1"
TAIWAN = "taiwan_nutrition_labelling"
UK = "uk_nutrition_declaration"
FORMATS = (TAIWAN, UK)

REQUIRED_ROWS = {
    UK: ("energy_kj", "energy_kcal", "fat", "saturates", "carbohydrate", "sugars", "protein", "salt"),
    TAIWAN: ("energy_kcal", "protein", "fat", "saturates", "trans_fat", "carbohydrate", "sugars", "sodium"),
}

# Hiragana, Katakana (less U+30FB and U+30FC), Katakana phonetic extensions, halfwidth
# Katakana, and every Hangul block.
UNSUPPORTED_RANGES = (
    (0x3040, 0x309F),
    (0x30A0, 0x30FA),
    (0x30FD, 0x30FF),
    (0x31F0, 0x31FF),
    (0xFF66, 0xFF9F),
    (0x1100, 0x11FF),
    (0x3130, 0x318F),
    (0xA960, 0xA97F),
    (0xAC00, 0xD7AF),
    (0xD7B0, 0xD7FF),
    (0xFFA0, 0xFFDC),
)
HAN_RANGES = ((0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF))

SUPPLEMENT_MARKERS = re.compile(
    r"food\s+supplement|dietary\s+supplement|supplement\s+facts|\bsoft\s?gels?\b|\bcaplets?\b|錠|营养补充|營養補充",
    re.IGNORECASE,
)


def _encodes(char: str, codec: str) -> bool:
    try:
        char.encode(codec)
    except UnicodeEncodeError:
        return False
    return True


def is_simplified_only(char: str) -> bool:
    """A Han character in GB 2312 but not in CP950 (Big5): a Simplified-only form."""
    code = ord(char)
    if not any(low <= code <= high for low, high in HAN_RANGES):
        return False
    return _encodes(char, "gb2312") and not _encodes(char, "cp950")


def is_unsupported_script(char: str) -> bool:
    code = ord(char)
    return any(low <= code <= high for low, high in UNSUPPORTED_RANGES)


def printed_texts(candidate: dict[str, Any]) -> list[str]:
    """Every printed string the route read from the label (labels, headers, values, serving lines)."""
    texts: list[str] = []
    for header in candidate.get("headers") or []:
        texts.append(str(header.get("printed_text") or ""))
    for cell in candidate.get("cells") or []:
        texts.append(str(cell.get("printed_label") or ""))
        texts.append(str(cell.get("printed_text") or ""))
    for field in ("serving_size", "servings_per_pack"):
        value = candidate.get(field)
        if isinstance(value, dict):
            texts.append(str(value.get("printed_text") or ""))
    return texts


def script_findings(texts: list[str]) -> list[str]:
    simplified = sorted({c for text in texts for c in text if is_simplified_only(c)})
    other = sorted({c for text in texts for c in text if is_unsupported_script(c)})
    findings = []
    if simplified:
        findings.append("simplified_only_characters: " + "".join(simplified))
    if other:
        findings.append("kana_or_hangul: " + "".join(other))
    return findings


def evaluate(candidate: dict[str, Any], label_format: str) -> dict[str, Any]:
    """The gate's findings for one candidate, without changing it."""
    if label_format not in FORMATS:
        raise ValueError(f"unknown label format {label_format!r}")
    headers = candidate.get("headers") or []
    cells = candidate.get("cells") or []
    declines: list[str] = []
    blocks: list[str] = []
    details: list[str] = []

    found = script_findings(printed_texts(candidate))
    if found:
        declines.append("unsupported_script")
        details.extend(found)

    marker_texts = [str(h.get("printed_text") or "") for h in headers] + [str(c.get("printed_label") or "") for c in cells]
    serving = candidate.get("serving_size")
    if isinstance(serving, dict):
        marker_texts.append(str(serving.get("printed_text") or ""))
    markers = sorted({m.group(0).lower() for text in marker_texts for m in SUPPLEMENT_MARKERS.finditer(text)})
    if markers:
        declines.append("not_a_food_nutrition_panel")
        details.append("supplement_markers: " + ", ".join(markers))

    amount_headers = [h.get("header_id") for h in headers if h.get("basis") != "reference_intake"]
    amount_cells = [c for c in cells if c.get("basis") != "reference_intake"]
    by_nutrient: dict[str, set[Any]] = {}
    for cell in amount_cells:
        by_nutrient.setdefault(str(cell.get("nutrient")), set()).add(cell.get("header_id"))
    required = REQUIRED_ROWS[label_format]
    missing = [row for row in required if row not in by_nutrient]
    if missing:
        declines.append("required_row_missing")
        details.append("required_rows_without_amount: " + ", ".join(missing))
    short = [row for row in required if row in by_nutrient and any(h not in by_nutrient[row] for h in amount_headers)]
    if short:
        declines.append("column_count_mismatch")
        details.append("required_rows_missing_a_column: " + ", ".join(short))

    bases = {h.get("basis") for h in headers}
    if label_format == UK:
        if not bases & {"per_100g", "per_100ml"}:
            blocks.append("required_basis_missing")
    else:
        if not isinstance(candidate.get("serving_size"), dict) or not isinstance(candidate.get("servings_per_pack"), dict):
            blocks.append("required_serving_declaration_missing")
    return {"gate_version": GATE_VERSION, "label_format": label_format, "declines": declines, "blocks": blocks, "details": details}


def apply_gate(candidate: dict[str, Any] | None, label_format: str) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    """Return (gated candidate, report). Never changes a value; only declines or blocks ready."""
    if label_format not in FORMATS:
        raise ValueError(f"unknown label format {label_format!r}")
    skipped = {"gate_version": GATE_VERSION, "label_format": label_format, "declines": [], "blocks": [], "details": []}
    if candidate is None or validate_candidate(candidate):
        return candidate, {**skipped, "skipped": "failed_candidate"}
    if candidate.get("declined"):
        return candidate, {**skipped, "skipped": "already_declined"}
    report = {**evaluate(candidate, label_format), "skipped": None}
    if report["declines"]:
        gated = copy.deepcopy(candidate)
        gated.update(
            {
                "declined": True,
                "decline_reasons": [*candidate.get("decline_reasons", []), *(f"gate:{r}" for r in report["declines"])],
                "would_mark_ready": False,
                "serving_size": "unknown",
                "servings_per_pack": "unknown",
                "headers": [],
                "cells": [],
                "warnings": [*candidate.get("warnings", []), *(f"{GATE_VERSION}: {d}" for d in report["details"])],
            }
        )
        return gated, report
    if report["blocks"] and candidate.get("would_mark_ready"):
        gated = copy.deepcopy(candidate)
        gated["would_mark_ready"] = False
        gated["warnings"] = [*candidate.get("warnings", []), *(f"{GATE_VERSION}: blocks ready: {b}" for b in report["blocks"])]
        return gated, report
    return candidate, report


def format_for_case(metadata: dict[str, Any]) -> str:
    """The label format a case declares, from its corpus or stratum (never from route output)."""
    if metadata.get("label_format") in FORMATS:
        return str(metadata["label_format"])
    corpus = str(metadata.get("corpus") or "")
    stratum = str(metadata.get("stratum") or "")
    if corpus in ("off_taiwan", "owner", "muesli_typed", "fda188", "zh_template") or stratum in ("taiwan_zh_hant", "muesli"):
        return TAIWAN
    if corpus in ("uk_v2_development_review", "v1", "v2dev") or stratum == "uk_en":
        return UK
    raise ValueError(f"no declared label format for corpus {corpus!r} and stratum {stratum!r}")
