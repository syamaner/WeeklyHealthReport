# Generic food-source implementation handoff — 4 October 2026

> **Current search refinement:** generic dishes can use attributed nutrition-bearing sources with representative-only review; exact brands still require applicable primary sources. At most two offered URLs are captured after empty/unreadable evidence, with no cross-source nutrient merging. Final exposed controls scored 7/8 (manufacturer panel abstention retained); two earlier v2 workflows completed. New 24-call cost $0.077246825. This remains local and absent from installed build21. [Policy, evaluation and limitations](generic-food-search-policy-v2-20261004.md).

> **Build21 device feedback:** the user installed build 21 and reported unsuccessful scallion-pancake/Fat-Daddy reviews. Explicit market selection, nutrition retrieval intent and clearer rejection explanations are repaired locally; package, simulator and static-analysis gates passed. Ten diagnostic calls cost $0.073381500. Fat Daddy nutrition and exact ETtoday extraction diagnosis remain unresolved; these changes are absent from build 21. [Feedback and repair evidence](generic-food-device-feedback-20261004.md).

> **TestFlight21 delivered:** 0.1.1 (21) is Testing in the existing Internal Testing group (one tester). Upload, processing, notes and audience verified in Safari after explicit user authorisation. [Delivery receipt](internal-testflight-build21.md). Physical acceptance remains pending.

> **Device build ready:** signed local 0.1.1 (19.1) is retained and verified. Installation was rejected by automatic approval review pending explicit in-place approval; nothing was installed. [Build receipt and checklist](generic-food-proposal-device-build-20261004.md).

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

The authorised local implementation and development evaluation are complete in
`/Users/sertanyamaner/.codex/worktrees/nutrition-generic-review/WeeklyHealthReport`.
Base: `fcf3c8c8c3f638dd14f2dfeb88a2213020063297`. Nutrition changes are uncommitted.
The dirty shared checkout is preserved. Earlier no-release checkpoints are historical; the explicitly authorised internal build 21 delivery is recorded above.

## Result

- The app uses OpenRouter: Luna/Azure searches and chooses a source, then Grok/xAI
  extracts structured proposals. Supplying a URL skips search/source choice.
  No Gemini API is composed. Optional Jev uses the same key and remains off by
  default because observed development results did not justify adding it.
- A generic bounded reader handles UTF-8 HTML/text and text-bearing PDFs without
  per-website nutrition adapters. Literal quotes, source hashes, basis and units
  are bound before review. Unknown nutrients, serving weights and density stay
  unknown; conflicting declarations and unsupported sources fail explicitly.
- Review requires match scope and three acknowledgements, then the existing
  quantity/acceptance/save flow. Original source facts remain immutable, user
  corrections remain separate, and reviewed web values stay labelled estimates.
- Local TFDA/Taiwan, CoFID, USDA and personal-library search are preserved. Merged
  workout and backup-protection changes are integrated. The bundled privacy
  policy describes OpenRouter/Exa data flows and retained review evidence.

## Verification

- 686 package tests: zero failures, two documented opt-in/source-evidence skips.
- 109 evaluation-tool tests: all pass.
- 315 tests on the final combined simulator tree: zero failures, one expected
  interactive-harness skip. Final static analysis succeeds.
- The separate synthetic native interaction passed before the later integration:
  explicit review, 50 g quantity, acceptance, one save, reopen with 3 g protein
  and unknown energy/sodium. Its screenshot is retained under
  `Tools/GenericFoodProposalEvaluation/native-evidence/`.
- New code/document files and the final diff pass whitespace checks. The
  packaged privacy text matches its source bytes. The final source/log index is
  `Tools/GenericFoodProposalEvaluation/final-verification-20261004.json`.

Final combined gate: `/private/tmp/nutrition-final-integrated-simulator-analysis-v1.log`.
Package gate: `/private/tmp/nutrition-generic-full-package-v10.log`.
Evaluator gate: `/private/tmp/nutrition-python-gates-v16.log`.
The [requirement audit](generic-food-proposal-completion-audit-v1.md) records exact
scope and the upstream WebKit test's failed first attempt and successful retry.

## Evaluation findings and limits

The authored 24-case set includes 16 user food-description seeds, 16 local/general
cases and eight Taiwan-market cases. Its numbers are fictional. Separate retained
public-source runs test real source declarations. On the paired exposed 19-case
public set, Grok passed 19/19 and Luna 14/19; this supports the current development
route choice, not independent accuracy or universal superiority over Gemini.

The actual six-query workflow smoke produced four eligible reviews, one capture
failure and one unattempted query after its reported-cost stop. A separately
frozen follow-up for the unattempted Ikari query completed safely with no allowed
confirmation. These are not pooled into a numeric-accuracy score. Later market
conflict repair is covered by frozen offline replay, not rewritten live results.

All recorded scopes total 361 requests, 355 known charges of $2.831090750 and six
unknown charges. Unknown is not zero; this is not an account credit statement.
Historical runtime limitations and failures remain in the immutable inventory.
No new provider calls were needed for the final merge, policy or offline eval work.

The framework freezes inputs/gold/runtime, preserves full planned denominators,
checks output receipts, compares paired routes and separates acquisition from
extraction. New reference preflight rejects malformed numbers/identities before
spend. The optional holdout gate rejects overlap with supplied development history;
it correctly flags all 19 exposed public cases. Passing that gate alone does not
establish semantic independence, source truth or calibrated confidence.

## Boundaries for subsequent delivery

Physical-device/VoiceOver acceptance, independent human source review and
confidence calibration are not established. Scanned/image-only PDFs, JavaScript
rendering, compressed responses and IPv6-only sources remain unsupported in the
current capture profile. Source binding does not prove that a panel describes a
user's real meal. The current documented search plugin still works in the retained
live evidence but is labelled deprecated in the newer server-tool migration docs;
a replacement needs its own bounded-call contract and qualification.

Committing, publishing the updated policy, releasing nutrition and distributing
a build require separate delivery authority. Published main/build 19 still has
its Gemini-era food flow; this OpenRouter work has not been released. Follow the
current release runbook and refresh heads before any later delivery. Do not
restart completed paid cases or alter retained evidence merely to fill the
remaining authorisation window.
