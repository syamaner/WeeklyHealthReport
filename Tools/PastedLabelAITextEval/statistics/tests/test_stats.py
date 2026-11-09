"""Tests for pasted_label_ai_text_stats on synthetic results, with hand-checked values.

Run: python3 -I -m unittest discover -s Tools/PastedLabelAITextEval/statistics/tests
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

# The script sits one directory up; `-I` leaves it off the path, so it is added explicitly.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pasted_label_ai_text_stats as stats  # noqa: E402

# bar-v2 is the bar A4 reads (D34); bar-v1 stays as history and differs only in bar 4 latency.
BAR = Path(__file__).resolve().parents[2] / "bar-v2.json"
BAR_V1 = Path(__file__).resolve().parents[2] / "bar-v1.json"


def scores(*, outcome="reached_confirm", printed=10, shown=10, correct=10, wrong=0, flagged=0, silent=0, attention=0, exact=None, no_edit=None,
           nutrients=None, reference_amounts=0, unrecognised_rows=0):
    exact = (outcome == "reached_confirm" and wrong == 0 and correct == printed) if exact is None else exact
    out = {"reached_confirm": int(outcome == "reached_confirm"), "declined": int(outcome == "declined"), "failed": int(outcome == "failed"),
           "fields_printed": printed, "fields_shown": shown if outcome == "reached_confirm" else 0,
           "fields_correct": correct if outcome == "reached_confirm" else 0, "fields_wrong": wrong, "wrong_flagged": flagged, "wrong_silent": silent,
           "attention_items": attention, "exact_match": int(exact), "no_edit": int(exact if no_edit is None else no_edit),
           "silent_error_table": int(silent > 0), "fields_reference_amounts": reference_amounts, "fields_unrecognised_rows": unrecognised_rows}
    for nutrient, counts in (nutrients or {}).items():
        for name, value in counts.items():
            out[f"nutrient.{nutrient}.{name}"] = value
    return out


def result(label, named, *, cost: str | None = "0.004", latency: float | None = 2.0, provider="model-a", prompt="prompt-v1", attempt="responded",
           reserved_w: str | None = "0.03"):
    send = {"attempt": attempt, "cost_usd": cost, "latency_seconds": 0.5, "reserved_w_usd": reserved_w}
    named = dict(named)
    if latency is not None:
        named["tap_latency_seconds"] = latency
    return {"vars": {"label_id": label}, "provider": {"id": "file://provider.js", "label": provider}, "prompt": {"label": prompt},
            "gradingResult": {"namedScores": named}, "response": {"output": json.dumps(send)}}


def write(rows) -> Path:
    handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
    json.dump({"results": {"results": rows}}, handle)
    handle.close()
    return Path(handle.name)


class IntervalTests(unittest.TestCase):
    def test_wilson_five_of_ten(self):
        # Hand check: centre 0.5; half-width z * sqrt(0.025 + z^2 / 400) / (1 + z^2 / 10) = 0.263405.
        low, high = stats.wilson(5, 10)
        self.assertAlmostEqual(low, 0.236595, places=5)
        self.assertAlmostEqual(high, 0.763405, places=5)

    def test_wilson_eight_of_twenty_four(self):
        # p = 1/3, z^2 = 3.841459: denominator 1.160061, centre (0.333333 + 0.080030) / 1.160061 = 0.356329,
        # half 1.959964 * sqrt(0.009259 + 0.001667) / 1.160061 = 0.176599.
        low, high = stats.wilson(8, 24)
        self.assertAlmostEqual(low, 0.179730, places=4)
        self.assertAlmostEqual(high, 0.532928, places=4)

    def test_clopper_pearson_at_zero_and_total(self):
        # 0 of 24: upper = 1 - 0.025^(1/24) = 0.142474, the spec's "about 14%" (5.2.1).
        low, high = stats.clopper_pearson(0, 24)
        self.assertEqual(low, 0.0)
        self.assertAlmostEqual(high, 1 - 0.025 ** (1 / 24), places=9)
        self.assertAlmostEqual(high, 0.142474, places=5)
        low, high = stats.clopper_pearson(24, 24)
        self.assertAlmostEqual(low, 0.025 ** (1 / 24), places=9)
        self.assertEqual(high, 1.0)

    def test_clopper_pearson_interior_matches_the_binomial_tails(self):
        low, high = stats.clopper_pearson(3, 10)
        self.assertAlmostEqual(1 - stats._binomial_cdf(2, 10, low), 0.025, places=9)
        self.assertAlmostEqual(stats._binomial_cdf(3, 10, high), 0.025, places=9)
        # Published values for 3 of 10: (0.0667, 0.6525).
        self.assertAlmostEqual(low, 0.066739, places=5)
        self.assertAlmostEqual(high, 0.652453, places=5)

    def test_proportion_chooses_the_method(self):
        self.assertEqual(stats.proportion(0, 24)["method"], "clopper_pearson")
        self.assertEqual(stats.proportion(24, 24)["method"], "clopper_pearson")
        self.assertEqual(stats.proportion(5, 10)["method"], "wilson")
        self.assertIsNone(stats.proportion(0, 0)["value"])


class OrderStatisticTests(unittest.TestCase):
    def test_upper_median_is_rank_thirteen_of_twenty_four(self):
        values = [float(v) for v in range(24, 0, -1)]
        self.assertEqual(stats.upper_median(values), 13.0)
        self.assertEqual(stats.upper_median([1.0, 2.0, 3.0]), 2.0)
        self.assertEqual(stats.upper_median([1.0, 2.0]), 2.0, "the upper of the two middle values")

    def test_nearest_rank_p90_is_rank_twenty_two_of_twenty_four(self):
        values = [float(v) for v in range(1, 25)]
        self.assertEqual(stats.nearest_rank(values, 90), 22.0)
        self.assertEqual(stats.nearest_rank([5.0], 90), 5.0)
        self.assertEqual(stats.nearest_rank([float(v) for v in range(1, 11)], 90), 9.0)


class MetricTests(unittest.TestCase):
    def labels(self):
        rows = [
            result("a", scores(printed=10, shown=10, correct=10)),
            result("b", scores(printed=10, shown=8, correct=6, wrong=2, flagged=1, silent=1, attention=3)),
            result("c", scores(outcome="declined", printed=5)),
            result("d", scores(outcome="failed", printed=5), cost=None, attempt="transport_failed:timed_out"),
        ]
        return stats.load_results(write(rows))["model-a|prompt-v1"]

    def test_field_metrics_by_hand(self):
        metrics = stats.field_metrics(self.labels())
        m: dict[str, float] = {}
        for name, value in metrics.items():
            self.assertIsNotNone(value, name)
            assert value is not None  # narrows the type for the checker
            m[name] = value
        # Micro: correct 16 of 18 shown and of 30 printed.
        self.assertAlmostEqual(m["field_precision_micro"], 16 / 18)
        self.assertAlmostEqual(m["field_recall_micro"], 16 / 30)
        p, r = 16 / 18, 16 / 30
        self.assertAlmostEqual(m["field_f1_micro"], 2 * p * r / (p + r))
        # Macro precision over the two labels reaching Confirm: (1 + 0.75) / 2.
        self.assertAlmostEqual(m["field_precision_macro"], 0.875)
        # Macro recall over all four labels, a failed or declined label scoring 0: (1 + 0.6 + 0 + 0) / 4.
        self.assertAlmostEqual(m["field_recall_macro"], 0.4)
        # Macro F1: label b's F1 is 2 * 0.75 * 0.6 / 1.35 = 0.666667.
        self.assertAlmostEqual(m["field_f1_macro"], (1 + 2 * 0.75 * 0.6 / 1.35) / 4)
        self.assertAlmostEqual(m["error_detection_recall"], 0.5)
        self.assertAlmostEqual(m["error_detection_precision"], 1 / 3)
        self.assertAlmostEqual(m["attention_items_per_table"], 1.5)

    def test_label_level_proportions(self):
        p = stats.label_proportions(self.labels())
        self.assertEqual((p["coverage"]["count"], p["coverage"]["total"]), (2, 4))
        self.assertEqual((p["exact_match"]["count"], p["exact_match"]["total"]), (1, 4))
        self.assertEqual((p["silent_error_tables"]["count"], p["silent_error_tables"]["total"]), (1, 2))
        self.assertEqual((p["failed_or_declined_reads"]["count"], p["failed_or_declined_reads"]["total"]), (2, 4))
        self.assertEqual((p["risk"]["count"], p["risk"]["total"]), (1, 2))

    def test_unknown_cost_is_counted_at_the_cap_and_a_refusal_at_nothing(self):
        labels = self.labels()
        self.assertEqual([label.cost_usd for label in labels], [0.004, 0.004, 0.004, 0.03], "an unknown cost at the tap's own W")
        self.assertEqual(stats.tap_cost({"attempt": "refused:the $5 cell stop would be passed", "cost_usd": None}, 0.05), (0.0, True))
        self.assertEqual(stats.operational(labels)["cost_usd"]["unknown_counted_at_cap"], 1)

    def test_bootstrap_is_seeded_and_degenerate_samples_give_the_point(self):
        same = stats.load_results(write([result(f"l{i}", scores(printed=4, shown=4, correct=3, wrong=1, flagged=1, attention=1)) for i in range(6)]))
        boot = stats.bootstrap(same["model-a|prompt-v1"], 500, 7)
        self.assertEqual(boot["field_precision_micro"]["interval"], [0.75, 0.75])
        labels = self.labels()
        first = stats.bootstrap(labels, 300, 11)
        self.assertEqual(first, stats.bootstrap(labels, 300, 11), "the same seed gives the same intervals")
        low, high = first["field_recall_micro"]["interval"]
        self.assertLessEqual(low, 16 / 30)
        self.assertGreaterEqual(high, 16 / 30)

    def test_summary_sums_the_reference_amounts(self):
        # Scorer v3 (D28): RI amount values are counted beside the printed fields, never in them.
        rows = [result("a", scores(printed=7, reference_amounts=4)), result("b", scores(outcome="declined", printed=5, reference_amounts=2)),
                result("c", scores(printed=3))]
        out = stats.summary(stats.load_results(write(rows)), 50, 1, None)["cells"]["model-a|prompt-v1"]
        self.assertEqual(out["fields_reference_amounts"], 6)
        legacy = [{"vars": {"label_id": "x"}, "provider": {"label": "m"}, "prompt": {"label": "p"}, "gradingResult": {}, "response": {}}]
        self.assertEqual(stats.summary(stats.load_results(write(legacy)), 10, 1, None)["cells"]["m|p"]["fields_reference_amounts"], 0)

    def test_summary_sums_the_unrecognised_rows(self):
        # Scorer v4 (D29): unrecognised-row values are counted beside the printed fields, never in them.
        rows = [result("a", scores(printed=7, unrecognised_rows=3)), result("b", scores(outcome="failed", printed=5, unrecognised_rows=1))]
        out = stats.summary(stats.load_results(write(rows)), 50, 1, None)["cells"]["model-a|prompt-v1"]
        self.assertEqual(out["fields_unrecognised_rows"], 4)
        legacy = [{"vars": {"label_id": "x"}, "provider": {"label": "m"}, "prompt": {"label": "p"}, "gradingResult": {}, "response": {}}]
        self.assertEqual(stats.summary(stats.load_results(write(legacy)), 10, 1, None)["cells"]["m|p"]["fields_unrecognised_rows"], 0)

    def test_breakdown_by_nutrient(self):
        rows = [result("a", scores(nutrients={"fat": {"printed": 1, "shown": 1, "correct": 1, "wrong": 0}})),
                result("b", scores(nutrients={"fat": {"printed": 1, "shown": 1, "correct": 0, "wrong": 1}}))]
        labels = stats.load_results(write(rows))["model-a|prompt-v1"]
        self.assertEqual(stats.by_nutrient(labels), {"fat": {"printed": 2, "shown": 2, "correct": 1, "wrong": 1}})

    def test_bar_over_twenty_four_labels(self):
        rows = [result(f"h{i:02}", scores(), cost=f"{0.001 * (i + 1):.3f}", latency=float(i + 1)) for i in range(18)]
        rows += [result(f"h{i:02}", scores(outcome="declined"), cost="0.020", latency=30.0) for i in range(18, 24)]
        labels = stats.load_results(write(rows))["model-a|prompt-v1"]
        figures = stats.bar(labels, BAR)
        self.assertEqual(figures["bar_1"], {"value": 0, "pass": True})
        self.assertEqual(figures["bar_3"], {"value": 6, "pass": True}, "at most 6 of 24")
        # Costs 0.001 to 0.018 and six of 0.020: the 13th sorted is 0.013.
        self.assertAlmostEqual(figures["bar_4_cost"]["value"], 0.013)
        self.assertFalse(figures["bar_4_cost"]["pass"])
        # Latencies 1 to 18 and six of 30: the 22nd sorted is 30.
        self.assertEqual(figures["bar_4_latency"], {"value": 30.0, "missing": 0, "pass": False})

    def test_the_default_bar_is_bar_v2(self):
        self.assertEqual(stats.DEFAULT_BAR, BAR)
        self.assertEqual(json.loads(stats.DEFAULT_BAR.read_text(encoding="utf-8"))["schema"], "pasted-label-ai-text-bar-v2")
        # The summary command reads bar-v2 when --bar is not given: a p90 of 18 s passes.
        rows = [result(f"h{i:02}", scores(), cost="0.001", latency=1.0) for i in range(21)]
        rows += [result(f"h{i:02}", scores(), cost="0.001", latency=18.0) for i in range(21, 24)]
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(stats.main(["summary", str(write(rows)), "--resamples", "10"]), 0)
        figures = json.loads(out.getvalue())["cells"]["model-a|prompt-v1"]["bar"]
        self.assertEqual(figures["bar_4_latency"], {"value": 18.0, "missing": 0, "pass": True})

    def test_a_p90_of_eighteen_seconds_passes_bar_v2_and_fails_bar_v1(self):
        # 21 taps at 1 s and 3 at 18 s: the 22nd sorted latency is 18 s, over 15 s (v1) and within 20 s (D34).
        rows = [result(f"h{i:02}", scores(), cost="0.001", latency=1.0) for i in range(21)]
        rows += [result(f"h{i:02}", scores(), cost="0.001", latency=18.0) for i in range(21, 24)]
        labels = stats.load_results(write(rows))["model-a|prompt-v1"]
        self.assertEqual(stats.bar(labels, BAR)["bar_4_latency"], {"value": 18.0, "missing": 0, "pass": True})
        self.assertEqual(stats.bar(labels, BAR_V1)["bar_4_latency"], {"value": 18.0, "missing": 0, "pass": False})

    def test_a_p90_over_twenty_seconds_fails_bar_v2(self):
        rows = [result(f"h{i:02}", scores(), cost="0.001", latency=1.0) for i in range(21)]
        rows += [result(f"h{i:02}", scores(), cost="0.001", latency=20.5) for i in range(21, 24)]
        labels = stats.load_results(write(rows))["model-a|prompt-v1"]
        self.assertFalse(stats.bar(labels, BAR)["bar_4_latency"]["pass"])
        rows[-1] = result("h23", scores(), cost="0.001", latency=20.0)
        rows[-2] = result("h22", scores(), cost="0.001", latency=20.0)
        rows[-3] = result("h21", scores(), cost="0.001", latency=20.0)
        self.assertTrue(stats.bar(stats.load_results(write(rows))["model-a|prompt-v1"], BAR)["bar_4_latency"]["pass"], "at most 20 s")


class GateFiveTests(unittest.TestCase):
    def test_a_detector_decline_before_sending_costs_nothing_and_is_known(self):
        self.assertEqual(stats.tap_cost({"attempt": "declined_before_send:nutrition_facts_title", "cost_usd": None}, 0.05), (0.0, True))

    def test_a_missing_latency_fails_bar_four(self):
        rows = [result(f"h{i:02}", scores(), cost="0.001", latency=1.0) for i in range(23)]
        rows.append(result("h23", scores(), cost="0.001", latency=None))
        figures = stats.bar(stats.load_results(write(rows))["model-a|prompt-v1"], BAR)
        self.assertEqual(figures["bar_4_latency"]["missing"], 1)
        self.assertFalse(figures["bar_4_latency"]["pass"])

    def test_the_results_must_equal_the_case_set(self):
        with tempfile.TemporaryDirectory() as directory:
            cases = Path(directory)
            for label in ("a", "b"):
                (cases / f"{label}.json").write_text("{}", encoding="utf-8")
            self.assertEqual(len(stats.load_results(write([result("a", scores()), result("b", scores())]), cases)["model-a|prompt-v1"]), 2)
            with self.assertRaises(ValueError):
                stats.load_results(write([result("a", scores())]), cases)
            with self.assertRaises(ValueError):
                stats.load_results(write([result("a", scores()), result("b", scores()), result("c", scores())]), cases)


class QodoFindingTests(unittest.TestCase):
    def test_a_cached_tap_counts_once_at_its_original_cost(self):
        self.assertEqual(stats.tap_cost({"attempt": "responded", "cached": True, "cost_usd": None, "cached_cost_usd": "0.004",
                                         "charged_usd": "0"}, 0.05), (0.004, True))
        self.assertEqual(stats.tap_cost({"attempt": "responded", "cached": True, "cost_usd": None, "cached_cost_usd": None}, 0.2), (0.2, False))
        self.assertEqual(stats.tap_cost({"attempt": "responded", "cached": True, "cost_usd": None, "cached_cost_usd": None, "reserved_w_usd": "0.04"}, 0.2),
                         (0.04, False))
        rows = [result("a", scores()), result("b", scores())]
        rows[1]["response"]["output"] = json.dumps({"attempt": "responded", "cached": True, "cost_usd": None, "cached_cost_usd": "0.004",
                                                    "charged_usd": "0", "latency_seconds": 2.0})
        labels = stats.load_results(write(rows))["model-a|prompt-v1"]
        self.assertEqual([label.cost_usd for label in labels], [0.004, 0.004])
        self.assertEqual(stats.operational(labels)["cost_usd"]["charged_this_run"], 0.0, "the first row's send record has no charged_usd")

    def test_each_result_marks_exactly_one_outcome(self):
        for named in ({"reached_confirm": 1, "declined": 1}, {"reached_confirm": 0}, {"failed": 2}, {"declined": 0.5, "failed": 0.5}):
            with self.assertRaises(ValueError, msg=str(named)):
                stats.load_results(write([result("a", named)]))

    def test_layout_shape_breakdown_reports_not_assigned(self):
        with tempfile.TemporaryDirectory() as directory:
            cases = Path(directory)
            (cases / "a.json").write_text(json.dumps({"layout_shape": "misaligned", "tier": "A"}), encoding="utf-8")
            (cases / "b.json").write_text(json.dumps({"tier": "B"}), encoding="utf-8")
            labels = stats.load_results(write([result("a", scores()), result("b", scores())]), cases)["model-a|prompt-v1"]
            shapes = stats.breakdowns(labels)["layout_shape"]
            self.assertEqual(sorted(shapes), ["misaligned", "not assigned"])
            self.assertEqual(shapes["misaligned"]["labels"], 1)
            (cases / "b.json").write_text(json.dumps({"layout_shape": "zigzag"}), encoding="utf-8")
            with self.assertRaises(ValueError):
                stats.load_results(write([result("a", scores()), result("b", scores())]), cases)

    def test_macro_precision_reports_its_exclusions(self):
        rows = [result("a", scores()), result("b", scores(outcome="declined")), result("c", scores(shown=0, correct=0))]
        labels = stats.load_results(write(rows))["model-a|prompt-v1"]
        self.assertEqual(stats.macro_precision_exclusions(labels),
                         {"averaged_over": 1, "excluded_not_reaching_confirm": 1, "excluded_confirm_without_fields": 1})
        out = stats.summary({"m|p": labels}, 50, 1, None)
        self.assertEqual(out["cells"]["m|p"]["field_level"]["field_precision_macro"]["exclusions"]["excluded_not_reaching_confirm"], 1)


class ReReviewTests(unittest.TestCase):
    def test_an_unknown_cost_is_charged_at_its_own_w_or_the_ledger_cap(self):
        self.assertEqual(stats.tap_cost({"attempt": "transport_failed:timed_out", "cost_usd": None, "reserved_w_usd": "0.0426"}, 0.2), (0.0426, False))
        self.assertEqual(stats.tap_cost({"attempt": "transport_failed:timed_out", "cost_usd": None}, stats.PER_TAP_CAP_USD), (0.2, False))
        self.assertEqual(stats.PER_TAP_CAP_USD, 0.20, "D25: the ledger's per-call cap, never $0.05")

    def test_a_tap_that_reserved_nothing_costs_nothing(self):
        for send in ({}, {"attempt": "catalogue_failed:unavailable"}, {"attempt": "refused:the $5 cell stop would be passed"},
                     {"attempt": "not_sent:text_empty"}):
            self.assertEqual(stats.tap_cost(send, 0.2), (0.0, True), str(send))

    def test_tap_latency_runs_from_the_providers_start_to_the_assertions_end(self):
        self.assertEqual(stats.tap_latency({"tap_latency_seconds": 3.5}, {"latency_seconds": 2.0}), 3.5)
        self.assertEqual(stats.tap_latency({"tap_latency_seconds": 0.1}, {"latency_seconds": 2.0, "cached": True}), 2.1,
                         "a cached tap adds its original attempt time")
        self.assertIsNone(stats.tap_latency({}, {"latency_seconds": 2.0}), "the attempt-only time is not the tap latency")
        labels = stats.load_results(write([result("a", scores(), latency=4.0)]))["model-a|prompt-v1"]
        self.assertEqual((labels[0].latency_seconds, labels[0].attempt_latency), (4.0, 0.5))
        op = stats.operational(labels)
        self.assertEqual(op["latency_seconds"]["p90_nearest_rank"], 4.0)
        self.assertEqual(op["attempt_latency_seconds_diagnostic"]["p90_nearest_rank"], 0.5)


class CompareTests(unittest.TestCase):
    def test_mcnemar_exact_by_hand(self):
        # b = 1, c = 6: 2 * (C(7,0) + C(7,1)) / 2^7 = 0.125.
        self.assertAlmostEqual(stats.mcnemar_exact(1, 6), 0.125)
        self.assertEqual(stats.mcnemar_exact(0, 0), 1.0)
        self.assertEqual(stats.mcnemar_exact(3, 3), 1.0)
        # b = 0, c = 5: 2 / 32.
        self.assertAlmostEqual(stats.mcnemar_exact(0, 5), 0.0625)

    def test_compare_two_cells(self):
        rows = []
        for i in range(8):
            rows.append(result(f"l{i}", scores(exact=i < 7, correct=10 if i < 7 else 8, wrong=0 if i < 7 else 2, shown=10), provider="model-a"))
            rows.append(result(f"l{i}", scores(exact=i < 1, correct=10 if i < 1 else 8, wrong=0 if i < 1 else 2, shown=10), provider="model-b"))
        cells = stats.load_results(write(rows))
        out = stats.compare(cells, "model-a|prompt-v1", "model-b|prompt-v1", 400, 3)
        self.assertEqual(out["exact_match_mcnemar"], {"a_only": 6, "b_only": 0, "p_value_exact": 2 / 64})
        self.assertEqual(out["no_edit_mcnemar"], out["exact_match_mcnemar"], "no serving edits, so no edit follows exact match")
        self.assertGreater(out["field_f1_micro_paired_bootstrap"]["difference_a_minus_b"], 0)
        self.assertEqual(out, stats.compare(cells, "model-a|prompt-v1", "model-b|prompt-v1", 400, 3), "seeded")
        same = stats.compare(cells, "model-a|prompt-v1", "model-a|prompt-v1", 200, 3)
        self.assertEqual(same["field_f1_micro_paired_bootstrap"]["interval"], [0.0, 0.0])

    def test_compare_no_edit_apart_from_exact_match(self):
        # Every label exact in both cells; model-b needs a serving edit on three, and on one a declined
        # label (no edit 0) faces an edit-free model-a table. b = 4, c = 1: 2 * (C(5,0) + C(5,1)) / 2^5 = 0.375.
        rows = []
        for i in range(6):
            rows.append(result(f"l{i}", scores(no_edit=i != 5), provider="model-a"))
            if i == 3:
                rows.append(result(f"l{i}", scores(outcome="declined"), provider="model-b"))
            else:
                rows.append(result(f"l{i}", scores(no_edit=i not in (0, 1, 2)), provider="model-b"))
        out = stats.compare(stats.load_results(write(rows)), "model-a|prompt-v1", "model-b|prompt-v1", 100, 3)
        self.assertEqual(out["no_edit_mcnemar"], {"a_only": 4, "b_only": 1, "p_value_exact": 0.375})
        self.assertEqual(out["exact_match_mcnemar"], {"a_only": 1, "b_only": 0, "p_value_exact": 1.0})

    def test_a_result_without_named_scores_is_a_failed_label(self):
        rows = [{"vars": {"label_id": "x"}, "provider": {"label": "m"}, "prompt": {"label": "p"}, "gradingResult": {}, "response": {}}]
        labels = stats.load_results(write(rows))["m|p"]
        self.assertEqual(labels[0].outcome, "failed")
        self.assertEqual((labels[0].cost_usd, labels[0].cost_known), (0.0, True), "no send record: a failed tap that cost nothing")

    def test_a_label_twice_in_one_cell_is_refused(self):
        with self.assertRaises(ValueError):
            stats.load_results(write([result("a", scores()), result("a", scores())]))


if __name__ == "__main__":
    unittest.main()
