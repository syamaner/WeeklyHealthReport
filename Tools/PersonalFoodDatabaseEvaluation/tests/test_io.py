"""Contract tests for seals, the freeze record, the results writer and the command line (synthetic)."""
import contextlib
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import helpers as H
import formats
import freeze
import pfd_eval
import results
import seals

FIX = Path(__file__).resolve().parent / "fixtures"


class Seals(unittest.TestCase):
    def test_bundle_matches_the_swift_listing_rule(self):
        h, files = seals.bundle_sha256(FIX / "seal-bundle" / "development", "development", ".json")
        self.assertEqual(f"{h} {files}", (FIX / "seal-bundle" / "EXPECTED").read_text().strip())

    def test_order_never_replaced_and_void_on_change(self):
        with H.private_dir() as t:
            root = Path(t)
            for name in ("development", "held-out"):
                (root / name).mkdir()
                (root / name / "query-set.json").write_text("{}")
            with self.assertRaises(seals.SealError):
                seals.seal("seal-heldout", root, "2026-11-08T00:00:00Z")
            seals.seal("seal-dev", root, "2026-11-08T00:00:00Z")
            with self.assertRaises(seals.SealError):
                seals.seal("seal-dev", root, "2026-11-08T00:00:01Z")
            seals.seal("seal-heldout", root, "2026-11-08T00:00:02Z")
            seals.require("seal-heldout", root)
            (root / "held-out" / "query-set.json").write_text("{ }")
            with self.assertRaises(seals.SealError):
                seals.require("seal-heldout", root)
            self.assertEqual(len((root / "seals.txt").read_text().splitlines()), 2)

    def test_seal_file_link_refused(self):
        with H.private_dir() as t, tempfile.TemporaryDirectory() as other:
            root = Path(t)
            (root / "seals.txt").symlink_to(Path(other) / "elsewhere.txt")
            with self.assertRaises(seals.SealError):
                seals.recorded(root)

    def test_damaged_seal_file_refused(self):
        with H.private_dir() as t:
            root = Path(t)
            (root / "seals.txt").write_text("seal-dev broken\n")
            with self.assertRaises(seals.SealError):
                seals.seal("seal-dev", root, "t")

    def test_held_out_scored_once_plus_one_rerun(self):
        with H.private_dir() as t:
            root = Path(t)
            (root / "held-out").mkdir()
            (root / "development").mkdir()
            for d in ("development", "held-out"):
                (root / d / "query-set.json").write_text("{}")
            seals.seal("seal-dev", root, "t0")
            seals.seal("seal-heldout", root, "t0")
            self.assertEqual(seals.log_held_out_run(root, "a" * 64, "t1"), 1)
            self.assertEqual(seals.log_held_out_run(root, "b" * 64, "t2"), 2)
            with self.assertRaises(seals.SealError):
                seals.log_held_out_run(root, "c" * 64, "t3")


class Freeze(unittest.TestCase):
    def test_changed_file_and_missing_entry_fail_closed(self):
        with tempfile.TemporaryDirectory() as t:
            repo = Path(t)
            (repo / "f.py").write_text("x = 1\n")
            doc = {"schema": "pfd-freeze-v1", "files": {"f.py": hashlib.sha256(b"x = 1\n").hexdigest()}}
            (repo / "freeze.json").write_text(json.dumps(doc))
            fz = freeze.load(repo / "freeze.json")
            freeze.check(fz, repo)
            with self.assertRaises(freeze.FreezeError):
                freeze.check(fz, repo, ("release_id",))
            (repo / "f.py").write_text("x = 2\n")
            with self.assertRaises(freeze.FreezeError):
                freeze.check(fz, repo)
            with self.assertRaises(freeze.FreezeError):  # the real tool folder: every scorer file must be listed
                freeze.check({"schema": "pfd-freeze-v1", "files": {}}, H.REPO)
            (repo / "freeze.json").write_text(json.dumps({**doc, "extra": 1}))
            with self.assertRaises(freeze.FreezeError):
                freeze.load(repo / "freeze.json")


class FreezeRecord(unittest.TestCase):
    def test_committed_record_matches_the_repository(self):
        record = H.HERE / "freeze-v1.json"
        if not record.exists():
            self.skipTest("no freeze record yet")
        doc = freeze.load(record)
        freeze.check(doc, H.REPO)
        self.assertIn(".agents/skills/personal-food-catalogue/scripts/workspace_guard.py", doc["files"])


class Results(unittest.TestCase):
    def test_allow_list(self):
        m = {"count": 1, "of": 40, "interval": [0.004, 0.128], "allowed": 4, "passes": True}
        data = results.build("A", H.RELEASE, {"a3_misleading": m, "a1_entries": 58, "a1_skip_limit_exceeded": False})
        self.assertIn(b"pfd-results-v1", data)
        for bad in ({"a3_misleading": {**m, "note": "x"}}, {"title": 1}, {"a1_entries": "Private title"},
                    {"a3_misleading": {**m, "count": 41}}):
            with self.assertRaises(results.ResultsError):
                results.build("A", H.RELEASE, bad)
        with self.assertRaises(results.ResultsError):
            results.build("B", H.RELEASE, {"queries": 3})  # Part B needs a set
        with self.assertRaises(results.ResultsError):
            results.build("A", "pfc:not-a-release", {})


class CommandLine(unittest.TestCase):
    TITLE = "Synthetic Secret Title"
    QUERY = "synthetic secret query"

    def test_isolated_help_from_another_folder(self):
        r = subprocess.run([sys.executable, "-I", str(H.HERE / "pfd_eval.py"), "--help"], capture_output=True, text=True,
                           cwd=tempfile.gettempdir())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("score-a", r.stdout)

    def test_private_root_refusals(self):
        with tempfile.TemporaryDirectory() as t:
            repo = Path(t) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            os.chmod(repo, 0o700)
            shared = Path(t) / "shared"
            shared.mkdir(mode=0o755)
            os.chmod(shared, 0o755)
            for root in (repo, shared):
                r = subprocess.run([sys.executable, "-I", str(H.HERE / "pfd_eval.py"), "seal", "--root", str(root), "seal-dev"],
                                   capture_output=True, text=True)
                self.assertNotEqual(r.returncode, 0)

    def test_corpus_hash_mismatch_refused_and_unpinned_corpus_unread(self):
        with self.assertRaises(formats.FormatError):
            pfd_eval.corpora_records(H.REPO, {"cofid": "0" * 64})
        self.assertEqual(pfd_eval.corpora_records(H.REPO, {}), {"cofid": {}, "usda": {}, "tfda": {}})

    def run_cli(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            try:
                pfd_eval.main(list(argv))
                code = 0
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 1
                print(e.code)
        text = out.getvalue()
        self.assertNotIn(self.TITLE, text)
        self.assertNotIn(self.QUERY, text)
        return code, text

    def test_end_to_end_counts_only(self):
        with H.private_dir() as t, tempfile.TemporaryDirectory() as r:
            root, repo = Path(t), Path(r)
            saved = (pfd_eval.REPO, pfd_eval.FREEZE, pfd_eval.corpora_records)
            try:
                pfd_eval.REPO = repo
                pfd_eval.FREEZE = repo / "freeze-v1.json"
                pfd_eval.corpora_records = lambda _repo, _pins: {"cofid": {f"cofid:synthetic:{n}": ("synthetic", "raw") for n in range(400)}}
                (repo / "frozen.py").write_text("frozen = True\n")
                pop = H.population(a1=4, a2=50, a3=45, a4=25, a5=1)
                pop[0]["title"] = self.TITLE
                export = json.dumps({"schema": "personal-food-catalogue-v1", "items": pop, "generic_corpora": []}).encode()
                rel = formats.release_id(export)
                (root / "export.json").write_bytes(export)
                (root / "counts.json").write_bytes(formats.dumps({"schema": "pfd-purchase-counts-v1", "release_id": rel,
                                                                  "counts": {pop[5]["id"]: 3}}))
                fz = {"schema": "pfd-freeze-v1", "files": {"frozen.py": hashlib.sha256(b"frozen = True\n").hexdigest()},
                      "release_id": rel, "seed": 42}
                pfd_eval.FREEZE.write_text(json.dumps(fz))
                code, text = self.run_cli("sample", "--root", str(root), "--export", str(root / "export.json"),
                                          "--counts", str(root / "counts.json"))
                self.assertEqual(code, 0, text)
                self.assertEqual(self.run_cli("sample", "--root", str(root), "--export", str(root / "export.json"),
                                              "--counts", str(root / "counts.json"))[0] != 0, True)  # never overwritten

                queries = [{"query_id": f"q-{n:04d}", "text": self.QUERY, "negative": n >= 10,
                            "answer": {"kind": "none"} if n >= 10 else {"kind": "entry", "entry_ids": [pop[n]["id"]], "step": 1}}
                           for n in range(14)]
                (root / "query-set.json").write_bytes(formats.dumps({"schema": "pfd-query-set-v1", "release_id": rel,
                                                                     "queries": queries}))
                self.assertEqual(self.run_cli("split", "--root", str(root), "--query-set", str(root / "query-set.json"))[0], 0)
                self.assertEqual(self.run_cli("seal", "--root", str(root), "seal-dev")[0], 0)
                self.assertEqual(self.run_cli("seal", "--root", str(root), "seal-heldout")[0], 0)

                sheet = formats.parse_sheet((root / "review" / "review-sheet.csv").read_bytes())
                sample_doc = formats.parse_sample((root / "sample" / "sample.json").read_bytes())
                for row in sheet:
                    if row["stratum"] in ("A1", "A5"):
                        row["product"] = "right_product"
                        for k in formats.NUTRIENTS:
                            row[k] = "agrees"
                done = {}
                for row in sheet:
                    s = row["stratum"]
                    if s in ("A2", "A3", "A4") and done.get(s, 0) < sample_doc["quotas"][s]:
                        row["verdict"] = {"A2": "same_food_same_state", "A3": "sensible", "A4": "nothing_suitable"}[s]
                        done[s] = done.get(s, 0) + 1
                (root / "review" / "review-sheet.csv").write_bytes(formats.write_sheet(sheet))
                self.assertNotEqual(self.run_cli("score-a", "--root", str(root), "--out", str(repo / "a.json"))[0], 0)  # unsealed, unpinned
                self.assertEqual(self.run_cli("seal", "--root", str(root), "seal-review")[0], 0)
                fz["sample_sha256"] = formats.sha256((root / "sample" / "sample.json").read_bytes())
                fz["purchase_counts_sha256"] = formats.sha256((root / "sample" / "purchase-counts.json").read_bytes())
                fz["heldout_sha256"] = seals.recorded(root)["seal-heldout"]
                pfd_eval.FREEZE.write_text(json.dumps(fz))
                code, text = self.run_cli("score-a", "--root", str(root), "--out", str(repo / "a.json"))
                self.assertEqual(code, 0, text)
                self.assertNotIn(self.TITLE.encode(), (repo / "a.json").read_bytes())
                self.assertNotIn(pop[0]["id"].encode(), (repo / "a.json").read_bytes())

                held = formats.parse_query_set((root / "held-out" / "query-set.json").read_bytes())
                ranking = {"schema": "pfd-ranking-output-v1", "release_id": rel, "set": "held-out",
                           "results": [{"query_id": q["query_id"], "candidates": []} for q in held["queries"]]}
                (root / "ranking.json").write_bytes(formats.dumps(ranking))
                code, text = self.run_cli("score-b", "--root", str(root), "--set", "held-out",
                                          "--ranking", str(root / "ranking.json"), "--out", str(repo / "b.json"))
                self.assertEqual(code, 0, text)
                self.assertNotIn(self.QUERY.encode(), (repo / "b.json").read_bytes())
                self.assertEqual(self.run_cli("score-b", "--root", str(root), "--set", "held-out",
                                              "--ranking", str(root / "ranking.json"))[0], 0)
                self.assertNotEqual(self.run_cli("score-b", "--root", str(root), "--set", "held-out",
                                                 "--ranking", str(root / "ranking.json"))[0], 0)  # third run refused
                (repo / "frozen.py").write_text("frozen = False\n")
                self.assertNotEqual(self.run_cli("score-a", "--root", str(root), "--out", str(repo / "c.json"))[0], 0)
            finally:
                pfd_eval.REPO, pfd_eval.FREEZE, pfd_eval.corpora_records = saved


if __name__ == "__main__":
    unittest.main()
