# Search quality development contract v3

Issue #148, based on merged PR #149 (`d3c3361`). This is a development refinement, not independent retrieval acceptance.

## Architecture gate

Domain nutrition, identity, evidence and schema rules remain closed. Infrastructure adapters own corpus vocabulary, lexical equivalents and source-local ranking. The application composite owns deterministic exposure of distinct source records, without comparing source scores or merging nutrients. Presentation owns explicit suggestion actions and carries the original evidence through them. Existing ports, provenance records and composition-root wiring remain sufficient; no provider, persistence or universal ranking framework is added.

Extension axes are additional adapters and future evaluated ranking policies. Contract tests protect original query evidence, full record provenance, exact saved reuse, hard preparation filters, no silent typo correction, meaningful-token coverage, schema-bounded scores and deterministic source interleaving. The development runner uses actual Swift adapters and public/synthetic queries, without network traffic.

## Versioned retrieval

- CoFID: `deterministic-primary-name-v3`. Existing eligibility threshold applies before normalisation; a 0.15 primary-name bonus is added when all comma-delimited main-name tokens occur in the query. The score is divided by 1.15 and clamped for floating-point rounding within the existing [0,1] schema.
- USDA: `usda-primary-name-v3`. Complete meaningful-term coverage remains mandatory. A 0.3 primary-name bonus is added to candidate coverage, then divided by 1.3.
- Shared lexical policy: `food-lexical-terms-v3`. Adds chickpea/chick peas/peas chick and courgette/zucchini equivalents to existing plurals and aliases. Original strings, saved aliases, decisive identity and source records remain unchanged. Candidate metadata records the lookup terms.
- Composite: `composite-interleaved-search-v2`. Exact saved reuse remains first. Exact source names precede other candidates; otherwise source-local ranks are interleaved in configured source order (UK CoFID then US USDA). No unlike scores are compared, duplicate records are fused or nutrient values backfilled. The expected confirmation identity/quantity comes from the first displayed candidate.
- On a miss, suggest at most three complete corpus-backed queries with one unknown word of at least five letters changed by one insertion/deletion/substitution. Other words must all occur in the supporting record. Known food words, short queries and multiple unknown words are never silently reinterpreted. Suggestions do not select candidates and still require a separate search and confirmation. Existing combined fish-and-chips guidance remains explicit component recovery.

## Evidence and limitations

Suggestion actions retain every original query and upstream capture record, preserve the current preparation filter, and deduplicate already supplied evidence. A normal independent search starts a new query; it does not silently accumulate earlier unrelated searches.

`Tools/FoodSearchQuality` contains the 44-query baseline and paired actual-adapter report. Eight narrow main-food-prefix judgements and source visibility in the first five are development diagnostics. They do not establish nutrition/cut/recipe identity or production accuracy. No independent human labels, held-out acceptance, new live source probe or physical-device check is claimed. Plain food variants such as raw/dried, whole/white egg or milk type still require explicit user review; no unrequested variant is declared correct. Mixed dishes remain distinct source records and no recipe is synthesised.

## Validation — 26 September 2026

All 175 FoodLedgerKit tests passed (five new development/behavioural tests). Full iPhone 17 Pro simulator suite and Xcode static analysis passed. Dependency boundaries and `git diff --check` passed. The paired report preserves 35/44 queries with candidates, raises candidate-or-guidance recovery from 37/44 to 40/44, moves the eight narrow main-food-first checks from 2/8 to 8/8, and exposes both admitted sources within the first five for 27 queries instead of 7. These are development results on the disclosed tuning sample. No new release, live provider request or physical-device acceptance was performed during this phase.

## Fruit plural repair — retrieval v4

The reported `clementine` miss was caused by the USDA name `Clementines, raw` lacking a retrieval equivalent. Shared lexical policy `food-lexical-terms-v4` explicitly maps common citrus, grape, pear, stone-fruit and berry plurals to their singular terms. Both adapter matcher versions advance to `primary-name-v4`; ranking formulas remain unchanged. Exact saved-alias normalisation, original evidence, source identities and nutrients remain unchanged.

The actual-adapter regression checks 14 singular/plural pairs in each source and the composite, requiring identical ordered record IDs and preserved original query evidence. A source may still lack the fruit, but USDA and the composite must find clementine. `clementine beef` must remain a miss. This is a bounded regression check, not independent accuracy acceptance.

## Current v4 reproduction — 27 September 2026

The actual Swift v4 adapters were rerun on the same 44 public/synthetic queries after the plural repair. Candidate/recovery/main-food/source-visibility denominators remain 35/44, 40/44, 8/8 and 27 queries respectively. The paired comparison is byte-identical to the historical v3 comparison artifact. `Tools/FoodSearchQuality/v4-reproduction-manifest.json` binds this reproduction to exact adapter/orchestration source hashes, current report hash and the unchanged comparison hash. The report envelope remains schema `search-development-v3`; this is distinct from retrieval policies v4. The separate 14 fruit singular/plural pairs still protect clementine and other reported variants. No new independent labels, provider request or device-accuracy claim is introduced.
