# Local receipt and inventory contract — v1

Issue: #130. This contract governs the local first slice; it grants no Drive access.

User clarification (25 September 2026): Google inventory import is optional,
never a setup or usage prerequisite. A fuller common-items/favourites management
UI is a later slice. Current presentation is limited to local import, review,
correction and searching reviewed entries; it does not require a Google account.

## Architecture gate

- **Domain:** bounded receipt grammar, immutable source/line identity, catalogue
  products, review revisions, explicit acquisition and remaining-stock assertions,
  and deterministic matching. No filesystem, UI, database or provider dependencies.
- **Application:** import/review commands, idempotency, explicit user decisions,
  source hashing, injected identifiers/time, and consumer-owned persistence and
  document-extraction interfaces. Import is never an instruction to consume food.
- **Infrastructure:** local text/PDF extraction and a separate, versioned inventory
  database. Inventory is not added to nutrition LogItem or its archive schema.
- **Presentation:** original line, editable proposal, candidate differences,
  explicit accept/defer/decline, selected-row batch review, durable progress and
  correction history. Composition connects inventory selection to existing generic
  food search without inferring consumed quantity or an exact nutrition match.

The credible extension points are document extraction and catalogue lookup.
Drive transport, scanned-document OCR and retailer-specific adapters are later
work. Source identity, dimension compatibility, immutable provenance and the
purchase/remaining/consumed distinction are closed v1 invariants, not plug-ins.

## Invariants

1. Imported bytes and extracted text remain immutable. Content SHA-256 plus
   original line number identifies a review row. Exact reimport resumes the saved
   review; it cannot create another acquisition. Duplicate-looking rows within one
   document remain separate evidence. Different bytes are different sources;
   apparent cross-document duplicates require review, not guessed deduplication.
2. Purchase count, pack content, line price and confirmed remaining stock have
   separate fields. No density conversion, household conversion or depletion is
   inferred. Unknown remains unknown. A purchased pack is not a consumed serving.
3. Catalogue identity and aliases help rank candidates but do not establish
   nutrition, availability or delivery. Brand/variant/pack differences stay
   visible. Corrections invalidate candidate selection. Ambiguous matches require
   explicit selection; no match is automatically accepted.
4. Totals, taxes, discounts, substitutions and returns remain visible context or
   unresolved rows. They do not silently become positive acquisitions. Orders do
   not establish delivered inventory. Remaining amounts require a dated explicit
   assertion and are displayed with that date, never as a live stock guarantee.
5. Review writes are atomic, versioned and retry-safe. A correction appends a
   revision rather than replacing evidence. Deferral/decline and undo are durable.
   A batch reports each saved or failed row; nothing claims all saved on failure.
6. Inventory selection only prefills a food query. Food confirmation and logging
   remain a separate explicit action. This slice never decrements stock implicitly.

An ambiguous/order/adjustment line can become a received acquisition only after
the user explicitly confirms receipt and supplies a correction explanation.
Catalogue sources can never establish receipt of goods. Undo acceptance appends
a deferred review and removes that row from the current received-acquisition
projection; it does not delete catalogue products or their history. Catalogue
details and dated remaining assertions are corrected explicitly during review.

## Local formats and limits

Receipt text and text-bearing PDFs are supported through user-selected local
files or pasted text. Catalogue entries can be reviewed from the same local
source or entered explicitly with product, category, aliases, pack description,
remaining amount, assertion date and notes. Table extraction is a proposal, not
an exact reading of spatial PDF cells. Every row needs review.

Open **Food logging → Review Receipts (Optional)**. Choose receipt or catalogue,
paste text or choose a file, then expand a line to compare its original with the
proposal. Select a suggested local product or explicitly create one; editing the
description clears that choice. Select rows individually before batch acceptance.
Saved sources and decisions survive reopening; uncommitted editor fields do not.
Search reviewed products by name, alias or category and optionally carry their
name and a minimal versioned product reference into generic food search. Original
receipt bytes, prices, stock amounts and notes are not copied into that reference.

The parser accepts up to 100,000 characters and 1,000 lines; imports are capped at
5 MB and PDFs at 100 pages. Every PDF page must have extractable text. The local
SQLite event store uses iOS complete file protection. No background import,
network source, stock depletion, favourites or automatic candidate acceptance is
implemented. The UI may display all original PDF text lines, including table
headings; spatial table reconstruction is not claimed.

Scanned/image-only PDFs, unreadable or oversized files are visibly rejected, not
silently treated as empty stock. No OCR acceptance gate is opened. Filenames,
source content and extracted personal receipt text stay local and are not logs,
telemetry, committed fixtures or issue attachments.

## Validation contract

Synthetic fixtures cover unit spellings, decimal commas, multipacks, variable
weight, prices, discounts/returns/totals, abbreviated and conflicting catalogue
names, unknown packs and old stock assertions. Shared store contract tests cover
atomicity, duplicate retry, conflicting retry, reopen, correction history and
stale revision rejection. Extraction adapters must satisfy the same empty/error
contract. Presentation tests cover explicit selection, correction invalidation,
partial save and resume. Package boundaries, simulator compilation and static
analysis remain delivery gates. Physical/provider validation is separate.

Inventory has its own local store; existing food-ledger archives do not claim to
include it. A future export/merge contract must explicitly version that scope.
