#!/usr/bin/env python3
"""Untouched ground-truth drafting (owner decision A; contract block `untouched_truth_drafting`).

Pass 1 for the 40 untouched Open Food Facts Taiwan photos is drafted by Qwen 3.5 through
OpenRouter, a model that is not a route C model under test; the owner then verifies every
value against the image (pass 2). The result is model-drafted, owner-verified evidence.

Rules this script enforces:

- Inputs are only the untouched Taiwan photos named by the hash-bound manifest, read from
  the read-only `sealed/` folder after an explicit `--unseal-for-drafting` with the
  manifest SHA-256. This opening is the set's unsealing for truth purposes only; routes
  A, B and C still never run on these images before the frozen single run. (The 40
  sealed UK v2 images were never acquired; that stratum is deferred by the owner.)
- One request per image with the route C provider block: one endpoint in `only` and
  `order`, no fallbacks, parameters required, data collection denied, ZDR. Strict JSON
  schema output, no tools, no retries, no streaming, 4096 output tokens, 90 s timeout.
- The response model must match the requested slug under `openrouter_route`'s slug rule,
  the provider must match the endpoint, and `finish_reason` must be `stop`; otherwise the
  image is recorded as failed and is not drafted.
- Spend: `usage.cost` from each response goes into the persistent ledger
  (`budget.LedgerBudget`) shared with route C: $0.05 per call, $25 in total, the 200-call
  sealed reservation held back. Insufficient credit (HTTP 402) stops the run.
- A journal records each request before it is sent and a receipt after; a request with no
  receipt stops the next run until reconciled.
- The key comes only from the `OPENROUTER_API_KEY` environment variable, or that one
  variable read from `--env-file` into this process's memory. It is placed in
  the request header and nowhere else: never printed, logged or written. Saved raw
  responses are response bodies only; no request headers are stored anywhere.
- Drafts, raw responses, the journal and the owner's review sheet live outside the
  repository; route C never reads them.
"""

from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import html
import json
import os
import re
import subprocess
import sys
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import openrouter_client  # noqa: E402
import openrouter_route  # noqa: E402
from budget import BudgetStop, LedgerBudget, contract_limits  # noqa: E402
from candidate import _collect, schema  # noqa: E402
from openrouter_route import RouteCModel  # noqa: E402

CONTRACT = HERE / "frozen-contract-v1.json"
MANIFEST = HERE / "fixtures" / "off-taiwan-manifest-v1.json"
INSTRUCTION = HERE / "openrouter" / "truth-drafting-instruction-v1.txt"
# v1 plus one clause for bilingual Traditional Chinese tables (owner, 17 October 2026),
# used only for the orders the contract lists under untouched_truth_drafting.bilingual_instruction.
# v1.1 was tried once for order 34 and still proposed an exclusion (English units), so
# v1.2 names the US layout and English units; v1.1 is kept as a record of that call.
INSTRUCTION_V1_1 = HERE / "openrouter" / "truth-drafting-instruction-v1.1.txt"
INSTRUCTION_BILINGUAL = HERE / "openrouter" / "truth-drafting-instruction-v1.2.txt"
INSTRUCTION_IDS = {
    INSTRUCTION: "truth-drafting-instruction-v1",
    INSTRUCTION_V1_1: "truth-drafting-instruction-v1.1",
    INSTRUCTION_BILINGUAL: "truth-drafting-instruction-v1.2",
}
TRUTH_SCHEMA = "label-capture-truth-v1"
WIRE_SCHEMA = HERE / "openrouter" / "truth-drafting-wire-schema-v1.json"
ENDPOINT_URL = "https://openrouter.ai/api/v1/chat/completions"
DRAFT_SCHEMA = "label-capture-truth-draft-v1"
PURPOSE = "untouched_truth_drafting"

UNITS = {
    "大卡": "kcal",
    "千卡": "kcal",
    "公克": "g",
    "克": "g",
    "毫克": "mg",
    "微克": "µg",
    "毫升": "ml",
    "kcal": "kcal",
    "kj": "kJ",
    "g": "g",
    "mg": "mg",
    "mcg": "µg",
    "µg": "µg",
    "μg": "µg",
    "ml": "ml",
    "%": "%",
}
# A bilingual label may echo the unit in brackets (`0.5 公克(g)`); the echo is kept in
# printed_text and the printed Chinese unit is the cell's unit.
VALUE = re.compile(
    r"^\s*(<=|≤|＜|<|少於|less than)?\s*(\d+(?:[.,]\d+)?)\s*(大卡|千卡|公克|毫克|微克|毫升|克|kcal|kJ|kj|KJ|mcg|µg|μg|mg|ml|mL|g|%)"
    r"\s*(?:[(（]\s*(?:kcal|kJ|g|mg|mcg|µg|ml)\s*[)）])?\s*$"
)
SERVING = re.compile(r"(\d+(?:\.\d+)?)\s*(公克|毫升|克|g|ml|mL)")
SERVINGS = re.compile(r"(約)?\s*(\d+(?:\.\d+)?)\s*份")


# --- Pure mapping ------------------------------------------------------------------------


def parse_value(printed: str) -> dict[str, str] | None:
    """Comparator, decimal text, printed unit and canonical unit; None if not a printed amount."""
    match = VALUE.match(printed or "")
    if not match:
        return None
    raw_comparator, number, unit = match.groups()
    comparator = "=" if raw_comparator is None else ("<=" if raw_comparator in ("<=", "≤") else "<")
    canonical = UNITS.get(unit) or UNITS.get(unit.lower())
    if canonical is None:
        return None
    return {"comparator": comparator, "decimal_text": number, "unit": unit, "canonical_unit": canonical}


def map_draft(
    wire: dict[str, Any],
    photo: dict[str, Any],
    *,
    model: str,
    endpoint: str,
    drafted_on: str,
    instruction: str = "truth-drafting-instruction-v1",
) -> dict[str, Any]:
    """Map the drafting wire output to one `label-capture-truth-draft-v1` record.

    Cells use the `label-capture-candidate-v1` cell shape. Every cell the model marked
    uncertain, and every printed value that does not parse as a printed amount, is listed
    in `uncertain_cells` for the owner. Nothing here fills a value the model left unknown.
    """
    case_id = f"off-taiwan:{photo['barcode13']}:nutrition_zh.{photo['revision']}"
    found = wire.get("table_found")
    serving_text = str(wire.get("serving_size_text") or "unknown")
    serving_match = SERVING.search(serving_text) if serving_text != "unknown" else None
    serving_quantity = f"{serving_match.group(1)}{serving_match.group(2)}" if serving_match else None
    pack_text = str(wire.get("servings_per_pack_text") or "unknown")
    pack_match = SERVINGS.search(pack_text) if pack_text != "unknown" else None
    headers = {}
    for header in wire.get("headers") or []:
        headers[header["header_id"]] = {
            "header_id": header["header_id"],
            "printed_text": header["printed_text"],
            "basis": header["basis"],
            "serving_conversion": serving_quantity if header["basis"] == "per_serving" else None,
            "uncertain": bool(header.get("uncertain")),
        }
    cells, uncertain = [], []
    seen_rows: dict[str, int] = {}
    for index, row in enumerate(wire.get("rows") or [], start=1):
        nutrient = row["nutrient"]
        row_id = nutrient if nutrient != "unrecognised" else f"row_{index}"
        seen_rows[row_id] = seen_rows.get(row_id, 0) + 1
        if seen_rows[row_id] > 1:
            row_id = f"{row_id}_{seen_rows[row_id]}"
        parent = row.get("parent_nutrient")
        parent = None if parent in (None, "", "none", "unknown") else parent
        for value in row.get("values") or []:
            header = headers.get(value["header_id"])
            parsed = parse_value(value["printed_text"])
            reasons = []
            if value.get("uncertain"):
                reasons.append("model_marked_uncertain")
            if row.get("label_uncertain"):
                reasons.append("label_uncertain")
            if header is None:
                reasons.append("unknown_header")
            elif header["uncertain"]:
                reasons.append("header_uncertain")
            if parsed is None:
                reasons.append("value_not_a_printed_amount")
            basis = header["basis"] if header else "unknown"
            cell = {
                "row_id": row_id,
                "parent_row_id": parent,
                "nutrient": nutrient,
                "printed_label": row["printed_label"],
                "header_id": value["header_id"],
                "basis": basis,
                "printed_text": value["printed_text"],
                "comparator": parsed["comparator"] if parsed else None,
                "decimal_text": parsed["decimal_text"] if parsed else None,
                "unit": parsed["unit"] if parsed else None,
                "canonical_unit": parsed["canonical_unit"] if parsed else None,
                "serving_conversion": (serving_quantity or "unknown")
                if basis == "per_serving"
                else ("unknown" if basis == "unknown" else "not_applicable"),
                "persistence_authorized": False,
                "requires_user_selection": True,
            }
            cell_errors = [] if parsed is None else _collect(cell, schema()["$defs"]["cell"], "cell")
            if cell_errors:
                reasons.append("schema: " + "; ".join(cell_errors))
            if reasons:
                uncertain.append(
                    {
                        "row_id": row_id,
                        "printed_label": row["printed_label"],
                        "header_id": value["header_id"],
                        "printed_text": value["printed_text"],
                        "reasons": reasons,
                    }
                )
            cells.append({**cell, "parsed": parsed is not None})
    proposal = {
        "taiwan_nutrition_label": "usable",
        "illegible": "requires_decline",
        "multiple_panels": "requires_decline",
        "other_language_nutrition_table": "exclude_and_refill",
        "no_nutrition_table": "exclude_and_refill",
    }.get(str(found), "owner_decides")
    if wire.get("serving_size_uncertain"):
        uncertain.append(
            {
                "row_id": "serving_size",
                "printed_label": "",
                "header_id": "",
                "printed_text": serving_text,
                "reasons": ["model_marked_uncertain"],
            }
        )
    if wire.get("servings_per_pack_uncertain"):
        uncertain.append(
            {
                "row_id": "servings_per_pack",
                "printed_label": "",
                "header_id": "",
                "printed_text": pack_text,
                "reasons": ["model_marked_uncertain"],
            }
        )
    return {
        "schema_version": DRAFT_SCHEMA,
        "case_id": case_id,
        "order": photo["order"],
        "input_sha256": photo["sha256"],
        "status": "draft_owner_verification_pending",
        "evidence_label": "model-drafted, owner verification pending",
        "drafted_by": {"model": model, "endpoint": endpoint, "drafted_on": drafted_on, "pass": 1, "instruction": instruction},
        "table_found": found,
        "proposal": proposal,
        "notes": wire.get("notes"),
        "language": wire.get("language"),
        "headers": list(headers.values()),
        "serving_size": "unknown"
        if serving_text == "unknown"
        else {
            "printed_text": serving_text,
            "decimal_text": serving_match.group(1) if serving_match else None,
            "unit": serving_match.group(2) if serving_match else None,
            "canonical_unit": UNITS.get(serving_match.group(2)) if serving_match else None,
        },
        "servings_per_pack": "unknown"
        if pack_text == "unknown" or not pack_match
        else {"printed_text": pack_text, "decimal_text": pack_match.group(2), "approximate": pack_match.group(1) is not None},
        "cells": cells,
        "uncertain_cells": uncertain,
    }


def request_body(target: RouteCModel, image_bytes: bytes, instruction: str, wire_schema: dict[str, Any]) -> dict[str, Any]:
    data_uri = "data:image/jpeg;base64," + base64.b64encode(image_bytes).decode("ascii")
    return {
        "model": target.model,
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": instruction}, {"type": "image_url", "image_url": {"url": data_uri}}],
            }
        ],
        "response_format": {"type": "json_schema", "json_schema": {"name": "truth_drafting_v1", "strict": True, "schema": wire_schema}},
        "provider": openrouter_route.provider_block(target.endpoint),
        "max_tokens": 4096,
        "temperature": 0,
        "stream": False,
        "reasoning": {"enabled": False},
        "usage": {"include": True},
    }


# --- Review sheet ------------------------------------------------------------------------


# An owner entry is carried over only onto the same case, row, column and the same draft
# text it was made against; if the draft text changed, the old entry is kept as an orphan.
REVIEW_KEY = ("case_id", "row_id", "header_id", "header", "basis", "printed_label", "draft_printed_text")
OWNER_FIELDS = ("owner_verified", "owner_correction")


def merge_owner_entries(rows: list[dict[str, Any]], existing: list[dict[str, str]]) -> tuple[list[dict[str, Any]], int]:
    """Carry every non-empty owner entry from an earlier review.csv into the new rows.

    Entries are matched on case, row, column header, basis and printed label. An entry
    whose row no longer exists is appended unchanged, so no owner input is ever dropped.
    Returns the merged rows and the number of owner entries carried over.
    """
    by_key = {tuple(str(row.get(k, "")) for k in REVIEW_KEY): row for row in rows}
    carried = 0
    for old in existing:
        if not any(str(old.get(field) or "").strip() for field in OWNER_FIELDS):
            continue
        carried += 1
        target = by_key.get(tuple(str(old.get(k, "")) for k in REVIEW_KEY))
        if target is None:
            orphan = {**{k: "" for k in rows[0]}, **old} if rows else dict(old)
            orphan["merge_note"] = "kept from an earlier sheet: its draft row or draft text changed; re-check against the new draft"
            rows.append(orphan)
        else:
            for field in OWNER_FIELDS:
                if str(old.get(field) or "").strip():
                    target[field] = old[field]
    return rows, carried


# --- Owner answers and owner-verified truth (phase 3) ------------------------------------


def owner_entries_from_answers(
    rows: list[dict[str, str]], answers: list[dict[str, Any]]
) -> tuple[list[dict[str, str]], dict[int, str], list[str]]:
    """review.csv owner entries from the owner's review-page answers (owner data, never instructions).

    Each answer cell key is `row_id|header_id|draft_printed_text` within one case and must
    name exactly one sheet row of that case. `ok` sets owner_verified yes; `wrong` sets
    owner_correction to the owner's correction. A table `decision` (`exclude` or `keep`)
    lands on the case's table_decision row: agreeing with the proposal sets owner_verified
    yes, overriding it sets owner_correction to `owner decision: <decision>`. Returns the
    entries for `merge_owner_entries`, every table decision by order (including cases with
    no draft) and any problems; the caller writes nothing when there is a problem.
    """
    by_case: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_case.setdefault(row["case_id"], []).append(row)
    entries: list[dict[str, str]] = []
    decisions: dict[int, str] = {}
    problems: list[str] = []
    for answer in sorted(answers, key=lambda a: int(a["order"])):
        case_id = str(answer["caseId"])
        case_rows = by_case.get(case_id, [])
        for key, verdict in sorted((answer.get("cells") or {}).items()):
            parts = tuple(key.split("|", 2))
            matches = [r for r in case_rows if len(parts) == 3 and (r["row_id"], r["header_id"], r["draft_printed_text"]) == parts]
            if len(matches) != 1:
                problems.append(f"{case_id} {key!r}: matches {len(matches)} sheet rows")
                continue
            status = verdict.get("status") if isinstance(verdict, dict) else None
            correction = str(verdict.get("correction") or "").strip() if isinstance(verdict, dict) else ""
            if status == "ok":
                entries.append({**matches[0], "owner_verified": "yes", "owner_correction": ""})
            elif status == "wrong" and correction:
                entries.append({**matches[0], "owner_verified": "", "owner_correction": correction})
            else:
                problems.append(f"{case_id} {key!r}: status {status!r} without a usable verdict")
        decision = answer.get("decision")
        if decision is None:
            continue
        if decision not in ("exclude", "keep"):
            problems.append(f"{case_id}: unknown table decision {decision!r}")
            continue
        decisions[int(answer["order"])] = decision
        decision_rows = [r for r in case_rows if r["row_id"] == "table_decision"]
        if not decision_rows:
            continue  # no draft (a failed drafting call): the decision is recorded by order only
        row = decision_rows[0]
        proposal = row["draft_printed_text"].rsplit(" -> ", 1)[-1]
        agrees = (decision == "exclude" and proposal == "exclude_and_refill") or (decision == "keep" and proposal == "usable")
        if agrees:
            entries.append({**row, "owner_verified": "yes", "owner_correction": ""})
        else:
            entries.append({**row, "owner_verified": "", "owner_correction": f"owner decision: {decision}"})
    return entries, decisions, problems


def _serving_size_from_text(text: str) -> dict[str, Any] | str:
    if text == "unknown":
        return "unknown"
    match = SERVING.search(text)
    return {
        "printed_text": text,
        "decimal_text": match.group(1) if match else None,
        "unit": match.group(2) if match else None,
        "canonical_unit": UNITS.get(match.group(2)) if match else None,
    }


def _servings_per_pack_from_text(text: str) -> dict[str, Any] | str:
    match = SERVINGS.search(text) if text != "unknown" else None
    if not match:
        return "unknown"
    return {"printed_text": text, "decimal_text": match.group(2), "approximate": match.group(1) is not None}


def coverage_tags(record: dict[str, Any]) -> list[str]:
    """Coverage tags (plan section 3.1) derived from a truth record alone, never from route output."""
    cells = record.get("cells") or []
    headers = record.get("headers") or []
    bases = {h["basis"] for h in headers}
    amount_bases = bases - {"reference_intake"}
    tags = {"zh_hant"} if record.get("language") in ("zh-Hant", "mixed") else set()
    if "per_serving" in amount_bases and amount_bases & {"per_100g", "per_100ml"}:
        tags.add("two_column_serving_and_100")
    if len([h for h in headers if h["basis"] != "reference_intake"]) == 1:
        tags.add("single_column")
    if "reference_intake" in bases:
        tags.add("reference_intake_column")
    if "per_100ml" in bases:
        tags.add("per_100ml")
    if any(c.get("comparator") not in (None, "=") for c in cells):
        tags.add("bound")
    if any(c.get("nutrient") == "sodium" for c in cells):
        tags.add("sodium")
    if any(c.get("parent_row_id") for c in cells):
        tags.add("nested_rows")
    if record.get("serving_size") not in (None, "unknown"):
        tags.add("serving_line")
    if record.get("servings_per_pack") not in (None, "unknown"):
        tags.add("servings_per_pack")
    if record.get("requires_decline"):
        tags.add("decline_expected")
    return sorted(tags)


def verified_record(draft: dict[str, Any], case_rows: list[dict[str, str]], *, verified_on: str) -> dict[str, Any] | None:
    """One `label-capture-truth-v1` record from a draft whose every sheet row the owner has checked.

    Returns None while any row is unchecked, while the table decision is unconfirmed, or
    when the owner kept a table the draft left empty (it needs a new draft first). An owner
    correction replaces the drafted printed text; a value that is not a printed amount
    (such as `*`, or `unknown` for an illegible value) is kept as an unscored cell, never as a value.
    """
    decision_row = next((r for r in case_rows if r["row_id"] == "table_decision"), None)
    if decision_row is None:
        return None
    if decision_row["owner_verified"] == "yes":
        outcome = draft["proposal"]
    elif decision_row["owner_correction"] == "owner decision: keep":
        outcome = "usable"
    elif decision_row["owner_correction"] == "owner decision: exclude":
        outcome = "exclude_and_refill"
    else:
        return None
    if outcome == "usable" and not draft["cells"]:
        return None  # kept by the owner, but the draft has no table yet: redraft, then review again
    # An exclusion needs only the confirmed decision; any other outcome needs every row checked.
    if outcome != "exclude_and_refill" and not all(r["owner_verified"] == "yes" or r["owner_correction"].strip() for r in case_rows):
        return None
    corrections = {(r["row_id"], r["header_id"]): r["owner_correction"].strip() for r in case_rows if r["owner_correction"].strip()}
    corrected = sum(1 for key in corrections if key[0] != "table_decision")
    drafted = draft["drafted_by"]
    record: dict[str, Any] = {
        "case_id": draft["case_id"],
        "input_sha256": draft["input_sha256"],
        "order": draft["order"],
        "review": {
            "pass_1": {
                "drafted_by": drafted["model"],
                "endpoint": drafted["endpoint"],
                "instruction": drafted.get("instruction", "truth-drafting-instruction-v1"),
                "drafted_on": drafted["drafted_on"],
            },
            "pass_2": {
                "reviewer": "owner",
                "method": "every drafted value, serving line and table decision checked against the image in a private review page",
                "verified_on": verified_on,
                "owner_corrections": corrected,
            },
            "evidence_label": "model-drafted, owner-verified" + (" (no owner corrections)" if corrected == 0 else ""),
        },
        "excluded": outcome == "exclude_and_refill",
        "exclusion_reason": draft["table_found"] if outcome == "exclude_and_refill" else None,
        "requires_decline": outcome == "requires_decline",
        "decline_reason": draft["table_found"] if outcome == "requires_decline" else None,
        "language": draft["language"],
    }
    if outcome != "usable":
        record.update({"headers": [], "serving_size": "unknown", "servings_per_pack": "unknown", "cells": [], "unscored_cells": []})
        record["coverage_tags"] = coverage_tags(record)
        return record
    serving_text = corrections.get(("serving_size", ""))
    pack_text = corrections.get(("servings_per_pack", ""))
    serving = _serving_size_from_text(serving_text) if serving_text else draft["serving_size"]
    pack = _servings_per_pack_from_text(pack_text) if pack_text else draft["servings_per_pack"]
    serving_quantity = f"{serving['decimal_text']}{serving['unit']}" if isinstance(serving, dict) and serving.get("decimal_text") else None
    headers = [
        {
            "header_id": h["header_id"],
            "printed_text": h["printed_text"],
            "basis": h["basis"],
            "serving_conversion": serving_quantity if h["basis"] == "per_serving" else None,
        }
        for h in draft["headers"]
    ]
    cells, unscored = [], []
    row_ids = {cell["row_id"] for cell in draft["cells"]}
    parents_cleared = 0
    mechanical: list[dict[str, str]] = []
    for cell in draft["cells"]:
        # The review page showed values, not parents, so parentage is structural only: a
        # draft parent naming the row itself or a row absent from the table (`energy` for
        # 熱量, `unrecognised`) means no parent. No printed text is changed.
        parent = cell["parent_row_id"]
        if parent is not None and (parent in (cell["row_id"], cell["nutrient"]) or parent not in row_ids):
            parent = None
            parents_cleared += 1
        printed = str(corrections.get((cell["row_id"], cell["header_id"]), cell["printed_text"]))
        parsed = parse_value(printed)
        if parsed is None or cell["basis"] == "unknown":
            if parsed is None and BARE_NUMBER.match(printed):
                # Printed without a unit (for example 熱量 "100" on a US-style label): kept as
                # printed and ungradable; no unit is inferred.
                reason = "printed without a unit; kept as printed and ungradable (no unit inferred)"
            else:
                reason = "not a printed amount" if parsed is None else "unknown column"
            unscored.append(
                {
                    "row_id": cell["row_id"],
                    "header_id": cell["header_id"],
                    "printed_label": cell["printed_label"],
                    "printed_text": printed,
                    "reason": reason,
                }
            )
            continue
        nutrient, row_id = cell["nutrient"], cell["row_id"]
        mapped = mechanical_nutrient(cell["printed_label"]) if nutrient == "unrecognised" else None
        if mapped is not None:
            # The review page showed labels and values, not nutrient keys: a draft that left a
            # closed Taiwan row name (for example 鈉 in "Sodium/鈉") unrecognised is mapped by the
            # agent's mechanical check, recorded per record, never by the owner's review.
            mechanical.append({"printed_label": cell["printed_label"], "draft_nutrient": nutrient, "nutrient": mapped})
            nutrient, row_id = mapped, mapped if mapped not in row_ids else row_id
        cells.append(
            {
                "row_id": row_id,
                "parent_row_id": parent,
                "nutrient": nutrient,
                **{k: cell[k] for k in ("printed_label", "header_id", "basis")},
                "printed_text": printed,
                **parsed,
                "serving_conversion": (serving_quantity or "unknown") if cell["basis"] == "per_serving" else "not_applicable",
            }
        )
    record.update({"headers": headers, "serving_size": serving, "servings_per_pack": pack, "cells": cells, "unscored_cells": unscored})
    record["review"]["structural_parent_cells_cleared"] = parents_cleared
    if mechanical:
        record["review"]["mechanical_nutrient_mappings"] = [dict(t) for t in {tuple(sorted(m.items())) for m in mechanical}]
    record["coverage_tags"] = coverage_tags(record)
    return record


BARE_NUMBER = re.compile(r"^\s*\d+(?:[.,]\d+)?\s*$")
# The closed Taiwan 營養標示 row names (plan section 2.1) and their canonical keys.
TAIWAN_ROW_NAMES = {
    "熱量": "energy_kcal",
    "蛋白質": "protein",
    "脂肪": "fat",
    "飽和脂肪": "saturates",
    "反式脂肪": "trans_fat",
    "碳水化合物": "carbohydrate",
    "糖": "sugars",
    "膳食纖維": "fibre",
    "鈉": "sodium",
}


def mechanical_nutrient(printed_label: str) -> str | None:
    """The canonical key when the label's Traditional Chinese part is exactly one closed row name.

    A bilingual label such as "Sodium/鈉" gives 鈉, so sodium. A longer name that only contains a
    row name (總脂肪, 添加糖) is not mapped. 熱量 maps only when the cell is graded at all.
    """
    parts = [part.strip() for part in re.split(r"[/／]", printed_label)]
    names = {TAIWAN_ROW_NAMES[p] for p in parts if p in TAIWAN_ROW_NAMES}
    return names.pop() if len(names) == 1 else None


def write_review_sheet(out: Path, drafts: list[dict[str, Any]], images: dict[str, Path]) -> int:
    """A local HTML page (image beside its draft) and a CSV with one row per cell to tick.

    An existing review.csv is never overwritten blindly: it is copied aside first and
    every non-empty owner entry is merged into the new sheet. Returns the number of owner
    entries carried over.
    """
    rows = []
    sections = []
    for draft in sorted(drafts, key=lambda d: d["order"]):
        image = images[draft["case_id"]]
        flagged = {(u["row_id"], u["header_id"]) for u in draft["uncertain_cells"]}
        headers = {h["header_id"]: h for h in draft["headers"]}
        cell_rows = []
        for cell in draft["cells"]:
            mark = (cell["row_id"], cell["header_id"]) in flagged
            header = headers.get(cell["header_id"], {})
            cell_rows.append(
                f"<tr class='{'flag' if mark else ''}'><td>{html.escape(cell['printed_label'])}</td>"
                f"<td>{html.escape(cell['nutrient'])}</td><td>{html.escape(str(cell['parent_row_id'] or ''))}</td>"
                f"<td>{html.escape(str(header.get('printed_text', '')))} ({html.escape(cell['basis'])})</td>"
                f"<td><b>{html.escape(cell['printed_text'])}</b></td><td>{'uncertain' if mark else ''}</td></tr>"
            )
            rows.append(
                {
                    "order": draft["order"],
                    "case_id": draft["case_id"],
                    "image": str(image),
                    "row_id": cell["row_id"],
                    "header_id": cell["header_id"],
                    "printed_label": cell["printed_label"],
                    "nutrient": cell["nutrient"],
                    "parent_row_id": cell["parent_row_id"] or "",
                    "header": header.get("printed_text", ""),
                    "basis": cell["basis"],
                    "draft_printed_text": cell["printed_text"],
                    "uncertain": "yes" if mark else "",
                    "owner_verified": "",
                    "owner_correction": "",
                    "merge_note": "",
                }
            )
        for field in ("serving_size", "servings_per_pack"):
            value = draft[field]
            rows.append(
                {
                    "order": draft["order"],
                    "case_id": draft["case_id"],
                    "image": str(image),
                    "row_id": field,
                    "header_id": "",
                    "printed_label": "",
                    "nutrient": "",
                    "parent_row_id": "",
                    "header": "",
                    "basis": "",
                    "draft_printed_text": value if isinstance(value, str) else value["printed_text"],
                    "uncertain": "yes" if (field, "") in flagged else "",
                    "owner_verified": "",
                    "owner_correction": "",
                    "merge_note": "",
                }
            )
        rows.append(
            {
                "order": draft["order"],
                "case_id": draft["case_id"],
                "image": str(image),
                "row_id": "table_decision",
                "header_id": "",
                "printed_label": "",
                "nutrient": "",
                "parent_row_id": "",
                "header": "",
                "basis": "",
                "draft_printed_text": f"{draft['table_found']} -> {draft['proposal']}",
                "uncertain": "",
                "owner_verified": "",
                "owner_correction": "",
                "merge_note": "",
            }
        )
        serving = draft["serving_size"] if isinstance(draft["serving_size"], str) else draft["serving_size"]["printed_text"]
        pack = draft["servings_per_pack"] if isinstance(draft["servings_per_pack"], str) else draft["servings_per_pack"]["printed_text"]
        sections.append(
            f"<section id='o{draft['order']}'><h2>{draft['order']:02d} · {html.escape(draft['case_id'])}</h2>"
            f"<div class='pair'><a href='{image.as_uri()}'>"
            f"<img src='{image.as_uri()}' alt='Nutrition label photo {draft['order']}'></a><div>"
            f"<p>Table: <b>{html.escape(str(draft['table_found']))}</b>, proposal <b>{html.escape(draft['proposal'])}</b>. "
            f"Uncertain cells: {len(draft['uncertain_cells'])}.</p>"
            f"<p>Serving size: {html.escape(serving)}<br>Servings per pack: {html.escape(pack)}</p>"
            f"<p>Notes: {html.escape(str(draft['notes']))}</p>"
            "<table><tr><th>Printed label</th><th>Nutrient</th><th>Parent</th><th>Column</th><th>Draft value</th><th></th></tr>"
            + "".join(cell_rows)
            + "</table></div></div></section>"
        )
    page = (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>"
        "<title>Untouched truth drafts</title><style>"
        ":root{--bg:#fff;--fg:#111;--flag:#fff3c4;--line:#ccc}"
        "@media (prefers-color-scheme: dark){:root{--bg:#111;--fg:#eee;--flag:#4a3d00;--line:#444}}"
        "body{background:var(--bg);color:var(--fg);font:15px/1.4 -apple-system,system-ui,sans-serif;margin:16px}"
        ".pair{display:flex;gap:16px;flex-wrap:wrap}img{max-width:min(560px,100%);border:1px solid var(--line)}"
        "table{border-collapse:collapse}td,th{border:1px solid var(--line);padding:3px 6px;text-align:left}tr.flag{background:var(--flag)}"
        "section{border-top:2px solid var(--line);padding-top:8px;margin-top:16px}"
        "</style></head><body><h1>Untouched Taiwan truth drafts: owner verification</h1>"
        "<p>Pass 1 drafted by a model (not a route under test). Check every value against the photo at full zoom (click the image), "
        "record corrections in <code>review.csv</code> (owner_verified yes, or owner_correction), "
        "and confirm or change each table decision. "
        "Highlighted rows were marked uncertain. These drafts are not ground truth until you have verified them.</p>"
        + "".join(sections)
        + "</body></html>"
    )
    (out / "review.html").write_text(page, encoding="utf-8")
    sheet = out / "review.csv"
    carried = 0
    if sheet.exists():
        previous = sheet.read_text(encoding="utf-8")
        backup = out / f"review.csv.before-{hashlib.sha256(previous.encode('utf-8')).hexdigest()[:12]}"
        if not backup.exists():
            backup.write_text(previous, encoding="utf-8")
        rows, carried = merge_owner_entries(rows, list(csv.DictReader(previous.splitlines())))
    with sheet.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]) if rows else ["case_id"])
        writer.writeheader()
        writer.writerows(rows)
    return carried


# --- Runner ------------------------------------------------------------------------------


def inside_git(path: Path) -> bool:
    """Whether a path, or its nearest existing ancestor if it does not exist yet, is in a checkout."""
    probe_path = path.expanduser().resolve()
    while not probe_path.exists():
        probe_path = probe_path.parent
    probe = subprocess.run(["git", "-C", str(probe_path), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return probe.returncode == 0


# The redirect-refusing opener now lives in the shared client (one retry policy for both callers).
RefuseRedirects = openrouter_client.RefuseRedirects
OPENER = openrouter_client.OPENER


def key_from_env_file(path: Path) -> str | None:
    """`OPENROUTER_API_KEY` from a dotenv file, held in memory only; nothing is echoed."""
    for raw in path.expanduser().read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        name, sep, value = line.partition("=")
        if sep and name.strip() == "OPENROUTER_API_KEY":
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            return value or None
    return None


def now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def journal_open_request(journal: Path) -> str | None:
    """The case id of a request with no receipt, if any."""
    pending: dict[str, int] = {}
    if journal.exists():
        for line in journal.read_text(encoding="utf-8").splitlines():
            event = json.loads(line)
            if event["event"] in ("request", "receipt"):  # per-attempt events sit between the two
                pending[event["case_id"]] = pending.get(event["case_id"], 0) + (1 if event["event"] == "request" else -1)
    return next((case for case, count in pending.items() if count > 0), None)


def append(journal: Path, event: dict[str, Any]) -> None:
    with journal.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, ensure_ascii=False) + "\n")


def _read_sheet(out: Path) -> tuple[str, list[dict[str, str]]]:
    previous = (out / "review.csv").read_text(encoding="utf-8")
    return previous, list(csv.DictReader(previous.splitlines()))


def apply_owner_answers(out: Path, answers_dir: Path) -> int:
    """Merge the owner's review-page answers into review.csv (copied aside first); no call."""
    previous, rows = _read_sheet(out)
    answers = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(answers_dir.glob("o*.json"))]
    entries, decisions, problems = owner_entries_from_answers(rows, answers)
    if problems:
        raise SystemExit("owner answers do not match the sheet; nothing written:\n" + "\n".join(problems))
    backup = out / f"review.csv.before-{hashlib.sha256(previous.encode('utf-8')).hexdigest()[:12]}"
    if not backup.exists():
        backup.write_text(previous, encoding="utf-8")
    merged, carried = merge_owner_entries(rows, entries)
    with (out / "review.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(merged[0]))
        writer.writeheader()
        writer.writerows(merged)
    statuses = [v.get("status") for a in answers for v in (a.get("cells") or {}).values()]
    record = {
        "answers": len(answers),
        "cells_answered": len(statuses),
        "cells_ok": statuses.count("ok"),
        "cells_wrong": statuses.count("wrong"),
        "entries_merged": carried,
        "table_decisions": {str(k): v for k, v in sorted(decisions.items())},
    }
    (out / "owner-answers-applied.json").write_text(json.dumps(record, indent=1), encoding="utf-8")
    print(json.dumps(record))
    return 0


def write_truth(out: Path, path: Path, *, verified_on: str, manifest_sha256: str) -> int:
    """Write the owner-verified untouched truth file; only fully checked cases become records."""
    _, rows = _read_sheet(out)
    rows = [r for r in rows if not (r.get("merge_note") or "").strip()]  # orphans from an earlier draft are not evidence
    by_case: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_case.setdefault(row["case_id"], []).append(row)
    drafts = [json.loads(p.read_text(encoding="utf-8")) for p in sorted((out / "drafts").glob("*.json"))]
    records, pending = [], []
    for draft in sorted(drafts, key=lambda d: d["order"]):
        record = verified_record(draft, by_case.get(draft["case_id"], []), verified_on=verified_on)
        if record is None:
            pending.append(draft["order"])
        else:
            records.append(record)
    usable = [r for r in records if not r["excluded"]]
    corrections = sum(r["review"]["pass_2"]["owner_corrections"] for r in records)
    document = {
        "schema_version": TRUTH_SCHEMA,
        "set": "off_taiwan_untouched",
        "status": "owner_verified",
        "evidence_label": "model-drafted, owner-verified" + (" (no owner corrections)" if corrections == 0 else ""),
        "drafting_method": "Pass 1 drafted by Qwen 3.5 (not a route C model) under owner decision A; pass 2 by the owner, every value "
        "checked against the image. Weaker evidence than independent human transcription.",
        "anchoring_note": "The owner confirmed every drafted value without a correction. Agreement with the draft cannot rule out "
        "anchoring on it: a value the owner accepted because the draft showed it would look the same.",
        "parentage_note": "The review page showed printed values, headers and serving lines, not parent rows, so parentage is "
        "structural: a draft parent naming the row itself or a row absent from the table is cleared.",
        "nutrient_key_note": "Nutrient keys were not on the review page either. A key the draft left unrecognised for a label whose "
        "Traditional Chinese part is exactly one closed Taiwan row name (for example 鈉 in 'Sodium/鈉') is mapped by the agent's "
        "mechanical check and listed per record under review.mechanical_nutrient_mappings; it is not owner-verified.",
        "unit_note": "A value printed without a unit (for example 熱量 '100' on a US-style bilingual label) is kept exactly as "
        "printed in unscored_cells and is ungradable; no unit is inferred.",
        "review_rounds": "Round 1 (17 October 2026): 40 photos, 527 of 527 cells confirmed, 11 exclusions agreed, order 23 excluded, "
        "order 34 kept. Round 2 (17 October 2026): order 34 (redrafted with the bilingual instruction v1.2) and refills 63 to 77, "
        "268 of 268 cells confirmed with no corrections, refill exclusions 66, 71 and 75 agreed. The owner confirmed order 34's "
        "printed values as drafted, including 熱量 '100' with no unit.",
        "manifest_sha256": manifest_sha256,
        "verified_on": verified_on,
        "counts": {
            "records": len(records),
            "usable": len(usable),
            "required_declines": sum(r["requires_decline"] for r in records),
            "excluded": sum(r["excluded"] for r in records),
            "scored_cells": sum(len(r["cells"]) for r in usable),
            "unscored_cells": sum(len(r["unscored_cells"]) for r in usable),
            "owner_corrections": corrections,
            "pending_orders": pending,
        },
        "records": records,
    }
    path.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(document["counts"]))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--image-root", type=Path, required=True, help="the Taiwan photo folder (with sealed/) outside any checkout")
    parser.add_argument("--out", type=Path, required=True, help="draft folder outside any checkout")
    parser.add_argument("--ledger", type=Path, required=True, help="persistent spend ledger outside any checkout")
    parser.add_argument("--unseal-for-drafting", action="store_true")
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--model", help="must equal the contract's drafting model if given")
    parser.add_argument("--endpoint", help="must equal the contract's drafting endpoint if given")
    parser.add_argument("--provider-name", help="must equal the contract's drafting provider if given")
    parser.add_argument("--orders", help="comma-separated untouched orders to draft (default: all not yet drafted)")
    parser.add_argument("--sheet-only", action="store_true", help="rebuild the review sheet from saved drafts; no call")
    parser.add_argument("--env-file", type=Path, help="dotenv file to take OPENROUTER_API_KEY from (only that variable, into this process)")
    parser.add_argument(
        "--bilingual-orders",
        help="comma-separated orders drafted with the bilingual instruction (listed in the contract); an earlier draft is moved aside",
    )
    parser.add_argument(
        "--apply-owner-answers", type=Path, help="folder of the owner's oNN.json review answers; merges them into review.csv, no call"
    )
    parser.add_argument(
        "--write-truth", type=Path, help="write the owner-verified untouched truth file from drafts and review.csv, no call"
    )
    parser.add_argument("--verified-on", help="date of the owner's verification (YYYY-MM-DD), with --write-truth")
    args = parser.parse_args()

    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    expected = contract["corpus"]["off_taiwan"]["manifest_sha256"]
    if not args.unseal_for_drafting:
        raise SystemExit("the untouched set is sealed; drafting needs --unseal-for-drafting")
    if args.manifest_sha256 != expected or hashlib.sha256(MANIFEST.read_bytes()).hexdigest() != expected:
        raise SystemExit("the manifest hash does not match the contract")
    if contract["untouched_truth_drafting"].get("owner_decision") != "A, 17 October 2026":
        raise SystemExit("drafting is not defined by the contract")
    pinned = contract["untouched_truth_drafting"]["model"]
    for name, given, expected_value in (
        ("--model", args.model, pinned["slug"]),
        ("--endpoint", args.endpoint, pinned["endpoint"]),
        ("--provider-name", args.provider_name, pinned["provider_name"]),
    ):
        if given is not None and given != expected_value:
            raise SystemExit(f"{name} {given!r} differs from the contract's {expected_value!r}")
    for path in (args.out, args.ledger, args.image_root):
        if inside_git(path):
            raise SystemExit(f"refusing a path inside a git checkout: {path}")
    args.out.mkdir(parents=True, exist_ok=True)
    args.ledger.parent.mkdir(parents=True, exist_ok=True)

    if args.apply_owner_answers:
        return apply_owner_answers(args.out, args.apply_owner_answers)
    if args.write_truth:
        if not args.verified_on:
            raise SystemExit("--write-truth needs --verified-on")
        return write_truth(args.out, args.write_truth, verified_on=args.verified_on, manifest_sha256=expected)
    bilingual_orders = {int(o) for o in args.bilingual_orders.split(",")} if args.bilingual_orders else set()
    allowed_bilingual = set(contract["untouched_truth_drafting"].get("bilingual_instruction", {}).get("orders", []))
    if not bilingual_orders <= allowed_bilingual:
        raise SystemExit(f"bilingual instruction orders {sorted(bilingual_orders - allowed_bilingual)} are not listed in the contract")

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    photos = [p for p in manifest["photos"] + manifest.get("refills", []) if p["split"] == "untouched" and not p.get("excluded")]
    if args.orders:
        wanted = {int(o) for o in args.orders.split(",")}
        photos = [p for p in photos if p["order"] in wanted]
    images = {
        f"off-taiwan:{p['barcode13']}:nutrition_zh.{p['revision']}": args.image_root
        / "sealed"
        / f"{p['order']:02d}-{p['barcode13']}-nutrition_zh.{p['revision']}.jpg"
        for p in manifest["photos"] + manifest.get("refills", [])
        if p["split"] == "untouched"
    }
    drafts_dir, raw_dir = args.out / "drafts", args.out / "raw"
    drafts_dir.mkdir(exist_ok=True)
    raw_dir.mkdir(exist_ok=True)
    journal = args.out / "journal.jsonl"

    if not args.sheet_only:
        key = os.environ.get("OPENROUTER_API_KEY") or (key_from_env_file(args.env_file) if args.env_file else None)
        if not key:
            raise SystemExit("OPENROUTER_API_KEY is not set in the environment")
        open_request = journal_open_request(journal)
        if open_request:
            raise SystemExit(f"a request for {open_request} has no receipt; reconcile the journal before another call")
        target = RouteCModel(
            label="qwen-drafting", model=pinned["slug"], endpoint=pinned["endpoint"], provider_name=pinned["provider_name"]
        )
        budget = LedgerBudget(args.ledger, limits=contract_limits(contract))
        wire_schema = json.loads(WIRE_SCHEMA.read_text(encoding="utf-8"))
        superseded = args.out / "superseded"
        for photo in sorted(photos, key=lambda p: p["order"]):
            case_id = f"off-taiwan:{photo['barcode13']}:nutrition_zh.{photo['revision']}"
            draft_path = drafts_dir / f"{photo['order']:02d}.json"
            instruction_path = INSTRUCTION_BILINGUAL if photo["order"] in bilingual_orders else INSTRUCTION
            instruction_id = INSTRUCTION_IDS[instruction_path]
            if draft_path.exists() and instruction_path is INSTRUCTION_BILINGUAL:
                old = json.loads(draft_path.read_text(encoding="utf-8"))
                old_id = old["drafted_by"].get("instruction", "truth-drafting-instruction-v1")
                if old_id != instruction_id:
                    # Keep the earlier draft and its raw response; nothing is overwritten.
                    superseded.mkdir(exist_ok=True)
                    for source in (draft_path, raw_dir / draft_path.name):
                        moved = superseded / f"{source.parent.name}-{photo['order']:02d}.{old_id.rsplit('-', 1)[-1]}.json"
                        if moved.exists():
                            raise SystemExit(f"refusing to overwrite {moved}")
                        source.rename(moved)
            if draft_path.exists():
                continue
            instruction = instruction_path.read_text(encoding="utf-8")
            image = images[case_id]
            data = image.read_bytes()
            if hashlib.sha256(data).hexdigest() != photo["sha256"]:
                raise SystemExit(f"{case_id} bytes do not match the manifest")
            append(
                journal,
                {
                    "event": "request",
                    "case_id": case_id,
                    "order": photo["order"],
                    "at": now(),
                    "model": target.model,
                    "endpoint": target.endpoint,
                    "instruction": instruction_id,
                },
            )
            poster = openrouter_client.http_post(key, "WeeklyHealthReport label evaluation drafting")

            def ledgered_post(
                payload: dict[str, Any], timeout: float, poster: openrouter_client.PostFn = poster
            ) -> tuple[int, dict[str, Any] | None, dict[str, str], float]:
                budget.before_call(target.label)  # the open call is on disk before each attempt is sent
                return poster(payload, timeout)

            def record(attempt: openrouter_client.Attempt, case_id: str = case_id, order: int = photo["order"]) -> None:
                # Every attempt is a ledger entry: its reported cost, or unknown (never zero).
                cost = openrouter_route.reported_cost(attempt.body)
                generation = attempt.body.get("id") if isinstance(attempt.body, dict) else None
                kind = openrouter_client.attempt_kind(attempt.status, attempt.body, attempt.retryable)
                if cost is None and attempt.retryable and isinstance(generation, str):
                    found, value = openrouter_client.generation_cost(key, generation)
                    if found == "found" and value is not None:
                        cost = Decimal(str(value))
                append(
                    journal,
                    {
                        "event": "attempt",
                        "case_id": case_id,
                        "order": order,
                        "attempt": attempt.number,
                        "at": now(),
                        "http_status": attempt.status,
                        "retryable": attempt.retryable,
                        "cause": attempt.cause,
                        "retry_after": attempt.retry_after,
                        "cost_usd": None if cost is None else str(cost),
                        "seconds": round(attempt.seconds, 2),
                    },
                )
                budget.record_call(
                    target.label,
                    cost,
                    purpose=PURPOSE,
                    case_id=case_id,
                    at=now(),
                    returned_model=attempt.body.get("model") if isinstance(attempt.body, dict) else None,
                    kind=kind,
                    attempt=attempt.number,
                    generation_id=generation if isinstance(generation, str) else None,
                )

            try:
                result = openrouter_client.call_with_retry(
                    request_body(target, data, instruction, wire_schema), ledgered_post, on_attempt=record
                )
            except BudgetStop as stop:
                append(journal, {"event": "receipt", "case_id": case_id, "order": photo["order"], "at": now(), "stopped": str(stop)})
                print(f"stopped at {case_id}: {stop}")
                break
            status, response = result.status, result.body
            seconds = sum(a.seconds for a in result.attempts)
            (raw_dir / f"{photo['order']:02d}.json").write_text(
                json.dumps(
                    {"http_status": status, "seconds": round(seconds, 2), "attempts": len(result.attempts), "body": response},
                    ensure_ascii=False,
                    indent=1,
                ),
                encoding="utf-8",
            )
            cost = openrouter_route.reported_cost(response)
            if result.exhausted or status != 200 or result.cause:
                problems = [f"request failed: {result.cause or f'HTTP {status}'}"]
            else:
                problems = openrouter_route.route_mismatches(response, target)
            append(
                journal,
                {
                    "event": "receipt",
                    "case_id": case_id,
                    "order": photo["order"],
                    "at": now(),
                    "http_status": status,
                    "attempts": len(result.attempts),
                    "cost_usd": None if cost is None else str(cost),
                    "seconds": round(seconds, 2),
                    "problems": problems,
                    "returned_model": response.get("model") if isinstance(response, dict) else None,
                },
            )
            if status in (401, 402, 403):
                message = (response or {}).get("error", {}).get("message", "") if isinstance(response, dict) else ""
                print(f"stopping: HTTP {status} {message[:200]}")
                break
            if problems:
                print(f"{case_id}: failed ({'; '.join(problems)})")
                continue
            assert isinstance(response, dict)
            try:
                wire = json.loads(response["choices"][0]["message"]["content"])
            except (KeyError, IndexError, TypeError, json.JSONDecodeError):
                print(f"{case_id}: failed (content is not schema JSON)")
                continue
            draft = map_draft(
                wire, photo, model=str(response.get("model")), endpoint=target.endpoint, drafted_on=now()[:10], instruction=instruction_id
            )
            draft_path.write_text(json.dumps(draft, ensure_ascii=False, indent=1), encoding="utf-8")
            print(f"{case_id}: drafted, {len(draft['cells'])} cells, {len(draft['uncertain_cells'])} uncertain, cost {cost}")
        print(f"ledger reported spend so far: {json.loads(args.ledger.read_text())['reported_spend_usd']}")

    if args.sheet_only:
        # Re-map saved drafts from their raw response bodies (no call), so a mapping fix
        # applies without another request; the drafting date and model are kept.
        by_order = {p["order"]: p for p in manifest["photos"] + manifest.get("refills", [])}
        for path in sorted(drafts_dir.glob("*.json")):
            old = json.loads(path.read_text(encoding="utf-8"))
            body = json.loads((raw_dir / path.name).read_text(encoding="utf-8"))["body"]
            wire = json.loads(body["choices"][0]["message"]["content"])
            drafted = old["drafted_by"]
            draft = map_draft(
                wire,
                by_order[old["order"]],
                model=drafted["model"],
                endpoint=drafted["endpoint"],
                drafted_on=drafted["drafted_on"],
                instruction=drafted.get("instruction", "truth-drafting-instruction-v1"),
            )
            path.write_text(json.dumps(draft, ensure_ascii=False, indent=1), encoding="utf-8")
    drafts = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(drafts_dir.glob("*.json"))]
    carried = write_review_sheet(args.out, drafts, images) if drafts else 0
    failed = sorted(p.stem for p in raw_dir.glob("*.json") if not (drafts_dir / p.name).exists())
    summary = {
        "requests": len(list(raw_dir.glob("*.json"))),
        "owner_entries_carried_over": carried,
        "failed_orders": failed,
        "drafted": len(drafts),
        "cells": sum(len(d["cells"]) for d in drafts),
        "uncertain_cells": sum(len(d["uncertain_cells"]) for d in drafts),
        "proposals": {k: sum(d["proposal"] == k for d in drafts) for k in sorted({d["proposal"] for d in drafts})},
    }
    (args.out / "summary.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
