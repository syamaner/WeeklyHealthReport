# Pasted nutrition label, UK English v1 (plan, #371)

Status: **owner-approved, 2 November 2026; architecture gate PASS WITH CHANGES, 2 November 2026, applied in this revision.** The owner decided decisions 1 to 6 of section 8 as recommended, in session, on 2 November 2026. The owner decided decisions 7 to 11, which the gate revision added (section 8.2), the same day in session; decision 11 is deferred by that decision to P1's counts. This plan authorises no change to the launch scope before P5; product code starts only at P2, under its own gate pass.

It plans how UK English pasted label text can meet the release gate that [pasted nutrition label v1](pasted-nutrition-label-v1.md) set in decision 3 ("UK English ships only after at least 20 real public UK label texts read with zero wrong values"), using the method that shipped Taiwan under [reader v3](pasted-nutrition-label-reader-v3.md) and its [release check](pasted-nutrition-label-reader-v3-release-check.md). Section 9 maps each gate finding to where it is addressed.

## 0. Scope

In scope: **pasted or typed text** of a UK nutrition declaration (gate format `uk_nutrition_declaration`), read on device by the existing pasted route and ending on the shared Confirm screen.

Out of scope, unchanged by this plan:

- **US "Nutrition Facts"** keeps declining `layout_not_supported` where format inference names it US (v1 decision 4). A US panel that prints a per 100 column infers as UK; section 7 covers it.
- **Label photos.** [Label photo AI pre-fill v1](label-photo-ai-prefill-v1.md) keeps its own Taiwan-only scope (decision 6). P5 makes that independence explicit in code, copy and that document (section 3, P5).
- **Egress.** The pasted route reads on device; this plan adds no destination. Collection and transcription happen in the owner's tools outside the product, as for Taiwan.
- Every closed product rule (unknown is never zero, append-only records, nothing saves except Log, no medical interpretation).

## 1. What exists today

| Piece | State | Where |
|---|---|---|
| English row vocabulary | Energy, Fat, Saturates, Carbohydrate, Sugars, Fibre, Protein, Salt, Sodium and US variants | `NutritionLabelParsing/LabelVocabulary.swift` (`englishRows`, pinned); `of which` is removed in `NutritionLabelTextParser.swift` |
| English serving and pack lines | Pack lines `Servings per container / pack / package` only; not `This pack contains`, `Contains N portions` or `Serves` | `NutritionLabelTextParserV3.swift` (`englishPackPhrase`) |
| Format inference | English with a per 100 g or ml column, or a salt or kJ row, is UK; other English is US and declines. Australian, New Zealand and EU English panels with a per 100 column also infer as UK | `NutritionLabelParsing/PastedLabelConversions.swift` (`LabelFormatInference`) |
| Decline gate | UK mandatory rows in `LabelDeclineGate.swift`; a missing mandatory row is a G3 **flag**, not a decline; G5 blocks ready without a per 100 column | `LabelDeclineGate.swift` |
| Arithmetic checks | Jurisdiction and tolerances (the larger of 15 kcal and 10%, as for Taiwan), the kJ / kcal ratio, the UK fibre form | `LabelGateTables.swift`, `LabelArithmeticChecks.swift` |
| Conversions | kJ to kcal and salt to sodium (÷ 2.5), labelled as calculated (v1 decision 6); version `pasted-label-conversions-v1` | `NutritionLabelParsing/PastedLabelConversions.swift`, repeated in `PastedLabelSource.rules` |
| Copy | "English (UK layout)"; the supported-layout sentence is built from the pasted scope and is **also used by photo declines** | `FoodLedgerPresentation/PastedLabelText.swift`, called from `LabelPhotoText.swift` |
| **Pasted launch scope** | `["taiwan_nutrition_labelling"]`: a UK table that passes the gate still declines `layout_not_supported`. Read directly by the static `PastedLabelReader.classify`, with no injection point | `FoodLedgerApplication/LabelReading.swift` (`PastedLabelLaunchScope`) |
| Photo launch scope | Its own constant, `LabelPhotoReading.launchScope`; photo verification requires it to be equal | `LabelPhotoReading.swift`, `LabelPhotoSource.swift` |
| Reader v3 freeze | `ReaderV3FreezeTests` pins every `NutritionLabelParsing` file, `LabelReading.swift`, the pasted manifests and sources, `NutritionLabelTextReader.swift` and the Taiwan fresh-set harness and scorer; pin 1 asserts new readings use parser v3 | `ReaderV3FreezeTests.swift`; reader v3 section 12.1 |

Evidence: 191 usable tables and 16 declines of **synthetic** English text rendered from the reviewed development truth, all exact (`Tools/NutritionLabelCaptureEvaluation/results/route-a-development-v1.md`). That is development evidence only: the parser was built against it, and no real pasted UK text has been read.

**Why this is not a one-line change.** Taiwan's synthetic results were just as clean, yet the first real Taiwan development set declined 17 of 24 labels (71%), mostly from layouts the synthetic renderer never produced. Real UK text will have its own shapes. Shapes to expect, from public retailer pages and the UK diagnosis in the [capture evaluation](nutrition-label-capture-evaluation-v1.md) section 9.7 (to be confirmed by the development set, not assumed):

- titles and lead lines: `Typical values`, `Nutrition`, `Nutritional information`, `Each 30g serving contains`;
- headers: `Per 100g`, `per 100ml`, `Per 30g serving`, `Per biscuit (12.5g)`, `% RI*`, `%RI per serving`, "as sold", "as prepared" and `with 125ml semi-skimmed milk`;
- energy printed in one cell (`1520kJ / 362kcal`), on two lines, or as `Energy (kJ)` and `Energy (kcal)` rows;
- extra sub-rows: `of which mono-unsaturates`, `polyunsaturates`, `polyols`, `starch`; vitamins and minerals with `%NRV`;
- non-numeric values: `<0.5g`, `Trace`, `Tr`, `-`;
- footers: `Reference intake of an average adult (8400kJ / 2000kcal)`, `This pack contains 8 servings`, `Contains 4 portions`;
- multilingual EU packs that read as `mixed` and so decline `format_ambiguous`.

## 2. Principles carried over unchanged

Reader v3 section 2 applies as written: the reader may leave a value, row or table unread, and may **never** bind a value to the wrong row, column, basis or unit; nothing printed vanishes ("Printed but not read"); the user validates on Confirm. Every proposal in the UK reader is judged by that rule first and decline rate second. Two UK applications are made explicit:

- **Markers are never zero.** `Trace`, `Tr`, `-` and `nil` are never bound as 0. They are left unread and listed under "Printed but not read", or, for `<0.5g`, bound as a bound with its comparator.
- **Identity is a closed rule.** A column for the food with something added (milk, water) is not the food as sold. If P1 finds such headers that the current markers (`prepared`, `drained`) miss, P2 adds them under a new identity mapping version, `pasted-label-identity-v2`, never by widening v1.

## 3. Phases

Each phase is its own PR with the full gates and its ledger row, except where noted. **The Taiwan path never changes**: Taiwan and `mixed` texts keep reader v3 (decision 7), so the reader v3 freeze stays intact apart from the named re-pins below.

**P0. This plan, approved.** Decisions of section 8, then this gate revision. A tracking issue is opened (with owner approval for the remote write).

**P1. UK development set.** About 24 public UK label texts (section 4), read through a **development-only harness** in a new, unpinned test file: it calls `LabelTextReading` directly and copies `PastedLabelReader.classify` without the launch-scope line, and is labelled development-only. A parity test shows it equals `classify` on every Taiwan fixture. It is never used for P4, and no product file changes (decision 8). Report counts only (section 6): accepted, declined by reason, values matched, wrong, not read, not stated, flags, warnings, correction burden, basis choices needed, plus these named counts: US-shaped panels reaching Confirm, non-UK English declarations, headers with something added, marker cells. A probe pass on scratch copies names the root cause of each decline class.

**P2. UK reader.** Changes only:

- a new parser file for English text (`nutrition-label-text-parser-uk-v1`, working name) and a new alias file `uk-row-aliases-v1`, each a new freeze key; `LabelVocabulary.swift` and parser v3 are not edited;
- a new reader adapter file beside `NutritionLabelTextReader.swift` that sends pure `english` texts to the UK parser and every other text to the pinned v3 reader, used by the harness only until P5;
- the reader seam: `PastedLabelReader` and `PastedLabelConfirmation` take a launch scope, defaulting to `PastedLabelLaunchScope.enabledFormats`, and the scope constant moves to its own unpinned file. This touches pinned files, so it is a **named re-pin amending reader v3 section 12.1** (decision 8), with a test that the default-scope reader equals today's `classify` on every fixture;
- the identity mapping v2, if P1 calls for it (section 2).

Format inference, the gate, the checks and the conversions stay at their current versions. Any change to one is a separately versioned component with its own identity check over the pasted **and** photo fixtures. Synthetic fixtures (invented values and names) and mutation cases under both oracles (reader v3 section 7.2) cover every new rule. The development set is re-run at every PR and must keep zero wrong values. If a new target is added, `check-boundaries.sh` is extended.

**P3. Freeze and UK fresh-set protocol.** In one commit, before any fresh label is collected ([P3 spec](pasted-nutrition-label-uk-english-v1-p3.md); its section 6 records an open owner decision for P5 on which policy `.product` becomes):

- the UK freeze: a new `UKReaderFreezeTests` pinning the UK parser, `uk-row-aliases-v1`, the adapter, the UK harness and scorer, and every file they read through;
- a **new** UK harness and scorer file with its own run and transcription schemas; `FreshSetProtocol.swift` and its Taiwan comparator and unit tables are not edited;
- the UK protocol adapted from reader v3 section 12.2: exclusion of every development site and product, 24 fixed slots by category and page kind, one English search term per category, eligibility and skip reasons, and the scorer's UK equivalence tables (units `kJ`, `kcal`, `g`, `mg`, `µg`; comparators `<`, `less than`; markers `Trace`, `Tr`, `-`; energy written as `kJ / kcal` in one cell);
- the one change allowed after the check, named in advance: the P5 diff below.

**P4. Release check, run once.** ([results](pasted-nutrition-label-uk-english-v1-release-check.md): the harness step passed the bar on 5 November 2026, with 4 of 24 labels reaching Confirm; the device step is pending.) Collector, blind transcriber, owner verification with two seals, one run on the freeze reference: the harness with the UK scope injected through the seam, and the device step through a **`#if DEBUG`-only** composition-root switch that injects the UK scope, never compiled into TestFlight or App Store builds and covered by its own test (decision 9). A Debug build installed on the owner's iPhone for this step is not distribution under reader v3 section 5.1. **Bar: zero wrong values** in every table that reaches Confirm. Any wrong value stops release and spends the set. A results file of counts, like the Taiwan release check.

**P5. Enable UK.** Only after P4 passes and the owner decides to ship, and only this diff:

- `PastedLabelLaunchScope.enabledFormats` becomes `["taiwan_nutrition_labelling", "uk_nutrition_declaration"]`, in that order, in its unpinned file; the composition root wires the P2 adapter for the product; the debug switch is removed;
- **new** manifests record that scope; stored manifests are never rewritten, and every stored Taiwan manifest decodes, verifies, reopens and re-encodes byte for byte;
- the UK parser's pipelines are appended to the admitted pipelines under manifests v1 and v2; the v3 entries stay; pin 2's hash is unchanged;
- the contract version for UK manifests, as decided (decision 10), with the distribution check recorded in the PR;
- photo independence: photo decline copy built from `LabelPhotoReading.launchScope`, not the pasted scope; [label photo AI pre-fill v1](label-photo-ai-prefill-v1.md) "launch scope" and "Locale" text updated to say the photo route has its own scope;
- view-model and simulator UI tests for a UK paste ending on Confirm with one Log action, the contract tests of section 7.1, a `journey-qa` walk and the `docs/releases/unreleased.md` row.

## 4. Development set (P1)

- **Size and kinds:** 24 labels, about 15 retailer pages across at least five retailers, 5 manufacturer pages, 4 PDFs, mirroring the Taiwan set so the two are comparable.
- **Categories:** the ten Taiwan categories with UK search terms (biscuits, soft drinks, milk and yoghurt, cereal, sauces, instant noodles, frozen, confectionery, nuts and dried fruit, bread), plus ready meals, which are common in UK pasting.
- **Collection:** public pages only, no account, no sign-in. A page behind a CAPTCHA or bot check is skipped (`blocked`), never bypassed. A table published only as an image is skipped (`table_image`).
- **Expected values:** for the development set, the agent's own transcription, checked by the owner later (as for Taiwan; development figures are not an accuracy rate).

## 5. Release check (P3 and P4)

As reader v3 section 7.4 and 12.2, with these UK differences:

- at least 24 fresh labels (bar at least 20), from sites and products not in the development set;
- a table printed per serving only reaches Confirm with the G5 block shown, and is scored like any other accepted table;
- calculated sodium from salt (salt ÷ 2.5) and kcal from kJ are scored on their operand only, and a calculated value beside a printed one is reported, never gating (reader v3 12.2.8);
- non-UK English declarations and US-shaped panels are counted on their own;
- the statistical limit is reported with the real counts (rule of three), never as a zero rate.

Goals that do not gate release: decline rate at most 25%, median correction burden at most 1.

## 6. Privacy

All real-text material lives in one private folder outside every git checkout and outside synced storage, `~/WHR-label-eval-private/uk-english-v1/`, split into `development/` and `fresh-set/`. The harness refuses a folder inside a git checkout; nothing checks synced storage, so that is a manual checklist item in every PR touching either set. Label texts, screenshots, page addresses, product names, transcriptions, per-label results and every hash stay there; tools write only there. The repository receives counts, page kinds and the selection rules. Every such PR carries the checklist item: "Only counts and rules were added from the real-text sets; no text, value, product name or hash."

## 7. Risks

- **UK told apart by shape.** A UK paste with neither a per 100 column nor salt or kJ infers as US and declines: safe. A US panel with a per 100 column, or an Australian, New Zealand or EU English panel, infers as UK and reaches Confirm with G3 flags for its missing rows rather than declining. P1 counts both; decision 11 (settled 3 November 2026) accepts them.
- **Reference intake columns and footers.** `%RI` cells and the reference intake footer (`8400kJ / 2000kcal`) must never bind as amounts.
- **Something added.** Headers such as `with 125ml semi-skimmed milk` miss today's basis-state markers and would be stored as the food as sold; section 2 and P2 cover it.
- **Older builds.** A shipped build that lacks the UK pipelines fails verification on a UK manifest (for example after an archive restore); decision 10 covers it.

### 7.1 Contract tests

1. Scope pin: `PastedLabelLaunchScope.enabledFormats` equals the two formats in order (P5; updates `PastedLabelApplicationContractTests`).
2. Photo independence: `LabelPhotoReading.launchScope` stays Taiwan-only, and photo verification rejects a manifest whose `launch_scope` includes UK or whose `label_format` is UK.
3. Photo decline copy names only the Taiwan layout while the pasted scope includes UK.
4. Golden bytes: stored Taiwan v1 and v2 manifests with Taiwan-only `launch_scope` decode, verify, reopen and re-encode byte for byte after P5.
5. A new UK manifest under v1 and v2 round-trips byte for byte and verifies at save and reopen, including salt-only sodium and kJ-only kcal conversions.
6. Admitted pipelines: the full list is pinned with the UK entries appended; the v3 entries stay; pin 2's hash is unchanged.
7. Routing: every `zh-Hant` and `mixed` text goes to the pinned v3 reader, and its output (candidate bytes, reading, outcome, flags, warnings, conversions, basis options and manifest) equals today's on every Taiwan fixture and parity case.
8. Seam and dev harness: a default-scope reader equals today's `classify`; the P1 dev harness equals `classify` on every Taiwan fixture.
9. UK mutation cases under both oracles: a `%RI` column beside an amount column; the reference intake footer never binding; `Trace`, `Tr` and `-` never becoming 0; `<0.5g` keeping its comparator; `kJ / kcal` in one cell; headers with something added; per-serving-only tables (G5 block, no wrong basis).
10. Format inference vectors for US with per 100, Australian and New Zealand, and EU English panels, pinning decision 11's outcome.
11. `UKReaderFreezeTests` as in P3.
12. The debug switch is absent from Release builds.

## 8. Owner decisions

Asked one at a time, each with a recommendation.

### 8.1 Decided (owner, in session, 2 November 2026)

1. **Scope: UK only, or UK and Irish English-only packs?** *Recommendation: UK only for v1.* **Decided: UK only.**
2. **Development set as in section 4?** *Recommendation: yes.* **Decided: yes, as described.**
3. **Taiwan path.** May the UK work ship without a new Taiwan fresh set if every Taiwan reading is unchanged? *Recommendation: yes, with an identity check.* **Decided: yes, with the identity check gating P3.** Decision 7, if taken, meets this by construction: Taiwan stays on the pinned v3 reader, and test 7 is the identity check.
4. **Release bar and goals as in section 5?** *Recommendation: the same as Taiwan.* **Decided: the same as Taiwan.**
5. **Roles** (collector, blind transcriber, owner verification, runner) as for Taiwan? *Recommendation: yes.* **Decided: yes, as for Taiwan.**
6. **Photo route stays Taiwan-only?** *Recommendation: yes.* **Decided: yes, Taiwan only.**

### 8.2 Added by the gate revision (decided by the owner, in session, 2 November 2026)

7. **Separate UK parser.** Send only pure `english` texts to a new UK parser and keep `zh-Hant` and `mixed` on the pinned reader v3, so Taiwan manifests stay byte-identical, at the cost of two parsers being live? *Recommendation: yes. The alternative, one parser v4 for both, changes `parser_version`, the pipeline and the release identifiers in every new Taiwan manifest, needs a manifest allow-list and amends pin 1.* **Decided (owner, in session, 2 November 2026): yes, a separate UK parser.**
8. **Harness and seam.** P1 uses a development-only harness with no product change; P2 adds the launch-scope seam as a named re-pin amending reader v3 section 12.1? *Recommendation: yes; the seam makes P4 and P5 possible without editing a pinned file again.* **Decided (owner, in session, 2 November 2026): yes to both; this approves the seam re-pin as an amendment to reader v3 section 12.1.**
9. **Device step of P4** through a `#if DEBUG`-only switch on a Debug build on the owner's iPhone, not counted as distribution? *Recommendation: yes; without it, a UK paste on a device can only decline before P5.* **Decided (owner, in session, 2 November 2026): yes, Debug only.**
10. **Contract version.** Do UK manifests raise `minimumContractVersion`, as reader v3 decision 13 did for manifest v2, so an older build refuses them clearly instead of failing verification? *Recommendation: yes.* **Decided (owner, in session, 2 November 2026): yes, for UK manifests only; Taiwan manifests keep their current contract version.**
11. **Non-UK English panels** (US with per 100, Australian, New Zealand, EU English): decide after P1's counts, before P3, between declining them (format inference v2, with photo fixtures in its identity check) and accepting them with copy that names no country. *Recommendation: decide on P1's evidence; lean towards declining, because the release check samples UK only.* **Decided (owner, in session, 2 November 2026): decide after P1's counts, before P3, leaning towards declining.** **Settled (owner, in session, 3 November 2026): allowed.** P1 and the P2a re-run found no such panel (every page was a UK site), so there was no evidence either way; the owner chose to accept them. A US panel with a per 100 column and Australian, New Zealand or EU English declarations keep inferring as UK under format inference v1 (no new version) and reach Confirm with G3 flags for any missing UK row; P5 settles the copy so it never claims the panel comes from the UK. Test 10 pins these vectors as accepted, and the P3 protocol counts them on their own. The release check still samples UK labels only, so its result says nothing about these panels; P5's release note says so.

## 9. Architecture gate findings applied (2 November 2026)

| Finding | Addressed in |
|---|---|
| 1. No injection point for a harness-only scope | P1 (development harness), P2 (seam), decision 8, test 8 |
| 2. Device run cannot see UK on the freeze build | P4, decision 9, test 12 |
| 3. Changing the scope edits a pinned file | P2 (scope in its own file), P3 (P5 diff named), P5 |
| 4. Parser version changes Taiwan manifests | Decision 7, P2 routing, test 7, decision 3 note |
| 5. Photo declines share the pasted scope copy | Section 1, P5, tests 2 and 3 |
| 6. Older builds and the contract version | Section 7, decision 10 |
| 7. Headers with something added | Section 2, P1 count, P2, test 9 |
| 8. Non-UK English infers as UK | Section 1, section 7, decision 11, test 10 |
| 9. Missing UK rows are flags, not declines | Section 1, section 7 |
| 10. Shared components with the photo route | P2 |
| 11. Pinned vocabulary, harness and scorer | P2, P3, test 11 |
| 12. Markers never zero | Section 2, test 9 |
| 13. Stored manifests never rewritten | P5, test 4 |
| 14. Section 1 table corrections | Section 1 |
