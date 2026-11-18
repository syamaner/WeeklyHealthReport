import FoodLedgerDomain
@testable import FoodLedgerPresentation
import XCTest

/// Label photo estimates (docs/personal-food-catalogue-off-estimates-v1-phase.md section 6, test 12):
/// the details line names the source in the owner's words (decision F5), and the other three keep
/// theirs.
final class PhotoEstimatePresentationTests: XCTestCase {
    func testEverySourceTypeHasItsDetailsText() {
        XCTAssertEqual(ApprovedEstimateText.sourceType(.productDatasetPhoto), "Product database label photo")
        XCTAssertEqual(ApprovedEstimateText.sourceType(.nationalComposition), "Food composition table")
        XCTAssertEqual(ApprovedEstimateText.sourceType(.manufacturerPage), "Maker's web page")
        XCTAssertEqual(ApprovedEstimateText.sourceType(.aggregator), "Food database website")
    }
}
