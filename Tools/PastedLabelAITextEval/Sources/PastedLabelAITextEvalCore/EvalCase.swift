import CryptoKit
import Foundation

/// `pasted-label-ai-text-eval-case-v1` (docs/pasted-label-ai-text-v1.md 5.1): one label of the
/// evaluation, in the one format that replaces the per-programme transcription schemas. It holds
/// no label text: the text is named by its SHA-256 and stays in the private folder. The expected
/// table is the transcription's, kept verbatim (labels, nutrients, columns and printed values as
/// transcribed), so scorer v2 reads it unchanged and the source transcription is recovered exactly.
/// The role follows from the set (5.1 and D4): only `uk_v2_fresh` is held out. Decoding is strict.
public struct EvalCase: Codable, Equatable, Sendable {
    public static let schema = "pasted-label-ai-text-eval-case-v1"

    /// The evaluation sets of 5.1.
    public enum EvalSet: String, Codable, CaseIterable, Sendable {
        case taiwanV3Development = "taiwan_v3_development"
        case taiwanV3Fresh = "taiwan_v3_fresh"
        case ukV1Development = "uk_v1_development"
        case ukV1Fresh = "uk_v1_fresh"
        case ukV2Fresh = "uk_v2_fresh"

        public var role: Role { self == .ukV2Fresh ? .heldOut : .tuning }
        public var format: Format {
            switch self {
            case .taiwanV3Development, .taiwanV3Fresh: .taiwan
            case .ukV1Development, .ukV1Fresh, .ukV2Fresh: .uk
            }
        }
    }

    public enum Role: String, Codable, CaseIterable, Sendable { case tuning, heldOut = "held_out" }

    /// The format the label is read under: Taiwan, or a UK-format declaration (EU English included, D18).
    public enum Format: String, Codable, CaseIterable, Sendable { case taiwan, uk }

    /// The expected table, verbatim from the transcription.
    public struct Expected: Codable, Equatable, Sendable {
        /// The UK schema's panel (`uk_declaration`, `us_nutrition_facts`, `other_english`); nil for
        /// a transcription in the Taiwan schema.
        public let panel: String?
        public let servingSize: TranscriptionShapes.Quantity?
        public let servingsPerPack: TranscriptionShapes.Pack?
        public let columns: [TranscriptionShapes.Column]
        public let rows: [TranscriptionShapes.Row]
        public let notes: [String]

        public init(panel: String?, servingSize: TranscriptionShapes.Quantity?, servingsPerPack: TranscriptionShapes.Pack?,
                    columns: [TranscriptionShapes.Column], rows: [TranscriptionShapes.Row], notes: [String]) {
            self.panel = panel; self.servingSize = servingSize; self.servingsPerPack = servingsPerPack
            self.columns = columns; self.rows = rows; self.notes = notes
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case panel, columns, rows, notes
            case servingSize = "serving_size", servingsPerPack = "servings_per_pack"
        }

        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "expected")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            panel = try container.decodeIfPresent(String.self, forKey: .panel)
            servingSize = try container.decodeIfPresent(TranscriptionShapes.Quantity.self, forKey: .servingSize)
            servingsPerPack = try container.decodeIfPresent(TranscriptionShapes.Pack.self, forKey: .servingsPerPack)
            columns = try container.decode([TranscriptionShapes.Column].self, forKey: .columns)
            rows = try container.decode([TranscriptionShapes.Row].self, forKey: .rows)
            notes = try container.decode([String].self, forKey: .notes)
        }
    }

    /// The transcription the case was converted from: its schema and the SHA-256 of its bytes.
    public struct Source: Codable, Equatable, Sendable {
        public let schema: String
        public let sha256: String
        public init(schema: String, sha256: String) { self.schema = schema; self.sha256 = sha256 }
        enum CodingKeys: String, CodingKey, CaseIterable { case schema, sha256 }
        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "source")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schema = try container.decode(String.self, forKey: .schema)
            sha256 = try container.decode(String.self, forKey: .sha256)
        }
    }

    /// One printed field: one nutrient under one column, as transcribed.
    public struct Field: Equatable, Sendable {
        public let rowIndex: Int
        public let columnIndex: Int
        public let label: String
        public let nutrient: String
        public let basis: String?
        public let value: TranscriptionShapes.Value
    }

    public let schema: String
    public let labelID: String
    public let set: EvalSet
    public let role: Role
    public let format: Format
    /// The collection tier (`A` or `B` for the UK sets), nil where the set has none.
    public let tier: String?
    /// The copy method recorded in the label's collection record.
    public let copyMethod: String
    /// The SHA-256 of the label's text file bytes, lowercase hex.
    public let textSHA256: String
    public let expected: Expected
    public let source: Source
    /// What a legacy transcription records beyond the case format, so it round-trips exactly
    /// (A2: the Taiwan reader v3 development set's older answer format). Absent for every other
    /// schema, so their canonical bytes are unchanged.
    public let legacy: TranscriptionShapes.LegacyExtras?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, set, role, format, tier, expected, source, legacy
        case labelID = "label_id", copyMethod = "copy_method", textSHA256 = "text_sha256"
    }

    public init(labelID: String, set: EvalSet, tier: String?, copyMethod: String, textSHA256: String, expected: Expected, source: Source,
                legacy: TranscriptionShapes.LegacyExtras? = nil) throws {
        self.schema = Self.schema
        self.labelID = labelID; self.set = set; self.role = set.role; self.format = set.format; self.tier = tier
        self.copyMethod = copyMethod; self.textSHA256 = textSHA256; self.expected = expected; self.source = source; self.legacy = legacy
        try validate()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema); try container.encode(labelID, forKey: .labelID); try container.encode(set, forKey: .set)
        try container.encode(role, forKey: .role); try container.encode(format, forKey: .format)
        try container.encodeIfPresent(tier, forKey: .tier); try container.encode(copyMethod, forKey: .copyMethod)
        try container.encode(textSHA256, forKey: .textSHA256); try container.encode(expected, forKey: .expected)
        try container.encode(source, forKey: .source); try container.encodeIfPresent(legacy, forKey: .legacy)
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: Self.schema)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        labelID = try container.decode(String.self, forKey: .labelID)
        set = try container.decode(EvalSet.self, forKey: .set)
        role = try container.decode(Role.self, forKey: .role)
        format = try container.decode(Format.self, forKey: .format)
        tier = try container.decodeIfPresent(String.self, forKey: .tier)
        copyMethod = try container.decode(String.self, forKey: .copyMethod)
        textSHA256 = try container.decode(String.self, forKey: .textSHA256)
        expected = try container.decode(Expected.self, forKey: .expected)
        source = try container.decode(Source.self, forKey: .source)
        legacy = try container.decodeIfPresent(TranscriptionShapes.LegacyExtras.self, forKey: .legacy)
        try validate()
    }

    public struct Invalid: Error, CustomStringConvertible, Equatable {
        public let description: String
        init(_ description: String) { self.description = description }
    }

    static let nutrients: Set<String> = ["energy_kcal", "energy_kj", "protein", "fat", "saturates", "trans_fat", "carbohydrate", "sugars",
                                         "added_sugars", "fibre", "sodium", "salt", "other"]
    static let bases: Set<String> = ["per_serving", "per_100g", "per_100ml", "reference_intake"]

    /// The closed set and schema pairing (Qodo finding 6 on #421), as the frozen harnesses in
    /// `Packages/FoodLedgerKit/Tests/FoodLabelTextCaptureTests/` read each set:
    /// - `taiwan_v3_fresh`: `FreshSet.transcription` and `FreshSet.problems`
    ///   (`FreshSet/FreshSetProtocol.swift`), the Taiwan schema only;
    /// - `uk_v1_fresh` and `uk_v2_fresh`: `UKFreshSet.transcription` (`UKFreshSet/UKFreshSetProtocol.swift`),
    ///   which refuses any schema but the UK one;
    /// - `uk_v1_development`: `UKFreshSet.developmentTranscription`, called by
    ///   `UKDevelopment/UKDevelopmentSet.swift`, which reads the P1 Taiwan-schema files and returns a
    ///   UK-schema file as it is;
    /// - `taiwan_v3_development`: no committed harness reads it (reader v3 section 1.1 kept its
    ///   transcriptions outside the repository with no recorded schema). A2 admits its older answer
    ///   format under the named legacy schema `TranscriptionShapes.TaiwanLegacyTranscription.schema`
    ///   (the format the owner described: columns with keys, values as a flat list), and nothing else.
    static let schemas: [EvalSet: Set<String>] = [
        .taiwanV3Development: [TranscriptionShapes.TaiwanLegacyTranscription.schema],
        .taiwanV3Fresh: [TranscriptionShapes.TaiwanTranscription.schema],
        .ukV1Development: [TranscriptionShapes.TaiwanTranscription.schema, TranscriptionShapes.UKTranscription.schema],
        .ukV1Fresh: [TranscriptionShapes.UKTranscription.schema],
        .ukV2Fresh: [TranscriptionShapes.UKTranscription.schema],
    ]

    public static func isSHA256Hex(_ text: String) -> Bool { isSHA256(text) }

    static func isSHA256(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// The rules every case holds, on build and on decode.
    func validate() throws {
        guard schema == Self.schema else { throw Invalid("schema \(schema) is not \(Self.schema)") }
        guard !labelID.isEmpty else { throw Invalid("empty label_id") }
        guard role == set.role else { throw Invalid("\(labelID): role \(role.rawValue) does not match set \(set.rawValue)") }
        guard format == set.format else { throw Invalid("\(labelID): format \(format.rawValue) does not match set \(set.rawValue)") }
        if let tier, tier.isEmpty { throw Invalid("\(labelID): empty tier") }
        if set == .ukV2Fresh, !["A", "B"].contains(tier ?? "") { throw Invalid("\(labelID): a held-out label needs tier A or B") }
        guard !copyMethod.isEmpty else { throw Invalid("\(labelID): empty copy_method") }
        guard Self.isSHA256(textSHA256) else { throw Invalid("\(labelID): text_sha256 is not lowercase SHA-256 hex") }
        guard Self.isSHA256(source.sha256) else { throw Invalid("\(labelID): source sha256 is not lowercase SHA-256 hex") }
        guard Self.schemas[set, default: []].contains(source.schema) else {
            throw Invalid("\(labelID): set \(set.rawValue) is not transcribed in schema \(source.schema)")
        }
        guard (legacy != nil) == (source.schema == TranscriptionShapes.TaiwanLegacyTranscription.schema) else {
            throw Invalid("\(labelID): legacy extras belong to the legacy schema only")
        }
        switch source.schema {
        case TranscriptionShapes.TaiwanTranscription.schema, TranscriptionShapes.TaiwanLegacyTranscription.schema:
            guard expected.panel == nil else { throw Invalid("\(labelID): a Taiwan-schema transcription has no panel") }
        default:
            guard let panel = expected.panel, TranscriptionShapes.UKTranscription.panels.contains(panel) else {
                throw Invalid("\(labelID): a UK-schema transcription needs a known panel")
            }
        }
        for column in expected.columns {
            if let basis = column.basis, !Self.bases.contains(basis) { throw Invalid("\(labelID): unknown basis \(basis)") }
        }
        for row in expected.rows {
            guard Self.nutrients.contains(row.nutrient) else { throw Invalid("\(labelID): unknown nutrient \(row.nutrient)") }
            guard row.values.count == expected.columns.count else {
                throw Invalid("\(labelID): row \(row.label) has \(row.values.count) values for \(expected.columns.count) columns")
            }
        }
        // The frozen harnesses' value rules, by the source schema's tables.
        let schema: TranscriptionRules.Schema = source.schema == TranscriptionShapes.UKTranscription.schema ? .uk : .taiwan
        let problems = TranscriptionRules.problems(expected, schema, ukMarkers: format == .uk)
        guard problems.isEmpty else { throw Invalid("\(labelID): " + problems.joined(separator: "; ")) }
    }

    /// The printed fields, in row then column order.
    public var fields: [Field] {
        expected.rows.enumerated().flatMap { rowIndex, row in
            row.values.enumerated().compactMap { columnIndex, value in
                value.map { Field(rowIndex: rowIndex, columnIndex: columnIndex, label: row.label, nutrient: row.nutrient,
                                  basis: expected.columns[columnIndex].basis, value: $0) }
            }
        }
    }

    // MARK: Canonical bytes

    /// The case's canonical JSON: sorted keys, no escaped slashes, one trailing newline.
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    public static func decode(_ data: Data) throws -> EvalCase { try JSONDecoder().decode(EvalCase.self, from: data) }

    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
