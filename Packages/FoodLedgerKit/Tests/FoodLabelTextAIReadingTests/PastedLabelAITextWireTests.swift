@testable import FoodLabelTextAIReading
import Foundation
import XCTest

/// Contract test 16 (docs/pasted-label-ai-text-v1.md 4.2 and 11.5): the strict decoder of
/// `pasted-label-ai-text-wire-schema-v1`, with goldens, including the optional `unit` member.
final class PastedLabelAITextWireTests: XCTestCase {
    static func answer(values: String, extraTop: String = "", header: String = #""basis": "per_100g""#, row: String = #""nutrient": "fat""#) -> Data {
        Data("""
        {"declined": false, "decline_reasons": [], "language": "en", "serving_size_text": "unknown", "servings_per_pack_text": "unknown",\(extraTop)
         "headers": [{"header_id": "h1", "printed_text": "Per 100g", \(header)}],
         "rows": [{"printed_label": "Fat", \(row), "parent_nutrient": "none", "values": [\(values)]}]}
        """.utf8)
    }

    func testTheGoldenDecodesExactly() throws {
        let wire = try XCTUnwrap(PastedLabelAITextWire.decode(Self.answer(values: #"{"header_id": "h1", "printed_text": "5", "unit": "g"}"#)))
        XCTAssertEqual(wire, PastedLabelAITextWire(
            declined: false, declineReasons: [], language: "en", servingSizeText: "unknown", servingsPerPackText: "unknown",
            headers: [.init(headerID: "h1", printedText: "Per 100g", basis: "per_100g")],
            rows: [.init(printedLabel: "Fat", nutrient: "fat", parentNutrient: "none", values: [.init(headerID: "h1", printedText: "5", unit: "g")])]))
        XCTAssertEqual(PastedLabelAITextWire.schemaVersion, "pasted-label-ai-text-wire-schema-v1")
    }

    func testTheUnitMemberIsOptional() throws {
        for (values, expected) in [(#"{"header_id": "h1", "printed_text": "5g"}"#, nil),
                                   (#"{"header_id": "h1", "printed_text": "5g", "unit": null}"#, nil),
                                   (#"{"header_id": "h1", "printed_text": "5g", "unit": ""}"#, nil),
                                   (#"{"header_id": "h1", "printed_text": "5", "unit": "mg"}"#, "mg" as String?)] {
            let wire = try XCTUnwrap(PastedLabelAITextWire.decode(Self.answer(values: values)), values)
            XCTAssertEqual(wire.rows[0].values[0].unit, expected, values)
        }
    }

    /// Qodo finding 1 on A2: a member named twice in one object is refused, wherever it is, and
    /// names are compared after unescaping.
    func testDuplicateMembersAreRefused() {
        let valid = String(decoding: Self.answer(values: #"{"header_id": "h1", "printed_text": "5g"}"#), as: UTF8.self)
        XCTAssertNotNil(PastedLabelAITextWire.decode(Data(valid.utf8)))
        let duplicated = [
            valid.replacingOccurrences(of: #"{"declined": false,"#, with: #"{"declined": false, "declined": true,"#),
            valid.replacingOccurrences(of: #"{"declined": false,"#, with: #"{"declined": true, "\u0064eclined": false,"#),
            valid.replacingOccurrences(of: #""printed_text": "5g"}"#, with: #""printed_text": "5g", "printed_text": "50g"}"#),
            valid.replacingOccurrences(of: #""basis": "per_100g"}"#, with: #""basis": "per_100g", "basis": "per_100ml"}"#),
        ]
        for text in duplicated {
            XCTAssertNotEqual(text, valid)
            XCTAssertNil(PastedLabelAITextWire.decode(Data(text.utf8)), text)
        }
        XCTAssertTrue(JSONMemberScan.hasNoDuplicateMembers(Data(#"{"a": [{"b": 1}, {"b": 2}], "c": "{\"a\": 1, \"a\": 2}"}"#.utf8)),
                      "the same name in sibling objects, or inside a string, is not a duplicate")
        XCTAssertFalse(JSONMemberScan.hasNoDuplicateMembers(Data(#"{"a": 1"#.utf8)), "unscannable bytes fail closed")
    }

    func testAnythingOffTheSchemaIsRefused() {
        let refused: [Data] = [
            Self.answer(values: #"{"header_id": "h1", "printed_text": "5", "unit": 5}"#),
            Self.answer(values: #"{"header_id": "h1", "printed_text": "5", "unit": ["g"]}"#),
            Self.answer(values: #"{"header_id": "h1", "printed_text": "5", "units": "g"}"#),
            Self.answer(values: #"{"header_id": "h1"}"#),
            Self.answer(values: #"{"header_id": "h1", "printed_text": 5}"#),
            Self.answer(values: #"{"header_id": "h1", "printed_text": "5g"}"#, extraTop: #" "notes": "x","#),
            Self.answer(values: #"{"header_id": "h1", "printed_text": "5g"}"#, header: #""basis": "per_pack""#),
            Self.answer(values: #"{"header_id": "h1", "printed_text": "5g"}"#, header: #""basis": "per_100g", "unit": "g""#),
            Self.answer(values: #"{"header_id": "h1", "printed_text": "5g"}"#, row: #""nutrient": "vitamin_c""#),
            Data(#"{"declined": false}"#.utf8),
            Data("not json".utf8),
            Data(#"{"declined": false, "decline_reasons": [], "language": "fr", "serving_size_text": "", "servings_per_pack_text": "", "headers": [], "rows": []}"#.utf8),
        ]
        for data in refused {
            XCTAssertNil(PastedLabelAITextWire.decode(data), String(decoding: data, as: UTF8.self))
        }
    }
}
