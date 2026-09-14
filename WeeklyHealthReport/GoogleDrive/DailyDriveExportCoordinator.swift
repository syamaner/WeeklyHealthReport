import DriveExportKit
import Foundation

struct DailyHealthExportIdentityPolicy: DrivePayloadIdentityPolicy {
    let ownerPropertyKey = "whrDailyCanonical"
    let orderingPropertyKey = "whrDataAsOf"

    func validate(payload: Data, reportDate: String) throws -> DrivePayloadIdentity {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(DailyHealthExportEnvelope.self, from: payload),
              (1...3).contains(envelope.schemaVersion),
              envelope.reportDate == reportDate,
              try DailyHealthExportSerializer.encode(envelope) == payload,
              let dataAsOf = try? timestamp(envelope.dataAsOf),
              let exportedAt = try? timestamp(envelope.exportedAt),
              exportedAt >= dataAsOf else {
            throw DailyDriveExportFailure.invalidPayload
        }
        if envelope.schemaVersion == 1 {
            guard envelope.today.nutrition == nil,
                  envelope.appContext.nutrition == nil,
                  envelope.today.notes == nil else {
                throw DailyDriveExportFailure.invalidPayload
            }
        } else {
            let expectedKeys = NutritionCatalogue.all.map(\.key)
            guard envelope.today.nutrition?.nutrients.map(\.key) == expectedKeys,
                  envelope.appContext.nutrition?.nutrients.map(\.key) == expectedKeys else {
                throw DailyDriveExportFailure.invalidPayload
            }
            if envelope.schemaVersion == 2 {
                guard envelope.today.notes == nil else {
                    throw DailyDriveExportFailure.invalidPayload
                }
            } else {
                guard let notes = envelope.today.notes,
                      notes.count <= DailyNotesPolicy.maximumNotesPerDay,
                      notes.allSatisfy({
                          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && $0.count <= DailyNotesPolicy.maximumCharactersPerNote
                      }),
                      notes.reduce(0, { $0 + $1.count })
                          <= DailyNotesPolicy.maximumCharactersPerDay else {
                    throw DailyDriveExportFailure.invalidPayload
                }
            }
        }
        return DrivePayloadIdentity(
            orderingToken: envelope.dataAsOf,
            payloadSHA256: DailyDriveExportCoordinator.sha256(payload)
        )
    }

    func compare(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        let lhsDate = try timestamp(lhs)
        let rhsDate = try timestamp(rhs)
        return lhsDate.compare(rhsDate)
    }

    func filename(for reportDate: String) -> String {
        "health-daily-\(reportDate).json"
    }

    private func timestamp(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw DailyDriveExportFailure.invalidPayload
        }
        return date
    }
}

extension DailyDriveMetadataKeys {
    static let owner = "whrDailyCanonical"
    static let dataAsOf = "whrDataAsOf"
}

extension KeychainDailyDriveExportIdentityStore {
    init(keychain: any DailyDriveSecurePersisting = DailyDriveKeychainStore()) {
        self.init(
            keychain: keychain,
            registryKey: "google.drive.daily-export-identities.v1",
            markerKey: "google.drive.daily-export-installation.v1"
        )
    }
}

extension DailyDriveExportCoordinator {
    init(
        transport: any DailyDriveTransporting,
        store: any DailyDriveExportIdentityPersisting
    ) {
        self.init(
            transport: transport,
            store: store,
            policy: DailyHealthExportIdentityPolicy()
        )
    }

    static func filename(for reportDate: String) -> String {
        DailyHealthExportIdentityPolicy().filename(for: reportDate)
    }
}
