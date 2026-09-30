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
