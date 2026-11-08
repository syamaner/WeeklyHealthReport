"""Contract tests for the v2 freeze record, v2 seals and the v2 command line (synthetic only).

Design: docs/personal-food-database-review-v2-design.md, section 7.
"""
import contextlib
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import helpers as H

sys.path.insert(0, str(H.HERE / "v2"))

import exclusions  # noqa: E402
import formats  # noqa: E402
import formats_v2 as F2  # noqa: E402
import freeze  # noqa: E402
import freeze_v2  # noqa: E402
import pfd_eval_v2  # noqa: E402
import results_v2  # noqa: E402
import sample as sample_mod  # noqa: E402
import seals  # noqa: E402
import seals_v2  # noqa: E402
from test_v2_pure import INVENTORY_BYTES, make_records, make_rows, row_of  # noqa: E402

FREEZE_V1 = H.HERE / "freeze-v1.json"
FREEZE_V2 = H.HERE / "freeze-v2.json"
T = "2026-11-08T00:00:00Z"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def v1_seals(root: Path, names=("seal-dev", "seal-heldout")):
    for folder in ("development", "held-out"):
        (root / folder).mkdir(exist_ok=True)
        (root / folder / "query-set.json").write_text("{}")
    for name in names:
        seals.seal(name, root, T)


def review_files(root: Path, sheet=b"sheet\n", evidence=b"evidence\n"):
    (root / "review-v2").mkdir(exist_ok=True)
    (root / "review-v2" / seals_v2.SHEET).write_bytes(sheet)
    (root / "review-v2" / seals_v2.EVIDENCE).write_bytes(evidence)


class FreezeV2(unittest.TestCase):
    def test_committed_records_match_the_repository(self):
        doc = freeze_v2.load(FREEZE_V2)
        freeze_v2.check(doc, H.REPO, FREEZE_V1)
        self.assertEqual(doc["part_a_bars"], "v2_proposed")
        self.assertEqual(doc["freeze_v1_sha256"], freeze_v2.v1_pin(FREEZE_V1.read_bytes()))
        listed = {f"{freeze_v2.TOOL}/v2/{p.name}" for p in (H.HERE / "v2").glob("*.py")} | {freeze_v2.INVENTORY}
        self.assertEqual(set(doc["files"]), listed)
        freeze.check(freeze.load(FREEZE_V1), H.REPO)  # every v1 hash still matches beside the v2 files

    def test_records_round_trip_with_and_without_bars(self):
        raw = FREEZE_V1.read_bytes()
        self.assertEqual(formats.dumps(json.loads(raw)), raw)
        doc = freeze_v2.parse(FREEZE_V2.read_bytes())
        self.assertEqual(freeze_v2.dumps_record(doc), FREEZE_V2.read_bytes())
        without = {k: v for k, v in doc.items() if k != "part_a_bars"}
        data = freeze_v2.dumps_record(without)
        self.assertNotIn("part_a_bars", freeze_v2.parse(data))
        self.assertEqual(freeze_v2.dumps_record(freeze_v2.parse(data)), data)

    def test_mismatches_and_unknown_values_fail_closed(self):
        with tempfile.TemporaryDirectory() as t:
            repo = Path(t)
            inv = repo / freeze_v2.INVENTORY
            inv.parent.mkdir(parents=True)
            inv.write_bytes(INVENTORY_BYTES)
            v1 = repo / "freeze-v1.json"
            v1.write_bytes(b"{}\n")
            doc = {"schema": "pfd-freeze-v2", "files": {freeze_v2.INVENTORY: sha(INVENTORY_BYTES)},
                   "freeze_v1_sha256": freeze_v2.v1_pin(b"{}\n"), "part_a_bars": "v2_proposed"}
            freeze_v2.check(freeze_v2.parse(formats.dumps(doc)), repo, v1)
            v1.write_bytes(b'{"heldout_sha256": "' + b"0" * 64 + b'"}\n')  # filled in later by the plan
            freeze_v2.check(freeze_v2.parse(formats.dumps(doc)), repo, v1)
            v1.write_bytes(b'{"seed": 1}\n')  # any other v1 change stops v2
            with self.assertRaises(freeze_v2.FreezeError):
                freeze_v2.check(freeze_v2.parse(formats.dumps(doc)), repo, v1)
            v1.write_bytes(b"{}\n")
            for bad in ({**doc, "part_a_bars": "v3"}, {**doc, "part_a_bars": None},
                        {**doc, "part_a_bars": ["v2_proposed"]}, {**doc, "part_a_bars": {}}, {**doc, "extra": 1},
                        {**doc, "schema": "pfd-freeze-v1"}, {**doc, "freeze_v1_sha256": "x"},
                        {k: v for k, v in doc.items() if k != "freeze_v1_sha256"}, {**doc, "files": {}}):
                with self.assertRaises(freeze_v2.FreezeError):
                    freeze_v2.parse(formats.dumps(bad))
            with self.assertRaises(freeze_v2.FreezeError):
                freeze_v2.check({**doc, "freeze_v1_sha256": "0" * 64}, repo, v1)
            with self.assertRaises(freeze_v2.FreezeError):
                freeze_v2.check({**doc, "files": {"other.py": sha(b"")}}, repo, v1)  # the inventory must be listed
            inv.write_bytes(INVENTORY_BYTES + b" ")
            with self.assertRaises(freeze_v2.FreezeError):
                freeze_v2.check(doc, repo, v1)

    def test_every_v2_module_must_be_listed(self):
        with self.assertRaises(freeze_v2.FreezeError) as e:
            freeze_v2.check({"schema": "pfd-freeze-v2", "files": {freeze_v2.INVENTORY: sha(INVENTORY_BYTES)},
                             "freeze_v1_sha256": freeze_v2.v1_pin(FREEZE_V1.read_bytes())}, H.REPO, FREEZE_V1)
        self.assertIn("does not list v2 file", str(e.exception))


class SealsV2(unittest.TestCase):
    def test_written_only_to_seals_v2_and_v1_reads_unchanged(self):
        with H.private_dir() as t:
            root = Path(t)
            v1_seals(root)
            review_files(root)
            before, have = (root / "seals.txt").read_bytes(), seals.recorded(root)
            h = seals_v2.seal_review(root, T)
            self.assertEqual((root / "seals.txt").read_bytes(), before)
            self.assertEqual(seals.recorded(root), have)
            self.assertEqual((root / "seals-v2.txt").read_text(), f"seal-review-v2 {h} 2 {T}\n")
            self.assertEqual(seals_v2.require_review(root), h)
            with self.assertRaises(seals_v2.SealError):
                seals_v2.seal_review(root, T)  # never replaced

    def test_a_bundle_changed_after_validation_is_not_sealed(self):
        with H.private_dir() as t:
            root = Path(t)
            v1_seals(root)
            review_files(root)
            with self.assertRaises(seals_v2.SealError):
                seals_v2.seal_review(root, T, expected_sha256="0" * 64)
            self.assertNotIn(seals_v2.REVIEW, seals_v2.recorded(root))
            h, _ = seals_v2.bundle_sha256(root)
            self.assertEqual(seals_v2.seal_review(root, T, expected_sha256=h), h)
            (root / "review-v2" / seals_v2.SHEET).write_bytes(b"changed\n")
            with self.assertRaises(seals_v2.SealError):
                seals_v2.require_review(root)

    def test_bundle_uses_the_v1_listing_rule(self):
        with H.private_dir() as t:
            root = Path(t)
            review_files(root)
            self.assertEqual(seals_v2.bundle_sha256(root), seals.bundle_sha256(root / "review-v2", "review-v2", ""))

    def test_needs_dev_and_heldout_and_refuses_after_a_v1_review_seal(self):
        for names in ((), ("seal-dev",)):
            with H.private_dir() as t:
                root = Path(t)
                v1_seals(root, names)
                review_files(root)
                with self.assertRaises(seals_v2.SealError):
                    seals_v2.seal_review(root, T)
                self.assertFalse((root / "seals-v2.txt").exists())
        with H.private_dir() as t:
            root = Path(t)
            v1_seals(root)
            (root / "review").mkdir()
            (root / "review" / "review-sheet.csv").write_text("v1\n")
            seals.seal("seal-review", root, T)
            review_files(root)
            with self.assertRaises(seals_v2.SealError) as e:
                seals_v2.seal_review(root, T)
            self.assertIn("v1 seal-review", str(e.exception))

    def test_exactly_the_two_files_and_no_links(self):
        def third(root):
            (root / "review-v2" / "notes.txt").write_text("x")

        def folder(root):
            (root / "review-v2" / "sub").mkdir()

        def missing(root):
            (root / "review-v2" / seals_v2.EVIDENCE).unlink()

        def member_link(root):
            (root / "review-v2" / seals_v2.EVIDENCE).unlink()
            os.symlink(root / "elsewhere.jsonl", root / "review-v2" / seals_v2.EVIDENCE)
            (root / "elsewhere.jsonl").write_text("x")

        def folder_link(root):
            os.rename(root / "review-v2", root / "real")
            os.symlink(root / "real", root / "review-v2")

        for change in (third, folder, missing, member_link, folder_link):
            with self.subTest(change=change.__name__), H.private_dir() as t:
                root = Path(t)
                v1_seals(root)
                review_files(root)
                change(root)
                with self.assertRaises(seals_v2.SealError):
                    seals_v2.seal_review(root, T)

    def test_bars_lock(self):
        with H.private_dir() as t:
            root = Path(t)
            v1_seals(root)
            review_files(root)
            with self.assertRaises(seals_v2.SealError):
                seals_v2.score_locked(root, "v2_proposed", "a" * 64, T, lambda: [])  # not sealed
            seals_v2.seal_review(root, T)
            seals_v2.check_bars(root, None)  # nothing locked yet
            self.assertTrue(seals_v2.score_locked(root, "v2_proposed", "a" * 64, T, lambda: []))
            self.assertEqual((root / "seals-v2.txt").read_text().splitlines()[1], f"score-a-v2 {'a' * 64} v2_proposed {T}")
            seals_v2.check_bars(root, "v2_proposed")
            for other in ("v1_accepted", None):
                with self.assertRaises(seals_v2.SealError):
                    seals_v2.check_bars(root, other)
            with self.assertRaises(seals_v2.SealError):
                seals_v2.score_locked(root, "v1_accepted", "b" * 64, T, lambda: [])
            with self.assertRaises(seals_v2.SealError):  # a rerun under different scoring code
                seals_v2.score_locked(root, "v2_proposed", "b" * 64, T, lambda: [])
            self.assertFalse(seals_v2.score_locked(root, "v2_proposed", "a" * 64, T, lambda: []))
            self.assertEqual(len((root / "seals-v2.txt").read_text().splitlines()), 2)

    def test_lock_is_recorded_before_any_count(self):
        with H.private_dir() as t:
            root = Path(t)
            v1_seals(root)
            review_files(root)
            seals_v2.seal_review(root, T)
            seen = []

            def write():
                seen.append(seals_v2.LOCK in seals_v2.recorded(root))
                raise KeyboardInterrupt  # interrupted while writing counts
            with self.assertRaises(KeyboardInterrupt):
                seals_v2.score_locked(root, "v2_proposed", "a" * 64, T, write)
            self.assertEqual(seen, [True])  # the lock existed before the first count
            with self.assertRaises(seals_v2.SealError):
                seals_v2.score_locked(root, "v1_accepted", "a" * 64, T, lambda: [])  # bars cannot change now
            self.assertFalse(seals_v2.score_locked(root, "v2_proposed", "a" * 64, T, lambda: []))  # same bars rerun

    def test_no_count_is_written_when_the_lock_cannot_be_recorded(self):
        with H.private_dir() as t:
            root = Path(t)
            v1_seals(root)
            review_files(root)
            seals_v2.seal_review(root, T)
            called = []
            os.chmod(root / "seals-v2.txt", 0o400)
            try:
                with self.assertRaises(OSError):
                    seals_v2.score_locked(root, "v2_proposed", "a" * 64, T, lambda: called.append(1))
            finally:
                os.chmod(root / "seals-v2.txt", 0o600)
            self.assertEqual(called, [])
            self.assertNotIn(seals_v2.LOCK, seals_v2.recorded(root))

    def test_damaged_or_linked_seal_file_refused(self):
        for text in ("seal-review-v2 broken\n", f"score-a-v2 {'a' * 64} v2_proposed {T}\n",
                     f"seal-review-v2 {'a' * 64} 2 {T}\nseal-review-v2 {'b' * 64} 2 {T}\n",
                     f"seal-review-v2 {'a' * 64} 2 {T}\nscore-a-v2 {'a' * 64} v3 {T}\n"):
            with H.private_dir() as t:
                (Path(t) / "seals-v2.txt").write_text(text)
                with self.assertRaises(seals_v2.SealError):
                    seals_v2.recorded(Path(t))
        with H.private_dir() as t, tempfile.TemporaryDirectory() as other:
            (Path(t) / "seals-v2.txt").symlink_to(Path(other) / "elsewhere.txt")
            with self.assertRaises(seals_v2.SealError):
                seals_v2.recorded(Path(t))


class CommandLine(unittest.TestCase):
    TITLE = "Synthetic Secret Title"

    def test_isolated_help_from_another_folder(self):
        r = subprocess.run([sys.executable, "-I", str(H.HERE / "v2" / "pfd_eval_v2.py"), "--help"], capture_output=True,
                           text=True, cwd=tempfile.gettempdir())
        self.assertEqual(r.returncode, 0, r.stderr)
        for cmd in ("review-sheet-v2", "seal", "score-a-v2"):
            self.assertIn(cmd, r.stdout)

    def test_private_root_refusals(self):
        with tempfile.TemporaryDirectory() as t:
            repo = Path(t) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            os.chmod(repo, 0o700)
            shared = Path(t) / "shared"
            shared.mkdir()
            os.chmod(shared, 0o755)
            for root in (repo, shared):
                r = subprocess.run([sys.executable, "-I", str(H.HERE / "v2" / "pfd_eval_v2.py"), "seal", "--root", str(root),
                                    "seal-review-v2"], capture_output=True, text=True)
                self.assertNotEqual(r.returncode, 0)
                self.assertFalse((root / "seals-v2.txt").exists())

    def run_cli(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            try:
                pfd_eval_v2.main(list(argv))
                code = 0
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 1
                print(e.code)
        text = out.getvalue()
        self.assertNotIn(self.TITLE, text)
        self.assertIsNone(re.search(r"pfc:[0-9a-f]{12}\b", text))  # no entry ID reaches the console
        return code, text

    def test_end_to_end_counts_only(self):
        with H.private_dir() as t, tempfile.TemporaryDirectory() as r:
            root, repo = Path(t), Path(r)
            saved = (pfd_eval_v2.REPO, pfd_eval_v2.FREEZE_V1, pfd_eval_v2.FREEZE_V2)
            try:
                pfd_eval_v2.REPO = repo
                pfd_eval_v2.FREEZE_V1, pfd_eval_v2.FREEZE_V2 = repo / "freeze-v1.json", repo / "freeze-v2.json"
                (repo / "frozen.py").write_text("frozen = True\n")
                inv = repo / freeze_v2.INVENTORY
                inv.parent.mkdir(parents=True)
                inv.write_bytes(INVENTORY_BYTES)
                pop = H.population(a1=4, a2=50, a3=45, a4=25, a5=1)
                pop[0]["title"] = self.TITLE
                sample_doc = {"schema": "pfd-sample-v1", "release_id": H.RELEASE, **sample_mod.draw(pop, {}, 42)}
                (root / "sample").mkdir()
                (root / "sample" / "sample.json").write_bytes(formats.dumps(sample_doc))
                counts = formats.dumps({"schema": "pfd-purchase-counts-v1", "release_id": H.RELEASE, "counts": {}})
                (root / "sample" / "purchase-counts.json").write_bytes(counts)
                fz1 = formats.dumps({"schema": "pfd-freeze-v1", "release_id": H.RELEASE, "seed": 42,
                                     "files": {"frozen.py": sha(b"frozen = True\n")},
                                     "sample_sha256": sha(formats.dumps(sample_doc)), "purchase_counts_sha256": sha(counts)})
                pfd_eval_v2.FREEZE_V1.write_bytes(fz1)

                def fz2(**extra):
                    pfd_eval_v2.FREEZE_V2.write_bytes(formats.dumps(
                        {"schema": "pfd-freeze-v2", "files": {freeze_v2.INVENTORY: sha(INVENTORY_BYTES)},
                         "freeze_v1_sha256": freeze_v2.v1_pin(fz1), **extra}))
                fz2()
                score = ("score-a-v2", "--root", str(root), "--out")

                code, text = self.run_cli("review-sheet-v2", "--root", str(root))
                self.assertEqual(code, 0, text)
                sheet_path = root / "review-v2" / seals_v2.SHEET
                self.assertEqual(sheet_path.read_bytes(), F2.write_sheet(F2.sheet_template(sample_doc)))
                self.assertEqual(len(F2.sheet_template(sample_doc)), len(sample_doc["entries"]))  # initial rows only
                self.assertNotEqual(self.run_cli("review-sheet-v2", "--root", str(root))[0], 0)  # never overwritten

                a2 = row_of(sample_doc, "A2")
                a1 = row_of(sample_doc, "A1")
                rows = make_rows(sample_doc, {a2: ("same_food", "same_state", "material_difference", "merge_failed")})
                sheet_path.write_bytes(F2.write_sheet(rows))
                (root / "review-v2" / seals_v2.EVIDENCE).write_bytes(
                    F2.write_evidence(make_records(rows, {(a1, "protein"): "error_basis"})))

                self.assertNotEqual(self.run_cli("seal", "--root", str(root), "seal-review-v2")[0], 0)  # no seal-dev
                v1_seals(root)
                v1_before = (root / "seals.txt").read_bytes()
                (root / "review-v2" / "notes.txt").write_text("x")
                self.assertNotEqual(self.run_cli("seal", "--root", str(root), "seal-review-v2")[0], 0)  # a third file
                (root / "review-v2" / "notes.txt").unlink()
                code, text = self.run_cli("seal", "--root", str(root), "seal-review-v2")
                self.assertEqual(code, 0, text)
                self.assertEqual((root / "seals.txt").read_bytes(), v1_before)

                code, text = self.run_cli(*score, str(repo / "a.json"))  # no part_a_bars: refused, nothing written
                self.assertNotEqual(code, 0)
                self.assertIn("part_a_bars", text)
                self.assertFalse((repo / "a.json").exists())
                self.assertFalse((root / "exclusions-v2").exists())
                self.assertEqual(len((root / "seals-v2.txt").read_text().splitlines()), 1)

                fz2(part_a_bars="v2_proposed")
                code, text = self.run_cli(*score, str(repo / "a.json"))
                self.assertEqual(code, 0, text)
                data = (repo / "a.json").read_bytes()
                doc = results_v2.parse(data)
                self.assertEqual(doc["part_a_bars"], "v2_proposed")
                self.assertEqual(doc["measures"]["a2_different_food_or_other_state"]["count"], 1)
                self.assertEqual(doc["measures"]["a1_macro_value_evidence_errors"]["count"], 1)
                self.assertIsNone(re.search(rb"pfc:[0-9a-f]{12}\b", data))
                self.assertNotIn(self.TITLE.encode(), data)
                ex = exclusions.parse((root / "exclusions-v2" / "exclusions.json").read_bytes())
                ids = [e["entry_id"] for e in sample_doc["entries"]]
                self.assertEqual(ex["withhold_entries"], [ids[a2 - 1]])
                self.assertEqual(ex["withhold_values"], [{"entry_id": ids[a1 - 1], "nutrient": "protein",
                                                          "assessment": "error_basis"}])
                lock = (root / "seals-v2.txt").read_text().splitlines()[1].split()
                self.assertEqual(lock[:3], ["score-a-v2", sha(pfd_eval_v2.FREEZE_V2.read_bytes()), "v2_proposed"])
                self.assertNotEqual(self.run_cli(*score, str(repo / "a.json"))[0], 0)  # never overwritten
                self.assertEqual(self.run_cli(*score, str(repo / "b.json"))[0], 0)  # same bars: a rerun is allowed
                self.assertEqual((repo / "b.json").read_bytes(), data)
                self.assertEqual(len((root / "seals-v2.txt").read_text().splitlines()), 2)

                for changed in ({"part_a_bars": "v1_accepted"}, {}):  # after the lock, every v2 command refuses
                    fz2(**changed)
                    for argv in (score + (str(repo / "c.json"),), ("seal", "--root", str(root), "seal-review-v2"),
                                 ("review-sheet-v2", "--root", str(root))):
                        code, text = self.run_cli(*argv)
                        self.assertNotEqual(code, 0)
                        self.assertIn("part_a_bars", text)
                    self.assertFalse((repo / "c.json").exists())
                fz2(part_a_bars="v2_proposed")

                (repo / "frozen.py").write_text("frozen = False\n")  # a changed v1 file
                self.assertNotEqual(self.run_cli(*score, str(repo / "d.json"))[0], 0)
                (repo / "frozen.py").write_text("frozen = True\n")
                inv.write_bytes(INVENTORY_BYTES + b"\n")  # a changed v2 file
                self.assertNotEqual(self.run_cli(*score, str(repo / "d.json"))[0], 0)
                inv.write_bytes(INVENTORY_BYTES)
                changed = json.loads(fz1)
                changed["seed"] = changed.get("seed", 0) + 1
                pfd_eval_v2.FREEZE_V1.write_bytes(json.dumps(changed).encode())  # a different freeze-v1.json
                self.assertNotEqual(self.run_cli(*score, str(repo / "d.json"))[0], 0)
                pfd_eval_v2.FREEZE_V1.write_bytes(fz1)
                sheet_path.write_bytes(F2.write_sheet(make_rows(sample_doc)))  # changed after the seal
                code, text = self.run_cli(*score, str(repo / "d.json"))
                self.assertNotEqual(code, 0)
                self.assertIn("void", text)
                self.assertFalse((repo / "d.json").exists())
            finally:
                pfd_eval_v2.REPO, pfd_eval_v2.FREEZE_V1, pfd_eval_v2.FREEZE_V2 = saved


if __name__ == "__main__":
    unittest.main()
