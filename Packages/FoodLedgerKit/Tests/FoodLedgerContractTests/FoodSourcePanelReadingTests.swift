import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

final class FoodSourcePanelReadingTests: XCTestCase {
    private func panels(_ html: String) throws -> [FoodSourceNutritionPanel] {
        try FoodSourceDocumentPanelReader.panels(HTMLFoodSourceTableProjector.project(Data(html.utf8)), documentID: "captured-document", recordID: "selected-record")
    }
    private func row(_ label: String, _ value: String) -> String { "<tr><th>" + label + "</th><td>" + value + "</td></tr>" }
    private func full(_ basis: String = "per 100 g") -> String {
        row("Typical values", basis) + row("Energy", "400 kJ / 92.0 kcal") + row("Fat", "3 g")
            + row("Carbohydrate", "12 g") + row("Protein", "5 g")
    }
    func testCompletePanelRetainsOriginalDecimalsCoordinatesAndBasis() throws {
        let result = try panels("<table>" + full() + "</table>")
        XCTAssertEqual(result.count, 1); XCTAssertTrue(result[0].hasFourMacros)
        XCTAssertEqual(result[0].declarations.map(\.declaredLiteral), ["92.0", "3", "12", "5"])
        XCTAssertEqual(result[0].declarations.map(\.value.amount), [92, 3, 12, 5])
        XCTAssertTrue(result[0].declarations.allSatisfy { $0.value.basis == .per100Grams })
        XCTAssertEqual(result[0].source.basisCell?.row, 1)
    }
    func testSplitIncompletePanelsAreNeverMerged() throws {
        let first = row("Typical values", "per 100 g") + row("Energy", "92 kcal") + row("Protein", "5 g")
        let second = row("Typical values", "per 100 g") + row("Fat", "3 g") + row("Carbohydrate", "12 g")
        for separator in ["", "</table><table>"] {
            let result = try panels("<table>" + first + separator + second + "</table>")
            XCTAssertEqual(result.count, 2)
            XCTAssertTrue(result.allSatisfy { !$0.hasFourMacros && $0.declarations.count == 2 })
            XCTAssertNotEqual(result[0].source.basisCell, result[1].source.basisCell)
            XCTAssertEqual(result[0].source.sha256, result[1].source.sha256)
        }
    }
    func testMassAndVolumeProfilesRemainSeparateAlternatives() throws {
        let result = try panels("<table>" + full("per 100 g") + full("per 100 ml") + "</table>")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].declarations.first?.value.basis, .per100Grams)
        XCTAssertEqual(result[1].declarations.first?.value.basis, .per100Millilitres)
        XCTAssertEqual(result[0].source.basisCell?.row, 1); XCTAssertEqual(result[1].source.basisCell?.row, 6)
    }
    func testHeadingStopsReadingAndLaterValuesCannotBackfill() throws {
        for heading in [row("Prepared", "with water"), row("Product", "different"), row("Protein", "per serving")] {
            let html = "<table>" + row("Typical values", "per 100 g") + row("Energy", "92 kcal") + heading
                + row("Fat", "3 g") + row("Carbohydrate", "12 g") + row("Protein", "5 g") + "</table>"
            let result = try panels(html)
            XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].declarations.map(\.field), [.energyConsumed])
        }
    }
    func testDuplicateNutrientStartsBoundaryWithoutOverwritingEarlierValue() throws {
        let html = "<table>" + row("Typical values", "per 100 g") + row("Energy", "92 kcal")
            + row("Energy", "150 kcal") + row("Fat", "3 g") + "</table>"
        let result = try panels(html)
        XCTAssertEqual(result[0].declarations.map(\.value.amount), [92])
    }
    func testUnsupportedServingBoundsUnitsAndMalformedSegmentRowsAreNotInvented() throws {
        XCTAssertTrue(try panels("<table>" + full("per serving") + "</table>").isEmpty)
        for value in ["&lt;92 kcal", "92%", "92 kJ", "92 g", "NaN kcal"] {
            let html = "<table>" + row("Typical values", "per 100 g") + row("Energy", value) + row("Protein", "5 g") + "</table>"
            XCTAssertTrue(try panels(html).isEmpty)
        }
        let html = "<table>" + row("Typical values", "per 100 g") + "<tr><th>Energy<br>Protein</th><td>92 kcal</td></tr></table>"
        XCTAssertTrue(try panels(html).isEmpty)
    }
    func testCapturedAlproIsReadWithoutModelProposedNumbersOrCoordinates() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "alpro-source-table-v7", withExtension: "json", subdirectory: "Fixtures"))
        let result = try FoodSourceDocumentPanelReader.panels(Data(contentsOf: url), documentID: "alpro-capture", recordID: "selected-alpro")
        XCTAssertEqual(result.count, 1); XCTAssertTrue(result[0].hasFourMacros)
        XCTAssertEqual(result[0].declarations.map(\.value.amount), [42, 1.9, 2.7, 3.3])
        XCTAssertTrue(result[0].declarations.allSatisfy { $0.value.basis == .per100Millilitres })
        XCTAssertFalse(result[0].declarations.contains { $0.field == .sodium })
    }
    func testMoreThanThirtyTwoPanelsAndInvalidTableIdentityAreRejected() throws {
        let html = "<table>" + String(repeating: row("Typical values", "per 100 g") + row("Energy", "92 kcal"), count: 33) + "</table>"
        XCTAssertThrowsError(try panels(html))
        let projection = Data(#"{"version":"table-preserving-source-v7","tables":[{"id":2,"rows":[]}]}"#.utf8)
        XCTAssertThrowsError(try FoodSourceDocumentPanelReader.panels(projection, documentID: "doc", recordID: "record"))
    }
}
