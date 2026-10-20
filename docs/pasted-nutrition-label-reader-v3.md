# Pasted nutrition label reader v3 (#93)

Status: **owner-approved, 20 October 2026.** The owner answered decisions 1 to 17 "yes to all", in session, on 20 October 2026, after the architecture gate, and approved decisions 18 to 22, which the gate revision added, in session the same day. It is a versioned amendment to the reader behind the pasted nutrition label route of [pasted nutrition label v1](pasted-nutrition-label-v1.md) so that it reads the common real Taiwan paste layouts that parser v2 declines today. It follows the owner's decision of 20 October 2026, in session: improve the reader against a real-text development set, then run the release check once on a **fresh** set of at least 20 real labels the reader has never seen.

**Architecture gate, 20 October 2026, on `3ccd9f24`: PASS WITH CHANGES.** Every finding is applied in this revision; section 11 maps each finding to where it is addressed, section 9.1 records the decided wording (marked "tightened" where the gate changed it) and section 9.2 records the decisions the revision added.

## 0. Why a separate document, and how it composes

This is a new document rather than an amendment section inside the v1 contract, for three reasons:

1. **v1 is approved and implemented.** Its text is cited by merged code and tests (PRs #267, #268, #271, #275). Amending it in place would mix approved and unapproved rules in one file, and its section numbers are referenced from code comments.
2. **The repository versions contracts by file** when the change is more than a clarification ([food confirmation v5](food-confirmation-contract-v5.md), [review manifest v2](generic-food-review-manifest-v2.md)). This change introduces a new parser version and, under decision 4, a new manifest version.
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

### 1.4 What stays outside the repository (gate finding 18; decision 20)

For the development set and the fresh release set alike: label texts, screenshots, source pages, expected values, per-label results and **text hashes** stay outside the repository. This is stricter than v1 section 9, which allowed hashes; it applies to these two sets. Evaluation tools and scripts write their outputs only to a folder outside the repository. The repository receives counts, page kinds and the rules used to choose labels, nothing else. Every PR in section 8 carries a checklist item: "Only counts and rules were added from the real-text sets; no text, value, product name or hash."

## 2. Principles carried over unchanged

From v1 section 1.1 and the repository rules: the reader pre-fills as much as it safely can, under the plain disclaimer; the user validates on Confirm and can correct any value; every exception is visible on its row; it is not binary. Unknown is never zero. Nothing saves except Log. One addition is made explicit here, because several proposals depend on it:

**The safety rule of v3.** The reader may leave a value unread, a row unread or the whole table declined. It may **never** bind a value to the wrong row, column, basis or unit. Where binding is in doubt, the cell is not read and Confirm says so. Every proposal below is judged against this rule first, and decline rate second.

**Nothing printed vanishes.** A row the reader saw but could not bind (section 3.8) is listed on Confirm under "Printed but not read" with its printed text, beside the existing "Read but not used" list, and its mandatory row (if any) carries the existing G3 or G4 flag.

## 3. Proposals per decline class

### 3.0 Layout precedence and gate input coverage (gate findings 13 and 6)

**One closed, ordered list inside the parser.** Parser v3 classifies the table body (the lines after the lines-before-the-table rules of 3.1) into exactly one layout, by testing these in order: (1) **inline** (parser v2's shape: each row label and its values on one line, possibly continued as v2 allows); (2) **stacked** (3.2); (3) **flattened line** (3.4). Each layout has a pure, closed predicate over the body's lines; there is no protocol or plug-in per layout. If the body satisfies **more than one** predicate, or none, the table declines (`layout_ambiguous`, copy as `unreadable_table`; decision 19). The basis-in-energy-line rule (3.5), the bilingual rule (3.6) and the basis choice (3.3) are modifiers that apply within the chosen layout, not layouts of their own. Adding a layout is a new parser version.

**Gate input coverage.** Gate v2 looks for supplement markers and unsupported script in the text it is given, which today is the candidate's cells and labels. Parser v3 consumes more lines without binding them (titles, rule lines, decoration, "Printed but not read" rows, English glosses, lines ignored in a flattened line). So parser v3 runs the gate's own `LabelDeclineGate.supplementMarkers(in:)` and its script classification over **every consumed-but-unbound line**, and a hit declines with the existing code (`not_a_food_nutrition_panel`, `unsupported_script`). The gate's code, version and Python parity are unchanged: the parser calls the same functions, it does not copy them. A test per new layout plants a supplement marker and a simplified-only character in an unbound line and expects the existing decline.

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
3. Serving label: `每[一1]?份量`. When the label stands alone, the next non-empty line is joined to it only if **all** of these hold (gate finding 4): that line is a serving quantity and nothing else; both lines come **before the first row label** of the table; the table's layout is **not stacked** (3.2); and the candidate has no `row_not_read: stacked_sequence` row. Otherwise the serving size is **not read** (G6 flag, the user can enter it). The joined serving line's printed text is the label line and the quantity line, each trimmed, joined by one ASCII space, and the candidate carries the warning `serving_line_joined` (serving v3, section 5.6, scans exactly this string).
4. Pack line: `本包裝(包)?含?` followed by an optional 約 and a number and 份. When the pack label stands alone, the same join rule and conditions as rule 3 apply. When the serving line also contains a pack phrase after its quantity, the pack count is read from that phrase, and the serving value ends where the pack phrase begins (section 5.6).
5. A closed set of leading row markers (`>>`, `>`, `•`, `·`, `▲`, `●`, `-` and `*` only when followed by a Han character) is removed from a row label before classification and counts as indentation.
6. A printed pack count of zero is read as printed, never used for the whole-pack option, and shown with "Printed as 0, so whole pack is not offered." (one PDF in the set prints 0 份).

**Residual risks.** A product name line in brackets before the title could be taken as decoration; it carries no value, so the worst case is a lost heading. Rule 3 could join a serving label to a quantity that belongs to something else; the conditions limit it to the very next non-empty line, before any row, outside stacked tables. In stacked PDFs (3.2) this means the serving size is usually not read and the user enters it; that is the price of not trusting text-layer order. A mutation that moves the serving quantity line elsewhere must end with the serving size not read (section 7.2).

**Changes.** Parser only, **with one persisted consequence:** `pasted-label-serving-v2` derives the serving-size segment from a pinned copy of parser v2's serving-size grammar (v1 section 6.3). A serving line read under rule 3 or 4 would not match that copy, so servings would silently not be offered. Section 5.6 specifies `pasted-label-serving-v3` in full, chosen by the manifest's parser version.

### 3.2 One value per line (labels 16, 21, 22, 23; `multiple_panels`)

**Layout.** Each row label, then each column's value, every item on its own line, usually from a PDF's text layer or a retailer page built from a grid of cells. With the line-before-table fixes (3.1), label 16 already reads in full: parser v2's value-only-line attachment handles the shape. The three PDFs add a harder problem: **their text layer puts the last one or two row labels after their values** (for example the values of the last two rows, then both labels), so reading in order binds the wrong numbers to the wrong rows, or overflows a row.

**Safe to read?** Partly. Rows before the first irregularity are bound in a regular sequence and can be read. From the first irregularity onwards, order is no longer evidence of binding.

**Rule (parser v3, "stacked layout").** A table is stacked when its row labels stand on lines with no values and its values stand on lines with no label. In a stacked table:

1. The expected sequence is strictly: a label line, then exactly as many value lines as there are columns (amount columns plus any reference-intake column), then the next label line.
2. **Template order (gate finding 3).** The mandatory row labels must appear in the official Taiwan template order: 熱量, 蛋白質, 脂肪, 飽和脂肪, 反式脂肪, 碳水化合物, 糖, 鈉 (each by its alias, section 4). Optional rows (fibre, added sugars, the named not-stored rows, unrecognised rows) may appear between them. The first mandatory label that comes before a mandatory label it should follow is a deviation.
3. At the **first deviation** (a label followed directly by another label, a row with more or fewer values than columns, values after the last label, a label at the end with no values, or a template-order break), that row and **every row after it** are not read (`row_not_read: stacked_sequence`). Their labels and values go to "Printed but not read".
4. Rows before the first deviation are read as normal, under the Taiwan unit rule (3.9).
5. **Mixed tables decline.** A body in which some rows are inline (label and value on one line) and others stacked satisfies neither predicate cleanly and declines `layout_ambiguous` (3.0; decision 21). There is no safe rule for binding across the two shapes: the inline rows prove nothing about the order of the stacked ones. Parser v2's stacked-energy continuation (kJ and kcal on two lines) stays part of the inline layout, unchanged.

**Residual risks.** With the template order enforced, a swap of two mandatory **labels** is a deviation. What remains undetectable by structure is a text layer that keeps the labels in order but exchanges the **value lines** of two adjacent rows with the same unit (for example the protein and fat values), or exchanges two adjacent optional rows. Section 7.2 names this as the accepted residual risk for owner approval (decision 18) and pins the reader's behaviour on it. The existing energy and sub-row checks warn on some of these cases and never block.

**Changes.** Parser only (new warnings in the candidate, which the manifest already stores as strings).

### 3.3 Value columns with no basis header (labels 05, 09, 10; `no_basis_header`)

**Layout.** The Taiwan serving lines, then rows with one or two value columns and no 每份 or 每100公克 heading at all; the heading row was an image or a merged cell that did not copy. The single-column cases print values whose size fits a serving; the two-column case prints the official template's order.

**Safe to read?** The rows and values bind cleanly; only the basis is unknown. Guessing the basis is exactly the error that must never happen silently (a per-serving column stored as per 100 g is wrong by the factor serving size / 100 on every value). So the reader must not choose. **The user can:** the label in their hand, or the product page, says what the column is.

**Proposal: an assisted basis choice instead of a decline.**

1. Parser v3 reads such a table and marks each amount column as "basis not printed". A `%` column is still recognised by its unit as the reference-intake column and is **never** a basis choice. A table where **some** amount columns have a printed basis and others do not declines `no_basis_header` as today (gate finding 7): a partly printed header is evidence of a misaligned paste, not of a missing heading.
2. The options and their order are computed in the application by one pure, tested function from the reading (number of unheaded amount columns, serving size read or not, its unit), not in presentation, which only renders them (gate finding 9). Before Confirm, a short sheet asks: "These values have no column heading. What are they for?" with **Per serving (printed serving size, for example 25 g)**, **Per 100 g**, **Per 100 ml**, and **I'm not sure**. For two amount columns it offers the official template's arrangements only: "Per serving, then per 100 g" and "Per serving, then per 100 ml"; any other arrangement is not offered. No option is preselected. "I'm not sure" returns to the label text screen with the text kept and a link to Search.
3. Per serving is offered only when a serving size was read (in grams or millilitres); otherwise only the per 100 options are offered, and "Per serving" says why it is missing.
4. The choice is recorded in the manifest (section 5.3) and shown on Confirm as the basis line "Per 100 g · Chosen by you", with **Change**. Changing it rebuilds the reading and, if the user has corrected or entered anything, asks first, as **Read again** does today.
5. Decision 5 (decided): a **basis plausibility warning** (`label-arithmetic-checks-v2`) beside an option that would imply more than 100 g of protein, fat and carbohydrate per 100 g, or more than 900 kcal per 100 g, beyond a stated tolerance. It is a warning, never a block and never a "checked" mark; a pass shows nothing.

**Why before Confirm and not as a Confirm requirement.** The stored column's basis decides the resolution's basis, the servings policy and the identity's `servingBasis`, so Confirm cannot be built without it. A sheet before Confirm adds no `FoodLogRequirement` and leaves `food_confirmation_v5` untouched. The journey still ends on the shared Confirm screen with one Log action.

**Residual risks.** The user can choose wrongly. That is a user assertion shown with its origin, like any correction, and the plausibility warning catches only implausible choices. A single column per serving and per 100 g can be equally plausible; the sheet must not imply that one answer is likely.

**Provenance (gate finding 8).** In a manifest v2 entry, the numbers of a chosen-basis column are printed, so they keep `user_verified_panel` provenance like any printed cell, but **their basis is user-asserted**, evidenced by the `basis_choices` record, and verified at save and at reopen (section 5.3). Confirm, the saved entry, Developer tools and the misread report show the basis as "Chosen by you".

**Changes. Persisted:** a new manifest field for the choice, and therefore a new manifest version (section 5.3). The candidate keeps its schema: after the choice, the adapter re-runs parser v3 on the same text with the chosen bases as an input (an application-owned type, `AssertedBases`, mapped by the adapter; no parser type crosses the port), so the stored candidate has ordinary bases and an empty printed header text, and gate v2 runs unchanged.

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
2. A **well-formed value token** is: an optional comparator, digits with at most one decimal point and no grouping, optional spaces, and a unit; and what follows its unit is a separator (space, `/`, `,`, `、`, `，`, `；`, `(`, `)`, `。`), a label token or the end.
3. **Every digit run must belong to a well-formed value token, a serving or pack phrase, or a basis phrase (gate finding 1).** Any other digit run is a **malformed** token. This covers: a number with two decimal points; two values with no separator between them; thousands separators in any form (`1,234大卡`, `1，234大卡`, `1 200毫克`, where the leading group would otherwise read as a value of its own); a number with no unit; and a stray number between rows.
4. **Segmentation** is accepted only if every label token is followed by exactly N value-or-malformed tokens (N = the number of amount columns, plus the reference column if printed) before the next label token. If any label token is followed by a different number, or if a malformed token or a `%` value stands **outside** any row (before the first label, or after a row's N tokens), the line is declined `flattened_table_ambiguous` (new code, copy as `count_mismatch`).
5. Within an accepted segmentation, a row containing any malformed token is **not read** (both columns, `row_not_read: malformed_value`) and goes to "Printed but not read". Other rows read normally.
6. **`%` on some rows only.** A `%` token counts toward N only when a reference-intake header was printed; then every row must carry its `%` token in the same position (mandatory rows with `*` instead of a percentage count it as that row's reference token). If `%` appears on some rows but no reference header was printed, or not in the same position on every row, the line declines `flattened_table_ambiguous`.
7. A row inside brackets after a parent row is that parent's sub-row; it is classified by the alias table, never by position.
8. The basis comes from a basis phrase before the first row (header or a prefix stuck to the first label, like `每份`), never from a later position. Without one, section 3.3 applies.

**Residual risks.** An unknown nutrient between known ones with the right value count is read as an unrecognised row (read but not used), which is correct. A site that prints a value without a unit in a flattened line would make segmentation fail and decline, which is safe. A flattened line that is really two panels (two basis phrases with different row sets) declines `multiple_panels`.

**Changes.** Parser only, plus one new decline code with copy (the renderer's code-to-copy test, v1 test 27, enumerates it).

### 3.5 Basis printed only inside the energy line (label 20; `no_table`)

**Layout.** Multi-line, one column, no header line; the basis is a bracket after the energy value (per 100 ml), and sub-rows carry a `>>` marker.

**Safe to read?** Yes, under a narrow rule.

**Rule (parser v3).** When there is no header line, the table has exactly one amount column, the **first row is the energy row** (熱量), and that row carries exactly one bracketed basis phrase that `basis(of:)` recognises, that phrase becomes the column's header (printed text: the bracket as printed) (gate finding 14). A basis phrase on any other row, on a first row that is not energy, or more than one, declines `multiple_panels` as now. A fixture with printed serving lines and a bracket saying per 100 g, whose values are really per serving, must end with the existing energy and scaling checks warning (they cannot prove the basis, so the fixture pins a warning, not a decline).

**Residual risks.** A label that states per 100 ml for energy but per serving for the rest would be misread; this is not a layout seen, and the energy and sub-row checks would usually warn. Accepted as low.

**Changes.** Parser only.

### 3.6 Bilingual Chinese and English tables (label 17; `multiple_panels`)

**Layout.** The official Taiwan template with an English gloss after each Chinese row label (for example 脂肪 followed by "Total Fat"), a bilingual title and header, bilingual serving lines (one with an English typo), and every value printed with its unit twice: a bracketed English unit and the Chinese unit.

**Safe to read?** Yes, by reading the Chinese and using the English only as a cross-check.

**Rule (parser v3).**

1. **Header (gate finding 16).** In a bilingual header the Chinese phrase decides each column's basis. If the English part of the same column names a different basis (for example per 100 g beside 每份), the table declines `multiple_panels`, as a conflicting header is evidence of a misaligned paste. An English part that names no basis is ignored.
2. Language: a text whose rows all start with a recognised Chinese row label is `zh-Hant` even if it contains Latin words, provided every Latin word sits either in a row's gloss, in the title, header or serving lines, or in a bracket after a recognised Chinese phrase.
3. The Chinese label classifies the row. If the English gloss classifies to a **different** nutrient under the existing English row table, the row is not read (a conflicting gloss is evidence the paste is misaligned). An unknown gloss is ignored.
4. A value printed as number, bracketed English unit, Chinese unit is one value only when both units have the same canonical unit; otherwise the row is not read.
5. Serving and pack lines read the Chinese phrase; an English bracket after it is ignored for **binding** the number, but it is **scanned for approximation** (gate finding 5): "about", "approx" or any other serving v3 approximation marker (section 5.6) in either language makes the pack count approximate (whole pack not offered) and the serving size approximate (servings not offered on a per 100 column). This is the conservative side.
6. Format inference: such a text is `taiwan_nutrition_labelling`, never UK or US, so the US "Nutrition Facts" words in the title do not route it to `layout_not_supported`. This needs no new inference rule: inference stays `pasted-label-format-inference-v1`, which already resolves a candidate whose language is `zh-Hant` to Taiwan; parser v3 only reports the language as `zh-Hant` under rule 2.

**Residual risks.** English-only rows inside a Chinese table (not seen) stay unrecognised. A bilingual label from a different market (for example a Hong Kong layout) would now infer as Taiwan; the Taiwan mandatory-row flags and the unit rule (3.9) still apply, and the release check should include at least one such case if one can be found.

**Changes.** Parser only (language and format inference are in the parser and the gate's inference, which reads the candidate's language; gate v2's code is unchanged because the candidate now says `zh-Hant`).

### 3.7 Two panels, and specification sheets mixed with other text (labels 07, 24)

**Layouts.** Label 07: one retailer cell holding two flavours, each a heading line and a one-line panel. Label 24: an importer specification sheet whose PDF text layer interleaves the nutrition table with ingredients, packaging and origin text, prints the serving labels in one block and their values in the next, and puts the last two labels after all values.

**Safe to read?**

- **07:** each panel on its own is readable (3.4), but which flavour the user ate is the user's knowledge. Choosing a panel automatically would be a guess.
- **24:** no. The stacked rule (3.2) would stop after the first row, which leaves a Confirm that is mostly empty; that is close to the blank nutrient form #86 excludes.

**Proposal.**

1. **Two panels: keep declining in v3, with better copy and a better next step.** New copy for `multiple_panels` when the parser found two or more complete panels: "This text has more than one nutrition table (for example two flavours). Delete the ones you did not eat, then read again." The text is kept and editable, so this costs the user one edit, and the stored text then is the panel they meant. A **panel chooser** (list each panel by its heading line and energy value, record the choice in the manifest) is possible later as its own persisted change; decision 8.
2. **Too little read: decline.** New parser decline `too_little_read` when fewer than 5 of the 8 Taiwan mandatory rows are read (energy, protein, fat, saturated fat, trans fat, carbohydrate, sugars, sodium). A mandatory row counts as **read** only when it has a cell in the column that would be stored (v1 section 6.3); for an unheaded table that is evaluated for each basis the sheet would offer, and the table declines only if it fails for every option (gate finding 15). A calculated value does not count. Copy: "Only a few values could be read from this text. Try copying the table again, or use Search or Barcode." The threshold is "more than half"; decision 3.

**Changes.** Copy only for two panels (parser v2 already declines it); parser only for `too_little_read` (a new code, mapped to copy).

### 3.8 Partial reading: a row is not read instead of the table being declined

Several rules above (3.2, 3.4, 3.6, 3.9) make a **row** unread rather than declining the table. This is the "partial reading" extension that v1 section 8.5 anticipated. It fits the v1 model without new persisted formats:

- An unread mandatory row has no cells, so gate v2 raises its existing G3 (`required_row_missing`) and Confirm shows the existing "Not read: <row>. Add it, or leave it unknown." The user enters it ("Entered by you") or leaves it unknown.
- A row unread in one column only (a malformed value in one column of a two-column row) is unread in **both** columns (section 3.4, rule 5), so the stored column never mixes a read value with an unread sibling from the same row.
- The parser records each unread row as a candidate warning `row_not_read: <reason>: <printed label>` (reasons: `stacked_sequence`, `malformed_value`, `unit_off_template`, `gloss_conflict`, `unit_pair_mismatch`). The manifest already stores candidate warnings verbatim. The application's `LabelReading` gains a list of unread rows for the "Printed but not read" section; this is an in-memory port change, not a stored one.
- `wouldMarkReady` stays false for any candidate with a `row_not_read` warning; in the product it has no effect on Log.

### 3.9 Taiwan unit rule (new safety rule)

The Taiwan template fixes each mandatory row's unit: energy in 大卡 (kcal), sodium in 毫克 (mg), the rest in 公克 (g). Parser v2 accepts g, mg or µg on any non-energy row. **Rule (parser v3, Taiwan only):** a mandatory row whose value unit is not the template unit is not read (`unit_off_template`). Optional rows keep parser v2's unit sets. This turns the most damaging misbinding (a gram value bound to sodium, or a milligram value bound to a gram row) into an unread row, and it is what makes the stacked rule (3.2) tolerable.

### 3.10 Summary

| Class (dev labels) | v3 outcome on the dev set (development evidence only) | Change |
|---|---|---|
| Lines before the table (16, and part of 05, 09, 10, 17, 19, 21 to 23) | 16 read in full | Parser; serving v3 (persisted method string) |
| One value per line (21, 22, 23) | Confirm, with 2 or 3 rows "Not read" each and the serving size not read (split serving lines are not joined in stacked tables, 3.1 rule 3) | Parser |
| No basis header (05, 09, 10) | Confirm after the user chooses the basis | **Persisted**: manifest v2 |
| One line (06, 08, 12, 13, 14, 19) | Confirm; 12 with two rows "Not read" (a malformed value and a missing separator) | Parser; new decline code |
| Basis in the energy line (20) | Confirm | Parser |
| Bilingual (17) | Confirm | Parser |
| Two panels (07) | Declined, new copy | Copy |
| Specification sheet (24) | Declined `too_little_read` | Parser; new decline code |
| Accepted today (01 to 04, 11, 15, 18) | Unchanged values; 03 and 11 gain the rows their alias names hid | Parser (alias table) |

With every proposal in place, the dev set would reach Confirm on 22 of 24 labels (8% declined, against 71% today). This number was produced by designing against these texts, so it is a ceiling, not a forecast.

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
| Parser | `nutrition-label-text-parser-v2` | `nutrition-label-text-parser-v3` (includes `taiwan-row-aliases-v1` and the layout precedence of 3.0) |
| Decline gate | `label-capture-decline-gate-v2` | **unchanged** (decision 11) |
| Format inference | `pasted-label-format-inference-v1` | **unchanged**: a bilingual Taiwan text resolves to Taiwan because parser v3 reports its language as `zh-Hant` (3.6) |
| Arithmetic checks | `label-arithmetic-checks-v1` | unchanged for manifest v1 readings; `label-arithmetic-checks-v2` (v1 plus the basis plausibility warning) for manifest v2 readings. decision 5, decided |
| Conversions | `pasted-label-conversions-v1` | unchanged |
| Manifest | `pasted-nutrition-label-v1` | unchanged for every reading with printed bases; `pasted-nutrition-label-v2` only for a reading with a chosen basis (decision 4) |
| Serving policy | `pasted-label-serving-v1`, `-v2` | add `pasted-label-serving-v3` (section 5.6, decision 12) |
| Candidate schema | `label-capture-candidate-v1` | unchanged |

**Parser v3 accumulates across PRs until it is frozen.** As with serving v2 (v1 section 6.3), a version that no distributed build carries can still be amended. It is frozen at the earlier of the release check's freeze commit (section 7.4) and the **first distribution** of any build carrying parser v3 or serving v3 (gate finding 19). "Distribution" means any TestFlight or App Store build, or any install on a device used with real food data, including the owner's own phone. No such build may carry parser v3 or serving v3 before the freeze; if one must, the freeze happens at that commit. After the freeze any change is parser v4 (or serving v4).

### 5.2 Admitted pipelines

`PastedLabelSource.admittedPipelines` is append-only. After all phases it holds exactly (gate finding 11):

- `pasted-nutrition-label-v1`:
  - `nutrition-label-text-parser-v2:label-capture-decline-gate-v2:label-arithmetic-checks-v1:pasted-label-conversions-v1` (existing)
  - `nutrition-label-text-parser-v3:label-capture-decline-gate-v2:label-arithmetic-checks-v1:pasted-label-conversions-v1` (new, PR 1)
- `pasted-nutrition-label-v2`:
  - `nutrition-label-text-parser-v3:label-capture-decline-gate-v2:label-arithmetic-checks-v2:pasted-label-conversions-v1` (new, PR 4; decision 5, decided)

A new reading writes the newest pipeline for its manifest version only. Existing entries are never removed or rekeyed. A contract test pins the full list.

### 5.3 Manifest v2 (only for the basis choice)

`pasted-nutrition-label-v2` is v1 plus one field:

| Field | Content |
|---|---|
| `basis_choices` | one record per **amount** column whose basis was not printed: `header_id`, `basis` (`per_serving`, `per_100g`, `per_100ml`), `offered` (the options shown, in order, as the application's pure options function returned them), `at` (milliseconds since 1970, injected clock). Never empty in a v2 manifest |

- `captureMethodVersion` `pasted-nutrition-label-v2`; `schemaVersion` `pasted-nutrition-label-v2:<format>`; same source ID, retention and admission list entry (`pasted-nutrition-label`), with a v2-aware verifier.
- **Verification adds (gate finding 7):**
  - every amount header (basis `per_serving`, `per_100g`, `per_100ml`) has empty printed text and exactly one `basis_choices` record with the same basis; every record names such a header; there is no mixed manifest with some amount headers printed and some chosen;
  - a `reference_intake` (`%`) header never has a record and keeps its printed text;
  - `offered` equals what the options function returns for the stored reading, and contains the chosen basis;
  - values from a chosen-basis column keep `user_verified_panel` provenance (their numbers are printed), and their **basis is user-asserted**, evidenced by the record (gate finding 8); verified at save (`invalidPastedLabelSource`) and at reopen (`integrityFailure`).
- **The v1 verifier tightens one check:** a v1 manifest with any amount header whose printed text is empty is rejected. Parser v2 and v3 never produce one under v1, so no stored entry is affected; a contract test proves the rejection.
- **Separate decode path (gate finding 10).** The v1 manifest type and its canonical encoding are unchanged and never gain a `basis_choices` key (golden bytes test); v2 is decoded by dispatching on `version`. `minimumContractVersion` treats both capture-method versions alike. Cross-route tests: the reviewed web verifier rejects v2 evidence; the pasted-label verifier rejects reviewed web evidence and a v1 manifest relabelled v2 (and the reverse).
- **Developer tools** re-parse a v2 entry with its `basis_choices` passed as asserted bases, so the re-parse reproduces the stored candidate; a v1 entry is re-parsed with none.
- **Contract version (decision 13).** Contract 7 has not been distributed (it is in `docs/releases/unreleased.md`). If, when PR 4 merges, no distributed build (definition in 5.1) carries contract 7, contract 7 covers both manifest versions and the store stays `food-ledger-v7`. Otherwise manifest v2 needs contract 8, because a contract-7 binary would decode the entry but fail its verification. PR 4 records the check (TestFlight build list, release notes, the owner's statement about device installs) in its description.
- A reading with printed bases keeps writing manifest v1, so the common case stays on the format already built and tested.

### 5.4 Stored manifests

- **Every stored v1 manifest decodes, verifies and reopens unchanged.** Verification compares against the stored bytes, never a re-parse (v1 section 6.1), so parser v3 cannot invalidate a parser-v2 entry. Golden fixtures pin a parser-v2 manifest and a parser-v3 manifest under v1, and a manifest v2, each round-tripping byte for byte.
- **Serving policy chosen by parser version**, through the closed table in 5.6.
- **Developer tools** re-parse with the current parser and show differences, for reproduction only.

### 5.5 Parity and non-regression

- **Parser:** there is no Python parser. The evaluation ran the Swift module through `NutritionLabelTextParse` (evaluation decision 2), so the Swift parser is its own reference, and parity means **non-regression** (gate finding 12). On every frozen evaluation case (the 107 untouched synthetic Taiwan cases, the English development cases and every existing parser fixture), parser v3's candidate must equal parser v2's except for differences on a closed, enumerated allow-list, each tied to a rule:
  1. the parser version string;
  2. a case parser v2 declined that v3 reads (rules 3.1 to 3.6); every such case must pass the **truth oracle**: each bound value equals the case's truth for row, column, basis and unit (7.2, class a). A frozen case whose truth is a required decline must still decline, unless the owner reclassifies it in the PR with a reason;
  3. a row parser v2 left `unrecognised` that an alias now names (section 4), with the same values;
  4. a Taiwan mandatory row with an off-template unit that v3 leaves unread (3.9);
  5. the new warnings (`row_not_read: …`, `serving_line_joined`);
  6. a different decline code for a case both versions decline (for example `multiple_panels` to `too_little_read` or `layout_ambiguous`).

  The test prints every difference with its allow-list item; a difference with no item fails.
- **Gate:** unchanged, so `decline_gate.py`, its exported vectors and the Swift parity tests (v1 tests 1 and 25) are unchanged. Parser v3 calls the gate's own marker and script functions on unbound lines (3.0); it does not copy them.
- **Arithmetic:** checks v2 is checks v1 plus one check, in Swift only, with its own golden vectors; the v1 parity tests against `arithmetic.py` stay and must still pass.

### 5.6 Serving policy `pasted-label-serving-v3` (gate finding 5)

**Method by parser version (closed, an application constant).**

| Manifest `parser_version` | Per-serving stored column | Per 100 g or per 100 ml stored column |
|---|---|---|
| `nutrition-label-text-parser-v2` | `pasted-label-serving-v1` | `pasted-label-serving-v2` |
| `nutrition-label-text-parser-v3` | `pasted-label-serving-v1` | `pasted-label-serving-v3` |
| any other | none | none |

With "none", Confirm offers no servings and no whole pack; at save a pasted-label servings conversion is refused (`sourceServingsRequired`); at reopen a stored servings conversion fails (`integrityFailure`). A v2 conversion on a parser-v3 manifest, or a v3 conversion on a parser-v2 manifest, is refused at save and fails at reopen. `PastedLabelServingPolicy.admittedVersions` becomes exactly `[v1, v2, v3]`.

**What v3 keeps from v2.** n servings are the quantity n × q against the per 100 basis, recorded as a quantity conversion whose method is `pasted-label-serving-v3` and which cites the pasted release and manifest evidence; the basis stays per 100; no unit mismatch (a serving in ml is never converted against per 100 g, nor g against per 100 ml); grams (millilitres) are accepted as for any per 100 basis; a serving size the user corrected or entered is exact by construction and is not scanned; the whole-pack rules of v1 section 2.3 apply, with the printed pack count of 0 never used (3.1 rule 6). The closed word, mark, range-mark and unit lists are **v2's lists, copied as they stand at the freeze**; any later change is serving v4.

**Grammar copy.** The application holds its own copy, `PastedLabelServingSizeGrammarV3` (the application cannot import the parser, v1 decision 10), pinned byte for byte to parser v3 by a parity test:

- label pattern: `(?i)^(?:serving\s+size|portion\s+size|每[一1]?份量)\s*[:：]?\s*(.+)$`
- bracket pattern: `[(（]([^)）]+)[)）]` (as v2)
- quantity pattern: `(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)(?![\p{L}])` (as v2)
- pack phrase pattern (new): `本包裝包?含?\s*約?\s*\d+(?:\.\d+)?\s*份|(?i:servings?\s+per\s+(?:container|pack|package))`

**Steps.**

1. **Source.** The candidate's `serving_size.printed_text`, as stored. For a joined serving line (3.1 rule 3) it is the label line and the quantity line, each trimmed, joined by exactly one ASCII space, and the candidate carries `serving_line_joined`. The policy never re-joins from `pasted_text`.
2. **Value.** The label pattern's capture group. No match: not offered.
3. **Serving and pack on one line.** If the value contains a pack phrase match, the value ends at the start of the first such match, with trailing spaces and the separators `,` `，` `、` `/` `／` removed. Nothing from the pack phrase is part of the serving value.
4. **Quantity.** As v2: the first quantity match inside the first bracketed group of the value, otherwise the first quantity match in the value; its number and unit must equal the recorded `decimal_text` and `unit`, otherwise not offered.
5. **Segment.** As v2 step 3 (start of the value to the end of the quantity, plus at most one tail, tried in v2's order), applied to the value from step 3.
6. **Approximate** when the segment contains anything v2 step 4 lists, **or**, for a bilingual line (the value contains a run of two or more ASCII letters), when **anywhere in the value from step 3** contains one of v2's English words or marks. A bilingual bracket is a gloss: it is ignored for binding (step 4 already binds the bracketed quantity only by position) but trusted for approximation, the conservative side.
7. **Display** as v2 (exact, approximate, range, unmatched).

**Parity test, extended.** Besides pinning the four strings, the fixture set covers joined serving lines, 每1份量, bilingual lines with and without an English "about", serving and pack on one line with 約 in the pack phrase only (stays exact) and in the serving value (approximate); the policy must bind the quantity parser v3 recorded on every fixture line.

**Serving v3 inputs from the last serving v2 review (decided in PR 1, 20 October 2026).** The final review of serving v2 (#277) left three forms open. Serving v2 never reaches users (parser v3 lands before release), so v2 keeps its behaviour on them unchanged, pinned by a test; v3 decides each on the conservative side:

1. **A tilde or wave dash before a piece count.** `30公克～約2片`, `30公克～（2片）` and `30公克～（約2片）` are refused under v2 (the tilde joins the segment as a mark). Under v3, a tilde or wave dash followed by an opening bracket, a 約/about-type word or both, and then a count of something that is not a weight or volume (v2's `countsPieces`), is that count, exactly as the bracket piece-count exception: the segment ends at the quantity, so the serving size is exact. A weight or volume after the tilde is never a count, so `30g ~ 35g` stays a range and `30公克～約35公克` and `30公克～（35公克）` stay approximate. The English form `30g ~ about 2 pieces` is a bilingual value under step 6 (a run of two or more ASCII letters), so its "about" makes it approximate; this is the same outcome step 6 gives `30g (about 2 biscuits)` under v3.
2. **A unit word between a range's low number and its mark.** `25 grams - 30g` is exact under v2 (its range pattern allows at most three characters there). v3's range pattern also allows any listed weight or volume unit there, so `25 grams - 30g` and `25 grams to 30 g` are ranges (no servings), shown as the serving size's own range (25 to 30 g) because "grams" is in the recorded unit family; `1 ounce - 28g` is a range shown as the recorded quantity with the range note.
3. **A range whose other end has no unit.** `30g - 2` shows "30–2 g" under v2. Under v3, when the recorded quantity is the low number, the range is the serving size's own only if the high number carries a unit of the same family (`30g-35g`, `30公克～35公克`); otherwise (`30g - 2`, `30g~35`) Confirm shows the recorded quantity with the range note. The printed pattern of a real range, `25-30g` (the unit printed once, after the high number), is still shown as 25 to 30 g. Either way no servings are offered.

## 6. Architecture notes

- Layers do not change: rules in `NutritionLabelParsing`; the basis choice as an application use-case step, with the options computed by a pure application function (gate finding 9) and the chosen bases passed through the `LabelTextReading` port as an application-owned `AssertedBases` value that the adapter maps; the sheet in presentation, rendering only; the manifest in application.
- `LabelReading` gains `unreadRows` and a `basisNotPrinted` marker per column. No parser type crosses the port (v1 decision 10).
- Layout precedence is a closed ordered list of pure predicates inside the parser, not a protocol per layout (3.0, gate finding 13).
- New decline codes (`flattened_table_ambiguous`, `too_little_read`, `layout_ambiguous`) and the multi-panel copy go through the existing code-to-copy table and its exhaustive test (v1 test 27).

## 7. Safety bar and evaluation

### 7.1 Synthetic fixtures per layout

Every layout in section 3 gets synthetic fixtures with invented values and invented product names, modelled on the shape only; no real label text, number or name enters the repository. At least: decorated titles (each decoration); every serving and pack variant, including the split lines, a split line after the first row, a split line in a stacked table, serving and pack on one line, and a pack count of 0; stacked layout regular, with labels after values at the end, with a label block before a value block, with a template-order break, mixed with inline rows; each flattened-line separator family, with a malformed number, a missing separator, thousands separators (`1,234大卡`, `1，234大卡`, `1 200毫克`), a stray number between rows, `%` on some rows only, an unknown row with the right count and with the wrong count; no basis header with one and two columns, with and without a serving size, with the `%` column, and with one printed and one unprinted amount header; basis in the energy line, in a later row, and on a first row that is not energy; the bracket-says-per-100 fixture whose values are per serving (checks warn); bilingual with agreeing, conflicting and unknown glosses, a conflicting English header, unit pairs that agree and that do not, and "about" in the English serving or pack bracket only; two panels; a specification sheet with interleaved text; a supplement marker and a simplified-only character in an unbound line of each layout.

### 7.2 Mutation tests (gate finding 2)

A mutation suite applies paste-like transformations to every synthetic fixture with known truth. Each mutation belongs to exactly one of two classes, with its own oracle:

- **(a) Structure-breaking** mutations change how the text is laid out, not what it says: drop or duplicate a value; drop a separator; double a decimal point; insert a thousands separator; move a label after its values; move a block of labels before their values; move the serving quantity line elsewhere (must end with the serving size not read); break template order; insert a second basis phrase; insert a line of unrelated text with a number and unit into the table; mix inline and stacked rows; full-width digits. **Oracle: the original truth.** Every value the reader binds must equal the original truth for its row, column, basis and unit; every row the mutation touched must be **not read**, or the table **declined**.
- **(b) Content-changing** mutations change what the label says: swap two row labels in an inline row or a flattened line, so the text now states different values for those rows; change a unit to another valid unit; replace a label with a substring trap (不飽和脂肪, 單元不飽和脂肪酸, 添加糖, 飽和脂肪 inside a longer word); add an English gloss naming another nutrient. **Oracle: the truth of the mutated text** (what a careful reader of the mutated text would record, computed by the fixture generator). Every bound value must equal that truth, or be not read, or the table declined; a substring trap must never be bound to the row it contains.

A single wrong bound value under either oracle fails the suite. The suite also reports how many mutations end as "not read" versus declined, as a measure of burden, not of safety.

**Accepted residual risk, for owner approval (decision 18).** In a stacked table, an exchange of the **value lines** of two adjacent rows that print the same unit, with the labels left in template order (or an exchange between two adjacent optional rows), is indistinguishable from a correct table by structure. The suite contains this mutation with a **pinned expectation**: the reader binds the values in text order (so they differ from the original truth), and the existing energy and sub-row checks warn where their arithmetic is violated. The test fails if that behaviour changes in either direction, so any change is deliberate. The owner's real-text release bar (zero wrong values) still applies to every real label.

### 7.3 Development-set run

The 24-label development set is re-run against each PR's build, outside the repository, with the same method as the 20 October run (section 1.4 governs what stays outside). Into the repository (PR description and a results file of counts) go only: labels, accepted, declined by reason, values matched, wrong, not read, not stated, flags, warnings, correction burden, and basis choices needed. It must keep **zero wrong values** at every PR; the seven labels accepted today must keep every value they read today.

### 7.4 Release check on a fresh set (gate finding 17)

The owner's decision of 20 October 2026 makes this the release gate for parser v3 (it replaces, for Taiwan, the pending v1 section 9 check, which was run on the development set and is now spent).

1. **Freeze and commit the rules first.** In one commit, before any fresh label is collected: the freeze (parser v3, alias table, manifest, serving and checks versions) and a written **selection and eligibility rule** (named sources and listings, the order products are taken in, what makes a label eligible, for example a Taiwan nutrition table present and copyable, and the allowed skip reasons). The commit hash is the freeze reference.
2. **Collect afterwards, by that rule.** At least 24 public Taiwan labels (the development set's size; the bar is at least 20), none from a product in the development set (checked by product name and by text hash, outside the repository). Stratified like the development set: about 15 retailer pages across at least five retailers, 5 manufacturer pages, 4 PDFs. Every skipped candidate is logged with its skip reason; the repository gets only skip counts by reason.
3. **Blind expected values before the run (decision 22).** An independent agent that never sees reader output, the parser source or the development results transcribes the expected values from each label's source screenshot or PDF page into a transcription file. The file's hash and time are recorded (outside the repository, and stated in the PR as "recorded before the run") **before** the reader runs. The owner then verifies each transcription against its source, so the owner's effort stays at checking, not typing; any owner fix is logged as a transcription correction, never as a reader result.
4. **Run once** on the frozen build, CLI and device build, as in v1 section 9. A **run** is one execution of the frozen build over the whole set that produces output for every label. An infrastructure failure (a build, tool or simulator failure that produces no reader output) is rerun with no change to code, inputs or transcription, and recorded; any run that produced reader output counts, and its results stand.
5. **Bar: zero wrong values** in every table that reaches Confirm, compared with the verified transcription, including values from a user-chosen basis when the owner chooses the basis from the label image. Any wrong value stops release; the fix is a new parser version, and the failed set becomes development evidence, so a **new** fresh set is needed for the next release check.
6. **Reported, not gated:** decline rate and reasons; correction burden (values corrected or entered per accepted table, mean and median, and the share needing any); basis choices needed; flags and warnings shown; rows "Printed but not read"; residual errors after the owner's check.

**Statistical limit.** Zero wrong values in roughly 150 checked values bounds the per-value wrong-value rate at about 2% with 95% confidence (rule of three, 3/150), and zero tables with a wrong value in 24 tables bounds the per-table rate at about 12.5% (3/24). The check rules out a frequent failure; it does not prove a zero rate, and the release note must not claim one.

**Target decline rate (non-gating goal):** at most 25% of the fresh set declined (today's development figure is 71%), with a median correction burden of at most 1 value per accepted table. Missing the goal does not block release when the zero-wrong-values bar passes; it is reported and informs the next version.

### 7.5 Contract tests required by the architecture gate

Written first, in the PR that builds their code (section 8):

1. **Flattened digit runs:** every digit run outside a well-formed value, serving, pack or basis token makes its row unread, or declines `flattened_table_ambiguous` outside a row; thousands separators (`,` `，` and a space), stray numbers and `%` on some rows only are covered.
2. **Mutation suite:** class (a) and class (b) oracles as in 7.2, with the stacked same-unit value exchange pinned.
3. **Stacked template order:** an out-of-order mandatory label is the first deviation; optional rows between mandatory ones are accepted; mixed inline and stacked bodies decline `layout_ambiguous`.
4. **Serving-line join:** a split serving or pack line is joined only before the first row label, outside stacked tables and with no `stacked_sequence` unread row; a moved serving quantity leaves the serving size not read.
5. **Serving v3:** the method table (including an unknown parser version: no servings, save refused, reopen fails), the cut at the pack phrase, the joined source string, bilingual approximation scanning, grammar parity on the extended fixtures, and cross-method refusal between v2 and v3.
6. **Gate input coverage:** per layout, a supplement marker or a simplified-only character in a consumed-but-unbound line declines with the existing code; gate code and Python parity unchanged.
7. **Manifest v2 verifier:** `%` headers never in `basis_choices`; mixed printed and chosen amount headers rejected; `offered` must match the options function; the v1 verifier rejects an empty amount header; the Developer tools re-parse with `basis_choices` reproduces the stored candidate.
8. **Chosen-basis provenance:** values keep `user_verified_panel`, the basis is shown "Chosen by you", and a changed basis or record fails at save and at reopen.
9. **Options function:** a pure application function returns the options and their order for one and two unheaded columns, with and without a serving size, in g or ml; presentation renders it without logic.
10. **Manifest versions and contract:** v1 bytes never gain `basis_choices`; v2 decodes through its own path; `minimumContractVersion` for both; cross-route verifier rejection both ways.
11. **Admitted pipelines:** the list is exactly the strings in 5.2.
12. **Non-regression:** every frozen-case difference between parser v2 and v3 is on the allow-list in 5.5, and every case v2 declined that v3 reads passes the truth oracle.
13. **Layout precedence:** a body matching more than one layout predicate, or none, declines `layout_ambiguous`.

And from the gate's low findings: the basis-in-energy-line rule requires energy as the first row, and the per-100 bracket over per-serving values pins a warning (14); `too_little_read` counts only mandatory rows with a cell in the stored column, for every offered basis (15); a conflicting English header declines (16).

## 8. Phasing into PRs

Each PR runs the full validation gates, adds its ledger row to `DEVELOPMENT_NOTES.md`, reports the dev-set counts (7.3), passes the non-regression test (5.5), and carries the checklist item of section 1.4.

1. **Lines before the table, aliases, the unit rule and layout precedence.** 3.0, 3.1, 3.9, section 4, the zero pack count, `pasted-label-serving-v3` with its method table and grammar parity test, the admitted pipeline entry, golden fixtures for parser-v2 and parser-v3 manifests. Tests 4, 5, 6, 11, 12, 13. Small and highest value: label 16 reads in full and two accepted labels gain rows.
2. **Partial reading and the stacked layout.** 3.2, 3.8, `too_little_read`, "Printed but not read" on Confirm (port, view model, copy), and the mutation suite as a standing test. Tests 2, 3, 15.
3. **Flattened lines, basis in the energy line, bilingual.** 3.4, 3.5, 3.6, `flattened_table_ambiguous`, the two-panel copy (3.7). Tests 1, 14, 16, and test 2 extended.
4. **Basis choice.** 3.3, manifest v2, verification, the options function, the sheet, "Chosen by you" and Change, the contract-version check (decision 13), and checks v2 (decision 5). Tests 7, 8, 9, 10. Needs its own architecture gate pass and a simulator journey.
5. **Freeze and release check.** The freeze and selection-rule commit, then section 7.4, the results file of counts, and the `docs/releases/unreleased.md` row.

PRs 2 and 3 change the parser only and can ship in either order after PR 1; PR 4 is the only persisted-format change. No build carrying any of PRs 1 to 4 is distributed before the freeze (5.1).

### 8.1 PR 1 as built

Recorded so later PRs and the release check start from what PR 1 actually does. Each point either follows from the rules above or narrows them on the conservative side; none widens what is read.

- **Parser v2 stays, unchanged.** The frozen evaluation contract (`Tools/NutritionLabelCaptureEvaluation/frozen-contract-v1.json`) pins the bytes of parser v2's source, the candidate and the `NutritionLabelTextParse` CLI, so parser v3 is a separate type (`NutritionLabelTextParserV3`) beside it. The reader adapter runs v3; v2 remains the evaluation reference and the baseline of the non-regression test (5.5), which compares v3 with v2's frozen candidates in the parity vectors. On all 314 frozen cases the two candidates are identical.
- **Layout precedence in PR 1** lists inline and stacked (3.0). Inline is v2's shape: every label line with values carries one row label (a recognised row label after the first value makes the line two rows), and a value-only line only continues a row whose label line carried values. Stacked is any body with label-only and value-only lines and no label line with values. The flattened layout (3.4) is appended by PR 3; until then a one-line table matches no layout and declines `layout_ambiguous`. Until PR 2 adds the sequence rule and template order (3.2), a stacked body is bound as parser v2 binds it. A body with no values at all keeps v2's `no_table`.
- **Titles.** A bracket group after the Chinese title that holds a digit or a basis phrase is not decoration (it is read as v2 reads it), so a title never swallows a basis.
- **Row markers.** A line starting with `*` before a Han character is a row only when what follows is a recognised row (alias or English table); otherwise it stays a footnote, as in v2. A marker counts as indentation only where indentation decides anything (unrecognised and English rows): a row matched in the alias table takes exactly the table's parent, so a bullet on every row never makes 蛋白質 or 鈉 a child of the row above.
- **Split lines.** A split pack line (本包裝含, then `N份`) joins under the same conditions as the serving line and carries the same `serving_line_joined` warning. A serving or pack label standing alone after the first row is not read, and its quantity line, if next, is consumed unbound so it can never become a row's value.
- **Gate input coverage** scans titles, rule lines, footnotes, header segments without a basis, extra serving and pack lines, unjoined split lines, rows printed without values and rows left unread.
- **Taiwan unit rule.** The rule applies to the units the row already allows (a unit outside them still declines `unrecognised_unit`, as in v2). An energy row printed in kJ, alone or beside 大卡, is not read (`row_not_read: unit_off_template: 熱量`); its G3 flag is shown and nothing is calculated from it. For a new Taiwan reading this replaces v1's kJ to kcal calculation on a kJ-only energy row (the rule `kj_to_kcal_v1` itself is unchanged, and stored entries keep their calculated values); the owner may wish to confirm this reading of decision 10 before the freeze.
- **Zero pack count.** Confirm shows "Printed as 0, so whole pack is not offered." beside a printed count of 0; the whole-pack rule already required a count above 0.

## 9. Owner decisions

The owner answered decisions 1 to 17 "yes to all", in session, on 20 October 2026, after the architecture gate. Where the gate tightened a decision's wording without changing its direction, the decision is recorded below in the revised wording and marked **(tightened)**. Parts of the revision that are genuinely new are split out as decisions 18 to 22; the owner approved them, in session, on 20 October 2026.

### 9.1 Decided (owner, in session, 20 October 2026)

1. **Document form.** Reader v3 is a separate versioned document that composes with v1, rather than an amendment section in v1. **Decided: yes (owner, 20 Oct 2026).**
2. **Partial reading (tightened).** A row whose binding is in doubt is "Not read" on Confirm, with its printed text listed under "Printed but not read", instead of the whole table declining; a stacked table stops reading at its first deviation, and a break of the official template order (熱量, 蛋白質, 脂肪, 飽和脂肪, 反式脂肪, 碳水化合物, 糖, 鈉, optional rows allowed between) counts as a deviation. **Decided: yes (owner, 20 Oct 2026).** (Mixed inline and stacked tables: decision 21.)
3. **Too little read (tightened).** A table with fewer than 5 of the 8 Taiwan mandatory rows read declines `too_little_read`; a row counts as read only when it has a cell in the stored column, for every basis the sheet would offer, and a calculated value does not count. **Decided: yes (owner, 20 Oct 2026).**
4. **Basis choice (tightened).** For value columns with no basis header, the user chooses the basis on a sheet before Confirm (no preselection, "I'm not sure" goes back), with the options computed by a pure application function, recorded in manifest `pasted-nutrition-label-v2`, instead of declining; a `%` column is never a choice, and a table with some printed and some missing amount headers still declines `no_basis_header`. **Decided: yes (owner, 20 Oct 2026).**
5. **Basis plausibility warning.** An option implying more than 100 g of macronutrients or 900 kcal per 100 g carries a warning, never a block, as `label-arithmetic-checks-v2`, Swift-only with its own golden vectors, used for manifest v2 readings. This settles decision 5 before PR 4, as the gate required. **Decided: yes (owner, 20 Oct 2026).**
6. **One-line tables (tightened).** A flattened line is read only when its segmentation is unambiguous; every digit run must belong to a well-formed value, serving, pack or basis token (thousands separators, stray numbers and `%` on some rows only included); a malformed token makes only its own row unread, and a malformed token outside any row declines `flattened_table_ambiguous`. **Decided: yes (owner, 20 Oct 2026).**
7. **Bilingual tables (tightened).** The Chinese label and header decide each row and column; a conflicting English gloss makes the row unread; a conflicting English header declines; an English bracket is ignored for binding but scanned for approximation, so "about" in either language makes **both the serving size and the pack count** approximate. **Decided: yes (owner, 20 Oct 2026).**
8. **Two panels.** Keep declining in v3 with the new "delete the ones you did not eat" copy; a panel chooser is later work. **Decided: yes (owner, 20 Oct 2026).**
9. **Alias table.** `taiwan-row-aliases-v1` as in section 4, with 醣類 held out until it is seen in real text. **Decided: yes (owner, 20 Oct 2026).**
10. **Taiwan unit rule (tightened).** A mandatory Taiwan row printed in a unit other than the template's is unread; together with the template order of decision 2 it bounds the stacked layout's misbinding. **Decided: yes (owner, 20 Oct 2026).**
11. **Gate unchanged.** `label-capture-decline-gate-v2` and its Python parity stay untouched; every new rule is in the parser, which calls the gate's own marker and script functions on consumed-but-unbound lines. **Decided: yes (owner, 20 Oct 2026).**
12. **Serving v3 (tightened: written out in full).** `pasted-label-serving-v3` exactly as section 5.6 states it: its own application grammar copy pinned to parser v3, the joined-line source string, the cut at the pack phrase, bilingual approximation scanning, v2's closed lists copied at the freeze, and a closed parser-version table under which an unknown parser version offers no servings, is refused at save and fails reopen. **Decided: yes (owner, 20 Oct 2026).**
13. **Contract version (tightened).** Contract 7 covers both manifest versions if, when PR 4 merges, no distributed build carries contract 7, where "distributed" means any TestFlight or App Store build or any install on a device used with real food data; otherwise manifest v2 needs contract 8. PR 4 records the check. **Decided: yes (owner, 20 Oct 2026).**
14. **Version freeze (tightened).** Parser v3 accumulates across PRs 1 to 4 and is frozen at the earlier of the release check's freeze commit and the first distribution of a build carrying parser v3 or serving v3; no such distribution happens before the freeze. **Decided: yes (owner, 20 Oct 2026).**
15. **Fresh release set (tightened).** At least 24 labels, stratified as in 7.4, collected after a commit that freezes the reader and writes down the selection and eligibility rule, with skip reasons logged; run once, a run being defined as in 7.4; zero wrong values; a failure spends the set; the statistical limit is stated in reporting. **Decided: yes (owner, 20 Oct 2026).** (Who transcribes the expected values, and when: decision 22.)
16. **Decline goal.** A non-gating goal of at most 25% declined and a median correction burden of at most 1 value per accepted table on the fresh set. **Decided: yes (owner, 20 Oct 2026).**
17. **Zero pack count.** A printed 0 servings per pack is read as printed, never used for whole pack, and Confirm says so. **Decided: yes (owner, 20 Oct 2026).**

### 9.2 Added by the revision (owner, in session, 20 October 2026)

18. **Accepted residual risk.** Accept that, in a stacked table, an exchange of the value lines of two adjacent rows printing the same unit (labels still in template order), or of two adjacent optional rows, cannot be detected by structure; the reader's behaviour on it is pinned by a test (7.2), and the existing checks warn where their arithmetic is violated. *Recommendation: yes.* **Decided: yes (owner, 20 Oct 2026).**
19. **Layout precedence.** Classify each table body into exactly one of inline, stacked or flattened by a closed ordered list of predicates inside the parser, declining `layout_ambiguous` when more than one or none matches (3.0). *Recommendation: yes.* **Decided: yes (owner, 20 Oct 2026).**
20. **Real-text privacy.** For the development and fresh sets, keep texts, screenshots, expected values, per-label results and **text hashes** outside the repository (stricter than v1 section 9, which allowed hashes), with tools writing only outside the repository and a checklist item in every PR (1.4). *Recommendation: yes.* **Decided: yes (owner, 20 Oct 2026).**
21. **Mixed inline and stacked tables.** Decline a table body in which some rows are inline and others stacked (`layout_ambiguous`), because the inline rows prove nothing about the order of the stacked ones; parser v2's kJ and kcal continuation stays inline (3.2 rule 5). *Recommendation: yes.* **Decided: yes (owner, 20 Oct 2026).**
22. **Blind transcription.** Expected values for the fresh set are transcribed, before the run, by an independent agent that never sees reader output, the parser source or the development results, from each label's source screenshot or PDF page; the transcription file's hash and time are recorded before the run (outside the repository; the PR states only that it was recorded); the owner then verifies each transcription against its source, and any owner fix is logged as a transcription correction (7.4 item 3). *Recommendation: yes.* **Decided: yes (owner, 20 Oct 2026).**

## 10. Not changing

- v1's journey, Confirm, origins, corrections, conversions, arithmetic checks v1, privacy and egress (no egress at all), the release note form, and the rule that Log is the only save.
- Gate v2 and its Python parity (decision 11); format inference v1; the candidate schema.
- UK and US layouts: still declined by the launch scope. Full-width digits still decline (v1 section 1).
- Every stored manifest, record and archive: they decode, verify and re-encode unchanged.

## 11. Architecture gate findings applied (20 October 2026, on `3ccd9f24`)

| Severity | Finding | Where |
|---|---|---|
| High | 1. Digit runs in flattened lines; thousands separators, stray numbers, partial `%` | 3.4 rules 2 to 6; test 1 |
| High | 2. Mutation oracles (structure-breaking, content-changing); pinned residual risk | 7.2; test 2; decision 18 |
| High | 3. Stacked template order; mixed inline and stacked tables decline | 3.2 rules 2 and 5; test 3; decisions 2 and 21 |
| High | 4. Serving-line join conditions; moved quantity not read | 3.1 rule 3; test 4 |
| High | 5. Serving v3 written in full; bilingual approximation for the serving size | 5.6; 3.6 rule 5; test 5; decisions 7 and 12 |
| Medium | 6. Gate input coverage on unbound lines | 3.0; test 6 |
| Medium | 7. Manifest v2 verifier: `%`, mixed headers, v1 empty header, Developer tools re-parse, `AssertedBases` | 3.3; 5.3; 6; test 7 |
| Medium | 8. Chosen-basis provenance stated | 3.3; 5.3; test 8 |
| Medium | 9. Options computed in the application | 3.3 item 2; 6; test 9 |
| Medium | 10. "Distributed" defined; separate v2 decode path; contract and cross-route tests | 5.1; 5.3; test 10; decision 13 |
| Medium | 11. Exact admitted pipeline strings; decision 5 before PR 4 | 5.1; 5.2; test 11; decision 5 (decided) |
| Medium | 12. Non-regression allow-list and truth oracle | 5.5; test 12 |
| Medium | 13. Closed layout precedence; multiple matches decline | 3.0; 6; test 13; decision 19 |
| Medium | 17. Fresh-set protocol: committed rule, blind transcription, run definition, statistical limit | 7.4; decisions 15 and 22 |
| Medium | 19. No distribution of parser or serving v3 before the freeze | 5.1; 8; decision 14 |
| Low | 14. Energy as first row for the basis bracket; warning fixture | 3.5; 7.5 |
| Low | 15. Definition of "read" for `too_little_read` | 3.7; 7.5; decision 3 |
| Low | 16. Chinese header decides; conflicting English header declines | 3.6 rule 1; 7.5; decision 7 |
| Low | 18. Real-text privacy enforcement; format inference stays v1 | 1.4; 3.6 rule 6; 5.1; decision 20 |
