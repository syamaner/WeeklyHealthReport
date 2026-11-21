# AI search by name, including page content v1: proposal (#488)

Status: **approved by the owner on 15 November 2026** (decisions in section 8; egress terms A1 to A15 in section 4). Written 15 November 2026 against `main` at `674e63b`. Approval does not change [`privacy-and-egress.md`](privacy-and-egress.md) or [`privacy-policy.txt`](privacy-policy.txt) yet: under A15 the amendments below take effect only in the P4 PR that wires the live transport for user-supplied content, and nothing new is sent before then.

**Amendment, 20 November 2026 ([O1](openrouter-single-consent-v1-amendment.md), implemented in #554).** A8 is amended in place (section 4): the first-use sheet is replaced by the Settings › OpenRouter consent. When this route is wired, its request site takes the same gate and adds its own entry to the privacy policy's OpenRouter section and its own egress row.

Owner priorities (14 November 2026): barcode is the primary route; label photos and screenshots rank next (#316, behind a switch); this route is third; receipts stay with the catalogue skill, outside the app. The assistive principle applies: AI pre-fills, the user checks and corrects, estimates and exceptions stay visible, every route ends on the shared Confirm with one Log action, nothing is saved automatically, and model output, citations or confidence never authorise nutrition by themselves.

## 1. What exists today and what this adds

**Web lookup** ([`generic-food-proposal-integration-v1.md`](generic-food-proposal-integration-v1.md), screen `GenericFoodProposalReviewView`, reached from search's "Not what you ate?") already does most of the plumbing:

- A typed name (1 to 300 characters) and the Settings market go to OpenRouter with the Exa web plugin (`max_results` 3) for discovery, then one lead-selection call (`typesafe/jev-1.13`); `OpenRouterFoodProvider`, version `openrouter-food-proposals-v4`.
- An optional **Source address** skips search and lead selection. The device itself fetches the page (`HTTPSFoodSourcePageAcquirer`: HTTPS only, at most 3 connections including redirects, 20 s, 2,000,000 bytes; `PublicFoodSourceCapture` accepts `text/html`, `text/plain` and `application/pdf`). PDFs are projected on device by `GenericFoodPDFProjector` (at most 10 pages, 1,000,000 bytes).
- The captured text blocks go to one extraction call (`openai/gpt-6-luna` on Azure) and one applicability check, routed with `only`, `allow_fallbacks: false`, `data_collection: "deny"` and `zdr: true`. Every value must be bound to quoted source text; unbound values stay unknown; the result is a `reviewed_web_proposal` with match type (exact product or similar food estimate) before the shared Confirm.
- No automatic retries and no app-enforced spending cap ("the app has no monetary spending cap", screen copy).

**Where it falls short for the owner.** The owner chose to start without a collection of their own failing searches (Q1), so the gaps below come from code and recorded evidence, not from measured user failures:

1. **No way to give the app content it cannot fetch.** Pages that need JavaScript, block non-browser clients, sit behind a login or a cookie wall, or are PDFs larger than 1 MB or 10 pages fail at capture, and the user has no fallback except manual entry. There is no paste-text or file input.
2. **Discovery quality is unproven.** The #100 disposition (11 October 2026) records exposed source controls at 7 of 8 and the original ETtoday and Fat Daddy cases not demonstrated; four soup descriptions were local misses. Exa via OpenRouter carries no search ZDR guarantee, and the web plugin is documented as deprecated.
3. **A separate review step before Confirm.** The user picks a match type and taps "Use this source" on the lookup screen, with quotes behind a disclosure, before Confirm; the label photo route instead shows values beside their source on Confirm with attention items that block Log. The two AI routes look and behave differently.
4. **No caps or retry policy** aligned with the label photo route (E9 to E11 there).

**What this adds.** One "Look up with AI" journey with four inputs (section 2), all producing the same evidence-bound proposal and ending on Confirm in the label photo pattern: values beside highlighted source text, attention items, unknowns left unknown. The new egress is user-supplied content (pasted text, a picked file's projected text) sent to the model; typed-name search keeps its current destinations.

## 2. Inputs and what leaves the device

| Input | On the device first | What leaves, and to whom | New? |
|---|---|---|---|
| **Typed name** | Shown exactly as it will be sent, with the market | Name and market to OpenRouter and its search engine (Exa) for discovery; lead metadata to the lead selector; then as for a URL | No (existing row) |
| **Pasted URL** | URL validated (HTTPS, at most 4,096 bytes) | An HTTPS GET from the device to that site, with no key, cookies or user data; then the projected page text to the one OpenRouter model endpoint | No (existing rows) |
| **Pasted page text** | Read through the system paste control only when tapped; projected into blocks; shown in full with a character count; checked by an on-device personal-data gate (section 4, A6) | The projected text, trimmed by the user if they wish, to the one OpenRouter model endpoint | **Yes** |
| **Picked HTML or PDF file** | Chosen in the Files picker; projected on device by the existing HTML and PDF projectors; file name, metadata and embedded images dropped | Only the projected text blocks, never the file bytes, to the one OpenRouter model endpoint | **Yes** |

A share-sheet extension (sharing a page or PDF from Safari into the app) is a new app target and is left to a later phase (Q4). Scanned PDFs with no text layer are declined in v1 with a message pointing to the label photo route.

## 3. Proposed flow

1. Add food, search, "Not what you ate?", **Look up with AI** (today's Web lookup, renamed in place; one journey per intent).
2. Choose an input: **Name**, **Page address**, **Paste page text** or **Choose a file**. Name and address keep today's fields.
3. **Before any send**, the screen shows exactly what will leave and where: the name and market, or the address, or the full projected text with its character count. A fixed line names the destination ("Sent to OpenRouter and one AI model. Your food log and Health data are never sent."). Personal-data gate hits are highlighted and must be removed or acknowledged before Send. The first send on a device shows a one-time confirmation sheet, as on the photo route.
4. **Send** (one tap, one action): progress with Stop; retries visible.
5. **Result:** the suggested source (page title and host, or "Text you pasted", or the file name shown locally only), match type proposed by the model and changeable by the user, and the values. Other leads stay inspectable for a typed name.
6. **Confirm** (shared screen, label photo pattern): a fixed line saying the values were read by AI from that source and must be checked; source text beside the values with each value's quote highlighted; attention items (unbound quote, unit or basis unclear, arithmetic mismatch, serving without a weight) block Log until resolved; unknown values stay unknown and never become zero; similar food estimates stay labelled as estimates. The user can correct any value, with the original kept as evidence.
7. **Log** is the only save. Cancelling at any point saves nothing.

The user validates: that the source is the food eaten (identity and preparation), the basis (per 100 g, per 100 ml or per serving), each value against its highlighted quote, and the amount eaten.

## 4. Egress terms: APPROVED 15 November 2026

The owner approved A1 to A15 as written on 15 November 2026. A7's token ceiling and A9's per-lookup cap are confirmed from the P3 measurements before P4; a change to either is recorded here before P4 lands. They mirror the approved label photo terms E1 to E16 ([`label-photo-ai-prefill-v1.md`](label-photo-ai-prefill-v1.md) section 10) where the shape is the same.

- [x] **A1 Destinations.** (a) `https://openrouter.ai/api/v1/chat/completions` for discovery, lead selection, extraction and the applicability check, as today; (b) the HTTPS site of a typed address or chosen lead, fetched by the device, as today. No new destination. *Recommend: approve.*
- [x] **A2 What is sent.** Typed name: the displayed name and market only. Address or lead: the projected page text. Pasted text or file: the projected text exactly as shown on the confirm-before-send view, plus the fixed instruction and strict JSON schema. *Recommend: approve.*
- [x] **A3 What is never sent.** The food log, saved foods, favourites, notes, Health data, location, device or account identifiers, file names, file metadata, embedded images, PDF attachments, cookies, and the key anywhere except the Authorization header. *Recommend: approve.*
- [x] **A4 Page fetch versus user-supplied content.** A page fetch is a plain HTTPS GET from the device carrying no user data; the fetched text then goes to the model as today. User-supplied content may contain personal data the app cannot fully recognise, so it is sent only after the user has seen it in full (A6). OpenRouter is never asked to fetch a URL on the app's behalf (no `web` plugin and no URL fetching tool on extraction calls). *Recommend: approve.*
- [x] **A5 Routing.** Extraction and applicability calls: provider `only` and `order` set to one endpoint, `allow_fallbacks: false`, `require_parameters: true`, `data_collection: "deny"`, `zdr: true`; the response's model and provider must match or the result is discarded. One extraction route is pinned after the evaluation (section 6) and changed only by a route version bump. Discovery keeps the existing Exa plugin route, whose search step has no ZDR guarantee; user-supplied content never goes through discovery. *Recommend: approve.*
- [x] **A6 Confirm before send and personal-data gate.** For pasted text and files: the full projected text is shown with Send; an on-device gate flags emails, phone numbers, UK postcodes, card-like and other long digit runs, and order, payment or account words; flagged text must be removed or acknowledged before Send. The gate is a warning aid, not a guarantee, and the copy says so. *Recommend: approve.*
- [x] **A7 Size.** Pasted text at most 100,000 characters before projection; files as today's limits (PDF at most 1,000,000 bytes and 10 pages, HTML at most 2,000,000 bytes); the projection sent at most 32,000 prompt tokens (the pasted-label text route's ceiling, [`pasted-label-ai-text-v1.md`](pasted-label-ai-text-v1.md) D36), measured on device before send; larger input is declined with a message to trim it. *Recommend: approve, with the token ceiling confirmed by the evaluation.*
- [x] **A8 When.** Only on the explicit Send tap after A6, with OpenRouter turned on in Settings (O1); no prefetch, per-keystroke, background or automatic re-send. *Amended by [O1](openrouter-single-consent-v1-amendment.md) (20 November 2026): A6's confirm-before-send view and its personal-data gate stay, since they show the exact content and change what the user does.*
- [x] **A9 Caps.** A per-lookup cap of $0.10 across all calls in that lookup, sized from the evaluation's measured worst case; a daily cap of 30 lookups and $0.50, kept in its own versioned day record separate from the label photo and text record (`label-ai-spend-day-v1`), so one route cannot exhaust the other. A lookup with no reported cost counts as its cap. The owner also sets a limit on the OpenRouter key. *Recommend: approve.*
- [x] **A10 Retries.** Model calls only: transport errors, timeouts, HTTP 408, 429, 500, 502, 503 and 504, with backoff honouring `Retry-After`, at most 3 attempts within a 90 s whole-call deadline, identical bytes, visible with Stop. Page fetches keep today's no-retry, 3-connection rule. Content failures are never retried. *Recommend: approve.* Today's web lookup calls are governed separately by the #500 model call retry amendment (120 s per call, [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md)); P4 must reconcile the two.
- [x] **A11 Key.** The existing OpenRouter key from this-device-only Keychain, validated in the session, shared with web lookup and the photo route. *Recommend: approve.*
- [x] **A12 On-device retention.** The projected text that was sent is kept on the device only, in the review manifest of a logged entry; nothing is kept for an unlogged lookup. It is not added to the Drive food export or backups beyond what `reviewed_web_proposal` carries today; P1 records what that is, and any change goes through the food daily export contract. *Recommend: approve.*
- [x] **A13 Provider records.** ZDR and no-collection cover the model endpoint only; OpenRouter keeps usage records under its own terms; Exa's search terms apply to typed-name discovery. The policy says so. *Recommend: approve the disclosure.*
- [x] **A14 Qualification before enabling.** The pinned route must meet the owner's bars on the sealed set (section 6) before the route is reachable outside a Debug build, and then only behind a Settings switch, off by default, internal builds first. *Recommend: approve.*
- [x] **A15 Records.** The policy amendments below take effect in the PR that wires the live user-supplied-content transport, not before. *Recommend: approve.*

**Approved amendment to `privacy-and-egress.md`** (not applied until P4, per A15):

```diff
-| OpenRouter and its configured providers | Displayed food terms and captured public source text | Only on an explicit web lookup, with the user's own validated key | [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) |
+| OpenRouter and its configured providers | Displayed food terms and captured public source text | Only on an explicit web lookup, with the user's own validated key | [generic-food-proposal-integration-v1.md](generic-food-proposal-integration-v1.md) |
+| OpenRouter and its one allow-listed extraction endpoint (ZDR, data collection denied, no fallbacks) | Page text the user pasted, or the text projected on the device from an HTML or PDF file the user picked, exactly as shown before sending, plus a fixed instruction and output schema; never the file itself, its name or metadata, the food log, health data or identifiers | Only when the user taps Send on Look up with AI after seeing the full text, with the user's own validated key; at most 3 attempts for retryable failures and $0.10 per lookup; at most 30 lookups and $0.50 per day | [ai-name-search-v1-proposal.md](ai-name-search-v1-proposal.md) |
```

and, under "Stays on the device unless the user sends it":

```diff
+- **Pasted page text and picked files** leave only as the projected text the user reviewed and sent from Look up with AI. The file itself never leaves; the sent text is kept on the device only with a logged entry.
```

## 5. Architecture gate

**Responsibilities.**

- *Domain* (pure): `FoodSourceContent` (input kind `typedName`, `address`, `pastedText`, `file`; projected blocks; SHA-256 of the sent bytes; character and token estimate), the existing `GenericFoodProposal` literal-binding and basis rules, and a pure `SuppliedContentGate` (size, block kinds, personal-data patterns to attention items). No networking, PDFKit, HTML parser or UI types.
- *Application*: one `AIFoodLookupCoordinator` that turns any input into `FoodSourceContent` and then runs the existing review pipeline (`FoodDocumentCapturing`, `FoodProposalExtracting`, `FoodProposalSelecting`, `FoodSourceLeadSelecting`, `FoodWebDiscovering`, `FoodSourcePageAcquiring`), a spend ledger port (own day record, A9), the retry policy (A10) and cancellation. A new consumer-owned port `FoodSourceContentProjecting` (bytes and declared type in, blocks out) replaces direct projector calls.
- *Infrastructure*: `OpenRouterFoodProvider` (extraction route pinned per A5), `HTTPSFoodSourcePageAcquirer` and `PublicFoodSourceCapture` (unchanged), `GenericFoodPDFProjector` and the HTML table projector behind `FoodSourceContentProjecting`, the spend day-record store.
- *Presentation*: input picker, paste control, Files picker, confirm-before-send view with gate highlights, progress, and the shared Confirm extended with the source-text pane already built for label photos.

**Dependency direction.** Presentation and infrastructure depend on application, which depends on domain. PDFKit, SwiftSoup, `UIDocumentPickerViewController`, URLSession and Network stay in adapters. Wiring is in `FoodLedgerCompositionRoot`. `check-boundaries.sh` gains the new files (no URL loading or PDFKit in domain or application).

**Invariants (closed).** Nothing is sent before the explicit Send; what is sent equals what was shown (hash checked at the transport); a value is pre-filled only when bound to a quote in the sent content, otherwise unknown; no inferred density, serving weight, salt-to-sodium or kJ conversion; similar food estimates are labelled; attention items block Log; one Log saves one versioned, append-only record; source content is untrusted data (prompt-injection text cannot change routing, schema or save rules); a market, key or input change invalidates an open result; existing `reviewed_web_proposal` records decode and re-encode unchanged, and the new input kind is a new manifest version, not an edit of the old one.

**Extension axes.** Input kinds (a share extension later is one adapter producing `FoodSourceContent`), document formats (behind `FoodSourceContentProjecting`), extraction routes (route version), discovery providers. Admission, binding, provenance and the Confirm rules are not extension points.

**Contract tests (written first).** Every `FoodSourceContentProjecting` adapter passes the same tests (block bounds, hidden or nested structures refused, metadata dropped, scanned PDF declined); sent bytes equal previewed bytes; gate hits block Send until resolved; the key never appears in a body, log or manifest; caps and day-record versioning (unversioned or corrupt fails closed); retry classes and deadline; response model and provider mismatch discards the result; unbound and bounded values stay unknown; prompt injection in pasted text; cancellation at each stage sends nothing further; manifest round-trip for each input kind and for existing records.

## 6. Evaluation before enabling

Quality is measured before the route is reachable outside Debug, reusing existing tools rather than adding a parallel harness:

- **Cases: public pages and synthetic text (Q1).** The practice and sealed sets are built from public product and recipe pages (HTML and PDF, saved as fetched) and synthetic pasted text written for the purpose, including personal-data and prompt-injection cases. Gold values are read from the page under the owner's review; no values are invented for real products. The repository holds only hashes, case IDs, synthetic fixtures and scores, as with `off-uk-v1`; saved copies of third-party pages stay in the private workspace. The owner may add real failing cases later, privately, to the practice set only.
- **Split before any model sees it:** a development set for tuning and a sealed held-out set opened once, checked for overlap with `Tools/GenericFoodProposalEvaluation/holdout_audit.py` and frozen with `frozen_run.py freeze` (which already pins executable, sources, fixtures, request limits and cost stops).
- **Tools.** `Tools/GenericFoodProposalEvaluation` (`evaluate.py`, `evaluate_workflow.py`) gains the pasted-text and file input kinds; `Tools/FoodSearchQuality` and `Tools/FoodQueryEvaluation` stay the regression checks for typed names and keep running in CI; the per-field scoring and spend ledger patterns of `Tools/PastedLabelAITextEval` are reused for correction burden and cost.
- **Measured, per input kind, with denominators:** reached Confirm; fields correct with no edit; silent errors (a wrong value without an attention item), reported case by case; correction burden (edits per logged entry); identity mismatches; declined and failed states; cost per lookup (median, worst) and latency (p90).
- **Bars are the owner's.** Accepted as starting bars on 15 November 2026 (Q5); they may be adjusted after the practice runs, and are frozen before the sealed set is opened: zero identity mismatches presented as exact product; silent-error fields reported individually with none on energy; no-edit at least 70% of usable cases; median cost at most $0.03; p90 latency at most 30 s. The pasted-label text route missed its held-out bars (D38, 9 November 2026) and was closed rather than retuned; the same rule applies here: a missed sealed run stops release, and the sealed set is spent.

## 7. Phases (one small PR each; nothing new sends before P4)

| Phase | Content | Sends anything new? |
|---|---|---|
| P0 | This proposal, owner decisions, approved terms recorded | No |
| P1 | Pure domain and application: `FoodSourceContent`, gate, projector port, coordinator, caps, contract tests; record what `reviewed_web_proposal` exports today | No |
| P2 | Presentation: input picker, paste and Files picker, confirm-before-send, Confirm source pane; scripted transport only | No |
| P3 | Evaluation: practice set of public pages and synthetic text, development runs on candidate routes, route pinned, A7 and A9 confirmed, bars frozen, sealed set built | Evaluation runs only, under their own approved terms |
| P4 | Live transport for user-supplied content, sealed run, policy amendments (A15), Settings switch off by default | Yes, Debug and switch only |
| P5 | Internal TestFlight, owner device check, then a decision on wider release | No change |
| Later | Estimate unknowns (section 9), its own proposal and terms | Only under its own approved terms |

## 8. Owner decisions (15 November 2026)

1. **Q1 Failing cases.** Approved to start without them: no collection of the owner's failing searches first; the evaluation uses public pages and synthetic text (section 6).
2. **Q2 Scope of v1.** Approved: v1 adds pasted page text and a picked HTML or PDF file; typed-name discovery stays as it is.
3. **Q3 Unsourced estimates.** Approved: in v1 a value the source does not quote stays unknown. A later phase may propose estimates for unknowns (section 9).
4. **Q4 Share extension.** Approved: no Safari share extension in v1.
5. **Q5 Bars.** Approved: the section 6 starting bars, adjustable after the practice runs and frozen before the sealed run.
6. **Q6 Egress terms.** Approved: A1 to A15, with A7 and A9 confirmed from P3 measurements before P4.

## 9. Later phase: estimate unknowns (not part of v1)

The owner asked on 15 November 2026 for a second phase that improves unknowns with AI, and approved adding it here. It starts only after v1 has shipped and needs its own proposal, egress terms and pass marks. The outline it starts from:

- The model proposes a **generic reference record** (for example a named reference food from an official composition table) for nutrients the source left unknown; it never invents a number.
- On Confirm each estimated value is labelled as an estimate, with its source, the reference record, its state and the method, per nutrient, and kept apart from values quoted by the source.
- The user accepts or corrects each estimated value; nothing is filled or saved automatically, and Log stays the only save.
- It is judged against its own pass marks on its own sealed set, and anything it sends is egress under its own approved terms.
