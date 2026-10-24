import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

/// Pasted label Confirm v1 (#306, `docs/pasted-label-confirm-v1.md` sections 4, 8.1 and 8.5,
/// tests 10, 14, 18 and C12) in presentation: the answer is asked once on Confirm, survives every
/// rebuild of the same reading, and only an editable source sets the flag. Synthetic readings.
@MainActor
final class PastedLabelConfirmV1PresentationTests: XCTestCase {
    private typealias F = LabelFixtures
    private static let unanswered = PastedLabelDetails(name: "Synthetic oat crackers", brand: "Synthetic Mill")

    private func confirm() throws -> (FoodConfirmationViewModel, PastedLabelSourceModel) {
        let source = try F.source(details: Self.unanswered)
        let (model, _) = try F.confirm(source)
        model.answersLabelFortification(for: source)
        return (model, source)
    }

    // MARK: 18. Flag wiring

    func test18OnlyAnEditableSourceSetsTheFlag() throws {
        let (model, source) = try confirm()
        XCTAssertTrue(source.isEditable)
        XCTAssertTrue(model.state.answersLabelFortification)
        XCTAssertTrue(model.asksLabelFortification)

        let input = try XCTUnwrap(source.input)
        let manifest = try XCTUnwrap(PastedLabelValueOrigins.manifest(input, candidate: input.candidates[0]))
        let stored = PastedLabelSourceModel(stored: manifest, nutrients: input.candidates[0].candidate.nutrients)
        XCTAssertFalse(stored.isEditable)
        let relog = FoodConfirmationViewModel(state: FoodConfirmationState(input: input, prefillSourceQuantity: false)) { _ in
            throw FoodConfirmationSaveError.noAcceptedCandidate
        }
        relog.answersLabelFortification(for: stored)
        XCTAssertFalse(relog.state.answersLabelFortification, "a stored source never sets it")
        XCTAssertFalse(relog.asksLabelFortification)
        XCTAssertEqual(relog.foodDetailsActionTitle, FoodConfirmationViewModel.addFoodDetailsTitle, "C6: re-logs keep Food details")
    }

    // MARK: Unanswered Confirm: copy, decisions loop and Food details

    func testUnansweredAsksInLabelWordingWithNoCatalogueRemedy() throws {
        let (model, _) = try confirm()
        model.send(.setQuantity(40, .grams))
        XCTAssertEqual(model.labelFortification, .unanswered)
        XCTAssertEqual(model.blockedReason, "Answer whether the label says vitamins or minerals are added.")
        XCTAssertEqual(model.pendingDifferences, [], "the generic decisions loop skips fortification")
        XCTAssertEqual(model.missingSourceDetails, [])
        XCTAssertNil(model.foodDetailsActionTitle)
        XCTAssertEqual(model.offeredChoices(.fortification), [.notSure])
        XCTAssertEqual(model.labelFortificationFooter, PastedLabelText.fortificationFooterUnanswered)
        XCTAssertFalse(model.canLog)
        XCTAssertEqual(PastedLabelText.fortificationQuestion, "Does the label say vitamins or minerals are added?")
        XCTAssertEqual([PastedLabelText.fortificationYes, PastedLabelText.fortificationNo, PastedLabelText.fortificationNotStated],
                       ["Yes, it lists added vitamins or minerals", "No, the ingredients list none", "Not stated"])
    }

    func testYesNoAndNotStatedLogAsSpecified() throws {
        for answer in [FoodConfirmationViewModel.LabelFortification.yes, .no, .notStated] {
            let (model, source) = try confirm()
            model.send(.setQuantity(40, .grams))
            model.answerLabelFortification(answer)
            XCTAssertEqual(model.labelFortification, answer)
            XCTAssertNil(model.labelFortificationFailure)
            XCTAssertTrue(model.canLog, "\(answer): \(model.blockedReason ?? "")")
            XCTAssertEqual(model.savesEstimate, answer == .notStated)
            XCTAssertEqual(source.fortificationAnswer, answer == .yes ? .yes : answer == .no ? .no : .unanswered)
            model.log()
            let saved = try XCTUnwrap(model.savedResult, "\(answer)")
            XCTAssertEqual(saved.assertions.count, answer == .notStated ? 1 : 0)
            let detail = SavedFoodEntryDetail(stored: saved, isEstimate: answer == .notStated, history: [])
            XCTAssertEqual(detail.pastedLabelFortification, answer == .yes ? "Yes" : answer == .no ? "No" : "Not stated")
        }
    }

    // MARK: 10. Rebuilds keep the answer (C11, C12)

    func test10EveryRebuildKeepsNotStatedAndTheFlag() throws {
        let (model, source) = try confirm()
        model.send(.setQuantity(40, .grams))
        model.answerLabelFortification(.notStated)
        func check(_ step: String) {
            XCTAssertTrue(model.state.answersLabelFortification, step)
            XCTAssertEqual(model.labelFortification, .notStated, step)
            XCTAssertFalse(model.requirements.contains { if case .sourceIdentityMissing = $0 { true } else { false } }, step)
            XCTAssertTrue(model.canLog, "\(step): \(model.blockedReason ?? "")")
            XCTAssertEqual(model.state.quantity.value, 40, step)
        }
        XCTAssertNil(source.setValue("protein", text: "5.4", unit: "g"))
        check("Correct")
        source.removeValue("protein")
        check("Remove")
        try source.replace(review: F.review())
        check("Basis Change (the same rebuild path)")
        source.updateNameAndBrand(name: "Synthetic oat crackers", brand: "Another Mill")
        check("Back to Confirm")
        // A rebuild that makes fortification known drops the carried Not stated.
        model.answerLabelFortification(.yes)
        XCTAssertEqual(model.labelFortification, .yes)
        XCTAssertNil(model.state.decisions[.fortification])
        XCTAssertFalse(model.savesEstimate)
    }

    /// Test 6: Yes or No after Not stated clears the decision; Not stated after Yes returns the
    /// source to unknown; Read again starts unanswered (covered with Back to Confirm below).
    func test06ChangingTheAnswerClearsOrRecordsTheDecision() throws {
        let (model, source) = try confirm()
        model.send(.setQuantity(40, .grams))
        model.answerLabelFortification(.notStated)
        XCTAssertEqual(model.state.decisions[.fortification], .notSure)
        for answer in [FoodConfirmationViewModel.LabelFortification.yes, .no] {
            model.answerLabelFortification(answer)
            XCTAssertNil(model.state.decisions[.fortification], "\(answer) clears Not stated")
            XCTAssertEqual(model.labelFortification, answer)
            XCTAssertFalse(model.savesEstimate)
            model.answerLabelFortification(.notStated)
            XCTAssertEqual(source.fortificationAnswer, .unanswered, "the source is unknown again")
            XCTAssertEqual(model.state.decisions[.fortification], .notSure)
            XCTAssertTrue(model.savesEstimate)
        }
        XCTAssertTrue(model.canLog, model.blockedReason ?? "")
    }

    func test10EveryRebuildKeepsYesAndNo() throws {
        for answer in [FoodConfirmationViewModel.LabelFortification.yes, .no] {
            let (model, source) = try confirm()
            model.send(.setQuantity(40, .grams))
            model.answerLabelFortification(answer)
            XCTAssertNil(source.setValue("protein", text: "5.4", unit: "g"))
            source.removeValue("protein")
            try source.replace(review: F.review())
            source.updateNameAndBrand(name: "Synthetic oat crackers", brand: "Another Mill")
            XCTAssertEqual(model.labelFortification, answer, "\(answer)")
            XCTAssertTrue(model.state.answersLabelFortification)
            XCTAssertTrue(model.canLog, "\(answer): \(model.blockedReason ?? "")")
        }
    }

    /// C12: answer Yes, edit the label text and the brand, Back to Confirm: still Yes.
    func testBackToConfirmKeepsTheConfirmAnswer() throws {
        let stub = F.StubReader(F.reading())
        let text = F.textModel(stub)
        text.name = "Synthetic oat crackers"
        text.text = F.pastedText
        let source = try XCTUnwrap(text.readLabel())
        let (model, _) = try F.confirm(source)
        model.answersLabelFortification(for: source)
        model.answerLabelFortification(.yes)
        text.text += " "
        text.text = F.pastedText
        text.brand = "Synthetic Mill"
        XCTAssertTrue(text.returnToConfirm() === source)
        XCTAssertEqual(source.fortificationAnswer, .yes)
        XCTAssertEqual(model.labelFortification, .yes)
        XCTAssertEqual(model.displayedBrand?.value, "Synthetic Mill")
        // Read again is a new source: the question is asked again.
        let again = try XCTUnwrap(text.confirmReadAgain())
        XCTAssertFalse(again === source)
        XCTAssertEqual(again.fortificationAnswer, .unanswered)
    }

    func testAFailedAnswerKeepsTheEarlierAnswerAndSaysSo() throws {
        let source = try F.source(details: Self.unanswered, conversions: Failing())
        let (model, _) = try F.confirm(source)
        model.answersLabelFortification(for: source)
        model.answerLabelFortification(.yes)
        XCTAssertEqual(model.labelFortificationFailure, "The answer could not be applied. Your earlier answer is kept.")
        XCTAssertEqual(model.labelFortification, .unanswered)
        XCTAssertEqual(source.fortificationAnswer, .unanswered)
    }

    /// A conversion checker that accepts the first build and refuses every rebuild.
    private final class Failing: PastedLabelConversionChecking, @unchecked Sendable {
        private var calls = 0
        func storedTextMatches(_ conversion: PastedLabelManifest.Conversion) -> Bool {
            calls += 1
            return calls <= 2
        }
    }

    // MARK: Order and copy

    func testTheSourceFooterAndSavedEntryTitleUseTheRouteCopy() {
        XCTAssertEqual(PastedLabelText.sourceFooter,
                       "To change the name, brand or text, use Edit label text. To change a value, correct it in Nutrition from the label.")
        XCTAssertEqual(PastedLabelText.fortificationFooterNotStated,
                       "Fortification stays unknown, so this entry is marked as an estimate. The label’s values are kept as read.")
    }
}
