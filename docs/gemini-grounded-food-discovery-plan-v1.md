# Gemini BYOK food-source discovery v1

Status: implemented for [#172](https://github.com/syamaner/WeeklyHealthReport/issues/172), 28 September 2026. The user authorised a user-key-only, explicit-tap source-discovery flow. This is separate from [#100](https://github.com/syamaner/WeeklyHealthReport/issues/100)'s frozen-candidate matching challenger. No provider call, personal-data evaluation, model-quality claim or TestFlight acceptance is implied by implementation.

The [unified search contract v1](unified-food-search-contract-v1.md) supersedes
the explicit-tap requirement as of 29 September 2026. Automatic enrichment is the
new target; this document records the historical citation-only implementation.
The manual route is now under **Search options → Developer tools → Debug Gemini
source discovery**. It remains citation-only. As of 30 September, the normal flow separately composes default-off automatic Gemini with exact validated-key grants and source-verified Alpro UK nutrition admission. Broader coverage and live/device acceptance remain pending; see the unified contract.

## Contract and architecture gate

The app's bundled CoFID/USDA search remains independent. **Search foods → run offline search → Search the web** opens a separate flow with an editable food-terms field prefilled from the completed offline query; no HealthKit data, diary, saved food, capture evidence or inventory is attached. Changing the offline query hides the web route until offline search runs again. The screen explains the exact outbound terms, fixed source-finding instruction, Google account charges, retention and key exposure before key entry. Key validation sends a model-metadata request only; food discovery requires a separate **Search the web** tap.

The architecture gate was completed before implementation:

| Responsibility | Owner / dependency |
| --- | --- |
| Discovery and credential contracts | `FoodLedgerApplication`: plain `FoodWebDiscoveryResult`, link policy, `FoodWebDiscovering` and `FoodWebKeyStoring`. No platform SDK imports, persistence or food-confirmation types. |
| Provider request / response / error projection | `FoodGenericSearch/GeminiFoodWebDiscovery`: injected HTTP transport, fixed model and Google endpoint. No ledger writer or candidate construction. |
| Secret persistence | `FoodGenericSearch/GeminiKeychainStore`: Security adapter, consumer-owned credential port. |
| User actions and asynchronous lifecycle | `FoodLedgerPresentation/FoodWebDiscoveryViewModel`: explicit validation/search, typed failure messages, cancellation and generation checks. |
| Native display | Separate SwiftUI discovery form; isolated WebKit renderer for provider HTML. |
| Concrete wiring | App food-search composition root. No Gemini dependency in bundled search or domain rules. |

Stable invariants are closed: a grounded response cannot become a nutrition candidate, confirmation, saved food or export; no model changes identity, preparation, quantity basis, nutrients or schema. Even a page claiming exact 10% yoghurt or a milk density remains an unverified lead. Source admission is a separate future contract, not a button in this flow. The response text is displayed completely and labelled unverified; any numbers it contains remain unadmitted.

Provider, transport and key storage are credible substitution boundaries. Synthetic contract tests cover request shape, empty/unverified results, unsafe links, schema failures and typed provider errors. Presentation tests exercise the same discovery port with controlled success, errors and suspended replies. `check-boundaries.sh` keeps domain/application free of UI, networking clients and Security; Security/WebKit imports are confined to their named concrete adapters. No provider SDK, backend, Firebase or project-owned credential is added.

### Citation presentation gate, after local development pilots

The five-case prompt pilots in [`Tools/GeminiGroundingEvaluation/pilot-findings-2026-09-28.md`](../Tools/GeminiGroundingEvaluation/pilot-findings-2026-09-28.md) found model-written Markdown links whose hosts differed from Google's annotation source titles. The citation URL, model prose and a Markdown URL embedded in that prose are three separate claims. The follow-up presentation change assigns parsing of this relationship to a pure `FoodLedgerApplication` policy, keeps Google's annotation URL as the only primary source link, and places the complete model answer and cited passages in clearly labelled, expandable text. The infrastructure adapter still only projects Google annotations; the presentation layer never turns a model-written Markdown URL into a source lead.

The stable invariants are unchanged: no cited page or model claim becomes admitted nutrition, identity, quantity or a saved food; no extra network request, key use or persistence is introduced. A matching host means only that the visible strings are consistent, not that the page exists or supports the claim. The policy treats model-written opaque redirects, generic citation titles with different written hosts, and broad multi-link spans as unresolved rather than falsely verified. The credible extension axis is a future page resolver or provider adapter behind the discovery port; neither can override the admission boundary. Synthetic contract tests cover matching subdomains, conflicting hosts, opaque redirects, broad spans and citation-free text. SwiftUI compilation and the simulator suite protect the presentation change.

## Frozen provider route

Official documentation checked 27–28 September 2026:

- [Google Search grounding](https://ai.google.dev/gemini-api/docs/google-search): Interactions API with `google_search`, text `url_citation` annotations and `google_search_result.result[].search_suggestions`.
- [Interactions API reference](https://ai.google.dev/api/interactions-api): request and completed-status response shape.
- [Interaction storage](https://ai.google.dev/gemini-api/docs/interactions-overview): stateless request setting.
- [Model metadata](https://ai.google.dev/api/models): bounded model-access check.
- [API keys](https://ai.google.dev/gemini-api/docs/api-key): client exposure and current restrictions.
- [Pricing](https://ai.google.dev/gemini-api/docs/pricing) and [terms](https://ai.google.dev/gemini-api/terms): current account obligations; no fixed-price promise in the app.

Route: `POST https://generativelanguage.googleapis.com/v1beta/interactions`, model `gemini-3.8-flash`, `tools:[{"type":"google_search"}]`, `store:false`, maximum output tokens 2048. Input is the trimmed, visible 1–300-character food-terms field; a fixed system instruction requests cited original/authoritative source pages without inferred nutrition. No previous interaction, background work, extra tool, automatic retry or automatic fallback is used. The client uses an ephemeral, cookieless, cacheless session, refuses redirects, limits elapsed resource time to 30 seconds and stops response accumulation at 1 MB. These client limits are not a provider spending cap; one tap can initiate multiple billable searches.

Validation uses `GET /v1beta/models/gemini-3.8-flash`, requiring the expected model metadata before saving. The local syntax check accepts 20–512 visible ASCII bytes, including punctuation, while rejecting whitespace and control bytes; only Google decides whether the credential is valid. A saved key must be explicitly revalidated after reopening the search flow; syntax alone never re-enables it, including after a failed removal. Validation establishes provisional model access, not Search entitlement, available quota or future validity. Errors distinguish explicit invalid/expired/revoked-key reasons and HTTP 401 from HTTP 403 permission restrictions, HTTP 429 quota/rate limits, request/model rejection, unsupported responses and network failure. Raw provider errors never reach UI/logs. A search-time key rejection disables and attempts to remove the credential; quota/network failures keep it available for a later explicit retry.

## Credentials and display

The user key is passed only in `x-goog-api-key`, never a URL or request body. Stored keys use a service-scoped generic-password item with the Data Protection Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and synchronisation disabled, including replacement updates. No UserDefaults, ledger, export or diagnostics field contains the key. The secure entry clears as validation starts and on leaving; plaintext necessarily exists in process memory for requests. Keychain does not prevent extraction on a compromised or instrumented client.

Removal cancels pending work and invalidates late replies before deleting the Keychain item. A delayed validation cannot recreate a removed key. Deletion failures are visible and do not claim success. Leaving the screen or editing terms discards pending search results; credential changes clear old results. Removal cannot recall a request Google already received or revoke a key at Google, so the UI links to AI Studio.

Generated text, citation links with their byte-range-validated cited passages, and every supplied suggestion block stay together on the transient result screen. Google's annotation URLs are presented as citation links; the full model answer and cited passages sit under expandable text so model-written links and claims cannot be mistaken for provider citations. They are never persisted, indexed, scraped, click-tracked or fed to another model. Provider instructions remain inert data. Only credential-free HTTPS links open externally. An unsafe citation or malformed passage span causes the whole response to fail closed. Provider HTML is kept intact inside a non-persistent, script-disabled WKWebView with a restrictive content policy; remote subresources, forms and frames are blocked. Only an explicit link activation opens the external browser. Native tests establish that fixture HTML renders without executing its script. Provider HTML styling/link behaviour and full accessibility still need a real-key device check.

The app discloses possible per-search charges, client-key extraction risk, and Google's grounding retention separately from `store:false`. Grounding prompts/context/results have a 30-day provider retention rule. Unpaid-service training/human-review rules and paid-service processing differ; UK/EEA/Swiss clients require a project with active billing. Current Google eligibility/region/age and account terms must be satisfied for live use. This implementation does not verify billing or promise legal/release acceptance.

## Validation and device runbook

Synthetic development fixtures contain no real credential and make no live provider call. Cases cover:

- exact request route/body/header, no key in URL/body, metadata validation;
- no call on screen creation, typing, absent key or invalid local input; separate validation and search actions;
- full response text under disclosure, provider citation links separate from model-written passages, matching/conflicting/opaque/broad link-host comparisons, malformed byte spans and multiple Search-suggestion blocks; empty/un-grounded response;
- malformed/incomplete/oversized responses, unsafe links, credential echoes, provider instructions, invalid key, permission, quota and network failures;
- offline-first route gating, cancellation-ignoring replies after query edits, leaving or key removal; removal during validation, failed-removal reopening and repeated taps;
- Keychain read/save/delete failure states, native secure entry, injected Security-operation tests for ThisDeviceOnly replacement/removal and isolated HTML rendering.

Local validation results are recorded in the PR. The unsigned iOS test host could not access Keychain; a local ad-hoc signed retry was blocked by the existing `FoodLedgerKit_FoodGenericSearch.bundle` resource-signing error. A macOS legacy-keychain experiment could round-trip synthetic values but did not expose iOS accessibility attributes, so it is not accepted as device-only protection evidence. Production explicitly selects the Data Protection Keychain; portable tests verify the Security requests and failure behaviour with an injected backend. Actual signed-device lock/unlock, storage and deletion remain acceptance gates. The native secure-field and script-disabled suggestion tests pass without a provider key.

Run:

```sh
swift test --package-path Packages/FoodLedgerKit
bash Packages/FoodLedgerKit/Scripts/check-boundaries.sh
xcodebuild analyze -project WeeklyHealthReport.xcodeproj -scheme WeeklyHealthReport -destination 'platform=iOS Simulator,id=<available-iPhone>' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project WeeklyHealthReport.xcodeproj -scheme WeeklyHealthReport -destination 'platform=iOS Simulator,id=<available-iPhone>' ENABLE_DEBUG_DYLIB=NO CODE_SIGNING_ALLOWED=NO
```

Before device/TestFlight acceptance, the user must supply their own eligible key and perform an explicitly authorised, bounded live test. Do not collect the key in an issue, test fixture, command, screenshot or chat.

1. Search bundled foods with no key and no network. Check the separate web route explains data, charges and key exposure and cannot search before validation.
2. Validate a user key. Check invalid key versus permission/quota/offline messages without inferring invalidity from a timeout. Confirm no food search occurs during setup.
3. Enter a public-only term such as `Greek yoghurt 10% fat` or `whole milk`; tap once. Review Google's account usage/cost separately. Open a Google-cited page and expand the cited passage and full answer. Check that a model-written different link is visibly flagged and never replaces the provider citation URL. Verify suggestions and explicit unverified status. No lead can be reviewed as a candidate or saved.
4. Check normal/large text, VoiceOver, keyboard, scrolling and external links. Confirm provided suggestion HTML remains fully visible and functional. Provider/layout acceptance is not established by fixture rendering.
5. Change terms, leave during a pending call, remove the key during validation/search, relaunch and lock/unlock. Confirm no late result or credential reappears; offline search still works. Check Google revocation separately if required.
6. Keep source-discovery quality, provider costs, source admission and device acceptance distinct. This flow does not fulfil #100's matching-challenger evaluation and must not close that issue as fully accepted.
