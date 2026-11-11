"""R2, R1 plus owner-approved estimates: synthetic contract tests (no private data)."""
import contextlib
import copy
import io
import json
import re
import sys
import unittest
from pathlib import Path

import helpers as H

sys.path.insert(0, str(H.HERE / "r2"))
sys.path.insert(1, str(H.HERE / "r1"))
sys.path.insert(2, str(H.HERE / "v2"))
sys.path.insert(3, str(H.REPO / ".agents" / "skills" / "personal-food-catalogue" / "scripts"))

import estimates_v1 as E  # noqa: E402
import exclusions  # noqa: E402
import export_v1  # noqa: E402
import pfd_r2  # noqa: E402
import r1_export as R1  # noqa: E402
import r2_export as R2  # noqa: E402
import test_r1 as F  # noqa: E402  (the synthetic pinned release and its builders)

GROUPS = {k: ("macro" if k in ("protein", "energy_consumed", "sodium") else "micro") for k in export_v1.CANON_UNITS}
A1_ON = {"a1": True, "a2": False}
URL = "https://maker.example/food"


def ident(title):
    return F.ident(title)


def fixture(entries=(), values=(("Synthetic merge food", "protein"),), unresolved=()):
    """The pinned release, R1 and the lists R1 was built from. By default the merge food's protein is
    withheld through its reference, so R1 removes that reference; A1 drops every Open Food Facts value."""
    pinned = F.pinned_doc()
    excl = F.excl("pfc:sha256:" + "1" * 64, entries=[ident(t) for t in entries],
                  values=[(ident(t), k) for t, k in values])
    unres = F.unres("pfc:sha256:" + "1" * 64, values=[(ident(t), k) for t, k in unresolved])
    r1, _ = R1.derive(pinned, excl, unres, A1_ON, set(export_v1.CANON_UNITS))
    return pinned, r1, excl, unres


def national(title, key, value, record="cofid:independent", source="cofid", origin="direct", basis="per_100_g"):
    return {"entry_id": ident(title), "nutrient": key, "value": value, "unit": export_v1.CANON_UNITS[key],
            "basis": basis, "underlying_source": "not_applicable", "origin": origin,
            "evidence": {"approved_as_estimate": True, "source_type": "national_composition",
                         "composition_source": source, "source_reference": record, "page_access": None,
                         "source_digest": None, "retrieved_on": None, "source_state": "raw",
                         "target_state": "raw", "state_basis": "source_states_it", "method": "direct",
                         "assumption": "Same food, same state.", "derivation": None}}


def page(title, key, value, url=URL, kind="manufacturer_page", underlying="not_applicable", access="direct_read",
         method="direct", derivation=None, origin="direct", basis="per_100_g"):
    return {"entry_id": ident(title), "nutrient": key, "value": value, "unit": export_v1.CANON_UNITS[key],
            "basis": basis, "underlying_source": underlying, "origin": origin,
            "evidence": {"approved_as_estimate": True, "source_type": kind, "composition_source": None,
                         "source_reference": url, "page_access": access, "source_digest": None,
                         "retrieved_on": "2026-11-09", "source_state": "as sold", "target_state": "as sold",
                         "state_basis": "stated_assumption", "method": method,
                         "assumption": "The page describes this product.", "derivation": derivation}}


def companion(r1, estimates):
    estimates = sorted(estimates, key=lambda e: (e["entry_id"], e["nutrient"]))
    return R2.parse_companion(R2.build_companion(R1.release_id(R1.dumps(r1)), estimates))


def build(estimates, fx=None):
    pinned, r1, excl, unres = fx or fixture()
    listed = {}
    for v in excl["withhold_values"] + unres["withhold_values"]:
        listed.setdefault(v["entry_id"], set()).add(v["nutrient"])
    return R2.derive(r1, pinned, companion(r1, estimates), listed, excl["withhold_entries"], GROUPS)


class Admission(unittest.TestCase):
    def test_each_rule_withholds_and_counts_once(self):
        kj = {"transform_id": "kj_to_kcal_v1", "version": "pasted-label-conversions-v1",
              "source_value": {"value": 418.4, "unit": "kJ"}}
        doc, c = build([
            page("Synthetic off food", "protein", 3.0),                                     # admitted
            page("Synthetic off food", "energy_consumed", 100.0, method="derived", derivation=kj),  # admitted
            national("Synthetic bare food", "calcium", 0),                                  # admitted, a zero
            page("Synthetic owner food", "protein", 9.0),                                   # label_kept
            page("Synthetic owner food", "fiber", 1.0, origin="recipe_estimate"),           # recipe_estimate
            page("Synthetic owner food", "sugar", 1.0, origin="prior_release_unresolved"),
            page("Synthetic candidate food", "protein", 1.0, kind="aggregator", underlying="open_food_facts"),
            page("Synthetic candidate food", "sugar", 1.0, url="https://uk.openfoodfacts.org/product/1"),
            page("Synthetic merge food", "protein", 1.0, origin="prior_release_resolved"),  # e3_withheld_value
            national("Synthetic merge food", "iron", 1.0, record="cofid:Synthetic merge food"),  # e3_withheld_source
            national("Synthetic mixed food", "iron", 1.0, record="cofid:Synthetic mixed food"),  # own_reference
            page("Synthetic bare food", "energy_consumed", 90.0, method="derived", derivation=kj),  # transform
            page("Synthetic bare food", "protein", 1.0, basis="per_100_ml_as_labelled"),   # basis
        ])
        self.assertEqual(c["estimates_admitted"], 3)
        for why in R2.WITHHELD:
            expect = 2 if why == "open_food_facts_source" else 1
            self.assertEqual(c[f"withheld_{why}"], expect, why)
        self.assertEqual(c["zeros_national_composition"], 1)
        self.assertEqual(c["admitted_by_method_derived"], 1)
        self.assertEqual(c["admitted_by_group_macro"], 2)
        self.assertEqual(c["admitted_by_group_micro"], 1)
        self.assertEqual(c["entries_with_estimates"], 2)
        self.assertEqual(R2.check_additive(fixture()[1], doc), [])
        self.assertEqual(E.check_bytes(R2.dumps(doc)), [])

    def test_an_independent_source_on_a_withheld_key_is_admitted_and_shown(self):
        _, c = build([national("Synthetic merge food", "protein", 2.0)])
        self.assertEqual(c["estimates_admitted"], 1)
        self.assertEqual(c["admitted_on_e3_listed_keys"], 1)

    def test_weaker_evidence_classes_are_counted(self):
        _, c = build([page("Synthetic off food", "protein", 1.0, kind="aggregator", underlying="not_stated"),
                      page("Synthetic off food", "sugar", 1.0, access="indexed_copy"),
                      page("Synthetic bare food", "sugar", 1.0, kind="aggregator", underlying="stated_independent",
                           access="indexed_copy")])
        self.assertEqual(c["aggregator_underlying_not_stated"], 1)
        self.assertEqual(c["indexed_copy_admitted"], 2)
        self.assertEqual(c["aggregator_or_indexed_copy_admitted"], 3)

    def test_transforms_are_the_closed_list_with_their_scope(self):
        def d(tid, version, value, unit):
            return {"transform_id": tid, "version": version, "source_value": {"value": value, "unit": unit}}
        g_to_mg = d("mass-g-to-mg", "v1", 0.5, "g")
        salt = d("salt_to_sodium_v1", "pasted-label-conversions-v1", 1.0, "g")
        kj = d("kj_to_kcal_v1", "pasted-label-conversions-v1", 418.4, "kJ")
        admitted = [("sodium", 500.0, g_to_mg), ("energy_consumed", 100.0 * 1.0049, kj)]
        withheld = [("calcium", 500.0, g_to_mg),                       # sodium only, as in import v1 section 4
                    ("protein", 100.0, kj),                            # another nutrient
                    ("energy_consumed", 100.0, d("kj_to_kcal_v1", "pasted-label-conversions-v1", 418.4, "g")),
                    ("energy_consumed", 100.0, d("kcal_from_guess", "v1", 418.4, "kJ")),
                    ("energy_consumed", 100.0 * 1.0051, kj)]           # just outside 0.5 per cent
        _, c = build([page("Synthetic off food", k, v, method="derived", derivation=dv) for k, v, dv in admitted])
        self.assertEqual(c["estimates_admitted"], 2)
        for k, v, dv in withheld:
            with self.subTest(nutrient=k, transform=dv["transform_id"]):
                _, c = build([page("Synthetic bare food", k, v, method="derived", derivation=dv)])
                self.assertEqual(c["withheld_transform"], 1)
        _, c = build([page("Synthetic bare food", "sodium", 400.0, method="derived", derivation=salt)])
        self.assertEqual(c["estimates_admitted"], 1)

    def test_transform_table_matches_the_v1_checker(self):
        self.assertEqual(set(E.TRANSFORMS), set(export_v1.TRANSFORMS))
        for key, (nutrient, unit, _fn) in E.TRANSFORMS.items():
            self.assertEqual((nutrient, unit), export_v1.TRANSFORMS[key][:2])

    def test_entries_with_no_nutrition_is_the_worklist(self):
        _, before = build([])
        _, after = build([page("Synthetic bare food", "protein", 1.0)])
        self.assertEqual(before["entries_with_no_nutrition"] - after["entries_with_no_nutrition"], 1)

    def test_no_laundering_of_values_or_records_e3_withheld(self):
        fx = fixture(entries=("Synthetic candidate food",), values=(), unresolved=(("Synthetic merge food", "iron"),))
        _, c = build([
            national("Synthetic candidate food", "iron", 1.0, record="cofid:Synthetic candidate food"),
            national("Synthetic merge food", "zinc", 1.0, record="cofid:Synthetic merge food"),
            page("Synthetic candidate food", "protein", 1.0),                              # independent: admitted
            page("Synthetic candidate food", "sugar", 1.0, origin="prior_release_resolved"),
            page("Synthetic merge food", "iron", 1.0, origin="prior_release_resolved"),   # an unresolved key
        ], fx)
        self.assertEqual(c["withheld_e3_withheld_source"], 2)  # withheld entry's and unresolved reference
        self.assertEqual(c["withheld_e3_withheld_value"], 2)
        self.assertEqual(c["estimates_admitted"], 1)
        self.assertEqual(c["admitted_on_withheld_entries"], 1)

    def test_a1_dropped_keys(self):
        _, c = build([page("Synthetic off food", "protein", 1.0),                                  # independent
                      page("Synthetic off food", "sodium", 1.0, origin="prior_release_resolved"),  # may be the dropped value
                      page("Synthetic mixed food", "sodium", 1.0, kind="aggregator", underlying="open_food_facts"),
                      page("Synthetic owner food", "sodium", 1.0, url="https://world.openfoodfacts.org/x",
                           origin="recipe_estimate")])
        self.assertEqual(c["estimates_admitted"], 1)
        self.assertEqual(c["admitted_on_a1_dropped_keys"], 1)
        self.assertEqual(c["withheld_e3_withheld_value"], 1)
        self.assertEqual(c["withheld_open_food_facts_source"], 1)
        self.assertEqual(c["companion_open_food_facts"], 2)  # counted whatever rule withholds it

    def test_check_admitted(self):
        fx = fixture()
        est = [page("Synthetic off food", "protein", 3.0), page("Synthetic owner food", "protein", 3.0)]
        doc, _ = build(est, fx)
        pinned, r1, excl, unres = fx
        rows = R2.admitted(r1, pinned, companion(r1, est), {}, [])
        self.assertEqual(len(rows), 1)
        self.assertEqual(R2.check_admitted(doc, rows), [])
        changed = copy.deepcopy(doc)
        next(it for it in changed["items"] if it["estimated_nutrients"])["estimated_nutrients"]["protein"]["value"] = 4.0
        self.assertIn("estimate-changed", R2.check_admitted(changed, rows))
        extra = copy.deepcopy(doc)
        owner = next(it for it in extra["items"] if it["id"] == ident("Synthetic owner food"))
        owner["estimated_nutrients"]["sugar"] = {"value": 1.0, "unit": "g", "evidence_id": "pfe:" + "e" * 16}
        self.assertIn("estimate-not-admitted: 1", R2.check_admitted(extra, rows))
        evidence = copy.deepcopy(doc)
        evidence["estimate_evidence"][0]["assumption"] = "Different."
        self.assertIn("evidence-changed", R2.check_admitted(evidence, rows))
        self.assertIn("admitted-estimate-missing: 1", R2.check_admitted(fixture()[1] | {"items": [
            {**it, "estimated_nutrients": {}} for it in fixture()[1]["items"]], "estimate_evidence": []}, rows))

    def test_unknown_entry_is_refused(self):
        bad = page("Synthetic off food", "protein", 1.0)
        bad["entry_id"] = "pfc:" + "0" * 12
        with self.assertRaises(R2.R2Error):
            build([bad])


class Output(unittest.TestCase):
    def test_deterministic_and_additive(self):
        est = [page("Synthetic off food", "protein", 3.0), national("Synthetic bare food", "calcium", 12.0)]
        a, _ = build(est)
        b, _ = build(list(reversed(est)))
        self.assertEqual(R2.dumps(a), R2.dumps(b))
        self.assertEqual(a["estimate_evidence"][0]["id"], min(R2.evidence_id(e["entry_id"], e["nutrient"]) for e in est))
        self.assertEqual(list(a), list(fixture()[1]) + ["estimate_evidence"])
        self.assertEqual(a["schema"], E.SCHEMA)

    def test_additive_proof_catches_a_change(self):
        r1 = fixture()[1]
        doc, _ = build([page("Synthetic off food", "protein", 3.0)])
        changed = copy.deepcopy(doc)
        changed["items"][0]["title"] = "Changed"
        self.assertIn("entries-differ-outside-estimates: 1", R2.check_additive(r1, changed))
        moved = copy.deepcopy(doc)
        moved["generated"] = "2026-01-01"
        self.assertIn("top-changed: generated", R2.check_additive(r1, moved))


class FileRules(unittest.TestCase):
    """The estimates-file rejection rules, applied to a valid R2 with one change each."""

    def setUp(self):
        doc, _ = build([page("Synthetic off food", "protein", 3.0), national("Synthetic bare food", "calcium", 12.0)])
        self.doc = doc
        self.assertEqual(E.check_bytes(R2.dumps(doc)), [])

    def codes(self, doc):
        return {e.split(":")[0] for e in E.check_bytes(R2.dumps(doc))}

    def entry(self, doc, title):
        return next(it for it in doc["items"] if it["id"] == ident(title))

    def record(self, doc, source_type):
        return next(r for r in doc["estimate_evidence"] if r["source_type"] == source_type)

    def mutate(self, fn):
        doc = copy.deepcopy(self.doc)
        fn(doc)
        return self.codes(doc)

    def test_rejections(self):
        cases = {
            "evidence-dangling": lambda d: self.entry(d, "Synthetic off food")["estimated_nutrients"]["protein"]
            .update(evidence_id="pfe:" + "f" * 16),
            "evidence-unused-or-shared": lambda d: d["estimate_evidence"].append(
                {**self.record(d, "manufacturer_page"), "id": "pfe:" + "f" * 16}),
            "evidence-mismatch": lambda d: self.record(d, "manufacturer_page").update(nutrient="sugar"),
            "not-approved": lambda d: self.record(d, "manufacturer_page").update(approved_as_estimate=1),
            "token": lambda d: self.record(d, "manufacturer_page").update(method="guessed"),
            "source-reference": lambda d: self.record(d, "manufacturer_page").update(source_reference=URL + "?a=1"),
            "open-food-facts-host": lambda d: self.record(d, "manufacturer_page").update(
                source_reference="https://world.openfoodfacts.org/product/1"),
            "date": lambda d: self.record(d, "manufacturer_page").update(retrieved_on="2026-02-30"),
            "free-text": lambda d: self.record(d, "manufacturer_page").update(assumption="a\x07b"),
            "type-fields": lambda d: self.record(d, "national_composition").update(page_access="direct_read"),
            "corpus-undeclared": lambda d: self.record(d, "national_composition").update(composition_source="usda"),
            "derivation-shape": lambda d: self.record(d, "manufacturer_page").update(
                method="derived", derivation={"transform_id": "x", "version": "y", "source_value": {"value": 1}}),
            "derivation-unexpected": lambda d: self.record(d, "manufacturer_page").update(
                derivation={"transform_id": "x", "version": "y", "source_value": {"value": 1, "unit": "g"}}),
            "label-and-estimate": lambda d: self.entry(d, "Synthetic owner food")["estimated_nutrients"].update(
                protein=self.entry(d, "Synthetic off food")["estimated_nutrients"]["protein"]),
            "unit": lambda d: self.entry(d, "Synthetic off food")["estimated_nutrients"]["protein"].update(unit="mg"),
            "value": lambda d: self.entry(d, "Synthetic off food")["estimated_nutrients"]["protein"].update(value=-1),
            "evidence-order": lambda d: d["estimate_evidence"].reverse(),
            "schema": lambda d: d.update(schema="personal-food-catalogue-v1"),
            "evidence-id": lambda d: d["estimate_evidence"][0].update(id="pfe:XYZ"),
            "evidence-duplicate": lambda d: d["estimate_evidence"].append(dict(d["estimate_evidence"][-1])),
            "derivation-missing": lambda d: self.record(d, "manufacturer_page").update(method="derived"),
            "digest": lambda d: self.record(d, "manufacturer_page").update(source_digest="abc"),
            "estimate-keys": lambda d: self.entry(d, "Synthetic off food")["estimated_nutrients"]["protein"]
            .update(note="x"),
            "unknown-nutrient": lambda d: self.entry(d, "Synthetic off food")["estimated_nutrients"].update(
                vitamin_z={"value": 1, "unit": "g", "evidence_id": "pfe:" + "f" * 16}),
            "item-keys": lambda d: self.entry(d, "Synthetic owner food").pop("estimated_nutrients"),
            "top-keys": lambda d: d.update(extra=1),
            "page-date": lambda d: self.record(d, "manufacturer_page").update(retrieved_on=None),
            "state-too-long": lambda d: self.record(d, "manufacturer_page").update(source_state="x" * 201),
            "assumption-too-long": lambda d: self.record(d, "manufacturer_page").update(assumption="x" * 501),
            "user-info": lambda d: self.record(d, "manufacturer_page").update(source_reference="https://u@maker.example/a"),
            "fragment": lambda d: self.record(d, "manufacturer_page").update(source_reference=URL + "#x"),
            "long-url": lambda d: self.record(d, "manufacturer_page").update(source_reference=URL + "/" + "a" * 2048),
            "private-host": lambda d: self.record(d, "manufacturer_page").update(source_reference="https://10.0.0.1/a"),
            "tfda-prefix": lambda d: self.record(d, "national_composition").update(source_reference="tfda:1"),
            "boolean": lambda d: self.entry(d, "Synthetic off food")["estimated_nutrients"]["protein"].update(value=True),
            "v1": lambda d: self.entry(d, "Synthetic off food").update(category="nonsense"),
        }
        real = {"page-date": "date", "state-too-long": "free-text", "assumption-too-long": "free-text",
                "user-info": "source-reference", "fragment": "source-reference", "long-url": "source-reference",
                "private-host": "source-reference", "tfda-prefix": "source-reference", "boolean": "value"}
        for code, fn in cases.items():
            with self.subTest(code=code):
                self.assertIn(real.get(code, code), self.mutate(fn))

    def test_each_schema_refuses_the_other(self):
        r1 = fixture()[1]
        self.assertTrue(export_v1.check_bytes(R2.dumps(self.doc)))
        self.assertTrue(E.check_bytes(R1.dumps(r1)))

    def test_own_reference_and_derivation_are_rejected(self):
        doc = copy.deepcopy(self.doc)
        rec = self.record(doc, "national_composition")
        bare = self.entry(doc, "Synthetic bare food")
        bare["generic_reference"] = {"source": "cofid", "corpus_sha256": F.CORPUS, "record_id": rec["source_reference"],
                                     "match": "close", "role": "candidate"}
        self.assertIn("own-reference", self.codes(doc))
        doc = copy.deepcopy(self.doc)
        rec = self.record(doc, "manufacturer_page")
        rec.update(method="derived", derivation={"transform_id": "mass-g-to-mg", "version": "v1",
                                                 "source_value": {"value": 1, "unit": "g"}})
        self.assertIn("derivation", self.codes(doc))

    def test_bytes_level_rejections(self):
        data = R2.dumps(self.doc)
        self.assertTrue(E.check_bytes(b"\xef\xbb\xbf" + data))
        self.assertTrue(E.check_bytes(data.replace(b'"schema"', b'"schema": 1, "schema"', 1)))
        self.assertTrue(E.check_bytes(b"[1, NaN]"))
        self.assertEqual(E.check_bytes(b"{}")[0].split(":")[0], "top-keys")


class Companion(unittest.TestCase):
    def setUp(self):
        self.r1 = fixture()[1]
        self.rid = R1.release_id(R1.dumps(self.r1))
        self.est = [page("Synthetic off food", "protein", 3.0)]

    def test_undeclared_corpus_refuses_the_companion(self):
        data = R2.build_companion(self.rid, [national("Synthetic bare food", "iron", 1.0, record="usda:1", source="usda")])
        R2.parse_companion(data)
        with self.assertRaises(R2.R2Error):
            R2.parse_companion(data, {"cofid"})

    def test_round_trip_is_canonical(self):
        data = R2.build_companion(self.rid, self.est)
        self.assertEqual(R2.build_companion(self.rid, R2.parse_companion(data)["estimates"]), data)

    def test_refusals(self):
        good = R2.build_companion(self.rid, self.est)
        doc = json.loads(good)
        variants = {
            "not canonical": json.dumps(doc, indent=1).encode(),
            "byte-order mark": b"\xef\xbb\xbf" + good,
            "repeated key": good.replace(b'{"estimates"', b'{"schema":"x","estimates"', 1),
            "NaN": good.replace(b'"value":3.0', b'"value":NaN'),
        }
        for name, data in variants.items():
            with self.subTest(name=name), self.assertRaises(R2.R2Error):
                R2.parse_companion(data)
        bad_cases = {
            "unsorted": [page("Synthetic off food", "sugar", 1.0), page("Synthetic off food", "protein", 1.0)],
            "pair twice": self.est * 2,
            "underlying on a manufacturer page": [page("Synthetic off food", "protein", 1.0, underlying="not_stated")],
            "aggregator without underlying": [page("Synthetic off food", "protein", 1.0, kind="aggregator")],
            "wrong unit": [{**self.est[0], "unit": "mg"}],
            "unknown origin": [{**self.est[0], "origin": "guess"}],
            "extra field": [{**self.est[0], "note": "x"}],
            "not approved": [{**self.est[0], "evidence": {**self.est[0]["evidence"], "approved_as_estimate": False}}],
            "bad url": [page("Synthetic off food", "protein", 1.0, url="http://maker.example/x")],
            "malformed derivation": [page("Synthetic off food", "energy_consumed", 1.0, method="derived",
                                          derivation={"bad": 1})],
            "array basis": [{**self.est[0], "basis": ["per_100_g"]}],
            "object source type": [{**self.est[0], "evidence": {**self.est[0]["evidence"], "source_type": {}}}],
            "localhost": [page("Synthetic off food", "protein", 1.0, url="https://localhost/x")],
            "ip literal": [page("Synthetic off food", "protein", 1.0, url="https://192.168.1.2/x")],
            "dotless host": [page("Synthetic off food", "protein", 1.0, url="https://intranet/x")],
            "leading-zero ip": [page("Synthetic off food", "protein", 1.0, url="https://127.0.0.01/x")],
            "short ip": [page("Synthetic off food", "protein", 1.0, url="https://127.1/x")],
            "hex ip": [page("Synthetic off food", "protein", 1.0, url="https://0x7f.1/x")],
            "ipv6 literal": [page("Synthetic off food", "protein", 1.0, url="https://[::1]/x")],
        }
        for name, est in bad_cases.items():
            with self.subTest(name=name), self.assertRaises(R2.R2Error):
                R2.build_companion(self.rid, est)


class CommandLine(unittest.TestCase):
    """The file handling of build-r2, with the freeze checks stubbed (they have their own tests)."""

    def setUp(self):
        self.pinned, self.r1, self.excl, self.unres = fixture()
        self.pinned_bytes = R1.dumps(self.pinned)
        self.rel = R1.release_id(self.pinned_bytes)
        self.excl = {**self.excl, "release_id": self.rel}
        self.unres = {**self.unres, "release_id": self.rel}
        self.r1_bytes = R1.dumps(self.r1)
        self.saved = (pfd_r2.freeze.check, pfd_r2.freeze.load, pfd_r2.freeze_v2.check, pfd_r2.freeze_v2.parse)
        pfd_r2.freeze.check = lambda doc, repo, needs=(): {"release_id": self.rel}
        pfd_r2.freeze.load = lambda path: {}
        pfd_r2.freeze_v2.check = lambda *a: {}
        pfd_r2.freeze_v2.parse = lambda data: {}

    def tearDown(self):
        pfd_r2.freeze.check, pfd_r2.freeze.load, pfd_r2.freeze_v2.check, pfd_r2.freeze_v2.parse = self.saved

    def setup_root(self, root: Path, estimates=None, unresolved_bytes=None):
        (root / "r1").mkdir(mode=0o700)
        (root / "exclusions-v2").mkdir(mode=0o700)
        excl_bytes = exclusions.build(self.rel, {k: self.excl[k] for k in
                                                 ("withhold_entries", "withhold_values", "reference_candidates")})
        unres_bytes = R1.build_unresolved(self.rel, self.unres["withhold_values"])
        (root / "exclusions-v2" / "exclusions.json").write_bytes(excl_bytes)
        (root / "r1" / "unresolved.json").write_bytes(unresolved_bytes or unres_bytes)
        (root / "r1" / "personal-food-catalogue-v1.json").write_bytes(self.r1_bytes)
        record = {"schema": "pfd-r1-build-v1", "pinned_release_id": self.rel,
                  "r1_release_id": R1.release_id(self.r1_bytes), "switches": A1_ON,
                  "exclusions_sha256": pfd_r2.formats.sha256(excl_bytes),
                  "results_sha256": "0" * 64, "unresolved_sha256": pfd_r2.formats.sha256(unres_bytes)}
        (root / "r1" / "build-record.json").write_bytes(json.dumps(record).encode())
        (root / "pinned.json").write_bytes(self.pinned_bytes)
        est = estimates if estimates is not None else [page("Synthetic off food", "protein", 3.0)]
        (root / "companion.json").write_bytes(R2.build_companion(R1.release_id(self.r1_bytes),
                                                                 sorted(est, key=lambda e: (e["entry_id"], e["nutrient"]))))

    def run_cli(self, root):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            try:
                pfd_r2.main(["build-r2", "--root", str(root), "--release", str(root / "pinned.json"),
                             "--companion", str(root / "companion.json")])
                code = 0
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 1
                print(e.code)
        text = out.getvalue()
        self.assertIsNone(re.search(r"pfc:[0-9a-f]{12}\b", text))  # no entry ID reaches the console
        self.assertIsNone(re.search(r"pfe:[0-9a-f]{16}", text))
        self.assertNotIn("Synthetic", text)
        self.assertNotIn("maker.example", text)
        return code, text

    def test_builds_once_counts_only_and_never_overwrites(self):
        with H.private_dir() as t:
            root = Path(t)
            self.setup_root(root)
            code, text = self.run_cli(root)
            self.assertEqual(code, 0, text)
            folder = root / pfd_r2.release_dir(re.search(r"R2 release (pfc:sha256:[0-9a-f]{64})", text)[1],
                                               pfd_r2.formats.sha256((root / "companion.json").read_bytes()))
            data = (folder / pfd_r2.R2_NAME).read_bytes()
            self.assertIn(f"R2 release {R2.release_id(data)}", text)
            self.assertIn("estimates_admitted 1", text)
            record = json.loads((folder / pfd_r2.RECORD_NAME).read_bytes())
            self.assertEqual(record["r2_release_id"], R2.release_id(data))
            self.assertEqual(record["companion_sha256"], pfd_r2.formats.sha256((root / "companion.json").read_bytes()))
            code, _ = self.run_cli(root)  # the same inputs give the same bytes, so a rerun is accepted
            self.assertEqual(code, 0)
            (folder / pfd_r2.RECORD_NAME).write_bytes(b"{}")
            code, text = self.run_cli(root)
            self.assertNotEqual(code, 0)
            self.assertIn("never overwritten", text)

    def test_a_second_round_gets_its_own_folder(self):
        with H.private_dir() as t:
            root = Path(t)
            self.setup_root(root)
            code, first = self.run_cli(root)
            self.assertEqual(code, 0, first)
            est = [page("Synthetic off food", "protein", 3.0), page("Synthetic bare food", "protein", 1.0)]
            (root / "companion.json").write_bytes(R2.build_companion(
                R1.release_id(self.r1_bytes), sorted(est, key=lambda e: (e["entry_id"], e["nutrient"]))))
            code, second = self.run_cli(root)
            self.assertEqual(code, 0, second)
            self.assertEqual(len([p for p in (root / "r2").iterdir() if p.is_dir()]), 2)
            # a third round that changes only a withheld row gives the same R2 bytes, a new folder and counts
            est.append(page("Synthetic owner food", "protein", 9.0))  # label_kept
            (root / "companion.json").write_bytes(R2.build_companion(
                R1.release_id(self.r1_bytes), sorted(est, key=lambda e: (e["entry_id"], e["nutrient"]))))
            code, third = self.run_cli(root)
            self.assertEqual(code, 0, third)
            self.assertIn("withheld_label_kept 1", third)
            self.assertEqual(re.search(r"R2 release (\S+)", second)[1], re.search(r"R2 release (\S+)", third)[1])
            self.assertEqual(len([p for p in (root / "r2").iterdir() if p.is_dir()]), 3)

    def test_refuses_wrong_inputs(self):
        cases = {
            "not the pinned release": lambda root: (root / "pinned.json").write_bytes(self.pinned_bytes + b"\n"),
            "differs from the one R1 was built with": lambda root: (root / "exclusions-v2" / "exclusions.json")
            .write_bytes(exclusions.build(self.rel, {"withhold_entries": [ident("Synthetic bare food")],
                                                     "withhold_values": [], "reference_candidates": []})),
            "is a link": lambda root: ((root / "real.json").write_bytes((root / "companion.json").read_bytes()),
                                       (root / "companion.json").unlink(),
                                       (root / "companion.json").symlink_to(root / "real.json")),
        }
        for message, spoil in cases.items():
            with self.subTest(message=message), H.private_dir() as t:
                root = Path(t)
                self.setup_root(root)
                spoil(root)
                code, text = self.run_cli(root)
                self.assertNotEqual(code, 0)
                self.assertIn(message, text)
                self.assertFalse((root / "r2").exists())

    def test_refuses_a_root_that_is_not_private(self):
        with H.private_dir() as t:
            root = Path(t)
            self.setup_root(root)
            root.chmod(0o755)
            try:
                code, text = self.run_cli(root)
            finally:
                root.chmod(0o700)
            self.assertNotEqual(code, 0)
            self.assertIn("readable by other users", text)

    def test_refuses_a_companion_for_another_r1(self):
        with H.private_dir() as t:
            root = Path(t)
            self.setup_root(root)
            (root / "companion.json").write_bytes(R2.build_companion("pfc:sha256:" + "9" * 64, []))
            code, text = self.run_cli(root)
            self.assertNotEqual(code, 0)
            self.assertIn("another R1 release", text)
            self.assertFalse((root / "r2").exists())

    def test_refuses_a_changed_unresolved_list(self):
        with H.private_dir() as t:
            root = Path(t)
            self.setup_root(root, unresolved_bytes=R1.build_unresolved(
                self.rel, [{"entry_id": ident("Synthetic bare food"), "nutrient": "protein"}]))
            # the record hashes the canonical empty list, so a different list is refused
            code, text = self.run_cli(root)
            self.assertNotEqual(code, 0)
            self.assertIn("differs from the one R1 was built with", text)

    def test_refuses_a_changed_r1_file(self):
        with H.private_dir() as t:
            root = Path(t)
            self.setup_root(root)
            (root / "r1" / "personal-food-catalogue-v1.json").write_bytes(self.r1_bytes + b"\n")
            code, text = self.run_cli(root)
            self.assertNotEqual(code, 0)
            self.assertIn("not the one its build record names", text)

    def test_refuses_an_r1_that_is_not_the_pinned_derivation(self):
        with H.private_dir() as t:
            root = Path(t)
            other, _ = R1.derive(self.pinned, self.excl, self.unres, {"a1": False, "a2": False},
                                 set(export_v1.CANON_UNITS))
            self.r1_bytes = R1.dumps(other)  # self-consistent file and record, but the record says a1 on
            self.setup_root(root)
            code, text = self.run_cli(root)
            self.assertNotEqual(code, 0)
            self.assertIn("not the drops-only export", text)

    def test_refuses_a_linked_output_folder(self):
        with H.private_dir() as t:
            root = Path(t)
            self.setup_root(root)
            (root / "elsewhere").mkdir(mode=0o700)
            (root / "r2").symlink_to(root / "elsewhere")
            code, text = self.run_cli(root)
            self.assertNotEqual(code, 0)
            self.assertIn("link or not a folder", text)


if __name__ == "__main__":
    unittest.main()
