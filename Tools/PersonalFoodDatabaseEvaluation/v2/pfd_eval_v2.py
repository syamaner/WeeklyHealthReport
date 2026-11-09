#!/usr/bin/env python3
"""Command line for the Part A best-estimate review, v2 (docs/personal-food-database-review-v2-design.md).

The only v2 entry point; `pfd_eval.py` is untouched and still runs every v1 and Part B command.
Only this file touches files and the clock. Every private path is refused inside a git working tree
or outside a private folder (the skill's workspace_guard, imported as pfd_eval.py imports it). Every
command checks freeze-v1.json and freeze-v2.json and the bars lock. The console shows counts only;
the one repository output is a pfd-results-v2 file.

    pfd_eval_v2.py review-sheet-v2 --root DIR
    pfd_eval_v2.py seal            --root DIR seal-review-v2
    pfd_eval_v2.py score-a-v2      --root DIR --out RESULTS.json
"""
import argparse
import datetime
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent
REPO = TOOL.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(1, str(TOOL))
sys.path.insert(2, str(REPO / ".agents" / "skills" / "personal-food-catalogue" / "scripts"))

import bars_v2  # noqa: E402
import exclusions  # noqa: E402
import formats  # noqa: E402
import formats_v2  # noqa: E402
import freeze  # noqa: E402
import freeze_v2  # noqa: E402
import results_v2  # noqa: E402
import score_a_v2  # noqa: E402
import seals  # noqa: E402
import seals_v2  # noqa: E402
from pfd_eval import write_all  # noqa: E402  (the v1 all-or-nothing writer, unchanged)
from workspace_guard import check, check_output  # noqa: E402

FREEZE_V1 = TOOL / "freeze-v1.json"
FREEZE_V2 = TOOL / "freeze-v2.json"
EXCLUSIONS = Path("exclusions-v2") / "exclusions.json"


def now_utc() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def private(root: Path, path) -> Path:
    p = check_output(path)
    if root not in p.parents and p != root:
        sys.exit("refused: every private file must be inside the evaluation folder")
    return p


def read_private(root, path) -> bytes:
    p = private(root, path)
    if p.is_symlink() or not p.is_file():
        sys.exit("refused: a named private file does not exist or is a link")
    return p.read_bytes()


def repo_out(path) -> Path:
    p = Path(path).resolve()
    if REPO.resolve() not in p.parents or p.suffix != ".json":
        sys.exit("refused: results go to a .json file inside this repository")
    return p


def frozen(root: Path, needs=()):
    """Both freeze records and the bars lock; returns (v1 record, v2 record, SHA-256 of freeze-v2.json)."""
    fz1 = freeze.check(freeze.load(FREEZE_V1), REPO, needs)
    if FREEZE_V2.is_symlink() or not FREEZE_V2.is_file():
        raise freeze_v2.FreezeError("freeze-v2 record not found")
    raw = FREEZE_V2.read_bytes()
    fz2 = freeze_v2.check(freeze_v2.parse(raw), REPO, FREEZE_V1)
    seals_v2.check_bars(root, fz2.get("part_a_bars"))
    return fz1, fz2, freeze_v2.sha256(raw)


def pinned_sample(root: Path, fz1: dict) -> dict:
    data = read_private(root, root / "sample" / "sample.json")
    if formats.sha256(data) != fz1["sample_sha256"]:
        sys.exit("refused: the sample differs from the freeze record")
    s = formats.parse_sample(data)
    if s["release_id"] != fz1["release_id"]:
        sys.exit("refused: the sample belongs to another release")
    return s


def bundle(root: Path, fz1: dict):
    sample = pinned_sample(root, fz1)
    inventory = formats_v2.parse_inventory((REPO / freeze_v2.INVENTORY).read_bytes())  # hash checked by frozen()
    folder = root / seals_v2.FOLDER
    rows = formats_v2.parse_sheet(read_private(root, folder / seals_v2.SHEET))
    records = formats_v2.parse_evidence(read_private(root, folder / seals_v2.EVIDENCE), inventory)
    score_a_v2.validate(sample, rows, records, inventory)
    return sample, rows, records, inventory


def cmd_review_sheet_v2(a, root):
    fz1, _, _ = frozen(root, ("release_id", "sample_sha256"))
    rows = formats_v2.sheet_template(pinned_sample(root, fz1))
    out = private(root, root / seals_v2.FOLDER / seals_v2.SHEET)
    write_all([(out, formats_v2.write_sheet(rows))])
    print(f"review sheet v2 written: {len(rows)} rows; fill every cell and add {seals_v2.EVIDENCE}, then seal")


def cmd_seal(a, root):
    fz1, _, _ = frozen(root, ("release_id", "sample_sha256"))
    before, _ = seals_v2.bundle_sha256(root)
    bundle(root, fz1)  # a bundle that could never be scored is refused before an irreversible seal
    h = seals_v2.seal_review(root, now_utc(), expected_sha256=before)
    print(f"{a.name} recorded: {h}")


def cmd_score_a_v2(a, root):
    fz1, fz2, fz2_sha = frozen(root, ("release_id", "sample_sha256", "purchase_counts_sha256"))
    bar_set = fz2.get("part_a_bars")
    if bar_set is None:
        sys.exit("refused: freeze-v2.json has no part_a_bars; the owner records the bars before any v2 scoring, "
                 "and nothing was written")
    if formats.sha256(read_private(root, root / "sample" / "purchase-counts.json")) != fz1["purchase_counts_sha256"]:
        sys.exit("refused: the purchase counts differ from the freeze record")
    seals_v2.require_review(root)
    sample, rows, records, inventory = bundle(root, fz1)
    measures = score_a_v2.score(sample, rows, records, inventory, bar_set)
    result = results_v2.build(fz1["release_id"], bar_set, measures)
    excluded = exclusions.build(fz1["release_id"], score_a_v2.exclusion_list(sample, rows, records, inventory))
    out = repo_out(a.out)
    ex_path = private(root, root / EXCLUSIONS)

    def write():
        items = [(out, result)]
        if ex_path.exists() or ex_path.is_symlink():
            if ex_path.is_symlink() or not ex_path.is_file() or ex_path.read_bytes() != excluded:
                sys.exit("refused: an exclusion list already exists and differs; it is never overwritten")
        else:
            items.append((ex_path, excluded))
        write_all(items)
        return [p for p, _ in items]

    first = seals_v2.score_locked(root, bar_set, fz2_sha, now_utc(), write)
    print(f"Part A v2 scored under {bar_set}{' (bars now locked)' if first else ''}:", summary(measures))


def summary(measures: dict) -> str:
    parts = []
    for k, v in sorted(measures.items()):
        if isinstance(v, dict):
            verdict = ""
            if "passes" in v:
                verdict = {True: "pass", False: "fail"}.get(v["passes"]) or ("not final" if v["of"] else "not assessed")
            parts.append(f"{k} {v['count']}/{v['of']}{' ' + verdict if verdict else ''}")
        elif k.endswith("_not_assessable") and v:
            parts.append(k)
    return "; ".join(parts)


def main(argv=None):
    p = argparse.ArgumentParser(prog="pfd_eval_v2.py", description="Part A best-estimate review, v2 (counts only).")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("review-sheet-v2", "seal", "score-a-v2"):
        sp = sub.add_parser(name)
        sp.add_argument("--root", required=True)
        if name == "seal":
            sp.add_argument("name", choices=(seals_v2.REVIEW,))
        if name == "score-a-v2":
            sp.add_argument("--out", required=True)
    a = p.parse_args(argv)
    root = check(Path(a.root))
    try:
        {"review-sheet-v2": cmd_review_sheet_v2, "seal": cmd_seal, "score-a-v2": cmd_score_a_v2}[a.cmd](a, root)
    except (formats.FormatError, freeze.FreezeError, freeze_v2.FreezeError, seals.SealError, seals_v2.SealError,
            results_v2.ResultsError, bars_v2.BarsError) as e:
        sys.exit(f"refused: {e}")


if __name__ == "__main__":
    main()
