import Foundation
import FoodLedgerDomain

/// Structural history of one log item (#197). Each step from a version to its successor is
/// classified by the records alone; `correctionReason` text is never parsed.
public struct FoodEntryHistoryEvent: Equatable, Sendable {
    public struct AmountChange: Equatable, Sendable {
        /// The amount as the user entered it (original input, conversion source or edible quantity).
        public let from: PositiveQuantity
        public let to: PositiveQuantity
        /// Edible amounts, present only when either side's edible amount differs from what was entered.
        public let edibleFrom: PositiveQuantity?
        public let edibleTo: PositiveQuantity?

        public init(from: PositiveQuantity, to: PositiveQuantity, edibleFrom: PositiveQuantity?, edibleTo: PositiveQuantity?) {
            self.from = from; self.to = to; self.edibleFrom = edibleFrom; self.edibleTo = edibleTo
        }
    }

    public struct TimeChange: Equatable, Sendable {
        public let from: Date
        public let to: Date

        public init(from: Date, to: Date) { self.from = from; self.to = to }
    }

    public enum Kind: Equatable, Sendable {
        case logged
        case removed
        case restored
        /// The product version changed: food details were corrected, possibly with other changes.
        case corrected(amount: AmountChange?, time: TimeChange?)
        /// Only the effective nutrition resolution changed (re-resolution).
        case nutritionUpdated
        case changed(amount: AmountChange?, time: TimeChange?)
    }

    public let kind: Kind
    public let at: Date
    public let logItemVersionID: LogItemVersionID

    public init(kind: Kind, at: Date, logItemVersionID: LogItemVersionID) {
        self.kind = kind; self.at = at; self.logItemVersionID = logItemVersionID
    }
}

public enum FoodEntryHistory {
    /// Events newest first. `conversions` are the quantity conversion versions the log versions
    /// reference; a missing one falls back to the edible quantity.
    public static func events(versions: [LogItemVersion], conversions: [QuantityConversionVersion]) -> [FoodEntryHistoryEvent] {
        let byID = Dictionary(versions.map { ($0.logItemVersionID, $0) }, uniquingKeysWith: { first, _ in first })
        let conversionByID = Dictionary(conversions.map { ($0.quantityConversionVersionID, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = versions.sorted {
            $0.ordinal.value == $1.ordinal.value ? $0.createdAt < $1.createdAt : $0.ordinal.value < $1.ordinal.value
        }
        var events: [FoodEntryHistoryEvent] = []
        for version in ordered {
            guard let previousID = version.supersedesLogItemVersionID, let previous = byID[previousID] else {
                events.append(.init(kind: .logged, at: version.createdAt, logItemVersionID: version.logItemVersionID))
                continue
            }
            events.append(.init(kind: kind(from: previous, to: version, conversions: conversionByID),
                                at: version.createdAt, logItemVersionID: version.logItemVersionID))
        }
        return events.reversed()
    }

    static func kind(from previous: LogItemVersion, to next: LogItemVersion,
                     conversions: [QuantityConversionVersionID: QuantityConversionVersion]) -> FoodEntryHistoryEvent.Kind {
        switch (previous.composition, next.composition) {
        case (_, .removed): return .removed
        case (.removed, _): return .restored
        default: break
        }
        let amount = amountChange(previous, next, conversions)
        let time = previous.occurredAt == next.occurredAt ? nil : FoodEntryHistoryEvent.TimeChange(from: previous.occurredAt, to: next.occurredAt)
        if previous.composition != next.composition { return .corrected(amount: amount, time: time) }
        if previous.effectiveResolutionVersionID != next.effectiveResolutionVersionID, amount == nil, time == nil {
            return .nutritionUpdated
        }
        return .changed(amount: amount, time: time)
    }

    private static func amountChange(_ previous: LogItemVersion, _ next: LogItemVersion,
                                     _ conversions: [QuantityConversionVersionID: QuantityConversionVersion]) -> FoodEntryHistoryEvent.AmountChange? {
        let from = entered(previous, conversions), to = entered(next, conversions)
        guard from != to || previous.edibleQuantity != next.edibleQuantity else { return nil }
        let showsEdible = from != previous.edibleQuantity || to != next.edibleQuantity
        return .init(from: from, to: to,
                     edibleFrom: showsEdible ? previous.edibleQuantity : nil,
                     edibleTo: showsEdible ? next.edibleQuantity : nil)
    }

    private static func entered(_ version: LogItemVersion,
                                _ conversions: [QuantityConversionVersionID: QuantityConversionVersion]) -> PositiveQuantity {
        let conversion = version.quantityConversionVersionID.flatMap { conversions[$0] }
        let last = FoodConfirmationService.lastEnteredAmount(version, conversion: conversion)
        return (try? PositiveQuantity(value: last.value, unit: last.unit)) ?? version.edibleQuantity
    }
}
