import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import NutritionLabelParsing
import UKNutritionLabelParsing

/// The UK English adapter for the `LabelTextReading` port (`docs/pasted-nutrition-label-uk-english-v1-p2.md`
/// section 1; parser `nutrition-label-text-parser-uk-v3` from `docs/pasted-nutrition-label-uk-english-v2-p1.md`). A text parser v3 reads as `english` goes through `NutritionLabelTextParserUK`, and
/// its reading records that parser's version; every other text goes to the pinned
/// `NutritionLabelTextReader`, whose reading is returned unchanged. The gate, inference, checks
/// and conversions steps repeat `NutritionLabelTextReader.read` with the UK parser, held together
/// by equality tests. Used by the UK development harness only until P5; not wired at the
/// composition root.
public struct UKEnglishLabelTextReader: LabelTextReading {
    private let pinned = NutritionLabelTextReader()
    private let languageProbe = NutritionLabelTextParserV3()
    private let parser = NutritionLabelTextParserUK()

    public init() {}

    public static let versions = LabelReading.Versions(parser: NutritionLabelTextParserUK.version, gate: LabelDeclineGate.version,
        arithmetic: LabelArithmeticChecks.version, conversion: PastedLabelConversions.version,
        formatInference: LabelFormatInference.version)
    public static let assertedVersions = LabelReading.Versions(parser: NutritionLabelTextParserUK.version, gate: LabelDeclineGate.version,
        arithmetic: LabelArithmeticChecksV2.version, conversion: PastedLabelConversions.version,
        formatInference: LabelFormatInference.version)

    public func read(_ text: String, textSHA256: String, assertedBases: AssertedBases?) -> LabelReading {
        // The same language the UK normaliser checks: parser v3 folds line endings and no-break
        // spaces before deciding the language, so the raw and folded text cannot disagree.
        guard languageProbe.parse(text, route: "A", inputSHA256: textSHA256).language == .english else {
            return pinned.read(text, textSHA256: textSHA256, assertedBases: assertedBases)
        }
        let candidate: LabelCaptureCandidate
        var unheaded: UnheadedTable?
        if let assertedBases {
            candidate = parser.parse(text, route: "A", inputSHA256: textSHA256,
                                     assertedBases: assertedBases.columns.map(NutritionLabelTextReader.basis))
        } else {
            candidate = parser.parse(text, route: "A", inputSHA256: textSHA256)
            if candidate.declineReasons == ["no_basis_header"] {
                unheaded = parser.unheadedShape(text, route: "A", inputSHA256: textSHA256).map(NutritionLabelTextReader.unheadedTable)
            }
        }
        let format = LabelFormatInference.infer(candidate)
        var gate: LabelReading.Gate?
        var checks: [LabelReading.Check] = []
        var conversions: [PastedLabelManifest.Conversion] = []
        let storedHeaderID = candidate.declined ? nil : PastedLabelStoredColumn.headerID(for: candidate)
        if !candidate.declined, let gateFormat = format.gateFormat {
            let report = LabelDeclineGate.apply(candidate, format: gateFormat).report
            gate = LabelReading.Gate(format: gateFormat.rawValue, skipped: report.skipped?.rawValue,
                                     hardDeclines: report.hardDeclineCodes, flags: NutritionLabelTextReader.flags(report, candidate: candidate))
            let table = LabelArithmeticTable(candidate, format: gateFormat)
            if assertedBases != nil {
                let amountBases = candidate.headers.filter { $0.basis != .referenceIntake }.map(\.basis.rawValue)
                checks = LabelArithmeticChecksV2.check(table, amountBases: amountBases).checks.map(NutritionLabelTextReader.check)
            } else {
                checks = LabelArithmeticChecks.check(table).checks.map(NutritionLabelTextReader.check)
            }
        }
        if let storedHeaderID {
            conversions = PastedLabelConversions.conversions(for: candidate, storedHeaderID: storedHeaderID)
                .map { NutritionLabelTextReader.conversion($0.record) }
        }
        return LabelReading(origin: .pastedText, textSHA256: textSHA256, candidate: NutritionLabelTextReader.candidate(candidate),
                            format: format.rawValue, gate: gate, checks: checks, conversions: conversions, storedHeaderID: storedHeaderID,
                            versions: assertedBases == nil ? Self.versions : Self.assertedVersions, unheadedTable: unheaded)
    }

    /// What the UK region stage set aside from `text`, beside the reading (never inside the pinned
    /// `LabelReading`); empty for a text that is not English. For the harness and, from P5,
    /// Developer tools (`docs/pasted-nutrition-label-uk-english-v2-p1.md` section 2).
    public func setAside(_ text: String) -> [UKSetAsideRecord] {
        parser.setAside(text).map { UKSetAsideRecord(rule: $0.rule.rawValue, line: $0.line, cell: $0.cell, text: $0.text) }
    }
}

/// One line or tab cell the UK reader set aside, as a plain value of `FoodLabelTextCapture`, so no
/// caller outside it depends on the UK parsing target.
public struct UKSetAsideRecord: Codable, Equatable, Sendable {
    /// The schema of a set-aside file: `{schema, label_id, entries}` with these records as entries.
    public static let fileSchema = "uk-set-aside-v1"

    public let rule: String
    public let line: Int
    public let cell: Int?
    public let text: String

    public init(rule: String, line: Int, cell: Int?, text: String) {
        self.rule = rule; self.line = line; self.cell = cell; self.text = text
    }
}
