"""Inspect wiring with no model or provider call: a stub parser stands in for the Swift CLI."""

import hashlib
import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

from helpers import HERE

STUB = """#!{python}
import json, sys
cases = json.load(sys.stdin)
out = []
for case in cases:
    out.append({{"id": case["id"], "parser_version": "stub", "candidate": {{
        "schema_version": "label-capture-candidate-v1", "route": "A", "input_sha256": "0" * 64,
        "status": "user_selection_only", "declined": True, "decline_reasons": ["no_table"],
        "ready_for_confirmation": False, "would_mark_ready": False, "automatic_save": False,
        "language": "unknown", "serving_size": "unknown", "servings_per_pack": "unknown",
        "headers": [], "cells": [], "warnings": []}}}})
json.dump(out, sys.stdout)
"""


VISION_STUB = """#!{python}
import json, sys
jobs = json.load(sys.stdin)
json.dump({{"adapter_version": "stub", "request_revision": 3, "recognition_languages": ["zh-Hant", "en-US"],
    "uses_language_correction": True, "operating_system": "stub",
    "results": [{{"id": j["id"], "image_sha256": "{digest}", "pixel_width": 1, "pixel_height": 1,
        "lines": [], "error": None}} for j in jobs]}},
    sys.stdout)
"""


@unittest.skipUnless(importlib.util.find_spec("inspect_ai"), "inspect_ai is not installed (see requirements.txt)")
class InspectWiringTests(unittest.TestCase):
    def test_route_a_task_scores_with_the_shared_scorer(self):
        from inspect_ai import eval as inspect_eval

        from inspect_task import label_capture_development_text

        loaded = [json.loads(line) for line in (HERE / "synthetic" / "development-cases-v1.jsonl").read_text().splitlines()]
        decline = next(c for c in loaded if c["truth"]["requires_decline"])
        usable = next(c for c in loaded if not c["truth"]["requires_decline"])
        with tempfile.TemporaryDirectory() as folder:
            dataset = Path(folder) / "cases.jsonl"
            dataset.write_text(json.dumps(decline) + "\n" + json.dumps(usable) + "\n")
            stub = Path(folder) / "stub-parser"
            stub.write_text(STUB.format(python=sys.executable))
            os.chmod(stub, stub.stat().st_mode | stat.S_IXUSR)
            logs = inspect_eval(
                label_capture_development_text(parser_binary=str(stub), dataset=str(dataset)),
                model="mockllm/model",
                log_dir=str(Path(folder) / "logs"),
                display="none",
            )
        log = logs[0]
        self.assertEqual(log.status, "success")
        assert log.results is not None
        metrics = {name: m.value for score in log.results.scores for name, m in score.metrics.items()}
        self.assertEqual(metrics["correct_decline"], 1.0)
        self.assertEqual(metrics["full_table"], 0.0)
        self.assertEqual(metrics["false_ready"], 0.0)

    def test_route_c_raises_while_disabled_and_makes_no_call(self):
        from inspect_ai import Task
        from inspect_ai import eval as inspect_eval
        from inspect_ai.dataset import Sample

        from budget import LedgerBudget
        from inspect_task import label_capture_scorer, route_c_openrouter

        sample = Sample(id="x", input="image:" + "0" * 64, target="{}", metadata={"image_path": "/nonexistent.jpg", "corpus": "off_taiwan"})
        with tempfile.TemporaryDirectory() as folder:
            budget = LedgerBudget(Path(folder) / "ledger.json")
            task = Task(dataset=[sample], solver=route_c_openrouter(budget), scorer=label_capture_scorer())
            log = inspect_eval(task, model="mockllm/model", log_dir=folder, display="none")[0]
            self.assertEqual(log.status, "error")
            self.assertIn("route C is disabled", str(log.error))
            self.assertFalse(log.stats.model_usage)
            self.assertEqual(json.loads((Path(folder) / "ledger.json").read_text())["entries"], [])

    def test_route_c_refuses_without_the_persistent_ledger(self):
        from budget import RunBudget
        from inspect_task import route_c_openrouter

        with self.assertRaises(TypeError):
            route_c_openrouter(RunBudget())  # type: ignore[arg-type]
        with self.assertRaises(TypeError):
            route_c_openrouter(None)  # type: ignore[arg-type]

    def test_route_c_records_purpose_and_sample_id(self):
        from inspect_ai import Task
        from inspect_ai import eval as inspect_eval
        from inspect_ai.dataset import Sample

        import inspect_task
        from budget import LedgerBudget
        from openrouter_route import RouteCModel

        target = RouteCModel(label="luna", model="mockllm/model", endpoint="azure", provider_name="Azure")
        raw = {"model": "mockllm/model", "provider": "Azure", "usage": {"cost": 0.01}, "choices": [{"finish_reason": "stop"}]}
        original = inspect_task._last_raw_response
        inspect_task._last_raw_response = lambda: raw
        try:
            with tempfile.TemporaryDirectory() as folder:
                image = Path(folder) / "a.png"
                image.write_bytes(b"\x89PNG\r\n\x1a\n")
                sample = Sample(id="case-1", input="image", target="{}", metadata={"image_path": str(image), "corpus": "off_taiwan"})
                budget = LedgerBudget(Path(folder) / "ledger.json")
                task = Task(
                    dataset=[sample],
                    solver=inspect_task.route_c_openrouter(budget, enabled=True, target=target),
                    scorer=inspect_task.label_capture_scorer(),
                )
                inspect_eval(task, model="mockllm/model", log_dir=folder, display="none")
                entries = json.loads((Path(folder) / "ledger.json").read_text())["entries"]
        finally:
            inspect_task._last_raw_response = original
        self.assertEqual([(e["purpose"], e["case_id"], e["cost_usd"]) for e in entries], [("route_c_development", "case-1", "0.01")])

    def test_route_b_task_runs_stub_vision_serialiser_and_parser(self):
        from inspect_ai import eval as inspect_eval

        from inspect_task import label_capture_development_photos

        loaded = [json.loads(line) for line in (HERE / "synthetic" / "development-cases-v1.jsonl").read_text().splitlines()]
        decline = next(c for c in loaded if c["truth"]["requires_decline"])
        with tempfile.TemporaryDirectory() as folder:
            image = Path(folder) / "development" / "a.jpg"
            image.parent.mkdir()
            image.write_bytes(b"not an image")
            digest = hashlib.sha256(image.read_bytes()).hexdigest()
            case = {
                "id": "photo",
                "input": {"kind": "image", "path": str(image)},
                "truth": decline["truth"],
                "metadata": {"corpus": "off_taiwan", "stratum": "taiwan_zh_hant", "split": "development", "sha256": digest},
            }
            cases_file = Path(folder) / "cases.json"
            cases_file.write_text(json.dumps([case]))
            vision = Path(folder) / "stub-vision"
            vision.write_text(VISION_STUB.format(python=sys.executable, digest=digest))
            parser = Path(folder) / "stub-parser"
            parser.write_text(STUB.format(python=sys.executable))
            for stub in (vision, parser):
                os.chmod(stub, stub.stat().st_mode | stat.S_IXUSR)
            log = inspect_eval(
                label_capture_development_photos(cases_file=str(cases_file), vision_binary=str(vision), parser_binary=str(parser)),
                model="mockllm/model",
                log_dir=str(Path(folder) / "logs"),
                display="none",
            )[0]
            self.assertEqual(log.status, "success")
            assert log.samples is not None
            self.assertEqual(log.samples[0].metadata["serialiser_version"], "label-capture-serialiser-v1")
            self.assertFalse(log.stats.model_usage)


if __name__ == "__main__":
    unittest.main()
