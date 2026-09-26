import DriveExportKit
import Foundation

struct DailyHealthExportIdentityPolicy: DrivePayloadIdentityPolicy {
    // Versioned refinement: cutoff remains primary; only full historical schema-3
    // snapshots use encoding time to order corrections at an unchanged cutoff.
    static let historicalOrderingVersion = "historical-v2"
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
        let orderingToken: String
        if envelope.schemaVersion == 3, try isHistorical(envelope) {
            orderingToken = "\(Self.historicalOrderingVersion)|\(envelope.dataAsOf)|\(envelope.exportedAt)"
        } else {
            orderingToken = envelope.dataAsOf
        }
        return DrivePayloadIdentity(
            orderingToken: orderingToken,
            payloadSHA256: DailyDriveExportCoordinator.sha256(payload)
        )
    }

    func compare(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        let lhsDates = try orderingDates(lhs)
        let rhsDates = try orderingDates(rhs)
        let cutoffOrder = lhsDates.cutoff.compare(rhsDates.cutoff)
        guard cutoffOrder == .orderedSame else { return cutoffOrder }
        return lhsDates.encoded.compare(rhsDates.encoded)
    }

    static func displayOrderingToken(_ token: String) -> String {
        let parts = token.components(separatedBy: "|")
        guard parts.count == 3, parts[0] == historicalOrderingVersion else { return token }
        return "\(parts[1]) (snapshot encoded \(parts[2]))"
    }

    private func orderingDates(_ token: String) throws -> (cutoff: Date, encoded: Date) {
        let parts = token.components(separatedBy: "|")
        if parts.count == 1 {
            let cutoff = try timestamp(token)
            return (cutoff, cutoff)
        }
        guard parts.count == 3, parts[0] == Self.historicalOrderingVersion else {
            throw DailyDriveExportFailure.invalidPayload
        }
        let cutoff = try timestamp(parts[1])
        let encoded = try timestamp(parts[2])
        guard encoded >= cutoff else { throw DailyDriveExportFailure.invalidPayload }
        return (cutoff, encoded)
    }

    private func isHistorical(_ envelope: DailyHealthExportEnvelope) throws -> Bool {
        guard let zone = TimeZone(identifier: envelope.timeZone) else {
            throw DailyDriveExportFailure.invalidPayload
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let cutoff = try timestamp(envelope.dataAsOf)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.string(from: cutoff) != envelope.reportDate else { return false }
        let start = try timestamp(envelope.dayWindow.start)
        guard formatter.string(from: start) == envelope.reportDate,
              calendar.startOfDay(for: start) == start,
              calendar.date(byAdding: .day, value: 1, to: start) == cutoff,
              try timestamp(envelope.dayWindow.end) == cutoff else {
            throw DailyDriveExportFailure.invalidPayload
        }
        return true
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
