# Food library storage, versioning and backup decision

Status: proposed decision for issue
[#90](https://github.com/syamaner/WeeklyHealthReport/issues/90), 20 September
2026. This document selects the persistence and recovery protocol for later
implementation. It does not add a database dependency, change the app, contact
Google Drive, alter OAuth, or export personal food data.

This decision consumes the normative
[`food-identity-nutrition-contract.md`](food-identity-nutrition-contract.md) and
the accepted [`food-log-ux-design-plan.md`](food-log-ux-design-plan.md). If this
document conflicts with either contract's identity, evidence, nutrient-state or
interaction rules, those earlier contracts win.

## 1. Decision summary

The food ledger will use:

1. **SQLite behind a narrow repository protocol**, implemented with a reviewed,
   exact-tag Swift Package Manager dependency on GRDB when the first storage slice
   is authorised.
2. **One serialized database writer** using `DatabaseQueue` and SQLite's rollback
   journal for v1. WAL is not required for the single-user foreground workload.
3. **Normalized immutable/version tables plus an append-only operation log** in the
   same transaction. The tables are the queryable materialization; the operation
   log is the merge, retry and audit boundary.
4. **Content-addressed local attachments** for retained source images. Raw images,
   OCR geometry, credentials and transient provider data remain outside canonical
   backup payloads.
5. **Immutable, deterministic backup generations** containing a manifest, compact
   ledger snapshot and later operations. Drive is an explicit user-triggered copy
   destination, never the live database.
6. **Import into a staging store, validate, then merge**. No backup ever replaces
   the live store merely because it is newer.
7. **Conflict preservation and explicit adjudication**. Concurrent edits never use
   last-write-wins; a user decision creates another immutable version.

This is deliberately not a universal storage framework. It is a food-ledger store
with pure domain inputs/outputs and a replaceable persistence adapter.

## 2. Why SQLite with GRDB

The app targets iOS 17, so SwiftData is available. Apple's `ModelContainer`
coordinates storage and supports automatic or planned migrations, but it owns the
object-store representation and migration machinery. That is useful for ordinary
app models, but it is a poor fit for this ledger's requirements to inspect exact
transactions, enforce append-only tables, import operations idempotently, construct
deterministic snapshots and prove merge behaviour independently of an object graph.

SQLite provides explicit transactions, constraints and indexes. SQLite documents
that reads and writes occur inside transactions and that only one write transaction
is active at a time. Foreign-key enforcement must be enabled on every connection,
so the store will assert `PRAGMA foreign_keys = ON` at open and test it rather than
assuming a default.

GRDB is selected over a hand-written SQLite C wrapper because it retains SQL and
transaction visibility while providing Swift value binding, migrations, typed
records and testable queue ownership. It is MIT licensed and distributed by Swift
Package Manager. The implementation issue must pin one reviewed exact release and
record its licence and checksum in the dependency inventory; a floating branch or
unbounded version range is not acceptable.

### Option comparison

| Option | Strengths | Rejection reason for this ledger |
| --- | --- | --- |
| One canonical JSON file | Smallest dependency surface; easy to inspect | Whole-document rewrites, weak indexed lookup, awkward transactional attachment/version updates, and unsafe merge pressure as records grow |
| SwiftData | Apple-native, iOS 17 baseline, relationships and migration plans | Store/migration details are less explicit than the required operation, integrity and deterministic-import boundaries |
| Core Data | Mature Apple framework with transactions and migrations | Adds object-graph complexity without improving deterministic operation exchange or canonical JSON control |
| Raw SQLite C API | Maximum control and no external dependency | Reimplements binding, error translation, migrations and concurrency safety that a narrow reviewed library already supplies |
| SQLite through GRDB | Explicit schema/transactions, constrained migrations, testable serialized access, SPM distribution | Adds one dependency; accepted with exact pinning, licence inventory and isolation behind repository protocols |

The decision dimensions are explicit:

| Option | Atomic multi-record save | Controlled migration | Indexed lookup | Deterministic backup/merge | Isolated tests |
| --- | --- | --- | --- | --- | --- |
| Canonical JSON file | Weak as the document grows | Explicit but whole-file | In-memory/rebuilt | Inspectable, but merge becomes whole-document logic | Good at small scale |
| SwiftData | Yes through model context | Automatic/custom plans | Framework-managed | Requires a separate operation/interchange layer | Good, but coupled to model containers |
| Core Data | Yes | Mature mapping/custom migration | Framework-managed | Requires a separate operation/interchange layer | Good, but object-graph heavy |
| Raw SQLite | Yes | Fully explicit | Fully explicit | Fully explicit | Good with substantial wrapper work |
| SQLite/GRDB | Yes | Named SQL/Swift migrations | Fully explicit | Fully explicit with the selected operation layer | Strong in-memory and temporary-file adapters |

## 3. Database and filesystem boundary

The root is:

```text
Application Support/WeeklyHealthReport/FoodLedger/
  food-ledger-v1.sqlite
  Attachments/v1/<first-two-sha256>/<sha256>
  Datasets/<source_release_id>/manifest.json
  Datasets/<source_release_id>/records...
  SearchIndexes/<source_release_id>/...
  ImportStaging/...
```

The directory, database, journal, attachments, manifests and staging files use
`FileProtectionType.complete`. Apple's complete protection makes files unavailable
while the device is locked; a protected-data error is not treated as an empty or
missing ledger. The existing daily-notes store already follows that fail-closed
pattern.

`Application Support` is used because Apple defines it as the sandboxed location
for application support/configuration data. Search indexes are rebuildable caches.
They are excluded from backup and may be deleted without deleting ledger truth.

Raw retained images are content-addressed by SHA-256. The database stores the hash,
media kind, size, protection/retention state and relative attachment path. It never
stores an absolute sandbox path. Writing evidence is:

1. write a protected temporary file without overwriting;
2. verify byte count and hash;
3. move it to its content-addressed location;
4. commit the evidence record and operation in one database transaction; and
5. remove an unreferenced file after rollback or later garbage collection.

The inverse order is prohibited because a committed evidence reference must never
point at bytes that were not durably verified.

## 4. SQLite operating policy

- Use one `DatabaseQueue` and one application process writer in v1.
- Use the rollback journal (`journal_mode=DELETE`) rather than WAL.
- Enable and assert `foreign_keys=ON` on every connection.
- Use explicit write transactions for every domain command.
- Use `synchronous=FULL` unless a measured implementation spike proves an equally
  safe Apple-platform setting; performance is not assumed to justify weaker
  durability.
- Set and check `application_id`, `user_version` and a ledger metadata row.
- Run `quick_check` on normal open after an unclean shutdown and `integrity_check`
  before export, after staging import and during diagnostics.
- Fail closed on unknown schema versions, failed migrations, constraint errors or
  integrity failures. Never erase or recreate automatically.

SQLite WAL would add `-wal` and `-shm` files and checkpoint behaviour to every
snapshot boundary. SQLite's current documentation also records a WAL-reset race
affecting older SQLite releases when multiple connections write/checkpoint
concurrently. The v1 workload does not need concurrent writers, so rollback journal
plus a serialized queue is simpler and avoids relying on the OS SQLite patch level.
WAL may be reconsidered only with an exact runtime SQLite inventory and a measured
need.

## 5. Logical schema

The storage adapter preserves the stable/version identifiers and minimum fields in
contract v1. The exact SQL belongs to an implementation issue, but these table
families are fixed:

### Immutable evidence and domain versions

- `capture_evidence`
- `user_assertion`
- `product` and `product_version`
- `library_entry` and `library_entry_version`
- `log_item` and `log_item_version`
- `resolution` and `resolution_version`
- `resolution_nutrient`
- `daily_summary_version` and `daily_summary_nutrient`
- `quantity_conversion_version`
- `plate` and `plate_weight_version`
- `candidate_decision`
- `conflict` and `conflict_adjudication`

Stable entity rows contain only identity and creation facts. Version rows are
insert-only. Foreign keys use version IDs, never human ordinals. An update or
delete trigger rejects changes to immutable tables outside the separately tested
privacy-purge command.

An integer ordinal is monotonic but not a foreign key. Concurrent devices may both
produce the same next ordinal; `(stable_id, ordinal, version_id)` remains
unambiguous. A later adjudicated version uses `max(seen ordinal) + 1` and cites the
conflict record containing every competing version ID.

### Source releases

- `source_release`
- `source_record_reference`
- `source_installation`

Source datasets are installed side-by-side under immutable `source_release_id`
directories. The manifest contains source/licence identity, byte hashes, schema and
pipeline versions. A new CoFID or other admitted release never mutates the old
directory. Resolution versions continue to cite the exact old release.

### Operation and snapshot metadata

- `ledger_actor`
- `ledger_operation`
- `snapshot_watermark`
- `backup_generation`
- `import_receipt`
- `purge_tombstone`

The query tables and operation row are written in the same transaction. A domain
mutation is successful only when both commit.

## 6. Operation log

Each installation has an opaque `actor_id` generated once and stored with the
ledger. Each operation contains:

- globally unique `operation_id`;
- `actor_id` and strictly increasing `actor_sequence`;
- operation schema/type and creation instant;
- affected stable and version IDs;
- canonical JSON payload or payload reference;
- previous operation hash for that actor;
- SHA-256 of the canonical operation bytes; and
- optional command/idempotency key.

The actor hash chain detects missing, reordered or altered operations inside one
actor stream; it is integrity evidence, not authentication or encryption.

Replay/import rules are:

1. An unseen `operation_id` is validated and applied in one transaction.
2. A seen ID with the same hash is an idempotent no-op.
3. A seen ID with a different hash is corruption and blocks the import.
4. A sequence gap or previous-hash mismatch blocks that actor stream.
5. Applying an operation never overwrites an immutable version.
6. A valid competing successor records a conflict rather than selecting by time,
   device, sequence or import order.

UI drafts and transient scans are not ledger operations until the user confirms a
domain command. OCR/search candidates and rejected candidates become operations
only when the accepted retention contract requires them for the decision record.

## 7. Deterministic snapshot and backup generation

A backup is an immutable generation, not a copied live SQLite file. Although
SQLite provides an online backup API for point-in-time database copies, a raw
database copy would expose storage layout as the long-term interchange contract.
The food backup instead uses canonical domain records and operations.

The generation is a deterministic archive with:

```text
manifest.json
snapshot.json
operations.ndjson
```

`manifest.json` contains:

- backup-format and food-contract versions;
- ledger/dataset ID and immutable snapshot ID;
- created-at and creating actor (metadata only, not ordering authority);
- schema version and migration identifiers;
- source-release IDs;
- per-actor compact-snapshot base and frozen end sequence/hash watermarks;
- record/operation counts;
- deterministic filename, byte count and SHA-256 for every member; and
- whether raw attachments are omitted (always `true` in v1).

`snapshot.json` is the compact, sorted projection at a verified base watermark at
or before the frozen backup boundary. `operations.ndjson` contains every operation
after that base and through the frozen end watermarks in
`(actor_id, actor_sequence, operation_id)` order. A first backup may use an empty
genesis snapshot plus all operations; a later verified compaction may advance the
base. JSON uses UTF-8, sorted object keys, fixed field ordering where arrays are
semantic, stable ISO 8601 formatting and no locale-sensitive numbers.

Snapshot creation:

1. starts a read transaction and freezes end watermarks;
2. selects a verified compact base no later than those end watermarks;
3. validates database integrity and source manifests;
4. produces the base snapshot and following operations into a protected staging
   directory;
5. hashes and re-reads every data member;
6. writes the manifest last;
7. reopens and validates the entire archive; and
8. records the completed generation locally.

An interrupted generation is incomplete and never offered for restore or upload.
Creating the same base/end generation must produce the same `snapshot.json` and
`operations.ndjson` hashes and the same snapshot ID. The manifest may carry a new
packaging time, and the archive container may have other non-semantic packaging
metadata; the data-member hashes, ledger ID, base/end watermarks and snapshot ID
are the content identity.

## 8. Explicit Drive backup protocol

Drive backup remains manual and uses the existing narrow `drive.file` account and
destination boundary only after a later implementation issue explicitly authorises
transport. #90 makes no provider call.

The first transport slice uploads one immutable archive per confirmed generation:

```text
food-ledger-<ledger-id>-<snapshot-id>.whrfoodbackup
```

The coordinator must:

1. freeze and validate the local generation before destination selection;
2. reserve/persist the Drive file ID before first create;
3. retry an uncertain create with the same ID;
4. read back by ID and verify exact bytes/hash before reporting success; and
5. retain the local verified receipt with account, folder, file ID, generation and
   hash, without storing OAuth credentials in the ledger.

No mutable “latest” file is authoritative. Listing or filename search may help the
user discover app-created backups but cannot establish identity. A newer backup
does not automatically delete an older one. Retention/deletion is explicit.

The archive excludes raw label images, OCR geometry, scanner frames, audio,
credentials, Keychain data, transient diagnostics and search indexes. It contains
personal food/log data. SHA-256 proves integrity, not secrecy or anonymity; the UI
must say that before upload. Client-side backup encryption would require a separate
key-recovery contract and is not silently inferred here.

## 9. Restore and merge

Restore never opens an archive as the live database. It:

1. obtains an explicitly selected local/Drive file;
2. verifies the whole manifest and supported versions before decoding records;
3. imports into a newly created protected staging database;
4. checks hashes, actor chains, constraints, source releases and full integrity;
5. computes a dry-run merge report against the live ledger;
6. asks the user to resolve blocking semantic conflicts; and
7. applies accepted operations to the live ledger in one bounded transaction or
   leaves it unchanged.

If the archive is corrupt, incomplete, uses an unsupported newer major version or
has an actor-chain gap, it is quarantined read-only and the live ledger is untouched.
If a known older backup format has a migration, the original archive/hash is
retained and the migration produces a new staging generation; no archive is edited
in place.

### Required merge examples

#### Independent new logs

Operations have different IDs and entity IDs. Import unions them. Derived daily
summaries are regenerated from the exact merged input versions; imported summaries
are evidence for comparison, not blindly retained as current.

#### Same-product concurrent edits

Both product versions are retained. If they descend from the same earlier version
and neither cites the other, the materialized product has a blocking conflict. The
user selects one, keeps both as distinct products, or creates a new adjudicated
version. Import time and actor ID never pick a winner.

#### Reformulation

A changed nutrient panel or decisive formulation state creates another product
version. Old logs remain linked to the old version. If chronology is not evidenced,
the versions coexist and new logging requires confirmation rather than silently
moving old or new logs.

#### Resolution correction

The correction adds an assertion and a resolution version. The original resolution
and original/effective resolution IDs remain reproducible. If concurrent
corrections disagree at the same precedence, affected nutrients are conflict/
`unknown` until adjudication creates another version.

#### Dataset re-resolution

A new dataset release installs beside the old release. Proposed results cite the
new release and algorithm version but are not effective until the later #101 policy
permits and confirms them. Importing a proposal never rewrites historical logs.

#### Plate and quantity overrides

A plate weight, serving conversion or quantity correction is an immutable version.
Old log versions retain the conversion they used. Concurrent changes produce an
explicit choice on the next use; they do not rewrite earlier edible quantities.

## 10. Retry and conflict policy

| Operation | Safe retry key | Result |
| --- | --- | --- |
| Local domain command before commit | command/idempotency ID | Same committed operation or no mutation |
| Backup generation | snapshot ID | Same member hashes or corruption failure |
| Drive create after uncertain response | reserved Drive file ID | Reconcile/read back; never allocate a replacement merely because response was lost |
| Import/replay | operation ID + hash | Identical no-op; divergent duplicate blocks |
| Independent additions | operation IDs | Union |
| Competing entity versions | version IDs + shared ancestry | Preserve both and create conflict |
| Conflict resolution | new assertion/version operation | Explicit user-authored successor; no deletion of alternatives |

## 11. Deletion and privacy

Normal “remove from favourites/library” is a new library-entry version or tombstone;
it does not erase historical evidence or logs.

Two destructive actions are separate:

- **Delete retained attachment:** remove raw local bytes after checking references;
  retain the evidence descriptor, byte hash and a minimal deletion tombstone so a
  later backup cannot silently resurrect it.
- **Delete all local food data:** require explicit confirmation, close the store,
  remove the database/journal/attachments/staging directories, create a new
  `ledger_id`, and report that Drive backups are separate copies that require their
  own explicit deletion.

A selective permanent deletion that would break referenced log/version integrity is
not included in v1. It requires a separate redaction/tombstone contract and fixtures.
The app must not claim that deleting local data deleted an existing Drive backup,
iOS device backup or independently exported archive.

## 12. Corruption and recovery

- Protected-data unavailability is a locked state, not “no data”.
- A decode, constraint, migration or integrity failure never triggers automatic
  recreation.
- Preserve the original file read-only, record a privacy-safe diagnostic code and
  offer restore/import only from a separately validated generation.
- If the last transaction failed, rely on SQLite rollback recovery, then validate.
- If an attachment is missing, preserve its descriptor/hash and mark the media
  unavailable; do not delete the evidence/domain records or fabricate OCR values.
- If an installed dataset fails its manifest hash, disable that release and every
  new resolution requiring it. Existing resolutions remain readable with an
  explicit source-unavailable diagnostic.
- Recovery never fetches a provider or Drive automatically.

## 13. Migrations

Migrations are ordered, named and one-way. Every shipped schema remains represented
by fixtures. A migration runs on a protected copy/staging database, validates the
result, then replaces the live store only after success; the last good store remains
available for recovery until the replacement is complete.

No migration may:

- rewrite original evidence;
- turn `unknown` into zero or `bounded` into exact;
- collapse product and resolution identity;
- renumber IDs or use ordinals as foreign keys;
- select a conflict winner; or
- delete an old source release still referenced by a resolution.

## 14. Implementation acceptance for later slices

Before the storage slice is accepted, synthetic tests must prove:

- transactional entity-version plus operation insertion;
- immutable-table update rejection;
- foreign-key enablement on open;
- retry idempotency and divergent duplicate rejection;
- actor-chain gap/reorder/tamper detection;
- deterministic snapshot member hashes;
- interrupted snapshot and corrupt manifest rejection;
- side-by-side source-release installation;
- every merge example in section 9;
- locked-device/protected-data fail-closed behaviour;
- migration success, rollback and unsupported-newer-schema refusal;
- attachment write failure without dangling evidence;
- local purge without claiming remote deletion; and
- canonical food JSON equality before and after backup round-trip.

The first implementation PR must add GRDB only to the food persistence boundary,
pin the reviewed release, inventory the licence and run package-isolation/build
checks. It must not add Drive transport, OCR, provider calls, HealthKit writes or UI
outside its bounded child issue.

## 15. Consequences for the epic

- #90 can close once this decision is accepted and merged.
- #94 remains a phase container and can then be decomposed.
- The first child should implement pure food-domain commands plus the local store,
  operation log and in-memory/file-backed test adapters; no route UI is required.
- Barcode, label OCR (#93) and generic search (#98) consume the same candidate,
  assertion, quantity, plate and confirmation records.
- Drive backup transport remains a later explicit slice even though its archive and
  merge semantics are fixed here.

## Sources checked

- [Apple: ModelContainer and migration plans](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [Apple: Application Support directory](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory)
- [Apple: complete file protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/complete)
- [SQLite: transactions](https://www.sqlite.org/lang_transaction.html)
- [SQLite: foreign keys](https://www.sqlite.org/foreignkeys.html)
- [SQLite: write-ahead logging](https://www.sqlite.org/wal.html)
- [SQLite: online backup API](https://www.sqlite.org/backup.html)
- [GRDB repository and licence](https://github.com/groue/GRDB.swift)
- [GRDB migrations](https://github.com/groue/GRDB.swift/blob/master/GRDB/Migration/DatabaseMigrator.swift)
