"""Route C routing and response checks; no model or provider call."""

import json
import unittest
from decimal import Decimal

import helpers  # noqa: F401  (puts the harness folder on sys.path)

import openrouter_route
from openrouter_route import RouteCModel

TARGET = RouteCModel(label="luna", model="openai/gpt-6-luna", endpoint="azure", provider_name="Azure")


def response(**overrides):
    raw = {"model": "openai/gpt-6-luna", "provider": "Azure", "usage": {"cost": 0.0042}, "choices": [{"finish_reason": "stop"}]}
    raw.update(overrides)
    return raw


class ProviderBlockTests(unittest.TestCase):
    def test_drafting_block_keeps_zdr_and_no_collection(self):
        self.assertEqual(
            openrouter_route.provider_block("azure"),
            {
                "only": ["azure"],
                "order": ["azure"],
                "allow_fallbacks": False,
                "require_parameters": True,
                "data_collection": "deny",
                "zdr": True,
            },
        )

    def test_route_c_request_pins_one_provider_without_zdr_for_the_evaluation(self):
        body = openrouter_route.route_c_request_body(TARGET, "data:image/png;base64,AA==", "instruction", {"type": "object"})
        self.assertEqual(body["provider"], {"only": ["azure"], "order": ["azure"], "allow_fallbacks": False, "require_parameters": True})
        self.assertEqual((body["max_tokens"], body["stream"], body["reasoning"]), (16384, False, {"enabled": False}))
        self.assertTrue(body["response_format"]["json_schema"]["strict"])
        self.assertTrue(body["response_format"]["json_schema"]["description"])  # never null (Luna on Azure ignored the schema)
        on = RouteCModel(label="luna", model="openai/gpt-6-luna", endpoint="openai", provider_name="OpenAI", reasoning="on")
        self.assertEqual(openrouter_route.route_c_request_body(on, "d", "i", {})["reasoning"], {"enabled": True})
        with self.assertRaises(ValueError):
            openrouter_route.route_c_request_body(RouteCModel("x", "m", "e", "p", reasoning="low"), "d", "i", {})

    def test_comments_are_stripped_at_every_depth_and_nothing_else_changes(self):
        schema = {
            "$comment": "top",
            "type": "object",
            "properties": {"rows": {"type": "array", "items": {"$comment": "nested", "type": "object", "required": ["a"]}}},
            "anyOf": [{"$comment": "in a list", "required": ["rows"]}],
        }
        sent = openrouter_route.route_c_request_body(TARGET, "d", "i", schema)["response_format"]["json_schema"]["schema"]
        self.assertNotIn("$comment", json.dumps(sent))
        self.assertEqual(sent["properties"]["rows"]["items"], {"type": "object", "required": ["a"]})
        self.assertEqual(sent["anyOf"], [{"required": ["rows"]}])
        self.assertIn("$comment", schema)  # the caller's schema is not modified


class ResponseTests(unittest.TestCase):
    def test_matching_response_is_accepted(self):
        self.assertEqual(openrouter_route.route_mismatches(response(), TARGET), [])

    def test_model_or_provider_mismatch_fails(self):
        self.assertTrue(openrouter_route.route_mismatches(response(model="openai/gpt-6.1-sol"), TARGET))
        self.assertTrue(openrouter_route.route_mismatches(response(provider="OpenAI"), TARGET))
        self.assertTrue(openrouter_route.route_mismatches(None, TARGET))

    def test_truncation_fails(self):
        self.assertTrue(openrouter_route.route_mismatches(response(choices=[{"finish_reason": "length"}]), TARGET))

    def test_reported_cost(self):
        self.assertEqual(openrouter_route.reported_cost(response()), Decimal("0.0042"))

    def test_missing_cost_is_unknown_not_zero(self):
        self.assertIsNone(openrouter_route.reported_cost(response(usage={})))
        self.assertIsNone(openrouter_route.reported_cost(response(usage={"cost": None})))
        self.assertIsNone(openrouter_route.reported_cost(response(usage={"cost": True})))
        self.assertIsNone(openrouter_route.reported_cost(None))


if __name__ == "__main__":
    unittest.main()
