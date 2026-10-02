# Candidate v3: extraction passes development and first holdouts

**20/20 development requests and 4/4 reserved holdout requests passed** under the new evidence-binding contract. All 24 completed with no retries. The candidate was frozen and selected after development evidence review, before any holdout call. There was no post-holdout prompt tuning.

This supports proceeding to a narrowly scoped app prototype. It does not establish universal food-search accuracy or authorise automatic admission of web nutrition. The dataset is small and deliberately constructed; related cases reuse source pages. Holdouts used two new source domains and supplied panels, not live holdout-site retrieval.

| Evaluation | Result | What it establishes |
| --- | ---: | --- |
| Development supplied panels | 12/12 | Fields, basis, preparation, ambiguity, representative labels and cooked-weight arithmetic |
| Development fetched documents | 8/8 | Same contracts plus reviewed field/column references against four selected primary pages |
| First holdout supplied panels | 4/4 | Positive extraction and conflicting identity abstention on Odysea/Alpro sources |
| Observed discovery leads, offline resolution | 4/4 expected outcomes | One verified record, one claim conflict, two unresolved leads; not four verified sources |
| Local tests | 43 passed | 23 extraction/binding/resolution tests plus 20 discovery regression tests |

## Source identity is now application-owned

`evidence_binding.py` creates an immutable request envelope containing selected source ID, source URL, evidence-text SHA-256 and exact request SHA-256. The same source ID and content hash appear in the request input. Request/evidence mismatches are rejected.

The model response schema no longer permits `source_url`. The application adds that metadata from the selected request envelope after schema validation, and retains the unmodified model extraction separately. A model-supplied source override is rejected. This is a new versioned contract, not silent correction or rescoring of v2's missing URL. V1 and v2 files and results remain intact.

Binding proves which evidence was supplied, not that every claim is true. Nutrient fields still face strict comparison, evidence-location checks and source review. Production would need a defined admission policy beyond these eval reference checks.

## Discovered records are verified before use

`resolve_discovery.py` reads pinned existing local resource versions and passes plain records to the pure resolver. The four fixtures reproduce IDs and claims from the earlier v2 Search probe; there were no new search calls this turn.

- **CoFID 18-070:** resolves to the admitted grilled medium-rare, lean sirloin record. Energy, protein and fat claims match. The explicitly reviewed alias “lean only” is accepted for this record; no fuzzy matching or broad aliases are introduced. The result still requires user confirmation of the representative preparation.
- **USDA SR 169457:** record identity resolves, but the claimed 29.33 g protein conflicts with 29.3 g in the pinned release. The resolver returns `conflicting_claims`; it does not silently accept or repair the model's numbers. This is a mismatch against the admitted version, not proof that every current online version is wrong.
- **Soup IDs 2707462 and 2707460:** remain unresolved against the admitted releases. The local adapter handles these observed CoFID/SR leads, not the absent FNDDS release. No guessed nutrition, substituted record or automatic source admission follows.

The next app flow should offer independently verified candidates for explicit selection. A verified local record can provide its admitted nutrition directly; asking Gemini to recreate those known numbers adds no value. A new web-only source needs a checked document and its own admission rules. Unresolved search output must remain a lead.

## Descriptive foods and portions

For generic lentil-and-tomato soup, the selected CSPI recipe remains a labelled representative example with a one-cup basis. No grams-per-cup value was invented for the 250 g request. This does not solve discovery for an unspecified personal recipe.

For 250 g cooked sirloin, the selected cooked composition record remained per 100 g, with explicit medium-rare/lean assumptions. The deterministic calculation scaled by 2.5 and matched the frozen totals. The raw distractor was not used, and no cooking loss or yield was inferred. Confirmation is simulated in this evaluation; no real food entry was selected or saved.

The holdout preserved Odysea's declared zero fibre and calcium in mg; Alpro's per-100-ml basis, microgram nutrients and unknown iron; and abstained for the requested wrong fat variant and wrong plant-drink product. Holdout text came from the pre-frozen factual references. No additional live page checks or source changes were made after seeing holdout responses.

## Evidence and reproducibility

`frozen-contract-v3.json` pins the candidate files, earlier contract, resolution fixtures and full local resource hashes. `selected-candidate-v3.json` records the passing development replay and evidence review before holdout. `holdout-claimed-v3.json` is the exclusive one-time marker created before the holdout key read/POSTs. Keep it: these four cases are now consumed holdouts and must not be represented as fresh tests for later tuning.

`development-{replay,report,attempts}-v3.json` and `holdout-{replay,report,attempts}-v3.json` retain only reviewed public/synthetic projections, metadata and usage. No key, provider interaction ID, raw response envelope, retrieved HTML or hidden reasoning is retained. `evidence-review-v3.json` records the agent review, which is not a second human annotation.

The automatic fetched documents remain private and temporary at `/private/tmp/gemini-nutrition-v2-documents-host`. Their hash manifest was frozen before the v2/v3 calls. Exact document replay needs those files; refetching later creates a new snapshot. Development source review uses the unchanged source snapshots, not current formulation truth.

```sh
python3 -m unittest discover -s Tools/GeminiNutritionExtractionEvaluation/tests -v
python3 Tools/GeminiNutritionExtractionEvaluation/resolve_discovery.py
python3 Tools/GeminiNutritionExtractionEvaluation/candidate_v3.py \
  --documents /private/tmp/gemini-nutrition-v2-documents-host \
  --replay Tools/GeminiNutritionExtractionEvaluation/development-replay-v3.json
python3 Tools/GeminiNutritionExtractionEvaluation/candidate_v3.py \
  --documents /private/tmp/gemini-nutrition-v2-documents-host \
  --replay Tools/GeminiNutritionExtractionEvaluation/holdout-replay-v3.json
```

No app/Swift code, food database, credential configuration, issue or remote Git state changed. The work remains local and uncommitted. Simulator/static analysis/device tests were not run for these Python-only eval changes.

Provider telemetry across this turn's 24 calls: **61,067 total tokens** (47,144 input, 13,224 output, 699 thought; zero cached/tool-use tokens reported). Actual account charges were not read or estimated. Assistant engineering/research usage is excluded.

## Next implementation boundary

Prepare a reviewed-candidate prototype: explicit Gemini tap, verified candidate selection, application-bound source metadata, clear representative-food assumptions, and review of source-supported nutrition and edible cooked quantity. Keep unresolved sources and unsupported mass conversions visible. Add broader independent evaluation before treating this small-set result as production reliability; use new holdouts for future tuning. Any production nutrition admission changes the current discovery-only contract and needs an explicit versioned design.
