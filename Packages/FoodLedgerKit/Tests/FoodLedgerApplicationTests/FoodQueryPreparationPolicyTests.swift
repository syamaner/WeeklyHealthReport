import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class FoodQueryPreparationPolicyTests: XCTestCase {
    func testNegatedMethodsDoNotBecomeAffirmativeDiscoveryConstraints() {
        for text in ["90g not grilled aubergine", "90g never boiled carrots", "90g non-roasted lamb", "90g not pan fried beef"] {
            let interpretation = FoodQueryInterpretation(text)
            XCTAssertTrue(interpretation.allowsDiscovery, text)
            XCTAssertNil(interpretation.preparation, text)
            XCTAssertEqual(interpretation.originalText, text)
        }
        XCTAssertEqual(FoodQueryInterpretation("87g raw lentils not cooked").preparation, .raw)
        XCTAssertEqual(FoodQueryInterpretation("90g grilled aubergine").preparation, .cooked)
    }

    func testCookingMethodsResolveCoarseStateAndRetainMethodWithoutInventingSourceFacts() throws {
        for word in ["boiled", "soft boiled", "pan-fried", "pan fried", "roasted", "grilled", "broiled", "fried", "baked", "steamed", "braised", "poached", "stewed"] {
            let parsed = FoodQueryParser.parse("90g \(word) broccoli")
            XCTAssertEqual(FoodQueryPreparationPolicy.kind(for: parsed), .cooked, word)
            let request = try GenericFoodSearchRequest(text: LedgerText(parsed.original), capturedAt: Date(timeIntervalSince1970: 0), locale: LedgerText("en_GB"))
            XCTAssertEqual(request.identity.preparation?.kind, .cooked, word)
            XCTAssertNil(request.identity.preparation?.method)
            XCTAssertTrue(request.retrievalText.contains(word.replacingOccurrences(of: " ", with: "-").split(separator: "-").last.map(String.init)!), word)
            XCTAssertEqual(parsed.quantity?.value, 90)
            XCTAssertEqual(request.text.value, parsed.original)
        }
        for word in ["raw", "uncooked"] {
            XCTAssertEqual(FoodQueryPreparationPolicy.kind(for: FoodQueryParser.parse("90g \(word) broccoli")), .raw)
        }
        for word in ["roast", "smoked", "freeze-dried", "fermented", "parboiled", "rawhide", "uncookedness", "roasting-pan"] {
            XCTAssertNil(FoodQueryPreparationPolicy.kind(for: FoodQueryParser.parse("90g \(word) broccoli")), word)
        }
        for query in ["90g raw boiled broccoli", "90g uncooked steamed broccoli"] {
            XCTAssertNil(FoodQueryPreparationPolicy.kind(for: FoodQueryParser.parse(query)))
        }
    }

    func testExplicitIdentityIsPreservedAndOnlyMissingPreparationIsResolved() throws {
        let identity = try GenericFoodIdentityQuery(bone: .boneless, skin: .skinless, servingBasis: .per100Grams,
            saltState: LedgerText("unsalted"), formulation: LedgerText("synthetic"))
        let request = try GenericFoodSearchRequest(text: LedgerText("90g boiled broccoli"), identity: identity,
            capturedAt: Date(timeIntervalSince1970: 0), locale: LedgerText("en_GB"))
        XCTAssertEqual(request.identity.preparation?.kind, .cooked)
        XCTAssertEqual(request.identity.bone, identity.bone)
        XCTAssertEqual(request.identity.skin, identity.skin)
        XCTAssertEqual(request.identity.servingBasis, identity.servingBasis)
        XCTAssertEqual(request.identity.saltState, identity.saltState)
        XCTAssertEqual(request.identity.formulation, identity.formulation)
        let explicit = try GenericFoodIdentityQuery(preparation: PreparationState(kind: .raw))
        let conflict = try GenericFoodSearchRequest(text: LedgerText("90g boiled broccoli"), identity: explicit,
            capturedAt: Date(timeIntervalSince1970: 0), locale: LedgerText("en_GB"))
        XCTAssertEqual(conflict.identity, explicit) // Coordinator rejects; never silently overrides.
    }
}
