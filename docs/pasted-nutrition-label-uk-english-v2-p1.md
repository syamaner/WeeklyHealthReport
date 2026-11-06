# Pasted nutrition label, UK English v2: P1 rule spec (#371)

Status: **revision 3, architecture gate PASS WITH CHANGES applied, 6 November 2026.** Revision 1 was gated FAIL (4 blocking findings, 7 changes, 1 suggestion), all addressed in revision 2 and mapped in section 9. Revision 2's re-gate passed it with 7 changes and 1 suggestion, applied here (section 9.1); the gate asked for no further review before P2. Phase P1 of [the UK English v2 plan](pasted-nutrition-label-uk-english-v2.md), whose five owner decisions are made. It maps the P1 development set's remaining declines, defines the rules for changes 1 to 6 as `nutrition-label-text-parser-uk-v3` with identity `pasted-label-identity-v3`, and sets the tests P2 must pass. No production code is written until the gate passes.

This file holds counts, rule shapes and synthetic examples only. No label text, value, product name, address or hash from either development set is copied here.

## 1. Development data, re-checked

Both development sets were re-read at `main` (`ec9adc4`) through the harness reader on scratch copies, with a leave-one-line-out probe of each decline. The probe confirms the v2 plan's fresh-set causes and adds the P1 set.

**P1 set (24 labels, 16 read, 8 declined):**

| Label count | Cause | Shape (synthetic) | Today | In v2 |
|---:|---|---|---|---|
| 2 | C9, prepared state | `Typical values  as per prepared cup`, `as per preparation instructions` | `basis_state_not_supported` | Declined (decision 3) |
| 1 | C1, pack-count line | `150G PACK (4-5 SERVINGS PER PACK)` before the heading | `count_mismatch` | Read by S1 |
| 1 | C10, small-calorie unit | `Energy (cal)  182  664` | `energy_without_unit` | Declined: `cal` is a thousandth of a kcal, and v1 already excludes it from N2 |
| 1 | C11, cells split across lines | `Energy  1000kJ` / `240kcal  800kJ` / `192kcal`; two rows' labels on separate lines above stacked values | `count_mismatch` | Declined: pairing values to rows needs layout the text does not keep |
| 1 | C12, basis inside each row label, space-aligned | `Protein g per 100 g/ml (As Sold)        3.9` | `uk_orphan_unit` | Declined |
| 1 | C13, two bases headed, one column of values, footnote markers | `Fat M        10.0g` under `Per 100g      Per lolly` | `uk_orphan_unit` | Declined (correct: the second column has no values) |
| 1 | C14, a value printed without a unit | `Fat  0.2` | `value_without_unit` | Declined (correct: no unit is ever invented) |

So v2 changes 1 to 6 read at most 1 more P1 label. The P1 set is mostly the long tail; the fresh set holds the shapes v2 targets.

**Fresh set correction.** The probe shows that one of the three C4 labels has a header naming a prepared state in one compound word (synthetic: `(ovenbaked) Per 100g`). Identity v2 matches whole words, so `baked` does not match `ovenbaked`: once C4 is joined, this label would read as the food as sold. Rule I1 (section 4) closes that gap, and the label stays declined. The v2 plan's upper bound falls from 20 to 19 of 24 fresh labels with change 6.

## 2. Responsibilities

`nutrition-label-text-parser-uk-v3` keeps uk-v2's structure (normalise, then parser v3 through its public API, then guard) and adds a region stage before normalisation and a reporting stage after the guard.

| Piece | Layer and home | Does | Never does |
|---|---|---|---|
| `UKTableRegion` (new) | `UKNutritionLabelParsing`, pure | Sets lines and cells aside under the closed rules S1 to S5 (section 3) and returns the kept lines plus a set-aside list. Each entry names its rule, its line index in the folded text and, for a cell, its tab-cell index | Sets anything aside without a rule; changes any kept text except by removing whole tab cells under S4 and S5; reads values |
| `UKTextNormalisation` | Same target | uk-v2's N1 to N5, plus N6 and N7 (section 3), on the kept lines | Adds, drops or changes a digit run, decimal separator or comparator (unchanged invariant) |
| `UKReadingGuard` | Same target | uk-v2's G1 to G3, plus G4 (section 3); G3 also runs over the set-aside lines | Changes a candidate |
| `UKSetAsideReport` (new) | Same target | After the guard passes, appends one `row_not_read: uk_set_aside: <printed label>` warning to the candidate for each reported row S2 set aside. A reported row is a set-aside line after S2's title whose label starts with a letter and which holds at least one match of parser v3's value pattern; its printed label is the trimmed text before the first value. Footnotes, notes and blank lines with no value are not reported | Runs on a declined candidate; changes any other field |
| `NutritionLabelTextParserUK` | Same target | Language check, then region, normalise, parser v3, guard and report, on all three entry points; `version` becomes `nutrition-label-text-parser-uk-v3`; adds `setAside(_:)`, returning the set-aside list as a plain value type of the UK target | Edits parser v3 or any `NutritionLabelParsing` file |
| `UKEnglishLabelTextReader` | `FoodLabelTextCapture` | Unchanged routing; records the new parser version; maps the set-aside list into a framework-free type owned by `FoodLabelTextCapture` for the harness and, in P5, Developer tools | Is wired at the composition root before P5; exposes a UK target type |
| `PastedLabelBasisStateV3` (new) | `FoodLedgerApplication` | Identity `pasted-label-identity-v3`: identity v2's markers plus I1 (section 4) | Changes identity v2, which stays as pinned; is read by the product `classify` before P5 |
| `PastedLabelLaunchScope` | `FoodLedgerApplication` | Gains `Identity.v3`; `.ukDevelopment` moves to `.v3` | Changes `.v1`, `.v2` or the product scope |

**Language gating.** The language decision is made once, on the pasted text, with parser v3's public language check (`NutritionLabelTextParserV3().parse(pasted).language`), exactly as today. Only an `english` text goes through region, normalisation, guard and report. Every other text goes to the pinned reader unchanged. `inputSHA256` is always the hash of the pasted text. Today `UKTextNormalisation.lines` checks the language again on the text it is given, which after the region stage would be the kept text. P2 removes that inner check, so normalisation always follows the pasted text's decision and the two stages cannot disagree.

**Dependency direction.** Unchanged. The new types live in existing targets; the UK target still imports only `Foundation` and `NutritionLabelParsing`, which `check-boundaries.sh` already enforces, and only `FoodLabelTextCapture` may import it. No framework or persistence type crosses a port.

**Set-aside accounting.** Region rules are the first UK rules that drop digits. They may only because every dropped line or cell is in the set-aside list with its rule and position, and a property test holds the multiset of numbers and comparators across kept plus set-aside text equal to the pasted text's. The list lives beside `LabelReading`, not inside it (that file is pinned). Before P5 the harness writes it to a separate private file per label (`set-aside/<label>.json`), so the run output format and `UKFreshSet.runSchema` are unchanged; P5 shows it in Developer tools. On Confirm, rows set aside by S2 appear under "Printed but not read" with the reason `uk_set_aside`. That reason is a UK extension of reader v3 section 3.8's list. `LabelUnreadRow` already accepts any reason string, so no pinned file changes for it. S1 and S5 lines and S4 cells are not nutrient rows, so they are not listed there. S3's second table is an identical copy of rows that are read, so it is not listed either.

### 2.1 Version, freeze and re-pin

- **Versions.** Parser `nutrition-label-text-parser-uk-v3` is S1 to S5, N1 to N7, parser v3, G1 to G4 and the report stage. Identity `pasted-label-identity-v3` is identity v2 plus I1. Changing any rule, list or order is a new version. uk-v2 and the uk-v2 harness were never admitted or stored, so uk-v2 is retired, as uk-v1 was. Identity v2 stays in the code, unchanged and pinned, because P2b's launch scope names it.
- **`UKReaderFreezeTests`.** P2 changes it as one named re-pin, recorded under "Re-pins after the UK freeze" in the test and in this spec:
  - pin 1 (versions and codes): the parser version string, `pasted-label-identity-v3`, `.ukDevelopment.identity == .v3`, and the new decline codes `uk_rows_after_table` and `uk_region_inconsistent`;
  - pin 2 (vocabularies): identity v3's markers and I1's compound list added beside identity v2's, whose hash stays as it is; and every new closed table: S1's count forms and pack sizes, the closed table titles, S2's titles, S4's reference-intake names, the copied row vocabulary and marker list, N6's serving words and N7's step patterns;
  - pin 3 (file hashes): every file of `UKNutritionLabelParsing`, `UKEnglishLabelTextReader.swift`, `PastedLabelLaunchScope.swift`, the new `PastedLabelBasisStateV3.swift`, the new `FoodLabelTextCapture` set-aside type, and the harness and scorer files that write or read the set-aside file. `PastedLabelBasisStateV2.swift` keeps its hash.
- **`ReaderV3FreezeTests`** stays green unedited. P3 freezes uk-v3 for the v2 release check.

## 3. Rules (closed lists)

**Order.** Language check on the pasted text; S1 to S5 over the folded lines; N7; N1 to N6 in uk-v2's order with N6 last; parser v3; G1 to G4 (G4 first, so its code wins over parser codes and G1 to G3); report. Each rule has positive synthetic cases that uk-v2 declines and uk-v3 reads correctly, and negative cases that must decline or stay byte-identical.

**Line predicates.** The region rules run before normalisation, so they use closed predicates on folded lines, not parser v3's classifier:

- a *heading line* is the first line matching the copied header phrase pattern, or the first line with two or more tab cells whose first cell is a closed table title (`Typical values`, `Average values`, `Nutrition`, `Nutritional information`, `Average nutritional information`, case-insensitive, optional trailing colon or tab);
- a *row line* is a line starting (after spaces, `-`, `_` or `of which`) with a word from parser v3's full English row vocabulary, copied into `UKVocabulary` under the parity test (energy, fat, saturates, mono-unsaturates, polyunsaturates, carbohydrate, sugars, polyols, starch, fibre, protein, salt, sodium, and parser v3's other English row names);
- a *complete table* is a heading line followed, within the next 24 non-blank lines, by row lines for energy and fat in that order, whether each row's value is on its own line (C4) or not.

### Region rules

- **S1 pack and serving count lines (change 1; C1, C6).** A line is set aside when, after trimming spaces and tabs, it is only a count statement: a count phrase from the closed forms `Contains <n> servings`, `<n> servings per pack`, `Approximately <n> servings`, `(<n>-<m> SERVINGS PER PACK)` and `. Contains <n> Servings`, optionally with a pack size (`<n>G PACK`, `<n>g pack`, `<n>ml`) before it. The count phrase must be present: a line that is only a pack size stays kept. The line must stand before the heading line or after the last row line. S1 never sets `servings_per_pack` or the pack size; both stay unknown unless the table states them.
- **S2 a following vitamins and minerals table (change 3; C3).** After a complete table, a line whose whole text is a closed title (`Vitamins and Minerals`, `Vitamins & Minerals`, `Vitamins`, `Minerals`, case-insensitive, optional trailing colon) and every line after it are set aside. If any row line of parser v3's English row vocabulary (sodium included) follows the title, the reading declines `uk_rows_after_table`: a declared nutrient is never dropped. The vitamin and mineral rows themselves are nutrients too, so each is reported under "Printed but not read" (section 2).
- **S3 stacked duplicate tables (change 5; C7).** Two complete tables, each with a one-basis heading line, one per 100 and one per serving, under a repeated title. The bases are told apart on the folded text, before normalisation: the per 100 heading must contain `100g`, `100 g`, `100ml` or `100 ml` after `per` (case-insensitive), and the per serving heading must not contain a standalone 100. Headings that need N1 or N6 to be recognised, or two headings that cannot be told apart, do not trigger S3, and the reading declines as today. When every row label matches in order and every value matches, character for character, the per serving table, with its heading, its title and any serving size line, is set aside, whichever order the two are printed in. The per 100 table is kept. Identical values mean a 100 g serving or a misprint; either way no nutrition is lost. Any difference declines `multiple_complete_panels`, as today. S3 never merges two tables into one reading.
- **S4 reference-value column (change 2; C2).** **Departure from the v2 plan:** change 2 said such a column "binds to `reference_intake`". The spec sets it aside instead, because parser v3 would read `8400kJ / 2000kcal` or `70g` as an amount or a malformed bound. Removing it is safer, and a reference intake is not a value of the food. The rule: in a table whose heading line has a cell naming the reference intake itself (`RI*`, `your RI*`, `Reference Intake`, `Reference intake of an average adult`, case-insensitive), that heading cell and the same tab cell on every row line are set aside. S4 fires only when every row line has the same number of tab cells as the heading line, so the column is found by position. A kJ and kcal pair in one cell (`8400kJ / 2000kcal`) is one cell. Otherwise nothing is set aside, and the reading declines as today. A `%RI` column is not S4: parser v3 binds it to `reference_intake`, and it stays bound.
- **S5 a count cell in the heading's label column (change 4, part; C5).** When the heading line's first tab cell is a closed count phrase (the S1 forms) rather than a table title, that cell is set aside and replaced by an empty cell, so the line keeps its tab structure. This was N6's third case in revision 1; it drops a digit run, so it is a region rule.

### Normalisation rules

- **N6 a heading without "per" (change 4; C5).** On the heading line only, a whole tab cell that is exactly a weight or volume (`100 ml`, `100g`, `100 g`) becomes `Per 100 ml` or `Per 100g`. A cell that is a weight or volume plus a closed serving word (`250 ml serving`, `30g portion`, `1 bar (45g)`) becomes `Per` followed by the cell. An empty first cell left by S5 becomes `Typical values`. N6 only adds words; no digit, unit or comparator changes.
- **N7 one cell per line (change 6; C4).** Fires only on this whole shape, blank lines allowed between any two lines:
  1. optionally, one or more title lines of the closed table titles before the heading (the scripted copies' extra title, such as `Nutritional Values` and `Typical values per 100g`);
  2. a heading line of one title cell, with an optional empty second cell (`Typical values⇥`);
  3. exactly one further heading line, a single basis cell matching the copied header phrase pattern and not a `%RI` or reference intake cell;
  4. then pairs: a label line with no digit, then a value line that is one value cell (a number with optional comparator and unit, or a marker from parser v3's marker list);
  5. through to the end of the kept text.

  N7 rewrites the shape as one tabbed heading line and one tabbed row line per pair, and removes the blank lines. If anything breaks the pattern (two label lines in a row, two value lines in a row, a value line with two cells, a second basis line, any other line after step 3), N7 leaves the text unchanged and the reading declines as today. N7 never pairs beyond "the label and the next value line".

### Guard rule

- **G4 region and N7 consistency.** Runs first among the guard rules, so its code takes precedence. It declines `uk_region_inconsistent` when:
  - (a) a kept line still matches an S1 count statement (a count line inside the table);
  - (b) N7 fired, but parser v3's rows (read plus unread) do not equal the number of pairs N7 wrote.

  Revision 2's tab-count check after S4 and S5 is removed: S4 fires only when the counts already match and S5 keeps the tab structure, so it could never fire.

G3 (identity on every line) also runs over the set-aside lines, so a prepared-state note in any set-aside text still declines.

**Decline codes.** `uk_rows_after_table` and `uk_region_inconsistent` render as `unreadable_table` until P5, as uk-v1's UK codes do. Their copy keys come with P5's named re-pin of the product copy.

## 4. Identity v3 and rule I1

Identity v3 (`pasted-label-identity-v3`, `PastedLabelBasisStateV3`) is identity v2's word and substring markers, unchanged, plus I1.

**I1, compound cooking words.** A separate rule, not a whole-word match. It declines when a single letter run is exactly a closed prefix followed by a v2 cooking word. The prefixes are `oven`, `pan`, `air`, `deep`, `shallow` and `stir`. The cooking words are `baked`, `cooked`, `fried`, `grilled`, `roasted`, `toasted`, `microwaved`, `heated`, `boiled` and `steamed`. Examples: `ovenbaked`, `airfried`, `ovenmicrowaved`, `stirfried`. Hyphenated forms (`oven-baked`, `pan-fried`) already decline under identity v2, because the hyphen splits them into words and the second is a v2 cooking word; their tests are regression checks, not evidence for I1. The whole letter run must be exactly prefix plus cooking word, so `panettone`, `airy`, `deeply` and `unbaked` do not match, and `uncooked` stays as identity v2 leaves it. I1 only adds declines.

The UK target's G3 holds its own copy of identity v3's markers and I1 lists, kept equal by the parity test. The product's `classify` keeps identity v1 until P5.

## 5. Invariants

- Never a wrong row, column, basis or unit; markers are never zero; unknown is never zero. A count line, a reference-value cell or a set-aside table never binds as an amount.
- Region rules drop only what their list records, by line or tab cell. The numbers and comparators of kept plus set-aside text equal the pasted text's.
- Normalisation still never adds, drops or changes a digit run, decimal separator or comparator.
- A declared nutrient row is never dropped silently: S2 declines on a main nutrient after the title, and reports every set-aside vitamin or mineral row; S3 drops only an identical copy.
- Every non-English text reads exactly as today. An English text no new rule touches reads exactly as under uk-v2, apart from the parser version.
- No new egress, no HealthKit change, no persisted format change; no UK manifest is stored before P5.

## 6. Contract tests for P2

1. **Per rule (S1 to S5, N6, N7, G4, I1).** Positive synthetic cases that uk-v2 declines and uk-v3 reads correctly. For each, a case one step outside the rule that still declines or stays unchanged. This includes S1's pack-size-only line, which is kept.
2. **N7.**
   - The same table with and without blank lines reads identically.
   - A title line before the heading reads.
   - Marker values (`Trace`, `<0.1g`) read with their marker or comparator.
   - Each broken alternation declines, and so does a two-column C4 shape.
   - A `%RI` basis line in step 3 declines.
3. **Region accounting property.** Over every fixture and mutation case:
   - kept plus set-aside numbers and comparators equal the pasted text's, at cell level (S4 and S5 included);
   - each entry names one rule and its position;
   - a text no S rule matches has an empty list and is byte-identical after the region stage.
4. **Normaliser properties,** extended to N6 and N7: no digit run, decimal separator or comparator added or dropped.
5. **Bindings.**
   - S4 never binds a reference-value cell to an amount, and `%RI` keeps binding to `reference_intake`.
   - S1 leaves `servings_per_pack` unknown.
   - S3 keeps the per 100 table when per serving is printed first or second.
   - Two identical tables whose bases cannot be told apart before normalisation do not trigger S3.
6. **Rule interactions.**
   - C4 with an S1 count line before the heading.
   - C4 with an S2 vitamins section.
   - S2 followed by a late `Sodium` row, which declines `uk_rows_after_table`.
   - N4 (title glued to the first row) with S2.
   - S5 with N6.
   - A count line inside the table declines `uk_region_inconsistent`, not a parser code (G4 precedence).
7. **Unread rows.**
   - S2's vitamin and mineral rows appear in `unreadRows` with the reason `uk_set_aside`, and nothing from S1, S3, S4 or S5 does.
   - A set-aside footnote with no value is not listed; one with a value is.
   - The reason renders as the existing fallback copy ("Not read.") until P5.
8. **Declines kept.**
   - C9 to C14 synthetic shapes keep declining with today's codes.
   - I1: `ovenbaked`, `airfried` and `ovenmicrowaved` decline. Regression: `oven-baked` and `pan-fried` still decline under identity v2's words.
   - `panettone`, `airy`, `deeply`, `unbaked`, `uncooked` and `serving` do not.
9. **Language gating.** An English pasted text whose kept lines would not read as English is still normalised and reads under uk-v3, not the pinned reader. A non-English pasted text never reaches the region stage.
10. **Routing and unchanged English.** As uk-v2's tests 7 to 9: every non-English fixture reads equal to the pinned reader. Every English fixture no new rule touches reads equal to uk-v2, apart from `versions.parser`.
11. **Parity.** `UKVocabulary`'s row vocabulary, marker list and header phrase pattern match parser v3's. G3's identity v3 and I1 lists equal `PastedLabelBasisStateV3`'s.
12. **Freeze.** `UKReaderFreezeTests` re-pinned as section 2.1, with the re-pin recorded; `ReaderV3FreezeTests` unedited and green; Taiwan probe tests unchanged.
13. **Development re-run.** Both development sets, 48 labels, through uk-v3, reporting counts only. Bar: zero wrong values. The P2 PR reports reads and declines by code for each set.

## 7. Out of scope

- C9 prepared states (decision 3), C8 PDF interleave, and C10 to C14.
- Developer tools display of the set-aside list (P5 at the latest, with the pasted and normalised text).
- Copy keys for the two new decline codes and copy text for the `uk_set_aside` reason (P5).
- The v2 fresh-set protocol and freeze (P3).

## 8. Gate questions (revision 1), answered

1. **Set-aside list or decline?** Keep the list, at cell level, returned beside `LabelReading` (section 2).
2. **S3?** Keep the per 100 table, whichever is printed first, and set aside the per serving table with its serving size line (section 3).
3. **New decline codes?** `unreadable_table` until P5 (section 3).

## 9. Gate findings map (revision 1)

1. N6's count case became S5 (section 3).
2. Identity v3 as a new type and launch scope case; re-pin list with pins 1 to 3 (sections 2, 2.1 and 4).
3. Reporting stage with the `uk_set_aside` reason; vitamin and mineral rows reported (sections 2 and 3).
4. S4's departure from the plan stated, with cell-level entries and the "never" clause changed (sections 2 and 3).
5. G4 runs first and takes precedence; test 6 pins the code.
6. Closed line predicates; interaction tests (section 3, test 6).
7. Language gating on the pasted text (section 2, test 9).
8. N7: one basis line, parser v3's marker list, title lines, end of the kept text, read plus unread rows in G4 (c).
9. S2 uses parser v3's full English row vocabulary.
10. S1's count phrase is required; pack-size-only negative case (test 1).
11. The set-aside list reaches P5 through a `FoodLabelTextCapture` type (section 2).
12. I1 is a separate compound rule with negative cases (section 4, test 8).

### 9.1 Re-gate of revision 2

1. Inner language check removed in P2; test 9 rewritten (section 2).
2. Reported rows defined for `UKSetAsideReport`; footnote tests (section 2, test 7).
3. Pin 2 lists every new closed table (section 2.1).
4. Set-aside list in a separate private file; run schema unchanged; harness and scorer in pin 3 (sections 2 and 2.1).
5. G4's unreachable tab-count check removed (section 3).
6. S3 recognises bases before normalisation only; negative test (section 3, test 5).
7. `uk_set_aside` fallback copy tested; copy text in P5 (test 7, section 7).
8. Suggestion adopted: I1 covers single-word compounds only, hyphen cases are regressions, `micro` dropped (section 4).
</content>
</invoke>
