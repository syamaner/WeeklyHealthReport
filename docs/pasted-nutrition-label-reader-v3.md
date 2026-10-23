# Pasted nutrition label reader v3 (#93)

Status: **owner-approved, 20 October 2026.** The owner answered decisions 1 to 17 "yes to all", in session, on 20 October 2026, after the architecture gate, and approved decisions 18 to 22, which the gate revision added, in session the same day. It is a versioned amendment to the reader behind the pasted nutrition label route of [pasted nutrition label v1](pasted-nutrition-label-v1.md) so that it reads the common real Taiwan paste layouts that parser v2 declines today. It follows the owner's decision of 20 October 2026, in session: improve the reader against a real-text development set, then run the release check once on a **fresh** set of at least 20 real labels the reader has never seen.

**Frozen, 21 October 2026 (section 12):** parser v3, `taiwan-row-aliases-v1`, checks v2, serving v3 and manifest v2 are frozen as of the commit that adds section 12, which also commits the fresh-set protocol (12.2). Any later change to them is a new version and needs a new fresh set.

**PR 4 design (section 8.4), 20 October 2026:** written for its own architecture gate pass before any PR 4 production code; decisions 24 to 26 (section 9.4) were made by the owner in session the same day.

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
2. The options and their order are computed in the application by one pure, tested function from the reading (number of unheaded amount columns, serving size read or not, its unit), not in presentation, which only renders them (gate finding 9). Before Confirm, a short sheet asks: "These values have no column heading. What are they for?" with **Per serving (printed serving size, for example 25 g)**, **Per 100 g**, **Per 100 ml**, and **I'm not sure**. For two amount columns it offers the official template's arrangements only: "Per serving, then per 100 g" and "Per serving, then per 100 ml"; any other arrangement is not offered. No option is preselected. "I'm not sure" returns to the label text screen with the text kept and a link to Search. (PR 4: the closed option table, the `offered` encoding and the lifecycle are in 8.4.3 and 8.4.9.)
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

**Superseded by decision 23 (owner, 20 October 2026).** Building PR 3 showed that a per 100 g bracket over values that are all per serving passes every check, so the rule above would store such a table per 100 g with nothing on Confirm to say so. The owner decided to ask the user instead: a basis printed only inside the energy line is **never** taken as the column's basis. Under the conditions above (no header line, energy first, exactly one bracketed basis phrase) the table has no basis header, so it is the case of 3.3: it declines `no_basis_header` (today's copy) until PR 4, and from PR 4 the user chooses the basis on the sheet. The parser carries the bracket as printed in the warning `basis_hint: energy_line: <bracket>` on the declined candidate, so the sheet may show "The label's energy line says 每100公克" as a hint; the hint is never preselected and never decides the basis. A basis phrase on any other row, on a first row that is not energy, or more than one, still declines `multiple_panels`.

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
2. **Too little read: decline.** New parser decline `too_little_read` when fewer than 5 of the 8 Taiwan mandatory rows are read (energy, protein, fat, saturated fat, trans fat, carbohydrate, sugars, sodium). A mandatory row counts as **read** only when it has a cell in the column that would be stored (v1 section 6.3); for an unheaded table that is evaluated for each basis the sheet would offer, and the table declines only if it fails for every option (gate finding 15; PR 4 narrows this to "for any option", which coincides under the option table, 8.4.7). A calculated value does not count. Copy: "Only a few values could be read from this text. Try copying the table again, or use Search or Barcode." The threshold is "more than half"; decision 3.

**Changes.** Copy only for two panels (parser v2 already declines it); parser only for `too_little_read` (a new code, mapped to copy).

### 3.8 Partial reading: a row is not read instead of the table being declined

Several rules above (3.2, 3.4, 3.6, 3.9) make a **row** unread rather than declining the table. This is the "partial reading" extension that v1 section 8.5 anticipated. It fits the v1 model without new persisted formats:

- An unread mandatory row has no cells, so gate v2 raises its existing G3 (`required_row_missing`) and Confirm shows the existing "Not read: <row>. Add it, or leave it unknown." The user enters it ("Entered by you") or leaves it unknown.
- A row unread in one column only (a malformed value in one column of a two-column row) is unread in **both** columns (section 3.4, rule 5), so the stored column never mixes a read value with an unread sibling from the same row.
- The parser records each unread row as a candidate warning `row_not_read: <reason>: <printed label>` (reasons: `stacked_sequence`, `malformed_value`, `unit_off_template`, `gloss_conflict`, `unit_pair_mismatch`). The manifest already stores candidate warnings verbatim. The application's `LabelReading` gains a list of unread rows for the "Printed but not read" section; this is an in-memory port change, not a stored one.
- `wouldMarkReady` stays false for any candidate with a `row_not_read` warning; in the product it has no effect on Log.

### 3.9 Taiwan unit rule (new safety rule)

The Taiwan template fixes each mandatory row's unit: energy in 大卡 (kcal), sodium in 毫克 (mg), the rest in 公克 (g). Parser v2 accepts g, mg or µg on any non-energy row. **Rule (parser v3, Taiwan only):** a mandatory row whose value unit is not the template unit is not read (`unit_off_template`). Optional rows keep parser v2's unit sets. **Energy (clarification, 20 October 2026, consistent with v1 decision 6; no new owner decision):** kJ is an accepted energy unit with the versioned `kj_to_kcal_v1` conversion, so the rule reads an energy row printed in 大卡/kcal, in kJ or in both. A kJ-only row is read and its kcal calculated exactly as under v1 (calculated, labelled, and a day total that includes it is marked as including estimates); with both printed, on one row or with the kJ on the next line, the kcal cell is stored and the kJ cell is read but not used, never both. Other energy units (for example `Cal`) are off-template. The rule exists to stop a required row binding a value in a wrong unit, which kJ on the energy row is not. This turns the most damaging misbinding (a gram value bound to sodium, or a milligram value bound to a gram row) into an unread row, and it is what makes the stacked rule (3.2) tolerable.

### 3.10 Summary

| Class (dev labels) | v3 outcome on the dev set (development evidence only) | Change |
|---|---|---|
| Lines before the table (16, and part of 05, 09, 10, 17, 19, 21 to 23) | 16 read in full | Parser; serving v3 (persisted method string) |
| One value per line (21, 22, 23) | Confirm, with 2 or 3 rows "Not read" each and the serving size not read (split serving lines are not joined in stacked tables, 3.1 rule 3) | Parser |
| No basis header (05, 09, 10) | Confirm after the user chooses the basis | **Persisted**: manifest v2 |
| One line (06, 08, 12, 13, 14, 19) | Confirm; 12 with two rows "Not read" (a malformed value and a missing separator) | Parser; new decline code |
| Basis in the energy line (20) | Confirm after the user chooses the basis, with the energy line's phrase as a hint (decision 23); declined `no_basis_header` until PR 4 | Parser; the hint is shown by PR 4's sheet |
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

**Parser v3 accumulates across PRs until it is frozen.** As with serving v2 (v1 section 6.3), a version that no distributed build carries can still be amended. It is frozen at the earlier of the release check's freeze commit (section 7.4) and the **first distribution** of any build carrying parser v3 or serving v3 (gate finding 19). "Distribution" means any TestFlight or App Store build, or any install on a device used with real food data, including the owner's own phone. No such build may carry parser v3 or serving v3 before the freeze; if one must, the freeze happens at that commit. After the freeze any change is parser v4 (or serving v4). **Frozen on 21 October 2026, before any distribution: section 12.**

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
- **Developer tools** re-parse a v2 entry with its `basis_choices` passed as asserted bases, so the re-parse reproduces the stored candidate; a v1 entry is re-parsed with none. (Deferred to issue #273 by decision 25; PR 4 pins the reproduction at the adapter, 8.4.6.)
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

1. **A tilde or wave dash before a piece count.** `30公克～約2片`, `30公克～（2片）` and `30公克～（約2片）` are refused under v2 (the tilde joins the segment as a mark). Under v3, a tilde or wave dash followed by an opening bracket, a 約/about-type word or both, and then a count of something that is not a weight or volume (v2's `countsPieces`), is that count, exactly as the bracket piece-count exception: the segment ends at the quantity, so the serving size is exact. A weight or volume after the tilde is never a count, so `30g ~ 35g` stays a range and `30公克～約35公克` stays approximate. In `30公克～（35公克）` the bracketed 35 公克 is the quantity both grammars bind first, so a recorded 30 公克 does not match: the serving size is unmatched and no servings are offered, under v2 and v3 alike. The English form `30g ~ about 2 pieces` is a bilingual value under step 6 (a run of two or more ASCII letters), so its "about" makes it approximate; this is the same outcome step 6 gives `30g (about 2 biscuits)` under v3.
2. **A unit word between a range's low number and its mark.** `25 grams - 30g` is exact under v2 (its range pattern allows at most three characters there). v3's range pattern also allows any listed weight or volume unit there, so `25 grams - 30g` and `25 grams to 30 g` are ranges (no servings), shown as the serving size's own range (25 to 30 g) because "grams" is in the recorded unit family; `1 ounce - 28g` is a range shown as the recorded quantity with the range note.
3. **A range whose other end has no unit.** `30g - 2` shows "30–2 g" under v2. Under v3, when the recorded quantity is the low number, the range is the serving size's own only if the high number carries a unit of the same family (`30g-35g`, `30公克～35公克`); otherwise (`30g - 2`, `30g~35`) Confirm shows the recorded quantity with the range note. The printed pattern of a real range, `25-30g` (the unit printed once, after the high number), is still shown as 25 to 30 g. Either way no servings are offered.

## 6. Architecture notes

- Layers do not change: rules in `NutritionLabelParsing`; the basis choice as an application use-case step, with the options computed by a pure application function (gate finding 9) and the chosen bases passed through the `LabelTextReading` port as an application-owned `AssertedBases` value that the adapter maps; the sheet in presentation, rendering only; the manifest in application.
- `LabelReading` gains `unreadRows` and (PR 4, 8.4.1) an optional `UnheadedTable` in place of the `basisNotPrinted` marker per column. No parser type crosses the port (v1 decision 10).
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

The owner's decision of 20 October 2026 makes this the release gate for parser v3 (it replaces, for Taiwan, the pending v1 section 9 check, which was run on the development set and is now spent). **The executable protocol is section 12.2**, committed with the freeze; where it is more specific than the items below, it governs.

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

And from the gate's low findings: the basis-in-energy-line rule requires energy as the first row, and the per-100 bracket over per-serving values pins a warning (14; superseded by decision 23: the bracket is a hint and the table declines `no_basis_header` until the user chooses); `too_little_read` counts only mandatory rows with a cell in the stored column, for every offered basis (15); a conflicting English header declines (16).

## 8. Phasing into PRs

Each PR runs the full validation gates, adds its ledger row to `DEVELOPMENT_NOTES.md`, reports the dev-set counts (7.3), passes the non-regression test (5.5), and carries the checklist item of section 1.4.

1. **Lines before the table, aliases, the unit rule and layout precedence.** 3.0, 3.1, 3.9, section 4, the zero pack count, `pasted-label-serving-v3` with its method table and grammar parity test, the admitted pipeline entry, golden fixtures for parser-v2 and parser-v3 manifests. Tests 4, 5, 6, 11, 12, 13. Small and highest value: label 16 reads in full and two accepted labels gain rows.
2. **Partial reading and the stacked layout.** 3.2, 3.8, `too_little_read`, "Printed but not read" on Confirm (port, view model, copy), and the mutation suite as a standing test. Tests 2, 3, 15.
3. **Flattened lines, basis in the energy line, bilingual.** 3.4, 3.5, 3.6, `flattened_table_ambiguous`, the two-panel copy (3.7). Tests 1, 14, 16, and test 2 extended.
4. **Basis choice.** 3.3 (including the energy-line hint of decision 23, shown on the sheet and never preselected), manifest v2, verification, the options function, the sheet, "Chosen by you" and Change, the contract-version check (decision 13), and checks v2 (decision 5). Tests 7, 8, 9, 10. Needs its own architecture gate pass and a simulator journey.
5. **Freeze and release check.** The freeze and selection-rule commit (5a, section 12), then section 7.4 under 12.2, the results file of counts, and the `docs/releases/unreleased.md` row (5b).

PRs 2 and 3 change the parser only and can ship in either order after PR 1; PR 4 is the only persisted-format change. No build carrying any of PRs 1 to 4 is distributed before the freeze (5.1).

### 8.1 PR 1 as built

Recorded so later PRs and the release check start from what PR 1 actually does. Each point either follows from the rules above or narrows them on the conservative side; none widens what is read.

- **Parser v2 stays, unchanged.** The frozen evaluation contract (`Tools/NutritionLabelCaptureEvaluation/frozen-contract-v1.json`) pins the bytes of parser v2's source, the candidate and the `NutritionLabelTextParse` CLI, so parser v3 is a separate type (`NutritionLabelTextParserV3`) beside it. The reader adapter runs v3; v2 remains the evaluation reference and the baseline of the non-regression test (5.5), which compares v3 with v2's frozen candidates in the parity vectors. On all 314 frozen cases the two candidates are identical.
- **Layout precedence in PR 1** lists inline and stacked (3.0). Inline is v2's shape: every label line with values carries one row label (a recognised row label after the first value makes the line two rows), and a value-only line only continues a row whose label line carried values. Stacked is any body with label-only and value-only lines and no label line with values. The flattened layout (3.4) is appended by PR 3; until then a one-line table matches no layout and declines `layout_ambiguous`. Until PR 2 adds the sequence rule and template order (3.2), a stacked body is bound as parser v2 binds it. A body with no values at all keeps v2's `no_table`.
- **Titles.** A bracket group after the Chinese title that holds a digit or a basis phrase is not decoration (it is read as v2 reads it), so a title never swallows a basis.
- **Row markers.** A line starting with `*` before a Han character is a row only when what follows is a recognised row (alias or English table); otherwise it stays a footnote, as in v2. A marker counts as indentation only where indentation decides anything (unrecognised and English rows), and only after a marker-free top-level row: a row matched in the alias table takes exactly the table's parent, and bullets on every row never chain one row under another (蛋白質 under 熱量, or English saturates under fat).
- **Split lines.** A split pack line (本包裝含, then `N份`) joins under the same conditions as the serving line. Each joined line carries one warning, at most once: `serving_line_joined` for the serving line (the string of rule 3) and `serving_line_joined: servings_per_pack` for the pack line. Both are visible: Confirm shows "Read from two lines of the label. Check the serving size." (or "… Check the servings per pack.") on the row and in the warnings, and they are recorded in `warnings_shown` (as `serving_line_joined:serving_size` and `serving_line_joined:servings_per_pack`) and in the misread report. A serving or pack label standing alone after the first row is not read, and its quantity line, if next, is consumed unbound so it can never become a row's value.
- **Gate input coverage** scans titles, rule lines, footnotes, header segments without a basis, extra serving and pack lines, unjoined split lines, rows printed without values and rows left unread, and also the bound serving and pack lines (the gate scans the serving line for markers but not the pack line).
- **"More than".** A value printed with `>`, `≥`, `＞`, `≧`, 超過, 大於, 多於 or "more than" before its number cannot be held by the reader (it has no such comparator), so the row that would receive it is not read (`row_not_read: malformed_value: <label>`, the reason of 3.8), on a label line or a value-only line, stacked or inline. `>` and `>>` are row markers only when a row label follows them, never before a number. The mark may stand apart from its value: after the row label (`鈉 超過`, `鈉 >`, `Sodium more than`) or on a line of its own (`超過`, `>`, `more than`); either way the row it qualifies (or, before any row, the next row) is not read. A trailing 以上 ("at least") is treated the same way.
- **Bound words.** ≦ and a 以下 printed after a value are "at most" (`<=`), and 未滿 before a value is "less than" (`<`), so these values reach Confirm as bounds, never as exact values; the 以下 stays in the cell's printed text. Parser v2 read `5 毫克 以下` as exact 5. This is item 8 of the non-regression allow-list (none of the 314 frozen cases has these words).
- **Unexplained bounds (the structural rule behind the two bullets above).** A closed bound vocabulary: more-than marks `>` `≥` `＞` `≧` 超過 大於 多於 以上 "more than" "over" "at least", and less-than marks `<` `≤` `＜` `≦` 未滿 少於 以下 "less than" "under" "up to". The marks are matched after whitespace and ASCII and full-width brackets are removed, so `以 上`, `（以上）` and `( 以下 )` match. English words are matched as whole words.
  - **A row's span** is its label line, its value lines and every other line up to the next **recognised** row label (alias or English table, markers removed). That includes mark-only lines, wrapped lines, footnotes, note lines and unrecognised rows: only a recognised row label ends a span, and the non-regression test's span helper uses the same rule. The span's lines are tokenised joined, so a mark split over lines (`以` then `上`, `More` then `than`) counts.
  - **Lines carrying a token.** A line that carries a token not explained by a recognised bound on values it gave a row, and that does not become a recognised row (a mark line, a junk row such as `以上*`, `以上 糖`, a note, a footnote), leaves the rows on both sides unread. A note's or footnote's values are never cells, so they explain nothing. Before the first row, such a line straight after a serving or pack line (printed or joined) leaves that line not read, and the first row unread.
  - **Wrapped labels (fifth review).** A row label wrapped over two lines and merged by the parser (`飽和` then `脂肪 1公克`, `of which` then `saturates 1g`) is a span boundary: the wrapped row's span starts at its label lines, so a token after it or on its merged line leaves that row unread, never the row above. The non-regression span helper treats wrapped labels the same way.
  - **Value lines.** A value line of a recognised row that carries a mark (`脂肪` then `>3公克`) is charged to that row only; the next plain row still reads.
  - **Known limit, accepted:** an English footer line after the table holding "under" or "up to" (for example "Suitable for children under 3") is a non-row line in the last row's span, so it leaves the last row unread. This is the conservative side; Taiwan is the only launch scope.
  - **Vocabulary additions (fourth review):** `↑` `﹥` `⩾` and "or more" (more-than), `↓` `﹤` `⩽` and "or less" (less-than); none of them is a recognised cell bound. Note lines also start with "Notes".
  - **The rule.** If the span holds any token that is not a recognised bound consumed on one of the row's own cells, the whole row is not read (`row_not_read: unexplained_bound: <label>`). The recognised bounds are `<`, `≤`, `≦`, `＜`, 未滿, 少於, "less than" before a value, and 以下 straight after it.
  - **Orphan lines.** A line holding only marks between two rows makes both rows unread.
  - **Row markers.** A leading row marker (`>`, `>>` before a label) is a marker, not a bound.
  - **Serving and pack lines.** The same applies: any token makes the serving size or pack count not read, including `本包裝含8份以下`.
  - **Allow-list.** Non-regression allow-list item 8 is narrowed to rows whose own span carries such a token or that carry the duplicate-row warning, to cells whose printed 以下, ≦ or 未滿 now make them a bound, and to serving and pack lines that carry a token.
- **Note lines** starting with 註, 備註, 說明 or "Note" are never rows: they are unbound and gate-scanned. As non-row lines they are in the previous row's span, so a bound word in a note (`註：鈉 5毫克以下以0標示`) leaves that row unread.
- **Serving size and pack count printed as "more than"** (`每份量 超過30公克`, `30公克以上`, `本包裝含超過8份`, `8份以上`, "servings per container more than 8") are not read: the serving size keeps its printed text with no quantity (no servings), and the pack count is not read (G6 flag).
- **Duplicate rows.** Two rows binding the same nutrient in the same column (for example a `*鈉` row before the real 鈉 row) are both not read (`row_not_read: duplicate_row: <label>`), so the row's G3 flag shows on Confirm; the reader never picks one.
- **English top-level rows** (energy, fat, carbohydrate, protein, sodium, salt, fibre) stay top-level however they are marked, as alias rows do.
- **Han text between values** is two rows on one line (`脂肪 10公克 其中飽和脂肪 3公克`, which parser v2 binds as fat per 100 g = 3 g): the body matches no layout and declines `layout_ambiguous`. There is no substring alias matching. Han text after the last value is not a second row. This is item 7 of the non-regression allow-list in the test (a case v2 read and v3 declines for this rule); none of the 314 frozen cases has it.
- **Repeated rows.** A `*` line naming a row that is already read (a reference footnote such as `*鈉 2000毫克` after the table) is a footnote, gate-scanned, never a second row.
- **Taiwan unit rule.** The rule applies to the units the row already allows (a unit outside them still declines `unrecognised_unit`, as in v2). Energy reads kcal or kJ as clarified in 3.9 (consistent with v1 decision 6), so kJ-only and kcal-plus-kJ rows read exactly as under v1; any other energy unit is not read (`row_not_read: unit_off_template: 熱量`).
- **Zero pack count.** Confirm shows "Printed as 0, so whole pack is not offered." beside a printed count of 0; the whole-pack rule already required a count above 0.

### 8.2 PR 2 as built

Recorded the same way. Every rule of 8.1 stays; each point below follows from 3.2, 3.7 and 3.8 or narrows them on the conservative side.

- **Carried over from the final review of PR 1.**
  - **Duplicate rows** are counted over every row with a recognised label, read or not: a row left unread for a bound, a malformed value, a stacked deviation or a missing value still names its nutrient, so a later row of the same nutrient is never read in its place (`脂肪 10公克 以上` then `脂肪 1公克` leaves fat unread, `row_not_read: duplicate_row`). When the whole label is not recognised, its first word or its leading Han run is looked up exactly (never as a substring), so `脂肪 abc公克` still names fat and 不飽和脂肪 never does. An energy row names its kcal or kJ key by the units printed, or both when it prints neither.
  - **A value printed before its label** on a value-only line (`>1公克 飽和脂肪`, `1公克 飽和脂肪`) is never attached to the row above, because the value belongs to the label after it. The line is consumed unbound (gate-scanned) and the label is listed as `row_not_read: value_before_label: <text>`. Bound words and marks after a value (`2 or less`, `1公克 以上`) are not a label.
- **Stacked sequence (3.2).** A row of a stacked table is regular when its label stands on one line (a label wrapped over two lines counts as one only when the merged label is a recognised row), its value lines each hold exactly one value, it has exactly one amount per amount column and, when a reference-intake column is printed, either no percentage or one per reference column. Values are bound by unit, so a percentage can never be taken for an amount. The first row that is not regular, or that breaks the template order (a mandatory row coming after a row it should precede, or repeating one; optional, not-stored and unrecognised rows may stand anywhere), and every row after it are not read (`row_not_read: stacked_sequence: <label>`); their lines are gate-scanned. This covers a label followed directly by another label, a dropped or duplicated value, values after the last label, a label at the end with no values, the last labels printed after their values (the values overflow the row above, which is then the first deviation) and a label block before its value block.
- **Two narrow regular forms, from the frozen cases.** An energy row may print its values in kJ, in kcal, or in both, one per line, as parser v2 groups energy by unit: one value per amount column in each unit printed (`506kJ`, `1686kJ`, `121大卡`, `403大卡` for two columns). A line holding only `*` after a stacked row's values stands for that row's reference intake, as the Taiwan template prints for rows without a percentage; it binds nothing. Without these two forms, 26 frozen cases parser v2 reads (English stacked energy, and the Taiwan template's `*` rows) would stop at their first row.
- **Too little read (3.7).** A Taiwan (`zh-Hant`) candidate declines `too_little_read` when fewer than 5 of the 8 template rows have a printed cell in the column that would be stored (v1 section 6.3). Energy counts in kcal or kJ (a kJ cell is a printed cell; its calculated kcal is not); optional rows, not-stored rows and percentage-only rows do not count. A Taiwan table whose rows were all left unread declines `too_little_read` rather than `no_table`. Its copy is the one in 3.7; it is a hard decline with its own copy key. Unheaded tables still decline `no_basis_header` until PR 4, which evaluates the count for each basis the sheet would offer.
- **Ambiguous numbers.** The mutation suite found that a thousands separator (`1,203毫克`) was read, as in parser v2, as the decimal-comma value 1.203. A number whose comma is followed by exactly three digits (a thousands separator or a decimal comma, which cannot be told apart), and any comma on a Taiwan alias row (the template prints a decimal point), now leave the row unread (`row_not_read: malformed_value`). None of the 314 frozen cases changes. Full-width digits still fail the gate's validation, which the product declines (`unreadable_table`), so they bind nothing either.
- **Printed but not read (3.8).** `LabelReading.unreadRows` lists the candidate's `row_not_read: <reason>: <label>` warnings in order, without repeats, as application-owned `LabelUnreadRow` values (no parser type crosses the port; the candidate schema and the manifest are unchanged, so a stored entry yields the same list from its manifest). Confirm shows them in a "Printed but not read" section, after "Read but not used", each as its printed label, "Not read" and a plain reason, with the footer "These rows are in your text but were not read. Where one of them is a value the app stores, its row above says Not read, and you can add it." An unread mandatory row keeps its G3 or G4 flag on its own row. The list shows the printed label; the row's values stay in the pasted text, which Confirm shows in full.
- **Mutation suite (7.2, test 2).** A standing test applies 419 paste-like mutations to two synthetic fixtures (two columns with the template plus fibre; one column with fibre between mandatory rows and a not-stored row) in the inline and stacked layouts: 324 structure-breaking (class a: drop, duplicate, doubled decimal point, full-width digits, an unrelated line, a second basis, the serving quantity moved, thousands separators in three forms, a label after its values, the last labels after or before their values, template-order breaks, mixed inline and stacked rows, values run together) and 95 content-changing (class b: two labels exchanged in an inline table, a unit changed, substring traps, an English gloss naming another nutrient). No mutation binds a wrong value under its oracle. At this head, 234 class (a) mutations decline, 70 read with rows not read and 20 read every row (an unrelated row read but not used, or a moved quantity that leaves only the serving size unread); 2 class (b) mutations decline, 30 read with rows not read and 63 read every row. (From PR 3 the twelve English-gloss mutations leave their row unread under the bilingual rule, so the class (b) figures for these two layouts are 2, 42 and 51; PR 3 pins every tally exactly, section 8.3.)
- **The accepted residual risk (decision 18), pinned.** In a stacked one-column table, protein and fat value lines exchanged (both in grams, labels in template order) are read in text order, protein 12.6 and fat 7.4, with no row warning and no failed check: the energy check passes within its tolerance. Fat and saturated fat exchanged are read in text order too, and the sub-row check fails (saturates above fat), which Confirm shows as a warning. Fibre and sugars exchanged are read in text order. The test fails if any of this changes in either direction.
- **Non-regression.** All 314 frozen cases are identical between parser v2 and parser v3; the allow-list is unchanged.

### 8.3 PR 3 as built

Recorded the same way. Every rule of 8.1 and 8.2 stays (the unexplained-bound span rule, wrapped labels, markers, duplicates over every recognised label, the ambiguous-number rule, the stacked sequence, `too_little_read` and "Printed but not read"); each point below follows from 3.4 to 3.7 or narrows them on the conservative side.

- **Carried over from the review and journey QA of PR 2.**
  - **Wrapped Taiwan labels keep the comma rule.** The any-comma check uses the merged label, so `碳水化` then `合物 1,5公克 5,0公克` leaves carbohydrate unread instead of reading 1.5 and 5.0.
  - **A number is never a label.** A number the value pattern had to cut inside its digits (`502千焦`, where 千焦 is not a unit, read as 50 before `2千焦`) makes the row it would join unread (`malformed_value`), on a label line or on a value line; the rest of the number is never listed as a label. Numbers separated by a space (`120 400`) keep parser v2's unit rules, so the frozen `no_energy_unit` cases still decline.
  - **"X from Y" rows.** An English label whose second word is "from" (`Energy from fat`, `Calories from fat`) is not looked up by its first word for the duplicate-row rule, so it no longer knocks the real energy row out; it stays an unrecognised row (read but not used).
  - **Reference-intake suffixes.** After a percentage, `DV`, `Daily Value`, `RI`, `NRV`, `reference intake` (with an optional "of" or "of the") and 每日參考值(百分比) name the cell's column, not a label, so `5% (DV)` and `6% of DV` are reference cells of the row above. A line holding `% DV`, `Daily Value`, `RI` or `NRV` is still a header phrase, as in parser v2.
  - **The mutation tallies are pinned exactly** (below); a change in either direction fails the test and is recorded here.
  - **A table whose rows were all left unread** declines `too_little_read` in every language (`Energy 400kcal`, `> 6mg Sodium`, `Protein 3g` used to say `no_table`); a text with no rows still says `no_table`.
  - **Copy.** The ambiguous-number rule has its own reason, `ambiguous_number` ("Not read: the number could be read in more than one way."), instead of sharing `malformed_value`; `malformed_value` reads "… such as “more than” or a broken number."; every quoted word in this copy uses typographic quotes.
- **Flattened lines (3.4, `FlattenedLine`).** A line is a flattened table when at least three labels from the alias table are each followed directly by a value with a unit (a `%` does not count). The tokeniser, a pure type beside the parser state:
  - **Separators** are spaces, `/` `／` `,` `，` `、` `；` `;` `:` `：` `|` `_` `=`, the hyphen and the other dashes, brackets, `。`, and the title decoration and bullets of 3.1 (★ ☆ ◎ ● ▲ ■ ◆ • ·).
  - **Before the first label** only these may stand: a title word (營養標示, 營養成分, 營養成份) with at most one bracket without a digit (`營養標示(熱量)`), 項目, a serving phrase (`每一份量 250 毫升`, with an optional bracket), a pack phrase (`本包裝含 7.4 份`) and basis phrases (每份, 每100公克, 每100毫升, 每日參考值(百分比)), including one stuck to the first label (`每份熱量`). Anything else there declines.
  - **Values.** ASCII digits with at most one decimal point, optional spaces and a unit (`大卡` `千卡` `公克` `毫克` `微克` `毫升` `克`, the Latin units, `%`), followed by a separator, a Han label or the end; `<`, `≤`, `≦`, `＜`, 未滿 or 少於 before it and 以下 straight after it make a bound. Every other digit run is malformed: no unit, a second decimal point, full-width digits, a unit followed by a digit (two values with no separator), "more than" or 以上, a thousands separator in any form (the leading group has no unit). A unit followed straight by the next label (`403大卡蛋白質`) is well-formed.
  - **Labels** are maximal Han runs; the voluntary bracket (自願標示者) is removed first. Sub-rows in brackets are classified by the alias table, never by position; an unknown label is an unrecognised row. A leading 其中 ("of which") is dropped only when the rest is an exact alias (`其中飽和脂肪` is saturated fat). A bound word stuck to the end of a label (`鈉超過50毫克`, `糖未滿0.5公克`, `鈉以下`) is never part of it: the label reads alone and the mark leaves the row unread (`unexplained_bound`), so its value is never shown as exact (invariant review of #283).
  - **Segmentation.** Every label must be followed by exactly N value-or-malformed tokens (N amount columns plus the reference column when one is printed), `%` or `*` must stand in the reference position on every row when a reference header is printed and nowhere otherwise, and nothing may stand outside a row; otherwise `flattened_table_ambiguous` (copied as `count_mismatch`). Latin text that is not a unit declines too (bilingual flattened lines are not read). A row with a malformed token, or another symbol, is not read in any column (`malformed_value`); a bound word or mark that no value consumed leaves its row unread (`unexplained_bound`).
  - **Basis.** From the basis phrases before the first label, or from header lines printed before the flattened line. A basis phrase after the first label declines `multiple_panels`; basis phrases of its own after earlier headers or rows with values are a second panel (below); no basis anywhere declines `no_basis_header` (3.3 until PR 4).
  - **Layout.** The body is flattened when it holds exactly one flattened line and every other body line is a label without values (a heading such as a flavour name, which binds nothing). A flattened line beside inline or stacked rows, or two flattened lines (a table split over two lines), match no single layout and decline `layout_ambiguous`.
  - **Gate input coverage.** The whole flattened line is gate-scanned, declined or read; later lines join the last row's span, so a bound word in a footnote after the table leaves that row unread.
- **A recognised label printed against its number** (`熱量51大卡`, the shape of the energy-line layout): when the whole leading Han run is a recognised Chinese row label (alias or recognised-but-not-stored, exact match only), one space is put between the label and the number, in every layout. `其中飽和脂肪3公克` is never split. None of the 314 frozen cases changes.
- **Basis in the energy line (3.5, as decided by decision 23).** A row line whose recognised row label carries a value and a bracketed basis phrase, after the value (`熱量 45大卡(每100毫升)`) or inside the label (`熱量(每100毫升) 45大卡`, invariant review of #283), is always a row, never a header line, so its value is never dropped. With exactly one printed amount header of the same basis the bracket repeats it and the row reads, but only when the bracket adds no quantity, or (per serving) a quantity equal to the header's serving conversion and to the serving size read; `熱量 120大卡(每份25公克)` under `每份(30公克)`, or with no printed quantity to compare, declines `multiple_panels` (re-review of #283). Otherwise the bracket is a basis hint only when no header line was printed, no row with values came before it, the row is energy, the bracket is the only basis bracket and it names an amount basis. The bracket never becomes a header: the row reads without it, the table has no basis header and declines `no_basis_header` (today's copy), and the declined candidate carries `basis_hint: energy_line: <bracket as printed>` for PR 4's sheet. A basis bracket on any other row, on a first row that is not energy, after a header line, or more than one, declines `multiple_panels`. Test 14 pins that a per 100 g bracket over per-serving values (energy per 100 g with the rest per serving, or every value per serving) is never read without the user's choice; the residual that the first wording of 3.5 accepted is gone.
- **Bilingual tables (3.6).**
  - **Header.** A header segment holding Chinese and English takes the Chinese phrase's basis; English naming a different basis declines `multiple_panels`. An English segment straight after a Chinese one is that column's English part: compared the same way, then joined to its printed text. English naming no basis is ignored.
  - **Rows.** A label made of a recognised Chinese row label (alias or recognised-but-not-stored) and an English gloss after it, bracketed or not, is read by its Chinese part. When the English row table names a different nutrient the row is not read (`row_not_read: gloss_conflict: <printed label>`); an unknown gloss is ignored. The gloss is consumed unbound, so the gate scans it.
  - **Unit pairs.** In number, bracketed English unit, Chinese unit (`4.3(g)公克`), the bracket is masked and the value reads with its Chinese unit, keeping its printed text as printed; when the two canonical units differ the row is not read (`row_not_read: unit_pair_mismatch: <printed label>`).
  - **Language.** A `mixed` text is `zh-Hant` when every row's label is a recognised Chinese row label and every Latin word sits in a gloss, a bracket on a row, or a title, header, serving or pack line; any other Latin word (an English note, an English-only row) keeps it `mixed`. Format inference stays v1.
  - **Serving and pack lines (tightened after the invariant review of #283).** On a serving or pack line holding Han and a Latin word, in either order and bracketed or not, the Chinese phrase decides and the English is never bound on its own:
    - **Serving size.** When the line's quantities disagree in number or canonical unit (`Serving size 25g 每一份量 30公克`, `每一份量30公克 (about 25g)`) the serving size is not read and the candidate carries `bilingual_quantity_conflict: serving_size`; when every quantity sits in an English bracket (`每一份量1包 (about 30g)`) it is not read either. When they agree, the quantity is located as serving v3 locates it (5.6 step 4), so servings stay offered.
    - **Pack count.** The count is the Chinese phrase's (`本包裝含 N 份`), and every number on the line must equal it; otherwise (`Servings per package: 3 本包裝含 2份`, or an English count with no Chinese one) the pack count is not read and the candidate carries `bilingual_quantity_conflict: servings_per_pack`. The same applies to a pack phrase inside a serving line. An approximation word or mark anywhere on such a line makes the count approximate. Chinese-only pack lines keep parser v2's reading.
    - **A number is never cut (second re-review of #283; this predates PR 3 and is parser v2's behaviour, which stays frozen).** Parser v3 locates a serving quantity only where no digit, separator or other numeral touches it on the left, and a serving or pack line holding a comma, a full-width point or another numeral between digits (`2．5公克`, `30,5g`, `3²0公克`, `2,5 servings`) is not read; parser v2 read the digits after the separator (5 g). None of the 314 frozen cases changes. On a serving line holding a pack phrase, the bilingual pack rule compares and scans for approximation over the whole serving value with its weight and volume quantities removed, so an English count before the Chinese phrase (`about 3 servings per container … 本包裝含2份`) is compared and its "about" kept. `gr` and `grs` are grams and `cc` is millilitres. From the focused re-review of #283:
      - **Flattened lines** compare the serving and pack segments of the physical line together, and scan them together for approximation, so an English count in the serving bracket is compared there too.
      - **Count words** (`1 bar`, `2 pieces`, `2片`) are removed before pack counts are compared, on serving lines, flattened lines and stand-alone pack lines alike (`本包裝含 6份 (12 pieces)` reads 6), so they never cost the pack count; servings and 份 stay pack words. A number straight after a servings-per phrase (servings or portions per container, package or pack, 每包裝, 本包裝含) is a pack count whatever word follows it, so `Servings per container: 3 bars` beside `本包裝含 2份` is a conflict.
      - **A multiplied serving** (`2x15g`, `2 x 15公克`, `15公克×2`, with `x`, `×`, `*` or `＊`) is not read, never the one factor. Parser v2 read 15 g; it stays frozen. A multiplier after the quantity needs a number after it, so a footnote asterisk (`30g*`, `30 g * Servings per container 2`) is not one.
      - **A Chinese serving number in non-ASCII digits** is never bound, even when an English bracket agrees with it after folding (`每一份量 ３０公克 (Serving size 30g)`): not read, with the warning.
      - **A bilingual line not read** for an unparsable or cut number carries its `bilingual_quantity_conflict` warning.
    - **Every quantity counts (re-review of #283).** Full-width digits and point are folded to ASCII before comparing, and a number that still cannot be parsed makes the line not read; it is never skipped. An English quantity in grams or millilitres under any spelling (`25 grams`) is compared like the others, and one in any other weight or volume unit (`1 oz`, `1 cup`) is a conflict; a count word (`2 pieces`) is not a quantity. Separately, a serving size or pack count printed in full-width or other non-ASCII digits is never bound, bilingual or not (full-width digits in a row's values still fail the gate's validation, as 8.2 records).
- **Two complete panels (3.7, decision 8).** When the parser declines `multiple_panels` at a second panel's title, header or basis phrase, it reads the text before and after that line on its own; when both read (or the second part itself holds two or more complete panels), the decline is `multiple_complete_panels`, with the copy of 3.7. Any other `multiple_panels` keeps its copy. Nothing is read either way. Heading lines (journey QA of #283): a title or header after rows makes a second panel only once a row carries values or names a recognised row, so a flavour name before the first panel's title is not a second panel; and a short Han heading line (no digit, not a row label) straight before the second panel's title or header belongs to the second panel.
- **Layout precedence** lists inline, stacked and flattened.
- **Mutation suite (test 2, extended).** The flattened and bilingual layouts of the same two fixtures add 410 structure-breaking mutations (drop, duplicate, doubled decimal point, full-width digits, no separator between values or rows, an unrelated row, a second basis, the serving quantity moved, a percentage on one row, a stray number, a label after its values, thousands separators in three forms, a row beside the flattened line or stacked in the bilingual table, a conflicting English header, a header on its own line, a value with its Chinese unit only) and 126 content-changing ones (labels exchanged, a unit changed, substring traps, an English gloss naming another nutrient, a bracketed English unit that disagrees). No mutation binds a wrong value under its oracle. Pinned tallies at this head: inline and stacked, class (a) 324 mutations, 234 declined, 70 read with rows not read, 20 read in full; class (b) 95, 2, 42, 51. Flattened and bilingual, class (a) 410, 291, 68, 51; class (b) 126, 12, 54, 60. Rows read in full under class (a) are an unrelated row read but not used, a missing separator between rows, the header on its own line or a value printed with its Chinese unit only; under class (b) they are the truth of the mutated text.
- **Non-regression.** All 314 frozen cases are identical between parser v2 and parser v3; the allow-list is unchanged.
- **Known limits, accepted.** A flattened line printing kJ and kcal for one row, or 每份 with its serving weight in a bracket (`每份(30公克)`), declines rather than guess. A bilingual table from another market reads as Taiwan when its rows are Taiwan rows (3.6 residual). A flattened bilingual line declines.

### 8.4 PR 4 design: the basis choice and manifest v2 (for the architecture gate)

Written before any PR 4 production code, so the gate can check it. It makes 3.3, 5.2 and 5.3 concrete and records the owner's decisions 24 to 26 (section 9.4). Where it narrows an earlier sentence, the earlier sentence carries a pointer here. Every rule of 8.1 to 8.3 stays.

#### 8.4.1 What the reader hands the application: `UnheadedTable`

`LabelReading` gains one optional, application-owned value, `unheadedTable: UnheadedTable?`. It replaces the "`basisNotPrinted` marker per column" of section 6, which was never built.

| Field | Content |
|---|---|
| `amountColumnCount` | 1 or 2: the number of amount columns (columns whose values carry an amount unit) |
| `amountHeaderIDs` | the header IDs the asserted headers will take, in column order: `header_1`, then `header_2`. These are the parser's existing IDs (the gate's "h1, h2"); a printed `%` column takes the next ID (`header_2` or `header_3`) |
| `referenceColumnPrinted` | whether a reference-intake (`%`) column was printed, as a header or as `%` values |
| `servingSize` | the serving size the parser read (its printed text, `decimal_text` and canonical unit), taken from the parser's side result, because a declined candidate carries no serving size, pack count, rows or cells; none when no serving size was read |
| `servingsPerPack` | the pack count the parser read, from the side result, for the same reason |
| `energyLineHint` | the `basis_hint: energy_line:` bracket as printed and the basis it names (`per_serving`, `per_100g`, `per_100ml`), when the parser carried one (decision 23) |

**Who fills it.** The parser computes a parser-owned side result beside the candidate (`NutritionLabelTextParserV3.UnheadedShape`, never part of the candidate) and the adapter maps it to `UnheadedTable`; no parser type crosses the port. A `no_basis_header` decline keeps today's shape exactly: no rows, cells, serving size or pack count, and warnings that are `[basis_hint: energy_line: <bracket>]` alone or empty (gate re-check, medium 1). The candidate schema stays `label-capture-candidate-v1`; the side result is not stored. The frozen `NutritionLabelTextParse` CLI and parser v2 do not change.

**When it is filled (all must hold).**

1. The candidate declined with decline codes **exactly** `[no_basis_header]`.
2. **No amount header was printed** anywhere in the table (a printed `%` header is allowed). A table with some amount headers printed and others missing ("mixed", in any layout) keeps today's decline and gets no `UnheadedTable`, so no sheet (3.3 item 1).
3. Every read row binds the same number of amount values, and that number is 1 or 2. Rows left unread (`row_not_read`) do not count; if no read row remains, there is nothing to choose and the table declines as today.
4. When a `%` column is printed, it is the **last** column on every row that prints it (the Taiwan template's position). A `%` value anywhere else leaves `UnheadedTable` nil.
5. The layout is inline, stacked, flattened or bilingual (8.4.13). A body that declines `layout_ambiguous`, `flattened_table_ambiguous` or `multiple_panels` never reaches `no_basis_header`, so it has no sheet.

**The sheet is offered only when** the reading's decline codes are exactly `[no_basis_header]` **and** `unheadedTable` is non-nil **and** the options function (8.4.3) returns at least one option **and** every option passes 8.4.7. When the options function returns nothing (two columns without a serving size in grams or millilitres) the table declines `unheaded_columns_without_serving_size`, or `unheaded_columns_serving_size_not_in_g_or_ml` when a serving size was printed in another form, each with its own copy (8.4.16). Otherwise the outcome is today's decline, unchanged.

#### 8.4.2 The port: `AssertedBases`

```swift
public struct AssertedBases: Equatable, Sendable {
    public enum Basis: String, Sendable { case perServing = "per_serving", per100g = "per_100g", per100ml = "per_100ml" }
    public let columns: [Basis]   // column order, one entry per amount column
}

public protocol LabelTextReading: Sendable {
    func read(_ text: String, textSHA256: String, assertedBases: AssertedBases?) -> LabelReading
}
```

- **By type** it holds only `per_serving`, `per_100g` and `per_100ml`; `reference_intake` cannot be asserted.
- **One requirement, no dropping default.** The protocol has the single requirement above; every conformer (the adapter and every test fake) implements it. A convenience `read(_:textSHA256:)` may exist only as an extension that passes `assertedBases: nil` explicitly; there is no default implementation that accepts `AssertedBases` and ignores it. A test fake that records the bases it received proves the application passes them.
- **The adapter maps** `AssertedBases` to the parser's own basis type and the parser applies it. The parser **declines** `asserted_bases_mismatch` (a new candidate decline code, copied as `unreadable_table`, and listed in the code-to-copy table so v1 test 27 enumerates it) when any amount header was printed, when `UnheadedTable`'s conditions (8.4.1) do not hold, or when the number of asserted bases differs from the amount column count. The application never asserts bases on such a text, so this decline can only show a programming error, never a user's choice.
- **What an asserted read returns.** The candidate the parser builds with the asserted headers in place of the missing ones: the amount headers are `header_1` (and `header_2`) with the asserted basis, **empty printed text** and no serving conversion (encoded as `null`, as for any absent header conversion); a printed `%` header keeps its printed text and takes the next ID. Cells of an asserted per-serving column carry the serving conversion the parser writes for a printed per-serving header with no conversion of its own: the serving size's `decimal_text` and printed unit (`30公克`), or `unknown` when no serving size was read; the verifier recomputes it and checks both (as built: the gate's "always `unknown`" would have made an asserted column differ from a printed one). Its warnings are the parse's full warnings with `basis_hint: energy_line: <bracket>` **last** when the parser carried a hint (decision 24). Its serving size and pack count equal `UnheadedTable`'s.
- **Pinned test (medium 1).** On each fixture, asserted reads under different options differ only in the headers' basis, the cells' `header_id` and `basis`, and the cells' `serving_conversion`; and the declined candidate's warnings stay `[basis_hint: …]` alone (or empty).

#### 8.4.3 The options function and the `offered` encoding

`PastedLabelBasisOptions.options(amountColumnCount:servingUnit:)` is a pure application function. Its inputs can be derived both from `UnheadedTable` (before the choice) and from a stored v2 candidate (the number of amount headers, and the serving size's canonical unit when `decimal_text` and a `g` or `ml` unit are present), so the verifier recomputes it from the stored bytes alone. `servingUnit` is `none`, `g` or `ml`. The function returns the closed table below, or `nil` for "no sheet, decline".

| Amount columns | Serving size | Options, in order |
|---|---|---|
| 1 | none | `per_100g`, `per_100ml` (Per serving is not offered, and the sheet says why) |
| 1 | g | `per_serving`, `per_100g`, `per_100ml` |
| 1 | ml | `per_serving`, `per_100ml`, `per_100g` |
| 2 | none | `nil`: no sheet; declines `unheaded_columns_without_serving_size` (or `unheaded_columns_serving_size_not_in_g_or_ml` when a serving size is printed in another form), because the template's first column is per serving, which needs a serving size |
| 2 | g | `per_serving,per_100g`, `per_serving,per_100ml` |
| 2 | ml | `per_serving,per_100ml`, `per_serving,per_100g` |

- **Arrangement identifiers.** An option is an arrangement: its column bases in column order, joined by `,` with no spaces (`per_100g`, `per_serving,per_100ml`). `offered` is the list of arrangement identifiers in the table's order. "I'm not sure" is never in `offered`; it is not a basis.
- **Order rule.** Per serving first when offered, then the per 100 basis in the serving size's own unit family, then the other. The order follows the printed serving unit only; it never says which answer is likely, and the sheet's copy must not either (3.3 residual risks).
- **The hint never changes the options, their order or a selection.** Nothing is preselected.
- **One serving-unit function (medium 4).** `PastedLabelBasisOptions.servingUnit(_: Candidate.ServingSize?) -> none | g | ml` is the only mapping, used by the sheet (on `UnheadedTable.servingSize`) and by the verifier (on the stored candidate). A serving size with `decimal_text` and canonical unit `g` or `ml` maps to that unit **whether serving v3 reads it as exact, approximate or a range** (8.4.10); anything else is `none`. A contract test proves that the options from `UnheadedTable` equal the options from each asserted candidate on every 8.4.13 fixture.
- Golden v2 manifests (8.4.6) pin `offered` for one and two columns; a table test pins every row above.

#### 8.4.4 `label-arithmetic-checks-v2`

`label-arithmetic-checks-v2` is `label-arithmetic-checks-v1` unchanged, plus one check, `basis_plausibility`, run for **each amount basis present in the cells** (all of them are asserted, because v2 only runs on an asserted read). It is Swift only (`LabelArithmeticChecksV2` in `NutritionLabelParsing`, calling v1 and appending); v1's Python parity tests stay untouched.

**Values.** For the basis being checked, a row's value is its single cell in that basis with the canonical unit named below. A cell with `=` gives its number; a cell with `<` or `<=` gives its **stated end** (the printed upper number), because the check looks for values that are too large and a bound's stated end is the largest it can be. A row with no such cell, more than one, another unit or an unparsable number is **missing**. Never zero.

**Two results per basis**, each `pass`, `fail` or `not_checkable`:

| Check (`nutrient` field) | Rows | Fails when |
|---|---|---|
| `macronutrients` | protein, fat, carbohydrate, each in `g` | the sum of the present rows is more than *limit* + *tolerance* |
| `energy` | the `energy_kcal` row in `kcal`; if none, the `energy_kj` row in `kJ` | the value is more than *limit* + *tolerance* (in kJ: both multiplied by 4.184) |

**Limits and tolerance, by asserted basis.**

| Basis | Macronutrient limit | Energy limit |
|---|---|---|
| `per_100g` | 100 g | 900 kcal |
| `per_100ml` | 150 g (syrups and honey weigh up to about 1.45 g per ml) | 900 kcal (oils, the densest energy, are about 830 kcal per 100 ml) |
| `per_serving`, serving size in g (s) | s g | 9 × s kcal |
| `per_serving`, serving size in ml, or no serving quantity | `not_checkable` | `not_checkable` |

*Tolerance* is the larger of 2% of the limit and an absolute floor (0.5 g for macronutrients, 5 kcal for energy, 20.92 kJ in kJ), so rounding to one decimal on three rows never fails a plausible label. Arithmetic is exact `Decimal`; the serving size is the candidate's `decimal_text`.

**Missing rows.** If the present rows alone are over the limit, the result is `fail`. Otherwise, if any row is missing, it is `not_checkable`: **never `pass` on missing rows**. With all rows present and within the limit it is `pass`.

**Order.** The checks are v1's checks in v1's order, then, for each amount basis in column order, `macronutrients` then `energy`.

**Warning codes** follow v1's form (v1 section 8.8): `basis_plausibility:<basis>:macronutrients` and `basis_plausibility:<basis>:energy`. A failure is a warning, never a block and never a checked mark; a pass shows nothing.

**Per option, through the port.** The application reads the text once per offered option with that option's `AssertedBases` (8.4.7), so each option's checks come back as part of an ordinary `LabelReading`. The sheet shows an option's plausibility warning beside it ("With this choice, protein, fat and carbohydrate add up to more than the food's weight." / "With this choice, the energy is higher than any food has."). **Confirm shows, and `warnings_shown` records, only the chosen option's warnings**, through the existing `LabelReading.warningCodes`.

**Golden vectors (Swift).** A table of synthetic inputs and expected statuses, with the limit arithmetic worked in the test's comments, covers at least (per 100 g: macronutrients fail above 102 g, energy above 918 kcal or 3,840.912 kJ; per 100 ml: macronutrients above 153 g; per serving of 25 g: macronutrients above 25.5 g, energy above 230 kcal):

- per 100 g, protein 30, fat 20, carbohydrate 40: pass; 60, 30, 20: fail;
- per 100 g, fat 99.9 with protein `<0.5` and carbohydrate `<0.5` (stated ends, 100.9 in all): pass;
- per 100 g, fat 99 and protein 2.5 with carbohydrate `<1` (102.5): fail, the stated end tips it;
- per 100 g, fat 103 with protein and carbohydrate missing: fail on the partial sum; fat 40 with carbohydrate missing: `not_checkable`;
- per 100 g energy 918 kcal: pass; 919 kcal: fail; no kcal row and 3,850 kJ: fail; 3,840 kJ: pass;
- per 100 ml, carbohydrate 140 with protein and fat 0: pass; 160: fail;
- per serving of 25 g, carbohydrate 30 with protein and fat 0: fail; 20: pass; energy 230 kcal: pass; 231 kcal: fail;
- per serving with the serving size in ml: both `not_checkable`.

#### 8.4.5 Versions per read

- An **unasserted** read reports `label-arithmetic-checks-v1`; an **asserted** read reports `label-arithmetic-checks-v2`. The adapter sets `LabelReading.versions` per read from which checks it ran; there is no single static `versions` for both.
- A usable unasserted reading writes manifest v1, an asserted one manifest v2, and each reading's pipeline string `<parser>:<gate>:<arithmetic>:<conversion>` must equal its 5.2 admitted entry **exactly**: `nutrition-label-text-parser-v3:label-capture-decline-gate-v2:label-arithmetic-checks-v1:pasted-label-conversions-v1` under v1, and `nutrition-label-text-parser-v3:label-capture-decline-gate-v2:label-arithmetic-checks-v2:pasted-label-conversions-v1` under v2. The confirmation builder throws rather than write a v2 manifest with checks v1 or the reverse, and the verifier's admitted-pipeline lookup (keyed by manifest version) rejects it at save and reopen. A contract test pins the full `admittedPipelines` map.

#### 8.4.6 `PastedLabelManifestV2` and one dispatcher

**Two strict types.** `PastedLabelManifest` (v1) and its canonical encoding are untouched: it never gains `basis_choices`, and a golden test pins its bytes for a parser-v2 and a parser-v3 entry. A new `PastedLabelManifestV2` has its own `CodingKeys` (v1's keys plus `basis_choices`), its own strict decoder (unknown or missing keys throw; `version` must be `pasted-nutrition-label-v2`; `basis_choices` must be non-empty) and its own encoder.

`basis_choices` holds one record per asserted amount header, in header order:

| Key | Content |
|---|---|
| `header_id` | the asserted header's ID |
| `basis` | `per_serving`, `per_100g` or `per_100ml` |
| `offered` | the arrangement identifiers shown, in order (8.4.3); the same list on every record |
| `at` | a JSON **integer** of whole milliseconds since 1970 (`Int64`), from the injected clock at the moment of the choice, truncated at stamping (with the 1 µs tolerance recorded in 8.4.16); the same on every record. The decoder rejects a non-integer, and the verifier requires `at` no later than the evidence's `capturedAt` (gate re-check, medium 3) |

**One dispatcher.** `PastedLabelEvidenceManifest` is an application enum, `.v1(PastedLabelManifest)` or `.v2(PastedLabelManifestV2)`. v2 reuses v1's nested types (identity mapping, candidate mirror, conversion, flag, correction); its `basis_choices` records decode strictly. A v2 release's `schema_version` is `pasted-nutrition-label-v2:<format>`, pinned in the goldens. Its `decode(_:)` reads only the `version` member first (a probe that is not strict), then strictly decodes exactly the matching type; any other version is `nil`. It exposes the shared fields (`pastedText`, `candidate`, `storedHeaderID`, `corrections`, `conversions`, versions, `warningsShown`, `name`, `brand`, `identityMapping`, `labelFormat`), `version`, and `basisChoices` (empty for v1), and encodes the case it holds. `PastedLabelEvidenceManifest.versions` is exactly `[pasted-nutrition-label-v1, pasted-nutrition-label-v2]`. The shared rules (stored basis, expected nutrients, corrections, servings, origins, the misread report) take the dispatcher, so there is one derivation for both versions and no copy.

**Every site that hard-codes `PastedLabelManifest.version` or `.decode` today, and what it becomes:**

| Site | Today | PR 4 |
|---|---|---|
| `PastedLabelSource.admittedPipelines` | v1 key only | adds the v2 key with its one pipeline (5.2) |
| `PastedLabelSource.schemaVersion` | `PastedLabelManifest.version + ":" + format` | the dispatcher's `version` |
| `PastedLabelSource.pipeline(_:)` | takes `PastedLabelManifest` | takes the dispatcher |
| `PastedLabelSource.checkCorrection(manifest:…)` | takes `PastedLabelManifest` | takes the dispatcher |
| `PastedLabelSource.confirmation(manifest:…)` | encodes v1; evidence `captureMethodVersion` v1 | takes the dispatcher; `captureMethodVersion` is the case's version |
| `PastedLabelSource.verify` | evidence version `== v1`; `PastedLabelManifest.decode` | evidence version in `versions`, decoded through the dispatcher, and the decoded `version` must equal the evidence's `captureMethodVersion` |
| `PastedLabelSource.isCanonical` | v1 decode and re-encode | dispatcher decode and re-encode of the same case |
| `PastedLabelSource.restoredSourceCandidate` | v1 decode | dispatcher decode |
| `PastedLabelSource.expectedCandidate`, `storedBasis`, `servingSizeCorrection`, `expectedNutrients`, `checkServingsPerPack` | take `PastedLabelManifest` | take the dispatcher; v2 adds the checks of 8.4.6 below |
| `PanelSourceAdmission.applies` (`PastedLabelSource.swift` about line 445) | evidence version `== v1` | evidence version in `versions` |
| `PastedLabelServingPolicy.manifest` (about line 194) and `storedServingSize`, `per100Serving` | v1 version and decode | dispatcher |
| `PastedLabelValueOrigins.manifest(evidence:…)` and `origins` (`NutrientValueOrigin.swift` about line 78), `NutrientValueOrigin.project` | v1 version and decode | dispatcher |
| `CanonicalFoodArchive.minimumContractVersion` (about line 111) | evidence version `== v1` gives 7 | either version gives 7 (decision 26) |
| `PastedLabelMisreadReport.init(manifest:)` | v1 | dispatcher; the report gains the basis line (8.4.12) |
| `SavedFoodEntryDetail.pastedLabel` | `PastedLabelManifest?` | `PastedLabelEvidenceManifest?` |
| `PastedLabelConfirmation.manifest` and `confirmation` | builds v1 | builds v1 without a choice, v2 with one (8.4.5) |
| Presentation: `PastedLabelSourceModel` (`manifest`, `init(stored:)`, the evidence lists, about line 291's "Other column" text), `FoodConfirmationView` (about line 102), `PastedLabelSavedEntryText` in `PastedLabelText.swift` (about lines 388 to 433) | v1 | dispatcher |
| `ReviewedFoodProposalConfirmation`'s verifier | matches its own version only | unchanged; a cross-route test proves it rejects v2 pasted evidence |
| `FoodLedgerMigrations` `v7_pasted_label` | comment names v1 | comment only; no migration (decision 26) |

`PastedLabelTextViewModel`'s and `PastedLabelText`'s other uses (`maximumTextScalars`, `Correction`, `Candidate.Header`) name nested types, not the version, and stay. Stage 2 re-runs `rg 'PastedLabelManifest\b'` (less nested-type uses such as `PastedLabelManifest.Candidate`) and `rg captureMethodVersion`, and records any further site in this table before merging.

**v2 verification (at save `invalidPastedLabelSource`, at reopen `integrityFailure`), in addition to everything v1 checks:**

1. The candidate has at least one amount header, and **every** amount header has empty printed text and no serving conversion: no mixed manifest.
2. `basis_choices` has exactly one record per amount header, in header order, with the same `header_id` and `basis`; no record names a `reference_intake` header or an unknown ID; a `%` header keeps its printed text.
3. `offered` is identical on every record and equals `PastedLabelBasisOptions.options` recomputed from the stored candidate (8.4.3); the chosen arrangement (the records' bases in header order) is in `offered`; `at` is identical on every record.
4. The pipeline is the v2 entry (checks v2).
5. `basis_hint:energy_line` may appear in `warnings_shown` only when the candidate has exactly one `basis_hint: energy_line:` warning, and only in its pinned position (8.4.12).
6. `at` is an integer and no later than the evidence's `capturedAt`; asserted headers have a `null` serving conversion and their per-serving cells the conversion of 8.4.2 (the serving size's `decimal_text` and printed unit, or `unknown` when no serving size was read).
7. Values from a chosen-basis column keep `user_verified_panel` provenance (their numbers are printed); their **basis** is user-asserted, evidenced by the record. A changed basis, record, `offered` or header fails.

**The v1 verifier tightens one check:** a v1 manifest with any amount header whose printed text is empty is rejected. Parser v2 and v3 never write one under v1.

**Cross-route and dispatch tests:** v1 evidence relabelled v2 and v2 relabelled v1 are rejected; the reviewed web verifier rejects both pasted versions; the pasted verifier rejects reviewed web evidence; `minimumContractVersion` is 7 for both.

**Developer tools re-parse** stays deferred to issue #273 (decision 25). PR 4 pins the reproduction property at the adapter instead: for each v2 golden fixture, `read(pastedText, assertedBases: <from basis_choices>)` mapped to the candidate mirror encodes byte for byte to the stored candidate.

#### 8.4.7 The same outcome across options

Before the sheet is shown, `PastedLabelReader` reads the text once per offered option with its `AssertedBases` and classifies each reading exactly as an ordinary reading is classified (the gate's hard declines, the launch scope, `PastedLabelBasisState.isAsSold`, a stored column, `too_little_read`). **If any option would hard-decline, there is no sheet:** the outcome is a decline with the first declining option's codes, in offered order. Only when every option is usable does the outcome become "needs a basis choice", carrying each option's usable review and plausibility warnings, so choosing an option never re-reads and never meets a decline after the sheet.

The gate's G1 and G2, the launch scope and `isAsSold` do not depend on the asserted basis (they read the text, the language and the header and serving wording, which an asserted read leaves as they are), so in practice only G3 to G6 flags, `too_little_read` and the checks can differ between options. This narrows 3.7's "declines only if it fails for every option" to "for any option". The two coincide under the options table: every arrangement stores the same column (the one column, or the per 100 column of two), so the count of mandatory rows read is the same for every option. The test pins both.

#### 8.4.8 The application step and the journey

- `PastedLabelReadOutcome` gains `.needsBasisChoice(PastedLabelBasisChoiceRequest)`: the pasted text, its hash, the declined reading, the `UnheadedTable`, the options in order with each option's review and warning codes, and the hint.
- Choosing is an application step that takes the request and an arrangement in its options, stamps `at` with the injected `LedgerClock`, and returns the option's `PastedLabelReview` with a `basisChoice` (arrangement, `offered`, `at`). The confirmation builder writes manifest v2 from it.
- Presentation renders the request without logic: the question "These values have no column heading. What are they for?", the options in order ("Per serving (25 g)", "Per 100 g", "Per 100 ml"; for two columns "Per serving (25 g), then per 100 g"), each option's warning, the hint when present ("The label's energy line says 每100毫升."), "Per serving is not offered because the serving size was not read." when that row of the table applies, and "I'm not sure", which goes back to the text with a link to Search. Nothing is preselected. Native grouped style, Dynamic Type, VoiceOver labels and 44 pt targets.

#### 8.4.9 The choice's lifecycle

- **Bound to the text and the reading.** A choice belongs to the text hash and the reading it was made on.
- **Edited text, or Read again**, clears the choice and shows the sheet again (on the new reading, if it still needs one).
- **Return to Confirm with unchanged text** keeps the choice and every correction, as today.
- **Change** on Confirm's basis line opens the sheet with **nothing preselected**; the current choice is labelled "Current choice", not selected. Choosing a different arrangement when the user has corrected or entered anything first asks "Changing what the values are for replaces your corrections.", as Read again does; Cancel keeps everything. Choosing the current arrangement again changes nothing.
- **Dismissing the first sheet** (after Read label) is "I'm not sure": it writes nothing and returns to the label text screen with the text kept.
- **From Change:** dismissing the sheet or Cancel keeps the current choice and stays on Confirm. "I'm not sure" returns to the label text screen and clears the choice: the Confirm is dropped and the text is kept.
- View-model tests cover each bullet.

#### 8.4.10 Servings under a chosen basis

The method table of 5.6 applies unchanged to the asserted basis: a stored per-serving column uses `pasted-label-serving-v1`; a stored per 100 g or per 100 ml column uses `pasted-label-serving-v3` (the manifest's parser is v3); a serving size in the other unit family offers no servings (`per_100ml` with a serving in grams, or the reverse). **Per serving is offered whenever a serving size with a `g` or `ml` quantity was read, including when serving v3 would show it as approximate or a range,** because a per-serving column's basis quantity is the recorded quantity exactly as for a printed per-serving column (v1 section 6.3); approximation affects only servings against a per 100 column. A test pins one column chosen per serving with an approximate serving size (servings offered through v1) and the same text chosen per 100 g (no servings, as serving v3 reads it approximate).

#### 8.4.11 One basis origin, one formatter

- **Application:** `PastedLabelBasisOrigin` is derived in one place from a review or from the dispatcher manifest: `printed`, or `chosenByYou(hint:)` where the hint is the energy-line bracket and its basis when the candidate carries `basis_hint: energy_line: …`. v1 manifests are always `printed`.
- **Presentation:** one formatter, `PastedLabelText.basisLine(basis:origin:)`, gives "Per 100 g" for printed and "Per 100 g · Chosen by you" for a choice, and, when the hint **differs** (the hint's basis is not one of the chosen arrangement's bases), the note "The label's energy line says 每100毫升." (decision 24; a visible note, never a block). Confirm's basis line, the saved entry's source line, the misread report and the Developer tools lines all use it.
- **Empty header text.** Any copy that shows a header's printed text renders a header with empty printed text by its basis label instead (for example "Other column: per serving", never "per serving ()"), including flag copy.
- A cross-surface test renders one v2 entry through all four surfaces and expects the same basis line.

- **G5 under a chosen basis.** `required_basis_missing` copy names the chosen basis by its label, for example "Only per serving values; the label does not print per 100 g.", with a test.

#### 8.4.12 Decision 24 on Confirm and in the record

- **Differs** means the hint's basis is not one of the chosen arrangement's bases (the same wording as 8.4.11). It is computed once, at the choice, from `UnheadedTable.energyLineHint.basis`.
- When it differs, Confirm shows the note on the basis line and records `basis_hint:energy_line` in `warnings_shown`, **after** the check codes and the serving-line codes. It is not repeated in the general warnings list, because the basis line shows it. When the hint agrees, nothing is shown or recorded. The candidate keeps the `basis_hint` warning either way.
- The saved entry, the misread report and Developer tools show the note **only when** `warnings_shown` contains `basis_hint:energy_line`, taking the bracket text from the candidate's warning; they never re-derive "differs".

#### 8.4.13 Layouts in scope, and fixtures

The sheet is offered for unheaded tables in the **inline**, **stacked**, **flattened** and **bilingual** layouts, and for the energy-line hint (3.5, decision 23). Synthetic fixtures (invented values and names), one per layout with one column and with two, plus:

- a **printed `%` header with unheaded amount columns** (the reference header printed, the amount headers not): `UnheadedTable` with `referenceColumnPrinted` true, the `%` header keeping its text and the next ID;
- a `%` value in a non-last position (no sheet);
- a mixed table, one amount header printed and one not, in each layout (no sheet, today's decline);
- two columns with no serving size (no sheet);
- an option that declines `too_little_read` or fails the gate (no sheet).

#### 8.4.14 Carried from the final review of PR 3 (parser v3, first code commit)

Parser v3 is not frozen (5.1), so these narrow its serving and pack reading on the conservative side, each with a test:

1. The servings-per lead widens to `servings?\s*(?:per|/)\s*\p{L}+`, with an optional bracketed qualifier before the `:`; "approximately", "around", `~` and `ca.` join the approximation words.
2. A second Chinese count in a pack line (`本包裝含 2份 (約3份)`, `(每包裝 3份)`) is compared with the first: a different count leaves the pack count not read (`bilingual_quantity_conflict: servings_per_pack`), and 約 in it makes the count approximate.
3. A bare ASCII bracket beside a full-width Chinese serving number (`每一份量 ３０公克 (30g)`) is not bound: the serving size is not read.
4. Approximation is scanned the same way, on the stripped text, on stand-alone pack lines and on flattened lines.
5. `Serving size 30g (x2)` is a multiplied serving and is not read.

The 314 frozen cases and the pinned mutation tallies of 8.3 must not change; if one does, it is recorded here with its rule.

#### 8.4.15 Contract tests for PR 4 (the gate's sixteen)

1. Golden round-trips: manifest v1 with parser v2 and parser v3, manifest v2 with one and two columns, each byte for byte.
2. Version dispatch: each version decodes only through its own type; unknown versions are `nil`; v1 bytes never gain `basis_choices`.
3. v2 verifier: every rule of 8.4.6 at save and at reopen.
4. v1 verifier rejects an empty-text amount header.
5. Cross-route rejection both ways, and relabelled versions.
6. `minimumContractVersion` is 7 for both versions.
7. Admitted pipelines: the map is exactly 5.2.
8. Options function: every row of the 8.4.3 table.
9. Checks v2 golden vectors (8.4.4).
10. `AssertedBases` at the adapter: the asserted read's headers, the `asserted_bases_mismatch` declines, and the byte-for-byte reproduction of decision 25.
11. Same outcome across options (8.4.7).
12. Mixed tables get no sheet, in every layout.
13. Chosen-basis provenance across surfaces (8.4.11).
14. Serving method table under an asserted basis (8.4.10).
15. View-model lifecycle (8.4.9).
16. Simulator UI test: paste an unheaded table, see the sheet, choose, reach Confirm with "Chosen by you", Change, dismiss, and Log.

Added by the gate re-check (20 October 2026):

17. Asserted reads under different options differ only in header basis, cell `header_id` and `basis`, and `serving_conversion`; the declined candidate's warnings stay `[basis_hint: …]` alone (8.4.2).
18. `UnheadedTable`'s serving size and pack count come from the side result and equal the asserted candidate's.
19. Decision 24: "differs" by arrangement; the position of `basis_hint:energy_line` in `warnings_shown`, not repeated in the warnings list; the verifier rejects it without exactly one hint warning; saved surfaces show it only from `warnings_shown`.
20. `at`: integer milliseconds, truncated from a sub-millisecond clock in a golden; a non-integer is rejected; a value later than `capturedAt` is rejected.
21. `servingUnit` is the one mapping; options from `UnheadedTable` equal options from each asserted candidate on every 8.4.13 fixture, approximate and range serving sizes included.
22. Asserted headers encode a `null` serving conversion and per-serving cells the conversion of 8.4.2; the verifier rejects anything else; the v2 `schema_version` is pinned.
23. Checks v2 order: v1's checks, then per basis in column order `macronutrients` then `energy`.
24. Change lifecycle: dismiss and Cancel stay on Confirm with the choice; "I'm not sure" from Change drops Confirm and clears the choice; G5 copy names the chosen basis.

Every reader v3 test, the 314 non-regression cases and the mutation tallies stay unchanged. The dev set (7.3) is re-run outside the repository and reported as counts only.

#### 8.4.16 PR 4 as built

Recorded the same way as 8.1 to 8.3. Each point follows from 8.4.1 to 8.4.15 or narrows them on the conservative side.

- **How the parser finds the column count.** `unheadedShape` reads the text with placeholder bases for one and for two columns. The count is the one that reads; when neither reads, the one that declines only `too_little_read` (so the application can decline it, 8.4.7); otherwise there is no shape. A one-column stacked table read as two columns stops at its first row, so it never fits two.
- **The asserted read** replaces the missing amount headers inside the parser before binding, in every layout; the flattened reader takes the asserted bases before any printed reference basis. An amount after a percentage on any row declines `asserted_bases_mismatch` (8.4.1 rule 4). The application asserts only after a shape exists, so the code never reaches a user.
- **The hint's printed text** is the bracket as printed, brackets included (`(每100毫升)`), as PR 3 stores it; the copy shows it without its brackets ("The label’s energy line says 每100毫升.").
- **An unheaded English table** has a shape, but every option declines `layout_not_supported` under the launch scope, so there is no sheet.
- **Change** keeps Confirm's model: the new option's review replaces the old one and the corrections are cleared (after the question), so Confirm's amount and time stay. A choice is stamped by the confirmation builder's clock.
- **Developer tools** show "Basis: <basis line>" with the hint note when shown, through the one formatter; the re-parse page stays with #273 (decision 25).
- **The 8.4.14 lows as built:** the flattened line scans the serving and pack segments together on the stripped text, so a second count or a 約 in the serving bracket (`每一份量 30公克 (約3份) 本包裝含 2份`) reaches the pack count; a serving number in full-width digits is never bound, bilingual or not.
- **Dev set (7.3), 21 October 2026, counts only:** 24 labels, 22 reach Confirm (4 of them after a basis choice, choosing the arrangement the label implies), 2 declined (`multiple_complete_panels` 1, `multiple_panels` 1); 275 values matched, 0 wrong; 10 rows printed but not read. The owner's value check of the development set is still outstanding (1.3).
- **From the invariant review and journey QA of #284:**
  - **Two unheaded columns and no serving size** decline `unheaded_columns_without_serving_size` with their own copy ("The columns have no headings and there is no serving size, so the app cannot tell what the values are for. Try copying the table with its headings."), through the code-to-copy table.
  - **Percentages with no printed reference header (narrowing of 8.4.1 rule 4).** Such percentages bind to no column, so the table has no shape and keeps today's `no_basis_header` decline. Supporting them would need a reference header with no printed text, which the v2 verifier forbids; a test pins the narrowing.
  - **G5 under a chosen basis** ("Only per serving values; the label does not print per 100 g", or per 100 mL for a serving in millilitres) applies only if a future layout raises G5 for a chosen basis: the Taiwan gate never raises it (G5 is UK only). The copy and its tests stay for that case.
  - **A bare `~` or `～`** (any mark of serving v3's list) on a Chinese-only pack line makes the count approximate.
  - **`at` and the capture.** The confirmation builder reads its clock once; if the clock moved backwards since the choice, `at` is re-stamped to the capture, so a rebuilt source still verifies and a save is never refused for it.
  - **A failed Change.** If the new option's source cannot be built, Confirm keeps its model (amount and time), its earlier choice and its corrections, and says "The values could not be changed. Your earlier choice is kept."; no new Confirm opens in its place.
  - **Confirm's pinned bar (#282).** At accessibility text sizes, or when the bar would hold more than two warnings, hints or estimates, only Log stays pinned; the warnings, the hint beside Log and the volume estimate move to a "Before you log" section at the end of the content, and warning text is never truncated. The Fortified? picker on the label text screen lists its answers inline at accessibility sizes.
- **From the final review of #284:**
  - **`at` in whole milliseconds on both sides.** `PastedLabelBasisChoice.milliseconds` truncates, with one tolerance: a value less than 1 µs (0.001 ms) from a whole millisecond, on either side, is that millisecond, so a value less than 1 µs below a whole millisecond rounds up to it (the only case where `at` is later than the clock's reading; a sub-millisecond part of 1 µs or more always truncates), so a capture that went through the store's millisecondsSince1970 Double round trip gives the same whole milliseconds as before it; a test saves and reopens re-stamped choices on both stores, on exact boundaries and with sub-millisecond parts.
  - **A serving size printed in another form** (for example `1包`) with two unheaded columns declines `unheaded_columns_serving_size_not_in_g_or_ml`: "… there is no serving size in grams or millilitres …".
  - **A disabled Log keeps one short line beside it** when only Log is pinned ("Not ready to log yet. See “Before you log” below."); the full hint, styled like the warnings (left-aligned, with an icon), is in "Before you log", which is never shown empty.
  - **A failed choice is never silent:** from Change, "The values could not be changed. Your earlier choice is kept."; after Read label, "This choice could not be applied. Nothing was saved, and your text is kept."
  - **The Change sheet's note** no longer mentions Search, which only the first sheet offers.

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

### 9.3 Added while building PR 3 (owner, in session, 20 October 2026)

23. **Basis printed only in the energy line.** A basis phrase printed only in a bracket on the energy line is never read as the column's basis, because a per 100 g bracket over values that are really per serving passes every check. The table is treated as having no basis header: it declines `no_basis_header` (today's copy) until PR 4, then the user chooses the basis on the sheet of 3.3, where the bracket as printed may be shown as a hint ("The label's energy line says 每100公克"), never preselected. The parser carries it as the warning `basis_hint: energy_line: <bracket>`. This replaces the rule of 3.5 and the pinned warning fixture of 7.5 item 14. **Decided: ask the user (owner, 20 Oct 2026).**

### 9.4 Added for PR 4 (owner, in session, 20 October 2026)

24. **The energy-line hint after the choice.** The `basis_hint: energy_line: …` warning stays in the stored candidate. When the hint names a basis other than the one the user chose, Confirm shows it as a visible note on the basis line ("The label's energy line says 每100毫升.") and records `basis_hint:energy_line` in `warnings_shown`; it is never a block and never changes the choice (8.4.11, 8.4.12). **Decided: yes (owner, 20 Oct 2026).**
25. **Developer tools re-parse deferred.** The Developer tools re-parse of a stored entry (5.3) stays deferred to issue #273. PR 4 pins the property it depends on at the adapter instead: `read(text, assertedBases: <from basis_choices>)` reproduces the stored candidate byte for byte (8.4.6). **Decided: yes (owner, 20 Oct 2026).**
26. **Contract 7 stays, with no migration.** The owner has never used a build carrying the paste route with real food, and no TestFlight build carried it, so no distributed build (5.1) carries contract 7. Under decision 13, contract 7 covers both manifest versions and the store stays `food-ledger-v7`. PR 4 records this evidence in its description. **Decided: yes (owner, 20 Oct 2026).**

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

## 12. Freeze (step 5a, 21 October 2026)

### 12.1 What is frozen

As of the commit that adds this section, the following are **frozen**:

| Component | Version |
|---|---|
| Parser | `nutrition-label-text-parser-v3`, with the layout precedence of 3.0 |
| Row aliases | `taiwan-row-aliases-v1` |
| Arithmetic checks for chosen-basis readings | `label-arithmetic-checks-v2` |
| Serving policy for a per 100 column of a parser-v3 manifest | `pasted-label-serving-v3`, with its grammar copy and its closed lists |
| Manifest for a chosen-basis reading | `pasted-nutrition-label-v2`, with its verifier, the options function of 8.4.3 and the `at` rule of 8.4.16 |

The versions they compose with were frozen earlier and stay so: `label-capture-decline-gate-v2`, `label-arithmetic-checks-v1`, `pasted-label-conversions-v1`, `pasted-label-format-inference-v1`, `pasted-nutrition-label-v1`, `pasted-label-serving-v1` and `-v2`, and the candidate schema `label-capture-candidate-v1`.

**The freeze reference** is the commit on `main` that merges the pull request adding this section. Its hash is recorded in the private run folder (12.3) and in the release-check pull request; it cannot be written here, because a commit cannot name itself. Section 5.1's "earlier of the release check's freeze commit and the first distribution" is settled: this is the freeze, and it comes before any distribution.

**After the freeze, any change to what a frozen version does is a new version** (parser v4, `taiwan-row-aliases-v2`, checks v3, serving v4, manifest v3), and a new version needs a **new fresh set** for its release check: the set collected under 12.2 measures this freeze and nothing else. A change that does not alter a frozen version's behaviour (a new version added beside it, a comment elsewhere) does not unfreeze anything.

**Pinned by a test.** `ReaderV3FreezeTests` (`Packages/FoodLedgerKit/Tests/FoodLabelTextCaptureTests/`) pins, with no label text:

1. the five version strings, and that new readings are written with parser v3;
2. a SHA-256 of a canonical listing of the frozen rule tables: the alias table and the recognised-but-not-stored list, the voluntary bracket, the layout precedence, the row markers, parser v3's approximation lists and a set of its patterns, the bound vocabulary, serving v3's grammar copy and closed lists, the serving method table, the admitted pipelines, the manifest versions, the options table and checks v2's constants. **Every list in it is filtered to the frozen versions** (the serving method table for parsers v2 and v3, the serving versions v1 to v3, the three frozen pipelines and the two manifest versions, each listed with whether it is still admitted), so adding a version is additive and leaves this hash unchanged. This hash never changes while these versions exist;
3. a SHA-256 of every file of the `NutritionLabelParsing` module (sources and resources; a new file there fails the test too), of the application files that implement serving v3, manifest v2 and the options function, of the files the fresh-set harness uses to read and bind values or to encode its results (`LabelReading.swift`, `PastedLabelSource.swift`, `PastedLabelConfirmation.swift`, `PastedLabelManifest.swift` and the adapter `NutritionLabelTextReader.swift`), and of the committed harness and scorer (`FreshSet/FreshSetProtocol.swift`, `FreshSet/FreshSetStepTests.swift`).

**Re-pin rules for pin 3, closed:**

- **A new version beside a frozen one** in a pinned file (for example serving v4 in the serving policy file): re-pin that file's hash, with pins 1 and 2 unchanged and the reason recorded under "Re-pins after the freeze" below.
- **A new file in `NutritionLabelParsing` holding only a new version** (for example a parser v4 type): add its key to the test, with pins 1 and 2 unchanged and the reason recorded below.
- **A comment-only change in a pinned file is still a change.** It is not made before the release check (12.2) has reported. After it, it needs a recorded re-pin whose pull request shows a diff of comments only, reviewed by an independent reviewer.
- **A change that alters what a frozen version does** is never re-pinned: it is a new version.

**Re-pins after the freeze:**

- `FreshSet/FreshSetProtocol.swift`, 23 October 2026: Amendment 3 (12.2.8), an owner decision before seal 2 and before any reader run on fresh text. It changes only the scorer's unit table (bilingual compound units) and the scoring of a non-numeric marker cell. Pins 1 and 2 are unchanged, and no reader file changes.

### 12.2 Fresh-set protocol (7.4, decisions 15, 20 and 22)

Written down in the same commit as the freeze, before any fresh label is collected, together with the committed harness and scorer (`Packages/FoodLedgerKit/Tests/FoodLabelTextCaptureTests/FreshSet/`, pinned by 12.1). Every step is mechanical; where a step meets a case it does not name, the label is skipped with the reason `other` and a one-line note in the skip log, never decided case by case. **Every `other` note is listed to the owner before the text seal**; the owner may only confirm the skip or record that the protocol is amended (in a new commit, before collection continues), never take the label in.

**Roles.** Four roles, kept apart:

- the **collector** (an agent or the owner) selects and saves labels under 12.2.1 to 12.2.4; it never runs the reader on a fresh text, and has never seen the development set's per-label results or the parser source (it may hold the exclusion list of 12.2.1);
- the **transcriber** (an agent in its own session) writes the expected values under 12.2.5; it never sees reader output, the parser source, this repository's tests or the development set's results;
- the **owner** verifies the transcriptions under 12.2.6 and makes the release decision;
- the **runner** (an agent or the owner) performs the run under 12.2.7 only after both seals of 12.2.6 exist.

#### 12.2.1 Exclusions: the development set

Every **site** and every **product** in the development set (1.1) is excluded. The development set's sites, by name only:

- retailers: 愛買 (FE Amart), PChome 24h 購物, 東森購物 (ETMall), Yahoo 奇摩購物中心, 全聯 (PX Go);
- manufacturer sites, by domain name: 00foods.com, green-n-safe.com, isun.hc.net.tw, oldpotrice.com, snackcontainerbase.com, top-most.com.tw;
- specification PDF sites, by domain name: emporium.com.tw, powerred.com.tw.

The retailers are excluded on every domain they use, image servers included.

The exclusion list itself (site, brand, product name and the SHA-256 of each development text) is kept **outside the repository**, as `excluded-development-set.json` in the private run folder (12.3), written before collection starts from the development set's own records. A fresh candidate is excluded when its site is on the list, when its brand and product name match a development product (a different pack size of the same product counts as the same product), or, after copying, when its text's SHA-256 equals a development text's. The repository gets only the number of candidates excluded this way.

#### 12.2.2 Strata and slots

24 slots, fixed in this order. Each slot names a category and a page kind (15 retailer pages, 5 manufacturer pages and 4 PDFs, as in the development set). Layout is never a stratum: the layouts are whatever the selected labels print, and layout is never a reason to take or skip a label.

| Slot | Category | Page kind |
|---|---|---|
| 1 | Snacks and biscuits | Retailer |
| 2 | Drinks | Retailer |
| 3 | Dairy | Retailer |
| 4 | Cereal and oats | Retailer |
| 5 | Sauces and condiments | Retailer |
| 6 | Instant noodles | Retailer |
| 7 | Frozen | Retailer |
| 8 | Confectionery | Retailer |
| 9 | Nuts and dried fruit | Retailer |
| 10 | Bread and bakery | Retailer |
| 11 | Snacks and biscuits | Retailer |
| 12 | Dairy | Retailer |
| 13 | Cereal and oats | Retailer |
| 14 | Nuts and dried fruit | Retailer |
| 15 | Bread and bakery | Retailer |
| 16 | Snacks and biscuits | Manufacturer |
| 17 | Drinks | Manufacturer |
| 18 | Dairy | Manufacturer |
| 19 | Cereal and oats | Manufacturer |
| 20 | Confectionery | Manufacturer |
| 21 | Drinks | PDF |
| 22 | Sauces and condiments | PDF |
| 23 | Instant noodles | PDF |
| 24 | Frozen | PDF |

Categories, each with its one search term and what belongs to it (a product outside its slot's definition is skipped `wrong_category`):

| Category | Search term | Belongs |
|---|---|---|
| Snacks and biscuits | 餅乾 | biscuits, crackers, cookies, crisps, puffed snacks |
| Drinks | 飲料 | ready-to-drink tea, juice, coffee, soy and soft drinks (not milk) |
| Dairy | 牛奶 | milk, flavoured milk, yoghurt, cheese |
| Cereal and oats | 燕麥 | oats, muesli, granola, breakfast cereal |
| Sauces and condiments | 醬料 | sauces, soy sauce, dressings, condiments |
| Instant noodles | 泡麵 | instant noodles, cup and bowl noodles |
| Frozen | 冷凍食品 | foods sold frozen (dumplings, meals, ice cream) |
| Confectionery | 糖果 | sweets, chocolate, gummies |
| Nuts and dried fruit | 堅果 | nuts, seeds, dried fruit |
| Bread and bakery | 麵包 | bread, toast, buns, cakes, pastries |

#### 12.2.3 Search procedure

**Retailer slots (1 to 15)**, in slot order, over this fixed list of retailers, none of them in the development set:

1. momo 購物網 (momoshop.com.tw)
2. 家樂福線上購物 (Carrefour Taiwan online)
3. 大潤發 (RT-Mart online)
4. 博客來 (books.com.tw)
5. friDay 購物
6. 樂天市場 (Rakuten Taiwan)
7. 生活市集 (buy123.com.tw)
8. 好市多線上購物 (Costco Taiwan online)
9. 屈臣氏 (Watsons Taiwan online)
10. 康是美 (Cosmed online)

Slot 1 starts at retailer 1. Each later retailer slot starts at the retailer after the one that supplied the previous retailer label, wrapping from 10 to 1. For the slot: on the current retailer, run the site's own search with the category's term, keep the site's default sort (record its name), and open the results **in listed order**, page after page, up to the first 20 results. A tile marked as an advertisement (廣告, 贊助, AD) is not a result. The first result that is eligible (12.2.4) fills the slot. If none of the first 20 is eligible, or the search returns nothing, the retailer is **exhausted for this category** (logged) and the slot moves to the next retailer in the list. A retailer that has supplied 2 labels is skipped (`site_cap`).

**Manufacturer slots (16 to 20) and PDF slots (21 to 24)**, in slot order: a web search on Google, signed out, in a private window, with the interface in Traditional Chinese and the region set to Taiwan. The query is the category's term followed by ` 營養標示` (manufacturer slots), or by ` 營養標示 filetype:pdf` (PDF slots). Open the organic results in listed order, up to the first 30; ads, "People also ask", image, video and shopping blocks are not results. A manufacturer slot takes the first eligible page on the brand owner's own site (the brand on the product is the site's owner, as its header, footer or about page states); a retailer, marketplace, news, blog, forum or recipe page is skipped `not_source_kind`. A PDF slot takes the first eligible PDF (served as a PDF) whose nutrition table has a text layer, from a manufacturer, importer or retailer. A site that has supplied 2 labels is skipped (`site_cap`), across all kinds.

**Fallbacks**, applied in this order and each logged:

1. A manufacturer or PDF slot with no eligible result in its first 30 becomes a retailer slot of the same category, filled by the retailer procedure in its slot position (`kind_fallback`).
2. A retailer slot for which every retailer is exhausted or capped is left unfilled (`slot_unfilled`).
3. If fewer than 24 labels are collected after slot 24, the slot table is walked again from slot 1, filling only unfilled slots and then, while still short, adding one more label per slot in slot order, under the same procedure and caps, until there are 24 labels or a full walk adds none.
4. Fewer than 20 labels after that: stop. There is no run; the shortfall and the skip counts are reported, and the protocol is amended in a new commit before any further collection.

**Recorded outside the repository for every result opened:** the slot, the site, the search term, the sort, the result position, the time, and either the label ID it became or its skip reason. Search results pages are saved as screenshots.

**Amendment 1 (owner, 21 October 2026, under fallback 4, before the text seal and before any reader run on fresh text).** The first collection walk reached slot 16 with 9 labels from 830 retailer results opened: most Taiwan retailer pages print the nutrition table as an image. Nothing about the collected labels' reader output was known when this amendment was made (the reader has not run on any fresh text). From this commit:

1. **Retailer result limit:** up to the first **50** results per retailer and category instead of 20. A retailer and category already searched under the old limit continue from result 21 in the same saved order (the first walk's search screenshots fix that order); a site that reshuffles on reload continues from the first load's screenshot.
2. **More retailers**, appended to the fixed list in this order, none in the development set: 11. 蝦皮購物 (shopee.tw), 12. 松果購物 (pcone.com.tw), 13. udn買東西 (shopping.udn.com), 14. 森森購物 (u-mall.com.tw). The rotation wraps from 14 to 1.
3. **Owner rulings on the first walk:** 萬家福線上購物 (online.uni-prosperity.com.tw), to which 家樂福線上購物 now redirects, is retailer 2; 大潤發 is unreachable and is logged exhausted each time its turn comes; listings sold by 愛買 are excluded on every site (it is a development-set retailer, so "excluded on every domain they use" covers its shops on marketplaces); the first walk's three `other` skips stand (a multi-flavour combo listing with no single contiguous table, and two ready-to-drink oat drinks that fit neither the Drinks nor the Cereal and oats definition).
4. **Environment for slots 16 to 24:** the Google search runs in a Safari private window (signed out), as written above; PDFs are copied from Preview as written in 12.2.4.

The nine labels already collected keep their IDs and slots. Collection resumes at slot 16, then applies fallbacks 1 to 4 with the amended limits; the re-walk of fallback 3 re-searches unfilled slots under the 50-result limit and the longer retailer list.

**Amendment 2 (owner, 22 October 2026, before the text seal and before any reader run on fresh text).** The resumed walk stopped at slot 21 with 14 labels: three of the four retailers added by Amendment 1 are closed or block automated visits (蝦皮購物 shows a traffic-verification page, udn買東西 closed in 2021, 森森購物 closed in 2025 and points to a development-set retailer), and the working retailers are near their caps. From this commit:

1. **Site cap:** at most **3** labels per site instead of 2, across all page kinds. A retailer previously skipped `site_cap` at 2 labels is eligible again for its third.
2. **PDF slots (21 to 24):** each candidate PDF is listed to the owner (file name, site and size) before it is downloaded; only listed and approved files are saved, into the private folder, and opened in Preview.
3. **Owner ruling on the resumed walk:** its `other` skip stands (a brand-site category page listing several products, each with its own one-line 營養標示, with no single contiguous nutrition section).

The fourteen labels already collected keep their IDs and slots. Collection resumes at slot 21, then applies fallback 3 (the re-walk of unfilled slots, then one more label per slot in slot order) under the 50-result limit and the cap of 3, and fallback 4 if still short of 20.

#### 12.2.4 Eligibility and skip reasons

A result is **eligible** when all of these hold:

1. it is a food sold in Taiwan, with a page in Traditional Chinese and a Taiwan nutrition table (營養標示, or a table with the Taiwan template's rows in Chinese);
2. the nutrition table is **selectable text**: in the page's HTML, or in a PDF's text layer. A table that is only an image (or only inside an image of the pack) is not;
3. it is not in the development set (12.2.1) and not a duplicate of a label already collected (same brand and product name; a different pack size is a duplicate, a different flavour is not);
4. it is not a supplement: no capsules, tablets, powders sold as 保健食品, 營養補充品 or 膳食補充品, no infant formula and no food for special medical purposes;
5. it is in its slot's category (12.2.2);
6. the page opens without a login, a CAPTCHA or a regional block;
7. its site has supplied fewer than 2 labels.

**Skip reasons (closed list):** `table_image`, `no_nutrition_table`, `blocked`, `duplicate`, `development_set`, `non_taiwan`, `supplement`, `wrong_category`, `not_source_kind`, `site_cap`, `other` (with a one-line note). A page holding two or more panels (two flavours) is eligible: it is a layout as it occurs.

**Saving an eligible label.** On the product page as it loads (the default variant when the page has a selector):

1. a full-page screenshot, and a screenshot in which the whole nutrition table is legible (for a PDF, the page or pages holding the table, rendered as images), saved in `collection/<label ID>/`;
2. the **pasted text**: select from the first line of the nutrition section (the 營養標示 title or, with no title, the first serving line or column heading) to the last line of the table, including footnotes directly under it, copy with the system copy command in Safari on macOS (Preview for a PDF), and save the clipboard's plain text exactly as copied, in UTF-8, with no edit of any kind, as `texts/<label ID>.txt`;
3. `collection/<label ID>/source.json`: the label ID (F01, F02, … in collection order), slot, category, page kind, site name, page address and time of capture.

The **text seal** follows the owner's review of the `other` notes: the committed step `seal-texts` (below) records in `seals.txt` the SHA-256 of a listing of `<sha256>  texts/<label ID>.txt` lines, sorted, with the number of files and the UTC time. From that moment the texts are frozen: no text is edited, added or removed.

**The committed steps.** Each step is one opt-in test run, skipped in the gates:

```
WHR_FRESH_SET_DIR=<private folder> WHR_FRESH_SET_STEP=<step> swift test --package-path Packages/FoodLedgerKit --filter FreshSetStepTests
```

with `<step>` one of `seal-texts`, `validate`, `seal-1`, `seal-2`, `run` and `score`. The private folder must be absolute and outside every git checkout (the step refuses a folder with a `.git` in any ancestor). A seal is never replaced, and each requires the one before it.

#### 12.2.5 Blind transcription (decision 22)

The transcriber, in a session of its own, receives **only** each label's screenshots and its PDF page renders where present, and these instructions. It **never** sees the pasted text, reader output, this repository's sources or tests, Developer tools or the development set's files. For each label it writes one file, `transcription/<label ID>.json`, holding what the label as shown in the screenshot prints, in the schema `reader-v3-fresh-transcription-v1`:

- `label_id`; `serving_size`: `{number, unit}` as printed, or `null` when not printed. When the serving prints a count and a weight or volume (`1片(30公克)`), the transcriber records the **weight or volume** (`30`, `公克`), which is what the reader binds; the count alone is recorded (with `outside_table`) only when no weight or volume is printed; `servings_per_pack`: `{number, approximate}` (approximate when 約 or "about" is printed), or `null`;
- `columns`, in printed order: `{heading, basis}`, where `heading` is the heading as printed (or `null` when the label prints none) and `basis` is `per_serving`, `per_100g`, `per_100ml` or `reference_intake` as the heading states it, or `null` when the label states no basis for that column anywhere;
- `rows`, in printed order: `{label, nutrient, values}`, where `nutrient` is one of `energy_kcal`, `energy_kj`, `protein`, `fat`, `saturates`, `trans_fat`, `carbohydrate`, `sugars`, `added_sugars`, `fibre`, `sodium`, `salt` or `other`, and `values` has one entry per column: `{comparator, number, unit}` as printed (comparator `=`, `<` or `<=`; the number in ASCII digits with at most one decimal point; the unit exactly as printed), or `null` when that column prints nothing for the row;
- `notes`: anything else, in plain words.

**Every printed form is recorded verbatim**, never adjusted to fit; the scorer maps comparators and units through its closed equivalence tables (12.2.8) before comparing. A form with no mapping there is recorded verbatim too: a unit such as 公撮, 片, 包 or full-width ｇ, a comparator such as `>`, a number that is not plain ASCII digits (full-width digits), or a serving printed only as a count (`2片`). A number with a comma (`1,5`) is recorded as printed too; it needs `outside_table` only where the comma rule of 12.2.8 cannot read it on that row. Such a value or serving size carries `"outside_table": true`. The step `validate` accepts it; it refuses only a value outside the lists that is **not** marked, so no label becomes impossible to transcribe after the text seal.

**A bilingual unit is recorded as printed** (`大卡/kcal`, `公克(g)`); it needs no `outside_table` when both parts map to the same canonical unit (Amendment 3, 12.2.8).

**A value cell that prints a non-numeric marker instead of a number** (for example the `*` of a reference-intake column whose reference value is not established) is recorded in exactly this form: `{"comparator": "=", "number": "<the marker as printed>", "unit": "", "outside_table": true}`, where the marker holds no digit (Amendment 3). `validate` accepts it.

The step `validate` checks every file against the schema and the unit table of 12.2.8; a file that fails is fixed by the transcriber before seal 1. When every file passes, the step `seal-1` records **seal 1**: the SHA-256 of the sorted per-file listing of `transcription/`, with the UTC time, before any reader run.

#### 12.2.6 Owner verification

The owner checks each transcription against its source on a local **review page** (an HTML file in the private run folder, never published): for each label, the screenshots and the transcription side by side, with a mark per value ("as printed" or "corrected to …"). The page states seal 1's hash at the top (and seal 2's, once recorded). There is no reader output anywhere on it, because the reader has not run.

Every owner correction is logged in `transcription-corrections.json` (label, value, before, after, reason) as a **transcription correction**, never as a reader result, and applied to the transcription file. When the owner has verified every label, the step `seal-2` records **seal 2**, and the review page is regenerated to show seal 2's hash beside seal 1's. The run may start only after seal 2. The release-check pull request records the date of seal 2 and the number of labels it covers, never its hash.

**The seal-2 transcription is final for scoring.** A dispute raised after the run (the owner or anyone else thinks a transcribed value is wrong) does not change it: the reader's value is still scored against seal 2, a disputed value counts as a **wrong value** when it differs, and the dispute is reported beside it; a dispute is never used to pass. **Any change to a transcription after seal 2 voids the run**: the steps `run` and `score` refuse to work when the transcriptions or the texts differ from their seals.

#### 12.2.7 The run

1. **Build.** Check out the freeze reference. The harness is the committed step `run` (`FreshSetProtocol.swift`): the app's Read label decision, `PastedLabelReader` with `NutritionLabelTextReader` and `SHA256Digester`, one JSON result per text in `run/`, in the schema `reader-v3-fresh-run-v1`. Record the commit in `run-log.txt`; the harness and scorer files are pinned by 12.1, so the commit fixes them.
2. **Basis choices without judgement.** When the outcome is "needs a basis choice", the harness chooses the arrangement whose bases are the seal-2 transcription's amount column bases, in column order, through the application's choosing step. When any of those bases is `null` (the label states no basis either), the label counts as **declined** `basis_not_sure`, as "I'm not sure" would end it; when the arrangement is not among the options offered, it counts as declined `basis_not_offered`.
3. **One run** is one execution of the harness over every frozen text. An **infrastructure failure** is a failure of the environment, not of the reader: a build, tool or machine failure that produces no reader output for a label. It is rerun **once** with **no change** to code, harness, texts or transcriptions, for the labels that have no output (the step `run` skips labels that have one); each attempt is recorded in `run-log.txt`: before any label is read, a start line with the UTC time, the commit (taken from the checkout, which must have no local change) and the labels without output, then one `wrote <label>` line per output. The step refuses a third attempt, and refuses to start when `run/` holds an output the log does not account for. A failure that repeats on that unchanged rerun of the same text counts as a **reader defect** and fails the check. Any output the reader produced counts, and its results stand.
4. **Device build.** The owner pastes each frozen text into a build of the freeze reference on the owner's iPhone (the distribution of 5.1, which the freeze allows). Where the basis sheet appears, the owner chooses by the same rule as item 2: the seal-2 transcription's bases, and "I'm not sure" when a basis is `null` or the arrangement is not offered. The owner records, per label, the outcome and every value Confirm shows. Each displayed value is scored in the same way as the harness's, and the device's outcome must equal the harness's; a difference is reported as a defect, and a wrong value on the device fails the check like one in the harness.
5. **Owner's check, as a user.** On each accepted Confirm of the device build, the owner then checks the values against the label image as a user would and corrects what they notice; this check never changes the scoring of items 1 to 4. The values that still differ from the seal-2 transcription after that check are the **residual errors after the owner's check** (7.4 item 6, v1 section 9), reported, not gating.

#### 12.2.8 Scoring and the bar

The step `score` (`FreshSet.score`) applies these rules exactly; they were fixed before collection.

**Equivalence tables** (the scorer's own, closed, fixed before collection). The transcriber records the printed form; the scorer maps it here before comparing. A printed form with no mapping stays `outside_table`: a reader value bound to it is wrong, and leaving it unread is not.

- **Comparators:** `=` → `=`; `<`, `＜`, 未滿, 少於 → `<`; `<=`, `≦`, `≤`, 以下 → `<=`.
- **Units**, looked up exactly or, failing that, lowercased (so kCal, KCAL, Kj, G, MG, Ml and mL all map): 大卡, 千卡, kcal → kcal; cal (so Cal) → cal, kept apart from kcal because the reader binds `Cal` as its own `cal` on a row it does not recognise, in a table that reaches Confirm (an energy row in Cal is left unread, 3.9); kj, 千焦 → kJ; 公克, 克, g, gr, gm → g; 毫克, mg → mg; 微克, µg, μg, mcg → µg; 毫升, ml, cc → ml; % → %. Full-width forms (ｇ) are not mapped.
- **Compound units (Amendment 3):** two units of the table joined by `/` or `／` (`大卡/kcal`, `毫升/mL`), or with the second in ASCII or full-width brackets (`公克(g)`, `毫克（mg）`), map to their canonical unit when **both parts map to the same one**. Parts that map to different canonical units (`公克/mg`), or that do not map, leave the compound unmapped, so it stays `outside_table`.
- **Numbers with a comma**, printed or read, use **exactly the reader's per-row comma rule**, by calling the reader's own function (`ParseStateV3.isAmbiguousNumber`) with the row's label: a comma followed by exactly three digits (`1,500`), or any comma on a Taiwan alias row (`脂肪 1,5公克`), is ambiguous, so the number is unparsable; any other single comma between digits is a decimal point (`維生素C 1,5毫克` is 1.5). The transcriber's verbatim number is read with the transcription row's label and the reader's `decimal_text` with the cell's label. An unparsable number bound by the reader is wrong; unread, it is not. Serving and pack lines holding a comma are never read by the reader (8.3), so their numbers are plain decimals. A parity test checks the rule against the reader on synthetic rows.

**Columns.** A reader header is matched to the one transcription column with the same `basis`. When the transcription has **two or more columns with that basis** (for example per 100 g as sold and per 100 g as prepared), the header is matched by position among the **amount columns** (reference-intake columns are left out on both sides) only when the reader read exactly the transcription's amount columns, in the same order and with the same bases; otherwise the match is ambiguous and every value bound under that header is a wrong value. The first column of a basis is never taken silently.

**Rows.** A recognised cell is matched to the one transcription row with its `nutrient`. A cell the reader did not recognise is matched, by **normalised label**, to the one transcription row with the same normalised label, **whatever that row's nutrient**; the match makes its value comparable but never counts as reading that nutrient (the burden ignores it). Normalisation, applied to the transcriber's and the reader's label alike: Unicode compatibility mapping (full-width letters, digits, brackets and colons to their ASCII forms); every whitespace character removed; leading row markers removed (`>>`, `>`, `•`, `·`, `▲`, `●`, `*`, `-`, repeatedly); a trailing colon removed; every bracket group whose content is a unit of the unit table removed (`(毫克)`, `(公克)`, `(g)`); one trailing `(自願標示者)` or `(自願標示)` removed; Latin letters lowercased. A label that normalises to nothing (only markers, spaces or a colon) never matches anything. No match, or more than one, is a wrong value.

**A value checked** is every value the reader binds in a table that reaches Confirm: every cell in every column, every calculated value, the serving size and the pack count.

**A wrong value** is a checked value for which any of these holds:

- its comparator differs from the transcription's, mapped through the comparator table (or the printed comparator has no mapping);
- its number differs from the transcription's number by exact decimal equality (6.0 equals 6, nothing else is equal), or either number is unparsable;
- its canonical unit differs from the transcription unit mapped through the unit table (or the printed unit has no mapping);
- it is bound where the transcription has `null` (not printed);
- for the serving size (scored whenever the reader recorded a number, with or without a canonical unit): its number differs, the label prints no serving size, or the reader recorded a canonical unit that differs from the transcription unit mapped through the table; for the pack count, its number or its "approximate" mark differs;
- **for a calculated value** (kJ to kcal, salt to sodium, `pasted-label-conversions-v1`): its operand (the printed source value, with the source cell's comparator, and the operand unit in canonical form: `kJ`, or `g_salt` as grams) differs from the transcription's printed source value. This is the **only** gate on a calculated value: with a correct operand, the value is the conversion rule's arithmetic, which is fixed by the conversion's version and its own tests.

**Calculated beside printed (reported, never gating).** `pasted-label-conversions-v1` calculates kcal whenever the stored column has a kJ cell and no kcal cell, and sodium likewise from salt, so a printed kcal (or sodium) row the reader left unread gets a calculated value on Confirm. When the label prints that target in the column, the score reports a **calculated vs printed discrepancy** (both values and their difference, or "not comparable" for another comparator or unit), counts it, and counts the unread printed row in the correction burden; it never makes the calculated value wrong. The reason: labels compute kcal from the macronutrients with factors (for example the EU's, or Taiwan's own rounding rules) that need not equal 1 kcal = 4.184 kJ, and sodium printed beside salt may be rounded independently, so a difference measures the label's own arithmetic, not a reader binding error. A printed target recorded `outside_table` is never compared.

A row the reader leaves "Not read" is not a wrong value; it counts toward the correction burden.

**A non-numeric marker cell (Amendment 3).** Where the transcription records a marker (12.2.5), the reader leaving that cell unbound is not wrong, and binding it as exactly the same marker is not wrong; binding any number there is a wrong value.

**Amendment 3 (owner, 23 October 2026, in session, before seal 2 and before any reader run on fresh text).** The owner's verification found bilingual units printed as one unit (`大卡/kcal`, `公克(g)`) and three reference-intake cells that print only `*`. The owner's ruling: keep bilingual units as printed, and the scorer's tables must admit these printed forms. From this commit, the compound-unit rule and the marker form and scoring above apply. The reader's rules are untouched (pin 2 unchanged); the scorer file is re-pinned (12.1).

**The bar (gating): zero wrong values** in every table that reaches Confirm, harness and device build alike, including values under a basis chosen as in 12.2.7 items 2 and 4. **Any wrong value fails the check:** release stops, the fix is a new parser version (or a new version of whichever frozen component caused it), and **the set is spent**: it becomes development evidence, and the next release check needs a new fresh set, collected under a protocol committed with that version's freeze.

**Reported, not gating** (repository counts only; the step `score` writes them to `results/summary.json`):

- **decline rate**: labels declined (including `basis_not_sure` and `basis_not_offered`) out of all labels, with counts by reason; goal **at most 25%** (decision 16);
- **correction burden**: per accepted table, the stored column's ledger values (energy, protein, fat, saturated fat, carbohydrate, sugars, fibre, sodium) that the label prints but Confirm leaves unread (a calculated kcal or sodium counts as read only when the label does not print the target in that column and its conversion reads the stored column; a printed target left unread counts, even beside a calculated value), plus the serving size and pack count printed but not read; the mean, the **median (goal at most 1)** and the share of tables needing any;
- rows "Printed but not read", basis choices needed, flags and warnings shown, by code;
- **calculated vs printed discrepancies**: their number and, outside the repository, their sizes;
- **residual errors after the owner's check** (12.2.7 item 5);
- disputes raised after the run, each beside the value it concerns;
- the **statistical limit**: with n values checked and zero wrong, the per-value wrong-value rate is below 3/n with 95% confidence (the rule of three); with t tables reaching Confirm and none wrong, the per-table rate is below 3/t. The report states both with the actual n and t, and never claims a zero rate.

Missing the decline or burden goal does not block release when the bar passes; it is reported and informs the next version.

### 12.3 Privacy (decision 20)

All real-text material lives in one private folder, **outside every git checkout and outside synced cloud storage**: `~/WHR-label-eval-private/reader-v3-fresh-set/`, with `excluded-development-set.json`, `collection/` (per-label folders, the skip log, search screenshots), `texts/`, `seals.txt`, `transcription/`, `transcription-corrections.json`, `review/`, `run/` and `results/`. Texts, screenshots, page addresses, product names, transcriptions, per-label results and **every hash** (text, bundle and seal hashes) stay there. Tools write only there. Seal hashes appear only in `seals.txt` and on the private review page; the release-check pull request states that seal 1 and seal 2 were "recorded before the run", with their dates and the number of labels seal 2 covers, and never quotes a hash.

The **repository** receives counts only: labels collected by category and page kind, candidates opened, skips by reason, development-set exclusions, fallbacks used, and the results of 12.2.8; plus the freeze reference commit and the dates of seal 1, seal 2 and the run. Every pull request touching the fresh set carries the checklist item of 1.4.

### 12.4 Next

Step 5b, after this freeze merges: build the exclusion list, collect under 12.2, transcribe, verify, run once and report counts in a results file and in the release-check pull request, with the `docs/releases/unreleased.md` row.

### 12.5 Carried from the final review of #284 (presentation only, in the freeze commit)

None of these changes a frozen version.

- **A failed choice is said after the sheet has gone.** Choosing clears the sheet before the failure is known, and an alert raised on the presenting screen while its sheet is still dismissing can be dropped. The failure now waits in the view model and is raised from the sheet's `onDismiss` (`basisSheetDidDisappear`), for the first sheet ("This choice could not be applied. …") and for Change ("The values could not be changed. …") alike; closing the screen drops a waiting failure.
- **"Before you log"** is shown through `FoodConfirmationView.showsBeforeLog(pinsOnlyLog:…)` with the view's own `pinsOnlyLog`, so the tested function and the view use one condition.
- **The Change sheet's note.** `PastedLabelBasisSheetView.offersSearch(hasSearch:fromChange:)` is the one condition for the Search button and the footer's note, with a view-level test on the first sheet and the Change sheet.
- **`at` wording.** The 1 µs tolerance of `PastedLabelBasisChoice.milliseconds` is stated exactly (8.4.6, 8.4.16), with boundary tests.
