# Food identity capture and nutrition augmentation

**Decision-grade technical research report — 19 September 2026**

This is a research and architecture recommendation, not an implementation plan or evidence that any provider works acceptably on the user's foods. Scores below are comparative engineering judgements based on published scope and data shape. They are not measured UK coverage percentages unless explicitly stated.

## 1. Executive summary

The product thesis is correct. UK back-of-pack declarations normally contain energy plus fat, saturates, carbohydrate, sugars, protein and salt; fibre and most micronutrients are voluntary. A barcode database can therefore identify a product, but cannot by itself provide the 39-nutrient record the app wants. The defensible architecture stores identity evidence permanently, stores each nutrition resolution as a replaceable version, and permits `unknown` at item, nutrient and daily-total level.

Build the first version around three decisions:

1. **Local-first identity ledger and personal library.** Scan EAN/UPC with VisionKit, look up Open Food Facts for candidate identity, and require confirmation of name, brand, variant, pack, edible quantity and decisive states such as bone-in, drained and cooked. Store logs and versioned library entries locally; use Drive as an export/backup channel, not the live database.
2. **Measured label data and generic augmentation never overwrite each other.** On-device Vision OCR extracts the physical panel. Geometry, header classification and arithmetic reconciliation validate column binding. Exact package values win only for nutrients actually printed. Missing micronutrients may be filled from a named generic composition row only after deterministic retrieval and calibrated acceptance; otherwise remain unknown.
3. **Do not put an LLM in charge of nutrient truth.** Apple Foundation Models can parse an utterance into typed identity fields, but code resolves those fields to real records. Start adjudication with an auditable feature model/ranker and hard contraindication rules. Jev is early access, text-only, vendor-benchmarked and not yet an acceptable dependency.

HealthKit should receive combined scalar samples as a downstream convenience. The app's JSON remains canonical because HealthKit statistics discard item provenance, bounds and the food/supplement split.

## 2. Findings that decide the architecture

### The label gap is real

Current GB guidance defines the mandatory declaration as energy in kJ and kcal plus fat, saturates, carbohydrate, sugars, protein and salt in grams. Fibre, mono- and polyunsaturated fats, and eligible vitamins/minerals are voluntary. Salt is calculated as total sodium multiplied by 2.5, so the inverse conversion is **sodium = salt / 2.5**. [UK nutrition legislation information sheet](https://www.gov.uk/government/publications/nutrition-legislation-information-sources/nutrition-legislation-information-sheet--2) and [technical guidance](https://assets.publishing.service.gov.uk/government/uploads/system/uploads/attachment_data/file/595961/Nutrition_Technical_Guidance.pdf).

Calling these “seven mandatory nutrients” is reasonable if energy is counted once, despite its two displayed units: energy, fat, saturates, carbohydrate, sugars, protein and salt. The product must never add kJ and kcal; they are two representations of the same energy.

The sardine example is also directionally and numerically sound: USDA SR Legacy food 175139, “Fish, sardine, Atlantic, canned in oil, drained solids with bone”, reports calcium at about **382 mg/100 g**. The official FDC search page was not indexable in this research pass, so that figure was cross-checked through multiple FDC-derived displays; treat the number as source-derived rather than fresh laboratory evidence. More importantly, the row name encodes *with bone*, *in oil* and *drained solids*. Those are matching features, not decorative text.

### Identity and nutrition are separable, but not independent

Identity capture should preserve what could later select or reject a composition row. At minimum:

- barcode/GTIN and scan symbology;
- displayed product name, brand, sub-brand and variant;
- pack net quantity, drained quantity where applicable, unit count and serving language;
- food category and physical form;
- raw/cooked/reheated; cooking method where relevant;
- whole/fillet, bone-in/boneless, skin-on/skinless;
- packing medium and whether consumed or drained: oil, water, brine, sauce;
- fortified/unfortified and named fortificants;
- salted/unsalted;
- ingredient text and declared percentages, with the package image or crop hash;
- captured quantity, edible mass, household measure and the conversion used;
- capture time, locale, user corrections and evidence provenance.

The nutrition panel is also identity evidence: it can reject a candidate whose energy or macros are incompatible. But it cannot establish attributes it does not print. The system must therefore show the decisive identity attributes during confirmation.

## 3. Source comparison

Scores: **5** excellent for this role, **1** weak, **—** not established. “39-depth” means the likelihood of a useful broad micronutrient profile, not that every row contains every target.

| Source | UK product identity | 39-depth | Augmentation suitability | Access, size, licence and decision |
|---|---:|---:|---:|---|
| Personal library | 5 after confirmation | Depends on resolution | 5 for repeat use | Canonical for this user; exact version and evidence retained. |
| Open Food Facts (OFF) | 4, unmeasured | 1–2 | 1 for micronutrients; 4 for identity | Free read/write API and bulk data; ODbL database, attribution/share-alike obligations. Product reads 15/min/IP, search 10/min/IP; writes authenticated. v3.6 is current but actively changing. Best open barcode bootstrap and contribution target, not nutrient authority. [API documentation](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/) |
| GS1 UK GTIN Check | 4 for registered identity | 1 | 1 | Returns GTIN, brand, description, image URL, category, net content, unit and country of sale—not a broad nutrient record. Access key/terms required. [GS1 UK terms](https://www.gs1uk.org/terms-and-conditions/GTIN-check-service) |
| NIQ Brandbank / GS1 productDNA / GDSN | 5 potential | 2 for label fields | 2 | Commercial/partner access; NIQ claims 300+ attributes/product and rich nutrition over 50m products, but public UK pricing, caching rights and measured coverage were not found. Strong enterprise identity option only after a sample-data evaluation. [NIQ content licensing](https://nielseniq.com/global/en/products/content-licensing/) |
| FatSecret Platform UK | 4 vendor claim | 2–3, unverified | 2 | UK is among commercial regional datasets; barcode and caching are Premier features. UK pricing is quote-only. “90%+ global UPC/EAN coverage” and verification claims are vendor-supplied, not an independent UK audit. [Editions and pricing](https://platform.fatsecret.com/api-editions) |
| Edamam Food Database | 2–3, unverified | 3 (documents 28 searchable nutrients) | 1 | UPC and text search exist. Published terms sharply restrict caching; some plans cache only four macros and cancelled subscriptions require returned nutrition data to stop being used. That conflicts with retrospective, versioned local records unless bespoke terms are negotiated. [API](https://developer.edamam.com/food-database-api-docs), [terms/pricing](https://developer.edamam.com/edamam-nutrition-api) |
| Nutritionix | 2 for UK, unverified | 2 | 1–2 | Public documentation exists, but current public UK coverage, pricing, caching rights and 39-nutrient completeness could not be verified. Do not select without a contracted evaluation sample. |
| Spoonacular | 2, unverified | 3 advertised | 1–2 | Advertises branded products and many nutrient fields. Current UK coverage, provenance, caching terms and decision-grade pricing were not verified from primary material. |
| Nutritics | 3–4 potential | 5 potential | 4 potential | Vendor advertises >1m foods and up to 258 parameters from official/branded sources. Pricing and local persistence rights are quote-only. Technically closest commercial fit; validate exact row provenance, redistribution/caching and UK branded coverage. [Food Data API](https://www.nutritics.com/en/product/food-data-api/) |
| Chomp / Barcode Lookup | 2–3, unverified | 1–2 | 1 | Identity-oriented commercial aggregators. No primary evidence found for complete UK micronutrients or acceptable durable caching. |
| USDA Foundation Foods | 1 | 5 | 4 for generic foods | Analytical generic composition; CC0/public domain. April 2026 JSON is 459 KB zipped/6.5 MB expanded; CSV 3.7/32 MB. Excellent local candidate source, but US descriptions and fortification reduce UK equivalence. [downloads](https://fdc.nal.usda.gov/download-datasets/), [API/licence](https://fdc.nal.usda.gov/api-guide/) |
| USDA SR Legacy | 1 | 5 | 4, with age warning | Final 2018 release; JSON 12.3/205 MB, CSV 6.7/54 MB. Rich, stable and useful for hard distinctions such as bone-in sardines, but no longer updated. |
| USDA FNDDS | 1 | 4–5 | 3 | Survey foods and portions; latest published download is 2021–2023. JSON 3.7/64 MB; CSV 200 MB/1.6 GB. Better for reported dishes than exact UK products. |
| USDA Branded | 1–2 | 1–2 | 1 | Label-derived branded data, not full micronutrients. April 2026 JSON 195 MB/3.1 GB; CSV 428 MB/2.9 GB. Poor iPhone bundle choice and weak UK identity. |
| UK CoFID 2021 | 2 (generic UK names) | 5 | 5 primary UK source | 4.42 MB workbook; 3,003-ish/3,300-ish food counts are reported in different official/associated materials, so ingest and count the actual workbook before freezing a claim. Last update 2021. Main UK generic source and first candidate family. [GOV.UK dataset](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid) |
| CoFID API (Quadram/FN-NBRI) | 2 | 5 | 5 | A 2026 developer API is now advertised; exact terms, SLA and request limits must be checked before dependency. Prefer bundling the authoritative extract until those are confirmed. [developer tools](https://fnnbri.quadram.ac.uk/developer-tools/) |
| CIQUAL 2025 | 1–2 | 5 | 4 | French generic composition; 2020 had 3,185 foods × 67 components and explicit missing/trace states; a 2025 update exists. Requires source attribution. Useful European cross-check, not first choice for UK names. [2020 documentation](https://ciqual.anses.fr/cms/sites/default/files/inline-files/Table%20Ciqual%202020_doc%20Excel_ENG_2020%2007%2007.pdf) |
| Frida 5.4 (2025) | 1–2 | 5 | 4 | Danish generic table with extensive components. Current downloadable size/licence terms were not established in accessible primary pages; resolve before shipping. [documentation](https://frida.fooddata.dk/pdf/en-frida-5.4-dokumentation.pdf) |
| Canadian Nutrient File 2026 | 1–2 | 5 | 3–4 | 5,993 foods and up to 173 nutrients; open Canadian government licence. Generic, sometimes fortified for Canada. Good cross-check; not UK authority. [Health Canada](https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/canadian-nutrient-file-about-us.html) |
| AUSNUT 2023 | 1–2 | 4 | 3 | 3,741 foods × 58 nutrients; complete 16-file download 11.3 MB. Includes recipes and supplement profiles; regional mismatch. [FSANZ data files](https://www.foodstandards.gov.au/science-data/food-nutrient-databases/ausnut/data-files) |
| EuroFIR FoodEXplorer | 2 | 5 | 4 | Harmonised gateway across ~40 databases. Membership, national-source terms and publication approval apply; not a frictionless redistributable app dataset. [FoodEXplorer](https://www.eurofir.org/our-tools/foodexplorer/) |
| Open Food Repo | 1 for UK | 1–2 | 1 | Research release described ~21,000 Swiss-market items. Current operational status and terms were not established well enough to recommend. |

No legitimate public nutrition/product feed was found for Tesco, Sainsbury's, Ocado, Waitrose, M&S, Asda or Morrisons. Retailer pages and private/internal APIs are not permission to reuse data. Do not scrape. Brandbank/GDSN/retailer partnership conversations are the legitimate route.

### Recommended source stack

1. **Identity:** personal library → OFF exact GTIN → optional GS1 UK identity check → user-defined product.
2. **UK generic composition:** CoFID first.
3. **Gap/cross-check candidates:** USDA Foundation/SR/FNDDS, then CIQUAL/Frida/CNF/AUSNUT where the food and preparation genuinely correspond.
4. **Commercial trial, not dependency:** evaluate Nutritics and NIQ Brandbank on the labelled UK corpus. Reject any contract that prevents storing a resolved version for historical reproducibility.

## 4. Capture technologies

### Barcode

Use **VisionKit `DataScannerViewController`** for the primary iOS 17 UI. It provides live camera handling, guidance, highlighting, focus and zoom; supports selected `VNBarcodeSymbology` values and quality/multiple-item options. For grocery goods enable EAN-13, EAN-8, UPC-E and ITF-14, and normalise UPC-A represented inside EAN-13. [Apple scanner guide](https://developer.apple.com/documentation/visionkit/scanning-data-with-the-camera)

Use AVFoundation only if the product needs a fully bespoke capture session, frame pipeline or device control. `AVCaptureMetadataOutput` exposes the same essential decoded payload and symbology but leaves the UX to the app. [Apple machine-readable types](https://developer.apple.com/documentation/avfoundation/machine-readable-object-types)

Apple publishes capability and API behaviour, not comparative grocery-barcode accuracy. Do not claim one framework is more accurate without the app's own device/corpus benchmark. For rapid repeat scanning: restrict symbologies, debounce identical codes, provide haptic success, keep the session alive, and require a deliberate “log again” action to prevent duplicate entries.

### Text and voice

The parser output is an *identity query*, never nutrition:

```text
"three boiled eggs and a tin of sardines in olive oil, drained"
  -> [{foodTerms:["egg"], count:3, preparation:["boiled"]},
      {foodTerms:["sardines"], count:1, container:"tin",
       packingMedium:"olive_oil", consumedState:"drained"}]
```

On iOS 17–25, retain `SFSpeechRecognizer`, require on-device recognition only when `supportsOnDeviceRecognition` is true, and use `contextualStrings` or a custom language model for library foods, brands, units and phrase templates. Apple warns that forced on-device recognition can be less accurate and documents availability/duration limits for the older service. [Speech request](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest) and [on-device requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)

On iOS 26, prefer `SpeechAnalyzer` + `SpeechTranscriber`: Apple states that the new model runs on-device, is faster/more flexible, supports live and long-form use, and uses downloadable model assets. Those are Apple claims, not food-dictation accuracy results. [WWDC25 session](https://developer.apple.com/videos/play/wwdc2025/277/)

Always display parsed quantity/unit/state chips before resolution. Fractions, homophones (“four/for”), decimals, “g” versus “ml”, and brand names are high-risk. Normalise UK terms through a bidirectional concept lexicon (courgette/zucchini, rocket/arugula, coriander/cilantro) while retaining the user's original words.

## 5. OCR — two separate products

### 5.1 Printed nutrition panels

#### Recommendation

Start on-device with Vision, not a vision LLM:

1. Capture a document crop plus optional second/third crop; reject blur, glare, clipped headers or severe perspective.
2. Run accurate `VNRecognizeTextRequest`/`RecognizeTextRequest` with British English, language correction and food custom words.
3. Preserve every text candidate, confidence and bounding box.
4. Detect header bands and build geometric columns from x-coordinates; do not flatten the OCR to a string first.
5. Classify columns by header semantics: `per 100 g/ml`, `per serving/unit`, `%RI`/reference intake.
6. Parse rows as a hierarchy (`fat > saturates`, `carbohydrate > sugars`), not additive peers.
7. Keep kJ and kcal as alternative energy representations and cross-check their conversion.
8. Run deterministic arithmetic reconciliation. Refuse unresolved layouts.
9. Show the original crop beside an editable table, emphasising every numeric value and its basis. Save only after explicit confirmation.

Vision runs on device and returns text, confidence and bounding boxes. Apple cautions that boxes are approximate, so geometry needs tolerance and visual confirmation. Apple publishes no measured accuracy for nutrition panels or handwriting. [Vision OCR](https://developer.apple.com/documentation/vision/recognizing-text-in-images) and [bounding-box caveat](https://developer.apple.com/documentation/vision/vnrecognizedtext/boundingbox%28for%3A%29)

iOS 26 document recognition may improve structure extraction, but it still needs the same domain validator; it is not evidence that a cell was bound to the right header.

#### Arithmetic validator for the reference panel

For each nutrient row with per-100 and per-serving values, estimate serving mass:

`m_i = 100 × servingValue_i / per100Value_i`

Use interval arithmetic for rounded values. A displayed value at precision `d` represents roughly `v ± 0.5 × 10^-d`, except `<x`, which is `[0,x)`. The candidate serving mass passes when:

- at least four independent ordinary rows support it;
- the robust median is within **±5% or ±0.5 g**, whichever is larger, of the pack-derived serving mass;
- at least 80% of usable rows' rounding intervals overlap the predicted per-serving value;
- kcal and kJ agree within ordinary label rounding after conversion;
- `%RI` values reconcile against the statutory RI constants and are never treated as product amounts.

For the example, 100 g / 20 = 5 g per twist; fat 26 g × .05 = 1.3 g and 499 kcal × .05 = 24.95 kcal. “3 twists” is therefore 15 g. Protein 0.75 g may display as 0.7 or 0.8 depending on the manufacturer's rounding policy; this is why interval reconciliation is safer than string equality.

These thresholds are proposed engineering starting points, not published standards. Tune them on a labelled UK-panel corpus. Do not auto-accept a table solely because rounded numbers happen to reconcile; header recognition and row identity must also pass.

#### Bounds and conversions

- Store `<0.5 g` as `{lower:0, lowerClosed:true, upper:0.5, upperClosed:false}`, not 0 or 0.5.
- For sums, sum lower and upper endpoints. Exact + upper-bounded remains upper-bounded. Unknown input makes the complete total unknown, though known subtotal and bounds may still be reported.
- Convert salt to sodium by dividing by 2.5; store the source as salt and the deterministic transform/version.
- Normalise per 100 ml separately from per 100 g. Never convert volume to mass without a named density and provenance.
- Preserve “as sold” versus “as prepared”, drained basis and serving definition.

#### Recipe reconstruction

Declared ingredient percentages can constrain a recipe but usually do not identify the full recipe. In the reference product, butter 28%, Parmesan 11%, milk powder and garlic 1% establish at least 40% of mass; the unquantified remainder, water loss, ingredient variants and manufacturing process remain unknown. EuroFIR's method applies yield at recipe level and retention at ingredient level, and explicitly describes results as approximations. [EuroFIR calculation guideline](https://www.eurofir.org/wp-admin/wp-content/uploads/2015/12/EUROFIR-RECIPE-GUIDELINE_FINAL.pdf)

Use recipe reconstruction only when quantified ingredients cover a high share of mass and the unresolved remainder cannot dominate the target nutrient. It may beat a generic analogue for a distinctive, heavily quantified recipe; otherwise use it as a cross-check or bounded estimate, not measured truth. Store each reconstructed nutrient independently because one recipe may estimate calcium well and iodine poorly.

### 5.2 Handwritten lists

Run a separate pipeline:

1. on-device Vision line detection and OCR;
2. geometry-based line ordering;
3. parse exactly one or more item/quantity pairs per line;
4. library/database candidate resolution;
5. mandatory review screen with original line crop, resolved item, amount and unit;
6. no write until every line is accepted, edited or explicitly skipped.

Cloud fallbacks support handwriting—Google Cloud Vision, Azure Document Intelligence and Amazon Textract all document it—but none publishes a directly comparable accuracy result for this food-list task. Google accepts a handwriting language hint; Azure labels Latin handwritten lines; Textract returns confidence and recommends task-specific thresholds. [Google handwriting OCR](https://docs.cloud.google.com/vision/docs/handwriting), [Azure layout](https://learn.microsoft.com/en-us/azure/ai-services/document-intelligence/prebuilt/layout), [Textract best practices](https://docs.aws.amazon.com/textract/latest/dg/textract-best-practices.html)

Therefore no provider wins on published accuracy. Benchmark them on the user's real print/cursive mix before adopting a cloud path. Score character error rate, exact numeric token accuracy, exact unit accuracy, line pairing accuracy and end-to-end corrected-entry time. Numeric tokens get stricter handling: confusable characters (`O/0`, `l/1`), missing decimals and ambiguous `g/ml` always require visual confirmation. A ten-line review should support keyboard traversal and “accept all unchanged” only after each numeric token has been highlighted—not hidden behind one global confirmation.

Images stay on device in the default path. A cloud fallback must be a separate opt-in action that names the provider and sends only the cropped panel/list image. Task C adjudicators receive text/features, never images.

## 6. Personal library and storage

The hypothesis is plausible but unverified: a 40–60-item library could dominate entries for a single person. Instrument only counts such as distinct confirmed identities and repeat-hit rate; do not upload behavioural analytics.

Resolution order:

1. exact barcode or stable library alias;
2. exact normalised name plus decisive state;
3. ranked library candidates using lexical match, compatible state, frequency and recency;
4. user selection when more than one remains;
5. external identity lookup or generic candidate retrieval;
6. user confirmation creates a new immutable library version.

Preferences such as “full-fat dairy” are **ranking priors, never silent filters**, unless the user explicitly creates a hard rule. The UI should say “ranked first because you usually choose full-fat” and keep alternatives visible. Frequency/recency may break ties only after hard identity compatibility.

### Storage decision

Use a local database as the live store. SwiftData is adequate for tens or hundreds of personal entries and gives typed models, indices, unique constraints and persistent history. A separately generated SQLite/FTS5 database is better for thousands of immutable composition rows and predictable fuzzy/prefix search. Recommended split:

- SwiftData: captures, products, product versions, log entries, user preferences and resolution versions;
- read-only SQLite + FTS5: reduced CoFID and selected generic composition tables;
- optional compact embedding index only if lexical/category retrieval fails in the measured evaluation. At this scale, embeddings are not justified by default.

Do not use one Drive JSON file as a database. Keep local transactions authoritative and export an append-only operation log plus periodic compact snapshot to the existing selected Drive folder. Each operation has UUID, device ID, Lamport counter/timestamp, entity/version ID and payload hash. Merge independent additions; surface concurrent edits of the same logical product as a user-resolved conflict. Never last-write-wins nutrition silently.

Drive exposes modified time, checksum and a monotonically increasing file version, but those are detection aids, not domain merge semantics. Retain the existing narrow `drive.file` permission. [Drive file resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files) and [scope guidance](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)

## 7. Model-layer recommendation

### Task A — extraction

Preferred on iOS 26: Apple Foundation Models guided generation into a small typed `CapturedItemQuery`. The model is on-device, supports constrained Swift types, and has a 4,096-token session context. Availability depends on device/Apple Intelligence state and the system model can change with OS updates, so keep deterministic parsing and manual entry as fallbacks and regression-test each supported OS model. [guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation), [context](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)

On iOS 17–25: deterministic tokenizer/grammar first; optionally a cloud structured-output model behind explicit consent. A local llama.cpp grammar can guarantee syntax on capable devices but adds model distribution, memory, energy and update burden without evidence it improves this small extraction task.

Enforcement pattern:

- output fields are quantities, units, free identity terms and enumerated preparation hints;
- no nutrient fields exist in the generation schema;
- generated strings query the library/datasets;
- only retrieved stable IDs can enter a resolved log;
- deterministic validation rejects impossible or ambiguous quantities;
- user sees and confirms the mapping.

### Task B — vision

Default: Apple Vision OCR + deterministic geometry/arithmetic. Cloud document OCR or a vision LLM is an evaluation-only fallback until measured on the panel/list corpus. A vision LLM may be useful as a second independent parser, but never as the sole evidence and never to generate missing nutrients. Images cross the device boundary only in this task and only after explicit opt-in.

### Task C — adjudication

Start with a gradient-boosted classifier or logistic ranker over explicit features, not an LLM:

- exact/normalised category and species;
- hard state compatibility (bone, skin, fortified, packing medium, drained, raw/cooked);
- ingredient token and quantified-ingredient overlap;
- energy/macro residuals after basis conversion;
- salt/sodium consistency;
- product form and pack/portion plausibility;
- regional/source compatibility;
- library frequency/recency as weak priors;
- missing decisive fields and candidate-source quality.

This is auditable, cheap, on-device and trainable from the labelled matching set. Hard contradictions remove candidates before scoring. The output is `{candidateID | decline, calibratedProbability, reasonCodes, modelVersion}`.

Jev supports typed probabilistic decisions, claims 70–500 ms, $0.042/million input tokens and cardinality up to 255, but as of 15 September 2026 it is **early access**, text/state input only, and its calibration/intelligence results are vendor-designed and vendor-reported. It guarantees type validity, not that a sardine candidate is semantically correct. Treat it as an experimental challenger after the baseline, never as an architectural dependency. [TypeSafe announcement](https://typesafe.ai/blog/introducing-system-one-models-and-jev)

Schema-constrained LLM output similarly guarantees well-formedness, not correctness. Independent research has repeatedly treated those as separate properties; the system must validate identity and macro agreement outside the model.

### Calibration and threshold

Create a labelled corpus of at least 300 distinct decisions before treating probabilities as meaningful; aim for 1,000+ with oversampled hard negatives. A single user's 40–60 foods cannot populate reliable probability bins alone, so bootstrap with synthetic pairings and public products, then reserve the user's confirmed cases for a final, untouched evaluation.

Report precision among accepted matches, recall/coverage, decline rate, top-k recall, Brier score, log loss, ECE with uncertainty and a reliability diagram. Use grouped splits by product family/brand so near-duplicates do not leak between train and test. Modern models can be poorly calibrated; post-hoc temperature, Platt or isotonic calibration must use a held-out set. [Guo et al., ICML 2017](https://proceedings.mlr.press/v70/guo17a/guo17a.pdf)

Set the production threshold from harm, not convention. Initial rule: auto-suggest only at calibrated `p ≥ 0.995`, with **zero hard contradictions**, macro reconciliation passing, and the margin over runner-up ≥0.20. Even then, require user confirmation for a new mapping. Below threshold, show candidates or decline. Once validation yields enough rare-error evidence, optimise expected loss with a wrong match cost at least 20× a declined match; publish the resulting threshold and confidence interval.

## 8. Full resolution chain

```text
Barcode / panel photo / handwritten list / text / voice
  -> capture evidence retained
  -> structured identity query (no nutrients)
  -> exact personal-library hit?
       yes -> confirm quantity/state -> immutable log referencing library version
       ambiguous -> show candidates -> user selects or declines
       no -> barcode identity lookup / deterministic generic retrieval
  -> physical-panel OCR available?
       yes -> geometry + arithmetic checks -> user verifies -> measured/bounded values
       fail -> retain image/candidate, save no OCR value
  -> retrieve 3–10 real generic candidates
  -> remove hard contradictions
  -> feature scorer + calibrated probability
       pass -> user confirms candidate and decisive attributes
       fail -> unknown; optional recipe reconstruction as separate estimate
  -> per-nutrient merge without overwriting evidence
  -> save resolution version and library alias
  -> export canonical JSON
  -> optionally write combined exact scalar nutrients to HealthKit
```

Deterministic retrieval should use category crosswalk + BM25/FTS lexical search first, preparation/state filters second, ingredient overlap third. Add embeddings only to raise measured top-10 recall. Keep 3–10 candidates for adjudication; too many near-duplicates harm both review and probability calibration.

## 9. Data model and merge policy

### Core entities

```json
{
  "capturedIdentity": {
    "id": "uuid",
    "originalText": "...",
    "barcode": {"value":"...", "symbology":"ean13"},
    "name":"...", "brand":"...", "variant":"...",
    "pack":{"net":{"value":100,"unit":"g"},"drained":null,"count":20},
    "states":{"preparation":"as_sold","bone":"unknown","packing":"none","consumed":"as_sold","fortification":"unknown"},
    "ingredients":{"text":"...","declaredPercentages":[]},
    "evidence":[{"kind":"panel_photo","sha256":"...","capturedAt":"..."}]
  },
  "foodResolution": {
    "id":"uuid", "identityID":"uuid", "version":3,
    "candidate":{"dataset":"cofid-2021","recordID":"..."},
    "decision":"accepted", "probability":0.997,
    "featuresVersion":"match-v1", "confirmedByUser":true
  },
  "nutrients": {
    "calcium": {
      "state":"augmented", "value":382, "unit":"mg_per_100_g",
      "source":{"dataset":"usda-sr-legacy","recordID":"175139","release":"2018"},
      "matchResolutionID":"uuid", "probability":0.997,
      "transform":null
    },
    "sugar": {
      "state":"bounded", "interval":{"lower":0,"upper":0.5,"upperClosed":false},
      "unit":"g_per_serving", "source":{"kind":"verified_panel_ocr"}
    }
  }
}
```

### Source class

Use `food`, `fortified_food`, `supplement`, `drink`, `water`. “Fortified food” needs its own class because its declared fortificant values may be measured while intrinsic micronutrients are augmented. `drink` captures beverages whose density/basis differs; plain water remains separate for useful hydration accounting. Classification describes the item, not confidence.

Supplements should be templates with an expected schedule and explicit daily `taken`/`skipped`/`unconfirmed` events. Never default a scheduled supplement to taken. Label amounts are measured declarations, not exact chemical assays: official tolerance guidance recognises raw-material variation, analytical error, overage, degradation and shelf-life effects. [EU/UK tolerance guidance](https://assets.publishing.service.gov.uk/government/uploads/system/uploads/attachment_data/file/212935/EU-Guidance-on-Tolerance.pdf). Preserve label date/lot when available; do not turn the record into dosing advice.

### Per-nutrient merge

The hierarchy is conditional, not a whole-record priority:

1. user-verified current physical panel, for that printed nutrient and declared basis;
2. exact-product database label value, if current/version-compatible;
3. reconstruction estimate, only where quantified ingredients and method support it;
4. accepted generic composition value;
5. unknown.

A physical package wins over a same-barcode database value because it is contemporaneous evidence of the item in hand, but only after the panel and basis are verified. A barcode can be reused through reformulation; store capture date, image hash, database revision and discrepancy rather than silently replacing either value.

Never copy generic micronutrients into a measured state. Per nutrient use:

- `measured`: declared/observed for the exact item and basis;
- `augmented`: composition estimate with source row and calibrated match probability;
- `bounded`: interval, with provenance; bounds may also be measured or augmented;
- `unknown`: no defensible value.

Daily aggregation returns an interval and completeness, not one falsely exact scalar:

```json
{
  "calcium": {
    "unit":"mg",
    "knownSubtotal":812.4,
    "lowerBound":812.4,
    "upperBound":813.9,
    "hasUnknownContribution":true,
    "bySourceClass":{"food":610.0,"fortified_food":102.4,"supplement":100.0,"drink":0.0,"water":0.0},
    "byEvidenceState":{"measured":310.0,"augmented":502.4,"boundedUpperWidth":1.5,"unknownItemCount":1}
  }
}
```

If `hasUnknownContribution` is true, this is a known subtotal and bound over known/bounded inputs—not a bound on the true whole-day total. UI language: “at least 812.4 mg accounted for; one item has unknown calcium”, not “812.4 mg total”.

Historical log entries reference immutable identity and resolution versions. Re-resolution creates a new resolution version and a derived daily-summary version with `supersedes`, algorithm version, source releases and timestamp. Preserve the prior result so downstream coaching changes are explainable.

## 10. HealthKit boundary

Apple currently documents 39 dietary quantity types: energy; carbohydrate; protein; total, saturated, mono- and polyunsaturated fat; fibre; sugar; cholesterol; vitamins A, B1/thiamin, B2/riboflavin, B3/niacin, B5/pantothenic acid, B6, B7/biotin, B9/folate, B12, C, D, E and K; calcium, chloride, iron, magnesium, phosphorus, potassium, sodium, zinc, chromium, copper, iodine, manganese, molybdenum and selenium; water; caffeine. The repository's `NutritionQueryCatalogue` matches this list. Apple documents no additions or deprecations among these in the current index. [Apple nutrition identifiers](https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers)

Canonical app units should remain those already used here: kcal; g for macros/fibre/sugar; mg for cholesterol, B1/B2/B3/B5/B6/C/E and most minerals; µg for A, B7, B9, B12, D, K, chromium, iodine, molybdenum and selenium; ml for water; mg for caffeine. HealthKit itself stores quantities convertible through `HKUnit`; these are app/export canonical units, not a claim that Apple mandates one display unit.

Food can be represented as an `HKCorrelation` of type `.food` containing dietary quantity samples, with `HKMetadataKeyFoodType` naming the food. Apple permits app-specific metadata keys on HealthKit objects. [food correlations](https://developer.apple.com/documentation/healthkit/hkcorrelationtypeidentifier/food), [metadata](https://developer.apple.com/documentation/healthkit/metadata-keys)

However, `HKStatisticsQuery`/`HKStatisticsCollectionQuery` returns sums/averages and optionally HealthKit **source app**, not arbitrary metadata grouped values. The source-class split therefore does not survive statistics aggregation. A consumer would have to read individual samples/correlations, inspect custom metadata and re-aggregate. [HKStatistics](https://developer.apple.com/documentation/healthkit/hkstatistics)

Decision: the app's local/versioned export is the system of record; HealthKit is a downstream combined-total output. Unknown nutrients are omitted from HealthKit, because HealthKit has no null or interval value. That omission is indistinguishable from an unlogged zero to a statistics-only consumer, so the app must never use HealthKit alone to claim completeness. Do not write upper bounds as exact samples.

Use deterministic `HKMetadataKeySyncIdentifier`/`SyncVersion` per log-nutrient sample. Updating a log means write the higher sync version for samples the app owns; deletion is limited to objects this app saved. Combined HealthKit totals also risk double counting when another app writes the same food, so the existing report must continue selecting this app's exact source rather than aggregating all sources. [HealthKit store deletion boundary](https://developer.apple.com/documentation/healthkit/hkhealthstore/delete%28_%3Awithcompletion%3A%29-17hzm)

A downstream coach currently reading source-filtered nutrition totals from HealthKit would need to migrate to the richer JSON to gain item provenance, bounds and source-class decomposition. During migration export both, include reconciliation totals, and flag any nutrient where the HealthKit exact-scalar subtotal differs from the JSON's exact writeable subtotal.

## 11. Offline and security architecture

- All capture, library hits, OCR, parsing and local generic search work offline.
- Unknown barcodes create local identities immediately; OFF contribution is a later explicit action.
- Cloud adjudication or OCR unavailability yields `measured only; augmentation pending`, never a guessed value or background retry without visibility.
- Bundle CoFID and a deliberately reduced generic candidate set, not the 3.1 GB USDA branded JSON. Store only required identifiers, names/synonyms, categories, states, 39 nutrient columns, provenance and portions.
- Dataset updates are signed/versioned manifests installed side-by-side; existing resolutions keep their old release until explicitly re-resolved.
- Do not embed USDA/commercial API secrets in a public iOS binary. OFF reads need no secret. USDA keys in a shipped app are recoverable; either use bundled data, ask the single user to supply their own key in Keychain, or introduce a minimal key-hiding proxy only if scale/terms require it.
- No server is needed for the single-user architecture. At 1,000 users, a backend becomes useful for licensed source access, key protection, dataset-delta distribution and aggregate model evaluation—but it must not become the only copy of the person's logs.

The current OFF full-dump byte sizes and a maintained UK-only subset size could not be verified because the dump host did not expose metadata through the available research tooling. Do not put an estimated number in a build decision. Measure the chosen artefact with `Content-Length`/download and record its date before implementation.

## 12. Validation programme

### Match-quality evaluation

Build a gold set with two labels per case: correct composition record(s), or “none acceptable”. Include at least:

- 100 recurring personal items;
- 100 ordinary UK packaged/whole foods;
- 100 deliberate hard-negative families;
- at least 50 reformulations/near-duplicate variants;
- multiple candidate sources and preparation states.

Hard negatives and their blocking attribute:

| Failure | Required discriminator |
|---|---|
| bone-in vs boneless fish | bone state / whole versus fillet |
| fortified vs unfortified cereal or plant milk | fortification and declared fortificants |
| wholemeal vs white flour/bread | grain refinement |
| skin-on vs skinless poultry | skin state |
| drained vs undrained canned food | consumed/drained state and drained mass |
| in oil vs brine/water | packing medium and whether consumed |
| salted vs unsalted | salt state |
| raw vs cooked | preparation method and yield basis |

Primary gate: **accepted-match precision**, with a one-sided 95% confidence lower bound. Target ≥99.5% point precision and no catastrophic hard-negative acceptance; report decline rate separately. Also report per-nutrient absolute/relative error on wrong matches, weighted by the magnitude of harm—not only row accuracy.

### OCR evaluation

Create 100+ real UK panels across flat, curved, glossy, crumpled, small-font and multi-column packages, plus 100+ handwritten lists from the intended writer(s). Ground truth every character, cell, row, column basis, bound and serving conversion.

Printed metrics: numeric cell exact accuracy; row/header binding accuracy; full-table exact accuracy; false-save rate; arithmetic-check detection rate; corrected seconds/panel. Handwriting: exact item, exact numeric token, exact unit, line pairing, end-to-end corrected entry and false-save rate. Evaluate Vision, cloud OCR and a vision model on the identical crops; publish privacy/cost separately.

### Completeness and provenance

For every item/day report the proportion of 39 nutrients in measured, augmented, bounded and unknown states. Never publish “X% complete” without the state split. Verify whole-food candidates against CoFID descriptions and packaged foods against the physical package, including basis and current formulation.

## 13. Phased delivery

### Phase 0 — corpus and contracts

Freeze schemas, create the labelled hard-negative set, ingest/version CoFID, and measure OFF coverage on the user's real pantry. Obtain sample terms/data from any commercial candidate. No provider selection before this evidence.

### Phase 1 — minimum version that beats the status quo

Local product/log store; VisionKit barcode; exact personal-library reuse; OFF identity lookup; manual identity/state/quantity confirmation; manual panel entry with bounded values; CoFID search with **user-selected** generic match; canonical JSON with provenance/source split; no automatic adjudication. This already preserves identity and makes augmentation revisable.

### Phase 2 — verified printed OCR

On-device panel capture, geometry, nested rows, salt conversion, serving derivation, interval arithmetic, self-validation and side-by-side confirmation. Unknown/failed OCR remains explicit.

### Phase 3 — text/voice and handwriting

On-device speech, typed extraction, library short-circuit, UK synonym vocabulary, handwritten batch capture and mandatory numeric review.

### Phase 4 — calibrated matching

Deterministic retrieval, hard rules, feature ranker, held-out calibration and threshold. Recipe reconstruction remains independently labelled and only fills supported nutrients.

### Phase 5 — HealthKit writes and retrospective re-resolution

Explicit user-invoked HealthKit save, sync identifiers/versions, deletion/amendment UX, combined scalars only; source-rich JSON remains canonical. Add opt-in dataset/model re-resolution with before/after diff.

### Phase 6 — optional commercial/cloud challengers

Run Nutritics/Brandbank, cloud OCR and Jev as challengers against the fixed corpus. Adopt only if they improve the chosen outcome under acceptable persistence, privacy and fallback terms.

## 14. Cost scenarios

At 15 new capture events/day, 30 days is 450 events. The personal library should make most repeat entries local; cloud figures below deliberately assume the pessimistic case of one external operation per event.

| Scenario | One user/month | 1,000 users/month | Notes |
|---|---:|---:|---|
| On-device OCR + bundled CoFID + OFF reads | £0 marginal | £0 provider fee, operational limits apply | OFF per-user product reads fit 15/min if not bursty; bulk/server use should use dumps and respect ODbL. |
| Google Document Text OCR | First 1,000 units/month free, then $1.50/1,000 | about $674 after first 1,000 | Current published list price; storage/network/tax excluded. At 450 pages, one user remains inside free tier. [pricing](https://cloud.google.com/vision/pricing) |
| Jev adjudication | effectively <$0.01 at small text payloads | likely low dollars, but cannot be decision-costed reliably | Vendor lists $0.042/million input tokens, free output; early-access availability and payload tokenisation/terms remain blockers. |
| USDA API | $0 | $0 | CC0, default 1,000 requests/hour/IP; a public key cannot safely ship in source. Bundle extracts or proxy at scale. |
| FatSecret UK / Nutritics / NIQ Brandbank | quote required | quote required | Do not estimate. Obtain rights for caching/version retention and a UK sample before architecture commitment. |
| Azure/AWS OCR | not costed | not costed | Current accessible price pages did not expose stable numeric UK rates suitable for citation; request calculator quotes at implementation time. |

Vision-capable LLM image cost depends on model, resolution/tokenisation and output. It cannot be honestly calculated from “15 lookups” alone. Measure the exact reference images against a frozen model/price before selecting it.

At 1,000 users, cost is less important than provider terms, key security, shared-IP rate limits, deletion/export obligations and reproducible versioning. The architecture should distribute licensed/open dataset snapshots and reserve online calls for genuinely new identities or opt-in OCR.

## 15. Risk register

| Risk | Severity | Mitigation / gate |
|---|---|---|
| Confident wrong generic match | Critical | Hard state exclusions, macro reconciliation, calibrated threshold, user confirmation, explicit decline, hard-negative test set. |
| OCR binds RI/serving to per-100 column | Critical | Header semantics + geometry + arithmetic intervals; refuse unresolved layouts; side-by-side review. |
| Weight OCR error silently scales all nutrients | Critical | Highlight every numeric/unit token; plausible-range and serving/pack reconciliation; mandatory confirmation. |
| Reformulation under same barcode | High | Physical panel precedence per nutrient, evidence date/hash, source revision, discrepancy and immutable versions. |
| Missing values appear as zero | Critical | `unknown` state throughout; known subtotal language; omit from HealthKit and never infer completeness there. |
| Bounds collapsed to scalars | High | Interval type and interval aggregation; never write bounds to HealthKit as exact quantities. |
| Frequency preference selects wrong variant | High | Prior only after compatibility; visible reason and alternatives; easy override. |
| Source-class split lost in HealthKit | High | Canonical local/Drive JSON; HealthKit downstream combined values only. |
| Double counting in HealthKit | High | Source-filtered reads, stable sync identifiers, user-visible write/amend boundary. |
| Commercial licence prevents history/cache | High | Contract gate before integration; open/local fallback; never make log interpretation subscription-dependent. |
| Cloud image/privacy exposure | High | On-device default; cropped, explicit opt-in; provider disclosure; no silent retry. |
| Recipe reconstruction looks measured | High | Separate provenance/state, coverage constraints, yield/retention versions and uncertainty. |
| Dataset/model update rewrites history | High | Immutable resolutions, explicit re-resolution, before/after diff and source release IDs. |

## 16. Open questions and how to resolve them

1. **Actual UK barcode coverage:** no provider publishes an independently measured pantry-relevant result. Scan 300–500 real UK items and score identity fields and freshness separately from nutrition.
2. **Current OFF dump/UK-subset sizes:** measure the actual dated artefacts before deciding bundle/server strategy.
3. **CoFID exact row/39-field completeness:** ingest the 2021 workbook and compute field-level coverage; do not infer it from total component count.
4. **Nutritics/NIQ/FatSecret commercial rights and prices:** request written terms for on-device cache, derived mappings, historical versions, attribution, termination and 1,000-user use.
5. **Handwriting and panel OCR accuracy:** no published benchmark matches this capture distribution. Run the proposed corpus evaluation.
6. **Jev calibration:** requires early access and a frozen independent labelled set. Vendor workflow benchmarks do not answer food-match calibration.
7. **Apple Foundation Models food parsing:** run exact-structure and semantic tests on supported hardware/OS versions, including model-update regression.
8. **User's distinct-food/repeat distribution:** measure locally for 6–8 weeks; this validates library-first economics without analytics.
9. **Supplement label error by product class:** official tolerance guidance establishes variability but not a universal realised-error rate. A decision-grade number would require product/lot-specific assay literature or testing.
10. **Physical HealthKit presentation:** Apple documents correlations and types, but the exact Health app UI for 39-nutrient food correlations should be checked on a real device only after explicit authorisation; simulator/build evidence is insufficient.

## Decision

Proceed with a local-first, evidence-preserving MVP. Use OFF for identity bootstrap, CoFID as the first UK generic composition source, VisionKit/Vision for capture, and explicit human confirmation for every new product-to-generic mapping. Defer automatic matching, cloud OCR, commercial sources and HealthKit writes until their own labelled evaluations and permissions are complete. The essential product advantage is not “more filled cells”; it is that every number can say what was measured, what was inferred, why it was inferred, and when the system declined to infer it.
