# Personal food database: gap estimates amendments (G1 to G3)

Status: **proposed for the owner's approval in #524.** The owner decided the three questions of
section 5 on 19 November 2026; this text becomes binding when the owner approves the PR, and no
value it admits is written before then. Written at the owner's request: "the best available
labelled estimate for every food. Nothing is deleted."

It is a delta on four accepted documents and repeats none of them:
[import v1](personal-food-catalogue-import-v1.md),
[labelled estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md) ("estimates
v2"), [label photo estimates](personal-food-catalogue-off-estimates-v1-proposal.md) ("label photo")
and the [E3 disposition](personal-food-database-e3-disposition.md). Everything they say that this
document does not name stays as written. Each amended document gains a dated note pointing here.

## 1. Why

Counts only, from the owner's private catalogue on 19 November 2026 (836 entries). Applying the
app's own merge rule (only a raw or cooked per 100 g entry merges a record of the same preparation),
275 entries lack at least one of energy, protein, fat and fibre; fibre is missing on 258. Three
closed rules hold back values that a careful estimate could supply:

1. **Composite dishes.** 54 of the 275 are packaged composite dishes, 36 of them with none of the
   four. Estimates v2 section 4 keeps a composite entry free of any national composition estimate
   ("another recipe is never borrowed"), a builder rule with an evaluator count.
2. **Per 100 ml.** The codec refuses every national composition estimate on an entry that is not per
   100 g (`estimate-basis`), even from a record that is itself per 100 ml. On 18 November the writer
   withheld 318 values for this reason. Wine and spirit entries with no label are filed per 100 g
   (import v1, `basis`), so the per 100 ml wine and spirit records of CoFID cannot fill them either.
3. **No repeat.** Label photo section 2.5 refuses a photo estimate for any entry, nutrient or barcode
   that has an E3 refusal row of four classes. Every one of the 385 rows of class `open_food_facts`
   names a nutrient that already has a value on the entry, so the entry and nutrient match blocks
   nothing; the barcode match does. Of the 275 gap entries, 14 carry their own Open Food Facts
   barcode with a refusal row: 9 only of class `open_food_facts` (all missing fibre), 1 of
   `open_food_facts` and `unresolved_a1`, and 4 of other classes. Outside the gap list, 42 more
   entries' barcodes are blocked for nutrients such as the fat breakdown. The count label photo
   section 2.5 asked for: on 18 November, 0 of the 40 approved photo values were blocked and 18 of
   35 own-barcode fibre candidates were.

## 2. Amendments

Every rule below is closed; changing one is a new dated amendment.

### G1. Generic dish records for composite dishes (owner, 19 November 2026)

Amends estimates v2 section 4 ("Composite entries get no national-composition estimate from another
recipe"), and the reading of import v1 decision 4 that it and estimates v1 section 3.2 (why
`recipe_estimate` is not a v1 source type) rest on: decision 4 now forbids another brand's
**label** for a composite dish, in the working catalogue or the file, and no longer forbids a
national table's generic dish record admitted under this section. `recipe_estimate` stays out of
the closed source-type list.

A `national_composition` estimate on an entry whose `product_type` is `packaged_composite` is
admitted only when all of these hold; otherwise the builder withholds it as `composite`, as today:

- `quality` is `low` (shown "Estimated from a similar food, rough"), never `medium` or `high`;
- `method` is `carried_from_similar_food`;
- `assumption` contains the fixed sentence **"A generic recipe, not this product's."**;
- the record is a record of the same kind of dish (a builder and owner obligation: the owner accepts
  each row on a review sheet, as estimates v2 section 3.3 requires);
- every other rule applies unchanged: label values first, the merged record first where the app
  merges, state contradiction, basis, fortification and the value checks.

**The codec enforces the tier.** Estimates v2 section 3.3 gains one ceiling: a `national_composition`
estimate on a `packaged_composite` entry is at most `low` (`estimate-quality`). This only tightens:
no earlier file holds such an estimate, because the builder withheld every one. The fixed sentence
is free text and stays a builder rule, with two must-be-zero builder counts: composite estimates
above `low`, and composite estimates without the fixed sentence.

### G2. Per 100 ml entries (owner, 19 November 2026)

Amends estimates v2 section 3.1 (the `estimate-basis` codec row and the third contradiction
bullet) and the import v1 `basis` row.

**G2a. A zero needs no density.** A `national_composition` estimate of exactly `0` from a per 100 g
record that quantifies that nutrient as exactly `0` may fill a per 100 ml entry. No conversion is
applied: zero grams in 100 g of a food means zero in any amount of it. Any non-zero value from a per
100 g record still never fills a per 100 ml entry. A trace, "N" or bound is unquantified and stays
unknown, as today.

**G2b. A per 100 ml record fills a per 100 ml entry.** A `national_composition` estimate from a
record whose serving basis is per 100 ml may fill a per 100 ml entry, with no conversion. A per 100
ml record never fills a per 100 g entry (unchanged).

**G2c. Basis from an owner decision.** The import v1 `basis` row ("An entry with no label values uses
`per_100_g`") gains one exception: an entry with no label values is filed `per_100_ml_as_labelled`
when the owner has recorded that basis for it in the private basis decisions list
(`work/basis-decisions.json`). This is evidence from the owner, as a confirmed label is; the
category never sets a basis. The token keeps its name, and its meaning for such an entry is "values
per 100 ml".

- **Format** `pfc-basis-decisions-v1`: `{"schema": "pfc-basis-decisions-v1", "rows": [...]}`, each
  row exactly `entry_id`, `basis` (only `per_100_ml`) and `date` (`YYYY-MM-DD`), at most one row per
  entry. Any other shape stops the build.
- **Precedence.** A label value of any kind (the owner's, or the item's own product record) sets the
  basis as today, and a decision on such an entry is ignored and counted. A decision is also refused
  and counted when the entry's reference would merge in the app (a raw or cooked entry with a record
  of the same preparation), so no merged value is lost. A row naming no entry is counted and ignored.
- **Shown.** Such an entry's source line reads "Your food database entry · per 100 mL", not
  "per 100 mL as labelled", because it has no label.

**Where the rule moves.** The codec cannot see the record, so it no longer raises `estimate-basis`.
The importer does, with the record in hand, in place of the third contradiction bullet for per 100
ml entries. The importer's order per estimate becomes `corpus-mismatch`, `record-missing`,
`value-unquantified`, `value-mismatch` (the first that fails), then `estimate-contradiction` and
`estimate-basis`, each whenever the record was read. `estimate-basis` joins the importer-only codes.
The basis outcome is:

| Entry basis | Record | Result |
|---|---|---|
| `per_100_g` | per 100 g with a known 100 g edible quantity | admitted (unchanged) |
| `per_100_g` | anything else | `estimate-contradiction` (unchanged) |
| `per_100_ml_as_labelled` | per 100 ml with a known 100 ml quantity | admitted (G2b) |
| `per_100_ml_as_labelled` | per 100 g with a known 100 g edible quantity, the record's value exactly `0` and the file's value exactly `0` | admitted (G2a) |
| `per_100_ml_as_labelled` | anything else | `estimate-basis` |

The fortified and preparation bullets apply to every entry, as today. A per 100 ml entry never
merges its record (unchanged), so the own-merge row cannot apply to one.

**Stored source basis.** An approved estimate's stored source value carries the entry's basis, as
today (`SourceExactNutrientValue`). For G2b that is the record's basis too. For G2a the stored value
is `0` per 100 ml, which is exactly true; the record's own basis stays readable through the evidence
record's `source_reference`. No stored content changes shape.

**Compatibility.** No token, field or schema changes. A build without this amendment rejects such a
file whole with `estimate-basis` on import; if such a file is already installed and the app is
rolled back, the earlier build's codec refuses it and the database is not shown, which fails closed
and never reads a value differently. Stored records and capture manifests are unchanged, and
Confirm's rule that no estimate survives a basis change stands.

### G3. Label photo re-admission over an `open_food_facts` refusal (owner, 18 November 2026)

Amends label photo section 2.5 as its "Owner direction, 18 November 2026" paragraph foresaw.

For `product_dataset_photo` estimates only, refusal rows of class `open_food_facts` no longer
refuse, by entry and nutrient or by barcode. A barcode or entry and nutrient with any row of class
`per_entry_exclusion`, `value_fault` or `unresolved_a1` stays refused, whatever else it has.

The photo estimate still meets every rule of label photo sections 2.1 to 2.4, and no stricter one
(owner, 19 November 2026, choosing the same rules as any photo): the photo was read by eye and its
SHA-256 kept, its basis column printed, its state read (`source_states_it`) or, for a pack sold ready
to eat, stated and confirmed on the row (`stated_assumption`), the state matching the entry, the
relation rules of section 2.3 (own barcode `same_food`, another barcode of the same product
`similar_food`), the owner accepting the row with its tier shown, and the tier at most `medium`,
which the codec enforces. A1's errors were state errors; the review sheet shows the state basis of
every such row so the owner sees which ones rest on a ready-to-eat assumption.

What does not change: the E3 disposition D1 and D3, and the A1 consequence. Open Food Facts typed
values stay dropped from R1 and are never brought back; a photo read is a new value with its own
evidence. Nothing here changes R1, its release ID, its seals or its results, and these estimates are
never described as evaluated.

The evaluator's count 3 of label photo section 2.5 becomes "photo estimates matching a refusal row
of class `per_entry_exclusion`, `value_fault` or `unresolved_a1`, **must be zero**", and it reports
one new count: photo estimates admitted over an `open_food_facts` refusal row. The app needs no
change: the refusal list is private and the builder applies it.

## 3. What does not change

- Unknown is never zero; only a quantified zero the source prints is written. No density, kJ to
  kcal, salt to sodium, serving or cooking conversion is applied.
- Raw, cooked, drained and dry stay distinct; the state rules of estimates v2 and label photo stand.
- A label value always wins and is never shadowed; estimates are augmented, never measured, and can
  be left out on Confirm.
- Every estimate is accepted by the owner, row by row, with its tier shown.
- No new egress, network call, token, schema version, store or food contract.

## 4. Architecture gate

- **Responsibilities.** G1's sentence and G3 are builder rules in the skill (`estimates_input.reason`,
  `estimate_counts.Lists.status`, `six_counts` and the evaluator counts). G1's ceiling and G2 change
  the pure codec table (`PersonalFoodDatabaseEstimates.tableCodes` and `ceiling`, domain), the code
  sets (`PersonalFoodDatabaseRuleCode.importerOnly`) and the importer check
  (`PersonalFoodDatabaseEstimateAdmission`, application, with a named per 100 ml predicate on
  `GenericRecordFacts` beside `isPer100GramsEdible`), and the skill's mirrors
  (`estimates_v2.table_codes` and `ceiling`, `estimates_input.reason`, whose record facts gain the
  record's basis, and `test_export_check.py`). G2c is read by the skill's build (`export_v1`). The
  only presentation change is G2c's source line in `PersonalFoodDatabaseCandidateBuilder`.
- **Dependency direction.** Unchanged. The importer check already receives the record through the
  consumer-owned `GenericRecordNutrientLookup` port; it gains no dependency.
- **Invariants.** Unknown is never zero; label first; no conversion; state and fortification rules;
  the tier ceilings; a file is rejected whole, never read differently, by a build without this
  amendment.
- **Extension axes.** None added. The basis table is closed.
- **Contract tests.** Shared fixtures in `docs/fixtures/personal-food-database-estimates-v2/`: the two
  codec `estimate-basis` fixtures move to the importer stage with a stub per 100 g record; new
  importer fixtures for a per 100 ml record accepted, a quantified zero accepted, a non-zero per 100 g
  value refused (`estimate-basis`), a zero file value against a non-zero per 100 g record refused
  (`value-mismatch`, `estimate-basis`) and a per 100 ml record on a per 100 g entry refused
  (`estimate-contradiction`). Skill tests: composite low admitted, composite medium and composite
  without the sentence withheld, the per 100 ml cases, a photo over an `open_food_facts` row admitted
  (by entry and nutrient, by an entry-scope row and by barcode) and over each other class refused,
  alone or mixed with `open_food_facts`, the new count reported and `refused_not_readmitted` no
  longer counting those rows, and the basis decisions list (format, precedence, merge refusal,
  unknown entry). App tests: the code order with a fortified and an unquantified per 100 g record on
  a per 100 ml entry, a per 100 ml record whose quantity is not 100 ml, an own `candidate` record
  under G2a and G2b, preparation and fortification on a per 100 ml record, the code sets agreeing
  with the manifest, a composite national estimate at `medium` refused by the codec, a per 100 ml
  estimate binding on Confirm and withheld after a basis change, and the G2c source line. Every
  existing golden and accept fixture keeps its bytes and codes.

## 5. Decisions

| # | Question | Decision |
|---|---|---|
| G1 | May a generic national-table dish record fill a composite dish, tier low? | Yes, as section 2 G1 says. **Owner, 19 November 2026.** |
| G2 | How are per 100 ml gaps closed honestly? | Zero carry-over, per 100 ml records, owner basis decisions; non-zero values still per 100 ml only. **Owner, 19 November 2026.** |
| G3 | Relax the no-repeat rule for label photos, and how strict is the state rule there? | Yes, for the `open_food_facts` class only, under the same rules as any photo, tier capped at medium, each row accepted. **Owner, 18 and 19 November 2026.** |
