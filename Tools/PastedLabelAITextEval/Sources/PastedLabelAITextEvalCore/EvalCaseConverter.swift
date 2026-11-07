import Foundation

/// The converters of docs/pasted-label-ai-text-v1.md 5.1: the Taiwan reader v3 transcription
/// schema and the UK transcription schema into `pasted-label-ai-text-eval-case-v1`, and back. The
/// existing data is never edited: a converter reads a transcription's bytes and records their
/// SHA-256 as the case's source. The collection metadata (tier, copy method, text hash) comes from
/// each label's collection record, which the caller reads.
public enum EvalCaseConverter {
    public struct Metadata: Equatable, Sendable {
        public let set: EvalCase.EvalSet
        public let tier: String?
        public let copyMethod: String
        public let textSHA256: String
        public init(set: EvalCase.EvalSet, tier: String?, copyMethod: String, textSHA256: String) {
            self.set = set; self.tier = tier; self.copyMethod = copyMethod; self.textSHA256 = textSHA256
        }
    }

    public struct Refused: Error, CustomStringConvertible, Equatable {
        public let description: String
        init(_ description: String) { self.description = description }
    }

    /// A `reader-v3-fresh-transcription-v1` file as a case.
    public static func fromTaiwan(_ data: Data, metadata: Metadata) throws -> EvalCase {
        let t = try JSONDecoder().decode(TranscriptionShapes.TaiwanTranscription.self, from: data)
        guard t.schema == TranscriptionShapes.TaiwanTranscription.schema else {
            throw Refused("schema \(t.schema) is not \(TranscriptionShapes.TaiwanTranscription.schema)")
        }
        return try EvalCase(labelID: t.labelID, set: metadata.set, tier: metadata.tier, copyMethod: metadata.copyMethod,
                            textSHA256: metadata.textSHA256,
                            expected: EvalCase.Expected(panel: nil, servingSize: t.servingSize, servingsPerPack: t.servingsPerPack,
                                                        columns: t.columns, rows: t.rows, notes: t.notes),
                            source: EvalCase.Source(schema: t.schema, sha256: EvalCase.sha256(data)))
    }

    /// A `uk-english-v1-fresh-transcription-v1` file as a case.
    public static func fromUK(_ data: Data, metadata: Metadata) throws -> EvalCase {
        let t = try JSONDecoder().decode(TranscriptionShapes.UKTranscription.self, from: data)
        guard t.schema == TranscriptionShapes.UKTranscription.schema else {
            throw Refused("schema \(t.schema) is not \(TranscriptionShapes.UKTranscription.schema)")
        }
        return try EvalCase(labelID: t.labelID, set: metadata.set, tier: metadata.tier, copyMethod: metadata.copyMethod,
                            textSHA256: metadata.textSHA256,
                            expected: EvalCase.Expected(panel: t.panel, servingSize: t.servingSize, servingsPerPack: t.servingsPerPack,
                                                        columns: t.columns, rows: t.rows, notes: t.notes),
                            source: EvalCase.Source(schema: t.schema, sha256: EvalCase.sha256(data)))
    }

    /// A transcription in either schema, chosen by its `schema` member.
    public static func convert(_ data: Data, metadata: Metadata) throws -> EvalCase {
        struct SchemaOnly: Decodable { let schema: String }
        switch try JSONDecoder().decode(SchemaOnly.self, from: data).schema {
        case TranscriptionShapes.TaiwanTranscription.schema: return try fromTaiwan(data, metadata: metadata)
        case TranscriptionShapes.UKTranscription.schema: return try fromUK(data, metadata: metadata)
        case let other: throw Refused("schema \(other) has no converter")
        }
    }

    /// The Taiwan-schema transcription a case was converted from.
    public static func taiwanTranscription(_ evalCase: EvalCase) throws -> TranscriptionShapes.TaiwanTranscription {
        guard evalCase.source.schema == TranscriptionShapes.TaiwanTranscription.schema else {
            throw Refused("\(evalCase.labelID) was not converted from the Taiwan schema")
        }
        let e = evalCase.expected
        return TranscriptionShapes.TaiwanTranscription(schema: evalCase.source.schema, labelID: evalCase.labelID, servingSize: e.servingSize,
                                                       servingsPerPack: e.servingsPerPack, columns: e.columns, rows: e.rows, notes: e.notes)
    }

    /// The UK-schema transcription a case was converted from.
    public static func ukTranscription(_ evalCase: EvalCase) throws -> TranscriptionShapes.UKTranscription {
        guard evalCase.source.schema == TranscriptionShapes.UKTranscription.schema, let panel = evalCase.expected.panel else {
            throw Refused("\(evalCase.labelID) was not converted from the UK schema")
        }
        let e = evalCase.expected
        return TranscriptionShapes.UKTranscription(schema: evalCase.source.schema, labelID: evalCase.labelID, panel: panel, servingSize: e.servingSize,
                                                   servingsPerPack: e.servingsPerPack, columns: e.columns, rows: e.rows, notes: e.notes)
    }
}
