import Foundation

/// What `PastedLabelAITextReading` returns (docs/pasted-label-ai-text-v1.md 4.2, 4.8, 5.2 item 2
/// and D19): the candidate the model's answer maps to, with every input the attention set needs,
/// and the outcome under the hard-decline rule.
///
/// - **Failed:** the answer is not a schema-valid text wire answer (nothing to show).
/// - **Declined:** a hard decline only (D19): the model declined, the panel detector declined the
///   text or the candidate, the inferred format is neither Taiwan nor a UK-format declaration,
///   gate G1 or G2, or a mapping that leaves no usable table (no amount value read).
/// - **Reached Confirm:** everything else. Gate findings G3 to G6 travel as flags and attention
///   inputs, exactly as in the product.
///
/// A wire value is either a cell of the candidate or not read; a value is never invented, and a
/// bare number with no unit stated is never a value (A1 finding F9). Each value carries its
/// locator status, its unit check outcome and its attention reasons
/// (`pasted-label-ai-text-attention-v1`, composing `label-photo-attention-v1`).
public struct PastedLabelAITextReadingResult: Equatable, Sendable {
    public enum Outcome: String, Equatable, Sendable, Codable, CaseIterable {
        case reachedConfirm = "reached_confirm", declined, failed
    }

    /// Why a wire value is not a cell. Never shown as zero: a not-read value is missing.
    public enum NotRead: String, Equatable, Sendable, Codable, CaseIterable {
        /// The model printed `unknown`.
        case unknown
        /// The printed text is not one value of the closed grammar.
        case unreadable
        /// A bare number with no unit from the model (F9): a not-read cell, never a value, under a
        /// blocking `unit_not_stated` item.
        case bareNumberWithoutUnit = "bare_number_without_unit"
        /// A bare number whose model unit is outside the closed unit table.
        case unitOutsideTable = "unit_outside_table"
        /// A thousands group led by `0` (`0,500g`, 4.3 item 2): ambiguous, so never 500 and never 0.5.
        case thousandsLedByZero = "thousands_led_by_zero"
        /// Its header ID is not one of the answer's headers.
        case undeclaredHeader = "undeclared_header"
        /// An absolute amount in a reference-intake column (photo amendment M1).
        case absoluteReferenceValue = "absolute_reference_value"
        /// A second value for the same row and header.
        case duplicateCell = "duplicate_cell"
    }

    public enum Read: Equatable, Sendable {
        /// The candidate cell with this row ID under the value's header.
        case cell(rowID: String)
        case notRead(NotRead)

        public var rowID: String? { if case let .cell(rowID) = self { rowID } else { nil } }
    }

    public struct Value: Equatable, Sendable {
        public let rowIndex: Int
        public let valueIndex: Int
        public let nutrient: String
        public let printedLabel: String
        public let headerID: String
        /// The header's basis, nil for an undeclared header.
        public let basis: String?
        public let printedText: String
        public let modelUnit: String?
        public let read: Read
        public let locator: PastedLabelTextLocator.Status
        public let unitCheck: PastedLabelAITextUnitCheck.Outcome
        /// The value's attention reasons, in `Reason` order. Non-empty blocks Log until resolved.
        public let reasons: [PastedLabelAITextAttention.Reason]

        public init(rowIndex: Int, valueIndex: Int, nutrient: String, printedLabel: String, headerID: String, basis: String?, printedText: String,
                    modelUnit: String?, read: Read, locator: PastedLabelTextLocator.Status, unitCheck: PastedLabelAITextUnitCheck.Outcome,
                    reasons: [PastedLabelAITextAttention.Reason]) {
            self.rowIndex = rowIndex; self.valueIndex = valueIndex; self.nutrient = nutrient; self.printedLabel = printedLabel
            self.headerID = headerID; self.basis = basis; self.printedText = printedText; self.modelUnit = modelUnit; self.read = read
            self.locator = locator; self.unitCheck = unitCheck; self.reasons = reasons
        }

        public var needsAttention: Bool { !reasons.isEmpty }
    }

    /// A serving line (`serving_size`, `servings_per_pack`) and where its printed text was found.
    public struct ServingLine: Equatable, Sendable {
        public let id: String
        public let printedText: String
        public let location: LabelPhotoAttention.Location
        public init(id: String, printedText: String, location: LabelPhotoAttention.Location) {
            self.id = id; self.printedText = printedText; self.location = location
        }
    }

    public struct Versions: Equatable, Sendable {
        public let wireSchema: String
        public let mapping: String
        public let locator: String
        public let vocabulary: String
        public let detector: String
        public let attention: String
        public let gate: String
        public let arithmetic: String
        public let conversion: String

        public init(wireSchema: String, mapping: String, locator: String, vocabulary: String, detector: String, attention: String, gate: String,
                    arithmetic: String, conversion: String) {
            self.wireSchema = wireSchema; self.mapping = mapping; self.locator = locator; self.vocabulary = vocabulary
            self.detector = detector; self.attention = attention; self.gate = gate; self.arithmetic = arithmetic; self.conversion = conversion
        }
    }

    public let outcome: Outcome
    /// Why the read failed (`unreadable_answer`, `text_too_long`), nil otherwise.
    public let failure: String?
    /// The hard-decline codes, in the order found; empty unless declined.
    public let declineReasons: [String]
    public let textSHA256: String
    /// `taiwan_nutrition_labelling`, `uk_nutrition_declaration`, or another inference outcome.
    public let inferredFormat: String?
    /// The mapped candidate (never the gate's withheld copy), nil when the read failed.
    public let candidate: PastedLabelManifest.Candidate?
    public let gate: LabelReading.Gate?
    public let checks: [LabelReading.Check]
    public let conversions: [PastedLabelManifest.Conversion]
    public let storedHeaderID: String?
    /// The detector on the text before sending, and again on the candidate.
    public let textDetector: PastedLabelAITextPanelDetector.Verdict
    public let candidateDetector: PastedLabelAITextPanelDetector.Verdict?
    public let values: [Value]
    public let servingLines: [ServingLine]
    /// Attention items on the serving lines (`serving_size`, `servings_per_pack`).
    public let servingAttention: [String: [PastedLabelAITextAttention.Reason]]
    public let versions: Versions

    public init(outcome: Outcome, failure: String?, declineReasons: [String], textSHA256: String, inferredFormat: String?,
                candidate: PastedLabelManifest.Candidate?, gate: LabelReading.Gate?, checks: [LabelReading.Check],
                conversions: [PastedLabelManifest.Conversion], storedHeaderID: String?, textDetector: PastedLabelAITextPanelDetector.Verdict,
                candidateDetector: PastedLabelAITextPanelDetector.Verdict?, values: [Value], servingLines: [ServingLine],
                servingAttention: [String: [PastedLabelAITextAttention.Reason]], versions: Versions) {
        self.outcome = outcome; self.failure = failure; self.declineReasons = declineReasons; self.textSHA256 = textSHA256
        self.inferredFormat = inferredFormat; self.candidate = candidate; self.gate = gate; self.checks = checks
        self.conversions = conversions; self.storedHeaderID = storedHeaderID; self.textDetector = textDetector
        self.candidateDetector = candidateDetector; self.values = values; self.servingLines = servingLines
        self.servingAttention = servingAttention; self.versions = versions
    }

    /// The values that became cells.
    public var cellValues: [Value] { values.filter { $0.read.rowID != nil } }

    /// Attention items over every value (a cell, or a not-read value the user must enter, such as
    /// `0,500g`) and serving line: the burden on the user at Confirm.
    public var attentionItemCount: Int {
        values.filter(\.needsAttention).count + servingAttention.values.filter { !$0.isEmpty }.count
    }
}
