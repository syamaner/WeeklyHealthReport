# Personal food database: labelled estimates on catalogue v2, phase gate (#511)

Status: **gate revision 2, 17 November 2026, before production code.** It plans the one
implementation phase (decision P5) of the accepted contract
[estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md), called "the
contract" below. It changes no rule of the contract. Where it pins something the contract leaves to
"the phase gate", or reads an ambiguous sentence one way, it says so in section 3, and the contract
wins on any disagreement. Two points narrow an inherited rule and are listed for the owner in
section 5. Programme #424, issue #511. Review record in section 6.

Numbers checked at the start of the phase, as the contract's version allocation asks: food
contract 9 is the current one (`CanonicalFoodProjection.foodContractVersion`, `food-ledger-v9`), so
approved estimates take **contract 10**; the daily export writes version 2, so estimates take
**version 3**; identity amendment **A2** is already recorded for this work. None is taken.
Contract 9 added no provenance kind (it is detected from layered decisions), so the model for the
new kind is contract 6 (`app_reference_definition`).

## 1. Order of work inside the phase

One PR, as P5 decides. The tree builds and its tests pass after each step. **No step binds an
estimate to a candidate before save, quick add, re-resolution, presentation and the daily export
handle it:** the two wiring points that pass a file's estimates into the candidate builder are the
last code step (S9). Until then an accepted estimates v2 file behaves as its v2 part.

| Step | Scope |
|---|---|
| S1 | Skill checker: the estimate rules and the section 3.1 table on the v2 part, shared fixtures in `docs/fixtures/personal-food-database-estimates-v2/`, CI step. |
| S2 | Skill writer: private input format, validator, assembly, builder refusals, re-admission, the six counts, change report. |
| S3 | Domain codec: third schema value, key and schema order, estimate model, rule codes, Settings copy. Lookup port, three conformances, importer checks, store manifest round trip. The codec accepts the schema in the same step as the importer checks it. |
| S4 | `approved_estimate` provenance kind with its closed sites, including `FoodDailyExportOrigin.bySourceKind`; the two evidence method-version constants; food contract 10, floor and metadata-only migration; daily export version 3 writer and validator. A document with an estimate is version 3 from the first step in which the kind exists. |
| S5 | Pure pieces with tests: manifest and leave-out evidence types, the per-facet comparison, the eligibility policy, builder precedence behind a parameter that only tests pass. |
| S6 | Confirm state, effective nutrients, leave-out and its evidence, save, reopen, quick add and re-log. |
| S7 | Re-resolution service. |
| S8 | Presentation: labels with the tier in words, details, notices, the re-resolution screen, Settings count, Developer tools. |
| S9 | Wiring: the search route and the re-resolution provider pass estimates to the builder; search visibility, fat partition and escalation tests; the search evaluations. |
| S10 | `privacy-and-egress.md`, contract status notes, simulator journey, ledger row. |

## 2. Architecture gate

The contract's section 7 is the gate of record (responsibilities, dependency direction, invariants,
extension axes, contract tests). This section adds only what that table does not name.

### 2.1 Responsibilities added or made concrete

| Responsibility | Home | Boundary |
|---|---|---|
| Estimate file rules in Python | skill `scripts/estimates_v2.py`, which imports `export_v1` for its tables; `export_v1.check_bytes` imports it lazily inside the function, after the key and schema order of contract section 2 | pure; no file access |
| Accepted-estimates input: format `pfc-accepted-estimates-v1`, validator, admission with reasons, assembly | skill `scripts/estimates_input.py` (pure) and `scripts/apply_estimates.py` (the only new file that touches the workspace) | private workspace only; `workspace_guard` on every path |
| The six evaluator counts and the re-admission checks | skill `scripts/estimate_counts.py` (pure) | synthetic lists in tests |
| Estimate model: `PersonalFoodDatabaseEstimate`, `PersonalFoodDatabaseEstimateEvidence` and their closed enums | `FoodLedgerDomain/PersonalFoodDatabaseEstimates.swift` | pure |
| Estimate checks and the section 3.1 table | `FoodLedgerDomain`, an extension of `PersonalFoodDatabaseChecker` using `PersonalFoodDatabaseRules` | pure |
| `GenericRecordFacts` (nutrients, identity, edible quantity) | `FoodLedgerDomain` | pure value |
| `GenericRecordNutrientLookup`, `GenericRecordLookupFailure`, `GenericRecordLookupSet` | `FoodLedgerApplication`, beside `GenericRecordResolving` | domain types only |
| CoFID, USDA and TFDA lookup conformances | `FoodGenericSearch/PersonalFoodDatabaseResolvers.swift`, no `import Foundation` | the existing no-URL boundary rule |
| Importer checks (four value codes, `estimate-contradiction`) | `FoodLedgerApplication/PersonalFoodDatabaseEstimateAdmission.swift`, a pure function over the decoded file and a lookup, called by `PersonalFoodDatabaseImporter` | ports only |
| Per-facet comparison in which unknown does not contradict | `FoodLedgerDomain`, `EstimateIdentityComparison` beside `IdentityCompatibility` (which treats unknown as a contradiction and is left as it is) | pure |
| Eligibility policy (contract 3.2) | `FoodLedgerApplication/ApprovedEstimateEligibility.swift`, one pure function used at bind, after a correction, on undo and in re-resolution | pure |
| Capture manifest and leave-out evidence types and their strict decoding | `FoodLedgerDomain/ApprovedEstimateEvidence.swift` | pure |
| Manifest building and verification, the effective nutrient set, the changed-facts predicate, the saved-version guard | `FoodLedgerApplication/ApprovedEstimateConfirmation.swift` | `CanonicalEncoding`, `Digesting`, `LedgerIDGenerating`, the lookup |
| Daily export version 3: origin, `estimate_quality`, the three estimate fields, manifest URL, validator row | `FoodLedgerApplication` (`FoodDailyExport.swift`, `FoodDailyExportShape.swift`); Drive admission stays the existing `DailyFoodExportIdentityPolicy`, which calls the shape rule | closed table |
| Label, tier and notice wording; Settings copy; the withholding facet in Developer tools | `FoodLedgerPresentation` and the app target's views, from stored provenance and manifest evidence | presentation only |

No new target. One new port. The composition root wires the lookup set into the importer, the
confirmation service and the re-resolution service. `check-boundaries.sh` extends its
`PersonalFoodDatabase*.swift` file and network rule to `ApprovedEstimate*.swift`.

### 2.2 Dependency direction

Unchanged. Domain gains types and pure rules. Application gains one port, pure policies and
orchestration. `FoodGenericSearch` gains three conformances. Presentation reads application
projections. The skill is outside the app and reads the bundled corpus files only as files.

### 2.3 Invariants this phase must keep (beyond the contract's list)

1. A `personal-food-catalogue-v1` or `-v2` file gets the same codes, in the same order, as before;
   both golden files keep their bytes; regenerating both fixture folders changes nothing.
2. The codec accepts `personal-food-catalogue-estimates-v2` only from the step in which the
   importer runs the bundled-record checks on it, and no step binds an estimate to a candidate
   before save, quick add, re-resolution and export handle it (section 1).
3. The skill writes plain v2 bytes, identical to today's, when no estimate is admitted.
4. The writer never takes a national composition value from its input: it reads the bundled
   record, so a typed value cannot stand in.
5. The new skill scripts print counts, rule codes, entry IDs and hashes only, to the private
   terminal. No title, brand, shop or value is printed.
6. A save with no approved estimate, no manifest and no leave-out writes exactly the records and
   commit type it writes today, and `FoodLogPolicy.requirements` returns what it returns today.
7. `FoodConfirmationState` decodes a state saved before this change: its coding becomes
   hand-written, the new members are read with `decodeIfPresent` and default to empty.
8. The capture manifest's payload holds no time and no evidence ID, so the same release and entry
   always give the same bytes and hash.

### 2.4 Extension axes

As the contract: the store is the one variation point. The accepted-estimates input is versioned by
its `schema` string; a new field is a new version. The lookup port takes a new corpus as a new
conformance that passes the shared suite.

### 2.5 Contract tests

The contract's list in section 7 is the list. Homes:

| Tests | Home |
|---|---|
| Codec stage fixtures, pinned code orders, the shared URL list | `docs/fixtures/personal-food-database-estimates-v2/`, written by `test_export_check.py --write-estimates-v2`; read by `PersonalFoodDatabaseCodecEstimatesTests` (Domain) and asserted by the Python checker |
| Rule-code enum equals the manifest's list; v1 and v2 lists are subsets; facet parity of `EstimateIdentityComparison` and `IdentityCompatibility` | `FoodLedgerDomainTests` |
| Importer stage fixtures with a stub lookup; importer with no lookup rejects | `PersonalFoodDatabaseEstimateAdmissionTests` (Application) |
| Lookup shared suite over CoFID, USDA, TFDA and the set, agreement with `resolve`, fortification pins | `FoodGenericSearchTests` |
| Precedence, non-promotion, separate candidate without estimates, search visibility, fat partition, escalation | `PersonalFoodDatabaseSearchTests` and the builder's tests (Application) |
| Eligibility, manifest, leave-out, save, reopen, re-log, quick add, re-resolution | `FoodLedgerApplicationTests` and `FoodLedgerContractTests` |
| Contract 10 floor cases, archive restore, contract 9 binary declines, closed kind sites, `.labelText` reader isolation each way, migration and open check | `FoodLedgerContractTests`, beside the contract 9 tests |
| Store manifest round trip for the third schema | `FoodLedgerPersonalDatabaseTests` |
| Daily export version 3 goldens in `docs/fixtures/food-daily-v3/`, shape rule, origin table | `FoodLedgerContractTests`; Drive validation, reconciliation and recovery in `WeeklyHealthReportTests/DailyFoodDriveExportTests` |
| Five labels, colour never without text, notices, Settings copy for each new code (through the grouped `reason(for:)`), no value field for an estimate | `FoodLedgerPresentationTests` |
| Boundary self-test for the extended file rule | `check-boundaries.sh` |
| Skill: input format, admission reasons, assembly, byte-identical v2 when empty, additive proof; six counts with a failing case for each must-be-zero count, withdrawn row, never-re-admissible class, list row without an accepted sheet row | `test_estimates_input.py`, `test_estimate_counts.py` |
| Simulator journey of the contract's last test bullet, synthetic file | app UI tests |

## 3. What this gate pins

### 3.1 Codec

1. **Before the parts.** After the key and schema order of contract section 2, an estimates v2 file
   whose `items` or `estimate_evidence` is not a list gets `items` and nothing else, as the R2 tool.
2. **Order of the three parts.** The whole v2 checker first; then the inherited estimate checks in
   the R2 tool's order (evidence records in file order, then entries in file order with their
   estimated values in file order, then unused or shared records in file order); then the section
   3.1 table over `estimate_evidence` in file order. Codes are appended as found.
3. **`item-keys` once.** In the v2 part an entry of an estimates v2 file must have v2's keys plus
   `estimated_nutrients`; anything else is `item-keys` there, and the estimate loop skips that
   entry without a second code.
4. **Which records get table rows.** A record gets table rows only when all of these hold: no
   inherited code was raised for it or for the value that cites it; exactly one value cites it,
   from the entry it names; that entry raised no code in the v2 part; the entry's ID and the
   record's ID are each unique in the file. The contract's two sentences on this are read together
   as that one rule.
5. **Own record.** A `national_composition` record whose `composition_source` and
   `source_reference` equal the entry's `generic_reference` `source` and `record_id`, whatever its
   role. Rows 2 to 4 of the table apply to role `candidate` only.
6. **Ceiling.** `high` needs all four conditions of contract 3.3; a page estimate satisfies the
   fourth vacuously. Otherwise `medium`; `state_basis` `unknown` caps at `low`.
7. **Page URL grammar (narrows the R2 rule; section 5).** The R2 tool uses Python's `urlsplit`,
   which Swift cannot mirror exactly. Both checkers use one hand-written grammar: at most 2,048
   bytes; ASCII only, no byte below 0x21 or above 0x7E; the literal lower-case prefix `https://`;
   an authority that ends at the first `/` or the end, with no `@`, optionally `:` and 1 to 5
   digits giving a port from 1 to 65535; a host of labels of ASCII letters, digits and hyphens
   joined by single dots, at least two labels, an optional single trailing dot, not `localhost` or
   under `.localhost` in any case, and a last label that is not all digits and does not start with
   `0x` in any case; no `?` and no `#` anywhere; an empty path is allowed.
   `open-food-facts-host` is judged on the lower-cased host without its trailing dot. Against the
   R2 tool this refuses an upper-case scheme, a non-ASCII path or host, an underscore in the host
   and an empty port. Every URL this grammar accepts, the R2 rule accepts. A shared list of accept
   and reject URLs in the fixture manifest is read by both checkers.
8. **Free text length** counts Unicode scalar values, as Python's `len` does; blank is the existing
   `isBlank`.

### 3.2 Skill writer

1. **Input** `work/accepted-estimates.json`, schema `pfc-accepted-estimates-v1`, canonical JSON.
   Top level: `schema`, `catalogue_release_id` (the `pfc:sha256:` ID of the plain v2 document the
   rows were accepted against; a mismatch refuses the run), `rows`. Each row: `entry_id`; `scope`
   (`nutrient` or `entry`); for `nutrient` scope `nutrient`, and `value` and `unit` when the source
   is a page; `evidence` (the contract's evidence record without `id`, `entry_id` and `nutrient`,
   with `quality`); `underlying_source` (`not_applicable`, `stated_independent`, `open_food_facts`,
   `not_stated`); `relation` (`same_food` or `similar_food`, which must agree with `method`);
   `accepted` (`{sheet, row}` naming the review sheet row that carries the owner's accept mark and
   the tier shown there).
2. **Whole-entry scope** is national composition only. It expands to one estimate for each
   nutrient the bundled record quantifies in the key's canonical unit, read by the skill's existing
   record readers, and never for a key the entry already has.
3. **A national composition row never carries a typed value.** A page row carries its value, on
   the entry's own basis.
4. **Admission, first reason wins, each counted and none fatal:** `label_kept` (the entry has a
   label value on the key); `merged_kept` (the entry's reference has role `merge` and its bundled
   record quantifies the key); `composite` (a national composition estimate on a
   `packaged_composite` entry); `open_food_facts_source`; `refused_source` (on the refusal list and
   not re-admitted); `readmission_class` (re-admitted but of a never-re-admissible class);
   `unquantified` (the record has no quantified value for the key); `basis`; `transform`; `codec`
   (the row would raise a section 3.1 code, for example `estimate-own-held`, named in the count).
   `merged_kept` narrows estimates v1 decision C6 on the builder side only (section 5): the app
   rule stays label, then estimate, then merged record. Its stated limit: the app merges a record
   only when the record-side conditions also hold, which Python does not evaluate, so an entry
   whose `merge` record the app does not merge keeps such a key unknown.
5. **Refusals and re-admission** come from three private files: `work/estimate-refusals.json`
   (entry ID, `source_type`, `source_reference`, optional nutrient, the E3 refusal class),
   `work/estimate-readmissions.json` (the contract's row: entry ID, nutrient, `source_type`,
   `source_reference`, `method`, corpus hash, date) and the re-admission sheet as
   `work/estimate-readmission-sheet.json` (the same fields, the refusal class, its reason and the
   accept mark). A re-admitted row's `assumption` must contain the fixed sentence "The evaluation
   withheld this source and the owner re-admitted it." and its tier is at most `medium`.
6. **Output.** With at least one admitted estimate: schema
   `personal-food-catalogue-estimates-v2`, every entry gains `estimated_nutrients` (sorted by key,
   possibly empty) as its last key, and `estimate_evidence` (sorted by `id`) is the last top-level
   key, written to `out/personal-food-catalogue-estimates-v2.json`. Evidence IDs are `pfe:` and
   the first 16 hex digits of SHA-256 of `pfe-v1|<entry id>|<nutrient>`, the R2 builder's
   derivation (`r2_export.evidence_id`). With none: plain v2, unchanged. The writer proves the
   result is additive over the plain v2 document and refuses to write a file `check_bytes` rejects.
7. **Importer-stage rules are not mirrored in Python** (the contract gives parity for codec codes
   only). The change report says, in counts, how many estimates the app will check against a
   bundled record.

### 3.3 App: where the manifest is built and which evidence is saved

"Bound to Confirm" is the point at which the database route builds its `PopulatedFoodConfirmation`
(`PersonalFoodDatabaseFoodSearch.route` and `PersonalFoodDatabaseReresolutionProvider.candidates`):
`NutrientEntry` validation needs the evidence ID and manifest hash before a candidate exists. Each
candidate with at least one estimate gets its own manifest, its own evidence ID appended to that
candidate's `evidenceIDs`, and the manifest's `CaptureEvidence` in the confirmation's evidence,
with `capturedAt` the request's own time (the route's `request.capturedAt`, the provider's `date`),
which the callers take from the injected clock. The route gains `CanonicalEncoding` and
`Digesting`; no second time source is added.

A search confirmation can hold several candidates. Today a first save writes every evidence item
of the input. From this phase a save leaves out `pfd-estimate-capture-v1` evidence that the
selected candidate does not list, so one entry's log never stores another entry's manifest. No
other evidence kind is filtered.

### 3.4 App: Confirm state and the check

**Members.** `FoodConfirmationState` gains three, all defaulting to empty:

- `leftOutEstimates: Set<NutrientKey>`;
- `estimateRecords: [ApprovedEstimateRecordKey: ApprovedEstimateRecordState]`, the cited records'
  `DecisiveIdentity` or `unreadable`. **A key that is absent reads as unreadable** in the pure
  policy, so an unbound state withholds every composition estimate;
- `estimateSeed: ApprovedEstimateSeed`, set only by `reopen`: the left-out keys from the effective
  version's verified leave-out evidence, and `evidenceAvailable`, false when the manifest or the
  leave-out item fails its hash. With evidence unavailable the seed is empty and every saved
  unknown manifest key is frozen as unknown.

Two app sites rebuild a state from another (`FoodLedgerCompositionRoot.swift`, the fill-carrying
rebuild and reopen). They use one helper, `carryingEstimateState(from:)`, so the members survive.

**Binding.** `FoodConfirmationService.bindEstimates(_:)` reads, for every candidate of the input,
each record its manifest cites and fills `estimateRecords`. It runs wherever a state for a new log
is made from a database confirmation (search to Confirm, re-log, favourite, list import), after a
correction of details on a reopened log (with the manifest's source, hash and record ID), and on
undo of a leave-out on a reopened log. `reopen` does not call it. Without a lookup the service
leaves the map empty (closed by default). Each creation site has a test; a missed site withholds,
it never shows an unchecked estimate.

**The policy** takes the manifest, `estimateRecords`, the confirmed identity
(`correction?.identity ?? reopened?.productVersion.identity ?? candidate identity`) and the
candidate's own serving basis, and returns the withheld keys with their reason (a facet, the basis,
or an unreadable record).

**Effective nutrients**, a computed property, so it cannot go stale:

| State | Result |
|---|---|
| New log | the candidate's (or the correction's) nutrients, with every withheld or left-out manifest key `.unknown(.noCompatibleSource)` |
| Reopened, no correction, leave-out set equal to its seed | the saved resolution's nutrients, untouched; no record is read |
| Reopened, no correction, leave-out set differs from its seed | the saved resolution's nutrients; a newly left-out key becomes unknown; an undone key takes the manifest's estimate only when the policy passes it for that key with the bound records; every other saved unknown stays unknown |
| Reopened with a correction | the correction's nutrients with every withheld or left-out manifest key unknown, the withheld set from the manifest and the bound records; with evidence unavailable every saved unknown manifest key stays unknown |

Sites, each marked:

| Site | Reads |
|---|---|
| `FoodConfirmation.swift` save: reviewed-web guard, label guard | not affected (other routes) |
| `FoodConfirmation.swift` save: the resolution version's nutrients | effective |
| `FoodConfirmationView.swift`: scaled-serving notes, nutrition review, displayed values, totals | effective |
| `FoodConfirmationView.swift`: the source reference section | effective for manifest keys, so a withheld or left-out value is never shown as a value |
| `FoodDetailsSheet.swift` `correction(for:)`, `FoodConfirmationView.swift` and `FoodDetailsFillPolicy.swift` corrections built from the candidate | stay on the candidate (the manifest is the record of what was offered; withholding is applied on top) |
| `FoodDetailsFillPolicy.isFill` and `isStoredFill` equality | equal except manifest keys saved as unknown, so details are still carried to a re-log |
| `FoodReresolutionService.prepareAcceptance`, `FoodReresolution` diff | the fresh candidate's nutrients with withheld keys unknown (S7) |
| `FoodSearchStatusPresentation.databaseScaledServingNotes` | effective |

**Save.** The service never trusts the state's copy of `estimateRecords`: for a new log, a
corrected reopened log and an undo it rebinds a local copy of the state through its own lookup
before `FoodLogPolicy.requirements` and before computing what it writes.

**Saved-version guard**, on save and on reopen: for a database candidate that lists a manifest and
has no correction, the version's nutrients equal the candidate's except that a manifest key may be
`.unknown(.noCompatibleSource)`. Anything else is an integrity failure on reopen and
`invalidApprovedEstimate` on save.

### 3.5 App: the changed-facts predicate and its sites

`FoodLogFactsChange.changed(state)`: a correction is present, or the leave-out set differs from its
seed (for a new log, is not empty). It replaces the correction test at exactly these sites:

1. `FoodConfirmationService.save`, `changesProduct` (new product version, resolution, resolution
   version and candidate decision instead of the saved ones), and with it the mutation lists;
2. `FoodLogEditComparison.hasChanges` (and so `FoodLogPolicy.editChanges`);
3. the save's evidence list, which today is empty for a reopened log and now carries the new
   leave-out item;
4. `makeAssertion`, which today returns nothing for a reopened save without a correction and for
   a new log without decisions;
5. the log item version's `correctionReason`;
6. the commit type, which is still computed as today from the assertion and the weight
   declaration; a leave-out adds no commit type.

It does not replace the correction test in `FoodLogPolicy.pendingDifferences`,
`FoodLogPolicy.savesEstimate`, the label and layer admission branches of `save`, the candidate
decision's requested outcome, or `QuickAddPolicy.pinnedIsUncorrected`.

**A leave-out-only save on a reopened log** writes a decision whose `expectedIdentity`,
`expectedEdibleQuantity` and outcome are the saved decision's (`previous.candidateDecision`), not
the reopened input's: the input's expected quantity is the logged amount, a database candidate is
always 100 g or 100 ml, and `CandidateDecision` refuses `selected` with any difference. Its
embedded candidate is the bound candidate with the leave-out evidence ID appended to its evidence
IDs and nothing else changed. The assertion's `confirmation` is the decision record of the saved
version's assertion that has one, or none. The product version keeps the saved identity.

**Pinned texts** (persisted data, not UI copy):

| Case | Reason | Claim |
|---|---|---|
| Correction present | the correction's, as today | as today |
| New log, generic estimate or decisions, with a leave-out | as today for that case | as today, then `; estimated values left out: <keys>` |
| New log, no other assertion, with a leave-out | `Changed left-out estimated values under pfd-estimate-left-out-v1` | `Estimated values left out: <keys>` |
| Reopened, no correction, leave-out set changed | the same reason | `Estimated values left out: <keys>` or `Estimated values left out: none` |

`<keys>` is the sorted nutrient keys joined by a comma and a space. The log item version's
`correctionReason` for the last row is `Estimated values left out or restored`.

**Log needs one known nutrient.** `FoodLogRequirement` gains `nothingKnown`, raised only when the
withheld or left-out set is not empty and no entry of the effective set has a value other than
unknown. `QuickAddPolicy.placement` places it on Confirm; `FoodLogRequirementText` gives "Nothing
to log: every value was left out".

**Re-log and favourites.** `relogInput` drops `pfd-estimate-left-out-v1` evidence items and their
IDs from the candidate, keeps the manifest, and the new state starts with an empty leave-out set.

### 3.6 App: quick add and the one-step save

`QuickAddIneligibility` gains `approvedEstimate`, checked first in `eligibility`, detected from the
restored candidate (an `approved_estimate` value or a `pfd-estimate-capture-v1` evidence ID). The
sheet saves through a sibling entry point, `FoodConfirmationService.saveQuickAdd`, as
`saveLabelPhoto` is one; it throws `FoodConfirmationSaveError.approvedEstimateNeedsConfirm` for a
state whose selected candidate lists a manifest. The other callers of `save` are Confirm routes and
are unchanged.

### 3.7 Not in this phase

The assistant-pasted estimates contract (its tier lowering and labels, daily export version 4).
Ranking changes. Any rebuild of the private catalogue or conversion of its review sheets.

## 4. Validation

The gates in `AGENTS.md`, the skill's own tests listed in its `SKILL.md`, and the FoodSearchQuality
and FoodQueryEvaluation steps of `.github/workflows/ios-ci.yml`, because estimates change search
visibility, the fat partition and escalation sufficiency. Simulator runs prove software behaviour
only; device acceptance is the owner's.

## 5. Points for the owner

Neither blocks the work; each is built as recommended and is one constant or one rule to change.

1. **Page URL grammar (3.1 item 7).** Recommended: the stricter shared grammar, recorded as a
   dated note in the contract, because the app and the skill must give the same verdict and
   `urlsplit` has no exact Swift equivalent. Cost: a page URL with an upper-case scheme, an
   underscore in its host or a non-ASCII character must be rewritten in its plain ASCII form
   before it is accepted.
2. **`merged_kept` (3.2 item 4).** The implementation brief asks that the writer never replace a
   merged value. Recommended: keep it, with its count in the private change report. Cost: where
   the owner accepted an estimate for a key the merged record already quantifies, the merged
   value stands.

## 6. Review record

- 17 November 2026, revision 1: blind `architecture-gate` review, NEEDS WORK, four blocking
  findings and fifteen others, each checked against the code and accepted. Folded into revision
  2: the order of work no longer binds an estimate before save, quick add, re-resolution and
  export handle it, and the export origin and version 3 move beside the new kind (B1, B2); a
  leave-out-only save takes its expectations and outcome from the saved decision (B3); the
  effective nutrient set has its third and fourth cases, and an absent record reads as unreadable
  (B4); the assertion, the correction reason and the commit type join the predicate's sites with
  one text table (H1); `nothingKnown` is placed, worded and limited to states with a withheld or
  left-out key (H2); the seed has a home and rebuilt states carry the members (H3); the nutrient
  sites are listed and marked (H4); carried details and stripped leave-out evidence on re-log
  (H5); `saveQuickAdd` and its error (M1); the `items` and `item-keys` positions and the table's
  uniqueness conditions (M2); the URL grammar's differences and a shared URL list (M3);
  `merged_kept` defined on the `merge` role with its limit (M4); the seed carries altered
  evidence, and a saved-version guard (M5); responsibilities and test homes (M6); the boundary
  rule, the dropped clock, hand-written state coding, the failure type beside the port and the
  lazy import (L1 to L5).
