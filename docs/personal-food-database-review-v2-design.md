# Personal food database evaluation: Part A review v2 design

Status: **revision 2, design approved by the owner on 8 November 2026, with the Part A bars
`v2_proposed` (plan decision 9). No tool code, freeze entry, seal or private file changes are made by
this document; implementation is its own phase.** Issue #440, programme #424. Revision 2 answers
an architecture-gate review (section 8).

The [evaluation plan](personal-food-database-evaluation-v1.md) (revision 5, section 3.3) says the
existing `pfd-review-sheet-v1` sheet and Part A scorer cannot represent the best-estimate rubric of
section 3.1. This file describes the smallest versioned change that can, and its architecture gate.
It moves no bar: which Part A bars apply is the owner's decision (plan section 6), recorded before
any v2 scoring, and the design supports either set.

## 1. What changes and what does not

| Unchanged, byte for byte | Added |
|---|---|
| Every v1 file: `pfd_eval.py`, `formats.py`, `score_a.py`, `bars.py`, `freeze.py`, `seals.py`, `results.py`, `score_b.py`, `queries.py`, `sample.py`, `split.py`, `stats.py` and every existing test | `pfd_eval_v2.py` (the v2 entry point), `formats_v2.py`, `score_a_v2.py`, `bars_v2.py`, `results_v2.py`, `exclusions.py`, `freeze_v2.py`, `seals_v2.py`, `nutrient-inventory-v1.json` and their tests |
| `freeze-v1.json`, so the pinned v1 record and its hash check are never amended | `freeze-v2.json` (section 4) |
| The private `seals.txt`, `review/` and `review/review-sheet.csv`; the pinned release, seed, sample and purchase counts | The private `seals-v2.txt`, `review-v2/` and `exclusions-v2/` |
| Part B: query set, split, seals, `pfd-results-v1` for Part B | |

Because no v1 file changes, every v1 hash in `freeze-v1.json` keeps matching and every v1 test
passes unmodified. A v1 sheet given to the v2 scorer, or a v2 sheet given to the v1 scorer, is
refused by schema name. Existing v1 results files stay readable.

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
`freeze-v2.json` (section 4).

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
| A1, A5 | any checks with outcome `not_applicable`; the entry is **decided** when any check fails or all three pass, and **unresolved** otherwise (no failure, at least one unresolved) | any other outcome |
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
**`score-a-v2` refuses to run, and writes nothing, when `part_a_bars` is absent from
`freeze-v2.json`**, so no count is seen before the owner fixes the bars.

Counts, each entry counted at most once per measure:

- **Per stratum:** passed, failed and unresolved counts for each of identity, state and variety.
- **A1 and A5:** entries with a wrong identity, state or material variety over decided entries
  (so every failed entry is in the denominator, and the share can never exceed one);
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
| More than 6 skipped A1 entries fail both A1 bars | no v2 equivalent: v1 skips meant "no pack to hand", which the rubric removes; unresolved A1 entries follow the general rule above (`passes: null`, not final) |

Under `v2_proposed` the plan section 6 proposed table applies directly.

## 4. Seals, freeze and private folders

- **Folders.** `review/` stays as it is. `review-v2/` holds exactly two files, the v2 sheet and the
  sidecar, by exact file name. The exclusion list (section 6) is written to a third folder,
  `exclusions-v2/`, outside both sealed folders.
- **Seals (`seals_v2.py`).** v2 seals go to their own private append-only `seals-v2.txt`, in the
  same line format and never replaced, so the v1 `seals.py` never meets an unknown seal name and
  Part B's seals and held-out run log are untouched. `seal-review-v2` bundles exactly the two named
  files of `review-v2/` and refuses a third file or a link. It requires `seal-dev` and
  `seal-heldout` in `seals.txt` (read through the unchanged v1 `seals.recorded`), keeping the plan's
  seal order. The v1 `seal-review` is simply never run for this rubric; as of 8 November 2026 no
  seal of any kind has been recorded, so nothing blocks either path. `pfd_eval_v2.py` refuses to
  run `seal-review-v2` if `seals.txt` already holds a v1 `seal-review`, and the v1 `score-a` is not
  used for the v2 review.
- **Freeze (`freeze_v2.py`, `freeze-v2.json`).** A new record, format `pfd-freeze-v2`, holds the
  hashes of the v2 files and the inventory, a `freeze_v1_sha256` of the unchanged `freeze-v1.json`
  (so the v1 record and everything it pins carry forward), and the optional `part_a_bars` with the
  closed values `v1_accepted` and `v2_proposed`; a value outside the set is refused. The v2 commands
  check both records and refuse a mismatch in either. `part_a_bars` is set only in a docs commit
  recording the owner's choice, before the first `score-a-v2` run (ideally before
  `seal-review-v2`). `freeze-v1.json` is never edited.
- **Bars lock.** The first `score-a-v2` run appends a `score-a-v2` line to `seals-v2.txt` holding
  the `part_a_bars` value and the SHA-256 of `freeze-v2.json` it ran under. Every later v2 command
  compares the current `part_a_bars` with that line and refuses a difference, so the bars cannot be
  switched after counts are seen. Changing them needs a new plan revision and a fresh sample (plan
  section 6), not an edit.
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
  `results_v2` builds the allow-listed results bytes and `exclusions` the `pfd-exclusions-v1`
  bytes (pure); `seals_v2` and `freeze_v2` read and append their own records, as `seals.py` and
  `freeze.py` do in v1; `pfd_eval_v2.py` does every other file read and write and the
  private-folder checks; `pfd_eval.py` is untouched.
- **Dependency direction.** Unchanged: pure modules import nothing from file or network code;
  the entry points import them. Standard library only, run with `python3 -I`; `workspace_guard.py`
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
- Freeze: `freeze-v1.json` and every v1 file hash are unchanged; `freeze-v2.json` refuses a
  `freeze_v1_sha256` mismatch, an unknown `part_a_bars` value and a changed v2 file; `score-a-v2`
  refuses to run, writing nothing, without `part_a_bars`; after a first run, a changed
  `part_a_bars` makes every v2 command refuse.
- Seals: v2 seals are written only to `seals-v2.txt`; the v1 `seals.py` reads `seals.txt`
  unchanged afterwards; `seal-review-v2` needs `seal-dev` and `seal-heldout`, refuses when a v1
  `seal-review` exists, covers exactly its two files and refuses a third file or a link.
- Bars: `bars_v2` matches `bars.judge` on shared names; under `v1_accepted` the A1 value and A5
  bars are `not_assessable`; unresolved A1 entries give `passes: null`, never false.
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

Revision 2 answers an architecture-gate review (NEEDS WORK) of revision 1 and a local Qodo review.
As it now stands: scoring fails closed without `part_a_bars`, and the first scoring run locks it;
no v1 file or `freeze-v1.json` is edited, and v2 has its own entry point, `freeze-v2.json` and
`seals-v2.txt`, so v2 never writes to the v1 seal log; v2 sealing still depends on the v1
`seal-dev` and `seal-heldout` (plan seal order) and is refused, by design, if a v1 `seal-review`
exists; `bars_v2` has its own judge; unresolved means "not final" (`passes: null`)
everywhere, with closed fields; per-stratum combination tables define every outcome and the A1
denominator; the sidecar has `unresolved`, a full-inventory coverage rule and empty-field rules;
there is no free-text column; the sheet holds initial rows only; the exclusion list is versioned and
stored apart; results v2 carries the bars choice and not-assessable flags; round-trip tests are
listed.

## 9. For the owner

1. Approve, amend or reject this design. Approved on 8 November 2026.
2. Choose the Part A bars (`v1_accepted` or `v2_proposed`), recorded as `part_a_bars` before any
   v2 scoring. Chosen on 8 November 2026: `v2_proposed`.
3. After approval, an implementation phase (its own issue and PR) builds the tool and its tests.
   The owner then fills the v2 sheet and sidecar, using the private proposals as a starting point,
   before `seal-review-v2` and `score-a-v2`.

## 10. Implementation notes (#443)

- The v2 modules sit in `Tools/PersonalFoodDatabaseEvaluation/v2/`, not beside the v1 modules:
  the v1 freeze check refuses any `*.py` file in the tool folder that `freeze-v1.json` does not
  list, so a v2 module there would stop every v1 command. The data files and tests stay where
  section 1 places them.
- Private file names: `review-v2/review-sheet-v2.csv`, `review-v2/nutrient-evidence-v2.jsonl` and
  `exclusions-v2/exclusions.json`.
- The A1 and A5 value bar is judged on macro and micro values together, matching the single
  "assessed value evidence error" bar of plan section 6; macro and micro counts are reported
  separately for information.
- The bars lock line in `seals-v2.txt` is `score-a-v2 <freeze-v2 sha256> <part_a_bars> <UTC time>`;
  a missing `part_a_bars` after the lock counts as a change and is refused.
- `freeze_v1_sha256` pins `freeze-v1.json` in canonical form without `heldout_sha256` and
  `golden_sha256`, the two entries the plan adds later, so recording the held-out seal does not stop
  the v2 commands; any other change to the v1 record still does.
- `seal-review-v2` hashes the bundle before validating it and refuses to seal if the files changed
  in between. `compatible_with_stated_assumption` is refused on A3 rows and on A4 rows other than
  `match_missed`, which never supply values.
