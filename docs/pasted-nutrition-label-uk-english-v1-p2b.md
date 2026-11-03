# Pasted nutrition label, UK English v1: P2b seam and energy labels spec (#371)

Status: **revision 2, 3 November 2026: architecture gate PASS WITH CHANGES on revision 1, all eight changes applied (section 6).** The second half of phase P2 of [the UK English plan](pasted-nutrition-label-uk-english-v1.md), after [P2a](pasted-nutrition-label-uk-english-v1-p2.md). It lands before any P3 work. Decision 11 was settled by the owner on 3 November 2026 as **allowed** (plan section 8.2); P2b changes nothing for it, and P3's test 10 pins it.

## 1. The reader seam (plan decision 8, a named re-pin)

Today `PastedLabelReader.classify` and `PastedLabelConfirmation` read the constant `PastedLabelLaunchScope.enabledFormats`, and `classify` reads identity v1 (`PastedLabelBasisState.isAsSold`) directly. Neither can be injected, so P4's debug-only device step and the development harness cannot use the UK scope through the product types. P2b changes that as follows.

| Change | File | Pinned |
|---|---|---|
| `PastedLabelLaunchScope` moves, unchanged, to its own file | `LabelReading.swift` to new `PastedLabelLaunchScope.swift` | `LabelReading.swift` re-pinned |
| `PastedLabelReader` gains a `PastedLabelReadingPolicy`. `init(reader:digester:policy:)` defaults to `.product`. The instance `read` and a new `classify(_:pastedText:policy:)` use the policy; the existing static `classify(_:pastedText:)` keeps its signature as a compatibility wrapper calling it with `.product` | `LabelReading.swift` | re-pinned |
| `PastedLabelConfirmation` takes a policy (default `.product`), records its launch scope in new manifests (`launch_scope`), and **throws** for any policy whose identity is not v1, since manifests record identity v1 and identity v2 has no manifest contract before P5 | `PastedLabelConfirmation.swift` | re-pinned |

**The policy is a closed set**, in the new unpinned file beside the scope. It is an `Equatable` value with no public memberwise initialiser, and exactly two members:

- `.product`: the scope `["taiwan_nutrition_labelling"]` and identity v1. This is today's behaviour.
- `.ukDevelopment`: the scope `["taiwan_nutrition_labelling", "uk_nutrition_declaration"]` and identity v2. It is used by the development harness, and later by P4's debug switch.

Identity is a closed enum `{ v1, v2 }` that maps to `PastedLabelBasisState` or `PastedLabelBasisStateV2`, not a closure. So a scope admitting UK cannot pair with identity v1, which would accept UK as-prepared tables as the food as sold. Nothing at the composition root changes before P4; P4's `#if DEBUG` switch is its own PR. `PastedLabelText.supportedLayouts` (decline copy) and `LabelPhotoReading.launchScope` stay on the constants, on purpose: copy follows the shipped scope (P4 notes the debug case), and the photo route keeps its own scope (decision 6).

**Why identity joins the decision 8 seam.** Decision 8 approved a launch-scope seam. Admitting UK under identity v1 would accept UK as-prepared headers (`with milk`, `cooked`, `+`) as the food as sold, so the scope and the identity rule must change together. The closed policy is the smallest seam that keeps them together, and its default is today's behaviour byte for byte. This is recorded in the re-pin entry, and reported to the owner in the PR.

**Recorded under "Re-pins after the freeze"** (reader v3 section 12.1), as decision 8 approved. Pins 1 and 2 are unchanged. With the default policy, the reader's behaviour is byte-identical, which test S1 shows.

**The P1 development copy goes, after serving as the reference.** S1 needs a reference the seam does not touch, and `UKDevelopmentReader` is that reference. The PR therefore has two commits:

1. The first adds the seam and runs the copy's product-configuration parity test against `PastedLabelReader(policy: .product)`, over every fixture in ordinary and basis-choice reads. The run is recorded in the PR.
2. The second deletes the copy and moves its tests onto the seam:
   - `testProductScopeMatchesThePastedLabelReaderOnEveryFixture` becomes S1, which is retired with the copy, its result recorded;
   - `testUKScopeRemovesOnlyTheScopeDeclineFromUKTables` becomes S2;
   - `testSyntheticUKDeclarationReachesConfirmUnderTheUKScope` and `testUSPanelStillDeclinesUnderTheUKScope` run on `.ukDevelopment`;
   - `UKDevelopmentSet.run` and `UKDevelopmentStepTests` use `PastedLabelReader(reader: UKEnglishLabelTextReader(), digester:, policy: .ukDevelopment)`.

## 2. Energy labels (`nutrition-label-text-parser-uk-v2`)

On the P2a re-run, an energy row printed `Energy kJ` or `Energy kcal`, with the unit repeated in every cell (`Energy kJ  347 kJ`), is unrecognised by parser v3. Its correct value was bound only to an unrecognised row (six of the ten scored artefacts), and a title line above it was merged into its label. The same row without the label unit reads correctly. So:

- **N5 redundant energy label unit.** N5 fires only when all of these hold:
  - (a) the line's label, with one trailing bare unit token removed (and an optional `:`), equals an entry of `UKVocabulary.energyLabels` exactly, so no digits and no basis phrase (`Energy per 100g kJ` is unchanged);
  - (b) the removed token is one of `kJ`, `kj`, `KJ`, `Kj`, `kcal`, `Kcal`, `KCAL`, `kCal`;
  - (c) the line holds at least one value, and **every** value carries a unit whose canonical unit, under parser v3's map (`kJ`, `kcal`, `cal` distinct), equals the label token's;
  - (d) values are separated only by spaces, tabs or `|`, with nothing after the last.

  Then the label's unit token is removed. Any other line is unchanged; such a line then meets N2 or G2 as before. N2 needs every value bare and N5 needs every value to carry a unit, so the two cannot both match. Rule order: N4, then at most one of N1, N2, N3, N5.

This changes a rule, so the parser version becomes `nutrition-label-text-parser-uk-v2`. Version 1 was never admitted to any manifest or stored reading (nothing UK is stored before P5), and no build ships it. It is retired, not kept beside v2, and the P3 freeze pins v2.

Not done: the bracketed `(kcal)` continuation row (two artefacts) and the bracketed sub-row with a bracketed value (two). Their values are correct and bound only to unrecognised rows. Rules for them would be judgement calls on very few labels, so they stay artefacts for the P3 UK scorer to handle.

## 3. Invariants

As P2a section 5, and:

- With the default policy, `PastedLabelReader`, `classify` and `PastedLabelConfirmation` behave exactly as today on every fixture, parity case and manifest golden.
- Stored manifests are untouched: the confirmation records the same `launch_scope` bytes under the default policy.
- N5 adds no number, unit or comparator; it only removes a label unit that every value on the line repeats.

## 4. Contract tests

1. **S1, default equality against an independent reference.** The pre-seam copy, run once in the first commit (section 1), covers every synthetic fixture, unheaded fixture, Taiwan probe text and frozen parity case, in ordinary and basis-choice reads. The existing contract and presentation suites also run unchanged.
2. **S2, the UK policy's exact effect,** per fixture, including basis-choice reads:
   - UK-policy codes = product codes − `layout_not_supported` (UK format only) + `basis_state_not_supported` exactly when identity v2 marks a header that v1 does not;
   - a usable product reading never changes;
   - at least one UK fixture becomes usable.
3. **Policy closure.**
   - Every policy admitting `uk_nutrition_declaration` uses identity v2.
   - `.product` is `["taiwan_nutrition_labelling"]` with v1.
   - The UK scope string equals `LabelFormatInference.Outcome.uk.rawValue`.
4. **S3, manifests.**
   - Under `.product`, the v1 and v2 manifest goldens are byte-identical, including `launch_scope`.
   - Under `.ukDevelopment`, the confirmation throws and builds no manifest, both for identity v2 and because the UK pipeline is not admitted. No UK manifest exists before P5.
5. **Reopen unchanged.** Existing stored manifests decode, re-encode and verify unchanged.
6. **N5 positive cases:**
   - `Energy kJ  1520 kJ  456 kJ`;
   - `Energy kcal: 362 kcal`;
   - `Energy kJ: 328 kJ`, moved from P2a's list of unchanged lines;
   - `Typical values Energy kJ 1520 kJ` (N4 splits, then N5).
7. **N5 lines left unchanged:**
   - `Energy kJ 1520` (N2's case);
   - `Energy kJ 1520 kcal`, `Energy kJ 1520kJ 18%`, `Energy kJ / kcal 1069kJ / 254kcal`;
   - `Energy kJ 1520 kJ 362 kcal`, `Energy kcal 1520 kJ`, `Energy kJ 1520 kJ 362`;
   - `Energy per 100g kJ 1520 kJ`, `Energy kJ 1520 kJ Energy kJ 456 kJ`, `Energy kJ kcal 1520 kJ`;
   - `Protein g 8g`, and Taiwan and mixed-script lines.
8. **N5 binding.**
   - `Energy kJ 1520 kJ` then `362 kcal` gives kJ 1520, with kcal correct or unread and never bound as kJ.
   - `Energy kJ 1,520 kJ` never gives 1.52.
   - A reference intake column keeps the `reference_intake` basis.
9. **Normaliser properties,** extended to N5:
   - no digit run, decimal separator or comparator is added, dropped or changed;
   - the output's tokens are a subset of the input's;
   - a line N5 rejects comes back byte for byte.
10. **Freeze.** `ReaderV3FreezeTests` passes with exactly the two named re-pins. Pins 1 and 2 are unchanged, and the new `PastedLabelLaunchScope.swift` is unpinned.
11. **Development set.** The re-run through the seam keeps **zero wrong values from a real misbinding**, and the artefact count is reported.

## 5. Questions for the gate

- **Q1.** Is the policy (scope plus identity rule) the right seam, or should identity stay outside the reader until P5?
- **Q2.** Is retiring the never-admitted UK v1, rather than keeping it beside v2, acceptable before the P3 freeze?

The gate answered: Q1 yes, identity in the reader policy, kept out of the confirmation and manifest until P5; Q2 yes. The doc comments naming v1 move to v2, and the P2a spec notes that its re-run results were under v1.

## 6. Gate findings map (revision 1)

1 S1 reference, section 1 (two commits) and test 1; 2 confirmation refuses non-v1 identity, section 1 and test 4; 3 S3 restated, test 4; 4 closed policy with an identity enum, section 1 and test 3; 5 exact S2 and named test migration, section 1 and test 2; 6 N5 tightened, section 2; 7 `Energy kJ: 328 kJ` moved, test 6; 8 why identity joins the seam, section 1.
