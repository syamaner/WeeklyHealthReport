# Pasted label AI reading v1: text first (#416)

Status: **draft spec, 7 November 2026. Documents only; no production code and no egress yet.** The owner decided D2 to D6 on 7 November 2026 (section 9), including the evaluation egress terms T1 to T7. The product route's egress terms (T8 to T12) still need line-by-line approval before the route sends anything. The architecture gate has not run.

## 1. Problem

The deterministic pasted-label reader declines most real UK text. The UK reader v2 release check ([P4 results](pasted-nutrition-label-uk-english-v2-p4.md) section 2) held the bar, with 0 wrong values, but 19 of 24 fresh labels declined. None of the 9 labels from new sites reached Confirm. v1 was 20 of 24. The decline causes are mostly layout (counts that do not line up, values printed without units), which further rules would chase site by site.

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

### 4.1 What is reused, unchanged

The photo route already has every stage after the model. The text route calls them and copies nothing:

- the OpenRouter transport, the route checker, the catalogue check, spend and retry policies (photo spec 17.18 and 17.21);
- the strict wire schema and the wire mapping `label-photo-wire-mapping-v1`. The app, not the model, turns printed text into numbers, units and comparators;
- decline gate v2, `pasted-label-conversions-v1`, `label-arithmetic-checks-v2`, the basis options and the identity mapping;
- the attention policy, the Confirm builder, atomic Log and fortification C1 to C12.

### 4.2 What is new

- **A text locator in place of the photo locator.** Each printed value the model returns must occur verbatim in the pasted text, on the line of its row label, in its header's column order. Exactly one match counts as found. Zero or several matches is an attention item. This is a check of the model's answer against the text, not a reader. It never produces a value. **Allowed by the owner (D3).**
- **Route versions:** `pasted-label-ai-text-v1`, and a manifest `pasted-label-ai-text-v1` recording:
  - the model, provider, endpoint, route, instruction, schema, mapping, gate, checks and locator versions;
  - the text hash and length, the raw response, usage and cost;
  - every per-value state and user action.
- **The text's provenance.** Unchanged values reuse `user_verified_panel`, with a new source ID `pasted-label-ai`. Corrected values carry `manual_declaration`, as on both existing routes.
- **Admission.** Through the composite `LabelSourceAdmission` (photo decision P19), extended by one verifier, so no freeze re-pin.

### 4.3 Formats

The photo route admits Taiwan only. The text route must admit UK declarations for the change to matter.

- **The UK rules already exist and are frozen:** the gate, conversions and identity v3 behind `.ukDevelopment`. Reusing them on a model's candidate is reuse, not new parsing.
- **Other English panels** (US with per 100, Australian, New Zealand, EU English) were settled as allowed in UK v1 decision 11. They reach Confirm with flags. **Decided by the owner (D2):** UK, those English panels and Taiwan declines are admitted, and everything else declines.

## 5. Evaluation programme

### 5.1 Data

Every set below is real public label text with a blind, owner-verified transcription, held in `~/WHR-label-eval-private/` and never in git.

| Set | Labels | Role proposed |
|---|---:|---|
| Taiwan reader v3 development set | 24 | Tuning |
| Taiwan reader v3 fresh set | 24 | Tuning (spent by its release check) |
| UK v1 development set | 24 | Tuning |
| UK v1 fresh set | 24 | Tuning (spent by the v1 probe) |
| UK v2 fresh set | 24 | **Held out.** Sealed, run once by the frozen reader, never probed |

- **Tuning:** about 96 labels. Prompt and model versions are compared on these as often as needed.
- **Held out:** the 24 UK v2 labels, run **once**, after the prompt, model and checks are frozen, against a bar fixed in advance (5.3). No Taiwan label is held out today, so Taiwan would need a new fresh collection under the existing protocol if it is to be measured on untouched text. **Decided by the owner (D4):** the UK v2 fresh set only, so Taiwan is not measured on untouched text in v1.
- **Synthetic adversarial texts** (committed, no real text): truncated tables, two panels, values without units, injected instructions in the pasted text, and a non-label paste. Every version must pass these before any real-text run.

One evaluation format replaces the per-programme schemas. A small converter maps the Taiwan and UK transcription schemas into it, proven by round-trip tests on synthetic fixtures. The existing data is not edited.

### 5.2 Harness

- **An offline tool** in `Tools/` beside the photo evaluation, reusing its budget, consent and spend-ledger code.
- **Output** in the release run format, so scorer v2's per-value rules decide wrong values. A small text-route scorer adds the AI-specific counts.
- **Each run** records the prompt version, model, endpoint, the text's hash and the raw response, privately. The repo gets counts only.
- **A run matrix:** prompt versions by models. Each cell runs on all tuning labels, with a spend stop per cell and per programme.

**Metrics per cell:**
- tables reaching Confirm;
- wrong values;
- **silent-error tables** (a wrong value with no attention item);
- no-edit tables;
- attention items per table;
- failed reads;
- median and p90 cost and latency.

### 5.3 Bar for the held-out run (accepted by the owner, 7 November 2026, D5)

1. **Zero silent-error tables.** Every wrong value must carry an attention item. The text locator makes this reachable, which it was not for photos.
2. **Tables needing no edit:** at least 80% of the tables that reach Confirm.
3. **AI reads that fail or decline:** at most 25% of the labels the frozen reader declines.
4. **Median cost** at most $0.01 per read; **p90 latency** at most 15 s.
5. **Reported, not gating:** wrong values that were flagged, attention items per table, and the results by tier and by copy method.

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
- [ ] **T9 Payload.** The pasted text as pasted, after the app's existing normalisation, at most 8,000 characters, with the fixed instruction and schema. Nothing else.
- [ ] **T10 Routing and key.** As photo E5, E7 and E8, with the one pinned text route.
- [ ] **T11 Caps.** Per read and per day, shared with the photo route's daily cap so the two routes cannot double the spend. Figures are set from the evaluation's measured costs.
- [ ] **T12 Records.** A `privacy-and-egress.md` row and the privacy policy text take effect in the PR that wires the live text route.

## 8. Phasing (one PR per phase)

| Phase | Content | Egress |
|---|---|---|
| A0 | This spec, the owner decisions, the architecture gate | None |
| A1 | The evaluation format, converters, the text locator as pure code, synthetic adversarial fixtures, and the bar committed | None |
| A2 | The text harness over a fake transport; scorer parity on synthetic runs | None |
| A3 | Tuning runs: the matrix, results as counts, and prompt and model frozen | T1 to T6 |
| A4 | The held-out run and its result | T7 |
| A5 | The product route behind a launch argument: Read with AI, Confirm with the text pane, manifest and admission | None until T8 to T12 |
| A6 | Device check by the owner, the records in force, and the route turned on | As approved |

## 9. Decisions for the owner (asked one at a time)

| ID | Question | Recommendation |
|---|---|---|
| D1 | Should Read with AI appear only after the frozen reader declines, never in place of a successful read? | Yes, as decided ("AI for the rest") |
| D2 | Which panels does the text route admit? | **Decided (owner, 7 November 2026):** UK declarations and the other English panels settled in UK v1 decision 11, plus Taiwan pastes the reader declines; everything else declines |
| D3 | Is the text locator allowed, given parsing is parked? | **Decided (owner, 7 November 2026): allowed.** It checks the model's answer and never produces a value |
| D4 | Held-out data: the UK v2 fresh set only, or also a new Taiwan fresh set? | **Decided (owner, 7 November 2026): the UK v2 fresh set only.** A Taiwan fresh set only if Taiwan declines turn out to matter |
| D5 | The held-out bar in 5.3 | **Decided (owner, 7 November 2026): as proposed.** Committed in A1, before any tuning run |
| D6 | The evaluation egress terms T1 to T7 | **Decided (owner, 7 November 2026): approved as written.** The product route's T8 to T12 come separately |
| D7 | A GitHub issue for this programme, with one PR per phase | Yes |

## 10. Not changing

- the frozen Taiwan reader, its pins and every manifest it writes;
- the photo route's Taiwan scope;
- the shared Confirm rules;
- the egress list, until T8 to T12 are approved and wired.
