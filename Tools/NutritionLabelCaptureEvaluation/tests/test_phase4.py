"""Phase 4 (#255): the decline gate and the whole-call deadline. Offline; no provider call.

The deadline tests start a local HTTP server on 127.0.0.1 only.
"""

from __future__ import annotations

import copy
import http.server
import importlib.util
import json
import threading
import time
import unittest
from typing import Any

from helpers import candidate_from_truth, declined_candidate, muesli_truth

import decline_gate as gate
import openrouter_client
from candidate import validate_candidate

TW = gate.TAIWAN
UK = gate.UK


def uk_cell(row: str, nutrient: str, header: str, basis: str, printed: str, number: str, unit: str, parent: str | None = None) -> dict:
    canonical = {"kJ": "kJ", "kcal": "kcal", "g": "g", "%": "%"}[unit]
    return {
        "row_id": row,
        "parent_row_id": parent,
        "nutrient": nutrient,
        "printed_label": row.replace("_", " ").title(),
        "header_id": header,
        "basis": basis,
        "printed_text": printed,
        "comparator": "=",
        "decimal_text": number,
        "unit": unit,
        "canonical_unit": canonical,
        "serving_conversion": "30g" if basis == "per_serving" else "not_applicable",
    }


def uk_truth() -> dict[str, Any]:
    rows = [
        ("energy_kj", "energy_kj", "1050kJ", "1050", "kJ", "315kJ", "315", None),
        ("energy_kcal", "energy_kcal", "250kcal", "250", "kcal", "75kcal", "75", None),
        ("fat", "fat", "9.0g", "9.0", "g", "2.7g", "2.7", None),
        ("saturates", "saturates", "3.2g", "3.2", "g", "1.0g", "1.0", "fat"),
        ("carbohydrate", "carbohydrate", "36g", "36", "g", "10.8g", "10.8", None),
        ("sugars", "sugars", "12g", "12", "g", "3.6g", "3.6", "carbohydrate"),
        ("protein", "protein", "6.0g", "6.0", "g", "1.8g", "1.8", None),
        ("salt", "salt", "0.45g", "0.45", "g", "0.14g", "0.14", None),
    ]
    cells = []
    for row, nutrient, p100, n100, unit, pserv, nserv, parent in rows:
        cells.append(uk_cell(row, nutrient, "h100", "per_100g", p100, n100, unit, parent))
        cells.append(uk_cell(row, nutrient, "hserv", "per_serving", pserv, nserv, unit, parent))
    return {
        "language": "en",
        "headers": [
            {"header_id": "h100", "printed_text": "per 100g", "basis": "per_100g", "serving_conversion": None},
            {"header_id": "hserv", "printed_text": "per 30g serving", "basis": "per_serving", "serving_conversion": "30g"},
        ],
        "serving_size": {"printed_text": "30g", "decimal_text": "30", "unit": "g", "canonical_unit": "g"},
        "servings_per_pack": {"printed_text": "10 servings", "decimal_text": "10", "approximate": False},
        "cells": cells,
    }


def uk_candidate(**changes: Any) -> dict[str, Any]:
    candidate = candidate_from_truth(uk_truth(), route="C")
    candidate.update(changes)
    return candidate


def tw_candidate() -> dict[str, Any]:
    return candidate_from_truth(muesli_truth(), route="C")


def without(candidate: dict[str, Any], nutrient: str, header: str | None = None) -> dict[str, Any]:
    changed = copy.deepcopy(candidate)
    changed["cells"] = [c for c in changed["cells"] if not (c["nutrient"] == nutrient and (header is None or c["header_id"] == header))]
    return changed


def run_gate(candidate: dict[str, Any], label_format: str) -> tuple[dict[str, Any], dict[str, Any]]:
    gated, report = gate.apply_gate(candidate, label_format)
    assert gated is not None
    return gated, report


class CompleteTablesPass(unittest.TestCase):
    def test_complete_taiwan_and_uk_candidates_pass_byte_for_byte(self) -> None:
        for candidate, label_format in ((tw_candidate(), TW), (uk_candidate(), UK)):
            before = copy.deepcopy(candidate)
            self.assertEqual(validate_candidate(candidate), [])
            gated, report = gate.apply_gate(candidate, label_format)
            self.assertIs(gated, candidate)
            self.assertEqual(gated, before)
            self.assertEqual((report["declines"], report["blocks"]), ([], []))

    def test_failed_and_already_declined_candidates_pass_through(self) -> None:
        broken = {"schema_version": "x"}
        self.assertIs(gate.apply_gate(broken, UK)[0], broken)
        self.assertEqual(gate.apply_gate(broken, UK)[1]["skipped"], "failed_candidate")
        self.assertIsNone(gate.apply_gate(None, UK)[0])
        declined = declined_candidate()
        self.assertIs(gate.apply_gate(declined, TW)[0], declined)

    def test_unknown_format_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            gate.apply_gate(uk_candidate(), "us_nutrition_facts")


class NeverChangesAValue(unittest.TestCase):
    def assert_declined(self, gated: dict[str, Any], reason: str) -> None:
        self.assertEqual(validate_candidate(gated), [])
        self.assertTrue(gated["declined"])
        self.assertFalse(gated["would_mark_ready"])
        self.assertEqual(gated["cells"], [])
        self.assertIn(f"gate:{reason}", gated["decline_reasons"])

    def test_a_decline_withholds_cells_and_leaves_the_input_untouched(self) -> None:
        candidate = without(tw_candidate(), "sodium")
        before = copy.deepcopy(candidate)
        gated, _ = run_gate(candidate, TW)
        self.assert_declined(gated, "required_row_missing")
        self.assertEqual(candidate, before)

    def test_a_block_changes_only_ready_and_warnings(self) -> None:
        candidate = uk_candidate()
        candidate["headers"] = [h for h in candidate["headers"] if h["basis"] != "per_100g"]
        candidate["cells"] = [c for c in candidate["cells"] if c["basis"] != "per_100g"]
        gated, report = run_gate(candidate, UK)
        self.assertEqual(report["blocks"], ["required_basis_missing"])
        self.assertFalse(gated["would_mark_ready"])
        self.assertEqual(
            {k: v for k, v in gated.items() if k not in ("would_mark_ready", "warnings")},
            {k: v for k, v in candidate.items() if k not in ("would_mark_ready", "warnings")},
        )
        self.assertTrue(candidate["would_mark_ready"])


class G1UnsupportedScript(unittest.TestCase):
    def test_codec_distinguisher_on_label_vocabulary(self) -> None:
        simplified = "营养质钠纤维饱热总钙铁单称参"
        traditional = "營養質鈉纖維飽熱總鈣鐵單稱參"
        shared = "糖脂肪蛋白碳水化合物每份公克毫克大卡"
        self.assertTrue(all(gate.is_simplified_only(c) for c in simplified))
        self.assertFalse(any(gate.is_simplified_only(c) for c in traditional + shared))
        self.assertFalse(any(gate.is_simplified_only(c) for c in "Energy 100g ・ー"))

    def test_v2_shared_variant_code_points_are_not_simplified(self) -> None:
        for char in "内温黄户着奥吴吕没别强兑虚册":
            self.assertTrue(gate._encodes(char, "gb2312") and not gate._encodes(char, "cp950"), char)
            self.assertFalse(gate.is_simplified_only(char), char)

    def test_v2_a_traditional_table_with_shared_variants_is_not_declined(self) -> None:
        candidate = tw_candidate()
        candidate["cells"][0]["printed_label"] = "熱量(常温)"
        candidate["serving_size"]["printed_text"] = "每一份量100公克(内容物)"
        candidate["headers"][0]["printed_text"] = "每份 黄豆"
        self.assertNotIn("unsupported_script", gate.evaluate(candidate, TW)["declines"])

    def test_v2_true_simplified_text_is_still_declined(self) -> None:
        candidate = tw_candidate()
        candidate["cells"][0]["printed_label"] = "能量(内含)"
        candidate["cells"][2]["printed_label"] = "蛋白质"
        candidate["headers"][0]["printed_text"] = "营养成分表 每份"
        report = gate.evaluate(candidate, TW)
        self.assertIn("unsupported_script", report["declines"])
        self.assertTrue(any(d.startswith("simplified_only_characters") and "质" in d and "内" not in d for d in report["details"]))

    def test_simplified_label_is_declined(self) -> None:
        candidate = tw_candidate()
        candidate["cells"][0]["printed_label"] = "能量"
        candidate["cells"][2]["printed_label"] = "蛋白质"
        gated, report = run_gate(candidate, TW)
        self.assertEqual(report["declines"][0], "unsupported_script")
        self.assertIn("simplified_only_characters: 质", report["details"])
        self.assertTrue(gated["declined"])

    def test_kana_and_hangul_are_declined_but_cjk_middle_dot_is_not(self) -> None:
        for text, declined in (("エネルギー", True), ("열량", True), ("熱量・能量", False), ("熱量ー", False)):
            candidate = tw_candidate()
            candidate["cells"][0]["printed_label"] = text
            self.assertEqual("unsupported_script" in gate.evaluate(candidate, TW)["declines"], declined, text)

    def test_simplified_text_in_a_serving_line_or_header_counts(self) -> None:
        candidate = tw_candidate()
        candidate["serving_size"]["printed_text"] = "每份量100克(营养)"
        self.assertIn("unsupported_script", gate.evaluate(candidate, TW)["declines"])
        candidate = uk_candidate()
        candidate["headers"][0]["printed_text"] = "每100克 营养成分"
        self.assertIn("unsupported_script", gate.evaluate(candidate, UK)["declines"])


class G2NotAFoodPanel(unittest.TestCase):
    def test_supplement_markers_decline(self) -> None:
        for text in ("Supplement Facts", "Food supplement", "per softgel", "per caplet", "營養補充"):
            candidate = uk_candidate()
            candidate["headers"][1]["printed_text"] = text
            self.assertIn("not_a_food_nutrition_panel", gate.evaluate(candidate, UK)["declines"], text)

    def test_coffee_capsules_and_scottish_tablet_are_food(self) -> None:
        for text in ("per capsule", "per 30g tablet", "每顆膠囊", "每錠", "口含錠 每份"):  # v2: 錠 alone is not a marker
            candidate = uk_candidate()
            candidate["headers"][1]["printed_text"] = text
            self.assertNotIn("not_a_food_nutrition_panel", gate.evaluate(candidate, UK)["declines"], text)


class G3RequiredRows(unittest.TestCase):
    def test_each_taiwan_mandatory_row_is_required(self) -> None:
        for nutrient in gate.REQUIRED_ROWS[TW]:
            report = gate.evaluate(without(tw_candidate(), nutrient), TW)
            self.assertIn("required_row_missing", report["declines"], nutrient)

    def test_each_uk_mandatory_row_is_required(self) -> None:
        for nutrient in gate.REQUIRED_ROWS[UK]:
            report = gate.evaluate(without(uk_candidate(), nutrient), UK)
            self.assertIn("required_row_missing", report["declines"], nutrient)

    def test_optional_rows_are_not_required(self) -> None:
        self.assertEqual(gate.evaluate(without(tw_candidate(), "fibre"), TW)["declines"], [])

    def test_a_row_with_only_a_reference_intake_value_has_no_amount(self) -> None:
        candidate = without(uk_candidate(), "salt")
        candidate["headers"].append({"header_id": "hri", "printed_text": "%RI", "basis": "reference_intake", "serving_conversion": None})
        candidate["cells"].append(
            {**uk_cell("salt", "salt", "hri", "reference_intake", "8%", "8", "%"), "serving_conversion": "not_applicable"}
        )
        self.assertIn("required_row_missing", gate.evaluate(candidate, UK)["declines"])


class G4ColumnCount(unittest.TestCase):
    def test_a_required_row_missing_from_the_per_100_column_declines(self) -> None:
        report = gate.evaluate(without(tw_candidate(), "sodium", "header_2"), TW)
        self.assertEqual(report["declines"], ["column_count_mismatch"])
        report = gate.evaluate(without(uk_candidate(), "salt", "h100"), UK)
        self.assertEqual(report["declines"], ["column_count_mismatch"])

    def test_v2_a_partial_per_portion_column_is_never_declined(self) -> None:
        # 1169/2011 Article 33: a per-portion column may list only some rows.
        candidate = uk_candidate()
        candidate["cells"] = [c for c in candidate["cells"] if c["basis"] != "per_serving" or c["nutrient"] in ("energy_kj", "energy_kcal")]
        self.assertEqual(gate.evaluate(candidate, UK)["declines"], [])
        self.assertEqual(gate.evaluate(without(tw_candidate(), "sodium", "header_1"), TW)["declines"], [])

    def test_a_missing_reference_intake_cell_is_not_a_mismatch(self) -> None:
        candidate = uk_candidate()
        candidate["headers"].append({"header_id": "hri", "printed_text": "%RI", "basis": "reference_intake", "serving_conversion": None})
        candidate["cells"].append(
            {**uk_cell("fat", "fat", "hri", "reference_intake", "13%", "13", "%"), "serving_conversion": "not_applicable"}
        )
        self.assertEqual(gate.evaluate(candidate, UK)["declines"], [])


class G5G6Blocks(unittest.TestCase):
    def test_taiwan_serving_declarations_block_ready(self) -> None:
        for field in ("serving_size", "servings_per_pack"):
            candidate = tw_candidate()
            candidate[field] = "unknown"
            gated, report = run_gate(candidate, TW)
            self.assertEqual(report["blocks"], ["required_serving_declaration_missing"])
            self.assertFalse(gated["declined"])
            self.assertFalse(gated["would_mark_ready"])

    def test_uk_servings_per_pack_is_not_required(self) -> None:
        self.assertEqual(gate.evaluate(uk_candidate(servings_per_pack="unknown"), UK)["blocks"], [])


class DeclaredFormat(unittest.TestCase):
    def test_format_comes_from_the_case_not_the_output(self) -> None:
        self.assertEqual(gate.format_for_case({"corpus": "off_taiwan", "split": "untouched"}), TW)
        self.assertEqual(gate.format_for_case({"corpus": "owner", "stratum": "muesli"}), TW)
        self.assertEqual(gate.format_for_case({"corpus": "uk_v2_development_review", "stratum": "uk_en"}), UK)
        for corpus, expected in (("v1", UK), ("v2dev", UK), ("fda188", TW), ("zh_template", TW), ("muesli_typed", TW)):
            self.assertEqual(gate.format_for_case({"corpus": corpus}), expected)
        self.assertEqual(gate.format_for_case({"corpus": "qualification", "label_format": UK}), UK)
        with self.assertRaises(ValueError):
            gate.format_for_case({"corpus": "somewhere_else"})


class OfflineRescore(unittest.TestCase):
    def test_rescore_reports_before_and_after_with_the_same_scorer(self) -> None:
        import rescore_development
        import score as scoring

        truth = muesli_truth()
        cut_off = without(tw_candidate(), "sodium")  # a route reading a cut-off table as ready
        rows = [
            {"id": "usable", "stratum": "s", "label_format": TW, "truth": truth, "candidate": tw_candidate()},
            {"id": "cut", "stratum": "s", "label_format": TW, "truth": {"requires_decline": True}, "candidate": cut_off},
        ]
        result = rescore_development.rescore(rows, scoring.load_thresholds())["s"]
        self.assertEqual(result["before"]["correct_decline"]["numerator"], 0)
        self.assertEqual(result["after"]["correct_decline"]["numerator"], 1)
        self.assertEqual(result["before"]["full_table"]["numerator"], result["after"]["full_table"]["numerator"])
        self.assertEqual([c["id"] for c in result["gate_changes"]], ["cut"])


# --- Whole-call deadline -------------------------------------------------------------------


class SlowHandler(http.server.BaseHTTPRequestHandler):
    mode = "fast"

    def log_message(self, format: str, *args: Any) -> None:  # keep test output quiet
        return

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        body = json.dumps({"id": "gen-1", "choices": []}).encode()
        try:
            if self.server.mode == "stall_headers":  # type: ignore[attr-defined]
                time.sleep(5)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            if self.server.mode == "trickle":  # type: ignore[attr-defined]
                self.send_header("Content-Length", str(200))
                self.end_headers()
                for _ in range(200):  # one byte every 0.1 s: each read is fast, the whole body is 20 s
                    self.wfile.write(b" ")
                    self.wfile.flush()
                    time.sleep(0.1)
                return
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            return


class LocalServer:
    def __init__(self, mode: str) -> None:
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), SlowHandler)
        self.server.mode = mode  # type: ignore[attr-defined]
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self) -> str:
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_address[1]}/api/v1/chat/completions"

    def __exit__(self, *exc: Any) -> None:
        self.server.shutdown()
        self.server.server_close()


class WholeCallDeadline(unittest.TestCase):
    def test_read_until_stops_at_the_deadline_between_chunks(self) -> None:
        ticks = iter([0.0, 0.5, 1.0, 1.5])
        chunks = iter([b"a", b"b", b"c", b"d"])
        with self.assertRaises(openrouter_client.DeadlineExceeded):
            openrouter_client.read_until(lambda _n: next(chunks), 1.2, clock=lambda: next(ticks))

    def test_read_until_returns_the_body_at_eof(self) -> None:
        chunks = iter([b"ab", b"c", b""])
        self.assertEqual(openrouter_client.read_until(lambda _n: next(chunks), 10.0, clock=lambda: 0.0), b"abc")

    def test_a_fast_answer_is_returned_whole(self) -> None:
        with LocalServer("fast") as url:
            status, body, headers, _ = openrouter_client.http_post("test-key", "test", url)({"x": 1}, 5.0)
        self.assertEqual(status, 200)
        self.assertEqual(body, {"id": "gen-1", "choices": []})
        self.assertEqual(headers.get("Content-Type"), "application/json")

    def test_a_slowly_trickled_body_is_cut_at_the_deadline(self) -> None:
        with LocalServer("trickle") as url:
            started = time.monotonic()
            status, body, _, seconds = openrouter_client.http_post("test-key", "test", url)({"x": 1}, 1.0)
            elapsed = time.monotonic() - started
        self.assertEqual((status, openrouter_client.cut_stage(body)), (0, openrouter_client.CUT_AFTER_SEND))
        self.assertLess(elapsed, 1.6)
        self.assertGreaterEqual(seconds, 0.9)

    def test_a_server_that_never_sends_headers_is_cut_at_the_deadline(self) -> None:
        with LocalServer("stall_headers") as url:
            started = time.monotonic()
            status, _, _, _ = openrouter_client.http_post("test-key", "test", url)({"x": 1}, 1.0)
            elapsed = time.monotonic() - started
        self.assertEqual(status, 0)
        self.assertLess(elapsed, 1.6)

    def test_the_retry_loop_with_the_real_post_stays_inside_its_overall_deadline(self) -> None:
        policy = openrouter_client.RetryPolicy(max_attempts=5, deadline_seconds=2.0, base_seconds=0.05, cap_seconds=0.1)
        attempts: list[openrouter_client.Attempt] = []
        with LocalServer("trickle") as url:
            started = time.monotonic()
            result = openrouter_client.call_with_retry(
                {"x": 1}, openrouter_client.http_post("test-key", "test", url), policy=policy, on_attempt=attempts.append
            )
            elapsed = time.monotonic() - started
        self.assertTrue(result.exhausted)
        self.assertLess(elapsed, 2.6)
        self.assertTrue(all(a.status == 0 and a.retryable for a in attempts))

    def test_redirects_are_never_followed(self) -> None:
        class Redirect(http.server.BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: Any) -> None:
                return

            def do_POST(self) -> None:  # noqa: N802
                self.rfile.read(int(self.headers.get("Content-Length", 0)))
                self.send_response(307)
                self.send_header("Location", "http://127.0.0.1:9/elsewhere")
                self.send_header("Content-Length", "0")
                self.end_headers()

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Redirect)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_address[1]}/x"
            status, body, _, _ = openrouter_client.http_post("test-key", "test", url)({"x": 1}, 2.0)
        finally:
            server.shutdown()
            server.server_close()
        self.assertEqual((status, body), (307, None))
        self.assertFalse(openrouter_client.classify(307, None)[0])


# --- Owner amendments of 18 October 2026 ---------------------------------------------------


def uk_wire(rows: list[dict[str, Any]], headers: list[dict[str, Any]], serving: str = "unknown") -> dict[str, Any]:
    return {
        "language": "en",
        "declined": False,
        "decline_reasons": [],
        "serving_size_text": serving,
        "servings_per_pack_text": "unknown",
        "headers": headers,
        "rows": rows,
    }


def wire_row(nutrient: str, label: str, values: list[tuple[str, str]], parent: str = "none") -> dict[str, Any]:
    return {
        "nutrient": nutrient,
        "printed_label": label,
        "parent_nutrient": parent,
        "values": [{"header_id": h, "printed_text": v} for h, v in values],
    }


class AmendmentS1ServingConversions(unittest.TestCase):
    def test_printed_mass_reads_decimal_and_canonical_unit(self) -> None:
        import score as scoring

        self.assertEqual(scoring.printed_mass("50g pack"), ("50", "g"))
        self.assertEqual(scoring.printed_mass("approx. 88g"), ("88", "g"))
        self.assertEqual(scoring.printed_mass("320毫升"), ("320", "ml"))
        self.assertEqual(scoring.printed_mass("Per Serving 330ml"), ("330", "ml"))
        for text in ("2 sausages", "1 cracker", "1/6 pack", "30mg", "unknown", None):
            self.assertIsNone(scoring.printed_mass(text), text)

    def test_header_wording_no_longer_matters_and_count_only_portions_leave_the_denominator(self) -> None:
        import score as scoring

        truth = uk_truth()
        for cell in truth["cells"]:
            if cell["basis"] == "per_serving":
                cell["serving_conversion"] = "30g serving"
        result = scoring.score_case(uk_candidate(), truth)
        self.assertEqual((result["conversions_exact"], result["conversions"]), (8, 8))
        for cell in truth["cells"]:
            if cell["basis"] == "per_serving":
                cell["serving_conversion"] = "2 sausages"
        result = scoring.score_case(uk_candidate(), truth)
        self.assertEqual(result["conversions"], 0)

    def test_a_different_mass_still_fails(self) -> None:
        import score as scoring

        candidate = uk_candidate()
        for cell in candidate["cells"]:
            if cell["basis"] == "per_serving":
                cell["serving_conversion"] = "40g"
        result = scoring.score_case(candidate, uk_truth())
        self.assertEqual((result["conversions_exact"], result["conversions"]), (0, 8))


class AmendmentsM1M2M3Mapping(unittest.TestCase):
    def test_m1_absolute_reference_values_are_left_out_not_failed(self) -> None:
        import route_c_mapping

        headers = [
            {"header_id": "h100", "printed_text": "Per 100g", "basis": "per_100g"},
            {"header_id": "hri", "printed_text": "RI for an average adult", "basis": "reference_intake"},
        ]
        wire = uk_wire([wire_row("fat", "Fat", [("h100", "9.0g"), ("hri", "70g")])], headers)
        candidate = route_c_mapping.map_wire(wire, "0" * 64)
        self.assertEqual(validate_candidate(candidate), [])
        self.assertEqual([c["header_id"] for c in candidate["cells"]], ["h100"])
        self.assertTrue(any("absolute reference value" in w for w in candidate["warnings"]))
        self.assertTrue(candidate["would_mark_ready"])  # a left-out reference value never counts as a missing amount

    def test_m2_energy_unit_from_the_row_label_keeps_printed_text(self) -> None:
        import route_c_mapping

        headers = [{"header_id": "h100", "printed_text": "Per 100g", "basis": "per_100g"}]
        rows = [wire_row("energy_kj", "Energy kJ", [("h100", "704")]), wire_row("energy_kcal", "Energy kcal", [("h100", "168")])]
        candidate = route_c_mapping.map_wire(uk_wire(rows, headers), "0" * 64)
        cells = {c["nutrient"]: c for c in candidate["cells"]}
        self.assertEqual(
            (cells["energy_kj"]["printed_text"], cells["energy_kj"]["unit"], cells["energy_kj"]["decimal_text"]), ("704", "kJ", "704")
        )
        self.assertEqual(cells["energy_kcal"]["canonical_unit"], "kcal")

    def test_m2_never_attaches_an_ambiguous_or_contradicting_unit(self) -> None:
        import route_c_mapping

        headers = [{"header_id": "h100", "printed_text": "Per 100g", "basis": "per_100g"}]
        for row in (
            wire_row("energy_kj", "Energy kJ/kcal", [("h100", "704")]),
            wire_row("energy_kj", "Energy kcal", [("h100", "704")]),
            wire_row("fat", "Fat g", [("h100", "9")]),
            wire_row("energy_kj", "Energy kJ", [("h100", "704 approx")]),
        ):
            candidate = route_c_mapping.map_wire(uk_wire([row], headers), "0" * 64)
            self.assertEqual(candidate["cells"], [], row["printed_label"])
            self.assertFalse(candidate["would_mark_ready"])

    def test_m3_per_serving_header_mass_is_the_serving_quantity(self) -> None:
        import route_c_mapping

        headers = [
            {"header_id": "h100", "printed_text": "Per 100g", "basis": "per_100g"},
            {"header_id": "hs", "printed_text": "PER PACK (50g)*", "basis": "per_serving"},
        ]
        wire = uk_wire([wire_row("fat", "Fat", [("h100", "9.0g"), ("hs", "4.5g")])], headers)
        candidate = route_c_mapping.map_wire(wire, "0" * 64)
        serving = [c for c in candidate["cells"] if c["basis"] == "per_serving"][0]
        self.assertEqual(serving["serving_conversion"], "50g")
        self.assertEqual(candidate["serving_size"], "unknown")  # the serving line is never invented
        headers[1]["printed_text"] = "Per 2 sausages"
        candidate = route_c_mapping.map_wire(wire, "0" * 64)
        self.assertEqual([c for c in candidate["cells"] if c["basis"] == "per_serving"][0]["serving_conversion"], "unknown")
        self.assertFalse(candidate["would_mark_ready"])

    def test_m3_a_printed_serving_line_still_wins(self) -> None:
        import route_c_mapping

        headers = [{"header_id": "hs", "printed_text": "per 40g", "basis": "per_serving"}]
        wire = uk_wire([wire_row("fat", "Fat", [("hs", "4.5g")])], headers, serving="Serving size 30g")
        candidate = route_c_mapping.map_wire(wire, "0" * 64)
        self.assertEqual(candidate["cells"][0]["serving_conversion"], "30g")


class AmendmentT1Convention(unittest.TestCase):
    def uk_truth_with_ri(self) -> dict[str, Any]:
        truth = uk_truth()
        truth["case_id"] = "uk-1"
        truth["requires_decline"] = False
        truth["headers"].append({"header_id": "hri", "printed_text": "", "basis": "reference_intake", "serving_conversion": None})
        truth["cells"].append({**uk_cell("saturates_ri", "saturates", "hri", "reference_intake", "16%", "16", "%"), "parent_row_id": None})
        return truth

    def test_reference_intake_cells_join_their_amount_row_and_parent(self) -> None:
        import cases

        truth = self.uk_truth_with_ri()
        before = copy.deepcopy(truth)
        changed, log = cases.apply_uk_truth_convention_t1(truth)
        self.assertEqual(truth, before)  # pure
        ri = [c for c in changed["cells"] if c["basis"] == "reference_intake"][0]
        self.assertEqual((ri["row_id"], ri["parent_row_id"]), ("saturates", "fat"))
        self.assertTrue(changed["reference_intake_transcribed"])
        self.assertEqual(log[0]["row_id"], ["saturates_ri", "saturates"])
        self.assertEqual(cases.apply_uk_truth_convention_t1(changed)[1], [])  # idempotent
        self.assertEqual([c["decimal_text"] for c in changed["cells"]], [c["decimal_text"] for c in before["cells"]])

    def test_untranscribed_reference_intake_columns_are_not_extras(self) -> None:
        import cases
        import score as scoring

        truth = cases.apply_uk_truth_convention_t1({**uk_truth(), "case_id": "uk-2", "requires_decline": False})[0]
        self.assertIs(truth["reference_intake_transcribed"], False)
        candidate = uk_candidate()
        candidate["headers"].append({"header_id": "hri", "printed_text": "%RI", "basis": "reference_intake", "serving_conversion": None})
        candidate["cells"].append(
            {
                **uk_cell("fat", "fat", "hri", "reference_intake", "13%", "13", "%"),
                "serving_conversion": "not_applicable",
                "persistence_authorized": False,
                "requires_user_selection": True,
            }
        )
        self.assertEqual(validate_candidate(candidate), [])
        self.assertEqual(scoring.score_case(candidate, truth)["tables_exact"], 1)
        transcribed = {**truth, "reference_intake_transcribed": True}
        self.assertEqual(scoring.score_case(candidate, transcribed)["tables_exact"], 0)
        self.assertEqual(scoring.score_case(candidate, uk_truth())["tables_exact"], 0)  # Taiwan-style truths are unchanged


class ReviewFixes(unittest.TestCase):
    """Invariant review of PR #259: M3 unit match, connect and DNS deadline, spend after a cut."""

    def test_m3_header_mass_never_reads_a_count_as_grams(self) -> None:
        import route_c_mapping

        for header_text, expected in (("Per 2 grilled sausages (90g)", "90g"), ("1 glass (250ml)", "250ml"), ("Per 2 sausages", "unknown")):
            headers = [{"header_id": "hs", "printed_text": header_text, "basis": "per_serving"}]
            wire = uk_wire([wire_row("fat", "Fat", [("hs", "4.5g")])], headers)
            candidate = route_c_mapping.map_wire(wire, "0" * 64)
            self.assertEqual(candidate["cells"][0]["serving_conversion"], expected, header_text)

    def test_serving_line_never_reads_a_count_as_grams(self) -> None:
        import route_c_mapping

        for text, expected in (
            ("2 grilled sausages (90g)", ("90", "g")),
            ("1 glass (250ml)", ("250", "ml")),
            ("每一份量100公克", ("100", "g")),
        ):
            serving = route_c_mapping._serving_size(text)
            assert isinstance(serving, dict)
            self.assertEqual((serving["decimal_text"], serving["canonical_unit"]), expected, text)
        unread = route_c_mapping._serving_size("2 grilled sausages")
        assert isinstance(unread, dict)
        self.assertIsNone(unread["decimal_text"])

    def test_a_dns_lookup_that_stalls_is_cut_at_the_deadline(self) -> None:
        def stalled(host: str, port: int) -> list[Any]:
            time.sleep(5)
            return []

        started = time.monotonic()
        status, body, _, _ = openrouter_client.http_post("test-key", "test", "http://example.invalid/x", resolver=stalled)({"x": 1}, 1.0)
        self.assertLess(time.monotonic() - started, 1.6)
        self.assertEqual(status, 0)
        self.assertEqual(openrouter_client.cut_stage(body), openrouter_client.CUT_BEFORE_SEND)

    def test_a_stalled_connect_handshake_is_cut_at_the_deadline(self) -> None:
        import socket

        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        held: list[socket.socket] = []

        def accept() -> None:
            try:
                conn, _ = listener.accept()
                held.append(conn)  # accepts TCP but never answers the TLS handshake
            except OSError:
                return

        threading.Thread(target=accept, daemon=True).start()
        try:
            url = f"https://127.0.0.1:{listener.getsockname()[1]}/x"
            started = time.monotonic()
            status, body, _, _ = openrouter_client.http_post("test-key", "test", url)({"x": 1}, 1.0)
            elapsed = time.monotonic() - started
        finally:
            for conn in held:
                conn.close()
            listener.close()
        self.assertEqual(status, 0)
        self.assertLess(elapsed, 1.6)
        self.assertEqual(openrouter_client.cut_stage(body), openrouter_client.CUT_BEFORE_SEND)

    def test_a_trickled_body_cut_after_send_keeps_the_generation_id(self) -> None:
        body = openrouter_client.cut_body(openrouter_client.CUT_AFTER_SEND, b'{"id": "gen-abc_123", "choi')
        self.assertEqual(body["id"], "gen-abc_123")
        self.assertEqual(openrouter_client.cut_stage(body), openrouter_client.CUT_AFTER_SEND)
        with LocalServer("trickle") as url:
            status, cut, _, _ = openrouter_client.http_post("test-key", "test", url)({"x": 1}, 1.0)
        self.assertEqual((status, openrouter_client.cut_stage(cut)), (0, openrouter_client.CUT_AFTER_SEND))

    def test_spend_after_a_cut(self) -> None:
        from decimal import Decimal

        ceiling = Decimal("0.20")
        after = openrouter_client.cut_body(openrouter_client.CUT_AFTER_SEND)
        before = openrouter_client.cut_body(openrouter_client.CUT_BEFORE_SEND)
        self.assertEqual(openrouter_client.charge_for_cut(after, None, ceiling), (ceiling, openrouter_client.CUT_UNRECONCILED_KIND))
        self.assertEqual(openrouter_client.charge_for_cut(after, Decimal("0.013"), ceiling), (Decimal("0.013"), None))
        self.assertEqual(openrouter_client.charge_for_cut(before, None, ceiling), (None, None))
        self.assertEqual(openrouter_client.charge_for_cut({"id": "gen-1"}, None, ceiling), (None, None))


@unittest.skipUnless(importlib.util.find_spec("inspect_ai"), "inspect_ai is not installed (see requirements.txt)")
class CutAttemptLedger(unittest.TestCase):
    def run_solver(self, first: dict[str, Any], lookup: Any) -> list[dict[str, Any]]:
        import tempfile
        from pathlib import Path

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
        ok = {
            "id": "gen-2",
            "model": "openai/gpt-6-luna",
            "provider": "OpenAI",
            "usage": {"cost": 0.01},
            "choices": [{"finish_reason": "stop", "message": {"content": json.dumps(answer)}}],
        }
        replies = [(0, first), (200, ok)]
        sent: list[dict[str, Any]] = []

        def post(body: dict[str, Any], timeout: float) -> tuple[int, dict[str, Any], dict[str, str], float]:
            sent.append(body)
            status, payload = replies[len(sent) - 1]
            return status, payload, {}, 0.1

        with tempfile.TemporaryDirectory() as folder:
            image = Path(folder) / "a.png"
            image.write_bytes(b"\x89PNG\r\n\x1a\n")
            metadata = {"image_path": str(image), "corpus": "off_taiwan", "sha256": "a" * 64}
            sample = Sample(id="case-1", input="image", target=json.dumps({"requires_decline": True}), metadata=metadata)
            budget = LedgerBudget(Path(folder) / "ledger.json")
            task = Task(
                dataset=[sample],
                solver=inspect_task.route_c_openrouter(budget, enabled=True, target=target, post=post, lookup=lookup, sleep=lambda _: None),
                scorer=inspect_task.label_capture_scorer(),
            )
            inspect_eval(task, model="mockllm/model", log_dir=folder, display="none")
            ledger = json.loads((Path(folder) / "ledger.json").read_text())
            self.per_call = ledger["limits"]["per_call_usd"]
        return ledger["entries"]

    def test_an_unreconciled_cut_is_charged_at_the_per_call_stop(self) -> None:
        entries = self.run_solver(openrouter_client.cut_body(openrouter_client.CUT_AFTER_SEND), lambda _: ("not_found", None))
        self.assertEqual((entries[0]["cost_usd"], entries[0]["kind"]), (self.per_call, openrouter_client.CUT_UNRECONCILED_KIND))
        self.assertEqual(entries[1]["cost_usd"], "0.01")

    def test_a_cut_with_a_generation_id_is_reconciled_by_lookup(self) -> None:
        cut = openrouter_client.cut_body(openrouter_client.CUT_AFTER_SEND, b'{"id":"gen-cut-1"')
        entries = self.run_solver(cut, lambda generation: ("found", 0.004) if generation == "gen-cut-1" else ("not_found", None))
        self.assertEqual((entries[0]["cost_usd"], entries[0].get("generation_id")), ("0.004", "gen-cut-1"))
        self.assertNotEqual(entries[0].get("kind"), openrouter_client.CUT_UNRECONCILED_KIND)


if __name__ == "__main__":
    unittest.main()
