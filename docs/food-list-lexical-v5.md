# Food list lexical grammar v5: vague portions need an amount

Status: **Approved by the owner on 13 October 2026** through the UX review decisions (decision B3, [owner decisions comment on #140](https://github.com/syamaner/WeeklyHealthReport/issues/140#issuecomment-6137491843)). Implemented in the same PR.
Programme: [#140](https://github.com/syamaner/WeeklyHealthReport/issues/140).
Amends the parsing envelope in [food-list-import.md](food-list-import.md). New lists have used [`food-list-lexical-v6`](food-list-lexical-v6.md) (household containers, #353) since 31 October 2026; v5 is frozen as `FoodListParser.parseV5`. Introduces the grammar identifier **`food-list-lexical-v5`**; `food-list-lexical-v4` ([contract](food-list-lexical-v4.md)) and `food-list-lexical-v3` stay defined and frozen.

## Problem

Under `food-list-lexical-v4` an article or a number in front of a vague portion word is read as a definite count, because the word is neither a unit nor a household measure:

| Line | v4 parse |
|---|---|
| `a handful of almonds` | 1 count of "handful of almonds" |
| `a few strawberries` | 1 count of "few strawberries" |
| `2 pinches of salt` | 2 counts of "pinches of salt" |
| `a bit of cheese` | 1 count of "bit of cheese" |

The user never said "one". The count is shown as a proposal on the review screen and reaches Confirm as an amount, and a count of one handful is not a consumed amount the app can stand behind. A line with no article (`handful of almonds`) already has no amount under v4, but its notice says the amount is missing, which is not quite the problem.

## Goal

A vague portion word is never read as a definite count. The line keeps its food name, has no amount and no unit, and carries the existing `householdMeasure` notice ("A mug, spoon or portion needs a measured amount or an evidenced conversion."), so the existing needs-amount rule blocks saving until the user enters a measured amount. Everything else is identical to v4.

Non-goals: household conversions, new notices, new units, changes to the v4 numeral grammar, the search query grammar (`food-query-parser-v6`) or receipts (`receipt-lexical-v1`).

## Vague portion words

The list is closed. Each word names a portion of no defined size; none has a standard measure that could be converted to grams or millilitres without guessing.

| Word (and plural) | Why it is vague |
|---|---|
| `handful`, `handfuls` | Depends on the hand and the food; a handful of nuts and a handful of spinach differ several times over in weight. |
| `pinch`, `pinches` | A cooking gesture with no agreed mass; it varies with the fingers and the grain size. |
| `dash`, `dashes` | Some recipe sources give it a nominal volume, but they disagree with each other and nobody measures it in use. |
| `splash`, `splashes` | A pour with no defined volume (a splash of milk in tea). |
| `drizzle`, `drizzles` | A thin pour of oil, honey or sauce with no defined volume. |
| `bit`, `bits` | "A bit of cheese" names an unspecified amount, not one piece. |
| `few` | "A few strawberries" is an unspecified small number; reading it as 1 (from the article) or as any other count would invent a quantity. |

### Where they are recognised

A vague word is recognised only at the start of the amount position, which is where v4 would otherwise read a count:

1. **After a leading amount**: an article (`a`, `an`), a word number (`one`, `two`, `three`, `half`, `quarter`) or any v4 numeral, optionally followed by `a` or `an` (`half a handful`). The leading amount is not used. If the numeral is itself ambiguous under the line's convention, the line also keeps v4's `ambiguousNumber` notice, before `householdMeasure`.
2. **At the start of a line with no amount** (`handful of almonds`, `pinch salt`, `few grapes`): `householdMeasure` replaces v4's `missingQuantity`. This applies only where v4 found no leading or trailing amount, so `Dash water 330 ml` keeps its trailing 330 ml exactly as in v4.

The phrase is matched case-insensitively as a whole word (so `dashi`, `bitter`, `fewer` and `pinchos` are not vague words), with an optional following `of`. The forms the owner named are handled: `a handful of`, `a pinch of`, `a few`, `a bit of`.

A vague word anywhere else in the line (`rice with a handful of peas`, `almonds a handful`) is not a vague portion under v5; such lines parse exactly as v4, which already gives them no amount.

### What a vague line records

| Field | v5 vague line |
|---|---|
| `quantity` | none |
| `unit` | none |
| `notices` | `householdMeasure` (after `ambiguousNumber` when the leading numeral is ambiguous), plus any notice v4 would add after the amount (multiple amounts, supplement, recipe, coffee preparation) |
| `query` | the rest of the line after the vague phrase and `of` (`almonds`); the phrase names no food and would only weaken search. When nothing follows the phrase, the query is the line after its leading amount, so it is never empty: `a handful` gives `handful`, `a handful of` gives `handful of`, and `pinch` gives `pinch` |
| `original` | unchanged, so the user and the evidence still see "a handful of almonds" |
| `grammarVersion` | `food-list-lexical-v5` |
| `numeralConvention` | the convention the line was parsed under, as in v4 |

### Golden examples (every numeral convention)

| Line | quantity | unit | notices | query |
|---|---|---|---|---|
| `a handful of almonds` | none | none | householdMeasure | `almonds` |
| `handful of almonds` | none | none | householdMeasure | `almonds` |
| `2 handfuls of almonds` | none | none | householdMeasure | `almonds` |
| `half a handful of oats` | none | none | householdMeasure | `oats` |
| `a pinch of salt` | none | none | householdMeasure | `salt` |
| `a dash of milk` | none | none | householdMeasure | `milk` |
| `a splash of milk` | none | none | householdMeasure | `milk` |
| `a drizzle of olive oil` | none | none | householdMeasure | `olive oil` |
| `a bit of cheese` | none | none | householdMeasure | `cheese` |
| `a few strawberries` | none | none | householdMeasure | `strawberries` |
| `1,5 handfuls of nuts` (full-stop-decimal or unspecified) | none | none | ambiguousNumber, householdMeasure | `nuts` |
| `1,5 handfuls of nuts` (comma-decimal) | none | none | householdMeasure | `nuts` |
| `Dash water 330 ml` | 330 | mL | none (as v4) | `Dash water` |
| `dashi 200 ml`, `bitter lemon 330 ml`, `fewer crisps` | as v4 | as v4 | as v4 | as v4 |

Every line of the v4 golden corpus that contains no vague portion parses under v5 exactly as under v4, apart from the grammar version.

Known limits, accepted: a pasted brand or product name that starts with a vague word and has no amount (`a Dash water`, `Pinch of Nom lasagne`) gets `householdMeasure` instead of v4's count or missing quantity, and the brand word is dropped from the search query (`a Dash water` searches for `water`). This fails safe: the user enters the amount, the original line is kept, and the query stays editable.

Common foods added by the app are different: their text is a saved food name, not a pasted portion. When a common food with no usual portion has a name starting with a vague word (`Pinch of Nom Lasagne`, `Splash orange`, `Bits & Bobs crisps`), the line still has no amount and the household-measure notice, but its search query is the whole saved name (`FoodListImportViewModel.addCommonFood`). With a usual portion the app writes the amount first ("250 g Pinch of Nom Lasagne"), so the vague rule does not apply. Other vague words (`little`, `some`, `bowl`, `glass`) are outside this closed list; `a little bit of cheese` still reads as v4 does (a count of "little bit of cheese"). Widening the list needs a further version.

## Versions, stored lines and evidence

- `FoodListParser.parse(_:convention:)` produces `food-list-lexical-v5` lines. `FoodListParser.version` is `food-list-lexical-v5`, with the frozen identifier `FoodListParser.v5Version`.
- The v4 grammar stays as frozen code, `FoodListParser.parseV4(_:convention:)`, with its identifier `FoodListParser.v4Version`; the v3 grammar stays as `FoodListParser.parse(_:)` and `legacyVersion`.
- **Restored lines are never re-parsed.** A line saved in a queue by a v3 or v4 build keeps its own version and parse, including a v4 count read from a vague word; it is the evidence the user reviewed. The review screen shows it as it was.
- **Evidence is stamped with the line's own version**, as v4 already does: `captureMethodVersion` is the line's `grammarVersion` (`food-list-lexical-v5`, `food-list-lexical-v4` or, when absent, `food-list-lexical-v3`). A v5 descriptor has exactly the v4 form (sorted keys, `numeralConvention`, canonical `quantity`); for a vague line its `quantity` is empty text unless the user typed one.
- **Version detection uses frozen literals.** A stored line is v4 when its `grammarVersion` equals the frozen `food-list-lexical-v4` and v5 when it equals the frozen `food-list-lexical-v5`, never the moving `version` constant. Lines of either version read their amounts under their recorded convention (`ParsedFoodListLine.readsNumeralConvention`): the untouched parse, or typed text made canonical by presentation (v4 contract, Q6). A line without a version, or with one this build does not know, keeps the frozen v3 reading, as under v4.
- `amountNumeral(of:)` reads v5 lines with the v4 numeral token; a vague line has no amount, so it has no numeral.

## Confirm and the review screen

No application rule changes; the only presentation change is the common-food query rule above. A vague line reaches the review screen with an empty amount and the household-measure notice, and Confirm opens with no amount (unit grams, the existing default for a line with no unit), so the needs-amount rule blocks Log until the user enters a measured amount. The #225 withholding safety net is unchanged and does not apply (there is no parsed amount to withhold).

## Receipts and other callers: out of scope

`ReceiptParser` (`receipt-lexical-v1`) and local inventory amounts use only the frozen v3 numeral rule `FoodListParser.number(_:)`, which v5 does not touch. Receipt lines that start with a vague-looking word ("Handful nuts 200g") are product names on a receipt and stay as they are. The search query grammar is likewise unchanged.

## Migration and compatibility

- **No database or schema change.** No new table, column, checkpoint schema version, archive contract, confirmation policy, notice case or operation type. `FoodListCheckpoint` stays schema version 1.
- Persisted format change: new lines carry `grammarVersion = food-list-lexical-v5`, using the optional key v4 added. v3 and v4 lines decode and re-encode byte-identically.
- An older v4 build opening a checkpoint with v5 lines would treat them as v3 lines (it does not know the identifier) and read typed amounts with the frozen v3 rule; downgrade is not supported in general, and nothing is lost from the ledger.

## Contract tests

All synthetic, offline and deterministic.

1. **Golden vague table** (`FoodListLexicalV5Tests`): every vague form above, under `fullStopDecimal`, `commaDecimal` and `unspecified`, asserting no amount, no unit, the notices, the query, the version and the convention; and every v4 golden numeral form before a vague word, with `ambiguousNumber` exactly where v4 finds the numeral ambiguous.
2. **v4 fixtures byte-identical**: `FoodListLexicalV4Tests` runs unchanged against the frozen `parseV4`; every non-vague line of the v4 corpus, plus look-alike words, parses under v5 exactly as under v4 apart from the version; the frozen v4 path still reads "a handful of almonds" as one count.
3. **Restored lines unchanged**: stored v3 and v4 lines decode and re-encode byte-identically and keep their version; a v4 queue restored in the review screen keeps its parse, proposal and v4 evidence label (`FoodListImportPresentationTests`); an unknown version is not read as v4 or v5.
4. **Confirm prefill empty**: a vague line reaches Confirm with no amount and `amountMissing` blocks Log, in en_GB, de_DE, fr_FR and a locale with an unrecognised decimal separator (`FoodListImportPresentationTests`, `CoFIDGenericFoodSearchTests`); its evidence is stamped v5 with the household-measure notice. A common food whose saved name starts with a vague word keeps the whole name as its query and evidence query, with and without a usual portion (`FoodListImportPresentationTests`).
5. **Evidence**: a v5 line's descriptor bytes equal the v4 descriptor for the same line, stamped v5; stored v4 lines keep their v4 label and bytes.
6. **Receipts unaffected**: a pinned `receipt-lexical-v1` snapshot of receipt lines starting with vague-looking words, and `ReceiptParserTests` unchanged.
7. **Evaluation gates**: `FoodSearchQuality` and `FoodQueryEvaluation` do not use `FoodListParser` and stay unchanged. The full gates in `AGENTS.md` run once the code is stable.

## Egress and HealthKit

None. The change is local parsing and local evidence. No destination, request, provider or HealthKit type is added or widened; HealthKit stays read-only.
