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
        /// How each side's amount was obtained (count-portion-estimate-v1, C7), derived from the
        /// records, so history can say "about" and name a new method or size.
        public let methodFrom: FoodQuantityMethod
        public let methodTo: FoodQuantityMethod
        /// The entered counts are servings, not pieces (`FoodAmountServings`).
        public let isServings: Bool

        public init(from: PositiveQuantity, to: PositiveQuantity, edibleFrom: PositiveQuantity?, edibleTo: PositiveQuantity?,
                    methodFrom: FoodQuantityMethod = .direct, methodTo: FoodQuantityMethod = .direct, isServings: Bool = false) {
            self.from = from; self.to = to; self.edibleFrom = edibleFrom; self.edibleTo = edibleTo
            self.methodFrom = methodFrom; self.methodTo = methodTo; self.isServings = isServings
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
        /// Only the weight declaration or the plate changed; amount and time are the same.
        case weightDetailsChanged
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
    public static func events(versions: [LogItemVersion], conversions: [QuantityConversionVersion],
                              isServings: Bool = false) -> [FoodEntryHistoryEvent] {
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
            events.append(.init(kind: kind(from: previous, to: version, conversions: conversionByID, isServings: isServings),
                                at: version.createdAt, logItemVersionID: version.logItemVersionID))
        }
        return events.reversed()
    }

    static func kind(from previous: LogItemVersion, to next: LogItemVersion,
                     conversions: [QuantityConversionVersionID: QuantityConversionVersion],
                     isServings: Bool = false) -> FoodEntryHistoryEvent.Kind {
        switch (previous.composition, next.composition) {
        case (_, .removed): return .removed
        case (.removed, _): return .restored
        default: break
        }
        let amount = amountChange(previous, next, conversions, isServings: isServings)
        let time = previous.occurredAt == next.occurredAt ? nil : FoodEntryHistoryEvent.TimeChange(from: previous.occurredAt, to: next.occurredAt)
        if previous.composition != next.composition { return .corrected(amount: amount, time: time) }
        if previous.effectiveResolutionVersionID != next.effectiveResolutionVersionID, amount == nil, time == nil {
            return .nutritionUpdated
        }
        if amount == nil, time == nil,
           previous.weightDeclaration != next.weightDeclaration || previous.plateWeightVersionID != next.plateWeightVersionID {
            return .weightDetailsChanged
        }
        return .changed(amount: amount, time: time)
    }

    private static func amountChange(_ previous: LogItemVersion, _ next: LogItemVersion,
                                     _ conversions: [QuantityConversionVersionID: QuantityConversionVersion],
                                     isServings: Bool) -> FoodEntryHistoryEvent.AmountChange? {
        let from = entered(previous, conversions), to = entered(next, conversions)
        let methodFrom = method(previous, conversions), methodTo = method(next, conversions)
        // A method change through a new conversion (another size or method) is an amount change;
        // a declaration-only change stays `weightDetailsChanged`.
        let conversionMethodChanged = methodFrom != methodTo
            && previous.quantityConversionVersionID != next.quantityConversionVersionID
        guard from != to || previous.edibleQuantity != next.edibleQuantity || conversionMethodChanged else { return nil }
        let showsEdible = from != previous.edibleQuantity || to != next.edibleQuantity
        return .init(from: from, to: to,
                     edibleFrom: showsEdible ? previous.edibleQuantity : nil,
                     edibleTo: showsEdible ? next.edibleQuantity : nil,
                     methodFrom: methodFrom, methodTo: methodTo, isServings: isServings)
    }

    private static func method(_ version: LogItemVersion,
                               _ conversions: [QuantityConversionVersionID: QuantityConversionVersion]) -> FoodQuantityMethod {
        FoodQuantityMethod.of(version, conversion: version.quantityConversionVersionID.flatMap { conversions[$0] })
    }

    private static func entered(_ version: LogItemVersion,
                                _ conversions: [QuantityConversionVersionID: QuantityConversionVersion]) -> PositiveQuantity {
        let conversion = version.quantityConversionVersionID.flatMap { conversions[$0] }
        let last = FoodConfirmationService.lastEnteredAmount(version, conversion: conversion)
        return (try? PositiveQuantity(value: last.value, unit: last.unit)) ?? version.edibleQuantity
    }
}
