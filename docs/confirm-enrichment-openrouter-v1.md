# Confirm enrichment through OpenRouter v1 (CE1)

Status: **approved by the owner on 20 November 2026: decisions CE-D1 to CE-D5 (section 16), egress terms
CE-T1 to CE-T15 as written (section 10) and the truthful provenance choice of section 14.
Documentation only; no app code or egress yet.** The implementation is a later phase with its own
architecture gate; the records of section 11.1 and 11.2 take effect in the PR that wires the live
transport, and section 11.1a before the first evaluation call. Architecture gate PASS at round
nine (section 17). Written for #549 (which
folds in #553) against `main` at `91fa7479`, after the owner approved
[one OpenRouter consent O1](openrouter-single-consent-v1-amendment.md) (#551, PR #554) the same day.
The owner approved the terms of section 10 and the decisions of section 16 on 20 November 2026; no app
egress, code, fixture or policy text changes until the phases that implement them. The [privacy and egress](privacy-and-egress.md) rows and
the privacy policy entries of section 11 are written here and take effect only in the PR that wires
the live transport, as label photo E16 did.

It is a delta on the [Confirm rules review](confirm-rules-review-v1.md) (rule 2, the fill path, and
rule 3, carrying fills), [food details from the catalogue I1](personal-food-catalogue-identity-facts-v1-amendment.md)
(the closed values of I1.1 and the Jev terms of I1.6, which stay developer-tooling terms),
[labelled estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md) (the estimate
states, leave-out and ranking), [assistant-pasted estimates v1](assistant-pasted-estimates-v1-proposal.md)
(whose eligibility, parsing and storage shapes this contract follows wherever it can), the
[food daily export v2](food-daily-export-contract-v2.md), and O1. It repeats none of them, and
everything they say that this document does not name stays as written.

## 1. Why

When the owner picks a food on Confirm, two kinds of gap are common:

1. **Unknown food details.** Confirm blocks Log with `sourceIdentityMissing` until preparation, bone,
   skin, drained state, packing medium and fortification are known (`FoodLogPolicy`,
   `FoodConfirmationPolicy.unresolvedIdentity`). Open Food Facts products arrive with all six
   unknown (`OpenFoodFactsLookup`), and so do Your food database entries without catalogue facts.
   Rule 1's one tap ("Packaged product, eaten as sold") helps only on Open Food Facts and still asks
   fortification; I1 helps only entries the owner has reviewed in the catalogue.
2. **Unknown nutrients.** Unknown stays unknown, correctly, and the estimate layers that exist
   cover only some routes and only from bundled reference rows or the owner's catalogue.

The owner's direction (20 November 2026) is that enrichment should run in the app: when Confirm has
gaps, the app may ask OpenRouter, sending the product details and the values already known, and
pre-fill suggestions the owner checks and corrects before Log. The catalogue's Jev terms (I1.6)
already let the owner's Mac send titles, brands, pack details, categories, product types and states
to Jev; the app terms follow the same shape. Everything a model returns is a suggestion: labelled,
changeable, never replacing a known value and never saved without Log.

## 2. Scope

| Route on Confirm | A. Food details | B. Unknown nutrients |
|---|---|---|
| Open Food Facts search and barcode | yes | yes |
| Your food database | yes, subject to decision CE-D5 | yes |
| Bundled tables (CoFID, USDA, TFDA, Ciqual) | not needed: generic rows do not raise `sourceIdentityMissing` | yes |
| Web lookup (reviewed web proposal) | no, in v1 | no, in v1 |
| Pasted label and label photo | no: they have their own fixed identity and fortification question | no, in v1 |
| Your foods (`personal-library:` rows from search or a barcode rescan) | no, in v1 | no, in v1 |

Web lookup and the label routes are left out of v1 for the reason assistant estimates gave: their
candidates are admitted at save only while the saved nutrients equal the verified source's
(`FoodConfirmationService.save`, the `invalidReviewedSource` and `invalidPastedLabelSource` guards),
and a reviewed web proposal has its own identity review. Adding them is a change to those verifiers,
in its own contract.

Your foods rows are built from a saved product version (`CoFIDGenericFoodSearch` and `BarcodeCapture`
build them from the saved name, brand, variant, pack facts and resolution nutrients), so their text may
be the owner's own correction and their nutrients may already hold earlier estimates; describing them
from the underlying source only is a later change. And a saved resolution version's
`openrouter_estimate` values never become source values: the Your foods builders rebuild each such key
as `.unknown` (`not_declared`) when they make a candidate, so `isProductCandidate` and
`isGenericEstimate` classify the row by its real source as today, and B values are never carried
through search or a rescan.

B is offered only for a candidate whose basis is `per_100_g` or `per_100_ml`. Neither part runs on
the re-resolution screen, the quick add sheet or a reopened log whose details are already saved.

## 3. When it runs (trigger, debounce, cache, caps)

### CE1.1 Trigger

Under decision CE-D1, **decided as recommended: automatic**: once the enrichment switch (section 9) and the
OpenRouter switch (O1) are on and the key is validated in this session, Confirm starts enrichment by
itself when the bound candidate has gaps and the debounce below has passed. (The one-tap alternative
was not chosen.) The request rules:

1. **A first, then B.** A runs when the candidate raises `sourceIdentityMissing`, no
   `decideDifference` is pending, no difference has been decided (`state.decisions` is empty, as the
   Food details sheet's own fill rule requires, because a fill clears decided answers) and no
   correction or reopened entry applies. B runs when at least
   one nutrient is eligible (CE1.4) and the subject of B (CE1.5) is settled: after A has returned,
   failed or was not needed, so B describes the food with A's pre-fills as they stand.
2. **Debounce.** A request starts only after the candidate, its identity and its basis have stayed
   the same for 1.5 seconds on an open Confirm. Changing the candidate ("Choose a different match"),
   correcting details or leaving Confirm within that time sends nothing. The debounce runs only while
   the app is active: moving the app to the background or locking the phone cancels a pending debounce,
   and cancels a request in flight as rule 4 does, so nothing is ever sent from the background.
3. **One request of each kind per subject per Confirm.** A subject (CE1.5) is asked at most once for
   A and once for B on one Confirm. If the owner changes details after B has answered, B's
   suggestions are cleared under CE1.6 rule 6 and, in automatic mode, B may be asked once more for
   the new subject; a third subject on the same Confirm is not asked automatically; an `Ask again` row, present
   in both modes once a subject has been asked, sends it on a tap, within the cap.
4. **In flight.** A request in flight when the candidate or subject changes, the app leaves the
   foreground, or Confirm closes, is
   cancelled; its answer, if it arrives, is discarded and never cached. A request already sent cannot
   be recalled.
5. **No key validation.** Enrichment never validates or revalidates the key. If the key is not
   validated in this session (after a relaunch, say), nothing is sent and no note is shown.
6. **Log never waits.** Log is enabled or blocked exactly as today while a request is in flight. If
   the owner logs first, the late answer is discarded.

### CE1.2 Per-subject cache

A successful, validated answer is kept on the device so that reopening Confirm for the same subject
sends nothing:

- **Key:** the SHA-256 of the canonical request subject (CE1.5) plus the contract, route and prompt
  versions. Never the key, the amount or a date.
- **Value:** the validated response bytes, the response hash, model, provider, cost, and the time
  received.
- **Store:** one file, `confirm-enrichment-cache-v1.json`, in the protected, backup-excluded app data
  directory, at most 500 entries, oldest first out, an entry expiring after 30 days. A corrupt or
  unknown file is discarded whole and rebuilt; it is never a reason to send more.
- **Not in any record, archive or export.** A cached answer reaches a record only through a Log, as
  the capture of CE1.7.
- **Turning enrichment or OpenRouter off** keeps the cache; **Remove key** keeps it; a `Clear
  suggestions cache` row in Settings › OpenRouter deletes the file.

### CE1.3 Caps and limits

- **Daily cap** under decision CE-D4 (decided 20 November 2026): **100 requests and $0.50 of reported
  cost per local day** (a request is one A or one B request, counted once whatever its retries; the cost counts
  every attempt), A and B together, counted on device in their own versioned day record,
  `confirm-enrichment-day-v1`, separate from `label-ai-spend-day-v1`, so one feature cannot use up the
  other. A request with no reported cost counts as its per-request worst case W. A cached answer
  counts nothing.
- **Per request:** A at most $0.01 and B at most $0.02 worst case W, sized from the route's
  catalogue prices and `max_tokens` (CE1.5); a reported cost above the per-request cap pauses that
  part for the rest of the day.
- **Retries:** as label photo E11 and the network resilience rule: only transport errors, timeouts,
  HTTP 408, 429, 500, 502, 503, 504 and provider-overloaded answers; exponential backoff with jitter
  honouring `Retry-After` in seconds and HTTP-date forms; at most 3 attempts within a 60 s whole-call
  deadline (30 s per attempt); identical bytes; every attempt counted. Content failures are never
  retried.
- **Reaching the cap** stops new requests until the next local day and shows the quiet note of section 6.

## 4. A. Food details through Jev

### CE1.4 Questions, answers and the confidence threshold

- **Destination.** `https://openrouter.ai/api/v1/systemone`, the System One request shape (`state` and
  typed `questions`), the endpoint the owner's catalogue tooling uses under I1.6. The request model is
  `typesafe/jev-1.13` and the response must name the model `typesafe/jev-1.13` (or the dated slug
  `typesafe/jev-1.13-20260917`) and the provider `TypeSafe`, the values the app's existing Jev route
  already checks (`OpenRouterFoodProvider`, web lookup's selection route, which calls
  `api/alpha/decisions` and is not enabled in the default flow). The evaluation's first request
  confirms that System One accepts this body and returns this shape; if it does not, switching to
  `alpha/decisions` changes the destination, so it reopens CE-T1 and the section 11.1 row for the
  owner's approval before release. A zero-data-retention endpoint with data collection denied
  is pinned where OpenRouter lists one for the model, with `allow_fallbacks: false`; where none is
  listed, the route is not enabled (this differs from I1.6, which only reports it, because app egress
  is automatic). The on-the-day identity check of label photo E7 applies: once per app session and per
  local day, two keyless catalogue requests (`/api/v1/models/typesafe/jev-1.13/endpoints` and the ZDR
  listing) confirm the endpoint before the first A request, under O1's gate as use
  `confirmEnrichmentDetailsCatalogueCheck`.
- **Questions.** One `choice` question per fact that is **unknown** on the bound candidate, never for
  a known one, with exactly the closed values of I1.1:

  | Fact | Choices |
  |---|---|
  | preparation | `as_sold`, `raw`, `cooked`, `unknown` |
  | bone | `with_bone`, `boneless`, `not_applicable`, `unknown` |
  | skin | `skin_on`, `skinless`, `not_applicable`, `unknown` |
  | drained | `drained`, `undrained`, `not_applicable`, `unknown` |
  | packing_medium | `as sold`, `not applicable`, `water`, `brine`, `oil`, `olive_oil`, `sauce`, `unknown` |
  | fortification | `unfortified`, `unknown` |

  **Fortified is never a choice, so it can never be pre-filled.** A fortified food keeps fortification
  unknown and is asked on Confirm as today (I1-D2's reason). The instructions are fixed text, pinned by
  the prompt version `confirm-details-prompt-v1`, and tell the model to choose `unknown` whenever the
  description does not settle the fact.
- **Response checks.** The provider and model must be exactly those requested (`jev-1.13` or a dated
  slug pinned at the evaluation); `answers` holds exactly the asked question keys; each answer is a
  `choice` whose value is one of that question's choices, with a `confidence` and `probabilities` that
  are finite numbers from 0 to 1. At most 50,000 bytes. Anything else is a failed request and nothing
  is pre-filled.
- **What is pre-filled.** An answer pre-fills its fact only when its choice is not `unknown` and its
  `confidence` is at least the threshold of decision CE-D3 (decided: **0.85**). Everything else
  stays unknown and is asked exactly as today. For a Your food database candidate, a `raw` or `cooked`
  preparation that disagrees with the entry's `state` under I1.1's agreement rule is not pre-filled.
- **Never replaced.** A fact the source states, a fact the catalogue states, and a fact the owner has
  already set on this Confirm are never asked and never changed.

- **A's subject** (cache key and once-per-subject rule): contract and prompt versions, the description
  fields sent, the sorted asked fact keys and `known_details`.

### CE1.4a How a pre-fill is applied and stored (the fill path)

- **One fill, held as a suggestion layer.** The pre-filled facts are not written into
  `state.correction`. They are held in a transient **suggestion layer** on Confirm (section 5a), and two
  identities are named:
  - the **effective identity** (correction, else reopened saved product, else candidate with the
    suggested facts applied) is what `FoodConfirmationState.unresolvedIdentity`, `pendingDifferences`,
    Confirm's display and the save use, so the layer alone can satisfy `sourceIdentityMissing` and
    enable Log;
  - the **fill-test baseline** (`FoodDetailsFillPolicy.currentIdentity`, unchanged: correction, else
    reopened saved product, else candidate) leaves the layer out, so a suggested fact is still unknown
    there.
  **Differences.** `IdentityCompatibility.contradictions` counts a fact as a difference whenever either
  side is unknown, and today `pendingDifferences` hides missing facts only because `unresolvedIdentity`
  lists them. So, while the layer holds an A fill, `pendingDifferences` leaves out the facts the fill
  sets (they are fills of unknown source facts, not differences to decide), and `savesEstimate` and
  `decisionRecord` apply the same rule. A starts only with no difference pending or decided
  (CE1.1 rule 1), and a fill raises none, so a layered state never carries a decided difference; if
  one ever becomes pending while the layer holds a fill, the fill is cleared from the layer first, so
  no saved record holds both a fill correction and a decision record. At save the fill is written as a
  correction, exactly as a sheet fill is.
  While a Jev fill is shown, the one-tap "Packaged product, eaten as sold" row is not offered:
  `PackagedAsSoldPolicy.offers` gains an explicit guard (no A fill in the layer), because after a
  partial fill `unresolvedIdentity` is still not empty; `Not these` brings the row back. A new builder in `FoodDetailsFillPolicy` (beside `PackagedAsSoldPolicy.correction(for:fortified:)`)
  turns the layer into the correction that save writes, changing only facts that were unknown. The live
  fill-only test (rule 2.1) therefore holds: weight, conversion and portion guide are kept (rule 2.4)
  and no typed reason is needed.
- **New frozen reason.** The stored reason is the frozen string `Food details suggested by Jev`
  beside the existing fixed reasons in `FoodDetailsFillPolicy`. Like them it is data, not copy.
- **Changeable (a dated amendment to Confirm rules review rule 2.1).** Confirm shows the facts on one
  line (section 8) with Change, which opens the Food details sheet. For the live fill-only test, the baseline
  leaves the layer out, so a fact set only by the suggestion layer is unknown there, as it was in the
  source: so changing a suggested fact, or a blank the suggestion left unknown, is a fill and needs
  no reason, and weight and conversion are kept. Changing a fact the source states needs a typed reason
  as today. Once the owner applies the sheet, the result is an ordinary `state.correction` and the
  layer's facts are folded into it; the stored reason is then `Food details added` unless every saved
  fact equals the suggestion, when it stays `Food details suggested by Jev`. Removing the suggestion (`Not these`) clears the fill and returns every suggested fact to
  unknown.
- **Stored as any fill today.** A new `ProductVersion` and `UserAssertion` with the claim
  `Corrected populated confirmation for …` and the frozen reason; no new record type, field or
  operation type. A Jev fill is carried on re-log and quick add exactly as other fills (rule 3,
  `isStoredFill` over typed fields), shown there as "Food details from your last entry".
- **Evidence.** One inline `CaptureEvidence` of kind `.labelText` with `captureMethodVersion`
  `confirm-details-capture-v1`, committed with the Log, holding (canonical JSON): the contract and
  prompt versions, model, provider, endpoint, the exact request body without the key, the response
  verbatim, its SHA-256, each question's choice and confidence, the threshold, and which facts were
  applied. It is cited from the candidate decision's evidence IDs, appended last (the mechanism
  estimates v2 section 5 defines for leave-out evidence), so no stored type gains a field. Other
  `.labelText` readers select by `captureMethodVersion` and ignore it (one test each way).
- **A shares B's food contract step.** `captureMethodVersion` decodes as free text (`LedgerText`), so an
  older build would decode A's evidence, but it would not reopen it safely: on an Open Food Facts entry
  with the #464 layer, an older build's `OpenFoodFactsEstimateSource.applies` requires every candidate
  evidence ID to be product evidence, so its reopen and estimate status would throw `integrityFailure`.
  So the floor rule of CE1.7 also returns the new contract for any record citing
  `confirm-details-capture-v1` evidence, and an older build refuses such a store closed rather than
  failing on reopen.

## 5. B. Unknown nutrients through a chat model

### CE1.5 The request

- **Destination.** `https://openrouter.ai/api/v1/chat/completions`, one route pinned by decision
  CE-D2 (recommendation: **GPT-6.1 Sol on Azure**, `openai/gpt-6.1-sol` with endpoint `azure`, the
  route the pasted label text evaluation measured, listed with zero data retention and structured
  outputs). Provider block exactly as label photo E5: `only` and `order` set to the one endpoint,
  `allow_fallbacks: false`, `require_parameters: true`, `data_collection: "deny"`, `zdr: true`; the
  response's model and provider must match or the request fails. On-the-day catalogue check as E7, as
  use `confirmEnrichmentNutrientsCatalogueCheck`. The route is changed only by a route version bump.
- **Strict JSON.** `response_format` is a strict `json_schema`:
  `{"schema":"confirm-nutrient-estimate-v1","basis":"per_100_g"|"per_100_ml","values":[{"nutrient":<key>,"value":<number>,"unit":<unit>}]}`,
  where `nutrient` is an enum of exactly the eligible keys of this request and `unit` of their
  canonical units. `max_tokens` 1,200 and a reasoning limit of 500 tokens, from which W is computed.
  The model supplies no tier and no confidence: every value it gives is stored at tier `low` (CE1.6).
- **Eligible nutrients.** Exactly the rule of assistant estimates section 5.1: a nutrient that, on the
  bound candidate, is `.unknown` with status `resolved` and reason `not_declared` or
  `no_compatible_source`, and has no catalogue estimate in any state. A label value, an Open Food Facts
  value, a merged record's value, a catalogue estimate (kept, withheld or left out), a bounded value, a
  conflict and a `missing_conversion` key are never requested. If no key is eligible, B sends nothing.
- **The subject** (what the cache key and the clearing rule hash): contract, route and prompt
  versions, the description fields of section 7 that this request sends, the typed identity tokens
  after any A fill, the basis, the sorted eligible keys and the SHA-256 of the canonical list of known
  values (key, value, unit, source phrase), since the parent and energy checks depend on them. A cached
  answer is reused only for the same subject, so it always validates as it did when received.
- **Instructions.** Fixed text, prompt version `confirm-nutrient-prompt-v1`: answer for the food
  exactly as described, per the stated basis only, never converting; use exactly the unit given; leave
  out any nutrient it cannot estimate and never write 0 for unknown; never change a known value. No
  health, target or diet wording.

### CE1.6 Validation and presentation of the estimate layer

1. **Response checks.** At most 100,000 bytes; one choice, `finish_reason` `stop`, no tool calls or
   refusal; strict schema validation; `schema` and `basis` equal to the request's. Any failure of shape
   fails the whole request and nothing is shown.
2. **Row checks** (a failing row is dropped, the others stay; codes as assistant estimates 4.2 where
   they exist): a key not requested (`unknown_nutrient`); a unit that is not the key's canonical unit
   (`unit`); a value that is negative, not finite or too large to hold (`value`); on a per 100 g entry
   a mass above 100 g in the key's unit, or energy above 900 kcal on either basis (`impossible_value`);
   a child above its parent, saturated, monounsaturated or polyunsaturated fat above total fat or
   sugars above carbohydrates, where the parent is known or a kept row of the same reply
   (`exceeds_parent`); a key repeated (`duplicate_nutrient`, which drops every row for that key).
3. **Energy against macros.** When energy, protein, carbohydrate and fat are all available after the
   merge (known or estimated) and at least one of the four is an estimate, a domain function
   `EstimateEnergyCheck` with its own constants (4 kcal/g protein and carbohydrate, 9 kcal/g fat, and
   the fibre forms) must pass for at least one of the three forms `LabelArithmeticChecks.energyCheck`
   knows: the general form, the UK form (carbohydrate excludes fibre, fibre at 2 kcal/g, when fibre is
   known) and the Taiwan form (carbohydrate includes fibre), each with tolerance the larger of 15 kcal and 10%. Any form
   is accepted because the candidate's jurisdiction is not reliably known; a parity test pins the
   constants against `LabelArithmeticChecks` (which the domain cannot import); if it fails, every estimated value
   among the four is dropped (`energy_mismatch`) and the known values stay as they are. On a per 100 ml
   basis the check runs on the same per 100 ml values.
4. **Never replacing a known value.** Enforced three times: the request asks only eligible keys, the
   row check drops any other, and the save service re-checks eligibility on the final nutrient set and
   refuses a state that fails.
5. **Shown as a labelled estimate layer, pre-filled.** Each kept row appears in Confirm's nutrient list
   in its normal place with one short `est.` tag beside the value (decided 20 November 2026 in #551),
   no sentence, and nothing on values read from a source. Each row has `Leave out` / `Put back`, the
   control catalogue estimates already use (`ApprovedEstimatePresentation`), so the owner accepts or
   leaves out each value before Log; a left-out value is unknown, never zero. VoiceOver reads "estimated"
   for the tag. Details (the existing Source details disclosure) show "Estimated by <model> through
   OpenRouter from the description of this food" and the time received.
6. **When details or basis change after B answered.** As assistant estimates 5.6: the rows are cleared
   from the list (stored nothing), and B may be asked again under CE1.1 rule 3.
7. **Log.** The saved version holds the kept rows (not left out). B is never a log's only nutrition: a
   new case `FoodLogRequirement.onlyEstimatedByOpenRouter`, on every route where B applies, is raised
   only when at least one B row is kept and no value from any other source is known, with frozen copy
   `Nothing to log yet: every value here is an estimate from OpenRouter.` With every B row left out, Log
   requirements are exactly what they would be with no B answer at all (`.nothingKnown` only under its
   existing estimates v2 condition), so B never blocks a state that logs today. Daily totals keep
   `includesEstimates`; a partial total stays a known minimum.

### CE1.7 Records and exports

- **Provenance kind `openrouter_estimate`.** A new `ProvenanceSourceKind.openRouterEstimate` (raw value
  `openrouter_estimate`). Neither `approved_estimate` (it names a catalogue release and an
  owner-approved evidence record) nor `assistant_estimate` (the owner's own assistant, outside the
  app) is true here. Rules, in `NutrientEntry` validation: only inside `.augmented`, never `.measured`
  or `.bounded`; its tier is implied by the kind (always `low`, exported as that constant, since
  `NutrientProvenance` has no tier field); `recordID` `ore:<capture evidence ID>`; `evidenceID` the capture below; `responseHash` the capture
  evidence's `byteHash` (the SHA-256 of the canonical capture payload), as approved estimates bind it,
  with the SHA-256 of the raw response bytes held inside the payload as `response_sha256`; `manifestReference` `confirm-nutrient-capture-v1#<nutrient key>`; `transforms`
  empty; `sourceID` `confirm-enrichment-openrouter`; a source release per capture,
  `openrouter-estimate:sha256:<capture hash>`, committed with the log. The phase gate pins the other
  required release and evidence fields with truthful constants.
- **Capture `confirm-nutrient-capture-v1`.** Inline `CaptureEvidence`, kind `.labelText`,
  canonical JSON: contract, route and prompt versions; model, provider and generation ID; the exact
  request body without the key; the response verbatim (at most 100,000 bytes, as checked); its hash;
  every row with its result code. Which rows a saved version keeps or leaves out is not in the capture
  (it would be fixed at the first save); it is in a small evidence item per saved version,
  `confirm-nutrient-choices-v1` (the resolution version ID, the capture hash and the sorted left-out
  keys), covered by the floor rule like the capture. Committed only with a Log
  whose saved version keeps at least one B value; with every row left out, nothing is stored.
- **Verification** on save and on reopen: the payload hash equals `byteHash` and each value's
  `responseHash`; the row checks, re-run on the stored response against the stored request, give the
  stored rows; each saved value equals a kept row. A mismatch shows "Evidence not available" and never
  changes a stored value.
- **Food contract.** `ProvenanceSourceKind` is a closed string enum, so an older build cannot decode
  the new kind. Following the allocation rule of estimates v2 and assistant estimates, B takes the
  **next free food contract** when its phase starts (13 at the time of writing: 11 is in use and 12 is
  reserved for assistant estimates), with the floor rule (a record holding `openrouter_estimate`
  provenance, `confirm-nutrient-capture-v1`, `confirm-nutrient-choices-v1` or `confirm-details-capture-v1` evidence) checked before the earlier ones and a
  metadata-only migration. An archive or store holding none keeps its contract and its bytes.
- **Daily export.** B takes the **next free daily export version** (7 at the time of writing: 4 and 6
  are reserved by assistant estimates and the union rule, and 5 is in use), written only for a day
  holding at least one `openrouter_estimate` value; any other day is written exactly as before, byte
  for byte. Its validator row: written exactly when at least one `openrouter_estimate` value is present (a file of
  that version without one is rejected); approved and photo estimates may be present alongside or
  absent (the version 3 and 5 rule that an `approved_estimate` must be present does not apply); for an
  `openrouter_estimate` value, `estimate_source_type`, `estimate_method` and `estimate_state_basis`
  are absent and `estimate_quality` is `low`; versions 3 and 5 reject the three new fields, and version 6, when it lands, rejects them too. The new
  version admits everything version 5 admits (approved estimate and label photo
  estimate fields), and everything version 6 admits once that lands, so a day mixing them is one
  file; goldens cover mixed days. Origin `openrouter_estimate` joins the closed origin table; the value exports `state:
  "estimated"`, `calculated: false`, `source_kind` `openrouter_estimate`, `estimate_quality` `low`
  (required, the only value), and three new fields for this kind only: `estimate_model` (the model
  slug), `estimate_contract` (`confirm-enrichment-openrouter-v1`) and `estimate_response_sha256` (the
  raw response's SHA-256 from the payload, not the capture hash).
  `source_release_id` is the constant `confirm-enrichment-openrouter`, never the per-capture
  identifier. No request text, response text or description field is exported. `notes` gains one
  constant sentence: "origin openrouter_estimate marks a value estimated by an OpenRouter model from a
  description of the food and kept by the user for that entry. It is not measured and does not come
  from a label or a food composition table." A build without this change rejects the new version in
  `validate` and fails closed. A Jev fill (A) changes no export field: food daily export v2 carries no
  identity facts.
- **Developer tools.** A session-only "Last Confirm enrichment" disclosure in Search details, like
  "Last web lookup": per request the use, route, model, provider, request field names sent, request
  and response hashes, latency, attempts, reported cost, the threshold and the outcome; no key. On a
  saved log, Source details show the capture hash, so a value can be reproduced from the stored
  request and response.

### CE1.7a Other routes and later edits

- **Re-log and quick add.** A fill (A) is carried as rule 3 says. For that, the stored fill test
  `isStoredFill` gains a separate predicate, `matchesExceptOpenRouterEstimates`: the saved nutrients
  equal the source candidate's except at keys where the saved value holds `openrouter_estimate`
  provenance and the source holds an eligible unknown (CE1.5). It is checked alongside, not inside,
  `matchesExceptHiddenEstimates` (which needs approved-estimate keys and the reverse direction), so an
  Open Food Facts entry with a Jev fill and B values and no approved estimates still carries its fill. B values are **not** carried: an
  entry whose saved version holds an `openrouter_estimate` value always opens Confirm on re-log and
  quick add (a new quick add ineligibility reason). On that Confirm, and on any Confirm that re-log
  or quick add opens, the per-subject cache may supply the suggestions again without sending, but
  nothing is sent: no automatic request and no `Ask again` row, as CE-T4 excludes quick add and
  re-log uses the owner's saved answers.
- **Re-resolution** does not carry B values (the fresh candidate may hold its own) and shows
  "Estimates from OpenRouter are not carried over", beside estimates v2's notice.
- **Reopen** reads no network. The suggestion layer is rebuilt from the effective version's cited
  capture (verified first) and its `confirm-nutrient-choices-v1` item: Confirm shows the saved B values
  with `est.` and the left-out rows with Put back, because for a candidate with no approved-estimate
  keys Confirm otherwise shows the candidate's nutrients, where these keys are unknown. Leave out and
  Put back on a B key change the layer, and save writes a new version that cites the same capture and
  a new choices item; verification accepts a later version that keeps fewer (or more) rows, as long as
  each saved value equals a kept row of the cited capture. A food details correction on reopen keeps the
  B values only when B's subject (CE1.5) is unchanged; otherwise they are removed with the visible note
  `Estimates from OpenRouter were removed because the food details changed.`, never silently. B is
  not asked again on a reopened log (section 2), so a new estimate needs a new log.
- **Search, the catalogue and import** are untouched. A B value never enters a catalogue file.

## 5a. The suggestion layer on Confirm

- **Where suggestions live.** One transient value on `FoodConfirmationState`, never encoded with it (as
  `answersLabelFortification` and the assistant estimate selection are): the A fill (suggested facts,
  the capture) and the B rows (kept and left out, the capture). Neither the candidate (`candidate.nutrients`
  stays the source's) nor `FoodCorrection` ever holds a model value, so `isValuePreserving` and
  `isFill` keep comparing source against owner, and the candidate decision stored with the log holds
  the source's values only.
- **Merge order at save.** The saved resolution version's nutrients are the candidate's (or the
  correction's), then estimates v2's withheld and left-out keys as unknown, then the #464 label estimate
  layer where it applies, then the kept B rows on keys still eligible. The #464 / off-label estimate layer is
  chosen on Confirm and merged only at save, so `candidate.nutrients` still shows its keys as unknown;
  an explicit rule therefore keeps one key to one estimate: a key the chosen label estimate layer
  fills is never requested from B and, if B has already answered, its B row for that key is dropped
  (`label_estimate`) when the layer is chosen; and while B rows are kept, the layer's keys that B
  already fills are offered by the layer as today, and choosing the layer drops those B rows. When
  assistant estimates are implemented, a
  key B fills is not offered to the assistant, and the assistant section is offered only for keys
  still unknown after B, so no key ever has two model contenders.
- **Reopen and edit with other layers.** Two existing checks would refuse a valid saved entry that
  combines an enrichment capture with another layer: `OpenFoodFactsEstimateSource.applies` requires
  every evidence ID on the decision candidate to be product evidence (reopen throws `integrityFailure`,
  edit `invalidLabelEstimate`), and both compare the resolution version's nutrients with
  `LabelEstimateLayer.expectedNutrients`. They are changed to skip evidence whose
  `captureMethodVersion` is `confirm-details-capture-v1` or `confirm-nutrient-capture-v1`, and to
  expect the layer merge plus the verified B rows. The approved-estimate manifest and leave-out paths on
  Your food database entries get the same two changes.
- **New logs from saved decisions.** A new log built from a saved decision (re-log, quick add) drops
  that decision's A and B capture evidence IDs, as estimates v2 does for leave-out IDs, and reuses the
  cache only and sends nothing (CE1.7a).

## 6. Failure states

Confirm behaves exactly as it does today in every failure, and shows at most one quiet note in the
Food details or nutrient section, never a sheet or alert:

| State | Note |
|---|---|
| OpenRouter off, no key or key not validated | none (O1's blocked row appears only on the `Ask again` row) |
| Enrichment switch off | none |
| Offline, timeout, connection failure | `Suggestions are not available right now.` |
| Refusal, invalid or mismatched response, route check failed | `Suggestions are not available right now.` |
| Daily cap reached or a part paused | `Today's limit for suggestions is reached.` |
| Every A answer below the threshold, or every B row dropped | none; the facts or values stay unknown as today |

A failure is not cached, so the next Confirm for the subject may ask again, within the cap. Nothing
about a failure is stored with a record.

## 7. Exact fields sent and never sent

**A (Jev) sends** one food description and the questions of CE1.4. The description is built by one pure
function from the bound candidate and, for a Your food database candidate, from the entry itself,
read locally from the active release by the candidate's `recordID` through a new read port
(`PersonalFoodDatabaseEntryReading`, no egress), because the candidate carries no category, product
type or state fields. Neither the entry nor the candidate has a pack size or pack type field
(`PersonalFoodDatabaseEntry`, empty `PackFacts`), so none is sent as its own field; a pack size or pack
type written in the entry's title travels inside the title, as stored. Open Food Facts candidates
carry no pack facts either, so for them only the name, brand, source token and known details are
sent:

| Field | Source |
|---|---|
| `name` | the source candidate's name, never text the owner typed in a correction |
| `brand` | the source candidate's brand, when there is one |
| `variant` | CoFID rows only, whose variant is the source's own text; never for USDA, TFDA, Ciqual or Open Food Facts, whose variant holds the app's own copy (`USDAGenericFoodSearch`, `TFDAGenericFoodSearch`, `CiqualGenericFoodSearch`, `OpenFoodFactsLookup`) |
| `category` | Your food database entries, the entry's category |
| `product_type`, `state` | Your food database entries, from the entry |
| `source` | one closed token: `open_food_facts`, `your_food_database` or `composition_table` |
| `known_details` | the facts already known, as I1.1 tokens, so the model does not contradict them |

**B (chat model) sends** the same description (source fields only, never correction text), the typed identity after any A fill (as I1.1 tokens),
the basis, each known nutrient value with its canonical unit and one closed phrase for its source
("from the label", "from the product's Open Food Facts record", "from a food composition table", "from
your food database", "estimated in your food database"), the eligible keys with their units, the fixed
instruction and the schema.

Golden tests pin the description per route (CoFID, USDA, TFDA, Ciqual, Open Food Facts search and
barcode, Your food database).

**Never sent, by either:** the search text the owner typed, the amount eaten, the time or date, notes, any other entry, totals, Apple
Health data, the barcode, entry, record, release, evidence or decision identifiers, source addresses,
digests, photos, receipt text, shop names other than the brand, prices, location, device or account
identifiers, the catalogue's free-text states and assumptions, and the key anywhere but the
Authorization header (a request containing it in the body is refused). A Your food database name can
come from a receipt product title, so it may hold a shop word or pack size; the app has no private
shop list to remove them, which is stated in the privacy entry.

**An on-device gate** runs on every description before it is sent, as AI search by name A6 and the
skill's `safe_query` do: a description holding an email address, a phone number, a UK postcode, a
run of 8 or more digits, a currency amount, or order, payment or account words is not sent (A or B
for that food is skipped, with no note), and the gate is a backstop, not a guarantee.

## 8. Presentation

- **Food details.** With a fill applied, Confirm shows one line in the food details area: `Food
  details suggested: <facts in plain words>`, for example "as sold, no packing liquid, not fortified",
  with `Change` and `Not these`. Facts left unknown are asked as today, below it. The line is hidden
  after a correction or on a reopened entry.
- **Nutrients.** Estimated values in the list with `est.` (CE1.6 rule 5). No other sentence.
- **Loading.** While a request runs, one quiet row `Looking for suggestions…` with `Stop` (explicit
  loading state; Stop cancels and sends nothing more). Log is unaffected.
- **Failure.** The one note of section 6.
- **Settings.** Under Settings › OpenRouter, after the consent switch: a toggle `Suggest missing food
  details and values on Confirm`, caption `Off by default. Sends a description of the food you are
  logging and its known values; never the amount, time, notes or Health data.`; a value row `Confirm
  suggestions today`, detail `<n> of <cap>`; and `Clear suggestions cache`.
- Native grouped style, Dynamic Type, VoiceOver labels on the tag, line and rows, 44 pt targets, no
  colour alone, British spelling, no emoji. No medical classification or advice anywhere.

## 9. Consent and the Settings switch

- **Under O1's single consent.** Enrichment sends nothing unless the OpenRouter switch is on, under
  the gate of O1 with four new `OpenRouterUse` cases, `confirmEnrichmentDetails` (A),
  `confirmEnrichmentNutrients` (B), `confirmEnrichmentDetailsCatalogueCheck` and
  `confirmEnrichmentNutrientsCatalogueCheck`, each with its policy entry
  and egress row (section 11). No per-feature consent, first-use sheet or egress statement.
- **O1's caption and mapping.** Under O1 section 3 a route that widens the consent switch's scope
  changes it in its own contract, so on approval the switch title becomes `Use OpenRouter for food
  lookups, label reading and Confirm suggestions`, its key (`openRouter.consent.v1`) unchanged, and
  the four new uses join `OpenRouterUse` with their `policyEntry` (`Confirm suggestions.`) and
  `egressRow` mapping, checked by O1's test 8. Because both rows of section 11 link to this contract,
  each use's `egressRow` identifies its row by the contract link plus the row's destination cell, so
  each use maps to exactly one row. O1's named list of request sites, and its boundary check, grow by
  the two new adapters and their catalogue checkers. The policy's opening
  paragraph, which quotes the title, and its sentence "Lookups and label reads need your own OpenRouter
  API key" (which becomes "Lookups, label reads and Confirm suggestions need…") change with it, and
  O1's pinned framing sentences are updated in the same PR.
- **The enrichment switch** (`confirmEnrichment.enabled.v1`, Boolean, missing reads as off, removed
  when off, read from the persistent domain only as O1 requires) turns the feature off independently.
  It is a feature switch, not a consent: with OpenRouter off it does nothing.
- **Turning either off** stops new requests at once; a request on the wire is not recalled; suggestions
  already shown stay until Confirm closes but nothing new arrives.

## 10. Egress terms (approved by the owner, 20 November 2026; nothing sent before the phases that wire them)

- [x] **CE-T1 Destinations.** `https://openrouter.ai/api/v1/systemone` (A, model `jev-1.13`) and
  `https://openrouter.ai/api/v1/chat/completions` (B, the CE-D2 route), plus the keyless catalogue
  listings of E7 for both models. No other destination.
- [x] **CE-T2 Payload.** Exactly the fields of section 7, with the fixed questions or instruction and
  schema.
- [x] **CE-T3 Never sent.** The list of section 7, and the on-device gate.
- [x] **CE-T3a Differences from the catalogue's Jev terms (I1.6), approved knowingly.** The app sends
  more than I1.6's catalogue tooling does: CoFID's variant text, a closed source token, the food details already known and, for B only and to a chat model,
  known nutrient values with their source phrases (I1.6 never sends nutrient values). It also has no
  private shop-marker list, so a Your food database name is sent as stored, and its deny gate is the
  on-device gate above, not the skill's `safe_query`. Requests are automatic under CE-D1 rather than
  listed for the owner before a run.
- [x] **CE-T4 When.** (Clarified after review: the Confirm that re-log or quick add opens sends
  nothing, using the cache only.) Under CE-D1: automatically on Confirm after the 1.5 s debounce when gaps exist,
  or only on the one-tap row; in both cases only with OpenRouter on (O1), the enrichment switch on and
  a key validated in this session; never in the background, from search results, on quick add, on
  re-resolution or for a reopened log's saved details.
- [x] **CE-T5 Routing.** Zero-data-retention endpoints only, `data_collection: "deny"`,
  `allow_fallbacks: false`, one endpoint pinned per route; the response's model and provider must
  match; a model with no listed ZDR endpoint is not enabled.
- [x] **CE-T6 Identity check on the day.** E7's catalogue check per route, once per app session and per
  local day, and again after a check that could not connect.
- [x] **CE-T7 Key.** The existing OpenRouter key from this-device-only Keychain, validated in the
  session; never in a body, log, capture, cache or export.
- [x] **CE-T8 Caps.** CE-D4's daily cap in `confirm-enrichment-day-v1`, the per-request caps of CE1.3,
  and the owner's own limit on the key.
- [x] **CE-T9 Retries.** As CE1.3.
- [x] **CE-T10 Response limits.** As CE1.4 and CE1.6 rule 1.
- [x] **CE-T11 On-device retention.** The per-subject cache of CE1.2 (protected, backup excluded,
  500 entries, 30 days, clearable); captures only with a Log that uses them; nothing in the Drive food
  export but the fields of CE1.7.
- [x] **CE-T12 Provider records.** ZDR and no-collection cover the model endpoints only; OpenRouter
  keeps account and usage records (model, tokens, cost, time, generation ID) under its own terms, and
  the policy says so.
- [x] **CE-T13 Qualification before enabling.** Section 12's bars pass on the evaluation, run by
  developer tooling under its own terms (CE-T15), before the route is reachable outside a Debug build;
  then internal TestFlight builds first.
- [x] **CE-T14 Records.** The `privacy-and-egress.md` rows and privacy policy entries of sections 11.1
  and 11.2 take effect in the PR that wires the live transport, not before; the developer tooling
  paragraph of 11.1a takes effect before the first evaluation call.
- [x] **CE-T15 Evaluation egress.** The evaluation tool sends the same request shapes, built from
  public Open Food Facts product data and bundled composition rows only (no owner data), to the same
  two destinations, with the owner's key read into memory only, a $5 programme spend stop and a $0.05
  per-call stop, raw responses kept in the owner's private evaluation folder, and counts, versions and
  hashes only in the repository.

## 11. Records text (added on approval, in the wiring PR)

### 11.1 `docs/privacy-and-egress.md`, Allowed egress, two rows

```diff
+| OpenRouter System One and its one allow-listed Jev endpoint (ZDR, data collection denied, no fallbacks; not enabled where no ZDR endpoint is listed) | One food description for the food on Confirm (the source's name and brand, CoFID's variant text, and for Your food database entries the category, product type and state where present (pack details only as written in the title), a closed source token and the food details already known) and fixed choice questions for each unknown food detail; never the search text typed, text typed in a correction, the amount eaten, time or date, notes, other entries, Health data, barcode, entry, record, release, evidence, decision, device or account identifiers, digests, the catalogue's free-text states, addresses, location, photos, receipt text, shop names other than the brand, prices or the key outside the Authorization header (section 7 of the contract) | With OpenRouter turned on in Settings (O1) and Suggest missing food details and values on, with the user's own validated key: automatically on Confirm, 1.5 s after a food with gaps is chosen, once per food and its details, or on a tap of Ask again, within the cap, when the selected food has unknown food details. Never on a Confirm opened by re-log or quick add, on the quick add sheet, on a reopened log, on re-resolution, from search results or in the background; never for web lookup, pasted label, label photo or Your foods rows; nutrient estimates only on a per 100 g or per 100 ml basis.  two keyless catalogue requests confirm the endpoint on the first request of a session and of each local day, and again after a check that could not connect; at most 3 attempts in 60 s and $0.01 per request; at most 100 requests and $0.50 of reported cost per day across both Confirm suggestion rows; a cached answer is reused without sending | [confirm-enrichment-openrouter-v1.md](confirm-enrichment-openrouter-v1.md) |
+| OpenRouter and its one allow-listed model endpoint for nutrient estimates (ZDR, data collection denied, no fallbacks; not enabled where no ZDR endpoint is listed) | The same food description, the food details after any suggestion, the nutrition basis, each known nutrient value with its unit and source phrase, the unknown nutrients asked, a fixed instruction and output schema; never the items listed in the row above | With OpenRouter turned on in Settings (O1) and Suggest missing food details and values on, with the user's own validated key: automatically on Confirm, 1.5 s after a food with gaps is chosen, once per food and its details, or on a tap of Ask again, within the cap, when at least one nutrient is unknown and eligible. Never on a Confirm opened by re-log or quick add, on the quick add sheet, on a reopened log, on re-resolution, from search results or in the background; never for web lookup, pasted label, label photo or Your foods rows; nutrient estimates only on a per 100 g or per 100 ml basis.  two keyless catalogue requests confirm the endpoint as in the row above; at most 3 attempts in 60 s and $0.02 per request, and the shared daily cap | [confirm-enrichment-openrouter-v1.md](confirm-enrichment-openrouter-v1.md) |
```

`Stays on the device unless the user sends it`, added: "**Confirm suggestions** (#549): the
per-subject cache of validated answers stays in the protected app data directory; a capture of the
request and response is stored only with a log that keeps a suggestion. The food daily export carries,
for an OpenRouter estimate only, the model, the contract version and the response's SHA-256."

### 11.1a `docs/privacy-and-egress.md`, developer tooling paragraph (before the first evaluation call)

Unlike the app rows, this paragraph takes effect, with the owner's approval of CE-T15, **before the
first evaluation call**, beside the existing tooling paragraphs:

"Developer tooling for the Confirm enrichment evaluation ([confirm-enrichment-openrouter-v1.md](confirm-enrichment-openrouter-v1.md)
section 12, #549) runs on the owner's Mac, not in the app, and is not app egress. It sends to
`https://openrouter.ai/api/v1/systemone` (model `jev-1.13`) and `https://openrouter.ai/api/v1/chat/completions`
(the CE-D2 route) only, plus the keyless GETs of their endpoint and zero-data-retention listings that
CE-T1 includes for the app's same request shapes. Each
request carries exactly the app's request shape for one evaluation case, built from public Open Food
Facts product data and bundled composition rows only, never the owner's data: the description fields,
the food details known, and for nutrient estimates the basis, the known values and the keys asked,
with the fixed questions or instruction and schema. Every request pins a zero-data-retention endpoint
with data collection denied and no fallbacks. The key is the OpenRouter key already approved for the
evaluations, read into memory only and never printed or stored. Spend stops at $5 for the programme
and $0.05 per call, enforced in the evaluation's own spend ledger before every call; a transient
failure is retried at most twice more with backoff that honours `Retry-After`. Raw responses, the
cache and the ledger stay in the owner's private evaluation folder; the repository gets counts,
versions and hashes only. The sealed set is sent once, by the frozen configuration. Owner approval:
20 November 2026 (CE-T15)."

### 11.2 Privacy policy, OpenRouter section (an entry in O1's list)

```text
Confirm suggestions. Only if you also turn on Suggest missing food details and values on Confirm in Settings › OpenRouter. When the food you are confirming has unknown food details or unknown nutrient values, the app asks automatically, a moment after the food is chosen. It never asks when you log again from an earlier entry or a favourite, when you reopen a log, or for web lookups, label readings or foods from Your foods. Sends a description of that food as its source gives it (never words you typed in a correction): the name and brand, a composition table's variant text, and for your own food database its category, product type and state where the app has them (a pack size written in a name is sent with the name), the food details already known, which source the food comes from (for example a food composition table), the questions asked or the nutrients wanted and, for nutrient estimates, the nutrition basis and the known values. A name from your own food database can come from a receipt product title, so check names you would not want sent. Food details go to the Jev model through OpenRouter's System One service; nutrient estimates go to one named model endpoint (currently GPT-6.1 Sol on Azure) with no fallback to other providers. You can also tap Ask again on Confirm to send the same request once more, within the daily limit. Never sent: the search text you typed, words you typed in a correction, the amount you ate, the time or date, notes, other entries, Apple Health data, barcodes, identifiers, photos or prices. Suggested food details are filled in for you to check and change; estimated values are marked est. and you can leave out each one before you tap Log. Nothing is saved until you tap Log, and an estimate never replaces a value from a label or a database. A failed request is retried at most twice; suggestions are limited to 100 requests and $0.50 of reported cost a day, and answers are kept on your device, so the same food is usually not sent again (a tap of Ask again, a change of details before you log or an answer older than 30 days sends again). OpenRouter keeps its own account and usage records for these requests, including the model, token counts, cost and time, under its terms. If you log a food with an estimated value, the Drive food file names the model that estimated it.
```

## 12. Evaluation bar before release

Run by developer tooling (CE-T15) on two sets built from public data only, never the owner's data:
a development set of 60 Open Food Facts products (UK and Taiwan, packaged, with complete declared
panels and food details checked by the owner on a review sheet) and 40 bundled composition rows, and
a sealed set of the same size and mix, opened once by the frozen configuration. For B, known values
are hidden per case (energy, a macro, fibre, sodium and one micronutrient at a time) and the model's
estimate is compared with the hidden declared value.

| Bar | A. Food details | B. Nutrients |
|---|---|---|
| Wrong pre-fills | at most 2% of pre-filled facts, and 0 wrong `preparation` pre-fills | n/a |
| Coverage | at least 60% of unknown facts pre-filled | at least 70% of requested nutrients returned and kept after validation |
| Accuracy | n/a | median absolute error, as a percentage of the declared value or of a floor where the declared value is smaller (5 kcal energy, 0.5 g for macronutrients and fibre, 5 mg sodium, 10% of the key's UK reference intake for other micronutrients), at most 20% for energy and macronutrients, 35% for fibre and sodium, 50% for other micronutrients |
| Safety | 0 fortified pre-fills (by construction) and 0 `unfortified` pre-fills on fortified foods (both sets include fortified products, at least 8 each) | 0 known values replaced (by construction) |
| Cost | median at most $0.002 per request | median at most $0.005 per request |
| Latency | p90 at most 10 s | p90 at most 20 s |

A missed bar stops release of that part; the other part may ship on its own. The bars, the sets'
manifests and the scorer are committed before the sealed run, and the sealed set is never reused.

## 13. What stays closed

- Nothing is saved without the owner's explicit Log; no automatic selection of a food.
- Unknown is never zero; estimates are labelled (`est.`), left out values are unknown; partial totals
  are known minimums.
- A suggestion never replaces a value or fact the source, the catalogue or the owner states.
- Fortified is never pre-filled; food details are asked wherever they stay unknown.
- Model output, confidence or citations never authorise nutrition by themselves.
- No medical classification, target, diagnosis or advice; the instructions hold none.
- HealthKit stays read-only and no Health data reaches any request.
- Stored records, archives and exports decode and re-encode unchanged across versions; a record
  without B values keeps its contract and bytes.

Two choices are stated plainly so they are not missed:

- **A Jev answer can enable Log.** Under I1 only facts the owner had reviewed in the catalogue could
  clear `sourceIdentityMissing`; here a Jev answer at or above 0.85 can, as a visible, changeable
  pre-fill the owner sees before tapping Log. This is a deliberate change, approved with this contract.
- **B rows start kept.** Assistant-pasted estimates start every row unticked; here each B value starts
  kept with `Leave out` beside it, following the assistive principle (AI pre-fills, the owner checks
  and corrects), with the `est.` tag on every one. This is also deliberate and approved.

## 14. Compatibility and rollback

- **A** adds no record type (a fill and a capture evidence with a new method version), but a record
  citing A's capture takes the same new contract as B (CE1.4a), so an older build refuses it closed.
- **B** adds a provenance kind, so it raises the food contract (CE1.7). Records and stores without A or B
  evidence keep their contract and bytes, and older builds decode them unchanged. **A record that holds a
  B value cannot be decoded by an older build**, which refuses the newer contract at open and fails
  closed, as every estimate kind before it has. #549 asks for provenance that older builds can decode;
  the only way to give that is to store B values under an existing kind, and none is true
  (`approved_estimate` names a catalogue release, `assistant_estimate` the owner's own assistant). This
  contract chooses truthful provenance, which the owner confirmed on 20 November 2026 (section 17).
- **Rollback.** Turning enrichment off stops new suggestions; saved logs keep what they were saved with.
  Downgrading the app past the B contract is refused for a store that holds a B value, as for earlier
  contract steps.

## 15. Architecture gate

- **Responsibilities.**
  - **Domain** (`FoodLedgerDomain`): `ProvenanceSourceKind.openRouterEstimate` and its validation; the
    capture payload types `confirm-details-capture-v1` and `confirm-nutrient-capture-v1` with
    canonical encoding; the closed fact choice lists, taken from I1.1's existing domain values; the pure
    row checks and `EstimateEnergyCheck` with its own constants (CE1.6 rule 3), since
    `NutritionLabelParsing` is frozen and the domain cannot import it; the parity test lives in a test
    target that already imports both, `FoodLabelPhotoReadingTests` (dependencies `FoodLedgerDomain` and
    `NutritionLabelParsing`), or in the new target's own test target with the same two dependencies.
  - **Application** (`FoodLedgerApplication`): ports `FoodDetailsSuggesting` (A) and
    `NutrientEstimateSuggesting` (B), each one method from a typed request to a typed outcome;
    `ConfirmEnrichmentPolicy` (eligibility, subject and request building, the debounce and
    once-per-subject state machine with an injected clock); `ConfirmEnrichmentCaching` and
    `ConfirmEnrichmentSpendLedger` ports; the fill builder in `FoodDetailsFillPolicy`; Confirm reducer
    actions to apply a fill, apply or clear B rows and leave out a row; the save service's
    re-check; the O1 gate with the four new uses.
  - **Infrastructure:** `OpenRouterJevFoodDetailsAdapter` (System One request and response checks) and
    `OpenRouterNutrientEstimateAdapter` (chat completions, provider block, strict schema, response
    checks), both over an injected transport, both taking `OpenRouterEgressPermitting`; a catalogue
    checker per route; a file cache and a file day ledger. They live in a new package target,
    `FoodConfirmEnrichment`, allowed by `check-boundaries.sh` to import `FoodLedgerApplication` and
    `FoodLedgerDomain` only, with one transport file allowed to load URLs, and added to O1's named list
    of request sites and its boundary check.
  - **Presentation:** the details line, the `est.` tag and Leave out rows, the loading row and note,
    the Settings rows, the Developer tools disclosure.
  - **Your food database entry reading:** the read port `PersonalFoodDatabaseEntryReading` (section 7)
    lives in the application layer; its adapter, over the active release, in
    `FoodLedgerPersonalDatabase`; it is wired at the root and makes no network call.
  - **Composition root:** wires the adapters, the gate, the cache, the ledger and the switch. It is
    the only importer of `FoodConfirmEnrichment`; `check-boundaries.sh` enforces that beside the URL
    confinement rule and O1's request site check.
- **Dependency direction.** Domain ← application ← infrastructure and presentation; no framework,
  network, file or clock type crosses a port.
- **Invariants.** No request with OpenRouter or enrichment off; a known value or fact is never asked
  or replaced; fortified never pre-filled; a B value is `.augmented`, `low`, `openrouter_estimate` and
  never a log's only nutrition; nothing stored without Log; caps never exceeded; the cache never holds
  a key or an amount; a record without B values keeps its contract and bytes.
- **Extension axes.** Another route on Confirm (web lookup, labels) is a scope change with its own
  verifier amendment; another model is a route version bump; another fact is an I1 schema step first.
  No generic AI framework, no protocol per method.
- **Contract tests (synthetic fixtures only, written first).**
  1. Eligibility: only unknown facts are asked; only eligible nutrients are requested; each ineligible
     class (label, Open Food Facts, merged, catalogue estimate in each state, bounded, conflict,
     `missing_conversion`) is never requested.
  2. Request bytes: goldens for A and B with every field of section 7; a description carrying a
     forbidden field is refused before sending; the key appears only in the header.
  3. Gate: with OpenRouter off, enrichment off or no validated key, zero requests on every path (O1
     test pattern, each new `OpenRouterUse`).
  4. Debounce and once-per-subject: a candidate change within 1.5 s sends nothing; one request per
     subject per Confirm; the second subject rule; in-flight cancellation discards the answer.
  5. A answers: below threshold, `unknown`, a choice outside the list, a mismatched model and an
     oversize response pre-fill nothing; a fill keeps weight and conversion and needs no reason; a
     state-disagreeing preparation is not pre-filled; fortified cannot be expressed.
  6. B rows: each row code drops its row only; the energy check drops only estimated values; a zero is
     kept and read as "none: 0 g"; shape failures show nothing.
  7. Save: the service refuses a B value on a non-eligible key; B never satisfies "one known nutrient";
     a left-out value is unknown; the capture is committed only when a value is kept.
  8. Records: a record citing A's capture, and one holding a B value, each raise `minimumContractVersion`
     to the new contract (including an Open Food Facts entry with the #464 layer and an A capture), and an
     older reader refuses them closed; records without either keep their bytes; capture
     verification on reopen.
  9. Export: a day with a B value writes the new version with the three new fields and the constant
     release ID; other days are byte for byte as before; the validator rejects the new fields in older
     versions.
  10. Cache and ledger: a cached subject sends nothing; corrupt files are discarded; the day cap and
      per-request caps hold, with unreported cost counted as W.
  11. Re-log, quick add, re-resolution: a Jev fill is carried; B values are not, and the entry opens
      Confirm.
  12. Shared port contract suites in `FoodLedgerTestSupport`, passed by the scripted and the live
      implementations of both suggesting ports, by the file and in-memory cache and day ledger, and by
      the file-backed and in-memory `PersonalFoodDatabaseEntryReading` (given a `recordID` it returns
      exactly the section 7 fields, and refuses a record not in the active release).
  13. Suggestion layer: B never changes `candidate.nutrients` or `correction.nutrients`; the A fill
      stays a fill after B arrives; changing a suggested fact needs no reason and keeps weight and
      conversion; a fill is refused while `state.decisions` is not empty; B never sends correction
      text; the deny gate stops a description holding each pattern.
  14. Re-log of an entry holding an A fill and B values: the fill is carried, the B values are not,
      and Confirm opens. A new log drops the earlier capture IDs.
  15. On an Open Food Facts product with every fact unknown, the A fill raises no `decideDifference`,
      saves, and writes no `FoodLogDecisionRecord`; a partial fill hides the one-tap row. Reopen and
      edit round trips for an Open Food Facts entry with the #464 layer plus A, plus B, and plus both,
      and for a Your food database entry with approved estimates, leave-out evidence and B. A candidate
      whose only known values would be B values is blocked, including one with no approved estimates.
      O1's request site list and `egressRow` mapping are complete for the four new uses, the two
      catalogue checks mapping to their own rows. A Your foods search row and a rescan row whose saved
      product has a corrected name or variant send nothing; a Your foods row whose saved version holds
      B values offers those keys as unknown and is classified by its real source.
      Reopen of an entry with B values shows them with `est.`; Leave out and Put back on a B key write a
      new version that passes verification; a details correction that changes B's subject removes the
      values with the note, and one that does not keeps them. Each of the four uses maps to exactly one
      egress row whose "When" names both switches.
      A decided difference and an A fill never coexist on save (a difference arising clears the fill);
      the Your food database description golden for a title holding a pack size sends it only inside the
      title; the parity test's target is allowed by `check-boundaries.sh`.
      A candidate with no known source values and one kept B row is blocked with
      `onlyEstimatedByOpenRouter`, not `.nothingKnown`; with one other source value known, it is not
      blocked; with every B row left out, the requirements equal those with no B answer at all, with
      and without approved-estimate keys. No
      evaluation artefact is committed before the 11.1a paragraph is in `privacy-and-egress.md`.
      Two identities: the layer alone enables Log; the one-tap row is hidden while a Jev fill shows and
      returns after `Not these`. B and the off-label layer never fill one key, in either order. The
      `responseHash`, `byteHash` and export hash bind as specified and tampering with any shows
      "Evidence not available". A version 7 file with only B values validates and one without is
      rejected. A-subject cache hit and miss. Energy check parity with `LabelArithmeticChecks`, Taiwan and UK forms included; a cache miss when
      a known value changes; mixed-day export goldens; the boundary script fails a non-root importer.
  16. Zero requests: the app moved to the background within the debounce, a Confirm opened by re-log or
      quick add (with a cache miss), the quick add sheet, a
      reopened log (including after a details correction), and re-resolution each send nothing.
  17. Simulator journey: an Open Food Facts product with all facts unknown is filled and logged with
      one amount; a bundled row gets two estimates, one left out, and logs; enrichment off sends
      nothing; a scripted failure shows the one note.

## 16. Decisions for the owner

Asked one at a time on #549, each with a recommendation, then the egress terms of section 10 and the
compatibility choice of section 14 with the approval.

- **CE-D1. Trigger mode.** **Decided as recommended (20 November 2026).** Recommendation: **automatic**, after the 1.5 s debounce, once per subject,
  with the enrichment switch off by default. It matches the assistive principle (AI pre-fills, the owner
  validates) and the owner's direction; the cache and the daily cap bound it. The alternative is one tap
  on Confirm, which sends only when asked.
- **CE-D2. The model for B.** **Decided as recommended (20 November 2026).** Recommendation: **GPT-6.1 Sol on Azure** (`openai/gpt-6.1-sol`, `azure`):
  listed with zero data retention and strict structured outputs, already measured on nutrition text in
  the pasted label evaluation, where its cost was about a cent a read for much longer inputs. Its
  latency there missed a 20 s bar on long labels; B's prompts are short and run while Confirm is open, so section 12 measures it afresh. The alternative is Gemini 4 Argon on Google Vertex, already
  qualified for label photos.
- **CE-D3. The confidence threshold for A.** **Decided as recommended (20 November 2026).** Recommendation: **0.85**, on Jev's reported confidence,
  confirmed by section 12's wrong pre-fill bar (if 0.85 misses it, the evaluation reports the lowest
  threshold that passes, and the owner chooses). Jev's confidence is uncalibrated, so the threshold is a
  frozen contract value, changed only by a new version.
- **CE-D4. The daily cap.** **Decided by the owner (20 November 2026): 100 requests and $0.50 of reported cost a day**, double the recommendation, with the per-request caps unchanged. Recommendation: **50 requests and $0.25 of reported cost a day**, A and B
  together, with $0.01 (A) and $0.02 (B) per request: well above a normal day of logging, small enough
  that a fault cannot spend much.
- **CE-D5. Your food database entries with catalogue facts.** **Decided as recommended (20 November 2026).** Recommendation: **skip A for any entry
  whose `identity_facts` is not null** (the owner has reviewed it in the catalogue), and ask A for
  entries without facts like any other route. B is unaffected.

## 17. Review record

- **Architecture gate, first round (20 November 2026): PASS WITH CHANGES.** All sixteen findings
  taken: suggestions live in a transient layer outside both the candidate and the correction, with a
  merge order at save and capture IDs dropped on new logs; a suggested fact counts as unknown for the
  live fill test, recorded as a dated amendment to rule 2.1, since the first draft's claim that
  changing it stays a fill was false against `currentIdentity`; `isStoredFill` treats B values as
  hidden so the fill is carried; B sends source fields only, never correction text, and Open Food
  Facts' variant (which holds app copy) is not sent; an on-device deny gate and a term listing every
  difference from I1.6; the Jev route pinned (path, slugs, provider) against the app's existing route;
  A also requires no decided differences; a domain energy check accepting any of the three forms with
  a parity test; the export version admits version 5's fields with mixed-day goldens; known values in
  the cache subject; evaluation bars for a wrong `unfortified` and a floor for small values; shared
  port suites and the import rule; O1's caption and mapping; tier and `recordID`; the `Ask again` row,
  the request count and no key validation; the `PackagedAsSoldPolicy` reference.
- **Architecture gate, second round (20 November 2026, at `30175b9c`): PASS WITH CHANGES.** All eleven
  findings taken: two named identities (the effective one, with the layer, gates Log and saves; the
  fill-test baseline leaves it out), so the first round's fix no longer contradicts itself; a separate
  carry predicate for B values, since `matchesExceptHiddenEstimates` works the other way round; an
  explicit one-key rule against the off-label layer, which merges at save so its keys look unknown;
  `responseHash` bound to the capture's `byteHash` with the raw response hash in the payload and the
  export; description fields named by real source, with Your food database fields read locally by
  `recordID`, variants sent for CoFID only (the other tables' and Open Food Facts' variants are app
  copy) and the typed search text never sent; the export version's own validator row; the energy check
  placed in the domain with a parity test target; A's subject; a switch to `alpha/decisions` reopens
  CE-T1; O1's pinned framing sentences change with the title; a testable statement for A's decoding.
- **Architecture gate, third round (20 November 2026, at `819a0d5b`): PASS WITH CHANGES.** All five
  findings taken: the facts an A fill sets are left out of `pendingDifferences`, `savesEstimate` and
  `decisionRecord` (otherwise the second round's effective identity would turn each filled fact into
  a difference against the unknown source and keep Log blocked); reopen and edit checks for the
  off-label layer and the approved-estimate paths skip enrichment captures and expect the B rows; an
  explicit guard hides the one-tap row after a partial fill; a new rule keeps B from being a log's only
  nutrition on every route; O1's request site list grows and each use maps to one egress row.
- **Architecture gate, fourth round (20 November 2026, at `c1dd9653`): PASS WITH CHANGES.** All three
  findings taken: Your foods rows (built from saved product versions, so possibly corrected text and
  earlier estimates) are out of scope in v1, and their builders rebuild saved `openrouter_estimate`
  keys as unknown so B values are never carried through search or a rescan; A no longer claims an
  unchanged contract, because an older build would decode A's evidence but fail to reopen a layered
  Open Food Facts entry citing it, so the floor rule covers A's capture too and older builds refuse
  closed; the catalogue check is split into one use per route, each mapped to its own egress row.
- **Architecture gate, fifth round (20 November 2026, at `0db9f2a3`): PASS WITH CHANGES.** All three
  findings taken: reopen rebuilds the B layer from the cited capture and a new per-version choices item
  (the first draft's capture held the left-out keys, fixed at the first save), Leave out and Put back
  write new versions, and a details correction that changes B's subject removes B values with a visible
  note; the second egress row's "When" names both switches; the Your food database read port is placed
  with its adapter and shared contract suite.
- **Architecture gate, sixth round (20 November 2026, at `af805a40`): PASS WITH CHANGES.** Both findings
  taken: pack size and pack type are dropped as separate fields, since neither the entry nor the
  candidate has them (they travel only inside a title, as stored), in section 7, the egress row and the
  policy text; and a layered state never carries a decided difference (a difference arising clears the
  fill), so no record holds both a fill correction and a decision record and `staleDecisions` cannot
  arise.
- **Architecture gate, seventh round (20 November 2026, at `58ba5896`): PASS WITH CHANGES.** Both
  findings taken: a developer tooling paragraph for the evaluation's egress (section 11.1a), in force
  with CE-T15's approval before the first evaluation call; and a named Log requirement,
  `onlyEstimatedByOpenRouter`, with frozen copy, since no "needs one known nutrient" reason exists and
  `.nothingKnown`'s copy would be false when B rows are kept.
- **Architecture gate, eighth round (20 November 2026, at `13f6f4e8`): PASS WITH CHANGES.** One finding
  taken: the new requirement is raised only when a B row is kept and nothing else is known, and with
  every B row left out the requirements equal those without B (the round-seven text would have blocked
  a state that logs today and contradicted its own test).
- **Architecture gate, ninth round (20 November 2026, at `cc7491ac`): PASS.** No finding; every cited
  claim checked against the code at that head.
- **Owner decisions (20 November 2026).** CE-D1, CE-D2, CE-D3 and CE-D5 decided as recommended; CE-D4
  decided as 100 requests and $0.50 a day. Asked one at a time. Then CE-T1 to CE-T15 approved as written
  (at `6b3c4133`), and section 14's truthful provenance (a new kind and the next free food contract)
  confirmed.
- **Blind invariant review (21 November 2026): BLOCK, fixed.** One blocking finding: the Jev egress row
  said "ZDR where listed", looser than CE1.4 and CE-T5, which never enable a route without a listed ZDR
  endpoint; the row now says so. Also taken: both rows name the `Ask again` tap, the per-request caps
  and retry limit, and the full never-sent list; version 6 rejects the new export fields; a stray full
  stop; the evaluation paragraph's approval date; the status wording after approval; "while Confirm is
  open" rather than "in the background"; and two choices stated plainly in section 13 (a Jev answer
  can enable Log, unlike I1; B rows start kept). No term changed: each fix brings a record into line
  with the approved terms.
- **Blind invariant re-review (21 November 2026, at `edcc52c8`): BLOCK, fixed.** Taken: the policy entry
  states OpenRouter's account and usage records (CE-T12); the re-ask after a details correction on a
  reopened log is removed, so a reopened log never sends; the Confirm that re-log or quick add opens
  uses the cache only and sends nothing; the cache sentence says "usually", and the entry names Ask
  again and the typed search text; the nutrient row states the ZDR rule; the ledger row says approved.
  Each fix narrows or restates; none widens a term.
- **Blind invariant re-review 2 (21 November 2026, at `0ae91926`): BLOCK, fixed.** Taken: section 5a no
  longer says a new log from a saved decision may ask (it uses the cache only, as CE1.7a and CE-T4
  say); both egress rows and the policy entry now carry CE-T4's exclusions and section 2's route
  scope; a zero-request test for re-log, quick add, reopen and re-resolution; "before you log" in the
  cache sentence; decided wording where the text still read as undecided; the full never-sent list
  in the Jev row. Narrowing and restating only.
- **Blind invariant re-review 3 (21 November 2026, at `1f49a457`): BLOCK, fixed.** Taken: the debounce
  runs only while the app is active, and moving to the background cancels a pending debounce and a
  request in flight, with a zero-request test, so "never in the background" holds; the policy entry
  names the source token, the source phrases and the questions or nutrients asked. Read as covered,
  and flagged to the owner: the evaluation's keyless catalogue GETs, which CE-T1 lists for the app's
  request shapes that CE-T15 reuses.
