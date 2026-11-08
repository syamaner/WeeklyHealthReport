#!/usr/bin/env python3
"""Synthetic tests for assemble_extras.attach_label. Every value here is synthetic.

Usage: python3 -I test_attach_label.py <scripts_dir>
"""
import sys
import unittest

sys.path.insert(0, sys.argv[1])
import assemble_extras as X  # noqa: E402

NOTE = "https://example.invalid/synthetic-oats; read 2026-11-08; as sold"


def item(origin, basis="per_100_g", note=NOTE):
    return {"source_id": "synthetic-page-2026-11-08", "attach_to": "Synthetic oats", "note": note,
            "captured": "2026-11-08", "label": {"origin": origin, "basis": basis,
                                                "values": {"protein": 12.0, "fat_total": 7.0}}}


def entry(basis="per_100_g"):
    return {"title": "Synthetic oats", "basis": basis, "nutrients": {"fiber": {"value": 9.0}},
            "label_tiers": {"off": {}}}


class AttachLabel(unittest.TestCase):
    def test_page_evidence_is_kept_with_the_label(self):
        t = entry()
        self.assertTrue(X.attach_label(t, item("page_unconfirmed")))
        src = "label:page-unconfirmed:synthetic-page-2026-11-08"
        self.assertEqual(t["label_evidence"], {src: {"origin": "page_unconfirmed", "note": NOTE}})
        self.assertEqual(t["label_tiers"]["owner"]["protein"]["source"], src)
        self.assertNotIn("protein", t["nutrients"])  # unconfirmed values never become entry nutrients

    def test_confirmed_label_fills_nutrients_and_keeps_evidence(self):
        t = entry()
        self.assertTrue(X.attach_label(t, item("page_confirmed")))
        self.assertEqual(t["nutrients"]["protein"]["value"], 12.0)
        self.assertEqual(t["nutrients"]["fiber"]["value"], 9.0)
        self.assertEqual(t["label_evidence"]["label:owner-page:synthetic-page-2026-11-08"]["note"], NOTE)

    def test_rerun_overwrites_rather_than_duplicates(self):
        t = entry()
        X.attach_label(t, item("page_unconfirmed"))
        X.attach_label(t, item("page_unconfirmed", note="https://example.invalid/synthetic-oats; read 2026-11-09; as sold"))
        self.assertEqual(len(t["label_evidence"]), 1)
        self.assertIn("2026-11-09", next(iter(t["label_evidence"].values()))["note"])

    def test_basis_rules_unchanged(self):
        self.assertFalse(X.attach_label(None, item("page_confirmed")))
        self.assertFalse(X.attach_label(entry(), item("page_confirmed", basis="per_serving")))
        t = entry()
        self.assertFalse(X.attach_label(t, item("page_unconfirmed", basis="per_100_ml")))
        self.assertNotIn("label_evidence", t)  # an unconfirmed label never changes the basis
        t = entry()
        self.assertTrue(X.attach_label(t, item("page_confirmed", basis="per_100_ml")))
        self.assertEqual(t["basis"], "per_100_ml_as_labelled")
        self.assertNotIn("fiber", t["nutrients"])  # old-basis values dropped


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1])
