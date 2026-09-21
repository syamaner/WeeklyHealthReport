# Food identity capture and nutrition augmentation epic plan

GitHub authority: [epic #86](https://github.com/syamaner/WeeklyHealthReport/issues/86).

Research authority: `food-identity-nutrition-architecture-research.md`.

Normative contract authority: `food-identity-nutrition-contract.md`. Later issues
must consume its identifiers, nutrient states, provenance, merge and migration rules
rather than redefining them.

UX design authority: [Food log UX design baseline](food-log-ux-design-plan.md),
backed by the versioned [36-screen HTML design bundle](designs/food-log-all-screens.html).
Later issue decomposition must use its capture, confirmation, closest-match,
quantity, preparation, plate-weight and override flows as the interaction baseline.

This document turns the research recommendation into an executable issue graph. It is a plan, not implementation evidence and not authority to exercise a provider, device, OAuth account, Drive destination or HealthKit store.

Epic triage was completed on 19 September 2026. #89 and #87 are complete. The
accepted UX baseline superseded the earlier manual-first MVP assumption. The
affected live issues were re-triaged on 20 September 2026; #90 is now the active
architecture decision and #94 remains a container awaiting decomposition.

## Outcome

Make repeated food logging easier while preserving enough identity and provenance
evidence to correct nutrition later. Barcode lookup, label photography and generic
food search populate the entry; a blank manual nutrient form is not an acceptable
normal or fallback journey. The product must prefer an explicit unknown or user
decision over an unjustified exact value.

The app's local, versioned data and canonical JSON remain the system of record. A barcode, nutrition panel, speech transcript or OCR result is capture evidence, not sufficient nutrition truth on its own.

## Frozen architecture direction

1. Keep append-only capture evidence, versioned identity assertions and immutable
   product/log versions separate from replaceable nutrition resolution versions.
2. Represent every nutrient as `measured`, `augmented`, `bounded` or `unknown`;
   unresolved conflicts are explicit and have an effective `unknown` value.
3. Store decisive identity states, including preparation, bone/skin state, drained state, packing medium, fortification, serving basis and edible quantity.
4. Reuse exact confirmed personal-library entries locally and offline.
5. Converge barcode, label-photo and generic-name search on one confirmation flow
   with quantity/unit, preparation, plate-weight, source and override controls.
6. Permit explicit closest-match acceptance for minor differences, but surface
   material preparation, edible-basis and formulation differences before save.
7. Treat overrides as versioned corrections to populated evidence/results, not as
   a routine blank nutrition-entry workflow.
8. Do not depend on Open Food Facts in Phase 1; #87 rejected it as an identity or
   nutrition-resolution dependency. Any later user-invoked candidate suggestion
   remains untrusted evidence and non-canonical until separately evaluated.
9. Start generic UK composition from a versioned CoFID release; Phase 1 requires user selection rather than automatic adjudication.
10. Keep Drive as an explicit backup/export path under narrow `drive.file` consent, not the live database.
11. Keep the existing app's HealthKit access read-only unless the dedicated plan is ratified and implementation is separately authorised.
12. Keep source-rich JSON canonical even if exact combined scalar nutrients are later written to HealthKit.
13. Do not scrape retailer sites or depend on a server for the single-user MVP.

## Issue graph

| Issue | Type | Deliverable | Entry/dependency gate |
|---|---|---|---|
| [#89](https://github.com/syamaner/WeeklyHealthReport/issues/89) | Plan/contract | Land the research, schema, provenance and merge contract | First authority task |
| [#87](https://github.com/syamaner/WeeklyHealthReport/issues/87) | Spike | Measured UK source coverage, CoFID ingest facts and licence/offline matrix | Starts after #89; fixtures use its source-release, provenance and identity vocabulary |
| [#90](https://github.com/syamaner/WeeklyHealthReport/issues/90) | Spike | [Local store/versioning and Drive backup/merge decision](food-library-storage-and-backup-decision.md) | Active; persists stable/version IDs and conflict rules; no live Drive work |
| [#88](https://github.com/syamaner/WeeklyHealthReport/issues/88) | Eval | Printed-panel OCR corpus, harness and promotion result | MVP-critical evidence gate under the accepted UX baseline |
| [#91](https://github.com/syamaner/WeeklyHealthReport/issues/91) | Eval | Handwriting corpus, harness and promotion result | Separate from printed OCR |
| [#92](https://github.com/syamaner/WeeklyHealthReport/issues/92) | Eval | [Matching, hard-negative and calibration corpus/harness](generic-food-match-evaluation.md) | Complete; accepted deterministic explicit-selection envelope, no automatic acceptance |
| [#94](https://github.com/syamaner/WeeklyHealthReport/issues/94) | Phase container | Local-first populated capture, shared confirmation, exact library reuse and provenance-rich JSON | #89, #87, local part of #90 and UX re-triage accepted; decompose before implementation |
| [#93](https://github.com/syamaner/WeeklyHealthReport/issues/93) | Delivery | Verified printed-panel capture | #94 and accepted #88 envelope |
| [#96](https://github.com/syamaner/WeeklyHealthReport/issues/96) | Delivery | Typed and on-device voice capture | #94 and speech characterisation |
| [#102](https://github.com/syamaner/WeeklyHealthReport/issues/102) | Delivery | Handwritten batch capture | #94 and accepted #91 envelope |
| [#98](https://github.com/syamaner/WeeklyHealthReport/issues/98) | Delivery | [Populated generic-food search and calibrated augmentation](generic-food-search-delivery.md) | Complete; offline, explicit-selection-only CoFID delivery inside the accepted #92 envelope |
| [#101](https://github.com/syamaner/WeeklyHealthReport/issues/101) | Delivery | Opt-in retrospective re-resolution | #98 and accepted versioning contract |
| [#97](https://github.com/syamaner/WeeklyHealthReport/issues/97) | Plan | HealthKit-write and richer-export migration contract | Current official Apple research; no writes |
| [#95](https://github.com/syamaner/WeeklyHealthReport/issues/95) | Eval | Commercial product-data source challengers | #87 baseline; separate commercial authority |
| [#99](https://github.com/syamaner/WeeklyHealthReport/issues/99) | Eval | Cloud OCR challengers | Frozen #88/#91 baseline; separate provider/data authority |
| [#100](https://github.com/syamaner/WeeklyHealthReport/issues/100) | Eval | Model-assisted matching challengers | Frozen #92 baseline; separate model/provider authority |

All sixteen tasks are native sub-issues of #86. The checklists in the epic provide a readable fallback and closure view.

## Triage outcome — updated 20 September 2026

| Issue | Priority | Readiness | Triage decision |
|---|---|---|---|
| #89 | P0 | Complete | Contract freezes the shared domain vocabulary and gates |
| #87 | P1 | Complete | CoFID admitted for user-selected generic augmentation; OFF rejected as a Phase 1 dependency on dated legacy-cohort evidence |
| #90 | P1 | Active; decision proposed | SQLite/GRDB local ledger, append-only operations, deterministic backup generations and staged merge; no live Drive work |
| #94 | P1 | Blocked by accepted #90 and decomposition | Phase container only; decompose around the accepted shared capture and confirmation design |
| #88 | P1 | Ready, MVP-critical | Printed-label population is a required capture route and gates #93 |
| #92 | P1 | Complete | Public/synthetic evaluation admits deterministic ranked candidates for explicit selection; automatic acceptance remains disabled and the personal gate is deferred |
| #93 | P1 | Blocked by #88 and shared foundation | Required label-photo population route represented by the accepted designs |
| #98 | P1/P2 | Complete | Offline CoFID ranking, hard rules, visible differences, shared confirmation and exact saved-food reuse; no automatic acceptance |
| #91 | P3 | Queued after #89 | Independent handwriting evaluation; not an MVP blocker |
| #96 | P3 | Blocked by #94 | Narrowed to typed and on-device voice capture |
| #102 | P3 | Blocked by #94, #91 | New independent handwriting delivery slice |
| #101 | P3 | Blocked by #98 | New independent retrospective re-resolution slice |
| #97 | P3 | Deferred | Revisit after the canonical MVP JSON contract is accepted |
| #95 | P3 | Deferred; blocked by #87 | Narrowed to commercial product-data challengers |
| #99 | P3 | Deferred; blocked by #88/#91 baseline | New independent cloud OCR challenger evaluation |
| #100 | P3 | Deferred; blocked by #92 baseline | New independent model-adjudication evaluation |

No direct duplicate was found among the repository's existing open issues. Existing note dictation, Drive export and nutrition-read infrastructure provide reusable seams, but none already delivers this food-capture scope.

## Sequencing

### Stage 0 — epic triage

Completed on 19 September 2026. The review covered scope, necessity, dependency accuracy, independence, evidence requirements, existing repository overlap and authority boundaries. It selected #89 as the sole ready issue and did not start it.

The remaining stages are the ratified dependency order. Each issue still requires explicit execution direction and any concrete external authority it identifies.

### Stage A — authority and fixtures

#89 is complete. #87 admits CoFID only for user-selected generic augmentation and
rejects OFF as a Phase 1 dependency. Its result is accepted. #90 is active and its
proposed decision selects the local operation, snapshot, backup and merge boundary.
#88 and #92 are ready independent MVP-critical evaluations. #91 may define its
separate handwriting corpus without blocking the first useful product.

Stage A exits when schemas, terminology, fixtures, scoring metrics and decision thresholds are fixed before final results are observed.

### Stage B — evidence

Complete #87, #88, #91 and #92 independently. Complete #90 without touching live Drive or changing OAuth configuration. A failed or inconclusive evaluation is valid: it narrows or stops the corresponding delivery issue.

Stage B exits with reproducible artefacts, denominators, raw result formats, failure taxonomy and a clear promote/decline recommendation for each evaluated capability.

### Stage C — minimum useful product

Deliver #94 only after the contract, source choice, local persistence boundary and
UX-driven issue re-triage are accepted. Decompose the shared shell represented by
the design bundle: three capture routes, one confirmation model, source-aware
closest-match selection, quantity/unit and preparation selection, plate handling,
overrides and offline saved-food reuse.

The first acceptable product must populate nutrition through barcode search, label
OCR or generic-food search. It must not require a blank manual nutrition form. It
may still require user selection, quantity entry, confirmation, retaking a label
photograph or correction of an extracted value. HealthKit writes, automatic Drive
work and a commercial provider remain outside this stage unless separately approved.

### Stage D — independently promoted capture and augmentation

#93, #96, #102 and #98 are separate promotions. Passing one does not waive another's evidence gate. #101 follows #98 because re-resolution depends on shipped versioned augmentation. They may be scheduled independently once #94 and their own prerequisites are accepted.

### Stage E — downstream interoperability and challengers

#97 remains planning-only until its permission, reconciliation, deletion and device protocol is ratified. #95, #99 and #100 run only when their respective open/on-device baselines are frozen and provider access, data handling, commercial contact and spend have explicit authority.

## Evaluation rules

### Source coverage

Report hit, exact variant, reformulation ambiguity, decisive-attribute completeness and nutrient-field completeness separately. Every percentage needs a denominator and dated corpus. Measure the actual CoFID/OFF artefacts; do not substitute approximate published counts or sizes.

### Printed OCR

Use at least 100 grounded UK nutrition panels. Report numeric-cell, row/header, full-table, basis conversion, false-save, arithmetic-check, decline and correction-time metrics. Recognition confidence alone cannot authorise a save.

### Handwriting

Use at least 100 grounded lists and report exact item, numeric token, unit, line pairing, corrected-entry, false-save, decline and correction-time metrics. Numeric tokens and units always require review.

### Matching and calibration

Use at least 300 labelled decisions before treating probabilities as meaningful and aim for 1,000+ with oversampled hard negatives. Primary promotion evidence is accepted-match precision with a one-sided 95% confidence lower bound, alongside decline rate and nutrient-error magnitude. Target at least 99.5% point precision and zero catastrophic hard-negative acceptances in the gate set. Freeze the threshold before the untouched final run.

## Cross-cutting acceptance

- `unknown` never becomes zero.
- Bounds never become exact scalar values.
- Measured and augmented values stay distinguishable at item, nutrient and daily-total level.
- Reformulation, correction and re-resolution create new versions without overwriting original evidence.
- Automated tests use synthetic/provider fixtures; live coverage and physical-camera/speech tests are separate evidence.
- Provider terms cover attribution, caching, persistence, redistribution, deletion/export and offline fallback before adoption.
- Commercial quality claims are not accepted as measured app evidence.
- No medical classification, interpretation, target, diagnosis or treatment advice is introduced.

## Authority boundaries

The epic and its planning tasks authorise repository and public-source planning only. They do not authorise:

- HealthKit read/write permission changes or personal HealthKit access;
- app launch, camera/microphone/device operation or personal capture;
- Google OAuth changes, Drive contact or Drive mutation;
- provider credentials, uploads, commercial contact or spend;
- commit, push, merge or release.

Each later task must identify and obtain the concrete authority it needs, with stop and recovery conditions, before crossing one of those boundaries.

## Current triage consequence

#87 and its final review are complete. The live issues affected by the UX baseline
have been re-triaged. #90 is active and must be accepted before #94 is decomposed;
it does not authorise Drive or OAuth work. #88 and #92 can proceed independently as
the evidence gates for #93 and #98. The HTML design bundle is planning authority,
not proof that OCR, retrieval, matching or physical capture has passed its gate.
