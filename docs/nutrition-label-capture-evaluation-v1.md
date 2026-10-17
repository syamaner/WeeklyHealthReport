# Nutrition-label capture evaluation v1

Status: **evaluation plan, approved by the owner, 17 October 2026.** All twelve decisions in section 12 were accepted as recommended, with decision 4 amended to five route C models. Later the same day the owner confirmed there will be **no new owner photos**: the corpus is limited to material the project already has (section 3), which makes decisions 6, 7 and 8 largely moot and narrows what any result can promote (section 3.5). The implementation phases are tracked in #255. Also on 17 October 2026 the owner approved two public Chinese additions (section 3.5): 60 Open Food Facts Taiwan label photos and Taiwan FDA open dataset 188 for synthetic pasted text. This document authorises no product code, no production capture route, no automatic saving and no API call. Route C below adds egress for the evaluation only; any product use of route C needs its own versioned contract, an update to [`privacy-and-egress.md`](privacy-and-egress.md), an update to [`privacy-policy.txt`](privacy-policy.txt) and separate owner approval. Version 1.1 (17 October 2026) records the evaluation framework, Inspect AI, in section 9.3, and the owner decisions on untouched ground truth and refills, with the deviations, in section 9.4. Version 1.2 (17 October 2026, phase 2) records route B, the safeguards, the untouched truth drafting and the UK shortfall and deferral in section 9.5. Version 1.3 (17 October 2026, phase 3) records the owner's verification of the untouched Taiwan drafts, the refills, the muesli consent and the route C development runs in section 9.6. Version 1.4 (18 October 2026, phase 4) records the decline gate, the offline re-score, the UK diagnosis and the whole-call deadline in section 9.7.

Related: #93 (printed-panel capture, blocked), #99 (cloud OCR challengers), #91 (handwritten lists, separate problem, not combined here), #86 (epic). Background evidence lives in [`Tools/FoodOCREvaluation/`](../Tools/FoodOCREvaluation/README.md).

## 1. Why a new evaluation

The #88 / #93 v1 gate evaluated one route: on-device Apple Vision with `en-US` on 40 UK Open Food Facts panels. It was declined ([result](../Tools/FoodOCREvaluation/untouched-gate-result-v1.md)): 97/535 strict cells, 157/535 bindings, 3/40 tables (all three were correct declines of empty tables), 0/79 serving conversions and 4/40 false-ready panels. Most failures were row and header binding, not character recognition. The v2 development work ([notes](../Tools/FoodOCREvaluation/v2-development-notes.md), [pre-gate plan](../Tools/FoodOCREvaluation/v2-pregate-plan.md), [`frozen-contract-v2.json`](../Tools/FoodOCREvaluation/frozen-contract-v2.json)) improved the policy but not binding, and its 40 untouched public images have never been run.

Three things have never been tried: a multimodal LLM, Chinese (Taiwan 營養標示) labels, and pasted table text. This plan compares three routes that all end in the **same structured candidate**, which a later phase would feed to the shared Confirm screen. Nothing in this evaluation saves food or treats any route's output as nutrition truth.

## 2. Routes under test

| Route | Input | Pipeline | Egress |
|---|---|---|---|
| **A. Pasted text** | Text the user pastes (copied from a web page, a PDF or a message) | Deterministic parser only | None |
| **B. On-device OCR** | Photo or screenshot | Apple Vision, recognition languages `zh-Hant` and `en` (exact locale identifiers as advertised by the Vision revision on the run day, recorded in the run manifest), then a geometry-to-lines serialiser, then the **same parser as A** | None |
| **C. Multimodal LLM** | Photo or screenshot | OpenRouter chat request with the image, a structured output schema and the existing ZDR routing | **New: the image leaves the device.** Evaluation only: the owner's own muesli label photo and public Open Food Facts corpus images only |

### 2.1 Parser scope (routes A and B)

The parser is pure, deterministic and has no network, clock or randomness dependency. It recognises:

- **English tables (UK and US):** `Energy` with `kJ` and `kcal`, `Calories`, `Fat`, `of which saturates`, `Saturated Fat`, `Trans Fat`, `Carbohydrate`, `Total Carbohydrate`, `of which sugars`, `Total Sugars`, `Includes Xg Added Sugars`, `Fibre` / `Dietary Fiber`, `Protein`, `Salt`, `Sodium`; column headers `per 100g`, `per 100ml`, `per serving`, `per X g`, `% RI`, `%DV`; serving lines such as `Serving size 30g` and `Servings per container about 8`.
- **Taiwan 營養標示 tables:** rows 熱量, 蛋白質, 脂肪, 飽和脂肪, 反式脂肪, 碳水化合物, 糖, 膳食纖維, 鈉 (and any further printed rows kept as unknown-meaning cells, never dropped silently); columns 每份 and 每100公克 (also 每100毫升 and 每日參考值百分比); units 大卡, 公克, 毫克 (also 微克 and 毫升); the serving size line 每一份量…公克 / 毫升; the servings per pack line 本包裝含…份.
- **Bounds:** `<0.1g`, `< 0.5 公克`, `less than 1g`, kept as bounds.
- **Indentation and parentage:** `of which`, leading full-width spaces, and the Taiwan sub-rows (飽和脂肪 and 反式脂肪 under 脂肪; 糖 and 膳食纖維 under 碳水化合物) record a parent row.

It never converts salt to sodium, kJ to kcal, % reference intake to an amount, or a per-serving value to per 100 g unless both the serving quantity and its unit are printed. A `% RI`, `%DV` or 每日參考值百分比 column is basis `reference_intake` and is never a product amount.

Route B's serialiser turns Vision observations into ordered lines with their geometry. It must bind by **column header and order within a column**, not by nearest vertical position alone: that is exactly where #93 failed, and it is the stress case in the first fixture (section 3.4).

### 2.2 Shared candidate

All three routes emit `label-capture-candidate-v1`, derived from the `candidate_schema` block of `frozen-contract-v2.json` and extended for Taiwan labels. Required fields:

- top level: `schema_version`, `route`, `input_sha256`, `status` (`user_selection_only`), `declined`, `decline_reasons`, `ready_for_confirmation` (always `false` in this evaluation's output; scoring separately records whether the route *would* have marked it ready), `automatic_save` (always `false`), `language` (`en`, `zh-Hant`, or `mixed`), `serving_size` (printed text, decimal text and unit, or `unknown`), `servings_per_pack` (printed text and decimal text, or `unknown`), `warnings`;
- per cell: `row_id`, `parent_row_id`, `nutrient` (closed canonical key or `unrecognised`), `printed_label`, `header_id`, `basis` (`per_100g`, `per_100ml`, `per_serving`, `reference_intake`), `printed_text`, `comparator` (`=`, `<`, `<=`), `decimal_text`, `unit` (as printed, with a separate canonical unit), `serving_conversion`, `persistence_authorized` (`false`), `requires_user_selection` (`true`).

`unknown` stays explicit everywhere. Route C's wire schema is designed with no more than 16 union-bearing parameters so every candidate model can accept it (schema v5's 24 unions broke Opus; see the [integration notes](generic-food-proposal-integration-v1.md)). It does not reuse schema v5 directly, because v5 cites captured text block IDs and an image has none; route C instead returns `printed_text` per cell, which is scored literally.

## 3. Corpus

### 3.1 Families

There are no new owner photos and no new screenshots. The corpus uses only material the project already has.

| Family | Source | Routes | Images or cases | Set |
|---|---|---|---|---|
| Muesli photo | The owner's single Taiwan label photo (section 3.4) | B, C | 1 | Development |
| v1 gate images | The 40 UK Open Food Facts panels from the #88 / #93 v1 gate; exposed by that run | B, C | 40 | Development |
| v2 tuning images | The 60 tuning identities of the frozen v2 public selection; exposed by the v2 tuning-only Vision run | B, C | 60 | Development |
| v2 sealed images | The 40 untouched identities of the frozen v2 public selection; never passed to any recogniser | B, C | 40 | **Untouched, opened once at the end** |
| Pasted text, English (synthetic) | Rendered from the reviewed ground truth of the same 140 public panels | A | One or more per usable panel | Same set as its source panel |
| Pasted text, Traditional Chinese (synthetic) | The muesli label typed out in Traditional Chinese, plus generated variants of the Taiwan table layout | A | 1 typed plus a generated set | Typed muesli is development; generated set split below |

Optional extra development material, not counted in the budget: the 60 v1 tuning panels (with committed v1 ground truth) and the 40-panel v2 development review. Both are already exposed and can never be untouched evidence.

**Pasted text is synthetic.** Every pasted case is generated by a frozen, deterministic renderer from verified ground truth, in several paste shapes seen on real pages (tab-separated, space-aligned, one value per line, label and value on separate lines, wrapped long labels). Each case is labelled `synthetic: true` with its generator version and seed. Route A on these cases measures the parser against clean text in known shapes; it does **not** measure real-world copy-and-paste variability, which remains unmeasured. Because the renderer reads ground truth only, route A on English pasted text also serves as the oracle-text diagnostic: route B's loss compared with route A on the same panel is the OCR and serialiser contribution.

**Synthetic Traditional Chinese set.** The muesli label, typed out by hand from the verified table, is the one real-layout Chinese text case. A frozen generator then produces Taiwan tables from a closed template covering the coverage tags below (two-column 每份 / 每100公克, single column, 每日參考值百分比 column, 每100毫升, bounds, missing rows, 本包裝含…份 with decimals such as 2.5), with values drawn from a seeded range and energy computed with the Taiwan formula so the arithmetic check is exercisable. Generator code, template and seed are frozen before any untouched generated case is produced; at least 40 development and 40 untouched generated cases, split by hash.

Coverage tags (recorded from ground truth before any run): `zh_hant`, `en_uk`, `two_column_serving_and_100`, `single_column`, `reference_intake_column`, `per_100ml`, `bound`, `salt`, `sodium`, `serving_line`, `servings_per_pack`, `nested_rows`, `column_offset`, `glossy`, `curved_or_crumpled`, `small_font`, `decline_expected`, `synthetic`. US English and screenshots are no longer covered (section 3.5).

### 3.2 Split and adequacy

- **Development:** the muesli photo, the 40 v1 gate images, the 60 v2 tuning images, their synthetic pasted texts, the typed muesli text and the development half of the generated Chinese set. Parser rules, serialiser, instruction text and schema may be tuned only on these.
- **Untouched:** the 40 v2 sealed images, their synthetic pasted texts, and the untouched half of the generated Chinese set. Assignments are already frozen for the public images and are frozen by hash for generated cases before generation.
- **Sealed v2 images** are opened only under the existing rules in `v2-pregate-plan.md` and `frozen-contract-v2.json`: identities and hashes already frozen, every route frozen by hash first, one single run for all routes together, no replacement, no rerun, results reported even if bad. Because the v2 review recorded only 8 of 16 required families, this cannot be called a v2 acceptance gate for #93; it is reported under this evaluation's own versioned contract.
- **Adequacy minima for a valid untouched result,** pre-registered and checked from ground truth only (no route output) before the run: at least 30 usable sealed tables, 5 required declines, 10 bounded cells and 20 printed serving conversions (the v2 contract's minima), plus at least 30 untouched synthetic Chinese cases. A shortfall makes the result invalid, reported as a diagnostic and never as a pass.

### 3.3 Privacy of the one personal photo

The repository is public. These rules now apply to the muesli photo only; public Open Food Facts images keep their existing licence and attribution handling.

1. **The original stays outside the repository**, in a private local folder that is not inside any git checkout and not inside a synced cloud folder (`~/WHR-label-eval-private/`, with `masters/`, `consent/` and `runs/`). The harness refuses any personal input path inside the repository and refuses to write personal image bytes into it.
2. **Metadata stripping:** ingest copies the original to `masters/` with `exiftool -all= -tagsFromFile @ -Orientation` (no pixel re-encoding; orientation kept), verifies with `exiftool -G -a` that no GPS, maker note, serial number, owner name or date-time tags remain, and fails closed otherwise. The stripped master's SHA-256 is its scored `input_sha256`.
3. **What is committed:** the hash, coverage tags, ground truth JSON and a redacted consent record. **No image bytes.** A panel-only crop is not committed in this round.
4. **Consent:** a private consent record holds four flags for the master hash, all `false` by default: `local_routes`, `send_to_openrouter`, `commit_ground_truth`, `commit_crop`. The route C runner refuses to send the photo unless `send_to_openrouter` is `true`. The owner sets the flags after looking at the stripped master.
5. **Reference by hash only in this task:** `b360d49e8934b4d275ea11640901ee1aeed767a12b56f9a7e4b1b1ba439d0d38` (SHA-256 of the uploaded file as received, 1512 by 2016 JPEG; a local Spotlight query showed no location metadata). It has not been copied into the repository. It shows a distributor's public business address and telephone number printed on the label, which is not personal data but is a further reason not to commit the whole image.

### 3.4 First fixture: Taiwan "6-Grain Muesli 500g"

Owner's hand-checked values (pass 1). One serving is 100 g, 5 servings per pack, so 每份 equals 每100公克:

| Row | Parent | 每份 | 每100公克 |
|---|---|---|---|
| 熱量 | | 367.2 大卡 | 367.2 大卡 |
| 蛋白質 | | 11 公克 | 11 公克 |
| 脂肪 | | 8.8 公克 | 8.8 公克 |
| 飽和脂肪 | 脂肪 | 1.2 公克 | 1.2 公克 |
| 反式脂肪 | 脂肪 | 0 公克 | 0 公克 |
| 碳水化合物 | | 67 公克 | 67 公克 |
| 糖 | 碳水化合物 | 9.1 公克 | 9.1 公克 |
| 膳食纖維 | 碳水化合物 | 12 公克 | 12 公克 |
| 鈉 | | 8 毫克 | 8 毫克 |

Serving size: 每一份量100公克 (100 g). Servings per pack: 本包裝含5份 (5). Net weight printed elsewhere on the label: 500公克, consistent with 5 × 100 g (an informing check only).

Why it matters: the right-hand column is printed about one row lower than the left, so a nearest-line binder pairs 熱量 with nothing or with the wrong value, and every row below shifts. Because the two columns hold identical values, a shifted binding is detectable (protein would become 367.2), which makes this a clean binding stress case. It is a **development** case, never untouched evidence.

### 3.5 Limits of this corpus

These limits are part of the result and must be repeated in every report.

- **Traditional Chinese photo coverage is a single real photo.** Any route B or route C result on Chinese labels is anecdotal. It cannot promote any route for Chinese label photos.
- **Promotion can apply only to UK English labels** (routes B and C, on Open Food Facts style photos), **plus pasted Chinese text** (route A) if its untouched synthetic cases pass every bar. Even then, real pasted Taiwan text from web pages is unmeasured, and a product phase must spot check real pasted examples before any user sees the route.
- **All pasted text is synthetic.** It shows the parser handles known shapes, not that real copied text arrives in those shapes.
- **US English and screenshots are not covered.** No result here speaks for US labels or web screenshots.
- **The public images are crowd-sourced Open Food Facts uploads,** not physical-camera captures by this app on the owner's device.

**Taiwan additions, approved by the owner on 17 October 2026:**

- **Open Food Facts Taiwan photos.** From the Search-a-licious query `countries_tags:"en:taiwan"`, products whose images include a `nutrition_zh` key (87 on 17 October 2026). Ordered by sha256 of the 13-digit barcode, the first 60 are taken: the first 20 by hash are development, the next 40 untouched. Files are `nutrition_zh.<rev>.full.jpg` with the revision pinned (28.9 MB in total on the day), kept outside the repository; the manifest records barcode, revision, URL, sha256 of the bytes, uploader and the CC BY-SA 3.0 attribution. Illegible crops or labels that are not 營養標示 are excluded with a logged reason and refilled from the next barcode in hash order; if the pool runs short, Taiwan barcodes (471 prefix) with a nutrition image under another language key follow, after a manual check that the label is Traditional Chinese. Hong Kong images, if ever used, are a separate stratum and never enter the Taiwan untouched set. Open Food Facts nutrient values are a draft to diff against, never ground truth; truth is the two-pass hand check.
- **Taiwan FDA dataset 188** (食品追溯追蹤系統消費者查詢資料集, Taiwan Open Government Data Licence v1, attribution required): rows with structured 營養標示 values are rendered into pasted-text cases in the exact label layout, labelled synthetic, and split by hash into development and untouched. Its values are manufacturer supplied and not guaranteed by the FDA, so a case is checked for internal consistency before use.

With these, route B and C results on Taiwan label photos can support a promotion decision for Traditional Chinese photos, scored on the 40 untouched Taiwan images as their own stratum. The budget in section 8.3 grows by about 300 calls (60 images × 5 models); the projection is recomputed from catalogue prices on the day, and the owner decides on any change to the $25 stop.

## 4. Ground truth: two-pass human check

Existing reviewed ground truth is reused wherever it exists; nothing is re-transcribed for its own sake.

| Set | Existing ground truth | Pass 2 needed |
|---|---|---|
| v1 gate images (40) | Committed `Tools/FoodOCREvaluation/fixtures/ground-truth-v1.json` (SHA-256 `c9475cbd…afcc0`), image-bound and visually verified | No; development only. Extended only for fields v1 did not record (servings per pack), marked as a single-pass extension |
| v2 tuning images (60) | The saved image-first v2 public reviews (100 hash-bound reviews, 25 September 2026, in an ignored local workspace) | No; development only. Single-pass, recorded as such |
| v2 sealed images (40) | The same saved v2 reviews | **Yes**, before the run (below) |
| Muesli photo | Owner's hand check (section 3.4) | **Yes**, against the physical pack |
| Synthetic pasted text | Generated from the ground truth above, so it inherits that truth exactly | No; the renderer is tested instead |

1. **Locate and freeze.** Phase 1 locates the v2 review workspace, verifies every annotation's image hash against the frozen v2 selection, and freezes a committed fixture with its SHA-256. Public-image transcriptions may be committed; image bytes are not. If the reviews for any sealed identity cannot be found or fail their hash check, those identities get a fresh pass 1 before the run, and the shortfall is recorded.
2. **Pass 2 for the sealed 40.** A second human check of each sealed image's ground truth against the image at full zoom, at least 24 hours after any edit, ticking or correcting every cell and recording whether a decline is required. Reviewing ground truth does not expose any route's output, so it does not consume the untouched set. The reviewer sees images and their reviews only; **no output from route A, B or C, and no other model, may prefill or alter an untouched case.**
3. **Pass 2 for the muesli label** is done by the owner against the physical package, if still available; otherwise against the image at full zoom, recorded as such.
4. **Disagreements** are resolved against the image or pack, never by majority with a model, and logged with both readings.
5. **Binding to identity:** each record carries `input_sha256`, reviewer identity, pass dates and editor version, so a changed image cannot inherit an annotation.
6. **Freeze:** the ground truth fixture hash is recorded in the contract before the sealed run. The existing `review_server.py` editor is extended for serving size and servings per pack rather than replaced.

## 5. Metrics and pass bars

The #93 strict bars are reused unchanged, per route, on that route's untouched set. Scoring uses the frozen v2 matching rules: canonical nutrient, parent and semantic basis; numeric text, comparator, unit and basis are compared without rewriting; missing candidates stay in denominators; declined images stay in denominators.

| Metric | Bar | Notes |
|---|---|---|
| Strict numeric-cell exact | at least 95% | Every printed product cell in every usable untouched table |
| Row / header binding | at least 98% | Correct row, parent and column header |
| Unit and basis | 100% | `大卡` canonicalises to kcal for unit identity, but printed unit text is retained and scored as printed |
| Full-table exact | at least 75% | Non-declined tables only; all rows, parents, headers, cells, bounds, bases, no extra cells |
| Serving conversions exact | at least 98% | Printed serving size quantity and unit; `unknown` or inferred values earn no credit |
| Servings per pack exact | at least 98% | New metric for 本包裝含…份 and `servings per container`; `about` kept as printed |
| Printed bounds preserved | 100% | An exact value replacing a bound fails |
| Correct decline | at least 95% | Every human-verified required decline; false declines on usable tables reported separately |
| False-ready (silent false-save) | **0** | Any incorrect, incomplete, extra or unbound table the route would mark ready, with or without a warning; any automatic persistence is a separate critical failure |
| Arithmetic mutation detection | 100% | The three frozen mutations (tenfold serving, basis transposition, bound replaced by exact) applied to untouched truth |

Reported but not gated: per-language and per-family breakdowns; route B loss against A-on-oracle; pairwise B against C on identical images (#99 asks for paired results, not vendor figures); correction count per table (cells a user would have to change). A zero false-ready count on a finite set is reported with its denominator and is not proof of a zero real-world rate.

## 6. Decline rules

A route must decline the table (all cells `unknown`, `declined: true`, reasons listed) when any of these holds:

- no nutrition table is found, or more than one product or panel is present and the panels cannot be separated;
- a value column has no recognisable basis header, or two columns resolve to the same basis without distinct printed headers;
- the number of values in a column cannot be bound one-to-one to the row labels (count mismatch, skipped or merged lines);
- a value has no unit, or an unrecognised unit, for an amount row (energy without kcal / kJ / 大卡 is never offered);
- the language is outside `en` and `zh-Hant` (Simplified Chinese, Japanese and others are declined in v1);
- for route C: schema-invalid output, refusal, truncation (`finish_reason` other than `stop`), tool calls, response model or provider not matching the request, timeout, or HTTP error. These are recorded as **failed**, a distinct state from declined, and both stay in the denominator.

A route may return a **partial** table: rows it could bind are candidates, the rest are explicit `unknown`. A partial table can never be marked ready. Image quality signals (Vision confidence, model self-reported confidence) may cause a decline but can never cause a ready mark.

## 7. Arithmetic cross-checks

These checks **inform but never authorise.** A pass never upgrades a candidate, never fills a missing value and never removes a warning. A failure adds a field-level warning ("energy does not match the macronutrients") and blocks the route from marking the table ready; it does not rewrite any value. The check is only run when every input is an exact printed value on the same basis; bounds and unknowns make it `not checkable`, never zero.

**General (UK and US):**

`kcal ≈ 4P + 4C + 9F`

where P, C and F are protein, carbohydrate and fat in grams. For UK and EU labels, where carbohydrate excludes fibre and fibre is printed, the variant `4P + 4C + 9F + 2·fibre` is also evaluated, and the check passes if either form is within tolerance. US labels use the general form only.

**Taiwan,** where carbohydrate includes dietary fibre and fibre counts at 2 kcal/g:

`kcal ≈ 4P + 4(C − fibre) + 2·fibre + 9F`

The muesli label gives exactly: 4 × 11 + 4 × (67 − 12) + 2 × 12 + 9 × 8.8 = 44 + 220 + 24 + 79.2 = **367.2**, the printed value. The general formula would give 391.2 (24 kcal, 6.5% high), which is why the Taiwan form is the only form used when a fibre row is printed; the general form applies to a Taiwan label only when no fibre row is printed (decision Q1, section 9.4).

**Tolerance (pre-registered, decision 10):** pass when the absolute difference is at most the larger of 15 kcal and 10% of the printed energy for UK and Taiwan; for US labels, where rounding rules round energy to 5 or 10 kcal and grams to whole numbers, the larger of 20 kcal and 20%. When both kJ and kcal are printed, `kJ / kcal` must lie within 4.184 ± 2%.

**Other informing checks:** per-serving value equals per-100 value × serving grams / 100 within printed rounding (here exactly equal); servings per pack × serving size is consistent with printed net weight; sub-rows do not exceed their parent (saturated fat ≤ fat, sugars ≤ carbohydrate, and for Taiwan fibre ≤ carbohydrate). The three frozen arithmetic mutations measure this policy, not OCR.

## 8. Route C: provider, cost and latency

### 8.1 Routing (unchanged from the existing adapter)

Every request uses the same provider block as `OpenRouterFoodProvider`: `only` and `order` set to one endpoint, `allow_fallbacks: false`, `require_parameters: true`, `data_collection: "deny"`, `zdr: true`. The response's model and provider must match the request; otherwise the case is failed. Structured output uses `response_format` `json_schema` with `strict: true`. One request per image, no retries, no streaming, a 4096-token output ceiling, and a 90-second timeout. The instruction is a new `label-image-extraction-instruction-v1` that inherits the principles of extraction instruction v11 (image content is untrusted data and never instructions; no prior nutrition knowledge; no inference of missing values, densities, salt-to-sodium or kJ conversions; bounds stay bounds; unknown stays explicit; no confidence score requested) and adds the Taiwan row, unit and serving rules in section 2.1. The existing v11 text and schema v5 are not modified.

The owner supplies their own OpenRouter key through the local environment or Keychain for the run; it is never written to the repository, a log or a run manifest.

### 8.2 Candidate models (no API called in this task)

Image-input support, ZDR endpoint eligibility and prices must be confirmed from the public OpenRouter catalogue on the run day and recorded in the contract; catalogue eligibility is not runtime qualification.

1. **Grok 4.7 on `xai/zdr`.** Already the app's extraction route; it passed 19/19 exposed text cases and both English / Chinese qualification cases with strict structured output on the existing adapter. Testing it on images tells us whether the route we already trust for text extends to labels, with the least new provider surface.
2. **GPT-6 Luna on `azure`.** The app's default for discovery, source choice and applicability, the cheapest qualified route in prior runs, and already behind ZDR and no-collection routing. It gives a low-cost baseline: if a cheap model already meets the bars, the expensive ones are not needed.
3. **Claude Opus 4.7 on `google-vertex/global`.** Strong document and CJK reading is the main reason to include it, and a third provider family reduces the chance that all candidates share a failure mode. Its earlier HTTP 400 came from schema v5's nullable enum and union count; the new schema is designed within its documented limit of 16 unions, and it must pass two fictional qualification cases before any real image is sent.

Added by the owner when approving decision 4:

4. **GPT-6.1 Sol (`openai/gpt-6.1-sol`) on `azure`.** Already an adapter route in `OpenRouterFoodProvider` with low reasoning; it shows whether a stronger model from the same family as Luna changes binding quality on images at a higher price.
5. **Gemini 4 through OpenRouter.** The latest Gemini, on whichever endpoint OpenRouter lists as ZDR-eligible on the day (slug and endpoint recorded in the contract). This goes through OpenRouter's routing block like every other model; it is **not** the retired direct Gemini egress, which stays retired.

All five face the same on-the-day gate: image input advertised, ZDR endpoint, `data_collection: "deny"`, no fallbacks, and response model and provider matching the request. A model that fails the gate is reported as not run, not as a quality result.

Reserve, not proposed for the first run: Qwen 3.5 on `deepinfra/fp8`, as a Chinese-strong open-weight comparison, only if its endpoint advertises image input and ZDR on the day. *Superseded by decision A (section 9.4): Qwen 3.5 VL drafts untouched ground truth, so it is no longer a route C reserve.*

### 8.3 Cost and latency measures

Per photo and per model: response-reported `usage.cost`, input and output tokens, wall-clock latency from request start to validated candidate, and HTTP status. Report median, p90 and maximum; unknown costs are counted and reported as unknown, never as zero. Request journals and receipts follow the existing pattern: a completed receipt is verified before the next call; a missing receipt stops the run.

Pre-registered stops (decision 9): stop a model's run if any single call reports more than **$0.05**; stop the whole evaluation at **$25** of reported cost (raised from $10 by the owner on 17 October 2026 to cover five models) or at the first unknown-cost call beyond three. These are run stops, not prepaid caps; the owner should also set a key limit at OpenRouter.

A rough envelope for planning, to be replaced by measured values. Route C images: 1 muesli + 100 development (40 v1 gate and 60 v2 tuning) + 40 sealed = **141 images**.

| Run | Calls (5 models) | At $0.005 per call | At $0.02 per call |
|---|---:|---:|---:|
| One development pass (101 images) | 505 | $2.53 | $10.10 |
| Sealed run (40 images, once) | 200 | $1.00 | $4.00 |
| **Both, one pass each** | **705** | **$3.53** | **$14.10** |
| Plus stability probe (10 development images × 3 repeats) | 855 | $4.28 | $17.10 |

Qualification calls (two fictional cases per model, 10 calls) and any repeat development passes after tuning come on top.

**Budget finding: the approved $10 total stop does not reliably cover five models over this corpus.** A single pass over all 141 images fits under $10 only if the average reported cost stays below about **$0.0142 per call** (705 calls), or about **$0.0117** with the stability probe (855 calls); every tuning iteration that reruns the 101 development images costs another 505 calls. At $0.02 per call a single development pass alone ($10.10) would reach the stop before the sealed run. The three added or premium models (Sol, Opus and Gemini 4) are the likeliest to sit at or above the top of that range, and a large-model call with an image, the instruction and a full table output could approach or exceed the **$0.05 per-call** stop, which would halt that model's run. These are assumptions, not quoted prices; no price was fetched for this plan. On 17 October 2026 the owner raised the total stop to **$25**, which covers all five models over the full corpus including the stability probe at up to about $0.029 per call; the $0.05 per-call stop is unchanged. Before the run, prices are recorded from the catalogue and, if the projected total exceeds $10, the owner chooses one of: raise the total stop, drop the stability probe, run development passes on a fixed subset (for example the muesli photo plus 20 development images) instead of all 101, or run the premium models on a subset first. Whatever is chosen, the sealed run's 200 calls are reserved out of the total before any development call, so the stop can never be reached with the untouched set unrun. Until then, the run order is Luna, Grok, Sol, Gemini 4, Opus, so that if the stop is reached, the cheaper arms are complete and only the most expensive arms are cut short; a cut-short arm is reported with its unattempted cases, never as a full result.

## 9. Frozen inputs and harness layout

### 9.1 Frozen-input rules

Before the untouched run, `frozen-contract-v1.json` records the SHA-256 of: the corpus manifest and split, the ground truth fixture, the candidate schema, the parser and serialiser sources, the Vision adapter source and binary, recognition languages and Vision revision, the route C instruction and wire schema, each model ID, endpoint, reasoning setting, token ceiling and timeout, the arithmetic tolerance table and the scorer. The runner refuses to start when any hash differs, refuses a non-empty output directory, writes its run manifest before the first recognition, and never reruns an untouched case. Tuning happens only on development cases. A later improvement needs a new versioned contract and a genuinely new untouched set; a consumed set is never relabelled as untouched.

### 9.2 Layout

A new sibling folder, so the frozen v1 and v2 artefacts in `Tools/FoodOCREvaluation/` stay byte-identical (decision 1):

```text
Tools/NutritionLabelCaptureEvaluation/
  README.md
  frozen-contract-v1.json          # thresholds, adequacy minima, hashes, tolerances
  validate_contract.py
  candidate-schema-v1.json         # shared output for A, B and C
  corpus-manifest-v1.json          # input hashes, tags, split, no paths or file names
  consent-redacted-v1.json         # muesli photo: hash and four flags only
  fixtures/ground-truth-v1.json    # frozen from v1, v2 reviews and the muesli check
  synthetic/                       # pasted-text renderer, Taiwan generator, seeds
  parser/                          # pure Swift module used by A and B (decision 2)
  vision_v3.swift                  # Vision adapter: zh-Hant + en, raw observations
  serialise_lines.py               # geometry to ordered lines, pure
  openrouter/
    label-image-extraction-instruction-v1.txt
    label-image-wire-schema-v1.json
    run_openrouter.py              # journal, receipts, stops, consent check
  ingest.py                        # muesli photo: strip, hash, consent stub; private folder only
  run_route_a.py
  run_route_b.py
  score.py                         # reuses v2 matching semantics
  arithmetic.py                    # section 7 checks and mutations
  tests/
  results/                         # committed reports and aggregate metrics
```

Pure scoring helpers from `Tools/FoodOCREvaluation/` may be imported read-only; nothing there is edited. Run outputs go to the private folder's `runs/` (the muesli photo) or an ignored `runs/` (public and pasted inputs). Public images are read from the existing hash-checked local workspaces and are never committed. CI gains contract validation and pure unit tests only; no CI job calls Vision on personal images or any provider.

### 9.3 Framework (v1.1 note, 17 October 2026)

On the owner's direction the harness is built on **Inspect AI** (`inspect_ai`, pinned to 0.3.276 in `Tools/NutritionLabelCaptureEvaluation/requirements.txt`, installed in a local venv only) rather than as a fully bespoke runner. Each case is an Inspect `Sample` (route input, truth as the target, metadata for corpus, split, coverage tags, hash and licence); development and untouched cases are separate datasets, and the untouched loader refuses to run without an explicit unseal flag and the sealed manifest's SHA-256. Each route is a solver (A: the Swift parser through its CLI; B: a reserved Vision slot; C: Inspect's `openrouter/...` model API with an image block and strict structured output, disabled until its phase). One scorer and one set of metrics serve every route; they call the pure scoring and arithmetic modules, whose unit tests run in CI with no model or provider call. Epochs serve the stability probe, and `.eval` logs are kept outside the repository with only summaries committed. Inspect's own `cost_limit` is per sample and priced from a cost table, so the plan's $0.05 per-call and $25 total stops on reported cost are enforced by a small wrapper. promptfoo was considered and not chosen: custom multi-denominator scoring and sealed-set handling fit it less well. The layout in section 9.2 is otherwise unchanged; phase 1 adds `inspect_task.py`, `budget.py`, `cases.py`, `acquire_off_taiwan.py` and `build_cases.py`, and puts the parser in the Swift target `NutritionLabelParsing` in `Packages/FoodLedgerKit` (decision 2) instead of a `parser/` folder.

### 9.4 Owner decisions and deviations (v1.1 note, 17 October 2026)

**Decision A, untouched ground truth.** Pass 1 for the 40 untouched Taiwan photos and the 40 sealed v2 UK images is drafted by a non-Claude model that is not a route C model under test: Qwen 3.5 VL through OpenRouter, which is therefore removed from the route C reserve. The owner then verifies every value against the image and corrects it. The result is recorded as **model-drafted, owner-verified**, which is weaker evidence than independent human transcription. Drafting sends public corpus images only to OpenRouter, with the route C provider block (one endpoint, ZDR, data collection denied, no fallbacks), in a later phase under the spend stops; it is defined, not run. Route C may never see untouched truth or drafts. The 20 Taiwan development truths were drafted by Claude (the assistant), so Claude Opus route C results on development data carry that caveat.

**Decision B, refill.** Up to 27 more Taiwan photos (orders 61 to 87 in hash order, about 13 MB, CC BY-SA 3.0) are approved, each downloaded only when an exclusion needs it, with the reason logged. The order is pre-registered: development replacements take the next barcodes first (61 and 62 replaced the English-only development orders 4 and 17), and untouched refills follow from order 63. The untouched minimum stays 40; if the refill pool runs out first, the Taiwan stratum is invalid and reported as a diagnostic.

**Deviations from this plan, recorded in `frozen-contract-v1.json`:**

- The 100 hash-bound v2 public reviews (section 4, step 1) were not found under the main checkout. The 40 sealed v2 images therefore need a fresh pass 1, by the decision A method, before the sealed run.
- Refill status: orders 4 and 17 are replaced by 61 and 62; untouched refills wait for the decision A drafting.
- Taiwan FDA dataset 188 rows are used in place of most of the closed-template generator (section 3.1); a small seeded template adds the tags FDA 188 lacks (bounds, 每日參考值百分比, 每100毫升, 本包裝含2.5份). Both are labelled synthetic.
- With a printed fibre row, the Taiwan energy check uses only the Taiwan form; the general form is used only when no fibre row is printed (section 7 is narrowed accordingly).

### 9.5 Phase 2 note (v1.2, 17 October 2026)

**UK images: shortfall and deferral.** The v1 gate panel images are no longer on disk (only their committed ground truth and raw Vision outputs remain), and the frozen v2 public selection behind the 60 tuning and 40 sealed identities in sections 3.1 and 3.2 was never acquired: no `frozen-selection-v2.json` or candidate inventory exists, and `v2-pregate-plan.md` records that no v2 acceptance corpus was built. Route B's UK development stratum therefore uses the 40 exposed v2 public development review images that are on disk, with their frozen review, and no UK image was downloaded. For now the UK untouched stratum does not exist. **UK untouched set deferred by the owner on 17 Oct 2026; acquire a fresh sealed UK set only if Taiwan results justify it. Until then no promotion decision for UK label photos.** Section 10's UK promotion path is suspended accordingly.

**Route B** is implemented (structural guards in the solver decline any table with a value the serialiser could not bind, and keep a table with a missing reference-intake cell from being marked ready): `vision_v3.swift` (Vision revision 3, accurate, `zh-Hant` and `en-US`, language correction as in the frozen v1 adapter; `en-GB` is not advertised on macOS 27.0.1, so it is not requested), `serialise_lines.py` (geometry to lines, binding by column header and order within a column) and the shared parser through `NutritionLabelTextParse` with route `B`. It ran on development images only; results are in `Tools/NutritionLabelCaptureEvaluation/results/route-b-development-v1.md`. The muesli photo was not run because its consent record has `local_routes` false.

**Safeguards** from the phase 1 review are in place: a missing `finish_reason` fails a route C response; the UK fibre form applies to UK labels only; refill batches are capped at the 5,000,000-byte stop; a model slug rule accepts only the requested slug or its dated snapshot (section 8.1 response check); and one persistent spend ledger outside the repository holds the $25 total and the 200-call sealed reservation across runs, models and the drafting.

**Decision A drafting** ran for the 40 untouched Taiwan photos with Qwen 3.5 (`qwen/qwen3.5-397b-a17b` on `deepinfra/fp8`, ZDR, image input, routed with the route C provider block). This opening is the set's unsealing for truth purposes only; routes A, B and C have still not run on these photos. Drafts are stored outside the repository, are not ground truth until the owner verifies each value against its image, and no route reads them.

**Egress.** This evaluation's OpenRouter egress (the drafting, and route C when it is enabled) is covered by this plan as evaluation-only egress of public corpus images, with the owner photo gated by its consent record; [`privacy-and-egress.md`](privacy-and-egress.md) describes the shipped app and is deliberately unchanged, and any product use still needs the contract, policy and approval steps in the status note at the top.

### 9.6 Phase 3 note (v1.3, 17 October 2026)

**Owner verification of the untouched Taiwan drafts (round 1).** The owner checked all 40 photos in a private review page: 527 of 527 cells confirmed with no corrections, 11 proposed exclusions agreed, order 23 (drafting failed on length) excluded, and order 34 kept as a Taiwan label although Qwen had proposed excluding it as a US-style bilingual label. The verified records are committed as `Tools/NutritionLabelCaptureEvaluation/fixtures/ground-truth-off-taiwan-untouched-v1.json` with the evidence label **model-drafted, owner-verified (no owner corrections)** and pinned by hash in the contract. With no corrections at all, **anchoring on the draft cannot be ruled out**. The page showed values, headers, serving lines and table decisions but not parent rows, so parentage in that file is structural (a deviation from section 4, step 2).

**Refills and round 2.** Refills 63 to 77 (5,776,668 bytes, under a 10 MB hard stop set by the owner) replace the 12 exclusions and three refills that were themselves other-language labels. They were drafted by the same contract-bound route; order 34 was redrafted with a bilingual instruction (v1 plus one clause, recorded as a deviation). Round 2 of the owner's review covers order 34 and the refills; the truth file is then rebuilt and re-pinned. The untouched photos have still not been seen by any route.

**Muesli photo.** On 17 October 2026 the owner granted every route, including OpenRouter; all four consent flags are true in the private and the redacted record. Route A on the typed text is exact; route B declines the photo (`unsupported_language`); route C has run on it in all ten development arms and read it exactly in every one (18 of 18 cells, the full table, 9 of 9 serving conversions and the servings per pack, none false-ready).

**Route C, development only.** Route C is implemented and enabled for the muesli photo, the Taiwan development photos and the UK development review images, never the untouched or sealed photos. A first run (ZDR endpoints, reasoning off, 4096 tokens, $0.05 per call) was **held by the owner** after Luna had sent 43 of 60 development photos; that partial run is discarded and never scored. The Taiwan development truths were drafted by Claude, so Claude Opus results on that stratum carry that caveat. Results (all ten arms complete): `Tools/NutritionLabelCaptureEvaluation/results/route-c-development-v1.md`.

**Deviations, owner decisions of 17 October 2026 (route C, evaluation only; product routing is unchanged).** Recorded in `frozen-contract-v1.json` under `route_c.owner_decisions_2026_10_17`:

1. The ZDR requirement (`zdr: true`) and `data_collection: "deny"` are dropped from the route C provider block (sections 8.1 and 8.2). Whether each model has a ZDR endpoint is recorded as information only; any product use would still need ZDR.
2. One pinned provider per model stays (`only` and `order`, no fallbacks, parameters required), chosen by quality and price: OpenAI for Luna and Sol, xAI for Grok, Google AI Studio for Gemini 4 (`google/gemini-4-argon`, the newest Gemini) and Anthropic for Claude, all first-party at list price. The model and provider identity checks stay.
3. The output ceiling rises from 4096 to 16384 tokens.
4. The per-call stop rises from $0.05 to $0.20, and the total stop from $25 to $60 (then $65, item 10). The 200 sealed calls stay reserved, now at $0.20 each ($40). Before any sealed run, if the remaining budget could not cover it, the run stops and the owner decides. The persistent ledger's limits were changed twice (to $60, then $65), each through a recorded amendment, never by hand.
5. Retryable errors (transport errors, timeouts, HTTP 408, 429, 500, 502, 503, 504 and provider-overloaded answers) are retried with exponential backoff and jitter, honouring `Retry-After` in both forms, for at most 5 attempts within 180 s. Content outcomes (schema failures, `finish_reason` other than `stop`, identity mismatches) are never retried; they are scored failures. Every attempt is in the ledger; a retryable error with no generation returned is recorded as `retryable_error_unknown_cost` and does not count toward the three-unknown stop. The same policy applies to the drafting client. Inspect's own retry for `openrouter/...` parses `Retry-After` but its backoff ignores it, and the OpenAI SDK under it retries on its own, so route C now posts to OpenRouter directly with one retry loop and Inspect runs the dataset, scorer and logs.
6. Each model runs twice on development data, reasoning off and reasoning on (the model's default effort), so the owner can choose per model before the untouched run.
7. The product ceilings (median $0.02 per photo, p90 20 seconds) are unchanged.

Later the same day the owner added, also recorded in the contract:

8. **Latest models.** Every route C model must be the latest generally available version in its family that takes image input. Checked against the public catalogue, only the Claude slot changed: Opus 4.7 became Claude Opus 5.5 (`anthropic/claude-opus-5.5`, released 22 September 2026), on the `anthropic` endpoint.
9. **Extra arms.** GPT-6 Luna Pro, GPT-6.1 Sol Pro and Claude Fable 5.1 run as extra development arms, cheapest first. Fable 5.1 carries the same Claude self-agreement caveat as Opus 5.5 on the Taiwan development truths. Reasoning off is not available (reasoning mandatory) on Grok, Sol, Sol Pro, Gemini 4, Opus 5.5 and Fable 5.1, so those run with reasoning on only.
10. **Budget.** The total stop rises to $65, with the $40 sealed reservation unchanged, giving $25 for development. The ledger's limits changed only through recorded amendments. A non-retryable rejection with no generation is logged as `rejected_no_generation_unknown_cost` and, like a retryable error, does not count toward the three-unknown stop. Before each arm, the runner checks the key's remaining limit and the account balance (both free) and refuses to start when the arm's projected cost plus a margin is not covered.
11. **Deadline.** One slow attempt can outlast the 180 s deadline, because the socket timeout is per read (Grok's maximum was 263 s). A whole-call deadline is implemented before the sealed run, not during development, so the development arms stay comparable.

The untouched Taiwan truth is complete after the owner's second review round: 40 usable tables, model-drafted and owner-verified with no corrections over 795 cells, re-pinned in the contract.

### 9.7 Phase 4 note (v1.4, 18 October 2026)

No API call was made in phase 4, and the untouched and sealed sets were not opened. Owner-approved plan of 17 October 2026:

- **Decline gate.** `label-capture-decline-gate-v1` (`Tools/NutritionLabelCaptureEvaluation/decline_gate.py`, contract block `decline_gate`, frozen and pinned) runs on every candidate from every route after extraction. From the candidate and the declared label format only, it declines unsupported scripts (kana, Hangul, or Han characters in GB 2312 but not in Big5), non-food panels (supplements), tables missing a mandatory row of the Taiwan or UK format, and mandatory rows missing an amount column; it blocks ready for a UK table without a per 100 g or ml column and a Taiwan table without its serving lines. It never changes a value. The rules come from the label regulations and section 6; development data motivated them but no rule was tuned to a development case. It is in Python, not the Swift parser, because no product path consumes route C yet; a product phase would port it behind the same test vectors.
- **Offline re-score.** On the saved development outputs, correct declines rise in every route C arm (Taiwan up to 5/5 for four arms; UK up to 12/17), no exactly right table is declined in routes B or C, and false-ready falls only from 53 to 49 over the ten arms: the remaining false-ready tables are image-quality declines the candidate cannot show, or wrong values. No arm meets the zero false-ready bar on development.
- **UK diagnosis.** Most UK loss is convention, not reading: serving conversions scored on header wording, count-only portions with no printed mass, absolute reference-intake columns failing the whole candidate, and units printed in the row label. Proposed amendments (S1, M1, M2, M3, T1) and possible truth errors are listed for the owner and **not applied**.
- **Owner amendments, 18 October 2026 (pre-registered before the untouched run).**
  - The owner approved all five as proposed, recorded in contract block `amendments_2026_10_18`:
    - **S1:** serving conversions are scored on the printed mass or volume, and count-only portions leave the denominator.
    - **M1:** route C leaves absolute reference-intake values out as unread instead of failing the candidate.
    - **M2:** route C takes the energy unit from the row label when the value prints none.
    - **M3:** route C reads the serving quantity from a per-serving header that prints a mass or volume.
    - **T1:** in the UK development truth, reference-intake cells share their amount row and parent, and untranscribed reference-intake columns are not counted as extras.
  - Re-scored offline, UK reading improves sharply: Luna off reaches 301/311 strict cells, and most arms reach 70/70 conversions. However, UK false-ready rises in every route C arm (28 → 61), because the image-quality declines that the gate cannot see now read as complete tables.
  - The section 5 bars are unchanged.
- **Whole-call deadline.** `openrouter_client.http_post` now bounds each attempt by the time left of the 180 s call budget with a watchdog that closes the socket; the retry policy is unchanged. The phase 3 development arms ran without it.

Results: [`Tools/NutritionLabelCaptureEvaluation/results/phase-4-decline-gate-and-uk-diagnosis-v1.md`](../Tools/NutritionLabelCaptureEvaluation/results/phase-4-decline-gate-and-uk-diagnosis-v1.md). The untouched Taiwan run (Gemini 4 Argon reasoning on, GPT-6.1 Sol on, Luna off) waits for the owner.

## 10. Promotion and decline

A route may be **proposed for product** (a separate phase, with its own architecture gate and contract) only when all of these hold on its untouched set:

- every bar in section 5 passes and the adequacy minima are met;
- zero false-ready tables and zero automatic persistence;
- the promotion is limited to what the corpus covers (section 3.5): UK English label photos for B and C, and pasted UK English or Taiwan text for A; Chinese label photos only on the untouched Open Food Facts Taiwan stratum, never on the single muesli photo;
- for B: the result was produced with the frozen on-device configuration, and a physical-device spot check by the owner on a sample of development images agrees (simulator and Mac runs prove software behaviour only);
- for C: median cost per photo at most $0.02 and p90 latency at most 20 seconds (decision 9), zero response model or provider mismatches, ZDR and no-collection routing honoured on every call, and **then** a versioned product contract, a `privacy-and-egress.md` row, a `privacy-policy.txt` update (the current policy states that photos are not attached to OpenRouter requests) and separate owner approval.

Even a promoted route only **proposes**: every cell goes to the shared Confirm screen beside the original image or pasted text, requires explicit user selection, and the user's Log action is the only save. Model output, citations, confidence and the arithmetic check never authorise nutrition.

A route stays **declined** when any bar fails, any false-ready table occurs, the gate is invalid through an adequacy shortfall, or (for C) any routing, cost or latency condition fails. A decline is recorded with its evidence and does not block the other routes. Recommended order of preference if more than one passes: A (no egress, no camera), then B (no egress), then C.

## 11. Owner-only steps

No new photos, screenshots or pasted texts are needed.

1. **Move the muesli photo** into a private folder outside any repository and outside synced cloud storage (`~/WHR-label-eval-private/`), then run ingest (once implemented) and set its four consent flags after looking at the stripped master. Set `send_to_openrouter` only if you are content for that image to go to the route C models.
2. **Pass 2 for the muesli label** against the physical pack, if you still have it.
3. **Pass 2 for the 40 sealed ground-truth records** (section 4), against the images at full zoom, before the sealed run.
4. **Check the typed muesli text and the synthetic Chinese generator template** for wording that looks like a real Taiwan label.
5. **Approve the spend and the runs:** confirm the five models and the prices recorded on the day, resolve the budget finding (section 8.3), confirm your OpenRouter key has a limit, then approve the single sealed run, which opens the 40 sealed v2 images.
6. **Device spot check** for any route B candidate for promotion.
7. **Decide** on the results and on the separate future question of adding public Taiwan images (section 3.5); promotion and any product egress remain your decisions alone.

## 12. Decisions for the owner

1. **Harness location.** Build in a new sibling `Tools/NutritionLabelCaptureEvaluation/` and leave `Tools/FoodOCREvaluation/` frozen? *Recommendation: yes.*
2. **Parser language.** Write the shared A / B parser as a pure Swift module so the evaluated code is the code that would ship, with Python only for orchestration and scoring? *Recommendation: yes.*
3. **Candidate schema.** Define a new `label-capture-candidate-v1` (and a route C wire schema with at most 16 unions) rather than adapting schema v5, leaving v11 and v5 untouched? *Recommendation: yes.*
4. **Route C models.** Test Grok 4.7 (`xai/zdr`), GPT-6 Luna (`azure`) and Claude Opus 4.7 (`google-vertex/global`), each only if the catalogue on the day shows image input and ZDR, with Opus first passing two fictional qualification cases? *Recommendation: yes, with Qwen 3.5 held in reserve.* **Owner answer (amended):** five models: Grok 4.7, GPT-6 Luna, Claude Opus 4.7, GPT-6.1 Sol (`openai/gpt-6.1-sol`) and Gemini 4, all through OpenRouter; Qwen 3.5 in reserve. Each passes the same on-the-day gate (image input, ZDR, no fallbacks). Gemini uses OpenRouter routing, not the retired direct Gemini egress. See the budget finding in section 8.3.
5. **Sealed v2 images.** Open the 40 sealed v2 images once, for all three routes together, only after every route is frozen, and report them as a separate public-UK result rather than a v2 acceptance gate (the v2 review met only 8 of 16 families)? *Recommendation: yes, as the final step.* With no owner photos, the sealed 40 are now **the** untouched image set for this evaluation.
6. **Owner corpus split.** *Superseded (no owner photos).* The muesli photo is fixed in development; the public split is the existing frozen v2 one (section 3.2). Only the generated Chinese set is split by hash.
7. **Private storage and consent.** *Narrowed to the muesli photo:* private folder, metadata stripping, hash-only reference and the per-image consent flags apply to that single image (section 3.3).
8. **Ground-truth pass 2.** *Largely superseded:* existing reviewed ground truth is reused (section 4). The owner still does pass 2 on the muesli label against the physical pack and on the 40 sealed records, recorded as single-reviewer evidence.
9. **Budget and product ceilings.** Set run stops at $0.05 per call and $25 in total (owner raised from $10, 17 October 2026), and product ceilings for route C at median $0.02 per photo and p90 20 seconds? *Recommendation: yes.*
10. **Arithmetic tolerance.** Adopt the larger of 15 kcal and 10% (UK and Taiwan), 20 kcal and 20% (US), and kJ / kcal within 4.184 ± 2%, with a failure blocking ready but never changing a value? *Recommendation: yes.*
11. **Independent promotion.** Allow route A to proceed to its own product contract if it passes, without waiting for B or C? *Recommendation: yes; it has no egress and the lowest risk.*
12. **Tracking.** Open a new evaluation issue linked to #93 and #99 for the implementation phases, rather than reusing #93? *Recommendation: yes; #93 stays the product delivery issue.*
