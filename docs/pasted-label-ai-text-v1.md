# Pasted label AI reading v1: text first (#416)

Status: **draft spec, revision 5, 7 November 2026. Documents only; no production code and no egress yet.** The owner decided D2 to D20 on 7 November 2026 (section 9), including the evaluation egress terms T1 to T7. The product route's egress terms (T8 to T12) still need line-by-line approval before the route sends anything. The architecture gate returned FAIL on revision 1 and PASS WITH CHANGES on revision 2. Revision 3 applied N1 to N16, and its re-check returned PASS WITH CHANGES. Revision 4 applied R1 to R6 and was confirmed PASS WITH CHANGES, with five wording gaps that were not blocking. Revision 5 closes those gaps and the six findings from a local Qodo review. Revision 5 itself has not been re-gated. The A1 PR opens with a gate pass on its own diff.

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
| Mapping | `label-photo-wire-mapping-v1` takes units from row labels for energy only | `pasted-label-ai-text-mapping-v1`, in a new file with its own copy of `parseValue`. Its unit table and comparators are the closed lists in the application layer (11.1), because the photo copy is internal to a pinned file. Parity with the photo copy is tested, except for the thousands rule in 4.3. Otherwise as v1, except that the model's unit for a bare number is accepted only when the sent text states that unit for the values (D10), and otherwise is an attention item. A unit is stated for the values when it is:<br>- a unit-only token in the column's header, such as `(g)`, `g` or `mg`; or<br>- a unit-only token in the row's label, such as `Fat (g)`.<br>A number followed by a unit in a header (`per 100 g`, `100g`, `per 30 g serving`) is the basis quantity and never states a unit (D16). Parity with v1 on every v1 vector where a unit is printed |
| Attention | The `label-photo-attention-v1` reasons are a closed, pinned set | `pasted-label-ai-text-attention-v1` in a new file: composes v1 and adds the reasons `unit_not_stated`, `vocabulary_mismatch` and `label_unknown`, with goldens |
| Spend | `LabelPhotoSpendPolicy` has a fixed 6,000-token ceiling and per-tap limit, and an unversioned day record | A per-route spend policy over one versioned shared day record (D14). It replaces `LabelPhotoSpendPolicy`'s day record (not pinned), so the photo route's read and write paths change in the same PR and count against the shared record. An over-ceiling text read pauses only the text route (D17). Existing day records are read as photo-only, and a corrupt record fails closed |
| Route checker | `OpenRouterLabelRouteChecker` accepts photo routes only | A text route checker with a parity test against the photo checker's rules |
| Locator | The Vision locator needs an image | `pasted-label-text-locate-v1` (4.3) |
| Assignment check | None exists | `pasted-label-ai-text-vocabulary-v1` (4.4, D11) |
| Scope and identity | `.ukDevelopment` is a harness policy, and confirmation refuses any identity but v1 | A text-route scope type in a new file (D8), and a new recorded identity contract `pasted-label-ai-text-identity-v1` that writes the UK as-sold rules into each manifest (D9) |
| Manifest, source and verifier | Photo evidence requires `.packageImage`, JPEG, an image hash and route `"C"` | `PastedLabelAITextManifest`, `PastedLabelAITextSource` and its verifier (4.5) |

### 4.3 Text locator `pasted-label-text-locate-v1`

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
   - **Thousands separator:** a `,` followed by exactly three digits and then a non-digit is a thousands separator, so `1,046kJ` is 1046 and `0,5g` is 0.5. A token with both a thousands `,` and a decimal mark (`1,046.5`) is read the same way. The photo copy reads every `,` as a decimal mark, so parity excludes this rule, and a vector covers it.
   - **Token boundaries:** start or end of line, whitespace (U+00A0 and U+202F included) outside a token, or one of `( ) [ ] ; : /`, `|` and a boundary `,`. So `1g` never matches inside `11g` or `0.1g`.
   - Trailing `*` and `†` footnote marks are kept as printed and ignored for matching.
   - The model's printed text must equal one token exactly, after that normalisation. Nothing else is normalised.
3. **Whole words.**
   - **Definitions:**
     - *CJK* means Script=Han, Hiragana or Katakana;
     - *punctuation* means general category P*;
     - *whitespace* means White_Space.
   - **Latin script:** bounded by line edges, whitespace or punctuation.
   - **CJK text** (`每100公克`, `蛋白質`): an exact substring whose neighbours on both sides are a line edge, whitespace, punctuation, a value token, or a character that is not CJK.
4. **Headers:** the model's amount headers, each located as the unique line holding its printed text as whole words. A model header not located, or located more than once, puts every value in its column under attention.
5. **Row labels:** located as unique whole words, longest match first, so `saturated fat` is taken before `fat` and `飽和脂肪` before `脂肪`. A label left ambiguous puts that row's values under attention.
6. **Row blocks:** a row's block runs from its label to the next located row label. The last block ends at the first blank line after a value token in that block, or at the end of the text. This covers one value per line as well as one row per line.
7. **Columns:** "headers" here means the model's amount headers that were located (item 4). A kJ and kcal pair counts as one cell (item 8).
   1. `%` tokens and the reference-intake header are set aside first. Each `%` token matches the reference-intake column.
   2. When the remaining cells equal the remaining headers in number, they match in printed order.
   3. When there are fewer cells, the block is **always attention**.
   4. When there are more, the block is attention.
8. **Energy pairs:** a pair is a kJ token and a kcal token next to each other, separated only by boundaries. It is one cell holding two values, stored as kJ then kcal whichever order is printed (kcal-first included). On one row per line, `1046kJ/250kcal 523kJ/125kcal` is two pairs, so two cells. A swap the vocabulary cannot see is left to `kj_kcal_ratio` in `label-arithmetic-checks-v2`.
9. **Repeats:** equal values in one block (`0g 0g`) are matched by ordinal.
10. **Result:** exactly one match is found. Zero or several matches is an attention item.

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
- not found and several matches.

### 4.4 Assignment check `pasted-label-ai-text-vocabulary-v1`

A closed, versioned vocabulary of row-label words (for example salt, sodium, sugars, of which saturates, and the Taiwan equivalents) and header words (per 100 g, per 100 ml, per serving, reference intake). When the model's nutrient or basis disagrees with the vocabulary entry for the located row label or header, that value is an attention item. A label or header the vocabulary does not know is attention too. The check never assigns anything (D11).

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
- **Archive:** a new food contract number, chosen in A1 as the next unused one after reading `CanonicalFoodArchive`. Older readers decline it cleanly, and every existing record decodes, verifies and re-encodes unchanged. A1 also checks that photo evidence is covered by its contract, which the gate found unverified.
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
- **layout declines** of a Taiwan table;
- **`layout_not_supported` for a UK-format paste.** Under the product scope, the reader declines every UK table with this code after its gate inferred the UK format, and that inferred format is how the paste is known to be UK. Read with AI is never offered for:
- identity declines such as `basis_state_not_supported`;
- `text_too_long`;
- empty pastes and hash failures;
- G1 simplified Chinese (D15).

### 4.7 Formats

v1 admits UK-format declarations and the Taiwan pastes the reader declines (D2 as amended).

- **EU English panels** follow the same rules and cannot be told apart reliably, so they are read as UK-format declarations under the UK rules and the UK bar (D18). No tuning or held-out label is EU English, so their accuracy is measured only as far as they match UK panels. The A4 result and the release note say so.
- **US per 100, Australian and New Zealand panels** stay declined in v1 (D13). A closed, pure detector on the pasted text runs **before anything is sent**. It declines them on their distinct rows, for example sodium in mg with no salt row, or an Australian per-serve column with average quantity wording, so the text is never sent and no read is spent. The same detector runs again on the model's candidate, as a second check. Each detector rule gets a vector, including one that proves no request is built for a detected panel.

### 4.8 Flags and attention

Attention items block Log, as photo decision P12. On the text route these are attention items:
- not-found values;
- unit checks that fail;
- vocabulary mismatches;
- arithmetic implications;
- G3 and G4 flags on the affected nutrients.

G5 and G6, and G3 for a missing optional row, inform without blocking. The attention version is recorded.

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

### 5.2 Harness

- **Driven through the shipped Swift code:** the request builder, mapping, gate, locator, vocabulary check and attention, like `Tools/LabelPhotoE13`, not a Python lookalike. The photo evaluation's budget, consent and spend-ledger code is reused.
- **Output** in the release run format, so scorer v2's per-value rules decide wrong values. A text-route scorer adds the AI-specific counts.
- **Each run** records the prompt version, model, endpoint, the text's hash and the raw response, privately. The repo gets counts only.
- **A run matrix:** prompt versions by models. Each cell runs on all tuning labels, with spend stops of $5 per cell and $25 for the programme (T5).
- **Pinned before A4:** the scorer, the converter and the frozen version, by SHA.

**Metrics per cell:**
- tables reaching Confirm;
- wrong values;
- silent-error tables;
- no-edit tables;
- attention items per table;
- failed and declined reads;
- median and p90 cost and latency.

### 5.3 Bar for the held-out run (accepted by the owner, 7 November 2026, D5 and D12)

**Definitions:**
- A **wrong value** is a value at Confirm that differs from the transcription under scorer v2.
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
4. **Median cost** at most $0.01 per tap; **p90 latency** at most 15 s.

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
- [x] **T5 Spend.** A stop of $5 per matrix cell and $25 for the programme, recorded in the existing spend ledger.
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
| A1 | The evaluation format, converters, the text locator as pure code, synthetic adversarial fixtures, and the bar committed | None |
| A2 | The text harness over a fake transport; scorer parity on synthetic runs | None |
| A3 | Tuning runs: the matrix, results as counts, and prompt and model frozen. Before the first run, a developer-tooling note for these runs is added to `privacy-and-egress.md` | T1 to T6 |
| A4 | The held-out run and its result | T7 |
| A5 | The product route behind a launch argument: Read with AI, Confirm with the text pane, manifest and admission | None until T8 to T12 |
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

### 11.4 Manifest-keyed sites (filled in A1 with the code's line numbers)

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
