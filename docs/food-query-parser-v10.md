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
text, attributes, quantities and the other reasons are what v9 gives.

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

One deliberate consequence: a name that ends in a plural unit, such as "peanut butter cups",
now clarifies as a portion, as "peanut butter cup" already did under v9. Discovery is still
allowed and the food text is unchanged (the unit is not at the start), so search finds the
same records; Confirm opens with the amount empty, as it did for the search route.

## Versions and stored values

`food-query-parser-v10` and `food-query-interpretation-v3` are code constants and are not
stored in food records, evidence or exports, so there is nothing to migrate. The list grammar
(`FoodListParser`, `food-list-lexical-v5`) already treats "mug" and "mugs" as household
measures and is unchanged.

## Evaluation

`Tools/FoodQueryEvaluation/synthetic-v9.json` keeps the 563 v8 cases unchanged and adds 18
household-container cases (`build_v9.py`, family `household_containers_v9`). Expectations
were written alongside the parser change; the first run used parser v9 from `main`, whose
hash the manifest records. Reasons are not scored, so the six route failures of the first
run are the queries without a number ("mugs of tea", "cups of coffee", "glasses of milk",
"pots of yoghurt", "packs of crisps", "peanut butter cups"); the numbered forms already
clarified under v9.

| Run | Routing | Quantity | Search cases, all fields | Unexpected prefills |
|---|---:|---:|---:|---:|
| v9 first run (parser v9) | 575/581 | 581/581 | 383/383 | 0 |
| v9 final (parser v10) | 581/581 | 581/581 | 383/383 | 0 |

The v8 gate still passes on parser v10. One v8 prediction differs from
`predictions/v8-final.json.gz`: "2 mugs coffee. 14g light roast grounds" gains
`portion_requires_confirmation`; its route (`clarify`) and empty quantity are unchanged. The
retrieval scenarios (`Tools/FoodSearchQuality/retrieval-scenarios-v3.json` to `v6`) were
replayed; the replay reports are byte-identical to a replay of `main` on the same machine.
Same-author synthetic cases, not independent acceptance.
