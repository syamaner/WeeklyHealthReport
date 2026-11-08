import Foundation

/// `PastedLabelAITextEval convert` and `convert-legacy` (docs/pasted-label-ai-text-v1.md 5.1, A3 of
/// #416): one transcription into one tuning case, as canonical JSON. The options are checked here,
/// so the CLI only reads files and prints. Only tuning sets are converted: `uk_v2_fresh` is the
/// sealed held-out set (D4) and is refused before its data is looked at. Every case is round-trip
/// checked against the bytes it came from before it is returned.
public enum ConvertCommand {
    public struct Failure: Error, CustomStringConvertible, Equatable {
        public let description: String
        init(_ description: String) { self.description = description }
    }

    public struct Options: Equatable, Sendable {
        /// `nil` for `convert-legacy`, whose set is always `taiwan_v3_development`.
        public let set: String?
        public let tier: String?
        public let copyMethod: String
        public let textSHA256: String
        public let layoutShape: String?
        /// The case ID to name the case by, in place of the transcription's own label ID.
        public let labelID: String?

        public init(set: String?, tier: String?, copyMethod: String, textSHA256: String, layoutShape: String?, labelID: String?) {
            self.set = set; self.tier = tier; self.copyMethod = copyMethod; self.textSHA256 = textSHA256
            self.layoutShape = layoutShape; self.labelID = labelID
        }
    }

    /// The label ID rule the promptfoo provider and assertion apply before naming a file.
    public static func isSafeLabelID(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix(".")
            && id.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || "._-".unicodeScalars.contains($0) }
    }

    /// `convert`: the set is named, and the converter is chosen by the file's `schema`.
    public static func convert(_ data: Data, _ options: Options) throws -> EvalCase {
        guard let raw = options.set else { throw Failure("convert needs --set") }
        guard raw != EvalCase.EvalSet.ukV2Fresh.rawValue else {
            throw Failure("uk_v2_fresh is the sealed held-out set (D4); it is never converted here")
        }
        guard let set = EvalCase.EvalSet(rawValue: raw), set.role == .tuning else {
            throw Failure("unknown set \(raw); the tuning sets are \(EvalCase.EvalSet.allCases.filter { $0.role == .tuning }.map(\.rawValue))")
        }
        return try finish(try EvalCaseConverter.convert(data, metadata: metadata(set, options)), data, options)
    }

    /// `convert-legacy`: the Taiwan reader v3 development set's older answer format.
    public static func convertLegacy(_ data: Data, _ options: Options) throws -> EvalCase {
        guard options.set == nil, options.tier == nil else { throw Failure("convert-legacy takes no --set or --tier") }
        return try finish(try EvalCaseConverter.fromTaiwanLegacy(data, metadata: metadata(.taiwanV3Development, options)), data, options)
    }

    static func metadata(_ set: EvalCase.EvalSet, _ options: Options) -> EvalCaseConverter.Metadata {
        .init(set: set, tier: options.tier, copyMethod: options.copyMethod, textSHA256: options.textSHA256)
    }

    static func finish(_ converted: EvalCase, _ data: Data, _ options: Options) throws -> EvalCase {
        let shape: EvalCase.LayoutShape? = try options.layoutShape.map {
            guard let shape = EvalCase.LayoutShape(rawValue: $0) else {
                throw Failure("unknown layout shape \($0); the closed set is \(EvalCase.LayoutShape.allCases.map(\.rawValue))")
            }
            return shape
        }
        if let id = options.labelID, !isSafeLabelID(id) { throw Failure("label ID \(id) does not match ^[A-Za-z0-9._-]+$ or starts with a dot") }
        let evalCase = try converted.with(labelID: options.labelID, layoutShape: shape)
        guard evalCase.role == .tuning else { throw Failure("\(evalCase.labelID): only tuning cases are converted") }
        try EvalCaseConverter.verifyRoundTrip(evalCase, source: data)
        return evalCase
    }
}
