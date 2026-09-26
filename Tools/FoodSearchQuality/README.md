# Multi-source search development diagnostics

The Swift test uses the actual bundled adapters and composite orchestration. It records whole record IDs/names, source order and suggested follow-up queries. No provider requests or private food logs are used. This is development/tuning evidence, not independent acceptance or measured production accuracy. The original frozen v1 evaluation is not overwritten.

Reproduce from the repository root:

```sh
WHR_SEARCH_QUALITY_REPORT=/private/tmp/search-quality-current.json swift test --package-path Packages/FoodLedgerKit --filter SearchQualityDevelopmentTests/testDevelopmentReport
python3 Tools/FoodSearchQuality/compare.py Tools/FoodSearchQuality/before-v2.json /private/tmp/search-quality-current.json /private/tmp/search-quality-comparison.json
```

The baseline was generated from merged PR #149 (`d3c3361`, retrieval v2). Compare the same 44 queries with the v3 development implementation. Eight main-food judgements check the first result for an explicit food-family prefix; these deliberately narrow lexical checks do not judge cut, fat, preparation, region, recipe equivalence or nutrient accuracy. Both-source exposure is a visibility metric, not relevance. Report each failure family separately, and use device feedback and independently reviewed labels before making quality acceptance claims.
