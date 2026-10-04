# Nutrition acceptance preparation — 4 October 2026

The updated native review-to-save interaction passed on the iPhone 18 Pro iOS 27 simulator. This is synthetic integration evidence, not physical-device, VoiceOver, independent nutrition accuracy or release acceptance.

## What was exercised

The actual SwiftUI controls displayed source protein 6g/100g and five unknown target nutrients. Representative-estimate scope and all three review acknowledgements were required to continue. The consumed quantity started blank; entering 50g displayed 3g protein and left missing nutrients unavailable. Save remained disabled until explicit match acceptance. Saving created exactly one temporary-ledger operation; reopening retained the manifest/evidence, nutrients, estimate status and unknown energy/sodium. Only fake credential validation ran. No personal food or HealthKit data was used and no provider charge was incurred.

The opt-in `testInteractiveReviewedPartialProposalSavesOnlyAfterExplicitReview` passed in 133.864 seconds. Accessibility actions and native controls were operated through Device Hub. This does not prove VoiceOver speech or physical touch behaviour. The successful test fixture already contains a successful applicability selection; real checking, failures and abstentions remain covered by the separate provider/orchestration tests and frozen four-call replay.

## Failure retained and repaired

The first launch lacked a test product after static analysis; rebuilding for testing restored it. A parallel runner stalled and was interrupted; the serial runner launched normally. The first completed interaction saved/reopened successfully but failed exact evidence equality because the fixture used a real-time timestamp. Payload and evidence hashes were unchanged. A Foundation reproduction found sub-microsecond differences in JSON millisecond Date round-tripping (maximum 0.357628 microseconds in 10,000 deterministic samples).

The test now injects a fixed whole-second `LedgerClock`, making its exact equality assertion deterministic. This is the only source/test change since the repair verification: no production file or frozen prediction changed. The focused interaction was rerun successfully. The prior failed log remains retained. The full suite/static analysis were not needlessly repeated for this fixture-only change.

## Source review packet

A [12-case worksheet](</Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/repair-20261004-v2/acceptance-review-v1/worksheet.md>) presents UK/local, Taiwan and general queries with full captured text, raw source links, hashes and blank responses. It omits model answers and earlier reference answers. Preparation by this agent is not independent review; a reviewer who has not seen those answers must complete it before comparing results. The failed capture remains present. Record source transcription separately from acceptance of a conflicting panel.

A separate same-agent audit checked frozen raw-source hashes and literal excerpts for Topcake, Jolly Time, Whitworths and Mutti. Topcake's 179.2/359.3 energy pair and Whitworths' 11.8/33.5 saturates pair are present in the sources. Jolly Time distinguishes 34g unpopped serving from a one-cup-popped table denominator. Mutti's longer name is present in raw JSON-LD. Reference decisions remain pending independent judgement; no gold alias, expected action or historical score changed. The diagnostic audit is deliberately outside the blinded worksheet directory.

## Physical-device handoff

Upstream main remains `79efe83526668e47608e33cbf00655638c2d4826`. The related release worker is idle/completed: internal build 19 came from `fcf3c8c8` and does not include this uncommitted nutrition implementation. Do not use that build to claim nutrition acceptance. The shared checkout and other simulator sessions were preserved.

For a future authorised local-device build, record the exact source manifest, device/OS and build identity, then repeat the synthetic partial-panel flow and unsuccessful-check flow without personal HealthKit export. Check large text and VoiceOver labels, focus order, source disclosures, unknowns, quantity entry, refusal and explicit save/reopen. Record actual observations and unresolved failures. Live-source inference should use only displayed public food terms and a separately bounded call plan. No installation, signing/upload, commit, push, distribution or external policy publication was performed in this phase.

## Retained evidence

Evidence root: `/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/repair-20261004-v2`.

* `native-acceptance-v1/`: passed/failed logs, deterministic Date reproduction, test configuration, saved-screen image and receipt hashes.
* `source-ambiguity-audit.json`: four frozen raw-source checks with literal excerpts.
* `acceptance-review-v1/`: 12 blank review responses, 11 captured-source text files and frozen manifest.
* Repository `Tools/GenericFoodProposalEvaluation/native-acceptance-20261004.json`: result and explicit test-only delta against the previous verified source manifest.

Independent review and physical-device acceptance remain open. Provider spend this phase: **$0**. All changes remain local and uncommitted.
