# Label plus generic estimate, v1 (#383, phase B of #381)

Status: architecture gate PASS WITH CHANGES (3 November 2026); all 12 findings applied below. No production code before this spec merges.

Plan: [`dark-chocolate-nutrient-sources-investigation.md`](dark-chocolate-nutrient-sources-investigation.md), section 4B. Phase A: [`cocoa-aware-search-v1.md`](cocoa-aware-search-v1.md). Merge rules: [`food-identity-nutrition-contract.md`](food-identity-nutrition-contract.md), section 8.

## Problem

A real dark chocolate bar is best recorded from its label: the label gives exact energy, fat, saturates, carbohydrate, sugars, protein and salt for that bar. Labels rarely print minerals, so iron, magnesium, potassium, zinc, copper, manganese and phosphorus stay unknown, although the bundled CoFID and USDA chocolate rows carry them. Phase A made the right generic rows easy to find; phase B lets the user keep the label and add the unprinted nutrients from one of those rows, labelled as estimates.

## Owner decisions (3 November 2026, recorded on #383)

1. **Cocoa percentage is decisive.** A generic row is compatible only when its stated cocoa band contains the bar's cocoa percentage, plus the two approved estimates with their notes: USDA FDC 167568 (unsweetened baking chocolate) for 100%, and the 70 to 85% band (FDC 170273) for 86% to 99%. With no cocoa percentage, no estimate is offered.
2. **Inside Confirm, before Log.** The label stays the selected food. An optional "Estimate unprinted nutrients" row lists compatible generic rows with nothing preselected. Choosing one shows a preview of each nutrient to be added, with source and release, marked as an estimate, and the estimate can be removed before Log. One Log action; the record cites both evidence sets; anything neither source has stays unknown.
3. **Cocoa percentage from the user.** Confirm shows a "Cocoa % on the pack" field, pre-filled when the product name or pasted label text states one; the user confirms it or types it. It is saved as a user-asserted attribute. Empty means no estimate.

## Rules

### 1. Which entries may offer an estimate

The "Estimate unprinted nutrients" row appears only when all hold:

- The selected candidate comes from the pasted label or label photo route, or is an Open Food Facts product admitted by [`off-label-estimate-v1.md`](off-label-estimate-v1.md) (#464), which takes the stored candidate as the evidence of record and checks it through one closed predicate, `OpenFoodFactsEstimateSource.applies`. Reviewed manufacturer pages are deferred: manufacturer entries require resolution nutrients to equal the candidate at save and reopen (gate finding, open question 2).
- Its name contains "chocolate" and none of milk, white or ruby (`CocoaPercentPolicy.chocolateTypes`). A milk chocolate bar states cocoa solids too, and no bundled row is a compatible estimate for it.
- Its basis has a known mass (per 100 g, or a serving with a stated mass). The resolution keeps the label's basis; generic per-100 g values are scaled to it with a named transform. A label basis with no mass offers no estimate.

### 2. Cocoa percentage field

- Pre-fill: one cocoa percentage from the candidate name, else (pasted labels) from the pasted text. The reader is `CocoaPercentPolicy.band(name:description:recordID:)` plus the label form "cocoa solids[: ]N% minimum" (B1). A range, more than one distinct value, an ingredient percentage ("30% cocoa butter") or a value outside rule 2's range gives no pre-fill. Until the UK reader is wired and the reader admits a cocoa solids line (#371), the pasted-text pre-fill is reached only through tests, and the name pre-fill is the shipped path.
- The field accepts 1 to 100, whole or one decimal place. The pre-fill is shown as a suggestion; the estimate list appears only after the user confirms or types a value.
- Saved as a user-asserted decisive attribute `cocoa_percent` on the confirmation, with the pre-fill origin (`name`, `pasted_text` or `typed`). The confirmed value, not the pre-fill, drives compatibility.

### 3. Compatible generic rows: `label-estimate-compatibility-v1`

A band predicate on one row, independent of which other rows are present, so reopen can recompute it. For the confirmed percentage `p`, a row is compatible when its provenance is a bundled `generic_composition_dataset` release (CoFID, USDA, TFDA as a regional source, or Ciqual as a reference-only source; never personal-library rows or library aliases), its name contains "chocolate" and none of milk, white or ruby, and:

- its declared band (`CocoaPercentPolicy.band`) contains `p`; or
- `p == 100` and its record ID is `CocoaPercentPolicy.estimate100RecordID` (FDC 167568); or
- `85 < p < 100` and its record ID is the pinned USDA FDC 170273 (70 to 85%) record ID.

The two pinned record IDs carry the owner decision; a later band (for example a Ciqual 80 to 89% row in phase C) adds compatibility only through the first bullet and never changes the result for these rows. Rows with no single band, blends and other bands are never offered. The list keeps phase A's tier order and shows phase A's note on each row ("Source covers 70 to 85% cocoa; you asked for 90%. Estimate only."). Regional rows follow non-regional rows, as in search.

### 4. Merge: `label-estimate-merge-v1`

A pure function in the application layer: label `NutrientSet` + chosen generic `NutrientSet` + its provenance → merged `NutrientSet` plus a per-key change list. Applied to each key in catalogue order:

| Label entry | Generic entry | Result |
| --- | --- | --- |
| `measured`, `augmented` or `bounded` | any | label entry, unchanged (a printed or product value is never overwritten, including a printed zero and a bound such as "less than 0.5 g") |
| `unknown` | `measured` or `augmented` with a value | generic value as `augmented`, with the generic row's provenance and the basis transform |
| `unknown` | `bounded` | generic bound as `bounded`, with its provenance |
| `unknown` | `unknown` | `unknown`, keeping the label's reason |

- Energy, fat, saturates, carbohydrate, sugars, protein and salt are filled from the generic row only when the label leaves them unknown; they keep the label value otherwise. Sodium and salt follow the existing pair rule and are never derived from each other by the merge.
- The full generic candidate is preserved in its own `CandidateDecision`; nutrient entries carry only the winner (section 8 step 6 at record level). `conflictCandidates` stays empty: no conflict can arise because a known label value always wins at a higher level.
- Copied generic entries keep the generic candidate's provenance verbatim (including its `decisionID` as stored on the candidate), plus the basis transform, so the merge is deterministic and reopen can recompute it.
- The generic decision's outcome is `selected_for_estimate`, a new typed outcome (or the existing nearest equivalent, fixed in B1): `CandidateDecision.init` forces `rejected` when identities contradict, and the generic row's unknown facets always contradict the label's identity, so the decision records estimate use without identity acceptance.
- The merge never changes identity, name, brand, barcode, pack facts or the amount.

### 5. Saved record

Every estimate-layer fact lives in an existing row; `StoredFoodConfirmation` is assembled by the reader, so the layer is an aggregate value only (`estimate: StoredLabelEstimate?`), never encoded on its own.

- Label candidate, evidence and decision: stored unchanged, so manifest verification still holds byte for byte.
- Generic choice: a second `CandidateDecision` row in `candidate_decision`, with its evidence in `candidate_decision_evidence` and its release in `source_release`.
- Cocoa percentage, its origin (`name`, `pasted_text`, `typed`), the policy versions (`label-estimate-compatibility-v1`, `label-estimate-merge-v1`) and the chosen generic row's name and description (B2: `CandidateDecision` keeps neither, and reopen needs them to rerun rule 3): typed fields of one optional `labelEstimate` value on the save's single `UserAssertion`, omitted when nil (the `confirmation` field precedent), so earlier assertions re-encode unchanged. The one-assertion-per-save rule holds.
- Resolution version: the merged nutrients, `sourceReleaseIDs` with both releases and `decisionIDs` with both decisions in position order, label first.

Operation types and registry:

- `confirmFoodV4` = the existing V1, V2 and V3 cases plus an estimate layer; it may carry typed decisions and declarations. Entries without a layer keep writing `confirmFood`, `confirmFoodV2` or `confirmFoodV3` exactly as today.
- A new registry `builtInV8` admits V4; `builtInV4` and `builtInV6` reject it. V4 joins `declaredQuantityTypes` and the retry list, and retrying a V4 save returns the stored entry.
- Editing a V4 entry that keeps the layer writes V4; an edit with a `correction` drops the layer and writes the case it would write today. Re-resolution is refused for entries with a layer in v1 (it replaces a whole resolution with one generic candidate and would discard the label).

Archive and store:

- `foodContractVersion` 8; `exportFloorContractVersion` stays 6. `minimumContractVersion` returns 8 only when a layer is present (a typed cocoa assertion or more than one decision per resolution version); the per-operation map sends V4 to 8. A store without layers still exports contract 6 or 7.
- GRDB: the schema already stores ordered decisions per resolution version and evidence per decision, so no table changes. The reader loads every decision in `decisionIDs`, in order, with its evidence. A metadata-only migration `v8_label_estimate` (`food-ledger-v8`, user_version 8) makes older binaries decline the store instead of failing integrity checks; historical migration hashes stay unchanged.

### 6. Reopen and verification

Reopen verifies each layer separately, then recomputes:

1. Label layer: the existing pasted-label or photo verifier checks the restored label candidate against its manifest.
2. Estimate layer: the stored generic decision is checked against its stored `SourceRelease` (release present; every copied entry's provenance names that release and record). The bundle is not re-read: no port looks rows up by ID, and section 9 forbids a withdrawn release from blocking reopening.
3. Compatibility: `label-estimate-compatibility-v1` rerun in full on the stored cocoa percentage, the stored row name and description, the decision's record ID and the stored generic nutrients must admit it.
4. Nutrients: with a layer, the resolution nutrients must equal `label-estimate-merge-v1(label, generic)`; without one, they must equal the label candidate, as today. The same rule replaces the equality checks at save of a reopened entry.

Any mismatch blocks reopening with the existing integrity failure state.

### 7. Confirm interaction

Under the label values, a section "Estimate unprinted nutrients":

- Cocoa % on the pack (field, pre-filled suggestion, explicit confirm with "Use this percentage"). A suggestion confirmed unchanged keeps its origin (`name` or `pasted_text`); any edit makes it `typed`. Editing a confirmed value withdraws the confirmation, the list and any choice. Empty or invalid text gives no list.
- After confirmation: the compatible rows, each with name, source family, release and phase A note; nothing selected.
- Candidate pool (`label-estimate-pool-v2`): one search of the query "dark chocolate <p>%" through the generic search port the search route uses, wired at the composition root (bundled CoFID, USDA, TFDA as a regional source and Ciqual 2025 as a reference-only source, `composite-generic-ranking-v11`, with the personal library's exact-alias reuse; no Open Food Facts and no network). The pool version is stamped as the evidence's `captureMethodVersion` and names the source set: `label-estimate-pool-v1` was CoFID, USDA and TFDA; `label-estimate-pool-v2` (#384, programme lead decision under the owner's delegation, 4 November 2026) adds Ciqual. Entries saved with v1 evidence keep it and reopen unchanged; nothing on reopen reads the stamp. Rows are kept when rule 3 admits them, distinct by record ID, in search order. The search evidence is a `generic_search` capture with method `label_estimate_pool_search`, so a saved estimate never claims a search the user typed; the chosen row is saved with that evidence and its release, as the search route saves a match. Tests pin 40, 50, 70, 85, 85.5, 86, 90, 99, 99.5 and 100%, including FDC 170273 for 86 to 99% and FDC 167568 for 100%, and under v2 Ciqual 31005 after the CoFID and USDA rows at 50% and 31074 after FDC 170273 at 70%. A personal-library alias that matches the query exactly returns only that saved row, which rule 3 refuses, so no estimate is offered then.
- The search runs only after confirmation; a failed search says "Estimates could not be loaded. Missing nutrients stay unknown." and Log is unchanged.
- After a food details correction the section stays with "Estimates are not available after food details are corrected. Missing nutrients stay unknown." and Log passes no estimate, because the save refuses an estimate on a corrected entry (rule 4: the merge never changes identity).
- After choosing a row: a preview list of only the keys that change, on the label's basis, each "Iron 11.9 mg · estimate · USDA SR Legacy 2018-04-01", and a "Remove estimate" action that restores the label-only state. Label values are listed as unchanged ("Unchanged from the label: Energy, Protein, …").
- Log with a chosen row passes the estimate to the save; with no row chosen it passes none, so the save is the label-only save byte for byte.
- No compatible row: "No estimate matches this cocoa percentage." Missing nutrients stay unknown.
- One Log action; Log is never blocked by the estimate section.

VoiceOver labels name each estimate as an estimate and its source; 44 pt targets; British spelling; no colour-only state. Wireframe input: none yet; the journey follows the existing Confirm sections.

### 8. Health, Copy all, Developer tools and export

Today `FoodEntryEstimateStatus.isEstimate` returns false for label sources, so an entry with a layer would not be marked. v1 adds the entry status "Partly estimated" beside it, `FoodEntryEstimateStatus.isPartlyEstimated`: the current saved version carries a label estimate layer. `isEstimate` keeps its meaning for every entry, and label-only entries are unchanged everywhere.

- One rule for the marking, `FoodEntryEstimateStatus.showsPartlyEstimated`, on every surface below: the entry carries a layer and is not an estimate as a whole. The whole-entry reasons are a generic or decided estimate (`isEstimate`) and an estimated amount; those keep "Estimate". Per-value states (augmented or calculated values, a calculated energy bound) never override the marking, as each value keeps its own.
- Food Log row: "Partly estimated" in place of "Estimate".
- Saved entry: the header reads "Partly estimated · Label values, with unprinted nutrients estimated from US reference", and an "Estimated nutrients" section names the row, its source family and release, the cocoa percentage with its origin ("Cocoa % on the pack: 90%, typed by you") and the estimated keys. Estimated values are marked "Estimated" beside each value and never carry a label origin such as "Printed".
- Developer tools (Settings › Developer tools on): the saved entry's section also lists the policy versions, both releases and both decisions, label first.
- Health and Copy all: they show day totals only, never food entries, and each total's "includes estimates" marker already reflects the estimated values it contains. No entry status is added there, so the Copy all text and its golden tests are unchanged and `health-copy-all-v2.md` needs no new version.
- Recent foods ("Partly estimated · Last: …") and Favourites ("25 g · Partly estimated") use the same rule.
- Logging a layered entry again (Recent foods, or a favourite through quick add) saves the label values only, because re-estimation is out of scope. Quick add never logs such a favourite in one step: it opens Confirm (`labelEstimateNotCarried`), and Confirm for a re-log or that favourite says "Logs the label values only. The estimated nutrients saved with the earlier entry are not logged again; missing nutrients stay unknown." An edit keeps the layer (section 5) and shows no such notice.
- On a label photo entry, a value the user left unknown that the estimate filled reads "Not on the label · Estimated", never both "Left unknown" and "Estimated".
- An estimated bound stays a bound on the saved entry ("Less than 0.5 g per 100 g · Estimated"), never "Unknown". The v1 bundled sources state no bounded values, so this is a guard for later releases.
- Per-nutrient lines keep each entry's own state.

The daily JSON export is unchanged: each estimated nutrient already carries its "estimated" state and the day totals' `includes_estimates` already marks the estimate, while entry-level estimate fields belong to #312.

## Not in scope

- Reviewed manufacturer pages (deferred; rule 1). Open Food Facts is admitted by [`off-label-estimate-v1.md`](off-label-estimate-v1.md).
- Ciqual (phase C); it becomes another compatible generic source through the same compatibility rule once admitted.
- Other foods than plain dark chocolate.
- Re-estimating saved entries after logging.
- Any new network destination.

## Architecture gate

**Responsibilities**

- Domain: typed optional cocoa fields on `UserAssertion`; the estimate decision outcome; `StoredLabelEstimate` on the aggregate; `confirmFoodV4`. Existing `NutrientEntry` validation already admits mixed provenance.
- Application: `LabelEstimateCompatibility` (rule 3) and `LabelEstimateMerge` (rule 4), pure and versioned; save, reopen, registry and retry extended for the optional layer; re-resolution refuses layered entries.
- Infrastructure: GRDB reader loads all decisions; metadata-only migration v8; archive contract 8.
- Presentation: a Confirm section driven by a small view-model slice; no rule in the view.

**Dependency direction:** presentation → application → domain; the bundled generic searchers are reached through the existing generic search port, wired at the composition root.

**Invariants:** label values never overwritten; unknown never zero; estimates labelled; nothing preselected or auto-saved; every save is one explicit Log; earlier records decode and re-encode byte for byte; label manifests still verify; no new egress.

**Extension axes:** generic sources (Ciqual in phase C) through the compatibility rule; other attribute-keyed estimates later would need their own versioned rule, not a generic framework.

**Contract tests (synthetic fixtures only)**

- Merge: each table row; printed zero; bound kept; sodium/salt never derived; catalogue order; generic provenance copied verbatim; scaling to the label basis; identity, pack facts and amount untouched.
- Compatibility v1: in band; 100 only with the estimate record ID; 85.5, 86, 99 and 99.5; blend and unbanded refused; an added 80 to 89% row does not change the result for an 87% bar; personal-library and alias rows refused; milk, white and ruby refused; empty percentage gives no list.
- Save and reopen: entries without a layer byte-identical under V1, V2 and V3; V4 round-trips; altered label manifest, generic decision, merged entry or cocoa assertion each fail reopen; a stored percentage the stored row does not admit fails; a withdrawn release still reopens; retrying a V4 save returns the stored entry.
- Registry: V4 with decisions and declarations admitted by `builtInV8`; V3 rules unchanged; `builtInV4` and `builtInV6` reject V4.
- Archive: contract 8 round-trip; contract 7 readers reject V4; pinned v1 to v7 fixtures byte-identical; a store without layers still exports contract 6 or 7.
- GRDB: all decisions load in position order with their evidence; v8 is metadata only; older schema readers decline v8; historical migration hashes unchanged.
- Status: an entry with a layer is "Partly estimated" on the Food Log, the saved entry, Recent foods, Favourites and Developer tools under one rule; Health and Copy all show day totals only, with "includes estimates"; label-only entries are unchanged.
- Re-resolution: refused for a layered entry.
- Presentation: pre-fill sources; no list until the percentage is confirmed; nothing preselected; preview lists only changed keys; Remove restores the label set; no-match copy; Log never blocked.
- Journey QA: pasted label and label photo routes in the simulator.

## Gate record

`architecture-gate`, read-only, 3 November 2026: PASS WITH CHANGES, 12 findings, all applied. High: estimate-layer storage (section 5), reopen nutrient equality (rule 6), operation-type rules (section 5), archive 8 (section 5), non-selected values and decision outcome (rule 4). Medium: no bundle re-read on reopen (rule 6), compatibility pinned to record IDs and gap-free (rule 3), basis direction (rule 1), bundled rows only (rule 3), entry-level estimate status (section 8), re-resolution excluded (section 5). Low: one assertion per save (section 5). B3 narrowed the entry-level status to the surfaces that show entries; Health and Copy all carry day totals only (programme lead decision under the owner's delegation, 4 November 2026).

## Delivery slices

- B1: compatibility and merge policies with contract tests (pure, no UI).
- B2: stored estimate layer, `confirmFoodV4`, reader, archive 8, reopen verification.
- B3: Confirm section, view-model tests, journey QA, invariant review, ledger row.

## Gate questions, answered from the code

- Schema: ordered decisions per resolution version and evidence per decision already exist; the reader took only the first. No table change; a metadata-only v8 migration (section 5).
- Routes: v1 covers pasted label and label photo; Open Food Facts and manufacturer pages are deferred to a later version with their own reopen verification (rule 1).
