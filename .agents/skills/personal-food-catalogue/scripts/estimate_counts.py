"""The evaluator's six counts and the re-admission checks for an estimates v2 catalogue
(docs/personal-food-catalogue-estimates-v2-proposal.md section 3.1, "The evaluator's counts, six in
all", and section 3.3; phase gate docs/personal-food-catalogue-estimates-v2-phase.md section 3.2
item 5).

Pure: parsed documents in, counts out. Three private files feed it, each canonical JSON with exact
keys and closed vocabularies (references/accepted-estimates-format.md):

- `pfc-estimate-refusals-v1`: what the E3 disposition refused, carried to v2 entry IDs. Rows of
  {entry_id, source_type, source_reference, refusal_class} with an optional `nutrient` (absent: every
  nutrient of that source for that entry). Two optional lists: `former_close_references`, rows of
  {entry_id, composition_source, record_id} naming a record that was once the entry's close
  reference, and `no_e3_counterpart`, the entry IDs with no counterpart in the pinned release.
- `pfc-estimate-readmissions-v1`: the owner's re-admission list. Rows of {entry_id, nutrient,
  source_type, source_reference, method, corpus_sha256, date}.
- `pfc-estimate-readmission-sheet-v1`: the re-admission sheet. The same fields plus `refusal_class`,
  `reason` and `accept` (`accepted`, `not_accepted` or `withdrawn`).

A refused source is re-admitted only when a list row and a sheet row with `accept` `accepted` name
the same entry, nutrient, source type, source reference, method, corpus hash and date, the hash is
the catalogue's own for that corpus, and the class is re-admissible. Anything else stays refused:
no sheet row, a row not accepted or withdrawn, another hash or date, a never-re-admissible class.
"""
import re

import estimates_input as I
import estimates_v2 as E
import estimates_v3 as V3
import export_v1

SCHEMA_REFUSALS = "pfc-estimate-refusals-v1"
SCHEMA_READMISSIONS = "pfc-estimate-readmissions-v1"
SCHEMA_SHEET = "pfc-estimate-readmission-sheet-v1"
# Contract section 3.1, "What can be re-admitted (closed list)": a stratum consequence (E3 section 6)
# or the removal-only mechanics of its section 3.
RE_ADMISSIBLE = ("stratum_consequence", "removal_mechanics")
# "Never re-admissible": an Open Food Facts underlying source; the unresolved A1 values; a per-entry
# exclusion (wrong identity, incompatible state, variety mismatch); a value excluded for its own wrong
# basis, transcription or derivation; a class with no truthful source type.
NEVER = ("open_food_facts", "unresolved_a1", "per_entry_exclusion", "value_fault", "no_truthful_source_type")
CLASSES = RE_ADMISSIBLE + NEVER
ACCEPT = ("accepted", "not_accepted", "withdrawn")
SENTENCE = "The evaluation withheld this source and the owner re-admitted it."
MUST_BE_ZERO = ("close_reference_as_same_food", "refused_not_readmitted", "readmitted_above_medium",
                "aggregator_not_stated_above_medium")
REPORTED = ("readmitted", "no_e3_counterpart")
REFUSAL_KEYS = {"entry_id", "source_type", "source_reference", "refusal_class"}
FORMER_KEYS = {"entry_id", "composition_source", "record_id"}
LIST_KEYS = {"entry_id", "nutrient", "source_type", "source_reference", "method", "corpus_sha256", "date"}
SHEET_KEYS = LIST_KEYS | {"refusal_class", "reason", "accept"}
HEX64 = re.compile(r"[0-9a-f]{64}")


def _refuse(what, text):
    raise I.EstimatesRefused(f"{what}: {text}")


def _token(v, allowed) -> bool:
    return isinstance(v, str) and v in allowed


def _entry(v) -> bool:
    return isinstance(v, str) and I.ENTRY_ID.fullmatch(v) is not None


def _reference(v) -> bool:
    return isinstance(v, str) and bool(v) and len(v) <= E.URL_LIMIT and not E.CONTROL.search(v)


def _ascending(keys, what):
    if keys != sorted(set(keys)):
        _refuse(what, "rows must be in ascending order, each once")


def _validate_refusals(doc):
    what = "estimate refusals"
    optional = {"former_close_references", "no_e3_counterpart"}
    if not isinstance(doc, dict) or doc.get("schema") != SCHEMA_REFUSALS \
            or not {"schema", "rows"} <= set(doc) or set(doc) - {"schema", "rows"} - optional:
        _refuse(what, f"not a {SCHEMA_REFUSALS} document")
    if not isinstance(doc["rows"], list):
        _refuse(what, "rows must be a list")
    keys = []
    for n, row in enumerate(doc["rows"]):
        if not isinstance(row, dict) or set(row) - {"nutrient"} != REFUSAL_KEYS:
            _refuse(what, f"row {n}: fields must be {sorted(REFUSAL_KEYS)}, with an optional nutrient")
        if not _entry(row["entry_id"]) or not _token(row["source_type"], E.SOURCE_TYPES) \
                or not _reference(row["source_reference"]) or not _token(row["refusal_class"], CLASSES) \
                or ("nutrient" in row and not _token(row["nutrient"], export_v1.CANON_UNITS)):
            _refuse(what, f"row {n}: a field is outside its form or closed list")
        keys.append((row["entry_id"], row["source_type"], row["source_reference"], row.get("nutrient", ""),
                     row["refusal_class"]))
    _ascending(keys, what)
    former = doc.get("former_close_references", [])
    if not isinstance(former, list):
        _refuse(what, "former_close_references must be a list")
    keys = []
    for n, row in enumerate(former):
        if not isinstance(row, dict) or set(row) != FORMER_KEYS or not _entry(row["entry_id"]) \
                or not _token(row["composition_source"], export_v1.GENERIC_SOURCES) or not _reference(row["record_id"]):
            _refuse(what, f"former_close_references {n}: must be exactly {sorted(FORMER_KEYS)}")
        keys.append((row["entry_id"], row["composition_source"], row["record_id"]))
    _ascending(keys, what)
    none = doc.get("no_e3_counterpart", [])
    if not isinstance(none, list) or not all(_entry(v) for v in none):
        _refuse(what, "no_e3_counterpart must be a list of entry IDs")
    _ascending(list(none), what)


def _validate_rows(doc, schema, row_keys, what):
    if not isinstance(doc, dict) or set(doc) != {"schema", "rows"} or doc["schema"] != schema:
        _refuse(what, f"not a {schema} document")
    if not isinstance(doc["rows"], list):
        _refuse(what, "rows must be a list")
    keys = []
    for n, row in enumerate(doc["rows"]):
        if not isinstance(row, dict) or set(row) != row_keys:
            _refuse(what, f"row {n}: fields must be exactly {sorted(row_keys)}")
        if not _entry(row["entry_id"]) or not _token(row["nutrient"], export_v1.CANON_UNITS) \
                or not _token(row["source_type"], E.SOURCE_TYPES) or not _reference(row["source_reference"]) \
                or not _token(row["method"], E.METHODS) or not export_v1._date(row["date"]) \
                or not isinstance(row["corpus_sha256"], str) or not HEX64.fullmatch(row["corpus_sha256"]):
            _refuse(what, f"row {n}: a field is outside its form or closed list")
        if row_keys == SHEET_KEYS and (not _token(row["refusal_class"], CLASSES) or not _token(row["accept"], ACCEPT)
                                       or not E.text_ok(row["reason"], 500)):
            _refuse(what, f"row {n}: refusal_class, reason or accept is outside its form or closed list")
        keys.append(_value_key(row))
    _ascending(keys, what)  # one row per value, so a withdrawn row cannot hide behind an accepted copy


def _value_key(row):
    return (row["entry_id"], row["nutrient"], row["source_type"], row["source_reference"], row["method"])


def _parse(data, what, validator, *args):
    doc = I.parse_canonical(data, what)
    I.guarded(what, validator, doc, *args)
    return doc


def parse_refusals(data) -> dict:
    return _parse(data, "estimate refusals", _validate_refusals)


def parse_readmissions(data) -> dict:
    return _parse(data, "estimate re-admissions", _validate_rows, SCHEMA_READMISSIONS, LIST_KEYS,
                  "estimate re-admissions")


def parse_sheet(data) -> dict:
    return _parse(data, "estimate re-admission sheet", _validate_rows, SCHEMA_SHEET, SHEET_KEYS,
                  "estimate re-admission sheet")


def reference_key(source_type, reference):
    """What two source references are compared on. A bundled record ID is compared as written. A
    page address is compared on its host as the checker reads it (lower case, no trailing dot) and
    the rest after the authority, so a refused page is not written again under another spelling of
    the same host. An address the checker would not accept is compared as written."""
    if source_type == "national_composition" or not isinstance(reference, str):
        return reference
    host = E.page_host(reference)
    if host is None:
        return reference
    authority, slash, rest = reference[len(E.URL_PREFIX):].partition("/")
    port = authority.partition(":")[2]
    return f"{host}:{port}/{rest}"


# Label photo phase gate section 3: the classes a photo estimate is matched against whatever the
# refusal row's source type, by entry and nutrient, or by barcode for every entry.
PHOTO_CLASSES = ("open_food_facts", "per_entry_exclusion", "value_fault", "unresolved_a1")
GTIN_PREFIX = "off:gtin:"
PRODUCT_PATH = re.compile(r"/product/([0-9]+)(?:/|$)")


def refusal_barcode(reference):
    """The barcode a refusal row names (`off:gtin:<digits>` or an address with `/product/<digits>`),
    leading zeros removed, or None."""
    if not isinstance(reference, str):
        return None
    if reference.startswith(GTIN_PREFIX) and V3.DIGITS.fullmatch(reference[len(GTIN_PREFIX):]):
        return V3.strip_zeros(reference[len(GTIN_PREFIX):])
    m = PRODUCT_PATH.search(reference)
    return V3.strip_zeros(m.group(1)) if m else None


class Lists:
    """The three private lists, any of them absent (None). An absent refusal list refuses nothing;
    an absent re-admission list or sheet re-admits nothing."""

    def __init__(self, refusals=None, readmissions=None, sheet=None):
        self.refusals = (refusals or {}).get("rows", [])
        self.former = {(r["entry_id"], r["composition_source"], r["record_id"])
                       for r in (refusals or {}).get("former_close_references", [])}
        self.no_counterpart = set((refusals or {}).get("no_e3_counterpart", []))
        self.listed = {_value_key(r): r for r in (readmissions or {}).get("rows", [])}
        self.sheet = {_value_key(r): r for r in (sheet or {}).get("rows", [])}

    def accepted(self, row) -> bool:
        """A list row is in force only with a sheet row that names the same value, corpus hash and
        date and carries the owner's accept mark."""
        on_sheet = self.sheet.get(_value_key(row))
        return on_sheet is not None and on_sheet["accept"] == "accepted" \
            and on_sheet["corpus_sha256"] == row["corpus_sha256"] and on_sheet["date"] == row["date"]

    def status(self, entry_id, nutrient, evidence, corpus_sha256) -> str:
        """`clear` (on no refusal list), `refused`, `class` (listed and accepted, but of a class
        that is never re-admissible) or `readmitted`. `corpus_sha256` is the catalogue's own hash
        for the evidence's corpus, None for a page."""
        if evidence["source_type"] == V3.TOKEN:
            code = V3.barcode(evidence["source_reference"])
            code = V3.strip_zeros(code) if code else None
            hit = any(r["refusal_class"] in PHOTO_CLASSES and (
                (r["entry_id"] == entry_id and r.get("nutrient", nutrient) == nutrient)
                or (code is not None and refusal_barcode(r["source_reference"]) == code)) for r in self.refusals)
            return I.REFUSED if hit else I.CLEAR  # never re-admissible: no list or sheet row names the token
        wanted = reference_key(evidence["source_type"], evidence["source_reference"])
        hits = [r for r in self.refusals
                if r["entry_id"] == entry_id and r["source_type"] == evidence["source_type"]
                and reference_key(r["source_type"], r["source_reference"]) == wanted
                and r.get("nutrient", nutrient) == nutrient]
        if not hits:
            return I.CLEAR
        row = self.listed.get((entry_id, nutrient, evidence["source_type"], evidence["source_reference"],
                               evidence["method"]))
        # A row covers that value only: another corpus hash is a later value of the same record.
        if row is None or not self.accepted(row) or corpus_sha256 is None or row["corpus_sha256"] != corpus_sha256:
            return I.REFUSED
        classes = {r["refusal_class"] for r in hits}
        if evidence["source_type"] != "national_composition" or any(c in NEVER for c in classes) \
                or self.sheet[_value_key(row)]["refusal_class"] not in classes:
            return I.CLASS
        return I.READMITTED

    def list_checks(self) -> dict:
        """Counts about the lists themselves, whatever the catalogue holds."""
        rows = list(self.listed.values())
        return {
            "list_rows": len(rows),
            "list_rows_without_accepted_sheet_row": sum(not self.accepted(r) for r in rows),
            "list_rows_withdrawn": sum(self.sheet.get(_value_key(r), {}).get("accept") == "withdrawn" for r in rows),
            # A former close reference re-admits only as carried_from_similar_food.
            "former_close_listed_as_other_method": sum(
                r["method"] != "carried_from_similar_food"
                and any((r["entry_id"], s, r["source_reference"]) in self.former for s in export_v1.GENERIC_SOURCES)
                for r in rows),
        }


def six_counts(doc: dict, accepted_rows: list, lists: Lists) -> dict:
    """The six counts over the catalogue document about to be written (a plain v2 document has no
    estimate, so every count is 0). `accepted_rows` are the rows of the accepted-estimates input,
    which hold what the file cannot show: an aggregator's underlying source.

    Returns {"counts": the six, "checks": codes of failed re-admission checks, "lists": list counts,
    "readmitted_rows": [{entry_id, nutrient, source_reference}] for the private change report}."""
    corpora = {c["source"]: c["corpus_sha256"] for c in doc["generic_corpora"]}
    records = {r["id"]: r for r in doc.get("estimate_evidence", [])}
    underlying = {(r["entry_id"], r["nutrient"]): r for r in accepted_rows if r["scope"] == "nutrient"}
    counts = {k: 0 for k in MUST_BE_ZERO + REPORTED}
    readmitted_rows, without_sentence, photo_state = [], 0, 0
    for it in doc["items"]:
        ref = it["generic_reference"]
        for key, value in it.get("estimated_nutrients", {}).items():
            rec = records[value["evidence_id"]]
            national = rec["source_type"] == "national_composition"
            status = lists.status(it["id"], key, rec, corpora.get(rec["composition_source"]) if national else None)
            counts["refused_not_readmitted"] += status in (I.REFUSED, I.CLASS)
            if status == I.READMITTED:
                counts["readmitted"] += 1
                counts["readmitted_above_medium"] += E.QUALITY_RANK[rec["quality"]] > E.QUALITY_RANK["medium"]
                without_sentence += SENTENCE not in rec["assumption"]
                readmitted_rows.append({"entry_id": it["id"], "nutrient": key,
                                        "source_reference": rec["source_reference"]})
            if national and rec["method"] != "carried_from_similar_food":
                named = (rec["composition_source"], rec["source_reference"])
                own_close = ref is not None and ref["match"] == "close" and named == (ref["source"], ref["record_id"])
                counts["close_reference_as_same_food"] += own_close or (it["id"], *named) in lists.former
            if rec["source_type"] == "aggregator" and E.QUALITY_RANK[rec["quality"]] > E.QUALITY_RANK["medium"]:
                row = underlying.get((it["id"], key))
                # A row that cannot be found states nothing, so it counts.
                counts["aggregator_not_stated_above_medium"] += (
                    row is None or row["evidence"]["source_reference"] != rec["source_reference"]
                    or row["underlying_source"] == "not_stated")
            counts["no_e3_counterpart"] += it["id"] in lists.no_counterpart
            if rec["source_type"] == V3.TOKEN:
                photo_state += not V3.state_compatible(it["state"], rec["source_state"], rec["state_basis"])
    list_counts = lists.list_checks()
    checks = []
    if without_sentence:
        checks.append(f"readmission-sentence: {without_sentence}")
    if photo_state:
        checks.append(f"photo-state-mismatch: {photo_state}")
    if list_counts["former_close_listed_as_other_method"]:
        checks.append(f"readmission-former-close-method: {list_counts['former_close_listed_as_other_method']}")
    return {"counts": counts, "checks": checks, "lists": list_counts, "readmitted_rows": readmitted_rows}


def failures(result: dict) -> list:
    """The reasons a catalogue must not be written: each must-be-zero count that is not zero, by
    name, then each failed check."""
    return [f"{name}: {result['counts'][name]}" for name in MUST_BE_ZERO if result["counts"][name]] \
        + list(result["checks"])
