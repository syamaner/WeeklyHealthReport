import Foundation

/// The Taiwan reader v3 development set's older answer format (docs/pasted-label-ai-text-v1.md
/// 5.1, A2 of #416), admitted under the named legacy schema
/// `reader-v3-development-transcription-legacy`. Its files carry no `schema` member; the owner
/// described their shape (field types only):
///
///     { columns: [{key, printed}], serving_size: {value, unit}, servings_per_pack: {value, approximate},
///       values: [{nutrient, column, value, unit, comparator, extra?}], notes, id, transcribed_by,
///       transcription_corrections? }
///
/// Decoding is strict (an undeclared key is an error). A `value` may be a JSON string or number,
/// and `notes` a string or a list of strings; a file mixing string and number values is refused,
/// so the encoding it used can be restored exactly. The optional `extra` (on a value) and
/// `transcription_corrections` (on the file) were found when A3 first ran the converter on the
/// real files; both are kept in the case's legacy extras so the file round-trips. The fixtures that
/// test them are synthetic.
extension TranscriptionShapes {
    /// A printed number recorded as a JSON string or a JSON number.
    public enum LegacyNumber: Codable, Equatable, Sendable {
        case string(String)
        case number(Decimal)

        public var text: String {
            switch self {
            case let .string(text): text
            case let .number(value): "\(value)"
            }
        }

        public var isNumber: Bool { if case .number = self { true } else { false } }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { self = .string(text); return }
            self = .number(try container.decode(Decimal.self))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(text): try container.encode(text)
            case let .number(value): try container.encode(value)
            }
        }
    }

    /// `notes` as a string or a list of strings.
    public enum LegacyNotes: Codable, Equatable, Sendable {
        case text(String)
        case list([String])

        public var lines: [String] {
            switch self {
            case let .text(text): [text]
            case let .list(lines): lines
            }
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { self = .text(text); return }
            self = .list(try container.decode([String].self))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .text(text): try container.encode(text)
            case let .list(lines): try container.encode(lines)
            }
        }
    }

    public struct TaiwanLegacyTranscription: Codable, Equatable, Sendable {
        public static let schema = "reader-v3-development-transcription-legacy"

        public struct Column: Codable, Equatable, Sendable {
            public let key: String
            public let printed: String?
            public init(key: String, printed: String?) { self.key = key; self.printed = printed }
            enum CodingKeys: String, CodingKey, CaseIterable { case key, printed }
            public init(from decoder: any Decoder) throws {
                try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "legacy column")
                let container = try decoder.container(keyedBy: CodingKeys.self)
                key = try container.decode(String.self, forKey: .key)
                printed = try container.decodeIfPresent(String.self, forKey: .printed)
            }
        }

        public struct Serving: Codable, Equatable, Sendable {
            public let value: LegacyNumber
            public let unit: String
            public init(value: LegacyNumber, unit: String) { self.value = value; self.unit = unit }
            enum CodingKeys: String, CodingKey, CaseIterable { case value, unit }
            public init(from decoder: any Decoder) throws {
                try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "legacy serving_size")
                let container = try decoder.container(keyedBy: CodingKeys.self)
                value = try container.decode(LegacyNumber.self, forKey: .value)
                unit = try container.decode(String.self, forKey: .unit)
            }
        }

        public struct Pack: Codable, Equatable, Sendable {
            public let value: LegacyNumber
            public let approximate: Bool
            public init(value: LegacyNumber, approximate: Bool) { self.value = value; self.approximate = approximate }
            enum CodingKeys: String, CodingKey, CaseIterable { case value, approximate }
            public init(from decoder: any Decoder) throws {
                try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "legacy servings_per_pack")
                let container = try decoder.container(keyedBy: CodingKeys.self)
                value = try container.decode(LegacyNumber.self, forKey: .value)
                approximate = try container.decode(Bool.self, forKey: .approximate)
            }
        }

        public struct Value: Codable, Equatable, Sendable {
            public let nutrient: String
            public let column: String
            public let value: LegacyNumber
            public let unit: String
            public let comparator: String
            /// `true` on a printed value beyond the mandatory rows (seen in the real files in A3); absent otherwise.
            public let extra: Bool?
            public init(nutrient: String, column: String, value: LegacyNumber, unit: String, comparator: String, extra: Bool? = nil) {
                self.nutrient = nutrient; self.column = column; self.value = value; self.unit = unit; self.comparator = comparator
                self.extra = extra
            }
            enum CodingKeys: String, CodingKey, CaseIterable { case nutrient, column, value, unit, comparator, extra }
            public init(from decoder: any Decoder) throws {
                try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "legacy value")
                let container = try decoder.container(keyedBy: CodingKeys.self)
                nutrient = try container.decode(String.self, forKey: .nutrient)
                column = try container.decode(String.self, forKey: .column)
                value = try container.decode(LegacyNumber.self, forKey: .value)
                unit = try container.decode(String.self, forKey: .unit)
                comparator = try container.decode(String.self, forKey: .comparator)
                extra = try container.decodeIfPresent(Bool.self, forKey: .extra)
            }
        }

        public let columns: [Column]
        public let servingSize: Serving?
        public let servingsPerPack: Pack?
        public let values: [Value]
        public let notes: LegacyNotes?
        public let id: String
        public let transcribedBy: String?
        /// The owner's dated corrections to the transcription (seen in the real files in A3), kept verbatim.
        public let transcriptionCorrections: [String]?

        public init(columns: [Column], servingSize: Serving?, servingsPerPack: Pack?, values: [Value], notes: LegacyNotes?, id: String,
                    transcribedBy: String?, transcriptionCorrections: [String]? = nil) {
            self.columns = columns; self.servingSize = servingSize; self.servingsPerPack = servingsPerPack; self.values = values
            self.notes = notes; self.id = id; self.transcribedBy = transcribedBy; self.transcriptionCorrections = transcriptionCorrections
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case columns, values, notes, id
            case servingSize = "serving_size", servingsPerPack = "servings_per_pack", transcribedBy = "transcribed_by"
            case transcriptionCorrections = "transcription_corrections"
        }

        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: Self.schema)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            columns = try container.decode([Column].self, forKey: .columns)
            servingSize = try container.decodeIfPresent(Serving.self, forKey: .servingSize)
            servingsPerPack = try container.decodeIfPresent(Pack.self, forKey: .servingsPerPack)
            values = try container.decode([Value].self, forKey: .values)
            notes = try container.decodeIfPresent(LegacyNotes.self, forKey: .notes)
            id = try container.decode(String.self, forKey: .id)
            transcribedBy = try container.decodeIfPresent(String.self, forKey: .transcribedBy)
            transcriptionCorrections = try container.decodeIfPresent([String].self, forKey: .transcriptionCorrections)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(columns, forKey: .columns); try container.encodeIfPresent(servingSize, forKey: .servingSize)
            try container.encodeIfPresent(servingsPerPack, forKey: .servingsPerPack); try container.encode(values, forKey: .values)
            try container.encodeIfPresent(notes, forKey: .notes); try container.encode(id, forKey: .id)
            try container.encodeIfPresent(transcribedBy, forKey: .transcribedBy)
            try container.encodeIfPresent(transcriptionCorrections, forKey: .transcriptionCorrections)
        }
    }

    /// What the legacy format records beyond the case format: the transcriber, the column keys,
    /// the flat value order, and the JSON encodings of numbers and notes.
    public struct LegacyExtras: Codable, Equatable, Sendable {
        public let transcribedBy: String?
        public let columnKeys: [String]
        /// `nutrient@column` in the file's value order.
        public let valueOrder: [String]
        /// `string` or `number`.
        public let numberEncoding: String
        /// `text`, `list` or nil when the file had no notes.
        public let notesEncoding: String?
        /// `nutrient@column` of the values marked `extra: true`, in value order; nil when none is.
        /// The values themselves stay in the expected table, as printed fields (as reader v3 scored them).
        public let extraValues: [String]?
        /// The file's `transcription_corrections`, verbatim; nil when it had none.
        public let transcriptionCorrections: [String]?

        public init(transcribedBy: String?, columnKeys: [String], valueOrder: [String], numberEncoding: String, notesEncoding: String?,
                    extraValues: [String]? = nil, transcriptionCorrections: [String]? = nil) {
            self.transcribedBy = transcribedBy; self.columnKeys = columnKeys; self.valueOrder = valueOrder
            self.numberEncoding = numberEncoding; self.notesEncoding = notesEncoding
            self.extraValues = extraValues; self.transcriptionCorrections = transcriptionCorrections
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case transcribedBy = "transcribed_by", columnKeys = "column_keys", valueOrder = "value_order", numberEncoding = "number_encoding"
            case notesEncoding = "notes_encoding", extraValues = "extra_values", transcriptionCorrections = "transcription_corrections"
        }

        public init(from decoder: any Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue), in: "legacy")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            transcribedBy = try container.decodeIfPresent(String.self, forKey: .transcribedBy)
            columnKeys = try container.decode([String].self, forKey: .columnKeys)
            valueOrder = try container.decode([String].self, forKey: .valueOrder)
            numberEncoding = try container.decode(String.self, forKey: .numberEncoding)
            notesEncoding = try container.decodeIfPresent(String.self, forKey: .notesEncoding)
            extraValues = try container.decodeIfPresent([String].self, forKey: .extraValues)
            transcriptionCorrections = try container.decodeIfPresent([String].self, forKey: .transcriptionCorrections)
        }
    }
}

extension EvalCaseConverter {
    /// The basis of a legacy column: its key when the key is a basis identifier, otherwise the one
    /// closed Taiwan heading it prints (`每份`, `每100公克`, `每100克`, `每100毫升`, `每日參考值百分比`),
    /// spaces removed; otherwise nil (an unknown basis, which the scorer never matches, so such a
    /// column's values count as wrong rather than as read).
    /// A key that is a basis identifier and a printed heading of the closed table that names
    /// another basis is refused, never resolved either way (A2 gate finding 11).
    static func legacyBasis(_ column: TranscriptionShapes.TaiwanLegacyTranscription.Column) throws -> String? {
        let compact = (column.printed ?? "").filter { !$0.isWhitespace }
        let table = ["每份": "per_serving", "每一份": "per_serving", "每100公克": "per_100g", "每100克": "per_100g", "每100g": "per_100g",
                     "每100毫升": "per_100ml", "每100ml": "per_100ml", "每日參考值百分比": "reference_intake"]
        let heading = table[compact]
        if EvalCase.bases.contains(column.key) {
            if let heading, heading != column.key {
                throw Refused("column \(column.key) prints \(column.printed ?? ""), which names \(heading)")
            }
            return column.key
        }
        return heading
    }

    /// A legacy Taiwan reader v3 development file as a case. Each nutrient becomes one row, in the
    /// order it first appears, labelled with its nutrient identifier (the format prints no label).
    /// A repeated nutrient and column, a value naming no column, or a file mixing string and
    /// number values is refused rather than guessed.
    public static func fromTaiwanLegacy(_ data: Data, metadata: Metadata) throws -> EvalCase {
        let t = try JSONDecoder().decode(TranscriptionShapes.TaiwanLegacyTranscription.self, from: data)
        let keys = t.columns.map(\.key)
        guard Set(keys).count == keys.count else { throw Refused("\(t.id): repeated column key") }
        var numbers = t.values.map(\.value)
        if let size = t.servingSize { numbers.append(size.value) }
        if let pack = t.servingsPerPack { numbers.append(pack.value) }
        let encodings = Set(numbers.map(\.isNumber))
        guard encodings.count <= 1 else { throw Refused("\(t.id): values mix JSON strings and numbers") }
        var order: [String] = []
        var extraValues: [String] = []
        var rows: [(nutrient: String, values: [TranscriptionShapes.Value?])] = []
        for value in t.values {
            guard let column = keys.firstIndex(of: value.column) else { throw Refused("\(t.id): value names unknown column \(value.column)") }
            let pair = value.nutrient + "@" + value.column
            guard !order.contains(pair) else { throw Refused("\(t.id): repeated value \(pair)") }
            // Only `extra: true` is seen; `false` would be a third state the case could not restore.
            guard value.extra != false else { throw Refused("\(t.id): \(pair) has extra false") }
            order.append(pair)
            if value.extra == true { extraValues.append(pair) }
            let index = rows.firstIndex { $0.nutrient == value.nutrient } ?? {
                rows.append((value.nutrient, Array(repeating: nil, count: keys.count)))
                return rows.count - 1
            }()
            rows[index].values[column] = TranscriptionShapes.Value(comparator: value.comparator, number: value.value.text, unit: value.unit)
        }
        let notesEncoding: String? = switch t.notes {
        case .text?: "text"
        case .list?: "list"
        case nil: nil
        }
        let extras = TranscriptionShapes.LegacyExtras(transcribedBy: t.transcribedBy, columnKeys: keys, valueOrder: order,
                                                      numberEncoding: encodings.first == true ? "number" : "string", notesEncoding: notesEncoding,
                                                      extraValues: extraValues.isEmpty ? nil : extraValues,
                                                      transcriptionCorrections: t.transcriptionCorrections)
        return try EvalCase(labelID: t.id, set: metadata.set, tier: metadata.tier, copyMethod: metadata.copyMethod, textSHA256: metadata.textSHA256,
                            expected: EvalCase.Expected(panel: nil,
                                                        servingSize: t.servingSize.map { .init(number: $0.value.text, unit: $0.unit) },
                                                        servingsPerPack: t.servingsPerPack.map { .init(number: $0.value.text, approximate: $0.approximate) },
                                                        columns: try t.columns.map { .init(heading: $0.printed, basis: try legacyBasis($0)) },
                                                        rows: rows.map { .init(label: $0.nutrient, nutrient: $0.nutrient, values: $0.values) },
                                                        notes: t.notes?.lines ?? []),
                            source: EvalCase.Source(schema: TranscriptionShapes.TaiwanLegacyTranscription.schema, sha256: EvalCase.sha256(data)),
                            legacy: extras)
    }

    /// The legacy transcription a case was converted from.
    public static func taiwanLegacyTranscription(_ evalCase: EvalCase) throws -> TranscriptionShapes.TaiwanLegacyTranscription {
        guard evalCase.source.schema == TranscriptionShapes.TaiwanLegacyTranscription.schema, let extras = evalCase.legacy else {
            throw Refused("\(evalCase.labelID) was not converted from the legacy schema")
        }
        let e = evalCase.expected
        func number(_ text: String) throws -> TranscriptionShapes.LegacyNumber {
            guard extras.numberEncoding == "number" else { return .string(text) }
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { throw Refused("\(evalCase.labelID): \(text) is not a number") }
            return .number(value)
        }
        var values: [TranscriptionShapes.TaiwanLegacyTranscription.Value] = []
        for pair in extras.valueOrder {
            let parts = pair.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2, let column = extras.columnKeys.firstIndex(of: parts[1]),
                  let row = e.rows.first(where: { $0.nutrient == parts[0] }), let value = row.values[column] else {
                throw Refused("\(evalCase.labelID): legacy value order names \(pair), which the case does not hold")
            }
            values.append(.init(nutrient: parts[0], column: parts[1], value: try number(value.number), unit: value.unit, comparator: value.comparator,
                                extra: extras.extraValues?.contains(pair) == true ? true : nil))
        }
        let notes: TranscriptionShapes.LegacyNotes? = switch extras.notesEncoding {
        case "text"?: .text(e.notes.first ?? "")
        case "list"?: .list(e.notes)
        default: nil
        }
        return TranscriptionShapes.TaiwanLegacyTranscription(
            columns: zip(extras.columnKeys, e.columns).map { .init(key: $0, printed: $1.heading) },
            servingSize: try e.servingSize.map { .init(value: try number($0.number), unit: $0.unit) },
            servingsPerPack: try e.servingsPerPack.map { .init(value: try number($0.number), approximate: $0.approximate) },
            values: values, notes: notes, id: evalCase.labelID, transcribedBy: extras.transcribedBy,
            transcriptionCorrections: extras.transcriptionCorrections)
    }
}
