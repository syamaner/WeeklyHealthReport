import Foundation
import FoodLedgerDomain

public enum FoodArchiveError: Error, Equatable, Sendable {
    case unsupportedBackupFormat(Int)
    case unsupportedFoodContract(Int)
    case unsupportedProjectionSchema(Int)
    case malformedArchive(String)
    case memberMismatch(String)
    case snapshotMismatch
    case actorChainGap(String)
    case divergentOperation(String)
    case stagingMismatch
    case interruptedGeneration
}

public struct CanonicalFoodNutritionSummary: Codable, Equatable, Sendable {
    public let summaryVersionID: LedgerText
    public let reportingDate: LedgerText
    public let nutrients: NutrientSet
    public let inputLogItemVersionIDs: [LogItemVersionID]
    public let hasUnknownContribution: Bool

    public init(
        summaryVersionID: LedgerText,
        reportingDate: LedgerText,
        nutrients: NutrientSet,
        inputLogItemVersionIDs: [LogItemVersionID],
        hasUnknownContribution: Bool
    ) {
        self.summaryVersionID = summaryVersionID
        self.reportingDate = reportingDate
        self.nutrients = nutrients
        self.inputLogItemVersionIDs = inputLogItemVersionIDs.sorted { $0.rawValue < $1.rawValue }
        self.hasUnknownContribution = hasUnknownContribution
    }
}

public struct CanonicalFoodProjection: Codable, Equatable, Sendable {
    public static let foodContractVersion = 1
    public static let dailySchemaVersion = 4

    public let foodContractVersion: Int
    public let dailySchemaVersion: Int
    public let records: LedgerMutation
    public let summaries: [CanonicalFoodNutritionSummary]

    public init(
        records: LedgerMutation,
        summaries: [CanonicalFoodNutritionSummary] = [],
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder()
    ) throws {
        foodContractVersion = Self.foodContractVersion
        dailySchemaVersion = Self.dailySchemaVersion
        self.records = try Self.sorted(records, encoder: encoder)
        self.summaries = try Self.sort(summaries, encoder: encoder)
    }

    private static func sorted(
        _ value: LedgerMutation,
        encoder: any CanonicalEncoding
    ) throws -> LedgerMutation {
        LedgerMutation(
            evidence: try sort(value.evidence, encoder: encoder),
            assertions: try sort(value.assertions, encoder: encoder),
            products: try sort(value.products, encoder: encoder),
            productVersions: try sort(value.productVersions, encoder: encoder),
            libraryEntries: try sort(value.libraryEntries, encoder: encoder),
            libraryEntryVersions: try sort(value.libraryEntryVersions, encoder: encoder),
            resolutions: try sort(value.resolutions, encoder: encoder),
            resolutionVersions: try sort(value.resolutionVersions, encoder: encoder),
            logItems: try sort(value.logItems, encoder: encoder),
            logItemVersions: try sort(value.logItemVersions, encoder: encoder),
            quantityConversions: try sort(value.quantityConversions, encoder: encoder),
            plates: try sort(value.plates, encoder: encoder),
            plateWeightVersions: try sort(value.plateWeightVersions, encoder: encoder),
            candidateDecisions: try sort(value.candidateDecisions, encoder: encoder),
            conflicts: try sort(value.conflicts, encoder: encoder),
            sourceReleases: try sort(value.sourceReleases, encoder: encoder),
            sourceInstallations: try sort(value.sourceInstallations, encoder: encoder)
        )
    }

    private static func sort<Value: Codable & Sendable>(
        _ values: [Value],
        encoder: any CanonicalEncoding
    ) throws -> [Value] {
        try values.map { (try encoder.encode($0), $0) }
            .sorted { $0.0.lexicographicallyPrecedes($1.0) }
            .map(\.1)
    }
}

public struct CanonicalFoodDocument: Codable, Equatable, Sendable {
    public let snapshotID: SHA256Digest
    public let projection: CanonicalFoodProjection

    public init(
        projection: CanonicalFoodProjection,
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
        digester: any Digesting = SHA256Digester()
    ) throws {
        self.projection = projection
        snapshotID = try digester.sha256(encoder.encode(projection))
    }
}

public struct FoodArchiveState: Equatable, Sendable {
    public let records: LedgerMutation
    public let operations: [LedgerOperation]
    public let summaries: [CanonicalFoodNutritionSummary]

    public init(
        records: LedgerMutation,
        operations: [LedgerOperation],
        summaries: [CanonicalFoodNutritionSummary] = []
    ) {
        self.records = records
        self.operations = operations
        self.summaries = summaries
    }
}

public protocol FoodArchiveLedgerAccess: LedgerCommandCommitting, LedgerReading {
    func archiveState() throws -> FoodArchiveState
    func commitAtomically(_ transactions: [LedgerTransaction]) throws -> [CommitOutcome]
}

public struct FoodArchiveMember: Codable, Equatable, Sendable {
    public let filename: LedgerText
    public let byteCount: Int
    public let sha256: SHA256Digest

    public init(filename: LedgerText, bytes: Data, digester: any Digesting) throws {
        self.filename = filename
        byteCount = bytes.count
        sha256 = try digester.sha256(bytes)
    }
}

public struct FoodArchiveWatermark: Codable, Equatable, Sendable {
    public let actorID: ActorID
    public let baseSequence: Int
    public let baseHash: SHA256Digest?
    public let endSequence: Int
    public let endHash: SHA256Digest

    public init(
        actorID: ActorID,
        baseSequence: Int = 0,
        baseHash: SHA256Digest? = nil,
        endSequence: Int,
        endHash: SHA256Digest
    ) {
        self.actorID = actorID
        self.baseSequence = baseSequence
        self.baseHash = baseHash
        self.endSequence = endSequence
        self.endHash = endHash
    }
}

public struct FoodArchiveManifest: Codable, Equatable, Sendable {
    public static let currentBackupFormatVersion = 1

    public let backupFormatVersion: Int
    public let foodContractVersion: Int
    public let dailySchemaVersion: Int
    public let ledgerID: LedgerText
    public let snapshotID: SHA256Digest
    public let createdAt: Date
    public let creatingActorID: ActorID
    public let migrationIdentifiers: [LedgerText]
    public let sourceReleaseIDs: [ExternalIdentifier]
    public let watermarks: [FoodArchiveWatermark]
    public let recordCount: Int
    public let operationCount: Int
    public let members: [FoodArchiveMember]
    public let rawAttachmentsOmitted: Bool
    public let hashesAreIntegrityMetadataOnly: Bool

    public init(
        ledgerID: LedgerText,
        snapshotID: SHA256Digest,
        createdAt: Date,
        creatingActorID: ActorID,
        sourceReleaseIDs: [ExternalIdentifier],
        watermarks: [FoodArchiveWatermark],
        recordCount: Int,
        operationCount: Int,
        members: [FoodArchiveMember]
    ) throws {
        backupFormatVersion = Self.currentBackupFormatVersion
        foodContractVersion = CanonicalFoodProjection.foodContractVersion
        dailySchemaVersion = CanonicalFoodProjection.dailySchemaVersion
        self.ledgerID = ledgerID
        self.snapshotID = snapshotID
        self.createdAt = createdAt
        self.creatingActorID = creatingActorID
        migrationIdentifiers = [try LedgerText("food-ledger-v1")]
        self.sourceReleaseIDs = sourceReleaseIDs.sorted { $0.value < $1.value }
        self.watermarks = watermarks.sorted { $0.actorID.rawValue < $1.actorID.rawValue }
        self.recordCount = recordCount
        self.operationCount = operationCount
        self.members = members.sorted { $0.filename.value < $1.filename.value }
        rawAttachmentsOmitted = true
        hashesAreIntegrityMetadataOnly = true
    }
}

public struct FoodArchiveBundle: Equatable, Sendable {
    public let manifest: Data
    public let snapshot: Data
    public let operations: Data

    public init(manifest: Data, snapshot: Data, operations: Data) {
        self.manifest = manifest
        self.snapshot = snapshot
        self.operations = operations
    }
}

public struct FoodArchiveGenerator: Sendable {
    private let encoder: any CanonicalEncoding
    private let digester: any Digesting

    public init(
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
        digester: any Digesting = SHA256Digester()
    ) {
        self.encoder = encoder
        self.digester = digester
    }

    public func generate(
        state: FoodArchiveState,
        ledgerID: LedgerText,
        createdAt: Date,
        creatingActorID: ActorID
    ) throws -> FoodArchiveBundle {
        let projection = try CanonicalFoodProjection(
            records: state.records,
            summaries: state.summaries,
            encoder: encoder
        )
        let document = try CanonicalFoodDocument(
            projection: projection,
            encoder: encoder,
            digester: digester
        )
        let snapshot = try encoder.encode(document)
        let sortedOperations = state.operations.sorted {
            ($0.actorID.rawValue, $0.actorSequence, $0.operationID.rawValue)
                < ($1.actorID.rawValue, $1.actorSequence, $1.operationID.rawValue)
        }
        let operationLines = try sortedOperations.map { try encoder.encode($0) }
        var operations = Data()
        for line in operationLines {
            operations.append(line)
            operations.append(0x0A)
        }
        let watermarks = try Self.watermarks(for: sortedOperations)
        let members = try [
            FoodArchiveMember(filename: LedgerText("operations.ndjson"), bytes: operations, digester: digester),
            FoodArchiveMember(filename: LedgerText("snapshot.json"), bytes: snapshot, digester: digester)
        ]
        let manifest = try FoodArchiveManifest(
            ledgerID: ledgerID,
            snapshotID: document.snapshotID,
            createdAt: createdAt,
            creatingActorID: creatingActorID,
            sourceReleaseIDs: projection.records.sourceReleases.map(\.sourceReleaseID),
            watermarks: watermarks,
            recordCount: Self.recordCount(projection.records),
            operationCount: sortedOperations.count,
            members: members
        )
        return FoodArchiveBundle(
            manifest: try encoder.encode(manifest),
            snapshot: snapshot,
            operations: operations
        )
    }

    private static func watermarks(for operations: [LedgerOperation]) throws -> [FoodArchiveWatermark] {
        let groups = Dictionary(grouping: operations, by: \.actorID)
        return try groups.map { actor, values in
            let sorted = values.sorted { $0.actorSequence < $1.actorSequence }
            guard let last = sorted.last else {
                throw FoodArchiveError.malformedArchive("empty actor stream")
            }
            return FoodArchiveWatermark(
                actorID: actor,
                endSequence: last.actorSequence,
                endHash: last.operationHash
            )
        }.sorted { $0.actorID.rawValue < $1.actorID.rawValue }
    }

    static func recordCount(_ records: LedgerMutation) -> Int {
        records.evidence.count + records.assertions.count + records.products.count
            + records.productVersions.count + records.libraryEntries.count
            + records.libraryEntryVersions.count + records.resolutions.count
            + records.resolutionVersions.count + records.logItems.count
            + records.logItemVersions.count + records.quantityConversions.count
            + records.plates.count + records.plateWeightVersions.count
            + records.candidateDecisions.count + records.conflicts.count
            + records.sourceReleases.count + records.sourceInstallations.count
    }
}

public struct VerifiedFoodArchive: Equatable, Sendable {
    public let manifest: FoodArchiveManifest
    public let document: CanonicalFoodDocument
    public let transactions: [LedgerTransaction]
}

public struct FoodArchiveVerifier: Sendable {
    private let encoder: any CanonicalEncoding
    private let digester: any Digesting
    private let operationVerifier: OperationVerifier

    public init(
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
        digester: any Digesting = SHA256Digester(),
        operationRegistry: LedgerOperationRegistry = .builtInV1
    ) {
        self.encoder = encoder
        self.digester = digester
        operationVerifier = OperationVerifier(
            encoder: encoder,
            digester: digester,
            operationRegistry: operationRegistry
        )
    }

    public func verify(_ bundle: FoodArchiveBundle) throws -> VerifiedFoodArchive {
        let decoder = Self.decoder()
        let manifest: FoodArchiveManifest
        do { manifest = try decoder.decode(FoodArchiveManifest.self, from: bundle.manifest) }
        catch { throw FoodArchiveError.malformedArchive("manifest") }
        guard manifest.backupFormatVersion == FoodArchiveManifest.currentBackupFormatVersion else {
            throw FoodArchiveError.unsupportedBackupFormat(manifest.backupFormatVersion)
        }
        guard manifest.foodContractVersion == CanonicalFoodProjection.foodContractVersion else {
            throw FoodArchiveError.unsupportedFoodContract(manifest.foodContractVersion)
        }
        guard manifest.dailySchemaVersion == CanonicalFoodProjection.dailySchemaVersion else {
            throw FoodArchiveError.unsupportedProjectionSchema(manifest.dailySchemaVersion)
        }
        guard manifest.rawAttachmentsOmitted, manifest.hashesAreIntegrityMetadataOnly else {
            throw FoodArchiveError.malformedArchive("privacy boundary")
        }
        guard manifest.members.count == 2,
              Set(manifest.members.map(\.filename.value))
                == Set(["snapshot.json", "operations.ndjson"]) else {
            throw FoodArchiveError.malformedArchive("member descriptors")
        }
        try verifyMember("snapshot.json", bytes: bundle.snapshot, manifest: manifest)
        try verifyMember("operations.ndjson", bytes: bundle.operations, manifest: manifest)

        let document: CanonicalFoodDocument
        do { document = try decoder.decode(CanonicalFoodDocument.self, from: bundle.snapshot) }
        catch { throw FoodArchiveError.malformedArchive("snapshot") }
        guard document.projection.foodContractVersion
                == CanonicalFoodProjection.foodContractVersion else {
            throw FoodArchiveError.unsupportedFoodContract(
                document.projection.foodContractVersion
            )
        }
        guard document.projection.dailySchemaVersion
                == CanonicalFoodProjection.dailySchemaVersion else {
            throw FoodArchiveError.unsupportedProjectionSchema(
                document.projection.dailySchemaVersion
            )
        }
        let expectedDocument = try CanonicalFoodDocument(
            projection: document.projection,
            encoder: encoder,
            digester: digester
        )
        let sourceReleaseIDs = document.projection.records.sourceReleases
            .map(\.sourceReleaseID)
            .sorted(by: { $0.value < $1.value })
        guard expectedDocument.snapshotID == document.snapshotID,
              document.snapshotID == manifest.snapshotID,
              FoodArchiveGenerator.recordCount(document.projection.records)
                == manifest.recordCount,
              sourceReleaseIDs == manifest.sourceReleaseIDs,
              try encoder.encode(document) == bundle.snapshot else {
            throw FoodArchiveError.snapshotMismatch
        }

        let operations = try decodeOperations(bundle.operations, decoder: decoder)
        guard operations.count == manifest.operationCount else {
            throw FoodArchiveError.memberMismatch("operation count")
        }
        let transactions = try operations.map { operation -> LedgerTransaction in
            let mutation: LedgerMutation
            do { mutation = try decoder.decode(LedgerMutation.self, from: operation.payload) }
            catch { throw FoodArchiveError.malformedArchive("operation payload") }
            let transaction = LedgerTransaction(mutation: mutation, operation: operation)
            try operationVerifier.verify(transaction)
            return transaction
        }
        try verifyActorChains(operations, watermarks: manifest.watermarks)
        return VerifiedFoodArchive(manifest: manifest, document: document, transactions: transactions)
    }

    private func verifyMember(
        _ filename: String,
        bytes: Data,
        manifest: FoodArchiveManifest
    ) throws {
        guard let member = manifest.members.first(where: { $0.filename.value == filename }),
              member.byteCount == bytes.count,
              member.sha256 == (try digester.sha256(bytes)) else {
            throw FoodArchiveError.memberMismatch(filename)
        }
    }

    private func decodeOperations(_ data: Data, decoder: JSONDecoder) throws -> [LedgerOperation] {
        guard data.isEmpty || data.last == 0x0A else {
            throw FoodArchiveError.malformedArchive("operations newline")
        }
        return try data.split(separator: 0x0A).map { line in
            do { return try decoder.decode(LedgerOperation.self, from: Data(line)) }
            catch { throw FoodArchiveError.malformedArchive("operation") }
        }
    }

    private func verifyActorChains(
        _ operations: [LedgerOperation],
        watermarks: [FoodArchiveWatermark]
    ) throws {
        let groups = Dictionary(grouping: operations, by: \.actorID)
        guard Set(groups.keys) == Set(watermarks.map(\.actorID)) else {
            throw FoodArchiveError.actorChainGap("watermark actors")
        }
        for watermark in watermarks {
            let values = (groups[watermark.actorID] ?? []).sorted { $0.actorSequence < $1.actorSequence }
            var previous = watermark.baseHash
            var sequence = watermark.baseSequence
            for value in values {
                guard value.actorSequence == sequence + 1,
                      value.previousOperationHash == previous else {
                    throw FoodArchiveError.actorChainGap(watermark.actorID.rawValue)
                }
                sequence = value.actorSequence
                previous = value.operationHash
            }
            guard sequence == watermark.endSequence, previous == watermark.endHash else {
                throw FoodArchiveError.actorChainGap(watermark.actorID.rawValue)
            }
        }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

public struct FoodArchiveMergeReport: Codable, Equatable, Sendable {
    public let newOperationCount: Int
    public let idempotentOperationCount: Int
    public let explicitConflictIDs: [ConflictID]
    public let requiresConflictResolution: Bool

    public init(
        newOperationCount: Int,
        idempotentOperationCount: Int,
        explicitConflictIDs: [ConflictID]
    ) {
        self.newOperationCount = newOperationCount
        self.idempotentOperationCount = idempotentOperationCount
        self.explicitConflictIDs = explicitConflictIDs.sorted { $0.rawValue < $1.rawValue }
        requiresConflictResolution = !explicitConflictIDs.isEmpty
    }
}

public struct StagedFoodArchive: Sendable {
    public let verified: VerifiedFoodArchive
    public let report: FoodArchiveMergeReport
}

public protocol FoodArchiveStaging: Sendable {
    func validate(_ transactions: [LedgerTransaction]) throws -> FoodArchiveState
}

public struct FoodArchiveImportService: Sendable {
    private let live: any FoodArchiveLedgerAccess
    private let staging: any FoodArchiveStaging
    private let verifier: FoodArchiveVerifier
    private let encoder: any CanonicalEncoding

    public init(
        live: any FoodArchiveLedgerAccess,
        staging: any FoodArchiveStaging,
        verifier: FoodArchiveVerifier = FoodArchiveVerifier(),
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder()
    ) {
        self.live = live
        self.staging = staging
        self.verifier = verifier
        self.encoder = encoder
    }

    public func dryRun(_ bundle: FoodArchiveBundle) throws -> StagedFoodArchive {
        let verified = try verifier.verify(bundle)
        let stagedState = try staging.validate(verified.transactions)
        let stagedProjection = try CanonicalFoodProjection(
            records: stagedState.records,
            summaries: verified.document.projection.summaries,
            encoder: encoder
        )
        guard try encoder.encode(stagedProjection) == encoder.encode(verified.document.projection) else {
            throw FoodArchiveError.stagingMismatch
        }
        var newCount = 0
        var idempotentCount = 0
        for transaction in verified.transactions {
            if let existing = try live.operation(id: transaction.operation.operationID) {
                guard existing.operationHash == transaction.operation.operationHash else {
                    throw FoodArchiveError.divergentOperation(transaction.operation.operationID.rawValue)
                }
                idempotentCount += 1
            } else {
                newCount += 1
            }
        }
        return StagedFoodArchive(
            verified: verified,
            report: FoodArchiveMergeReport(
                newOperationCount: newCount,
                idempotentOperationCount: idempotentCount,
                explicitConflictIDs: verified.document.projection.records.conflicts.map(\.conflictID)
            )
        )
    }

    public func apply(_ staged: StagedFoodArchive) throws -> [CommitOutcome] {
        try live.commitAtomically(staged.verified.transactions)
    }
}
