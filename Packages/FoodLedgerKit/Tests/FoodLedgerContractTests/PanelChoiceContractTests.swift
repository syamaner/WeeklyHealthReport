import Foundation
import FoodGenericSearch
@_spi(ReviewedWebRegression) import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import XCTest

/// Phase 2 of docs/web-lookup-part-read-pages-v1-proposal.md (#508): the offer table, the writer
/// for every offered pick, and the panel list content (gate docs/web-lookup-panel-choice-phase2-gate.md).
final class PanelChoiceContractTests: XCTestCase {
    private let lines = ["豆花 每份一碗 熱量150大卡 蛋白質6公克", "豆花 每份一碗 熱量250大卡 蛋白質6公克", "豆花 冷藏 每份一碗 熱量150大卡 蛋白質6公克"]

    // MARK: Offer table, one case per row (contract test 14)

    func testRow1OneOfferableCandidateIsOfferedAndPreselected() throws {
        let review = try review([.c1], choice: "c1")
        XCTAssertEqual(review.offer.candidates.map(\.id), ["c1"])
        XCTAssertEqual(review.offer.preselectedID, "c1")
        XCTAssertFalse(review.offer.warns)
        XCTAssertFalse(review.offer.requiresPick)
    }

    func testRow2SuggestionAndItsCompetingPanelsAreOfferedButNotAnotherFood() throws {
        let review = try review([.c1, .c2Different, .otherPreparation], choice: "c1")
        XCTAssertEqual(review.offer.candidates.map(\.id), ["c1", "c2"], "the other preparation is a different food")
        XCTAssertEqual(review.offer.preselectedID, "c1")
        XCTAssertFalse(review.offer.warns)
        // Contract test 15: both conflicting candidates are choosable although neither is eligible.
        XCTAssertTrue(review.validation.candidates.filter { $0.id != "c3" }.allSatisfy { $0.choosable && !$0.selectionEligible })
    }

    func testRow2EqualPanelsAreBothOffered() throws {
        let review = try review([.c1, .c2Equal], choice: "c1")
        XCTAssertEqual(review.offer.candidates.map(\.id), ["c1", "c2"])
        XCTAssertEqual(review.offer.preselectedID, "c1")
    }

    func testRow3ClarifyWithCompetingPanelsRequiresAPickAndWarns() throws {
        let review = try review([.c1, .c2Different], choice: "clarify")
        XCTAssertEqual(review.offer.candidates.map(\.id), ["c1", "c2"])
        XCTAssertNil(review.offer.preselectedID)
        XCTAssertTrue(review.offer.requiresPick)
        XCTAssertTrue(review.offer.warns)
    }

    func testRow3EqualPanelsWithAConflictingThirdAreAllOffered() throws {
        let review = try review([.c1, .c2Equal, .c3Different], choice: "clarify")
        XCTAssertEqual(review.offer.candidates.map(\.id), ["c1", "c2", "c3"])
    }

    func testNothingIsOfferedForEveryOtherAnswer() throws {
        let cases: [(String, GenericFoodProposalReview)] = [
            ("clarify, one candidate", try review([.c1], choice: "clarify")),
            ("clarify, equal panels only", try review([.c1, .c2Equal], choice: "clarify")),
            ("clarify, only partner unusable", try review([.c1InternalConflict, .c2Different], choice: "clarify")),
            ("none", try review([.c1, .c2Different], choice: "none")),
            ("check not run", try review([.c1, .c2Different], choice: nil)),
            ("check unavailable", try review([.c1, .c2Different], choice: "c1", rankingUnavailable: true)),
            ("named candidate with a basis conflict", try review([.c1], choice: "c1", query: "tofu pudding per 100 ml"))
        ]
        for (name, review) in cases {
            XCTAssertTrue(review.offer.isEmpty, name)
            XCTAssertFalse(review.validation.candidates.contains { review.permitsConfirmation(of: $0) }, name)
        }
    }

    func testRow1WithAnUnusablePartnerShowsNoDifferentValues() throws {
        let review = try review([.c1InternalConflict, .c2Different], choice: "c2")
        XCTAssertEqual(review.offer.candidates.map(\.id), ["c2"])
        let content = FoodWebLookupOfferContent(review: review, selectedID: "c2", scope: nil)
        XCTAssertEqual(content.rows.map(\.differentValues), [false])
    }

    // MARK: Writer: every offered pick prepares and is admitted

    func testEveryOfferedPickPreparesAnAdmittedV3ManifestAcrossCombinations() throws {
        let sets: [[Panel]] = [[.c1], [.c1, .c2Different], [.c1, .c2Equal], [.c1, .c2Equal, .c3Different],
                               [.c1InternalConflict, .c2Different], [.c1, .c2Different, .otherPreparation]]
        var offeredCount = 0
        for (set, query) in sets.flatMap({ set in [ReviewedWebFixtures.query, "tofu pudding per 100 ml"].map { (set, $0) } }) {
            for choice in ["c1", "c2", "c3", "clarify", "none"] where choice == "clarify" || choice == "none" || set.contains(where: { $0.id == choice }) {
                guard let review = try? review(set, choice: choice, query: query) else { continue }
                if query != ReviewedWebFixtures.query { XCTAssertTrue(review.offer.isEmpty, "a basis conflict offers nothing: \(set) \(choice)") }
                for proposal in review.offer.candidates {
                    let input = try confirmation().prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("en_GB"))
                    XCTAssertEqual(FoodReviewedWebProposalPolicy.scope(input, candidate: input.candidates[0]), .representativeEstimate, "\(set) \(choice) \(proposal.id)")
                    guard case let .v3(manifest) = FoodProposalReviewManifestRecord.decode(Data(try ReviewedWebFixtures.manifestText(input).utf8)) else {
                        XCTFail("v3"); continue
                    }
                    XCTAssertNil(manifest.admissionFailure)
                    XCTAssertEqual(manifest.offered, review.offer.candidates.map(\.candidate))
                    XCTAssertEqual(manifest.gate.personChoice, proposal.id)
                    XCTAssertEqual(manifest.gate.selectionChoice, choice)
                    offeredCount += 1
                }
                for proposal in review.validation.candidates where !review.offer.candidates.contains(proposal) {
                    XCTAssertThrowsError(try confirmation().prepare(review: review, proposal: proposal, scope: .representativeEstimate,
                                                                    locale: LedgerText("en_GB")), "\(set) \(choice) \(proposal.id)")
                }
            }
        }
        XCTAssertGreaterThan(offeredCount, 10)
    }

    // MARK: v2 is unchanged

    func testV2KeepsChoicePolicyV3AndRefusesPhase2Picks() throws {
        XCTAssertEqual(FoodProposalReviewGateRecord.knownChoicePolicies, ["food-proposal-review-choice-v3"])
        XCTAssertEqual(GenericFoodProposalReview.choicePolicyVersion, "food-proposal-review-choice-v4")
        let row2 = try review([.c1, .c2Different], choice: "c1")
        let row3 = try review([.c1, .c2Different], choice: "clarify")
        for (name, review, proposal) in [("row 2 alternative", row2, row2.offer.candidates[1]), ("row 2 suggestion", row2, row2.offer.candidates[0]),
                                         ("row 3 pick", row3, row3.offer.candidates[0])] {
            XCTAssertThrowsError(try confirmation().prepareVersion2(review: review, proposal: proposal, scope: .representativeEstimate,
                                                                    locale: LedgerText("en_GB")), name)
        }
        let row1 = try review([.c1], choice: "c1")
        let v2 = try confirmation().prepareVersion2(review: row1, proposal: row1.offer.candidates[0], scope: .representativeEstimate, locale: LedgerText("en_GB"))
        XCTAssertTrue(try ReviewedWebFixtures.manifestText(v2).contains(#""choicePolicy":"food-proposal-review-choice-v3""#))
    }

    func testSelectionAcceptsAChoosableConflictingIdAndRejectsAnUnusableOne() throws {
        let validation = try review([.c1InternalConflict, .c2Different], choice: nil).validation
        XCTAssertNoThrow(try FoodProposalSelection(unscoredChoice: "c2", validation: validation))
        XCTAssertThrowsError(try FoodProposalSelection(unscoredChoice: "c1", validation: validation))
    }

    // MARK: Panel list content (contract test 17)

    func testRow2ContentPreselectsTheSuggestionWithoutTheWarning() throws {
        let review = try review([.c1, .c2Different], choice: "c1")
        let content = FoodWebLookupOfferContent(review: review, selectedID: "c1", scope: .representativeEstimate)
        XCTAssertEqual(content.title, "Suggested source")
        XCTAssertNil(content.warningLine)
        XCTAssertNil(content.promptLine)
        XCTAssertNil(content.disabledReason)
        XCTAssertEqual(content.rows.map(\.suggested), [true, false])
        XCTAssertEqual(content.rows.map(\.differentValues), [true, true])
        XCTAssertEqual(content.rows.map(\.selected), [true, false])
        XCTAssertEqual(content.rows.map(\.firstQuote), [lines[0], lines[1]])
        XCTAssertEqual(content.rows.map { $0.declared.map(\.value) }, [["150", "6"], ["250", "6"]])
        XCTAssertEqual(content.selected?.name, "豆花")
        XCTAssertEqual(content.rows[0].accessibilityLabel, "豆花, Entry 1 of 2, per 每份一碗, \(FoodNutritionReviewPresentation.label(.energyConsumed)) 150 kcal, \(FoodNutritionReviewPresentation.label(.protein)) 6 g, Suggested, Different values")
    }

    func testRow3ContentAsksForAPickAndKeepsTheWarningAfterIt() throws {
        let review = try review([.c1, .c2Different], choice: "clarify")
        let before = FoodWebLookupOfferContent(review: review, selectedID: nil, scope: nil)
        XCTAssertEqual(before.title, "Choose a panel")
        XCTAssertEqual(before.warningLine, "The check could not confirm this page matches your food. Compare the name, brand and variant before you choose.")
        XCTAssertEqual(before.promptLine, "This page gives more than one set of values. Choose the one that matches your food.")
        XCTAssertEqual(before.disabledReason, "Choose a panel to use this source.")
        XCTAssertEqual(before.rows.map(\.suggested), [false, false])
        XCTAssertNil(before.selected)
        let after = FoodWebLookupOfferContent(review: review, selectedID: "c2", scope: .representativeEstimate)
        XCTAssertEqual(after.warningLine, before.warningLine)
        XCTAssertEqual(after.title, "Choose a panel")
        XCTAssertNil(after.disabledReason)
        XCTAssertEqual(after.rows.map(\.selected), [false, true])
        XCTAssertEqual(after.selected?.declared.first?.value, "250")
        // An id outside the offer selects nothing.
        XCTAssertNil(FoodWebLookupOfferContent(review: review, selectedID: "c9", scope: nil).selected)
    }

    func testContentRebuiltFromTheManifestEqualsTheContentShown() throws {
        for (choice, pick) in [("c1", "c2"), ("c1", "c1"), ("clarify", "c2")] {
            let review = try review([.c1, .c2Different, .otherPreparation], choice: choice)
            let proposal = try XCTUnwrap(review.offer.candidates.first { $0.id == pick })
            let shown = FoodWebLookupOfferContent(review: review, selectedID: pick, scope: .representativeEstimate)
            let input = try confirmation().prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("en_GB"))
            guard case let .v3(manifest) = FoodProposalReviewManifestRecord.decode(Data(try ReviewedWebFixtures.manifestText(input).utf8)) else {
                return XCTFail("v3")
            }
            XCTAssertEqual(FoodWebLookupOfferContent(manifest: manifest), shown, "\(choice) \(pick)")
        }
    }

    func testCopyForOffersAndForPagesWithNothingOffered() throws {
        let row2 = try review([.c1, .c2Different], choice: "c1")
        XCTAssertEqual(GenericFoodProposalReviewCopy.summary(row2), "Found 1 source · it gives more than one set of values")
        XCTAssertEqual(GenericFoodProposalReviewCopy.summary(try review([.c1], choice: "c1")), "Found 1 source · 1 suits this food")
        XCTAssertEqual(row2.validation.candidates.map { GenericFoodProposalReviewCopy.status($0, in: row2) }, ["Different values", "Different values"])
        let none = try review([.c1, .c2Different], choice: "none")
        XCTAssertEqual(GenericFoodProposalReviewCopy.noSuggestion(none).text, "No usable source was found for this food.")
        for review in [none, try review([.c1, .c2Different], choice: nil), try review([.c1, .c2Different], choice: "c1", rankingUnavailable: true)] {
            XCTAssertFalse(GenericFoodProposalReviewCopy.noSuggestion(review).text.contains("conflicting values"))
        }
        let unchecked = try review([.c1, .c2Different], choice: "c1", rankingUnavailable: true)
        XCTAssertEqual(unchecked.validation.candidates.map { GenericFoodProposalReviewCopy.status($0, in: unchecked) },
                       ["Different values · Not checked for this food", "Different values · Not checked for this food"])
        let unusable = try review([.c1InternalConflict], choice: nil)
        XCTAssertEqual(GenericFoodProposalReviewCopy.status(unusable.validation.candidates[0], in: unusable), "Needs more information")
        // "Other sources" for a page with nothing offered: a conflict with an unusable candidate is not "Different values".
        let partner = try review([.c1InternalConflict, .c2Different], choice: "clarify")
        XCTAssertTrue(partner.offer.isEmpty)
        XCTAssertEqual(partner.validation.candidates.map(\.status), [.conflictingCandidates, .conflictingCandidates])
        XCTAssertEqual(partner.validation.candidates.map { GenericFoodProposalReviewCopy.status($0, in: partner) },
                       ["Needs more information", "Not suggested for this food"])
        // Equal duplicates are offered, but the summary does not claim different sets of values.
        XCTAssertEqual(GenericFoodProposalReviewCopy.summary(try review([.c1, .c2Equal], choice: "c1")), "Found 1 source · 1 suits this food")
    }

    // MARK: Fixtures

    enum Panel: Equatable, CustomStringConvertible {
        case c1, c2Different, c2Equal, c3Different, c1InternalConflict, otherPreparation
        var id: String {
            switch self { case .c1, .c1InternalConflict: "c1"; case .c2Different, .c2Equal: "c2"; case .c3Different, .otherPreparation: "c3" }
        }
        var description: String { "\(self == .c1 ? "c1" : String(describing: id))" }
    }

    private func confirmation() -> ReviewedFoodProposalConfirmation {
        ReviewedFoodProposalConfirmation(ids: RandomLedgerIDGenerator(), clock: LedgerFixtures.clock,
            encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
    }

    private func review(_ panels: [Panel], choice: String?, rankingUnavailable: Bool = false,
                        query: String = ReviewedWebFixtures.query) throws -> GenericFoodProposalReview {
        let document = try GenericFoodDocumentProjector.project(Data(lines.joined(separator: "\n").utf8), url: URL(string: "https://example.com/tofu")!,
            mediaType: "text/plain", retrievedAt: LedgerFixtures.date, origin: "synthetic_fixture")
        let candidates = try panels.map { try candidate($0, documentID: document.id) }
        let validation = try FoodProposalBinding.validate(.init(candidates: candidates, preferredId: candidates[0].id), documents: [document])
        XCTAssertEqual(validation.candidates.count, panels.count, "\(validation.rejected)")
        let selection = try choice.map { try FoodProposalSelection(unscoredChoice: $0, validation: validation) }
        return GenericFoodProposalReview(foodTerms: query, discovery: nil, documents: [document], validation: validation,
                                         selection: selection, rankingUnavailable: rankingUnavailable)
    }

    private func candidate(_ panel: Panel, documentID: String) throws -> FoodProposalCandidate {
        let (block, energy, preparation): (String, String, String?) = switch panel {
        case .c1, .c1InternalConflict, .c2Equal: ("b1", "150", nil)
        case .c2Different, .c3Different: ("b2", "250", nil)
        case .otherPreparation: ("b3", "150", "冷藏")
        }
        let quote = block == "b1" ? lines[0] : block == "b2" ? lines[1] : lines[2]
        let ref: [[String: Any]] = [["block_id": block, "quote": quote]]
        let values: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            let known = key == .energy || key == .protein
            let conflict = panel == .c1InternalConflict && key == .fat
            return ["key": key.rawValue, "state": known ? "declared" : "unknown",
                    "value": known ? (key == .energy ? energy : "6") as Any : NSNull(), "unit": known ? key.unit as Any : NSNull(),
                    "evidence": known ? ref : [], "unknown_reason": known ? NSNull() : (conflict ? "conflict" : "not_observed") as Any]
        }
        let object: [String: Any] = ["id": panel.id, "document_id": documentID, "name": "豆花", "brand": NSNull(),
            "preparation": preparation.map { $0 as Any } ?? NSNull(), "identity_evidence": ref, "panel_evidence": ref,
            "basis": ["amount": "1", "unit": "serving", "label": "每份一碗", "evidence": ref],
            "nutrients": values, "limitations": []]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FoodProposalCandidate.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
