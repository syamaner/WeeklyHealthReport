import copy
import unittest

from helpers import candidate_from_truth, declined_candidate, muesli_truth

import score

THRESHOLDS = score.load_thresholds()


def cell(table, nutrient, basis):
    return next(c for c in table["cells"] if c["nutrient"] == nutrient and c["basis"] == basis)


class ScoreCaseTests(unittest.TestCase):
    def test_exact_candidate_passes_every_count(self):
        truth = muesli_truth()
        result = score.score_case(candidate_from_truth(truth), truth)
        self.assertEqual(result["failed"], 0)
        self.assertEqual(result["cells_exact"], result["product_cells"])
        self.assertEqual(result["product_cells"], 18)
        self.assertEqual(result["tables_exact"], 1)
        self.assertEqual(result["conversions"], 9)
        self.assertEqual(result["conversions_exact"], 9)
        self.assertEqual(result["servings_per_pack_exact"], 1)
        self.assertEqual(result["false_ready"], 0)
        self.assertEqual(result["would_mark_ready_after_arithmetic"], 1)

    def test_shifted_binding_is_caught_and_counts_as_false_ready(self):
        truth = muesli_truth()
        candidate = candidate_from_truth(truth)
        # Bind the right-hand column one row lower: protein gets the energy value (section 3.4).
        per100 = [c for c in candidate["cells"] if c["basis"] == "per_100g"]
        values = [c["decimal_text"] for c in per100]
        for item, value in zip(per100[1:], values[:-1], strict=True):
            item["decimal_text"] = value
        result = score.score_case(candidate, truth)
        self.assertEqual(result["tables_exact"], 0)
        self.assertLess(result["cells_bound"], result["all_cells"])
        self.assertEqual(cell(candidate, "protein", "per_100g")["decimal_text"], "367.2")
        # The arithmetic policy blocks ready here, so this shift is not a silent false-save.
        self.assertEqual(result["would_mark_ready_after_arithmetic"], 0)
        self.assertEqual(result["false_ready"], 0)

    def test_wrong_but_consistent_table_marked_ready_is_false_ready(self):
        truth = muesli_truth()
        candidate = candidate_from_truth(truth)
        cell(candidate, "sodium", "per_100g")["decimal_text"] = "80"
        cell(candidate, "sodium", "per_serving")["decimal_text"] = "80"
        result = score.score_case(candidate, truth)
        self.assertEqual(result["false_ready"], 1)

    def test_bound_replaced_by_exact_fails_bounds(self):
        truth = muesli_truth()
        cell(truth, "trans_fat", "per_100g")["comparator"] = "<"
        cell(truth, "trans_fat", "per_100g")["decimal_text"] = "0.1"
        candidate = candidate_from_truth(truth)
        cell(candidate, "trans_fat", "per_100g")["comparator"] = "="
        result = score.score_case(candidate, truth)
        self.assertEqual(result["bounded_cells"], 1)
        self.assertEqual(result["bounds_exact"], 0)

    def test_required_decline(self):
        truth = dict(muesli_truth(), requires_decline=True, cells=[])
        self.assertEqual(score.score_case(declined_candidate(), truth)["declines_correct"], 1)
        result = score.score_case(candidate_from_truth(muesli_truth()), truth)
        self.assertEqual(result["declines_correct"], 0)
        self.assertEqual(result["false_ready"], 1)

    def test_false_decline_stays_in_denominators(self):
        truth = muesli_truth()
        result = score.score_case(declined_candidate(), truth)
        self.assertEqual(result["false_declines"], 1)
        self.assertEqual(result["product_cells"], 18)
        self.assertEqual(result["cells_exact"], 0)

    def test_invalid_candidate_is_failed_not_declined(self):
        truth = muesli_truth()
        candidate = candidate_from_truth(truth)
        candidate["automatic_save"] = True
        result = score.score_case(candidate, truth)
        self.assertEqual(result["failed"], 1)
        self.assertEqual(result["declined"], 0)
        self.assertEqual(result["product_cells"], 18)
        self.assertEqual(score.score_case(None, truth)["failed"], 1)

    def test_unknown_conversion_earns_no_credit(self):
        truth = muesli_truth()
        candidate = candidate_from_truth(truth)
        for item in candidate["cells"]:
            if item["basis"] == "per_serving":
                item["serving_conversion"] = "unknown"
        self.assertEqual(score.score_case(candidate, truth)["conversions_exact"], 0)

    def test_conversion_ignores_whitespace_only(self):
        truth = muesli_truth()
        candidate = candidate_from_truth(truth)
        for item in candidate["cells"]:
            if item["basis"] == "per_serving":
                item["serving_conversion"] = "100 公克"
        self.assertEqual(score.score_case(candidate, truth)["conversions_exact"], 9)

    def test_extra_cell_breaks_full_table(self):
        truth = muesli_truth()
        candidate = candidate_from_truth(truth)
        extra = copy.deepcopy(candidate["cells"][0])
        extra.update({"nutrient": "unrecognised", "printed_label": "鈣", "row_id": "row_99"})
        candidate["cells"].append(extra)
        result = score.score_case(candidate, truth)
        self.assertEqual(result["extra_cells"], 1)
        self.assertEqual(result["tables_exact"], 0)

    def test_duplicate_basis_without_distinct_headers_never_earns_credit(self):
        truth = muesli_truth()
        truth["headers"][1]["basis"] = "per_serving"
        truth["headers"][1]["printed_text"] = "每份"
        for item in truth["cells"]:
            if item["header_id"] == "header_2":
                item["basis"] = "per_serving"
        result = score.score_case(candidate_from_truth(truth), truth)
        self.assertEqual(result["cells_exact"], 0)
        self.assertEqual(result["tables_exact"], 0)

    def test_reference_intake_is_not_a_product_cell(self):
        truth = muesli_truth()
        truth["headers"][1].update({"basis": "reference_intake", "printed_text": "每日參考值百分比"})
        for item in truth["cells"]:
            if item["header_id"] == "header_2":
                item.update({"basis": "reference_intake", "unit": "%", "canonical_unit": "%"})
        result = score.score_case(candidate_from_truth(truth), truth)
        self.assertEqual(result["product_cells"], 9)
        self.assertEqual(result["all_cells"], 18)


class AggregateTests(unittest.TestCase):
    def test_zero_denominator_is_never_a_pass(self):
        truth = muesli_truth()
        summary = score.aggregate([score.score_case(candidate_from_truth(truth), truth)], THRESHOLDS)
        self.assertEqual(summary["metrics"]["bounds"]["verdict"], "no_denominator")
        self.assertEqual(summary["metrics"]["correct_decline"]["verdict"], "no_denominator")
        self.assertEqual(summary["metrics"]["full_table"]["verdict"], "pass")

    def test_bars_come_from_the_contract(self):
        self.assertEqual(THRESHOLDS["numeric_cell_exact_minimum"], 0.95)
        self.assertEqual(THRESHOLDS["servings_per_pack_minimum"], 0.98)
        self.assertEqual(THRESHOLDS["false_ready_maximum"], 0)

    def test_one_false_ready_fails(self):
        truth = muesli_truth()
        candidate = candidate_from_truth(truth)
        cell(candidate, "sodium", "per_100g")["decimal_text"] = "80"
        cell(candidate, "sodium", "per_serving")["decimal_text"] = "80"
        summary = score.aggregate([score.score_case(candidate, truth)], THRESHOLDS)
        self.assertEqual(summary["metrics"]["false_ready"]["verdict"], "fail")


if __name__ == "__main__":
    unittest.main()
