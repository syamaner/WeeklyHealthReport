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
| P5 | **Size.** After crop: long edge at most **2,048 px** and at most **3,200,000 px** in total, JPEG quality 0.85; if the encoded file exceeds **1,500,000 bytes**, re-encode at 0.75 then 0.65; if still over, the read is refused with the copy in 7.2. A crop whose short edge is under **240 px**, before or after scaling, is refused as too small (lowered from 480 px after L0, 17.9; to be confirmed by E13), and a crop whose sides differ by more than **8 times** is refused as too narrow (17.17) | As stated; 2,048 px keeps small Chinese print legible. **The evaluation sent full-size images**, so section 10 E13 re-qualifies at this size before release | Approved (E3); minimum decided 25 October 2026 (17.9) |
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
2. Find every **row label** and every **header** of the table that occurs exactly once. A row label may not be preceded by a letter or ideograph, so 脂肪 is not found inside 飽和脂肪; a header needs only to occur once, because headers are often printed on one line (17.10).
3. Candidates for a value come from **value tokens**, read the same way from the model's text and from every recognised line: a sign (- or − straight before the number, unless it is the second value of a range), a comparator (<, ≤, ≦, >, ≥, ≧, less than, 少於, 未滿, 低於, 小於, 不足, 不超過, 大於, 高於, 超過 before the number, 以下, 以上, 以內 after its unit), the number (digits, a point between digits, and a comma between digits, so 1,234 is one number), and a unit from a closed list (kcal, kJ, 大卡, 千卡, 千焦, g, 公克, 克, mg, 毫克, μg, mcg, 微克, ml, 毫升, kg, 公斤, l, 公升, %). A value is a candidate only where a printed token has the **same comparator, number and unit**; a token that is part of a range (25-30公克, 25公克~30公克, 25至30公克) never matches. So a different unit on the same line, a dropped or added comparator or sign, a dropped or added decimal point, a number inside a longer number and a value inside a range are never found.
4. When the value's row label was found, keep only candidates whose **nearest row label** (by vertical centre) is that label; when its header was found, keep only candidates whose **nearest header** (by horizontal centre) is that header. Nearest, not a fixed band, because Vision often reads the label column and the value columns as separate lines and photos are often tilted. **Row distance limit:** a candidate counts as the row's value only when its vertical offset from the label is under **1/3** of the local spacing (the gap to the nearer neighbouring label; the one neighbour at the table's edges). A candidate nearest the label but further off has drifted: it makes the value **ambiguous**, never found. **Unlisted column:** when the reading has one value column, a row that holds more number tokens (outside its label) than the reading lists for it has a second column the reading does not know, so a match there is ambiguous, not found. **Column not confirmed:** when the reading has more than one value column, a value is found only when at least two headers are located and its own header is one of them; otherwise it is ambiguous. **Own label not located:** when the value's own row label is not located exactly once (for example the model misspells it, or no row label is located at all), or it is the only label located so no spacing can be measured, the value is **never found**: candidates near another located label are dropped as that row's, and any candidate makes the value ambiguous, whether or not some remain. Serving lines, which carry their own words, are unaffected.
5. Exactly one candidate left: **found**, with its bounding box (normalised to the image, rounded to four decimals). Several: **ambiguous**. None: try the **number alone**, only for a printed token with the same comparator and number, no unit, that ends its line, and only when a line just to its right in the same row band reads as the model's unit (Vision read the unit on its own line); without that unit line the value is ambiguous. A model value with no unit is never found (ambiguous). If nothing matches, **not found**. Serving lines match by their whole text bounded by non-digits (no digit, point or comma either side), or by their quantity's token with its unit. Ambiguous and not found are both shown as "Not found on the photo".
6. **Order within the column** (17.10): only a value that step 5 left **ambiguous** can be placed by rank, never one found or not found. Its text must repeat in a known column (the reading has one value column, or the headers separate them), the column must hold exactly as many occurrences of the text as the reading has values with it there, every one of those values must have its row label found exactly once with the labels running top to bottom in the reading's row order, and the occurrence of its rank must be one of its own step 4 candidates, within the row distance limit of its own label, on a row with no unlisted number. Otherwise it stays ambiguous.

**Precondition.** The reading lists each column's values in the table's printed row order, top to bottom, as the model's rows are. The order pass checks this against the row labels found on the photo and places nothing when they disagree or cannot be checked.

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
+| OpenRouter and its one allow-listed model endpoint (ZDR, data collection denied, no fallbacks) | One cropped, downscaled label photo re-encoded with all metadata removed, plus a fixed instruction and output schema; no name, brand, food log, health data or identifiers | Only when the user taps Read label with AI on the Label photo screen, with the user's own validated key; on the first tap of a session, and on the first tap of each new local day, two catalogue requests (the model's endpoint listing and the ZDR endpoint listing) with no key and no user data first confirm the endpoint; at most 3 attempts for retryable failures and $0.05 in total per tap; at most 30 reads and $0.50 per day | [label-photo-ai-prefill-v1.md](label-photo-ai-prefill-v1.md) |
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

presentation → application → domain; `FoodLabelPhotoReading` → application, domain, `NutritionLabelParsing`; `FoodLabelPhotoCapture` → application, domain, `FoodLabelPhotoReading`, Apple frameworks. `check-boundaries.sh` gains `check_imports FoodLabelPhotoReading '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'` and an allow-list for `FoodLabelPhotoCapture` (`Foundation|ImageIO|CoreGraphics|UniformTypeIdentifiers|Vision|Network|CryptoKit|FoodLedgerApplication|FoodLedgerDomain|FoodLabelPhotoReading`), plus the importer rules of 17.2: `FoodLabelPhotoCapture` is imported only by the composition root and its tests, and `FoodLabelPhotoReading` only by its own tests, `FoodLabelPhotoCapture` and that adapter's tests (the app is never linked to it directly); `NutritionLabelParsing` is still imported only by its existing users and `FoodLabelPhotoReading`. The OpenRouter key store stays in `FoodGenericSearch` and is passed in through the existing `FoodWebKeyStoring` port.

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
| L1a | Matcher ambiguity reduced (order within the column, headers on one line), L0 re-run at 240 px, matcher moved unchanged into `FoodLabelPhotoReading` with a hash pin, boundary script for the new target (17.10) | None |
| L1c | Locator v2 (17.11), before L1b at the owner's request ("Let's try to resolve"): row labels recovered between located neighbours, columns inferred from value tokens, a table-wide offset; measured by L0 against v1 with the adversarial suite and an extended sweep; and the alternative attention policy measured, not adopted. **Done 25 October 2026** | None |
| L1d | Locator v3 (17.15): each header's basis passed to the matcher; only the amount headers must be located, the reference-intake column confirmed by its % unit and position, never as an amount column; a per-serving header with its bracketed serving quantity (D4); attack scenarios first, measured by L0 against v2 as pinned | None |
| L1b | Pure core: wire mapping port, `LabelPhotoReading`, attention v1, serving v1 with its parity test, manifest codec, verifier, composite admission, preparer types, retry and spend policies, tests 1 to 12 | None |
| L2 | Image preparation and Vision locator, tests 13 and 14 (17.17) | None |
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
  - an importer rule like the `FoodLabelTextCapture` one (near line 89) for each of `FoodLabelPhotoCapture` and `FoodLabelPhotoUI`: only the composition root and the target's own tests import it, and `FoodLedgerPresentation` never does. `FoodLabelPhotoReading` is narrower (built in L1a): only its own tests, `FoodLabelPhotoCapture` and that adapter's tests import it, because the app is never linked to it directly (next item), so the composition root reaches it through the adapter;
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

L1 re-runs `rg 'isVersion|captureMethodVersion'` and adds any further site to this table before merging. L1b re-ran it (17.16): the further sites are `ReviewedFoodProposalConfirmation.swift:361` and `:415` and `CanonicalFoodArchive.swift:120`, which match only `label_text` evidence of a reviewed web version, so none matches photo evidence (`package_image`, `label-photo-ai-v1` or `label-photo-preparation-v1`); each returns its "other route" answer.

### 17.5 M2, M3 and M4: attention, catalogue check and spend

**Attention (M2).** `label-photo-attention-v1` is in the manifest and the pipeline string. The per serving against per 100 check is versioned as `label-photo-serving-consistency-v1` (the per serving value equals the per 100 value times the serving grams over 100, within the printed rounding of the evaluation's section 7), because it is not part of `label-arithmetic-checks-v2`. The verifier **recomputes** the attention set from the stored `locations`, `flags_shown` and recorded check outcomes (`warnings_shown`) under the stored attention version, and requires it to equal the stored `attention` items exactly, each with a resolution. It does not re-run the checks (17.1).

**Catalogue check (M3).** E7's runtime check runs on the **first Read tap of a session, and on the first tap of each new local day, before the image is sent**: two catalogue requests (the model's endpoint listing and the ZDR endpoint listing), each with **no Authorization header** and no user data. A mismatch or failure ends the tap with the "route unavailable" copy and nothing is sent; a pass is cached for the rest of that local day in the session. The egress row in 11.1 states it.

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

### 17.10 L1a: matcher ambiguity and the L0 re-run at 240 px (25 October 2026, no egress)

**Matcher changes** (still `label-photo-vision-locate-v1`, since nothing has shipped; pinned from here by `LabelPhotoFreezeTests`):

- **Headers by containment.** Headers are often printed on one line ("每份 每100公克"), where the label rule refused the second header, so the column filter never ran. Headers now need only to occur exactly once; row labels keep the label rule.
- **Order within the column, ambiguous values only.** A value the first pass left ambiguous whose text repeats in its column (such as 0公克) is placed by rank under the conditions of 6.1 step 6: a known column, equal counts, every such value's row label found once and in the reading's row order, and the rank's occurrence among the value's own candidates. It never changes a found or not found value.
- **Row distance limit and unlisted column (re-check of #320, decided as safety first).** The re-check found that nearest-row assignment had no distance limit, so on a tilted photo a wrong value could be found on the neighbouring row's identical text, and a one-column reading could meet a second value column it does not list. Step 4 of 6.1 now limits the offset to 1/3 of the local label spacing and treats an unlisted number on a one-column row as ambiguity. The coordinator asked for "about 0.4"; 1/3 is used because the reviewer's tilt case (drift 0.05 at spacing 0.08) puts the wrong row's value 0.375 of a row away, which 0.4 would accept. The three adversarial cases (that tilt, values exactly half a row low with compensating errors, an unlisted second column) are regression tests expecting not found or ambiguous, and the order pass also requires its placed box within the limit on a row with no unlisted number.
- **Values compared as tokens, and the mutation sweep (final re-check of `145f0c34`).** The reviewer's sweep (6 synthetic layouts, 3,297 single-model-error mutations) found six roots of false found: the number-alone fallback ignoring a unit on the same line (R1), a preceding comparator not rejected (R2), a comma not treated as part of a number (R3), a leading minus dropped (R4), two columns with no confirmed header (R5) and serving lines matched by plain containment (R6). Values are now compared as tokens (6.1 step 3), the number-alone fallback needs the model's unit read just beside the number, a reading with no unit is never found, a value in a multi-column reading needs its own located header, and serving lines use the bounded rule. The sweep is ported into `FoodLabelPhotoReadingTests` as a contract test (`LabelValueMatcherSweepTests`): it asserts no false found outside the harness's own artefacts (its mutator treats the Han numeral 一 as a digit, and a wording-only serving change), no correct box moved, no side-effect upgrade, and baselines of 22/22 (two columns), 12/12 (one column, separate and merged lines), at least 20/22 and 11/12 with the unit split; two columns with unread headers are never found by design. Fourteen named regression tests cover S1 to S4 and the same family (decimal point, full-width digits and units, trailing digits, % values, kcal against kJ on one line, ranges, sign, the unit beside, a reading with no unit).
- **Own row label not located (re-check of `8ebfe912`).** With the value's own label not located, the first pass used to drop the row filter, so a model that misspelt the fat label (脂舫) and read saturated fat's 3公克 as fat's value had it found on the saturated fat row. The value is now never found without its own located label (6.1 step 4). The reviewer's case 10 and 10b and a no-labels-located case are regression tests expecting ambiguous; one earlier test gained a second located label so it still exercises the one-line headers.
- **Invariant review of #320 (BLOCK, fixed).** The first version of the order pass placed by counts and order alone and overrode found and not found values. The reviewer reproduced a swap (fat 0公克 and saturated fat 3公克 exchanged by the model) where it marked the wrong fat value as found on saturated fat's row, hiding a silent error; and with no header text on a two-column table it treated the whole photo as one column. Both are now regression tests (the swapped values are not found; the two-column case stays ambiguous), with a third for query order that differs from printed order (no placement). The matcher is re-pinned once, before anything shipped; the reading passes the number of value columns (`columnCount`).

**Re-run** with the decided 240 px minimum (P5), same inputs and method as 17.9, with the matcher as finally pinned: [`results/l0-locate-rate-v2.md`](../Tools/NutritionLabelCaptureEvaluation/results/l0-locate-rate-v2.md).

| Untouched Taiwan, Gemini 4 Argon | L0 (17.9; 480 px, first matcher) | L1a (240 px, pinned matcher) |
|---|---|---|
| Photos refused by the short-edge minimum | 8 of 40 | 3 of 40 |
| Pre-filled tables | 29 | 34 |
| Correct values found on the photo | 356 / 479 (74.3%) | 235 / 557 (42.2%) |
| Correct values not found / ambiguous | 54 / 69 | 76 / 246 |
| Silent wrong values that became attention items | 4 of 4 | 4 of 4 |
| Silent-error tables fully caught | 1 of 2 | 1 of 2 |
| Tables opening with no attention item | 3 of 29 | 1 of 34 |
| Attention items per table, median / p90 | 3 / 13 | 11 / 17 |
| Serving lines found | 40 / 58 | 39 / 68 |

On the same 29 tables at 480 px, the pinned matcher finds 41.1%. Sol finds 42.7% at 240 px and catches 4 of 4 silent wrong values; Luna 42.8% and all 52 of 52. On the 15 development photos Gemini finds 133 of 238 (55.9%), median 8.

**Reading.** v1 is now a strict corroborator: a value is "Found on photo" only when the same comparator, number and unit are printed on its own located row, within a third of the label spacing, under its own located header. Every safety step has narrowed it: 81.7% (blocked order pass), 81.0% (fixed), 73.6% (1/3 distance limit), 61.8% (own label located), 42.2% (tokens, unit beside, column confirmed). A comparison run (not committed) shows the column rule alone costs 81 values (56.7% without it): on these photos the two headers are often not located exactly once. In exchange, the silent wrong values of all three arms are now flagged except one serving line, so a found value can be trusted; the cost is an attention median of 11 per table, with almost every table needing checks. Recovering found values safely is planned as phase L1c (recorded in L1b, not here): placing a misread or unlocated row label, and a header, by their order between located neighbours, as locator v2, measured by L0 against v1 with the same adversarial suite and the sweep.

### 17.11 L1c: locator v2 and the attention policy measured (25 October 2026, no egress)

The owner asked for the attention burden of v1 (a median of 11 values to check per table) to be resolved, so L1c ran before L1b. Two levers were measured on the same photos and the same truth as 17.10; counts and case IDs only in [`results/l0-locate-rate-v3.md`](../Tools/NutritionLabelCaptureEvaluation/results/l0-locate-rate-v3.md).

**Locator v2 (`label-photo-vision-locate-v2`).** Every v1 safety rule stays; v2 recovers rows and columns v1 could not confirm, and every recovered placement still has to pass the token rule (comparator, number, unit):

1. **Row labels not located exactly once** are placed between their located neighbours above and below (both required; never across a located label, never at the table's top or bottom edge), and only for a label whose values form one run of the reading: by its own text printed once between them; else by a line in the label column one character different from it (a near-miss; labels of two or more characters); else by the reading's row order, only when nothing at all was read in the label column between the neighbours (a line there is some other label, so the order cannot be trusted for that slot) and the gap fits the table's row step within a quarter.
2. **Columns whose headers were not located** are inferred from the x-positions of unit-bearing value tokens on located rows, when they split into exactly the reading's column count with gaps over 0.03 and more than twice the widest group, agree with any single located header, and the reading lists one header per column in left-to-right order (a stated precondition).
3. **A table-wide vertical offset** is estimated from values whose token is printed exactly once on the photo, and removed before the 1/3 row distance limit, only when at least three rows agree within 0.15 of a row (and at least three quarters of the contributing rows), and the offset is at least 0.1 of a row.

It also reports **evidence** for a value that is not found: its token printed only in another row or column (`elsewhere`), or a different token in its own located cell (`conflicting_in_cell`).

**Safety.** The reviewer's cases 1 to 10, S1 to S4 and the fourteen named regression tests still pass; case 10 is now not found rather than ambiguous (the misspelt 脂舫 is placed on the printed 脂肪 line, and the wrong value is plainly elsewhere). The ported sweep (`LabelValueMatcherSweepTests`) gained five layouts that attack recovery itself: labels misread by one character, labels not read at all, unread headers with missing labels, a table-wide drift of 0.45 of a row, and a one-column table with drift and misread labels. Over all eleven layouts it finds **zero false found** (only the harness's own artefacts), no moved box and no side-effect upgrade. The sweep caught two recovery faults while it was being built, both fixed before measurement: placing a label by row order into a slot where another (misread) label was printed, and placing a label the reading gives to two places. The reviewer's original harness, run on v2: 22/22, **22/22** (headers unread, from 2/22), 20/22, 12/12, 12/12, 11/12, 3,297 mutations, 18 findings, all artefacts.

**Results, untouched Taiwan at 240 px (current blocking policy, P12):**

| | v1 Gemini | v2 Gemini | v2 Sol | v2 Luna |
|---|---|---|---|---|
| Correct values found on the photo | 235 / 557 (42.2%) | 341 / 557 (61.2%) | 347 / 564 (61.5%) | 346 / 566 (61.1%) |
| Not found / ambiguous | 76 / 246 | 77 / 139 | 96 / 121 | 70 / 150 |
| Silent wrong values that need a check | 4 of 4 | 4 of 4 | 4 of 4 | 52 of 52 |
| Silent-error tables fully caught | 1 of 2 | 1 of 2 | 3 of 3 | 4 of 5 |
| Tables opening with nothing to check | 1 of 34 | 5 of 34 | 5 of 35 | 5 of 37 |
| Values to check per table, median / p90 | 11 / 17 | 6.5 / 17 | 7 / 17 | 8 / 17 |

On the 15 development photos v2 finds 79.4% (Gemini), median 2 and p90 9.

**The alternative attention policy, measured and not adopted.** Under it only items with evidence block Log (a gate flag, a failed check, or a contradicting token: `elsewhere` or `conflicting_in_cell`), while a value merely not located is a soft marker plus one table-level "I've checked against the photo". With locator v2:

| Untouched Taiwan | Gemini 4 Argon | GPT-6.1 Sol | Luna |
|---|---|---|---|
| Blocking items per table, median / p90 | 0 / 2 | 0 / 2 | 0 / 5 |
| Tables with no blocking item | 22 of 34 | 21 of 35 | 22 of 37 |
| Silent wrong values that would still block | **1 of 4** | **2 of 4** | **12 of 52** |
| Silent-error tables fully blocked | 0 of 2 | 2 of 3 | 0 of 5 |

**Reading and recommendation.** Locator v2 is the safe lever: it recovers about half of what the safety rounds took (42.2% to 61.2% found, a median of 11 to 6.5 values to check) while every silent wrong value still needs a check and the sweep stays at zero false found. The alternative policy would remove almost all blocking (median 0), but it lets most silent errors through as soft markers: 3 of Gemini's 4, 2 of Sol's 4 and 40 of Luna's 52 would no longer block Log, because for most of them the matcher sees no contradicting token on the photo, only an absent or unconfirmed one. **Recommendation: adopt locator v2 with the current blocking policy (P12) for v1 of the route.** If the median of 6.5 is still too much, the next lever is presentation, not policy: group the checks by row, show each beside its region, and make "Matches the photo" one tap per row, which the burden measure counts per value. The alternative policy is not recommended unless the owner accepts that most silent errors would rest on the table-level confirmation.

### 17.12 Locator v2 after the #321 review: recovery locates, never confirms (25 October 2026)

The review of #321 (BLOCK) reproduced, for every recovery mechanism of 17.11, a single model error that v2 then confirmed. The guiding principle now in the matcher: **recovery may locate (to zoom and highlight the region) and narrow candidates; "Found on photo" needs direct evidence**, which is the row's own label text located on the photo (once, or once between its located neighbours) and, with two or more columns, a located header agreeing with the column.

- **Offset:** only rows whose value sits within 0.45 of a row of its label contribute, and the centre must be within 0.45 too, so a reading shifted by a whole row can no longer move the table (it was accepted up to 0.75).
- **Near-miss labels:** a line that is itself a row label of another nutrient (the reading's labels, or a closed vocabulary of Taiwan and English row names such as 維生素B12) is never a near-miss; a label ending in a digit or Latin letter is not found inside a longer one (維生素B1 is not in 維生素B12). Values on near-miss rows are at most ambiguous.
- **Row-order placement:** values on such rows are at most ambiguous; the placement is refused when any value token between the neighbours sits off the expected row slots (a tall wrapped label).
- **Inferred columns:** they filter but never confirm; found needs at least one located header agreeing with its inferred group. A group may not hold two unit tokens of one row, and each group must be narrower than about one token width, so an omitted third column cannot merge two.
- **Evidence** (`elsewhere`, `conflicting_in_cell`) is reported only on rows whose own label is located and columns separated by located headers.
- When a value has exactly one candidate on an indirect row or an inferred column, it is ambiguous **with its region**, so Confirm can still zoom to it.

Both reviewer harnesses run clean on the pinned matcher: the base sweep (3,297 mutations, 18 findings, all its artefacts) and the attack harness (20 scenarios, A1 to A6, no false found and no false evidence on correct values). The attack scenarios are ported into `FoodLabelPhotoReadingTests` as `LabelValueMatcherAttackTests`; the sweep's recovery baselines now count only directly confirmed values (2/22 with headers unread, 16/22 with labels misread or missing).

**Results, untouched Taiwan at 240 px** ([`results/l0-locate-rate-v3.md`](../Tools/NutritionLabelCaptureEvaluation/results/l0-locate-rate-v3.md), replacing the 17.11 figures):

| | v1 Gemini | v2 Gemini | v2 Sol | v2 Luna |
|---|---|---|---|---|
| Correct values found on the photo | 42.2% | 334 / 557 (60.0%) | 340 / 564 (60.3%) | 339 / 566 (59.9%) |
| Ambiguous values / with a located region | 246 / 0 | 150 / 10 | 133 / 10 | 183 / 10 |
| Silent wrong values that need a check | 4 of 4 | 4 of 4 | 4 of 4 | 52 of 52 |
| Tables opening with nothing to check | 1 of 34 | 5 of 34 | 5 of 35 | 5 of 37 |
| Values to check per table, median / p90 | 11 / 17 | 6.5 / 17 | 7 / 17 | 8 / 18 |
| Evidence-only policy: silent wrong values still blocking | | 0 of 4 | 2 of 4 | 6 of 52 |
| Evidence-only policy: blocking items per table, median / p90 | | 0 / 2 | 0 / 2 | 0 / 5 |

Development photos: v2 Gemini finds 75.2%, median 2.

**Reading.** The found rate is almost unchanged by the review (61.2% to 60.0%): most of v2's gain comes from rows whose own label is located and columns a located header confirms, which still count. Recovery now rarely gives a single located candidate on these photos (10 ambiguous values per arm come with a region). The evidence-only policy is weaker than before (it would block none of Gemini's 4 silent wrong values), because evidence is now reported only where it is direct. **The recommendation of 17.11 stands: adopt locator v2 with the current blocking policy.**

### 17.13 Locator v2 after the #321 re-check: headers in their band, own header, whole words (25 October 2026)

The re-check of `a371b043` confirmed the 17.12 fixes and reproduced four more single-model-error false founds, all fixed:

- **B6, B6c: headers anywhere on the photo.** A header now counts as located only in the **header band**: above the top directly located row label and within about two and a half row steps of it, below any serving line printed above the table, next to a value token of a direct row, and on a line that carries no other value with a unit once the headers' own text is removed (so "每份 185公克", a serving line, is not a header line, while "每份 每100公克" and "每100公克" are).
- **B6b: any header instead of the value's own.** With two or more columns, found needs the value's **own** header located in the band; inferred columns only narrow candidates and choose the region to highlight.
- **B1: a label inside a longer word.** A CJK label followed by another ideograph is part of a longer word (糖 is not in 糖醇), except a known non-nutrient suffix (含量, 總量) or a unit written straight after the label.
- **B5: the offset window.** Rows contribute to the table-wide offset only within a third of a row, and the offset itself is at most a third of a row. A reading shifted by one whole row can be confirmed only if the values drift about two thirds of a row from their own labels, which is the irreducible limit of matching by position alone (the value is then nearer the wrong label than its own); v1 had the same limit. Evidence `elsewhere` is now reported only when every printed occurrence of the value is clearly on another direct row (not in the band between rows), so correct values drifted between rows no longer come back `elsewhere`.
- **Found while fixing (the sweep's side-effect check):** a row whose label is not located left a double gap that inflated the median row step, and with it the offset and the distance limit, so one model error elsewhere could upgrade correct values. The row step is now the lower quartile of the gaps between adjacent located labels, and no row's distance limit is wider than that step.

The reviewer's attack harness (A1 to A6 and B1 to B7, 39 scenarios) runs clean on the pinned matcher: no wrong value found and no correct value with contradicting evidence. The base sweep shows only its 18 artefacts with the original baselines (22/22, 2/22, 20/22, 12/12, 12/12, 11/12). All 39 scenarios are in `LabelValueMatcherAttackTests`; the sweep's drift layouts at 0.45 of a row now expect no confirmed values (beyond the offset window).

**Results, untouched Taiwan at 240 px** ([`results/l0-locate-rate-v3.md`](../Tools/NutritionLabelCaptureEvaluation/results/l0-locate-rate-v3.md), replacing 17.12):

| | v1 Gemini | v2 Gemini | v2 Sol | v2 Luna |
|---|---|---|---|---|
| Correct values found on the photo | 42.2% | 292 / 557 (52.4%) | 298 / 564 (52.8%) | 299 / 566 (52.8%) |
| Ambiguous values / with a located region | 246 / 0 | 196 / 44 | 179 / 44 | 223 / 42 |
| Silent wrong values that need a check | 4 of 4 | 4 of 4 | 4 of 4 | 52 of 52 |
| Tables opening with nothing to check | 1 of 34 | 3 of 34 | 3 of 35 | 3 of 37 |
| Values to check per table, median / p90 | 11 / 17 | 7 / 18 | 8 / 17 | 8 / 18 |
| Evidence-only policy: silent wrong values still blocking | | 0 of 4 | 2 of 4 | 6 of 52 |
| Evidence-only policy: blocking items per table, median / p90 | | 0 / 1 | 0 / 2 | 0 / 3 |

Development photos: v2 Gemini finds 64.7%, median 6.

**Reading.** Requiring each value's own header in the header band costs most of this round (60.0% to 52.4%): on these photos one of the two column headers is often not read, and those values are now ambiguous, though 44 of them come with a located region to zoom to. Every silent wrong value of every arm still needs a check. **Recommendation unchanged:** adopt locator v2 with the current blocking policy (P12); it still roughly halves the gap to v1's attention burden (median 11 to 7), and the region highlight shortens the checks it leaves.

### 17.14 Locator v2 after round 4: every header in place before a column confirms (25 October 2026)

Round 4 on `4fa597f6` confirmed A1 to A6 and B1 to B7 and found two more single-model-error false founds, both header confirmation, plus one low finding; all fixed:

- **C1:** a split serving line left 每份 alone in the header band; with the real headers unread and the model reversing them, the right column was found under 每份. **C2, C2b:** 每份 was located by containment inside the reference-intake header 每份參考值%, so a swapped reading was confirmed and correct values got a false `conflicting_in_cell`.
- **Fixes.** (1) A header line counts only when, after removing the reading's header texts, nothing but punctuation remains. (2) For found, the value's own header must sit directly above it, within about one token width. (3) With two or more columns, found and evidence require **every** one of the reading's headers located in the band, at distinct x positions in the reading's left-to-right order; one header alone, or headers out of order, confirm nothing, and inferred columns only narrow candidates and choose the region. **C7d:** a unit straight after a CJK label is accepted only when the unit ends the word (糖克數 is not the 糖 row).

**Round 5** on `5bb10927` held every header rule and found one more false found, **D1:** the order-within-column pass checked the row and the column but not the own header above the value. With three printed columns, a reading of two (both headers read in order) and an unheaded middle column holding 0公克 on three rows read under 每份, the first pass was rightly ambiguous, but the order pass counted the middle tokens as 每份's (nearest header) and placed all three. **Fix:** with two or more columns the order pass counts only tokens under the value's own header, and places a value only when its token sits under that header. D1 and its control D1b are regression tests; the fix left the L0 counts unchanged.

**Round 6** on `8353536e` held the order pass and found one last route, **E2** (low realism): the own-header test admitted any token within one token width of the header's centre, so a narrow unheaded column touching the 每份 column (or read on one line with it, "3公克 5公克") was found when the model read it under 每份, 8 of 8. **Fix:** the value's centre must lie within its header's x span, or the header's centre within the value's span; and with two or more columns the value's cell (its row, under its own header) must hold exactly one value token, which also closes a narrow column overlapping the header's span. Both apply to the first pass and the order pass; for evidence, the cell is the tokens under the own header, and a conflict is claimed only when no token in the wider column matches either. E2 at several positions and the merged-line variant are regression tests.

All six reviewer harnesses run clean on the pinned matcher: round 6 (A to E, 70 scenarios, and E2 swept from x 0.47 to 0.65), round 5 (63), round 4 (54), round 3 (39), round 2 (20), each with no false found and no false evidence on correct values; and the base sweep with only its 18 artefacts and its original baselines. All 70 scenarios are in `LabelValueMatcherAttackTests`.

**Results, untouched Taiwan at 240 px** (replacing 17.13; after the round-6 fix):

| | v1 Gemini | v2 Gemini | v2 Sol | v2 Luna |
|---|---|---|---|---|
| Correct values found on the photo | 42.2% | 207 / 557 (37.2%) | 214 / 564 (37.9%) | 214 / 566 (37.8%) |
| Ambiguous values / with a located region | 246 / 0 | 281 / 129 | 263 / 128 | 308 / 127 |
| Silent wrong values that need a check | 4 of 4 | 4 of 4 | 4 of 4 | 52 of 52 |
| Tables opening with nothing to check | 1 of 34 | 3 of 34 | 3 of 35 | 3 of 37 |
| Values to check per table, median / p90 | 11 / 17 | 14 / 18 | 14 / 18 | 13 / 19 |
| Evidence-only policy: silent wrong values still blocking | | 0 of 4 | 2 of 4 | 6 of 52 |

Development photos: v2 Gemini finds 55.5%, median 8. Before the round-6 fix the untouched counts were 39.0%, 39.7% and 39.6% found (medians 14, 14, 12); the stricter own-header test costs about two points.

**Reading.** With every header required, v2 now confirms fewer values than v1 did (37.2% against 42.2%) and leaves more to check (median 14 against 11), although 129 of its ambiguous values come with a region to zoom to. A comparison run (not committed) shows the header-above rule costs nothing; the cost is requiring all of the reading's headers, which on these photos often fails; the likely blocker, not yet measured case by case, is the reference-intake column's header (每日參考值百分比), often printed over two lines. Note that v1's lower bar is exactly what rounds 2 to 4 showed to be unsafe (one header, or a header found anywhere, could confirm a swapped column). **Recommendation:** keep v2 as pinned (safe), and as the next lever require only the reading's **amount** column headers (per serving, per 100 g or ml) to be located in order, with the reference-intake column confirmed by its % unit instead. That needs the reading to pass each header's basis to the matcher, a small API change, and its own attack scenarios (a % column mislabelled as an amount column, and the reverse) before it is measured.

### 17.15 L1d: locator v3, header bases (25 October 2026, no egress)

Round 4 left v2 requiring every header of the reading in the header band, and the likely blocker was the reference-intake column's header (每日參考值百分比), often printed over two lines (17.14). Under the owner's delegation (Option 2), v3 takes each header's basis and relaxes that one rule. Its attack scenarios were written before the change (`LabelValueMatcherReferenceIntakeTests`).

- **API.** `locate` gains `headerBases: [HeaderBasis]` (amount or reference intake), one per header, with an empty text for a header that has none printed. Without bases every column is an amount column, which is v2's rule, so existing callers are unchanged. L0 now passes every header with its basis.
- **Amount headers.** With two or more columns, found needs every **amount** header (per serving, per 100 g or ml) located in the band, with distinct texts, at distinct x positions in the reading's order. A reference-intake header need not be located; when it is, it must sit on its own side of every amount header, or nothing confirms.
- **Amount values.** An amount value needs its own header directly above it (round 6's span rule) and a unit other than %.
- **Reference-intake values.** A reference-intake value needs a % unit and a token outside every amount column, on the side the reading's column order gives it. When its own header is located, the value must sit under it; with more than one reference-intake column, that header must be located. It is never confirmed as an amount column.
- **Unlocated headers.** When any header of the reading is not located, the value's row may hold no more value tokens than the reading has columns, so a column the reading left out cannot be taken for one it has. The cell must still hold one token (round 6).
- **D4.** A header line may carry, besides the reading's header texts and punctuation, exactly one bracketed quantity equal to a quantity on the reading's serving lines ("每份（30公克）" with 每一份量30公克). Any other remainder still rejects the line: 35公克, 毫升, two brackets, a % inside, no brackets, or 約.
- **Evidence** keeps v2's bar (every header located, its own among them), so the evidence-only policy measure does not change.

**Attacks.** The new scenarios all hold, with no wrong value found:
- a % column mislabelled as an amount column, and the reverse;
- every column called reference intake;
- an amount header missing while the % header is read;
- an amount header with no printed text;
- a % value with a matching amount-like number (12公克 and 12%);
- an adjacent row's %;
- a % column printed on the other side;
- an omitted per-100 column, including a stray 每份 above it;
- an unheaded second % column;
- swapped amount columns and swapped headers among three columns;
- a narrow column touching an amount column, read either way;
- bracketed quantities that do not match the serving size.

The two-line header no longer blocks a correct reading: 12 of 12 are found, against none under v2's rule.

**Harnesses.** All six reviewer harnesses (rounds 2 to 6 and the base sweep) run clean on v3 three ways:
- without bases;
- with bases named from the header text (參考 or %);
- with the last column of every multi-column reading forced to reference intake, which stresses the relaxed path.

The E2 position sweep is also clean.

**Results, untouched Taiwan at 240 px** (counts in `results/l0-locate-rate-v4.json`):

| | v2 Gemini (pinned) | v3 Gemini | v3 Sol | v3 Luna |
|---|---|---|---|---|
| Correct values found on the photo | 207 / 557 (37.2%) | 243 / 557 (43.6%) | 250 / 564 (44.3%) | 248 / 566 (43.8%) |
| Ambiguous values / with a located region | 281 / 129 | 245 / 93 | 227 / 92 | 274 / 93 |
| Silent wrong values that need a check | 4 of 4 | 4 of 4 | 4 of 4 | 52 of 52 |
| Tables opening with nothing to check | 3 of 34 | 5 of 34 | 5 of 35 | 5 of 37 |
| Values to check per table, median / p90 | 14 / 18 | 9 / 18 | 9 / 18 | 9 / 19 |

Development photos are unchanged (Gemini 55.5%, median 8). Against v2 as it stood after round 4 (39.0%, median 14), v3 is 4.6 points higher. A comparison run with D4 switched off, before the round-6 tolerance was carried over, gave the same counts. On these photos the gain comes from the header bases.

**Reading.** v3 confirms more values than either v2 or v1 (43.6% against 37.2% and 42.2%) and halves the typical number of values to check from v2's 14 to 9. Every silent wrong value of every arm still needs a check.

**Round 1 of the #322 review** held every basis attack and found two routes, both fixed:

- **G1 (high, from v1):** a serving line matched by its quantity alone could be any token on the photo, so a serving size misread to equal a table value (每一份量30公克 read as 3公克, with 脂肪 3公克 in the table) was found at the fat cell, with or without a D4 header. A serving line matched by its quantity alone now counts only on a line outside the table: not between the top and bottom located rows, and not level with a located row label or header. The line, or one level with it, must also carry the serving line's own words. D4 now accepts a bracketed quantity only from a serving line whose whole printed text is on the photo (F8c: a bracket of 35 g with a printed serving line of 30 g and a model reading of 35 g).
- **G2 (medium):** two % columns between the amount columns, neither header read, with the first blank on some rows so the row token count still fit; the model read the second. With its header not located, a reference-intake value is now confirmed by position only when the table's % tokens sit at one x position.
- **C1 under a first-column reference intake (two errors, optional):** with a reference-intake header not located, more than half of the reading's reference-intake values must be printed in %; a column the reading calls reference intake that holds amounts confirms nothing.

F9, F8c, F8d, F5b and the C1 case are regression tests. The round-1 harness (A to E and F1 to F9, 87 scenarios) is clean with no bases, amount bases, a first-column and a last-column reference intake, and the bases-enabled sweep has no finding. All earlier harnesses stay clean. On L0 the cell counts do not change, and fewer serving lines are found (Gemini 35 of 68, against 39): those found only by their quantity, without their words, now need a check.

**Round 2 of the #322 review** held G1, G2 and the C1 rule and found two more single-error routes, both fixed:

- **H4 (medium):** % positions were separated by a gap larger than the median width of all tokens, so two narrow % columns close together counted as one. Positions are now told apart by the % tokens' own spans: a token starts a new position when it does not overlap the current one, or its centre is more than about one % token (at least 0.02) from the last.
- **H1 (medium-low):** the serving words could sit anywhere on the matched or a level line, so a footnote (*每一份量含膳食纖維 3公克) vouched for a misread 每一份量3公克. The words must now sit directly before (or after) the quantity on its own line, whitespace ignored. For a line Vision split in two, the quantity must start its line, and the words must end the nearest line directly to its left, level with it.

H4 at 0.60 and 0.64 and H1 are regression tests. The round-2 harness (A to F and H1 to H5, 104 scenarios) is clean in every base mode, and all earlier harnesses stay clean. On L0 the value counts do not change. Serving lines found fall again (Gemini 30 of 68, against 35), because a quantity whose words are not directly beside it now needs a check; Gemini's median to check is 9.5.

**Round 3 of the #322 review** held H4 and H1 at realistic spacing and found three low-severity edges, all fixed by stricter rules:

- **I1:** two touching % columns with mixed token widths still merged into one position. The count of % positions is now never less than the largest number of % tokens on any one direct row, with the span walk kept as a second signal.
- **I4b:** a suffix serving line (30公克/每份 misread as 3公克/每份) was found inside a footnote, *糖3公克/每份以下, because only the words after the quantity were checked, and the whole-text match had no boundary. **I3b:** a split serving line was matched when another block's level line ended with the serving words (另一口味每一份量, beside 3公克膳食纖維).
  - A serving line now counts only as the line itself, apart from whitespace and punctuation. Whatever comes before its words is empty or ends with punctuation; whatever comes after is empty or starts with punctuation.
  - For a split line, the quantity's line starts with the quantity, and the line to its left ends with the words, after nothing but such a boundary.
  - A whole-text match is likewise refused when a letter or ideograph touches it.
  - A serving line printed with the servings-per-pack line (每一份量30公克，本包裝含2份) still counts.

I1 (centre distances 0.04 and 0.045), I3b, I4b and the joined-line control are regression tests. The round-3 harness (A to H and I1 to I4, 121 scenarios) is clean in every base mode, and all earlier harnesses stay clean. On L0 the value counts do not change; Luna finds one serving line fewer (33).

### 17.16 L1b: the pure core (25 October 2026, no egress)

L1b adds the application's and the pure reader's label photo types, all with contract tests and no transport, image or Vision code:

- **Wire mapping.** `LabelPhotoWire` (a strict decoder of `label-photo-wire-schema-v1`: every member required, no other member, the enumerations closed) and `LabelPhotoWireMapping` (`label-photo-wire-mapping-v1`), the Swift port of `route_c_mapping.map_wire`, including Python's `re` digit and space classes and `repr`.
  - **Parity (tests 1 and 16).** `export_photo_parity.py` writes 171 committed vectors from the committed Taiwan truth, a mutation family and synthetic branch cases; its `check` mode re-derives them.
  - **Private parity.** Its `private` mode maps every saved route C answer outside the repository. All 742 saved answers (untouched and development, every arm) map to the reference candidate; only that count is reported.
- **Reader (test 2).** `LabelPhotoReader` conforms to the application's `LabelPhotoInterpreting` port and returns `LabelPhotoReading`. It runs the frozen format inference, gate v2 on the Taiwan format, `label-arithmetic-checks-v2` over the amount bases and `pasted-label-conversions-v1`, calling them and never copying them. Any inferred format other than Taiwan is declined `layout_not_supported`, and an answer that is not schema-valid gives nothing to show.
- **Manifest (test 5).** `LabelPhotoManifest` is the strict codec of 8.1. It is pinned by a golden SHA-256, and unknown, missing or malformed members throw. It amends 8.1 in five places, recorded here:
  - `label_format` is `taiwan_nutrition_labelling`, as in the pasted manifests and the launch scope;
  - `request.reasoning` is `reasoning_limit`, the limit sent;
  - `catalogue_check` holds `at`, `slug`, `endpoint`, `input_modalities`, `zero_data_retention`, `prompt_price` and `completion_price`;
  - each attention record carries `reasons`, a list, since one value can be not found, gate-flagged and in a failed check at once;
  - a new `checks_failed` member records the failed checks, so attention is recomputed without re-running the checks or parsing warning codes (`warnings_shown` must equal their codes).
- **Source and verifier (tests 6 and 20).** `LabelPhotoSource` builds the confirmation input: the image evidence, the manifest evidence, the release and the candidate.
  - **One derivation.** It derives values by projecting the stored manifest, in memory only, onto the pasted manifest's shape, and calling the pasted rules on it (stored basis, nutrients, corrections, conversions). Only each value's source ID changes. When the user leaves a value unknown, every cell of that nutrient in that column is dropped from the projection (a repeated row included), so the nutrient is stored unknown. `conversions` holds only the conversions still shown: leaving a conversion's source unknown removes that conversion, and its calculated value reads "Left unknown". This is an obligation and test of the L3 Confirm builder. The verifier refuses a kept conversion from a left-unknown source, so Log would fail closed otherwise.
  - **What the verifier checks.** It checks 8.2 against the stored bytes:
    - the digest and canonical bytes;
    - the admitted pipeline;
    - the wire digest and the 65,536-byte limit;
    - the image evidence and its attachment;
    - the admitted locator versions;
    - one location record per cell and serving line, with a region exactly on found values and inside the unit square;
    - the attention set, recomputed and equal to the stored one, every resolution agreeing with the corrections;
    - every stored value.
  - **Cross-route.** Each route's verifier refuses the other's evidence, including relabelled manifests.
- **Admission.** `LabelSourceAdmission` routes a candidate with any photo evidence, release or value to the photo verifier only when nothing in it names the pasted source. It sends a pasted candidate to `PanelSourceAdmission`, and refuses a mixed one.
- **Serving (test 3).** `LabelPhotoServingPolicy` (`label-photo-serving-v1`) reads the projection with the pasted per-serving rule and `pasted-label-serving-v3`'s per-100 rule. Parity with the pasted policy holds for twelve printed serving lines, both per-100 bases, exact and approximate packs, and both per-serving cases.
- **Ports and preparer types.**
  - The ports are `LabelImagePreparing`, `LabelImageReading`, `LabelValueLocating`, `LabelPhotoRouteChecking`, `LabelPhotoSpendLedger` and `ConnectivityStatus`.
  - The other types are `LabelPhotoWireReply`, `LabelCropRect` and `PreparedLabelImage`; the last has a `package` initialiser and the E3 bounds.
  - The one admitted route is Gemini 4 Argon on `google-vertex`. L3 confirms the endpoint tag; any other tag is a new entry.
- **Policies (tests 4, 9, 10, 21 and 26).** Attention v1, the retry schedule and the spend caps are pure and tested: the per-tap $0.05 total across attempts and the 6,000 prompt-token ceiling.
- **Freeze.** `LabelPhotoFreezeTests` now also pins the wire schema and mapping, serving v1, attention v1 and the manifest codec.

**Invariant review of #323 (BLOCK, fixed; decisions under the owner's delegation, within E9 and E10).**

- **Left unknown stays unknown (high).** The projection dropped a left-unknown cell before the pasted rules ran, so an entered value in that column (with no row) or a conversion calculating that nutrient could still store it as known. The verifier now checks the stored, unprojected manifest first: no correction for a left-unknown cell's nutrient in its column (whatever its row), no conversion to that nutrient from that column, and no correction of a serving line left unknown.
- **The day never exceeds $0.50 (E10).** A tap is admitted only while the day's cost plus a whole tap's $0.05 stays within $0.50.
- **An unreported cost counts at least $0.05 (E10, 17.5, test 10).** A tap with any attempt lacking a reported cost counts the larger of $0.05 and its reported costs plus W for each unreported attempt; any other tap counts its reported cost. (A first wording here charged only W, which contradicted the approved E10; the re-check corrected it.)
- **The spend ledger tells absent from unreadable.** `load()` returns `.absent` (a fresh day), `.day` or `.unreadable`, and unreadable fails closed.
- **A clock moved back never resets the allowance.** A stored day later than today counts as today.
- **Closed values at verify.** The request's wire schema must be `label-photo-wire-schema-v1`, the image's media type `image/jpeg`, and every `checks_failed` name one of the closed set: the six `label-arithmetic-checks-v1` names, `basis_plausibility`, and `serving_consistency` for `label-photo-serving-consistency-v1`.
- **Only the preparer builds a `PreparedLabelImage`.** Its initialiser is private to its file, and the only way in is the package `PreparedLabelImageFactory`. The boundary script refuses the factory, or `PreparedLabelImage(` or `.init(`, anywhere but the capture adapter and tests. L2's test 13 also pins that the recorded SHA-256 is that of the bytes.
- **Re-check: repeated rows (high).** Leaving one of two repeated rows unknown (`sugars` and `sugars_2` in one column) dropped only that cell, so the other became the stored value although the pasted rule stores a repeated nutrient unknown.
  - Leaving a value unknown now takes every cell of its nutrient in its column out of the projection, so the nutrient stays unknown.
  - Any conversion from that nutrient in that column is refused.
  - Regression tests cover the repeated value and the repeated kJ source.
- **Re-check: attention times.** Each resolution's `at` lies between the answer's `completed_at` and the capture.
- **Q1, retry.** The retry policy returns each attempt's timeout as min(45 s, what is left of the 90 s deadline), so the whole call ends by the deadline by construction.
- **Q2, cancellation.** Cancellation belongs to L3's orchestrator, which stops at once and never retries across a user action.
- **Q3, the accepted H2 limit.** The verifier recomputes attention from the stored locations, flags and failed checks, and never re-runs the locator or the checks (17.1). A stored `found` status, or a failed check left out of `checks_failed`, therefore cannot be re-derived at verify. This is accepted: the reading and the locator are not replayed by design. Both are written only by the app's own pipeline, and the manifest digest binds them.

L1b adds no target. `FoodLabelPhotoReading` gains its planned dependencies (the application, the domain and `NutritionLabelParsing`), which the boundary script already allowed. The copy for decline and failure codes (test 2's copy mapping) and the request and response checks (tests 7 and 8) belong to L3 and L4.

### 17.17 L2: image preparation and the Vision locator (25 October 2026, no egress)

L2 adds the `FoodLabelPhotoCapture` target, with no network code and nothing wired into the app yet. The boundary script gains three rules:
- the target's import allow-list (17.2);
- that only the composition root and the target's own tests import it;
- that each framework stays in its adapter file: ImageIO, CoreGraphics and UniformTypeIdentifiers in the preparer, Vision in the locator, Network and URLSession reserved for L3's connectivity adapter and transport.

- **`ImageIOLabelImagePreparer` (`label-photo-preparation-v1`).**
  - It decodes the primary image with its orientation applied to the pixels.
  - It crops to the user's rectangle and refuses a crop whose short edge is under 240 px, then turns the crop by the user's quarter turns.
  - It scales so the long edge is at most 2,048 px and the area at most 3.2 megapixels, and draws into an 8-bit sRGB bitmap.
  - It encodes a JPEG from those pixels alone at 0.85, then 0.75, then 0.65 while it exceeds 1,500,000 bytes; past that it refuses.
  - It then keeps only the allow-listed JPEG structure (see the #324 review below), so the output is untagged sRGB with no metadata block whatever the encoder wrote, or the read is refused.
  - The bytes' SHA-256 is computed from the bytes it returns, and `PreparedLabelImage` is built only through the package factory.
- **`VisionLabelValueLocator`.**
  - It runs `VNRecognizeTextRequest` on the prepared bytes themselves: revision 3, accurate, `zh-Hant` and `en-US` (those the running revision supports), language correction off.
  - It then calls the pinned matcher (`label-photo-vision-locate-v3`) with every header of the reading and its basis.
  - It records one location per cell (`<row_id>@<header_id>`) and per printed serving line, with a region only on a found value: decimal text with four places, inside the unit square.
- **Decisions the spec left open, taken here.**
  - **The crop rectangle** is normalised to the upright photo (after its orientation) with the origin top left. The user's quarter turns apply to the cropped part, clockwise.
  - **Regions** are recorded in Vision's normalised coordinates, origin bottom left, as the matcher reads them. L4's photo view converts them when it draws.
- **Tests 13, 14 and 23 run in the package** (`FoodLabelPhotoCaptureTests`), so they run with `swift test` on macOS, where ImageIO and Vision are the same frameworks; the simulator app tests are unchanged.
  - **Fixtures**, built at test time, are synthetic:
    - a JPEG with EXIF, GPS, TIFF, IPTC, the Apple maker note, XMP (including a Photoshop block), an embedded thumbnail and orientation 6;
    - a HEIC with a depth map and an HDR gain map;
    - a PNG with `eXIf` and `tEXt` chunks.
  - **Positive controls** assert each fixture holds them first.
  - **After preparation:**
    - no metadata dictionary, XMP, auxiliary data or embedded thumbnail;
    - orientation 1 or absent, and one image;
    - none of the byte signatures `Exif\0\0`, `http://ns.adobe.com/xap`, `Photoshop 3.0`, `ICC_PROFILE` or a TIFF header;
    - no application segment but APP0.
  - **Pixels** are upright (a known asymmetric fixture with orientation 6, then a crop with a quarter turn).
  - **Bounds:** every output is within 2,048 px, 3.2 MP and 1,500,000 bytes or is refused, and a 239 px crop is refused while 240 px is accepted.
  - **Hash:** the recorded SHA-256 is that of the bytes.
  - **End to end:** a synthetic Taiwan label rendered at test time is located with most values found, and a misread value is not.

**Invariant review of #324 (BLOCK, fixed).**

- **An allow-listed JPEG structure.** The sanitiser no longer copies everything after the scan. The prepared file must be exactly:
  - SOI;
  - optionally one APP0 that is a plain 16-byte JFIF header with no thumbnail;
  - quantisation and Huffman tables, and a restart interval;
  - exactly one SOF0 and one SOS;
  - scan data holding only stuffed `FF 00` and restart markers;
  - one EOI as the last two bytes.

  Other application segments and comments before the scan (the encoder's metadata, such as its ICC profile) are dropped. Anything else refuses the read (`malformedOutput`): a standalone or reserved marker before the scan, a progressive or second frame, a second scan, a marker or comment inside the scan, trailing bytes, an appended image with its MPF segment, or a JFXX or thumbnail-bearing APP0. Pure adversarial vectors cover each case.
- **Confinement checks every import form.** The per-file framework confinement uses the script's own import parsing, so attributes, `import struct X.Y`, trailing comments and indentation all count. URL loading (URLSession, NSURLConnection, CFNetwork, CFStream, `Data(contentsOf:)`) is refused outside the transport. Network leaves the target's allow-list until L3 adds its adapter.
- **The factory.** It is called only from the preparer's own file and tests, and it computes the SHA-256 of the bytes itself, through an injected digester.
- **The quality ladder is a pure function.** Its test is discriminating: an encoding that fits only at 0.75, one that fits only at 0.65, and one refused.
- **Decisions taken on the review.**
  - **(a) Shape.** The 240 px short-edge minimum applies after scaling as well, and a crop whose sides differ by more than 8 times is refused (`cropTooNarrow`; P5 amended).
  - **(b) Memory.** The photo is decoded subsampled, to the size the crop needs at the output bounds, rather than at full size. A large synthetic source is tested end to end, and the decode size is tested directly.
  - **(c) An L5/E13 gate.** Before the route is enabled, `FoodLabelPhotoCaptureTests` run once on a physical iPhone and the result is recorded, so the metadata guarantee is checked on iOS's ImageIO as well as macOS's.
- Quarter turns 2 and 3 are tested as well.

**The #324 re-review (PASS) and its Low hardening, folded into L3.** The structure is now exact as well as allow-listed:

- APP0 is accepted only once, and only as the first segment after SOI.
- DRI has length exactly 4 and appears at most once.
- SOF0 has length 8 + 3 x Nf and SOS 6 + 2 x Ns, with 1 to 4 components each.
- Restart markers in the scan are accepted only under a declared non-zero restart interval, and only in sequence `FF D0` to `FF D7` modulo 8. ImageIO writes its own DRI and restart markers, which pass.
- The subsampled-decode test adds a large orientation-6 source, which comes out portrait with the long edge at 2,048 px and the asymmetric marker in the right place.

### 17.18 L3: the read orchestrator, the OpenRouter adapter over a fake transport, the Confirm builder and atomic Log (26 October 2026, no egress)

L3 adds no live transport. The adapter talks to a `LabelPhotoHTTPTransporting` protocol, and its tests use a fake. No code loads a URL: the live conformer is L5's, in `OpenRouterTransport.swift`, the one file the boundary script allows to, and it ships with the egress records (E16).

**The read orchestrator (`LabelPhotoReadSession`, tests 9, 10, 21, 22 and 26).** One actor per app session. For each Read tap, in order:

1. The day's admission from the spend ledger. An unreadable ledger fails closed with the daily limit state; a paused day or a full allowance sends nothing.
2. On the session's first tap, and again on the first tap of each new local day (prices are per day), the catalogue check, before any image request. The slug, the endpoint, image input, zero data retention and the prices must match the route, and the worst case W of one attempt must fit the tap's $0.05. A mismatch or a failure ends the tap with "route unavailable" and nothing sent. A pass is kept for the session.
3. Attempts. Each one starts only while the tap's remaining budget covers a whole W, with the retry policy's delay and the clamped timeout of min(45 s, what is left of 90 s), until one of these:
   - an answer;
   - a failure that is not retried;
   - the attempt or deadline limit;
   - Cancel.
4. The tap is recorded on the day (E10).

**Cancel.**
- Cancel during an attempt stops at once. The attempt counts as sent, so a tap with no reported cost is charged $0.05 under E10.
- Cancel while waiting to retry starts no further attempt.
- Cancel before anything is sent charges nothing.

**The answer** carries the reply and the request record (instruction and schema digests, limits and the session's catalogue check), through the attempt port's `manifestRequest`.

**The adapter (`FoodLabelPhotoCapture`, tests 7, 8, 21 and 22).**

- **The request (E1, E2, E5).** One POST to `https://openrouter.ai/api/v1/chat/completions`. The body is exactly:
  - the model;
  - one user message holding the fixed instruction and the prepared JPEG as a data URI;
  - the strict wire schema, without `$comment`, under the evaluation's schema name and description;
  - the provider block: `only` and `order` the one endpoint, no fallbacks, parameters required, data collection denied and ZDR;
  - `max_tokens` 1,200, `reasoning: {"max_tokens": 500}`, `stream: false` and `usage: {"include": true}`.

  The body is serialised with sorted keys, and its bytes for a fixed image are pinned by SHA-256 (the golden). The key travels only as `Authorization: Bearer`, and a body that would contain the key is refused. No other header is sent: no referrer and no app title. The instruction and schema ship as package resources whose SHA-256 equal the evaluation's frozen contract pins, and a changed resource refuses to build a request.
- **The response checks (E5, E12).** A reply is an answer only when all of these hold:
  - it is at most 200,000 bytes (the transport stops reading past that);
  - HTTP 200, with exactly one choice;
  - `finish_reason` is `stop`, with no tool call and no refusal;
  - the model is exactly the requested slug, or one of its dated slugs pinned at E13 qualification (`pinnedSnapshots`, empty until then; no pattern is matched);
  - the provider, lower-cased with spaces as hyphens, equals the endpoint tag;
  - it has a generation ID, and its content (at most 65,536 bytes) decodes under the strict wire schema.

  Each other case is a failed read with nothing shown:
  - `length` gives truncated;
  - `content_filter` or a refusal gives refused;
  - a wrong model or provider gives its own code;
  - oversize gives oversize;
  - anything else gives an unreadable answer.

  A missing, negative or non-numeric cost is unknown, never zero; a reported zero is a reported cost.
- **Retry classification (E11, 17.5).**
  - HTTP 408, 429, 500, 502, 503 and 504, transport errors and timeouts are retried.
  - The overloaded answer is retried: an error object with code 502, 503 or 529 and no choices, in an HTTP error or a 200 envelope.
  - 401 and 403 give "key rejected" and are not retried; nor is any other status.
  - `Retry-After` is passed to the retry policy as received.
- **The catalogue check (E7, M3, test 22).** Two GETs of OpenRouter's public catalogue, with no Authorization header, no body and no user data: the model's endpoint listing (slug, image input, the endpoint's prices) and the ZDR endpoint listing, which must hold the same model on the same endpoint tag.

**Open for L5, before the live transport is wired.** These are not guessed here:
- The live catalogue's field names in the ZDR listing (`model_id` or `model`, and `tag`).
- Whether Gemini 4 Argon on Vertex bills reasoning outside `max_tokens`. `reasoningBilledSeparately` stays an explicit composition choice; with it, W is about $0.029 and an unreported failure leaves no retry.

L5 confirms both against the catalogue and a fictional qualification label, and records them here.

**The Confirm builder (`LabelPhotoConfirmation`, test 4 as Confirm applies it).**

- **The review.** `review(reading:image:reply:request:locations:)` refuses three things:
  - a declined or unusable reading (its codes);
  - a reading, reply or image that do not belong together;
  - locations that do not give exactly one record per cell and printed serving line.

  It computes the attention items and check groups with the same `LabelPhotoSource.attention` the verifier recomputes.
- **What it records.**
  - `flags_shown` holds every gate flag as shown with the reading. It is never reduced by a correction, unlike the pasted route, because attention is recomputed from it.
  - `checks_failed` holds the failed `label-arithmetic-checks-v2` results.
  - **Decision:** the per serving against per 100 check of 17.5 is v2's own `serving_scaling` (evaluation section 7, called and never copied), so v1 never emits a separate `serving_consistency` record. The name stays admitted and `consistency_version` stays as recorded.
- **Actions.** Each returns a new review:
  - "Matches the photo";
  - "I've checked them" on a check group, which keeps any correction or left-unknown already made;
  - "Leave unknown";
  - "Correct";
  - entering a serving line the label does not print.

  "Correct" follows the pasted rules. Only a value of the stored column, printed once in its ledger unit, can be corrected, and so can the serving size; a printed servings-per-pack line and other columns can only be checked or left unknown. A later resolution replaces the earlier one and its correction.
- **The shown-conversions rule (17.16).** Leaving a value unknown takes every value of its nutrient in its column out of the stored values. Any conversion from it, or to that nutrient in that column, is removed from `conversions` and reads "Left unknown"; changing the resolution brings it back.
- **Log.** Log stays disabled until every item is resolved. Each record's time is clamped between the answer's `completed_at` and the capture, even if the clock moved. The built input is checked with the save verifier before it is returned, so the builder fails closed.

**Atomic Log (17.3, test 15).**

- **The path.** `FoodConfirmationService.saveLabelPhoto` is the only way a new photo entry is logged:
  1. It checks that the bytes hash to the image evidence.
  2. It persists them through `EvidenceAttachmentStoring.persist`.
  3. It binds the image evidence to the descriptor.
  4. It saves with one commit whose evidence may reference only that descriptor (`FoodLedgerService`'s commit with `persistedAttachments`).
- **On failure.** On a policy rejection, a verifier rejection or a commit failure it calls `removeIfUnreferenced`.
- **What the tests show.** On the GRDB store with its real attachments directory:
  - each failure leaves no evidence row, no release and no file;
  - a successful Log is exactly one commit, and the entry reopens and verifies;
  - the plain `save` refuses a new photo entry without its photo.
- **Admission.** Save and reopen now route label candidates through `LabelSourceAdmission`, so a photo candidate reaches the photo verifier and a mixed one is refused. Pasted entries are unchanged, and their whole suite passes.

**Not in L3.** These are not in L3:
- the live transport and its egress records (L5);
- the file-backed spend ledger and the screens (L4);
- the copy for decline and failure codes (L4).

**The #324 re-review's Low hardening** is folded in (17.17).

**Invariant review of #326 (BLOCK on spend accounting, fixed; decisions by the coordinator under the owner's delegation).**

- **The tap is reserved before the first send (medium).** Before attempt 1 the session stores one more read and a whole tap's $0.05. At the end it reconciles that reservation to the tap's cost, up as well as down: a reported cost above $0.05 counts in full and pauses the day. A kill or crash mid-attempt leaves the reservation counted. A tap that sent nothing releases it. A test holds an attempt that never returns and reads the stored reservation.
- **A failed ledger write fails closed (medium).** If the reservation cannot be stored, nothing is sent. If the final write fails, the reservation stays. Either way every further read in that session is refused with the daily limit state.
- **One tap at a time (low to medium).** An in-flight flag is set before the first suspension, so a concurrent tap is refused and sends nothing. The admission is checked again on a fresh ledger read just before the reservation. At 29 reads and $0.45, two concurrent taps send once.
- **An unreadable ledger is never overwritten (low).** If the ledger reads as unreadable at the end of a tap, it is left as it is and the route stays closed.
- **No attempt without time (low).** If the clamped timeout is zero or less (for example after a suspension while waiting to retry), no attempt starts and the read ends timed out.
- **Q1, model identity (E5).** The response model must equal the request exactly, or appear in an explicit list of dated slugs for the approved model pinned at E13 qualification (`OpenRouterLabelPhotoAttempt.pinnedSnapshots`, empty until then). The evaluation's date-pattern rule is no longer used.
- **Q2, the key.** The session checks that a key is present and well formed before anything leaves, the catalogue requests included. The validated-key gate on the screen belongs to L4.
- **Q3, the day.** The catalogue check runs again on the first tap of a new local day, because prices are per day.
- **Q4, Cancel.** Accepted as built. L5's transport maps `.cancelled` only to task cancellation.

**Live transport obligations for L5.** `OpenRouterTransport.swift`, the one file allowed to load URLs, must do all of these:

- send a fixed, neutral `User-Agent` and no `Accept-Language`;
- use an ephemeral configuration with no cookies, no URL cache and no credential storage;
- refuse every redirect;
- cap the streamed reply at the requested byte maximum and report `exceededLimit` instead of reading on;
- apply the per-attempt timeout it is given;
- map `.cancelled` only to task cancellation, `.timedOut` to the timeout, `.offline` to no network path, and anything else to `.failed`;
- use the same anonymous configuration for the catalogue GETs, with no Authorization header.

Before the route is enabled, L5 also confirms the ZDR listing's live field names and whether reasoning is billed outside `max_tokens`, and records both here.
