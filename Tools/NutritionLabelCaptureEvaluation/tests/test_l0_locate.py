"""Phase L0 locate-rate analysis (#316). Pure parts only; synthetic fixtures, no Vision."""

from __future__ import annotations

import copy
import unittest
from decimal import Decimal
from typing import Any

import helpers

import decline_gate
import l0_locate as l0

TAIWAN = decline_gate.TAIWAN


def table() -> tuple[dict[str, Any], dict[str, Any]]:
    truth = helpers.muesli_truth()
    return helpers.candidate_from_truth(truth), truth


def index_of(output: dict[str, Any], nutrient: str, basis: str) -> int:
    (found,) = [i for i, c in enumerate(output["cells"]) if c["nutrient"] == nutrient and c["basis"] == basis]
    return found


def all_found(output: dict[str, Any]) -> dict[str, str]:
    located = {f"cell:{i}": "found" for i in range(len(output["cells"]))}
    located.update({field: "found" for field in ("serving_size", "servings_per_pack")})
    return located


class L0LocateTests(unittest.TestCase):
    def test_exact_table_found_everywhere_has_no_attention(self) -> None:
        output, truth = table()
        result = l0.table_result({"id": "x", "candidate": output, "truth": truth, "label_format": TAIWAN}, all_found(output))
        self.assertTrue(result["prefilled"])
        self.assertEqual(result["attention"], 0)
        self.assertEqual(result["wrong"], 0)
        self.assertFalse(result["silent_table"])

    def test_misread_value_not_found_is_a_caught_silent_error(self) -> None:
        output, truth = table()
        wrong = copy.deepcopy(output)
        i = index_of(wrong, "sodium", "per_100g")
        wrong["cells"][i]["decimal_text"] = "9" + wrong["cells"][i]["decimal_text"]
        located = all_found(wrong)
        located[f"cell:{i}"] = "not_found"
        result = l0.table_result({"id": "x", "candidate": wrong, "truth": truth, "label_format": TAIWAN}, located)
        self.assertEqual((result["silent"], result["silent_by_locator"]), (1, 1))
        self.assertTrue(result["silent_caught"])

    def test_consistent_misread_found_on_the_photo_stays_silent(self) -> None:
        output, truth = table()
        wrong = copy.deepcopy(output)
        # Both columns ten times too large, so the per serving against per 100 check still agrees.
        for basis in ("per_100g", "per_serving"):
            cell = wrong["cells"][index_of(wrong, "sodium", basis)]
            cell["decimal_text"] = str(Decimal(cell["decimal_text"]) * 10)
        result = l0.table_result({"id": "x", "candidate": wrong, "truth": truth, "label_format": TAIWAN}, all_found(wrong))
        self.assertEqual((result["silent"], result["silent_by_locator"]), (2, 0))
        self.assertFalse(result["silent_caught"])

    def test_energy_failure_implicates_the_energy_inputs_of_its_basis(self) -> None:
        output, _ = table()
        broken = copy.deepcopy(output)
        broken["cells"][index_of(broken, "energy_kcal", "per_100g")]["decimal_text"] = "999"
        implicated = {broken["cells"][i]["nutrient"] for i in l0.arithmetic_attention(broken)}
        self.assertIn("energy_kcal", implicated)
        self.assertIn("protein", implicated)
        self.assertNotIn("sodium", implicated)

    def test_queries_carry_row_label_header_and_printed_text(self) -> None:
        output, _ = table()
        headers, queries = l0.queries(output)
        self.assertTrue(headers)
        first = queries[0]
        self.assertEqual(set(first), {"id", "row_label", "header_text", "printed_text"})
        self.assertTrue(any(q["id"] == "serving_size" for q in queries))


if __name__ == "__main__":
    unittest.main()
