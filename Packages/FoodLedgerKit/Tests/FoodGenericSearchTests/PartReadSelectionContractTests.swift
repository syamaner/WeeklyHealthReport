import CryptoKit
import Foundation
@_spi(ReviewedWebRegression) import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
@testable import FoodGenericSearch
import XCTest

/// Contract #508 phase 3 (docs/web-lookup-part-read-pages-v1-proposal.md section 12, settled in
/// docs/web-lookup-part-read-phase3-gate.md): part-read selection `food-document-block-selection-v1`.
/// Every page here is synthetic.
final class PartReadSelectionContractTests: XCTestCase {
    private let url = URL(string: "https://unfamiliar.example/product")!
    private let selected = ";projection:" + FoodDocumentPartialRead.selectedProjectionVersion
    private let panel = "<table><tr><th>Energy</th><td>61kcal</td></tr><tr><th>Fat</th><td>3.1g</td></tr>"
        + "<tr><th>Protein</th><td>6.2g</td></tr></table>"
    /// 2,100 navigation blocks: enough on their own to pass the 2,048-block bound.
    private let menu = "<ul>" + (1...2_100).map { "<li>Aisle \($0)</li>" }.joined() + "</ul>"

    private func project(_ source: String, _ partRead: FoodDocumentPartReadPermission = .permitted,
                         mediaType: String = "text/html") throws -> CapturedFoodDocument {
        try GenericFoodDocumentProjector.project(Data(source.utf8), url: url, mediaType: mediaType,
            retrievedAt: Date(timeIntervalSince1970: 0), partRead: partRead)
    }
    private func assertTooLarge(_ source: String, _ partRead: FoodDocumentPartReadPermission = .permitted,
                                mediaType: String = "text/html", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try project(source, partRead, mediaType: mediaType), file: file, line: line) {
            XCTAssertEqual($0 as? FoodSourceAcquisitionError, .responseTooLarge, file: file, line: line)
        }
    }
    private func texts(_ document: CapturedFoodDocument) -> [String] { document.blocks.map(\.text) }

    // MARK: Test 1, boundary identity

    func testBoundsProjectWholeUnderBothPermissionsAndOneMoreEntersSelectionOnlyWithPermission() throws {
        XCTAssertEqual(FoodDocumentBlockSelection.bounds, FoodDocumentBounds.current)
        let blocks = String(repeating: "<p>x</p>", count: 2_048)
        XCTAssertEqual(try project(blocks, .refused), try project(blocks, .permitted))
        XCTAssertNil(try project(blocks).partialRead)
        let characters = "<p>" + String(repeating: "x", count: 100_000) + "</p>"
        XCTAssertEqual(try project(characters, .refused), try project(characters, .permitted))
        // A 2,049th block: refused without permission, selected with it.
        let overBlocks = "<h1>Tofu</h1>" + String(repeating: "<p>x</p>", count: 2_047) + panel
        assertTooLarge(overBlocks, .refused)
        let partBlocks = try project(overBlocks)
        XCTAssertEqual(partBlocks.partialRead?.fullBlocks, 2_051)
        XCTAssertEqual(texts(partBlocks).suffix(3), ["Energy | 61kcal", "Fat | 3.1g", "Protein | 6.2g"])
        // A 100,001st character: refused without permission, selected with it.
        let overCharacters = "<h1>Tofu</h1><p>" + String(repeating: "y", count: 99_990) + "</p>" + panel
        assertTooLarge(overCharacters, .refused)
        let partCharacters = try project(overCharacters)
        XCTAssertGreaterThan(try XCTUnwrap(partCharacters.partialRead).fullCharacters, 100_000)
        XCTAssertEqual(texts(partCharacters), ["Tofu", "Energy | 61kcal", "Fat | 3.1g", "Protein | 6.2g"])
    }

    // MARK: Test 2, whole pages unchanged

    func testPagesWithinTheBoundsAreIdenticalUnderBothPermissions() throws {
        let small = "<h1>Tofu</h1>" + panel
        let between = "<h1>Large</h1><table>" + (1...700).map { "<tr><td>Row \($0)</td><td>\($0) g</td></tr>" }.joined()
            + "</table><p>" + String(repeating: "z", count: 40_000) + "</p>"
        for source in [small, between] {
            let refused = try project(source, .refused), permitted = try project(source, .permitted)
            XCTAssertEqual(refused, permitted)
            XCTAssertNil(permitted.partialRead)
            XCTAssertTrue(permitted.blocks.allSatisfy { $0.locator.hasSuffix(";projection:swift-food-document-blocks-v6") })
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            XCTAssertEqual(try encoder.encode(refused), try encoder.encode(permitted))
        }
    }

    // MARK: Test 3, errors and cancellation in the extended walk

    func testMalformedStructuredDataAfterTheBoundIsTooLargeAndBeforeItIsUnchanged() throws {
        let bad = #"<script type="application/ld+json">{"name": </script>"#
        assertTooLarge("<h1>Tofu</h1>" + menu + bad + panel)
        XCTAssertThrowsError(try project("<h1>Tofu</h1>" + bad + panel + menu)) {
            XCTAssertEqual($0 as? GenericFoodProposalError, .invalidDocument)
        }
    }

    func testCancellationInsideTheExtendedWalkAndTheSelectionStaysCancellation() async {
        let source = Data(("<h1>Tofu</h1>" + menu + panel).utf8)
        let url = url
        let walk = Task {
            try GenericFoodDocumentProjector.project(source, url: url, mediaType: "text/html", retrievedAt: Date(timeIntervalSince1970: 0),
                origin: "synthetic_fixture", partRead: .permitted, boundPassed: { withUnsafeCurrentTask { $0?.cancel() } },
                selectionStarts: {})
        }
        do { _ = try await walk.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        // Cancelled after the walk, as selection starts: the projector still reports cancellation.
        let afterWalk = Task {
            try GenericFoodDocumentProjector.project(source, url: url, mediaType: "text/html", retrievedAt: Date(timeIntervalSince1970: 0),
                origin: "synthetic_fixture", partRead: .permitted, boundPassed: {},
                selectionStarts: { withUnsafeCurrentTask { $0?.cancel() } })
        }
        do { _ = try await afterWalk.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        let selection = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FoodDocumentBlockSelection.select([.init(kind: "tr", text: "Energy 61kcal", unit: "table:1")])
        }
        do { _ = try await selection.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
    }

    // MARK: Test 4, other media types

    func testPlainTextBeyondTheBoundsIsRefusedWithPermission() {
        let plain = Array(repeating: "Energy 61kcal", count: 2_049).joined(separator: "\n")
        assertTooLarge(plain, .permitted, mediaType: "text/plain")
        assertTooLarge(String(repeating: "x", count: 100_001), .permitted, mediaType: "text/plain")
    }

    // MARK: Test 5, all or nothing

    func testCompetingPanelsAreAllKeptWithOrWithoutTheirSharedLabel() throws {
        let inside = try project("<h1>Tofu</h1><p>Batch A and batch B</p>" + panel + panel + menu)
        XCTAssertEqual(texts(inside).prefix(8), ["Tofu", "Batch A and batch B", "Energy | 61kcal", "Fat | 3.1g", "Protein | 6.2g",
                                                  "Energy | 61kcal", "Fat | 3.1g", "Protein | 6.2g"])
        let filler = (1...20).map { "<p>Filler \($0)</p>" }.joined()
        let outside = try project("<h1>Tofu</h1><p>Batch A and batch B</p>" + filler + panel + filler + panel + menu)
        XCTAssertFalse(texts(outside).contains("Batch A and batch B"))
        XCTAssertEqual(texts(outside).filter { $0 == "Energy | 61kcal" }.count, 2)
        XCTAssertEqual(texts(outside).filter { $0 == "Protein | 6.2g" }.count, 2)
    }

    func testARequiredSetThatDoesNotFitIsRefusedAndManySmallUnitsThatFitAreKept() throws {
        // 30 panels of 70 rows each: 2,100 required rows, so nothing is kept.
        let rows = (1...70).map { "<tr><td>Energy \($0)</td><td>\($0) kcal</td></tr>" }.joined()
        assertTooLarge("<h1>Tofu</h1>" + String(repeating: "<table>" + rows + "</table>", count: 30))
        // 50 small panels that fit are all kept, none ranked or dropped.
        let kept = try project("<h1>Tofu</h1>" + String(repeating: panel, count: 50) + menu)
        XCTAssertEqual(texts(kept).filter { $0 == "Fat | 3.1g" }.count, 50)
    }

    // MARK: Test 6, units

    func testTableUnitsNestedTablesCaptionsAndExtents() throws {
        // Inner nutrition rows form their own unit; the outer table is not a nutrition unit, so
        // only six outer rows after the inner panel are kept as context.
        let outerRows = (1...30).map { "<tr><td>Outer row \($0)</td></tr>" }.joined()
        let nested = try project("<h1>Tofu</h1><table><tr><td>Header</td><td>" + panel + "</td></tr>" + outerRows + "</table>" + menu)
        XCTAssertTrue(texts(nested).contains("Protein | 6.2g"))
        XCTAssertTrue(texts(nested).contains("Outer row 6"))
        XCTAssertFalse(texts(nested).contains("Outer row 7"))
        // A nested non-nutrition table inside a nutrition table, and a header row that wraps it,
        // are kept whole by the extent, beyond any window.
        let notes = "<table>" + (1...20).map { "<tr><td>Note \($0)</td></tr>" }.joined() + "</table>"
        let wrapped = try project("<h1>Tofu</h1><table><tr><th>Energy</th><td>61kcal</td></tr><tr><th>Fat</th><td>3.1g</td></tr>"
            + "<tr><td>" + notes + "</td></tr><tr><th>Protein</th><td>6.2g</td></tr><tr><th>Salt</th><td>0.1g</td></tr></table>" + menu)
        XCTAssertEqual((1...20).filter { texts(wrapped).contains("Note \($0)") }.count, 20)
        // A block over 1,400 characters inside an extent is kept; a caption joins its table's
        // unit, so a long caption is kept although as context it would end the window.
        let long = "Per 100g " + String(repeating: "x", count: 1_500)
        let captioned = try project("<h1>Tofu</h1><table><caption>" + long + "</caption>"
            + "<tr><th>Energy</th><td>61kcal</td></tr><tr><th>Fat</th><td>3.1g</td></tr><tr><th>Protein</th><td>6.2g</td></tr></table>" + menu)
        XCTAssertTrue(texts(captioned).contains(long))
        let inExtent = try project("<h1>Tofu</h1><table><tr><th>Energy</th><td>61kcal</td></tr><tr><td>" + long + "</td></tr>"
            + "<tr><th>Fat</th><td>3.1g</td></tr><tr><th>Protein</th><td>6.2g</td></tr></table>" + menu)
        XCTAssertTrue(texts(inExtent).contains(long))
        // A single unit over the budget is refused.
        assertTooLarge("<h1>Tofu</h1><table>" + (1...2_100).map { "<tr><td>Energy \($0) kcal</td></tr>" }.joined() + "</table>")
    }

    func testDefinitionUnitsAndBlocksThatBelongToNoUnit() throws {
        let pairs = "<dt>Energy</dt><dd>61kcal</dd><dt>Fat</dt><dd>3.1g</dd><dt>Protein</dt><dd>6.2g</dd>"
        let list = try project("<h1>Tofu</h1><dl>" + pairs + "</dl>" + menu)
        XCTAssertEqual(texts(list).prefix(4), ["Tofu", "Energy | 61kcal", "Fat | 3.1g", "Protein | 6.2g"])
        let wrapped = try project("<h1>Tofu</h1><dl><div><dt>Energy</dt><dd>61kcal</dd></div><div><dt>Fat</dt><dd>3.1g</dd></div>"
            + "<div><dt>Protein</dt><dd>6.2g</dd></div></dl>" + menu)
        XCTAssertEqual(wrapped.blocks.filter { $0.kind == "definition_row" }.count, 3)
        // Lone dt and dd blocks are no unit; nor is a pair with no dl; nor a price-per-100 g table.
        // Five lone blocks that each match, inside one dl: still no unit.
        let lone = "<h1>Tofu</h1><dl><dt>Energy 61kcal</dt><dt>Fat 3g</dt><dt>Protein 6g</dt><dd>Salt 1g</dd><dd>Sugars 2g</dd></dl>"
        XCTAssertEqual(try project(lone, .refused).blocks.filter { ["dt", "dd"].contains($0.kind) }.count, 5)
        assertTooLarge(lone + menu)
        assertTooLarge("<h1>Tofu</h1><div>" + pairs + "</div>" + menu)
        assertTooLarge("<h1>Tofu</h1><table>" + (1...5).map { "<tr><td>Pack \($0)</td><td>£1.2\($0) per 100g</td></tr>" }.joined()
            + "</table>" + menu)
    }

    // MARK: Test 7, matching

    func testVocabularyMatchingRuleAndThresholdsArePinned() {
        XCTAssertEqual(FoodDocumentBlockSelection.policy, "food-document-block-selection-v1")
        XCTAssertEqual(FoodDocumentBlockSelection.latinTerms, ["energy", "calorie", "calories", "kcal", "kj", "protein", "proteins",
            "fat", "fats", "saturates", "saturated", "carbohydrate", "carbohydrates", "carbs", "sugar", "sugars", "fibre", "fiber",
            "salt", "sodium"])
        XCTAssertEqual(FoodDocumentBlockSelection.chineseTerms, ["熱量", "热量", "能量", "蛋白質", "蛋白质", "脂肪", "碳水化合物", "糖",
            "膳食纖維", "膳食纤维", "鈉", "钠"])
        XCTAssertEqual(FoodDocumentBlockSelection.contextBefore, 12)
        XCTAssertEqual(FoodDocumentBlockSelection.contextAfter, 6)
        XCTAssertEqual(FoodDocumentBlockSelection.longContextBlockCharacters, FoodProposalEvidenceCatalog.maximumExcerptCharacters)
        XCTAssertEqual(FoodDocumentBlockSelection.nutritionBlockThreshold, 3)
        for text in ["61kcal", "Per100g Energy 250", "Fat:3g", "fat-free 0g", "ENERGY 61", "熱量150大卡", "蛋白质6克",
                     "Sugars 2g", "Fat\u{0301} 3g", "Énergie kj 250"] {
            XCTAssertTrue(FoodDocumentBlockSelection.matches(text), text)
        }
        for text in ["Per100g", "fatty 3", "kjeldahl 4", "saltire 2", "Energy", "熱量", "Protein ６g", "Price £1.20 per 100g",
                     "ÉNERGIE 61", "\u{212A}cal 61", "\u{212A}J 250"] {
            XCTAssertFalse(FoodDocumentBlockSelection.matches(text), text)
        }
    }

    func testMenuNoiseOutsideATableIsNotANutritionUnit() {
        assertTooLarge("<h1>Shop</h1><ul>" + (1...2_100).map { "<li>Protein bars \($0) for £3</li>" }.joined() + "</ul>")
    }

    // MARK: Test 8, context and identity

    func testLongContextEndsTheWindowAndStructuredDataUsesAPosition() throws {
        let long = try project("<h1>Tofu</h1><p>A label</p><p>" + String(repeating: "y", count: 1_500) + "</p>" + panel + menu)
        XCTAssertEqual(texts(long).prefix(4), ["Tofu", "Energy | 61kcal", "Fat | 3.1g", "Protein | 6.2g"])
        let near = (1...11).map { "<p>Near \($0)</p>" }.joined()
        let json = #"<script type="application/ld+json">{"name": "Tofu"}</script>"#
        // Twelve positions before the table: eleven paragraphs and the JSON-LD block; "Far" is the thirteenth.
        let withJSON = try project("<h1>Tofu</h1><p>Far</p>" + json + near + panel + menu)
        XCTAssertFalse(texts(withJSON).contains("Far"))
        XCTAssertTrue(texts(withJSON).contains(#"{"name": "Tofu"}"#), "Kept by the JSON-LD fill, not as context")
        let withoutJSON = try project("<h1>Tofu</h1><p>Far</p>" + near + panel + menu)
        XCTAssertTrue(texts(withoutJSON).contains("Far"))
    }

    func testNearestHeadingAtAnyDistanceAndPagesWithoutAnH1() throws {
        let filler = (1...40).map { "<p>Filler \($0)</p>" }.joined()
        let far = try project("<h1>Tofu</h1><h2>Nutrition</h2>" + filler + panel + menu)
        XCTAssertEqual(texts(far).prefix(3), ["Tofu", "Nutrition", "Filler 29"])
        let noH1 = try project("<title>Tofu page</title><h2>Nutrition</h2>" + panel + menu)
        XCTAssertFalse(noH1.blocks.contains { $0.kind == "h1" })
        XCTAssertTrue(texts(noH1).contains("Nutrition"))
    }

    func testTheH1CountsAtExactlyTheBlockBound() throws {
        func page(rows: Int) -> String {
            "<h1>Tofu</h1><table>" + (1...rows).map { "<tr><td>Energy \($0) kcal</td></tr>" }.joined() + "</table>"
                + (1...10).map { "<p>After \($0)</p>" }.joined()
        }
        // h1 + 2,041 rows + 6 after = 2,048 required blocks.
        XCTAssertEqual(try project(page(rows: 2_041)).blocks.count, 2_048)
        assertTooLarge(page(rows: 2_042))
    }

    // MARK: Test 9, JSON-LD

    func testStructuredDataFillsInOrderSkipsWhatDoesNotFitAndNeverRefuses() throws {
        let big = #"<script type="application/ld+json">{"a": ""# + String(repeating: "z", count: 99_990) + #""}</script>"#
        let small = #"<script type="application/ld+json">{"b": 1}</script>"#
        let document = try project("<h1>Tofu</h1>" + panel + big + small + menu)
        XCTAssertFalse(texts(document).contains { $0.hasPrefix(#"{"a""#) })
        XCTAssertTrue(texts(document).contains(#"{"b": 1}"#))
        // A long JSON-LD block inside a window does not end it.
        let longJSON = #"<script type="application/ld+json">{"c": ""# + String(repeating: "q", count: 1_500) + #""}</script>"#
        let window = try project("<h1>Tofu</h1><p>Before the data</p>" + longJSON + panel + menu)
        XCTAssertTrue(texts(window).contains("Before the data"))
    }

    // MARK: Test 10, output

    func testOutputIsDeterministicWithOriginalIdsPathsCountsAndHash() throws {
        let source = "<h1>Synthetic tofu</h1>" + menu + "<h2>Nutrition</h2>" + panel
        let first = try project(source), second = try project(source)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.blocks.map(\.id)).count, first.blocks.count)
        // b1 is the h1; b2 to b2101 the menu; b2102 the heading; b2103 to b2105 the rows.
        XCTAssertEqual(first.blocks.first?.id, "b1")
        XCTAssertEqual(first.blocks.suffix(3).map(\.id), ["b2103", "b2104", "b2105"])
        XCTAssertEqual(first.blocks.suffix(10).first?.id, "b2096")
        let whole = try project("<h1>Synthetic tofu</h1>", .refused)
        XCTAssertEqual(first.blocks[0].locator, whole.blocks[0].locator.replacingOccurrences(of: ";projection:swift-food-document-blocks-v6", with: selected))
        XCTAssertTrue(first.blocks.allSatisfy { $0.locator.hasSuffix(selected) })
        // The kept rows' paths equal the same rows projected whole (menu after the panel keeps paths equal).
        let panelFirst = try project("<h1>Synthetic tofu</h1><h2>Nutrition</h2>" + panel + menu)
        let panelWhole = try project("<h1>Synthetic tofu</h1><h2>Nutrition</h2>" + panel, .refused)
        XCTAssertEqual(panelFirst.blocks.prefix(5).map { $0.locator.replacingOccurrences(of: selected, with: "") },
                       panelWhole.blocks.map { $0.locator.replacingOccurrences(of: ";projection:swift-food-document-blocks-v6", with: "") })
        XCTAssertEqual(panelFirst.blocks.prefix(5).map(\.id), panelWhole.blocks.map(\.id))
        let menuCharacters = (1...2_100).reduce(0) { $0 + "Aisle \($1)".count }
        let record = try XCTUnwrap(first.partialRead)
        XCTAssertEqual(record.fullBlocks, 2_105)
        XCTAssertEqual(record.fullCharacters, "Synthetic tofu".count + menuCharacters + "Nutrition".count
            + "Energy | 61kcal".count + "Fat | 3.1g".count + "Protein | 6.2g".count)
        XCTAssertEqual(record.keptBlocks, first.blocks.count)
        XCTAssertEqual(record.keptCharacters, first.characterCount)
        let hash = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(first.rawSha256, hash)
        XCTAssertEqual(first.id, "doc_" + hash.prefix(16))
        // The record round-trips and validates.
        let decoded = try JSONDecoder().decode(CapturedFoodDocument.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(decoded, first)
        XCTAssertNoThrow(try decoded.validate())
    }

    func testALocatorTooLongForTheSelectedVersionIsRefusedAndNeverShortened() throws {
        // Find a nesting whose longest whole-page locator fits 500 with the v6 suffix but not with the
        // selected suffix, which is nine characters longer.
        XCTAssertEqual(selected.count - ";projection:swift-food-document-blocks-v6".count, 9)
        var found = false
        for padding in 1...80 {
            let tag = "w" + String(repeating: "x", count: padding)
            let open = String(repeating: "<\(tag)>", count: 6), close = String(repeating: "</\(tag)>", count: 6)
            let wrapped = "<h1>Tofu</h1>" + open + panel + close
            guard let whole = try? project(wrapped, .refused) else { continue }
            let longest = whole.blocks.map(\.locator.count).max() ?? 0
            guard (492...500).contains(longest) else { continue }
            found = true
            assertTooLarge(wrapped + menu)
            break
        }
        XCTAssertTrue(found, "No nesting reached the edge")
    }

    // MARK: Test 13, provider bodies for a projected part-read document

    func testProviderBodiesForAProjectedPartReadDocument() throws {
        let document = try project("<h1>Synthetic tofu</h1>" + menu + "<h2>Nutrition</h2>" + panel)
        XCTAssertNotNil(document.partialRead)
        let catalogue = try FoodProposalEvidenceCatalog(documents: [document]).requestDocuments()
        let entries = try XCTUnwrap(catalogue.first?["blocks"] as? [[String: String]])
        XCTAssertEqual(entries.map { $0["id"] }, (1...document.blocks.count).map { "e\($0)" }, "Catalogue ids, not block ids")
        XCTAssertEqual(entries.map { $0["text"] }, texts(document))
        XCTAssertEqual(Set(catalogue[0].keys), ["id", "url", "raw_sha256", "capture_origin", "retrieved_at", "evidence_catalog_version", "blocks"])
        let extraction = String(decoding: try OpenRouterFoodProvider.extractionBody(foodTerms: "tofu", documents: [document]), as: UTF8.self)
        XCTAssertFalse(extraction.contains("partial_read") || extraction.contains("partialRead") || extraction.contains("full_blocks"))
        XCTAssertFalse(extraction.contains(FoodDocumentPartialRead.selectedProjectionVersion))
        XCTAssertFalse(extraction.contains("b2103"), "Original block ids are not sent on the production route")
        let jev = try XCTUnwrap(OpenRouterFoodProvider.providerDocuments([document]) as? [[String: Any]])
        XCTAssertEqual(Set(jev[0].keys), ["id", "url", "raw_sha256", "capture_origin", "retrieved_at", "blocks"])
        let blocks = try XCTUnwrap(jev[0]["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.map { $0["id"] as? String }, document.blocks.map(\.id))
        XCTAssertEqual(blocks.map { $0["locator"] as? String }, document.blocks.map(\.locator), "The jev route sends locators")
    }

    // MARK: Test 18, the public capture under the shared port contract

    func testPublicCapturePassesTheSharedPortContract() async {
        let violations = await FoodDocumentCapturePortContracts.violations { shape in
            let body = FoodDocumentCapturePortContracts.html(shape)
            let capture = PublicFoodSourceCapture(resolve: { _ in ["8.8.8.8"] }, fetch: { _, _ in
                Data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)
            }, now: { Date(timeIntervalSince1970: 0) })
            return (capture, URL(string: "https://publisher.example/tofu")!)
        }
        XCTAssertEqual(violations, [])
    }

    // A projected part-read document validates and is outside what v1 and v2 reviews admit.
    func testAProjectedPartReadDocumentValidatesAndIsOutsideVersion1And2() throws {
        let document = try project("<h1>Synthetic tofu</h1>" + menu + panel)
        XCTAssertNotNil(document.partialRead)
        XCTAssertTrue(document.hasSelectedLocator)
        XCTAssertNoThrow(try document.validate())
        XCTAssertTrue(document.fits(.reviewManifestV1V2), "Small enough, so only the part-read rules can refuse it")
        XCTAssertFalse(FoodProposalReviewManifestRecord.fitsVersion1Or2(document))
    }
}
