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

        target = RouteCModel(label="luna", model="openai/gpt-6-luna", endpoint="openai", provider_name="OpenAI")
        answer = {
            "declined": True,
            "decline_reasons": ["no_table"],
            "language": "unknown",
            "serving_size_text": "unknown",
            "servings_per_pack_text": "unknown",
            "headers": [],
            "rows": [],
        }
        replies = [
            (429, {"error": {"code": 429, "message": "rate limited"}}, {"Retry-After": "0"}),
            (
                200,
                {
                    "id": "gen-1",
                    "model": "openai/gpt-6-luna",
                    "provider": "OpenAI",
                    "usage": {"cost": 0.01},
                    "choices": [{"finish_reason": "stop", "message": {"content": json.dumps(answer)}}],
                },
                {},
            ),
        ]
        sent = []

        def post(body, timeout):  # noqa: ANN001, ANN202
            sent.append(body)
            status, payload, headers = replies[len(sent) - 1]
            return status, payload, headers, 0.1

        with tempfile.TemporaryDirectory() as folder:
            image = Path(folder) / "a.png"
            image.write_bytes(b"\x89PNG\r\n\x1a\n")
            metadata = {"image_path": str(image), "corpus": "off_taiwan", "sha256": "a" * 64}
            sample = Sample(id="case-1", input="image", target=json.dumps({"requires_decline": True}), metadata=metadata)
            budget = LedgerBudget(Path(folder) / "ledger.json")
            task = Task(
                dataset=[sample],
                solver=inspect_task.route_c_openrouter(budget, enabled=True, target=target, post=post, sleep=lambda _: None),
                scorer=inspect_task.label_capture_scorer(),
            )
            log = inspect_eval(task, model="mockllm/model", log_dir=folder, display="none")[0]
            ledger = json.loads((Path(folder) / "ledger.json").read_text())
            call = (log.samples or [])[0].metadata["route_c"]
        self.assertEqual(log.status, "success")
        self.assertFalse(log.stats.model_usage)  # Inspect's generate is never called
        self.assertEqual(len(sent), 2)
        self.assertNotIn("Bearer", json.dumps(sent))
        self.assertEqual(
            [(e["purpose"], e["case_id"], e["cost_usd"], e.get("kind"), e.get("attempt")) for e in ledger["entries"]],
            [
                ("route_c_development", "case-1", None, "retryable_error_unknown_cost", 1),
                ("route_c_development", "case-1", "0.01", None, 2),
            ],
        )
        self.assertEqual((ledger["open_calls"], ledger["unknown_cost_calls"]), (0, 0))
        self.assertEqual((call["attempts"], call["retries"], call["cost_usd"]), (2, 1, "0.01"))

    def _run_route_c_once(self, reply: dict) -> tuple[int, dict, dict]:
        """Run the route C solver on one sample against a scripted OpenRouter reply; return (posts, ledger, metadata)."""
        from inspect_ai import Task
        from inspect_ai import eval as inspect_eval
        from inspect_ai.dataset import Sample

        import inspect_task
        from budget import LedgerBudget
        from openrouter_route import RouteCModel

        target = RouteCModel(label="luna", model="openai/gpt-6-luna", endpoint="openai", provider_name="OpenAI")
        sent: list[dict] = []

        def post(body, timeout):  # noqa: ANN001, ANN202
            sent.append(body)
            return 200, reply, {}, 0.1

        with tempfile.TemporaryDirectory() as folder:
            image = Path(folder) / "a.png"
            image.write_bytes(b"\x89PNG\r\n\x1a\n")
            metadata = {"image_path": str(image), "corpus": "off_taiwan", "sha256": "a" * 64}
            sample = Sample(id="c", input="image", target=json.dumps({"requires_decline": True}), metadata=metadata)
            budget = LedgerBudget(Path(folder) / "ledger.json")
            task = Task(
                dataset=[sample],
                solver=inspect_task.route_c_openrouter(budget, enabled=True, target=target, post=post, sleep=lambda _: None),
                scorer=inspect_task.label_capture_scorer(),
            )
            log = inspect_eval(task, model="mockllm/model", log_dir=folder, display="none")[0]
            ledger = json.loads((Path(folder) / "ledger.json").read_text())
            sample_metadata = dict((log.samples or [])[0].metadata)
        return len(sent), ledger, sample_metadata

    def test_route_c_schema_invalid_200_is_a_failed_case_after_one_attempt(self):
        reply = {
            "id": "gen-1",
            "model": "openai/gpt-6-luna",
            "provider": "OpenAI",
            "usage": {"cost": 0.001},
            "choices": [{"finish_reason": "stop", "message": {"content": json.dumps({"declined": False, "columns": []})}}],
        }
        posts, ledger, metadata = self._run_route_c_once(reply)
        self.assertEqual(posts, 1)
        self.assertEqual(metadata["route_c"]["retries"], 0)
        self.assertTrue(metadata["route_c_failed"][0].startswith("schema-invalid output"))
        self.assertEqual([e["cost_usd"] for e in ledger["entries"]], ["0.001"])

    def test_route_c_truncated_answer_is_not_retried(self):
        reply = {
            "id": "gen-2",
            "model": "openai/gpt-6-luna",
            "provider": "OpenAI",
            "usage": {"cost": 0.002},
            "choices": [{"finish_reason": "length", "message": {"content": '{"declined": fal'}}],
        }
        posts, ledger, metadata = self._run_route_c_once(reply)
        self.assertEqual(posts, 1)
        self.assertEqual(metadata["route_c_failed"], ["finish_reason 'length'"])
        self.assertEqual(ledger["unknown_cost_calls"], 0)

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
