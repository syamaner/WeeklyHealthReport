import Foundation

// Favourites are append-only food-ledger records (food quick add contract v1, #198). They are
// separate from inventory "usual foods" and from personal-library aliases: a favourite never
// feeds search and never rewrites a log entry. Strict decoding lives in ValidatedDecoding.swift.

public enum FavouriteTag: Sendable {}
public enum FavouriteVersionTag: Sendable {}
public enum FavouriteArrangementVersionTag: Sendable {}

public typealias FavouriteID = LedgerID<FavouriteTag>
public typealias FavouriteVersionID = LedgerID<FavouriteVersionTag>
public typealias FavouriteArrangementVersionID = LedgerID<FavouriteArrangementVersionTag>

/// An app-defined reference food. Closed: a new reference is a new case (and a new release).
public enum ReferenceFoodID: String, Codable, CaseIterable, Sendable {
    case plainWaterV1 = "plain-water-v1"

    /// The only unit a reference favourite may use.
    public var unit: QuantityUnit {
        switch self {
        case .plainWaterV1: .millilitres
        }
    }
}

/// What a favourite logs again. A saved entry is pinned by its immutable log item version; the
/// product, resolution and evidence are read through that version, never stored here.
public enum FavouriteBinding: Codable, Equatable, Hashable, Sendable {
    case savedEntry(LogItemVersionID)
    case reference(ReferenceFoodID)
}

/// Value and unit only, as the amount was last entered. No conversion, plate or decision.
public struct FavouriteAmount: Codable, Equatable, Hashable, Sendable {
    public let value: Double
    public let unit: QuantityUnit

    public init(value: Double, unit: QuantityUnit) throws {
        guard value.isFinite else { throw FoodLedgerValidationError.nonFinite("favourite amount") }
        guard value > 0 else { throw FoodLedgerValidationError.nonPositive("favourite amount") }
        self.value = value
        self.unit = unit
    }
}

public enum FavouriteState: String, Codable, Sendable {
    case active
    /// A tombstone: the favourite is no longer offered. It never removes any record.
    case removed
}

public struct FavouriteEntry: Codable, Equatable, Sendable {
    public let favouriteID: FavouriteID
    public let createdAt: Date

    public init(favouriteID: FavouriteID, createdAt: Date) {
        self.favouriteID = favouriteID
        self.createdAt = createdAt
    }
}

public struct FavouriteVersion: Codable, Equatable, Sendable {
    public let favouriteVersionID: FavouriteVersionID
    public let favouriteID: FavouriteID
    public let ordinal: VersionOrdinal
    public let supersedesFavouriteVersionID: FavouriteVersionID?
    public let binding: FavouriteBinding
    public let label: LedgerText
    public let defaultAmount: FavouriteAmount
    public let state: FavouriteState
    public let createdAt: Date

    public init(
        favouriteVersionID: FavouriteVersionID,
        favouriteID: FavouriteID,
        ordinal: VersionOrdinal,
        supersedesFavouriteVersionID: FavouriteVersionID? = nil,
        binding: FavouriteBinding,
        label: LedgerText,
        defaultAmount: FavouriteAmount,
        state: FavouriteState,
        createdAt: Date
    ) throws {
        guard (supersedesFavouriteVersionID == nil) == (ordinal.value == 1) else {
            throw FoodLedgerValidationError.invalidOrdinal
        }
        if case let .reference(reference) = binding, defaultAmount.unit != reference.unit {
            throw FoodLedgerValidationError.invalidUnit
        }
        self.favouriteVersionID = favouriteVersionID
        self.favouriteID = favouriteID
        self.ordinal = ordinal
        self.supersedesFavouriteVersionID = supersedesFavouriteVersionID
        self.binding = binding
        self.label = label
        self.defaultAmount = defaultAmount
        self.state = state
        self.createdAt = createdAt
    }
}

/// Quick-add order. Reordering writes one arrangement version and no favourite version.
public struct FavouriteArrangement: Codable, Equatable, Sendable {
    public let arrangementVersionID: FavouriteArrangementVersionID
    public let ordinal: VersionOrdinal
    public let supersedesArrangementVersionID: FavouriteArrangementVersionID?
    public let order: [FavouriteID]
    public let createdAt: Date

    public init(
        arrangementVersionID: FavouriteArrangementVersionID,
        ordinal: VersionOrdinal,
        supersedesArrangementVersionID: FavouriteArrangementVersionID? = nil,
        order: [FavouriteID],
        createdAt: Date
    ) throws {
        guard (supersedesArrangementVersionID == nil) == (ordinal.value == 1) else {
            throw FoodLedgerValidationError.invalidOrdinal
        }
        guard Set(order).count == order.count else {
            throw FoodLedgerValidationError.duplicateValue("favourite order")
        }
        self.arrangementVersionID = arrangementVersionID
        self.ordinal = ordinal
        self.supersedesArrangementVersionID = supersedesArrangementVersionID
        self.order = order
        self.createdAt = createdAt
    }
}
