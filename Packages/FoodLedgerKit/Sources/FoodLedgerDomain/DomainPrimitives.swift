import Foundation

public enum FoodLedgerValidationError: Error, Equatable, Sendable {
    case empty(String)
    case invalidIdentifier(String)
    case nonFinite(String)
    case nonPositive(String)
    case negative(String)
    case invalidDigest
    case invalidOrdinal
    case invalidUnit
    case invalidBasis
    case malformedBounds
    case missingProvenance
    case invalidProvenance
    case invalidNutrientCatalogue
    case invalidConflict
    case duplicateValue(String)
    case hardIdentityContradiction([IdentityContradiction])
}

public struct LedgerText: Codable, Hashable, Sendable {
    public let value: String

    public init(_ value: String, field: String = "value") throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FoodLedgerValidationError.empty(field) }
        self.value = trimmed
    }
}

public struct LedgerID<Tag>: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard
            rawValue == rawValue.lowercased(),
            let uuid = UUID(uuidString: rawValue),
            uuid.uuidString.lowercased() == rawValue
        else {
            throw FoodLedgerValidationError.invalidIdentifier(rawValue)
        }
        self.rawValue = rawValue
    }
}

public enum EvidenceTag: Sendable {}
public enum AssertionTag: Sendable {}
public enum ProductTag: Sendable {}
public enum ProductVersionTag: Sendable {}
public enum LibraryEntryTag: Sendable {}
public enum LibraryEntryVersionTag: Sendable {}
public enum LogItemTag: Sendable {}
public enum LogItemVersionTag: Sendable {}
public enum ResolutionTag: Sendable {}
public enum ResolutionVersionTag: Sendable {}
public enum QuantityConversionVersionTag: Sendable {}
public enum PlateTag: Sendable {}
public enum PlateWeightVersionTag: Sendable {}
public enum CandidateDecisionTag: Sendable {}
public enum ConflictTag: Sendable {}
public enum OperationTag: Sendable {}
public enum ActorTag: Sendable {}

public typealias EvidenceID = LedgerID<EvidenceTag>
public typealias AssertionID = LedgerID<AssertionTag>
public typealias ProductID = LedgerID<ProductTag>
public typealias ProductVersionID = LedgerID<ProductVersionTag>
public typealias LibraryEntryID = LedgerID<LibraryEntryTag>
public typealias LibraryEntryVersionID = LedgerID<LibraryEntryVersionTag>
public typealias LogItemID = LedgerID<LogItemTag>
public typealias LogItemVersionID = LedgerID<LogItemVersionTag>
public typealias ResolutionID = LedgerID<ResolutionTag>
public typealias ResolutionVersionID = LedgerID<ResolutionVersionTag>
public typealias QuantityConversionVersionID = LedgerID<QuantityConversionVersionTag>
public typealias PlateID = LedgerID<PlateTag>
public typealias PlateWeightVersionID = LedgerID<PlateWeightVersionTag>
public typealias CandidateDecisionID = LedgerID<CandidateDecisionTag>
public typealias ConflictID = LedgerID<ConflictTag>
public typealias OperationID = LedgerID<OperationTag>
public typealias ActorID = LedgerID<ActorTag>

public struct SHA256Digest: Codable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        let valid = value.count == 64 && value.allSatisfy { $0.isHexDigit } && value == value.lowercased()
        guard valid else { throw FoodLedgerValidationError.invalidDigest }
        self.value = value
    }
}

public struct VersionOrdinal: Codable, Hashable, Sendable {
    public let value: Int

    public init(_ value: Int) throws {
        guard value > 0 else { throw FoodLedgerValidationError.invalidOrdinal }
        self.value = value
    }
}

public enum QuantityUnit: String, Codable, CaseIterable, Sendable {
    case grams = "g"
    case millilitres = "mL"
    case count
}

public struct PositiveQuantity: Codable, Equatable, Sendable {
    public let value: Double
    public let unit: QuantityUnit

    public init(value: Double, unit: QuantityUnit) throws {
        guard value.isFinite else { throw FoodLedgerValidationError.nonFinite("quantity") }
        guard value > 0 else { throw FoodLedgerValidationError.nonPositive("quantity") }
        self.value = value
        self.unit = unit
    }
}

public struct NonNegativeQuantity: Codable, Equatable, Sendable {
    public let value: Double
    public let unit: QuantityUnit

    public init(value: Double, unit: QuantityUnit) throws {
        guard value.isFinite else { throw FoodLedgerValidationError.nonFinite("quantity") }
        guard value >= 0 else { throw FoodLedgerValidationError.negative("quantity") }
        self.value = value
        self.unit = unit
    }
}

public struct ExternalIdentifier: Codable, Hashable, Sendable {
    public let value: String

    public init(_ value: String, field: String = "external identifier") throws {
        self.value = try LedgerText(value, field: field).value
    }
}
