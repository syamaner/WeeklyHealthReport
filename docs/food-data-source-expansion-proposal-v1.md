# Food data source expansion: reviewable proposal v1

Date: 26 September 2026. Issue: #144. The user approved labelled USDA whole-record candidates and bounded OFF registration/staging evaluation on this date. The optional read-only OFF app flow was subsequently approved; representative production coverage and independent search-quality acceptance remain open.

## Recommended decision

Keep CoFID as the UK generic source. Admit an additional explicitly labelled **USDA US-composition candidate** source, starting with Foundation Foods and SR Legacy, as whole-record alternatives requiring user selection. Never backfill an existing CoFID record or package label with USDA values; never describe a US grade/cut/preparation as the user's exact UK product. Defer FNDDS initially: prepared US diet-survey dishes add useful names but further recipe/portion assumptions.

Investigate Open Food Facts (OFF) as a user-invoked packaged-product **candidate** lookup, not authoritative identity. Before API use, approve and submit the project's requested usage registration. Before app integration/persistence, define and ratify the ODbL/contents-licence boundary, attribution, caching/export handling and the network privacy change. An isolated cache is an architecture proposal, not proof of licence compliance. Do not write to OFF, upload photos or personal logs, or submit user barcode histories.

This explicitly revisits the Phase 1 decision in `docs/food-source-coverage-and-licence-evaluation.md`, which says “Do not use USDA FoodData Central to silently fill CoFID gaps” and excludes OFF from Phase 1 identity/canonical resolution. The proposed optional whole-record USDA candidates do not silently fill gaps; source admission still needs the product decision about regional estimates. OFF registration would contact an external organisation and disclose the supplied project/contact details, so it needs user approval and an email address.

## Measured public-source probe

Only three account-free public USDA ZIPs were downloaded from the official download index. No API key, paid provider, personal data or device was used. Archives total 17,760,907 bytes. The complete hash-bound probe is `Tools/FoodSourceEvaluation/usda-public-coverage-probe-2026-09-26.json`.

| Snapshot | Object records | Non-object slots | Descriptions containing ribeye / rib eye | Descriptions containing fish and chips |
|---|---:|---:|---:|---:|
| Foundation, April 2026 | 363 | 32 | 1 / 0 | 0 |
| SR Legacy, April 2018 | 7,793 | 0 | 19 / 51 | 0 |
| FNDDS 2021–2023, October 2024 download | 5,432 | 0 | 3 / 0 | 0 |

These are literal substring counts, not retrieval accuracy, unique beef-cut counts, nutrient completeness or representative UK coverage. Some legacy ribeye hits refer to other species; grade, fat, bone and preparation descriptions must stay visible. No combined fish-and-chips text hit is not proof that every relevant recipe concept is absent.

Foundation FDC 2646172 is `Beef, ribeye, steak, boneless, choice, raw` with 22 reported nutrient entries. SR Legacy includes separately described raw and cooked rib-eye records. Current Foundation JSON contains 32 null slots; ingestion must record/quarantine them rather than crash or present a fictitious record. Nutrient mapping/units require an explicit contract: missing values stay unknown, duplicate energy conventions are not added, salt is not blindly treated as sodium, and carbohydrate conventions must remain visible. Values from a database match remain augmented estimates, not measurements of the user's meal.

## Architecture gate

- Application owns a cohesive candidate-source capability and composite search orchestration. Independent CoFID/USDA adapters return provider-neutral candidates and source-release metadata. Platform/network/JSON types stay inside adapters.
- Keep exact saved-library reuse first and independent of all external availability. Each candidate comes from one immutable source record/release; no automatic nutrient merge, cross-provider identity unification or source replacement.
- Centralise nutrient mapping, unit conversion, identity invariants and source-release versions; provider substitutions cannot override them. A downloaded source is not admitted until its canonical projection is hash-bound and validates.
- Generic sources are bundled/offline and need no runtime USDA API/account/backend. OFF, if admitted later, uses explicit foreground lookup, minimal GTIN disclosure, cancellation/timeout/rate limiting and no background activity.
- Alternate sources satisfy shared contract tests for evidence, unknowns, source IDs/releases, hard-rule constraints, per-100-unit basis, explicit selection and offline exact reuse. Enforce module/import boundaries in CI.
- Broader ranking, duplicate presentation and everyday query evaluation follow the source selection. The preserved v2 prototype is development material, not a promoted multi-source matcher.

## Concrete next implementation slices after the decision

1. Freeze accepted Foundation/SR snapshots and produce canonical projections with explicit nutrient/unit/identity maps, null quarantine and record-level provenance; pure source-contract tests.
2. Add USDA candidate adapter and offline composition alongside CoFID; show source/region, preparation and record differences in existing confirmation. No source-filled values get inserted into another source record.
3. Prepare OFF usage registration, then a bounded read-only staging probe: at most 50 public documentation/sample GTIN requests, at most 5 requests/minute, no retries after a rate-limit/error stop, no personal inputs or writes, no cost. Staging evidence is schema/transport evidence, not current UK production coverage.
4. Establish a separately bounded public UK production cohort and rights-compliant persistence plan before production API validation or app integration. Commercial alternatives remain #95 if OFF is not suitable.
5. Evaluate and refine everyday multi-source retrieval, then implement the intake-first UI sequence.

## OFF registration and staging result

The approved registration was submitted with the user-supplied contact address. The form confirmed “Your response has been recorded”. No launch date, producer relationship, editing account, application backend or public app-store URL was invented. The disclosed use was read-only staging evaluation with no personal logs, writes or uploads. Contact details and the response-edit link are deliberately excluded from this repository.

One of the approved maximum 50 staging reads was made, using the official public example GTIN 3274080005003 against `/api/v3.6/product/…` on `world.openfoodfacts.net`. HTTP 200, status success, product present; 142,240 response bytes, SHA-256 `c3af9faf2b86ba32566d337edb644dc160e1cf05d0f67350497e69dfcc287616`. No retries, private inputs or paid calls. This proves transport/schema only; it does not establish UK coverage or production licensing. The raw response remains temporary evaluation material and is not bundled in the app.

## Offline implementation contract

The bundled projection includes 363 Foundation and 7,793 SR Legacy records (8,156 total). The 32 Foundation null slots are recorded in the probe and omitted. `project_usda.py` requires the pinned official archive hashes and generates `usda-generic-v1.json`, whose SHA-256 is `70480d2c58bac9fcf9646b3b66c70be00e52398695536cef0af129ea1528e4c7`.

USDA candidates preserve source descriptions and release/record/nutrient IDs. Energy uses one declared convention in priority order: Atwater specific (2048), Atwater general (2047), then energy (1008). It is never summed across conventions. Missing or duplicate nutrient entries remain unknown; incompatible water mass versus canonical volume remains unknown. Vitamin A RAE/IU is not silently mapped to the UK RE field. Carbohydrate-by-difference differences are visible. Preparation/bone is inferred only from explicit source wording; other identity states stay unknown.

Both adapters pass the same evidence, unknown-value, explicit-selection and hard-identity checks. Composite orchestration preserves source order without comparing unlike scores or merging source records. Ribeye, rib eye and rib-eye retrieve labelled USDA records. Combined fish-and-chips remains an explicit miss with component suggestions. Broader relevance evaluation remains #148.

## Official references checked

- [USDA download index](https://fdc.nal.usda.gov/download-datasets/): exact download links and released snapshots.
- [USDA API guide](https://fdc.nal.usda.gov/api-guide/): CC0/public-domain data and API-key requirements. The recommended offline adapter avoids API credentials.
- [Foundation Foods documentation](https://fdc.nal.usda.gov/Foundation_Foods_Documentation/): distinct source types, sampled US foods and missing-nutrient/energy conventions.
- [OFF API introduction](https://openfoodfacts.github.io/openfoodfacts-server/api/): current v3 guidance, usage registration, custom User-Agent, staging and rate limits. The page currently states 15 product reads/minute/IP and 10 search reads/minute/IP; the proposed probe is below these.
- [OFF licensing guidance](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorials/license-be-on-the-legal-side/): ODbL database, Database Contents Licence contents and separate image licence.
- [OFF usage form](https://docs.google.com/forms/d/e/1FAIpQLSdIE3D8qvjC_zRJw1W8OmuHhsWJ_NSckiiniAHlfaVwUZCziQ/viewform): first page requires email and provides a nutrition topic.

## Reproduction

Run `python3 Tools/FoodSourceEvaluation/probe_usda_snapshots.py` with the three local official ZIP paths. It performs no network requests. Compare archive/JSON hashes and hit records against the saved probe; published non-object slots are explicit. The public files remain in `/private/tmp/whr-source-probe/`; the approved Foundation/SR projection is now bundled; FNDDS remains probe-only.

## Production evaluation extension

The user approved at most 50 public UK production reads at no more than 5/minute. The first request was a bounded public UK-tag discovery query (the official API currently provides structured search in v2 only). It returned HTTP 503 immediately; the probe stopped without retrying. Exactly one production request was attempted, zero product reads completed, and no public cohort was retrieved/frozen. `Tools/FoodSourceEvaluation/off-public-uk-production-probe-2026-09-26.json` preserves the result. This is an availability failure, not a measured coverage miss.

The reviewable optional in-app lookup, provenance, licence notices and private storage/export proposal is `docs/off-barcode-candidate-plan-v1.md`. The user subsequently approved the in-app flow, explicitly read-only with no account for now. The source plan now records the local implementation and validation; UK production coverage remains unverified.
