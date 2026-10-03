# Nutrition test-build readiness

This candidate combines the local nutrition evaluation repairs with current main at
`12743760a4c5dc0eed9d56a20c17c963139c39ad`, the lineage used for internal build 16.
The original development checkout is preserved. Work is local and uncommitted.

## Scope and architecture

The candidate retains current description discovery, progressive search, nutrition
review and source admission, and adds the reviewed parser/lexical/ranking refinements
and original-list plus generic-search evidence handoff. Both source adapters keep
upstream food-form and identity gates. The shared interpretation remains the app's
orchestration boundary; legacy parser results remain diagnostic. No provider or
persistence interface changes are needed. Existing store contracts and the expanded
synthetic journeys protect source identity, original evidence, quantities, conversion,
unknowns and explicit acceptance.

Integration versions are query parser v7, preparation policy v2, lexical terms v8,
representation ranking v6, CoFID matcher v12, USDA matcher v13 and composite matcher
v8. Negated cooking words cannot become affirmative discovery constraints. Preparation
and nutrient facts still come from the selected source. No provider inference or
external data acquisition is part of local validation.

## Evidence required before the next build

- A complete package suite, simulator suite and Xcode static analysis on these bytes.
- An unsigned iOS Release build using `com.otherweather.ReportWeeklyHealth`.
- The full offline profile, including 13 confirmed-input, 9 linked-query, 7 list and
  14 multi-source/volume journeys, with private labels and source hashes verified.
- Frozen public retrieval comparison against build 16's v5 reference, retaining
  labels and reporting every changed observation; exact new-baseline reproduction.
- App-resource inspection: only the three expected public food JSON resources,
  no private references or evaluation outputs. Module boundaries and diff checks.

Quality acceptance remains incomplete: the private corpus is exposed development
evidence, fourteen legacy NLP reference disagreements remain visible, and independent
prospective labels/thresholds, fresh model/judge evaluation, OCR, real speech and
physical-device acceptance are not established. These are explicit test-build limits,
not hidden passing scores.

## What to test on the next internal build

1. Paste `100g raw apples` and `50g boiled eggs` on separate lines. Select each exact
   intended generic record and confirm explicitly; reopen both entries and check
   quantities, retained evidence and Food Log totals.
2. Paste the same consumed apple line twice. Confirm both separately; verify two
   contributions, and verify declining or deferring a line adds nothing.
3. Enter `half a green pepper` and `2 eggs`. Keep item counts visible and require an
   explicit supported conversion or measured edible weight before saving mass totals.
4. Search raw ribeye; compare the selected USDA composition record with its saved
   source and amount. Check raw/cooked and negated preparation remain faithful.
5. Search 200 mL of the eligible CoFID whole pasteurised milk. Accept its offered
   estimate explicitly: 206 g should be retained with the independent conversion
   source. Editing the amount clears the old conversion. UHT and USDA records must
   not receive that offer. Unconverted volume may save with unknown mass-based totals.
6. Search an ambiguous meal description or household portion. Discovery may proceed;
   uncertain amounts stay empty for review. Changing the query invalidates old results.
7. Repeat through reviewed dictation and reopen the app to inspect persistence.
   Record device/OS and the actual outcome; simulator checks do not establish speech,
   capture, HealthKit, VoiceOver or physical persistence behaviour.

## Delivery boundary

The unsigned artifact is compile evidence, not an installable or uploaded build.
When delivery is requested, commit only the candidate scope, run protected PR/main
checks, use existing signing and internal audience, and verify an unused build number
live before archive/export. The project default build number is historical and must
not be reused for distribution. No signing, upload, device installation, new tester,
provider spend, commit or push is authorised by this readiness preparation alone.

## Completed local gates

The isolated candidate is ready for the next internal test-build preparation. Final
validation reports 533 package cases (two optional skips, zero failures), 280 simulator
tests, 57 harness tests, 11 acceptance-readiness tests, 4 retrieval-scorer tests,
7 source-projection tests and 23 extraction-contract tests. Xcode static analysis,
unsigned iOS Release compilation, module boundaries, workflow YAML and diff checks
pass. All 43 frozen journey cases pass (13 confirmed-input, 9 linked-query, 7 lists,
14 multi-source); the list suite additionally checks fourteen lines. Public retrieval
v6 reproduces exactly with unchanged v5 aggregate metrics and top-five grade sequences.

The Release artifact uses the established app bundle identity. Its only JSON resources
are the pinned public CoFID, USDA and milk-conversion files. The historical project
build number remains compile-only; no signing or distribution occurred. The private
readiness receipt pins build inputs, executable, public replay, evaluation output,
validation logs and owner-only permissions. It verifies all 28 original private files,
the user review export, reference labels and the original checkout's 23 changed files
are untouched. Remote main was rechecked at the same base commit before handoff.

The final evaluation correctly remains `incomplete` for its seven unrun profile
families. No broad AI-quality or independent-acceptance claim follows from these
local gates. The fourteen legacy NLP disagreements remain recorded for later review.
