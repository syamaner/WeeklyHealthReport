"""The pfd-exclusions-v1 file: what the later export phase withholds. Pure: data in, bytes out.

Design: docs/personal-food-database-review-v2-design.md, section 6. Private, written to
`exclusions-v2/` outside both sealed folders. It holds entry IDs, inventory keys and assessment
tokens only, never values, titles, URLs or record identifiers. A new field or token set is a new
schema version.

    {"schema": "pfd-exclusions-v1", "release_id": "pfc:sha256:...",
     "withhold_entries": ["pfc:..."],                                  every value and reference
     "withhold_values": [{"entry_id", "nutrient", "assessment"}],     one value each (error_*)
     "reference_candidates": ["pfc:..."]}                             unresolved: stays a candidate
"""
import json
import re

from formats import ENTRY_ID, RELEASE_ID, FormatError, dumps

SCHEMA = "pfd-exclusions-v1"
KEYS = {"schema", "release_id", "withhold_entries", "withhold_values", "reference_candidates"}
VALUE_KEYS = {"entry_id", "nutrient", "assessment"}
ERRORS = {"error_basis", "error_state", "error_transcription", "error_derivation", "error_source"}
NUTRIENT = re.compile(r"[a-z][a-z0-9_]*")


def _validate(doc: dict):
    if not isinstance(doc, dict) or set(doc) != KEYS or doc["schema"] != SCHEMA:
        raise FormatError("exclusions: not a pfd-exclusions-v1 document")
    if not isinstance(doc["release_id"], str) or not RELEASE_ID.fullmatch(doc["release_id"]):
        raise FormatError("exclusions: invalid release_id")
    for field in ("withhold_entries", "reference_candidates"):
        ids = doc[field]
        if not isinstance(ids, list) or not all(isinstance(i, str) and ENTRY_ID.fullmatch(i) for i in ids) \
                or len(set(ids)) != len(ids):
            raise FormatError(f"exclusions: {field}: entry IDs, each once")
    if set(doc["withhold_entries"]) & set(doc["reference_candidates"]):
        raise FormatError("exclusions: an entry is both withheld and a pending candidate")
    vals = doc["withhold_values"]
    if not isinstance(vals, list):
        raise FormatError("exclusions: withhold_values must be a list")
    seen = set()
    for n, v in enumerate(vals):
        if not isinstance(v, dict) or set(v) != VALUE_KEYS:
            raise FormatError(f"exclusions: value {n}: fields must be entry_id, nutrient and assessment")
        if not (isinstance(v["entry_id"], str) and ENTRY_ID.fullmatch(v["entry_id"])
                and isinstance(v["nutrient"], str) and NUTRIENT.fullmatch(v["nutrient"]) and v["assessment"] in ERRORS):
            raise FormatError(f"exclusions: value {n}: invalid field")
        if (v["entry_id"], v["nutrient"]) in seen:
            raise FormatError(f"exclusions: value {n}: listed twice")
        seen.add((v["entry_id"], v["nutrient"]))


def build(release_id: str, data: dict) -> bytes:
    """`data` is score_a_v2.exclusion_list output."""
    doc = {"schema": SCHEMA, "release_id": release_id, **data}
    _validate(doc)
    return dumps(doc)


def parse(data: bytes) -> dict:
    try:
        doc = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise FormatError("exclusions: not valid UTF-8 JSON") from None
    _validate(doc)
    return doc
