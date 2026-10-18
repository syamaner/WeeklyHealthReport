#!/usr/bin/env python3
"""Route A once on the untouched pasted-text cases (phase 5, #255; owner decision of 18 October 2026).

The untouched pasted-text set is the FDA dataset 188 rows and the closed-template candidates
whose hash assigns them to `untouched` (contract `corpus.fda188`; `synthetic/render.py`). They
were counted but never rendered while the generator could change. This script renders them
with the frozen generator, with no change to it:

- `render_rows(..., split)` applies exactly the per-row logic of `build_cases.fda_cases` and
  `build_cases.template_cases` (layout, shape and decline-variant choices are hash-seeded by the
  same `render.choose` calls) to the rows of the requested split. With `split="development"`
  it reproduces the committed development cases byte for byte, which the tests check, so the
  untouched cases come from the same frozen code path;
- the FDA CSV must match the SHA-256 in `fixtures/fda-188-source-v1.json`.

Then it runs the shipped Swift parser (the frozen `NutritionLabelTextParse` binary, hash in
`untouched_run.route_b.parser_binary_sha256`) on each case once, applies decline gate v2 with
the Taiwan format, and scores with the frozen scorer. It refuses a non-frozen contract, a
second start (the same run register as `run_untouched.py`) and paths inside the repository.
No network call. The rendered cases and the per-case outputs stay outside the repository.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import arithmetic  # noqa: E402
import build_cases  # noqa: E402
import decline_gate  # noqa: E402
import run_untouched  # noqa: E402
import score as scoring  # noqa: E402
from synthetic import render  # noqa: E402

FDA_SOURCE = HERE / "fixtures" / "fda-188-source-v1.json"


def _case(case_id: str, text: str, truth: dict[str, Any], metadata: dict[str, Any], split: str) -> dict[str, Any]:
    case = build_cases.text_case(case_id, text, truth, metadata)
    case["metadata"]["split"] = split
    return case


def fda_rows(csv_path: Path, split: str) -> list[dict[str, Any]]:
    """`build_cases.fda_cases` for any split, unchanged otherwise."""
    eligible = []
    with csv_path.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            if not row.get("每份熱量", "").strip():
                continue
            truth, _ = render.fda_truth(row)
            if truth is None:
                continue
            if arithmetic.check_table(truth)["status"] == arithmetic.FAIL:
                continue
            eligible.append((render.fda_order_key(row), truth))
    eligible.sort(key=lambda item: item[0])
    cases = []
    for order_key, truth in eligible[: build_cases.FDA_CANDIDATE_LIMIT]:
        if render.fda_split(order_key) != split:
            continue
        layout = render.choose(("two_column", "single_column_serving", "single_column_100"), order_key, "layout")
        variant = render.select_columns(truth, layout)
        if variant is None:
            layout = "single_column_serving"
            variant = render.select_columns(truth, layout)
        if variant is None:
            raise ValueError(f"{truth['case_id']} has no renderable column")
        shape = render.choose(render.CHINESE_SHAPES, order_key, "shape")
        text, rendered = render.render_chinese(variant, shape)
        tags = {"zh_hant", "synthetic", "serving_line", "servings_per_pack", "sodium", "nested_rows", f"shape_{shape}"}
        tags.add("two_column_serving_and_100" if len(variant["headers"]) > 1 else "single_column")
        if any(h["basis"] == "per_100ml" for h in variant["headers"]):
            tags.add("per_100ml")
        base = {"corpus": "fda188", "language": "zh-Hant", "licence": build_cases.FDA_LICENCE, "fda_order_key": order_key, "layout": layout}
        cases.append(_case(f"{truth['case_id']}:{layout}:{shape}", text, rendered, {**base, "coverage_tags": sorted(tags)}, split))
        decline = render.choose(("none",) * 8 + ("simplified", "no_energy_unit"), order_key, "decline")
        if decline != "none":
            text, rendered = render.render_chinese(
                variant, shape, simplified=decline == "simplified", strip_energy_unit=decline == "no_energy_unit"
            )
            rendered.update(
                {"requires_decline": True, "decline_reason": "unsupported_language" if decline == "simplified" else "energy_without_unit"}
            )
            cases.append(
                _case(
                    f"{truth['case_id']}:{layout}:{shape}:{decline}",
                    text,
                    rendered,
                    {**base, "coverage_tags": sorted(tags | {"decline_expected"})},
                    split,
                )
            )
    return cases


def template_rows(split: str) -> list[dict[str, Any]]:
    """`build_cases.template_cases` for any split, unchanged otherwise."""
    cases = []
    for variant in render.TEMPLATE_VARIANTS:
        for index in range(render.TEMPLATE_CANDIDATES_PER_VARIANT):
            truth = render.template_truth(variant, index)
            if render.template_split(truth["template_order_key"]) != split:
                continue
            shape = render.choose(render.CHINESE_SHAPES, truth["template_order_key"], "shape")
            text, rendered = render.render_chinese(truth, shape)
            tags = {"zh_hant", "synthetic", "serving_line", "servings_per_pack", "sodium", "nested_rows", f"shape_{shape}"}
            tags |= build_cases.TEMPLATE_TAGS[variant]
            metadata = {
                "corpus": "zh_template",
                "language": "zh-Hant",
                "template_variant": variant,
                "licence": "Synthetic values from a seeded closed template; no source data",
                "coverage_tags": sorted(tags),
            }
            cases.append(_case(f"{truth['case_id']}:{shape}", text, rendered, metadata, split))
    return cases


def render_rows(csv_path: Path, split: str) -> list[dict[str, Any]]:
    return fda_rows(csv_path, split) + template_rows(split)


def run_parser(binary: Path, cases: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    payload = json.dumps([{"id": c["id"], "text": c["input"]["text"]} for c in cases]).encode("utf-8")
    done = subprocess.run([str(binary)], input=payload, capture_output=True, check=True)
    return {item["id"]: item for item in json.loads(done.stdout)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fda-csv", type=Path, required=True)
    parser.add_argument("--parser-binary", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True, help="outside the repository; must be empty")
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--register", type=Path, default=Path.home() / "WHR-label-eval-private" / "untouched-run-register-v1.json")
    args = parser.parse_args(argv)

    contract = run_untouched.frozen_contract()
    run_untouched.require_pinned_register(contract, args.register)
    for path in (args.out_dir, args.summary, args.register):
        if not run_untouched.run_route_c.outside_repository(path):
            raise SystemExit(f"refusing a path inside the repository: {path}")
    if args.out_dir.exists() and any(args.out_dir.iterdir()):
        raise SystemExit("--out-dir must be empty")
    expected_csv = json.loads(FDA_SOURCE.read_text(encoding="utf-8"))["extracted"]["sha256"]
    if build_cases.sha256_file(args.fda_csv) != expected_csv:
        raise SystemExit("the FDA CSV does not match fixtures/fda-188-source-v1.json")
    if hashlib.sha256(args.parser_binary.read_bytes()).hexdigest() != contract["untouched_run"]["route_b"]["parser_binary_sha256"]:
        raise SystemExit("the parser binary does not match the frozen hash")

    cases = render_rows(args.fda_csv, "untouched")
    args.out_dir.mkdir(parents=True, exist_ok=True)
    dataset = args.out_dir / "untouched-text-cases-v1.jsonl"
    dataset.write_text("\n".join(json.dumps(c, ensure_ascii=False, sort_keys=True) for c in cases) + "\n", encoding="utf-8")
    run_untouched.register_start(args.register, "A", "untouched-text", args.out_dir)
    try:
        outputs = run_parser(args.parser_binary, cases)
    except BaseException as error:
        run_untouched.register_finish(args.register, "A", "untouched-text", f"failed: {type(error).__name__}")
        raise
    thresholds = scoring.load_thresholds()
    results, per_case, by_corpus = [], [], {}
    for case in cases:
        candidate = outputs[case["id"]]["candidate"]
        gated, report = decline_gate.apply_gate(candidate, decline_gate.format_for_case(case["metadata"]))
        result = scoring.score_case(gated, case["truth"])
        results.append(result)
        by_corpus.setdefault(case["metadata"]["corpus"], []).append(result)
        per_case.append(
            {
                "id": case["id"],
                "corpus": case["metadata"]["corpus"],
                "requires_decline": bool(case["truth"].get("requires_decline")),
                "declined": bool(gated and gated.get("declined")),
                "gate_declines": report["declines"],
                "table_exact": result["tables_exact"],
                "false_ready": result["false_ready"],
                "would_mark_ready": result["would_mark_ready_after_arithmetic"],
            }
        )
    (args.out_dir / "outputs.json").write_text(json.dumps(outputs, ensure_ascii=False) + "\n", encoding="utf-8")
    truths = [c["truth"] for c in cases if not c["truth"].get("requires_decline")]
    mutation = arithmetic.mutation_detection(truths)["overall"]
    summary = {
        "route": "A",
        "split": "untouched",
        "generator_version": render.GENERATOR_VERSION,
        "seed": render.SEED,
        "dataset_sha256": build_cases.sha256_file(dataset),
        "parser_version": next(iter(outputs.values()))["parser_version"] if outputs else None,
        "gate_version": decline_gate.GATE_VERSION,
        "cases": len(cases),
        "required_declines": sum(1 for c in cases if c["truth"].get("requires_decline")),
        "by_corpus_cases": {name: len(group) for name, group in by_corpus.items()},
        "overall": scoring.aggregate(results, thresholds),
        "by_corpus": {name: scoring.aggregate(group, thresholds) for name, group in sorted(by_corpus.items())},
        "arithmetic_mutation_detection": {"detected": mutation["detected"], "applicable": mutation["applicable"]},
        "per_case": per_case,
    }
    args.summary.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    run_untouched.register_finish(args.register, "A", "untouched-text", "complete")
    print(json.dumps({k: summary[k] for k in ("cases", "required_declines", "by_corpus_cases", "dataset_sha256")}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
