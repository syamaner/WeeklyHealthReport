#!/usr/bin/env python3
"""Command line for R1, the drops-only export (r1_export.py; E3 disposition D1 and D2).

Only this file touches files. It reuses the frozen review v2 checks without editing them: both
freeze records and the review seal must hold, Part A must already be scored (the bars lock exists
and matches), and the pinned release must have the ID in freeze-v1.json. It reads the exclusion
list and refuses it unless it equals the list the sealed review gives, derives the unresolved list from the
sealed review with the frozen parsers, writes the R1 file, the unresolved list and a build record
(switches and hashes) to the private folder (never overwriting a different file) and prints counts
and the R1 release ID only.

    pfd_r1.py build-r1 --root DIR --release PINNED.json --a1 {on,off} --a2 {on,off}
"""
import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent
REPO = TOOL.parents[1]
SKILL = REPO / ".agents" / "skills" / "personal-food-catalogue" / "scripts"
sys.path.insert(0, str(HERE))
sys.path.insert(1, str(TOOL / "v2"))
sys.path.insert(2, str(TOOL))
sys.path.insert(3, str(SKILL))

import exclusions  # noqa: E402
import formats  # noqa: E402
import freeze  # noqa: E402
import freeze_v2  # noqa: E402
import export_v1  # noqa: E402  (the importer's rejection rules, unchanged)
import pfd_eval_v2  # noqa: E402  (frozen checks and private-path rules, unchanged)
import r1_export  # noqa: E402
import score_a_v2  # noqa: E402
import seals  # noqa: E402
import seals_v2  # noqa: E402
from pfd_eval import write_all  # noqa: E402
from workspace_guard import check, check_output  # noqa: E402

OUT_DIR = Path("r1")
R1_FILE = OUT_DIR / "personal-food-catalogue-v1.json"
UNRESOLVED_FILE = OUT_DIR / "unresolved.json"
RECORD_FILE = OUT_DIR / "build-record.json"


def _write_once(items):
    """All or nothing; an existing file must already hold the same bytes."""
    todo = []
    for path, data in items:
        if path.exists() or path.is_symlink():
            if path.is_symlink() or not path.is_file() or path.read_bytes() != data:
                sys.exit("refused: an R1 output already exists and differs; it is never overwritten")
        else:
            todo.append((path, data))
    if todo:
        todo[0][0].parent.mkdir(mode=0o700, exist_ok=True)
        write_all(todo)


def cmd_build_r1(a, root: Path):
    fz1, fz2, fz2_sha = pfd_eval_v2.frozen(root, ("release_id", "sample_sha256"))
    seals_v2.require_review(root)
    if seals_v2.recorded(root).get(seals_v2.LOCK) is None:
        sys.exit("refused: Part A has not been scored; R1 is built only after score-a-v2 locks the bars")
    seals_v2.check_bars(root, fz2.get("part_a_bars"), fz2_sha)  # same bars and scoring code as the locked run
    if Path(a.release).is_symlink():
        sys.exit("refused: the pinned release file is a link")
    pinned_path = check_output(Path(a.release))
    if not pinned_path.is_file():
        sys.exit("refused: the pinned release file does not exist")
    pinned_bytes = pinned_path.read_bytes()
    if r1_export.release_id(pinned_bytes) != fz1["release_id"]:
        sys.exit("refused: the release file is not the pinned release")
    if export_v1.check_bytes(pinned_bytes):
        sys.exit("refused: the pinned release fails the importer's rules")
    sample, rows, records, inventory = pfd_eval_v2.bundle(root, fz1)
    by_row = score_a_v2.validate(sample, rows, records, inventory)
    per_stratum = {}
    for r in rows:
        n = sum(rec["assessment"] == "unresolved" for rec in by_row[r["row"]])
        if n:
            per_stratum[r["stratum"]] = per_stratum.get(r["stratum"], 0) + n
    unresolved_bytes = r1_export.build_unresolved(fz1["release_id"], r1_export.unresolved_list(rows, by_row))
    excl_bytes = pfd_eval_v2.read_private(root, root / pfd_eval_v2.EXCLUSIONS)
    excl = exclusions.parse(excl_bytes)
    if excl["release_id"] != fz1["release_id"]:
        sys.exit("refused: the exclusion list belongs to another release")
    expected = exclusions.build(fz1["release_id"], score_a_v2.exclusion_list(sample, rows, records, inventory))
    if excl_bytes != expected:
        sys.exit("refused: the exclusion list differs from the one the sealed review gives; it was changed")
    pinned = json.loads(pinned_bytes.decode("utf-8"))
    switches = {"a1": a.a1 == "on", "a2": a.a2 == "on"}
    try:
        unresolved = r1_export.parse_unresolved(unresolved_bytes)
        doc, counts = r1_export.derive(pinned, excl, unresolved, switches, set(inventory["group_of"]))
    except r1_export.R1Error as e:
        sys.exit(f"refused: {e}")
    data = r1_export.dumps(doc)
    errs = r1_export.check_drops_only(pinned, doc) + r1_export.check_applied(doc, excl, unresolved, switches) \
        + export_v1.check_export_conventions(doc) + export_v1.check_bytes(data)
    if errs:
        sys.exit(f"refused: R1 fails {len(errs)} checks (drops-only, applied, conventions or importer rules); "
                 "nothing written")
    record = json.dumps({"schema": "pfd-r1-build-v1", "pinned_release_id": fz1["release_id"],
                         "r1_release_id": r1_export.release_id(data), "switches": switches,
                         "exclusions_sha256": formats.sha256(excl_bytes),
                         "unresolved_sha256": formats.sha256(unresolved_bytes)},
                        sort_keys=True, separators=(",", ":")).encode() + b"\n"
    _write_once([(pfd_eval_v2.private(root, root / UNRESOLVED_FILE), unresolved_bytes),
                 (pfd_eval_v2.private(root, root / R1_FILE), data),
                 (pfd_eval_v2.private(root, root / RECORD_FILE), record)])
    print(f"R1 built with a1 {a.a1}, a2 {a.a2}: " + "; ".join(f"{k} {v}" for k, v in counts.items()))
    print(f"unresolved values withheld: {len(unresolved['withhold_values'])} "
          f"(by stratum: {', '.join(f'{k} {v}' for k, v in sorted(per_stratum.items())) or 'none'})")
    print(f"R1 release {r1_export.release_id(data)}")


def main(argv=None):
    p = argparse.ArgumentParser(prog="pfd_r1.py", description="R1, the drops-only export (counts only).")
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("build-r1")
    sp.add_argument("--root", required=True)
    sp.add_argument("--release", required=True)
    sp.add_argument("--a1", required=True, choices=("on", "off"))
    sp.add_argument("--a2", required=True, choices=("on", "off"))
    a = p.parse_args(argv)
    root = check(Path(a.root))
    try:
        cmd_build_r1(a, root)
    except (r1_export.R1Error, formats.FormatError, freeze.FreezeError, freeze_v2.FreezeError, seals.SealError,
            seals_v2.SealError) as e:
        sys.exit(f"refused: {e}")


if __name__ == "__main__":
    main()
