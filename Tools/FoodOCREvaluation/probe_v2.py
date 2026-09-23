#!/usr/bin/env python3
"""Development regression on exposed v1 raw outputs; never a v2 gate."""

from __future__ import annotations

import json
from pathlib import Path

from build_gate_outcomes import raw_filename
from evaluate import score_panel
from geometry_v2 import candidate_review


def main() -> None:
    root = Path(__file__).resolve().parent
    fixture = json.loads((root / "fixtures/ground-truth-v1.json").read_text())
    v1 = json.loads((root / "fixtures/untouched-outcomes-v1.json").read_text())
    v1_by_id = {panel["panel_id"]: panel for panel in v1["panels"]}
    totals = {key: 0 for key in (
        "panels", "expected_cells", "v1_exact_cells", "v2_exact_cells",
        "v2_candidates", "v2_bounds_exact", "v2_conversions_exact", "v2_ready",
        "v1_false_ready_cases_still_ready",
    )}
    for panel in fixture["panels"]:
        if panel["split"] != "untouched_gate":
            continue
        raw = json.loads((root / "fixtures/untouched-vision-raw-v1" / raw_filename(panel["panel_id"])).read_text())
        if raw["imageSHA256"] != panel["image_sha256"]:
            raise ValueError(f"raw image identity mismatch: {panel['panel_id']}")
        v2 = candidate_review(raw)
        prior = score_panel(panel, v1_by_id[panel["panel_id"]])
        current = score_panel(panel, {
            "cells": v2["candidates"],
            "ready_for_confirmation": v2["ready_for_confirmation"],
            "unresolved_warning": v2["unresolved_warning"],
            "declined": v2["declined"],
        })
        totals["panels"] += 1
        totals["expected_cells"] += current["expected_cells"]
        totals["v1_exact_cells"] += prior["exact_cells"]
        totals["v2_exact_cells"] += current["exact_cells"]
        totals["v2_candidates"] += len(v2["candidates"])
        totals["v2_bounds_exact"] += current["bound_exact"]
        totals["v2_conversions_exact"] += current["conversion_exact"]
        totals["v2_ready"] += int(v2["ready_for_confirmation"])
        totals["v1_false_ready_cases_still_ready"] += int(
            v1_by_id[panel["panel_id"]]["ready_for_confirmation"] and v2["ready_for_confirmation"]
        )
    print(json.dumps({"scope": "exposed_v1_development_only_not_untouched_v2", **totals}, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
