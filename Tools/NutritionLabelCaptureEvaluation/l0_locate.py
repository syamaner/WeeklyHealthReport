#!/usr/bin/env python3
"""Phase L0 of the label photo AI pre-fill (#316, docs/label-photo-ai-prefill-v1.md 6.1 and 17.6).

Offline and on device: no model, provider or network call, and nothing is rerun at a provider.
It takes the saved route C answers of the untouched and development Taiwan runs, prepares each
public Open Food Facts photo as E3 says, runs Apple Vision on the prepared bytes on this Mac, and
locates every pre-filled value with the shipped Swift matcher (`Tools/LabelPhotoLocateL0`,
`LabelValueMatcher`, `label-photo-vision-locate-v1`). It then asks:

- how many correct values are found on the photo (attention noise is the rest);
- how many of the silent errors of the correction-effort analysis (assisted view) would have
  become attention items, by the locator alone and with the arithmetic checks;
- how many pre-filled tables would open with no attention item at all.

Jobs and raw results (photo paths and model text) stay under the private runs folder; only counts
and case ids are written to the repository.

    .venv/bin/python l0_locate.py --runs ~/WHR-label-eval-private/runs --photos ~/WHR-label-eval-private/off-taiwan-v1 \\
        --out results/l0-locate-rate-v4.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import statistics
import subprocess
from pathlib import Path
from typing import Any

import arithmetic
import correction_effort as ce
import score as scoring

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent / "LabelPhotoLocateL0"
ANALYSIS_VERSION = "label-photo-l0-locate-rate-v4"
ATTENTION_DRAFT = "label-photo-attention-v1 (draft used by L0)"
# The alternative attention policy measured for the owner (L1c, 17.11): only items with evidence block
# Log (a gate flag, a failed check, or the photo contradicting the value: its token printed only in
# another row or column, or a different token in its own cell); "not located" is a soft marker plus
# one table-level confirmation.
EVIDENCE_POLICY = "evidence-blocks-v1 (measured, not adopted)"
CONTRADICTING = ("elsewhere", "conflicting_in_cell")
ARMS = ("gemini-on", "sol-on", "luna-off")
ENERGY_ROWS = ("energy_kcal", "protein", "fat", "carbohydrate", "fibre")


# ---------------------------------------------------------------- pure


def classify_cells(output: dict[str, Any], truth: dict[str, Any], report: dict[str, Any]) -> dict[int, str]:
    """Each known pre-filled cell (by index in `output["cells"]`): `correct`, `wrong` or `unscored`.

    The same matching as `correction_effort.label_effort` (stage 1 exact by the scorer's key, then
    the rest are corrections or removals), keeping the cell identity.
    """
    cells = output.get("cells") or []
    known = [i for i, c in enumerate(cells) if ce._value_known(c)]
    if truth.get("reference_intake_transcribed") is False:
        known = [i for i in known if cells[i].get("basis") != "reference_intake"]
    unscored = {(scoring.nutrient_key(c), c.get("basis")) for c in truth.get("unscored_cells") or []}
    truth_groups: dict[tuple, list[dict[str, Any]]] = {}
    for cell in ce.gradable_truth_cells(truth):
        truth_groups.setdefault(ce._key(cell, truth), []).append(cell)
    classes: dict[int, str] = {}
    by_key: dict[tuple, list[int]] = {}
    for i in known:
        by_key.setdefault(ce._key(cells[i], output), []).append(i)
    for key, indices in by_key.items():
        expected = list(truth_groups.get(key, []))
        for i in indices:
            match = next((t for t in expected if scoring.strict_equal(t, cells[i])), None)
            if match is not None:
                expected.remove(match)
                classes[i] = "correct"
    for i in known:
        if i not in classes:
            classes[i] = "unscored" if (scoring.nutrient_key(cells[i]), cells[i].get("basis")) in unscored else "wrong"
    return classes


def arithmetic_attention(output: dict[str, Any]) -> set[int]:
    """Cells the failed arithmetic and consistency checks implicate (attention draft rules)."""
    cells = output.get("cells") or []
    implicated: set[int] = set()
    for check in arithmetic.check_table(output)["checks"]:
        if check.get("status") != arithmetic.FAIL:
            continue
        name, basis = check.get("name"), check.get("basis")
        for i, cell in enumerate(cells):
            nutrient = cell.get("nutrient")
            if (
                (name == "energy" and cell.get("basis") == basis and nutrient in ENERGY_ROWS)
                or (name == "kj_kcal_ratio" and cell.get("basis") == basis and nutrient in ("energy_kcal", "energy_kj"))
                or (name == "serving_scaling" and nutrient == check.get("nutrient") and cell.get("basis") != "reference_intake")
                or (
                    name == "subrow_not_above_parent"
                    and cell.get("basis") == basis
                    and nutrient in (check.get("child"), arithmetic_parent(check.get("child")))
                )
            ):
                implicated.add(i)
    return implicated


def arithmetic_parent(child: Any) -> str:
    return {"saturates": "fat", "trans_fat": "fat", "sugars": "carbohydrate", "fibre": "carbohydrate"}.get(str(child), "")


def queries(output: dict[str, Any]) -> tuple[list[str], list[str], list[dict[str, Any]]]:
    """Every header (an empty text when none is printed), its basis for the locator, and the queries."""
    listed = output.get("headers") or []
    headers = {h.get("header_id"): h.get("printed_text") or None for h in listed}
    found = []
    for i, cell in enumerate(output.get("cells") or []):
        if ce._value_known(cell) and cell.get("printed_text"):
            found.append(
                {
                    "id": f"cell:{i}",
                    "row_label": cell.get("printed_label") or None,
                    "header_text": headers.get(cell.get("header_id")),
                    "printed_text": cell["printed_text"],
                }
            )
    for field in ce.SERVING_FIELDS:
        line = output.get(field)
        if isinstance(line, dict) and line.get("printed_text"):
            found.append({"id": field, "row_label": None, "header_text": None, "printed_text": line["printed_text"]})
    texts = [h.get("printed_text") or "" for h in listed]
    bases = ["reference_intake" if h.get("basis") == "reference_intake" else "amount" for h in listed]
    return texts, bases, found


def table_result(
    row: dict[str, Any], located: dict[str, str], evidence: dict[str, str] | None = None, regions: dict[str, bool] | None = None
) -> dict[str, Any]:
    output, truth = row["candidate"], row["truth"]
    view, report = ce.assisted_view(output, row["label_format"])
    if report["hard_decline"] is not None or view is None:
        return {"id": row["id"], "prefilled": False}
    classes = classify_cells(view, truth, report)
    flagged_rows = ce.flagged_rows(report.get("details") or [])
    arith = arithmetic_attention(view)
    cells = view.get("cells") or []
    counts = {
        k: 0
        for k in (
            "correct_found",
            "correct_not_found",
            "correct_ambiguous",
            "wrong",
            "wrong_flagged",
            "silent",
            "silent_by_locator",
            "silent_by_locator_or_checks",
            "attention",
            "blocking",
            "silent_blocking",
            "ambiguous_with_region",
            "ambiguous_total",
        )
    }
    evidence = evidence or {}
    regions = regions or {}
    silent_missed = 0
    silent_unblocked = 0
    for i, kind in classes.items():
        status = located.get(f"cell:{i}", "not_found")
        by_locator = status != "found"
        by_gate = cells[i].get("nutrient") in flagged_rows
        attention = by_locator or by_gate or i in arith
        counts["attention"] += int(attention)
        blocking = by_gate or i in arith or (by_locator and evidence.get(f"cell:{i}") in CONTRADICTING)
        if status == "ambiguous":
            counts["ambiguous_total"] += 1
            counts["ambiguous_with_region"] += int(regions.get(f"cell:{i}", False))
        counts["blocking"] += int(blocking)
        if kind == "correct":
            counts["correct_" + {"found": "found", "not_found": "not_found", "ambiguous": "ambiguous"}[status]] += 1
        elif kind == "wrong":
            counts["wrong"] += 1
            if by_gate:
                counts["wrong_flagged"] += 1
            else:
                counts["silent"] += 1
                counts["silent_by_locator"] += int(by_locator)
                counts["silent_by_locator_or_checks"] += int(by_locator or i in arith)
                silent_missed += int(not (by_locator or i in arith))
                counts["silent_blocking"] += int(blocking)
                silent_unblocked += int(not blocking)
    serving = {}
    for field in ce.SERVING_FIELDS:
        status = ce._serving_status(field, truth, view)
        if status in ("ok", "correction", "removal") and isinstance(view.get(field), dict):
            serving[field] = {"truth": "correct" if status == "ok" else "wrong", "located": located.get(field, "not_found")}
            counts["attention"] += int(located.get(field, "not_found") != "found")
    silent_serving = [f for f, s in serving.items() if s["truth"] == "wrong"]
    silent_serving_missed = [f for f in silent_serving if serving[f]["located"] == "found"]
    return {
        "id": row["id"],
        "prefilled": True,
        **counts,
        "serving": serving,
        "silent_table": bool(counts["silent"] or silent_serving),
        "silent_caught": bool(counts["silent"] or silent_serving) and silent_missed == 0 and not silent_serving_missed,
        "silent_blocked": bool(counts["silent"] or silent_serving) and silent_unblocked == 0 and not silent_serving,
    }


def summarise(tables: list[dict[str, Any]]) -> dict[str, Any]:
    pre = [t for t in tables if t["prefilled"]]
    total = {
        k: sum(t[k] for t in pre)
        for k in (
            "correct_found",
            "correct_not_found",
            "correct_ambiguous",
            "wrong",
            "wrong_flagged",
            "silent",
            "silent_by_locator",
            "silent_by_locator_or_checks",
            "silent_blocking",
            "ambiguous_total",
            "ambiguous_with_region",
        )
    }
    blocking = sorted(t["blocking"] for t in pre)
    correct = total["correct_found"] + total["correct_not_found"] + total["correct_ambiguous"]
    lines = [s for t in pre for s in t["serving"].values()]
    attention = sorted(t["attention"] for t in pre)
    return {
        "tables": len(tables),
        "prefilled_tables": len(pre),
        "correct_cells": correct,
        **total,
        "correct_found_share": round(total["correct_found"] / correct, 4) if correct else None,
        "serving_lines": len(lines),
        "serving_lines_found": sum(1 for s in lines if s["located"] == "found"),
        "tables_with_no_attention": sum(1 for t in pre if t["attention"] == 0),
        "attention_per_table_median": statistics.median(attention) if attention else None,
        "attention_per_table_p90": ce.nearest_rank(attention, 0.9) if attention else None,
        "silent_error_tables": sorted(t["id"] for t in pre if t["silent_table"]),
        "silent_error_tables_caught": sorted(t["id"] for t in pre if t["silent_caught"]),
        "evidence_policy": {
            "blocking_per_table_median": statistics.median(blocking) if blocking else None,
            "blocking_per_table_p90": ce.nearest_rank(blocking, 0.9) if blocking else None,
            "tables_with_no_blocking": sum(1 for t in pre if t["blocking"] == 0),
            "silent_wrong_values_blocking": total["silent_blocking"],
            "silent_error_tables_fully_blocked": sorted(t["id"] for t in pre if t["silent_blocked"]),
        },
    }


# ---------------------------------------------------------------- I/O


def photo_index(photos: Path) -> dict[str, Path]:
    index = {}
    for path in sorted(photos.rglob("*")):
        if path.is_file() and path.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp", ".heic"):
            index[hashlib.sha256(path.read_bytes()).hexdigest()] = path
    return index


def run_arm(
    rows: list[dict[str, Any]], photos: dict[str, Path], work: Path, name: str, min_short_edge: int | None = None
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    jobs, missing = [], []
    for row in rows:
        path = photos.get(row["truth"]["input_sha256"])
        if path is None:
            missing.append(row["id"])
            continue
        headers, bases, found = queries(row["candidate"] or {})
        jobs.append(
            {
                "id": row["id"],
                "image_path": str(path),
                "headers": headers,
                "header_bases": bases,
                "column_count": len(headers),
                "queries": found,
            }
        )
    work.mkdir(parents=True, exist_ok=True)
    jobs_path, out_path = work / f"{name}-jobs.json", work / f"{name}-located.json"
    jobs_path.write_text(json.dumps(jobs, ensure_ascii=False), encoding="utf-8")
    subprocess.run(
        ["swift", "run", "-c", "release", "--package-path", str(TOOL), "label-photo-locate-l0", str(jobs_path), str(out_path)],
        check=True,
        env=dict(os.environ, **({"L0_MIN_SHORT_EDGE": str(min_short_edge)} if min_short_edge is not None else {})),
    )
    results = {r["id"]: r for r in json.loads(out_path.read_text(encoding="utf-8"))}
    tables = []
    prepared = [r["prepared"] for r in results.values() if r.get("prepared")]
    for row in rows:
        result = results.get(row["id"])
        if result is None or result.get("refused"):
            tables.append({"id": row["id"], "prefilled": False})
            continue
        tables.append(
            table_result(
                row,
                {loc["id"]: loc["status"] for loc in result["locations"]},
                {loc["id"]: loc.get("evidence", "none") for loc in result["locations"]},
                {loc["id"]: bool(loc.get("has_region")) for loc in result["locations"]},
            )
        )
    meta = {
        "photos_missing": missing,
        "photos_refused": {
            reason: sorted(r["id"] for r in results.values() if r.get("refused") == reason)
            for reason in sorted({r["refused"] for r in results.values() if r.get("refused")})
        },
        "prepared_long_edge_max": max((max(p["width"], p["height"]) for p in prepared), default=None),
        "prepared_bytes_max": max((p["bytes"] for p in prepared), default=None),
        "prepared_quality_counts": {str(q): sum(1 for p in prepared if p["quality"] == q) for q in (0.85, 0.75, 0.65)},
        "vision": next(iter(results.values()))["vision"] if results else None,
    }
    return tables, meta


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    private = Path.home() / "WHR-label-eval-private"
    parser.add_argument("--runs", type=Path, default=private / "runs")
    parser.add_argument("--photos", type=Path, default=private / "off-taiwan-v1")
    parser.add_argument("--out", type=Path, default=HERE / "results" / "l0-locate-rate-v4.json")
    args = parser.parse_args(argv)
    photos = photo_index(args.photos)
    work = args.runs / "l0-locate-v1"
    report: dict[str, Any] = {
        "analysis_version": ANALYSIS_VERSION,
        "attention_rules": ATTENTION_DRAFT,
        "alternative_policy": EVIDENCE_POLICY,
        "view": "assisted",
        "egress": "none",
        "matcher": "Tools/LabelPhotoLocateL0 LabelValueMatcher (label-photo-vision-locate-v3)",
        "locator": "label-photo-vision-locate-v3 (L1d); v2 counts in l0-locate-rate-v3.json, v1 in l0-locate-rate-v2.json",
        "strata": {},
    }
    passes = (("untouched_taiwan", None), ("development_taiwan", None))
    for stratum, minimum in passes:
        report["strata"][stratum] = {}
        for arm in ARMS:
            if stratum.startswith("untouched_taiwan"):
                rows, _ = ce.untouched_rows(args.runs, arm)
            else:
                rows = ce.development_rows(args.runs, arm).get("taiwan_zh_hant", [])
            tables, meta = run_arm(rows, photos, work, f"{stratum}-{arm}", minimum)
            report["strata"][stratum][arm] = {**summarise(tables), **meta}
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                s: {
                    a: {
                        k: v[k]
                        for k in (
                            "prefilled_tables",
                            "correct_found_share",
                            "silent",
                            "silent_by_locator_or_checks",
                            "tables_with_no_attention",
                        )
                    }
                    for a, v in arms.items()
                }
                for s, arms in report["strata"].items()
            },
            indent=1,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
