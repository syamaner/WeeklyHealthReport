import Foundation

/// The model's answer under `pasted-label-ai-text-wire-schema-v1` (docs/pasted-label-ai-text-v1.md
/// 4.2, contract test 16): the photo wire's shape (printed text only, absent values as the string
/// `unknown`), plus one optional member on each value, `unit`, which the model fills only for a
/// bare number. The unit is never taken on trust: the mapping accepts it only through the unit
/// check (D10, D16).
///
/// Decoding is strict: every required member is present exactly once, no other member is admitted,
/// and every enumerated member holds one of its values. `unit` may be absent, `null` or a string
/// (an empty string reads as absent); any other type throws. So a reply that is not schema-valid
/// never reaches the mapping.
public struct PastedLabelAITextWire: Decodable, Equatable, Sendable {
    public static let schemaVersion = "pasted-label-ai-text-wire-schema-v1"
    public static let languages: Set<String> = ["en", "zh-Hant", "mixed", "unknown"]
    public static let bases: Set<String> = ["per_100g", "per_100ml", "per_serving", "reference_intake"]
    public static let nutrients: Set<String> = ["energy_kj", "energy_kcal", "fat", "saturates", "trans_fat", "carbohydrate", "sugars",
                                                "added_sugars", "fibre", "protein", "salt", "sodium", "unrecognised"]

    public struct Header: Decodable, Equatable, Sendable {
        public let headerID: String
        public let printedText: String
        public let basis: String

        enum CodingKeys: String, CodingKey, CaseIterable { case headerID = "header_id", printedText = "printed_text", basis }

        public init(headerID: String, printedText: String, basis: String) {
            self.headerID = headerID; self.printedText = printedText; self.basis = basis
        }

        public init(from decoder: any Decoder) throws {
            try TextWireKeys.require(CodingKeys.self, optional: [], in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            headerID = try container.decode(String.self, forKey: .headerID)
            printedText = try container.decode(String.self, forKey: .printedText)
            basis = try container.decode(String.self, forKey: .basis)
            guard PastedLabelAITextWire.bases.contains(basis) else {
                throw DecodingError.dataCorruptedError(forKey: .basis, in: container, debugDescription: "Unknown basis")
            }
        }
    }

    public struct Value: Decodable, Equatable, Sendable {
        public let headerID: String
        public let printedText: String
        /// The model's unit for a bare number, nil when absent, `null` or empty.
        public let unit: String?

        enum CodingKeys: String, CodingKey, CaseIterable { case headerID = "header_id", printedText = "printed_text", unit }

        public init(headerID: String, printedText: String, unit: String? = nil) {
            self.headerID = headerID; self.printedText = printedText; self.unit = unit.flatMap { $0.isEmpty ? nil : $0 }
        }

        public init(from decoder: any Decoder) throws {
            try TextWireKeys.require(CodingKeys.self, optional: [.unit], in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            headerID = try container.decode(String.self, forKey: .headerID)
            printedText = try container.decode(String.self, forKey: .printedText)
            unit = try container.decodeIfPresent(String.self, forKey: .unit).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    public struct Row: Decodable, Equatable, Sendable {
        public let printedLabel: String
        public let nutrient: String
        public let parentNutrient: String
        public let values: [Value]

        enum CodingKeys: String, CodingKey, CaseIterable {
            case printedLabel = "printed_label", nutrient, parentNutrient = "parent_nutrient", values
        }

        public init(printedLabel: String, nutrient: String, parentNutrient: String, values: [Value]) {
            self.printedLabel = printedLabel; self.nutrient = nutrient; self.parentNutrient = parentNutrient; self.values = values
        }

        public init(from decoder: any Decoder) throws {
            try TextWireKeys.require(CodingKeys.self, optional: [], in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            printedLabel = try container.decode(String.self, forKey: .printedLabel)
            nutrient = try container.decode(String.self, forKey: .nutrient)
            parentNutrient = try container.decode(String.self, forKey: .parentNutrient)
            values = try container.decode([Value].self, forKey: .values)
            guard PastedLabelAITextWire.nutrients.contains(nutrient) else {
                throw DecodingError.dataCorruptedError(forKey: .nutrient, in: container, debugDescription: "Unknown nutrient")
            }
        }
    }

    public let declined: Bool
    public let declineReasons: [String]
    public let language: String
    public let servingSizeText: String
    public let servingsPerPackText: String
    public let headers: [Header]
    public let rows: [Row]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case declined, declineReasons = "decline_reasons", language, servingSizeText = "serving_size_text"
        case servingsPerPackText = "servings_per_pack_text", headers, rows
    }

    public init(declined: Bool, declineReasons: [String], language: String, servingSizeText: String, servingsPerPackText: String,
                headers: [Header], rows: [Row]) {
        self.declined = declined; self.declineReasons = declineReasons; self.language = language
        self.servingSizeText = servingSizeText; self.servingsPerPackText = servingsPerPackText; self.headers = headers; self.rows = rows
    }

    public init(from decoder: any Decoder) throws {
        try TextWireKeys.require(CodingKeys.self, optional: [], in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        declined = try container.decode(Bool.self, forKey: .declined)
        declineReasons = try container.decode([String].self, forKey: .declineReasons)
        language = try container.decode(String.self, forKey: .language)
        servingSizeText = try container.decode(String.self, forKey: .servingSizeText)
        servingsPerPackText = try container.decode(String.self, forKey: .servingsPerPackText)
        headers = try container.decode([Header].self, forKey: .headers)
        rows = try container.decode([Row].self, forKey: .rows)
        guard PastedLabelAITextWire.languages.contains(language) else {
            throw DecodingError.dataCorruptedError(forKey: .language, in: container, debugDescription: "Unknown language")
        }
    }

    /// The answer bytes decoded strictly, or nil when they are not a schema-valid answer.
    public static func decode(_ data: Data) -> PastedLabelAITextWire? {
        try? JSONDecoder().decode(PastedLabelAITextWire.self, from: data)
    }
}

/// Every required member present exactly once, the optional ones at most once, and no other (the
/// schema's `additionalProperties: false`).
enum TextWireKeys {
    private struct AnyKey: CodingKey {
        let stringValue: String; let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    static func require<Keys: CodingKey & CaseIterable & Hashable>(_ keys: Keys.Type, optional: Set<Keys>, in decoder: any Decoder) throws {
        let present = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
        let all = Set(Keys.allCases.map(\.stringValue))
        let required = all.subtracting(optional.map(\.stringValue))
        guard Set(present).isSubset(of: all), required.isSubset(of: Set(present)), present.count == Set(present).count else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected or missing wire members"))
        }
    }
}
