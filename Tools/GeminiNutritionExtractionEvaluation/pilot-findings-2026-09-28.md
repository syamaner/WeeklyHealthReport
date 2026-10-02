# Nutrition extraction pilot — 28 September 2026

Gemini can extract the tested nutrition facts when the evidence is available. Selected-page retrieval is uneven, and the output contract needs tightening before app integration. No app prompt or admission policy was changed.

## Frozen experiment and result

16 source-disjoint challenge cases: 12 development, 4 holdouts. All 20 planned development requests completed (12 supplied-panel, 8 selected-URL); no provider retries. Model `gemini-3.8-flash`, low thinking, 4,096 output-token cap, 55-second transport timeout, structured JSON. URL condition used URL Context only, not Google Search. The initial sandbox attempt could not read Keychain and made no provider request; the authorised host run then completed.

| Measure | Supplied panel | Selected URL |
| --- | ---: | ---: |
| Completed requests | 12/12 | 8/8 |
| Schema-valid JSON | 12/12 | 8/8 |
| Strict frozen case pass | 3/12 | 1/8 |
| Field state/value/unit matches, excluding operator* | 78/78 | 36/56 |
| Invented values for reference-unknown fields | 0 | 0 |
| Values emitted on expected-abstention cases | 0 | 0 |

*This is a post-run descriptive breakdown, not a replacement gate. Repeated questions over the same panels are correlated, and these denominators include unknown fields. The URL denominator retains the 20 fields missing because yoghurt/milk retrieval failed. All 36 returned URL nutrient records matched the reference state/value/unit; that is conditional performance, not overall web coverage. The strict case gate remains failed.

## What failed

- The model returned `operator: null` for 62 exact-value panel fields and 34 URL fields instead of the frozen `=` contract. Values, units and declared state were correct; bounds (`<`, `>=`) were preserved. This is a representation/prompt contract defect, not evidence of wrong nutrient numbers. Preserve this baseline; tighten the schema/prompt in a new candidate rather than silently rescoring null as equality.
- The explicitly selected CoFID sirloin record was conservatively labelled `representative` instead of `source_record` in n16. No exact-meal claim was made. The distinction needs clearer wording; an explicit choice of a population composition record still estimates a real meal.
- URL Context failed both Olympus tasks and the selected Graham's product page. It retrieved the Graham's homepage, which did not supply the required panel, and returned unavailable. The separately opened manufacturer product pages did contain the facts. Tool retrieval failures are coverage failures, not model fabrication.
- No URL citation annotations were returned in any structured response. Tool retrieval status and the model-written source URL/snippets are insufficient alone for production field provenance. Independent page checks support the McCain and CSPI values in this pilot; the app still needs an explicit evidence/admission design.

## The user's descriptive-food cases

- **“lentil and tomato soup”**: both conditions extracted the selected [CSPI recipe](https://www.cspi.org/recipe/tomato-lentil-soup) as a representative recipe, with its declared one-cup basis. This does not establish the user's recipe or exact nutrition.
- **250 g cooked soup**: both conditions stated that gram scaling was unavailable because the recipe has no declared cooked mass per cup. No density or recipe yield was invented.
- **“250g cooked weight sirloin”**: the supplied-record case selected cooked CoFID values, left them per 100 g, and explicitly identified the assumption: grilled medium-rare, lean meat only. The independent deterministic calculation correctly scaled those selected values by 2.5 (for example, 176 kcal becomes 440 kcal). That total applies to the representative record, not every possible sirloin preparation. This is panel evidence only; sirloin web retrieval was not tested.
- **Specified cooked sirloin record**: the same scaling passed, with the conservative applicability classification noted above.

The soup and sirloin tests therefore cover descriptive matching against a selected source, source-basis extraction, representative labelling and supported arithmetic. They do not prove free-text search-to-food matching end to end. The remaining product preference is whether to offer a labelled representative estimate for confirmation or ask for recipe details first; this pilot uses the former as a stated provisional assumption.

## Reference and evidence review

References were frozen before calls from public [Olympus](https://www.olympus-foods.co.uk/products/yogurt/greek-yogurt-10-fat.html), [Graham's](https://www.grahamsfamilydairy.com/our-products/grahams-milk/whole-milk/), [McCain](https://www.mccain.co.uk/home-chips-straight-cut/) and [CSPI](https://www.cspi.org/recipe/tomato-lentil-soup) pages, existing admitted CoFID resource facts, and synthetic controls. Holdout references use separate Odysea and Alpro sources. This is an agent-reviewed factual transcription, not a second human annotation or nutritional ground truth. Live pages and tool caches may drift. Synthetic prompt-injection resistance here is one explicit footer example, not a security benchmark.

The structured public/synthetic projection was reviewed before retaining `pilot-replay-v1.json`; no key, interaction ID, raw response, retrieved HTML or hidden reasoning is retained. `pilot-evidence-review-v1.json` records the page/panel review and replay hash. Reproduce the strict result with:

```sh
python3 Tools/GeminiNutritionExtractionEvaluation/evaluate.py --replay Tools/GeminiNutritionExtractionEvaluation/pilot-replay-v1.json
python3 -m unittest discover -s Tools/GeminiNutritionExtractionEvaluation/tests -v
```

The provider reported 65,852 total tokens across these 20 requests: 18,088 input, 9,785 output, 35,009 tool-use and 2,970 thought tokens; cached tokens 0. Provider charges were not read or estimated. `raw_prompt_token` is overlapping provider telemetry, not added to the total. This excludes assistant development/research tokens. Four extraction holdouts and the separate discovery holdouts remain untouched.

## Next bounded experiment

1. Tighten the structured representation and applicability wording, preserving the frozen baseline and strict result.
2. Compare URL Context with extraction from a separately fetched, bounded source document. This pilot's cleaned transcriptions make extraction easier than raw HTML, so the next dataset must include real page layout, irrelevant navigation and conflicting panels. Keep explicit source identity and retrieval failures visible.
3. Test description-to-candidate selection for cooked meat and recipes, then confirm a labelled representative candidate before scaling the edible cooked amount. Avoid silently converting a recipe serving to measured grams.
4. Broaden source/food families and ambiguous/adversarial cases. Select a candidate on development data before the one-time holdout run. Do not ship nutrition saving from this pilot alone.
