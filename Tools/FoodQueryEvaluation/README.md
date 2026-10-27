# Food query evaluation

Synthetic en-GB development fixtures for the NLP search phase. The runner evaluates the production Swift parser without network or Gemini calls. Initial expectations preceded implementation; later versions add exposed challenge cases. All are visible development material, not a sealed independent holdout or evidence of user accuracy.

Responsibilities: a pure parser separates food identity, explicit variant attributes and intake quantity; retrieval uses food/attributes; presentation may prefill quantity after explicit candidate selection. Saving remains a separate confirmation. Original query and source provenance survive unchanged. Quantity must never be added to a food-name token filter. Counts remain counts until a selected source provides a compatible portion weight; ml never becomes g without evidenced density. Greek and Greek-style remain distinct. Numeric fat percentage is a requested variant, not permission to manufacture nutrient values.

Routes: search returns structured terms; clarify retains input and requests missing/ambiguous meaning; reject does not produce a saveable food. Missing exact catalogue coverage must produce labelled alternatives or an honest miss, never imply that parsing found the exact product. Qualitative fat labels are not converted to numeric percentages. Multiple foods require explicit decomposition/review; this phase does not infer recipes. Household measures remain unresolved until an explicit standard/source portion is available.

Run `python3 Tools/FoodQueryEvaluation/validate.py`. This validates fixture integrity only, not parser performance. Later adapters should emit one result per case ID, retaining original text. Report exact food, attribute, quantity and route accuracy separately and by family; report false automatic conversions/substitutions as errors. Paraphrases of a scenario must stay in the same split. Any future independent acceptance set must be separately authored and frozen before tuning; this file cannot be relabelled as an untouched gate.

## Expanded v2

262 cases: the original 60 plus 202 invented cases informed by phrasing patterns in a user-supplied diary. The original personal file remains outside this directory. New cases use altered amounts and fictional brands, and omit diary dates, venues and health events. Template variants are correlated and must not be treated as 262 independent observations. Repetition tests formatting invariance; it does not establish representative accuracy. Validate v2 (default) or v1 with `python3 Tools/FoodQueryEvaluation/validate.py v1`.

New families cover prefix/suffix amounts, decimals, kilograms, brands, cocoa/ingredient percentages distinct from fat, preparation and weight basis. Clarification cases cover grounds versus drink, count plus mass, packs, mixtures, menu prices, times, supplements, narrative input and unsafe typo correction. All clarification cases leave quantity unresolved for this draft; the future parser may preserve tentative spans but cannot prefill a confirmed amount from them.

## Measured parser checkpoint

Run the production Swift parser locally:

```sh
swiftc Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryDiscoveryPolicy.swift Tools/FoodQueryEvaluation/run.swift -o /tmp/whr-query-eval
/tmp/whr-query-eval Tools/FoodQueryEvaluation/synthetic-v2.json /tmp/query-results.json
python3 Tools/FoodQueryEvaluation/score.py Tools/FoodQueryEvaluation/synthetic-v2.json /tmp/query-results.json /tmp/query-report.json
```

The runner injects a fictional Acme brand vocabulary; production uses an explicit recognised-brand list, and never infers arbitrary unknown words as brands. Scoring pins the fixture bytes. Current development checkpoint: 262/262 route and quantity; 231/262 strict food and 256/262 attributes; all 212 search-route cases match every scored field. Clarification cases preserve tentative spans rather than always nulling food/attributes. Reasons are diagnostics, not scored.

The 36 prospective scenarios were frozen before their first run, with results retained in prospective-result-v1.json. Routing: 35/36; quantity: 36/36. “A scoop of protein powder” exposed an unhandled household portion. The production rule was subsequently repaired; the original prospective result is not rewritten or promoted to independent acceptance. These are same-author, exposed regression scenarios. An independent acceptance gate and real device review remain outstanding.

## Challenge expansion v3

429 total cases, adding 167 cases across 119 scenario groups. The 72 formatting variants share 24 food scenarios and are correlated. Other additions cover numeric and Unicode fractions, leading decimals/thousands separators, non-fat percentages, approximations, prices, scope/variant contradictions, household portions and malformed quantities. Expectations are desired behaviour, including syntax not yet supported; the parser was unchanged for this evaluation.

Run `python3 Tools/FoodQueryEvaluation/validate.py v3`, then substitute synthetic-v3.json into the parser/scoring commands above. The existing v2 CI regression gate remains unchanged; v3 is a discovery challenge set rather than a newly passing gate. Same-author synthetic cases are not independent acceptance. The old fixtures are retained verbatim. build_v3.py reproduces the fixture deterministically.

First-run results: 405/429 routing and 414/429 quantity; among the 167 additions, 143/167 routing and 152/167 quantity. Six new examples prefilled a quantity where the desired route asks for clarification or rejection. See v3-new-case-summary.json for those cases, and development-challenge-v3-result.json for all field/family failures. They identify follow-up work; no parser changes were made to improve these scores.

## Current checkpoint: v5

511 cases (60 → 262 → 429 → 495 → 511). v4 adds 66 boundary scenarios;
v5 retains them, corrects nlp-444's omitted `preparation=boiled` expectation, and
adds 16 quantity/variant boundaries. Earlier fixtures and first-run scores remain
unchanged. Numeric percentage attributes compare numerically (`10` equals `10.0`);
all other fields compare exactly. Metric schema 2 is used for comparable repair
reports. See [evaluation-report.md](evaluation-report.md) for the confusion matrix,
precision/recall/F1, extraction scores, safety counters and limitations.

CI now validates v5, tests the scorer, and gates routing and quantity on all cases
plus every scored field on search-eligible cases. Tentative extraction disagreements
on clarification/rejection remain visible in the report and do not block this gate.
The gate is a development regression check, not independent acceptance.

```sh
python3 Tools/FoodQueryEvaluation/validate.py v5
python3 -m unittest discover -s Tools/FoodQueryEvaluation/tests
swiftc Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryDiscoveryPolicy.swift Tools/FoodQueryEvaluation/run.swift -o /tmp/whr-query-eval
/tmp/whr-query-eval Tools/FoodQueryEvaluation/synthetic-v5.json /tmp/query-results.json
python3 Tools/FoodQueryEvaluation/score.py Tools/FoodQueryEvaluation/synthetic-v5.json /tmp/query-results.json /tmp/query-report.json --gate
```

Frozen synthetic predictions are retained as deterministic gzip files in
`predictions/`. To replay a retained result, decompress its JSON and pass it to
`score.py` with the matching fixture. The report pins SHA-256 of the uncompressed
prediction bytes and fixture bytes. Reasons are diagnostic and not scored.
No personal diary contents are included in these prediction files.

## Current checkpoint: v6 (food-query-parser-v8)

523 cases: v5 unchanged plus 12 egg-count cases (`build_v6.py`, family
`egg_count_v6`). Expectations were written against food-query-parser-v7, whose
hash the manifest records. Seven are counts ("2 scrambled eggs", "two fried
eggs", "3 poached eggs", "a fried egg", "one poached egg", "2 x scrambled eggs"
and a branded form); five are boundaries that must not become counts or must
reject ("2 scrambled eggs 120g", "2 fried bananas", "2 pan fried eggs",
"not fried 2 eggs", "0 fried eggs"). See `docs/food-query-parser-v8.md`.

| Run | Routing | Quantity | Search cases, all fields | Unexpected prefills |
|---|---:|---:|---:|---:|
| v6 first run (parser v7) | 518/523 | 516/523 | 347/354 | 0 |
| v6 final (parser v8) | 523/523 | 523/523 | 354/354 | 0 |

The v5 gate still passes unchanged with parser v8 (511/511 routing and quantity,
every v5 report field equal to `metrics-v5-final.json` except the predictions hash,
which differs only in diagnostic reason strings of three clarification cases that
predate this change). CI now gates v6.

```sh
python3 Tools/FoodQueryEvaluation/validate.py v6
swiftc Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryDiscoveryPolicy.swift Tools/FoodQueryEvaluation/run.swift -o /tmp/whr-query-eval
/tmp/whr-query-eval Tools/FoodQueryEvaluation/synthetic-v6.json /tmp/query-results.json
python3 Tools/FoodQueryEvaluation/score.py Tools/FoodQueryEvaluation/synthetic-v6.json /tmp/query-results.json /tmp/query-report.json --gate
```

## Current checkpoint: v7 (food-lexical-terms-v9, parser unchanged)

542 cases: v6 unchanged plus 19 plural food-name cases (`build_v7.py`, family
`plural_food_v7`). The parser is still food-query-parser-v8; the cases pin the
food text it hands to retrieval, where food-lexical-terms-v9 folds plurals (see
`docs/food-lexical-terms-v9.md`). Expectations were written before the first
run against the parser hash in `manifest-v7.json`.

| Run | Routing | Quantity | Search cases, all fields | Unexpected prefills |
|---|---:|---:|---:|---:|
| v7 first and final run (parser v8) | 542/542 | 542/542 | 372/372 | 0 |

The only field difference is the tentative food on the clarify case "a handful
of walnuts" (expected "walnuts"), which the gate does not score. The v6 gate
still passes and its predictions are byte-identical to `predictions/v6-final.json.gz`.
CI now gates v7.

```sh
python3 Tools/FoodQueryEvaluation/validate.py v7
swiftc Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryDiscoveryPolicy.swift Tools/FoodQueryEvaluation/run.swift -o /tmp/whr-query-eval
/tmp/whr-query-eval Tools/FoodQueryEvaluation/synthetic-v7.json /tmp/query-results.json
python3 Tools/FoodQueryEvaluation/score.py Tools/FoodQueryEvaluation/synthetic-v7.json /tmp/query-results.json /tmp/query-report.json --gate
```

## Current checkpoint: v8 (food-query-parser-v9)

563 cases: v7 unchanged plus 21 count-form cases (`build_v8.py`, family
`count_forms_v8`) for #317 and the parse part of #315. Nine are counts ("2 hard
boiled eggs", "a hard boiled egg", "3 pieces banana", "3 pieces of banana",
"2 pieces apple" and similar); twelve are boundaries that must not become counts
or must reject ("a piece of banana", "3 pieces cheese", "3 pieces of apple
pie", "2 pieces banana bread", "2 pieces of egg fried rice", "3 pieces of red
pepper", "2 hard bananas", "2 hard boiled bananas", a count with a mass, and
zero). See `docs/food-query-parser-v9.md`. The first run
used parser v8, whose hash `manifest-v8.json` records.

| Run | Routing | Quantity | Search cases, all fields | Unexpected prefills |
|---|---:|---:|---:|---:|
| v8 first run (parser v8) | 554/563 | 554/563 | 372/381 | 0 |
| v8 final (parser v9) | 563/563 | 563/563 | 381/381 | 0 |

The v7 gate still passes and parser v9's v7 predictions are byte-identical to
`predictions/v7-final.json.gz`. CI now gates v8.

```sh
python3 Tools/FoodQueryEvaluation/validate.py v8
swiftc Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryDiscoveryPolicy.swift Tools/FoodQueryEvaluation/run.swift -o /tmp/whr-query-eval
/tmp/whr-query-eval Tools/FoodQueryEvaluation/synthetic-v8.json /tmp/query-results.json
python3 Tools/FoodQueryEvaluation/score.py Tools/FoodQueryEvaluation/synthetic-v8.json /tmp/query-results.json /tmp/query-report.json --gate
```
