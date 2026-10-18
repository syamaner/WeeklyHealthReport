"""Phase 3 (#255): owner answers, owner-verified truth, refill reasons and the route C mapping. Offline only."""

from __future__ import annotations

import json
import random
import tempfile
import unittest
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path

from helpers import HERE  # noqa: F401  (puts the harness folder on sys.path)

import acquire_off_taiwan  # noqa: E402
import candidate  # noqa: E402
import draft_untouched_truth as drafting  # noqa: E402
import openrouter_client  # noqa: E402
import route_c_mapping  # noqa: E402
import run_route_c  # noqa: E402
from budget import (  # noqa: E402
    REJECTED_ERROR_KIND,
    RETRYABLE_ERROR_KIND,
    BudgetStop,
    LedgerBudget,
    contract_limits,
    sealed_projection_check,
)

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

    def test_mechanical_nutrient_mapping_is_exact_only(self):
        self.assertEqual(drafting.mechanical_nutrient("Sodium/鈉"), "sodium")
        self.assertEqual(drafting.mechanical_nutrient("鈉"), "sodium")
        self.assertIsNone(drafting.mechanical_nutrient("Total Fat/總脂肪"))  # contains 脂肪 but is not the row name
        self.assertIsNone(drafting.mechanical_nutrient("Includes 0 g Added Sugars /添加糖"))
        self.assertIsNone(drafting.mechanical_nutrient("Calcium /鈣"))

    def test_unit_less_values_stay_as_printed_and_ungradable(self):
        wire = wire_draft()
        wire["rows"][0]["values"][0]["printed_text"] = "100"
        wire["rows"].append(
            {
                "printed_label": "Sodium/鈉",
                "nutrient": "unrecognised",
                "parent_nutrient": "none",
                "label_uncertain": False,
                "values": [{"header_id": "per_serving", "printed_text": "0mg", "uncertain": False}],
            }
        )
        draft = drafting.map_draft(wire, PHOTO, model="m", endpoint="e", drafted_on="2026-10-17")
        rows = sheet_rows(draft)
        entries, _, _ = drafting.owner_entries_from_answers(rows, [all_ok(rows)])
        merged, _ = drafting.merge_owner_entries([dict(r) for r in rows], entries)
        record = drafting.verified_record(draft, merged, verified_on="2026-10-17")
        assert record is not None
        energy = next(u for u in record["unscored_cells"] if u["printed_text"] == "100")
        self.assertIn("no unit inferred", energy["reason"])
        self.assertFalse(any(c["row_id"] == "energy_kcal" and c["basis"] == "per_serving" for c in record["cells"]))
        sodium = next(c for c in record["cells"] if c["printed_label"] == "Sodium/鈉")
        self.assertEqual((sodium["nutrient"], sodium["row_id"]), ("sodium", "sodium"))
        self.assertEqual(record["review"]["mechanical_nutrient_mappings"][0]["nutrient"], "sodium")

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
        # Phase 5: three owner corrections after the untouched run, a recorded deviation.
        self.assertEqual(
            truth["evidence_label"], "model-drafted, owner-verified (3 owner corrections after the untouched run, 18 October 2026)"
        )
        self.assertEqual(truth["counts"]["owner_corrections"], 3)
        self.assertIn("unknown error rate", truth["post_run_correction_note"])
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

    def test_credit_gate_uses_the_smaller_of_key_and_account_credit(self):
        # 17 October 2026: the key had $58 left but the account only $0.76, and OpenRouter answered 402.
        credit = {"limit_remaining": 58.43, "account_remaining": 0.76, "available": 0.76}
        allowed, needed = run_route_c.credit_gate(credit, Decimal("3.3"))
        self.assertFalse(allowed)
        self.assertEqual(needed, Decimal("4.3"))  # projection plus the $1 minimum margin
        self.assertTrue(run_route_c.credit_gate({"available": 20.0}, Decimal("8.3"))[0])  # 8.3 + 2.075 margin
        self.assertFalse(run_route_c.credit_gate({"available": 20.0}, Decimal("8.3"), reserve_usd=Decimal("40"))[0])
        self.assertFalse(run_route_c.credit_gate({"available": None}, Decimal("0.1"))[0])  # unknown credit refuses

    def test_credit_lookup_failure_makes_available_unknown_so_the_gate_refuses(self):
        key = {"limit": 75, "limit_remaining": 58.4, "usage": 16.6}
        credits = {"total_credits": 190, "total_usage": 119.3}
        self.assertAlmostEqual(run_route_c.credit_from(key, credits)["available"], 58.4)
        failed = run_route_c.credit_from(key, {"error": "URLError"})  # /credits errors
        self.assertIsNone(failed["available"])
        self.assertFalse(run_route_c.credit_gate(failed, Decimal("0.1"))[0])
        self.assertIsNone(run_route_c.credit_from({"error": "HTTPError"}, credits)["available"])  # /key errors
        self.assertIsNone(run_route_c.credit_from(key, {"total_credits": "190", "total_usage": 119.3})["available"])
        self.assertIsNone(run_route_c.credit_from({**key, "limit_remaining": None}, credits)["available"])
        unlimited = run_route_c.credit_from({"limit": None, "limit_remaining": None}, credits)  # explicit null limit
        self.assertAlmostEqual(unlimited["available"], 70.7)

    def test_pinned_targets_come_from_the_contract(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        luna = run_route_c.pinned_target(contract, "luna", "off")
        self.assertEqual((luna.model, luna.endpoint, luna.provider_name, luna.reasoning), ("openai/gpt-6-luna", "openai", "OpenAI", "off"))
        self.assertEqual(luna.label, "luna-reasoning-off")
        self.assertEqual(run_route_c.pinned_target(contract, "opus", "on").reasoning, "on")
        with self.assertRaisesRegex(SystemExit, "not a pinned setting"):
            run_route_c.pinned_target(contract, "opus", "low")


NOW = datetime(2026, 10, 17, 12, 0, 0, tzinfo=UTC)


def scripted(replies: list[tuple[int, dict | None, dict[str, str]]]):  # noqa: ANN201
    sent: list[float] = []

    def post(body: dict, timeout: float):  # noqa: ANN202
        sent.append(timeout)
        status, payload, headers = replies[len(sent) - 1]
        return status, payload, headers, 0.5

    return post, sent


class FakeClock:
    def __init__(self) -> None:
        self.t = 0.0
        self.sleeps: list[float] = []

    def __call__(self) -> float:
        return self.t

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.t += seconds


OK_BODY = {"id": "gen-1", "model": "m", "usage": {"cost": 0.01}, "choices": [{"finish_reason": "stop", "message": {"content": "{}"}}]}


class RetryPolicyTests(unittest.TestCase):
    def call(self, replies, policy=openrouter_client.DEFAULT_POLICY):  # noqa: ANN001, ANN201
        post, sent = scripted(replies)
        clock = FakeClock()
        attempts: list = []
        result = openrouter_client.call_with_retry(
            {}, post, policy=policy, sleep=clock.sleep, clock=clock, now=lambda: NOW, rng=random.Random(1), on_attempt=attempts.append
        )
        return result, clock, attempts, sent

    def test_retry_after_seconds(self):
        self.assertEqual(openrouter_client.parse_retry_after("7", NOW), 7.0)
        self.assertIsNone(openrouter_client.parse_retry_after("soon", NOW))
        result, clock, _, _ = self.call([(429, None, {"Retry-After": "7"}), (200, OK_BODY, {})])
        self.assertEqual(result.status, 200)
        self.assertGreaterEqual(clock.sleeps[0], 7.0)

    def test_retry_after_http_date(self):
        self.assertEqual(openrouter_client.parse_retry_after("Sat, 17 Oct 2026 12:00:12 GMT", NOW), 12.0)
        self.assertEqual(openrouter_client.parse_retry_after("Sat, 17 Oct 2026 11:00:00 GMT", NOW), 0.0)
        result, clock, _, _ = self.call([(503, None, {"retry-after": "Sat, 17 Oct 2026 12:00:12 GMT"}), (200, OK_BODY, {})])
        self.assertEqual(result.retries, 1)
        self.assertGreaterEqual(clock.sleeps[0], 12.0)

    def test_429_then_success(self):
        result, clock, attempts, _ = self.call([(429, {"error": {"code": 429, "message": "rate limited"}}, {}), (200, OK_BODY, {})])
        self.assertEqual((result.status, result.exhausted, result.retries, len(attempts)), (200, False, 1, 2))
        self.assertTrue(attempts[0].retryable and not attempts[1].retryable)
        self.assertLessEqual(clock.sleeps[0], openrouter_client.DEFAULT_POLICY.base_seconds)  # first jittered wait

    def test_503_exhausted_after_five_attempts(self):
        result, clock, attempts, _ = self.call([(503, None, {})] * 5)
        self.assertTrue(result.exhausted)
        self.assertEqual(len(attempts), 5)
        self.assertEqual(len(clock.sleeps), 4)
        self.assertIn("5 attempts", result.cause or "")

    def test_deadline_bounds_the_call(self):
        policy = openrouter_client.RetryPolicy(max_attempts=5, deadline_seconds=10)
        result, _, attempts, sent = self.call([(429, None, {"Retry-After": "30"})] * 5, policy)
        self.assertTrue(result.exhausted)
        self.assertEqual(len(attempts), 1)  # waiting 30 s would pass the 10 s deadline
        self.assertLessEqual(sent[0], 10)  # the socket timeout is the time left

    def test_transport_errors_and_overloaded_providers_are_retried(self):
        self.assertEqual(openrouter_client.classify(0, None)[0], True)
        for status in (408, 429, 500, 502, 503, 504, 529):
            self.assertTrue(openrouter_client.classify(status, None)[0], status)
        self.assertTrue(openrouter_client.classify(200, {"error": {"code": 502, "message": "Provider returned error"}})[0])
        self.assertTrue(openrouter_client.classify(400, {"error": {"message": "Provider is overloaded"}})[0])

    def test_content_outcomes_and_other_errors_are_never_retried(self):
        for status, body in (
            (200, {**OK_BODY, "choices": [{"finish_reason": "length", "message": {"content": "{"}}]}),  # truncation
            (200, {**OK_BODY, "model": "someone/else"}),  # identity mismatch
            (200, {**OK_BODY, "choices": [{"finish_reason": "stop", "message": {"content": "not json"}}]}),  # schema failure
            (400, {"error": {"code": 400, "message": "invalid schema"}}),
            (402, {"error": {"code": 402, "message": "insufficient credit"}}),
        ):
            result, clock, attempts, _ = self.call([(status, body, {})])
            self.assertEqual((len(attempts), clock.sleeps, result.exhausted), (1, [], False), status)


class LedgerRetryAndLimitTests(unittest.TestCase):
    def test_retryable_unknown_costs_do_not_count_toward_the_stop(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            ledger = LedgerBudget(path)
            for number in range(5):
                ledger.before_call("m")
                ledger.record_call("m", None, purpose="p", case_id="c", at="t", kind=RETRYABLE_ERROR_KIND, attempt=number + 1)
            self.assertEqual(LedgerBudget(path).unknown_cost_calls, 0)
            LedgerBudget(path).before_call("m")  # still allowed
            LedgerBudget(path).record_call("m", None, purpose="p", case_id="c", at="t")  # an HTTP 200 answer without a cost
            self.assertEqual(LedgerBudget(path).unknown_cost_calls, 1)

    def test_attempt_kinds(self):
        rejected = {"error": {"code": 400, "message": "Reasoning is mandatory for this endpoint and cannot be disabled."}}
        self.assertEqual(openrouter_client.attempt_kind(400, rejected, False), REJECTED_ERROR_KIND)
        self.assertEqual(openrouter_client.attempt_kind(429, None, True), RETRYABLE_ERROR_KIND)
        self.assertEqual(openrouter_client.attempt_kind(0, None, True), RETRYABLE_ERROR_KIND)
        self.assertIsNone(openrouter_client.attempt_kind(400, {**rejected, "id": "gen-1"}, False))  # a generation exists
        self.assertIsNone(openrouter_client.attempt_kind(400, {**rejected, "usage": {"prompt_tokens": 9}}, False))
        self.assertIsNone(openrouter_client.attempt_kind(200, {"choices": []}, False))  # an HTTP 200 without a cost still counts
        self.assertIsNone(openrouter_client.attempt_kind(500, {"id": "gen-2"}, True))

    def test_rejections_without_a_generation_do_not_count_but_a_200_without_cost_does(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            for _ in range(4):
                LedgerBudget(path).before_call("grok")
                LedgerBudget(path).record_call("grok", None, purpose="p", case_id="q", at="t", kind=REJECTED_ERROR_KIND)
            self.assertEqual(LedgerBudget(path).unknown_cost_calls, 0)
            LedgerBudget(path).before_call("grok")
            LedgerBudget(path).record_call("grok", None, purpose="p", case_id="q", at="t")
            self.assertEqual(LedgerBudget(path).unknown_cost_calls, 1)

    def test_existing_entries_are_relabelled_only_through_a_recorded_amendment(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            for cost in (None, Decimal("0.01"), None):
                LedgerBudget(path).before_call("grok")
                LedgerBudget(path).record_call("grok", cost, purpose="p", case_id="q", at="t")
            self.assertEqual(LedgerBudget(path).unknown_cost_calls, 2)
            with self.assertRaises(BudgetStop):  # an entry with a reported cost is never relabelled
                LedgerBudget.relabel_entries(path, [1], REJECTED_ERROR_KIND, at="t", reason="r", evidence=[])
            with self.assertRaises(BudgetStop):  # only to a kind excluded from the stop
                LedgerBudget.relabel_entries(path, [0], "anything", at="t", reason="r", evidence=[])
            LedgerBudget.relabel_entries(path, [0, 2], REJECTED_ERROR_KIND, at="t", reason="owner decision", evidence=[{"entry": 0}])
            ledger = LedgerBudget(path)
            self.assertEqual(ledger.unknown_cost_calls, 0)
            self.assertEqual(ledger.amendments[0]["relabelled_entries"], [0, 2])
            self.assertEqual(ledger.reported_spend_usd, Decimal("0.01"))

    def test_relabel_refuses_bad_indices_and_unlooked_generations_and_recounts(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            LedgerBudget(path).before_call("m")
            LedgerBudget(path).record_call("m", None, purpose="p", case_id="q", at="t", generation_id="gen-9")
            LedgerBudget(path).before_call("m")
            LedgerBudget(path).record_call("m", None, purpose="p", case_id="q", at="t")
            bad_indices: list[list[int]] = [[-1], [2], [True]]  # True is a bool, not an index
            for bad in bad_indices:
                with self.assertRaises(BudgetStop):
                    LedgerBudget.relabel_entries(path, bad, REJECTED_ERROR_KIND, at="t", reason="r", evidence=[])
            with self.assertRaises(BudgetStop):  # a generation id needs a lookup result in the evidence
                LedgerBudget.relabel_entries(path, [0], REJECTED_ERROR_KIND, at="t", reason="r", evidence=[])
            LedgerBudget.relabel_entries(
                path, [0, 1], REJECTED_ERROR_KIND, at="t", reason="r", evidence=[{"entry": 0, "generation_lookup": "not_found"}]
            )
            raw = json.loads(path.read_text())
            self.assertEqual(raw["unknown_cost_calls"], 0)  # the stored counter is recomputed on write
            self.assertEqual(raw["unknown_cost_calls"], LedgerBudget(path).unknown_cost_calls)

    def test_close_open_call_accepts_only_known_kinds_and_records_an_amendment(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            LedgerBudget(path).before_call("luna")
            with self.assertRaises(BudgetStop):
                LedgerBudget(path).close_open_call("luna", None, purpose="p", case_id="c", at="t", kind="anything")
            LedgerBudget(path).close_open_call(
                "luna", Decimal("0.05"), purpose="p", case_id="c", at="t", kind="unreconciled_in_flight_ceiling_charge"
            )
            ledger = LedgerBudget(path)
            self.assertEqual(ledger.amendments[-1]["kind"], "unreconciled_in_flight_ceiling_charge")

    def test_limits_change_only_through_a_recorded_amendment(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            LedgerBudget(path)
            new = {"per_call_usd": "0.2", "total_usd": "60", "unknown_cost_calls_allowed": 3, "sealed_reserved_calls": 200}
            new["sealed_reserved_per_call_usd"] = "0.20"
            with self.assertRaises(BudgetStop):
                LedgerBudget(path, limits=new)
            LedgerBudget.amend_limits(path, new, at="2026-10-17", reason="owner decision")
            ledger = LedgerBudget(path, limits=new)
            self.assertEqual(ledger.reserved_usd, Decimal("40.00"))
            self.assertEqual(ledger.limits_history[0]["reason"], "owner decision")

    def test_contract_limits_hold_back_forty_dollars_and_leave_twenty_five(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        limits = contract_limits(contract)
        self.assertEqual((limits["per_call_usd"], limits["total_usd"], limits["sealed_reserved_per_call_usd"]), (0.2, 65, "0.20"))
        with tempfile.TemporaryDirectory() as folder:
            ledger = LedgerBudget(Path(folder) / "ledger.json", limits=limits)
            self.assertEqual(ledger.total_usd - ledger.reserved_usd, Decimal("25.00"))

    def test_sealed_run_stops_before_it_starts_when_the_budget_cannot_cover_it(self):
        self.assertEqual(sealed_projection_check(Decimal("19"), Decimal("0"), Decimal("60"), Decimal("0.20"), 200), Decimal("40.00"))
        with self.assertRaises(BudgetStop):
            sealed_projection_check(Decimal("21"), Decimal("0"), Decimal("60"), Decimal("0.20"), 200)

    def test_open_in_flight_call_can_be_closed_with_a_recorded_charge(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            LedgerBudget(path).before_call("luna")
            LedgerBudget(path).close_open_call(
                "luna", Decimal("0.05"), purpose="p", case_id="unknown", at="t", kind="unreconciled_in_flight_ceiling_charge"
            )
            ledger = LedgerBudget(path)
            self.assertEqual((ledger.open_calls, ledger.reported_spend_usd), (0, Decimal("0.05")))
            with self.assertRaises(BudgetStop):
                ledger.close_open_call("luna", None, purpose="p", case_id="x", at="t", kind="k")


if __name__ == "__main__":
    unittest.main()
