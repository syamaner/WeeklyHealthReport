"""Phase 5 (#255): round-3 truth answers and the untouched-run guards. Offline; no provider call."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import helpers  # noqa: F401  (puts the harness folder on sys.path)

import cases
import run_untouched

HERE = Path(__file__).resolve().parents[1]


def gemini_pin() -> dict:
    contract = json.loads((HERE / "frozen-contract-v1.json").read_text(encoding="utf-8"))
    return contract["route_c"]["models"]["gemini"]


def catalogue_entry(pin: dict, **changes: object) -> dict:
    catalogue = pin["catalogue_2026_10_17"]
    endpoint = {
        "tag": pin["endpoint"],
        "provider_name": pin["provider_name"],
        "pricing": {
            "prompt": str(float(catalogue["prompt_usd_per_million"]) / 1_000_000),
            "completion": str(float(catalogue["completion_usd_per_million"]) / 1_000_000),
        },
        "supported_parameters": ["response_format", "structured_outputs", "reasoning", "max_tokens", "temperature"],
        "status": catalogue["status"],
    }
    endpoint.update(changes)
    return {"id": pin["slug"], "architecture": {"input_modalities": ["text", "image"]}, "endpoints": [endpoint]}


class RoundThreeTruth(unittest.TestCase):
    def test_order_3_is_no_longer_a_required_decline_and_is_not_scored(self) -> None:
        truth = json.loads((HERE / "fixtures" / "ground-truth-off-taiwan-development-v1.json").read_text(encoding="utf-8"))
        record = next(r for r in truth["records"] if r["case_id"] == "off-taiwan:4710228034096:nutrition_zh.7")
        self.assertIs(record["requires_decline"], False)
        self.assertIs(record["excluded_from_scoring"], True)
        self.assertEqual(record["cells"], [])  # nothing invented
        self.assertEqual(record["owner_verified_cells"][0]["printed_text"], "19毫克")
        self.assertEqual(truth["counts"]["required_declines"], 4)

    def test_the_development_loader_leaves_out_an_excluded_from_scoring_record(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "development").mkdir()
            image = root / "development" / "03-4710228034096-nutrition_zh.7.jpg"
            image.write_bytes(b"x")
            sha = cases.sha256_file(image)
            manifest = root / "manifest.json"
            photo = {"split": "development", "order": 3, "barcode13": "4710228034096", "revision": 7, "sha256": sha, "attribution": "a"}
            manifest.write_text(json.dumps({"photos": [photo], "licence": "CC BY-SA 3.0"}), encoding="utf-8")
            truth = root / "truth.json"
            record = {"case_id": "off-taiwan:4710228034096:nutrition_zh.7", "excluded_from_scoring": True}
            truth.write_text(json.dumps({"records": [record]}), encoding="utf-8")
            self.assertEqual(cases.load_development_photos(manifest, root, truth), [])
            record["excluded_from_scoring"] = False
            truth.write_text(json.dumps({"records": [record]}), encoding="utf-8")
            self.assertEqual(len(cases.load_development_photos(manifest, root, truth)), 1)


class UntouchedRunGuards(unittest.TestCase):
    def test_catalogue_unchanged_passes(self) -> None:
        pin = gemini_pin()
        self.assertEqual(run_untouched.catalogue_check(catalogue_entry(pin), pin), [])

    def test_any_catalogue_change_stops(self) -> None:
        pin = gemini_pin()
        for changes in (
            {"provider_name": "Someone Else"},
            {"pricing": {"prompt": "0.000003", "completion": "0.00001"}},
            {"supported_parameters": ["response_format", "reasoning", "max_tokens"]},
            {"status": -2},
            {"tag": "google-vertex"},
        ):
            self.assertTrue(run_untouched.catalogue_check(catalogue_entry(pin, **changes), pin), changes)
        self.assertTrue(run_untouched.catalogue_check({"error": "HTTPError"}, pin))
        renamed = catalogue_entry(pin)
        renamed["id"] = "google/gemini-4-argon-preview"
        self.assertTrue(run_untouched.catalogue_check(renamed, pin))

    def test_each_route_and_arm_runs_once(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            register = Path(folder) / "register.json"
            run_untouched.register_start(register, "C", "gemini-on", Path(folder))
            run_untouched.register_finish(register, "C", "gemini-on", "failed: HTTPError")
            with self.assertRaises(SystemExit):
                run_untouched.register_start(register, "C", "gemini-on", Path(folder))
            run_untouched.register_start(register, "C", "sol-on", Path(folder))

    def test_only_the_frozen_arms_with_their_development_settings(self) -> None:
        contract = json.loads((HERE / "frozen-contract-v1.json").read_text(encoding="utf-8"))
        self.assertEqual(sorted(contract["untouched_run"]["route_c_arms"]), ["gemini-on", "luna-off", "sol-on"])
        target = run_untouched.untouched_arm(contract, "luna-off")
        self.assertEqual((target.model, target.endpoint, target.reasoning), ("openai/gpt-6-luna", "openai", "off"))
        with self.assertRaises(SystemExit):
            run_untouched.untouched_arm(contract, "grok-on")

    def test_route_b_reads_untouched_photos_only_after_the_unseal(self) -> None:
        import importlib.util

        if importlib.util.find_spec("inspect_ai") is None:
            self.skipTest("inspect_ai is not installed")
        import inspect_task

        sealed = {"split": "untouched", "image_path": "/x/sealed/01.jpg", "corpus": "off_taiwan"}
        with self.assertRaises(cases.SealedSetError):
            inspect_task.route_b_input_allowed(sealed)
        inspect_task.route_b_input_allowed({**sealed, "unsealed_for_run": True})
        with self.assertRaises(cases.SealedSetError):
            inspect_task.route_b_input_allowed({**sealed, "unsealed_for_run": "yes"})


if __name__ == "__main__":
    unittest.main()
