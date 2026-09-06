import CryptoKit
import Foundation

actor CanonicalExportCoordinator {
    typealias TokenProvider = @Sendable (_ forceRefresh: Bool) async throws -> String

    private enum Reconciliation {
        case expected
        case previous
        case missing
        case mismatch
    }

    private let transport: any DriveTransporting
    private let store: any CanonicalExportIdentityPersisting
    private var activeOperationID: String?
    private var cancellationRequested = false

    init(
        transport: any DriveTransporting,
        store: any CanonicalExportIdentityPersisting
    ) {
        self.transport = transport
        self.store = store
    }

    func requestCancellation() {
        guard activeOperationID != nil else { return }
        cancellationRequested = true
    }

    func export(
        payload: Data,
        generation: Int,
        reportDate: String,
        accountID: String,
        folderID: String,
        tokenProvider: @escaping TokenProvider
    ) async throws -> CanonicalExportResult {
        guard activeOperationID == nil else { throw CanonicalExportFailure.busy }
        guard SyntheticPayload.allowedReportDates.contains(reportDate),
              (try? SyntheticPayload.revision(in: payload, reportDate: reportDate)) == generation else {
            throw CanonicalExportFailure.invalidSyntheticPayload
        }

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
                throw CanonicalExportFailure.destinationChangeRequiresMigration
            }

            var token = try await validatedToken(
                forceRefresh: false,
                expectedAccountID: accountID,
                tokenProvider: tokenProvider
            )
            let hash = Self.sha256(payload)
            let index: Int

            if let existingIndex = registry.exactIndex(
                accountID: accountID,
                folderID: folderID,
                reportDate: reportDate
            ) {
                index = existingIndex
            } else {
                let fileID: String
                do { fileID = try await transport.generateFileID(accessToken: token) }
                catch { throw map(error) }
                try ensureActive(operationID)
                let pending = PendingSyntheticOperation(
                    operationID: operationID,
                    generation: generation,
                    payloadSHA256: hash,
                    kind: .create,
                    phase: .reserved
                )
                registry.identities.append(CanonicalExportIdentity(
                    accountID: accountID,
                    folderID: folderID,
                    reportDate: reportDate,
                    fileID: fileID,
                    installationID: registry.installationID,
                    lastVerified: nil,
                    pending: pending
                ))
                index = registry.identities.count - 1
                try persist(registry)
            }

            var identity = registry.identities[index]
            if let verified = identity.lastVerified {
                guard generation >= verified.generation else {
                    throw CanonicalExportFailure.staleGeneration
                }
                if generation == verified.generation {
                    guard verified.payloadSHA256 == hash else {
                        throw CanonicalExportFailure.staleGeneration
                    }
                    let reconciled = try await reconcile(
                        identity: identity,
                        expectedPayload: payload,
                        token: token
                    )
                    guard reconciled == .previous else {
                        throw failure(for: reconciled)
                    }
                    return .unchangedVerified(generation: generation)
                }
            }

            if let pending = identity.pending {
                if pending.phase != .reserved {
                    guard pending.generation == generation, pending.payloadSHA256 == hash else {
                        throw CanonicalExportFailure.unresolvedRequest
                    }
                    let reconciled = try await reconcile(
                        identity: identity,
                        expectedPayload: payload,
                        token: token
                    )
                    if reconciled == .expected {
                        try finalize(
                            operationID: pending.operationID,
                            generation: generation,
                            hash: hash,
                            in: &registry,
                            at: index
                        )
                        return .verified(generation: generation, created: pending.kind == .create)
                    }
                    guard reconciled == .missing || reconciled == .previous else {
                        throw failure(for: reconciled)
                    }
                    identity = registry.identities[index]
                    identity.pending = PendingSyntheticOperation(
                        operationID: operationID,
                        generation: generation,
                        payloadSHA256: hash,
                        kind: pending.kind,
                        phase: .reserved
                    )
                    registry.identities[index] = identity
                    try persist(registry)
                } else {
                    identity.pending = PendingSyntheticOperation(
                        operationID: operationID,
                        generation: generation,
                        payloadSHA256: hash,
                        kind: pending.kind,
                        phase: .reserved
                    )
                    registry.identities[index] = identity
                    try persist(registry)
                }
            } else {
                identity.pending = PendingSyntheticOperation(
                    operationID: operationID,
                    generation: generation,
                    payloadSHA256: hash,
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
            let descriptor = descriptor(for: submitted, generation: generation, hash: hash)
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
                    try finalize(
                        operationID: operationID,
                        generation: generation,
                        hash: hash,
                        in: &registry,
                        at: index
                    )
                    let created = submitted.pending?.kind == .create
                    return cancellationRequested
                        ? .cancelledAfterSubmissionVerified(generation: generation, created: created)
                        : .verified(generation: generation, created: created)
                } catch let failure as CanonicalExportFailure {
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
                    let reconciled = try? await reconcile(
                        identity: registry.identities[index],
                        expectedPayload: payload,
                        token: token
                    )
                    if reconciled == .expected {
                        try finalize(
                            operationID: operationID,
                            generation: generation,
                            hash: hash,
                            in: &registry,
                            at: index
                        )
                        let created = submitted.pending?.kind == .create
                        return cancellationRequested
                            ? .cancelledAfterSubmissionVerified(generation: generation, created: created)
                            : .verified(generation: generation, created: created)
                    }
                    if !cancellationRequested,
                       !retriedUncertainSubmission,
                       (reconciled == .missing || reconciled == .previous) {
                        retriedUncertainSubmission = true
                        registry.identities[index].pending?.phase = .submitted
                        try persist(registry)
                        continue
                    }
                    throw CanonicalExportFailure.unresolvedRequest
                }
            }
        } catch let failure as CanonicalExportFailure {
            throw failure
        } catch {
            throw CanonicalExportFailure.transportFailure
        }
    }

    func recover(
        selectedFileID: String,
        reportDate: String,
        accountID: String,
        folderID: String,
        tokenProvider: @escaping TokenProvider
    ) async throws -> CanonicalRecoveryResult {
        guard activeOperationID == nil else { throw CanonicalExportFailure.busy }
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

        guard metadata.id == selectedFileID,
              metadata.name == SyntheticPayload.filename(for: reportDate),
              metadata.mimeType == "application/json",
              metadata.parents == [folderID],
              !metadata.trashed,
              metadata.driveID == nil,
              metadata.isAppAuthorized,
              metadata.canEdit,
              metadata.appProperties[CanonicalMetadataKeys.owner] == CanonicalMetadataKeys.ownerValue,
              metadata.appProperties[CanonicalMetadataKeys.reportDate] == reportDate,
              let remoteInstallationID = metadata.appProperties[CanonicalMetadataKeys.installationID],
              let generationText = metadata.appProperties[CanonicalMetadataKeys.generation],
              let generation = Int(generationText),
              let expectedHash = metadata.appProperties[CanonicalMetadataKeys.payloadSHA256],
              expectedHash == Self.sha256(content),
              try SyntheticPayload.revision(in: content, reportDate: reportDate) == generation else {
            throw CanonicalExportFailure.identityRecoveryAmbiguous
        }

        let marker = try store.installationMarker()
        guard marker == nil || marker == remoteInstallationID else {
            throw CanonicalExportFailure.identityRecoveryAmbiguous
        }
        var registry = try store.load() ?? CanonicalExportRegistry(installationID: remoteInstallationID)
        if !registry.identities.isEmpty, registry.installationID != remoteInstallationID {
            throw CanonicalExportFailure.identityRecoveryAmbiguous
        }
        if registry.hasDifferentDestination(accountID: accountID, folderID: folderID, reportDate: reportDate) {
            throw CanonicalExportFailure.destinationChangeRequiresMigration
        }
        if let index = registry.exactIndex(accountID: accountID, folderID: folderID, reportDate: reportDate) {
            guard registry.identities[index].fileID == selectedFileID else {
                throw CanonicalExportFailure.identityRecoveryAmbiguous
            }
            registry.identities[index].lastVerified = VerifiedSyntheticSnapshot(
                generation: generation,
                payloadSHA256: expectedHash,
                verifiedAt: Date()
            )
            registry.identities[index].pending = nil
            try persist(registry)
            return .alreadyTracked(generation: generation)
        }

        registry.installationID = remoteInstallationID
        registry.identities.append(CanonicalExportIdentity(
            accountID: accountID,
            folderID: folderID,
            reportDate: reportDate,
            fileID: selectedFileID,
            installationID: remoteInstallationID,
            lastVerified: VerifiedSyntheticSnapshot(
                generation: generation,
                payloadSHA256: expectedHash,
                verifiedAt: Date()
            ),
            pending: nil
        ))
        try persist(registry)
        return .recovered(generation: generation)
    }

    private func loadOrCreateRegistry() throws -> CanonicalExportRegistry {
        do {
            if let registry = try store.load() {
                guard registry.version == CanonicalExportRegistry.formatVersion else {
                    throw CanonicalExportFailure.identityRecoveryAmbiguous
                }
                return registry
            }
            guard try store.installationMarker() == nil else {
                throw CanonicalExportFailure.identityRecoveryAmbiguous
            }
            let registry = CanonicalExportRegistry()
            try persist(registry)
            return registry
        } catch let failure as CanonicalExportFailure {
            throw failure
        } catch is DecodingError {
            throw CanonicalExportFailure.identityRecoveryAmbiguous
        } catch {
            throw CanonicalExportFailure.persistenceFailure
        }
    }

    private func persist(_ registry: CanonicalExportRegistry) throws {
        do { try store.save(registry) }
        catch { throw CanonicalExportFailure.persistenceFailure }
    }

    private func validatedToken(
        forceRefresh: Bool,
        expectedAccountID: String,
        tokenProvider: TokenProvider
    ) async throws -> String {
        let token: String
        do { token = try await tokenProvider(forceRefresh) }
        catch let failure as SyntheticCredentialFailure { throw CanonicalExportFailure.credentials(failure) }
        catch { throw CanonicalExportFailure.credentialsRejected }

        do {
            let account = try await transport.account(accessToken: token)
            guard account.id == expectedAccountID else { throw CanonicalExportFailure.accountMismatch }
            return token
        } catch let failure as CanonicalExportFailure {
            throw failure
        } catch DriveAPI.Failure.httpStatus(401, _) where !forceRefresh {
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
        identity: CanonicalExportIdentity,
        descriptor: DriveUploadDescriptor,
        payload: Data,
        token: String,
        expectedAccountID: String,
        tokenProvider: TokenProvider
    ) async throws -> String {
        do {
            try await submit(identity: identity, descriptor: descriptor, payload: payload, token: token)
            return token
        } catch DriveAPI.Failure.httpStatus(401, _) {
            let refreshed = try await validatedToken(
                forceRefresh: true,
                expectedAccountID: expectedAccountID,
                tokenProvider: tokenProvider
            )
            try await submit(identity: identity, descriptor: descriptor, payload: payload, token: refreshed)
            return refreshed
        }
    }

    private func submit(
        identity: CanonicalExportIdentity,
        descriptor: DriveUploadDescriptor,
        payload: Data,
        token: String
    ) async throws {
        switch identity.pending?.kind {
        case .create:
            try await transport.createFile(descriptor, content: payload, accessToken: token)
        case .update:
            try await transport.updateFile(descriptor, content: payload, accessToken: token)
        case nil:
            throw CanonicalExportFailure.staleCompletion
        }
    }

    private func reconcile(
        identity: CanonicalExportIdentity,
        expectedPayload: Data,
        token: String
    ) async throws -> Reconciliation {
        let metadata: DriveFileMetadata
        do { metadata = try await transport.fileMetadata(id: identity.fileID, accessToken: token) }
        catch DriveAPI.Failure.httpStatus(404, _) { return .missing }
        let content = try await transport.fileContent(id: identity.fileID, accessToken: token)

        if metadata.trashed { throw CanonicalExportFailure.remoteTrashed }
        if metadata.parents != [identity.folderID] { throw CanonicalExportFailure.remoteMoved }
        guard metadata.id == identity.fileID,
              metadata.name == SyntheticPayload.filename(for: identity.reportDate),
              metadata.mimeType == "application/json",
              metadata.driveID == nil,
              metadata.isAppAuthorized,
              metadata.canEdit else {
            throw CanonicalExportFailure.remoteMetadataMismatch
        }

        if let pending = identity.pending,
           metadata.appProperties == properties(
               installationID: identity.installationID,
               reportDate: identity.reportDate,
               generation: pending.generation,
               hash: pending.payloadSHA256
           ), content == expectedPayload,
           Self.sha256(content) == pending.payloadSHA256,
           (try? SyntheticPayload.revision(in: content, reportDate: identity.reportDate)) == pending.generation {
            return .expected
        }

        if let verified = identity.lastVerified,
           metadata.appProperties == properties(
               installationID: identity.installationID,
               reportDate: identity.reportDate,
               generation: verified.generation,
               hash: verified.payloadSHA256
           ), Self.sha256(content) == verified.payloadSHA256,
           (try? SyntheticPayload.revision(in: content, reportDate: identity.reportDate)) == verified.generation {
            return .previous
        }
        return .mismatch
    }

    private func finalize(
        operationID: String,
        generation: Int,
        hash: String,
        in registry: inout CanonicalExportRegistry,
        at index: Int
    ) throws {
        let current: CanonicalExportRegistry?
        do { current = try store.load() }
        catch { throw CanonicalExportFailure.persistenceFailure }
        guard let currentIndex = current?.exactIndex(
            accountID: registry.identities[index].accountID,
            folderID: registry.identities[index].folderID,
            reportDate: registry.identities[index].reportDate
        ), current?.identities[currentIndex].pending?.operationID == operationID else {
            throw CanonicalExportFailure.staleCompletion
        }
        registry.identities[index].lastVerified = VerifiedSyntheticSnapshot(
            generation: generation,
            payloadSHA256: hash,
            verifiedAt: Date()
        )
        registry.identities[index].pending = nil
        try persist(registry)
    }

    private func descriptor(
        for identity: CanonicalExportIdentity,
        generation: Int,
        hash: String
    ) -> DriveUploadDescriptor {
        DriveUploadDescriptor(
            id: identity.fileID,
            name: SyntheticPayload.filename(for: identity.reportDate),
            parentID: identity.folderID,
            appProperties: properties(
                installationID: identity.installationID,
                reportDate: identity.reportDate,
                generation: generation,
                hash: hash
            )
        )
    }

    private func properties(
        installationID: String,
        reportDate: String,
        generation: Int,
        hash: String
    ) -> [String: String] {
        [
            CanonicalMetadataKeys.owner: CanonicalMetadataKeys.ownerValue,
            CanonicalMetadataKeys.reportDate: reportDate,
            CanonicalMetadataKeys.installationID: installationID,
            CanonicalMetadataKeys.generation: String(generation),
            CanonicalMetadataKeys.payloadSHA256: hash
        ]
    }

    private func ensureActive(_ operationID: String) throws {
        guard activeOperationID == operationID else { throw CanonicalExportFailure.staleCompletion }
    }

    private func failure(for reconciliation: Reconciliation) -> CanonicalExportFailure {
        switch reconciliation {
        case .expected: return .transportFailure
        case .previous: return .unresolvedRequest
        case .missing: return .remoteMissing
        case .mismatch: return .remoteContentMismatch
        }
    }

    private func isDefinitiveRejection(_ error: Error) -> Bool {
        guard case let DriveAPI.Failure.httpStatus(code, reason) = error else { return false }
        if code == 403, reason == "userRateLimitExceeded" { return false }
        return code == 400 || code == 401 || code == 403 || code == 404
    }

    private func map(_ error: Error) -> CanonicalExportFailure {
        guard case let DriveAPI.Failure.httpStatus(code, reason) = error else {
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

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
