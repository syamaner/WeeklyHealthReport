import Foundation

struct DriveFileMetadata: Equatable, Sendable {
    let id: String
    let name: String
    let mimeType: String
    let parents: [String]
    let trashed: Bool
    let driveID: String?
    let isAppAuthorized: Bool
    let canEdit: Bool
    let appProperties: [String: String]
}

struct DriveUploadDescriptor: Equatable, Sendable {
    let id: String
    let name: String
    let parentID: String
    let appProperties: [String: String]
}

protocol DriveTransporting: Sendable {
    func account(accessToken: String) async throws -> DriveAccount
    func generateFileID(accessToken: String) async throws -> String
    func createFile(
        _ descriptor: DriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws
    func updateFile(
        _ descriptor: DriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws
    func fileMetadata(id: String, accessToken: String) async throws -> DriveFileMetadata
    func fileContent(id: String, accessToken: String) async throws -> Data
}

enum SyntheticCredentialFailure: String, Error, Equatable, Sendable {
    case expired
    case denied
    case revoked
}

struct VerifiedSyntheticSnapshot: Codable, Equatable, Sendable {
    let generation: Int
    let payloadSHA256: String
    let verifiedAt: Date
}

struct PendingSyntheticOperation: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case create, update }
    enum Phase: String, Codable, Sendable { case reserved, submitted, uncertain }

    let operationID: String
    let generation: Int
    let payloadSHA256: String
    let kind: Kind
    var phase: Phase
}

struct CanonicalExportIdentity: Codable, Equatable, Sendable {
    let accountID: String
    let folderID: String
    let reportDate: String
    let fileID: String
    let installationID: String
    var lastVerified: VerifiedSyntheticSnapshot?
    var pending: PendingSyntheticOperation?
}

struct CanonicalExportRegistry: Codable, Equatable, Sendable {
    static let formatVersion = 1

    let version: Int
    var installationID: String
    var identities: [CanonicalExportIdentity]

    init(installationID: String = UUID().uuidString, identities: [CanonicalExportIdentity] = []) {
        version = Self.formatVersion
        self.installationID = installationID
        self.identities = identities
    }

    func exactIndex(accountID: String, folderID: String, reportDate: String) -> Int? {
        identities.firstIndex {
            $0.accountID == accountID && $0.folderID == folderID && $0.reportDate == reportDate
        }
    }

    func hasDifferentDestination(accountID: String, folderID: String, reportDate: String) -> Bool {
        identities.contains {
            $0.reportDate == reportDate && ($0.accountID != accountID || $0.folderID != folderID)
        }
    }
}

protocol CanonicalExportIdentityPersisting: Sendable {
    func load() throws -> CanonicalExportRegistry?
    func installationMarker() throws -> String?
    func save(_ registry: CanonicalExportRegistry) throws
}

struct KeychainCanonicalExportIdentityStore: CanonicalExportIdentityPersisting, Sendable {
    private static let key = "google.drive.canonical-export-identities"
    private static let markerKey = "google.drive.canonical-export-installation"
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func load() throws -> CanonicalExportRegistry? {
        guard let data = try keychain.load(account: Self.key) else { return nil }
        let registry = try JSONDecoder().decode(CanonicalExportRegistry.self, from: data)
        guard registry.version == CanonicalExportRegistry.formatVersion,
              try installationMarker() == registry.installationID else {
            throw CanonicalExportFailure.identityRecoveryAmbiguous
        }
        return registry
    }

    func installationMarker() throws -> String? {
        guard let data = try keychain.load(account: Self.markerKey) else { return nil }
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw CanonicalExportFailure.identityRecoveryAmbiguous
        }
        return value
    }

    func save(_ registry: CanonicalExportRegistry) throws {
        if let marker = try installationMarker() {
            guard marker == registry.installationID else {
                throw CanonicalExportFailure.identityRecoveryAmbiguous
            }
        } else {
            try keychain.save(Data(registry.installationID.utf8), account: Self.markerKey)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try keychain.save(encoder.encode(registry), account: Self.key)
    }
}

enum CanonicalExportFailure: Error, Equatable, Sendable {
    case busy
    case invalidSyntheticPayload
    case staleGeneration
    case destinationChangeRequiresMigration
    case accountMismatch
    case identityRecoveryAmbiguous
    case staleCompletion
    case credentials(SyntheticCredentialFailure)
    case credentialsRejected
    case permissionDenied
    case quotaExceeded
    case rateLimited
    case remoteMissing
    case remoteMoved
    case remoteTrashed
    case remoteMetadataMismatch
    case remoteContentMismatch
    case unresolvedRequest
    case persistenceFailure
    case transportFailure
}

enum CanonicalExportResult: Equatable, Sendable {
    case verified(generation: Int, created: Bool)
    case unchangedVerified(generation: Int)
    case cancelledBeforeSubmission
    case cancelledAfterSubmissionVerified(generation: Int, created: Bool)
}

enum CanonicalRecoveryResult: Equatable, Sendable {
    case recovered(generation: Int)
    case alreadyTracked(generation: Int)
}

enum CanonicalMetadataKeys {
    static let owner = "whrSyntheticCanonical"
    static let ownerValue = "v1"
    static let reportDate = "whrReportDate"
    static let installationID = "whrInstallationID"
    static let generation = "whrGeneration"
    static let payloadSHA256 = "whrPayloadSHA256"
}
