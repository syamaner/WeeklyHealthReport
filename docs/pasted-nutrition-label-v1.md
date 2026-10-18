# Pasted nutrition label v1 (#93)

Status: **draft for owner approval, 18 October 2026. Documentation only; it authorises no production code until the owner answers the decisions in section 10.** The owner approved drafting this contract on 18 October 2026, after route A of the label-capture evaluation (#255) passed every reader bar on its untouched synthetic pasted-text cases. It is the "independent promotion" that evaluation decision 11 allows, for route A only. No photo route (B or C) is proposed here, and nothing here adds egress.

This contract composes with, and does not amend, [food confirmation v5](food-confirmation-contract-v5.md) (`food_confirmation_v5`), the [food identity and nutrition contract](food-identity-nutrition-contract.md), the [review manifest v2](generic-food-review-manifest-v2.md) and [UX revamp v1](ux-revamp-v1.md). The evaluation it relies on is [`nutrition-label-capture-evaluation-v1.md`](nutrition-label-capture-evaluation-v1.md); its phase 5 results are on PR #260's branch `feat/255-label-eval-phase-5`, cited by path below.

## 1. Evidence this contract rests on, and its limits

| Evidence | What it shows | Where |
|---|---|---|
| Route A, untouched pasted text, run once on 18 October 2026 | 107 synthetic Taiwan cases (75 FDA dataset 188, 32 closed-template, 15 required declines). 1093/1093 strict cells, 1123/1123 bindings, 92/92 tables, 599/599 serving conversions, 92/92 servings per pack, 36/36 bounds, 15/15 declines, 0 false-ready, 0 false declines, 0 automatic persistence | `Tools/NutritionLabelCaptureEvaluation/results/untouched-taiwan-v1.md` section 6, on `origin/feat/255-label-eval-phase-5` |
| Arithmetic mutation detection on the same truth | 110/116: tenfold serving 69/72, basis transposition 32/35, bound replaced by exact 9/9. **6 planted mutations pass the tolerance.** The bar (100%) fails; it measures the shared arithmetic policy, not the parser | same file, section 6 |
| Route A, English development text | 191 usable tables and 16 declines rendered from the reviewed v1 and v2 development truth, all exact. **Development evidence only**: the parser and renderer were built against these cases | `Tools/NutritionLabelCaptureEvaluation/results/route-a-development-v1.md` |
| Parser | `nutrition-label-text-parser-v2`, Swift target `NutritionLabelParsing`, Foundation only | `Packages/FoodLedgerKit/Sources/NutritionLabelParsing/` (on `main`) |
| Decline gate | `label-capture-decline-gate-v2`, in Python, formats `taiwan_nutrition_labelling` and `uk_nutrition_declaration` only | `Tools/NutritionLabelCaptureEvaluation/decline_gate.py` (on the PR #260 branch) |

Limits that carry into the product:

- **Every evaluated case is synthetic.** It was rendered from verified values in known paste shapes by the same generator family the parser was developed against. Real copy-and-paste text from web pages, PDFs and messages is **unmeasured** (evaluation section 3.5). A clean result on synthetic text is not a real-world accuracy rate, and 0 false-ready on 107 cases is not proof of a zero rate.
- **The untouched pass is Taiwan only.** No untouched English pasted-text case was run. English rests on development evidence (decision 3).
- **There is no US gate format.** Gate v2 knows UK and Taiwan mandatory rows only, so a US "Nutrition Facts" paste has no decline gate to run under (decision 4).
- **The arithmetic check misses some planted errors.** It is a warning only here (section 4). Its silence is never evidence that a table is right.
- **Cell-level truth on the untouched photo set has an unknown error rate** (the owner's caveat of 18 October 2026). Route A's text cases were rendered from FDA dataset 188 and templates, not from that photo truth, so this caveat does not change route A's figures, but the general lesson stands: one reviewer can miss an error.

## 2. User journey

One intent, "log a packaged food from its nutrition label", one journey, ending on the shared Confirm screen with one Log action ([UX revamp v1](ux-revamp-v1.md), rule 1).

```
Add food ── Paste nutrition label ── Label text ──(Read label)──┬── Confirm ── Log
                                         ▲                       │
                                         └──── Declined (reason, text kept) ◄┘
```

### 2.1 Add food

Add food gains one row, **Paste nutrition label**, beside barcode, paste or dictate and favourites. It is a separate row from "Paste or dictate" because the intents differ: a food list names several foods by words and amounts; a label declares the nutrition of one food (decision 1).

### 2.2 Label text screen

- A **Name** field (required, plain text, for example "Oat granola"), and an optional **Brand** field. A pasted label rarely names the product, and the saved food needs a name the user can find again. These are identity fields, not nutrient fields; there is still no blank nutrient-entry form (#86).
- A multi-line **Label text** field. The user pastes or types the table. The text stays editable.
- A short line under the field: "Paste the nutrition table only. The text you read is saved with the entry as its source, on this device."
- **Read label** runs the on-device reader (section 2.4). It is disabled while Name or Label text is empty, or the text is over the length limit (section 6.2).
- "Leave without saving" writes nothing. Text that is never logged is not retained, not hashed and not logged anywhere.

### 2.3 Confirm

The shared Confirm screen, with its `food_confirmation_v5` requirements, amount, time and Log action unchanged. The route supplies the source section:

- **Source line:** "From pasted label · per 100 g" (or per 100 ml, or per serving), with the label language ("English, UK layout" or "Traditional Chinese, Taiwan layout").
- **Values, each beside its source text.** One row per stored nutrient: the stored value, then the printed label and printed value exactly as pasted, for example `Fat 3.2 g` beside "Fat · 3.2g", or `Saturated fat 1.1 g` beside "飽和脂肪 · 1.1公克". Bounds read as printed: "Less than 0.1 g" beside "<0.1g".
- **Basis** of the stored values: per 100 g, per 100 ml or per serving (section 6.3 says which column is stored).
- **Serving size and servings per pack** as printed, with the parsed amount: "Serving size 30 g (printed: Serving size 30g)", "Servings per pack about 8 (printed: Servings per container about 8)", "本包裝含 2.5 份". Absent lines read "Not stated".
- **Not stated:** every app nutrient the label does not print reads "Not stated". It is unknown, never zero.
- **Read but not used:** printed rows the ledger does not store (salt, a kJ value beside kcal, % RI or %DV columns, unrecognised rows) are listed with their printed text and "Not used", so nothing printed vanishes silently (section 3.3).
- **Other column:** when a second amount column was printed (for example per serving beside per 100 g), its values are shown under a disclosure as evidence, read-only.
- **Warnings** (non-blocking, section 4), above the Log bar.
- **Pasted text:** the whole text, read-only, behind one disclosure.
- **Edit label text** returns to the label text screen with the text and name kept. Values cannot be edited on Confirm: a misread is fixed by editing the text and reading it again, so every stored value stays bound to the text it came from.

The user picks the amount and taps Log. Amount options, built only from printed facts:

- grams or millilitres, matching the stored basis (the existing per 100 g with mL notice still applies);
- **servings**, only when a serving size with a quantity and unit is printed;
- **whole pack**, only when servings per pack is printed as an exact number (not "about") and a serving size is printed.

Log follows `food_confirmation_v5` exactly: it is the explicit acceptance of the food, amount, time and source shown at that moment, and it is the only save. A parse result, a warning, a passed check or the absence of a warning never saves and never enables Log by itself.

### 2.4 The reader

Read label runs, on device and in this order, with no network, clock or randomness dependency:

1. `nutrition-label-text-parser-v2` (unchanged) on the exact text;
2. the decline gate ported to Swift (section 7), which may decline but never changes a value;
3. the arithmetic and consistency checks (section 4), which may add warnings but never change, fill or remove a value.

A declined result shows the decline screen state (section 3). A non-declined result opens Confirm.

## 3. Declines, partial tables and unknowns

### 3.1 What the user sees

A decline stays on the label text screen, with the text kept and a plain reason above the field. Codes are for Developer tools only.

| Reason codes | Copy |
|---|---|
| `unsupported_language`, `unsupported_script` | "This label is in a language the app cannot read yet. It reads English (UK layout) and Traditional Chinese (Taiwan layout) labels." |
| `no_table` | "No nutrition table was found in this text." |
| `multiple_panels` | "This text seems to contain more than one nutrition table. Paste one table at a time." |
| `no_basis_header`, `duplicate_basis`, `required_basis_missing` | "The text does not show clearly whether values are per 100 g, per 100 ml or per serving." |
| `count_mismatch`, `column_count_mismatch`, `values_without_row` | "Some values could not be matched to their rows. Check that each row has its values on the same line or in the same order." |
| `energy_without_unit`, `value_without_unit`, `unrecognised_unit` | "A value is missing its unit, or uses a unit the app does not recognise." |
| `required_row_missing` | "This table is missing rows a <UK / Taiwan> label must show, such as <first missing row>." |
| `required_serving_declaration_missing` | "This Taiwan label needs its serving size and servings per pack lines." |
| `not_a_food_nutrition_panel` | "This looks like a supplement panel, which the app does not read." |
| `format_ambiguous`, `layout_not_supported` (section 5) | "The app could not tell which label layout this is. It reads UK and Taiwan layouts." |
| `text_too_long` | "This text is too long to be one nutrition table. Paste the table only." |

The gate's two "blocks ready" findings (`required_basis_missing`, `required_serving_declaration_missing`) are **declines** in the product. In the evaluation they stopped a ready mark; the product has no ready mark short of Log, so the only safe mapping is not to open Confirm.

### 3.2 What the user can do next

- **Edit the text** and read it again (the text and name stay in the fields).
- **Paste again** (clear and paste).
- **Use another route:** Search or Barcode from Add food, each a one-tap link under the reason.

A decline writes nothing to the ledger, keeps no copy of the text after the screen closes, and records nothing except, while the screen is open, the reason codes in Developer tools.

### 3.3 Partial tables and unknowns

- **Never silently completed.** No value is inferred, back-filled or converted to complete a table: no salt to sodium, no kJ to kcal, no % RI to an amount, no per-serving value to per 100 g (or the reverse), no value copied from the other column, no zero for a missing row.
- **Not printed means unknown.** A nutrient the label does not print is stored as `unknown(not_declared)` and reads "Not stated".
- **Printed but not used stays visible.** Salt, kJ beside kcal, reference-intake columns and unrecognised rows are listed on Confirm as read but not used, and kept in the stored evidence; they never become a ledger value.
- **kJ only:** when energy is printed only in kJ, energy is `unknown(missing_conversion)` and the kJ text is shown as not used (decision 6).
- **Salt only:** when a UK label prints salt and no sodium, sodium is `unknown(missing_conversion)` and salt is shown as not used (decision 6).
- **Bounds stay bounds.** `<0.1g`, `< 0.5 公克` and `less than 1g` are stored as bounded values with their printed comparator, never as an exact value or zero.
- **Mandatory rows** are enforced by the gate: a UK or Taiwan table missing a mandatory row declines (section 3.1), so a table that reaches Confirm has every mandatory row read. Any other row may be partial in the sense above, and stays unknown.

## 4. Arithmetic and consistency checks: warnings only

The frozen section 7 policy of the evaluation, ported to Swift with its own identifier (`label-arithmetic-checks-v1`, proposed), runs on every non-declined table:

- energy against macronutrients: `kcal ≈ 4P + 4C + 9F` (UK may also pass with `+ 2·fibre`); Taiwan, when fibre is printed, `kcal ≈ 4P + 4(C − fibre) + 2·fibre + 9F`; tolerance the larger of 15 kcal and 10% (UK, Taiwan) or 20 kcal and 20% (US, if enabled);
- `kJ / kcal` within 4.184 ± 2% when both are printed;
- per serving against per 100 × serving / 100, within printed rounding;
- sub-rows not exceeding their parent (saturates ≤ fat, sugars ≤ carbohydrate, Taiwan fibre ≤ carbohydrate);
- inputs that are bounds or unknowns make a check "not checkable", never zero and never a failure.

**Product rule (deliberately different from the evaluation):** in the evaluation a failed check blocked the route's ready mark. In the product a failure is a **non-blocking warning** on Confirm, for example "Energy does not match the fat, carbohydrate and protein shown. Check the label text." It never blocks Log, never authorises Log, never changes, fills or removes a value, and is not a `FoodLogRequirement`. A pass shows **nothing**: there is no "checked" or "verified" badge, because the check misses some errors (6 of 116 planted mutations, section 1) and must not be read as confirmation. The owner decides whether the failed mutation bar stands in the way of this (decision 2).

Warnings are not persisted as nutrition. The warning codes shown at Log are recorded in the manifest (section 6.1) as evidence of what the user saw.

## 5. Languages and layouts

| Language | Layout (gate format) | v1 |
|---|---|---|
| Traditional Chinese (`zh-Hant`) | Taiwan 營養標示 (`taiwan_nutrition_labelling`) | Supported. Untouched synthetic evidence |
| English | UK nutrition declaration (`uk_nutrition_declaration`) | Supported if the owner accepts development-only evidence plus the pre-release real-text check (decision 3) |
| English | US "Nutrition Facts" | Declines with `layout_not_supported` in v1 unless the owner chooses otherwise (decision 4) |
| Simplified Chinese, Japanese, Korean, every other language | none | Declines (`unsupported_language` or `unsupported_script`) |

**Format inference.** The evaluation declared each case's format from its corpus, never from route output. The product has no corpus, so the gate's format must be inferred, deterministically, from the candidate: `zh-Hant` resolves to Taiwan; English with a per 100 g or per 100 ml column resolves to UK; English without one resolves to US (declined in v1 unless decision 4 says otherwise); `mixed` or `unknown` language declines with `format_ambiguous`. This is a deviation from the evaluation method, so it gets its own test vectors (section 8.5) built from the frozen development and untouched cases with their declared formats, and inference must agree with the declared format on every one.

## 6. Data model

### 6.1 Evidence: a pasted-label manifest

A logged label is stored as one `CaptureEvidence` whose payload is a canonical, byte-exact **pasted-label manifest**, `pasted-nutrition-label-v1`, following the review manifest pattern ([review manifest v2](generic-food-review-manifest-v2.md), "Retention"):

| Field | Content |
|---|---|
| `version` | `pasted-nutrition-label-v1` |
| `pasted_text` | The exact text that was read, verbatim (decision 5) |
| `pasted_text_sha256` | SHA-256 of its UTF-8 bytes |
| `parser_version` | `nutrition-label-text-parser-v2` |
| `gate_version` | the Swift gate version (section 7) |
| `arithmetic_version` | `label-arithmetic-checks-v1` (proposed) |
| `label_format` | the inferred gate format |
| `candidate` | the `label-capture-candidate-v1` the reader produced: headers, cells (printed label, printed text, comparator, decimal text, unit, basis, parent), serving size, servings per pack, warnings |
| `stored_header_id` | the column whose values were stored (section 6.3) |
| `warnings_shown` | the warning codes on Confirm at Log |
| `name`, `brand` | as entered |

- Encoding: `FoundationCanonicalJSONEncoder` (sorted keys, unescaped slashes), the same as the review manifest. The bytes are stored verbatim as the `.text` payload and are never re-encoded from the struct after save.
- `CaptureEvidence`: `kind = .labelText` (existing), `captureMethod = "User pasted nutrition label"`, `captureMethodVersion = "pasted-nutrition-label-v1"`, `byteHash` = SHA-256 of the manifest bytes, `locale` as today.
- `SourceRelease`: `sourceID = "pasted-nutrition-label"`, `sourceReleaseID = "pasted-label:" + manifestHash`, `manifestHash`, `artifactHash = pasted_text_sha256`, `schemaVersion = "pasted-nutrition-label-v1:" + label_format`, `pipelineVersion = "<parser_version>:<gate_version>:<arithmetic_version>"`, `licence = "User-supplied label text; no redistribution licence inferred."`, `attribution = "Pasted nutrition label"`.
- Provenance on every stored nutrient: `source_kind = user_verified_panel` (existing; decision 7), `source_id = pasted-nutrition-label`, the release above, `evidence_id`, and `manifestReference = "manifest-sha256=…;header=…;row=…;literal=…"` naming the cell it came from. No transform is recorded because none is applied.
- `kind = .labelText` is already used by the reviewed web manifest. Lookups for each route discriminate by `release.sourceID` and `captureMethodVersion`, and a contract test proves neither route's verifier accepts the other's evidence (section 8.4).

**Verification at save and at reopen.** As for reviewed web proposals: the service checks the manifest digest, that the stored nutrients, units, bounds and basis equal the manifest's cells for `stored_header_id`, and that the pipeline is an admitted one; otherwise `invalidPastedLabelSource` before policy at save and `integrityFailure` at reopen. Verification compares against the stored manifest, **not** a re-parse, so a later parser version never invalidates an old entry. Developer tools can re-run the current parser on `pasted_text` and show any difference, for reproduction only.

### 6.2 Limits on the pasted text

- At most 8,000 characters (proposed); longer text declines `text_too_long` before parsing.
- Text is stored exactly as read: no trimming, normalisation or redaction after Read label. The user can edit it before reading.

### 6.3 Which column is stored

One resolution has one basis. The stored column is chosen by a fixed rule, never by the user's amount:

1. the per 100 g or per 100 ml column, when one is printed (UK always, Taiwan when 每100公克 or 每100毫升 is printed);
2. otherwise the per-serving column, with basis `perServing(serving quantity)`, only when the serving size prints a quantity and unit.

Values in the other column are kept in the manifest and shown as evidence. They are never merged into the stored column: a nutrient printed only in the other column stays unknown in the stored one. When both columns are printed and disagree beyond rounding, the scaling check warns (section 4).

### 6.4 Reuse: library food and favourites

- **Library food.** A first Log creates a local food with a `LibraryEntry` aliased by the entered name (and brand), as other exact saves do. Logging it again from search or recents reuses the stored product version and resolution; it does not re-read any text.
- **Favourite.** Only by the existing explicit favourite action after save ([food quick add v1](food-quick-add-contract-v1.md)); never automatic (decision 8).
- **Re-reading.** Pasting a new label for the same name creates a new evidence record and a new product version through the ordinary correction path; earlier entries keep their versions.

### 6.5 Confirmation v5 and the assertion grammar

- The policy stays `food_confirmation_v5`; `methodVersion` on new resolutions is `food_confirmation_v5`.
- A pasted-label save is a **plain exact save**: values are measured from the user's label text, the product identity is the user's named food, and it is not a generic estimate. It writes **no new assertion row**; the parser, gate and check versions live in the manifest. This keeps the persisted assertion grammar of v5 section 1 unchanged, so no new policy identifier is needed.
- Inline decisions, typed requirements, "When" and the amount rules apply unchanged. Which `DecisiveIdentity` facets a named packaged food carries, so that `sourceIdentityMissing` does not block a fully named label, is an implementation question for the architecture gate, settled before code with a contract test (section 8.4).
- The review manifest v2 contract is not amended. The pasted-label manifest is a sibling with the same retention and verification pattern.

### 6.6 Schema and archive version

The enum cases already exist (`CaptureKind.labelText`, `ProvenanceSourceKind.userVerifiedPanel`, `CapturePayload.text`), so no stored type gains a case. A version bump is still proposed (decision 9), because an older binary could decode a pasted-label entry but could not verify it, and would treat it as an unverifiable source:

- **Food contract 7**, migration identifier `food-ledger-v7`. `CanonicalFoodArchive.minimumContractVersion` returns 7 when any evidence has `captureMethodVersion == "pasted-nutrition-label-v1"`. A binary with this contract exports contract 7 only when such evidence exists; otherwise it keeps exporting the lowest contract its records need, as today.
- **SQLite migration `v7_pasted_label`:** metadata only (`schema_identity = food-ledger-v7`, `user_version = 7`). No immutable row is rewritten. A schema-6 opener throws `unknownSchema(7)`.
- **Existing records keep their bytes.** Every v1 to v6 record and archive decodes and re-encodes byte for byte (golden fixtures, section 8.4). The operation type stays `confirm_food_v1`, `confirm_food_v2` or `confirm_food_v3` as the save requires; no operation type is added.
- **Daily JSON:** unchanged. Food entries are not in the Daily JSON today; the pasted text and manifest never enter it.
- Release note: after updating, the app cannot be downgraded once a label is logged, and an archive with a logged label cannot be restored into an older build.

## 7. Privacy

**Fully on device. No egress. [`privacy-and-egress.md`](privacy-and-egress.md) and [`privacy-policy.txt`](privacy-policy.txt) do not change.**

- Reading uses only `NutritionLabelParsing` and the ported gate and checks, with no network, provider, model or OCR call.
- The pasted text is stored only in the local food ledger, inside the manifest of the entry it produced, under the existing rule that the food log stays local. It leaves the device only inside an inventory backup file the user explicitly exports, which that document already covers for the whole food log. It is never in Daily JSON, Copy all, Full Page or any report.
- Reading the clipboard happens only when the user pastes into the field (the system paste control); the app never reads the pasteboard on its own.
- No telemetry, analytics or automatic report of any kind (section 9).

## 8. Architecture gate

### 8.1 Responsibilities and layers

| Layer | Owns | Must not |
|---|---|---|
| **`NutritionLabelParsing`** (pure, Foundation only) | Parser v2 (unchanged); the Swift **decline gate** port with format inference; the Swift **arithmetic and consistency checks** port. Inputs are text and the injected hash string; output is `LabelCaptureCandidate` plus gate and check findings | Hash, read a clock, touch the ledger, know about Confirm |
| **Domain** (`FoodLedgerDomain`) | No change expected. Existing evidence, provenance and nutrient types | Depend on the parser |
| **Application** (`FoodLedgerApplication`) | A small consumer-owned port `PastedLabelReading` returning an application-owned reading (cells, basis, serving facts, decline reasons, warnings, versions); a `PastedLabelConfirmation` use case that builds the manifest, evidence, release and `PopulatedFoodConfirmation`; save and reopen verification; `minimumContractVersion` | Import `NutritionLabelParsing` types across the port (decision 10), format copy |
| **Adapter** (new target `FoodLabelTextCapture`, decision 10) | Implements `PastedLabelReading` with `NutritionLabelParsing`, mapping candidate and gate output to the application reading | Persist, decide, or present |
| **Infrastructure** (`FoodLedgerGRDB`, `FoodLedgerArchive`) | Migration `v7_pasted_label`; archive contract 7 | Interpret label text |
| **Presentation** (`FoodLedgerPresentation`) | Label text screen and view model; decline copy renderer; Confirm source section for pasted labels; warning copy | Parse, hash, or decide what is stored |
| **Composition root** | Registers the "Paste nutrition label" entry route and the adapter | Contain rules |

Hashing (SHA-256 of the text and the manifest) uses the injected digester, as `ReviewedFoodProposalConfirmation` does.

### 8.2 Dependency direction and `check-boundaries`

`FoodLabelTextCapture` → `FoodLedgerApplication`, `FoodLedgerDomain`, `NutritionLabelParsing`. `FoodLedgerApplication` does not depend on `NutritionLabelParsing`. `NutritionLabelParsing` keeps its Foundation-only allow-list. `Packages/FoodLedgerKit/Scripts/check-boundaries.sh` gains `check_imports FoodLabelTextCapture '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'`, and a check that no other target imports `NutritionLabelParsing` except the adapter, the CLI tool and its tests.

### 8.3 Invariants

1. The only save is the user's Log on Confirm. Reading, a gate pass, a check pass and the absence of a warning never save and never enable Log.
2. Every stored value is a printed cell of the stored column, bound by `manifestReference` to its printed label and text; no value is inferred, converted, copied from another column or defaulted.
3. Unknown is never zero; bounds stay bounds; "Not stated" is unknown.
4. Declines write nothing and retain nothing.
5. The gate and checks never change a value; checks never block or authorise Log.
6. Records are append-only and versioned; stored manifests are byte-exact and verified at save and reopen against themselves, not a re-parse.
7. No egress; the app never reads the pasteboard unprompted.
8. Only `en` (UK layout, and US if decision 4 allows) and `zh-Hant` (Taiwan layout) are read; everything else declines.
9. No medical classification, targets or interpretation in any copy.
10. Older records and archives decode and re-encode unchanged.

### 8.4 Contract tests (written first)

Parsing and gate (pure, `NutritionLabelParsingTests`):

1. **Gate port parity:** the Swift gate reproduces `decline_gate.py` (gate v2) on frozen vectors exported from every development and untouched pasted-text case, including the shared-variant code points (内 温 黄 …), supplement markers, missing mandatory rows and per 100 column checks.
2. **Arithmetic port parity:** the Swift checks reproduce `arithmetic.py` on the three frozen mutation families applied to the untouched truth, including the same 6 misses, the muesli example (367.2 kcal) and "not checkable" for bounds.
3. **Format inference** agrees with the declared format on every frozen case; `mixed` and `unknown` decline `format_ambiguous`.
4. **No inference:** kJ-only energy, salt-only sodium, % RI columns and one-column-only nutrients never produce a stored value.
5. **Determinism:** the same text gives byte-identical candidate and findings across runs and locales.

Application (`FoodLedgerApplicationTests`, `FoodLedgerContractTests`):

6. A non-declined reading yields a `PopulatedFoodConfirmation` whose every non-unknown nutrient cites a manifest cell of the stored column; no-other-column fill.
7. A declined reading yields no confirmation and writes no evidence.
8. A failed arithmetic check yields a warning and no `FoodLogRequirement`; Log enablement with and without the warning is identical.
9. Save verification: an altered value, unit, bound, basis or manifest byte fails `invalidPastedLabelSource` before policy; reopen fails `integrityFailure`.
10. **Cross-route isolation:** the reviewed web verifier rejects pasted-label evidence and the pasted-label verifier rejects reviewed web evidence, though both use `kind = .labelText`.
11. A pasted-label save writes no assertion and records `methodVersion = food_confirmation_v5`; a named label does not raise `sourceIdentityMissing`.
12. `minimumContractVersion` returns 7 with pasted-label evidence and is unchanged without it.
13. Golden fixtures: every existing v1 to v6 record and archive decodes and re-encodes byte for byte; a contract-7 archive round-trips byte for byte; a schema-6 opener throws `unknownSchema(7)`.
14. A logged label reused from search creates a new log item against the stored resolution and reads no text.

Presentation and UI:

15. View-model tests: Read label disabled states, each decline code maps to its copy, the text and name survive a decline and Edit label text.
16. Confirm shows every stored value beside its printed source text, the basis, serving size and servings per pack (or "Not stated"), and the read-but-not-used rows.
17. Simulator UI test: Add food → Paste nutrition label → read → Confirm → Log; and a declined paste → edit → read → Confirm.
18. Accessibility: VoiceOver reads each value with its source text; 44 pt targets; Dynamic Type at the largest size; warnings not conveyed by colour alone.

### 8.5 Extension axes

- **Photo routes.** A future on-device OCR (route B) or multimodal (route C) photo route produces the same `LabelCaptureCandidate`, runs the same gate and checks, and feeds the same Confirm source section with the image in place of the pasted text. Each needs its own contract; route C also needs a privacy and egress change and owner approval. Neither is authorised here.
- **Layouts.** A new layout (US, then others) is a new gate format with its own mandatory rows and test vectors, under a new gate version; the parser and Confirm do not change unless the layout needs new vocabulary (a new parser version).
- **Closed:** what counts as a stored value, unknown handling, the Log rule, provenance and the manifest's byte-exact retention.

## 9. Measuring real pasted text without collecting user data

Real pasted text is unmeasured, so v1 has a measurement plan that collects nothing from users automatically. **No telemetry.**

1. **Pre-release owner check (release gate, decision 11).** Before any user sees the route, the owner copies real labels from public pages (retailer product pages, manufacturer PDFs, Taiwan product pages) into the CLI `NutritionLabelTextParse` and on a device build. Each result is checked against its source. The texts stay outside the repository; the repository gets counts, page kinds and hashes only. Bar: zero wrong values in any non-declined table; declines and their reasons are reported, not gated. Any wrong value stops release and goes to a new parser or gate version.
2. **Owner-run local regression.** The owner's private real-text set is re-run against every new parser or gate version before it ships, with the same bar.
3. **Developer tools.** On the owner's own device, Developer tools show, for any logged label, the manifest, its versions, and a re-parse with the current parser with differences, so a reported misread can be reproduced locally.
4. **Opt-in "Report a misread" (deferred, decision 12).** A user-initiated action that builds a plain-text report (the text the user chooses to include, the versions, the parsed values and what the user says is wrong) for the user to copy or share themselves. It sends nothing on its own. It widens what the existing clipboard and share-sheet row carries, so it needs a one-line `privacy-and-egress.md` and `privacy-policy.txt` change; that is why it is not in v1.

## 10. Owner decisions

Each has one question and a recommendation.

1. **Entry point.** Should "Paste nutrition label" be its own row in Add food, rather than detected automatically inside "Paste or dictate"? *Recommendation: yes, its own row; one intent per journey, and no guessing what a paste is.*
2. **The failed mutation bar.** Should route A proceed to product although arithmetic mutation detection was 110/116, given that the check is warning-only and never authorises a save? *Recommendation: yes; the bar measures the shared check, the reader passed every bar, and the product shows no "checked" badge.*
3. **English at launch.** Should UK English labels ship in v1 on development-only evidence plus the pre-release real-text check, rather than waiting for untouched English evidence? *Recommendation: yes, but only if the pre-release check (decision 11) includes at least 20 real UK labels with zero wrong values; otherwise ship Taiwan first.*
4. **US layout.** Should US "Nutrition Facts" pastes decline in v1 until a US gate format with its own test vectors exists? *Recommendation: yes; gate v2 has no US mandatory rows, so it cannot decline a broken US table.*
5. **Pasted text or hash.** Should the manifest keep the pasted text verbatim, rather than only its hash? *Recommendation: verbatim; it is the evidence behind every value, it stays on device, and a hash alone cannot be reproduced or shown on Confirm or in Developer tools.*
6. **No conversion.** Should kJ-only energy and salt-only sodium stay unknown in v1, with the printed value shown as "not used", rather than converting? *Recommendation: yes; any conversion needs its own versioned transform contract.*
7. **Provenance kind.** Should label-sourced values use the existing `user_verified_panel` source kind (distinguished by `source_id = pasted-nutrition-label`), rather than a new kind? *Recommendation: yes; it matches "a user-entered or verified package declaration" and adds no enum case.*
8. **Reuse.** Should a logged label become a reusable library food under its entered name, with favouriting only by the existing explicit action? *Recommendation: yes.*
9. **Version bump.** Should a logged label move the store to food contract 7 and `food-ledger-v7`, so older builds refuse rather than misread it? *Recommendation: yes, metadata-only migration, no rows rewritten.*
10. **Adapter target.** Should the parser reach the application through a new adapter target `FoodLabelTextCapture` behind an application-owned port, rather than the application importing `NutritionLabelParsing` directly? *Recommendation: yes; it keeps the parser replaceable by a photo route and keeps parser types out of the application.*
11. **Pre-release check size.** Should the release gate be at least 20 real public labels per shipped language, with zero wrong values in non-declined tables? *Recommendation: yes.*
12. **Report a misread.** Should the opt-in "Report a misread" wait for its own small contract and privacy update, leaving v1 with owner-run checks only? *Recommendation: yes; v1 then changes no privacy text.*

## 11. Not changing

- `food_confirmation_v5`, its requirements and its assertion grammar; the review manifest v2; parser v2; the evaluation and its frozen artefacts.
- `privacy-and-egress.md` and `privacy-policy.txt`.
- HealthKit (read-only); the Health report, Copy all and Daily JSON.
- Photo capture of any kind (#93's photo route stays unpromoted).
