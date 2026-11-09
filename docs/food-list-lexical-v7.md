# Food list lexical grammar v7: household measures leave the food name

Status: **Approved under the owner approval of 24 October 2026**, which delegated the UX review backlog (bugs first, then enhancements) together with the contract amendments those items need. Implemented in the same PR.
Fixes part 2 of [#359](https://github.com/syamaner/WeeklyHealthReport/issues/359). Amends the parsing envelope in [food-list-import.md](food-list-import.md). Introduces the grammar identifier **`food-list-lexical-v7`**; `food-list-lexical-v6` ([contract](food-list-lexical-v6.md)), v5, v4 and v3 stay defined and frozen. Part 1 of #359, the search side, is [query interpretation v4](food-query-interpretation-v4.md).

## Problem

`food-list-lexical-v6` removed five containers (cups, mugs, glasses, pots and packs) from the search query. Every other household measure still kept its unit word, so Find matches looked for "slices of bread" and found nothing, and containers outside the closed set were worse: v6 did not know them as household measures at all, so a line such as "a bottle of water" became a definite count the user never stated.

| Line | v6 parse |
|---|---|
| `2 slices of bread` | no amount, household-measure notice, food "slices of bread" |
| `2 tbsp olive oil` | no amount, household-measure notice, food "tbsp olive oil" |
| `a bottle of water` | 1 count of "bottle of water" |
| `a can of coke`, `a tin of tomatoes`, `a bowl of porridge` | 1 count, container kept in the food |
| `a spoonful of sugar`, `2 tea spoons sugar` | 1 or 2 counts, spoon kept in the food |
| `500 ml bottle of water` | 500 mL of "bottle of water" |
| `jars of honey` | missing-quantity notice, food "jars of honey" |

## Goal

The v6 rule, applied to a wider closed set: a household measure gives no amount and no unit, carries the existing `householdMeasure` notice, and leaves the search query ("2 slices of bread" searches "bread"). The existing needs-amount rule blocks Log until the user enters a measured amount. **v7 removes amounts and never adds one**: every line whose parse changes either had no amount under v6 or loses the count or the mass or volume v6 read.

Non-goals: household conversions (no count, volume or portion size is inferred), new notices, new units, the search parser, and receipts (`receipt-lexical-v1`).

## The closed set

`HouseholdContainerRule.listMeasurePatternV7`, whole words matched case-insensitively, singular and plural:

- **The v6 containers:** cups, mugs, glasses, pots, packs.
- **Other containers:** bottles, jars, tubs, cans, tins, cartons, bowls, bags, sachets, plates. The issue names bottles, jars and tubs; the others are in search's household-portion list already (interpretation v2), so adding them keeps the two grammars aligned and stops each one from producing a count.
- **Other household measures:** slices, scoops, portions, servings, packets, dollops, spoons, spoonfuls, teaspoons, teaspoonfuls, tablespoons, tablespoonfuls, `tsp`, `tbsp`, and the split forms "tea spoon(s)" and "table spoon(s)". A unit may carry a full stop, as the v4 unit token allows ("2 tsp. sugar" searches "sugar").

Pieces stay a count unit, unchanged ("3 pieces of cheese" is 3 counts of "cheese"). Words that only contain a unit are not measures: "bagel", "canned tuna", "tinned peas", "platefuls", "servingware", "sliced bread", "spoonbread". Widening the set needs a further version.

The `householdMeasure` notice for the new words comes only from this v7 branch. The older `household` word list in `FoodListParser` (which gives the notice without removing the word) is unchanged because the frozen grammars use it.

## Guards (shared with search)

The v6 guards in `HouseholdContainerRule` apply unchanged:

- Cups and mugs are a measure with or without "of", except before `cake` or `cakes` (a mug cake is a food).
- Pots, glasses, packs and bottles also start food names (pot noodle, glass noodles, pack choi, bottle gourd), so they are a measure only when "of" follows them.
- A measure with no food after it ("2 slices", "a jar of") is not one, so the query is never empty.

v7 adds one guard, `HouseholdContainerRule.measureLeavesFoodText(unit:followedByOf:rest:afterAmount:)`: **with no amount, "of" must follow the unit.** "mugs of tea" and "slices of bread" name a measure; "cup noodles", "mugs tea" and "slice bread" are kept as names. Search interpretation v4 uses the same function.

## Where measures are recognised

As in v6, only at the start of the food text, in the four amount positions:

| Position | Example | v7 result |
|---|---|---|
| After a leading count, word number or article (optionally `x`) | `2 slices of bread`, `a bottle of water`, `two slices of toast`, `2 x bottles of water`, `2 tbsp olive oil` | no amount, `householdMeasure`, query `bread`, `water`, `toast`, `water`, `olive oil` |
| After a leading mass or volume, with or without "of" | `500 ml bottle of water`, `500 ml of bottle of water`, `400 g tin of tomatoes` | no amount and no unit, `householdMeasure`, query `water`, `water`, `tomatoes` |
| Before a single trailing mass or volume | `bottle of water 500 ml` | as the row above |
| With no amount, "of" required | `slices of bread`, `jars of honey` | `householdMeasure` instead of `missingQuantity`, query `bread`, `honey` |

The v6 containers are checked first, so every v6 container line keeps its v6 parse apart from the version, except the three no-amount, no-"of" lines below. A vague portion (v5) is checked before both. Notices added after the amount still apply (`multipleAmounts`, `preparationInput`, `recipe`, `supplement`), and an ambiguous numeral keeps `ambiguousNumber` before `householdMeasure`. A count unit before a measure keeps the written count, as in v6 ("2 pieces slice of cake").

## Lines whose parse changes from v6

`FoodListLexicalV7Tests.changedFromV6` pins each against `parseV6` under every numeral convention:

- **Counts v6 read from a container it did not know**, now no amount: "a bottle of water" (1), "2 bottles of water" (2), "2 jars honey" (2), "a can of coke", "a tin of tomatoes", "a tub of ice cream", "a bowl of porridge", "a carton of juice", "a bag of crisps", "a sachet of oats", "a plate of pasta", "1 serving of rice", "a dollop of cream", "a spoonful of sugar" (1 each) and "2 tea spoons sugar" (2).
- **A mass or volume v6 kept next to a measure it did not know**, now withheld: "500 ml bottle of water", "400 g tin of tomatoes", "30 g slice of cheese".
- **Household measures v6 already gave no amount**, now leaving the query: "2 slices of bread", "2 scoops protein powder", "2 tbsp olive oil", "a portion of chips", "2 packets of crisps", "1 table spoon of honey".
- **No amount, with "of"**: "slices of bread" and "jars of honey" gain `householdMeasure` and leave the query.
- **No amount and no "of"**: "cup noodles", "mugs tea" and "cup tea" were stripped by v6 ("noodles", "tea"); v7 keeps the whole text with `missingQuantity`, so a product name such as Cup Noodles survives. Neither grammar has an amount for these lines.

## Common foods added by the app

As in v6, a saved name is a food name: when it starts with a measure (now the wider set, for example "Slice of Heaven cake" or "Bowl of porridge") and there is no usual portion, the line has no amount and the household-measure notice, and the query is the whole name. With a usual mass or volume portion the parse withholds the amount and the app fills the editable amount from the saved portion, as if typed ("30 g Slice of Heaven cake"). A count portion parses as before ("1 piece Bowl of porridge"). A saved name such as "Mug Shot pasta" with no portion now has the missing-quantity notice instead of the household-measure notice (no "of"); its query is still the whole name and it still has no amount.

## Versions, stored lines and evidence

- `FoodListParser.parse(_:convention:)` produces `food-list-lexical-v7` lines. `FoodListParser.version` is `food-list-lexical-v7`, with the frozen identifier `FoodListParser.v7Version`.
- v6 stays as frozen code, `FoodListParser.parseV6(_:convention:)`; v5, v4 and v3 are unchanged.
- **Restored lines are never re-parsed.** A stored v6 line keeps its own parse, including a v6 count read from "a bottle of water".
- **Evidence is stamped with the line's own version.** A v7 descriptor has exactly the v6 form.
- **Version detection uses frozen literals.** `ParsedFoodListLine.isV7` compares with `food-list-lexical-v7`; `readsNumeralConvention` is true for v4 to v7 lines. An unknown version keeps the v3 reading.

## Migration and compatibility

No database or schema change, no new notice, unit, table, column, checkpoint schema version or operation type. New lines carry `grammarVersion = food-list-lexical-v7` in the existing optional key; v3 to v6 lines decode and re-encode byte-identically. An older build opening v7 lines treats them as v3 lines, as before; downgrade is not supported in general.

## Contract tests

All synthetic, offline and deterministic.

1. **Golden measure table** (`FoodListLexicalV7Tests.measureTable`) under `fullStopDecimal`, `commaDecimal` and `unspecified`, in all four positions; the ambiguous numeral case; and notices after the amount.
2. **v6 unchanged**: look-alikes, the v6 container and unchanged tables, the v5 vague table and the v4 corpus parse as `parseV6` apart from the version; the changed lines are pinned against `parseV6`.
3. **Rule**: `HouseholdMeasureRuleV7Tests` covers `measureLeavesFoodText` and `leadingListMeasure`, including an empty rest and the look-alikes.
4. **Stored lines**: v7 encoding; v3 to v6 lines restored byte-identically; an unknown `food-list-lexical-v8` not read as v7.
5. **Confirm**: v7 lines reach Confirm with no amount and `amountMissing` blocks Log in en_GB, de_DE, fr_FR and ar_SA (`FoodListImportPresentationTests`) and through CoFID search with v7 evidence (`CoFIDGenericFoodSearchTests`); common foods keep their name and portion.
6. **Parity with search**: `FoodQueryInterpretationTests.testListGrammarAndSearchShareTheContainerRule`, with its table of known divergences (spoon abbreviations, see [interpretation v4](food-query-interpretation-v4.md)).

## Egress and HealthKit

None. Local parsing and local evidence only; HealthKit stays read-only.
