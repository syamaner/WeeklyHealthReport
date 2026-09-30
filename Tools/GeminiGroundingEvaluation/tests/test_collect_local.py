import json
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from collect_local import capture, project_completed, request_body  # noqa: E402
from evaluate import EvaluationError  # noqa: E402


class LocalCollectorTests(unittest.TestCase):
    def setUp(self):
        self.cases = [
            {"id": "g01", "split": "development", "food_terms": "Greek yoghurt 5%"},
            {"id": "g02", "split": "development", "food_terms": "whole goat milk"},
            {"id": "h01", "split": "holdout", "food_terms": "unseen food"},
        ]
        self.key = "synthetic-example-key-123456"

    def completed_reply(self):
        answer = "Manufacturer confirms a 5% plain yoghurt."
        return json.dumps({"status": "completed", "steps": [
            {"type": "model_output", "content": [{"type": "text", "text": answer,
             "annotations": [{"type": "url_citation", "title": "Manufacturer",
                              "url": "https://example.org/yoghurt", "start_index": 0,
                              "end_index": len(answer.encode("utf-8"))}]}]},
            {"type": "google_search_result", "result": [{"search_suggestions": "<div>private</div>"}]}
        ]}).encode()

    def test_journals_attempt_and_projection_before_next_request(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "run"
            calls = []

            def fetch(body, key):
                calls.append(json.loads(body))
                self.assertEqual(key, self.key)
                journal = json.loads((output / "attempts.json").read_text())
                self.assertEqual(journal["attempts"][-1]["outcome"], "started")
                if len(calls) == 1:
                    return 200, self.completed_reply()
                saved = json.loads((output / "replay.json").read_text())
                self.assertEqual([row["case_id"] for row in saved["results"]], ["g01"])
                raise TimeoutError("synthetic timeout")

            journal = capture(self.cases, ["g01", "g02"], "synthetic instruction", self.key,
                              output, "synthetic-run", "2026-09-28", fetch)
            self.assertEqual([row["outcome"] for row in journal["attempts"]],
                             ["completed", "timeout"])
            self.assertEqual(len(calls), 2)
            self.assertEqual(calls[0]["tools"], [{"type": "google_search"}])
            self.assertIs(calls[0]["store"], False)
            self.assertEqual(calls[0]["input"], "Greek yoghurt 5%")
            replay = json.loads((output / "replay.json").read_text())
            self.assertEqual(len(replay["results"]), 1)
            self.assertEqual(replay["results"][0]["leads"][0]["cited_text"],
                             "Manufacturer confirms a 5% plain yoghurt.")
            self.assertTrue(replay["results"][0]["suggestions_present"])
            for path in (output / "replay.json", output / "attempts.json"):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
                self.assertNotIn(self.key, path.read_text())
                self.assertNotIn("<div>private</div>", path.read_text())

    def test_noncompleted_status_stops_without_retry_or_raw_save(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "run"
            calls = []

            def fetch(body, key):
                calls.append(body)
                return 200, b'{"status":"in_progress","id":"do-not-save","steps":[]}'

            journal = capture(self.cases, ["g01", "g02"], "prompt", self.key,
                              output, "synthetic-run", "2026-09-28", fetch)
            self.assertEqual(len(calls), 1)
            self.assertEqual(journal["attempts"][0]["interaction_status"], "in_progress")
            self.assertEqual(journal["attempts"][0]["outcome"], "non_completed")
            self.assertEqual(json.loads((output / "replay.json").read_text())["results"], [])
            self.assertNotIn("do-not-save", (output / "attempts.json").read_text())

    def test_holdout_rejected_before_output_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "run"
            with self.assertRaisesRegex(EvaluationError, "development cases only"):
                capture(self.cases, ["h01"], "prompt", self.key, output,
                        "synthetic-run", "2026-09-28", lambda body, key: None)
            self.assertFalse(output.exists())

    def test_bad_citation_fails_closed(self):
        reply = json.loads(self.completed_reply())
        reply["steps"][0]["content"][0]["annotations"][0]["end_index"] = 9999
        with self.assertRaisesRegex(EvaluationError, "invalid citation"):
            project_completed("g01", reply)

    def test_thinking_level_is_explicit_only_for_configured_variant(self):
        original = json.loads(request_body("milk", "prompt"))
        self.assertEqual(original["generation_config"], {"max_output_tokens": 2048})
        low = json.loads(request_body("milk", "prompt", "low"))
        self.assertEqual(low["generation_config"],
                         {"max_output_tokens": 2048, "thinking_level": "low"})
        with self.assertRaisesRegex(EvaluationError, "unsupported thinking level"):
            request_body("milk", "prompt", "minimal")


if __name__ == "__main__":
    unittest.main()
