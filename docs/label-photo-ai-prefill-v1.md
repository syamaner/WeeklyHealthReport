# Label photo AI pre-fill v1 (#316)

Status: **design spec, egress amendment and architecture gate, 25 October 2026. Documents only; no production code.** The owner approved the route and the egress in principle on 25 October 2026, then **approved every egress term E1 to E16 as written ("Approve all", 25 October 2026; section 10)**. Q1 to Q3 were decided as recommended under the owner's delegated autonomy the same day (section 3.1). The architecture gate returned **PASS WITH CHANGES**; every required change is applied here (section 17) and must hold before any L1 code. The approved changes to [privacy and egress](privacy-and-egress.md) and the [privacy policy](privacy-policy.txt) are in section 11; they take effect in the PR that wires the live transport (E16), so the bundled policy is unchanged until then and the current app sends no label photo.

It adds a new entry route. It does **not** amend [reader v3](pasted-nutrition-label-reader-v3.md) or any file pinned by `ReaderV3FreezeTests` (section 12.6). It reuses the pasted route's Confirm rules from [pasted label Confirm v1](pasted-label-confirm-v1.md) and [food confirmation v5](food-confirmation-contract-v5.md), and extends them only where a photo differs (section 4).

## 1. Problem

Typing or pasting a Taiwan 營養標示 table is slow, and most labels the user meets are on a pack, not in copyable text. The on-device route B of the [capture evaluation](nutrition-label-capture-evaluation-v1.md) read only 4 of 40 untouched Taiwan photos. The multimodal route C did much better but did not pass the automatic bars (evaluation section 9.8), so it can only be offered as an assisted pre-fill that the user checks, which is exactly the owner's principle: the machine pre-fills, the user confirms or overrides, and exceptions are visible.

Evidence this design rests on, and its limits:

| Evidence | What it says | Limit |
|---|---|---|
| [Untouched Taiwan run](../Tools/NutritionLabelCaptureEvaluation/results/untouched-taiwan-v1.md) (18 October 2026) | Gemini 4 Argon: 33/40 full tables as run, median cost $0.0105, p50 / p90 latency 9.9 / 15.5 s. GPT-6.1 Sol: 33/40, $0.0162, 16.7 / 22.6 s (over the 20 s ceiling). Luna: 30/40, $0.0006, 5.8 / 9.8 s. No identity mismatches | Ran on **first-party, non-ZDR** endpoints with full-size images by owner decision for the evaluation only (evaluation 9.6 items 1 and 2). ZDR endpoints and downscaled images are unmeasured |
| [Correction effort](../Tools/NutritionLabelCaptureEvaluation/results/correction-effort-v1.md), assisted view | Tables needing no edit: Gemini 4 35/40, Sol 34/40, Luna 30/40. Silent-error tables (a wrong value no flag marks): Gemini 4 2, Sol 3, Luna 7 | Truth is model-drafted, owner-verified, with a known anchoring caveat; whether users catch errors is not measured |
| Route B (Vision) | No false-ready, but declines 35 of 40 | Its raw recognition was not measured as a **locator** of known values (section 6) |

So: roughly 1 table in 20 would carry a wrong value that nothing flags. The design's job is to make checking against the photo quick, to flag what can be flagged mechanically, and to say plainly that the values were read by AI.

## 2. Owner decisions (25 October 2026, verbatim)

> We were going to use open router. So what if not100%? We will what we can user overrides or confirms. Ui should make it easy to zoom and pan and focus on the labels

> Ok let's go with Taiwan now. And passing these kinds of photos ok. We strip metadata for sure.

Read as:

1. The route uses OpenRouter and a multimodal model; accuracy below 100% is accepted because the user confirms or overrides every value.
2. The Confirm screen must make it easy to zoom, pan and focus on the label.
3. v1 covers Taiwan (Traditional Chinese 營養標示) labels only; other languages decline with the pasted route's message.
4. Sending the cropped, downscaled, metadata-stripped label photo to OpenRouter is approved **in principle**. All metadata is stripped by re-encoding from pixels, and a test proves none survives.
5. The concrete egress terms (section 10) need explicit line-by-line approval before any code sends data.

Later the same day (25 October 2026):

6. **Egress terms:** "Approve all": E1 to E16 approved as written (section 10).
7. **Q1, Q2 and Q3** decided as recommended, under the owner's delegated autonomy: attention items block Log; unchanged photo values reuse `user_verified_panel` with source `label-photo-ai`; admission goes through the composite `LabelSourceAdmission`, with no freeze re-pin.

## 3. Decisions with recommendations

Each row is a design decision. Rows marked **Owner** need an answer before the phase that depends on them; the recommendation is the default if the owner agrees.

| ID | Decision | Recommendation | Owner? |
|---|---|---|---|
| P1 | **Entry.** Add food gains **Photo of nutrition label**, beside Paste nutrition label. One intent ("log a packaged food from its label"), two inputs; both end on the shared Confirm with one Log | As stated | No |
| P2 | **Sources.** Camera, photo library and screenshots (screenshots arrive through the library) | Camera through `UIImagePickerController` (camera source, still photo only, no video, no Live Photo); library through SwiftUI `PhotosPicker`, which runs out of process and needs no photo library permission. VisionKit's document camera was considered: its edge detection suits flat sheets, not curved packs, so the app's own crop step is used for every source | No |
| P3 | **Crop before sending.** A mandatory crop screen; the user frames the table. Nothing outside the crop is sent or kept | Free-form rectangle with handles, pinch-zoom and pan under it, initial crop the whole image; rotate in 90° steps. No automatic table detection in v1 (it would be another on-device model to qualify) | No |
| P4 | **Metadata.** The sent image is re-encoded from decoded pixels: orientation applied to the pixels, colour converted to sRGB, written by ImageIO as baseline JPEG with no metadata dictionary. No EXIF, GPS, TIFF, IPTC, XMP, maker notes (including Apple's), thumbnails, depth, gain maps or auxiliary images survive | As stated, proven by the tests in 12.5 | No (owner decided) |
| P5 | **Size.** After crop: long edge at most **2,048 px** and at most **3,200,000 px** in total, JPEG quality 0.85; if the encoded file exceeds **1,500,000 bytes**, re-encode at 0.75 then 0.65; if still over, the read is refused with the copy in 7.2. A crop whose short edge is under **240 px** is refused as too small (lowered from 480 px after L0, 17.9; to be confirmed by E13) | As stated; 2,048 px keeps small Chinese print legible. **The evaluation sent full-size images**, so section 10 E13 re-qualifies at this size before release | Approved (E3); minimum decided 25 October 2026 (17.9) |
| P6 | **Explicit send.** Nothing leaves the device until the user taps **Read label with AI**, beside a statement that the photo goes to OpenRouter and the model. The first read on a device shows a one-time confirmation sheet | As stated; copy in 7.1 | Approved (E4) |
| P7 | **What is sent.** The prepared image, a fixed instruction and a fixed strict output schema. Not the name, brand, notes, food log, health data, device or account identifiers | As stated; name and brand stay on device | Approved (E2) |
| P8 | **Output.** The model returns the evaluation's wire shape (headers with printed text and basis; rows with printed label, nutrient, parent and per-header printed text; serving lines as printed text). The app, not the model, turns printed text into numbers, units and comparators, and builds the same `label-capture-candidate-v1` the pasted route produces | Port the evaluation's `route_c_mapping.py` to Swift as `label-photo-wire-mapping-v1`, behind exported parity vectors, as the gate was ported | No |
| P9 | **Same rules as pasted.** The candidate goes through the frozen decline gate v2 (G1 and G2 hard declines, G3 to G6 flags), the Taiwan launch scope, `pasted-label-conversions-v1`, `label-arithmetic-checks-v2`, the basis options function and the identity mapping, all called, never copied or changed | As stated (section 12.6 lists the calls) | No |
| P10 | **Servings.** The same outcomes as `pasted-label-serving-v1` (per serving column) and `-v3` (per 100 g or ml with an exact serving in the same unit). The frozen serving policy is keyed by pasted parser versions, so the photo route owns `label-photo-serving-v1` with the same rules and a parity test over every pasted serving fixture | As stated; no frozen file changes | No |
| P11 | **Regions per value.** Apple Vision text recognition runs **on device** on the same prepared image and locates each returned printed value, constrained to its row label's line and its header's column. A value with exactly one match is **found on the photo**; zero or several matches is **not found** | Vision, not model boxes (section 6 compares) | No |
| P12 | **Attention items block Log.** A value not found on the photo, a value the arithmetic or consistency checks implicate, a serving line not found, and any G3 to G6 flag are **attention items**. Each must be resolved (Matches the photo, Correct, or Leave unknown) before Log is enabled. Values found on the photo with no failed check need no tap | As stated. This differs from the pasted route, where flags never block, because a photo read has silent misreads that pasted text does not (section 1). It is a route-owned requirement, like the pasted fortification policy | **Decided: yes (Q1)** |
| P13 | **Fortification.** Exactly the pasted Confirm v1 rules C1 to C12: asked once on Confirm, Yes / No / Not stated, nothing preselected, nothing inferred from the photo or the model | As stated; the model is never asked about fortification | No |
| P14 | **Honesty note.** A fixed line at the top of the label section: values were read by AI from the photo and must be checked. No confidence scores, no "verified" badge | Copy in 7.3 | No |
| P15 | **Provenance.** A versioned manifest `label-photo-ai-v1` records model, provider, endpoint, route, instruction, schema, mapping, gate, checks, locator and serving versions, the image hash and size, the model's raw response, usage and cost, and every per-value state and user action | Section 8 | No |
| P16 | **Keep the photo.** The exact sent image (already cropped, downscaled and stripped) is kept on device with a **logged** entry as evidence, so Confirm on reopen shows it and its hash verifies. Unlogged photos and every original are never written to disk by the app. Kept photos are not in the Drive food export or in backups (archives already omit raw attachments) | Keep | **Approved (E15)** |
| P17 | **Model.** One route in v1: Gemini 4 Argon on its ZDR endpoint. GPT-6.1 Sol on Azure is the named alternative, used only through a route version bump, never as a fallback. Luna is excluded (5 to 7 silent-error tables) | As stated | **Approved (E6)** |
| P18 | **Value provenance kind.** Unchanged values carry the existing `user_verified_panel` kind (the numbers are printed, the user checked them and logged), with the release's source ID `label-photo-ai` saying they were read by AI from a photo; corrected or entered values carry `manual_declaration`, as on the pasted route | Reuse the two existing kinds; a new kind such as `model_read_panel` would change a closed domain enum and every store decoder | **Decided: reuse (Q2; export per 17.4)** |
| P19 | **Admission without touching the freeze.** `PanelSourceAdmission.admitted` lives in the pinned `PastedLabelSource.swift`, so the photo verifier cannot be appended there without a re-pin. A new `LabelSourceAdmission` (new file) routes a candidate whose release or any value names `label-photo-ai` to the photo verifier, and every other candidate to the unchanged `PanelSourceAdmission`; the two Confirm call sites (`FoodConfirmation.swift`, near lines 498 and 841) and the fortification scope predicate call the composite | Composite. Alternative: re-pin the freeze (pin 4) to append one verifier, which needs an owner freeze decision | **Decided: composite (Q3)** |
| P20 | **Reading type.** `LabelReading.Origin` (pinned `LabelReading.swift`) has only `pasted_text`. The photo route returns its own application type `LabelPhotoReading` holding the same candidate, gate split, flags, warnings and versions plus the per-value locations, rather than adding a case to a pinned enum | As stated; the shared Confirm sections take a small protocol both readings satisfy (12.1) | No |
| P21 | **Offline and no key.** Read label is disabled with an explicit state when offline, when no key is stored, when the key has not been validated this session, or when the daily limit is reached | As stated (section 9) | No |

### 3.1 Questions for the owner (decided 25 October 2026)

All four are closed: Q1 to Q3 as recommended under delegated autonomy, and the checklist approved in full. The original wording is kept for the record.

1. **Q1 (P12): should attention items block Log until each is resolved?** Recommendation: yes. It costs a tap per flagged value (on the evaluation, most tables would have none), and it is the only mechanical defence against a misread that the photo makes visible. Without it, a not-found value would be one more caption the user can scroll past.
2. **Q2 (P18): reuse `user_verified_panel` for unchanged photo values?** *Decided: yes, option (a); the export behaviour and every manifest-keyed site are in 17.4.*
3. **Q3 (P19): composite admission rather than a freeze re-pin?** Recommendation: composite; the freeze then stays at pin 3.
4. **The egress checklist (section 10)**, line by line.

## 4. User journey

```
Add food ─ Photo of nutrition label ─ Source (camera / library) ─ Crop ─ Label photo
                                                                           │ (Read label with AI)
                                                                           ▼
                                        Declined / Failed (photo kept on screen) ◄── Reading
                                                                           │
                                                                           ▼
                                                                  Confirm ── Log
```

### 4.1 Label photo screen

- **Photo** (the crop, as it will be sent), with **Retake** / **Choose another** and **Adjust crop**.
- **Name** (required) and **Brand** (optional), as on the pasted route. They are stored with the entry and never sent.
- The **egress statement** (7.1) directly above the button, every time.
- **Read label with AI**, disabled while Name is empty, no photo is chosen, or a blocking state of section 9 holds.
- **Leave without saving** discards the photo from memory.

### 4.2 Confirm (order)

1. **Food**: name, brand, source line "From a label photo, read by AI", estimate notice if Not stated is chosen.
2. **Fortification**: pasted Confirm v1 section 4.1, unchanged.
3. **Amount eaten**: as pasted Confirm v1 (servings by default when a serving is read and exact).
4. **Label photo**: the photo pane (section 5).
5. **Nutrition from the photo**: honesty note, attention summary, basis line, values with their states, serving lines, "Printed but not read", "Read but not used".
6. The existing remainder (compact nutrition for the amount, Save as favourite, Source details, recovery, Before you log).

The pasted route's Edit label text becomes **Retake or adjust photo**, which returns to the Label photo screen; a new read is a new source (pasted C10 applies: corrections and the fortification answer reset, after the existing "Reading again replaces your corrections" confirmation).

## 5. Photo pane and focus

- **Always available.** The pane sits above the values at a fixed height (about 40% of the screen at default text size, a compact strip at accessibility sizes with a **Show photo** button), and **Full screen** opens it in a sheet that keeps the selected value's highlight.
- **Zoom and pan.** Pinch to zoom (1x to 8x), drag to pan, double-tap to toggle between fit and 3x at the tapped point; **Fit** button to reset. VoiceOver: the pane is one adjustable element; swipe up / down zooms in or out, and the three-finger scroll pans.
- **Focus.** Tapping a value row (or its **Show on photo** button, a 44 pt target) zooms and pans the photo so the value's region is centred at a legible scale, and draws a highlight: a 2 pt outline in the accent colour **plus** a white-backed caption with the row and column ("Fat, per 100 g"), so the highlight never relies on colour alone. The row label's region gets a thinner dashed outline. VoiceOver announces "Showing fat, per 100 g, on the photo".
- **Not found values** have no region; Show on photo zooms to the row label if it was found, otherwise fits the whole photo, and says "This value was not found on the photo. Check the table yourself."
- The pane is display only. It never edits a value and never sends anything.

## 6. Locating values on the photo (on device)

### 6.1 Recommendation: Apple Vision, locally

After the model's reading is mapped (P8), `LabelValueLocating` runs `VNRecognizeTextRequest` (accurate level, `zh-Hant` and `en-US` as advertised by the running Vision revision, language correction off) on the **same prepared image** that was sent. For each row and each value cell:

1. Normalise both sides: Unicode NFKC (full-width digits and letters to half-width), remove whitespace, lower case, keep the comparator and unit characters. Only ASCII digits count as digits (Han numerals such as 一 are words on a label).
2. Find every **row label** and every **header** of the table that occurs exactly once; a label or header may not be preceded by a letter or ideograph, so 脂肪 is not found inside 飽和脂肪.
3. Candidates for a value are occurrences of its normalised printed text not preceded or followed by a digit or decimal point (so 5公克 is not found inside 15公克), with the box of that substring.
4. When the value's row label was found, keep only candidates whose **nearest row label** (by vertical centre) is that label; when its header was found, keep only candidates whose **nearest header** (by horizontal centre) is that header. Nearest, not a fixed band, because Vision often reads the label column and the value columns as separate lines and photos are often tilted.
5. Exactly one candidate left: **found**, with its bounding box (normalised to the image, rounded to four decimals). Several: **ambiguous**. None: try the next text in order, the part from the first digit or comparator ("每一份量 185 公克" to "185公克"), then, for a value, its number alone (when Vision reads the unit as its own line); if none has a candidate, **not found**. Ambiguous and not found are both shown as "Not found on the photo".

Serving lines and the servings per pack line are located the same way on their printed text, with no row or column constraint. The matcher (`LabelValueMatcher`, `label-photo-vision-locate-v1`) is pure Swift; L0 built and measured it (17.9) and L1 carries the file into the package unchanged.

Being found is **corroboration, not verification**: two independent readers agree that this text appears at this place in this row and column. It cannot prove the model bound the value to the right nutrient when the row label itself was misread, so found values are still values the user checks; they are just not attention items.

### 6.2 Compared with asking the model for boxes

| | Vision locally (recommended) | Model returns boxes |
|---|---|---|
| Egress | None beyond the read | None extra, but a larger response |
| Independence | Independent second reader; agreement is evidence | The same model grades itself; a misread value comes with a confident box |
| Accuracy | Text boxes from OCR are tight and well defined | Multimodal box output varies by model and is unmeasured here |
| Schema | Unchanged evaluated wire schema | Adds four numbers per cell; the 16-union budget and the evaluated schema change, so route C quality would need re-measuring |
| Cost and latency | On-device, about a second | More output tokens on every read |
| Risk | Route B showed Vision misreads Taiwan photos as a **table reader**; as a **locator** of known strings its rate is unmeasured | Box drift would highlight the wrong place, which is worse than no highlight |

**Measure before building the UI.** The raw Vision outputs of the 20 development and 40 untouched Taiwan photos already exist from route B, and the route C outputs are saved, so the located rate per cell, and how many of the evaluation's silent errors would have been not found, can be computed **offline with no egress**. Phase L0 (section 13) does this first. If fewer than about 70% of correct cells are found, attention items would be mostly noise; the owner then decides between keeping P12 as a softer non-blocking flag or adding model boxes in a v2.

## 7. Exact copy

British spelling, plain language, no emoji. Strings live in a new `LabelPhotoText`; shared Confirm strings stay where they are. `<Model>` and `<Provider>` are the display names of the one allow-listed route, for example "Gemini 4 Argon" and "Google Vertex".

### 7.1 Label photo screen

| Element | Copy |
|---|---|
| Add food row | `Photo of nutrition label` |
| Add food row subtitle | `Taiwan labels (營養標示). Read by AI; you check every value.` |
| Source choices | `Take photo`, `Choose from library` |
| Crop screen title / instruction | `Crop to the label` / `Drag the corners so the nutrition table fills the frame. Only this part is sent.` |
| Crop actions | `Use crop`, `Rotate`, `Cancel` |
| Name / Brand | as the pasted route |
| Egress statement (above the button, always) | `Read label with AI sends this cropped photo to OpenRouter, which passes it to <Model> on <Provider> to read the table. Location and camera details are removed first. Your name, brand and food log are not sent. Nothing is saved until you tap Log.` |
| Button | `Read label with AI` |
| Under the button | `Uses your OpenRouter key and credit. Today: <n> of 30 reads.` |
| First-use sheet title | `Send label photos to OpenRouter?` |
| First-use sheet body | `To read a label photo, the app sends the cropped photo to OpenRouter and the model it names, using your key. OpenRouter is asked to use only an endpoint that keeps no copy and does not train on it, with no fallback to other providers. OpenRouter keeps its own account and usage records. You check and correct every value before anything is saved.` |
| First-use sheet actions | `Send photo`, `Not now`, link `Privacy policy` |
| Leave | `Leave without saving` |

### 7.2 Blocking, reading, declined and failed states

| State | Copy |
|---|---|
| Camera permission denied | `Camera access is off for this app. You can choose a photo from your library instead, or turn on the camera in Settings.` with `Choose from library` and `Open Settings` |
| No key | `Add your OpenRouter key to read label photos.` with `OpenRouter settings` |
| Key not validated this session | `Validate your OpenRouter key before reading a photo.` with `Validate key` |
| Offline | `You're offline. Reading a label photo needs a connection. You can paste the label text instead.` with `Paste nutrition label` |
| Daily limit reached | `You've reached today's limit of 30 label photo reads (or $0.50 of reported cost). It resets at midnight.` |
| Route unavailable (on-the-day check failed) | `Label photo reading is unavailable: the model's private endpoint could not be confirmed. Nothing was sent.` |
| Crop too small | `This crop is too small to read. Move closer or crop less tightly.` |
| Photo too large after compression | `This photo could not be made small enough to send. Crop more tightly and try again.` |
| Reading | `Reading the label…` with `Cancel` |
| Retrying | `OpenRouter is busy. Trying again (attempt <n> of 3)…` with `Cancel` |
| Cancelled after sending | `Stopped. The photo may already have reached OpenRouter; nothing was saved.` |
| Declined: language | `This label is in a language the app cannot read yet. It reads Traditional Chinese (Taiwan layout) labels.` (the pasted route's sentence, from `PastedLabelLaunchScope`) |
| Declined: no table | `No nutrition table was found in this photo. Crop to the table and try again.` |
| Declined: supplement | `This looks like a supplement panel, which the app does not read.` |
| Declined: prepared or drained | the pasted route's `basis_state_not_supported` sentence |
| Failed: timed out | `Reading the photo timed out. You can try again.` |
| Failed: connection | `Reading the photo could not connect. Check your connection and try again.` |
| Failed: key rejected | `OpenRouter rejected the API key. Replace or revalidate it.` |
| Failed: quota | `OpenRouter reports a quota or rate limit. Check your quota and billing before trying again.` |
| Failed: unusable answer (schema, truncation, refusal, wrong model or provider) | `The model's answer could not be used, so nothing is shown. You can try again, or paste the label text.` |
| Failed: cost over the per-call limit | `This read cost more than the $0.05 limit, so label photo reading is paused for today.` |
| After any decline or failure | `Paste nutrition label`, `Search foods` (one tap each), and the photo stays on screen |

### 7.3 Confirm

| Element | Copy |
|---|---|
| Source line | `From a label photo, read by AI · per 100 g` (or per 100 ml, per serving) `· Traditional Chinese, Taiwan layout` |
| Honesty note (top of the label section, always) | `Read by AI from your photo. AI can misread numbers, so check each value against the photo before you log.` |
| Attention summary (when any) | `<n> values need your check before you can log.` |
| Attention summary (none) | `Every value was found on the photo. Check them before you log.` |
| Value state: found | `Found on photo` |
| Value state: not found | `Not found on photo. Check it.` |
| Value state: check failed | `Doesn't add up with the other values. Check it.` |
| Value state after resolving | `Checked by you`, `Corrected by you`, `Entered by you`, `Left unknown` |
| Attention actions (each 44 pt) | `Matches the photo`, `Correct`, `Leave unknown` |
| Arithmetic item (table level) | `Energy does not match protein, fat and carbohydrate. Check these values against the photo.` with `I've checked them` (marks the energy, protein, fat, carbohydrate and fibre items checked) |
| Per serving against per 100 item | `The per serving and per 100 g values do not agree with the serving size. Check them against the photo.` with `I've checked them` |
| Show on photo (VoiceOver label) | `Show <row>, <column> on the photo` |
| Pinned bar beside a disabled Log | `Check the <n> highlighted values against the photo.` (after the fortification sentence when both block) |
| Source footer | `To read a different photo, use Retake or adjust photo. To change a value, correct it in Nutrition from the photo.` |
| Saved entry and Developer tools | `Read by <Model> on <Provider> through OpenRouter, <date>; checked by you` and the per-value states |

Leave unknown stores the nutrient as unknown, never zero, and reads "Left unknown" on Confirm and "Not stated" after saving, as any unknown does.

## 8. Persistence and versioning

### 8.1 Manifest `label-photo-ai-v1`

A logged photo entry stores **two** `CaptureEvidence` records:

1. **Image**: `kind = .packageImage` (existing), `captureMethod = "Label photo prepared on device"`, `captureMethodVersion = "label-photo-preparation-v1"`, payload `.descriptor("image/jpeg")`, `byteHash` = SHA-256 of the sent bytes, `attachment` through the existing `recordEvidenceWithAttachment` and `EvidenceAttachmentStoring` (protected, backup-excluded attachments directory).
2. **Manifest**: `kind = .packageImage`, `captureMethod = "Label photo read by AI"`, `captureMethodVersion = "label-photo-ai-v1"`, payload `.text(<canonical manifest bytes>)`, `byteHash` = SHA-256 of the manifest bytes, no attachment.

The manifest, encoded with `FoundationCanonicalJSONEncoder` (sorted keys, unescaped slashes) and stored verbatim:

| Field | Content |
|---|---|
| `version` | `label-photo-ai-v1` |
| `route_version` | `label-photo-ai-route-v1` |
| `image` | `sha256`, `byte_count`, `pixel_width`, `pixel_height`, `media_type` (`image/jpeg`), `preparation_version` (`label-photo-preparation-v1`), `jpeg_quality` |
| `request` | `model` (requested slug), `endpoint` (requested provider tag), `reasoning` (as sent), `max_output_tokens`, `instruction_version`, `instruction_sha256`, `wire_schema_version`, `wire_schema_sha256`, `catalogue_check` (`at`, and the slug, endpoint, modalities, ZDR flag and prices seen) |
| `response` | `model` and `provider` as returned, `generation_id`, `finish_reason`, `attempts` (count), `usage` (`prompt_tokens`, `completion_tokens`, `reasoning_tokens` when reported, `cost_usd` as decimal text or `unknown`), `requested_at`, `completed_at` (milliseconds, injected clock), `wire_text` (the model's JSON answer, verbatim, at most 65,536 bytes), `wire_sha256` |
| `mapping_version` | `label-photo-wire-mapping-v1` |
| `gate_version`, `arithmetic_version`, `conversion_version`, `serving_version` | `label-capture-decline-gate-v2`, `label-arithmetic-checks-v2`, `pasted-label-conversions-v1`, `label-photo-serving-v1` |
| `label_format`, `launch_scope` | `taiwan`, `["taiwan_nutrition_labelling"]` |
| `identity_mapping` | `pasted-label-identity-v1` and its facet values, including the fortification answer (the same mapping: it describes a printed label, whatever the input) |
| `candidate` | the `label-capture-candidate-v1` built by the mapping, with `route` `C` |
| `locations` | `locator_version` (`label-photo-vision-locate-v1`), `vision_revision`, `languages`, and one record per cell and serving line: `cell` (row and header ID, or `serving_size` / `servings_per_pack`), `status` (`found`, `not_found`, `ambiguous`), `region` (normalised `x`, `y`, `w`, `h` as decimal text, only when found) |
| `stored_header_id`, `basis_choices`, `conversions`, `flags_shown`, `warnings_shown`, `corrections` | as pasted manifest v2 (`basis_choices` always present, empty when every basis was printed) |
| `attention` | one record per attention item shown: `item` (cell, line or `arithmetic:<check>`), `reason` (`not_found`, `ambiguous`, `check_failed`, `gate_flag`), `resolution` (`checked`, `corrected`, `entered`, `left_unknown`), `at` |
| `attention_version` | `label-photo-attention-v1` (17.5) |
| `consistency_version` | `label-photo-serving-consistency-v1`, the per serving against per 100 check (17.5) |
| `name`, `brand` | as entered (`brand` omitted when empty) |

- **No key, no device or account identifier, no original image, no crop coordinates in the original** are stored. The generation ID is OpenRouter's request reference, kept so the user can reconcile cost on their account.
- `SourceRelease`: `sourceID = "label-photo-ai"`, `sourceReleaseID = "label-photo-ai:" + manifestHash`, `artifactHash` = image SHA-256, `schemaVersion = "label-photo-ai-v1:taiwan"`, `pipelineVersion = "<route>:<model>@<endpoint>:<instruction>:<mapping>:<gate>:<arithmetic>:<consistency>:<conversion>:<serving>:<locator>:<attention>"`, `licence = "User-supplied label photo read by an AI model; no redistribution licence inferred."`, `attribution = "Label photo read by AI"`.
- Value provenance: P18. `manifestReference` names the cell (`manifest-sha256=…;header=…;row=…;literal=…`) or the correction (`;correction=<index>`), as the pasted route.

### 8.2 Verification

At save (`invalidLabelPhotoSource`, before policy) and at reopen (`integrityFailure`), against the stored manifest, never a re-read:

1. Manifest digest, strict decode (unknown or missing keys throw), canonical re-encode equals the stored bytes.
2. The pipeline is the one admitted entry for `label-photo-ai-v1` (append-only list, pinned by a test).
3. `wire_sha256` matches `wire_text`. The verifier does **not** replay the mapping (17.1): it checks the stored candidate against itself and the stored values, as the pasted verifier does; replay is a reader-level contract test (17.8 test 16).
4. Stored nutrients, units, bounds and basis equal the candidate's stored column, conversions and corrections exactly as the pasted v2 rules define.
5. The attention set recomputed from the stored locations, flags and check outcomes under `attention_version` equals the stored `attention` items (17.5), and every item has a resolution; a `left_unknown` cell is stored unknown; a `corrected` or `entered` one equals its correction record.
6. Every `region` is inside the unit square; `found` has a region and the others do not.
7. When the image attachment is present, its SHA-256 equals `image.sha256`. When it is absent (a restored archive), the entry still verifies on the manifest and Confirm on reopen says `The photo is not on this device.`
8. Cross-route: the pasted verifier rejects photo evidence and the photo verifier rejects pasted and reviewed web evidence, including a photo manifest relabelled as pasted and the reverse.

### 8.3 Versions and compatibility

- New: manifest `label-photo-ai-v1`, route `label-photo-ai-route-v1`, preparation `label-photo-preparation-v1`, instruction `label-photo-instruction-v1` (the evaluation's `label-image-extraction-instruction-v1` text, unchanged unless qualification requires otherwise, in which case the version moves), wire schema `label-photo-wire-schema-v1` (the evaluation's `label-image-wire-schema-v1`), mapping `label-photo-wire-mapping-v1`, serving `label-photo-serving-v1`, locator `label-photo-vision-locate-v1`.
- Any change to one of them is a new version; stored entries are never re-verified against a newer version.
- **Store and archive (decided by the gate; 17.7).** Metadata-only migration `v8_label_photo`, `foodContractVersion` 8, and `minimumContractVersion` 8 only when `label-photo-ai-v1` evidence exists, so contract 6 and 7 export bytes are unchanged and an older binary declines a contract 8 archive cleanly. Archives omit raw attachments already (`rawAttachmentsOmitted`), so the photo is never in a backup; the manifest is.
- Every existing record decodes, verifies and re-encodes byte for byte.
- The Daily JSON health export gains nothing. The food daily export gains no field (17.4): photo values export as `label_checked_by_you` (or `entered_by_you`) with a `label-photo-ai:` `source_release_id`. Photo-specific per-value origins are deferred to the food export v2 issue #312.

## 9. Screen states

| State | When | What the user sees | Read label / Log |
|---|---|---|---|
| Empty | Route opened | Take photo, Choose from library | n/a |
| Camera denied | Camera permission off | 7.2 copy, library still offered | n/a |
| Cropping | Photo chosen | Crop screen | n/a |
| Ready | Crop set, Name entered, key validated, online, under limits | Photo, fields, egress statement, button enabled | Read enabled |
| No key / not validated / offline / daily limit / route unavailable | As named | 7.2 copy, one-tap way out | Read disabled |
| Reading | After the tap | Progress, Cancel | n/a |
| Retrying | Retryable failure within the deadline | 7.2 retrying copy, Cancel | n/a |
| Declined | Model decline, G1, G2, launch scope, basis state | Reason (7.2), photo kept, other routes | n/a |
| Failed | Transport, HTTP, content or cost failure | Reason (7.2), photo kept, Try again (a new explicit tap) | n/a |
| Confirm: attention | Any unresolved attention item | Summary, highlighted rows, pinned bar | Log disabled |
| Confirm: partial | Rows not read, unknowns | "Not read" rows; unknown never zero | as requirements |
| Confirm: estimate | Not stated chosen | Estimate notice | as requirements |
| Confirm: ready | All requirements met | Log enabled | Log enabled |
| Failed: save | Existing save failure | Existing recovery | Retry as today |
| Saved / reopened | After Log, Edit | Photo (or "not on this device"), read-only states | n/a |

Try again after a failure is a new user tap, never automatic, and it counts against the daily limit.

## 10. Egress terms (approved by the owner, 25 October 2026)

**Approved in full: "Approve all" (owner, 25 October 2026).** The lines below are the approved text, unchanged. The architecture gate narrowed three of them without widening any (E7's timing and headers, E9 as a per-tap total, E11's overloaded answer defined); the narrowed rules are in 17.5 and bind the implementation. No live transport is wired before L5 (section 13), and the policy changes take effect with it (E16).

- [x] **E1 Destination.** `https://openrouter.ai/api/v1/chat/completions` only, which forwards to the one pinned model endpoint (E6). *Recommend: approve.*
- [x] **E2 Payload.** One prepared JPEG as a data URI, the fixed instruction and the fixed strict JSON schema; nothing else: no name, brand, notes, food log, health data, location, device or account identifiers. The key travels only in the Authorization header and a request containing it in the body is refused. *Recommend: approve.*
- [x] **E3 Image.** Cropped by the user; re-encoded from pixels with every metadata block removed (a test proves it); long edge at most 2,048 px, at most 3.2 megapixels, at most 1,500,000 bytes. *Recommend: approve.*
- [x] **E4 When.** Only on the explicit Read label with AI tap beside the egress statement, with a one-time confirmation sheet on first use; no background, prefetch or automatic re-read. *Recommend: approve.*
- [x] **E5 Routing.** Provider block `only` and `order` set to the one endpoint, `allow_fallbacks: false`, `require_parameters: true`, `data_collection: "deny"`, `zdr: true`; the response's model and provider must match the request or the read fails and nothing is shown. *Recommend: approve.*
- [x] **E6 Model allow-list.** Exactly one route: Gemini 4 Argon (`google/gemini-4-argon`) on the ZDR endpoint OpenRouter lists on the day (expected Google Vertex); GPT-6.1 Sol on Azure named as the alternative, switched only by a route version bump; no fallbacks; Luna excluded. *Recommend: approve, subject to E7 and E13.*
- [x] **E7 Identity check on the day.** Before each release that enables the route, and at runtime once per app session before the first read, a free catalogue request (no user data) confirms slug, endpoint, image input, ZDR and prices; any mismatch disables reading and nothing is sent. *Recommend: approve.*
- [x] **E8 Key.** The user's existing OpenRouter key from this-device-only Keychain, validated in the current session; never in a body, log, manifest or export. *Recommend: approve.*
- [x] **E9 Per-call cap.** Output limited to 4,000 tokens so the worst case at the day's catalogue prices stays under **$0.05**; a reported cost above $0.05 pauses the route for the rest of the day. *Recommend: approve.*
- [x] **E10 Daily cap.** At most **30 reads and $0.50** of reported cost per local calendar day, counted on device; a read with no reported cost counts as $0.05. The owner also sets a limit on the OpenRouter key. *Recommend: approve.*
- [x] **E11 Retries.** Only transport errors, timeouts, HTTP 408, 429, 500, 502, 503, 504 and provider-overloaded answers; exponential backoff with jitter honouring `Retry-After` in seconds and HTTP-date forms; at most 3 attempts within a 90 s whole-call deadline (45 s per attempt), identical bytes, visible with Cancel; content failures never retried. This amends the "no automatic retries" egress rule for this path only. *Recommend: approve.*
- [x] **E12 Response limits.** At most 200,000 bytes, a single choice with `finish_reason` `stop`, no tool calls or refusal, strict schema validation; anything else is a failed read. *Recommend: approve.*
- [x] **E13 Qualification before enabling.** The approved route, on its ZDR endpoint with the E3 preparation, runs once on the 20 development and 40 untouched Taiwan photos (public Open Food Facts images, now exposed, so a regression check) and on the 10 remaining approved refill photos (orders 78 to 87) as a fresh check; bars: zero identity mismatches, median cost at most $0.02, p90 latency at most 20 s, no-edit tables at least 80% of usable tables, silent-error tables reported case by case; spend stop $10. *Recommend: approve.*
- [x] **E14 Provider records.** ZDR and no-collection apply to the model endpoint only; OpenRouter keeps account and usage records (model, tokens, cost, time, generation ID) under its own terms, and the policy says so. *Recommend: approve the disclosure.*
- [x] **E15 On-device retention.** The sent image is kept with a logged entry only, in the protected, backup-excluded attachments directory, never in the Drive export or archives; unlogged photos and originals are never written by the app. *Recommend: approve.*
- [x] **E16 Records.** The `privacy-and-egress.md` row, the privacy policy text (section 11) and the camera usage string take effect in the same PR that wires the live transport. *Recommend: approve.*

## 11. Approved amendments (take effect with the live transport, E16)

### 11.1 `docs/privacy-and-egress.md`

Add one row to "Allowed egress" when the live transport is wired:

```diff
 | OpenRouter and its configured providers | Displayed food terms and captured public source text | Only on an explicit web lookup, with the user's own validated key | [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) |
+| OpenRouter and its one allow-listed model endpoint (ZDR, data collection denied, no fallbacks) | One cropped, downscaled label photo re-encoded with all metadata removed, plus a fixed instruction and output schema; no name, brand, food log, health data or identifiers | Only when the user taps Read label with AI on the Label photo screen, with the user's own validated key; on the first tap of a session a catalogue request with no key and no user data first confirms the endpoint; at most 3 attempts for retryable failures and $0.05 in total per tap; at most 30 reads and $0.50 per day | [label-photo-ai-prefill-v1.md](label-photo-ai-prefill-v1.md) |
```

Amend the first rule for every egress path:

```diff
-- User-initiated and visible; no automatic retries, pagination, per-keystroke requests or background work beyond the approved budget for that path.
+- User-initiated and visible; no automatic retries, pagination, per-keystroke requests or background work beyond the approved budget for that path. A path's contract may approve bounded retries of retryable transport failures within the one user action, with backoff that honours `Retry-After` and a whole-call deadline (label photo reading: 3 attempts in 90 s).
```

Amend "Stays on the device unless the user sends it":

```diff
+- **Label photos** leave only as the single prepared image sent when the user taps Read label with AI. The image kept with a logged entry stays on the device; it is not in the Drive food export or backups.
```

Until the transport PR, the file carries only a pointer to this contract under an "Approved, not yet in force" heading.

### 11.2 `docs/privacy-policy.txt`

The policy is bundled in the app, so it is **not edited until the transport PR**; the text below replaces or adds the marked sentences in that PR (E16).

In "Local food records and notes":

```diff
-Camera access is optional and used to scan food barcodes; the current app does not offer label-photo OCR upload.
+Camera access is optional and used to scan food barcodes and, if you choose, to photograph a nutrition label. If you log a food from a label photo, the cropped photo that was sent is kept locally with that entry as its evidence; it is not included in the Drive food file or in backups. Photos you do not log, and your original photos, are not stored by the app.
```

New paragraph at the end of "Optional online food search":

```diff
+Label photo reading is optional and uses your own validated OpenRouter key. Only when you tap Read label with AI, the app sends the part of the photo you cropped, made smaller and re-encoded with location, camera and other metadata removed, to OpenRouter with a fixed instruction, and OpenRouter passes it to one named model endpoint (currently Gemini 4 Argon on Google Vertex) classified for zero data retention and no data collection, with no fallback to other providers. Your food name, brand, food log, notes and Apple Health data are not sent. The model's answer pre-fills the label values, which you check and correct before anything is saved. The app retries a failed request at most twice within the same tap, and limits reading to 30 photos and $0.50 of reported cost a day; reads may incur charges on your account. OpenRouter keeps its own account and usage records, including the model, token counts, cost and time of each request, under its terms. Avoid photographing anything other than the nutrition table.
```

In the existing sentence "The app does not attach HealthKit records, saved food or diary history, notes, receipts, photos or audio to these requests", add "web nutrition" before "requests" so it stays true.

The camera usage string (`NSCameraUsageDescription`) becomes: `Weekly Health Report uses the camera only when you choose to scan a food barcode or photograph a nutrition label.`

## 12. Architecture gate

### 12.1 Responsibilities

| Layer | Owns | Must not |
|---|---|---|
| **Domain** (`FoodLedgerDomain`) | Nothing new. `CaptureKind.packageImage`, `AttachmentDescriptor`, the provenance kinds and nutrient types are reused | Change a closed enum |
| **Application** (`FoodLedgerApplication`, new files only) | Ports: `LabelImagePreparing` (crop rectangle and bytes in, prepared bytes and dimensions out), `LabelImageReading` (prepared image in, `LabelPhotoWireReply` out: wire text, identity, usage, attempts), `LabelValueLocating` (image and candidate in, locations out), `LabelPhotoRouteChecking` (the on-the-day catalogue check), `LabelPhotoSpendLedger` (today's reads and cost), `ConnectivityStatus`. Types: `LabelPhotoReading`, `LabelPhotoAttention` (pure rules: which items, how resolved), `LabelPhotoServingPolicy`, `LabelPhotoManifest` with its strict codec, `LabelPhotoSource` (release, evidence, confirmation building, verifier), `LabelSourceAdmission` (composite, P19), `LabelPhotoSpendPolicy` (caps), `LabelPhotoRetryPolicy` (pure schedule from attempt, status and `Retry-After`, with an injected clock and jitter source). A small `LabelSourceSections` protocol both readings satisfy for the shared Confirm sections | Import the parser, ImageIO, Vision, URLSession or SwiftUI; hash or read a clock directly |
| **Pure reader** (new target `FoodLabelPhotoReading`, Foundation only plus `NutritionLabelParsing`) | `label-photo-wire-mapping-v1` (wire text to `LabelCaptureCandidate`), then the frozen gate, conversions and checks, mapped to `LabelPhotoReading` | Network, images, clocks |
| **Infrastructure** (new target `FoodLabelPhotoCapture`, iOS) | `ImageIOLabelImagePreparer` (decode, orient, crop, sRGB, scale, encode without metadata), `VisionLabelValueLocator`, `OpenRouterLabelImageReader` (request building, routing block, identity check, response limits, retry loop over an injected transport, cancellation), `OpenRouterLabelRouteChecker`, `NWPathConnectivityStatus`, a file-backed spend ledger in the protected app directory | Decide what is stored, format copy |
| **Presentation** (`FoodLedgerPresentation`; Foundation, SwiftUI and WebKit only) | Label photo screen and view model, Confirm attention rows and actions, the value list's focus requests, copy (`LabelPhotoText`); it shows the photo only through a view the composition root injects (17.2) | Import `FoodLabelPhotoCapture`, `FoodLabelPhotoReading`, `FoodLabelPhotoUI`, UIKit, PhotosUI or ImageIO; keep image bytes in scene or app storage |
| **Capture UI** (new target `FoodLabelPhotoUI`, like `FoodBarcodeCapture`; SwiftUI, UIKit, PhotosUI) | Camera picker, `PhotosPicker`, the crop screen and the zoom, pan and highlight photo view, behind application-owned closures or an injected view factory (17.2) | Decide, persist or send |
| **Composition root** | Registers the entry route, wires adapters; in phases before approval, wires only a fake transport | Contain rules |

### 12.2 Dependency direction

presentation → application → domain; `FoodLabelPhotoReading` → application, domain, `NutritionLabelParsing`; `FoodLabelPhotoCapture` → application, domain, `FoodLabelPhotoReading`, Apple frameworks. `check-boundaries.sh` gains `check_imports FoodLabelPhotoReading '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'` and an allow-list for `FoodLabelPhotoCapture` (`Foundation|ImageIO|CoreGraphics|UniformTypeIdentifiers|Vision|Network|CryptoKit|FoodLedgerApplication|FoodLedgerDomain|FoodLabelPhotoReading`), plus: only the composition root and their tests import either target; `NutritionLabelParsing` is still imported only by its existing users and `FoodLabelPhotoReading`. The OpenRouter key store stays in `FoodGenericSearch` and is passed in through the existing `FoodWebKeyStoring` port.

### 12.3 Invariants

1. **The only save is Log.** A read, a found value, a passed check or a resolved attention item never saves and never enables Log by itself.
2. **Nothing leaves without the tap.** No code path sends an image except the one Read label action; no retry crosses a user action; the payload is exactly E2.
3. **No metadata leaves.** The sent bytes are produced only by the preparer from decoded pixels.
4. **Model output never authorises.** The model's text is evidence; the app derives every number with the pure mapping and frozen rules; confidence is never requested or shown; fortification is never asked of the model.
5. **Unknown is never zero**; bounds stay bounds; Leave unknown stores unknown.
6. **One rule set.** Gate, conversions, checks, basis options and identity mapping are the frozen pasted ones, called not copied; serving parity is tested.
7. **Records are append-only and versioned**; the manifest is byte-exact and verified against itself; existing records and archives are unchanged.
8. **The freeze holds.** No file pinned by `ReaderV3FreezeTests` changes (12.6).
9. **Taiwan only** in v1; everything else declines.
10. **No medical classification** or interpretation in any copy.
11. **Costs are bounded** per call and per day, and unknown cost is never counted as zero.

### 12.4 Extension axes

- **Model route**: a closed enum of allow-listed routes; adding one is a new route version, an E-line approval and a qualification run. No user-selectable model in v1.
- **Locale**: the launch scope is the pasted route's; adding UK photos needs the UK untouched set the evaluation deferred, and its own contract.
- **Locator**: behind `LabelValueLocating`; model boxes could be a second conformer in a v2.
- Kept closed: the attention rules, the payload, the routing block and the manifest grammar.

### 12.5 Contract tests (written first)

Pure (package):

1. Wire mapping parity with the evaluation's exported vectors from `route_c_mapping.py` on every saved development and untouched route C output: identical candidates.
2. Gate, conversions and checks are the frozen functions (a test fake records the calls); decline codes map to 7.2 copy, and an unknown code renders the fallback.
3. Serving parity: for every pasted serving fixture, `label-photo-serving-v1` gives the same options and amounts as the pasted policy.
4. Attention rules: every reason creates an item; Log stays disabled until each has a resolution; arithmetic items resolve their implicated rows together; Leave unknown stores unknown.
5. Manifest strict codec goldens; canonical bytes; unknown or missing keys throw; generation ID, usage and unknown cost round-trip.
6. Verifier: every rule in 8.2 (no mapping replay; 17.1), including the attention recomputation, region bounds, a missing attachment and all cross-route rejections; `LabelSourceAdmission` routes photo and pasted candidates correctly, and a mixed candidate (one value naming each source) is refused.
7. Request builder golden: the exact JSON body, provider block, `max_tokens` 1,200 and the `reasoning` limit of 500 (17.5), one image part; the body never contains the key, name, brand or any field outside E2.
8. Response checks: wrong model, wrong provider, `finish_reason` other than `stop`, tool calls, refusal, oversize, schema-invalid each fail with nothing shown.
9. Retry policy: each retryable status retries; content failures do not; `Retry-After` in seconds and HTTP-date forms; a `Retry-After` past the deadline stops; at most 3 attempts in 90 s; cancellation stops at once (fake clock and jitter).
10. Spend policy: 30 reads, $0.50, unknown cost counted at $0.05, over-cap cost pauses the day, local-midnight reset with an injected calendar.
11. Locator matching on synthetic observations: unique, none, several, row band and column band constraints, full-width normalisation.
12. Existing pasted-label and catalogue entries decode, verify and re-encode byte for byte; `ReaderV3FreezeTests` passes with no re-pin.

Infrastructure (app test target, since ImageIO and Vision need the platform):

13. **Metadata stripping**: fixtures with EXIF (including GPS, maker notes and Apple's MakerApple), XMP, IPTC, a thumbnail, an orientation of 6, a HEIC with depth and a gain map, and a PNG with `eXIf` and `tEXt` chunks. After preparation: `CGImageSourceCopyPropertiesAtIndex` has no `{Exif}`, `{GPS}`, `{TIFF}`, `{IPTC}`, `{MakerApple}` or other maker dictionary; `CGImageSourceCopyMetadataAtIndex` is nil or empty; no orientation other than 1; one image and no auxiliary data; and a byte scan finds no `Exif\0\0`, `http://ns.adobe.com/xap`, `Photoshop 3.0` or APP segments other than APP0. Pixels are visually upright (a known asymmetric fixture).
14. Size bounds: every output within 2,048 px, 3.2 MP and 1,500,000 bytes, or refused; crops under 480 px refused.

Section 17.8 adds eleven contract tests from the architecture gate (tests 15 to 25).

### 12.6 Reader v3 freeze

`ReaderV3FreezeTests` pins every file of `NutritionLabelParsing` and, in `FoodLedgerApplication`, `PastedLabelManifest.swift`, `PastedLabelManifestV2.swift`, `LabelReading.swift`, `PastedLabelSource.swift`, `PastedLabelConfirmation.swift`, `PastedLabelBasisChoice.swift`, `PastedLabelServingPolicy.swift` and `PastedLabelServingSizeGrammarV3.swift`, plus `FoodLabelTextCapture/NutritionLabelTextReader.swift` and the fresh-set harness. **None changes.** The photo route only calls, from the pure reader target `FoodLabelPhotoReading` (never from `FoodLedgerApplication`, which cannot import the parser; 17.1): `LabelDeclineGate.evaluate` / `apply`, `LabelArithmeticChecksV2.check`, the conversions in `PastedLabelConversions`, `PastedLabelBasisOptions.options(for:)`, and the pasted identity mapping and launch scope. Because `PanelSourceAdmission.admitted` and `LabelReading.Origin` are in pinned files, P19 and P20 add new types instead. The test must pass unchanged.

## 13. Phasing (one PR per phase; nothing sends before L5)

| Phase | Content | Egress |
|---|---|---|
| L0 | Offline locate-rate measurement (6.1, with the inputs and method of 17.6); report found rate and how many silent errors would be not found. **Done 25 October 2026 (17.9)** | None |
| L1 | Pure core: wire mapping port, `LabelPhotoReading`, attention, serving, manifest, verifier, composite admission, retry and spend policies, tests 1 to 12 | None |
| L2 | Image preparation and Vision locator, tests 13 and 14 | None |
| L3 | OpenRouter adapter and route checker against a fake transport only | None |
| L4 | UI: source, crop, Label photo screen, Confirm photo pane and attention, with the fake transport in UI tests | None |
| L5 | E13 qualification (owner-run, approved), then wire the live transport with the section 11 policy updates | As approved |

## 14. Test plan

- **Pure**: 12.5 tests 1 to 12, plus copy mapping for every decline and failure code.
- **View model**: Read label disabled in every blocking state; first-use sheet once; Cancel during Reading and Retrying; Try again is a new tap and counts toward the limit; focus requests from value rows; attention resolution enabling Log; Retake resets answers and corrections after confirmation; fortification C1 to C12 behaviour unchanged on this route.
- **Simulator UI** (fake transport via a launch argument, never the network; photos from the library seeded with synthetic Taiwan label images rendered from the evaluation's synthetic template, never real user photos): the journey of section 4 at default and AX5 sizes; a read with two not-found values blocks Log until resolved; zoom, pan and focus; each 7.2 state through the fake; VoiceOver labels on the pane and attention actions.
- **Device (owner)**: one real label through the camera after approval, comparing the saved values with the pack; the simulator proves software behaviour only.

## 15. Journey QA checklist (#316)

- [ ] Add food shows Photo of nutrition label with its subtitle.
- [ ] Take photo asks for camera permission only when chosen; denied shows the 7.2 copy with the library offered.
- [ ] Choose from library opens the system picker with no library permission prompt.
- [ ] Crop screen: corners drag, pinch and pan work, Rotate turns 90°, a tiny crop is refused with the 7.2 copy.
- [ ] Label photo screen shows the crop, Name, Brand, the egress statement and Read label with AI; the button is disabled with no name.
- [ ] No key, key not validated, offline and daily limit each show their copy and disable the button.
- [ ] First read shows the one-time sheet; Not now sends nothing; later reads do not show it.
- [ ] Reading shows progress and Cancel; a fake busy reply shows Retrying with the attempt count.
- [ ] Each declined and failed state shows its copy, keeps the photo, and offers Paste nutrition label and Search foods.
- [ ] Confirm order: Food, Fortification, Amount eaten, Label photo, Nutrition from the photo, remainder.
- [ ] The honesty note is always shown; no confidence or "verified" wording anywhere.
- [ ] Pinch-zoom, pan, double-tap and Fit work; Full screen keeps the highlight.
- [ ] Tapping a value zooms to its region with an outline and a caption; a not-found value says so.
- [ ] Not-found and check-failed values are highlighted in words, not colour alone; Log stays disabled with the pinned bar until each is resolved.
- [ ] Matches the photo, Correct and Leave unknown each resolve an item; Leave unknown shows "Left unknown" and saves unknown.
- [ ] Fortification behaves exactly as on the pasted route.
- [ ] Log saves once; the saved entry shows the photo and "Read by <Model> on <Provider> through OpenRouter, …; checked by you".
- [ ] Developer tools show the manifest versions, model, provider, cost and per-value states.
- [ ] 44 pt targets, VoiceOver on every control, no truncation at AX5, British spelling, no emoji.

## 16. Not changing

Reader v3 and every frozen file; the pasted route; the catalogue and web review routes and their egress; HealthKit (read-only); the Daily JSON health export; the food daily export's fields (17.4); the existing OpenRouter food provider and its routes.

## 17. Architecture gate findings applied (25 October 2026, on `3b950f72`)

The gate returned **PASS WITH CHANGES**. Each finding is applied below and overrides any earlier sentence it narrows; none widens an approved egress term.

### 17.1 H2: the application never imports the parser; no replay at verification

`FoodLedgerApplication` may import only CryptoKit, Foundation and `FoodLedgerDomain` (the `check_imports FoodLedgerApplication` line of `check-boundaries.sh`). So:

- The candidate projection is application-owned: the photo manifest reuses the pasted manifest v2 candidate type (`PastedLabelManifest.Candidate` and its nested types, used from the pinned file, not changed), so stored candidate, stored basis, expected nutrients, corrections and basis options work on one shape.
- The mapping, gate, conversions and checks run only in `FoodLabelPhotoReading`, which hands the application a `LabelPhotoReading` built on that projection.
- The verifier checks the **stored** candidate, as the pasted verifier does, and never re-runs the mapping. Replay of `wire_text` to the stored candidate is a contract test at the reader (test 16). If replay were ever wanted at verification, it would be a consumer-owned port that fails closed when no conformer is wired; v1 does not add it.

### 17.2 H3 and L1: platform code stays in adapters; boundary script edits

- `FoodLedgerPresentation` keeps its allow-list (`Foundation|FoodLedgerApplication|FoodLedgerDomain|SwiftUI|WebKit`, near line 226). Camera, `PhotosPicker`, the crop screen and the zoom, pan and highlight photo view live in a new target **`FoodLabelPhotoUI`** (SwiftUI, UIKit, PhotosUI, `FoodLedgerApplication`, `FoodLedgerDomain`), wired at the composition root as `FoodBarcodeCapture` is. Presentation asks for "choose a photo", "crop" and "show this image focused on this region" through application-owned closures or an injected view factory; regions and crops are application types.
- The crop crossing `LabelImagePreparing` is a pure `LabelCropRect` (normalised `x`, `y`, `width`, `height` in 0...1, validated, plus a quarter-turn count), never `CGRect`.
- `check-boundaries.sh` edits, made in L1 with matching self-test fixtures:
  - new lines `check_imports FoodLabelPhotoReading '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'`, `check_imports FoodLabelPhotoCapture '^(CoreGraphics|CryptoKit|Foundation|ImageIO|Network|UniformTypeIdentifiers|Vision|FoodLedgerApplication|FoodLedgerDomain|FoodLabelPhotoReading)$'` and `check_imports FoodLabelPhotoUI '^(FoodLedgerApplication|FoodLedgerDomain|PhotosUI|SwiftUI|UIKit)$'`;
  - the `NutritionLabelParsing` importer regex (near line 82) admits `Sources/FoodLabelPhotoReading` and `Tests/FoodLabelPhotoReadingTests`;
  - an importer rule like the `FoodLabelTextCapture` one (near line 89) for each of `FoodLabelPhotoReading`, `FoodLabelPhotoCapture` and `FoodLabelPhotoUI`: only the composition root and the target's own tests import it, and `FoodLedgerPresentation` never does;
  - the `Package.swift` dependency rule (near line 111) covers the three targets and their allowed dependents, and the link rule (near lines 119 and 120) also refuses an app target that links `FoodLabelPhotoReading` directly;
  - self-test negative fixtures, beside the existing ones (near lines 174 to 209): presentation importing `FoodLabelPhotoUI`, `PhotosUI` or `ImageIO`; application importing `NutritionLabelParsing` or `FoodLabelPhotoReading`; a `Package.swift` edge from presentation to a photo target. Each must fail.
- Within `FoodLabelPhotoCapture` each framework is confined to its adapter file: ImageIO and CoreGraphics to the preparer, Vision to the locator, Network to the connectivity adapter, URLSession to the OpenRouter transport. A script check fails on any other file importing them.

### 17.3 H1: one atomic Log

- On Log, the save use case **first** persists the image bytes through `EvidenceAttachmentStoring.persist`, then makes **one** ledger commit holding the image evidence, the manifest evidence, the release and the log records.
- If policy or the verifier rejects the save, or the commit fails, it calls `removeIfUnreferenced` on the descriptor. Nothing is committed before Log.
- `FoodLedgerService.recordEvidenceWithAttachment` (`FoodLedgerService.swift`, near lines 176 to 210) commits evidence on its own, so this route **must not** call it; it reuses that function's descriptor-and-evidence construction inside the single commit.
- Test 15 proves it.

### 17.4 H4: Q2 decided; export and every manifest-keyed site

**Export, option (a).** Photo values are `user_verified_panel` without a pasted-label manifest, so the food daily export's closed rule gives `label_checked_by_you` (and `entered_by_you` for corrected or entered values, through `manual_declaration`), with `source_release_id` `label-photo-ai:<manifest SHA-256>`. This is **no field change**, recorded in [food daily export v1](food-daily-export-contract-v1.md). Photo-specific per-value origins (found, checked, corrected) are deferred to the food export v2 issue #312.

**Sites keyed on `PastedLabelEvidenceManifest.isVersion`, and what each does for a photo entry.** Photo evidence has `captureMethodVersion` `label-photo-ai-v1` or `label-photo-preparation-v1`, never a pasted version, so each returns its "other route" answer:

| Site | Pinned? | For a photo entry | The photo route's own handling |
|---|---|---|---|
| `PastedLabelSource.swift:138` (pasted `verify`) | Yes | Not reached: `LabelSourceAdmission` sends photo candidates to the photo verifier | `LabelPhotoSource.verify` |
| `PastedLabelSource.swift:528` (`PanelSourceAdmission.applies`) | Yes | False on the evidence clause; true if any value claims `user_verified_panel`, which is why the composite routes first | `LabelSourceAdmission.applies` (fortification scope, per 100 mL default) |
| `PastedLabelServingPolicy.swift:196` (serving manifest lookup) | Yes, untouched | nil, so no pasted serving applies | `LabelPhotoServingPolicy` (P10) |
| `NutrientValueOrigin.swift:89` (`PastedLabelValueOrigins.manifest`) | No | nil, so the export uses its "without a pasted-label manifest" row (`label_checked_by_you`) | Confirm and saved-entry origins come from the photo manifest's own projection; the export is unchanged |
| `CanonicalFoodArchive.swift:111` (`minimumContractVersion`) | No | Not matched | A new first check returns 8 when `label-photo-ai-v1` evidence exists (17.7) |

L1 re-runs `rg 'isVersion|captureMethodVersion'` and adds any further site to this table before merging.

### 17.5 M2, M3 and M4: attention, catalogue check and spend

**Attention (M2).** `label-photo-attention-v1` is in the manifest and the pipeline string. The per serving against per 100 check is versioned as `label-photo-serving-consistency-v1` (the per serving value equals the per 100 value times the serving grams over 100, within the printed rounding of the evaluation's section 7), because it is not part of `label-arithmetic-checks-v2`. The verifier **recomputes** the attention set from the stored `locations`, `flags_shown` and recorded check outcomes (`warnings_shown`) under the stored attention version, and requires it to equal the stored `attention` items exactly, each with a resolution. It does not re-run the checks (17.1).

**Catalogue check (M3).** E7's runtime check runs on the **first Read tap of a session, before the image is sent**: a GET of the model's public endpoint listing with **no Authorization header** and no user data. A mismatch or failure ends the tap with the "route unavailable" copy and nothing is sent; a pass is cached for the session. The egress row in 11.1 states it.

**Spend (M4).**

- Every attempt that sent bytes is counted, including one cut by Cancel: its reported `usage.cost` when reconciled, otherwise its worst case.
- **The approved $0.05 is a total per tap, across all attempts.** Before each attempt the reader computes its worst case W, 6,000 input tokens at the day's prompt price plus `max_tokens` at the completion price (plus the reasoning limit as well, if the endpoint bills reasoning tokens outside `max_tokens`; L3 confirms the endpoint's semantics and test 21 pins W), and does not start the attempt if W exceeds $0.05 less what the tap has already been charged (reported cost, or W for an attempt with no reported cost). A retry happens only when the remaining budget covers a whole worst-case attempt.
- The request golden pins `max_tokens` **1,200** and an explicit `reasoning` limit of **500** tokens, sized from the evaluation's median Gemini cost. At the catalogue prices recorded for Gemini 4 Argon ($2 and $10 per million tokens), W is about $0.024, so an unreported failure leaves room for one retry; if reasoning is billed separately W rises to about $0.029, so after a failure with no reported cost no retry fits and the rule stops the tap (a failure whose cost is reported, often as zero for a rejected request, still leaves room). E13 measures the 6,000-token input ceiling and the truncation rate at 1,200; any change is a new route version within the same $0.05.
- **Input ceiling, fail closed.** A reply whose reported `usage.prompt_tokens` exceeds 6,000 means the worst case was understated, so the route pauses for the rest of the local day (the same state and copy as a per-call cost over $0.05) and the read's answer is still shown for checking. Test 26.
- The daily caps are unchanged (E10): a tap with any attempt lacking a reported cost counts as $0.05 toward the daily $0.50.
- **Provider-overloaded answer** (E11): an OpenRouter error object whose numeric `code` is 502, 503 or 529, in an HTTP error reply or an HTTP 200 envelope, with no `choices`. Nothing else is retried on content grounds.

### 17.6 M5: L0 inputs and method

- Route C answers: the saved untouched and development outputs in the evaluation's log directory outside the repository (evaluation section 9.8; `results/untouched-taiwan-v1.json` in the repository holds case IDs only).
- Route B: the raw outputs of `vision_v3.swift`. L0 first checks whether they store observation geometry. If not, L0 **re-runs Vision locally** (no egress) on the photos after the E3 preparation, through the **shipped Swift matcher** of `VisionLabelValueLocator` driven by a small command-line harness, not a Python lookalike.
- L0 reports found, not-found and ambiguous rates per cell over correct cells, and for each silent-error case of the correction-effort analysis whether it would have been an attention item.

### 17.7 M1: migration and contract version

- Migration `v8_label_photo` changes metadata only, as `v7_pasted_label` did: no table, no column, no rewrite.
- `foodContractVersion` 8; `minimumContractVersion` is 8 only when the records hold `label-photo-ai-v1` evidence, and otherwise exactly as today (6 or 7), so existing export bytes are unchanged.
- A contract-7 binary refuses a contract 8 archive through its existing newer-archive decline.
- Test 18 proves it.

### 17.8 M6, L2 to L4 and the added contract tests

**Image (M6).** The output has no APP segment except APP0 (JFIF) and, only if a profile is kept, one APP2 `ICC_PROFILE` equal by SHA-256 to a pinned sRGB profile. v1 strips the profile and writes untagged sRGB, so APP2 is absent. `PreparedLabelImage` (bytes, dimensions, SHA-256) has an internal initialiser and is constructible only by the preparer; the request builder accepts only that type.

**Directories (L2).** A composition-root test proves the attachments root and the file-backed spend ledger both sit under the backup-excluded, file-protected health-data directory.

**Conformance and freeze (L3).** Any conformance of the pinned `LabelReading` to the shared Confirm sections protocol is a retroactive extension in a new file; `LabelReading.swift` is untouched. Once L1 lands, a photo freeze test pins the mapping v1, serving v1, the locator matcher, attention v1 and the manifest codec by SHA-256, in the style of `ReaderV3FreezeTests`.

**Failure modes (L4).**

- An unreadable or corrupt spend ledger fails closed: the route shows the daily limit state and sends nothing.
- A save while protected data is locked shows `Your food log is locked while the iPhone is locked. Unlock it and tap Log again.`, keeping the photo, answers and corrections.
- The daily reset follows the injected calendar and time zone.

**Added contract tests (written first), numbered after 12.5:**

15. **Atomic Log (H1):** a policy-rejected save, a verifier rejection and an injected commit failure each leave no evidence row, no release and no file under the attachments root; a successful Log makes exactly one commit.
16. **Mapping replay at the reader (H2):** for every saved route C output, `wire_text` maps to the stored candidate byte for byte; the application verifier passes with no parser linked.
17. **Boundaries (H3, L1):** every negative self-test fixture of 17.2 fails the script, and the baseline passes.
18. **Contract version and migration (M1):** contract 6 and 7 export goldens byte for byte; a photo archive exports as 8; an 8 archive into a 7 reader declines cleanly; migration from v7 keeps every row's bytes.
19. **Export (H4):** a photo entry's food daily export golden shows `label_checked_by_you` and `entered_by_you` with a `label-photo-ai:` release ID and no new key; every 17.4 site returns its stated answer for photo evidence.
20. **Attention recomputation (M2):** a manifest with an attention item removed, added, or with a changed reason or version is rejected at save and at reopen.
21. **Spend per tap (M4):** attempts with reported, unreported and cancelled costs; no attempt starts past the $0.05 tap budget; the request golden pins `max_tokens` 1,200 and the reasoning limit of 500; the overloaded answer is exactly the 17.5 definition.
22. **Catalogue check (M3):** runs once per session on the first tap, before any image request, with no Authorization header and no body; a failure sends nothing.
23. **Image hardening (M6):** positive controls assert each fixture **contains** GPS, MakerApple, XMP, depth data and a gain map before preparation; output APP segments are as stated; `PreparedLabelImage` cannot be built outside the preparer (a compile-time test); the request's data URI decodes to exactly the prepared bytes.
24. **Directories (L2):** the attachments root and the spend ledger sit under the backup-excluded directory.
25. **Failure modes and freeze (L3, L4):** an unreadable ledger reports the limit reached; the locked-data save copy; the reset by the injected calendar; the photo freeze test.
26. **Input ceiling (17.5):** a reply reporting 6,001 prompt tokens pauses the route until the injected calendar's next local day; 6,000 does not; a pause survives relaunch through the spend ledger.

### 17.9 L0 result (25 October 2026, no egress)

Run once on this Mac (macOS 27.0.1, Vision revision 3, accurate, `zh-Hant` and `en-US`, language correction off) with `Tools/NutritionLabelCaptureEvaluation/l0_locate.py` and the Swift tool `Tools/LabelPhotoLocateL0`. Inputs, as 17.6 names them: the saved route C answers of the untouched run (`~/WHR-label-eval-private/runs/untouched-v1/<arm>/untouched/*.eval`) and of the development run (`runs/route-c-dev`), and the public Open Food Facts Taiwan photos in `~/WHR-label-eval-private/off-taiwan-v1/`, matched by SHA-256. The stored route B outputs carry no per-substring geometry, so Vision was re-run locally on the E3-prepared bytes. Photos are used uncropped (they are already panel photos). Assisted view (the product design); attention uses the draft attention rules (not found or ambiguous, a failed arithmetic or consistency check, a G3 or G4 flag). Counts and case IDs only: [`results/l0-locate-rate-v1.md`](../Tools/NutritionLabelCaptureEvaluation/results/l0-locate-rate-v1.md).

| Untouched Taiwan, E3 as specified | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Photos refused by the 480 px short-edge minimum | 8 of 40 | 8 of 40 | 8 of 40 |
| Pre-filled tables | 29 | 30 | 32 |
| Correct values found on the photo | 356 / 479 (74.3%) | 345 / 487 (70.8%) | 375 / 505 (74.3%) |
| Correct values not found / ambiguous | 54 / 69 | 69 / 73 | 57 / 73 |
| Silent wrong values that became attention items | 4 of 4 | 1 of 3 | 29 of 44 |
| Silent-error tables fully caught | 1 of 2 | 1 of 2 | 2 of 4 |
| Tables opening with no attention item | 3 of 29 | 3 of 30 | 3 of 32 |
| Attention items per table, median / p90 | 3 / 13 | 3 / 13 | 3.5 / 15 |
| Serving lines found | 40 / 58 | 42 / 60 | 44 / 64 |

With the 480 px minimum lifted (sensitivity only), Gemini 4 Argon pre-fills 37 tables, finds 443 of 603 correct values (73.5%) and catches all 4 silent wrong values (1 of 2 silent-error tables fully); Sol finds 70.7% and catches 2 of 4. On the 15 development photos (12 pre-filled, 3 refused by the minimum) Gemini finds 74.7% with no silent error.

**Reading.**

- The found rate (71 to 74%) is just above the 70% line of 6.1, so P12 stands; but with a median of 3 and a p90 of 13 attention items per table, and only about 1 table in 10 opening clear, it costs more taps than the correction-effort analysis suggested. Ambiguity (repeated values such as 0公克 where a row label is not found exactly once) is the largest source.
- For the arm the contract chose, every silent wrong value Gemini 4 Argon made became an attention item. One silent-error table stays partly silent because its wrong serving line was found on the photo, which a locator cannot catch.
- The 480 px minimum refuses 8 of the 40 public photos, small crowd-sourced panel crops; Gemini read those 8 with no silent error. Camera photos will rarely be that small, but screenshots may.

**What L1 needs from this.**

1. Reduce ambiguity in `label-photo-vision-locate-v1` **before** it is frozen (L3): for example resolve a repeated value by its order within its column when the row labels are read in the same order. Re-run L0 after the change and keep the version string, since nothing has shipped.
2. **Decided (coordinator, under the owner's delegation, 25 October 2026):** the P5 short-edge minimum becomes **240 px**, to be confirmed by E13, because the evaluation's models read these photos. It is not an egress term. L0 measured 480 px; the L1 re-run uses 240 px.
3. Port the attention draft of `l0_locate.py` (`table_result` and `arithmetic_attention`) into `label-photo-attention-v1` exactly as measured here, so the L0 counts describe the shipped rules.
4. Keep the L0 numbers in the E13 report beside the ZDR-endpoint run, re-measured on that run's answers.
