import Foundation
import FoodLedgerDomain

public enum FoodIntakeProjectionError: Error { case competingVersions, unsupportedMixture, missingReference }

public struct FoodIntakeLogRow: Sendable {
    public let logItemID: LogItemID
    public let occurredAt: Date
    public let name: String
    public let quantity: PositiveQuantity
    public let sourceIDs: [String]
    public let totals: [FoodIntakeTotal]
}

public struct FoodIntakeProjection: Sendable {
    public let summary: FoodIntakeSummary
    public let rows: [FoodIntakeLogRow]

    public init(records: LedgerMutation, reportingDate: String) throws {
        let superseded = Set(records.logItemVersions.compactMap(\.supersedesLogItemVersionID))
        let heads = records.logItemVersions.filter { !superseded.contains($0.logItemVersionID) }
        let grouped = Dictionary(grouping: heads, by: \.logItemID)
        guard grouped.values.allSatisfy({ !$0.contains(where: { $0.reportingDate.value == reportingDate }) || $0.count == 1 }) else { throw FoodIntakeProjectionError.competingVersions }
        let current = heads.filter { $0.reportingDate.value == reportingDate }
            .sorted { $0.occurredAt == $1.occurredAt ? $0.logItemID.rawValue < $1.logItemID.rawValue : $0.occurredAt < $1.occurredAt }
        var contributions: [FoodIntakeContribution] = []
        var rows: [FoodIntakeLogRow] = []
        for log in current {
            guard case let .product(productID) = log.composition else { throw FoodIntakeProjectionError.unsupportedMixture }
            guard let product = records.productVersions.first(where: { $0.productVersionID == productID }) else {
                throw FoodIntakeProjectionError.missingReference
            }
            let version = records.resolutionVersions.first { $0.resolutionVersionID == log.effectiveResolutionVersionID }
            let resolution = version.flatMap { version in records.resolutions.first { $0.resolutionID == version.resolutionID } }
            let contribution = FoodIntakeContribution(quantity: log.edibleQuantity, basis: resolution?.basis ?? .unknown, nutrients: version?.nutrients)
            contributions.append(contribution)
            let sources = Set((version?.nutrients.entries ?? []).flatMap { $0.value.provenance }.map { $0.sourceID.value })
            rows.append(FoodIntakeLogRow(logItemID: log.logItemID, occurredAt: log.occurredAt,
                                         name: product.name.value, quantity: log.edibleQuantity, sourceIDs: sources.sorted(),
                                         totals: FoodIntakeSummary(contributions: [contribution]).totals))
        }
        summary = FoodIntakeSummary(contributions: contributions)
        self.rows = rows
    }
}

/// Completed local days preceding an injected instant. An unreadable day has no
/// summary; an empty day has a summary with zero entries and unknown nutrients.
public struct FoodIntakeDayPreview: Sendable {
    public let date: Date
    public let summary: FoodIntakeSummary?

    public static func pastWeek(records: LedgerMutation, now: Date, calendar: Calendar) -> [Self] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = calendar.startOfDay(for: now)
        return (1...7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let projection = try? FoodIntakeProjection(records: records, reportingDate: formatter.string(from: day))
            return Self(date: day, summary: projection?.summary)
        }
    }
}
