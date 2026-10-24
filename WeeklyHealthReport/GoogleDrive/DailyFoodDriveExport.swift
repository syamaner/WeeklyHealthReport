import DriveExportKit
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// The two daily files Export sends (`docs/food-daily-export-contract-v1.md`, #287). Each has its
/// own identity policy, registry and installation marker, so neither can collide by date.
enum DailyExportDocumentType: Hashable, CaseIterable {
    case health
    case food
}

/// Drive identity for `food-daily-YYYY-MM-DD.json`. The ordering token always carries
/// `exported_at`, because a past day's `data_as_of` is fixed at the next local midnight and a
/// corrected re-export must still replace the earlier file.
struct DailyFoodExportIdentityPolicy: DrivePayloadIdentityPolicy {
    static let orderingVersion = "food-v1"
    static let summaryVersion = "food-intake-summary-v5"
    let ownerPropertyKey = "whrDailyFood"
    let orderingPropertyKey = "whrDataAsOf"

    func validate(payload: Data, reportDate: String) throws -> DrivePayloadIdentity {
        guard let document = try? FoodDailyExportSerializer.decode(payload),
              document.foodDailySchemaVersion == FoodDailyExportDocument.schemaVersion,
              document.reportDate == reportDate,
              document.nutrientCatalogueVersion == NutrientSet.catalogueVersion,
              document.summaryVersion == Self.summaryVersion,
              document.summary.map(\.key) == NutrientKey.allCases.map(\.rawValue),
              document.entries.allSatisfy({ $0.nutrients.map(\.key) == NutrientKey.allCases.map(\.rawValue) }),
              TimeZone(identifier: document.timeZone) != nil,
              (try? FoodDailyExportSerializer.encode(document)) == payload else {
            throw DailyDriveExportFailure.invalidPayload
        }
        let token = "\(Self.orderingVersion)|\(document.dataAsOf)|\(document.exportedAt)"
        _ = try orderingDates(token)
        return DrivePayloadIdentity(
            orderingToken: token,
            payloadSHA256: DailyDriveExportCoordinator.sha256(payload)
        )
    }

    func compare(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        let lhsDates = try orderingDates(lhs)
        let rhsDates = try orderingDates(rhs)
        let cutoffOrder = lhsDates.cutoff.compare(rhsDates.cutoff)
        guard cutoffOrder == .orderedSame else { return cutoffOrder }
        return lhsDates.exported.compare(rhsDates.exported)
    }

    func filename(for reportDate: String) -> String {
        "food-daily-\(reportDate).json"
    }

    static func displayOrderingToken(_ token: String) -> String {
        let parts = token.components(separatedBy: "|")
        guard parts.count == 3, parts[0] == orderingVersion else { return token }
        return "\(parts[1]) (prepared \(parts[2]))"
    }

    /// The food token's own parser: millisecond ISO 8601 text, never the health parser.
    private func orderingDates(_ token: String) throws -> (cutoff: Date, exported: Date) {
        let parts = token.components(separatedBy: "|")
        guard parts.count == 3, parts[0] == Self.orderingVersion,
              let cutoff = FoodDailyExportTimestamp.date(parts[1]),
              let exported = FoodDailyExportTimestamp.date(parts[2]),
              exported >= cutoff else {
            throw DailyDriveExportFailure.invalidPayload
        }
        return (cutoff, exported)
    }
}

extension KeychainDailyDriveExportIdentityStore {
    /// The food registry and its own installation marker. A shared marker would make the first
    /// food export fail after any health export (`identityRecoveryAmbiguous`).
    static func food(keychain: any DailyDriveSecurePersisting = DailyDriveKeychainStore()) -> KeychainDailyDriveExportIdentityStore {
        KeychainDailyDriveExportIdentityStore(
            keychain: keychain,
            registryKey: "google.drive.daily-food-export-identities.v1",
            markerKey: "google.drive.daily-food-export-installation.v1"
        )
    }
}

/// The food ledger as it is now, read once per refresh. Consumer-owned; the composition root
/// adapts the food ledger store to it.
@MainActor
protocol DailyFoodLedgerSnapshotReading {
    func dailyFoodExportSnapshot() throws -> LedgerMutation
}

/// Whether Food log is on. Persisted so switching it off survives a relaunch.
protocol DailyFoodLogPreferencePersisting {
    func loadFoodLogEnabled() -> Bool
    func saveFoodLogEnabled(_ enabled: Bool)
}

struct UserDefaultsDailyFoodLogPreference: DailyFoodLogPreferencePersisting {
    static let key = "daily-export.food-log-enabled.v1"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadFoodLogEnabled() -> Bool {
        defaults.object(forKey: Self.key) as? Bool ?? true
    }

    func saveFoodLogEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}

final class MemoryDailyFoodLogPreference: DailyFoodLogPreferencePersisting {
    private var enabled: Bool
    init(enabled: Bool = true) { self.enabled = enabled }
    func loadFoodLogEnabled() -> Bool { enabled }
    func saveFoodLogEnabled(_ enabled: Bool) { self.enabled = enabled }
}

/// The prepared food file: the exact bytes Export sends.
struct DailyFoodExportPreview: Equatable {
    let document: FoodDailyExportDocument
    let bytes: Data

    var reportDate: String { document.reportDate }
    var sha256: String { DailyDriveExportCoordinator.sha256(bytes) }
    var dataAsOf: String { document.dataAsOf }
    var orderingToken: String {
        "\(DailyFoodExportIdentityPolicy.orderingVersion)|\(document.dataAsOf)|\(document.exportedAt)"
    }
}

/// Why no food file was prepared. A blocked day never becomes an empty-day file.
enum DailyFoodExportBlock: Equatable {
    case competingVersions
    case unsupportedMixture
    case missingReference
    /// A value's source has no origin in the closed rule, or an entry has no attributable source.
    case unsupportedSource
    case unreadable

    var line: String {
        switch self {
        case .competingVersions:
            "An entry on this day has two current versions, so no food file was prepared. Open the Food Log to check the day."
        case .unsupportedMixture:
            "An entry on this day is a mixture, which this file does not support yet, so no food file was prepared."
        case .missingReference:
            "An entry on this day refers to a food or nutrition record that is missing, so no food file was prepared."
        case .unsupportedSource:
            "An entry on this day has a nutrient source this file cannot describe yet, so no food file was prepared."
        case .unreadable:
            "The food log could not be read, so no food file was prepared."
        }
    }
}

enum DailyFoodExportPreparation: Equatable {
    /// Nothing prepared for the current snapshot (or it was sent and verified).
    case notPrepared
    /// Food log is switched off: Export sends the health file only.
    case off
    /// This build has no readable food ledger.
    case unavailable
    case prepared(DailyFoodExportPreview)
    case blocked(DailyFoodExportBlock)

    var preview: DailyFoodExportPreview? {
        if case let .prepared(preview) = self { preview } else { nil }
    }
}

/// Builds the food file for the same refresh as the health file: the same report date, time zone,
/// `data_as_of` and `exported_at` instants, read from the reviewed health envelope.
struct DailyFoodExportService {
    private let reader: (any DailyFoodLedgerSnapshotReading)?
    private let appContext: FoodDailyExportAppContext

    init(reader: (any DailyFoodLedgerSnapshotReading)?, appContext: FoodDailyExportAppContext = .bundle()) {
        self.reader = reader
        self.appContext = appContext
    }

    static let unavailable = DailyFoodExportService(reader: nil)

    var isAvailable: Bool { reader != nil }

    @MainActor
    func prepare(matching health: DailyHealthExportEnvelope) -> DailyFoodExportPreparation {
        guard let reader else { return .unavailable }
        guard let zone = TimeZone(identifier: health.timeZone),
              let dataAsOf = Self.healthInstant(health.dataAsOf),
              let exportedAt = Self.healthInstant(health.exportedAt) else {
            return .blocked(.unreadable)
        }
        do {
            let records = try reader.dailyFoodExportSnapshot()
            let document = try FoodDailyExportBuilder.make(FoodDailyExportRequest(
                records: records, reportDate: health.reportDate, timeZone: zone, dataAsOf: dataAsOf,
                exportedAt: exportedAt, appContext: appContext))
            return .prepared(DailyFoodExportPreview(document: document, bytes: try FoodDailyExportSerializer.encode(document)))
        } catch let error as FoodIntakeProjectionError {
            switch error {
            case .competingVersions: return .blocked(.competingVersions)
            case .unsupportedMixture: return .blocked(.unsupportedMixture)
            case .missingReference: return .blocked(.missingReference)
            }
        } catch let error as FoodDailyExportError {
            switch error {
            case .missingReference: return .blocked(.missingReference)
            case .unmappedSource, .unattributedEntry: return .blocked(.unsupportedSource)
            case .exportedBeforeDataAsOf, .invalidTimeZone: return .blocked(.unreadable)
            }
        } catch {
            return .blocked(.unreadable)
        }
    }

    /// The health envelope's second-precision timestamp, so both files carry the same instant.
    private static func healthInstant(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

extension FoodDailyExportAppContext {
    static func bundle(_ bundle: Bundle = .main) -> FoodDailyExportAppContext {
        FoodDailyExportAppContext(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        )
    }
}

extension DailyDriveExportResult {
    /// The food file's result line, with the food token shown as its cutoff and preparation time.
    var foodUserFacingLabel: String {
        switch self {
        case .verified(let token, _):
            "verified in Drive for \(DailyFoodExportIdentityPolicy.displayOrderingToken(token))."
        case .unchangedVerified(let token):
            "already in Drive unchanged for \(DailyFoodExportIdentityPolicy.displayOrderingToken(token))."
        case .cancelledBeforeSubmission:
            "cancelled before sending."
        case .cancelledAfterSubmissionVerified(let token, _):
            "cancelled after sending; Drive verified \(DailyFoodExportIdentityPolicy.displayOrderingToken(token))."
        }
    }
}

extension DailyDriveRecoveryResult {
    var foodUserFacingLabel: String {
        switch self {
        case .recovered(let token):
            "recovery verified the selected file through \(DailyFoodExportIdentityPolicy.displayOrderingToken(token))."
        case .alreadyTracked(let token):
            "the selected file is already tracked through \(DailyFoodExportIdentityPolicy.displayOrderingToken(token))."
        case .migrated(let token):
            "the selected file was recovered for this folder through \(DailyFoodExportIdentityPolicy.displayOrderingToken(token))."
        }
    }
}
