#!/usr/bin/env python3
"""Export the frozen tables and parity vectors for the Swift port (#93, pasted label PR 1).

Contract: `docs/pasted-nutrition-label-v1.md` sections 3.5, 4, 5 and 8.2 to 8.4. Two jobs, both
deterministic (no clock, no randomness, no network) and both reading only committed or
synthetic data:

`tables` writes the two data tables the Swift decline gate reads, because Swift has neither
Python's GB 2312 and CP950 codecs nor Python `re` character classes:

- `gate-v2-simplified-only-v1.txt`: every code point in `HAN_RANGES` that gate v2's
  `is_simplified_only` classifies as Simplified-only (in GB 2312, not in CP950, not a shared
  variant), as upper-case hexadecimal, sorted, one per line;
- `gate-v2-marker-classes-v1.txt`: the Python `re` classes the supplement-marker pattern
  depends on (`\\s`, the case-insensitive equivalents of each pattern letter, and the `\\w`
  word characters behind `\\b`), with the Python and Unicode database versions they came from.

`vectors` runs the Swift `NutritionLabelTextParse` binary once on every development pasted-text
case (`synthetic/development-cases-v1.jsonl`) and on the untouched closed-template cases
(re-rendered with the frozen generator path, which needs no source data), adds hand-built
synthetic candidates for the gate rules no rendered case reaches, and records what the frozen
Python reference returns for each: gate v2 (`decline_gate.apply_gate`), the arithmetic checks
(`arithmetic.check_table`), the format the case declares and the three frozen mutation families
on every usable truth. The untouched FDA dataset 188 cases are included only when
`--untouched-fda-csv` names the hash-checked CSV, which is kept outside the repository; without
it they are left out and the vectors say so.

`check` re-derives everything except the parser output from committed files and fails on any
difference, so CI can confirm the vectors still match the frozen Python without the binary.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import platform
import re
import subprocess
import sys
import unicodedata
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import arithmetic  # noqa: E402
import cases as case_loading  # noqa: E402
import decline_gate  # noqa: E402
from synthetic import render  # noqa: E402

PACKAGE = REPO / "Packages" / "FoodLedgerKit"
RESOURCES = PACKAGE / "Sources" / "NutritionLabelParsing" / "Resources"
FIXTURES = PACKAGE / "Tests" / "NutritionLabelParsingTests" / "Fixtures"
SIMPLIFIED_TABLE = RESOURCES / "gate-v2-simplified-only-v1.txt"
MARKER_TABLE = RESOURCES / "gate-v2-marker-classes-v1.txt"
CODE_POINTS = FIXTURES / "parity-code-points-v1.json"
CASES = FIXTURES / "parity-cases-v1.jsonl"
MUTATIONS = FIXTURES / "parity-mutations-v1.jsonl"
SUMS = FIXTURES / "parity-sha256-v1.txt"
DEVELOPMENT = HERE / "synthetic" / "development-cases-v1.jsonl"
FDA_SOURCE = HERE / "fixtures" / "fda-188-source-v1.json"

VECTORS_VERSION = "pasted-label-parity-vectors-v1"
INFERENCE_VERSION = "pasted-label-format-inference-v1"
JURISDICTION = {decline_gate.TAIWAN: "taiwan", decline_gate.UK: "uk"}
ZERO_HASH = "0" * 64
# The cell fields the frozen mutations may change.
MUTABLE_FIELDS = ("basis", "comparator", "decimal_text", "printed_text")

# The supplement-marker pattern as a closed structure, so the Swift matcher can be written
# against it. `marker_pattern()` rebuilds gate v2's pattern string from it and `tables`
# refuses to run if they differ.
MARKER_ALTERNATIVES: tuple[tuple[str, ...], ...] = (
    ("lit:food", "ws+", "lit:supplement"),
    ("lit:dietary", "ws+", "lit:supplement"),
    ("lit:supplement", "ws+", "lit:facts"),
    ("b", "lit:soft", "ws?", "lit:gel", "opt:s", "b"),
    ("b", "lit:caplet", "opt:s", "b"),
    ("lit:营养补充",),
    ("lit:營養補充",),
)


def marker_pattern() -> str:
    pieces = []
    for alternative in MARKER_ALTERNATIVES:
        text = ""
        for token in alternative:
            if token == "b":
                text += r"\b"
            elif token == "ws+":
                text += r"\s+"
            elif token == "ws?":
                text += r"\s?"
            elif token.startswith("lit:"):
                text += token.removeprefix("lit:")
            elif token.startswith("opt:"):
                text += token.removeprefix("opt:") + "?"
        pieces.append(text)
    return "|".join(pieces)


def pattern_letters() -> list[str]:
    letters = {ch for alt in MARKER_ALTERNATIVES for token in alt if token[:4] in ("lit:", "opt:") for ch in token[4:]}
    return sorted(letters)


# --- Tables -------------------------------------------------------------------------------


def simplified_only_code_points() -> list[int]:
    return [code for low, high in decline_gate.HAN_RANGES for code in range(low, high + 1) if decline_gate.is_simplified_only(chr(code))]


def simplified_only_table() -> str:
    return "".join(f"{code:04X}\n" for code in simplified_only_code_points())


def _runs(codes: list[int]) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    for code in codes:
        if runs and runs[-1][1] == code - 1:
            runs[-1] = (runs[-1][0], code)
        else:
            runs.append((code, code))
    return runs


def marker_classes_table() -> str:
    if marker_pattern() != decline_gate.SUPPLEMENT_MARKERS.pattern:
        raise SystemExit("MARKER_ALTERNATIVES no longer rebuilds gate v2's supplement-marker pattern")
    if decline_gate.SUPPLEMENT_MARKERS.flags & re.IGNORECASE == 0:
        raise SystemExit("gate v2's supplement-marker pattern is expected to be case-insensitive")
    every = range(0x110000)
    space = [code for code in every if re.fullmatch(r"\s", chr(code))]
    word = [code for code in every if re.fullmatch(r"\w", chr(code))]
    lines = [
        "label-capture-decline-gate-v2 supplement marker classes v1",
        f"python {platform.python_version()} unicodedata {unicodedata.unidata_version}",
        "pattern " + marker_pattern(),
        "space " + " ".join(f"{code:04X}" for code in space),
    ]
    for letter in pattern_letters():
        folds = [code for code in every if re.fullmatch(re.escape(letter), chr(code), re.IGNORECASE)]
        lowered = " ".join(f"{code:04X}:" + ".".join(f"{ord(c):04X}" for c in chr(code).lower()) for code in folds)
        lines.append(f"fold {ord(letter):04X} {lowered}")
    lines.extend(f"word {low:04X} {high:04X}" for low, high in _runs(word))
    return "\n".join(lines) + "\n"


def code_point_runs() -> dict[str, Any]:
    """Gate v2's own classification of every code point in HAN_RANGES and UNSUPPORTED_RANGES."""
    ranges = sorted({*decline_gate.HAN_RANGES, *decline_gate.UNSUPPORTED_RANGES})
    runs: list[list[Any]] = []
    for low, high in ranges:
        for code in range(low, high + 1):
            char = chr(code)
            klass = "s" if decline_gate.is_simplified_only(char) else "u" if decline_gate.is_unsupported_script(char) else "-"
            if runs and runs[-1][2] == klass and runs[-1][1] == code - 1:
                runs[-1][1] = code
            else:
                runs.append([code, code, klass])
    return {
        "version": VECTORS_VERSION,
        "gate_version": decline_gate.GATE_VERSION,
        "han_ranges": [list(r) for r in decline_gate.HAN_RANGES],
        "unsupported_ranges": [list(r) for r in decline_gate.UNSUPPORTED_RANGES],
        "shared_variants": sorted(f"{ord(c):04X}" for c in decline_gate.SHARED_VARIANTS),
        "code_points": sum(high - low + 1 for low, high in ranges),
        "runs": runs,
    }


# --- Format inference (contract section 5) ----------------------------------------------------


def infer_format(candidate: dict[str, Any]) -> str:
    """zh-Hant is Taiwan; English with a per 100 g or ml column, or else a salt or kJ row, is UK; other English is US; else ambiguous.

    Owner decision of 18 October 2026: a UK table printed per serving only is inferred as UK (the gate then
    flags the missing per 100 column, G5), not as US.
    """
    language = candidate.get("language")
    if language == "zh-Hant":
        return decline_gate.TAIWAN
    if language == "en":
        bases = {h.get("basis") for h in candidate.get("headers") or []}
        if bases & {"per_100g", "per_100ml"}:
            return decline_gate.UK
        nutrients = {c.get("nutrient") for c in candidate.get("cells") or []}
        return decline_gate.UK if nutrients & {"salt", "energy_kj"} else "us_nutrition_facts"
    return "format_ambiguous"


# --- Synthetic gate candidates ----------------------------------------------------------------


def candidate_from_truth(truth: dict[str, Any], language: str = "zh-Hant") -> dict[str, Any]:
    keys = (
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
    return {
        "schema_version": "label-capture-candidate-v1",
        "route": "A",
        "input_sha256": ZERO_HASH,
        "status": "user_selection_only",
        "declined": False,
        "decline_reasons": [],
        "ready_for_confirmation": False,
        "would_mark_ready": True,
        "automatic_save": False,
        "language": language,
        "serving_size": copy.deepcopy(truth["serving_size"]),
        "servings_per_pack": copy.deepcopy(truth["servings_per_pack"]),
        "headers": [{k: h[k] for k in ("header_id", "printed_text", "basis", "serving_conversion")} for h in truth["headers"]],
        "cells": [{**{k: c[k] for k in keys}, "persistence_authorized": False, "requires_user_selection": True} for c in truth["cells"]],
        "warnings": [],
    }


def _relabel(candidate: dict[str, Any], nutrient: str, label: str) -> dict[str, Any]:
    changed = copy.deepcopy(candidate)
    for cell in changed["cells"]:
        if cell["nutrient"] == nutrient:
            cell["printed_label"] = label
    return changed


def _header_text(candidate: dict[str, Any], text: str) -> dict[str, Any]:
    changed = copy.deepcopy(candidate)
    changed["headers"][0]["printed_text"] = text
    return changed


def synthetic_candidates() -> list[tuple[str, str, dict[str, Any] | None]]:
    """(id, declared format, candidate) for gate rules and marker edge cases no rendered case reaches."""
    muesli = candidate_from_truth(render.muesli_truth(ZERO_HASH))
    out: list[tuple[str, str, dict[str, Any] | None]] = [("synthetic:muesli", decline_gate.TAIWAN, muesli)]
    tw = decline_gate.TAIWAN
    uk = decline_gate.UK
    # G1: Simplified-only characters (unsorted and repeated), shared variants, kana and Hangul.
    out.append(("synthetic:g1:simplified", tw, _relabel(muesli, "fat", "脂肪营养热量营")))
    for char in sorted(decline_gate.SHARED_VARIANTS):
        out.append((f"synthetic:g1:shared-variant:{ord(char):04X}", tw, _relabel(muesli, "fat", "脂肪" + char)))
    out.append(("synthetic:g1:shared-and-simplified", tw, _relabel(muesli, "fat", "内温营黄")))
    out.append(("synthetic:g1:kana-hangul", tw, _relabel(muesli, "sodium", "ナトリウム나트륨・ー")))
    serving = copy.deepcopy(muesli)
    serving["serving_size"]["printed_text"] = "每一份量热"
    out.append(("synthetic:g1:serving-line", tw, serving))
    per_pack = copy.deepcopy(muesli)
    per_pack["servings_per_pack"]["printed_text"] = "本包装含5份"
    out.append(("synthetic:g1:servings-per-pack-line", tw, per_pack))
    value = copy.deepcopy(muesli)
    value["cells"][0]["printed_text"] = "367.2卡路里热"
    out.append(("synthetic:g1:value-text", tw, value))
    # G2: supplement markers and the regex edge cases (case, \s, \b, optional s).
    markers = [
        "Softgel",
        "SOFTGELS",
        "soft gel",
        "Soft Gels",
        "soft　gel",
        "soft gels",
        "soft\x1cgel",
        "soft\x0bgel",
        "soft\x85gel",
        "soft  gel",
        "softgelsx",
        "xsoftgel",
        "_softgel",
        "softgel_",
        "1softgel",
        "softgel2",
        "softgel²",
        "²softgel",
        "softgeĺ",
        "́softgel",
        "é softgel",
        "softgelé",
        "ſoftgel",
        "Caplet",
        "caplets",
        "CAPLETSS",
        "capletsy",
        "dietary supplement",
        "DİETARY SUPPLEMENT",
        "dıetary supplement",
        "food\tsupplement",
        "food\nsupplement",
        "FOOD  SUPPLEMENTS",
        "foodsupplement",
        "Supplement Facts",
        "supplement facts",
        "營養補充食品",
        "营养补充剂",
        "softgel softgel caplet",
        "Soft gel / Softgels / caplet",
        "Coffee capsule tablet 膠囊 口含錠",
    ]
    for index, text in enumerate(markers):
        out.append((f"synthetic:g2:label:{index:02d}", tw, _relabel(muesli, "protein", text)))
    out.append(("synthetic:g2:header", tw, _header_text(muesli, "Per softgel")))
    serving_marker = copy.deepcopy(muesli)
    serving_marker["serving_size"]["printed_text"] = "每一份量 2 Softgels"
    out.append(("synthetic:g2:serving-line", tw, serving_marker))
    not_read = copy.deepcopy(muesli)
    not_read["cells"][2]["printed_text"] = "softgel"
    not_read["servings_per_pack"]["printed_text"] = "本包裝含 softgel"
    out.append(("synthetic:g2:value-text-is-not-a-marker-source", tw, not_read))
    # G3 and G4: missing mandatory rows and per 100 column checks; G5 and G6.
    missing = copy.deepcopy(muesli)
    missing["cells"] = [c for c in missing["cells"] if c["nutrient"] not in ("sodium", "trans_fat")]
    out.append(("synthetic:g3:taiwan", tw, missing))
    out.append(("synthetic:g3:uk-format-on-taiwan-rows", uk, muesli))
    reference_only = copy.deepcopy(muesli)
    for cell in reference_only["cells"]:
        if cell["nutrient"] == "sodium":
            cell["basis"] = "reference_intake"
            cell["canonical_unit"] = "%"
            cell["header_id"] = "header_3"
    reference_only["headers"].append(
        {"header_id": "header_3", "printed_text": "每日參考值百分比", "basis": "reference_intake", "serving_conversion": None}
    )
    out.append(("synthetic:g3:reference-intake-only", tw, reference_only))
    two_per_100 = copy.deepcopy(muesli)
    two_per_100["headers"][0]["basis"] = "per_100ml"
    for cell in two_per_100["cells"]:
        if cell["header_id"] == "header_1":
            cell["basis"] = "per_100ml"
            cell["serving_conversion"] = "not_applicable"
    two_per_100["cells"] = [c for c in two_per_100["cells"] if not (c["header_id"] == "header_1" and c["nutrient"] in ("sugars", "fat"))]
    out.append(("synthetic:g4:two-per-100-columns", tw, two_per_100))
    partial_serving = copy.deepcopy(muesli)
    partial_serving["cells"] = [c for c in partial_serving["cells"] if not (c["basis"] == "per_serving" and c["nutrient"] == "sugars")]
    out.append(("synthetic:g4:partial-serving-column-is-not-declined", tw, partial_serving))
    no_serving = copy.deepcopy(muesli)
    no_serving["serving_size"] = "unknown"
    out.append(("synthetic:g6:serving-size", tw, no_serving))
    no_pack = copy.deepcopy(muesli)
    no_pack["servings_per_pack"] = "unknown"
    out.append(("synthetic:g6:servings-per-pack", tw, no_pack))
    serving_only = copy.deepcopy(muesli)
    serving_only["headers"] = serving_only["headers"][:1]
    serving_only["cells"] = [c for c in serving_only["cells"] if c["header_id"] == "header_1"]
    out.append(("synthetic:g5:uk-without-per-100", uk, serving_only))
    out.append(("synthetic:g5:taiwan-serving-only", tw, serving_only))
    ready_false = copy.deepcopy(no_pack)
    ready_false["would_mark_ready"] = False
    out.append(("synthetic:g6:not-ready-is-not-rewritten", tw, ready_false))
    every = _relabel(_relabel(missing, "protein", "Softgel"), "fat", "热ア")
    out.append(("synthetic:all-rules-in-order", tw, every))
    # Skipped states.
    out.append(("synthetic:skip:none", tw, None))
    declined = copy.deepcopy(muesli)
    declined.update({"declined": True, "decline_reasons": ["no_table"], "would_mark_ready": False, "cells": [], "headers": []})
    out.append(("synthetic:skip:already-declined", tw, declined))
    bad_hash = copy.deepcopy(muesli)
    bad_hash["input_sha256"] = "not-a-hash"
    out.append(("synthetic:skip:failed:hash", tw, bad_hash))
    newline_hash = copy.deepcopy(muesli)
    newline_hash["input_sha256"] = ZERO_HASH + "\n"
    out.append(("synthetic:python-dollar-allows-a-final-newline", tw, newline_hash))
    bad_decimal = copy.deepcopy(muesli)
    bad_decimal["cells"][0]["decimal_text"] = "1.2.3"
    out.append(("synthetic:skip:failed:decimal", tw, bad_decimal))
    bad_unit = copy.deepcopy(muesli)
    bad_unit["cells"][0]["canonical_unit"] = "cal_typo"
    out.append(("synthetic:skip:failed:unit", tw, bad_unit))
    bad_nutrient = copy.deepcopy(muesli)
    bad_nutrient["cells"][0]["nutrient"] = "vitamin_c"
    out.append(("synthetic:skip:failed:nutrient", tw, bad_nutrient))
    bad_route = copy.deepcopy(muesli)
    bad_route["route"] = "D"
    out.append(("synthetic:skip:failed:route", tw, bad_route))
    mismatched = copy.deepcopy(muesli)
    mismatched["cells"][0]["basis"] = "per_100g"
    out.append(("synthetic:skip:failed:header-basis", tw, mismatched))
    reference_amount = copy.deepcopy(reference_only)
    for cell in reference_amount["cells"]:
        if cell["basis"] == "reference_intake":
            cell["canonical_unit"] = "mg"
    out.append(("synthetic:skip:failed:reference-intake-amount", tw, reference_amount))
    conversion = copy.deepcopy(muesli)
    for cell in conversion["cells"]:
        if cell["basis"] == "per_100g":
            cell["serving_conversion"] = "100公克"
            break
    out.append(("synthetic:skip:failed:serving-conversion", tw, conversion))
    english = candidate_from_truth(render.muesli_truth(ZERO_HASH), language="en")
    out.append(("synthetic:language:en-taiwan-rows", tw, english))
    out.append(("synthetic:language:mixed", tw, candidate_from_truth(render.muesli_truth(ZERO_HASH), language="mixed")))
    return out


# --- Vectors ---------------------------------------------------------------------------------


def _gate(candidate: dict[str, Any] | None, label_format: str) -> dict[str, Any]:
    original = copy.deepcopy(candidate)
    gated, report = decline_gate.apply_gate(copy.deepcopy(candidate), label_format)
    # `gated` is null when the gate returned the candidate unchanged, to keep the vectors small.
    return {"report": report, "gated": None if gated == original else gated}


def _arithmetic(candidate: dict[str, Any] | None, label_format: str) -> dict[str, Any] | None:
    if candidate is None or label_format not in JURISDICTION:
        return None
    return arithmetic.check_table({**candidate, "jurisdiction": JURISDICTION[label_format]})


def expected_for(candidate: dict[str, Any] | None, label_format: str) -> dict[str, Any]:
    return {
        "gate": _gate(candidate, label_format),
        "arithmetic": _arithmetic(candidate, label_format),
        "inferred_format": infer_format(candidate) if candidate is not None else None,
    }


def mutation_record(case_id: str, truth: dict[str, Any]) -> dict[str, Any]:
    record: dict[str, Any] = {
        "id": case_id,
        "truth": truth,
        "jurisdiction": arithmetic.jurisdiction_for(truth),
        "original": arithmetic.check_table(truth),
        "mutations": {},
    }
    for mutation in arithmetic.MUTATIONS:
        mutated = arithmetic.mutate(truth, mutation)
        if mutated is None:
            record["mutations"][mutation] = None
            continue
        changed = [
            {"index": index, **{k: cell.get(k) for k in MUTABLE_FIELDS}}
            for index, (cell, before) in enumerate(zip(mutated["cells"], truth["cells"], strict=True))
            if cell != before
        ]
        record["mutations"][mutation] = {"changed_cells": changed, "checks": arithmetic.check_table(mutated)}
    return record


def text_cases(fda_csv: Path | None) -> tuple[list[dict[str, Any]], list[str]]:
    import run_untouched_text  # the frozen generator path; imports nothing private

    development = case_loading.load_development_text(DEVELOPMENT)
    untouched = run_untouched_text.template_rows("untouched")
    sets = ["development (committed)", "untouched zh_template (re-rendered, synthetic)"]
    if fda_csv is not None:
        expected = json.loads(FDA_SOURCE.read_text(encoding="utf-8"))["extracted"]["sha256"]
        if case_loading.sha256_file(fda_csv) != expected:
            raise SystemExit("the FDA CSV does not match fixtures/fda-188-source-v1.json")
        untouched = run_untouched_text.fda_rows(fda_csv, "untouched") + untouched
        # The same cases as the single untouched route A run: its recorded dataset hash must match.
        dataset = "\n".join(json.dumps(c, ensure_ascii=False, sort_keys=True) for c in untouched) + "\n"
        if hashlib.sha256(dataset.encode("utf-8")).hexdigest() != untouched_dataset_sha256():
            raise SystemExit("the re-rendered untouched set differs from the one route A ran on")
        sets.append(FDA_SET)
    for case in untouched:
        if hashlib.sha256(case["input"]["text"].encode("utf-8")).hexdigest() != case["metadata"]["sha256"]:
            raise SystemExit(f"{case['id']} text does not match its hash")
    return development + untouched, sets


def run_parser(binary: Path, loaded: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    payload = json.dumps([{"id": c["id"], "text": c["input"]["text"]} for c in loaded]).encode("utf-8")
    done = subprocess.run([str(binary)], input=payload, capture_output=True, check=True)
    return {item["id"]: item for item in json.loads(done.stdout)}


def _line(record: dict[str, Any]) -> str:
    return json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


FDA_SET = "untouched fda188 (rendered from the hash-checked CSV; owner decision 18 October 2026)"
UNTOUCHED_RESULT = HERE / "results" / "untouched-taiwan-v1.json"


def untouched_dataset_sha256() -> str:
    return json.loads(UNTOUCHED_RESULT.read_text(encoding="utf-8"))["route_a_untouched_text"]["dataset_sha256"]


def meta(sets: list[str], parser_version: str | None) -> dict[str, Any]:
    extra: dict[str, Any] = {}
    if FDA_SET in sets:
        source = json.loads(FDA_SOURCE.read_text(encoding="utf-8"))
        extra = {
            "untouched_dataset_sha256": untouched_dataset_sha256(),
            "fda188_licence": source["licence"],
            "fda188_licence_url": source["licence_url"],
            "fda188_attribution": source["attribution"],
            "fda188_caveat": "Values are supplied by manufacturers and are not guaranteed by the FDA; cases are rendered synthetic text.",
        }
    return {
        **extra,
        "kind": "meta",
        "version": VECTORS_VERSION,
        "gate_version": decline_gate.GATE_VERSION,
        "inference_version": INFERENCE_VERSION,
        "parser_version": parser_version,
        "supplement_marker_pattern": decline_gate.SUPPLEMENT_MARKERS.pattern,
        "sets": sets,
        "reference_sha256": {
            name: case_loading.sha256_file(HERE / name)
            for name in ("decline_gate.py", "arithmetic.py", "candidate.py", "candidate-schema-v1.json")
        },
        "note": "Synthetic or committed data only. Expected values are the frozen Python reference's own output.",
    }


def build_case_lines(loaded: list[dict[str, Any]], outputs: dict[str, dict[str, Any]], sets: list[str]) -> list[str]:
    parser_versions = {item["parser_version"] for item in outputs.values()}
    if len(parser_versions) != 1:
        raise SystemExit(f"expected one parser version, got {parser_versions}")
    lines = [_line(meta(sets, next(iter(parser_versions))))]
    for case in loaded:
        label_format = decline_gate.format_for_case(case["metadata"])
        candidate = outputs[case["id"]]["candidate"]
        lines.append(
            _line(
                {
                    "kind": "text",
                    "id": case["id"],
                    "corpus": case["metadata"]["corpus"],
                    "split": case["metadata"]["split"],
                    "declared_format": label_format,
                    "text": case["input"]["text"],
                    "text_sha256": case["metadata"]["sha256"],
                    "candidate": candidate,
                    "expected": expected_for(candidate, label_format),
                }
            )
        )
    for case_id, label_format, candidate in synthetic_candidates():
        lines.append(
            _line(
                {
                    "kind": "candidate",
                    "id": case_id,
                    "declared_format": label_format,
                    "candidate": candidate,
                    "expected": expected_for(candidate, label_format),
                }
            )
        )
    return lines


def build_mutation_lines(loaded: list[dict[str, Any]]) -> list[str]:
    lines = []
    for case in loaded:
        truth = case["truth"]
        if truth.get("requires_decline"):
            continue
        lines.append(_line({"kind": "truth", "split": case["metadata"]["split"], **mutation_record(case["id"], truth)}))
    muesli = render.muesli_truth(ZERO_HASH)
    lines.append(_line({"kind": "truth", "split": "synthetic", **mutation_record("synthetic:muesli", muesli)}))
    return lines


def jsonl_lines(path: Path) -> list[str]:
    """Lines split on U+000A only: the JSON keeps U+001C, U+0085 and U+2028, which `splitlines` would split on."""
    return [line for line in path.read_text(encoding="utf-8").split("\n") if line]


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def sums_text() -> str:
    files = [SIMPLIFIED_TABLE, MARKER_TABLE, CODE_POINTS, CASES, MUTATIONS]
    return "".join(f"{case_loading.sha256_file(p)}  {p.name}\n" for p in files)


def code_points_text() -> str:
    return json.dumps(code_point_runs(), sort_keys=True, separators=(",", ":")) + "\n"


def command_tables() -> None:
    write(SIMPLIFIED_TABLE, simplified_only_table())
    write(MARKER_TABLE, marker_classes_table())
    write(CODE_POINTS, code_points_text())


def command_vectors(binary: Path, fda_csv: Path | None) -> None:
    loaded, sets = text_cases(fda_csv)
    outputs = run_parser(binary, loaded)
    write(CASES, "\n".join(build_case_lines(loaded, outputs, sets)) + "\n")
    write(MUTATIONS, "\n".join(build_mutation_lines(loaded)) + "\n")
    write(SUMS, sums_text())


def check() -> list[str]:
    """Differences between the committed files and what the frozen Python derives from them."""
    problems = []
    if SIMPLIFIED_TABLE.read_text(encoding="utf-8") != simplified_only_table():
        problems.append("the simplified-only table differs from gate v2's codecs")
    if CODE_POINTS.read_text(encoding="utf-8") != code_points_text():
        problems.append("the code-point runs differ from gate v2")
    marker_lines = MARKER_TABLE.read_text(encoding="utf-8").split("\n", 2)
    # The classes depend on Python's Unicode database. Under any other version the comparison
    # cannot be made, which is a failure, not a skip (CI pins Python 3.11).
    if not marker_lines[1].endswith(f" unicodedata {unicodedata.unidata_version}"):
        problems.append(f"the marker classes need Unicode {marker_lines[1].split()[-1]}; this Python has {unicodedata.unidata_version}")
    elif marker_lines[2] != marker_classes_table().split("\n", 2)[2]:
        problems.append("the marker classes differ from Python re")
    if SUMS.read_text(encoding="utf-8") != sums_text():
        problems.append("parity-sha256-v1.txt does not match the files")
    lines = [json.loads(line) for line in jsonl_lines(CASES)]
    synthetic = {case_id: (fmt, cand) for case_id, fmt, cand in synthetic_candidates()}
    import run_untouched_text  # the frozen generator path; imports nothing private

    development = {c["id"]: c for c in case_loading.load_development_text(DEVELOPMENT)}
    development.update({c["id"]: c for c in run_untouched_text.template_rows("untouched")})
    for record in lines[1:]:
        if record["kind"] == "candidate":
            fmt, cand = synthetic[record["id"]]
            if (fmt, cand) != (record["declared_format"], record["candidate"]):
                problems.append(f"{record['id']}: synthetic candidate differs from the generator")
        elif record["id"] in development:
            case = development[record["id"]]
            if case["input"]["text"] != record["text"] or decline_gate.format_for_case(case["metadata"]) != record["declared_format"]:
                problems.append(f"{record['id']}: text or format differs from the committed or re-rendered case")
        if record["kind"] == "text" and hashlib.sha256(record["text"].encode("utf-8")).hexdigest() != record["text_sha256"]:
            problems.append(f"{record['id']}: text hash differs")
        if expected_for(record["candidate"], record["declared_format"]) != record["expected"]:
            problems.append(f"{record['id']}: expected output differs from the frozen Python")
    if lines[0] != meta(lines[0]["sets"], lines[0]["parser_version"]):
        problems.append("vector metadata differs (reference hashes or pattern changed)")
    fda_records = {r["id"] for r in lines[1:] if r.get("corpus") == "fda188" and r.get("split") == "untouched"}
    muesli = render.muesli_truth(ZERO_HASH)
    for line in jsonl_lines(MUTATIONS):
        record = json.loads(line)
        # Each truth is the committed or re-rendered case's own truth; untouched FDA truth (rendered from
        # the private CSV) is tied to a committed text case and to the run's dataset hash at export.
        if record["id"] in development:
            if development[record["id"]]["truth"] != record["truth"]:
                problems.append(f"{record['id']}: mutation truth differs from the committed or re-rendered case")
        elif record["id"] == "synthetic:muesli":
            if record["truth"] != muesli:
                problems.append("synthetic:muesli: truth differs from the generator")
        elif record["id"] not in fda_records:
            problems.append(f"{record['id']}: mutation truth has no source case")
        if mutation_record(record["id"], record["truth"]) != {
            k: record[k] for k in ("id", "truth", "jurisdiction", "original", "mutations")
        }:
            problems.append(f"{record['id']}: mutation outcome differs from the frozen Python")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("tables", help="write the frozen gate tables and code-point runs")
    vectors = sub.add_parser("vectors", help="run the Swift parser and write the parity vectors")
    vectors.add_argument("--parser-binary", type=Path, required=True)
    vectors.add_argument("--untouched-fda-csv", type=Path, help="the hash-checked FDA 188 CSV (outside the repository); optional")
    sub.add_parser("check", help="re-derive the committed files with the frozen Python")
    args = parser.parse_args(argv)
    if args.command == "tables":
        command_tables()
    elif args.command == "vectors":
        command_vectors(args.parser_binary, args.untouched_fda_csv)
    else:
        problems = check()
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1 if problems else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
