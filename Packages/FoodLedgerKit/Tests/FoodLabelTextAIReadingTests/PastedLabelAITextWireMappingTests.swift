@testable import FoodLabelPhotoReading
@testable import FoodLabelTextAIReading
import FoodLedgerApplication
import Foundation
import NutritionLabelParsing
import XCTest

/// `pasted-label-ai-text-mapping-v1` (docs/pasted-label-ai-text-v1.md 4.2, 4.3 item 2, D10, D16;
/// contract tests 9 and 26; A1 finding F9).
final class PastedLabelAITextWireMappingTests: XCTestCase {
    typealias Mapping = PastedLabelAITextWireMapping
    static let sha = String(repeating: "ab", count: 32)

    // MARK: Test 26: parseValue parity with the photo copy

    static let parityVectors = [
        "5g", "5 g", "0.5g", "0,5g", "<0.5g", "< 0.5 g", "<=1g", "≤1g", "＜0.5公克", "少於5毫克", "less than 0.5 g", "250kcal", "1046kJ", "1046 KJ",
        "1046kj", "150大卡", "10.0公克", "100毫克", "5 mg", "12mcg", "12 µg", "12μg", "200ml", "200 mL", "13%", "5g (g)", "5 g（g）", "250kcal (kcal)",
        "5", "unknown", "trace", "-", "5gg", "5 g g", "g5", "", " 5g ", "５g", "٥g", "5.5.5g", "1.046,5g", "<", "less than", "５０公克", "5千卡",
        "5 微克", "5毫升", "5克", "5 grams", "5%RI", "0g*", "Fat 5g",
    ]

    func testParseValueMatchesThePhotoCopyOutsideTheThousandsRule() {
        for printed in Self.parityVectors {
            let photo = LabelPhotoWireMapping.parseValue(printed)
            let text = Mapping.parseValue(printed)
            switch (photo, text) {
            case (nil, .notAValue): break
            case let (photo?, .value(text)):
                XCTAssertEqual(photo.comparator, text.comparator, printed)
                XCTAssertEqual(photo.decimalText, text.decimalText, printed)
                XCTAssertEqual(photo.unit, text.unit, printed)
                XCTAssertEqual(photo.canonicalUnit, text.canonicalUnit, printed)
            default: XCTFail("\(printed): photo \(String(describing: photo)), text \(text)")
            }
        }
    }

    func testTheClosedListsAreThePhotoCopysLists() {
        XCTAssertEqual(PastedLabelAITextValueGrammar.units, LabelPhotoWireMapping.units)
        XCTAssertEqual(PastedLabelAITextValueGrammar.valueUnits, LabelPhotoWireMapping.valueUnits)
        XCTAssertEqual(PastedLabelAITextValueGrammar.echoUnits, LabelPhotoWireMapping.echoUnits)
        XCTAssertEqual(Mapping.comparators.map(\.0), LabelPhotoWireMapping.comparators.map(\.0))
        XCTAssertEqual(Mapping.comparators.map(\.1), LabelPhotoWireMapping.comparators.map(\.1))
    }

    /// The one documented difference: a thousands separator. The photo copy reads `1,046kJ` as 1.046.
    func testTheThousandsRule() {
        for (printed, decimal) in [("1,046kJ", "1046"), ("1,046 kJ", "1046"), ("1,046.5kJ", "1046.5"), ("12,500mg", "12500"), ("<1,000mg", "1000")] {
            guard case let .value(parsed) = Mapping.parseValue(printed) else { return XCTFail(printed) }
            XCTAssertEqual(parsed.decimalText, decimal, printed)
            XCTAssertNotEqual(LabelPhotoWireMapping.parseValue(printed)?.decimalText, decimal, "\(printed): the photo copy differs here")
        }
        for printed in ["0,500g", "0,500 g", "00,500g", "<0,500g"] {
            XCTAssertEqual(Mapping.parseValue(printed), .thousandsLedByZero, printed)
        }
        // Not a thousands group: four digits, or two, after the comma; a decimal comma stays one.
        guard case let .value(comma) = Mapping.parseValue("0,5g"), case let .value(four) = Mapping.parseValue("1,0465g") else { return XCTFail() }
        XCTAssertEqual(comma.decimalText, "0,5")
        XCTAssertEqual(four.decimalText, "1,0465")
    }

    // MARK: Mapping vectors

    static func wire(header: String = "Per 100g", basis: String = "per_100g", label: String = "Fat", nutrient: String = "fat",
                     printed: String, unit: String? = nil) -> PastedLabelAITextWire {
        PastedLabelAITextWire(declined: false, declineReasons: [], language: "en", servingSizeText: "unknown", servingsPerPackText: "unknown",
                              headers: [.init(headerID: "h1", printedText: header, basis: basis)],
                              rows: [.init(printedLabel: label, nutrient: nutrient, parentNutrient: "none",
                                           values: [.init(headerID: "h1", printedText: printed, unit: unit)])])
    }

    func mapped(_ text: String, _ wire: PastedLabelAITextWire) -> Mapping.Mapped { Mapping.map(wire, text: text, inputSHA256: Self.sha) }

    func testABareNumberWithoutAUnitIsNeverAValue() {
        let result = mapped("Per 100g\nFat 5", Self.wire(printed: "5"))
        XCTAssertEqual(result.candidate.cells, [])
        XCTAssertEqual(result.values.map(\.read), [.notRead(.bareNumberWithoutUnit)])
        XCTAssertEqual(result.values[0].reasons, [], "a not-read cell, not an attention item (F9)")
        XCTAssertEqual(result.values[0].unitCheck, .missing)
        XCTAssertFalse(result.candidate.wouldMarkReady)
    }

    func testAThousandsGroupLedByZeroIsAnAttentionItemNever500() {
        let result = mapped("Per 100g\nFat 0,500g", Self.wire(printed: "0,500g"))
        XCTAssertEqual(result.candidate.cells, [])
        XCTAssertEqual(result.values.map(\.read), [.notRead(.thousandsLedByZero)])
        XCTAssertEqual(result.values[0].reasons, [.ambiguous])
    }

    func testTheModelsUnitIsAcceptedOnlyWhereTheTextStatesIt() throws {
        // Stated in the row label.
        var result = mapped("Per 100g\nFat (g) 5", Self.wire(label: "Fat (g)", printed: "5", unit: "g"))
        XCTAssertEqual(result.values[0].unitCheck, .statedInRowLabel)
        XCTAssertEqual(result.values[0].reasons, [])
        let cell = try XCTUnwrap(result.candidate.cells.first)
        XCTAssertEqual([cell.decimalText, cell.unit, cell.canonicalUnit], ["5", "g", "g"])
        // Stated in the header.
        result = mapped("Fat\t(g)\nFat 5", Self.wire(header: "(g)", printed: "5", unit: "g"))
        XCTAssertEqual(result.values[0].unitCheck, .statedInHeader)
        // A basis quantity never states a unit (D16): read, under attention.
        result = mapped("Per 100 g\nFat 5", Self.wire(header: "Per 100 g", printed: "5", unit: "g"))
        XCTAssertEqual(result.values[0].unitCheck, .notStated)
        XCTAssertEqual(result.values[0].reasons, [.unitNotStated])
        XCTAssertEqual(result.candidate.cells.map(\.canonicalUnit), ["g"])
        // The row label states another unit than the model's.
        result = mapped("Per 100g\nSodium (mg) 5", Self.wire(label: "Sodium (mg)", nutrient: "sodium", printed: "5", unit: "g"))
        XCTAssertEqual(result.values[0].reasons, [.unitNotStated])
        // A unit outside the closed table cannot be read.
        result = mapped("Per 100g\nFat (grams) 5", Self.wire(label: "Fat (grams)", printed: "5", unit: "grams"))
        XCTAssertEqual(result.values.map(\.read), [.notRead(.unitOutsideTable)])
        XCTAssertEqual(result.values[0].reasons, [.unitNotStated])
    }

    func testAPrintedUnitIsNeverOverridden() throws {
        let result = mapped("Per 100g\nFat 5g", Self.wire(printed: "5g", unit: "mg"))
        XCTAssertEqual(result.values[0].unitCheck, .conflict)
        XCTAssertEqual(result.values[0].reasons, [.unitNotStated])
        XCTAssertEqual(try XCTUnwrap(result.candidate.cells.first).canonicalUnit, "g")
    }

    func testAnAbsoluteValueInAReferenceIntakeColumnIsNotRead() {
        let result = mapped("%RI\nFat 5g", Self.wire(header: "%RI", basis: "reference_intake", printed: "5g"))
        XCTAssertEqual(result.values.map(\.read), [.notRead(.absoluteReferenceValue)])
    }

    // MARK: Test 9: parity with label-photo-wire-mapping-v1 where a unit is printed

    func testParityWithThePhotoMappingWhereAUnitIsPrinted() {
        let tables: [PastedLabelAITextWire] = [
            PastedLabelAITextWire(declined: false, declineReasons: [], language: "en", servingSizeText: "30g", servingsPerPackText: "about 8 servings",
                headers: [.init(headerID: "h1", printedText: "Per 100g", basis: "per_100g"), .init(headerID: "h2", printedText: "Per 30g serving", basis: "per_serving"),
                          .init(headerID: "h3", printedText: "%RI", basis: "reference_intake")],
                rows: [.init(printedLabel: "Energy", nutrient: "energy_kj", parentNutrient: "none", values: [.init(headerID: "h1", printedText: "1046kJ"), .init(headerID: "h2", printedText: "314kJ")]),
                       .init(printedLabel: "Fat", nutrient: "fat", parentNutrient: "none", values: [.init(headerID: "h1", printedText: "9.5g"), .init(headerID: "h2", printedText: "2.9g"), .init(headerID: "h3", printedText: "4%")]),
                       .init(printedLabel: "of which saturates", nutrient: "saturates", parentNutrient: "fat", values: [.init(headerID: "h1", printedText: "<0.1g"), .init(headerID: "h2", printedText: "unknown")]),
                       .init(printedLabel: "Salt", nutrient: "salt", parentNutrient: "none", values: [.init(headerID: "h1", printedText: "0,75g"), .init(headerID: "h9", printedText: "0.2g")])]),
            PastedLabelAITextWire(declined: false, declineReasons: [], language: "zh-Hant", servingSizeText: "30 公克", servingsPerPackText: "約 8 份",
                headers: [.init(headerID: "h1", printedText: "每份", basis: "per_serving"), .init(headerID: "h1", printedText: "每份", basis: "per_serving")],
                rows: [.init(printedLabel: "鈉", nutrient: "sodium", parentNutrient: "none", values: [.init(headerID: "h1", printedText: "少於5毫克")]),
                       .init(printedLabel: "其他", nutrient: "unrecognised", parentNutrient: "none", values: [.init(headerID: "h1", printedText: "1公克")])]),
            PastedLabelAITextWire(declined: true, declineReasons: ["not_a_label"], language: "unknown", servingSizeText: "", servingsPerPackText: "",
                                  headers: [], rows: []),
        ]
        for table in tables {
            let photo = LabelPhotoWireMapping.map(LabelPhotoWire(declined: table.declined, declineReasons: table.declineReasons, language: table.language,
                servingSizeText: table.servingSizeText, servingsPerPackText: table.servingsPerPackText,
                headers: table.headers.map { .init(headerID: $0.headerID, printedText: $0.printedText, basis: $0.basis) },
                rows: table.rows.map { row in .init(printedLabel: row.printedLabel, nutrient: row.nutrient, parentNutrient: row.parentNutrient,
                                                    values: row.values.map { .init(headerID: $0.headerID, printedText: $0.printedText) }) }),
                inputSHA256: Self.sha)
            let text = Mapping.map(table, text: "", inputSHA256: Self.sha).candidate
            XCTAssertEqual(text.cells, photo.cells)
            XCTAssertEqual(text.headers, photo.headers)
            XCTAssertEqual(text.servingSize, photo.servingSize)
            XCTAssertEqual(text.servingsPerPack, photo.servingsPerPack)
            XCTAssertEqual(text.declined, photo.declined)
            XCTAssertEqual(text.declineReasons, photo.declineReasons)
            XCTAssertEqual(text.wouldMarkReady, photo.wouldMarkReady)
            // Warnings name the same findings; the unread value's wording is the text route's own.
            XCTAssertEqual(text.warnings.map { $0.components(separatedBy: " ").first! }, photo.warnings.map { $0.components(separatedBy: " ").first! })
        }
    }
}
