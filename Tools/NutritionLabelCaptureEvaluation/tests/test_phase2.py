"""Phase 2: route B serialiser, UK review conversion, safeguards and drafting mapping.

No Vision run, no image, no model or provider call: synthetic recogniser output only.
"""

import csv
import http.server
import importlib.util
import json
import multiprocessing
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from decimal import Decimal
from pathlib import Path
from unittest import mock

from helpers import HERE

import acquire_off_taiwan
import arithmetic
import cases
import draft_untouched_truth as drafting
import openrouter_route
import serialise_lines
from budget import BudgetStop, LedgerBudget, RunBudget
from candidate import validate_candidate
from openrouter_route import RouteCModel


def token(text, x, y, width=None, height=0.04):
    return {"text": text, "box": {"x": x, "y": y - height / 2, "width": width or 0.012 * len(text), "height": height}}


def line(*tokens):
    text = " ".join(t["text"] for t in tokens)
    x0 = min(t["box"]["x"] for t in tokens)
    x1 = max(t["box"]["x"] + t["box"]["width"] for t in tokens)
    y = tokens[0]["box"]["y"]
    return {
        "text": text,
        "confidence": 1.0,
        "box": {"x": x0, "y": y, "width": x1 - x0, "height": tokens[0]["box"]["height"]},
        "tokens": list(tokens),
    }


ROWS = ["熱量", "蛋白質", "脂肪", "飽和脂肪", "反式脂肪", "碳水化合物", "糖", "膳食纖維", "鈉"]
VALUES = ["367.2大卡", "11公克", "8.8公克", "1.2公克", "0公克", "67公克", "9.1公克", "12公克", "8毫克"]


def muesli_like(right_offset_rows=1.0, drop_label=None):
    """Two identical columns; the right one printed about one row lower (plan section 3.4)."""
    pitch = 0.06
    lines = [line(token("每份", 0.40, 0.20)), line(token("每100公克", 0.65, 0.20))]
    for index, (label, value) in enumerate(zip(ROWS, VALUES, strict=True)):
        y = 0.28 + index * pitch
        if label != drop_label:
            lines.append(line(token(label, 0.05, y)))
        lines.append(line(token(value, 0.40, y)))
        lines.append(line(token(value, 0.65, y + right_offset_rows * pitch)))
    return {"lines": lines}


class SerialiserTests(unittest.TestCase):
    def test_column_printed_one_row_lower_binds_by_order(self):
        result = serialise_lines.serialise(muesli_like())
        rows = result["text"].splitlines()
        self.assertEqual(rows[0], "每份\t每100公克")
        self.assertIn("熱量\t367.2大卡\t367.2大卡", rows)
        self.assertIn("鈉\t8毫克\t8毫克", rows)
        self.assertEqual(result["report"]["unbound_values"], 0)
        self.assertEqual(result["report"]["column_shift_in_rows"][1], 1.0)

    def test_aligned_columns_need_no_shift(self):
        result = serialise_lines.serialise(muesli_like(right_offset_rows=0))
        self.assertIn("蛋白質\t11公克\t11公克", result["text"].splitlines())
        self.assertEqual(result["report"]["column_shift_in_rows"], [0.0, 0.0])

    def test_missed_row_label_never_shifts_a_column(self):
        # 糖 is not recognised: its values must surface unbound (a count mismatch for the
        # parser), never slide onto 膳食纖維 or 鈉.
        result = serialise_lines.serialise(muesli_like(right_offset_rows=0, drop_label="糖"))
        rows = result["text"].splitlines()
        self.assertIn("膳食纖維\t12公克\t12公克", rows)
        self.assertIn("9.1公克", rows)
        self.assertEqual(result["report"]["unbound_values"], 2)

    def test_values_are_never_rewritten(self):
        result = serialise_lines.serialise(muesli_like())
        for value in VALUES:
            self.assertIn(value, result["text"])

    def test_stacked_kj_and_kcal_share_the_energy_row(self):
        lines = [
            line(token("Per", 0.5, 0.10), token("100g", 0.56, 0.10)),
            line(token("Energy", 0.05, 0.20)),
            line(token("1642kJ", 0.5, 0.18)),
            line(token("388kcal", 0.5, 0.22)),
            line(token("Fat", 0.05, 0.30)),
            line(token("5.4g", 0.5, 0.30)),
        ]
        text = serialise_lines.serialise({"lines": lines})["text"].splitlines()
        self.assertIn("Energy\t1642kJ\t388kcal", text)
        self.assertIn("Fat\t5.4g", text)

    def test_slashed_energy_is_two_values(self):
        lines = [
            line(token("per", 0.5, 0.10), token("100ml", 0.55, 0.10)),
            line(token("Energy", 0.05, 0.2)),
            line(token("271kJ/65kcal", 0.5, 0.2)),
        ]
        self.assertIn("Energy\t271kJ\t65kcal", serialise_lines.serialise({"lines": lines})["text"].splitlines())

    def test_header_over_two_lines_is_joined_and_footnote_dropped(self):
        lines = [
            line(token("Per", 0.5, 0.10)),
            line(token("100g", 0.5, 0.15)),
            line(token("Per", 0.75, 0.10)),
            line(token("2", 0.75, 0.15), token("Sausages", 0.77, 0.15)),
            line(token("Fat", 0.05, 0.25)),
            line(token("7.8g", 0.5, 0.25)),
            line(token("6.7g", 0.75, 0.25)),
            line(token("*Reference", 0.05, 0.9), token("intake", 0.2, 0.9)),
        ]
        text = serialise_lines.serialise({"lines": lines})["text"].splitlines()
        self.assertIn("Per 100g\tPer 2 Sausages", text)
        self.assertIn("Fat\t7.8g\t6.7g", text)
        self.assertFalse(any("Reference" in row for row in text))


PARSER_CLI = HERE.parents[1] / "Packages" / "FoodLedgerKit" / ".build" / "out" / "Products" / "Debug" / "NutritionLabelTextParse"


def reference_intake_table(drop_percent_row=None):
    """每份 and 每日參考值百分比 columns; optionally the % cell of one row is not recognised."""
    rows = [
        ("熱量", "120大卡", "6%"),
        ("蛋白質", "3公克", "5%"),
        ("脂肪", "2公克", "3%"),
        ("碳水化合物", "20公克", "7%"),
        ("鈉", "50毫克", "3%"),
    ]
    lines = [line(token("每份", 0.40, 0.20)), line(token("每日參考值百分比", 0.65, 0.20))]
    for index, (label, amount, percent) in enumerate(rows):
        y = 0.28 + index * 0.06
        lines.append(line(token(label, 0.05, y)))
        lines.append(line(token(amount, 0.40, y)))
        if label != drop_percent_row:
            lines.append(line(token(percent, 0.70, y)))
    return {"lines": lines}


@unittest.skipUnless(
    PARSER_CLI.exists() and importlib.util.find_spec("inspect_ai"), "needs the built NutritionLabelTextParse and inspect_ai"
)
class RouteBEndToEndTests(unittest.TestCase):
    """Serialiser, then the real parser CLI, then route B's structural checks."""

    def run_route_b(self, recognised):
        from inspect_task import route_b_structural_checks

        serialised = serialise_lines.serialise(recognised)
        payload = json.dumps([{"id": "x", "text": serialised["text"], "route": "B", "input_sha256": "c" * 64}])
        output = subprocess.run([str(PARSER_CLI)], input=payload.encode(), capture_output=True, check=True).stdout
        parsed = json.loads(output)[0]["candidate"]
        return parsed, route_b_structural_checks(parsed, serialised["report"])

    def test_missed_row_label_declines(self):
        _, candidate = self.run_route_b(muesli_like(right_offset_rows=0, drop_label="糖"))
        self.assertTrue(candidate["declined"])
        self.assertFalse(candidate["would_mark_ready"])
        self.assertEqual(candidate["cells"], [])
        self.assertEqual(validate_candidate(candidate), [])

    def test_missed_reference_intake_cell_is_never_ready(self):
        _, ready = self.run_route_b(reference_intake_table())
        self.assertTrue(ready["would_mark_ready"], ready["warnings"])
        parsed, candidate = self.run_route_b(reference_intake_table(drop_percent_row="碳水化合物"))
        self.assertFalse(candidate["declined"])
        self.assertFalse(candidate["would_mark_ready"])
        self.assertIn("rows_without_reference_intake_cell: carbohydrate", candidate["warnings"])
        self.assertEqual(validate_candidate(candidate), [])

    def test_missed_percent_label_that_lands_on_a_complete_row_never_marks_ready(self):
        # The % cell of 脂肪 is recognised but its label is not, and the value sits a row
        # lower: whatever binding results, the table must not be ready.
        recognised = reference_intake_table()
        recognised["lines"] = [entry for entry in recognised["lines"] if entry["text"] != "脂肪"]
        _, candidate = self.run_route_b(recognised)
        self.assertFalse(candidate["would_mark_ready"])


class UkReviewTests(unittest.TestCase):
    panel = {
        "panel_id": "off:1:nutrition_en.1",
        "image_sha256": "a" * 64,
        "ground_truth": {
            "requires_decline": False,
            "cells": [
                {
                    "row_id": "energy_kj",
                    "parent_row_id": None,
                    "header_id": "header_1",
                    "basis": "per_100g",
                    "printed_text": "1642 kJ",
                    "comparator": None,
                    "decimal_text": "1642",
                    "unit": "kj",
                    "serving_conversion": None,
                },
                {
                    "row_id": "fat",
                    "parent_row_id": None,
                    "header_id": "header_2",
                    "basis": "per_serving",
                    "printed_text": "0.8g",
                    "comparator": None,
                    "decimal_text": "0.8",
                    "unit": "g",
                    "serving_conversion": "14g",
                },
                {
                    "row_id": "fat_ri",
                    "parent_row_id": None,
                    "header_id": "header_3",
                    "basis": "per_serving",
                    "printed_text": "1%",
                    "comparator": None,
                    "decimal_text": "1",
                    "unit": "%",
                    "serving_conversion": None,
                },
                {
                    "row_id": "salt",
                    "parent_row_id": None,
                    "header_id": "header_1",
                    "basis": "per_100g",
                    "printed_text": "<0.01g",
                    "comparator": "<",
                    "decimal_text": "0.01",
                    "unit": "g",
                    "serving_conversion": None,
                },
                {
                    "row_id": "vitamin_e",
                    "parent_row_id": None,
                    "header_id": "header_1",
                    "basis": "per_100g",
                    "printed_text": "3mg",
                    "comparator": None,
                    "decimal_text": "3",
                    "unit": "mg",
                    "serving_conversion": None,
                },
            ],
        },
    }

    def test_conversion_keeps_printed_units_and_bounds(self):
        truth = cases.uk_truth_from_review(self.panel)
        cells = {c["row_id"]: c for c in truth["cells"] if c["basis"] != "reference_intake"}
        reference = {c["row_id"]: c for c in truth["cells"] if c["basis"] == "reference_intake"}
        self.assertEqual((cells["energy_kj"]["unit"], cells["energy_kj"]["canonical_unit"]), ("kJ", "kJ"))
        self.assertEqual(cells["salt"]["comparator"], "<")
        self.assertEqual(cells["fat"]["serving_conversion"], "14g")
        # Amendment T1: the fat_ri reference-intake cell now shares the fat row and its parent.
        self.assertEqual((reference["fat"]["nutrient"], reference["fat"]["parent_row_id"]), ("fat", cells["fat"]["parent_row_id"]))
        self.assertEqual((cells["vitamin_e"]["nutrient"], cells["vitamin_e"]["printed_label"]), ("unrecognised", "vitamin e"))
        self.assertEqual(truth["servings_per_pack"], "not_recorded")
        self.assertEqual(truth["jurisdiction"], "uk")


class RouteBGuardTests(unittest.TestCase):
    @unittest.skipUnless(importlib.util.find_spec("inspect_ai"), "inspect_ai is not installed (see requirements.txt)")
    def test_refuses_sealed_and_untouched_inputs(self):
        from inspect_task import route_b_input_allowed

        with self.assertRaises(cases.SealedSetError):
            route_b_input_allowed({"split": "untouched", "image_path": "/x/development/a.jpg"})
        with self.assertRaises(cases.SealedSetError):
            route_b_input_allowed({"split": "development", "image_path": "/x/sealed/a.jpg"})
        with self.assertRaises(PermissionError):
            route_b_input_allowed({"split": "development", "image_path": "/x/a.jpg", "corpus": "owner"})
        route_b_input_allowed({"split": "development", "image_path": "/x/development/a.jpg", "corpus": "off_taiwan"})

    def test_owner_photo_needs_local_routes_consent(self):
        with tempfile.TemporaryDirectory() as folder:
            master = Path(folder) / "m.jpg"
            master.write_bytes(b"x")
            consent = Path(folder) / "c.json"
            contract = Path(folder) / "contract.json"
            digest = cases.sha256_file(master)
            contract.write_text(json.dumps({"corpus": {"muesli": {"stripped_master_sha256": digest}}}))
            consent.write_text(json.dumps({"master_sha256": digest, "local_routes": False}))
            with self.assertRaises(PermissionError):
                cases.load_owner_photo(master, consent, {"cells": []}, contract)
            consent.write_text(json.dumps({"master_sha256": digest, "local_routes": True}))
            loaded = cases.load_owner_photo(master, consent, {"cells": []}, contract)
            self.assertEqual(loaded["truth"]["input_sha256"], digest)


class SafeguardTests(unittest.TestCase):
    target = RouteCModel(label="luna", model="openai/gpt-6-luna", endpoint="azure", provider_name="Azure")

    def raw(self, **overrides):
        raw = {"model": "openai/gpt-6-luna", "provider": "Azure", "usage": {"cost": 0.004}, "choices": [{"finish_reason": "stop"}]}
        raw.update(overrides)
        return raw

    def test_missing_finish_reason_is_a_problem(self):
        self.assertTrue(openrouter_route.route_mismatches(self.raw(choices=[{}]), self.target))
        self.assertTrue(openrouter_route.route_mismatches(self.raw(choices=[]), self.target))
        self.assertTrue(openrouter_route.route_mismatches(self.raw(choices=None), self.target))

    def test_model_slug_rule(self):
        accepted = [
            "openai/gpt-6-luna",
            "openai/gpt-6-luna-20261001",
            "openai/gpt-6-luna-2026-10-01",
            "openai/gpt-6-luna-10-01",
            "openai/gpt-6-luna-1001",
        ]
        rejected = [
            "openai/gpt-6-luna-mini",
            "openai/gpt-6-luna-thinking",
            "openai/gpt-6-luna-v2",
            "openai/gpt-6-luna:free",
            "openai/gpt-6-luna-20261001:nitro",
            "openai/gpt-6.1-sol",
            "openai/gpt-6",
            "azure/gpt-6-luna",
            "openai/gpt-6-luna-202610",
            "openai/gpt-6-luna-20261341",
            "openai/gpt-6-luna-2026-02-30",
            "openai/gpt-6-luna-0230",
            "openai/gpt-6-luna-13-01",
            None,
        ]
        for slug in accepted:
            self.assertTrue(openrouter_route.model_slug_matches("openai/gpt-6-luna", slug), slug)
            self.assertEqual(openrouter_route.route_mismatches(self.raw(model=slug), self.target), [], slug)
        for slug in rejected:
            self.assertFalse(openrouter_route.model_slug_matches("openai/gpt-6-luna", slug), slug)

    def test_logged_request_must_not_carry_credential_headers(self):
        self.assertEqual(openrouter_route.logged_request_credentials({"extra_headers": {"x-irid": "1", "x-session-id": "s"}}), [])
        self.assertEqual(openrouter_route.logged_request_credentials({"extra_headers": {"Authorization": "Bearer x"}}), ["Authorization"])
        self.assertEqual(openrouter_route.logged_request_credentials({"extra_headers": {"X-Api-Key": "k"}}), ["X-Api-Key"])
        self.assertEqual(openrouter_route.logged_request_credentials(None), [])

    def test_uk_fibre_variant_is_not_applied_to_us_labels(self):
        cells = [
            {"nutrient": n, "basis": "per_serving", "canonical_unit": u, "comparator": "=", "decimal_text": v}
            for n, u, v in (
                ("energy_kcal", "kcal", "200"),
                ("protein", "g", "10"),
                ("fat", "g", "0"),
                ("carbohydrate", "g", "20"),
                ("fibre", "g", "30"),
            )
        ]
        us = arithmetic.energy_check({"jurisdiction": "us", "cells": cells}, "per_serving")
        self.assertEqual([f["form"] for f in us["forms"]], ["general"])
        # general 120 is 80 short of 200, allowed max(20, 40): fails; the UK form (180) would pass.
        self.assertEqual(us["status"], arithmetic.FAIL)
        uk = arithmetic.energy_check({"jurisdiction": "uk", "cells": cells}, "per_serving")
        self.assertEqual([f["form"] for f in uk["forms"]], ["general", "uk_fibre"])
        self.assertEqual(uk["status"], arithmetic.PASS)

    def test_refill_max_bytes_is_capped_at_the_contract_batch_stop(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        self.assertEqual(acquire_off_taiwan.REFILL_BATCH_STOP_BYTES, contract["corpus"]["off_taiwan"]["refill_rule"]["batch_stop_bytes"])
        with tempfile.TemporaryDirectory() as folder:
            base = [
                "--out",
                folder,
                "--manifest",
                str(HERE / "fixtures" / "off-taiwan-manifest-v1.json"),
                "--replace",
                "21",
                "--reason",
                "x",
            ]
            self.assertEqual(acquire_off_taiwan.refill([*base, "--max-bytes", "5000001"]), 2)
            self.assertEqual(acquire_off_taiwan.refill([*base, "--max-bytes", "0"]), 2)


def _ledger_worker(path: str, name: str, calls: int) -> None:
    budget = LedgerBudget(Path(path))
    for index in range(calls):
        budget.before_call(name)
        budget.record_call(name, Decimal("0.01"), purpose="test", case_id=f"{name}-{index}", at="t")


class LedgerTests(unittest.TestCase):
    def test_spend_and_reservation_persist_across_runs(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            first = LedgerBudget(path)
            first.before_call("luna")
            first.record_call("luna", Decimal("0.02"), purpose="development", case_id="a", at="t1")
            second = LedgerBudget(path)
            self.assertEqual(second.spent_usd, Decimal("0.02"))
            self.assertEqual(second.reserved_usd, Decimal("10.00"))
            data = json.loads(path.read_text())
            self.assertEqual(data["entries"][0]["purpose"], "development")
            self.assertEqual(data["sealed_reservation_remaining_calls"], 200)
            sealed = LedgerBudget(path, sealed_run=True)
            sealed.before_call("luna")
            sealed.record_call("luna", Decimal("0.03"), purpose="sealed", case_id="b", at="t2")
            self.assertEqual(LedgerBudget(path).sealed_calls_made, 1)

    def test_development_spend_stops_short_of_the_reservation_across_runs(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            for _ in range(3):
                budget = LedgerBudget(path)
                for _ in range(100):
                    budget.before_call("luna")
                    budget.record_call("luna", Decimal("0.05"), purpose="development", case_id="x", at="t")
            with self.assertRaises(BudgetStop):
                LedgerBudget(path).before_call("luna")

    def test_an_unrecorded_call_stays_charged_at_the_ceiling(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            LedgerBudget(path).before_call("luna")  # interrupted: never recorded
            later = LedgerBudget(path)
            self.assertEqual(later.spent_usd, Decimal("0.05"))
            self.assertEqual(json.loads(path.read_text())["open_calls"], 1)

    def test_two_instances_interleave_on_one_ledger(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            # $0.09 of headroom above the $10 reservation: only one $0.05 call may be open at once.
            limits = {"total_usd": "10.09"}
            first, second = LedgerBudget(path, limits=limits), LedgerBudget(path, limits=limits)
            first.before_call("luna")
            with self.assertRaises(BudgetStop):
                second.before_call("grok")  # sees the first instance's open call
            first.record_call("luna", Decimal("0.01"), purpose="development", case_id="a", at="t1")
            second.before_call("grok")
            second.record_call("grok", Decimal("0.02"), purpose="development", case_id="b", at="t2")
            data = json.loads(path.read_text())
            self.assertEqual([e["case_id"] for e in data["entries"]], ["a", "b"])
            self.assertEqual((data["open_calls"], data["reported_spend_usd"]), (0, "0.03"))

    def test_separate_processes_lose_no_update(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            LedgerBudget(path)
            context = multiprocessing.get_context("spawn")
            workers = [context.Process(target=_ledger_worker, args=(str(path), name, 20)) for name in ("p1", "p2", "p3")]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(60)
                self.assertEqual(worker.exitcode, 0)
            data = json.loads(path.read_text())
            self.assertEqual(len(data["entries"]), 60)
            self.assertEqual(data["open_calls"], 0)
            self.assertEqual(Decimal(data["reported_spend_usd"]), Decimal("0.60"))

    def test_an_open_sealed_call_counts_against_the_sealed_cap(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            limits = {"sealed_reserved_calls": 2}
            crashed = LedgerBudget(path, sealed_run=True, limits=limits)
            crashed.before_call("luna")  # never recorded
            later = LedgerBudget(path, sealed_run=True, limits=limits)
            later.before_call("luna")
            later.record_call("luna", Decimal("0.01"), purpose="sealed", case_id="x", at="t")
            self.assertEqual(later.sealed_calls_made, 2)
            with self.assertRaises(BudgetStop):
                later.before_call("luna")

    def test_changed_limits_are_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ledger.json"
            LedgerBudget(path)
            with self.assertRaises(BudgetStop):
                LedgerBudget(path, limits={"total_usd": "50"})

    def test_in_flight_calls_count_against_the_stop(self):
        budget = RunBudget(total_usd=Decimal("10.10"))  # $0.10 above the $10 reservation
        budget.before_call("luna")
        budget.before_call("luna")
        with self.assertRaises(BudgetStop):
            budget.before_call("luna")


class DraftingTests(unittest.TestCase):
    photo = {"barcode13": "4710000000000", "revision": "3", "order": 21, "sha256": "b" * 64}
    wire = {
        "table_found": "taiwan_nutrition_label",
        "language": "zh-Hant",
        "serving_size_text": "每一份量30公克",
        "serving_size_uncertain": False,
        "servings_per_pack_text": "本包裝含2.5份",
        "servings_per_pack_uncertain": True,
        "headers": [
            {"header_id": "h1", "printed_text": "每份", "basis": "per_serving", "uncertain": False},
            {"header_id": "h2", "printed_text": "每100公克", "basis": "per_100g", "uncertain": False},
        ],
        "rows": [
            {
                "printed_label": "熱量",
                "nutrient": "energy_kcal",
                "parent_nutrient": "none",
                "label_uncertain": False,
                "values": [
                    {"header_id": "h1", "printed_text": "120大卡", "uncertain": False},
                    {"header_id": "h2", "printed_text": "400大卡", "uncertain": True},
                ],
            },
            {
                "printed_label": "飽和脂肪",
                "nutrient": "saturates",
                "parent_nutrient": "fat",
                "label_uncertain": False,
                "values": [
                    {"header_id": "h1", "printed_text": "< 0.5 公克", "uncertain": False},
                    {"header_id": "h2", "printed_text": "unknown", "uncertain": True},
                ],
            },
        ],
        "notes": "none",
    }

    def test_maps_to_candidate_cells_and_lists_uncertain_ones(self):
        draft = drafting.map_draft(
            self.wire, self.photo, model="qwen/qwen3.5-397b-a17b-20260216", endpoint="deepinfra/fp8", drafted_on="2026-10-17"
        )
        self.assertEqual(draft["status"], "draft_owner_verification_pending")
        self.assertEqual(draft["case_id"], "off-taiwan:4710000000000:nutrition_zh.3")
        cells = {(c["row_id"], c["header_id"]): c for c in draft["cells"]}
        energy = cells[("energy_kcal", "h1")]
        self.assertEqual(
            (energy["decimal_text"], energy["unit"], energy["canonical_unit"], energy["serving_conversion"]),
            ("120", "大卡", "kcal", "30公克"),
        )
        bound = cells[("saturates", "h1")]
        self.assertEqual((bound["comparator"], bound["decimal_text"], bound["parent_row_id"]), ("<", "0.5", "fat"))
        self.assertFalse(cells[("saturates", "h2")]["parsed"])
        flagged = {(u["row_id"], u["header_id"]) for u in draft["uncertain_cells"]}
        self.assertEqual(flagged, {("energy_kcal", "h2"), ("saturates", "h2"), ("servings_per_pack", "")})
        self.assertEqual(draft["servings_per_pack"]["decimal_text"], "2.5")
        self.assertTrue(all(c["persistence_authorized"] is False and c["requires_user_selection"] is True for c in draft["cells"]))

    def test_parse_value_keeps_printed_units_and_bilingual_echoes(self):
        self.assertEqual(
            drafting.parse_value("0.5 公克(g)"), {"comparator": "=", "decimal_text": "0.5", "unit": "公克", "canonical_unit": "g"}
        )
        bound = drafting.parse_value("<0.1公克")
        assert bound is not None
        self.assertEqual(bound["comparator"], "<")
        self.assertIsNone(drafting.parse_value("*"))
        self.assertIsNone(drafting.parse_value("unknown"))
        self.assertIsNone(drafting.parse_value("5 IU"))

    def test_unparsed_cells_carry_no_invented_value(self):
        draft = drafting.map_draft(self.wire, self.photo, model="m", endpoint="e", drafted_on="d")
        unparsed = [c for c in draft["cells"] if not c["parsed"]]
        self.assertTrue(unparsed)
        for cell in unparsed:
            self.assertNotEqual(cell["decimal_text"], "0")
            self.assertEqual((cell["decimal_text"], cell["comparator"], cell["unit"], cell["canonical_unit"]), (None, None, None, None))
        wire = json.loads(json.dumps(self.wire))
        wire["rows"][0]["values"][0]["header_id"] = "missing"
        cell = next(
            c for c in drafting.map_draft(wire, self.photo, model="m", endpoint="e", drafted_on="d")["cells"] if c["header_id"] == "missing"
        )
        self.assertEqual(cell["basis"], "unknown")

    def test_owner_entries_survive_a_regenerated_sheet(self):
        draft = drafting.map_draft(self.wire, self.photo, model="m", endpoint="e", drafted_on="d")
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            images = {draft["case_id"]: out / "21.jpg"}
            self.assertEqual(drafting.write_review_sheet(out, [draft], images), 0)
            rows = list(csv.DictReader((out / "review.csv").read_text().splitlines()))
            rows[0]["owner_correction"] = "121大卡"
            rows[1]["owner_verified"] = "yes"
            orphan = {**rows[0], "row_id": "gone", "owner_correction": "keep me"}
            with (out / "review.csv").open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows([*rows, orphan])
            self.assertEqual(drafting.write_review_sheet(out, [draft], images), 3)
            merged = list(csv.DictReader((out / "review.csv").read_text().splitlines()))
            self.assertEqual(merged[0]["owner_correction"], "121大卡")
            self.assertEqual(merged[1]["owner_verified"], "yes")
            self.assertIn("keep me", [r["owner_correction"] for r in merged])
            self.assertTrue(list(out.glob("review.csv.before-*")))

    def test_redirects_are_refused_so_the_key_is_never_forwarded(self):
        seen = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                seen.append((self.path, self.headers.get("Authorization")))
                self.send_response(307 if self.path == "/start" else 200)
                self.send_header("Location", "/elsewhere")
                self.send_header("Content-Length", "2")
                self.end_headers()
                self.wfile.write(b"{}")

            def log_message(self, format, *args):  # noqa: A002
                pass

        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}/start"
            request = urllib.request.Request(url, data=b"{}", headers={"Authorization": "Bearer test"}, method="POST")
            with self.assertRaises(urllib.error.HTTPError) as caught:
                drafting.OPENER.open(request, timeout=10)
            self.assertEqual(caught.exception.code, 307)
        finally:
            server.shutdown()
            server.server_close()
        self.assertEqual([path for path, _ in seen], ["/start"])

    def test_cli_model_must_match_the_contract(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        digest = contract["corpus"]["off_taiwan"]["manifest_sha256"]
        with tempfile.TemporaryDirectory() as folder:
            argv = ["draft", "--image-root", folder, "--out", folder + "/o", "--ledger", folder + "/l.json", "--unseal-for-drafting"]
            argv += ["--manifest-sha256", digest, "--model", "qwen/qwen3.5-27b", "--sheet-only"]
            with mock.patch.object(sys, "argv", argv), self.assertRaisesRegex(SystemExit, "differs from the contract"):
                drafting.main()
            self.assertFalse((Path(folder) / "o").exists())

    def test_git_check_runs_before_any_folder_is_created(self):
        missing = HERE / "not-yet-created" / "child"
        self.assertTrue(drafting.inside_git(missing))
        self.assertFalse(missing.parent.exists())

    def test_non_label_images_are_proposed_for_exclusion(self):
        wire = {**self.wire, "table_found": "other_language_nutrition_table", "headers": [], "rows": []}
        self.assertEqual(drafting.map_draft(wire, self.photo, model="m", endpoint="e", drafted_on="d")["proposal"], "exclude_and_refill")

    def test_request_uses_the_route_c_provider_block_and_carries_no_key(self):
        target = RouteCModel(label="q", model="qwen/qwen3.5-397b-a17b", endpoint="deepinfra/fp8", provider_name="DeepInfra")
        body = drafting.request_body(target, b"\xff\xd8", "instruction", {"type": "object"})
        self.assertEqual(body["provider"], openrouter_route.provider_block("deepinfra/fp8"))
        self.assertEqual(body["max_tokens"], 4096)
        self.assertTrue(body["response_format"]["json_schema"]["strict"])
        self.assertNotIn("Authorization", json.dumps(body))
        self.assertNotIn("Bearer", json.dumps(body))

    def test_journal_detects_a_request_without_receipt(self):
        with tempfile.TemporaryDirectory() as folder:
            journal = Path(folder) / "journal.jsonl"
            drafting.append(journal, {"event": "request", "case_id": "a"})
            self.assertEqual(drafting.journal_open_request(journal), "a")
            drafting.append(journal, {"event": "receipt", "case_id": "a"})
            self.assertIsNone(drafting.journal_open_request(journal))

    def test_review_sheet_links_each_image_to_its_draft(self):
        draft = drafting.map_draft(self.wire, self.photo, model="m", endpoint="e", drafted_on="d")
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            image = out / "21.jpg"
            drafting.write_review_sheet(out, [draft], {draft["case_id"]: image})
            page = (out / "review.html").read_text()
            self.assertIn(image.as_uri(), page)
            self.assertIn("120大卡", page)
            rows = (out / "review.csv").read_text().splitlines()
            self.assertTrue(rows[0].startswith("order,case_id,image"))
            self.assertEqual(len(rows), 1 + 4 + 3)  # header, four cells, serving size, servings per pack, decision


class ReReviewTests(unittest.TestCase):
    """Second invariant review of PR #257."""

    def test_fourth_unknown_cost_call_is_refused_before_it_is_made(self):
        budget = RunBudget()
        for _ in range(3):
            budget.before_call("grok")
            budget.record("grok", None)
        with self.assertRaises(BudgetStop):
            budget.before_call("grok")
        with tempfile.TemporaryDirectory() as folder:
            ledger = LedgerBudget(Path(folder) / "ledger.json")
            for index in range(3):
                ledger.before_call("grok")
                ledger.record_call("grok", None, purpose="t", case_id=str(index), at="t")
            with self.assertRaises(BudgetStop):
                ledger.before_call("grok")
            self.assertEqual(json.loads((Path(folder) / "ledger.json").read_text())["open_calls"], 0)

    def test_changed_draft_text_keeps_the_owner_entry_as_an_orphan(self):
        wire = json.loads(json.dumps(DraftingTests.wire))
        draft = drafting.map_draft(wire, DraftingTests.photo, model="m", endpoint="e", drafted_on="d")
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            images = {draft["case_id"]: out / "21.jpg"}
            drafting.write_review_sheet(out, [draft], images)
            rows = list(csv.DictReader((out / "review.csv").read_text().splitlines()))
            rows[0]["owner_correction"] = "125大卡"
            with (out / "review.csv").open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
            wire["rows"][0]["values"][0]["printed_text"] = "121大卡"  # the draft changed
            changed = drafting.map_draft(wire, DraftingTests.photo, model="m", endpoint="e", drafted_on="d")
            self.assertEqual(drafting.write_review_sheet(out, [changed], images), 1)
            merged = list(csv.DictReader((out / "review.csv").read_text().splitlines()))
            current = next(r for r in merged if r["draft_printed_text"] == "121大卡")
            self.assertEqual(current["owner_correction"], "")
            orphan = next(r for r in merged if r["owner_correction"] == "125大卡")
            self.assertEqual(orphan["draft_printed_text"], "120大卡")
            self.assertTrue(orphan["merge_note"])

    def test_unknown_basis_has_unknown_serving_conversion(self):
        wire = json.loads(json.dumps(DraftingTests.wire))
        wire["rows"][0]["values"][0]["header_id"] = "missing"
        cells = drafting.map_draft(wire, DraftingTests.photo, model="m", endpoint="e", drafted_on="d")["cells"]
        cell = next(c for c in cells if c["header_id"] == "missing")
        self.assertEqual((cell["basis"], cell["serving_conversion"]), ("unknown", "unknown"))

    def test_in_repository_out_creates_no_folder(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        digest = contract["corpus"]["off_taiwan"]["manifest_sha256"]
        target = HERE / "drafts-must-not-exist"
        with tempfile.TemporaryDirectory() as folder:
            argv = ["draft", "--image-root", folder, "--out", str(target), "--ledger", folder + "/l.json", "--unseal-for-drafting"]
            argv += ["--manifest-sha256", digest, "--sheet-only"]
            with mock.patch.object(sys, "argv", argv), self.assertRaisesRegex(SystemExit, "inside a git checkout"):
                drafting.main()
        self.assertFalse(target.exists())

    def test_aggregate_reports_the_ready_count(self):
        import score

        results = [{"cases": 1, "would_mark_ready_after_arithmetic": 1}, {"cases": 1, "would_mark_ready_after_arithmetic": 0}]
        self.assertEqual(score.aggregate(results, score.load_thresholds())["would_mark_ready_after_arithmetic"], 1)

    def test_route_c_runner_keeps_logs_outside_and_images_out_of_logs(self):
        import run_route_c

        with tempfile.TemporaryDirectory() as folder:
            kwargs = run_route_c.eval_kwargs(Path(folder))
        self.assertIs(kwargs["log_images"], False)
        self.assertEqual(kwargs["model"], "mockllm/model")  # the solver posts itself; generate is never called
        self.assertNotIn("model_args", kwargs)
        self.assertNotIn("extra_headers", kwargs)
        with self.assertRaises(SystemExit):
            run_route_c.eval_kwargs(HERE / "logs")
        argv = ["--label", "luna", "--reasoning", "off", "--ledger", "/tmp/y", "--log-dir", "/tmp/z"]
        argv += ["--qualification-dir", "/tmp/q", "--uk-workspace", "/tmp/u", "--projected-cost-usd", "0.1"]
        contract = json.loads(run_route_c.CONTRACT.read_text())
        contract["route_c"]["enabled"] = False
        original = run_route_c.CONTRACT
        with tempfile.TemporaryDirectory() as folder:
            run_route_c.CONTRACT = Path(folder) / "contract.json"
            run_route_c.CONTRACT.write_text(json.dumps(contract))
            try:
                with self.assertRaisesRegex(SystemExit, "disabled"):
                    run_route_c.main(argv)
            finally:
                run_route_c.CONTRACT = original
        contract["route_c"]["enabled"] = True
        with self.assertRaisesRegex(SystemExit, "not pinned"):
            run_route_c.pinned_target(contract, "qwen")


if __name__ == "__main__":
    unittest.main()
