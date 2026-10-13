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

## Issue #161 current replay

[Confirmation/ranking v4](retrieval-report-v4.md) preserves the historical v3
replay and judgements. At that checkpoint CI compared the same scenarios with
`retrieval-metrics-final-v4.json`; v3 reproduction commands above apply to its
historical implementation. Egg-size guide data and device acceptance stay deferred.

## Current CI replay: v5 (30 September 2026)

CI uses `retrieval-metrics-final-v5.json` with the unchanged v3 scenario labels and
scorer. v4 remains historical evidence. The current 72-query, three-source replay
changes only r059/r060 (banana/100g banana), each in CoFID and composite: the existing
labelled grade-1 row `1664:4167f51564a89259` now appears at rank 6 and 16 respectively.
The added candidate is flavoured milk (strawberry/banana), already labelled as a
low-relevance alternative; it is not a new correct top match. All top-five
metrics, all aggregate summaries and the other 212 scored rows are exactly unchanged.
This reconciles the existing named-food retrieval changes with the CI snapshot;
it does not relabel results, change production matching or establish independent
acceptance. v73 preserves the failing v4 comparison and the full current replay.

## Current CI replay: ranking v7 (13 October 2026)

CI verifies two reports from one replay of `retrieval-scenarios-v4.json`
(the 72 v3 cases plus eight part-word and produce-skin cases). The v3 rows are scored with the
unchanged v3 labels against `retrieval-metrics-final-v7.json`; every summary
equals v6 and only four raw-ribeye tails change. The full v4 rows are scored
against `retrieval-metrics-v4-final-v7.json`; `retrieval-metrics-v4-baseline-v6.json`
keeps the same labels scored on ranking v6. See `docs/generic-food-ranking-v7.md`
and `v7-reproduction-manifest.json`. Score with Python 3.12 or later: float
`sum()` changed in 3.12, so 3.11 differs in the last bit of two summaries.

```sh
WHR_RETRIEVAL_REPORT=/private/tmp/retrieval-current.json WHR_RETRIEVAL_REPORT_V4=/private/tmp/retrieval-v4-current.json swift test --package-path Packages/FoodLedgerKit --filter RankedRetrievalDevelopmentTests/testReplay
python3.12 Tools/FoodSearchQuality/score_retrieval.py Tools/FoodSearchQuality/retrieval-scenarios-v3.json /private/tmp/retrieval-current.json /private/tmp/retrieval-metrics.json --verify-report Tools/FoodSearchQuality/retrieval-metrics-final-v7.json
python3.12 Tools/FoodSearchQuality/score_retrieval.py Tools/FoodSearchQuality/retrieval-scenarios-v4.json /private/tmp/retrieval-v4-current.json /private/tmp/retrieval-v4-metrics.json --verify-report Tools/FoodSearchQuality/retrieval-metrics-v4-final-v7.json
```

To rebuild the v4 labels, write the ungraded replays for ranking v6 and v7 and
pass both to `build_retrieval_v4.py`. Raw replays are not retained (about 2 MB
each); their hashes are in the manifest.

## Current CI replay: composite v9 (13 October 2026)

The replay now reads `retrieval-scenarios-v5.json` (the 80 v4 cases plus seven
Taiwan source-order cases) and writes three reports from one run: v3 and v4 rows
use the two-source composite order, derived from the regional composite row by
removing TFDA records (exact when Taiwan is not promoted; still verified against
`retrieval-metrics-final-v7.json` and `retrieval-metrics-v4-final-v7.json`), and
v5 rows from the production composite with TFDA as a regional source and each
case's market, verified against `retrieval-metrics-v5-final-v9.json`.
`retrieval-metrics-v5-baseline-v8.json` scores the same labels with every source
interleaved (the v8 behaviour); set `WHR_RETRIEVAL_REPORT_V5_BASELINE` to write
that replay. See `docs/composite-regional-order-v9.md` and
`v9-reproduction-manifest.json`.

```sh
WHR_RETRIEVAL_REPORT=/private/tmp/retrieval-current.json WHR_RETRIEVAL_REPORT_V4=/private/tmp/retrieval-v4-current.json WHR_RETRIEVAL_REPORT_V5=/private/tmp/retrieval-v5-current.json swift test --package-path Packages/FoodLedgerKit --filter RankedRetrievalDevelopmentTests/testReplay
python3.12 Tools/FoodSearchQuality/score_retrieval.py Tools/FoodSearchQuality/retrieval-scenarios-v5.json /private/tmp/retrieval-v5-current.json /private/tmp/retrieval-v5-metrics.json --verify-report Tools/FoodSearchQuality/retrieval-metrics-v5-final-v9.json
```
