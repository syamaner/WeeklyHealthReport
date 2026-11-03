import FoodLabelTextCapture
import FoodLedgerApplication
import Foundation
import NutritionLabelParsing
import XCTest

/// The P1 development harness against the product (`docs/pasted-nutrition-label-uk-english-v1.md`
/// test 8): with the product's own scope it decides every fixture exactly as `PastedLabelReader`,
/// and with the UK scope it differs only where a UK table would be declined for scope alone.
final class UKDevelopmentReaderTests: XCTestCase {
    private let product = PastedLabelReader(reader: NutritionLabelTextReader(), digester: SHA256Digester())

    private func fixtureTexts() throws -> [String] {
        let synthetic = [
            SyntheticLabelTexts.base, SyntheticLabelTexts.kilojoulesOnly, SyntheticLabelTexts.asPrepared, SyntheticLabelTexts.drained,
            SyntheticLabelTexts.sodiumMissing, SyntheticLabelTexts.packMissing, SyntheticLabelTexts.perServingOnly,
            SyntheticLabelTexts.perServingNoSize, SyntheticLabelTexts.supplement, SyntheticLabelTexts.fullwidthDigits,
            SyntheticLabelTexts.energyMismatch, SyntheticLabelTexts.usNutritionFacts, SyntheticLabelTexts.ukDeclaration,
            SyntheticLabelTexts.japanese,
            UnheadedTableFixtures.inline1, UnheadedTableFixtures.inline2, UnheadedTableFixtures.inline1Ml,
            UnheadedTableFixtures.stacked1, UnheadedTableFixtures.stacked2, UnheadedTableFixtures.flattened1,
            UnheadedTableFixtures.flattened2, UnheadedTableFixtures.energyLine, UnheadedTableFixtures.energyLineServing,
            UnheadedTableFixtures.mixedInline,
        ]
        return synthetic + (try FrozenParityCases.textCases().map(\.text))
    }

    func testProductScopeMatchesThePastedLabelReaderOnEveryFixture() throws {
        let development = UKDevelopmentReader.product
        let texts = try fixtureTexts()
        XCTAssertGreaterThan(texts.count, 100)
        for text in texts {
            XCTAssertEqual(development.read(text), product.read(text), text)
        }
    }

    /// P2b S1 reference (`docs/pasted-nutrition-label-uk-english-v1-p2b.md`): the pre-seam copy, in
    /// its UK configuration, decides every fixture exactly as the seam's `.ukDevelopment` policy.
    func testTheSeamUKPolicyMatchesThePreSeamCopyOnEveryFixture() throws {
        let seam = PastedLabelReader(reader: UKEnglishLabelTextReader(), digester: SHA256Digester(), policy: .ukDevelopment)
        let copy = UKDevelopmentReader()
        for text in try fixtureTexts() + TaiwanHeaderProbeTests.texts() {
            XCTAssertEqual(seam.read(text), copy.read(text), text)
        }
    }

    func testUKScopeRemovesOnlyTheScopeDeclineFromUKTables() throws {
        let development = UKDevelopmentReader(reader: NutritionLabelTextReader(), isAsSold: PastedLabelBasisState.isAsSold)
        var admitted = 0
        for text in try fixtureTexts() {
            let expected = product.read(text)
            let actual = development.read(text)
            guard actual != expected else { continue }
            // Only a UK table the product declined for scope may differ, and only by that code.
            guard case let .declined(codes, reading) = expected else { XCTFail("a usable product reading changed: \(text)"); continue }
            XCTAssertTrue(codes.contains(PastedLabelCodes.layoutNotSupported), text)
            XCTAssertEqual(reading?.format, LabelFormatInference.Outcome.uk.rawValue, text)
            let others = codes.filter { $0 != PastedLabelCodes.layoutNotSupported }
            if others.isEmpty {
                if case .declined = actual { XCTFail("a scope-only decline still declines: \(text)") }
                admitted += 1
            } else {
                XCTAssertEqual(actual.declineCodes, others, text)
            }
        }
        XCTAssertGreaterThan(admitted, 0)
    }

    func testSyntheticUKDeclarationReachesConfirmUnderTheUKScope() {
        guard case let .usable(review) = UKDevelopmentReader().read(SyntheticLabelTexts.ukDeclaration) else {
            return XCTFail("the synthetic UK declaration should be usable under the UK scope")
        }
        XCTAssertEqual(review.reading.format, LabelFormatInference.Outcome.uk.rawValue)
        XCTAssertEqual(product.read(SyntheticLabelTexts.ukDeclaration).declineCodes, [PastedLabelCodes.layoutNotSupported])
    }

    func testUSPanelStillDeclinesUnderTheUKScope() {
        let outcome = UKDevelopmentReader().read(SyntheticLabelTexts.usNutritionFacts)
        XCTAssertFalse(outcome.declineCodes.isEmpty)
        // The same reason as the product, apart from the launch scope code the UK scope removes.
        XCTAssertEqual(outcome.declineCodes, product.read(SyntheticLabelTexts.usNutritionFacts).declineCodes.filter { $0 != PastedLabelCodes.layoutNotSupported })
    }
}
