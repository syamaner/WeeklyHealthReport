#!/usr/bin/env python3
"""Synthetic tests for the gap estimates amendments G1 and G2
(docs/personal-food-catalogue-gap-estimates-v1-amendment.md); G3 is tested in test_photo_estimates.py.

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
import estimates_input as I  # noqa: E402
import export_v1  # noqa: E402
from test_estimates_input import CORPORA, RECORDS, item, national, plain, read, row  # noqa: E402

ML_RECORD, ZERO_RECORD = "cofid:synthetic:row:0101", "cofid:synthetic:row:0102"
RECORDS[("cofid", ML_RECORD)] = {"nutrients": {"sugar": 2.0, "fiber": 0}, "preparation": "unknown",
                                 "fortification": "unfortified", "per_100_g": False, "per_100_ml": True}
RECORDS[("cofid", ZERO_RECORD)] = {"nutrients": {"fiber": 0, "sugar": 4.5}, "preparation": "unknown",
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


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1])
