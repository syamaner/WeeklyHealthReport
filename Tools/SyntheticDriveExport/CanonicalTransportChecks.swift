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

struct AmbiguousIdentityStore: CanonicalExportIdentityPersisting {
    func load() throws -> CanonicalExportRegistry? {
        throw CanonicalExportFailure.identityRecoveryAmbiguous
    }

    func installationMarker() throws -> String? { nil }

    func save(_ registry: CanonicalExportRegistry) throws {}
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
        print("CHECK: synthetic payload identity policy")
        try syntheticPayloadIdentityPolicy()
        print("CHECK: initial create and replacement")
        try await initialCreateAndReplacement()
        print("CHECK: build-6 bounded device probe controls")
        try await boundedDeviceProbeControls()
        print("PASS: synthetic fixture policy, shared coordinator happy path and bounded adverse probe controls")
    }

    static func syntheticPayloadIdentityPolicy() throws {
        let policy = SyntheticFixtureIdentityPolicy()
        for revision in 1...3 {
            let payload = try SyntheticPayload.data(revision)
            let identity = try policy.validate(payload: payload, reportDate: reportDate)
            precondition(identity.orderingToken == String(revision))
            precondition(identity.payloadSHA256 == CanonicalExportCoordinator.sha256(payload))
        }
        let ascending = try policy.compare("1", "2")
        let same = try policy.compare("2", "2")
        let descending = try policy.compare("3", "2")
        precondition(ascending == .orderedAscending)
        precondition(same == .orderedSame)
        precondition(descending == .orderedDescending)
        do {
            _ = try policy.validate(payload: Data("foreign".utf8), reportDate: reportDate)
            preconditionFailure("Foreign bytes must not be admitted")
        } catch {}
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
            reportDate: reportDate,
            accountID: account,
            folderID: folder,
            tokenProvider: tokenProvider
        )
    }

    static func exportAdverse(
        _ revision: Int,
        coordinator: CanonicalExportCoordinator
    ) async throws -> CanonicalExportResult {
        try await coordinator.export(
            payload: SyntheticPayload.data(revision, reportDate: SyntheticPayload.adverseReportDate),
            reportDate: SyntheticPayload.adverseReportDate,
            accountID: accountID,
            folderID: folderID,
            tokenProvider: token
        )
    }

    static func boundedDeviceProbeControls() async throws {
        precondition(SyntheticPayload.filename == "health-daily-2026-09-06.json")
        precondition(SyntheticPayload.filename(for: SyntheticPayload.adverseReportDate) == "health-daily-2026-09-07.json")
        let adverseMorning = try SyntheticPayload.data(1, reportDate: SyntheticPayload.adverseReportDate)
        let adverseMorningRevision = try SyntheticPayload.revision(
            in: adverseMorning,
            reportDate: SyntheticPayload.adverseReportDate
        )
        precondition(adverseMorningRevision == 1)
        do {
            _ = try SyntheticPayload.revision(in: adverseMorning)
            preconditionFailure("Adverse bytes must not be admitted as the accepted fixture date")
        } catch {}

        let server = TestDriveServer()
        let probe = AdverseProbeDriveTransport(base: server)
        let coordinator = CanonicalExportCoordinator(transport: probe, store: TestIdentityStore())

        let acceptedResult = try await export(3, coordinator: coordinator)
        precondition(acceptedResult == .verified(dataAsOf: "3", created: true))

        try await probe.arm(.retryNextCreateAfterLostResponse)
        let createResult = try await exportAdverse(1, coordinator: coordinator)
        let createObservation = await probe.takeObservation()
        let countAfterCreate = await server.fileCount()
        precondition(createResult == .verified(dataAsOf: "1", created: true))
        precondition(createObservation == .createRetriedAfterLostResponseWithSameReservedID)
        precondition(countAfterCreate == 2)
        let createIDs = await server.createIDs
        precondition(createIDs.count == 3 && createIDs[1] == createIDs[2])
        precondition(createIDs[0] != createIDs[1])

        try await probe.arm(
            .cancelBeforeSubmission,
            cancellationHandler: { await coordinator.requestCancellation() }
        )
        let preCancellationResult = try await exportAdverse(2, coordinator: coordinator)
        let preCancellationObservation = await probe.takeObservation()
        let updatesAfterPreCancellation = await server.updateIDs
        precondition(preCancellationResult == .cancelledBeforeSubmission)
        precondition(preCancellationObservation == .cancellationInjectedBeforeSubmission)
        precondition(updatesAfterPreCancellation.isEmpty)

        try await probe.arm(.loseNextTwoSubmissionsBeforeCommit)
        do {
            _ = try await exportAdverse(2, coordinator: coordinator)
            preconditionFailure("Two dropped submissions must remain unresolved")
        } catch CanonicalExportFailure.unresolvedRequest {}
        let unresolvedObservation = await probe.takeObservation()
        let updatesAfterLosses = await server.updateIDs
        precondition(unresolvedObservation == .twoSubmissionsDroppedWithSameStoredID)
        precondition(updatesAfterLosses.isEmpty)

        try await probe.arm(.loseNextResponseAfterCommit)
        let lostResponseResult = try await exportAdverse(2, coordinator: coordinator)
        let lostResponseObservation = await probe.takeObservation()
        precondition(lostResponseResult == .verified(dataAsOf: "2", created: false))
        precondition(lostResponseObservation == .responseLostAfterCommit)

        try await probe.arm(
            .cancelAfterSubmission,
            cancellationHandler: { await coordinator.requestCancellation() }
        )
        let postCancellationResult = try await exportAdverse(3, coordinator: coordinator)
        let postCancellationObservation = await probe.takeObservation()
        let finalCount = await server.fileCount()
        precondition(postCancellationResult == .cancelledAfterSubmissionVerified(dataAsOf: "3", created: false))
        precondition(postCancellationObservation == .cancellationInjectedAfterSubmission)
        precondition(finalCount == 2)
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
        precondition(morningResult == .verified(dataAsOf: "1", created: true))
        let savedAfterCreate = try store.load()!
        let fileID = savedAfterCreate.identities[0].fileID
        precondition(savedAfterCreate.identities[0].lastVerified?.dataAsOf == "1")
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
        precondition(eveningResult == .verified(dataAsOf: "2", created: false))
        precondition(bedtimeResult == .verified(dataAsOf: "3", created: false))
        precondition(repeatedResult == .unchangedVerified(dataAsOf: "3"))
        precondition(updateIDs == [fileID, fileID])
        precondition(fileCount == 1)
        precondition(finalContent == expectedBedtime)
    }

}
