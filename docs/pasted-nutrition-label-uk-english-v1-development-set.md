# Pasted nutrition label, UK English v1: development set results (#371, P1)

Counts from phase P1 of [the UK English plan](pasted-nutrition-label-uk-english-v1.md): 24 real public UK label texts read with the current reader (parser v3, gate v2, checks v2, conversions v1) through the development-only harness (`Tests/FoodLabelTextCaptureTests/UKDevelopment/`), which admits `uk_nutrition_declaration` without changing the product's scope. Under plan section 6 this file holds counts and layout descriptions only: no label text, value, product name, page address or hash. Everything else stays in the private folder outside the repository.

**These are development figures, not an accuracy rate.** The expected values are the collecting agent's own transcription from each label's screenshot; the owner's check of them is outstanding. Every rule P2 adds will be shaped by these labels, so only the P4 fresh set measures the reader.

## Collection

| Count | Value |
| --- | ---: |
| Labels | 24 |
| Retailer pages (5 retailers) | 15 |
| Manufacturer pages | 5 |
| PDFs (foodservice specification sheets, one host, 2014 to 2015) | 4 |
| Candidates opened | 58 |

Labels by category: biscuits and crisps 4, frozen 3, cereal 2, milk and yoghurt 2, sauces 2, nuts and dried fruit 2, bread 2, instant noodles 2, soft drinks 2, ready meals 2, confectionery 1.

Skips by reason (34): `blocked` 13, `no_nutrition_table` 11, `other` 8 (withdrawn pages, pages that rendered empty, dead PDF links, a recipe guide), `duplicate` 1, `wrong_category` 1.

Sites used, by name (they are excluded from the P3 fresh set): retailers M&S, Aldi UK, Healthy Supplies, Abel & Cole, Amazon UK; manufacturers COOK, Tyrrells, Warburtons, Clearspring, Dorset Cereals; PDFs from NHS Supply Chain specification documents. Most large UK grocers (Tesco, Sainsbury's, Asda, Ocado, Morrisons, Waitrose, Iceland, Co-op and others) refused headless access and were skipped as `blocked`, never bypassed. The P3 protocol has to plan for that.

## Results

| Measure | Value |
| --- | ---: |
| Labels | 24 |
| Reached Confirm | 12 |
| Declined | 12 (50%) |
| Values checked | 141 |
| Wrong values, as scored | 17, in 7 tables |
| of which a wrong basis (one label) | 8, plus 1 calculated value |
| of which unrecognised rows the scorer could not match by label | 8, in 6 tables |
| Basis choices needed | 0 |
| Rows "Printed but not read" | 1 |
| Calculated vs printed discrepancies | 1 |
| Correction burden, mean / median | 0.750 / 1.0 |
| Share of tables needing any correction | 0.667 |

Declines by reason: `value_without_unit` 5, `count_mismatch` 4, `energy_without_unit` 1, `no_table` 1, `basis_state_not_supported` 1.

Inferred format: `uk_nutrition_declaration` 13, `us_nutrition_facts` 11. The 11 are all parser declines whose candidate has no header, so inference falls through to US; no label in the set is a US panel, and none is a non-UK English declaration (every site is a UK site). Decision 11 therefore has no evidence from this set either way.

## Root causes (from the private texts, described by shape only)

Examples marked *synthetic* are invented to show the shape; none is copied from a label.

1. **Wrong basis: a per 100 header read as per serving (1 label, 8 values and a calculated sodium).** The per 100 header used an abbreviated gram unit the header vocabulary does not know, and it bound as a per serving column, so every value in the table was stored under the wrong basis. This breaks the safety rule of reader v3 section 2 on the English path. It does not affect any shipped build (UK is outside the launch scope), and P2 must fix it first, with mutation cases for the common spellings of grams after `per 100` (abbreviated, plural, spelt out, and with or without a space). It also needs a check that no Taiwan bilingual header reaches the same path.
2. **Unit printed in the row label, bare numbers in the cells (6 labels; `value_without_unit`, `energy_without_unit`).** The energy or nutrient row carries its unit in the label, either after the name or in brackets, and the cells hold numbers only (*synthetic*: `Protein (g) | 5.0`). The commonest UK retailer layout in the set.
3. **Cells the row and column counts cannot line up (4 labels; `count_mismatch`).** Energy in kJ and kcal sharing one cell per column (*synthetic*: `1000kJ/240kcal`), the kJ and kcal values of one cell wrapped onto two lines, a second column header with no values under it, and a comparator separated from its number by a space.
4. **Lead lines glued to the first row (4 labels, all one retailer; scored wrong).** A title line joined to the first energy row, so the energy rows were not recognised; their values were bound to an unrecognised row whose label the scorer could not match. Energy then came only from conversions or not at all.
5. **Sub-row markers the vocabulary does not know (3 labels; scored wrong or unread).** An `of which` marker followed by a long dash (U+2014), a sub-row whose whole label is in brackets, a leading underscore before the marker, and a bare kcal continuation row under the kJ row.
6. **One row per nutrient with the basis inside the label (1 PDF; `no_table`).** Each line names the nutrient, its unit, the basis and the as-sold state in one label, followed by a single value.
7. **Prepared food (2 labels).** One header naming a prepared serving declined correctly. A header saying the values apply after following the preparation instructions did **not** match the basis-state markers; that label declined for another reason, but had it parsed it would have been stored as sold. This is the identity gap of plan section 2, so P2 needs identity mapping v2.

## What P2 takes from this

- Fix 1 before anything else, as a safety repair, with mutation cases.
- Causes 2 to 5 are the decline and burden work; 2 and 3 account for 10 of the 12 declines.
- Cause 7 confirms the need for `pasted-label-identity-v2` (plan section 2).
- The scorer matches an unrecognised row by its normalised label. Lead lines glued to a row, and markers it does not strip (a long dash, U+2014; a leading underscore; brackets around a sub-row), turned correct-looking bindings into "wrong" scores. The UK scorer of P3 needs its normalisation and marker rules written for UK labels before collection, without forgiving a real misbinding.

## Outstanding

- The owner's check of the 24 transcriptions against their screenshots.
- The synced-storage checklist item: the private folder `~/WHR-label-eval-private/uk-english-v1/` is outside every git checkout and outside synced storage (checked manually; the harness checks only the first).

Only counts and rules were added from the real-text sets; no text, value, product name or hash.
