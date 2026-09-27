# Multi-source search development diagnostics

The Swift test uses the actual bundled adapters and composite orchestration. It records whole record IDs/names, source order and suggested follow-up queries. No provider requests or private food logs are used. This is development/tuning evidence, not independent acceptance or measured production accuracy. The original frozen v1 evaluation is not overwritten.

Reproduce from the repository root:

```sh
WHR_SEARCH_QUALITY_REPORT=/private/tmp/search-quality-current.json swift test --package-path Packages/FoodLedgerKit --filter SearchQualityDevelopmentTests/testDevelopmentReport
python3 Tools/FoodSearchQuality/compare.py Tools/FoodSearchQuality/before-v2.json /private/tmp/search-quality-current.json /private/tmp/search-quality-comparison.json
```

The baseline was generated from merged PR #149 (`d3c3361`, retrieval v2). Compare the same 44 queries with the v3 development implementation. Eight main-food judgements check the first result for an explicit food-family prefix; these deliberately narrow lexical checks do not judge cut, fat, preparation, region, recipe equivalence or nutrient accuracy. Both-source exposure is a visibility metric, not relevance. Report each failure family separately, and use device feedback and independently reviewed labels before making quality acceptance claims.

The 27 September v4 reproduction is bound by `v4-reproduction-manifest.json`. Its paired comparison is byte-identical to `paired-development-v3.json`; the report schema is unchanged while the manifest records retrieval-policy v4 and exact source hashes. This does not promote the tuning sample into independent acceptance.


## Historical record-level ranked retrieval v2 (superseded by issue #160)

See [retrieval-report-v2.md](retrieval-report-v2.md), [retrieval-contract-v1.md](retrieval-contract-v1.md) and the visible pre-tuning [judgement corrections](judgement-revisions.md). Both historical v1 and corrected v2 labels are retained. Reproduce the actual bundled adapters and composite:

```sh
WHR_RETRIEVAL_REPORT=/private/tmp/retrieval-current.json swift test --package-path Packages/FoodLedgerKit
python3 -m unittest discover -s Tools/FoodSearchQuality/tests -v
python3 Tools/FoodSearchQuality/score_retrieval.py Tools/FoodSearchQuality/retrieval-scenarios-v2.json /private/tmp/retrieval-current.json /private/tmp/retrieval-metrics.json --verify-report Tools/FoodSearchQuality/retrieval-metrics-final-v2.json
```

Score the preserved baseline with the same corrected labels by replacing the replay argument with `Tools/FoodSearchQuality/retrieval-before-v1.json.gz`. The v1 replay name denotes its capture before tuning, not use of erroneous v1 labels. No provider access is required. Full candidates include source nutrition provenance; quantity queries do not infer portion weights or density.


## Current generic retrieval v3 / issue #160

See [retrieval-report-v3.md](retrieval-report-v3.md), [generic contract](retrieval-contract-v2.md) and [device retest](device-retest-v3.md). V3 supersedes narrow food-specific bonuses and defers detailed numeric variants. The build 9 baseline and final run use identical 72-scenario generic labels.

```sh
WHR_RETRIEVAL_REPORT=/private/tmp/retrieval-current.json swift test --package-path Packages/FoodLedgerKit
python3 Tools/FoodSearchQuality/score_retrieval.py Tools/FoodSearchQuality/retrieval-scenarios-v3.json /private/tmp/retrieval-current.json /private/tmp/retrieval-metrics.json --verify-report Tools/FoodSearchQuality/retrieval-metrics-final-v3.json
```

Replay the preserved baseline using `retrieval-build9-v3.json.gz`. The current reproduction manifest binds source, judgement and result hashes; archived v2 hashes refer to its historical implementation commit.
