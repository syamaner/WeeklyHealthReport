# Food query parser v8: cooked egg counts

Owner decision E on issue #140 (13 October 2026). A bounded change to the count
grammar of the pure search parser (`FoodQueryParser`).

## Rule

`food-query-parser-v8` accepts `scrambled`, `fried` and `poached` between a
count and `egg` or `eggs`, alongside the existing `boiled` and `soft boiled`.
"2 scrambled eggs", "two fried eggs", "a fried egg" and "2 x poached eggs" are
read as item counts. Under v7 they were either a clarification ("2 scrambled
egg" with an unresolved number) or a search with no amount ("two fried egg").

- The method stays in the food text ("scrambled egg", "fried egg"), so
  retrieval still asks for that record; it is not turned into a preparation
  attribute and does not filter sources.
- The new words apply to eggs only. "2 fried bananas" keeps its v7 route.
- "pan fried" is not added: "2 pan fried eggs" still asks for clarification.
- A count with a mass ("2 scrambled eggs 120g") still asks which basis to use;
  a negated method ("not fried 2 eggs") is not a count; zero rejects.

## Counts stay basis-only

A count is never a mass. No portion weight, egg size, energy or nutrient value
is inferred. On Confirm the amount is 2 eggs with no conversion, and Log stays
blocked by the existing "count needs a measured amount" requirement until the
user gives a weight or the selected source provides a compatible portion. A
test exercises this for scrambled, fried and poached eggs through the
two-source composite.

## Versions and stored values

`food-query-parser-v8` is a code constant. The parser version is not stored in
food records, evidence or exports, so there is nothing to migrate; the original
query text remains the stored evidence. The list grammar
([food list lexical v4](food-list-lexical-v4.md)) has its own count rules and is
unchanged.

## Evaluation

`Tools/FoodQueryEvaluation/synthetic-v6.json` keeps the 511 v5 cases unchanged
and adds 12 egg-count cases written against parser v7 before the first run.
First run (parser v7): routing 518/523, quantity 516/523. Final (parser v8):
routing 523/523, quantity 523/523, every scored field on all 354 search cases,
zero unexpected quantity prefills. The v5 gate passes unchanged: parser v8
produces byte-identical v5 predictions to parser v7. Same-author synthetic
cases, not independent acceptance.
