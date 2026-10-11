# Food quick add contract v1 (#198)

Status: **draft for owner review, 11 October 2026. Documents only; no code has changed.**
This is the change [ux-revamp-v1.md](ux-revamp-v1.md) calls "Quick add" (section "Contract changes > 4"). It builds on [food-confirmation-contract-v5.md](food-confirmation-contract-v5.md) (one Log action, `FoodLogPolicy`, D4 and D6) and sequences after phase 3 (#196, PR #207: recent foods, `FoodConfirmationService.relogInput`, food archive contract 5, schema `food-ledger-v5`). Phase plan: [ux-revamp-phase-5-favourites.md](ux-revamp-phase-5-favourites.md). Wireframes: [`Favourites.dc.html`](designs/ux-revamp-v1/Favourites.dc.html), [`QuickAdd.dc.html`](designs/ux-revamp-v1/QuickAdd.dc.html).

## Baseline at `9fc734d` plus PR #207

| Concept | Where it lives today | Can it hold a source-bound favourite? |
|---|---|---|
| Common foods "favourites" | `InventoryProductVersion.favourite` and `usualPortion` in the local inventory (`FoodLedgerDomain/LocalInventory.swift`, inventory backup format 2), shown by `CommonFoodsView` | No. They are names, aliases and usual portions with no source, product, resolution or evidence. "Quick-add for review" adds a line to the review queue; it asserts nothing. |
| Personal library | `LibraryEntry` and `LibraryEntryVersion` in the food ledger (`IdentityAndRecords.swift`): product version, non-empty aliases, optional reusable quantity and conversion, append-only versions | Not safely. A library entry is an **exact alias** found by `exactLibraryEntries(alias:)`. Under v5 D6 an estimate save creates none, and v2 forbids exact personal-library reuse of an unknown-identity estimate. A favourite made from an estimate must exist without becoming an exact alias. It also has no resolution pin, order or removal state. |
| Recent foods (PR #207) | `FoodRecentItemsProjection` plus `relogInput(_:)`, which restores the saved entry's **source** candidate (never corrected identity, decisions or edible quantity), re-verifies reviewed web manifests and reuses retained evidence via `relogSource` | Yes, as the construction pattern. Quick add reuses it. |
| Water | `NutrientKey.water` (canonical unit mL) already exists and is summed by `FoodIntakeSummary` within one reporting date | No reference record exists. |

## 1. What a favourite stores

Favourites are new append-only food-ledger records, not inventory rows and not library entries.

```
FavouriteEntry        { favouriteID, createdAt }
FavouriteVersion      { favouriteVersionID, favouriteID, ordinal, supersedesFavouriteVersionID?,
                        binding, label, defaultAmount, state (active | removed), createdAt }
FavouriteBinding      = .savedEntry(logItemID, logItemVersionID, productVersionID, resolutionVersionID)
                      | .reference(ReferenceFoodID)          // only .plainWaterV1 in this contract
FavouriteAmount       { value (finite, > 0), unit (QuantityUnit) }
FavouriteArrangement  { arrangementVersionID, ordinal, supersedes?, order: [FavouriteID], createdAt }
```

- **Source-bound product and resolution.** A `.savedEntry` binding pins the exact log item version the favourite was made from, together with that version's product version and resolution version. Quick add rebuilds its input from those pinned records (section 3), so later edits, corrections or removal of the source entry never change the favourite.
- **Default amount.** Value and unit only, as `FoodConfirmationService.lastEnteredAmount` reads them (weight declaration original input, then conversion source quantity, then edible quantity). No conversion, plate or decision is carried.
- **Label.** The display name, defaulting to the source product name. It is presentation data; it never alters product identity, nutrients or provenance.
- **Estimate status is derived, never stored.** `FoodEntryEstimateStatus` is evaluated over the pinned stored confirmation. A favourite made from an estimate keeps the estimate label and its provenance.
- **Display order.** One `FavouriteArrangement` lists active favourites in quick-add order. The first four are the Home chips and the "On Today's quick add" group; the rest are "Other favourites". Reordering writes one new arrangement version and no favourite version. Removed favourites are dropped from the projection even if an older arrangement lists them; active favourites missing from the arrangement are appended by `createdAt`.
- **Strict decoding** rejects a non-positive or non-finite amount, an empty label, a duplicate ID in `order`, an unknown binding or reference case and a `.reference` binding whose amount unit is not mL.

### Creation (Q2)

A favourite is created from a logged entry: "Save as favourite" on Confirm (the v5 D4 slot), or from a saved entry or recent food. "Create a favourite from Food search, Barcode or Web lookup" on the Favourites screen opens that route with Save as favourite preset, and the Confirm bar reads "Log and save favourite". The log save is unchanged; the favourite is written by a **separate** operation `save_favourite_v1` immediately afterwards, so every confirm operation payload stays byte-identical to v5. If the second operation fails, the entry stays logged and the screen says "Logged. Favourite not saved" with Try again (idempotent on its own key).

Estimate entries may be saved as favourites (D6 forbids exact aliases, not favourites). Photo routes show "Not yet available" and create nothing until #93 or a separately approved image contract.

## 2. Relationship to common foods and the library

- **New record, no reuse of either store.** Reusing inventory favourites would lose source binding; reusing `LibraryEntry` would turn every favourite into an exact alias, contradicting D6 and v2. Favourites therefore never appear in `exactLibraryEntries(alias:)` and never feed generic or personal-library search.
- **No migration.** Existing inventory favourites and usual portions are untouched, keep backup format 2 and remain in Common foods. They cannot be converted automatically because they carry no source. Q6 covers the duplicate wording.
- **Append-only edits.** Rename and default-amount changes write a new `FavouriteVersion` superseding the head; removal writes a `removed` version (a tombstone, not a delete). Changing the bound food is not an edit: it is a new favourite. No favourite operation contains a log item, log item version, product, resolution or assertion, so past entries cannot be rewritten by construction; a contract test proves their bytes and hashes are unchanged.
- Competing favourite heads stop the Favourites projection with an explicit failed state, as the intake projection does for log heads; nothing chooses by ordinal or time.

## 3. Quick add: a one-step confirmation sheet

Quick add is a sheet presenting a pre-built `FoodConfirmationState`. Tapping a chip or row only opens it; **nothing is logged on a single tap**. Log in the sheet is the v5 explicit acceptance of the food, amount, time and source shown.

### Input construction (relogInput style)

- `.savedEntry`: `favouriteInput(_:)` restores the pinned stored confirmation through the same code as `relogInput` (generalised so `restoredConfirmationInput` can be addressed by a pinned log item version, a read-only reader addition), re-verifying reviewed web manifests and carrying only the source candidate. The state's `relogSource` equivalent points at the pinned entry so retained evidence is reused, never rewritten.
- `.reference(.plainWaterV1)`: the fixed reference input from section 4.
- The state's quantity is the chosen preset or custom amount in the favourite's unit; `occurredAt` is nil for Now or the chosen time.
- Saving calls the unchanged `FoodConfirmationService.save`. The operation type, assertion, `methodVersion = food_confirmation_v5`, reporting day and alias rule are whatever Confirm would produce for the same state. Quick add adds **no new log operation type** and records no favourite reference on the entry (Q4), so a quick-add entry is indistinguishable from the same Confirm save.

The result is a **new log item** (version 1), not a new version of an earlier entry.

### Eligibility (pure `QuickAddPolicy`, application layer)

The one-step sheet is offered only when all hold:

1. the input rebuilds and re-verifies; otherwise the favourite shows "Source can no longer be verified" and offers removal;
2. `FoodLogPolicy.savesEstimate` is false (the v2 unknown-identity estimate, representative web scope, or any recorded `differs` / `notSure` all fail this);
3. `FoodLogPolicy.requirements` for the state with the default amount and Now contains only the **sheet-resolvable** cases below.

| May appear in the sheet (blocks Log, fixed inline) | Never in the sheet: opens the full Confirm |
|---|---|
| `amountMissing`, `amountTextInvalid` (custom amount), `occurredAtInFuture`, `occurredAtTooEarly` (When, same seven-day window as v5) | `decideDifference`, `sourceIdentityMissing`, `recipeServingsRequired`, `sourceServingsRequired`, `measuredWeightMissing`, `weightBasisMissing`, `retainedWeightNeedsConfirmation`, `countNeedsMeasuredAmount`, `emptyPlateWeightMissing`, `plateNeedsGramTotal`, `plateNotLighterThanTotal` |

Ineligible favourites open the full Confirm screen with the same state for fresh explicit confirmation, per the specification and v5 D6. Re-resolution keeps its strict identity requirements. The service evaluates `FoodLogPolicy` again at save, so a bypassed view model still cannot log an unmet requirement. The sheet's "Edit" opens the full Confirm with the current sheet state.

### Sheet content

Title "Quick add <label>", food line, presets, Other amount, When (Now by default), a plain source line and "Log <amount>". No estimate label is needed because estimates never reach the sheet. Water presets are 150, 250, 330 and 500 mL with the favourite's default selected. Food favourites offer the default amount plus Other amount in the same unit; changing unit opens Confirm (Q5).

## 4. Water: one fixed reference record

- **Identity.** `ReferenceFoodID.plainWaterV1`. Source ID `weeklyhealthreport.reference`, source release `plain-water-v1`, record ID `plain-water`, new provenance kind `app_reference_definition` (Q3). The definition is a constant canonical JSON document compiled into the app; the release `artifactHash` and `manifestHash` are its SHA-256, pinned by a golden test. It is stored like any source release and evidence; the byte-identical evidence member is reused by later water entries.
- **Product identity.** Exact and fully known: item class food, preparation `as_sold`, every other facet `not_applicable`, so v5 raises no difference or missing identity and the save is never an estimate.
- **Resolution.** Basis `per100Millilitres`; water 100 mL exact; energy 0 kcal, protein, carbohydrates and fat 0 g exact; every other nutrient omitted and therefore unknown (Q1). Amounts are mL only; no density or gram conversion is inferred.
- **Versioning.** The definition is immutable. Any change is `plain-water-v2` with a new release, while v1 entries keep resolving to v1. Water favourites use the `.reference` binding, so they never depend on a saved entry.
- **Built-in default (Q7).** With no stored arrangement, the projection shows a built-in Water 250 mL quick-add item first. Nothing is written until the user logs, edits or reorders; the first edit or reorder writes the favourite and arrangement records.

### Daily-first aggregation in mL

- Water contributions use the existing `FoodIntakeSummary` scaling (consumed mL divided by the 100 mL basis), so units always agree.
- Within a reporting date, current log heads are summed first; removed and superseded versions contribute nothing; backdated entries count on the reporting date derived from `occurredAt`.
- A day with no entries shows No data, not 0 mL. Any multi-day water figure averages completed daily totals with equal weight; none is added in this phase.
- Home's water figure is the **plain water logged** total (Q8), complete by construction. The dietary water nutrient total keeps the existing completeness rule (a food without a declared water value marks it as a known minimum).
- HealthKit is untouched: nothing is written to Health, and `toShare` stays empty.

## 5. Versions and compatibility

| Change | Version |
|---|---|
| `FavouriteEntry`, `FavouriteVersion`, `FavouriteArrangement`; operations `save_favourite_v1`, `revise_favourite_v1`, `arrange_favourites_v1`; provenance kind `app_reference_definition` | Food archive contract **6**, migration identifier `food-ledger-v6` |
| SQLite | Migration `v6_favourites` creates `favourite`, `favourite_version` (with `supersedes_id` and binding foreign keys) and `favourite_arrangement_version` tables, sets `user_version = 6` and `schema_identity = food-ledger-v6`, and rewrites no existing row |
| Registry | New `LedgerOperationRegistry` version admitting the three operations; earlier registries reject them; `requireSupported` rejects favourite records under any other operation type |
| Archive admission | `minimumContractVersion` returns 6 for any favourite record or any `app_reference_definition` provenance, so a water entry alone requires contract 6 |

- Every v1 to v5 record, operation, hash and frozen archive decodes and re-encodes byte for byte; archives of contracts 1 to 5 keep importing with identical canonical bytes.
- Older binaries fail safely: a contract-5 importer rejects a contract-6 archive with `unsupportedFoodContract(6)`; a schema-5 opener throws `unknownSchema(6)`. Release note: downgrading is not possible after updating.
- **Daily JSON stays pinned to food contract `<= 3`**, with a `DailyHealthExportTests` case rejecting a contract-6 document alongside the existing 4 and 5 cases.
- Inventory backup format 2 and the receipt and list checkpoints are unchanged.

## 6. Egress

Unchanged. Favourites and quick add are local only. No network call, no OpenRouter or online lookup at quick-add time (rebuild uses retained evidence only), no HealthKit write, no Drive export of food entries (#97), no analytics. Creating a favourite through search or web lookup uses those routes' existing egress unchanged.

## 7. Contract tests (written first)

1. **Same entry as Confirm.** For an exact barcode favourite and plain water, the sheet save and a Confirm save of the same state (fixed clock and IDs) produce identical mutation payloads, operation type, assertion (or none), `methodVersion` and reporting date.
2. **No single-tap log.** Opening the sheet from a chip writes no operation; only Log does, once.
3. **Estimate favourites never use the sheet.** Generic CoFID, representative web and `differs` / `notSure` favourites are ineligible in `QuickAddPolicy` and the service still refuses an unmet requirement with the view model bypassed.
4. **Requirement split.** Each `FoodLogRequirement` case is classified exactly once as sheet-resolvable or Confirm-only; a new case fails the test until classified.
5. **Favourite edits never rewrite entries.** Rename, amount change, removal and reorder leave every log item, version, product, resolution, assertion, payload hash and operation hash byte-identical.
6. **Pinned binding.** Correcting, editing or removing the source entry leaves `favouriteInput` unchanged; a tampered reviewed web manifest makes the favourite unverifiable.
7. **No alias.** Saving any favourite creates no `LibraryEntry`; `exactLibraryEntries(alias:)` never returns a favourite.
8. **Water reference.** Golden canonical bytes and SHA-256; exact identity raises no requirement; energy and macros exactly 0; other nutrients unknown; evidence reused byte-identically.
9. **Water daily-first.** 150 + 250 + 330 mL on one day is 730 mL; a removed entry and a superseded version contribute nothing; an empty day is No data; a backdated entry and DST days (`Europe/London`, `Pacific/Auckland`, 29 March and 25 October 2026) land on the derived reporting date.
10. **Strict decoding and arrangement.** Every invalid shape in section 1 is rejected; competing heads fail the projection; removed favourites drop out; the first four drive Home.
11. **Compatibility.** Literal v1 to v5 payloads and frozen archives byte for byte; contract-5 import rejects contract 6; v6 export is contract 6 only when required; `unknownSchema(6)`; migration rewrites no row bytes; registry admission; retry recovery for `save_favourite_v1`.
12. **Memory and GRDB parity.** Tests 5 to 10 run against both stores and after an archive round trip.
13. **Daily JSON** rejects a contract-6 food document.

## 8. Not changing, or deferred

Confirmation v5 policy, requirement set, assertion grammar and estimate projection; the reviewed web gate; search and recent foods; inventory and Common foods data. Deferred: photo routes (#93), favourite-only save without logging, quick add from widgets or Siri, writing water to HealthKit, food in Daily JSON (#97).

## 9. Owner decisions (recommended, awaiting approval)

| ID | Decision | Recommendation |
|---|---|---|
| Q1 | Plain water nutrients beyond water | Energy, protein, carbohydrates and fat exactly 0; minerals and all else unknown (tap water varies) |
| Q2 | How a favourite is created | Only from a logged entry (Confirm "Save as favourite", saved entry, recent food) via a separate `save_favourite_v1`; favourite-only save deferred |
| Q3 | Water provenance | New kind `app_reference_definition` with an app-compiled, hashed definition, not a CoFID record (a generic record is an estimate and could never use the sheet) |
| Q4 | Record the favourite on the log entry | No; the entry is identical to a Confirm save |
| Q5 | Sheet amounts for food favourites | Default amount plus Other amount in the same unit; a unit change opens Confirm |
| Q6 | Two meanings of "favourite" | Keep inventory data unchanged; rename its copy to "Usual foods" and "Add to review" in presentation only |
| Q7 | Water as the first quick-add item | Built-in default projection, written only on first edit or reorder; no records seeded without user action |
| Q8 | Home water figure | Plain water logged (complete); dietary water nutrient total keeps the existing known-minimum rule |
| Q9 | Version bump | Archive contract 6 and schema `food-ledger-v6` after phase 3's contract 5; Daily JSON pin stays `<= 3` |
| Q10 | Custom water amount bounds | Greater than 0 and at most 5000 mL per entry |
