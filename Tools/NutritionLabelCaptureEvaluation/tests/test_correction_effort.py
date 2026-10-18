"""Correction-effort analysis (#255, post-freeze addition). Pure; synthetic fixtures only."""

from __future__ import annotations

import copy
import unittest
from typing import Any

import helpers

import correction_effort as effort
import decline_gate

TAIWAN = decline_gate.TAIWAN


def truth() -> dict[str, Any]:
    return helpers.muesli_truth()


def candidate(record: dict[str, Any] | None = None) -> dict[str, Any]:
    return helpers.candidate_from_truth(record or truth())


def cell(table: dict[str, Any], nutrient: str, basis: str) -> dict[str, Any]:
    (found,) = [c for c in table["cells"] if c["nutrient"] == nutrient and c["basis"] == basis]
    return found


def assisted(output: dict[str, Any] | None, record: dict[str, Any] | None = None) -> dict[str, Any]:
    presented, report = effort.assisted_view(output, TAIWAN)
    return effort.label_effort(presented, record or truth(), report)


def as_run(output: dict[str, Any] | None, record: dict[str, Any] | None = None) -> dict[str, Any]:
    presented, report = effort.as_run_view(output, TAIWAN)
    return effort.label_effort(presented, record or truth(), report)


class CellEdits(unittest.TestCase):
    def test_exact_table_needs_no_edit(self) -> None:
        result = assisted(candidate())
        self.assertEqual(result["edits"], 0)
        self.assertFalse(result["silent_error"])
        self.assertEqual((result["serving_size"], result["servings_per_pack"]), ("ok", "ok"))

    def test_wrong_value_is_one_silent_correction(self) -> None:
        output = candidate()
        cell(output, "protein", "per_100g")["decimal_text"] = "1.1"
        result = assisted(output)
        self.assertEqual(result["corrections_by_type"], {"value": 1, "unit": 0, "binding": 0})
        self.assertEqual(result["edits"], 1)
        self.assertTrue(result["silent_error"])
        self.assertEqual(result["silent_rows"], ["protein"])

    def test_wrong_unit_is_a_unit_correction(self) -> None:
        output = candidate()
        target = cell(output, "sodium", "per_100g")
        target.update({"unit": "公克", "canonical_unit": "g"})
        self.assertEqual(assisted(output)["corrections_by_type"], {"value": 0, "unit": 1, "binding": 0})

    def test_right_value_under_the_wrong_parent_is_one_binding_correction_per_cell(self) -> None:
        output = candidate()
        for basis in ("per_serving", "per_100g"):
            cell(output, "saturates", basis)["parent_row_id"] = None
        result = assisted(output)
        self.assertEqual(result["corrections_by_type"], {"value": 0, "unit": 0, "binding": 2})
        self.assertEqual((result["fills"], result["removals"]), (0, 0))

    def test_right_value_in_the_wrong_column_is_a_binding_correction(self) -> None:
        record = truth()
        record["cells"] = [c for c in record["cells"] if not (c["nutrient"] == "fibre" and c["basis"] == "per_100g")]
        output = candidate(record)
        moved = cell(output, "fibre", "per_serving")
        moved.update({"basis": "per_100g", "header_id": "header_2", "serving_conversion": "not_applicable"})
        result = assisted(output, record)
        self.assertEqual(result["corrections_by_type"]["binding"], 1)
        self.assertEqual((result["fills"], result["removals"]), (0, 0))

    def test_unread_cell_is_a_visible_fill_not_a_correction(self) -> None:
        output = candidate()
        # Route C's mapping leaves an unread value out of the cells (`route_c_mapping.map_wire`).
        output["cells"] = [c for c in output["cells"] if not (c["nutrient"] == "fibre" and c["basis"] == "per_100g")]
        result = assisted(output)
        self.assertEqual((result["corrections"], result["fills"], result["edits"]), (0, 1, 1))
        self.assertFalse(result["silent_error"])
        self.assertFalse(result["silent_omission"])

    def test_row_left_out_entirely_is_a_silent_omission(self) -> None:
        output = candidate()
        output["cells"] = [c for c in output["cells"] if c["nutrient"] != "fibre"]
        result = assisted(output)
        self.assertEqual(result["fills"], 2)
        self.assertFalse(result["silent_error"])
        self.assertEqual(result["unflagged_missing_rows"], ["fibre"])

    def test_invented_value_is_a_silent_removal(self) -> None:
        output = candidate()
        extra = copy.deepcopy(cell(output, "sugars", "per_serving"))
        extra.update({"row_id": "added_sugars", "nutrient": "added_sugars", "printed_label": "添加糖"})
        output["cells"].append(extra)
        result = assisted(output)
        self.assertEqual((result["removals"], result["edits"]), (1, 1))
        self.assertEqual(result["silent_rows"], ["added_sugars"])

    def test_reference_intake_cell_is_not_a_removal_when_the_truth_did_not_transcribe_it(self) -> None:
        record = truth()
        record["reference_intake_transcribed"] = False
        output = candidate(record)
        extra = copy.deepcopy(cell(output, "protein", "per_100g"))
        extra.update({"basis": "reference_intake", "header_id": "ri", "unit": "%", "canonical_unit": "%"})
        output["cells"].append(extra)
        self.assertEqual(assisted(output, record)["removals"], 0)


class ServingLines(unittest.TestCase):
    def test_wrong_serving_size_is_a_silent_correction(self) -> None:
        output = candidate()
        output["serving_size"]["decimal_text"] = "10"
        result = assisted(output)
        self.assertEqual(result["serving_size"], "correction")
        self.assertTrue(result["silent_error"])
        self.assertIn("serving_size", result["silent_rows"])

    def test_unread_serving_line_is_a_flagged_fill(self) -> None:
        output = candidate()
        output["servings_per_pack"] = "unknown"
        result = assisted(output)
        self.assertEqual((result["servings_per_pack"], result["serving_line_edits"]), ("fill", 1))
        self.assertFalse(result["silent_error"])

    def test_invented_servings_per_pack_is_a_removal(self) -> None:
        record = truth()
        record["servings_per_pack"] = "unknown"
        output = candidate(truth())
        self.assertEqual(assisted(output, record)["servings_per_pack"], "removal")

    def test_uk_review_without_serving_lines_is_not_scored(self) -> None:
        record = truth()
        record.update({"serving_size": "unknown", "servings_per_pack": "not_recorded"})
        result = assisted(candidate(truth()), record)
        self.assertEqual((result["serving_size"], result["servings_per_pack"]), ("not_scored", "not_scored"))


class Views(unittest.TestCase):
    def test_missing_mandatory_row_declines_as_run_but_is_a_flag_in_the_assisted_view(self) -> None:
        output = candidate()
        output["cells"] = [c for c in output["cells"] if c["nutrient"] != "sodium"]
        run = as_run(output)
        self.assertEqual(run["hard_decline"], "gate:required_row_missing")
        self.assertEqual((run["cells_to_type"], run["serving_lines_to_type"]), (18, 2))
        self.assertIsNone(run["edits"])
        help_ = assisted(output)
        self.assertIsNone(help_["hard_decline"])
        self.assertEqual(help_["fills"], 2)
        self.assertEqual(help_["unflagged_missing_rows"], [], "the G3 flag marks the sodium row")

    def test_wrong_value_in_a_flagged_row_is_not_silent(self) -> None:
        output = candidate()
        output["cells"] = [c for c in output["cells"] if not (c["nutrient"] == "fat" and c["basis"] == "per_100g")]
        cell(output, "fat", "per_serving")["decimal_text"] = "88"
        result = assisted(output)
        self.assertEqual((result["corrections"], result["fills"]), (1, 1))
        self.assertFalse(result["silent_error"], "G4 flags the fat row")

    def test_hard_declines_of_the_assisted_design(self) -> None:
        simplified = candidate()
        cell(simplified, "energy_kcal", "per_serving")["printed_label"] = "热量"
        self.assertEqual(effort.assisted_view(simplified, TAIWAN)[1]["hard_decline"], "gate:unsupported_script")
        self.assertEqual(effort.assisted_view(helpers.declined_candidate(), TAIWAN)[1]["hard_decline"], "route_declined")
        self.assertEqual(effort.assisted_view(None, TAIWAN)[1]["hard_decline"], "failed_output")
        self.assertEqual(effort.assisted_view({"schema_version": "x"}, TAIWAN)[1]["hard_decline"], "failed_output")

    def test_views_never_change_a_value(self) -> None:
        output = candidate()
        output["serving_size"] = "unknown"
        before = copy.deepcopy(output)
        presented, _ = effort.assisted_view(output, TAIWAN)
        self.assertEqual(output, before)
        assert presented is not None
        self.assertEqual(presented["cells"], before["cells"])


class Summary(unittest.TestCase):
    def label(self, case_id: str, edits: int | None, declined: str | None = None) -> dict[str, Any]:
        result = assisted(candidate())
        result.update({"edits": edits, "hard_decline": declined, "cells_to_type": 18 if declined else 0})
        return {"id": case_id, "effort": result, "flags": []}

    def test_distribution_median_and_p90(self) -> None:
        labels = [self.label(f"c{i}", value) for i, value in enumerate([0, 0, 0, 1, 2, 3, 6, 9])]
        labels.append(self.label("d", None, "route_declined"))
        summary = effort.summarise(labels)
        dist = summary["distribution"]
        self.assertEqual([dist[name]["tables"] for name in (*effort.BUCKETS, "whole_table_by_hand")], [3, 2, 1, 2, 1])
        self.assertEqual(summary["median_edits_per_prefilled_table"], 1.5)
        self.assertEqual(summary["p90_edits_per_prefilled_table"], 9)
        self.assertEqual(summary["total_edits_prefilled"], 21)
        self.assertEqual(
            summary["hard_declines"],
            {"tables": 1, "reasons": {"route_declined": 1}, "cells_to_type": 18, "serving_lines_to_type": 0, "ids": ["d"]},
        )

    def test_nearest_rank(self) -> None:
        self.assertIsNone(effort.nearest_rank([], 0.9))
        self.assertEqual(effort.nearest_rank([5], 0.9), 5)
        self.assertEqual(effort.nearest_rank(list(range(10)), 0.9), 8)

    def test_usable_excludes_declines_and_exclusions(self) -> None:
        self.assertTrue(effort.usable(truth()))
        for flag in ("excluded", "requires_decline", "excluded_from_scoring"):
            self.assertFalse(effort.usable({**truth(), flag: True}))


if __name__ == "__main__":
    unittest.main()
