"""Contract tests for the pure modules (synthetic data only)."""
import json
import unittest

import helpers as H  # noqa: F401  (sets sys.path)
import bars
import formats
import sample
import score_a
import queries
import score_b
import split
from stats import wilson


class Stats(unittest.TestCase):
    def test_known_values(self):
        self.assertEqual(wilson(5, 10), (0.236593, 0.763407))
        self.assertEqual(wilson(0, 10), (0.0, 0.277533))
        self.assertEqual(wilson(10, 10), (0.722467, 1.0))
        self.assertIsNone(wilson(0, 0))
        with self.assertRaises(ValueError):
            wilson(3, 2)
        with self.assertRaises(TypeError):
            wilson(True, 2)


class Bars(unittest.TestCase):
    def test_allowed_counts_at_planned_sizes(self):
        self.assertEqual(bars.allowed("a1_nutrient_disagreements", 464), 13)
        self.assertEqual(bars.allowed("a5_nutrient_disagreements", 33), 0)
        self.assertEqual(bars.allowed("a5_nutrient_disagreements", 34), 1)
        self.assertEqual(bars.allowed("b_wrong_entry_first", 64), 1)
        self.assertEqual(bars.allowed("b_negative_false_hits", 10), 0)
        self.assertEqual(bars.allowed("b_top1_acceptable", 64), 55)

    def test_fixed_counts_whatever_the_size(self):  # decision 7
        self.assertEqual(bars.allowed("a2_different_food_or_other_state", 45), 2)
        self.assertEqual(bars.allowed("a3_misleading", 47), 4)

    def test_judge(self):
        self.assertEqual(bars.judge("a3_misleading", 4, 40), {"allowed": 4, "passes": True})
        self.assertEqual(bars.judge("a3_misleading", 5, 40)["passes"], False)
        self.assertEqual(bars.judge("b_top1_acceptable", 55, 64)["passes"], True)
        self.assertEqual(bars.judge("b_top1_acceptable", 54, 64)["passes"], False)
        self.assertEqual(bars.judge("a5_nutrient_disagreements", 0, 0), {"allowed": None, "passes": None})
        self.assertEqual(bars.judge("a1_wrong_product_or_variant", 0, 50, forced_fail=True)["passes"], False)


class Sampling(unittest.TestCase):
    def test_stratum_order(self):
        both = H.entry(1, kind="exact_product_dataset", role="merge")
        both["label_nutrients"]["fat_total"] = H.label("manual_declaration")
        self.assertEqual(sample.stratum(both), "A5")
        self.assertEqual(sample.stratum(H.entry(2, kind="exact_product_dataset", role="merge")), "A1")
        self.assertEqual(sample.stratum(H.entry(3, role="merge")), "A2")
        self.assertEqual(sample.stratum(H.entry(4, role="candidate")), "A3")
        self.assertEqual(sample.stratum(H.entry(5)), "A4")

    def test_seeded_order_is_pinned(self):
        ids = [H.eid(n) for n in range(1, 6)]
        self.assertEqual(sample.seeded_order(7, ids), sample.seeded_order(7, list(reversed(ids))))
        self.assertNotEqual(sample.seeded_order(7, ids), sample.seeded_order(8, ids))
        # Golden order: SHA-256 of "<seed>|<id>", independent of the Python version.
        import hashlib
        want = sorted(ids, key=lambda i: hashlib.sha256(f"7|{i}".encode()).hexdigest())
        self.assertEqual(sample.seeded_order(7, ids), want)

    def test_draw_quotas_census_and_replacements(self):
        pop = H.population()
        s = sample.draw(pop, {}, 11)
        self.assertEqual(s["quotas"], {"A1": 5, "A5": 2, "A2": 40, "A3": 40, "A4": 20})
        self.assertEqual(len(s["replacements"]["A2"]), 20)
        self.assertEqual(s, sample.draw(pop, {}, 11))
        self.assertNotEqual(s["entries"], sample.draw(pop, {}, 12)["entries"])

    def test_top30_overflow_and_tie_break(self):
        pop = H.population(a2=60)
        a2 = [e["id"] for e in pop if sample.stratum(e) == "A2"]
        counts = {i: 5 for i in a2[:45]}  # 45 most-bought, all A2, tied
        top = sample.top_entries(counts, [e["id"] for e in pop])
        self.assertEqual(top, sorted(a2[:45])[:30])  # tie broken by id
        s = sample.draw(pop, counts, 3)
        self.assertEqual(s["quotas"]["A2"], 40)
        many = {i: 9 for i in a2[:30]}
        many.update({i: 1 for i in a2[30:]})
        self.assertEqual(sample.draw(pop, many, 3)["quotas"]["A2"], 40)
        small = H.population(a2=60)
        c2 = {e["id"]: 9 for e in small if sample.stratum(e) == "A2"}
        self.assertEqual(sample.draw(small, c2, 3)["quotas"]["A2"], 40)

    def test_quota_grows_when_top30_exceed_it(self):
        pop = H.population(a4=40)
        a4 = [e["id"] for e in pop if sample.stratum(e) == "A4"]
        counts = {i: 3 for i in a4[:25]}
        self.assertEqual(sample.draw(pop, counts, 1)["quotas"]["A4"], 25)

    def test_sheet_needs_known_generic_records(self):
        pop = H.population(a1=0, a2=1, a3=0, a4=0, a5=0)
        s = {"schema": "pfd-sample-v1", "release_id": H.RELEASE, **sample.draw(pop, {}, 1)}
        with self.assertRaises(formats.FormatError):
            sample.sheet_rows(s, pop, {"cofid": {}})
        rows = sample.sheet_rows(s, pop, {"cofid": {"cofid:synthetic:1": ("Synthetic oats", "raw")}})
        self.assertIn("Synthetic oats", rows[0]["matched"])


class Splitting(unittest.TestCase):
    def query_set(self, pos=140, neg=20):
        qs = []
        for n in range(pos + neg):
            negative = n >= pos
            qs.append({"query_id": f"q-{n:04d}", "text": f"synthetic query {n}", "negative": negative,
                       "answer": {"kind": "none"} if negative else {"kind": "entry", "entry_ids": [H.eid(n + 1)], "step": 1}})
        return {"schema": "pfd-query-set-v1", "release_id": H.RELEASE, "queries": qs}

    def test_negatives_split_evenly_and_reproducibly(self):
        out = split.split(self.query_set(), 5)
        dev, held = out["development"]["queries"], out["held-out"]["queries"]
        self.assertEqual(sum(q["negative"] for q in dev), 10)
        self.assertEqual(sum(q["negative"] for q in held), 10)
        self.assertEqual(len(dev) - 10, 84)
        self.assertEqual(out, split.split(self.query_set(), 5))
        self.assertEqual(len(set(q["query_id"] for q in dev) & set(q["query_id"] for q in held)), 0)


def sheet_bytes(rows):
    return formats.write_sheet(rows)


class PartA(unittest.TestCase):
    def setUp(self):
        self.pop = H.population(a1=10, a2=45, a3=45, a4=25, a5=0)
        self.sample = {"schema": "pfd-sample-v1", "release_id": H.RELEASE, **sample.draw(self.pop, {}, 9)}
        self.rows = sample.sheet_rows(self.sample, self.pop, {"cofid": {f"cofid:synthetic:{n}": ("x", "raw") for n in range(200)}})

    def fill(self, a1_skips=0, a1_wrong=0, a1_differs=0, a2_bad=0, a2_skip_first=False):
        rows = [dict(r) for r in self.rows]
        a1 = [r for r in rows if r["stratum"] == "A1"]
        for i, r in enumerate(a1):
            if i < a1_skips:
                r["product"] = "skipped"
                continue
            r["product"] = "wrong_variant" if i - a1_skips < a1_wrong else "right_product"
            for j, k in enumerate(formats.NUTRIENTS):
                r[k] = "not_on_pack" if j == 7 else ("missing_in_entry" if j == 6 else "agrees")
            if i - a1_skips < a1_differs:
                r["energy_consumed"] = "differs"
        for s, good, bad in (("A2", "same_food_same_state", "different_food"), ("A3", "sensible", "misleading_close"),
                             ("A4", "nothing_suitable", "match_missed")):
            rs = [r for r in rows if r["stratum"] == s]
            quota, checked = self.sample["quotas"][s], 0
            for i, r in enumerate(rs):
                if checked >= quota:
                    break
                if s == "A2" and a2_skip_first and i == 0:
                    r["verdict"] = "skipped"
                    continue
                r["verdict"] = bad if (s == "A2" and checked < a2_bad) else good
                checked += 1
        return formats.parse_sheet(sheet_bytes(rows))

    def test_counts_and_exclusions(self):
        m = score_a.score(self.sample, self.fill(a1_wrong=2, a1_differs=3, a2_bad=2))
        self.assertEqual(m["a1_wrong_product_or_variant"]["count"], 2)
        self.assertTrue(m["a1_wrong_product_or_variant"]["passes"])
        self.assertEqual(m["a1_nutrient_disagreements"]["of"], 10 * 6)  # not_on_pack and missing_in_entry excluded
        self.assertEqual(m["a1_missing_in_entry"], 10)
        self.assertEqual(m["a1_not_on_pack"], 10)
        self.assertEqual(m["a2_different_food_or_other_state"]["count"], 2)
        self.assertTrue(m["a2_different_food_or_other_state"]["passes"])
        self.assertIsNone(m["a5_nutrient_disagreements"]["passes"])  # no A5 entries: not assessed

    def test_a1_skip_limit(self):
        self.assertFalse(score_a.score(self.sample, self.fill(a1_skips=6))["a1_skip_limit_exceeded"])
        m = score_a.score(self.sample, self.fill(a1_skips=7))
        self.assertTrue(m["a1_skip_limit_exceeded"])
        self.assertFalse(m["a1_wrong_product_or_variant"]["passes"])
        self.assertFalse(m["a1_nutrient_disagreements"]["passes"])
        self.assertEqual(m["a1_wrong_product_or_variant"]["of"], 3)  # never replaced

    def test_all_a1_skipped_fails_rather_than_not_assessed(self):
        m = score_a.score(self.sample, self.fill(a1_skips=10))
        self.assertFalse(m["a1_wrong_product_or_variant"]["passes"])
        self.assertFalse(m["a1_nutrient_disagreements"]["passes"])

    def test_sheet_order_and_uniqueness(self):
        rows = self.fill()
        a2 = [i for i, r in enumerate(rows) if r["stratum"] == "A2"]
        swapped = list(rows)
        swapped[a2[0]], swapped[a2[1]] = swapped[a2[1]], swapped[a2[0]]
        with self.assertRaises(formats.FormatError):
            score_a.score(self.sample, swapped)
        with self.assertRaises(formats.FormatError):
            score_a.score(self.sample, rows + [rows[0]])

    def test_row_numbers_checked_without_echoing_the_cell(self):
        rows = [dict(r) for r in self.rows]
        rows[0]["row"] = "Private pasted title"
        with self.assertRaises(formats.FormatError) as e:
            formats.parse_sheet(formats.write_sheet(rows))
        self.assertNotIn("Private pasted title", str(e.exception))

    def test_short_of_quota_fails_closed(self):
        rows = [r for r in self.fill() if not (r["stratum"] == "A3" and r["reason"] == "replacement")]
        rows = [r for r in rows if not (r["stratum"] == "A3" and r["verdict"] == "")]
        sample = dict(self.sample, replacements={**self.sample["replacements"], "A3": []})
        a3 = [r for r in rows if r["stratum"] == "A3"]
        a3[0]["verdict"] = "skipped"
        renum = [dict(r, row=str(i)) for i, r in enumerate(rows, start=1)]
        m = score_a.score(sample, formats.parse_sheet(formats.write_sheet(renum)))
        self.assertTrue(m["a3_short_of_quota"])
        self.assertFalse(m["a3_misleading"]["passes"])

    def test_skip_is_replaced_and_quota_rules(self):
        m = score_a.score(self.sample, self.fill(a2_skip_first=True))
        self.assertEqual(m["a2_different_food_or_other_state"]["of"], 40)
        self.assertEqual(m["a2_skipped"], 1)
        rows = self.fill()
        late = next(r for r in reversed(rows) if r["stratum"] == "A2")
        late["verdict"] = "different_food"
        with self.assertRaises(formats.FormatError):
            score_a.score(self.sample, rows)
        rows = self.fill()
        first = next(r for r in rows if r["stratum"] == "A3")
        first["verdict"] = ""
        with self.assertRaises(formats.FormatError):
            score_a.score(self.sample, rows)


class PartB(unittest.TestCase):
    def q(self, n, kind, negative=False, **kw):
        answer = {"kind": kind, **kw}
        return {"query_id": f"q-{n:04d}", "text": "synthetic", "negative": negative, "answer": answer}

    def run_b(self, queries, results):
        qs = {"schema": "pfd-query-set-v1", "release_id": H.RELEASE, "set": "held-out", "queries": queries}
        rk = {"schema": "pfd-ranking-output-v1", "release_id": H.RELEASE, "set": "held-out",
              "results": [{"query_id": f"q-{n:04d}", "candidates": c} for n, c in enumerate(results)]}
        return score_b.score(formats.parse_query_set(formats.dumps(qs)), formats.parse_ranking(formats.dumps(rk)))

    def test_kinds_and_denominators(self):
        e1, e2 = {"kind": "entry", "entry_id": H.eid(1), "step": 2}, {"kind": "entry", "entry_id": H.eid(2), "step": 1}
        g = {"kind": "generic", "source": "cofid", "record_id": "cofid:x"}
        g2 = {"kind": "generic", "source": "usda", "record_id": "usda:y"}
        queries = [self.q(0, "entry", entry_ids=[H.eid(1)], step=2),   # right entry first, right step
                   self.q(1, "entry", entry_ids=[H.eid(1)], step=1),   # empty list: not acceptable
                   self.q(2, "generic", generic=[{"source": "cofid", "record_id": "cofid:x"}]),  # wrong generic first
                   self.q(3, "none", negative=True),                 # empty: acceptable
                   self.q(4, "none", negative=True),                 # generic first: acceptable
                   self.q(5, "none", negative=True)]                 # entry first: the one false hit
        m = self.run_b(queries, [[e1], [], [g2, g], [], [g], [e2]])
        self.assertEqual(m["b_top1_acceptable"]["count"], 3)
        self.assertEqual(m["b_top3_acceptable"]["count"], 4)
        self.assertEqual(m["b_step_correct"]["count"], 1)
        self.assertEqual(m["b_wrong_generic_first"]["count"], 1)
        # One negative false hit counts once in each of top-1, wrong entry first and negative false hits.
        self.assertEqual(m["b_wrong_entry_first"]["count"], 1)
        self.assertEqual(m["b_negative_false_hits"], {"count": 1, "of": 3, "interval": list(wilson(1, 3)),
                                                     "allowed": 0, "passes": False})
        self.assertEqual(m["b_top1_acceptable"]["of"], 6)

    def test_query_ids_must_match(self):
        with self.assertRaises(formats.FormatError):
            self.run_b([self.q(0, "none")], [[], []])


class Formats(unittest.TestCase):
    SECRET = "Private Example Title 12345"

    def test_unknown_tokens_kinds_and_schemas_refused_without_leaking(self):
        row = {"schema": "pfd-review-sheet-v1", "row": 1, "stratum": "A2", "reason": "draw", "entry_id": H.eid(1),
               "title": self.SECRET, "verdict": self.SECRET}
        with self.assertRaises(formats.FormatError) as e:
            formats.parse_sheet(formats.write_sheet([row]))
        self.assertNotIn(self.SECRET, str(e.exception))
        bad_q = {"schema": "pfd-query-set-v1", "release_id": H.RELEASE,
                 "queries": [{"query_id": "q-0001", "text": self.SECRET, "negative": False, "answer": {"kind": self.SECRET}}]}
        with self.assertRaises(formats.FormatError) as e:
            formats.parse_query_set(formats.dumps(bad_q))
        self.assertNotIn(self.SECRET, str(e.exception))
        for parser in (formats.parse_query_set, formats.parse_ranking, formats.parse_sample, formats.parse_purchase_counts):
            with self.assertRaises(formats.FormatError):
                parser(json.dumps({"schema": "pfd-something-v0"}).encode())

    def test_ranking_output_round_trips(self):
        doc = {"schema": "pfd-ranking-output-v1", "release_id": H.RELEASE, "set": "development",
               "results": [{"query_id": "q-0001", "candidates": [{"kind": "entry", "entry_id": H.eid(1), "step": 3},
                                                                  {"kind": "generic", "source": "tfda", "record_id": "tfda:X1"}]}]}
        data = formats.dumps(doc)
        self.assertEqual(formats.dumps(formats.parse_ranking(data)), data)

    def test_wrong_types_refused_not_crashed(self):
        for doc, parser in (({"schema": "pfd-query-set-v1", "release_id": H.RELEASE, "queries": None}, formats.parse_query_set),
                            ({"schema": "pfd-ranking-output-v1", "release_id": H.RELEASE, "set": "development", "results": 1}, formats.parse_ranking),
                            ({"schema": "pfd-query-set-v1", "release_id": H.RELEASE, "queries": [
                                {"query_id": "q-0001", "text": "x", "negative": False, "answer": {"kind": "entry", "entry_ids": 1, "step": 1}}]},
                             formats.parse_query_set)):
            with self.assertRaises(formats.FormatError):
                parser(formats.dumps(doc))

    def test_boolean_step_refused(self):
        doc = {"schema": "pfd-ranking-output-v1", "release_id": H.RELEASE, "set": "development",
               "results": [{"query_id": "q-0001", "candidates": [{"kind": "entry", "entry_id": H.eid(1), "step": True}]}]}
        with self.assertRaises(formats.FormatError):
            formats.parse_ranking(formats.dumps(doc))

    def test_negative_needs_none(self):
        q = {"schema": "pfd-query-set-v1", "release_id": H.RELEASE,
             "queries": [{"query_id": "q-0001", "text": "x", "negative": True, "answer": {"kind": "entry", "entry_ids": [H.eid(1)], "step": 1}}]}
        with self.assertRaises(formats.FormatError):
            formats.parse_query_set(formats.dumps(q))



class QueryTemplate(unittest.TestCase):
    ENTRIES = {H.eid(1), H.eid(2)}
    GENERIC = {"cofid": {"cofid:synthetic:1"}}

    def assemble(self, *rows):
        data = queries.template() + ("\n".join(rows) + "\n").encode()
        return queries.assemble(data, H.RELEASE, self.ENTRIES, self.GENERIC)

    def test_rows_become_a_valid_query_set(self):
        doc = self.assemble(f"synthetic one,no,entry,{H.eid(1)} {H.eid(2)},variety,",
                            "synthetic two,no,generic,,,cofid=cofid:synthetic:1",
                            ",,,,,",  # blank rows are skipped
                            "synthetic three,yes,none,,,",
                            "synthetic four,no,none,,,")  # plan 4.2: the owner may mark others none
        self.assertEqual([q["query_id"] for q in doc["queries"]], ["q-0001", "q-0002", "q-0003", "q-0004"])
        self.assertEqual(doc["queries"][0]["answer"], {"kind": "entry", "entry_ids": [H.eid(1), H.eid(2)], "step": 2})
        self.assertEqual(doc["queries"][1]["answer"]["generic"], [{"source": "cofid", "record_id": "cofid:synthetic:1"}])
        self.assertEqual(queries.counts(doc), {"queries": 4, "negative": 1, "entry": 1, "generic": 1, "none": 2})
        formats.parse_query_set(formats.dumps(doc))

    def test_mistakes_are_refused_by_row_without_echoing_cells(self):
        bad = [
            "secret words,maybe,none,,,",
            f"secret words,yes,entry,{H.eid(1)},1,",
            f"secret words,no,entry,{H.eid(9)},1,",
            "secret words,no,entry,pfc:nothex,1,",
            f"secret words,no,entry,{H.eid(1)},4,",
            "secret words,no,generic,,,cofid=cofid:unknown",
            "secret words,no,generic,,,ciqual=x",
            "secret words,no,none,,1,",
            ",no,none,,,",
            "secret words,no,none,,,,extra",
        ]
        for row in bad:
            with self.subTest(row=row), self.assertRaises(queries.QueryTemplateError) as cm:
                self.assemble(row)
            self.assertIn("row 2", str(cm.exception))
            self.assertNotIn("secret", str(cm.exception))
        with self.assertRaises(queries.QueryTemplateError):
            self.assemble("Secret  Words,no,none,,,", "secret words,no,none,,,")  # duplicate after normalising
        with self.assertRaises(queries.QueryTemplateError):
            queries.assemble(b"query,answer\n", H.RELEASE, self.ENTRIES, self.GENERIC)
        with self.assertRaises(queries.QueryTemplateError):
            self.assemble()

    def test_lookup_is_alphabetical_and_says_where_words_matched(self):
        entries = [H.entry(1, title="Synthetic Zeta Oats"), H.entry(2, title="Synthetic Alpha Oats"), H.entry(3, title="Synthetic Rice")]
        entries[2]["variety"] = "oats"
        rows, total = queries.lookup_entries(entries, "OATS")
        self.assertEqual(total, 3)
        self.assertEqual([r[0] for r in rows], [H.eid(2), H.eid(3), H.eid(1)])
        self.assertEqual(rows[1][3], ["variety"])
        self.assertEqual(queries.lookup_entries(entries, "oats missing"), ([], 0))
        self.assertEqual(queries.lookup_entries(entries, "  "), ([], 0))
        many = [H.entry(n, title=f"Synthetic oats {n}") for n in range(1, 40)]
        rows, total = queries.lookup_entries(many, "oats")
        self.assertEqual((len(rows), total), (queries.LOOKUP_LIMIT, 39))

    def test_generic_lookup_prints_the_template_form(self):
        recs = {"cofid": {"cofid:synthetic:1": ("Synthetic oats, raw", "raw")}, "usda": {}}
        rows, total = queries.lookup_generic(recs, "oats")
        self.assertEqual((rows, total), ([("cofid=cofid:synthetic:1", "Synthetic oats, raw", "raw")], 1))


class QueryCSVRegression(unittest.TestCase):
    def test_malformed_quoting_is_refused(self):
        with self.assertRaises(queries.QueryTemplateError):
            queries.assemble(queries.template() + b'"Synthetic,no,none,,,\n', H.RELEASE, set(), {})

    def test_query_whitespace_is_preserved(self):
        doc = queries.assemble(queries.template() + b"  Synthetic query  ,no,none,,,\n", H.RELEASE, set(), {})
        self.assertEqual(doc["queries"][0]["text"], "  Synthetic query  ")

    def test_unknown_entry_names_column_without_value(self):
        with self.assertRaises(queries.QueryTemplateError) as cm:
            queries.assemble(queries.template() + f"Synthetic,no,entry,{H.eid(9)},1,\n".encode(), H.RELEASE, set(), {})
        self.assertIn("row 2: entry_ids:", str(cm.exception))
        self.assertNotIn(H.eid(9), str(cm.exception))

    def test_brand_only_match_is_not_reported_as_title(self):
        entry = H.entry(1, title="Synthetic item")
        entry["brand"] = "SyntheticBrand"
        rows, total = queries.lookup_entries([entry], "SyntheticBrand")
        self.assertEqual(total, 1)
        self.assertEqual(rows[0][3], ["brand"])


if __name__ == "__main__":
    unittest.main()
