import CryptoKit
import Foundation

public struct VerifiedDailyDriveSnapshot: Codable, Equatable, Sendable {
    public let dataAsOf: String
    public let payloadSHA256: String
    public let verifiedAt: Date

    public init(dataAsOf: String, payloadSHA256: String, verifiedAt: Date) {
        self.dataAsOf = dataAsOf
        self.payloadSHA256 = payloadSHA256
        self.verifiedAt = verifiedAt
    }
}

public struct PendingDailyDriveOperation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case create, update }
    public enum Phase: String, Codable, Sendable { case reserved, submitted, uncertain }

    public let operationID: String
    public let dataAsOf: String
    public let payloadSHA256: String
    public let kind: Kind
    public var phase: Phase

    public init(operationID: String, dataAsOf: String, payloadSHA256: String, kind: Kind, phase: Phase) {
        self.operationID = operationID
        self.dataAsOf = dataAsOf
        self.payloadSHA256 = payloadSHA256
        self.kind = kind
        self.phase = phase
    }
}

public struct DailyDriveExportIdentity: Codable, Equatable, Sendable {
    public let accountID: String
    public let folderID: String
    public let reportDate: String
    public let fileID: String
    public let installationID: String
    public var lastVerified: VerifiedDailyDriveSnapshot?
    public var pending: PendingDailyDriveOperation?

    public init(accountID: String, folderID: String, reportDate: String, fileID: String, installationID: String, lastVerified: VerifiedDailyDriveSnapshot?, pending: PendingDailyDriveOperation?) {
        self.accountID = accountID
        self.folderID = folderID
        self.reportDate = reportDate
        self.fileID = fileID
        self.installationID = installationID
        self.lastVerified = lastVerified
        self.pending = pending
    }
}

public struct DailyDriveExportRegistry: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public let version: Int
    public var installationID: String
    public var identities: [DailyDriveExportIdentity]

    public init(
        installationID: String = UUID().uuidString,
        identities: [DailyDriveExportIdentity] = []
    ) {
        version = Self.formatVersion
        self.installationID = installationID
        self.identities = identities
    }

    public func exactIndex(accountID: String, folderID: String, reportDate: String) -> Int? {
        identities.firstIndex {
            $0.accountID == accountID && $0.folderID == folderID && $0.reportDate == reportDate
        }
    }

    public func hasDifferentDestination(
        accountID: String,
        folderID: String,
        reportDate: String
    ) -> Bool {
        identities.contains {
            $0.reportDate == reportDate && ($0.accountID != accountID || $0.folderID != folderID)
        }
    }
}

public protocol DailyDriveExportIdentityPersisting: Sendable {
    func load() throws -> DailyDriveExportRegistry?
    func installationMarker() throws -> String?
    func save(_ registry: DailyDriveExportRegistry) throws
}

public struct KeychainDailyDriveExportIdentityStore: DailyDriveExportIdentityPersisting, Sendable {
    private let registryKey: String
    private let markerKey: String
    private let keychain: any DailyDriveSecurePersisting

    public init(
        keychain: any DailyDriveSecurePersisting = DailyDriveKeychainStore(),
        registryKey: String,
        markerKey: String
    ) {
        self.keychain = keychain
        self.registryKey = registryKey
        self.markerKey = markerKey
    }

    public func load() throws -> DailyDriveExportRegistry? {
        guard let data = try keychain.load(account: registryKey) else { return nil }
        let registry = try JSONDecoder().decode(DailyDriveExportRegistry.self, from: data)
        guard registry.version == DailyDriveExportRegistry.formatVersion,
              try installationMarker() == registry.installationID else {
            throw DailyDriveExportFailure.identityRecoveryAmbiguous
        }
        return registry
    }

    public func installationMarker() throws -> String? {
        guard let data = try keychain.load(account: markerKey) else { return nil }
        guard let marker = String(data: data, encoding: .utf8), !marker.isEmpty else {
            throw DailyDriveExportFailure.identityRecoveryAmbiguous
        }
        return marker
    }

    public func save(_ registry: DailyDriveExportRegistry) throws {
        if let marker = try installationMarker() {
            guard marker == registry.installationID else {
                throw DailyDriveExportFailure.identityRecoveryAmbiguous
            }
        } else {
            try keychain.save(Data(registry.installationID.utf8), account: markerKey)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try keychain.save(encoder.encode(registry), account: registryKey)
    }
}

public enum DailyDriveCredentialFailure: String, Error, Equatable, Sendable {
    case expired
    case denied
    case revoked
    case missing
    case indeterminate
}

public enum DailyDriveExportFailure: Error, Equatable, Sendable {
    case busy
    case invalidPayload
    case staleSnapshot
    case destinationChangeRequiresMigration
    case accountMismatch
    case identityRecoveryAmbiguous
    case staleCompletion
    case credentials(DailyDriveCredentialFailure)
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

public enum DailyDriveExportResult: Equatable, Sendable {
    case verified(dataAsOf: String, created: Bool)
    case unchangedVerified(dataAsOf: String)
    case cancelledBeforeSubmission
    case cancelledAfterSubmissionVerified(dataAsOf: String, created: Bool)
}

public enum DailyDriveRecoveryResult: Equatable, Sendable {
    case recovered(dataAsOf: String)
    case alreadyTracked(dataAsOf: String)
    case migrated(dataAsOf: String)
}

public enum DailyDriveMetadataKeys {
    public static let ownerValue = "v1"
    public static let reportDate = "whrReportDate"
    public static let installationID = "whrInstallationID"
    public static let payloadSHA256 = "whrPayloadSHA256"
}

public struct DrivePayloadIdentity: Equatable, Sendable {
    public let orderingToken: String
    public let payloadSHA256: String

    public init(orderingToken: String, payloadSHA256: String) {
        self.orderingToken = orderingToken
        self.payloadSHA256 = payloadSHA256
    }
}

public protocol DrivePayloadIdentityPolicy: Sendable {
    func validate(payload: Data, reportDate: String) throws -> DrivePayloadIdentity
    func compare(_ lhs: String, _ rhs: String) throws -> ComparisonResult
    func filename(for reportDate: String) -> String
    var ownerPropertyKey: String { get }
    var orderingPropertyKey: String { get }
}

public actor DailyDriveExportCoordinator {
    public typealias TokenProvider = @Sendable (_ forceRefresh: Bool) async throws -> String

    private enum Reconciliation {
        case expected
        case previous
        case missing
        case mismatch
    }

    private let transport: any DailyDriveTransporting
    private let store: any DailyDriveExportIdentityPersisting
    private let policy: any DrivePayloadIdentityPolicy
    private var activeOperationID: String?
    private var cancellationRequested = false

    public init(
        transport: any DailyDriveTransporting,
        store: any DailyDriveExportIdentityPersisting,
        policy: any DrivePayloadIdentityPolicy
    ) {
        self.transport = transport
        self.store = store
        self.policy = policy
    }

    public func requestCancellation() {
        guard activeOperationID != nil else { return }
        cancellationRequested = true
    }

    public func abandonDestination(accountID: String, folderID: String) throws {
        try abandonIdentities {
            $0.accountID == accountID && $0.folderID == folderID
        }
    }

    public func abandonFileIdentity(accountID: String, folderID: String, reportDate: String) throws {
        try abandonIdentities {
            $0.accountID == accountID
                && $0.folderID == folderID
                && $0.reportDate == reportDate
        }
    }

    private func abandonIdentities(
        matching predicate: (DailyDriveExportIdentity) -> Bool
    ) throws {
        guard activeOperationID == nil else { throw DailyDriveExportFailure.busy }
        do {
            guard var registry = try store.load() else {
                guard try store.installationMarker() == nil else {
                    throw DailyDriveExportFailure.identityRecoveryAmbiguous
                }
                return
            }
            registry.identities.removeAll(where: predicate)
            try persist(registry)
        } catch let failure as DailyDriveExportFailure {
            throw failure
        } catch is DecodingError {
            throw DailyDriveExportFailure.identityRecoveryAmbiguous
        } catch {
            throw DailyDriveExportFailure.persistenceFailure
        }
    }

    public func export(
        payload: Data,
        reportDate: String,
        accountID: String,
        folderID: String,
        tokenProvider: @escaping TokenProvider
    ) async throws -> DailyDriveExportResult {
        guard activeOperationID == nil else { throw DailyDriveExportFailure.busy }
        let payloadIdentity = try validatedPayload(payload, reportDate: reportDate)
        let operationID = UUID().uuidString
        activeOperationID = operationID
        cancellationRequested = false
        defer {
            if activeOperationID == operationID { activeOperationID = nil }
            cancellationRequested = false
        }

        do {
            var registry = try loadOrCreateRegistry()
            guard !registry.hasDifferentDestination(
                accountID: accountID,
                folderID: folderID,
                reportDate: reportDate
            ) else {
                throw DailyDriveExportFailure.destinationChangeRequiresMigration
            }

            var token = try await validatedToken(
                forceRefresh: false,
                expectedAccountID: accountID,
                tokenProvider: tokenProvider
            )
            let index: Int

            if let existingIndex = registry.exactIndex(
                accountID: accountID,
                folderID: folderID,
                reportDate: reportDate
            ) {
                index = existingIndex
            } else {
                let fileID: String
                do {
                    fileID = try await transport.generateFileID(accessToken: token)
                } catch {
                    throw map(error)
                }
                try ensureActive(operationID)
                registry.identities.append(DailyDriveExportIdentity(
                    accountID: accountID,
                    folderID: folderID,
                    reportDate: reportDate,
                    fileID: fileID,
                    installationID: registry.installationID,
                    lastVerified: nil,
                    pending: PendingDailyDriveOperation(
                        operationID: operationID,
                        dataAsOf: payloadIdentity.orderingToken,
                        payloadSHA256: payloadIdentity.payloadSHA256,
                        kind: .create,
                        phase: .reserved
                    )
                ))
                index = registry.identities.count - 1
                try persist(registry)
            }

            var identity = registry.identities[index]
            if let verified = identity.lastVerified {
                let ordering = try compare(payloadIdentity.orderingToken, verified.dataAsOf)
                guard ordering != .orderedAscending else {
                    throw DailyDriveExportFailure.staleSnapshot
                }
                if ordering == .orderedSame {
                    guard verified.payloadSHA256 == payloadIdentity.payloadSHA256 else {
                        throw DailyDriveExportFailure.staleSnapshot
                    }
                    let reconciled = try await reconcile(
                        identity: identity,
                        expectedPayload: payload,
                        token: token
                    )
                    guard reconciled == .previous else {
                        throw failure(for: reconciled)
                    }
                    return .unchangedVerified(dataAsOf: verified.dataAsOf)
                }
            }

            if let pending = identity.pending {
                if pending.phase != .reserved {
                    guard pending.dataAsOf == payloadIdentity.orderingToken,
                          pending.payloadSHA256 == payloadIdentity.payloadSHA256 else {
                        throw DailyDriveExportFailure.unresolvedRequest
                    }
                    let reconciled = try await reconcile(
                        identity: identity,
                        expectedPayload: payload,
                        token: token
                    )
                    if reconciled == .expected {
                        try finalize(
                            operationID: pending.operationID,
                            dataAsOf: pending.dataAsOf,
                            hash: pending.payloadSHA256,
                            registry: &registry,
                            index: index
                        )
                        return .verified(
                            dataAsOf: pending.dataAsOf,
                            created: pending.kind == .create
                        )
                    }
                    guard reconciled == .missing || reconciled == .previous else {
                        throw failure(for: reconciled)
                    }
                }
                identity = registry.identities[index]
                identity.pending = PendingDailyDriveOperation(
                    operationID: operationID,
                    dataAsOf: payloadIdentity.orderingToken,
                    payloadSHA256: payloadIdentity.payloadSHA256,
                    kind: pending.kind,
                    phase: .reserved
                )
                registry.identities[index] = identity
                try persist(registry)
            } else {
                identity.pending = PendingDailyDriveOperation(
                    operationID: operationID,
                    dataAsOf: payloadIdentity.orderingToken,
                    payloadSHA256: payloadIdentity.payloadSHA256,
                    kind: .update,
                    phase: .reserved
                )
                registry.identities[index] = identity
                try persist(registry)
            }

            if cancellationRequested || Task.isCancelled {
                if registry.identities[index].lastVerified != nil {
                    registry.identities[index].pending = nil
                    try persist(registry)
                }
                return .cancelledBeforeSubmission
            }

            registry.identities[index].pending?.phase = .submitted
            try persist(registry)
            let submitted = registry.identities[index]
            let descriptor = descriptor(for: submitted)
            var retriedUncertainSubmission = false

            while true {
                do {
                    token = try await submitWith401Refresh(
                        identity: submitted,
                        descriptor: descriptor,
                        payload: payload,
                        token: token,
                        expectedAccountID: accountID,
                        tokenProvider: tokenProvider
                    )
                    try ensureActive(operationID)
                    let reconciled = try await reconcile(
                        identity: submitted,
                        expectedPayload: payload,
                        token: token
                    )
                    guard reconciled == .expected else { throw failure(for: reconciled) }
                    guard let pending = submitted.pending else {
                        throw DailyDriveExportFailure.staleCompletion
                    }
                    try finalize(
                        operationID: operationID,
                        dataAsOf: pending.dataAsOf,
                        hash: pending.payloadSHA256,
                        registry: &registry,
                        index: index
                    )
                    return cancellationRequested
                        ? .cancelledAfterSubmissionVerified(
                            dataAsOf: pending.dataAsOf,
                            created: pending.kind == .create
                        )
                        : .verified(
                            dataAsOf: pending.dataAsOf,
                            created: pending.kind == .create
                        )
                } catch let failure as DailyDriveExportFailure {
                    throw failure
                } catch {
                    if isDefinitiveRejection(error) {
                        if registry.identities[index].lastVerified != nil {
                            registry.identities[index].pending = nil
                        } else {
                            registry.identities[index].pending?.phase = .reserved
                        }
                        try persist(registry)
                        throw map(error)
                    }

                    registry.identities[index].pending?.phase = .uncertain
                    try persist(registry)
                    let current = registry.identities[index]
                    let reconciled = try? await reconcile(
                        identity: current,
                        expectedPayload: payload,
                        token: token
                    )
                    if reconciled == .expected, let pending = current.pending {
                        try finalize(
                            operationID: operationID,
                            dataAsOf: pending.dataAsOf,
                            hash: pending.payloadSHA256,
                            registry: &registry,
                            index: index
                        )
                        return cancellationRequested
                            ? .cancelledAfterSubmissionVerified(
                                dataAsOf: pending.dataAsOf,
                                created: pending.kind == .create
                            )
                            : .verified(
                                dataAsOf: pending.dataAsOf,
                                created: pending.kind == .create
                            )
                    }
                    if !cancellationRequested,
                       !retriedUncertainSubmission,
                       (reconciled == .missing || reconciled == .previous) {
                        retriedUncertainSubmission = true
                        registry.identities[index].pending?.phase = .submitted
                        try persist(registry)
                        continue
                    }
                    throw DailyDriveExportFailure.unresolvedRequest
                }
            }
        } catch let failure as DailyDriveExportFailure {
            throw failure
        } catch {
            throw DailyDriveExportFailure.transportFailure
        }
    }

    public func recover(
        selectedFileID: String,
        reportDate: String,
        accountID: String,
        folderID: String,
        tokenProvider: @escaping TokenProvider
    ) async throws -> DailyDriveRecoveryResult {
        guard activeOperationID == nil else { throw DailyDriveExportFailure.busy }
        let operationID = UUID().uuidString
        activeOperationID = operationID
        defer { if activeOperationID == operationID { activeOperationID = nil } }

        let token = try await validatedToken(
            forceRefresh: false,
            expectedAccountID: accountID,
            tokenProvider: tokenProvider
        )
        let metadata = try await transport.fileMetadata(id: selectedFileID, accessToken: token)
        let content = try await transport.fileContent(id: selectedFileID, accessToken: token)
        try ensureActive(operationID)
        let payloadIdentity = try validatedPayload(content, reportDate: reportDate)

        guard metadata.id == selectedFileID,
              metadata.name == policy.filename(for: reportDate),
              metadata.mimeType == "application/json",
              metadata.parents == [folderID],
              !metadata.trashed,
              metadata.driveID == nil,
              metadata.isAppAuthorized,
              metadata.canEdit,
              metadata.appProperties[policy.ownerPropertyKey]
                == DailyDriveMetadataKeys.ownerValue,
              metadata.appProperties[DailyDriveMetadataKeys.reportDate] == reportDate,
              let remoteInstallationID = metadata.appProperties[
                DailyDriveMetadataKeys.installationID
              ],
              metadata.appProperties[policy.orderingPropertyKey]
                == payloadIdentity.orderingToken,
              metadata.appProperties[DailyDriveMetadataKeys.payloadSHA256]
                == payloadIdentity.payloadSHA256 else {
            throw DailyDriveExportFailure.identityRecoveryAmbiguous
        }

        let marker = try store.installationMarker()
        guard marker == nil || marker == remoteInstallationID else {
            throw DailyDriveExportFailure.identityRecoveryAmbiguous
        }
        var registry = try store.load()
            ?? DailyDriveExportRegistry(installationID: remoteInstallationID)
        guard registry.identities.isEmpty || registry.installationID == remoteInstallationID else {
            throw DailyDriveExportFailure.identityRecoveryAmbiguous
        }
        let verified = VerifiedDailyDriveSnapshot(
            dataAsOf: payloadIdentity.orderingToken,
            payloadSHA256: payloadIdentity.payloadSHA256,
            verifiedAt: Date()
        )
        if let index = registry.exactIndex(
            accountID: accountID,
            folderID: folderID,
            reportDate: reportDate
        ) {
            guard registry.identities[index].fileID == selectedFileID else {
                throw DailyDriveExportFailure.identityRecoveryAmbiguous
            }
            registry.identities[index].lastVerified = verified
            registry.identities[index].pending = nil
            try persist(registry)
            return .alreadyTracked(dataAsOf: verified.dataAsOf)
        }

        let sameDateIndices = registry.identities.indices.filter {
            registry.identities[$0].reportDate == reportDate
        }
        if !sameDateIndices.isEmpty {
            guard sameDateIndices.count == 1 else {
                throw DailyDriveExportFailure.identityRecoveryAmbiguous
            }
            let index = sameDateIndices[0]
            let existing = registry.identities[index]
            guard existing.accountID == accountID else {
                throw DailyDriveExportFailure.destinationChangeRequiresMigration
            }
            guard existing.fileID == selectedFileID,
                  existing.installationID == remoteInstallationID else {
                throw DailyDriveExportFailure.identityRecoveryAmbiguous
            }
            registry.identities[index] = DailyDriveExportIdentity(
                accountID: accountID,
                folderID: folderID,
                reportDate: reportDate,
                fileID: selectedFileID,
                installationID: remoteInstallationID,
                lastVerified: verified,
                pending: nil
            )
            try persist(registry)
            return .migrated(dataAsOf: verified.dataAsOf)
        }

        registry.installationID = remoteInstallationID
        registry.identities.append(DailyDriveExportIdentity(
            accountID: accountID,
            folderID: folderID,
            reportDate: reportDate,
            fileID: selectedFileID,
            installationID: remoteInstallationID,
            lastVerified: verified,
            pending: nil
        ))
        try persist(registry)
        return .recovered(dataAsOf: verified.dataAsOf)
    }

    private func loadOrCreateRegistry() throws -> DailyDriveExportRegistry {
        do {
            if let registry = try store.load() {
                guard registry.version == DailyDriveExportRegistry.formatVersion else {
                    throw DailyDriveExportFailure.identityRecoveryAmbiguous
                }
                return registry
            }
            guard try store.installationMarker() == nil else {
                throw DailyDriveExportFailure.identityRecoveryAmbiguous
            }
            let registry = DailyDriveExportRegistry()
            try persist(registry)
            return registry
        } catch let failure as DailyDriveExportFailure {
            throw failure
        } catch is DecodingError {
            throw DailyDriveExportFailure.identityRecoveryAmbiguous
        } catch {
            throw DailyDriveExportFailure.persistenceFailure
        }
    }

    private func persist(_ registry: DailyDriveExportRegistry) throws {
        do {
            try store.save(registry)
        } catch let failure as DailyDriveExportFailure {
            throw failure
        } catch {
            throw DailyDriveExportFailure.persistenceFailure
        }
    }

    private func validatedToken(
        forceRefresh: Bool,
        expectedAccountID: String,
        tokenProvider: TokenProvider
    ) async throws -> String {
        let token: String
        do {
            token = try await tokenProvider(forceRefresh)
        } catch let failure as DailyDriveCredentialFailure {
            throw DailyDriveExportFailure.credentials(failure)
        } catch {
            throw DailyDriveExportFailure.credentialsRejected
        }

        do {
            let account = try await transport.account(accessToken: token)
            guard account.id == expectedAccountID else {
                throw DailyDriveExportFailure.accountMismatch
            }
            return token
        } catch let failure as DailyDriveExportFailure {
            throw failure
        } catch DailyDriveAPI.Failure.httpStatus(401, _) where !forceRefresh {
            return try await validatedToken(
                forceRefresh: true,
                expectedAccountID: expectedAccountID,
                tokenProvider: tokenProvider
            )
        } catch {
            throw map(error)
        }
    }

    private func submitWith401Refresh(
        identity: DailyDriveExportIdentity,
        descriptor: DailyDriveUploadDescriptor,
        payload: Data,
        token: String,
        expectedAccountID: String,
        tokenProvider: TokenProvider
    ) async throws -> String {
        do {
            try await submit(
                identity: identity,
                descriptor: descriptor,
                payload: payload,
                token: token
            )
            return token
        } catch DailyDriveAPI.Failure.httpStatus(401, _) {
            let refreshed = try await validatedToken(
                forceRefresh: true,
                expectedAccountID: expectedAccountID,
                tokenProvider: tokenProvider
            )
            try await submit(
                identity: identity,
                descriptor: descriptor,
                payload: payload,
                token: refreshed
            )
            return refreshed
        }
    }

    private func submit(
        identity: DailyDriveExportIdentity,
        descriptor: DailyDriveUploadDescriptor,
        payload: Data,
        token: String
    ) async throws {
        switch identity.pending?.kind {
        case .create:
            try await transport.createFile(descriptor, content: payload, accessToken: token)
        case .update:
            try await transport.updateFile(descriptor, content: payload, accessToken: token)
        case nil:
            throw DailyDriveExportFailure.staleCompletion
        }
    }

    private func reconcile(
        identity: DailyDriveExportIdentity,
        expectedPayload: Data,
        token: String
    ) async throws -> Reconciliation {
        let metadata: DailyDriveFileMetadata
        do {
            metadata = try await transport.fileMetadata(
                id: identity.fileID,
                accessToken: token
            )
        } catch DailyDriveAPI.Failure.httpStatus(404, _) {
            return .missing
        }
        let content = try await transport.fileContent(id: identity.fileID, accessToken: token)

        if metadata.trashed { throw DailyDriveExportFailure.remoteTrashed }
        if metadata.parents != [identity.folderID] { throw DailyDriveExportFailure.remoteMoved }
        guard metadata.id == identity.fileID,
              metadata.name == policy.filename(for: identity.reportDate),
              metadata.mimeType == "application/json",
              metadata.driveID == nil,
              metadata.isAppAuthorized,
              metadata.canEdit else {
            throw DailyDriveExportFailure.remoteMetadataMismatch
        }

        if let pending = identity.pending,
           metadata.appProperties == properties(
               installationID: identity.installationID,
               reportDate: identity.reportDate,
               dataAsOf: pending.dataAsOf,
               hash: pending.payloadSHA256
           ),
           content == expectedPayload,
           Self.sha256(content) == pending.payloadSHA256,
           (try? validatedPayload(content, reportDate: identity.reportDate))?
               .orderingToken == pending.dataAsOf {
            return .expected
        }

        if let verified = identity.lastVerified,
           metadata.appProperties == properties(
               installationID: identity.installationID,
               reportDate: identity.reportDate,
               dataAsOf: verified.dataAsOf,
               hash: verified.payloadSHA256
           ),
           Self.sha256(content) == verified.payloadSHA256,
           (try? validatedPayload(content, reportDate: identity.reportDate))?
               .orderingToken == verified.dataAsOf {
            return .previous
        }
        return .mismatch
    }

    private func finalize(
        operationID: String,
        dataAsOf: String,
        hash: String,
        registry: inout DailyDriveExportRegistry,
        index: Int
    ) throws {
        let current: DailyDriveExportRegistry?
        do {
            current = try store.load()
        } catch {
            throw DailyDriveExportFailure.persistenceFailure
        }
        guard let currentIndex = current?.exactIndex(
            accountID: registry.identities[index].accountID,
            folderID: registry.identities[index].folderID,
            reportDate: registry.identities[index].reportDate
        ), current?.identities[currentIndex].pending?.operationID == operationID else {
            throw DailyDriveExportFailure.staleCompletion
        }
        registry.identities[index].lastVerified = VerifiedDailyDriveSnapshot(
            dataAsOf: dataAsOf,
            payloadSHA256: hash,
            verifiedAt: Date()
        )
        registry.identities[index].pending = nil
        try persist(registry)
    }

    private func descriptor(for identity: DailyDriveExportIdentity) -> DailyDriveUploadDescriptor {
        guard let pending = identity.pending else {
            return DailyDriveUploadDescriptor(
                id: identity.fileID,
                name: policy.filename(for: identity.reportDate),
                parentID: identity.folderID,
                appProperties: [:]
            )
        }
        return DailyDriveUploadDescriptor(
            id: identity.fileID,
            name: policy.filename(for: identity.reportDate),
            parentID: identity.folderID,
            appProperties: properties(
                installationID: identity.installationID,
                reportDate: identity.reportDate,
                dataAsOf: pending.dataAsOf,
                hash: pending.payloadSHA256
            )
        )
    }

    private func properties(
        installationID: String,
        reportDate: String,
        dataAsOf: String,
        hash: String
    ) -> [String: String] {
        [
            policy.ownerPropertyKey: DailyDriveMetadataKeys.ownerValue,
            DailyDriveMetadataKeys.reportDate: reportDate,
            DailyDriveMetadataKeys.installationID: installationID,
            policy.orderingPropertyKey: dataAsOf,
            DailyDriveMetadataKeys.payloadSHA256: hash
        ]
    }

    private func ensureActive(_ operationID: String) throws {
        guard activeOperationID == operationID else {
            throw DailyDriveExportFailure.staleCompletion
        }
    }

    private func failure(for reconciliation: Reconciliation) -> DailyDriveExportFailure {
        switch reconciliation {
        case .expected: .transportFailure
        case .previous: .unresolvedRequest
        case .missing: .remoteMissing
        case .mismatch: .remoteContentMismatch
        }
    }

    private func isDefinitiveRejection(_ error: Error) -> Bool {
        guard case let DailyDriveAPI.Failure.httpStatus(code, reason) = error else {
            return false
        }
        if code == 403, reason == "userRateLimitExceeded" { return false }
        return code == 400 || code == 401 || code == 403 || code == 404
    }

    private func map(_ error: Error) -> DailyDriveExportFailure {
        guard case let DailyDriveAPI.Failure.httpStatus(code, reason) = error else {
            return .transportFailure
        }
        switch code {
        case 401: return .credentialsRejected
        case 403 where reason == "storageQuotaExceeded": return .quotaExceeded
        case 403 where reason == "userRateLimitExceeded": return .rateLimited
        case 403: return .permissionDenied
        case 404: return .remoteMissing
        case 429: return .rateLimited
        default: return .transportFailure
        }
    }

    private func validatedPayload(
        _ payload: Data,
        reportDate: String
    ) throws -> DrivePayloadIdentity {
        do {
            return try policy.validate(payload: payload, reportDate: reportDate)
        } catch {
            throw DailyDriveExportFailure.invalidPayload
        }
    }

    private func compare(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        do {
            return try policy.compare(lhs, rhs)
        } catch {
            throw DailyDriveExportFailure.invalidPayload
        }
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
