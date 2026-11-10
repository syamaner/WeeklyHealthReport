# Nutrition label entry v1 (#454)

Status: **design spec and architecture gate, revision 3, 10 November 2026. Documents only; no production code.**
- Q1 to Q3 were decided by the owner on 10 November 2026 (section 9).
- The architecture gate returned PASS WITH CHANGES on revision 1 (12 changes) and on revision 2 (N1 to N6). All are applied here, with their sections listed in section 11.
- **The gate passed revision 3 on 10 November 2026.** Its one optional note, the DEBUG seam's loading event and gate, is applied in 6.2 test 10.

## 1. Purpose

Add food has two rows for one intent:
- "Paste nutrition label": the offline pasted-label reader v3, released under #93.
- "Photo of nutrition label": the AI label photo route, #316, built and qualified but off for users.

This spec replaces them with one **Nutrition label** entry. It offers three choices: take a photo, choose a photo or screenshot, or paste. Paste looks at what the clipboard holds:
- **an image** goes to the label photo route (crop, then Read label with AI);
- **text** goes to the pasted-label reader, on device.

A fourth choice, **Type or paste text**, opens the text screen empty, as the old row did. Every path still ends on the shared Confirm screen with one Log action. Nothing about reading, checking, saving or the stored records changes.

## 2. Owner direction (10 November 2026)

The owner asked whether pasting text could be retired in favour of pasting screenshots. The agreed direction keeps the text reader inside the combined entry, because:
- it needs no key, no network and no spend;
- the photo route has a daily cap of 30 reads;
- the pasted records already logged must keep decoding.

Pasting an image becomes a first-class input. UK label photos are out of scope here (section 8).

## 3. Journey

### 3.1 Add food

One row, **Nutrition label** (identifier `addFood.nutritionLabel`), replaces both label rows. Its subtitle depends only on the photo route's mode (`labelPhotoMode != .off`), never on its blockers, which are only known asynchronously:
- **Mode not off:** "Photo, screenshot or pasted text. Photos: Taiwan labels (營養標示), read by AI; you check every value."
- **Mode off (every Release build today):** "Paste or type the label text. Read on this device."

The row is always shown, because text entry is always available. The unavailable row in `Favourites.swift` ("Photo of nutrition label") is renamed "Nutrition label" so the two lists agree.

### 3.2 The Nutrition label screen

A native grouped list with up to two sections.

1. **Photo or screenshot.** Shown only when the mode is not off.
   - The existing `LabelPhotoSourceButtons`, unchanged. Their labels stay "Take photo" and "Choose from library". Screenshots arrive through the library, as P2 already says. Take photo is absent where there is no camera.
   - Footer: "Taiwan labels only. The part you crop is sent to OpenRouter to be read. Nothing else is sent."
2. **Paste.**
   - **Paste:** the system paste control (3.3).
   - **Type or paste text:** a plain row, always enabled. It opens the pasted-label screen empty, exactly as "Paste nutrition label" did, and reads nothing from the clipboard.
   - Footer, mode not off: "Paste a screenshot of a label, or its text. Text is read on this device."
   - Footer, mode off: "Paste the label text. Reading label photos is not available in this version."

### 3.3 What Paste does

**The control.** `PasteButton(supportedContentTypes:payloadAction:)`, which delivers `[NSItemProvider]`. A single-`Transferable` `payloadType:` form delivers only one representation and cannot tell "both" apart, so it is not used.
- **Mode not off:** the supported types are `[.image, .plainText]`.
- **Mode off:** the supported types are `[.plainText]` only, so image bytes are never requested or loaded.

The system enables the control only when the clipboard holds a supported type, and iOS shows no paste permission prompt for it. The app reads the clipboard only when the control is tapped.

**Loading.** Items load asynchronously.
- **While loading:** "Reading the clipboard…" is shown, and Paste and Type or paste text are disabled.
- **On leaving the screen:** the load is cancelled.
- **When it fails:** an image that cannot be loaded or decoded shows "The pasted image could not be opened. Nothing was sent." Neither route is called automatically. If usable text was also on the clipboard, the same message is followed by the one button "Read the text on this device".
- **Holding the payload:** the loaded image and text are kept in memory in the entry model only until they are routed.
  - When the user picks one option in the "Both" choice, or in the failed-image case, the other payload is dropped.
  - When the user leaves the screen, or the app goes to the background, both are dropped and nothing is routed.
  - Nothing loaded from the clipboard is written to disk by the entry.

**Classification.** After loading, a pure classifier `NutritionLabelPasteKind.classify(hasImage:hasText:)` decides from what was loaded, never from what it says:
- `hasImage` means at least one provider's image representation loaded into data.
- `hasText` means the first plain-text item is not empty once whitespace is trimmed. The trim is only for this test.

| After loading | Result |
|---|---|
| An image, no usable text | The image goes to the photo route (3.5) |
| Usable text, no image | The text goes to the pasted-label screen (3.5) |
| Both | A choice: "Read the image with AI" or "Read the text on this device" (Q2, decided: ask) |
| Neither | Inline: "The clipboard has no label image or text." |

An image with only whitespace text counts as an image.

### 3.4 Photo route availability

The entry screen does not work out blockers. A pasted image always goes to `LabelPhotoScreenModel.choose(_:)` (3.5), and the photo screen then shows whatever blocker applies, with its existing `Blocker.text` and `action`, as it does for a chosen photo today. That covers all six cases: `noKey`, `keyNotValidated`, `offline`, `dailyLimit`, `paused` and `routeUnavailable`. It also covers the moment before `refresh()` has finished, when no blocker is shown yet and Read cannot be tapped until the crop is used.

| Photo route mode | Photo section | Pasted image | Pasted or typed text |
|---|---|---|---|
| Off | Hidden | Never requested (3.3) | Works |
| Fake or live, any blocker or none | Shown | Opens the crop step; the photo screen shows the blocker | Works |

**The photo screen's paste actions are unchanged.** `LabelPhotoText.pasteLabel` ("Paste nutrition label") drives two buttons: the offline blocker's action, and the button shown after a decline or failure (`LabelPhotoScreenView.swift:81, 125`; label photo spec copy rows at lines 177 and 195). Both keep their copy, and they still open the pasted-label screen empty, which is the same target as Type or paste text. The pasted-label screen keeps its title, "Paste nutrition label", and that title matches these buttons.

**Retake.** For a pasted image, Retake on the photo screen offers camera and library but not Paste. This is accepted for v1: to paste a different image, the user goes back one screen.

### 3.5 After routing

**A pasted image** enters through the same `LabelPhotoScreenModel` instance the photo screen uses. There is one per entry visit, built by `root.labelPhotoScreenModel()`:
- `LabelPhotoFlowView` gains an initialiser that takes this injected model, in place of building its own (`FoodLedgerCompositionRoot.swift:1764-1767`).
- The entry screen pushes the photo screen with the pasted image held as a one-shot pending input.
- The photo screen calls `choose(_:)` with it once, after it has appeared, so the crop cover is presented once, from the screen it is attached to.
- `choose(_:)` only opens the crop step. Cancel crop returns to the photo screen.
- The source buttons on the entry screen use the same path: model, push, then `choose(_:)` after the screen appears.

Nothing else changes:
- preparation P3 to P9 at `useCrop`;
- the blockers and caps in `canRead` and `blocker`;
- the first-use consent at `readTapped` and `firstUseAccepted`;
- the request, attention items and Confirm.

There is no second path into the photo route. The image is prepared from its pixels, so its metadata is removed (E3), and it is kept on device only under the existing photo storage rule.

**Pasted text** goes to the pasted-label screen as an optional initial value of `PastedLabelTextViewModel.text`, passed at the point where `PastedLabelFlowView` builds the model. The `String` is the clipboard text **byte for byte**: no trim, normalisation or truncation. The text screen still enforces its own rules:
- the 8,000-scalar limit, through `isTooLong`;
- `canRead`;
- reader v3's parse, declines, basis choice and manifest.

A text over the limit reaches the screen and is blocked there, as if it had been pasted into the field.

## 4. Egress and contract amendments

Unchanged in destination, payload and conditions:
- **E1:** the OpenRouter chat endpoint only.
- **E2:** one prepared JPEG, the fixed instruction and the fixed schema.
- **E3:** cropped by the user and re-encoded with every metadata block removed.
- **E10:** the daily caps.

The approved photo spec does name its image sources:
- **P2:** "Camera, photo library and screenshots (screenshots arrive through the library)".
- **P1:** a separate Add food row beside Paste nutrition label.

The clipboard is therefore a new source, approved by the owner as Q1. The same PR amends three contracts, each with a dated amendment citing Q1 to Q3 of this spec:
- **`docs/label-photo-ai-prefill-v1.md`:**
  - P1: the photo route is reached from the combined Nutrition label entry;
  - P2: adds "an image pasted with the system paste control on the Nutrition label screen, only when tapped".
- **`docs/pasted-nutrition-label-v1.md`:** section 7 (the clipboard is read "only when the user pastes into the field") and invariant 12 ("not read from the pasteboard by the app"). Both also allow the system paste control on the Nutrition label screen. They keep two rules: the clipboard is never read unprompted, and the text is never kept outside a logged entry's manifest.
- **`docs/privacy-and-egress.md`:** the label photo rows name camera, photo library or a pasted image as sources. The clipboard-as-destination row (Copy all) stays separate, so the clipboard is never presented as egress.

In the same PR, `docs/privacy-policy.txt` says the label photo may be one you took, chose or pasted. Pasted text never leaves the device, as today.

## 5. Records and compatibility

- **No schema change.** Saved entries keep their existing sources: pasted text keeps the pasted-label source (`pasted_text`) and its manifest, and photo reads keep `label-photo-ai-v1`.
- **No change to route identities:** reader v3, photo route v2 (`LabelPhotoRoute.v2US`), the decline gate, conversions or arithmetic checks.
- Stored records, archives and exports decode and re-encode unchanged. A test decodes the existing pasted and photo fixtures after the change.

## 6. Architecture gate

**Responsibilities:**
- **Presentation (`FoodLedgerPresentation`)**, new files named `NutritionLabel*` so the `PastedLabel*` file-count test is unaffected:
  - `NutritionLabelPasteKind`, the pure classifier, with no explicit `import Foundation`;
  - `NutritionLabelEntryText`, the copy of section 7;
  - `NutritionLabelEntryModel`, holding the mode, the paste state (idle, loading, failed, both, nothing) and the routing callbacks;
  - `NutritionLabelEntryView`, the screen.
  The view gets the paste control through a consumer-owned port that uses presentation-owned types only:
  - `NutritionLabelControlFactory.pasteControl(acceptsImages: Bool, events: @escaping (NutritionLabelPasteEvent) -> Void) -> AnyView`;
  - `NutritionLabelPasteEvent` is `.loading`, `.loaded(imageData: Data?, text: String?)` or `.failed(text: String?)`.

  No `UTType`, `NSItemProvider` or FoodLabelPhotoUI type crosses into presentation. The photo source buttons come from the existing `LabelPhotoViewFactory.sourceButtons` (`LabelPhotoViews.swift:44`), used only when the mode is not off. In off mode the entry model hides the photo section from the mode, and no factory is asked for source buttons.
- **Photo UI (`FoodLabelPhotoUI`):**
  - one new file, `LabelPastePicker.swift`, the only package source that uses `PasteButton`, `NSItemProvider` or `UIPasteboard`. The app target's existing clipboard writes, such as Copy all (`DailyExportView.swift:89`, `HealthReportView.swift:224`), are unaffected.
    - It turns `acceptsImages` into `UTType`s.
    - It loads the providers into image `Data` and `String`, and emits the events.
    - It owns its load task and cancels it when it disappears.
  - `LabelPhotoSourceButtons`, unchanged.
- **Composition root:**
  - `AppNutritionLabelControls`, the implementation of `NutritionLabelControlFactory`. It is built in **every** mode, off included, because the Paste section always shows. In off mode it is called with `acceptsImages: false`.
  - One `nutritionLabel` entry route replaces the `pasteLabel` and `photoLabel` parameters of `AddFoodView`.
  - A pasted image is wired to `labelPhotoScreenModel()`'s `choose(_:)`. That function stays nil when off, and off never requests images.
  - Pasted or empty text is wired to `PastedLabelFlowView` with its optional initial text.

**Boundary script (`check-boundaries.sh`):**
- **FoodLabelPhotoUI allow-list:** add `UniformTypeIdentifiers`.
- **New rule:** it scans `Packages/FoodLedgerKit/Sources` only. There, `PasteButton`, `NSItemProvider` and `UIPasteboard` may appear only in `Sources/FoodLabelPhotoUI/LabelPastePicker.swift`, and `UTType`, `UniformTypeIdentifiers` and `NSItemProvider` never in FoodLedgerPresentation.
- **Self-test:** seeded-violation cases for both parts of the rule, plus a check that the app target's existing clipboard writes are not flagged.
- No new target.

**Dependency direction:** presentation calls application ports and its own consumer-owned port; adapters are wired only at the composition root. No domain or application file changes.

**Invariants:**
- one journey per intent, ending on the shared Confirm;
- no automatic reading, sending or saving;
- the clipboard is read only on a tap of the system paste control, and an empty text entry reads nothing;
- in off mode an image is never requested;
- a pasted image has exactly one path into the photo route (`choose(_:)`);
- pasted text is routed byte for byte;
- egress unchanged apart from the approved source (section 4);
- records unchanged (section 5).

**Extension axis:** the entry route. A later input, such as a UK photo format (section 8), plugs into the same screen without touching either reader.

### 6.1 Tests that change

| Test | Change |
|---|---|
| `WeeklyHealthReportTests/PastedLabelRouteTests.swift` (the `pasteLabel` initialiser, Mirror path and `addFoodRow == "Paste nutrition label"`) | Replaced by a `nutritionLabel` route test and the new row copy |
| `LabelPhotoPresentationTests.swift` (the offline action copy) | Unchanged: the copy stays "Paste nutrition label" (3.4) |
| `PastedLabelPresentationTests.swift` (exactly 4 `PastedLabel*` files, `UIPasteboard` banned in them) | Count kept; the ban is extended to every `NutritionLabel*` presentation file |
| `LabelPhotoCompositionTests.swift` (`labelPhotoEnabled`, `labelPhotoScreenModel()`) | Kept; adds the off-mode factory and the single route |
| `AddFoodView` identifier `addFood.photoLabel` | Replaced by `addFood.nutritionLabel` |

### 6.2 Contract tests to add

1. **Classifier:**
   - image only, text only, both, neither;
   - whitespace-only text counts as no text;
   - an image with whitespace text gives image.
2. **Entry model:**
   - off and not-off give their sections, footers and subtitle;
   - off requests `.plainText` only;
   - the Taiwan scope appears in the not-off copy.
3. **Paste states:**
   - loading disables Paste and Type or paste text;
   - a failed image load shows its copy and calls neither route;
   - a failed image load with usable text offers only "Read the text on this device";
   - leaving cancels the load;
   - in the "Both" and failed-image states, choosing one option drops the other payload;
   - leaving the screen, or going to the background, drops both and routes nothing.
4. **Image routing:**
   - a pasted image reaches `choose(_:)` and nothing else, after which `prepared == nil`, `cropping == true`, and `canRead == false` until `useCrop`;
   - without consent, `readTapped` shows the first-use sheet and the scripted transport records zero requests;
   - with each of the six blockers set, Read stays disabled.
5. **Text routing:**
   - pasted text equals `model.text` byte for byte, including leading and trailing whitespace;
   - a text over 8,000 scalars reaches the screen and is blocked by `isTooLong`;
   - a reader v3 read of pasted text gives the same manifest as the same text typed in.
6. **Empty entry:** Type or paste text opens the screen empty, with no clipboard read.
7. **Boundary script:**
   - the seeded `PasteButton`, `NSItemProvider` and `UIPasteboard` violations outside `LabelPastePicker.swift` are caught;
   - a seeded `UTType` or `NSItemProvider` in FoodLedgerPresentation is caught;
   - the app target's clipboard writes are not flagged.
8. **Composition:**
   - the control factory exists when off;
   - the injected `LabelPhotoScreenModel` reaches `LabelPhotoFlowView` unchanged, and the paste path and the source-button path use the same instance;
   - a pending image is consumed once, after the photo screen appears, so the crop opens exactly once and Cancel crop returns to the photo screen;
   - `labelPhotoScreenModel()` is still nil when off;
   - `AddFoodView` has one `nutritionLabel` route and no `pasteLabel` or `photoLabel` parameters.
9. **Compatibility:** the existing `pasted_text` and `label-photo-ai-v1` fixtures decode and re-encode unchanged.
10. **Journey (journey-qa, fake route, synthetic images only):**
    - Add food, then Nutrition label;
    - paste text, then Confirm;
    - paste an image, crop, read, then Confirm;
    - both kinds on the clipboard: the choice appears;
    - offline and no key: a pasted image reaches the blocker, and text works;
    - Type or paste text with an empty clipboard;
    - default size and AX5, VoiceOver labels, 44 pt targets;
    - check that "Paste or dictate a list" and "Nutrition label" read as distinct.
    How the clipboard is seeded:
    - **Text:** `xcrun simctl pbcopy`.
    - **An image, through the real paste control:**
      1. Write a synthetic label JPEG from `LabelPhotoSyntheticRenderer` to a file.
      2. Add it to the simulator with `xcrun simctl addmedia`.
      3. Copy it from Photos in the simulator.
    - **Both:** copy the image, then append the text with the system share or copy actions if they keep both. Otherwise use the DEBUG-only seam below.
    - **DEBUG-only seam:** `-LabelPasteSample image|text|both|brokenImage`, honoured only in fake mode and compiled out of Release, like `LabelPhotoRouteMode.live` (`FoodLedgerCompositionRoot.swift:1559-1563`). With it, `LabelPastePicker` emits `.loading` first and then the synthetic payload, instead of reading the clipboard, so the loading state is covered too. It covers the "Both" and failed-image states. Its gate is the same `#if DEBUG` and fake-mode condition as `labelPhotoSample` (`FoodLedgerCompositionRoot.swift:1714-1717`), so a live DEBUG build never emits a synthetic payload.

    The QA report records which method each step used.

## 7. Copy

| Place | Copy |
|---|---|
| Add food row | Nutrition label |
| Row subtitle, mode not off | Photo, screenshot or pasted text. Photos: Taiwan labels (營養標示), read by AI; you check every value. |
| Row subtitle, mode off | Paste or type the label text. Read on this device. |
| Photo section footer | Taiwan labels only. The part you crop is sent to OpenRouter to be read. Nothing else is sent. |
| Paste section footer, mode not off | Paste a screenshot of a label, or its text. Text is read on this device. |
| Paste section footer, mode off | Paste the label text. Reading label photos is not available in this version. |
| Empty text row | Type or paste text |
| Loading | Reading the clipboard… |
| Image could not be loaded | The pasted image could not be opened. Nothing was sent. |
| Image failed, text present | Read the text on this device |
| Both on clipboard | Read the image with AI / Read the text on this device |
| Nothing usable | The clipboard has no label image or text. |
| Photo screen offline action and post-decline button | Paste nutrition label (unchanged) |

A UK photo is still declined after reading, with the existing message.

## 8. Not in this spec: UK label photos

The evaluation deferred the UK sealed photo set until Taiwan results justified it. E13 has now passed. On 39 exposed UK development photos, Gemini 4 Argon got 299 of 311 cells exactly right, and 18 of 22 usable tables fully right (#255 phase 4, section 8). That is development evidence only.

On 10 November 2026 a sealed set of UK Open Food Facts photos was collected, outside the repository: 20 development and 40 sealed. It has no ground truth yet. A UK version needs:
- a version 2 of the photo route contract, with a UK launch scope;
- ground truth checked by the owner;
- one qualification run like E13.

That will be its own issue.

## 9. Owner questions

- **Q1. Clipboard as an image source.** Allow a pasted image into the label photo route under the approved terms E1 to E16 unchanged, with the contract and policy wording of section 4? *Recommend: approve.* **Approved by the owner, 10 November 2026 ("Yes, approve Q1").**
- **Q2. Both image and text on the clipboard.** Ask the user, or always prefer the image? *Recommend: ask.* Copying from a web page can carry both, and only the user knows which one they meant. **Decided by the owner, 10 November 2026: ask.**
- **Q3. Release builds while the photo route is off.** Rename the row to "Nutrition label" now, or keep "Paste nutrition label" until the photo route is turned on? *Recommend: rename now.* It is the same journey, and the change ships once instead of twice. **Decided by the owner, 10 November 2026: rename now.** Revision 2 keeps the old row's empty text entry as Type or paste text, so a Release build loses no capability.

## 10. Phasing

One PR, once this revision passes the gate:
- the code and tests of section 6;
- the three contract amendments and the policy wording of section 4;
- the ledger row.

The photo route stays off for users until the owner's device check and decision (#316). This entry does not turn it on.

## 11. Gate changes applied

Revision 3, from the gate on revision 2:

| Gate item | Where |
|---|---|
| N1. A port in presentation-owned types (`NutritionLabelPasteEvent`); the photo section hidden by mode | Section 6, Responsibilities; boundary rule |
| N2. `LabelPhotoFlowView` takes the injected model; `choose(_:)` once, after the push | 3.5; 6.2 test 8 |
| N3. Both photo screen paste buttons keep their copy | 3.4; 6.1; section 7 |
| N4. The clipboard rule scoped to package sources | Section 6; 6.2 test 7 |
| N5. Image failed with text present; payloads dropped on choosing, leaving or going to the background | 3.3; 6.2 test 3 |
| N6. Working image seeding, plus a DEBUG-only seam | 6.2 test 10 |

Revision 2, from the gate on revision 1:

| Gate item | Where |
|---|---|
| 1. Factory port, built in off mode too | Section 6, Responsibilities |
| 2. `PasteButton(supportedContentTypes:payloadAction:)`, `UniformTypeIdentifiers`, one-file clipboard rule | 3.3, section 6 |
| 3. All six blockers from the same model instance; pending status | 3.4, 3.5 |
| 4. Subtitle keyed on mode; Taiwan scope kept | 3.1, section 7 |
| 5. P1 and P2 amendment; the corrected sentence | Section 4 |
| 6. Pasted-label section 7 and invariant 12 amendment | Section 4 |
| 7. Text byte for byte; the limit enforced by the text screen | 3.5, 6.2 test 5 |
| 8. Tests that change | 6.1 |
| 9. The empty Type or paste text entry; "Neither" after loading | 3.2, 3.3 |
| 10. Loading and failed states, cancellation | 3.3, 6.2 test 3 |
| 11. Source button labels unchanged | 3.2 |
| 12. Off mode requests text only | 3.3, 6.2 test 2 |
