"""Pure development-only result projection and roster checks."""
def complete_roster(rows, expected):
    ids = [row["id"] for row in rows]
    if len(ids) != len(set(ids)) or set(ids) != set(expected):
        raise ValueError("Missing, extra or duplicate observation IDs")


def parser_rows(fixture, predictions):
    complete_roster(predictions, [case["id"] for case in fixture["cases"]])
    by_id = {row["id"]: row["parsed"] for row in predictions}
    result = []
    for case in fixture["cases"]:
        expected, observed = case["expected"], by_id[case["id"]]
        fields = ["route", "quantity"]
        if expected["route"] == "search":
            fields += ["food", "attributes"]
        # Reuse the legacy normalisation for numeric percentage attributes.
        import sys
        scorer = sys.modules["query_score"]
        failed = [field for field in fields if
                  (scorer.normal_attributes(observed[field]) != scorer.normal_attributes(expected[field])
                   if field == "attributes" else observed.get(field) != expected[field])]
        result.append(dict(id=case["id"], suite="query", family=case["family"],
                           evidence="synthetic_exposed_development", input=case["query"],
                           observed=observed, expectation_met=not failed,
                           reason="legacy regression matched" if not failed else "mismatch: " + ", ".join(failed),
                           ai_status="not_applicable_deterministic_parser",
                           safeguard_status="not_run", outcome_status="not_run"))
    return result


def safeguard_rows(observations):
    expected = ["unsupported-count-conversion", "supported-grams-control"]
    complete_roster([dict(row, id=row["case_id"]) for row in observations], expected)
    rows = []
    for observed in observations:
        blocked = observed["case_id"] == expected[0]
        ok = (observed["validation"] == "blocked" and observed["error"] == "missingConversion"
              and observed["saved_count"] == 0) if blocked else (
                  observed["validation"] == "saved" and observed["saved_count"] == 1)
        rows.append(dict(id=observed["case_id"], suite="safeguard", family="quantity_conversion",
                         evidence="synthetic_contract_probe", observed=observed,
                         raw_proposal={"kind": "synthetic_failure_injection" if blocked else "supported_control",
                                       "invented_grams": 80 if blocked else None},
                         expectation_met=ok, reason="production save boundary " + ("matched" if ok else "FAILED"),
                         ai_status="fail_synthetic_unsupported_claim" if blocked else "not_applicable",
                         safeguard_status="pass" if ok else "fail",
                         outcome_status="unresolved_expected_block" if blocked and ok else (
                             "saved_control_only" if ok else "fail")))
    return rows


def summary(rows):
    complete_roster(rows, [row["id"] for row in rows])
    return {suite: dict(cases=len(items), expectations_met=sum(r["expectation_met"] for r in items),
                        failures=[r["id"] for r in items if not r["expectation_met"]])
            for suite in sorted({r["suite"] for r in rows})
            for items in [[r for r in rows if r["suite"] == suite]]}
