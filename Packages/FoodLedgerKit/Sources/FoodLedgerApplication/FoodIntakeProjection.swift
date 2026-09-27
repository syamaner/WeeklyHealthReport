import Foundation
import FoodLedgerDomain

public enum FoodIntakeProjectionError: Error { case competingVersions, unsupportedMixture, missingReference }

public struct FoodIntakeLogRow: Sendable {
    public let logItemID: LogItemID
    public let logItemVersionID: LogItemVersionID
    public let occurredAt: Date
    public let name: String
    public let quantity: PositiveQuantity
    public let sourceIDs: [String]
    public let totals: [FoodIntakeTotal]
}

public struct FoodIntakeProjection: Sendable {
    public let summary: FoodIntakeSummary
    public let rows: [FoodIntakeLogRow]
    public let removedRows: [FoodIntakeLogRow]

    public init(records: LedgerMutation, reportingDate: String) throws {
        let superseded = Set(records.logItemVersions.compactMap(\.supersedesLogItemVersionID))
        let heads = records.logItemVersions.filter { !superseded.contains($0.logItemVersionID) }
        let grouped = Dictionary(grouping: heads, by: \.logItemID)
        guard grouped.values.allSatisfy({ !$0.contains(where: { $0.reportingDate.value == reportingDate }) || $0.count == 1 }) else { throw FoodIntakeProjectionError.competingVersions }
        let current = heads.filter { $0.reportingDate.value == reportingDate }
            .sorted { $0.occurredAt == $1.occurredAt ? $0.logItemID.rawValue < $1.logItemID.rawValue : $0.occurredAt < $1.occurredAt }
        var contributions: [FoodIntakeContribution] = []
        var rows: [FoodIntakeLogRow] = []
        var removedRows: [FoodIntakeLogRow] = []
        for head in current {
            let log: LogItemVersion
            let removed: Bool
            if case let .removed(reference) = head.composition {
                guard let original = records.logItemVersions.first(where: { $0.logItemVersionID == reference }) else {
                    throw FoodIntakeProjectionError.missingReference
                }
                try head.validateRemovalTransition(predecessor: original)
                log = original; removed = true
            } else { log = head; removed = false }
            guard case let .product(productID) = log.composition else { throw FoodIntakeProjectionError.unsupportedMixture }
            guard let product = records.productVersions.first(where: { $0.productVersionID == productID }) else {
                throw FoodIntakeProjectionError.missingReference
            }
            let version = records.resolutionVersions.first { $0.resolutionVersionID == log.effectiveResolutionVersionID }
            let resolution = version.flatMap { version in records.resolutions.first { $0.resolutionID == version.resolutionID } }
            let contribution = FoodIntakeContribution(quantity: log.edibleQuantity, basis: resolution?.basis ?? .unknown, nutrients: version?.nutrients)
            if !removed { contributions.append(contribution) }
            let sources = Set((version?.nutrients.entries ?? []).flatMap { $0.value.provenance }.map { $0.sourceID.value })
            let row = FoodIntakeLogRow(logItemID: log.logItemID, logItemVersionID: head.logItemVersionID, occurredAt: log.occurredAt,
                                         name: product.name.value, quantity: log.edibleQuantity, sourceIDs: sources.sorted(),
                                         totals: FoodIntakeSummary(contributions: [contribution]).totals)
            if removed { removedRows.append(row) } else { rows.append(row) }
        }
        summary = FoodIntakeSummary(contributions: contributions)
        self.rows = rows
        self.removedRows = removedRows
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
