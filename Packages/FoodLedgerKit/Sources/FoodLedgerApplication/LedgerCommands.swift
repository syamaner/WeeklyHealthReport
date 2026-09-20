import CryptoKit
import Foundation
import FoodLedgerDomain

public enum FoodLedgerStoreError: Error, Equatable, Sendable {
    case protectedDataUnavailable
    case corruptStore
    case unknownSchema(Int)
    case migrationFailed(String)
    case integrityFailure(String)
    case immutableRecord(String)
    case missingReference(String)
    case divergentDuplicateOperation
    case actorSequenceMismatch
    case actorHashMismatch
    case unsupportedOperation
    case attachmentFailure(String)
}

public struct LedgerMutation: Codable, Equatable, Sendable {
    public var evidence: [CaptureEvidence]
    public var assertions: [UserAssertion]
    public var products: [Product]
    public var productVersions: [ProductVersion]
    public var libraryEntries: [LibraryEntry]
    public var libraryEntryVersions: [LibraryEntryVersion]
    public var resolutions: [NutritionResolution]
    public var resolutionVersions: [NutritionResolutionVersion]
    public var logItems: [LogItem]
    public var logItemVersions: [LogItemVersion]
    public var quantityConversions: [QuantityConversionVersion]
    public var plates: [Plate]
    public var plateWeightVersions: [PlateWeightVersion]
    public var candidateDecisions: [CandidateDecision]
    public var conflicts: [LedgerConflict]
    public var sourceReleases: [SourceRelease]
    public var sourceInstallations: [SourceInstallation]

    public init(
        evidence: [CaptureEvidence] = [],
        assertions: [UserAssertion] = [],
        products: [Product] = [],
        productVersions: [ProductVersion] = [],
        libraryEntries: [LibraryEntry] = [],
        libraryEntryVersions: [LibraryEntryVersion] = [],
        resolutions: [NutritionResolution] = [],
        resolutionVersions: [NutritionResolutionVersion] = [],
        logItems: [LogItem] = [],
        logItemVersions: [LogItemVersion] = [],
        quantityConversions: [QuantityConversionVersion] = [],
        plates: [Plate] = [],
        plateWeightVersions: [PlateWeightVersion] = [],
        candidateDecisions: [CandidateDecision] = [],
        conflicts: [LedgerConflict] = [],
        sourceReleases: [SourceRelease] = [],
        sourceInstallations: [SourceInstallation] = []
    ) {
        self.evidence = evidence
        self.assertions = assertions
        self.products = products
        self.productVersions = productVersions
        self.libraryEntries = libraryEntries
        self.libraryEntryVersions = libraryEntryVersions
        self.resolutions = resolutions
        self.resolutionVersions = resolutionVersions
        self.logItems = logItems
        self.logItemVersions = logItemVersions
        self.quantityConversions = quantityConversions
        self.plates = plates
        self.plateWeightVersions = plateWeightVersions
        self.candidateDecisions = candidateDecisions
        self.conflicts = conflicts
        self.sourceReleases = sourceReleases
        self.sourceInstallations = sourceInstallations
    }

    public var isEmpty: Bool {
        evidence.isEmpty && assertions.isEmpty && products.isEmpty && productVersions.isEmpty &&
        libraryEntries.isEmpty && libraryEntryVersions.isEmpty && resolutions.isEmpty &&
        resolutionVersions.isEmpty && logItems.isEmpty && logItemVersions.isEmpty &&
        quantityConversions.isEmpty && plates.isEmpty && plateWeightVersions.isEmpty &&
        candidateDecisions.isEmpty && conflicts.isEmpty && sourceReleases.isEmpty
            && sourceInstallations.isEmpty
    }

    public var affectedIDs: [String] {
        var ids: [String] = []
        ids += evidence.map(\.evidenceID.rawValue)
        ids += assertions.map(\.assertionID.rawValue)
        ids += products.map(\.productID.rawValue)
        ids += productVersions.map(\.productVersionID.rawValue)
        ids += libraryEntries.map(\.libraryEntryID.rawValue)
        ids += libraryEntryVersions.map(\.libraryEntryVersionID.rawValue)
        ids += resolutions.map(\.resolutionID.rawValue)
        ids += resolutionVersions.map(\.resolutionVersionID.rawValue)
        ids += logItems.map(\.logItemID.rawValue)
        ids += logItemVersions.map(\.logItemVersionID.rawValue)
        ids += quantityConversions.map(\.quantityConversionVersionID.rawValue)
        ids += plates.map(\.plateID.rawValue)
        ids += plateWeightVersions.map(\.plateWeightVersionID.rawValue)
        ids += candidateDecisions.map(\.candidateDecisionID.rawValue)
        ids += conflicts.map(\.conflictID.rawValue)
        ids += sourceReleases.map(\.sourceReleaseID.value)
        ids += sourceInstallations.map(\.sourceReleaseID.value)
        return ids.sorted()
    }
}

public struct LedgerOperationType: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard let marker = rawValue.range(of: "_v", options: .backwards),
              marker.lowerBound != rawValue.startIndex,
              let version = Int(rawValue[marker.upperBound...]),
              version > 0 else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let type = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid versioned operation type"
            )
        }
        self = type
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let recordEvidence = Self(rawValue: "record_evidence_v1")!
    public static let createProduct = Self(rawValue: "create_product_v1")!
    public static let reformulateProduct = Self(rawValue: "reformulate_product_v1")!
    public static let correctResolution = Self(rawValue: "correct_resolution_v1")!
    public static let saveLibraryEntry = Self(rawValue: "save_library_entry_v1")!
    public static let recordLogItem = Self(rawValue: "record_log_item_v1")!
    public static let correctLogItem = Self(rawValue: "correct_log_item_v1")!
    public static let recordQuantityConversion = Self(rawValue: "record_quantity_conversion_v1")!
    public static let recordPlateWeight = Self(rawValue: "record_plate_weight_v1")!
    public static let recordCandidateDecision = Self(rawValue: "record_candidate_decision_v1")!
    public static let preserveConflict = Self(rawValue: "preserve_conflict_v1")!
    public static let installSourceRelease = Self(rawValue: "install_source_release_v1")!
    public static let composite = Self(rawValue: "composite_v1")!

    public static let builtInV1: Set<Self> = [
        .recordEvidence, .createProduct, .reformulateProduct, .correctResolution,
        .saveLibraryEntry, .recordLogItem, .correctLogItem, .recordQuantityConversion,
        .recordPlateWeight, .recordCandidateDecision, .preserveConflict,
        .installSourceRelease, .composite
    ]
}

public struct LedgerOperationRegistry: Sendable {
    private let supported: Set<LedgerOperationType>

    public init(supported: Set<LedgerOperationType>) {
        self.supported = supported
    }

    public func requireSupported(_ type: LedgerOperationType) throws {
        guard supported.contains(type) else { throw FoodLedgerStoreError.unsupportedOperation }
    }

    public static let builtInV1 = LedgerOperationRegistry(supported: LedgerOperationType.builtInV1)
}

public struct ActorHead: Codable, Equatable, Sendable {
    public let sequence: Int
    public let operationHash: FoodLedgerDomain.SHA256Digest?

    public init(sequence: Int, operationHash: FoodLedgerDomain.SHA256Digest?) {
        self.sequence = sequence
        self.operationHash = operationHash
    }
}

public struct LedgerOperation: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let operationID: OperationID
    public let actorID: ActorID
    public let actorSequence: Int
    public let operationType: LedgerOperationType
    public let createdAt: Date
    public let affectedIDs: [String]
    public let payload: Data
    public let payloadHash: FoodLedgerDomain.SHA256Digest
    public let previousOperationHash: FoodLedgerDomain.SHA256Digest?
    public let operationHash: FoodLedgerDomain.SHA256Digest
    public let idempotencyKey: LedgerText?

    public init(
        operationID: OperationID,
        actorID: ActorID,
        actorSequence: Int,
        operationType: LedgerOperationType,
        createdAt: Date,
        affectedIDs: [String],
        payload: Data,
        payloadHash: FoodLedgerDomain.SHA256Digest,
        previousOperationHash: FoodLedgerDomain.SHA256Digest?,
        operationHash: FoodLedgerDomain.SHA256Digest,
        idempotencyKey: LedgerText?
    ) {
        self.operationID = operationID
        self.actorID = actorID
        self.actorSequence = actorSequence
        self.operationType = operationType
        self.createdAt = createdAt
        self.affectedIDs = affectedIDs
        self.payload = payload
        self.payloadHash = payloadHash
        self.previousOperationHash = previousOperationHash
        self.operationHash = operationHash
        self.idempotencyKey = idempotencyKey
    }
}

public struct UnsignedLedgerOperation: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let operationID: OperationID
    public let actorID: ActorID
    public let actorSequence: Int
    public let operationType: LedgerOperationType
    public let createdAt: Date
    public let affectedIDs: [String]
    public let payloadHash: FoodLedgerDomain.SHA256Digest
    public let previousOperationHash: FoodLedgerDomain.SHA256Digest?
    public let idempotencyKey: LedgerText?

    public init(
        schemaVersion: Int,
        operationID: OperationID,
        actorID: ActorID,
        actorSequence: Int,
        operationType: LedgerOperationType,
        createdAt: Date,
        affectedIDs: [String],
        payloadHash: FoodLedgerDomain.SHA256Digest,
        previousOperationHash: FoodLedgerDomain.SHA256Digest?,
        idempotencyKey: LedgerText?
    ) {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.actorID = actorID
        self.actorSequence = actorSequence
        self.operationType = operationType
        self.createdAt = createdAt
        self.affectedIDs = affectedIDs
        self.payloadHash = payloadHash
        self.previousOperationHash = previousOperationHash
        self.idempotencyKey = idempotencyKey
    }
}

public struct LedgerTransaction: Equatable, Sendable {
    public let mutation: LedgerMutation
    public let operation: LedgerOperation

    public init(mutation: LedgerMutation, operation: LedgerOperation) {
        self.mutation = mutation
        self.operation = operation
    }
}

public enum CommitOutcome: Equatable, Sendable {
    case committed(LedgerOperation)
    case idempotent(LedgerOperation)
}

public protocol LedgerCommandCommitting: Sendable {
    func actorHead(for actorID: ActorID) throws -> ActorHead
    func operation(id: OperationID) throws -> LedgerOperation?
    func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome
}

public struct LedgerCounts: Equatable, Sendable {
    public let evidence: Int
    public let productVersions: Int
    public let resolutionVersions: Int
    public let logItemVersions: Int
    public let conflicts: Int
    public let operations: Int

    public init(
        evidence: Int,
        productVersions: Int,
        resolutionVersions: Int,
        logItemVersions: Int,
        conflicts: Int,
        operations: Int
    ) {
        self.evidence = evidence
        self.productVersions = productVersions
        self.resolutionVersions = resolutionVersions
        self.logItemVersions = logItemVersions
        self.conflicts = conflicts
        self.operations = operations
    }
}

public protocol LedgerReading: Sendable {
    func counts() throws -> LedgerCounts
    func productVersions(productID: ProductID) throws -> [ProductVersion]
    func resolutionVersion(id: ResolutionVersionID) throws -> NutritionResolutionVersion?
    func exactLibraryEntries(alias: LedgerText) throws -> [LibraryEntryVersion]
    func conflicts() throws -> [LedgerConflict]
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease?
}

public protocol CanonicalEncoding: Sendable {
    func encode<T: Encodable & Sendable>(_ value: T) throws -> Data
}

public protocol Digesting: Sendable {
    func sha256(_ data: Data) throws -> FoodLedgerDomain.SHA256Digest
}

public protocol LedgerClock: Sendable {
    func now() -> Date
}

public protocol LedgerIDGenerating: Sendable {
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag>
}

public protocol EvidenceAttachmentStoring: Sendable {
    func persist(_ bytes: Data, mediaKind: LedgerText) throws -> AttachmentDescriptor
    func removeIfUnreferenced(_ descriptor: AttachmentDescriptor) throws
}

public protocol SourceReleaseInstalling: Sendable {
    func installSourceRelease(
        _ release: SourceRelease,
        installation: SourceInstallation,
        operationID: OperationID,
        idempotencyKey: LedgerText?
    ) throws -> CommitOutcome
}

public struct FoundationCanonicalJSONEncoder: CanonicalEncoding {
    public init() {}

    public func encode<T: Encodable & Sendable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }
}

public struct SHA256Digester: Digesting {
    public init() {}

    public func sha256(_ data: Data) throws -> FoodLedgerDomain.SHA256Digest {
        try FoodLedgerDomain.SHA256Digest(
            CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }
}

public struct SystemLedgerClock: LedgerClock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct RandomLedgerIDGenerator: LedgerIDGenerating {
    public init() {}
    public func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        try LedgerID(UUID().uuidString.lowercased())
    }
}

public struct OperationVerifier: Sendable {
    private let encoder: any CanonicalEncoding
    private let digester: any Digesting
    private let operationRegistry: LedgerOperationRegistry

    public init(
        encoder: any CanonicalEncoding,
        digester: any Digesting,
        operationRegistry: LedgerOperationRegistry = .builtInV1
    ) {
        self.encoder = encoder
        self.digester = digester
        self.operationRegistry = operationRegistry
    }

    public func verify(_ transaction: LedgerTransaction) throws {
        let payload = try encoder.encode(transaction.mutation)
        guard payload == transaction.operation.payload,
              transaction.mutation.affectedIDs == transaction.operation.affectedIDs else {
            throw FoodLedgerStoreError.integrityFailure("operation payload")
        }
        try verifyStored(transaction.operation)
    }

    public func verifyStored(_ operation: LedgerOperation) throws {
        try operationRegistry.requireSupported(operation.operationType)
        guard operation.actorSequence > 0 else {
            throw FoodLedgerStoreError.actorSequenceMismatch
        }
        guard try digester.sha256(operation.payload) == operation.payloadHash else {
            throw FoodLedgerStoreError.integrityFailure("operation payload hash")
        }
        let unsigned = UnsignedLedgerOperation(
            schemaVersion: LedgerOperation.schemaVersion,
            operationID: operation.operationID,
            actorID: operation.actorID,
            actorSequence: operation.actorSequence,
            operationType: operation.operationType,
            createdAt: operation.createdAt,
            affectedIDs: operation.affectedIDs,
            payloadHash: operation.payloadHash,
            previousOperationHash: operation.previousOperationHash,
            idempotencyKey: operation.idempotencyKey
        )
        guard try digester.sha256(encoder.encode(unsigned)) == operation.operationHash else {
            throw FoodLedgerStoreError.integrityFailure("operation hash")
        }
    }
}
