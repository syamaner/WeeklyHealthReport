# Pasted label Confirm v1 (#306)

Status: **design spec and architecture gate, 24 October 2026. Documents only; no code has changed.** The owner approved autonomous delivery of #306, including this contract amendment, on 24 October 2026. Source: the UX review of `main` at `53450fb7` (issues 2, 3 and 4). The architecture gate returned **PASS WITH CHANGES** on `d917d57d`; every required change is applied here (section 13).

It amends, in the style of [count conversion method v1](count-conversion-method-v1.md):

- [Food confirmation contract v5](food-confirmation-contract-v5.md), section 3 ("Rules kept from v1 and v2": unknown fortification on an exact panel always raises `sourceIdentityMissing`);
- [Pasted nutrition label v1](pasted-nutrition-label-v1.md), sections 2.2 (the optional Fortified? choice on the label text screen), 2.3 (Confirm) and 6.5 (identity mapping, and "a pasted-label save writes no new assertion row").

It does **not** amend [reader v3](pasted-nutrition-label-reader-v3.md): no file pinned by `ReaderV3FreezeTests` changes (section 7).

## 1. Problem

Walking the paste route at `53450fb7` (review screenshots 43 to 60):

1. **Fortification is asked in the wrong place, and then blocks with the wrong remedy.** The label text screen offers an optional "Fortified?" picker, unanswered by default. Left unanswered, the pasted label's identity has `fortification = unknown`, so Confirm raises `sourceIdentityMissing([.fortification])` and the pinned bar says "This source does not say: fortification. Choose a different match or add the food details." There is no other match: the source is the user's own label.
2. **The only fix is the catalogue form.** "Add food details" opens the Food details sheet: Item class, Preparation, Bone, Skin, Drained state, packing medium, Fortification, "Keep populated basis" and a required reason for correction. Every facet except fortification is already fixed by `pasted-label-identity-v1`, and the save becomes a correction (a new product version and a "Corrected populated confirmation" assertion) for what is really one answer about the label.
3. **Amount eaten sits below about 20 nutrient rows.** The pasted-label sections (values, "Correct …" actions, serving lines) come before the decisions and the amount, so the user scrolls past the whole table to reach the field that Log needs. The wireframe order (`docs/designs/ux-revamp-v1/Confirm.dc.html`) is food, blocking decision, amount, When, nutrition, source.
4. **The unit opens on grams even when the label states a serving.** A label with "每一份量 30 公克" opens on `g`; servings are one picker change away, but they are what the user usually means.

## 2. What is stored today (baseline at `277d7bf7`)

| Fact | Where | Format |
|---|---|---|
| The Fortified? answer | Pasted-label manifest (v1 and v2), `identity_mapping.fortification_answer` | `yes`, `no` or `unanswered` (`PastedLabelIdentity.FortificationAnswer`, `FoodLedgerDomain/PastedLabelDomain.swift`) |
| The resulting facet | The candidate's and saved `ProductVersion`'s `DecisiveIdentity.fortification` | `fortified`, `unfortified`, `unknown`, derived by `PastedLabelIdentity.fortification(_:)`; the manifest verifier requires the identity to equal the mapping of the answer |
| The item class | `identity_mapping.item_class` and `ProductVersion.itemClass` | `fortified_food` for `yes`, otherwise `food` |
| A Food details fix | A correction: new `ProductVersion` with the corrected identity, one assertion ("Corrected populated confirmation for …"); the manifest still says `unanswered` | existing correction path |
| Typed inline decisions | `UserAssertion.confirmation: FoodLogDecisionRecord` under `confirm_food_v3` | v5 section 3; a pasted-label save writes none today |

The answer is collected on the label text screen (`PastedLabelTextViewModel.fortification`) and passed as `PastedLabelDetails.fortification` to the confirmation builder. `PastedLabelSourceModel.updateDetails(_:)` already rebuilds the source on Confirm, keeping corrections, when name, brand or the answer change without a new reading.

## 3. Decisions

| ID | Decision |
|---|---|
| C1 | **Ask once, on Confirm.** The Fortified? picker is removed from the label text screen. A new reading always reaches Confirm with the answer `unanswered`; Confirm asks. Nothing is preselected and nothing is inferred from the text (a vitamin row in the table does not answer it). |
| C2 | **Three answers in label wording: Yes / No / Not stated.** Yes and No are facts about the label, so they become the source's identity through the existing manifest field (`fortification_answer` = `yes` or `no`), applied by the existing `updateDetails` rebuild. Not stated keeps the manifest at `unanswered` and the identity at `unknown`, and is recorded as the existing typed inline decision `fortification: source unknown, choice not_sure`. **No new persisted field, value, token, operation type, contract or schema.** |
| C3 | **Not stated is a labelled estimate** under v5 section 5(b) (any `not_sure` is an estimate), unchanged: the product identity has an unknown decisive detail. The label's values are kept as read; the estimate notice says why. Library aliases follow v5 D6 (none for an estimate). **Owner decision, 24 October 2026: Not stated counts as an estimate** (closes Q1, section 12). |
| C4 | **Pasted-label fortification is an inline decision, never `sourceIdentityMissing`.** For a pasted-label source, the **state property** `FoodConfirmationState.unresolvedIdentity` (`FoodConfirmation.swift`, near line 253) omits `.fortification`; the facet then appears through the unchanged difference computation (unknown on either side is a material difference) as `decideDifference(.fortification)`. The **static** `FoodConfirmationPolicy.unresolvedIdentity(_:allowingEstimate:)` is unchanged, so its other callers (`FoodLogPolicy` line 146, `FoodEntryEstimateStatus`, CoFID admission, `FoodConfirmationState.unresolvedIdentity(_:)` near line 931) keep their results. This is the only change to the closed v5 rules, and it is scoped to the pasted-label source (C6a) **in two situations only**, and never while a Food details correction is applied: (a) every new pasted-label Confirm, whether a new reading, a re-log or a favourite (amended after journey QA, section 14); and (b) a reopened pasted-label entry whose current version's decision record holds `fortification: not_sure`, so its quantity and time edits are not blocked. The transient `answersLabelFortification` flag (never persisted) marks an editable source, where Yes and No are inline (C6); it no longer gates C4. |
| C5 | **The only admitted recorded decision for that facet is `not_sure`.** `FoodLogPolicy.offeredChoices(state, facet: .fortification)` returns `[.notSure]` for a pasted-label source (the domain's `FoodLogFacetDecision.offeredChoices` is unchanged). Enforcement: `FoodLogPolicy.decisionRecord` throws `staleDecisions` for any other choice on that facet, including `differs:fortified` and `differs:unfortified` (and `matches_source`, already refused against an unknown source state). A Yes or No must change the source, not be recorded as "eaten differs from source". |
| C6 | **Never the catalogue form for an editable pasted label.** On a pasted-label Confirm whose source is **editable** (a new reading, before saving), "Add food details", the Food details sheet and "Choose a different match" are not offered. Under `pasted-label-identity-v1`, fortification is the only facet that can be unknown, so after C4 `sourceIdentityMissing` can never arise there (pinned by a test). **Re-logs and favourites** of a stored pasted label (`FoodConfirmation.swift` near lines 708 to 748, the non-editable `PastedLabelSourceModel(stored:)`) cannot rebuild the stored manifest, so the Fortification section offers **Not stated** inline (an estimate, logged in one step once chosen) and Yes or No through Food details, with the footer "This saved label cannot be changed here. Choose Not stated, or use Add food details to say Yes or No." The stored decision is never carried: the user chooses again on Confirm. "Choose a different match" is never shown for a pasted label. |
| C6a | **One scope predicate.** "Pasted-label source" means `PanelSourceAdmission.applies(input, candidate:)` (in the pinned `PastedLabelSource.swift`, called, not changed). The new policy and the existing per 100 mL default in `FoodConfirmationState.init` both use it, replacing the duplicate `sourceID == PastedLabelSource.sourceID` check. `PanelSourceAdmission.applies` (`PastedLabelSource.swift` near lines 520 to 527) is broader than the old `sourceID` check used by the per 100 mL default (it also matches panel provenance and pasted-label evidence); this is accepted because the extra inputs it matches are ones panel admission refuses at save, and a test pins the opening unit for every verified pasted fixture and for catalogue fixtures, so no admitted input changes its opening unit. C4 never relaxes a source that admission does not verify: a forged release carrying the pasted source ID without a valid manifest is refused by panel admission before any requirement is evaluated (test 8.5.11). |
| C7 | **Screen order:** Food, Fortification (the blocking decision), Amount eaten (with When), Nutrition from the label, then the existing remainder. Only the pasted-label sections move; their content is unchanged. |
| C8 | **Servings by default when the label states a serving.** On a new pasted-label Confirm with no amount yet, the unit opens on servings whenever `PastedLabelServingPolicy.serving(input, candidate:)` returns a serving (the same condition under which the picker offers servings today). The amount stays empty: no quantity is chosen for the user. |
| C9 | **The answer stays visible after it is given,** with the chosen option shown, so it can be changed before Log. It never disappears from under the user. |
| C10 | **Read again resets the answer** to unanswered and clears a Not stated decision: a new reading is a new source, and nothing carries over silently. Every other rebuild of the same reading keeps the answer (C11). |
| C11 | **The answer survives every source rebuild.** `FoodConfirmationViewModel.replaceSourceInput` (`FoodConfirmationView.swift` near lines 61 to 86) today builds a fresh state, so `decisions` is `[:]` after any rebuild. It must carry `decisions[.fortification] = .notSure` into the rebuilt state **while the rebuilt candidate's fortification is still `unknown`**, and drop it otherwise; no other decision is carried. It also carries `answersLabelFortification` (with `quantity` and `occurredAt`, as today), and all of this only while `state.reopened == nil` (it already returns early otherwise). Without the flag, `sourceIdentityMissing` would return after the rebuild and the carried `not_sure` would throw `staleDecisions`. Yes and No live in the source model's held details, so they survive rebuilds through C12. The rebuild paths are: a value Correct, Remove value, basis Change, and Back to Confirm from the label text screen. |
| C12 | **Back to Confirm never overwrites the answer.** Today `returnToConfirm` (`PastedLabelTextViewModel.swift` near lines 81 to 85 and 136 to 139) calls `PastedLabelSourceModel.updateDetails(details)` (near lines 388 to 393) with the text screen's whole details, which would reset a Confirm Yes or No to `unanswered` once the text screen loses its picker. `updateDetails` is split into `updateNameAndBrand(name:brand:)`, which keeps the held answer, and `answerFortification(_:) throws`, which rebuilds and throws on failure (so Confirm can show the failure copy of 4.1 and keep the earlier answer). The held answer is exposed read-only (`fortificationAnswer`). |

## 4. Exact copy

British spelling, plain language, no emoji. New strings live in `PastedLabelText`; the generic `FoodLogRequirementText` keeps its catalogue wording for every other route.

### 4.1 Fortification section

| Element | Copy |
|---|---|
| Section header | `Fortification` (the question is the first row of the section and the picker's accessibility label) |
| Question (picker label, VoiceOver label) | `Does the label say vitamins or minerals are added?` |
| Option 1 | `Yes, it lists added vitamins or minerals` |
| Option 2 | `No, the ingredients list none` |
| Option 3 | `Not stated` |
| Footer, unanswered | `Check the ingredients or claims on the pack. Choose Not stated if the text you have does not say, for example a nutrition table without its ingredients.` |
| Footer, Yes | `Saved as a fortified food.` |
| Footer, No | `Saved as not fortified.` |
| Footer, Not stated | `Fortification stays unknown, so this entry is marked as an estimate. The label’s values are kept as read.` (curly apostrophe, as the route's other copy) |
| Failed answer change | `The answer could not be applied. Your earlier answer is kept.` |

### 4.2 Requirement and bar

| Where | Copy |
|---|---|
| Pinned bar beside a disabled Log, and the "Before you log" row, when the answer is missing | `Answer whether the label says vitamins or minerals are added.` |
| VoiceOver hint on the disabled Log | the same sentence |
| Estimate notice beside the food (existing renderer, `savesEstimate`) | existing `FoodConfirmationViewModel.estimateNotice`, unchanged |

The phrase "Choose a different match or add the food details" never appears on a pasted-label Confirm.

### 4.3 Amount and Source footer

| Element | Copy |
|---|---|
| Unit picker value when servings are the default | existing `servings` |
| Amount caption with servings (existing `countsPastedLabelServings` caption) | unchanged |
| Source footer on a pasted-label Confirm | `To change the name, brand or text, use Edit label text. To change a value, correct it in Nutrition from the label.` (replaces "Need to correct the food itself? Choose a different match, …" for this route only) |

### 4.4 Label text screen

The "Fortified?" picker and its footer ("Does the pack say vitamins or minerals are added?") are removed. `PastedLabelText.fortifiedQuestion` and `fortifiedHelp` are deleted once no view uses them.

### 4.5 Developer tools and saved entry

The pasted-label details show `Fortification on the label: <value>`, from one **total** pure function in `FoodLedgerApplication`, beside `SavedFoodEntryDetail.swift` (near line 81), over the manifest answer, the current version's decision record and whether the current version is a correction. Every combination has exactly one row:

| Manifest answer | `not_sure` decision on fortification | Current version is a Food details correction | Shown |
|---|---|---|---|
| `yes` | any | no | `Yes` |
| `yes` | any | yes | `Yes, then corrected in food details` |
| `no` | any | no | `No` |
| `no` | any | yes | `No, then corrected in food details` |
| `unanswered` | yes | no | `Not stated` |
| `unanswered` | any | yes | `Not stated or not answered, then corrected in food details` (a correction's version carries only the correction assertion, so an earlier Not stated cannot be told apart; section 14) |
| `unanswered` | no | no | `Not answered` |

A `yes` or `no` manifest with a `not_sure` decision cannot be saved (C5 and the stale-decision rule), but the function still answers from the manifest, so it never fails. Table-tested row by row (8.5.13).

## 5. Screen order and states

### 5.1 Order (new entry, pasted label)

1. **Food**: name, brand, source line, estimate notice when Not stated is chosen.
2. **Fortification**: the section of 4.1.
3. **Amount eaten**: quantity, unit (servings by default under C8), Whole pack, When, Weighed on a plate, as today.
4. **Nutrition from the label**: the existing `PastedLabelSourceSections` (disclaimer, basis line with Change, values with Correct actions, serving lines, "Printed but not read", "Read but not used").
5. The existing remainder: compact nutrition for the amount, Save as favourite, Source details, recovery, Before you log.

A reopened pasted-label entry keeps the same order. Its Fortification row is read-only, showing the recorded answer (4.5), because reopened entries bypass decisions (v5 section 3).

### 5.2 State table

| State | When | What the user sees | Log |
|---|---|---|---|
| Loading | Reading the label (label text screen, unchanged); a Yes or No rebuild is synchronous on Confirm | Existing reading progress; no spinner on Confirm | n/a |
| Blocked: fortification | Answer missing | Fortification section with no option selected; bar copy of 4.2 | Disabled |
| Blocked: amount | No amount, or other existing typed requirement | Existing field-local messages; servings unit when C8 applies | Disabled |
| Blocked: both | Answer and amount missing | Fortification first (requirement order follows the screen) | Disabled |
| Partial | Rows not read, or values unknown | Existing "Not read" rows and "Printed but not read"; unknown stays unknown, never zero | Enabled once requirements are met |
| No serving | No serving size read, or servings not offered (for example an unknown parser version) | Unit opens on the basis unit (`g`, or `mL` for per 100 mL); no Whole pack | as requirements |
| Estimate | Not stated chosen | Estimate notice beside the food; Not stated footer | Enabled when the amount is set |
| Failed: answer change | The Yes or No rebuild throws | 4.1 failure copy; previous answer, corrections, amount and time kept | Unchanged |
| Failed: save | Existing `saveFailed` | Existing recovery section | Retry as today |
| Saved / reopened | After Log, or Edit | Read-only answer (4.5); existing exits | n/a |

## 6. Persistence and compatibility

| Answer | Manifest `fortification_answer` | Identity / item class | Assertion | Operation |
|---|---|---|---|---|
| Yes | `yes` | `fortified` / `fortified_food` | none (plain exact save) | as today for a pasted label |
| No | `no` | `unfortified` / `food` | none | as today |
| Not stated | `unanswered` | `unknown` / `food`; the candidate decision is recorded `rejected` with reason `fortification`, as v2 records an unknown-identity generic estimate (section 14) | exactly one, the v5 "Exact with decisions" row: reason `Logged with inline decisions under food_confirmation_v5`, claim `Logged under food_confirmation_v5; decisions: fortification: source unknown, choice not_sure`, record `[fortification, unknown, not_sure]` | `confirm_food_v3` |

- Every value above already exists and already decodes strictly (`not_sure` against an unknown source state is a valid `FacetDecision`). The persisted grammar is unchanged, so `methodVersion` stays `food_confirmation_v5` and no new policy identifier is needed.
- Food contract and store stay at the current levels (contract 7, `food-ledger-v7`): `confirm_food_v3` needs contract 4 or later, which a pasted-label archive already exceeds.
- Records written before this change decode, verify and re-encode byte for byte. A pre-change entry fixed through Food details keeps its correction and reopens unchanged.
- The Daily JSON food export ([food daily export v1](food-daily-export-contract-v1.md)) gains no field; a Not stated entry's estimate status reaches it through the existing projection only.

## 7. Reader v3 freeze

`ReaderV3FreezeTests` pins (pin 3) every file of `NutritionLabelParsing`, and `FoodLedgerApplication/PastedLabelManifest.swift`, `LabelReading.swift`, `PastedLabelSource.swift`, `PastedLabelConfirmation.swift`, `PastedLabelBasisChoice.swift`, `PastedLabelManifestV2.swift`, `PastedLabelServingPolicy.swift`, `PastedLabelServingSizeGrammarV3.swift`, `FoodLabelTextCapture/NutritionLabelTextReader.swift` and the fresh-set harness. **None of them changes.** The design only calls existing API in them (`PastedLabelDetails`, `PanelSourceAdmission.applies`, `PastedLabelServingPolicy.serving`). `FoodLedgerDomain/PastedLabelDomain.swift` is not pinned but feeds the manifest verifier, so its behaviour does not change: `FortificationAnswer` gains no case. Its stale doc comments (near lines 46 and 51 to 54: "The optional Fortified? answer on Confirm" and "unanswered is unknown (which raises the existing `sourceIdentityMissing` requirement)") get a **comment-only** fix in the implementation PR, saying that the answer is given on Confirm and that unanswered is unknown, which raises `sourceIdentityMissing` for catalogue-style resolution but is an inline decision on an editable pasted-label Confirm (C4). No re-pin is needed; the freeze test must pass unchanged.

## 8. Architecture gate

### 8.1 Responsibilities

| Layer | Change |
|---|---|
| Domain | None. `FortificationAnswer`, `FoodLogDecisionRecord`, `FacetDecision`, `offeredChoices` and `IdentityCompatibility` are unchanged. |
| Application | New file `FoodLedgerApplication/PastedLabelFortificationPolicy.swift`: a pure `applies(_ state:)` that is true when `PanelSourceAdmission.applies(input, candidate:)` holds (C6a) and either the state carries `answersLabelFortification` or it is a reopened entry whose current decision record has `fortification: not_sure` (C4); and `offeredChoices` = `[.notSure]` (C5). `FoodConfirmationState` gains the transient `answersLabelFortification: Bool` (default false). `FoodConfirmationState` is synthesised `Codable` (`FoodConfirmation.swift` near line 159), so it gets explicit `CodingKeys` that exclude the flag: it is never in encoded bytes and always decodes as false. The **state property** `FoodConfirmationState.unresolvedIdentity` omits `.fortification` when the policy applies; the static `FoodConfirmationPolicy.unresolvedIdentity` is unchanged (C4). `FoodLogPolicy.offeredChoices(state, facet: .fortification)` narrows to `[.notSure]` and `FoodLogPolicy.decisionRecord` throws `staleDecisions` for any other fortification choice when the policy applies (C5). `FoodConfirmationState.init` opens on `.count` under C8, after the per 100 mL rule (which now uses the C6a predicate) and only when `quantity.value == nil` and `reopened == nil`. A total formatter for 4.5 sits beside `SavedFoodEntryDetail.swift`. |
| Infrastructure | None. No GRDB, schema, archive or provider change. |
| Presentation | `PastedLabelSourceModel`: `updateDetails` is split into `updateNameAndBrand(name:brand:)` (keeps the held answer) and `answerFortification(_:) throws` (rebuilds; on failure the earlier answer, corrections and model stay), with the held answer exposed read-only as `fortificationAnswer` (C12). `PastedLabelTextViewModel`: loses `fortification` and its picker; `returnToConfirm` calls `updateNameAndBrand` only; Read again builds a new source model, so the answer resets (C10). `FoodConfirmationViewModel`: the paste route sets `answersLabelFortification` when it opens Confirm on an editable source; gains `pastedLabelFortification` (unanswered, yes, no, notStated, from the source model's held answer and the state's decision) and `answerFortification(_:)`, which calls the source model's throwing `answerFortification` for Yes or No (showing the 4.1 failure copy if it throws) and sends `decideDifference(.fortification, .notSure)` for Not stated; `replaceSourceInput` carries `decisions[.fortification] = .notSure` across a rebuild while the rebuilt candidate's fortification is still `unknown`, and drops it otherwise (C11). The view renders the order of 5.1; the generic decisions loop (`FoodConfirmationView.swift` near lines 875 to 881) skips `.fortification` when the policy applies, because the Fortification section renders it; "Add food details" and "Choose a different match" are hidden only for an editable pasted source (C6); the requirement maps to 4.2 copy. |
| Composition root | One line in `FoodLedgerCompositionRoot` (`open(_:)` near lines 801 to 808, beside `pastedLabelConfirmation` near lines 462 to 467): after building or reusing the Confirm model for a pasted source, call `model.answersLabelFortification(for: source)`. That entry point on `FoodConfirmationViewModel` (whose `state` is `private(set)`) sets the flag only when `source.isEditable`; nothing else sets it. |

### 8.2 Dependency direction

Unchanged: presentation → application → domain. The new policy reads only `PopulatedFoodConfirmation` and domain types; it does not import the parser, SwiftUI or GRDB. `check-boundaries.sh` needs no new rule because no target is added.

### 8.3 Invariants

1. Every save is the Log press; the answer is never preselected or inferred, and model output never answers it.
2. Unknown stays unknown: Not stated stores `unknown`, never `unfortified`.
3. One home per meaning: Yes and No live in the manifest and identity; Not stated lives in the decision record. A pasted-label save never carries both a known fortification and a fortification decision.
4. Requirements other than the pasted-label fortification facet, and every other route, behave exactly as before (v5 sections 2 and 3).
5. Stored records decode and re-encode unchanged; no frozen file changes.
6. The amount is never filled in for the user; only the unit default changes, and only at opening.

### 8.4 Extension axes

Kept closed. The pasted-label fortification policy is one small route-owned type, not a framework for per-route facet wording. If another route later needs a label-wording decision, it adds its own policy beside this one and its own contract.

### 8.5 Contract tests to add (written first)

1. **Policy scope:** for an editable pasted-label input (`answersLabelFortification`) with `unanswered`, requirements are `[decideDifference(.fortification), amountMissing]` and never contain `sourceIdentityMissing`; for a catalogue exact product with unknown fortification, `sourceIdentityMissing([.fortification])` is unchanged.
2. **Identity v1 closure:** for every `FortificationAnswer` and every basis, `pasted-label-identity-v1` with C4 yields an empty `unresolvedIdentity`, so C6 holds by construction.
3. **Yes and No:** the rebuild gives manifest `yes` / `no`, identity `fortified` / `unfortified`, item class `fortified_food` / `food`, no material difference, a plain exact save with no assertion.
4. **Not stated:** saves exactly one assertion with the golden reason, claim and record of section 6 under `confirm_food_v3`; manifest `unanswered`; identity `unknown`; the estimate projection is true on memory and GRDB stores and after an archive round trip; no library entry.
5. **Refused direct saves** with the view model bypassed: an unanswered pasted label; `differs:fortified` and `differs:unfortified` on a pasted-label source; a `not_sure` decision with a known fortification (stale decision after Yes or No).
6. **Decision clearing:** Yes or No after Not stated clears the decision; Read again resets to unanswered; basis Change keeps the answer.
7. **Reopen:** a Not stated entry reopens with no requirement from fortification, a quantity or time edit writes no assertion and keeps the estimate status from the original version.
8. **Compatibility:** pre-change pasted-label entries (answered, and corrected through Food details) decode, verify, reopen and re-encode byte for byte; `ReaderV3FreezeTests` passes with no re-pin.
9. **Servings default:** opens on `.count` with an empty amount when `PastedLabelServingPolicy.serving` is non-nil (per 100 g with an exact serving, per serving column); stays on `g` or `mL` when it is nil (no serving size, unknown parser version); a reopened entry and a query amount keep their unit.
10. **Rebuilds keep the answer (C11, C12),** each for Not stated and for Yes / No: value Correct, Remove value, basis Change and Back to Confirm keep the answer (Not stated as `decisions[.fortification] = .notSure`, Yes / No as the held manifest answer); a rebuild that makes fortification known drops a carried `not_sure`; Read again resets to unanswered with no decision. Explicitly: answer Yes, open Edit label text, change the text and the brand, Back to Confirm, still Yes. After each of Correct, Remove, Basis Change and Back to Confirm, `answersLabelFortification` is still set and the requirements never contain `sourceIdentityMissing`.
11. **One scope predicate (C6a):** the policy and the per 100 mL default use `PanelSourceAdmission.applies`; a forged release with the pasted source ID and no valid manifest is refused by panel admission at build and at save before any requirement is evaluated, so C4 never applies to it.
12. **Unchanged callers (C4):** the static `FoodConfirmationPolicy.unresolvedIdentity` returns the same results as before for catalogue, generic and pasted identities; `FoodEntryEstimateStatus` and `FoodLogPolicy.savesEstimate` are unchanged for catalogue and generic sources.
13. **4.5 formatter:** every row of the 4.5 table, including Not stated then a later Food details correction, and `unanswered` with neither (`Not answered`).
14. **Decisions loop and offered set (C5):** `FoodLogPolicy.offeredChoices(.fortification)` is `[.notSure]` for a pasted-label source and the domain's full set for a catalogue source; `decisionRecord` throws `staleDecisions` for `differs:fortified` and `differs:unfortified` on a pasted-label source; the generic decisions loop renders no fortification row there.
15. **Re-log and favourites (C6):** a re-log of a Not stated entry raises `sourceIdentityMissing([.fortification])` and offers Food details, as today. `QuickAddPolicy.eligibility` (`QuickAdd.swift` near lines 57 to 65): a Yes favourite and a No favourite are eligible exactly as a plain exact pasted favourite is today; a Not stated favourite is `.confirm(.estimate)`; a pre-change favourite fixed through Food details is `.confirm(.corrected)`.
16. **Daily JSON food export golden:** a Not stated entry exports with exactly the existing fields (no new key), its estimate status through the existing projection; the golden file is byte-pinned.
18. **Flag wiring:** `answersLabelFortification(for:)` sets the flag for an editable source only; a `PastedLabelSourceModel(stored:)` never sets it, and neither do re-log, favourite or reopen states.
19. **Flag never persisted:** an encoded `FoodConfirmationState` has no `answersLabelFortification` key, and decoding yields false.
20. **Opening unit pinned:** for every verified pasted-label fixture (per 100 g, per 100 mL, per serving, chosen basis) and for catalogue fixtures, the opening unit is as specified (C6a, C8).
17. **Archive round trip:** a pre-change pasted-label entry fixed through Food details (manifest `unanswered`, correction assertion) exports, imports and re-encodes byte for byte, and reopens with Food details still offered.

## 9. Test plan

**Pure (FoodLedgerKit):** the contract tests of 8.5; `PastedLabelFortificationPolicy` table tests; the 4.5 formatter for every stored combination; requirement order with both blockers.

**View model (app tests, `PastedLabelRouteTests` and Confirm view model tests):** `answerFortification` routes Yes / No through the source model's throwing `answerFortification` and Not stated through `decideDifference`; a failed rebuild keeps the earlier answer, corrections, amount and time and shows the 4.1 failure copy; the requirement copy is the 4.2 sentence, never the catalogue sentence; `foodDetailsActionTitle` is nil and "Choose a different match" is not offered on a pasted-label Confirm; the label text view model no longer carries fortification; tests that set `fortification` on the text screen are moved to Confirm; contract tests 10, 14 and 15 also run at view-model level (rebuild paths through `replaceSourceInput`, the hidden decisions row, Food details offered on a re-log).

**Simulator UI:**

1. Paste a per 100 g label with an exact serving size; Confirm shows Food, Fortification, Amount eaten (unit `servings`, amount empty), then the label values, in that order at default and AX5 text sizes.
2. Log stays disabled with the 4.2 sentence until an answer and an amount are given; Yes, then 1 serving, logs; the saved entry shows "Fortification on the label: Yes" and is not an estimate.
3. Not stated, 2 servings, logs as an estimate; the Food Log row carries the estimate prefix.
4. No Food details sheet appears at any point; the label text screen has no Fortified? picker.
5. A label with no serving size opens on `g` (per 100 mL label on `mL`) with no Whole pack.

## 10. Journey QA checklist (#306)

- [ ] Label text screen: Name, Brand, Label text and Read label only; no Fortified? picker.
- [ ] Confirm order: Food, Fortification, Amount eaten, Nutrition from the label, remainder (default size and AX5).
- [ ] Fortification: three options in 4.1 wording, none preselected, 44 pt rows, VoiceOver reads the question and each option, no colour-only state.
- [ ] Unanswered: Log disabled; bar and "Before you log" show "Answer whether the label says vitamins or minerals are added."; no "Choose a different match", no "Add food details".
- [ ] Yes: footer "Saved as a fortified food."; Log enabled once an amount is set; saved entry not an estimate.
- [ ] No: footer "Saved as not fortified."; saved entry not an estimate.
- [ ] Not stated: estimate notice beside the food; footer per 4.1; saved entry and Food Log show the estimate.
- [ ] Changing the answer before Log keeps corrections, amount and time.
- [ ] Unit opens on servings when the label states an exact serving; amount empty; Whole pack still offered when a pack count was read.
- [ ] No serving size: unit opens on g (mL for a per 100 mL label).
- [ ] Basis Change keeps the answer; Read again asks it again.
- [ ] Answer Yes, then correct a value, remove it, use Edit label text to change the brand and Back to Confirm: still Yes. Repeat with Not stated: still Not stated and still an estimate.
- [ ] Re-log a Not stated entry from Recent foods: Food details is offered, as before this change; a Not stated favourite asks for confirmation as an estimate.
- [ ] Reopened entry: Fortification read-only with the recorded answer; quantity edit saves.
- [ ] Developer tools show "Fortification on the label: …" per 4.5.
- [ ] Copy: British spelling, no emoji, nothing truncated at AX5.

## 11. Not changing

Reader v3 and every frozen version (section 7); the identity mapping's other facets; the basis sheet; serving policies and conversions; Whole pack; corrections to values; the catalogue routes' requirements, copy and Food details sheet; the estimate projection; the assertion grammar; HealthKit (read-only, untouched); egress (none).

## 12. Owner decision (Q1 closed)

**Q1. Should Not stated be an estimate?** **Decided: yes (owner, 24 October 2026).** It needs no change to the closed estimate projection, and it is honest that the product's identity is not fully known. The rejected alternative (Not stated on a user's own label as exact) would have needed a route-scoped exception in `FoodEntryEstimateStatus` and `FoodLogPolicy.savesEstimate` and a new decision token, so a grammar change. Consequence accepted: a Not stated entry is tagged "Estimate" in the Food Log and day totals, and creates no library alias.

## 13. Architecture gate findings applied (24 October 2026, on `d917d57d`)

Verdict: PASS WITH CHANGES. Every required change is applied.

| # | Finding | Where |
|---|---|---|
| 1 | `replaceSourceInput` resets `decisions` on every rebuild; carry `not_sure` while fortification stays unknown | C11; 8.1; test 10 |
| 2 | `returnToConfirm` would wipe a Confirm Yes or No; split `updateDetails`, throwing answer, read-only held answer; `PastedLabelSourceModel.swift` changes | C12; 8.1; test 10 |
| 3 | Re-log and favourites use a non-editable source; C6 applies only to an editable source; Quick add eligibility tests | C4 scope; C6; test 15 |
| 4 | Generic decisions loop skips fortification; `offeredChoices` narrowed; `staleDecisions` enforcement | C5; 8.1; test 14 |
| 5 | C4 names only the state property; static function unchanged | C4; test 12 |
| 6 | One scope predicate; forged release refused before C4 | C6a; test 11 |
| 7 | Total 4.5 formatter, home beside `SavedFoodEntryDetail.swift`, table-tested | 4.5; test 13 |
| 8 | Stale doc comment in `PastedLabelDomain.swift` | Section 7 (comment-only fix in the implementation PR) |
| 9 | Record the owner decision on Not stated | C3; section 12 |
| 10 | Extra contract tests: Daily JSON golden, archive round trip of a pre-change correction | Tests 16 and 17 |
| R1 | Re-check on `e94b3eff`: `replaceSourceInput` carries the flag, only before a save | C11; test 10 |
| R2 | Name the composition-root entry point; editable sources only | 8.1; test 18 |
| R3 | Record that the admission predicate is broader than the old check | C6a; test 20 |
| R4 | The flag is excluded from `Codable` | 8.1; test 19 |

### Files the implementation changes

`FoodLedgerApplication/PastedLabelFortificationPolicy.swift` (new), the 4.5 formatter (new, beside `SavedFoodEntryDetail.swift`), `FoodConfirmation.swift`, `FoodLogPolicy.swift`, `FoodLedgerDomain/PastedLabelDomain.swift` (comments only), `FoodLedgerPresentation/FoodConfirmationView.swift`, `PastedLabelSourceModel.swift`, `PastedLabelTextViewModel.swift`, `PastedLabelViews.swift`, `PastedLabelText.swift`, `FoodLogRequirementText.swift` if the route copy is mapped there, the Developer tools pasted-label details, and tests. No file pinned by `ReaderV3FreezeTests`.

## 14. Implementation notes (#306 build, 24 October 2026)

Where the build narrowed or completed the spec:

- **Candidate decision outcome for Not stated.** The domain refuses a `selected` `CandidateDecision` whose expected identity has an unknown facet (`hardIdentityContradiction`). A Not stated save is therefore recorded with the existing outcome `rejected` and `contradiction_reasons: [fortification]`, exactly as v2 records an unknown-identity generic estimate (`FoodConfirmationService`, the same branch as `isGenericEstimate`). No new value; tested in 8.5 test 4. Quick add still answers `.confirm(.estimate)` first for such a favourite.
- **Composition root.** The one-line wiring is in the paste route's `open(_:)`, an event handler, not in `pastedLabelConfirmation`, which runs while the view is built.
- **Section 4.5 surface.** "Fortification on the label" is shown on the saved entry (`SavedFoodEntryView`). Developer tools list only the current reading's lines (no stored entries, v5 section 5), and a new reading is always unanswered, so no Developer tools line is added.
- **Test 16.** The Daily JSON check pins that a Not stated entry exports exactly the same entry keys as a No entry (no new field), rather than a byte-pinned golden file, because the existing export tests build their own synthetic days.
- **Reopened entries.** The Fortification section shows the recorded answer read-only through the 4.5 formatter on any reopened pasted-label entry.
- **Invariant review of `381e694e` (BLOCK, fixed).** C4 never applies while a Food details correction is applied (`state.correction != nil`), for new and reopened entries alike: a correction carries no decision record, so its identity must be complete under the unchanged v5 rule. Without this, reopening a Not stated entry and applying a correction that left fortification unknown saved an exact entry with unknown fortification. Contract test: on a reopened Not stated entry, a correction with fortification unknown raises `sourceIdentityMissing([.fortification])`, and a correction to fortified or unfortified saves as exact.
- **4.5 after a correction.** Stores fill a saved entry's assertions from its current product and resolution versions, and the reader has no lookup by assertion ID, so the `supersedes_assertion_id` chain cannot be walked cheaply. The two corrected `unanswered` rows are therefore one row, "Not stated or not answered, then corrected in food details".
- **Test 4, library entries.** A pasted-label candidate carries no library aliases, so the D6 check (no library entry) holds trivially; the test pins that the archive has none after a Not stated save.
- **Journey QA of `381e694e` (PASS WITH NOTES, folded in under the owner's delegation).** (1) A Not stated favourite or Recent re-log was stuck behind "Choose a different match or add the food details". C4 now applies to every new pasted-label Confirm, so a re-log or favourite asks inline with Not stated (C6); Quick add still sends a Not stated favourite to Confirm as an estimate, and one explicit choice logs it. (2) The saved entry no longer repeats the decision as "Fortification: Not sure" under Source for a pasted label. (3) The section header is "Fortification". (4) While the Fortification section is shown, the estimate notice sits in its footer, below the answers, so choosing Not stated moves nothing under the finger (an exception to v5 section 5's "beside the food", agreed under the delegation). (5) Stored conversion methods are shown in plain copy: the pasted-label serving methods as "From the label’s serving size", the named recipe serving as "From the recipe’s serving" and the source-declared serving as "From the source’s serving size"; identifiers stay behind the Developer tools disclosure. Left for #308: the AX5 title truncation and the unit staying on mL after a basis change.
- **Invariant re-check of `b555285d` (BLOCK, fixed).** The question is asked only on an editable reading or when the source’s fortification is still unknown. A re-log or favourite of a stored label answered Yes or No asks nothing, shows “Fortification on the label: Yes” (or No) read-only, has no requirement and saves as exact; a Not stated tap there is a no-op, because Not stated is recorded only while fortification is a pending difference. The recipe and source serving method labels live in `FoodLogText`, beside the label serving copy in `PastedLabelText`.
- **Journey QA re-walk of `b555285d` (D2 to D4, folded in).** D2: a favourite pinned to a pasted label logged in servings shows its amount as servings (“1 serving”) on Home chips, the Add food Favourites rows, the Favourites list and the Quick add sheet (`FavouritesService.amountIsServings`, read from the pinned entry; the sheet reads its rebuilt source). D3: on a re-log or favourite Confirm the Source footer says “To change the label’s name, text or values, paste the label again from Add food.”, and no pasted-label Confirm suggests another match. D4: after Not stated the Fortification footer is the only estimate notice. Left for #308: the Quick add sheet title truncation.
