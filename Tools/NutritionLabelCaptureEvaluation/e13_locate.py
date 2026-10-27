#!/usr/bin/env python3
"""Locator exposure of the E13 answers (docs/label-photo-ai-prefill-v1.md 17.21).

Offline and on device: no model, provider or network call. It takes the E13 run's answers for
the scored Taiwan photos and does the following:

- maps each answer as `e13_score.py` does;
- prepares each photo as E3 says;
- runs Apple Vision and the L0 locator (`Tools/LabelPhotoLocateL0`, `label-photo-vision-locate-v3`)
  on the prepared bytes, exactly as `l0_locate.py` does for the October answers;
- asks, per pre-filled table, whether the app would draw attention to every silent wrong value
  (`silent_caught`) and whether it would block Log on it (`silent_blocked`).

A row the answer left out entirely has no pre-filled value to locate, so the locator cannot raise
it. Such a row is reported as an omission, not as caught.

Jobs and raw results stay under the private runs folder. Only counts and case ids are written.

    python3 -I e13_locate.py --out results/e13-locate-v1.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import correction_effort as ce  # noqa: E402
import decline_gate  # noqa: E402
import e13_score  # noqa: E402
import l0_locate  # noqa: E402


def rows_for(records: list[dict[str, Any]], split: str) -> list[dict[str, Any]]:
    truths = {r["case_id"]: r for r in json.loads(e13_score.TRUTH[split].read_text(encoding="utf-8"))["records"]}
    rows = []
    for record in records:
        truth = truths.get(record["id"])
        if record["split"] != split or truth is None or not ce.usable(truth):
            continue
        rows.append({"id": record["id"], "truth": truth, "label_format": decline_gate.TAIWAN, "candidate": e13_score.candidate(record)})
    return rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    private = Path.home() / "WHR-label-eval-private"
    parser.add_argument("--records", type=Path, default=private / "runs" / "e13-v1" / "e13-records.jsonl")
    parser.add_argument("--photos", type=Path, default=private / "off-taiwan-v1")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    records = [json.loads(line) for line in args.records.read_text(encoding="utf-8").splitlines() if line.strip()]
    photos = l0_locate.photo_index(args.photos)
    work = private / "runs" / "e13-v1" / "locate"
    report: dict[str, Any] = {
        "analysis": "e13-locate-v1",
        "egress": "none",
        "locator": "Tools/LabelPhotoLocateL0 LabelValueMatcher (label-photo-vision-locate-v3)",
        "view": "assisted",
        "strata": {},
    }
    for split in ("untouched", "development"):
        rows = [row for row in rows_for(records, split) if row["candidate"] is not None]
        tables, meta = l0_locate.run_arm(rows, photos, work, f"e13-{split}")
        silent = [t for t in tables if t.get("silent_table")]
        report["strata"][split] = {
            **l0_locate.summarise(tables),
            **meta,
            "silent_tables": [
                {
                    "id": t["id"],
                    "silent_values": t["silent"],
                    "silent_values_flagged_by_locator_or_checks": t["silent_by_locator_or_checks"],
                    "silent_serving_lines": [f for f, s in t["serving"].items() if s["truth"] == "wrong"],
                    "caught": t["silent_caught"],
                    "blocked": t["silent_blocked"],
                }
                for t in silent
            ],
        }
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    for split, block in report["strata"].items():
        print(split, json.dumps(block["silent_tables"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
