import Foundation

@main enum PolicyChecks {
    static func main() throws {
        var policy = ExportPolicy(highestSubmitted: 0)
        precondition(policy.begin(1))
        precondition(!policy.begin(2), "Only one picker at a time")
        policy.finish()
        precondition(policy.begin(3))
        policy.finish() // Cancellation/failure must not lower the watermark.
        precondition(!policy.begin(2))
        precondition(policy.begin(3), "Identical revision can be retried")
        policy.finish()
        var relaunched = ExportPolicy(highestSubmitted: policy.highestSubmitted)
        precondition(!relaunched.begin(1))
        precondition(relaunched.begin(3))
        for revision in 1...3 {
            let data = try SyntheticPayload.data(revision)
            let repeated = try SyntheticPayload.data(revision)
            precondition(data == repeated)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            precondition(json["revision"] as? Int == revision)
            precondition(json["synthetic_only"] as? Bool == true)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent(DirectoryProbe.folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = folder.appendingPathComponent(SyntheticPayload.filename)
        _ = try DirectoryProbe.write(1, in: folder)
        _ = try DirectoryProbe.write(2, in: folder)
        let evening = try Data(contentsOf: file)
        let expectedEvening = try SyntheticPayload.data(2)
        precondition(evening == expectedEvening)
        precondition(tryCount(folder) == 1)
        let repeatedResult = try DirectoryProbe.write(2, in: folder)
        precondition(repeatedResult.contains("no write"))
        do {
            _ = try DirectoryProbe.write(1, in: folder)
            preconditionFailure("Must reject old content")
        } catch DirectoryProbe.Failure.staleRevision {}
        do {
            _ = try DirectoryProbe.write(3, in: folder, injectFailure: true)
            preconditionFailure("Expected injected failure")
        } catch DirectoryProbe.Failure.injectedFailure {}
        let preserved = try Data(contentsOf: file)
        precondition(preserved == evening)
        let extra = folder.appendingPathComponent("unexpected.json")
        try Data("untouched".utf8).write(to: extra)
        do {
            _ = try DirectoryProbe.write(3, in: folder)
            preconditionFailure("Must reject unexpected folder contents")
        } catch DirectoryProbe.Failure.unexpectedContents {}
        let stillPreserved = try Data(contentsOf: file)
        precondition(stillPreserved == evening)
        _ = try ExistingFileProbe.write(3, at: file)
        let bedtime = try Data(contentsOf: file)
        let expectedBedtime = try SyntheticPayload.data(3)
        precondition(bedtime == expectedBedtime)
        let existingRepeat = try ExistingFileProbe.write(3, at: file)
        precondition(existingRepeat.contains("no write"))
        do {
            _ = try ExistingFileProbe.write(2, at: file)
            preconditionFailure("Existing-file route must reject stale content")
        } catch DirectoryProbe.Failure.staleRevision {}
        do {
            _ = try ExistingFileProbe.write(3, at: file, injectFailure: true)
            preconditionFailure("Expected existing-file failure")
        } catch DirectoryProbe.Failure.injectedFailure {}
        let afterFailure = try Data(contentsOf: file)
        precondition(afterFailure == bedtime)
        try Data("unknown content".utf8).write(to: file)
        do {
            _ = try ExistingFileProbe.write(3, at: file)
            preconditionFailure("Must refuse unknown existing content")
        } catch DirectoryProbe.Failure.unknownPayload {}
        let unknownPreserved = try Data(contentsOf: file)
        precondition(unknownPreserved == Data("unknown content".utf8))
        try consentAndDestinationChecks()
        print("PASS: existing-file replacement, repeat no-op, stale rejection, injected failure and unknown-content preservation")
        print("PASS: admission, stale rejection, retry, restored watermark, deterministic JSON; local coordinated create/replace, no-op repeat, injected failure preservation and unexpected-content refusal")
        print("PASS: exact drive.file scope, Picker selection, account partitioning, folder admission and revoke transitions")
    }

    static func tryCount(_ folder: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).count) ?? -1
    }

    static func consentAndDestinationChecks() throws {
        try DriveConsentPolicy.validateGrantedScopes(DriveConsentPolicy.scope)
        for badScope in [nil, "openid \(DriveConsentPolicy.scope)", "https://www.googleapis.com/auth/drive"] {
            do {
                try DriveConsentPolicy.validateGrantedScopes(badScope)
                preconditionFailure("Must reject missing, identity or broad Drive scopes")
            } catch is DriveConsentPolicy.Failure {}
        }
        let selectedFolder = try DriveConsentPolicy.selectedFolderID(from: "folder-1")
        precondition(selectedFolder == "folder-1")
        for invalidSelection: Any? in [nil, "", "folder-1,folder-2", 42] {
            do {
                _ = try DriveConsentPolicy.selectedFolderID(from: invalidSelection)
                preconditionFailure("Must require exactly one Picker folder")
            } catch DriveConsentPolicy.Failure.invalidPickerSelection {}
        }

        let valid = DriveFolderMetadata(
            id: "folder-1", accountID: "account-a", name: "WeeklyHealthReport Exports",
            mimeType: DriveConsentPolicy.folderMIMEType, trashed: false, driveID: nil,
            isAppAuthorized: true, canAddChildren: true
        )
        try DriveConsentPolicy.validate(folder: valid, expectedAccountID: "account-a")
        let invalidFolders = [
            DriveFolderMetadata(id: "1", accountID: "account-b", name: "x", mimeType: valid.mimeType, trashed: false, driveID: nil, isAppAuthorized: true, canAddChildren: true),
            DriveFolderMetadata(id: "1", accountID: valid.accountID, name: "x", mimeType: "application/json", trashed: false, driveID: nil, isAppAuthorized: true, canAddChildren: true),
            DriveFolderMetadata(id: "1", accountID: valid.accountID, name: "x", mimeType: valid.mimeType, trashed: true, driveID: nil, isAppAuthorized: true, canAddChildren: true),
            DriveFolderMetadata(id: "1", accountID: valid.accountID, name: "x", mimeType: valid.mimeType, trashed: false, driveID: "shared", isAppAuthorized: true, canAddChildren: true),
            DriveFolderMetadata(id: "1", accountID: valid.accountID, name: "x", mimeType: valid.mimeType, trashed: false, driveID: nil, isAppAuthorized: false, canAddChildren: true),
            DriveFolderMetadata(id: "1", accountID: valid.accountID, name: "x", mimeType: valid.mimeType, trashed: false, driveID: nil, isAppAuthorized: true, canAddChildren: false)
        ]
        for invalid in invalidFolders {
            do {
                try DriveConsentPolicy.validate(folder: invalid, expectedAccountID: "account-a")
                preconditionFailure("Must reject invalid folder metadata")
            } catch is DriveConsentPolicy.Failure {}
        }

        var partitions = DestinationPartitions()
        let first = DestinationBinding(accountID: "account-a", folderID: "folder-a", folderName: "A", origin: .created)
        let second = DestinationBinding(accountID: "account-b", folderID: "folder-b", folderName: "B", origin: .picker)
        partitions.bind(first)
        partitions.bind(second)
        precondition(partitions.destination(for: "account-a") == first)
        precondition(partitions.destination(for: "account-b") == second)
        precondition(partitions.destination(for: "account-c") == nil)
        precondition(DisconnectTransition.afterRevocation(statusCode: 200) == .clearCredentialsPreserveDestinations)
        precondition(DisconnectTransition.afterRevocation(statusCode: 400) == .keepCredentialsAndReportFailure)
    }
}
