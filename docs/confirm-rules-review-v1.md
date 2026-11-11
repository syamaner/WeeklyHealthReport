# Confirm rules review v1 (#470)

Status: owner decisions 1 to 5 taken, 11 November 2026. Architecture gate FAIL on the first draft, then PASS WITH CHANGES on the revision (both 11 November 2026); all findings applied below (see Gate record).

Amends, once decided: [`food-confirmation-contract-v5.md`](food-confirmation-contract-v5.md) section 3 (mandatory identity for exact products) and section 7 (the frozen `applyCorrection` reducer), [`food-quick-add-contract-v1.md`](food-quick-add-contract-v1.md) rule 3 and its favourite label line, and [`ux-revamp-phase-3-search.md`](ux-revamp-phase-3-search.md) ("a corrected exact product asks for identity details again; carrying corrections is #198"). Evidence: the owner's use of TestFlight 0.3.0 (30) on 11 November 2026, and a read-only inventory of every rule that blocks or adds a step on Confirm (same day).

## Problem

The owner: logging an Open Food Facts product is "annoying really", and saving it as a favourite does not help, because every later log asks for the same food details again. Direction: "We should review and relax the rules as we were over eager earlier."

What happens today for a packaged product found through Open Food Facts (search or barcode):

1. The product arrives with all six food details unknown: preparation, bone, skin, drained, packing medium and fortification (`OpenFoodFactsLookup.swift`, hard-coded). Log is blocked by `sourceIdentityMissing`.
2. The only way through is the Food details sheet. Apply stays disabled until a reason is typed (`FoodDetailsSheet.canApply`), and packing medium is free text: left empty, it stays unknown and Log stays blocked.
3. Applying it records a correction, which also clears any conversion or portion guide, asks to reconfirm an entered weight, and makes the entry ineligible for favourite quick add (`QuickAddPolicy.pinnedIsUncorrected`).
4. Re-log and a favourite rebuild the source candidate from the stored Open Food Facts record and drop the food details. The corrected name, brand and variant already carry today (they are restored from the saved product version); only the food details are lost. A fresh search for the same product starts from nothing. Only a barcode rescan through the personal library keeps everything.

Pasted labels and label photos already avoid most of this: they get a fixed "as sold" identity, with fortification asked inline as Yes, No or Not stated (`PastedLabelDomain.identity(fortification:servingBasis:)`). Bundled reference rows skip it as labelled estimates.

## What stays closed

These are product rules (AGENTS.md) and this review does not touch them:

- Nothing is saved without an explicit Log; no automatic selection.
- Unknown is never zero; estimates are labelled; partial totals are known minimums.
- Food records are versioned and append-only; stored records and archives decode and re-encode unchanged.
- No medical classification, targets or advice.

Food details being known before Log is an app policy (`food_confirmation_v1` to `v5`), not one of these rules. It exists so that "chicken, raw, with skin" and "chicken, roasted, without skin" are never logged with each other's values. For a packaged product eaten as sold, five of the six questions do not apply.

## Proposed rules

### 1. One tap: "Packaged product, eaten as sold" (owner's first choice)

1. **Where.** On Confirm for an Open Food Facts product (search or barcode) when `sourceIdentityMissing` is present and no `decideDifference` is pending. Shown above "Add food details", which stays. Not offered on other routes (manufacturer pages, reviewed web pages, generic rows and labels have their own paths; a library rescan already has known food details).
2. **What it asks.** One question, fortified: **Yes** or **No**. Nothing is pre-selected (Open Food Facts gives the app no fortification field). "Not sure" opens the full Food details sheet, where fortification stays unknown and Log stays blocked, as today: a correction cannot record a "Not sure" decision, and an unknown fortification on an exact product must not be reported as a non-estimate (gate finding 1).
3. **What it sets.** Preparation as sold; bone, skin and drained not applicable; packing medium "as sold" (the pasted-label value); serving basis, name, brand, variant and every value unchanged. **No** keeps the item class `food`. **Yes** sets fortified, which the record model requires to be item class `fortifiedFood`; that also withdraws a #464 estimate (the reference rows are unfortified) and, under rule 3, is not carried (gate finding 2).
4. **Visible and reversible.** Confirm then shows "Food details: packaged, as sold, not fortified" (or "fortified") with a Change link to the full sheet.
5. **How it is recorded.** Exactly as today's correction from the sheet (product version, assertion with the claim "Corrected populated confirmation for …", candidate decision), with the fixed reason "Packaged product, eaten as sold". No new record type, field or operation type; older and newer builds read it as an ordinary correction.
6. **Side effects.** Because it only fills unknown details (rule 2.1), it keeps an entered weight (no "Keep this weight"), conversion and portion guide, and with **No** keeps the #464 estimate layer.

### 2. Filling in blanks is not a correction to justify

1. **Fill-only test.** One pure application policy, `FoodDetailsFillPolicy`, decides whether a correction only fills in blanks:
   - **Live** (Confirm, against the selected candidate): name, brand, variant, nutrients, serving basis and declared fortificants are all equal; every food detail that differs was unknown both in the source and in the current identity (the correction, else the reopened saved product, else the candidate: the same order the reducer uses), so editing a saved "as sold" entry to "cooked", or changing a rule 1 answer, is not a fill; item class is unchanged, except `food` to `fortifiedFood` when the fortification fill is Yes.
   - **Stored** (re-log and quick add, against a saved entry): over typed fields only. The saved product's food details against `candidateDecision.candidate.identity` are fill-only; serving basis equal; the resolution's nutrients equal the candidate's (or its estimate layer merge); item class as restored today. It never reads the reason or claim text, so a typed reason that happens to equal a fixed one carries nothing (gate finding 4).
   - `OpenFoodFactsEstimateSource.isIdentityOnlyCorrection` (decision 6 of `off-label-estimate-v1`) is restated on top of it (value-preserving and not fortified), so the comparison exists once (gate finding 3).
2. **Reason optional.** When the live test holds, the Food details sheet's reason is optional; left empty, the record stores the fixed reason "Food details added". Changing anything the source states still needs a typed reason, as today.
3. **Packing medium choices.** The sheet gains "As sold" and "Not applicable" beside the free text, stored as named values with the frozen strings "as sold" and "not applicable" (no new state, so older builds decode them; gate finding 8).
4. **Reducer.** `applyCorrection` (frozen in v5 section 7) keeps weight, conversion and portion guide when the live test holds, and clears them as today otherwise: a count conversion entered against the item in hand stays valid when details go from unknown to as sold, not when raw becomes cooked (gate finding 7).

### 3. Re-log and favourites keep the food details you gave

1. **Carried.** When the stored fill-only test holds for a saved entry, re-log and favourite quick add start with its food details filled, shown as "Food details from your last entry" with a Change link. The new save records the fixed reason "Food details from your last entry".
2. **Not carried.** A correction that changed a stated detail or a value is not carried (its food details are dropped, as today). Decisions ("matches source", "Not sure"), fortified fills and estimate layers are not carried.
3. **Never bypasses a difference.** A carried fill is applied only when the rebuilt candidate has no material difference against what was asked for; otherwise those differences are decided first, as today (gate finding 5). On re-log and quick add the expectation is the source's own, so this normally holds.
4. **Order on re-log.** The carried fill is applied before the last amount, unit and portion guide are restored (re-log restores no conversion today), so it never clears them.
5. **Quick add.** Rule 3 of the quick add contract is rewritten: a pinned entry is eligible when it carried no correction, or when the stored fill-only test holds and its effective resolution equals the original. Eligibility is computed on the rebuilt state with the carried fill applied. A layered entry, or one with a fortified fill, still opens the full Confirm. Rule 2 (quick adds never grow the personal library) is unchanged.
6. **Favourite label.** Quick add v1 says the label defaults to the source name, "not a corrected product name", but the code restores the saved name. v2 records what the code does: the saved product name.
7. **Library alias.** Unchanged: a re-log with a carried fill can create a library alias, as any corrected save does today.

### 4. Later, not in this contract

- **Fresh search pre-fill** (the same barcode found through Open Food Facts search after an earlier log): needs a new local read port keyed on barcode and source, a stale-data rule and its own contract tests (gate finding 6). No egress. Proposed as a follow-up once rules 1 to 3 are in use.
- **Not sure fortification on an exact product** as a labelled estimate: needs a versioned assertion shape (gate finding 1, option b).

### 5. The other Confirm rules

| Rule | What it asks | Proposal |
| --- | --- | --- |
| Inline differences (`decideDifference`) | Choose "matches", "differs" or "Not sure" when a row differs from what you asked for | Keep. This is the one place a wrong food is caught. |
| "Not sure" makes an estimate | The entry is labelled an estimate | Keep (closed rule). |
| Amount required | A number above 0 | Keep. |
| Servings rules | Count servings when the source gives no serving weight | Keep. |
| Count needs a measured amount | "2 biscuits" needs a weight, a conversion or a portion guide | Keep; the last portion guide already carries on re-log, and a fill no longer clears it (rule 2.4). |
| Measured weight and basis, plate rules | Grams and measured or estimated basis | Keep. |
| "Keep this weight" after a correction | Reconfirm a weight when identity changes | Relax: not asked after a fill (rule 2.4). |
| Correction clears conversion and portion guide | Re-enter them | Relax: kept after a fill (rule 2.4). |
| Backdating window | Seven days back from today | Owner's call (decision 5). |
| Label layer not carried on quick add | A layered chocolate always opens full Confirm | Keep for now; revisit after device use of #464. |

## Architecture

- `FoodDetailsFillPolicy` and the rule 1 answer are pure `FoodLedgerApplication` code; the as-sold identity may reuse the domain constructor `PastedLabelDomain.identity`; Confirm gains one action. No port, store, migration or schema change. Boundaries unchanged (`check-boundaries.sh`).
- Rule 2 changes `FoodDetailsSheet.canApply`, the reason default and the packing medium choices (presentation), and the `applyCorrection` reducer branch (application).
- Rule 3 changes `relogInput`, `relogState`, `favouriteInput` and `QuickAddPolicy`. Reads only; each new entry is written exactly as a Confirm save writes it today.
- **Versions.** `FoodConfirmationPolicy.version` becomes `food_confirmation_v6` (written to resolution method versions and assertion reasons, read by nothing). `FoodLogDecisionRecord.currentPolicyVersion` stays `food_confirmation_v5`, because its decoder refuses any other value and changing it would make every stored decision undecodable (gate finding 9). Quick add contract v1 becomes v2. Operation types stay `confirmFood`, `V2` and `V4`. No food contract, schema or archive version change.

## Tests (to be fixed before code)

1. Live fill test: true only when every differing detail was unknown and name, brand, variant, nutrients, basis and fortificants are equal; each field changed alone makes it false; the Yes item class step is covered.
2. `isIdentityOnlyCorrection` is expressed through the fill test, and the existing Open Food Facts estimate contract tests pass unchanged.
3. Rule 1 with No and with Yes: the record equals a sheet correction with the fixed reason; name and values unchanged; operation type, candidate decision and claim as today. No keeps item class `food` and the estimate layer; Yes gives `fortifiedFood` and withdraws the layer.
4. Rule 1 offers no Not sure; Not sure opens the sheet and Log stays blocked.
5. Reducer: weight, conversion and portion guide kept after a fill, cleared after a stated-detail change. Reopening an "as sold" entry and changing it to cooked, and a second correction after rule 1, are not fills: a reason is required and the conversion is cleared.
6. Stored fill test over typed fields only: an entry whose typed reason equals a fixed reason but changes a stated detail is not carried.
7. Re-log and quick add carry a fill and need only an amount; a stated-detail or value correction is not carried; the carried fill is visible; layers are not carried; quick add rule 2 holds; quick add pinned-binding tests 6 and B still pass; eligibility uses the rebuilt state with the carried fill, and a fortified fill is not eligible.
8. A carried fill never bypasses a material difference.
9. Packing medium "as sold" and "not applicable" are stored as named values and decode on the previous build.
10. Stores and archives written before and after decode and re-encode byte for byte; a decision record with "food_confirmation_v5" still decodes after the version bump.
11. Journey: scan or search an Open Food Facts chocolate, tap "Packaged product, eaten as sold", answer No, Log; favourite it; quick add it with one amount and Log.

## Decisions for the owner

1. Rule 1, the one-tap answer for Open Food Facts products, asking only fortified Yes or No. Recommended: yes. **Decided by the owner, 11 November 2026:** yes.
2. Rule 2, no typed reason when only filling in blanks, plus the packing medium choices. Recommended: yes. **Decided by the owner, 11 November 2026:** yes.
3. Rule 3, re-log and favourites keep your food details, and such favourites can use quick add. Recommended: yes. **Decided by the owner, 11 November 2026:** yes.
4. Section 4, leave the fresh-search pre-fill and Not sure fortification for later. Recommended: yes. **Decided by the owner, 11 November 2026:** yes, later.
5. Backdating window: keep seven days, or widen it (for example to 30). Recommended: keep seven, since the Daily export covers seven days. **Decided by the owner, 11 November 2026:** keep seven.

## Gate record

Architecture gate, 11 November 2026: FAIL on the first draft; doc changes only. Applied: Not sure removed from rule 1 (finding 1); Yes changes item class and withdraws the layer (2); one fill-only policy with live and stored forms, decision 6 restated on it (3, 4); the problem statement corrected (name, brand and variant already carry); carried fills never bypass differences (5); fresh-search pre-fill deferred (6); weight, conversion and portion guide kept only for fills (7); packing medium as named values (8); decision record policy version stays v5 (9); quick add rule 3 rewritten and the label conflict resolved (10); scope narrowed to Open Food Facts and "only blocking" defined (11); no fortification pre-selection (12); fixed reasons named (13); readers and library alias confirmed unchanged (14). Re-gate, 11 November 2026: PASS WITH CHANGES, findings 1 to 14 resolved; applied: the live fill test also compares against the current identity (A), re-log restores no conversion (B), quick add eligibility uses the rebuilt state with the carried fill and refuses a fortified fill (C), the policy lives in the application layer (D).
