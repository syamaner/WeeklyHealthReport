# Pasted food-list import

Issue: [#127](https://github.com/syamaner/WeeklyHealthReport/issues/127)

## Flow

**Food Log → Paste or dictate food list** prepares a newline-separated list for review.
Every nonblank line keeps its original text and line number, including duplicates.
Blank lines remain in the original input and do not become food items. A compact
queue shows saved, pending, unresolved, failed, deferred, declined and context
states. Its progress message counts food lines separately from context and never
calls a partially saved list complete.

The selected line shows the original, editable name/modifiers, consumed amount,
unit and preparation. Find matches uses the existing offline search, with exact
saved-food lookup first. The user chooses a candidate and enters the shared
confirmation flow. Each item requires explicit acceptance before saving. The
confirmation shows the original line, parser notices and the actual saved item
and amount. Next line advances the queue. Saved rows cannot be saved again.

Unsaved input, edited lines, row dispositions, stable IDs and selection are saved
locally and resume after restarting the app. Search results and unfinished
confirmation screens must be reviewed again; ledger reconciliation recognises
committed saves even if their checkpoint was interrupted. Saved ledger entries
remain durable. Starting another list explicitly
confirms discarding the current queue; it never deletes saved food.

## Architecture gate

- `FoodLedgerDomain.FoodListParser` owns a pure, versioned lexical grammar and
  parsing notices. It has no database, UI, network or provider dependency.
- `FoodLedgerApplication.FoodListImportService` turns an editable line into an
  existing generic search request and populated confirmation. It records original
  text, line number, corrected search text, quantity, unit, preparation and notices
  in manual capture evidence. JSON string encoding preserves source whitespace.
- `FoodLedgerPresentation` owns selection, correction, per-line state and the
  review queue. The app composition root supplies search, clock, IDs and saving.
- The existing ledger owns atomic saves, source provenance and immutable record
  versions. Each row retains one operation ID and idempotency key. A retry first
  recovers a committed confirmation, including when its previous response was
  lost, before generating any new records.

The parser can evolve under a new parser version without changing the accepted
CoFID matcher or ledger schema. Input modes and search adapters remain replaceable
at the existing application boundaries. Import checks and tests enforce package
dependencies. No automatic match acceptance or alternate save schema is added.

## Parsing envelope

`food-list-lexical-v2` (and v3, v4, v5, v6) handles compact/spaced gram and millilitre forms, their plural
and regional spellings, explicit kg/L scaling, decimal points, unambiguous decimal
commas, simple fractions, `1x` counts, half/quarter and one/two/three counts, and
bulleted lines. Articles `a` and `an` remain counts, except before a vague portion
word or a household container under v5 and v6 (see below). A single trailing metric
amount is supported when no leading amount is present; competing amounts stay
unresolved. A small unit dictionary recognises common spellings. One-edit
matches to long unit words are flagged for correction; short units such as mg are
never fuzzily changed into g. A bounded food spelling dictionary offers explicit
opt-in query corrections without changing the frozen search normalisation.

Times, meal headings, price-like standalone decimals and recognisable narrative
lines remain visible as context. The user can reclassify any such line as food.
Times do not backdate a log: confirmed entries use the existing save-time date.
The input limit is 200 lines and 30,000 characters, with rejection rather than
silent truncation.

New lists are parsed under `food-list-lexical-v7` ([contract](food-list-lexical-v7.md),
#359), which is v6 with the household-measure rule widened to the other containers (bottles,
jars, tubs, cans, tins, cartons, bowls, bags, sachets, plates) and household measures (slices,
scoops, portions, servings, packets, dollops, spoons): each gives no amount and the
household-measure notice and leaves the food name ("2 slices of bread" searches "bread", "a
bottle of water" is no longer a count). With no amount, "of" must follow ("slices of bread",
but "cup noodles" keeps its name).

`food-list-lexical-v6` ([contract](food-list-lexical-v6.md), #353) is v5 plus household
containers. Cups, mugs, glasses, pots and packs, under
the container rule search uses (`HouseholdContainerRule`), give no amount and the
household-measure notice and leave the food name: "2 mugs of tea" searches "tea", and a
mass or volume next to a container ("250 ml mug of milk") is withheld as in search. A mug
cake keeps its name, and glasses, pots and packs need "of" ("a pot noodle" is as v5).

`food-list-lexical-v5` ([contract](food-list-lexical-v5.md), #140 decision B3) is v4 plus
vague portion words. "A handful of", "a pinch of",
"a dash of", "a splash of", "a drizzle of", "a bit of" and "a few" (with a number or
article in front, or none) are never read as a definite count: the line keeps its food
name, has no amount and carries the household-measure notice, so the needs-amount rule
blocks saving until the user enters a measured amount. Everything else is as v4.

Under `food-list-lexical-v4` ([contract](food-list-lexical-v4.md),
#222), which v5 keeps unchanged for numerals, the review screen maps the device locale's decimal separator to a numeral
convention (full-stop-decimal, comma-decimal or unspecified) and passes it to the pure
parser, which reads numerals with the same rule as every other amount field. An
English "1,500" is 1500; a German "1,5" is 1.5. A numeral that could mean two amounts
(a German "1.500", which may be grouping for 1500; an English "1,5"; any space
grouping) has no amount and the number format notice, and the existing needs-amount
rule blocks saving until the user enters one. Each line records its grammar version
and convention, and its capture evidence is stamped with them, with the amount as
canonical text. A typed amount is made canonical with the amount field's locale, the
rule the field validated it with, before it reaches search or Confirm; the line's own
convention applies only to its untouched parsed amount.

Lines saved in a queue by an earlier build keep their `food-list-lexical-v3` or
`food-list-lexical-v4` parse and label and are never re-parsed, so a v4 line that read
"a handful" as one count keeps that proposal for the user to review. For v3 lines, and
as a safety net for v4 and v5 lines restored in another locale, the review screen still checks the numeral behind each untouched
parsed amount against the device locale and withholds an ambiguous one (#225).

Uncertain numbers, household measures, pack multipliers and multiple amounts leave
the consumed amount empty. Coffee-ground amounts remain preparation information.
Spoon and slice measures remain unresolved; split spoon names are recognised. Negated preparation terms stay
in the query and do not assert cooking or an inferred opposite state. Roast and
toasted are recognised cooking states; coffee roast describes grounds. Known
supplement names add a review notice without establishing product identity or dose.
The search-query parser (`food-query-parser-v5`) likewise retains negated cooking
terms instead of extracting them as affirmative preparation attributes. A single
exact gram amount can accompany a slice descriptor without a household conversion.
Unmeasured slices and competing amounts stay unresolved. Narrow rye/wheat/wholemeal
bread conjunctions are symmetric in word order; separate food combinations remain
subject to clarification. Parser search eligibility does not imply that a compatible
catalogue record exists or that a confirmation is accepted.
Count-to-mass and volume-to-mass conversions are never inferred. Raw/cooked state
is carried to search and checked against saved-food reuse as well as CoFID.
Other preparation terms, brands, percentages and recipe descriptions stay in the
editable query. Supplements require an exact saved supplement; homemade mixtures
require a saved recipe or separate ingredient logging. Missing evidence produces
an unresolved row, not fabricated nutrition. Generic misses offer another search
or deferral; the deferred label-photo route is not advertised.

## Validation and limits

Synthetic tests cover grammar variants, original whitespace/order, duplicate water
entries, mixed notes, coffee preparation, typo correction, branded text, recipes,
count-only food, ambiguous fish, supplements and cooked-weight food. Search tests
exercise the real bundled CoFID projection and preserve missing consumed amounts.
Review tests cover edits invalidating candidates, partial batches, explicit
acceptance, save failure/retry, decline/defer, context correction and saved-row
locking. Shared memory/SQLite contracts prove replay recovers the same log item.

Local package tests, Xcode analysis and simulator tests validate software behavior.
The user's physical-device test is deferred. This feature has no Drive, provider,
HealthKit, voice, handwriting or label-OCR dependency.

### Evidence retained at generic search

List search retains the original manual descriptor and a distinct `genericSearch`
capture containing the reviewed query (`food_list_generic_search`, method version
`v1`). Both are linked to the selected source candidate and retained through save
and reopen. Reviewed speech text keeps its manual capture method. This supplies the
existing generic-estimate confirmation contract without inventing missing source
identity or changing exact-product admission. Explicit acceptance and consumed
quantity/conversion review are still required.
