# Pasted food-list import

Issue: [#127](https://github.com/syamaner/WeeklyHealthReport/issues/127)

## Flow

**Food logging → Paste Food List** prepares a newline-separated list for review.
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

Unsaved review state survives navigation within the running app through the
composition root. It is **session-only**: restarting the app discards unsaved
lines. Saved ledger entries remain durable. Starting another list explicitly
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

`food-list-lexical-v1` handles compact/spaced gram and millilitre forms, their plural
and regional spellings, explicit kg/L scaling, decimal points, unambiguous decimal
commas, simple fractions, `1x` counts, half/quarter and one/two/three counts, and
bulleted lines. A small unit dictionary recognises common spellings. One-edit
matches to long unit words are flagged for correction; short units such as mg are
never fuzzily changed into g. A bounded food spelling dictionary offers explicit
opt-in query corrections without changing the frozen search normalisation.

Times, meal headings, price-like standalone decimals and recognisable narrative
lines remain visible as context. The user can reclassify any such line as food.
Times do not backdate a log: confirmed entries use the existing save-time date.
The input limit is 200 lines and 30,000 characters, with rejection rather than
silent truncation.

Uncertain numbers, household measures, pack multipliers and multiple amounts leave
the consumed amount empty. Coffee-ground amounts remain preparation information.
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
