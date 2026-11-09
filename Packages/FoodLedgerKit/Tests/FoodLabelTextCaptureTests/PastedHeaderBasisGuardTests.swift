@testable import FoodLabelTextCapture
import FoodLedgerApplication
import Foundation
import NutritionLabelParsing
import XCTest

/// #375: a per serving header that names 100 declines on the shipped reader instead of storing per
/// 100 values as per serving, and no accepted reading changes. Every text is synthetic.
final class PastedHeaderBasisGuardTests: XCTestCase {
    private let product = PastedLabelReader(reader: NutritionLabelTextReader(), digester: SHA256Digester())
    private let parser = NutritionLabelTextParserV3()

    static let rows = "熱量 200大卡\n蛋白質 5公克\n脂肪 3公克\n飽和脂肪 1公克\n反式脂肪 0公克\n碳水化合物 30公克\n糖 10公克\n鈉 100毫克"

    static func taiwan(_ header: String, title: String = "營養標示") -> String {
        "\(title)\n每一份量 30公克\n本包裝含 5份\n\(header)\n" + rows
    }

    func testEveryHeaderOfTheDefectNowDeclinesInsteadOfBindingPerServing() {
        for header in ["Per 100gm", "per 100 grams", "Per 100", "Per 100gms", "per 100 kcal", "Per serving (100 pieces)"] {
            for title in ["營養標示", "營養標示 Nutrition Facts"] {
                XCTAssertEqual(product.read(Self.taiwan(header, title: title)).declineCodes, [PastedHeaderBasisGuard.declineCode], header)
            }
        }
    }

    func testHeadersThatNameTheirBasisAreUnchanged() {
        for (header, basis) in [("per 100 g", "per_100g"), ("每份", "per_serving"), ("每100公克", "per_100g"), ("Per serving (100g)", "per_serving"),
                                ("Per 30g serving", "per_serving")] {
            guard case let .usable(review) = product.read(Self.taiwan(header)) else { return XCTFail(header) }
            XCTAssertEqual(review.reading.candidate.headers.first { $0.headerID == review.storedHeaderID }?.basis, basis, header)
        }
    }

    /// No fixture or frozen parity case reaches the guard: every accepted reading is unchanged.
    func testTheGuardLeavesEveryFixtureAndParityCaseUnchanged() throws {
        let texts = [SyntheticLabelTexts.base, SyntheticLabelTexts.kilojoulesOnly, SyntheticLabelTexts.asPrepared, SyntheticLabelTexts.drained,
                     SyntheticLabelTexts.sodiumMissing, SyntheticLabelTexts.packMissing, SyntheticLabelTexts.perServingOnly,
                     SyntheticLabelTexts.perServingNoSize, SyntheticLabelTexts.supplement, SyntheticLabelTexts.fullwidthDigits,
                     SyntheticLabelTexts.energyMismatch, SyntheticLabelTexts.usNutritionFacts, SyntheticLabelTexts.ukDeclaration,
                     SyntheticLabelTexts.japanese, UnheadedTableFixtures.inline1, UnheadedTableFixtures.inline2, UnheadedTableFixtures.inline1Ml,
                     UnheadedTableFixtures.stacked1, UnheadedTableFixtures.stacked2, UnheadedTableFixtures.flattened1,
                     UnheadedTableFixtures.flattened2, UnheadedTableFixtures.energyLine, UnheadedTableFixtures.energyLineServing,
                     UnheadedTableFixtures.mixedInline] + (try FrozenParityCases.textCases().map(\.text))
        XCTAssertGreaterThan(texts.count, 100)
        for text in texts {
            let candidate = parser.parse(text, inputSHA256: "x")
            XCTAssertEqual(PastedHeaderBasisGuard.apply(candidate), candidate, text)
            for bases in [[LabelBasis.per100g], [.perServing, .per100g]] {
                let asserted = parser.parse(text, inputSHA256: "x", assertedBases: bases)
                XCTAssertEqual(PastedHeaderBasisGuard.apply(asserted), asserted, text)
            }
        }
    }

    func testAStrayClosingBracketNeverHidesOrInventsAHundred() {
        XCTAssertFalse(PastedHeaderBasisGuard.namesHundred("Per serving) (100g)"))
        XCTAssertTrue(PastedHeaderBasisGuard.namesHundred("Per serving) 100"))
        XCTAssertTrue(PastedHeaderBasisGuard.namesHundred("Per serving (100 pieces)"))
    }

    func testTheGuardOnlyEverDeclines() {
        for header in ["Per 100gm", "per 100 g", "Per 100", "每份"] {
            let candidate = parser.parse(Self.taiwan(header), inputSHA256: "x")
            let guarded = PastedHeaderBasisGuard.apply(candidate)
            XCTAssertTrue(guarded == candidate || (guarded.declined && guarded.cells.isEmpty && guarded.inputSHA256 == "x"), header)
        }
    }
}
