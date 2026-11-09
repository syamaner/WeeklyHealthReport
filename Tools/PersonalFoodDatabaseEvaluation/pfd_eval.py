#!/usr/bin/env python3
"""Command line for the personal food database evaluation (plan docs/personal-food-database-evaluation-v1.md).

Only this file touches files, the clock and randomness. Every private path is refused inside a git
working tree or outside a private folder (the skill's workspace_guard). The console shows counts
only, except `lookup`, which is for the owner's own screen; the one repository output is a
pfd-results-v1 file.

    pfd_eval.py draw-seed
    pfd_eval.py query-template   --root DIR
    pfd_eval.py assemble-queries --root DIR --export FILE
    pfd_eval.py lookup           --root DIR --export FILE [--generic] WORDS...   (owner only)
    pfd_eval.py sample   --root DIR --export FILE --counts FILE
    pfd_eval.py split    --root DIR --query-set FILE
    pfd_eval.py seal     --root DIR NAME            (seal-dev, seal-heldout, seal-review)
    pfd_eval.py score-a  --root DIR --out RESULTS.json
    pfd_eval.py score-b  --root DIR --set development|held-out --ranking FILE [--out RESULTS.json]
"""
import argparse
import datetime
import json
import os
import secrets
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(1, str(REPO / ".agents" / "skills" / "personal-food-catalogue" / "scripts"))

import formats  # noqa: E402
import queries  # noqa: E402
import freeze  # noqa: E402
import results  # noqa: E402
import sample as sample_mod  # noqa: E402
import score_a  # noqa: E402
import score_b  # noqa: E402
import seals  # noqa: E402
import split as split_mod  # noqa: E402
from workspace_guard import check, check_output  # noqa: E402

FREEZE = HERE / "freeze-v1.json"
CORPORA = {"cofid": "cofid-2021-generic-search-v1.json", "usda": "usda-generic-v1.json", "tfda": "tfda-generic-v1.json"}


def now_utc() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def private(root: Path, path) -> Path:
    p = check_output(path)
    if root not in p.parents and p != root:
        sys.exit("refused: every private file must be inside the evaluation folder")
    return p


def read_private(root, path) -> bytes:
    p = private(root, path)
    if not p.is_file():
        sys.exit("refused: a named private file does not exist")
    return p.read_bytes()


def write_new(path: Path, data: bytes):
    write_all([(path, data)])


def write_all(items):
    """Write every file or none.

    All destinations are checked first. Each file goes to a new, randomly named temporary file created
    exclusively (so a planted link is never followed); only when every temporary file is complete are
    they moved into place. Any failure removes the temporary files and every destination already
    moved, so a failed run leaves nothing behind and can be run again.
    """
    if any(p.exists() or p.is_symlink() for p, _ in items):
        sys.exit("refused: an evaluation file already exists and is never overwritten")
    temps, done = [], []
    try:
        for p, data in items:
            p.parent.mkdir(parents=True, exist_ok=True)
            fd, name = tempfile.mkstemp(dir=p.parent, prefix="." + p.name + ".", suffix=".partial")
            temps.append(Path(name))
            with os.fdopen(fd, "wb") as fh:
                fh.write(data)
        for (p, _), tmp in zip(items, temps):
            if p.exists() or p.is_symlink():
                raise FileExistsError("an evaluation file appeared during the write")
            os.replace(tmp, p)
            done.append(p)
    except BaseException:
        for p in temps + done:
            try:
                p.unlink()
            except FileNotFoundError:
                pass
        raise


def corpora_records(repo: Path, pins: dict) -> dict:
    """Generic records by the record IDs the import file uses, from the bundled corpora."""
    res = repo / "Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources"
    out = {}
    for src, name in CORPORA.items():
        if src not in pins:
            out[src] = {}  # an unpinned corpus is never read; a reference to it is refused when the sheet is built
            continue
        data = (res / name).read_bytes()
        if pins[src] != formats.sha256(data):
            raise formats.FormatError(f"{src}: the import file was built against a different bundled corpus")
        recs = json.loads(data)["records"]
        if src == "cofid":
            out[src] = {r["record_id"]: (r["name"], (r.get("identity") or {}).get("preparation", "unknown")) for r in recs}
        elif src == "usda":
            out[src] = {r["id"]: (r["name"], r.get("preparation") or "unknown") for r in recs}
        else:
            out[src] = {"tfda:" + r["id"]: (r.get("sourceEnglish") or r["name"], r.get("preparation") or "unknown") for r in recs}
    return out


def frozen(needs=()):
    return freeze.check(freeze.load(FREEZE), REPO, needs)


def cmd_draw_seed(_):
    print(secrets.randbelow(2 ** 31))


def cmd_sample(a, root):
    fz = frozen(("release_id", "seed"))
    export = read_private(root, a.export)
    if formats.release_id(export) != fz["release_id"]:
        sys.exit("refused: the import file is not the pinned release")
    counts_bytes = read_private(root, a.counts)
    counts = formats.parse_purchase_counts(counts_bytes)
    if counts["release_id"] != fz["release_id"]:
        sys.exit("refused: the purchase counts belong to another release")
    entries, pins = formats.export_entries(export)
    s = sample_mod.draw(entries, counts["counts"], fz["seed"])
    doc = {"schema": "pfd-sample-v1", "release_id": fz["release_id"], **s}
    rows = sample_mod.sheet_rows(doc, entries, corpora_records(REPO, pins))
    write_all([(private(root, root / "sample" / "sample.json"), formats.dumps(doc)),
               (private(root, root / "review" / "review-sheet.csv"), formats.write_sheet(rows)),
               (private(root, root / "sample" / "purchase-counts.json"), counts_bytes)])  # the copy the freeze pins
    print("sample written:", ", ".join(f"{k} {v}" for k, v in sorted(s["quotas"].items())), f"; sheet rows {len(rows)}")


def pinned_export(a, root):
    fz = frozen(("release_id",))
    export = read_private(root, a.export)
    if formats.release_id(export) != fz["release_id"]:
        sys.exit("refused: the import file is not the pinned release")
    entries, pins = formats.export_entries(export)
    return fz, entries, corpora_records(REPO, pins), pins


def generic_aliases(repo: Path, pins: dict) -> dict:
    """The search aliases the bundled corpora carry (only TFDA has them), for the owner's lookup only.
    Read after corpora_records has checked each pinned corpus against its pin."""
    if "tfda" not in pins:
        return {}
    recs = json.loads((repo / "Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources" / CORPORA["tfda"]).read_bytes())
    return {"tfda": {"tfda:" + r["id"]: [a for a in r.get("aliases") or [] if isinstance(a, str)] for r in recs["records"]}}


def cmd_query_template(a, root):
    out = private(root, root / "queries" / "query-template.csv")
    write_new(out, queries.template())
    print("template written to queries/query-template.csv; fill it in, then run assemble-queries")


def cmd_assemble_queries(a, root):
    fz, entries, corpora, _ = pinned_export(a, root)
    doc = queries.assemble(read_private(root, root / "queries" / "query-template.csv"), fz["release_id"],
                           {e["id"] for e in entries}, {src: set(recs) for src, recs in corpora.items()})
    write_new(private(root, root / "queries" / "query-set.json"), formats.dumps(doc))
    print("query set written:", ", ".join(f"{k} {v}" for k, v in queries.counts(doc).items()))


def interactive() -> bool:
    return sys.stdin.isatty() and sys.stdout.isatty()


def cmd_lookup(a, root):
    """Owner only: prints catalogue rows to this screen and writes nothing.

    This is a guard against an accidental run by an agent's non-interactive shell, not authentication:
    on the owner's own account nothing in code can tell the owner from a process acting for them."""
    if not interactive():
        sys.exit("refused: lookup prints catalogue rows, so it runs only in the owner's interactive terminal")
    _, entries, corpora, pins = pinned_export(a, root)
    text = " ".join(a.words)
    if a.generic:
        rows, total = queries.lookup_generic(corpora, text, generic_aliases(REPO, pins))
        for ref, name, prep in rows:
            print(f"{ref}\t{name} ({prep})")
    else:
        rows, total = queries.lookup_entries(entries, text)
        for eid, brand, title, matched in rows:
            print(f"{eid}\t{brand + ' ' if brand else ''}{title}\tmatched: {', '.join(matched)}")
    print(f"{total} match{'es' if total != 1 else ''}" + (f", first {len(rows)} shown; add a word to narrow" if total > len(rows) else ""))


def cmd_split(a, root):
    fz = frozen(("release_id", "seed"))
    qs = formats.parse_query_set(read_private(root, a.query_set))
    if qs["release_id"] != fz["release_id"] or "set" in qs:
        sys.exit("refused: the query set must be the unsplit set for the pinned release")
    out = split_mod.split(qs, fz["seed"])
    write_all([(private(root, root / name / "query-set.json"), formats.dumps(doc)) for name, doc in out.items()])
    print("split written:", ", ".join(f"{k} {len(v['queries'])} ({sum(q['negative'] for q in v['queries'])} negative)"
                                      for k, v in out.items()))


def cmd_seal(a, root):
    h = seals.seal(a.name, root, now_utc())
    print(f"{a.name} recorded: {h}")


def repo_out(path) -> Path:
    p = Path(path).resolve()
    if REPO.resolve() not in p.parents or p.suffix != ".json":
        sys.exit("refused: results go to a .json file inside this repository")
    return p


def cmd_score_a(a, root):
    fz = frozen(("release_id", "sample_sha256", "purchase_counts_sha256"))
    sample_bytes = read_private(root, root / "sample" / "sample.json")
    if formats.sha256(sample_bytes) != fz["sample_sha256"]:
        sys.exit("refused: the sample differs from the freeze record")
    if formats.sha256(read_private(root, root / "sample" / "purchase-counts.json")) != fz["purchase_counts_sha256"]:
        sys.exit("refused: the purchase counts differ from the freeze record")
    seals.require("seal-review", root)
    sample = formats.parse_sample(sample_bytes)
    if sample["release_id"] != fz["release_id"]:
        sys.exit("refused: the sample belongs to another release")
    rows = formats.parse_sheet(read_private(root, root / "review" / "review-sheet.csv"))
    measures = score_a.score(sample, rows)
    out = repo_out(a.out)
    write_new(out, results.build("A", fz["release_id"], measures))
    print("Part A scored:", summary(measures))


def cmd_score_b(a, root):
    fz = frozen(("release_id", "heldout_sha256") if a.set == "held-out" else ("release_id",))
    seal_name = "seal-heldout" if a.set == "held-out" else "seal-dev"
    sealed = seals.require(seal_name, root)
    if a.set == "held-out" and sealed != fz["heldout_sha256"]:
        sys.exit("refused: the held-out seal differs from the freeze record")
    qs = formats.parse_query_set(read_private(root, root / a.set / "query-set.json"))
    ranking_bytes = read_private(root, a.ranking)
    ranking = formats.parse_ranking(ranking_bytes)
    if ranking["set"] != a.set or qs["release_id"] != fz["release_id"]:
        sys.exit("refused: the ranking output or query set is for another set or release")
    measures = score_b.score(qs, ranking)
    if a.set == "held-out":
        if not a.out:
            sys.exit("refused: a held-out run needs --out, so every run leaves its result")
        out = repo_out(a.out)
        if out.exists() or out.is_symlink():
            sys.exit("refused: an evaluation file already exists and is never overwritten")
        # Plan 4.3: every result states the owner's openings of per-query development output.
        log = root / "exposures.txt"
        if log.is_symlink() or (log.exists() and not log.is_file()):
            sys.exit("refused: exposures.txt must be a plain file inside the evaluation folder")
        measures["owner_development_output_openings"] = len(
            [l for l in log.read_text(encoding="utf-8").splitlines() if l.strip()]) if log.exists() else 0

        def write(n):
            measures["held_out_run"] = n
            write_new(out, results.build("B", fz["release_id"], measures, "held-out"))
            return out

        n = seals.log_held_out_run(root, formats.sha256(ranking_bytes), now_utc(), write)
        print(f"held-out run {n} of {seals.HELD_OUT_RUN_LIMIT} recorded")
    elif a.out:
        sys.exit("refused: development results are never repository evidence")
    print(f"Part B {a.set} scored:", summary(measures))


def summary(measures: dict) -> str:
    parts = []
    for k, v in sorted(measures.items()):
        if isinstance(v, dict):
            verdict = {True: "pass", False: "fail", None: "not assessed"}.get(v.get("passes"), "") if "passes" in v else ""
            parts.append(f"{k} {v['count']}/{v['of']}{' ' + verdict if verdict else ''}")
    return "; ".join(parts)


def main(argv=None):
    p = argparse.ArgumentParser(prog="pfd_eval.py", description="Personal food database evaluation (counts only).")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("draw-seed")
    for name in ("query-template", "assemble-queries", "lookup", "sample", "split", "seal", "score-a", "score-b"):
        sp = sub.add_parser(name)
        sp.add_argument("--root", required=True)
        if name == "sample":
            sp.add_argument("--export", required=True)
            sp.add_argument("--counts", required=True)
        if name in ("assemble-queries", "lookup"):
            sp.add_argument("--export", required=True)
        if name == "lookup":
            sp.add_argument("--generic", action="store_true", help="search the pinned generic records instead")
            sp.add_argument("words", nargs="+")
        if name == "split":
            sp.add_argument("--query-set", required=True)
        if name == "seal":
            sp.add_argument("name", choices=seals.ORDER)
        if name == "score-a":
            sp.add_argument("--out", required=True)
        if name == "score-b":
            sp.add_argument("--set", required=True, choices=sorted(formats.SETS))
            sp.add_argument("--ranking", required=True)
            sp.add_argument("--out")
    a = p.parse_args(argv)
    if a.cmd == "draw-seed":
        return cmd_draw_seed(a)
    root = check(Path(a.root))
    try:
        {"query-template": cmd_query_template, "assemble-queries": cmd_assemble_queries, "lookup": cmd_lookup,
         "sample": cmd_sample, "split": cmd_split, "seal": cmd_seal, "score-a": cmd_score_a, "score-b": cmd_score_b}[a.cmd](a, root)
    except (formats.FormatError, queries.QueryTemplateError, freeze.FreezeError, seals.SealError, results.ResultsError) as e:
        sys.exit(f"refused: {e}")


if __name__ == "__main__":
    main()
