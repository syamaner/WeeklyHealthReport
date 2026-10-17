"""Inspect AI tasks, solvers and scorers for the nutrition-label capture evaluation.

One Inspect `Sample` per case: the route input (pasted text, or an image path), the
target (the truth record as JSON) and metadata (corpus, split, coverage tags, sha256,
licence). Solvers differ per route; the scorer and metrics are the same for every
route and call the pure functions in `score.py` and `arithmetic.py`.

- Route A: `route_a_parser` runs the Swift parser through its CLI wrapper.
- Route B: `route_b_vision` runs the Vision CLI (`vision_v3.swift`), the geometry
  serialiser (`serialise_lines.py`) and the same Swift parser; development images only.
- Route C: `route_c_openrouter` posts to OpenRouter through `openrouter_client` (one retry loop); it makes no call
  unless explicitly enabled, the consent check passes and the spend guard allows it.
"""

from __future__ import annotations

import asyncio
import base64
import json
import sys
import time
from collections.abc import Callable
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import jsonschema
from inspect_ai import Task, task
from inspect_ai.dataset import MemoryDataset, Sample
from inspect_ai.model import ModelOutput
from inspect_ai.scorer import CORRECT, INCORRECT, Metric, SampleScore, Score, Target, metric, scorer
from inspect_ai.solver import Generate, Solver, TaskState, solver

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import cases as case_loading  # noqa: E402
import decline_gate  # noqa: E402
import openrouter_client  # noqa: E402
import openrouter_route  # noqa: E402
import route_c_mapping  # noqa: E402
import score as scoring  # noqa: E402
import serialise_lines  # noqa: E402
from budget import LedgerBudget, contract_limits  # noqa: E402
from openrouter_route import RouteCModel  # noqa: E402

DEVELOPMENT_TEXT = HERE / "synthetic" / "development-cases-v1.jsonl"
ROUTE_C_INSTRUCTION = HERE / "openrouter" / "label-image-extraction-instruction-v1.txt"
ROUTE_C_WIRE_SCHEMA = HERE / "openrouter" / "label-image-wire-schema-v1.json"


def to_sample(case: dict[str, Any]) -> Sample:
    source = case["input"]
    metadata = dict(case["metadata"])
    metadata["input_kind"] = source["kind"]
    if source["kind"] == "text":
        prompt = source["text"]
    else:
        metadata["image_path"] = source["path"]
        prompt = f"image:{metadata['sha256']}"
    return Sample(id=case["id"], input=prompt, target=json.dumps(case["truth"], ensure_ascii=False, sort_keys=True), metadata=metadata)


# --- Solvers -------------------------------------------------------------------------


async def _run_parser(binary: Path, case_id: str, text: str) -> dict[str, Any]:
    process = await asyncio.create_subprocess_exec(
        str(binary), stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    stdout, stderr = await process.communicate(json.dumps([{"id": case_id, "text": text}]).encode("utf-8"))
    if process.returncode != 0:
        raise RuntimeError(f"parser failed for {case_id}: {stderr.decode(errors='replace')}")
    (result,) = json.loads(stdout)
    return result


@solver
def route_a_parser(binary: str) -> Solver:
    """Route A: the shipped Swift parser on pasted text, through its CLI wrapper."""
    path = Path(binary)

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        if state.metadata.get("input_kind") != "text":
            raise ValueError("route A only takes pasted text")
        result = await _run_parser(path, str(state.sample_id), state.input_text)
        state.metadata["parser_version"] = result["parser_version"]
        state.output = ModelOutput.from_content(model="route-a-parser", content=json.dumps(result["candidate"], ensure_ascii=False))
        return state

    return solve


async def _run_json(binary: Path, payload: Any, what: str) -> Any:
    process = await asyncio.create_subprocess_exec(
        str(binary), stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    stdout, stderr = await process.communicate(json.dumps(payload).encode("utf-8"))
    if process.returncode != 0:
        raise RuntimeError(f"{what} failed: {stderr.decode(errors='replace')}")
    return json.loads(stdout)


def route_b_input_allowed(metadata: dict[str, Any]) -> None:
    """Route B runs on development images only in this phase; never on a sealed folder."""
    path = Path(str(metadata.get("image_path", "")))
    if metadata.get("split") != "development" or "sealed" in path.parts:
        raise case_loading.SealedSetError("route B may run on development images only")
    if metadata.get("corpus") == "owner" and metadata.get("consent_local_routes") is not True:
        raise PermissionError("the owner photo has no local_routes consent")


def route_b_structural_checks(candidate: dict[str, Any], report: dict[str, Any]) -> dict[str, Any]:
    """Route B's structural guards on top of the parser, for photos only.

    1. A value the serialiser could not bind to a row means a row label or cell was
       missed, so the table is declined, whatever the parser made of the text (the parser
       may attach a value-only line to the row above, a legitimate pasted shape).
    2. When a reference-intake column exists, every row with an amount should carry a
       reference-intake cell; a photo row without one may be a missed cell, so the table
       is never marked ready (it stays a partial candidate; nothing is removed).
    """
    unbound = int(report.get("unbound_values", 0))
    if candidate.get("declined"):
        return candidate
    if unbound > 0:
        return {
            **candidate,
            "declined": True,
            "decline_reasons": ["values_without_row"],
            "ready_for_confirmation": False,
            "would_mark_ready": False,
            "automatic_save": False,
            "serving_size": "unknown",
            "servings_per_pack": "unknown",
            "headers": [],
            "cells": [],
            "warnings": [*candidate.get("warnings", []), f"serialiser_unbound_values: {unbound}"],
        }
    cells = candidate.get("cells") or []
    if any(h.get("basis") == "reference_intake" for h in candidate.get("headers") or []):
        amount_rows = {c["row_id"] for c in cells if c.get("basis") != "reference_intake"}
        reference_rows = {c["row_id"] for c in cells if c.get("basis") == "reference_intake"}
        missing = sorted(amount_rows - reference_rows)
        if missing:
            return {
                **candidate,
                "would_mark_ready": False,
                "warnings": [*candidate.get("warnings", []), "rows_without_reference_intake_cell: " + ", ".join(missing)],
            }
    return candidate


@solver
def route_b_vision(vision_binary: str | None = None, parser_binary: str | None = None) -> Solver:
    """Route B: Apple Vision (zh-Hant + en) through `vision_v3`, the serialiser, then the same parser as A.

    No network. The recognised lines stay in the Inspect log outside the repository; the
    scored candidate carries the image hash as its `input_sha256`.
    """

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        if vision_binary is None or parser_binary is None:
            raise ValueError("route B needs the vision_v3 and NutritionLabelTextParse binaries")
        if state.metadata.get("input_kind") != "image":
            raise ValueError("route B only takes images")
        route_b_input_allowed(state.metadata)
        recognised = await _run_json(Path(vision_binary), [{"id": str(state.sample_id), "path": state.metadata["image_path"]}], "vision")
        (image,) = recognised["results"]
        if image.get("error"):
            raise RuntimeError(f"vision failed for {state.sample_id}: {image['error']}")
        if image["image_sha256"] != state.metadata["sha256"]:
            raise ValueError(f"{state.sample_id} bytes do not match the recorded hash")
        serialised = serialise_lines.serialise(image)
        (parsed,) = await _run_json(
            Path(parser_binary),
            [{"id": str(state.sample_id), "text": serialised["text"], "route": "B", "input_sha256": image["image_sha256"]}],
            "parser",
        )
        state.metadata.update(
            {
                "parser_version": parsed["parser_version"],
                "vision": {
                    k: recognised[k]
                    for k in (
                        "adapter_version",
                        "request_revision",
                        "recognition_languages",
                        "uses_language_correction",
                        "operating_system",
                    )
                },
                "serialiser_version": serialised["serialiser_version"],
                "serialiser_report": serialised["report"],
                "serialised_text": serialised["text"],
            }
        )
        candidate = route_b_structural_checks(parsed["candidate"], serialised["report"])
        state.output = ModelOutput.from_content(model="route-b-vision", content=json.dumps(candidate, ensure_ascii=False))
        return state

    return solve


ROUTE_C_RUN_ORDER = ("luna", "grok", "sol", "gemini", "opus")  # Qwen 3.5 is no longer a route C reserve (decision A)

# The real POST is injected by the runner (with the key); tests inject a fake. Route C never calls
# Inspect's `generate`, so there is one retry loop (openrouter_client) and every attempt is ledgered.
RouteCPoster = Callable[[dict[str, Any], float], tuple[int, dict[str, Any] | None, dict[str, str], float]]
GenerationLookup = Callable[[str], tuple[str, Any]]
# Set by `run_route_c.py` (and tests) through `configure_route_c_transport`, so the key-bearing
# callables never become Inspect task arguments (which Inspect writes into the log).
ROUTE_C_TRANSPORT: dict[str, Any] = {}


def configure_route_c_transport(post: RouteCPoster | None, lookup: GenerationLookup | None) -> None:
    ROUTE_C_TRANSPORT.clear()
    if post is not None:
        ROUTE_C_TRANSPORT.update({"post": post, "lookup": lookup})


@solver
def route_c_openrouter(
    budget: LedgerBudget,
    enabled: bool = False,
    target: RouteCModel | None = None,
    post: RouteCPoster | None = None,
    lookup: GenerationLookup | None = None,
    policy: openrouter_client.RetryPolicy | None = None,
    sleep: Callable[[float], None] | None = None,
) -> Solver:
    """Route C: one OpenRouter request per image (with bounded retries) and strict structured output.

    The request is rebuilt from the instruction and the image only, so route C never sees
    truth or drafts. The owner photo needs `send_to_openrouter` consent. Each attempt passes
    the persistent spend ledger before it is sent and is recorded after, with its reported
    `usage.cost`, or as unknown (a retryable error with no generation as
    `retryable_error_unknown_cost`, reconciled through the generation lookup where an id
    exists). The final answer must match the requested model and provider, finish with
    `stop` and validate against the wire schema; otherwise the case is failed, never retried.
    """
    if not isinstance(budget, LedgerBudget):
        raise TypeError("route C needs the persistent LedgerBudget; refusing an in-memory or missing budget")
    guard = budget

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        if not enabled:
            raise RuntimeError("route C is disabled; no provider call is made")
        poster = post if post is not None else ROUTE_C_TRANSPORT.get("post")
        finder = lookup if post is not None else ROUTE_C_TRANSPORT.get("lookup")
        if target is None or poster is None:
            raise ValueError("route C needs a pinned model and endpoint and a poster")
        if state.metadata.get("corpus") == "owner" and state.metadata.get("consent_send_to_openrouter") is not True:
            raise PermissionError("the owner photo has no send_to_openrouter consent")
        instruction = ROUTE_C_INSTRUCTION.read_text(encoding="utf-8")
        wire = json.loads(ROUTE_C_WIRE_SCHEMA.read_text(encoding="utf-8"))
        body = openrouter_route.route_c_request_body(target, _data_uri(Path(state.metadata["image_path"])), instruction, wire)
        purpose = "route_c_sealed" if guard.sealed_run else "route_c_development"
        attempt_costs: list[str | None] = []
        label = target.label

        def before(_: Any) -> None:
            guard.before_call(label)

        def record(attempt: openrouter_client.Attempt) -> None:
            cost = openrouter_route.reported_cost(attempt.body)
            generation = attempt.body.get("id") if isinstance(attempt.body, dict) else None
            kind = openrouter_client.attempt_kind(attempt.status, attempt.body, attempt.retryable)
            if cost is None and attempt.retryable and isinstance(generation, str) and finder is not None:
                found, value = finder(generation)  # reconcile a retried attempt that did produce a generation
                if found == "found" and value is not None:
                    cost = Decimal(str(value))
            attempt_costs.append(None if cost is None else str(cost))
            guard.record_call(
                label,
                cost,
                purpose=purpose,
                case_id=str(state.sample_id),
                at=datetime.now(UTC).isoformat(timespec="seconds"),
                returned_model=attempt.body.get("model") if isinstance(attempt.body, dict) else None,
                kind=kind,
                attempt=attempt.number,
                generation_id=generation if isinstance(generation, str) else None,
            )

        def ledgered_post(payload: dict[str, Any], timeout: float) -> tuple[int, dict[str, Any] | None, dict[str, str], float]:
            before(None)  # the open call is on disk before the request is sent
            return poster(payload, timeout)

        started = time.monotonic()
        result = await asyncio.to_thread(
            openrouter_client.call_with_retry,
            body,
            ledgered_post,
            policy=policy or openrouter_client.DEFAULT_POLICY,
            sleep=sleep or time.sleep,
            on_attempt=record,
        )
        latency = time.monotonic() - started
        raw = result.body
        raw_usage = raw.get("usage") if isinstance(raw, dict) else None
        usage: dict[str, Any] = raw_usage if isinstance(raw_usage, dict) else {}
        known = [Decimal(c) for c in attempt_costs if c is not None]
        details = usage.get("completion_tokens_details")
        # A call's cost is the sum of its attempts' reported costs; it is unknown when the final
        # attempt (the one that answered) reported none. Retryable attempts without a cost are counted.
        final_known = bool(attempt_costs) and attempt_costs[-1] is not None
        state.metadata["route_c"] = {
            "model_label": target.label,
            "reasoning": target.reasoning,
            "cost_usd": str(sum(known, Decimal(0))) if final_known else None,
            "unknown_cost_attempts": sum(1 for c in attempt_costs if c is None),
            "attempt_costs_usd": attempt_costs,
            "attempts": len(result.attempts),
            "retries": result.retries,
            "retry_causes": [a.cause for a in result.attempts if a.retryable],
            "latency_seconds": round(latency, 3),
            "returned_model": raw.get("model") if isinstance(raw, dict) else None,
            "returned_provider": raw.get("provider") if isinstance(raw, dict) else None,
            "prompt_tokens": usage.get("prompt_tokens"),
            "completion_tokens": usage.get("completion_tokens"),
            "reasoning_tokens": details.get("reasoning_tokens") if isinstance(details, dict) else None,
        }
        problems: list[str] = []
        if result.exhausted or result.status != 200 or result.cause:
            problems = [f"request failed: {result.cause or f'HTTP {result.status}'}"]
        else:
            problems = openrouter_route.route_mismatches(raw, target)
        candidate = None
        if not problems:
            try:
                assert isinstance(raw, dict)
                content = raw["choices"][0]["message"]["content"]
                state.metadata["route_c_answer"] = content  # kept in the private Inspect log only
                parsed = json.loads(content)
                # Strict output is requested, but the answer is checked here too: a
                # schema-invalid answer is failed (plan section 6), never mapped.
                jsonschema.validate(parsed, wire)
                candidate = route_c_mapping.map_wire(parsed, str(state.metadata["sha256"]))
            except jsonschema.ValidationError as failure:
                problems = [f"schema-invalid output: {failure.message[:160]}"]
            except (json.JSONDecodeError, KeyError, IndexError, TypeError, AttributeError, AssertionError) as failure:
                problems = [f"content is not schema JSON: {type(failure).__name__}"]
        if problems or candidate is None:
            state.metadata["route_c_failed"] = problems
            state.output = ModelOutput.from_content(model=target.model, content="")
        else:
            state.output = ModelOutput.from_content(model=target.model, content=json.dumps(candidate, ensure_ascii=False))
        return state

    return solve


def _data_uri(path: Path) -> str:
    mime = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}.get(path.suffix.lower(), "image/jpeg")
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


@solver
def decline_gate_solver() -> Solver:
    """The route-independent decline gate (`decline_gate.py`), run after every route's extraction.

    It reads the candidate and the label format the case declares, and may only decline or
    block ready; it never changes a value. The ungated candidate is kept in the private log
    when the gate changed it, so before and after stay comparable.
    """

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        completion = state.output.completion if state.output else ""
        if not completion:
            return state
        try:
            candidate = json.loads(completion)
        except json.JSONDecodeError:
            return state
        label_format = decline_gate.format_for_case(state.metadata)
        gated, report = decline_gate.apply_gate(candidate, label_format)
        state.metadata["decline_gate"] = report
        if gated is not candidate:
            state.metadata["pre_gate_candidate"] = candidate
            state.output = ModelOutput.from_content(model=state.output.model, content=json.dumps(gated, ensure_ascii=False))
        return state

    return solve


# --- Scorer and metrics ------------------------------------------------------------


def _sum(scores: list[SampleScore], key: str) -> int:
    return sum(int((s.score.metadata or {}).get(key, 0)) for s in scores)


def _ratio(scores: list[SampleScore], numerator: str, denominator: str) -> float:
    total = _sum(scores, denominator)
    return _sum(scores, numerator) / total if total else -1.0  # -1 means no denominator, never a pass


@metric
def strict_cells() -> Metric:
    def compute(scores: list[SampleScore]) -> float:
        return _ratio(scores, "cells_exact", "product_cells")

    return compute


@metric
def binding() -> Metric:
    def compute(scores: list[SampleScore]) -> float:
        return _ratio(scores, "cells_bound", "all_cells")

    return compute


@metric
def unit_and_basis() -> Metric:
    def compute(scores: list[SampleScore]) -> float:
        return _ratio(scores, "cells_unit_basis", "product_cells")

    return compute


@metric
def full_table() -> Metric:
    def compute(scores: list[SampleScore]) -> float:
        return _ratio(scores, "tables_exact", "usable_tables")

    return compute


@metric
def serving_conversions() -> Metric:
    def compute(scores: list[SampleScore]) -> float:
        return _ratio(scores, "conversions_exact", "conversions")

    return compute


@metric
def servings_per_pack() -> Metric:
    def compute(scores: list[SampleScore]) -> float:
        return _ratio(scores, "servings_per_pack_exact", "servings_per_pack")

    return compute


@metric
def bounds() -> Metric:
    def compute(scores: list[SampleScore]) -> float:
        return _ratio(scores, "bounds_exact", "bounded_cells")

    return compute


@metric
def correct_decline() -> Metric:
    def compute(scores: list[SampleScore]) -> float:
        return _ratio(scores, "declines_correct", "declines_required")

    return compute


@metric
def false_ready() -> Metric:
    """Silent false-save count: tables the route would mark ready that are not exactly right."""

    def compute(scores: list[SampleScore]) -> float:
        return float(_sum(scores, "false_ready") + _sum(scores, "automatic_persistence"))

    return compute


@metric
def energy_check_pass() -> Metric:
    """Share of checkable candidates whose energy matches (informs, never authorises)."""

    def compute(scores: list[SampleScore]) -> float:
        statuses = [(s.score.metadata or {}).get("energy_check") for s in scores]
        checkable = [status for status in statuses if status in ("pass", "fail")]
        return sum(status == "pass" for status in checkable) / len(checkable) if checkable else -1.0

    return compute


@scorer(
    metrics=[
        strict_cells(),
        binding(),
        unit_and_basis(),
        full_table(),
        serving_conversions(),
        servings_per_pack(),
        bounds(),
        correct_decline(),
        false_ready(),
        energy_check_pass(),
    ]
)
def label_capture_scorer():
    """The same scorer for every route; counts live in the score metadata."""

    async def score(state: TaskState, target: Target) -> Score:
        truth = json.loads(target.text)
        try:
            candidate = json.loads(state.output.completion) if state.output and state.output.completion else None
        except json.JSONDecodeError:
            candidate = None
        result = scoring.score_case(candidate, truth)
        good = result["declines_correct"] if truth.get("requires_decline") else result["tables_exact"]
        return Score(
            value=CORRECT if good else INCORRECT, answer=None, metadata=result, explanation="; ".join(result["failure_reasons"]) or None
        )

    return score


# --- Tasks ---------------------------------------------------------------------------


@task
def label_capture_development_text(parser_binary: str, dataset: str = str(DEVELOPMENT_TEXT), epochs: int = 1) -> Task:
    """Route A on the development pasted-text cases (synthetic plus the typed muesli text)."""
    samples = [to_sample(case) for case in case_loading.load_development_text(Path(dataset))]
    return Task(
        dataset=MemoryDataset(samples, name="development-text-v1"),
        solver=[route_a_parser(parser_binary), decline_gate_solver()],
        scorer=label_capture_scorer(),
        epochs=epochs,
        name="label_capture_route_a_development",
    )


@task
def label_capture_development_photos(cases_file: str, vision_binary: str, parser_binary: str) -> Task:
    """Route B on development photos; `cases_file` is a JSON list built by `run_route_b.py`."""
    loaded = json.loads(Path(cases_file).read_text(encoding="utf-8"))
    for case in loaded:
        if case["metadata"].get("split") != "development":
            raise case_loading.SealedSetError(f"{case['id']} is not a development case")
    return Task(
        dataset=MemoryDataset([to_sample(c) for c in loaded], name="development-photos-v1"),
        solver=[route_b_vision(vision_binary, parser_binary), decline_gate_solver()],
        scorer=label_capture_scorer(),
        name="label_capture_route_b_development",
    )


@task
def label_capture_route_c_development(
    cases_file: str,
    ledger: str,
    model: str,
    endpoint: str,
    provider_name: str,
    label: str,
    enabled: bool = False,
    reasoning: str = "off",
) -> Task:
    """Route C on development photos; run only through `run_route_c.py` (log directory, key and retry rules)."""
    loaded = json.loads(Path(cases_file).read_text(encoding="utf-8"))
    for case in loaded:
        if case["metadata"].get("split") != "development" or "sealed" in Path(str(case["input"].get("path", ""))).parts:
            raise case_loading.SealedSetError(f"{case['id']} is not a development case")
    target = RouteCModel(label=label, model=model, endpoint=endpoint, provider_name=provider_name, reasoning=reasoning)
    contract = json.loads((HERE / "frozen-contract-v1.json").read_text(encoding="utf-8"))
    budget = LedgerBudget(Path(ledger), limits=contract_limits(contract))
    return Task(
        dataset=MemoryDataset([to_sample(c) for c in loaded], name="development-photos-route-c-v1"),
        solver=[route_c_openrouter(budget, enabled=enabled, target=target), decline_gate_solver()],
        scorer=label_capture_scorer(),
        name="label_capture_route_c_development",
    )


@task
def label_capture_untouched_photos(
    route: str,
    manifest: str,
    image_root: str,
    truth: str,
    unseal: bool = False,
    manifest_sha256: str | None = None,
    ledger: str | None = None,
) -> Task:
    """The sealed 40 Taiwan photos; refuses without an explicit, hash-bound unseal."""
    loaded = case_loading.load_untouched_photos(
        Path(manifest), Path(image_root), unseal=unseal, manifest_sha256=manifest_sha256, truth_path=Path(truth)
    )
    if route == "C":
        if ledger is None:
            raise ValueError("route C needs the persistent spend ledger")
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text(encoding="utf-8"))
        chosen = route_c_openrouter(LedgerBudget(Path(ledger), sealed_run=True, limits=contract_limits(contract)), enabled=False)
    else:
        chosen = route_b_vision()
    return Task(
        dataset=MemoryDataset([to_sample(c) for c in loaded], name="untouched-photos-v1"),
        solver=[chosen, decline_gate_solver()],
        scorer=label_capture_scorer(),
        name=f"label_capture_route_{route.lower()}_untouched",
    )
