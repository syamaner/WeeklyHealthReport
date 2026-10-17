"""Route C routing rules and response checks (plan section 8.1). Pure; no I/O.

Every request pins one endpoint with the same provider block as the app's
`OpenRouterFoodProvider`: `only` and `order` set to that endpoint, no fallbacks,
parameters required, data collection denied and ZDR required. A response is accepted
only when its model matches the request under the slug rule below (the exact slug or
its dated snapshot) and its provider matches the pinned endpoint. Cost is the `usage.cost` value
OpenRouter reports on the raw response; Inspect 0.3.276's `ModelUsage.total_cost` is
computed from Inspect's own price table, not from that field, so it is not used. A
missing or non-numeric cost is unknown, never zero.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Any


@dataclass(frozen=True)
class RouteCModel:
    label: str
    model: str
    endpoint: str
    # The provider name OpenRouter returns for that endpoint, recorded from the catalogue on the run day.
    provider_name: str
    # "off" sends reasoning {enabled: false}; "on" sends {enabled: true} at the model's default effort.
    reasoning: str = "off"


def provider_block(endpoint: str) -> dict[str, Any]:
    """The app's provider block (ZDR, data collection denied); still used by the untouched truth drafting."""
    return {
        "only": [endpoint],
        "order": [endpoint],
        "allow_fallbacks": False,
        "require_parameters": True,
        "data_collection": "deny",
        "zdr": True,
    }


def route_c_provider_block(endpoint: str) -> dict[str, Any]:
    """Route C's evaluation-only block (owner decisions 1 and 2, 17 October 2026): one pinned provider,
    no fallbacks, parameters required, without the ZDR and data-collection requirements. Product
    routing is unchanged and would still need `provider_block`."""
    return {"only": [endpoint], "order": [endpoint], "allow_fallbacks": False, "require_parameters": True}


ROUTE_C_MAX_TOKENS = 16384  # owner decision 3, 17 October 2026 (was 4096)


def _without_comments(node: Any) -> Any:
    if isinstance(node, dict):
        return {k: _without_comments(v) for k, v in node.items() if k != "$comment"}
    if isinstance(node, list):
        return [_without_comments(v) for v in node]
    return node


SCHEMA_DESCRIPTION = "The nutrition table printed in the image, transcribed as printed."


def route_c_request_body(target: RouteCModel, image_data_uri: str, instruction: str, wire_schema: dict[str, Any]) -> dict[str, Any]:
    """One route C chat-completions request: instruction and image only, strict schema, pinned provider.

    The schema block always carries a description: with `"description": null` (what Inspect
    sends when none is set) OpenRouter's Azure route for Luna answered outside the strict schema
    on 17 October 2026. No streaming, no tools, one choice.
    """
    if target.reasoning not in ("off", "on"):
        raise ValueError(f"reasoning must be off or on, not {target.reasoning!r}")
    # `$comment` is documentation only; Anthropic rejects it in a structured-output schema
    # (HTTP 400, 17 October 2026), so it is stripped for every model. Nothing else changes.
    wire_schema = _without_comments(wire_schema)
    return {
        "model": target.model,
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": instruction}, {"type": "image_url", "image_url": {"url": image_data_uri}}],
            }
        ],
        "response_format": {
            "type": "json_schema",
            "json_schema": {"name": "label_image_extraction_v1", "description": SCHEMA_DESCRIPTION, "strict": True, "schema": wire_schema},
        },
        "provider": route_c_provider_block(target.endpoint),
        "max_tokens": ROUTE_C_MAX_TOKENS,
        "reasoning": {"enabled": target.reasoning == "on"},
        "stream": False,
        "usage": {"include": True},
    }


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


# Model slug rule (#255 phase 2). OpenRouter may answer a request for `vendor/model`
# with the dated snapshot it actually served, for example `qwen/qwen3.5-397b-a17b-20260216`.
# A returned slug is accepted only when it is the requested slug exactly, or the
# requested slug followed by `-` and one date in a closed set of snapshot forms:
# YYYYMMDD, YYYY-MM-DD, MM-DD or MMDD. Anything else (another size, `-mini`,
# `-thinking`, `-v2`, `.1`, a `:free` or `:nitro` routing variant, another vendor) is
# a mismatch, so a family member can never pass for the model that was requested.
# Widening the set is a contract change.
# The suffix must also be a real calendar date (a month-day form is checked in a leap year).
SLUG_DATE_FORMATS = ("-%Y%m%d", "-%Y-%m-%d", "-%m-%d", "-%m%d")
SLUG_SUFFIX = re.compile(r"^-(?:\d{8}|\d{4}-\d{2}-\d{2}|\d{2}-\d{2}|\d{4})$")


def _is_calendar_date(suffix: str) -> bool:
    for form in SLUG_DATE_FORMATS:
        text, pattern = (suffix, form) if "%Y" in form else ("-2000" + suffix, "-%Y" + form)
        try:
            datetime.strptime(text, pattern)
        except ValueError:
            continue
        return True  # SLUG_SUFFIX has already fixed the digit counts
    return False


def model_slug_matches(requested: str, returned: Any) -> bool:
    if not isinstance(returned, str) or not requested:
        return False
    if returned == requested:
        return True
    suffix = returned[len(requested) :]
    return returned.startswith(requested) and bool(SLUG_SUFFIX.match(suffix)) and _is_calendar_date(suffix)


def logged_request_credentials(request: Any) -> list[str]:
    """Header names in a logged model request that could carry a credential.

    Inspect 0.3.276's OpenAI-compatible providers (including `openrouter/...`) log the
    request dict in `ModelEvent.call.request`, and that dict includes `extra_headers`
    (request id, session id and any `GenerateConfig.extra_headers`). The API key travels
    in the SDK client's own Authorization header, which is not in that dict; this check
    makes sure nothing puts a credential into the logged headers either.
    """
    headers = request.get("extra_headers") if isinstance(request, dict) else None
    if not isinstance(headers, dict):
        return []
    risky = ("authorization", "api-key", "x-api-key", "cookie", "proxy-authorization")
    return sorted(name for name in headers if str(name).lower() in risky or "token" in str(name).lower() or "key" in str(name).lower())


def _normalise_provider(name: Any) -> str:
    return str(name or "").strip().lower().replace(" ", "-")


def route_mismatches(raw: dict[str, Any] | None, target: RouteCModel) -> list[str]:
    """Reasons the response cannot be accepted; empty when model and provider match."""
    if not isinstance(raw, dict):
        return ["no raw response to verify the route"]
    problems = []
    if not model_slug_matches(target.model, raw.get("model")):
        problems.append(f"response model {raw.get('model')!r} does not match {target.model!r}")
    if _normalise_provider(raw.get("provider")) != _normalise_provider(target.provider_name):
        problems.append(f"response provider {raw.get('provider')!r} does not match {target.endpoint!r}")
    choices = raw.get("choices")
    if not (isinstance(choices, list) and choices and isinstance(choices[0], dict)):
        problems.append("no choices to verify finish_reason")
    elif choices[0].get("finish_reason") != "stop":
        # A missing finish_reason is a problem too: truncation cannot be ruled out.
        problems.append(f"finish_reason {choices[0].get('finish_reason')!r}")
    return problems
