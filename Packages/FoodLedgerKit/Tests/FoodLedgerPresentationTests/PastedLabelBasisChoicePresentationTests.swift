import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// Reader v3 section 8.4 (PR 4) in presentation: the basis sheet's lifecycle on the label text
/// screen and Confirm (8.4.9), one basis origin and formatter across Confirm, the saved entry,
/// the misread report and Developer tools (8.4.11, decision 24), G5 under a chosen basis and a
/// header with empty printed text. Contract tests 13, 15 and 24 of 8.4.15. Synthetic readings.
@MainActor
final class PastedLabelBasisChoicePresentationTests: XCTestCase {
    private typealias F = LabelFixtures

    // MARK: Fixtures: an unheaded one-column table and its asserted readings

    nonisolated private static let text = "營養標示\n每一份量30公克\n本包裝含8份\n熱量 120大卡(每100毫升)\n蛋白質 3.0公克\n脂肪 4.5公克\n碳水化合物 18.0公克\n鈉 60毫克\n"
    nonisolated private static let hint = "basis_hint: energy_line: (每100毫升)"
    nonisolated private static let serving = PastedLabelManifest.Candidate.ServingSize(printedText: "每一份量30公克", decimalText: "30", unit: "公克",
                                                                           canonicalUnit: "g")

    nonisolated private static func asserted(_ basis: String) -> LabelReading {
        let cells = [("熱量", "energy_kcal", "120", "大卡", "kcal"), ("蛋白質", "protein", "3.0", "公克", "g"), ("脂肪", "fat", "4.5", "公克", "g"),
                     ("碳水化合物", "carbohydrate", "18.0", "公克", "g"), ("鈉", "sodium", "60", "毫克", "mg")].map {
            PastedLabelManifest.Candidate.Cell(rowID: $0.1, parentRowID: nil, nutrient: $0.1, printedLabel: $0.0, headerID: "header_1", basis: basis,
                printedText: $0.2 + $0.3, comparator: "=", decimalText: $0.2, unit: $0.3, canonicalUnit: $0.4,
                servingConversion: basis == "per_serving" ? "30公克" : "not_applicable")
        }
        let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: F.hash(text), declined: false, declineReasons: [], wouldMarkReady: false,
            language: "zh-Hant", servingSize: serving, servingsPerPack: .init(printedText: "本包裝含8份", decimalText: "8", approximate: false),
            headers: [.init(headerID: "header_1", printedText: "", basis: basis, servingConversion: nil)], cells: cells, warnings: [hint])
        let flags: [LabelReading.Flag] = basis == "per_serving" ? [.init(code: "required_basis_missing", concerns: "per_100")] : []
        let versions = LabelReading.Versions(parser: PastedLabelSource.parserVersionV3, gate: PastedLabelSource.gateVersion,
            arithmetic: PastedLabelSource.arithmeticVersionV2, conversion: PastedLabelSource.conversionVersion,
            formatInference: "pasted-label-format-inference-v1")
        return LabelReading(origin: .pastedText, textSHA256: F.hash(text), candidate: candidate, format: "taiwan_nutrition_labelling",
            gate: .init(format: "taiwan_nutrition_labelling", skipped: nil, hardDeclines: [], flags: flags), checks: [], conversions: [],
            storedHeaderID: "header_1", versions: versions)
    }

    nonisolated private static func declined() -> LabelReading {
        let candidate = PastedLabelManifest.Candidate(route: "A", inputSHA256: F.hash(text), declined: true, declineReasons: ["no_basis_header"],
            wouldMarkReady: false, language: "zh-Hant", servingSize: nil, servingsPerPack: nil, headers: [], cells: [], warnings: [hint])
        return LabelReading(origin: .pastedText, textSHA256: F.hash(text), candidate: candidate, format: "taiwan_nutrition_labelling",
            gate: nil, checks: [], conversions: [], storedHeaderID: nil, versions: F.versions,
            unheadedTable: UnheadedTable(amountColumnCount: 1, referenceColumnPrinted: false, servingSize: serving,
                                         servingsPerPack: .init(printedText: "本包裝含8份", decimalText: "8", approximate: false),
                                         energyLineHint: .init(printedText: "(每100毫升)", basis: .per100ml)))
    }

    private final class Reader: LabelTextReading, @unchecked Sendable {
        private let lock = NSLock()
        private var _reads = 0
        var reads: Int { lock.withLock { _reads } }
        func read(_ text: String, textSHA256: String, assertedBases: AssertedBases?) -> LabelReading {
            lock.withLock { _reads += 1 }
            guard let assertedBases else { return PastedLabelBasisChoicePresentationTests.declined() }
            return PastedLabelBasisChoicePresentationTests.asserted(assertedBases.columns[0].rawValue)
        }
    }

    private var lines: [String] = []

    private func model() -> PastedLabelTextViewModel {
        let reader = PastedLabelReader(reader: Reader(), digester: SHA256Digester())
        let builder = F.builder()
        let model = PastedLabelTextViewModel(read: { reader.read($0) }, makeConfirm: { review, details in
            try PastedLabelSourceModel(review: review, details: details, builder: builder, locale: F.locale)
        }, choose: { try builder.choose($0, in: $1) }, recordDiagnostics: { [weak self] in self?.lines = $0 })
        model.name = "Synthetic chosen biscuits"
        model.fortification = .no
        model.text = Self.text
        return model
    }

    private func arrangement(_ id: String) -> PastedLabelBasisOptions.Arrangement { PastedLabelBasisOptions.Arrangement(identifier: id)! }

    // MARK: 15. The lifecycle (8.4.9)

    func test15TheSheetFollowsReadLabelAndAChoiceOpensConfirm() throws {
        let model = model()
        XCTAssertNil(model.readLabel(), "the sheet first, never Confirm")
        let sheet = try XCTUnwrap(model.basisSheet)
        XCTAssertFalse(sheet.fromChange)
        XCTAssertNil(sheet.current, "nothing preselected")
        XCTAssertEqual(model.basisOptions.map(\.title), ["Per serving (30 g)", "Per 100 g", "Per 100 mL"])
        XCTAssertTrue(model.basisOptions.allSatisfy { !$0.isCurrent })
        XCTAssertEqual(model.basisHint, "The label’s energy line says 每100毫升.")
        XCTAssertFalse(model.perServingUnavailable)
        XCTAssertNil(model.confirm)
        XCTAssertEqual(lines, ["Pasted label needs a basis choice: offered per_serving | per_100g | per_100ml"])
        let confirm = try XCTUnwrap(model.chooseBasis(arrangement("per_100g")))
        XCTAssertNil(model.basisSheet)
        XCTAssertEqual(confirm.basisLine, "per 100 g · Chosen by you")
        XCTAssertEqual(confirm.basisHintNote, "The label’s energy line says 每100毫升.", "decision 24: the hint differs")
        XCTAssertTrue(confirm.canChangeBasis)
        XCTAssertTrue(lines.contains("Basis: per 100 g · Chosen by you The label’s energy line says 每100毫升."), "\(lines)")
        XCTAssertFalse(confirm.warnings.contains { $0.contains("energy line") }, "the hint is on the basis line, not in the warnings")
        // Return to Confirm with unchanged text keeps the choice.
        XCTAssertTrue(model.canReturnToConfirm)
        XCTAssertTrue(model.returnToConfirm() === confirm)
        XCTAssertEqual(confirm.currentArrangement, arrangement("per_100g"))
    }

    func test15EditedTextOrReadAgainClearsTheChoiceAndShowsTheSheetAgain() throws {
        let model = model()
        model.readLabel()
        let confirm = try XCTUnwrap(model.chooseBasis(arrangement("per_100g")))
        model.text += "\n"
        XCTAssertFalse(model.canReturnToConfirm, "edited text")
        XCTAssertNil(model.readLabel())
        XCTAssertNotNil(model.basisSheet, "the sheet again")
        XCTAssertNil(model.confirm, "the choice is cleared")
        // Read again on unchanged text with corrections asks first, then shows the sheet again.
        model.text = Self.text
        model.readLabel()
        let again = try XCTUnwrap(model.chooseBasis(arrangement("per_100g")))
        XCTAssertFalse(again === confirm)
        XCTAssertNil(again.setValue("protein", text: "3.5", unit: "g"))
        XCTAssertNil(model.readLabel())
        XCTAssertTrue(model.asksToReplaceCorrections)
        XCTAssertNil(model.confirmReadAgain())
        XCTAssertNotNil(model.basisSheet)
        XCTAssertNil(model.confirm)
    }

    func test15DismissingOrNotSureAfterReadLabelWritesNothingAndKeepsTheText() throws {
        let model = model()
        model.readLabel()
        model.basisSheetDismissed()
        XCTAssertNil(model.basisSheet)
        XCTAssertNil(model.confirm)
        XCTAssertEqual(model.text, Self.text)
        model.readLabel()
        XCTAssertFalse(model.basisNotSure(), "Confirm is not open")
        XCTAssertNil(model.confirm)
        XCTAssertEqual(model.text, Self.text)
    }

    // MARK: 24. Change on Confirm

    func test24ChangeLabelsTheCurrentChoiceAndAsksBeforeClearingCorrections() throws {
        let model = model()
        model.readLabel()
        let confirm = try XCTUnwrap(model.chooseBasis(arrangement("per_100g")))
        confirm.changeBasis?()
        let sheet = try XCTUnwrap(model.basisSheet)
        XCTAssertTrue(sheet.fromChange)
        XCTAssertEqual(model.basisOptions.filter(\.isCurrent).map(\.id), ["per_100g"], "labelled, not selected")
        // The current arrangement again changes nothing.
        XCTAssertNil(model.chooseBasis(arrangement("per_100g")))
        XCTAssertNil(model.basisSheet)
        XCTAssertTrue(model.confirm === confirm)
        // Dismissing keeps the choice and stays on Confirm.
        confirm.changeBasis?()
        model.basisSheetDismissed()
        XCTAssertTrue(model.confirm === confirm)
        XCTAssertEqual(confirm.currentArrangement, arrangement("per_100g"))
        // With corrections, another arrangement asks first; Cancel keeps everything.
        XCTAssertNil(confirm.setValue("protein", text: "3.5", unit: "g"))
        confirm.changeBasis?()
        XCTAssertNil(model.chooseBasis(arrangement("per_serving")))
        XCTAssertTrue(model.asksToReplaceCorrectionsOnBasisChange)
        model.cancelBasisChange()
        XCTAssertTrue(confirm.hasCorrections)
        XCTAssertEqual(confirm.currentArrangement, arrangement("per_100g"))
        // Change and replace: the same Confirm (amount and time stay), the new basis, no corrections.
        XCTAssertNil(model.chooseBasis(arrangement("per_serving")))
        XCTAssertTrue(try XCTUnwrap(model.confirmBasisChange()) === confirm)
        XCTAssertEqual(confirm.currentArrangement, arrangement("per_serving"))
        XCTAssertFalse(confirm.hasCorrections)
        XCTAssertEqual(confirm.basisLine, "per serving · Chosen by you")
        // G5 under a chosen basis names the basis by its label.
        XCTAssertEqual(confirm.basisFlag, "Only per serving values; the label does not print per 100 g.")
    }

    func test24NotSureFromChangeDropsConfirmAndKeepsTheText() throws {
        let model = model()
        model.readLabel()
        let confirm = try XCTUnwrap(model.chooseBasis(arrangement("per_100ml")))
        XCTAssertNil(confirm.basisHintNote, "the hint agrees: no note")
        confirm.changeBasis?()
        XCTAssertTrue(model.basisNotSure(), "Confirm closes")
        XCTAssertNil(model.confirm)
        XCTAssertNil(model.basisSheet)
        XCTAssertEqual(model.text, Self.text)
        XCTAssertFalse(model.canReturnToConfirm)
    }

    // MARK: 13. One basis origin and formatter across surfaces

    func test13ConfirmTheSavedEntryTheReportAndDeveloperToolsShowTheSameBasisLine() throws {
        let model = model()
        model.readLabel()
        let source = try XCTUnwrap(model.chooseBasis(arrangement("per_100g")))
        let (confirm, _) = try F.confirm(source)
        confirm.send(.setQuantity(40, .grams))
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult, confirm.blockedReason ?? "")
        let detail = SavedFoodEntryDetail(stored: saved, isEstimate: false, history: [])
        let line = "per 100 g · Chosen by you"
        XCTAssertEqual(source.sourceLine, "From pasted label · \(line) · Traditional Chinese, Taiwan layout")
        XCTAssertEqual(PastedLabelSavedEntryText.sourceLine(detail), source.sourceLine)
        XCTAssertEqual(PastedLabelSavedEntryText.basisHintNote(detail), source.basisHintNote)
        let stored = PastedLabelSourceModel(stored: try XCTUnwrap(detail.pastedLabel), nutrients: saved.resolutionVersion.nutrients)
        XCTAssertEqual(stored.sourceLine, source.sourceLine)
        XCTAssertEqual(stored.basisHintNote, source.basisHintNote)
        let report = try XCTUnwrap(PastedLabelSavedEntryText.reportText(detail))
        XCTAssertTrue(report.contains("Basis: \(line) The label’s energy line says 每100毫升."), report)
        XCTAssertTrue(source.reportText.contains("Basis: \(line)"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("Basis: \(line)") })
        // Chosen-basis values keep their printed origin.
        XCTAssertEqual(source.rows.first { $0.id == "protein" }?.origin, .printed)
        // A printed basis shows no "Chosen by you" anywhere.
        XCTAssertEqual(PastedLabelText.basisLine(basis: "per_100g", origin: .printed), "per 100 g")
        XCTAssertNil(PastedLabelText.basisHintNote(.printed))
    }

    // MARK: Empty header text is named by its basis label

    func testAnEmptyTextHeaderIsNamedByItsBasisLabel() {
        let headers: [PastedLabelManifest.Candidate.Header] = [.init(headerID: "header_1", printedText: "", basis: "per_serving", servingConversion: nil)]
        XCTAssertEqual(PastedLabelText.flagMessage(.init(code: "required_basis_missing", concerns: "per_100"), headers: headers),
                       "Only per serving values; the label does not print per 100 g.")
        XCTAssertEqual(PastedLabelText.flagMessage(.init(code: "required_basis_missing", concerns: "per_100"), headers: []),
                       "No per 100 g or per 100 ml values were read.")
        XCTAssertEqual(PastedLabelText.flagMessage(.init(code: "column_count_mismatch", concerns: "sodium@header_1"), headers: headers),
                       "Not read: sodium, per serving. Add it, or leave it unknown.")
        XCTAssertEqual(PastedLabelText.basisOptionTitle(.init([.perServing, .per100ml]), servingSize: Self.serving), "Per serving (30 g), then per 100 mL")
        XCTAssertEqual(PastedLabelText.warningMessage("basis_plausibility:per_100g:macronutrients"), PastedLabelText.plausibilityMacronutrients)
        XCTAssertEqual(PastedLabelText.warningMessage("basis_plausibility:per_100g:energy"), PastedLabelText.plausibilityEnergy)
    }
}
