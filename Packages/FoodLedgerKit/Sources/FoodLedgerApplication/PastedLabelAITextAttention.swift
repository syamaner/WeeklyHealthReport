import Foundation

/// The reasons of `pasted-label-ai-text-attention-v1` (docs/pasted-label-ai-text-v1.md 4.2 and
/// 4.8): every `label-photo-attention-v1` reason, carried across unchanged with its raw value,
/// plus the text route's `unit_not_stated`, `vocabulary_mismatch` and `label_unknown`. Each is an
/// attention item that blocks Log until resolved (photo decision P12).
///
/// The text checks map onto them as follows:
/// - a locator value not found is `not_found`; a value found more than once is `ambiguous`, and
///   so is a found value whose place is not certain (its row label not located, its header
///   unknown or not located, or its block holding fewer or more cells than headers);
/// - a unit check outcome that needs attention is `unit_not_stated`;
/// - a vocabulary verdict is `vocabulary_mismatch` or `label_unknown`.
///
/// The composition of the full attention set (gate flags and failed checks over the stored cells
/// and serving lines) is written with the text manifest in A5, from the attention inputs it
/// stores; it composes `LabelPhotoAttention.items` and adds these reasons.
public enum PastedLabelAITextAttention {
    public static let version = "pasted-label-ai-text-attention-v1"
    /// The photo attention version this one composes.
    public static let composedVersion = LabelPhotoAttention.version

    /// In the order they are listed on an item: the v1 reasons first, in v1 order.
    public enum Reason: String, Equatable, Sendable, Codable, CaseIterable {
        case notFound = "not_found"
        case ambiguous
        case gateFlag = "gate_flag"
        case checkFailed = "check_failed"
        case unitNotStated = "unit_not_stated"
        case vocabularyMismatch = "vocabulary_mismatch"
        case labelUnknown = "label_unknown"

        /// A v1 reason, unchanged.
        public init(_ reason: LabelPhotoAttention.Reason) {
            switch reason {
            case .notFound: self = .notFound
            case .ambiguous: self = .ambiguous
            case .gateFlag: self = .gateFlag
            case .checkFailed: self = .checkFailed
            }
        }
    }

    /// The locator's reason for one value, if any.
    public static func reason(_ value: PastedLabelTextLocator.ValueResult) -> Reason? {
        switch value.status {
        case .notFound: .notFound
        case .ambiguous: .ambiguous
        case .found: value.attention.isEmpty ? nil : .ambiguous
        }
    }

    public static func reason(_ outcome: PastedLabelAITextUnitCheck.Outcome) -> Reason? {
        outcome.needsAttention ? .unitNotStated : nil
    }

    public static func reason(_ verdict: PastedLabelAITextVocabulary.Verdict) -> Reason? {
        switch verdict {
        case .agrees: nil
        case .mismatch: .vocabularyMismatch
        case .unknown: .labelUnknown
        }
    }

    /// Reasons in `Reason` order, without repeats.
    public static func ordered(_ reasons: [Reason]) -> [Reason] { Reason.allCases.filter(reasons.contains) }
}
