"""Route C routing rules and response checks (plan section 8.1). Pure; no I/O.

Every request pins one endpoint with the same provider block as the app's
`OpenRouterFoodProvider`: `only` and `order` set to that endpoint, no fallbacks,
parameters required, data collection denied and ZDR required. A response is accepted
only when its model and provider match the request. Cost is the `usage.cost` value
OpenRouter reports on the raw response; Inspect 0.3.276's `ModelUsage.total_cost` is
computed from Inspect's own price table, not from that field, so it is not used. A
missing or non-numeric cost is unknown, never zero.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Any


@dataclass(frozen=True)
class RouteCModel:
    label: str
    model: str
    endpoint: str
    # The provider name OpenRouter returns for that endpoint, recorded from the catalogue on the run day.
    provider_name: str


def provider_block(endpoint: str) -> dict[str, Any]:
    return {
        "only": [endpoint],
        "order": [endpoint],
        "allow_fallbacks": False,
        "require_parameters": True,
        "data_collection": "deny",
        "zdr": True,
    }


def model_args(target: RouteCModel) -> dict[str, Any]:
    """Inspect `model_args` for the OpenRouter provider (`openrouter/<model>`)."""
    return {"provider": provider_block(target.endpoint)}


def reported_cost(raw: dict[str, Any] | None) -> Decimal | None:
    usage = raw.get("usage") if isinstance(raw, dict) else None
    cost = usage.get("cost") if isinstance(usage, dict) else None
    if isinstance(cost, bool) or not isinstance(cost, int | float | str):
        return None
    try:
        value = Decimal(str(cost))
    except InvalidOperation:
        return None
    return value if value >= 0 else None


def _normalise_provider(name: Any) -> str:
    return str(name or "").strip().lower().replace(" ", "-")


def route_mismatches(raw: dict[str, Any] | None, target: RouteCModel) -> list[str]:
    """Reasons the response cannot be accepted; empty when model and provider match."""
    if not isinstance(raw, dict):
        return ["no raw response to verify the route"]
    problems = []
    if raw.get("model") != target.model:
        problems.append(f"response model {raw.get('model')!r} does not match {target.model!r}")
    if _normalise_provider(raw.get("provider")) != _normalise_provider(target.provider_name):
        problems.append(f"response provider {raw.get('provider')!r} does not match {target.endpoint!r}")
    choices = raw.get("choices")
    if isinstance(choices, list) and choices and isinstance(choices[0], dict):
        if choices[0].get("finish_reason") != "stop":
            problems.append(f"finish_reason {choices[0].get('finish_reason')!r}")
    return problems
