#!/usr/bin/env python3
"""Build the route A DEVELOPMENT pasted-text dataset (synthetic, deterministic).

Sources, all development only:
- English: reviewed v1 ground truth (`Tools/FoodOCREvaluation/fixtures/ground-truth-v1.json`,
  100 panels, all exposed) and, when available locally, the frozen 40-panel v2 public
  development review (22 usable tables). The 40 sealed v2 identities are never read.
- Traditional Chinese: the muesli label typed by hand (`synthetic/muesli-zh-typed-v1.txt`)
  and Taiwan FDA dataset 188 rows that pass the internal-consistency check, ordered and
  split by hash. Only rows whose hash assigns them to development are rendered; untouched
  rows are counted, never rendered, until the generator is frozen.

Writes one JSON object per line: id, input, truth, metadata.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import arithmetic  # noqa: E402
from synthetic import render  # noqa: E402

FDA_LICENCE = "Open Government Data License, version 1.0 (Taiwan); attribution: Taiwan Food and Drug Administration, dataset 188"
OFF_LICENCE = "Open Food Facts; transcription of CC BY-SA 3.0 images"
FDA_CANDIDATE_LIMIT = 120


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_case(case_id: str, text: str, truth: dict[str, Any], metadata: dict[str, Any]) -> dict[str, Any]:
    truth = {k: v for k, v in truth.items() if not k.startswith("_")}
    truth["case_id"] = case_id
    truth["input_sha256"] = render.digest(text)
    return {
        "id": case_id,
        "input": {"kind": "text", "text": text},
        "truth": truth,
        "metadata": {
            "split": "development",
            "synthetic": True,
            "generator_version": render.GENERATOR_VERSION,
            "seed": render.SEED,
            "sha256": truth["input_sha256"],
            **metadata,
        },
    }


def english_cases(panels: list[dict[str, Any]], corpus: str, exclusions: list[dict[str, str]]) -> list[dict[str, Any]]:
    cases = []
    for panel in panels:
        truth, reason = render.english_truth(panel["panel_id"], panel["ground_truth"])
        if truth is None:
            exclusions.append({"source": panel["panel_id"], "reason": reason or "unrecorded reason"})
            continue
        shape = render.choose(render.ENGLISH_SHAPES, panel["panel_id"])
        text = render.render_english(truth, shape)
        families = panel.get("families") or panel["ground_truth"].get("families") or []
        tags = sorted({"en_uk", "synthetic", f"shape_{shape}"} | set(families))
        cases.append(
            text_case(
                f"{corpus}:{panel['panel_id']}:{shape}",
                text,
                truth,
                {
                    "corpus": corpus,
                    "language": "en",
                    "coverage_tags": tags,
                    "licence": OFF_LICENCE,
                    "source_image_sha256": panel.get("image_sha256"),
                },
            )
        )
    return cases


def fda_cases(csv_path: Path, exclusions: list[dict[str, str]]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    eligible = []
    reasons: dict[str, int] = {}
    with csv_path.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            if not row.get("每份熱量", "").strip():
                continue
            truth, reason = render.fda_truth(row)
            if truth is None:
                key = reason or "unrecorded reason"
                reasons[key] = reasons.get(key, 0) + 1
                continue
            check = arithmetic.check_table(truth)
            if check["status"] == arithmetic.FAIL:
                reasons["fails the internal-consistency check"] = reasons.get("fails the internal-consistency check", 0) + 1
                continue
            eligible.append((render.fda_order_key(row), truth))
    eligible.sort(key=lambda item: item[0])
    chosen = eligible[:FDA_CANDIDATE_LIMIT]
    split_counts = {"development": 0, "untouched": 0}
    cases = []
    for order_key, truth in chosen:
        split = render.fda_split(order_key)
        split_counts[split] += 1
        if split != "development":
            continue  # untouched rows are rendered only after the generator is frozen
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
        base = {"corpus": "fda188", "language": "zh-Hant", "licence": FDA_LICENCE, "fda_order_key": order_key, "layout": layout}
        cases.append(text_case(f"{truth['case_id']}:{layout}:{shape}", text, rendered, {**base, "coverage_tags": sorted(tags)}))
        decline = render.choose(("none",) * 8 + ("simplified", "no_energy_unit"), order_key, "decline")
        if decline != "none":
            text, rendered = render.render_chinese(
                variant, shape, simplified=decline == "simplified", strip_energy_unit=decline == "no_energy_unit"
            )
            rendered.update(
                {"requires_decline": True, "decline_reason": "unsupported_language" if decline == "simplified" else "energy_without_unit"}
            )
            cases.append(
                text_case(
                    f"{truth['case_id']}:{layout}:{shape}:{decline}",
                    text,
                    rendered,
                    {**base, "coverage_tags": sorted(tags | {"decline_expected"})},
                )
            )
    summary = {"eligible_rows": len(eligible), "candidates_taken": len(chosen), "split": split_counts, "ineligible_reasons": reasons}
    return cases, summary


TEMPLATE_TAGS = {
    "bound": {"bound", "two_column_serving_and_100"},
    "reference_intake_column": {"reference_intake_column", "single_column"},
    "per_100ml": {"per_100ml", "two_column_serving_and_100"},
    "single_column": {"single_column"},
    "servings_2_5": {"two_column_serving_and_100"},
}
# Coverage tags from plan section 3.1. Photo-only tags cannot apply to pasted text.
PLAN_TAGS = [
    "zh_hant",
    "en_uk",
    "two_column_serving_and_100",
    "single_column",
    "reference_intake_column",
    "per_100ml",
    "bound",
    "salt",
    "sodium",
    "serving_line",
    "servings_per_pack",
    "nested_rows",
    "column_offset",
    "glossy",
    "curved_or_crumpled",
    "small_font",
    "decline_expected",
    "synthetic",
]
PHOTO_ONLY_TAGS = {"column_offset", "glossy", "curved_or_crumpled", "small_font"}


def template_cases() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Development cases from the closed Taiwan template; untouched candidates are counted, not rendered."""
    cases = []
    split_counts = {"development": 0, "untouched": 0}
    for variant in render.TEMPLATE_VARIANTS:
        for index in range(render.TEMPLATE_CANDIDATES_PER_VARIANT):
            truth = render.template_truth(variant, index)
            split = render.template_split(truth["template_order_key"])
            split_counts[split] += 1
            if split != "development":
                continue
            shape = render.choose(render.CHINESE_SHAPES, truth["template_order_key"], "shape")
            text, rendered = render.render_chinese(truth, shape)
            tags = {"zh_hant", "synthetic", "serving_line", "servings_per_pack", "sodium", "nested_rows", f"shape_{shape}"}
            tags |= TEMPLATE_TAGS[variant]
            cases.append(
                text_case(
                    f"{truth['case_id']}:{shape}",
                    text,
                    rendered,
                    {
                        "corpus": "zh_template",
                        "language": "zh-Hant",
                        "template_variant": variant,
                        "licence": "Synthetic values from a seeded closed template; no source data",
                        "coverage_tags": sorted(tags),
                    },
                )
            )
    return cases, {
        "variants": list(render.TEMPLATE_VARIANTS),
        "candidates_per_variant": render.TEMPLATE_CANDIDATES_PER_VARIANT,
        "split": split_counts,
    }


def coverage(cases: list[dict[str, Any]]) -> dict[str, Any]:
    chinese = [c for c in cases if c["metadata"]["language"] == "zh-Hant"]
    present = {tag for c in chinese for tag in c["metadata"]["coverage_tags"]}
    return {
        "chinese_cases": len(chinese),
        "covered": sorted(tag for tag in PLAN_TAGS if tag in present),
        "not_covered": sorted(tag for tag in PLAN_TAGS if tag not in present),
        "not_applicable_to_pasted_text": sorted(PHOTO_ONLY_TAGS),
        "counts": {tag: sum(tag in c["metadata"]["coverage_tags"] for c in chinese) for tag in PLAN_TAGS if tag in present},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--v1-ground-truth", type=Path, required=True)
    parser.add_argument("--v2-development-review", type=Path, help="frozen 40-panel v2 public development review (local, ignored)")
    parser.add_argument("--fda-csv", type=Path, required=True)
    parser.add_argument("--muesli-text", type=Path, default=HERE / "synthetic" / "muesli-zh-typed-v1.txt")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    exclusions: list[dict[str, str]] = []
    v1 = json.loads(args.v1_ground_truth.read_text())
    cases = english_cases(v1["panels"], "v1", exclusions)
    sources = {"v1_ground_truth_sha256": sha256_file(args.v1_ground_truth)}
    if args.v2_development_review:
        v2 = json.loads(args.v2_development_review.read_text())
        if v2.get("acceptance_gate") is not False or v2.get("kind") != "public_development_review_freeze":
            raise SystemExit("refusing anything but the frozen development-only v2 review")
        panels = [dict(p, families=p["ground_truth"].get("families")) for p in v2["panels"]]
        cases += english_cases(panels, "v2dev", exclusions)
        sources["v2_development_review_sha256"] = sha256_file(args.v2_development_review)
    muesli_text = args.muesli_text.read_text(encoding="utf-8")
    cases.append(
        text_case(
            "owner:muesli-6-grain:typed",
            muesli_text,
            render.muesli_truth(),
            {
                "corpus": "muesli_typed",
                "language": "zh-Hant",
                "licence": "Owner's own label, typed by hand; values published in the plan",
                "coverage_tags": [
                    "zh_hant",
                    "two_column_serving_and_100",
                    "serving_line",
                    "servings_per_pack",
                    "nested_rows",
                    "sodium",
                ],
                "synthetic": False,
            },
        )
    )
    fda, fda_summary = fda_cases(args.fda_csv, exclusions)
    cases += fda
    sources["fda188_csv_sha256"] = sha256_file(args.fda_csv)
    template, template_summary = template_cases()
    cases += template

    lines = [json.dumps(case, ensure_ascii=False, sort_keys=True) for case in cases]
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    report = {
        "generator_version": render.GENERATOR_VERSION,
        "seed": render.SEED,
        "dataset_sha256": sha256_file(args.out),
        "cases": len(cases),
        "by_corpus": {
            name: sum(1 for c in cases if c["metadata"]["corpus"] == name) for name in sorted({c["metadata"]["corpus"] for c in cases})
        },
        "required_declines": sum(1 for c in cases if c["truth"]["requires_decline"]),
        "sources": sources,
        "fda188": fda_summary,
        "zh_template": template_summary,
        "chinese_coverage": coverage(cases),
        "english_exclusions": exclusions,
    }
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("cases", "by_corpus", "required_declines", "dataset_sha256")}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
