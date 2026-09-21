#!/usr/bin/env python3
"""Create the frozen public/synthetic bootstrap set without invoking the matcher."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path
from typing import Any


UNKNOWN_IDENTITY = {
    "preparation": "unknown",
    "bone": "unknown",
    "skin": "unknown",
    "drained": "unknown",
    "packing_medium": "unknown",
    "fortification": "unknown",
    "salt_state": "unknown",
    "serving_basis": "unknown",
    "edible_quantity": "unknown",
    "formulation": "unknown",
}

HARD_FAMILIES = {
    "preparation": ("raw", "cooked"),
    "bone": ("boneless", "with_bone"),
    "skin": ("skinless", "skin_on"),
    "drained": ("drained", "undrained"),
    "packing_medium": ("brine", "oil"),
    "fortification": ("unfortified", "fortified"),
    "salt_state": ("unsalted", "salted"),
    "serving_basis": ("per_100_g", "per_serving"),
}


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def split_for(case_id: str) -> str:
    bucket = int(hashlib.sha256(case_id.encode()).hexdigest()[:8], 16) % 10
    return "tuning" if bucket < 6 else "calibration" if bucket < 8 else "gate"


def case(case_id: str, family: str, provenance: str, query: dict[str, Any], label: dict[str, Any]) -> dict[str, Any]:
    return {
        "case_id": case_id,
        "split": split_for(case_id),
        "family": family,
        "provenance": provenance,
        "query": query,
        "label": label,
    }


def numeric_nutrients(keys: list[str], seed: int, multiplier: float = 1.0) -> dict[str, Any]:
    result = {}
    for offset, key in enumerate(keys, start=1):
        value = round((seed + offset) * 0.17 * multiplier, 6)
        result[key] = {"state": "numeric", "unit": "fixture_unit", "value": f"{value:g}"}
    return result


def synthetic_record(record_id: str, name: str, identity: dict[str, str], nutrients: dict[str, Any]) -> dict[str, Any]:
    return {
        "record_id": record_id,
        "source_release_id": "synthetic:generic-match-bootstrap:v1",
        "name": name,
        "description": "Synthetic evaluation record; not a food or personal observation.",
        "identity": identity,
        "nutrients": nutrients,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    corpus_bytes = gzip.decompress(args.corpus.read_bytes())
    corpus = json.loads(corpus_bytes)
    public_records = sorted(
        corpus["records"],
        key=lambda record: hashlib.sha256(record["record_id"].encode()).hexdigest(),
    )
    nutrient_keys = sorted(public_records[0]["nutrients"])
    cases = []
    synthetic_records = []

    for index, record in enumerate(public_records[:400], start=1):
        record_id = record["record_id"]
        cases.append(
            case(
                f"public-exact-{index:04d}",
                "exact_public_name",
                "public_cofid_2021",
                {"text": record["name"], "identity": record["identity"]},
                {
                    "acceptable_record_ids": [record_id],
                    "exact_record_ids": [record_id],
                    "expected_action": "show_exact_for_explicit_selection",
                    "reference_record_id": record_id,
                    "required_blocked": {},
                },
            )
        )

    for index, record in enumerate(public_records[400:700], start=1):
        record_id = record["record_id"]
        clauses = [clause.strip() for clause in record["name"].split(",") if clause.strip()]
        transformed = " ".join(reversed(clauses)) if len(clauses) > 1 else " ".join(reversed(record["name"].split()))
        expected_action = (
            "show_exact_for_explicit_selection"
            if transformed.casefold() == record["name"].casefold()
            else "show_closest_for_explicit_selection"
        )
        cases.append(
            case(
                f"public-perturbed-{index:04d}",
                "public_name_token_order",
                "public_cofid_2021",
                {"text": transformed, "identity": record["identity"]},
                {
                    "acceptable_record_ids": [record_id],
                    "exact_record_ids": [record_id],
                    "expected_action": expected_action,
                    "reference_record_id": record_id,
                    "required_blocked": {},
                },
            )
        )

    for family, (target_value, conflict_value) in HARD_FAMILIES.items():
        for ordinal in range(1, 41):
            stem = f"synthetic {family.replace('_', ' ')} case {ordinal:03d}"
            target_id = f"synthetic:hard:{family}:{ordinal:03d}:target"
            conflict_id = f"synthetic:hard:{family}:{ordinal:03d}:conflict"
            query_identity = dict(UNKNOWN_IDENTITY)
            query_identity[family] = target_value
            target_identity = dict(query_identity)
            conflict_identity = dict(query_identity)
            conflict_identity[family] = conflict_value
            synthetic_records.extend(
                [
                    synthetic_record(target_id, f"{stem} {target_value}", target_identity, numeric_nutrients(nutrient_keys, ordinal)),
                    synthetic_record(conflict_id, stem, conflict_identity, numeric_nutrients(nutrient_keys, ordinal, 1.8)),
                ]
            )
            cases.append(
                case(
                    f"hard-{family}-{ordinal:03d}",
                    f"hard_negative_{family}",
                    "synthetic_public_bootstrap",
                    {"text": stem, "identity": query_identity},
                    {
                        "acceptable_record_ids": [target_id],
                        "exact_record_ids": [target_id],
                        "expected_action": "show_closest_for_explicit_selection",
                        "reference_record_id": target_id,
                        "required_blocked": {conflict_id: [family]},
                    },
                )
            )

    for ordinal in range(1, 81):
        stem = f"synthetic reformulated soup {ordinal:03d}"
        target_id = f"synthetic:reformulation:{ordinal:03d}:v2"
        conflict_id = f"synthetic:reformulation:{ordinal:03d}:v1"
        query_identity = dict(UNKNOWN_IDENTITY)
        query_identity["formulation"] = "v2"
        target_identity = dict(query_identity)
        conflict_identity = dict(query_identity)
        conflict_identity["formulation"] = "v1"
        synthetic_records.extend(
            [
                synthetic_record(target_id, f"{stem} current", target_identity, numeric_nutrients(nutrient_keys, ordinal + 100)),
                synthetic_record(conflict_id, stem, conflict_identity, numeric_nutrients(nutrient_keys, ordinal + 100, 1.25)),
            ]
        )
        cases.append(
            case(
                f"reformulation-{ordinal:03d}",
                "reformulation_near_duplicate",
                "synthetic_public_bootstrap",
                {"text": stem, "identity": query_identity},
                {
                    "acceptable_record_ids": [target_id],
                    "exact_record_ids": [target_id],
                    "expected_action": "show_closest_for_explicit_selection",
                    "reference_record_id": target_id,
                    "required_blocked": {conflict_id: ["formulation"]},
                },
            )
        )

    for ordinal in range(1, 81):
        stem = f"synthetic porridge case {ordinal:03d}"
        reference_id = f"synthetic:minor:{ordinal:03d}:reference"
        close_id = f"synthetic:minor:{ordinal:03d}:close"
        identity = dict(UNKNOWN_IDENTITY)
        identity["preparation"] = "cooked"
        synthetic_records.extend(
            [
                synthetic_record(reference_id, f"{stem} plain", identity, numeric_nutrients(nutrient_keys, ordinal + 200)),
                synthetic_record(close_id, f"{stem} oats", identity, numeric_nutrients(nutrient_keys, ordinal + 200, 1.03)),
            ]
        )
        cases.append(
            case(
                f"minor-difference-{ordinal:03d}",
                "acceptable_minor_difference",
                "synthetic_public_bootstrap",
                {"text": f"{stem} oats", "identity": identity},
                {
                    "acceptable_record_ids": [reference_id, close_id],
                    "exact_record_ids": [close_id],
                    "expected_action": "show_exact_for_explicit_selection",
                    "reference_record_id": reference_id,
                    "required_blocked": {},
                },
            )
        )

    for ordinal in range(1, 101):
        cases.append(
            case(
                f"no-result-{ordinal:03d}",
                "no_acceptable_candidate",
                "synthetic_public_bootstrap",
                {"text": f"zzzxqv unmatched synthetic item {ordinal:03d}", "identity": dict(UNKNOWN_IDENTITY)},
                {
                    "acceptable_record_ids": [],
                    "exact_record_ids": [],
                    "expected_action": "decline",
                    "reference_record_id": None,
                    "required_blocked": {},
                },
            )
        )

    payload = {
        "schema_version": 1,
        "source_releases": [corpus["source"], {
            "source_id": "synthetic_generic_match_bootstrap",
            "release_id": "synthetic:generic-match-bootstrap:v1",
            "title": "Synthetic public bootstrap cases for issue #92",
            "personal_data": False,
        }],
        "personal_gate": {"status": "deferred", "reason": "No authorised frozen personal case set was available."},
        "synthetic_records": sorted(synthetic_records, key=lambda record: record["record_id"]),
        "cases": sorted(cases, key=lambda item: item["case_id"]),
    }
    rendered = canonical_json(payload)
    args.output.write_bytes(rendered)
    print(json.dumps({"cases": len(cases), "synthetic_records": len(synthetic_records), "sha256": hashlib.sha256(rendered).hexdigest()}))


if __name__ == "__main__":
    main()
