"""Route C routing and response checks; no model or provider call."""

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
    def test_pins_one_endpoint_with_zdr_and_no_collection(self):
        self.assertEqual(
            openrouter_route.model_args(TARGET),
            {
                "provider": {
                    "only": ["azure"],
                    "order": ["azure"],
                    "allow_fallbacks": False,
                    "require_parameters": True,
                    "data_collection": "deny",
                    "zdr": True,
                }
            },
        )


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
