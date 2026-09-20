import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import GRDB

public struct ProtectedDataAvailability: Sendable {
    private let check: @Sendable () -> Bool

    public init(check: @escaping @Sendable () -> Bool) {
        self.check = check
    }

    public func requireAvailable() throws {
        guard check() else { throw FoodLedgerStoreError.protectedDataUnavailable }
    }

    public static let available = ProtectedDataAvailability { true }
}

public final class FoodLedgerGRDBStore: LedgerCommandCommitting, LedgerReading, FoodConfirmationReading,
    EvidenceAttachmentStoring, FoodArchiveLedgerAccess, @unchecked Sendable
{
    public static let schemaVersion = 1
    public static let applicationID = 0x5748_5246 // WHRF

    private let databaseQueue: DatabaseQueue
    private let encoder: any CanonicalEncoding
    private let decoder: JSONDecoder
    private let digester: any Digesting
    private let verifier: OperationVerifier
    private let operationRegistry: LedgerOperationRegistry
    private let attachmentsRoot: URL
    private let protectedData: ProtectedDataAvailability

    public init(
        databaseURL: URL,
        attachmentsRoot: URL? = nil,
        protectedData: ProtectedDataAvailability = .available,
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
        digester: any Digesting = SHA256Digester(),
        operationRegistry: LedgerOperationRegistry = .builtInV1
    ) throws {
        try protectedData.requireAvailable()
        self.encoder = encoder
        self.digester = digester
        self.protectedData = protectedData
        self.operationRegistry = operationRegistry
        verifier = OperationVerifier(
            encoder: encoder,
            digester: digester,
            operationRegistry: operationRegistry
        )
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.attachmentsRoot = attachmentsRoot
            ?? databaseURL.deletingLastPathComponent().appendingPathComponent("Attachments/v1")

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.applyCompleteProtection(to: databaseURL.deletingLastPathComponent())

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
            try db.execute(sql: "PRAGMA synchronous = FULL")
        }

        do {
            databaseQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        } catch {
            throw FoodLedgerStoreError.corruptStore
        }
        try Self.validatePreMigrationIdentity(databaseQueue)
        do {
            try Self.migrator.migrate(databaseQueue)
        } catch {
            throw FoodLedgerStoreError.migrationFailed(String(describing: error))
        }
        try Self.validateOpenPolicy(databaseQueue)
        try validateStoredLedger()
        try Self.applyCompleteProtection(to: databaseURL)
    }

    public static func temporary(
        directory: URL,
        protectedData: ProtectedDataAvailability = .available,
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
        digester: any Digesting = SHA256Digester(),
        operationRegistry: LedgerOperationRegistry = .builtInV1
    ) throws -> FoodLedgerGRDBStore {
        try FoodLedgerGRDBStore(
            databaseURL: directory.appendingPathComponent("food-ledger-v1.sqlite"),
            attachmentsRoot: directory.appendingPathComponent("Attachments/v1"),
            protectedData: protectedData,
            encoder: encoder,
            digester: digester,
            operationRegistry: operationRegistry
        )
    }

    public func actorHead(for actorID: ActorID) throws -> ActorHead {
        try protectedData.requireAvailable()
        return try databaseQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT sequence, operation_hash FROM ledger_actor WHERE actor_id = ?",
                arguments: [actorID.rawValue]
            ) else {
                return ActorHead(sequence: 0, operationHash: nil)
            }
            return ActorHead(
                sequence: row["sequence"],
                operationHash: try SHA256Digest(row["operation_hash"])
            )
        }
    }

    public func operation(id: OperationID) throws -> LedgerOperation? {
        try protectedData.requireAvailable()
        return try databaseQueue.read { db in
            try fetchOperation(db, id: id.rawValue)
        }
    }

    public func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome {
        try protectedData.requireAvailable()
        try verifier.verify(transaction)
        return try write { try commit(transaction, db: $0) }
    }

    public func commitAtomically(_ transactions: [LedgerTransaction]) throws -> [CommitOutcome] {
        try protectedData.requireAvailable()
        for transaction in transactions { try verifier.verify(transaction) }
        return try write { db in
            try transactions.map { try commit($0, db: db) }
        }
    }

    public func archiveState() throws -> FoodArchiveState {
        try protectedData.requireAvailable()
        return try databaseQueue.read { db in
            func values<Value: Decodable>(_ type: Value.Type, table: String) throws -> [Value] {
                let rows = try Row.fetchAll(db, sql: "SELECT payload FROM \(table) ORDER BY 1")
                return try rows.map { try decoder.decode(type, from: $0["payload"]) }
            }
            let operationRows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM ledger_operation ORDER BY actor_id, actor_sequence, operation_id"
            )
            return FoodArchiveState(
                records: LedgerMutation(
                    evidence: try values(CaptureEvidence.self, table: "capture_evidence"),
                    assertions: try values(UserAssertion.self, table: "user_assertion"),
                    products: try values(Product.self, table: "product"),
                    productVersions: try values(ProductVersion.self, table: "product_version"),
                    libraryEntries: try values(LibraryEntry.self, table: "library_entry"),
                    libraryEntryVersions: try values(LibraryEntryVersion.self, table: "library_entry_version"),
                    resolutions: try values(NutritionResolution.self, table: "resolution"),
                    resolutionVersions: try values(NutritionResolutionVersion.self, table: "resolution_version"),
                    logItems: try values(LogItem.self, table: "log_item"),
                    logItemVersions: try values(LogItemVersion.self, table: "log_item_version"),
                    quantityConversions: try values(QuantityConversionVersion.self, table: "quantity_conversion_version"),
                    plates: try values(Plate.self, table: "plate"),
                    plateWeightVersions: try values(PlateWeightVersion.self, table: "plate_weight_version"),
                    candidateDecisions: try values(CandidateDecision.self, table: "candidate_decision"),
                    conflicts: try values(LedgerConflict.self, table: "conflict"),
                    sourceReleases: try values(SourceRelease.self, table: "source_release"),
                    sourceInstallations: try values(SourceInstallation.self, table: "source_installation")
                ),
                operations: try operationRows.map {
                    try OperationRecord(row: $0).operation(registry: operationRegistry)
                }
            )
        }
    }

    private func commit(_ transaction: LedgerTransaction, db: Database) throws -> CommitOutcome {
        if let existing = try fetchOperation(db, id: transaction.operation.operationID.rawValue) {
            guard existing.operationHash == transaction.operation.operationHash else {
                throw FoodLedgerStoreError.divergentDuplicateOperation
            }
            return .idempotent(existing)
        }
        let head = try Self.fetchActorHead(db, actorID: transaction.operation.actorID)
        guard transaction.operation.actorSequence == head.sequence + 1 else {
            throw FoodLedgerStoreError.actorSequenceMismatch
        }
        guard transaction.operation.previousOperationHash == head.operationHash else {
            throw FoodLedgerStoreError.actorHashMismatch
        }
        try insert(transaction.mutation, db: db)
        let record = try OperationRecord(operation: transaction.operation)
        try db.execute(
            sql: """
                INSERT INTO ledger_operation(
                    operation_id, actor_id, actor_sequence, operation_type, created_at,
                    affected_ids, payload, payload_hash, previous_operation_hash,
                    operation_hash, idempotency_key
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                record.operationID, record.actorID, record.actorSequence,
                record.operationType, record.createdAt, record.affectedIDs,
                record.payload, record.payloadHash, record.previousOperationHash,
                record.operationHash, record.idempotencyKey
            ]
        )
        try db.execute(
            sql: """
                INSERT INTO ledger_actor(actor_id, sequence, operation_hash)
                VALUES (?, ?, ?)
                ON CONFLICT(actor_id) DO UPDATE SET
                    sequence = excluded.sequence,
                    operation_hash = excluded.operation_hash
                """,
            arguments: [
                transaction.operation.actorID.rawValue,
                transaction.operation.actorSequence,
                transaction.operation.operationHash.value
            ]
        )
        return .committed(transaction.operation)
    }

    private func write<Value>(_ body: (Database) throws -> Value) throws -> Value {
        do {
            return try databaseQueue.write(body)
        } catch let error as FoodLedgerStoreError {
            throw error
        } catch let error as DatabaseError {
            if error.extendedResultCode == .SQLITE_CONSTRAINT_PRIMARYKEY
                || error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE
                || error.message?.contains("immutable") == true {
                throw FoodLedgerStoreError.immutableRecord(error.message ?? "immutable row")
            }
            if error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY {
                throw FoodLedgerStoreError.missingReference(error.message ?? "foreign key")
            }
            throw FoodLedgerStoreError.integrityFailure(error.message ?? "database constraint")
        } catch {
            throw FoodLedgerStoreError.integrityFailure(String(describing: error))
        }
    }

    public func counts() throws -> LedgerCounts {
        try protectedData.requireAvailable()
        return try databaseQueue.read { db in
            LedgerCounts(
                evidence: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM capture_evidence") ?? 0,
                productVersions: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM product_version") ?? 0,
                resolutionVersions: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM resolution_version") ?? 0,
                logItemVersions: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM log_item_version") ?? 0,
                conflicts: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM conflict") ?? 0,
                operations: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_operation") ?? 0
            )
        }
    }

    public func productVersions(productID: ProductID) throws -> [ProductVersion] {
        try protectedData.requireAvailable()
        return try decodeRows(
            sql: "SELECT payload FROM product_version WHERE product_id = ? ORDER BY ordinal, version_id",
            arguments: [productID.rawValue]
        )
    }

    public func resolutionVersion(id: ResolutionVersionID) throws -> NutritionResolutionVersion? {
        try protectedData.requireAvailable()
        return try decodeOne(
            sql: "SELECT payload FROM resolution_version WHERE version_id = ?",
            arguments: [id.rawValue]
        )
    }

    public func exactLibraryEntries(alias: LedgerText) throws -> [LibraryEntryVersion] {
        try protectedData.requireAvailable()
        return try databaseQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT payload FROM library_entry_version ORDER BY version_id"
            )
            return try rows.compactMap { row -> LibraryEntryVersion? in
                let value: LibraryEntryVersion = try decoder.decode(
                    LibraryEntryVersion.self,
                    from: row["payload"]
                )
                return value.aliases.contains(alias) ? value : nil
            }
        }
    }

    public func barcodeLibraryRecords(alias: LedgerText) throws -> [BarcodeLibraryRecord] {
        try protectedData.requireAvailable()
        return try databaseQueue.read { db in
            func decode<Value: Decodable>(
                _ type: Value.Type,
                table: String,
                column: String,
                id: String
            ) throws -> Value? {
                guard let data = try Data.fetchOne(
                    db,
                    sql: "SELECT payload FROM \(table) WHERE \(column) = ?",
                    arguments: [id]
                ) else { return nil }
                return try decoder.decode(type, from: data)
            }

            let entryRows = try Row.fetchAll(
                db,
                sql: "SELECT payload FROM library_entry_version ORDER BY version_id"
            )
            let allEntries = try entryRows.map { row in
                try decoder.decode(LibraryEntryVersion.self, from: row["payload"])
            }
            let supersededIDs = Set(allEntries.compactMap(\.supersedesLibraryEntryVersionID))
            let entries = allEntries.filter {
                !supersededIDs.contains($0.libraryEntryVersionID) && $0.aliases.contains(alias)
            }
            return try entries.flatMap { entry -> [BarcodeLibraryRecord] in
                guard let product: ProductVersion = try decode(
                    ProductVersion.self,
                    table: "product_version",
                    column: "version_id",
                    id: entry.productVersionID.rawValue
                ) else {
                    throw FoodLedgerStoreError.integrityFailure("missing barcode product version")
                }
                let resolutionRows = try Row.fetchAll(
                    db,
                    sql: "SELECT payload FROM resolution WHERE product_version_id = ? ORDER BY resolution_id",
                    arguments: [product.productVersionID.rawValue]
                )
                return try resolutionRows.compactMap { row -> BarcodeLibraryRecord? in
                    let resolution = try decoder.decode(NutritionResolution.self, from: row["payload"])
                    guard let versionData = try Data.fetchOne(
                        db,
                        sql: "SELECT payload FROM resolution_version WHERE resolution_id = ? ORDER BY ordinal DESC, version_id DESC LIMIT 1",
                        arguments: [resolution.resolutionID.rawValue]
                    ) else { return nil }
                    let version = try decoder.decode(NutritionResolutionVersion.self, from: versionData)
                    let releases = try version.sourceReleaseIDs.map { identifier in
                        guard let release: SourceRelease = try decode(
                            SourceRelease.self,
                            table: "source_release",
                            column: "source_release_id",
                            id: identifier.value
                        ) else {
                            throw FoodLedgerStoreError.integrityFailure("missing barcode source release")
                        }
                        return release
                    }
                    return try BarcodeLibraryRecord(
                        libraryEntryVersion: entry,
                        productVersion: product,
                        resolution: resolution,
                        resolutionVersion: version,
                        sourceReleases: releases
                    )
                }
            }
        }
    }

    public func conflicts() throws -> [LedgerConflict] {
        try protectedData.requireAvailable()
        return try decodeRows(sql: "SELECT payload FROM conflict ORDER BY conflict_id")
    }

    public func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? {
        try protectedData.requireAvailable()
        return try decodeOne(
            sql: "SELECT payload FROM source_release WHERE source_release_id = ?",
            arguments: [id.value]
        )
    }

    public func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? {
        try protectedData.requireAvailable()
        return try databaseQueue.read { db in
            func decode<Value: Decodable>(_ type: Value.Type, table: String, column: String, id: String) throws -> Value? {
                guard let data = try Data.fetchOne(
                    db,
                    sql: "SELECT payload FROM \(table) WHERE \(column) = ?",
                    arguments: [id]
                ) else { return nil }
                return try decoder.decode(type, from: data)
            }
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT payload FROM log_item_version WHERE log_item_id = ? ORDER BY ordinal DESC, version_id DESC LIMIT 1",
                arguments: [logItemID.rawValue]
            ) else { return nil }
            let logVersion = try decoder.decode(LogItemVersion.self, from: data)
            guard let logItem: LogItem = try decode(LogItem.self, table: "log_item", column: "log_item_id", id: logItemID.rawValue),
                  case let .product(productVersionID) = logVersion.composition,
                  let productVersion: ProductVersion = try decode(ProductVersion.self, table: "product_version", column: "version_id", id: productVersionID.rawValue),
                  let product: Product = try decode(Product.self, table: "product", column: "product_id", id: productVersion.productID.rawValue),
                  let resolutionVersion: NutritionResolutionVersion = try decode(NutritionResolutionVersion.self, table: "resolution_version", column: "version_id", id: logVersion.effectiveResolutionVersionID.rawValue),
                  let resolution: NutritionResolution = try decode(NutritionResolution.self, table: "resolution", column: "resolution_id", id: resolutionVersion.resolutionID.rawValue),
                  let decisionID = resolutionVersion.decisionIDs.first,
                  let decision: CandidateDecision = try decode(CandidateDecision.self, table: "candidate_decision", column: "decision_id", id: decisionID.rawValue) else {
                throw FoodLedgerStoreError.integrityFailure("incomplete food confirmation aggregate")
            }
            let evidence: [CaptureEvidence] = try decision.candidate.evidenceIDs.compactMap {
                try decode(CaptureEvidence.self, table: "capture_evidence", column: "evidence_id", id: $0.rawValue)
            }
            let releases: [SourceRelease] = try resolutionVersion.sourceReleaseIDs.compactMap {
                try decode(SourceRelease.self, table: "source_release", column: "source_release_id", id: $0.value)
            }
            let assertionIDs = Set(productVersion.assertionIDs + resolutionVersion.assertionIDs)
            let assertions: [UserAssertion] = try assertionIDs.compactMap {
                try decode(UserAssertion.self, table: "user_assertion", column: "assertion_id", id: $0.rawValue)
            }.sorted { $0.createdAt < $1.createdAt }
            guard evidence.count == decision.candidate.evidenceIDs.count,
                  releases.count == resolutionVersion.sourceReleaseIDs.count,
                  assertions.count == assertionIDs.count else {
                throw FoodLedgerStoreError.integrityFailure("incomplete food confirmation provenance")
            }
            let conversion: QuantityConversionVersion? = try logVersion.quantityConversionVersionID.flatMap {
                try decode(QuantityConversionVersion.self, table: "quantity_conversion_version", column: "version_id", id: $0.rawValue)
            }
            let plateVersion: PlateWeightVersion? = try logVersion.plateWeightVersionID.flatMap {
                try decode(PlateWeightVersion.self, table: "plate_weight_version", column: "version_id", id: $0.rawValue)
            }
            let plate: Plate? = try plateVersion.flatMap {
                try decode(Plate.self, table: "plate", column: "plate_id", id: $0.plateID.rawValue)
            }
            return StoredFoodConfirmation(
                evidence: evidence,
                sourceReleases: releases,
                product: product,
                productVersion: productVersion,
                resolution: resolution,
                resolutionVersion: resolutionVersion,
                logItem: logItem,
                logItemVersion: logVersion,
                quantityConversion: conversion,
                plate: plate,
                plateWeightVersion: plateVersion,
                candidateDecision: decision,
                assertions: assertions
            )
        }
    }

    public func persist(_ bytes: Data, mediaKind: LedgerText) throws -> AttachmentDescriptor {
        try protectedData.requireAvailable()
        do {
            let hash = try digester.sha256(bytes)
            let relative = "\(hash.value.prefix(2))/\(hash.value)"
            let descriptor = try AttachmentDescriptor(
                sha256: hash,
                mediaKind: mediaKind,
                byteCount: bytes.count,
                relativePath: try LedgerText(relative)
            )
            let finalURL = attachmentsRoot.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: finalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.applyCompleteProtection(to: attachmentsRoot)
            try Self.applyCompleteProtection(to: finalURL.deletingLastPathComponent())
            if FileManager.default.fileExists(atPath: finalURL.path) {
                let existing = try Data(contentsOf: finalURL)
                guard existing.count == bytes.count, try digester.sha256(existing) == hash else {
                    throw FoodLedgerStoreError.integrityFailure("attachment hash collision")
                }
                return descriptor
            }
            let temporaryURL = finalURL.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString.lowercased()).tmp")
            do {
                try bytes.write(to: temporaryURL, options: .withoutOverwriting)
                let written = try Data(contentsOf: temporaryURL)
                guard written.count == bytes.count, try digester.sha256(written) == hash else {
                    throw FoodLedgerStoreError.integrityFailure("attachment verification")
                }
                try Self.applyCompleteProtection(to: temporaryURL)
                try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
                try Self.applyCompleteProtection(to: finalURL)
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }
            return descriptor
        } catch let error as FoodLedgerStoreError {
            throw error
        } catch {
            throw FoodLedgerStoreError.attachmentFailure(String(describing: error))
        }
    }

    public func removeIfUnreferenced(_ descriptor: AttachmentDescriptor) throws {
        try protectedData.requireAvailable()
        let referenced = try databaseQueue.read { db -> Bool in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM capture_evidence")
            return try rows.contains { row in
                let evidence = try decoder.decode(CaptureEvidence.self, from: row["payload"])
                return evidence.attachment == descriptor
            }
        }
        guard !referenced else { return }
        let url = attachmentsRoot.appendingPathComponent(descriptor.relativePath.value)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func verifyIntegrity() throws {
        try protectedData.requireAvailable()
        let result = try databaseQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check")
        }
        guard result == "ok" else {
            throw FoodLedgerStoreError.integrityFailure(result ?? "no integrity result")
        }
    }

    private func validateStoredLedger() throws {
        try databaseQueue.read { db in
            try validatePayloads(CaptureEvidence.self, table: "capture_evidence", db: db)
            try validatePayloads(UserAssertion.self, table: "user_assertion", db: db)
            try validatePayloads(Product.self, table: "product", db: db)
            try validatePayloads(ProductVersion.self, table: "product_version", db: db)
            try validatePayloads(
                QuantityConversionVersion.self,
                table: "quantity_conversion_version",
                db: db
            )
            try validatePayloads(LibraryEntry.self, table: "library_entry", db: db)
            try validatePayloads(LibraryEntryVersion.self, table: "library_entry_version", db: db)
            try validatePayloads(NutritionResolution.self, table: "resolution", db: db)
            try validatePayloads(LogItem.self, table: "log_item", db: db)
            try validatePayloads(LogItemVersion.self, table: "log_item_version", db: db)
            try validatePayloads(Plate.self, table: "plate", db: db)
            try validatePayloads(PlateWeightVersion.self, table: "plate_weight_version", db: db)
            try validatePayloads(CandidateDecision.self, table: "candidate_decision", db: db)
            try validatePayloads(LedgerConflict.self, table: "conflict", db: db)
            try validatePayloads(SourceRelease.self, table: "source_release", db: db)
            try validatePayloads(SourceInstallation.self, table: "source_installation", db: db)
            let records = try Row.fetchAll(
                db,
                sql: "SELECT * FROM ledger_operation ORDER BY actor_id, actor_sequence"
            ).map(OperationRecord.init(row:))
            var heads: [String: ActorHead] = [:]
            for record in records {
                let operation = try record.operation(registry: operationRegistry)
                try verifier.verifyStored(operation)
                let head = heads[operation.actorID.rawValue]
                    ?? ActorHead(sequence: 0, operationHash: nil)
                guard operation.actorSequence == head.sequence + 1 else {
                    throw FoodLedgerStoreError.actorSequenceMismatch
                }
                guard operation.previousOperationHash == head.operationHash else {
                    throw FoodLedgerStoreError.actorHashMismatch
                }
                heads[operation.actorID.rawValue] = ActorHead(
                    sequence: operation.actorSequence,
                    operationHash: operation.operationHash
                )
            }
            let storedHeads = try Row.fetchAll(
                db,
                sql: "SELECT actor_id, sequence, operation_hash FROM ledger_actor"
            )
            guard storedHeads.count == heads.count else {
                throw FoodLedgerStoreError.integrityFailure("actor head count")
            }
            for row in storedHeads {
                let actor: String = row["actor_id"]
                let stored = ActorHead(
                    sequence: row["sequence"],
                    operationHash: try SHA256Digest(row["operation_hash"])
                )
                guard heads[actor] == stored else {
                    throw FoodLedgerStoreError.integrityFailure("actor head")
                }
            }

            let versions = try Row.fetchAll(
                db,
                sql: "SELECT version_id, payload FROM resolution_version"
            )
            for row in versions {
                let version: NutritionResolutionVersion
                do {
                    version = try decoder.decode(
                        NutritionResolutionVersion.self,
                        from: row["payload"]
                    )
                } catch {
                    throw FoodLedgerStoreError.integrityFailure("resolution payload decoding")
                }
                let nutrientRows = try Row.fetchAll(
                    db,
                    sql: "SELECT nutrient_key, payload FROM resolution_nutrient WHERE resolution_version_id = ? ORDER BY position",
                    arguments: [version.resolutionVersionID.rawValue]
                )
                let keys = nutrientRows.map { $0["nutrient_key"] as String }
                let entries: [NutrientEntry]
                do {
                    entries = try nutrientRows.map { row in
                        try decoder.decode(NutrientEntry.self, from: row["payload"] as Data)
                    }
                } catch {
                    throw FoodLedgerStoreError.integrityFailure("resolution nutrient decoding")
                }
                guard keys == NutrientKey.allCases.map(\.rawValue),
                      entries == version.nutrients.entries else {
                    throw FoodLedgerStoreError.integrityFailure("resolution nutrient catalogue")
                }
            }
        }
    }

    private func validatePayloads<Value: Decodable>(
        _ type: Value.Type,
        table: String,
        db: Database
    ) throws {
        do {
            for data in try Data.fetchAll(db, sql: "SELECT payload FROM \(table)") {
                _ = try decoder.decode(type, from: data)
            }
        } catch {
            throw FoodLedgerStoreError.integrityFailure("\(table) payload decoding")
        }
    }

    private func decodeRows<Value: Decodable>(
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> [Value] {
        try databaseQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                try decoder.decode(Value.self, from: row["payload"])
            }
        }
    }

    private func decodeOne<Value: Decodable>(
        sql: String,
        arguments: StatementArguments
    ) throws -> Value? {
        try databaseQueue.read { db in
            guard let data = try Data.fetchOne(db, sql: sql, arguments: arguments) else { return nil }
            return try decoder.decode(Value.self, from: data)
        }
    }

    private func insert(_ mutation: LedgerMutation, db: Database) throws {
        try insertPayloads(mutation.evidence, table: "capture_evidence", id: "evidence_id", db: db) {
            [$0.evidenceID.rawValue]
        }
        try insertPayloads(mutation.assertions, table: "user_assertion", id: "assertion_id", db: db) {
            [$0.assertionID.rawValue, $0.evidenceID?.rawValue, $0.supersedesAssertionID?.rawValue]
        }
        try insertPayloads(mutation.products, table: "product", id: "product_id", db: db) {
            [$0.productID.rawValue]
        }
        try insertPayloads(mutation.sourceReleases, table: "source_release", id: "source_release_id", db: db) {
            [$0.sourceReleaseID.value]
        }
        for value in mutation.productVersions {
            try requireRecordedConflict(
                db: db,
                table: "product_version",
                idColumn: "version_id",
                supersedes: value.supersedesProductVersionID?.rawValue,
                newVersion: value.productVersionID.rawValue,
                kind: .competingProductSuccessors,
                conflicts: mutation.conflicts
            )
            try db.execute(
                sql: "INSERT INTO product_version(version_id, product_id, ordinal, supersedes_id, payload) VALUES (?, ?, ?, ?, ?)",
                arguments: [value.productVersionID.rawValue, value.productID.rawValue, value.ordinal.value,
                            value.supersedesProductVersionID?.rawValue, try encoder.encode(value)]
            )
            try insertLinks(
                table: "product_version_evidence",
                ownerColumn: "version_id",
                ownerID: value.productVersionID.rawValue,
                targetColumn: "evidence_id",
                targetIDs: value.evidenceIDs.map(\.rawValue),
                db: db
            )
            try insertLinks(
                table: "product_version_assertion",
                ownerColumn: "version_id",
                ownerID: value.productVersionID.rawValue,
                targetColumn: "assertion_id",
                targetIDs: value.assertionIDs.map(\.rawValue),
                db: db
            )
        }
        try insertPayloads(mutation.libraryEntries, table: "library_entry", id: "library_entry_id", db: db) {
            [$0.libraryEntryID.rawValue]
        }
        for value in mutation.quantityConversions {
            try requireRecordedConflict(
                db: db,
                table: "quantity_conversion_version",
                idColumn: "version_id",
                supersedes: value.supersedesQuantityConversionVersionID?.rawValue,
                newVersion: value.quantityConversionVersionID.rawValue,
                kind: .competingQuantityVersions,
                conflicts: mutation.conflicts
            )
            try db.execute(
                sql: "INSERT INTO quantity_conversion_version(version_id, ordinal, supersedes_id, source_release_id, evidence_id, payload) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [value.quantityConversionVersionID.rawValue, value.ordinal.value,
                            value.supersedesQuantityConversionVersionID?.rawValue,
                            value.sourceReleaseID?.value, value.evidenceID?.rawValue,
                            try encoder.encode(value)]
            )
        }
        for value in mutation.libraryEntryVersions {
            try requireRecordedConflict(
                db: db,
                table: "library_entry_version",
                idColumn: "version_id",
                supersedes: value.supersedesLibraryEntryVersionID?.rawValue,
                newVersion: value.libraryEntryVersionID.rawValue,
                kind: .competingLibrarySuccessors,
                conflicts: mutation.conflicts
            )
            try db.execute(
                sql: "INSERT INTO library_entry_version(version_id, library_entry_id, product_version_id, ordinal, supersedes_id, quantity_conversion_version_id, payload) VALUES (?, ?, ?, ?, ?, ?, ?)",
                arguments: [value.libraryEntryVersionID.rawValue, value.libraryEntryID.rawValue,
                            value.productVersionID.rawValue, value.ordinal.value,
                            value.supersedesLibraryEntryVersionID?.rawValue,
                            value.quantityConversionVersionID?.rawValue, try encoder.encode(value)]
            )
        }
        for value in mutation.resolutions {
            try db.execute(
                sql: "INSERT INTO resolution(resolution_id, product_version_id, payload) VALUES (?, ?, ?)",
                arguments: [value.resolutionID.rawValue, value.productVersionID.rawValue, try encoder.encode(value)]
            )
        }
        for value in mutation.candidateDecisions {
            try db.execute(
                sql: "INSERT INTO candidate_decision(decision_id, source_release_id, assertion_id, payload) VALUES (?, ?, ?, ?)",
                arguments: [value.candidateDecisionID.rawValue, value.candidate.sourceReleaseID.value,
                            value.assertionID?.rawValue, try encoder.encode(value)]
            )
            try insertLinks(
                table: "candidate_decision_evidence",
                ownerColumn: "decision_id",
                ownerID: value.candidateDecisionID.rawValue,
                targetColumn: "evidence_id",
                targetIDs: value.candidate.evidenceIDs.map(\.rawValue),
                db: db
            )
        }
        for value in mutation.resolutionVersions {
            try requireRecordedConflict(
                db: db,
                table: "resolution_version",
                idColumn: "version_id",
                supersedes: value.supersedesResolutionVersionID?.rawValue,
                newVersion: value.resolutionVersionID.rawValue,
                kind: .competingResolutionSuccessors,
                conflicts: mutation.conflicts
            )
            try db.execute(
                sql: "INSERT INTO resolution_version(version_id, resolution_id, ordinal, supersedes_id, payload) VALUES (?, ?, ?, ?, ?)",
                arguments: [value.resolutionVersionID.rawValue, value.resolutionID.rawValue,
                            value.ordinal.value, value.supersedesResolutionVersionID?.rawValue,
                            try encoder.encode(value)]
            )
            try insertLinks(
                table: "resolution_version_source_release",
                ownerColumn: "version_id",
                ownerID: value.resolutionVersionID.rawValue,
                targetColumn: "source_release_id",
                targetIDs: value.sourceReleaseIDs.map(\.value),
                db: db
            )
            try insertLinks(
                table: "resolution_version_decision",
                ownerColumn: "version_id",
                ownerID: value.resolutionVersionID.rawValue,
                targetColumn: "decision_id",
                targetIDs: value.decisionIDs.map(\.rawValue),
                db: db
            )
            try insertLinks(
                table: "resolution_version_assertion",
                ownerColumn: "version_id",
                ownerID: value.resolutionVersionID.rawValue,
                targetColumn: "assertion_id",
                targetIDs: value.assertionIDs.map(\.rawValue),
                db: db
            )
            try validateNutrientProvenance(value, db: db)
            for (index, nutrient) in value.nutrients.entries.enumerated() {
                try db.execute(
                    sql: "INSERT INTO resolution_nutrient(resolution_version_id, position, nutrient_key, payload) VALUES (?, ?, ?, ?)",
                    arguments: [value.resolutionVersionID.rawValue, index, nutrient.key.rawValue,
                                try encoder.encode(nutrient)]
                )
            }
        }
        try insertPayloads(mutation.logItems, table: "log_item", id: "log_item_id", db: db) {
            [$0.logItemID.rawValue]
        }
        for value in mutation.logItemVersions {
            let productVersionID: String?
            switch value.composition {
            case let .product(id): productVersionID = id.rawValue
            case .mixture: productVersionID = nil
            }
            try requireRecordedConflict(
                db: db,
                table: "log_item_version",
                idColumn: "version_id",
                supersedes: value.supersedesLogItemVersionID?.rawValue,
                newVersion: value.logItemVersionID.rawValue,
                kind: .competingLogCorrections,
                conflicts: mutation.conflicts
            )
            if let plateWeightVersionID = value.plateWeightVersionID,
               !mutation.plateWeightVersions.contains(where: {
                   $0.plateWeightVersionID == plateWeightVersionID
               }) {
                try requireReference(
                    table: "plate_weight_version",
                    column: "version_id",
                    id: plateWeightVersionID.rawValue,
                    db: db
                )
            }
            try db.execute(
                sql: "INSERT INTO log_item_version(version_id, log_item_id, product_version_id, ordinal, supersedes_id, original_resolution_version_id, effective_resolution_version_id, quantity_conversion_version_id, payload) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                arguments: [value.logItemVersionID.rawValue, value.logItemID.rawValue, productVersionID,
                            value.ordinal.value, value.supersedesLogItemVersionID?.rawValue,
                            value.originalResolutionVersionID.rawValue,
                            value.effectiveResolutionVersionID.rawValue,
                            value.quantityConversionVersionID?.rawValue, try encoder.encode(value)]
            )
            if case let .mixture(componentIDs) = value.composition {
                try insertLinks(
                    table: "log_item_component",
                    ownerColumn: "version_id",
                    ownerID: value.logItemVersionID.rawValue,
                    targetColumn: "component_version_id",
                    targetIDs: componentIDs.map(\.rawValue),
                    db: db
                )
            }
        }
        try insertPayloads(mutation.plates, table: "plate", id: "plate_id", db: db) {
            [$0.plateID.rawValue]
        }
        for value in mutation.plateWeightVersions {
            try requireRecordedConflict(
                db: db,
                table: "plate_weight_version",
                idColumn: "version_id",
                supersedes: value.supersedesPlateWeightVersionID?.rawValue,
                newVersion: value.plateWeightVersionID.rawValue,
                kind: .competingPlateVersions,
                conflicts: mutation.conflicts
            )
            try db.execute(
                sql: "INSERT INTO plate_weight_version(version_id, plate_id, ordinal, supersedes_id, evidence_id, payload) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [value.plateWeightVersionID.rawValue, value.plateID.rawValue,
                            value.ordinal.value, value.supersedesPlateWeightVersionID?.rawValue,
                            value.evidenceID?.rawValue, try encoder.encode(value)]
            )
        }
        try validateConflicts(mutation.conflicts, db: db)
        try insertPayloads(mutation.conflicts, table: "conflict", id: "conflict_id", db: db) {
            [$0.conflictID.rawValue]
        }
        try insertPayloads(
            mutation.sourceInstallations,
            table: "source_installation",
            id: "source_release_id",
            db: db
        ) {
            [$0.sourceReleaseID.value]
        }
    }

    private func insertLinks(
        table: String,
        ownerColumn: String,
        ownerID: String,
        targetColumn: String,
        targetIDs: [String],
        db: Database
    ) throws {
        for (position, targetID) in targetIDs.enumerated() {
            try db.execute(
                sql: "INSERT INTO \(table)(\(ownerColumn), position, \(targetColumn)) VALUES (?, ?, ?)",
                arguments: [ownerID, position, targetID]
            )
        }
    }

    private func validateNutrientProvenance(
        _ version: NutritionResolutionVersion,
        db: Database
    ) throws {
        for entry in version.nutrients.entries {
            for value in [entry.value] + entry.conflictCandidates {
                for provenance in value.provenance {
                    guard version.sourceReleaseIDs.contains(provenance.sourceReleaseID) else {
                        throw FoodLedgerStoreError.missingReference(provenance.sourceReleaseID.value)
                    }
                    if let evidenceID = provenance.evidenceID {
                        try requireReference(
                            table: "capture_evidence",
                            column: "evidence_id",
                            id: evidenceID.rawValue,
                            db: db
                        )
                    }
                    if let decisionID = provenance.decisionID {
                        try requireReference(
                            table: "candidate_decision",
                            column: "decision_id",
                            id: decisionID.rawValue,
                            db: db
                        )
                    }
                    if let assertionID = provenance.assertionID {
                        try requireReference(
                            table: "user_assertion",
                            column: "assertion_id",
                            id: assertionID.rawValue,
                            db: db
                        )
                    }
                    for transform in provenance.transforms {
                        if let conversionID = transform.quantityConversionVersionID {
                            try requireReference(
                                table: "quantity_conversion_version",
                                column: "version_id",
                                id: conversionID.rawValue,
                                db: db
                            )
                        }
                    }
                }
            }
        }
    }

    private func requireReference(
        table: String,
        column: String,
        id: String,
        db: Database
    ) throws {
        let exists = try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM \(table) WHERE \(column) = ?)",
            arguments: [id]
        ) ?? false
        guard exists else { throw FoodLedgerStoreError.missingReference(id) }
    }

    private func validateConflicts(_ conflicts: [LedgerConflict], db: Database) throws {
        for conflict in conflicts {
            let table: String
            switch conflict.kind {
            case .competingProductSuccessors: table = "product_version"
            case .competingLibrarySuccessors: table = "library_entry_version"
            case .competingResolutionSuccessors: table = "resolution_version"
            case .competingLogCorrections: table = "log_item_version"
            case .competingQuantityVersions: table = "quantity_conversion_version"
            case .competingPlateVersions: table = "plate_weight_version"
            }
            try requireReference(
                table: table,
                column: "version_id",
                id: conflict.ancestorVersionID.value,
                db: db
            )
            for competitor in conflict.competingVersionIDs {
                let ancestor = try String.fetchOne(
                    db,
                    sql: "SELECT supersedes_id FROM \(table) WHERE version_id = ?",
                    arguments: [competitor.value]
                )
                guard ancestor == conflict.ancestorVersionID.value else {
                    throw FoodLedgerStoreError.integrityFailure("invalid conflict ancestry")
                }
            }
        }
    }

    private func insertPayloads<Value: Encodable & Sendable>(
        _ values: [Value],
        table: String,
        id: String,
        db: Database,
        arguments: (Value) throws -> [DatabaseValueConvertible?]
    ) throws {
        for value in values {
            var values = try arguments(value)
            values.append(try encoder.encode(value))
            let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
            let columns: String
            switch table {
            case "user_assertion": columns = "assertion_id, evidence_id, supersedes_id, payload"
            default: columns = "\(id), payload"
            }
            try db.execute(
                sql: "INSERT INTO \(table)(\(columns)) VALUES (\(placeholders))",
                arguments: StatementArguments(values)
            )
        }
    }

    private func requireRecordedConflict(
        db: Database,
        table: String,
        idColumn: String,
        supersedes: String?,
        newVersion: String,
        kind: ConflictKind,
        conflicts: [LedgerConflict]
    ) throws {
        guard let supersedes else { return }
        let competitors = try String.fetchAll(
            db,
            sql: "SELECT \(idColumn) FROM \(table) WHERE supersedes_id = ?",
            arguments: [supersedes]
        )
        for competitor in competitors where competitor != newVersion {
            let recorded = conflicts.contains { conflict in
                conflict.kind == kind
                    && conflict.ancestorVersionID.value == supersedes
                    && Set(conflict.competingVersionIDs.map(\.value))
                        .isSuperset(of: [competitor, newVersion])
            }
            guard recorded else {
                throw FoodLedgerStoreError.integrityFailure("unrecorded competing successor")
            }
        }
    }

    private static func fetchActorHead(_ db: Database, actorID: ActorID) throws -> ActorHead {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT sequence, operation_hash FROM ledger_actor WHERE actor_id = ?",
            arguments: [actorID.rawValue]
        ) else {
            return ActorHead(sequence: 0, operationHash: nil)
        }
        return ActorHead(
            sequence: row["sequence"],
            operationHash: try SHA256Digest(row["operation_hash"])
        )
    }

    private func fetchOperation(_ db: Database, id: String) throws -> LedgerOperation? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM ledger_operation WHERE operation_id = ?",
            arguments: [id]
        ) else { return nil }
        return try OperationRecord(row: row).operation(registry: operationRegistry)
    }

    private static func validatePreMigrationIdentity(_ queue: DatabaseQueue) throws {
        let identity = try queue.read { db -> (Int, Int) in
            let applicationID = try Int.fetchOne(db, sql: "PRAGMA application_id") ?? 0
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            return (applicationID, version)
        }
        if identity.1 > schemaVersion { throw FoodLedgerStoreError.unknownSchema(identity.1) }
        if identity.0 != 0, identity.0 != applicationID { throw FoodLedgerStoreError.corruptStore }
        if identity.1 > 0, identity.0 != applicationID { throw FoodLedgerStoreError.corruptStore }
    }

    private static func validateOpenPolicy(_ queue: DatabaseQueue) throws {
        try queue.read { db in
            let foreignKeys = try Int.fetchOne(db, sql: "PRAGMA foreign_keys") ?? 0
            let journal = try String.fetchOne(db, sql: "PRAGMA journal_mode")?.lowercased()
            let synchronous = try Int.fetchOne(db, sql: "PRAGMA synchronous") ?? 0
            let application = try Int.fetchOne(db, sql: "PRAGMA application_id") ?? 0
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            let metadata = try String.fetchOne(
                db,
                sql: "SELECT value FROM ledger_metadata WHERE key = 'schema_identity'"
            )
            let check = try String.fetchOne(db, sql: "PRAGMA quick_check")
            let foreignKeyFailures = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            guard foreignKeys == 1,
                  journal == "delete",
                  synchronous == 2,
                  application == applicationID,
                  version == schemaVersion,
                  metadata == "food-ledger-v1",
                  check == "ok",
                  foreignKeyFailures.isEmpty else {
                throw FoodLedgerStoreError.integrityFailure("database open policy")
            }
        }
    }

    private static func applyCompleteProtection(to url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
    }
}

private struct OperationRecord {
    let operationID: String
    let actorID: String
    let actorSequence: Int
    let operationType: String
    let createdAt: Double
    let affectedIDs: Data
    let payload: Data
    let payloadHash: String
    let previousOperationHash: String?
    let operationHash: String
    let idempotencyKey: String?

    init(operation: LedgerOperation) throws {
        operationID = operation.operationID.rawValue
        actorID = operation.actorID.rawValue
        actorSequence = operation.actorSequence
        operationType = operation.operationType.rawValue
        createdAt = operation.createdAt.timeIntervalSince1970
        affectedIDs = try JSONEncoder().encode(operation.affectedIDs)
        payload = operation.payload
        payloadHash = operation.payloadHash.value
        previousOperationHash = operation.previousOperationHash?.value
        operationHash = operation.operationHash.value
        idempotencyKey = operation.idempotencyKey?.value
    }

    init(row: Row) {
        operationID = row["operation_id"]
        actorID = row["actor_id"]
        actorSequence = row["actor_sequence"]
        operationType = row["operation_type"]
        createdAt = row["created_at"]
        affectedIDs = row["affected_ids"]
        payload = row["payload"]
        payloadHash = row["payload_hash"]
        previousOperationHash = row["previous_operation_hash"]
        operationHash = row["operation_hash"]
        idempotencyKey = row["idempotency_key"]
    }

    func operation(registry: LedgerOperationRegistry) throws -> LedgerOperation {
        guard let type = LedgerOperationType(rawValue: operationType) else {
            throw FoodLedgerStoreError.unsupportedOperation
        }
        try registry.requireSupported(type)
        return LedgerOperation(
            operationID: try OperationID(operationID),
            actorID: try ActorID(actorID),
            actorSequence: actorSequence,
            operationType: type,
            createdAt: Date(timeIntervalSince1970: createdAt),
            affectedIDs: try JSONDecoder().decode([String].self, from: affectedIDs),
            payload: payload,
            payloadHash: try SHA256Digest(payloadHash),
            previousOperationHash: try previousOperationHash.map(SHA256Digest.init),
            operationHash: try SHA256Digest(operationHash),
            idempotencyKey: try idempotencyKey.map { try LedgerText($0) }
        )
    }
}
