# Personal food database import v1

Status: accepted by the owner on 7 November 2026 (revision 5, twelve owner decisions in section 2).
Revisions 2 to 5 answered five rounds of architecture-gate and invariant review and three Qodo local
reviews. Implementation has not started: it is a separate phase with its own architecture gate, and
the amendment rows for A1 in `unified-food-search-contract-v1.md` and identity contract section 8 are
added in that change. Issue: [#419](https://github.com/syamaner/WeeklyHealthReport/issues/419).

## 1. Purpose and scope

The owner keeps a private nutrition database built from their own receipts, notes and food logs.
It is assembled on the owner's Mac with the
[`personal-food-catalogue`](../.agents/skills/personal-food-catalogue/SKILL.md) skill, whose
procedure and data-free scripts are in this repository and whose inputs, working files and output
stay in a private workspace. This contract lets the app **import that file locally** and offer its
entries in food search, without changing how food is confirmed or saved.

User-facing name: **Your food database**. Code names use `PersonalFoodDatabase…`, distinct from the
retailer catalogue of receipt import (`local-inventory-contract.md`) and the personal library
(`PersonalLibraryGenericFoodSearch`). The file schema string is `personal-food-catalogue-v1`.

In scope: the file format, a local import, replace and remove flow, a search adapter with a
fallback chain, provenance on Confirm, and contract tests. Out of scope: the build itself as app
code; any network call for this feature; supplements (section 12); editing entries in the app; any
change to HealthKit, Drive or the exports beyond what an ordinary saved log already produces.

## 2. Owner decisions recorded (7 November 2026)

1. Everything is sanitised before it goes near the repository. The repository receives only this
   contract, the importer, the adapter, the data-free build skill and **synthetic** fixtures.
2. The database is a **private import**, never bundled into the build.
3. Enrich as far as possible, with a source on every nutrient (amendment A1).
4. Composite dishes stay without nutrients rather than borrowing another brand's recipe.
5. **Generic values are referenced, not copied.** The app reads them from its own bundled corpus.
6. **Local first, then online**, as an ordering rule (section 5).
7. **Another brand's label stays out of v1.** It is kept in the private working catalogue only.
8. **Only a same-food, known-preparation generic record merges into an entry.** A close match, or
   one whose state is not raw or cooked, is offered as its own candidate straight after the entry.
9. **Confirm is enough.** Automatic matches are exported unreviewed and shown as automatic in
   details; the user still picks every candidate on Confirm before anything is logged.
10. **Ask before sending.** No search query leaves the Mac until the owner has approved that exact
    query (section 8).
11. **Owner label values stay measured.** Values the owner typed or confirmed from a pack are
    `manual_declaration` and `measured` for the nutrients printed, as when a label is typed into the
    app today; Open Food Facts and generic values are `augmented`.
12. **Existing log rule for identity facts.** An entry carrying label values may ask for unknown
    preparation, packing medium, fortification and the other identity facts on Confirm before Log,
    as Open Food Facts products already do; pure generic matches keep the estimate allowance (section
    7). No log policy changes.

## 3. Architecture gate

**Responsibilities**

- *Domain* (`FoodLedgerDomain`): pure `PersonalFoodDatabaseEntry`, `PersonalFoodDatabaseRelease`
  and a pure codec for the wire format, with the validation in section 4.2.
- *Application* (`FoodLedgerApplication`): `PersonalFoodDatabaseImporting` (a consumer-owned seam
  for the Settings view model: validate, derive the release ID from the file bytes through the
  injected `Digesting` port, replace atomically, and reject a declared source whose ID is already
  stored with different fields, read through the existing `FoodConfirmationReading.sourceRelease(id:)`);
  the consumer-owned `PersonalFoodDatabaseStoring`
  port; and `PersonalFoodDatabaseFoodSearch` implementing `GenericFoodSearching`. Referenced records
  come through a consumer-owned `GenericRecordResolving` port:
  `resolve(source, corpusSHA256, recordID, evidenceIDs, queryAlias) -> ResolvedGenericRecord?`. The
  adapter builds the candidate through its **own** candidate builder: record facts (name, brand,
  variant, barcode, item class, pack facts, `sourceReleaseID`, `recordID`, identity, edible quantity,
  nutrients) are exactly the adapter's; evidence IDs and match metadata are bound to the current
  request, with `methodVersion` `pfc-resolution-v1` and the adapter's own score for `queryAlias`. It
  also returns the adapter's own `SourceRelease`, so the composite's duplicate-release check and
  `FoodSearchResultMerger`'s record check both hold. CoFID, USDA and TFDA
  adapters implement it; CIQUAL is out of scope.
- *Infrastructure*: a new `FoodLedgerPersonalDatabase` target depending only on Domain and
  Application, holding the protected store in the dataset layout of
  `food-library-storage-and-backup-decision.md` (`FoodLedger/Datasets/<release_id>/` with the file
  and a manifest), one active release. Protected data unavailable is reported as unavailable.
- *Presentation*: Settings row "Your food database" (import, replace, remove, last imported, entry
  count, unresolved references) and source details on Confirm.
- *Composition root*: the only importer of the store target. `check-boundaries.sh` gains that rule
  with a failing fixture.

Dependency direction is unchanged; no GRDB, file-system, SwiftUI or hashing implementation crosses
a port. The one extension axis is the store. Format, provenance, precedence and the confirmation
path are closed.

## 4. File format `personal-food-catalogue-v1`

UTF-8 JSON without a byte-order mark, at most 26,214,400 bytes and 20,000 entries. Decoding is
**strict**: unknown keys, missing keys and repeated keys in one object are rejected.

**Release identity.** The file carries no self-hash. The app computes SHA-256 of the exact bytes;
the release ID is `pfc:sha256:<hex>`. Every field of every release is a pure function of its ID,
so importing the same bytes again, or seeing the same ID in a later file, gives an identical
`SourceRelease`; the importer rejects a declared source whose ID is already stored with different
fields. The database release is `sourceID` `personal-food-database`, `releasedAt` `generated` at
00:00:00Z (inside the hashed bytes; the import time is kept only in the manifest), `artifactHash` and
`manifestHash` the file hash, `schemaVersion`
`personal-food-catalogue-v1`, `pipelineVersion` `pfc-resolution-v1`, licence "private", attribution
"Your food database, built by the owner".

Top level (exactly these keys):

| Field | Meaning |
|---|---|
| `schema` | `personal-food-catalogue-v1` |
| `generated` | a real `YYYY-MM-DD` date, the owner's build date; the database release's `releasedAt` |
| `sources` | every release that a label value cites, each with all `SourceRelease` fields: `source_release_id`, `source_id`, `released_at` (UTC), `artifact_sha256`, `schema_version`, `pipeline_version`, `licence`, `attribution`, `manifest_sha256` |
| `generic_corpora` | `{source, corpus_sha256}` for each referenced corpus, each source once; a hash that differs from the app's pin leaves that corpus's references unresolved |
| `items` | entries sorted by `id` |

Every release's fields except its date and hashes are fixed per `source_id`, and `artifact_sha256`
and `manifest_sha256` both equal the hash inside its ID:

| `source_id` | `schema_version` | `pipeline_version` | `licence` | `attribution` |
|---|---|---|---|---|
| `open-food-facts` | `off-v3.6-product-record` | `off-product-projection-v4` | exactly "ODbL 1.0 https://opendatacommons.org/licenses/odbl/1-0/; contents: https://opendatacommons.org/licenses/dbcl/1-0/" | exactly "Open Food Facts · https://world.openfoodfacts.org/product/" and the 8 to 14 digit code |
| `owner` | `pfc-intake-label-v1` | `personal-food-catalogue-skill-v1` | `private` | "Label values typed or confirmed by the owner" |

Open Food Facts releases use a reduced form defined here, distinct from the app's own
`off:snapshot:` releases so the two can never meet under one ID:
`pfc-off:sha256:<product record hash>:projection:off-product-projection-v4:retrieved:<YYYY-MM-DD>`,
with `released_at` that retrieved date and `source_id` `open-food-facts`. The record is the API v3.6
product object the app reads, serialised with sorted keys. Owner label releases are opaque:
`owner:sha256:<hash of title, values and capture date>`, with `released_at` the capture date and
`source_id` `owner`; a label without a capture date is never exported. These are the only two release forms and source IDs; `released_at` is always a
UTC date at 00:00:00Z. No file name, place or person ever appears in a
release ID, because release IDs travel into the food export.

Entry (exactly these keys):

| Field | Meaning |
|---|---|
| `id` | `pfc:` and 12 lower-case hex digits, unique within the file, entries sorted by it. The importer treats it as **opaque** (no recomputation, so no Unicode case-folding parity is needed between Python and Swift). The skill derives it from SHA-256 of `v1|<normalised brand>|<normalised title>` (NFKC, case fold, runs of letters, numbers, combining marks, `&` and `%`) and refuses to export two entries with the same normalised brand and title |
| `brand` | brand or `null` |
| `title`, `titles`, `aliases` | display title (string), every title variant seen and search terms (lists of strings) |
| `concept`, `variety`, `fallback_chain` | generic concept, more specific kind, most specific to most generic |
| `category` | closed: `fruit`, `vegetable`, `herb_spice`, `dairy`, `egg`, `meat`, `fish`, `grain_cereal`, `bakery`, `legume`, `nut_seed`, `oil_fat`, `condiment_sauce`, `snack`, `confectionery`, `beverage`, `alcohol`, `ready_meal`, `other` |
| `product_type` | closed: `fresh_whole`, `packaged_single_ingredient`, `packaged_composite`, `unknown` |
| `state` | closed: `raw`, `cooked`, `canned`, `frozen`, `dried`, `smoked`, `unknown` (section 4.1) |
| `basis` | `per_100_g` or `per_100_ml_as_labelled`, taken from evidence only: the owner's confirmed label, else the item's own product record, never another brand's record or the category. An entry with no label values uses `per_100_g`, the generic records' basis. One basis per entry |
| `label_nutrients` | printed label values (below), possibly empty |
| `generic_reference` | `null` or `{source, corpus_sha256, record_id, match, role}` |

Label nutrient value (exactly these keys; `transforms` and `source_value` together or not at all):

```json
{"value": 400.0, "unit": "mg", "source_kind": "exact_product_dataset",
 "source_release": "pfc-off:sha256:<64 hex>:projection:off-product-projection-v4:retrieved:2026-11-07",
 "record_id": "off:gtin:05036589252092", "match": "probable",
 "transforms": [{"transform_id": "mass-g-to-mg", "version": "v1"}],
 "source_value": {"value": 0.4, "unit": "g"}}
```

- `source_kind` and `match` are a closed pair: `manual_declaration` with `owner` (values the owner
  typed, or agent-read photo or page values the owner confirmed; `record_id` null; its release has
  `source_id` `owner`) and `exact_product_dataset` with `probable` (the product's own Open Food Facts
  record; `record_id` exactly `off:gtin:` and 14 ASCII digits; its release has `source_id`
  `open-food-facts`). Agent-read values the owner has not confirmed are never written.
- Values are finite, non-negative numbers in canonical units. There is no null, trace or bounded
  value in v1: an Open Food Facts value with a `<` or `>` modifier, a trace or an "N" is left out
  and stays unknown. Zero is only a declared zero.
- Transforms reuse the app's own pairs. The two calculations, `salt_to_sodium_v1` /
  `pasted-label-conversions-v1` (sodium from salt in g: g / 2.5 × 1000) and `kj_to_kcal_v1` /
  `pasted-label-conversions-v1` (kcal from kJ, only when kcal is not printed: kJ / 4.184), appear only
  on `manual_declaration` values and keep `calculated: true` in the food export
  (`NutrientDerivation.calculatedTransforms`). The unit conversion `mass-g-to-mg` / `v1` (sodium in
  g) appears only on `exact_product_dataset` values and is not a calculation (`calculated: false`).
  Each applies to one nutrient, one source unit and one source kind. `transforms` holds exactly one `{transform_id, version}` and `source_value` exactly
  `{value, unit}` with the printed value; the importer recomputes the value from `source_value` and
  rejects a difference above 0.5 per cent. Unknown pairs are rejected.
- Open Food Facts values follow the app's `OpenFoodFactsLookup.project` rules exactly, read from
  the same API v3.6 product endpoint with the same status and returned-code checks (the skill's
  `off_rules.py` is a cited port): the same eight fields; one packaging input set for the product's
  basis, or legacy `nutriments` only for mass products with `nutrition_data_per` 100g; legacy sodium
  unknown; a pack quantity that is mass or volume, not both; dietary supplements refused; the stored
  unit must be canonical, with sodium g to mg the only conversion. The one difference: a value the
  app would bound is left out, because v1 has no bounds.

Generic reference:

- `source` is `cofid`, `usda` or `tfda`; `record_id` (a non-empty string) is the record identity
  the app's adapter uses for its candidates (the CoFID and USDA corpus record IDs as stored;
  `tfda:<id>` for TFDA, and only TFDA uses that prefix).
- `match` is `same_food_same_state` or `close`. `role` is `merge` only when the match is
  `same_food_same_state`, the entry's state is `raw` or `cooked`, and the basis is `per_100_g`;
  otherwise `candidate` (decision 8). A concept-only match is never written.
- If the corpus hash differs from the pin, or the record is missing, the reference is unresolved:
  the entry keeps its label values, Settings counts it, and nothing is substituted.

### 4.1 State and identity mapping

| `state` | Identity used for the merge |
|---|---|
| `raw` | `PreparationState(kind: .raw)` |
| `cooked` | `PreparationState(kind: .cooked, method: nil)` |
| `canned`, `frozen`, `dried`, `smoked`, `unknown` | preparation unknown, so no merge (decision 8) |

Bone, skin, drained state, packing medium, fortification and salt state are unknown on the entry.
A `merge` reference takes its decisive identity from the referenced record; the merge is eligible
only where identity contract section 8 finds the two compatible (section 6). Nothing is inferred
from the title.

### 4.2 Rejection rules

The importer rejects the whole file, with a visible reason and the active release unchanged, for:
invalid JSON (including `NaN` and `Infinity` tokens), a byte-order mark or non-UTF-8 bytes; a number
too large to be a nutrient value; size or count limits; any unknown, missing or
repeated key at any level; a field of the wrong type; an unknown `schema`; `generated` not a strict
`YYYY-MM-DD` real date; a source missing any release field, with an unknown `source_id` or release
form, hashes that differ from the hash in its ID, fields off the pins above, a malformed
`released_at`, an Open Food Facts `released_at` that is not the date in its ID, or declared twice; a duplicate corpus; a value citing
a release not in `sources` or one of the wrong source; a `record_id` outside its kind's form; an
`id` not of the `pfc:` form, duplicated or out of order; a missing title; a value outside the closed vocabularies; an
unknown nutrient key or a non-canonical unit; a negative, non-finite or boolean value; a
`source_kind`/`match` pair outside the closed list; an unknown transform, one on the wrong nutrient,
source unit or source kind, a value that does not follow from its `source_value`, a transform without
`source_value` or the reverse; a generic reference with an unknown source, a non-admitted match or
role, a `merge` role that fails the merge condition, an undeclared corpus hash, or a TFDA record ID
without `tfda:` (or a non-TFDA record ID with it). The importer never crashes on a
malformed file: every unexpected type is a rejection.

## 5. Search: local first, then online

- The adapter matches the parsed query against `title`, `titles`, `aliases`, `variety` and
  `concept` with the existing lexical rules, in three steps: (1) title or alias, (2) variety,
  (3) concept. The step is carried on the application type `GenericFoodMatch` (next to
  `isExactName`), never on the Codable domain candidate.
- Each entry produces at most two candidates, in this order: the entry itself (its label values,
  plus the generic values when the reference role is `merge`), then, when the role is `candidate`,
  the referenced generic record as its own candidate. That candidate is the adapter's own
  `PopulatedFoodCandidate` (section 3); "Generic: <name>" is presentation only, from the step and
  role on `GenericFoodMatch`. When the same `FoodSearchCandidateID` also comes back from that
  source's own route, the composite, after the v12 sort, keeps the first one (in the database
  group) and drops the later copy only when `sameSourceRecord` holds, and otherwise throws, as the
  merger does. `sameSourceRecord`, today private to `FoodSearchResultMerger`, moves to one shared
  internal function in `FoodLedgerApplication` used by both, so the record-equality rule has one home;
  the composite's dedupe runs after the v12 sort and its fat and preparation partitions, before
  `PopulatedFoodConfirmation` is built. An entry with no
  values and no reference is shown as "No nutrition data yet" with its fallback chain.
- Results use a new source family **"Your food database"**, not the closed "Your foods" family; the
  family mapping in `FoodSearchResultSummary` is amended for this one case.
- Ranking is `composite-generic-ranking-v12`, a new document. v12 keeps v11's keys and adds one
  group key placed **first**, ahead of the preparation-unverified, group, cocoa, exact-name and
  preference keys: Your food database steps 1, 2 and 3, then every other source in v11 order. The
  v11 fat and preparation-unverified partitions, which today run globally after the sort, are
  restructured to run within each group; this deliberately lets a database row with unknown
  preparation, or one missing a fat term, rank above verified rows from other sources, and the v12
  document must say so. With no database rows, v12 output
  equals v11 exactly. Exact saved aliases still short-circuit before any of this.
- **Online routes stay where they are.** "Local first" is an ordering rule only. When online
  lookups (Open Food Facts) or label reading (OpenRouter, from a photo or pasted text) run is
  unchanged and is decided by the existing `FoodSearchEscalationPolicy` and its sufficiency test
  (strong identity and complete required nutrition). A database row is assessed by that same test;
  a lexical match alone never suppresses an online route. Online results are separate candidates and
  never fill or overwrite a database entry.
- Database rows are not used as the label-estimate pool and are not offered in the pasted food list
  queue in v1 (section 12).

## 6. Amendment A1: per-nutrient sources within one entry

Unified food search contract v1, lines 26 to 27, says: "Do not combine one candidate's strong
identity with another's complete nutrients." and "Never silently combine nutrients". A1 permits a
combination **only for Your food database entries whose reference role is `merge`**, and only
visibly. It is recorded as dated amendment rows in `unified-food-search-contract-v1.md` and identity
contract section 8, in the same change that implements this document. Its method version is
`pfc-resolution-v1`, carried in `CandidateMatchMetadata.methodVersion`.

1. Resolution is per nutrient under identity contract section 8, unchanged except for item 2:
   label values are used for the nutrients they declare, and the merged generic record supplies the
   rest. The merge happens only if section 8 finds the entry's identity (section 4.1) and the
   record's compatible; otherwise the generic record is offered as a separate candidate.
2. For **Your food database entries only**, when `product_type` is `fresh_whole`, the generic record
   comes before an `exact_product_dataset` value, because a retailer label for loose produce rarely
   describes the edible portion. A `manual_declaration` value still comes first.
3. One generic record per entry, so no generic-against-generic conflict arises. A disagreement
   between label values at the same level is a conflict and the nutrient is unknown, as in section 8.
4. Value states (decision 11): `manual_declaration` values the owner typed or confirmed from a pack
   are `measured` for the nutrients printed, as the domain's provenance rule requires and as when a
   label is typed into the app today; every other value from Your food database (Open Food Facts and
   generic) is `augmented`. A product-name match never makes a value measured.
5. When an entry's nutrients come from more than one source, Confirm shows "Nutrients from more than
   one source", with the per-nutrient list and "automatic match" behind details.
6. Bundled source adapters keep their own no-backfill rule; A1 does not apply to them.

## 7. Confirmation, saving and records

- A database result enters the shared Confirm screen with one Log action. Nothing is selected or
  saved automatically; the quantity is always the user's.
- Identity facts follow the existing `FoodLogPolicy` unchanged. An entry whose values all come from its
  merged generic record, and a separate "Generic" candidate, use the existing generic-estimate
  allowance (`FoodConfirmationPolicy.isGenericEstimate`: generic-search evidence and only
  `generic_composition_dataset` provenance). An entry carrying label values is treated like an Open
  Food Facts product today: Confirm asks for any unknown preparation, bone, skin, drained state,
  packing medium or fortification through the existing correction flow before Log is enabled. No log
  policy changes (decision 12).
- On save, the ledger stores the resolution as today with only existing `ProvenanceSourceKind`
  cases, and persists `SourceRelease` records for the database release (section 4), for each cited
  label release (from `sources`) and for the merged generic record (the adapter's own release). The
  database release names its upstream releases through each value's `NutrientProvenance`
  (`sourceReleaseID` and `manifestReference`), as a reduced local corpus under identity contract
  section 7.
- Replacing or removing the database never edits or deletes saved food. Release records stay in the
  ledger and archives. In v1, re-resolution of a log whose database release is not installed returns
  the existing `unavailableTarget` outcome and changes nothing. Stored records, archives and exports decode and
  re-encode unchanged.
- The daily food export carries what any saved log carries; release IDs in it are opaque. Under
  its closed origin table, `manual_declaration` values (owner-typed, or owner-confirmed photo or page
  values) export as `entered_by_you`, `exact_product_dataset` values as their product origin, and the
  merged generic values as the generic origin, with `calculated: true` where a calculated transform
  was used. The
  database file itself is not exported, backed up or sent anywhere.
- A locked store makes the adapter return no result; it never throws into the composite, so other
  sources still answer. The "unavailable" state is shown only in Settings ("Your food database is
  locked until you unlock your iPhone"), never as search guidance: the database route's no-result is
  never the composite's fallback route. The composite gains one init parameter, `databaseSource`, for
  the database group.

## 8. Privacy and egress

App side: no new destination. Import reads a file the user chose on the device; search and confirm
run offline. The store uses complete file protection and "Remove" deletes it.

Developer side (not app egress), recorded in [`privacy-and-egress.md`](privacy-and-egress.md) with
owner approval of 7 November 2026: the skill's scripts send Open Food Facts only (a) product titles
from the owner's receipts (item lines only, never headers) and from intake items that name a brand,
with pack sizes removed, (b) generic food names, and (c) barcodes of chosen matches, all through the
paced client. Every query
passes the outbound gate `http_client.safe_query` (deny patterns plus at least one known food word,
or Chinese text containing a known Chinese food fragment from the TFDA names),
and, because a word list cannot recognise every personal name, is sent only after the owner has
approved that exact query (`owner_approval`: planned queries go to a pending file and the run stops
before any network call; declined queries are never sent). Decision 10. Barcode lookups send only
digits from Open Food Facts' own results and need no separate approval. Product pages
the owner names are read once with the agent's web-fetch tool. What the agent reads reaches the
agent's model provider: the owner's notes, label and receipt photos, CSV header rows, product pages
the owner names, and the food titles the agent maps or shows the owner for approval; only when the
owner asks.

## 9. Contract tests (synthetic fixtures only)

- The on-disk synthetic fixtures in `docs/fixtures/personal-food-database-v1/` (a golden file with
  ASCII, accented and Chinese titles, one `reject-*.json` per rule, and `manifest.json` giving each
  file's expected **rule code**; the two large cases, size and count, are generated at test time),
  consumed by both the skill's `check_bytes` (`test_export_check.py`) and the Swift importer tests,
  which must report the same rule code for each file; neither may crash on any of them.
- An owner-typed database value saves and round-trips as `manual_declaration` and `measured`.
- The resolver binds the request's evidence IDs, and the confirmation builds without
  `missingProvenance`.
- Release immutability: the same bytes give an equal `SourceRelease`; the same Open Food Facts or
  owner release ID in two files has equal fields; a known ID with different fields is rejected and
  the active release stays; re-resolution after remove gives `unavailableTarget`, and after re-import
  succeeds.
- A locked database store, with every other source returning no result, shows the other source's
  guidance, not the database's.
- Generic candidate dedupe: a database "Generic" candidate and the same record from its own source,
  differing only in match metadata, give one row in the database position and the merger succeeds;
  differing record facts throw.
- A salt-derived or kJ-derived database value exports `calculated: true`.
- Release identity: the same bytes give the same `pfc:sha256:` in Python and Swift; one changed byte
  gives a new release.
- Open Food Facts parity: the cases in the skill's `test_off_rules.py` reproduced against
  `OpenFoodFactsLookup.project`, using the v3.6 response shape, including non-string `quantity` and
  `product_name`.
- Resolver contract shared by the CoFID, USDA and TFDA resolvers: resolves by the defined record
  form; a hash mismatch or missing record is unresolved; returns the adapter's own `SourceRelease`;
  the composite never throws a duplicate release.
- Merge: `same_food_same_state` with raw or cooked merges when section 8 agrees; `close`, other
  states and incompatible identity become a separate candidate; same-level label conflict gives
  unknown; the fresh-food order; `pfc-resolution-v1` recorded; `manual_declaration` values `measured`,
  Open Food Facts and generic values `augmented`, and a merged entry holding both passes `NutrientEntry`
  validation.
- Ranking v12: no database rows gives v11 output exactly (FoodSearchQuality and FoodQueryEvaluation
  fixtures); exact-alias short-circuit; tier tests with database rows under preparation, fat and
  cocoa queries; the step on `GenericFoodMatch`; family never `.yourFoods`.
- Escalation: a lexical-only database match does not suppress an online route.
- Provenance round trip: a saved log decodes and re-encodes byte-stable; its release records resolve
  after removal, archive restore and in the food export.
- Lifecycle: atomic replace; failed import keeps the active release; locked store is unavailable
  and does not fail other sources; remove keeps logs and release records.
- Boundaries: store target import rule with a failing fixture; no network module reachable.
- Simulator journey: import a synthetic file, search, open Confirm, see the source notice, log,
  remove the database, see the log unchanged.

## 10. Validation

The gates in `AGENTS.md`, plus FoodSearchQuality and FoodQueryEvaluation for the ranking change.
Device acceptance is the owner's: import the real file on the iPhone and compare entries with their
packs.

## 11. Relationship to the skill

`export_v1.py` writes this format, checks the bundled corpus hashes against the Swift pins, runs
`check_bytes` on its own output and refuses to write a file the app would reject. It withholds
unconfirmed values and maps any model-proposed value outside a closed vocabulary to `unknown` or
`other`, reporting the count. Label values come only from full Open Food Facts product records and
owner-typed or owner-confirmed labels.

## 12. Open questions for the owner

1. Decided: another brand's label stays out of v1 (decision 7).
2. Decided: developer-side egress recorded (section 8).
3. Decided 7 November 2026: supplements stay out of v1; a separate v2 with a count basis (per tablet,
   capsule or scoop) will cover them.
4. Decided 7 November 2026: database rows stay out of the pasted food list queue and the
   label-estimate pool in v1; they appear only in ordinary search.
