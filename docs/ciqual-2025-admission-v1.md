# Ciqual 2025 admission, v1 (#384, phase C of #381)

Status: architecture gate PASS WITH CHANGES (4 November 2026); all findings applied below. No production code before this spec merges.

Plan: [`dark-chocolate-nutrient-sources-investigation.md`](dark-chocolate-nutrient-sources-investigation.md), section 4C. Phase A: [`cocoa-aware-search-v1.md`](cocoa-aware-search-v1.md). Phase B: [`label-estimate-merge-v1.md`](label-estimate-merge-v1.md). Previous bundled-source admission: [`taiwan-food-catalogue-v1.md`](taiwan-food-catalogue-v1.md) and [`composite-regional-order-v9.md`](composite-regional-order-v9.md).

Every figure below was read from the downloaded Ciqual 2025 files on 4 November 2026 (snapshot: files dated 2025-11-03, dataset version 1.0 released 2025-11-19), unless another date or source is given.

## Problem

The bundled CoFID 2021 and USDA SR Legacy corpora have no European dark chocolate row at 70%. ANSES's Ciqual 2025 table has an analysed 70% bar (31074) with a full mineral set, plus 50%, cooking and no-added-sugar dark chocolate rows, under an open licence. Phase C admits Ciqual as a further bundled generic composition source, so these rows are offered in search and, through phase B's compatibility rule, as estimates for a labelled bar's unprinted nutrients. Ciqual adds nothing above 70%: for 86% to 99% and 100% the phase A USDA estimates remain.

## Owner decisions (4 November 2026, recorded on #384)

4. **Admit the chocolate and cocoa group first.** Phase C v1 admits only Ciqual's chocolate group, including 31074, 31005, 31085 and 31030. Everything else in the table stays out. The admission contract (licence and attribution, pinned files and hashes, constituent mapping, "< n" and "traces" handling, "-" as unknown) is written for the whole source, so admitting a further group later is a separate, reviewable change.
5. **Ciqual rows follow every UK and US row.** Ciqual joins the composite after CoFID and USDA, ordered after them by source as Taiwan's TFDA is today (`composite-regional-order-v9`). There is no promotion in v1, because the app has no French market setting. The existing tiers still apply (preparation-verified rows first, requested-fat matches, cocoa band fit). UK and US results do not change. The order is presentation only: `label-estimate-compatibility-v1` checks each bundled row on its own, so Ciqual rows are offered as estimates whatever their position.

The further decisions taken for this spec (D1 to D10) are in "Decisions record" at the end.

## 1. Source admission

### 1.1 Release identity and pinning

Recherche Data Gouv dataset doi:[10.57745/RDMHWY](https://doi.org/10.57745/RDMHWY), "Table de composition nutritionnelle des aliments Ciqual 2025", version 1.0, state RELEASED, release time 2025-11-19T16:29:04Z, producer Anses. The record lists eight files; the projector reads four XML files and pins a fifth for completeness:

| File ID | File | Bytes | MD5 (published = downloaded) | SHA-256 | Used |
| --- | --- | --- | --- | --- | --- |
| 666252 | `alim_2025_11_03.xml` (foods) | 1,581,031 | `8e1171d63cee4b6010cfce25dd29243d` | `e0b1de25b3039028205e9d54a96892e403e1b313c2efeb41180fabe132627478` | yes |
| 666250 | `alim_grp_2025_11_03.xml` (groups) | 80,421 | `c31aeea90349c3aab86f98ef5f4f10da` | `e216928be1001aed15ba1b120405b70a98145da2a1a76026d6e33542bd5e39dc` | yes |
| 666246 | `const_2025_11_03.xml` (constituents) | 17,955 | `d8f2f25fdacb887bc993a6eeaf80f203` | `3a231ea3e9836e4ac0b6ff94511e010210b2523d1b8b486c6b29e211066ba3f3` | yes |
| 666249 | `compo_2025_11_03.xml` (composition) | 69,243,149 | `2da725585946434df320d8041631998b` | `8c46a9032ece4eab4ffccc9dfcb0c490ec2f416aa664cc1ee013b241c6bdd4af` | yes |
| 666248 | `sources_2025_11_03.xml` (bibliographic sources) | 871,783 | `5469598d6b4811672b65e1644dfc6485` | `73e6a0c573f88c23f23b4670a016c616edea806b3d92340942cdbdb9b4323137` | pinned, not projected |

All five MD5 values match the values published in the dataset metadata. The PDF documentation (666748) and the two spreadsheets (666245, 666260) are not inputs to the corpus; C1 reads the PDF only to settle ambiguities A3 and A7.

- The files are UTF-8 with a byte order mark, elements carry leading and trailing spaces, and an absent value is written as an empty element with a `missing=" "` attribute. The projector strips the mark and the spaces and treats `missing` as absent.
- **Source manifest.** The projector writes a canonical JSON source manifest (DOI, dataset version, release time, and for each of the five files its ID, name, size, MD5 and SHA-256, sorted by file ID). Any changed byte in any file fails the build.
- **Hash terms, used throughout this spec.** The *source manifest SHA-256* is the SHA-256 of that manifest. The *corpus SHA-256* is the SHA-256 of the bundled corpus file. The `SourceRelease` fields are `artifactHash` = source manifest SHA-256, `manifestHash` = corpus SHA-256 (as CoFID and USDA set it) and `releasedAt` = 2025-11-19T00:00:00Z.
- **Identifiers.** `sourceID` is `ciqual`. The source release ID is `ciqual:2025-11-19:sha256:<source manifest SHA-256>`. The app's `sourceReleaseID` is `<source release ID>:projection:<corpus SHA-256>`, as USDA does, so a corrected projection coexists with older saves. The record ID is `<source release ID>:alim:<alim_code>`, for example `…:alim:31074`; `alim_code` is unique in the foods file (3,484 codes).
- **Corpus.** `Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources/ciqual-2025-generic-v1.json`, schema `ciqual-generic-v1`, projection `ciqual-projection-v1`, group scope `ciqual-group-scope-v1`. The searcher checks the corpus SHA-256 at load (`CiqualGenericFoodSearch.corpusSHA256`) and refuses a mismatch, as CoFID, USDA and TFDA do. The expected corpus SHA-256 is recorded in the C1 PR.

### 1.2 Licence and attribution

- **Licence:** "etalab 2.0" on the record (SPDX `etalab-2.0`, https://spdx.org/licenses/etalab-2.0.html), that is Etalab Open Licence 2.0. Repository reading, not legal advice. `SourceRelease.licence`: `Etalab Open Licence 2.0 · https://www.etalab.gouv.fr/licence-ouverte-open-licence/`.
- **Attribution (decided, D2).** The record's notes (in French) say the data may be reproduced only with an explicit reference to the source, in the short form "Anses. 2025. Table de composition nutritionnelle des aliments Ciqual" or a detailed form with "Ciqual 2025" and the DOI URL. The app uses the detailed French form with the DOI. The English wording in the investigation ("Anses. 2025. Ciqual French food composition table") is not on the record and is not used. `SourceRelease.attribution`: `Anses. 2025. Table de composition nutritionnelle des aliments Ciqual 2025. https://doi.org/10.57745/RDMHWY. Reviewed projection of the chocolate group; English names as published by Anses; no Anses endorsement.`
- **Where it is shown:** the Confirm source details (which already show `attribution` and `licence` for the selected release, `FoodConfirmationView`), Developer tools (release, record, both hashes, attribution, licence), and the saved record's `SourceRelease`, which travels with the food daily export through `source_release_id`. The search row and Confirm source line show only the family label (section 7).

### 1.3 Network use

The only network use is a developer downloading the five files by hand before running the projector, from `entrepot.recherche.data.gouv.fr` (Dataverse API `api/access/datafile/<id>`). The projector, its tests and the app make no network call: the projector reads local paths and verifies hashes, as `project_tfda.py` and `project_usda.py` do with local ZIPs. The app reads only the bundled corpus. `ciqual.anses.fr` is not needed (it returned HTTP 503 on 3 November 2026 and was not contacted on 4 November).

**Egress (decided, D1; approved and applied).** The owner approved on 4 November 2026, recorded on #384, that this developer download is not app egress, and the clarifying sentence below is now in [`privacy-and-egress.md`](privacy-and-egress.md) (CoFID, USDA and TFDA downloads follow the same pattern):

> Source datasets bundled with the app (CoFID 2021, USDA FoodData Central, TFDA and Ciqual 2025) are downloaded by a developer, outside the app, before the projection is built. That download carries no user data and is not app egress; the app reads only the bundled, hash-checked projections and makes no request to those publishers.

## 2. Group scope: `ciqual-group-scope-v1`

Ciqual has three group levels. The chocolate group is **group 07 "sugar and confectionery" (produits sucrés), subgroup 0702 "chocolate and chocolate products" (chocolats et produits à base de chocolat), sub-subgroup 000000 (none)**. It holds 29 foods. v1 admits exactly the foods whose `alim_ssgrp_code` is `0702` (decided, D3):

| Code | English name (as published) | French name |
| --- | --- | --- |
| 31000 | Chocolate bar with biscuit | Barre chocolatée biscuitée |
| 31001 | Chocolate bar, chocolate-coated, without biscuit | Barre chocolatée non biscuitée enrobée |
| 31002 | Coconut bar, chocolate-coated | Barre à la noix de coco, enrobée de chocolat |
| 31004 | Milk chocolate, bar | Chocolat au lait, tablette |
| 31005 | Dark chocolate, 50% cocoa, bar | Chocolat noir 50 % de cacao environ, tablette |
| 31009 | Milk chocolate, with puffed/popped cereals, bar | Chocolat au lait aux céréales croustillantes, tablette |
| 31010 | White chocolate, bar | Chocolat blanc, tablette |
| 31012 | Chocolate confectionery or bar, with milk | Barre ou confiserie chocolatée au lait |
| 31018 | Milk chocolate, with dried fruits (nuts, almonds, raisins, praliné), bar | Chocolat au lait aux fruits secs (noisettes, amandes, raisins, praline), tablette |
| 31020 | Milk chocolate, no added sugars, with sweeteners, bar | Chocolat au lait sans sucres ajoutés, avec édulcorants, tablette |
| 31026 | White chocolate, with dried fruits (nuts, almonds, raisins, praliné), bar | Chocolat blanc aux fruits secs (noisettes, amandes, raisins, praliné) , tablette |
| 31030 | Dark chocolate, no added sugars, with sweetener(s), bar | Chocolat noir sans sucres ajoutés, avec édulcorants, en tablette |
| 31032 | Chocolate spread with hazelnuts | Pâte à tartiner chocolat et noisette |
| 31041 | Chocolate confectionery, coated | Confiserie au chocolat dragéifiée |
| 31042 | Chocolate-coated peanut | Cacahuète enrobée de chocolat dragéifiée |
| 31063 | Chocolate confectionery, filled with nuts and/or praliné | Bouchée chocolat fourrage fruits à coques et/ou praliné |
| 31066 | Chocolate and nut confectionery, filled with praliné | Rocher chocolat fourré praliné |
| 31069 | Dark chocolate, with fruits (orange, raspberries, pear), bar | Chocolat noir aux fruits (orange, framboise, poire), tablette |
| 31070 | Dark chocolate, with dried fruits (nuts, almonds, raisin, praliné), bar | Chocolat noir aux fruits secs (noisettes, amandes, raisins, praline), tablette |
| 31071 | Chocolate bar with dried fruits | Barre chocolatée aux fruits secs |
| 31072 | Dark chocolate, filled with mint confectionery | Chocolat noir fourrage confiseur à la menthe |
| 31073 | Soft cake filled with chocolate and milk, with chocolate coating, prepacked, refrigerated | Gâteau moelleux fourré au chocolat et au lait, enrobé de chocolat, préemballé, rayon frais |
| 31074 | Dark chocolate, 70% cocoa, bar | Chocolat noir 70 % de cacao environ, de dégustation, tablette |
| 31080 | Dark chocolate, filled with praliné, bar | Chocolat noir fourré praliné, tablette |
| 31084 | Milk chocolate, filled with praliné, bar | Chocolat au lait fourré au praliné, tablette |
| 31085 | Dark chocolate, more than 40% cocoa, for cooking, bar | Chocolat noir 40% de cacao et plus, à pâtisser, tablette |
| 31091 | Chocolate confectionery, filled with wafer/biscuit | Bouchée/bonbon au chocolat fourrage gaufrettes ou biscuit |
| 31098 | Chocolate bar, milk chocolate, with nougat | Barre chocolat au lait avec nougat |
| 31120 | Chocolate, bar (average) | Chocolat, tablette (aliment moyen) |

**The subgroup holds no cocoa product.** Cocoa powder, cocoa butter and cocoa drinks sit elsewhere: 16030 "Cocoa butter" (subgroup 0902), 18100 "Cocoa powder, no added sugars, powder, instant" and the sweetened drink powders (0602, sub-subgroup 060207), ready-to-drink cocoa (060206) and 42501 "Cocoa powder for baby beverage" (1104). Decision 4 names "chocolate and cocoa products"; the published subgroup is "chocolate and chocolate products". v1 follows the published subgroup exactly and admits none of the cocoa rows; they can come later as their own group change. Chocolate-containing foods in other subgroups (biscuits, cakes, cereals, desserts) also stay out.

**Rule for later groups.** Each further admission is its own versioned change of `ciqual-group-scope-v1` (a list of whole published subgroup or sub-subgroup codes, never single foods picked by name), with its own owner approval, a Ciqual retrieval evaluation across that group's foods, and the earlier replays unchanged. The release, manifest, mapping and value rules below do not change when a group is added. A group change therefore alters only the corpus and the values derived from it (the corpus SHA-256, so the projection `sourceReleaseID` and `manifestHash`), and the Ciqual rows in results. It never changes a CoFID, USDA or TFDA row or the order between them: that follows from the composite v11 invariant (section 5), because cocoa tier keys are computed within each deferral group and removing Ciqual rows from any v11 output gives the v10 output. A food is never admitted outside its published group. The band reading of every admitted row is frozen (section 4).

## 3. Projection rules: `ciqual-projection-v1`

### 3.1 Constituent mapping to the 39 keys

Ciqual 2025 has 74 constituents. Values are per 100 g of food as sold (Ciqual's convention); the basis is `per100Grams`. Units are converted only at the projection boundary (`µg` written as `mcg`).

| NutrientKey | Ciqual constituent (code, English name) | Unit | Notes |
| --- | --- | --- | --- |
| energy_consumed | 328 Energy, Regulation EU No 1169/2011 (kcal/100g) | kcal | see 3.4 |
| carbohydrates | 31000 Carbohydrate | g | available carbohydrate, fibre excluded (CoFID convention; USDA's is by difference) |
| protein | 25000 Protein (N x Jones' factor) | g | A2 |
| fat_total | 40000 Fat | g | |
| fat_saturated | 40302 FA saturated | g | |
| fat_monounsaturated | 40303 FA mono | g | |
| fat_polyunsaturated | 40304 FA poly | g | |
| fiber | 34100 Fibres (fibres alimentaires) | g | |
| sugar | 32000 Sugars | g | |
| cholesterol | 75100 Cholesterol | mg | |
| vitamin_a | 51104 Vitamin A activity, retinol equivalent | mcg | A3, decided in C1; English unit label misprinted "µg/100mg", French says µg/100 g |
| thiamin_b1 | 56100 | mg | |
| riboflavin_b2 | 56200 | mg | |
| niacin_b3 | 56310 | mg | |
| pantothenic_acid_b5 | 56400 | mg | |
| vitamin_b6 | 56500 | mg | |
| biotin_b7 | none | | unknown, `not_declared` |
| folate_b9 | 56700 Vitamin B9 or total folates | mcg | A4 (56702 DFE not used) |
| vitamin_b12 | 56600 | mcg | |
| vitamin_c | 55100 | mg | |
| vitamin_d | 52100 Vitamin D | mcg | D2 (52200) and D3 (52300) not summed |
| vitamin_e | 71010 Alpha-tocopherol | mg | A5 (53100 "Vitamin E" not used) |
| vitamin_k | 54101 Vitamin K1 | mcg | A6 (K2, 54104, not added) |
| calcium | 10200 | mg | |
| chloride | 10170 | mg | |
| iron | 10260 | mg | |
| magnesium | 10120 | mg | |
| phosphorus | 10150 | mg | |
| potassium | 10190 | mg | |
| sodium | 10110 Sodium | mg | see 3.5 |
| zinc | 10300 | mg | |
| chromium | none | | unknown, `not_declared` |
| copper | 10290 | mg | |
| iodine | 10530 | mcg | |
| manganese | 10251 | mg | |
| molybdenum | none | | unknown, `not_declared` |
| selenium | 10340 | mcg | |
| water | 400 Water (g/100g) | g, catalogue unit mL | unknown, `missing_conversion`, as CoFID water is today (no density conversion) |
| caffeine | none | | unknown, `not_declared` (Ciqual 2025 has no caffeine or theobromine) |

Four keys have no Ciqual constituent (biotin, chromium, molybdenum, caffeine). Seven keys have more than one candidate constituent (energy, protein, vitamin A, folate, vitamin D, vitamin E, vitamin K); the projector reads exactly the one named above and never adds or substitutes another, as `project_usda.py` keeps one convention per key. Constituents not listed (ash, salt, individual sugars, starch, polyols, alcohol, organic acids, individual fatty acids, retinol, beta-carotene, kJ energies, N x 6.25 protein) are not projected; the projector records them in the audit only.

### 3.2 Value forms

Within the 29 scoped foods the composition file has 2,146 rows (29 foods x 74 constituents). Their `teneur` forms:

| Form | All 74 constituents | The 35 mapped constituents | Projection |
| --- | --- | --- | --- |
| number with a decimal comma, for example `0,33` | 1,058 | 569 | exact, `augmented` |
| number without a comma, for example `591` (including 10 mapped literal zeros) | 373 | 211 | exact, `augmented`; a declared `0` stays zero |
| `< n`, for example `< 20`, `< 0,01` (32 distinct literals) | 165 | 48 | upper bound (3.3) |
| `traces` | 35 | 6 | unknown (3.3) |
| `-` | 515 | 181 | unknown, never zero |

For the whole table (3,484 foods, 257,816 rows): 91,990 comma numbers, 59,991 plain numbers, 20,075 `< n`, 2,514 `traces`, 83,246 `-`.

- **Projector rejections.** The projector fails the build, over the whole table and not only the scoped rows, so a later group cannot introduce an unhandled form silently, on: any form outside the five above; `< n` with n ≤ 0; a non-`-` value with no confidence code; a `-` that carries a confidence code; a duplicate `alim_code` or duplicate food and constituent pair; a changed byte in any pinned file. On 4 November 2026 every non-`-` row in the table had a code and every `-` had none (83,246 of each).
- **Decimal commas.** `,` is the decimal separator; there are no thousands separators. The projector parses with a fixed rule (one optional comma, digits only), never a locale, and stores the decimal string and the original literal.
- **Confidence codes.** `code_confiance` is A, B, C or D on every value except `-`. Scoped mapped values: A 574, D 225, C 26, B 9. Energy is D on all 29 foods (calculated). Codes are kept in the corpus per value, carried in `manifestReference`, and shown only in details and Developer tools ("Ciqual confidence A"); they never change ranking, compatibility, provenance kind or the estimate label.
- **`min` and `max`.** 521 scoped rows also carry a `min` and/or `max`. They are not projected into nutrients in any case; whether the corpus keeps them for Developer tools is decided in the C1 PR from the Ciqual documentation (A7).
- **`source_code`.** Kept per value as a reference to `sources_2025_11_03.xml`, details only.

### 3.3 Bounds, traces and unknown

- **`< n`** becomes `bounded` with `lower: nil`, `upper: n`, `upperClosed: false`, `origin: augmented`, provenance `generic_composition_dataset`, and a `SourceBoundedNutrientValue` with the same open upper bound. This is the shape the pasted label reader already writes for "less than" values, and phase B's merge copies a generic bound as a bound. It is never shown or totalled as n or as zero; totals follow the existing known-minimum rules for bounds.
- **`traces`** (decided, D4) is unknown with reason `no_compatible_source`, exactly as the CoFID projection treats its `trace` state today. The literal `traces` stays in the corpus and is shown in Developer tools. No lower-only bound is written.
- **`-`** is unknown with reason `not_declared`. Never zero.
- **Declared zero** (`0`) is an exact zero, as TFDA keeps declared zeros.

### 3.4 Energy

Ciqual gives four energy constituents: 327 (kJ) and 328 (kcal) under Regulation (EU) No 1169/2011 factors, and 332 (kJ) and 333 (kcal) from N x Jones' factor with fibres. The projection takes **328, kcal, as published**, never 327 converted and never an app calculation, because the regulation factors are those of UK and EU labels. For the 29 scoped foods 328 and 333 are present on every row; for the five rows checked in detail (31005, 31030, 31074, 31085, 31120) they are equal. Energy confidence is D on all 29 (calculated, not analysed); Developer tools say so.

### 3.5 Sodium and salt

The catalogue has `sodium` and no salt key. The projection maps 10110 Sodium (mg) only. 10004 Salt (g, "sel chlorure de sodium") is not projected and sodium is never derived from salt or the reverse. In the 28 scoped foods with both as numbers, salt (as mg) divided by sodium ranges from 2.42 to 3.71, not a fixed 2.5, so a derivation would also disagree with the source. One food has both as `traces`.

### 3.6 Provenance and identity

- Each value: `sourceKind: generic_composition_dataset`, `sourceID: ciqual`, the app `sourceReleaseID`, `recordID` as in 1.1, `responseHash` the SHA-256 of `compo_2025_11_03.xml`, and `manifestReference`. The corpus stores the per-value part (file, food, constituent, literal, confidence); the searcher builds the full reference at runtime from `CiqualGenericFoodSearch.corpusSHA256`, as TFDA does, for example `compo_2025_11_03.xml;alim=31074;const=10260;literal=11;confidence=A;projection=<corpus SHA-256>`. This satisfies phase B's `isBundledGeneric` (generic kind with a record ID) without any change to it.
- Identity: per 100 g; edible quantity known, 100 g; item class food; preparation from explicit words only (as `usda-preparation-words-v2`), otherwise `unknown`. Bone, skin, drained, packing medium and fortification stay unknown; "no added sugars" and "with sweeteners" stay in the name, not in identity.
- One source record per candidate; no cross-source backfill.
- **French name (decided, D5).** The French name is corpus-only. It is shown in Developer tools for search results, is not searched, is never stored on saved records and is never put in the candidate `variant`. No schema, archive or export change results.
- **Re-resolution.** Ciqual entries are not re-resolution targets, as for USDA and TFDA: `CoFIDReresolutionProvider` offers only the CoFID matcher target, and nothing is added for Ciqual.

## 4. Search

- **Name language.** The searchable and displayed name is Ciqual's published English name (`alim_nom_eng`). No reviewed aliases are added. The candidate variant is the fixed text "Ciqual · French composition estimate · per 100 g", as TFDA's variant names its family; it contains no percentage, so it never contributes a band.
- **Eligibility parity.** `CiqualGenericFoodSearch` implements the existing `GenericFoodSearching` port with the USDA rules: every meaningful query word in the name, the same discovery, preparation and identity guards, `GenericFoodRankingPolicy` preference, the phase A cocoa admission exception, and phase A ordering applied before its 10-row cut. CoFID's UK name equivalence ("dark chocolate" also matching "Chocolate, plain") does not apply to Ciqual.
- **Cocoa bands from Ciqual names.** The English names carry three forms; the French names add "environ" (about) and "et plus" (and more), which are not read (French is not searched):

  | Food | English name form | `cocoa-percent-policy-v1` reads | `cocoa-percent-policy-v2` reads (pinned) |
  | --- | --- | --- | --- |
  | 31074 | "70% cocoa" | point band [70, 70] | point band [70, 70] |
  | 31005 | "50% cocoa" | point band [50, 50] | point band [50, 50] |
  | 31085 | "more than 40% cocoa" | point band [40, 40] (**wrong**: the qualifier is ignored) | `.atLeast(40)` |
  | the other 26 foods | no percentage | no band | no band |

- **"About" (decided, D6).** The English point bands are read as stated, with no tolerance: 31074 is [70, 70], not 65 to 75.

### 4.1 `cocoa-percent-policy-v2`: open-ended bands

v2 adds one `Band` case, `.atLeast(N)`, and changes nothing else in v1.

1. **Phrases.** In text outside parentheses, `N%` directly followed by `cocoa` or `cacao` (with or without `solids`, not followed by an ingredient word) is open-ended when it is preceded by "more than", "over", "at least" or "minimum", or followed (after the cocoa wording) by "or more", "and more" or "minimum". Matching is case-insensitive and accepts the same spacing as v1.
2. **Pass order.** Within one text: parenthesised text is classed as blend and removed, as in v1; ranges are read and stripped, as in v1; then open-ended matches are read as `.atLeast(N)` **and stripped**; then the point pass runs on what remains. So "more than 40% cocoa" gives `.atLeast(40)` and no point band, not nil.
3. **Combination across name and description.** Readings from both texts are collected as in v1. A blend is ignored when any declared or open-ended reading exists, as v1 ignores a blend beside a declared band. If exactly one distinct non-blend reading remains, it is the band. Two distinct non-blend readings (for example a declared band and an `.atLeast`, or two different `.atLeast` values) give no band, as two declared bands do in v1. N outside 0 to 100 gives no band.
4. **Behaviour.** `.atLeast` has `range` nil, so it sorts in tier 4 (no single band). `admits` returns false and `isCocoaMatch` is false, so such a row enters results only by full word coverage ("dark chocolate 40%" reaches 31085 because its name contains "dark" and "chocolate") and the Search screen groups it by name words as any unbanded row. Under `label-estimate-compatibility-v1` it is never a declared band, so it is never compatible.
5. **Notes.** Only when `cocoa_percent` is present:

   | Case | Detail note | Row caution |
   | --- | --- | --- |
   | `.atLeast(N)`, request M | Source states N% cocoa or more, with no single band; you asked for M%. | N% cocoa or more |

6. **Phase B pre-fill (rule 2) unchanged.** `LabelEstimateCompatibility.statedPercent` reads `.declared` bands today, so label text such as "at least 70% cocoa", "minimum 70% cocoa", "more than 70% cocoa", "over 70% cocoa", "70% cocoa or more", "70% cocoa and more" and "70% cocoa minimum" pre-fill 70 under v1. Under v2 that text gives `.atLeast(70)`, so `statedPercent` turns `.atLeast(N)` from label text into a pre-fill of N, under the same one-value rule. `label-estimate-compatibility-v1` behaviour, including its pre-fill results, is unchanged.

### 4.2 Band freezing

`label-estimate-merge-v1` rule 6 reruns `label-estimate-compatibility-v1` on reopen with the live band reader. The band reading of every admitted row is therefore frozen under compatibility v1: any change to how an admitted CoFID, USDA, TFDA or Ciqual row's name, description and record ID read as a band needs `label-estimate-compatibility-v2` (and a reopen rule for records saved under v1). v2 of the cocoa policy is admissible only because:

- a test asserts that the v2 band equals the v1 band for every record in the bundled CoFID, USDA and TFDA corpora (name, description, record ID); and
- the v2 bands of all 29 Ciqual rows are pinned (the table above), so later reader changes are caught.

Milk, white and filled rows keep phase A's rules: milk and white are excluded from cocoa admission; filled and fruit rows have no band.

## 5. Ordering: `composite-generic-ranking-v11`

- The composite takes three deferral groups: **default** (CoFID, USDA), **deferred regional** (TFDA, promotable by `regional-source-order-v1`) and, new, **reference-only** (Ciqual, never promoted). Reference-only routes are interleaved after all other routes at each rank, so the relative offsets of non-Ciqual rows are those of v10.
- Key order: preparation verification, then deferral group (default; then TFDA when not promoted; then Ciqual), then cocoa tier, then exact name and representation preference. When Taiwan is promoted, CoFID, USDA and TFDA form one group and interleave as in v10, and Ciqual still follows. The fat partition and the outer preparation partition run afterwards, unchanged, as stable partitions.
- **Cocoa tier keys are computed inside each deferral group.** `CocoaPercentPolicy.tierKeys` takes the bands of one group's rows only, so a reference row's band can never change which default or regional row is "the greatest band below" (tier 2) or move it between tiers. In v10 the keys were computed over all rows; for default and regional rows v11 computes them over exactly the rows v10 saw.
- **Invariant: removing Ciqual rows from any v11 output gives the v10 output exactly, for every request.** This holds through the fat and preparation partitions because they are stable and the comparator for any two non-Ciqual rows is unchanged. It is stated on the ranked match list; the one visible difference is that a request whose only matches are Ciqual rows returned no result in v10 and now returns them.
- Consequence: for "dark chocolate 70%", USDA 170273 leads, and Ciqual 31074 follows every CoFID and USDA row in the same preparation and fat partition, including out-of-band ones such as CoFID 17-491. That is the cost of decision 5.
- **Ciqual and TFDA (decided, D7).** Ciqual follows TFDA, so every existing row keeps its position.
- Today `CompositeGenericFoodSearch` has one `promotesRegional` closure for all regional sources, so adding Ciqual to `regionalSources` would promote it whenever Taiwan is promoted. v11 adds the separate reference-only group instead.
- `composite-generic-ranking-v11` is stamped on new capture evidence; stored v10 and older values still decode (free text). No schema, archive or export change.

## 6. Phase B interplay

`label-estimate-compatibility-v1` already admits any row whose every stated value has `generic_composition_dataset` provenance with a record ID, a name containing "chocolate" and none of milk, white or ruby, and a declared band containing the confirmed percentage. With `cocoa-percent-policy-v2`:

| Ciqual row | Compatible at |
| --- | --- |
| 31074 Dark chocolate, 70% cocoa, bar | exactly 70 |
| 31005 Dark chocolate, 50% cocoa, bar | exactly 50 |
| 31085 Dark chocolate, more than 40% cocoa, for cooking, bar | never (`.atLeast`); refused at save. Under v1 it would wrongly be compatible at exactly 40 |
| 31030, 31069, 31070, 31072, 31080 (dark, no stated percentage) | never |
| 31120 Chocolate, bar (average); bars, confectionery, spread, cake | never (no band) |
| 31004, 31009, 31010, 31018, 31020, 31026, 31084, 31098 (milk or white) | never |

The pinned USDA estimates for 86% to 99% and 100% are unchanged, as rule 3 promises. A 70% bar now gets two compatible rows (USDA 170273 and Ciqual 31074); the estimate list keeps search order, so Ciqual is listed second. Ciqual `< n` values are copied as bounds by `label-estimate-merge-v1` (rule 4, "unknown + bounded"). The rule 3 prose names "CoFID, USDA, or TFDA"; C2 updates that sentence to name Ciqual too, a wording change with no behaviour change. Phase B3, the Confirm estimate section, has merged (#397, 1b5d8bf), so phase C has no pending phase B dependency.

## 7. Surfaces

- **Source family (decided, D8).** `FoodSearchResultSummary.SourceFamily` gains `frenchReference`, "French reference", mapped from `sourceID == "ciqual"`. The search row source label reads "Ciqual · on device"; Confirm's source line reads "French reference · estimate". Both land in C2 with the composition root.
- **Health and Copy all.** Ciqual nutrients count like any other generic estimate under the existing rules: exact values as estimates, bounds as bounds, unknown as unknown. No new line or format.
- **Developer tools.** Release, record ID, source manifest and corpus SHA-256, attribution, licence, per-value literal, confidence code and source code; for search results also the French name, and `min`/`max` if C1 keeps them (A7).
- **Food daily export.** Already carries `source_kind`, `source_release_id` and per-value provenance; a Ciqual entry needs no new field. C3 confirms the export contract does not enumerate release IDs or families.
- **Copy.** British spelling, no emoji; VoiceOver reads "French reference, estimate".

## Not in scope

- Any Ciqual food outside subgroup 0702, including cocoa powder and cocoa butter.
- French name search, aliases or a French market setting; Ciqual promotion.
- Interpolation between bands; any band tolerance for "about".
- A lower-only bound for "traces".
- Theobromine or any new NutrientKey; a salt key.
- Changes to CoFID, USDA or TFDA projections or rankings.
- Re-resolution to Ciqual.
- Any runtime network destination.

## Architecture gate

**Responsibilities**

- Tooling (`Tools/FoodSourceEvaluation/project_ciqual.py`, `audit_ciqual.py`, `tests/test_ciqual_projection.py`): hash checks against pinned values, source manifest, group scope, constituent mapping, value-form parsing and rejections, corpus and audit output. Deterministic, offline, local paths only.
- Infrastructure (`CiqualGenericFoodSearch` in `FoodGenericSearch`): corpus load and hash check, `SourceRelease`, candidate projection including the runtime `manifestReference`, matching.
- Application: `CocoaPercentPolicy` v2 (`.atLeast`, pre-fill mapping in `statedPercent`), `CompositeGenericFoodSearch` v11 (reference-only group, per-group tier keys). No new port.
- Presentation: the family label, Confirm source line and Developer tools lines. Composition root: wire Ciqual as reference-only.

**Dependency direction:** presentation → application → domain; `FoodGenericSearch` depends on application and domain; the composition root alone constructs `CiqualGenericFoodSearch`. No new package target; `check-boundaries.sh` unchanged.

**Invariants:** unknown never zero; `-` and `traces` never zero; `< n` never exact; one constituent per key, never summed; sodium never derived from salt; one record per candidate; no automatic selection or save; removing Ciqual rows from any v11 output gives the v10 output; bands of admitted rows frozen under compatibility v1; confidence codes never change ranking or compatibility; the French name never reaches a saved record; no runtime egress; stored records decode and re-encode unchanged.

**Extension axes:** further Ciqual groups through `ciqual-group-scope` versions only; other bundled reference sources through the same reference-only group. Mapping, value forms, identity and band rules stay closed.

**Contract tests (synthetic fixtures plus the pinned corpus SHA-256)**

- **Subsequence property:** for every FoodSearchQuality v3 to v8 query, and for "dark chocolate p%" with p from 1 to 100 in 0.5 steps, with Taiwan promoted and not promoted, removing Ciqual rows from the v11 output gives the v10 output exactly; repeated with a synthetic reference-only row banded at 90% to prove the per-group tier keys.
- **Band equality:** v2 band equals v1 band for every CoFID, USDA and TFDA record (name, description, record ID); the 29 Ciqual bands match the pinned table.
- **`.atLeast` precedence phrases:** each phrase in 4.1 rule 1 gives `.atLeast(N)` and no point band; combination with a blend (open-ended wins), with a declared band and with a second `.atLeast` (no band); an ingredient word after the cocoa wording gives no band; tier 4, `admits` false, `isCocoaMatch` false; note and caution text.
- **Rule 2 pre-fill phrases:** "at least 70% cocoa", "minimum 70% cocoa", "more than 70% cocoa", "over 70% cocoa", "70% cocoa or more", "70% cocoa and more" and "70% cocoa minimum" pre-fill 70 under v2 as under v1; two different values still give no pre-fill.
- **Phase B reopen:** the existing phase B and archive contract 8 fixtures reopen unchanged; a layered save with 31074 at 70% saves and reopens; 31085 is refused at save for any percentage, including 40.
- **Projector rejections:** synthetic XML with an unknown form, `< 0`, `< -1`, a missing confidence code on a number, a `-` with a code, a duplicate code or pair, a changed byte in each pinned file, and a food outside 0702 (excluded); BOM, padded elements, `missing` attribute, decimal comma, `< 0,01` and `< 20` to upper bounds, `traces` and `-` to unknown, declared `0` kept; one constituent per key with 333 ignored; salt not projected.
- **Corpus and searcher:** pinned corpus SHA-256 at load; source manifest SHA-256; 29 records; every projected value equals its source literal (audit, as TFDA's); 31074 per 100 g iron 11 mg, magnesium 200 mg, selenium bounded `< 20` mcg, vitamin E (alpha-tocopherol) 0.67 mg, vitamin B12 a declared zero; biotin, chromium, molybdenum, caffeine and water unknown; `manifestReference` built from `corpusSHA256`; `isBundledGeneric` true; variant has no percentage; no French name on a saved record.
- **Re-resolution refusal:** a saved Ciqual entry offers no re-resolution target.
- **Family mapping:** `ciqual` maps to `frenchReference`, "French reference", search row "Ciqual · on device", Confirm "French reference · estimate"; CoFID, USDA and TFDA mappings unchanged.
- **Version assertions:** `CocoaAwareSearchTests` and `RegionalSourceOrderTests` updated to `cocoa-percent-policy-v2` and `composite-generic-ranking-v11`.

**Replays.** FoodSearchQuality v3 to v7 replays keep their current source lists and their frozen `--verify-report` files, byte for byte. v8 adds a Ciqual replay of the production composite with `WHR_RETRIEVAL_REPORT_V8`, a new `score_retrieval.py` step in `.github/workflows/ios-ci.yml` and a frozen report. FoodQueryEvaluation is unchanged (no parser change).

## Delivery slices

- **C1, tooling and corpus:** projector, audit, Python tests, bundled corpus, pinned hashes, audit file; adds this spec to `CODE_READ_DOCS` in `.github/scripts/ci_changes.py`. The C1 PR also:
  - decides A3 (vitamin A convention; vitamin A stays unknown if still unclear) and A7 (`min`/`max`) from the Ciqual documentation PDF;
  - adds the exact projector and audit commands under "Reproduce", and the expected corpus SHA-256;
  - adds a worked trace of 31074 iron from Developer tools back to the `compo_2025_11_03.xml` literal.
- **C2, searcher, composite and source line:** `CiqualGenericFoodSearch`, `cocoa-percent-policy-v2` with the pre-fill mapping, `composite-generic-ranking-v11`, composition root, `frenchReference`, the search row label and Confirm source line, the rule 3 wording, version assertions, and FoodSearchQuality v8 with expectations frozen before code ("dark chocolate 70%", "dark chocolate 50%", "dark chocolate 40%", "dark chocolate", "milk chocolate", "white chocolate", "chocolate spread"; v3 to v7 byte-identical).
- **C3, surfaces and evaluation:** Developer tools lines, export contract check, journey QA in the simulator on search and on the merged Confirm estimate section (#397), invariant review, ledger row.

## Gate questions, answered from the code

- **Is a bounded generic value representable?** Yes. `NutrientBounds` with `origin: augmented` and `generic_composition_dataset` provenance passes `NutrientEntry` validation (`Nutrition.swift`), and `lower: nil, upper: n` is the shape `PastedLabelSource` writes. No domain change.
- **How do the other bundled sources treat traces and missing?** CoFID maps `trace` and `present_unquantified` to unknown (`no_compatible_source`) and `blank` and `unmapped` to `not_declared`; water in g becomes `missing_conversion` (`CoFIDGenericFoodSearch.nutrients`). TFDA and USDA omit missing values, which become `not_declared`.
- **Can Ciqual join `regionalSources`?** Not as is: one `promotesRegional` closure covers every regional source, so Ciqual would be promoted with Taiwan. Hence the reference-only group in v11.
- **Are cocoa tier keys per source today?** No: v10 computes `tierKeys` over all interleaved rows, so a new source's band could change another row's tier 2 status. Hence per-group keys in v11.
- **Does phase B need code for Ciqual?** Only the pre-fill mapping in `statedPercent` (4.1 rule 6). `LabelEstimateCompatibility.isBundledGeneric` checks provenance kind and record ID only; the band reader decides the rest.
- **Who offers re-resolution?** Only `CoFIDReresolutionProvider`, with the CoFID matcher version as target; USDA and TFDA have none, and Ciqual gets none.
- **Does the export need a new field?** No; `source_kind`, `source_release_id` and provenance already carry the source (`FoodDailyExport.swift`).

## Gate record

`architecture-gate`, read-only, 4 November 2026: PASS WITH CHANGES, all findings applied.

- **High.** Composite v11 tier keys per deferral group and the removal invariant (section 5; section 2 group rule). Rule 2 pre-fill kept for open-ended label phrases (4.1 rule 6).
- **Medium.** `.atLeast` details: strip before the point pass, combination, tier 4, `admits` and `isCocoaMatch` false, note copy (4.1). Band freezing under compatibility v1, with a band-equality test replacing the qualifier scan and the 29 Ciqual bands pinned (4.2). Replays: v3 to v7 frozen, v8 added, version assertions (Architecture gate, Replays and Contract tests). Slices: `frenchReference` and the Confirm source line in C2; B3 merged (Delivery slices, section 6). French name corpus-only (3.6). `CODE_READ_DOCS` in C1 (Delivery slices).
- **Low.** Projector rejections and runtime `manifestReference`, one set of hash terms (1.1, 3.2, 3.6). Re-resolution excluded with a test (3.6, Contract tests). A3, A7 and the C1 reproduction items (Delivery slices).

## Decisions record

All on 4 November 2026. D1 is the owner's; D2 to D10 are programme lead decisions under the owner's delegation, recorded on #384.

- **D1, egress:** the developer download is not app egress; the clarifying sentence is approved and applied to `privacy-and-egress.md` (1.3).
- **D2, attribution:** the record's French citation with the DOI (1.2).
- **D3, scope:** subgroup 0702 only; cocoa powder and butter later as their own group change (2).
- **D4, traces:** unknown, as CoFID (3.3).
- **D5, French names:** corpus-only, not searched, never on saved records (3.6).
- **D6, "about":** no tolerance; point bands as stated (4).
- **D7, Ciqual and TFDA:** Ciqual after TFDA (5).
- **D8, family label:** "French reference" (7).
- **D9, `cocoa-percent-policy-v2`:** `.atLeast` approved as amended by the gate (4.1, 4.2).
- **D10, composite v11:** the never-promoted reference-only group approved as amended by the gate (5).

## Ambiguities

- A1. Energy: 328 and 333 agree on the rows checked; the projector reads 328 and the audit reports any food where they differ.
- A2. Protein: 25000 (N x Jones' factor) and 25003 (N x 6.25) both exist; for chocolate the Jones factor is 6.25, so they are equal in scope. 25000 is used.
- A3. Vitamin A: 51104's INFOODS tag is RAE (retinol activity equivalents) while its names say retinol equivalent; CoFID's RETEQU is retinol equivalents, and USDA vitamin A is not mapped. Decided in the C1 PR from the Ciqual documentation; vitamin A stays unknown if still unclear.
- A4. Folate: 56700 (total folates) matches USDA 1177 and CoFID FOLT; 56702 (DFE) is present on one scoped food and is not used.
- A5. Vitamin E: 53100 "Vitamin E" is `-` on 24 of 29 scoped foods, while 71010 alpha-tocopherol has 18 numbers; USDA maps alpha-tocopherol (1109). 71010 is used; 53100 is not.
- A6. Vitamin K: K1 (54101) only, as CoFID VITK1 and USDA 1185; K2 (54104, one scoped number) is not added.
- A7. `min`/`max`: never nutrient bounds; whether they are kept for Developer tools is decided in the C1 PR from the Ciqual documentation.

## Reproduce

1. Download the five files by ID from `https://entrepot.recherche.data.gouv.fr/api/access/datafile/<id>` into a folder outside Git, and the metadata from `https://entrepot.recherche.data.gouv.fr/api/datasets/:persistentId/?persistentId=doi:10.57745/RDMHWY`.
2. Check MD5 against the metadata and SHA-256 against 1.1.
3. C1 adds the projector, audit and test commands here, with the expected corpus SHA-256, as in the Taiwan catalogue.
