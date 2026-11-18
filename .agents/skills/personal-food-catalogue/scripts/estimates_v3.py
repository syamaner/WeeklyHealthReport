"""The label photo rules of `personal-food-catalogue-estimates-v3`
(docs/personal-food-catalogue-off-estimates-v1-proposal.md sections 2.1 to 2.4; phase gate
docs/personal-food-catalogue-off-estimates-v1-phase.md sections 2 and 4).

Pure. `estimates_v2.check` calls these only for a v3 file, so a v2 file keeps exactly its v2 codes.
The Swift codec (`PersonalFoodDatabasePhotoEstimates.swift`) applies the same rules in the same order.
"""
import re

SCHEMA = "personal-food-catalogue-estimates-v3"
TOKEN = "product_dataset_photo"
PHOTO_PREFIX = "https://images.openfoodfacts.org/images/products/"
URL_LIMIT = 2048
HEX64 = re.compile(r"[0-9a-f]{64}")
DIGITS = re.compile(r"[0-9]+")
STATE_BASES = ("source_states_it", "stated_assumption")
METHODS = ("direct", "carried_from_similar_food")
RULE_CODES = ("photo-fields", "photo-relation", "photo-missing")
# Phase gate section 2.4: the closed source states, compared as exact bytes.
SOURCE_STATES = ("as sold", "as sold, cooked", "as prepared", "raw", "cooked", "dried", "frozen", "canned",
                 "drained", "smoked")
COMPATIBLE = {
    "unknown": {"as sold", "raw"},
    "raw": {"raw", "as sold"},
    "cooked": {"cooked", "as sold, cooked", "as prepared"},
    "canned": {"canned", "drained", "as sold"},
    "dried": {"dried", "as sold"},
    "frozen": {"frozen", "as sold"},
    "smoked": {"smoked", "as sold"},
}


def barcode(ref):
    """The barcode of a photo address (phase gate section 2.1), or None when the address is not
    exactly the photo form: the fixed prefix, one or more all-digit segments, one file name."""
    if not isinstance(ref, str) or not ref.startswith(PHOTO_PREFIX) or len(ref.encode("utf-8")) > URL_LIMIT:
        return None
    try:
        raw = ref.encode("ascii")
    except UnicodeEncodeError:
        return None
    if any(b < 0x21 or b > 0x7e for b in raw) or "?" in ref or "#" in ref:
        return None
    parts = ref[len(PHOTO_PREFIX):].split("/")
    if len(parts) < 2 or not parts[-1] or not all(DIGITS.fullmatch(p) for p in parts[:-1]):
        return None
    return "".join(parts[:-1])


def strip_zeros(digits: str) -> str:
    return digits.lstrip("0") or "0"


def entry_barcodes(item) -> set:
    """The digits of every `off:gtin:` record the entry cites in its labels, leading zeros removed."""
    labels = item.get("label_nutrients") if isinstance(item, dict) else None
    out = set()
    for v in (labels.values() if isinstance(labels, dict) else []):
        rid = v.get("record_id") if isinstance(v, dict) else None
        if isinstance(rid, str) and rid.startswith("off:gtin:") and DIGITS.fullmatch(rid[len("off:gtin:"):]):
            out.add(strip_zeros(rid[len("off:gtin:"):]))
    return out


def record_fails(rec, date_ok) -> bool:
    """Section 2.1 and 2.2 for one photo record: True when any rule fails (one `photo-fields`)."""
    return (rec.get("composition_source") is not None or rec.get("page_access") != "direct_read"
            or barcode(rec.get("source_reference")) is None
            or not (isinstance(rec.get("source_digest"), str) and HEX64.fullmatch(rec["source_digest"]))
            or not date_ok(rec.get("retrieved_on"))
            or rec.get("state_basis") not in STATE_BASES or rec.get("method") not in METHODS
            or rec.get("derivation") is not None)


def check_record(rec, err, where, date_ok):
    if record_fails(rec, date_ok):
        err("photo-fields", where)


def relation_codes(rec, item) -> list:
    """Section 2.3: `direct` only for a photo of a barcode the entry cites."""
    code = barcode(rec.get("source_reference"))
    if rec.get("method") == "direct" and (code is None or strip_zeros(code) not in entry_barcodes(item)):
        return ["photo-relation"]
    return []


def check_missing(doc, err):
    """A v3 file holds at least one photo estimate (cited evidence of the token)."""
    cited = set()
    for it in doc.get("items", []) if isinstance(doc.get("items"), list) else []:
        est = it.get("estimated_nutrients") if isinstance(it, dict) else None
        for v in (est.values() if isinstance(est, dict) else []):
            if isinstance(v, dict) and isinstance(v.get("evidence_id"), str):
                cited.add(v["evidence_id"])
    evidence = doc.get("estimate_evidence") if isinstance(doc.get("estimate_evidence"), list) else []
    if not any(isinstance(r, dict) and r.get("source_type") == TOKEN and r.get("id") in cited for r in evidence):
        err("photo-missing", "a v3 file holds no photo estimate")


def state_compatible(entry_state, source_state, state_basis) -> bool:
    """Phase gate section 2.4, with `canned` + `as sold` only when the panel states it."""
    if source_state not in COMPATIBLE.get(entry_state, set()):
        return False
    return not (entry_state == "canned" and source_state == "as sold" and state_basis != "source_states_it")
