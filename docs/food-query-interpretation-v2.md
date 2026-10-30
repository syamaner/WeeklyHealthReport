# Food query interpretation v2: household portions leave the search text

Fixes #333. A bounded change to `FoodQueryInterpretation` (application layer), which turns
the parser's retrieval hints into the search request. `FoodQueryParser` stays
`food-query-parser-v9` and its output is unchanged.

## Problem

A query whose amount is a household portion ("3 pieces cheese", "3 pieces of apple pie",
"a handful of almonds", "2 slices of toast") is routed to clarification with
`portion_requires_confirmation`, and discovery is still allowed. The parser keeps the
portion words in its food text, so search looked for "3 pieces cheese" and found nothing,
while "cheese" finds many records. This predates parser v9: the same queries give no match
with parser v8.

## Rule

`food-query-interpretation-v2` removes one leading amount and household unit from the food
text used for retrieval when, and only when, the parser reports
`portion_requires_confirmation` and no "Use N from your description" suggestion applies.

- The amount is a numeral, `half`, one to six as words, or `a` / `an`, optionally followed by
  `x`; the unit is one of the parser's household units or `slice` / `slices`. A leading
  `some` is removed on its own.
- `pot`, `glass`, `bottle` and `pack` also start food names (pot noodle, glass noodles,
  bottle gourd, pack choi), so they are removed only when "of" follows that leading unit in
  the original: "a pot of yoghurt" searches "yoghurt", while "a pot noodle" is unchanged. An
  "of" later in the text does not count: "a glass noodle salad with a glass of milk" is
  unchanged.
- `cup` is removed with or without "of" ("1 cup rice" and "half cup rice" search "rice"),
  except before `cake` or `cakes`: "a cup cake" and "1 cup cakes" are unchanged.
- A zero amount, a portion that is not at the start ("cheese 3 pieces") and a portion with no
  food after it ("3 pieces") are unchanged.

Examples: "3 pieces cheese" searches "cheese", "3 pieces of apple pie" searches "apple pie",
"A bowl of rice" searches "rice", "2 slices of toast" searches "toast".

## What does not change

- The route stays `clarify` and the reasons, including `portion_requires_confirmation`, are
  the parser's. The baseline parse and the original text (the stored evidence) are unchanged.
- No amount is set. The query quantity stays empty, no "Use N" suggestion is offered, and
  Confirm opens with the amount empty for the user to enter. No count, weight or portion
  size is inferred from the portion words.
- Numbered pieces of a counted whole item ("3 pieces banana") keep the v9 count.
- Discovery admission is unchanged: sources that re-parse the raw text still see the
  clarification and decline it as before.

"2 hard boiled bananas" has no portion word and is outside this rule. It still offers "Use 2
from your description" and searches "hard banana" with the boiled preparation; the bundled
sources have no boiled banana record, so "boiled bananas" also finds no match.

## Versions and evaluation

`food-query-interpretation-v2` is a code constant and is not stored in records, evidence or
exports, so there is nothing to migrate. The parser evaluation (`Tools/FoodQueryEvaluation`,
`synthetic-v8.json`) compiles only the parser and discovery policy, so its predictions are
unchanged and no new evaluation set is needed. The retrieval scenarios
(`Tools/FoodSearchQuality/retrieval-scenarios-v3.json` to `v6`) contain no household-portion
queries, so their replay is unchanged. Both CI steps run as before.

## Amendment: v3 (#335)

`food-query-interpretation-v3`, with `food-query-parser-v10`, extends this rule to the plural
forms of the singular-only units: `cups` and `mugs` behave like `cup` (removed with or without
"of", except before `cake` or `cakes`), `mug` joins them, and `pots`, `glasses` and `packs`
keep the "of" guard. "3 mugs of tea" searches "tea" and offers no "Use 3" suggestion; "a mug
cake" keeps its food text. See [query parser v10](food-query-parser-v10.md).
