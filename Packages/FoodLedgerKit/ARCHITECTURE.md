# FoodLedgerKit architecture gate

Issue #108 introduces a local ledger without capture UI, providers, Drive,
HealthKit writes, background work or personal data.

## Responsibilities and dependency direction

- `FoodLedgerDomain` owns immutable values, typed identities, validation, the v1
  nutrient algebra and catalogue, identity compatibility, provenance and conflict
  semantics. It uses Foundation value facilities only.
- `FoodLedgerApplication` owns commands and transaction orchestration. It depends
  on the domain and consumer-owned capabilities for command commit/ledger reads,
  attachments and source-release installation. Clocks, identifiers, canonical
  encoding and hashing are injected.
- `FoodLedgerGRDB` owns schema, migrations, private database records, file
  protection, SQLite policy and domain mapping. It is the only target that imports
  GRDB or handles database identifiers.
- `FoodLedgerTestSupport` supplies the in-memory adapter used by the same contract
  suite as the temporary-file GRDB adapter.

Dependencies point inward:

```text
FoodLedgerDomain <- FoodLedgerApplication <- FoodLedgerGRDB
                                    ^
                                    `- FoodLedgerTestSupport
```

SwiftPM target dependencies prevent the domain from seeing either application or
infrastructure modules. Import guards provide a second, explicit CI check.

## Closed invariants

These are intentionally not extension points: the four nutrient states; the
ordered 39-key v1 catalogue and canonical units; unknown not being zero; bounds
not being exact scalars; finite quantities and valid bases; lowercase UUID entity
and version identities; immutable evidence/version history; mandatory identity
contradictions; provenance; atomic query-row plus operation commits; actor
sequence/hash validation; idempotency; and conflict preservation. A change needs
an explicit contract and schema version.

Nutrient provenance retains the original source value, unit and basis plus named,
versioned transformations. Exact outputs cannot conceal bounded source values.
Unknown decisive identity or edible quantity blocks candidate selection, and
version lineage cannot cross a stable entity. These rules are validated by domain
construction and decoding, then reinforced by adapter reference checks and SQLite
foreign keys/triggers.

## Credible extension axes

Provider-neutral capture/candidate inputs admit later barcode, OCR and search
adapters. Candidate ranking and compatibility policies may add source-specific
rules only after the domain's hard contradictions. Projections, attachment stores,
source installers and persistence adapters are replaceable capabilities. Versioned
operation kinds are admitted through an injected supported-operation registry;
stored operations are authenticated from their original canonical bytes rather
than decoded as the current command type, and unregistered kinds fail closed.
Adding one of these extensions does not change settled domain entities or GRDB
schema code.

## Capability ports and behavioural contracts

The application exposes cohesive command/reading, attachment and source-release
capabilities rather than an all-purpose repository or one protocol per method.
The shared store contract suite runs unchanged against in-memory and GRDB
implementations. It covers atomicity, idempotency, immutable-row rejection,
actor-chain failure, conflict preservation, fail-closed errors, attachment
rollback, source releases, reformulation, corrections, quantity/plate versions,
and bounded/unknown nutrients. Domain tests cover all public validation paths, and
an adapter-substitution test proves a synthetic capture producer can be added
without modifying Domain or GRDB production code.

The GRDB adapter normalises evidence, assertion, source-release, candidate and
component references into foreign-keyed link tables. One `DatabaseQueue` commits
immutable/version rows and the append-only operation envelope in one transaction.
Protected-data availability is checked for every operation; open also validates
application/schema identity, migrations, foreign keys, integrity, stored payloads
and actor chains. Content-addressed attachments are written before the database
transaction and removed if that transaction fails; callers cannot submit an
attachment descriptor through the generic commit path.

Privacy purge is deliberately not exposed by this package. Issue #108 excludes
personal-data handling, so immutable update/delete triggers remain unconditional;
a future purge requires a separately authorised and tested capability rather than
an adapter escape hatch.
