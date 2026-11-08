#!/usr/bin/env python3
"""Synthetic tests for purchase_counts.py. Every value here is synthetic.

Usage: python3 -I test_purchase_counts.py <scripts_dir>
"""
import json
import sys
import unittest

sys.path.insert(0, sys.argv[1])
import purchase_counts as P  # noqa: E402
from export_v1 import entry_id  # noqa: E402


def export(*pairs):
    items = [{"id": entry_id(b, t), "brand": b, "title": t} for b, t in pairs]
    return json.dumps({"schema": "personal-food-catalogue-v1", "items": items}).encode()


def food(brand, title, lines, kind="food"):
    return {"kind": kind, "brand": brand, "title": title, "purchase_lines": lines}


class PurchaseCounts(unittest.TestCase):
    def test_counts_follow_the_export_id_rule_and_add_up(self):
        data = export((None, "Synthetic oats"), ("Brandless", "Synthetic rice"), (None, "Synthetic note food"))
        cat = {"items": [food(None, "Synthetic oats", 3), food(None, "synthetic  OATS", 2),
                         food("Brandless", "Synthetic rice", 1), food(None, "Synthetic soap", 9, kind="non_food")]}
        doc = P.purchase_counts(cat, data)
        self.assertEqual(doc["schema"], "pfd-purchase-counts-v1")
        self.assertTrue(doc["release_id"].startswith("pfc:sha256:"))
        self.assertEqual(doc["counts"], dict(sorted({entry_id(None, "Synthetic oats"): 5,
                                                     entry_id("Brandless", "Synthetic rice"): 1,
                                                     entry_id(None, "Synthetic note food"): 0}.items())))

    def test_a_bought_food_missing_from_the_export_is_refused_without_its_title(self):
        with self.assertRaises(P.CountsError) as cm:
            P.purchase_counts({"items": [food(None, "Synthetic secret", 2)]}, export((None, "Synthetic oats")))
        self.assertNotIn("secret", str(cm.exception))

    def test_an_unbought_food_missing_from_the_export_is_ignored(self):
        doc = P.purchase_counts({"items": [food(None, "Synthetic other", 0)]}, export((None, "Synthetic oats")))
        self.assertEqual(list(doc["counts"].values()), [0])

    def test_invalid_counts_and_files_are_refused(self):
        for lines in (-1, True, "2"):
            with self.assertRaises(P.CountsError):
                P.purchase_counts({"items": [food(None, "Synthetic oats", lines)]}, export((None, "Synthetic oats")))
        with self.assertRaises(P.CountsError):
            P.purchase_counts({"items": []}, b'{"schema": "other", "items": []}')
        with self.assertRaises(P.CountsError):
            P.purchase_counts({"items": []}, export((None, "Synthetic oats"), (None, "Synthetic oats")))


if __name__ == "__main__":
    unittest.main(argv=sys.argv[:1])
