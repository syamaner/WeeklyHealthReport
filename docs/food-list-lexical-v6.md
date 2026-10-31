# Food list lexical grammar v6: household containers leave the food name

Status: **Approved under the owner approval of 24 October 2026**, which delegated the UX review backlog (bugs first, then enhancements) together with the contract amendments those items need. Implemented in the same PR.
Fixes [#353](https://github.com/syamaner/WeeklyHealthReport/issues/353). Amends the parsing envelope in [food-list-import.md](food-list-import.md). Introduces the grammar identifier **`food-list-lexical-v6`**; `food-list-lexical-v5` ([contract](food-list-lexical-v5.md)), `food-list-lexical-v4` ([contract](food-list-lexical-v4.md)) and `food-list-lexical-v3` stay defined and frozen.

## Problem

Under `food-list-lexical-v5` a household container stays in the food name, so Find matches searches for the container as well as the food and returns nothing:

| Line | v5 parse | Search (parser v10, interpretation v3) |
|---|---|---|
| `2 mugs of tea` | no amount, household-measure notice, food "mugs of tea" | food "tea", amount left for Confirm |
| `a pot of yoghurt` | 1 count of "pot of yoghurt" | food "yoghurt", amount left for Confirm |
| `2 glasses of milk` | 2 counts of "glasses of milk" | food "milk", amount left for Confirm |
| `250 ml mug of milk` | 250 mL of "mug of milk" | no quantity (the volume could measure the mug or the milk) |
| `mugs of tea` | missing-quantity notice, food "mugs of tea" | clarifies, amount left for Confirm |

The list grammar listed mugs, cups and packs as household measures but kept the unit word in the query, and did not know glasses or pots at all, so "a pot of yoghurt" became a definite count the user never stated. Search fixed the same class of fault in #333 and #335 ([query parser v10](food-query-parser-v10.md), [interpretation v2 and its v3 amendment](food-query-interpretation-v2.md)).

## Goal

A pasted line and the same search text look for the same food, under one rule, and a container never produces an amount. The line has no amount and no unit and carries the existing `householdMeasure` notice ("A mug, spoon or portion needs a measured amount or an evidenced conversion."), so the existing needs-amount rule blocks Log until the user enters a measured amount. Everything else is identical to v5.

Non-goals: household conversions (no count, volume or portion size is inferred from a container), new notices, new units, the other household measures (spoons, scoops, slices, portions, packets), other containers (bottles, jars, tubs, cans, cartons), the search grammar, and receipts (`receipt-lexical-v1`).

## One rule: `HouseholdContainerRule`

The container guards that search applies under `food-query-interpretation-v3` move, unchanged, from `FoodQueryInterpretation` (application layer) to a pure domain type, `FoodLedgerDomain.HouseholdContainerRule`, so the list grammar (domain layer) can use them without depending on the application layer. Search calls the same type; its behaviour is unchanged (the existing interpretation tests and both search evaluations pass as before).

- `cup`, `cups`, `mug` and `mugs` are a container with or without "of" ("2 mugs tea", "1 cup rice"), except before `cake` or `cakes`: a mug cake is a food in its own right, as a cup cake is.
- `pot`, `pots`, `glass`, `glasses`, `pack` and `packs` (and, in search only, `bottle` and `bottles`) also start food names (pot noodle, glass noodles, pack choi), so they are a container only when "of" follows them ("a pot of yoghurt").
- The list grammar recognises the closed set cups, mugs, glasses, pots and packs, singular and plural, as whole words matched case-insensitively ("cupcakes", "potatoes", "packed lunch" and "mugwort" are not containers). A container with no food after it ("2 mugs", "a mug of") is not one, so the query is never empty. Widening the set needs a further version.

## Where containers are recognised

A container is recognised only at the start of the food text, in the four amount positions:

| Position | Example | v6 result |
|---|---|---|
| After a leading count, word number or article (optionally `x`) | `2 mugs of tea`, `a pot of yoghurt`, `two mugs of hot chocolate`, `2 x mugs of tea` | no amount, `householdMeasure`, query `tea`, `yoghurt`, `hot chocolate`, `tea` |
| After a leading mass or volume | `250 ml mug of milk`, `200 g pot of yoghurt` | no amount and no unit, `householdMeasure`, query `milk`, `yoghurt` |
| Before a single trailing mass or volume | `mug of milk 250 ml` | as the row above |
| With no amount | `mugs of tea`, `glass of milk` | `householdMeasure` instead of `missingQuantity`, query `tea`, `milk` |

A mass or volume next to a container is withheld for the same reason search withholds it: the grammar cannot tell whether "250 ml" measures the mug or the milk. The user enters the consumed amount on the review screen or on Confirm. The original line keeps "250 ml", so the evidence still shows what was written.

A vague portion (v5) is checked first, so "a handful of" lines are exactly as v5. Notices that v5 adds after the amount still apply: a second mass in the rest of the line still gives `multipleAmounts`, coffee grounds still give `preparationInput`, and "homemade" still gives `recipe`. An ambiguous numeral before a container keeps `ambiguousNumber` before `householdMeasure`, as v5 does for vague words.

### What does not change

- "a mug cake", "2 mug cakes", "mug cake" and "200 g mug cake" parse as v5 (the household-measure notice where v5 gives it, and the food text kept).
- Glasses, pots and packs without "of" parse as v5: "a pot noodle" is still one count of "pot noodle", "2 packs crisps" still has the household-measure notice with "packs crisps", and "200 g glass noodles" keeps its 200 g. Search clarifies "a pot noodle" because its parser treats a portion word anywhere as a portion; the list grammar keeps v5's reading at the amount position only, so these lines keep their v5 route. This is the existing difference between the two grammars and is not widened.
- A container later in the line ("rice with a cup of peas", "tea 2 mugs", "milk 250 ml mug") parses as v5.

### Golden examples (every numeral convention)

| Line | quantity | unit | notices | query |
|---|---|---|---|---|
| `2 mugs of tea` | none | none | householdMeasure | `tea` |
| `2 mugs tea` | none | none | householdMeasure | `tea` |
| `a cup of tea`, `1 cup rice` | none | none | householdMeasure | `tea`, `rice` |
| `a glass of milk`, `2 glasses of milk` | none | none | householdMeasure | `milk` |
| `a pot of yoghurt`, `2 pots of yoghurt` | none | none | householdMeasure | `yoghurt` |
| `a pack of crisps`, `2 packs of crisps` | none | none | householdMeasure | `crisps` |
| `mugs of tea` | none | none | householdMeasure | `tea` |
| `250 ml mug of milk` | none | none | householdMeasure | `milk` |
| `200 g pot of yoghurt` | none | none | householdMeasure | `yoghurt` |
| `1,5 mugs of tea` (full-stop-decimal or unspecified) | none | none | ambiguousNumber, householdMeasure | `tea` |
| `a mug cake` | none | none | householdMeasure (as v5) | `mug cake` |
| `a pot noodle` | 1 | count | none (as v5) | `pot noodle` |
| `150 g boiled rice` | 150 | g | none (as v5) | `boiled rice` |

`FoodListLexicalV6Tests` holds the full tables.

## Common foods added by the app

A saved common-food name is a food name, not a pasted portion, so the v5 rule extends to containers: when a name starts with a container ("Mug Shot pasta", "Glass of milk", "Cup of tea") and has no usual portion, the line has no amount and the household-measure notice, but its search query is the whole saved name (`FoodListImportViewModel.addCommonFood`). With a usual mass or volume portion the app writes "of" between its own portion and the name ("68 g of Mug Shot pasta"), so the grammar reads the portion as the amount of the whole name instead of withholding it; a count portion is written as before ("1 piece Pot of yoghurt"). Names that do not start with a container ("90 g Pot Noodle") are written as before.

## Versions, stored lines and evidence

- `FoodListParser.parse(_:convention:)` produces `food-list-lexical-v6` lines. `FoodListParser.version` is `food-list-lexical-v6`, with the frozen identifier `FoodListParser.v6Version`.
- The v5 grammar stays as frozen code, `FoodListParser.parseV5(_:convention:)`, with its identifier `FoodListParser.v5Version`; v4 and v3 are unchanged.
- **Restored lines are never re-parsed.** A line saved in a queue by a v5 build keeps its own version and parse, including a v5 count read from "a pot of yoghurt"; it is the evidence the user reviewed.
- **Evidence is stamped with the line's own version** (`captureMethodVersion`). A v6 descriptor has exactly the v5 form; for a container line its `quantity` is empty text unless the user typed one.
- **Version detection uses frozen literals.** `ParsedFoodListLine.isV6` compares with the frozen `food-list-lexical-v6`; `readsNumeralConvention` is true for v4, v5 and v6 lines. A version this build does not know keeps the frozen v3 reading, as before.

## Confirm and the review screen

No application rule changes. A container line reaches the review screen with an empty amount and the household-measure notice, and Confirm opens with no amount, so the needs-amount rule blocks Log until the user enters a measured amount. Find matches searches the food ("tea"), as search does.

## Migration and compatibility

- **No database or schema change.** No new table, column, checkpoint schema version, archive contract, confirmation policy, notice case or operation type. `FoodListCheckpoint` stays schema version 1.
- New lines carry `grammarVersion = food-list-lexical-v6`, using the optional key v4 added. v3, v4 and v5 lines decode and re-encode byte-identically.
- An older v5 build opening a checkpoint with v6 lines would treat them as v3 lines (it does not know the identifier), as v4 builds did with v5 lines; downgrade is not supported in general, and nothing is lost from the ledger.

## Contract tests

All synthetic, offline and deterministic.

1. **Golden container table** (`FoodListLexicalV6Tests`): every container form above under `fullStopDecimal`, `commaDecimal` and `unspecified`, asserting no amount, no unit, the notices, the query, the version and the convention; the ambiguous numeral case; and notices after the amount.
2. **v5 unchanged**: `FoodListLexicalV5Tests` runs against the frozen `parseV5`; the look-alike lines, the v5 vague table and the v4 corpus parse under v6 exactly as v5 apart from the version; the lines whose parse changes are pinned against their v5 parse.
3. **One rule**: `HouseholdContainerRuleTests` covers the guards and the look-alike words; `FoodQueryInterpretationTests.testListGrammarAndSearchShareTheContainerRule` checks that the list query equals the search retrieval text for the same lines, that neither gains an amount, and that both keep the container word where the guard keeps it.
4. **Stored lines**: v6 encoding, v5 lines restored byte-identically and an unknown version not read as v6.
5. **Confirm prefill empty**: container lines reach Confirm with no amount and `amountMissing` blocks Log in en_GB, de_DE, fr_FR and ar_SA (`FoodListImportPresentationTests`), and through CoFID search with v6 evidence and the household-measure notice (`CoFIDGenericFoodSearchTests`). Common foods that start with a container keep their name, and their mass, volume or count portion (`FoodListImportPresentationTests`).
6. **Evaluation gates**: `FoodQueryEvaluation` compiles only the query parser and discovery policy, which are unchanged. `FoodSearchQuality` replays search through `FoodQueryInterpretation`, whose behaviour is unchanged; both CI steps run as before. The full gates in `AGENTS.md` run once the code is stable.

## Egress and HealthKit

None. The change is local parsing and local evidence. No destination, request, provider or HealthKit type is added or widened; HealthKit stays read-only.
