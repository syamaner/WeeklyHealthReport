#if canImport(DriveExportKit)
import DriveExportKit
#endif
import Foundation

struct SyntheticFixtureIdentityPolicy: DrivePayloadIdentityPolicy {
    let ownerPropertyKey = "whrSyntheticCanonical"
    let orderingPropertyKey = "whrGeneration"

    func validate(payload: Data, reportDate: String) throws -> DrivePayloadIdentity {
        guard SyntheticPayload.allowedReportDates.contains(reportDate) else {
            throw DailyDriveExportFailure.invalidPayload
        }
        let generation = try SyntheticPayload.revision(in: payload, reportDate: reportDate)
        return DrivePayloadIdentity(
            orderingToken: String(generation),
            payloadSHA256: DailyDriveExportCoordinator.sha256(payload)
        )
    }

    func compare(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        guard let lhsValue = Int(lhs), let rhsValue = Int(rhs) else {
            throw DailyDriveExportFailure.invalidPayload
        }
        if lhsValue < rhsValue { return .orderedAscending }
        if lhsValue > rhsValue { return .orderedDescending }
        return .orderedSame
    }

    func filename(for reportDate: String) -> String {
        SyntheticPayload.filename(for: reportDate)
    }
}

enum SyntheticIdentityStoreKeys {
    static let registry = "google.drive.canonical-export-identities.v2"
    static let marker = "google.drive.canonical-export-installation.v2"
}

extension DailyDriveExportCoordinator {
    init(
        transport: any DailyDriveTransporting,
        store: any DailyDriveExportIdentityPersisting
    ) {
        self.init(
            transport: transport,
            store: store,
            policy: SyntheticFixtureIdentityPolicy()
        )
    }
}
