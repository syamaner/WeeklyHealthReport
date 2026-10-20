import Foundation
import FoodLedgerDomain

/// One recently logged food, keyed by its source record. Pure projection data.
public struct FoodRecentItem: Equatable, Sendable {
    public let logItemID: LogItemID
    public let sourceReleaseID: ExternalIdentifier
    public let recordID: ExternalIdentifier
    public let occurredAt: Date
    /// The amount as last entered (value and unit only).
    public let lastAmount: PositiveQuantity
    /// Energy of that entry, when known.
    public let energyKcal: Double?
    /// The last amount is a pasted label's servings (#93), not pieces.
    public let lastAmountIsServings: Bool
    /// Energy stated only as an upper bound, when `energyKcal` is nil: the Food Log row's rule.
    public let energyUpperBound: FoodEnergyUpperBound?

    public init(logItemID: LogItemID, sourceReleaseID: ExternalIdentifier, recordID: ExternalIdentifier,
                occurredAt: Date, lastAmount: PositiveQuantity, energyKcal: Double?, lastAmountIsServings: Bool = false,
                energyUpperBound: FoodEnergyUpperBound? = nil) {
        self.logItemID = logItemID; self.sourceReleaseID = sourceReleaseID; self.recordID = recordID
        self.occurredAt = occurredAt; self.lastAmount = lastAmount; self.energyKcal = energyKcal
        self.lastAmountIsServings = lastAmountIsServings; self.energyUpperBound = energyUpperBound
    }
}

/// Recent foods from the ledger: current heads only (removed and superseded entries excluded),
/// de-duplicated by source release and record with the most recent `occurredAt` kept, ordered by
/// `occurredAt` (ties by log item ID), limited to a window and a count. No I/O, no clock.
public enum FoodRecentItemsProjection {
    public static let defaultLimit = 10
    public static let defaultWindowDays = 30

    public static func items(records: LedgerMutation, now: Date, calendar: Calendar,
                             limit: Int = defaultLimit, windowDays: Int = defaultWindowDays) -> [FoodRecentItem] {
        guard limit > 0, let start = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now)) else { return [] }
        let superseded = Set(records.logItemVersions.compactMap(\.supersedesLogItemVersionID))
        let heads = records.logItemVersions.filter { !superseded.contains($0.logItemVersionID) }
        var byLogItem: [LogItemID: LogItemVersion] = [:]
        for head in heads {
            // Competing heads for one log item are ambiguous: skip the item rather than guess.
            if byLogItem[head.logItemID] != nil { byLogItem[head.logItemID] = nil; continue }
            byLogItem[head.logItemID] = head
        }
        var latest: [String: FoodRecentItem] = [:]
        for head in byLogItem.values {
            guard case .product = head.composition, head.occurredAt >= start, head.occurredAt <= now,
                  let resolution = records.resolutionVersions.first(where: { $0.resolutionVersionID == head.effectiveResolutionVersionID }),
                  let decision = records.candidateDecisions.first(where: { resolution.decisionIDs.contains($0.candidateDecisionID) && $0.outcome == .selected })
                    ?? records.candidateDecisions.first(where: { resolution.decisionIDs.contains($0.candidateDecisionID) }) else { continue }
            let conversion = head.quantityConversionVersionID.flatMap { id in
                records.quantityConversions.first { $0.quantityConversionVersionID == id }
            }
            let last = FoodConfirmationService.lastEnteredAmount(head, conversion: conversion)
            guard let amount = try? PositiveQuantity(value: last.value, unit: last.unit) else { continue }
            let basis = records.resolutions.first { $0.resolutionID == resolution.resolutionID }?.basis ?? .unknown
            let contribution = FoodIntakeContribution(quantity: head.edibleQuantity, basis: basis, nutrients: resolution.nutrients)
            let total = FoodIntakeSummary(contributions: [contribution]).totals.first { $0.key == .energyConsumed }
            let energy = total?.incompleteContributions == 0 ? total?.knownAmount : nil
            let sourceID = records.sourceReleases.first { $0.sourceReleaseID == decision.candidate.sourceReleaseID }?.sourceID.value
            let item = FoodRecentItem(logItemID: head.logItemID, sourceReleaseID: decision.candidate.sourceReleaseID,
                recordID: decision.candidate.recordID, occurredAt: head.occurredAt, lastAmount: amount,
                energyKcal: energy,
                lastAmountIsServings: PastedLabelServingPolicy.isServingsAmount(enteredUnit: amount.unit, conversion: conversion,
                                                                                sourceID: sourceID),
                energyUpperBound: energy == nil ? FoodEnergyUpperBound.of(contribution) : nil)
            let key = decision.candidate.sourceReleaseID.value + "\u{1F}" + decision.candidate.recordID.value
            if let existing = latest[key], !Self.isMoreRecent(item, than: existing) { continue }
            latest[key] = item
        }
        return Array(latest.values.sorted { isMoreRecent($0, than: $1) }.prefix(limit))
    }

    static func isMoreRecent(_ lhs: FoodRecentItem, than rhs: FoodRecentItem) -> Bool {
        lhs.occurredAt == rhs.occurredAt ? lhs.logItemID.rawValue > rhs.logItemID.rawValue : lhs.occurredAt > rhs.occurredAt
    }
}

/// A recent food that passed source verification and can be logged again.
public struct FoodRecentRelogItem: Equatable, Sendable {
    public let item: FoodRecentItem
    /// Display name of the restored source candidate.
    public let name: String
    public let isEstimate: Bool
    /// The verified current version of the entry: what "Save as favourite" pins (Q2). Nil only
    /// for callers that never offer saving.
    public let logItemVersionID: LogItemVersionID?
    /// The app's plain water reference: it has its own quick-add item, so it is not offered as a
    /// favourite here (as on Confirm).
    public let isPlainWater: Bool

    public init(item: FoodRecentItem, name: String, isEstimate: Bool,
                logItemVersionID: LogItemVersionID? = nil, isPlainWater: Bool = false) {
        self.item = item; self.name = name; self.isEstimate = isEstimate
        self.logItemVersionID = logItemVersionID; self.isPlainWater = isPlainWater
    }
}

/// Filters projected recent foods through the verifying re-log builder (injected digester inside
/// `FoodConfirmationService`). Entries whose source cannot be restored are omitted, never shown
/// with partial data.
public struct FoodRecentItemsService: Sendable {
    private let reader: any FoodConfirmationReading
    private let confirmations: FoodConfirmationService

    public init(reader: any FoodConfirmationReading, confirmations: FoodConfirmationService) {
        self.reader = reader; self.confirmations = confirmations
    }

    public func items(records: LedgerMutation, now: Date, calendar: Calendar,
                      limit: Int = FoodRecentItemsProjection.defaultLimit) -> [FoodRecentRelogItem] {
        // Project generously, then keep only verifiable items up to the limit.
        FoodRecentItemsProjection.items(records: records, now: now, calendar: calendar, limit: Int.max).lazy.compactMap { item in
            guard let saved = try? reader.foodConfirmation(logItemID: item.logItemID),
                  let input = try? confirmations.relogInput(saved),
                  let isEstimate = try? confirmations.isEstimate(saved) else { return nil }
            // Only a current product version can be pinned; a removal head never reaches here.
            guard case .product = saved.logItemVersion.composition else { return nil }
            // The Food Log row's rule (FoodLogDayContent): an estimated entry, or totals that
            // include estimates (an augmented or calculated value, or an estimated weight).
            let log = saved.logItemVersion
            let totals = FoodIntakeSummary(contributions: [.init(quantity: log.edibleQuantity, basis: saved.resolution.basis,
                nutrients: saved.resolutionVersion.nutrients, quantityIsEstimate: log.weightDeclaration?.basis == .estimated)]).totals
            return FoodRecentRelogItem(item: item, name: input.candidates[0].name.value,
                                       isEstimate: isEstimate || totals.contains { $0.includesEstimates }
                                           || item.energyUpperBound?.isCalculated == true,
                                       logItemVersionID: saved.logItemVersion.logItemVersionID,
                                       isPlainWater: PlainWaterReference.isPlainWater(saved.resolutionVersion))
        }.prefix(limit).map { $0 }
    }
}
