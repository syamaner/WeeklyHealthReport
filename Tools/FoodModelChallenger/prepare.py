#!/usr/bin/env python3
"""Offline preparation only: freeze #92 candidates without exporting labels."""
from __future__ import annotations
import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

FROZEN_CONTRACT_SHA256 = "fc607d52360c38ae28381c4f6c70ad85dd5d0d6887192dd22d01efefdc8ffbd2"
BASELINE = Path(__file__).resolve().parents[1] / "FoodMatchEvaluation"
sys.path.insert(0, str(BASELINE))
from evaluate import canonical_json, load_and_verify  # noqa: E402
from matcher import retrieve  # noqa: E402


def packets(contract: dict, corpus: dict, gold: dict) -> list[dict]:
    records = corpus["records"] + gold["synthetic_records"]
    by_id = {record["record_id"]: record for record in records}
    if len(by_id) != len(records):
        raise ValueError("duplicate source record ID")
    output = []
    for case in gold["cases"]:
        result = retrieve(case["query"]["text"], case["query"]["identity"], records, contract)
        output.append({
            "case_id": case["case_id"], "split": case["split"], "query": case["query"],
            "candidates": [by_id[candidate.record_id] for candidate in result.candidates],
        })
    return output


def validate_choice(packet: dict, record_id: str | None) -> None:
    """A challenger can decline or choose an admitted record, never add one."""
    if record_id is None:
        return
    if not isinstance(record_id, str) or record_id not in {item["record_id"] for item in packet["candidates"]}:
        raise ValueError("choice outside frozen hard-rule-admitted candidate set")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    contract_path = BASELINE / "frozen-contract-v1.json"
    if hashlib.sha256(contract_path.read_bytes()).hexdigest() != FROZEN_CONTRACT_SHA256:
        raise ValueError("frozen contract hash mismatch")
    contract = json.loads(contract_path.read_bytes())
    matcher = BASELINE / "matcher.py"
    if hashlib.sha256(matcher.read_bytes()).hexdigest() != contract["implementation"]["matcher_source_sha256"]:
        raise ValueError("frozen matcher source hash mismatch")
    corpus, gold = load_and_verify(contract, BASELINE / "fixtures/cofid-2021-evaluation-v1.json.gz",
                                   BASELINE / "fixtures/gold-set-v1.json")
    values = packets(contract, corpus, gold)
    payload = canonical_json({"schema_version": "food-model-candidate-packets-v1", "cases": values})
    manifest = {
        "schema_version": "food-model-preparation-v1", "run_ready": False,
        "provider_calls": 0, "personal_data": False, "labels_in_packets": False,
        "frozen_contract_sha256": hashlib.sha256(contract_path.read_bytes()).hexdigest(),
        "matcher_sha256": hashlib.sha256(matcher.read_bytes()).hexdigest(),
        "packets_sha256": hashlib.sha256(payload).hexdigest(), "packets_byte_count": len(payload),
        "nonempty_case_count": sum(bool(case["candidates"]) for case in values),
        "case_count": len(values), "split_counts": dict(Counter(case["split"] for case in values)),
        "model": None, "route": None, "prompt_sha256": None, "generation_settings": None,
        "thresholds": None, "maximum_calls": None, "maximum_spend": None,
        "retention_policy": None, "execution_authority": None,
    }
    args.output.write_bytes(payload)
    args.manifest.write_bytes(canonical_json(manifest))


if __name__ == "__main__":
    main()
