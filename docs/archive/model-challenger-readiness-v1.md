# Issue #100 readiness and execution boundary

This is offline preparation, not a model evaluation or production integration. The delivery programme must finish #144/#148/#142/#143 with validated merges before selecting a challenger run. Physical-device acceptance remains distinct from software gates. No model, provider route, prompt, budget or execution permission is selected here.

## Frozen comparison

#100 requires the identical candidate sets, hard negatives and held-out labels from #92. The historical deterministic baseline remains `deterministic-lexical-hard-rules-v1`, with explicit selection only. Its 1,280 public/synthetic cases split into 793 tuning, 254 calibration and 233 gate cases. The baseline gate has already been consumed for #92; it is historical comparison evidence, not a new untouched personal acceptance set. Do not reuse the 44-query multi-source development report as held-out acceptance or pretend the current CoFID/USDA retrieval v4 is the same baseline.

Verified inputs:

| Artifact | SHA-256 |
| --- | --- |
| `Tools/FoodMatchEvaluation/frozen-contract-v1.json` | `fc607d52360c38ae28381c4f6c70ad85dd5d0d6887192dd22d01efefdc8ffbd2` |
| `Tools/FoodMatchEvaluation/matcher.py` | `3d4a40fb06b6bc89c91c7b9af316dc89319e09bc1baf8a3b007b52070e13e517` |
| `Tools/FoodMatchEvaluation/fixtures/gold-set-v1.json` | `3ecfdec9d0003d93220a1434b320b4b244c8098a36e993dda8813d95206dba16` |
| `Tools/FoodMatchEvaluation/fixtures/cofid-2021-evaluation-v1.json.gz` | `a3f2776903b370397bf5621a293aa66a4cda67823053bcd34c6e13fa597e6f29` |
| `Tools/FoodMatchEvaluation/result-v1.json` | `6fe51d03abad8ab446a58bd68a456343b3e672b25f3b27eba80e1a2ab30a67e8` |

`Tools/FoodModelChallenger/prepare.py` verifies the frozen matcher and fixture hashes, then computes the original hard-rule-admitted candidates in their original order. Packets contain query, identity and whole candidate records, including visibly synthetic records where the original evaluation uses them. They omit labels, case-family judgements and lexical scores. Labels stay in the local evaluator. A model may decline or choose a packet record ID; `validate_choice` rejects invented and hard-rule-excluded IDs. An empty packet declines without a model call. This helper is evaluation-only and has no provider or ledger adapter.

Reproduce offline:

```sh
python3 -m unittest discover -s Tools/FoodMatchEvaluation/tests -v
python3 Tools/FoodMatchEvaluation/evaluate.py \
  --contract Tools/FoodMatchEvaluation/frozen-contract-v1.json \
  --corpus Tools/FoodMatchEvaluation/fixtures/cofid-2021-evaluation-v1.json.gz \
  --gold Tools/FoodMatchEvaluation/fixtures/gold-set-v1.json \
  --verify-report Tools/FoodMatchEvaluation/result-v1.json
python3 -m unittest discover -s Tools/FoodModelChallenger/tests -v
python3 Tools/FoodModelChallenger/prepare.py \
  --output /private/tmp/food-challenger-packets-v1.json \
  --manifest /private/tmp/food-challenger-preparation-v1.json
```

The preparation manifest records candidate-packet SHA-256, byte count, split denominators and zero provider calls. `run_ready` is false. Candidate packets are generated locally rather than committed as a second copy of the corpus.

## Required decisions before execution

Freeze an exact public model identifier/version where supported, provider and route, prompt hash, generation settings, output schema, timeout/retry/stop rules, call limit and hard spend ceiling. Verify current official provider documentation for pricing, retention/training use and version reproducibility. Obtain explicit authority for that concrete public/synthetic run before any provider invocation. An unavailable immutable model revision must be stated as a reproducibility limit.

Tune prompts using tuning cases only; freeze calibration methodology, thresholds and the gate protocol before seeing challenger gate results. Record each request configuration, input hash, returned model/version metadata, valid/invalid choice, decline, elapsed time, token usage and actual priced cost where available. A timeout, malformed response, out-of-set choice or exhausted budget declines; never silently changes route or retries beyond the approved policy. Retain no personal food data, scans or images.

Compare accepted-match precision and its uncertainty, confidence calibration, decline rate, catastrophic hard-negative errors, latency and cost against the frozen baseline. Report families and denominators separately. Synthetic nutrient errors remain fixture-unit diagnostics, not dietary accuracy. Candidate-set recall cannot improve in an adjudication-only comparison; any missing record remains missing. Recommend no model if the evidence does not justify one. Automatic acceptance and production integration remain outside this evaluation's authority.

Web search or new external food retrieval changes the candidate universe and therefore is not part of this identical-candidate experiment. A grounded web-search experiment would require its own source/identity/nutrition contract, frozen comparison and explicit run authority. It cannot silently replace #144's admitted food sources or manufacture nutrient values.
