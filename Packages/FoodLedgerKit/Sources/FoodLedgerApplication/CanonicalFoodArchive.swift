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
    /// The highest contract this binary reads and writes (7: pasted-label evidence).
    public static let foodContractVersion = 7
    /// The contract an export carries when its records need no more: unchanged from contract 6,
    /// so a store without pasted-label evidence exports exactly the bytes it did before contract 7.
    public static let exportFloorContractVersion = 6
    public static let dailySchemaVersion = 4

    /// The contract an export of these records carries: contract 7 only when pasted-label
    /// evidence exists, otherwise the contract-6 floor as before.
    public static func exportContractVersion(for records: LedgerMutation, favourites: FavouriteMutation = FavouriteMutation()) -> Int {
        max(exportFloorContractVersion, minimumContractVersion(for: records, favourites: favourites))
    }

    public let foodContractVersion: Int
    public let dailySchemaVersion: Int
    public let records: LedgerMutation
    public let summaries: [CanonicalFoodNutritionSummary]
    /// Favourite records (contract 6). Encoded only when non-empty, so a projection without
    /// favourites keeps exactly the bytes of earlier contracts.
    public let favourites: FavouriteMutation

    public init(
        records: LedgerMutation,
        summaries: [CanonicalFoodNutritionSummary] = [],
        favourites: FavouriteMutation = FavouriteMutation(),
        foodContractVersion: Int? = nil,
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder()
    ) throws {
        let foodContractVersion = foodContractVersion ?? Self.exportContractVersion(for: records, favourites: favourites)
        guard (1...Self.foodContractVersion).contains(foodContractVersion),
              foodContractVersion >= Self.minimumContractVersion(for: records, favourites: favourites) else { throw FoodArchiveError.unsupportedFoodContract(foodContractVersion) }
        self.foodContractVersion = foodContractVersion
        dailySchemaVersion = Self.dailySchemaVersion
        self.records = try Self.sorted(records, encoder: encoder)
        self.summaries = try Self.sort(summaries, encoder: encoder)
        self.favourites = FavouriteMutation(
            favourites: try Self.sort(favourites.favourites, encoder: encoder),
            favouriteVersions: try Self.sort(favourites.favouriteVersions, encoder: encoder),
            arrangements: try Self.sort(favourites.arrangements, encoder: encoder))
    }

    enum CodingKeys: String, CodingKey { case foodContractVersion, dailySchemaVersion, records, summaries, favourites }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        foodContractVersion = try values.decode(Int.self, forKey: .foodContractVersion)
        dailySchemaVersion = try values.decode(Int.self, forKey: .dailySchemaVersion)
        records = try values.decode(LedgerMutation.self, forKey: .records)
        summaries = try values.decode([CanonicalFoodNutritionSummary].self, forKey: .summaries)
        let favourites = try values.decodeIfPresent(FavouriteMutation.self, forKey: .favourites)
        // An explicitly empty member is not a canonical encoding.
        if let favourites, favourites.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .favourites, in: values, debugDescription: "Empty favourites member")
        }
        self.favourites = favourites ?? FavouriteMutation()
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(foodContractVersion, forKey: .foodContractVersion)
        try values.encode(dailySchemaVersion, forKey: .dailySchemaVersion)
        try values.encode(records, forKey: .records)
        try values.encode(summaries, forKey: .summaries)
        if !favourites.isEmpty { try values.encode(favourites, forKey: .favourites) }
    }

    /// Lowest contract that can carry these records. Contract 7 (pasted-label evidence) is
    /// checked first, before the contract 6 early returns, so an archive with both favourites
    /// and a pasted label is never reported as contract 6. Then contract 6: any favourite
    /// record, app reference provenance or reference definition evidence.
    public static func minimumContractVersion(for records: LedgerMutation, favourites: FavouriteMutation = FavouriteMutation()) -> Int {
        if records.evidence.contains(where: { $0.captureMethodVersion.value == PastedLabelManifest.version }) { return 7 }
        if !favourites.isEmpty { return 6 }
        if records.evidence.contains(where: { $0.kind == .referenceDefinition }) { return 6 }
        let provenance = records.resolutionVersions.flatMap { $0.nutrients.entries }
            + records.candidateDecisions.flatMap { $0.candidate.nutrients.entries }
        if provenance.contains(where: { entry in
            ([entry.value] + entry.conflictCandidates).contains { $0.provenance.contains { $0.sourceKind == .appReferenceDefinition } }
        }) { return 6 }
        // Reviewed web manifest v2 (single review action, recorded gate): contract 5.
        if records.evidence.contains(where: { $0.captureMethodVersion.value == ReviewedFoodProposalConfirmation.version }) { return 5 }
        if records.assertions.contains(where: { $0.confirmation != nil }) { return 4 }
        if records.logItemVersions.contains(where: { $0.weightDeclaration != nil }) { return 3 }
        return records.logItemVersions.contains { log in
            if case .removed = log.composition { return true }
            return log.plateWeightVersionID != nil
        } ? 2 : 1
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
    public let favourites: FavouriteMutation

    public init(
        records: LedgerMutation,
        operations: [LedgerOperation],
        summaries: [CanonicalFoodNutritionSummary] = [],
        favourites: FavouriteMutation = FavouriteMutation()
    ) {
        self.records = records
        self.operations = operations
        self.summaries = summaries
        self.favourites = favourites
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
        members: [FoodArchiveMember],
        foodContractVersion: Int = CanonicalFoodProjection.exportFloorContractVersion
    ) throws {
        backupFormatVersion = Self.currentBackupFormatVersion
        guard (1...CanonicalFoodProjection.foodContractVersion).contains(foodContractVersion) else {
            throw FoodArchiveError.unsupportedFoodContract(foodContractVersion)
        }
        self.foodContractVersion = foodContractVersion
        dailySchemaVersion = CanonicalFoodProjection.dailySchemaVersion
        self.ledgerID = ledgerID
        self.snapshotID = snapshotID
        self.createdAt = createdAt
        self.creatingActorID = creatingActorID
        migrationIdentifiers = foodContractVersion == 1 ? [try LedgerText("food-ledger-v1")]
            : foodContractVersion == 2 ? [try LedgerText("food-ledger-v1"), try LedgerText("food-ledger-v2")]
            : foodContractVersion == 3 ? [try LedgerText("food-ledger-v1"), try LedgerText("food-ledger-v2"), try LedgerText("food-ledger-v3")]
            : foodContractVersion == 4 ? [try LedgerText("food-ledger-v1"), try LedgerText("food-ledger-v2"), try LedgerText("food-ledger-v3"), try LedgerText("food-ledger-v4")]
            : foodContractVersion == 5 ? [try LedgerText("food-ledger-v1"), try LedgerText("food-ledger-v2"), try LedgerText("food-ledger-v3"), try LedgerText("food-ledger-v4"), try LedgerText("food-ledger-v5")]
            : try (1...foodContractVersion).map { try LedgerText("food-ledger-v\($0)") }
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
            favourites: state.favourites,
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
            recordCount: Self.recordCount(projection.records, favourites: projection.favourites),
            operationCount: sortedOperations.count,
            members: members,
            foodContractVersion: projection.foodContractVersion
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

    /// Every record of the projection: ledger records plus favourite records.
    static func recordCount(_ records: LedgerMutation, favourites: FavouriteMutation) -> Int {
        favourites.recordCount + records.evidence.count + records.assertions.count + records.products.count
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
        operationRegistry: LedgerOperationRegistry = .builtInV6
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
        guard (1...CanonicalFoodProjection.foodContractVersion).contains(manifest.foodContractVersion) else {
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
        guard document.projection.foodContractVersion == manifest.foodContractVersion else {
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
        guard manifest.foodContractVersion >= CanonicalFoodProjection.minimumContractVersion(
            for: document.projection.records, favourites: document.projection.favourites)
        else { throw FoodArchiveError.unsupportedFoodContract(manifest.foodContractVersion) }
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
              FoodArchiveGenerator.recordCount(document.projection.records, favourites: document.projection.favourites)
                == manifest.recordCount,
              sourceReleaseIDs == manifest.sourceReleaseIDs,
              try encoder.encode(document) == bundle.snapshot else {
            throw FoodArchiveError.snapshotMismatch
        }

        let operations = try decodeOperations(bundle.operations, decoder: decoder)
        guard operations.count == manifest.operationCount else {
            throw FoodArchiveError.memberMismatch("operation count")
        }
        // The operation type selects the payload case; the verifier re-encodes that case and
        // checks it against the stored payload bytes and hash.
        let transactions = try operations.map { operation -> LedgerTransaction in
            let payload: LedgerPayload
            do { payload = try LedgerPayload.decode(operation.payload, type: operation.operationType) }
            catch { throw FoodArchiveError.malformedArchive("operation payload") }
            let transaction = LedgerTransaction(payload: payload, operation: operation)
            try operationVerifier.verify(transaction)
            return transaction
        }
        if transactions.contains(where: { transaction in
            let type = transaction.operation.operationType
            let required = LedgerOperationType.favouriteTypes.contains(type) ? 6
                : type == .confirmFoodV3 ? 4
                : LedgerOperationType.declaredQuantityTypes.contains(type) ? 3
                : [.removeLogItem, .restoreLogItem].contains(type) ? 2 : 1
            return max(required, CanonicalFoodProjection.minimumContractVersion(
                for: transaction.mutation, favourites: transaction.favourites)) > manifest.foodContractVersion
        }) { throw FoodArchiveError.unsupportedFoodContract(manifest.foodContractVersion) }
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
            favourites: stagedState.favourites,
            foodContractVersion: verified.document.projection.foodContractVersion,
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
