"""Phase 3 (#255): owner answers, owner-verified truth, refill reasons and the route C mapping. Offline only."""

from __future__ import annotations

import json
import unittest

from helpers import HERE  # noqa: F401  (puts the harness folder on sys.path)

import acquire_off_taiwan  # noqa: E402
import candidate  # noqa: E402
import draft_untouched_truth as drafting  # noqa: E402
import route_c_mapping  # noqa: E402
import run_route_c  # noqa: E402

CASE = "off-taiwan:4710000000000:nutrition_zh.1"
PHOTO = {"barcode13": "4710000000000", "revision": "1", "order": 21, "sha256": "a" * 64}


def wire_draft() -> dict:
    return {
        "table_found": "taiwan_nutrition_label",
        "language": "zh-Hant",
        "serving_size_text": "每一份量30公克",
        "serving_size_uncertain": False,
        "servings_per_pack_text": "本包裝含4份",
        "servings_per_pack_uncertain": False,
        "headers": [
            {"header_id": "per_serving", "printed_text": "每份", "basis": "per_serving", "uncertain": False},
            {"header_id": "ri", "printed_text": "每日參考值百分比", "basis": "reference_intake", "uncertain": False},
        ],
        "rows": [
            {
                "printed_label": "熱量",
                "nutrient": "energy_kcal",
                "parent_nutrient": "energy",
                "label_uncertain": False,
                "values": [
                    {"header_id": "per_serving", "printed_text": "120大卡", "uncertain": False},
                    {"header_id": "ri", "printed_text": "6%", "uncertain": False},
                ],
            },
            {
                "printed_label": "脂肪",
                "nutrient": "fat",
                "parent_nutrient": "fat",
                "label_uncertain": False,
                "values": [{"header_id": "per_serving", "printed_text": "4公克", "uncertain": False}],
            },
            {
                "printed_label": "飽和脂肪",
                "nutrient": "saturates",
                "parent_nutrient": "fat",
                "label_uncertain": False,
                "values": [
                    {"header_id": "per_serving", "printed_text": "<0.5公克", "uncertain": False},
                    {"header_id": "ri", "printed_text": "*", "uncertain": False},
                ],
            },
        ],
        "notes": "none",
    }


def sheet_rows(draft: dict) -> list[dict[str, str]]:
    headers = {h["header_id"]: h for h in draft["headers"]}
    rows = [
        {
            "case_id": draft["case_id"],
            "row_id": c["row_id"],
            "header_id": c["header_id"],
            "header": headers[c["header_id"]]["printed_text"],
            "basis": c["basis"],
            "printed_label": c["printed_label"],
            "draft_printed_text": c["printed_text"],
            "owner_verified": "",
            "owner_correction": "",
            "merge_note": "",
        }
        for c in draft["cells"]
    ]
    for field, text in (
        ("serving_size", draft["serving_size"]["printed_text"]),
        ("servings_per_pack", draft["servings_per_pack"]["printed_text"]),
    ):
        rows.append({**{k: "" for k in rows[0]}, "case_id": draft["case_id"], "row_id": field, "draft_printed_text": text})
    rows.append(
        {
            **{k: "" for k in rows[0]},
            "case_id": draft["case_id"],
            "row_id": "table_decision",
            "draft_printed_text": "taiwan_nutrition_label -> usable",
        }
    )
    return rows


def all_ok(rows: list[dict[str, str]]) -> dict:
    return {
        "order": 21,
        "caseId": CASE,
        "cells": {f"{r['row_id']}|{r['header_id']}|{r['draft_printed_text']}": {"status": "ok"} for r in rows},
    }


class OwnerAnswerTests(unittest.TestCase):
    def setUp(self):
        self.draft = drafting.map_draft(wire_draft(), PHOTO, model="m", endpoint="e", drafted_on="2026-10-17")
        self.rows = sheet_rows(self.draft)

    def test_every_ok_answer_becomes_an_owner_verified_entry_through_the_merge(self):
        entries, decisions, problems = drafting.owner_entries_from_answers(self.rows, [all_ok(self.rows)])
        self.assertEqual(problems, [])
        self.assertEqual(decisions, {})
        merged, carried = drafting.merge_owner_entries([dict(r) for r in self.rows], entries)
        self.assertEqual(carried, len(self.rows))
        self.assertTrue(all(r["owner_verified"] == "yes" for r in merged))

    def test_unmatched_key_or_wrong_without_correction_is_a_problem(self):
        answer = all_ok(self.rows)
        answer["cells"]["fat|per_serving|5公克"] = {"status": "ok"}
        answer["cells"]["fat|per_serving|4公克"] = {"status": "wrong"}
        _, _, problems = drafting.owner_entries_from_answers(self.rows, [answer])
        self.assertEqual(len(problems), 2)

    def test_a_wrong_answer_with_a_correction_replaces_the_printed_text_in_truth(self):
        answer = all_ok(self.rows)
        answer["cells"]["fat|per_serving|4公克"] = {"status": "wrong", "correction": "4.5公克"}
        entries, _, problems = drafting.owner_entries_from_answers(self.rows, [answer])
        self.assertEqual(problems, [])
        merged, _ = drafting.merge_owner_entries([dict(r) for r in self.rows], entries)
        record = drafting.verified_record(self.draft, merged, verified_on="2026-10-17")
        assert record is not None
        fat = next(c for c in record["cells"] if c["row_id"] == "fat")
        self.assertEqual((fat["printed_text"], fat["decimal_text"]), ("4.5公克", "4.5"))
        self.assertEqual(record["review"]["pass_2"]["owner_corrections"], 1)
        self.assertEqual(record["review"]["evidence_label"], "model-drafted, owner-verified")

    def test_keep_over_an_exclusion_proposal_is_an_owner_correction(self):
        rows = [dict(r) for r in self.rows]
        rows[-1]["draft_printed_text"] = "other_language_nutrition_table -> exclude_and_refill"
        entries, decisions, problems = drafting.owner_entries_from_answers(
            rows, [{"order": 21, "caseId": CASE, "cells": {}, "decision": "keep"}]
        )
        self.assertEqual((problems, decisions), ([], {21: "keep"}))
        self.assertEqual(entries[0]["owner_correction"], "owner decision: keep")
        undrafted = drafting.owner_entries_from_answers(rows, [{"order": 23, "caseId": "other", "cells": {}, "decision": "exclude"}])
        self.assertEqual(undrafted[1], {23: "exclude"})


class VerifiedTruthTests(unittest.TestCase):
    def setUp(self):
        self.draft = drafting.map_draft(wire_draft(), PHOTO, model="m", endpoint="e", drafted_on="2026-10-17")
        self.rows = sheet_rows(self.draft)

    def verified(self, rows: list[dict[str, str]]) -> dict | None:
        entries, _, _ = drafting.owner_entries_from_answers(rows, [all_ok(rows)])
        merged, _ = drafting.merge_owner_entries([dict(r) for r in rows], entries)
        return drafting.verified_record(self.draft, merged, verified_on="2026-10-17")

    def test_unchecked_rows_keep_the_case_pending(self):
        self.assertIsNone(drafting.verified_record(self.draft, self.rows, verified_on="2026-10-17"))

    def test_parents_are_structural_and_non_amounts_are_unscored(self):
        record = self.verified(self.rows)
        assert record is not None
        parents = {c["row_id"]: c["parent_row_id"] for c in record["cells"]}
        self.assertEqual(parents, {"energy_kcal": None, "fat": None, "saturates": "fat"})
        self.assertEqual(record["review"]["structural_parent_cells_cleared"], 3)
        self.assertEqual([u["printed_text"] for u in record["unscored_cells"]], ["*"])
        self.assertEqual(record["review"]["evidence_label"], "model-drafted, owner-verified (no owner corrections)")
        bound = next(c for c in record["cells"] if c["row_id"] == "saturates")
        self.assertEqual((bound["comparator"], bound["decimal_text"]), ("<", "0.5"))
        self.assertIn("bound", record["coverage_tags"])
        self.assertIn("reference_intake_column", record["coverage_tags"])
        self.assertNotIn("parsed", record["cells"][0])

    def test_confirmed_exclusion_needs_only_the_decision(self):
        draft = {
            **self.draft,
            "proposal": "exclude_and_refill",
            "table_found": "other_language_nutrition_table",
            "cells": [],
            "headers": [],
        }
        rows = [r for r in self.rows if r["row_id"] in ("serving_size", "servings_per_pack", "table_decision")]
        rows[-1] = {**rows[-1], "owner_verified": "yes"}
        record = drafting.verified_record(draft, rows, verified_on="2026-10-17")
        assert record is not None
        self.assertTrue(record["excluded"])
        self.assertEqual(record["cells"], [])

    def test_kept_table_without_cells_waits_for_a_redraft(self):
        draft = {**self.draft, "proposal": "exclude_and_refill", "cells": []}
        rows = [{**r, "owner_correction": "owner decision: keep"} if r["row_id"] == "table_decision" else r for r in self.rows[-3:]]
        self.assertIsNone(drafting.verified_record(draft, rows, verified_on="2026-10-17"))

    def test_committed_untouched_truth_is_owner_verified_with_no_corrections(self):
        truth = json.loads((HERE / "fixtures" / "ground-truth-off-taiwan-untouched-v1.json").read_text())
        self.assertEqual(truth["evidence_label"], "model-drafted, owner-verified (no owner corrections)")
        self.assertEqual(truth["counts"]["owner_corrections"], 0)
        self.assertIn("anchoring", truth["anchoring_note"])
        for record in truth["records"]:
            for cell in record["cells"]:
                self.assertEqual(
                    candidate._collect(
                        {**cell, "persistence_authorized": False, "requires_user_selection": True},
                        candidate.schema()["$defs"]["cell"],
                        "cell",
                    ),
                    [],
                )


class RefillReasonTests(unittest.TestCase):
    def test_one_reason_per_replaced_order(self):
        self.assertEqual(acquire_off_taiwan.refill_reasons([4, 17], "English", []), {4: "English", 17: "English"})
        self.assertEqual(acquire_off_taiwan.refill_reasons([23, 25], None, ["23=failed", "25=English"]), {23: "failed", 25: "English"})
        self.assertIsNone(acquire_off_taiwan.refill_reasons([23, 25], None, ["23=failed"]))
        self.assertIsNone(acquire_off_taiwan.refill_reasons([23], "x", ["23=y"]))
        self.assertIsNone(acquire_off_taiwan.refill_reasons([23], None, ["23="]))

    def test_untouched_refill_total_stop_matches_the_contract(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        self.assertEqual(
            acquire_off_taiwan.UNTOUCHED_REFILL_TOTAL_STOP_BYTES,
            contract["corpus"]["off_taiwan"]["refill_rule"]["untouched_total_stop_bytes"],
        )


def wire_route_c() -> dict:
    return {
        "declined": False,
        "decline_reasons": [],
        "language": "zh-Hant",
        "serving_size_text": "每一份量100公克",
        "servings_per_pack_text": "本包裝含5份",
        "headers": [
            {"header_id": "h1", "printed_text": "每份", "basis": "per_serving"},
            {"header_id": "h2", "printed_text": "每100公克", "basis": "per_100g"},
        ],
        "rows": [
            {"printed_label": "熱量", "nutrient": "energy_kcal", "parent_nutrient": "none", "values": [
                {"header_id": "h1", "printed_text": "367.2大卡"}, {"header_id": "h2", "printed_text": "367.2大卡"}]},
            {"printed_label": "脂肪", "nutrient": "fat", "parent_nutrient": "fat", "values": [
                {"header_id": "h1", "printed_text": "8.8公克"}, {"header_id": "h2", "printed_text": "8.8公克"}]},
            {"printed_label": "飽和脂肪", "nutrient": "saturates", "parent_nutrient": "fat", "values": [
                {"header_id": "h1", "printed_text": "1.2公克"}, {"header_id": "h2", "printed_text": "1.2公克"}]},
        ],
    }  # fmt: skip


class RouteCMappingTests(unittest.TestCase):
    def test_maps_to_a_schema_valid_candidate_that_would_be_ready(self):
        mapped = route_c_mapping.map_wire(wire_route_c(), "b" * 64)
        self.assertEqual(candidate.validate_candidate(mapped), [])
        self.assertTrue(mapped["would_mark_ready"])
        self.assertFalse(mapped["ready_for_confirmation"] or mapped["automatic_save"])
        parents = {c["row_id"]: c["parent_row_id"] for c in mapped["cells"]}
        self.assertEqual(parents, {"energy_kcal": None, "fat": None, "saturates": "fat"})
        self.assertEqual(mapped["serving_size"]["decimal_text"], "100")
        self.assertEqual(mapped["servings_per_pack"]["decimal_text"], "5")
        self.assertTrue(all(c["serving_conversion"] == "100公克" for c in mapped["cells"] if c["basis"] == "per_serving"))

    def test_unknown_or_unread_values_are_left_out_and_block_ready(self):
        wire = wire_route_c()
        wire["rows"][1]["values"][0]["printed_text"] = "unknown"
        mapped = route_c_mapping.map_wire(wire, "b" * 64)
        self.assertEqual(candidate.validate_candidate(mapped), [])
        self.assertFalse(mapped["would_mark_ready"])
        self.assertEqual(len(mapped["cells"]), 5)
        self.assertTrue(any(w.startswith("value_not_read") for w in mapped["warnings"]))

    def test_value_under_an_undeclared_header_blocks_ready(self):
        wire = wire_route_c()
        wire["rows"][0]["values"][0]["header_id"] = "h9"
        self.assertFalse(route_c_mapping.map_wire(wire, "b" * 64)["would_mark_ready"])

    def test_per_serving_without_a_printed_quantity_blocks_ready(self):
        wire = wire_route_c()
        wire["serving_size_text"] = "unknown"
        mapped = route_c_mapping.map_wire(wire, "b" * 64)
        self.assertFalse(mapped["would_mark_ready"])
        self.assertTrue(all(c["serving_conversion"] == "unknown" for c in mapped["cells"] if c["basis"] == "per_serving"))

    def test_decline_keeps_everything_unknown(self):
        mapped = route_c_mapping.map_wire({**wire_route_c(), "declined": True, "decline_reasons": ["no_table"]}, "b" * 64)
        self.assertEqual(candidate.validate_candidate(mapped), [])
        self.assertEqual((mapped["cells"], mapped["serving_size"], mapped["would_mark_ready"]), ([], "unknown", False))

    def test_english_servings_per_pack(self):
        for text, expected in (("about 8 servings per container", "8"), ("This pack contains 10 servings", "10")):
            parsed = route_c_mapping._servings_per_pack(text)
            assert isinstance(parsed, dict)
            self.assertEqual(parsed["decimal_text"], expected)
        self.assertEqual(route_c_mapping._servings_per_pack("unknown"), "unknown")


class RouteCRunnerTests(unittest.TestCase):
    def test_percentiles_and_unknown_costs(self):
        rows = [{"cost_usd": "0.01", "latency_seconds": s} for s in (1, 2, 3, 4, 10)] + [{"cost_usd": None, "latency_seconds": 5}]
        stats = run_route_c.call_stats(rows)
        self.assertEqual(stats["unknown_cost_calls"], 1)
        self.assertEqual(stats["reported_cost_usd"], "0.05")
        self.assertEqual(stats["latency_p50_seconds"], 3.5)
        self.assertEqual(stats["latency_p90_seconds"], 10)
        self.assertIsNone(run_route_c.percentile([], 0.9))

    def test_pinned_targets_come_from_the_contract(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        luna = run_route_c.pinned_target(contract, "luna")
        self.assertEqual(
            (luna.model, luna.endpoint, luna.provider_name, luna.reasoning_effort), ("openai/gpt-6-luna", "azure", "Azure", "none")
        )
        self.assertIsNone(run_route_c.pinned_target(contract, "opus").reasoning_effort)


if __name__ == "__main__":
    unittest.main()
