# Food query parser v10: plural household containers

Fixes #335. A bounded change to the household-portion words of the pure search parser
(`FoodQueryParser`) and the matching retrieval rule in `FoodQueryInterpretation`, which
becomes `food-query-interpretation-v3`.

## Problem

Parser v9 listed `cup`, `mug`, `glass`, `pot` and `pack` only in the singular, while jars,
tubs, cartons, bottles and the other containers already accepted a plural. "3 mugs of tea"
therefore had no `portion_requires_confirmation` reason. It still clarified, because the
number was unresolved, but the interpretation then offered "Use 3 from your description"
and searched for "mugs tea". "mugs of tea" with no number was routed straight to search.
The same held for cups, glasses, pots and packs.

## Rule

`food-query-parser-v10` treats `cups`, `mugs`, `glasses`, `pots` and `packs` as household
portions, exactly like their singular forms. Nothing else in the grammar changes: the food
text and attributes are what v9 gives. Because a household portion routes to clarification,
any query that now contains one of these plural words loses its search route and with it any
quantity (see "Queries whose route changes" below).

`food-query-interpretation-v3` applies the v2 rule (one leading amount and household unit
leaves the retrieval text when the parser asks for portion confirmation) to the same plural
forms, with the v2 guards:

- `mug` and `mugs` behave like `cup` and `cups`: they are removed with or without "of"
  ("2 mugs tea" and "a mug of coffee" search "tea" and "coffee"), except before `cake` or
  `cakes`. A mug cake is a food in its own right, as a cup cake is, so "a mug cake", "1 mug
  cake" and "2 mug cakes" keep their food text. Unlike `pot` or `glass`, no common food name
  starts with "mug", so an "of" guard would only stop "2 mugs tea" from searching "tea".
- `pots`, `glasses` and `packs` are removed only when "of" follows that leading unit, as
  `pot`, `glass`, `bottle(s)` and `pack` already are: "2 pots of yoghurt" searches
  "yoghurt", while "2 pots noodles" is unchanged.
- The "Use N from your description" exclusion list also names mugs and glasses. Under parser
  v10 these queries already clarify as portions, so this is a second guard, not a new route.

Examples: "3 mugs of tea" clarifies, offers no "Use 3" suggestion and searches "tea"; "2
cups of tea" searches "tea"; "2 glasses of milk" searches "milk".

## What does not change

- The route stays `clarify`. No amount is set, no suggestion is offered and Confirm opens
  with the amount empty for the user to enter. No count, volume or portion size is inferred
  from the container word. The original text remains the stored evidence.
- Jars, tubs, cartons and bottles already accepted a plural; their parse is unchanged.
- "mug cake" already clarified under v9 because `mug` is a portion word; it still does, and
  its food text is kept.
- Words that only contain a unit ("cupcakes", "potatoes", "packed lunch") are unchanged.

## Queries whose route changes

Each of these matches the existing singular rule and is intentional.

- **A mass or volume with a plural container name.** "200g fruit cups", "100g quaker oat so
  simple pots" and "300ml glasses of milk" were `search` with a 200 g, 100 g or 300 ml
  quantity under v9. They now clarify with no quantity, so Confirm opens with the amount
  empty instead of pre-filled. This is how "200g fruit cup" and "300ml glass of milk" already
  behaved under v9: the parser does not decide whether a mass refers to the container or its
  contents.
- **A name that ends in a plural container word.** "yoghurt pots", "fruit cups", "lettuce
  cups" and "peanut butter cups" were `search`; they now clarify, as "yoghurt pot" and
  "peanut butter cup" already did. Discovery is still allowed and the food text is unchanged
  (the unit is not at the start), so search finds the same records.
- **A count before such a name.** "2 yoghurt pots" offered "Use 2 from your description"
  under v2, because the text after the number parsed as a plain food. The parser now treats
  "yoghurt pots" as a portion, so no suggestion is offered and the amount is left for Confirm,
  as for "2 yoghurt pot". The food text is the parser's ("2 yoghurt pots"), as it is for the
  singular form.
- **A bare plural unit.** "cups", "glasses" and "packs" on their own now clarify, as "cup",
  "glass" and "pack" already did. A container word alone names no food.

Food names that start with a unit keep their v9 routes: "packed lunch" is `search` (only a
whole word matches), and "pot noodle" and "glass noodles" clarify as they did under v9.

## Versions and stored values

`food-query-parser-v10` and `food-query-interpretation-v3` are code constants and are not
stored in food records, evidence or exports, so there is nothing to migrate. The list grammar
(`FoodListParser`, `food-list-lexical-v5`) already treats "mug" and "mugs" as household
measures and is unchanged.

## Evaluation

`Tools/FoodQueryEvaluation/synthetic-v9.json` keeps the 563 v8 cases unchanged and adds 29
household-container cases (`build_v9.py`, family `household_containers_v9`). Expectations
were written alongside the parser change; 11 of them (the route changes above and the
unchanged food names) were added after the invariant review of PR #340, and both runs were
regenerated with all 29. The first run used parser v9 from `main`, whose hash the manifest
records. Reasons are not scored, so the 13 route failures of the first run are the queries
whose route changes: those without a number ("mugs of tea", "cups of coffee", "glasses of
milk", "pots of yoghurt", "packs of crisps"), the trailing plural names ("peanut butter cups",
"yoghurt pots", "fruit cups", "lettuce cups"), the bare "cups" and the three mass or volume
cases, which v9 pre-filled. The numbered forms already clarified under v9.

| Run | Routing | Quantity | Search cases, all fields | Unexpected prefills |
|---|---:|---:|---:|---:|
| v9 first run (parser v9) | 579/592 | 589/592 | 384/384 | 3 |
| v9 final (parser v10) | 592/592 | 592/592 | 384/384 | 0 |

The v8 gate still passes on parser v10. One v8 prediction differs from
`predictions/v8-final.json.gz`: "2 mugs coffee. 14g light roast grounds" gains
`portion_requires_confirmation`; its route (`clarify`) and empty quantity are unchanged. The
retrieval scenarios (`Tools/FoodSearchQuality/retrieval-scenarios-v3.json` to `v6`) were
replayed; the replay reports are byte-identical to a replay of `main` on the same machine.
Same-author synthetic cases, not independent acceptance.
