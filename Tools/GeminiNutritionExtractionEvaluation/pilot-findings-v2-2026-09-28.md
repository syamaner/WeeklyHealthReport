# Candidate v2 results — 28 September 2026

Fetched-document extraction passed all eight development tasks. Across both conditions, the unchanged strict reference gate passed 19/20 cases, up from 4/20 in v1. All declared values, units, operators, unknown states, food variants, preparations and denominators matched. One supplied-panel response omitted its source URL. The four holdouts remain untouched, and nothing has been promoted to the app.

| Condition | Completed | Strict pass | Evidence |
| --- | ---: | ---: | --- |
| Supplied factual panels | 12/12 | 11/12 | Same frozen v1 facts; source URL missing in n04 |
| Automatically fetched page text | 8/8 | 8/8 | Four primary source pages; field line pointers checked |
| Separate descriptive-food Search probes | 2/2 | No formal benchmark score | Source identity/provenance problems remain |

This was 22 Gemini requests, with no retries. The four-page fetch initially failed under the network sandbox before succeeding with authorised host network access. There were no provider calls during that sandbox fetch failure. Document extraction uses automatic HTML text conversion retaining menus, recommendations and table columns, not hand-selected nutrition facts. Script/style/template text is removed; no browser rendering or CSS-visibility computation is performed. The pages are small; PDFs, JavaScript-only pages, anti-bot responses and other languages remain untested.

## What improved

The explicit equality-marker instruction fixed all 96 operator omissions observed in v1's two conditions; v2 itself contains different URL-versus-document conditions, so this is not a same-transport causal comparison. The unchanged gold and strict comparison still require `=` for declared values and preserve inequalities. The explicitly selected CoFID record was correctly distinguished from a generic representative choice. No post-processing changed model values or repaired a missing operator.

The host fetch retrieved all four selected pages, including Olympus yoghurt and Graham's milk. All eight document tasks passed identity, preparation, basis, nutrient fields and line-reference checks. Independent agent review checked adjacent nutrient labels and preparation headers as well as numeric lines; a line containing a number alone is not field proof. This is a small development challenge set with correlated repeated pages, not general accuracy evidence.

## Soup and cooked sirloin

- The selected CSPI soup recipe stayed a representative example, with a one-cup nutrition basis. Its 250 g variant explicitly said gram scaling was unavailable without measured yield/density. Both supplied-panel and fetched-document cases passed.
- The supplied CoFID sirloin cases chose cooked, grilled medium-rare lean meat instead of the raw distractor. Generic wording retained the representative qualification. Explicit record selection retained source-record qualification. Deterministic scaling from 100 g to 250 g matched the frozen portion totals; no cooking yield was invented.
- These extraction tests begin with a selected source. The separate Search probes below test whether the earlier discovery stage can supply a trustworthy candidate. Neither probe constitutes the user's confirmation of an actual meal.

## Discovery still needs a source-verification step

For **lentil and tomato soup**, Gemini wrote links to USDA FNDDS IDs 2707462 and 2707460 and supplied recipe assumptions and nutrition. The provider citation titles instead pointed to third-party sites (`myfoodanalysis.com`, `saciedad.com`). The named USDA links could not be opened by the independent web tool (404). That does not prove the records are false, but the primary identity and claimed facts remain unverified. No candidate was accepted for downstream extraction or scaling. Citation-title disagreement is a diagnostic, not proof of the final redirect destination; redirects were not independently resolved in this probe.

For **250g cooked weight sirloin**, the CoFID candidate identified code **18-070**, matching the existing admitted local record `Beef, sirloin steak, grilled medium-rare, lean`. Its reported energy, protein and fat match the resource. This gives a credible path to resolve a discovered lead against an already admitted record, then ask the user to confirm the preparation. The separate USDA 169457 candidate matched the record identity but reported **29.33 g protein/100 g**, versus **29.3 g** in the admitted local USDA release. The current USDA page could not be independently read, so this is a mismatch against our admitted version, not proof of a current-source error. Some added cooking assumptions were not independently established. A readable answer and plausible arithmetic are insufficient to accept all its claims.

Consequently this turn did not establish a complete successful free-text-to-confirmed-food flow for both phrases. It exposed a real discovery-to-evidence boundary. The pipeline must stop at unresolved source identity instead of sending unverified model claims into extraction. No additional call can manufacture confirmation or missing source evidence.

## Remaining extraction defect and next design

The frozen-McCain **panel** case n04 returned `source_url: null`, although the request included the selected URL. Every nutrient field was correct. Its separate **document** case returned the URL and passed. The strict baseline remains **19/20**; it has not been rescored or silently repaired.

For the next version, source identity should be bound by application orchestration to the selected evidence document and its hash. The model should extract fields and evidence locations, not recreate request metadata. Preserve the model's reported source for discrepancy diagnostics; reject a conflicting source rather than letting it replace the selected one. This is a versioned envelope change with contract tests, not permission to label all source text correct or admit nutrition. Keep explicit candidate confirmation separate from representative-food assumptions and deterministic portion arithmetic.

A further live run or holdout run was not launched. The frozen advancement rule requires all development cases and evidence checks to pass; the missing source URL and unresolved soup discovery prevent that claim. The next experiment should cover verified source resolution plus the revised evidence envelope before spending the holdouts. Avoid merely extending prompts until the benchmark passes.

## Reproduction and artefacts

- `frozen-contract-v2.json`: hashes of unchanged gold, candidate prompt/schema, collector/scorer/fetcher and pre-run design; document manifest hash.
- `pilot-replay-v2.json`, `pilot-attempts-v2.json`, `pilot-report-v2.json`: public/synthetic projected responses and the unchanged strict result.
- `document-manifest-v2.json`: selected/retrieved URL, timestamps, HTML/text hashes. Full text is private at `/private/tmp/gemini-nutrition-v2-documents-host`; raw HTML was discarded. These temporary files are needed for line-level replay and may not survive cleanup. Refetching later is a new snapshot, not an exact reproduction.
- `evidence-review-v2.json`: agent field/column review and separate discovery findings, not independent human annotation.
- `discovery-probe-v2.json`: two public-query response projections, including provider citation annotations. They are unverified model output, not an admitted nutrient source.

```sh
python3 -m unittest discover -s Tools/GeminiNutritionExtractionEvaluation/tests -v
python3 Tools/GeminiNutritionExtractionEvaluation/candidate_v2.py \
  --documents /private/tmp/gemini-nutrition-v2-documents-host \
  --replay Tools/GeminiNutritionExtractionEvaluation/pilot-replay-v2.json
```

The exact adapter/scorer inputs were frozen before collection. v1 files and results remain unchanged. No Swift/app code, database, credential configuration or remote GitHub state changed.

Provider telemetry: extraction reported 51,405 total tokens (39,722 input, 11,683 output); discovery reported 1,788 total (265 input, 1,523 output, 109 cached reported separately). Total **53,193** across 22 requests. Tool/thought counters were zero as reported; that does not establish zero Search charges. No account bill was read or estimated. Assistant research/development usage is excluded.
