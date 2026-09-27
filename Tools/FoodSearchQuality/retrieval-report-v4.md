# Issue #161 confirmation and ranking replay

Same-author development replay against unchanged 72-scenario v3 labels. This is
not independent frozen acceptance, physical-device usability, or exact variant
coverage. Historical replays, labels, metrics and reports remain untouched.

The source-neutral whole-representation preference is stronger than another
ordinary descriptor such as white. No food-specific score override is added.
Explicit white/whites and yolk/yolks retain lexical retrieval; style remains in
catalogue names and matching, and an unrequested style is a specialisation.
Greek/Greek-style alternatives carry a tentative type warning. USDA has no
Greek-style record and returns an honest miss for that explicit query.

| Source | Hit@1 / Hit@5 / MRR | nDCG@5 before → after | Incorrect variant at 1 / 5 |
| --- | --- | --- | --- |
| CoFID | 0.97561 / 0.97561 / 0.97561 | 0.91991 → 0.92893 | 12 / 27, unchanged |
| USDA | 0.93333 / 1 / 0.96667 | 0.97614 → 0.97614 | 15 / 72, unchanged |
| Composite | 1 / 1 / 1 | 0.97830 → 0.98386 | 9 / 69, unchanged |

No-result counts are unchanged. The generic labels judge food families and can
count several preparations/types as relevant; high Hit@1 does not establish the
user's exact food identity. Incorrect variants remain visible as a limitation.
Additional regression tests require a whole egg first for `2 eggs`, preserve
`egg white`, and distinguish Greek-style retrieval from Greek yoghurt.

The retained milk, rice and Greek-yoghurt first results stay unchanged. The saved
v4 replay and SHA-256 manifest bind these comparisons to unchanged bundled sources.
The v4 CI expected metrics are a reproducibility check, not new quality thresholds.

```sh
WHR_RETRIEVAL_REPORT=/private/tmp/retrieval-current.json swift test --package-path Packages/FoodLedgerKit
python3 Tools/FoodSearchQuality/score_retrieval.py Tools/FoodSearchQuality/retrieval-scenarios-v3.json /private/tmp/retrieval-current.json /private/tmp/retrieval-metrics.json --verify-report Tools/FoodSearchQuality/retrieval-metrics-final-v4.json
```

Before comparing older code, score `retrieval-final-v3.json.gz` against the same
v3 scenarios; do not change labels to match observed rankings.
