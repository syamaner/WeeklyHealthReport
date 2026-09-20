# UK food source coverage and licence evaluation

Status: **complete — final review passed**

Evidence dates: **19–20 September 2026**
Contract authority: [Food identity and nutrition provenance contract](food-identity-nutrition-contract.md)

This document records the evidence gathered for issue #87. It does not select an
application architecture, change a production schema or authorise provider use.
The research used public read-only sources. Nine public Ocado product pages, six
supplement product cases and nineteen user-supplied food-package cases were inspected
against public manufacturer or retailer pages; there was no automated collection,
login, basket, subscription or order action. No provider was written to and no
commercial party was contacted.

## Decision

The evidence supports this provisional Phase 1 source stack:

1. Keep user-captured packaging and manual values as the identity and label-value
   authority. Preserve the evidence even when a dataset later resolves it.
2. Admit the immutable 2021 CoFID workbook as an **augmentation source for
   user-selected generic-food matches**, subject to the ingest qualifications
   below. A numeric CoFID value becomes `augmented`, never `measured`.
3. Do not depend on Open Food Facts (OFF) for Phase 1 identity or canonical
   resolution. A dated independent legacy cohort produced 17 hits from 49 GTINs.
   A current nine-product Ocado page sample supplied useful label ground truth,
   but eight pages exposed no public UPC/GTIN and none supplied an immutable
   source release or formulation-effective date, so it could not establish OFF
   exact-variant, reformulation or freshness accuracy. A later user-invoked
   candidate lookup may be evaluated separately, but its result remains untrusted
   evidence. Its ODbL boundary also requires a deliberate storage and attribution
   design.
4. Do not use USDA FoodData Central to silently fill CoFID gaps in Phase 1. It is
   versionable and permissively licensed, but its branded market coverage is US
   and New Zealand and its generic records encode different regional products and
   fortification practices. It remains a comparison source, not a default merge
   source.
5. Exclude the current FN-NBRI APIs and all commercial candidates from the
   canonical path until their persistence, redistribution and application-use
   rights are obtained in writing. No enquiry was made during this spike.

This completes #87 as a measured decline rather than a promotion. The barcode
coverage cohort is deliberately labelled as a 2015 Greater London legacy sample;
no score is presented as current or universal UK pantry coverage. The separate
current recurring-pantry sample tests the contract against real public label
pages but, because product identifiers and history are missing, is not silently
substituted as an OFF accuracy cohort.

## Artefact manifest and reproducibility

| Artefact | Release or observation | Size | Integrity / version |
| --- | --- | ---: | --- |
| CoFID workbook | 2021, GOV.UK asset | 4,629,542 bytes | SHA-256 `436e9445ef2adb2a75f3d7edd51302de3adad25385f9795fc94ba58bd030e97d` |
| Tesco Grocery 1.0 food categories | Figshare v2; 2015 Greater London purchases | 1,375,434 bytes | SHA-256 `e79c86e1247408238d3062c7f78f18ca054d68d8d1e6def92ea70435347e3f15`; CC BY 4.0 |
| OFF legacy-cohort observation | Live API v3.6 reads on 2026-09-20 | 49 product reads | Redacted aggregate and response-manifest hash in `tesco-off-public-cohort-result.json`; raw mutable responses not committed |
| Ocado recurring-pantry observation | Nine public product pages read manually on 2026-09-20 | 9 page reads | Dated redacted result in `ocado-public-recurring-pantry-result.json`; purchase dates, quantities, frequency and prices not retained |
| Supplement-label observation | Six public manufacturer or retailer product cases read manually on 2026-09-20 | 6 product cases | Dated redacted result in `supplement-public-label-result.json`; source screenshots, intake frequency, schedule and purpose not retained |
| User-supplied package-label observation | Nineteen food package cases inspected on 2026-09-20 | 19 product cases | Evidence hashes and dated result in `user-supplied-package-label-result.json`; raw package images not committed |
| OFF JSONL bulk export | HTTP headers observed 2026-09-19 22:05 UTC | 13,008,035,579 bytes compressed | S3 version `bRcbj75WCnZmGCTgPNW0kAQIss8e7rPN`; last modified 2026-09-19 06:47:26 GMT |
| OFF CSV bulk export | HTTP headers observed 2026-09-19 22:05 UTC | 1,275,171,186 bytes compressed | S3 version `uvydhnebwGxhERAxg4cGeculdh05rjIg`; last modified 2026-09-19 12:21:04 GMT |
| FoodData Central | April 2026 published downloads | Foundation JSON 459 KB compressed; branded JSON 195 MB compressed | release-labelled historical downloads retained by USDA |

The OFF sizes came from `HEAD` requests; neither export was downloaded. The CoFID
workbook was downloaded from the [official GOV.UK publication page](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid)
and measured locally. Reproduce the analysis with:

```sh
python3 -m venv /tmp/cofid-evaluation
/tmp/cofid-evaluation/bin/pip install -r Tools/FoodSourceEvaluation/requirements.txt
/tmp/cofid-evaluation/bin/python Tools/FoodSourceEvaluation/analyse_cofid.py \
  /path/to/McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021.xlsx
```

The analyzer emits JSON and checks the observed workbook hash. The source download
is deliberately not checked into the repository.

The legacy OFF cohort is selected independently of OFF from the CC BY 4.0
[Tesco Grocery 1.0 food-category file](https://doi.org/10.6084/m9.figshare.8668265.v2).
Reproduce its source filtering and private sample manifest with:

```sh
python3 Tools/FoodSourceEvaluation/analyse_tesco_off_sample.py \
  /path/to/food_categories.csv --output /tmp/tesco-off-private-sample.json
```

The repository result omits GTINs and raw OFF responses. It preserves redacted
hit/miss and adjudication outcomes plus sample and response-manifest hashes. A
later rerun can be compared with the dated observation, but is not expected to be
identical; the live API is not an immutable canonical source release.

The selector emits `canonical_private_sample_sha256` before optional redaction.
That digest can therefore be compared directly with the dated result without
committing the selected GTINs.

For contract use, the release should be named from the immutable artefact, for
example `cofid:2021:sha256:436e9445…97d`; the full digest remains in its manifest.
Derived source-record IDs must be scoped to that release.

## CoFID 2021 measured result

### Shape and identity

The workbook has 2,887 food rows but only 2,886 unique food codes. Code `13-669`
is duplicated for two different records: row 55, “Aubergine, flesh and skin,
roasted in rapeseed oil”, and row 2827, “Watercress, raw”. Therefore a CoFID food
code alone does not satisfy the contract's stable source-record identity rule.
An ingest must use an immutable release ID plus a deterministic row identity (for
example worksheet row and a normalized-row hash), retain the published code as a
non-unique source attribute and reject any unexpected duplicate drift.

The nutrient sheets use the same row layout. Values are normally per 100 g; the
[official user guide](https://assets.publishing.service.gov.uk/media/60538e66d3bf7f03249bac58/McCance_and_Widdowsons_Composition_of_Foods_integrated_dataset_2021.pdf)
states that alcoholic beverages are per 100 ml. Basis therefore cannot be assumed
from the numeric column alone.

Identity-relevant facts are mostly embedded in names/descriptions rather than
structured fields. Simple, reproducible name markers found 37 rows containing
`fortified`, 29 containing `drained`, none containing `undrained`, 111 containing
`weighed with bone` (including the plural), one containing `boneless`, 60 containing
`canned`, and none containing `supplement`. These counts show examples,
not completeness: an ingest must parse them only into proposed assertions and
require confirmation for decisive identity fields.

### Nutrient coverage

The workbook exposes source columns for 36 of the contract's 39 nutrients. The
counts below use all 2,887 rows. `Tr` is CoFID's trace marker; `N` means present in
significant quantity but no reliable amount. Both are counted separately from
blank and numeric cells.

| Contract key | CoFID code | Numeric | `Tr` | `N` | Blank |
| --- | --- | ---: | ---: | ---: | ---: |
| `energy_consumed` | `KCALS` | 2849 | 5 | 32 | 1 |
| `carbohydrates` | `CHO` | 2765 | 88 | 32 | 2 |
| `protein` | `PROT` | 2838 | 49 | 0 | 0 |
| `fat_total` | `FAT` | 2789 | 98 | 0 | 0 |
| `fat_saturated` | `SATFOD` | 2363 | 248 | 262 | 14 |
| `fat_monounsaturated` | `MONOFOD` | 2273 | 300 | 299 | 15 |
| `fat_polyunsaturated` | `POLYFOD` | 2355 | 219 | 297 | 16 |
| `fiber` | `AOACFIB` | 1473 | 75 | 471 | 868 |
| `sugar` | `TOTSUG` | 2634 | 155 | 96 | 2 |
| `cholesterol` | `CHOL` | 2672 | 24 | 176 | 15 |
| `vitamin_a` | `RETEQU` | 1925 | 589 | 372 | 1 |
| `thiamin_b1` | `THIA` | 2565 | 205 | 117 | 0 |
| `riboflavin_b2` | `RIBO` | 2599 | 162 | 126 | 0 |
| `niacin_b3` | `NIAC` | 2658 | 110 | 119 | 0 |
| `pantothenic_acid_b5` | `PANTO` | 2247 | 96 | 543 | 1 |
| `vitamin_b6` | `VITB6` | 2408 | 117 | 362 | 0 |
| `biotin_b7` | `BIOT` | 1925 | 159 | 803 | 0 |
| `folate_b9` | `FOLT` | 2382 | 134 | 371 | 0 |
| `vitamin_b12` | `VITB12` | 2452 | 309 | 126 | 0 |
| `vitamin_c` | `VITC` | 2109 | 687 | 90 | 1 |
| `vitamin_d` | `VITD` | 2203 | 359 | 323 | 2 |
| `vitamin_e` | `VITE` | 1996 | 100 | 790 | 1 |
| `vitamin_k` | `VITK1` | 285 | 18 | 0 | 2584 |
| `calcium` | `CA` | 2813 | 27 | 46 | 1 |
| `chloride` | `CL` | 2462 | 61 | 362 | 2 |
| `copper` | `CU` | 2499 | 243 | 144 | 1 |
| `iodine` | `I` | 1396 | 304 | 1183 | 4 |
| `iron` | `FE` | 2749 | 89 | 48 | 1 |
| `magnesium` | `MG` | 2761 | 38 | 87 | 1 |
| `manganese` | `MN` | 2284 | 303 | 298 | 2 |
| `phosphorus` | `P` | 2805 | 30 | 51 | 1 |
| `potassium` | `K` | 2818 | 25 | 43 | 1 |
| `selenium` | `SE` | 1766 | 437 | 681 | 3 |
| `sodium` | `NA` | 2747 | 97 | 43 | 0 |
| `zinc` | `ZN` | 2577 | 141 | 168 | 1 |
| `water` | `WATER` | 2856 | 24 | 7 | 0 |
| `chromium` | — | 0 | 0 | 0 | 2887 |
| `molybdenum` | — | 0 | 0 | 0 | 2887 |
| `caffeine` | — | 0 | 0 | 0 | 2887 |

Mapping qualifications are material:

- `AOACFIB`, not the separate NSP column, maps to `fiber`.
- `NIAC`, not niacin equivalent, maps to `niacin_b3`.
- `VITK1` is phylloquinone only. It is a restricted component candidate for
  `vitamin_k`, not evidence that total vitamin K is known. Only 285 rows are
  numeric in any case.
- CoFID expresses water as grams while the repository canonical unit is `mL`.
  Ingest must retain the source unit and use an explicit, versioned conversion
  rule rather than relabelling the source value.
- Chromium, molybdenum and caffeine have no columns and remain `unknown` unless
  another compatible source supplies them.
- Numeric dataset cells map to `augmented`. `N`, blank and a `Tr` value without a
  documented numeric upper bound map to `unknown`, with their source marker and
  reason preserved. `Tr` must not become zero or an invented `bounded` interval.

The practical gaps are not limited to rare nutrients. Numeric coverage is 51.0%
for AOAC fibre, 48.4% for iodine and 9.9% for vitamin K1. CoFID is therefore a
useful generic-food augmenter, not a complete 39-nutrient resolution.

### Food-family fit

| Family | Finding | Phase 1 treatment |
| --- | --- | --- |
| Generic whole and prepared foods | Core CoFID use; descriptions and references provide useful matching context | User-selected match may augment compatible nutrients |
| Canned/drained and bone/skin variants | Variants exist, but decisive facts are text and edible conversion factors rather than a complete structured identity model | Parse as proposals; require exact compatibility and user confirmation |
| Fortified foods | Some generic fortified variants exist; no market-effective product identity or reformulation history | Do not use as a substitute for a current package label |
| Branded packaged foods | No barcode product master, label-effective dates or reliable current reformulation chain | CoFID cannot establish product identity or freshness |
| Supplements | No rows named as supplements and no dose/form/compound identity model | Out of CoFID scope |
| Drinks and water | Drinks exist, with a documented 100 ml exception for alcohol; water is a nutrient and an item classification in the repository contract | Preserve basis explicitly; do not infer density or serving conversion |

The 2021 page says that this release mainly added pork data and corrected three
published values, while the rest remained from 2019. CoFID itself warns that
values are typical rather than definitive and that processed-food formulations
change. It cannot establish current product-label truth.

## Ocado public recurring-pantry observation

The user supplied a multi-order Ocado purchase list to make the validation less
abstract. Duplicate purchases, one non-food item and an unavailable item that was
substituted were excluded. The repository does not retain purchase dates, use-by
dates, quantities, frequency or prices. Nine food products were deliberately
selected to exercise the contract's difficult boundaries rather than to estimate
market prevalence. Public pages were read manually in Safari while logged out;
no basket, order, review or account state was changed.

All 9/9 exact public product pages exposed an Ocado product ID, pack description
and nutrition panel. Ingredient lists were present for 7/9. Only 1/9 exposed a
public UPC or GTIN, and 0/9 exposed either an immutable source release or a
formulation-effective date. Consequently these pages can corroborate a captured
package at an observation time, but cannot independently establish exact barcode
coverage, label freshness or reformulation history.

The cases materially exercise the frozen contract:

| Case | Public evidence | Contract consequence |
| --- | --- | --- |
| M&S sardines in olive oil | 120 g net, 90 g drained; nutrition per 100 g drained; small soft edible bones retained | Bone state, packing medium, drained quantity and basis are decisive identity, not descriptive garnish |
| M&S mackerel in olive oil | 125 g net, 88 g drained; 44 g half-can serving; may contain bones | Net quantity cannot substitute for edible/drained quantity; “may contain” remains uncertainty, not `with_bone` |
| Eat Wholesome black beans | 60% beans plus water; rinse before use; nutrition only says per 100 g; no drained weight | Packing medium is observable, but drained state, edible quantity and consumption basis remain unresolved |
| Warburtons seeded brioche buns | Per 100 g and per 62.5 g bun; marketed “enriched with butter & egg”; no added vitamin/mineral declaration | Marketing “enriched” must not be mapped to the contract's nutrient-fortification state |
| M&S soda water | Carbonated water plus sodium bicarbonate; per 100 mL and 250 mL; six `<` nutrient values; public UPC | Classify as `water`; preserve each `<` value as `bounded`, not zero; serving basis remains separate from container volume |
| M&S beef burgers | Raw, needs cooking, two servings; two `<` nutrient values | Preparation state and label bounds survive resolution; cooked values must not be inferred from the raw label |
| M&S frozen salmon | Frozen raw portions, defrost before cooking, may contain bones | Frozen/preparation and uncertain bone state prevent a silent generic fresh-salmon match |
| Graham's organic whole milk | Pasteurised, unhomogenised; per 100 mL; no calcium value published | An unlisted nutrient remains `unknown` even when a generic composition source could later augment it |
| M&S washed baby-leaf salad | Washed and ready to eat; mixed named leaves; 80 g bag | Prepared mixed produce is not interchangeable with any one raw leaf record |

The two canned fish pages publish drained weights and drained nutrition bases. The
canned-pulse page does not, so liquid-packed cases are 2/3 complete for decisive
consumption basis, not 3/3. Two pages contain explicit label bounds. All nine omit
most of the contract's 39 nutrients; omitted fields remain `unknown` until a
compatible versioned augmenter supplies them.

This purposeful pantry sample contains no supplement and no confirmed
nutrient-fortified food. The brioche page demonstrates why the latter cannot be
inferred from the word “enriched”. A separate supplement-label observation below
covers dose form, compound and serving-basis failures. A positive fortified-food
example remains a fixture requirement for later evaluation; its absence does not
weaken the negative source-adoption decision.

The result is recorded in `ocado-public-recurring-pantry-result.json`. It stores
only the public product facts needed to reproduce the contract judgement. It is
not a product catalogue, does not grant retailer reuse rights and does not admit
Ocado as a canonical source. Any implementation-time use beyond manual evidence
review would require a separate rights, update and source-release decision.

## User-supplied food package observation

### Olympus 10% strained Greek yoghurt

A supplied Olympus yoghurt package image exposes EAN-13 `5202178085963`, a 1 kg
net weight and establishment mark `GR 46.1 EC`. The check digit is valid. The raw
image remains local-only; its SHA-256 identifies the evidence without adding the
image to the repository.

The GTIN has exact public matches to Olympus/Olympos 10% fat strained Greek
yoghurt, 1 kg. Costco UK's current public page independently names the same product
and pack as item `235777_BD`, although it does not publish the GTIN. An official
Olympus 10% yoghurt page publishes per-100-g nutrition: 134 kcal, 10 g fat, 6.2 g
saturates, 4 g carbohydrate, 4 g sugars, 7 g protein and 0.18 g salt. The page has
neither an immutable release nor a formulation-effective date.

A later user-supplied table, whose source URL and release were not provided, gives
130 kcal, 10 g fat, 6.2 g saturates, 48 mg cholesterol, 4 g carbohydrate, 4 g
sugars, 6 g protein, approximately 0.1075 g salt and 43 mg sodium per 100 g; fibre
is shown as `?`. Its separate “Compared to: Whole milk yogurts” column contains
category averages and is excluded from product evidence. The user explicitly
confirmed that the product column is correct and should be used as-is. That
assertion promotes its numeric canonical values to an evidence-scoped manual
declaration; it does not turn the table into a physical package panel. The table
agrees with the manufacturer page for fat, saturates, carbohydrate and sugars but
conflicts on energy, protein and salt. Its salt and sodium entries are internally
consistent with the factor 2.5, but that does not establish which was originally
declared.

This produces a deliberately split result:

- GTIN and net weight are measured package facts;
- product name, 10% variant, strained state and Costco item are strongly
  corroborated identity candidates;
- “10% fat” in the title is not by itself a measured nutrient declaration;
- the user-confirmed table is the effective manual declaration at its per-100-g
  basis; fibre remains `unknown` because the table itself shows `?`;
- the conflicting manufacturer values remain rejected candidates rather than being
  deleted; and
- a later package panel may create stronger physical evidence without rewriting
  this assertion or its source table.

### The Estate Dairy Jersey Milk Cottage Cheese

Two supplied package images establish EAN-13 `5065019089359` (valid check digit),
450 g net weight, establishment mark `UK EB031`, The Estate Dairy at Wallstone
Farm, and an exact `per 100 g` nutrition basis. Ingredients are Jersey milk,
Jersey cream, live cultures and low-sodium sea salt. The printed panel declares
135 kcal, 7.3 g fat, 5.0 g saturates, 4.1 g carbohydrate, 3.1 g sugars, 13.2 g
protein and 0.64 g salt. `salt_to_sodium_v1` therefore derives 256 mg sodium per
100 g while retaining salt as the source declaration.

The current Ocado page for the same named 450 g product publishes 123 kcal, 7.8 g
fat, 6.9 g saturates, 3.6 g carbohydrate, 3.6 g sugars, 10.0 g protein and 0.9 g
salt per 100 g. The producer's current page instead describes approximately 61 g
protein per 450 g pot and 7.5% fat, closer to the supplied package but still not an
exact versioned panel. Neither public page provides a formulation-effective date.

The package declaration takes precedence for this evidence-scoped product version.
The public disagreement is retained as possible reformulation or retailer
staleness; the evidence does not choose between those causes. A later different
panel under the same GTIN must create another product and resolution version rather
than overwrite this package.

### Lancashire Farm Greek Style Luxury Yogurt

A barcode-only image supplies valid EAN-13 `5035251001310`. Independent current
public GTIN listings resolve it as Lancashire Farm Greek Style Luxury Yogurt, 10%
fat, 1 kg. The manufacturer, Ocado and Asda pages agree on a per-100-g panel:
120 kcal, 10 g fat, 5.15 g saturates, 2.6 g monounsaturates, 0.46 g
polyunsaturates, 6.5 g carbohydrate, 3.4 g sugars, 4.13 g protein, fibre `<0.5 g`,
0.15 g salt and 0.14 g calcium. The salt declaration would derive 60 mg sodium,
and calcium converts to the canonical 140 mg.

The agreement materially strengthens the product candidate but does not make the
web values package-measured. None of the mutable pages provides an immutable source
release or formulation-effective date, and the supplied image contains no
nutrition panel. Fibre is preserved as the candidate interval `[0, 0.5)` g rather
than zero. Nutrition remains non-effective pending the exact package panel or a
separately ratified compatible-source rule.

### Co-op 10 Cheesy Singles

A barcode-only image supplies valid EAN-13 `5000128782661` and the visible
packaging code `AW CODE: C51236/1/15 0421 20788439`. The exact Central Co-op GTIN
page resolves the product as Co-op 10 Cheesy Singles, 200 g, containing ten 20 g
slices. “Co-op American cheese” is retained as the user's personal alias, not used
to replace the canonical product name or infer an American regulatory category.

The exact public page declares per 100 g: 247 kcal, 16 g fat, 8.2 g saturates,
10 g carbohydrate, 7.6 g sugars, fibre `<0.5 g`, 15 g protein and 1.99 g salt.
The salt value would derive 796 mg sodium. It also publishes a per-slice column:
49 kcal, 3.2 g fat, 1.6 g saturates, 2.0 g carbohydrate, 1.5 g sugars, fibre
`<0.5 g`, 3.0 g protein and 0.40 g salt.

The exact 20 g serving conversion exposes two legitimate representation details:

- scaling the per-100-g fibre interval gives `[0, 0.1)` g per slice, a tighter
  compatible interval than the separately printed `[0, 0.5)` g slice bound; and
- scaling 1.99 g salt gives 0.398 g salt and 159.2 mg sodium per slice, while the
  printed slice column rounds salt to 0.40 g.

Both declarations and the deterministic projections are retained; neither is
silently overwritten. Ingredients describe a processed slice containing 60%
vegetarian cheese, water, palm oil, milk-derived ingredients, modified starch,
flavouring, colours, lactic acid and emulsifying salts. Tricalcium phosphate in
that emulsifying-salt list does not by itself establish the contract's
`fortified_food` class because the page makes no calcium declaration or
fortification claim. As the supplied image contains no nutrition panel, all web
nutrition remains a non-effective candidate.

### Co-op Ripe and Ready Twin Pack Hass Avocados

A produce sticker supplies valid EAN-13 `5000128606387`, Peru origin, Class I,
packer code `M1799`, best-before text `21 SEP` without a printed year, and the
marking `NOT FOR EU`. The exact Central Co-op GTIN page resolves the product name
and proposes a two-avocado ripe-and-ready Hass pack.

The public page currently says origin South Africa. For this captured package,
that mutable seasonal-origin value is rejected and Peru remains authoritative.
The mismatch is retained rather than interpreted as a correction or silently
overwritten.

The page publishes per 100 g: 177 kcal, 17 g fat, 4.2 g saturates, 1.8 g
carbohydrate, sugars `<0.5 g`, 3.1 g fibre, 1.8 g protein, salt `<0.01 g` and
2.2 mg vitamin E. The bounds are preserved as `[0, 0.5)` g sugar and `[0, 0.01)`
g salt; `salt_to_sodium_v1` would produce `[0, 4)` mg sodium.

Nutrition remains non-effective. The page does not say whether its per-100-g basis
is edible flesh excluding skin and stone, and neither the sticker nor page gives a
net, edible or per-fruit mass. Twin-pack identity therefore cannot produce a
per-avocado or consumed nutrient amount.

The result is recorded in `user-supplied-package-label-result.json`. It
demonstrates that barcode identity resolution and nutrition resolution are
separate decisions even when the barcode match is strong.

### Co-op British Raspberries 150g

A produce label supplies valid EAN-13 `5000128915618`, 150 g net weight, Kent UK
origin, Lagorai variety, supplier Sean Charlton, supplier code `M150/SC/104`,
printed code `L1`, best-before text `20 Sep` without a printed year, and the
marking `Not for EU`. The exact Central Co-op GTIN page resolves the product as
Co-op British Raspberries 150g and confirms the pack size.

The public page currently says origin Spain. For this captured punnet, Kent UK
remains authoritative and Spain is retained only as incompatible seasonal
catalogue evidence. The page's British product name and Spain origin field are
themselves inconsistent, further preventing the mutable page from correcting the
package.

The same exact-GTIN page contains two incompatible per-100-g nutrition profiles.
One declares 170 kJ/40 kcal, 0.3 g fat, saturates `<0.1 g`, 4.6 g carbohydrate,
4.6 g sugars, 6.5 g fibre, 1.4 g protein and salt `<0.1 g`; it also supplies an
approximate 80 g/two-handful serving. The other declares 163 kJ/39 kcal, fat
`<0.5 g`, saturates `<0.1 g`, 6.1 g carbohydrate, 6.1 g sugars, 3.8 g fibre,
0.6 g protein and salt `<0.01 g`.

Those profiles are retained separately. The bounds are not converted to zero:
their salt values would respectively map through `salt_to_sodium_v1` to
`[0, 40)` mg and `[0, 4)` mg sodium per 100 g. No field-by-field merge, numerical
preference or whole-punnet projection is allowed. Although the exact package
quantity is known, effective nutrition still requires a matching panel or a
versioned source that identifies which profile applies; consumed quantity remains
a separate log fact.

The result is recorded in `user-supplied-package-label-result.json`. It extends
the conflict test beyond package-versus-page disagreement: one mutable exact-GTIN
record can itself contain multiple unresolved product versions.

### Co-op Irresistible Butter Basted Turkey Breast 120g

Two package crops supply valid EAN-13 `5000128599450`, AW code `C51560/2/1`,
three servings and a full nutrition panel at both per-100-g and per-slice (40 g)
bases. The exact Central Co-op GTIN page resolves the current public identity as
Co-op Irresistible Butter Basted Turkey Breast 120g: roasted, sliced turkey breast
with a preparation identity that must not be collapsed into generic raw turkey.

The photographed package panel is measured evidence. Per 100 g it declares
517 kJ/122 kcal, 1.0 g fat, 0.4 g saturates, zero carbohydrate, zero sugars,
fibre `<0.5 g`, 28 g protein and 0.62 g salt. Salt maps through
`salt_to_sodium_v1` to 248 mg sodium. Per 40 g slice it declares 207 kJ/49 kcal,
fat `<0.5 g`, 0.1 g saturates, zero carbohydrate, zero sugars, fibre `<0.5 g`,
11 g protein and 0.25 g salt, which maps to 100 mg sodium.

The direct source columns survive deterministic checking. Scaling the displayed
per-100-g column by 0.4 agrees after rounding for energy, fat, carbohydrate,
sugars, protein and salt. It would give a tighter fibre bound of `[0, 0.2)` g
instead of the separately printed `[0, 0.5)` g and 0.16 g saturates instead of
the printed 0.1 g. These are retained as source declarations and projections,
not silently made identical.

The current exact-GTIN page is materially different: per 100 g it declares
598 kJ/141 kcal, 1.3 g fat, 0.4 g saturates, carbohydrate `<0.5 g`, sugars
`<0.5 g`, fibre `<0.5 g`, 32 g protein and 0.50 g salt (200 mg derived sodium).
It also lists turkey, salted Jersey butter (4%), Cornish sea salt (1%) and
dextrose, says 105 g raw turkey is used per 100 g finished product, identifies
milk as an allergen and gives UK origin.

The public profile is retained as a separate possible formulation and rejected
for the captured package. It has neither an immutable release nor an effective
date, and the supplied crops omit the package use-by or lot date, so this evidence
does not claim which formulation came first. Any later dataset or model
re-resolution may create a new resolution version; it may not rewrite the
captured barcode, AW code, panel, source serving columns or the resolution
attached to an earlier log occurrence.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
the contract's product-reformulation and retrospective-re-resolution rules with
a directly measured package/public conflict.

### Co-op Specially Selected Asparagus Tips 100g

Two package crops supply valid EAN-13 `5000128946834`, 100 g net weight, Peru
origin, packer code `M244`, best-before text `22 SEP` without a printed year,
additional code `SS 2 10:08`, and a complete per-100-g nutrition panel. The
official Co-op page identifies a 100 g Specially Selected Asparagus Tips product;
a current Southern Co-op retail listing independently matches the Peru origin and
headline nutrition. Neither accessible page exposes the barcode, so this is not
counted as an exact public GTIN match.

The package panel is measured evidence. Per 100 g—and therefore per labelled
100 g pack quantity—it declares 119 kJ/28 kcal, 0.6 g fat, saturates `<0.1 g`,
2.0 g carbohydrate, 1.9 g sugars, 1.7 g fibre, 2.9 g protein, salt `<0.01 g`
and folic acid 175 mcg. Salt remains `[0, 0.01)` g and maps through
`salt_to_sodium_v1` to `[0, 4)` mg sodium; neither bound becomes zero.

The folic-acid unit glyph is visually ambiguous in the photograph. The same row
prints 88% RI, which against the UK adult 200 mcg folic-acid reference intake
identifies the intended value as 175 mcg, not 175 mg. The canonical mapping is
therefore `folate_b9: 175 mcg`, with the source image and this explicit unit
resolution retained rather than silently correcting or accepting the glyph.

The current retail summary agrees on 119 kJ/28 kcal, 0.6 g fat and 1.9 g sugars,
but displays saturates as 0.1 g and salt as 0.01 g without the package's
less-than qualifiers, and omits carbohydrate, fibre, protein and folate. It is
compatible but less precise and cannot overwrite the measured panel. The 100 g
pack basis enables an exact whole-pack projection if a log records the whole pack
as consumed; package quantity alone is not consumption evidence.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
bounded-value preservation, folic-acid-to-`folate_b9` mapping and explicit unit
resolution without upgrading product-family corroboration to a barcode match.

### Co-op Baby Spinach 100g candidate

Two package crops supply valid EAN-13 `5000129330328`, AW code `P51128/1/4`, and
a complete panel at per-100-g and per-cereal-bowl (80 g) bases. The supplied crops
do not show the front name, net weight, origin, date, or whether the leaves are
washed and ready to eat. Those decisive identity attributes remain unknown.

The user identifies the product as baby spinach. Secondary catalogue entries
identify Co-op Baby Spinach 100g or Mild & Delicate Baby Spinach and reproduce the
distinctive 15 kcal per 80 g cereal-bowl serving, but expose neither this barcode
nor an immutable formulation date. The identity and 100 g pack are therefore
strong candidates, not measured package facts or an exact public GTIN match.

The package panel is measured evidence. Per 100 g it declares 78 kJ/19 kcal,
0.6 g fat, saturates `<0.1 g`, carbohydrate `<0.5 g`, sugars `<0.5 g`, 1.0 g
fibre, 2.6 g protein and 0.08 g salt, which maps through `salt_to_sodium_v1` to
32 mg sodium. Per 80 g cereal bowl it declares 62 kJ/15 kcal, fat `<0.5 g`,
saturates `<0.1 g`, carbohydrate `<0.5 g`, sugars `<0.5 g`, 0.8 g fibre, 2.1 g
protein and 0.06 g salt, which maps to 24 mg sodium.

Scaling the displayed per-100-g column by 0.8 is compatible with the directly
printed serving values after rounding. It would give tighter bounds of
`[0, 0.08)` g saturates and `[0, 0.4)` g carbohydrate and sugars, while the
printed serving column retains `[0, 0.1)` g and `[0, 0.5)` g. Both source columns
and deterministic projections survive; neither overwrites the other. “Cereal
bowl” is a source serving definition, not a consumed occurrence.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
bounded serving projections, unknown preparation attributes and the rule that
compatible secondary product-family data cannot silently become exact identity.

### M&S Unwaxed Lemons

The package prints `M 0806 336 S`, not an EAN-13. Normalising its numeric product
component to `00806336` resolves the exact official M&S product code for M&S
Unwaxed Lemons. The repository preserves the original marking and identifies it
as an M&S retailer-code namespace rather than manufacturing a GTIN.

The package panel is measured evidence. Per 100 g it declares 79 kJ/19 kcal,
0.3 g fat, 0.1 g saturates, 3.2 g carbohydrate, 3.2 g sugars, zero fibre, 1.0 g
protein, salt `<0.01 g`, and vitamin C 58 mg (73% RI). Vitamin C maps directly to
`vitamin_c`; salt remains `[0, 0.01)` g and maps through `salt_to_sodium_v1` to
`[0, 4)` mg sodium.

The official M&S page reproduces the package nutrients and currently describes a
640 g product. Ocado uses the same M&S code, describes four seedless unwaxed
lemons, and also reproduces the label values. Neither count nor weight appears in
the supplied crops, so both current catalogue quantities remain candidates rather
than captured-package facts.

The M&S page additionally publishes sodium as 0.01 g (10 mg). That cannot coexist
with total salt below 0.01 g and conflicts with the deterministic `[0, 4)` mg
sodium bound. The direct package salt declaration wins; the official-page sodium
field is retained as conflicting provenance and rejected rather than silently
merged. Ocado omits that sodium field.

The per-100-g sources do not say whether their basis is whole fruit, flesh, juice
or another edible portion. Pack count, captured weight and edible quantity are
also absent. The catalogue therefore cannot derive nutrition for “one lemon” or
a consumed occurrence without a measured edible mass.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
namespaced non-GTIN identifiers, exact retailer-code resolution, vitamin mapping,
conflict rejection and edible-quantity boundaries.

### Co-op tomato, exact variant unresolved

Two package crops supply valid EAN-13 `5000128863186`, packaging code
`P53944/1/2`, and a complete per-100-g nutrition panel. The user identifies the
food as tomato, but the crops do not show a front name, variety, vine or organic
status, pack quantity, origin or date. No accessible public source was found for
the exact GTIN, so those identity attributes remain unknown.

The package panel is measured evidence. Per 100 g it declares 71 kJ/17 kcal,
0.1 g fat, saturates `<0.1 g`, 3.0 g carbohydrate, 3.0 g sugars, 1.0 g fibre,
0.5 g protein, salt `<0.1 g`, and vitamin C 17 mg (21.25% NRV). Vitamin C maps
directly to `vitamin_c`; salt remains `[0, 0.1)` g and maps through
`salt_to_sodium_v1` to `[0, 40)` mg sodium.

Public search found a Co-op Organic Vine Tomatoes page with a different GTIN,
`5000128721141`. It shares energy, carbohydrate, sugars and fibre, illustrating
how generic produce panels collide across products. It cannot resolve this
package: organic and vine identity are unevidenced, and it declares vitamin C
22 mg rather than 17 mg, fat `<0.5 g` rather than 0.1 g, and protein `<0.5 g`
rather than 0.5 g. The near match is retained as a negative control and rejected
for both identity and nutrition.

Without measured pack or edible quantity, no whole-pack or per-tomato nutrient
amount is derived. A similar macro profile is not a substitute for decisive
identity evidence.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
valid-but-unresolved barcode identity, exact micronutrient preservation and
rejection of a tempting different-GTIN generic-food match.

### Co-op whole milk, pack unresolved

Two package crops supply valid EAN-13 `5000129393828`, AW code `C54935/1/1`, a
per-100-g nutrition declaration and the statement `10 Servings`. The user
identifies the product as whole milk. The crops do not show the front name,
ingredients, pack mass or volume, serving size, origin, date, processing or
fortification declarations.

The package panel is measured evidence at its printed mass basis. Per 100 g it
declares 264 kJ/63 kcal, 3.5 g fat, 2.5 g saturates, 4.6 g carbohydrate, 4.6 g
sugars, zero fibre, 3.3 g protein and 0.04 g salt. Salt maps through
`salt_to_sodium_v1` to 16 mg sodium. The contract does not silently rename this
as per 100 mL or apply an assumed milk density.

No accessible public exact-GTIN record was found. A historical official Co-op
allergen catalogue confirms multiple British fresh whole-milk variants, including
1 pint/568 mL and 2 pints/1.136 L, but does not identify this barcode. A current
different-brand 1 L whole milk shares 63 kcal and 3.5 g fat but differs in basis,
saturates, carbohydrate, protein and salt; it is retained as a rejected category
near match, not used for identity or augmentation.

The ten-servings statement lacks a visible serving size. It therefore cannot
establish 1 L, 1 kg, ten 100-g portions, ten 100-mL portions or consumption.
Pasteurisation, homogenisation and fortification remain unknown, as do calcium
and every other undeclared canonical nutrient.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
drink classification, mass-versus-volume basis preservation, unknown serving
quantity and rejection of category-level micronutrient completion.

### Co-op wheat and rye sourdough, exact public identity unresolved

Two package crops supply valid EAN-13 `5000129399301`, AW code `B55033/1/1`,
approximately eight servings and a complete nutrition panel at per-100-g and
per-average-slice bases. The user identifies the product as wheat and rye
sourdough. The crops do not show the front name, ingredients, net weight,
fortification, origin, date, or whether the loaf was sold sliced.

The package panel is measured evidence. Per 100 g it declares 949 kJ/225 kcal,
1.3 g fat, 0.2 g saturates, 41 g carbohydrate, 2.2 g sugars, 7.8 g fibre, 8.3 g
protein and 0.71 g salt. Salt maps through `salt_to_sodium_v1` to 284 mg sodium.
Per average slice, printed as approximately 63 g, it declares 598 kJ/141 kcal,
0.8 g fat, 0.1 g saturates, 26 g carbohydrate, 1.4 g sugars, 4.9 g fibre, 5.2 g
protein and 0.45 g salt, which maps to 180 mg sodium.

Scaling the displayed per-100-g values by 0.63 agrees with the slice column after
display rounding for kJ and every macro. The kcal calculation is 141.75 while
the package prints 141. Both source columns and the deterministic projection are
retained; the calculated value does not silently correct the directly printed
one. Likewise, eight approximate 63 g slices suggest about 504 g but do not prove
an exact pack weight.

No indexed exact-GTIN product facts were found. A request to the expected Central
Co-op product URL returned an anti-bot shell rather than a product record, so it
does not establish a public identity or formulation. Ocado publishes a similarly
named 500 g wheat-and-rye sourdough, but it is a different retailer product with
approximately ten 45 g servings and materially different nutrition: 255 kcal,
3.3 g fat, 4.9 g fibre and 0.87 g salt per 100 g. Its fortified wheat flour,
18% wholemeal rye, rapeseed oil, soya flour and wheat gluten cannot be imported
into the captured product.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
approximate serving-basis preservation, source-versus-projection rounding and
rejection of a tempting same-name product match. Pack weight, exact slice mass,
consumed amount, ingredients, fortification and every undeclared canonical
nutrient remain unknown.

### M&S Danish mackerel fillets in olive oil

Two package crops supply the marking `M 0809 160 S`, the product description
“mackerel fillets in olive oil (26%),” ingredients, a bone warning, two servings
and a drained nutrition panel. The marking normalises to M&S product code
`00809160`; it is a namespaced retailer code, not a GTIN.

Current and historical public evidence resolves that exact code as M&S Danish
Mackerel Fillets in Olive Oil. The current retail listing gives 125 g net and
88 g drained weight, packed in Denmark with mackerel caught in the North East
Atlantic. An exact-code M&S market page identifies common mackerel (`Scomber
scombrus`), but the supplied crop itself says only mackerel, so the scientific
species remains public candidate evidence. The package lists mackerel, olive oil
and salt and says “may contain bones.” That warning leaves actual bone presence
and bone-excluded edible mass unknown; the product must not be silently
classified as boneless.

The package panel is measured evidence per 100 g **drained**: 1104 kJ/266 kcal,
19.9 g fat, 3.6 g saturates, 0.3 g carbohydrate, 0.1 g sugars, 0.4 g fibre,
21.2 g protein and 0.68 g salt. Salt maps through `salt_to_sodium_v1` to 272 mg
sodium. The drained basis cannot be applied to the gross 125 g can or to packing
oil that was discarded or consumed without an explicit log quantity.

The source serving is half a can, 44 g drained, and the can declares two
servings. Scaling by 0.44 gives 117.04 kcal, 8.756 g fat, 9.328 g protein,
0.2992 g salt and 119.68 mg sodium. These are deterministic projections, not
direct panel values. The panel directly prints only omega 3 for both bases:
2.0 g per 100 g and 0.9 g per half can. The projected 0.88 g is compatible after
rounding. Omega 3 remains a retained source fact outside the frozen 39-nutrient
catalogue and is not aliased to total polyunsaturated fat.

Public nutrition also supplies a conflict test. The exact-code M&S market page
agrees with the package's 0.68 g salt, while the current Ocado page reports
0.58 g. The package value remains effective for this captured version; the
retailer assertions stay separate and are neither averaged nor resolved by
last-write-wins.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
drained-versus-undrained semantics, packing-medium identity, possible-bone state,
non-GTIN retailer identity, noncanonical fatty-acid retention and explicit public
conflict handling. A consumed occurrence still requires the actual drained fish
quantity and whether any packing oil was consumed.

### Baymar Gourmet sardines in olive oil with chilli

Two package crops supply valid EAN-13 `8425930142231` and a multilingual
nutrition panel explicitly headed per 100 g **of product**. Exact official
manufacturer evidence resolves the product as Baymar reference `SARG004`, baby
sardines in olive oil with chilli pepper, containing 22–26 fish, with 120 g net
and 84 g drained weight. Exact-EAN retail evidence identifies `Sprattus sprattus`
at 70%, olive oil at 28.4%, salt and chilli pepper at 0.6%.

The package panel is measured evidence per 100 g product: 1040 kJ/251 kcal,
20 g fat, 4.3 g saturates, zero carbohydrate, zero sugars, 17 g protein and
1.5 g salt. Salt maps through `salt_to_sodium_v1` to 600 mg sodium. Fibre is not
printed and therefore remains unknown rather than zero, as do calcium, vitamin D,
omega-3 components and every other absent canonical nutrient.

This basis is intentionally different from the preceding mackerel case. Here the
profile is for product as sold, including its packing medium; it is not labelled
as drained. If a log explicitly records all 120 g of fish and oil as consumed,
scaling by 1.2 gives 301.2 kcal, 24 g fat, 20.4 g protein, 1.8 g salt and 720 mg
sodium. Applying the same profile to the 84 g drained fish is not permitted:
that would silently retain the wrong proportion of oil. Actual fish and oil
consumption remain separate log quantities.

Bone state also remains unresolved. An AECOC Baymar product-family entry describes
boneless sardines, but it gives neither this EAN nor the `SARG004` chilli reference
and appears to describe the plain-olive-oil sibling. It cannot make the captured
product boneless. Bone-in and boneless sardines require distinct identity or
version evidence; the 22–26-fish presentation is not enough to infer either.

A retailer page for exact reference `SARG004` reports 4.7 g saturates, conflicting
with the photographed 4.3 g. The package value remains effective for this evidence
version. The retailer assertion is retained separately rather than averaged or
selected by last-write-wins.

The result is recorded in `user-supplied-package-label-result.json`. Together with
the mackerel case, it exercises both directions of the drained-state boundary:
drained nutrition must not be applied to gross can weight, and oil-inclusive
nutrition must not be applied to drained fish weight.

### M&S Chopped Italian Tomatoes 400g

The previously unidentified package is M&S Chopped Italian Tomatoes. Its marking
`M 0821 964 S` normalises to M&S product code `00821964`; it is a namespaced
retailer identifier, not a GTIN. The current official M&S page resolves a 400 g
can produced in Foggia, Italy, containing Italian chopped tomatoes (65%), tomato
juice and citric acid.

The photographed panel is measured evidence per 100 g: 105 kJ/25 kcal, 0.2 g
fat, 0.1 g saturates, 3.9 g carbohydrate, 3.8 g sugars, 1.2 g fibre, 1.3 g
protein and 0.02 g salt. Salt maps through `salt_to_sodium_v1` to 8 mg sodium.
The current official UK page and an exact-code M&S market page reproduce that
profile and the ingredient identity.

If a log explicitly records all 400 g as consumed, deterministic scaling gives
100 kcal, 0.8 g fat, 15.6 g carbohydrate, 15.2 g sugars, 4.8 g fibre, 5.2 g
protein and 32 mg sodium. Product identity and pack size alone do not establish
that consumption.

An exact-code M&S Cyprus page carries a materially different profile: 20 kcal,
fat and saturates below 0.1 g, 2.7 g carbohydrate, 2.5 g sugars, 1.9 g fibre,
1.4 g protein and 0.10 g salt per 100 g. That may be a market variant,
reformulation or stale page, but no source provides an effective date. It remains
a separate candidate version and cannot overwrite or be merged into the measured
package.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
anonymous-package resolution through a retailer namespace, product-basis quantity
projection and exact-code cross-market conflict handling.

### Eat Wholesome Organic Black Beans

The photographed UPC-A `628110454485` is structurally valid and normalises to
GTIN-13 `0628110454485`. The user links it to Eat Wholesome Organic Black Beans,
but no accessible public page was found that exposes this exact UPC. The product
name and brand are therefore user-linked identity facts rather than facts visible
in the supplied crops or an exact public barcode resolution.

The photographed panel is measured evidence per 100 g drained: 425 kJ/101 kcal,
0.7 g fat, 0 g saturates, 13.1 g carbohydrate, 0 g sugars, 6.9 g fibre, 7.2 g
protein and 0.08 g salt. Salt maps through `salt_to_sodium_v1` to 32 mg sodium.
Neither net weight nor drained weight is visible.

The current same-name [Ocado product page](https://www.ocado.com/products/eat-wholesome-organic-black-beans/430403011)
describes a 400 g product containing 60% organic black beans and water, but its
published profile is materially different: 240 kJ/57 kcal, 0.6 g fat, 6.3 g
carbohydrate, 5.1 g fibre, 4.1 g protein and 0.05 g salt per 100 g. It does not
expose the photographed UPC. The public profile therefore remains a separate
candidate market, formulation, date or basis; it cannot overwrite or be merged
with the package panel.

No whole-can projection is made. The public 400 g gross weight is not a drained
weight, and multiplying it by the public 60% bean ingredient proportion would not
prove the captured package's drained edible quantity. A consumed quantity must
remain explicit rather than inferred.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
valid-but-publicly-unresolved barcode handling, explicit drained-state nutrition,
same-name public-version conflict and refusal to manufacture edible quantity.

### The Organic Protein Co Pure Unflavoured Organic Whey Protein

EAN-13 `0702403240297` is structurally valid and resolves exactly to The Organic
Protein Co Pure Unflavoured Organic Whey Protein Powder, 400 g. An exact-barcode
wholesale listing supplies the pack identity, ingredient as organic whey protein
concentrate from organic milk and milk allergen. The current
[manufacturer page](https://theorganicproteincompany.co.uk/products/organic-whey-protein)
confirms that this is concentrate rather than isolate or hydrolysate.

The photographed panel directly declares both per-100-g and per-25-g serving
values. Per 100 g it contains 1672 kJ/395 kcal, 4.1 g fat, 3.1 g saturates,
8.5 g carbohydrate, 4.4 g sugars, 5.4 g fibre, 79 g protein, 0.5 g salt,
637 mg calcium, 361 mg phosphorus and 2 mcg vitamin B12. Salt maps to 200 mg
sodium. The direct 25 g column declares 418 kJ/99 kcal, 19.6 g protein and its
other rounded serving values; it remains independent evidence rather than being
replaced by a quarter-scale calculation. In particular, its 0.1 g salt maps to
40 mg sodium, while quartering the rounded per-100-g salt gives 50 mg.

The package also declares 18 amino acids per 100 g. Isoleucine (5.03 g), leucine
(8.4 g) and valine (4.63 g) are marked as BCAA and sum to 18.06 g. These remain
measured source facts outside the frozen canonical nutrient catalogue; they are
not collapsed into total protein or silently added as new canonical nutrients.

The current official macro profile matches the package, as does phosphorus, but
the official page now reports 545 mg calcium per 100 g rather than the package's
637 mg. It also contains contradictory Q&A answers for BCAA and leucine amounts.
The captured package remains effective for this evidence version; the newer
calcium and inconsistent Q&A remain separate mutable public observations without
an effective formulation date.

The exact public 400 g identity permits a deterministic whole-pack projection
only if a food log explicitly records the whole pack. It does not establish that
one 25 g serving, sixteen servings or any amount was consumed.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
exact-GTIN food-powder resolution, independent serving-column rounding,
non-catalogue amino-acid retention and package-versus-current micronutrient drift.

### M&S Collection British Single Apiary Select Farm Honey

The marking `M 2916 1201 S` normalises to M&S product code `29161201`; it is a
namespaced retailer identifier, not a GTIN. The current
[official M&S page](https://www.marksandspencer.com/food/british-single-apiary-select-farm-honey/p/fdp60511170)
resolves that code exactly to British Single Apiary Select Farm Honey, 250 g.
M&S describes each jar as harvested from one apiary on one Select Farm. The
supplied crops show “British honey”; the single-apiary, Select Farm and 250 g
facts come from the exact-code public identity.

The photographed per-100-g panel declares 1306 kJ/307 kcal, less than 0.1 g fat,
less than 0.1 g saturates, 76.4 g carbohydrate, 76.4 g sugars, less than 0.5 g
fibre, 0.4 g protein and 0.03 g salt. Salt maps through `salt_to_sodium_v1` to
12 mg sodium. The current official page reproduces every value and bound. The
less-than values remain bounded observations rather than being converted to zero.

If a log explicitly records all 250 g as consumed, deterministic scaling gives
3265 kJ/767.5 kcal, 191 g carbohydrate, 191 g sugars, 1 g protein and 30 mg
sodium, while retaining fat and saturates below 0.25 g and fibre below 1.25 g.
Exact jar identity and size alone do not establish that any amount was consumed.

The infant warning and storage text are retained only as package provenance and
safety labelling. They are not instructions derived from the user's request.

The result is recorded in `user-supplied-package-label-result.json`. It exercises
exact retailer-namespace resolution, origin/apiary identity, bounded nutrient
preservation and quantity projection without inferred consumption.

## Public supplement-label observation

The user supplied five current supplement names and captured quantities. They
were treated as product-selection fixtures, not as evidence that a dose was
consumed: the screenshot is not committed, and the repository result retains no
frequency, schedule, health purpose or other regimen history. Public pages were
read manually without an account or any basket, order, subscription or review
action.

Four cases now have exact public product-identity matches. Anthony's matched the brand
and product family but not a confirmed variant, while the abbreviated `AG` liquid
entry had only a probable AG1 match. No case provided an immutable source release
or a formulation-effective date. Six public pages exposed numeric candidates as
accessible text, and four exact-product pages were conflict-free. Later
user-supplied Centrum, Solgar fish oil, AG and Boots psyllium package panels
provide evidence-scoped authority for their printed formulations but do not turn
the public pages into a reusable supplement catalogue.

| Case | Public evidence | Contract consequence |
| --- | --- | --- |
| Centrum Advance 50+ | A user-supplied panel declares 24 micronutrients per tablet. The current official ingredient PDF reproduces all photographed values. Ocado's table is malformed and incomplete, while a Haleon professional page gives thiamin as 1.65 mg rather than the package and official PDF's 1.7 mg. | The 24 photographed values are `measured` for this package evidence. Preserve RE/NE/alpha-TE and folic-acid qualifiers, reject the malformed retailer fields and retain the thiamin difference as separate public provenance. The barcode digits, front name, lot and tablet count remain uncaptured. |
| Solgar Triple Strength Omega-3 | A user-supplied panel gives valid UPC-A `033984020580` and declares 2800 mg cold-water fish-oil concentrate, 1008 mg EPA and 756 mg DHA per two softgels, sourced from anchovy, herring, mackerel and sardine and presented as ethyl esters. Exact-UPC official evidence identifies the 100-softgel product and corroborates equivalent one-softgel values. | Scale the direct two-softgel declaration by exactly 1/2 for the captured one-softgel quantity: 1400 mg fish-oil concentrate, 504 mg EPA and 378 mg DHA. Preserve fish species and ethyl-ester form. Fish oil, EPA and DHA remain outside the frozen 39 nutrients and must not be mapped to `fat_polyunsaturated`; directions do not create a regimen. |
| Momentous Zinc Picolinate | A user-supplied panel gives valid UPC-A `850030796172`, one capsule per serving, 60 servings and 15 mg zinc as zinc picolinate. The official page corroborates the amount and serving but uses US 136% Daily Value rather than the package's GB/EU 150% RI. | The package's `zinc: 15 mg` is `measured` per capsule. Picolinate remains compound identity/provenance, and the source-specific percentages are retained without treating them as an amount conflict. The opaque printed code is not guessed to be a lot or date. |
| Anthony's Psyllium Husk Powder | Public organic-variant page gives directions in teaspoons, while the captured quantity is 5 g; numeric nutrition is label-image-only. Exact variant is not established. | Retain 5 g as the captured quantity. Do not invent a teaspoon conversion or fibre amount; both exact variant and fibre remain unresolved. |
| AG D3+K2 liquid | Captured basis is one drop. A user-supplied panel declares a daily serving as six drops (0.15 mL), vitamin D 25 mcg and vitamin K 100 mcg per serving, with 200 servings per container. Ingredients identify vitamin D as cholecalciferol from lanolin, vitamin K as menaquinone-7, an MCT-oil carrier and tocopherol-rich extract. The probable public pages now return not found, and cached text incorrectly associated the same amounts with one drop. | The package values are `measured` at the printed six-drop basis. A one-drop projection uses the evidenced exact factor 1/6: vitamin D `25/6` mcg, vitamin K `100/6` mcg and volume 0.025 mL. Preserve and reject the incompatible cached candidate; barcode/lot and market variant remain to be linked. |
| Boots Good Gut / Wellthy Psyllium Husk Powder | A user-supplied panel directly declares 95 g psyllium husk and 82 g fibre per 100 g, and 3 g psyllium husk supplying 2.46 g fibre per 3.16 g serving. Distinctive wording and serving basis resolve the Boots product lineage; the current official page identifies a 100 g Wellthy product but claims 3 g soluble fibre per teaspoon. | Preserve the direct package component and fibre values. Psyllium remains supplement-component identity while fibre maps canonically. Do not turn approximate teaspoon directions into an intake event or let the current page's apparent component/fibre conflation overwrite 2.46 g. Front brand, barcode, net weight and date evidence remain uncaptured. |

The Centrum panel maps directly to the frozen catalogue at a one-tablet basis:
vitamins A, D, E, K and C; B1, B2, B3, B5, B6, B7, B9 and B12; calcium,
phosphorus, magnesium, iron, zinc, copper, manganese, selenium, chromium,
molybdenum and iodine. Vitamin A is 800 mcg RE with 50% as beta-carotene;
vitamin E is 18 mg alpha-TE; niacin is 24 mg NE; and folic acid maps to
`folate_b9` at 300 mcg while retaining its source form. Undeclared catalogue
nutrients remain unknown rather than zero.

The official Centrum ingredient PDF matches the panel, including vitamin C
120 mg, vitamin E 18 mg, copper 0.5 mg and thiamin 1.7 mg. The 1.65 mg thiamin
on the separate professional page may reflect rounding, an older formulation or
another publication convention; no source supplies an effective date, so the
contract records the difference without choosing a retrospective history.

The Momentous package supplies UPC-A `850030796172` (normalised GTIN-13
`0850030796172`) with a valid check digit. Its direct one-capsule declaration
requires no serving conversion: 15 mg maps to canonical `zinc`, while “as zinc
picolinate” survives as compound provenance. The visible `MMT-Z-60 160925` text
is retained as an opaque package code; it is not interpreted as a product version,
lot or date without issuer semantics.

The Solgar package supplies UPC-A `033984020580` (normalised GTIN-13
`0033984020580`) with a valid check digit. Its direct two-softgel declaration
supports an exact one-softgel projection for the previously captured quantity:
1400 mg cold-water fish-oil concentrate, 504 mg EPA and 378 mg DHA. These remain
supplement components outside the frozen catalogue rather than aliases for total
fat or polyunsaturated fat. The label's fish species and ethyl-ester qualifier
remain identity provenance.

These cases add five supplement-specific checks to the source contract:

- a saved product or schedule is not a confirmed consumed occurrence;
- dose form, compound identity and source serving basis survive nutrient mapping;
- a per-serving value is not converted to a captured tablet, capsule, softgel,
  powder mass or drop without explicit compatible conversion evidence;
- disappeared, image-only or internally inconsistent pages cannot establish a
  current measured value or a retrospective formulation history;
- label directions and safety wording remain source provenance, not a prescribed
  regimen or evidence that the user consumed a serving.

The result is recorded in `supplement-public-label-result.json`. The Centrum,
Solgar fish oil, Momentous zinc, AG and Boots psyllium panels' printed amounts are
evidence-scoped `measured` values; their raw images remain local-only and are
represented by SHA-256 descriptors. Public-page amounts remain separately
versioned corroboration or conflict evidence. This observation does not change
the Phase 1 source decision:
manual package evidence is authoritative, and CoFID remains limited to
user-selected generic-food augmentation.

## Open Food Facts: independent legacy-cohort result

[OFF API documentation](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/)
states that data is volunteer-contributed and gives no accuracy or completeness
assurance. Product and search reads are rate-limited; bulk export is recommended
for more than a few hundred products. The database is ODbL, individual database
contents use the Database Contents Licence, and images are CC BY-SA. OFF's
[local-cache guidance](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/creating-a-local-cache-of-open-food-facts-data/)
also makes clear that a cached database remains inside the ODbL boundary and that
there is no public real-time update stream.

Those properties could support a user-invoked **candidate suggestion**: barcode in,
possible identity and label facts out, followed by independent evidence and
confirmation. They do not justify Phase 1 reliance or canonical use. In particular:

- barcode hit is not exact variant, current formulation or complete identity;
- missing preparation, drained state, packing medium, fortification, basis or
  edible quantity must remain unknown;
- an OFF edit is not evidence that an earlier package was reformulated;
- OFF source snapshots and attribution must remain separable from CoFID, manual
  evidence and the app's own assertions; and
- canonical persistence of OFF-derived records needs an ODbL compliance design,
  including produced-work/database separation and share-alike obligations.

### Sampling frame and integrity limits

[Tesco Grocery 1.0](https://doi.org/10.1038/s41597-020-0397-7) is independent of
OFF and records products purchased in 411 Greater London Tesco stores during 2015.
Its product-category file is CC BY 4.0 and claims 67,296 distinct GTIN rows across
17 manually validated categories. It is useful as a dated legacy frame, not as a
current UK market census: it covers one retailer, one region, Clubcard purchases
and products from 2015.

The published CSV has an additional material defect. Of 67,296 rows, 59,649 GTINs
are rendered in lossy scientific notation and cannot be recovered exactly. The
remaining 7,647 exact-digit rows pass the GTIN check digit and were eligible. All
17 categories remained, but `poultry` had only one eligible identifier.

Before any OFF lookup, the analyzer selected three products per eligible category
by ascending SHA-256 of `(source release ID, category, normalized GTIN)`. This
created a frozen 49-item sample: three per category except the single eligible
`poultry` row. GTINs and raw API responses remain outside the repository; the
committed result contains redacted aggregates and hashes.

### Measured result

| Measure | Result | Interpretation |
| --- | ---: | --- |
| Barcode hits | 17 / 49 (34.7%) | Dated legacy survival/coverage only |
| Misses | 32 / 49 (65.3%) | A miss cannot distinguish absence, deletion or identifier history |
| Hits tagged for the UK | 9 / 17 (52.9%) | Country tagging is incomplete evidence, not market authority |
| Category-concordant hits | 15 / 17 (88.2%) | Broad 2015 category agrees with current OFF name/category evidence |
| Category contradictions | 1 / 17 (5.9%) | Current OFF record conflicts with the published 2015 category |
| Category indeterminate | 1 / 17 (5.9%) | Current record lacks enough or unambiguous category evidence |
| Independently adjudicable exact variants | 0 / 17 | Tesco file has no product name, variant or package snapshot |
| Independently adjudicable label freshness | 0 / 17 | No dated 2015 label facts are published |
| Independently adjudicable reformulations | 0 / 17 | Neither source provides a ground-truth formulation chain |

The zeroes in the final three rows mean **not adjudicable**, not that every hit was
wrong. They prevent an exact-variant or freshness claim. Treating OFF's own current
record as both prediction and ground truth would be circular.

Among the 17 hits, OFF returned product name for 17, brand for 15, quantity for 12,
packaging for 7, category tags for 13, serving size for 6, nutrition basis for 15
and ingredient text for 11. These are presence counts, not correctness results.
No returned normalized field establishes preparation, bone/skin state, drained
state, packing medium, fortification or edible quantity against independent
evidence.

Against the repository's 39 nutrient keys, the hits contained 115 numeric `_100g`
cells out of 663 possible (17.3%). Median completeness was 7/39, with a range of
0–20. Even these cells are OFF source assertions; without a label snapshot they
cannot be promoted to `measured` or treated as current.

### Decision

OFF is **rejected as a Phase 1 identity or nutrition-resolution dependency**. The
hit rate is limited in this dated cohort, category contradictions exist, decisive
identity is not structured sufficiently for the contract, and exact variant and
freshness cannot be independently verified. A later optional candidate-suggestion
evaluation may use `off-product-sample-template.json` with current local evidence,
but it is not a prerequisite for the manual Phase 1 stack and cannot silently
promote OFF values.

## Source, release and licence matrix

| Source | Versioned local persistence | Update / size | Rights observed | Decision |
| --- | --- | --- | --- | --- |
| GOV.UK CoFID 2021 workbook | Yes: freeze bytes, hash and derived row manifest | Static 4.63 MB workbook; page last updated 2021-03-19 | GOV.UK says its content is OGL unless otherwise stated; this publication has no visible contrary notice. Preserve Crown attribution and source/release details. This is a repository conclusion, not legal advice. | Admit for generic-food augmentation with ingest qualifications |
| [FN-NBRI CoFID API v2.2.0](https://fnnbri.quadram.ac.uk/developer-tools/) | Technically possible, contractual right not established | API key by contact; no public full-release size established | Developer page requires citation and displays CC BY-NC-SA 4.0 non-commercial/share-alike terms, but page layout does not unambiguously allocate every term between its two APIs | Exclude until written persistence/application/redistribution terms are clear |
| [FN-NBRI Food Labelling API v2.0.0](https://fnnbri.quadram.ac.uk/developer-tools/) | Not established | 2,886 foods; API key by contact | Same visible non-commercial/share-alike restriction and ambiguity | Exclude; no contact authorised |
| Open Food Facts | Bulk snapshots are technically available; exact compliance boundary needs design | Observed JSONL 13.01 GB and CSV 1.28 GB compressed; frequently regenerated; no public real-time change stream | ODbL database, Database Contents Licence contents, CC BY-SA images; attribution/share-alike apply | Reject as Phase 1 dependency; any later candidate-suggestion experiment remains non-canonical |
| USDA FoodData Central April 2026 | Yes; dated and historical downloads | Foundation JSON 459 KB compressed; branded JSON 195 MB; branded online/API updates monthly, downloads twice yearly | Public domain / CC0; attribution requested | Comparison only; regional and fortification mismatch blocks silent Phase 1 merge |
| Brandbank / GS1 / Nutritics and other commercial candidates | Unknown | Unknown until vendor-specific proposal | No rights inferred from marketing pages | Excluded pending separately authorised commercial evaluation |

The [GOV.UK terms](https://www.gov.uk/help/terms-conditions) establish the default
OGL position. The [USDA download page](https://fdc.nal.usda.gov/download-datasets/)
and [FoodData Central licensing statement](https://fdc.nal.usda.gov/api-guide/)
provide the current sizes, release cadence and CC0 position. These terms must be
rechecked at implementation and each source release.

## Unresolved commercial questions

No vendor was contacted and no answer is assumed. A later, separately authorised
evaluation must ask each candidate for:

1. UK GTIN and market coverage measured against a customer-supplied redacted
   cohort, including exact variant and reformulation history.
2. Rights to cache full records locally, keep immutable historical versions,
   derive canonical nutrient resolutions and retain them after termination.
3. Rights to redistribute source-derived fields inside user-owned JSON/Drive
   exports and backups, including attribution wording.
4. Stable product/release identifiers, corrections, effective dates, tombstones,
   change feeds and reproducible snapshot manifests.
5. Nutrition-field definitions, serving bases, bounds/rounding, ingredient and
   allergen scope, decisive identity attributes and provenance to label evidence.
6. API/bulk-delivery limits, offline rights, UK data residency/privacy terms,
   service levels, pricing and non-production evaluation fixtures.

Three non-commercial evidence questions also remain: obtain the Olympus,
Lancashire Farm and Co-op cheese package nutrition/ingredients and lot or
best-before panels, plus an avocado edible/net quantity, the raspberry nutrition
panel, the turkey ingredients/use-by or lot panel and the cottage-cheese use-by
or lot mark if formulation timing is needed; obtain the sourdough front,
ingredients, net-weight and date panels if its exact identity, fortification or
formulation timing is needed; obtain the mackerel best-before or lot mark if its
captured formulation must be placed in time; obtain the sardine best-before or
lot mark and exact-product bone declaration if its captured formulation or bone
state must be resolved; obtain the chopped-tomato best-before or lot mark if the
cross-market formulation difference must be placed in time; obtain the black-bean
front, net/drained-weight and best-before or lot panels if its exact identity,
quantity or formulation timing must be resolved; obtain the whey-protein front,
ingredient, net-weight and best-before or lot panels if package-visible identity,
organic certification or formulation timing is needed; obtain the psyllium front,
barcode, net-weight, complete ingredient/allergen and best-before or lot panels if
the captured branding, package version or formulation timing must be resolved;
obtain the fish-oil front, softgel-count, complete ingredients and best-before or
lot panels if package-visible identity or formulation timing must be resolved;
obtain the honey front, apiary/farm identifier and best-before or lot panels if
the captured apiary or formulation must be placed more precisely; obtain a
positive nutrient-fortified-food fixture; and decide in a separately ratified catalogue
change whether supplement components such as EPA and DHA should extend the frozen
39 nutrients. Until then they remain retained source facts, not aliases.

## Acceptance status

| #87 acceptance criterion | Result |
| --- | --- |
| Coverage measured reproducibly with denominators | **Met:** 17/49 hits in a reproducible, explicitly dated legacy cohort; exact variant/freshness adjudicability reported separately as 0/17; a separate 9/9 current-page pantry sample, six-case supplement edge sample and nineteen food-package-label cases exercise contract fields without being misreported as barcode coverage |
| OFF accepted or rejected for bounded identity role on evidence | **Met:** rejected as a Phase 1 dependency; optional future suggestion role remains non-canonical |
| CoFID suitability and nutrient/food-family gaps explicit | **Met** |
| Non-versionable sources excluded or restricted | **Met** |
| Phase 1 stack and unresolved commercial questions recorded | **Met** |

Issue #87 is locally complete and ready for a separate review/commit decision. Its
Phase 1 source stack is manual package evidence plus user-selected CoFID generic
augmentation, with explicit unknowns for all remaining nutrients. It has no OFF,
commercial-provider or USDA dependency.
