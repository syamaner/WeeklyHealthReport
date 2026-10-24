# Pasted label Confirm v1 (#306)

Status: **design spec and architecture gate, 24 October 2026. Documents only; no code has changed.** The owner approved autonomous delivery of #306, including this contract amendment, on 24 October 2026. Source: the UX review of `main` at `53450fb7` (issues 2, 3 and 4).

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
| C3 | **Not stated is a labelled estimate** under v5 section 5(b) (any `not_sure` is an estimate), unchanged: the product identity has an unknown decisive detail. The label's values are kept as read; the estimate notice says why. Library aliases follow v5 D6 (none for an estimate). See open question Q1. |
| C4 | **Pasted-label fortification is an inline decision, never `sourceIdentityMissing`.** For a pasted-label source, `FoodConfirmationPolicy.unresolvedIdentity` omits `.fortification`; the facet then appears through the unchanged difference computation (unknown on either side is a material difference) as `decideDifference(.fortification)`. This is the only change to the closed v5 rules, and it is scoped to the pasted-label source. |
| C5 | **The only admitted recorded decision for that facet is `not_sure`.** The service refuses `matches_source` (already refused against an unknown source state) and `differs:fortified` / `differs:unfortified` on a pasted-label source: a Yes or No must change the source, not be recorded as "eaten differs from source". |
| C6 | **Never the catalogue form for a pasted label.** On a pasted-label Confirm before saving, "Add food details", the Food details sheet and "Choose a different match" are not offered. Under `pasted-label-identity-v1`, fortification is the only facet that can be unknown, so after C4 `sourceIdentityMissing` can never arise for a pasted label (pinned by a test). |
| C7 | **Screen order:** Food, Fortification (the blocking decision), Amount eaten (with When), Nutrition from the label, then the existing remainder. Only the pasted-label sections move; their content is unchanged. |
| C8 | **Servings by default when the label states a serving.** On a new pasted-label Confirm with no amount yet, the unit opens on servings whenever `PastedLabelServingPolicy.serving(input, candidate:)` returns a serving (the same condition under which the picker offers servings today). The amount stays empty: no quantity is chosen for the user. |
| C9 | **The answer stays visible after it is given,** with the chosen option shown, so it can be changed before Log. It never disappears from under the user. |
| C10 | **Read again resets the answer** to unanswered and clears a Not stated decision: a new reading is a new source, and nothing carries over silently. Basis Change (reader v3 8.4.9) keeps the answer, because it rebuilds the same reading. |

## 4. Exact copy

British spelling, plain language, no emoji. New strings live in `PastedLabelText`; the generic `FoodLogRequirementText` keeps its catalogue wording for every other route.

### 4.1 Fortification section

| Element | Copy |
|---|---|
| Section header | `Fortification` |
| Question (picker label, VoiceOver label) | `Does the label say vitamins or minerals are added?` |
| Option 1 | `Yes, it lists added vitamins or minerals` |
| Option 2 | `No, the ingredients list none` |
| Option 3 | `Not stated` |
| Footer, unanswered | `Check the ingredients or claims on the pack. Choose Not stated if the text you have does not say, for example a nutrition table without its ingredients.` |
| Footer, Yes | `Saved as a fortified food.` |
| Footer, No | `Saved as not fortified.` |
| Footer, Not stated | `Fortification stays unknown, so this entry is marked as an estimate. The label's values are kept as read.` |
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

The pasted-label details show `Fortification on the label: Yes`, `No` or `Not stated`, derived by one pure function: `yes` and `no` from the manifest; `unanswered` with a recorded `not_sure` decision is `Not stated`; `unanswered` with a correction (entries saved before this change through Food details) is `Not answered (corrected in food details)`.

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
| Not stated | `unanswered` | `unknown` / `food` | exactly one, the v5 "Exact with decisions" row: reason `Logged with inline decisions under food_confirmation_v5`, claim `Logged under food_confirmation_v5; decisions: fortification: source unknown, choice not_sure`, record `[fortification, unknown, not_sure]` | `confirm_food_v3` |

- Every value above already exists and already decodes strictly (`not_sure` against an unknown source state is a valid `FacetDecision`). The persisted grammar is unchanged, so `methodVersion` stays `food_confirmation_v5` and no new policy identifier is needed.
- Food contract and store stay at the current levels (contract 7, `food-ledger-v7`): `confirm_food_v3` needs contract 4 or later, which a pasted-label archive already exceeds.
- Records written before this change decode, verify and re-encode byte for byte. A pre-change entry fixed through Food details keeps its correction and reopens unchanged.
- The Daily JSON food export ([food daily export v1](food-daily-export-contract-v1.md)) gains no field; a Not stated entry's estimate status reaches it through the existing projection only.

## 7. Reader v3 freeze

`ReaderV3FreezeTests` pins (pin 3) every file of `NutritionLabelParsing`, and `FoodLedgerApplication/PastedLabelManifest.swift`, `LabelReading.swift`, `PastedLabelSource.swift`, `PastedLabelConfirmation.swift`, `PastedLabelBasisChoice.swift`, `PastedLabelManifestV2.swift`, `PastedLabelServingPolicy.swift`, `PastedLabelServingSizeGrammarV3.swift`, `FoodLabelTextCapture/NutritionLabelTextReader.swift` and the fresh-set harness. **None of them changes.** The design only calls existing API in them (`PastedLabelDetails`, `PastedLabelSource.sourceID`, `PastedLabelServingPolicy.serving`). `FoodLedgerDomain/PastedLabelDomain.swift` is not pinned but feeds the manifest verifier, so it is not changed either: `FortificationAnswer` gains no case. No re-pin is needed; the freeze test must pass unchanged.

## 8. Architecture gate

### 8.1 Responsibilities

| Layer | Change |
|---|---|
| Domain | None. `FortificationAnswer`, `FoodLogDecisionRecord`, `FacetDecision`, `offeredChoices` and `IdentityCompatibility` are unchanged. |
| Application | New file `FoodLedgerApplication/PastedLabelFortificationPolicy.swift`: a pure `applies(input, candidate:)` (the candidate's source release has `sourceID == PastedLabelSource.sourceID`, the predicate `FoodConfirmationState.init` already uses for the per 100 mL default) and `admits(_ choice:) -> Bool` (only `.notSure`). `FoodConfirmationState.unresolvedIdentity` omits `.fortification` when it applies (C4), for new and reopened entries. `FoodLogPolicy` (requirements and the service check) refuses any other recorded fortification choice on a pasted-label source (C5). `FoodConfirmationState.init` opens on `.count` under C8, after the existing per 100 mL rule and only when `quantity.value == nil` and `reopened == nil`. A replaced pasted-label input (Yes / No rebuild, Read again) clears the fortification decision. |
| Infrastructure | None. No GRDB, schema, archive or provider change. |
| Presentation | `FoodConfirmationViewModel` gains `pastedLabelFortification` (unanswered, yes, no, notStated, derived from the source model's details and the state's decision) and `answerFortification(_:)`, which sends Yes or No to `PastedLabelSourceModel.updateDetails` and Not stated to `send(.decideDifference(.fortification, .notSure))`. The view renders the section in the order of 5.1, hides "Add food details" and "Choose a different match" when the policy applies, and maps the requirement to 4.2 copy. The label text screen loses its picker and `PastedLabelTextViewModel.fortification`. One pure formatter produces 4.5 for the saved entry and Developer tools. |
| Composition root | None. |

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

1. **Policy scope:** for a pasted-label input with `unanswered`, requirements are `[decideDifference(.fortification), amountMissing]` and never contain `sourceIdentityMissing`; for a catalogue exact product with unknown fortification, `sourceIdentityMissing([.fortification])` is unchanged.
2. **Identity v1 closure:** for every `FortificationAnswer` and every basis, `pasted-label-identity-v1` with C4 yields an empty `unresolvedIdentity`, so C6 holds by construction.
3. **Yes and No:** the rebuild gives manifest `yes` / `no`, identity `fortified` / `unfortified`, item class `fortified_food` / `food`, no material difference, a plain exact save with no assertion.
4. **Not stated:** saves exactly one assertion with the golden reason, claim and record of section 6 under `confirm_food_v3`; manifest `unanswered`; identity `unknown`; the estimate projection is true on memory and GRDB stores and after an archive round trip; no library entry.
5. **Refused direct saves** with the view model bypassed: an unanswered pasted label; `differs:fortified` and `differs:unfortified` on a pasted-label source; a `not_sure` decision with a known fortification (stale decision after Yes or No).
6. **Decision clearing:** Yes or No after Not stated clears the decision; Read again resets to unanswered; basis Change keeps the answer.
7. **Reopen:** a Not stated entry reopens with no requirement from fortification, a quantity or time edit writes no assertion and keeps the estimate status from the original version.
8. **Compatibility:** pre-change pasted-label entries (answered, and corrected through Food details) decode, verify, reopen and re-encode byte for byte; `ReaderV3FreezeTests` passes with no re-pin.
9. **Servings default:** opens on `.count` with an empty amount when `PastedLabelServingPolicy.serving` is non-nil (per 100 g with an exact serving, per serving column); stays on `g` or `mL` when it is nil (no serving size, unknown parser version); a reopened entry and a query amount keep their unit.

## 9. Test plan

**Pure (FoodLedgerKit):** the contract tests of 8.5; `PastedLabelFortificationPolicy` table tests; the 4.5 formatter for every stored combination; requirement order with both blockers.

**View model (app tests, `PastedLabelRouteTests` and Confirm view model tests):** `answerFortification` routes Yes / No through `updateDetails` and Not stated through `decideDifference`; a failed rebuild keeps the earlier answer, corrections, amount and time and shows the 4.1 failure copy; the requirement copy is the 4.2 sentence, never the catalogue sentence; `foodDetailsActionTitle` is nil and "Choose a different match" is not offered on a pasted-label Confirm; the label text view model no longer carries fortification; tests that set `fortification` on the text screen are moved to Confirm.

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
- [ ] Reopened entry: Fortification read-only with the recorded answer; quantity edit saves.
- [ ] Developer tools show "Fortification on the label: …" per 4.5.
- [ ] Copy: British spelling, no emoji, nothing truncated at AX5.

## 11. Not changing

Reader v3 and every frozen version (section 7); the identity mapping's other facets; the basis sheet; serving policies and conversions; Whole pack; corrections to values; the catalogue routes' requirements, copy and Food details sheet; the estimate projection; the assertion grammar; HealthKit (read-only, untouched); egress (none).

## 12. Open question for the owner

**Q1. Should Not stated be an estimate?** Recommended: **yes, as specified (C3).** It needs no change to the closed estimate projection, and it is honest that the product's identity is not fully known. The alternative is to treat Not stated on a user's own label as exact (the printed values do not depend on the answer), which would need a route-scoped exception in `FoodEntryEstimateStatus` and in `FoodLogPolicy.savesEstimate`, and a recorded choice that is not `not_sure` or a new token, so a grammar change. The cost of the recommendation: a Not stated entry is tagged "Estimate" in the Food Log and day totals, and creates no library alias.
