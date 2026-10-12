# Food list lexical grammar v4: locale-aware amounts (#222)

Status: **Approved by the owner, 12 October 2026, with every recommended answer (Q1 to Q6; approval comment on #226). Implemented in the same PR.** The receipt follow-up is #227.
Programme: [#140](https://github.com/syamaner/WeeklyHealthReport/issues/140). Issue: [#222](https://github.com/syamaner/WeeklyHealthReport/issues/222).
Amends the parsing envelope in [food-list-import.md](food-list-import.md). Introduces the grammar identifier **`food-list-lexical-v4`**; `food-list-lexical-v3` stays defined and frozen.

## Problem

`FoodListParser` (`FoodLedgerDomain/FoodListParser.swift`, version `food-list-lexical-v3`) reads numerals without knowing the reader's decimal convention:

- A comma followed by exactly three digits is refused (`\d,\d{3}(?:\D|$)`), so an en_GB "1,500 g rice" gets no amount and an `ambiguousNumber` notice, although in British English it can only mean 1500.
- Any other comma is read as a decimal point, and any full stop as a decimal point, so a German "1.500 g Reis" (grouping for 1500) becomes 1.5 g and an English "1,5 g" becomes 1.5 g.
- A comma followed by four or more digits is read as a decimal ("1,5000" is 1.5), which no convention supports.
- Grouped numerals with more than one group ("1,000,000") or with a decimal tail ("1,000.5") are not captured as one numeral at all.

PR #225 made the review screen safe without changing the parser: `FoodListAmountText.withholdingAmbiguousAmount` (in `FoodLedgerPresentation/FoodListImportView.swift`) re-derives the parsed numeral through `FoodListParser.amountNumeral(of:)` and checks it against the device locale with `FoodAmountFieldText.canonical`, leaving the amount empty when the numeral could mean two values. The stored parse is unchanged, so the manual capture evidence written by `FoodListImportService.search` (`FoodLedgerApplication/FoodListImport.swift`) still records a v3 parse that does not say which convention the reviewer used.

## Goals

1. Read an amount exactly when the user's numeral convention gives it one value, and never guess otherwise.
2. Keep the domain parser pure: the convention is an explicit input value, never Foundation `Locale` state read inside the domain or application layers.
3. Make each list evidence record reproducible: the grammar version and the convention it was parsed under are both recorded.
4. Leave every v3 record, checkpoint line and fixture readable and byte-identical. v3 lines are never re-parsed.
5. Keep the list field, the Confirm amount field and the parser on one rule, so a numeral accepted in one place is not refused or read differently in another.

Non-goals: new units, household conversions, ranges, mixed numbers or new unicode fractions; any change to `food-query-parser-v6`, `receipt-lexical-v1` or the local inventory amount fields.

## Numeral convention

A new closed domain type, `NumeralConvention`, with persisted raw values:

| Case | Raw value | Decimal separator | Grouping separator accepted |
|---|---|---|---|
| `fullStopDecimal` | `full_stop_decimal` | full stop | comma, in groups of three |
| `commaDecimal` | `comma_decimal` | comma | none (see Q2) |
| `unspecified` | `unspecified` | either, only where both conventions agree | none |

`unspecified` is the safe fallback: a numeral with a comma or full stop gets a value only when `fullStopDecimal` and `commaDecimal` would both give the same value. It also defines how a caller with no locale (tests, tools) behaves.

### How the convention reaches the parser

- `FoodListParser.parse(_ text: String, convention: NumeralConvention)` is the v4 entry point. It reads no locale, environment or clock.
- The mapping from the device locale lives in presentation, next to the rule it must agree with: `NumeralConvention(locale:)` in `FoodLedgerPresentation`, defined as `Locale.decimalSeparator == "."` gives `fullStopDecimal`, `","` gives `commaDecimal`, anything else (for example the Arabic decimal separator) gives `unspecified`.
- `FoodListImportViewModel` already receives `amountLocale` from the composition root (`FoodLedgerCompositionRoot.foodListModel`); it derives the convention once when a list is prepared and passes it to the parser. The convention is frozen per prepared list: changing the device locale later never re-reads a prepared line.
- The existing locale-free `FoodListParser.parse(_:)` and `FoodListParser.number(_:)` keep their v3 behaviour exactly (see Receipts and Compatibility).

## v4 numeral grammar

The table is normative. "Ambiguous" means: no amount, and the line carries the existing `ambiguousNumber` notice ("Check the number format before choosing an amount."), so the needs-amount rule blocks saving until the user enters one. As in v3, a recognised unit after a leading numeral is kept so the user enters the amount in it; a trailing ambiguous amount leaves no unit (owner-confirmed clarification, 12 October 2026: the unit stays on a leading ambiguous numeral). Values are before unit scaling (kg and L still multiply by 1000).

### Separators and grouping

| Numeral as written | v3 today | v4 `fullStopDecimal` (en_GB, en_US) | v4 `commaDecimal` (de_DE, fr_FR) | v4 `unspecified` |
|---|---|---|---|---|
| `150` | 150 | 150 | 150 | 150 |
| `1.5` | 1.5 | 1.5 | 1.5 | 1.5 |
| `0.25` | 0.25 | 0.25 | 0.25 | 0.25 |
| `.5` (leading decimal point) | 0.5 | 0.5 | 0.5 | 0.5 |
| `1.500` (full stop, exactly three digits) | 1.5 | 1.5 | ambiguous (grouping for 1500, or an English decimal) | ambiguous |
| `0.175` | 0.175 | 0.175 | ambiguous (same shape) | ambiguous |
| `1.5000` (full stop, four or more digits) | 1.5 | 1.5 | 1.5 | 1.5 |
| `1,5` | 1.5 | ambiguous (decimal comma, or a mistyped group) | 1.5 | ambiguous |
| `1,50` | 1.5 | ambiguous | 1.5 | ambiguous |
| `1,500` (comma, exactly three digits) | ambiguous | **1500** (Q1) | 1.5 | ambiguous |
| `12,345` | ambiguous | 12345 | 12.345 | ambiguous |
| `1,5000` (comma, four or more digits) | 1.5 | ambiguous | 1.5 | ambiguous |
| `1,000,000` | not captured: no amount (ambiguous number, unknown unit) | 1000000 | ambiguous (two commas) | ambiguous |
| `1,000.5` | not captured: no amount (ambiguous number, unknown unit) | 1000.5 | ambiguous (both separators) | ambiguous |
| `12,34,567` (non-three-digit groups) | not captured | ambiguous | ambiguous | ambiguous |
| `1.000.000` | not captured | ambiguous (two full stops) | ambiguous (Q2) | ambiguous |
| `1.500,5` | not captured | ambiguous (both separators) | ambiguous (both separators, Q2) | ambiguous |
| `1 500` (space) | not captured: unknown unit | ambiguous (Q2) | ambiguous (Q2) | ambiguous |
| `1\u{00A0}500` (no-break space) | not captured | ambiguous (Q2) | ambiguous (Q2) | ambiguous |
| `1\u{202F}500` (narrow no-break space, fr_FR grouping) | not captured | ambiguous (Q2) | ambiguous (Q2) | ambiguous |
| `,5` (leading comma) | not an amount: missing quantity | not an amount: missing quantity | not an amount: missing quantity | not an amount: missing quantity |

Rules behind the table, matching `FoodAmountFieldText.canonical` so the parser, the list field and Confirm agree:

1. Full-stop-decimal: a comma is only grouping, and only as `^\d{1,3}(,\d{3})+(\.\d+)?$`. Any other comma is ambiguous. A full stop is always a decimal point; more than one full stop is ambiguous.
2. Comma-decimal: a comma is the decimal point (at most one). A full stop is accepted as a decimal point only when the numeral has no comma and no full stop is followed by exactly three digits; otherwise it is ambiguous. Full-stop grouping is not accepted (Q2).
3. Space grouping (U+0020, U+00A0, U+202F between digit groups) is ambiguous in every convention (Q2). Where v3 left such a line with an `unknownUnit` notice, v4 reports `ambiguousNumber` instead, which names the real problem.
4. The numeral token widens from v3's `[0-9]+(?:[.,][0-9]+)?` to capture the grouped and spaced forms above, in both the leading and the trailing amount position, so they are classified rather than half-read. A space joins a numeral only when exactly three digits follow (not a fraction), so "1 1/2" and "2 pretzels" are captured as in v3, while "2 100 g" is read as one space-grouped, ambiguous numeral. Everything after the numeral (unit dictionary, household words, typo guard, multiple-amount and pack guards, coffee and supplement rules) is unchanged from v3.

### Forms that do not depend on the convention

| Form | v3 and v4 (all conventions) |
|---|---|
| `1/2`, `3/4` (integer fraction) | 0.5, 0.75 |
| `1/0` | no amount |
| `1,5/2` or `1.5/2` (non-integer numerator) | ambiguous (v3: 0.75 for `1.5/2`; v4 requires integer fraction parts) |
| `½` | 0.5 |
| `¼`, `¾`, `⅓` and other unicode fractions | not recognised, as v3 (out of scope) |
| `1 1/2` (mixed number) | no amount, `unknownUnit`, as v3 (out of scope) |
| `100-150 g`, `1–2 apples` (ranges) | no amount, as v3 (no range grammar) |
| `half`, `quarter`, `one`, `two`, `three`, `a`, `an` | as v3 |
| `0`, negative, `nan`, `inf` | no amount, as v3 |
| `2x350g`, `2 x 500 g` | `multipleAmounts`, no amount, as v3 |
| Price-like or time-like lines (`£7.40`, `1,50`, `08:10`) | context, as v3; the context rule runs before numerals and ignores the convention |

## What is stored

### Parse output

`ParsedFoodListLine` gains two optional fields, both encoded only when present:

| Field | Type | v3 line (absent) | v4 line |
|---|---|---|---|
| `grammarVersion` | `String?` | read as `food-list-lexical-v3` | `food-list-lexical-v4` |
| `numeralConvention` | `NumeralConvention?` | read as unknown (v3 had none) | the convention the line was parsed under |

Synthesised `Codable` with optional fields keeps every existing `FoodListCheckpoint` (schema version 1) decodable, and a v3 line re-encodes with the same keys it had. The checkpoint schema version stays 1: bumping it would make `validate()` reject every saved queue.

### Capture evidence

`FoodListImportService.search` writes the manual `CaptureEvidence` as today, with two changes for v4 lines only:

- `captureMethodVersion` is the **line's** `grammarVersion` (`food-list-lexical-v4`), not the `FoodListParser.version` constant. This also closes a latent mislabel: today a line restored from a v3 checkpoint after an upgrade would be stamped with whatever the constant says at search time.
- The JSON descriptor (sorted keys) gains `"numeralConvention"` (Q4), and its `quantity` is canonical text: full stop decimal, no grouping, no trailing `.0` (`FoodAmountTextParser.editableText`), whether the amount was proposed by the parser or typed by the user. Text that does not read as one amount (empty, or refused) is recorded unchanged (clarification accepted by the owner, 12 October 2026). Under v3 the descriptor holds the field text as typed, which may be locale-formatted, and v3 lines keep doing so.

The `genericSearch` capture (`food_list_generic_search`, `v1`), the evidence `locale` field, the confirmation policy, the ledger schema and the archive formats do not change. No reader decodes the list descriptor; it is opaque `LedgerText` retained for provenance.

### v3 evidence and lines stay as they are

- Saved v3 evidence is never rewritten, re-encoded or re-parsed; it keeps `captureMethodVersion = food-list-lexical-v3` and its descriptor bytes.
- A v3 line in a restored checkpoint keeps its v3 parse and is stamped v3 when searched. It is not re-parsed under v4, even if untouched, because its original parse is the evidence the user reviewed.
- The v3 numeral rule stays available as frozen code for those lines, for `FoodListParser.number(_:)` callers and for `amountNumeral(of:)` on v3 lines.

### Reading the amount into Confirm

`FoodListImportService.confirmation(for:)` used to re-read `draft.quantityText` with the locale-free `FoodListParser.number`. For a v4 line it now uses `parsed.quantity` while the amount is the untouched proposal; the line's own convention applies only to that parse. Typed text is made canonical in presentation with `FoodAmountFieldText.canonical` under the amount field's locale, the same rule the field validated it with, when the line is handed to search or Confirm (`FoodListAmountText.reviewed`), and the application reads it with the canonical amount parser `FoodAmountTextParser.parse` (`FoodListLineDraft.amountValue`). The line's convention never reinterprets typed text, so after a region change (an en_GB queue restored under de_DE) a typed "1,250" is 1.25 g, as the German field shows it. Text the field refuses never reaches search or Confirm. The field keeps the text as typed, so the user still sees "1,5" rather than a rewritten "1.5". This removes a gap found while drafting: on en_GB, typing "1,500" into a list line passed the field check but `FoodListParser.number("1,500")` returned nil, so Confirm opened with an empty amount. A v3 line restored from an older queue keeps the frozen v3 reading of its text. Typed text saved in a queue before a region change is re-read under the current locale when the queue is restored (en_GB "1,250", meaning 1250, reads as 1.25 under de_DE); the field and Confirm still agree, and Confirm shows the amount before Log. A common-food line written by the app with exactly three decimals (for example "0.125 g") and restored on a comma-decimal device is withheld by the safety net and asks for the amount again; this fails safe and is accepted.

Common-food shortcuts that add a line are written by the app as canonical text ("0.125 g") and parsed under `fullStopDecimal`, the convention they were written in, which the line records. The portion is therefore exact under every device convention, `unspecified` included.

A stored line is recognised as v4 by the frozen identifier `food-list-lexical-v4` (`FoodListParser.v4Version`), never by the moving current-version constant, so a later grammar cannot misread v4 lines.

## Presentation-layer withholding

- For v4 lines, `withholdingAmbiguousAmount` becomes redundant: the parser already returns no amount where the device convention is ambiguous. It **stays as defence in depth** and remains required for v3 lines restored from a checkpoint, which may hold proposals from ambiguous numerals.
- `showsAmbiguousNumeral` keeps working for both: for v4 lines the `ambiguousNumber` notice on the parse is the primary signal.
- A contract test asserts the two layers agree: for every row of the golden table, a v4 parse under a convention has an amount if and only if `FoodAmountFieldText.canonical(numeral, locale:)` accepts the numeral in a locale with that convention. Any future drift fails the build.

## Receipts and other callers: out of scope

`ReceiptParser` (`receipt-lexical-v1`) calls `FoodListParser.number(_:)` for purchase counts and pack amounts, and `LocalInventoryViewModel` uses it for typed inventory amounts. Both stay on the frozen v3 numeral rule:

- Changing `number(_:)` would silently change `receipt-lexical-v1` output without a version change, which the versioning rules forbid.
- Receipts are proposals into local inventory, never consumed food, and already fail closed on "1,000 g" (`ReceiptParserTests.testEmptyOversizedAndAmbiguousNumbersFailClosed`).
- A receipt's numeral convention is the shop's, not necessarily the device's, so the device locale is the wrong input there. A locale-aware receipt grammar needs its own `receipt-lexical-v2` contract (Q3).

The known v3 receipt behaviour remains: a German receipt line "Reis 1.500 g" proposes a 1.5 g pack. It is a reviewed proposal, not a saved amount, and is recorded here as a follow-up rather than fixed by this contract. The search query grammar (`food-query-parser-v6`, which `FoodAmountTextParser` reuses) is likewise unchanged.

## Migration and compatibility

- **No database or schema change.** No new table, column, checkpoint schema version, archive contract, confirmation policy or operation type.
- Persisted format changes, all additive and confined to new data: two optional keys on `ParsedFoodListLine` inside the checkpoint blob; one new key and canonical `quantity` text inside v4 list descriptors.
- New enum values: `NumeralConvention` is new. `FoodListNotice` gains no case. An older app build opening a checkpoint written by a v4 build would drop the unknown optional keys on its next save; downgrade is not supported in general, and nothing is lost from the ledger.
- `FoodListParser.version` becomes `food-list-lexical-v4`; a separate frozen `legacyVersion = "food-list-lexical-v3"` names the old grammar for tests and stamping.
- Historical source-hash manifests under `Tools/FoodSearchQuality/` and `Tools/GenericFoodProposalEvaluation/` that list `FoodListParser.swift` are point-in-time records and already differ from the current file (PR #225 changed it); no CI step verifies them, so they are not updated.

## Contract tests

All synthetic, offline and deterministic.

1. **Golden numeral table** (`FoodListParserTests`): every row of both tables above, parsed under `fullStopDecimal`, `commaDecimal` and `unspecified`, in leading (`<n> g rice`) and trailing (`rice <n> g`) positions, asserting quantity, unit and notices. The en_GB, de_DE and fr_FR presentation mapping is tested separately (`NumeralConvention(locale:)`), including fr_FR's narrow no-break space grouping in formatted output.
2. **Field agreement** (presentation tests): the table above agrees with `FoodAmountFieldText.canonical` for en_GB, de_DE and fr_FR.
3. **Legacy v3 unchanged**: the existing v3 tests (`testAmountNumeralReportsTheParsedNumeralWithoutChangingTheParse`, `testAmbiguousAmountsNeverBecomeConsumedGrams` and the rest) run against the frozen v3 entry point unchanged, and a pinned v3 checkpoint JSON fixture decodes and re-encodes byte-identically.
4. **Evidence round trip**: a v4 line produces a descriptor whose bytes are pinned (sorted keys, `numeralConvention`, canonical `quantity`) and whose `captureMethodVersion` is `food-list-lexical-v4`; a restored v3 line produces a v3-stamped descriptor without the new key.
5. **Withholding**: restored v3 lines are still withheld under #225's rule; v4 lines with an ambiguous numeral reach the review screen already empty with the notice; typed "1,500" on en_GB reaches Confirm as 1500.
6. **Callers pinned**: `ReceiptParserTests` and inventory amount tests unchanged.
7. **Evaluation gates**: the ranked retrieval replay (`score_retrieval.py --verify-report retrieval-metrics-final-v6.json`) and `FoodQueryEvaluation` (`validate.py v5`, `synthetic-v5.json`) do not use `FoodListParser` and must stay byte-identical. The full gates in `AGENTS.md` run once the code is stable.

## Egress and HealthKit

None. The change is local parsing and local evidence. No destination, request, provider or HealthKit type is added or widened; HealthKit stays read-only.

## Decisions (answered by the owner, 12 October 2026)

The owner accepted every recommendation below.

**Q1. Should en_GB "1,500 g rice" read as 1500 g?**
Answer: **yes**, under `fullStopDecimal` only. In that convention a comma in groups of three can only be grouping, Confirm shows the amount before Log, and the list field already accepts "1,500" as 1500. Alternative: keep it ambiguous everywhere (today's behaviour), which costs British users a re-type for every grouped number. A further option, not recommended for v4, is a new non-blocking notice ("Read as 1500; check the number format"), which would add a `FoodListNotice` case.

**Q2. How are space-grouped and full-stop-grouped numbers treated?**
Answer: **ambiguous in every convention**, including fr_FR's narrow no-break space and German "1.500" / "1.500,5". Space grouping also collides with mixed numbers and two separate numbers ("1 500 g" may be a count of 1 and 500 g), and accepting German full-stop grouping would contradict the Confirm field, which refuses it. Food amounts above 999 g or ml are rare, so the cost is small. Revisit together with the field rule if users report it.

**Q3. Are receipts in scope?**
Answer: **out**. `receipt-lexical-v1` keeps the frozen v3 numeral rule; a receipt's convention is the shop's rather than the device's, and its outputs are inventory proposals, not consumed amounts. Tracked as #227.

**Q4. Should the numeral convention be recorded in evidence?**
Answer: **yes**, as `numeralConvention` on each v4 parsed line and in each v4 list descriptor. Without it a v4 descriptor cannot be re-derived: "1,500" means 1500 or 1.5 depending on the convention, and the evidence `locale` identifier alone depends on how a future OS maps that locale.

**Q5. What does a device with an unrecognised decimal separator get?**
Answer: **`unspecified`**, which accepts a numeral only where both conventions agree, so no such device sees a guessed value.

**Q6. Should Confirm read list amounts from the untouched parse or canonical typed text (instead of re-parsing field text with the v3 rule)?**
Answer: **yes**, as specified above; it fixes the en_GB "1,500" typed-text gap and keeps one numeral rule per amount.

## Delivery

Delivered on the contract's own branch and PR (#226), with `food-list-import.md` updated to describe v4. Tests: `FoodListLexicalV4Tests` (golden tables, v3 freeze and encoding), `CoFIDGenericFoodSearchTests` (evidence bytes, v3 label, Q6 prefill) and `FoodListImportPresentationTests` (locale mapping, field agreement, restored v3 queue, Confirm end to end). Architecture gate: domain owns `NumeralConvention` and the grammar; application stamps the line's own version; presentation owns the locale mapping; the composition root is unchanged apart from passing the locale it already passes.
