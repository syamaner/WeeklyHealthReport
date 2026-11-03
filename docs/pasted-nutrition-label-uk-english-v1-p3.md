# Pasted nutrition label, UK English v1: P3 freeze and fresh-set protocol (#371)

Status: **revision 2, 3 November 2026: architecture gate PASS WITH CHANGES on revision 1, all eight changes applied (section 9).** Phase P3 of [the UK English plan](pasted-nutrition-label-uk-english-v1.md), after [P2a](pasted-nutrition-label-uk-english-v1-p2.md) and [P2b](pasted-nutrition-label-uk-english-v1-p2b.md). It lands in one commit before any fresh label is collected. It adds tests, a harness, a scorer and this protocol; **no product source file changes**, so no shipped behaviour changes and no reader v3 pin moves.

The plan named `uk-row-aliases-v1` as its own file. P2a put the UK row lists (`UKVocabulary.subRowParents`, `topLevelRows`) in `UKVocabulary.swift`, versioned with the parser, so there is no separate alias key; pin 2 lists those tables.

## 1. The UK freeze (`UKReaderFreezeTests`)

Frozen as of the P3 commit, which is the reference of the P4 release check: `nutrition-label-text-parser-uk-v2`, `pasted-label-identity-v2`, the reading policy `.ukDevelopment`, the UK reader adapter, and the UK harness and scorer. Any later change to what one of them does is a new version and needs a new fresh set. Three pins, as reader v3 section 12.1:

1. **Version strings:** `NutritionLabelTextParserUK.version`, `PastedLabelBasisStateV2.version`, the guard's three decline codes, the two UK schemas (section 2), and `.ukDevelopment`'s scope and identity.
2. **Rule tables:** a SHA-256 of a canonical listing of `UKVocabulary` (value and header patterns, unit tokens, energy labels, sub-row parents, top-level rows, identity markers), the normalisation and guard constants and patterns, identity v2's markers, and the scorer's equivalence tables (section 3). It never changes while these versions exist.
3. **Source files:** a SHA-256 of each file below, comments included, held **in this freeze** whether or not the reader v3 freeze also pins it. Every file of `Sources/UKNutritionLabelParsing/` and of `Sources/FoodLabelTextCapture/` is enumerated (every file type, resources included), so a new file in either module cannot slip past.
   - every file of `Sources/UKNutritionLabelParsing/` and of `Sources/FoodLabelTextCapture/` (the UK adapter, the pinned reader it falls back to, and `PastedHeaderBasisGuard.swift`, which that reader calls and neither freeze pinned before);
   - `Sources/FoodLedgerApplication/PastedLabelBasisStateV2.swift` and `PastedLabelLaunchScope.swift` (the policy the harness reads);
   - the shared files the UK path reads through, with their own UK hashes: every file the reader v3 freeze pins (parser v3, gate, checks, conversions, format inference, `LabelReading.swift`, `PastedLabelConfirmation.swift`, the manifest files) and `Tests/FoodLabelTextCaptureTests/FreshSet/FreshSetProtocol.swift`;
   - `Tests/FoodLabelTextCaptureTests/UKFreshSet/UKFreshSetProtocol.swift` and `UKFreshSetStepTests.swift`.

   A reader v3 re-pin of a shared file (as P2b re-pinned `LabelReading.swift`) can be right for Taiwan and still change UK reading, so it fails here too and needs its own record in this freeze. A test also asserts that every reader v3 pinned file is in this list, so neither freeze can drop one silently.

**Re-pin rules** are reader v3's (12.1), recorded in a new "Re-pins after the UK freeze" list in this file. **The one change named in advance** is the P5 diff (section 6). Its re-pins are recorded with pins 1 and 2 shown unchanged.

## 2. The UK harness (`UKFreshSetProtocol.swift`, new)

A new file beside the Taiwan one; `FreshSetProtocol.swift` is not edited. It reuses the Taiwan file's infrastructure unchanged (`FreshSet.privateFolder`, the bundle hash and seals, `requireSealed`, `append`), so the private-folder refusal and the bundle hash are the same code. The UK seal step follows the same rules (order, "a seal is never replaced", the `seals.txt` format) in its own function, because the Taiwan one validates the Taiwan schema. Everything that reads or scores is its own:

- **Transcription schema `uk-english-v1-fresh-transcription-v1`.** The Taiwan shape (label ID, serving size, servings per pack, columns, rows, notes) plus:
  - `panel`: `uk_declaration`, `us_nutrition_facts` or `other_english` (Australian, New Zealand, EU English, or a US panel with a per 100 column), as the screenshot shows it; counted on its own (decision 11);
  - `panel` is decided by the panel's title alone: `us_nutrition_facts` when it is titled `Nutrition Facts` (with or without a per 100 column), `uk_declaration` when it is titled as a UK declaration or not titled and printed by a UK site's product, and `other_english` for an Australian, New Zealand or other English title (`Nutrition Information`, `Average Quantity`), whatever the site;
  - markers as first-class values: `{"comparator": "=", "number": "<the marker as printed>", "unit": ""}` with no `outside_table`, for a printed `Trace`, `Tr`, or any dash (`-`, `–`, `—`, `−`); any other non-numeric cell (`N/A`, `*`) is recorded as Amendment 3, with `outside_table`;
  - **row labels are recorded as printed on the line that holds the value**, so a continuation line `(kcal) 240kcal` under `Energy 1000kJ` is a row labelled `(kcal)`, nutrient `energy_kcal`;
  - one cell printing kJ and kcal together (`1000kJ/240kcal`) is recorded as **two rows with the same label**, nutrients `energy_kj` and `energy_kcal`, each holding its own part as printed. Example (synthetic): `{"label": "Energy", "nutrient": "energy_kj", "values": [{"comparator": "=", "number": "1000", "unit": "kJ"}]}` then the same with `energy_kcal` and `240`, `kcal`.
- **Run schema `uk-english-v1-fresh-run-v1`.** The Taiwan run result plus `format` (the inferred format). The run reads through `PastedLabelReader(reader: UKEnglishLabelTextReader(), digester: SHA256Digester(), policy: .ukDevelopment)` and builds its `PastedLabelConfirmation` with the **same** `.ukDevelopment` policy. The run only calls `choose` (the basis choice, reader v3 12.2.7 item 2, exactly); it never builds a manifest, and `manifest` throws `identityNotRecordable` for the UK policy (P2b), so no UK record can be built before P5. `UKDevelopmentSet.runAll` is aligned to the same pairing. The run log, the single rerun for an infrastructure failure and the refusal of a third attempt are as 12.2.7 item 3.
- **Steps**, each one opt-in test run skipped in the gates: `WHR_UK_FRESH_SET_DIR=<private folder> WHR_UK_FRESH_SET_STEP=<step> swift test --package-path Packages/FoodLedgerKit --filter UKFreshSetStepTests`, with `<step>` one of `seal-texts`, `validate`, `seal-1`, `seal-2`, `run`, `score`. `run` and `score` refuse when the texts or transcriptions differ from their seals.
- **Development use.** `UKDevelopmentSet` (unpinned, development only) scores with `UKFreshSet.score` from P3, decoding the P1 transcriptions (Taiwan schema, `panel` absent and counted `unknown`) through a development-only decoder. The release-check steps accept only the UK schema.

## 3. The UK scorer

`UKFreshSet.score` applies reader v3 12.2.8 with these UK tables, closed and fixed before collection. Every rule not named here is 12.2.8's, word for word.

- **Comparators:** `=` → `=`; `<`, `less than` (case-insensitive) → `<`; `<=`, `≤` → `<=`. Anything else has no mapping.
- **Units**, exact or lowercased: `kj` → `kJ`; `kcal` → `kcal`; `cal` → `cal` (kept apart, as 12.2.8); `g`, `gm`, `gms`, `gr`, `grs` → `g`; `mg` → `mg`; `µg`, `μg`, `mcg` → `µg`; `ml` → `ml`; `%` → `%`. Compound units as Amendment 3 (`kJ/kcal` is not a compound: its parts map to different units, so a transcriber records two rows).
- **Markers:** `Trace`, `Tr` (case-insensitive) and every dash (`-`, `–`, `—`, `−`), one class: a transcriber cannot tell the dashes apart reliably. Unbound, or bound as any marker of the class, is not wrong; any number bound there is wrong, `0` included.
- **Comma numbers:** exactly 12.2.8's rule through the reader's own `ParseStateV3.isAmbiguousNumber`, unchanged.
- **Label normalisation for unrecognised rows**, applied to the transcription's and the reader's label alike (12.2.8's steps, then):
  1. leading markers also include `—`, `–` and `_`;
  2. one leading `of which` (any case, any spacing) is removed;
  3. a bracket group whose content is a unit is removed only when something else remains, so a label that is only `(kcal)` normalises to `kcal`;
  4. every remaining bracket character is removed, so `(of which sugars)` and a label cut at a stray `(` both normalise to `sugars`;
  5. the Taiwan `(自願標示)` step does not apply.
- **Unit agreement.** A unit that an unrecognised cell's label names in brackets, or that the matched row's label names, must equal the cell's canonical unit; otherwise the value is wrong. So removing a unit bracket in normalisation never hides a mismatch (`Energy (kJ)` holding a kcal value is wrong).
- **Disambiguation by unit.** When two or more transcription rows share a normalised label (an energy cell recorded as kJ and kcal rows), an unrecognised cell matches the one among them whose value in its column has the cell's canonical unit. Still none or more than one: a wrong value.

**Why these rules cannot forgive a misbinding.** Each rule only decides **which printed row** a reader value is compared with; the comparison itself (comparator, exact number, canonical unit, column basis) is unchanged, and a match never counts as reading a ledger nutrient, so the correction burden is unaffected. A value bound to the wrong row, column, basis or unit still differs from the row it is matched with, or matches no row, and both are wrong. Contract test 6 shows each rule's negative case.

**Not pinned on purpose:** `PastedLabelDomain.swift` and `LedgerCommands.swift` (`PastedLabelIdentity`, `SHA256Digester`) are general ledger files changed by unrelated work; pin 1 holds the decline code strings the UK path uses, and the digester is SHA-256 by contract. A stray `.DS_Store` in either enumerated module fails the freeze locally; that is a false failure, kept as fail-safe.

## 4. The UK fresh-set protocol (adapted from reader v3 12.2)

Roles, the text seal, blind transcription, owner verification with two seals, the review page, the run and the bar are reader v3 12.2's, with the UK harness and scorer. Differences:

### 4.1 Exclusions

Every site and product of the development set. Sites, by name: retailers M&S, Aldi UK, Healthy Supplies, Abel & Cole, Amazon UK (every seller on Amazon UK); manufacturers COOK, Tyrrells, Warburtons, Clearspring, Dorset Cereals; NHS Supply Chain documents. The private exclusion list (site, brand, product and each development text's SHA-256) is written to the fresh-set folder from the development records before collection starts.

### 4.2 Slots

24 slots, 15 retailer pages, 5 manufacturer pages and 4 PDFs, fixed in this order:

| Slots | Page kind | Categories, in slot order |
|---|---|---|
| 1 to 11 | Retailer | biscuits and crisps, soft drinks, milk and yoghurt, cereal, sauces, instant noodles, frozen, confectionery, nuts and dried fruit, bread, ready meals |
| 12 to 15 | Retailer | biscuits and crisps, cereal, ready meals, milk and yoghurt |
| 16 to 20 | Manufacturer | biscuits and crisps, soft drinks, cereal, confectionery, bread |
| 21 to 24 | PDF | sauces, frozen, ready meals, soft drinks |

| Category | Search term | Belongs |
|---|---|---|
| Biscuits and crisps | `biscuits` | biscuits, crackers, crisps, puffed snacks |
| Soft drinks | `soft drinks` | squash, juice, fizzy drinks, ready-to-drink tea and coffee (not milk) |
| Milk and yoghurt | `milk` | milk, flavoured milk, yoghurt, cheese |
| Cereal | `breakfast cereal` | oats, muesli, granola, breakfast cereal |
| Sauces | `sauce` | sauces, dressings, condiments |
| Instant noodles | `instant noodles` | instant, cup and pot noodles |
| Frozen | `frozen` | foods sold frozen |
| Confectionery | `chocolate` | sweets, chocolate |
| Nuts and dried fruit | `nuts` | nuts, seeds, dried fruit |
| Bread | `bread` | bread, rolls, wraps, cakes, pastries |
| Ready meals | `ready meal` | chilled or ambient ready meals |

### 4.3 Search procedure

As 12.2.3 with its amendments built in from the start: up to the first **50** results per retailer and category, at most **3** labels per site across every page kind, and each candidate PDF listed to the owner (file name, site, size) before it is downloaded.

Retailers, none in the development set, rotated as 12.2.3: 1. Tesco, 2. Sainsbury's, 3. Asda, 4. Morrisons, 5. Waitrose, 6. Ocado, 7. Iceland, 8. Co-op, 9. Lidl GB, 10. Holland & Barrett, 11. Planet Organic, 12. Sous Chef. A retailer that shows a CAPTCHA, bot check or traffic-verification page is skipped `blocked` and exhausted for that category, never bypassed; the development set found most large grocers refuse automated visits, so the collector may be the owner in Safari, and the skip log records which.

**The collector is fixed per retailer before collection starts** (an agent in the in-app browser, or the owner in Safari) and recorded in the private folder; it is never chosen after a page is seen.

Manufacturer and PDF slots: Google, signed out, private window, English interface, region United Kingdom. Query: the category's term followed by ` nutrition information`, and for PDFs ` nutrition information filetype:pdf`. Up to the first 30 organic results; ads, "People also ask", image, video and shopping blocks are not results. A manufacturer slot takes the first eligible page on the brand owner's own site; a retailer, marketplace, news, blog, forum or recipe page is skipped `not_source_kind`. A PDF slot takes the first eligible PDF with a text layer, from a manufacturer, importer, retailer or foodservice supplier.

**Fallbacks**, in order, each logged:

1. A manufacturer or PDF slot with no eligible result in its first 30 becomes a retailer slot of the same category (`kind_fallback`).
2. A retailer slot for which every retailer is exhausted, blocked or capped is left unfilled (`slot_unfilled`).
3. Fewer than 24 labels after slot 24: walk the slot table again from slot 1, filling unfilled slots, then adding one label per slot in slot order, until 24 labels or a walk adds none.
4. Fewer than 20 labels after that: stop. There is no run; the shortfall and skip counts are reported, and the protocol is amended in a new commit before collection continues.

**Amendment 1 (owner, 3 November 2026, before any fresh page is opened).** The owner chose an agent collector with the owner as fallback. From this commit:

1. **Collectors, fixed now.** Every retailer, manufacturer and PDF slot starts with an agent in the Claude desktop app's built-in browser, run in its own session that has never read the parser source, this repository's tests or the development set's per-label results. The fallback is a rule, not a choice: the first time a site shows the agent a CAPTCHA, bot check or traffic-verification page, that visit is logged `blocked` (collector `agent`) and the owner in Safari becomes that site's collector for the rest of collection; Google moves to the owner in a Safari private window the same way. A block page shows no label, so the switch cannot depend on what a label prints. The assignment and every switch are recorded in `collectors.json` in the private folder.
2. **How the agent copies.** The agent selects the nutrition section in the built-in browser from the first line to the last (12.2.4 item 2) and copies with the system copy command; the clipboard's plain text is saved exactly as copied (read with `pbpaste`, no edit). The owner copies in Safari on macOS, and either collector uses Preview for a PDF. Each `source.json` records the collector and the copy method. If the agent's copy does not reach the system clipboard, collection stops before the first label and the protocol is amended; the agent never substitutes a scripted selection.

### 4.4 Eligibility and skip reasons

As 12.2.4, with item 1 as: a food sold in the UK, on an English page, with a nutrition table in English. Panels are **not** chosen by kind: a US-style or other English panel on an eligible page is taken like any other and counted under `panel`. Skip reasons as 12.2.4, with `non_taiwan` replaced by `non_uk`. The text is copied in Safari on macOS (Preview for a PDF) exactly as 12.2.4 item 2.

### 4.5 Scoring and reporting

The bar is unchanged: **zero wrong values** in every table that reaches Confirm, harness and device step alike; any wrong value stops release and spends the set. Reported, never gating, as plan section 5: decline rate (goal at most 25%), correction burden (median goal at most 1), calculated-beside-printed discrepancies, counts by `panel` (US-shaped and other English panels on their own, with the note that the check samples UK sites only), and the rule-of-three limit with the real counts.

## 5. Invariants

- No product source file changes; the reader v3 freeze, its pins and every Taiwan reading are unchanged.
- The UK harness never builds a UK manifest (the confirmation throws for `.ukDevelopment`, P2b).
- The scorer's tables are fixed before collection and pinned; nothing in them reads a fresh label.
- No real label text, value, product name, address or hash enters the repository; the development re-run reports counts only.

## 6. The P5 diff, named in advance, and an open owner decision

P5 is allowed exactly the plan's list. This freeze surfaces one gap in it, recorded here as **an open owner decision before P5, not settled by P3**: the release check measures `.ukDevelopment` (both formats, identity v2), and the plan's list does not say which policy `.product` becomes. The recommendation is that `.product` becomes equal to `.ukDevelopment`, so the check measures what ships. That goes beyond the plan's list, so it needs:

- a plan amendment approved by the owner;
- a versioned identity contract for manifests recording v2 (with decision 10), and a named reader v3 re-pin of `PastedLabelConfirmation.swift`;
- a **whole-reading Taiwan check**: once the UK adapter is wired, English-language Taiwan texts go through the UK parser and `UKReadingGuard` rather than `PastedHeaderBasisGuard`, so over every Taiwan fixture, parity case and the Taiwan development and sealed fresh sets (read-only, counts only) the outcome, candidate and decline codes must equal today's. If any differs, P5 stops and the owner decides.

## 7. Contract tests

1. **Freeze:** `UKReaderFreezeTests` pins 1 to 3; every shared file has its own UK hash; the UK and `FoodLabelTextCapture` modules are enumerated (all file types); every reader v3 pinned file is in the UK list.
2. **Schemas:** a UK transcription with markers, a `panel` and a split energy cell validates; a Taiwan-schema file is refused by the release steps; an unmarked unit outside the table is refused.
3. **Steps:** the private-folder refusal, seal order and refusal to replace a seal, and `run`/`score` refusing changed texts or transcriptions, on a synthetic folder in the scratch directory.
4. **Run:** a synthetic UK declaration reaches `usable` through `.ukDevelopment`; a basis-choice text follows the transcription's bases; `basis_not_sure` and `basis_not_offered` as 12.2.7; the harness builder's policy is `.ukDevelopment`, and `manifest` throws `identityNotRecordable` for a UK review.
5. **Scorer positives:** `less than 0.5g` matches `<0.5g`; `Trace` unbound and bound as `Trace` are not wrong; every dash pair (`-`/`—`, `–`/`-`, `−`/`—`) is not wrong; a P1 marker recorded with `outside_table` (Taiwan schema) scores through the development decoder; `(kcal)` continuation, `of which — sugars`, `(of which sugars)` and a label cut at `(` match their rows; a kJ/kcal cell recorded as two rows matches by unit.
6. **Scorer negatives** (each still wrong): `Trace` bound as `0`; a sugars value bound to the saturates row; a kcal value matched against a kJ-only label; a value under the wrong column basis; two rows with the same normalised label and unit; a value with the right number and the wrong unit; a label that normalises to nothing; on a kJ/kcal energy pair, a kJ-unit cell carrying the kcal number; a top-level `Sugars` and an `of which sugars` row in the same unit (cannot be told apart, so wrong); a kcal cell labelled `Energy (kJ)` against rows `Energy (kJ)` and `Energy (kcal)` (unit agreement). Schema: `N/A` without `outside_table` is refused.
7. **Development set:** the re-run through the UK scorer keeps zero wrong values from a real misbinding and reports what remains; counts only.

## 8. Questions for the gate

- **Q1.** Is reusing `FreshSet`'s infrastructure (folder, seals, log) right, or should the UK harness copy it so the two freezes share nothing?
- **Q2.** Is pinning `PastedLabelLaunchScope.swift`, with the P5 change named in advance, right, given the plan left that file unpinned for reader v3?
- **Q3.** Is section 6 (`.product` equal to `.ukDevelopment` at P5, with the Taiwan identity check) the right way to keep the release check measuring what ships?

The gate answered: Q1 yes, with the UK's own hashes for shared files (change 1); Q2 yes, and the P5 re-pin shows pins 1 and 2 unchanged; Q3 yes in principle, but it is beyond the plan's P5 list, so it becomes the open owner decision of section 6.

## 9. Gate findings map (revision 1)

1 shared files hashed in this freeze, section 1 and test 1; 2 `FoodLabelTextCapture` enumerated, all file types, section 1; 3 harness confirmation under `.ukDevelopment`, `choose` only, section 2 and test 4; 4 dashes one marker class, other non-numeric cells `outside_table`, sections 2 and 3; 5 label-on-the-value-line rule, `panel` by title, schema example, section 2; 6 `.product` at P5 is an open owner decision, section 6; 7 whole-reading Taiwan check, section 6; 8 UK fallbacks written out and the collector fixed in advance, section 4.3. Optional note: `grs` added to the unit table.

## 10. Invariant review (implementation)

PASS, with three low findings, all applied: unit agreement added to the scorer (section 3) with its negative test; pin 2 lists every Basic Multilingual Plane member of the separator set, not only ASCII; the `.DS_Store` false failure is noted and kept fail-safe. Its two questions are answered in section 3 (files not pinned on purpose) and section 2 (the seal step's own function).
