"""Inspect wiring, offline: a stub parser stands in for the Swift CLI; no model is called."""

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
            logs = inspect_eval(label_capture_development_text(parser_binary=str(stub), dataset=str(dataset)),
                                model="mockllm/model", log_dir=str(Path(folder) / "logs"), display="none")
        log = logs[0]
        self.assertEqual(log.status, "success")
        metrics = {name: m.value for score in log.results.scores for name, m in score.metrics.items()}
        self.assertEqual(metrics["correct_decline"], 1.0)
        self.assertEqual(metrics["full_table"], 0.0)
        self.assertEqual(metrics["false_ready"], 0.0)

    def test_route_b_and_c_are_not_runnable_in_phase_1(self):
        from inspect_task import route_b_vision, route_c_openrouter

        self.assertTrue(callable(route_b_vision()))
        self.assertTrue(callable(route_c_openrouter()))


if __name__ == "__main__":
    unittest.main()
