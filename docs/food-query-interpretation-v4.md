# Food query interpretation v4: household units with no amount before them

Status: **Approved under the owner approval of 24 October 2026**, which delegated the UX review backlog together with the contract amendments it needs. Implemented in the same PR.
Fixes part 1 of [#359](https://github.com/syamaner/WeeklyHealthReport/issues/359). Amends [interpretation v2](food-query-interpretation-v2.md) and its v3 amendment ([query parser v10](food-query-parser-v10.md)). `FoodQueryInterpretation.version` becomes `food-query-interpretation-v4`; `FoodQueryParser` stays `food-query-parser-v10` and its output is unchanged. Part 2, the list grammar, is [list lexical v7](food-list-lexical-v7.md).

## Problem

The v2 and v3 rule removes a household unit from the retrieval text only after a leading amount ("3 mugs of tea" searches "tea"). Two forms kept the unit:

| Query | v3 retrieval text |
|---|---|
| `mugs of tea`, `cup of tea`, `slices of bread`, `jars of honey` (no amount) | `mugs tea`, `cup tea`, `slices bread`, `jars honey` |
| `250 ml mug of milk`, `300ml glasses of milk`, `500 ml bottle of water` (the parser withholds the mass or volume) | `mug milk`, `glasses milk`, `bottle water` |

Each already clarifies with no quantity, so the search simply found less.

## Rule

When the parser reports `portion_requires_confirmation` and no "Use N" suggestion applies (unchanged conditions), and the parser's food text starts with one of the v2 household units (now with plural `bowls`) followed by a food:

- If the original starts with a mass or volume (g, kg, ml, l and their spelt forms), an optional "of", and that unit, the unit leaves the retrieval text under the v3 guards: cups and mugs with or without "of" except before a cake, pots, glasses, packs and bottles only before "of". "250 ml mug of milk" and "250 ml mug milk" search "milk"; "200 g glass noodles", "200 g mug cake" and "200 g bottle gourd" keep their text.
- If the original starts with the unit itself, there is no amount, so "of" must follow it: "mugs of tea" searches "tea" and "mug of milk 250 ml" searches "milk", while "cup noodles", "mugs tea", "mug cake", "pot noodle" and "glass noodles" keep their text.

Both cases call the shared domain function `HouseholdContainerRule.measureLeavesFoodText(unit:followedByOf:rest:afterAmount:)`, which the list grammar v7 also uses, so the "of" rule cannot drift between search and lists.

## What does not change

- The route, reasons, quantity (none), suggestion (none), discovery permission and original text are those of v3. Only the retrieval text changes, and only by removing the unit word.
- No amount is set and Confirm opens with the amount empty. No count, volume or portion size is inferred from the unit.
- Queries with a leading count keep the v3 rule exactly.

## Known divergence from the list grammar

Parser v10 gives `tbsp`, `tsp`, "tea spoon(s)" and "table spoon(s)" no `portion_requires_confirmation` reason, so this rule does not apply to them: "2 tbsp olive oil" still searches "tbsp olive oil", while list v7 searches "olive oil". Neither produces an amount. Closing the gap needs a parser version and a FoodQueryEvaluation update, and is left as a follow-up. The parity test names these cases.

## Versions and stored values

`food-query-interpretation-v4` is a code constant and is not stored in food records, evidence or exports, so nothing migrates. The parser is unchanged, so the `FoodQueryEvaluation` gate (which compiles only the parser and discovery policy) is unaffected. No `FoodSearchQuality` retrieval scenario query contains a household unit, so its replays are unchanged.

## Contract tests

`FoodQueryInterpretationTests.testBareLeadingHouseholdUnitLeavesTheRetrievalText` (the changed queries, with route, reasons, quantity and suggestion pinned to v3, and the kept names) and `testListGrammarAndSearchShareTheContainerRule` (search and list parity, with the divergence table). Synthetic, offline and deterministic.

## Egress and HealthKit

None.
