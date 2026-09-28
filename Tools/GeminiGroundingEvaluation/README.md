# Gemini grounded food-source discovery: offline evaluation v1

This is a frozen, public/synthetic evaluation set for [#172](https://github.com/syamaner/WeeklyHealthReport/issues/172). It tests whether a future explicit-tap Gemini response helps a person find original food sources, while keeping source leads separate from admitted nutrition. It makes **no provider call** and does not score the current app, a Gemini model, a signed device or a user key. The 16 food terms and their SHA-256 are fixed in `frozen-contract-v1.json` before any live Gemini output was captured for this set. User-reported yoghurt and milk phrases are included; all other inputs are public or synthetic and contain no food history.

## Architecture and evaluation boundary

- The frozen case file owns query families, split, intended source-discovery task and identity/preparation traps. It contains no provider response, provider-specific type or nutrition ground truth.
- A replay is a privacy-reviewed projection of the app's `FoodWebDiscoveryResult`: response text, cited leads and whether Search suggestions were supplied. A future collector may use any provider adapter, but this scorer makes no network call and has no key access.
- An independent reviewer opens each linked page, checks the cited passage against the page and the food terms, then records lead grade, claim support and answer-level hazards in a separate judgement file. Unknown or inaccessible pages stay `unverified`, never automatically correct. The reviewer records a check date and evidence note; URL match or HTTPS alone cannot prove grounding.
- `evaluate.py` validates complete case coverage and emits counts by family and split. Its automatic checks cover only schema, link shape and cited-text attachment. Its relevance and truth metrics come from the independent judgements. A provider cannot alter the case file or judgement rubric.
- The stable safety invariant is that neither a model's number nor a cited page becomes admitted nutrition, product identity or saved food. A severe identity/preparation mismatch, unsupported citation or promoted nutrition is reported explicitly. This eval cannot itself authorise source admission.

The development split has 12 cases and the holdout split has four. Do not inspect holdout results while changing the app or prompt. Freeze a new version if cases, grading rules or split change; preserve v1 for paired comparison. The source examples in the case file are leads for independent review, not an exhaustive URL allowlist and not licensed nutrition data. A reviewer can credit a different original source when the evidence supports it.

## Reproduce offline

```sh
python3 Tools/GeminiGroundingEvaluation/evaluate.py \
  --contract Tools/GeminiGroundingEvaluation/frozen-contract-v1.json \
  --validate-cases Tools/GeminiGroundingEvaluation/cases-v1.json
python3 -m unittest discover -s Tools/GeminiGroundingEvaluation/tests -v
```

To evaluate later captured output, copy `replay-template-v1.json` and `judgements-template-v1.json` to a private working location; fill one row for **every** case. Keep the Gemini key, interaction ID, raw provider envelope, personal data and Search-suggestion HTML out of the replay. Set `suggestions_present` from the app projection without storing the HTML. Run:

```sh
python3 Tools/GeminiGroundingEvaluation/evaluate.py \
  --contract Tools/GeminiGroundingEvaluation/frozen-contract-v1.json \
  --cases Tools/GeminiGroundingEvaluation/cases-v1.json \
  --replay /private/tmp/gemini-grounding-replay.json \
  --judgements /private/tmp/gemini-grounding-judgements.json \
  --output /private/tmp/gemini-grounding-report.json
```

Report lead precision@3, useful-lead@3, primary-lead@3, cited-text attachment, reviewed citation support, severe identity errors and nutrition-promotion errors for each split/family. A result with missing cases or missing review does not receive a quality score. `unverified` citations and inaccessible pages are shown in the denominator and not counted as supported. The scores are discovery diagnostics, not nutritional accuracy, statistical population estimates, app UX acceptance or permission to ingest a source. In particular, finding a current product page cannot prove that its label applies to a historical pack or that its data can be redistributed.

After a key owner separately authorises a bounded live run, capture and review the same visible food terms on the user's eligible account. Record model/version, date, request count and account charges separately from this offline artefact. Compare development and untouched holdout results, then decide whether a prompt/app change is warranted. This document does not grant live-call, spend or key-handling authority.

## Judgement rubric

- `exact_primary`: original manufacturer or authoritative composition record for the requested food and explicit variant/preparation, without claiming an unsupplied pack or formulation date.
- `useful_related`: source aids investigation but differs in a material variant, regional basis or preparation, or cannot establish exact identity. It must be labelled as an alternative.
- `irrelevant`: the page does not help source the queried food.
- `severe_mismatch`: the response presents a conflicting species, food, fat variant, raw/cooked state, recipe or pack as if exact. A merely labelled alternative is `useful_related`.
- `supports_cited_text`: `yes` only when the linked page actually supports the attributed text and its scope; `no` for contradiction or citation laundering; `unverified` if the page is inaccessible or insufficient. This is a page review, not the scorer's substring check.
- `distinctions_preserved`: all case-specific traps remain explicit or appropriately uncertain in the full answer. `promotes_unverified_nutrition` flags instructions to use model/page numbers directly for saving, source mixing, inferred density or an assertion of exact nutritional identity without an admission contract.

Review the same product's current label, code, pack, date and licence as separate questions before any eventual source-admission proposal under #144's successor. The 10.2 g/100 g CoFID Greek-style record may be a close **labelled** alternative to 10% Greek yoghurt; it is not an exact 10% product. A web result is not a substitute for this distinction.
