# Food confirmation contract v5 (#195)

Status: **draft for owner review, 11 October 2026. Documents only; no code has changed.**
This is the change [ux-revamp-v1.md](ux-revamp-v1.md) calls "Confirmation v3" (section "Contract changes > 2"). It amends [food-confirmation-contract-v2.md](food-confirmation-contract-v2.md). Phase plan: [ux-revamp-phase-2-confirm.md](ux-revamp-phase-2-confirm.md).

## Naming

The stored policy identifier is already `food_confirmation_v4`: v1 (exact identity), v2 (generic composition estimate, #161), v3 (recipe source serving), v4 (reviewed web proposal and named serving). This contract introduces **`food_confirmation_v5`**, and the file is named after it. "Historical v1/v2 payloads" in the specification means every record written under policies v1 to v4, food archive contracts 1 to 3 and SQLite schema identities `food-ledger-v1` to `food-ledger-v3`.

## Baseline: how confirmation is stored at `8bad5c5`

From `FoodLedgerApplication/FoodConfirmation.swift`.

| Fact | Stored today |
|---|---|
| Acceptance | Never persisted. `FoodConfirmationDecision` is transient view state. A first save or a correction writes a `CandidateDecision` (`selected`, or `rejected` for a corrected or contradicted generic estimate) whose `expectedIdentity` is the saved product identity. |
| Plain exact acceptance | No `UserAssertion`. |
| Closest match | One assertion: `reason` = the user's free text; `claim` = `Accepted explained closest match; differences: <raw values joined by ", ">`. Product identity and nutrients stay the source's. |
| Generic estimate | One assertion: `reason` = `Explicitly accepted generic composition estimate; unknown source details remain unknown`; `claim` = `Accepted estimate under food_confirmation_v4; not verified product identity`. |
| Correction | One assertion: `reason` = the correction reason; `claim` = `Corrected populated confirmation for <source name>`; a new `ProductVersion`. |
| Quantity edit of a saved entry | Only a new `LogItemVersion`; product, product version, decision, resolution and resolution version are reused and **no assertion is written** (`changesProduct` is false, so the `Updated confirmed quantity` branch in `makeAssertion` is unreachable). |
| Policy version | `NutritionResolutionVersion.methodVersion`, written only with a new resolution. |
| Time | `occurredAt = clock.now()`; `reportingDate = FoodReportingDay.key(for: now, calendar:)`. Edits, removal, restoration and re-resolution copy both. |
| Library | A `LibraryEntry` and version are created on a first save whenever the candidate has `libraryAliases`. |
| Operation | `confirm_food_v1`, or `confirm_food_v2` with a weight declaration. Retry recovery (`FoodLedgerService.confirmedLogItemID`) accepts only those two types. |
| Bypasses | A material difference does not block when `state.reopened != nil` or a correction is applied (service guard near line 415; view model `saveRequirements` near `FoodConfirmationView.swift:169`). |

Hashed or byte-exact data: each operation's canonical mutation payload (`payloadHash`) and the operation (`operationHash`) in `FoodLedgerService.commit`; the archive snapshot ID and member hashes; the reviewed web manifest (`byteHash`, release `manifestHash`, re-verified at save and reopen); and the frozen `legacy-v1` and `legacy-v2` fixtures. `UserAssertion` uses synthesised `Codable`, so an older decoder silently drops an unknown key. Assertions are stored as a payload blob in SQLite, so no column is needed.

## 1. One Log action

Pressing **Log** is the explicit acceptance of the food, amount, time and source displayed at that moment. "Accept this match" and `acceptClosestMatch` are removed (state is never persisted, so no compatibility is lost).

- The view model sends one `log` intent; the service accepts and saves the state it is given in one call.
- Log is enabled only when the requirement list (section 2) is empty and the phase is `editing` or `saveFailed`. While disabled, the bar states the first requirement.
- "Leave without saving" writes nothing; `declined` stays transient.
- New resolutions record `methodVersion = food_confirmation_v5`.

### Exactly one assertion per save

| Save | `reason` | `claim` | Typed record |
|---|---|---|---|
| Plain exact, no difference | none | none | none |
| Exact with decisions | `Logged with inline decisions under food_confirmation_v5` | `Logged under food_confirmation_v5; decisions: <list>` | yes |
| Generic estimate, no difference | `Explicitly accepted generic composition estimate; unknown source details remain unknown` | `Accepted estimate under food_confirmation_v5; not verified product identity` | none |
| Generic estimate with decisions | as generic | `Accepted estimate under food_confirmation_v5; not verified product identity; decisions: <list>` | yes |
| Correction (decisions cleared) | the correction reason | `Corrected populated confirmation for <source name>` | none |
| Quantity or time edit | none (no assertion, as today) | none | none |

`<list>` is the decisions in `IdentityContradiction.allCases` order, joined by `"; "`, each as `<facet raw value>: source <source state token>, choice <choice token>`. Choice tokens: `matches_source`, `differs:<state raw value>`, `different_medium_or_none`, `not_sure`, `use_source_basis`, `use_source_serving`. Example: `skin: source skinless, choice differs:skin_on`. This grammar is **persisted, versioned data**, not UI copy: changing it needs a new policy identifier. Golden-string tests pin every row and assert assertion count is exactly one (or zero where shown).

## 2. Typed requirements

`saveRequirements: [String]` is replaced by `FoodLogRequirement`, a closed enum returned by the pure function `FoodLogPolicy.requirements(state:now:calendar:)`. The service evaluates the same function and refuses with `FoodConfirmationSaveError.unmetRequirements([FoodLogRequirement])`. Presentation maps each case to copy in one renderer; no copy names a disclosure.

| Case | Replaces | Satisfied by |
|---|---|---|
| `decideDifference(IdentityContradiction)` | "Explain why the closest match is acceptable…" | An inline choice (section 3). Not raised when `reopened != nil` or a correction is applied. |
| `sourceIdentityMissing([IdentityContradiction])` | "Food details still needed: …" | Another match, or a correction in the sheet |
| `amountMissing` | "Enter an amount greater than zero…" | A finite amount above zero |
| `amountTextInvalid` | `invalidOriginalAmountText` and `originalAmountRequirement` | A parsable amount, or clearing the optional original amount under direct weight |
| `recipeServingsRequired` | recipe servings | Count unit, no direct weight, conversion or plate |
| `sourceServingsRequired` | source-declared servings | As above |
| `measuredWeightMissing` | total edible weight | A finite gram total above zero |
| `weightBasisMissing` | measured or estimate basis | A declared basis |
| `retainedWeightNeedsConfirmation` | "…use 'Accept this match' to reconfirm" | An explicit "Keep this weight" action, not the Log press |
| `countNeedsMeasuredAmount` | count without conversion | A conversion or direct weight, or g / mL |
| `emptyPlateWeightMissing` | empty plate weight | A plate weight |
| `plateNeedsGramTotal` | plate needs grams | A gram total |
| `plateNotLighterThanTotal` | total must exceed plate | Corrected weights |
| `occurredAtInFuture` | new | A time not after now |
| `occurredAtTooEarly` | new | A day inside the window (section 4) |

"Confirm that this is the food you want using 'Accept this match'" is not dropped; it becomes the Log press. Order is fixed and follows the screen. Save-time integrity failures stay typed errors (`invalidReviewedSource`, `missingConversion`, plate unit, non-positive edible quantity). The per 100 g with mL basis warning stays a non-blocking notice.

**Deviation recorded:** ux-revamp-v1 lists "requirement and difference types" under the domain. `FoodLogRequirement` is policy output that depends on draft state, so it lives in `FoodLedgerApplication`. Facet, source-state and choice types stay in the domain because they are persisted.

## 3. Inline decisions

The difference set and its computation are unchanged and closed: `IdentityContradiction` as produced by `FoodConfirmationState.materialDifferences` today, including the generic filter (equal unknowns stay unknown) and the forced edible-quantity difference for an unreopened source-declared serving. The bypasses for reopened entries and corrections are kept exactly.

### Offered options per facet

`matchesSource` is offered only when the source state is known (not `unknown`). `differs` values exclude `unknown`, `named` (free text), `not_applicable` and the source's own value. `notSure` records an unknown eaten state.

| Facet | `matchesSource` | `differs` values | `notSure` |
|---|---|---|---|
| preparation | if kind not `unknown` | `as_sold`, `raw`, `cooked`, `reheated` minus source kind | yes |
| bone | if known | `with_bone`, `boneless` minus source | yes |
| skin | if known | `skin_on`, `skinless` minus source | yes |
| drained | if known | `drained`, `undrained` minus source | yes |
| packing medium | if `named` | the closed case `different_medium_or_none` (no text) | yes |
| fortification | if known | `fortified`, `unfortified` minus source | yes |
| serving basis | acknowledgement only: `use_source_basis` | none | no |
| edible quantity | acknowledgement only: `use_source_serving` | none | no |

Serving basis and edible quantity are acknowledgement rows ("Use the source's basis", "Use the source's serving"). They state that the entered amount is expressed on the source's basis; they never convert. `recipeServingsRequired`, `sourceServingsRequired` and `countNeedsMeasuredAmount` still apply independently.

### Record and recording

`FoodLogDecisionRecord { policyVersion, decisions: [FacetDecision] }`, `FacetDecision { facet, sourceState, choice }`. It stores only the source state of the selected candidate and the user's choice; it never stores `expectedIdentity` as "what was eaten". No estimate flag is stored; estimate status is derived (section 5). Strict decoding rejects: an empty list; duplicate facets; out-of-order facets; `matchesSource` against an unknown source state; a `differs` value that equals the source or is outside the offered set; `notSure` or `differs` on serving basis or edible quantity; an acknowledgement on any other facet; an unknown enum case.

The service refuses the save unless the decided facets equal `materialDifferences` for the selected candidate exactly, and each recorded `sourceState` equals that candidate's current state. When a bypass applies, decisions must be empty. Selecting another candidate or applying a correction clears decisions.

A `differs` or `notSure` choice makes the entry a labelled estimate. Product identity and nutrients remain the source's; nothing is recalculated or inferred.

Implementation note: a facet that is also in `unresolvedIdentity` is excluded from inline decisions, because `sourceIdentityMissing` always blocks it and no inline answer could resolve it.

### Rules kept from v1 and v2

- `sourceIdentityMissing` is not an inline decision. Unknown preparation, bone, skin, drained state, packing medium or fortification on an exact product or panel still blocks; unknown serving basis blocks for every source; corrections cannot opt an exact product into the estimate rule.
- Generic admission (retained generic-search evidence, provenance from the selected release and record, known basis) and its `rejected` outcome when contradicted are unchanged.
- An unknown-identity estimate stays ineligible for exact library reuse; re-resolution stays strict.

## 4. When

- `FoodConfirmationState.occurredAt: Date?`. For a new entry nil means "Now" and resolves to `clock.now()` at commit, so a screen opened at 23:58 and logged at 00:02 lands on the new day. A reopened entry starts with its stored `occurredAt`.
- `reportingDate = FoodReportingDay.key(for: occurredAt, calendar:)`. "Unchanged" means exact instant equality with the stored `occurredAt`; then the stored `reportingDate` is retained even after a time-zone change.
- One clock and one calendar are wired at the composition root into both the view model and `FoodConfirmationService`; the service is authoritative.
- Window: `start = gregorian.date(byAdding: .day, value: -7, to: gregorian.startOfDay(for: now))`, where `gregorian` is a Gregorian calendar in the injected calendar's time zone. A changed `occurredAt` must satisfy `start <= occurredAt <= now`. The service rejects a future or too-early time even if the view model is bypassed. An unchanged historical time outside the window remains valid for quantity edits.
- A non-existent spring-forward wall time is resolved by the calendar before policy runs; the reporting day is the day containing the resolved instant.
- A time edit is an ordinary new `LogItemVersion` superseding the head, reusing product, decision and resolution, with no assertion. Correction reason: `Confirmation time correction` (time only) or `Confirmation time, quantity or plate correction` (time and more); otherwise the existing `Confirmation quantity or plate correction`. The head moves to the new day without `competingVersions`; removal and restoration keep the edited time.

## 5. Estimate status projection

`FoodEntryEstimateStatus` is a pure application projection over a `StoredFoodConfirmation`: estimate when (a) `FoodConfirmationPolicy.isGenericEstimate` holds for the input rebuilt by `restoredConfirmationInput` from stored evidence and provenance (this includes representative web scope) and the saved product identity still has an unknown decisive detail (the v2 unknown-identity estimate, with or without a correction; a generic match whose identity the user fully resolved keeps v2's known-identity exact reuse), or (b) the decision record contains any `differs` or `notSure`. Legacy closest-match entries are not relabelled unless (a) holds. Status follows the current version: the assertions read are those of the current product and resolution versions, so after a correction (which carries no decisions) an entry is an estimate only if (a) holds. The same rule decides, before saving, whether a save is an estimate (`FoodLogPolicy.savesEstimate`), including for a corrected generic estimate. The Confirm screen and the existing Food Log entry rows (an "Estimate" prefix on the source line) use it. Developer Diagnostics does not list food entries today, so adding it there is deferred to the Food Log and saved-entry redesign (#197). Measured versus estimated weight stays the separate existing quantity flag.

Whenever a save will write an estimate, the estimate label and "Unknown details stay unknown" appear on the primary screen beside the food, not inside Details.

## 6. Library aliases (D6)

An estimate save (generic, or any `differs` / `notSure`) creates no `LibraryEntry` even if the candidate carries `libraryAliases`. Exact `matchesSource` saves keep today's alias rule.

## 7. Identity correction

`applyCorrection` and `FoodCorrection` are unchanged and move to a secondary sheet: before logging from the `sourceIdentityMissing` row ("Choose a different match", "Add food details"), so an exact product with unknown identity is never stranded; after logging from the saved entry's Edit (#197).

## 8. Compatibility and admission (D1)

- `UserAssertion` gains optional `confirmation: FoodLogDecisionRecord`, omitted when nil, so v1 to v4 assertions re-encode byte for byte.
- New operation `confirm_food_v3`, added to `LedgerOperationType.declaredQuantityTypes` and `LedgerOperationRegistry.builtInV4`. `requireSupported` rejects an assertion carrying `confirmation` under any other type. It also rejects a `confirm_food_v3` mutation without such an assertion, and archive verification requires food contract 4 for any `confirm_food_v3` operation. `FoodLedgerService.confirmedLogItemID` accepts `confirm_food_v3` so idempotent retry recovers it.
- Food contract **4**, migration identifier `food-ledger-v4`. `minimumContractVersion` returns 4 when any assertion carries `confirmation`. A v5 binary always exports contract 4; older binaries (contract 3 and below) cannot import any archive from it. v1 to v3 archives keep importing with identical canonical bytes.
- SQLite migration `v4_confirmation_decisions` sets `user_version = 4` and `schema_identity = food-ledger-v4`, rewriting no rows. A schema-3 opener throws `unknownSchema(4)`.
- Release note: after updating, downgrading the app is not possible and archives cannot be restored into older builds.
- Backdated times need no format change. No stored record, operation, hash, archive or exported file is rewritten.

## 9. Daily JSON (D7)

Food entries are not exported today (#97). `DailyHealthExport` currently admits a food document for any contract in `1...CanonicalFoodProjection.foodContractVersion`, which would widen automatically to 4. Pin admission to contract `<= 3` until #97 defines food transport, with a `DailyHealthExportTests` case rejecting a contract-4 document. Exported files and archives are immutable; no invalidation rule is needed now.

## 10. Interactions

- **Reviewed web proposals:** the manifest digest, basis and nutrient checks run before policy and still fail as `invalidReviewedSource`. Exact scope keeps every unknown-identity blocker; representative scope keeps the v4 estimate rule inside v5.
- **Quick add (#198)** must use `FoodLogPolicy`, the same save path, assertion rules and estimate projection.
- **List import** uses the same state and policy per item; When defaults to Now per item.

## 11. Contract tests (written first)

1. Requirement mapping table: each former string's scenario yields exactly its typed case; empty list implies the service saves.
2. Bypasses: no `decideDifference` when reopened or after a correction, in policy and service; decisions must be empty then.
3. Refused direct saves: undecided, stale, missing or extra decisions, wrong `sourceState`, future or too-early time all refused by the service with the view model bypassed.
4. Golden reason and claim strings for every row of the assertion table; exactly one assertion per save.
5. Edit-only mutations: quantity and time edits write one `LogItemVersion` and no product, decision, resolution or assertion.
6. Strict decoding rejects each invalid record shape listed in section 3.
7. Literal v1 to v4 assertion, log and resolution payloads, their hashes and the frozen legacy archives re-encode byte for byte.
8. Admission: v3 registry rejects `confirm_food_v3`; a `confirmation` assertion under any other type is rejected; contract-3 import rejects contract-4 archives; a v5 export is contract 4; schema-3 opener throws `unknownSchema(4)`; migration rewrites no row bytes.
9. Retry recovery returns the stored confirmation for a `confirm_food_v3` operation.
10. Estimate projection on memory and GRDB stores and after archive round trip: generic, representative web, `differs`, `notSure` are estimates; `matchesSource` only and legacy closest match are not.
11. Alias rule: estimate saves create no library entry; exact saves keep it.
12. When boundaries in `Europe/London` and `Pacific/Auckland` across 29 March and 25 October 2026: window start, now, one second either side, 23:58 open with 00:02 Log, unchanged-instant retention, Buddhist display calendar.
13. Time edit moves the head with no `competingVersions`; removal and restoration keep the edited time.
14. Daily JSON admission rejects a contract-4 food document.
15. Reviewed web exact and representative saves fail `invalidReviewedSource` before policy when altered; valid saves record `food_confirmation_v5`.
16. View model: estimate label and unknowns notice are on the primary screen whenever the save would be an estimate.
17. `Tools/NutritionEvaluationSpike` compiles against the new reducer.

## 12. Not changing, or deferred

- Domain identity compatibility, candidate selection, nutrition values, quantity, conversion, plate and direct-weight rules, unknown nutrient semantics, provenance, generic, recipe and named-serving policies and the reviewed web gate.
- No new difference kinds, no free-text decisions, no inference of eaten state or nutrients.
- Amended 23 October 2026 by [count-conversion-method-v1.md](count-conversion-method-v1.md): the method for a count conversion is a closed choice, and "Estimated by eye" is an estimated direct weight, not a conversion. `countNeedsMeasuredAmount` is unchanged.
- Amended 24 October 2026 by [pasted-label-confirm-v1.md](pasted-label-confirm-v1.md): for a pasted-label source only, unknown fortification is an inline decision (Not stated records `not_sure`) instead of `sourceIdentityMissing`; every other source keeps the section 3 rule.
- Deferred: Save as favourite (#198), shared When for a list import, count quantity guides, query-derived differences, backdating beyond seven days, food in Daily JSON (#97).

## 13. Owner decisions (recommended, awaiting approval)

| ID | Decision | Recommendation |
|---|---|---|
| D1 | Typed decisions or claim text only | Typed optional assertion field with operation `confirm_food_v3`, food contract 4 and schema `food-ledger-v4` |
| D2 | Source of the "what you ate" side | Keep today's difference computation; the record stores only the source state and the user's choice, never `expectedIdentity` as eaten state |
| D3 | How far back When goes | Today plus the previous 7 local days |
| D4 | Save as favourite in phase 2 | Defer to #198; leave the slot empty and write no library record |
| D5 | "Not sure" on a known exact-product facet | Allowed and recorded as an estimate; not offered for serving basis or edible quantity |
| D6 | Library aliases for estimates | Estimate saves create no exact library aliases |
| D7 | Daily JSON food-document admission | Pin to food contract `<= 3` until #97, with a `DailyHealthExportTests` case |
