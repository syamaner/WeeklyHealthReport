"""Phase 2: route B serialiser, UK review conversion, safeguards and drafting mapping.

No Vision run, no image, no model or provider call: synthetic recogniser output only.
"""

import importlib.util
import json
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from helpers import HERE

import acquire_off_taiwan
import arithmetic
import cases
import draft_untouched_truth as drafting
import openrouter_route
import serialise_lines
from budget import BudgetStop, LedgerBudget, RunBudget
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
        cells = {c["row_id"]: c for c in truth["cells"]}
        self.assertEqual((cells["energy_kj"]["unit"], cells["energy_kj"]["canonical_unit"]), ("kJ", "kJ"))
        self.assertEqual(cells["salt"]["comparator"], "<")
        self.assertEqual(cells["fat"]["serving_conversion"], "14g")
        self.assertEqual((cells["fat_ri"]["nutrient"], cells["fat_ri"]["basis"]), ("fat", "reference_intake"))
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
            None,
        ]
        for slug in accepted:
            self.assertTrue(openrouter_route.model_slug_matches("openai/gpt-6-luna", slug), slug)
            self.assertEqual(openrouter_route.route_mismatches(self.raw(model=slug), self.target), [], slug)
        for slug in rejected:
            self.assertFalse(openrouter_route.model_slug_matches("openai/gpt-6-luna", slug), slug)

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


if __name__ == "__main__":
    unittest.main()
