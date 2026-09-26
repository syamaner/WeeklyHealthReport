import DriveExportKit

extension DailyDriveConsentPolicy.Failure {
    var userFacingLabel: String {
        switch self {
        case .missingDriveFileScope: "drive.file was not granted"
        case .unexpectedScope: "an unexpected broader or identity scope was returned"
        case .invalidPickerSelection: "selection did not return exactly one item"
        case .accountMismatch: "account mismatch"
        case .notAppAuthorized: "the folder was not explicitly authorised for this app"
        case .notFolder: "the selection is not a folder"
        case .trashed: "the folder is trashed"
        case .sharedDriveUnsupported: "Shared Drives are unsupported"
        case .notWritable: "the folder cannot accept children"
        }
    }
}

extension DailyDriveExportResult {
    var verifiedLabel: String {
        switch self {
        case .verified(let dataAsOf, _), .unchangedVerified(let dataAsOf),
             .cancelledAfterSubmissionVerified(let dataAsOf, _):
            "Verified through \(DailyHealthExportIdentityPolicy.displayOrderingToken(dataAsOf))"
        case .cancelledBeforeSubmission:
            "No new verified upload"
        }
    }

    var userFacingLabel: String {
        switch self {
        case .verified(let dataAsOf, _):
            "Upload metadata and bytes verified remotely for \(DailyHealthExportIdentityPolicy.displayOrderingToken(dataAsOf))."
        case .unchangedVerified(let dataAsOf):
            "The unchanged \(DailyHealthExportIdentityPolicy.displayOrderingToken(dataAsOf)) snapshot was reverified; no write ran."
        case .cancelledBeforeSubmission:
            "Cancelled before submission. The last verified Drive file was preserved."
        case .cancelledAfterSubmissionVerified(let dataAsOf, _):
            "Cancellation followed submission; reconciliation verified \(DailyHealthExportIdentityPolicy.displayOrderingToken(dataAsOf))."
        }
    }
}

extension DailyDriveRecoveryResult {
    var verifiedLabel: String {
        switch self {
        case .recovered(let dataAsOf), .alreadyTracked(let dataAsOf),
             .migrated(let dataAsOf):
            "Recovered and verified through \(DailyHealthExportIdentityPolicy.displayOrderingToken(dataAsOf))"
        }
    }

    var userFacingLabel: String {
        switch self {
        case .recovered(let dataAsOf):
            "Explicit recovery verified the selected canonical file through \(DailyHealthExportIdentityPolicy.displayOrderingToken(dataAsOf))."
        case .alreadyTracked(let dataAsOf):
            "The selected canonical file was already tracked and reverified through \(DailyHealthExportIdentityPolicy.displayOrderingToken(dataAsOf))."
        case .migrated(let dataAsOf):
            "The selected canonical file was safely migrated to this destination and verified through \(DailyHealthExportIdentityPolicy.displayOrderingToken(dataAsOf))."
        }
    }
}

extension DailyDriveExportFailure {
    var userFacingLabel: String {
        switch self {
        case .busy: "Another export or reconciliation is active."
        case .invalidPayload: "The preview is not canonical daily-export JSON."
        case .staleSnapshot: "A stale or conflicting snapshot was rejected; the last verified file is unchanged."
        case .destinationChangeRequiresMigration: "The selected destination differs from this date's canonical file identity. Explicitly recover that JSON file to migrate it safely."
        case .accountMismatch: "Export is blocked by a Google account mismatch."
        case .identityRecoveryAmbiguous: "Export is blocked because canonical identity recovery is ambiguous."
        case .staleCompletion: "A stale completion was rejected; the last verified file was preserved."
        case .credentials(let reason): "Google credentials are \(reason.rawValue). Reconnect before exporting."
        case .credentialsRejected: "Google credentials were expired, denied or revoked. Reconnect before exporting."
        case .permissionDenied: "Google denied the operation. No broader permission will be requested."
        case .quotaExceeded: "Drive quota is exhausted. No retry was queued."
        case .rateLimited: "Drive rate-limited the request. No background retry was queued."
        case .remoteMissing: "The stored Drive file is missing or inaccessible. Confirm an explicit override before creating a replacement."
        case .remoteMoved: "The canonical file moved outside the validated destination. Choose its current folder, then explicitly recover that JSON file."
        case .remoteTrashed: "The stored file is trashed. Confirm replacement before creating a new file ID."
        case .remoteMetadataMismatch: "Remote metadata did not match the canonical identity."
        case .remoteContentMismatch: "Remote bytes did not match the reviewed preview."
        case .unresolvedRequest: "The submitted request is unresolved. New writes are blocked; no retry is queued."
        case .persistenceFailure: "Secure export identity state could not be persisted."
        case .transportFailure: "The Drive request failed. Upload is unverified and no retry was queued."
        }
    }
}
