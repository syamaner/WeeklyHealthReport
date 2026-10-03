# Gemini nutrition extraction evaluation v1

This is an eval-only experiment authorised on 28 September 2026. It does not change the app, admit nutrients, or authorise later runs. Source discovery is evaluated separately in `../GeminiGroundingEvaluation`.

## Architecture gate and invariants

The frozen corpus owns dated public-source facts and synthetic challenges. A pure scorer compares provider-neutral extraction records. The Gemini adapter owns request shaping and response projection; the collector owns Keychain, transport and private journalling. Transport is injected for contract tests. Neither provider types nor networking enter the scorer. No Swift, HealthKit or food-history inputs are involved.

Versioned invariants: preserve declared value, operator, unit, denominator and preparation; unknown is not zero; percent is not grams; mass is not volume; never infer density, nutrients or edible yield. Reject a conflicting food variant and abstain when preparation/basis is ambiguous. A source URL or model-generated quote alone is not field-level proof. This experiment cannot establish formulation/pack identity or redistribution rights.

## Design frozen before collection

16 challenge cases: 12 development and 4 untouched holdouts. Development includes 6 real-page tasks from 3 manufacturer domains 2 synthetic panels, 2 descriptive soup tasks and 2 admitted CoFID cooked-meat tasks. Holdout tasks use 2 other manufacturer domains. Splits are source-disjoint, not food-family-disjoint. This is a small, deliberately difficult diagnostic set, not a representative benchmark; no population accuracy claim is justified.

Two conditions use the same prompt and schema:

- `panel`: a reconstructed factual transcription is supplied, without tools. This isolates extraction from retrieval; it does not test arbitrary HTML or OCR.
- `url`: only the selected public URL and requested food/fields are supplied, with Gemini URL Context. This tests retrieval plus extraction, conditional on correct source selection. It is not an end-to-end Google Search test.

The development run is capped at 20 POSTs (12 panel + 8 URL), no automatic retries. A failed/non-completed call stops collection. Holdouts are rejected by the collector. Cases, source facts, prompt and response schema are SHA-256 frozen before running. Gold and other cases never enter the request. Key comes from the authorised Mac Keychain item and is never written. Each attempt is journalled before POST and each completed projection saved before the next request. Raw envelopes, interaction IDs, page HTML and hidden reasoning are discarded. Output directories must be new and owner-only.

## Reference quality

`corpus-v1.json` contains factual numeric transcriptions checked against the selected public manufacturer pages on 2026-09-28 before provider collection. These are agent-reviewed references, not a second human annotation or nutritional truth. The supplied panels are reconstructed text, not archived HTML. Live pages and Google's cached URL context can differ. Every disagreement needs page review before attribution. In particular, the Alpro search snippet and opened page differed in micronutrient content; the opened UK page governs this reference. Graham's minimum fat percentage stays `>= 3.5 %`, never an exact grams-per-volume claim.

## Metrics and decision rule

Report request completion, schema/contract validity, tool retrieval metadata and exact case success separately. Field comparisons include state, value, operator and unit; case success additionally requires source, status, denominator and preparation. Track missing/extra fields, fabricated values for reference-unknown fields, and values emitted on abstention cases. Unknown instead of a supported value is a coverage failure, not fabrication. Evidence snippets require independent review; nonempty snippets are only a completeness check. A matching value without a supporting page is not verified extraction.

Advance only after all development cases meet the contract with no invented values, identity/preparation/basis errors, and source evidence reviewed. Then select a frozen candidate before running holdouts once. Any failure keeps this development-only. Even a pass requires a separate app admission design and broader dataset (more brands, languages, PDFs, inaccessible pages, conflicting/dated labels, recipes and malicious HTML).

Google documents [URL Context](https://ai.google.dev/gemini-api/docs/url-context) for selected-page extraction and [structured outputs with tools](https://ai.google.dev/gemini-api/docs/structured-output) as preview. Structured JSON does not guarantee semantic accuracy. URL Context can use indexed content before live fetch.

## Reproduce

```sh
python3 -m unittest discover -s Tools/GeminiNutritionExtractionEvaluation/tests -v
python3 Tools/GeminiNutritionExtractionEvaluation/evaluate.py --validate
python3 Tools/GeminiNutritionExtractionEvaluation/collect.py --keychain-service YOUR_SERVICE --max-requests 20 --output-dir /private/tmp/gemini-nutrition-new-run
python3 Tools/GeminiNutritionExtractionEvaluation/evaluate.py --replay /private/tmp/gemini-nutrition-new-run/replay.json
```

The last command reports the frozen development plan, retaining incomplete cases in the denominator. Unit tests use synthetic transport only. No Swift validation is necessary for these Python-only artefacts.

The user added descriptive lentil-and-tomato soup and 250 g cooked sirloin before freezing. The soup cases use the original [CSPI recipe](https://www.cspi.org/recipe/tomato-lentil-soup); its one-cup basis cannot be scaled to grams without further evidence. Sirloin controls use dated admitted local CoFID records with their resource hash. These are panel-only, not web-retrieval evidence. Generic descriptions require `representative` applicability and explicit recipe/cooking/lean-fat assumptions; a source record is never proof of the actual meal. Per-100-g cooked meat is scaled to the 250 g cooked portion by deterministic code, with separate expected totals. No raw-to-cooked yield is inferred. The provisional product policy is to offer a labelled representative estimate for confirmation.

## Candidate v2

The [v2 findings](pilot-findings-v2-2026-09-28.md) report 19/20 strict development passes, including all 8 fetched-document cases, plus two separately reviewed descriptive-food Search probes. `experiment-v2.md` records the pre-run architecture and request limit. All original v1 hashes remain unchanged; v2 has a separate contract. Source-document text is private and temporary; see the findings for reproduction limits. The four holdouts remain untouched because the development/evidence gate is not yet fully met.

## Latest: candidate v3

[V3 findings](pilot-findings-v3-2026-09-28.md): **20/20 development and 4/4 first holdout passes** after moving selected-source identity into an application-owned evidence envelope. The four extraction holdouts have now been used once; the earlier v1/v2 “untouched” statements describe those historical runs. No further tuning used their outputs. The separate discovery holdouts remain untouched.

The pure record resolver verifies one observed CoFID lead, flags one USDA numeric claim conflict and leaves two soup IDs unresolved. Safe routing is distinct from successful discovery coverage. This remains an eval prototype with 43 passing local tests and no app nutrition admission. See `experiment-v3.md` for the pre-run architecture/gates and the findings for source-text retention and reproduction limits.
