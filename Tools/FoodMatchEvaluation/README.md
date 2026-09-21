# Generic-food matching evaluation

This directory is the reproducible, evaluation-only artefact for issue #92. It
does not ship product behaviour, contact a provider or permit automatic food
selection.

`frozen-contract-v1.json` fixes the source release, fixture hashes, split,
features, weights, metrics and policy before the untouched gate is run. The
committed CoFID projection is derived from the official 2021 workbook under the
Open Government Licence. It contains source rows and values, not personal food
or consumption data. Synthetic cases are visibly namespaced and are not factual
food observations.

The personal-case gate is deliberately deferred. Therefore the only admissible
recommendation from this evaluation is explicit user selection or decline. Even
a perfect synthetic/public score cannot promote automatic acceptance.

## Reproduce the source projection

Use the exact workbook whose SHA-256 is recorded in the contract:

```sh
python3 -m venv /tmp/whr-cofid-evaluation
/tmp/whr-cofid-evaluation/bin/python -m pip install -r Tools/FoodSourceEvaluation/requirements.txt
/tmp/whr-cofid-evaluation/bin/python Tools/FoodMatchEvaluation/build_cofid_release.py \
  /path/to/CoFID_2021.xlsx \
  --output /tmp/cofid-2021-evaluation-v1.json.gz
```

The builder fails closed for any other workbook hash. Rebuild the gold fixture
from that projection with `build_gold_set.py`; compare the emitted hashes with
the frozen contract before evaluating.

## Verify

```sh
python3 -m unittest discover -s Tools/FoodMatchEvaluation/tests -v
python3 Tools/FoodMatchEvaluation/evaluate.py \
  --contract Tools/FoodMatchEvaluation/frozen-contract-v1.json \
  --corpus Tools/FoodMatchEvaluation/fixtures/cofid-2021-evaluation-v1.json.gz \
  --gold Tools/FoodMatchEvaluation/fixtures/gold-set-v1.json \
  --verify-report Tools/FoodMatchEvaluation/result-v1.json
```
