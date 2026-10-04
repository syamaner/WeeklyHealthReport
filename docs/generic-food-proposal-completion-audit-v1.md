# Generic food proposal completion audit v1

> **Acceptance preparation:** the updated synthetic native save/reopen interaction passed; a blinded 12-case source worksheet is ready. Independent review and physical-device acceptance remain pending. [Acceptance receipt](generic-food-proposal-acceptance-20261004.md).

> **Current repair result, 4 October:** the unit/basis and applicability repairs are implemented on `79efe835`.
> The fresh follow-up passed its predeclared gates: 10/11 captured cases (10/12 including acquisition),
> 4/4 required abstentions and primary search 6/6. The exposed regression scored 17/20 under unchanged gold.
> App confirmation now requires successful Luna applicability checking after Grok extraction; no Gemini/Jev calls.
> New cost: 66 calls, $0.921713950, all known. Package/evaluator/simulator/static-analysis gates passed.
> Read the [repair results and limitations](generic-food-proposal-repair-results-20261004.md).
> Changes remain local and uncommitted. Earlier checkpoints below are historical, including the failed original holdout.

> **Later evaluation, 4 October:** the new prospective holdout did not pass
> qualification. It captured 20/24 sources, achieved 13/20 correct review outcomes
> on captured sources and found matching primary sources on 4/6 search queries.
> Query applicability and generic unit handling need repair before delivery.
> See [the holdout report](generic-food-proposal-holdout-20261004.md).
> The 26 new calls cost $0.584324675 with no unknown new charges. Documentation-only
> PR #183 is integrated at `79efe83526668e47608e33cbf00655638c2d4826`; production
> source is unchanged. The earlier completion and test evidence below describes
> the local implementation and development gates, not holdout acceptance.

Final audit: 4 October 2026, after the combined simulator/analysis gate. Local base:
`fcf3c8c8c3f638dd14f2dfeb88a2213020063297`, including Taiwan PR #180,
workout reader PR #181 and privacy/backup PR #182. Nutrition implementation is uncommitted in the isolated
`nutrition-generic-review` worktree. No remote nutrition delivery is claimed.

The current authority expires at 09:06 London on 5 October. The user expressly
requires device tests to wait until all coding jobs and relevant other-agent
merges are complete. The original goal's earlier deadline is superseded.

## Requirement evidence

| Requirement | Inspected evidence | Result and scope |
| --- | --- | --- |
| OpenRouter-only active app route | `WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift` constructs OpenRouter discovery/source choice and Grok extraction; no Gemini adapter is composed | Implemented. Historical Gemini package code remains regression evidence. This does not claim every Gemini capability is equivalent. |
| Generic parsing rather than a website allowlist | `GenericFoodDocumentProjector.swift`, `GenericFoodPDFProjector.swift`, `PublicFoodSourceCapture.swift`; projector and capture contract tests | Implemented for bounded UTF-8 HTML/text and text-bearing PDF. Image-only/scanned PDFs, scripts, compressed responses and IPv6-only sources remain explicit format/transport limitations. |
| Structured, source-bound proposals | `GenericFoodProposal.swift`, `FoodProposalEvidenceCatalog.swift`, `StrictFoodProposalJSON.swift`, and provider route contract tests | Six nutrient slots, exact captured references, basis/unit/numeric-context checks and conflict rejection. Literal binding does not prove nutrient meaning or product applicability. |
| No invented unknowns, density or portion weights | Binding tests and `ReviewedFoodProposalConfirmationTests`, including source-serving and altered-nutrient/basis rejection | Implemented in the closed admission path. Numeric fiction in synthetic fixtures is labelled and never admitted as catalogue data. |
| Explicit partial-data review and save | `GenericFoodProposalReviewView.swift`, confirmation bridge/service, 14 reviewed-proposal contract tests | Scope plus three acknowledgements, no intake prefill or automatic acceptance, preserved unknowns and one explicit ledger operation. Both store contracts and reopen/idempotency checks cover provenance. |
| Real native review-to-save interaction | Opt-in `testInteractiveReviewedPartialProposalSavesOnlyAfterExplicitReview`; retained synthetic screenshot and test log | One successful simulator interaction before the user's later deferral. 50 g of synthetic tofu yields 3 g protein, with other target nutrients unknown. This is not physical-device, VoiceOver or live nutrition acceptance. |
| Optional Jev with the same key | `FoodProposalSelecting`, `OpenRouterFoodProvider` selection adapter and shared request credential; paired evaluator arms | Implemented and evaluated. Jev is off in the default composition because the observed development comparison did not justify it. No second key is required. |
| Confidence is honestly presented | Review view labels optional raw Jev confidence uncalibrated; confirmation choice policy and bridge require source binding and user review | No numerical confidence threshold can authorise a save. Calibration is not established. |
| Privacy and credentials | Explicit-tap UI, OpenRouter-specific ThisDeviceOnly Keychain, provider-body and key-replacement tests; capture capability accepts no provider credential | Food terms and public source text only. No history/HealthKit payloads. PR #182 backup protection is retained; the bundled policy now describes the local OpenRouter flow. Public publication remains part of a separately authorised nutrition release. |
| Errors, alternatives and source applicability | Reviewer, presentation and frozen workflow replay tests; market conflict policy | HTTP 400 is not a bad-key verdict; failed capture/source choice retains links. UK/GB, IE and TW URL conflicts are rejected. Unknown geography still needs review. No automatic retry or alternate-source capture. |
| User food descriptors and Taiwan/local/general eval cases | `development-24/roster.json`: 16 user descriptor seeds; 16 local/general and 8 Taiwan-market cases | Included. All numeric panels in this 24-case dataset are fictional; separate public-source sets supply real declaration evidence. |
| Preserve Taiwan catalogue and unrelated work | TFDA adapter and `Resources/tfda-generic-v1.json` are byte-identical to merged main; TFDA tests passed. PR #181 integration receipt retains all 26 other local modified tracked files byte-for-byte | Preserved. Only README overlapped the upstream merge, and its three-way merge was clean. Shared dirty checkout untouched. |
| Robust evaluation denominators and reproducibility | Frozen runner, full-roster evaluator, paired comparison and staged-workflow evaluators; 109 current Python tests | Failures/unattempted cases remain in denominators, missing predictions are not abstentions, wrong food/basis invalidates claims, families/domains stay grouped. Input/runtime/output receipts retain source versions and cost uncertainty. |
| Invalid reference data cannot reach a paid run | `source-review-gold-v2`, freeze preflight and prospective builder regression tests | Finite nonnegative nutrients, finite positive bases and explicit identity/choice lists required before runtime or loader access/output creation. All 33 historical plans pass structural compatibility checks; no scores were rewritten. |
| Authorised bounded live OpenRouter evidence | Immutable public, prospective and workflow runs; `run-inventory-20261004-0813.json` | 361 recorded requests, 355 known costs totalling $2.831090750 plus six unresolved costs. No new call in this audit. Results demonstrate a working route on observed cases, not universal support or independent accuracy. |
| Applicable tests and static analysis | Logs listed below; source/log hash index | 686 package tests, 109 evaluator tests and 315 final combined simulator tests passed with the documented skips. Final combined static analysis succeeded. |
| Verified handoff | This audit and `generic-food-proposal-integration-v1.md` | Final local handoff and source/log hash index are complete; release and independent acceptance boundaries remain explicit. |

## Validation scope

- `/private/tmp/nutrition-generic-full-package-v10.log`: 686 package tests, two
  intentional skips, zero failures. FoodLedger production code is unchanged since
  this run; no FoodLedger package source was changed by PR #181 or #182.
- `/private/tmp/nutrition-final-integrated-simulator-analysis-v1.log`: 315 final
  combined simulator tests, one expected opt-in interaction skip, zero failures;
  static analysis succeeded. The upstream WebKit test also passed. Existing
  AppAuth, upstream synthetic HKWorkout initializer and AppIntents warnings remain.
- `/private/tmp/nutrition-native-interaction-run-v1.log`: one opt-in synthetic native
  interaction passed separately before the testing deferral.
- `/private/tmp/nutrition-integrated-build-analysis-v1.log`: combined app build and
  static analysis passed after PR #181 integration, without launching device tests.
  Existing AppAuth deprecation and AppIntents metadata warnings remain.
- `/private/tmp/nutrition-python-gates-v16.log`: all 109 current evaluator tests pass.
- `Tools/GenericFoodProposalEvaluation/final-verification-20261004.json`: 314
  current source/configuration files, retained log hashes, cost inventory hash
  and byte-identical bundled/source privacy text. This index is local evidence,
  not external attestation or a substitute for checking test scope.

## Completed integration gates

1. PR #182 merged as `fcf3c8c8c3f638dd14f2dfeb88a2213020063297`, from the reviewed
   `434d40e3b338c9be6956d1e549c9245ad7eb4ee8` source. Its first hosted run failed
   one existing WebKit readiness assertion; an unchanged retry passed. That
   historical failure remains recorded rather than being rewritten as a clean
   first-attempt pass.
2. The isolated checkout fast-forwarded to that merge after backups. README and
   FoodLedgerCompositionRoot were the only overlaps and merged cleanly; all 25
   other modified tracked files stayed byte-identical. Receipt:
   `/private/tmp/nutrition-before-privacy-merge-hflpvl3i/receipt.json`.
3. The prepared OpenRouter policy was applied only after its expected upstream
   hash matched. HealthKit, Drive, backup and reversible-history disclosures are
   preserved. The app bundle's policy is byte-identical to the new local source.
4. After relevant coding and integration were complete, the full combined
   simulator/analysis command passed. No physical device or personal HealthKit
   data was involved, and no further code changes followed that gate.
5. All prior provider snapshots and costs remain unchanged. No inference was
   repeated to refresh the integration. The final handoff is
   `generic-food-proposal-handoff-20261004.md`. Nutrition changes remain local and
   uncommitted; no push, issue, nutrition release or external policy publication
   was performed by this chat.

Independent source review, a prospectively separated holdout, calibrated confidence,
physical-device/VoiceOver acceptance and meal applicability are not established by
these development results. They must remain explicit limitations; neither test
counts nor literal quotes convert them into verified claims.


## Addendum: holdout preflight, 09:30 London

The remaining independent-acceptance boundary now has a mechanical overlap gate:
`holdout_audit.py` and the freezer's repeatable `--holdout-against` option reject
shared declared families/domains, queries, comparison IDs, URLs or source bytes
against supplied hash-verified development plans. The 19-case public cohort is
correctly flagged as fully exposed; no new accuracy result is implied. All 109
evaluator tests pass. The 09:25 hash index remains an historical index; it is not
a current hash attestation for the subsequently updated freezer or new audit tool.
