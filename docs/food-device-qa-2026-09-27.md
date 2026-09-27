# Food-flow device QA — 27 September 2026

Direct UI observations through iPhone Mirroring, approximately 16:09–16:20 Europe/London. Existing installed TestFlight app, expected 0.1.1 (10) from the release session; installed version was not independently checked in this run. The local confirmation UX prototype was not installed. No provider calls, uploads, source changes or HealthKit writes. This is exploratory device QA, not a frozen independent retrieval-acceptance benchmark.

## Findings

1. **P1 — Generic-food confirmation cannot save with unknown identity metadata.** Rice, milk, yoghurt and whole egg candidates show unknown bone/skin/drained/packing/fortification fields as material differences. Milk/yoghurt also show unknown preparation. Ordinary acceptance is disabled. Prior rice reproduction: a written explanation enables Save, then Save fails with “Resolve every highlighted identity difference before saving.” No assertion should manufacture missing catalogue metadata. The visible error does not name the required fields. Collapsing details alone does not repair this contract.
2. **P1 — Stale results remain selectable after query edits.** Search `100g rice`; replace text with `200ml milk` without pressing Search. Rice results remain displayed and selectable. Selecting the first opens rice confirmation with 100 g from the previous retrieval. The prior snapshot is retained, but the UI does not indicate it belongs to the old query or prevent selection. Stale hints and no-result/clarification messages also persist while the text changes.
3. **P2 — Whole egg ranking.** `2 eggs` returns “Eggs, chicken, white, boiled” first; “Egg, whole, raw, fresh” second. Plain whole eggs should not be outranked by egg whites for this unqualified query under the generic presentation policy. Preserve explicit egg-white queries.
4. **P2 — Overloaded confirmation.** Long source hashes/record IDs, all nutrient fields and the complete correction form precede Save. Technical labels include “Conversion method/version”, “Material match differences” and “immutable version”. Generic candidates force a written justification. Save appears available before its identity requirements are satisfied.

## Search and handoff checks

| Query | Observed result | Scope of outcome |
|---|---|---|
| `200ml milk` | Whole pasteurised average first; whole UHT second; whole buttermilk third. First selection shows 200 mL. | Quantity handoff observed; per-100-g source explicitly warns that no density is inferred. Acceptance remains blocked by unknown details. |
| `0.25kg rice` | White long-grain raw enriched first; cooked enriched second. Second selection shows 250 g. | Non-first selection and kg conversion observed. Amount can be edited to 180 g. No save. |
| `200g Greek yoghurt 10% fat` | Plain whole-milk Greek yoghurt first; 4.39 g fat per 100 g explicitly labelled alternative to requested 10%. Another 5.0 g alternative follows. | 200 g observed in confirmation. Exact 10% match not claimed. Unknown details remain. |
| `2 eggs` | Egg whites boiled first; whole raw egg second. | Second selection shows 2 count and requires an explicit edible conversion/method. No weight invented; no save. |
| `Greek youghurt` | Plain whole-milk Greek yoghurt results. | Exact misspelled query verified; keyboard correction dismissed. Relevant retrieval observed. |
| `clementines` | Clementines, raw. | Plural retrieval observed. |
| `cooked ribeye` | Cooked/grilled beef ribeye records first and second. | Preparation preserved in visible results; not an exhaustive all-results check. |
| `bowl of rice` | Clarification asks for measurable amount or defined serving; input retained. | No results selected or saved. |
| `<100g rice` | Clarification asks for actual consumed amount; bounds cannot prefill an exact amount. | No results selected or saved. |
| `dragonfruit` | No compatible generic food found. | Honest visible catalogue miss; no nutrient invention or fallback. This observation does not prove exhaustive catalogue absence under every synonym. |
| `100g rice` then edit to `200ml milk` | Old rice result opens confirmation with 100 g. | Stale-selection defect reproduced. |

Mirroring intermittently ignored inputs or reordered rapid typing. Queries were verified visually before search; incorrect input attempts were discarded. Screenshots were observed inline rather than exported into this document. The earlier brown-rice reproduction displayed 100 g, but its original quantity entry was not observed, so it is not evidence of parsed handoff for that earlier query.

## End state and next work

Returned to Food Log for 27 September 2026: **0 entries**, matching the initial empty log. No QA food was saved and no food identity was corrected. Fix the generic confirmation contract and invalidate stale selectable results first; add egg/egg-white ranking scenarios before tuning. Keep unknown facts unknown and preserve whole-record nutrition provenance. Recheck these device flows after an explicitly authorised later release; this run does not validate the local UX prototype.

## Software repair and later device retest

Issue #161 uses the versioned [confirmation v2 contract](food-confirmation-contract-v2.md).
The exploratory observations above are preserved as originally recorded. The
repair has not been installed or checked on the returned phone. No new TestFlight
upload or iPhone Mirroring access is authorised by this change.

After a separately approved release, verify the installed version, then:

- Search 100 g rice; edit to 200 mL milk without searching. Old results and hints
  must disappear and no rice candidate can be selected. Repeat with a filter edit.
- Explicitly accept and save rice and yoghurt estimates without filling unknown
  bone/skin/packing fields. Reopen and verify the amount and unknown fields.
- Save 200 mL milk while preserving the warning and unavailable mass-based totals.
- Search `2 eggs`: choose a whole egg. Count alone must not save; supply a measured
  total edible weight excluding shell and method, then save/reopen. There is no
  evidenced small/medium/large guide enabled; no egg weights may be guessed.
- Search `egg white`, `egg whites`, `Greek yoghurt`, `Greek-style yoghurt` and
  `200g Greek yoghurt 10% fat`. Keep source wording and tentative type/fat notes.
- Recheck spelling, plurals, cooked ribeye, bowl/bounded-amount clarification and
  dragonfruit no-result recovery. Verify large text and VoiceOver through expanded
  source/correction details, Save, retry and leave-without-saving.

Use temporary test entries with explicit user permission. Simulator and package
evidence prove software contracts, not physical-device usability or nutrition truth.
