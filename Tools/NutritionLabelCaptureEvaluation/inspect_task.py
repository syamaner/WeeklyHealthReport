"""Inspect AI tasks, solvers and scorers for the nutrition-label capture evaluation.

One Inspect `Sample` per case: the route input (pasted text, or an image path), the
target (the truth record as JSON) and metadata (corpus, split, coverage tags, sha256,
licence). Solvers differ per route; the scorer and metrics are the same for every
route and call the pure functions in `score.py` and `arithmetic.py`.

- Route A: `route_a_parser` runs the Swift parser through its CLI wrapper.
- Route B: `route_b_vision` is a reserved slot for the Vision CLI (later phase).
- Route C: `route_c_openrouter` is defined but disabled in phase 1; it makes no call
  unless explicitly enabled, the consent check passes and the spend guard allows it.
"""

from __future__ import annotations

import asyncio
import json
import sys
from decimal import Decimal
from pathlib import Path
from typing import Any

from inspect_ai import Task, task
from inspect_ai.dataset import MemoryDataset, Sample
from inspect_ai.model import ChatMessageUser, ContentImage, ContentText, ModelOutput, ResponseSchema
from inspect_ai.scorer import CORRECT, INCORRECT, Metric, SampleScore, Score, Target, metric, scorer
from inspect_ai.solver import Generate, Solver, TaskState, solver
from inspect_ai.util import JSONSchema

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import cases as case_loading  # noqa: E402
import score as scoring  # noqa: E402
from budget import RunBudget  # noqa: E402

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


@solver
def route_b_vision(binary: str | None = None) -> Solver:
    """Route B slot: Vision (zh-Hant + en) then the serialiser and the same parser (later phase)."""

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        raise NotImplementedError("route B is not implemented in phase 1")

    return solve


ROUTE_C_RUN_ORDER = ("luna", "grok", "sol", "gemini", "opus")


@solver
def route_c_openrouter(enabled: bool = False, budget: RunBudget | None = None, model_label: str = "") -> Solver:
    """Route C: one OpenRouter request per image with strict structured output.

    Disabled in phase 1. When enabled later: the owner photo needs `send_to_openrouter`
    consent, the spend guard runs before and after each call, there are no retries and
    no streaming, and the response is validated against the shared candidate schema.
    """
    guard = budget or RunBudget()

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        if not enabled:
            raise RuntimeError("route C is disabled in phase 1; no provider call is made")
        if state.metadata.get("corpus") == "owner" and state.metadata.get("consent_send_to_openrouter") is not True:
            raise PermissionError("the owner photo has no send_to_openrouter consent")
        instruction = ROUTE_C_INSTRUCTION.read_text(encoding="utf-8")
        state.messages = [ChatMessageUser(content=[ContentText(text=instruction), ContentImage(image=state.metadata["image_path"])])]
        guard.before_call(model_label)
        wire = json.loads(ROUTE_C_WIRE_SCHEMA.read_text(encoding="utf-8"))
        # One request, no tool loop, no retries, 4096 output tokens, 90 s timeout, strict schema.
        state = await generate(
            state,
            tool_calls="none",
            max_tokens=4096,
            timeout=90,
            max_retries=0,
            response_schema=ResponseSchema(name="label_image_extraction_v1", json_schema=JSONSchema.model_validate(wire), strict=True),
        )
        cost = state.output.usage.total_cost if state.output and state.output.usage else None
        guard.record(model_label, Decimal(str(cost)) if cost is not None else None)
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
        solver=route_a_parser(parser_binary),
        scorer=label_capture_scorer(),
        epochs=epochs,
        name="label_capture_route_a_development",
    )


@task
def label_capture_untouched_photos(
    route: str, manifest: str, image_root: str, truth: str, unseal: bool = False, manifest_sha256: str | None = None
) -> Task:
    """The sealed 40 Taiwan photos; refuses without an explicit, hash-bound unseal."""
    loaded = case_loading.load_untouched_photos(
        Path(manifest), Path(image_root), unseal=unseal, manifest_sha256=manifest_sha256, truth_path=Path(truth)
    )
    solvers = {"B": route_b_vision(), "C": route_c_openrouter(enabled=False)}
    return Task(
        dataset=MemoryDataset([to_sample(c) for c in loaded], name="untouched-photos-v1"),
        solver=solvers[route],
        scorer=label_capture_scorer(),
        name=f"label_capture_route_{route.lower()}_untouched",
    )
