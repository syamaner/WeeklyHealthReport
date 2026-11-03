# Pasted nutrition label, UK English v1: development set results (#371, P1)

Counts from phase P1 of [the UK English plan](pasted-nutrition-label-uk-english-v1.md): 24 real public UK label texts read with the current reader (parser v3, gate v2, checks v2, conversions v1) through the development-only harness (`Tests/FoodLabelTextCaptureTests/UKDevelopment/`), which admits `uk_nutrition_declaration` without changing the product's scope. Under plan section 6 this file holds counts and layout descriptions only: no label text, value, product name, page address or hash. Everything else stays in the private folder outside the repository.

**These are development figures, not an accuracy rate.** The expected values are the collecting agent's own transcription from each label's screenshot, checked by the owner against every screenshot on 3 November 2026 with no corrections. Every rule P2 adds will be shaped by these labels, so only the P4 fresh set measures the reader.

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

## Checks

- Owner check, 3 November 2026: all 24 transcriptions compared with their screenshots; none needed a correction, so the figures above stand.
- The synced-storage checklist item: the private folder `~/WHR-label-eval-private/uk-english-v1/` is outside every git checkout and outside synced storage (checked manually; the harness checks only the first).

## P2a re-run (UK reader, 3 November 2026)

The same 24 labels read through the P2a reader (`nutrition-label-text-parser-uk-v1`: normalisation N1 to N4, parser v3, guard G1 to G3) with identity mapping v2, via the development harness ([P2a spec](pasted-nutrition-label-uk-english-v1-p2.md)). Still development figures, not an accuracy rate.

| Measure | P1 | P2a |
| --- | ---: | ---: |
| Reached Confirm | 12 | 16 |
| Declined | 12 (50%) | 8 (33%) |
| Values checked | 141 | 181 |
| Wrong values from a real misbinding | 9 (one wrong basis) | **0** |
| Scored wrong but justified as scorer artefacts | 8 | 10, in 7 tables |
| Correction burden, mean / median | 0.750 / 1.0 | 0.688 / 1.0 |
| Share of tables needing any correction | 0.667 | 0.562 |

- The wrong basis of P1 cause 1 is gone: that header now binds per 100 g (N1), and G1 declines any other per serving header that names 100.
- Each of the 10 artefacts was checked individually in the private results: the value equals the transcription for its printed row, column, basis and unit, and is bound only to an unrecognised row. Their shapes: a title on its own line merged by parser v3 into the first energy label (4), an `of which` wrapped onto a line starting with a long dash (2), a bracketed sub-row whose value is also bracketed (2), and a `(kcal)` continuation row (2).
- Declines by reason: `basis_state_not_supported` 2, `count_mismatch` 2, `uk_orphan_unit` 2 (guard G2: a label naming kJ and kcal over one combined cell, and the one-row-per-nutrient PDF), `energy_without_unit` 1 (an energy row labelled `(cal)`, which N2 deliberately excludes), `value_without_unit` 1.
- Inferred format: `uk_nutrition_declaration` 16, `us_nutrition_facts` 8 (all parser declines with no header, as in P1).
- Left for P2b: energy rows labelled `Energy kJ` or `Energy kcal` whose cells also carry the unit read as unrecognised rows (row aliases), and the title merged across lines.

## P2b re-run (seam and UK parser v2, 3 November 2026)

The same 24 labels read through `PastedLabelReader` with the `.ukDevelopment` policy and the UK adapter, now `nutrition-label-text-parser-uk-v2` (P2a's rules plus N5, [P2b spec](pasted-nutrition-label-uk-english-v1-p2b.md)). The P2a figures above were under the retired v1.

| Measure | P2a | P2b |
| --- | ---: | ---: |
| Reached Confirm | 16 | 16 |
| Declined | 8 (33%) | 8 (33%) |
| Values checked | 181 | 182 |
| Wrong values from a real misbinding | 0 | **0** |
| Scored wrong but justified as scorer artefacts | 10, in 7 tables | 6, in 3 tables |
| Correction burden, mean / median | 0.688 / 1.0 | 0.375 / 0.0 |
| Share of tables needing any correction | 0.562 | 0.250 |
| Calculated vs printed discrepancies (reported, never gating) | 1 | 2 |

- N5 recognised the energy rows printed `Energy kJ` or `Energy kcal` with the unit repeated in their cells, which also ended the title merge across lines: the four title artefacts are gone.
- The six remaining artefacts are the shapes P2b left on purpose (a `(kcal)` continuation row, a bracketed sub-row with a bracketed value, and an `of which` wrapped onto a line starting with a long dash); each was checked in P2a and their values are unchanged.
- The two discrepancies are kcal calculated from kJ against the printed kcal, each differing by under 5 kcal (rounding on the label); they are reported, as reader v3 12.2.8 requires.
- Declines are unchanged by reason.

## P3 re-run (UK scorer, 3 November 2026)

The same reading as P2b (no reader change in P3), scored by the new UK scorer `UKFreshSet.score` ([P3 spec](pasted-nutrition-label-uk-english-v1-p3.md) section 3) through its development decoder, with the confirmation built under the same `.ukDevelopment` policy.

| Measure | P2b | P3 |
| --- | ---: | ---: |
| Reached Confirm | 16 | 16 |
| Declined | 8 (33%) | 8 (33%) |
| Values checked | 182 | 182 |
| Wrong values from a real misbinding | 0 | **0** |
| Scored wrong but justified as scorer artefacts | 6, in 3 tables | **0** |
| Correction burden, mean / median | 0.375 / 0.0 | 0.375 / 0.0 |
| Share of tables needing any correction | 0.250 | 0.250 |
| Calculated vs printed discrepancies (reported, never gating) | 2 | 2 |

- The six artefacts are now matched to their printed rows by the UK label rules (an `of which` wrapped onto a long dash, a bracketed sub-row cut at its bracket, a `(kcal)` continuation row), and each compares equal; no comparison rule changed.
- Panels: the P1 transcriptions predate the `panel` field, so all 24 count as `unknown`.

Only counts and rules were added from the real-text sets; no text, value, product name or hash.
