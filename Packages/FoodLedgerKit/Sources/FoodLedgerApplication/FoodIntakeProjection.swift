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
    /// When the entry was removed (the removing version's creation time); nil for current entries.
    /// In memory only; nothing new is persisted.
    public let removedAt: Date?
    /// Energy for the amount when the source states it only as an upper bound ("less than"):
    /// shown as a bound on the Food Log row, never as an exact amount or zero. The day total
    /// still counts it as incomplete, as before.
    public var energyUpperBound: FoodEnergyUpperBound? = nil
    /// The entry is plain water (`PlainWaterReference.isPlainWater`). Its own `totals` keep the
    /// reference's exact zeros; the day summary leaves them out (`food-intake-summary-v6`, #304).
    public var isPlainWater: Bool = false
    /// The amount as entered (the count of a count entry), for the amount line "3 pieces · about
    /// 150 g" (count-portion-estimate-v1). Defaults to the edible quantity.
    public var enteredAmount: PositiveQuantity? = nil
    /// How the amount was obtained, derived from the stored records (C7). Never stored.
    public var quantityMethod: FoodQuantityMethod = .direct
    /// Whether the entry was counted in servings (pasted label or source serving).
    public var amountIsServings: Bool = false
}

/// An energy upper bound scaled to the amount eaten, with whether the stored value is calculated.
public struct FoodEnergyUpperBound: Equatable, Sendable {
    public let kcal: Double
    public let closed: Bool
    public let isCalculated: Bool
    public init(kcal: Double, closed: Bool, isCalculated: Bool) {
        self.kcal = kcal; self.closed = closed; self.isCalculated = isCalculated
    }

    /// The bound for one contribution: a bounded energy value with an upper end and no lower end,
    /// on a basis the quantity scales against. Nil for anything else.
    public static func of(_ contribution: FoodIntakeContribution) -> FoodEnergyUpperBound? {
        guard let entry = contribution.nutrients?.entries.first(where: { $0.key == .energyConsumed }),
              case let .bounded(bounds) = entry.value, bounds.lower == nil, let upper = bounds.upper,
              // "Less than 0" admits no amount: shown as unknown, never as a bound or zero.
              upper > 0 || bounds.upperClosed,
              let scale = FoodIntakeSummary.scale(quantity: contribution.quantity, basis: contribution.basis) else { return nil }
        let kcal = upper * scale
        guard kcal.isFinite else { return nil }
        return FoodEnergyUpperBound(kcal: kcal, closed: bounds.upperClosed, isCalculated: NutrientDerivation.isCalculated(entry.value))
    }
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
            let conversion = log.quantityConversionVersionID.flatMap { id in
                records.quantityConversions.first { $0.quantityConversionVersionID == id }
            }
            // count-portion-estimate-v1 (C6): one estimate rule over the stored records
            // (`food-intake-summary-v6`).
            let contribution = FoodIntakeContribution(quantity: log.edibleQuantity, basis: resolution?.basis ?? .unknown, nutrients: version?.nutrients,
                                                      quantityIsEstimate: FoodQuantityEstimate.isEstimate(log, conversion: conversion))
            let isPlainWater = version.map(PlainWaterReference.isPlainWater) ?? false
            if !removed {
                contributions.append(FoodIntakeContribution(quantity: contribution.quantity, basis: contribution.basis,
                                                            nutrients: contribution.nutrients,
                                                            quantityIsEstimate: contribution.quantityIsEstimate,
                                                            isPlainWater: isPlainWater))
            }
            let sources = Set((version?.nutrients.entries ?? []).flatMap { $0.value.provenance }.map { $0.sourceID.value })
            let entered = FoodConfirmationService.lastEnteredAmount(log, conversion: conversion)
            let row = FoodIntakeLogRow(logItemID: log.logItemID, logItemVersionID: head.logItemVersionID, occurredAt: log.occurredAt,
                                         name: product.name.value, quantity: log.edibleQuantity, sourceIDs: sources.sorted(),
                                         totals: FoodIntakeSummary(contributions: [contribution]).totals,
                                         removedAt: removed ? head.createdAt : nil,
                                         energyUpperBound: FoodEnergyUpperBound.of(contribution),
                                         isPlainWater: isPlainWater,
                                         enteredAmount: try? PositiveQuantity(value: entered.value, unit: entered.unit),
                                         quantityMethod: FoodQuantityMethod.of(log, conversion: conversion),
                                         amountIsServings: FoodAmountServings.isServings(enteredUnit: entered.unit, conversion: conversion,
                                             sourceID: Self.sourceID(version, records: records), basis: resolution?.basis))
            if removed { removedRows.append(row) } else { rows.append(row) }
        }
        summary = FoodIntakeSummary(contributions: contributions)
        self.rows = rows
        self.removedRows = removedRows
    }

    /// The source ID of the entry's nutrition release, for the shared servings predicate.
    /// The decision candidate's release, as Recent and the saved entry read it: the selected
    /// decision of the effective resolution, else its first decision.
    static func sourceID(_ version: NutritionResolutionVersion?, records: LedgerMutation) -> String? {
        guard let version, let release = decisionCandidateReleaseID(version, records: records) else { return nil }
        return records.sourceReleases.first { $0.sourceReleaseID == release }?.sourceID.value
    }

    public static func decisionCandidateReleaseID(_ version: NutritionResolutionVersion, records: LedgerMutation) -> ExternalIdentifier? {
        let decision = records.candidateDecisions.first { version.decisionIDs.contains($0.candidateDecisionID) && $0.outcome == .selected }
            ?? records.candidateDecisions.first { version.decisionIDs.contains($0.candidateDecisionID) }
        return decision?.candidate.sourceReleaseID
    }
}

/// Completed local days preceding an injected instant. An unreadable day has no
/// summary; an empty day has a summary with zero entries and unknown nutrients.
public struct FoodIntakeDayPreview: Sendable {
    public let date: Date
    public let summary: FoodIntakeSummary?

    public static func pastWeek(records: LedgerMutation, now: Date, calendar: Calendar) -> [Self] {
        let today = calendar.startOfDay(for: now)
        return (1...7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let projection = try? FoodIntakeProjection(records: records, reportingDate: FoodReportingDay.key(for: day, calendar: calendar))
            return Self(date: day, summary: projection?.summary)
        }
    }
}
