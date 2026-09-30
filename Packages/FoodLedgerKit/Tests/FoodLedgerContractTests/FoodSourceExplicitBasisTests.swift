import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

final class FoodSourceExplicitBasisTests: XCTestCase {
    private let values = [("Energy", "257kJ/61kcal"), ("Fat", "3.0g"), ("Carbohydrates", "7.1g"), ("Protein", "1.1g")]
    private func rows() -> String { values.map { "<tr><td>\($0.0)</td><td>\($0.1)</td></tr>" }.joined() }
    private func caption(_ basis: String = "Nutrition information per 100ml:,") -> String {
        "<table><caption>" + basis + "</caption>" + rows() + "</table>"
    }
    private func inline() -> String {
        "<table>" + values.map { "<tr><td><span>\($0.0)</span><div>per 100 G \($0.1)</div></td></tr>" }.joined() + "</table>"
    }
    private func panels(_ html: String) throws -> [FoodSourceNutritionPanel] {
        try FoodSourceDocumentPanelReader.panels(HTMLFoodSourceTableProjector.project(Data(html.utf8)), documentID: "captured", recordID: "record")
    }

    func testCaptionPreservesActualLocationUnitsAndOriginalLiteralWithoutInventedCell() throws {
        let panel = try XCTUnwrap(panels(caption()).first)
        XCTAssertTrue(panel.hasFourMacros); XCTAssertNil(panel.source.basisCell)
        XCTAssertEqual(panel.source.basisLocation, .caption(table: 1, index: 1))
        XCTAssertEqual(panel.declarations.map(\.declaredLiteral), ["61", "3.0", "7.1", "1.1"])
        XCTAssertEqual(panel.declarations.map(\.value.amount), [61, 3, 7.1, 1.1])
        XCTAssertTrue(panel.declarations.allSatisfy { $0.value.basis == .per100Millilitres && $0.basisCell == nil && $0.bindingVersion == FoodSourceExplicitBasisBinding.version })
        XCTAssertEqual(panel.declarations[0].sourceCell, .init(table: 1, row: 1, cell: 2, segment: 1))
        let location = try JSONDecoder().decode(FoodSourceBasisLocation.self, from: JSONEncoder().encode(panel.source.basisLocation))
        XCTAssertEqual(location, panel.source.basisLocation)
    }

    func testEachInlineValueRetainsItsOwnDeclaredDenominatorLocation() throws {
        let panel = try XCTUnwrap(panels(inline()).first)
        XCTAssertTrue(panel.hasFourMacros); XCTAssertNil(panel.source.basisCell)
        XCTAssertTrue(panel.declarations.allSatisfy { $0.value.basis == .per100Grams })
        for (index, value) in panel.declarations.enumerated() {
            let actual = FoodSourceCell(table: 1, row: index + 1, cell: 1, segment: 2)
            XCTAssertEqual(value.sourceCell, actual); XCTAssertEqual(value.basisLocation, .inline(actual))
        }
    }

    func testMissingDuplicateAndConflictingCaptionsCannotSupplyBasis() throws {
        XCTAssertTrue(try panels("<table>" + rows() + "</table>").isEmpty)
        for extra in ["Nutrition information per 100ml:,", "Nutrition information per 100g", "Prepared with water"] {
            let html = caption().replacingOccurrences(of: "</caption>", with: "</caption><caption>" + extra + "</caption>")
            XCTAssertTrue(try panels(html).isEmpty)
        }
        for unsupported in ["per serving", "Nutrition information per 30ml", "Nutrition information per 100ml prepared", "Nutrition information per 100g or 100ml", ""] {
            XCTAssertTrue(try panels(caption(unsupported)).isEmpty)
        }
    }

    func testCaptionCannotOverrideAnyCompetingHeaderOrInlineLayout() throws {
        for header in ["per 100 ml", "per 100 g", "per serving"] {
            let row = "<tr><th>Typical values</th><td>\(header)</td></tr>"
            for html in [caption().replacingOccurrences(of: "</caption>", with: "</caption>" + row), caption().replacingOccurrences(of: "</table>", with: row + "</table>")] {
                XCTAssertTrue(try panels(html).isEmpty)
            }
        }
        XCTAssertTrue(try panels(inline().replacingOccurrences(of: "<table>", with: "<table><caption>Nutrition information per 100 g</caption>")).isEmpty)
    }

    func testInlineMixedMissingAndUnsupportedDenominatorsAreNotCombined() throws {
        for replacement in ["per 100 ml 3.0g", "3.0g", "per serving 3.0g", "per 30 G 3.0g", "per 100 G prepared 3.0g"] {
            XCTAssertTrue(try panels(inline().replacingOccurrences(of: "per 100 G 3.0g", with: replacement)).isEmpty)
        }
        XCTAssertTrue(try panels(inline().replacingOccurrences(of: "<div>", with: "").replacingOccurrences(of: "</div>", with: "")).isEmpty)
    }

    func testDuplicateNutrientsAndAmbiguousSegmentsDoNotBecomeCompleteProfiles() throws {
        for html in [caption().replacingOccurrences(of: "</table>", with: "<tr><td>Carbohydrate</td><td>99g</td></tr></table>"),
                     inline().replacingOccurrences(of: "</table>", with: "<tr><td>Fat<div>per 100 G 99g</div></td></tr></table>"),
                     caption().replacingOccurrences(of: "3.0g", with: "3.0g<br>5.0g"),
                     inline().replacingOccurrences(of: "3.0g", with: "3.0g<br>5.0g"),
                     caption().replacingOccurrences(of: "<td>Fat", with: "<td colspan='2'>Fat")] {
            XCTAssertTrue(try panels(html).isEmpty)
        }
    }

    func testSectionHeadingStopsCaptionBeforeLaterValuesAndCannotBackfill() throws {
        let html = caption().replacingOccurrences(of: "<tr><td>Fat", with: "<tr><td>Product</td><td>Different food</td></tr><tr><td>Fat")
        let result = try panels(html)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].declarations.map(\.field), [.energyConsumed])
    }

    func testBoundsWrongUnitsAndUnrepresentableValuesAreRejected() throws {
        for value in ["&lt;3.0g", "3%", "3mg", "NaNg", "9007199254740993g"] {
            XCTAssertTrue(try panels(caption().replacingOccurrences(of: "3.0g", with: value)).isEmpty)
            XCTAssertTrue(try panels(inline().replacingOccurrences(of: "3.0g", with: value)).isEmpty)
        }
    }

    func testClaimsCannotChangeSourceBasisCoordinatesLiteralOrAmount() throws {
        for html in [caption(), inline()] {
            let panel = try XCTUnwrap(panels(html).first)
            let value = panel.declarations[1]
            func claim(hash: String? = nil, literal: String? = nil, amount: Double? = nil, unit: String = "g", basis: ResolutionBasis? = nil, cell: FoodSourceCell? = nil) -> FoodSourceNutrientClaim {
                .init(documentID: value.documentID, recordID: value.recordID, sha256: hash ?? value.sha256,
                    field: value.field, amount: amount ?? value.value.amount, unit: unit, basis: basis ?? value.value.basis,
                    declaredLiteral: literal ?? value.declaredLiteral, sourceCell: cell ?? value.sourceCell)
            }
            XCTAssertEqual(try FoodSourceExplicitBasisBinding.bind([claim()], to: panel.source), [value])
            for wrong in [claim(hash: String(repeating: "0", count: 64)), claim(literal: "3"), claim(amount: 4), claim(unit: "mg"),
                          claim(basis: value.value.basis == .per100Grams ? .per100Millilitres : .per100Grams),
                          claim(cell: .init(table: 2, row: 2, cell: 1, segment: 1))] {
                XCTAssertThrowsError(try FoodSourceExplicitBasisBinding.bind([wrong], to: panel.source))
            }
            XCTAssertThrowsError(try FoodSourceNutritionBinding.bind([claim()], to: panel.source))
            XCTAssertThrowsError(try FoodSourceExplicitBasisBinding.bind([claim(), claim()], to: panel.source))
        }
    }

    @MainActor
    func testCancelledReaderCannotPublishAnEmptySuccess() async throws {
        let projection = try HTMLFoodSourceTableProjector.project(Data(caption().utf8))
        let task = Task { try FoodSourceDocumentPanelReader.panels(projection, documentID: "doc", recordID: "record") }
        task.cancel()
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSeparateCaptionTablesRetainSeparateMassAndVolumeProvenance() throws {
        let result = try panels(caption() + caption("Nutrition information per 100g"))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].declarations.first?.value.basis, .per100Millilitres)
        XCTAssertEqual(result[1].declarations.first?.value.basis, .per100Grams)
        XCTAssertEqual(result[1].source.basisLocation, .caption(table: 2, index: 1))
        XCTAssertTrue(result[1].declarations.allSatisfy { $0.sourceCell.table == 2 })
    }
}
