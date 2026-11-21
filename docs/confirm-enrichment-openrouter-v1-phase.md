# Confirm enrichment through OpenRouter v1: phase gate

Status: **phase gate, 21 November 2026, under blind review (section 13); awaiting the owner's approval
before any production code. No app egress and no evaluation call until the steps of section 10 say
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
| Food contract | **13** | CE1.7: the next free number when the phase starts. 11 is in use (`CanonicalFoodProjection.foodContractVersion`, `CanonicalFoodArchive.swift:44`); 12 is reserved by [assistant-pasted estimates v1](assistant-pasted-estimates-v1-proposal.md) section 7. Section 2.7 says how 12 is treated. |
| Store | `FoodLedgerGRDBStore.schemaVersion` 13, migration `v13_confirm_enrichment`, metadata `food-ledger-v13` | Metadata only, as `v11_label_photo_estimate` (`FoodLedgerMigrations.swift:76`). |
| Daily food export | **`food_daily_schema_version` 7** | CE1.7: 5 is in use; 4 and 6 are reserved by assistant estimates and the union rule. |
| Provenance kind | `ProvenanceSourceKind.openRouterEstimate`, raw value `openrouter_estimate` | CE1.7. |
| Captures | `confirm-details-capture-v1` (A), `confirm-nutrient-capture-v1` (B), `confirm-nutrient-choices-v1` (B, per saved version) | CE1.4a, CE1.7. |
| Cache file | `confirm-enrichment-cache-v1.json` | CE1.2. |
| Day record | `confirm-enrichment-day-v1.json` | CE1.3 names the record; the gate makes it a file beside the cache. |
| Versions | contract `confirm-enrichment-openrouter-v1`; routes `confirm-details-route-v1`, `confirm-nutrient-route-v1`; prompts `confirm-details-prompt-v1`, `confirm-nutrient-prompt-v1` | CE1.4, CE1.5. Each route version fixes model, provider, endpoint, `max_tokens`, reasoning limit and the catalogue prices W is computed from. |
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
time received, `locale` the candidate evidence's locale, `originalPayload` `.text` of the canonical
payload, `byteHash` its SHA-256 (citation sites in section 2.4a). Payload keys: `schema`, `contract`, `route`, `prompt`, `model`,
`provider`, `endpoint` (the route version's constant, section 3.3 item 3), `generation_id` (read from
the response), `request_body` (the exact body as a UTF-8 string, no key), `response` (verbatim, at most
50,000 bytes), `response_sha256`, `answers` (per asked fact, sorted: `fact`, `choice`, `confidence`),
`threshold` (`"0.85"`), `applied` (sorted fact keys pre-filled).

### 2.3 `confirm-nutrient-capture-v1` (B)

As 2.2, with `captureMethod` `Values estimated through OpenRouter`, the response at most 100,000
bytes, no `answers`, `threshold` or `applied`, and `rows`: one item per response row in response
order with `nutrient`, `value` (the decimal as received, as a string), `unit` and `result`. `result` is
`kept` or a code that depends only on the stored request and response: `unknown_nutrient`, `unit`,
`value`, `impossible_value`, `exceeds_parent`, `duplicate_nutrient`, or `energy_mismatch` computed
against the request's known values and the reply alone. Drops that depend on a later choice on
Confirm are not in the capture: they are in the choices item (2.4). Committed only with a Log whose
saved version keeps at least one B value.

### 2.4 `confirm-nutrient-choices-v1` (B, per saved version)

`CaptureEvidence`, kind `.labelText`, `captureMethod` `Estimated values left out by you`,
`captureMethodVersion` `confirm-nutrient-choices-v1`. Payload keys: `schema`, `resolution_version_id`,
`capture_sha256`, `left_out` (sorted keys the owner left out), `layer_dropped` (sorted keys dropped
because the chosen #464 or off-label layer fills them, CE1 section 5a, `label_estimate`), and
`merge_energy_dropped` (sorted estimated keys dropped by the energy check run after that layer's
values are merged, `energy_mismatch`). Nutrient keys only, no values. One per saved version that cites
a B capture.

Verification (CE1.7) re-runs the row checks on the stored response against the stored request, giving
the capture's `rows`; then removes `layer_dropped`, checks those keys are exactly the B keys the saved
version's label layer fills, re-runs the energy check on the merge of the saved version's known values,
its label layer and the kept B rows, giving `merge_energy_dropped`; then requires each saved B value
to equal a kept row not in `left_out`. Any mismatch shows "Evidence not available" and changes nothing.

### 2.4a Where each item is cited

Evidence is reached through the decision's embedded candidate, as estimates v2's leave-out item is
(`FoodConfirmation.swift:856-864`). Each save that writes a resolution version with CE1 evidence writes
a new candidate decision whose candidate equals the bound candidate except its evidence IDs, which
are the bound candidate's own, then any estimates v2 leave-out item, then in this order the A capture,
the B capture and that version's choices item. So the choices item, which is per saved version, is
always cited by that version's own decision, and its `resolution_version_id` must equal the version
that cites the decision (verification refuses otherwise).

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
                 "received_at": <RFC 3339 UTC> } ] }
```

Exactly CE1.2's value: response bytes, response hash, model, provider, cost and time received. **No
request body, key, amount, description field or other date.** `subject_sha256` is the SHA-256 of the
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
the cached response and takes `endpoint` from the route version. Test G1 proves that capture is
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
  | `confirm-details-route-v1` | 4,000 tokens | 400 tokens (sent as `max_tokens` if System One accepts it; otherwise used for W only, and the first-request stop of section 9 records which) | none |
  | `confirm-nutrient-route-v1` | 6,000 tokens | 1,200 (`max_tokens`, CE1.5) | 500 (CE1.5) |

  A request body longer in UTF-8 bytes than its prompt ceiling in tokens is refused before sending
  (bytes bound tokens from above), with no note, as the deny gate is. If the day's prices make W
  exceed the per-request cap, the route check fails as route unavailable for that day and the part
  sends nothing.
- **Whole-request cap.** An attempt may start only when the request's charged total plus W is at most
  $0.01 (A) or $0.02 (B), checked before every attempt, so one request, retries included, never counts
  or spends more than the approved per-request figure. An attempt with no reported cost is charged W.
  If W is so close to the cap that no retry fits, the request simply makes fewer attempts.
- **Day cap.** A request may start only when `requests` is below 100 and `settled_microusd` plus the
  open requests' charges plus W is at most 500,000. A request counts once, at its first reservation.
- **Reservations** are tagged with a `request_id` from an injected generator, so reconcile and release
  are idempotent per request, across a day change too. A reported cost above the per-request cap adds
  the part to `paused` for the rest of the local day.
- **Fail closed.** A corrupt or unknown ledger file is replaced at once with a record for today whose
  `requests` is 100, so nothing more is sent that local day, after a relaunch too, and the next local day
  starts clean.
- **Day change.** A new local day (from the injected clock and time zone) starts a new record. Open
  requests of the previous day are closed at their charged amounts, which stay counted in the day they
  were sent; a later reconcile or release for such a `request_id` is ignored.

The `ConfirmEnrichmentSpendLedger` port only loads and stores a typed `Day`; its shared suite covers
persistence only. Separate from `label-ai-spend-day-v1`, which is unchanged.

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
  `migrationIdentifiers` (`:335-340`) for contract 13 is `food-ledger-v1` to `food-ledger-v11` plus
  `food-ledger-v13`, never `v12`. Assistant-pasted estimates, unbuilt, takes the next free number when
  its phase starts, as its section 7 already allows; PR 1 adds a dated note there.
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
| Application | new `ConfirmEnrichmentPolicy` | Eligibility (CE1.4, CE1.5), subjects, the on-device deny gate (CE1 section 7), the prompt ceiling refusal (section 2.6), typed request bodies (section 3.2). CE-D5 reads `hasCatalogueFacts` from `PersonalFoodDescriptionFields`, which the read port sets from the entry's `identityFacts != nil` (`PersonalFoodDatabaseCandidates.swift:114`), so A is skipped for a reviewed entry. |
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
  `CanonicalEncoding`. The port receives those exact bytes; the adapter sends them unchanged and adds
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
   sites, joins `openrouter_exempt` (`:459`) as a reviewed exemption. No application file holds an
   OpenRouter URL: the capture's `endpoint` is passed in from the route version at the root.
4. The application file-and-network ban (`check_personal_database_search_edges`, `:619-622`, today
   `PersonalFoodDatabase*.swift` and `ApprovedEstimate*.swift` only) extends to `ConfirmEnrichment*.swift`,
   `ConfirmDetails*.swift`, `ConfirmNutrient*.swift` and `OpenRouterEstimate*.swift`, and also bans
   `CryptoKit` and `Date()` there (`FoodLedgerApplication` may import `CryptoKit` elsewhere, `:707`).
5. `Tools/ConfirmEnrichmentEval` follows the `PastedLabelAITextEval` rules (`:726-772`): a pure core
   with no URL loading, one live-transport file, and no network destination other than the 11.1a ones.
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
| `ConfirmEnrichmentSpendLedger` | `load() -> Day?`, `store(_ day: Day)` | file; in-memory |
| `PersonalFoodDatabaseEntryReading` | `descriptionFields(recordID:) -> PersonalFoodDescriptionFields?` | `ActiveReleaseEntryReader`; in-memory |
| `ConfirmEnrichmentDelaying` | `wait(seconds:) async throws` (cancellable), for the 1.5 s debounce and backoff | the app's task sleep; scripted |
| `ConfirmEnrichmentElapsedTiming` | `now() -> Duration` (monotonic), for the 60 s whole-call and 30 s attempt deadlines | the app's continuous clock; scripted |
| `ConfirmEnrichmentJittering` | `fraction() -> Double` in 0 to 1, for backoff jitter | system random; seeded |
| `LedgerClock`, `LedgerIDGenerating` (existing, `LedgerCommands.swift:488, 492`) and a `TimeZone` value | wall time for the local day, `received_at` and the 30-day expiry; `request_id` and evidence IDs | existing |
| Lifecycle input | `ConfirmEnrichmentSession.appBecameInactive()` and `appBecameActive()`, called by the view model from the scene phase | none (an action, not a port) |
| `FoodWebKeyStoring` (existing, `FoodWebDiscovery.swift:49`) | read by the adapters on every attempt | Keychain; test |
| `OpenRouterEgressPermitting` (existing, O1) | asked by the session before reserving and by each adapter before each attempt | `OpenRouterConsentPreference` composed with `ConfirmEnrichmentPreference`; tool-local gate |

`ConfirmEnrichmentAttemptResult` is `.notSent(reason)` (refused by the gate, no key, cancelled before
sending), `.sent(status, responseBytes, reportedCost, retryAfter, generationID)` or `.transportFailed
(class)` after sending. The session also takes the key state (`OpenRouterKeyState`, O1) as an input:
nothing starts unless it is `valid` in this session (CE1.1 rule 5). A key replaced while OpenRouter was
off is never sent (O1 test 2), because the adapter reads the key per attempt and the session reads the
key state per request. Framework, URL and HTTP types never cross a port.

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
  even with both switches on.
- **The Debug scripted journey (PR 2).** A `ScriptedConfirmEnrichmentGate` in `FoodConfirmEnrichment`,
  wholly inside `#if DEBUG`, permits the four uses only when both switches are on. The root builds it
  only together with the scripted adapters, never with a live adapter, when the Debug launch argument
  `-ConfirmEnrichmentRoute scripted` is present. The enrichment switch is set for that journey by a
  Debug-only seed argument, `-confirmEnrichment.enabled.v1 on`, resolved like O1's
  `OpenRouterConsentSeed` (writes only with `debugBuild` true); in Release the argument domain is never
  read, as O1 requires. A boundary self-test fails if the scripted gate's name appears outside an
  `#if DEBUG` block, or in the same root branch as a live adapter.
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
  `byteHash`, and the recording transport sees zero requests. With the file cache too.
- **G2 Cache content.** The decoded key set equals 2.5's; a request with a sentinel description,
  amount and key leaves none of the three strings in the file bytes; an extra key, unknown schema or
  more than 500 entries discards the file; an entry older than 30 days misses; a hit whose bytes fail
  the checks or whose hash differs misses and is dropped.
- **G3 Spend.** Pure `ConfirmEnrichmentSpendPolicy` tests: the 101st request of a day and a request
  that would pass $0.50 do not start, and the gate is not asked; no attempt starts when charged plus W
  would pass $0.01 (A) or $0.02 (B); an unreported cost is charged W; reconcile and release are
  idempotent per `request_id`, across a day change; a reported cost above the cap pauses that part
  only; a corrupt ledger refuses until the next local day.
- **G4 Numbers.** An archive labelled 12 is refused at each of the three range sites; 11 and 13 are
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
- **G7 Boundaries.** Each of the six items of section 3.3 fails on its self-test fixture.
- **G8 Layers on reopen.** A B entry with the #464 layer, chosen before and after B answers: save,
  reopen and edit verify; `layer_dropped` and `merge_energy_dropped` are rebuilt exactly; altering
  either list shows "Evidence not available".
- **G9 Your foods.** Through both builders, each saved `openrouter_estimate` key becomes
  `.unknown(not_declared)` and the row is classified by its real source.
- **G10 Consent records.** Before PR 5 the four uses are nil and refused; after it, each in-force use
  maps to exactly one row and one policy entry.
- **G11 Evaluation tool.** Its only network calls go to the 11.1a destinations; it refuses to send
  without the 11.1a paragraph on `origin/main`; it stops at the spend limits.
- **G12 Readers and citations.** The pasted label, label photo and approved-estimate `.labelText`
  readers ignore the three CE1 method versions, and the CE1 readers ignore every other version; an
  Open Food Facts entry with the #464 layer, an A capture, a B capture and a choices item passes
  `applies` on reopen and edit; a choices item whose `resolution_version_id` differs from the citing
  version fails verification; re-log and quick add drop all three ID kinds.
- **G13 Time.** Scripted delay, elapsed time, clock and jitter drive the debounce, the 60 s and 30 s
  deadlines, `Retry-After`, the day reset and the 30-day expiry; no new application file calls `Date()`.
- **G14 Route check.** Runs once per app session and local day, and again after a connection failure;
  a failed or refused check reserves and counts nothing; a day whose prices make W exceed the cap
  makes the part unavailable; a body over its prompt ceiling is refused before sending.
- **G15 Cache writes and Debug wiring.** A cancelled or late answer is never stored; an all-unknown A
  answer and an all-dropped B answer are stored and reused; the file and in-memory caches give the
  same results under `ConfirmEnrichmentCachePolicy`; the scripted gate cannot be reached in Release
  (boundary self-test of section 6).

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
  `origin/main` after a fetch (`git show origin/main:docs/privacy-and-egress.md`).

## 9. Evaluation before any release (CE1 section 12)

- **Data source, no new destination.** The tool makes no Open Food Facts request. Open Food Facts cases
  are read locally from a public Open Food Facts data export that the developer has downloaded outside
  the tool (it carries no user data, like the bundled source datasets), and composition rows from the
  app's bundled projections. The tool's only network calls are the 11.1a destinations (section 11,
  point 4).
- **Sets.** Development set: 60 Open Food Facts products (UK and Taiwan, packaged, complete declared
  panels, at least 8 fortified) and 40 bundled rows; a sealed set of the same size and mix. The owner
  checks the food details of the Open Food Facts cases on a review sheet before any A score counts.
  Manifests (case identifiers, barcodes or row identifiers, content hashes) are committed; product data
  and responses stay in the private folder.
- **Micronutrient floor.** The 10% of the UK reference intake in CE1 section 12 uses the reference
  intakes of Annex XIII of retained Regulation (EU) No 1169/2011, held as a constant table in the
  scorer only (the app gains no reference value). A key with no reference intake there uses no floor,
  which makes its bar stricter (section 11, point 6).
- **Run.** The tool sends exactly the app's request bytes through the `FoodConfirmEnrichment` adapters
  with a tool-local gate, under CE-T15 ($5 programme, $0.05 per call, in its own spend ledger before
  every call; at most 3 attempts with backoff honouring `Retry-After`). For B, known values are hidden
  per case as CE1 section 12 says.
- **First request stop.** The first A request checks that System One accepts the body and returns the
  CE1.4 shape. If it does not, the run stops: switching to `alpha/decisions` reopens CE-T1 and the 11.1
  row for the owner (CE1.4).
- **Order.** PR 4a commits the scorer, the bars as code, both manifests and the frozen configuration,
  and merges. Only then is the sealed set sent, once, by that configuration, and its report lands in
  PR 4b. A prompt change during development is a prompt version bump.
- **Outcome.** Counts, versions and hashes per bar in the repository. A missed bar stops release of
  that part; the other may ship alone. If A misses the wrong pre-fill bar at 0.85, the report gives the
  lowest threshold that passes and the owner chooses (CE-D3).
- **Release.** No build that can reach a route outside Debug goes anywhere until its part passes; then
  internal TestFlight only (CE-T13), after the owner's one combined device check of O1 and CE1.

## 10. PR split

Each PR has its own branch, a ledger row, the validation gates of `AGENTS.md`, a blind
`invariant-reviewer` and a general defect review at its head, and the owner's yes before merge.

| PR | Content | Egress |
|---|---|---|
| 1. Formats | Domain kinds, provenance and release constants, capture and choices types, row and energy checks with the parity test, the application response checks (which verification needs), the citation and skip rules of 2.4a, the four `OpenRouterUse` cases not in force with nil mappings, contract 13 floor and accepted set, store 13, export 7 writer and validators, verification on save and reopen, fixtures; dated notes in assistant-pasted estimates v1 and food daily export v2. Store 13 migrates every store on first open, so a downgrade past it is refused. No UI writes CE1 records yet. | None |
| 2. Confirm layer | Application policy, session, spend, retry and cache policies, ports and their suites; the `FoodConfirmEnrichment` target and product with the file cache and ledger, the scripted adapters and the Debug scripted gate (no live adapter); the Debug seed argument; boundary items 1, 2 and 4 and the scripted gate self-test; the Your food database read port and adapter; the suggestion layer, reducer, fill builder, Log requirement, re-log, quick add, re-resolution and reopen rules; presentation; scripted answers reachable only by a Debug launch argument; simulator journey with scripted answers. | None |
| 3. Adapters and tooling | The two adapters, route checker, routes file and transport; boundary items 3 and 5; `Tools/ConfirmEnrichmentEval` with its preflight; the section 11.1a paragraph. Not wired into the app. | Tooling only, after merge |
| 4a. Evaluation freeze | Development runs, review sheet outcome, scorer, bars as code, manifests, frozen configuration. | Tooling only |
| 4b. Sealed report | The single sealed run's report. | Tooling only |
| 5. Wiring | Composition root, Settings rows and switch, the uses in force for each part that passed, section 11.1 rows, 11.2 entry, O1 title and framing changes, Developer tools disclosure, journey QA; then the combined device check. | App, with both switches on |

PRs 1 to 3 can be reviewed and merged without any network call from the app.

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
   and "$0.02 per request" as whole-request totals across all attempts, enforced before each attempt
   (section 2.6), never as per-attempt figures. And the evaluation reads Open Food Facts data from a
   public export downloaded outside the tool, adding no destination to 11.1a; a fetch by the tool would
   need its own approved addition first. Both narrow; neither changes a term.
5. **Every store moves to 13.** CE1 section 14 speaks of refusing a downgrade "for a store that holds a
   B value". The store's migrations are per store, not per record, so the first build carrying PR 1
   migrates every store to 13 and refuses a downgrade past it for every store, as each earlier
   contract step did (`FoodLedgerMigrations.swift:76`, `FoodLedgerGRDBStore.swift:1248`). Archives and
   exports without CE1 content keep their bytes and labels, as CE1.7 says. So no build cut from `main`
   after PR 1 can be downgraded below it.
6. **Evaluation floor.** A micronutrient with no UK reference intake is scored with no floor, which is
   stricter than giving it one.

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
