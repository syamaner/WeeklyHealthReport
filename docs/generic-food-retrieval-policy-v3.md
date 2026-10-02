# Generic food retrieval policy v3

The local CoFID and USDA adapters share pure lexical and ranking policy in
FoodLedgerApplication. A bounded primary-name rejection now prevents bread,
rolls, buns and relish from standing in for another requested food. A query for
an ingredient or filling alone does not request its bread or condiment. An
explicit request for the derivative food remains searchable. The check uses
whole tokens in the comma-delimited primary source name; it is not a general
food-identity classifier, and it does not establish exact product identity.

Seed/seeds is a lexical equivalent, shared by retrieval and ranking. Dry/dried,
fresh/dehydrated, roast/roasted and slice/sliced are unchanged in this revision.
Preparation, edible basis, unknown metadata and all other decisive identity
checks remain separate and mandatory. The rule neither edits original evidence
nor infers a portion, nutrient value, recipe, cut or preparation state. Candidate
selection remains explicit.

Versions: generic-representation-ranking-v3, food-lexical-terms-v6,
cofid-generic-ranking-v8 and usda-generic-ranking-v9. Catalogue schemas and hashes
are unchanged by this policy repair. Match-method versions distinguish new
ranking observations from prior saved records.

The architecture gate keeps retrieval policy pure, infrastructure-specific
catalogue loading in FoodGenericSearch, and orchestration in the existing
application service. Both source adapters use the same rule. No new provider
abstraction or dependency is introduced.

## Regression checks and local run book

Run the pure policy tests and both adapter suites:

```sh
swift test --package-path Packages/FoodLedgerKit --skip-update \
  --filter 'GenericFoodRankingPolicyTests|USDAGenericFoodSearchTests|CoFIDGenericFoodSearchTests'
```

Synthetic contracts cover derivative-only negatives, explicit derivative
requests, whole-token boundaries, identical singular/plural seed record IDs,
unchanged original evidence, explicit selection and incompatible preparation.
Then run the complete package suite, complete app simulator suite and Xcode
static analysis as prescribed by AGENTS.md. Review `git diff --check` and the
final diff. The simulator does not establish personal food or device accuracy.

Personal evaluation sources, frozen references, baseline snapshots and reports
remain outside Git in their private offline harness. Re-run that harness under
network denial without modifying frozen labels. Retain source and implementation
hashes and the preceding results to distinguish retrieval changes from source
coverage, routing, quantity and identity changes. Personal results are exposed
development evidence, not an independent acceptance gate. No network provider,
ledger save, installation, commit or publication is part of this run book.
