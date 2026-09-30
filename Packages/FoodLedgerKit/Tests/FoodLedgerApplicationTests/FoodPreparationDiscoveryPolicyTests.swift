import XCTest
import FoodLedgerApplication
import FoodLedgerDomain

final class FoodPreparationDiscoveryPolicyTests: XCTestCase {
    func testUnknownPreparationRequiresNamedDishReviewAndNeverOverridesKnownState() throws {
        let named = FoodQueryParser.parse("200g cooked porridge made with water")
        let ordinary = FoodQueryParser.parse("100g cooked milk powder")
        for kind in [PreparationKind.raw, .cooked] {
            let expected = try PreparationState(kind: kind)
            let unknown = try PreparationState(kind: .unknown)
            XCTAssertTrue(FoodPreparationDiscoveryPolicy.accepts(requested: expected, actual: unknown, sourceName: "Porridge, made with water", query: named))
            XCTAssertFalse(FoodPreparationDiscoveryPolicy.accepts(requested: expected, actual: unknown, sourceName: "Milk powder", query: ordinary))
            XCTAssertEqual(unknown.kind, .unknown)
            XCTAssertTrue(FoodPreparationDiscoveryPolicy.isUnverified(requested: expected, actual: unknown.kind))
            for actualKind in [PreparationKind.raw, .cooked, .asSold, .reheated] {
                XCTAssertEqual(FoodPreparationDiscoveryPolicy.accepts(requested: expected, actual: try PreparationState(kind: actualKind), sourceName: "Synthetic", query: named), kind == actualKind)
            }
        }
        for kind in [PreparationKind.asSold, .reheated] {
            XCTAssertFalse(FoodPreparationDiscoveryPolicy.accepts(requested: try PreparationState(kind: kind), actual: try PreparationState(kind: .unknown), sourceName: "Porridge", query: named))
        }
    }
    func testContrarySourceWordsVetoButNeverPopulateUnknownPreparation() throws {
        let named = FoodQueryParser.parse("200g porridge made with water")
        let unknown = try PreparationState(kind: .unknown)
        for name in ["Porridge raw", "Porridge uncooked", "Porridge cooked and raw"] {
            XCTAssertFalse(FoodPreparationDiscoveryPolicy.accepts(requested: try PreparationState(kind: .cooked), actual: unknown, sourceName: name, query: named))
        }
        for word in ["cooked", "roasted", "boiled", "grilled", "broiled", "fried", "baked", "steamed", "braised", "poached", "stewed"] {
            XCTAssertFalse(FoodPreparationDiscoveryPolicy.accepts(requested: try PreparationState(kind: .raw), actual: unknown, sourceName: "Porridge " + word, query: named), word)
        }
        XCTAssertTrue(FoodPreparationDiscoveryPolicy.accepts(requested: try PreparationState(kind: .cooked), actual: unknown, sourceName: "Porridge rawhide", query: named))
        XCTAssertEqual(unknown.kind, .unknown)
    }
}
