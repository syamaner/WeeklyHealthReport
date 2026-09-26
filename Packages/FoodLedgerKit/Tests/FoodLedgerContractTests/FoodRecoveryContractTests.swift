import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import XCTest

final class FoodRecoveryContractTests: XCTestCase {
    private func id<Tag>(_ n: Int) throws -> LedgerID<Tag> { try LedgerID(String(format: "00000000-0000-0000-0000-%012x", n)) }

    func testReceiptCheckpointReopensOriginalEditsAndPendingCommand() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("receipt-draft.sqlite")
        let line = try XCTUnwrap(ReceiptParser.parse("Oats 500 g").first)
        var draft = InventoryLineDraft(line: line)
        draft.description = "Corrected oats"; draft.createProduct = true
        let product = try InventoryProductVersion(productID: id(90), version: 1, name: draft.description, updatedAt: Date(timeIntervalSince1970: 1700000000))
        let pending = InventoryCommand(operationID: try id(91), expectedRevision: 0, mutations: [.product(product)])
        let checkpoint = InventoryReviewCheckpoint(activeSourceID: nil, drafts: ["synthetic:1": draft], selectedLines: ["synthetic:1"], paste: "Oats 500 g", sourceKind: .receipt, pendingCommand: pending)
        try InventoryReviewCheckpointGRDBStore(databaseURL: url).save(checkpoint)
        let loaded = try XCTUnwrap(InventoryReviewCheckpointGRDBStore(databaseURL: url).load())
        XCTAssertEqual(loaded.drafts["synthetic:1"], draft)
        XCTAssertEqual(loaded.pendingCommand, pending)
        XCTAssertEqual(loaded.selectedLines, checkpoint.selectedLines)
        var unsupported = checkpoint; unsupported.schemaVersion = 99
        XCTAssertThrowsError(try InventoryReviewCheckpointGRDBStore(databaseURL: url).save(unsupported))
        XCTAssertEqual(try InventoryReviewCheckpointGRDBStore(databaseURL: url).load()?.pendingCommand, pending)
    }

    func testDraftReopenPreservesEditsIdentifiersAndDispositions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("draft.sqlite")
        let parsed = try FoodListParser.parse("20 g oats\n100 ml milk")
        var first = FoodListLineDraft(parsed: parsed[0], operationID: try id(1), evidenceID: try id(2))
        first.query = "rolled oats"; first.quantityText = "25"
        let second = FoodListLineDraft(parsed: parsed[1], operationID: try id(3), evidenceID: try id(4))
        let checkpoint = FoodListCheckpoint(input: "20 g oats\n100 ml milk", inputMethod: .reviewedSpeechText,
            drafts: [first, second], dispositions: ["saved", "deferred"], savedIDs: [try id(5), nil], selectedID: second.id)
        try FoodListCheckpointGRDBStore(databaseURL: url).save(checkpoint)
        let loaded = try XCTUnwrap(FoodListCheckpointGRDBStore(databaseURL: url).load())
        XCTAssertEqual(loaded.drafts, [first, second])
        XCTAssertEqual(loaded.dispositions, ["saved", "deferred"])
        XCTAssertEqual(loaded.selectedID, second.id)
        XCTAssertEqual(loaded.inputMethod, .reviewedSpeechText)
        var invalid = loaded; invalid.schemaVersion = 99
        XCTAssertThrowsError(try FoodListCheckpointGRDBStore(databaseURL: url).save(invalid))
        XCTAssertEqual(try FoodListCheckpointGRDBStore(databaseURL: url).load()?.drafts, loaded.drafts)
        XCTAssertThrowsError(try FoodListCheckpointGRDBStore(databaseURL: url, protectedData: ProtectedDataAvailability { false }))
    }

    func testInventoryBackupRestoresHistoryAndFavouritesWithoutOverwritingDivergence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try LocalInventoryGRDBStore(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let target = try LocalInventoryGRDBStore(databaseURL: directory.appendingPathComponent("target.sqlite"))
        let product = try InventoryProductVersion(productID: id(10), version: 1, name: "Synthetic oats", aliases: ["breakfast oats"], updatedAt: Date(timeIntervalSince1970: 1700000000), favourite: true, usualPortion: InventoryAmount(value: 25, unit: .grams))
        let text = "Synthetic oats 500 g £1.00"
        let receipt = try InventorySource(contentID: SHA256Digester().sha256(Data(text.utf8)), kind: .receipt, displayName: "Invented receipt", originalBytes: Data(text.utf8), extractedText: text, extractionVersion: "synthetic-v1", importedAt: Date(timeIntervalSince1970: 1700000000))
        let review = try InventoryReviewRevision(sourceID: receipt.contentID, lineNumber: 1, version: 1, disposition: .accepted, productID: product.productID, productVersion: 1, correctedDescription: product.name, reviewedAt: Date(timeIntervalSince1970: 1700000000))
        let command = InventoryCommand(operationID: try id(11), expectedRevision: 0, mutations: [.source(receipt), .product(product), .review(review)])
        _ = try source.commit(command)
        let backup = try source.exportBackup()
        try target.restoreBackup(backup)
        try target.restoreBackup(backup)
        XCTAssertEqual(try target.snapshot(), try source.snapshot())
        XCTAssertEqual(try target.snapshot().products.first?.usualPortion?.value, 25)
        XCTAssertEqual(try target.snapshot().sources.first?.originalBytes, Data(text.utf8))
        XCTAssertEqual(try target.snapshot().reviewHistory.first, review)
        let correction = try InventoryProductVersion(productID: id(10), version: 2, name: "Corrected oats", updatedAt: Date(timeIntervalSince1970: 1700000001))
        _ = try source.commit(InventoryCommand(operationID: id(12), expectedRevision: 1, mutations: [.product(correction)]))
        try target.restoreBackup(source.exportBackup())
        XCTAssertEqual(try target.snapshot(), try source.snapshot())
        try target.restoreBackup(backup)
        XCTAssertEqual(try target.snapshot().revision, 2, "An older compatible backup never removes newer data")
        let divergent = try LocalInventoryGRDBStore(databaseURL: directory.appendingPathComponent("divergent.sqlite"))
        _ = try divergent.commit(InventoryCommand(operationID: id(13), expectedRevision: 0, mutations: [.product(product)]))
        let before = try divergent.snapshot()
        XCTAssertThrowsError(try divergent.restoreBackup(backup))
        XCTAssertEqual(try divergent.snapshot(), before)
        var corrupted = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        corrupted["sha256"] = String(repeating: "a", count: 64)
        XCTAssertThrowsError(try target.restoreBackup(JSONSerialization.data(withJSONObject: corrupted)))
        XCTAssertEqual(try target.snapshot().revision, 2)
    }
}
