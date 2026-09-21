#!/usr/bin/env python3
"""Pure deterministic retrieval and hard-rule matching for issue #92."""

from __future__ import annotations

import math
import re
import unicodedata
from dataclasses import dataclass
from typing import Any, Iterable


UNKNOWN = "unknown"
HARD_IDENTITY_FIELDS = (
    "preparation",
    "bone",
    "skin",
    "drained",
    "packing_medium",
    "fortification",
    "salt_state",
    "serving_basis",
    "edible_quantity",
    "formulation",
)

TOKEN_ALIASES = {
    "aubergines": "aubergine",
    "eggplant": "aubergine",
    "eggplants": "aubergine",
    "garbanzo": "chickpea",
    "garbanzos": "chickpea",
    "yogurt": "yoghurt",
    "yogurts": "yoghurt",
}


def normalize_text(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value)
    ascii_text = "".join(character for character in decomposed if not unicodedata.combining(character))
    tokens = re.findall(r"[a-z0-9]+", ascii_text.casefold())
    return " ".join(TOKEN_ALIASES.get(token, token) for token in tokens)


def token_set(value: str) -> frozenset[str]:
    normalized = normalize_text(value)
    return frozenset(normalized.split()) if normalized else frozenset()


def identity_contradictions(expected: dict[str, str], candidate: dict[str, str]) -> list[str]:
    """Return closed hard contradictions before any ranking is considered.

    A known expected field requires the same known candidate value. Unknown query
    fields do not invent a constraint; they still prevent any automatic action at
    the policy layer.
    """

    contradictions = []
    for field in HARD_IDENTITY_FIELDS:
        expected_value = expected.get(field, UNKNOWN)
        if expected_value == UNKNOWN:
            continue
        candidate_value = candidate.get(field, UNKNOWN)
        if candidate_value == UNKNOWN or candidate_value != expected_value:
            contradictions.append(field)
    return contradictions


def lexical_features(query: str, candidate_name: str) -> dict[str, float]:
    query_normalized = normalize_text(query)
    candidate_normalized = normalize_text(candidate_name)
    query_tokens = token_set(query)
    candidate_tokens = token_set(candidate_name)
    intersection = query_tokens & candidate_tokens
    union = query_tokens | candidate_tokens
    return {
        "exact_name": 1.0 if query_normalized == candidate_normalized and query_normalized else 0.0,
        "query_coverage": len(intersection) / len(query_tokens) if query_tokens else 0.0,
        "candidate_coverage": len(intersection) / len(candidate_tokens) if candidate_tokens else 0.0,
        "jaccard": len(intersection) / len(union) if union else 0.0,
    }


def weighted_score(features: dict[str, float], weights: dict[str, float]) -> float:
    return sum(features[name] * weights[name] for name in sorted(weights))


def material_differences(query: str, expected: dict[str, str], candidate: dict[str, Any]) -> list[str]:
    differences = []
    query_tokens = token_set(query)
    candidate_tokens = token_set(candidate["name"])
    for token in sorted(candidate_tokens - query_tokens):
        differences.append(f"candidate_only_token:{token}")
    for token in sorted(query_tokens - candidate_tokens):
        differences.append(f"query_only_token:{token}")
    for field in HARD_IDENTITY_FIELDS:
        expected_value = expected.get(field, UNKNOWN)
        candidate_value = candidate.get("identity", {}).get(field, UNKNOWN)
        if expected_value != UNKNOWN and expected_value != candidate_value:
            differences.append(f"{field}:{expected_value}->{candidate_value}")
    return differences


@dataclass(frozen=True)
class RankedCandidate:
    record_id: str
    score: float
    features: dict[str, float]
    differences: list[str]


@dataclass(frozen=True)
class RetrievalResult:
    candidates: list[RankedCandidate]
    blocked: dict[str, list[str]]
    action: str


def retrieve(
    query: str,
    identity: dict[str, str],
    records: Iterable[dict[str, Any]],
    contract: dict[str, Any],
) -> RetrievalResult:
    retrieval = contract["retrieval"]
    weights = retrieval["weights"]
    minimum_score = retrieval["minimum_score"]
    candidates: list[RankedCandidate] = []
    blocked: dict[str, list[str]] = {}

    for record in records:
        contradictions = identity_contradictions(identity, record.get("identity", {}))
        if contradictions:
            blocked[record["record_id"]] = contradictions
            continue
        features = lexical_features(query, record["name"])
        score = weighted_score(features, weights)
        if score < minimum_score:
            continue
        candidates.append(
            RankedCandidate(
                record_id=record["record_id"],
                score=score,
                features=features,
                differences=material_differences(query, identity, record),
            )
        )

    candidates.sort(key=lambda item: (-item.score, item.record_id))
    candidates = candidates[: retrieval["candidate_limit"]]
    if not candidates:
        action = "decline"
    elif candidates[0].features["exact_name"] == 1.0:
        action = "show_exact_for_explicit_selection"
    else:
        action = "show_closest_for_explicit_selection"
    return RetrievalResult(candidates=candidates, blocked=blocked, action=action)


def one_sided_wilson_lower(successes: int, total: int, z: float) -> float | None:
    if total == 0:
        return None
    proportion = successes / total
    denominator = 1.0 + z * z / total
    centre = proportion + z * z / (2.0 * total)
    margin = z * math.sqrt((proportion * (1.0 - proportion) + z * z / (4.0 * total)) / total)
    return max(0.0, (centre - margin) / denominator)
