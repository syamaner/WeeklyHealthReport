#!/usr/bin/env python3
"""Command line for R2, R1 plus owner-approved estimates (r2_export.py;
docs/personal-food-database-r2-builder-v1.md).

Only this file touches files. It refuses unless the pinned release has the ID in freeze-v1.json, the
R1 file in the private folder has the ID its build record names, the R1 unresolved and exclusion
lists match the hashes in that record, and the companion names the R1 ID. It writes the R2 file and
a build record to the private folder (never overwriting a different file) and prints counts and the
R2 release ID only.

    pfd_r2.py build-r2 --root DIR --release PINNED.json --companion COMPANION.json
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
sys.path.insert(2, str(TOOL / "r1"))
sys.path.insert(3, str(TOOL))
sys.path.insert(4, str(SKILL))

import estimates_v1  # noqa: E402
import exclusions  # noqa: E402
import export_v1  # noqa: E402
import formats  # noqa: E402
import formats_v2  # noqa: E402
import freeze  # noqa: E402
import freeze_v2  # noqa: E402
import pfd_eval_v2  # noqa: E402  (private-path rules, unchanged)
import r1_export  # noqa: E402
import r2_export  # noqa: E402
from pfd_eval import write_all  # noqa: E402
from workspace_guard import check, check_output  # noqa: E402

R1_DIR = Path("r1")
R1_FILE = R1_DIR / "personal-food-catalogue-v1.json"
R1_UNRESOLVED = R1_DIR / "unresolved.json"
R1_RECORD = R1_DIR / "build-record.json"
OUT_DIR = Path("r2")  # each build in r2/<R2 ID prefix>-<companion hash prefix>/, so rebuilds never collide
R2_NAME = "personal-food-catalogue-estimates-v1.json"
RECORD_NAME = "build-record.json"


def release_dir(r2_id: str, companion_sha256: str) -> Path:
    """Keyed by the release and the companion, so a companion that changes only withheld rows (same
    R2 bytes, different record) gets its own folder and its counts are still printed."""
    return OUT_DIR / f"{r2_id.split(':')[-1][:16]}-{companion_sha256[:16]}"


def _write_once(items):
    """All or nothing; an existing file must already hold the same bytes."""
    todo = []
    for path, data in items:
        if path.exists() or path.is_symlink():
            if path.is_symlink() or not path.is_file() or path.read_bytes() != data:
                sys.exit("refused: an R2 output already exists and differs; it is never overwritten")
        else:
            todo.append((path, data))
    if todo:
        todo[0][0].parent.mkdir(mode=0o700, exist_ok=True)
        write_all(todo)


def _r1_record(data: bytes) -> dict:
    try:
        rec = json.loads(data.decode("utf-8"), object_pairs_hook=export_v1._no_duplicate_keys)
    except Exception:  # noqa: BLE001  (bad UTF-8, bad JSON or a repeated key)
        sys.exit("refused: the R1 build record is not valid JSON")
    need = {"schema", "pinned_release_id", "r1_release_id", "exclusions_sha256", "unresolved_sha256"}
    if not isinstance(rec, dict) or not need <= set(rec) or rec["schema"] != "pfd-r1-build-v1":
        sys.exit("refused: the R1 build record is not a pfd-r1-build-v1 record")
    return rec


def cmd_build_r2(a, root: Path):
    fz1 = freeze.check(freeze.load(pfd_eval_v2.FREEZE_V1), REPO, ("release_id",))
    if pfd_eval_v2.FREEZE_V2.is_symlink() or not pfd_eval_v2.FREEZE_V2.is_file():
        sys.exit("refused: the freeze-v2 record is missing")
    freeze_v2.check(freeze_v2.parse(pfd_eval_v2.FREEZE_V2.read_bytes()), REPO, pfd_eval_v2.FREEZE_V1)  # inventory hash
    for name in (a.release, a.companion):
        if Path(name).is_symlink():
            sys.exit("refused: an input file is a link")
    pinned_path = check_output(Path(a.release))
    if not pinned_path.is_file():
        sys.exit("refused: the pinned release file does not exist")
    pinned_bytes = pinned_path.read_bytes()
    if r1_export.release_id(pinned_bytes) != fz1["release_id"]:
        sys.exit("refused: the release file is not the pinned release")
    record_bytes = pfd_eval_v2.read_private(root, root / R1_RECORD)
    record = _r1_record(record_bytes)
    if record["pinned_release_id"] != fz1["release_id"]:
        sys.exit("refused: the R1 build record belongs to another pinned release")
    r1_bytes = pfd_eval_v2.read_private(root, root / R1_FILE)
    r1_id = r1_export.release_id(r1_bytes)
    if r1_id != record["r1_release_id"]:
        sys.exit("refused: the R1 file is not the one its build record names")
    if export_v1.check_bytes(r1_bytes):
        sys.exit("refused: the R1 file fails the importer's rules")
    unresolved_bytes = pfd_eval_v2.read_private(root, root / R1_UNRESOLVED)
    excl_bytes = pfd_eval_v2.read_private(root, root / pfd_eval_v2.EXCLUSIONS)
    if formats.sha256(unresolved_bytes) != record["unresolved_sha256"] \
            or formats.sha256(excl_bytes) != record["exclusions_sha256"]:
        sys.exit("refused: the unresolved or exclusion list differs from the one R1 was built with")
    unresolved = r1_export.parse_unresolved(unresolved_bytes)
    excl = exclusions.parse(excl_bytes)
    if unresolved["release_id"] != fz1["release_id"] or excl["release_id"] != fz1["release_id"]:
        sys.exit("refused: the unresolved or exclusion list belongs to another release")
    r1 = json.loads(r1_bytes.decode("utf-8"))
    companion_bytes = pfd_eval_v2.read_private(root, check_output(Path(a.companion)))
    companion = r2_export.parse_companion(companion_bytes, {c["source"] for c in r1["generic_corpora"]})
    if companion["r1_release_id"] != r1_id:
        sys.exit("refused: the companion names another R1 release")
    inventory = formats_v2.parse_inventory((REPO / freeze_v2.INVENTORY).read_bytes())  # hash checked above
    groups = {k: g for g, keys in inventory["groups"].items() for k in keys}
    listed = {}
    for v in excl["withhold_values"] + unresolved["withhold_values"]:
        listed.setdefault(v["entry_id"], set()).add(v["nutrient"])
    pinned = json.loads(pinned_bytes.decode("utf-8"))
    # R1 must be the derivation of the pinned release under the recorded lists and switches, not only
    # a file whose build record names it.
    switches = record.get("switches")
    if not isinstance(switches, dict) or set(switches) != {"a1", "a2"}:
        sys.exit("refused: the R1 build record has no valid switches")
    expected_r1, _ = r1_export.derive(pinned, excl, unresolved, switches, set(inventory["group_of"]))
    if r1_export.dumps(expected_r1) != r1_bytes:
        sys.exit("refused: the R1 file is not the drops-only export of the pinned release under its build record")
    doc, counts = r2_export.derive(r1, pinned, companion, listed, excl["withhold_entries"], groups)
    data = r2_export.dumps(doc)
    written = json.loads(data.decode("utf-8"))  # the proofs run on the bytes that will be written
    rows = r2_export.admitted(r1, pinned, companion, listed, excl["withhold_entries"])
    errs = r2_export.check_additive(r1, written) + r2_export.check_admitted(written, rows) \
        + estimates_v1.check_bytes(data)
    if errs:
        codes = ", ".join(sorted({e.split(":")[0] for e in errs}))  # rule codes only, never IDs
        sys.exit(f"refused: R2 fails {len(errs)} checks ({codes}); nothing written")
    r2_id = r2_export.release_id(data)
    out = json.dumps({"schema": "pfd-r2-build-v1", "pinned_release_id": fz1["release_id"],
                      "r1_release_id": r1_id, "r2_release_id": r2_id,
                      "companion_sha256": formats.sha256(companion_bytes),
                      "r1_build_record_sha256": formats.sha256(record_bytes)},
                     sort_keys=True, separators=(",", ":")).encode() + b"\n"
    folder_name = release_dir(r2_id, formats.sha256(companion_bytes))
    for folder in (root / OUT_DIR, root / folder_name):
        if folder.is_symlink() or (folder.exists() and not folder.is_dir()):
            sys.exit("refused: the R2 output folder is a link or not a folder; nothing written")
    (root / OUT_DIR).mkdir(mode=0o700, exist_ok=True)
    _write_once([(pfd_eval_v2.private(root, root / folder_name / R2_NAME), data),
                 (pfd_eval_v2.private(root, root / folder_name / RECORD_NAME), out)])
    print("R2 built: " + "; ".join(f"{k} {v}" for k, v in counts.items()))
    print(f"R1 release {r1_id}")
    print(f"R2 release {r2_id}")


def main(argv=None):
    p = argparse.ArgumentParser(prog="pfd_r2.py", description="R2, R1 plus approved estimates (counts only).")
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("build-r2")
    sp.add_argument("--root", required=True)
    sp.add_argument("--release", required=True)
    sp.add_argument("--companion", required=True)
    a = p.parse_args(argv)
    root = check(Path(a.root))
    try:
        cmd_build_r2(a, root)
    except (r2_export.R2Error, r1_export.R1Error, formats.FormatError, freeze.FreezeError,
            freeze_v2.FreezeError) as e:
        sys.exit(f"refused: {e}")


if __name__ == "__main__":
    main()
