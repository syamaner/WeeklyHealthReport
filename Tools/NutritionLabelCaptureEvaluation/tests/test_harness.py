"""Candidate schema, spend stops, sealed-set guard, selection rule, renderer and contract."""

import hashlib
import json
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from helpers import HERE, candidate_from_truth, declined_candidate, muesli_truth

import acquire_off_taiwan
import cases
import validate_contract
from budget import BudgetStop, RunBudget
from candidate import validate_candidate
from synthetic import render


class CandidateSchemaTests(unittest.TestCase):
    def test_valid_candidates(self):
        self.assertEqual(validate_candidate(candidate_from_truth(muesli_truth())), [])
        self.assertEqual(validate_candidate(declined_candidate()), [])

    def test_never_authorises_persistence(self):
        for field, value in (("ready_for_confirmation", True), ("automatic_save", True), ("status", "ready")):
            candidate = candidate_from_truth(muesli_truth())
            candidate[field] = value
            self.assertTrue(validate_candidate(candidate), field)
        candidate = candidate_from_truth(muesli_truth())
        candidate["cells"][0]["persistence_authorized"] = True
        self.assertTrue(validate_candidate(candidate))

    def test_unknown_must_be_explicit(self):
        candidate = candidate_from_truth(muesli_truth())
        candidate["serving_size"] = None
        self.assertTrue(validate_candidate(candidate))
        candidate["serving_size"] = "unknown"
        self.assertEqual(validate_candidate(candidate), [])

    def test_declined_candidate_keeps_no_cells(self):
        candidate = declined_candidate()
        candidate["cells"] = candidate_from_truth(muesli_truth())["cells"][:1]
        self.assertTrue(validate_candidate(candidate))

    def test_reference_intake_cell_must_be_a_percentage(self):
        candidate = candidate_from_truth(muesli_truth())
        candidate["headers"][1]["basis"] = "reference_intake"
        for item in candidate["cells"]:
            if item["header_id"] == "header_2":
                item["basis"] = "reference_intake"
        self.assertTrue(any("reference-intake" in e for e in validate_candidate(candidate)))


class BudgetTests(unittest.TestCase):
    def test_per_call_stop_stops_that_model(self):
        budget = RunBudget()
        with self.assertRaises(BudgetStop):
            budget.record("opus", Decimal("0.051"))
        with self.assertRaises(BudgetStop):
            budget.before_call("opus")
        budget.before_call("luna")

    def test_development_calls_cannot_spend_the_sealed_reservation(self):
        budget = RunBudget()
        self.assertEqual(budget.reserved_usd, Decimal("10.00"))  # 200 calls at the $0.05 ceiling
        for _ in range(300):  # $15 = $25 total minus the $10 reservation
            budget.before_call("luna")
            budget.record("luna", Decimal("0.05"))
        with self.assertRaises(BudgetStop):
            budget.before_call("luna")

    def test_sealed_run_may_use_its_reservation_once(self):
        budget = RunBudget(spent_usd=Decimal("14.95"), sealed_run=True)
        for _ in range(200):
            budget.before_call("luna")
            budget.record("luna", Decimal("0.05"))
        self.assertEqual(budget.reserved_usd, 0)
        with self.assertRaises(BudgetStop):
            budget.before_call("luna")

    def test_total_stop_on_reported_cost(self):
        budget = RunBudget(sealed_run=True, sealed_reserved_calls=10_000)
        for _ in range(499):
            budget.record("luna", Decimal("0.05"))
        with self.assertRaises(BudgetStop):
            budget.record("luna", Decimal("0.05"))

    def test_unknown_cost_beyond_three_stops(self):
        budget = RunBudget()
        for _ in range(3):
            budget.record("grok", None)
        self.assertEqual(budget.spent_usd, 0)
        with self.assertRaises(BudgetStop):
            budget.record("grok", None)


class SealedSetTests(unittest.TestCase):
    manifest = HERE / "fixtures" / "off-taiwan-manifest-v1.json"

    def test_refuses_without_unseal(self):
        with self.assertRaises(cases.SealedSetError):
            cases.load_untouched_photos(self.manifest, Path("/nonexistent"), unseal=False, manifest_sha256=None)

    def test_refuses_wrong_hash(self):
        with self.assertRaises(cases.SealedSetError):
            cases.load_untouched_photos(self.manifest, Path("/nonexistent"), unseal=True, manifest_sha256="0" * 64)

    def test_refuses_while_contract_is_not_frozen(self):
        digest = hashlib.sha256(self.manifest.read_bytes()).hexdigest()
        with self.assertRaisesRegex(cases.SealedSetError, "not frozen"):
            cases.load_untouched_photos(self.manifest, Path("/nonexistent"), unseal=True, manifest_sha256=digest)

    def test_development_loader_refuses_untouched_cases(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "cases.jsonl"
            text = "x"
            path.write_text(
                json.dumps(
                    {
                        "id": "a",
                        "input": {"kind": "text", "text": text},
                        "truth": {},
                        "metadata": {"split": "untouched", "sha256": render.digest(text)},
                    }
                )
                + "\n"
            )
            with self.assertRaises(cases.SealedSetError):
                cases.load_development_text(path)

    def test_manifest_split_and_attribution(self):
        manifest = json.loads(self.manifest.read_text())
        photos = manifest["photos"]
        self.assertEqual(len(photos), 60)
        self.assertEqual([p["split"] for p in photos], ["development"] * 20 + ["untouched"] * 40)
        self.assertEqual([p["order_key_sha256"] for p in photos], sorted(p["order_key_sha256"] for p in photos))
        for photo in photos:
            self.assertEqual(photo["order_key_sha256"], hashlib.sha256(photo["barcode13"].encode()).hexdigest())
            self.assertIn("CC BY-SA 3.0", photo["attribution"])
            self.assertRegex(photo["sha256"], r"^[0-9a-f]{64}$")
            self.assertIn(f"nutrition_zh.{photo['revision']}.full.jpg", photo["url"])
        self.assertLessEqual(manifest["total_bytes"], acquire_off_taiwan.APPROVED_MAX_BYTES)


class SelectionRuleTests(unittest.TestCase):
    def test_orders_by_barcode_hash_and_splits_20_40(self):
        hits = [{"code": str(1000 + i), "images": {"nutrition_zh": {"rev": "3", "imgid": "1"}, "1": {"uploader": "u"}}} for i in range(70)]
        hits.append({"code": "abc", "images": {"nutrition_zh": {"rev": "1"}}})
        hits.append({"code": "5", "images": {"nutrition_en": {"rev": "1"}}})
        chosen = acquire_off_taiwan.select(hits)
        self.assertEqual(len(chosen), 60)
        self.assertEqual([c["order_key_sha256"] for c in chosen], sorted(c["order_key_sha256"] for c in chosen))
        self.assertEqual(sum(c["split"] == "development" for c in chosen), 20)
        self.assertEqual(chosen[0]["url"].split("/")[-1], "nutrition_zh.3.full.jpg")
        self.assertTrue(all(c["barcode13"].startswith("000000000") for c in chosen))

    def test_image_path_layout(self):
        self.assertEqual(acquire_off_taiwan.image_path("4710018149108"), "471/001/814/9108")
        self.assertEqual(acquire_off_taiwan.image_path("80177425"), "000/008/017/7425")


class RendererTests(unittest.TestCase):
    def test_choice_is_deterministic(self):
        self.assertEqual(render.choose(render.ENGLISH_SHAPES, "x"), render.choose(render.ENGLISH_SHAPES, "x"))

    def test_fda_split_by_hash(self):
        self.assertEqual(render.fda_split("00000000" + "0" * 56), "development")
        self.assertEqual(render.fda_split("00000001" + "0" * 56), "untouched")

    def test_column_variants_never_add_values(self):
        truth = muesli_truth()
        single = render.select_columns(truth, "single_column_serving")
        assert single is not None
        self.assertEqual(len(single["cells"]), 9)
        self.assertTrue(
            {(c["nutrient"], c["decimal_text"]) for c in single["cells"]} <= {(c["nutrient"], c["decimal_text"]) for c in truth["cells"]}
        )

    def test_fda_row_needs_structured_values(self):
        row = {
            "每一份量": "90公克",
            "本包裝含": "2份",
            "每份熱量": "198.9大卡",
            "每份蛋白質": "11公克",
            "每份脂肪": "14公克",
            "每份飽和脂肪": "4.1公克",
            "每份反式脂肪": "0公克",
            "每份碳水化合物": "7.4公克",
            "每份糖": "4公克",
            "每份鈉": "603毫克",
        }
        truth, reason = render.fda_truth(row)
        self.assertIsNone(reason)
        assert truth is not None
        self.assertEqual(truth["serving_size"]["canonical_unit"], "g")
        row["每份鈉"] = "603公克"
        self.assertIsNone(render.fda_truth(row)[0])

    def test_simplified_variant_is_unsupported(self):
        text, _ = render.render_chinese(muesli_truth(), "tab", simplified=True)
        self.assertIn("营养标示", text)
        self.assertIn("热量", text)


class TemplateTests(unittest.TestCase):
    def test_template_tables_pass_the_arithmetic_policy(self):
        import arithmetic

        for variant in render.TEMPLATE_VARIANTS:
            for index in range(render.TEMPLATE_CANDIDATES_PER_VARIANT):
                truth = render.template_truth(variant, index)
                self.assertNotEqual(arithmetic.check_table(truth)["status"], arithmetic.FAIL, (variant, index))

    def test_variants_carry_their_tags(self):
        bound = render.template_truth("bound", 0)
        self.assertTrue(any(c["comparator"] == "<" for c in bound["cells"]))
        reference = render.template_truth("reference_intake_column", 0)
        ri = {c["nutrient"] for c in reference["cells"] if c["basis"] == "reference_intake"}
        self.assertNotIn("trans_fat", ri)
        self.assertNotIn("sugars", ri)
        text, _ = render.render_chinese(reference, "tab")
        self.assertIn("每日參考值百分比", text)
        self.assertIn("*", text)
        self.assertEqual(render.template_truth("servings_2_5", 0)["servings_per_pack"]["decimal_text"], "2.5")
        self.assertEqual(render.template_truth("per_100ml", 0)["headers"][1]["basis"], "per_100ml")


class RefillRuleTests(unittest.TestCase):
    def test_refills_are_limited_to_orders_61_to_87(self):
        ranked = [{"order": order, "barcode13": str(order)} for order in range(1, 90)]
        self.assertEqual([t["order"] for t in acquire_off_taiwan.refill_targets(ranked, [61, 62])], [61, 62])
        with self.assertRaises(ValueError):
            acquire_off_taiwan.refill_targets(ranked, [60])
        with self.assertRaises(ValueError):
            acquire_off_taiwan.refill_targets(ranked, [88])

    def test_manifest_records_the_development_replacements(self):
        manifest = json.loads((HERE / "fixtures" / "off-taiwan-manifest-v1.json").read_text())
        refills = {r["order"]: r for r in manifest["refills"] if r["split"] == "development"}
        self.assertEqual({o: r["replaces_order"] for o, r in refills.items()}, {61: 4, 62: 17})
        self.assertTrue(all("CC BY-SA 3.0" in r["attribution"] for r in refills.values()))
        photos = {p["order"]: p for p in manifest["photos"]}
        self.assertTrue(photos[4]["excluded"] and photos[17]["excluded"])
        self.assertLessEqual(sum(r["bytes"] for r in refills.values()), 5_000_000)

    def test_manifest_records_the_untouched_refills_in_hash_order(self):
        manifest = json.loads((HERE / "fixtures" / "off-taiwan-manifest-v1.json").read_text())
        refills = [r for r in manifest["refills"] if r["split"] == "untouched"]
        self.assertEqual([r["order"] for r in refills], list(range(63, 78)))
        self.assertTrue(all(r["replacement_reason"] and "CC BY-SA 3.0" in r["attribution"] for r in refills))
        self.assertLessEqual(sum(r["bytes"] for r in refills), 10_000_000)
        everything = {p["order"]: p for p in manifest["photos"] + manifest["refills"]}
        for refill in refills:
            replaced = everything[refill["replaces_order"]]
            self.assertTrue(replaced["excluded"] and replaced["exclusion_reason"] == refill["replacement_reason"])
        usable = [p for p in everything.values() if p["split"] == "untouched" and not p.get("excluded")]
        self.assertEqual(len(usable), 40)
        self.assertFalse(everything[34].get("excluded"))


class ContractTests(unittest.TestCase):
    def test_contract_is_valid(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        self.assertEqual(validate_contract.validate(contract), [])

    def test_wire_schema_within_union_limit(self):
        wire = json.loads((HERE / "openrouter" / "label-image-wire-schema-v1.json").read_text())
        self.assertLessEqual(validate_contract.count_unions(wire), 16)

    def test_changed_bar_is_rejected(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        contract["metrics"]["false_ready_maximum"] = 1
        self.assertIn("metrics differ from the plan's pre-registered bars", validate_contract.validate(contract))

    def test_route_c_disabled_in_phases_1_and_2(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        contract["status"] = "development_phase_2"
        contract["route_c"]["enabled"] = True
        self.assertIn("route C must stay disabled in phases 1 and 2", validate_contract.validate(contract))

    def test_enabled_route_c_pins_exactly_the_five_models_with_a_catalogue_record(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        self.assertIs(contract["route_c"]["enabled"], True)
        self.assertEqual(sorted(contract["route_c"]["models"]), ["fable", "gemini", "grok", "luna", "luna_pro", "opus", "sol", "sol_pro"])
        del contract["route_c"]["models"]["opus"]["catalogue_2026_10_17"]
        self.assertIn(
            "route C model opus passed the gate without a slug, endpoint, provider and catalogue record",
            validate_contract.validate(contract),
        )
        contract["route_c"]["models"]["qwen"] = {"slug": "qwen/qwen3.5-397b-a17b"}
        self.assertIn(
            "route C must pin exactly the approved models (five base models and three extra arms)", validate_contract.validate(contract)
        )

    def test_untouched_truth_hash_is_pinned(self):
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text())
        contract["ground_truth"]["untouched_sha256"] = "0" * 64
        self.assertIn("untouched ground truth hash does not match the contract", validate_contract.validate(contract))


class DevelopmentDatasetTests(unittest.TestCase):
    def test_dataset_is_development_only_and_hash_bound(self):
        loaded = cases.load_development_text(HERE / "synthetic" / "development-cases-v1.jsonl")
        self.assertGreaterEqual(len(loaded), 100)
        self.assertTrue(all(c["metadata"]["split"] == "development" for c in loaded))
        self.assertTrue(all(c["metadata"]["synthetic"] for c in loaded if c["metadata"]["corpus"] != "muesli_typed"))
        corpora = {c["metadata"]["corpus"] for c in loaded}
        self.assertEqual(corpora, {"v1", "v2dev", "muesli_typed", "fda188", "zh_template"})
        fda_dev = [c for c in loaded if c["metadata"]["corpus"] == "fda188" and not c["truth"]["requires_decline"]]
        self.assertGreaterEqual(len(fda_dev), 40)
        self.assertTrue(all(render.fda_split(c["metadata"]["fda_order_key"]) == "development" for c in fda_dev))

    def test_typed_muesli_matches_the_plan(self):
        loaded = {c["id"]: c for c in cases.load_development_text(HERE / "synthetic" / "development-cases-v1.jsonl")}
        truth = loaded["owner:muesli-6-grain:typed"]["truth"]
        values = {(c["nutrient"], c["basis"]): c["decimal_text"] for c in truth["cells"]}
        expected = {
            "energy_kcal": "367.2",
            "protein": "11",
            "fat": "8.8",
            "saturates": "1.2",
            "trans_fat": "0",
            "carbohydrate": "67",
            "sugars": "9.1",
            "fibre": "12",
            "sodium": "8",
        }
        for basis in ("per_serving", "per_100g"):
            self.assertEqual({k: v for (k, b), v in values.items() if b == basis}, expected)
        self.assertEqual(truth["servings_per_pack"]["decimal_text"], "5")
        self.assertEqual(truth["serving_size"]["decimal_text"], "100")


if __name__ == "__main__":
    unittest.main()
