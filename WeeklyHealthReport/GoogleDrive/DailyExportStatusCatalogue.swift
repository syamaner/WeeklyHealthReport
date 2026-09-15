import DriveExportKit
import DriveExportOAuth
import Foundation

struct DailyExportFailureResolution {
    let presentationState: DailyExportPresentationState?
    let statusOverride: String?
    let invalidatesPreview: Bool
}

enum DailyExportStatusCatalogue {
    static func status(
        for state: DailyExportPresentationState,
        hasStoredSession: Bool
    ) -> String {
        switch state {
        case .preparing:
            "Restoring the saved account, destination and nutrition source…"
        case .needsGoogleConnection:
            hasStoredSession
                ? "The stored Google session needs fresh consent before export can continue."
                : "Connect Google to continue. No Health or Drive request ran."
        case .needsNutritionSource:
            "Choose a nutrition source explicitly. Opening this screen did not request Health access."
        case .readyToExport:
            "Fresh preview created in memory. Review the snapshot, then choose Export."
        case .needsAttention(let attention):
            status(for: attention)
        }
    }

    static func resolve(_ error: Error) -> DailyExportFailureResolution {
        if let failure = error as? DailyExportPreparationFailure {
            return resolution(for: failure)
        }
        if let failure = error as? DailyDriveConsentPolicy.Failure {
            let attention: DailyExportAttention = failure == .trashed
                ? .destinationTrashed
                : .destinationMissingOrInaccessible
            return DailyExportFailureResolution(
                presentationState: .needsAttention(attention),
                statusOverride: "Rejected by consent/destination policy: \(failure.userFacingLabel).",
                invalidatesPreview: false
            )
        }
        if let failure = error as? DailyDriveExportFailure {
            let state: DailyExportPresentationState
            switch failure {
            case .credentials, .credentialsRejected:
                state = .needsGoogleConnection
            case .remoteMissing, .remoteTrashed, .remoteMoved,
                 .destinationChangeRequiresMigration, .identityRecoveryAmbiguous:
                state = .needsAttention(.canonicalRecovery)
            default:
                state = .needsAttention(.unexpected)
            }
            return DailyExportFailureResolution(
                presentationState: state,
                statusOverride: failure.userFacingLabel,
                invalidatesPreview: false
            )
        }
        if let failure = error as? HealthDataError, failure == .unavailable {
            return resolution(for: .healthDataUnavailable)
        }
        if let failure = error as? DailyHealthExportError {
            switch failure {
            case .nutritionSourceRequired:
                return DailyExportFailureResolution(
                    presentationState: .needsNutritionSource,
                    statusOverride: "Choose a visible nutrition source before refreshing the preview.",
                    invalidatesPreview: false
                )
            case .nutritionSourceUnavailable:
                return resolution(for: .nutritionSourceUnavailable)
            case .notesChanged:
                return resolution(for: .notesChanged)
            case .notesUnavailable:
                return resolution(for: .notesUnavailable)
            case .invalidTimeZone, .invalidWindow, .invalidMetricValue:
                return unexpectedResolution
            }
        }
        let cocoaError = error as NSError
        if cocoaError.domain == AppAuthDriveSession.errorDomain,
           cocoaError.code == AppAuthDriveSession.userCancelledAuthorizationFlowCode {
            return DailyExportFailureResolution(
                presentationState: nil,
                statusOverride: "Consent or selection was cancelled. Existing state was preserved.",
                invalidatesPreview: false
            )
        }
        if let failure = error as? DailyDriveSessionController.Failure,
           case .missingConfiguration = failure {
            return DailyExportFailureResolution(
                presentationState: .needsAttention(.configurationUnavailable),
                statusOverride: nil,
                invalidatesPreview: false
            )
        }
        return unexpectedResolution
    }

    private static func resolution(
        for failure: DailyExportPreparationFailure
    ) -> DailyExportFailureResolution {
        let state: DailyExportPresentationState
        switch failure {
        case .freshGoogleConsentRequired:
            state = .needsGoogleConnection
        case .googleUnavailable:
            state = .needsAttention(.googleUnavailable)
        case .destinationRequired:
            state = .needsAttention(.destinationRequired)
        case .destinationMissingOrInaccessible:
            state = .needsAttention(.destinationMissingOrInaccessible)
        case .destinationTrashed:
            state = .needsAttention(.destinationTrashed)
        case .destinationSetupFailed:
            state = .needsAttention(.destinationSetupFailed)
        case .nutritionSourceUnavailable:
            state = .needsAttention(.nutritionSourceUnavailable)
        case .healthDataUnavailable:
            state = .needsAttention(.healthDataUnavailable)
        case .notesUnavailable:
            state = .needsAttention(.notesUnavailable)
        case .notesChanged:
            state = .needsAttention(.notesChanged)
        }
        return DailyExportFailureResolution(
            presentationState: state,
            statusOverride: nil,
            invalidatesPreview: failure.invalidatesPreview
        )
    }

    private static func status(for attention: DailyExportAttention) -> String {
        switch attention {
        case .configurationUnavailable:
            "Drive export is disabled until this app has its own local OAuth client configuration."
        case .googleUnavailable:
            "The stored Google account could not be revalidated. No export ran."
        case .destinationRequired:
            "Choose an existing Drive folder or explicitly create a new export folder. No folder was created automatically."
        case .destinationMissingOrInaccessible:
            "The stored destination is missing or inaccessible. It was not replaced."
        case .destinationTrashed:
            "The stored destination is trashed. It was not replaced."
        case .destinationSetupFailed:
            "The destination could not be prepared. No duplicate folder or export was created."
        case .nutritionSourceUnavailable:
            "The selected nutrition source is unavailable. Refresh sources and choose again; no unfiltered nutrition was used."
        case .healthDataUnavailable:
            "Health data is unavailable on this device. No JSON or Drive request was created."
        case .notesUnavailable:
            "Saved notes are unavailable. No preview or Drive request was created."
        case .notesChanged:
            "Saved notes changed during refresh. Refresh and review a new preview."
        case .canonicalRecovery:
            "Canonical file identity needs contextual recovery before export."
        case .unexpected:
            "Operation failed. No background retry was queued."
        }
    }

    private static var unexpectedResolution: DailyExportFailureResolution {
        DailyExportFailureResolution(
            presentationState: .needsAttention(.unexpected),
            statusOverride: nil,
            invalidatesPreview: false
        )
    }
}

private extension DailyExportPreparationFailure {
    var invalidatesPreview: Bool {
        switch self {
        case .nutritionSourceUnavailable, .notesUnavailable, .notesChanged:
            true
        case .freshGoogleConsentRequired, .googleUnavailable, .destinationRequired,
             .destinationMissingOrInaccessible, .destinationTrashed, .destinationSetupFailed,
             .healthDataUnavailable:
            false
        }
    }
}
