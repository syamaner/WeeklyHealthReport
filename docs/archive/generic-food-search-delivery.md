# Offline generic-food search delivery

Status: **complete — explicit user selection required**

Evidence date: **21 September 2026**

Issue: [#98](https://github.com/syamaner/WeeklyHealthReport/issues/98)

Evaluation authority: [Generic-food retrieval and closest-match evaluation](generic-food-match-evaluation.md)

## Delivered envelope

`FoodGenericSearch` loads the immutable 2,887-row CoFID 2021 projection locally.
The bundled canonical JSON has SHA-256
`2b0fbbade4d405eabcad440cabb1560e9861d9388c5fb4032ef24c81fb45f445`;
loading fails closed if its bytes differ. It retains the original workbook release
identity, row identity, published food group, source description, OGL v3 licence
and attribution, and all 39 nutrient source states.

The production matcher is the accepted #92
`deterministic-lexical-hard-rules-v1` contract:

- exact-name, query-coverage, candidate-coverage and Jaccard weights are 0.55,
  0.20, 0.15 and 0.10;
- the minimum score is 0.25 and at most ten candidates are returned;
- known preparation, bone, skin, drained, packing-medium, fortification, salt,
  serving-basis, edible-quantity and formulation conflicts are removed before
  ranking; and
- ties are resolved by immutable record ID.

Every result remains a candidate. The search view shows exact/closest status,
source description, score, lexical differences and record ID before routing the
chosen row into the shared populated confirmation. A miss preserves the typed
query evidence and offers another search or leaving the item unresolved. There is no blank
nutrient form and no automatic acceptance path. The main report exposes the
offline flow under **Food logging → Search Generic Foods**; declining every
candidate returns to an explicit no-selection state and saves nothing.

## Provenance and offline reuse

The candidate snapshot records source release/record, matcher version, score,
material differences and the fixed `explicit_user_selection_v1` policy. Numeric
source values with matching canonical units become `augmented`; blank, trace,
present-but-unquantified and unmapped states remain explicit unknown states.
CoFID water is sourced in grams, so it remains `unknown(missing_conversion)`
rather than being relabelled as canonical millilitres.

After the user resolves mandatory identity, chooses a candidate and confirms the
quantity, the same atomic ledger operation stores the candidate decision and exact
normalised name aliases. A later identical local search hydrates the current saved
product and resolution versions before searching CoFID. Concurrent saved heads
remain ambiguous rather than being selected by storage order.

## Verification

Package contracts cover:

- corpus hash, release, row count and 39-nutrient projection;
- all ten frozen hard-rule families before lexical rank;
- exact, closest, deterministic duplicate-name tie and explicit no-result paths;
- frozen weights, threshold, candidate limit and normalisation aliases;
- match-method/difference/selection-policy provenance;
- quantity changes without corrupting candidate identity; and
- search, explicit correction/confirmation, atomic save and offline exact reuse.

The full simulator build, static analysis and existing food-ledger, archive,
Drive-policy and app tests remain the final CI gate. These software checks do not
claim personal-food, provider, physical-device or automatic-acceptance validation.

## Reproduction

The production resource is the canonical decompressed #92 projection:

```sh
gzip -dc Tools/FoodMatchEvaluation/fixtures/cofid-2021-evaluation-v1.json.gz \
  > Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/cofid-2021-generic-search-v1.json
shasum -a 256 Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/cofid-2021-generic-search-v1.json
swift test --package-path Packages/FoodLedgerKit
```

No provider, OAuth, Drive, personal health data, private account, commercial
source, paid service or physical device is used by this delivery.
