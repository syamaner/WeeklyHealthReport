#!/usr/bin/env python3
"""Run and verify the frozen issue #92 generic-food evaluation."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from matcher import one_sided_wilson_lower, retrieve  # noqa: E402


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def load_and_verify(contract: dict[str, Any], corpus_path: Path, gold_path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    gzip_bytes = corpus_path.read_bytes()
    canonical_corpus = gzip.decompress(gzip_bytes)
    gold_bytes = gold_path.read_bytes()
    expected = contract["fixtures"]
    actual = {
        "corpus_gzip_sha256": hashlib.sha256(gzip_bytes).hexdigest(),
        "corpus_canonical_sha256": hashlib.sha256(canonical_corpus).hexdigest(),
        "gold_sha256": hashlib.sha256(gold_bytes).hexdigest(),
    }
    for key, digest in actual.items():
        if digest != expected[key]:
            raise ValueError(f"{key} mismatch: {digest}; expected {expected[key]}")
    corpus = json.loads(canonical_corpus)
    gold = json.loads(gold_bytes)
    if canonical_json(corpus) != canonical_corpus:
        raise ValueError("corpus is not canonical JSON before compression")
    if canonical_json(gold) != gold_bytes:
        raise ValueError("gold set is not canonical JSON")
    return corpus, gold


def nutrient_errors(reference: dict[str, Any], candidate: dict[str, Any]) -> list[dict[str, Any]]:
    errors = []
    for key in sorted(set(reference.get("nutrients", {})) & set(candidate.get("nutrients", {}))):
        left = reference["nutrients"][key]
        right = candidate["nutrients"][key]
        if left.get("state") != "numeric" or right.get("state") != "numeric":
            continue
        reference_value = float(left["value"])
        candidate_value = float(right["value"])
        absolute = abs(candidate_value - reference_value)
        relative = absolute / abs(reference_value) if reference_value else None
        errors.append({"nutrient": key, "absolute": absolute, "relative": relative})
    return errors


def evaluate(contract: dict[str, Any], corpus: dict[str, Any], gold: dict[str, Any], selected_split: str | None = None) -> dict[str, Any]:
    records = corpus["records"] + gold["synthetic_records"]
    by_id = {record["record_id"]: record for record in records}
    if len(by_id) != len(records):
        raise ValueError("duplicate source record ID")
    all_cases = gold["cases"]
    if len(all_cases) < contract["gold_set"]["minimum_cases"]:
        raise ValueError("gold set is smaller than the frozen minimum")
    if len(all_cases) < contract["gold_set"]["aim_cases"]:
        raise ValueError("gold set does not meet the frozen aim")
    if gold["personal_gate"]["status"] != "deferred":
        raise ValueError("this contract expects the personal gate to remain deferred")
    cases = [item for item in all_cases if selected_split is None or item["split"] == selected_split]
    if not cases:
        raise ValueError("selected split is empty")

    failures = Counter({
        "retrieval_miss": 0,
        "hard_rule_failure": 0,
        "ranking_failure": 0,
        "explanation_failure": 0,
        "calibration_failure": 0,
        "action_failure": 0,
    })
    family_counts = Counter()
    split_counts = Counter(item["split"] for item in cases)
    non_decline = 0
    top_correct = 0
    candidate_recalled = 0
    correct_declines = 0
    catastrophic_acceptances = 0
    action_correct = 0
    score_bins: dict[str, list[bool]] = defaultdict(list)
    per_nutrient: dict[str, list[tuple[float, float | None]]] = defaultdict(list)

    for item in cases:
        family_counts[item["family"]] += 1
        label = item["label"]
        result = retrieve(item["query"]["text"], item["query"]["identity"], records, contract)
        candidate_ids = [candidate.record_id for candidate in result.candidates]
        acceptable = set(label["acceptable_record_ids"])
        if acceptable:
            non_decline += 1
            recalled = bool(acceptable & set(candidate_ids))
            candidate_recalled += int(recalled)
            if not recalled:
                failures["retrieval_miss"] += 1
            top_is_correct = bool(candidate_ids and candidate_ids[0] in acceptable)
            top_correct += int(top_is_correct)
            if not top_is_correct and recalled:
                failures["ranking_failure"] += 1
            if candidate_ids:
                score = result.candidates[0].score
                bin_name = f"{int(score * 10) / 10:.1f}-{int(score * 10) / 10 + 0.1:.1f}"
                score_bins[bin_name].append(top_is_correct)
        else:
            declined = result.action == "decline"
            correct_declines += int(declined)
            if not declined:
                failures["calibration_failure"] += 1

        if result.action == label["expected_action"]:
            action_correct += 1
        else:
            failures["action_failure"] += 1

        if candidate_ids and candidate_ids[0] not in set(label["exact_record_ids"]):
            if not result.candidates[0].differences:
                failures["explanation_failure"] += 1

        for record_id, expected_reasons in label["required_blocked"].items():
            actual_reasons = result.blocked.get(record_id, [])
            if not set(expected_reasons).issubset(actual_reasons):
                failures["hard_rule_failure"] += 1
            if record_id in candidate_ids:
                catastrophic_acceptances += 1

        if candidate_ids and label["reference_record_id"] and candidate_ids[0] != label["reference_record_id"]:
            for error in nutrient_errors(by_id[label["reference_record_id"]], by_id[candidate_ids[0]]):
                per_nutrient[error["nutrient"]].append((error["absolute"], error["relative"]))

    z = contract["metrics"]["one_sided_95_z"]
    lower_bound = one_sided_wilson_lower(top_correct, non_decline, z)
    result = {
        "schema_version": 1,
        "contract_version": contract["contract_version"],
        "matcher_version": contract["matcher_version"],
        "scope": selected_split or "all_frozen_splits",
        "source_release_ids": sorted(source["release_id"] for source in gold["source_releases"]),
        "fixture_counts": {
            "cases": len(cases),
            "all_frozen_cases": len(all_cases),
            "source_records": len(records),
            "by_split": dict(sorted(split_counts.items())),
            "by_family": dict(sorted(family_counts.items())),
            "personal_gate": "deferred",
        },
        "metrics": {
            "retrieval_recall": candidate_recalled / non_decline if non_decline else None,
            "top_rank_precision": top_correct / non_decline if non_decline else None,
            "top_rank_precision_one_sided_95_lower": lower_bound,
            "explicit_selection_success": candidate_recalled / non_decline if non_decline else None,
            "correct_decline_rate": correct_declines / (len(cases) - non_decline) if len(cases) > non_decline else None,
            "action_accuracy": action_correct / len(cases),
            "catastrophic_hard_negative_acceptances": catastrophic_acceptances,
            "failures": dict(sorted(failures.items())),
            "score_calibration": {
                name: {"cases": len(values), "top_rank_precision": sum(values) / len(values)}
                for name, values in sorted(score_bins.items())
            },
            "approximate_match_nutrient_error": {
                key: {
                    "comparisons": len(values),
                    "mean_absolute_fixture_units": statistics.fmean(item[0] for item in values),
                    "mean_relative": statistics.fmean(item[1] for item in values if item[1] is not None),
                }
                for key, values in sorted(per_nutrient.items())
            },
        },
        "gate": {
            "zero_catastrophic_acceptances": catastrophic_acceptances == 0,
            "minimum_retrieval_recall": (candidate_recalled / non_decline) >= contract["metrics"]["minimum_retrieval_recall"],
            "minimum_explicit_selection_success": (candidate_recalled / non_decline) >= contract["metrics"]["minimum_explicit_selection_success"],
            "automatic_acceptance_eligible": False,
        },
        "recommendation": {
            "decision": "keep_user_selection_only",
            "automatic_acceptance": "disabled",
            "reason": "The frozen public/synthetic bootstrap does not include an authorised untouched personal-case gate; its metrics cannot establish production-distribution precision.",
            "allowed_product_envelope": [
                "deterministic local candidate retrieval",
                "hard contradictions before ranking",
                "ranked exact or closest candidates with material differences",
                "explicit accept, choose-another, or decline",
            ],
        },
    }
    if not all(result["gate"][key] for key in ("zero_catastrophic_acceptances", "minimum_retrieval_recall", "minimum_explicit_selection_success")):
        raise ValueError(f"evaluation gate failed: {result['gate']}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--gold", required=True, type=Path)
    parser.add_argument("--split", choices=("tuning", "calibration", "gate"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-report", type=Path)
    args = parser.parse_args()
    contract = json.loads(args.contract.read_text())
    matcher_path = Path(__file__).with_name("matcher.py")
    matcher_digest = hashlib.sha256(matcher_path.read_bytes()).hexdigest()
    expected_matcher_digest = contract["implementation"]["matcher_source_sha256"]
    if matcher_digest != expected_matcher_digest:
        raise SystemExit(
            f"matcher source hash mismatch: {matcher_digest}; expected {expected_matcher_digest}"
        )
    corpus, gold = load_and_verify(contract, args.corpus, args.gold)
    report = canonical_json(evaluate(contract, corpus, gold, args.split))
    if args.output:
        args.output.write_bytes(report)
    if args.verify_report and args.verify_report.read_bytes() != report:
        raise SystemExit("committed evaluation report does not match the frozen inputs")
    if not args.output and not args.verify_report:
        sys.stdout.buffer.write(report)


if __name__ == "__main__":
    main()
