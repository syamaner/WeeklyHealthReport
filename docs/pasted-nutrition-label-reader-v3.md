# Pasted nutrition label reader v3 (#93)

Status: **draft for owner review, 20 October 2026. Nothing here is approved.** It proposes a versioned amendment to the reader behind the pasted nutrition label route of [pasted nutrition label v1](pasted-nutrition-label-v1.md) so that it reads the common real Taiwan paste layouts that parser v2 declines today. It follows the owner's decision of 20 October 2026, in session: improve the reader against a real-text development set, then run the release check once on a **fresh** set of at least 20 real labels the reader has never seen.

## 0. Why a separate document, and how it composes

This is a new document rather than an amendment section inside the v1 contract, for three reasons:

1. **v1 is approved and implemented.** Its text is cited by merged code and tests (PRs #267, #268, #271, #275). Amending it in place would mix approved and unapproved rules in one file, and its section numbers are referenced from code comments.
2. **The repository versions contracts by file** when the change is more than a clarification ([food confirmation v5](food-confirmation-contract-v5.md), [review manifest v2](generic-food-review-manifest-v2.md)). This change introduces a new parser version and, if decision 4 is accepted, a new manifest version.
3. **v1 remains the contract for everything this document does not change:** the journey, Confirm, the origins, the conversions, the arithmetic checks, privacy, the storage model and the release gate. This document only says what changes and why.

The file is named after the parser version it introduces (`nutrition-label-text-parser-v3`). When the owner approves it, v1 gains a one-line pointer in its status block and section 11; nothing else in v1 changes. If code later cites this document it is added to `CODE_READ_DOCS` then, not now.

## 1. Evidence and its limits

### 1.1 The development set

A development set of 24 public Taiwan labels was copied from retailer pages, manufacturer pages and importer specification PDFs on 20 October 2026 and read with the production reader at `fc3f260b` (parser v2, gate v2, launch scope `taiwan_nutrition_labelling`). The texts, screenshots and per-label results stay **outside the repository**; the repository holds only counts and layout descriptions.

| Measure | Count |
|---|---|
| Labels | 24 (retailer 15, manufacturer 5, PDF 4) |
| Reached Confirm | 7 |
| Wrong values in those 7 (agent pre-check; owner check outstanding) | 0 |
| Values matched / not read / not stated | 113 / 4 / 2 |
| Declined | 17: `multiple_panels` 8, `no_table` 6, `no_basis_header` 3 |

Recognised row names that parser v2 does not know, seen in accepted tables: the saturated and trans fat rows written with a trailing 酸, and the fibre row with the "voluntarily declared" (自願標示者) bracket. Each became an unrecognised row, so a printed value read as "Not read".

### 1.2 Root causes, checked with the CLI

The decline codes name where parser v2 stopped, not why. Running the current CLI (`NutritionLabelTextParse`, built at `fc3f260b`) on probe variants of the private texts, held in the scratchpad only, gave:

| Probe | Result |
|---|---|
| Label 16 as pasted | `multiple_panels` |
| Label 16 with only the pack line's wording variant (本包裝**包**含) replaced by the known form | read in full: 8 rows, 16 cells, no warnings |
| Label 17 (bilingual) as pasted | `multiple_panels` |
| Label 17 with the bilingual title reduced to the Chinese title | `value_without_unit` (the bracketed English unit beside the Chinese unit) |
| Label 21 (PDF) with its split serving lines joined | `count_mismatch` (row labels out of order, below) |
| Label 03 (accepted) | 7 cells, two `unrecognised_row` warnings for the 酸 forms |

So `multiple_panels` is mostly **not** two panels. In seven of its eight cases it is a line before the table that parser v2 does not recognise (a decorated title, a split serving line, a pack-line variant), which starts the row section early, so the real column header that follows is taken for a second panel. Only label 07 really has two panels.

### 1.3 Limits

- **The development set is now development evidence.** Every rule below was shaped by looking at these 24 texts, so the dev-set figures in section 7 are not an accuracy rate. Only the fresh release set (section 7.4) measures the reader.
- **24 labels is small.** The layouts are from a handful of sites; a site template accounts for several labels each (one retailer's one-line layout for three, one importer's PDF export for three).
- **Expected values are the agent's own transcription**; the owner's value check of the development set is outstanding.

## 2. Principles carried over unchanged

From v1 section 1.1 and the repository rules: the reader pre-fills as much as it safely can, under the plain disclaimer; the user validates on Confirm and can correct any value; every exception is visible on its row; it is not binary. Unknown is never zero. Nothing saves except Log. One addition is made explicit here, because several proposals depend on it:

**The safety rule of v3.** The reader may leave a value unread, a row unread or the whole table declined. It may **never** bind a value to the wrong row, column, basis or unit. Where binding is in doubt, the cell is not read and Confirm says so. Every proposal below is judged against this rule first, and decline rate second.

**Nothing printed vanishes.** A row the reader saw but could not bind (section 3.8) is listed on Confirm under "Printed but not read" with its printed text, beside the existing "Read but not used" list, and its mandatory row (if any) carries the existing G3 or G4 flag.

## 3. Proposals per decline class

Each subsection gives the real layout (described, not quoted), whether it can be read without risking a wrong value, the proposed rule, residual risks, and what changes: **parser only** (new parser behaviour; the manifest shape, corrections and stored versions keep their format) or **persisted** (a manifest field, a record or a version string that stored data carries).

### 3.1 Lines before the table (cause of most `multiple_panels` and some `no_basis_header`)

**Layouts seen.**

- Titles with decoration: a leading symbol (★, ◎, ▲), square brackets (【】), equals-sign rules, or the Chinese title followed by an English one, or by a bracket naming the energy unit.
- Serving size variants: the serving label with a digit instead of 一 (每1份量); the serving label alone on its line with the quantity on the next non-empty line (PDF export); the serving size and the pack count on one line.
- Pack count variants: 本包裝**包**含 N 份; 本包裝 N 份 without 含; the pack label alone on its line with "N份" on the next.
- Decorative row prefixes: `>>`, `•`, `▲`, `●`, used as indentation or bullets.
- Rule lines of `=`, `-` or `─` only.

**Safe to read?** Yes. None of these carries a value that could be bound to a row. The risk is only in recognising them too widely.

**Rule (parser v3).**

1. A title line is the title pattern after removing, at either end, a closed set of decoration characters (★ ☆ ◎ ● ▲ ■ ◆ 【 】 [ ] = and spaces) and, after the Chinese title, either an English title from the existing title words or one bracketed group. A title line never carries a value.
2. A rule line (only `=`, `-`, `─`, `_`, `*` and spaces) is skipped.
3. Serving label: `每[一1]?份量`. When the label stands alone, the next non-empty line is joined to it only if that line is a serving quantity and nothing else; otherwise the serving size is not read.
4. Pack line: `本包裝(包)?含?` followed by an optional 約 and a number and 份. When the pack label stands alone, the same one-line join rule applies. When the serving line also contains a pack phrase after its quantity, the pack count is read from that phrase.
5. A closed set of leading row markers (`>>`, `>`, `•`, `·`, `▲`, `●`, `-` and `*` only when followed by a Han character) is removed from a row label before classification and counts as indentation.
6. A printed pack count of zero is read as printed, never used for the whole-pack option, and shown with "Printed as 0, so whole pack is not offered." (one PDF in the set prints 0 份).

**Residual risks.** A product name line in brackets before the title could be taken as decoration; it carries no value, so the worst case is a lost heading. Rule 3 could join a serving label to a quantity that belongs to something else; the join is only to the very next non-empty line and only when that line is nothing but a quantity.

**Changes.** Parser only, **with one persisted consequence:** `pasted-label-serving-v2` derives the serving-size segment from a pinned copy of parser v2's serving-size grammar (v1 section 6.3). A serving line read under rule 3 or 4 would not match that copy, so servings would silently not be offered. Section 5.4 proposes `pasted-label-serving-v3`, a copy pinned to parser v3, chosen by the manifest's parser version.

### 3.2 One value per line (labels 16, 21, 22, 23; `multiple_panels`)

**Layout.** Each row label, then each column's value, every item on its own line, usually from a PDF's text layer or a retailer page built from a grid of cells. With the line-before-table fixes (3.1), label 16 already reads in full: parser v2's value-only-line attachment handles the shape. The three PDFs add a harder problem: **their text layer puts the last one or two row labels after their values** (for example the values of the last two rows, then both labels), so reading in order binds the wrong numbers to the wrong rows, or overflows a row.

**Safe to read?** Partly. Rows before the first irregularity are bound in a regular sequence and can be read. From the first irregularity onwards, order is no longer evidence of binding.

**Rule (parser v3, "stacked layout").** A table is stacked when its row labels stand on lines with no values and its values stand on lines with no label. In a stacked table:

1. The expected sequence is strictly: a label line, then exactly as many value lines as there are columns (amount columns plus any reference-intake column), then the next label line.
2. At the **first deviation** (a label followed directly by another label, a row with more or fewer values than columns, values after the last label, or a label at the end with no values), that row and **every row after it** are not read. Their labels and values go to "Printed but not read".
3. Rows before the first deviation are read as normal, under the Taiwan unit rule (3.9).

**Residual risks.** A text layer could swap two labels while keeping the regular sequence. The Taiwan unit rule (3.9) catches any swap between energy, sodium and the gram rows; a swap between two gram rows (for example protein and fat) is not caught by structure and is only partly caught by the existing energy and sub-row checks, which warn and never block. This is the main residual risk of v3 and is the focus of the mutation tests (section 7.2).

**Changes.** Parser only (new warnings in the candidate, which the manifest already stores as strings).

### 3.3 Value columns with no basis header (labels 05, 09, 10; `no_basis_header`)

**Layout.** The Taiwan serving lines, then rows with one or two value columns and no 每份 or 每100公克 heading at all; the heading row was an image or a merged cell that did not copy. The single-column cases print values whose size fits a serving; the two-column case prints the official template's order.

**Safe to read?** The rows and values bind cleanly; only the basis is unknown. Guessing the basis is exactly the error that must never happen silently (a per-serving column stored as per 100 g is wrong by the factor serving size / 100 on every value). So the reader must not choose. **The user can:** the label in their hand, or the product page, says what the column is.

**Proposal: an assisted basis choice instead of a decline.**

1. Parser v3 reads such a table and marks each amount column as "basis not printed". A `%` column is still recognised by its unit as the reference-intake column.
2. Before Confirm, a short sheet asks: "These values have no column heading. What are they for?" with **Per serving (printed serving size, for example 25 g)**, **Per 100 g**, **Per 100 ml**, and **I'm not sure**. For two amount columns it offers the official template's arrangements only: "Per serving, then per 100 g" and "Per serving, then per 100 ml"; any other arrangement is not offered. No option is preselected. "I'm not sure" returns to the label text screen with the text kept and a link to Search.
3. Per serving is offered only when a serving size was read (in grams or millilitres); otherwise only the per 100 options are offered, and "Per serving" says why it is missing.
4. The choice is recorded in the manifest (section 5.3) and shown on Confirm as the basis line "Per 100 g · Chosen by you", with **Change**. Changing it rebuilds the reading and, if the user has corrected or entered anything, asks first, as **Read again** does today.
5. Optional, decision 5: a **basis plausibility warning** beside an option that would imply more than 100 g of protein, fat and carbohydrate per 100 g, or more than 900 kcal per 100 g, beyond a stated tolerance. It is a warning, never a block and never a "checked" mark; a pass shows nothing.

**Why before Confirm and not as a Confirm requirement.** The stored column's basis decides the resolution's basis, the servings policy and the identity's `servingBasis`, so Confirm cannot be built without it. A sheet before Confirm adds no `FoodLogRequirement` and leaves `food_confirmation_v5` untouched. The journey still ends on the shared Confirm screen with one Log action.

**Residual risks.** The user can choose wrongly. That is a user assertion shown with its origin, like any correction, and the plausibility warning catches only implausible choices. A single column per serving and per 100 g can be equally plausible; the sheet must not imply that one answer is likely.

**Changes. Persisted:** a new manifest field for the choice, and therefore a new manifest version (section 5.3). The candidate keeps its schema: after the choice, the adapter re-runs parser v3 on the same text with the chosen bases as an input, so the stored candidate has ordinary bases and an empty printed header text, and gate v2 runs unchanged.

### 3.4 Whole table on one line (labels 06, 08, 12, 13, 14, 19; `no_table`, and `multiple_panels` for 19)

**Layouts seen.**

- A basis phrase, a dash, then `row value unit` items separated by `/` (one column).
- Serving lines, then `每份` stuck to the first row, items separated by `,` or `、`, with sub-rows inside brackets after their parent and separated by `/` inside the bracket (one column; also the single-sentence label 19, ending with `。`).
- Serving lines, a header `每份 / 每100毫升`, then rows whose two values are separated by ` / `.
- Serving lines, a header (`項目 每份 每100毫升`), then rows `name value unit value unit` separated only by spaces (three labels from one retailer).

Every case is a table flattened by the page's copy behaviour. The site templates are regular.

**Safe to read?** Yes, when the **segmentation** into rows is unambiguous. The row labels are short closed-vocabulary Han runs and every value carries a Chinese unit, so the line can be tokenised into label tokens and value tokens with no guessing. It is not safe when a label is unknown and the value count around it is irregular, or when a number is malformed.

**Rule (parser v3, "flattened line").** A line is treated as a flattened table only when it contains at least three recognised row labels from the alias table (section 4) each followed by a value with a unit. Then:

1. Tokenise into: serving and pack phrases (rules of 3.1), basis phrases, label tokens (maximal Han runs that are not units, after removing separators), and value tokens (number plus unit, with the existing comparator forms).
2. A value token must be delimited: what follows its unit is a separator (space, `/`, `,`, `、`, `，`, `；`, `(`, `)`, `。`), a label token or the end. A number with two decimal points, or two values with no separator between them, is **malformed**.
3. **Segmentation** is accepted only if every label token is followed by exactly N well-formed or malformed value tokens (N = the number of amount columns, plus the reference column if printed) before the next label token. If any label token is followed by a different number of value tokens, the line is declined `flattened_table_ambiguous` (new code, copy as `count_mismatch`).
4. Within an accepted segmentation, a row with any malformed value is **not read** (both columns) and goes to "Printed but not read". Other rows read normally.
5. A row inside brackets after a parent row is that parent's sub-row; it is classified by the alias table, never by position.
6. The basis comes from a basis phrase before the first row (header or a prefix stuck to the first label, like `每份`), never from a later position. Without one, section 3.3 applies.

**Residual risks.** An unknown nutrient between known ones with the right value count is read as an unrecognised row (read but not used), which is correct. A site that prints a value without a unit in a flattened line would make segmentation fail and decline, which is safe. A flattened line that is really two panels (two basis phrases with different row sets) declines `multiple_panels`.

**Changes.** Parser only, plus one new decline code with copy (the renderer's code-to-copy test, v1 test 27, enumerates it).

### 3.5 Basis printed only inside the energy line (label 20; `no_table`)

**Layout.** Multi-line, one column, no header line; the basis is a bracket after the energy value (per 100 ml), and sub-rows carry a `>>` marker.

**Safe to read?** Yes, under a narrow rule.

**Rule (parser v3).** When there is no header line, the table has exactly one amount column, and the **first row** carries exactly one bracketed basis phrase that `basis(of:)` recognises, that phrase becomes the column's header (printed text: the bracket as printed). A basis phrase on any other row, or more than one, declines `multiple_panels` as now.

**Residual risks.** A label that states per 100 ml for energy but per serving for the rest would be misread; this is not a layout seen, and the energy and sub-row checks would usually warn. Accepted as low.

**Changes.** Parser only.

### 3.6 Bilingual Chinese and English tables (label 17; `multiple_panels`)

**Layout.** The official Taiwan template with an English gloss after each Chinese row label (for example 脂肪 followed by "Total Fat"), a bilingual title and header, bilingual serving lines (one with an English typo), and every value printed with its unit twice: a bracketed English unit and the Chinese unit.

**Safe to read?** Yes, by reading the Chinese and using the English only as a cross-check.

**Rule (parser v3).**

1. Language: a text whose rows all start with a recognised Chinese row label is `zh-Hant` even if it contains Latin words, provided every Latin word sits either in a row's gloss, in the title, header or serving lines, or in a bracket after a recognised Chinese phrase.
2. The Chinese label classifies the row. If the English gloss classifies to a **different** nutrient under the existing English row table, the row is not read (a conflicting gloss is evidence the paste is misaligned). An unknown gloss is ignored.
3. A value printed as number, bracketed English unit, Chinese unit is one value only when both units have the same canonical unit; otherwise the row is not read.
4. Serving and pack lines read the Chinese phrase; an English bracket after it is ignored for the number, **except** that "about" (or 約) in either language makes the pack count approximate. This is the conservative side: whole pack is then not offered.
5. Format inference: such a text is `taiwan_nutrition_labelling`, never UK or US, so the US "Nutrition Facts" words in the title do not route it to `layout_not_supported`.

**Residual risks.** English-only rows inside a Chinese table (not seen) stay unrecognised. A bilingual label from a different market (for example a Hong Kong layout) would now infer as Taiwan; the Taiwan mandatory-row flags and the unit rule (3.9) still apply, and the release check should include at least one such case if one can be found.

**Changes.** Parser only (language and format inference are in the parser and the gate's inference, which reads the candidate's language; gate v2's code is unchanged because the candidate now says `zh-Hant`).

### 3.7 Two panels, and specification sheets mixed with other text (labels 07, 24)

**Layouts.** Label 07: one retailer cell holding two flavours, each a heading line and a one-line panel. Label 24: an importer specification sheet whose PDF text layer interleaves the nutrition table with ingredients, packaging and origin text, prints the serving labels in one block and their values in the next, and puts the last two labels after all values.

**Safe to read?**

- **07:** each panel on its own is readable (3.4), but which flavour the user ate is the user's knowledge. Choosing a panel automatically would be a guess.
- **24:** no. The stacked rule (3.2) would stop after the first row, which leaves a Confirm that is mostly empty; that is close to the blank nutrient form #86 excludes.

**Proposal.**

1. **Two panels: keep declining in v3, with better copy and a better next step.** New copy for `multiple_panels` when the parser found two or more complete panels: "This text has more than one nutrition table (for example two flavours). Delete the ones you did not eat, then read again." The text is kept and editable, so this costs the user one edit, and the stored text then is the panel they meant. A **panel chooser** (list each panel by its heading line and energy value, record the choice in the manifest) is possible later as its own persisted change; decision 8.
2. **Too little read: decline.** New parser decline `too_little_read` when fewer than 5 of the 8 Taiwan mandatory rows are read (energy, protein, fat, saturated fat, trans fat, carbohydrate, sugars, sodium). Copy: "Only a few values could be read from this text. Try copying the table again, or use Search or Barcode." The threshold is "more than half"; decision 3.

**Changes.** Copy only for two panels (parser v2 already declines it); parser only for `too_little_read` (a new code, mapped to copy).

### 3.8 Partial reading: a row is not read instead of the table being declined

Several rules above (3.2, 3.4, 3.6, 3.9) make a **row** unread rather than declining the table. This is the "partial reading" extension that v1 section 8.5 anticipated. It fits the v1 model without new persisted formats:

- An unread mandatory row has no cells, so gate v2 raises its existing G3 (`required_row_missing`) and Confirm shows the existing "Not read: <row>. Add it, or leave it unknown." The user enters it ("Entered by you") or leaves it unknown.
- A row unread in one column only (a malformed value in one column of a two-column row) is unread in **both** columns (rule 3.4.4), so the stored column never mixes a read value with an unread sibling from the same row.
- The parser records each unread row as a candidate warning `row_not_read: <reason>: <printed label>` (reasons: `stacked_sequence`, `malformed_value`, `unit_off_template`, `gloss_conflict`, `unit_pair_mismatch`). The manifest already stores candidate warnings verbatim. The application's `LabelReading` gains a list of unread rows for the "Printed but not read" section; this is an in-memory port change, not a stored one.
- `wouldMarkReady` stays false for any candidate with a `row_not_read` warning; in the product it has no effect on Log.

### 3.9 Taiwan unit rule (new safety rule)

The Taiwan template fixes each mandatory row's unit: energy in 大卡 (kcal), sodium in 毫克 (mg), the rest in 公克 (g). Parser v2 accepts g, mg or µg on any non-energy row. **Rule (parser v3, Taiwan only):** a mandatory row whose value unit is not the template unit is not read (`unit_off_template`). Optional rows keep parser v2's unit sets. This turns the most damaging misbinding (a gram value bound to sodium, or a milligram value bound to a gram row) into an unread row, and it is what makes the stacked rule (3.2) tolerable.

### 3.10 Summary

| Class (dev labels) | v3 outcome on the dev set (development evidence only) | Change |
|---|---|---|
| Lines before the table (16, and part of 05, 09, 10, 17, 19, 21 to 23) | 16 read in full | Parser; serving v3 (persisted method string) |
| One value per line (21, 22, 23) | Confirm, with 2 or 3 rows "Not read" each | Parser |
| No basis header (05, 09, 10) | Confirm after the user chooses the basis | **Persisted**: manifest v2 |
| One line (06, 08, 12, 13, 14, 19) | Confirm; 12 with two rows "Not read" (a malformed value and a missing separator) | Parser; new decline code |
| Basis in the energy line (20) | Confirm | Parser |
| Bilingual (17) | Confirm | Parser |
| Two panels (07) | Declined, new copy | Copy |
| Specification sheet (24) | Declined `too_little_read` | Parser; new decline code |
| Accepted today (01 to 04, 11, 15, 18) | Unchanged values; 03 and 11 gain the rows their alias names hid | Parser (alias table) |

If every proposal is accepted, the dev set would reach Confirm on 22 of 24 labels (8% declined, against 71% today). This number was produced by designing against these texts, so it is a ceiling, not a forecast.

## 4. Row-name aliases: `taiwan-row-aliases-v1`

A closed, versioned table inside parser v3. Matching stays **exact** on the compacted label (spaces and ideographic spaces removed, after the row-marker rule of 3.1), never substring or prefix: 不飽和脂肪 contains 飽和脂肪 and must never be read as saturated fat.

**Normalisation before lookup** (closed list): remove one trailing bracket group whose content is exactly 自願標示者 or 自願標示, in ASCII or full-width brackets. Nothing else is stripped.

| Printed label (after normalisation) | Row | Parent | Evidence |
|---|---|---|---|
| 熱量 | energy | none | v2 |
| 蛋白質 | protein | none | v2 |
| 脂肪 | fat | none | v2 |
| 飽和脂肪, **飽和脂肪酸** | saturates | fat | v2; dev set (2 labels) |
| 反式脂肪, **反式脂肪酸** | trans_fat | fat | v2; dev set (2 labels) |
| 碳水化合物 | carbohydrate | none | v2 |
| 糖 | sugars | carbohydrate | v2 |
| **添加糖** | added_sugars (existing reader key, not a ledger key: read but not used) | sugars | not in the dev set; included so the exact match keeps it away from 糖 (owner to confirm, decision 9) |
| 膳食纖維 (also with the 自願標示者 bracket) | fibre | carbohydrate | v2; dev set |
| 鈉 | sodium | none | v2 |

**Recognised as not stored** (named so they are never mistaken for a stored row, and listed under "Read but not used"): 膽固醇, 鈣, 鉀, 鐵, 維生素 rows, 單元不飽和脂肪(酸), 多元不飽和脂肪(酸), 不飽和脂肪(酸). These stay `unrecognised` in the candidate (no new nutrient key) but are pinned by tests as never matching a stored row.

**Held out, decision 9:** 醣類 (an older wording for carbohydrate on some Taiwan labels). It is one character away from 糖 in meaning and appearance; adding it should wait until it is seen in real text, and then needs its own mutation test (醣類 never read as sugars, 糖類 never read as carbohydrate).

Extending the table is a new alias version and a new parser version. The English row table is unchanged in v3 (UK English is not shipping).

## 5. Versioning

### 5.1 Version strings

| Component | Today | Proposed |
|---|---|---|
| Parser | `nutrition-label-text-parser-v2` | `nutrition-label-text-parser-v3` (includes `taiwan-row-aliases-v1`) |
| Decline gate | `label-capture-decline-gate-v2` | **unchanged** (recommended; decision 11) |
| Arithmetic checks | `label-arithmetic-checks-v1` | unchanged, or `label-arithmetic-checks-v2` if the basis plausibility warning is accepted (decision 5) |
| Conversions | `pasted-label-conversions-v1` | unchanged |
| Manifest | `pasted-nutrition-label-v1` | unchanged for parser-only phases; `pasted-nutrition-label-v2` when the basis choice lands (decision 4) |
| Serving policy | `pasted-label-serving-v1`, `-v2` | add `pasted-label-serving-v3` (decision 12) |
| Candidate schema | `label-capture-candidate-v1` | unchanged |

**Parser v3 accumulates across PRs until the release check starts.** As with serving v2 (v1 section 6.3), a version that no distributed build carries can still be amended; once the release check's freeze commit is recorded (section 7.4), any change is parser v4.

### 5.2 Admitted pipelines

`PastedLabelSource.admittedPipelines` is append-only. After all phases:

- `pasted-nutrition-label-v1`: `…-parser-v2:…-gate-v2:…-checks-v1:…-conversions-v1` (existing) and `…-parser-v3:…-gate-v2:…-checks-v1:…-conversions-v1` (new).
- `pasted-nutrition-label-v2`: `…-parser-v3:…-gate-v2:<checks v1 or v2>:…-conversions-v1`.

A new reading writes the newest pipeline only. Existing entries are never removed or rekeyed.

### 5.3 Manifest v2 (only for the basis choice)

`pasted-nutrition-label-v2` is v1 plus one field:

| Field | Content |
|---|---|
| `basis_choices` | one record per amount column whose basis was not printed: `header_id`, `basis` (`per_serving`, `per_100g`, `per_100ml`), `offered` (the options shown, in order), `at` (milliseconds since 1970, injected clock). An empty array when every basis was printed |

- `captureMethodVersion` `pasted-nutrition-label-v2`; `schemaVersion` `pasted-nutrition-label-v2:<format>`; same source ID, verifier and retention.
- **Verification adds:** every header whose printed text is empty has exactly one `basis_choices` record with the same basis, and every record names such a header. Values from a chosen-basis column are stored with `user_verified_panel` provenance like any printed cell (their numbers are printed), and the basis line's origin is "Chosen by you".
- **Contract version (decision 13).** `minimumContractVersion` must treat the v2 capture method like v1. Contract 7 has not been distributed (it is listed in `docs/releases/unreleased.md`), so the recommendation is to keep contract 7 and `food-ledger-v7` and have contract 7 cover both manifest versions. If any build carrying contract 7 is distributed before manifest v2 merges, manifest v2 needs contract 8, because a contract-7 binary would decode the entry but fail its verification.
- A parser-only reading (no unprinted basis) keeps writing manifest v1, so the common case stays on the format already built and tested.

### 5.4 Stored manifests

- **Every stored v1 manifest decodes, verifies and reopens unchanged.** Verification compares against the stored bytes, never a re-parse (v1 section 6.1), so parser v3 cannot invalidate a parser-v2 entry. Golden fixtures pin a parser-v2 manifest and a parser-v3 manifest under v1, and a manifest v2, each round-tripping byte for byte.
- **Serving policy chosen by parser version.** Reopen re-evaluates the serving rule against the stored manifest. A parser-v2 manifest keeps `pasted-label-serving-v2` with its pinned v2 grammar; a parser-v3 manifest on a per-100 column uses `pasted-label-serving-v3`, identical to v2 except that its grammar copy is pinned to parser v3's serving grammar (3.1). v1 (per-serving column) is unchanged for both. A v2 conversion on a parser-v3 manifest, or the reverse, fails at save (`sourceServingsRequired`) and at reopen (`integrityFailure`).
- **Developer tools** re-parse with the current parser and show differences, so a parser-v2 entry will show what v3 would read. This is for reproduction only.

### 5.5 Parity with the Python reference

- **Parser:** there is no Python parser. The evaluation ran the Swift module through `NutritionLabelTextParse` (evaluation decision 2), so the Swift parser is its own reference. Parity here means **non-regression**: parser v3 must produce, on every frozen evaluation case (the 107 untouched synthetic Taiwan cases, the English development cases and every existing parser fixture), a candidate identical to parser v2's in every field except the version string. Any difference is a finding to explain before merge.
- **Gate:** unchanged, so `decline_gate.py`, its exported vectors and the Swift parity tests (v1 tests 1 and 25) are unchanged. Every v3 rule that needs a decision lives in the parser, which the gate already treats as its input.
- **Arithmetic:** if checks v2 is accepted, it is checks v1 plus one check, implemented in Swift only, with its own golden vectors; the v1 parity tests against `arithmetic.py` stay as they are and must still pass.

## 6. Architecture notes

- Layers do not change: rules in `NutritionLabelParsing`; the basis choice as an application use-case step (the adapter re-runs the parser with the chosen bases through the `LabelTextReading` port, which gains an optional `assertedBases` input); the sheet in presentation; the manifest in application.
- `LabelReading` gains `unreadRows` and a `basisNotPrinted` marker per column. No parser type crosses the port (decision 10 of v1).
- New decline codes (`flattened_table_ambiguous`, `too_little_read`) and the multi-panel copy go through the existing code-to-copy table and its exhaustive test.
- The architecture gate should be run on this document before PR 1.

## 7. Safety bar and evaluation

### 7.1 Synthetic fixtures per layout

Every layout in section 3 gets synthetic fixtures with invented values and invented product names, modelled on the shape only; no real label text, number or name enters the repository. At least: decorated titles (each decoration); every serving and pack variant, including the split lines and a pack count of 0; stacked layout regular, with labels after values at the end, with a label block before a value block, and with a swapped label pair; each flattened-line separator family, with a malformed number, a missing separator, an unknown row with the right count and with the wrong count; no basis header with one and two columns, with and without a serving size, and the `%` column; basis in the energy line, and in a later row; bilingual with agreeing, conflicting and unknown glosses, unit pairs that agree and that do not, and "about" in the English pack bracket only; two panels; a specification sheet with interleaved text.

### 7.2 Mutation tests

A mutation suite applies, to every synthetic fixture whose truth is known, the transformations a paste can introduce, and asserts the **safety property**: every value the reader binds equals the truth for that row, column, basis and unit, or it is not read, or the table is declined. A single wrong bound value fails the suite. Mutations: swap two adjacent row labels; move a label after its values; drop or duplicate a value; drop a separator; double a decimal point; change a unit to another valid unit; replace a label with a substring trap (不飽和脂肪, 單元不飽和脂肪酸, 添加糖, 飽和脂肪 inside a longer word); add an English gloss naming another nutrient; insert a second basis phrase; insert a line of unrelated text with a number and unit into the table; full-width digits (must still decline, v1 section 1). The suite also reports how many mutations end as "not read" versus declined, as a measure of burden, not of safety.

### 7.3 Development-set run

The 24-label development set is re-run against each PR's build, outside the repository, with the same method as the 20 October run. Into the repository (PR description and a results file of counts) go only: labels, accepted, declined by reason, values matched, wrong, not read, not stated, flags, warnings, correction burden, and basis choices needed. It must keep **zero wrong values** at every PR; the seven labels accepted today must keep every value they read today.

### 7.4 Release check on a fresh set

The owner's decision of 20 October 2026 makes this the release gate for parser v3 (it replaces, for Taiwan, the pending v1 section 9 check, which was run on the development set and is now spent).

1. **Freeze first.** Record the freeze commit (parser v3, alias table, manifest and serving versions) before any fresh label is collected.
2. **Collect afterwards, by rule.** At least 24 public Taiwan labels (the development set's size; the bar is at least 20), none from a product in the development set (checked by product and by text hash). Stratified like the development set: about 15 retailer pages across at least five retailers, 5 manufacturer pages, 4 PDFs. A selection rule written down before collection (for example the first eligible products of named category listings), so layouts are not picked to suit the reader. Texts stay outside the repository.
3. **Run once** on the frozen build, CLI and device build, as in v1 section 9.
4. **Bar: zero wrong values** in every table that reaches Confirm, including values from a user-chosen basis when the owner chooses the basis from the label image. Any wrong value stops release; the fix is a new parser version, and the failed set becomes development evidence, so a **new** fresh set is needed for the next release check.
5. **Reported, not gated:** decline rate and reasons; correction burden (values corrected or entered per accepted table, mean and median, and the share needing any); basis choices needed; flags and warnings shown; rows "Printed but not read"; residual errors after the owner's check.

**Target decline rate (non-gating goal):** at most 25% of the fresh set declined (today's development figure is 71%), with a median correction burden of at most 1 value per accepted table. Missing the goal does not block release when the zero-wrong-values bar passes; it is reported and informs the next version.

## 8. Phasing into PRs

Each PR runs the full validation gates, adds its ledger row to `DEVELOPMENT_NOTES.md`, reports the dev-set counts (7.3) and passes the non-regression parity (5.5).

1. **Lines before the table, aliases and the unit rule.** 3.1, 3.9, section 4, the zero pack count, `pasted-label-serving-v3` with its grammar parity test, the admitted pipeline entry, golden fixtures for parser-v2 and parser-v3 manifests. Small and highest value: label 16 reads in full and two accepted labels gain rows.
2. **Partial reading and the stacked layout.** 3.2, 3.8, `too_little_read`, "Printed but not read" on Confirm (port, view model, copy), and the mutation suite (7.2) as a standing test.
3. **Flattened lines, basis in the energy line, bilingual.** 3.4, 3.5, 3.6, `flattened_table_ambiguous`, the two-panel copy (3.7).
4. **Basis choice.** 3.3, manifest v2, verification, the sheet, "Chosen by you" and Change, contract-version handling (decision 13), and checks v2 if decision 5 is accepted. Needs its own architecture gate pass and a simulator journey.
5. **Freeze and release check.** Section 7.4, the results file of counts, and the `docs/releases/unreleased.md` row.

PRs 1 to 3 change the parser only and can ship in any order after 1; PR 4 is the only persisted-format change.

## 9. Owner decisions

1. **Document form.** Should reader v3 be a separate versioned document that composes with v1, rather than an amendment section in v1? *Recommendation: yes* (section 0).
2. **Partial reading.** Should a row whose binding is in doubt be "Not read" on Confirm (with its printed text listed) instead of declining the whole table, and should a stacked table stop reading at its first deviation? *Recommendation: yes.*
3. **Too little read.** Should a table with fewer than 5 of the 8 Taiwan mandatory rows read decline `too_little_read`, so Confirm never opens as a mostly empty form? *Recommendation: yes.*
4. **Basis choice.** For value columns with no basis header, should the user choose the basis on a sheet before Confirm (no preselection, "I'm not sure" goes back), recorded in a new manifest version, instead of declining? *Recommendation: yes.*
5. **Basis plausibility warning.** Should an option implying more than 100 g of macronutrients or 900 kcal per 100 g carry a warning (never a block), as `label-arithmetic-checks-v2`? *Recommendation: yes, warning only.*
6. **One-line tables.** Should a flattened line be read only when its segmentation is unambiguous for every row (otherwise decline), with a malformed value making only its own row unread? *Recommendation: yes.*
7. **Bilingual tables.** Should the Chinese label decide each row, with a conflicting English gloss making the row unread and "about" in either language making the pack count approximate? *Recommendation: yes.*
8. **Two panels.** Keep declining with the new "delete the ones you did not eat" copy in v3, and leave a panel chooser for later? *Recommendation: yes.*
9. **Alias table.** Approve `taiwan-row-aliases-v1` as in section 4, holding 醣類 out until it is seen in real text? *Recommendation: yes.*
10. **Taiwan unit rule.** Should a mandatory Taiwan row printed in a unit other than the template's be unread? *Recommendation: yes.*
11. **Gate unchanged.** Keep `label-capture-decline-gate-v2` and its Python parity untouched, putting every new rule in the parser? *Recommendation: yes.*
12. **Serving v3.** Add `pasted-label-serving-v3` (v2 rules, grammar pinned to parser v3), chosen by the manifest's parser version, rather than leaving servings unavailable for the new serving-line forms? *Recommendation: yes.*
13. **Contract version.** If no build carrying contract 7 has been distributed when manifest v2 merges, keep contract 7 for both manifest versions; otherwise move to contract 8? *Recommendation: yes, as stated.*
14. **Version freeze.** Let parser v3 accumulate across PRs 1 to 4 and freeze it at the release check, any later change being v4? *Recommendation: yes.*
15. **Fresh release set.** At least 24 labels, stratified as in 7.4, collected after the freeze under a selection rule written in advance, run once, zero wrong values; a failure spends the set? *Recommendation: yes.*
16. **Decline goal.** Set a non-gating goal of at most 25% declined and a median correction burden of at most 1 on the fresh set? *Recommendation: yes.*
17. **Zero pack count.** Read a printed 0 servings per pack as printed, never offer whole pack from it, and say so on Confirm? *Recommendation: yes.*

## 10. Not changing

- v1's journey, Confirm, origins, corrections, conversions, arithmetic checks v1, privacy and egress (no egress at all), the release note form, and the rule that Log is the only save.
- Gate v2 and its Python parity (if decision 11 is accepted); the candidate schema.
- UK and US layouts: still declined by the launch scope. Full-width digits still decline (v1 section 1).
- Every stored manifest, record and archive: they decode, verify and re-encode unchanged.
