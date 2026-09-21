# Generic-food retrieval and closest-match evaluation

Status: **complete — user-selection-only envelope accepted**

Evidence date: **21 September 2026**

Issue: [#92](https://github.com/syamaner/WeeklyHealthReport/issues/92)

Normative contract: [Food identity and nutrition provenance contract](food-identity-nutrition-contract.md)

## Decision

The evaluated deterministic retrieval and hard-rule pipeline is suitable for
showing ranked CoFID candidates for **explicit user selection**. It is not
evidence for automatic acceptance.

The accepted envelope for #98 is:

- search an immutable local CoFID release deterministically;
- apply known preparation, bone, skin, drained, packing-medium, fortification,
  salt, serving-basis, edible-quantity and formulation contradictions before
  ranking;
- show exact or closest candidates with source identity and material
  differences;
- require the user to accept, choose another candidate or decline; and
- keep unmatched, ambiguous or contradicted cases explicit rather than filling a
  nutrition resolution.

Automatic acceptance remains disabled. The frozen public/synthetic result's
one-sided 95% precision lower bound is below the 99.5% promotion target, and no
authorised untouched personal-case set was available. Either condition is enough
to prevent promotion.

## Frozen evidence

`Tools/FoodMatchEvaluation/frozen-contract-v1.json` was fixed before the untouched
gate run. It records the features, weights, split algorithm, thresholds, fixture
hashes, matcher hash and the policy that every candidate requires explicit user
selection.

The source projection contains 2,887 CoFID rows from the official 2021 workbook,
identified by immutable release, worksheet row and canonical row hash. Published
food codes remain attributes because the workbook contains a duplicate code. The
projection preserves the published food group and all 39 catalogue positions:
36 mapped CoFID components and three explicit unmapped nutrients. Source and
canonical units remain separate; in particular, CoFID water remains sourced in
grams rather than being relabelled as the ledger's canonical millilitres. Serving
basis is per 100 g except for published alcoholic-beverage groups, which remain
per 100 ml. It is reproducibly derived from workbook
SHA-256 `436e9445ef2adb2a75f3d7edd51302de3adad25385f9795fc94ba58bd030e97d`.

The 1,280 labelled decisions are public or visibly synthetic bootstrap cases:

| Family | Cases |
| --- | ---: |
| Exact public CoFID names | 400 |
| Token-order public queries | 300 |
| Eight hard-negative identity families | 320 |
| Synthetic reformulation near-duplicates | 80 |
| Synthetic acceptable minor differences | 80 |
| No acceptable candidate | 100 |

The deterministic split produced 793 tuning, 254 calibration and 233 untouched
gate cases. Synthetic nutrient values exist only to exercise error reporting;
they are labelled fixture units and are not food facts. No personal foods,
consumption history, provider response or commercial data is present.

## Results

| Metric | All 1,280 | Untouched gate |
| --- | ---: | ---: |
| Candidate-set retrieval recall | 100% | 100% |
| Explicit-selection success | 100% | 100% |
| Correct decline rate | 100% | 100% |
| Top-rank precision | 99.83% | 100% |
| One-sided 95% top-rank precision lower bound | 99.489% | 98.752% |
| Catastrophic hard-negative acceptances | 0 | 0 |
| Action-policy accuracy | 100% | 100% |

The full frozen set exposed two ranking and explanation failures. One pair used
the exact same public name for distinct CoFID records (`Beef, mince, stewed`);
the other produced tied lamb records after token-order normalisation. Both
expected candidates remained in the returned set, so explicit selection
succeeded, but lexical ordering alone could neither choose nor explain the
correct row. This is product evidence for showing source descriptions and
decisive differences, not a reason to invent a stronger ranker or silently pick
the first row.

The report also retains per-nutrient error magnitudes for synthetic acceptable or
wrong top candidates. These fixture-unit values validate the reporting path; they
must not be interpreted as real dietary error estimates.

## Reproduction and boundary

The checked-in evaluation runs without the source workbook or network:

```sh
python3 -m unittest discover -s Tools/FoodMatchEvaluation/tests -v
python3 Tools/FoodMatchEvaluation/evaluate.py \
  --contract Tools/FoodMatchEvaluation/frozen-contract-v1.json \
  --corpus Tools/FoodMatchEvaluation/fixtures/cofid-2021-evaluation-v1.json.gz \
  --gold Tools/FoodMatchEvaluation/fixtures/gold-set-v1.json \
  --verify-report Tools/FoodMatchEvaluation/result-v1.json
```

`Tools/FoodMatchEvaluation/README.md` documents deterministic reconstruction from
the official workbook. Hash mismatches, non-canonical fixtures and source-row
alignment drift fail closed.

This issue changes no app behaviour. It performs no provider, model, OAuth,
Drive, HealthKit, account, commercial-source or physical-device operation. A
future authorised frozen personal-case gate may re-evaluate promotion, but it
cannot retroactively change this v1 result.
