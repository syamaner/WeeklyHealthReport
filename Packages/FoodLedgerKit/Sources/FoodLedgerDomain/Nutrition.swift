import Foundation

public enum NutrientUnit: String, Codable, Sendable {
    case kilocalories = "kcal"
    case grams = "g"
    case milligrams = "mg"
    case micrograms = "mcg"
    case millilitres = "mL"
}

public enum NutrientKey: String, Codable, CaseIterable, Sendable {
    case energyConsumed = "energy_consumed"
    case carbohydrates
    case protein
    case fatTotal = "fat_total"
    case fatSaturated = "fat_saturated"
    case fatMonounsaturated = "fat_monounsaturated"
    case fatPolyunsaturated = "fat_polyunsaturated"
    case fiber
    case sugar
    case cholesterol
    case vitaminA = "vitamin_a"
    case thiaminB1 = "thiamin_b1"
    case riboflavinB2 = "riboflavin_b2"
    case niacinB3 = "niacin_b3"
    case pantothenicAcidB5 = "pantothenic_acid_b5"
    case vitaminB6 = "vitamin_b6"
    case biotinB7 = "biotin_b7"
    case folateB9 = "folate_b9"
    case vitaminB12 = "vitamin_b12"
    case vitaminC = "vitamin_c"
    case vitaminD = "vitamin_d"
    case vitaminE = "vitamin_e"
    case vitaminK = "vitamin_k"
    case calcium
    case chloride
    case iron
    case magnesium
    case phosphorus
    case potassium
    case sodium
    case zinc
    case chromium
    case copper
    case iodine
    case manganese
    case molybdenum
    case selenium
    case water
    case caffeine

    public var canonicalUnit: NutrientUnit {
        switch self {
        case .energyConsumed: .kilocalories
        case .carbohydrates, .protein, .fatTotal, .fatSaturated,
             .fatMonounsaturated, .fatPolyunsaturated, .fiber, .sugar: .grams
        case .vitaminA, .biotinB7, .folateB9, .vitaminB12, .vitaminD,
             .vitaminK, .chromium, .iodine, .molybdenum, .selenium: .micrograms
        case .water: .millilitres
        default: .milligrams
        }
    }
}

public enum ResolutionBasis: Codable, Equatable, Sendable {
    case per100Grams
    case per100Millilitres
    case perServing(PositiveQuantity)
    case perUnit(PositiveQuantity)
    case named(LedgerText, PositiveQuantity)
    case unknown
}

public struct SourceExactNutrientValue: Codable, Equatable, Sendable {
    public let amount: Double
    public let unit: LedgerText
    public let basis: ResolutionBasis

    public init(amount: Double, unit: LedgerText, basis: ResolutionBasis) throws {
        guard amount.isFinite else { throw FoodLedgerValidationError.nonFinite("source nutrient amount") }
        guard amount >= 0 else { throw FoodLedgerValidationError.negative("source nutrient amount") }
        guard basis != .unknown else { throw FoodLedgerValidationError.invalidBasis }
        self.amount = amount
        self.unit = unit
        self.basis = basis
    }
}

public struct SourceBoundedNutrientValue: Codable, Equatable, Sendable {
    public let lower: Double?
    public let upper: Double?
    public let lowerClosed: Bool
    public let upperClosed: Bool
    public let unit: LedgerText
    public let basis: ResolutionBasis

    public init(
        lower: Double?,
        upper: Double?,
        lowerClosed: Bool,
        upperClosed: Bool,
        unit: LedgerText,
        basis: ResolutionBasis
    ) throws {
        guard lower != nil || upper != nil else { throw FoodLedgerValidationError.malformedBounds }
        guard lower?.isFinite != false, upper?.isFinite != false else {
            throw FoodLedgerValidationError.nonFinite("source nutrient bound")
        }
        guard lower.map({ $0 >= 0 }) ?? true, upper.map({ $0 >= 0 }) ?? true else {
            throw FoodLedgerValidationError.negative("source nutrient bound")
        }
        if let lower, let upper {
            guard lower < upper else { throw FoodLedgerValidationError.malformedBounds }
        }
        guard basis != .unknown else { throw FoodLedgerValidationError.invalidBasis }
        self.lower = lower
        self.upper = upper
        self.lowerClosed = lowerClosed
        self.upperClosed = upperClosed
        self.unit = unit
        self.basis = basis
    }
}

public enum SourceNutrientValue: Codable, Equatable, Sendable {
    case exact(SourceExactNutrientValue)
    case bounded(SourceBoundedNutrientValue)
}

public struct NutrientTransform: Codable, Equatable, Sendable {
    public let transformID: LedgerText
    public let transformVersion: LedgerText
    public let quantityConversionVersionID: QuantityConversionVersionID?

    public init(
        transformID: LedgerText,
        transformVersion: LedgerText,
        quantityConversionVersionID: QuantityConversionVersionID? = nil
    ) {
        self.transformID = transformID
        self.transformVersion = transformVersion
        self.quantityConversionVersionID = quantityConversionVersionID
    }
}

public enum ProvenanceSourceKind: String, Codable, Sendable {
    case userVerifiedPanel = "user_verified_panel"
    case manualDeclaration = "manual_declaration"
    case exactProductDataset = "exact_product_dataset"
    case genericCompositionDataset = "generic_composition_dataset"
    case recipeReconstruction = "recipe_reconstruction"
}

public struct NutrientProvenance: Codable, Equatable, Sendable {
    public let sourceKind: ProvenanceSourceKind
    public let sourceID: ExternalIdentifier
    public let sourceReleaseID: ExternalIdentifier
    public let recordID: ExternalIdentifier?
    public let evidenceID: EvidenceID?
    public let capturedAt: Date?
    public let responseHash: SHA256Digest?
    public let manifestReference: LedgerText?
    public let decisionID: CandidateDecisionID?
    public let assertionID: AssertionID?
    public let transforms: [NutrientTransform]

    public init(
        sourceKind: ProvenanceSourceKind,
        sourceID: ExternalIdentifier,
        sourceReleaseID: ExternalIdentifier,
        recordID: ExternalIdentifier? = nil,
        evidenceID: EvidenceID? = nil,
        capturedAt: Date? = nil,
        responseHash: SHA256Digest? = nil,
        manifestReference: LedgerText? = nil,
        decisionID: CandidateDecisionID? = nil,
        assertionID: AssertionID? = nil,
        transforms: [NutrientTransform] = []
    ) {
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.sourceReleaseID = sourceReleaseID
        self.recordID = recordID
        self.evidenceID = evidenceID
        self.capturedAt = capturedAt
        self.responseHash = responseHash
        self.manifestReference = manifestReference
        self.decisionID = decisionID
        self.assertionID = assertionID
        self.transforms = transforms
    }
}

public struct ExactNutrientValue: Codable, Equatable, Sendable {
    public let amount: Double
    public let unit: NutrientUnit
    public let sourceValue: SourceNutrientValue
    public let provenance: [NutrientProvenance]

    public init(
        amount: Double,
        unit: NutrientUnit,
        sourceValue: SourceNutrientValue,
        provenance: [NutrientProvenance]
    ) throws {
        guard amount.isFinite else { throw FoodLedgerValidationError.nonFinite("nutrient amount") }
        guard amount >= 0 else { throw FoodLedgerValidationError.negative("nutrient amount") }
        guard !provenance.isEmpty else { throw FoodLedgerValidationError.missingProvenance }
        guard case .exact = sourceValue else { throw FoodLedgerValidationError.malformedBounds }
        if case let .exact(source) = sourceValue,
           source.unit.value != unit.rawValue,
           provenance.allSatisfy({ $0.transforms.isEmpty }) {
            throw FoodLedgerValidationError.invalidProvenance
        }
        self.amount = amount
        self.unit = unit
        self.sourceValue = sourceValue
        self.provenance = provenance
    }
}

public enum BoundOrigin: String, Codable, Sendable {
    case measured
    case augmented
}

public struct NutrientBounds: Codable, Equatable, Sendable {
    public let lower: Double?
    public let upper: Double?
    public let lowerClosed: Bool
    public let upperClosed: Bool
    public let origin: BoundOrigin
    public let unit: NutrientUnit
    public let sourceValue: SourceNutrientValue
    public let provenance: [NutrientProvenance]

    public init(
        lower: Double?,
        upper: Double?,
        lowerClosed: Bool,
        upperClosed: Bool,
        origin: BoundOrigin,
        unit: NutrientUnit,
        sourceValue: SourceNutrientValue,
        provenance: [NutrientProvenance]
    ) throws {
        guard lower != nil || upper != nil else { throw FoodLedgerValidationError.malformedBounds }
        guard lower?.isFinite != false, upper?.isFinite != false else {
            throw FoodLedgerValidationError.nonFinite("nutrient bound")
        }
        guard lower.map({ $0 >= 0 }) ?? true, upper.map({ $0 >= 0 }) ?? true else {
            throw FoodLedgerValidationError.negative("nutrient bound")
        }
        if let lower, let upper {
            guard lower < upper else { throw FoodLedgerValidationError.malformedBounds }
        }
        guard !provenance.isEmpty else { throw FoodLedgerValidationError.missingProvenance }
        let sourceUnit: LedgerText
        switch sourceValue {
        case let .exact(source): sourceUnit = source.unit
        case let .bounded(source): sourceUnit = source.unit
        }
        if sourceUnit.value != unit.rawValue,
           provenance.allSatisfy({ $0.transforms.isEmpty }) {
            throw FoodLedgerValidationError.invalidProvenance
        }
        self.lower = lower
        self.upper = upper
        self.lowerClosed = lowerClosed
        self.upperClosed = upperClosed
        self.origin = origin
        self.unit = unit
        self.sourceValue = sourceValue
        self.provenance = provenance
    }
}

public enum UnknownReason: String, Codable, Sendable {
    case notDeclared = "not_declared"
    case noCompatibleSource = "no_compatible_source"
    case missingConversion = "missing_conversion"
    case conflictingEvidence = "conflicting_evidence"
}

public enum NutrientValue: Codable, Equatable, Sendable {
    case measured(ExactNutrientValue)
    case augmented(ExactNutrientValue)
    case bounded(NutrientBounds)
    case unknown(UnknownReason)

    public var provenance: [NutrientProvenance] {
        switch self {
        case let .measured(value), let .augmented(value): value.provenance
        case let .bounded(value): value.provenance
        case .unknown: []
        }
    }
}

public enum ResolutionStatus: String, Codable, Sendable {
    case resolved
    case conflict
}

public struct NutrientEntry: Codable, Equatable, Sendable {
    public let key: NutrientKey
    public let value: NutrientValue
    public let status: ResolutionStatus
    public let conflictCandidates: [NutrientValue]

    public init(
        key: NutrientKey,
        value: NutrientValue,
        status: ResolutionStatus = .resolved,
        conflictCandidates: [NutrientValue] = []
    ) throws {
        switch (status, value, conflictCandidates.count) {
        case (.resolved, _, 0): break
        case (.conflict, .unknown(.conflictingEvidence), 2...): break
        default: throw FoodLedgerValidationError.invalidConflict
        }
        try Self.validate(value, for: key, allowUnknown: true)
        for candidate in conflictCandidates {
            try Self.validate(candidate, for: key, allowUnknown: false)
        }
        self.key = key
        self.value = value
        self.status = status
        self.conflictCandidates = conflictCandidates
    }

    private static func validate(
        _ value: NutrientValue,
        for key: NutrientKey,
        allowUnknown: Bool
    ) throws {
        switch value {
        case let .measured(exact):
            guard exact.unit == key.canonicalUnit else { throw FoodLedgerValidationError.invalidUnit }
            guard exact.provenance.allSatisfy({
                switch $0.sourceKind {
                case .userVerifiedPanel, .manualDeclaration, .exactProductDataset: true
                case .genericCompositionDataset, .recipeReconstruction: false
                }
            }) else { throw FoodLedgerValidationError.invalidProvenance }
        case let .augmented(exact):
            guard exact.unit == key.canonicalUnit else { throw FoodLedgerValidationError.invalidUnit }
            guard exact.provenance.allSatisfy({ provenance in
                switch provenance.sourceKind {
                case .genericCompositionDataset, .exactProductDataset:
                    provenance.recordID != nil
                case .recipeReconstruction:
                    true
                case .userVerifiedPanel, .manualDeclaration:
                    false
                }
            }) else { throw FoodLedgerValidationError.invalidProvenance }
        case let .bounded(bounds):
            guard bounds.unit == key.canonicalUnit else { throw FoodLedgerValidationError.invalidUnit }
            guard bounds.provenance.allSatisfy({ provenance in
                switch (bounds.origin, provenance.sourceKind) {
                case (.measured, .userVerifiedPanel), (.measured, .manualDeclaration),
                     (.measured, .exactProductDataset), (.augmented, .recipeReconstruction):
                    true
                case (.augmented, .genericCompositionDataset), (.augmented, .exactProductDataset):
                    provenance.recordID != nil
                default:
                    false
                }
            }) else { throw FoodLedgerValidationError.invalidProvenance }
        case .unknown:
            guard allowUnknown else { throw FoodLedgerValidationError.invalidConflict }
        }
    }
}

public struct NutrientSet: Codable, Equatable, Sendable {
    public static let catalogueVersion = 1
    public let entries: [NutrientEntry]

    public init(entries: [NutrientEntry]) throws {
        guard entries.map(\.key) == NutrientKey.allCases else {
            throw FoodLedgerValidationError.invalidNutrientCatalogue
        }
        self.entries = entries
    }
}
