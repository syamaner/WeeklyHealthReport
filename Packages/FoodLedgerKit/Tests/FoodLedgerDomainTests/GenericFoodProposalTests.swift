import Foundation
import FoodLedgerDomain
import XCTest

final class GenericFoodProposalTests: XCTestCase {
    private let sourceText = "豆花 每份一碗 熱量150大卡 蛋白質6公克"

    func testPartialChineseServingRetainsUnknownsAndRequiresSemanticReview() throws {
        let result = try validate(candidate())
        let bound = try XCTUnwrap(result.candidates.first)
        XCTAssertTrue(bound.selectionEligible)
        XCTAssertEqual(bound.status, .literalBound)
        XCTAssertEqual(bound.candidate.basis.amount, "1")
        XCTAssertEqual(bound.candidate.basis.label, "每份一碗")
        XCTAssertEqual(bound.candidate.nutrients.filter { $0.state == .unknown }.count, 4)
        XCTAssertEqual(bound.document.rawSha256, String(repeating: "a", count: 64))
    }

    func testInventedNumberIsRejectedEvenWhenAnotherNumberIsPresent() throws {
        var value = candidate()
        var nutrients = value["nutrients"] as! [[String: Any]]
        nutrients[0]["value"] = "151"
        value["nutrients"] = nutrients
        XCTAssertEqual(try validate(value).rejected.first?.reason, .invalidNutrient)
    }

    func testQuoteMustBeAnExactSubstringOfItsOwnBlock() throws {
        var value = candidate()
        value["identity_evidence"] = [["block_id": "b1", "quote": "Invented soy pudding"]]
        XCTAssertEqual(try validate(value).rejected.first?.reason, .invalidReference)
    }

    func testInventedBrandDoesNotPassIdentityBinding() throws {
        var value = candidate(); value["brand"] = "Famous Brand"
        XCTAssertEqual(try validate(value).rejected.first?.reason, .invalidIdentity)
    }

    func testMissingBasisRemainsVisibleButCannotBeSelected() throws {
        var value = candidate()
        value["basis"] = ["amount": NSNull(), "unit": NSNull(), "label": NSNull(), "evidence": []]
        let result = try validate(value)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertFalse(result.candidates[0].selectionEligible)
        XCTAssertThrowsError(try FoodProposalSelection(choice: "c1", probabilities: ["c1": 1, "none": 0, "clarify": 0], rawConfidence: 1, validation: result))
    }

    func testChineseNumeralInWireAmountIsRejected() throws {
        var value = candidate()
        var basis = value["basis"] as! [String: Any]; basis["amount"] = "一"; value["basis"] = basis
        XCTAssertEqual(try validate(value).rejected.first?.reason, .invalidBasis)
    }

    func testOneServingDoesNotSupplyGramsOrAllowMultiplier() throws {
        for unitAndAmount in [("serving", "2"), ("g", "150")] {
            var value = candidate()
            var basis = value["basis"] as! [String: Any]
            basis["unit"] = unitAndAmount.0; basis["amount"] = unitAndAmount.1; value["basis"] = basis
            XCTAssertEqual(try validate(value).rejected.first?.reason, .invalidBasis)
        }
    }

    func testNutrientsOutsideTheDeclaredPanelAreRejected() throws {
        var value = candidate()
        var nutrients = value["nutrients"] as! [[String: Any]]
        nutrients[1]["evidence"] = [["block_id": "b2", "quote": "Other product protein 6g"]]
        value["nutrients"] = nutrients
        XCTAssertEqual(try validate(value, additionalBlocks: [.init(id: "b2", kind: "p", text: "Other product protein 6g", locator: "p:2")]).rejected.first?.reason, .invalidNutrient)
    }

    func testIdentityAndUnknownReferencesCannotBorrowAnotherPanel() throws {
        var value = candidate()
        let reference = [["block_id": "b2", "quote": "Other product protein 6g"]]
        let blocks = [FoodDocumentBlock(id: "b2", kind: "p", text: "Other product protein 6g", locator: "p:2")]
        value["name"] = "Other product"; value["identity_evidence"] = reference
        XCTAssertEqual(try validate(value, additionalBlocks: blocks).rejected.first?.reason, .invalidIdentity)
        value = candidate()
        var nutrients = value["nutrients"] as! [[String: Any]]
        nutrients[2]["evidence"] = reference; value["nutrients"] = nutrients
        XCTAssertEqual(try validate(value, additionalBlocks: blocks).rejected.first?.reason, .invalidNutrient)
    }

    func testDuplicateNutrientAndCandidateIDsFailClosed() throws {
        var value = candidate()
        var nutrients = value["nutrients"] as! [[String: Any]]; nutrients[1] = nutrients[0]; value["nutrients"] = nutrients
        XCTAssertEqual(try validate(value).rejected.first?.reason, .invalidNutrient)
        XCTAssertThrowsError(try decodeAndValidate([candidate(), candidate()]))
    }

    func testSameProductConflictsCannotBeHiddenByBasisWording() throws {
        var other = candidate(); other["id"] = "c2"
        var basis = other["basis"] as! [String: Any]; basis["label"] = "一碗"; other["basis"] = basis
        var nutrients = other["nutrients"] as! [[String: Any]]
        nutrients[0]["value"] = "250"; nutrients[0]["evidence"] = [["block_id": "b1", "quote": "熱量250大卡"]]
        other["nutrients"] = nutrients
        let result = try decodeAndValidate([candidate(), other], text: sourceText + " 另一處標示熱量250大卡")
        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertTrue(result.candidates.allSatisfy { $0.status == .conflictingCandidates && !$0.selectionEligible })
    }

    func testUnknownConflictPreventsSelectionWithoutDiscardingSource() throws {
        var value = candidate()
        var nutrients = value["nutrients"] as! [[String: Any]]; nutrients[2]["unknown_reason"] = "conflict"; value["nutrients"] = nutrients
        let result = try validate(value)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertFalse(result.candidates[0].selectionEligible)
    }

    func testUnitsBoundsRangesAndApproximateNumbersCannotBecomeExact() {
        for text in ["<6 g", "≤6g", ">6g", "-6 g", "about 6g", "約6公克", "3–6g", "6g–8g", "6g to 8g", "0.6g", "16g", "6mg", "6 gallons", "6,6g",
                     "less than 6g", "more than 6g", "at least 6g", "at most 6g", "under 6g", "over 6g", "minimum: 6g", "maximum 6g",
                     "小於6公克", "少于6克", "大約6公克", "至少6公克", "最多6公克", "超過6公克",
                     "6g or less", "6g or more", "6g ± 2g", "6g (approx)", "6g maximum", "6公克以下", "6公克左右"] {
            XCTAssertFalse(FoodProposalBinding.hasLiteral(text, value: "6", unit: "g"), text)
        }
        for text in ["Protein 6g", "蛋白質6公克", "蛋白質 6 克", "6.00 G"] {
            XCTAssertTrue(FoodProposalBinding.hasLiteral(text, value: "6", unit: "g"), text)
        }
    }

    func testSeparateQuotesCannotManufactureNumberAndUnitPair() throws {
        var value = candidate()
        var nutrients = value["nutrients"] as! [[String: Any]]
        nutrients[1]["evidence"] = [["block_id": "b1", "quote": "6"], ["block_id": "b1", "quote": "公克"]]
        value["nutrients"] = nutrients
        XCTAssertEqual(try validate(value).rejected.first?.reason, .invalidNutrient)
    }

    func testShortQuoteCannotStripQualifierRangeOrLeadingDigitFromSource() throws {
        for observed in ["<6公克", "約6公克", "16公克", "0.6公克", "3–6公克", "6公克–8公克", "6公克 to 8公克",
                         "小於6公克", "大約6公克", "6公克以下", "at least 6公克", "6公克 or less", "6公克 ± 2公克"] {
            let text = "豆花 每份一碗 熱量150大卡 蛋白質" + observed
            var value = candidate()
            let full = [["block_id": "b1", "quote": text]]
            value["identity_evidence"] = [["block_id": "b1", "quote": "豆花"]]
            value["panel_evidence"] = full
            var basis = value["basis"] as! [String: Any]; basis["evidence"] = full; value["basis"] = basis
            var nutrients = value["nutrients"] as! [[String: Any]]
            nutrients[0]["evidence"] = [["block_id": "b1", "quote": "150大卡"]]
            nutrients[1]["evidence"] = [["block_id": "b1", "quote": "6公克"]]
            value["nutrients"] = nutrients
            XCTAssertEqual(try decodeAndValidate([value], text: text).rejected.first?.reason, .invalidNutrient, observed)
        }
    }

    func testIdentityCannotBeAssembledAcrossSeparateQuotes() throws {
        var value = candidate(); value["name"] = "豆 花"
        value["identity_evidence"] = [["block_id": "b1", "quote": "豆"], ["block_id": "b1", "quote": "花"]]
        XCTAssertEqual(try validate(value).rejected.first?.reason, .invalidIdentity)
    }
    func testCompleteStructuralRowsCanBindTheirExplicitHeaderUnit() throws {
        for kind in ["tr", "definition_row"] {
            for row in ["Protein (g) | 1.2 | 6", "Protein (g) | <0.5 / 6", "蛋白質 (公克) | 6.00"] {
                XCTAssertEqual(try validateHeaderRow(row, kind: kind).candidates.count, 1, row)
            }
        }
    }

    func testHeaderUnitProfileRejectsBoundsRangesWrongUnitsAndShortQuotes() throws {
        for row in ["Protein (g) | <6", "Protein (g) | ≤6", "Protein (g) | about 6", "Protein (g) | 3–6",
                    "Protein (g) | 6–8", "Protein (mg) | 6", "Protein (g) | 16", "Protein (g) | 0.6",
                    "Protein (g) | 6 / 2mg", "Protein | 6", "Protein (g) | 6 /", "Protein (g) | 6,0",
                    "Protein (g) | 6 / 1 / 2 / 3 / 4"] {
            XCTAssertEqual(try validateHeaderRow(row).rejected.first?.reason, .invalidNutrient, row)
        }
        XCTAssertEqual(try validateHeaderRow("Protein (g) | 6", kind: "p").rejected.first?.reason, .invalidNutrient)
        XCTAssertEqual(try validateHeaderRow("Protein (g) | <0.5 / 6", quote: "6").rejected.first?.reason, .invalidNutrient)
        XCTAssertEqual(try validateHeaderRow("Protein (g) | 6 / 8", quote: "Protein (g) | 6").rejected.first?.reason, .invalidNutrient)
    }

    func testWholeScalarUnitLabelAndBareHeaderRemainLiteral() throws {
        for row in ["Protein (g): 6", "Protein (g) : 6.00", "蛋白質 (公克)：6"] {
            XCTAssertEqual(try validateHeaderRow(row, kind: "div").candidates.count, 1, row)
        }
        XCTAssertEqual(try validateHeaderRow("Protein g | 6").candidates.count, 1)
        for row in ["Protein (g): <6", "Protein (g): 6-8", "Protein (g): about 6", "Protein (g): 6%",
                    "Protein (g): 6 (estimated)", "Protein (mg): 6", "Protein: 6", "Protein (g): 6 / 8"] {
            XCTAssertEqual(try validateHeaderRow(row, kind: "div").rejected.first?.reason, .invalidNutrient, row)
        }
        XCTAssertEqual(try validateHeaderRow("Protein (g): 6", kind: "div", quote: "6").rejected.first?.reason, .invalidNutrient)
        XCTAssertEqual(try validateEnergyRow("Energy kJ/kcal | <624/150").rejected.first?.reason, .invalidNutrient)
    }

    func testPluralMillilitresRetainExactQuantityAndRejectQualifiers() {
        XCTAssertTrue(FoodProposalBinding.hasLiteral("Per 100mls", value: "100", unit: "ml"))
        for text in ["<100mls", "about 100mls", "100mls–200mls", "100mlstuff"] {
            XCTAssertFalse(FoodProposalBinding.hasLiteral(text, value: "100", unit: "ml"), text)
        }
    }

    func testPairedEnergyHeaderBindsOnlyItsExactKcalColumn() throws {
        for row in ["Energy kJ/kcal | 624/150", "Energy (kcal/kJ) | 150/624", "熱量 kJ/kcal | 624/150 | 100/24"] {
            XCTAssertEqual(try validateEnergyRow(row).candidates.count, 1, row)
        }
        for row in ["Energy kJ/kcal | 150/624", "Energy kcal/kJ | 624/150", "Energy kJ/kcal | 624/<150",
                    "Energy kJ/kcal | 624/about 150", "Energy kJ/kcal | 624/150–180", "Energy kJ/kJ | 624/150",
                    "Energy kJ/kcal | 624/150/3", "Energy kJ/kcal | 624/150 | invalid", "Calories | 150"] {
            XCTAssertEqual(try validateEnergyRow(row).rejected.first?.reason, .invalidNutrient, row)
        }
        XCTAssertEqual(try validateEnergyRow("Energy kJ/kcal | 624/150", kind: "p").rejected.first?.reason, .invalidNutrient)
        XCTAssertEqual(try validateEnergyRow("Energy kJ/kcal | 624/150", quote: "150").rejected.first?.reason, .invalidNutrient)
    }

    private func validateEnergyRow(_ row: String, kind: String = "tr", quote: String? = nil) throws -> FoodProposalValidation {
        var value = candidate()
        var panel = value["panel_evidence"] as! [[String: Any]]
        panel.append(["block_id": "b2", "quote": row]); value["panel_evidence"] = panel
        var nutrients = value["nutrients"] as! [[String: Any]]
        nutrients[0]["evidence"] = [["block_id": "b2", "quote": quote ?? row]]; value["nutrients"] = nutrients
        return try validate(value, additionalBlocks: [.init(id: "b2", kind: kind, text: row, locator: "row:2")])
    }

    private func validateHeaderRow(_ row: String, kind: String = "definition_row", quote: String? = nil) throws -> FoodProposalValidation {
        var value = candidate()
        var panel = value["panel_evidence"] as! [[String: Any]]
        panel.append(["block_id": "b2", "quote": row]); value["panel_evidence"] = panel
        var nutrients = value["nutrients"] as! [[String: Any]]
        nutrients[1]["evidence"] = [["block_id": "b2", "quote": quote ?? row]]; value["nutrients"] = nutrients
        return try validate(value, additionalBlocks: [.init(id: "b2", kind: kind, text: row, locator: "row:2")])
    }

    func testShortLiteralQuoteWithValidOriginalContextRemainsUsable() throws {
        var value = candidate()
        var nutrients = value["nutrients"] as! [[String: Any]]
        nutrients[1]["evidence"] = [["block_id": "b1", "quote": "6公克"]]
        value["nutrients"] = nutrients
        XCTAssertEqual(try validate(value).candidates.count, 1)
    }

    func testSelectionRequiresExactOfferedDistributionAndUncalibratedConfidence() throws {
        let validation = try validate(candidate())
        let selected = try FoodProposalSelection(choice: "c1", probabilities: ["c1": 0.9, "none": 0.05, "clarify": 0.05], rawConfidence: 0.92, validation: validation)
        XCTAssertEqual(selected.calibration, "not_calibrated_for_nutrition")
        XCTAssertThrowsError(try FoodProposalSelection(choice: "c2", probabilities: ["c1": 1, "none": 0, "clarify": 0], rawConfidence: 1, validation: validation))
        XCTAssertThrowsError(try FoodProposalSelection(choice: "c1", probabilities: ["c1": 1], rawConfidence: 1, validation: validation))
        XCTAssertThrowsError(try FoodProposalSelection(choice: "c1", probabilities: ["c1": 0.5, "none": 0, "clarify": 0], rawConfidence: 1, validation: validation))
        XCTAssertThrowsError(try FoodProposalSelection(choice: "c1", probabilities: ["c1": 1, "none": 0, "clarify": 0], rawConfidence: .nan, validation: validation))
    }

    func testDocumentLimitsAndDuplicateBlockIDsAreRejected() throws {
        let block = FoodDocumentBlock(id: "b1", kind: "p", text: sourceText, locator: "p:1")
        XCTAssertThrowsError(try document(blocks: [block, block]))
        XCTAssertThrowsError(try document(blocks: [.init(id: "b1", kind: "p", text: String(repeating: "a", count: 30_001), locator: "p:1")]))
    }

    private func candidate() -> [String: Any] {
        let ref: [[String: Any]] = [["block_id": "b1", "quote": sourceText]]
        let nutrients: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            let declared = key == .energy || key == .protein
            return ["key": key.rawValue, "state": declared ? "declared" : "unknown",
                    "value": declared ? (key == .energy ? "150" : "6") as Any : NSNull(),
                    "unit": declared ? key.unit as Any : NSNull(), "evidence": declared ? ref : [],
                    "unknown_reason": declared ? NSNull() : "not_observed" as Any]
        }
        return ["id": "c1", "document_id": "d1", "name": "豆花", "brand": NSNull(), "preparation": NSNull(),
                "identity_evidence": ref, "panel_evidence": ref,
                "basis": ["amount": "1", "unit": "serving", "label": "每份一碗", "evidence": ref],
                "nutrients": nutrients, "limitations": []]
    }
    private func document(blocks: [FoodDocumentBlock]) throws -> CapturedFoodDocument {
        try CapturedFoodDocument(id: "d1", url: "https://example.com/food", rawSha256: String(repeating: "a", count: 64),
            captureOrigin: "synthetic", retrievedAt: "2026-10-04T00:00:00Z", blocks: blocks)
    }
    private func validate(_ candidate: [String: Any], additionalBlocks: [FoodDocumentBlock] = []) throws -> FoodProposalValidation {
        try decodeAndValidate([candidate], additionalBlocks: additionalBlocks)
    }
    private func decodeAndValidate(_ candidates: [[String: Any]], text: String? = nil, additionalBlocks: [FoodDocumentBlock] = []) throws -> FoodProposalValidation {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try JSONSerialization.data(withJSONObject: ["version": FoodProposalExtraction.schemaVersion, "candidates": candidates, "preferred_id": "c1"])
        return try FoodProposalBinding.validate(decoder.decode(FoodProposalExtraction.self, from: response), documents: [document(blocks: [.init(id: "b1", kind: "p", text: text ?? sourceText, locator: "p:1")] + additionalBlocks)])
    }
}
