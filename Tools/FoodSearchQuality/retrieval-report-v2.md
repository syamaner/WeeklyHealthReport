# Ranked retrieval development report v2

48 exposed, same-author synthetic scenarios run through bundled CoFID, bundled USDA and their actual composite (144 replay rows). These are development/regression evidence, not independent acceptance or production retrieval accuracy. Queries include yoghurt spelling and numeric fat variants, ribeye spacing/hyphens and preparation, clementine plurals, mass/count-bearing searches, unrelated terms and honest catalogue misses. No device feedback is included.

Record-level judgements were fixed before tuning. `judgement-revisions.md` records two pre-tuning v1 author errors; the baseline and final results below both use corrected v2 labels with identical query text. Source-specific labels cover the complete relevant catalogue, not just retrieved candidates. Preparation scenarios pass the parsed raw/cooked constraint as the presentation flow does. Generic ribeye intent uses beef relevance, not bison; unqualified yoghurt gives plain records the highest grade. These are explicit evaluation conventions, not assertions of the user's product identity.

| Source | Relevant coverage / 48 | Hit@1 before → after | Hit@5 before → after | MRR before → after | nDCG@5 before → after |
|---|---:|---:|---:|---:|---:|
| cofid | 9 | 0.000 → 1.000 | 1.000 → 1.000 | 0.500 → 1.000 | 0.876 → 1.000 |
| usda | 24 | 0.792 → 1.000 | 0.875 → 1.000 | 0.833 → 1.000 | 0.783 → 1.000 |
| composite | 27 | 0.593 → 1.000 | 0.889 → 1.000 | 0.741 → 1.000 | 0.771 → 0.976 |

Hit/MRR denominators are relevant-coverage cases (27 composite), excluding catalogue gaps. nDCG uses the whole labelled catalogue ideal and includes tentative-only cases (36 composite); an all-grade-1 ranking can score 1 without returning a requested numeric fat match. Do not read that as successful exact retrieval.

| Composite family | Cases | Relevant coverage | Hit@1 before → after | MRR before → after |
|---|---:|---:|---:|---:|
| catalogue-miss | 5 | 0 | — → — | — → — |
| clementine | 5 | 5 | 1.000 → 1.000 | 1.000 → 1.000 |
| ribeye | 6 | 6 | 1.000 → 1.000 | 1.000 → 1.000 |
| ribeye-preparation | 4 | 4 | 0.500 → 1.000 | 0.750 → 1.000 |
| unrelated | 7 | 0 | — → — | — → — |
| yoghurt-fat | 15 | 6 | 0.500 → 1.000 | 0.500 → 1.000 |
| yoghurt-spelling | 6 | 6 | 0.000 → 1.000 | 0.500 → 1.000 |

Composite confusion matrix before: 24 relevant requests retrieved relevant records, 3 retrieved only tentative alternatives; 9 tentative-only requests returned tentative alternatives; all 12 empty-catalogue cases returned empty. After: all 27 relevant requests retrieve relevant records; the 9 tentative-only and 12 empty cases are unchanged. Full per-source/per-family confusion matrices and per-case ranks are in the metrics JSON.

Numeric fat mismatch exposure at rank 1 decreases from 12 to 9; the remaining 9 are coverage gaps for 0%, 2% and 10%, not ranking failures. In the 6 covered numeric-fat scenarios it falls from 3 to 0. Mismatch exposure in the first five decreases from 72 to 69: visible alternatives remain, with explicit source-fat notes, and do not become exact variants. CoFID plain Greek yoghurt reports 10.2 g/100 g and USDA has a 5 g/100 g record; neither establishes product identity. No tolerance-based fat equivalence is introduced.

Demonstrated repairs: plain yoghurt ranks ahead of flavoured records for unqualified queries; exact numeric source-fat agreement is promoted before each adapter's ten-result limit (the 5 g/100 g USDA record was previously discarded); unspecified cooked ribeye prefers beef over bison, while explicit species and hard preparation constraints still control retrieval. Query parsing is cached once per adapter. Policy versions advance; source scores remain bounded ranking hints, not probabilities. Source records, nutrition and provenance remain unchanged. All 28 common whole records have identical source, identity, edible basis and nutrients across baseline/final replays.

Catalogue gaps remain separate: CoFID has no named ribeye or clementine records in this projection; composite coverage comes from USDA. The 9 differing-fat cases retain tentative alternatives. The combined fish-and-chips requests and unrelated/missing names stay unresolved. No additional sources or Gemini fallback are added.

Replay files preserve original query, complete source release identity, candidate identity, edible basis, unknown nutrient states, nutrient provenance and fat notes. Baseline, intermediate and final compressed captures are retained, with hash binding in `retrieval-reproduction-v2.json`; older query parsing and search diagnostics are untouched. The final report is reproduced in CI and checked for drift, which is a development regression gate only.

Validation: 199 FoodLedgerKit tests (one opt-in offline replay skipped, zero failures; including three new replay/ranking contracts), package boundaries, four retrieval scorer tests, six parser scorer tests, the unchanged 511-case parser gate, 26 CI-helper tests, 273 passing iOS simulator tests and successful Xcode analysis. See PR checks for exact-head hosted outcomes. Simulator tests do not establish device usability; build 0.1.1 (9) feedback remains separate. No provider calls, spend, credentials or new TestFlight upload.
