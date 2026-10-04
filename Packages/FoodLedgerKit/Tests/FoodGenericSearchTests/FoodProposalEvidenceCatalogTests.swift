import Foundation
import FoodLedgerDomain
@testable import FoodGenericSearch
import XCTest

final class FoodProposalEvidenceCatalogTests: XCTestCase {
    func testProviderInputOmitsLongLocationsWhileSourceAndReferencesRetainTraceability() throws {
        let locator = "document/" + String(repeating: "div[12]/", count: 50)
        let source = try CapturedFoodDocument(id: "d1", url: "https://example.com/food",
            rawSha256: String(repeating: "a", count: 64), captureOrigin: "synthetic_fixture",
            retrievedAt: "2026-10-04T00:00:00Z", blocks: [
                .init(id: "original-heading", kind: "h1", text: "Tofu", locator: locator),
                .init(id: "original-row", kind: "tr", text: "Protein 6g", locator: locator + "tr[1]")])
        let catalog = try FoodProposalEvidenceCatalog(documents: [source])
        let blocks = try XCTUnwrap(catalog.requestDocuments()[0]["blocks"] as? [[String: String]])
        XCTAssertEqual(blocks, [["id": "e1", "kind": "h1", "text": "Tofu"],
                                ["id": "e2", "kind": "tr", "text": "Protein 6g"]])
        let reference = try XCTUnwrap(catalog.references(["e2"], documentID: "d1").first)
        let original = try XCTUnwrap(source.blocks.first { $0.id == reference["block_id"] })
        XCTAssertEqual(original.locator, locator + "tr[1]")
        XCTAssertEqual(original.text, reference["quote"])
        XCTAssertEqual(source.blocks[0].locator, locator)
    }

    func testEvidenceIDsResolveWithinTheirOwnDocumentWithoutModelQuotations() throws {
        let first = try document(id: "d1", text: "Protein 6g")
        let second = try document(id: "d2", text: "Protein 12g")
        let catalog = try FoodProposalEvidenceCatalog(documents: [first, second])
        XCTAssertEqual(try catalog.references(["e1"], documentID: "d1"), [["block_id": "b1", "quote": "Protein 6g"]])
        XCTAssertEqual(try catalog.references(["e1"], documentID: "d2"), [["block_id": "b1", "quote": "Protein 12g"]])
        XCTAssertThrowsError(try catalog.references(["e1"], documentID: "not-offered"))
        XCTAssertThrowsError(try catalog.references(["e2"], documentID: "d1"))
        XCTAssertThrowsError(try catalog.references(["e1", "e1"], documentID: "d1"))
        XCTAssertThrowsError(try catalog.references([["block_id": "e1", "quote": "invented"]], documentID: "d1"))
    }

    func testLongUnicodeBlocksUseBoundedOriginalExcerptsAndKeepOriginalBlockIdentity() throws {
        let original = String(repeating: "豆花 source text ", count: 250) + "Protein <6g end"
        let catalog = try FoodProposalEvidenceCatalog(documents: [document(id: "d1", text: original)])
        let blocks = try XCTUnwrap(catalog.requestDocuments()[0]["blocks"] as? [[String: String]])
        XCTAssertGreaterThan(blocks.count, 1)
        XCTAssertTrue(blocks.allSatisfy { ($0["text"]?.count ?? 0) <= FoodProposalEvidenceCatalog.maximumExcerptCharacters })
        XCTAssertTrue(blocks.allSatisfy { original.contains($0["text"]!) })
        let last = try XCTUnwrap(blocks.last)
        XCTAssertTrue(last["text"]!.contains("Protein <6g end"))
        let references = try catalog.references(blocks.map { $0["id"]! }, documentID: "d1")
        XCTAssertTrue(references.allSatisfy { $0["block_id"] == "b1" })
        XCTAssertEqual(references.map { $0["quote"]! }, blocks.map { $0["text"]! })
        XCTAssertEqual(catalog.requestDocuments()[0]["evidence_catalog_version"] as? String, FoodProposalEvidenceCatalog.version)
    }

    func testUnbrokenLongTextStillTerminatesWithoutChangingSourceCharacters() throws {
        let text = String(repeating: "字", count: 30_000)
        let catalog = try FoodProposalEvidenceCatalog(documents: [document(id: "d1", text: text)])
        let blocks = try XCTUnwrap(catalog.requestDocuments()[0]["blocks"] as? [[String: String]])
        XCTAssertLessThan(blocks.count, 30)
        XCTAssertTrue(blocks.allSatisfy { !$0["text"]!.isEmpty && text.contains($0["text"]!) })
    }

    private func document(id: String, text: String) throws -> CapturedFoodDocument {
        try CapturedFoodDocument(id: id, url: "https://example.com/food", rawSha256: String(repeating: "a", count: 64),
            captureOrigin: "synthetic_fixture", retrievedAt: "2026-10-04T00:00:00Z",
            blocks: [.init(id: "b1", kind: "p", text: text, locator: "p:1")])
    }
}
