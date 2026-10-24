# Food quick add contract v1 (#198)

Status: **approved by the owner on 12 October 2026 with every recommended answer (Q1 to Q11); implemented in #198 (PR #209).** Rebase notes for phases 3 and 4 are in the [phase plan](ux-revamp-phase-5-favourites.md#rebase-notes-12-october-2026-after-phases-3-and-4-merged).
This is the change [ux-revamp-v1.md](ux-revamp-v1.md) calls "Quick add" (section "Contract changes > 4"). It builds on [food-confirmation-contract-v5.md](food-confirmation-contract-v5.md) (one Log action, `FoodLogPolicy`, D4 and D6) and sequences after phase 3 (#196, PR #207: recent foods, `FoodConfirmationService.relogInput`, food archive contract 5, schema `food-ledger-v5`). Phase plan: [ux-revamp-phase-5-favourites.md](ux-revamp-phase-5-favourites.md). Wireframes: [`Favourites.dc.html`](designs/ux-revamp-v1/Favourites.dc.html), [`QuickAdd.dc.html`](designs/ux-revamp-v1/QuickAdd.dc.html).

**Entry condition:** PR #207 is merged and its archive contract 5, `relogInput` and `minimumContractVersion` are as described here. If not, sections 3 and 6 are re-derived before implementation.

**Amendment to the specification:** ux-revamp-v1 says quick add "logs a new version". Quick add creates a **new log item at version 1**; it never supersedes an earlier entry.

## Baseline at `9fc734d` plus PR #207

| Concept | Where it lives today | Can it hold a source-bound favourite? |
|---|---|---|
| Common foods "favourites" | `InventoryProductVersion.favourite` and `usualPortion` in the local inventory (`LocalInventory.swift`, inventory backup format 2), shown by `CommonFoodsView` | No. Names, aliases and usual portions with no source, product, resolution or evidence. "Quick-add for review" asserts nothing. |
| Personal library | `LibraryEntry` and `LibraryEntryVersion` (`IdentityAndRecords.swift`), created at a first exact confirm from the candidate's `libraryAliases` | Not safely. A library entry is an **exact alias** found by `exactLibraryEntries(alias:)`. v5 D6 and v2 forbid exact reuse of estimates. |
| Recent foods (PR #207) | `relogInput(_:)` restores the saved entry's **source** candidate and re-verifies reviewed web manifests; `relogSource: LogItemID` lets `save` skip evidence retained by that entry's current head | The construction pattern is reused; the evidence-skip mechanism is not sufficient (section 3). |
| Water | `NutrientKey.water` (mL) and `ItemClass.water` exist; `FoodIntakeSummary` sums within one reporting date | No reference record. |

## 1. What a favourite stores

Favourites are new append-only food-ledger records, not inventory rows and not library entries.

```
FavouriteEntry        { favouriteID, createdAt }
FavouriteVersion      { favouriteVersionID, favouriteID, ordinal, supersedesFavouriteVersionID?,
                        binding, label, defaultAmount, state (active | removed), createdAt }
FavouriteBinding      = .savedEntry(logItemVersionID)
                      | .reference(ReferenceFoodID)          // only .plainWaterV1 in this contract
FavouriteAmount       { value (finite, > 0), unit (QuantityUnit) }
FavouriteArrangement  { arrangementVersionID, ordinal, supersedes?, order: [FavouriteID], createdAt }
```

- **Binding by log item version only.** `.savedEntry` stores one `LogItemVersionID`. Product version, resolution version and evidence are read through that immutable version (a read-only reader addition, `foodConfirmation(logItemVersionID:)`), so the binding cannot hold inconsistent IDs. The store and strict decoding reject a binding to a version that does not exist or whose composition is not `.product` (for example a `.removed` version).
- **Default amount.** Value and unit only, as `FoodConfirmationService.lastEnteredAmount` reads them. No conversion, plate or decision is carried.
- **Label.** Display name, defaulting to the **source candidate** name (what `favouriteInput` rebuilds, not a corrected product name); never alters identity, nutrients or provenance.
- **Estimate status is derived, never stored**, from `FoodEntryEstimateStatus` over the pinned stored confirmation. A favourite made from an estimate keeps the estimate label and provenance.
- **Display order.** One `FavouriteArrangement` lists favourites in quick-add order. The first four are the Home chips and "On Today's quick add"; the rest are "Other favourites". Reordering writes one arrangement version and no favourite version. Removed favourites are dropped even if listed; active favourites missing from the arrangement are appended by `createdAt`.
- **Competing heads** of any `FavouriteVersion` chain **or** of the `FavouriteArrangement` chain stop the Favourites projection with an explicit failed state, as the intake projection does for log heads. Nothing chooses by ordinal or time.
- **Strict decoding** rejects a non-positive or non-finite amount, an empty label, a duplicate ID in `order`, an unknown binding or reference case and a `.reference` binding whose unit is not mL.

### Creation and idempotency (Q2)

A favourite is created from a logged entry: "Save as favourite" on Confirm (the v5 D4 slot), or from a saved entry or recent food. "Create a favourite from Food search, Barcode or Web lookup" opens that route with Save as favourite preset; the Confirm bar reads "Log and save favourite". The log save is unchanged; the favourite is written by a **separate** operation `save_favourite_v1` immediately afterwards, so confirm operation payloads stay byte-identical to v5.

- **Idempotency.** The ledger dedupes on `OperationID`. `FavouritesService.saveFavourite` first looks up an active favourite already bound to this log item version and returns it without writing. Otherwise it commits with an `OperationID` derived deterministically from the log item version (the idempotency key `save_favourite_v1:<logItemVersionID>` is metadata only), so a retry after a lost response returns `.idempotent` with the same favourite. After removal, favouriting the same version writes a new favourite with a fresh operation ID.
- **Failure between the two operations:** the entry stays logged and the screen says "Logged. Favourite not saved" with Try again. An app kill between them is accepted; recovery is "Save as favourite" from the saved entry.
- Estimate entries may be favourites (D6 forbids exact aliases, not favourites). Photo routes show "Not yet available" until #93 or a separately approved image contract.

## 2. Relationship to common foods and the library

- **New record, no reuse of either store.** Reusing inventory favourites loses source binding; reusing `LibraryEntry` would make every favourite an exact alias. Favourites never appear in `exactLibraryEntries(alias:)` and never feed search.
- **No alias growth.** The library alias is created only at the first exact confirm, as today. `favouriteInput` strips the source candidate's `libraryAliases`, and the water input has none, so N quick adds create no `LibraryEntry` or version.
- **No migration.** Inventory favourites and usual portions are untouched (backup format 2) and cannot be converted, as they carry no source. Q6 covers the wording.
- **Append-only edits.** Rename and default-amount changes write a new `FavouriteVersion`; removal writes a `removed` version (a tombstone). Changing the bound food is a new favourite. No favourite operation contains a log, product, resolution or assertion record, so past entries cannot be rewritten by construction.

## 3. Quick add: a one-step confirmation sheet

Quick add is a sheet presenting a pre-built `FoodConfirmationState`. Tapping a chip or row only opens it; **nothing is logged on a single tap**. Log in the sheet is the v5 explicit acceptance of the food, amount, time and source shown.

### Input construction (relogInput style)

- `.savedEntry`: `favouriteInput(_:)` reads the pinned log item version and restores it through the same code as `relogInput` (`restoredConfirmationInput` generalised to a pinned version), re-verifying reviewed web manifests, carrying only the source candidate, stripping `libraryAliases`.
- `.reference(.plainWaterV1)`: the fixed reference input from section 4.
- Quantity is the chosen preset or custom amount in the favourite's unit; `occurredAt` is nil for Now or the chosen time.
- Every quick add writes a **new** product, product version and resolution, exactly as a Confirm save of the same input does; it never reuses the pinned entry's product or resolution IDs.

### Named save change: retained evidence by existence (replaces "save unchanged")

`relogSource` keys evidence reuse on a `LogItemID` head, which is nil after removal, differs after correction or re-timing, and does not exist for water. `FoodConfirmationService.save` therefore changes in one named way: **before writing, each input evidence member that already exists in the store and is byte-identical is skipped**, via a reader check, exactly as `missingReleases` already skips stored source releases. An existing evidence ID with different bytes still fails as `immutableRecord`. Comparison uses the canonical encoder bytes of the stored and input member (not `Equatable`, unless a test proves it covers every field). The check is an optimisation only: if it passes but the insert collides (a race), the insert still fails as `immutableRecord`; nothing is overwritten. The operation's pinned `affectedIDs` reflect exactly what the skip decides, tested. `relogSource` is removed (its PR #207 tests move to the existence rule); the rule covers recent foods, favourites and water. It does not change any operation type, payload shape or hash of a save that writes new evidence.

The operation type, assertion, `methodVersion = food_confirmation_v5`, reporting day and alias rule are otherwise whatever Confirm would produce for the same state. Quick add adds **no new log operation type** and records no favourite reference on the entry (Q4).

### Eligibility (pure `QuickAddPolicy`, application layer)

The one-step sheet is offered only when all hold:

1. the input rebuilds and re-verifies; otherwise the favourite shows "Source can no longer be verified" and offers removal;
2. the pinned entry's derived `FoodEntryEstimateStatus` is **not** estimate, **and** `FoodLogPolicy.savesEstimate` for the rebuilt state is false;
3. the pinned entry carried **no correction or re-resolution**: its product version ordinal is 1, no correction assertion is attached, its candidate decision outcome is not `.rejected`, and its effective resolution version equals the original one. Any of these opens Confirm, because the rebuilt source candidate drops the correction;
4. `FoodLogPolicy.requirements` for the state with the default amount and Now contains only the sheet-resolvable cases below.

| May appear in the sheet (blocks Log, fixed inline) | Never in the sheet: opens the full Confirm |
|---|---|
| `amountMissing`, `amountTextInvalid` (custom amount, including the Q10 bound), `occurredAtInFuture`, `occurredAtTooEarly` (same seven-day window as v5) | `decideDifference`, `sourceIdentityMissing`, `recipeServingsRequired`, `sourceServingsRequired`, `measuredWeightMissing`, `weightBasisMissing`, `retainedWeightNeedsConfirmation`, `countNeedsMeasuredAmount`, `emptyPlateWeightMissing`, `plateNeedsGramTotal`, `plateNotLighterThanTotal` |

Ineligible favourites open the full Confirm with the same state for fresh explicit confirmation (specification and v5 D6). Re-resolution keeps strict identity requirements. The service evaluates `FoodLogPolicy` again at save. The sheet's "Edit" opens Confirm with the current sheet state.

### Sheet content

Title "Quick add <label>", food line, presets, Other amount, When (Now by default), a plain source line and "Log <amount>". When the sheet opens from Add food on a past Food Log day, When starts on that day at the current clock time instead (owner decision D, 13 October 2026; presentation only, `FoodLogPolicy` still decides the save). Estimates never reach the sheet. Water presets: 150, 250, 330 and 500 mL. Food favourites offer the default amount plus Other amount in the same unit; a unit change opens Confirm (Q5). The Q10 upper bound is a **sheet-only input bound** surfaced as `amountTextInvalid`; Confirm is not bounded and no policy version changes.

## 4. Water: one fixed reference record

- **Source release.** Source ID `weeklyhealthreport.reference`, release `plain-water-v1`, `releasedAt` 2026-10-11T00:00:00Z, schema `reference-food-v1`, pipeline `plain-water-v1`, licence "App-defined reference; no third-party data", attribution "WeeklyHealthReport plain water reference". `artifactHash` and `manifestHash` are the SHA-256 of the constant canonical definition JSON compiled into the app, computed with the injected digester and pinned by a golden test.
- **Evidence.** One member with a fixed `EvidenceID` constant, new `CaptureKind.referenceDefinition` (`reference_definition`), fixed `capturedAt` 2026-10-11T00:00:00Z, locale `en_GB`, capture method `app_reference_definition` version `plain-water-v1`, payload `.descriptor("weeklyhealthreport.reference/plain-water-v1/plain-water")`, `byteHash` the definition hash. The first water save writes it; later saves skip it by the existence rule in section 3.
- **Identity.** Exact and fully known: item class `water` (existing case), preparation `as_sold`, every other facet `not_applicable`, so v5 raises no difference or missing identity and the save is never an estimate. Provenance kind is the new `app_reference_definition`, record ID `plain-water`.
- **Resolution (Q1).** Basis `per100Millilitres`; water 100 mL exact; energy 0 kcal exact; protein, carbohydrates, total fat, saturated, monounsaturated and polyunsaturated fat, sugar and fibre 0 g exact and cholesterol 0 mg exact (implied by fat and carbohydrate being exactly 0); minerals, vitamins and caffeine omitted, so unknown. Effect on completeness: energy, protein, carbohydrates, fat, fat subtypes, sugar, fibre and cholesterol stay complete on a day of only water; sodium and other minerals become known minimums. **Amended 24 October 2026 (#304, [health-food-and-water-v1.md](health-food-and-water-v1.md) decision 10):** the zeros stay true of each water entry, but they are no contribution to day totals, so a water-only day has no known energy or macros (never 0) and water never makes a food's unknown nutrient known. Amounts are mL only; no density is inferred.
- **Versioning.** Immutable; any change is `plain-water-v2` with a new release and evidence ID, and v1 entries keep resolving to v1.
- **Plain water entry predicate.** A current log head whose effective resolution has provenance `app_reference_definition`, source release `plain-water-v1` and record ID `plain-water`. A corrected entry whose resolution no longer has that provenance leaves the set.
- **Built-in water (Q7).** A built-in Water 250 mL quick-add item is shown first unless a `FavouriteVersion` chain with binding `.reference(.plainWaterV1)` exists (active or removed). Logging from it writes only the log entry, never a favourite. Editing or reordering it writes the favourite (and arrangement) records; removing it writes the favourite record plus a `removed` version, which hides the built-in item for good.
  - **Amendment (owner-approved 13 October 2026).** Removing water is confirmed first, and once every plain water chain is removed Favourites offers "Add Water to quick add", which appends a new `active` version (`revise_favourite_v1`, same label and default amount) to the earliest-created removed plain water chain; it never starts a second chain, writes nothing while water is offered, and the built-in item stays hidden.

### Daily-first aggregation in mL

- Contributions use the existing `FoodIntakeSummary` scaling (consumed mL over the 100 mL basis).
- Within a reporting date, current heads are summed first; removed and superseded versions contribute nothing; backdated entries count on the date derived from `occurredAt`.
- An empty day shows No data, not 0 mL. Any multi-day figure averages daily totals with equal weight; none is added in this phase.
- Home's water figure is **plain water logged** (Q8), the sum over the plain water predicate, complete by construction. The dietary water nutrient total keeps the existing known-minimum rule.
- HealthKit is untouched: nothing is written to Health; `toShare` stays empty.

## 5. Where favourite records travel

`LedgerMutation` uses synthesised `Codable` and is encoded in operation payloads (`payloadHash`) and in `CanonicalFoodProjection.records`, which feeds the archive and the Daily JSON food projection. Adding keys to it would change every encoded mutation. Favourite records therefore travel in a **separate `FavouriteMutation` payload**, never inside `LedgerMutation`, and in a separate `favourites` member of the canonical projection that is encoded only when non-empty (`decodeIfPresent`). Pre-v6 operation payloads, their hashes and `CanonicalFoodProjection` bytes are pinned by literal fixtures.

### One versioned commit, verify and import mechanism

- **Typed payload selected by operation type.** `LedgerPayload = .ledger(LedgerMutation) | .favourites(FavouriteMutation)`. The operation type decides the case: `save_favourite_v1`, `revise_favourite_v1` and `arrange_favourites_v1` are `.favourites`; every other type is `.ledger`. Payload bytes are the case's own encoding with no wrapper, so a `.ledger` payload is byte-identical to today's. `LedgerTransaction(mutation:operation:)` keeps its shape and encoding; a sibling initialiser carries `.favourites`, and existing callers compile unchanged.
- **Commit port.** The store's commit accepts the transaction with its payload; the in-memory and GRDB insert paths dispatch on the case, writing favourite tables only for `.favourites`. Replay and retry recovery use the same dispatch.
- **Verifier and import.** Archive import (`CanonicalFoodArchive.swift` near line 423) decodes each payload by operation type instead of always as `LedgerMutation`; the operation verifier re-encodes the decoded case and checks `payloadHash`. The per-operation contract check (near lines 427 to 430) adds: the three favourite operations require contract 6.
- **Contract and counts.** `minimumContractVersion` and `recordCount` take the whole projection (ledger records plus favourites), not only `LedgerMutation`; a favourites-only projection requires 6.
- **affectedIDs** for a favourite operation are its favourite, favourite version and arrangement version IDs.
- Memory and GRDB stores pass the same commit, replay and import contract tests.

## 6. Versions and compatibility

| Change | Version |
|---|---|
| Favourite records and `FavouriteMutation`; operations `save_favourite_v1`, `revise_favourite_v1`, `arrange_favourites_v1`; `ProvenanceSourceKind.appReferenceDefinition`; `CaptureKind.referenceDefinition` | Food archive contract **6**, migration identifier `food-ledger-v6` |
| SQLite | Migration `v6_favourites` creates `favourite`, `favourite_version` (with `supersedes_id`, a nullable `log_item_version_id` foreign key, a nullable `reference_id` and a `CHECK` that exactly one is set) and `favourite_arrangement_version`, all with the same refuse-update and refuse-delete triggers as the existing record tables; sets `user_version = 6` and `schema_identity = food-ledger-v6`, rewrites no row |
| Registry | New `LedgerOperationRegistry` version admitting the three operations; earlier registries reject them |
| Archive admission | `minimumContractVersion` checks contract 6 conditions before contract 5 ones and returns 6 for any favourite record, `app_reference_definition` provenance or `reference_definition` evidence, so a water-only ledger requires contract 6 |

- Every exhaustive switch over `ProvenanceSourceKind` and `CaptureKind` classifies the new cases explicitly (generic policy: not generic; reviewed web policy: not applicable; presentation: "App reference"), with a test per switch site.
- Every v1 to v5 record, operation, hash and frozen archive decodes and re-encodes byte for byte; contracts 1 to 5 keep importing with identical canonical bytes.
- Older binaries fail safely: a contract-5 importer rejects contract 6 with `unsupportedFoodContract(6)`; a schema-5 opener throws `unknownSchema(6)`. Release note: downgrading is not possible after updating.
- **Daily JSON stays pinned to food contract `<= 3`**, with a test rejecting a contract-6 document alongside the 4 and 5 cases.
- Inventory backup format 2 and the receipt and list checkpoints are unchanged.

## 7. Egress

Unchanged. Favourites and quick add are local only: no network call at quick-add time (rebuild uses retained evidence), no HealthKit write, no Drive export of food entries (#97), no analytics. Creating a favourite through search or web lookup uses those routes' existing egress.

## 8. Contract tests (written first)

1. **Same entry as Confirm.** For an exact barcode favourite and plain water, sheet and Confirm saves of the same state (fixed clock and IDs) produce identical mutations, operation type, assertion (or none), `methodVersion` and reporting date.
2. **No single-tap log.** Opening the sheet writes nothing; one Log writes once.
3. **Eligibility union.** Ineligible when the pinned entry is a derived estimate, when `savesEstimate(rebuilt)` is true, or when the pinned entry carried an identity correction; covered for generic CoFID, representative web, `differs` / `notSure` and a corrected exact product. The service still refuses unmet requirements with the view model bypassed.
4. **Requirement split.** Every `FoodLogRequirement` case is classified exactly once; a new case fails until classified.
5. **Favourite edits never rewrite entries.** Rename, amount change, removal and reorder leave every log, product, resolution and assertion record and every payload and operation hash byte-identical.
6. **Pinned binding.** After the source entry is removed, restored, corrected or re-timed, `favouriteInput` is unchanged and a quick-add save succeeds with no duplicate evidence; a tampered reviewed web manifest makes the favourite unverifiable.
7. **No alias growth.** N quick adds of an exact favourite and N water logs create no `LibraryEntry` or version; `exactLibraryEntries(alias:)` never returns a favourite.
8. **Water reference.** Golden canonical bytes and SHA-256 via the injected digester; exact identity raises no requirement; nutrients exactly as Q1; a water-only day keeps energy and macros complete and sodium a known minimum.
9. **Water daily-first.** 150 + 250 + 330 mL is 730 mL; removed and superseded versions contribute nothing; empty day is No data; backdated and DST days (`Europe/London`, `Pacific/Auckland`, 29 March and 25 October 2026) land on the derived date.
10. **Decoding and heads.** Every invalid shape in section 1 is rejected; competing favourite heads and competing arrangement heads each fail the projection; removed favourites drop out; the first four drive Home.
11. **Compatibility.** Literal v1 to v5 payloads and frozen archives byte for byte; registry admission; `unknownSchema(6)`; migration rewrites no row; Daily JSON rejects contract 6.

Additional tests from the architecture gate:

- **A.** Second and third water saves write no duplicate evidence or release, on memory and GRDB stores.
- **B.** Save from a favourite after its source entry is removed, restored, corrected and re-timed (each separately).
- **C.** Literal pre-v6 operation payloads with `payloadHash` and `operationHash`, and `CanonicalFoodProjection` bytes, unchanged; a projection without favourites omits the `favourites` key.
- **D.** Eligibility union as in test 3, each condition alone, plus a corrected product version, a `.rejected` decision and a re-resolved pinned entry, each opening Confirm.
- **E.** Binding consistency: a binding to a missing log item version or to a `.removed` version is rejected by the store and by strict decoding; quick-add entries never reuse the pinned product or resolution IDs.
- **F.** No alias growth as in test 7.
- **G.** Competing arrangement heads produce the failed state.
- **H.** Built-in water: shown with no water favourite; logging from it writes no favourite; hidden once a `.reference(.plainWaterV1)` chain exists, active or removed; removal writes the record plus a removed version.
- **I.** `save_favourite_v1` idempotency: retry after a failure between the log and favourite operations, and retry after a lost response following commit, each yield one favourite; favouriting the same entry version twice returns the existing favourite.
- **J.** Provenance and capture kind classification at every switch site; `minimumContractVersion` returns 6 for a water-only ledger; a contract-5 binary rejects it.
- **K.** Water nutrients and completeness as in test 8.
- **L.** Plain water predicate: a water entry is in the set; a corrected entry whose resolution leaves the reference provenance is not.
- **M.** Q10 bound: 0 and 5000.0001 mL fail as `amountTextInvalid` in the sheet; 5000 mL passes; Confirm and the service accept 5000.0001 mL.
- **N.** Memory and GRDB store parity for tests 5 to 10 and A to L, including after an archive round trip.

Additional tests from the re-check:

- **O.** A contract-6 archive containing all three favourite operations imports and verifies with payload and operation hashes unchanged, on both stores.
- **P.** A contract-5 manifest containing a favourite operation is rejected; `minimumContractVersion` returns 6 for a favourites-only projection.
- **Q.** Literal `LedgerTransaction` and existing payload bytes are unchanged after the typed-payload generalisation.
- **R.** Q11 skip and conflict: identical stored evidence is skipped with pinned `affectedIDs`; the same `EvidenceID` with a different `capturedAt` or `byteHash` throws `immutableRecord` on both stores.
- **S.** Favourite tables refuse update and delete on GRDB, with in-memory parity.
- **T.** `relogSource` is gone and recent-food re-log still writes no duplicate evidence.
- **U.** The FoodLedgerKit boundary check is unchanged.

## 9. Not changing, or deferred

Confirmation v5 policy, requirement set, assertion grammar and estimate projection; the reviewed web gate; search and recent foods behaviour; inventory and Common foods data. Deferred: photo routes (#93), favourite-only save without logging, widgets or Siri, writing water to HealthKit, food in Daily JSON (#97).

## 10. Owner decisions (approved 12 October 2026, recommended answers)

| ID | Decision | Recommendation |
|---|---|---|
| Q1 | Plain water nutrients beyond water | Energy, protein, carbohydrates, total fat, fat subtypes, sugar, fibre and cholesterol exactly 0; minerals, vitamins and caffeine unknown (tap water varies), so minerals become known minimums on water days |
| Q2 | How a favourite is created | Only from a logged entry via a separate `save_favourite_v1` keyed on the log item version; favourite-only save deferred |
| Q3 | Water provenance | New `app_reference_definition` with an app-compiled, hashed definition, not a CoFID record (a generic record is an estimate and could never use the sheet) |
| Q4 | Record the favourite on the log entry | No; the entry is identical to a Confirm save |
| Q5 | Sheet amounts for food favourites | Default amount plus Other amount in the same unit; a unit change opens Confirm |
| Q6 | Two meanings of "favourite" | Keep inventory data; rename its copy to "Usual foods" and "Add to review" in presentation only |
| Q7 | Water as the first quick-add item | Built-in item, hidden once a water favourite chain exists; logging from it writes no favourite. Amended 13 October 2026: water can be added back after removal (section 4) |
| Q8 | Home water figure | Plain water logged (complete); dietary water nutrient total keeps the known-minimum rule |
| Q9 | Version bump | Archive contract 6 and schema `food-ledger-v6` after phase 3's contract 5; Daily JSON pin stays `<= 3` |
| Q10 | Custom water amount bound | Sheet-only: greater than 0 and at most 5000 mL, surfaced as `amountTextInvalid`; Confirm unbounded; no policy version change |
| Q11 | Retained-evidence mechanism | Skip stored evidence whose canonical bytes are identical, by existence in `save`; remove `relogSource`; collisions still fail as `immutableRecord` |
