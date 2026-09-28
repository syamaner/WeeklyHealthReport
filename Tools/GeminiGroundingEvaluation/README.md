# Gemini grounded food-source discovery: offline evaluation

These are frozen, public/synthetic evaluation sets for [#172](https://github.com/syamaner/WeeklyHealthReport/issues/172). They test whether an explicit-tap Gemini response helps a person find original food sources, while keeping source leads separate from admitted nutrition. The scorer makes **no provider call** and does not itself score the app, a Gemini model, a signed device or a user key. User-reported yoghurt and milk phrases are included; all other inputs are public or synthetic and contain no food history.

## Architecture and evaluation boundary

- The frozen case file owns query families, split, intended source-discovery task and identity/preparation traps. It contains no provider response, provider-specific type or nutrition ground truth.
- A replay is a privacy-reviewed projection of the app's `FoodWebDiscoveryResult`: response text, cited leads and whether Search suggestions were supplied. A future collector may use any provider adapter, but this scorer makes no network call and has no key access.
- An independent reviewer opens each linked page, checks the cited passage against the page and the food terms, then records lead grade, claim support and answer-level hazards in a separate judgement file. For v2 judgements the reviewer also records the final page URL after any grounding redirect, or `null` if inaccessible. Unknown or inaccessible pages stay `unverified`, never automatically correct. The reviewer records a check date and evidence note; URL match or HTTPS alone cannot prove grounding.
- `evaluate.py` validates complete case coverage and emits counts by family and split. Its automatic checks cover only schema, link shape and cited-text attachment. V2 judgements group citation annotations by the reviewer's final page URL before computing page-level top-three metrics; citation support remains annotation-level. Legacy v1 judgements still yield the original annotation-level report and are labelled as such. Its relevance and truth metrics come from the independent judgements. A provider cannot alter the case file or judgement rubric.
- The stable safety invariant is that neither a model's number nor a cited page becomes admitted nutrition, product identity or saved food. A severe identity/preparation mismatch, unsupported citation or promoted nutrition is reported explicitly. This eval cannot itself authorise source admission.

V1 has 12 development and four holdout cases. Its SHA-256 was fixed before the local live baseline, but all 16 outputs were inspected on 28 September 2026. V1 remains a regression comparator, not unseen holdout evidence for prompt tuning. V2 keeps those 16 cases as development cases, adds 12 new development cases and freezes 12 fresh holdout cases: 28 development and 12 holdout in all. No Gemini output for the new cases was collected before the v2 hash was frozen. Keep the 12 v2 holdout outputs and judgements out of prompt selection; inspect them once after choosing a candidate on development cases. If a holdout informs another revision, freeze fresh cases for the next evaluation.

V2 covers dairy fat, liquid quantity basis, raw/cooked and skin preparation, grain and potato preparation, count-to-edible-weight uncertainty, whole dishes and branded pack identity. This is a focused challenge set, not a representative sample of user searches. The separately frozen [holdout pre-review](holdout-evidence-v2.md) records source candidates and explicit gaps before any new provider output; its hash is in the v2 contract. New case rows themselves have no example source URLs. Before scoring a live run, an independent reviewer must open its cited pages and record evidence for every lead; an empty `source_leads` list is neither a failure nor proof of correctness. Source examples are leads for independent review, not an exhaustive URL allowlist or licensed nutrition data. A reviewer can credit a different original source when the evidence supports it.

CI runs the frozen-hash validation and scorer tests as a separate offline job. It does not contact Gemini or review any real response.

## Reproduce offline

```sh
python3 Tools/GeminiGroundingEvaluation/evaluate.py \
  --contract Tools/GeminiGroundingEvaluation/frozen-contract-v2.json \
  --validate-cases Tools/GeminiGroundingEvaluation/cases-v2.json
python3 -m unittest discover -s Tools/GeminiGroundingEvaluation/tests -v
```

To evaluate later captured output, copy `replay-template-v1.json` and `judgements-template-v2.json` to a private working location; fill one row for **every** case and one judgement per citation annotation. Open the final page behind each citation redirect and record its HTTPS URL as `resolved_url`; use `null` and `unverified` when it cannot be checked. Keep the Gemini key, interaction ID, raw provider envelope, personal data and Search-suggestion HTML out of the replay. Set `suggestions_present` from the app projection without storing the HTML. Run:

```sh
python3 Tools/GeminiGroundingEvaluation/evaluate.py \
  --contract Tools/GeminiGroundingEvaluation/frozen-contract-v2.json \
  --cases Tools/GeminiGroundingEvaluation/cases-v2.json \
  --replay /private/tmp/gemini-grounding-replay.json \
  --judgements /private/tmp/gemini-grounding-judgements.json \
  --output /private/tmp/gemini-grounding-report.json
```

The v2 report uses distinct reviewed source pages for page precision@3, useful-page@3 and primary-page@3. It also reports citation-annotation count, duplicate annotations, cited-text attachment, reviewed citation support, severe identity errors, unrequested nutrient-number quotes, consumed-amount-as-pack errors and nutrition-promotion errors for each split/family. A result with missing cases or missing review does not receive a quality score. `unverified` citations and inaccessible pages are shown in the denominator and not counted as supported; an unresolved redirect is conservatively a distinct unverified source identity. The scores are discovery diagnostics, not nutritional accuracy, statistical population estimates, app UX acceptance or permission to ingest a source. In particular, finding a current product page cannot prove that its label applies to a historical pack or that its data can be redistributed.

For a bounded live run, capture and review the same visible food terms on the user's eligible account. Record model/version, date, request count and account charges separately from this offline artefact. A collector must journal each attempted case before its POST, save each completed privacy-reviewed projection before starting the next request, record non-`completed` status or timeout without saving the raw envelope or interaction ID, and leave incomplete cases unscored. Do not retry a case automatically. Compare prompt candidates on the 28 development cases, choose one, then run the 12 untouched v2 holdouts once. An earlier 16-case live run was separately authorised; this document does not grant further live-call, spend or key-handling authority.

`prompt-baseline-v1.txt` copies the current app instruction for paired comparison. `prompt-candidate-v2.txt` through `prompt-candidate-v6.txt` are development-only candidates, not app prompts. A 28 September 2026 pilot attempted three v2 cases and produced no saved, scoreable replay: one completed result was lost by a collector that wrote only at batch end, one interaction returned a non-`completed` status that was not recorded, and one request timed out before an HTTP response. No claim of improvement follows from that attempt; the app instruction remains unchanged. A private attempt memo is retained at `/private/tmp/gemini-grounding-prompt-v2-pilot-20260928.md`.

The [development pilot findings](pilot-findings-2026-09-28.md) record paired low-thinking yoghurt/milk observations and five-case v3–v6 checks. Each five-case run completed, but page and claim defects remain, so no candidate has been selected or promoted to the app. These partial development captures do not receive a whole-set quality score. The 12 v2 holdouts remain untouched.

`diagnose_citations.py` accepts a partial privacy-reviewed replay and flags only a syntactic inconsistency: a model-written Markdown link host differs from the provider citation's domain-shaped title or direct URL host. Opaque Google redirect links are counted separately, since their destination cannot be inferred from their visible host. This diagnostic makes no network call and cannot verify that a linked page exists, identifies the food or supports the cited words. Independent page review remains mandatory. For example:

```sh
python3 Tools/GeminiGroundingEvaluation/diagnose_citations.py \
  /private/tmp/gemini-grounding-v6-low-five-20260928/replay.json
```

`collect_local.py` is the repaired, development-only capture adapter. It checks the frozen contract before reading the named Mac Keychain item, sends the app-shaped request, and creates a new owner-only output directory. `attempts.json` is written before each POST; each completed response is reduced to `replay.json` before another request begins. A timeout, non-`completed` status, invalid response or HTTP error stops the run without retrying. Neither file stores the credential, raw reply, interaction ID or suggestion HTML. Its transport and journalling behaviour are tested with synthetic responses. A one-case `g12` live smoke run completed and preserved both files under `/private/tmp/gemini-grounding-prompt-v2-smoke-g12-20260928/`; it is not a whole-set quality score. The candidate returned an exact-GTIN [KFF/Erudus distributor specification](https://www.kff.co.uk/erudus/pdf/basic/19b8857973cc4c28977c8934a10a0a52) and a crowdsourced product entry, but did not return the related [Kraft Heinz manufacturer case page](https://www.kraftheinzawayfromhome.com/en-GB/products/05000157014009-baked-beans-6-x-2-62-kg). This is insufficient to adopt the candidate as the app prompt.

```sh
python3 Tools/GeminiGroundingEvaluation/collect_local.py \
  --contract Tools/GeminiGroundingEvaluation/frozen-contract-v2.json \
  --cases Tools/GeminiGroundingEvaluation/cases-v2.json \
  --prompt Tools/GeminiGroundingEvaluation/prompt-candidate-v6.txt \
  --case-id g01 --max-requests 1 \
  --thinking-level low \
  --keychain-service YOUR_MAC_KEYCHAIN_SERVICE \
  --output-dir /private/tmp/gemini-grounding-new-run \
  --run-id development-pilot
```

Only development case IDs are accepted. A new output directory and an explicit request cap are required for each run. `--thinking-level` is optional; omitting it preserves the app request shape, while `low`, `medium` or `high` makes a development-only configuration change. A partial replay is evidence of captured cases, not a valid whole-set score; `evaluate.py` still requires every case and independent page judgements.

## Judgement rubric

- `exact_primary`: original manufacturer or authoritative composition record for the requested food and explicit variant/preparation, without claiming an unsupplied pack or formulation date.
- `useful_related`: source aids investigation but differs in a material variant, regional basis or preparation, or cannot establish exact identity. It must be labelled as an alternative.
- `irrelevant`: the page does not help source the queried food.
- `severe_mismatch`: the response presents a conflicting species, food, fat variant, raw/cooked state, recipe or pack as if exact. A merely labelled alternative is `useful_related`.
- `supports_cited_text`: `yes` only when the linked page actually supports the attributed text and its scope; `no` for contradiction or citation laundering; `unverified` if the page is inaccessible or insufficient. This is a page review, not the scorer's substring check.
- `distinctions_preserved`: all case-specific traps remain explicit or appropriately uncertain in the full answer. `promotes_unverified_nutrition` flags instructions to use model/page numbers directly for saving, source mixing, inferred density or an assertion of exact nutritional identity without an admission contract.
- V2 `quotes_unrequested_nutrition` flags energy or nutrient quantities in the answer beyond food-identifying terms explicitly supplied by the user, even if the model does not recommend saving them. `misreads_consumed_amount_as_pack` flags a request amount treated as a required retail package size without user evidence.

Review the same product's current label, code, pack, date and licence as separate questions before any eventual source-admission proposal under #144's successor. The 10.2 g/100 g CoFID Greek-style record may be a close **labelled** alternative to 10% Greek yoghurt; it is not an exact 10% product. A web result is not a substitute for this distinction.
