# Gemini BYOK food-source discovery v1

Status: implemented for [#100](https://github.com/syamaner/WeeklyHealthReport/issues/100), 28 September 2026. The user authorised a user-key-only, explicit-tap source-discovery flow. This is separate from #100's frozen-candidate matching challenger. No provider call, personal-data evaluation, model-quality claim or TestFlight acceptance is implied by implementation.

## Contract and architecture gate

The app's bundled CoFID/USDA search remains independent. **Search foods → Search the web** opens a separate flow with its own food-terms field; no local query, HealthKit data, diary, saved food, capture evidence or inventory is automatically attached. The screen explains the exact outbound terms, fixed source-finding instruction, Google account charges, retention and key exposure before key entry. Key validation sends a model-metadata request only; food discovery requires a separate **Search the web** tap.

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

## Frozen provider route

Official documentation checked 27–28 September 2026:

- [Google Search grounding](https://ai.google.dev/gemini-api/docs/google-search): Interactions API with `google_search`, text `url_citation` annotations and `google_search_result.result[].search_suggestions`.
- [Interactions API reference](https://ai.google.dev/api/interactions-api): request and completed-status response shape.
- [Interaction storage](https://ai.google.dev/gemini-api/docs/interactions-overview): stateless request setting.
- [Model metadata](https://ai.google.dev/api/models): bounded model-access check.
- [API keys](https://ai.google.dev/gemini-api/docs/api-key): client exposure and current restrictions.
- [Pricing](https://ai.google.dev/gemini-api/docs/pricing) and [terms](https://ai.google.dev/gemini-api/terms): current account obligations; no fixed-price promise in the app.

Route: `POST https://generativelanguage.googleapis.com/v1beta/interactions`, model `gemini-3.8-flash`, `tools:[{"type":"google_search"}]`, `store:false`, maximum output tokens 2048. Input is the trimmed, visible 1–300-character food-terms field; a fixed system instruction requests cited original/authoritative source pages without inferred nutrition. No previous interaction, background work, extra tool, automatic retry or automatic fallback is used. The client uses an ephemeral, cookieless, cacheless session, refuses redirects, limits elapsed resource time to 30 seconds and stops response accumulation at 1 MB. These client limits are not a provider spending cap; one tap can initiate multiple billable searches.

Validation uses `GET /v1beta/models/gemini-3.8-flash`, requiring the expected model metadata before saving. It establishes provisional model access, not Search entitlement, available quota or future validity. Errors distinguish explicit invalid/expired/revoked-key reasons and HTTP 401 from HTTP 403 permission restrictions, HTTP 429 quota/rate limits, request/model rejection, unsupported responses and network failure. Raw provider errors never reach UI/logs. A search-time key rejection disables and attempts to remove the credential; quota/network failures keep it available for a later explicit retry.

## Credentials and display

The user key is passed only in `x-goog-api-key`, never a URL or request body. Stored keys use a service-scoped generic-password item with the Data Protection Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and synchronisation disabled, including replacement updates. No UserDefaults, ledger, export or diagnostics field contains the key. The secure entry clears as validation starts and on leaving; plaintext necessarily exists in process memory for requests. Keychain does not prevent extraction on a compromised or instrumented client.

Removal cancels pending work and invalidates late replies before deleting the Keychain item. A delayed validation cannot recreate a removed key. Deletion failures are visible and do not claim success. Leaving the screen or editing terms discards pending search results; credential changes clear old results. Removal cannot recall a request Google already received or revoke a key at Google, so the UI links to AI Studio.

Generated text, citation links and every supplied suggestion block stay together on the transient result screen. They are never persisted, indexed, scraped, click-tracked or fed to another model. Provider instructions remain inert data. Only credential-free HTTPS links open externally. An unsafe citation causes the whole response to fail closed. Provider HTML is kept intact inside a non-persistent, script-disabled WKWebView with a restrictive content policy; remote subresources, forms and frames are blocked. Only an explicit link activation opens the external browser. Native tests establish that fixture HTML renders without executing its script. Provider HTML styling/link behaviour and full accessibility still need a real-key device check.

The app discloses possible per-search charges, client-key extraction risk, and Google's grounding retention separately from `store:false`. Grounding prompts/context/results have a 30-day provider retention rule. Unpaid-service training/human-review rules and paid-service processing differ; UK/EEA/Swiss clients require a project with active billing. Current Google eligibility/region/age and account terms must be satisfied for live use. This implementation does not verify billing or promise legal/release acceptance.

## Validation and device runbook

Synthetic development fixtures contain no real credential and make no live provider call. Cases cover:

- exact request route/body/header, no key in URL/body, metadata validation;
- no call on screen creation, typing, absent key or invalid local input; separate validation and search actions;
- full response text, source titles/links and multiple Search-suggestion blocks; empty/un-grounded response;
- malformed/incomplete/oversized responses, unsafe links, credential echoes, provider instructions, invalid key, permission, quota and network failures;
- cancellation-ignoring replies after query edits, leaving or key removal; removal during validation; repeated taps;
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
3. Enter a public-only term such as `Greek yoghurt 10% fat` or `whole milk`; tap once. Review Google's account usage/cost separately. Verify the full generated response, citation destinations, suggestions and explicit unverified status. No lead can be reviewed as a candidate or saved.
4. Check normal/large text, VoiceOver, keyboard, scrolling and external links. Confirm provided suggestion HTML remains fully visible and functional. Provider/layout acceptance is not established by fixture rendering.
5. Change terms, leave during a pending call, remove the key during validation/search, relaunch and lock/unlock. Confirm no late result or credential reappears; offline search still works. Check Google revocation separately if required.
6. Keep source-discovery quality, provider costs, source admission and device acceptance distinct. This flow does not fulfil #100's matching-challenger evaluation and must not close that issue as fully accepted.
