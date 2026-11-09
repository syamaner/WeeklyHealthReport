"""R1, the drops-only export: synthetic contract tests (no private data)."""
import contextlib
import copy
import io
import json
import re
import sys
import unittest
from pathlib import Path

import helpers as H

sys.path.insert(0, str(H.HERE / "r1"))
sys.path.insert(1, str(H.HERE / "v2"))
sys.path.insert(2, str(H.REPO / ".agents" / "skills" / "personal-food-catalogue" / "scripts"))

import exclusions  # noqa: E402
import export_v1  # noqa: E402
import pfd_r1  # noqa: E402
import r1_export as R  # noqa: E402

OFF_HASH, OWNER_HASH = "b" * 64, "c" * 64
OFF_REL = f"pfc-off:sha256:{OFF_HASH}:projection:off-product-projection-v4:retrieved:2026-11-07"
OWNER_REL = f"owner:sha256:{OWNER_HASH}"
CORPUS = "a" * 64
SWITCH_OFF = {"a1": False, "a2": False}
NUTRIENTS = set(export_v1.CANON_UNITS)


def off_value(value=1.0, key="protein"):
    unit = export_v1.CANON_UNITS[key]
    return {"value": value, "unit": unit, "source_kind": "exact_product_dataset", "source_release": OFF_REL,
            "record_id": "off:gtin:00000000000017", "match": "probable"}


def owner_value(value=2.0, key="protein"):
    return {"value": value, "unit": export_v1.CANON_UNITS[key], "source_kind": "manual_declaration",
            "source_release": OWNER_REL, "record_id": None, "match": "owner"}


def item(title, labels=None, role=None, state="raw"):
    ref = None
    if role:
        ref = {"source": "cofid", "corpus_sha256": CORPUS, "record_id": f"cofid:{title}",
               "match": "same_food_same_state" if role == "merge" else "close", "role": role}
    return {"id": export_v1.entry_id(None, title), "brand": None, "title": title, "titles": [title], "aliases": [],
            "concept": None, "variety": None, "fallback_chain": [], "category": "other",
            "product_type": "unknown", "state": state, "basis": "per_100_g", "label_nutrients": labels or {},
            "generic_reference": ref}


def pinned_doc():
    items = [
        item("Synthetic off food", {"protein": off_value(), "sodium": off_value(5.0, "sodium")}),
        item("Synthetic owner food", {"protein": owner_value()}),
        item("Synthetic mixed food", {"protein": owner_value(), "sodium": off_value(5.0, "sodium")}, role="merge"),
        item("Synthetic merge food", role="merge"),
        item("Synthetic candidate food", role="candidate"),
        item("Synthetic bare food"),
    ]
    items.sort(key=lambda x: x["id"])
    sources = [
        {"source_release_id": OFF_REL, "source_id": "open-food-facts", "released_at": "2026-11-07T00:00:00Z",
         "artifact_sha256": OFF_HASH, **{k: export_v1.SOURCE_PINS["open-food-facts"][k]
                                         for k in ("schema_version", "pipeline_version", "licence")},
         "attribution": "Open Food Facts · https://world.openfoodfacts.org/product/00000000000017",
         "manifest_sha256": OFF_HASH},
        {"source_release_id": OWNER_REL, "source_id": "owner", "released_at": "2026-11-01T00:00:00Z",
         "artifact_sha256": OWNER_HASH, **export_v1.SOURCE_PINS["owner"], "manifest_sha256": OWNER_HASH},
    ]
    sources.sort(key=lambda s: s["source_release_id"])
    return {"schema": "personal-food-catalogue-v1", "generated": "2026-11-07", "sources": sources,
            "generic_corpora": [{"source": "cofid", "corpus_sha256": CORPUS}], "items": items}


def ident(title):
    return export_v1.entry_id(None, title)


def excl(release, entries=(), values=(), candidates=()):
    return {"schema": "pfd-exclusions-v1", "release_id": release, "withhold_entries": list(entries),
            "withhold_values": [{"entry_id": e, "nutrient": n, "assessment": "error_source"} for e, n in values],
            "reference_candidates": list(candidates)}


def unres(release, values=()):
    return {"schema": R.SCHEMA_UNRESOLVED, "release_id": release,
            "withhold_values": [{"entry_id": e, "nutrient": n} for e, n in values]}


def by_title(doc, title):
    return next(it for it in doc["items"] if it["id"] == ident(title))


class Fixture(unittest.TestCase):
    def test_synthetic_pinned_release_is_importable(self):
        self.assertEqual(export_v1.check_bytes(R.dumps(pinned_doc())), [])


class Derive(unittest.TestCase):
    def setUp(self):
        self.pinned = pinned_doc()
        self.rel = R.release_id(R.dumps(self.pinned))

    def run_r1(self, switches=SWITCH_OFF, e=None, u=None):
        e, u = e or excl(self.rel), u or unres(self.rel)
        doc, counts = R.derive(self.pinned, e, u, switches, NUTRIENTS)
        self.assertEqual(R.check_applied(doc, e, u, switches), [])
        data = R.dumps(doc)
        self.assertEqual(export_v1.check_bytes(data), [])
        self.assertEqual(export_v1.check_export_conventions(doc), [])
        self.assertEqual(R.check_drops_only(self.pinned, doc), [])
        return doc, counts

    def test_no_drops_reproduces_the_pinned_bytes(self):
        doc, counts = self.run_r1()
        self.assertEqual(R.dumps(doc), R.dumps(self.pinned))
        self.assertEqual(counts["sources_removed"], 0)

    def test_a1_drops_every_open_food_facts_value_and_its_source(self):
        doc, counts = self.run_r1({"a1": True, "a2": False})
        kinds = {v["source_kind"] for it in doc["items"] for v in it["label_nutrients"].values()}
        self.assertEqual(kinds, {"manual_declaration"})
        self.assertEqual(counts["values_dropped_a1"], 3)
        self.assertEqual([s["source_id"] for s in doc["sources"]], ["owner"])
        self.assertEqual(counts["sources_removed"], 1)
        self.assertEqual(by_title(doc, "Synthetic off food")["label_nutrients"], {})
        mixed = by_title(doc, "Synthetic mixed food")
        self.assertEqual(set(mixed["label_nutrients"]), {"protein"})
        self.assertEqual(mixed["generic_reference"]["role"], "merge")  # pinned merge kept, never added

    def test_withheld_entry_loses_values_and_reference(self):
        e = excl(self.rel, entries=[ident("Synthetic mixed food")])
        doc, counts = self.run_r1(e=e)
        mixed = by_title(doc, "Synthetic mixed food")
        self.assertEqual((mixed["label_nutrients"], mixed["generic_reference"]), ({}, None))
        self.assertEqual((counts["entries_withheld"], counts["values_dropped_withheld_entry"],
                          counts["references_removed_withheld_entry"]), (1, 2, 1))
        self.assertEqual(mixed["title"], "Synthetic mixed food")  # the entry stays: "No nutrition data yet"

    def test_withheld_label_value_demotes_the_merge_so_it_cannot_refill_it(self):
        e = excl(self.rel, values=[(ident("Synthetic mixed food"), "protein")])
        doc, counts = self.run_r1(e=e)
        mixed = by_title(doc, "Synthetic mixed food")
        self.assertEqual(set(mixed["label_nutrients"]), {"sodium"})
        self.assertEqual(mixed["generic_reference"]["role"], "candidate")
        self.assertEqual(counts["references_demoted_to_candidate"], 1)
        kept = copy.deepcopy(doc)
        by_title(kept, "Synthetic mixed food")["generic_reference"]["role"] = "merge"
        self.assertIn("listed-value-reachable-through-merge", R.check_applied(kept, e, unres(self.rel), SWITCH_OFF))

    def test_withheld_label_value_is_removed(self):
        e = excl(self.rel, values=[(ident("Synthetic owner food"), "protein")])
        doc, counts = self.run_r1(e=e)
        self.assertEqual(by_title(doc, "Synthetic owner food")["label_nutrients"], {})
        self.assertEqual(counts["values_dropped_withheld_value"], 1)
        self.assertEqual(counts["entries_with_no_nutrition"], 2)  # with the bare food

    def test_value_reached_through_a_reference_removes_the_reference_once(self):
        e = excl(self.rel, values=[(ident("Synthetic merge food"), "fiber"), (ident("Synthetic merge food"), "iron")])
        doc, counts = self.run_r1(e=e)
        self.assertIsNone(by_title(doc, "Synthetic merge food")["generic_reference"])
        self.assertEqual(counts["references_removed_for_value"], 1)

    def test_unresolved_value_is_withheld_and_counted_apart(self):
        u = unres(self.rel, [(ident("Synthetic mixed food"), "sodium")])
        doc, counts = self.run_r1(u=u)
        self.assertEqual(set(by_title(doc, "Synthetic mixed food")["label_nutrients"]), {"protein"})
        self.assertEqual((counts["values_dropped_unresolved"], counts["values_dropped_withheld_value"]), (1, 0))

    def test_value_listed_as_error_and_unresolved_counts_once_as_error(self):
        key = (ident("Synthetic owner food"), "protein")
        _, counts = self.run_r1(e=excl(self.rel, values=[key]), u=unres(self.rel, [key]))
        self.assertEqual((counts["values_dropped_withheld_value"], counts["values_dropped_unresolved"]), (1, 0))

    def test_unreachable_listed_value_is_refused(self):
        u = unres(self.rel, [(ident("Synthetic bare food"), "protein")])
        with self.assertRaises(R.R1Error):
            R.derive(self.pinned, excl(self.rel), u, SWITCH_OFF, NUTRIENTS)

    def test_reference_candidates_and_a2_demote_merges_never_promote(self):
        doc, counts = self.run_r1(e=excl(self.rel, candidates=[ident("Synthetic merge food")]))
        self.assertEqual(by_title(doc, "Synthetic merge food")["generic_reference"]["role"], "candidate")
        self.assertEqual(by_title(doc, "Synthetic mixed food")["generic_reference"]["role"], "merge")
        self.assertEqual(counts["references_demoted_to_candidate"], 1)
        doc, counts = self.run_r1({"a1": False, "a2": True})
        roles = {it["generic_reference"]["role"] for it in doc["items"] if it["generic_reference"]}
        self.assertEqual(roles, {"candidate"})
        self.assertEqual(counts["references_demoted_to_candidate"], 2)

    def test_unknown_entry_and_release_mismatch_are_refused(self):
        with self.assertRaises(R.R1Error):
            R.derive(self.pinned, excl(self.rel, entries=[H.eid(7)]), unres(self.rel), SWITCH_OFF, NUTRIENTS)
        with self.assertRaises(R.R1Error):
            R.derive(self.pinned, excl(self.rel), unres(H.RELEASE), SWITCH_OFF, NUTRIENTS)
        for bad in ({"a1": True}, {"a1": 1, "a2": False}, {"a1": True, "a2": False, "a3": True}):
            with self.assertRaises(R.R1Error):
                R.derive(self.pinned, excl(self.rel), unres(self.rel), bad, NUTRIENTS)

    def test_candidate_reference_is_removed_for_a_listed_value(self):
        doc, counts = self.run_r1(e=excl(self.rel, values=[(ident("Synthetic candidate food"), "fiber")]))
        self.assertIsNone(by_title(doc, "Synthetic candidate food")["generic_reference"])
        self.assertEqual(counts["references_removed_for_value"], 1)

    def test_listed_nutrient_outside_the_inventory_is_refused(self):
        e = excl(self.rel, values=[(ident("Synthetic merge food"), "fibre_typo")])
        with self.assertRaises(R.R1Error):
            R.derive(self.pinned, e, unres(self.rel), SWITCH_OFF, NUTRIENTS)

    def test_check_applied_names_each_missed_removal(self):
        e = excl(self.rel, entries=[ident("Synthetic mixed food")], values=[(ident("Synthetic owner food"), "protein")],
                 candidates=[ident("Synthetic merge food")])
        on = {"a1": True, "a2": True}
        self.assertEqual(R.check_applied(self.pinned, e, unres(self.rel), on),
                         ["a1-value-kept", "a2-merge-kept", "candidate-still-merge", "listed-value-kept",
                          "withheld-entry-kept"])
        self.assertEqual(R.check_applied(self.pinned, excl(self.rel), unres(self.rel), SWITCH_OFF), [])

    def test_same_inputs_give_the_same_bytes(self):
        args = (excl(self.rel, entries=[ident("Synthetic owner food")]), unres(self.rel), {"a1": True, "a2": False})
        a = R.dumps(R.derive(copy.deepcopy(self.pinned), *args, NUTRIENTS)[0])
        b = R.dumps(R.derive(copy.deepcopy(self.pinned), *args, NUTRIENTS)[0])
        self.assertEqual(a, b)

    def test_derive_does_not_mutate_the_pinned_document(self):
        before = R.dumps(self.pinned)
        self.run_r1({"a1": True, "a2": True}, e=excl(self.rel, entries=[ident("Synthetic mixed food")]))
        self.assertEqual(R.dumps(self.pinned), before)


class DropsOnly(unittest.TestCase):
    def setUp(self):
        self.pinned = pinned_doc()

    def test_detects_every_kind_of_addition_or_change(self):
        cases = {
            "value-added-or-changed": lambda d: by_title(d, "Synthetic bare food")["label_nutrients"].update(
                {"protein": owner_value()}),
            "reference-added-or-promoted": lambda d: by_title(d, "Synthetic candidate food")["generic_reference"].update(
                {"role": "merge"}),
            "entry-field-changed": lambda d: by_title(d, "Synthetic owner food").update({"state": "cooked"}),
            "source-added-or-changed": lambda d: d["sources"][0].update({"released_at": "2026-11-08T00:00:00Z"}),
            "top-changed: generated": lambda d: d.update({"generated": "2026-11-09"}),
            "entries-changed": lambda d: d["items"].pop(),
        }
        for code, change in cases.items():
            doc = copy.deepcopy(self.pinned)
            change(doc)
            self.assertIn(code, R.check_drops_only(self.pinned, doc), code)

    def test_a_new_reference_on_a_bare_entry_is_caught(self):
        doc = copy.deepcopy(self.pinned)
        by_title(doc, "Synthetic bare food")["generic_reference"] = by_title(doc, "Synthetic merge food")["generic_reference"]
        self.assertIn("reference-added-or-promoted", R.check_drops_only(self.pinned, doc))


class Unresolved(unittest.TestCase):
    def test_list_from_parsed_review_rows(self):
        rows = [{"row": "1", "entry_id": H.eid(2)}, {"row": "2", "entry_id": H.eid(1)}]
        by_row = {"1": [{"nutrient": "protein", "assessment": "unresolved"}, {"nutrient": "fat_total", "assessment": "correct"}],
                  "2": [{"nutrient": "sodium", "assessment": "unresolved"}, {"nutrient": "iron", "assessment": "error_source"}]}
        self.assertEqual(R.unresolved_list(rows, by_row),
                         [{"entry_id": H.eid(1), "nutrient": "sodium"}, {"entry_id": H.eid(2), "nutrient": "protein"}])

    def test_round_trip_and_refusals(self):
        data = R.build_unresolved(H.RELEASE, [{"entry_id": H.eid(1), "nutrient": "protein"}])
        self.assertEqual(R.parse_unresolved(data)["withhold_values"], [{"entry_id": H.eid(1), "nutrient": "protein"}])
        for bad in ([{"entry_id": H.eid(1), "nutrient": "protein"}] * 2,
                    [{"entry_id": "pfc:x", "nutrient": "protein"}],
                    [{"entry_id": H.eid(1), "nutrient": "protein", "value": 1}]):
            with self.assertRaises(R.R1Error):
                R.build_unresolved(H.RELEASE, bad)
        with self.assertRaises(R.R1Error):
            R.parse_unresolved(b'{"schema": "pfd-unresolved-v2", "release_id": "x", "withhold_values": []}')
        with self.assertRaises(R.R1Error):  # one byte form only
            R.parse_unresolved(data.replace(b",", b", "))
        with self.assertRaises(R.R1Error):
            R.build_unresolved(H.RELEASE, [{"entry_id": H.eid(2), "nutrient": "protein"},
                                           {"entry_id": H.eid(1), "nutrient": "protein"}])
        self.assertEqual(R.build_unresolved(H.RELEASE, R.parse_unresolved(data)["withhold_values"]), data)


class CommandLine(unittest.TestCase):
    """The file handling of build-r1, with the frozen checks stubbed (they have their own tests)."""

    def setUp(self):
        self.pinned = pinned_doc()
        self.data = R.dumps(self.pinned)
        self.rel = R.release_id(self.data)
        self.saved = (pfd_r1.pfd_eval_v2.frozen, pfd_r1.pfd_eval_v2.bundle, pfd_r1.seals_v2.require_review,
                      pfd_r1.score_a_v2.validate)
        rows = [{"row": "1", "entry_id": ident("Synthetic mixed food"), "stratum": "A1"}]
        by_row = {"1": [{"nutrient": "sodium", "assessment": "unresolved"}]}
        self.called = set()
        self.fail_gate = None

        def gate(name, value):
            def stub(*args, **kwargs):
                self.called.add(name)
                if self.fail_gate == name:
                    raise SystemExit(f"refused: {name} failed")
                return value
            return stub
        pfd_r1.pfd_eval_v2.frozen = gate("frozen", ({"release_id": self.rel}, {}, ""))
        pfd_r1.pfd_eval_v2.bundle = gate("bundle", ({}, rows, [], {"group_of": {k: "macro" for k in NUTRIENTS}}))
        pfd_r1.seals_v2.require_review = gate("require_review", "sealed")
        pfd_r1.score_a_v2.validate = gate("validate", by_row)

    def tearDown(self):
        (pfd_r1.pfd_eval_v2.frozen, pfd_r1.pfd_eval_v2.bundle, pfd_r1.seals_v2.require_review,
         pfd_r1.score_a_v2.validate) = self.saved

    def setup_root(self, root: Path, exclusion_release=None):
        (root / "exclusions-v2").mkdir()
        (root / "exclusions-v2" / "exclusions.json").write_bytes(exclusions.build(
            exclusion_release or self.rel, {"withhold_entries": [], "withhold_values": [],
                                            "reference_candidates": [ident("Synthetic merge food")]}))
        release = root / "pinned.json"
        release.write_bytes(self.data)
        return release

    def run_cli(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            try:
                pfd_r1.main(list(argv))
                code = 0
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 1
                print(e.code)
        text = out.getvalue()
        self.assertIsNone(re.search(r"pfc:[0-9a-f]{12}\b", text))  # no entry ID reaches the console
        self.assertNotIn("Synthetic", text)  # no title either
        return code, text

    def test_builds_once_counts_only_and_never_overwrites(self):
        with H.private_dir() as t:
            root = Path(t)
            release = self.setup_root(root)
            argv = ("build-r1", "--root", str(root), "--release", str(release), "--a1", "on", "--a2", "off")
            code, text = self.run_cli(*argv)
            self.assertEqual(code, 0, text)
            r1 = (root / pfd_r1.R1_FILE).read_bytes()
            self.assertIn(f"R1 release {R.release_id(r1)}", text)
            self.assertIn("values_dropped_a1 2", text)  # the unresolved sodium is counted as unresolved first
            self.assertIn("values_dropped_unresolved 1", text)
            self.assertIn("unresolved values withheld: 1 (by stratum: A1 1)", text)
            self.assertEqual(self.called, {"frozen", "bundle", "require_review", "validate"})
            record = json.loads((root / pfd_r1.RECORD_FILE).read_bytes())
            self.assertEqual((record["switches"], record["r1_release_id"]),
                             ({"a1": True, "a2": False}, R.release_id(r1)))
            doc = json.loads(r1)
            self.assertEqual(R.check_drops_only(self.pinned, doc), [])
            self.assertEqual(by_title(doc, "Synthetic merge food")["generic_reference"]["role"], "candidate")
            self.assertEqual(R.parse_unresolved((root / pfd_r1.UNRESOLVED_FILE).read_bytes())["release_id"], self.rel)
            self.assertEqual(self.run_cli(*argv)[0], 0)  # identical rerun is accepted, nothing rewritten
            (root / pfd_r1.R1_FILE).write_bytes(b"{}")
            code, text = self.run_cli(*argv)
            self.assertNotEqual(code, 0)
            self.assertIn("never overwritten", text)

    def test_each_gate_failure_writes_nothing(self):
        for name in ("frozen", "require_review", "bundle", "validate"):
            with self.subTest(gate=name), H.private_dir() as t:
                root = Path(t)
                release = self.setup_root(root)
                self.fail_gate = name
                code, _ = self.run_cli("build-r1", "--root", str(root), "--release", str(release), "--a1", "on",
                                       "--a2", "off")
                self.assertNotEqual(code, 0)
                self.assertFalse((root / "r1").exists())

    def test_pinned_release_failing_the_importer_rules_is_refused(self):
        with H.private_dir() as t:
            root = Path(t)
            release = self.setup_root(root)
            bad = R.dumps({**self.pinned, "schema": "personal-food-catalogue-v0"})
            release.write_bytes(bad)
            self.rel = R.release_id(bad)
            pfd_r1.pfd_eval_v2.frozen = lambda root, needs=(): ({"release_id": self.rel}, {}, "")
            code, text = self.run_cli("build-r1", "--root", str(root), "--release", str(release), "--a1", "on",
                                      "--a2", "off")
            self.assertNotEqual(code, 0)
            self.assertIn("importer's rules", text)
            self.assertFalse((root / "r1").exists())

    def test_linked_release_is_refused(self):
        with H.private_dir() as t:
            root = Path(t)
            release = self.setup_root(root)
            link = root / "link.json"
            link.symlink_to(release)
            code, text = self.run_cli("build-r1", "--root", str(root), "--release", str(link), "--a1", "on", "--a2", "off")
            self.assertNotEqual(code, 0)
            self.assertIn("is a link", text)

    def test_refuses_another_release_or_exclusion_list(self):
        with H.private_dir() as t:
            root = Path(t)
            release = self.setup_root(root, exclusion_release=H.RELEASE)
            code, text = self.run_cli("build-r1", "--root", str(root), "--release", str(release), "--a1", "on", "--a2", "off")
            self.assertNotEqual(code, 0)
            self.assertIn("another release", text)
            release.write_bytes(self.data + b" ")
            code, text = self.run_cli("build-r1", "--root", str(root), "--release", str(release), "--a1", "on", "--a2", "off")
            self.assertIn("not the pinned release", text)
            self.assertFalse((root / pfd_r1.R1_FILE).exists())


if __name__ == "__main__":
    unittest.main()
