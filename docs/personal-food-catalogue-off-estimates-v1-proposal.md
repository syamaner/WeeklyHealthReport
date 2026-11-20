# Personal food database: estimates read from Open Food Facts label photos (proposal)

Status: **accepted by the owner on 18 November 2026, after two blind review rounds (section 8).
Implemented in #518** (phase gate:
[label photo estimates v1, phase gate](personal-food-catalogue-off-estimates-v1-phase.md)). The owner decided F1 to F7 the same day (section 7). Written at the
owner's request of 18 November 2026 to use Open Food Facts as an estimate source when enriching,
with fibre always provided. No app code, skill code, fixture or private file
changes with this document. Implementation is one phase after the estimates v2 phase (#511, PR 514)
has merged, with its own issue and architecture gate.

**Amendment, 19 November 2026 ([gap estimates amendments](personal-food-catalogue-gap-estimates-v1-amendment.md), proposed in #524).** Section 2.5 is relaxed as its owner direction foresaw (G3): a refusal row of class `open_food_facts` no longer refuses a photo estimate, by entry and nutrient or by barcode; the other three classes still do. Every rule of sections 2.1 to 2.4 still applies, the tier stays capped at `medium`, and the evaluator's count 3 now covers the other three classes only. D1, D3 and the A1 consequence are unchanged.

It is a delta on three accepted documents and repeats none of them:
[approved estimates v1](personal-food-catalogue-estimates-v1.md),
[labelled estimates on catalogue v2](personal-food-catalogue-estimates-v2-proposal.md) and the
[E3 disposition](personal-food-database-e3-disposition.md). Everything they say that this document
does not name stays as written. Section 2.0 names each rule it amends; on acceptance each of those
documents gains a dated amendment note pointing here.

**Amendment, 19 November 2026 ([amendments G7 and G8](personal-food-catalogue-tables-composites-amendment-v1.md), proposed in #532).** The composite foods rule is amended: a label photo of another product may fill a composite entry at `low` with the fixed sentence "A generic recipe, not this product's." (G7); a photo of the same named product is unchanged.

## 1. Why a delta is needed

Today an estimate can never come from Open Food Facts. Estimates v1 section 3.1 forbids "an
estimate whose underlying source is an Open Food Facts record, whatever page or route it was read
through", section 2.2 forbids an Open Food Facts host in `source_reference`, and estimates v2
section 3.1 lists such a value as never re-admissible. The estimates v2 implementation enforces
the rule twice (PR 514, not yet merged): the skill writer withholds the row
(`open_food_facts_source`) and the app decoder refuses the host.

The rule came from the E3 evaluation: amendment A1 failed, and the A1 consequence dropped every
Open Food Facts label value from R1, the drops-only release (E3 disposition, sections 2 and 3). Section 1.1
of that document records where those errors were: all 22 value errors were state errors ("the numbers were
given for a different state of the food, such as as sold rather than prepared, not mistranscribed
or for a different food"), and it names state as "the first issue to work on if Open Food Facts
values are ever reconsidered".

Two things have changed since (counts only, from the owner's private catalogue on 18 November
2026):

1. **The owner now reads the label photo.** On 18 November the owner approved 8 estimates for
   missing values after reading each source's nutrition panel photo, with the state, basis and
   limits written per row. 7 of the 8 cite an Open Food Facts label photo, so none of the 7 can
   reach the app. In that private review (not in E3, which found state errors rather than
   mistranscription) the photos also corrected some of the dataset's typed fields, which is why
   this proposal admits the photo, not the typed fields.
2. **Fibre is the largest single gap.** 690 of 836 entries have no fibre on their own label. For
   branded and packaged foods, an Open Food Facts panel photo is often the only public source.

## 2. What changes

One new source type, admitted only under the rules below. Every rule is closed; changing one is a
new version of this contract.

### 2.0 Rules amended, by name

Each amendment admits `product_dataset_photo` estimates under sections 2.1 to 2.5 and nothing else.
For every other source type and route the amended rule stays exactly as written.

| Rule | Amendment |
|---|---|
| Estimates v1 section 3.1 ("never an estimate whose underlying source is an Open Food Facts record") | Exception for `product_dataset_photo` only. |
| Estimates v1 sections 2.2 and 2.3 (Open Food Facts host rejection) | Unchanged for estimates v1 and v2 files. The exception exists only in the v3 schema of section 2.1. |
| Estimates v2 section 3.1 (Open Food Facts "never re-admissible") | Unchanged: nothing is re-admitted. A photo estimate is a new value with its own evidence, not a re-admission, and section 2.5 keeps every withheld value out. |
| E3 disposition section 4.1 and D1 | **The A1 consequence still stands.** Open Food Facts typed values stay dropped from R1 and are never brought back. The new route admits only photo reads, and only for an entry and nutrient where E3 withheld nothing (section 2.5). |
| E3 disposition D3 ("any value whose underlying source is Open Food Facts is refused while the A1 consequence stands") | Unchanged and still in force for aggregator and indexed-copy values. Only estimates v1 section 3.1 gains the photo exception, and estimates v2 section 3.1's citation of D3 keeps its meaning for those classes. |

### 2.1 The source type `product_dataset_photo`

- **What it is.** A value read by eye from the nutrition panel photo that Open Food Facts links to
  a product record, never from the record's typed fields.
- **Wire.** The v3 schema below, and only it, adds the `source_type` token
  `product_dataset_photo` to the evidence record of estimates v1 section 2.2. Estimates v1 (the R2
  builder format) and v2 are not widened. Its evidence record:
  - `source_reference`: the public HTTPS address of the photo, on `images.openfoodfacts.org`
    only, with no user information, query string or fragment, at most 2,048 bytes. The Open Food
    Facts host rejection of estimates v1 section 2.3 stays in force for `manufacturer_page` and
    `aggregator`.
  - `composition_source`: `null`. `page_access`: `direct_read`. `retrieved_on`: required, the
    date the photo was read.
  - `source_digest`: required and never `null`. It is the SHA-256 of the photo bytes. The photo
    itself stays in the owner's private workspace; the digest travels in the catalogue, the
    capture manifest and, as `content_hash`, the daily export (estimates v1 section 7).
    A value whose photo was not kept is not admitted.
  - `method`: `direct` or `carried_from_similar_food` only, never `derived` or
    `carried_from_same_food` (section 2.3).
  - `underlying_source` (accepted-estimates input): `not_applicable`; any other token is refused.
- **Catalogue schema.** A new token in a closed list is a new schema version.
  `personal-food-catalogue-estimates-v3` is v2 plus the token and the rules of sections 2.1 to 2.4
  (the host rule, the required digest and date, the refused `unknown` state basis and `derived`
  method, and the `medium` ceiling). The builder writes v3 **only when at least one
  `product_dataset_photo` estimate is admitted**; otherwise it writes estimates v2, byte-identical
  to what it writes today, so release identity and the Part B binding (E3 disposition, section 5
  point 4) are unaffected. A v3 file is a new release with its own ID. Part B binds to the release
  that ships, chosen before the first development run under E3 section 5 point 4; if a v3 release
  ships in place of the bound one, it needs its own Part B run on a fresh held-out set, as that
  point says. A v2 file carrying the token is rejected, a v3 file holding no photo estimate is
  rejected, and a decoder that does not know v3 rejects the file whole.
- **Token lists per version.** The app keeps one closed source-type list per catalogue schema,
  daily export version and stored contract, never one shared list, so adding the token cannot
  widen estimates v2, daily export 3 or 4, or an earlier stored contract.
- **Accepted-estimates input.** The private input format `pfc-accepted-estimates-v1` becomes
  `pfc-accepted-estimates-v2`: the same fields plus the token. The v1 input keeps refusing it.
- **Stored records.** Capture manifests hold the whole evidence record (estimates v1 section 5.2),
  so a log saved from a photo estimate needs a new food contract floor: the next free contract
  number, with its migration and store version and an archive fixture, allocated at the phase gate.
  A store or archive holding no photo estimate keeps its contract and its bytes.
- **Shown.** The details line gains the source-type text "Product database label photo". The
  closed tier labels of estimates v2 section 3.3 are unchanged.

### 2.2 What may be read from the photo

- **Basis.** Only a column whose heading prints per 100 g, or per 100 ml for an entry on that
  basis. A per-serving or per-portion column is never used or scaled.
- **Printed values only.** No kJ to kcal, salt to sodium or serving conversion, no density, no
  edible-fraction or cooking conversion; `derivation` is always `null`. A nutrient the panel does
  not print stays unknown.
- **Zeros and bounds.** A zero is written only where the panel prints a quantified zero. A bound
  such as "<0.5 g" is not written: the estimates format has no bound, so the nutrient stays
  unknown and the bound is noted on the private review sheet.
- **Never overwrites.** Estimates v2 section 4 is unchanged: a label value always wins, and a file
  with the same nutrient in both lists is rejected.

### 2.3 State and identity (the A1 lesson)

- **State must be read, not assumed.** `state_basis` is `source_states_it` when the panel or pack
  prints the state the column describes (for example "as sold", "as prepared", "drained"), or
  `stated_assumption` when the panel prints none and the pack is sold ready to eat, with that
  assumption written out. A food that is cooked, rehydrated, baked or otherwise prepared before
  eating always needs `source_states_it`. `unknown` is refused for this source type, because A1
  failed on state.
- **State must match.** `source_state` must describe the entry's state. A dry-as-sold panel never
  supplies a cooked or prepared entry, and the other way round. "As sold" does not contradict an
  entry whose state is `unknown`, and `as sold` and `raw` do not contradict each other in either
  direction, as estimates v2 section 3.2 says.
- **Who checks it.** Confirm's facet check covers national composition estimates only, so for
  this source type the state match is a builder rule. The evaluator counts photo estimates whose
  `source_state` and the entry's state differ, and that count must be zero.
- **Relation.** A photo linked to the barcode of the product the owner bought is `same_food` with
  method `direct`. A photo from another barcode (another pack size, market, flavour or revision of
  the same product) is `similar_food` with method `carried_from_similar_food`, and its assumption
  says how it differs.
- **Composite foods.** Only the same brand and the same named product, in another pack, market or
  revision. A different product of the same brand, or any other brand's recipe, is refused, as
  import v1 decision 4 requires.

### 2.4 Quality tier

- **Ceiling `medium`** for every `product_dataset_photo` estimate, enforced by the codec. `high`
  stays reserved as estimates v2 section 3.3 defines it. Below the ceiling the builder may go
  lower, and a `stated_assumption` state or a similar food is at most `medium` already.
- The owner sets the tier per row on the review sheet, as estimates v2 section 3.3 requires; no
  agent sets one on the owner's behalf.

### 2.5 No laundering, and the evaluation stays as it is

- A value or record that E3 withheld stays withheld (E3 disposition, section 4.1). Today's
  refusal matching compares source type and reference, so it could never match a photo row. For
  this source type the builder therefore refuses a photo estimate for **any entry and nutrient**
  that has a refusal row of class `open_food_facts`, `per_entry_exclusion`, `value_fault` or
  `unresolved_a1`, **whatever that row's source type**. A refusal row with no `nutrient` covers
  every nutrient of its entry. Refusal rows carry no barcode field, so a barcode is taken from a
  row only when its `source_reference` is an Open Food Facts record ID (`off:gtin:` and digits) or
  product address (`/product/` and digits); a photo of that barcode is refused for every entry. A
  row with no recoverable barcode refuses by entry and nutrient only. The evaluator counts photo
  estimates matching a refusal row either way, and that count must be zero.
- **Expected effect.** This may refuse the owner's own barcode for many entries, because the A1
  consequence dropped 385 Open Food Facts values (E3 disposition, section 1.1). That is the
  intended cost of no laundering. The private refusals list does not exist yet; when it is built,
  the builder reports, counts only, how many of the 7 approved photo estimates and of the fibre
  candidates pass this rule, before the first run.
- **Owner direction, 18 November 2026:** if that count shows the rule blocks too much, the rule is
  to be relaxed rather than accepted as a loss. The relaxation is a dated amendment to this
  section, proposed with the count. The likely form: allow a photo of the bought barcode for a
  nutrient whose typed value A1 dropped, when the photo's printed state is read and matches the
  entry (A1's errors were all state errors). Other refusal classes stay as written.
- The pinned evaluation release, R1, its release ID, its seals and its results are unchanged. This
  route adds owner-approved estimates, not evaluated values: no results narrative, Settings text
  or release note may describe them as evaluated (E3 disposition, section 5 point 3).
- The evaluator adds four counts:
  1. `product_dataset_photo` estimates admitted, by macro and micro and by `same_food` and
     `similar_food`;
  2. those withheld, by class;
  3. photo estimates matching a refusal row (this section), **must be zero**;
  4. photo estimates whose `source_state` and the entry's state differ (section 2.3), **must be
     zero**.

### 2.6 Fibre first

The first private run of this route is a fibre pass. For every entry with no fibre value, the
builder lists a candidate: its own barcode's record where one is known, otherwise a search query
written to the pending file. No query is sent until the owner approves that exact query (the
existing outbound rule). A fibre value is offered only from a panel that prints fibre per 100 g on
the entry's basis; otherwise fibre stays unknown, never zero. The other nutrients of the same panel
may be offered in the same row, each accepted by the owner.

## 3. What does not change

- The owner accepts every value as an estimate, row by row, with its tier shown. A model, a
  citation or a typed dataset field never authorises a value.
- Unknown is never zero; bounds stay bounds; raw, cooked, drained and dry stay distinct.
- Estimates are augmented, never measured, and can be left out on Confirm (estimates v2 section 5).
- Search, Confirm, the ranking of sources and the merged generic record are untouched.
- The app makes no new network call and never fetches the photo.

## 4. Daily export

The daily food export already carries the estimate's source type token. A new token is a new
export version, so the versions need a total order:

- The new version is a **superset of the highest version implemented** when this phase starts,
  plus the token. Today that is version 3: version 4 (assistant-pasted estimates v1 section 9,
  `food-daily-export-contract-v2.md`) is accepted but not built, and it is not a prerequisite.
  The new number is the next one not already claimed by any contract, fixed at the phase gate;
  whichever of the two is built second takes the union of both shapes.
- **Validator row:** the new version requires at least one `product_dataset_photo` estimate, and a
  document at that version with none is rejected.
- A document takes **the lowest version that can describe it**: a photo estimate forces the new
  version whatever else the document holds, and a document with both a photo estimate and an
  assistant estimate is valid at the new version. Every field and notes sentence a lower version
  requires for the values present is still required. A document with no photo estimate exports
  byte-identically to before.
- Each version's validator keeps its own token list (section 2.1), so version 3 and 4 validators
  reject the token.
- The photo address can appear in the export, as page addresses of approved estimates already do
  (query string and fragment dropped). It contains the product's barcode, as the photo addresses
  of Open Food Facts always do.

## 5. Privacy and egress

- **App.** No new destination. The export the user sends may carry the photo address, which
  includes the product barcode (section 4); the implementing change records that in
  `privacy-and-egress.md` beside the page addresses already recorded.
- **Developer tooling.** The skill already queries Open Food Facts under the owner's per-query
  approval, but the tooling paragraph of [`privacy-and-egress.md`](privacy-and-egress.md) lists
  only search queries, generic names and barcodes as what is sent. This route adds two things that
  need new wording there, approved by the owner with its date, before first use:
  1. **A photo fetch:** the label photo of a record found by an approved query or a barcode
     lookup, fetched from `images.openfoodfacts.org` by the paced client, sending only the photo
     address.
  2. **A photo read by the agent:** the agent reads the panel and proposes the values, and the
     owner checks each against the photo. The public photo therefore reaches the agent's model
     provider, which the paragraph today covers only for the owner's own photos.
- The photo bytes stay in the private workspace; their digests travel as section 2.1 says. The
  repository gets this contract, code and synthetic fixtures only.

## 6. Architecture gate (to complete in the phase spec)

Paths below are as on the estimates v2 branch (PR 514).

- **Domain** (`PersonalFoodDatabaseEstimates.swift`, `ApprovedEstimateEvidence.swift`): the v3
  schema, one token list per version, the host rule for `images.openfoodfacts.org` on that token
  only, required digest and date, refused `unknown` state basis and `derived` method, and the
  `medium` ceiling. The Open Food Facts host rejection stays for the two page types.
- **Shared enum:** `PersonalFoodDatabaseEstimateSourceType` (`PersonalFoodDatabaseEstimates.swift`)
  is decoded by the catalogue codec and by the export validator (`FoodDailyExportShape.swift`); the
  per-version token lists replace that shared closed set at both call sites.
- **Presentation** (`ApprovedEstimatePresentation.swift`): the F5 text "Product database label
  photo".
- **Stored data:** the new food contract floor with its GRDB migration and store version, the food
  archive's contract version, and an archive fixture.
- **Skill** (`estimates_input.py`, `estimates_v2.py`, `estimate_counts.py`): input v2, writing
  catalogue v3 only when needed, the same checks, the entry-and-nutrient refusal rule of section
  2.5, and the new counts (admitted, withheld by class, refusal matches, state mismatches). The
  `open_food_facts_source` withholding stays for every other source type.
- **Export** (`FoodDailyExportShape.swift`): the new version, its token list and the version order.
- **Contract tests**, with synthetic fixtures, in Python and Swift alike:
  - accepted; wrong host; query string; missing digest; `unknown` state basis; `derived` method;
    `high` tier; `underlying_source` other than `not_applicable`; a page type on an Open Food
    Facts host;
  - a refusal hit matched by entry and nutrient on a row of another source type;
  - the token rejected in a catalogue v2 file, in input v1, and by export 3 and 4 validators;
  - a catalogue with no photo estimate written byte-identical as estimates v2;
  - a stored manifest with the token at the new contract floor, rejected by the previous contract,
    and an archive without the token keeping its bytes;
  - export order fixtures, including a document with both a photo and an assistant estimate;
  - a refusal row with no `nutrient` refusing every nutrient; the barcode-derived refusal;
  - `stated_assumption` on a food prepared before eating refused; `carried_from_same_food`
    refused; `same_food` with `carried_from_similar_food` refused;
  - the state-mismatch count non-zero for a dry panel on a cooked entry;
  - a v3 file with no photo estimate rejected; the new export version without one rejected;
  - the details text shown; the export `content_hash` equal to the manifest digest.

## 7. Decisions for the owner

| # | Question | Recommendation |
|---|---|---|
| F1 | Admit Open Food Facts label photos as a labelled estimate source, under sections 2.1 to 2.5? | Yes, photo only, never typed fields. **Decided by the owner, 18 November 2026: accepted.** |
| F2 | Tier ceiling for this source | `medium`. **Decided by the owner, 18 November 2026: `medium`.** |
| F3 | Allow `stated_assumption` when the panel prints no state? | Yes, for ready-to-eat packs only, with the assumption written out. **Decided by the owner, 18 November 2026: yes, ready-to-eat only.** |
| F4 | Keep each photo privately with its SHA-256, and refuse a value without one? | Yes. **Decided by the owner, 18 November 2026: yes, keep photos.** |
| F5 | Details text | "Product database label photo". **Decided by the owner, 18 November 2026: that text.** |
| F6 | Egress wording for the photo fetch and the agent's photo read (section 5) | Approve at implementation, from the change that adds it, before first use. **Decided by the owner, 18 November 2026: at implementation.** |
| F7 | Run the fibre pass first? | Yes. **Decided by the owner, 18 November 2026: fibre first.** |

## 8. Review record

- **18 November 2026, blind hostile read (architecture-gate role) of the first draft: block.** Four
  blocking findings, all applied: the rules this amends were not named, and the A1 consequence's
  status was unstated (section 2.0); the refusal rule matched by source type and could never
  fire (section 2.5); stored manifests needed a contract floor (section 2.1); and one shared token
  list would have widened older versions (section 2.1). Seven more were applied too: v3 written
  only when needed; v1 not widened; where digests travel; export version order; `underlying_source`
  and input v2; state match as a builder rule with a count; and egress wording for the agent's
  photo read. The private counts in section 1 were not checkable by the reviewer.
- **18 November 2026, blind re-review of the revised draft: pass with notes.** All eleven earlier
  findings confirmed applied. Applied from this round: the refusal rule's barcode source, the
  no-`nutrient` meaning and its expected effect (section 2.5); D3 named separately (section 2.0);
  the Part B case for a shipped v3 release (section 2.1); the export version built over the
  highest implemented version, with its validator row (section 4); the four evaluator counts
  listed (section 2.5); the shared enum, presentation and store targets (section 6); R1 named for
  the A1 drops; the `as sold` and `raw` rule cited as written; the barcode in the exported photo
  address (sections 4 and 5); and ten more contract tests.
- The phase gate runs the `architecture-gate` and `invariant-reviewer` roles blind to each other
  before any code.
