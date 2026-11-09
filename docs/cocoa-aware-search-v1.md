# Cocoa-aware generic food search v1

Phase A of #381, issue #382. Background, reproduction and source survey: [dark-chocolate-nutrient-sources-investigation.md](dark-chocolate-nutrient-sources-investigation.md). This phase uses only the bundled CoFID 2021 and USDA corpora. It adds no source, no network destination and no nutrient value. The text sent to the existing online routes changes for some queries; see "Online search terms".

## Problem

A typed cocoa percentage is parsed but then ignored by offline search, so the composite search can put a 45 to 59% row first for a 90% or 100% request and say nothing about it. Several common phrasings ("100% cacao", "85% cocoa chocolate", "dark chocolate 85 per cent", "chocolate 85% cocoa solids") either clarify, return hot cocoa drinks or return nothing. CoFID's UK name for dark chocolate ("Chocolate, plain", described as 36 to 50% cocoa solids) is not reached by "dark chocolate", whose only CoFID hit is a mint fondant row.

## Owner decisions (3 November 2026)

- A 100% cocoa request offers USDA FDC 167568 "Baking chocolate, unsweetened, squares" as a labelled estimate. It is never selected or saved automatically, and its missing keys stay unknown.
- A request between 86% and 99% ranks the nearest band below it (USDA 70 to 85%) first, with a visible note. Nothing is interpolated.

## Rules

### 1. Parser: `food-query-parser-v11`

All changes are inside `FoodQueryParser`, so the standalone FoodQueryEvaluation build (which compiles only the parser and the discovery policy) still compiles. The cocoa word lists live in the parser.

1. **"per cent" is "percent".** `per cent` and `per-cent` are accepted wherever the parser recognises `percent`: the main percentage pattern, the relative-percentage check ("10 per cent less fat" gives `relative_percentage`), the percentage-range check (so "70-85 per cent dark chocolate" clarifies exactly as "70-85% dark chocolate" does) and the "N% or M" check. This applies to every percentage key, so "10 per cent fat yoghurt" becomes `fat_percent=10` (v10 left an unresolved number).
2. **Cocoa wording names the cocoa key, in chocolate context only.** A percentage becomes `cocoa_percent` when the text contains "chocolate" (as in v10). It also becomes `cocoa_percent` when it is directly followed by `cocoa` or `cacao` (optionally followed by `solids`), or directly preceded by `cocoa solids` or `cacao solids`, provided that after removing the percentage and that cocoa wording the remaining food words are either empty or include `chocolate`, or are all within {dark, plain, bitter, bittersweet, extra}.
3. **Other cocoa products keep v10 behaviour.** Rule 2's cocoa-wording route does not apply if the text names any of: powder, butter, nib, nibs, paste, mass, liquor, bean, beans, tea, drink, hot, mix, beverage, spread. "100% cocoa powder", "100% cacao paste", "100% cocoa mass", "70% cocoa beans", "cacao nibs 100%" and "100% cocoa butter" still give `unspecified_percent` with `percentage_meaning_unknown`, as in v10. "85% cacao bar" also keeps v10 behaviour because "bar" is outside rule 2's word set.
4. **Cocoa words leave the food text** only when rule 2's cocoa-wording route applied. "85% cocoa chocolate" and "chocolate 85% cocoa solids" search "chocolate"; "dark chocolate 70% cacao" searches "dark chocolate".
5. **A bare cocoa percentage searches chocolate.** If rule 2's cocoa-wording route applied and either no food word remains ("100% cacao", "85% cocoa") or only words from {dark, plain, bitter, bittersweet, extra} remain ("dark 90% cocoa"), `chocolate` is appended to the food text and the route is `search`. No reason code is added, because any reason routes the query to clarification; instead `CocoaPercentPolicy` recognises the rewrite when the parsed food contains "chocolate" and the original text does not. This is an interpretation for retrieval only: it is never stored as identity, the original text remains the stored evidence, and the "Searched as chocolate with N% cocoa." note is shown on every result row and in the no-result state.
6. **Conflicts.** Two different cocoa percentages ("dark chocolate 70% cocoa 85% cocoa") give `conflicting_variants`, as the existing rule does for any repeated key.
7. **Case and spacing.** Matching is case-insensitive and accepts "85%cocoa" and "85 % cacao", as the existing percentage pattern does.

Unchanged: percentages outside 0 to 100 stay invalid; a percentage with `fat` stays `fat_percent`; "100% peanut butter" stays `ingredient_percent`; "cocoa solids 90" with no `%`, `percent` or `per cent` stays an unresolved number.

### 2. Cocoa band of a source row: `cocoa-percent-policy-v1`

A new pure application type, `CocoaPercentPolicy`, gives each candidate either a **declared band**, read from source text, or the one **owner-approved estimate band**.

Declared bands come from the candidate name and, for CoFID, the description the candidate carries as its variant. No band is inferred from nutrients.

- A range `L-U%` or `L- U%`, or the same with an en dash (U+2013) in place of the hyphen, directly followed by `cacao solids` or `cocoa solids`, outside parentheses, is the closed band [L, U]. This reads USDA "Chocolate, dark, 45- 59% cacao solids", "60-69%" and "70-85%", and CoFID's description "36-50% cocoa solids" for 17-491 "Chocolate, plain".
- A single `N%` directly followed by `cocoa` or `cacao` (with or without `solids`), outside parentheses, is the point band [N, N], unless an ingredient word follows (`butter`, `powder`, `mass`, `liquor`, `paste`, `nib(s)`, `bean(s)`): "30% cocoa butter" states an ingredient, not the chocolate's band.
- Text inside parentheses is never a band. USDA 170274 "Candies, chocolate, dark, NFS (45-59% cacao solids 90%; ...)" describes a blend and is classed as **blend, no single band**.
- Invalid readings give no band: L > U, a bound outside 0 to 100, or more than one distinct band in the same text.

The estimate band is a closed list of one, keyed by identity rather than name: the USDA SR Legacy record FDC 167568 in the bundled release gets [100, 100] marked as an estimate. Basis: US standards of identity name unsweetened baking chocolate as chocolate liquor, which is finely ground cacao nibs with 50 to 60% cacao fat ([21 CFR 163.111](https://www.law.cornell.edu/cfr/text/21/163.111), checked 3 November 2026). Optional ingredients (butter, salt, spices and others) are permitted, so it stays an estimate for a 100% bar, never the user's product. Excluded on purpose: 167567 "Baking chocolate, unsweetened, liquid" (a different, pourable product) and 167999 "Baking chocolate, mexican, squares" (sweetened and spiced). A guard test fails if 167568's name in the bundled corpus ever changes.

### 3. Eligibility exception, ordering and notes

**Scope.** Every rule in this section applies only when the parsed food words are all within {dark, plain, bitter, bittersweet, extra, chocolate}. The parser keeps v10's cocoa key for any text containing "chocolate", so "chocolate milk 2%" or "chocolate cake 70%" still carry `cocoa_percent`, but they get no cocoa eligibility, ordering or notes (invariant review finding 3).

1. **Eligibility exception (versioned, owned by `cocoa-percent-policy-v1`).** Generic search normally requires every meaningful query word in the source name (`generic-food-ranking-v7`, CoFID and USDA predicates). Two closed exceptions are added:
   - **Cocoa percentage admission.** When the parsed query has `cocoa_percent` and its food words are all within {dark, plain, bitter, bittersweet, extra, chocolate}, a row with a declared band or the estimate band is admitted even if it lacks a query word, provided its name contains `chocolate` and does not name an unrequested chocolate type from {milk, white, ruby}.
   - **UK name equivalence.** A query whose food words are exactly {dark, chocolate} also matches CoFID's "Chocolate, plain" names, because "plain chocolate" is the UK name for dark chocolate. This is an explicit equivalence, not a band rule.
   All other source guards (food form, derivative names, identity contradictions, CoFID score floor) still run.
2. **Ordering is one stable function** in `CocoaPercentPolicy`, applied by each source to its ranked rows **before its 10-row cut**, and again by the composite across sources. Single-source callers therefore get the same order by construction. Tiers, only when `cocoa_percent` is present:
   1. rows whose band (declared or estimate) contains the requested value;
   2. otherwise, rows whose band has the greatest upper bound below the requested value; if several share it, they keep the existing order;
   3. other banded rows, by distance from the requested value, ties in the existing order (a request below every band therefore starts here, with the nearest band);
   4. rows with no band, including blends, in the existing order.
3. **Composite key order** becomes: preparation verification, then regional deferral (Taiwan rows stay after UK and US rows unless promoted), then cocoa tier, then exact name and representation preference, as today. The fat partition and the outer preparation partition are unchanged. Without `cocoa_percent` the tier key is constant, so the order is exactly today's.
4. **Representation.** `generic-representation-ranking-v9` adds `fondant`, `centres` and `centred` to the unrequested specialisation descriptors, so "Chocolate, dark, with crème or mint fondant centres" no longer leads "dark chocolate" but still appears, and still leads "mint dark chocolate". `filled` is deliberately not added: it would move USDA "Milk, filled, fluid, with lauric acid oil" in the frozen "milk" scenarios and would penalise "not filled" names.
5. **Notes.** `CocoaPercentPolicy` owns both the detail note (used by `FoodQueryCandidateAssessment.note`) and the short row caution (used by `FoodSearchResultText.caution` in `FoodSearchStatusPresentation.swift`). Presentation only displays them. Only when `cocoa_percent` is present:

   | Case | Detail note | Row caution |
   | --- | --- | --- |
   | Declared band contains N | Source covers L to U% cocoa. | L to U% cocoa |
   | Declared band does not contain N | Source covers L to U% cocoa; you asked for N%. Estimate only. | L to U% cocoa · requested N% |
   | Estimate band, N = 100 | US unsweetened baking chocolate, used as a 100% cocoa estimate. It is not your bar; compare the label. | 100% cocoa estimate · baking chocolate |
   | Estimate band, N < 100 | US unsweetened baking chocolate, a 100% cocoa estimate; you asked for N%. Estimate only. | 100% cocoa estimate · requested N% |
   | Blend | No single cocoa band from this source; you asked for N%. | No single cocoa band |
   | No band | Cocoa percentage not stated by this source; you asked for N%. | Cocoa % not stated |

   When chocolate was implied (rule 5), every detail note starts "Searched as chocolate with N% cocoa.", and the Search screen shows that sentence once, as its own line above the results and inside the no-result state whatever else that state shows (`FoodSearchResultText.interpretationNote`, rendered by `GenericFoodSearchView`). Notes never change nutrients, identity or selection.

   Screen grouping (#391): the Search screen splits ranked rows into "Best matches" and "Other matches" by name words (#308). A row that this policy admits for a requested cocoa percentage (rule 3 eligibility: chocolate in the name, no unrequested milk, white or ruby, and a stated band or the approved estimate) also counts as a close match, so the screen keeps the order above; without this, "Baking chocolate, unsweetened, squares" fell to Other matches for "dark chocolate 100%". Grouping is presentation only (`CocoaPercentPolicy.isCocoaMatch`, used by `GenericFoodSearchViewModel.closeMatches`).

## Who is affected

- Typed search and list import use the composite, so both get the ordering and notes.
- CoFID re-resolution searches a stored product name with no percentage, so only the UK name equivalence can reach it. Re-resolving a "Chocolate, plain" or mint fondant record is unchanged apart from the specialisation preference.
- The personal-library exact-alias reuse route is unchanged: a saved alias still returns its saved record first.

## Online search terms

No destination is added and `docs/privacy-and-egress.md` needs no change, but the displayed terms submitted to existing routes change:

- Open Food Facts (when the online food database is enabled): "100% cacao" now sends "chocolate" with the descriptor "100% cocoa"; "85% cocoa chocolate" sends "chocolate 85% cocoa"; "per cent" queries now send their percentage (fat percentages also change the transport's percentage priority). These remain "the displayed terms of a submitted search", because the Search screen shows "Searched as chocolate with N% cocoa." whenever the food text was rewritten. The OFF transport's percentage pattern accepts "per cent" as well.
- OpenRouter web lookup (explicit, with the user's key) receives the same displayed food terms.

## Architecture gate

Gate run 3 November 2026 by `architecture-gate`: PASS WITH CHANGES, 14 findings, all applied in this version (truncation, regional order, eligibility exception, parser scope, visible rewrite note, dropping `filled`, identity-keyed estimate, notes ownership, online terms, every percentage pattern, version stamping, swiftc file list, band edge cases, affected callers).

Invariant review of the implementation, 3 November 2026: PASS WITH CHANGES, 7 findings, all applied: the implied-chocolate sentence is now rendered on the Search screen (it had existed only in an uncalled detail note, so Open Food Facts could have received "chocolate" without the user seeing it); the band reader ignores ingredient percentages; cocoa rules apply only to plain chocolate descriptions; an inverted band built outside the reader is no band rather than a trap; the implied-chocolate check folds width as the parser does; a stored v14 capture evidence round-trip test was added; and the Open Food Facts pattern was simplified.

- **Responsibilities.** Parsing stays in `FoodQueryParser`. Band reading, the estimate mapping, eligibility exceptions, tier ordering and note text live in one pure application type, `CocoaPercentPolicy`. CoFID and USDA call its eligibility and ordering; the composite calls its ordering; `FoodQueryCandidateAssessment` and `FoodSearchResultText` call its notes.
- **Dependency direction.** `CocoaPercentPolicy` depends only on `FoodLedgerDomain` value types and `ParsedFoodQuery`. Infrastructure adapters depend on it, never the reverse. No SwiftUI, HealthKit, GRDB, filesystem, network, clock or randomness. No new package target.
- **Invariants.** No nutrient value, provenance or identity changes; unknown stays unknown; ordering is a permutation (nothing filtered, nothing selected); the shared Confirm screen and single Log action are unchanged; the original query remains the evidence; no persisted type changes.
- **Versions on records.** Matcher, ranking and policy versions are stamped on new evidence and match metadata only. Stored records carrying `cofid-generic-ranking-v14`, `usda-generic-ranking-v15`, `composite-generic-ranking-v9` or `generic-representation-ranking-v8` still decode and re-encode unchanged. The CoFID matcher version is also the re-resolution target identifier, so a re-resolution proposal prepared before the upgrade and confirmed after it returns `unavailableTarget` and must be prepared again, as with every earlier CoFID matcher change. The parser version is not persisted.
- **Extension axis.** A future source (Ciqual 2025 in phase C) gains cocoa ordering by declaring bands in its names or descriptions, without changing the policy. The estimate list stays closed.

## Contract tests

1. Each source alone (CoFID, USDA) for "100% cacao", "dark chocolate 100%" and "90% dark chocolate" includes the target row inside its own 10-row cut and in first position where a tier-1 or tier-2 row exists.
2. Composite cocoa queries with a synthetic banded regional source: regional rows stay last unless promoted; `testTwoSourceRowsEqualRegionalRowsWithoutTaiwanWhenNotPromoted` gains the cocoa queries.
3. Ordering is a permutation: the same candidates before and after (nutrients, identity, provenance equal), nothing filtered, nothing selected; `expectedIdentity` follows the first match exactly as today; personal-library alias reuse for "100% cacao" is unchanged.
4. Parser cases: every row of the parser table below, all 592 FoodQueryEvaluation v9 cases unchanged.
5. Band reader: "45- 59%", en-dash range, point band, L > U, out-of-range bounds, parenthesised blend, CoFID description band, two bands in one text.
6. Estimate mapping: only release plus FDC 167568 gets the estimate; 167567 and 167999 get none; a guard fails if 167568's name changes.
7. Eligibility: "dark chocolate" admits 17-491 and no unbanded row lacking a query word; a synthetic "Chocolate, milk, 30% cocoa" row is not admitted for "dark chocolate 30%"; without `cocoa_percent` and with other food words, eligibility is unchanged; "salmon chocolate" stays empty.
8. Notes and cautions: one fixture per table row, including the estimate row for a request below 100, the blend row and the implies-chocolate note on every row and in the no-result state; no cocoa note without `cocoa_percent`; cautions asserted through `FoodSearchResultText.caution`.
9. Open Food Facts terms for "100% cacao", "85% cocoa chocolate" and "10 per cent fat yoghurt", and the transport's percentage priority for "per cent" input.
10. Version assertions updated (`LexicalPluralRetrievalTests`, `RegionalSourceOrderTests`); a stored v14 CoFID match metadata and capture evidence round-trip byte-identically.
11. FoodSearchQuality v3 to v6 metrics byte-identical, with r037 ("salmon chocolate"), r049 ("milk") and r050 ("200ml milk") asserted explicitly.

## Evaluation (expectations frozen before code)

Synthetic queries only. Both harnesses are exact-replay gates, so the expectations below are written into the fixtures before production code and the first run is kept.

- **FoodQueryEvaluation v10.** `build_v10.py` appends the parser cases to v9 and writes `synthetic-v10.json` and `manifest-v10.json` with the parser hash before the first run; the `validate.py` allowlist and the three CI lines move to v10. The gate requires every case exact, so the 592 v9 cases, including the three existing dark chocolate cases (nlp-226, nlp-351, nlp-492), must still pass.
- **FoodSearchQuality v7.** `build_retrieval_v7.py` appends r106 onwards to v6 with a cocoa grade rule; `RankedRetrievalDevelopmentTests` replays v7 and writes `WHR_RETRIEVAL_REPORT_V7`; CI gains a fifth `score_retrieval.py` block. `--verify-report` is full equality, so the v3 to v6 metrics files must stay byte-identical. If any earlier result moves, the phase stops and records each move before regenerating anything.

Parser cases (food, key attributes, route):

| Query | Food | Attributes | Route |
| --- | --- | --- | --- |
| 100% cacao | chocolate | cocoa_percent=100 | search (chocolate implied) |
| 85% cocoa | chocolate | cocoa_percent=85 | search (chocolate implied) |
| 85% cocoa chocolate | chocolate | cocoa_percent=85 | search |
| chocolate 85% cocoa solids | chocolate | cocoa_percent=85 | search |
| dark chocolate 70% cacao | dark chocolate | cocoa_percent=70 | search |
| dark 90% cocoa | dark chocolate | cocoa_percent=90 | search (chocolate implied) |
| dark chocolate 85 per cent | dark chocolate | cocoa_percent=85 | search |
| 85%cocoa / 85 % cacao / 100% CACAO | chocolate | cocoa_percent as written | search |
| 25g 99% dark chocolate | dark chocolate | cocoa_percent=99, 25 g | search |
| 10 per cent fat yoghurt | yoghurt | fat_percent=10 | search |
| 70-85 per cent dark chocolate | n/a | none | clarify, as "70-85% dark chocolate" does in v10 |
| 10 per cent less fat | n/a | n/a | relative_percentage reason recorded |
| dark chocolate 70% cocoa 85% cocoa | n/a | n/a | conflicting_variants reason recorded |
| 100% cocoa powder / 100% cacao paste / 100% cocoa mass / 70% cocoa beans / cacao nibs 100% / 100% cocoa butter / 85% cacao bar | as v10 | unspecified_percent | clarify, as v10 |
| 85% hot cocoa | as v10 | as v10 | as v10 |
| cocoa solids 90 | cocoa solids 90 | none | clarify (`unresolved_number`) |

Retrieval expectations (composite, first result):

| Query | First result | Note |
| --- | --- | --- |
| dark chocolate 70% | USDA 170273 (70 to 85%) | in band |
| dark chocolate 85% | USDA 170273 | in band |
| 90% dark chocolate | USDA 170273 | out of band |
| 99% dark chocolate | USDA 170273, then 167568 | out of band |
| dark chocolate 100% | USDA 167568 | 100% estimate |
| 100% cacao | USDA 167568 | 100% estimate, searched as chocolate |
| 85% cocoa chocolate | USDA 170273 | in band; no cocoa drink in the top 3 |
| chocolate 85% cocoa solids | USDA 170273 | in band |
| dark chocolate 85 per cent | USDA 170273 | in band |
| dark chocolate 40% | CoFID 17-491 (36 to 50%; 40 lies in no USDA band) | in band |
| dark chocolate 50% | CoFID 17-491 and USDA 170271 (both contain 50), existing order between them | in band |
| dark chocolate 30% | the nearest band (CoFID 17-491) | out of band |
| dark chocolate | a plain dark row (CoFID 17-491 or a USDA dark band), not 17-650 | none |
| mint dark chocolate | CoFID 17-650 | none |
| plain chocolate | CoFID 17-491 | none |
| salmon chocolate | no result (unchanged) | none |

## Results (3 November 2026)

- FoodQueryEvaluation v10: first run on parser v10 routed 614 of 625 cases correctly and got 388 of 404 search cases exact; parser v11 passes all 625 (all 592 v9 cases unchanged).
- FoodSearchQuality v3 to v6: byte-identical metrics; no earlier case's records change between the v9 and v10 replays.
- FoodSearchQuality v7, composite rows for the 16 new cases: hit@1 13 to 16, nDCG@5 sum 10.50 to 16.00, wrong band first 3 to 0. Wrong band within the top 5 rises from 19 to 43, because the other stated bands now follow the matching one as labelled alternatives. Labels are same-author development labels, not an independent holdout.

## Queries whose route or results change

- "per cent" queries for any percentage now parse; fat ones search with `fat_percent`, where v10 clarified on an unresolved number.
- "N% cocoa" and "N% cacao" with no other food word now search chocolate instead of clarifying.
- "dark chocolate" without a percentage now also lists CoFID "Chocolate, plain", and the mint fondant row moves down.
- Any name containing "fondant", "centres" or "centred" counts one unrequested specialisation when the user did not name it. No v3 to v6 result contains such a name (checked by the gate against the frozen v6 replay).

## Versions

`food-query-parser-v11`, `cocoa-percent-policy-v1`, `generic-representation-ranking-v9`, `composite-generic-ranking-v10`, `cofid-generic-ranking-v15`, `usda-generic-ranking-v16`. `food-query-interpretation` is not changed by this phase (#370 is changing it separately).
