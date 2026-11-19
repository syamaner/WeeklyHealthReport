#!/usr/bin/env python3
"""Synthetic tests for the gap estimates amendments G1 and G2
(docs/personal-food-catalogue-gap-estimates-v1-amendment.md), the own merge amendment G4
(docs/personal-food-catalogue-own-merge-amendment-v1.md) and the composite web amendment G5
(docs/personal-food-catalogue-composite-web-amendment-v1.md); G3 is tested in test_photo_estimates.py.

Usage: python3 -I test_gap_amendments.py <scripts_dir>
Every title, brand and value here is synthetic.
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import estimate_counts as C  # noqa: E402
import estimates_v2 as EV  # noqa: E402
import estimates_input as I  # noqa: E402
import export_v1  # noqa: E402
from test_estimates_input import CORPORA, RECORDS, item, national, page, plain, read, reference, row  # noqa: E402

ML_RECORD, ZERO_RECORD = "cofid:synthetic:row:0101", "cofid:synthetic:row:0102"
RECORDS[("cofid", ML_RECORD)] = {"nutrients": {"sugar": 2.0, "fiber": 0}, "preparation": "unknown",
                                 "fortification": "unfortified", "per_100_g": False, "per_100_ml": True}
RECORDS[("cofid", ZERO_RECORD)] = {"nutrients": {"fiber": 0, "sugar": 4.5}, "preparation": "unknown",
                                   "fortification": "unfortified", "per_100_g": True, "per_100_ml": False}
RAW_RECORD, UNSTATED_RECORD = "cofid:synthetic:row:0103", "cofid:synthetic:row:0104"
RECORDS[("cofid", RAW_RECORD)] = {"nutrients": {"protein": 11.0}, "preparation": "raw",
                                  "fortification": "unfortified", "per_100_g": True, "per_100_ml": False}
RECORDS[("cofid", UNSTATED_RECORD)] = {"nutrients": {"protein": 3.0, "fiber": 2.5}, "preparation": "unknown",
                                       "fortification": "unfortified", "per_100_g": True, "per_100_ml": False}
DISH = item("Synthetic Ready Meal", product_type="packaged_composite", state="unknown")
DRINK = item("Synthetic Still Drink", state="unknown", basis="per_100_ml_as_labelled")
NO_REFUSALS = C.Lists({"schema": C.SCHEMA_REFUSALS, "rows": []})


def generic(ref, quality="low", assumption=I.COMPOSITE_SENTENCE + " Synthetic.", **changes):
    return national("carried_from_similar_food", ref=ref, quality=quality, state_basis="stated_assumption",
                    assumption=assumption, **changes)


def admit(*rows, doc=None):
    doc = doc or plain(DISH, DRINK)
    rows = sorted(rows, key=lambda r: (r["entry_id"], r.get("nutrient", "")))
    acc = I.parse(I.build(I.release_id(I.dumps(doc)), rows))
    estimates, _ = I.expand(doc, acc, read)
    return doc, I.admit(doc, estimates, read)


class CompositeDishes(unittest.TestCase):
    """G1: a generic dish record fills a composite dish only as a rough similar-food estimate."""

    def test_a_low_similar_food_estimate_with_the_sentence_is_admitted(self):
        doc, (admitted, counts) = admit(row(DISH, generic("cofid:synthetic:row:0001"), "protein"))
        self.assertEqual((len(admitted), counts["withheld_composite"]), (1, 0))
        out = I.assemble(doc, admitted)
        self.assertEqual(export_v1.check_bytes(I.dumps(out)), [])
        result = C.six_counts(out, [], NO_REFUSALS)
        self.assertEqual((result["counts"]["composite_above_low"], result["counts"]["composite_without_sentence"]), (0, 0))

    def test_medium_or_no_sentence_is_withheld(self):
        for ev in (generic("cofid:synthetic:row:0001", quality="medium"),
                   generic("cofid:synthetic:row:0001", assumption="Synthetic assumption.")):
            _, (admitted, counts) = admit(row(DISH, ev, "protein"))
            self.assertEqual((admitted, counts["withheld_composite"]), ([], 1))

    def test_the_codec_refuses_a_composite_estimate_above_low(self):
        doc, (admitted, _) = admit(row(DISH, generic("cofid:synthetic:row:0001"), "protein"))
        out = I.assemble(doc, admitted)
        out["estimate_evidence"][0]["quality"] = "medium"
        self.assertIn("estimate-quality", [e.split(":", 1)[0] for e in export_v1.check_bytes(I.dumps(out))])
        result = C.six_counts(out, [], NO_REFUSALS)
        self.assertIn("composite_above_low: 1", C.failures(result))

    def test_a_label_value_still_wins_on_a_composite(self):
        labelled = {**DISH, "label_nutrients": {"protein": {"value": 7.0, "unit": "g", "source_kind": "manual_declaration",
                                                            "source_release": "owner:sha256:" + "d" * 64,
                                                            "record_id": None, "match": "owner"}}}
        doc = plain(labelled, DRINK)
        _, (admitted, counts) = admit(row(labelled, generic("cofid:synthetic:row:0001"), "protein"), doc=doc)
        self.assertEqual((admitted, counts["withheld_label_kept"]), ([], 1))


class PerMillilitre(unittest.TestCase):
    """G2: per 100 ml records, and a quantified zero, on a per 100 ml entry; nothing else."""

    def test_a_per_100_ml_record_fills_a_per_100_ml_entry(self):
        _, (admitted, counts) = admit(row(DRINK, generic(ML_RECORD), "sugar"))
        self.assertEqual((len(admitted), counts["withheld_basis"]), (1, 0))

    def test_a_quantified_zero_from_a_per_100_g_record_fills_a_per_100_ml_entry(self):
        _, (admitted, counts) = admit(row(DRINK, generic(ZERO_RECORD), "fiber"))
        self.assertEqual((len(admitted), counts["withheld_basis"]), (1, 0))

    def test_a_non_zero_per_100_g_value_never_fills_a_per_100_ml_entry(self):
        _, (admitted, counts) = admit(row(DRINK, generic(ZERO_RECORD), "sugar"))
        self.assertEqual((admitted, counts["withheld_basis"]), ([], 1))

    def test_a_per_100_ml_record_never_fills_a_per_100_g_entry(self):
        per_g = item("Synthetic Cordial Concentrate", state="unknown")
        doc = plain(DISH, DRINK, per_g)
        _, (admitted, counts) = admit(row(per_g, generic(ML_RECORD), "sugar"), doc=doc)
        self.assertEqual((admitted, counts["withheld_basis"]), ([], 1))


class BasisDecisions(unittest.TestCase):
    """G2c: the owner's basis decision files an unlabelled entry per 100 ml; nothing else changes."""

    def setUp(self):
        export_v1.BASIS_DECISIONS.clear()

    def load(self, doc):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "basis-decisions.json"
            p.write_text(json.dumps(doc))
            return export_v1.load_basis_decisions(p)

    def test_the_format_is_closed(self):
        ok = {"schema": "pfc-basis-decisions-v1", "rows": [{"entry_id": "pfc:000000000001", "basis": "per_100_ml",
                                                            "date": "2026-11-19"}]}
        self.assertEqual(list(self.load(ok)), ["pfc:000000000001"])
        bad = [{**ok, "schema": "pfc-basis-decisions-v2"}, {**ok, "extra": 1},
               {**ok, "rows": [{**ok["rows"][0], "basis": "per_100_g"}]},
               {**ok, "rows": [{**ok["rows"][0], "date": "19 November"}]},
               {**ok, "rows": [{**ok["rows"][0], "note": "x"}]},
               {**ok, "rows": ok["rows"] * 2}]
        for doc in bad:
            with self.assertRaises(ValueError, msg=json.dumps(doc)):
                self.load(doc)
        self.assertEqual(export_v1.load_basis_decisions(Path("/nonexistent/basis-decisions.json")), {})

    def test_precedence(self):
        decisions = {e: {"entry_id": e, "basis": "per_100_ml", "date": "2026-11-19"}
                     for e in ("free", "labelled", "merging", "absent")}
        self.assertEqual(export_v1.decided_basis("free", {}, None, decisions), "per_100_ml_as_labelled")
        self.assertIsNone(export_v1.decided_basis("labelled", {"sugar": {}}, None, decisions))
        self.assertIsNone(export_v1.decided_basis("merging", {}, {"role": "merge"}, decisions))
        self.assertEqual(export_v1.decided_basis("candidate", {}, {"role": "candidate"}, {}), None)
        self.assertEqual(dict(export_v1.BASIS_DECISIONS), {"applied": 1, "ignored: the entry has label values": 1,
                                                           "refused: the entry merges its record": 1})

    def test_build_applies_a_decision_and_the_file_passes_the_checker(self):
        cat = {"items": [{"kind": "food", "title": "Synthetic Red Wine", "brand": None, "category": "alcohol",
                          "product_type": "packaged_single_ingredient", "state": "unknown"}],
               "off_releases": {}}
        eid = export_v1.entry_id(None, "Synthetic Red Wine")
        decisions = {eid: {"entry_id": eid, "basis": "per_100_ml", "date": "2026-11-19"},
                     "pfc:000000000009": {"entry_id": "pfc:000000000009", "basis": "per_100_ml", "date": "2026-11-19"}}
        doc, _ = export_v1.build(cat, CORPORA, "2026-11-19", decisions)
        self.assertEqual(doc["items"][0]["basis"], "per_100_ml_as_labelled")
        self.assertEqual(export_v1.check_bytes(json.dumps(doc, indent=1, ensure_ascii=False).encode()), [])
        self.assertEqual(export_v1.BASIS_DECISIONS["ignored: no such entry"], 1)
        plain_doc, _ = export_v1.build(cat, CORPORA, "2026-11-19")
        self.assertEqual(plain_doc["items"][0]["basis"], "per_100_g")

    def test_a_decision_on_a_labelled_entry_is_counted_as_ignored(self):
        self.assertIsNone(export_v1.decided_basis("x", {"sugar": {}}, None, {"x": {}}))
        self.assertEqual(export_v1.BASIS_DECISIONS["ignored: the entry has label values"], 1)


class OwnMergeRecord(unittest.TestCase):
    """G4: an estimate from the entry's own merge record is admitted only where the app does not merge it,
    as an own same-food record at most `medium`."""

    @staticmethod
    def entry(record, state="raw"):
        return item("Synthetic Loose Greens", state=state, product_type="fresh_whole",
                    generic_reference=reference(record_id=record, role="merge"))

    def run_one(self, entry, evidence, nutrient):
        doc = plain(entry, DISH, DRINK)
        return admit(row(entry, evidence, nutrient), doc=doc)[1]

    def test_a_record_the_app_does_not_merge_fills_a_raw_and_a_cooked_entry_at_medium(self):
        for state in ("raw", "cooked"):
            entry = self.entry(UNSTATED_RECORD, state)
            ev = national(ref=UNSTATED_RECORD, state_basis="stated_assumption")
            admitted, counts = self.run_one(entry, ev, "fiber")
            self.assertEqual((len(admitted), counts["withheld_codec"]), (1, 0), state)

    def test_a_record_the_app_merges_is_never_estimated_from(self):
        entry = self.entry(RAW_RECORD)
        admitted, counts = self.run_one(entry, national(ref=RAW_RECORD), "protein")
        self.assertEqual((admitted, counts["withheld_merged_kept"]), ([], 1))

    def test_the_codec_caps_an_own_merge_estimate_at_medium_and_keeps_the_method_and_state_rows(self):
        entry = self.entry(UNSTATED_RECORD)
        cases = [(national(ref=UNSTATED_RECORD, quality="high"), ["estimate-quality"]),
                 (national("carried_from_similar_food", ref=UNSTATED_RECORD, state_basis="stated_assumption"),
                  ["estimate-own-method"]),
                 (national(ref=UNSTATED_RECORD, state_basis="unknown", quality="low"), ["estimate-own-state"])]
        for ev, codes in cases:
            admitted, counts = self.run_one(entry, ev, "fiber")
            self.assertEqual((admitted, counts["withheld_codec"]), ([], 1), codes)
            for code in codes:
                self.assertEqual(counts["codec_" + code], 1, code)
            self.assertNotIn("codec_estimate-own-merge", {k for k, v in counts.items() if v})
            self.assertNotIn("codec_estimate-own-held", {k for k, v in counts.items() if v})

    def test_the_ceiling(self):
        ev = national(ref=UNSTATED_RECORD)
        self.assertEqual(EV.ceiling(ev, own=True), "high")
        self.assertEqual(EV.ceiling(ev, own=True, own_merge=True), "medium")
        self.assertEqual(EV.ceiling({**ev, "state_basis": "unknown"}, own=True, own_merge=True), "low")
        self.assertNotIn("estimate-own-merge", EV.RULE_CODES)


def web(source_type="aggregator", method="carried_from_similar_food", quality="low",
        assumption=I.COMPOSITE_SENTENCE + " Synthetic.", **changes):
    return page(source_type=source_type, method=method, quality=quality, assumption=assumption,
                state_basis="stated_assumption", **changes)


class CompositeWebPages(unittest.TestCase):
    """G5: a web page about a generic dish fills a composite dish on G1's terms; a page about this
    product is unchanged; a manufacturer page about another product never fills it."""

    def run_rows(self, *evs):
        return admit(*[row(DISH, ev, n, value=v) for ev, n, v in evs])

    def test_a_low_generic_aggregator_value_with_the_sentence_is_admitted_and_exports(self):
        doc, (admitted, counts) = self.run_rows((web(), "protein", 6.0))
        self.assertEqual((len(admitted), counts["withheld_composite"]), (1, 0))
        out = I.assemble(doc, admitted)
        self.assertEqual(export_v1.check_bytes(I.dumps(out)), [])
        result = C.six_counts(out, [], NO_REFUSALS)
        self.assertEqual([result["counts"][k] for k in ("composite_above_low", "composite_without_sentence",
                                                        "composite_other_product_page")], [0, 0, 0])

    def test_medium_or_no_sentence_is_withheld(self):
        for ev in (web(quality="medium"), web(assumption="Synthetic assumption.")):
            _, (admitted, counts) = self.run_rows((ev, "protein", 6.0))
            self.assertEqual((admitted, counts["withheld_composite"]), ([], 1))

    def test_a_manufacturer_page_about_another_product_is_withheld(self):
        _, (admitted, counts) = self.run_rows((web(source_type="manufacturer_page"), "protein", 6.0))
        self.assertEqual((admitted, counts["withheld_composite"]), ([], 1))

    def test_a_page_about_this_product_keeps_its_ceiling(self):
        for source_type in ("aggregator", "manufacturer_page"):
            for method in ("direct", "carried_from_same_food"):
                doc, (admitted, counts) = self.run_rows((page(source_type=source_type, method=method), "protein", 6.0))
                self.assertEqual((len(admitted), counts["withheld_composite"]), (1, 0), (source_type, method))
                out = I.assemble(doc, admitted)
                self.assertEqual(export_v1.check_bytes(I.dumps(out)), [])
                result = C.six_counts(out, [], NO_REFUSALS)
                self.assertEqual(result["counts"]["composite_above_low"], 0)

    def test_the_codec_refuses_a_generic_web_value_above_low(self):
        doc, (admitted, _) = self.run_rows((web(), "protein", 6.0))
        out = I.assemble(doc, admitted)
        out["estimate_evidence"][0]["quality"] = "medium"
        self.assertIn("estimate-quality", [e.split(":", 1)[0] for e in export_v1.check_bytes(I.dumps(out))])
        self.assertIn("composite_above_low: 1", C.failures(C.six_counts(out, [], NO_REFUSALS)))

    def test_a_label_value_still_wins(self):
        labelled = {**DISH, "label_nutrients": {"protein": {"value": 7.0, "unit": "g", "source_kind": "manual_declaration",
                                                            "source_release": "owner:sha256:" + "d" * 64,
                                                            "record_id": None, "match": "owner"}}}
        _, (admitted, counts) = admit(row(labelled, web(), "protein", value=6.0), doc=plain(labelled, DRINK))
        self.assertEqual((admitted, counts["withheld_label_kept"]), ([], 1))

    def test_the_ceiling(self):
        similar = web()
        self.assertEqual(EV.ceiling(similar, own=False, composite=True), "low")
        self.assertEqual(EV.ceiling(similar, own=False, composite=False), "medium")
        self.assertEqual(EV.ceiling(web(source_type="manufacturer_page"), own=False, composite=True), "low")
        self.assertEqual(EV.ceiling(page(method="direct"), own=False, composite=True), "high")
        photo = {**similar, "source_type": "product_dataset_photo"}
        self.assertEqual(EV.ceiling(photo, own=False, composite=True), "medium")
        self.assertEqual(I.REASONS.count("composite"), 1)
        self.assertIn("composite_other_product_page", C.MUST_BE_ZERO)


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1])
