#!/usr/bin/env python3
"""Add the owner's accepted estimates to the plain v2 catalogue file
(docs/personal-food-catalogue-estimates-v2-phase.md section 3.2).

Reads, in the private workspace: out/personal-food-catalogue-v2.json (written by export_v1.py, never
changed here), work/accepted-estimates.json (`pfc-accepted-estimates-v1`; absent means there is
nothing to do) and three optional lists, work/estimate-refusals.json,
work/estimate-readmissions.json and work/estimate-readmission-sheet.json. National composition values
are read from the app's bundled corpus files in the repository, with their hash pins checked.

Writes out/personal-food-catalogue-estimates-v2.json (mode 600) when at least one estimate is
admitted, and the private out/estimates-change-report.json. With no estimate admitted the plain v2
file stands and no estimates file is written. It refuses to write (exit 2) a file the app's codec
would reject, a file that is not purely additive over the plain v2 file, or one for which any
must-be-zero evaluator count is not zero. An estimates file left by an earlier run is renamed
whenever this run does not write a new one, so a stale file cannot be imported by mistake.

Prints counts, rule codes, entry IDs and the release ID only: never a title, brand or value.

Usage: python3 -I apply_estimates.py <workspace> <repo_root>
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_guard import check as guard_workspace, check_output  # noqa: E402
from private_config import require  # noqa: E402
import assemble as A  # noqa: E402  (the skill's existing record readers)
import estimate_counts as C  # noqa: E402
import estimates_input as I  # noqa: E402
import export_v1  # noqa: E402

INPUT_NAME = "accepted-estimates.json"
REFUSALS_NAME = "estimate-refusals.json"
READMISSIONS_NAME = "estimate-readmissions.json"
SHEET_NAME = "estimate-readmission-sheet.json"
OUTPUT_NAME = "personal-food-catalogue-estimates-v2.json"
SUPERSEDED_NAME = "personal-food-catalogue-estimates-v2.superseded.json"
# Label photo phase gate section 1: a run that admits a photo estimate writes v3 under its own name.
OUTPUT_NAME_V3 = "personal-food-catalogue-estimates-v3.json"
SUPERSEDED_NAME_V3 = "personal-food-catalogue-estimates-v3.superseded.json"
REPORT_NAME = "estimates-change-report.json"


def _canonical_unit(values: dict) -> dict:
    """Quantified values in the key's canonical unit only; anything else is unknown, never converted."""
    return {k: v["value"] for k, v in values.items()
            if v.get("value") is not None and v.get("unit") == export_v1.CANON_UNITS.get(k)}


def cofid_facts(rec: dict) -> dict:
    """As the app's CoFID adapter reads a record (`CoFIDGenericFoodSearch`): a value whose source unit is
    not the key's canonical unit is unknown, never converted. Today that is water, held in g against a
    canonical mL, so a water estimate is never written that the app's importer would refuse."""
    identity = rec["identity"]
    same_unit = {k: v for k, v in rec["nutrients"].items()
                 if isinstance(v, dict) and v.get("source_unit") == v.get("canonical_unit")}
    return {"nutrients": _canonical_unit(A.cofid_nutrients({**rec, "nutrients": same_unit})),
            "preparation": identity["preparation"],
            "fortification": identity["fortification"], "per_100_g": identity["serving_basis"] == "per_100_g",
            "per_100_ml": identity["serving_basis"] == "per_100_ml"}


def usda_facts(rec: dict, prefix="usda") -> dict:
    """USDA and TFDA records never state fortification (contract section 3.1), so it is None here."""
    return {"nutrients": _canonical_unit(A.usda_nutrients(rec, prefix=prefix)), "preparation": rec["preparation"],
            "fortification": None, "per_100_g": True, "per_100_ml": False}


def record_reader(repo: Path):
    """`read_record(source, record_id)` over the bundled corpus files, each loaded on first use. A
    record ID is the one `export_v1.choose_reference` writes, so a TFDA ID carries its `tfda:` prefix."""
    res = repo / "Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources"
    index, cache = {}, {}

    def load(source):
        records = json.loads((res / export_v1.SWIFT_PINS[source][0]).read_bytes())["records"]
        if source == "cofid":
            return {r["record_id"]: r for r in records}
        return {("tfda:" if source == "tfda" else "") + r["id"]: r for r in records}

    def read(source, record_id):
        key = (source, record_id)
        if key not in cache:
            try:
                if source not in index:
                    index[source] = load(source) if source in export_v1.SWIFT_PINS else {}
                rec = index[source].get(record_id)
                cache[key] = None if rec is None else (
                    cofid_facts(rec) if source == "cofid" else usda_facts(rec, prefix=source))
            except (OSError, ValueError, TypeError, KeyError, AttributeError):
                cache[key] = None  # a record that cannot be read supplies nothing
        return cache[key]

    return read


def _codes(errs) -> list:
    """The rule code of each "code: detail" string. Details can hold a title, so they are dropped."""
    return sorted({str(e).split(":", 1)[0] for e in errs})


def _write(path: Path, data: bytes):
    path = check_output(path)
    path.write_bytes(data)
    path.chmod(0o600)
    return path


def _retire(out: Path, keep: str = ""):
    """Renames an estimates file left by an earlier run, of either name except `keep`; it no longer
    matches the plain v2 file."""
    for name, superseded in ((OUTPUT_NAME, SUPERSEDED_NAME), (OUTPUT_NAME_V3, SUPERSEDED_NAME_V3)):
        old = out / name
        if name != keep and old.exists():
            old.replace(check_output(out / superseded))
            print(f"renamed the earlier estimates file to {superseded}")


def _refuse(out: Path, text: str, lines=()):
    print(f"ESTIMATES REFUSED: {text}")
    for line in lines:
        print("  -", line)
    _retire(out)
    print("the plain v2 file stands")
    sys.exit(2)


def _optional(path: Path, parse):
    return parse(path.read_bytes()) if path.exists() else None


def main(ws: Path, repo: Path):
    ws = guard_workspace(ws)
    require()
    work, out = ws / "work", ws / "out"
    plain_path = out / export_v1.OUTPUT_NAME
    if not plain_path.is_file():
        _refuse(out, f"{export_v1.OUTPUT_NAME} is missing; run export_v1.py first")
    plain = plain_path.read_bytes()
    errs = export_v1.check_bytes(plain)
    if errs:
        _refuse(out, "the plain v2 file fails the importer's rules", _codes(errs))
    doc = json.loads(plain)
    if doc["schema"] != export_v1.SCHEMA_V2 or I.dumps(doc) != plain:
        _refuse(out, "the plain file is not a personal-food-catalogue-v2 file in the export's own serialisation")
    release = I.release_id(plain)
    if not (work / INPUT_NAME).exists():
        _retire(out)
        print(f"no {INPUT_NAME}: nothing to add, the plain v2 file stands (release {release})")
        return
    lists_read = {name: (work / name).exists() for name in (REFUSALS_NAME, READMISSIONS_NAME, SHEET_NAME)}
    # Contract 3.1: E3 refusals bind by default, so they must have been checked. A missing refusal
    # list is not an empty one: it stops the run. A list with no rows records a completed check
    # that found nothing to refuse.
    if not lists_read[REFUSALS_NAME]:
        _refuse(out, f"no {REFUSALS_NAME}: the refused sources must be carried forward before any estimate is written; "
                     "write one with no rows if there is nothing to refuse")
    try:
        accepted = I.parse((work / INPUT_NAME).read_bytes())
        lists = C.Lists(_optional(work / REFUSALS_NAME, C.parse_refusals),
                        _optional(work / READMISSIONS_NAME, C.parse_readmissions),
                        _optional(work / SHEET_NAME, C.parse_sheet))
    except I.EstimatesRefused as e:
        _refuse(out, str(e))
    if accepted["catalogue_release_id"] != release:
        _refuse(out, f"the rows were accepted against another catalogue release; this one is {release}")
    pins, pin_errs = export_v1.corpus_pins(repo.expanduser())
    declared = {c["source"]: c["corpus_sha256"] for c in doc["generic_corpora"]}
    if pin_errs or any(pins.get(source) != digest for source, digest in declared.items()):
        _refuse(out, "a bundled corpus file does not match its pin or the catalogue's declared hash",
                [e.split(":", 1)[0] for e in pin_errs])
    read_record = record_reader(repo.expanduser())
    try:
        estimates, counts = I.expand(doc, accepted, read_record)
    except I.EstimatesRefused as e:
        _refuse(out, str(e))
    admitted, admission = I.admit(doc, estimates, read_record, lists.status)
    counts.update(admission)
    counts.update(I.change_report(doc, admitted, read_record))
    data = I.output_bytes(plain, doc, admitted)
    out_doc = json.loads(data)
    six = C.six_counts(out_doc, accepted["rows"], lists)
    problems = []
    if admitted:
        problems = _codes(export_v1.check_bytes(data)) + _codes(export_v1.check_export_conventions(out_doc)) \
            + _codes(I.check_additive(doc, out_doc)) + _codes(I.check_admitted(out_doc, admitted))
    failed = C.failures(six)
    report = {"schema": "pfc-estimates-change-report-v1", "plain_release_id": release,
              "release_id": I.release_id(data), "written": bool(admitted) and not problems and not failed,
              "counts": counts, "evaluator_counts": six["counts"], "evaluator_checks": six["checks"],
              "readmission_lists": six["lists"], "readmitted_rows": six["readmitted_rows"],
              # Which private lists were present: an absent refusals list refuses nothing, and the
              # report must say so rather than show a zero that was never checked.
              "lists_read": lists_read,
              "rule_codes": problems}
    _write(out / REPORT_NAME, json.dumps(report, indent=1, ensure_ascii=False).encode())
    print(f"accepted estimates: {counts}")
    print(f"evaluator counts: {six['counts']}; lists: {six['lists']}")
    missing = [name for name, present in lists_read.items() if not present]
    print(f"private lists read: {[n for n, p in lists_read.items() if p]}"
          + (f"; NOT PRESENT (nothing checked against them): {missing}" if missing else ""))
    if problems or failed:
        _refuse(out, "the estimates file would be rejected or a must-be-zero count is not zero", problems + failed)
    if not admitted:
        _retire(out)
        print(f"no estimate admitted: the plain v2 file stands (release {release})")
        return
    name = OUTPUT_NAME_V3 if out_doc["schema"] == export_v1.SCHEMA_ESTIMATES_V3 else OUTPUT_NAME
    _retire(out, keep=name)
    path = _write(out / name, data)
    print(f"wrote {path.name} ({len(data) / 1e6:.2f} MB, {counts['admitted']} estimates on "
          f"{counts['entries_with_estimates']} entries, {counts['checked_against_bundled_record']} to be checked "
          f"against a bundled record by the app)")
    print(f"release {I.release_id(data)}")
    print(f"import this file, not {export_v1.OUTPUT_NAME}, on an app build that accepts {out_doc['schema']}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
