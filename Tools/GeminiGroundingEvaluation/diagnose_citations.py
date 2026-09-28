#!/usr/bin/env python3
"""Flag model-written link hosts that disagree with grounding citation host hints."""

import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

MARKDOWN_LINK = re.compile(r"\[[^\]]+\]\((https://[^\s)]+)\)")
HOST_HINT = re.compile(r"(?:[a-z0-9-]+\.)+[a-z]{2,}", re.IGNORECASE)
GROUNDING_REDIRECT = "vertexaisearch.cloud.google.com"


def host(value):
    try:
        parsed = urlsplit(value)
        return (parsed.hostname or "").lower().removeprefix("www.")
    except ValueError:
        return ""


def compatible(left, right):
    return left == right or left.endswith("." + right) or right.endswith("." + left)


def diagnose_lead(lead):
    cited = lead.get("cited_text", "")
    written_hosts = sorted({host(url) for url in MARKDOWN_LINK.findall(cited)} - {""})
    comparable_hosts = [item for item in written_hosts if item != GROUNDING_REDIRECT]
    title = lead.get("title", "")
    hinted_host = title.lower().removeprefix("www.") if HOST_HINT.fullmatch(title) else ""
    if not hinted_host:
        citation_host = host(lead.get("url", ""))
        if citation_host and citation_host != GROUNDING_REDIRECT:
            hinted_host = citation_host
    return {
        "citation_host_hint": hinted_host or None,
        "written_link_hosts": written_hosts,
        "apparent_host_mismatch": bool(hinted_host and comparable_hosts and
                                      not any(compatible(hinted_host, item) for item in comparable_hosts)),
        "opaque_written_redirect": GROUNDING_REDIRECT in written_hosts,
        "multiple_written_hosts": len(written_hosts) > 1,
        "no_written_link_in_span": not written_hosts,
    }


def diagnose_replay(replay):
    if replay.get("schema_version") != "gemini-grounding-replay-v1":
        raise ValueError("unsupported replay schema")
    results = replay.get("results")
    if not isinstance(results, list):
        raise ValueError("missing replay results")
    cases = []
    for result in results:
        case_id, leads = result.get("case_id"), result.get("leads")
        if not isinstance(case_id, str) or not isinstance(leads, list):
            raise ValueError("invalid replay case")
        annotations = []
        for index, lead in enumerate(leads, start=1):
            if not isinstance(lead, dict):
                raise ValueError("invalid citation annotation")
            annotations.append({"annotation_index": index, **diagnose_lead(lead)})
        cases.append({"case_id": case_id, "annotations": annotations})
    all_annotations = [item for case in cases for item in case["annotations"]]
    return {
        "schema_version": "gemini-citation-diagnostic-v1",
        "interpretation": "Host-shape hints only; not page verification or claim support",
        "cases": cases,
        "counts": {
            "cases": len(cases),
            "annotations": len(all_annotations),
            "apparent_host_mismatch": sum(item["apparent_host_mismatch"] for item in all_annotations),
            "opaque_written_redirect": sum(item["opaque_written_redirect"] for item in all_annotations),
            "multiple_written_hosts": sum(item["multiple_written_hosts"] for item in all_annotations),
            "no_written_link_in_span": sum(item["no_written_link_in_span"] for item in all_annotations),
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("replay", type=Path)
    args = parser.parse_args()
    try:
        replay = json.loads(args.replay.read_text(encoding="utf-8"))
        print(json.dumps(diagnose_replay(replay), indent=2, sort_keys=True))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(2, f"citation diagnostic failed: {error}\n")


if __name__ == "__main__":
    main()
