import FoodLedgerApplication
@testable import FoodLabelPhotoReading
import XCTest

/// docs/pasted-label-ai-text-v1.md 4.2 and 11.1: the text route's closed comparator and unit
/// lists, held in the application layer, equal the lists of `label-photo-wire-mapping-v1`. The
/// photo lists are internal to a pinned file, so this test lives in the photo reader's own test
/// target, which may import both. The thousands-separator rule is a token-grammar rule of the
/// text locator, not a list, so it is outside this parity by construction (4.3 item 2).
final class PastedLabelAITextClosedListParityTests: XCTestCase {
    func testUnitTableEqualsThePhotoMapping() {
        XCTAssertEqual(PastedLabelAITextValueGrammar.units, LabelPhotoWireMapping.units)
    }

    func testValueUnitsEqualThePhotoMappingInOrder() {
        XCTAssertEqual(PastedLabelAITextValueGrammar.valueUnits, LabelPhotoWireMapping.valueUnits)
        XCTAssertEqual(PastedLabelAITextValueGrammar.echoUnits, LabelPhotoWireMapping.echoUnits)
    }

    func testComparatorsEqualThePhotoMappingInOrder() {
        XCTAssertEqual(PastedLabelAITextValueGrammar.comparators.map(\.printed), LabelPhotoWireMapping.comparators.map(\.0))
        XCTAssertEqual(PastedLabelAITextValueGrammar.comparators.map(\.value), LabelPhotoWireMapping.comparators.map(\.1.rawValue))
    }

    func testCanonicalLookupAgrees() {
        for unit in LabelPhotoWireMapping.valueUnits + ["KCAL", "Mg", "ML", "unknown"] {
            XCTAssertEqual(PastedLabelAITextValueGrammar.canonicalUnit(unit), LabelPhotoWireMapping.canonical(unit), unit)
        }
    }
}
