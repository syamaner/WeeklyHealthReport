# Unified food search: delivery readiness v1

Status: 30 September 2026, v73. Implementation is local, uncommitted and unreleased
in `codex/unified-food-search`, based on `312b20cf5a80bf71c56f9d6e7cc89c5a0278db15`.
PR #176 at that head does not yet contain the accumulated implementation.
This document supports review and testing; it does not claim live or device acceptance.

## Delivered behaviour and evidence

| Area | Local implementation and measured evidence | Remaining boundary |
| --- | --- | --- |
| One search | Local first, enabled OFF, then enabled valid-BYOK Gemini; results remain usable. Synthetic contracts exercise unavailable/failed stages, cancellation and late responses. | Confidence is conservative, not calibrated probability; generic/manufacturer candidates remain uncertain. |
| Privacy/access | Both online services default off. Stored key is not opt-in; exact key validated for this session. Only displayed food terms leave the port. Replacement/removal/service changes cancel and invalidate late responses. | Google billing/retention and real-device Keychain behaviour require the documented user check. |
| OFF | One search plus at most two details, seven-second pacing, 20-second stage, no retries. Source detail panel and explicit mass/volume required. | Captured four-query comparison: 0/4 local to 3/4 combined reviewable choices. This is not current provider availability or catalogue recall. |
| Gemini sources | One discovery plus at most three source HTTPS attempts including redirects; 50-second combined ceiling. Exact host scope; independently bound table values. Alpro/Arla/Oatly UK adapters. | Captured six-query comparison: 1/6 local to 4/6 combined choices; only three quantity-compatible four-macro profiles including local quinoa. Other hosts remain citation-only. |
| Source honesty | Six of six captured native citation sets retained. Three positive manufacturer pages match four reviewed macros; two negatives rejected; one unreviewed page excluded. Arla 230 ml cannot use a per-100-g panel without a separately admitted conversion. | Six decisive identity fields remain unknown on captured manufacturer candidates; no runtime-sufficient candidate. Nutrient completeness and reviewability are different. |
| Local relevance | Direct sirloin names precede incidental parenthetical mentions. Cooking methods constrain retrieval. Whole-cow's-milk wording offers a user-selected broader milk search. USDA projection repairs 27 preparation labels; 8,156-record source facts otherwise unchanged. | No guessed species, preparation, density or silent nearest-match selection. Local gaps remain visible. |
| Descriptive food | Bounded lentil/tomato soup and porridge-with-water/milk grammar reaches discovery without inventing recipe or amount. Named-dish source-unknown preparation is labelled and ranked after known compatible preparation. | Two of six registered descriptions have local choices; four soup descriptions still have none. This is not general recipe estimation. |
| Confirmation | Explicit choice freezes food and quantity. Both store contracts retain basis/provenance through save, reopen and quantity edits. Unknown preparation is not promoted into exact saved identity. | Representative on-device review/save/reopen and accessibility checks remain unverified. |

The paired app replay contains 11 runs, including one shared Alpro query through all
three layers; all retain prior-stage rows and source facts. The OFF and Gemini
cohorts have different queries and denominators and must not be pooled into an
accuracy percentage. Source captures/selected native citations do not reproduce a
fresh full Gemini response or its lead ranking. Consumed development/holdout data
cannot establish independent acceptance. Fresh incremental quality, latency, paid
cost and escalation benefit remain unmeasured for the final implementation.

## Validation and CI reconciliation

The v72 exact source manifest passed 466 package tests (465 passed, one optional
replay skipped), 279 simulator tests and Xcode static analysis. v73 changes only
CI guards/snapshots and documentation; production Swift and data hashes remain
identical. An additional five-test ranked retrieval run enabled the optional replay;
four scorer tests passed. Do not combine these overlapping counts into a new suite total.

The 72-query replay covers CoFID, USDA and composite (216 scored rows). v5 retains
v3 labels and the scorer unchanged. Only four row grade arrays differ from v4:
r059/r060 add the already-labelled flavoured-milk alternative at CoFID rank 6 and
composite rank 16. All aggregate summaries and top-five metrics are identical;
212 rows are identical. This is snapshot maintenance, not measured quality gain.
The old v4 evidence remains intact.

The CI boundary guard now explicitly permits SwiftSoup only in five concrete HTML
adapters and CoreFoundation only in OFF JSON transport. Domain/application imports
remain closed. The exact SwiftSoup pin and retained licence are checked; four
negative probes in a temporary package copy prove forbidden placements fail.

## Focused device checklist after a separately authorised build

Record build/commit, service settings, query, selected source and observed outcome.
Do the offline checks first. Live service checks below require separate provider
and device authority; this checklist does not itself enable services or use keys.

1. Leave services off. Search `10% yoghurt`, `whole milk`, and `250g cooked weight
   sirloin`. Verify explicit alternatives/source names and literal percentage;
   no automatic choice or inferred species. Check sirloin leads with named cuts.
2. Search `220ml whole cow's milk`. Follow the explicit broader whole-milk
   suggestion. Check the original amount survives and source identity is not
   silently marked cow-confirmed; apply any offered conversion only explicitly.
3. Search `boiled broccoli` and `raw quinoa`; inspect preparation. Try conflicting
   `raw boiled broccoli`: clarify instead of silently choosing a state.
4. Search `cooked porridge made with water` and porridge with milk. Known compatible
   records should precede any labelled unknown-preparation alternatives. Check no
   recipe proportions or eaten quantity are invented. Search homemade lentil and
   tomato soup: a local miss is currently expected, not fabricated nutrition.
5. Select a candidate, enter measured edible weight as eaten, review missing fields,
   save, reopen and edit the amount. Check source, preparation, unit/basis and totals
   remain consistent. Exact-product unknowns must be resolved before saving. Open
   expandable source details; verify identifiers do not clutter the main review.
6. Check large text, VoiceOver labels, keyboard dismissal, decline/None, back and
   resubmit. Change query/preparation during pending enrichment: stale results
   must not replace the new list or selected confirmation.
7. When authorised, enable OFF alone and submit a packaged-food query. Local rows
   should remain while it runs; offline/quota/provider errors should leave them
   usable. Confirm disabling services applies to the next submission and cancels
   pending work. Do not infer success from an empty or citation-only response.
8. When authorised, separately enable automatic Gemini and validate the BYOK key.
   Test one supported source, then an unsupported source. Only independently
   admitted nutrition can become a candidate; unsupported sources retain links.
   Check the Arla volume/mass mismatch remains explicit. Remove/replace the key
   during a pending request and verify its late response cannot publish.

## Delivery scope and next decision

The review bundle comprises application policies/coordinator; OFF and bounded
Gemini acquisition/manufacturer adapters; service/key lifecycle and unified UI;
confirmation persistence repair; local ranking and USDA projection; tests, exact
SwiftSoup dependency/licence, CI gates and corresponding contracts/docs. Keep
historical evaluation seals and unrelated primary-checkout work unchanged. The v73
local manifest and diff inventory bind this readiness review to exact file bytes.

Next delivery action is to commit the scoped bundle, update PR #176, run remote CI
on the resulting head, resolve findings and merge only after the required checks.
The hourly continuation grant covers code/offline evaluations/existing issues; it
is not new commit/push/merge/release authority. Obtain that delivery decision before
publication. A subsequent TestFlight release, live evaluation budget and device
acceptance are separate decisions and evidence. Do not start another speculative
feature cycle while waiting.
