import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

final class FoodSourceTableProjectionTests: XCTestCase {
    private func projection(_ html: String) throws -> FoodSourceTableDocument {
        let bytes = try HTMLFoodSourceTableProjector.project(Data(html.utf8))
        return try JSONDecoder().decode(FoodSourceTableDocument.self, from: bytes)
    }
    func testPairedSegmentsAndBlankPositionsRemainInTheirCells() throws {
        let doc = try projection("<table><tr><th>Fat<br>Saturates<br></th><td>1.1 g<br>0 g<br></td><td><br>A<br><br></td><td></td></tr></table>")
        let cells = doc.tables[0].rows[0].cells
        XCTAssertEqual(cells[0].segments, ["Fat", "Saturates", ""])
        XCTAssertEqual(cells[1].segments, ["1.1 g", "0 g", ""])
        XCTAssertEqual(cells[2].segments, ["", "A", "", ""])
        XCTAssertEqual(cells[3].segments, [""])
    }
    func testDifferentSegmentsAndMassVolumeColumnsAreNotZippedOrCollapsed() throws {
        let doc = try projection("<table><tr><th></th><th>per 100 g</th><th>per 100 ml</th></tr><tr><th>Fat<br>Saturates</th><td>3g</td><td>4g<br>2g</td></tr></table>")
        let row = doc.tables[0].rows[1]
        XCTAssertEqual(row.cells.map(\.segments), [["Fat", "Saturates"], ["3g"], ["4g", "2g"]])
        XCTAssertEqual(doc.tables[0].rows[0].cells[2].segments, ["per 100 ml"])
    }
    func testBlocksInlineFormattingAndEntitiesPreserveMeaning() throws {
        let doc = try projection("<table><tr><td><div>Typical values</div><p>Vitamin B<sub>12</sub> &lt;0.1g &amp; salt</p></td></tr></table>")
        XCTAssertEqual(doc.tables[0].rows[0].cells[0].segments, ["Typical values", "Vitamin B12 <0.1g & salt"])
    }
    func testScriptsStylesTemplatesAndNoscriptTextAreNotProjected() throws {
        let html = "<table><tr><td>Fat<script>invent99</script><style>invent98</style><template>invent97</template><noscript>invent96</noscript>1g</td></tr></table>"
        let projected = try HTMLFoodSourceTableProjector.project(Data(html.utf8))
        XCTAssertFalse(String(decoding: projected, as: UTF8.self).contains("invent"))
        let doc = try JSONDecoder().decode(FoodSourceTableDocument.self, from: projected)
        XCTAssertEqual(doc.tables[0].rows[0].cells[0].segments, ["Fat1g"])
    }
    func testSpansAndMultipleTableIDsArePreservedForLaterRejection() throws {
        let doc = try projection("<table><thead><tr><th rowspan='2'>Energy</th><td colspan='2'>Per 100g</td></tr></thead></table><table><tr><td>Other</td></tr></table>")
        XCTAssertEqual(doc.tables.map(\.id), [1, 2])
        XCTAssertEqual(doc.tables[0].rows[0].cells[0].rowspan, 2)
        XCTAssertEqual(doc.tables[0].rows[0].cells[1].colspan, 2)
    }
    func testNestedTablesInvalidSpansAndResourceExcessAreRejected() throws {
        for html in ["", "<p>No tables</p>",
            "<table><tr><td><table><tr><td>nested</td></tr></table></td></tr></table>",
            "<table><tr><td rowspan='0'>1g</td></tr></table>",
            "<table><tr><td colspan='-1'>1g</td></tr></table>",
            "<table><tr><td>" + String(repeating: "a<br>", count: 65) + "</td></tr></table>",
            String(repeating: "<table><tr><td>x</td></tr></table>", count: 33),
            "<table>" + String(repeating: "<tr><td>x</td></tr>", count: 257) + "</table>",
            "<p>" + String(repeating: "x", count: 2_000_001) + "</p>"] {
            XCTAssertThrowsError(try projection(html))
        }
    }
    func testLargeRawHTMLDoesNotExpandTableProjectionBudget() throws {
        let html = "<script>" + String(repeating: "x", count: 1_500_000)
            + "</script><table><tr><td>Fat</td><td>1g</td></tr></table>"
        let bytes = try HTMLFoodSourceTableProjector.project(Data(html.utf8))
        XCTAssertLessThan(bytes.count, 1_000)
        XCTAssertEqual(FoodSourceDocumentDecoder.maximumBytes, 500_000)
        let oversizedProjection = "<table><tr><td>" + String(repeating: "x", count: 500_001) + "</td></tr></table>"
        XCTAssertThrowsError(try HTMLFoodSourceTableProjector.project(Data(oversizedProjection.utf8))) { error in
            XCTAssertEqual(error as? FoodSourceBindingError, .invalidDocument)
        }
        let oversizedHTML = "<script>" + String(repeating: "x", count: 2_000_001)
            + "</script><table><tr><td>Fat</td><td>1g</td></tr></table>"
        XCTAssertThrowsError(try HTMLFoodSourceTableProjector.project(Data(oversizedHTML.utf8)))
    }

    func testHTML5RepairIsVersionedAndRawInputHashRemainsDistinct() throws {
        let complete = Data("<table><tr><td>A</td></tr></table>".utf8)
        let implied = Data("<table><tr><td>A".utf8)
        let a = try HTMLFoodSourceTableProjector.project(complete)
        let b = try HTMLFoodSourceTableProjector.project(implied)
        let x = try XCTUnwrap(JSONSerialization.jsonObject(with: a) as? [String: Any])
        let y = try XCTUnwrap(JSONSerialization.jsonObject(with: b) as? [String: Any])
        XCTAssertEqual(x["projection_version"] as? String, "swift-html-source-tables-v2")
        XCTAssertNotEqual(x["html_sha256"] as? String, y["html_sha256"] as? String)
        XCTAssertEqual(try JSONDecoder().decode(FoodSourceTableDocument.self, from: a),
                       try JSONDecoder().decode(FoodSourceTableDocument.self, from: b))
    }
    func testReconstructedCapturedAlproHTMLBindsTheSameFourSourceMacros() throws {
        // Controlled reconstruction from the factual captured table, not a fresh website fetch.
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "alpro-source-table-v7", withExtension: "json", subdirectory: "Fixtures"))
        let original = try JSONDecoder().decode(FoodSourceTableDocument.self, from: Data(contentsOf: fixture))
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let html = "<table><tbody>" + original.tables[0].rows.map { row in
            "<tr>" + row.cells.enumerated().map { index, cell in
                let tag = index == 0 ? "th" : "td"
                return "<" + tag + ">" + cell.segments.map(escape).joined(separator: "<br>") + "</" + tag + ">"
            }.joined() + "</tr>"
        }.joined() + "</tbody></table>"
        let bytes = try HTMLFoodSourceTableProjector.project(Data(html.utf8))
        let s = try FoodSourceDocumentDecoder.decode(bytes, documentID: "alpro-captured-reconstruction", recordID: "selected-alpro",
            basisCell: .init(table: 1, row: 1, cell: 2, segment: 1))
        XCTAssertEqual(s.document, original)
        let fields: [(NutrientKey, Double, String, Int)] = [(.energyConsumed, 42, "42", 2), (.fatTotal, 1.9, "1.9", 3),
            (.carbohydrates, 2.7, "2.7", 4), (.protein, 3.3, "3.3", 6)]
        let claims = fields.map { field, amount, literal, row in
            FoodSourceNutrientClaim(documentID: s.documentID, recordID: s.recordID, sha256: s.sha256,
                field: field, amount: amount, unit: field == .energyConsumed ? "kcal" : "g", basis: .per100Millilitres,
                declaredLiteral: literal, sourceCell: .init(table: 1, row: row, cell: 2, segment: 1))
        }
        XCTAssertEqual(try FoodSourceNutritionBinding.bind(claims, to: s).map(\.value.amount), [42, 1.9, 2.7, 3.3])
    }
}
