# UX revamp phase 3: Add food, search and web lookup (#196) architecture gate

Status: **draft for owner review, 11 October 2026; architecture gate passed with changes, folded in.** Contract: [generic-food-review-manifest-v2.md](generic-food-review-manifest-v2.md) (the specification's "Single-step web review"). Specification: [ux-revamp-v1.md](ux-revamp-v1.md). Wireframes: [`AddFood`](designs/ux-revamp-v1/AddFood.dc.html), [`SearchResults`](designs/ux-revamp-v1/SearchResults.dc.html), [`WebLookup`](designs/ux-revamp-v1/WebLookup.dc.html). Retrieval quality stays with #100.

Contract tests land first; screens follow. Owner decisions P1 to P6 (below) and Q1 to Q5 (contract section 8) are approved before production code.

## Responsibilities and files

| Layer | Owns in this phase | Files |
|---|---|---|
| Domain | Nothing new | none |
| Application | Manifest V1 (frozen) and V2, admission v6 with recorded gate, `prepare(review:proposal:scope:)`; `FoodWebLookupReviewContent`; `FoodConfirmationService.relogInput(_:)`; `FoodRecentItemsProjection` and `FoodRecentItemsService`; `FoodSearchResultSummary` (structured values); archive contract 5 | `ReviewedFoodProposalConfirmation.swift`, `GenericFoodProposalReview.swift`, `FoodConfirmation.swift`, new `FoodRecentItems.swift`, new `FoodSearchResultSummary.swift`, `CanonicalFoodArchive.swift` |
| Infrastructure | Migration `v5_review_manifest`; open-policy identity `food-ledger-v5` (`FoodLedgerGRDBStore.swift:1151`) | `FoodLedgerGRDB/FoodLedgerMigrations.swift`, `FoodLedgerGRDBStore.swift` |
| Presentation | Add food screen; Search results restyle and result-row formatter; Web lookup screen; copy | new `AddFoodView.swift`; `GenericFoodSearchView.swift`, `FoodSearchStatusPresentation.swift`; `GenericFoodProposalReviewView.swift` |
| Composition root and app | `.addFood` route, entry wiring, injected digester for recent items, in-memory search diagnostics | `AppRoute.swift`, `FoodLedgerCompositionRoot.swift`, Home and Settings views |

Dependency direction: Presentation → Application → Domain; GRDB → Application ports → Domain. Views format application values; they never decide eligibility, scale energy or de-duplicate. The FoodLedgerKit import-boundary check covers the new files.

## Screens

| Screen | Wireframe content | Today's code | New or restyled |
|---|---|---|---|
| Add food | Field "Food and amount"; rows Scan barcode, Paste or dictate a list, Favourites; Favourites; Recent with "Last: 150 g · yesterday" and energy; nothing logs until Log | Separate Home entries for `.genericFoodSearch`, `.barcodeFoodCapture`, `.foodListImport`, `.commonFoods` | **New** screen and route `.addFood`; the field submits to Search results; rows reuse existing routes; Recent is new; Favourites per P2 |
| Search results | Amount and preparation chips; one progress line with Stop; "Stopped. These are the matches found so far."; Best matches; "Added from online database"; "Not what you ate?" (web lookup, barcode); raw/cooked footnote | `GenericFoodSearchView`: parsed quantity, preparation picker, progress with Stop, "Added online" caption, "Review web nutrition" button, in-screen Developer tools with scores and record IDs | **Restyled**: chips over `parsedQuery.quantity` and `preparationFilter`; rows formatted from `FoodSearchResultSummary`; online group as its own section; web lookup only under "Not what you ate?"; diagnostics move to Settings › Developer tools (P4) |
| Web lookup | Market in header; "Found 3 sources · 1 suits this food"; suggested source, match type, values and "Not stated", quotes behind a disclosure, "Use this source"; other sources with plain status; egress footnote | `GenericFoodProposalReviewView` list plus `FoodProposalDetailView` with three toggles; market picker on screen; uncalibrated confidence shown | **Restyled and merged** per manifest v2; market read-only, set in Settings (`.foodMarket`); confidence, rejection reasons and source attempts move to Developer tools; key missing, no usable source, conflicting source and unavailable states kept |

Search results and Web lookup are sub-flows, not restorable routes: restoring never re-runs a paid or online request. `.addFood` restores with an empty field.

## Search result rows

`FoodSearchResultSummary` (application) returns structured values: a closed source-family enum (UK reference, US reference, Taiwan reference, packaged product, your foods), preparation, raw source strings, and either `energy(kcal, for: quantity)` or `basisOnly(basis)`. Presentation formats "UK reference · cooked · 248 kcal for 150 g".

- Energy for the amount only when energy is exact or augmented and the basis is per 100 g with a gram amount, or per 100 mL with a millilitre amount (only mL is normalised). Everything else, including oz, counts, named servings and mL against per 100 g, is basis-only. Unknown energy shows no figure.
- Rounding: kcal to the nearest whole number, half away from zero, after scaling.

## Recent foods

No projection exists (Home has only day previews). Two parts:

- **`FoodRecentItemsProjection`** (pure, from `LedgerMutation`): current heads only, removed and superseded excluded. De-duplication key: `sourceReleaseID + recordID` of the current resolution; the row shows the source name, so a corrected product name is not shown (documented difference). `occurredAt` drives window and order; ties break by log item ID. Last amount is the head's entered value and unit. Estimate status from `FoodEntryEstimateStatus`.
- **`FoodRecentItemsService`** (application, injected digester): filters items through `relogInput`, omitting any whose source cannot be restored, and applies the P1 limit.

Tapping opens Confirm as a **new** entry from `relogInput` (source identity, edible quantity unknown, decisions asked again, value and unit prefilled). It reuses existing manifest evidence and never writes a new manifest. Nothing logs on a tap.

## Entry routes (all reach the same Confirm)

Search result; Web lookup via `prepare(review:proposal:scope:)`; barcode direct and via search; paste or dictate per item; recent item via `relogInput`; Favourites as today (P2). A simulator UI test per route asserts it lands on Confirm.

## Owner decisions (recommended, awaiting approval)

| ID | Decision | Recommendation |
|---|---|---|
| P1 | Recent list size and window | 10 items within 30 days, by `occurredAt` |
| P2 | Favourites before #198 | Favourites row opens Common foods; an empty "No favourites yet" section until #198 |
| P3 | What "last amount" carries | Value and unit only |
| P4 | Search diagnostics | In-memory snapshot of the last search for Developer tools; never persisted, never holds a credential |
| P5 | Energy for the amount | The tightened rule above |
| P6 | Retired `.gemini` search stage | Leave it in this phase |

## Risks

- **Spec gap:** "favourites listed" depends on #198; P2 keeps the slot honest.
- **Gate regressions:** the gate moves into the application and is recorded; tests cover each blocking outcome at preparation and from the record.
- **Older binaries:** contract 5 and schema 5 prevent downgrade and restore into the phase 2 build; release note.
- **Corrections on re-log:** a corrected exact product asks for identity details again; carrying corrections is #198.
- **Accidental egress:** no per-keystroke search; restored routes never search; web lookup stays explicit.
- **Raw and cooked:** chips change the filter before ranking; stale responses stay rejected by the coordinator token.
- **Accessibility:** 44 pt chips and rows, progress announced once, Stop reachable by VoiceOver.

## Tests

1. **Pure:** recent projection (removed, superseded, de-duplication, backdated entry ordering, remove then restore, window, last amount, estimate status, `Europe/London` midnight); `FoodSearchResultSummary` structure tests (oz, count, named serving, unknown energy, mL against per 100 g, rounding) separate from formatter golden strings; `FoodWebLookupReviewContent` golden outputs.
2. **Contract:** manifest v2 section 7 items 1 to 13; recent service omits unrestorable sources; existing `ProgressiveFoodSearchCoordinatorTests` and `FoodSearchEscalationPolicyTests` stay green.
3. **View model:** no per-keystroke search; chip edits re-run with the filter; Stop keeps matches; "Use this source" disabled while scope is unset, including representative-only; a market change while a result is open invalidates it (stale query); key change cancels; recent tap prefills and does not save; the diagnostics snapshot holds no credential.
4. **Native render (style of `testConfirmScreenLeadsWithFoodAndLogThenNutritionWithoutDefaultIntakeOrSourceIDs`):** Add food with and without recents; Search results with chips, plain rows, online group and "Not what you ate?", no scores or record IDs; Web lookup with one suggested source, values and "Not stated", one "Use this source", quotes collapsed, no confidence, and the egress footnote; extend the two existing OpenRouter render tests.
5. **Simulator UI:** each entry route reaches Confirm; Dynamic Type at accessibility sizes; VoiceOver order.
6. **Gates:** FoodLedgerKit and simulator suites, Xcode static analysis, boundary check, `git diff --check`; device pass with the reported queries.
