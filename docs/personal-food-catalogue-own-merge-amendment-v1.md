# Personal food database: estimates from a merge record the app does not merge (G4)

Status: **accepted.** The owner decided the question of section 5 on 19 November 2026 and approved
#527, which merged on 19 November 2026. It follows the [gap estimates amendments G1 to G3](personal-food-catalogue-gap-estimates-v1-amendment.md)
and keeps their numbering.

It is a delta on [labelled estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md)
("estimates v2") and repeats none of it. Everything estimates v2, import v1 and G1 to G3 say that this
document does not name stays as written. Estimates v2 gains a dated note pointing here.

## 1. Why

Estimates v2 section 3.1 refuses, in the codec, any estimate that cites the entry's own generic
record when that reference has `role` `merge` (`estimate-own-merge`), because "the merged record
already supplies its values". That is true only when the app merges the record. The app merges only
when `PersonalFoodDatabaseCandidateBuilder.mergeEligible` holds: a raw or cooked per 100 g entry,
and a record whose preparation is known and equal to the entry's state, per 100 g with a known 100 g
edible quantity, and not fortified. When it does not hold, the entry shows none of the record's
values, and the codec also refuses the same values as labelled estimates, so the entry stays empty.

Counts only, from the owner's private catalogue on 19 November 2026 (836 entries): 704 accepted
estimates on 28 raw or cooked entries are withheld this way. In every one the record names the same
food and does not state whether it is raw or cooked. 72 of them would fill a missing energy,
protein, fat or fibre value on 24 entries. The file already admits 6,736 estimates from other
records whose preparation is not stated.

## 2. Amendment G4 (owner, 19 November 2026)

Amends estimates v2 section 3.1 (the `estimate-own-merge` codec row and the importer rules) and
section 3.3 (one ceiling). The rule is closed; changing it is a new dated amendment.

**G4a. `estimate-own-merge` moves to the importer.** The codec cannot see the record, so it no
longer raises `estimate-own-merge`. The importer does, with the record in hand: for a
`national_composition` estimate whose `composition_source` and `source_reference` name the entry's
own reference with `role` `merge`, it raises `estimate-own-merge` when the app would merge that
record into that entry (the same predicate as `mergeEligible`, on the record's facts). The merged
record still supplies those values, so an estimate from it is still refused. The importer's order
per estimate becomes `corpus-mismatch`, `record-missing`, `value-unquantified`, `value-mismatch`
(the first that fails), then `estimate-contradiction`, `estimate-basis` and `estimate-own-merge`,
each whenever the record was read. `estimate-own-merge` joins the importer-only codes.

**G4b. Otherwise it is an own same-food record.** When the app would not merge the record, the
estimate is judged as an own record in the codec, and the merge reference's match is always
`same_food_same_state` (import v1's `merge-condition`):

| Codec row | Own `candidate` reference (unchanged) | Own `merge` reference (G4) |
|---|---|---|
| `estimate-own-method` | method must agree with the match | method must be `carried_from_same_food` |
| `estimate-own-state` | `state_basis` must not be `unknown` | the same |
| `estimate-own-held` | raised for a same-food record on a raw or cooked entry | **not raised:** a merge reference was never held or demoted on purpose |
| `estimate-quality` | section 3.3 ceilings | the section 3.3 ceiling, and never above **`medium`** |

The cap at `medium` is the owner's decision: the record is the same food, but it does not say whether
it describes the raw or the cooked food, so it can never be shown as the highest tier. The cap only
lowers the existing ceiling: an `unknown` state basis still gives `low`, and is refused anyway by
`estimate-own-state`. Every other
check applies unchanged: label values first, the value checks against the record, and
`estimate-contradiction` (a stated preparation that differs, a fortified record, a record that is not
per 100 g edible).

**Which records.** A merge reference's record fails to merge when its preparation is not known, when
it differs from the entry's state, when it is not per 100 g edible, or when it is fortified. The last
three are `estimate-contradiction` for any estimate from that record, except one case: an `as_sold`
record on a `raw` entry does not merge (the kinds differ) but does not contradict either (estimates v2
section 3.2 treats `as_sold` and `raw` as compatible), so G4 admits it, at most `medium`, like a
record whose preparation is not stated.

**Defence in depth on load.** The app decodes the stored file with the codec on every load, not with
the importer. So the candidate builder also enforces the rule structurally: when it merges the
entry's record, an estimate that cites that same record never fills a key, and the merged value is
used. A stored file can therefore never show an own estimate in place of a merged value, even if a
later build's adapter read the same pinned corpus differently.

**Shown.** Such an estimate is shown like any other national estimate from the same food at its
tier. The entry's identity is unchanged, the reference stays `merge`, and no value is merged.

**Determinism.** Whether a record merges depends on the facts the app's adapter reads from the
bundled record. The file pins each corpus by hash, so a build that pins another corpus rejects the
file with `corpus-mismatch`; for the same pinned corpus, a later adapter change that made a record
merge is covered by the builder guard above.

**Compatibility and rollback.** Only a file that holds such an estimate changes outcome. A build
without this amendment rejects that file whole with `estimate-own-merge`; it never reads a value
differently. If such a file is already installed and the app is downgraded to such a build, the
build's codec refuses the stored file on load, so Your food database shows no rows until a file
without those rows is imported; it fails closed and never misreads a value. Rolling back means
rebuilding the file without those rows. No token, field, schema
version, store, food contract or egress changes.

## 3. What does not change

- Unknown is never zero; no conversion of any kind is applied.
- Raw, cooked, drained and dry stay distinct. The app still never merges a record whose preparation
  it cannot confirm, and the entry's own record is never promoted to a merge by an estimate.
- A label value always wins; where the record merges, the merged value wins over any estimate from
  it; estimates are augmented, never measured, and can be left out on Confirm.
- Every estimate is accepted by the owner, row by row, with its tier shown.
- An own `candidate` reference keeps every row of section 3.1, `estimate-own-held` included.

## 4. Architecture gate

- **Responsibilities.** The codec table (`PersonalFoodDatabaseEstimates.tableCodes` and `ceiling`,
  domain) drops the `estimate-own-merge` row, applies the method and state rows to an own merge
  reference and caps it at `medium`. The importer check (`PersonalFoodDatabaseEstimateAdmission`,
  application) raises `estimate-own-merge` with a merge predicate on `GenericRecordFacts`;
  `PersonalFoodDatabaseCandidateBuilder.mergeEligible` delegates to that same predicate, so the
  importer and the candidate builder cannot disagree about what merges. The code sets change in
  `PersonalFoodDatabaseRuleCode.importerOnly`. The skill mirrors the codec in
  `estimates_v2.table_codes` and `ceiling` (with `estimate-own-merge` moved from `RULE_CODES` to the
  end of the importer codes), and the fixtures in `test_export_check.py`. The builder in
  `estimates_input.reason` needs no new reason: an own merge estimate on a record that merges is
  already withheld as `merged_kept` (the key is quantified) or `unquantified` (it is not, so no value
  can match). `PersonalFoodDatabaseCandidateBuilder.build` gains the guard of section 2.
- **Dependency direction.** Unchanged. The importer already receives the record through the
  consumer-owned `GenericRecordNutrientLookup` port.
- **Invariants.** The merge rule itself is untouched; label first; merged value first where it
  merges; no conversion; the tier ceilings; a file is rejected whole, never read differently, by a
  build without this amendment.
- **Extension axes.** None added.
- **Contract tests.** Shared fixtures in `docs/fixtures/personal-food-database-estimates-v2/`:
  - the codec fixture `reject-own-merge` becomes an importer fixture at `medium` against a new stub
    record `cofid:example` (raw, unfortified, per 100 g edible) that merges, giving exactly
    `[estimate-own-merge]`; its bytes change;
  - importer fixtures for a record that would merge whose value fails: `[value-mismatch,
    estimate-own-merge]` and `[value-unquantified, estimate-own-merge]`;
  - importer fixtures for an own merge record that is fortified, not per 100 g edible, or cooked on a
    raw entry: `[estimate-contradiction]`, no `estimate-own-merge`;
  - codec fixtures for an own merge reference: `high` (`estimate-quality`), cited as a similar food or
    `direct` (`estimate-own-method`), an `unknown` state basis at `low` (`estimate-own-state`);
  - accept fixtures at `medium` for a raw and a cooked entry whose own merge record has no stated
    preparation, and for a raw entry whose own merge record is `as_sold`;
  - the manifest's `stub_lookup` gains records and, per record, the entry states it merges into, which
    both the Swift and the Python tests check against their own merge predicate; `importer_rule_codes`
    and `estimates_only_rule_codes` end with `estimate-own-merge`.

  App tests: the code sets agree with the manifest; the ceiling cap and its `unknown` precedence;
  `mergeEligible` and the importer agree with the manifest's merge flags; an admitted own merge
  estimate fills its key while nothing merges; with a record that merges, an own estimate on a merged
  key is not used (the guard); and the importer test that a codec rejection keeps the active release
  uses another codec fixture. Skill tests: the ceiling, and the builder admitting an own merge row
  when the record does not merge and withholding it when it does. Every other existing golden and
  accept fixture keeps its bytes and codes.

## 5. Decisions
| # | Question | Decision |
|---|---|---|
| G4 | What tier may an estimate from an own merge record the app does not merge take? | `carried_from_same_food`, at most `medium`, with the state basis stated. **Owner, 19 November 2026** ("Medium, same food"). |
