# Confirm enrichment through OpenRouter v1: phase gate

Status: **phase gate, 21 November 2026, architecture gate PASS at round fifteen (section 13);
approved by the owner on 21 November 2026, with the nine readings of section 11; edits made after
approval (section 13) only narrow terms and are shown to the owner with the merge ask. No app egress and no evaluation call until the steps of section 10 say
so.** Implements the approved contract
[Confirm enrichment through OpenRouter v1 (CE1)](confirm-enrichment-openrouter-v1.md) (PR 555;
decisions CE-D1 to CE-D5 and terms CE-T1 to CE-T15 approved 20 November 2026). Part of #549. Written
against `main` at `6897af0e`.

Everything in CE1 stands. This file fixes the numbers, names, closed formats, code sites, ports, tests
and PR split that CE1 left to the gate (CE1.7: "the phase gate pins the other required release and
evidence fields"; "the next free food contract when its phase starts"). It repeats no rule of CE1.
Where the gate places or narrows a CE1 rule, the CE1 section is cited; section 11 lists the points
where the gate reads CE1 strictly, for the owner to see before approving. No point widens a term.

## 1. Numbers and names allocated here

| Item | Value | Why |
|---|---|---|
| Food contract | **13** | CE1.7: the next free number when the phase starts. 11 is in use (`CanonicalFoodProjection.foodContractVersion`, `CanonicalFoodArchive.swift:44`); 12 is reserved for [assistant-pasted estimates v1](assistant-pasted-estimates-v1-proposal.md) by its dated amendment of 18 November 2026 (line 11), and its section 7 says a phase takes the next free number. Section 2.7 says how 12 is treated. |
| Store | `FoodLedgerGRDBStore.schemaVersion` 13, migration `v13_confirm_enrichment`, metadata `food-ledger-v13` | Metadata only, as `v11_label_photo_estimate` (`FoodLedgerMigrations.swift:76`). |
| Daily food export | **`food_daily_schema_version` 7** | CE1.7: 5 is in use; 4 and 6 are reserved by assistant estimates and the union rule. |
| Provenance kind | `ProvenanceSourceKind.openRouterEstimate`, raw value `openrouter_estimate` | CE1.7. |
| Captures | `confirm-details-capture-v1` (A), `confirm-nutrient-capture-v1` (B), `confirm-nutrient-choices-v1` (B, per saved version) | CE1.4a, CE1.7. |
| Cache file | `confirm-enrichment-cache-v1.json` | CE1.2. |
| Day record | `confirm-enrichment-day-v1.json` | CE1.3 names the record; the gate makes it a file beside the cache. |
| Versions | contract `confirm-enrichment-openrouter-v1`; routes `confirm-details-route-v1`, `confirm-nutrient-route-v1`; prompts `confirm-details-prompt-v2`, `confirm-nutrient-prompt-v1` | CE1.4, CE1.5. Each route version fixes model, provider, endpoint, `max_tokens`, reasoning limit and the prompt and completion ceilings; it holds no prices, which are read from the day's catalogue check (section 2.6). |
| Response schema | `confirm-nutrient-estimate-v1` | CE1.5. |
| `OpenRouterUse` cases | `confirmEnrichmentDetails`, `confirmEnrichmentNutrients`, `confirmEnrichmentDetailsCatalogueCheck`, `confirmEnrichmentNutrientsCatalogueCheck` | CE1 section 9; mapping and in-force timing in section 6. |
| Feature switch | `confirmEnrichment.enabled.v1` | CE1 section 9. |
| Frozen reason | `Food details suggested by Jev` | CE1.4a. |
| Log requirement | `FoodLogRequirement.onlyEstimatedByOpenRouter` | CE1.6 rule 7. |
| Quick add ineligibility | `QuickAddIneligibility.openRouterEstimate` | CE1.7a, beside `approvedEstimate` (`QuickAdd.swift:26`). |
| Package target and product | `FoodConfirmEnrichment` (library product, so the evaluation tool can link it) | CE1 section 15. |
| Evaluation tool | `Tools/ConfirmEnrichmentEval` (pure core library plus executable), private folder outside the repository | CE-T15, section 9. |

## 2. Closed formats

All JSON here is canonical (sorted keys, no insignificant whitespace) through the existing
`CanonicalEncoding` port (`LedgerCommands.swift:480`) and hashed through `Digesting` (`:484`). Each
format has a closed key set: an unknown key, a missing required key or a wrong type fails decoding.
Money is an integer count of micro-dollars, never a float.

### 2.1 `openrouter_estimate` provenance (CE1.7, fields pinned)

A B value is a `NutrientEntry` value inside `.augmented` only, with exactly one `NutrientProvenance`:

| Field | Value |
|---|---|
| `sourceKind` | `openrouter_estimate` |
| `sourceID` | `confirm-enrichment-openrouter` |
| `sourceReleaseID` | `openrouter-estimate:sha256:<hex>`, where `<hex>` equals `responseHash` |
| `recordID` | `ore:<capture evidence ID>` |
| `evidenceID` | the `confirm-nutrient-capture-v1` evidence ID |
| `capturedAt` | required: the capture's `capturedAt` (the time the answer was received) |
| `responseHash` | the capture's `byteHash` |
| `manifestReference` | `confirm-nutrient-capture-v1#<nutrient key>` |
| `decisionID`, `assertionID` | nil |
| `transforms` | empty |

A new `OpenRouterEstimateProvenance.isValid(_:key:)` beside `ApprovedEstimateProvenance.isValid`
(`Nutrition.swift`) checks every row, and `NutrientEntry` validation refuses the kind in `.measured` or
`.bounded` or alongside a second provenance. Tier is implied (`low`); `NutrientProvenance` gains no
field.

The per-capture `SourceRelease` committed with the log:

| Field | Value |
|---|---|
| `sourceReleaseID` | as above |
| `sourceID` | `confirm-enrichment-openrouter` |
| `releasedAt` | the capture's `capturedAt` |
| `artifactHash`, `manifestHash` | the capture's `byteHash` |
| `schemaVersion` | `confirm-nutrient-capture-v1` |
| `pipelineVersion` | `confirm-nutrient-route-v1` |
| `licence` | `Model output; no licence applies` |
| `attribution` | `Estimated through OpenRouter` (the model is in the capture, never in a constant) |

### 2.2 `confirm-details-capture-v1` (A)

`CaptureEvidence` (`IdentityAndRecords.swift:201`), kind `.labelText`, `captureMethod`
`Food details suggested by Jev`, `captureMethodVersion` `confirm-details-capture-v1`, `capturedAt` the
time received, `locale` that of the first of the bound candidate's own evidence IDs (section 2.4a) in
list order, or `en_GB` (the constant `PersonalFoodDatabaseSearch.swift:299` uses) when that list is empty, `originalPayload` `.text` of the canonical
payload, `byteHash` its SHA-256 (citation sites in section 2.4a). Payload keys: `schema`, `contract`, `route`, `prompt`, `model`,
`provider`, `endpoint` (the route version's constant, section 3.3 item 3), `generation_id` (read from
the response and derived from the stored response, as CE1.7 names it for B), `request_body` (the exact body as a UTF-8 string, no key), `response` (verbatim, at most
50,000 bytes), `response_sha256`, `answers` (per asked fact, sorted: `fact`, `choice`, `confidence`),
`threshold` (`"0.85"`), `applied` (sorted fact keys pre-filled).

### 2.3 `confirm-nutrient-capture-v1` (B)

As 2.2, with `captureMethod` `Values estimated through OpenRouter`, the response at most 100,000
bytes, no `answers`, `threshold` or `applied`, and `rows`: one item per response row in response
order with `nutrient`, `value` (the decimal as received, as a string), `unit` and `result`. `result` is
`kept` or a CE1.6 rule 2 code, which depends only on the stored request and response:
`unknown_nutrient`, `unit`, `value`, `impossible_value`, `exceeds_parent` (against the request's known
parents and kept rows of the same reply) or `duplicate_nutrient`. The energy check of CE1.6 rule 3
runs "after the merge", so it is never in the capture: it and a parent check against parents that the
chosen label layer adds are computed on the merge and recorded in the choices item (2.4). Committed only with a Log whose
saved version keeps at least one B value.

### 2.4 `confirm-nutrient-choices-v1` (B, per saved version)

`CaptureEvidence`, kind `.labelText`, `captureMethod` `Estimated values left out by you`,
`captureMethodVersion` `confirm-nutrient-choices-v1`. Payload keys: `schema`, `resolution_version_id`,
`capture_sha256`, `left_out` (sorted keys the owner left out), `layer_dropped` (sorted keys dropped
because the chosen #464 or off-label layer fills them, CE1 section 5a, `label_estimate`),
`merge_parent_dropped` (sorted B keys above a parent that the chosen layer supplies, `exceeds_parent`)
and `merge_energy_dropped` (sorted B keys dropped by the CE1.6 rule 3 energy check on the merge of
known values, the layer and the remaining B rows, `energy_mismatch`). Nutrient keys only, no values.
One per saved version that cites a B capture. On Confirm the same merge checks run live whenever the
layer choice changes, so a B row the merge no longer rejects comes back.

Verification (CE1.7) re-runs the row checks on the stored response against the stored request, giving
the capture's `rows`; then removes `layer_dropped` after checking those keys are exactly the B keys
the saved version's label layer fills; re-runs the parent and energy checks on the merge of the saved
version's known values, its label layer and the remaining B rows, which must give exactly
`merge_parent_dropped` and `merge_energy_dropped`; then requires each saved B value to equal a kept
row not in `left_out`. Any mismatch shows "Evidence not available" and changes nothing.

### 2.4a Where each item is cited

Evidence is reached through the decision's embedded candidate, as estimates v2's leave-out item is
(`FoodConfirmation.swift:856-864`). The rule applies only to saves where `changesProduct` holds (today
the only saves that write a decision, product version and resolution version, `:881, 1040`); a save
without it, such as a quantity-only edit, writes no decision and keeps citing the stored one unchanged.
Each such save that writes CE1 evidence, **and each such save whose bound candidate cites any item of
the three CE1 method versions**, writes a new candidate decision whose
candidate equals the bound candidate except its evidence IDs, so no earlier CE1 item is ever carried
through `?? selected.candidate` (`:859-865`). On
reopen the bound candidate is the stored decision's candidate (`FoodConfirmation.swift:1229, 1237`),
which already lists earlier items, so **the bound candidate's own IDs** are its evidence IDs with every
estimates v2 leave-out item and every item of the three CE1 method versions removed, order kept. The
new list is those own IDs, then, once each and only when its rule holds, the leave-out item
(estimates v2's existing rule: `changesProduct` and a non-empty saved leave-out set, `:839-840`),
the A capture, the B capture and that version's new choices item. So each version's decision cites at
most one choices item, its own, whose `resolution_version_id` must equal the version citing the
decision (verification refuses otherwise).

- **A capture** is appended only while the version being saved still holds at least one fact equal
  to the capture's `applied` facts (on a first save, the fill; on reopen, the earlier capture). It is
  never committed after `Not these`, or when the sheet replaced every suggested fact.
- **Product version.** The new `ProductVersion`'s evidence IDs (today `selected.candidate.evidenceIDs`,
  `FoodConfirmation.swift:894`) take the same list as the new decision candidate, so a reopened save
  never carries an earlier CE1 or leave-out item there either.
- **B capture and choices item** are appended only while the saved version keeps at least one B
  value. A version with every B row left out cites neither (CE1.7: with every row left out, nothing is
  stored), so its B values are gone and a later reopen offers no Put back for them.
- **The reopen path.** Today `leaveOutChanged` is `correction == nil && savedLeftOut != seed.leftOut`
  and `leaveOutOnly` is `previous != nil && leaveOutChanged` (`:832, 835`); that path keeps the earlier
  decision's expected quantity and outcome but writes a new decision candidate (`:900-913`). CE1
  widens both: a change of B choices sets `changesProduct` through its own term, and `leaveOutOnly`
  becomes `previous != nil && correction == nil && (approved leave-out changed || B choices changed)`.
  The path still keeps the earlier expectations and outcome, and its new decision candidate carries
  the list above. The two places that write its stored texts use the widened predicate too:
  `makeAssertion` (`:1434-1435`, which today returns nil without an approved leave-out change) writes an
  assertion and carries the previous decision record (`:1438`), and the log edit reason (`:979`) uses
  the B text. The texts are data, frozen in a new `OpenRouterEstimateChoicesText` beside
  `ApprovedEstimateLeaveOutText` (`ApprovedEstimateConfirmation.swift:305-307`): reason
  `Changed kept or left-out OpenRouter estimates under confirm-nutrient-choices-v1`, edit reason
  `OpenRouter estimates left out or restored`, claim `Kept OpenRouter estimates; left out: <sorted keys
  or none>`. When an approved leave-out and B choices change in one save, the reason and edit reason
  are the B texts and the claim appends the approved suffix (`ApprovedEstimateLeaveOutText.claimSuffix`).
- **B's subject on reopen** (CE1.7a, a details correction keeps B only when B's subject is unchanged)
  is computed by the same pure subject builder as on a live Confirm, over the reopened state on the
  source side only: description fields and source phrases from the capture's stored request inputs
  (section 3.2), never re-read, so a newer Your food database release between log and reopen changes
  nothing; identity tokens and basis from the bound candidate plus the correction; known values from
  the bound candidate plus the correction, leaving out `openrouter_estimate` keys, keys the label layer
  fills and estimates v2's withheld and left-out keys, so neither B's own values nor the #464 layer
  enter it. Eligible keys depend on whether the label layer was chosen before or after B answered (CE1
  section 5a), so the comparison removes the saved label layer's keys from the eligible keys on both
  sides, the stored inputs and the reopened state, and compares every other part as is. B is kept
  exactly when the two subjects so formed are equal, in either order.

- **Skip list.** `OpenFoodFactsEstimateSource.applies` (`OpenFoodFactsEstimateSource.swift:29-30`),
  `LabelEstimateLayer.expectedNutrients` callers and the approved-estimate manifest and leave-out paths
  skip evidence whose `captureMethodVersion` is any of the three CE1 versions before their own checks,
  and every other `.labelText` reader selects by its own method version (G12).
- **New logs** from a saved decision (re-log, quick add) drop all three kinds of ID, as estimates v2
  drops leave-out IDs (CE1 section 5a).

### 2.5 `confirm-enrichment-cache-v1.json` (CE1.2: the approved value only)

```text
{ "schema": "confirm-enrichment-cache-v1",
  "entries": [ { "subject_sha256": <64 hex>, "part": "details" | "nutrients",
                 "response": <base64 of the validated response bytes>, "response_sha256": <64 hex>,
                 "model": <slug>, "provider": <name>, "cost_microusd": <int or null>,
                 "received_at": <RFC 3339 UTC, exactly three fractional digits> } ] }
```

Exactly CE1.2's value: response bytes, response hash, model, provider, cost and time received. **No
field for the request body, key, amount, description or any other date.** `subject_sha256` is the SHA-256 of the
canonical subject of CE1.4 (A) or CE1.5 (B), whose versions are inside it. At most 500 entries ordered
by `received_at`, oldest dropped first; an entry older than 30 days is a miss and is dropped at the
next write. Stored with `NSFileProtectionComplete` in the backup-excluded app data directory. A corrupt,
unknown-schema or over-size file is deleted whole and rebuilt empty; a read failure is a miss and never
a reason to send twice (the once-per-subject rule still holds). On a hit the response bytes are
re-checked by the same response and row checks as a live answer (section 3.2); a `response_sha256`
mismatch or a failed check is a miss and the entry is removed.

- **When an entry is written.** Only after the response checks pass, and never for a cancelled or late
  answer (CE1.1 rule 4) or a failure (CE1 section 6). An answer that passes the checks but pre-fills
  nothing (every A answer `unknown` or below 0.85) or keeps no row (every B row dropped) is a validated
  answer and is cached, so the same subject is not sent again; it is not a failure.
- **One policy.** Expiry, the 500-entry eviction and the over-size rule are a pure application
  `ConfirmEnrichmentCachePolicy` given `now`; the file and in-memory caches both apply it, and the
  shared suite checks they agree.

**Rebuild equals live.** The request body is not cached. A capture made from a hit rebuilds the body
from the live Confirm inputs through the same pure builder (section 3.2), reads `generation_id` from
the cached response and takes `endpoint` from the route version. Its `CaptureEvidence.capturedAt`,
the provenance `capturedAt` and the `SourceRelease.releasedAt` are all the cached `received_at`, never
the time of the hit. The live time received is truncated to whole milliseconds (the store's record
time precision, `FoodLedgerGRDBStore.swift:54`) before it reaches the capture, provenance, release or
cache, so a live capture and a hit carry the same value. A verbatim response may echo request text (System One may echo `state`); CE1.2
keeps the response verbatim, so the cache may hold such an echo, and only the request body itself is
excluded. Test G1 proves that capture is
byte-identical, `byteHash` included, to the capture of a live answer for the same subject.

### 2.6 `confirm-enrichment-day-v1.json` (CE1.3)

```text
{ "schema": "confirm-enrichment-day-v1", "local_day": "YYYY-MM-DD", "requests": <int>,
  "settled_microusd": <int>, "paused": ["details" | "nutrients"],
  "open_requests": [ { "request_id": <uuid>, "part": "details" | "nutrients",
                       "charged_microusd": <int>, "attempts_sent": <int> } ] }
```

Same protection and backup exclusion as the cache. The arithmetic lives in a pure application
`ConfirmEnrichmentSpendPolicy`, the shape of `LabelPhotoSpendPolicy` (`LabelPhotoSpendPolicy.swift:59-72`):

- **W per attempt** is computed as `LabelPhotoSpendPolicy.worstCase` does (`LabelPhotoSpendPolicy.swift:59-62`):
  a prompt ceiling times the prompt price plus the completion ceiling (and reasoning limit where billed
  separately) times the completion price, with **prices from the day's catalogue check**, as label
  photo takes them (`:37-39`). Ceilings pinned by the route versions:

  | Route | Prompt ceiling | Completion ceiling | Reasoning limit |
  |---|---|---|---|
  | `confirm-details-route-v1` | 8,000 tokens (raised from 4,000 before the freeze, 22 November 2026, when prompt v2's choice descriptions made the body longer) | 400 tokens, sent as `max_tokens`; if System One does not accept `max_tokens`, the route version's completion ceiling is the 50,000-byte response limit counted as tokens, so W stays a true worst case | none |
  | `confirm-nutrient-route-v1` | 6,000 tokens | 1,200 (`max_tokens`, CE1.5) | 500 (CE1.5) |

  A request body longer in UTF-8 bytes than its prompt ceiling in tokens is refused before sending
  (bytes bound the tokens the app sends from above), with no note, as the deny gate is. Because System
  One builds its own prompt from `state` and `questions`, the evaluation's first request also checks
  that the reported prompt tokens are within the ceiling (section 9). If the day's prices make W
  exceed the per-request cap, the route check fails as route unavailable for that day and the part
  sends nothing. With the 50,000-token fallback, W for A is above $0.01 at almost any listed price, so
  A would never run; that case is a first-request stop for the owner (section 9), not a silent outcome.
  W and every reported cost are rounded up to whole micro-dollars. Pricing fields beside prompt and
  completion (22 November 2026, after the live Azure listing): a cache-write price is admitted at any
  well-formed rate and W prices every prompt token at the larger of the prompt and cache-write rates;
  `overrides` long-context tiers are admitted only when every tier's `min_prompt_tokens` is above the
  route's prompt ceiling, so no request can reach one; anything malformed fails the route closed.
- **Whole-request cap.** An attempt may start only when the request's `attemptsCharged` (held in the
  session: each sent attempt's reported cost, or W when none is reported; never the reserved
  `charged_microusd`) plus W is at most $0.01 (A) or $0.04 (B; raised from $0.02 by the owner on 22 November 2026), checked before every attempt, so one request, retries included, never counts
  or spends more than the approved per-request figure. An attempt with no reported cost is charged W.
  If W is so close to the cap that no retry fits, the request simply makes fewer attempts.
- **Day cap.** A request may start only when `requests` is below 100 and `settled_microusd` plus the
  open requests' charges plus its per-request cap is at most 500,000, so neither it nor its retries can
  take the day past $0.50. A request counts once, at its reservation.
- **Reservations** are tagged with a `request_id` from an injected generator, so reconcile and release
  are idempotent per request, across a day change too. A reservation writes the whole per-request cap
  (10,000 or 40,000) as `charged_microusd` in one atomic update before the first attempt is sent, as
  label photo reserves its whole per-tap limit (`LabelPhotoSpendPolicy.swift:177-180`); each sent
  attempt increments `attempts_sent` in the same way, and the reconcile at the end lowers the charge to
  the reported costs (unreported attempts at W), up or down, never clamped to the reservation, as label
  photo does (`LabelPhotoSpendPolicy.swift:204-205`). So a request cut short by a crash or a kill still
  counts at its cap on relaunch. The day cap is then checked once, at reservation, against the cap, and
  retries stay inside that reservation. **One pause trigger:** at reconcile, the part is added to
  `paused` for the rest of the local day when any single attempt is reported above W (W was then not a
  worst case) or the request's total reported cost is above its per-request cap, as label photo sums
  the tap (`LabelPhotoSpendPolicy.swift:209-213`).
- **Prompt over the ceiling.** At reconcile, an attempt that reports more prompt tokens than its
  route's ceiling adds that part to `paused` for the rest of the local day, as label photo's `overInput`
  does (`LabelPhotoSpendPolicy.swift:206-213`), since W was then not a worst case; the other part stays
  open. A committed worst-case B golden (the most eligible keys and the most known values) asserts the
  body fits the 6,000-token ceiling, and the evaluation reports how many requests the ceiling refused.
- **Fail closed.** The port reports `.absent`, `.day(Day)` or `.unreadable`, as label photo's
  `Stored` does (`LabelPhotoSpendPolicy.swift:142-146`). `ConfirmEnrichmentSpendPolicy`, not the adapter,
  turns `.unreadable` into a record for today whose `requests` is 100, written at once, so nothing more
  is sent that local day, after a relaunch too; `.absent` is a fresh day. A failed reservation write
  sends nothing. A failed reconcile write is retried once, then the part closes for the app session,
  as `LabelPhotoReadSession.swift:241-245` does.
- **Day change.** A new local day (from the injected clock and time zone) starts a new record only
  when today is later than the stored day; a stored day on or after today is kept, so a clock moved back
  never resets the allowance (label photo's `stored.day >= today`, `LabelPhotoSpendPolicy.swift:150-151`). Open
  requests of the previous day are closed at their charged amounts, which stay counted in the day they
  were sent; a later reconcile or release for such a `request_id` is ignored.

The `ConfirmEnrichmentSpendLedger` port only reads a `Stored` value and applies one atomic
`update(_ transform: (Stored) throws -> Day) throws -> Day`, as label photo's ledger does
(`LabelPhotoPorts.swift:174`), so the policy sees `.absent` and `.unreadable` inside the update and a
refusal throws without writing; its shared suite covers persistence, the three stored states and that
a throwing transform stores nothing. Separate from `label-ai-spend-day-v1`, which is unchanged.

### 2.7 Food contract 13 and the store

- **Floor rule.** `CanonicalFoodProjection.minimumContractVersion` (`CanonicalFoodArchive.swift:137`)
  returns 13, checked first, for a record set holding `openrouter_estimate` provenance anywhere a
  nutrient set is stored (resolution versions, candidate decisions, conflict candidates) or evidence
  whose `captureMethodVersion` is `confirm-details-capture-v1`, `confirm-nutrient-capture-v1` or
  `confirm-nutrient-choices-v1`. The contract 11 and earlier rules are unchanged.
- **Contract 12 is never written or read.** The store's migrations run in order, so once store 13
  exists a later `v12` migration cannot run. The three range checks that admit `1...foodContractVersion`
  today (`CanonicalFoodArchive.swift:72`, the manifest init at `:326` and verification at `:488`) take
  one accepted set, `1...11` plus `13`, and refuse 12 with `unsupportedFoodContract(12)`.
  Decoding an archive labelled below 13 that holds `openrouter_estimate` provenance or evidence of
  any of the three CE1 method versions fails, as decoding already fails for an archive below 11 that
  holds a label photo estimate (`CanonicalFoodArchive.swift:98-104`).
  `migrationIdentifiers` (`:335-340`) for contract 13 is `food-ledger-v1` to `food-ledger-v11` plus
  `food-ledger-v13`, never `v12`. Assistant-pasted estimates, unbuilt, takes the next free number when
  its phase starts, as its section 7's next-free rule allows (the reservation of 12 is the dated
  amendment at line 11 of that document); PR 1 adds a dated note there.
- **Store.** `v13_confirm_enrichment` changes metadata only. Every store at 11 migrates to 13 on first
  open of a build carrying PR 1, so a downgrade to a store-11 build is then refused for every store, as
  it was for each earlier step (section 11, point 5); a store or archive with no CE1 record keeps its record bytes and, for
  archives, its contract label.

### 2.8 Daily food export 7

- Writer (`FoodDailyExport.swift:589-596`): schema 7 when any entry holds an `openrouter_estimate`
  value, checked before the schema 5, 3 and 2 choices, which are otherwise unchanged byte for byte.
- `FoodDailyExportShape` (`FoodDailyExportShape.swift:46-60`): `acceptedSummaryVersions[7]` =
  `food-intake-summary-v6`; `estimateSourceTypes(schema: 7)` = schema 5's set; the schema 7 validator
  row of CE1.7. Schemas 1, 2, 3 and 5 reject the origin and the three new fields.
- Version 7 admits exactly what version 5 admits plus B, and not assistant estimate fields (section 11,
  point 2).
- The `notes` sentence of CE1.7, verbatim. PR 1 adds a dated note for version 7 to
  `food-daily-export-contract-v2.md`, as the label photo phase did for version 5.

## 3. Responsibilities and dependency direction

### 3.1 Sites

| Layer | Site | Change |
|---|---|---|
| Domain | `ProvenanceSourceKind`, `NutrientEntry` validation, new `OpenRouterEstimateProvenance` | Section 2.1. |
| Domain | new `ConfirmEnrichmentCapture` (payload types of 2.2 to 2.4) | Typed, closed keys; `typed(_ evidence:)` gives nil for any other method version. |
| Domain | new `ConfirmNutrientRowCheck`, `EstimateEnergyCheck` | CE1.6 rules 2 and 3, pure, own constants. |
| Domain | `PersonalFoodDatabaseIdentityFacts` (`PersonalFoodDatabaseModel.swift:250`) | Reused for A's choice lists; its `Fortification` already has no fortified case (`:272`), so A cannot express one. |
| Application | new `ConfirmEnrichmentPolicy` | Eligibility (CE1.4, CE1.5), subjects, the on-device deny gate (CE1 section 7), the prompt ceiling refusal (section 2.6), typed request bodies (section 3.2). CE-D5 reads `hasCatalogueFacts` from `PersonalFoodDescriptionFields`, which the read port sets from the entry's `identityFacts != nil` (`PersonalFoodDatabaseEntry.identityFacts`, `PersonalFoodDatabaseModel.swift:332`), so A is skipped for a reviewed entry. |
| Application | new `ConfirmEnrichmentSession` | The CE1.1 state machine (debounce, once per subject, second subject, `Ask again`, cancellation, foreground only), and the request loop: ledger check, gate, reserve, attempt, retry with backoff and deadline (CE1.3) through `ConfirmEnrichmentRetryPolicy` (pure, the classes of CE1.3, `Retry-After` in both forms) and `ConfirmEnrichmentDelaying`. |
| Application | new `ConfirmEnrichmentSpendPolicy` | Section 2.6. |
| Application | new `ConfirmDetailsResponseCheck`, `ConfirmNutrientResponseCheck` | CE1.4 and CE1.6 rule 1 shape checks over `Data`; used live, on a cache hit and on reopen. |
| Application | `FoodConfirmationState`, `FoodConfirmationAction`, `reduce` (`FoodConfirmation.swift:169, 335, 372`) | The transient suggestion layer (CE1 section 5a, never encoded), effective identity versus fill-test baseline (CE1.4a), actions to apply and clear A, apply and clear B rows, Leave out and Put back. |
| Application | `FoodDetailsFillPolicy`, `PackagedAsSoldPolicy.offers`, `pendingDifferences`, `savesEstimate`, `decisionRecord` | CE1.4a. |
| Application | `FoodConfirmationService.save` and verification | CE1.6 rule 4 re-check, CE1 section 5a merge order, capture and choices evidence, verification of 2.4. |
| Application | `FoodLogPolicy` (`FoodLogRequirement`), `QuickAdd`, `isStoredFill`, new `matchesExceptOpenRouterEstimates` beside `ApprovedEstimateSource.matchesExceptHiddenEstimates` (`ApprovedEstimateConfirmation.swift:50, 63`) | CE1.6 rule 7, CE1.7a. |
| Application | `OpenFoodFactsEstimateSource.applies` (`OpenFoodFactsEstimateSource.swift:18`), `LabelEstimateLayer`, approved-estimate manifest and leave-out paths | CE1 section 5a. |
| Application | new `OpenRouterEstimateCarry.sourceNutrients(_:)` | One pure function that rebuilds saved `openrouter_estimate` keys as `.unknown` (`not_declared`), used by both Your foods builders (`CoFIDGenericFoodSearch` in `FoodGenericSearch`, and the `BarcodeCapture` path) (CE1 section 2). |
| Application | `CanonicalFoodProjection`, `FoodDailyExport`, `FoodDailyExportShape` | Sections 2.7 and 2.8. |
| Application | `OpenRouterUse` (`OpenRouterEgress.swift`) | Four cases (section 6). |
| Application | ports of section 4 | New. |
| Infrastructure | `FoodConfirmEnrichment`: `OpenRouterJevFoodDetailsAdapter`, `OpenRouterNutrientEstimateAdapter`, `ConfirmEnrichmentRouteChecker`, `ConfirmEnrichmentRoutes` (route-version constants, URLs included), `ConfirmEnrichmentTransport` (the only file that loads URLs, refusing every redirect as `OpenRouterTransport.RedirectRefusal` does, `OpenRouterTransport.swift:111-116`), `FileConfirmEnrichmentCache`, `FileConfirmEnrichmentDayLedger`, and the scripted adapters for Debug journeys | One HTTP attempt per call, Authorization header from `FoodWebKeyStoring` read on every attempt, byte limit while reading, the gate at every attempt; no content rule. |
| Infrastructure | `FoodLedgerPersonalDatabase`: `ActiveReleaseEntryReader` | `PersonalFoodDatabaseEntryReading` adapter (CE1 section 7), local only. |
| Infrastructure | `FoodLedgerGRDB` | Migration 13 and open check (`FoodLedgerGRDBStore.swift:23, 1248`). |
| Presentation | `FoodLedgerPresentation`: `FoodConfirmationView`, `FoodDetailsSheet`, new `ConfirmEnrichmentText` | Details line, `est.` tag, Leave out and Put back, loading row with Stop, the one note, VoiceOver labels; every string frozen in `ConfirmEnrichmentText`. |
| App target | Settings › OpenRouter, `ConfirmEnrichmentPreference`, Developer tools "Last Confirm enrichment", `FoodLedgerCompositionRoot` | CE1 sections 8 and 9; the only app importer of `FoodConfirmEnrichment`. |
| Tooling | `Tools/ConfirmEnrichmentEval` | Section 9. |
| Scripts | `check-boundaries.sh` | Section 3.3. |

### 3.2 Where the request and response bytes are made

CE1 section 15 places "request and response checks" in the adapters. The gate places them in
application code, because the same checks must run on a cache hit and on reopen, where no adapter runs:

- The **request body** is a typed `Encodable` value built by `ConfirmEnrichmentPolicy` from the live
  Confirm inputs (CE1 section 7 description, questions or instruction and schema, and the route
  version's model and provider block passed in as plain values), encoded once through
  `CanonicalEncoding`. The variable part of each request is one canonical JSON object of a closed
  type, `ConfirmDetailsRequestInputs` (description fields, known details, asked facts) or
  `ConfirmNutrientRequestInputs` (description fields, identity tokens, basis, known values with unit and
  source phrase, eligible keys with units), held in one fixed place: System One's `state` value for A,
  the single user message's content for B (the fixed instruction is the system message). Verification
  and the reopen subject decode that object from the capture's `request_body` with a closed decoder,
  never the prose. These types and decoders are in PR 1; the builder is in PR 2. The port receives
  those exact bytes; the adapter sends them unchanged and adds
  only the Authorization header. A golden per part and route pins the bytes (CE1 test 2); G6 pins that
  the wire bytes equal the capture's `request_body`.
- The **response checks** (size, one choice, `finish_reason`, refusal, strict schema, `schema` and
  `basis`, model and provider match, A's answer keys and ranges) are pure application functions; the
  **row checks** and energy check are domain. The adapter checks only HTTP status, the byte limit and
  the transport failure class.

### 3.3 Dependency direction and boundary checks

Domain ← application ← infrastructure and presentation; the app target composes. `check-boundaries.sh`
gains, each with a self-test fixture that makes it fail:

1. `FoodConfirmEnrichment` may import `FoodLedgerApplication`, `FoodLedgerDomain` and `Foundation`
   only; URL loading only in `ConfirmEnrichmentTransport.swift`.
2. The only importers of `FoodConfirmEnrichment` are `FoodLedgerCompositionRoot.swift`, its own test
   target and `Tools/ConfirmEnrichmentEval`; and in `Package.swift` only its test target depends on it
   (the dependents rule at `check-boundaries.sh:207-217`).
3. `openrouter_request_sites` (`:451-458`) gains the two adapters and `ConfirmEnrichmentRouteChecker.swift`.
   `ConfirmEnrichmentRoutes.swift`, which holds the URLs only as route-version constants used by gated
   sites, joins `openrouter_exempt` (`:459`) as a reviewed exemption. The routes file and its exemption
   land in PR 2, because the scripted captures, W, the request goldens and the scripted answers all
   need the route values; the request-site additions land in PR 3 with the adapters. No application file holds an
   OpenRouter URL: the capture's `endpoint` is passed in from the route version at the root.
4. The application file-and-network ban (`check_personal_database_search_edges`, `:619-622`, today
   `PersonalFoodDatabase*.swift` and `ApprovedEstimate*.swift` only) extends to `ConfirmEnrichment*.swift`,
   `ConfirmDetails*.swift`, `ConfirmNutrient*.swift` and `OpenRouterEstimate*.swift`, and also bans
   `CryptoKit` and `Date()` there (`FoodLedgerApplication` may import `CryptoKit` elsewhere, `:707`).
5. `Tools/ConfirmEnrichmentEval` follows the `PastedLabelAITextEval` rules (`:726-772`): a pure core
   with no URL loading, one live-transport file, and no network destination other than the 11.1a ones.
   Its import allow-list is `Foundation`, `FoodLedgerDomain`, `FoodLedgerApplication`,
   `FoodConfirmEnrichment` and `FoodGenericSearch`. `FoodGenericSearch` is admitted because the bundled
   row candidates are built there (`CoFIDGenericFoodSearch.swift:306-330` and the other tables), but it
   also holds network clients, so a further rule fails the tool if any of its files names
   `OpenFoodFactsLookup`, `OpenFoodFactsSearch`, `GeminiFoodSearch`, `OpenRouterFoodProvider` or
   `URLSession`. No tool file loads URLs, the live-transport file included: that file builds
   `FoodConfirmEnrichment`'s `ConfirmEnrichmentTransport`, adapters and route checker, so the redirect
   refusal and the destinations are the app's, and the existing `url_loading_pattern` check
   (`check-boundaries.sh:762-764`) runs over the whole tool with a self-test fixture of a `URLSession`
   call in that file. The moved mapping below is named `OpenFoodFactsProductMapping`, which the rule
   allows. Open Food Facts cases go through the existing pure
   `OpenFoodFactsLookup.project(product:artifact:gtin:evidence:retrievedAt:searchScore:searchCategory:)`
   (`OpenFoodFactsLookup.swift:112`), which barcode (`:106`) and search (`OpenFoodFactsSearch.swift:74`)
   already call. PR 3 moves it unchanged, with its full parameter list, into an
   `OpenFoodFactsProductMapping` enum in the same target that names no network type, made `public`
   with its signature otherwise unchanged (it is internal today and the tool is a separate package that
   sees public API only, as `Tools/PastedLabelAITextEval/Package.swift:18` is), and both callers use it.
   The tool builds its `evidence:` argument as the barcode and search callers do, from the export
   record's bytes and the case's retrieval time, so a record read from the downloaded export becomes exactly the app's search or barcode
   candidate. The existing lookup tests pass unchanged, and a golden shows an export record gives the
   same A and B request bytes as both candidates for the same product. **Bundled rows** are reached
   through each table's existing public `search(_:)` (`CoFIDGenericFoodSearch.swift:68` and the other
   tables): the private case list holds the search text and the row's `recordID`, and the tool selects the
   result with that `recordID`, failing the case if it is absent, so no new public API is added for
   them; a test shows the selected candidate equals that row's app search candidate.
6. The energy check parity test lives in `FoodLabelPhotoReadingTests` (dependencies
   `FoodLedgerDomain` and `NutritionLabelParsing`), allowed by the existing rule at `:82`.

## 4. Ports

Each is consumer-owned and passes a shared contract suite in `FoodLedgerTestSupport` run by every
implementation (CE1 test 12).

| Port (application) | Shape | Implementations |
|---|---|---|
| `FoodDetailsSuggesting` | `attempt(_ body: Data, timeout:) async -> ConfirmEnrichmentAttemptResult` | Jev adapter; scripted |
| `NutrientEstimateSuggesting` | the same shape | nutrient adapter; scripted |
| `ConfirmEnrichmentRouteChecking` | `check(_ part:) async -> ConfirmEnrichmentRouteCheckResult` | route checker; scripted |
| `ConfirmEnrichmentCaching` | `answer(subject:part:now:) -> CachedAnswer?`, `store(_:now:)`, `remove(subject:part:)`, `clear()` | file; in-memory |
| `ConfirmEnrichmentSpendLedger` | `read() -> Stored` (`.absent`, `.day(Day)`, `.unreadable`), `update(_ transform: (Stored) throws -> Day) throws -> Day` (atomic) | file; in-memory |
| `PersonalFoodDatabaseEntryReading` | `descriptionFields(recordID:) -> PersonalFoodDescriptionFields?` | `ActiveReleaseEntryReader`; in-memory |
| `ConfirmEnrichmentDelaying` | `wait(seconds:) async throws` (cancellable), for the 1.5 s debounce and backoff | `TaskConfirmEnrichmentDelaying` in `FoodConfirmEnrichment`, as `TaskLabelPhotoSleeper` sits in `FoodLabelPhotoCapture` (`LabelPhotoComponents.swift:12`); scripted |
| `ConfirmEnrichmentElapsedTiming` | `now() -> Duration` (monotonic), for the 60 s whole-call and 30 s attempt deadlines | `ContinuousConfirmEnrichmentTiming` in `FoodConfirmEnrichment`; scripted |
| `ConfirmEnrichmentJittering` | `fraction() -> Double` in 0 to 1, for backoff jitter | `SystemConfirmEnrichmentJitter` in `FoodConfirmEnrichment`; seeded |
| `LedgerClock`, `LedgerIDGenerating` (existing, `LedgerCommands.swift:488, 492`) and a `TimeZone` value | wall time for the local day, `received_at` and the 30-day expiry; `request_id` and evidence IDs | existing |
| Lifecycle input | `ConfirmEnrichmentSession.appBecameInactive()` and `appBecameActive()`, called by the view model from the scene phase | none (an action, not a port) |
| `FoodWebKeyStoring` (existing, `FoodWebDiscovery.swift:49`) | read by the adapters on every attempt | Keychain; test |
| `OpenRouterEgressPermitting` (existing, O1) | asked by the session before reserving, by each adapter before each attempt, and by the route checker before each of its two catalogue fetches, with the catalogue use its caller passes (as `OpenRouterLabelRouteChecker.swift:27-29, 59`); the checker's result gains `.notPermitted`, as `LabelPhotoRouteCheckFailure.notPermitted` | `OpenRouterConsentPreference` composed with `ConfirmEnrichmentPreference`; tool-local gate |

`ConfirmEnrichmentAttemptResult` is `.notSent(reason)` (refused by the gate, no key, cancelled before
sending), `.sent(status, responseBytes, retryAfter)`, or `.transportFailed(class)` after sending.
`.sent` carries no generation ID, cost or token
count: the capture's `generation_id`, the reported cost and the reported prompt tokens all come from
one pure usage and response parse of the response bytes (OpenRouter's `usage` block), which a cache hit
also runs. A value the body does not carry is JSON `null` in the capture, an unreported cost (charged
W) and unreported prompt tokens (no pause). The session also takes the key state (`OpenRouterKeyState`, O1) as an input:
nothing starts unless it is `valid` in this session (CE1.1 rule 5). A key replaced while OpenRouter was
off is never sent (O1 test 2), because the adapter reads the key per attempt and the session reads the
key state per request. Framework, URL and HTTP types never cross a port.

The three real timing implementations run their shared suites in `FoodConfirmEnrichmentTests`; the
composed gate and the Keychain store implement existing ports and stay covered by G17 and
`OpenRouterConsentTests`.

## 5. Invariants (each with the test that holds it)

1. With OpenRouter off, enrichment off, no validated key, the app in the background, or a Confirm
   opened by re-log or quick add, zero requests reach the transport (CE1 tests 3 and 16; G5).
2. A known value or fact is never asked or replaced, checked three times (CE1.6 rule 4; CE1 tests 1, 7).
3. Fortified is never pre-filled: A's choice type cannot express it (CE1 test 5).
4. A B value is `.augmented`, `openrouter_estimate`, tier `low`, with the provenance of 2.1, and never
   a log's only nutrition (CE1 tests 7, 15).
5. Nothing is stored without Log; captures only with a Log that uses them (CE1 test 7).
6. One request never counts more than its per-request cap, retries included; the day caps hold;
   unreported cost counts as W; a broken ledger fails closed (CE1 test 10; G3).
7. The cache holds exactly CE1.2's value (G2).
8. A capture from a cache hit equals the capture from a live answer for the same subject (G1).
9. A record or archive with no CE1 evidence or provenance keeps its record bytes and contract (CE1 test 8).
10. Contract 12 is refused at every range site; schema 7 is written only for a day holding a B value
    (G4; CE1 test 9).

## 6. Consent gating through `OpenRouterEgressPermitting`

- **Preconditions for anything.** No cache lookup, display of a cached answer or request happens
  unless the part is available (below), the OpenRouter and enrichment switch states (read from their
  preferences by the view model, as O1's journeys read the consent state for the blocked row) are both
  on, and the key state is `valid` in this session. This is a state read, not a `permits` call; the
  gate itself is asked only at steps (3) and (4) and by the request sites, so it is enforced twice as
  in O1. So with either switch off or no validated key a
  Confirm shows no suggestion, cached or not, as CE1 section 6 says. The cache-only Confirm that re-log
  or quick add opens (CE1.7a) meets the same preconditions and then reads the cache only.
- **Availability.** The session takes one injected value per part, `ConfirmEnrichmentAvailability`.
  The root's live branch sets it to `use.isInForce`, so before PR 5 the live session never starts; only
  the `#if DEBUG` scripted branch (below) sets it to true, so PR 2's scripted journey runs end to end
  while the uses are not in force. A boundary self-test fails if a true literal for it appears outside
  an `#if DEBUG` block or in a branch that builds a live adapter.
- **Ask again** skips the cache lookup, sends once within the caps, and replaces the subject's entry
  when the answer validates (CE1.1 rule 3, the 11.2 policy text).
- **Order of one request.** (1) The cache: a hit sends nothing and counts nothing. (2) The ledger may
  admit the request (section 2.6). (3) The gate permits the part's use. (4) The route check, when due:
  the first request of the app session and of each local day, and the next request after a check that
  could not connect (CE-T6); the session asks the gate for the part's catalogue check use before it.
  The session holds the checked day and the route-unavailable day per part in memory, as
  `LabelPhotoReadSession.routeUnavailableOn` does (`LabelPhotoReadSession.swift:105, 126, 142-147`). A
  failed or refused check reserves nothing and counts nothing; a failed check other than a connection
  failure makes the part unavailable for the local day. (5) Reserve. (6) Before each attempt the
  adapter asks the gate again. A refusal
  before the first attempt is sent releases the reservation and returns `.notSent`; a refusal before a
  later attempt reconciles only the attempts already sent and ends as `notPermittedAfterSending`, with
  no wait or send after it, as O1 test 2 describes for label photo (`LabelPhotoReadSession.swift:161-172,
  203, 229-238`). A refusal is never retried or slept on. On automatic Confirm it shows nothing (CE1
  section 6); on the `Ask again` row it shows O1's blocked row.
- **The app's gate** permits a Confirm use only when the use is in force, the OpenRouter switch is on
  and `confirmEnrichment.enabled.v1` is true. Enrichment never validates a key.
- **From PR 1 to PR 5** the four cases exist (added in PR 1, so PR 2's session compiles against them)
  with `isInForce` false and `policyEntry` and `egressRow` nil, exactly like the pasted label text uses
  (`OpenRouterEgress.swift:29, 38`), so the existing `OpenRouterConsentTests`
  (`WeeklyHealthReportTests/OpenRouterConsentTests.swift:164-166`) holds and the app's gate refuses them
  even with both switches on. Three existing pins change with them: PR 1 updates
  `Packages/FoodLedgerKit/Tests/FoodLabelPhotoCaptureTests/OpenRouterLabelConsentTests.swift:77` (the not-in-force set, now six uses) and
  `FoodDailyExportContractTests.swift:451` (`ProvenanceSourceKind.allCases` against the origin table,
  gaining `openrouter_estimate` as the schema 7 origin row); PR 5 updates
  `Packages/FoodLedgerKit/Tests/FoodLedgerApplicationTests/OpenRouterConsentSessionTests.swift:26` (the in-force list) and `OpenRouterLabelConsentTests.swift:77`
  again (the not-in-force set becomes the pasted label text uses plus the uses of any part that missed
  its bar).
- **The Debug scripted journey (PR 2).** A `ScriptedConfirmEnrichmentGate` in `FoodConfirmEnrichment`,
  wholly inside `#if DEBUG`, permits the four uses only when both switches are on. The root builds it
  only together with the scripted adapters, never with a live adapter, when the Debug launch argument
  `-ConfirmEnrichmentRoute scripted` is present. The enrichment switch is set for that journey by a
  seed argument with its own key, `-ConfirmEnrichment on|off`, resolved like
  `OpenRouterConsentSeed.resolve(argument:debugBuild:)` (`WeeklyHealthReport/FoodLedger/OpenRouterConsent.swift:50`, applied at `:59-69`):
  it writes or removes `confirmEnrichment.enabled.v1` only with `debugBuild` true and is ignored in
  Release. `ConfirmEnrichmentPreference` reads only the persistent domain
  (`persistentDomain(forName:)`), as O1 requires of the consent switch, so the preference key in the
  argument domain never reads as on. With the scripted route, the session's key state is `valid` from
  a Debug-only scripted source inside the same `#if DEBUG` branch, as O1's scripted label photo mode
  takes its own; it holds no real key. A boundary self-test fails if the scripted gate's name appears outside an
  `#if DEBUG` block, or in the same root branch as a live adapter.
- **Scripted state is separate.** The scripted branch uses the in-memory cache and day ledger
  (`InMemoryConfirmEnrichmentCache` and `InMemoryConfirmEnrichmentDayLedger`, production types in
  `FoodConfirmEnrichment` inside `#if DEBUG`, covered by the scripted gate's self-test, since the app
  does not link `FoodLedgerTestSupport`), never
  `confirm-enrichment-cache-v1.json` or `confirm-enrichment-day-v1.json`, as label photo gives its
  scripted mode its own ledger (`WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift:1811-1817`).
  So a scripted answer, which must name the live route's model and provider to pass the checks, is
  never a hit for a later live request, and scripted requests never use up or pause the live day.
  `Clear suggestions cache` and the Developer tools disclosure act on the active mode's stores only.
- **Where the tests run.** The application session tests (G3's session cases, G5 with scripted
  adapters, G13, G15 and G17's session cases) live in `FoodLedgerApplicationTests` and use test doubles
  of the cache, ledger and suggesting ports in `FoodLedgerTestSupport`, as label photo's session tests
  use their own (`Packages/FoodLedgerKit/Tests/FoodLedgerApplicationTests/LabelPhotoReadSessionTests.swift`).
  Every implementation of each port, the file types, the Debug in-memory types (in
  `FoodConfirmEnrichmentTests`) and those doubles, passes the same shared contract suite. This is the
  package's first `#if DEBUG` source.
- **In PR 5**, for each part that passed its bars, its two uses become in force with `policyEntry`
  `Confirm suggestions.` and `egressRow` the string `<contract link>#<destination prefix>`:
  `confirm-enrichment-openrouter-v1.md#OpenRouter System One` for the Jev uses and
  `confirm-enrichment-openrouter-v1.md#OpenRouter and its one allow-listed model endpoint for nutrient estimates`
  for the nutrient uses. The test's matcher (`:171`) splits `egressRow` at its first `#`: the link part
  must appear as `(<link>)` in the row and, when a prefix is present, the row must start with
  `| <prefix>`; existing uses have no `#` and match by link alone as today. So each use maps to exactly
  one row. The same PR changes the row count (`:168-169`, 2 today) to the number of OpenRouter rows
  then present, and checks each new row's "When" names both switches.

## 7. Contract tests

CE1 section 15's seventeen tests are adopted as written. The gate adds:

- **G1 Rebuild equals live.** For A and for B: a live scripted answer gives a capture; on a second
  Confirm for the same subject the cache hit gives a capture with identical payload bytes and
  `byteHash`, the same `capturedAt`, provenance `capturedAt` and `releasedAt` (the cached
  `received_at`, compared as encoded values at millisecond precision), and the recording transport sees
  zero requests. With the file cache too, which round-trips `received_at` without loss. Both for a
  response with a generation ID in its body and for one with none (`generation_id` null); no header
  value reaches the capture.
- **G2 Cache content.** The decoded key set equals 2.5's; a request with a sentinel description,
  amount and key, answered by a scripted response that does not echo them, leaves none of the three
  strings in the file bytes or in any decoded `response`; an extra key, unknown schema or
  more than 500 entries discards the file; an entry older than 30 days misses; a hit whose bytes fail
  the checks or whose hash differs misses and is dropped.
- **G3 Spend.** Pure `ConfirmEnrichmentSpendPolicy` tests: the 101st request of a day and a request
  that would pass $0.50 make no reservation, no gate call for the request use and no transport call;
  the first attempt starts right after a reservation at the cap, and retries are gated by
  `attemptsCharged`, never `charged_microusd`; no attempt starts when charged plus W
  would pass $0.01 (A) or $0.04 (B); an unreported cost is charged W; reconcile and release are
  idempotent per `request_id`, across a day change; a reported cost above the cap pauses that part
  only; a corrupt ledger refuses until the next local day; a request whose cap would take the day past
  500,000 micro-dollars does not start, so no retry can either; `.absent`, `.unreadable` and `.day` behave as 2.6 says in
  both ledgers; a failed reservation write sends nothing and a failed reconcile closes the part; W
  and reported costs round up to whole micro-dollars; an attempt reported above W is reconciled to its
  full reported amount, above the reservation, and counted in `settled_microusd`; the part pauses when
  any attempt is reported above W, including one where the request stays under its cap (W 3,000,
  reported 4,000, cap 10,000), or when the request's total is above its cap; an attempt whose parsed
  prompt tokens exceed its route's ceiling pauses that part only, for the local day; a route version
  holds no prices, so W changes with the day's catalogue prices alone.
- **G4 Numbers.** An archive labelled 12 is refused at each of the three range sites; an archive
  labelled 11 holding each kind of CE1 content (B provenance, an A capture, a B capture, a choices item)
  fails decoding; 11 and 13 are
  accepted; contract 13's `migrationIdentifiers` are v1 to v11 plus v13; a store at 11 migrates to 13
  changing metadata only; each field of 2.1 is required in its exact form (one mutation test per field,
  giving "Evidence not available").
- **G5 Gate and attempts.** A shared single-attempt suite, run by the scripted and live adapters: the
  gate is asked on every attempt and records its own use; a use not in force, with both switches on,
  makes zero transport calls; a refusal on attempt 1 releases the reservation; a refusal on attempt 2
  ends with exactly one send, reconciles only it and gives `notPermittedAfterSending`; a key replaced
  while the switch was off is never sent.
- **G6 Wire bytes.** The bytes the transport records equal the capture's `request_body` and the
  committed golden; only the Authorization header holds the key; the provider block equals the route
  version's; a redirect is refused.
- **G7 Boundaries.** Every boundary self-test fails on its fixture: items 1 to 5 of section 3.3 (item 6
  adds no rule; its parity test lands in PR 1 under the existing rule at `:82`), the routes file passing
  only through its exemption, the
  availability literal and the scripted gate name (section 6).
- **G8 Layers on reopen.** A B entry with the #464 layer, chosen before and after B answers: save,
  reopen and edit verify; `layer_dropped`, `merge_parent_dropped` and `merge_energy_dropped` are
  rebuilt exactly; altering any list shows "Evidence not available". A layer chosen after B whose merge
  passes the energy check keeps B rows that B's own values alone would not; a layer parent below a
  kept B child drops that child.
- **G9 Your foods.** Through both builders, each saved `openrouter_estimate` key becomes
  `.unknown(not_declared)` and the row is classified by its real source.
- **G10 Consent records.** Before PR 5 the four uses are nil and refused; after it, the not-in-force set
  is the pasted label text uses plus any part that missed its bar, and each in-force use
  maps to exactly one row and one policy entry.
- **G11 Evaluation tool.** Its console output, every error and stop message included, names cases only
  by hash and carries no request body, response, barcode or description. The tool binary's only network calls go to the 11.1a destinations; it refuses to send
  without the 11.1a paragraph on `origin/main`; it stops at the spend limits.
- **G12 Readers and citations.** The pasted label, label photo and approved-estimate `.labelText`
  readers ignore the three CE1 method versions, and the CE1 readers ignore every other version; an
  Open Food Facts entry with the #464 layer, an A capture, a B capture and a choices item passes
  `applies` on reopen and edit; a choices item whose `resolution_version_id` differs from the citing
  version fails verification; re-log and quick add drop all three ID kinds. Reopen, Put back, save,
  reopen, Leave out, save: each version's decision cites exactly one choices item, its own, and no
  earlier CE1 or leave-out ID appears twice.
- **G13 Time.** Scripted delay, elapsed time, clock and jitter drive the debounce, the 60 s and 30 s
  deadlines, `Retry-After`, the day reset and the 30-day expiry; no new application file calls `Date()`.
- **G14 Route check.** Runs once per app session and local day, and again after a connection failure;
  a failed or refused check reserves and counts nothing; a day whose prices make W exceed the cap
  makes the part unavailable; a body over its prompt ceiling is refused before sending; with
  `max_tokens` not accepted, W uses the response-limit ceiling. The route checker asks the gate before
  each of its two catalogue fetches with the catalogue use its caller passes; a refusal before either
  fetch sends nothing more, reserves nothing and leaves the part available.
- **G15 Cache writes and Debug wiring.** A cancelled or late answer is never stored; an all-unknown A
  answer and an all-dropped B answer are stored and reused; the file and in-memory caches give the
  same results under `ConfirmEnrichmentCachePolicy`; a scripted answer is never a hit for the live
  cache, and scripted requests never change the live day record (`requests`, `settled_microusd`,
  `paused`); the scripted gate cannot be reached in Release
  (boundary self-test of section 6).

- **G16 Seed isolation.** `-confirmEnrichment.enabled.v1 YES` in the argument domain reads as off in
  every build; the `-ConfirmEnrichment on` seed writes only with `debugBuild` true; the Debug key-state
  source is not compiled in Release.
- **G17 Preconditions and composition.** With enrichment off, OpenRouter off or no validated key, a
  cached subject shows no suggestion and nothing is sent; `Ask again` on a cached subject sends once
  and replaces the entry; every CE request site and the route checker receive the composed gate, which
  refuses with enrichment off and OpenRouter on, while the bare `OpenRouterConsentPreference` is
  unchanged (`OpenRouterConsentTests.swift:48`). A save of a reopened CE1 entry that writes no new CE1
  evidence (a details correction removing B, every B row left out, a fill replaced in the sheet)
  carries no earlier B capture or choices item, in its decision candidate or its product version,
  carries the A capture exactly when the A rule holds,
  and verifies; a quantity-only edit writes no new decision, product version or resolution version; a
  B-only Leave out on reopen writes the frozen `OpenRouterEstimateChoicesText` reason, claim and edit
  reason and carries the earlier decision record; the request inputs decode from each route golden,
  and changing them while keeping the hashes fails verification; a details correction across a Your
  food database release change keeps or removes B by the subject rule of 2.4a; an Open Food Facts entry with the #464 layer and B rows keeps B after a details
  correction that leaves the source-side subject unchanged, with the layer chosen before B and with it
  chosen after B, and removes it with the frozen note after one that changes the identity tokens; `Not these` before the first Log commits no A capture; a
  B-only Leave out on a reopened log keeps the earlier expectations and outcome; a kill between
  reservation and reply leaves the request counted at its cap; a clock moved back resets nothing.
Fixtures are synthetic, under `docs/fixtures/confirm-enrichment-v1/`: request goldens per route
(CoFID, USDA, TFDA, Ciqual, Open Food Facts search and barcode, Your food database, including a title
with a pack size), scripted responses per row code, records and archives at contract 13, and daily
export goldens for schema 7 alone and mixed with schema 3 and 5 content.

## 8. Privacy and egress records

- **Section 11.1 rows and the "Stays on the device" sentence** are added to `privacy-and-egress.md`
  word for word as CE1 writes them, **in the wiring PR (PR 5)** and not before (CE-T14), with the 11.2
  policy entry in `privacy-policy.txt`, the O1 switch title and framing changes (CE1 section 9) and
  the uses turned in force. A verbatim test pins them, as
  `testTheLabelPhotoPrivacyRecordsAreInForceVerbatim` does for label photo.
- A part that missed its bar is not put in force, and its row and policy wording are not added. If only
  one part ships, the wiring PR carries a narrowed text for that part, shown to the owner first; never a
  widened one.
- **Section 11.1a**, the tooling paragraph, is added word for word in PR 3 and must be on `main` before
  the tool's first network call. The tool's preflight refuses to send unless the paragraph is present,
  word for word, both in `docs/privacy-and-egress.md` of the checkout it runs from and in that file on
  `origin/main` (`git show origin/main:docs/privacy-and-egress.md`). The tool binary never runs git
  over the network: a wrapper script runs `git fetch origin` first with the key unset, as
  `Tools/PastedLabelAITextEval/promptfoo/run-heldout.sh:36` does, and the tool only reads.

## 9. Evaluation before any release (CE1 section 12)

- **Data source, no new destination.** The tool makes no Open Food Facts request. Open Food Facts cases
  are read locally from a public Open Food Facts data export that the owner downloads by hand outside
  the tool and outside the app (no user data, like the bundled source datasets). Composition rows come
  from the app's bundled projections. No agent or tool fetches the export; a fetch by either would need
  its own approved paragraph in `privacy-and-egress.md` first.
  **Dated amendment, 21 November 2026 (owner approval, #549):** that paragraph now exists. At the owner's
  request an agent may download the one public export named there into the owner's private folder and
  run the tool's deterministic `select` command, which draws both sets with a recorded seed and prints
  only counts and manifest hashes. The agent never opens or reads the export, case lists, records or
  review sheet. The review sheet and every send to OpenRouter stay the owner's own steps, as below. The tool's only network calls are the 11.1a destinations (section 11,
  point 4).
- **Sets.** Development set: 60 Open Food Facts products (UK and Taiwan, packaged, complete declared
  panels, at least 8 fortified) and 40 bundled rows; a sealed set of the same size and mix. The owner
  checks the food details of the Open Food Facts cases on a review sheet before any A score counts.
  The case lists themselves (case identifiers, barcodes, search texts, row identifiers) and the review
  sheet stay in the private folder with the product data and responses. The repository gets only what
  the 11.1a paragraph allows: counts, versions and hashes, so the committed manifest of each set is the
  SHA-256 of its canonical case list with the case count, and the review sheet outcome is committed as
  counts only.
- **Bar class and floor per key.** The error is `|estimate - declared| / max(declared, floor)`, so a
  declared 0 never divides by zero. Every `NutrientKey` (`Nutrition.swift:12-50`) is in exactly one row:

  | Class (CE1 section 12) | Keys | Floor | Bar |
  |---|---|---|---|
  | Energy | `energy_consumed` | 5 kcal | 20% |
  | Macronutrients | `carbohydrates`, `protein`, `fat_total`, `fat_saturated`, `fat_monounsaturated`, `fat_polyunsaturated`, `sugar` | 0.5 g | 20% |
  | Fibre and sodium | `fiber` (0.5 g), `sodium` (5 mg) | as shown | 35% |
  | Other micronutrients | the thirteen vitamins and the thirteen minerals from `calcium` to `selenium` except `sodium` | 10% of the key's reference intake in Annex XIII of retained Regulation (EU) No 1169/2011, held as a constant table in the scorer only (the app gains no reference value); every one of these keys has one | 50% |
  | Not measured | `cholesterol`, `water`, `caffeine`: no Annex XIII reference intake and not in any CE1 class | none | none |

  Because no bar can measure the last row, the gate removes those three keys from B's eligible set in
  v1 (`ConfirmEnrichmentPolicy` never requests them), so the app never shows an estimate the
  evaluation did not measure (section 11, point 6). A scorer test maps all 39 keys (1 + 7 + 2 + 26 + 3)
  to exactly one row each, `sodium` only in the fibre and sodium row.
- **Who runs it.** The owner runs the tool on the Mac and reads its output and the review sheet there.
  No agent starts a run, reads its console output or reads the private folder, so no case data reaches
  an agent's model provider; an agent sees only what the owner commits to the repository (counts,
  versions and hashes). The key, as 11.1a says, is the OpenRouter key already approved for the
  evaluations, read into memory only and never printed or stored; the gate adds that it is read from
  the owner's own environment. The tool's console output, every error and stop message
  included, still names a case only by its hash (a G11 case), so a pasted log carries no case data.
- **Run.** The tool sends exactly the app's request bytes through the `FoodConfirmEnrichment` adapters
  with a tool-local gate, under CE-T15 ($25 programme, $0.05 per call, in its own spend ledger before
  every call; at most 3 attempts with backoff honouring `Retry-After`). It runs its own loop over the
  pure `ConfirmEnrichmentRetryPolicy` and its CE-T15 ledger, not `ConfirmEnrichmentSession`, so the app's
  daily caps do not apply to it and the retry behaviour the latency bar measures is the app's. For B, known values are hidden
  per case as CE1 section 12 says.
- **First request stop.** The first A request checks that System One accepts the body and returns the
  CE1.4 shape. If it does not, the run stops: switching to `alpha/decisions` reopens CE-T1 and the 11.1
  row for the owner (CE1.4). It also records whether `max_tokens` was accepted (which fixes the route
  version's completion ceiling, section 2.6) and stops if the reported prompt tokens exceed the route's
  prompt ceiling, since W would then not be a worst case. If `max_tokens` is not accepted and the
  fallback W is above $0.01 at the day's prices, the run stops and the owner decides, because A could
  then never run in the app. More generally, the first request of each part computes W at that day's
  catalogue prices with the route version's ceilings; if W is above the part's per-request cap, the run
  stops for the owner, since the part could pass every bar and still never run in the app. The 4b
  report records, per part, only whether W was within the cap; W itself stays private.
- **Route freeze.** `confirm-details-route-v1` (committed in PR 2) is frozen only after the first A request has shown
  whether System One accepts `max_tokens`. Any change that follows to `ConfirmEnrichmentRoutes.swift`
  and to A's synthetic request golden of PR 2 lands in PR 4a, before the frozen configuration. The first
  request is an evaluation case, so its body never enters the repository: PR 4a commits only its
  SHA-256. The route freeze check is part of `Tools/ConfirmEnrichmentEval`, run from the private folder,
  which rebuilds that body from the private case through the app's builder and compares the hash. No
  repository test reads the private folder, and no evaluation case is ever committed as a fixture.
- **Order.** PR 4a commits the scorer, the bars as code, both manifests and the frozen configuration,
  and merges. Only then is the sealed set sent, once, by that configuration, and its report lands in
  PR 4b. A prompt change during development is a prompt version bump.
- **Outcome.** The repository gets counts, versions and hashes only, as 11.1a says: per bar, pass or
  fail and the number of cases within and outside its threshold; per part, whether W at the day's prices
  is within the per-request cap. The medians, the p90 latency, the costs and W themselves stay in the
  private folder with the per-case results, for the owner to read there. A missed bar stops release of
  that part; the other may ship alone. If A misses the wrong pre-fill bar at 0.85, the report gives the
  lowest threshold that passes and the owner chooses (CE-D3).
- **Release.** No build that can reach a route outside Debug goes anywhere until its part passes; then
  internal TestFlight only (CE-T13), after the owner's one combined device check of O1 and CE1.

### PR 4a scorer architecture

The evaluation core owns the versioned nutrient classes, hidden-key policy and bar arithmetic.
The harness reads local evidence and reuses the app's request, response and merge rules. The CLI
only renders aggregate counts and pass or fail. Dependencies point from the executable and harness
to the core and from the core to the existing domain and application types. The scorer has no
network access or open extension for new bars. An alternative evidence reader must supply the
same typed observations and pass the synthetic integration tests. The contract tests cover all
keys, hidden variants, validation drops, missing evidence and boundary values for each bar.

For a legacy Open Food Facts panel with only declared salt, the scoring reference uses declared
salt divided by 2.5, converted from grams to milligrams. The app's projection stays unknown for
sodium. B creates one variant per available class in the order energy, macro, fibre, sodium,
other micronutrient. Within the macro and other micronutrient classes, the case's position in its
manifest rotates through its declared keys in raw-key order. Each variant hides one key; other
eligible unknowns remain eligible. Only the hidden key has a reference for accuracy. B's coverage
uses all requested keys. A's fact bars use the owner-reviewed Open Food Facts cases. A pre-fill
without a confirmed match counts outside the wrong pre-fill bar. The fortified safety bar needs
at least eight owner-confirmed fortified products in each set.

**Dated scorer rule, 22 November 2026 (owner decision, #564).** Each hidden key belongs in its
accuracy class's median even when B omits the key or validation drops the estimate. The scorer
counts it outside the limit and sorts it after every finite error. A missing middle value makes
the median fail.

Send and score use the same request plan. A reviewed case without A questions contributes no
request. The tool refuses an unreadable case, a refused request build or an ineligible B variant
before sending anything. A run with a planned request that never starts has no scorable completion.
Failed attempts on a started request stay in the measured sample. The latency clock ends at the
last attempted response or transport failure.

The sealed send requires a complete freeze record, a clean checkout whose commit is on
`origin/main`, the sealed manifest and a successful local rebuild of the first A request from
the development manifest. It claims each sealed part once before sending it, and only when the
programme stop still leaves room for that part's whole run at worst: for every planned request,
the smaller of three attempts at W and the part's whole-request cap. The bound holds while each
attempt reports at most W; a report above W can still stop a claimed run. Otherwise it prints the needed and
remaining amounts and stops without claiming or sending. A claim is never given back: a sealed part
whose send stops after its claim (a transport failure, the first request stop, a ledger refusal or
an unwritable record) stays used up and is never sent again, because the model may already have
seen some of its requests. The owner decided this on 22 November 2026. The two parts and both sets share the live
spend ledger. Development, sealed and fake completion evidence have
separate locations. Fake sends and scores are labelled and refuse the sealed case list.
Before the freeze, the owner can run `check-plan --cases CASES --private DIR` on either set. It
builds both parts' request plans as `send` would, offline with no key, and prints the request
counts, or one stop code for the part whose plan cannot be built (for example because of a bundled
row with no measurable B variant) without naming the case. The owner can use `prepare-sealed-review` after the same merged freeze checks. It creates the
sealed review sheet once and reports only its row count.

## 10. PR split

Each PR has its own branch, a ledger row, the validation gates of `AGENTS.md`, a blind
`invariant-reviewer` and a general defect review at its head, and the owner's yes before merge.

| PR | Content | Egress |
|---|---|---|
| 1. Formats | Domain kinds, provenance and release constants, capture and choices types, row and energy checks with the parity test, the application response checks and the request input types with their decoders (which verification needs), the strip, skip, drop-on-new-log and verification rules of 2.4a (the B-choices term of "The reopen path" and `OpenRouterEstimateChoicesText` land in PR 2 with the suggestion layer), the four `OpenRouterUse` cases not in force with nil mappings, contract 13 floor and accepted set, store 13, export 7 writer and validators, verification on save and reopen, fixtures; dated notes in assistant-pasted estimates v1 and food daily export v2. Store 13 migrates every store on first open, so a downgrade past it is refused. No UI writes CE1 records yet. | None |
| 2. Confirm layer | Application policy, session, spend, retry and cache policies, ports and their suites; the `FoodConfirmEnrichment` target and product with the file cache and ledger, the scripted adapters and the Debug scripted gate and the in-memory cache and ledger (no live adapter); `ConfirmEnrichmentRoutes.swift` with its `openrouter_exempt` entry, and the request goldens; `ConfirmEnrichmentPreference` (persistent-domain read of `confirmEnrichment.enabled.v1`), the Debug seed argument, the Debug-only scripted wiring at the composition root and `ConfirmEnrichmentAvailability`; the B-choices term of 2.4a's reopen path with `OpenRouterEstimateChoicesText`; boundary items 1, 2 and 4, the scripted gate self-test and the availability literal self-test; the Your food database read port and adapter; the suggestion layer, reducer, fill builder, Log requirement, re-log, quick add, re-resolution and reopen rules; presentation; the save-side writing of the captures and choices item in `FoodConfirmationService.save`; `OpenRouterEstimateCarry` and its use in both Your foods builders; scripted answers reachable only by a Debug launch argument; simulator journey with scripted answers. | None |
| 3. Adapters and tooling | The two adapters, route checker and transport (G6 compares their wire bytes with PR 2's goldens); the public `OpenFoodFactsProductMapping`; boundary items 3 and 5; `Tools/ConfirmEnrichmentEval` with its preflight; the section 11.1a paragraph. Not wired into the app. | Tooling only, after merge |
| 4a. Evaluation freeze | Any route constant and golden change from the first request (route freeze), development run counts, versions and hashes (raw runs stay in the private folder), review sheet outcome as counts, scorer, bars as code, manifests, frozen configuration. | Tooling only |
| 4b. Sealed report | The single sealed run's report. | Tooling only |
| 5. Wiring | Composition root and the composed live gate, the Settings toggle row with its caption and the other Settings rows, the uses in force for each part that passed, section 11.1 rows, 11.2 entry, O1 title and framing changes, Developer tools disclosure, journey QA; then the combined device check. | App, with both switches on |

PRs 1 to 3 can be reviewed and merged without any network call from the app.

Tests per PR (CE1 section 15 tests land with the code they cover): **PR 1** G4, G12's fixture cases (reader selection
each way, the `resolution_version_id` refusal, re-log and quick add dropping all three ID kinds,
`applies` on fixture records) and the format and verification half of G8; **PR 2** G1, G2, G3, G5 (scripted adapters), the rest of G8, G12's Put back and Leave out
citation sequence and the reopen and edit of a B entry with the #464 layer, G9, G13, G15,
G16, G17 and G7's items 1, 2 and 4, the routes file exemption, the scripted gate and the availability
literal, and a test that the scripted answers, captures and goldens take model, provider and endpoint
from the `ConfirmEnrichmentRoutes` constants; **PR 3** G5 (live
adapters), G6, G11, G14 and G7's items 3 and 5; **PR 4a** the scorer table test (the route freeze
check runs in the tool, not as a repository test); **PR 5** G10, the verbatim records test, and a test that the scripted and live branches read the same
route values.

## 11. Points the owner sees before approving

1. **Food contract 13 leaves 12 unused.** CE1 names 13 because 12 is reserved; ordered store
   migrations mean 12 can never be built after 13, so assistant-pasted estimates takes the next free
   number at its own phase (its section 7 allows this) and every reader refuses 12. The alternative,
   CE1 taking 12 and assistant estimates moving to 13 as the label photo gate did with 11, is equally
   safe; the gate keeps 13 because the approved contract and the hand-over name it.
2. **Export 7 and assistant fields.** CE1.7 says version 7 also admits version 6's fields "once that
   lands". A shipped version is never widened (label photo gate, section 1), because an older build
   would reject a newer file of the same version. So 7 is built without assistant fields, and a day
   mixing B and assistant values is left to the assistant phase, which allocates a new number. No B
   day is affected.
3. **Checks one layer down.** Section 3.2 places request building and response checks in application
   code rather than in the adapters, so a cache hit and a reopen run the same checks. No term changes.
4. **Per-request caps across retries, and the evaluation's data.** The gate reads "$0.01 per request"
   and "$0.02 per request" (since raised to $0.04 for B, 22 November 2026) as whole-request totals across all attempts, enforced before each attempt
   (section 2.6), never as per-attempt figures. And the evaluation reads Open Food Facts data from a
   public export the owner downloads by hand outside the tool, adding no destination to 11.1a; a fetch by the tool would
   need its own approved addition first. Both narrow; neither changes a term.
5. **Every store moves to 13.** CE1 section 14 speaks of refusing a downgrade "for a store that holds a
   B value". The store's migrations are per store, not per record, so the first build carrying PR 1
   migrates every store to 13 and refuses a downgrade past it for every store, as each earlier
   contract step did (`FoodLedgerMigrations.swift:76`, `FoodLedgerGRDBStore.swift:1248`). Archives and
   exports without CE1 content keep their bytes and labels, as CE1.7 says. So no build cut from `main`
   after PR 1 can be downgraded below it.
6. **Three keys not requested from B.** CE1 section 12 gives no bar class to `cholesterol`, `water` or
   `caffeine`, and Annex XIII gives them no reference intake, so the evaluation cannot measure them.
   The gate leaves them out of B's eligible keys in v1 (they stay unknown, as today). This narrows
   CE1.5; adding them later needs a bar and a version bump.
7. **Three more key lists in the choices item.** CE1.7 lists the choices item as the version ID, the
   capture hash and the left-out keys. The gate adds `layer_dropped`, `merge_parent_dropped` and
   `merge_energy_dropped` (section 2.4): nutrient keys only, no values, so reopen can rebuild the merge
   checks that CE1.6 rule 3 runs after the merge.
8. **The evaluation tool also imports the adapters.** CE1 section 15 names the composition root as
   the only importer of `FoodConfirmEnrichment`. The gate also lets `Tools/ConfirmEnrichmentEval`
   import it, so the evaluation sends exactly the app's request shapes (CE-T15); the tool is outside
   the app and the boundary rule names it.
9. **A second, Debug-only gate.** O1's Debug label photo flow reuses the app's preference as its gate.
   The CE1 uses are not in force until PR 5, so PR 2's scripted journey needs its own Debug-only gate
   (section 6). It is built only with the scripted adapters, makes no network call and is not compiled
   in Release.

## 12. Not in this phase

Web lookup, label routes and Your foods rows on Confirm (CE1 section 2); any change to the catalogue or
its skill; external TestFlight or App Store builds; any evaluation call before section 11.1a is on
`main`.

## 13. Review record

- **Architecture gate, first round (21 November 2026, at `4f9a5d22`): PASS WITH CHANGES.** All sixteen
  findings taken: single-attempt ports with retries, backoff and reservations in the session, and a
  refusal after sending kept distinct; a pure spend policy with per-request reservation identities in
  the day record; the four uses keep nil mappings until the wiring PR, which updates the consent test's
  row count and matcher; per-request caps as whole-request totals with W sized from route prices; the
  evaluation reads Open Food Facts data locally and sends only to the 11.1a destinations; the
  application boundary rule extended to the new files and `CryptoKit`; the routes file as a reviewed
  request-site exemption with no URL in application code; target, product, dependents rule and scripted
  adapters moved into PR 2, tool rules added; layer-dependent drops moved from the capture to the
  choices item so verification can rebuild them; the Your foods rebuild as one pure function; the key
  source and key state named; all three archive range sites and the migration identifier list pinned;
  a dated note on food daily export v2 and the store downgrade stated; PR 4 split into freeze and
  sealed report, the first-request stop and the reference intake table named; three citation fixes;
  stricter provenance checks, the ledger's protection class and the redirect refusal.
- **Architecture gate, second round (21 November 2026, at `524e6848`): PASS WITH CHANGES.** All fourteen
  findings taken: the four uses move into PR 1, and a Debug-only scripted gate and seed argument serve
  PR 2's journey without ever wrapping a live adapter; each CE1 evidence item's citation site is pinned
  (a new decision per saved version, items appended in a fixed order) with the skip list and the drop
  on new logs; clock, monotonic time, jitter, ID generator, time zone and lifecycle inputs are named;
  W uses the day's catalogue prices and pinned prompt and completion ceilings, an over-ceiling body is
  refused and a too-costly day disables the part; the route check is placed in the request order with
  its state holder; the cache gains `remove`, one expiry policy and a rule for when it is written,
  including validated answers that pre-fill nothing; the downgrade of every store is a point for the
  owner; response checks move into PR 1; the corrupt ledger and day change rules are mechanical; the
  `egressRow` encoding is pinned; a reader test each way; the preflight checks `origin/main`; the
  micronutrient floor choice is listed; CE-D5's source field is named.
- **Architecture gate, third round (21 November 2026, at `82120dab`): PASS WITH CHANGES.** All nine
  findings taken: A's completion ceiling falls back to the response limit when `max_tokens` is not
  accepted, and the first request stops on prompt tokens above the ceiling; the three existing test
  pins that change are named per PR; the seed argument has its own key and the preference reads only
  the persistent domain; the route checker asks the gate before each fetch and returns `.notPermitted`;
  the energy check and a parent check against layer parents run on the merge, as CE1.6 rule 3 says,
  and are recorded in the choices item, so the capture holds only request-and-reply codes; G2 checks
  decoded responses and the echo rule is stated; a hit's three times are the cached `received_at`; the
  scripted key state is named; the Debug-only gate is an owner point.
- **Architecture gate, fourth round (21 November 2026, at `4aa2a281`): PASS WITH CHANGES.** All eleven
  findings taken: on reopen the bound candidate's own evidence IDs exclude earlier leave-out and CE1
  items, each new decision cites its own choices item once, and a B Leave out or Put back never takes
  the leave-out-only path; the day cap is checked before every attempt; the ledger port reports absent,
  day or unreadable with an atomic update, the fail-closed rule lives in the spend policy, and failed
  writes are defined; times are truncated to milliseconds and `received_at` has three fractional
  digits; a refused `max_tokens` with W above the cap is a first-request stop; the choices item's extra
  lists are an owner point; costs round up to whole micro-dollars; save-side writing and the Your foods
  carry function are placed in PR 2; the locale source is pinned; two citations corrected.
- **Architecture gate, fifth round (21 November 2026, at `1a5f1ef5`): PASS WITH CHANGES.** All nine
  findings taken: the reopen path is described as the code has it, and widened so a B choice change
  keeps the earlier expectations and outcome; the strip rule applies to every save of a CE1 entry, with
  a rule per item for when it is cited and an all-left-out version citing neither B item; the ledger
  update takes the stored state and may throw without writing; a reservation writes the whole
  per-request cap before sending and a clock moved back resets nothing; the cache and every request
  need both switches and a validated key, and `Ask again` bypasses the cache; two citations corrected;
  the git fetch runs in a wrapper; the tool runs its own retry loop; the tool import is an owner point,
  the Debug root wiring is in PR 2 and the composed gate has a test.
- **Architecture gate, sixth round (21 November 2026, at `9058cf5f`): PASS WITH CHANGES.** All nine
  findings taken: a B-only choices save writes frozen assertion and edit texts and carries the earlier
  decision record; the citation rule applies only to saves that change the product; the A capture's
  carry rule is stated against the version being saved and the leave-out rule is named; each request's
  variable part is one canonical object with a closed decoder, in PR 1, so verification never parses
  prose; B's subject on reopen is computed from the stored inputs; the per-attempt total is named apart
  from the reservation; the evaluation stops when either part's W would exceed its cap; the
  preconditions are a state read, not a gate call; one citation corrected.
- **Architecture gate, seventh round (21 November 2026, at `3feec3b3`): PASS WITH CHANGES.** All six
  findings taken: availability is an injected value per part, true only on the Debug scripted branch,
  so PR 2's journey runs while the uses are not in force; the tool's import list admits
  `FoodGenericSearch` with a rule that it never names that target's network types, and a pure Open Food
  Facts product mapping makes an export record the app's candidate; a reported prompt above the
  ceiling pauses the part, with a worst-case golden; an archive labelled below 13 holding CE1 content
  fails decoding; PR 1 and PR 2 split the 2.4a rules by what each can compile.
- **Architecture gate, eighth round (21 November 2026, at `e07e931f`): PASS WITH CHANGES.** All six
  findings taken: the generation ID comes only from the response parse, null when absent; every
  nutrient key has a bar class and a floor, and the three with no class or reference intake are left out
  of B in v1 (an owner point); A's route is frozen after the first request, with any change in PR 4a;
  the existing Open Food Facts `project` function is moved unchanged rather than a new one written; the
  reconcile moves the charge up or down; every boundary self-test is in G7.
- **Architecture gate, ninth round (21 November 2026, at `3aabe37f`): PASS WITH CHANGES.** All four
  findings taken: sodium sits in one row only and the table counts all 39 keys; one pause trigger
  (any attempt above W, or the request's total above its cap) in both places; no tool file loads URLs,
  the tool reuses the app's transport, and the whole-tool URL check applies; the product version takes
  the same evidence list as the new decision; the availability self-test is placed in PR 2.
- **Architecture gate, tenth round (21 November 2026, at `622bed0d`): PASS WITH CHANGES.** All six
  findings taken: cost, prompt tokens and generation ID all come from one pure usage parse, with a
  prompt-over-ceiling pause test; route versions hold no prices; B's subject on reopen is built on the
  source side only, so B and layer values never enter it; the moved Open Food Facts mapping is made
  public and bundled rows are reached through the tables' public search by `recordID`;
  `ConfirmEnrichmentPreference` and its seed test move into PR 2; tests are in numeric order with a
  per-PR list.
- **Architecture gate, eleventh round (21 November 2026, at `a0502b9f`): PASS WITH CHANGES.** All three
  findings taken: the reopen subject comparison removes the saved label layer's keys from the eligible
  keys on both sides, so it holds whichever order the layer was chosen in, with a G17 case for each; G12
  is split between PR 1 (fixture cases) and PR 2 (the choices sequence and the layered edit); the
  attempt result's third case is restored to the list.
- **Architecture gate, twelfth round (21 November 2026, at `5a6f1f1f`): PASS WITH CHANGES.** Both
  findings taken: the scripted branch uses in-memory cache and ledger, so a scripted answer never
  reaches the live cache or day record, with a G15 case; PR 5 also updates the not-in-force pin, with
  G10 to match.
- **Architecture gate, thirteenth round (21 November 2026, at `99948264`): PASS WITH CHANGES.** All four
  findings taken: the routes file, its exemption and the request goldens move into PR 2, with the
  request sites still in PR 3; the in-memory cache and ledger are production Debug-only types in
  `FoodConfirmEnrichment` that the shared suites run; G7 drops item 6, which adds no rule; the
  reservation of contract 12 is cited to the dated amendment.
- **Architecture gate, fourteenth round (21 November 2026, at `c1975b36`): PASS WITH CHANGES.** Both
  findings taken: the session tests' home and their doubles are named, with every implementation
  passing the shared suites; the PR 2 route test checks the constants, and the scripted-versus-live
  comparison moves to PR 5. Two test paths were made explicit.
- **Architecture gate, fifteenth round (21 November 2026, at `eb96ad76`): PASS.** One optional low
  finding taken: the real delaying, elapsed-timing and jitter implementations live in
  `FoodConfirmEnrichment`, where their shared suites run, and the composed gate and Keychain store stay
  covered by their existing tests.
- **Owner approval (21 November 2026).** The owner approved the gate as written, including the nine
  readings of section 11, so implementation may start with PR 1 (formats).
- **Blind invariant review (21 November 2026, at `af12ad6b`): PASS.** Taken: the evaluation case lists
  and review sheet stay private and the repository gets only hashed manifests and counts, as 11.1a
  allows; the Open Food Facts export is downloaded by the owner by hand, never by an agent or the tool;
  the cache sentence says no field holds the request body; `generation_id` in A's capture is noted as
  CE1.7 names it for B; the PR count is corrected.
- **Blind invariant re-review (21 November 2026, at `de390a6c`): BLOCK, fixed.** The route freeze
  golden would have put one evaluation case's description in the repository; PR 4a now commits only
  the first request body's SHA-256. Also taken: PR 4a commits development run counts, versions and
  hashes only; a broken section 9 sentence is split; section 11 point 4 says the owner downloads the
  export by hand.
- **After approval.** Every edit after the owner's approval of 21 November 2026 (the invariant review
  and its three re-reviews recorded here) narrows a term or states a step, and none widens one: the
  evaluation case lists and review sheet stay private and the repository gets hashed manifests and
  counts; the route freeze keeps only a body hash and runs inside the tool; the outcome stays counts,
  versions and hashes, with medians, latency, costs and W kept private; the owner, not an agent, runs
  the tool and fetches the Open Food Facts export by hand (a new manual step for the owner); the tool's
  output names cases by hash only. They are shown to the owner with the merge ask.
- **Blind invariant re-review 2 (21 November 2026, at `9972e6bc`): PASS.** Three low findings taken: the
  route freeze check runs inside the tool from the private folder, and no repository test or fixture
  holds an evaluation case; the outcome names the aggregate figures it commits, never per-case data;
  the status line notes the edits after approval. The open question is answered in section 9: the
  owner runs the tool, and an agent sees only what the repository may hold.
- **Blind invariant re-review 3 (21 November 2026, at `1dcfb85e`): BLOCK, fixed.** The previous edit had
  read "counts" in 11.1a as including medians, latency and costs, a widening after approval; the
  outcome is back to counts, versions and hashes, with pass or fail per bar and the figures kept
  private. Also taken: the owner runs the tool and no agent reads its output or the private folder;
  the tool's output names cases by hash only, with a G11 case; the key source is stated; the record of
  edits after approval is complete.
- **Blind invariant re-review 4 (21 November 2026, at `5ec923df`): PASS.** Every change since the
  approval at `af12ad6b` narrows a term or adds a step. One low citation fix taken after it: the key
  sentence now credits 11.1a only with what it says. That commit changes wording only.

## PR 4a configuration record

| Version or count | Value |
|---|---|
| Evaluation configuration | `confirm-enrichment-eval-configuration-v1` |
| Scorer | `confirm-enrichment-eval-scorer-v1` |
| Case list | `confirm-enrichment-eval-cases-v1` |
| Request and completion evidence | `confirm-enrichment-eval-request-v1`, `confirm-enrichment-eval-completed-run-v2` |
| A route and prompt | `confirm-details-route-v1`, `confirm-details-prompt-v2` |
| B route, prompt and response schema | `confirm-nutrient-route-v1`, `confirm-nutrient-prompt-v1`, `confirm-nutrient-estimate-v1` |
| Development count | 100 |
| Sealed count | 100 |
| Open Food Facts per set | 60, 30 UK, 30 Taiwan, 8 fortified |
| Bundled rows per set | 40, 10 per table |
| Development SHA-256 | `1c357f97866f1a5f62b078201e5217d9f814e00f93a59942099a948dcd619bfa` |
| Sealed SHA-256 | `a3396991fe7b42a9a5faeb027a5e74f891ef5eacbe539cc6385fbe0b6dcc495b` |
| First A request SHA-256 (prompt v2) | `7894c4ed72b4e0ddc95bd8fdc6b394cf31b7de0dd7bb9183620c80184b06a0cc` |
| Development plan | 60 A requests, 406 B requests |
| Reviewed products | 60, of which 11 fortified |

The route freeze was recorded on 22 November 2026 (`EvalConfiguration.freeze`) from the first A
request under prompt v2, reported by `send --part details --first-request-only` after response
validation and the first-request ceiling check, and from the development plan and review counts.
`verify-freeze` rebuilds that first request privately and checks its hash. The owner runs `prepare-sealed-review --cases SEALED_CASES
--private DIR` in the merged checkout to create `review-sheet-sealed.csv`. A score requires the completed review CSV passed as
`--review-sheet`. B derives its variants from the selected case list, so the case-list
manifests are unchanged. Scores use request cost across attempts, charging W when an attempt
reported no cost, and elapsed wall time including retries. The latency bar uses nearest-rank p90.
