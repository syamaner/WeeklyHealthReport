#!/usr/bin/env python3
"""Add the owner's approved food details to the catalogue file
(docs/personal-food-catalogue-identity-facts-v1-amendment.md sections I1.1, I1.3 and I1.5).

Reads, in the private workspace: the newest catalogue file in out/ (the estimates v3 file, else the
estimates v2 file, else the plain v2 file; never changed here) and work/approved-identity-facts.json
(`pfc-approved-identity-facts-v1`; absent means there is nothing to do). Only facts the owner approved
are in that file; anything else stays unknown.

Writes out/personal-food-catalogue-estimates-v4.json (mode 600) when at least one entry gets
non-null `identity_facts`, and the private out/identity-facts-report.json, which lists by entry ID
the entries whose facts would make the merge ineligible, would make the entry disappear, would make
an estimate contradict, or state `as_sold` for a food usually searched with "raw". A row that would
make the importer reject the file (an estimate contradiction) is never written, and one that would make
the entry disappear is written only with `accept_disappear: true`. With no row written, today's v2 or
v3 file stands and an earlier v4 file is renamed, so a stale one cannot be imported by mistake.

Prints counts, rule codes and the release ID only: never a title, brand or value.

Usage: python3 -I apply_identity_facts.py <workspace> <repo_root>
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check as guard_workspace, check_output  # noqa: E402
from private_config import require  # noqa: E402
import apply_estimates as AP  # noqa: E402
import estimates_input as I  # noqa: E402
import export_v1  # noqa: E402
import identity_facts as F  # noqa: E402

INPUT_NAME = "approved-identity-facts.json"
OUTPUT_NAME = "personal-food-catalogue-estimates-v4.json"
SUPERSEDED_NAME = "personal-food-catalogue-estimates-v4.superseded.json"
REPORT_NAME = "identity-facts-report.json"
BASE_NAMES = (AP.OUTPUT_NAME_V3, AP.OUTPUT_NAME, export_v1.OUTPUT_NAME)


def _retire(out: Path):
    old = out / OUTPUT_NAME
    if old.exists():
        old.replace(check_output(out / SUPERSEDED_NAME))
        print(f"renamed the earlier food details file to {SUPERSEDED_NAME}")


def _refuse(out: Path, text: str, lines=()):
    print(f"FOOD DETAILS REFUSED: {text}")
    for line in lines:
        print("  -", line)
    _retire(out)
    print("the previous catalogue file stands")
    sys.exit(2)


def check_additive(base: dict, out: dict) -> list:
    """The v4 document only adds `identity_facts` (and, over a plain v2 file, empty estimate keys)."""
    try:
        errs = []
        if [it["id"] for it in base["items"]] != [it["id"] for it in out["items"]]:
            return ["entries-changed"]
        for k in base:
            if k not in ("schema", "items") and I.canonical(base[k]) != I.canonical(out[k]):
                errs.append(f"top-changed: {k}")
        carried = "estimate_evidence" in base  # over a plain v2 file the estimate keys are added empty
        drop = {"identity_facts"} if carried else {"identity_facts", "estimated_nutrients"}
        differ = sum(I.canonical(a) != I.canonical({k: b[k] for k in b if k not in drop})
                     for a, b in zip(base["items"], out["items"]))
        if differ:
            errs.append(f"entries-differ-outside-facts: {differ}")
        return errs
    except Exception as e:  # noqa: BLE001
        return [f"malformed: {type(e).__name__}"]


def build(base: dict, approved: dict, read_record):
    """(output bytes or None when no row is written, report)."""
    out, report = F.apply(base, approved, read_record)
    if not report["written"]:
        return None, report
    return I.dumps(out), report


def main(ws: Path, repo: Path):
    ws = guard_workspace(ws)
    require()
    work, out = ws / "work", ws / "out"
    base_path = next((out / n for n in BASE_NAMES if (out / n).is_file()), None)
    if base_path is None:
        _refuse(out, "no catalogue file in out/; run export_v1.py first")
    if not (work / INPUT_NAME).exists():
        _retire(out)
        print(f"no {INPUT_NAME}: nothing to add, {base_path.name} stands")
        return
    base_bytes = base_path.read_bytes()
    errs = export_v1.check_bytes(base_bytes)
    if errs:
        _refuse(out, f"{base_path.name} fails the importer's rules", AP._codes(errs))
    base = json.loads(base_bytes)
    try:
        approved = F.parse((work / INPUT_NAME).read_bytes())
    except F.FactsRefused as e:
        _refuse(out, str(e))
    data, report = build(base, approved, AP.record_reader(repo.expanduser()))
    problems = []
    if data is not None:
        doc = json.loads(data)
        problems = AP._codes(export_v1.check_bytes(data)) + AP._codes(export_v1.check_export_conventions(doc)) \
            + AP._codes(check_additive(base, doc))
    summary = {k: len(v) for k, v in report.items()}
    AP._write(out / REPORT_NAME, json.dumps({"schema": "pfc-identity-facts-report-v1", "base": base_path.name,
                                             "release_id": I.release_id(data) if data else None,
                                             "counts": summary, "entries": report, "rule_codes": problems},
                                            indent=1).encode())
    print(f"food details: {summary}")
    if problems:
        _refuse(out, "the food details file would be rejected", problems)
    if data is None:
        _retire(out)
        print(f"no food details written: {base_path.name} stands")
        return
    path = AP._write(out / OUTPUT_NAME, data)
    print(f"wrote {path.name} ({len(data) / 1e6:.2f} MB, food details on {summary['written']} entries)")
    print(f"release {I.release_id(data)}")
    print(f"import this file, not {base_path.name}, on an app build that accepts {F.SCHEMA}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
