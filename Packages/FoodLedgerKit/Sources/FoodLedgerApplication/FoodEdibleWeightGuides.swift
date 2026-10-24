import FoodLedgerDomain

/// A piece size a count portion guide offers (count-portion-estimate-v1, #307). The names are the
/// source's US grading; the weight shown beside each is the meaning.
public enum FoodEdibleWeightGuideSize: String, CaseIterable, Codable, Equatable, Sendable {
    case small
    case medium
    case large
    case extraLarge = "extra_large"
}

/// The frozen v1 table of count portion guide codes (count-portion-estimate-v1, section 3). A
/// stored code always keeps its size, grams and label here, even if a later adapter withdraws
/// the guide. A new value, record or wording needs `count_portion_guide_v2:…`.
public enum CountPortionGuideCode {
    public struct Entry: Equatable, Sendable {
        public let code: String
        public let size: FoodEdibleWeightGuideSize
        public let grams: Double
        public let preparation: Preparation
        /// True for a boiled size other than Large: the raw-egg weight for that size (C11).
        public let isDerived: Bool
        public let sourceFDCID: Int
        public let sourcePortionID: Int
        public let sourceDescriptor: String
    }

    public enum Preparation: String, Equatable, Sendable { case raw, boiled }

    /// Prefix shared by every version of the code. A code under it that is not in this table
    /// fails closed at save (C9).
    public static let codePrefix = "count_portion_guide_v"
    public static let v1Prefix = "count_portion_guide_v1:"
    /// The guide source release ID prefix. Estimate status needs code and release together (C6).
    public static let releasePrefix = "usda-sr-legacy-portions:"
    public static let sourceReleaseID =
        "usda-sr-legacy-portions:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef"

    public static let entries: [Entry] = [
        raw(.small, 38, portion: 88379, "small"),
        raw(.medium, 44, portion: 88378, "medium"),
        raw(.large, 50, portion: 88374, "large"),
        raw(.extraLarge, 56, portion: 88375, "extra large"),
        derivedBoiled(.small, 38, portion: 88379, "small"),
        derivedBoiled(.medium, 44, portion: 88378, "medium"),
        Entry(code: v1Prefix + "usda_sr_legacy_173424_92500", size: .large, grams: 50, preparation: .boiled,
              isDerived: false, sourceFDCID: 173424, sourcePortionID: 92500, sourceDescriptor: "large"),
        derivedBoiled(.extraLarge, 56, portion: 88375, "extra large"),
    ]

    private static func raw(_ size: FoodEdibleWeightGuideSize, _ grams: Double, portion: Int, _ descriptor: String) -> Entry {
        Entry(code: v1Prefix + "usda_sr_legacy_171287_\(portion)", size: size, grams: grams, preparation: .raw,
              isDerived: false, sourceFDCID: 171287, sourcePortionID: portion, sourceDescriptor: descriptor)
    }

    private static func derivedBoiled(_ size: FoodEdibleWeightGuideSize, _ grams: Double, portion: Int, _ descriptor: String) -> Entry {
        Entry(code: v1Prefix + "usda_sr_legacy_boiled_from_171287_\(portion)", size: size, grams: grams, preparation: .boiled,
              isDerived: true, sourceFDCID: 171287, sourcePortionID: portion, sourceDescriptor: descriptor)
    }

    public static func entry(_ code: LedgerText) -> Entry? { entries.first { $0.code == code.value } }

    public static func isGuideCode(_ methodVersion: LedgerText) -> Bool { methodVersion.value.hasPrefix(codePrefix) }

    /// Whether a conversion method text may be saved as a guide: outside this namespace, or a
    /// frozen v1 code.
    public static func admits(_ methodVersion: LedgerText) -> Bool {
        !isGuideCode(methodVersion) || entry(methodVersion) != nil
    }
}

/// One size of a count portion guide for one record: a food-specific edible mass per piece.
public struct FoodEdibleWeightGuide: Equatable, Sendable {
    public let code: LedgerText
    public let size: FoodEdibleWeightGuideSize
    /// The size as the source names it ("large").
    public let sourceDescriptor: LedgerText
    public let edibleGramsPerPiece: Double
    public let isDerived: Bool

    public init(code: LedgerText, size: FoodEdibleWeightGuideSize, sourceDescriptor: LedgerText,
                edibleGramsPerPiece: Double, isDerived: Bool) throws {
        _ = try PositiveQuantity(value: edibleGramsPerPiece, unit: .grams)
        self.code = code; self.size = size; self.sourceDescriptor = sourceDescriptor
        self.edibleGramsPerPiece = edibleGramsPerPiece; self.isDerived = isDerived
    }
}

/// The allow-listed sizes for exactly one record, in size order, with its default (Large).
public struct FoodEdibleWeightGuideSet: Equatable, Sendable {
    public let foodRecordID: ExternalIdentifier
    public let foodSourceReleaseID: ExternalIdentifier
    public let entries: [FoodEdibleWeightGuide]
    public let defaultCode: LedgerText

    public init(foodRecordID: ExternalIdentifier, foodSourceReleaseID: ExternalIdentifier,
                entries: [FoodEdibleWeightGuide], defaultCode: LedgerText) throws {
        guard !entries.isEmpty, entries.contains(where: { $0.code == defaultCode }),
              Set(entries.map(\.code)).count == entries.count else { throw FoodLedgerValidationError.invalidProvenance }
        self.foodRecordID = foodRecordID; self.foodSourceReleaseID = foodSourceReleaseID
        self.entries = entries; self.defaultCode = defaultCode
    }

    public func entry(_ code: LedgerText) -> FoodEdibleWeightGuide? { entries.first { $0.code == code } }
}

/// Consumer-owned port for count portion guides (count-portion-estimate-v1, section 8). Empty
/// means no evidenced guide for this record.
public protocol FoodEdibleWeightGuideProviding: Sendable {
    var sourceRelease: SourceRelease { get }
    /// The allow-listed sizes for exactly this record, or nil.
    func guide(for candidate: PopulatedFoodCandidate) throws -> FoodEdibleWeightGuideSet?
}

extension FoodEdibleWeightGuideProviding {
    /// The entry a stored or selected code names, if this record still offers it.
    public func entry(_ code: LedgerText, for candidate: PopulatedFoodCandidate) throws -> FoodEdibleWeightGuide? {
        try guide(for: candidate)?.entry(code)
    }
}

/// Where a guide may be offered: unit pieces with a positive finite count on a record that is
/// not counted in servings (source-declared, recipe or pasted-label servings). Decided by the
/// existing serving policies, never by the unit alone (gate G6).
public enum CountPortionGuidePolicy {
    public static func applies(_ state: FoodConfirmationState) -> Bool {
        guard state.quantity.unit == .count, state.quantity.directWeight == nil,
              state.quantity.plateChoice == .foodOnly else { return false }
        return admitsRecord(state)
    }

    /// Whether the selected record is counted in pieces at all (not servings), whatever the amount.
    public static func admitsRecord(_ state: FoodConfirmationState) -> Bool {
        let candidate = state.selectedCandidate
        return !FoodSourceServingPolicy.applies(state.input, candidate: candidate)
            && !FoodNamedServingPolicy.applies(state.input, candidate: candidate)
            && !PastedLabelServingPolicy.servingsOnly(state.input, candidate: candidate)
            && state.pastedLabelServing == nil
    }

    /// The edible grams a selected guide gives for a count, from the frozen table.
    public static func grams(code: LedgerText, count: Double) -> Double? {
        guard count.isFinite, count > 0, let entry = CountPortionGuideCode.entry(code) else { return nil }
        let total = count * entry.grams
        return total.isFinite && total > 0 ? total : nil
    }
}
