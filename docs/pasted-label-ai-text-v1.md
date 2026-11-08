# Pasted label AI reading v1: text first (#416)

Status: **draft spec, revision 15, 8 November 2026.** The owner decided D2 to D25 on 7 November 2026 and D26 to D33 on 8 November 2026 (section 9), including the evaluation egress terms T1 to T7. The product route's egress terms (T8 to T12) still need line-by-line approval before the route sends anything. The gate history is: revision 1 FAIL, then PASS WITH CHANGES on revisions 2, 3 and 4, with revision 5 closing the last wording gaps and the local Qodo findings. Revision 6 records A1's implementation amendments: the full-width boundaries and the attention rules for hidden cells, comparator words, glued basis quantities and nested labels (4.3), the unit and vocabulary details (4.2, 4.4), the offer and detector details (4.6, 4.7), D23, and the items moved to A5. A1's pure checks exist as code. Revision 7 records A2's implementation amendments: bound words and their direction (4.3), bare numbers as attention (4.2), the envelope check's home (11.1), W and the cache (5.2), the scorer's name and the day record (4.2). Revision 8 gives the text evaluation its own spend ledger (D26, 5.2 and T5), after the #426 Qodo findings. Revision 9 (A3, 8 November 2026) adds the evaluation tool's live mode, its retries and the no-generation rule (5.2 item 1). Revision 10 (A3, 8 November 2026, approved by the owner from the tuning v1 triage, causes B, D and G) fixes deterministic checks that declined or dropped values the model read correctly: the detector's Taiwan title rule (detector v2, 4.7), the text route's format step (4.7), and the bracket rule and the kcal spellings (mapping v2 and locator v2, 4.2 and 4.3). No check produces a value. Revision 11 (A3, 8 November 2026) makes the prompt version a closed parameter of the request builder (5.2 item 1) and adds `prompt-v2` for tuning; the app still sends `prompt-v1`. Revision 12 (A3, 8 November 2026, D28) moves the scorer to `pasted-label-ai-text-scorer-v3`: values in reference-intake amount columns are no longer printed fields (5.2 item 2 and 5.2.1). The comparison rules of `uk-fresh-scorer-v2`, the bar in 5.3 and `bar-v1.json` are unchanged. Revision 13 (A3, 8 November 2026, D29) moves the scorer to `pasted-label-ai-text-scorer-v4`: values on unrecognised rows are no longer printed fields. Revision 14 (A3, 8 November 2026, D30) reads a printed dash, `Trace` or `Tr` that the locator finds at its row and column as not declared (mapping v3 and locator v3, 4.2 and 4.3 item 11): shown as printed, never zero and never a stored value, and on its own no longer a reason the table is not ready. The scorer is unchanged. Revision 15 (A3, 8 November 2026, D31 to D33) moves the scorer to `pasted-label-ai-text-scorer-v5`, which pairs two or more %RI columns in printed order (D31) and reads a lone `*` as a class marker (D32); reads a lone `*` in a %RI column as not declared, like a dash (mapping v4 and locator v4, D32); and declines a reply whose header names two bases, such as `per 100g/ml` (vocabulary v2, D33). The prompts, the bar and `bar-v1.json` are unchanged. The product route has still sent nothing.

## 1. Problem

The deterministic pasted-label reader declines most real UK text. The UK reader v2 release check (P4 results, section 2 of `docs/pasted-nutrition-label-uk-english-v2-p4.md` in [syamaner/WeeklyHealthReport#415](https://github.com/syamaner/WeeklyHealthReport/pull/415)) held the bar, with 0 wrong values, but 19 of 24 fresh labels declined. None of the 9 labels from new sites reached Confirm. v1 was 20 of 24. The decline causes are mostly layout (counts that do not line up, values printed without units), which further rules would chase site by site.

The [label photo route](label-photo-ai-prefill-v1.md) already reads Taiwan label photos with a model through OpenRouter, ending on the shared Confirm with attention items. Pasted text is an easier input than a photo: every value the model returns can be checked character by character against the text the user pasted.

## 2. Owner decisions (7 November 2026, verbatim)

> why don't we fall back to open router?

> So we prepare eval data set and tweak the prompt versions and various models. Once txt works, we do images.

> We park parsing completely and go with open router

Then, asked what happens to the shipped Taiwan reader: **"Freeze it, AI for the rest"**.

Read as:

1. **Parsing is parked.** No new reader version and no new parser rules for any format.
2. **The Taiwan reader stays frozen as it ships.** A paste it reads reaches Confirm exactly as today.
3. **Declined pastes can go to OpenRouter.** Any paste the reader declines, every UK paste included, can be read by a model on an explicit user action, ending on the shared Confirm.
4. **Evaluation first.** An evaluation set is prepared, and prompt versions and models are compared on it before anything ships.
5. **Text before images.** Label photos beyond Taiwan follow once the text route works.

## 3. User journey

1. Add food, then Paste nutrition label, exactly as today.
2. **The reader reads it:** Confirm, unchanged.
3. **The reader declines:** the decline message stays, and below it a **Read with AI** action appears beside a one-line statement that the pasted text goes to OpenRouter and the model. The first use on a device shows a one-time confirmation sheet, as on the photo route.
4. **Reading:** a progress state with Cancel. Retries are visible.
5. **Confirm:**
   - a fixed line saying the values were read by AI from the pasted text and must be checked;
   - the pasted text shown beside the values, with each value's source highlighted;
   - attention items that block Log until resolved, as photo route decision P12;
   - fortification asked as today.
6. **Failed or declined AI read:** an explicit state with Try again (a new tap that counts toward the limits) and manual entry. Unknown is never zero.

No automatic send. A paste never leaves the device unless the user taps Read with AI.

## 4. Design

### 4.1 Called, not copied

These existing pieces are type-neutral and are called unchanged. Their files stay byte-identical, and `LabelPhotoFreezeTests` passes with no re-pin:

- decline gate v2 (with `.uk` for UK candidates), `pasted-label-conversions-v1` and `label-arithmetic-checks-v2`, called from the new adapter target (11.1);
- `LabelPhotoAttention.items` (`label-photo-attention-v1`), unchanged and composed by the text attention version;
- the retry policy and the provider-identity rules (photo spec 17.18 and 17.21);
- the shared Confirm sections protocol, atomic Log and fortification C1 to C12.

### 4.2 New, owned by the text route

The photo pieces below are image-typed or Taiwan-only, so the text route has its own:

| Piece | Why it is new | Text route |
|---|---|---|
| Reader adapter | `LabelPhotoReader` admits Taiwan only | A text reader adapter calling the gate with Taiwan or `.uk` |
| Request and attempt port | The photo body is an image data URI with schema `label_image_extraction_v1`, and `LabelPhotoAttempting` takes a `PreparedLabelImage` | A text-only request builder (instruction and schema pinned by SHA) and a `PastedLabelAITextAttempting` port |
| Route set | `LabelPhotoRoute` is a closed set of photo routes | `PastedLabelAITextRoute`, its own closed set |
| Wire schema | `label-photo-wire-schema-v1` has no unit member (`LabelPhotoWire.Value` holds a header ID and printed text only) | `pasted-label-ai-text-wire-schema-v1`: printed text as printed, plus an optional `unit` member the model fills only for a bare number, with its own strict decoder and goldens |
| Mapping | `label-photo-wire-mapping-v1` takes units from row labels for energy only | `pasted-label-ai-text-mapping-v4` (v1 until revision 10, v2 until revision 14, v3 until revision 15), in a new file with its own copy of `parseValue`. Its unit table and comparators are the closed lists in the application layer (11.1), because the photo copy is internal to a pinned file. Parity with the photo copy is tested, except for the thousands rule in 4.3 and the two revision 10 rules in 4.3 item 2 (brackets and kcal spellings). Otherwise as v1, except that the model's unit for a bare number is accepted only when the sent text states that unit for the values (D10), and otherwise is an attention item. A unit is stated for the values when it is:<br>- a unit-only token in the column's header, such as `(g)`, `g` or `mg`; or<br>- a unit-only token in the row's label, such as `Fat (g)`.<br>A number followed by a unit in a header (`per 100 g`, `100g`, `per 30 g serving`) is the basis quantity and never states a unit (D16). A bare number for which the model gives no unit is a not-read cell with a blocking `unit_not_stated` attention item, so the user is always prompted and the value is never read, nor does a unit with a digit just before it, even across a space (`per100 g`, `每100 公克`). The row label's region runs from the label to the first value token on its line. A row label that states a unit overrides the header, a unit outside the closed table is not stated, and a printed unit that conflicts with the model's unit is attention. Parity with v1 on every v1 vector where a unit is printed. From v3 (D30), a value printed as a dash (`-`, `–`, `—`), `Trace` or `Tr` (any letter case) that the locator finds at its row and column with no attention item is `not_declared`: never a cell, never zero, never a stored value and not a left-out amount. A marker the locator does not find there stays a not-read value the user enters. From v4 (D32), a value printed as a lone `*` under a reference-intake header is a not-declared marker on the same terms; a `*` attached to a number (`7%*`) or a heading is a footnote and unchanged, and a lone `*` under a product-amount header stays unreadable |
| Attention | The `label-photo-attention-v1` reasons are a closed, pinned set | `pasted-label-ai-text-attention-v1` in a new file: composes v1 and adds the reasons `unit_not_stated`, `vocabulary_mismatch` and `label_unknown`, with goldens |
| Spend | `LabelPhotoSpendPolicy` has a fixed 6,000-token ceiling and per-tap limit, and an unversioned day record | A per-route spend policy over one versioned shared day record (D14). It replaces `LabelPhotoSpendPolicy`'s day record (not pinned), so the photo route's read and write paths change in the same PR and count against the shared record. The day record is mutable working state, not a food record, so the rule that records re-encode unchanged does not apply to it. An unversioned record keeps every value it had when it is first rewritten with its version and an empty text share. An over-ceiling text read pauses only the text route (D17). Existing day records are read as photo-only, and a corrupt record fails closed |
| Route checker | `OpenRouterLabelRouteChecker` accepts photo routes only | A text route checker with a parity test against the photo checker's rules |
| Locator | The Vision locator needs an image | `pasted-label-text-locate-v4` (4.3; v1 until revision 10, v2 until revision 14, v3 until revision 15) |
| Assignment check | None exists | `pasted-label-ai-text-vocabulary-v2` (4.4, D11; v1 until revision 15, D33) |
| Scope and identity | `.ukDevelopment` is a harness policy, and confirmation refuses any identity but v1 | A text-route scope type in a new file (D8), and a new recorded identity contract `pasted-label-ai-text-identity-v1` that writes the UK as-sold rules into each manifest (D9) |
| Manifest, source and verifier | Photo evidence requires `.packageImage`, JPEG, an image hash and route `"C"` | `PastedLabelAITextManifest`, `PastedLabelAITextSource` and its verifier (4.5) |

### 4.3 Text locator `pasted-label-text-locate-v4`

A pure, deterministic check of the model's answer against the text. It never produces a value (D3).

1. **Input:** the sent text, byte-identical to what was hashed and stored. Offsets are counted in Unicode scalars.
2. **Token grammar:**
   - A value token has three parts:
     - an optional comparator;
     - a number in Unicode decimal digits (general category Nd, as the copied `parseValue` accepts), with at most one decimal mark;
     - an optional unit or `%`.

     Comparators and units come from closed lists held in the application layer (11.1). The text target's copy of `parseValue` uses the same lists (4.2), including `＜` and `少於` and the Taiwan units such as `公克`, `毫克` and `大卡`. Inside a token, only spaces, tabs, U+00A0 or U+202F may sit between the parts.
   - **A token is the longest grammar match** that starts and ends at a boundary. Spaces inside it do not split it, so `5 g` and `less than 0.5 g` are each one token.
   - **Decimal mark:** a `.`, or a `,` between two digits that is not a thousands separator (next item). Any other `,` is a boundary, so `0,5g` is one token and `5g, 2g` is two.
   - **Thousands separator:** a `,` followed by exactly three digits and then a non-digit is a thousands separator, so `1,046kJ` is 1046 and `0,5g` is 0.5. A token with both a thousands `,` and a decimal mark (`1,046.5`) is read the same way. A thousands group led by `0` (`0,500g`) is ambiguous, so the A2 mapping makes it an attention item rather than reading 500. The photo copy reads every `,` as a decimal mark, so parity excludes this rule, and a vector covers it.
   - **Token boundaries:** start or end of line, whitespace (U+00A0 and U+202F included) outside a token, or one of `( ) [ ] ; : /`, `|` and a boundary `,`, together with their full-width forms `（ ） ［ ］ ； ： ／ ｜ ，` and the ideographic `、` and `。`. A CJK letter touching a value is not a boundary, so that value is not a token. So `1g` never matches inside `11g` or `0.1g`.
   - Trailing `*` and `†` footnote marks are kept as printed and ignored for matching.
   - A full-width `，` between two digits is neither a decimal mark nor a boundary, so no token forms there and the value is attention.
   - **Bound words around a token:** the check looks past spaces and punctuation on the token's line.
     - **Left:** a comparator word in any letter case, a closed list of bound words (Taiwan `未滿` `少於` `低於` `不到` `小於`; English `less than`, `under`, `below`, `up to`, `max` and similar), or a math-symbol (Unicode Sm) scalar that is not itself a listed comparator (`≦`, `~`).
     - **Right:** a closed list of words (`以下`, `以內`, `or less`, `max`, `maximum`, `or under`, `or below`).

     A token without its own comparator that has a bound word on either side is attention. A token that prints its own comparator ignores a bound word that agrees with that comparator's direction (`<= 0.5g or less`). A word that conflicts with it (`<5g or more`, `少於5毫克以上`) is attention. A bound is never read as an exact value.
   - The model's printed text must equal one token exactly, after that normalisation. Nothing else is normalised, except the two revision 10 rules (locator v2 and mapping v2):
     - **Brackets:** a model may copy the brackets a label prints around a value (`(4.9g)`, or `1.1g)` from a row printed as `(of which saturates 1.1g)`). One outer `(` `)` pair, one lone leading opener or one lone trailing closer (full-width forms included) is dropped from the model's text, and the value is found only where the sent text prints those same brackets right beside the token. Nested brackets, a bracket inside the text and a trailing echo (`5 g (g)`) are unchanged, and a bracketed bare number (`(35)`) is never read.
     - **kcal spellings:** `Kcal`, `kCal`, `KCal` and `KCAL` are text-only units for kcal, which the closed table already maps case-insensitively; each names kcal and nothing else. The photo list and its parity are unchanged. `Cal` stays outside the table, so `28.0Cal` is still a not-read attention item.
3. **Whole words.**
   - **Definitions:**
     - *CJK* means Script=Han, Hiragana or Katakana;
     - *punctuation* means general category P*;
     - *whitespace* means White_Space.
   - **Latin script:** bounded by line edges, whitespace or punctuation.
   - **CJK text** (`每100公克`, `蛋白質`): an exact substring whose neighbours on both sides are a line edge, whitespace, punctuation, a value token, or a character that is not CJK.
4. **Headers:** the model's amount headers, each located as a single whole-word occurrence in the whole text. A model header not located, or located more than once, puts every value in its column under attention. A located header whose span lies inside a row block puts that block under attention. A header whose vocabulary verdict is not `agrees` never removes value tokens from the cells, so a fake or unknown header cannot hide a cell.
5. **Row labels:** located as unique whole words, longest match first, so `saturated fat` is taken before `fat` and `飽和脂肪` before `脂肪`. A label left ambiguous puts that row's values under attention. Before the model's labels are located, every occurrence of a longer vocabulary label is claimed (matched case-insensitively), so a short label such as `fat` never matches inside `Saturated fat` when the model omitted that row. Model rows with the same printed label share one location.
6. **Row blocks:** a row's block runs from its label to the next located row label. The last block ends at the first blank line after a value token in that block, or at the end of the text. This covers one value per line as well as one row per line.
7. **Columns:** "headers" here means the model's amount headers that were located (item 4). A kJ and kcal pair counts as one cell (item 8).
   1. `%` tokens and the reference-intake header are set aside first. Each `%` token matches the reference-intake column.
   2. When the remaining cells equal the remaining headers in number, they match in printed order.
   3. When there are fewer cells, the block is **always attention**.
   4. When there are more, the block is attention.
8. **Energy pairs:** a pair is a kJ token and a kcal token next to each other, separated only by boundaries. It is one cell holding two values, stored as kJ then kcal whichever order is printed (kcal-first included). On one row per line, `1046kJ/250kcal 523kJ/125kcal` is two pairs, so two cells. A swap the vocabulary cannot see is left to `kj_kcal_ratio` in `label-arithmetic-checks-v2`.
9. **Repeats:** equal values in one block (`0g 0g`) are matched by ordinal.
10. **Result:** exactly one match is found. Zero or several matches is an attention item.
11. **Not-declared markers** (v3, revision 14, D30): a dash (`-`, `–`, `—`), `Trace` or `Tr` in any letter case, standing alone between token boundaries in a block, is a printed column position, never a value token. A dash or word followed on its line by a word that is not a marker (`- of which sugars`, `Trace elements`) is not one. Markers fill their printed positions among the columns: first, with one located reference-intake header, when every cell, marker and `%` token equals every located header in printed order and each sits under a header that can hold it; then as in item 7 when the cells alone equal the headers (the markers are then reference-intake candidates); then when cells and markers together equal the amount headers. A model value that is a marker is found only where the same marker text is printed at its row and column; a marker never matches a number, nor a number a marker. A block with no marker is located exactly as in v2.
12. **Star markers** (v4, revision 15, D32): a lone `*` standing alone between token boundaries in a block, with no trailing `*` or `†`, is a marker of the reference-intake column only. It may take a reference-intake position under item 11, never an amount position, and is never an amount candidate, so a lone `*` the model places under an amount header is never found. A `*` glued to a number (`7%*`, part of its token), to a heading (`RI*`) or followed by a word (`* Reference value not set`) is not one. A model value printed as `*` is matched as `*`. A block with no `*` is located exactly as in v3.

A vector is committed for each of these:
- one value per line;
- misaligned columns (fewer values than headers);
- more values than headers;
- a `%` column;
- a kJ and kcal cell;
- repeated values;
- substrings;
- recurring row labels;
- the last block;
- a `100g` header (D16);
- a decimal comma (`0,5g`) next to a boundary `,`;
- Taiwan comparators `少於` and `＜` with CJK units;
- CJK whole-word header and row-label location;
- `%` with too few other cells;
- a kJ and kcal cell counted as one cell;
- `5 g` and `less than 0.5 g` as one token each, and U+00A0 inside a token;
- two energy pairs on one line, and a kcal-first pair;
- a digit outside ASCII and full width, under the copy's rule and parity test 26;
- a last block followed by footer text with no blank line;
- not found and several matches;
- a marker in a product-amount column and in the %RI column, a list dash, a marker the text prints elsewhere or not at all, and a number where the text prints a marker (v3);
- a lone `*` in the %RI column, a lone `*` in a product-amount column, a `*` the text does not print there, `7%*`, `RI*`, `**` and a footnote line (v4).

### 4.4 Assignment check `pasted-label-ai-text-vocabulary-v2`

A closed, versioned vocabulary of row-label words (for example salt, sodium, sugars, of which saturates, and the Taiwan equivalents) and header words (per 100 g, per 100 ml, per serving, reference intake). When the model's nutrient or basis disagrees with the vocabulary entry for the located row label or header, that value is an attention item. A label or header the vocabulary does not know is attention too (`label_unknown`), and so is a header naming two bases. A reference-intake word decides the basis on its own. The check never assigns anything (D11).

From v2 (revision 15, D33), a header that joins a mass and a volume basis (`per 100g/ml`, `per 100 g/ml`, `100g/100ml`, `per 100g / 100ml`, `每100公克/毫升`) names two bases; v1 read `per 100g/ml` as per 100 g alone. Such a header does not establish the basis from the paste, so the reader declines the reply with the reason `vocabulary:two_basis_header`, whatever basis the model gave it, as it would a value column with no recognisable basis (D27). The check reads the header as the model returned it and, when the sent text goes on from it with a slash and the other unit (a model's `per 100g` printed as `per 100g/ml`), the whole printed heading cell. A reference-intake heading (`%RI per 100g/ml`) still decides its basis on its own and is not declined; every other header reads as under v1.

### 4.5 Manifest, versions and records

- **Distinct versions:**
  - route `pasted-label-ai-text-route-v1`;
  - manifest `pasted-label-ai-text-v1`;
  - mapping, locator, vocabulary and identity versions as above;
  - attention policy version recorded;
  - evidence kind `.labelText`, which the pasted route already uses. The capture method version and the `pasted-label-ai:` release-ID prefix separate the two, and contract test 4 covers relabelling in both directions;
  - `SourceRelease.schemaVersion` `<manifest>:<format>`;
  - an append-only list of admitted pipelines.

  No text-route version is added to the pinned `PastedLabelEvidenceManifest.versions`.
- **What the manifest stores:**
  - the sent text verbatim (at most 8,000 scalars);
  - the model, provider, endpoint and route;
  - the instruction and schema SHA;
  - the raw response, usage and cost;
  - the attention inputs (the gate-flagged nutrients, the failed checks and the serving lines), so the verifier replays attention from the stored inputs, as the photo manifest does;
  - every per-value state, location and user action.
- **Verification:** the verifier re-runs the locator, the unit check and the vocabulary check on the stored text, and the attention set from the stored attention inputs. It cannot re-run the gate or the arithmetic, which live outside the application layer. It requires identical results. This is stronger than the photo route, which cannot replay Vision.
- **Provenance:** unchanged values reuse `user_verified_panel` with release ID `pasted-label-ai:`. Corrected or entered values carry `manual_declaration`, and export gives `label_checked_by_you` and `entered_by_you`, with no new export key.
- **Identity:** UK candidates record `pasted-label-ai-text-identity-v1` (D9), which applies the UK as-sold rules of identity v3 and records them explicitly. Taiwan candidates record the existing Taiwan identity v1 facets, which confirmation already accepts.
- **Export:** the stored text is handled exactly as the pasted route handles its text today, with no new export key and no change to the Drive egress (D20).
- **Archive:** a new food contract number, chosen in A5 as the next unused one after reading `CanonicalFoodArchive`. Older readers decline it cleanly, and every existing record decodes, verifies and re-encodes unchanged. A5 also checks that photo evidence is covered by its contract, which the gate found unverified.
- **Admission:** `LabelSourceAdmission` becomes three-way (pasted, photo, text), and a candidate naming two sources is refused.
- **Manifest-keyed sites:** each gets a stated answer for text evidence, in a table in section 11:
  - `PastedLabelSource` (two sites);
  - `PastedLabelServingPolicy`;
  - `NutrientValueOrigin`;
  - `CanonicalFoodArchive`;
  - `ReviewedFoodProposalConfirmation`;
  - `LabelSourceAdmission`;
  - the `FoodConfirmation` save and reopen branches keyed on the photo source;
  - the `LabelEstimateConfirm` cocoa pre-fill, which returns pasted text only for the pasted source.

### 4.6 When Read with AI is offered

Only for a closed set of the frozen reader's decline codes, fixed in A1 from `LabelReading`'s codes:
- **layout declines** of a Taiwan table, from the closed set `PastedLabelAITextOffer.taiwanLayoutCodes` (offered only when every decline code is in it);
- **`layout_not_supported` for a UK-format paste.** Under the product scope, the reader declines every UK table with this code after its gate inferred the UK format, and that inferred format is how the paste is known to be UK. It is offered only when the decline codes are exactly `{layout_not_supported}`. Read with AI is never offered for:
- identity declines such as `basis_state_not_supported`;
- `text_too_long`;
- empty pastes and hash failures;
- G1 simplified Chinese (D15).

### 4.7 Formats

v1 admits UK-format declarations and the Taiwan pastes the reader declines (D2 as amended).

- **EU English panels** follow the same rules and cannot be told apart reliably, so they are read as UK-format declarations under the UK rules and the UK bar (D18). No tuning or held-out label is EU English, so their accuracy is measured only as far as they match UK panels. The A4 result and the release note say so.
- **US per 100, Australian and New Zealand panels** stay declined in v1 (D13). A closed, pure detector on the pasted text runs **before anything is sent**. It declines them on their distinct rows, for example sodium in mg with no salt row, or an Australian per-serve column with average quantity wording, so the text is never sent and no read is spent. The same detector, version `pasted-label-ai-text-panel-detector-v2` (v1 until revision 10), runs again on the model's candidate, as a second check. The `sodium_without_salt` rule looks for the word salt anywhere in the text, does not require mg, and is skipped when the text contains CJK script, so a bilingual Taiwan paste passes. From v2, the `nutrition_facts_title` rule is skipped when the text also prints the Taiwan mandatory title `營養標示` (a bilingual Taiwan paste prints `營養標示 Nutrition Facts`); Han script without that title still declines, and so does every other US rule.
- **Format step** `pasted-label-ai-text-format-v1` (revision 10): the frozen `pasted-label-format-inference-v1` runs unchanged, then a candidate it finds ambiguous because the model's language is `mixed` is a Taiwan panel when the sent text prints `營養標示`. `unknown`, and `mixed` without the title, stay `format_ambiguous`; gate v2 still runs every Taiwan rule, G1 included. The version is recorded with the reader's versions. Each detector rule gets a vector. The vector proving that no request is built for a detected panel comes in A5, with the orchestrator.

### 4.8 Flags and attention

Attention items block Log, as photo decision P12. On the text route these are attention items:
- not-found values;
- unit checks that fail;
- vocabulary mismatches;
- arithmetic implications;
- G3 and G4 flags on the affected nutrients.

G5 and G6, and G3 for a missing optional row, inform without blocking. A value that is found but whose position is uncertain maps to `ambiguous`, and the locator's block, header and label reasons map to `ambiguous` too. The attention version is recorded.

### 4.9 Prompt injection and privacy

- **The instruction** treats the pasted text as data only: no tools and a strict schema, with the response limits of photo E12.
- **The copy** asks the user to paste only the nutrition table.
- **Adversarial fixtures:**
  - injected instructions;
  - fabricated values that do occur in the text;
  - nutrient and basis reassignment;
  - two panels;
  - a truncated table;
  - a non-label paste.

  Each must end as a decline or an attention item, never a silent value.

## 5. Evaluation programme

### 5.1 Data

Every set below is real public label text with a blind, owner-verified transcription, held in `~/WHR-label-eval-private/` and never in git.

| Set | Labels | Role |
|---|---:|---|
| Taiwan reader v3 development set | 24 | Tuning |
| Taiwan reader v3 fresh set | 24 | Tuning (spent by its release check) |
| UK v1 development set | 24 | Tuning |
| UK v1 fresh set | 24 | Tuning (spent by the v1 probe) |
| UK v2 fresh set | 24 | **Held out (D4).** Sealed, run once by the frozen reader, not probed for decline causes |

- **Tuning:** about 96 labels. Prompt and model versions are compared on these as often as needed.
- **Held out:** the 24 UK v2 labels, run **once**, after the prompt, model and checks are frozen, against the bar in 5.3. Taiwan is not measured on untouched text in v1 (D4).
- **Independence:**
  - 15 of the held-out labels (tier B) share sites with the UK v1 tuning sets, so tier A (9 labels) is reported on its own as the independent figure;
  - **what is already known about the held-out set:**
    - the frozen reader's P4 counts, published in P4 section 2 (19 of 24 declined, reasons by tier, 0 wrong values in 87);
    - the coordinator saw one label's column heading and transcription notes while recording Amendment 6;
    - no prompt or rule in this programme has been run on, or tuned against, any held-out text.
  - **Rule:** prompt authors and harness operators never read the held-out texts, transcriptions or P4 per-label results until A4 is scored. The A4 result states this exposure beside the counts.
- **Synthetic adversarial texts** (committed, no real text) per 4.3 and 4.9. Every version must pass these before any real-text run.

One evaluation format replaces the per-programme schemas. A converter maps the Taiwan and UK transcription schemas into it, proven by round-trip tests on synthetic fixtures. The existing data is not edited.

### 5.2 Harness (amended 7 November 2026, D21 and D22)

**Framework: promptfoo (D21), run locally.** It runs the matrix of prompt versions by models, caches responses so that re-scoring never pays again, records cost and latency per call, and shows results in a local viewer. Scoring stays in the shipped Swift code (architecture gate finding M5), so promptfoo orchestrates and never decides a value.

1. **Sending, with spend enforced.** promptfoo calls a custom JavaScript provider (`file://`), which runs `PastedLabelAITextEval send` for each label. That Swift tool:
   - builds the request with the shipped text request builder, so the evaluated request is the product's (instruction and schema SHA, and the provider block with `only` and `order` pinned to one ZDR endpoint, `allow_fallbacks: false`, `data_collection: "deny"` and `zdr: true`, as T3 requires);
   - takes the prompt version as a closed parameter (revision 11): `prompt-v1` or `prompt-v2`, each instruction a bundled file pinned by SHA-256. The default is `prompt-v1`, so the app's composition root and every v1 golden are unchanged. Only the system message differs between versions; the schema, the provider block and the limits are the same. `send --prompt-version` selects it (default `prompt-v1`) and records it with the instruction's SHA-256; the instruction is in the body, so each version has its own cache key and its own W. `make-config.js` accepts `v1` and `v2`, and `provider.js` passes the cell's version to `send` and refuses a record sent under another. `prompt-v2` keeps every `prompt-v1` rule and adds four, from the UK tuning v1 results:
     - a per-serving column header that states the serving (`Per slice (40g)`, `per 30g serving`) is copied exactly as the serving size when no serving size line is printed, and a serving printed only as a count (`Per 3 nuggets`) is copied as text. The mapping already takes the same quantity from such a header, and the serving line is still located in the text; nothing is computed;
     - a column of adult reference intake amounts (`RI*`, `Reference Intake`, `your RI*`) is `reference_intake`, like a %RI column. The mapping never reads its absolute values as product amounts;
     - a cell printed as `-` or `–` is copied as printed, never as 0. The mapping reads it as a not-read cell, as it reads `unknown`, so the table is not marked ready;
     - each value is given once, with no commentary, so a four-column table fits the output limit.

     A two-basis header (`per 100g/ml`) keeps the `prompt-v1` rule. Under vocabulary v1 it read as per 100 g alone and raised no attention item for a per 100 g basis; from vocabulary v2 (D33) the reader declines it whatever the model returns, so neither prompt's text changes;
   - before every call, reserves the call's worst-case cost W in the text evaluation's own spend ledger, `pasted-label-ai-text-spend-ledger-v1` (T5, D26). It is a separate file from the photo evaluation's `label-capture-spend-ledger-v1`, and each tool refuses the other's schema. W is bounded from the actual request: the instruction and schema tokens plus the sent text's UTF-8 byte count as an upper bound on its tokens. A text whose bound passes the ceiling is refused. After any settle above W or above the ceiling, the cell stops; and refuses to send when the reservation would pass the $5 cell stop or the $25 programme stop;
   - sends through the shipped OpenRouter transport to `https://openrouter.ai/api/v1/chat/completions` (T1), with the key from the environment only (T4);
   - settles the reservation to the reported cost. A call with no reported cost stays recorded in the ledger as **unknown cost**, charged at W towards the stops, so the ledger's stop on unknown-cost calls (three) still applies. As in the photo evaluation (owner, 17 October 2026), an attempt that ended in an error and returned no generation (a transport failure, or an HTTP error with no `id` and no `usage`) is still charged at W but does not count towards that stop; an HTTP 200 answer without a cost does. A transient failure (transport, 429 or 5xx) is retried within one tap, at most three attempts in all, with backoff that honours `Retry-After` and a fresh reservation of W for every attempt (A3). The file records `charged_usd`, the total the stops see, beside the reported costs;
   - returns the raw response, token usage, cost and latency to promptfoo.

     Two further candidates, `gemini-3.8-flash-vertex-us-4k` and `gpt-6-luna-azure-4k`, are the same endpoints with a 4,000-token output cap (owner, 8 November 2026), because four-column UK tables ran out of output at 2,400 under `prompt-v2`. They are appended, so the set stays append-only and the 2,400-token cells stay comparable; W is bounded from the larger cap.

   A refused call counts as failed, and the stop ends the cell. promptfoo's HTTP and OpenRouter providers are not used: the first would send outside the spend ledger, and the second documents no way to pass the provider routing block. The product's shared daily cap (D14) applies to the app, not to evaluation runs, which T5 governs.
2. **Scoring.** The scorer is `pasted-label-ai-text-scorer-v5` (v1 until revision 12, v3 in revision 12, v4 in revision 13, v5 in revision 15; there is no v2, so that its name never reads as `uk-fresh-scorer-v2`), which applies the comparison rules of `uk-fresh-scorer-v2` (and the Taiwan fresh-set rules) and is tested for parity with them on shared synthetic vectors. From v3, values in reference-intake amount columns are not printed fields (5.2.1, D28), and from v4 neither are values on rows the transcription records as `other`, which the app keeps as unrecognised (D29). From v5 (D31), when the transcription has two or more reference-intake columns that are percentage columns under R1, the app's reference-intake headers that hold percentages are paired with them in printed order, as product-amount columns are paired by position: a cell is correct only in its paired column, and unequal counts stay ambiguous (wrong); one percentage column is read as in v4. From v5 (D32), a transcribed lone `*` is a class marker for R1, so a %RI column with some `*` cells stays a percentage column and its values are printed fields, and it matches only a shown `*`. A `file://` JavaScript assertion passes each raw response to `PastedLabelAITextEval score`, which runs the shipped steps in product order:
   - the text mapping;
   - **decline gate v2** (with `.uk` for UK candidates), the conversions and the arithmetic checks;
   - the panel detector;
   - the locator, unit and vocabulary checks;
   - attention;
   - scorer v5, with the comparison rules of `uk-fresh-scorer-v2`, against the label's transcription. From mapping v3 (D30) the harness's Confirm table also carries each not-declared marker as printed (`=`, no unit), which the scorer's comparison matches only against a transcribed class marker; from mapping v4 (D32) that includes a lone `*` under a reference-intake header, which matches only a transcribed lone `*`.

   A table counts as reaching Confirm only when the product would show it. Only a **hard decline** counts as declined (D19): gate G1 or G2, a detector decline, a header naming two bases (`vocabulary:two_basis_header`, D33), or a mapping that leaves no usable table. Gate findings G3 to G6 travel to Confirm as flags or attention items, exactly as in the product. The assertion returns `pass`, `score` and `namedScores` for every per-label count in 5.2.1, and the response's model and provider must match the pinned route, or the label counts as failed (T3).
3. **Caching.** `PastedLabelAITextEval send` keeps its own response cache in the private folder, keyed by the SHA-256 of the request body, so re-scoring a cell reuses its responses and never pays again. Only an HTTP 200 reply that passes the envelope check is cached, so a transient failure is never made permanent. promptfoo's cache is not relied on, because it is not documented for custom providers. A cached response keeps its original recorded cost, and is not charged again in the ledger.
4. **Statistics.** A small script of our own reads promptfoo's exported results and computes the metrics and tests in 5.2.1. promptfoo's own pass rates are not used as results.
5. **Local only:**
   - telemetry, update checks and sharing are switched off by environment variable, checked against promptfoo's current documentation in A2;
   - its cache, database and exports are kept in the private folder, never in the repo or the home directory default;
   - promptfoo is pinned to an exact version, chosen in A2 and at least two weeks old;
   - A3's developer-tooling note in `privacy-and-egress.md` names it as local tooling that adds no destination.
6. **Runs.** Each run records the prompt version, model, endpoint, the text's hash and the raw response, privately. The repo gets counts only. Spend stops are $5 per cell and $25 for the programme (T5). The scorer, converter, statistics script, promptfoo version and frozen route are pinned by SHA before A4.

### 5.2.1 Metrics (standard, D22)

Each metric is computed per cell on the tuning set, and once on the held-out set. Every metric comes with a 95% interval, chosen by what it is:
- **Label-level proportions** (exact match, no edit, coverage, failed reads, silent-error tables): Wilson, or Clopper-Pearson (exact) when the count is 0 or equals the total.
- **Field-level metrics** (precision, recall and F1, micro and macro), error-detection precision and recall, and attention items per table: a percentile bootstrap that resamples **labels**, 10,000 times. Fields within one label are not independent, so no binomial interval is used for them.

- **Field level** (key information extraction, as in the SROIE and CORD benchmarks):
  - A field is one printed value: one nutrient under one basis.
  - A value in a reference-intake amount column is not a field (scorer v3, D28). Such a column is a reference-intake column that is not a percentage column under R1 (at least one `%` value and, apart from class markers, nothing else); a column holding both percentages and amounts is left out whole. Its values, class markers included, are counted per label as `fields_reference_amounts`, so printed fields plus that count is every transcribed value. Every value shown at Confirm is still scored, and one in a reference-intake column that the transcription records as amounts stays wrong.
  - A value on a row the transcription records as nutrient `other` (outside a reference-intake amount column) is not a field either (scorer v4, D29): the app keeps such a row as unrecognised and never logs it. Every cell shown at Confirm, an unrecognised cell included, is still scored, and the count is reported per label as `fields_unrecognised_rows`.
  - A lone `*` in a %RI column is a class marker for R1 (scorer v5, D32), so such a column is a percentage column and its values, the `*` cells included, are printed fields; under v3 and v4 it was a reference-intake amount column.
  - It is correct only on an exact match with the transcription after unit normalisation, under the comparison rules of `uk-fresh-scorer-v2` (scorer v3).
  - **Precision** is correct fields over fields shown at Confirm. **Recall** is correct fields over printed fields. **F1** combines the two. All three are reported micro (pooled over values) and macro (averaged per label).
  - **Macro averages:** macro precision averages over the labels that reach Confirm, and the count of labels excluded is reported beside it. Macro recall and F1 average over all labels. A failed or declined label scores 0 on both, since none of its printed fields was read.
- **Document level:**
  - **exact match:** every field of the table correct, and nothing missing;
  - **no edit,** as defined in 5.3.
- **Selective prediction:**
  - **coverage:** tables reaching Confirm over labels;
  - **risk:** tables with any wrong value over tables reaching Confirm.
- **Error detection** (attention items as a classifier of wrong values):
  - **recall:** wrong values with an attention item over wrong values. A silent error is a miss;
  - **precision:** attention items on wrong values over all attention items. The rest are false alarms, and they are the burden on the user;
  - attention items per table.
- **Operational:** failed and declined reads, plus cost and latency at p50 and p90.
- **Breakdowns:** by nutrient, by layout shape (one row per line, one value per line, misaligned, unitless), by tier and by copy method.
- **Comparing versions** (tuning set only):
  - prompt and model versions are compared on the same labels;
  - a **McNemar test** for table-level exact match, and one for no edit;
  - a **paired bootstrap** (10,000 resamples over labels, with the seed recorded in each run) for field F1;
  - the number of versions compared is reported with the winner, and no held-out label informs the choice.
- **Ground-truth reliability:** for a sample of at least 12 tuning labels, a second independent blind transcription. Field-level exact agreement is reported. A disagreement is resolved against the source before scoring, and the rate is published.
- **The 5.3 bar** is unchanged and still gates release. It is reported beside these metrics. The held-out set is small: zero silent errors in 24 tables still allows a true rate of up to about 14% (two-sided 95%), and the result states this.

### 5.3 Bar for the held-out run (accepted by the owner, 7 November 2026, D5 and D12)

**Definitions:**
- A **wrong value** is a value at Confirm that differs from the transcription under scorer v2. Here scorer v2 means the comparison rules of `uk-fresh-scorer-v2`, which `pasted-label-ai-text-scorer-v3` applies unchanged (D28); bar 2 is read under v3.
- A **silent-error table** has a wrong value that carries no attention item.
- A printed row the model omits is a **not-read row**. It is shown as missing, never as zero, and is not a wrong value. It does make the table need an edit.
- **No edit** means no correction and no entry. "Matches the text" taps on attention items are allowed and counted.
- **Outcome:** each held-out label ends as exactly one of reached Confirm, failed or declined, and the three add up to 24. A gate or detector decline after a valid model reply counts as declined (D19).
- **Cost** is per tap, including retries, and is the reported cost. An unknown cost is counted at the per-tap cap. It is measured over all 24 taps.
- **Latency** is per tap, from the tap to Confirm or failure, including retries, over all 24 taps. p90 is the nearest-rank 90th percentile (the 22nd of 24 sorted values).
- **Copy method** is the copy method recorded in each label's collection record (scripted range, owner's Preview selection, and so on).

**Bar:**
1. **Zero silent-error tables.** The locator, the unit check and the vocabulary check together make this reachable.
2. **Tables needing no edit:** at least 80% of the tables that reach Confirm.
3. **AI reads that fail or decline:** at most 25% of all 24 held-out labels, since the shipped reader declines every UK paste (D12). That is at most 6.
4. **Median cost** at most $0.01 per tap, as the upper median (the 13th of 24 sorted costs, D23); **p90 latency** at most 15 s.

**Reported, not gating:**
- wrong values that were flagged;
- attention items per table;
- the results by tier (tier A on its own) and by copy method;
- rule-of-three upper limits with the real counts, as in P4.

A miss stops release. The held-out set is then spent and becomes tuning data.

### 5.4 Models

Only ZDR endpoints with data collection denied and no fallbacks, confirmed from OpenRouter's catalogue on the day.

- **Start:** the models the photo evaluation measured, Gemini 4 Argon and GPT-6.1 Sol.
- **Also:** cheaper text-only models listed with ZDR on the day.
- Every candidate is named with its endpoint in the run record. The shipped route pins exactly one, as on the photo route (E6).

## 6. Images later

Once the text route passes, the photo route widens beyond Taiwan with the same method:

- a photo evaluation set built from the same labels where photos exist;
- the frozen text-route prompt as the starting point;
- the photo route's own locator and bar.

That is a separate spec.

## 7. Egress terms (for approval; nothing sent before)

Two separate approvals: the evaluation runs (T1 to T7), then the product route (T8 to T12), each line by line.

**Evaluation runs (approved by the owner, "Approve all", 7 November 2026, D6):**
- [x] **T1 Destination.** `https://openrouter.ai/api/v1/chat/completions` and the keyless catalogue listings only.
- [x] **T2 Payload.** One label's pasted text exactly as saved, the fixed instruction and the fixed schema. No name, owner data, health data or identifiers. The texts are public pages' nutrition sections.
- [x] **T3 Routing.** ZDR endpoints only, `data_collection: "deny"`, `allow_fallbacks: false`, one endpoint pinned per cell. The response's model and provider must match the request.
- [x] **T4 Key.** The OpenRouter key already approved for the photo evaluation, loaded into the environment only and never printed.
- [x] **T5 Spend.** A stop of $5 per matrix cell and $25 for the programme, recorded in the existing spend ledger. A fresh text evaluation ledger caps a single call at $0.20 (D25). *Amended 8 November 2026 (D26): recorded in the text evaluation's own spend ledger rather than the photo ledger; the stops are unchanged.*
- [x] **T6 Records.** Raw responses stay in the private folder. The repo gets counts, versions and hashes of committed synthetic fixtures only.
- [x] **T7 Held-out run.** One run, by the frozen version, after the bar is committed.

**Product route:**
- [ ] **T8 When.** Only on the explicit Read with AI tap after a decline, with the egress statement and a first-use sheet. No background, prefetch or automatic re-read.
- [ ] **T9 Payload.** The pasted text as pasted, after the app's existing normalisation, at most 8,000 Unicode scalars, with the fixed instruction and schema. Nothing else.
- [ ] **T10 Routing and key.** As photo E5, E7 and E8, with the one pinned text route.
- [ ] **T11 Caps.** One day record shared with the photo route (D14): at most 30 reads and $0.50 a day across both, with each route keeping its own per-read cap. The text route's worst-case cost W and prompt-token ceiling are sized for 8,000 scalars of Traditional Chinese, from the evaluation's measured costs. An over-ceiling text read pauses only the text route for the day (D17). The photo row in `privacy-and-egress.md` and E10's wording are amended in the same PR.
- [ ] **T12 Records.** A `privacy-and-egress.md` row and the privacy policy text take effect in the PR that wires the live text route.

## 8. Phasing (one PR per phase)

| Phase | Content | Egress |
|---|---|---|
| A0 | This spec, the owner decisions, the architecture gate | None |
| A1 | The evaluation format and converters; the closed lists, text locator, unit check, vocabulary, panel detector, offer rule and attention reasons as pure code; synthetic vectors and adversarial fixtures against those checks; and the bar committed and pinned by SHA in `Tools/PastedLabelAITextEval/bar-v1.json`. Done in the A1 PR | None |
| A2 | The harness: `PastedLabelAITextEval` (request builder and scorer CLI), the promptfoo configuration with its custom `file://` provider and assertion, the spend reservation and the response cache, the statistics script, and promptfoo pinned with telemetry, updates and sharing off. All run over a fake transport, with scorer parity on synthetic runs | None |
| A3 | Tuning runs: the matrix, results as counts, and prompt and model frozen. Before the first run, a developer-tooling note for these runs is added to `privacy-and-egress.md` | T1 to T6 |
| A4 | The held-out run and its result | T7 |
| A5 | The identity contract (D9) and its goldens, the archive contract number (4.5), the 11.4 site table with line numbers, the photo-evidence contract check (4.5), the full attention composition and the "no request for a detected panel" vector (4.7), all moved from A1 because they need the manifest. Then the product route behind a launch argument: Read with AI, Confirm with the text pane, manifest and admission | None until T8 to T12 |
| A6 | Device check by the owner, the records in force, and the route turned on | As approved |

## 9. Decisions for the owner (asked one at a time)

| ID | Question | Recommendation |
|---|---|---|
| D1 | Should Read with AI appear only after the frozen reader declines, never in place of a successful read? | Yes, as decided ("AI for the rest") |
| D2 | Which panels does the text route admit? | **Decided (owner, 7 November 2026), amended by D13:** UK declarations plus Taiwan pastes the reader declines; everything else declines |
| D3 | Is the text locator allowed, given parsing is parked? | **Decided (owner, 7 November 2026): allowed.** It checks the model's answer and never produces a value |
| D4 | Held-out data: the UK v2 fresh set only, or also a new Taiwan fresh set? | **Decided (owner, 7 November 2026): the UK v2 fresh set only.** A Taiwan fresh set only if Taiwan declines turn out to matter |
| D5 | The held-out bar in 5.3 | **Decided (owner, 7 November 2026): as proposed.** Committed in A1, before any tuning run |
| D6 | The evaluation egress terms T1 to T7 | **Decided (owner, 7 November 2026): approved as written.** The product route's T8 to T12 come separately |
| D7 | A GitHub issue for this programme, with one PR per phase | **Decided (owner, 7 November 2026): yes,** #416 |
| D8 | UK product scope: re-pin `PastedLabelLaunchScope.swift`, or give the text route its own scope? | **Decided (owner, 7 November 2026): the text route owns its scope in new files, with no re-pin.** The frozen reader, its policy members and every pin stay unchanged |
| D9 | UK identity: record identity v1 facets with a v3 as-sold check, or a new recorded identity? | **Decided (owner, 7 November 2026): a new versioned identity contract owned by the text route.** Each manifest records the UK as-sold rules explicitly, with goldens and round-trip tests, written in A1 |
| D10 | Values printed without units | **Decided (owner, 7 November 2026): the model returns the unit, and the app accepts it only when that unit token appears in the same row's label or the column's header in the pasted text; otherwise it is an attention item.** A versioned text-route mapping, which verifies and never produces a value |
| D11 | Check the model's nutrient and basis assignments? | **Decided (owner, 7 November 2026): yes.** A closed, versioned vocabulary of row-label and header words (English and Taiwan) checks each assignment, and any mismatch is an attention item. It never assigns anything itself |
| D12 | Bar 3's denominator | **Decided (owner, 7 November 2026): all 24 held-out labels,** since the shipped reader declines every UK paste. At most 6 of 24 may fail or decline |
| D13 | Other English panels (US per 100, Australian, New Zealand, EU English), which no evaluation label measures | **Decided (owner, 7 November 2026): declined in v1, amending D2; amended by D18 for EU English.** v1 admits UK-format declarations (EU English included) and Taiwan declines. The others are added later, with their own labels in the tuning and held-out sets |
| D14 | Daily spend across the text and photo routes | **Decided (owner, 7 November 2026): one shared cap.** One day record counts both routes, at most 30 reads and $0.50 a day in total, and each route keeps its own per-read cap. The photo row in `privacy-and-egress.md` and E10's wording are amended in the same PR |
| D15 | Offer Read with AI after identity declines? | **Decided (owner, 7 November 2026): no.** It is offered only for a closed set of layout and format decline codes. Identity declines, `text_too_long`, empty pastes and hash failures keep today's message |
| D16 | Does a header's basis quantity (`per 100 g`) state a unit? | **Decided (owner, 7 November 2026): no.** Only a unit stated for the values counts |
| D17 | What pauses when a text read goes over its token ceiling? | **Decided (owner, 7 November 2026): the text route only.** Photo reads continue under the shared cap |
| D18 | EU English panels | **Decided (owner, 7 November 2026): read as UK-format declarations,** under the UK rules and bar. US per 100, Australian and New Zealand panels decline after the model on a detector |
| D19 | Does a gate decline after a valid model reply count against bar 3? | **Decided (owner, 7 November 2026): yes.** Every held-out label ends as exactly one of reached Confirm, failed or declined |
| D20 | Is the stored text in the Drive export and archives? | **Decided (owner, 7 November 2026): as the pasted route does today,** with no new export key |
| D21 | Evaluation framework | **Decided (owner, 7 November 2026): promptfoo, run locally,** driving the shipped Swift request builder and scorer (5.2). Ragas and other LLM-judge tools were rejected, because the labels have exact ground truth. Hosted platforms were rejected because they would be a new egress destination |
| D22 | Metrics | **Decided (owner, 7 November 2026): standard metrics** (5.2.1), each with a 95% interval: field precision, recall and F1, exact match, coverage and risk, error-detection precision and recall, paired tests between versions, and ground-truth agreement |
| D23 | The median for bar 4 over an even count | **Decided (owner, 7 November 2026): the upper median,** the 13th of 24 sorted costs, which is the stricter reading and always an observed cost |
| D24 | promptfoo's transitive `npm audit` findings (5 high and 3 moderate, all denial-of-service class: `basic-ftp`, `glob`, `minimatch`, `@modelcontextprotocol/server-filesystem`) | **Decided (owner, 7 November 2026): accepted risk** for local developer tooling that runs synthetic or private evaluation data over a fake transport, or over OpenRouter under T1 to T7. None of the affected FTP, PAC or MCP filesystem paths is used. They are reviewed again whenever the pin moves |
| D25 | The evaluation ledger's per-call cap | **Decided (owner, 7 November 2026): $0.20 per call** for a fresh text evaluation ledger, because W is now bounded from the request. The $5 cell and $25 programme stops (T5) are unchanged. An existing ledger keeps its own value |
| D26 | Where the text evaluation records spend | **Decided (owner, 8 November 2026, accepting the recommended fix for the #426 Qodo findings): its own ledger file,** `pasted-label-ai-text-spend-ledger-v1`. Sharing the photo ledger left two readers with different rules: the photo tool sees an unknown text cost as no amount, and refuses a fresh text ledger's limits. Each tool now refuses the other's schema. The $5 cell, $25 programme, $0.20 per-call and three unknown-cost stops are unchanged |
| D27 | A value column with no printed basis header | **Decided (owner, 8 November 2026): the reply is declined.** The app cannot know whether the values are per serving, per 100 g or per 100 ml, and asking the user to choose would add a new decision at Confirm. A3 tuning records such labels as expected declines; they still count against bar 3 on the held-out set | Prompt-v1 rule unchanged; no contract change |
| D28 | Reference-intake amount columns in the scorer | **Decided (owner, 8 November 2026): `pasted-label-ai-text-scorer-v3`.** A value in a reference-intake column that is not a percentage column under R1 (at least one `%` value and, apart from class markers, nothing else) is not a printed field: the mapping never reads an absolute reference amount (`absolute_reference_value`) and the ledger never stores one, so the user never enters it. %RI values, every product amount, the comparison rules of `uk-fresh-scorer-v2` (R1 to R3) and silent-error scoring are unchanged; every cell shown at Confirm is still scored, and a cell in an RI column that the key prints as an amount stays wrong. The excluded count is recorded per label as `fields_reference_amounts`. Decided before any held-out text was read; the bar in 5.3 and `bar-v1.json` are unchanged and bar 2 is read under v3. Every A3 cell is re-scored under v3 from cached responses before the A3 record is written |
| D29 | Unrecognised rows in the scorer | **Decided (owner, 8 November 2026): `pasted-label-ai-text-scorer-v4`.** A value on a row the transcription records as nutrient `other` (a printed row outside the app's nutrients, such as a vitamin) is not a printed field, on the same principle as D28: the app keeps the row as unrecognised and never logs it, so the user never enters it. A value in a reference-intake amount column is counted under D28 first. The comparison rules, every cell shown at Confirm and silent-error scoring are unchanged; the count is recorded per label as `fields_unrecognised_rows`. Decided before any held-out text was read; the bar and `bar-v1.json` are unchanged, and every A3 cell is re-scored under v4 from cached responses |
| D30 | Printed dashes and `Trace` in the text route | **Decided (owner, 8 November 2026): read as not declared.** A cell the label prints as a dash (`-`, `–`, `—`), `Trace` or `Tr` (any letter case) is `not_declared` (`pasted-label-ai-text-mapping-v3`, `pasted-label-text-locate-v3`): shown as printed, never zero, never logged as a number, and needing no entry, so on its own it no longer keeps a table from being ready. It is accepted only where the locator finds the same marker at that row and column with no attention item; a dash the model claims and the text does not print there stays a not-read value. Markers fill their printed column positions, so a dash no longer puts its row's other values under attention. No persisted record, archive, export or pinned file changes. `pasted-label-ai-text-scorer-v4` is unchanged: it already compares a transcribed class marker only with a shown marker, so a marker against the key's marker is correct and a marker against a number, or a number against a marker, stays wrong; the harness's Confirm table now carries the shown markers. Decided before any held-out text was read; the bar and `bar-v1.json` are unchanged, and every A3 cell is re-scored from cached responses |
| D31 | Two or more %RI columns in the scorer | **Decided (owner, 8 November 2026): `pasted-label-ai-text-scorer-v5`.** R1 picks "the" percentage column, so with two percentage reference-intake columns in the key every %RI cell was ambiguous and wrong (tuning label ukv1fresh-F18). When the key has two or more reference-intake columns that are percentage columns under R1, the app's reference-intake headers that hold percentages are paired with them in printed order (left to right), as the scorer already pairs product-amount columns by position; a cell is correct only in its paired column, and unequal counts stay ambiguous (wrong). One percentage column is read exactly as in v4. The other comparison rules, the printed-field exclusions and silent-error scoring are unchanged. Decided before any held-out text was read; the bar and `bar-v1.json` are unchanged, and every A3 cell is re-scored from cached responses |
| D32 | A lone `*` in a %RI column | **Decided (owner, 8 November 2026): a class marker read as not declared.** A cell printed as a lone `*` in a reference-intake percentage column is `not_declared` (`pasted-label-ai-text-mapping-v4`, `pasted-label-text-locate-v4`), exactly as a D30 dash: shown as printed, never zero, never a stored value and needing no entry, accepted only where the locator finds that same `*` at that row and column with no attention item. A `*` attached to a number (`7%*`) or to a heading is a footnote and unchanged; a lone `*` in a product-amount column stays unreadable. In `pasted-label-ai-text-scorer-v5` a transcribed lone `*` is a class marker for R1, so a %RI column with some `*` cells stays a percentage column (tuning label tw3fresh-F04), and it matches only a shown `*`. No persisted record, archive, export or pinned file changes. Decided before any held-out text was read; the bar and `bar-v1.json` are unchanged |
| D33 | Headers naming two bases | **Decided (owner, 8 November 2026): the reply is declined.** A column heading that names both a mass and a volume basis (`per 100g/ml`, `per 100 g/ml`, `100g/100ml`, `per 100g / 100ml`) does not establish the basis from the paste. `pasted-label-ai-text-vocabulary-v2` recognises such a heading as naming two bases, and the reader declines the reply with the reason `vocabulary:two_basis_header`, whatever basis the model gave it, the same treatment as D27; a reference-intake heading still decides its basis on its own. Prompt v1 and v2 text is unchanged. Tuning labels ukv1dev-U02 and ukv1dev-U18 are expected declines under D27 and D33, and still count against bar 3 on the held-out set. Decided before any held-out text was read; the bar and `bar-v1.json` are unchanged |

## 10. Not changing

- the frozen Taiwan reader, its pins and every manifest it writes;
- the photo route's Taiwan scope;
- the shared Confirm rules;
- the egress list, until T8 to T12 are approved and wired.

## 11. Architecture gate

The gate returned **FAIL** on revision 1, **PASS WITH CHANGES** on revision 2 and on revision 3 (7 November 2026; each handover is on #416). Revision 4 applies the revision 3 changes R1 to R6. This section holds what the gate needs before any A1 code.

### 11.1 Responsibilities and dependency direction

- **Domain:** unchanged.
- **Application** (`FoodLedgerApplication`, imports only `Foundation`, `CryptoKit` and `FoodLedgerDomain`, as `check_imports` already enforces):
  - the checks that read the text: the locator, the unit check, the vocabulary check, the pre-send panel detector and the text attention version. All are pure Foundation, so the verifier can replay them;
  - the closed comparator and unit lists those checks use. The adapter target's copy of `parseValue` imports them from here, so there is one list and no application-to-adapter edge;
  - the scope and identity types;
  - the manifest codec, source, verifier and three-way admission;
  - the per-route spend policy over the shared day record;
  - two ports and the orchestrator:
    - `PastedLabelAITextAttempting`, which takes text and returns raw response bytes;
    - `PastedLabelAITextReading`, which takes text and raw bytes and returns a candidate with its attention inputs.

    Application tests use fakes that share the contract suite with the real adapters.
- **New adapter target `FoodLabelTextAIReading`:**
  - the text wire schema decoder;
  - the text mapping, with its own copy of `parseValue`, calling the frozen gate, conversions and checks;
  - the implementation of `PastedLabelAITextReading`;
  - the text reader adapter (Taiwan or `.uk`), which calls the application's panel detector on the candidate.

  It may import `Foundation`, `FoodLedgerDomain`, `FoodLedgerApplication` and `NutritionLabelParsing`, and nothing else. It does not import `FoodLabelPhotoReading`. Mapping parity with v1 is shown by a test target, `FoodLabelTextAIReadingTests`, that imports both.
- **The envelope check** (the T3 model and provider match, `finish_reason`, size caps and usage) is pure and lives in `FoodLedgerApplication`, so the orchestrator applies it. Infrastructure returns raw bytes only.
- **Infrastructure:**
  - the text request builder, the text route checker and the implementation of `PastedLabelAITextAttempting`, in `FoodLabelPhotoCapture` beside the existing OpenRouter transport. That adapter returns raw bytes only and never decodes the text wire, so no edge from `FoodLabelPhotoCapture` to `FoodLabelTextAIReading` appears.

  Concrete adapters are wired only at the composition root.
- **Presentation:** Read with AI on the decline state, the reading state, and the text pane and highlights on the shared Confirm.
- **Boundaries:** these edits to `check-boundaries.sh`, each with a negative self-test fixture:
  - a new rule, `check_imports FoodLabelTextAIReading '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'`;
  - `FoodLabelTextAIReading` and `FoodLabelTextAIReadingTests` added to the `NutritionLabelParsing` file and package allow-lists;
  - only `FoodLabelTextAIReadingTests` added to the `FoodLabelPhotoReading` file and package allow-lists;
  - a rule that only `FoodLedgerCompositionRoot.swift` and `Tests/FoodLabelTextAIReadingTests/` may import `FoodLabelTextAIReading`;
  - `FoodLabelTextAIReading` added to the `for dep in` package loop, with the package allow-list `^(FoodLabelTextAIReadingTests)$`;
  - the pbxproj rule: the app may link `FoodLabelTextAIReading`, and still may not link `NutritionLabelParsing` directly (the existing rule).

  The negative fixtures:
  - the application or presentation layer importing `FoodLabelTextAIReading`;
  - the new target importing `FoodLabelPhotoReading`;
  - a non-test target reaching `FoodLabelPhotoReading` through the new target;
  - a package target depending on `FoodLabelTextAIReading`.

### 11.2 Invariants

- HealthKit untouched. No send without the explicit tap.
- Unknown is never zero, and omitted rows are not-read.
- Model output never authorises a value: the locator, the unit check and the vocabulary check verify, and the user confirms.
- No frozen file changes: `ReaderV3FreezeTests`, `UKReaderFreezeTests` and `LabelPhotoFreezeTests` pass with no re-pin (D8).
- Every stored record, archive and export decodes and re-encodes unchanged.

### 11.3 Extension axes

- new text routes (models) through a route version bump;
- new admitted formats through D13's later addition with their own data;
- new vocabulary entries through a vocabulary version.

Nothing else is open.

### 11.4 Manifest-keyed sites (line numbers filled in A5)

| Site | Answer for text evidence |
|---|---|
| `PastedLabelSource` (two sites) | Not a pasted manifest: refused, routed by admission |
| `PastedLabelServingPolicy` | The text route's own serving policy, with the same rules and a parity test |
| `NutrientValueOrigin` | `label_checked_by_you` and `entered_by_you` |
| `CanonicalFoodArchive` | The new contract number (4.5) |
| `ReviewedFoodProposalConfirmation` | `.labelText` evidence of the text manifest version only |
| `LabelSourceAdmission` | Three-way, mixed sources refused |
| `FoodConfirmation` save and reopen branches keyed on the photo source | The text route's own branch: the text pane on reopen, with its manifest verified |
| `LabelEstimateConfirm` cocoa pre-fill | Returns the stored text for the text source, as it does for pasted |

### 11.5 Contract tests (written first)

1. Locator vectors for every shape in 4.3, plus whole-token boundaries and scalar offsets, with byte-identical output on repeated runs.
2. Verifier replay of the locator and the vocabulary check. Tampered text, or an added, removed or moved location, is rejected at save and at reopen.
3. Manifest strict-codec goldens: canonical bytes, unknown or missing keys throw, versions distinct, stored text round-trips.
4. Three-way admission, including relabelled and mixed evidence.
5. Every manifest-keyed site in 11.4, and the export golden.
6. Archive goldens unchanged byte for byte. The new contract exports, an older reader declines it, and every existing record re-encodes unchanged.
7. The three freeze suites pass with no re-pin.
8. The UK path calls the gate with `.uk`, the conversions and the checks (a recording fake), and the identity contract's goldens.
9. Mapping parity with `label-photo-wire-mapping-v1` where a unit is printed, plus unit-check vectors.
10. Request golden: text only, an 8,000-scalar cap, instruction and schema SHA, the provider block as E5, and no key, name or brand in the body.
11. Shared spend across routes: unknown cost counted at the cap, and a corrupt ledger fails closed.
12. Decline eligibility: only the closed set in 4.6 offers Read with AI.
13. The adversarial fixtures in 4.9.
14. Boundary self-tests.
15. Converter round-trips. The scorer and converter are pinned by SHA before A4.
16. Text wire schema strict-codec goldens, including the `unit` member.
17. Text attention goldens, with every v1 reason mapped across unchanged.
18. Locator vectors for the token grammar, header location, the last block, more and fewer values than headers, the `%` column and a `100g` header.
19. Boundary self-tests for every new edge in 11.1.
20. Spend:
    - an over-ceiling text read pauses only the text route;
    - existing day records decode as photo-only;
    - a corrupt record fails closed.
21. The text route checker refuses photo routes, and the photo checker refuses text routes.
22. The `FoodConfirmation` and `LabelEstimateConfirm` sites in 11.4.
23. Relabelled `.labelText` evidence is refused in both directions.
24. The detector declines US per 100, Australian and New Zealand panels before any request is built, and again on the model's candidate. It reads an EU English panel as UK-format.
25. Verifier replay of the unit check and the attention set, rejecting tampered stored gate flags or failed checks.
26. Parity between the text target's copy of `parseValue` (with its unit table and comparators) and `LabelPhotoWireMapping.parseValue`.
27. The locator vectors added in 4.3 for revision 4.
28. Contract suites for both ports, shared by the fakes and the real adapters.
