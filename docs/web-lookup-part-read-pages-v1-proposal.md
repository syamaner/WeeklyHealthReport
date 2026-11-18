# Web lookup: larger pages, part-read pages and panel choice v1 (proposal)

Status: **accepted by the owner on 17 November 2026; phase 1 merged (PR 512)** (#508): the larger bounds of section 4 and the stored format and admission of manifest v3 (sections 6 and 8.4), with a writer for offer row 1 only ([phase 1 gate](web-lookup-larger-pages-phase1-gate.md)); phase 2, panel choice (sections 8 and 9, [phase 2 gate](web-lookup-panel-choice-phase2-gate.md)), implemented in PR 515 on `feat/508-panel-choice`, with contract test 20 amended to an app-hosted route test and a rendered screenshot. Part-read selection (sections 5 and 7), phase 3, is implemented on `feat/508-part-read-selection` ([phase 3 gate](web-lookup-part-read-phase3-gate.md)), which settles the vocabulary and an extent rule (section 13). The live measurement of section 12, test 21, has not been run. The owner took decisions W1 to W9 and answered questions O1 to O3 the same day (sections 2 and 8.5), then accepted the text as a whole. Answer O4 was added afterwards the same day. When implemented it amends [generic web proposal integration v1](generic-food-proposal-integration-v1.md) and [generic food review manifest v2](generic-food-review-manifest-v2.md). The file keeps its original name so that links hold. Documentation only: no app code, test or fixture changes with this document, and `privacy-and-egress.md` and `privacy-policy.txt` are edited only by the implementing change, with the wording in section 10. The pull request that adds this document closes nothing.

It has three parts, in the order a page meets them:

1. **Larger pages** (section 4): the page bounds rise so that ordinary product pages are read whole.
2. **Part-read pages** (sections 5 to 7): a page beyond the new bounds is read in part, keeping every nutrition section, or refused.
3. **Panel choice** (section 8): when a page yields competing panels, the person picks one.

## 1. Problem and evidence

Web lookup captures a public page, projects it to text blocks, and sends those blocks to the provider for a bounded review. `GenericFoodDocumentProjector.project` refuses a page with `responseTooLarge` once its projected text passes 30,000 characters or it would emit a 513th block (`GenericFoodDocumentProjector.swift:30`). `CapturedFoodDocument.validate` enforces the same bounds on the stored type (`GenericFoodProposal.swift:38` and `:40`). The person sees "The source is too large for this bounded review. Choose a more specific food page." (`GenericFoodProposalReviewView.swift:146`).

A device report on TestFlight 0.3.0 (37) showed an ordinary shop product page refused this way. There is no more specific page: it is the product page. It is not established whether that run was a supplied page address or a discovery run.

That page also prints its main panel for two differently sourced batches, with different values. Today two candidates from one page with the same name, brand, preparation and basis but a different declared value are both marked `conflicting_candidates` (`GenericFoodProposal.swift:165` to `:166`), neither is eligible, and the screen says the source "gives conflicting values for this food, so it cannot be used". Only the candidate the applicability check suggests can ever be confirmed (`GenericFoodProposalReview.swift:54` to `:56`).

### 1.1 First measurement (17 November 2026)

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

A trial part-read rule kept every table that had a per-100 header or at least three rows with a nutrient term and a digit, with 12 blocks before and 6 after, the first `h1` and every JSON-LD block: 141 blocks and 12,317 characters on A, 30 blocks and 1,550 characters on B, 30 blocks and 1,755 characters on C. A word-based rule (any block containing a nutrient word) was tried and rejected: on A it marked 150 blocks holding 39,948 characters.

### 1.2 Wider measurement (17 November 2026)

The same scratch build was run over 43 projections of public product pages: the seven above and 36 more (two of the 36 repeat pages already in the seven). Forty-seven addresses on 25 hosts were tried, at most eight per host; 17 returned a block, a challenge or an error to a plain download. Eleven of those gave nothing to project. The other six returned a challenge or error body that projects to two blocks; those six are counted among the 43 although they are not product pages. They carry no nutrition, so the counts below of pages with nutrition and of refusals are unaffected, but they lower the smallest and median figures in the table.

| | Smallest | Median | 75th percentile | 90th percentile | Largest |
|---|---:|---:|---:|---:|---:|
| Blocks | 2 | 196 | 784 | 818 | 832 |
| Characters | 57 | 7,425 | 13,382 | 13,991 | 55,921 |

- 25 of the 43 carry nutrition (a nutrition table, or at least four blocks pairing a nutrient term with a quantity). Today's bounds refuse 11 of those 25.
- Of the 12 projections over today's bounds, 11 exceed only the block bound (784 to 832 blocks, 12,462 to 15,058 characters) and one, page A, exceeds both.
- All 43 fit within 1,024 blocks and 60,000 characters. The largest raw page was 1.04 MB.

### 1.3 Limits of this evidence

- The sample leans on two retailers and is a development sample, not a held-out set. Sites that block a plain download are missing.
- The trial part-read rule was a script, not production code, and differs from section 5: it admitted a table on a per-100 header alone, kept every JSON-LD block, and had no definition-list units, no nearest-heading rule and no long-block rule. Definition-list units have no evidence yet.
- No provider call was made. Nothing here shows that a review on a larger page, or on kept blocks, yields a bindable proposal, or what it costs in time and tokens.
- The page `title` is projected as a plain text block and is not kept by the part-read rule, which matters on a page with no `h1` block.
- No sampled page exceeds the bounds chosen in section 4. Sections 5 to 7 are therefore not exercised by this evidence at the new bounds: the trial figures for A, B and C describe pages that would now be read whole.
- The retained pages over the bounds from the earlier evaluation were not available and are not in the sample.

## 2. Owner decisions (17 November 2026)

| # | Decision | Outcome |
|---|---|---|
| W1 | Supersede the two recorded "no truncation" decisions with a bounded selection | Yes ("the trade-offs are worth it in principle") |
| W2 | When the nutrition sections do not all fit | Keep every panel; never decline because there are several; refuse only when they cannot all fit |
| W3 | Part-read screen wording | "Only part of this page was read." and "Not in the part read" |
| W4 | Source order | As proposed in section 7 |
| W5 | Egress | Approved in principle; the new maximum chosen under W9 |
| W6 | Layouts in v1 | Tables and definition lists first |
| W7 | Older builds | The owner is not concerned with how older builds treat the new reviews. Every review already saved must keep opening as it does now, which is a product rule and not part of the choice |
| W8 | Competing panels | The person can pick between them; the model's suggestion is a pre-selection they can override (added by the owner) |
| W9 | Page bounds | Raise them so that ordinary product pages are read whole, with part-reading as the fallback beyond; the owner chose the larger of two offered limits: 2,048 blocks and 100,000 characters |

The owner also answered questions O1 to O3 the same day and then accepted this text as a whole. Answer O4 followed after acceptance. All four answers are in section 8.5.

## 3. What this supersedes

On acceptance:

- Integration v1, "Public HTML size gate": the sentence that the "512-block and 30,000-text-character limits remain" is replaced by the bounds in section 4, and "No truncation, decompression or host exceptions are added" is replaced by the bounded selection of section 5 for HTML pages beyond the new bounds. Decompression and host exceptions stay excluded.
- Integration v1, the later checkpoint: an exploratory main-landmark-only projection still exceeded the block bound for two retained pages, "so no main-content truncation policy was adopted". This proposal is not a main-landmark rule; sections 1.1 and 1.2 are its evidence.
- Manifest v2, section 2 ("Gate decision as data"): admission v6 rejects a `selectionChoice` different from `candidate.id`. That stays true for manifest v2. Section 8 defines a third manifest version in which the person's choice is recorded beside the model's.
- Manifest v2, section 3, "New saves always write v2", and section 4, where only the suggested candidate can be prepared and `clarify` and non-preferred alternatives stay blocking: superseded for manifest v3 only (section 8).
- Manifest v2, section 9, "Content of `web-lookup-review-v1`": unchanged. A second identifier is added beside it (section 9).
- The rule that candidates which conflict with each other cannot be used (section 8.1).

Historical evaluation outcomes recorded as `capture_responseTooLarge` stay as recorded.

## 4. Larger pages (decision W9)

| Bound | Today | Proposed |
|---|---:|---:|
| Blocks per captured document | 512 | 2,048 |
| Characters per captured document | 30,000 | 100,000 |

- Both the projector's output bound and `CapturedFoodDocument.validate` move together. The projector applies one output bound to HTML and `text/plain`, so a whole `text/plain` source rises to the same bounds; selection (section 5) is for HTML only.
- Admission of stored v1 and v2 reviews keeps today's bounds (section 8.4): the higher domain bound does not widen what they accept.
- Unchanged: raw bytes at most 3 MB, at most 50,000 nodes, depth at most 64, UTF-8, media types, HTTPS and public-address pinning, connection and deadline limits, the 150-second review deadline, at most two captures per run. PDF projection keeps its own bounds.
- A page within today's bounds projects to exactly today's output. A page between the old and new bounds projects whole, by the same walk, with no selection.
- Whole-page projections keep the version string `swift-food-document-blocks-v6`: the walk and every coordinate are unchanged, and only the admission bound moves. The integration contract describes the 3 MB change under "projection v6"; this change keeps the name, so that fixtures with retained bytes keep re-projecting equal. The cost is that v6 no longer implies the old output bound. The phase gate may revisit this.
- What actually limits a review of a 100,000-character document is not established and is measured before release (section 12, test 21). Known from the source: the whole catalogue goes to two different models, one for extraction and one for applicability; their output allowances are 4,096 and 1,800 tokens; each model call has 90 seconds per attempt and 120 seconds in all, inside the 150-second run that also covers discovery, lead choice and capture; there is no client-side cap on the request body; the catalogue excerpts long blocks at 1,400 characters and repeats 100 characters of overlap per excerpt. The model context limits are not in the source.
- A saved review stores its whole document, including a locator of up to 500 characters per block. At the new bounds one saved review can exceed 1 MB. Whether storage or archives need a limit is left to the phase gate.

The chosen bounds are about two and a half times the largest block count and nearly twice the largest character count in section 1.2.

## 5. Part-read selection (`food-document-block-selection-v1`)

Selection runs only for an HTML page whose full projection exceeds the bounds of section 4. A `text/plain` source over those bounds, and a PDF over its own unchanged bounds, are refused as today.

### 5.1 The walk

The walk continues past the output bounds to the end of the document. No further block or character ceiling is added; the 3 MB and 50,000-node gates bound the walk, and the run deadline and cancellation still apply to it and to the matching. If the walk meets any error other than cancellation after the point where the projection would have refused (for example malformed JSON-LD), the result is `responseTooLarge`, so the failure class and the fallback to another lead do not change. Cancellation stays cancellation.

### 5.2 The rule

1. **Structural units.** A table unit is every emitted `tr` block whose nearest ancestor table is the same table, plus that table's `caption` block if it has one. A definition unit is every emitted `definition_row` block whose nearest `dl` ancestor is the same list. Lone `dt` and `dd` blocks, and rows the projector emits as other block kinds (for example a row that wraps a nested table), belong to no unit. The projector passes each block's unit key to the selection as data; the selection does not parse locator strings.
2. **Nutrition units.** A unit is a nutrition unit when at least three of its blocks contain a term from the closed nutrient vocabulary together with a digit. A per-100 basis in the caption or first emitted row is not enough by itself, so a price-per-100 g table is not a nutrition unit. The vocabulary and the matching rule are published in the implementing change and pinned by tests. Matching uses explicit look-arounds, not word boundaries, so "Per100g" and "61kcal" match; Chinese terms have their own rule.
3. **Context.** Each nutrition unit takes up to 12 blocks before it and up to 6 after it. A context block longer than 1,400 characters (the provider excerpt length, `FoodProposalEvidenceCatalog.maximumExcerptCharacters`) ends the window on that side and is not kept. A JSON-LD block inside a window is treated under step 6, not as context. Each nutrition unit also takes the nearest heading block (`h1` to `h6`) before it, whatever the distance. Overlapping windows merge.
4. **Identity.** The first block of kind `h1`, if the page has one, is required.
5. **All or nothing (decision W2).** The required set is every nutrition unit, its context and nearest heading, and the first `h1` block. If the required set is within the bounds of section 4, it is kept. Otherwise the result is `responseTooLarge`, as today. No nutrition unit is dropped, ranked or cut, and no block is truncated. A page is never refused because it has several nutrition units.
6. **JSON-LD.** After the required set is admitted, JSON-LD blocks are tried in document order. Each is added if both totals stay within the bounds; one that does not fit is skipped and later ones are still tried. A JSON-LD block is never a reason to refuse and never displaces a required block.
7. **No nutrition unit.** If the page has none, the result is `responseTooLarge`, as today.
8. **Output.** Kept blocks keep their original order, their ids from the full projection (so block `b137` stays `b137`) and their locator paths. Their locators carry the version string `swift-food-document-blocks-v7-selected`, a named constant. If a locator would exceed 500 characters with the longer string, the result is `responseTooLarge`; nothing is shortened.
9. `rawSha256` remains the hash of the complete raw bytes, and the document id is unchanged.

Counts are `Character` counts of the normalised block text, as today. The windows 12 and 6, the 1,400-character rule and the three-block threshold are closed policy values of `food-document-block-selection-v1`. Changing one of them, the vocabulary or a unit definition is a new policy version.

### 5.3 What selection never does

No host-specific rule, no host exception, no model in the selection, no script execution, no truncation inside a block, no cross-source merging, no value produced by the selection itself, no choice between panels. The same bytes always give the same kept blocks.

### 5.4 Known limit: a label far from its panel

A line that tells two panels apart (page A's batch label) is kept only when it falls inside a context window or is the nearest heading. Kept or not, plain page text does not say which panel a shared label belongs to; that is true of a whole page too. Both panels reach the review and the person chooses (section 8), with the page open beside them if they need it.

## 6. The part-read record

`CapturedFoodDocument` gains an optional member `partialRead`:

| Field | Meaning |
|---|---|
| `policy` | `food-document-block-selection-v1` (the constant lives in `FoodLedgerDomain`) |
| `fullBlocks`, `fullCharacters` | counts of the full projection |
| `keptBlocks`, `keptCharacters` | counts of the stored blocks |

- It is absent for every whole page, so existing documents, manifests, archives and fixtures decode and re-encode with identical bytes.
- `validate()` checks it: a known policy; kept counts equal to the actual blocks; full counts at least the kept counts and over at least one bound. It also refuses a document whose locators carry the selected version string without `partialRead`, or the reverse.
- It is retained in the review manifest and shown in Developer tools. The app has no screen today that reopens a saved review; the screen content of section 9 is defined so that it can be rebuilt from the manifest alone if one is added.
- It is not sent to any provider. The extraction and applicability routes send only catalogue entries (id, kind, text). One route, the `.jev` selection route, serialises whole documents (`OpenRouterFoodProvider.swift:233`); production composes the applicability route, and the `.jev` route is used by defaults, tests and the probe. The implementing change excludes the record on that route and pins its request body. On that route the locators are still sent, so the selected version string and the non-contiguous ids disclose that a page was read in part; that is accepted, since the route already sends locators.

## 7. Source order (decision W4)

Today a second lead is tried only after an empty extraction or a recoverable acquisition failure, which includes `responseTooLarge` (`GenericFoodProposalReview.swift:160`), with at most two captures per run.

The capture port gains a part-read permission, passed by the reviewer for each capture. Without it a page beyond the bounds is refused. The larger bounds of section 4 apply to every capture.

- **Supplied address, or a run with no source selector.** One capture, permission granted.
- **Discovery run.** Before the first capture the reviewer evaluates one predicate: does the discovery result hold another admissible lead? If not, the first capture has permission. If so, the first capture has none; a page beyond the bounds is refused and the run moves on.
- **Second capture.** It always has permission, whether the run reached it after a refusal or after an empty first extraction.
- **No way back.** If a second lead exists but is not captured (the selector abstains, a market conflict, a provider error), or its capture fails for another reason, the run ends as today. The first page is not part-read in that run: doing so would need a third capture or retained bytes. The person can give that page's address directly, which reads it in part. The owner accepted this cost.
- The two-capture limit, one discovery, no repeated step and no merging are unchanged.

## 8. Panel choice (decision W8)

### 8.1 What changes

- **Conflict between candidates no longer makes them unusable.** Two candidates from one page that differ in a declared value are still detected and still marked, but the mark now means "the person must choose", not "cannot be used". A candidate with a conflict inside itself (a nutrient whose unknown reason is `conflict`) stays unusable.
- **The person may confirm a candidate other than the model's suggestion.** The model's choice stays recorded as data and never becomes authority; the person's explicit pick is what the review acknowledges.

### 8.2 Choosable candidates

A candidate is choosable when it is literally bound to the captured document, has a basis unit, has at least one declared nutrient and has no nutrient whose unknown reason is `conflict`. This is today's `selectionEligible` without the status test.

The applicability check runs over the choosable candidates. Today it is skipped when no candidate is eligible, which includes the conflicting case, and when no selector is composed; under this proposal a page with two conflicting panels still gets the check, and the check may answer with one of them, `clarify` or `none`. Every place that tests `selectionEligible` to build, validate or permit a choice moves to the choosable rule; the implementing change lists them. The applicability instruction says nothing today about candidates that conflict with each other; whether its text and version change is left to the phase gate.

Extraction still returns at most three candidates per page, as today. A page with more panels than that offers at most three.

### 8.3 When a choice is offered

The table is keyed on the answer the check recorded (`selection.choice`, with the ranking available), not on the derived suggestion, which also reads `clarify` when the check never ran. A choosable candidate whose basis conflicts with the request is never offered, whether or not it is the suggestion.

| Recorded answer of the check | Offered |
|---|---|
| A choosable candidate, and no other choosable candidate | That candidate, as today |
| A choosable candidate, and other choosable candidates exist | The suggestion and only the choosable candidates that compete with it (the same name, brand, preparation and basis as the suggestion); the suggestion is pre-selected and the person can change it. A choosable candidate for a different product is not offered, so the person cannot confirm another food's values |
| `clarify`, and two or more choosable candidates conflict with each other (same name, brand, preparation and basis, a different declared value) | Those conflicting candidates; nothing is pre-selected and the person must pick before the action is enabled. The screen carries the warning line of answer O4, because the check did not confirm the match |
| `clarify` in any other case | Nothing, as today (answer O1) |
| `none`; the check not run, unavailable or failed | Nothing, as today |

A market conflict ends the run before any review exists, as today. Two candidates with the same name and the same values (a page that prints one panel twice) do not conflict; they are both offered as they are, and removing such duplicates is left to the phase gate.

No candidate is ever selected automatically beyond the pre-selection shown, and nothing is saved by a selection. The single "Use this source" action, the scope choice and the Confirm screen with its one Log action are unchanged.

### 8.4 What is recorded

A new choice policy identifier, known only to manifest v3 (today `FoodProposalReviewGateRecord.knownChoicePolicies` is one set shared by every version; it becomes per version), and a third manifest version, `reviewed-web-proposal-v3`, with its own entry in `ReviewedFoodProposalConfirmation.admittedPipelines`. That table ties each manifest version to exactly one pipeline triple, so a new behaviour needs a new version; the v1 and v2 entries are untouched and every stored review is admitted exactly as today.

Manifest v3 has its own strict manifest and gate types, with its own closed key sets; the v2 types and their key sets are not changed. The known presentation and choice-policy sets are per manifest version: v1 and v2 admit only what they admit today. A v1 or v2 manifest whose document has `partialRead`, a selected-version locator, more than 512 blocks or more than 30,000 characters is rejected, as today. The constant that identifies v2 is not repointed, and a regression-only v2 writer is kept for tests, as was done for v1.

Manifest v3 is manifest v2 with:

- `gate.selectionChoice`: the model's answer, unchanged in meaning; it may now differ from the confirmed candidate and may be `clarify`;
- `gate.personChoice`: the id of the candidate the person confirmed; it must equal `candidate.id`;
- `offered`: the candidates shown to the person, complete and in display order, so that what was acknowledged can be rebuilt from the manifest alone. It contains the confirmed candidate;
- the optional `document.partialRead` of section 6;
- `review.presentation`: `web-lookup-review-v2` (section 9).

Admission for v3 rejects, at save and at reopen: `rankingAvailable` false; `selectionChoice` `none`; `personChoice` different from `candidate.id`; a confirmed candidate that is not in `offered`; an offered candidate that does not bind to the retained document or is not choosable; an offered candidate whose basis conflicts with the request; `selectionChoice` `clarify` unless at least two offered candidates conflict with each other; a `selectionChoice` that names a candidate not in `offered`; offered candidates that do not all share one name, brand, preparation and basis; more than three offered candidates or a repeated id; `representativeSourceOnly` true with `exact_product` scope; an unknown choice policy or presentation; a `partialRead` that fails section 6. Presentation cannot construct a permitting gate or supply `offered`; both come from the reviewer's result.

New builds write v3 for every web review, so production has one writer. An archive holding v3 evidence needs at least food contract 5, as v2 does; whether it needs a higher number is left to the phase gate. Following decision W7, no work is planned to make an older build refuse or read a v3 review gracefully.

### 8.5 Owner answers to questions O1 to O4 (17 November 2026)

- **O1, answered: keep it blocked.** When the check answers `clarify` and the cause is not competing panels (one candidate only, or candidates that are different products), the person cannot use a candidate, as today. The check downgrades its answer to `clarify` when it judges the identity, preparation or basis a mismatch or uncertain, and it does not record which, so the app could not say what to look out for.
- **O2, answered: approved as proposed.** The copy for the panel list in section 9 stands: "Suggested", "Choose a panel", "This page gives more than one set of values. Choose the one that matches your food." and "Different values".
- **O3, answered: approved.** A page whose candidates conflict gets the applicability request that is skipped today (section 10). The destination and the kind of content are unchanged; what changes is when a request happens. The approval covers this proposal's text. The wording in `privacy-and-egress.md` and `privacy-policy.txt` changes only with the implementing change and is shown to the owner before it lands.
- **O4, answered: offer with a warning.** Raised by the independent review at acceptance. The check turns a named candidate into `clarify` when any of its four facets (identity, exclusions, basis, nutrient meaning) is not supported (`OpenRouterFoodProvider.swift:274-283`) and does not keep the facets, so row 3 of the offer table cannot tell a conflict between panels from a doubt about the food itself: a page for a different brand with two batch panels also reaches row 3. The owner chose to offer the pick in every row 3 case with a visible warning, not to record the facets and gate on them. The facets are not added to manifest v3. Answer O1 is unchanged for every other `clarify`.

## 9. Screen contract `web-lookup-review-v2`

Written for every v3 review. `web-lookup-review-v1` and its golden content are unchanged and remain the contract for stored v1 and v2 reviews.

Content: everything in `web-lookup-review-v1`, with these differences:

- **Panel choice.** When more than one candidate is offered, the screen lists each with its name, its distinguishing details (the existing `distinguishingDetails`), its basis label and its declared values. Candidates that conflict with each other have the same name, brand, preparation and basis, so their distinguishing details can only number them; each such row therefore also shows the nearest kept heading above its panel and its first quoted line, and the person chooses on those and on the values. One row is selected at a time; the details, quotes and limitations shown below are those of the selected candidate.
- **Words (answer O2).** The suggested candidate carries the word "Suggested". Candidates that differ in a declared value carry "Different values" in place of "Conflicting values". When nothing is pre-selected the section is titled "Choose a panel", with the line "This page gives more than one set of values. Choose the one that matches your food.", the summary line does not say that none suits, and the reason the action is disabled is shown beside it. The sentence that the source "gives conflicting values for this food, so it cannot be used" is not shown for a v3 review; a candidate with a conflict inside itself keeps its existing status text.
- **Warning line (answer O4).** Whenever the choice is offered on a `clarify` answer (row 3 of section 8.3), the section shows a line saying that the check did not confirm this page matches the food asked for. It is text, not colour alone, it sits above the panels and it stays visible after a pick. Wording, approved by the owner on 17 November 2026: "The check could not confirm this page matches your food. Compare the name, brand and variant before you choose." The line is part of the golden content and is rebuilt from a retained v3 manifest (it follows from `selectionChoice` `clarify`), so a reopened review shows it too.
- **Part-read line.** For a part-read document only: "Only part of this page was read."
- **Group title.** For a part-read document only, the "Not stated" group is titled "Not in the part read". Its membership is unchanged (every nutrient that is neither declared nor unusable). "Not usable" is unchanged. Unknown stays unknown and is never shown or saved as zero.

Selection state is conveyed by the selected trait and a visible mark, never by colour alone; each row is at least 44 points high and has a VoiceOver label naming the panel and whether it is the suggestion. Developer tools shows the choice policy, the offered ids, and for a part-read document the policy id and the four counts.

The refusal copy is unchanged in v1, including its advice to choose a more specific page. Rewording it for pages that are still refused is left to the phase gate.

## 10. Privacy and egress (decisions W5 and W9)

Destinations and content class (captured public source text) do not change. Three things change:

- **Amount.** The most page text one captured document can carry rises from 30,000 characters in 512 blocks to 100,000 characters in 2,048 blocks. A run still captures at most two pages.
- **Timing.** A page over today's bounds has none of its page text sent today. Under this proposal it is sent, whole or in part. In a discovery run the discovery and lead-choice requests are already sent before any capture, today and under this proposal.
- **Requests (answer O3).** A page whose candidates conflict with each other gets the applicability request, which today is skipped for it. It carries the conflicting candidates with their page quotes, and is subject to the existing limit of three attempts.

The 100,000 characters are of distinct page text; the catalogue repeats up to 100 characters of overlap per excerpt of a long block. On the production route the part-read record and locators are not sent. (Correction, 18 November 2026, from the review of PR 519: this sentence also said that original block ids are not sent. The catalogue sends its own entry ids, but the applicability request carries the choosable candidates whole, and their evidence names original block ids, as it already did for whole pages before #508. For a part-read page those ids can show that it was read in part and roughly where. No privacy document claimed otherwise, and nothing about what is sent changes.) Picking a panel, preparing a confirmation and saving send nothing.

Proposed wording, applied only by the implementing change:

- `privacy-and-egress.md`, the OpenRouter web lookup row, added to its "what" cell: "at most 100,000 characters in 2,048 blocks per captured page (part-read pages v1, #508); for a page larger than that, only its nutrition tables and lists, the lines and headings around them, its main heading and its structured data blocks", and this document added to its contract cell.
- `privacy-policy.txt`, after "Captured source text and displayed food terms go to OpenRouter and the configured extraction and applicability providers": "A page is sent whole up to a fixed size. When a page is larger than that, only its nutrition tables and lists, the lines and headings around them, its main heading and its structured data are sent, and the review says that only part of the page was read."

## 11. Invariants and architecture gate

Invariants:

- **Unknown is never zero.** A nutrient outside the kept blocks, or not declared by the chosen panel, is unknown.
- **Competing panels stay visible.** No nutrition unit is dropped by selection. At most three candidates are extracted, as today, and every one that is offered is shown. The suggestion is only a pre-selection the person can change.
- **Every save is an explicit action bound to its evidence.** The person's pick and the "Use this source" tap are recorded with the offered candidates and the document; model output never authorises nutrition by itself.
- **Binding is unchanged.** A quote must be found in a kept block, looked up by id, and numeric context is checked against the original block text.
- **Stored formats.** Stored v1 and v2 reviews and every document without `partialRead` are byte-identical before and after.
- **Accepted risk (answer O4).** On a `clarify` answer with conflicting panels the person may confirm a panel from a page the check doubted for a reason it did not keep, including a different brand or product. The safeguards are the warning line, no pre-selection, the explicit pick, the scope choice and Confirm with its single Log action. Nothing is selected or saved without those steps.
- **No medical interpretation, no automatic saving.** Confirm and its single Log action are untouched.

Architecture gate:

- **Responsibilities.** The projector parses and builds blocks, each with a structural unit key. A new pure type in `FoodGenericSearch` applies the part-read selection. The domain holds the bounds, the part-read record, the policy id and the choosable rule. The application reviewer owns source order, passes the permission through the capture port and decides what is offered. Admission owns the v3 rules. Presentation owns the list and the copy.
- **Dependency direction.** The selection file imports only Foundation and `FoodLedgerDomain`; `check-boundaries.sh` gains a rule for that file. Domain and application gain no new dependency.
- **Port change.** `FoodDocumentCapturing.capture` gains the part-read permission. The public capture and every fake pass the same contract tests for both values.
- **Extension axes.** None new. The bounds, vocabulary, unit definitions, windows, thresholds and the offer table are closed values under versioned identifiers.
- **Named risks.** More text per review (cost, time, and more room for misleading page text); a basis or state qualifier outside a context window; a label far from its panel; a page shaped to look like a nutrition table; a page with no `h1` block losing its title; a person picking the wrong panel, including, on a `clarify` answer, a panel from a page for a different product (the accepted risk of answer O4, above). The mitigations are the bounds, the all-or-nothing rule, the nearest-heading rule, the visible part-read line, the panel list showing each panel's own values and details, the existing review and confirmation, and the measurements in section 12. None removes the need for the person to read the result.

## 12. Contract tests the implementing change must add

Bounds and projection:

1. Boundary identity at the new bounds: 2,048 blocks and 100,000 characters project whole; a 2,049th block or a 100,001st character enters selection (with permission) or refuses (without).
2. A page within today's bounds, and one between the old and new bounds, project whole with the v6 version string; every fixture with retained bytes re-projects equal.
3. A page over the bounds with malformed JSON-LD after the bound gives `responseTooLarge` and the reviewer still tries the second lead; cancellation during the extended walk stays cancellation.
4. A `text/plain` source within the new bounds projects whole and one beyond them is refused; a PDF over its own bounds is still refused although the domain bound is higher.

Selection:

5. All or nothing: two panels with a shared label inside one window are both kept with the label; with the label outside every window both are kept without it; a page whose required set does not fit is refused; no unit is split, ranked or cut; a page with many small nutrition units that fit is kept.
6. Units: table, nested table, a header row wrapping a nested table, a `caption` basis, a definition list, a `dl` with wrapped pairs, lone `dt` and `dd` blocks, a price-per-100 g table, a unit over budget.
7. Matching: unspaced forms, Chinese terms, menu noise; the vocabulary is pinned.
8. Context and identity: a context block over 1,400 characters ends the window; the nearest heading is kept at any distance; a page with no `h1` block; the `h1` counted at exactly the block bound.
9. JSON-LD: one inside a context window; fill order; one over budget is skipped and a later one is still tried; none causes a refusal.
10. Determinism; original ids and paths; unique ids; the locator length edge gives `responseTooLarge`.

Stored shapes and admission:

11. Domain: the part-read record validates against the actual blocks; a locator version and `partialRead` mismatch is refused; full counts within the bounds are refused; documents with and without the record round-trip; existing fixtures and golden bytes are unchanged.
12. Every stored v1 and v2 review is admitted and reopened unchanged, and the retained golden v2 bytes still decode and rehash through the regression writer; a v2 manifest carrying a v3 key, the new choice policy, `web-lookup-review-v2`, a part-read document or a document over today's bounds is rejected; golden v3 bytes pin key names and order; one failing case per v3 admission rule in section 8.4; `minimumContractVersion` with v3 evidence.
13. Provider: no request body contains the part-read record; the catalogue output for a part-read document is pinned; the `.jev` request body for a part-read document is pinned, including its locators.

Review and choice:

14. One case per row of the offer table in section 8.3, including that the action is disabled until a pick when nothing is pre-selected; `clarify` with non-conflicting candidates; the check not run and no selector composed; a non-suggested candidate with a basis conflict is not offered and cannot be prepared; three candidates of which two conflict; two identical candidates.
15. Two candidates that differ in a declared value are both choosable and both offered; a candidate with a conflict inside itself is not. When the check names a candidate and the page also yields a choosable candidate for a different product, that other candidate is not offered, and a v3 manifest whose `offered` mixes products is rejected.
16. The applicability check runs for a page whose candidates conflict with each other, and its answer is recorded.
17. Presentation: golden content for `web-lookup-review-v2` with one candidate, with several, and part-read; the suggestion is named in words; an unknown presentation fails closed; the content rebuilt from a retained v3 manifest equals the content shown; presentation cannot supply `offered` or construct a permitting gate; picking a panel, preparing and saving make no network request. Golden content for a `clarify` review with conflicting panels carries the warning line of answer O4, before and after a pick and when rebuilt from the manifest; a review on a named candidate does not carry it.
18. Capture port: shared contract tests for the public capture and the fakes, for both permission values.
19. Reviewer source order: a supplied address; no selector; a first lead over the bounds with and without another lead; a second lead that abstains after a first lead over the bounds; an empty first extraction followed by a second page over the bounds; the capture count never above two.
20. A simulator UI test of the route: lookup, pick a panel, use the source, Confirm.

Before release:

21. A live measurement on a fresh set of pages not used in section 1, reported as a separately labelled experiment: review time and token use at the new bounds, binding on whole large pages and on part-read pages, and at least one page with competing panels taken through to Confirm. It includes at least one page beyond the new bounds, found or, failing that, constructed and labelled as such. It reports review time, token use and saved manifest size, and passes only if no timeout or refusal is attributable to size on either model route.
22. Boundaries: the selection file's imports.

The evaluation steps for search and query changes in `.github/workflows/ios-ci.yml` run for the implementing change.

## 13. Left to the phase gate

- The exact nutrient vocabulary and matching rule, including the Chinese rule.
- The new choice policy identifier, the v3 pipeline triple, whether the food contract number moves, and the SQLite schema position.
- The existing tests that pin today's refusals and must change (in the projector tests and the domain proposal tests).
- Removing duplicate candidates with equal names and values.
- Whether any existing test assumes contiguous block ids, and whether the extraction and applicability instruction texts assume a whole page or a single usable candidate.
- Whether the extraction routes need a larger output or context allowance at the new bounds.
- The refusal copy for pages that are still refused.
- The interaction with [AI search by name v1](ai-name-search-v1-proposal.md) (#488), which also reads page addresses.
- Whether the context windows hold on the fresh set, and whether list-style panels are common enough beyond the new bounds to need a later version.
- Notes from the independent review at acceptance (17 November 2026), none of which blocked accepting this text; each is settled before code:
  - Offer table row 3 cannot tell a conflict between panels from a doubt about the food itself. Settled by the owner as answer O4 (section 8.5): the pick is offered with a warning line, and the facets are not recorded.
  - Two candidates with the same name and the same values are both offered only under row 2; under `clarify` they do not conflict and nothing is offered. Test 14 needs one expectation per row.
  - The table needs a row, and a test, for a recorded answer that names a candidate whose basis conflicts with the request: nothing is offered.
  - "The same name, brand, preparation and basis" is pinned to the equality the conflict rule already uses (exact strings, basis amount and unit), in the offer rule, in admission and on the screen alike.
  - "A confirmed candidate that is not in `offered`" means equality of the whole candidate, not of its id alone.
  - Under `clarify`, admission accepts a third candidate of the same identity that conflicts with neither of the others, which row 3 would not offer; the two are aligned.
  - With an untouched pre-selection the record cannot tell a pick from a tap, as in v2 today; the wording "the person's explicit pick" in section 8.1 is softened, and whether the "no automatic selection" line in `AGENTS.md` needs a note about the pre-selection goes to the owner.
  - On a row 3 screen the prompt "Choose the one that matches your food." stands beside the warning that the check could not confirm the match. Their order, whether the prompt changes on that screen, and how VoiceOver reads the warning are settled with the golden content.
  - A v1 or v2 manifest whose document carries `partialRead` must be rejected by an explicit admission rule; it is not rejected by decoding alone.
- Whether this is one implementation phase or three (bounds, part-read, choice). The parts are separable in that order, and since no sampled page exceeds the new bounds, part-read may reasonably come last.

Settled by the phase 3 gate (18 November 2026), part of `food-document-block-selection-v1`:

- The vocabulary and matching rule are in [the phase 3 gate](web-lookup-part-read-phase3-gate.md), section 3.2. Read with it, the example in section 5.2 step 2 means "Per100g Energy" matches; a basis alone ("Per100g") carries no nutrient term.
- **Extent.** A unit's blocks need not be adjacent (a header row wrapping a nested table, a nested table). A nutrition unit's extent runs from its first to its last block; every block inside it except JSON-LD is required, with no length limit or window count, and the windows of step 3 count from the extent's ends. The walk is pre-order, so an extent never leaves its table or list.
- A JSON-LD block inside a window uses up its position, is not context and never ends the window.

## 14. Out of scope

PDF and plain-text sources; panels outside tables and definition lists; host-specific adapters; using a candidate when the check answers `none`; merging values across panels or sources; any change to Confirm.

## 15. Review record

- The part-read design had one blind architecture gate before it was written down.
- The first version of this document (part-read only) had one blind hostile review against the source at `main` 37cad25 and two local Qodo reviews; their findings were folded in.
- The owner then took decisions W1 to W9, two of which (W8 and W9) added the panel choice and the larger bounds. Sections 4, 8, 9 and 10 and the changes that follow from them were written after those decisions.
- The revised version had one blind hostile review against the source (ready with changes) and one local Qodo review. Their findings are folded in: per-version admission so that v1 and v2 accept nothing new, a retained v2 regression writer, an offer table keyed on the recorded answer and limited to competing panels for `clarify`, the offered candidates stored in full, the `text/plain` bound, the screen wording for a list with no pre-selection, the limits on a 100,000-character review, and the egress wording. The edits made after those reviews have had no review of their own.
- The owner then answered questions O1 to O3 (section 8.5); each answer matches what the text already proposed. A local Qodo review at that point raised three findings. One was folded in: when the check names a candidate, only the candidates that compete with it are offered, and v3 admission rejects an offered set that mixes products (the earlier text offered every choosable candidate, which could have let a person confirm a different product from the same page). One was already met by section 8.4 (`offered` holds complete candidates). One restated the no-way-back cost in section 7, which the owner accepted under W4. This last edit has had no review of its own.
- The owner accepted the text as a whole on 17 November 2026, knowing that the narrowed offer rule had not been reviewed separately. One blind invariant review then ran at the accepted text: pass with notes, nothing blocking. Its notes are listed in section 13 for the implementing change's architecture gate, and it corrected the account of the sample in section 1.2.
- The owner then answered the one note that review sent back (answer O4, section 8.5): offer with a warning. The O4 text, the warning line in section 9 and the accepted-risk line in section 11 were added after the merge of the accepted text and were then reviewed once by a blind invariant review, together with the row 3 sentence and the extension to test 17: pass with notes, nothing blocking. Following its first note the owner widened the approved wording of the warning line from "name and brand" to "name, brand and variant". Its second note goes to the phase gate (section 13). This last edit has had no review of its own.
- Not validated on a device. The measurements in section 1 have the limits listed in section 1.3.
