#!/usr/bin/env python3
"""Offline, review-dependent scoring of cited food-source discovery leads."""

import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path
from urllib.parse import urlsplit

CASE_VERSION = "gemini-grounding-cases-v1"
REPLAY_VERSION = "gemini-grounding-replay-v1"
JUDGEMENT_VERSIONS = {"gemini-grounding-judgements-v1", "gemini-grounding-judgements-v2"}
GRADES = {"exact_primary", "useful_related", "irrelevant", "severe_mismatch", "unverified"}
SUPPORT = {"yes", "no", "unverified"}


class EvaluationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise EvaluationError(message)


def safe_url(value):
    if not isinstance(value, str):
        return False
    try:
        url = urlsplit(value)
        return (url.scheme == "https" and bool(url.hostname) and url.username is None
                and url.password is None and (url.port is None or url.port > 0)
                and not any(character.isspace() for character in value))
    except ValueError:
        return False


def load(path):
    with Path(path).open(encoding="utf-8") as source:
        return json.load(source)


def validate_cases(document):
    require(document.get("schema_version") == CASE_VERSION, "unsupported case schema")
    cases = document.get("cases")
    require(isinstance(cases, list) and cases, "cases must be a nonempty list")
    ids = set()
    for case in cases:
        case_id = case.get("id")
        require(isinstance(case_id, str) and case_id and case_id not in ids, "duplicate or empty case id")
        ids.add(case_id)
        require(case.get("split") in {"development", "holdout"}, f"{case_id}: invalid split")
        for field in ("family", "food_terms", "task"):
            require(isinstance(case.get(field), str) and case[field].strip(), f"{case_id}: missing {field}")
        require(1 <= len(case["food_terms"]) <= 300, f"{case_id}: terms exceed app limit")
        distinctions = case.get("critical_distinctions")
        require(isinstance(distinctions, list) and distinctions
                and all(isinstance(item, str) and item.strip() for item in distinctions),
                f"{case_id}: missing critical distinctions")
        leads = case.get("source_leads")
        require(isinstance(leads, list) and all(safe_url(url) for url in leads),
                f"{case_id}: invalid source example")
    return cases


def verify_frozen_contract(case_path, contract_path):
    contract = load(contract_path)
    require(contract.get("schema_version") == "gemini-grounding-contract-v1", "unsupported frozen contract")
    require(contract.get("case_file") == case_path.name, "contract names another case file")
    digest = hashlib.sha256(case_path.read_bytes()).hexdigest()
    require(digest == contract.get("cases_sha256"), "frozen case hash changed")
    pre_review_name = contract.get("pre_review_file")
    pre_review_digest = contract.get("pre_review_sha256")
    require((pre_review_name is None) == (pre_review_digest is None),
            "incomplete pre-review contract")
    if pre_review_name is not None:
        require(isinstance(pre_review_name, str) and pre_review_name not in {"", ".", ".."}
                and Path(pre_review_name).name == pre_review_name,
                "invalid pre-review file")
        actual = hashlib.sha256((contract_path.parent / pre_review_name).read_bytes()).hexdigest()
        require(actual == pre_review_digest, "frozen pre-review hash changed")
    cases = validate_cases(load(case_path))
    for split in ("development", "holdout"):
        require(sum(case["split"] == split for case in cases) == contract.get(f"{split}_count"),
                f"frozen {split} split changed")
    require(contract.get("source_admission") is False, "invalid source-admission boundary")
    return cases


def indexed_rows(document, expected_version, key, case_ids):
    require(document.get("schema_version") == expected_version, f"unsupported {key} schema")
    rows = document.get("results")
    require(isinstance(rows, list), f"{key}: results must be a list")
    index = {}
    for row in rows:
        case_id = row.get("case_id")
        require(case_id in case_ids and case_id not in index, f"{key}: unexpected or duplicate case {case_id}")
        index[case_id] = row
    require(set(index) == case_ids, f"{key}: missing cases {sorted(case_ids - set(index))}")
    return index


def evaluate(case_document, replay, judgements):
    cases = validate_cases(case_document)
    case_ids = {case["id"] for case in cases}
    require(isinstance(replay.get("run_id"), str) and replay["run_id"].strip(), "missing run id")
    require(replay.get("run_id") == judgements.get("run_id"), "replay and review run ids differ")
    require(isinstance(replay.get("provider"), str) and replay["provider"].strip(), "missing provider")
    require(isinstance(replay.get("model"), str) and replay["model"].strip(), "missing model identifier")
    require(isinstance(replay.get("captured_on"), str) and replay["captured_on"].strip(), "missing capture date")
    require(isinstance(judgements.get("reviewer"), str) and judgements["reviewer"].strip(), "missing reviewer")
    require(isinstance(judgements.get("reviewed_on"), str) and judgements["reviewed_on"].strip(), "missing review date")
    responses = indexed_rows(replay, REPLAY_VERSION, "replay", case_ids)
    judgement_version = judgements.get("schema_version")
    require(judgement_version in JUDGEMENT_VERSIONS, "unsupported judgement schema")
    page_review = judgement_version == "gemini-grounding-judgements-v2"
    reviews = indexed_rows(judgements, judgement_version, "judgement", case_ids)
    per_case = []
    for case in cases:
        case_id = case["id"]
        response = responses[case_id]
        review = reviews[case_id]
        answer = response.get("response_text")
        leads = response.get("leads")
        labelled_leads = review.get("leads")
        require(isinstance(answer, str), f"{case_id}: missing response text")
        require(isinstance(leads, list) and isinstance(labelled_leads, list)
                and len(leads) == len(labelled_leads), f"{case_id}: incomplete lead review")
        require(type(response.get("suggestions_present")) is bool, f"{case_id}: missing suggestion status")
        for flag in ("distinctions_preserved", "promotes_unverified_nutrition"):
            require(type(review.get(flag)) is bool, f"{case_id}: missing {flag} review")
        if page_review:
            for flag in ("quotes_unrequested_nutrition", "misreads_consumed_amount_as_pack"):
                require(type(review.get(flag)) is bool, f"{case_id}: missing {flag} review")
        require(isinstance(review.get("answer_note"), str) and review["answer_note"].strip(),
                f"{case_id}: missing answer evidence note")
        for ordinal, (lead, judgement) in enumerate(zip(leads, labelled_leads), start=1):
            require(isinstance(lead.get("title"), str) and lead["title"].strip(),
                    f"{case_id} lead {ordinal}: missing title")
            require(safe_url(lead.get("url")), f"{case_id} lead {ordinal}: unsafe URL")
            cited = lead.get("cited_text")
            require(isinstance(cited, str) and cited.strip() and cited in answer,
                    f"{case_id} lead {ordinal}: citation not attached to response text")
            require(judgement.get("grade") in GRADES, f"{case_id} lead {ordinal}: invalid grade")
            require(judgement.get("supports_cited_text") in SUPPORT,
                    f"{case_id} lead {ordinal}: invalid citation review")
            require(isinstance(judgement.get("evidence_note"), str) and judgement["evidence_note"].strip(),
                    f"{case_id} lead {ordinal}: missing page evidence note")
            if page_review:
                resolved = judgement.get("resolved_url")
                require(resolved is None or safe_url(resolved),
                        f"{case_id} lead {ordinal}: invalid resolved URL")
                require(resolved is not None or judgement["grade"] == "unverified",
                        f"{case_id} lead {ordinal}: unresolved page cannot receive a relevance grade")
                require(resolved is not None or judgement["supports_cited_text"] == "unverified",
                        f"{case_id} lead {ordinal}: unresolved page cannot support a citation")
        if page_review:
            pages = {}
            for lead, judgement in zip(leads, labelled_leads):
                identity = judgement["resolved_url"] or lead["url"]
                pages.setdefault(identity, []).append(judgement)
            top = []
            for citations in list(pages.values())[:3]:
                grades = {citation["grade"] for citation in citations}
                supported = any(citation["supports_cited_text"] == "yes" for citation in citations)
                if "severe_mismatch" in grades:
                    grade = "severe_mismatch"
                elif supported and grades == {"exact_primary"}:
                    grade = "exact_primary"
                elif supported and grades <= {"exact_primary", "useful_related"}:
                    grade = "useful_related"
                else:
                    grade = "unverified"
                top.append({"grade": grade})
        else:
            top = labelled_leads[:3]
        per_case.append({
            "case_id": case_id, "split": case["split"], "family": case["family"],
            "lead_count": len(leads), "page_count": len(pages) if page_review else None,
            "suggestions_present": response["suggestions_present"],
            "useful_at_3": any(lead["grade"] in {"exact_primary", "useful_related"} for lead in top),
            "primary_at_3": any(lead["grade"] == "exact_primary" for lead in top),
            "useful_leads_at_3": sum(lead["grade"] in {"exact_primary", "useful_related"} for lead in top),
            "inspected_leads_at_3": len(top),
            "supported_citations": sum(lead["supports_cited_text"] == "yes" for lead in labelled_leads),
            "unsupported_citations": sum(lead["supports_cited_text"] == "no" for lead in labelled_leads),
            "unverified_citations": sum(lead["supports_cited_text"] == "unverified" for lead in labelled_leads),
            "severe_mismatch": any(lead["grade"] == "severe_mismatch" for lead in labelled_leads),
            "distinctions_preserved": review["distinctions_preserved"],
            "promotes_unverified_nutrition": review["promotes_unverified_nutrition"],
        })
        if page_review:
            per_case[-1]["quotes_unrequested_nutrition"] = review["quotes_unrequested_nutrition"]
            per_case[-1]["misreads_consumed_amount_as_pack"] = review["misreads_consumed_amount_as_pack"]

    groups = defaultdict(list)
    for row in per_case:
        groups["all"].append(row)
        groups[f"split:{row['split']}"].append(row)
        groups[f"family:{row['family']}"].append(row)

    def summary(rows):
        inspected = sum(row["inspected_leads_at_3"] for row in rows)
        citations = sum(row["lead_count"] for row in rows)
        result = {
            "cases": len(rows), "leads": citations,
            "useful_at_3": sum(row["useful_at_3"] for row in rows),
            "primary_at_3": sum(row["primary_at_3"] for row in rows),
            "lead_precision_at_3": (sum(row["useful_leads_at_3"] for row in rows) / inspected
                                    if inspected else None),
            "structurally_attached_citations": citations,
            "supported_citations": sum(row["supported_citations"] for row in rows),
            "unsupported_citations": sum(row["unsupported_citations"] for row in rows),
            "unverified_citations": sum(row["unverified_citations"] for row in rows),
            "severe_mismatch_cases": sum(row["severe_mismatch"] for row in rows),
            "distinctions_preserved_cases": sum(row["distinctions_preserved"] for row in rows),
            "nutrition_promotion_cases": sum(row["promotes_unverified_nutrition"] for row in rows),
            "suggestions_present_cases": sum(row["suggestions_present"] for row in rows),
        }
        if page_review:
            result["source_pages"] = sum(row["page_count"] for row in rows)
            result["duplicate_citation_annotations"] = citations - result["source_pages"]
            result["page_precision_at_3"] = result.pop("lead_precision_at_3")
            result["citation_annotations"] = result.pop("leads")
            result["unrequested_nutrition_cases"] = sum(row["quotes_unrequested_nutrition"] for row in rows)
            result["consumed_amount_as_pack_cases"] = sum(row["misreads_consumed_amount_as_pack"] for row in rows)
        return result

    groups = {name: summary(rows) for name, rows in sorted(groups.items())}
    if page_review:
        for row in per_case:
            row["citation_annotations"] = row.pop("lead_count")
            row["source_pages"] = row.pop("page_count")
            row["useful_pages_at_3"] = row.pop("useful_leads_at_3")
            row["inspected_pages_at_3"] = row.pop("inspected_leads_at_3")
    else:
        for row in per_case:
            row.pop("page_count")
    return {"schema_version": "gemini-grounding-report-v2" if page_review else "gemini-grounding-report-v1",
            "scoring_unit": "reviewed_source_page" if page_review else "citation_annotation",
            "run_id": replay["run_id"],
            "provider": replay["provider"], "model": replay["model"],
            "captured_on": replay["captured_on"], "reviewer": judgements["reviewer"],
            "reviewed_on": judgements["reviewed_on"],
            "interpretation": "Reviewed source-discovery diagnostics only; no nutrition admission or device/provider acceptance",
            "groups": groups,
            "cases": per_case}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-cases", type=Path)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--replay", type=Path)
    parser.add_argument("--judgements", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        if args.validate_cases:
            cases = verify_frozen_contract(args.validate_cases, args.contract)
            print(json.dumps({"valid_cases": len(cases),
                              "development": sum(case["split"] == "development" for case in cases),
                              "holdout": sum(case["split"] == "holdout" for case in cases)}))
            return
        require(all((args.cases, args.replay, args.judgements, args.output)),
                "provide --cases, --replay, --judgements and --output")
        verify_frozen_contract(args.cases, args.contract)
        result = evaluate(load(args.cases), load(args.replay), load(args.judgements))
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(result["groups"]["all"], sort_keys=True))
    except (EvaluationError, OSError, json.JSONDecodeError) as error:
        parser.exit(2, f"evaluation invalid: {error}\n")


if __name__ == "__main__":
    main()
