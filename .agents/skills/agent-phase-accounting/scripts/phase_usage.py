#!/usr/bin/env python3
"""Measure Codex or Claude Code session token usage, whole-session or for a bounded phase."""

from __future__ import annotations

import argparse
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP
import json
from pathlib import Path
import sys
from typing import Any, Iterable, Iterator


CODEX_FIELDS = ("input_tokens", "cached_input_tokens", "output_tokens")
FIELDS = (
    "input_tokens",
    "cached_input_tokens",
    "cache_write_input_tokens",
    "cache_write_5m_input_tokens",
    "output_tokens",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Measure whole-session usage or a phase delta for a Codex or Claude Code session."
    )
    parser.add_argument("session", type=Path, help="Codex rollout JSONL or Claude Code session JSONL")
    parser.add_argument(
        "--format",
        choices=("auto", "codex", "claude"),
        default="auto",
        help="Transcript format (default: detect)",
    )
    parser.add_argument(
        "--baseline",
        nargs=3,
        type=int,
        metavar=("INPUT", "CACHED_INPUT", "OUTPUT"),
        help="Codex only: counters captured at the start of the measured phase",
    )
    parser.add_argument(
        "--since",
        help="Claude only: ISO 8601 timestamp; count only messages at or after it",
    )
    parser.add_argument(
        "--until",
        help="Claude only: ISO 8601 timestamp; count only messages before it",
    )
    parser.add_argument(
        "--include-subagents",
        action="store_true",
        help="Claude only: add <session>/subagents/*.jsonl next to the session file",
    )
    parser.add_argument("--uncached-input-rate", type=Decimal)
    parser.add_argument("--cached-input-rate", type=Decimal)
    parser.add_argument("--output-rate", type=Decimal)
    parser.add_argument(
        "--cache-write-rate",
        type=Decimal,
        help="Claude only: rate for 1-hour (or unclassified) cache writes; required when any are present",
    )
    parser.add_argument(
        "--cache-write-5m-rate",
        type=Decimal,
        help="Claude only: rate for 5-minute cache writes; required when any are present",
    )
    parser.add_argument("--json", action="store_true", dest="as_json")
    return parser.parse_args()


def read_events(path: Path) -> Iterator[Any]:
    """Stream events line by line so large transcripts are never held in memory."""
    try:
        handle = path.open(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"cannot read session: {error}") from error
    with handle:
        for line in handle:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                # A live writer may leave its final line temporarily incomplete.
                continue


def detect_format(events: Iterable[Any]) -> str:
    for event in events:
        if not isinstance(event, dict):
            continue
        if event.get("type") == "event_msg":
            return "codex"
        if isinstance(event.get("message"), dict) and "usage" in event["message"]:
            return "claude"
    raise ValueError("cannot detect transcript format; pass --format")


def codex_counter(events: Iterable[Any]) -> dict[str, int]:
    latest: dict[str, int] | None = None
    for event in events:
        if not isinstance(event, dict) or event.get("type") != "event_msg":
            continue
        payload = event.get("payload", {})
        if payload.get("type") != "token_count":
            continue
        usage = payload.get("info", {}).get("total_token_usage")
        if isinstance(usage, dict) and all(isinstance(usage.get(f), int) for f in CODEX_FIELDS):
            latest = {f: usage[f] for f in CODEX_FIELDS}
    if latest is None:
        raise ValueError("no complete token-count event found")
    latest["cache_write_input_tokens"] = 0
    latest["cache_write_5m_input_tokens"] = 0
    validate(latest, "session")
    return latest


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def claude_counter(paths: list[Path], since: str | None, until: str | None) -> dict[str, int]:
    start = parse_time(since) if since else None
    end = parse_time(until) if until else None
    # Streaming writes one record per content block; keep the last usage per message.
    messages: dict[str, dict[str, int]] = {}
    for path in paths:
        for event in read_events(path):
            if not isinstance(event, dict) or event.get("type") != "assistant":
                continue
            message = event.get("message")
            if not isinstance(message, dict) or not isinstance(message.get("usage"), dict):
                continue
            stamp = event.get("timestamp")
            if (start or end) and not isinstance(stamp, str):
                continue
            if stamp and start and parse_time(stamp) < start:
                continue
            if stamp and end and parse_time(stamp) >= end:
                continue
            usage = message["usage"]
            keys = ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens")
            values = {k: usage.get(k, 0) for k in keys}
            breakdown = usage.get("cache_creation")
            values["cache_write_5m"] = (
                breakdown.get("ephemeral_5m_input_tokens", 0) if isinstance(breakdown, dict) else 0
            )
            if not all(isinstance(v, int) for v in values.values()):
                continue
            ident = f"{path.name}:{message.get('id') or event.get('uuid')}"
            messages[ident] = values
    if not messages:
        raise ValueError("no assistant usage found in the selected window")
    uncached = sum(m["input_tokens"] for m in messages.values())
    read = sum(m["cache_read_input_tokens"] for m in messages.values())
    write = sum(m["cache_creation_input_tokens"] for m in messages.values())
    counter = {
        "input_tokens": uncached + read + write,
        "cached_input_tokens": read,
        "cache_write_input_tokens": write,
        # 5-minute writes are priced differently from 1-hour writes.
        "cache_write_5m_input_tokens": sum(m["cache_write_5m"] for m in messages.values()),
        "output_tokens": sum(m["output_tokens"] for m in messages.values()),
    }
    validate(counter, "session")
    return counter


def validate(counter: dict[str, int], label: str) -> None:
    if any(counter[f] < 0 for f in FIELDS):
        raise ValueError(f"{label} counters must be non-negative")
    if counter["cached_input_tokens"] + counter["cache_write_input_tokens"] > counter["input_tokens"]:
        raise ValueError(f"{label} cached input exceeds total input")
    if counter["cache_write_5m_input_tokens"] > counter["cache_write_input_tokens"]:
        raise ValueError(f"{label} 5-minute cache writes exceed total cache writes")


def codex_phase(current: dict[str, int], baseline_values: list[int] | None) -> tuple[str, dict[str, int]]:
    if baseline_values is None:
        return "whole-session", current
    baseline: dict[str, int] = dict(zip(CODEX_FIELDS, baseline_values, strict=True))
    baseline["cache_write_input_tokens"] = 0
    baseline["cache_write_5m_input_tokens"] = 0
    validate(baseline, "baseline")
    delta = {f: current[f] - baseline[f] for f in FIELDS}
    if any(v < 0 for v in delta.values()):
        raise ValueError("session counters decreased relative to the baseline")
    validate(delta, "phase")
    return "delta", delta


def calculate_cost(usage: dict[str, int], args: argparse.Namespace) -> tuple[Decimal | None, Decimal | None]:
    rates = (args.uncached_input_rate, args.cached_input_rate, args.output_rate)
    if all(r is None for r in rates) and args.cache_write_rate is None and args.cache_write_5m_rate is None:
        return None, None
    if any(r is None for r in rates):
        raise ValueError("provide uncached input, cached input and output rates together")
    write_5m = usage["cache_write_5m_input_tokens"]
    write_other = usage["cache_write_input_tokens"] - write_5m
    if write_other and args.cache_write_rate is None:
        raise ValueError("1-hour cache writes are present; provide --cache-write-rate")
    if write_5m and args.cache_write_5m_rate is None:
        raise ValueError("5-minute cache writes are present; provide --cache-write-5m-rate")
    extra = (args.cache_write_rate or Decimal(0), args.cache_write_5m_rate or Decimal(0))
    if any(r < 0 for r in (*rates, *extra)):
        raise ValueError("rates must be non-negative")
    million = Decimal(1_000_000)
    uncached = usage["input_tokens"] - usage["cached_input_tokens"] - usage["cache_write_input_tokens"]
    exact = (
        Decimal(uncached) * args.uncached_input_rate
        + Decimal(usage["cached_input_tokens"]) * args.cached_input_rate
        + Decimal(write_other) * extra[0]
        + Decimal(write_5m) * extra[1]
        + Decimal(usage["output_tokens"]) * args.output_rate
    ) / million
    return exact, exact.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def main() -> int:
    args = parse_args()
    try:
        fmt = detect_format(read_events(args.session)) if args.format == "auto" else args.format
        if fmt == "codex":
            if args.since or args.until or args.include_subagents or args.cache_write_rate is not None or args.cache_write_5m_rate is not None:
                raise ValueError("--since, --until, --include-subagents and --cache-write-rate are Claude-only")
            boundary, usage = codex_phase(codex_counter(read_events(args.session)), args.baseline)
        else:
            if args.baseline:
                raise ValueError("--baseline is Codex-only; use --since/--until for Claude")
            paths = [args.session]
            if args.include_subagents:
                paths += sorted((args.session.parent / args.session.stem / "subagents").glob("*.jsonl"))
            usage = claude_counter(paths, args.since, args.until)
            boundary = "window" if (args.since or args.until) else "whole-session"
        exact_cost, rounded_cost = calculate_cost(usage, args)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    total = usage["input_tokens"] + usage["output_tokens"]
    result: dict[str, Any] = {
        "format": fmt,
        "boundary": boundary,
        **usage,
        "uncached_input_tokens": usage["input_tokens"] - usage["cached_input_tokens"] - usage["cache_write_input_tokens"],
        "total_tokens": total,
    }
    if fmt == "claude":
        result["subagents_included"] = args.include_subagents
    if exact_cost is not None and rounded_cost is not None:
        result["api_equivalent_exact"] = format(exact_cost, "f")
        result["api_equivalent_rounded"] = format(rounded_cost, ".2f")

    if args.as_json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    for key, value in result.items():
        print(f"{key}={value}")
    cells = f"{usage['input_tokens']:,} ({usage['cached_input_tokens']:,}) | {usage['output_tokens']:,} | {total:,}"
    if rounded_cost is not None:
        cells += f" | ${rounded_cost:.2f}"
    print(f"markdown_cells={cells}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
