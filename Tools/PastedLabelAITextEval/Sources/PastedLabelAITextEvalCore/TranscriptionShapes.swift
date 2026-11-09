import Foundation

/// The decoding shapes of the two transcription schemas the evaluation reads, copied from the
/// frozen harnesses (`Packages/FoodLedgerKit/Tests/FoodLabelTextCaptureTests/FreshSet/FreshSetProtocol.swift`,
/// `FreshSet.Transcription`, and `.../UKFreshSet/UKFreshSetProtocol.swift`, `UKFreshSet.Transcription`)
/// so this tool never imports a test target. Only the shapes are copied; the scorers' unit and
/// comparator tables stay in the frozen harnesses. Unlike the originals, decoding is strict: an
/// undeclared key is an error, so a conversion never drops a field.
public enum TranscriptionShapes {
    /// The printed number, unit or comparator, recorded verbatim; `outside_table` when it is outside
    /// the scorer's closed lists.
    public struct Quantity: Codable, Equatable, Sendable {
        public let number: String
        public let unit: String
        public let outsideTable: Bool?
        public init(number: String, unit: String, outsideTable: Bool? = nil) { self.number = number; self.unit = unit; self.outsideTable = outsideTable }
        enum CodingKeys: String, CodingKey, CaseIterable { case number, unit, outsideTable = "outside_table" }
        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "serving_size")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            number = try container.decode(String.self, forKey: .number)
            unit = try container.decode(String.self, forKey: .unit)
            outsideTable = try container.decodeIfPresent(Bool.self, forKey: .outsideTable)
        }
    }

    public struct Pack: Codable, Equatable, Sendable {
        public let number: String
        public let approximate: Bool
        public init(number: String, approximate: Bool) { self.number = number; self.approximate = approximate }
        enum CodingKeys: String, CodingKey, CaseIterable { case number, approximate }
        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "servings_per_pack")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            number = try container.decode(String.self, forKey: .number)
            approximate = try container.decode(Bool.self, forKey: .approximate)
        }
    }

    public struct Column: Codable, Equatable, Sendable {
        public let heading: String?
        public let basis: String?
        public init(heading: String?, basis: String?) { self.heading = heading; self.basis = basis }
        enum CodingKeys: String, CodingKey, CaseIterable { case heading, basis }
        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "column")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            heading = try container.decodeIfPresent(String.self, forKey: .heading)
            basis = try container.decodeIfPresent(String.self, forKey: .basis)
        }
    }

    public struct Value: Codable, Equatable, Sendable {
        public let comparator: String
        public let number: String
        public let unit: String
        public let outsideTable: Bool?
        public init(comparator: String, number: String, unit: String, outsideTable: Bool? = nil) {
            self.comparator = comparator; self.number = number; self.unit = unit; self.outsideTable = outsideTable
        }
        enum CodingKeys: String, CodingKey, CaseIterable { case comparator, number, unit, outsideTable = "outside_table" }
        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "value")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            comparator = try container.decode(String.self, forKey: .comparator)
            number = try container.decode(String.self, forKey: .number)
            unit = try container.decode(String.self, forKey: .unit)
            outsideTable = try container.decodeIfPresent(Bool.self, forKey: .outsideTable)
        }
    }

    public struct Row: Codable, Equatable, Sendable {
        public let label: String
        public let nutrient: String
        /// One entry per column; null where the row prints nothing in that column.
        public let values: [Value?]
        public init(label: String, nutrient: String, values: [Value?]) { self.label = label; self.nutrient = nutrient; self.values = values }
        enum CodingKeys: String, CodingKey, CaseIterable { case label, nutrient, values }
        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "row")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try container.decode(String.self, forKey: .label)
            nutrient = try container.decode(String.self, forKey: .nutrient)
            values = try container.decode([Value?].self, forKey: .values)
        }
    }

    /// `reader-v3-fresh-transcription-v1` (reader v3 12.2.5): the Taiwan schema, also used by the
    /// UK v1 development transcriptions.
    public struct TaiwanTranscription: Codable, Equatable, Sendable {
        public static let schema = "reader-v3-fresh-transcription-v1"
        public let schema: String
        public let labelID: String
        public let servingSize: Quantity?
        public let servingsPerPack: Pack?
        public let columns: [Column]
        public let rows: [Row]
        public let notes: [String]

        public init(schema: String, labelID: String, servingSize: Quantity?, servingsPerPack: Pack?, columns: [Column], rows: [Row], notes: [String]) {
            self.schema = schema; self.labelID = labelID; self.servingSize = servingSize; self.servingsPerPack = servingsPerPack
            self.columns = columns; self.rows = rows; self.notes = notes
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schema, columns, rows, notes
            case labelID = "label_id", servingSize = "serving_size", servingsPerPack = "servings_per_pack"
        }

        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: Self.schema)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schema = try container.decode(String.self, forKey: .schema)
            labelID = try container.decode(String.self, forKey: .labelID)
            servingSize = try container.decodeIfPresent(Quantity.self, forKey: .servingSize)
            servingsPerPack = try container.decodeIfPresent(Pack.self, forKey: .servingsPerPack)
            columns = try container.decode([Column].self, forKey: .columns)
            rows = try container.decode([Row].self, forKey: .rows)
            notes = try container.decode([String].self, forKey: .notes)
        }
    }

    /// `uk-english-v1-fresh-transcription-v1` (UK v1 P2 section 2): the Taiwan shape plus `panel`.
    public struct UKTranscription: Codable, Equatable, Sendable {
        public static let schema = "uk-english-v1-fresh-transcription-v1"
        public static let panels: Set<String> = ["uk_declaration", "us_nutrition_facts", "other_english"]
        public let schema: String
        public let labelID: String
        public let panel: String
        public let servingSize: Quantity?
        public let servingsPerPack: Pack?
        public let columns: [Column]
        public let rows: [Row]
        public let notes: [String]

        public init(schema: String, labelID: String, panel: String, servingSize: Quantity?, servingsPerPack: Pack?, columns: [Column], rows: [Row],
                    notes: [String]) {
            self.schema = schema; self.labelID = labelID; self.panel = panel; self.servingSize = servingSize; self.servingsPerPack = servingsPerPack
            self.columns = columns; self.rows = rows; self.notes = notes
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schema, panel, columns, rows, notes
            case labelID = "label_id", servingSize = "serving_size", servingsPerPack = "servings_per_pack"
        }

        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: Self.schema)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schema = try container.decode(String.self, forKey: .schema)
            labelID = try container.decode(String.self, forKey: .labelID)
            panel = try container.decode(String.self, forKey: .panel)
            servingSize = try container.decodeIfPresent(Quantity.self, forKey: .servingSize)
            servingsPerPack = try container.decodeIfPresent(Pack.self, forKey: .servingsPerPack)
            columns = try container.decode([Column].self, forKey: .columns)
            rows = try container.decode([Row].self, forKey: .rows)
            notes = try container.decode([String].self, forKey: .notes)
        }
    }
}
