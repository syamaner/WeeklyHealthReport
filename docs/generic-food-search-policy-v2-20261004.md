# Food search source policy v2 — 4 October 2026

## Architecture gate

The harness owns explicit food terms and market. The OpenRouter adapter owns retrieval and the strict, versioned model-output wire contract. The application owns source-purpose semantics, budgeted orchestration, provenance, cancellation and confirmation restrictions. Literal identity, basis, nutrients and admission remain in provider-independent domain code and are unchanged.

`FoodSourceLeadPurpose` is a consumer-owned type: primary product or representative estimate. The adapter translates its wire reason into this purpose. An ordinary alternate provider must satisfy the same purpose/abstention contract; application rules do not inspect vendor reason strings. Lead wire contract is `offline-lead-selection-v2`; review choice policy is `food-proposal-review-choice-v3`. Legacy v1 responses are rejected; historical v1 qualification remains historical.

## Search and source policy

Exact requested brands, restaurants, variants and packs require applicable primary sources. Generic dishes may use an attributed secondary nutrition article or source-backed recipe when the supplied metadata actually contains nutrition for the same dish, preparation and market. A title promising calories, anonymous estimate, menu price, location page, mismatched addition or wrong-country variant is insufficient. Source selection does not establish nutrient correctness.

Every generic-dish lead, including a manufacturer or institutional panel, is classified as representative. Exact-product purpose requires an explicitly requested named product. A representative lead restricts later confirmation to representative estimate, enforced in application preparation as well as the match-type picker. Original food terms and market remain the extraction/applicability query. No recipe, brand alias, portion weight, nutrient or conversion is invented.

## Bounded fallback

One discovery returns at most three offered leads. At most two different offered URLs may be selected for capture. An alternative is considered only after an empty extraction with no rejected proposals and `none` preference, or unsupported/unavailable/oversized capture. The same offered URL and already observed redirect targets are excluded. A second source choice uses remaining metadata from the same discovery.

No fallback follows a provider/key/quota failure, rejected binding, conflict, clarification or failed/negative applicability. A supplied URL is reviewed alone. The 150-second total deadline and cancellation apply to the whole operation. At most six inference/search requests are possible: one discovery, two lead choices, two extractions and one applicability check. Pages are never combined into one nutrition record. Successful and failed source-attempt URLs are retained. If no alternative exists, the original empty-extraction/acquisition outcome is preserved.

The UI remains a harness. It states the two-page bound and possible additional model charges, shows source attempts and explains representative-only evidence. UX redesign is deferred.

## Evaluation

The initial v2 prompt passed eight exposed source-selection controls. Tightening the policy so every generic dish uses representative purpose produced **7/8** on a separately frozen final run. The retained miss is the Tenyu manufacturer scallion-pancake panel: the model abstained although gold expected a representative lead. All five required abstentions passed; the partial secondary dish table and UK exact primary control passed. Gold was not changed after predictions. This is a known retrieval false negative, not a successful qualification.

All eight final responses are replayed through the current Swift adapter using a synthetic key and a transport that cannot network. Replay checks request/schema agreement and decoding of the actual model response; it does not convert the 7/8 source-selection result into 8/8 accuracy.

Two frozen full workflows completed: scallion pancake representative estimate Taiwan selected the H.LIFE article, bound a partial table and required representative review; Arla Cravendale whole milk UK selected its exact primary page and completed capture/extraction/applicability. Neither saved food. Both selected the first suitable source, so live fallback was not exercised; deterministic port tests cover fallback success/failure, two-source cap, no rediscovery/merging, quota stop, manual URL, applicability abstention, representative scope and original outcome preservation.

Provider usage for this refinement: **24 calls**, **$0.077246825**, no unknown reported costs or retries. The initial eight selection calls cost $0.0006822; eight full-workflow calls cost $0.075855625; the final eight controls cost $0.0007090. Frozen plans, runner snapshots, requests, raw responses, generation IDs and cost receipts are retained in `/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-source-policy-v2-20261004`, `nutrition-source-policy-v2-workflow-20261004` and `nutrition-source-policy-v2-final-20261004`. The two full workflows predate the final prompt tightening; their selected purposes agree with the final rule, but they are not fresh final-prompt end-to-end runs.

These are exposed development controls and two workflow observations, not held-out nutrition accuracy, confidence calibration, statistical superiority or physical-device acceptance. Fat Daddy still lacks a demonstrated nutrition-bearing source in the earlier observations. No silent generic fried-chicken substitution is allowed. The exact original ETtoday failure remains unreproduced.

## Validation

The final simulator suite passed 318 cases with one skip and no failures; Xcode static analysis succeeded. The pre-existing AppAuth export deprecation warning remains outside this nutrition change. Offline replay of all eight final responses passed against the current Swift request contract. Full package validation passed 709 cases with 5 skips and no failures, including the enabled eight-response replay. Whitespace checks cover the seven changed source/test/probe files as well as tracked diffs.

## Integration and delivery

Main was checked during this phase and remains `22df0958244d790ca8021b734e056f4c1140afd5`. The export worker's files and dirty shared checkout are untouched. Changes remain uncommitted in the isolated nutrition checkout. Installed TestFlight build21 does not contain this refinement. No commit, push, upload, external distribution, HealthKit export or policy publication is performed.

## Saved food market follow-up

The user-approved market preference stores only the explicitly selected market in
local UserDefaults under `food.webReview.market.v1`. Composition restores a known
value when a review model is created; absent or unrecognised values use Unspecified.
Choosing Unspecified removes the preference. Selection remains editable on every
request; changing it cancels the current review and invalidates its results.
The presentation model receives an initial market and a save callback, keeping
concrete persistence at the app composition boundary. No location permission or
IP lookup is used. Taiwan is added to the original outbound terms; brand identity
and source checks remain unchanged. This change makes no provider calls.

Focused presentation validation passed 21 tests, including restored Taiwan terms,
no write on initialisation or unchanged selection, switching market and clearing it.

The complete simulator suite passed 317 cases with 1 skip and no failures; Xcode static analysis succeeded. Main remained `22df0958244d790ca8021b734e056f4c1140afd5`. The preference is local and uncommitted, and is absent from installed build21.
