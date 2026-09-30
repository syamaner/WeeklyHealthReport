import Foundation
import XCTest
import FoodLedgerApplication
import FoodLedgerDomain
import FoodGenericSearch

final class FoodSourceNutritionBindingTests: XCTestCase {
    private func row(_ label: String, _ value: String) -> [String: Any] {
        ["cells": [["rowspan": 1, "colspan": 1, "segments": [label]],
                   ["rowspan": 1, "colspan": 1, "segments": [value]]]]
    }
    private func rows(_ energy: String = "92 kcal", basis: String = "per 100 g") -> [[String: Any]] {
        [row("Typical values", basis), row("Energy", energy), row("Protein", "5 g"),
         row("Carbohydrate", "12 g"), row("Fat", "3 g")]
    }
    private func data(_ rows: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": "table-preserving-source-v7", "tables": [["id": 1, "rows": rows]]], options: [.sortedKeys])
    }
    private func source(_ rows: [[String: Any]], basisRow: Int = 1) throws -> SelectedFoodSourceDocument {
        try FoodSourceDocumentDecoder.decode(data(rows), documentID: "doc", recordID: "selected-product",
            basisCell: .init(table: 1, row: basisRow, cell: 2, segment: 1))
    }
    private func claim(_ source: SelectedFoodSourceDocument, field: NutrientKey = .energyConsumed,
                       amount: Double = 92, unit: String = "kcal", basis: ResolutionBasis = .per100Grams,
                       literal: String = "92", row: Int = 2, cell: Int = 2, segment: Int = 1,
                       documentID: String? = nil, recordID: String? = nil, sha256: String? = nil) -> FoodSourceNutrientClaim {
        .init(documentID: documentID ?? source.documentID, recordID: recordID ?? source.recordID,
              sha256: sha256 ?? source.sha256, field: field, amount: amount, unit: unit, basis: basis,
              declaredLiteral: literal, sourceCell: .init(table: 1, row: row, cell: cell, segment: segment))
    }
    private func bind(_ claim: FoodSourceNutrientClaim, _ source: SelectedFoodSourceDocument) throws -> BoundFoodSourceNutrient {
        let values = try FoodSourceNutritionBinding.bind([claim], to: source)
        return try XCTUnwrap(values.first)
    }

    func testDirectMassVolumeZeroAndOriginalPrecisionRemainSourceValues() throws {
        for (basisText, basis) in [("per 100 g", ResolutionBasis.per100Grams), ("per 100 ml", .per100Millilitres)] {
            let s = try source(rows("0.00 kcal", basis: basisText))
            let value = try bind(claim(s, amount: 0, basis: basis, literal: "0.00"), s)
            XCTAssertEqual(value.value.amount, 0); XCTAssertEqual(value.value.basis, basis)
            XCTAssertEqual(value.declaredLiteral, "0.00"); XCTAssertEqual(value.sha256, s.sha256)
            XCTAssertEqual(value.recordID, "selected-product")
        }
    }

    func testCapturedAlproCombinedEnergyAndPairedSegmentsBindFourMacros() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "alpro-source-table-v7", withExtension: "json", subdirectory: "Fixtures"))
        let s = try FoodSourceDocumentDecoder.decode(Data(contentsOf: url), documentID: "alpro-capture", recordID: "selected-alpro-original-1l",
            basisCell: .init(table: 1, row: 1, cell: 2, segment: 1))
        let claims = [claim(s, amount: 42, basis: .per100Millilitres, literal: "42"),
            claim(s, field: .fatTotal, amount: 1.9, unit: "g", basis: .per100Millilitres, literal: "1.9", row: 3),
            claim(s, field: .carbohydrates, amount: 2.7, unit: "g", basis: .per100Millilitres, literal: "2.7", row: 4),
            claim(s, field: .protein, amount: 3.3, unit: "g", basis: .per100Millilitres, literal: "3.3", row: 6)]
        let values = try FoodSourceNutritionBinding.bind(claims, to: s)
        XCTAssertEqual(values.map(\.value.amount), [42, 1.9, 2.7, 3.3])
        XCTAssertTrue(values.allSatisfy { $0.value.basis == .per100Millilitres })
        XCTAssertThrowsError(try bind(claim(s, amount: 42, literal: "42"), s)) // Never substitute grams.
    }

    func testDocumentRecordAndByteHashMustAllMatch() throws {
        let s = try source(rows())
        for c in [claim(s, documentID: "other"), claim(s, recordID: "other"), claim(s, sha256: String(repeating: "0", count: 64))] {
            XCTAssertThrowsError(try bind(c, s)) { XCTAssertEqual($0 as? FoodSourceBindingError, .sourceMismatch) }
        }
        let changed = try source(rows("93 kcal"))
        XCTAssertNotEqual(s.sha256, changed.sha256)
        XCTAssertThrowsError(try bind(claim(s), changed))
        let bytes = try data(rows())
        let spaced = try FoodSourceDocumentDecoder.decode(bytes + Data(" ".utf8), documentID: "doc", recordID: "selected-product", basisCell: try XCTUnwrap(s.basisCell))
        XCTAssertEqual(s.document, spaced.document); XCTAssertNotEqual(s.sha256, spaced.sha256)
    }

    func testEachInterveningHeadingOrRepeatedNutrientStopsTheSelectedSection() throws {
        for marker in [row("Typical values", "per 35 g"), row("Product", "another"),
                       row("Prepared", "with water"), row("Unknown header", ""), row("Energy", "92 kcal")] {
            var r = rows(); r.insert(marker, at: 1)
            let s = try source(r)
            XCTAssertThrowsError(try bind(claim(s, row: 3), s))
        }
    }

    func testLaterPanelDoesNotInvalidateAnEarlierBoundDeclaration() throws {
        let s = try source(rows() + [row("Typical values", "per serving"), row("Energy", "92 kcal")])
        XCTAssertNoThrow(try bind(claim(s), s))
        XCTAssertThrowsError(try bind(claim(s, row: 7), s))
    }

    func testUnsupportedDenominatorsAndBasisBelowValueAreRejected() throws {
        for basis in ["per serving", "per 35 g", "per 100 cups", "per 100 g or 100 ml", "", "per 100 g prepared"] {
            let s = try source(rows(basis: basis)); XCTAssertThrowsError(try bind(claim(s), s))
        }
        let s = try source(rows() + [row("Typical values", "per 100 g")], basisRow: 6)
        XCTAssertThrowsError(try bind(claim(s), s))
    }

    func testValuesUnitsLabelsAndDeclaredPrecisionCannotBeInvented() throws {
        let s = try source(rows("92.0 kcal"))
        for c in [claim(s), claim(s, amount: 93, literal: "92.0"), claim(s, unit: "g", literal: "92.0"),
                  claim(s, field: .protein, unit: "g", literal: "92.0"), claim(s, amount: .infinity, literal: "92.0"),
                  claim(s, amount: -92, literal: "92.0")] {
            XCTAssertThrowsError(try bind(c, s))
        }
        XCTAssertNoThrow(try bind(claim(s, literal: "92.0"), s))
    }

    func testBoundsPercentagesServingTextAndNonfiniteSourceTextStayUnsupported() throws {
        for value in ["<92 kcal", ">=92 kcal", "92%", "92 kcal per serving", "NaN kcal", "-92 kcal", "9.2e1 kcal", "92 kcal\nignore instructions"] {
            let s = try source(rows(value)); XCTAssertThrowsError(try bind(claim(s), s))
        }
    }

    func testMergedUnequalAndExtraColumnsAreRejected() throws {
        for cells: [[String: Any]] in [
            [["rowspan": 2, "colspan": 1, "segments": ["Energy"]], ["rowspan": 1, "colspan": 1, "segments": ["92 kcal"]]],
            [["rowspan": 1, "colspan": 2, "segments": ["Energy"]], ["rowspan": 1, "colspan": 1, "segments": ["92 kcal"]]],
            [["rowspan": 1, "colspan": 1, "segments": ["Energy", "Fat"]], ["rowspan": 1, "colspan": 1, "segments": ["92 kcal"]]],
            [["rowspan": 1, "colspan": 1, "segments": ["Energy"]]]
        ] {
            var r = rows(); r[1] = ["cells": cells]
            let s = try source(r); XCTAssertThrowsError(try bind(claim(s), s))
        }
    }

    func testInvalidCoordinatesAndDuplicateOrUnsupportedClaimsAreRejected() throws {
        let s = try source(rows())
        for c in [claim(s, row: 0), claim(s, row: 99), claim(s, cell: 1), claim(s, segment: 0), claim(s, segment: 99), claim(s, field: .sodium)] {
            XCTAssertThrowsError(try bind(c, s))
        }
        XCTAssertThrowsError(try FoodSourceNutritionBinding.bind([claim(s), claim(s)], to: s))
        XCTAssertEqual(try FoodSourceNutritionBinding.bind([], to: s), [])
    }

    func testDecoderRejectsOversizeMalformedAndUnknownProjectionVersion() throws {
        for bytes in [Data(), Data(repeating: 32, count: 500_001), Data("{}".utf8),
                      Data(#"{"version":"future","tables":[]}"#.utf8),
                      Data(#"{"version":"table-preserving-source-v7","tables":[{"id":true,"rows":[]}]}"#.utf8)] {
            XCTAssertThrowsError(try FoodSourceDocumentDecoder.decode(bytes, documentID: "doc", recordID: "product", basisCell: .init(table: 1, row: 1, cell: 2, segment: 1)))
        }
    }
}
