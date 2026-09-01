#!/usr/bin/env python3
"""Read the latest Codex token counter and optionally calculate a phase delta."""

from __future__ import annotations

import argparse
from decimal import Decimal, ROUND_HALF_UP
import json
from pathlib import Path
import sys
from typing import Any


COUNTER_FIELDS = ("input_tokens", "cached_input_tokens", "output_tokens")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Measure whole-session Codex usage or a delta from a captured baseline."
    )
    parser.add_argument("session", type=Path, help="Codex rollout JSONL path")
    parser.add_argument(
        "--baseline",
        nargs=3,
        type=int,
        metavar=("INPUT", "CACHED_INPUT", "OUTPUT"),
        help="Counters captured at the start of the measured phase",
    )
    parser.add_argument("--uncached-input-rate", type=Decimal)
    parser.add_argument("--cached-input-rate", type=Decimal)
    parser.add_argument("--output-rate", type=Decimal)
    parser.add_argument("--json", action="store_true", dest="as_json")
    return parser.parse_args()


def latest_counter(path: Path) -> dict[str, int]:
    latest: dict[str, int] | None = None
    try:
        lines = path.open(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"cannot read session: {error}") from error

    with lines:
        for line in lines:
            try:
                event: Any = json.loads(line)
            except json.JSONDecodeError:
                # A live writer may leave its final line temporarily incomplete.
                continue
            if event.get("type") != "event_msg":
                continue
            payload = event.get("payload", {})
            if payload.get("type") != "token_count":
                continue
            usage = payload.get("info", {}).get("total_token_usage")
            if not isinstance(usage, dict):
                continue
            if all(isinstance(usage.get(field), int) for field in COUNTER_FIELDS):
                latest = {field: usage[field] for field in COUNTER_FIELDS}

    if latest is None:
        raise ValueError("no complete token-count event found")
    validate_counter(latest, label="session")
    return latest


def validate_counter(counter: dict[str, int], label: str) -> None:
    if any(counter[field] < 0 for field in COUNTER_FIELDS):
        raise ValueError(f"{label} counters must be non-negative")
    if counter["cached_input_tokens"] > counter["input_tokens"]:
        raise ValueError(f"{label} cached input exceeds total input")


def phase_counter(
    current: dict[str, int], baseline_values: list[int] | None
) -> tuple[str, dict[str, int]]:
    if baseline_values is None:
        return "whole-session", current
    baseline = dict(zip(COUNTER_FIELDS, baseline_values, strict=True))
    validate_counter(baseline, label="baseline")
    delta = {field: current[field] - baseline[field] for field in COUNTER_FIELDS}
    if any(value < 0 for value in delta.values()):
        raise ValueError("session counters decreased relative to the baseline")
    validate_counter(delta, label="phase")
    return "delta", delta


def calculate_cost(
    usage: dict[str, int], args: argparse.Namespace
) -> tuple[Decimal | None, Decimal | None]:
    rates = (
        args.uncached_input_rate,
        args.cached_input_rate,
        args.output_rate,
    )
    if all(rate is None for rate in rates):
        return None, None
    if any(rate is None for rate in rates):
        raise ValueError("provide all three rates or none")
    if any(rate < 0 for rate in rates if rate is not None):
        raise ValueError("rates must be non-negative")

    million = Decimal(1_000_000)
    uncached = usage["input_tokens"] - usage["cached_input_tokens"]
    exact = (
        Decimal(uncached) * args.uncached_input_rate
        + Decimal(usage["cached_input_tokens"]) * args.cached_input_rate
        + Decimal(usage["output_tokens"]) * args.output_rate
    ) / million
    return exact, exact.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def main() -> int:
    args = parse_args()
    try:
        current = latest_counter(args.session)
        boundary, usage = phase_counter(current, args.baseline)
        exact_cost, rounded_cost = calculate_cost(usage, args)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    total = usage["input_tokens"] + usage["output_tokens"]
    result: dict[str, Any] = {
        "boundary": boundary,
        **usage,
        "uncached_input_tokens": (
            usage["input_tokens"] - usage["cached_input_tokens"]
        ),
        "total_tokens": total,
    }
    if exact_cost is not None and rounded_cost is not None:
        result["api_equivalent_exact"] = format(exact_cost, "f")
        result["api_equivalent_rounded"] = format(rounded_cost, ".2f")

    if args.as_json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0

    for key, value in result.items():
        print(f"{key}={value}")
    cells = (
        f"{usage['input_tokens']:,} ({usage['cached_input_tokens']:,}) | "
        f"{usage['output_tokens']:,} | {total:,}"
    )
    if rounded_cost is not None:
        cells += f" | ${rounded_cost:.2f}"
    print(f"markdown_cells={cells}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
