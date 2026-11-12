# Personal food database import v1: phase 1 plan and P1a gate

Status: **draft, 11 November 2026, programme #424, base contract #419.** It plans the app side of
[import v1](personal-food-catalogue-import-v1.md) (revision 5, accepted 7 November 2026), which is
step 1 of the order of work in the [estimates contract](personal-food-catalogue-estimates-v1.md)
(section 6). E3 is final (plan revision 7, decision 11) and both contracts are accepted, so the
block on importer code is lifted. This document changes no rule of either contract; where it
refines one, it says so and the contract wins.

## 1. Why phase 1 is split

Import v1 is one contract but four kinds of change: a pure codec, a protected store with a
Settings lifecycle, a search adapter with a nutrient merge, and the confirmation, save and export
path. One PR for all of it would be too large to review against the closed rules. Phase 1 is
therefore three PRs, each with its own ledger row, in this order:

| PR | Scope | Contract sections |
|---|---|---|
| **P1a** | Pure domain codec for `personal-food-catalogue-v1`: strict JSON reading, typed model, every rejection rule with the shared rule codes, release identity as a pure function of the digest. No store, no UI, not wired. | 3 (domain), 4, 4.1, 4.2, 9 (fixtures, release identity) |
| **P1b** | `FoodLedgerPersonalDatabase` store target (protected dataset layout, one active release), `PersonalFoodDatabaseImporting` (validate, digest, atomic replace, release immutability), Settings row "Your food database" (import, replace, remove, locked), boundary rule with a failing fixture. | 3, 7 (lifecycle, locked), 8, 9 (lifecycle, immutability, boundaries) |
| **P1c** | `GenericRecordResolving` for CoFID, USDA and TFDA, `PersonalFoodDatabaseFoodSearch`, the composite's `databaseSource`, the "Your food database" family, amendment A1 merge, Confirm notice, save, release records and export, the amendment rows, and the simulator journey. No ranking change: rows take their v11 place. | 5 (except v12), 6, 7, 9 |

Then, as the estimates contract orders: phase 2 (estimates decoder, provenance kind, capture
manifest, presentation, export amendment) and phase 3 (ranking v12).

## 2. P1a architecture gate

**Responsibilities.**

- `PersonalFoodDatabaseJSON` (`FoodLedgerDomain`): a strict, byte-level reader that turns the file
  into a small value tree (object as ordered key and value pairs, array, string, number as its
  exact source text plus a finite `Double`, boolean, null). It refuses a byte-order mark, UTF-16 or
  any non-UTF-8 byte, `NaN`, `Infinity` and every other non-JSON token, a repeated key in one object,
  nesting deeper than a fixed limit and trailing bytes. Foundation's `JSONSerialization` and
  `JSONDecoder` are not used for this file: neither reports repeated keys, and both lose the exact
  number text the "too large to be a nutrient value" rule needs.
- `PersonalFoodDatabaseCodec` (`FoodLedgerDomain`): `decode(_ bytes: Data) -> Result<PersonalFoodDatabaseFile, PersonalFoodDatabaseRejection>`.
  It enforces the size and count limits, then every rule of section 4.2 on the value tree, and
  collects every failing rule code rather than stopping at the first, as the skill's `check_bytes`
  does. The rejection carries the set of rule codes and a short visible reason; it never carries an
  entry ID, title or value, so a later Settings message cannot leak file content.
- Typed model (`FoodLedgerDomain`): `PersonalFoodDatabaseFile`, `PersonalFoodDatabaseEntry`,
  `PersonalFoodDatabaseLabelValue`, `PersonalFoodDatabaseGenericReference`,
  `PersonalFoodDatabaseDeclaredSource`, and closed enums for category, product type, state, basis,
  source kind and match pair, generic source, reference match and role. Values use the existing
  `NutrientKey` and canonical units; transforms use one table built from the app's existing pairs
  (`NutrientDerivation.calculatedTransforms` and the `mass-g-to-mg` conversion), each limited to its
  nutrient, source unit and source kind, with the 0.5 per cent recompute check.
- Release identity (`FoodLedgerDomain`): `PersonalFoodDatabaseRelease.sourceRelease(fileSHA256:generated:)`
  builds the database `SourceRelease` exactly as section 4 defines it, as a pure function of the
  digest and the `generated` date. The digest itself is computed by the caller through the
  existing `Digesting` port (P1b); the domain never hashes.

**Dependency direction.** Domain only: Foundation and existing `FoodLedgerDomain` types. Nothing
imports the new types yet except tests. No application, infrastructure or presentation change, no
persisted format or schema change, no migration.

**Invariants.** A rejected file yields no model. Every unexpected type is a rejection, never a
crash or a trap. Unknown stays unknown: there is no null, trace or bounded value, and zero is only
a declared zero. Entry IDs are opaque (never recomputed). The rule codes are the skill's codes, so
the two checkers cannot silently disagree.

**Extension axes.** None. The format is closed; a new field, source, transform or vocabulary value
is a new schema version. The estimates decoder of phase 2 sits beside this codec and shares its
validation functions, so P1a exposes them as internal functions of the module rather than private
helpers of one type.

**Contract tests (synthetic fixtures only).**

- Every file in `docs/fixtures/personal-food-database-v1/manifest.json`: `golden.json` decodes; each
  `reject-*.json` is rejected with its listed rule code among the codes; none crashes. The two
  generated cases (size and count) are built at test time. The test reads the manifest, so a new
  fixture added for the Python checker is picked up by Swift with no code change.
- The golden file decodes to the expected typed values (ASCII, accented and Chinese titles; a
  transform value; a `merge` and a `candidate` reference).
- Release identity: for `golden.json`, the release ID from SHA-256 of its bytes equals the one the
  skill's `export_v1` computes (pinned in the test as a constant derived from the fixture); one
  changed byte gives a different release; the `SourceRelease` fields match section 4 exactly.
- The strict reader in isolation: repeated keys at depth, BOM, UTF-16, non-finite tokens, deep
  nesting, trailing bytes, huge integers, escaped and non-BMP strings.

**Validation.** `swift test --package-path Packages/FoodLedgerKit`, `check-boundaries.sh` and
`git diff --check`. P1a touches no app target, so the Xcode gates run but are expected unchanged.

### 2.1 Changes from the architecture-gate review (11 November 2026)

Verdict PASS WITH CHANGES. Each change below binds P1a and overrides any looser wording above.

1. **Numbers.** A number node keeps its exact text and a `Double` that may be infinite. The codec
   rejects as `value` anything non-finite, negative or at least 1e15 (`export_v1._num`), so the
   400-digit fixture gives `value`, as the manifest expects. Python refuses an integer of more than
   4,300 digits as `json`; Swift does the same by counting digits before conversion, and a shared
   fixture pins it.
2. **Lone surrogates** (`"\ud800"`) cannot be held in a Swift `String`. Both checkers reject them as
   `json`; the Python checker gains the rule and a shared fixture.
3. **Unicode comparison.** Keys, IDs and vocabulary are compared by Unicode scalars, never by Swift
   `String` equality (which uses canonical equivalence), so two keys differing only as NFC and NFD
   are distinct, as in Python. Every digit, hex, date and GTIN rule checks ASCII bytes;
   `Character.isHexDigit` and other Unicode-aware predicates are not used, and unvalidated text never
   reaches `SHA256Digest`.
4. **Stage order,** as in `check_bytes`: size, then BOM, then whole-file UTF-8 (`encoding`), then
   parse (`json`), then the rules. The reader checks depth before recursing, with Python's
   effective limit stated in code, and overflow is `json`.
5. **No throwing primitives on file content.** No `try!`; brand and titles are kept as raw strings
   (an empty brand string is valid). The `title` rule uses one whitespace set equal to Python's
   `str.strip()` (which includes U+001C to U+001F), with a shared fixture.
6. **Declared sources.** `PersonalFoodDatabaseDeclaredSource.sourceRelease()` moves into P1a, so
   P1b's immutability check has its mapping. The Open Food Facts parity test (contract section 9)
   is owned by P1c.
7. **Rule codes.** A closed Swift enum whose raw values are the Python codes, with a test that the
   two sets are equal. The Python checker emits `corpus` instead of `malformed` for a non-string
   corpus source. New shared fixtures cover `sources`, `item-keys`, `label-nutrients`,
   `value-shape` and that corpus case.
8. **Transforms.** A separate allow-list for this schema, sodium-only for `mass-g-to-mg`;
   `NutrientDerivation.calculatedTransforms` is not changed. The check copies Python's formula and
   order exactly: rejected when `abs(f(sv) - v) > 0.005 * abs(f(sv)) + 1e-9`.
9. **Release date.** `sourceRelease` takes the validated typed date and computes 00:00:00Z with a
   fixed UTC Gregorian calendar, never the process calendar or time zone.
10. **Golden bytes.** The fixture folder is marked `-text` in `.gitattributes`; the test pins the
    SHA-256 `shasum` gives for the committed `golden.json` and uses a test-local CryptoKit digest.
11. **Accept set.** The manifest gains an `accept` list checked by both sides: `-0`, `4e2`, an
    integer value, a transform exactly at the tolerance, an empty brand, empty `label_nutrients` and
    `titles`, and an `off-product-projection-v5` release.

12. **Value budget** (from the Qodo review of PR #465). A file below the byte limit can still hold
    millions of tiny values, and the parsed tree would exhaust the phone's memory before any count
    rule ran. Both checkers refuse a file of more than 4,000,000 JSON values (object keys not
    counted) as `count`, checked after parsing and before unpaired surrogates. The Swift reader stops
    storing values once past the budget but keeps parsing, so a later syntax error or repeated key
    is still reported first, as in Python; its nodes keep no number text and are not boxed. This
    refines the "size or count limits" of import v1 section 4.2: a real file holds far fewer values
    than its bytes allow (the 20,000-entry limit stays the binding one), so only a dense or hostile
    file reaches it. The manifest carries `max_values`, and a generated case checks it on both sides.

Added contract tests: the rule-code set equality; stage order; lone surrogates, depth limit plus
one, an integer over 4,300 digits, `1e400`, `1e15` and a U+001C title; NFC and NFD keys distinct;
full-width digits rejected in GTIN, hex and dates; the tolerance boundary both ways; declared Open
Food Facts and owner sources mapping to `SourceRelease`; `releasedAt` unchanged under a non-UTC
process time zone; a seeded fuzz of truncations and type swaps of the golden file with no trap;
and the accept set on both checkers.

Python changes stay inside the skill script and its tests; no frozen tool, seal or freeze record
changes. They make the checker stricter only for inputs no build has produced (lone surrogates) or
change one rejection's code (`malformed` to `corpus`).

## 3. P1b architecture gate (11 November 2026)

P1b installs, replaces and removes the file and shows it in Settings. Nothing searches it yet: the
store has no reader outside the Settings flow until P1c, and no food record, export or HealthKit
path changes.

**Responsibilities.**

- `PersonalFoodDatabaseStoring` (`FoodLedgerApplication`, consumer-owned port): `activeRelease()`
  returns the installed file's bytes and manifest or nil; `install(bytes:manifest:)` replaces the
  active release atomically; `remove()` deletes it. It throws only `PersonalFoodDatabaseStoreError`
  (`locked`, `damaged`, `writeFailed`); no `URL`, `FileManager` or protection type crosses it.
- `PersonalFoodDatabaseManifest` (`FoodLedgerApplication`, a plain value type): schema, release ID, file
  SHA-256, `generated`, import time, entry count and a manifest version. The import time lives only
  here (import v1 section 4), never in a `SourceRelease`.
- `PersonalFoodDatabaseImporting` (`FoodLedgerApplication`, the Settings view model's seam) with one
  implementation, `PersonalFoodDatabaseImporter`, injected with the store, `Digesting`, `LedgerClock`
  and the existing `FoodConfirmationReading` (for `sourceRelease(id:)`, as import v1 section 3 names
  it). Operations:
  - `status()`: `none`, `installed(summary)`, `locked` or `damaged`. The summary holds release ID,
    `generated`, import time and entry count, never entry content.
  - `importFile(_ bytes: Data)`: codec decode (P1a), digest, the database `SourceRelease` and each
    declared source's `SourceRelease`, the immutability check, then `install`. Any failure leaves the
    active release as it was.
  - `remove()`.
- **Immutability check.** Each declared source, and the database release itself, is compared with
  (a) the ledger's stored release of the same ID and (b) the same ID among the active file's declared
  sources. Any difference rejects the import with `releaseConflict` and installs nothing. Importing
  the same bytes again is a no-op that reports the existing summary.
- `FilePersonalFoodDatabaseStore` (new target `FoodLedgerPersonalDatabase`, depending only on
  Domain and Application): this answers the P1a open point. The file lives under the existing
  dataset root of `food-library-storage-and-backup-decision.md` section 3, inside the app's
  `FoodLedger/v1/` root:

  ```text
  FoodLedger/v1/Datasets/personal-food-database/active.json        pointer to the active release
  FoodLedger/v1/Datasets/personal-food-database/pfc-sha256-<hex>/personal-food-catalogue-v1.json
  FoodLedger/v1/Datasets/personal-food-database/pfc-sha256-<hex>/manifest.json
  FoodLedger/v1/ImportStaging/personal-food-database-<uuid>/
  ```

  A release folder is named `pfc-sha256-<hex>` (the release ID with `:` replaced, since `:` is a path
  separator in Finder). Install writes the file and manifest into a staging folder, renames it into
  place, then replaces `active.json` atomically (the commit point), then deletes the old folder;
  leftover staging folders and unreferenced release folders are swept on the next install. Every
  folder and file uses `FileProtectionType.complete` and is excluded from backup (import v1 section
  7: the file is not backed up). Load reads the pointer, the manifest and the file, and checks the
  file's SHA-256 against the manifest through the injected `Digesting`; a mismatch or an undecodable
  manifest is `damaged` (storage decision section 3, "disable that release"). Protected data
  unavailable, through an injected availability check or a protection error, is `locked`, never
  empty and never damaged.
- **Presentation** (`FoodLedgerPresentation`): `PersonalFoodDatabaseSettingsViewModel` with explicit
  `loading`, `none`, `installed`, `locked` and `damaged` states, an `isWorking` flag for an import or
  remove in progress and a `message` for its outcome (including every failure), and all copy.
  A rejection shows a short reason per rule-code group (for example "This file is not a food
  database file from your Mac" or "An entry in this file could not be read"), never an entry ID,
  title or value. The outcome message is announced to VoiceOver.
- **App**: Settings row "Your food database" in the Data section (detail: entry count, "Locked",
  "Needs replacing" or "Not added"), opening a screen with Import (or Replace) through the system
  file picker (`.json`, size checked before reading, as `InventoryBackupFile` does), Remove behind a
  confirmation that says saved food is kept, and last imported, generated date and entry count.
- **Composition root**: the only importer of `FoodLedgerPersonalDatabase`. `check-boundaries.sh`
  gains that rule and a self-test fixture that must fail (an application file importing the target).

**Dependency direction.** Domain ← Application ← `FoodLedgerPersonalDatabase` (Foundation file APIs
only) ← composition root. Presentation depends on Application only. No GRDB, SwiftUI, UIKit or
CryptoKit in the new target; protected-data availability is injected as a closure from the app.

**Invariants.** A failed, rejected or interrupted import keeps the active release byte for byte. One
active release. Remove and replace never touch the ledger, saved food or release records (no ledger
write at all in P1b). Locked is reported as locked. No network. No file content in any message or
log. The manifest is not a `SourceRelease` and never enters the ledger.

**Extension axes.** The store (an in-memory test store in `FoodLedgerTestSupport` passes the same
contract suite). Nothing else.

**Contract tests (synthetic fixtures only).**

- Store contract suite, run against the file store (temporary folder) and the in-memory store:
  install then load returns equal bytes and manifest; replace swaps atomically; an injected failure
  at each install step (staging, rename, pointer) leaves the previous release loadable; remove then
  load is nil; a changed byte in the stored file is `damaged`; locked is `locked` for load, install
  and remove.
- Importer: the golden file installs with release ID `pfc:sha256:` of its bytes and the codec's
  entry count; a reject fixture installs nothing and returns its rule codes; the same bytes twice is
  a no-op; a declared source whose ID the lookup holds with different fields is `releaseConflict`
  and the active release stays; the same with the active file's sources; equal fields pass; remove
  keeps the lookup's records (the importer never writes them).
- View model: every state and its copy; a rejection message contains no fixture title, ID or value.
- Boundaries: the new rules and a failing self-test fixture for each (section 3.1, change 9).
- App test in the simulator (`SettingsContributionTests`): through the composition root's model,
  import the golden fixture, see the row's entry count, reject a fixture with the active release
  kept, remove, see "Not added" and an empty folder.

**Deferred to P1c, with a reason.** The Settings row's "unresolved references" count (import v1
section 3) needs the CoFID, USDA and TFDA resolvers, which are P1c; P1b shows the entry count only
and P1c adds the unresolved count. Re-resolution after remove (`unavailableTarget`) and lifecycle
tests that need a saved database log are P1c, since nothing can be saved from the database before
then.

**Validation.** All `AGENTS.md` gates (P1b touches the app target and its Xcode project).

### 3.1 Changes from the architecture-gate review (11 November 2026)

Verdict PASS WITH CHANGES. Each change binds P1b and overrides looser wording above.

1. **Layout.** Import v1 section 3 and the storage decision write `FoodLedger/Datasets/<release_id>/`;
   every food ledger file already lives under `FoodLedger/v1/`, and the personal database gets its own
   folder so the pointer has one home. Import v1 records this as a dated clarification (section 3 of
   the contract); folder names are always `pfc-sha256-<hex>`.
2. **Same bytes.** Re-importing the active bytes is a no-op only when the active release loads and
   verifies. Over a `damaged` release (or a pointer naming a missing folder) the same bytes reinstall:
   that is the "Needs replacing" repair.
3. **Replacing a damaged release.** The active file's declared sources cannot be read when it is
   damaged, so that comparison is skipped and the ledger comparison still applies. Over a locked store
   the import fails as `locked` before any comparison.
4. **Crash sequence.**
   - Install: refuse bytes whose SHA-256 is not the manifest's; stage into
     `ImportStaging/personal-food-database-<uuid>/`; if the target release folder already exists, keep it
     untouched when the current pointer names it and it verifies, otherwise (an orphan no pointer
     names, or a damaged copy with nothing valid to lose) replace it; rename staging into place; write and protect `active.json.pending`, then
     rename it over the pointer (commit point; nothing that can fail runs after it); then sweep. A
     failed install deletes its own staging and pending files at once.
   - Remove: delete the pointer first (commit point), then the release folder, then sweep.
   - Reads go by path through `FileManager`; no URL-loading API (`contentsOf:`) is reachable, which
     the boundaries script checks.
   - Sweep: only after a pointer write or delete in this call succeeded, never while locked or damaged;
     it deletes release folders other than the one the pointer names and only
     `ImportStaging/personal-food-database-*` (other features share `ImportStaging`).
   - Load: no pointer is `none`, even with orphan folders present; a pointer that does not decode, or
     names a missing folder, is `damaged`.
5. **Versioned on-disk JSON.** The pointer `{"folder": "pfc-sha256-<hex>", "version": 1}` and the
   manifest `{"entry_count", "file_sha256", "generated" ("YYYY-MM-DD"), "imported_at" (RFC 3339 UTC to
   the second, "Z"), "release_id", "schema", "version": 1}` are encoded with sorted keys by the file
   store, which owns their shape; the Application manifest is a plain value and the in-memory store
   encodes nothing. Golden fixtures of both decode and re-encode byte for byte; an unknown version is
   `damaged`.
6. **Damaged check.** On load the store checks the file's SHA-256 against the manifest, that
   `release_id` is `pfc:sha256:` plus that hash, and that the folder name is the pointer's folder and
   matches the hash. Any mismatch is `damaged`.
7. **Port.** The importer reads releases through the existing `FoodConfirmationReading`, as the
   contract names; no new lookup port.
8. **Importer outcomes,** closed in Application: `installed(summary)`, `unchanged(summary)`,
   `rejected(rule codes)`, `releaseConflict`, `locked`, `writeFailed`, `tooLarge`, and
   `ledgerUnavailable` (the saved release records could not be read, so immutability could not be
   checked; added in implementation). None carries an entry ID, title, value or source field.
9. **Boundaries** (`check-boundaries.sh`, `Package.swift`): the new library product and target; the
   target's own imports allow-listed to `Foundation`, `FoodLedgerApplication` and `FoodLedgerDomain`;
   a token rule refusing `URLSession`, `URLRequest` and `Network` in it; only the composition root and
   the target's tests import it. Each rule has a self-test fixture that must fail.
10. **Protection.** `swift test` runs on macOS, where `.protectionKey` is unavailable. The store takes an
    injected protection applier (the iOS default sets `FileProtectionType.complete`); the package test
    asserts it is called for every folder and file the store creates. The simulator has no data
    protection (it reports no protection attribute), so the attribute itself is checked only on the
    device. Backup exclusion is inherited from the `WeeklyHealthReport/` root
    (`LocalHealthStorageDirectory.prepare`), and the app test target asserts the store folder sits
    under it and the root reports excluded.
11. **P1c obligations.** The deferred items are listed in section 4 as required P1c contract tests
    and on #424.

Also adopted: the picked file is size-checked against the codec's 26,214,400-byte limit (not the
inventory backup limit) inside security-scoped access; install and remove run one at a time on an
actor; the store is built lazily so the composition root's init never touches protected files while
the phone is locked.

Added contract tests: missing pointer is `none`; undecodable pointer or missing folder is `damaged`;
orphans swept only after a successful commit; an orphan folder of the same release still installs;
same bytes over a damaged release reinstall; remove deletes the pointer first and deletes nothing
while locked; golden pointer and manifest byte-stable; release ID or folder disagreeing with the hash
is `damaged`; each boundary rule fails its fixture; the protection applier covers every path.

## 4. Open points (none blocks P1b)

- **Required P1c contract tests** (deferred from P1b, import v1 sections 3 and 9): the Settings
  "unresolved references" count; re-resolution after remove gives `unavailableTarget`, and after
  re-import succeeds; remove keeps saved logs and their release records with a real database log.

- P1c: the composite's dedupe and the shared `sameSourceRecord` move are specified in section 5 of
  the contract; P1c's gate restates them with the resolver contract suite.

## 5. P1c architecture gate (12 November 2026)

P1c makes Your food database searchable and loggable: import v1 sections 5 (except v12), 6, 7 and 9.
It is written against the code on main at `c55fdad`. Where it refines the contract it says so, and
the contract wins.

**Responsibilities.**

- `GenericRecordResolving` (`FoodLedgerApplication`, consumer-owned port):
  `resolve(_ reference: GenericRecordReference, request: GenericFoodSearchRequest, evidence: [CaptureEvidence]) -> ResolvedGenericRecord?`,
  where the reference is `{source, corpusSHA256, recordID}` and the result is
  `{candidate: PopulatedFoodCandidate, release: SourceRelease}`. It never throws: a hash that differs
  from the adapter's pin, an unknown record or a record of another source returns nil (unresolved).
- Resolvers (`FoodGenericSearch`): CoFID, USDA and TFDA each gain a conformance that builds the
  candidate through the adapter's **own** existing candidate builder (record facts, identity, edible
  quantity and nutrients byte-identical to what its search route returns), binds the request's
  evidence IDs, and sets `CandidateMatchMetadata.methodVersion` to `pfc-resolution-v1` with the
  adapter's own score for the entry's first matched alias. It returns the adapter's own
  `SourceRelease`. A small `GenericRecordResolverSet` dispatches on `source`. Ciqual is out of scope.
- `PersonalFoodDatabaseIndex` (`FoodLedgerApplication`, a final class with a lock): holds the
  decoded active release, loaded lazily from `PersonalFoodDatabaseStoring.activeRelease()` through
  the P1a codec, keyed by release ID. `invalidate()` is called by the Settings flow after every
  install and remove (wired at the composition root). Any store error or decode failure leaves the
  index empty and reports `unavailable`; it never throws into search.
- `PersonalFoodDatabaseFoodSearch` (`FoodLedgerApplication`, conforms to `GenericFoodSearching`):
  matches `GenericFoodSearchRequest.retrievalText` with `GenericFoodRankingPolicy.terms` against
  title, titles and aliases (step 1), variety (step 2) and concept (step 3); the best step wins per
  entry; at most 10 entries. It builds each entry candidate (below) and, for a `candidate` role, the
  resolved generic record as a second row straight after it. No match, an empty or unavailable index,
  or any internal failure returns `.noResult` with **no** guidance and no suggestions.
- `PersonalFoodDatabaseCandidateBuilder` (`FoodLedgerApplication`, pure): entry plus an optional
  resolved `merge` record gives one `PopulatedFoodCandidate` with `sourceReleaseID` the database
  release (`pfc:sha256:…`), `recordID` the entry `id`, item class and identity per section 4.1, edible
  quantity `.known(100 g)` for `per_100_g` and the label basis otherwise, and nutrients per A1
  (below). It also returns the `SourceRelease` set the candidate cites: the database release, each
  cited label release from `sources`, and the merged record's release.
- `GenericFoodMatch` gains `personalDatabase: PersonalFoodDatabaseMatchContext?`
  (`{step: 1...3, isGenericReference: Bool}`), default nil, so every existing match is unchanged.
- `CompositeGenericFoodSearch` gains one init parameter, `databaseSource: (any GenericFoodSearching)? = nil`.
  Its rows join group 0 after the existing default sources and take their v11 place (no v12; the
  version string stays `composite-generic-ranking-v11`, and with no database rows the output is
  byte-identical). Its `noResult` is never taken as the fallback route or for suggestions. After the
  v11 sort and partitions, a record dedupe keeps the first row per `FoodSearchCandidateID` when
  `sameSourceRecord` holds and throws otherwise, before `PopulatedFoodConfirmation` is built.
- `sameSourceRecord` moves from `FoodSearchResultMerger` to one internal function in
  `FoodLedgerApplication` used by both.
- `FoodSearchResultSummary.family`: source ID `personal-food-database` maps to a new
  `.yourFoodDatabase` case ("Your food database"), never `.yourFoods`. Generic-reference rows keep
  their own source's family; "Generic: <name>" is presentation from `personalDatabase`.
- Settings: `PersonalFoodDatabaseSummary` gains `unresolvedReferenceCount`, computed from the index
  with the resolver set; the row shows it when above zero. `installed` gains `replaced: Bool`, so a
  first import says "Your food database was added." and a replacement "was updated.". The footer
  "Food search does not use this file yet." is removed.
- Confirm: when a selected database candidate's nutrients carry more than one `sourceReleaseID`,
  Confirm shows "Nutrients from more than one source", with the per-nutrient source and "automatic
  match" behind details (A1 item 5).

**A1 merge (import v1 section 6), restated for code.**

1. The merge runs only for role `merge`, entry state `raw` or `cooked`, basis `per_100_g`, and a
   resolved record whose known preparation agrees with the entry's (known against known only, the
   same rule as `FoodReresolutionProposal.hasNoKnownContradictions`). The merged candidate takes the
   record's identity for every other facet. Otherwise the record is offered as its own row.
2. Per nutrient, in order: `manual_declaration`; then, for `fresh_whole` only, the generic value;
   then `exact_product_dataset`; then (non-`fresh_whole`) the generic value. Two label values at the
   same level that disagree give `.unknown(.conflictingEvidence)` with both as conflict candidates.
3. States: `manual_declaration` is `.measured` with provenance `{manual_declaration, owner, <owner release>}`;
   `exact_product_dataset` is `.augmented` with its `off:gtin:` record ID; generic values keep the
   resolved record's own `.augmented` provenance unchanged. Every entry passes `NutrientEntry`
   validation; a value that would not is left unknown and counted in a test, never coerced.
4. Transforms: the codec's `salt_to_sodium_v1`, `kj_to_kcal_v1` (both `pasted-label-conversions-v1`)
   and `mass-g-to-mg` / `v1` are carried as `NutrientTransform`s with the printed source value, so
   `NutrientDerivation.isCalculated` gives `calculated: true` for the first two and false for the third.

**Routing and isolation.**

- The database-aware composite is built only for the Add food search view model. The label-estimate
  pool and the food list import keep a composite **without** `databaseSource` (import v1 section 12,
  decision 4); a test pins both.
- Escalation is unchanged. `ConservativeFoodSearchCoverageAssessment` calls a row strong only with
  `reuse`, which a database row never has, so a lexical match never suppresses an online route.
- A locked or damaged store gives `noResult` from the database route only; other sources answer and
  their guidance is shown.

**Saving and records.** No save-path change. The route's `sourceReleases` include every release the
candidate's provenance names, so `FoodConfirmationService` persists them through its existing
`missingReleases` step; the resolution links the database release as today. A new contract test
asserts that every provenance `sourceReleaseID` of a database candidate is in the confirmation's
`sourceReleases`. Re-resolution is unchanged: a database release is never a `FoodReresolutionTarget`,
so any attempt returns `unavailableTarget`; the P1b-deferred tests check that, and that remove keeps
the log and its release records.

**Decision needed (one, with a recommendation).** Import v1 section 7 gives an entry whose values
all come from its merged record the generic-estimate allowance. The code's
`FoodConfirmationPolicy.isGenericEstimate` grants it only when every provenance names the
candidate's **own** release and record, which a database entry never does. Options: (a) keep the
policy unchanged, so such entries ask for the unknown identity facts on Confirm (stricter, no closed
rule touched); (b) extend the policy for this one case. **Recommendation: (a)** for P1c, recorded as
a dated clarification in import v1 section 7; a separate "Generic" row, which is the record's own
candidate, keeps the allowance as today.

**Dependency direction.** Unchanged. The search, builder and index live in Application and depend
on the store port only. Resolvers live in `FoodGenericSearch` beside the corpora. Only the
composition root wires the store, index, resolver set and composites. No new import into Domain;
`check-boundaries.sh` gains a rule that `FoodLedgerApplication`'s database files name no
`FoodGenericSearch` type, with a failing fixture.

**Invariants.** Unknown stays unknown (no title inference, no coercion); no automatic selection or
saving; Confirm stays the only Log path; no network module reachable from the new code; stored
records, archives and exports decode and re-encode unchanged; with no database installed, search
output is identical to today.

**Contract tests (synthetic fixtures only).** Import v1 section 9 minus v12 and Open Food Facts
parity (already covered by P1a), plus: the resolver suite run against all three resolvers; index
invalidation after install and remove; v11 identity with an empty database (the v8 retrieval replay
and `CiqualCompositeContractTests` unchanged); label-estimate pool and list import never see database
rows; the provenance-release-subset test; the Settings unresolved count and the added/updated
wording; the simulator journey of section 9 with a synthetic file.

**Validation.** All `AGENTS.md` gates, plus the FoodSearchQuality replay steps from
`.github/workflows/ios-ci.yml` (FoodQueryEvaluation tests only the parser and is unaffected, but is
run as CI does).

### 5.1 Changes from the architecture-gate review (12 November 2026)

Verdict PASS WITH CHANGES. Each change binds P1c and overrides looser wording in section 5.

1. **Re-resolution.** A `PersonalFoodDatabaseReresolutionProvider` implements the existing
   `FoodReresolutionProviding`: its only target is the active database release with method
   `pfc-resolution-v1`; `candidates(for:target:at:)` looks up the saved log's `recordID` (the entry
   `id`) in the index and rebuilds the candidate through the same builder. After remove there is no
   target, so the service returns `unavailableTarget`; after re-import of a file holding that entry
   it succeeds. The composition root adds it beside `CoFIDReresolutionProvider`.
2. **Merge condition.** A record merges only if its preparation kind is **known** and equals the
   entry's (`raw` or `cooked`), the kind alone is compared (a cooked entry has no method, so a record
   with a cooking method still merges, and its method is kept), and the record's serving basis is
   per 100 g with a known 100 g edible quantity. Anything else becomes its own row.
3. **No nutrition data.** In P1c an entry is left out of results when no nutrient would be known
   (no label values and no resolved `merge` record), so no log can reach the export's
   `unattributedEntry` path. The "No nutrition data yet" row with its fallback chain is deferred to a
   later phase as a dated note in import v1 section 5; a test pins the omission.
4. **Dedupe under v11.** The dedupe runs only on a pair where one row came from the database route.
   The database copy is kept (with its `personalDatabase` context and `pfc-resolution-v1` metadata),
   at the position of whichever copy sorted first; the other is dropped when `sameSourceRecord`
   holds and the search throws otherwise. Rows from existing sources are never deduped. "Straight
   after its entry" holds within the database route only.
5. **Group.** The composite places the database route at a fixed index ahead of the regional and
   reference routes and assigns it group 0 explicitly, leaving the regional and reference indices and
   groups as today; a test pins this with regional rows both deferred and promoted.
6. **Exact name and order.** A database entry row is `isExactName` when the folded query terms equal
   the folded title or one alias at step 1; a Generic row uses its adapter's own rule. Within the
   route, entries are ordered by step, then `GenericFoodRankingPolicy.preference`, then entry `id`;
   at most 10 entries (up to 20 rows). The route never sets `reuse`.
7. **Index concurrency.** The index is warmed off the main thread at launch, after every install and
   remove, and on `protectedDataDidBecomeAvailable`. Search reads the current snapshot under a short
   lock and never waits for a load (no database rows until warm). A generation counter discards a
   load that finishes after `invalidate()`. A `locked` result is never cached; `damaged` is cached
   until the next invalidation.
8. **Resolver port.** `resolve(_ reference:, evidenceIDs:, queryAlias:) -> ResolvedGenericRecord?`
   and `contains(_ reference:) -> Bool` for the Settings count. The pins checked are
   `CoFIDGenericFoodSearch.corpusCanonicalSHA256`, `USDAGenericFoodSearch.corpusSHA256` and
   `TFDAGenericFoodSearch.corpusSHA256`. `PersonalFoodDatabaseReferenceCount` computes the count in
   the index's background warm-up; Settings reads it with the summary.
9. **Label provenance.** `manual_declaration`: `sourceID` `owner`, `sourceReleaseID` the `owner:`
   release, `recordID` nil. `exact_product_dataset`: `sourceID` `open-food-facts`, `sourceReleaseID`
   the `pfc-off:` release, `recordID` `off:gtin:…`. Both: `manifestReference`
   `<database release ID>#<entry id>`, never a title, brand or name. A test checks the saved log's
   food export carries only opaque IDs.
10. **Identity and basis.** Item class is `.drink` for category `beverage` or `alcohol`, otherwise
    `.food`; never water, fortified food or supplement; fortification unknown. `per_100_g` gives
    serving basis per 100 g and edible quantity `.known(100 g)`; `per_100_ml_as_labelled` gives per
    100 mL and `.known(100 mL)`, and never merges.
11. **Open Food Facts parity** is a P1c test (plan section 2.1 item 6): the skill's
    `test_off_rules.py` cases against `OpenFoodFactsLookup.project`.
12. **Boundary rules.** Replace the redundant rule with two that bite, each with a failing fixture:
    `FoodLedgerApplication`'s `PersonalFoodDatabase*` files name no `FileManager`, `URLSession`,
    `URLRequest` or `contentsOf:`; the resolver files in `FoodGenericSearch` name no URL-loading token.
13. **A1 amendment rows** are added in this change to `unified-food-search-contract-v1.md` and to
    section 8 of `food-identity-nutrition-contract.md`, dated and citing import v1 section 6.

Adopted suggestions: one shared set of CoFID, USDA, TFDA and Ciqual instances feeds both composites
and the resolver set; `personal-food-database` is checked first in `FoodSearchResultSummary.family`;
the golden fixture's Chinese title is tested for step-1 matching.

Added contract tests are those listed in the review: refused merges (unknown preparation, per
100 mL record, other states), the pinned no-conflict case plus the builder's conflict branch, the
no-data omission, the three dedupe cases, the group pin, deterministic order, the four index cases,
evidence parity when the database route answers first, label provenance fields, the per-100 mL
basis, re-resolution after remove and re-import, a logged Generic row re-resolving as a CoFID log
does, Open Food Facts parity, the isolated composites, resolver-versus-route facts for all three
resolvers, and the boundary fixtures.

**Owner decision (12 November 2026):** option (a), the stricter path. It is a rule change, recorded
as a dated amendment in import v1 section 7 with the owner's approval of the same day.
