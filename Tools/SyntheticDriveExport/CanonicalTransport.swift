import Foundation

// Test-only transport interposer for build-6 device acceptance. It never changes
// request bodies, identifiers, scopes or destinations. Its bounded modes either
// suppress a request before it reaches Drive, discard a successful response, or
// inject cancellation at a precisely defined coordinator boundary.
actor AdverseProbeDriveTransport: DriveTransporting {
    enum Mode: Sendable {
        case retryNextCreateAfterLostResponse
        case loseNextResponseAfterCommit
        case cancelBeforeSubmission
        case cancelAfterSubmission
        case loseNextTwoSubmissionsBeforeCommit
    }

    enum Observation: String, Equatable, Sendable {
        case createRetriedAfterLostResponseWithSameReservedID
        case responseLostAfterCommit
        case cancellationInjectedBeforeSubmission
        case cancellationInjectedAfterSubmission
        case twoSubmissionsDroppedWithSameStoredID

        var userFacingLabel: String {
            switch self {
            case .createRetriedAfterLostResponseWithSameReservedID:
                return "Probe discarded the committed create response and verified that the conflict retry used the same reserved file ID."
            case .responseLostAfterCommit:
                return "Probe discarded the successful submission response; Drive readback established the outcome."
            case .cancellationInjectedBeforeSubmission:
                return "Probe injected cancellation after account validation and before file submission."
            case .cancellationInjectedAfterSubmission:
                return "Probe injected cancellation only after Drive accepted the file submission."
            case .twoSubmissionsDroppedWithSameStoredID:
                return "Probe dropped both bounded submissions before commit using the same stored file ID."
            }
        }
    }

    enum Failure: Error, Sendable {
        case alreadyArmed
        case missingCancellationHandler
        case unexpectedOperation
        case fileIdentityChanged
    }

    typealias CancellationHandler = @Sendable () async -> Void

    private enum SubmissionKind { case create, update }

    private let base: any DriveTransporting
    private var mode: Mode?
    private var cancellationHandler: CancellationHandler?
    private var submissionCount = 0
    private var firstFileID: String?
    private var hideNextMetadataRead = false
    private var observation: Observation?

    init(base: any DriveTransporting) {
        self.base = base
    }

    func arm(_ mode: Mode, cancellationHandler: CancellationHandler? = nil) throws {
        guard self.mode == nil else { throw Failure.alreadyArmed }
        switch mode {
        case .cancelBeforeSubmission, .cancelAfterSubmission:
            guard cancellationHandler != nil else { throw Failure.missingCancellationHandler }
        default:
            break
        }
        self.mode = mode
        self.cancellationHandler = cancellationHandler
        submissionCount = 0
        firstFileID = nil
        observation = nil
    }

    func takeObservation() -> Observation? {
        defer { observation = nil }
        return observation
    }

    func clear() {
        disarm()
    }

    func account(accessToken: String) async throws -> DriveAccount {
        let account = try await base.account(accessToken: accessToken)
        if case .cancelBeforeSubmission? = mode {
            guard let cancellationHandler else { throw Failure.missingCancellationHandler }
            await cancellationHandler()
            observation = .cancellationInjectedBeforeSubmission
            disarm()
        }
        return account
    }

    func generateFileID(accessToken: String) async throws -> String {
        try await base.generateFileID(accessToken: accessToken)
    }

    func createFile(
        _ descriptor: DriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        if case .retryNextCreateAfterLostResponse? = mode {
            if submissionCount == 0 {
                submissionCount = 1
                firstFileID = descriptor.id
                try await base.createFile(descriptor, content: content, accessToken: accessToken)
                hideNextMetadataRead = true
                throw URLError(.networkConnectionLost)
            }
            guard submissionCount == 1, firstFileID == descriptor.id else {
                throw Failure.fileIdentityChanged
            }
            submissionCount = 2
            do {
                try await base.createFile(descriptor, content: content, accessToken: accessToken)
                throw Failure.unexpectedOperation
            } catch DriveAPI.Failure.httpStatus(409, _) {
                observation = .createRetriedAfterLostResponseWithSameReservedID
                disarm()
                throw DriveAPI.Failure.httpStatus(409, nil)
            }
        }
        if try shouldDropBeforeCommit(kind: .create, fileID: descriptor.id) {
            throw URLError(.networkConnectionLost)
        }
        try await base.createFile(descriptor, content: content, accessToken: accessToken)
        try await finishSuccessfulSubmission(kind: .create, fileID: descriptor.id)
    }

    func updateFile(
        _ descriptor: DriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        if try shouldDropBeforeCommit(kind: .update, fileID: descriptor.id) {
            throw URLError(.networkConnectionLost)
        }
        try await base.updateFile(descriptor, content: content, accessToken: accessToken)
        try await finishSuccessfulSubmission(kind: .update, fileID: descriptor.id)
    }

    func fileMetadata(id: String, accessToken: String) async throws -> DriveFileMetadata {
        if hideNextMetadataRead {
            hideNextMetadataRead = false
            throw DriveAPI.Failure.httpStatus(404, nil)
        }
        return try await base.fileMetadata(id: id, accessToken: accessToken)
    }

    func fileContent(id: String, accessToken: String) async throws -> Data {
        try await base.fileContent(id: id, accessToken: accessToken)
    }

    private func shouldDropBeforeCommit(kind: SubmissionKind, fileID: String) throws -> Bool {
        switch mode {
        case .loseNextTwoSubmissionsBeforeCommit:
            submissionCount += 1
            if firstFileID == nil { firstFileID = fileID }
            guard firstFileID == fileID, submissionCount <= 2 else {
                throw Failure.fileIdentityChanged
            }
            if submissionCount == 2 {
                observation = .twoSubmissionsDroppedWithSameStoredID
                disarm()
            }
            return true
        default:
            return false
        }
    }

    private func finishSuccessfulSubmission(kind: SubmissionKind, fileID: String) async throws {
        switch mode {
        case .loseNextResponseAfterCommit:
            observation = .responseLostAfterCommit
            disarm()
            throw URLError(.networkConnectionLost)
        case .cancelAfterSubmission:
            guard let cancellationHandler else { throw Failure.missingCancellationHandler }
            await cancellationHandler()
            observation = .cancellationInjectedAfterSubmission
            disarm()
        default:
            break
        }
    }

    private func disarm() {
        mode = nil
        cancellationHandler = nil
        submissionCount = 0
        firstFileID = nil
        hideNextMetadataRead = false
    }
}
