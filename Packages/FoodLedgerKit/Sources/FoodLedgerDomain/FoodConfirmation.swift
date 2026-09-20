import Foundation

public struct PopulatedFoodCandidate: Codable, Equatable, Sendable {
    public let candidate: ProviderNeutralCandidate
    public let name: LedgerText
    public let brand: LedgerText?
    public let variant: LedgerText?
    public let barcode: LedgerText?
    public let itemClass: ItemClass
    public let packFacts: PackFacts

    public init(
        candidate: ProviderNeutralCandidate,
        name: LedgerText,
        brand: LedgerText? = nil,
        variant: LedgerText? = nil,
        barcode: LedgerText? = nil,
        itemClass: ItemClass,
        packFacts: PackFacts = PackFacts()
    ) throws {
        switch itemClass {
        case .fortifiedFood:
            guard candidate.identity.fortification == .fortified else {
                throw FoodLedgerValidationError.invalidBasis
            }
        case .food, .drink, .water:
            guard candidate.identity.fortification != .fortified else {
                throw FoodLedgerValidationError.invalidBasis
            }
        case .supplement:
            break
        }
        self.candidate = candidate
        self.name = name
        self.brand = brand
        self.variant = variant
        self.barcode = barcode
        self.itemClass = itemClass
        self.packFacts = packFacts
    }
}

public struct PopulatedFoodConfirmation: Codable, Equatable, Sendable {
    public let evidence: [CaptureEvidence]
    public let sourceReleases: [SourceRelease]
    public let candidates: [PopulatedFoodCandidate]
    public let expectedIdentity: DecisiveIdentity
    public let expectedEdibleQuantity: EdibleQuantityIdentity

    public init(
        evidence: [CaptureEvidence],
        sourceReleases: [SourceRelease],
        candidates: [PopulatedFoodCandidate],
        expectedIdentity: DecisiveIdentity,
        expectedEdibleQuantity: EdibleQuantityIdentity
    ) throws {
        guard !candidates.isEmpty else { throw FoodLedgerValidationError.empty("candidates") }
        guard Set(evidence.map(\.evidenceID)).count == evidence.count,
              Set(sourceReleases.map(\.sourceReleaseID)).count == sourceReleases.count else {
            throw FoodLedgerValidationError.duplicateValue("confirmation input")
        }
        let evidenceIDs = Set(evidence.map(\.evidenceID))
        let releaseIDs = Set(sourceReleases.map(\.sourceReleaseID))
        guard candidates.allSatisfy({
            Set($0.candidate.evidenceIDs).isSubset(of: evidenceIDs)
                && releaseIDs.contains($0.candidate.sourceReleaseID)
        }) else {
            throw FoodLedgerValidationError.missingProvenance
        }
        self.evidence = evidence
        self.sourceReleases = sourceReleases
        self.candidates = candidates
        self.expectedIdentity = expectedIdentity
        self.expectedEdibleQuantity = expectedEdibleQuantity
    }
}

public enum FoodQuantityValidationError: Error, Equatable, Sendable {
    case missingQuantity
    case missingConversion
    case missingPlateWeight
    case invalidPlateUnit
    case nonPositiveEdibleQuantity
}

public enum FoodQuantityCalculator {
    public static func direct(
        entered: PositiveQuantity,
        conversion: QuantityConversionVersion?
    ) throws -> PositiveQuantity {
        if entered.unit == .count {
            guard let conversion, conversion.sourceQuantity == entered else {
                throw FoodQuantityValidationError.missingConversion
            }
            return conversion.convertedQuantity
        }
        if let conversion {
            guard conversion.sourceQuantity == entered else {
                throw FoodQuantityValidationError.missingConversion
            }
            return conversion.convertedQuantity
        }
        return entered
    }

    public static func subtractPlate(
        total: PositiveQuantity,
        emptyPlate: PlateWeightVersion?
    ) throws -> PositiveQuantity {
        guard total.unit == .grams else { throw FoodQuantityValidationError.invalidPlateUnit }
        guard let emptyPlate else { throw FoodQuantityValidationError.missingPlateWeight }
        let edible = total.value - emptyPlate.emptyWeight.value
        guard edible > 0 else { throw FoodQuantityValidationError.nonPositiveEdibleQuantity }
        return try PositiveQuantity(value: edible, unit: .grams)
    }
}
