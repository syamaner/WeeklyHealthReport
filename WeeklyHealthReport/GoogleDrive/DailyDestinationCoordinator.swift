import DriveExportKit
import Foundation

@MainActor
final class DailyDestinationCoordinator {
    enum FileReplacementReason { case trashed, missingOrInaccessible }
    enum Failure: Error { case noDestination }

    private struct FileReplacementCandidate: Equatable {
        let accountID: String
        let folderID: String
        let reportDate: String
    }

    private let drive: any DailyDriveSessionTransporting
    private let secureStore: any DailyDriveSecurePersisting
    private let destinationsKey: String

    private var partitions = DailyDestinationPartitions()
    private var trashedDestinationCandidate: DailyDestinationBinding?
    private var fileReplacementCandidate: FileReplacementCandidate?
    private(set) var destinationPartitionsAvailable = true
    private(set) var fileReplacementReason: FileReplacementReason?

    var canForgetTrashedDestination: Bool {
        trashedDestinationCandidate != nil
    }

    init(
        drive: any DailyDriveSessionTransporting,
        secureStore: any DailyDriveSecurePersisting,
        destinationsKey: String
    ) {
        self.drive = drive
        self.secureStore = secureStore
        self.destinationsKey = destinationsKey
    }

    func restoreWithoutNetwork() throws {
        do {
            if let data = try secureStore.load(account: destinationsKey) {
                partitions = try JSONDecoder().decode(DailyDestinationPartitions.self, from: data)
            }
        } catch {
            destinationPartitionsAvailable = false
            throw error
        }
    }

    func activeDestination(for accountID: String?) -> DailyDestinationBinding? {
        guard let accountID else { return nil }
        return partitions.destination(for: accountID)
    }

    func destinationLabel(for accountID: String) -> String {
        partitions.destination(for: accountID)?.folderName ?? "Choose or create a destination"
    }

    func storedDestination(for accountID: String) throws -> DailyDestinationBinding? {
        guard destinationPartitionsAvailable else {
            throw DailyExportPreparationFailure.destinationSetupFailed
        }
        return partitions.destination(for: accountID)
    }

    func validateStoredDestination(
        _ binding: DailyDestinationBinding,
        context: DailyExportGoogleContext
    ) async throws {
        do {
            let folder = try await drive.folder(
                id: binding.folderID,
                accessToken: context.accessToken,
                accountID: context.account.id
            )
            try validate(folder, binding: binding, accountID: context.account.id)
            try accept(
                folder: folder,
                origin: binding.origin == .pendingCreate ? .created : binding.origin,
                accountID: context.account.id
            )
        } catch DailyDriveConsentPolicy.Failure.trashed {
            throw DailyExportPreparationFailure.destinationTrashed
        } catch DailyDriveAPI.Failure.httpStatus(401, _) {
            throw DailyExportPreparationFailure.freshGoogleConsentRequired
        } catch DailyDriveAPI.Failure.httpStatus(404, _)
            where binding.origin == .pendingCreate {
            try await submitReservedDefaultDestination(binding, context: context)
        } catch DailyDriveAPI.Failure.httpStatus(403, _),
                DailyDriveAPI.Failure.httpStatus(404, _) {
            throw DailyExportPreparationFailure.destinationMissingOrInaccessible
        } catch let failure as DailyDriveConsentPolicy.Failure {
            if failure == .trashed {
                throw DailyExportPreparationFailure.destinationTrashed
            }
            throw DailyExportPreparationFailure.destinationMissingOrInaccessible
        } catch {
            throw DailyExportPreparationFailure.destinationMissingOrInaccessible
        }
    }

    func createDefaultDestination(context: DailyExportGoogleContext) async throws {
        guard destinationPartitionsAvailable else {
            throw DailyExportPreparationFailure.destinationSetupFailed
        }
        if let binding = partitions.destination(for: context.account.id) {
            try await validateStoredDestination(binding, context: context)
            return
        }
        do {
            let folderID = try await drive.generateFileID(accessToken: context.accessToken)
            let binding = DailyDestinationBinding(
                accountID: context.account.id,
                folderID: folderID,
                folderName: DailyDriveConsentPolicy.defaultExportFolderName,
                origin: .pendingCreate
            )
            var updatedPartitions = partitions
            updatedPartitions.bind(binding)
            try persist(updatedPartitions)
            partitions = updatedPartitions
            try await submitReservedDefaultDestination(binding, context: context)
        } catch DailyDriveAPI.Failure.httpStatus(401, _) {
            throw DailyExportPreparationFailure.freshGoogleConsentRequired
        } catch let failure as DailyExportPreparationFailure {
            throw failure
        } catch {
            throw DailyExportPreparationFailure.destinationSetupFailed
        }
    }

    func acceptPickedFolder(_ folder: DailyDriveFolder, accountID: String) throws {
        try DailyDriveConsentPolicy.validate(folder: folder, expectedAccountID: accountID)
        try accept(folder: folder, origin: .picker, accountID: accountID)
    }

    func acceptAccount(_ accountID: String) {
        if trashedDestinationCandidate?.accountID != accountID {
            clearTrashedDestinationCandidate()
        }
        if fileReplacementCandidate?.accountID != accountID {
            clearFileReplacementCandidate()
        }
    }

    func trashedDestination(for accountID: String) -> DailyDestinationBinding? {
        guard let candidate = trashedDestinationCandidate,
              candidate.accountID == accountID,
              activeDestination(for: accountID) == candidate else { return nil }
        return candidate
    }

    func fileReplacementCandidate(
        accountID: String,
        folderID: String?
    ) -> (accountID: String, folderID: String, reportDate: String)? {
        guard let candidate = fileReplacementCandidate,
              candidate.accountID == accountID,
              candidate.folderID == folderID else { return nil }
        return (candidate.accountID, candidate.folderID, candidate.reportDate)
    }

    func clearCandidates() {
        clearTrashedDestinationCandidate()
        clearFileReplacementCandidate()
    }

    func forgetTrashedDestination(_ candidate: DailyDestinationBinding) throws {
        var updatedPartitions = partitions
        guard updatedPartitions.unbind(
            accountID: candidate.accountID,
            folderID: candidate.folderID
        ) else {
            throw Failure.noDestination
        }
        try persist(updatedPartitions)
        partitions = updatedPartitions
        clearTrashedDestinationCandidate()
        clearFileReplacementCandidate()
    }

    func markFileForReplacement(
        accountID: String,
        folderID: String,
        reportDate: String,
        reason: FileReplacementReason
    ) {
        fileReplacementCandidate = FileReplacementCandidate(
            accountID: accountID,
            folderID: folderID,
            reportDate: reportDate
        )
        fileReplacementReason = reason
    }

    func clearFileReplacementCandidate(
        accountID: String? = nil,
        folderID: String? = nil,
        reportDate: String? = nil
    ) {
        if let candidate = fileReplacementCandidate,
           let accountID, let folderID, let reportDate,
           candidate != FileReplacementCandidate(
               accountID: accountID,
               folderID: folderID,
               reportDate: reportDate
           ) {
            return
        }
        fileReplacementCandidate = nil
        fileReplacementReason = nil
    }

    func clearFileReplacementCandidate(unlessReportDate reportDate: String) {
        guard fileReplacementCandidate?.reportDate != reportDate else { return }
        clearFileReplacementCandidate()
    }

    private func submitReservedDefaultDestination(
        _ binding: DailyDestinationBinding,
        context: DailyExportGoogleContext
    ) async throws {
        let folder: DailyDriveFolder
        do {
            folder = try await drive.createFolder(
                id: binding.folderID,
                accessToken: context.accessToken,
                accountID: context.account.id
            )
        } catch DailyDriveAPI.Failure.httpStatus(401, _) {
            throw DailyExportPreparationFailure.freshGoogleConsentRequired
        } catch {
            do {
                folder = try await drive.folder(
                    id: binding.folderID,
                    accessToken: context.accessToken,
                    accountID: context.account.id
                )
            } catch DailyDriveAPI.Failure.httpStatus(401, _) {
                throw DailyExportPreparationFailure.freshGoogleConsentRequired
            } catch {
                throw DailyExportPreparationFailure.destinationSetupFailed
            }
        }
        do {
            try DailyDriveConsentPolicy.validate(
                folder: folder,
                expectedAccountID: context.account.id
            )
            try accept(folder: folder, origin: .created, accountID: context.account.id)
        } catch {
            throw DailyExportPreparationFailure.destinationSetupFailed
        }
    }

    private func accept(
        folder: DailyDriveFolder,
        origin: DailyDestinationBinding.Origin,
        accountID: String
    ) throws {
        clearTrashedDestinationCandidate()
        if fileReplacementCandidate?.accountID != accountID
            || fileReplacementCandidate?.folderID != folder.id {
            clearFileReplacementCandidate()
        }
        var updatedPartitions = partitions
        updatedPartitions.bind(DailyDestinationBinding(
            accountID: accountID,
            folderID: folder.id,
            folderName: folder.name,
            origin: origin
        ))
        try persist(updatedPartitions)
        partitions = updatedPartitions
    }

    private func validate(
        _ folder: DailyDriveFolder,
        binding: DailyDestinationBinding,
        accountID: String
    ) throws {
        do {
            try DailyDriveConsentPolicy.validate(folder: folder, expectedAccountID: accountID)
            clearTrashedDestinationCandidate()
        } catch DailyDriveConsentPolicy.Failure.trashed {
            trashedDestinationCandidate = binding
            throw DailyDriveConsentPolicy.Failure.trashed
        }
    }

    private func clearTrashedDestinationCandidate() {
        trashedDestinationCandidate = nil
    }

    private func persist(_ partitions: DailyDestinationPartitions) throws {
        try secureStore.save(try JSONEncoder().encode(partitions), account: destinationsKey)
    }
}
