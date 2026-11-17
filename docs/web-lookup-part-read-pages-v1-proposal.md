# Web lookup: part-read pages v1 (proposal)

Status: **proposal of 17 November 2026, not accepted, not implemented** (#508). It would amend [generic web proposal integration v1](generic-food-proposal-integration-v1.md) and [generic food review manifest v2](generic-food-review-manifest-v2.md). Nothing here takes effect until the owner accepts it; the decisions it needs are in section 2. Documentation only: no app code, test or fixture changes with this document, and `privacy-and-egress.md` and `privacy-policy.txt` are edited only by the implementing change, with the wording in section 9. The pull request that adds this document closes nothing.

## 1. Problem and evidence

Web lookup captures a public page, projects it to text blocks, and sends those blocks to the provider for a bounded review. `GenericFoodDocumentProjector.project` refuses a page with `responseTooLarge` once its projected text passes 30,000 characters or it would emit a 513th block (`GenericFoodDocumentProjector.swift:30`). `CapturedFoodDocument.validate` enforces the same bounds on the stored type (`GenericFoodProposal.swift:38` and `:40`). The person sees "The source is too large for this bounded review. Choose a more specific food page." (`GenericFoodProposalReviewView.swift:146`).

A device report on TestFlight 0.3.0 (37) showed an ordinary shop product page refused this way. There is no more specific page: it is the product page. It is not established whether that run was a supplied page address or a discovery run.

### 1.1 Measurement (17 November 2026)

The projector was run offline over seven public product pages in a scratch copy of the package at `main` 37cad25, with only the two output bounds lifted. No provider call was made and nothing in the repository was changed. Pages were fetched once with a desktop browser identity; the HTML the app's own capture is served may differ, so the figures describe these fetches, not the device.

| Page | Blocks | Characters | Today |
|---|---:|---:|---|
| A: shop product page (the page in the device report) | 638 | 55,921 | exceeds both bounds |
| B: supermarket product page | 808 | 13,541 | exceeds the block bound |
| C: supermarket product page, same site as B | 818 | 13,897 | exceeds the block bound |
| D to G: four other product pages | 155 to 216 | 3,041 to 11,203 | fit |

What the pages over the bounds contain:

- B and C: about 550 of the blocks are navigation menu items. The nutrition panel is one table of 11 rows, six blocks below the product heading.
- A: nine tables. Seven carry nutrition or composition values per 100 g. Three of the seven are the main panel, printed for two differently sourced batches of the product (one batch twice), with different energy values. One block of 10,683 characters is machine-readable shop data, not nutrition. Three JSON-LD blocks total 7,262 characters.
- In the six pages that print their panel as a table, the basis wording ("per 100 g") is in the table's own header row and the section heading is within six blocks above the table. The seventh page (one of D to G) prints its panel as list items.
- On A, the line naming the two batches is one combined tab label, six blocks above one panel and 58 blocks above the other batch's panel.

A trial rule kept every table that had a per-100 header or at least three rows with a nutrient term and a digit, with 12 blocks before and 6 after, the first `h1` and every JSON-LD block:

| Page | Kept blocks | Kept characters |
|---|---:|---:|
| A | 141 | 12,317 |
| B | 30 | 1,550 |
| C | 30 | 1,755 |

A word-based rule (any block containing a nutrient word) was also tried and rejected: on A it marked 150 blocks holding 39,948 characters, more than the character bound by itself.

Limits of this evidence:

- Seven pages, three of them over the bounds and those from two sites. It is a development sample, not a held-out set.
- The trial rule was a script, not production code, and it differs from section 4: it admitted a table on a per-100 header alone, kept every JSON-LD block, had no definition-list units, no nearest-heading rule and no long-block rule. Definition-list units have no evidence yet.
- No provider call was made, so nothing here shows that the kept blocks yield a bindable proposal. The page `title` is projected as a plain text block and is not kept by the rule, which matters on a page with no `h1` block.
- The retained pages over the bounds from the earlier evaluation were not available and are not in the sample.

## 2. Decisions for the owner

| # | Decision | Recommendation |
|---|---|---|
| W1 | Supersede the two recorded "no truncation" decisions (section 3) with the bounded selection in section 4 | Yes |
| W2 | Selection rule: keep every nutrition unit whole or refuse; never drop one nutrition unit to make another fit | Yes. A rule that drops units could hide a competing panel (page A has two) |
| W3 | A part-read page is shown under a new screen identifier `web-lookup-review-v2`, with the line "Only part of this page was read." and the "Not stated" group renamed "Not in the part read" | Yes. The copy is fixed at acceptance (section 6) |
| W4 | Source order (section 7): part-reading applies when the person gave the page address, or when the discovery result holds no other admissible lead. A run that moves to a second lead does not come back to the first | Yes. It keeps the two-capture rule and needs no retained bytes. The cost is stated in section 7 |
| W5 | Egress: a page refused today has none of its page text sent to the provider; under this proposal its kept text is sent, within the existing destination, content class and bounds. `privacy-and-egress.md` says "changing when a request happens" needs a contract, a policy update and approval | Approve as within the existing OpenRouter row, with the wording in section 9 |
| W6 | Scope of v1: tables and definition lists only. A page over the bounds whose panel is in neither is still refused | Yes, and measure before widening |
| W7 | Compatibility (section 5.2): a part-read review is written under a third manifest version with its own admitted pipeline and takes the next free food contract number, so that an older build refuses it at import and not later at reopen, and every existing v1 and v2 review is admitted exactly as today | Yes |

## 3. What this supersedes

On acceptance, and only for HTML pages whose full projection exceeds the output bounds:

- Integration v1, "Public HTML size gate": "No truncation, decompression or host exceptions are added." Decompression and host exceptions stay excluded.
- Integration v1, the later checkpoint: an exploratory main-landmark-only projection still exceeded the block bound for two retained pages, "so no main-content truncation policy was adopted". This proposal is not a main-landmark rule; section 1.1 is its evidence.
- Manifest v2, section 2: `document: CapturedFoodDocument // unchanged` stays true for manifest v2. The optional member (section 5) appears only in a part-read document, which is written under a third manifest version (section 5.2).
- Manifest v2, section 9, "Content of `web-lookup-review-v1`": unchanged. A second identifier is added beside it (section 6).

Historical evaluation outcomes recorded as `capture_responseTooLarge` stay as recorded.

## 4. Selection contract (`food-document-block-selection-v1`)

### 4.1 Unchanged gates

Raw bytes at most 3 MB, at most 50,000 nodes, depth at most 64, UTF-8, media type, HTTPS and public-address pinning, connection and deadline limits. PDF and `text/plain` sources are unchanged: one over its bounds is refused as today.

### 4.2 Pages within the bounds

If the full projection has at most 512 blocks and at most 30,000 characters, the output is exactly today's: the same blocks, ids, locators and the version string `swift-food-document-blocks-v6`. Selection does not run. Every fixture with retained bytes re-projects equal.

### 4.3 Pages over the bounds

The walk continues past the output bounds to the end of the document. No new block or character ceiling is added; the unchanged 3 MB and 50,000-node gates bound the walk, and the run timeout and cancellation still apply to it and to the matching. If the walk meets any error other than cancellation after the point where today's projection would have refused (for example malformed JSON-LD), the result is `responseTooLarge`, so the failure class and the fallback to another lead do not change. Cancellation stays cancellation.

Selection then runs on the full ordered block list:

1. **Structural units.** A table unit is every emitted `tr` block whose nearest ancestor table is the same table, plus that table's `caption` block if it has one. A definition unit is every emitted `definition_row` block whose nearest `dl` ancestor is the same list. Lone `dt` and `dd` blocks, and rows the projector emits as other block kinds (for example a row that wraps a nested table), belong to no unit. The projector passes each block's unit key to the selection as data; the selection does not parse locator strings.
2. **Nutrition units.** A unit is a nutrition unit when at least three of its blocks contain a term from the closed nutrient vocabulary together with a digit. A per-100 basis in the unit's caption or first emitted row is not enough by itself, so a price-per-100 g table is not a nutrition unit. The vocabulary and the matching rule are published in the implementing change and pinned by tests. Matching uses explicit look-arounds, not word boundaries, so "Per100g" and "61kcal" match; Chinese terms have their own rule.
3. **Context.** Each nutrition unit takes up to 12 blocks before it and up to 6 after it. A context block longer than 1,400 characters (the provider excerpt length, `FoodProposalEvidenceCatalog.maximumExcerptCharacters`) ends the window on that side and is not kept. A JSON-LD block inside a window is treated under step 6, not as context. Each nutrition unit also takes the nearest heading block (`h1` to `h6`) before it, whatever the distance. Overlapping windows merge.
4. **Identity.** The first block of kind `h1`, if the page has one, is required.
5. **All or nothing.** The required set is every nutrition unit, its context and nearest heading, and the first `h1` block. If the required set is within 512 blocks and 30,000 characters, it is kept. Otherwise the result is `responseTooLarge`, exactly as today. No nutrition unit is dropped, ranked or cut, and no block is truncated.
6. **JSON-LD.** After the required set is admitted, JSON-LD blocks are tried in document order. Each is added if both totals stay within the bounds; one that does not fit is skipped and later ones are still tried. A JSON-LD block is never a reason to refuse and never displaces a required block.
7. **No nutrition unit.** If the page has none, the result is `responseTooLarge`, as today.
8. **Output.** Kept blocks keep their original order, their ids from the full projection (so block `b137` stays `b137`) and their locator paths. Their locators carry the version string `swift-food-document-blocks-v7-selected`, a named constant. If a locator would exceed 500 characters with the longer string, the result is `responseTooLarge`; nothing is shortened.
9. `rawSha256` remains the hash of the complete raw bytes, and the document id is unchanged.

Counts are `Character` counts of the normalised block text, as today. The windows 12 and 6, the 1,400-character rule and the three-block threshold are closed policy values of `food-document-block-selection-v1`. Changing one of them, the vocabulary or a unit definition is a new policy version.

### 4.4 What selection never does

No host-specific rule, no host exception, no model in the selection, no script execution, no truncation inside a block, no cross-source merging, no value produced by the selection itself. The same bytes always give the same kept blocks.

### 4.5 Known limit: a label far from its panel

A line that tells two panels apart (page A's batch label) is kept only when it falls inside a context window or is the nearest heading. Kept or not, plain page text does not say which panel a shared label belongs to; that is true of a whole page too. Both panels reach the review, their values differ, and the existing conflict handling and the person's own reading decide. Selection never resolves it. Test 4 in section 11 pins this behaviour.

## 5. The part-read record and compatibility

### 5.1 The record

`CapturedFoodDocument` gains an optional member `partialRead`:

| Field | Meaning |
|---|---|
| `policy` | `food-document-block-selection-v1` (the constant lives in `FoodLedgerDomain`) |
| `fullBlocks`, `fullCharacters` | counts of the full projection |
| `keptBlocks`, `keptCharacters` | counts of the stored blocks |

- It is absent for every page within the bounds, so existing documents, manifests, archives and fixtures decode and re-encode with identical bytes.
- `validate()` checks it: a known policy; kept counts equal to the actual blocks; full counts at least the kept counts and over at least one bound. It also refuses a document whose locators carry the selected version string without `partialRead`, or the reverse.
- Admission refuses a manifest unless its `presentation` is `web-lookup-review-v2`, and its manifest version the part-read version of section 5.2, exactly when `document.partialRead` is present.
- It is retained in the review manifest, so a reopened review still says the page was read in part.
- It is not sent to any provider. The extraction and applicability routes send only catalogue entries (id, kind, text). One route, the `.jev` selection route, serialises whole documents (`OpenRouterFoodProvider.swift:233`); production composes the applicability route, and the `.jev` route is used by defaults, tests and the probe. The implementing change excludes the record on that route and pins its request body. On that route the locators are still sent, so the selected version string and the non-contiguous ids disclose that a page was read in part; that is accepted, since the route already sends locators.

### 5.2 Older builds (decision W7)

Manifest v2 records why food contract 5 was introduced: without a bump an older build would import newer records and fail them later at reopen. The same applies here. A build that does not know `web-lookup-review-v2` fails closed on it when it decodes the review action, which is too late if the record was already imported.

Admission is closed: `ReviewedFoodProposalConfirmation.admittedPipelines` ties each manifest version to exactly one stored pipeline triple. Adding an admission version under manifest v2 would therefore either stop existing whole-page v2 reviews from being admitted or fail the new ones.

Recommended: part-read reviews are written under a third manifest version, `reviewed-web-proposal-v3`, with its own triple in that table. Whole-page reviews keep writing v2, and the v1 and v2 entries are untouched, so every stored review is admitted exactly as today. `minimumContractVersion` returns the next free food contract number when any evidence carries the v3 capture method version, so an older build refuses the archive at import. The number is taken at implementation time (two accepted proposals already reserve the next two numbers, and theirs are re-checked the same way). The SQLite schema position follows the metadata-only precedent of the contract 5 migration and is fixed at the phase gate. Manifest v3 is manifest v2 with the part-read document and the `web-lookup-review-v2` presentation; it changes no other field.

The alternative is to let the table hold two triples for v2. It changes the closed "exactly one" rule for every reader of that table and gives an older build no evidence field to refuse on, so it is not recommended.

## 6. Screen contract `web-lookup-review-v2`

Used only for part-read documents. `web-lookup-review-v1` and its golden content are unchanged and stay in use for whole pages.

Content: everything in `web-lookup-review-v1`, with two differences:

- one added line: "Only part of this page was read.";
- the "Not stated" group is titled "Not in the part read", because on a part-read page an absent nutrient may be outside the part read. Its membership is unchanged (every nutrient that is neither declared nor unusable). "Not usable" is unchanged. Unknown stays unknown and is never shown or saved as zero.

Developer tools shows the policy id and the four counts.

The refusal copy is unchanged in v1, including its advice to choose a more specific page, which section 1 shows can be unhelpful. Rewording it for pages that are still refused is left to the phase gate (section 12).

## 7. Source order

Today a second lead is tried only after an empty extraction or a recoverable acquisition failure, which includes `responseTooLarge` (`GenericFoodProposalReview.swift:160`), with at most two captures per run.

The capture port gains a part-read permission, passed by the reviewer for each capture. Without it the projector behaves exactly as today.

- **Supplied address, or a run with no source selector.** One capture, permission granted.
- **Discovery run.** Before the first capture the reviewer evaluates one predicate: does the discovery result hold another admissible lead? If not, the first capture has permission. If so, the first capture has none; a page over the bounds is refused as today and the run moves on.
- **Second capture.** It always has permission, whether the run reached it after a refusal or after an empty first extraction.
- **No way back.** If a second lead exists but is not captured (the selector abstains, a market conflict, a provider error), or its capture fails for another reason, the run ends as today. The first page is not part-read in that run: doing so would need a third capture or retained bytes. The person can give that page's address directly, which reads it in part.
- The two-capture limit, one discovery, no repeated step and no merging are unchanged.

## 8. Invariants

- **Unknown is never zero.** A nutrient outside the kept blocks is unknown.
- **Competing panels stay visible.** Because no nutrition unit is dropped, two panels on one page both reach the review. Selection never picks between them.
- **Binding is unchanged.** A quote must be found in a kept block, looked up by id, and numeric context is checked against the original block text.
- **Stored formats.** Records without `partialRead` are byte-identical before and after. Part-read records are new and are refused by older builds at import (section 5.2).
- **No medical interpretation, no automatic saving.** The Confirm step and its single Log action are untouched.

## 9. Privacy and egress

Destinations, content class (captured public source text) and per-document bounds do not change. What changes is when page text is sent: a page over the bounds has none of its page text sent today, and under this proposal its kept text is sent. In a discovery run the discovery and lead-choice requests are already sent before any capture, today and under this proposal.

Proposed wording, applied only by the implementing change after approval of W5:

- `privacy-and-egress.md`, the OpenRouter web lookup row, added to its "what" cell: "for a page too large to review whole, only its nutrition tables and lists, the lines and headings around them, its main heading and its structured product data (part-read pages v1, #508)", and this document added to its contract cell.
- `privacy-policy.txt`, after "Captured source text and displayed food terms go to OpenRouter and the configured extraction and applicability providers": "When a page is too large to review whole, only its nutrition tables and lists, the lines and headings around them, its main heading and its structured product data are sent, and the review says that only part of the page was read."

## 10. Architecture gate

- **Responsibilities.** The projector parses and builds blocks, each with a structural unit key. A new pure type in `FoodGenericSearch` applies the selection. The domain type holds and validates the part-read record and the policy id. The application reviewer owns source order and passes the permission through the capture port. Admission owns the presentation and part-read consistency rule. Presentation owns the copy.
- **Dependency direction.** The selection file imports only Foundation and `FoodLedgerDomain`; `check-boundaries.sh` gains a rule for that file. Domain and application gain no new dependency.
- **Port change.** `FoodDocumentCapturing.capture` gains the part-read permission. The public capture and every fake pass the same contract tests for both values.
- **Extension axes.** None new. The vocabulary, unit definitions, windows and thresholds are closed values under one policy id.
- **Named risks.** A basis or state qualifier outside the context window; a label far from its panel (section 4.5); a hostile page shaped to look like a nutrition table; a page with no `h1` block losing its title. The mitigations are the all-or-nothing rule, the nearest-heading rule, the visible part-read line, the existing review and confirmation, and the replay in section 11. None removes the need for the person to read the result.

## 11. Contract tests the implementing change must add

1. Boundary identity: 512 blocks and 30,000 characters give today's output; 513 blocks or 30,001 characters enter selection; a kept total of exactly 512 blocks and 30,000 characters passes.
2. Every fixture with retained bytes re-projects equal.
3. A page over the bounds with malformed JSON-LD after the bound gives `responseTooLarge` and the reviewer still tries the second lead; cancellation during the extended walk stays cancellation.
4. All or nothing: two panels with a shared label inside one window are both kept with the label; with the label outside every window both are kept without it; a page whose required set does not fit is refused; no unit is split, ranked or cut.
5. Units: table, nested table, a header row wrapping a nested table, a `caption` basis, a definition list, a `dl` with wrapped pairs, lone `dt` and `dd` blocks, a price-per-100 g table, a unit over budget.
6. Matching: unspaced forms, Chinese terms, menu noise; the vocabulary is pinned.
7. Context and identity: a context block over 1,400 characters ends the window; the nearest heading is kept at any distance; a page with no `h1` block; the `h1` counted at exactly 512 blocks.
8. JSON-LD: one inside a context window; fill order; one over budget is skipped and a later one is still tried; none causes a refusal.
9. Determinism; original ids and paths; unique ids; the locator length edge gives `responseTooLarge`.
10. Domain: the part-read record validates against the actual blocks; a locator version and `partialRead` mismatch is refused; full counts within the bounds are refused; documents with and without the record round-trip; existing fixtures and golden bytes are unchanged.
11. Admission: a presentation and `partialRead` mismatch is refused in both directions.
12. Compatibility: a part-read review is refused by an older build at import or archive verification under the chosen contract number, not at reopen; every stored v1 and v2 review is admitted unchanged; a v3 manifest without `partialRead`, and a v2 manifest with it, are refused.
13. Provider: no request body contains the part-read record; the catalogue output for a part-read document is pinned; the `.jev` request body for a part-read document is pinned, including its locators.
14. Presentation: golden content for `web-lookup-review-v2`; an unknown presentation fails closed; a reopened part-read review still shows the line.
15. Capture port: shared contract tests for the public capture and the fakes, for both permission values.
16. Reviewer: a supplied address; no selector; a first lead over the bounds with and without another lead; a second lead that abstains after a first lead over the bounds; an empty first extraction followed by a second page over the bounds; the capture count never above two.
17. PDF and `text/plain` sources over their bounds are still refused.
18. Boundaries: the selection file's imports.
19. An offline replay on a fresh set of pages over the bounds that were not used in section 1.1, reported as a separately labelled experiment, before release. It includes at least one live review per page class so that binding on kept blocks is shown, not assumed.

The evaluation steps for search and query changes in `.github/workflows/ios-ci.yml` run for the implementing change.

## 12. Left to the phase gate

- The exact nutrient vocabulary and matching rule, including the Chinese rule.
- The food contract number, the v3 pipeline triple and the SQLite schema position (section 5.2).
- Whether any existing test assumes contiguous block ids, and whether the extraction instruction text assumes a whole page.
- The refusal copy for pages that are still refused (section 6).
- The interaction with [AI search by name v1](ai-name-search-v1-proposal.md) (#488), which also reads page addresses.
- Whether the context windows hold on the fresh replay set, and whether list-style panels (W6) are common enough to need a later version.

## 13. Out of scope

Raising the 30,000-character or 512-block bounds; PDF and plain-text sources; panels outside tables and definition lists; host-specific adapters; choosing between competing panels; any change to Confirm.

## 14. Review record

- The design behind this document had one blind architecture gate before it was written; its findings shaped sections 4 to 7.
- This document had one local Qodo review (three findings: the admission order of identity and JSON-LD blocks against the budget, a label separated from its panel, and a first lead never part-read after a failed second lead) and one blind hostile review against the source at `main` 37cad25 (verdict: ready with changes). All of their findings are folded in or recorded: the admission order in section 4.3, the label limit in section 4.5, the source-order cost in section 7, compatibility in section 5.2, and the open items in section 12.
- A second local Qodo review of the revision raised two further points, both folded in: the privacy wording now names every kind of kept block (section 9), and the compatibility recommendation now fits the closed one-triple-per-version admission table (section 5.2). It left one earlier point open, the first lead that is not part-read after a failed second lead; that is the stated cost of decision W4 (section 7), not an oversight.
- The edits made after that second review have had no review of their own.
- Not reviewed by the owner. Not validated on a device. The measurement in section 1.1 has the limits listed there.
