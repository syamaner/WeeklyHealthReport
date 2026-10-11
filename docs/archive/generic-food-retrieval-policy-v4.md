# Generic food retrieval policy v4

This revision extends the bounded v3 policy with roast/roasted and
slice/slices/sliced lexical equivalents. It preserves the slice descriptor as a
retrieval requirement; a source that does not declare slices is not silently
substituted. Original evidence, source names, identity and quantity remain intact.

The preparation handoff now translates the affirmative parser-v5 cooking
methods (roasted, boiled, soft-boiled and pan-fried) into the broad cooked state.
The existing GenericFoodIdentityQuery owns that pure translation. Retrieval
retains the cooking-method words as well as the parsed food name, so the broad
state does not erase the requested method. The view model rejects conflicts
with either a selected preparation filter or a supplied identity before search.
Both adapters retain their source identity checks and use the same lexical
policy. No new abstraction or infrastructure dependency is introduced.

A roast-labelled source may be an explicitly raw cut. The source preparation
projection therefore remains usda-preparation-words-v2: a roast noun or sliced
form does not assert cooked preparation. Unknown source preparation stays
unknown and cannot satisfy a requested raw or cooked state. No corpus schema,
record, nutrient value, source release or catalogue hash changes in this repair.
Roast/roasted lexical equivalence is not nutrition-identity evidence. Explicit
selection and quantity/portion review remain required.

Versions: generic-representation-ranking-v4, food-lexical-terms-v7,
cofid-generic-ranking-v9 and usda-generic-ranking-v10. Parser output remains v5;
its cooking-method descriptors are unchanged. The match-method versions identify
new retrieval observations separately from prior saved records.

## Validation and run book

Freeze synthetic expectations before modifying production behaviour. Test
method/form equivalents, retained slice constraints, different cooking methods,
negation, unknown preparation, raw roast cuts, unchanged original evidence and
explicit selection. Run the shared policy, presentation handoff and both source
adapter suites:

```sh
swift test --package-path Packages/FoodLedgerKit --skip-update \
  --filter 'GenericFoodRankingPolicyTests|GenericFoodSearchPresentationTests|USDAGenericFoodSearchTests|CoFIDGenericFoodSearchTests'
python3 -m unittest discover -s Tools/FoodSourceEvaluation/tests
```

Run the complete package and app simulator suites, followed by Xcode static
analysis. Review the final diff and `git diff --check`. Synthetic simulator tests
prove software behaviour, not personal food identity or device acceptance.

Private evaluation sources, references and reports remain outside Git. Retain
the prior run, update the private query probes to use the same application
preparation translation, and rerun the offline harness with frozen labels and
catalogue hashes unchanged. Report query and list paths separately: lexical
recovery may still be blocked by missing preparation or form evidence. No
personal examples, data, derived reports or private source paths belong here.
