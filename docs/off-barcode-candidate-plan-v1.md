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

## Nutrition schema repair v2 — 27 September 2026

Architecture gate: parsing remains wholly inside the OFF infrastructure adapter; the application candidate port, domain units/identity, explicit confirmation and provenance invariants are unchanged. The current v3.6 product response uses `nutrition.input_sets`, not the legacy `nutrition_data_per`/`nutriments` shape. Read exactly one `source=packaging`, `preparation=as_sold`, `per=100g` input set. Multiple eligible sets decline. No aggregate, prepared, volume, estimate or computed value is used to backfill the selected set. Missing/malformed modern nutrition declines without falling back to legacy data. Legacy mass fields remain supported only when the modern nutrition object is absent.

Advance projection/source/candidate policies to v2. Preserve `<`, `<=`, `>` and `>=` as augmented bounds, excluded from known-value totals; unsupported modifiers such as approximation remain unknown. Whole-response hashes, attribution and original scan evidence remain intact. Transport limits and user consent are unchanged.

Public UK supplier barcode 5000157004000 (Heinz Beanz 2.62 kg) returned HTTP 200 through both v2 and the shipped v3.6 endpoint. The current adapter declined v3.6 because legacy nutrition fields were absent; the modern packaging set contains protein 4.4 g/100 g and saturated fat <0.1 g/100 g. This single diagnostic establishes the schema mismatch, not representative UK coverage, current exact-label accuracy or reformulation acceptance. Public source: https://classicfinefoods.co.uk/grocery/885-heinz-baked-beans.html . Official change log: https://openfoodfacts.github.io/openfoodfacts-server/api/ref-api-and-product-schema-change-log/ . Raw full response remains temporary, not an app resource.

The same replay also exposed `success_with_warnings` for OFF's harmless leading-zero code normalisation. Admit only `different_normalized_product_code` with `impact=none`, then enforce canonical GTIN equality as before. Any other warning is rejected. Recognise a documented `product_not_found` failure at HTTP 404 as a miss, while other 404 responses fail closed.

### Approved bounded public replay

The user authorised at most 30 public production reads, at <=5/minute, no personal scans/images/accounts/spend. Two diagnostic reads used the public supplier code above; the remaining 28 read the first-ordinal-per-category then second-ordinal-in-category-order subset of the existing hash-selected Tesco Grocery 1.0 frame. The source SHA-256 was reverified; reads were spaced by at least 13 seconds, with no retries. No provider calls remain in this approved budget.

Actual Swift adapter replay: 28 legacy cases, 11 HTTP 200 products, 17 observed HTTP 404s, 2 populated candidates, 9 insufficient-data declines and no remaining adapter failures among the HTTP 200 responses. The 404 bodies were not retained by the probe, so they are not counted as adapter-level `notFound` evidence; synthetic contracts separately prove that route. Source-supported candidates are 2/28 in this deliberately historical sample; exact present-day variants, label freshness and reformulations remain unadjudicated. Report: `Tools/FoodSourceEvaluation/off-public-uk-legacy-replay-2026-09-27.json`. Source: https://doi.org/10.6084/m9.figshare.8668265.v2 (CC BY 4.0; dataset authors). No raw product response, contributor metadata or image is bundled.

Recommendation: retain OFF as an optional reviewed source, with truthful misses/insufficient-data recovery and no coverage promise. It is unsuitable as a universal or automatically trusted UK food catalogue. USDA and CoFID remain whole-record offline generic sources; exact saved reuse remains independent of OFF. Further current-UK/volume coverage is a separately scoped extension, not a model-generated nutrition substitute.
