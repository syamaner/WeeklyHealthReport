# Nutrition-label capture evaluation v1

Status: **evaluation plan only.** Scope approved by the owner on 17 October 2026. This document authorises no product code, no production capture route, no automatic saving and no API call. Route C below adds egress for the evaluation only; any product use of route C needs its own versioned contract, an update to [`privacy-and-egress.md`](privacy-and-egress.md), an update to [`privacy-policy.txt`](privacy-policy.txt) and separate owner approval.

Related: #93 (printed-panel capture, blocked), #99 (cloud OCR challengers), #91 (handwritten lists, separate problem, not combined here), #86 (epic). Background evidence lives in [`Tools/FoodOCREvaluation/`](../Tools/FoodOCREvaluation/README.md).

## 1. Why a new evaluation

The #88 / #93 v1 gate evaluated one route: on-device Apple Vision with `en-US` on 40 UK Open Food Facts panels. It was declined ([result](../Tools/FoodOCREvaluation/untouched-gate-result-v1.md)): 97/535 strict cells, 157/535 bindings, 3/40 tables (all three were correct declines of empty tables), 0/79 serving conversions and 4/40 false-ready panels. Most failures were row and header binding, not character recognition. The v2 development work ([notes](../Tools/FoodOCREvaluation/v2-development-notes.md), [pre-gate plan](../Tools/FoodOCREvaluation/v2-pregate-plan.md), [`frozen-contract-v2.json`](../Tools/FoodOCREvaluation/frozen-contract-v2.json)) improved the policy but not binding, and its 40 untouched public images have never been run.

Three things have never been tried: a multimodal LLM, Chinese (Taiwan 營養標示) labels, and pasted table text. This plan compares three routes that all end in the **same structured candidate**, which a later phase would feed to the shared Confirm screen. Nothing in this evaluation saves food or treats any route's output as nutrition truth.

## 2. Routes under test

| Route | Input | Pipeline | Egress |
|---|---|---|---|
| **A. Pasted text** | Text the user pastes (copied from a web page, a PDF or a message) | Deterministic parser only | None |
| **B. On-device OCR** | Photo or screenshot | Apple Vision, recognition languages `zh-Hant` and `en` (exact locale identifiers as advertised by the Vision revision on the run day, recorded in the run manifest), then a geometry-to-lines serialiser, then the **same parser as A** | None |
| **C. Multimodal LLM** | Photo or screenshot | OpenRouter chat request with the image, a structured output schema and the existing ZDR routing | **New: the image leaves the device.** Evaluation only, owner's own label photos and public corpus images only |

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

| Family | Source | Routes | Approximate size |
|---|---|---|---|
| Owner photos, Taiwan | Labels the owner owns, photographed by the owner | B, C | About 18 |
| Owner photos, UK | As above | B, C | About 12 |
| Screenshots | Public product web pages (Taiwan and UK retailers or manufacturers), screenshotted by the owner | B, C | 8 to 12 |
| Pasted text | Text copied from the same or other public pages, saved with source URL and capture date | A | 10 to 20 |
| Oracle text | The verified ground-truth transcript of every photo and screenshot | A (diagnostic) | One per image |
| Public UK v2 sealed | The 40 sealed v2 untouched Open Food Facts images | B, C (A via oracle text) | 40 |

Where possible a screenshot and a pasted text come from the **same page**, so A and B / C can be paired on identical content. The oracle-text run isolates parser quality from OCR quality: route B's loss compared with A-on-oracle is the OCR and serialiser contribution.

Required coverage tags (recorded at intake, before any run): `zh_hant`, `en_uk`, `en_us`, `two_column_serving_and_100`, `single_column`, `reference_intake_column`, `per_100ml`, `bound`, `salt`, `sodium`, `serving_line`, `servings_per_pack`, `nested_rows`, `column_offset`, `glossy`, `curved_or_crumpled`, `angled`, `small_font`, `screenshot`, `decline_expected`.

### 3.2 Split

- **Development:** the first fixture (already exposed in this planning task) plus a deterministic third of the remaining owner images and screenshots, and a third of pasted texts. Parser rules, serialiser, instruction text and schema may be tuned only on these.
- **Untouched:** the rest. Assignment uses the existing pattern: sort by SHA-256 of `"label-capture-v1:" + input_sha256`, take the first third for development. Assignment is frozen in `corpus-manifest-v1.json` before ground truth is reviewed and before any route runs on the untouched set.
- **Adequacy minima for a valid untouched result** (pre-registered; a shortfall makes the gate invalid, never a pass): at least 12 Taiwan photo tables, 8 UK photo tables, 6 screenshots, 8 pasted texts, 3 expected declines, 5 bounded cells, 10 printed serving conversions and every coverage tag present at least once across development and untouched.
- **Sealed v2 images:** opened only under the existing rules in `v2-pregate-plan.md` and `frozen-contract-v2.json`: identities and hashes already frozen, all three routes frozen by hash first, one single run, no replacement, no rerun, results reported even if bad. Because the v2 review recorded only 8 of 16 required families, this run cannot be called a v2 acceptance gate for #93; it is reported as a separate, versioned public-UK result (decision 5).

### 3.3 Privacy of personal photos

The repository is public. Personal photos are handled as follows.

1. **Originals stay outside the repository**, in a private local folder that is not inside any git checkout and not inside a synced cloud folder (recommended: `~/WHR-label-eval-private/`, with `inbox/`, `masters/`, `consent/` and `runs/`). The harness refuses any personal input path inside the repository and refuses to write image bytes into it. `.gitignore` gains defensive entries for `*.heic`, `*.jpg`, `*.jpeg` and `*.png` under the new tool folder, with an explicit allow-list for consented crops.
2. **Metadata stripping:** ingest copies each original from `inbox/` to `masters/` with `exiftool -all= -tagsFromFile @ -Orientation` (no pixel re-encoding; orientation kept so the image is not silently rotated). Ingest then verifies with `exiftool -G -a` that no GPS, maker note, serial number, owner name or date-time tags remain, and fails closed otherwise. HEIC inputs are converted once to JPEG at maximum quality before stripping and the conversion is recorded. The stripped master is the scored identity; its SHA-256 is the `input_sha256`. The original's hash is kept only in the private folder.
3. **What is committed:** SHA-256 hashes, coverage tags, ground truth JSON, the consent ledger (hash, flags and date, no file names or paths), run reports and aggregate metrics. **No image bytes by default.** A nutrition-panel crop is committed only when its consent flag is set and the owner has checked the crop shows nothing but the panel (no hands, faces, receipts, addresses, screens, home interiors or other packaging). Screenshots are checked for browser chrome showing account names, tabs or notifications, and cropped to the page content.
4. **Per-image consent:** `consent/consent-ledger.json` in the private folder holds, per master hash, four independent flags, all `false` by default: `local_routes` (A and B), `send_to_openrouter` (C), `commit_ground_truth`, `commit_crop`; plus the date and a free-text note. The owner sets them by editing the file or answering a prompt from `ingest.py`; the harness reads them before every action and refuses any route C request for a hash without `send_to_openrouter: true`. The owner's scope approval covers route C for own photos in principle; the per-image flag is what prevents an accidental send of a photo with personal background. A redacted copy (hash and flags only) is committed.
5. **The first fixture** is referenced only by hash in this task:
   `b360d49e8934b4d275ea11640901ee1aeed767a12b56f9a7e4b1b1ba439d0d38` (SHA-256 of the uploaded file as received, 1512 by 2016 JPEG; it showed no location metadata in a local Spotlight query). It has not been copied into the repository. At ingest it will be stripped and receive a new master hash, which becomes its scored identity. It shows a distributor's public business address and telephone number printed on the label, which is not personal data but is a reason to commit a panel-only crop rather than the whole label.

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

## 4. Ground truth: two-pass human check

1. **Pass 1, transcription.** A human enters every visible nutrition cell from the image (or, for owner photos, from the physical pack) into the review editor: row, parent, header, basis, printed text, comparator, decimal text, unit, serving size line and servings per pack. Drafts may come only from a source independent of the routes under test (for example a blank Taiwan or UK row template). **No output from route A, B or C, and no other model, may prefill an untouched case.** Development cases may use drafts, recorded as such.
2. **Pass 2, verification.** A second, separate check at least 24 hours later, by a different person where available, otherwise by the owner against the **physical package** for owner photos and against the image at full zoom for public images and screenshots. Every cell is ticked or corrected; the reviewer also records whether the image is legible enough to require a decline.
3. **Disagreements** are resolved against the physical pack or the image, never by majority with a model, and logged with both readings.
4. **Binding to identity:** each record carries the master `input_sha256`, reviewer identity, pass dates and editor version, so a changed image cannot inherit an annotation.
5. **Freeze:** the ground truth fixture hash is recorded in the contract before any untouched run. The existing `review_server.py` editor is extended (in the implementation phase) for Chinese labels, serving size and servings per pack rather than replaced.

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

where P, C and F are protein, carbohydrate and fat in grams. For UK and EU labels, where carbohydrate excludes fibre and fibre is printed, the variant `4P + 4C + 9F + 2·fibre` is also evaluated, and the check passes if either form is within tolerance.

**Taiwan,** where carbohydrate includes dietary fibre and fibre counts at 2 kcal/g:

`kcal ≈ 4P + 4(C − fibre) + 2·fibre + 9F`

The muesli label gives exactly: 4 × 11 + 4 × (67 − 12) + 2 × 12 + 9 × 8.8 = 44 + 220 + 24 + 79.2 = **367.2**, the printed value. The general formula would give 391.2 (24 kcal, 6.5% high), which is why the language-specific form is used first.

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

Reserve, not proposed for the first run: Qwen 3.5 on `deepinfra/fp8`, as a Chinese-strong open-weight comparison, only if its endpoint advertises image input and ZDR on the day.

### 8.3 Cost and latency measures

Per photo and per model: response-reported `usage.cost`, input and output tokens, wall-clock latency from request start to validated candidate, and HTTP status. Report median, p90 and maximum; unknown costs are counted and reported as unknown, never as zero. Request journals and receipts follow the existing pattern: a completed receipt is verified before the next call; a missing receipt stops the run.

Pre-registered stops (decision 9): stop a model's run if any single call reports more than **$0.05**; stop the whole evaluation at **$10** of reported cost or at the first unknown-cost call beyond three. These are run stops, not prepaid caps; the owner should also set a key limit at OpenRouter.

A rough envelope for planning, to be replaced by measured values: about 100 images (owner photos, screenshots and the 40 public images) × 3 models, plus 10 development images × 3 models × 3 repeats for a stability probe, is about 390 calls; at an assumed $0.005 to $0.02 per photo that is roughly $2 to $8.

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
  consent-ledger-redacted-v1.json  # hash and four flags only
  fixtures/ground-truth-v1.json
  fixtures/crops/                  # consented panel crops only
  parser/                          # pure Swift module used by A and B (decision 2)
  vision_v3.swift                  # Vision adapter: zh-Hant + en, raw observations
  serialise_lines.py               # geometry to ordered lines, pure
  openrouter/
    label-image-extraction-instruction-v1.txt
    label-image-wire-schema-v1.json
    run_openrouter.py              # journal, receipts, stops, consent check
  ingest.py                        # strip, hash, consent stub; private folder only
  run_route_a.py
  run_route_b.py
  score.py                         # reuses v2 matching semantics
  arithmetic.py                    # section 7 checks and mutations
  tests/
  results/                         # committed reports and aggregate metrics
```

Pure scoring helpers from `Tools/FoodOCREvaluation/` may be imported read-only; nothing there is edited. Run outputs go to the private folder's `runs/` (owner images) or an ignored `runs/` (public and pasted inputs). CI gains contract validation and pure unit tests only; no CI job calls Vision on personal images or any provider.

## 10. Promotion and decline

A route may be **proposed for product** (a separate phase, with its own architecture gate and contract) only when all of these hold on its untouched set:

- every bar in section 5 passes and the adequacy minima are met;
- zero false-ready tables and zero automatic persistence;
- for B: the result was produced with the frozen on-device configuration, and a physical-device spot check by the owner on at least five owner labels agrees (simulator and Mac runs prove software behaviour only);
- for C: median cost per photo at most $0.02 and p90 latency at most 20 seconds (decision 9), zero response model or provider mismatches, ZDR and no-collection routing honoured on every call, and **then** a versioned product contract, a `privacy-and-egress.md` row, a `privacy-policy.txt` update (the current policy states that photos are not attached to OpenRouter requests) and separate owner approval.

Even a promoted route only **proposes**: every cell goes to the shared Confirm screen beside the original image or pasted text, requires explicit user selection, and the user's Log action is the only save. Model output, citations, confidence and the arithmetic check never authorise nutrition.

A route stays **declined** when any bar fails, any false-ready table occurs, the gate is invalid through an adequacy shortfall, or (for C) any routing, cost or latency condition fails. A decline is recorded with its evidence and does not block the other routes. Recommended order of preference if more than one passes: A (no egress, no camera), then B (no egress), then C.

## 11. Owner-only steps

1. **Create the private folder** outside any repository and outside synced cloud storage, with `inbox/`, `masters/`, `consent/` and `runs/`.
2. **Take the photos** (about 30, Taiwan and UK labels you own). Lay the pack flat in daylight, fill the frame with the nutrition panel and the product name, avoid glare and shadows, and keep people, hands, receipts, letters, screens and room details out of shot. For about a third, also take a deliberately harder shot (angled, curved or glossy) of the same label and say so in the note. Keep the packs until pass 2 is done.
3. **Hand them over:** in Photos on the Mac, select the pictures, choose File, Export, Export as JPEG at maximum quality with location information unticked, and save them into `inbox/`. (From the iPhone, AirDrop with Options, Location turned off, also works.) Do not attach them to chat, email or an issue.
4. **Screenshots and pasted texts:** capture public product pages only, crop away browser chrome, and save each pasted text as a `.txt` with the page URL and date on the first line.
5. **Run ingest** (once implemented) and set the four consent flags per image. Set `send_to_openrouter` only after looking at the stripped master.
6. **Ground truth:** do pass 1 or pass 2 (or both, at least 24 hours apart) against the physical packs.
7. **Approve the spend and the run:** confirm the models, budget and that your key has a limit, then approve the single untouched run, and separately approve opening the sealed v2 images.
8. **Device spot check** for any route B candidate for promotion.
9. **Decide** on the results; promotion and any product egress remain your decisions alone.

## 12. Decisions for the owner

1. **Harness location.** Build in a new sibling `Tools/NutritionLabelCaptureEvaluation/` and leave `Tools/FoodOCREvaluation/` frozen? *Recommendation: yes.*
2. **Parser language.** Write the shared A / B parser as a pure Swift module so the evaluated code is the code that would ship, with Python only for orchestration and scoring? *Recommendation: yes.*
3. **Candidate schema.** Define a new `label-capture-candidate-v1` (and a route C wire schema with at most 16 unions) rather than adapting schema v5, leaving v11 and v5 untouched? *Recommendation: yes.*
4. **Route C models.** Test Grok 4.7 (`xai/zdr`), GPT-6 Luna (`azure`) and Claude Opus 4.7 (`google-vertex/global`), each only if the catalogue on the day shows image input and ZDR, with Opus first passing two fictional qualification cases? *Recommendation: yes, with Qwen 3.5 held in reserve.*
5. **Sealed v2 images.** Open the 40 sealed v2 images once, for all three routes together, only after every route is frozen, and report them as a separate public-UK result rather than a v2 acceptance gate (the v2 review met only 8 of 16 families)? *Recommendation: yes, as the final step after the owner-photo gate.*
6. **Owner corpus split.** Use a deterministic hash-ordered one-third development and two-thirds untouched split, with the muesli label fixed in development and the adequacy minima in section 3.2? *Recommendation: yes; take a few extra photos so the minima survive declines.*
7. **Private storage and consent.** Keep originals in `~/WHR-label-eval-private/` (not synced), strip metadata at ingest, commit only hashes, ground truth and a redacted consent ledger, and require a per-image `send_to_openrouter` flag? *Recommendation: yes; commit no crops in the first round.*
8. **Ground-truth pass 2.** Accept the owner as pass 2 reviewer, checking against the physical pack at least 24 hours after pass 1, when no second person is available? *Recommendation: yes, and record it as single-reviewer evidence.*
9. **Budget and product ceilings.** Set run stops at $0.05 per call and $10 in total, and product ceilings for route C at median $0.02 per photo and p90 20 seconds? *Recommendation: yes.*
10. **Arithmetic tolerance.** Adopt the larger of 15 kcal and 10% (UK and Taiwan), 20 kcal and 20% (US), and kJ / kcal within 4.184 ± 2%, with a failure blocking ready but never changing a value? *Recommendation: yes.*
11. **Independent promotion.** Allow route A to proceed to its own product contract if it passes, without waiting for B or C? *Recommendation: yes; it has no egress and the lowest risk.*
12. **Tracking.** Open a new evaluation issue linked to #93 and #99 for the implementation phases, rather than reusing #93? *Recommendation: yes; #93 stays the product delivery issue.*
