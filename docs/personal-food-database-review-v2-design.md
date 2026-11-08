# Personal food database evaluation: Part A review v2 design

Status: **design proposal, revision 2, 8 November 2026, awaiting owner approval. No tool code,
freeze entry, seal or private file changes until the owner approves or amends it.** Issue #440,
programme #424. Revision 2 answers an architecture-gate review (section 8).

The [evaluation plan](personal-food-database-evaluation-v1.md) (revision 5, section 3.3) says the
existing `pfd-review-sheet-v1` sheet and Part A scorer cannot represent the best-estimate rubric of
section 3.1. This file describes the smallest versioned change that can, and its architecture gate.
It moves no bar: which Part A bars apply is the owner's decision (plan section 6), recorded before
any v2 scoring, and the design supports either set.

## 1. What changes and what does not

| Unchanged | Changed, re-hashed in the implementation commit | Added |
|---|---|---|
| `score_a.py`, `bars.py`, `formats.py` v1 parsers, `score_b.py`, `queries.py`, `sample.py`, `split.py`, `stats.py` and every existing test | `freeze.py` (one optional key), `seals.py` (one seal name and exact-file bundles), `pfd_eval.py` (new commands) | `formats_v2.py`, `score_a_v2.py`, `bars_v2.py`, `results_v2.py`, `exclusions.py`, `nutrient-inventory-v1.json` and their tests |
| `review/review-sheet.csv` byte for byte; the pinned release, seed, sample and purchase counts | | |
| Part B: query set, split, seals, `pfd-results-v1` for Part B | | |

The claim is that **v1 scoring semantics are unchanged**, shown by every existing v1 test passing
unmodified; it is not that every file keeps its hash. A v1 sheet given to the v2 scorer, or a v2
sheet given to the v1 scorer, is refused by schema name. Existing v1 results files stay readable.

## 2. Files

### 2.1 Declared inventory, `pfd-nutrient-inventory-v1`

A committed JSON data file in the tool folder, not private, listing canonical `NutritionExport` keys
in three closed groups, 39 keys in all:

- **macro (8):** `energy_consumed`, `protein`, `fat_total`, `fat_saturated`, `carbohydrates`,
  `sugar`, `fiber`, `sodium` (the v1 eight, so A1 macro results stay comparable);
- **micro (26):** the 13 vitamins, the 7 minerals other than sodium and the 6 ultratrace minerals;
- **other (5, informational):** `water`, `cholesterol`, `fat_monounsaturated`,
  `fat_polyunsaturated`, `caffeine`. These get coverage counts but never enter an error denominator.

The grouping is explicit in the file, not derived from the app's categories (the app files sodium
under minerals). A contract test reads the `.init(key: "…"` lines of `NutritionExport.swift` with a
fixed pattern and checks the file lists exactly those 39 keys, so the inventory cannot drift. Salt
is not a key: a salt value is evidence for `sodium` with method `derived`. The file's SHA-256 is in
the Freeze list `files` (section 4).

### 2.2 Review sheet, `pfd-review-sheet-v2`

Private CSV in the folder `review-v2/` (never `review/`, see section 4), generated empty by a new
`review-sheet-v2` command from the pinned sample. It holds **exactly `sample["entries"]`**, the 158
initial rows in sample order; `reason` is `census`, `top30` or `draw`, and a `replacement` row is
refused. Columns:

`schema, row, stratum, reason, entry_id, identity, state, variety, outcome`

Every cell must hold a token from its closed set; **a blank cell is refused**, never read as
unresolved. Tokens:

- `identity`: `same_food`, `different_food`, `unresolved`.
- `state`: `same_state`, `compatible_with_stated_assumption`, `different_state`, `unresolved`.
  `compatible_with_stated_assumption` counts as a state pass only when the row's sidecar records for
  the values it supplies carry `state_basis` `stated_assumption`; otherwise the row is refused.
- `variety`: `same_or_immaterial`, `material_difference`, `unresolved`.
- `outcome`: per stratum, below. For A1 and A5 the outcome is `not_applicable`.

Precedence for counting an entry: **fail beats unresolved, unresolved beats pass**. A check passes
when identity is `same_food`, state is `same_state` or a supported
`compatible_with_stated_assumption`, and variety is `same_or_immaterial`.

| Stratum | Allowed combinations | Refused |
|---|---|---|
| A1, A5 | any checks with outcome `not_applicable`; the entry is **checked** when no check is `unresolved` | any other outcome |
| A2 | `merge_ok` only when all three checks pass; `merge_failed` when at least one check fails (other checks may be unresolved); `unresolved` when no check fails and at least one is unresolved | `merge_ok` with a failing or unresolved check; `merge_failed` with no failing check |
| A3 | `sensible` when the candidate's relationship is accurately represented: identity `same_food`, or a labelled alternative state (`different_state`) or variety (`material_difference`) that never supplies target-state values; `misleading_other_state` when state is `different_state` and it is represented as equivalent; `misleading_close` for a misleading identity or variety; `unresolved` when any check is `unresolved` and nothing is misleading | `sensible` with identity `different_food`; `misleading_other_state` without `different_state` |
| A4 | `match_missed` only with all three checks passing for the named record, plus a sidecar record of `assessment` `match_available`; `nothing_suitable` with all three checks `unresolved` (there is no record to check) after the documented search; `unresolved` otherwise | `match_missed` without its sidecar record; `nothing_suitable` with any check other than `unresolved` |

The sheet holds tokens, row numbers and entry IDs only; there is no free-text column.

### 2.3 Evidence sidecar, `pfd-nutrient-evidence-v2`

Private JSON Lines in `review-v2/`, one record per row and inventory key:

`schema, row, nutrient, assessment, source_kind, state_basis, method`

- **Coverage rule.** Every A1, A2 and A5 row carries exactly one record for **every** inventory
  key; a missing key or a duplicate is refused, so an omitted key can never shrink a denominator.
  A4 rows carry one record (key `energy_consumed`) only when the outcome is `match_missed`. A3 rows
  carry none: candidates never supply target-state values.
- `assessment`: `correct`, `error_basis`, `error_state`, `error_transcription`, `error_derivation`,
  `error_source`, `unresolved`, `missing`, `missing_source_available`, `present_unquantified`
  (traces and "N" values), `candidate_only`, `match_available` (A4 only).
  Identity is judged once per entry on the sheet, not per value, so there is no value-level
  identity token and nothing is double-counted.
- For `missing`, `missing_source_available`, `present_unquantified`, `candidate_only` and
  `unresolved`, the fields `source_kind`, `state_basis` and `method` are empty; otherwise each
  holds a token:
  - `source_kind`: `pinned_release`, `national_composition`, `manufacturer_page`, `aggregator`,
    `owner_declaration`;
  - `state_basis`: `source_states_it`, `stated_assumption`, `unknown`;
  - `method`: `direct`, `derived`, `carried_from_same_food`, `carried_from_similar_food`.
- No other field is allowed, and every field is a string. The sidecar carries **no values, titles,
  URLs or record identifiers**: those stay in the existing private proposal files, which the scorer
  never reads. Source disagreement alone is not an error token (plan section 3.4).

## 3. Scoring (`score_a_v2.py`, pure)

Inputs: the sealed sample, the v2 sheet, the sidecar, the inventory and the `part_a_bars` choice.
**`score-a-v2` refuses to run, and writes nothing, when `part_a_bars` is absent from the Freeze
list**, so no count is seen before the owner fixes the bars.

Counts, each entry counted at most once per measure:

- **Per stratum:** checked, failed and unresolved entries for identity, state and variety.
- **A1 and A5:** entries with a wrong identity, state or material variety over checked entries;
  assessed value evidence errors (any `error_*`) over assessed values (`correct` plus `error_*`),
  macro and micro denominators separate. `unresolved`, `missing`, `missing_source_available`,
  `present_unquantified` and `candidate_only` never enter a denominator and are counted on their own.
- **A2:** `merge_failed` entries over A2 entries without `unresolved` outcome; A2 assessed value
  evidence errors (informational).
- **A3:** `misleading_other_state` first, then `misleading_close`, each entry at most once.
- **A4:** `match_missed` and `nothing_suitable`; `unresolved` counted separately.
- **Coverage (informational):** per row, macro, micro and other keys assessed `correct`; a complete
  micro row means all 26 keys. `missing_source_available` gives the "a suitable source could supply
  it" count of plan section 3.4.
- **Exposure:** values whose state rests on a stated assumption, and values with unknown source
  state.

**Unresolved and bars.** A measure's result carries `passes: null` and a closed
`<measure>_unresolved` count whenever its stratum has an unresolved entry or value: the result is
"not final", and no section 6 export consequence fires. A stratum with unresolved items never
passes and never fails until they are resolved. Unresolved rows are never replaced: the owner's
judgement, not the row, is missing.

**Mapping under `v1_accepted`.**

| Accepted bar | v2 count used |
|---|---|
| A1 wrong product or wrong variant | A1 entries failing identity or variety; a state failure is reported beside it and counted under it, since a wrong state is a wrong product for the eaten food |
| A1 nutrient disagreement, A5 owner label value disagrees with the pack | not assessable under this rubric (no pack); reported as `not_assessable`, never as a pass |
| A2 different food or other state | `merge_failed`, including `material_difference` |
| A3 misleading, A4 match missed | unchanged meaning |
| More than 6 skipped A1 entries fail both A1 bars | replaced by: more than 6 unresolved A1 entries gives `passes: false` for the A1 entry bar (fail closed, as v1) |

Under `v2_proposed` the plan section 6 proposed table applies directly.

## 4. Seals, freeze and private folders

- **Folders.** `review/` stays as it is. `review-v2/` holds exactly two files, the v2 sheet and the
  sidecar, by exact file name. The exclusion list (section 6) is written to a third folder,
  `exclusions-v2/`, outside both sealed folders.
- **Seals (`seals.py`).** `FOLDERS` gains an exact file-name list per seal instead of one suffix;
  `seal-review-v2` bundles exactly the two named files and refuses a third file or a link. `ORDER`
  becomes `seal-dev`, `seal-heldout`, then **one of** `seal-review` or `seal-review-v2`: the two are
  mutually exclusive, each needs `seal-heldout` first, and `recorded()` accepts either name, so Part
  B's `require("seal-heldout")` and the held-out run log keep working with a v2 seal present. A
  seal is never replaced.
- **Freeze (`freeze.py`).** `part_a_bars` becomes an **optional** key with the closed values
  `v1_accepted` and `v2_proposed`; the existing `freeze-v1.json` without it still loads unchanged,
  and a value outside the set is refused. It is set only in a docs commit recording the owner's
  choice, before the first `score-a-v2` run (ideally before `seal-review-v2`). The new and changed
  files are added to `files` in the implementation commit.
- **Bars (`bars_v2.py`).** Its own table and judge, holding `v1_accepted` and `v2_proposed`; a test
  shows it gives the same allowed counts and verdicts as `bars.judge` for the names both share.

## 5. Results, `pfd-results-v2` (`results_v2.py`)

A new writer; `results.py` is not edited. The same allow-list design as `pfd-results-v1`: closed
field names, whole-number counts, intervals, `passes` true, false or null, and the release ID; any
other key or string is refused by the same string scan. It adds the v2 Part A field names, a
`part_a_bars` field holding one of its two tokens, boolean `<measure>_not_assessable` flags and the
`<measure>_unresolved` counts. Part B keeps writing `pfd-results-v1`.

## 6. Architecture gate

- **Responsibilities.** `formats_v2` parses and validates bytes (pure); `score_a_v2` counts and
  builds the exclusion list as data (pure); `bars_v2` holds bars as data with its own judge;
  `results_v2` writes the allow-listed results; `exclusions` defines `pfd-exclusions-v1`;
  `pfd_eval.py` is the only module doing file input and output, private-folder checks and seals.
- **Dependency direction.** Unchanged: pure modules import nothing from file or network code;
  `pfd_eval.py` imports them. Standard library only, run with `python3 -I`; `workspace_guard.py`
  stays the single private-folder guard.
- **Invariants.** Unknown is never zero; unresolved is never a pass and never a fail; every token is
  closed and versioned; a blank is refused; error messages name rows and columns, never values; the
  scored bundle holds tokens, row numbers and entry IDs only; results are counts only; nothing
  writes to the pinned release, the v1 sheet or `review/`.
- **Exclusions.** `pfd-exclusions-v1` (private, `exclusions-v2/`) lists, by entry ID and inventory
  key, what the later export phase withholds: every value and reference of an entry failing
  identity, merged state or material variety in any stratum; every value assessed `error_*`, even
  when its stratum is within its bar; and every reference left unresolved, which stays a candidate.
- **Extension axes.** A new inventory version or token set is a new schema version, not an edit.
  Bars are data, so an owner decision changes a freeze entry, not code.
- **CI.** If the tool cites this file, it is added to `CODE_READ_DOCS` in
  `.github/scripts/ci_changes.py` in the implementation commit.

## 7. Contract tests (synthetic only)

- Every existing v1 test passes unmodified; v1 and v2 sheets are each refused by the other scorer.
- Freeze: `freeze-v1.json` without `part_a_bars` loads; an unknown value is refused; `score-a-v2`
  refuses to run, writing nothing, without it.
- Seals: with `seal-review-v2` recorded, `require("seal-heldout")` and the held-out run log still
  work; `seal-review` and `seal-review-v2` are mutually exclusive; `seal-review-v2` covers exactly
  its two files and refuses a third file or a link.
- Bars: `bars_v2` matches `bars.judge` on shared names; under `v1_accepted` the A1 value and A5
  bars are `not_assessable`; more than 6 unresolved A1 entries fails the A1 entry bar.
- Sheet: each refused combination in the section 2.2 table is refused; a blank cell, an unknown
  token, an out-of-order row and a replacement row are refused; precedence (fail over unresolved
  over pass, A3 other-state first, one count per entry).
- Sidecar: a missing or duplicate inventory key is refused; a record for a row or stratum outside
  the coverage rule is refused; extra fields (value, URL, title) and non-string types are refused;
  empty source fields are enforced for the non-assessed tokens.
- Denominators: `unresolved`, `missing`, `missing_source_available`, `present_unquantified` and
  `candidate_only` never enter one; a declared zero assessed `correct` counts; "other" keys never
  enter an error denominator.
- Unresolved: counted, `passes: null`, no export consequence, never replaced.
- Coverage: counts `correct` only; 25 of 26 micro keys is not complete.
- Inventory: equals the 39 `NutritionExport` keys under the explicit grouping 8, 26 and 5.
- Results v2: refuses unknown keys and strings; accepts the closed bars and not-assessable fields.
- Exclusions: the format is versioned and round-trips; per-entry and per-value exclusions apply in
  every stratum, including a value-level error within a passing bar.
- Round-trips: the v2 sheet, sidecar, inventory, `pfd-results-v2`, `pfd-exclusions-v1` and
  `freeze-v1.json` with and without `part_a_bars` decode and re-encode unchanged; an existing v1
  results file still parses.

## 8. Review record

Revision 2 answers an architecture-gate review (NEEDS WORK) of revision 1: scoring now fails closed
without `part_a_bars`; `freeze.py` and `seals.py` are named as changed, with an optional freeze key,
mutually exclusive review seals and exact-file bundles; `bars_v2` has its own judge; unresolved
means "not final" with closed fields; per-stratum combination tables replace the loose rules; the
sidecar gains `unresolved`, a full-inventory coverage rule and empty-field rules; `note_ref` is
removed; the sheet holds initial rows only; the exclusion list is versioned and stored apart;
results v2 carries the bars choice and not-assessable flags; round-trip tests are listed.

## 9. For the owner

1. Approve, amend or reject this design.
2. Choose the Part A bars (`v1_accepted` or `v2_proposed`), recorded as `part_a_bars` before any
   v2 scoring.
3. After approval, an implementation phase (its own issue and PR) builds the tool and its tests.
   The owner then fills the v2 sheet and sidecar, using the private proposals as a starting point,
   before `seal-review-v2` and `score-a-v2`.
