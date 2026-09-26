# Optional Open Food Facts barcode candidates: app integration proposal v1

Issue #144. This proposal follows approved usage registration, successful staging transport, and a separately approved production probe. The production probe stopped on its first HTTP 503, with no retries and no product records. It provides no UK coverage or nutrition-accuracy evidence. Do not promote it as a successful barcode source.

## Proposed user flow

1. Check the exact saved library offline first. Preserve scan evidence and existing reuse behaviour.
2. On a miss, offer an explicit **Look up on Open Food Facts** action. Before the first request, explain that the barcode will be sent to Open Food Facts; lookup is optional. Never call on capture, in the background or on every keystroke.
3. Send only the validated GTIN in one foreground HTTPS GET to the official product endpoint, with the registered app User-Agent. No account, food history, meal date, quantity, location, image or HealthKit data. Rate-limit, cancel, time out and stop on errors without automatic retries.
4. Show a source-attributed product candidate or an explicit unavailable/not-found/incomplete state. A barcode hit is not verified identity or nutrition. Preserve returned name/brand/quantity, snapshot identity and supported declared nutrients; reject mismatched returned codes and ambiguous basis/units. Never infer liquid density, missing nutrients, preparation or recipe composition.
5. Save only after existing populated confirmation and quantity review. Keep the original scan and source metadata. A selected external record is an estimate; it never overwrites another source's record or a verified package label.

## Proposed storage, attribution and export boundary

OFF's database is under ODbL 1.0, individual contents under the Database Contents Licence, and images under a separate CC-BY-SA licence. This first adapter would not fetch or store images.

Keep immutable OFF source snapshots and licence/attribution/product URL metadata distinguishable from user-created log events. Show “Open Food Facts” with product and licence links in candidate/review screens. Preserve these notices through local archive round-trips and any user-initiated food-containing export. No central product database, public aggregation, OFF contribution/write endpoint or publication is proposed.

ODbL's collective/derivative database distinction and publicly-used derivative requirements must not be bypassed by merely calling a cache “isolated”. The application does not claim that personal logs are licensed for public redistribution. Public sharing of a derived product database, bulk OFF corpus bundling or changed export licensing would need its own explicit design. The proposed first use is private, local food logging with source notices retained, not publication.

## Architecture and contracts

Application owns a narrow asynchronous packaged-candidate lookup capability independent of the offline generic-search port. A network adapter owns URLSession, JSON, fixed endpoint construction, size/time/rate limits and API schema conversion. Domain correctness, barcode identity, unknown nutrient states and confirmation remain closed. Compose this optional adapter alongside the existing offline library path at the composition root.

Synthetic transport/mapper contracts precede any in-app live call: malformed code, code mismatch, unknown product, 503/429, timeout, cancellation, oversized payload, absent/ambiguous nutrition basis, incompatible units, missing values, provenance, attribution/archive/export preservation and exact offline reuse while the network is unavailable. Public production coverage remains a separate evaluation, not a software-test claim.

## Approved app-flow decision

The user approved this proposed app flow, then explicitly chose read operations only and no OFF account for now. The usage registration is complete; no app user account or credentials were created. No Gemini calls or spending are part of this decision.

## Primary references

- [OFF API documentation](https://openfoodfacts.github.io/openfoodfacts-server/api/): v3.6 product reads, custom User-Agent, limits and unreliable/incomplete data warning. Structured discovery currently uses v2; v3 has no structured-search endpoint.
- [OFF licence guidance](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorials/license-be-on-the-legal-side/): distinct database, contents and image licences.
- [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/): sections 4.2–4.6, notices, collective databases, publicly-used derivatives and machine-readable access requirements.

## Local implementation and limits

The application-owned asynchronous capability is `PackagedFoodCandidateLookingUp`; the concrete OFF adapter and HTTPS transport are infrastructure in FoodGenericSearch. The existing barcode coordinator still resolves the exact local library first and never calls the network. The optional foreground action appears only for GTIN fallbacks and uses versioned first-use disclosure. Cancel, rescan and leaving the screen cancel the task and invalidate late results. Errors preserve original scan evidence and the generic-search route.

The first mapper requires a matching returned GTIN, nonempty name, explicit `nutrition_data_per=100g`, a mass-labelled pack, and at least one supported finite, nonnegative, non-boolean nutrient. It declines liquid/ambiguous packs and known dietary-supplement categories. It supports energy-kcal, protein, carbohydrates, total/saturated fat, fibre and sugars only when units agree; missing nutrients remain unknown and incompatible units require conversion. Sodium is never inferred from salt. All OFF nutrition is augmented source data, not verified package measurement. Unknown identity attributes still require existing explicit confirmation review.

Transport is HTTPS GET only to the fixed official v3.6 endpoint, without redirects, credentials, cookies, response cache or automatic adapter retries. It admits one attempt per 13 seconds, uses 15-second request / 20-second resource timeouts and a 500,000-byte streaming response cap. Tests inject transport/clock services and intercept HTTP with URLProtocol; no live provider traffic is generated. Snapshot identifiers include payload hash and retrieval time so repeated responses cannot mutate immutable source-release metadata. Raw full product responses are not persisted; selected source values, original barcode, hash/version provenance, product URL and licence notices are retained.

The initial production discovery attempt remains the only production developer call and stopped at HTTP 503. No new live OFF calls, write operations or accounts were made during implementation. Representative UK hit rate, liquid support and physical-device barcode/network usability remain unverified. The account recommendation in the supplied API document does not add credential requirements to read requests; account-dependent contribution endpoints remain excluded.

## Validation — 26 September 2026

All 170 FoodLedgerKit tests pass, including eight new OFF mapper/transport tests. Full iPhone 17 Pro simulator tests, Xcode static analysis, dependency boundaries and `git diff --check` pass. HTTP tests are intercepted synthetic traffic, covering GET-only disclosure, credential/cookie removal, rate spacing, body cap and timeout propagation; source contracts cover cancellation, local/invalid codes, absent/mismatched products, unit/basis rejection, archive notices and exact offline reuse. No account, new live provider call, write/upload, commit, push, PR or TestFlight release was made. Physical scan/disclosure/cancellation behaviour and representative UK source coverage remain manual validation boundaries.
