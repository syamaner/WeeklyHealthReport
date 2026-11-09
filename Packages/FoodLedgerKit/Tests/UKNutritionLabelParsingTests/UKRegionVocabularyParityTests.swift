@testable import NutritionLabelParsing
@testable import UKNutritionLabelParsing
import XCTest

/// Contract test 11 of `docs/pasted-nutrition-label-uk-english-v2-p1.md`: the region stage's row
/// predicate covers every English row parser v3 knows, so S2 can never set a declared nutrient
/// aside without declining.
final class UKRegionVocabularyParityTests: XCTestCase {
    func testTheRowPredicateCoversEveryParserV3EnglishRow() {
        for label in LabelVocabulary.englishRows.keys.sorted() {
            XCTAssertNotNil(UKTableRegion.rowWord(label), label)
            XCTAssertNotNil(UKTableRegion.rowWord("of which \(label)"), label)
            XCTAssertNotNil(UKTableRegion.rowWord("\(label)\t1.0g"), label)
        }
    }

    func testEveryUKRowWordThatParserV3KnowsClassifiesAsARow() {
        let unknownToParserV3: Set<String> = ["mono-unsaturates", "monounsaturates", "polyunsaturates", "poly-unsaturates", "polyols",
                                              "starch", "sugar"]
        for word in UKVocabulary.rowWords where !unknownToParserV3.contains(word) {
            XCTAssertNotNil(RowClassifier.classify(word), word)
        }
    }
}
