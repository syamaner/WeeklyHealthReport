# Confirm enrichment through OpenRouter v1: phase gate

Status: **phase gate, 21 November 2026, draft for blind review (section 13); awaiting the owner's
approval before any production code. No app egress and no evaluation call until the steps of
section 10 say so.** Implements the approved contract
[Confirm enrichment through OpenRouter v1 (CE1)](confirm-enrichment-openrouter-v1.md) (PR 555;
decisions CE-D1 to CE-D5 and terms CE-T1 to CE-T15 approved 20 November 2026). Part of #549. Written
against `main` at `6897af0e`.

Everything in CE1 stands. This file fixes the numbers, names, closed formats, code sites, ports, tests
and PR split that CE1 left to the gate (CE1.7 "the phase gate pins the other required release and
evidence fields"; CE1.7 "the next free food contract when its phase starts"). It repeats no rule of
CE1. Where a refinement here narrows or places a CE1 rule, the CE1 section is cited; section 11 lists
the two points where the gate reads CE1 strictly and the owner sees the reading before approving.

## 1. Numbers and names allocated here

| Item | Value | Why |
|---|---|---|
| Food contract | **13** | CE1.7: the next free number when the phase starts. 11 is in use (`CanonicalFoodProjection.foodContractVersion`, `CanonicalFoodArchive.swift:44`), 12 is reserved by [assistant-pasted estimates v1](assistant-pasted-estimates-v1-proposal.md) section 7 (as renumbered by the label photo phase gate). See section 2.7 for how 12 is treated. |
| Store | `FoodLedgerGRDBStore.schemaVersion` 13, migration `v13_confirm_enrichment`, metadata `food-ledger-v13` | Metadata only, as `v11_label_photo_estimate` (`FoodLedgerMigrations.swift:76`). |
| Daily food export | **`food_daily_schema_version` 7** | CE1.7: 5 is in use, 4 and 6 are reserved by assistant estimates and the union rule. |
| Provenance kind | `ProvenanceSourceKind.openRouterEstimate`, raw value `openrouter_estimate` | CE1.7. |
| Captures | `confirm-details-capture-v1` (A), `confirm-nutrient-capture-v1` (B), `confirm-nutrient-choices-v1` (B, per saved version) | CE1.4a, CE1.7. |
| Cache file | `confirm-enrichment-cache-v1.json` | CE1.2. |
| Day record | `confirm-enrichment-day-v1.json` | CE1.3 names the record `confirm-enrichment-day-v1`; this gate makes it a file beside the cache. |
| Contract, route and prompt versions | `confirm-enrichment-openrouter-v1`; `confirm-details-route-v1`, `confirm-nutrient-route-v1`; `confirm-details-prompt-v1`, `confirm-nutrient-prompt-v1` | CE1.4, CE1.5, CE1.7. The two route versions are new names here; each fixes model, provider, endpoint, `max_tokens` and reasoning limit. |
| Response schema | `confirm-nutrient-estimate-v1` | CE1.5. |
| `OpenRouterUse` cases | `confirmEnrichmentDetails`, `confirmEnrichmentNutrients`, `confirmEnrichmentDetailsCatalogueCheck`, `confirmEnrichmentNutrientsCatalogueCheck` | CE1 section 9. Added not in force (PR 3); put in force only in the wiring PR (section 10). |
| Feature switch | `confirmEnrichment.enabled.v1` | CE1 section 9. |
| Frozen reason | `Food details suggested by Jev` | CE1.4a. |
| Log requirement | `FoodLogRequirement.onlyEstimatedByOpenRouter` | CE1.6 rule 7. |
| Quick add ineligibility | `QuickAddIneligibility.openRouterEstimate` | CE1.7a, a new case beside `approvedEstimate` (`QuickAdd.swift:26`). |
| Package target | `FoodConfirmEnrichment` | CE1 section 15. |
| Evaluation tool | `Tools/ConfirmEnrichmentEval` (SwiftPM package, core library plus executable), private folder `~/…/confirm-enrichment-eval/` outside the repository | CE-T15, section 9 here. |

## 2. Closed formats

All JSON here is canonical (sorted keys, no insignificant whitespace) through the existing
`CanonicalEncoding` port (`LedgerCommands.swift:480`), hashed through `Digesting` (`:484`). Every
format has a closed key set: an unknown key, a missing required key or a wrong type is a decode
failure. Money is an integer count of micro-dollars (`cost_microusd`), never a float.

### 2.1 `openrouter_estimate` provenance (CE1.7, fields pinned)

A B value is a `NutrientEntry` value inside `.augmented` only, with one `NutrientProvenance`:

| Field | Value |
|---|---|
| `sourceKind` | `openrouter_estimate` |
| `sourceID` | `confirm-enrichment-openrouter` |
| `sourceReleaseID` | `openrouter-estimate:sha256:<capture byteHash hex>` |
| `recordID` | `ore:<capture evidence ID>` |
| `evidenceID` | the `confirm-nutrient-capture-v1` evidence ID |
| `capturedAt` | the capture's `capturedAt` (the time the answer was received) |
| `responseHash` | the capture's `byteHash` |
| `manifestReference` | `confirm-nutrient-capture-v1#<nutrient key>` |
| `decisionID`, `assertionID` | nil |
| `transforms` | empty |

A new `OpenRouterEstimateProvenance.isValid(_:key:)` beside `ApprovedEstimateProvenance.isValid`
(`Nutrition.swift`) checks all of these, and `NutrientEntry` validation refuses the kind in `.measured`
or `.bounded`. Tier is implied (`low`); `NutrientProvenance` gains no field.

The per-capture `SourceRelease` committed with the log, every field truthful:

| Field | Value |
|---|---|
| `sourceReleaseID` | as above |
| `sourceID` | `confirm-enrichment-openrouter` |
| `releasedAt` | the capture's `capturedAt` |
| `artifactHash`, `manifestHash` | the capture's `byteHash` |
| `schemaVersion` | `confirm-nutrient-capture-v1` |
| `pipelineVersion` | the route version, `confirm-nutrient-route-v1` |
| `licence` | `Model output; no licence applies` |
| `attribution` | `Estimated through OpenRouter` (the model is in the capture, never in a constant) |

### 2.2 `confirm-details-capture-v1` (A)

`CaptureEvidence`, kind `.labelText`, `captureMethod` `Food details suggested by Jev`,
`captureMethodVersion` `confirm-details-capture-v1`, `capturedAt` the time received, `locale` the
candidate evidence's locale, `originalPayload` `.text` of the canonical payload, `byteHash` its SHA-256.
Payload keys: `schema` (`confirm-details-capture-v1`), `contract`, `route`, `prompt`, `model`,
`provider`, `endpoint` (from the route version), `generation_id` (read from the response),
`request_body` (the exact body bytes as a UTF-8 string, no key), `response` (verbatim, at most 50,000
bytes), `response_sha256`, `answers` (per asked fact, sorted: `fact`, `choice`, `confidence`),
`threshold` (`0.85`, as a decimal string), `applied` (sorted fact keys pre-filled). Cited last in the
candidate decision's evidence IDs (CE1.4a).

### 2.3 `confirm-nutrient-capture-v1` (B)

As 2.2, with `captureMethod` `Values estimated through OpenRouter`, the response at most 100,000
bytes, no `answers`, `threshold` or `applied`, and `rows`: one item per response row in response
order, `nutrient`, `value` (decimal string as received), `unit`, `result` (`kept` or a CE1.6 rule 2 or
3 code: `unknown_nutrient`, `unit`, `value`, `impossible_value`, `exceeds_parent`,
`duplicate_nutrient`, `energy_mismatch`, `label_estimate`). Committed only with a Log whose saved
version keeps at least one B value.

### 2.4 `confirm-nutrient-choices-v1` (B, per saved version)

`CaptureEvidence`, kind `.labelText`, `captureMethod` `Estimated values left out by you`,
`captureMethodVersion` `confirm-nutrient-choices-v1`. Payload keys: `schema`, `resolution_version_id`,
`capture_sha256`, `left_out` (sorted nutrient keys, possibly empty). One per saved version that cites a
B capture; nutrient keys only, no values.

### 2.5 `confirm-enrichment-cache-v1.json` (CE1.2: the approved value only)

```text
{ "schema": "confirm-enrichment-cache-v1",
  "entries": [ { "subject_sha256": <64 hex>, "part": "details" | "nutrients",
                 "response": <base64 of the validated response bytes>, "response_sha256": <64 hex>,
                 "model": <slug>, "provider": <name>, "cost_microusd": <int or null>,
                 "received_at": <RFC 3339 UTC> } ] }
```

Exactly CE1.2's value: response bytes, response hash, model, provider, cost, time received. **No
request body, no key, no amount, no description field and no other date.** `subject_sha256` is the
SHA-256 of the canonical subject of CE1.4 (A) or CE1.5 (B), whose versions are inside it. At most 500
entries, ordered by `received_at`, oldest dropped first; an entry older than 30 days is ignored and
dropped at the next write. Stored in the protected (`NSFileProtectionComplete`), backup-excluded app
data directory. A corrupt, unknown-schema or over-size file is deleted whole and rebuilt empty, and a
read failure is a cache miss, never a reason to send twice (the once-per-subject rule still holds).
On a hit the response bytes are re-checked by the same response and row checks as a live answer
(section 3.2), and a mismatch of `response_sha256` is a miss and drops the entry.

**Rebuild equals live.** The request body is not cached. A capture made from a hit rebuilds the body
from the live Confirm inputs through the same pure builder (section 3.2) and holds `generation_id`
from the cached response and `endpoint` from the route version. Test G1 (section 7) proves the
capture from a hit is byte-identical, `byteHash` included, to the capture of a live answer for the
same subject.

### 2.6 `confirm-enrichment-day-v1.json` (CE1.3)

```text
{ "schema": "confirm-enrichment-day-v1", "local_day": "YYYY-MM-DD", "requests": <int>,
  "cost_microusd": <int>, "reserved_microusd": <int>, "paused": ["details" | "nutrients"] }
```

`local_day` is the device's local calendar day from the injected clock and time zone; a new day resets
the record. A request counts once when its first attempt is reserved; each attempt reserves W
(A 10,000, B 20,000 micro-dollars) before it is sent and is reconciled to the reported cost, or kept
at W when none is reported. A reported cost above the per-request cap adds the part to `paused`. A
corrupt or unknown file counts as the cap reached until the next local day, then is rewritten: unlike
the cache, a broken ledger fails closed. Separate from `label-ai-spend-day-v1`, which is unchanged.

### 2.7 Food contract 13 and the store

- **Floor rule.** `CanonicalFoodProjection.minimumContractVersion` returns 13, checked first, for a
  record set holding `openrouter_estimate` provenance anywhere a nutrient set is stored (resolution
  versions, candidate decisions, conflict candidates) or evidence whose `captureMethodVersion` is
  `confirm-details-capture-v1`, `confirm-nutrient-capture-v1` or `confirm-nutrient-choices-v1`. The
  contract 11 and earlier rules are left exactly as they are.
- **Contract 12 is never written or read.** No build writes 12 and the store's migrations run in
  order, so after store 13 exists a later `v12` migration cannot run. The binary's accepted set becomes
  `1...11` and `13` (not the range `1...13`, which `CanonicalFoodArchive.init` uses today and would
  admit 12); an archive labelled 12 is refused with `unsupportedFoodContract(12)`. Assistant-pasted
  estimates, unbuilt, takes the next free number when its phase starts, as its section 7 already
  allows; this PR adds a dated note there (section 11, point 1).
- **Store.** `v13_confirm_enrichment` changes metadata only. A store at 11 opens and migrates to 13;
  an older binary refuses a store at 13 closed; a store or archive with no CE1 record keeps its bytes
  and, for archives, its contract label.

### 2.8 Daily food export 7

- Writer (`FoodDailyExport.swift:589-596`): schema 7 when any entry holds an `openrouter_estimate`
  value, checked before the schema 5, 3 and 2 choices, which are otherwise unchanged byte for byte.
- `FoodDailyExportShape`: `acceptedSummaryVersions[7]` = `food-intake-summary-v6`;
  `estimateSourceTypes(schema: 7)` = schema 5's set; the schema 7 validator row of CE1.7 (at least one
  `openrouter_estimate` value; approved and photo estimates optional; for the new origin,
  `estimate_quality` `low` and `estimate_model`, `estimate_contract`, `estimate_response_sha256`
  required, the three estimates v2 tokens absent; `source_release_id` the constant). Schemas 1, 2, 3
  and 5 reject the three new fields and the origin.
- Version 7 is built to admit exactly what version 5 admits plus B. It does not admit assistant
  estimate fields; see section 11, point 2.
- The `notes` sentence of CE1.7, verbatim.

## 3. Responsibilities and dependency direction

### 3.1 Sites

| Layer | Site | Change |
|---|---|---|
| Domain | `ProvenanceSourceKind`, `NutrientEntry` validation, new `OpenRouterEstimateProvenance` | Section 2.1. |
| Domain | new `ConfirmEnrichmentCapture` (payload types of 2.2 to 2.4) | Typed, `Codable`, closed keys; a `typed(_ evidence:)` reader that gives nil for any other method version. |
| Domain | new `ConfirmNutrientRowCheck`, `EstimateEnergyCheck` | CE1.6 rules 2 and 3, pure, own constants. |
| Domain | `IdentityFacts` closed values (I1.1) | Reused for A's choice lists; `fortified` is not a member of A's list type, so it cannot be built. |
| Application | new `ConfirmEnrichmentPolicy` | Eligibility (CE1.4, CE1.5), subjects, the on-device deny gate (CE1 section 7), and typed request bodies (section 3.2). |
| Application | new `ConfirmEnrichmentSession` | The CE1.1 state machine (debounce, once per subject, second subject, `Ask again`, cancellation, foreground only) over an injected delay port and clock. |
| Application | new `ConfirmDetailsResponseCheck`, `ConfirmNutrientResponseCheck` | CE1.4 and CE1.6 rule 1 shape checks over `Data`; used live, on a cache hit and on reopen. |
| Application | `FoodConfirmationState`, `FoodConfirmationAction`, `reduce` (`FoodConfirmation.swift:169, 335, 372`) | The transient suggestion layer (CE1 section 5a, never encoded), effective identity versus fill-test baseline (CE1.4a), actions to apply and clear A, apply and clear B rows, Leave out and Put back. |
| Application | `FoodDetailsFillPolicy`, `PackagedAsSoldPolicy.offers`, `pendingDifferences`, `savesEstimate`, `decisionRecord` | CE1.4a. |
| Application | `FoodConfirmationService.save` and verification | CE1.6 rule 4 re-check, merge order of section 5a, capture and choices evidence, CE1.7 verification on save and reopen. |
| Application | `FoodLogPolicy` (`FoodLogRequirement`), `QuickAdd`, `isStoredFill`, `ApprovedEstimateConfirmation.matchesExceptHiddenEstimates` (`:63`) beside new `matchesExceptOpenRouterEstimates` | CE1.6 rule 7, CE1.7a. |
| Application | `OpenFoodFactsEstimateSource.applies` (`OpenFoodFactsEstimateSource.swift:18`), `LabelEstimateLayer`, approved-estimate manifest and leave-out paths | CE1 section 5a, reopen and edit with other layers. |
| Application | Your foods builders (`CoFIDGenericFoodSearch`, `BarcodeCapture` callers) | Rebuild saved `openrouter_estimate` keys as `.unknown` (`not_declared`) (CE1 section 2). |
| Application | `CanonicalFoodProjection`, `FoodDailyExport`, `FoodDailyExportShape` | Sections 2.7 and 2.8. |
| Application | `OpenRouterUse` (`OpenRouterEgress.swift`) | Four cases with `isInForce`, `policyEntry` and `egressRow` (section 6). |
| Application | ports of section 4 | New. |
| Infrastructure | `FoodConfirmEnrichment` target: `OpenRouterJevFoodDetailsAdapter`, `OpenRouterNutrientEstimateAdapter`, `ConfirmEnrichmentRouteChecker` (one per route), `ConfirmEnrichmentTransport` (the only file that may load URLs), `FileConfirmEnrichmentCache`, `FileConfirmEnrichmentDayLedger` | HTTP, Authorization header, retries (CE1.3), size limits, the gate at every attempt; no content rules. |
| Infrastructure | `FoodLedgerPersonalDatabase`: `ActiveReleaseEntryReader` | The `PersonalFoodDatabaseEntryReading` adapter (CE1 section 7), local only. |
| Infrastructure | `FoodLedgerGRDB` | Migration 13 and open check. |
| Presentation | `FoodLedgerPresentation`: `FoodConfirmationView`, `FoodDetailsSheet`, new `ConfirmEnrichmentText` | The details line, `est.` tag, Leave out and Put back, loading row with Stop, the one note, VoiceOver labels; every string frozen in `ConfirmEnrichmentText`. |
| App target | Settings › OpenRouter, `ConfirmEnrichmentPreference`, Developer tools "Last Confirm enrichment", `FoodLedgerCompositionRoot` | CE1 sections 8 and 9; the only app importer of `FoodConfirmEnrichment`. |
| Tooling | `Tools/ConfirmEnrichmentEval` | Section 9. |
| Scripts | `check-boundaries.sh` | Section 3.3. |

### 3.2 Where the request and response bytes are made

CE1 section 15 places "request and response checks" in the adapters. The gate places them one layer
lower, because the same checks must run on a cache hit and on reopen (CE1.2, CE1.7), where no adapter
is involved:

- The **request body** is a typed, `Encodable` value built by `ConfirmEnrichmentPolicy` from the
  live Confirm inputs (description of CE1 section 7, questions or instruction and schema, provider
  block from the route version), and encoded once through `CanonicalEncoding`. The port receives
  those exact bytes; the adapter sends them unchanged and adds only the Authorization header. One
  golden per part and route pins the bytes (CE1 test 2), and a recording-transport test pins that the
  wire bytes equal the bytes the capture holds.
- The **response checks** (size, one choice, `finish_reason`, refusal, strict schema, `schema` and
  `basis`, model and provider match, A's answer keys and ranges) are pure application functions over
  the response bytes; the **row checks** and energy check are domain. The adapter checks only HTTP
  status, the byte limit while reading, and the retry classification.

So no URL, header or transport type reaches the application, and no content rule lives in
infrastructure.

### 3.3 Dependency direction and boundary checks

Domain ← application ← infrastructure and presentation; the app target composes. `check-boundaries.sh`
gains:

1. `FoodConfirmEnrichment` may import `FoodLedgerApplication`, `FoodLedgerDomain` and `Foundation`
   only; URL loading (`URLSession` and the rest of `url_loading_pattern`) only in
   `ConfirmEnrichmentTransport.swift`.
2. The only importers of `FoodConfirmEnrichment` are `FoodLedgerCompositionRoot.swift`, its own test
   target and `Tools/ConfirmEnrichmentEval`; any other importer fails (self-test fixture included).
3. `openrouter_request_sites` gains the two adapters and the route checker file; each must reference
   `OpenRouterEgressPermitting`. No new exemption.
4. Domain and application stay free of `URLSession`, `FileManager`, clocks and hashing (existing rules
   cover the new files).
5. The energy check parity test lives in a test target depending on `FoodLedgerDomain` and
   `NutritionLabelParsing` (`FoodLabelPhotoReadingTests`), allowed by the existing rule at line 82.

## 4. Ports

Each is consumer-owned, one purpose, and passes a shared contract suite in `FoodLedgerTestSupport`
run by every implementation (CE1 test 12).

| Port (application) | Shape | Implementations |
|---|---|---|
| `FoodDetailsSuggesting` | `suggest(_ request: ConfirmDetailsWireRequest) async -> ConfirmDetailsWireOutcome` | `OpenRouterJevFoodDetailsAdapter`; `ScriptedFoodDetailsSuggesting` (test support, Debug journeys) |
| `NutrientEstimateSuggesting` | `suggest(_ request: ConfirmNutrientWireRequest) async -> ConfirmNutrientWireOutcome` | `OpenRouterNutrientEstimateAdapter`; `ScriptedNutrientEstimateSuggesting` |
| `ConfirmEnrichmentRouteChecking` | `check(_ part: ConfirmEnrichmentPart) async -> RouteCheckOutcome` | `ConfirmEnrichmentRouteChecker`; scripted |
| `ConfirmEnrichmentCaching` | `answer(for subject: SHA256Digest, part:) -> CachedAnswer?`, `store(_:)`, `clear()` | file; in-memory |
| `ConfirmEnrichmentSpendLedger` | `reserve(part:worstCase:) -> Reservation?`, `reconcile(_:reportedCost:)`, `today() -> DaySummary` | file; in-memory |
| `PersonalFoodDatabaseEntryReading` | `descriptionFields(for recordID:) -> PersonalFoodDescriptionFields?` | `ActiveReleaseEntryReader`; in-memory |
| `ConfirmEnrichmentDelaying` | `wait(_ seconds: Double) async throws` (cancellable) | app's task sleep; scripted |
| `OpenRouterEgressPermitting` | existing (O1) | `OpenRouterConsentPreference` composed with `ConfirmEnrichmentPreference` for the four uses; tool-local gate |

A wire outcome is `.answered(responseBytes, model, provider, generationID, reportedCost, attempts)`,
`.failed(reason)` or `.notPermitted`; framework, URL and HTTP types never cross a port. No generic AI
port, repository or protocol per method.

## 5. Invariants (each with the test that holds it)

1. With OpenRouter off, enrichment off, no validated key, the app in the background, or a Confirm
   opened by re-log or quick add, zero requests reach the transport (CE1 tests 3 and 16; G5).
2. A known value or fact is never asked or replaced, checked three times (CE1.6 rule 4; CE1 tests 1, 7).
3. Fortified is never pre-filled: A's choice type cannot express it (CE1 test 5).
4. A B value is `.augmented`, `openrouter_estimate`, tier `low`, with the provenance of 2.1, and never
   a log's only nutrition (CE1 tests 7, 15).
5. Nothing is stored without Log; captures only with a Log that uses them (CE1 test 7).
6. Caps never exceeded, unreported cost counted as W, a broken ledger fails closed (CE1 test 10; G3).
7. The cache holds exactly CE1.2's value, never a request body, key, amount or description (G1, G2).
8. A capture from a cache hit equals the capture from a live answer for the same subject (G1).
9. A record or archive with no CE1 evidence or provenance keeps its contract and bytes (CE1 test 8).
10. Contract 12 is refused; schema 7 is written only for a day holding a B value (G4; CE1 test 9).

## 6. Consent gating through `OpenRouterEgressPermitting`

- Every request site (each attempt of both adapters, both catalogue checks) asks
  `permits(use)` immediately before sending, as O1.2 requires; a refusal returns `.notPermitted`
  before any reservation is taken or released as O1 test 2 describes for label photo, is never
  retried or slept on, and shows nothing on automatic Confirm (CE1 section 6) and O1's blocked row on
  the `Ask again` row.
- The app's gate permits a Confirm use only when the use `isInForce`, the OpenRouter switch is on and
  `confirmEnrichment.enabled.v1` is true. The key-validated check is the session's own (CE1.1 rule 5),
  made before the session asks to send; enrichment never validates a key.
- Mapping (O1 test 8): `confirmEnrichmentDetails` and `confirmEnrichmentDetailsCatalogueCheck` map to
  the Jev row; the two nutrient uses to the nutrient row; each `egressRow` is the contract link
  `confirm-enrichment-openrouter-v1.md` plus the row's destination cell prefix (`OpenRouter System One`
  or `OpenRouter and its one allow-listed model endpoint for nutrient estimates`), so each use maps to
  exactly one row. `policyEntry` is `Confirm suggestions.` for all four. O1 test 8's matcher gains the
  destination-prefix form; the existing uses keep matching by link alone.
- From PR 3 to the wiring PR the four cases exist with `isInForce` false, so the app's gate refuses
  them even with both switches on, as it does the pasted label text uses today.

## 7. Contract tests

CE1 section 15's seventeen tests are adopted as written. The gate adds:

- **G1 Rebuild equals live.** For A and for B: run a live scripted answer, save the capture; clear the
  in-memory session, reopen Confirm for the same subject with the cache holding the entry; the capture
  built from the hit has payload bytes and `byteHash` identical to the live one, and the recording
  transport saw zero requests on the second pass. Also with the file cache.
- **G2 Cache content.** The cache file's decoded key set equals section 2.5's; a fixture whose request
  carries a sentinel description, amount and key leaves none of the three strings anywhere in the file
  bytes; a file with an extra key, an unknown schema or more than 500 entries is discarded whole; an
  entry older than 30 days is a miss; a hit whose bytes fail the response checks, or whose hash
  differs, is a miss and the entry is dropped.
- **G3 Ledger.** The 101st request of a day and a request that would pass $0.50 are refused before the
  gate is asked; a corrupt ledger refuses every request until the next local day; a day change resets;
  a reported cost above the per-request cap pauses only that part.
- **G4 Numbers.** Archives labelled 12 are refused; 11 and 13 accepted; a store at 11 migrates to 13
  with only metadata changed; the provenance and release fields of 2.1 are each required in their
  exact form (one test per field, mutation gives "Evidence not available").
- **G5 Gate.** With a recording gate, every attempt of each adapter and each catalogue check records
  its own use, never another; with the use not in force, both switches on, zero transport calls; a
  refusal on attempt 2 ends with exactly one send, as O1 test 2.
- **G6 Wire bytes.** The bytes the transport records equal the capture's `request_body` and the
  committed golden; the Authorization header holds the key and no body byte does; the provider block
  equals the route version's.
- **G7 Boundaries.** The four `check-boundaries.sh` additions of section 3.3 each fail on a self-test
  fixture.

Fixtures are synthetic, under `docs/fixtures/confirm-enrichment-v1/`: request goldens per route
(CoFID, USDA, TFDA, Ciqual, Open Food Facts search and barcode, Your food database, including a title
with a pack size), scripted responses per row code, records and archives at contract 13, and food
daily export goldens for schema 7 alone and mixed with schemas 3 and 5 content.

## 8. Privacy and egress records

- **Section 11.1 rows and the "Stays on the device" sentence** are added to `privacy-and-egress.md`,
  word for word as CE1 writes them, **in the wiring PR (PR 5)** and not before (CE-T14), together with
  the 11.2 policy entry in `privacy-policy.txt`, the O1 switch title and framing sentence changes
  (CE1 section 9) and the `OpenRouterUse` cases turned in force. A verbatim test pins both rows and
  the entry, as `testTheLabelPhotoPrivacyRecordsAreInForceVerbatim` does for label photo.
- A use whose evaluation part missed its bar (section 9) is not put in force, and its row and policy
  sentence are not added; the wiring PR then carries an owner-approved narrowed text for the part that
  ships, never a widened one.
- **Section 11.1a**, the developer tooling paragraph, is added word for word in PR 3 and must be on
  `main` before the tool's first network call. The tool refuses to send unless the paragraph is
  present in `docs/privacy-and-egress.md` at the checkout it runs from (a preflight string check), and
  CE1 test 15's rule that no evaluation artefact is committed before the paragraph holds by order of
  the PRs.

## 9. Evaluation before any release (CE1 section 12)

- **Sets.** Built by the tool from public Open Food Facts product data and bundled composition rows
  only. Development set: 60 Open Food Facts products (UK and Taiwan, packaged, complete declared
  panels, at least 8 fortified) and 40 bundled rows; sealed set of the same size and mix. The owner
  checks the food details of the Open Food Facts cases on a review sheet before any A score counts.
  Manifests (case identifiers, barcodes or row identifiers, content hashes) are committed; product
  data and responses stay in the private folder.
- **Run.** The tool sends exactly the app's request bytes through the `FoodConfirmEnrichment`
  adapters with a tool-local gate, under CE-T15's limits ($5 programme, $0.05 per call, enforced in its
  own spend ledger before every call; at most 3 attempts with backoff honouring `Retry-After`). For B,
  known values are hidden per case as CE1 section 12 says.
- **Order.** The scorer, the bars of CE1 section 12 as code, and both manifests are committed (PR 4)
  before the sealed run; the sealed set is sent once by the frozen configuration and never reused.
  Development runs may iterate on prompt text only by a prompt version bump.
- **Outcome.** The repository gets counts, versions and hashes per bar. A missed bar stops release of
  that part; the other part may ship alone. If A misses the wrong pre-fill bar at 0.85, the report
  gives the lowest threshold that passes and the owner chooses (CE-D3).
- **Release.** No build that can reach either route outside Debug goes anywhere until its part passes;
  then internal TestFlight only (CE-T13), after the owner's one combined device check of O1 and CE1.

## 10. PR split

Each PR has its own branch, a ledger row, the validation gates of `AGENTS.md`, a blind
`invariant-reviewer` and a general defect review at its head, and the owner's yes before merge.

| PR | Content | Egress |
|---|---|---|
| 1. Formats | Domain kinds, provenance and release constants, capture and choices types, row and energy checks with the parity test, contract 13 floor and accepted set, store 13, export schema 7 writer and validators, verification on save and reopen, fixtures; dated note in assistant-pasted estimates v1. No UI path writes them yet. | None |
| 2. Confirm layer | Application policy, session state machine, response checks, ports and their contract suites, in-memory and file cache and ledger (in `FoodConfirmEnrichment`, without adapters), the Your food database read port and adapter, the suggestion layer and reducer, fill builder, Log requirement, re-log, quick add, re-resolution and reopen rules, presentation with `ConfirmEnrichmentText`, scripted adapters reachable only by a Debug launch argument, simulator journey with scripted answers. | None |
| 3. Adapters and tooling | The two adapters, route checkers and transport in `FoodConfirmEnrichment`, the four `OpenRouterUse` cases not in force, the boundary additions, `Tools/ConfirmEnrichmentEval` with its preflight, and the section 11.1a paragraph. Not wired into the app. | Tooling only, after merge |
| 4. Evaluation | Development runs, review sheet outcome, frozen configuration, scorer and manifests, then the sealed run and its report (counts, versions, hashes). | Tooling only |
| 5. Wiring | Composition root, Settings rows and switch, the uses in force for each part that passed, section 11.1 rows, 11.2 entry, O1 title and framing changes, Developer tools disclosure, journey QA; then the combined device check. | App, once merged, with both switches on |

PR 1 and the formats part of PR 2 change no behaviour for any store without CE1 records. PRs 1 to 3 can
be reviewed and merged without any network call from the app.

## 11. Points the owner sees before approving

1. **Food contract 13 leaves 12 unused.** CE1 names 13 because 12 is reserved; ordered store
   migrations mean 12 can never be built after 13, so assistant-pasted estimates takes the next free
   number at its phase (its section 7 allows this) and 12 is refused by every reader. The alternative,
   CE1 taking 12 and assistant estimates moving to 13 as the label photo gate did with 11, is equally
   safe; the gate keeps 13 because the approved contract and the issue hand-over name it.
2. **Export 7 and assistant fields.** CE1.7 says version 7 also admits version 6's fields "once that
   lands". The label photo gate's rule is that a shipped version is never widened, because an older
   build would reject a newer file of the same version. The gate builds 7 without assistant fields and
   leaves a day mixing B and assistant values to the assistant phase, which allocates a new union
   number. No B day is affected. This reads CE1.7 strictly in favour of fail-closed exports.
3. **Checks one layer down.** Section 3.2 places request building and response checks in application
   code rather than in the adapters, so a cache hit and a reopen run the same checks. No term changes.

## 12. Not in this phase

Web lookup, label routes and Your foods rows on Confirm (CE1 section 2); any change to the catalogue
or its skill; external TestFlight or App Store builds; any evaluation call before section 11.1a is on
`main`.

## 13. Review record

(Blind `architecture-gate` rounds recorded here.)
