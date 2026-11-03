import FoodLabelTextCapture
import FoodLedgerApplication
import Foundation
import XCTest

/// P2a gate finding 13 (`docs/pasted-nutrition-label-uk-english-v1-p2.md`, #375): how the shipped
/// reader handles a Traditional Chinese or mixed paste whose amount header uses an English gram
/// spelling the header vocabulary does not know.
final class TaiwanHeaderProbeTests: XCTestCase {
    private let product = PastedLabelReader(reader: NutritionLabelTextReader(), digester: SHA256Digester())

    static func texts() -> [String] {
        let rows = "熱量 200大卡\n蛋白質 5公克\n脂肪 3公克\n飽和脂肪 1公克\n反式脂肪 0公克\n碳水化合物 30公克\n糖 10公克\n鈉 100毫克"
        let headers = ["Per 100gm", "per 100 grams", "Per 100", "Per 100gms", "per 100 g"]
        return headers.flatMap { header in
            ["營養標示\n每一份量 30公克\n本包裝含 5份\n\(header)\n" + rows,
             "營養標示 Nutrition Facts\n每一份量 30公克\n本包裝含 5份\n\(header)\n" + rows]
        }
    }

    /// Since #375 the shipped reader declines these headers instead of binding them per serving;
    /// `per 100 g` still reads per 100 g.
    func testShippedReaderDeclinesTheseUnknownGramHeaders() {
        for text in Self.texts() {
            let outcome = product.read(text)
            if text.contains("per 100 g\n") {
                guard case let .usable(review) = outcome else { XCTFail(text); continue }
                XCTAssertEqual(review.reading.candidate.headers.first { $0.headerID == review.storedHeaderID }?.basis, "per_100g")
            } else {
                XCTAssertEqual(outcome.declineCodes, ["unrecognised_unit"], text)
            }
        }
    }
}
