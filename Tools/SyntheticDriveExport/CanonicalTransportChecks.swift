import Foundation

final class TestIdentityStore: CanonicalExportIdentityPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var value: CanonicalExportRegistry?
    private var marker: String?
    private(set) var saveCount = 0

    init(_ value: CanonicalExportRegistry? = nil) {
        self.value = value
        marker = value?.installationID
    }

    func load() throws -> CanonicalExportRegistry? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func save(_ registry: CanonicalExportRegistry) throws {
        lock.lock()
        if let marker { precondition(marker == registry.installationID) }
        self.marker = registry.installationID
        value = registry
        saveCount += 1
        lock.unlock()
    }

    func installationMarker() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return marker
    }

    func removeRegistryPreservingMarker() {
        lock.lock()
        value = nil
        lock.unlock()
    }

    func mutate(_ change: (inout CanonicalExportRegistry) -> Void) {
        lock.lock()
        if value == nil { value = CanonicalExportRegistry() }
        change(&value!)
        lock.unlock()
    }
}

actor TestDriveServer: DriveTransporting {
    enum SubmissionBehavior: Sendable {
        case succeed
        case transientBeforeCommit
        case transientAfterCommit
        case unauthorized
        case permissionDenied
    }

    struct StoredFile: Sendable {
        var descriptor: DriveUploadDescriptor
        var content: Data
    }

    private(set) var accountID = "account-a"
    private(set) var generatedIDs: [String] = []
    private(set) var createIDs: [String] = []
    private(set) var updateIDs: [String] = []
    private var files: [String: StoredFile] = [:]
    private var createBehaviors: [SubmissionBehavior] = []
    private var updateBehaviors: [SubmissionBehavior] = []
    private var generatedCounter = 0
    private var contentOverride: Data?
    private var metadataParentOverride: String?
    private var metadataTrashed = false
    private var pauseNextGenerate = false
    private var generateContinuation: CheckedContinuation<Void, Never>?
    private var pauseNextUpdateAfterCommit = false
    private var updateContinuation: CheckedContinuation<Void, Never>?
    private var reservationProbe: (@Sendable () -> Bool)?

    func setAccountID(_ value: String) { accountID = value }
    func enqueueCreate(_ behavior: SubmissionBehavior) { createBehaviors.append(behavior) }
    func enqueueUpdate(_ behavior: SubmissionBehavior) { updateBehaviors.append(behavior) }
    func overrideContent(_ data: Data?) { contentOverride = data }
    func overrideParent(_ parent: String?) { metadataParentOverride = parent }
    func setTrashed(_ value: Bool) { metadataTrashed = value }
    func pauseGenerate() { pauseNextGenerate = true }
    func pauseUpdateAfterCommit() { pauseNextUpdateAfterCommit = true }
    func setReservationProbe(_ probe: @escaping @Sendable () -> Bool) { reservationProbe = probe }
    func isGeneratePaused() -> Bool { generateContinuation != nil }
    func isUpdatePaused() -> Bool { updateContinuation != nil }
    func resumeGenerate() { generateContinuation?.resume(); generateContinuation = nil }
    func resumeUpdate() { updateContinuation?.resume(); updateContinuation = nil }
    func fileCount() -> Int { files.count }
    func storedContent(id: String) -> Data? { files[id]?.content }

    func account(accessToken: String) async throws -> DriveAccount {
        DriveAccount(id: accountID, displayName: "Synthetic User", emailAddress: "synthetic@example.invalid")
    }

    func generateFileID(accessToken: String) async throws -> String {
        if pauseNextGenerate {
            pauseNextGenerate = false
            await withCheckedContinuation { generateContinuation = $0 }
        }
        generatedCounter += 1
        let id = "generated-\(generatedCounter)"
        generatedIDs.append(id)
        return id
    }

    func createFile(
        _ descriptor: DriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        createIDs.append(descriptor.id)
        precondition(reservationProbe?() ?? true, "Generated file ID must be persisted before create")
        let behavior = createBehaviors.isEmpty ? .succeed : createBehaviors.removeFirst()
        switch behavior {
        case .succeed:
            guard files[descriptor.id] == nil else { throw DriveAPI.Failure.httpStatus(409, nil) }
            files[descriptor.id] = StoredFile(descriptor: descriptor, content: content)
        case .transientBeforeCommit:
            throw URLError(.timedOut)
        case .transientAfterCommit:
            files[descriptor.id] = StoredFile(descriptor: descriptor, content: content)
            throw URLError(.networkConnectionLost)
        case .unauthorized:
            throw DriveAPI.Failure.httpStatus(401, nil)
        case .permissionDenied:
            throw DriveAPI.Failure.httpStatus(403, "insufficientFilePermissions")
        }
    }

    func updateFile(
        _ descriptor: DriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        updateIDs.append(descriptor.id)
        let behavior = updateBehaviors.isEmpty ? .succeed : updateBehaviors.removeFirst()
        switch behavior {
        case .succeed:
            guard files[descriptor.id] != nil else { throw DriveAPI.Failure.httpStatus(404, nil) }
            files[descriptor.id] = StoredFile(descriptor: descriptor, content: content)
        case .transientBeforeCommit:
            throw URLError(.timedOut)
        case .transientAfterCommit:
            guard files[descriptor.id] != nil else { throw DriveAPI.Failure.httpStatus(404, nil) }
            files[descriptor.id] = StoredFile(descriptor: descriptor, content: content)
            throw URLError(.networkConnectionLost)
        case .unauthorized:
            throw DriveAPI.Failure.httpStatus(401, nil)
        case .permissionDenied:
            throw DriveAPI.Failure.httpStatus(403, "insufficientFilePermissions")
        }
        if pauseNextUpdateAfterCommit {
            pauseNextUpdateAfterCommit = false
            await withCheckedContinuation { updateContinuation = $0 }
        }
    }

    func fileMetadata(id: String, accessToken: String) async throws -> DriveFileMetadata {
        guard let file = files[id] else { throw DriveAPI.Failure.httpStatus(404, nil) }
        return DriveFileMetadata(
            id: id,
            name: file.descriptor.name,
            mimeType: "application/json",
            parents: [metadataParentOverride ?? file.descriptor.parentID],
            trashed: metadataTrashed,
            driveID: nil,
            isAppAuthorized: true,
            canEdit: true,
            appProperties: file.descriptor.appProperties
        )
    }

    func fileContent(id: String, accessToken: String) async throws -> Data {
        guard let file = files[id] else { throw DriveAPI.Failure.httpStatus(404, nil) }
        return contentOverride ?? file.content
    }
}

@main
enum CanonicalTransportChecks {
    static let reportDate = "2026-09-06"
    static let accountID = "account-a"
    static let folderID = "folder-a"
    static let token: CanonicalExportCoordinator.TokenProvider = { forceRefresh in
        forceRefresh ? "fresh-token" : "initial-token"
    }

    static func main() async throws {
        print("CHECK: initial create and replacement")
        try await initialCreateAndReplacement()
        print("CHECK: uncertain create retry")
        try await uncertainCreateRetriesSameID()
        print("CHECK: commit then lost response")
        try await commitThenLostResponseReconciles()
        print("CHECK: token refresh and rejected write")
        try await tokenRefreshAndRejectedWritePreservation()
        print("CHECK: cancellation and serialisation")
        try await cancellationAndSerialisation()
        print("CHECK: unresolved request and no queue")
        try await unresolvedRequestHasNoQueue()
        print("CHECK: relaunch and recovery")
        try await relaunchRecoveryAndExplicitRecovery()
        print("CHECK: credentials and destination isolation")
        try await credentialAndDestinationIsolation()
        print("CHECK: verification and stale completion")
        try await verificationAndStaleCompletionRejection()
        print("CHECK: payload and remote state rejection")
        try await invalidPayloadAndRemoteStateRejection()
        print("PASS: canonical Drive transport state, retry, update, verification, cancellation, recovery and fail-closed checks")
    }

    static func export(
        _ revision: Int,
        coordinator: CanonicalExportCoordinator,
        account: String = accountID,
        folder: String = folderID,
        tokenProvider: @escaping CanonicalExportCoordinator.TokenProvider = token
    ) async throws -> CanonicalExportResult {
        try await coordinator.export(
            payload: SyntheticPayload.data(revision),
            generation: revision,
            reportDate: reportDate,
            accountID: account,
            folderID: folder,
            tokenProvider: tokenProvider
        )
    }

    static func initialCreateAndReplacement() async throws {
        let store = TestIdentityStore()
        let server = TestDriveServer()
        await server.setReservationProbe {
            guard let identity = try? store.load()?.identities.first else { return false }
            return identity.fileID == "generated-1" && identity.pending?.phase == .submitted
        }
        let coordinator = CanonicalExportCoordinator(transport: server, store: store)
        let morningResult = try await export(1, coordinator: coordinator)
        precondition(morningResult == .verified(generation: 1, created: true))
        let savedAfterCreate = try store.load()!
        let fileID = savedAfterCreate.identities[0].fileID
        precondition(savedAfterCreate.identities[0].lastVerified?.generation == 1)
        precondition(savedAfterCreate.identities[0].pending == nil)
        let generatedIDs = await server.generatedIDs
        let createIDs = await server.createIDs
        precondition(generatedIDs == [fileID])
        precondition(createIDs == [fileID])

        let eveningResult = try await export(2, coordinator: coordinator)
        let bedtimeResult = try await export(3, coordinator: coordinator)
        let repeatedResult = try await export(3, coordinator: coordinator)
        let updateIDs = await server.updateIDs
        let fileCount = await server.fileCount()
        let finalContent = await server.storedContent(id: fileID)
        let expectedBedtime = try SyntheticPayload.data(3)
        precondition(eveningResult == .verified(generation: 2, created: false))
        precondition(bedtimeResult == .verified(generation: 3, created: false))
        precondition(repeatedResult == .unchangedVerified(generation: 3))
        precondition(updateIDs == [fileID, fileID])
        precondition(fileCount == 1)
        precondition(finalContent == expectedBedtime)
    }

    static func uncertainCreateRetriesSameID() async throws {
        let store = TestIdentityStore()
        let server = TestDriveServer()
        await server.enqueueCreate(.transientBeforeCommit)
        let coordinator = CanonicalExportCoordinator(transport: server, store: store)
        let result = try await export(1, coordinator: coordinator)
        let ids = await server.createIDs
        let generatedCount = await server.generatedIDs.count
        precondition(result == .verified(generation: 1, created: true))
        precondition(ids.count == 2 && ids[0] == ids[1])
        precondition(generatedCount == 1)
        precondition(store.saveCount >= 3, "Reservation and submitted state must persist before create completion")
    }

    static func commitThenLostResponseReconciles() async throws {
        let store = TestIdentityStore()
        let server = TestDriveServer()
        await server.enqueueCreate(.transientAfterCommit)
        let coordinator = CanonicalExportCoordinator(transport: server, store: store)
        let result = try await export(1, coordinator: coordinator)
        let createCount = await server.createIDs.count
        let fileCount = await server.fileCount()
        precondition(result == .verified(generation: 1, created: true))
        precondition(createCount == 1)
        precondition(fileCount == 1)
    }

    static func tokenRefreshAndRejectedWritePreservation() async throws {
        let store = TestIdentityStore()
        let server = TestDriveServer()
        let coordinator = CanonicalExportCoordinator(transport: server, store: store)
        _ = try await export(1, coordinator: coordinator)
        let fileID = try store.load()!.identities[0].fileID

        await server.enqueueUpdate(.unauthorized)
        let refreshedResult = try await export(2, coordinator: coordinator)
        let refreshedCount = await server.updateIDs.count
        precondition(refreshedResult == .verified(generation: 2, created: false))
        precondition(refreshedCount == 2)

        await server.enqueueUpdate(.permissionDenied)
        do {
            _ = try await export(3, coordinator: coordinator)
            preconditionFailure("Denied update must fail")
        } catch CanonicalExportFailure.permissionDenied {}
        let content = await server.storedContent(id: fileID)
        let expectedEvening = try SyntheticPayload.data(2)
        let persisted = try store.load()!.identities[0]
        precondition(content == expectedEvening)
        precondition(persisted.lastVerified?.generation == 2)
        precondition(persisted.pending == nil)
    }

    static func cancellationAndSerialisation() async throws {
        let preStore = TestIdentityStore()
        let preServer = TestDriveServer()
        await preServer.pauseGenerate()
        let preCoordinator = CanonicalExportCoordinator(transport: preServer, store: preStore)
        let preTask = Task { try await export(1, coordinator: preCoordinator) }
        await waitUntil { await preServer.isGeneratePaused() }
        await preCoordinator.requestCancellation()
        await preServer.resumeGenerate()
        let preResult = try await preTask.value
        let preCreateIDs = await preServer.createIDs
        let preIdentity = try preStore.load()!.identities[0]
        precondition(preResult == .cancelledBeforeSubmission)
        precondition(preCreateIDs.isEmpty)
        precondition(preIdentity.pending?.phase == .reserved)

        let postStore = TestIdentityStore()
        let postServer = TestDriveServer()
        let postCoordinator = CanonicalExportCoordinator(transport: postServer, store: postStore)
        _ = try await export(1, coordinator: postCoordinator)
        await postServer.pauseUpdateAfterCommit()
        let postTask = Task { try await export(2, coordinator: postCoordinator) }
        await waitUntil { await postServer.isUpdatePaused() }
        do {
            _ = try await export(3, coordinator: postCoordinator)
            preconditionFailure("A second export must not overlap")
        } catch CanonicalExportFailure.busy {}
        await postCoordinator.requestCancellation()
        await postServer.resumeUpdate()
        let postResult = try await postTask.value
        precondition(postResult == .cancelledAfterSubmissionVerified(generation: 2, created: false))
    }

    static func unresolvedRequestHasNoQueue() async throws {
        let store = TestIdentityStore()
        let server = TestDriveServer()
        let coordinator = CanonicalExportCoordinator(transport: server, store: store)
        _ = try await export(1, coordinator: coordinator)
        await server.enqueueUpdate(.transientBeforeCommit)
        await server.enqueueUpdate(.transientBeforeCommit)
        do {
            _ = try await export(2, coordinator: coordinator)
            preconditionFailure("Two uncertain submissions must remain unresolved")
        } catch CanonicalExportFailure.unresolvedRequest {}
        let count = await server.updateIDs.count
        try await Task.sleep(for: .milliseconds(20))
        let countAfterWait = await server.updateIDs.count
        precondition(countAfterWait == count, "No offline/background queue may run")
        do {
            _ = try await export(3, coordinator: coordinator)
            preconditionFailure("A newer generation must be blocked while a request is unresolved")
        } catch CanonicalExportFailure.unresolvedRequest {}
        let persisted = try store.load()!.identities[0]
        precondition(persisted.lastVerified?.generation == 1)
    }

    static func relaunchRecoveryAndExplicitRecovery() async throws {
        let persisted = TestIdentityStore()
        let server = TestDriveServer()
        let first = CanonicalExportCoordinator(transport: server, store: persisted)
        _ = try await export(1, coordinator: first)
        let identity = try persisted.load()!.identities[0]
        let relaunched = CanonicalExportCoordinator(transport: server, store: persisted)
        _ = try await export(2, coordinator: relaunched)
        let generatedCount = await server.generatedIDs.count
        let updateIDs = await server.updateIDs
        precondition(generatedCount == 1)
        precondition(updateIDs == [identity.fileID])

        let recoveredStore = TestIdentityStore()
        let recoveryCoordinator = CanonicalExportCoordinator(transport: server, store: recoveredStore)
        let recoveryResult = try await recoveryCoordinator.recover(
            selectedFileID: identity.fileID,
            reportDate: reportDate,
            accountID: accountID,
            folderID: folderID,
            tokenProvider: token
        )
        precondition(recoveryResult == .recovered(generation: 2))
        let recovered = try recoveredStore.load()!
        precondition(recovered.identities[0].fileID == identity.fileID)
        precondition(recovered.identities[0].installationID == identity.installationID)

        persisted.removeRegistryPreservingMarker()
        let missingStateCoordinator = CanonicalExportCoordinator(transport: server, store: persisted)
        do {
            _ = try await export(3, coordinator: missingStateCoordinator)
            preconditionFailure("Missing identity state with an installation marker must fail closed")
        } catch CanonicalExportFailure.identityRecoveryAmbiguous {}
        let generatedAfterLoss = await server.generatedIDs.count
        precondition(generatedAfterLoss == 1)
        let recoveredAfterLoss = try await missingStateCoordinator.recover(
            selectedFileID: identity.fileID,
            reportDate: reportDate,
            accountID: accountID,
            folderID: folderID,
            tokenProvider: token
        )
        precondition(recoveredAfterLoss == .recovered(generation: 2))
    }

    static func credentialAndDestinationIsolation() async throws {
        for credentialFailure in [SyntheticCredentialFailure.expired, .denied, .revoked] {
            let store = TestIdentityStore()
            let server = TestDriveServer()
            let coordinator = CanonicalExportCoordinator(transport: server, store: store)
            let failing: CanonicalExportCoordinator.TokenProvider = { _ in throw credentialFailure }
            do {
                _ = try await export(1, coordinator: coordinator, tokenProvider: failing)
                preconditionFailure("Rejected credentials must fail closed")
            } catch CanonicalExportFailure.credentials(let observed) {
                precondition(observed == credentialFailure)
            }
            let generatedIDs = await server.generatedIDs
            precondition(generatedIDs.isEmpty)
        }

        let store = TestIdentityStore()
        let server = TestDriveServer()
        let coordinator = CanonicalExportCoordinator(transport: server, store: store)
        _ = try await export(1, coordinator: coordinator)
        do {
            _ = try await export(2, coordinator: coordinator, folder: "folder-b")
            preconditionFailure("A destination change needs an explicit migration policy")
        } catch CanonicalExportFailure.destinationChangeRequiresMigration {}

        await server.setAccountID("account-b")
        do {
            _ = try await export(2, coordinator: coordinator)
            preconditionFailure("Account state must never be reused across accounts")
        } catch CanonicalExportFailure.accountMismatch {}
        let persisted = try store.load()!.identities[0]
        precondition(persisted.accountID == accountID)
    }

    static func verificationAndStaleCompletionRejection() async throws {
        let mismatchStore = TestIdentityStore()
        let mismatchServer = TestDriveServer()
        let mismatchCoordinator = CanonicalExportCoordinator(transport: mismatchServer, store: mismatchStore)
        _ = try await export(1, coordinator: mismatchCoordinator)
        _ = try await export(2, coordinator: mismatchCoordinator)
        await mismatchServer.overrideContent(try SyntheticPayload.data(3))
        do {
            _ = try await export(2, coordinator: mismatchCoordinator)
            preconditionFailure("Remote content must be byte-for-byte verified")
        } catch CanonicalExportFailure.remoteContentMismatch {}
        let mismatchIdentity = try mismatchStore.load()!.identities[0]
        precondition(mismatchIdentity.lastVerified?.generation == 2)

        let staleStore = TestIdentityStore()
        let staleServer = TestDriveServer()
        let staleCoordinator = CanonicalExportCoordinator(transport: staleServer, store: staleStore)
        _ = try await export(1, coordinator: staleCoordinator)
        await staleServer.pauseUpdateAfterCommit()
        let task = Task { try await export(2, coordinator: staleCoordinator) }
        await waitUntil { await staleServer.isUpdatePaused() }
        staleStore.mutate { registry in
            guard let pending = registry.identities[0].pending else { return }
            registry.identities[0].pending = PendingSyntheticOperation(
                operationID: "newer-operation",
                generation: pending.generation,
                payloadSHA256: pending.payloadSHA256,
                kind: pending.kind,
                phase: pending.phase
            )
        }
        await staleServer.resumeUpdate()
        do {
            _ = try await task.value
            preconditionFailure("A stale completion must not become verified state")
        } catch CanonicalExportFailure.staleCompletion {}
        let staleIdentity = try staleStore.load()!.identities[0]
        precondition(staleIdentity.lastVerified?.generation == 1)
    }

    static func invalidPayloadAndRemoteStateRejection() async throws {
        let store = TestIdentityStore()
        let server = TestDriveServer()
        let coordinator = CanonicalExportCoordinator(transport: server, store: store)
        do {
            _ = try await coordinator.export(
                payload: Data(#"{"synthetic_only":true,"marker":"invented-but-not-approved"}"#.utf8),
                generation: 4,
                reportDate: reportDate,
                accountID: accountID,
                folderID: folderID,
                tokenProvider: token
            )
            preconditionFailure("Only the three fixed invented fixtures are admitted")
        } catch CanonicalExportFailure.invalidSyntheticPayload {}

        _ = try await export(1, coordinator: coordinator)
        await server.overrideParent("different-folder")
        do {
            _ = try await export(1, coordinator: coordinator)
            preconditionFailure("A moved file must fail verification")
        } catch CanonicalExportFailure.remoteMoved {}
        await server.overrideParent(nil)
        await server.setTrashed(true)
        do {
            _ = try await export(1, coordinator: coordinator)
            preconditionFailure("A trashed file must fail verification")
        } catch CanonicalExportFailure.remoteTrashed {}
    }

    static func waitUntil(_ predicate: @escaping () async -> Bool) async {
        for _ in 0..<1_000 {
            if await predicate() { return }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for deterministic test gate")
    }
}
