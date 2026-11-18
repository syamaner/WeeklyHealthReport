# Accepted estimates: the four private input formats

`apply_estimates.py` reads these from `<workspace>/work/`. They are private: they never enter this
repository, an issue, a PR or a commit, and every example below is synthetic. The rules are in
[estimates on catalogue v2](../../../docs/personal-food-catalogue-estimates-v2-proposal.md) and its
[phase gate](../../../docs/personal-food-catalogue-estimates-v2-phase.md), section 3.2.

All four are **canonical JSON**: UTF-8 with no byte-order mark, object keys sorted, no spaces, no
repeated keys, no `NaN` or `Infinity`, and exactly one trailing newline. In Python that is
`json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode() + b"\n"`
(`estimates_input.canonical`). Keys are exact, vocabularies are closed, and a file that is not in
this form is refused whole, with a message that names no food and no value. A new field is a new
schema version.

| File | Schema | Needed |
|---|---|---|
| `work/accepted-estimates.json` | `pfc-accepted-estimates-v1` | absent means there is nothing to add |
| `work/estimate-refusals.json` | `pfc-estimate-refusals-v1` | optional; absent refuses nothing |
| `work/estimate-readmissions.json` | `pfc-estimate-readmissions-v1` | optional; absent re-admits nothing |
| `work/estimate-readmission-sheet.json` | `pfc-estimate-readmission-sheet-v1` | optional; absent re-admits nothing |

The examples are indented for reading; the files themselves are canonical.

## 1. `pfc-accepted-estimates-v1`

Top level, exactly: `schema`, `catalogue_release_id`, `rows`.

- `catalogue_release_id` is the `pfc:sha256:` ID of the plain v2 file the rows were accepted
  against (`export_v1.py` and `apply_estimates.py` print it). A mismatch refuses the run, so rows are
  never applied to a catalogue the owner did not review.
- `rows` are in ascending (`entry_id`, `nutrient`) order, a whole-entry row first, each pair once.

Each row:

| Field | Meaning |
|---|---|
| `entry_id` | the entry's `pfc:` ID in the plain v2 file |
| `scope` | `entry` (national composition only: one estimate for each nutrient the record quantifies) or `nutrient` |
| `nutrient` | `nutrient` scope only: the inventory key |
| `value`, `unit` | page rows only (`manufacturer_page`, `aggregator`): the value on the entry's own basis, in the key's canonical unit. **A national composition row never carries them**: the value is read from the app's bundled record, so a typed value cannot stand in |
| `evidence` | the contract's evidence record (estimates v1 section 2.2) without `id`, `entry_id` and `nutrient`, with `quality` (`high`, `medium`, `low`) |
| `underlying_source` | `not_applicable` for every source that is not an aggregator; for an aggregator `stated_independent`, `open_food_facts` or `not_stated` |
| `relation` | `same_food` or `similar_food`; `similar_food` exactly when `method` is `carried_from_similar_food` |
| `accepted` | `{sheet, row}`: the review sheet and the row number that carry the owner's accept mark and the tier shown there |

A national composition row is never `derived`. A whole-entry row skips a key the entry already has
on its label and a key that a `nutrient` row of the same entry names, so a more specific row always
wins.

```json
{
  "schema": "pfc-accepted-estimates-v1",
  "catalogue_release_id": "pfc:sha256:0000000000000000000000000000000000000000000000000000000000000000",
  "rows": [
    {
      "entry_id": "pfc:0123456789ab",
      "scope": "entry",
      "evidence": {
        "approved_as_estimate": true, "source_type": "national_composition",
        "composition_source": "cofid", "source_reference": "cofid:synthetic:row:0001",
        "page_access": null, "source_digest": null, "retrieved_on": null,
        "source_state": "canned, drained", "target_state": "canned, drained",
        "state_basis": "source_states_it", "method": "carried_from_same_food",
        "assumption": "Synthetic Tinned Fish is the food this record describes.",
        "derivation": null, "quality": "high"
      },
      "underlying_source": "not_applicable",
      "relation": "same_food",
      "accepted": {"sheet": "Synthetic sheet A", "row": 12}
    },
    {
      "entry_id": "pfc:0123456789ab",
      "scope": "nutrient",
      "nutrient": "fiber",
      "value": 1.2,
      "unit": "g",
      "evidence": {
        "approved_as_estimate": true, "source_type": "manufacturer_page",
        "composition_source": null, "source_reference": "https://example.invalid/synthetic-tinned-fish",
        "page_access": "direct_read", "source_digest": null, "retrieved_on": "2026-11-16",
        "source_state": "as sold", "target_state": "as sold",
        "state_basis": "source_states_it", "method": "direct",
        "assumption": "The page describes the food as sold by Example Brand.",
        "derivation": null, "quality": "medium"
      },
      "underlying_source": "not_applicable",
      "relation": "same_food",
      "accepted": {"sheet": "Synthetic sheet C", "row": 4}
    }
  ]
}
```

### Admission

Each estimate is admitted or withheld; the first reason wins, each is counted and none stops the
run: `label_kept`, `merged_kept`, `composite`, `open_food_facts_source`, `refused_source`,
`readmission_class`, `unquantified`, `basis`, `fortified_record`, `state_contradiction`, `transform`,
`codec` (`merged_kept` only where the app merges that record: a raw or cooked entry per 100 g and a
record of the same preparation, per 100 g and not fortified; with the codec's own code, for
example `estimate-own-held`, in the counts). `basis` is a national composition estimate on an entry
that is not per 100 g, or from a record that is not; no density is ever inferred.

## 2. `pfc-estimate-refusals-v1`

Required whenever `accepted-estimates.json` exists: E3 refusals bind by default, so the writer
stops when this file is missing. A file with no rows records a completed check that found nothing
to refuse.

What the E3 disposition refused, carried to v2 entry IDs. Top level: `schema` and `rows`, with two
optional lists.

- `rows`: `{entry_id, source_type, source_reference, refusal_class}` with an optional `nutrient`.
  Without `nutrient` the row refuses every nutrient of that source for that entry. Ascending by
  (`entry_id`, `source_type`, `source_reference`, `nutrient`, `refusal_class`).
- `refusal_class`, closed. Re-admissible: `stratum_consequence`, `removal_mechanics`. Never
  re-admissible: `open_food_facts`, `unresolved_a1`, `per_entry_exclusion` (wrong identity,
  incompatible state or variety mismatch), `value_fault` (its own wrong basis, transcription or
  derivation), `no_truthful_source_type` (a recipe estimate, a prior release, a transform outside
  the closed list).
- `former_close_references` (optional): `{entry_id, composition_source, record_id}` for a record
  that was once the entry's close reference. A same-food estimate that cites one is counted, and
  that count must be zero. Ascending, each once.
- `no_e3_counterpart` (optional): entry IDs with no counterpart in the pinned evaluation release,
  ascending. Estimates on them are reported as a number, so the limit of the refusal rule stays
  visible.

```json
{
  "schema": "pfc-estimate-refusals-v1",
  "rows": [
    {"entry_id": "pfc:0123456789ab", "refusal_class": "stratum_consequence",
     "source_reference": "usda-synthetic:fdc:1", "source_type": "national_composition"}
  ],
  "former_close_references": [
    {"composition_source": "cofid", "entry_id": "pfc:0123456789ab", "record_id": "cofid:synthetic:row:0002"}
  ],
  "no_e3_counterpart": ["pfc:ba9876543210"]
}
```

## 3. `pfc-estimate-readmissions-v1`

The owner's re-admission list. Top level: `schema`, `rows`. One row is one value:
`{entry_id, nutrient, source_type, source_reference, method, corpus_sha256, date}`, ascending by the
first five fields, each once. `corpus_sha256` is the corpus hash the value was approved against: a
row covers that value only, never a later value of the same record.

```json
{
  "schema": "pfc-estimate-readmissions-v1",
  "rows": [
    {"corpus_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
     "date": "2026-11-16", "entry_id": "pfc:0123456789ab", "method": "carried_from_similar_food",
     "nutrient": "iron", "source_reference": "usda-synthetic:fdc:1", "source_type": "national_composition"}
  ]
}
```

## 4. `pfc-estimate-readmission-sheet-v1`

The re-admission sheet the list is derived from. Top level: `schema`, `rows`. Each row has the list
row's seven fields plus `refusal_class` (the closed list above), `reason` (plain text, at most 500
characters) and `accept`: `accepted`, `not_accepted` or `withdrawn`. One row per value.

```json
{
  "schema": "pfc-estimate-readmission-sheet-v1",
  "rows": [
    {"accept": "accepted",
     "corpus_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
     "date": "2026-11-16", "entry_id": "pfc:0123456789ab", "method": "carried_from_similar_food",
     "nutrient": "iron", "reason": "Withheld with its stratum; the record itself was not found wrong.",
     "refusal_class": "stratum_consequence", "source_reference": "usda-synthetic:fdc:1",
     "source_type": "national_composition"}
  ]
}
```

### When a refused source counts as re-admitted

Only when all of these hold; anything else stays refused:

- a list row and a sheet row name the same entry, nutrient, source type, source reference, method,
  corpus hash and date, and the sheet row's `accept` is `accepted` (a row that is `not_accepted` or
  `withdrawn`, or a list row with no sheet row, is refused);
- the corpus hash is the catalogue's own for that corpus;
- the source is `national_composition`, no refusal of that value has a never-re-admissible class,
  and the sheet's class is one of the refusal list's classes for it.

A re-admitted estimate's `assumption` must contain the sentence "The evaluation withheld this source
and the owner re-admitted it.", its tier is at most `medium`, and a former close reference
re-admits only as `carried_from_similar_food`. Re-admission overrides no mechanical rule: a `raw` or
`cooked` entry still cannot take its own held record (`estimate-own-held`).

## The evaluator's six counts

`estimate_counts.six_counts` reports them for the file about to be written. Four must be zero, or
nothing is written: `close_reference_as_same_food`, `refused_not_readmitted`,
`readmitted_above_medium`, `aggregator_not_stated_above_medium`. Two are numbers: `readmitted` and
`no_e3_counterpart`. The private `out/estimates-change-report.json` holds them with the admission
counts and the re-admitted rows.

## Converting the review sheets

In general terms only; the sheets and their rows are private.

- Each accepted sheet row becomes one row here, with its sheet name and row number in `accepted`. A
  row the owner did not accept becomes nothing.
- Same-food and similar-food rows from composition tables use `entry` or `nutrient` scope and carry
  no value: the builder reads it from the bundled record.
- Fibre-only rows are `nutrient`-scope rows.
- Generic records from official tables are whole-entry rows, with `relation` and `method` set from
  the match: the same food gives `same_food` and `carried_from_same_food`, a close match gives
  `similar_food` and `carried_from_similar_food`.
- Page rows carry the URL, the date read, the state the page describes and the value.

The conversion itself is a separate, owner-approved step. This change does not perform it, and no
agent accepts a row, sets a tier or re-admits a source on the owner's behalf.
