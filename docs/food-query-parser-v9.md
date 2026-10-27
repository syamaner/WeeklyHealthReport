# Food query parser v9: hard boiled eggs and numbered pieces

Fixes #317 and the query-parse part of #315. A bounded change to the count
grammar of the pure search parser (`FoodQueryParser`).

## Rule

`food-query-parser-v9` makes two additions to the v8 count grammar.

1. **Hard boiled.** `hard boiled` and `hard-boiled` are accepted between a count
   and a counted whole item, alongside `boiled` and `soft boiled`. "2 hard
   boiled eggs", "two hard boiled eggs", "a hard boiled egg" and "2 x hard
   boiled eggs" are read as item counts. Under v8 the number was left
   unresolved, so Confirm opened with an empty amount and offered "Use 2 from
   your description" instead of pre-filling the count, unlike "2 eggs".
2. **Numbered pieces.** A numeral or the number words one, two and three (or
   zero, which rejects) followed by `piece` or `pieces`, an optional `of`, and
   a counted whole item is read as that count: "3 pieces banana", "3 pieces of
   banana", "2 pieces apple". This is the unit Confirm already shows for "3
   bananas" ("3 pieces"). Under v8 "pieces" was always a household portion, so
   the query asked for clarification and searched for "3 pieces banana".

Boundaries that keep their v8 route:

- "a piece of banana" stays a portion question: an article names a part, not a
  whole item.
- Pieces of anything outside the counted whole-item list ("3 pieces cheese",
  "3 pieces of cake") stay a household portion.
- A count with a mass ("2 hard boiled eggs 100g", "3 pieces banana 120g") still
  asks which basis to use; zero rejects; "2 hard bananas" is not a count.
- The food text is unchanged from the uncounted form: "2 hard boiled eggs"
  hands retrieval the same food and `preparation=boiled` attribute as "hard
  boiled eggs", so the same records are found.

## Counts stay basis-only

A count is never a mass. No portion weight, egg size, energy or nutrient value
is inferred. On Confirm the amount is the count with no conversion, the user
can still edit it, and Log stays governed by the existing count rules (a
measured amount, a compatible source portion or an explicitly chosen portion
guide). Nothing is saved automatically.

## Versions and stored values

`food-query-parser-v9` is a code constant. As with v8, the parser version is
not stored in food records, evidence or exports, so there is nothing to
migrate; the original query text remains the stored evidence. The list grammar
(`food-list-lexical-v5`), which already reads "3 pieces banana" as a count, is
unchanged.

## Evaluation

`Tools/FoodQueryEvaluation/synthetic-v8.json` keeps the 542 v7 cases unchanged
and adds 16 count-form cases (`build_v8.py`, family `count_forms_v8`).
Expectations were written alongside the parser change; the first run used
parser v8 from `main`, whose hash the manifest records.

| Run | Routing | Quantity | Search cases, all fields | Unexpected prefills |
|---|---:|---:|---:|---:|
| v8 first run (parser v8) | 549/558 | 549/558 | 372/381 | 0 |
| v8 final (parser v9) | 558/558 | 558/558 | 381/381 | 0 |

Parser v9 produces byte-identical v7 predictions to `predictions/v7-final.json.gz`,
and the v7 gate still passes. Same-author synthetic cases, not independent
acceptance.
