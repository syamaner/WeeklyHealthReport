# Pasted nutrition label, UK English v1: P2a reader spec (#371)

Status: **revision 3, architecture gate PASS, 3 November 2026.** Revision 1 was gated PASS WITH CHANGES (16 findings, mapped in section 9); revision 2's re-gate the same day closed 12 and left five changes, applied here (section 9.1); the final re-check asked for one edit (G3 over every non-row line), applied, after which the gate passed. Phase P2 of [the UK English plan](pasted-nutrition-label-uk-english-v1.md), split in two PRs so that the reader lands without touching any pinned file:

- **P2a (this spec):** the UK reader (a new parsing target), its reader adapter, the identity mapping v2 and the development set re-run. No product behaviour changes; the product still declines every UK paste `layout_not_supported`.
- **P2b (next, before any P3 work):** the reader seam (the launch scope passed into `PastedLabelReader` and `PastedLabelConfirmation`) as the named re-pin of reader v3 section 12.1 (plan decision 8), limited to the seam files and recorded under "Re-pins after the freeze"; and `uk-row-aliases-v1`, or a recorded finding that it is not needed.

The split departs from "one PR per phase" in `AGENTS.md`. It was taken under the owner's delegation of 3 November 2026 and is reported to the owner in the P2a PR; P2a and P2b each get their own ledger row.

The evidence is the [P1 development set](pasted-nutrition-label-uk-english-v1-development-set.md): 12 of 24 declines, and one wrong basis (a per 100 header with a gram spelling the reader does not know, bound per serving). The gate found the same fallback on the shipped Taiwan path; #375 repaired it separately (section 8).

## 1. Responsibilities

| Piece | Layer and home | Does | Never does |
|---|---|---|---|
| `UKTextNormalisation` | New target `UKNutritionLabelParsing`, pure | Rewrites English lines into shapes parser v3 reads correctly, under the closed rules N1 to N4 (section 2) | Adds, drops or changes a digit run, decimal separator or comparator; touches non-English text |
| `UKReadingGuard` | Same target | Declines a candidate under the closed rules G1 to G3 (section 3) | Changes a candidate in any other way |
| `NutritionLabelTextParserUK` | Same target | Three entry points mirroring parser v3 (`parse`, `parse(assertedBases:)`, `unheadedShape`); each normalises the pasted text, calls parser v3's public API on the result, then runs the guard; `inputSHA256` is always the hash of the pasted text | Edits parser v3 or any `NutritionLabelParsing` file |
| `UKEnglishLabelTextReader` | `FoodLabelTextCapture`, new file | The `LabelTextReading` port: a text whose parser v3 language (`NutritionLabelTextParserV3().parse(pasted).language`, public) is `english` goes through the UK parser; every other text goes to the pinned `NutritionLabelTextReader`, whose result is returned unchanged. Records `nutrition-label-text-parser-uk-v1` in `LabelReading.Versions.parser` | Is wired at the composition root before P5 |
| `PastedLabelBasisStateV2` | `FoodLedgerApplication`, new unpinned file | v1's markers plus the closed UK list (section 4) | Widens v1; is read by the product `classify` before P5 |

**Version.** `nutrition-label-text-parser-uk-v1` is defined as normalisation rules N1 to N4 plus parser v3 plus guard rules G1 to G3. Any change to a rule or to the guard is a new parser version. There is no separate normaliser field in `LabelReading.Versions` (that file is pinned).

**Internal symbols.** Parser v3's vocabularies and helpers are internal to `NutritionLabelParsing`, so the UK target holds its own copies of what it needs: the header phrase pattern, the energy labels, the sub-row names and the unit tokens. Vocabulary parity tests (`@testable import NutritionLabelParsing`, tests only) assert each copy equals, or is a subset of, what parser v3 classifies.

**Adapter pipeline.** `NutritionLabelTextReader` fixes its parser, so the UK adapter repeats its gate, inference, checks and conversions steps, reusing its internal static mapping helpers from within `FoodLabelTextCapture`. The equality tests of section 6 (items 7 to 9) hold the two pipelines together.

**Boundaries.** `check-boundaries.sh` gains:

- (a) `check_imports UKNutritionLabelParsing '^(Foundation|NutritionLabelParsing)$'`;
- (b) `Sources/UKNutritionLabelParsing` and its test target among the paths allowed to import `NutritionLabelParsing`;
- (c) `UKNutritionLabelParsing` among `NutritionLabelParsing`'s allowed dependents in the Package.swift check;
- (d) `UKNutritionLabelParsing` importable only by `FoodLabelTextCapture`, its tests and its own tests, checked in sources and in Package.swift;
- (e) no library product, with a pbxproj check that no `productName = UKNutritionLabelParsing;` exists;
- (f) a self-test fixture for each new forbidden form.

## 2. Normalisation rules (closed list)

Applied only when the pasted text's language is `english`. Each line is checked against N4 (split) first; then each resulting line gets at most one of N1 to N3, in that order. A line no rule matches is passed through byte for byte. Each rule has a positive case that parser v3 declines or leaves unread before normalisation and reads correctly after (section 6, item 1); a shape parser v3 already reads is not rewritten.

- **N1 header unit spelling.** Case-insensitive, only on a line matching the copied header phrase pattern. A `(?<![\d.,])100` followed (with optional spaces) by a gram spelling (`gm`, `gms`, `gr`, `grs`, `gram`, `grams`, `gramme`, `grammes`) and then a non-letter or the line end becomes `100g`. A millilitre spelling (`mls`, `millilitre`, `millilitres`, `milliliter`, `milliliters`) becomes `100ml` in the same way. Development cause 1.
- **N2 unit in the row label.** Fires only when the whole line is a label ending in exactly one unit token from the closed list below, followed only by bare numbers. Each number may carry a comparator (`<`, `less than`). Separators are spaces, tabs and `|` only (`/` joins one cell's kJ and kcal on UK labels, so a line with `/` is never rewritten). No letter and no other unit token may stand after the first number. The unit is removed from the label and written after each number; any other line is left unchanged. Cause 2. The closed unit list:
  - bracketed forms parser v3's unit hint does not cover: `(KJ)`, `(Kj)`, `(Kcal)`, `(KCAL)`, `(kCal)`, `(μg)` (Greek mu);
  - bare forms: `g`, `mg`, `µg`, `μg`, `mcg`, `kJ`, `kj`, `KJ`, `Kj`, `kcal`, `Kcal`, `KCAL`, `kCal`.

  `cal` and `Cal` are excluded: a small calorie is a thousandth of a kilocalorie, and no development label needs them.
- **N3 sub-row markers.** `of which` followed by a long dash (U+2014), or by `are`, and a leading `_` before `of which`, become the plain `of which`. A sub-row wholly in brackets becomes `of which <name>` only when `<name>` is in the closed list `saturates`, `sugars`, `mono-unsaturates`, `polyunsaturates`, `polyols` or `starch`, and only when the nearest top-level row above is that name's parent. A unit, energy or basis word in brackets is never rewritten. Cause 5.
- **N4 a title glued to the first row.** A line that starts with a closed title phrase (`Typical values`, `Average values`, `Nutrition`, `Nutritional information`, `Average nutritional information`, case-insensitive) followed directly by a copied energy label is split into the title line and the row line. Cause 4.

**Dropped from revision 1:** the kJ and kcal pair cell rule. Parser v3 already reads `1000kJ/240kcal` as two values grouped by unit, so cause 3 is not that shape. Its real shapes (a wrapped cell, an empty second header column, a comparator with spaces) are probed first; a rule comes only in a later parser version, with its own positive case.

**Printed text (gate Q1, accepted with conditions).** Headers, labels and value cells in the candidate carry the normalised text. Conditions:

- `inputSHA256` is the pasted text's hash;
- normalisation is a pure function fixed by the parser version;
- a property test shows no rule changes a digit run, a decimal separator or a comparator;
- Developer tools can show the pasted and normalised text side by side (P2b, or P5 at the latest);
- the P5 manifest decision (plan decision 10) records that UK `printed_text` and `printed_label` mean "after normalisation".

## 3. Guard rules (closed list)

The guard only ever returns the candidate unchanged or a decline. It runs after parser v3 on every entry point.

- **G1 header basis.** Decline `uk_header_basis_unrecognised` when a header bound per serving contains a standalone `(?<![\d.,])100(?![\d.,])` outside its outermost brackets, or a bracketed 100 followed by anything other than `g` or `ml` (optional spaces allowed, so `Per serving (100 g)` passes). This covers `Per 100`, `Per 100  g` (split by two spaces), `Per 100` with the unit on the next line, `per 100 kcal`, `per 100 oz`, `per 100 pieces` and `per 100 portions`. `Per serving (100g)` stays per serving, which is numerically correct.
- **G2 conflicting units on a line.** Decline `uk_orphan_unit` on any line holding a value (value-only lines included) when:
  - (a) a unit token stands after the first value without a number of its own (`Energy (kJ) 1520 (kcal) 362`; a line `362 (kcal)` under `Energy (kJ) 1520`);
  - (b) the label holds more than one unit token (`Energy kJ (kcal) 1520 362`, `Energy (kJ) (kcal) 1520 362`);
  - (c) the label holds a unit token and a value carries a different unit other than `%` (`Energy (kJ) 1520 kcal 362`);
  - (d) the label holds a unit token and two numbers are joined by `/` (`Energy (kJ) 1520/362`).

  Before (a) to (d), the basis token `100g/ml` (as in `per 100g/ml`, one per 100 basis for a solid or a liquid) is read as `100g`; it is not two units. Found on the development re-run, where it declined two correctly read tables.

  "A number of its own" means exactly what parser v3's value pattern attaches: the guard tokenises with a copy of `PatternsV3.value`, covered by the vocabulary parity test. It is checked on the normalised lines, since the candidate does not keep them.
- **G3 identity on every line.** Decline `basis_state_not_supported` when an identity v2 marker appears on any line of the normalised text, before, inside or after the table. The UK target cannot tell a recognised row from other text without parser v3's internal classifier, so it checks every line, which only adds declines (a row label carrying a marker is itself suspect). This covers:
  - every segment of a header-phrase line, bound or not (`Per 30g serving  with 125ml milk`);
  - lead lines and wrapped header lines (`Typical values as prepared`, `with semi-skimmed milk`);
  - footnotes, marked or not (`*when prepared`, `Values are for the product as prepared`).

  This also declines on, for example, an ingredient list or product text pasted with the table; that is the accepted direction. A closed exemption (such as a line starting `Ingredients`) may come only as a later parser version, if the development re-run shows the burden is too high.

  The UK target cannot import `FoodLedgerApplication`, so G3 holds its own copy of the marker list. A parity test in `FoodLabelTextCaptureTests` asserts it equals `PastedLabelBasisStateV2`'s, so any change to identity v2 also changes the UK parser's version.

**Decline codes.** `uk_header_basis_unrecognised` and `uk_orphan_unit` have no `PastedLabelCodes` mapping, so until P5 they render as `unreadable_table`. That fallback is accepted for the development harness; P5 adds their copy keys.

## 4. Identity mapping v2 (`pasted-label-identity-v2`)

A header (its printed text and serving conversion) is not the food as sold when it carries any of:

- v1's markers (`prepared`, `drained`, and the Taiwan substrings);
- as whole words: `preparation`, `reconstituted`, `reconstitution`, `rehydrated`, `diluted`, `dilution`, `cooked`, `cooking`, `baked`, `grilled`, `fried`, `microwaved`, `heated`, `boiled`, `steamed`, `roasted`, `toasted`, `brewed`, `infused`, `soaked`, `poached`, `braised`, `barbecued`, `made`, `served`, `instructions`, `consumed`, and `with`;
- the symbol `+` followed by anything.

These are matched as whole words, case-insensitively, so `unprepared`, `undrained`, `uncooked` and `serving` do not match. False positives only add declines, so the list leans towards declining. The product's `classify` keeps v1 until P5; the development harness reads UK texts with v2. Its version string lives beside `PastedLabelIdentity.version` in a new unpinned file. No manifest records it before P5, so stored manifests are unaffected.

## 5. Invariants

- Never a wrong row, column, basis or unit (reader v3 section 2); markers are never zero; unknown is never zero.
- Every non-English text reads exactly as today, through the pinned reader.
- An English text no rule matches and the guard passes gives the same full `LabelReading` as `NutritionLabelTextReader`, apart from `versions.parser`.
- No new egress, no HealthKit change, no persisted format change; no UK manifest is stored before P5.
- `ReaderV3FreezeTests` stays green without edits.

## 6. Contract tests

1. **Per rule (N1 to N4).** Positive cases, each shown to be declined or left unread by parser v3 before normalisation. Cases that must stay unchanged: `Energy kJ 1520 / kcal 362`, `Salt (g) 0.1 Tr`, `Fat (g) 3.4 5%`, `(kcal) 362`, `(Fibre) 3g`, the reference intake footer `8400kJ / 2000kcal`, and Taiwan and bilingual lines.
2. **Normaliser property test,** over every fixture and mutation case:
   - the multiset of numbers and comparators is preserved;
   - unit tokens are preserved apart from N1's respelling and N2's copy of the label unit onto each number;
   - the output is byte-identical where no rule fires;
   - the language is unchanged.
3. **Guard cases.** Every G1 to G3 shape above declines. `per 100gm`, `per 100gms`, `per 100 grams`, `per 100 g` and `Per 100mls` bind per 100. `Per 30g serving` and `Per serving (100g)` stay per serving. The guard either returns its input or declines.
4. **Conflicting units.** Every G2 shape (a) to (d) declines, and none ever binds a value with another value's unit.
5. **Markers.** `Trace`, `Tr`, `-` and `nil` are never read as 0. `<0.5g` and `less than 0.5g` keep their comparator. `%RI` columns, bare-number reference intake cells and the reference intake footer never bind as amounts.
6. **Identity v2.**
   - Each new marker declines.
   - `unprepared`, `undrained`, `uncooked`, `as sold` and `serving` do not decline; every `with` and `+` form does.
   - The unbound header segment, lead line, wrapped line, marked footnote and unmarked trailing note cases of G3 decline.
   - G3's marker list equals `PastedLabelBasisStateV2`'s.
   - v2 equals v1 on every Taiwan fixture header.
7. **Routing parity.** Every `zh-Hant`, `mixed` and `unknown` fixture and frozen parity case gives a `LabelReading` equal to `NutritionLabelTextReader`'s.
8. **Unchanged English.** On every English fixture where no rule fires and the guard passes, the full `LabelReading` is equal apart from `versions.parser`. This covers ordinary, unheaded and asserted-bases reads.
9. **Existing suites.** Covered through tests 7 and 8 rather than by re-running each suite: every synthetic, unheaded, Taiwan probe and frozen parity fixture those suites use is read through both adapters in ordinary and both asserted-bases forms, and the readings must be equal (non-English) or equal apart from the parser version (English the rules leave unchanged).
10. **Vocabulary parity.** The UK copies match parser v3 (section 1), including the value pattern G2 tokenises with.
11. **Taiwan probe.** `TaiwanHeaderProbeTests` pins the shipped behaviour: since #375 these headers decline `unrecognised_unit`, and `per 100 g` still reads per 100 g.
12. **Boundaries.** `check-boundaries.sh` covers the new target, with the self-test fixtures of section 1.
13. **Freeze.** `ReaderV3FreezeTests` stays green unedited.

## 7. Development set re-run

Re-run the development set through the adapter with identity v2. The bar is **zero wrong values from a real misbinding**. Each remaining scorer label-match artefact is justified individually in the private results (the value equals the truth for its printed row, column, basis and unit, and is bound only to an unrecognised row). The repository receives only their count.

## 8. Out of scope

- The shipped Taiwan path's per serving fallback: repaired separately in #375 (a decline-only guard on the pinned reader, by owner decision), on which this PR is based.
- The seam re-pin and row aliases (P2b).
- Format inference, the gate, the checks and the conversions, which stay at their versions.

## 9. Gate findings map (revision 1)

1 N2 whole-line rule, section 2; 2 G2, section 3; 3 N3 closed list and rule order, section 2; 4 G1, section 3; 5 identity v2 widened and G3, sections 3 and 4; 6 public routing and copied vocabularies, section 1; 7 rules restricted to shapes parser v3 fails, revision 1's N3 dropped, section 2; 8 N1 detail, section 2; 9 three entry points, section 1; 10 version definition, section 1; 11 full-reading equality and both-adapter suites, section 6; 12 boundaries (a) to (f), section 1; 13 #375 and the probe, sections 6 and 8; 14 artefacts justified, section 7; 15 decline code fallback, section 3; 16 split recorded, status.

### 9.1 Re-gate of revision 2

1 `/` dropped from N2's separators, G2 (d); 2 N2 unit list closed, `cal` excluded; 3 G2 (a) to (d) with value-pattern parity; 4 G3 over every header segment, lead lines and footnotes, with marker-list parity; 5 identity v2 declines on any `with` and `+`, with the added words. Suggestion 1 adopted: N3's parent is the nearest top-level row above.
