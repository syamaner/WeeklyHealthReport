import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import XCTest

final class LocalInventoryContractTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testAdaptersShareAtomicRetryAndCorrectionContract() throws {
        try withStores { store in
            let source = try self.source("2 x Sample oats 500 g £4.20\nTOTAL £4.20")
            let product = try self.product()
            let review = try self.review(source, product: product, version: 1)
            let command = InventoryCommand(operationID: try self.id(1), expectedRevision: 0,
                mutations: [.source(source), .product(product), .review(review)])
            let saved = try store.commit(command)
            XCTAssertEqual(saved.revision, 1)
            XCTAssertEqual(saved.reviewHistory.count, 1)
            XCTAssertNil(saved.products[0].remaining, "Acquired packs must not become remaining stock")
            XCTAssertEqual(try store.commit(command), saved)
            XCTAssertThrowsError(try store.commit(InventoryCommand(operationID: try self.id(1), expectedRevision: 0, mutations: [.source(source)])))
            XCTAssertThrowsError(try store.commit(InventoryCommand(operationID: try self.id(2), expectedRevision: 0, mutations: [.source(source)])))
            XCTAssertEqual(try store.snapshot(), saved)

            let undo = try InventoryReviewRevision(sourceID: source.contentID, lineNumber: 1, version: 2, disposition: .deferred, note: "Undo for correction", reviewedAt: self.date)
            let corrected = try store.commit(InventoryCommand(operationID: try self.id(3), expectedRevision: 1, mutations: [.review(undo)]))
            XCTAssertEqual(corrected.reviewHistory.count, 2)
            XCTAssertEqual(corrected.review(sourceID: source.contentID, lineNumber: 1)?.disposition, .deferred)
            XCTAssertEqual(corrected.reviewHistory[0], review)

            let newProduct = try self.product(version: 2)
            let badReview = try self.review(source, product: newProduct, version: 5)
            XCTAssertThrowsError(try store.commit(InventoryCommand(operationID: try self.id(4), expectedRevision: 2, mutations: [.product(newProduct), .review(badReview)])))
            XCTAssertEqual(try store.snapshot(), corrected, "Failed multi-mutation command must not save its product")
        }
    }

    func testReimportKeepsSourceAndDoesNotDuplicateAcquisition() throws {
        try withStores { store in
            let service = LocalInventoryService(store: store, digester: SHA256Digester(), clock: Clock())
            let text = "Meadow milk 1 l 1.50"
            let document = ExtractedInventoryDocument(originalBytes: Data(text.utf8), text: text, extractionVersion: "synthetic-v1")
            let first = try service.importDocument(document, kind: .receipt, name: "Invented receipt", operationID: self.id(1))
            let second = try service.importDocument(document, kind: .receipt, name: "Renamed receipt", operationID: self.id(2))
            XCTAssertEqual(first, second)
            XCTAssertEqual(try store.snapshot().revision, 1)
            XCTAssertEqual(try store.snapshot().sources.count, 1)
            XCTAssertTrue(try store.snapshot().reviewHistory.isEmpty)
            XCTAssertThrowsError(try service.importDocument(document, kind: .catalogue, name: "Wrong mode", operationID: self.id(3)))
        }
    }

    func testOrdersAndContextCannotBecomeReceivedAcquisitionsWithoutCorrection() throws {
        try withStores { store in
            let product = try self.product()
            var revision = 0
            for (index, input) in ["ORDER oats 500 g", "TOTAL 4.00", "RETURN oats 500 g"].enumerated() {
                let source = try self.source(input)
                let command = InventoryCommand(operationID: try self.id(index + 10), expectedRevision: revision, mutations: [.source(source)] + (index == 0 ? [.product(product)] : []))
                revision = try store.commit(command).revision
                let review = try self.review(source, product: product, version: 1)
                XCTAssertThrowsError(try store.commit(InventoryCommand(operationID: try self.id(index + 20), expectedRevision: revision, mutations: [.review(review)])))
            }
        }
    }

    func testContentTamperingAndMissingReferencesFailClosed() throws {
        try withStores { store in
            let source = try self.source("Oats 500 g")
            let forged = try InventorySource(contentID: source.contentID, kind: .receipt, displayName: "Fake", originalBytes: Data("changed".utf8), extractedText: "Oats 500 g", extractionVersion: "synthetic", importedAt: self.date)
            XCTAssertThrowsError(try store.commit(InventoryCommand(operationID: try self.id(1), expectedRevision: 0, mutations: [.source(forged)])))
            let review = try self.review(source, product: self.product(), version: 1)
            XCTAssertThrowsError(try store.commit(InventoryCommand(operationID: try self.id(2), expectedRevision: 0, mutations: [.source(source), .review(review)])))
            XCTAssertEqual(try store.snapshot().revision, 0)
        }
    }

    func testSQLiteReopenPreservesEvidenceAndHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("inventory.sqlite")
        let store = try LocalInventoryGRDBStore(databaseURL: url)
        let source = try source("Meadow beans 3 x 400 g 2.40")
        let saved = try store.commit(InventoryCommand(operationID: id(1), expectedRevision: 0, mutations: [.source(source)]))
        XCTAssertEqual(try LocalInventoryGRDBStore(databaseURL: url).snapshot(), saved)
        XCTAssertThrowsError(try LocalInventoryGRDBStore(databaseURL: url, protectedData: ProtectedDataAvailability { false }))
    }

    func testMatchingKeepsConflictingAliasesAndDoesNotAssertAvailability() throws {
        let remaining = try InventoryRemainingAssertion(amount: InventoryAmount(value: 0, unit: .grams), assertedAt: date)
        let first = try InventoryProductVersion(productID: id(100), version: 1, name: "Meadow full milk", category: "Dairy", aliases: ["MILK"], packDescription: "1 l", remaining: remaining, updatedAt: date)
        let second = try InventoryProductVersion(productID: id(101), version: 1, name: "Valley skimmed milk", category: "Dairy", aliases: ["MILK"], packDescription: "2 l", updatedAt: date)
        let matches = InventoryMatcher.matches("milk", products: [second, first])
        XCTAssertEqual(matches.count, 2)
        XCTAssertTrue(matches.allSatisfy(\.exactNameOrAlias))
        XCTAssertTrue(matches.allSatisfy { !$0.differences.isEmpty })
        XCTAssertEqual(matches[0].product.remaining?.assertedAt, date)
        XCTAssertEqual(InventoryMatcher.matches("Dairy", products: [first, second]).count, 2)
        XCTAssertTrue(InventoryMatcher.matches("unmatched", products: [first]).isEmpty)
    }

    func testSelectionEvidenceOmitsStockAndReceiptContents() throws {
        let store = InMemoryInventoryStore()
        let product = try product()
        _ = try store.commit(InventoryCommand(operationID: id(1), expectedRevision: 0, mutations: [.product(product)]))
        let service = LocalInventoryService(store: store, digester: SHA256Digester(), clock: Clock())
        let evidence = try service.selectionEvidence(for: product, evidenceID: id(2), locale: LedgerText("en_GB"))
        XCTAssertEqual(evidence.kind, .manual)
        XCTAssertEqual(evidence.captureMethodVersion.value, "inventory-selection-v1")
        guard case let .text(payload) = evidence.originalPayload else { return XCTFail("Expected selection descriptor") }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.value.utf8)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["productID", "version", "name", "packDescription"])
        XCTAssertEqual(json["name"] as? String, "Sample oats")
        XCTAssertThrowsError(try service.selectionEvidence(for: self.product(version: 2), evidenceID: id(3), locale: LedgerText("en_GB")))
    }

    func testFutureStockAssertionAndCatalogueDeliveryAreRejected() throws {
        let future = try InventoryRemainingAssertion(amount: InventoryAmount(value: 50, unit: .grams), assertedAt: date.addingTimeInterval(1))
        XCTAssertThrowsError(try InventoryProductVersion(productID: id(100), version: 1, name: "Sample", remaining: future, updatedAt: date))
        try withStores { store in
            let bytes = Data("Sample oats 500 g".utf8)
            let source = try InventorySource(contentID: SHA256Digester().sha256(bytes), kind: .catalogue, displayName: "Catalogue", originalBytes: bytes, extractedText: String(decoding: bytes, as: UTF8.self), extractionVersion: "synthetic", importedAt: self.date)
            let product = try self.product()
            let review = try self.review(source, product: product, version: 1)
            XCTAssertThrowsError(try store.commit(InventoryCommand(operationID: self.id(1), expectedRevision: 0, mutations: [.source(source), .product(product), .review(review)])))
            XCTAssertEqual(try store.snapshot().revision, 0)
        }
    }

    private func withStores(_ test: (any InventoryStoring) throws -> Void) throws {
        try test(InMemoryInventoryStore())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(LocalInventoryGRDBStore(databaseURL: directory.appendingPathComponent("inventory.sqlite")))
    }

    private func source(_ text: String) throws -> InventorySource {
        let bytes = Data(text.utf8)
        return try InventorySource(contentID: SHA256Digester().sha256(bytes), kind: .receipt, displayName: "Synthetic", originalBytes: bytes, extractedText: text, extractionVersion: "synthetic-v1", importedAt: date)
    }

    private func product(version: Int = 1) throws -> InventoryProductVersion {
        try InventoryProductVersion(productID: id(100), version: version, name: "Sample oats", packDescription: "500 g", updatedAt: date)
    }

    private func review(_ source: InventorySource, product: InventoryProductVersion, version: Int) throws -> InventoryReviewRevision {
        try InventoryReviewRevision(sourceID: source.contentID, lineNumber: 1, version: version, disposition: .accepted, productID: product.productID, productVersion: product.version, correctedDescription: product.name, purchaseCount: 2, packAmount: InventoryAmount(value: 500, unit: .grams), received: true, reviewedAt: date)
    }

    private func id<Tag>(_ value: Int) throws -> LedgerID<Tag> {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
    private struct Clock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }
}
