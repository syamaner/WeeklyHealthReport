import CryptoKit
import Foundation

struct VerifiedDailyDriveSnapshot: Codable, Equatable, Sendable {
    let dataAsOf: String
    let payloadSHA256: String
    let verifiedAt: Date
}

struct PendingDailyDriveOperation: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case create, update }
    enum Phase: String, Codable, Sendable { case reserved, submitted, uncertain }

    let operationID: String
    let dataAsOf: String
    let payloadSHA256: String
    let kind: Kind
    var phase: Phase
}

struct DailyDriveExportIdentity: Codable, Equatable, Sendable {
    let accountID: String
    let folderID: String
    let reportDate: String
    let fileID: String
    let installationID: String
    var lastVerified: VerifiedDailyDriveSnapshot?
    var pending: PendingDailyDriveOperation?
}

struct DailyDriveExportRegistry: Codable, Equatable, Sendable {
    static let formatVersion = 1

    let version: Int
    var installationID: String
    var identities: [DailyDriveExportIdentity]

    init(
        installationID: String = UUID().uuidString,
        identities: [DailyDriveExportIdentity] = []
    ) {
        version = Self.formatVersion
        self.installationID = installationID
        self.identities = identities
    }

    func exactIndex(accountID: String, folderID: String, reportDate: String) -> Int? {
        identities.firstIndex {
            $0.accountID == accountID && $0.folderID == folderID && $0.reportDate == reportDate
        }
    }

    func hasDifferentDestination(
        accountID: String,
        folderID: String,
        reportDate: String
    ) -> Bool {
        identities.contains {
            $0.reportDate == reportDate && ($0.accountID != accountID || $0.folderID != folderID)
        }
    }
}

protocol DailyDriveExportIdentityPersisting: Sendable {
    func load() throws -> DailyDriveExportRegistry?
    func installationMarker() throws -> String?
    func save(_ registry: DailyDriveExportRegistry) throws
}

struct KeychainDailyDriveExportIdentityStore: DailyDriveExportIdentityPersisting, Sendable {
    private static let registryKey = "google.drive.daily-export-identities.v1"
    private static let markerKey = "google.drive.daily-export-installation.v1"
    private let keychain: DailyDriveKeychainStore

    init(keychain: DailyDriveKeychainStore = DailyDriveKeychainStore()) {
        self.keychain = keychain
    }

    func load() throws -> DailyDriveExportRegistry? {
        guard let data = try keychain.load(account: Self.registryKey) else { return nil }
        let registry = try JSONDecoder().decode(DailyDriveExportRegistry.self, from: data)
        guard registry.version == DailyDriveExportRegistry.formatVersion,
              try installationMarker() == registry.installationID else {
            throw DailyDriveExportFailure.identityRecoveryAmbiguous
        }
        return registry
    }

    func installationMarker() throws -> String? {
        guard let data = try keychain.load(account: Self.markerKey) else { return nil }
        guard let marker = String(data: data, encoding: .utf8), !marker.isEmpty else {
            throw DailyDriveExportFailure.identityRecoveryAmbiguous
        }
        return marker
    }

    func save(_ registry: DailyDriveExportRegistry) throws {
        if let marker = try installationMarker() {
            guard marker == registry.installationID else {
                throw DailyDriveExportFailure.identityRecoveryAmbiguous
            }
        } else {
            try keychain.save(Data(registry.installationID.utf8), account: Self.markerKey)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try keychain.save(encoder.encode(registry), account: Self.registryKey)
    }
}

enum DailyDriveCredentialFailure: String, Error, Equatable, Sendable {
    case expired
    case denied
    case revoked
}

enum DailyDriveExportFailure: Error, Equatable, Sendable {
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

enum DailyDriveExportResult: Equatable, Sendable {
    case verified(dataAsOf: String, created: Bool)
    case unchangedVerified(dataAsOf: String)
    case cancelledBeforeSubmission
    case cancelledAfterSubmissionVerified(dataAsOf: String, created: Bool)
}

enum DailyDriveRecoveryResult: Equatable, Sendable {
    case recovered(dataAsOf: String)
    case alreadyTracked(dataAsOf: String)
}

enum DailyDriveMetadataKeys {
    static let owner = "whrDailyCanonical"
    static let ownerValue = "v1"
    static let reportDate = "whrReportDate"
    static let installationID = "whrInstallationID"
    static let dataAsOf = "whrDataAsOf"
    static let payloadSHA256 = "whrPayloadSHA256"
}

actor DailyDriveExportCoordinator {
    typealias TokenProvider = @Sendable (_ forceRefresh: Bool) async throws -> String

    private struct PayloadIdentity {
        let envelope: DailyHealthExportEnvelope
        let dataAsOfDate: Date
        let hash: String
    }

    private enum Reconciliation {
        case expected
        case previous
        case missing
        case mismatch
    }

    private let transport: any DailyDriveTransporting
    private let store: any DailyDriveExportIdentityPersisting
    private var activeOperationID: String?
    private var cancellationRequested = false

    init(
        transport: any DailyDriveTransporting,
        store: any DailyDriveExportIdentityPersisting
    ) {
        self.transport = transport
        self.store = store
    }

    func requestCancellation() {
        guard activeOperationID != nil else { return }
        cancellationRequested = true
    }

    func abandonDestination(accountID: String, folderID: String) throws {
        try abandonIdentities {
            $0.accountID == accountID && $0.folderID == folderID
        }
    }

    func abandonFileIdentity(accountID: String, folderID: String, reportDate: String) throws {
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

    func export(
        payload: Data,
        reportDate: String,
        accountID: String,
        folderID: String,
        tokenProvider: @escaping TokenProvider
    ) async throws -> DailyDriveExportResult {
        guard activeOperationID == nil else { throw DailyDriveExportFailure.busy }
        let payloadIdentity = try Self.validate(payload: payload, reportDate: reportDate)
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
                        dataAsOf: payloadIdentity.envelope.dataAsOf,
                        payloadSHA256: payloadIdentity.hash,
                        kind: .create,
                        phase: .reserved
                    )
                ))
                index = registry.identities.count - 1
                try persist(registry)
            }

            var identity = registry.identities[index]
            if let verified = identity.lastVerified {
                let verifiedDate = try Self.timestamp(verified.dataAsOf)
                guard payloadIdentity.dataAsOfDate >= verifiedDate else {
                    throw DailyDriveExportFailure.staleSnapshot
                }
                if payloadIdentity.dataAsOfDate == verifiedDate {
                    guard verified.payloadSHA256 == payloadIdentity.hash else {
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
                    guard pending.dataAsOf == payloadIdentity.envelope.dataAsOf,
                          pending.payloadSHA256 == payloadIdentity.hash else {
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
                    dataAsOf: payloadIdentity.envelope.dataAsOf,
                    payloadSHA256: payloadIdentity.hash,
                    kind: pending.kind,
                    phase: .reserved
                )
                registry.identities[index] = identity
                try persist(registry)
            } else {
                identity.pending = PendingDailyDriveOperation(
                    operationID: operationID,
                    dataAsOf: payloadIdentity.envelope.dataAsOf,
                    payloadSHA256: payloadIdentity.hash,
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

    func recover(
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
        let payloadIdentity = try Self.validate(payload: content, reportDate: reportDate)

        guard metadata.id == selectedFileID,
              metadata.name == Self.filename(for: reportDate),
              metadata.mimeType == "application/json",
              metadata.parents == [folderID],
              !metadata.trashed,
              metadata.driveID == nil,
              metadata.isAppAuthorized,
              metadata.canEdit,
              metadata.appProperties[DailyDriveMetadataKeys.owner]
                == DailyDriveMetadataKeys.ownerValue,
              metadata.appProperties[DailyDriveMetadataKeys.reportDate] == reportDate,
              let remoteInstallationID = metadata.appProperties[
                DailyDriveMetadataKeys.installationID
              ],
              metadata.appProperties[DailyDriveMetadataKeys.dataAsOf]
                == payloadIdentity.envelope.dataAsOf,
              metadata.appProperties[DailyDriveMetadataKeys.payloadSHA256]
                == payloadIdentity.hash else {
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
        guard !registry.hasDifferentDestination(
            accountID: accountID,
            folderID: folderID,
            reportDate: reportDate
        ) else {
            throw DailyDriveExportFailure.destinationChangeRequiresMigration
        }

        let verified = VerifiedDailyDriveSnapshot(
            dataAsOf: payloadIdentity.envelope.dataAsOf,
            payloadSHA256: payloadIdentity.hash,
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
              metadata.name == Self.filename(for: identity.reportDate),
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
           (try? Self.validate(payload: content, reportDate: identity.reportDate))?
               .envelope.dataAsOf == pending.dataAsOf {
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
           (try? Self.validate(payload: content, reportDate: identity.reportDate))?
               .envelope.dataAsOf == verified.dataAsOf {
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
                name: Self.filename(for: identity.reportDate),
                parentID: identity.folderID,
                appProperties: [:]
            )
        }
        return DailyDriveUploadDescriptor(
            id: identity.fileID,
            name: Self.filename(for: identity.reportDate),
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
            DailyDriveMetadataKeys.owner: DailyDriveMetadataKeys.ownerValue,
            DailyDriveMetadataKeys.reportDate: reportDate,
            DailyDriveMetadataKeys.installationID: installationID,
            DailyDriveMetadataKeys.dataAsOf: dataAsOf,
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

    private static func validate(payload: Data, reportDate: String) throws -> PayloadIdentity {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(DailyHealthExportEnvelope.self, from: payload),
              envelope.schemaVersion == 1,
              envelope.reportDate == reportDate,
              try DailyHealthExportSerializer.encode(envelope) == payload,
              let dataAsOf = try? timestamp(envelope.dataAsOf),
              let exportedAt = try? timestamp(envelope.exportedAt),
              exportedAt >= dataAsOf else {
            throw DailyDriveExportFailure.invalidPayload
        }
        return PayloadIdentity(
            envelope: envelope,
            dataAsOfDate: dataAsOf,
            hash: sha256(payload)
        )
    }

    private static func timestamp(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw DailyDriveExportFailure.invalidPayload
        }
        return date
    }

    static func filename(for reportDate: String) -> String {
        "health-daily-\(reportDate).json"
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
