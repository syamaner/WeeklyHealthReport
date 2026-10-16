import copy
import unittest

from helpers import candidate_from_truth, muesli_truth

import arithmetic
import score


def set_value(table, nutrient, basis, text, comparator="="):
    for cell in table["cells"]:
        if cell["nutrient"] == nutrient and cell["basis"] == basis:
            cell["decimal_text"] = text
            cell["comparator"] = comparator


class EnergyTests(unittest.TestCase):
    def test_taiwan_form_reproduces_the_muesli_label_exactly(self):
        check = arithmetic.energy_check(muesli_truth(), "per_100g")
        self.assertEqual(check["status"], arithmetic.PASS)
        forms = {f["form"]: f for f in check["forms"]}
        self.assertEqual(forms["taiwan"]["computed_kcal"], "367.2")
        self.assertEqual(forms["taiwan"]["difference"], "0.0")
        self.assertEqual(forms["general"]["computed_kcal"], "391.2")

    def test_tolerance_is_larger_of_15_kcal_and_10_percent(self):
        table = muesli_truth()
        set_value(table, "energy_kcal", "per_100g", "450")  # every form is over 45 kcal above
        self.assertEqual(arithmetic.energy_check(table, "per_100g")["status"], arithmetic.FAIL)
        set_value(table, "energy_kcal", "per_100g", "400")  # 32.8 above, allowed 40
        self.assertEqual(arithmetic.energy_check(table, "per_100g")["status"], arithmetic.PASS)

    def test_small_energy_uses_the_absolute_floor(self):
        table = {"language": "en", "cells": [
            {"nutrient": n, "basis": "per_100g", "canonical_unit": u, "comparator": "=", "decimal_text": v}
            for n, u, v in (("energy_kcal", "kcal", "20"), ("protein", "g", "1"), ("fat", "g", "0"), ("carbohydrate", "g", "8"))]}
        # computed 36, printed 20: 16 above the 15 kcal floor
        self.assertEqual(arithmetic.energy_check(table, "per_100g")["status"], arithmetic.FAIL)

    def test_us_tolerance_is_wider(self):
        table = {"jurisdiction": "us", "cells": [
            {"nutrient": n, "basis": "per_serving", "canonical_unit": u, "comparator": "=", "decimal_text": v}
            for n, u, v in (("energy_kcal", "kcal", "100"), ("protein", "g", "5"), ("fat", "g", "0"), ("carbohydrate", "g", "24"))]}
        # computed 116: 16 above, within max(20, 20)
        self.assertEqual(arithmetic.energy_check(table, "per_serving")["status"], arithmetic.PASS)

    def test_uk_fibre_variant_may_pass(self):
        cells = [{"nutrient": n, "basis": "per_100g", "canonical_unit": u, "comparator": "=", "decimal_text": v}
                 for n, u, v in (("energy_kcal", "kcal", "200"), ("protein", "g", "10"), ("fat", "g", "0"),
                                 ("carbohydrate", "g", "30"), ("fibre", "g", "20"))]
        # general 160 (40 short, allowed 20); with fibre 200
        self.assertEqual(arithmetic.energy_check({"language": "en", "cells": cells}, "per_100g")["status"], arithmetic.PASS)

    def test_bounds_and_unknowns_are_not_checkable(self):
        table = muesli_truth()
        set_value(table, "fat", "per_100g", "8.8", comparator="<")
        self.assertEqual(arithmetic.energy_check(table, "per_100g")["status"], arithmetic.NOT_CHECKABLE)
        table["cells"] = [c for c in table["cells"] if c["nutrient"] != "protein"]
        self.assertEqual(arithmetic.energy_check(table, "per_serving")["status"], arithmetic.NOT_CHECKABLE)


class OtherCheckTests(unittest.TestCase):
    def test_kj_kcal_ratio(self):
        cells = [{"nutrient": "energy_kj", "basis": "per_100g", "canonical_unit": "kJ", "comparator": "=", "decimal_text": "1500"},
                 {"nutrient": "energy_kcal", "basis": "per_100g", "canonical_unit": "kcal", "comparator": "=", "decimal_text": "355"}]
        self.assertEqual(arithmetic.kj_kcal_check({"cells": cells}, "per_100g")["status"], arithmetic.PASS)
        cells[1]["decimal_text"] = "300"
        self.assertEqual(arithmetic.kj_kcal_check({"cells": cells}, "per_100g")["status"], arithmetic.FAIL)

    def test_subrow_above_parent_fails(self):
        table = muesli_truth()
        set_value(table, "fibre", "per_100g", "70")
        statuses = {c["child"]: c["status"] for c in arithmetic.subrow_checks(table, "per_100g")}
        self.assertEqual(statuses["fibre"], arithmetic.FAIL)

    def test_serving_scaling_respects_printed_rounding(self):
        table = muesli_truth()
        self.assertTrue(all(c["status"] == arithmetic.PASS for c in arithmetic.scaling_checks(table)))
        set_value(table, "protein", "per_serving", "13")
        self.assertIn(arithmetic.FAIL, {c["status"] for c in arithmetic.scaling_checks(table)})

    def test_net_weight(self):
        from decimal import Decimal
        self.assertEqual(arithmetic.net_weight_check(muesli_truth(), Decimal("500"))["status"], arithmetic.PASS)
        self.assertEqual(arithmetic.net_weight_check(muesli_truth(), Decimal("900"))["status"], arithmetic.FAIL)

    def test_failure_blocks_ready_but_never_rewrites(self):
        candidate = candidate_from_truth(muesli_truth())
        set_value(candidate, "energy_kcal", "per_100g", "900")
        before = copy.deepcopy(candidate)
        ready, check = score.effective_ready(candidate)
        self.assertFalse(ready)
        self.assertIn("energy does not match the macronutrients", check["warnings"])
        self.assertEqual(candidate, before)

    def test_pass_never_upgrades_an_unready_candidate(self):
        candidate = candidate_from_truth(muesli_truth(), ready=False)
        ready, check = score.effective_ready(candidate)
        self.assertEqual(check["status"], arithmetic.PASS)
        self.assertFalse(ready)


class MutationTests(unittest.TestCase):
    def test_three_frozen_mutations(self):
        self.assertEqual(arithmetic.MUTATIONS, ("tenfold_serving", "basis_transposition", "bound_replaced_by_exact"))
        table = muesli_truth()
        tenfold = arithmetic.mutate(table, "tenfold_serving")
        self.assertEqual(arithmetic.check_table(tenfold)["status"], arithmetic.FAIL)
        # The muesli serving is 100 g, so a basis transposition is not applicable.
        self.assertIsNone(arithmetic.mutate(table, "basis_transposition"))
        self.assertIsNone(arithmetic.mutate(table, "bound_replaced_by_exact"))

    def test_transposition_detected_when_serving_differs(self):
        table = muesli_truth()
        table["serving_size"]["decimal_text"] = "50"
        for cell in table["cells"]:
            if cell["basis"] == "per_serving":
                cell["decimal_text"] = str(arithmetic.number(cell["decimal_text"]) / 2)
        self.assertNotEqual(arithmetic.check_table(table)["status"], arithmetic.FAIL)
        mutated = arithmetic.mutate(table, "basis_transposition")
        self.assertEqual(arithmetic.check_table(mutated)["status"], arithmetic.FAIL)

    def test_bound_replacement_detected_only_with_a_bounded_partner_column(self):
        table = muesli_truth()
        set_value(table, "trans_fat", "per_serving", "0.1", comparator="<")
        set_value(table, "trans_fat", "per_100g", "0.1", comparator="<")
        mutated = arithmetic.mutate(table, "bound_replaced_by_exact")
        self.assertEqual(arithmetic.check_table(mutated)["status"], arithmetic.FAIL)
        outcome = arithmetic.mutation_detection([table])
        self.assertEqual(outcome["bound_replaced_by_exact"], {"applicable": 1, "detected": 1})


if __name__ == "__main__":
    unittest.main()
