#!/usr/bin/env python3
"""Capture bounded Gemini development cases without retaining credentials or raw replies."""

import argparse
import http.client
import json
import os
import subprocess
from datetime import date
from pathlib import Path

from evaluate import EvaluationError, load, safe_url, verify_frozen_contract

MODEL = "gemini-3.8-flash"
INSTRUCTION_TIMEOUT = 30
MAX_REPLY_BYTES = 1_000_000


def request_body(food_terms, instruction, thinking_level=None):
    generation = {"max_output_tokens": 2048}
    if thinking_level is not None:
        if thinking_level not in {"low", "medium", "high"}:
            raise EvaluationError("unsupported thinking level")
        generation["thinking_level"] = thinking_level
    return json.dumps({"model": MODEL, "input": food_terms, "system_instruction": instruction,
                       "tools": [{"type": "google_search"}], "store": False,
                       "generation_config": generation}).encode("utf-8")


def key_from_keychain(service):
    completed = subprocess.run(["security", "find-generic-password", "-s", service, "-w"],
                               capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise EvaluationError("Mac Keychain credential could not be read")
    key = completed.stdout.rstrip("\r\n")
    encoded = key.encode("utf-8")
    if not (20 <= len(encoded) <= 512 and all(33 <= byte <= 126 for byte in encoded)):
        raise EvaluationError("Mac Keychain credential is not a header-safe value")
    return key


def live_fetch(body, key):
    connection = http.client.HTTPSConnection("generativelanguage.googleapis.com",
                                            timeout=INSTRUCTION_TIMEOUT)
    try:
        connection.request("POST", "/v1beta/interactions", body=body,
                           headers={"x-goog-api-key": key, "Content-Type": "application/json"})
        response = connection.getresponse()
        return response.status, response.read(MAX_REPLY_BYTES + 1)
    finally:
        connection.close()


def project_completed(case_id, reply):
    if not isinstance(reply, dict) or reply.get("status") != "completed":
        raise EvaluationError(f"{case_id}: interaction is not completed")
    steps = reply.get("steps")
    if not isinstance(steps, list):
        raise EvaluationError(f"{case_id}: missing steps")
    blocks = []
    suggestions_present = False
    for step in steps:
        if not isinstance(step, dict):
            raise EvaluationError(f"{case_id}: invalid step")
        if step.get("type") == "model_output":
            content = step.get("content") or []
            if not isinstance(content, list) or any(not isinstance(block, dict) for block in content):
                raise EvaluationError(f"{case_id}: invalid content")
            blocks.extend(block for block in content if block.get("type") == "text")
        elif step.get("type") == "google_search_result":
            results = step.get("result") or []
            if not isinstance(results, list) or any(not isinstance(result, dict) for result in results):
                raise EvaluationError(f"{case_id}: invalid search result")
            suggestions_present |= any(result.get("search_suggestions") for result in results)
    if not blocks:
        raise EvaluationError(f"{case_id}: no model text")
    texts, leads = [], []
    for block in blocks:
        response_text = block.get("text")
        if not isinstance(response_text, str):
            raise EvaluationError(f"{case_id}: invalid response text")
        texts.append(response_text)
        encoded = response_text.encode("utf-8")
        annotations = block.get("annotations") or []
        if not isinstance(annotations, list) or any(not isinstance(item, dict) for item in annotations):
            raise EvaluationError(f"{case_id}: invalid annotations")
        for citation in annotations:
            if citation.get("type") != "url_citation":
                continue
            start, end = citation.get("start_index"), citation.get("end_index")
            url, title = citation.get("url"), citation.get("title")
            if (type(start) is not int or type(end) is not int or not 0 <= start < end <= len(encoded)
                    or not safe_url(url) or title is not None and not isinstance(title, str)):
                raise EvaluationError(f"{case_id}: invalid citation")
            try:
                cited_text = encoded[start:end].decode("utf-8")
            except UnicodeDecodeError as error:
                raise EvaluationError(f"{case_id}: invalid citation span") from error
            if not cited_text.strip():
                raise EvaluationError(f"{case_id}: empty citation")
            leads.append({"title": title or url, "url": url, "cited_text": cited_text})
    return {"case_id": case_id, "response_text": "\n\n".join(texts),
            "leads": leads, "suggestions_present": bool(suggestions_present)}


def write_private_json(path, document):
    encoded = (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    temporary = path.with_name(path.name + ".tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as target:
            target.write(encoded)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def capture(cases, case_ids, instruction, key, output_dir, run_id, captured_on, fetch,
            thinking_level=None):
    case_by_id = {case["id"]: case for case in cases}
    if len(case_ids) != len(set(case_ids)) or any(case_id not in case_by_id for case_id in case_ids):
        raise EvaluationError("unknown or duplicate case ID")
    if any(case_by_id[case_id]["split"] != "development" for case_id in case_ids):
        raise EvaluationError("collector accepts development cases only")
    output_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
    replay = {"schema_version": "gemini-grounding-replay-v1", "run_id": run_id,
              "provider": "Google Gemini", "model": MODEL, "captured_on": captured_on, "results": []}
    journal = {"run_id": run_id, "attempts": []}
    replay_path, journal_path = output_dir / "replay.json", output_dir / "attempts.json"
    write_private_json(replay_path, replay)
    write_private_json(journal_path, journal)
    for case_id in case_ids:
        attempt = {"case_id": case_id, "outcome": "started"}
        journal["attempts"].append(attempt)
        write_private_json(journal_path, journal)
        try:
            status, raw = fetch(request_body(case_by_id[case_id]["food_terms"], instruction,
                                             thinking_level), key)
        except TimeoutError:
            attempt["outcome"] = "timeout"
            write_private_json(journal_path, journal)
            break
        except Exception:
            attempt["outcome"] = "transport_error"
            write_private_json(journal_path, journal)
            break
        attempt["http_status"] = status
        if status != 200 or len(raw) > MAX_REPLY_BYTES or key.encode("utf-8") in raw:
            attempt["outcome"] = "response_rejected"
            write_private_json(journal_path, journal)
            break
        try:
            reply = json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError):
            attempt["outcome"] = "invalid_json"
            write_private_json(journal_path, journal)
            break
        interaction_status = reply.get("status") if isinstance(reply, dict) else None
        attempt["interaction_status"] = (interaction_status if interaction_status in {
            "queued", "in_progress", "requires_action", "completed", "failed", "cancelled", "incomplete"
        } else "unknown")
        if interaction_status != "completed":
            attempt["outcome"] = "non_completed"
            write_private_json(journal_path, journal)
            break
        try:
            projected = project_completed(case_id, reply)
        except EvaluationError:
            attempt["outcome"] = "invalid_projection"
            write_private_json(journal_path, journal)
            break
        replay["results"].append(projected)
        write_private_json(replay_path, replay)
        attempt["outcome"] = "completed"
        attempt["cited_leads"] = len(projected["leads"])
        write_private_json(journal_path, journal)
    return journal


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--cases", type=Path, required=True)
    parser.add_argument("--prompt", type=Path, required=True)
    parser.add_argument("--case-id", action="append", required=True)
    parser.add_argument("--max-requests", type=int, required=True)
    parser.add_argument("--thinking-level", choices=("low", "medium", "high"))
    parser.add_argument("--keychain-service", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()
    try:
        cases = verify_frozen_contract(args.cases, args.contract)
        if args.max_requests < 1 or len(args.case_id) > args.max_requests:
            raise EvaluationError("case IDs exceed request cap")
        if any(case_id not in {case["id"] for case in cases if case["split"] == "development"}
               for case_id in args.case_id):
            raise EvaluationError("collector accepts development cases only")
        instruction = args.prompt.read_text(encoding="utf-8").strip()
        if not instruction or not args.run_id.strip():
            raise EvaluationError("prompt and run ID must be nonempty")
        if args.output_dir.exists():
            raise EvaluationError("output directory already exists")
        key = key_from_keychain(args.keychain_service)
        journal = capture(cases, args.case_id, instruction, key, args.output_dir,
                          args.run_id, str(date.today()), live_fetch, args.thinking_level)
        print(json.dumps({"attempts": journal["attempts"], "output_dir": str(args.output_dir)}))
    except (EvaluationError, OSError, ValueError) as error:
        parser.exit(2, f"collector failed: {error}\n")


if __name__ == "__main__":
    main()
