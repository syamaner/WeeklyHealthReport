# Web lookup part-read selection, phase 3: architecture gate

Status: **gate passed with changes, implemented on `feat/508-part-read-selection`, egress wording approved by the owner, 18 November 2026** (#508). Phase 3 of [web lookup part-read pages v1](web-lookup-part-read-pages-v1-proposal.md) ("the contract"): part-read selection (contract sections 5 to 7, decisions W1, W2, W4 and W6) and the section 10 egress wording for part-read pages. Phase 1 ([gate](web-lookup-larger-pages-phase1-gate.md), PR 512) already landed the larger bounds, the domain `FoodDocumentPartialRead` record with its `validate()` rules, the constants `food-document-block-selection-v1` and `swift-food-document-blocks-v7-selected`, the frozen manifest v3 format and admission, and the part-read line and group title as content rules that the screen already renders. Phase 2 ([gate](web-lookup-panel-choice-phase2-gate.md), PR 515) landed panel choice. This phase writes the part-read record for the first time; it must not change the v3 format, its admission, its pipeline triple, v1 or v2 admission, or any stored byte.

## 1. Scope

In:

- A pure selection type in `FoodGenericSearch` that applies `food-document-block-selection-v1` (contract section 5.2) to the blocks of a full projection.
- The projector: a structural unit key for every block, an extended walk past the bounds when part-reading is permitted, and the part-read document (kept blocks, selected-version locators, `partialRead`).
- The capture port gains the part-read permission; the public capture passes it to the projector; every fake honours it; one shared contract suite runs over the public capture and the fakes, for both values.
- The reviewer's source order (contract section 7).
- Developer tools: for a part-read document, the policy id and the four counts.
- `privacy-and-egress.md` and `privacy-policy.txt`: the contract section 10 part-read wording (section 8 below), shown to the owner before it lands.

Out: the refusal copy (unchanged, section 6); any change to the v3 format, admission, the offer table, Confirm or its single Log action; PDF and `text/plain` selection; list-style panels outside tables and definition lists; host rules; the live measurement (contract test 21, which runs once after this phase over all three phases, owner decision); AI search by name (#488).

## 2. Responsibilities and dependency direction

| Layer | Owns in this phase |
|---|---|
| Domain (`FoodLedgerDomain`) | Unchanged. `FoodDocumentPartialRead`, its constants, `selectionPolicyBounds` and the `validate()` rules are phase 1's and are only exercised now. |
| Infrastructure, selection (`FoodGenericSearch/FoodDocumentBlockSelection.swift`) | New pure type `FoodDocumentBlockSelection`. Input: the full projection as an ordered list of `(kind, text, unit)` where `unit` is an opaque unit key or none. Output: the kept positions in document order, or a refusal (`nil`). Holds the closed policy values (windows 12 and 6, the 1,400-character rule, the three-block threshold, the vocabulary and the matching rule). It never parses locators, never reads a host, never truncates and never produces a value. It calls `Task.checkCancellation()` in its loops (standard library, no import). The file imports only `Foundation` and `FoodLedgerDomain`; `check-boundaries.sh` gains a rule for this one file. |
| Infrastructure, projector (`GenericFoodDocumentProjector`) | Emits each block with its locator path and unit key (section 3.1). Without permission it refuses at the bound exactly as today. With permission and an HTML page over `FoodDocumentBounds.current`, it walks to the end, runs the selection, and builds the part-read `CapturedFoodDocument`: kept blocks with their original ids and paths, locators ending `;projection:swift-food-document-blocks-v7-selected`, and `partialRead` with the full and kept counts. `rawSha256` and the document id are those of the complete raw bytes. |
| Infrastructure, capture (`PublicFoodSourceCapture`) | Passes the permission to the projector. Nothing else changes (HTTPS, pinning, redirects, media types, 3 MB). |
| Application (`FoodLedgerApplication`) | `FoodDocumentCapturing.capture(_:partRead:)` with a closed two-value permission type. `GenericFoodProposalReviewer` decides the permission for each capture (section 5). No new dependency. |
| Presentation | The screen's part-read line and "Not in the part read" title already follow from `document.partialRead` under `web-lookup-review-v2` (phase 1 content, rendered in `GenericFoodProposalReviewView`); this phase adds a test that a projected part-read document reaches them. Developer tools gains one line (section 6). |
| Test support (`FoodLedgerTestSupport`) | `FoodDocumentCapturePortContracts`: the shared capture contract suite and a synthetic over-bounds page, in the pattern of `PastedLabelAITextPortContracts` (no XCTest import; returns its violations). |

Dependency direction is unchanged: the selection is infrastructure that depends on the domain only; the projector depends on the selection; the reviewer knows only the port and the permission.

## 3. The selection, settled

### 3.1 Structural unit keys

The projector already tracks the DOM path of every element it walks. The walk carries the path of the nearest ancestor `table` and the nearest ancestor `dl`.

- A block emitted with kind `tr` gets the unit key `table:<path of its nearest ancestor table>`.
- A block emitted with kind `caption` gets the key of its nearest ancestor table, so a caption joins its own table's unit.
- A block emitted with kind `definition_row` gets `dl:<path of the nearest ancestor-or-self dl of the element whose children are being walked>`. A `dl` whose pairs are wrapped in a `div` is one unit, because the nearest `dl` is the same. A `dt` and `dd` pair with no `dl` above it (for example directly under a `div`) has no unit.
- Every other block has no unit: lone `dt` and `dd` blocks, a row the projector does not emit as `tr` (one that wraps a nested table or structured data; its inner text blocks have no unit), a `caption` with block content inside it (its inner blocks are emitted under their own kinds), `json_ld`, headings, paragraphs, list items, `text`.
- Rows of a nested table belong to the nested table, never to the outer one.

The key is data passed beside each block; the selection compares keys for equality only. It is never added to `FoodDocumentBlock`, its locator or any stored or sent value.

### 3.2 Nutrient vocabulary and matching rule (`food-document-block-selection-v1`)

A block **matches** when its text contains at least one ASCII digit `0` to `9` and at least one vocabulary term under the rule for that term's script.

Matching runs over Unicode scalars. Only ASCII `A` to `Z` are folded to lower case; no other case mapping is applied, so scalar positions never shift. Latin-script terms:

`energy`, `calorie`, `calories`, `kcal`, `kj`, `protein`, `proteins`, `fat`, `fats`, `saturates`, `saturated`, `carbohydrate`, `carbohydrates`, `carbs`, `sugar`, `sugars`, `fibre`, `fiber`, `salt`, `sodium`

A Latin term matches only where the scalar before it and the scalar after it are not ASCII letters `a` to `z` (or it is at the start or end of the text). These are explicit look-arounds, not word boundaries, so digits, punctuation and any non-ASCII scalar (including a combining mark) are allowed on either side: "61kcal", "Per100g Energy", "Fat:3g" and "fat-free" match; "fatty", "kjeldahl" and "saltire" do not; "Per100g" alone has no term and does not match. Plurals are listed, never inferred.

Chinese terms, matched as plain substrings (Chinese text has no word separators, so no look-around applies):

`熱量`, `热量`, `能量`, `蛋白質`, `蛋白质`, `脂肪`, `碳水化合物`, `糖`, `膳食纖維`, `膳食纤维`, `鈉`, `钠`

Settled consequences:

- Digits are ASCII only. Full-width digits do not count in v1; the projector's existing row join already treats ASCII digits as values.
- `糖` alone is included because labels print it as a row; menu noise containing it (for example a confectionery link) matters only if three blocks of one table or definition unit each match, which the all-or-nothing rule still bounds.
- A per-100 basis is not a term. A table whose rows read "£1.20 per 100g" does not match on that alone, so a price-per-100 g table is not a nutrition unit.
- The vocabulary, the rule and the digit class are pinned by a test that compares them to literals. Changing any of them is a new policy version.

A unit is a **nutrition unit** when at least three of its blocks match.

### 3.3 Extent, context, heading and identity

- **Extent (a settlement of contract section 5.2, recorded there).** A nutrition unit's extent runs from its first block to its last block in document order. Every block inside the extent is required, whatever its length and with no window count, except `json_ld` blocks (step 3 of section 3.4). This keeps a table whole when its rows are interleaved with blocks of no unit (for example the text blocks of a header row that wraps a nested table, or a nested non-nutrition table), so no unit is split. The walk is pre-order, so every block between a unit's first and last block lies inside that unit's `table` or `dl` subtree: an extent never leaves its table or list, which keeps the egress wording "nutrition tables and lists" accurate. "Before" and "after" below are relative to the extent.
- **Context before.** Up to 12 positions before the extent. Walking outwards, a block longer than 1,400 characters (`FoodProposalEvidenceCatalog.maximumExcerptCharacters`, the same value, restated as a closed policy literal and pinned equal by a test) ends the window and is not kept. A `json_ld` block uses up one of the 12 positions, is not kept as context and never ends the window, whatever its length.
- **Context after.** The same rule for up to 6 positions after the extent.
- **Nearest heading.** The last block of kind `h1` to `h6` before the extent's first block is required, at any distance and whatever its length.
- **Identity.** The first block of kind `h1` in the document, if any, is required.
- Positions in a window may belong to another unit (nutrition or not); they are kept as single blocks. Overlapping windows merge.

### 3.4 Admission of the required set, JSON-LD, output

1. No nutrition unit: refuse.
2. The required set is the union of every nutrition unit's extent, context and nearest heading, and the first `h1`. If its block count is above `FoodDocumentPartialRead.selectionPolicyBounds.blocks` or its character count above `.characters`, refuse. Nothing is ranked, dropped or cut.
3. Then each `json_ld` block, in document order, is added if both totals stay within those bounds; one that does not fit is skipped and later ones are still tried.
4. Kept positions are returned in document order.
5. The projector maps a refusal to `FoodSourceAcquisitionError.responseTooLarge`. It builds each kept block with its original id (`b137` stays `b137`), its original path and the selected-version suffix. It checks each locator's length itself before building the document: one over 500 characters gives `responseTooLarge`; nothing is shortened. Any other error in building or validating the kept document (a programming fault) also maps to `responseTooLarge`, as every non-cancellation error after the bound does (section 3.5).

`selectionPolicyBounds` equals `FoodDocumentBounds.current` today; a test pins the equality, so a later change to `current` cannot silently diverge from the policy.

### 3.5 The extended walk

- Without permission, the walk refuses at the bound exactly as today: same point, same error.
- With permission, `emit` stops refusing at the bound and records that the bound was passed. The walk continues to the end. The 3 MB, 50,000-node and depth-64 gates are unchanged and run before the walk as today; no new ceiling is added.
- After the bound was passed, any error other than cancellation (for example malformed JSON-LD, today `invalidDocument`, and any error in the selection or in building and validating the kept document) becomes `responseTooLarge`. Before the bound, errors are unchanged. Cancellation stays cancellation, during the walk and during the selection.
- Only `text/html` selects. A `text/plain` source over the bounds is refused with or without permission; PDF keeps its own bound and is refused over it with or without permission.
- A page within the bounds projects whole with the v6 string, identical with or without permission.

## 4. The capture port

```swift
public enum FoodDocumentPartReadPermission: Sendable, Equatable { case refused, permitted }
public protocol FoodDocumentCapturing: Sendable {
    func capture(_ url: URL, partRead: FoodDocumentPartReadPermission) async throws -> CapturedFoodDocument
}
```

No default value on the port: every call site states the permission. The projector's own parameter defaults to `refused`, so its other callers (app tests, PDF, offline tools) keep today's behaviour.

Shared contract (`FoodDocumentCapturePortContracts` in `FoodLedgerTestSupport`). Its input is a page **shape**: `whole`, `overBoundsWithPanel`, `overBoundsWithoutPanel`. Each subject is supplied as a factory from shape to a capturing instance and an address. The suite checks, for both values:

1. `whole` gives the same document under both values, with no `partialRead`.
2. `overBoundsWithPanel` is refused with `responseTooLarge` under `refused`.
3. `overBoundsWithPanel` under `permitted` gives a document that validates, carries `partialRead`, and whose every locator carries the selected version.
4. `overBoundsWithoutPanel` is refused with `responseTooLarge` under both values, so a fake cannot pass by always returning a part-read document.

Subjects: `PublicFoodSourceCapture`, serving real synthetic HTML for each shape through its internal resolve and fetch seams; and the reviewer tests' `ReviewPorts`, which scripts each shape. `FrozenCapture` is not a suite subject: it is tied to one frozen fixture; it forwards the permission to the projector, and the replay tests assert that every frozen fixture re-projects equal under both values. `ForbiddenMarketCapture` is a tripwire that fails on any call. In the probe tool, both live captures (`capture-audit`, `capture`) and `reproject` pass `permitted` (whole pages are identical either way, section 3.5), offline `project` takes an explicit flag, and `SmokeCapture` forwards the permission and records it in `capture-attempt.json`, so a smoke run matches production.

## 5. Source order (contract section 7, decision W4)

| Capture | Permission |
|---|---|
| A supplied address | `permitted` |
| A run with no source selector composed (one capture of the first allowed lead) | `permitted` |
| The first capture of a discovery run with a selector | `permitted` only when the discovery result holds no other admissible lead |
| The second capture | `permitted`, whether reached after a refusal or after an empty first extraction |

"Another admissible lead" is the existing second-lead filter evaluated before the first capture: a lead in the discovery result, other than the selected lead's address, that `FoodWebLinkPolicy.isAllowed` admits. It is computed by one pure static function so that the predicate and the second-lead pool cannot drift. Because the predicate equals the pool's filter (before redirects are known), a first page refused without permission always has a second lead to try.

No way back: when the second lead is not captured (the selector abstains, a market conflict, a provider error) or its capture fails for another reason, the run ends as today and the first page is not part-read. "As today" is exact: after a first-capture failure the run surfaces the second attempt's reason (for an abstaining selector, `sourceNotSuggested`), with the first address in `sourceAttempts`; this phase does not change which reason is shown. The two-capture limit, one discovery, no repeated step and no merging are unchanged.

## 6. Settled here (contract section 13 items for this phase)

- **Existing tests that pin today's refusals and change.** `GenericFoodDocumentProjectorTests`: `testBoundedCaptureFailuresAreDistinguishedFromUnsupportedEncoding` and `testLargerBoundsAdmitExactlyTheirEdges` keep their assertions because they call the projector without permission (the default stays `refused`, so each also pins the "without" half of test 1); `testLargeHTMLRetainsSmallReadablePanelWithoutExecutingPageScripts` likewise. No domain proposal test changes: the domain rules are phase 1's. Reviewer tests that call `capture(_:)` move to the two-argument form; the fake records the permission it received so source order can be asserted.
- **Contiguous ids.** No production code assumes contiguous block ids: the evidence catalogue issues its own `e<n>` entry ids per document and resolves them back to block ids by lookup; binding looks blocks up by id; content reads quotes. One test asserts contiguous ids on purpose (`testPageBetweenOldAndNewBoundsProjectsWholeWithTheV6String`, a whole page, which stays true). The `.jev` route serialises original ids, which therefore disclose a part-read page; the contract accepts this (section 6). The production applicability request also carries original block ids, in the evidence of the choosable candidates it sends (as it did for whole pages before #508); the contract's section 10 sentence that said otherwise is corrected there, and a test pins the ids the applicability body sends for a projected part-read document.
- **Instruction texts.** The extraction route's "Read all captured blocks" and the applicability instruction make no whole-page claim; both are unchanged, so `food-proposal-applicability-v1` and the extraction schema keep their versions.
- **Refusal copy.** Unchanged ("The source is too large for this bounded review. Choose a more specific food page."). A page still refused after selection is one whose required set does not fit or which has no nutrition table or list; the advice to choose a more specific page remains accurate for both.
- **Output and context allowances.** Unchanged in code; contract test 21 measures them.
- **Developer tools lines** (`GenericFoodProposalReviewViewModel.diagnosticLines` in `GenericFoodProposalReviewView.swift`). For a part-read document: "Part read: food-document-block-selection-v1 · full <n> blocks, <n> characters · kept <n> blocks, <n> characters". The permission per source attempt is not recorded in the review result; it follows from the source order of section 5 and the attempt's position, which the existing "Source attempt" lines show, so no new stored or result field is added.
- **Contract section 5.2 example.** The contract's "\"Per100g\" ... match" is read as "Per100g Energy" matching: a basis alone carries no term (section 3.2).
- **AI search by name (#488).** Its inputs use the projector's default `refused` until #488's own gate decides.
- **Projection version string.** Whole pages keep `swift-food-document-blocks-v6`; kept blocks carry the selected string; no new whole-page version.

## 7. Invariants

- Unknown is never zero: a nutrient outside the kept blocks is not declared, and under `web-lookup-review-v2` the screen calls it "Not in the part read".
- No nutrition unit is dropped, ranked, split or cut; competing panels all reach extraction (W2).
- Selection produces no value, uses no model and no host rule, and is deterministic for the same bytes.
- Binding is unchanged: quotes must be found in a kept block, looked up by id.
- Stored formats: every document without `partialRead` encodes with identical bytes; every retained fixture re-projects equal; v1 and v2 admission still reject part-read documents (phase 1 rules, re-run).
- The part-read record is never sent to a provider; the `.jev` body for a projected part-read document is pinned.

## 8. Egress wording (contract section 10; shown to the owner before it lands)

- `privacy-and-egress.md`, the OpenRouter web lookup row, added to its "what" cell after the phase 1 amount clause: "for a page larger than that, only its nutrition tables and lists, the lines and headings around them, its main heading and its structured data blocks (part-read pages, #508)". The contract is already in its contract cell.
- `privacy-policy.txt`: the phase 1 sentence "A page is sent whole up to a fixed size; a larger page is not sent." is replaced by the contract's sentence: "A page is sent whole up to a fixed size. When a page is larger than that, only its nutrition tables and lists, the lines and headings around them, its main heading and its structured data are sent, and the review says that only part of the page was read."

## 9. Contract tests in this phase (contract section 12)

1. 2,048 blocks and 100,000 characters project whole under both permissions; a 2,049th block or a 100,001st character refuses without permission and enters selection with it.
2. A page within today's bounds and one between the old and new bounds project whole with the v6 string under both permissions; every retained fixture re-projects equal (the existing replay and fixture tests, unchanged).
3. With permission, malformed JSON-LD after the bound gives `responseTooLarge`, and before the bound stays `invalidDocument`; the reviewer tries the second lead after a first-lead `responseTooLarge`; cancellation inside the extended walk, as selection starts and inside the selection stays `CancellationError` (internal overload parameters, never public and never static mutable state, cancel the current task once the bound is passed or once the walk ends).
4. `text/plain` beyond the bounds is refused with permission; a PDF over its own bound is refused with permission.
5. All or nothing: two panels with a shared label inside one window, both kept with the label; the label outside every window, both kept without it; a required set that does not fit is refused; many small nutrition units that fit are all kept.
6. Units: table; nested table (inner rows form their own unit); a nested non-nutrition table inside a nutrition table is kept whole; a block over 1,400 characters inside an extent is kept; a `dt` and `dd` pair with no `dl` is no unit; a header row wrapping a nested table (extent keeps the table whole); a `caption` joins its table; a definition list; a `dl` with wrapped pairs; lone `dt` and `dd` blocks are not a unit; a price-per-100 g table is not a nutrition unit; a single unit over budget is refused.
7. Matching: "61kcal", "Per100g Energy", "Fat:3g" match; "Per100g" alone and "fatty" do not; a combining mark after a term and a non-ASCII upper-case letter behave as section 3.2 says; Chinese terms match without separators; a menu of navigation items with nutrient words but no table is not a unit; the vocabulary, the digit class and the thresholds are pinned to literals.
8. Context and identity: a context block over 1,400 characters ends the window and is not kept; a `json_ld` block uses up a window position; the nearest heading is kept at any distance; a page with no `h1` keeps no identity block and is not refused for it; an `h1` that brings the required set to exactly the block bound is kept, and one more block refuses.
9. JSON-LD: one inside a window is not kept as context but is tried in fill order; one over 1,400 characters inside a window does not end it; one over budget is skipped and a later one still fits; none causes a refusal.
10. Determinism (same bytes, same document); kept ids and paths equal the full projection's; ids unique; `fullBlocks` and `fullCharacters` equal the full walk's totals; `rawSha256` and the document id are those of the complete raw bytes; a locator that would pass 500 characters with the selected suffix gives `responseTooLarge`; an over-bounds page with no nutrition unit gives `responseTooLarge`.
13. Provider: no extraction, applicability or `.jev` body for a projected part-read document contains the part-read record; the catalogue output and the `.jev` body for it are pinned, including the `.jev` locators.
18. Capture port: the shape-based suite of section 4 over the public capture and `ReviewPorts`, for both values; `FrozenCapture` fixtures re-project equal under both values.
19. Reviewer source order: a supplied address (permitted); no selector (permitted); a first lead over the bounds with another lead (refused, then the second lead permitted) and without one (permitted, one capture); a second lead that abstains after a first lead over the bounds (the run ends with `sourceNotSuggested` as today, the first address in `sourceAttempts`, no part-read), and likewise a market conflict and a provider error on the second lead; an empty first extraction followed by a second page over the bounds (second permitted); the capture count never above two.
22. Boundaries: `check-boundaries.sh` allows only `Foundation` and `FoodLedgerDomain` in the selection file, written in the attribute-aware resolver style, failing when the file is missing, with self-test fixtures for `import SwiftSoup`, `@preconcurrency import Network`, `import FoodLedgerApplication` and `import CryptoKit`.

Also: a projected part-read document validates, round-trips byte-identically, is admitted by v3 and rejected by v1 and v2 admission; its `web-lookup-review-v2` content carries the part-read line and "Not in the part read"; Developer tools shows the part-read line. Evaluation: the FoodSearchQuality and FoodQueryEvaluation steps of `ios-ci.yml`.

## 10. Not established

- Whether the windows hold on real pages beyond the new bounds, and whether list-style panels are common there: no sampled page exceeds the new bounds (contract section 1.3). Contract test 21 includes at least one such page, found or constructed and labelled.
- Review time, tokens and binding on part-read pages. Contract test 21.
- Anything on a device.

## 11. Review record

One blind architecture-gate review of the draft (read-only, at 74c1fa4d): pass with changes. Folded in: the shared capture suite rebuilt on page shapes, with a no-panel case under both values, `FrozenCapture` taken out of it and covered by re-projection; the abstaining second lead asserted as today (`sourceNotSuggested`), with market-conflict and provider-error cases; "Per100g" alone does not match, recorded as reading the contract's example; the extent rule recorded as a settlement of contract section 5.2, with its subtree property and tests; the `dl` key as ancestor-or-self, with a pair outside any `dl` having no unit; JSON-LD window counting tested; matching over scalars with ASCII-only folding; every error after the bound, including building the kept document, mapped to `responseTooLarge` with a locator pre-check; the probe's captures, `reproject` and `SmokeCapture` pass or record the permission; the boundary rule in the resolver style with self-tests; no static test hook; the Developer tools home named; the #488 interaction; the permission type renamed `FoodDocumentPartReadPermission`. The owner approved the section 8 wording as written on 18 November 2026. This revision has had no review of its own.

After implementation, one blind invariant review of the diff (read-only): pass with notes, nothing blocking. Folded in: the lone `dt` and `dd` case now has five blocks that each match; the Kelvin sign pins ASCII-only folding (Unicode lower-casing would turn it into "k"); a second test seam cancels as selection starts, and removing the projector's rethrow fails that test; the long-locator case is sized so the whole-page locator fits 500 and only the nine characters of the selected suffix refuse it; kept rows' ids and paths are compared with the same rows projected whole; matching counts only up to the threshold and checks cancellation as it runs (same result, no policy change). The retained-evidence replay tests (`FOOD_WORKFLOW_REPLAY=1`) fail the same seven assertions on this branch and on the phase 2 branch (a missing local `plan.json` and older request bodies), so they are pre-existing and not used as evidence here; the frozen-capture check under both permissions runs only with that variable. These fixes have had no review of their own.

A blind invariant review at the pull request head (2851305): pass with notes, nothing blocking. Folded in: the applicability request carries original block ids in candidate evidence, so the contract's section 10 sentence is corrected with a dated note and a test pins the ids sent; contract test 1's permitted half is tested at exactly 2,049 blocks and 100,001 characters; a non-ASCII upper-case letter beside a term ("ÉFAT 3g") replaces a case that no rule could tell apart, and pins the boundary rule (a non-ASCII letter beside a term does not block a match), while the Kelvin-sign cases pin ASCII-only folding; the nearest heading is found in one pass over the page instead of one scan per unit. Recorded rather than changed: cancellation inside the selection's loops is checked in code (every 64 members while matching, and per unit and per JSON-LD block) but only the check on entry is tested; the both-permission re-projection of retained fixtures rests on the code path for CI, since the replay tests run only with `FOOD_WORKFLOW_REPLAY=1`. These last edits have had no review of their own.

A blind invariant review of the fixes at ac4d3615: pass with notes, nothing blocking. Folded in: the contract's section 6 sentence about what the extraction and applicability routes send now matches the section 10 correction; the applicability test parses the request body and checks the candidates' `block_id` values and that catalogue entries use their own ids, instead of scanning the whole body; the extraction check covers every kept block id; the gate's wording on "ÉFAT 3g" names the boundary rule.

A blind invariant review at 5db68233, before the merge: pass with notes, nothing blocking. Folded in: that extraction check could not fail (block ids inside the serialised message are escaped), so both provider tests now decode the request state and walk every string value; a kept block id appears only as the candidates' `block_id` (exactly `b2103`) in the applicability request and nowhere in the extraction request, and catalogue entries carry only `id`, `kind` and `text`. Recorded rather than changed: the egress row says "its structured data blocks" while only the JSON-LD blocks that fit are sent; it overstates in the safe direction and is the owner's approved wording. These last edits have had no review of their own.
