import Foundation

/// Shared output of every nutrition-label capture route (`label-capture-candidate-v1`).
///
/// A candidate only proposes cells for explicit user selection. It never authorises
/// persistence: `readyForConfirmation` and `automaticSave` are always `false`,
/// and `wouldMarkReady` records what the route would have done, for scoring only.
public struct LabelCaptureCandidate: Equatable, Sendable {
    public static let schemaVersion = "label-capture-candidate-v1"

    public var route: String
    public var inputSHA256: String
    public var declined: Bool
    public var declineReasons: [String]
    public var wouldMarkReady: Bool
    public var language: LabelLanguage
    public var servingSize: LabelServingSize?
    public var servingsPerPack: LabelServingsPerPack?
    public var headers: [LabelHeader]
    public var cells: [LabelCell]
    public var warnings: [String]

    public init(
        route: String,
        inputSHA256: String,
        declined: Bool,
        declineReasons: [String],
        wouldMarkReady: Bool,
        language: LabelLanguage,
        servingSize: LabelServingSize?,
        servingsPerPack: LabelServingsPerPack?,
        headers: [LabelHeader],
        cells: [LabelCell],
        warnings: [String]
    ) {
        self.route = route
        self.inputSHA256 = inputSHA256
        self.declined = declined
        self.declineReasons = declineReasons
        self.wouldMarkReady = wouldMarkReady && !declined
        self.language = language
        self.servingSize = servingSize
        self.servingsPerPack = servingsPerPack
        self.headers = headers
        self.cells = cells
        self.warnings = warnings
    }

    public static func declined(route: String, inputSHA256: String, language: LabelLanguage, reasons: [String]) -> Self {
        Self(
            route: route,
            inputSHA256: inputSHA256,
            declined: true,
            declineReasons: reasons,
            wouldMarkReady: false,
            language: language,
            servingSize: nil,
            servingsPerPack: nil,
            headers: [],
            cells: [],
            warnings: []
        )
    }
}

public enum LabelLanguage: String, Codable, Sendable {
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case mixed
    case unknown
}

public enum LabelBasis: String, Codable, Sendable {
    case per100g = "per_100g"
    case per100ml = "per_100ml"
    case perServing = "per_serving"
    case referenceIntake = "reference_intake"
}

public enum LabelComparator: String, Codable, Sendable {
    case equal = "="
    case less = "<"
    case lessOrEqual = "<="
}

public struct LabelServingSize: Codable, Equatable, Sendable {
    public var printedText: String
    public var decimalText: String?
    public var unit: String?
    public var canonicalUnit: String?

    enum CodingKeys: String, CodingKey {
        case printedText = "printed_text"
        case decimalText = "decimal_text"
        case unit
        case canonicalUnit = "canonical_unit"
    }
}

public struct LabelServingsPerPack: Codable, Equatable, Sendable {
    public var printedText: String
    public var decimalText: String
    public var approximate: Bool

    enum CodingKeys: String, CodingKey {
        case printedText = "printed_text"
        case decimalText = "decimal_text"
        case approximate
    }
}

public struct LabelHeader: Codable, Equatable, Sendable {
    public var headerID: String
    public var printedText: String
    public var basis: LabelBasis
    public var servingConversion: String?

    enum CodingKeys: String, CodingKey {
        case headerID = "header_id"
        case printedText = "printed_text"
        case basis
        case servingConversion = "serving_conversion"
    }
}

public struct LabelCell: Codable, Equatable, Sendable {
    public var rowID: String
    public var parentRowID: String?
    public var nutrient: String
    public var printedLabel: String
    public var headerID: String
    public var basis: LabelBasis
    public var printedText: String
    public var comparator: LabelComparator
    public var decimalText: String
    public var unit: String
    public var canonicalUnit: String
    /// The printed serving quantity for a per-serving cell, or `unknown`.
    public var servingConversion: String
    public var persistenceAuthorized: Bool { false }
    public var requiresUserSelection: Bool { true }

    enum CodingKeys: String, CodingKey {
        case rowID = "row_id"
        case parentRowID = "parent_row_id"
        case nutrient
        case printedLabel = "printed_label"
        case headerID = "header_id"
        case basis
        case printedText = "printed_text"
        case comparator
        case decimalText = "decimal_text"
        case unit
        case canonicalUnit = "canonical_unit"
        case servingConversion = "serving_conversion"
        case persistenceAuthorized = "persistence_authorized"
        case requiresUserSelection = "requires_user_selection"
    }

    public init(
        rowID: String,
        parentRowID: String?,
        nutrient: String,
        printedLabel: String,
        headerID: String,
        basis: LabelBasis,
        printedText: String,
        comparator: LabelComparator,
        decimalText: String,
        unit: String,
        canonicalUnit: String,
        servingConversion: String
    ) {
        self.rowID = rowID
        self.parentRowID = parentRowID
        self.nutrient = nutrient
        self.printedLabel = printedLabel
        self.headerID = headerID
        self.basis = basis
        self.printedText = printedText
        self.comparator = comparator
        self.decimalText = decimalText
        self.unit = unit
        self.canonicalUnit = canonicalUnit
        self.servingConversion = servingConversion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rowID = try container.decode(String.self, forKey: .rowID)
        parentRowID = try container.decodeIfPresent(String.self, forKey: .parentRowID)
        nutrient = try container.decode(String.self, forKey: .nutrient)
        printedLabel = try container.decode(String.self, forKey: .printedLabel)
        headerID = try container.decode(String.self, forKey: .headerID)
        basis = try container.decode(LabelBasis.self, forKey: .basis)
        printedText = try container.decode(String.self, forKey: .printedText)
        comparator = try container.decode(LabelComparator.self, forKey: .comparator)
        decimalText = try container.decode(String.self, forKey: .decimalText)
        unit = try container.decode(String.self, forKey: .unit)
        canonicalUnit = try container.decode(String.self, forKey: .canonicalUnit)
        servingConversion = try container.decode(String.self, forKey: .servingConversion)
        guard try container.decode(Bool.self, forKey: .persistenceAuthorized) == false,
              try container.decode(Bool.self, forKey: .requiresUserSelection) == true else {
            throw DecodingError.dataCorruptedError(forKey: .persistenceAuthorized, in: container, debugDescription: "A label cell can never authorise persistence")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rowID, forKey: .rowID)
        try container.encode(parentRowID, forKey: .parentRowID)
        try container.encode(nutrient, forKey: .nutrient)
        try container.encode(printedLabel, forKey: .printedLabel)
        try container.encode(headerID, forKey: .headerID)
        try container.encode(basis, forKey: .basis)
        try container.encode(printedText, forKey: .printedText)
        try container.encode(comparator, forKey: .comparator)
        try container.encode(decimalText, forKey: .decimalText)
        try container.encode(unit, forKey: .unit)
        try container.encode(canonicalUnit, forKey: .canonicalUnit)
        try container.encode(servingConversion, forKey: .servingConversion)
        try container.encode(false, forKey: .persistenceAuthorized)
        try container.encode(true, forKey: .requiresUserSelection)
    }
}

extension LabelCaptureCandidate: Codable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case route
        case inputSHA256 = "input_sha256"
        case status
        case declined
        case declineReasons = "decline_reasons"
        case readyForConfirmation = "ready_for_confirmation"
        case wouldMarkReady = "would_mark_ready"
        case automaticSave = "automatic_save"
        case language
        case servingSize = "serving_size"
        case servingsPerPack = "servings_per_pack"
        case headers
        case cells
        case warnings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .schemaVersion) == Self.schemaVersion,
              try container.decode(String.self, forKey: .status) == "user_selection_only",
              try container.decode(Bool.self, forKey: .readyForConfirmation) == false,
              try container.decode(Bool.self, forKey: .automaticSave) == false else {
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Candidate violates the user-selection-only contract")
        }
        route = try container.decode(String.self, forKey: .route)
        inputSHA256 = try container.decode(String.self, forKey: .inputSHA256)
        declined = try container.decode(Bool.self, forKey: .declined)
        declineReasons = try container.decode([String].self, forKey: .declineReasons)
        wouldMarkReady = try container.decode(Bool.self, forKey: .wouldMarkReady)
        language = try container.decode(LabelLanguage.self, forKey: .language)
        servingSize = try Self.decodeKnown(LabelServingSize.self, container, .servingSize)
        servingsPerPack = try Self.decodeKnown(LabelServingsPerPack.self, container, .servingsPerPack)
        headers = try container.decode([LabelHeader].self, forKey: .headers)
        cells = try container.decode([LabelCell].self, forKey: .cells)
        warnings = try container.decode([String].self, forKey: .warnings)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(route, forKey: .route)
        try container.encode(inputSHA256, forKey: .inputSHA256)
        try container.encode("user_selection_only", forKey: .status)
        try container.encode(declined, forKey: .declined)
        try container.encode(declineReasons, forKey: .declineReasons)
        try container.encode(false, forKey: .readyForConfirmation)
        try container.encode(wouldMarkReady, forKey: .wouldMarkReady)
        try container.encode(false, forKey: .automaticSave)
        try container.encode(language, forKey: .language)
        if let servingSize { try container.encode(servingSize, forKey: .servingSize) } else { try container.encode("unknown", forKey: .servingSize) }
        if let servingsPerPack { try container.encode(servingsPerPack, forKey: .servingsPerPack) } else { try container.encode("unknown", forKey: .servingsPerPack) }
        try container.encode(headers, forKey: .headers)
        try container.encode(cells, forKey: .cells)
        try container.encode(warnings, forKey: .warnings)
    }

    private static func decodeKnown<T: Decodable>(_ type: T.Type, _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> T? {
        if let text = try? container.decode(String.self, forKey: key) {
            guard text == "unknown" else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Only the explicit string unknown is allowed")
            }
            return nil
        }
        return try container.decode(T.self, forKey: key)
    }
}
