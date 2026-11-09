# Dark chocolate (70% to 100% cocoa) nutrient sources: investigation and proposal

Status: investigation and plan, 3 November 2026. No product code, contract, egress or bundled data has changed.

Owner direction (3 November 2026): all three options are needed. They are planned below as three phases, A then B then C (see "Phase plan"), tracked in #381 with phase issues #382 (A), #383 (B) and #384 (C). Each phase still needs its own spec, architecture gate and, where marked, a versioned contract amendment before production code.

## Problem

The owner reports that searching for dark chocolate at 80%, 85%, 90% or 100% cocoa gives no useful nutrition. The goal is correct macros and micronutrients for these foods, within the closed rules: unknown is never zero, estimates are labelled, there is no automatic selection, and every save is an explicit user action bound to its evidence.

## Summary

- **This is mostly retrieval and parsing, with a coverage gap above 85%.** The bundled USDA SR Legacy projection already has a 70 to 85% row with full mineral coverage, and an unsweetened baking chocolate row that is effectively 100% cocoa mass. The app either does not reach them or does not tell them apart.
- **The cocoa percentage is parsed and then ignored offline.** `cocoa_percent` only feeds the Open Food Facts query text. Generic ranking does not use it, so the 70 to 85% row comes first at 70% and 85% by accident and the 45 to 59% row comes first at 90%, 99% and 100%, with no note that the band does not match.
- **CoFID has no row at 70% or above,** and for "dark chocolate" its only hit is After Eight style mint fondant chocolate. The UK name for dark chocolate in CoFID ("Chocolate, plain", 36 to 50% cocoa solids) is never reached by "dark chocolate".
- **Several common phrasings fail to parse:** "100% cacao" and "85% cacao" go to clarification, "85% cocoa chocolate" returns hot cocoa drinks, "dark chocolate 85 per cent" and "cocoa solids 90" end as an unresolved number.
- **Plan:** phase A uses only the bundled CoFID and USDA data, makes the cocoa percentage a ranking and disclosure signal, fixes the phrasing and the UK naming, and adds evaluation cases (no new source, no new egress). Phase B lets label macros and a labelled generic estimate for unprinted nutrients sit on one entry, which needs a new per-nutrient merge because none exists today. Phase C bundles Ciqual 2025 (Etalab 2.0, verified), which adds an analysed 70% row but nothing above 70%, so the 86% to 99% gap stays a disclosed nearest-band estimate.

## 1. Reproduction at code level

Method: a throwaway XCTest probe (not committed) ran `CoFIDGenericFoodSearch`, `USDAGenericFoodSearch` and a `CompositeGenericFoodSearch` built the way the app composes them ([FoodLedgerCompositionRoot.swift:132](../WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift#L132)), against the bundled resources at `origin/main` 099c875c. Synthetic query strings only. The probe lived in `Packages/FoodLedgerKit/Tests/FoodGenericSearchTests/` and was removed after the run.

### What the parser does

| Query | Route | Food text used for retrieval | Attributes | Reasons |
| --- | --- | --- | --- | --- |
| dark chocolate 85% | search | dark chocolate | `cocoa_percent=85` | none |
| 85% dark chocolate | search | dark chocolate | `cocoa_percent=85` | none |
| dark chocolate 85 percent | search | dark chocolate | `cocoa_percent=85` | none |
| dark chocolate 85 per cent | clarify | dark chocolate 85 per cent | none | `unresolved_number` |
| 85% cocoa chocolate | search | cocoa chocolate | `cocoa_percent=85` | none |
| chocolate 85% cocoa solids | search | chocolate cocoa solids | `cocoa_percent=85` | none |
| 100% cacao / 85% cacao | clarify | cacao | `unspecified_percent` | `percentage_meaning_unknown` |
| cocoa solids 90 | clarify | cocoa solids 90 | none | `unresolved_number` |
| 70-85% dark chocolate | clarify | 70 dark chocolate | none | `unresolved_number` |
| lindt 85% | clarify | lindt | `unspecified_percent=85` | `percentage_meaning_unknown` |

The percentage is not treated as an amount. It is captured by the percent pattern at [FoodQueryParser.swift:132](../Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift#L132) and becomes `cocoa_percent` only when the text contains the word "chocolate" ([FoodQueryParser.swift:140](../Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift#L140)). "Cocoa" and "cacao" on their own do not qualify, and the British "per cent" does not match the pattern, which then leaves a bare number for [FoodQueryParser.swift:238](../Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift#L238).

### What the searches return (composite order, first rows)

| Query | First results | Problem |
| --- | --- | --- |
| dark chocolate | USDA 45 to 59%, 60 to 69%, 70 to 85%, then CoFID mint fondant | CoFID "Chocolate, plain" absent |
| dark chocolate 70% or 85% | USDA 70 to 85% first | right row, for the wrong reason (below) |
| dark chocolate 90% / 99% | USDA 45 to 59% first | wrong band first, no disclosure |
| 100% cacao | USDA 45 to 59% first (after a clarify route) | 100% row (baking chocolate) not offered |
| 85% / 100% cocoa chocolate | hot cocoa drinks and cocoa mixes | wrong food |
| chocolate 85% cocoa solids | no result | "cocoa solids" kept as food words |
| plain chocolate | CoFID "Chocolate, plain" | correct, but only with the UK word |
| baking chocolate | USDA unsweetened baking chocolate | only reachable with "baking" |
| lindt excellence 85% dark chocolate | no result offline | expected: no branded data offline |

Why 70% and 85% happen to work: `GenericFoodRankingPolicy.preference` ([GenericFoodRankingPolicy.swift:44](../Packages/FoodLedgerKit/Sources/FoodLedgerApplication/GenericFoodRankingPolicy.swift#L44)) counts candidate tokens absent from the requested text (`additionalTerms`, line 68). The requested text "dark chocolate 85%" contains the token "85", which also appears in "70-85% cacao solids", so that row has one fewer extra term. This is lexical coincidence, not percentage matching, and it fails for every value that is not a band endpoint.

No disclosure when the band is wrong: `FoodQueryCandidateAssessment.variantNote` ([FoodQueryCandidateAssessment.swift:32](../Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryCandidateAssessment.swift#L32)) writes notes for `unspecified_percent` and `fat_percent` only. A 90% request shown the 45 to 59% row gets the generic USDA difference text ("attributes need review", [USDAGenericFoodSearch.swift:118](../Packages/FoodLedgerKit/Sources/FoodGenericSearch/USDAGenericFoodSearch.swift#L118)) and nothing about cocoa.

Only Open Food Facts uses the value, by adding "85% cocoa" to the submitted search terms ([OpenFoodFactsSearch.swift:96](../Packages/FoodLedgerKit/Sources/FoodGenericSearch/OpenFoodFactsSearch.swift#L96)), and only when the online food database is enabled.

### Bundled coverage

CoFID 2021 (`cofid-2021-generic-search-v1.json`, OGL v3) has no dark chocolate row at 70% or above. Relevant rows:

- 17-491 "Chocolate, plain", described as 6 bars, 3 brands, 36 to 50% cocoa solids. Fibre is `present_unquantified` and caffeine is `unmapped`, so both stay unknown, which is correct.
- 17-650 "Chocolate, dark, with crème or mint fondant centres" (After Eights and similar).
- 12-545 "Cocoa powder", 17-002 "Cocoa butter".

USDA (`usda-generic-v1.json`, SR Legacy 2018-04-01 and Foundation 2026-04-30, CC0) has, per 100 g:

| FDC ID | Name | Energy kcal | Fat g | Sat g | Carb g | Sugars g | Fibre g | Protein g | Fe mg | Mg mg | K mg | Zn mg | Cu mg | Mn mg | P mg | Caffeine mg |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 170272 | Chocolate, dark, 60-69% cacao solids | 579 | 38.3 | 22.0 | 52.4 | 36.7 | 8.0 | 6.12 | 6.32 | 176 | 567 | 2.65 | 1.25 | 1.32 | 260 | 86 |
| 170273 | Chocolate, dark, 70-85% cacao solids | 598 | 42.6 | 24.5 | 45.9 | 24.0 | 10.9 | 7.79 | 11.9 | 228 | 715 | 3.31 | 1.77 | 1.95 | 308 | 80 |
| 167568 | Baking chocolate, unsweetened, squares | 642 | 52.3 | 32.3 | 28.4 | 0.91 | 16.6 | 14.3 | 17.4 | 327 | 830 | 9.63 | 3.23 | 4.17 | 400 | 80 |

Of the 39 catalogue keys, 170273 carries 30; it has no biotin, chloride, chromium, folate, iodine, molybdenum, vitamin A, vitamin C or vitamin D, which stay unknown. 167568 carries 33. US carbohydrate is by difference and includes fibre; the existing USDA difference text already says so. Theobromine is in SR Legacy but not in the catalogue. There is no row between 86% and 99%.

### Evaluation fixtures

- FoodQueryEvaluation (CI: `python3 Tools/FoodQueryEvaluation/validate.py v9`, [ios-ci.yml:441](../.github/workflows/ios-ci.yml#L441)) checks only parsing: "25g 90 percent dark chocolate", "12g 85% dark chocolate" and "8g 70 percent dark chocolate" expect `cocoa_percent` ([synthetic-v9.json:4844](../Tools/FoodQueryEvaluation/synthetic-v9.json#L4844), [7522](../Tools/FoodQueryEvaluation/synthetic-v9.json#L7522), [10321](../Tools/FoodQueryEvaluation/synthetic-v9.json#L10321); origin [build_v3.py:26](../Tools/FoodQueryEvaluation/build_v3.py#L26)).
- FoodSearchQuality retrieval scenarios v3 to v6 ([ios-ci.yml:117](../.github/workflows/ios-ci.yml#L117)) contain no dark chocolate, cacao or plain chocolate case, so nothing guards the ranking above.

Diagnosis: **coverage** (no UK row at 70% or above, no row of any kind at 86% to 99%), **retrieval** (UK naming, cocoa percentage unused, wrong band silently first, mint fondant row for plain "dark chocolate") and **parsing** (cacao, cocoa solids, per cent).

## 2. Candidate data sources

Checked on 3 November 2026 unless stated. Licence readings are repository conclusions, not legal advice.

| Source | Cocoa coverage observed | Nutrients relevant here | Measured or calculated | Licence | Cadence | Egress |
| --- | --- | --- | --- | --- | --- | --- |
| [CoFID 2021](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid) (bundled) | Plain chocolate 36 to 50% only; cocoa powder; cocoa butter | Full mineral set for plain chocolate; fibre unquantified | Analysed samples (6 bars, 3 brands) per the row description | OGL v3 | Static since 2021 | None (bundled) |
| [USDA FDC SR Legacy](https://fdc.nal.usda.gov/download-datasets/) (bundled) | 45 to 59%, 60 to 69%, 70 to 85%, NFS blend, unsweetened baking chocolate | 30 to 33 of 39 keys, including fibre, Fe, Mg, K, Zn, Cu, Mn, P, caffeine, sugars, saturates | Per-value derivation codes exist in SR; not rechecked per value today | CC0 ([API guide](https://fdc.nal.usda.gov/api-guide/)) | Final release April 2018, never updated | None (bundled) |
| USDA Foundation Foods (October 2026 release listed) | API search for "dark chocolate 85% cacao" returned no chocolate rows | n/a | Analytical | CC0 | About twice yearly | None if bundled |
| USDA FNDDS 2021 to 2023 | "Dark chocolate candy" (2710336), a blended generic (46.1 g sugars) | Broad, includes theobromine | Calculated from SR links | CC0 | Every two years | None if bundled |
| USDA Branded Foods (October 2026) | 52,835 search hits for the query, for example 2106228 "85% CACAO DARK CHOCOLATE" | US label set: energy, fat, saturates, carbohydrate, sugars, fibre, protein, sodium, Ca, Fe, K, vitamin D | Label declarations, US products | CC0 | Monthly online, twice-yearly downloads | Runtime API (`api.nal.usda.gov`) is **not** in the egress list; bundling 195 MB is impractical |
| [Ciqual 2025](https://entrepot.recherche.data.gouv.fr/dataset.xhtml?persistentId=doi%3A10.57745%2FRDMHWY) (ANSES) | Released 19 Nov 2025, 3,484 foods, 74 constituents. Dark chocolate rows: 31085 more than 40% for cooking, 31005 about 50%, **31074 about 70% (tasting bar)**, 31030 no added sugars with sweeteners, plus filled and fruit variants. Nothing above 70% | 31074 per 100 g: 591 kcal, fat 46.3 g, saturates 28.7 g, carbohydrate 26.9 g, sugars 17.9 g, fibre 12.8 g, Fe 11, Mg 200, K 750, Zn 3, Cu 1.6, Mn 1.7, P 280, Ca 62 mg; selenium "< 20" µg | Confidence code A (highest) on every listed nutrient of 31074 except energy (D, calculated from the regulation factors). Values include "< n" bounds, "traces" and "-" (missing) | Etalab Open Licence 2.0 on the Recherche Data Gouv record; ANSES asks for attribution; the record's own citation is French, and the app uses its detailed French form with the DOI (decision D2 in [ciqual-2025-admission-v1.md](ciqual-2025-admission-v1.md); the English wording first noted here is not on the record) | 2020, then 2025; no stated cadence | None at runtime if bundled; build-time download from recherche.data.gouv.fr; a source admission contract is needed |
| [Matvaretabellen](https://www.matvaretabellen.no/en/chocolate-dark-70-cocoa/) (Norway) | "Chocolate, dark, 70 % cocoa" (09.133) | Fibre 11.0 g, Fe 9.4, Mg 170, K 560, Zn 2.6, Cu 1.37, P 230 per 100 g; manganese not shown | Mostly analysed (Swedish Livsmedelsverket 2022 analysis); some fatty acids and carbohydrate calculated | **Not stated on the page**; not established | Not stated | None if bundled; licence must be established first |
| Frida 5.5 (DTU, 2025; [FAO listing](https://www.fao.org/food-composition/tables-and-databases/detail/(denmark--2024)-danish-food-composition-table/en)) | Not verified (site is script-rendered; the DTU data repository returned 403) | Not verified | Not verified | FAO lists "Free access"; no licence confirmed | Periodic | None if bundled; licence unconfirmed |
| EuroFIR FoodEXplorer | Aggregates national tables | n/a | n/a | Membership and licence terms; not rechecked today | n/a | Excluded as for other commercial sources |
| Open Food Facts | Many 85% to 100% products, label values entered by contributors | Usually label macros only; quality varies (the Lindt Excellence 85% entry shows fibre 0 g, which is implausible for 85% cocoa) | Community-entered labels | ODbL, DbCL, CC BY-SA images (see [source evaluation](food-source-coverage-and-licence-evaluation.md)) | Continuous | **Already allowed** when the online food database is enabled |
| Manufacturer pages, for example [Montezuma's Absolute Black 100%](https://montezumas.co.uk/100-cocoa-chocolate-bar-absolute-black.html) | Exact products | Mandatory UK macros plus fibre; no minerals. Montezuma's page today: 623 kcal, fat 53 g, saturates 32 g, carbohydrate 18 g, sugars 0.6 g, fibre 11 g, protein 14 g, salt 0.01 g; retailer copies still show an older 601 kcal and 17 g fibre panel | Label declarations | Page copyright; facts read during a reviewed web lookup | Changes with reformulation | **Already allowed** only as "a chosen public source page" during an explicit web lookup, with OpenRouter |

Not checked from a primary source today: Lindt UK, Green & Black's and Hotel Chocolat pages (search results returned only retailers and aggregators, whose values disagree, for example Lindt 99% between 559 and 599 kcal). Treat them as unknown until read from the manufacturer page or pack.

Takeaways: at 70% or above, USDA (70 to 85% and 100%) and Ciqual 2025 (70%) give full minerals under open licences, and nothing reviewed covers 86% to 99% as a generic row. The European tables checked stop at about 70%. Ciqual 31074 and USDA 170273 broadly agree on minerals (for example magnesium 200 and 228 mg, iron 11 and 11.9 mg) but differ on sugars (17.9 and 24.0 g) and carbohydrate (26.9 and 45.9 g, partly because USDA carbohydrate is by difference and includes fibre), which is why the source and band must be visible on the candidate.

Ciqual 2025 files checked: the five XML files on the Recherche Data Gouv record (file IDs 666252 foods, 666246 constituents, 666249 composition), MD5 checksums matching the published values. ciqual.anses.fr itself returned HTTP 503 with no Retry-After on every attempt on 3 November 2026. A 100% bar is cocoa mass, which is the same ingredient as unsweetened baking chocolate, but its presentation as "Baking chocolate" is a US product and the 100% label values above (fibre 11 g) differ from the USDA row (16.6 g), so it must be shown as an estimate, never as the product.

## 3. Label reality and how the rules apply

UK labels give the mandatory declaration (energy, fat, saturates, carbohydrate, sugars, protein, salt) and often fibre. Minerals, caffeine and vitamins are almost never printed. So for a branded bar:

- **Label values are `measured`** for exactly the nutrients printed, and only those ([food-identity-nutrition-contract.md](food-identity-nutrition-contract.md) section 8: a physical panel value "cannot make unprinted nutrients measured").
- **Unprinted nutrients stay `unknown`** unless the user explicitly accepts a compatible generic row, in which case they are `augmented` with release and record provenance (precedence step 4). They are never zero.
- **Compatibility needs a cocoa rule.** Today cocoa percentage is not a decisive identity attribute, so nothing stops a 45 to 59% row lending its minerals to an 85% bar, and nothing says it is a different band. Proposal: a generic row is compatible with a requested or labelled cocoa percentage only when its declared band contains that value (70 to 85% row for 70% to 85%; unsweetened baking chocolate for 100%). Outside a band the row may still be offered as a tentative alternative with a visible note, never as compatible.
- **No interpolation.** Estimating 90% by blending the 70 to 85% and 100% rows would be a new reconstruction method that invents values; it is out of scope without a separate recipe-reconstruction contract.
- **No automatic selection or save.** Every route above ends on the shared Confirm screen with one Log action; the user chooses the row and the amount.
- **Disclosure where it matters.** The band mismatch note sits on the candidate, as the `fat_percent` note does; provider stages and record IDs stay behind details.

## 4. Options, ranked

### A. Use the bundled data properly (recommended first)

Scope:

1. Parser: route "cocoa", "cacao" and "cocoa solids" percentages to `cocoa_percent` (not only when "chocolate" is present), accept "per cent", and strip "cocoa solids" / "cacao" from the retrieval text so "85% cocoa chocolate" retrieves dark chocolate, not hot cocoa. Hot cocoa, cocoa powder and cocoa butter queries without a percentage must keep their current results.
2. Ranking: read the cocoa band from the source name (the USDA names include an irregular "45- 59%"), rank the row whose band contains the requested value first, and treat a 100% request as matching unsweetened baking chocolate. When no band contains the value (86% to 99%), keep the nearest higher band first and add a note.
3. Disclosure: extend `FoodQueryCandidateAssessment.variantNote` with a cocoa note, for example "Source covers 70 to 85% cocoa; you asked for 90%. Estimate only." and "US unsweetened baking chocolate, used as a 100% cocoa estimate."
4. UK naming: let "dark chocolate" reach CoFID "Chocolate, plain" (with its 36 to 50% band visible), and stop the mint fondant row leading a plain "dark chocolate" query while keeping it for "mint dark chocolate".

Trade-offs: no licence or egress change and small effort; macros and minerals are good for 70% to 85% and reasonable for 100%; 86% to 99% remains an honest nearest-band estimate. Branded bars still need the label route for macros.

Needs: versioned contract updates (parser v11, generic ranking v8 or a new lexical terms version, CoFID and USDA matcher versions) under the usual phase process; an owner decision on whether the US baking chocolate row may be offered for 100% requests.

### B. Label macros plus labelled generic micronutrients

Scope: after the user records a bar from its label (pasted label, label photo, Open Food Facts, or a reviewed manufacturer page), offer one explicit "Add estimated minerals from …" choice using the band-compatible generic row from option A. Printed nutrients stay `measured` from the label; unprinted ones become `augmented` from the chosen row; anything neither source has stays unknown.

Trade-offs: the most accurate result for real bars (exact macros, sensible minerals) and no new egress, but it is a cross-source per-nutrient merge in the confirmation flow. Medium to large effort.

What exists today (checked 3 November 2026): the domain already keeps provenance per nutrient entry (`NutrientEntry` with its own `NutrientProvenance`), so a mixed-source nutrient set is representable. The Confirm flow does not build one: each confirmation saves one selected candidate's nutrient set. The nearest feature, re-resolution ([FoodReresolution.swift](../Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodReresolution.swift), CoFID only), replaces the whole resolution with one candidate's nutrients and shows a before and after diff; it does not merge. So B needs a new application-layer merge that applies the contract's section 8 precedence, plus a Confirm interaction.

Design sketch for the phase spec: the label candidate stays the selected candidate; an "Estimate unprinted nutrients" action lists only band-compatible generic rows (from A, and from C once admitted); choosing one shows which nutrients would be filled, from which source and release, before Log; printed nutrients are never overwritten, and a printed value that conflicts with nothing is not touched; the saved record cites both evidence sets. A pure merge policy in the application layer, contract-tested, keeps presentation thin.

Needs: owner approval and a contract amendment for the cocoa compatibility rule as a decisive attribute and for the label plus estimate interaction; a record-format check that saved records decode and re-encode unchanged; journey QA on the Confirm screen.

### C. Admit an additional bundled composition source

Scope: admit Ciqual 2025 (Etalab Open Licence 2.0, verified on the Recherche Data Gouv record) as a further bundled generic source. Matvaretabellen and Frida stay out until their licences are established.

What it adds: an analysed European 70% bar (31074, confidence A), a 50% bar, a cooking chocolate row and a no-added-sugar row, each with a full mineral set. It adds nothing above 70%, so for 85% to 100% A's USDA rows remain the generic estimate.

Trade-offs: a second, well-documented view at 50% and 70%, closer to European formulations than SR Legacy; Ciqual's "< n" and "traces" values map to `bounded` rather than exact values, and "-" to unknown, which needs a projection rule; build-time download, frozen bytes, hashes and an attribution manifest, but no runtime egress. It is a whole-source admission, so it affects many other foods too; ordering against CoFID and USDA must be decided, as Taiwan's was in `composite-regional-order-v9`.

Scoping choice for the owner: admit the whole table (larger review, wider benefit) or only the chocolate and cocoa group first (smaller, quicker, but a partial corpus needs its own admission rule).

Needs: source admission contract (licence, attribution, release pinning, constituent mapping to the 39 keys, bound and trace handling), composite ordering decision, owner approval.

### Not recommended

- Runtime USDA FDC Branded API: a new egress destination (`api.nal.usda.gov`) for US products; it needs a contract, a policy update and explicit owner approval, and gives US label data rather than UK.
- Interpolating between cocoa bands: invents values.

## 5. Tests and evaluation cases (synthetic only)

FoodQueryEvaluation (new synthetic version, expectations written before code):

- "100% cacao", "85% cacao", "90% cocoa dark chocolate", "dark chocolate 85 per cent", "cocoa solids 90", "chocolate 85% cocoa solids", "25g 99% dark chocolate" expect food "dark chocolate" and the right `cocoa_percent`.
- Guards: "hot cocoa", "cocoa powder", "2 tbsp cocoa powder", "cocoa butter", "70-85% dark chocolate" (stays ambiguous), "10% fat yoghurt" (stays `fat_percent`), "100% peanut butter" (stays `ingredient_percent`).

FoodSearchQuality (a new retrieval scenarios file, frozen labels, scored in CI):

- 70% and 85% expect FDC 170273 first; 90% and 99% expect 170273 first with the band note; 100% expects 167568 first with the estimate note.
- "dark chocolate" expects a plain dark row first, not 17-650; "plain chocolate" keeps 17-491; "mint dark chocolate" keeps 17-650.
- "85% cocoa chocolate" must not return a cocoa drink first.

Pure tests (FoodLedgerKit):

- Cocoa band parsing from names, including "45- 59%" and the NFS blend name (which must not be read as a 90% band).
- Band containment and the 100% mapping; no band means a note, never a silent best match.
- Note text for in-band, out-of-band and 100% cases.
- Unknown stays unknown: CoFID fibre `present_unquantified` and USDA missing keys never become zero.
- No candidate is selected or saved without the explicit action (existing confirmation tests extended).
- Option B only: printed values stay `measured`, unprinted values take `augmented` provenance from the chosen row, and decode and re-encode of saved records is unchanged.
- Option C only: corpus hash and manifest pinning; constituent mapping to the 39 keys; "< 20" projects to a bound, "traces" to a bound with origin recorded, "-" to unknown, never zero; French decimal commas parse; 70% requests rank Ciqual 31074 and USDA 170273 by the agreed order; retrieval evals for existing non-chocolate foods do not regress.

## 6. Phase plan (owner direction: A, B and C)

| Phase | Depends on | Contracts | Main gates | Owner decisions before code |
| --- | --- | --- | --- | --- |
| A. Cocoa-aware search on bundled data | none | parser v11, generic ranking and lexical terms version, CoFID and USDA matcher versions, candidate note text | FoodQueryEvaluation and FoodSearchQuality new versions, package tests, analyze, app tests | none (decisions 1 and 2 settled) |
| B. Label macros plus labelled estimates | A (band compatibility and notes) | cocoa band as a decisive compatibility attribute; per-nutrient merge in confirmation; record compatibility | merge policy contract tests, archive round trip, journey QA on Confirm, invariant review | decision 3 |
| C. Ciqual 2025 admission | A for the cocoa band rule; independent of B | source admission contract, composite ordering, bound and trace projection | corpus hash and manifest tests, boundary script, retrieval evals across non-chocolate foods, invariant review | decisions 4 and 5 |

B and C can run in parallel after A because they touch different layers (confirmation merge versus a new generic source adapter), but both rely on A's band rule, so A lands first. B gains from C (more compatible rows) without needing it.

Each phase follows the usual delivery rules: one issue and branch, a phase spec with the architecture gate, evaluation expectations frozen before code, and a ledger row.

## 7. Owner decisions needed

Decided on 3 November 2026:

- A, B and C are all in scope.
- For 100% cocoa requests, phase A offers USDA FDC 167568 "Baking chocolate, unsweetened, squares" as a labelled estimate, with a visible note that it is a US unsweetened baking chocolate used as a 100% cocoa estimate, not the user's bar. It is never selected or saved automatically, and its missing keys stay unknown.
- For 86% to 99% cocoa requests, phase A ranks the nearest covering band (USDA 170273, 70 to 85%) first with a visible note, for example "Source covers 70 to 85% cocoa; you asked for 90%. Estimate only." The note sits on the candidate where the choice is made. Nothing is interpolated, selected or saved automatically.

Still open, in the order they block work:

1. ~~May the USDA unsweetened baking chocolate row be offered as a labelled estimate for 100% cocoa requests?~~ Decided: yes (see above).
2. ~~For 86% to 99%, is "nearest band (70 to 85%) with a visible note" acceptable, or should those requests show no generic row and point the user to the label route?~~ Decided: nearest band with a note (see above).
3. B: approve cocoa percentage as a decisive compatibility attribute for generic estimates, and the label plus estimate interaction on Confirm (contract amendment).
4. C: admit the whole Ciqual 2025 table, or the chocolate and cocoa group first?
5. C: where Ciqual sits in the composite order relative to CoFID (UK first) and USDA.

No option needs a new runtime network destination. If one is ever proposed (for example the USDA Branded API), it needs a contract, a policy update and explicit owner approval.

## Sources checked (3 November 2026)

- GOV.UK CoFID publication: https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid (as recorded in the bundled manifest; not re-fetched)
- USDA FoodData Central downloads: https://fdc.nal.usda.gov/download-datasets/
- USDA FoodData Central API search and food endpoints (DEMO_KEY, read-only research calls): https://api.nal.usda.gov/fdc/v1/foods/search and /food/2106228, /food/2710336
- ANSES, new Ciqual version (19 November 2025): https://www.anses.fr/en/content/new-enhanced-and-more-representative-version-ciqual-table
- Ciqual 2020 on data.gouv.fr: https://www.data.gouv.fr/fr/datasets/table-de-composition-nutritionnelle-des-aliments-ciqual-2020/ (ciqual.anses.fr itself returned HTTP 503)
- Ciqual 2025 on Recherche Data Gouv (doi:10.57745/RDMHWY), metadata via the Dataverse API and XML files 666252, 666246, 666249: https://entrepot.recherche.data.gouv.fr/dataset.xhtml?persistentId=doi%3A10.57745%2FRDMHWY
- Matvaretabellen, Chocolate, dark, 70 % cocoa: https://www.matvaretabellen.no/en/chocolate-dark-70-cocoa/
- FAO listing for Frida 5.5: https://www.fao.org/food-composition/tables-and-databases/detail/(denmark--2024)-danish-food-composition-table/en
- Montezuma's Absolute Black 100%: https://montezumas.co.uk/100-cocoa-chocolate-bar-absolute-black.html
- Open Food Facts, Lindt Excellence 85%: https://world.openfoodfacts.org/product/3046920022606
