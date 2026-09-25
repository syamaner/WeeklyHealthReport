import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import XCTest

@MainActor
final class LocalInventoryPresentationTests: XCTestCase {
    func testImportRequiresExplicitChoiceAndCorrectionInvalidatesIt() throws {
        let model = try makeModel()
        model.paste = "Sample oats 500 g £2.20"
        model.importPaste()
        let line = try XCTUnwrap(model.activeSource?.lines.first)
        XCTAssertFalse(model.save(line, disposition: .accepted))
        XCTAssertTrue(model.snapshot.products.isEmpty)
        var draft = model.draft(for: line)
        draft.createProduct = true
        model.update(draft, line: line)
        XCTAssertTrue(model.save(line, disposition: .accepted))
        XCTAssertFalse(try XCTUnwrap(model.snapshot.reviewHistory.last).received)
        XCTAssertNil(model.snapshot.products[0].remaining)
        draft = model.draft(for: line)
        XCTAssertNotNil(draft.selectedProductID)
        draft.description = "Different oats"
        model.update(draft, line: line)
        XCTAssertNil(model.draft(for: line).selectedProductID)
        XCTAssertFalse(model.draft(for: line).createProduct)
        XCTAssertFalse(model.save(line, disposition: .accepted))
    }

    func testBatchReportsPartialSaveAndDurableDeferredUndo() throws {
        let store = InMemoryInventoryStore()
        let model = try makeModel(store)
        model.paste = "Sample oats 500 g\nSample rice 1 kg"
        model.importPaste()
        let source = try XCTUnwrap(model.activeSource)
        var draft = model.draft(for: source.lines[0])
        draft.createProduct = true
        model.update(draft, line: source.lines[0])
        model.selectedLines = Set(source.lines.map { source.lineKey($0.lineNumber) })
        model.acceptSelected()
        XCTAssertTrue(model.message?.contains("Saved 1 of 2") == true)
        XCTAssertEqual(model.snapshot.reviewHistory.count, 1)
        XCTAssertEqual(model.selectedLines.count, 1)
        XCTAssertTrue(model.save(source.lines[0], disposition: .deferred))
        let reopened = try makeModel(store)
        XCTAssertEqual(reopened.activeSource?.contentID, source.contentID)
        XCTAssertEqual(reopened.snapshot.review(sourceID: source.contentID, lineNumber: 1)?.disposition, .deferred)
        XCTAssertEqual(reopened.snapshot.reviewHistory.count, 2)
    }

    func testLostResponseRetryKeepsSameOperationAndNoDuplicateProduct() throws {
        let store = LostResponseStore()
        let model = try makeModel(store)
        model.paste = "Sample oats 500 g"
        model.importPaste()
        let line = try XCTUnwrap(model.activeSource?.lines.first)
        var draft = model.draft(for: line)
        draft.createProduct = true
        draft.received = true
        model.update(draft, line: line)
        store.failAfterNextCommit = true
        XCTAssertFalse(model.save(line, disposition: .accepted))
        let pendingID = try XCTUnwrap(model.pendingCommand?.operationID)
        draft.description = "Must not edit uncertain save"
        model.update(draft, line: line)
        XCTAssertNotEqual(model.draft(for: line).description, draft.description)
        XCTAssertTrue(model.retryPending())
        XCTAssertNil(model.pendingCommand)
        XCTAssertEqual(store.lastOperation, pendingID)
        XCTAssertEqual(model.snapshot.products.count, 1)
        XCTAssertEqual(model.snapshot.reviewHistory.count, 1)
        XCTAssertTrue(model.snapshot.reviewHistory[0].received)
    }

    func testStaleSnapshotCanReloadWithoutRetryDeadlock() throws {
        let store = InMemoryInventoryStore()
        let model = try makeModel(store)
        model.paste = "Sample oats 500 g"
        model.importPaste()
        let other = try makeModel(store)
        let line = try XCTUnwrap(model.activeSource?.lines.first)
        XCTAssertTrue(other.save(line, disposition: .declined))
        XCTAssertFalse(model.save(line, disposition: .deferred))
        XCTAssertNil(model.pendingCommand)
        model.reload()
        XCTAssertTrue(model.save(line, disposition: .deferred))
        XCTAssertEqual(model.snapshot.reviewHistory.count, 2)
    }

    func testBadNumbersDoNotBecomeUnknownSilently() throws {
        let model = try makeModel()
        model.paste = "Sample oats"
        model.importPaste()
        let line = try XCTUnwrap(model.activeSource?.lines.first)
        var draft = model.draft(for: line)
        draft.createProduct = true
        draft.purchaseCount = "maybe two"
        model.update(draft, line: line)
        XCTAssertFalse(model.save(line, disposition: .accepted))
        XCTAssertNil(model.pendingCommand)
        XCTAssertTrue(model.snapshot.products.isEmpty)
    }

    func testExplicitStockAssertionAndCorrectionAreVersionedSeparately() throws {
        let model = try makeModel()
        model.paste = "Sample oats 500 g"
        model.importPaste()
        let line = try XCTUnwrap(model.activeSource?.lines.first)
        var draft = model.draft(for: line)
        draft.createProduct = true
        draft.remaining = "250"
        let assertionDate = draft.assertionDate
        model.update(draft, line: line)
        XCTAssertTrue(model.save(line, disposition: .accepted))
        XCTAssertEqual(model.snapshot.products[0].remaining?.amount.value, 250)
        XCTAssertEqual(model.snapshot.products[0].remaining?.assertedAt, assertionDate)
        draft = model.draft(for: line)
        draft.editProduct = true
        draft.remaining = "0.00"
        model.update(draft, line: line)
        XCTAssertTrue(model.save(line, disposition: .accepted))
        XCTAssertEqual(model.snapshot.products.count, 1)
        XCTAssertEqual(model.snapshot.productVersions.count, 2)
        XCTAssertEqual(model.snapshot.products[0].remaining?.amount.value, 0)
        XCTAssertEqual(model.snapshot.reviewHistory.map(\.productVersion), [1, 2])
    }

    func testVariableWeightRequiresExplicitAcquisitionCorrection() throws {
        let model = try makeModel()
        model.paste = "Carrots 0.75 kg @ 1.25/kg"
        model.importPaste()
        let line = try XCTUnwrap(model.activeSource?.lines.first)
        var draft = model.draft(for: line)
        draft.createProduct = true
        draft.received = true
        model.update(draft, line: line)
        XCTAssertFalse(model.save(line, disposition: .accepted))
        XCTAssertNil(model.pendingCommand, "A missing correction is editable, not an uncertain persistence failure")
        draft.acquisitionCorrection = "Checked the receipt: 750 g carrots were delivered; 1.25/kg is only the rate."
        draft.packAmount = "750"
        draft.packUnit = .grams
        model.update(draft, line: line)
        XCTAssertTrue(model.save(line, disposition: .accepted))
        XCTAssertEqual(model.snapshot.reviewHistory.last?.packAmount?.value, 750)
        XCTAssertFalse(model.snapshot.reviewHistory.last?.acquisitionCorrection.isEmpty ?? true)
        XCTAssertNil(model.snapshot.products[0].remaining)
    }

    private func makeModel(_ store: any InventoryStoring = InMemoryInventoryStore()) throws -> LocalInventoryViewModel {
        try LocalInventoryViewModel(service: LocalInventoryService(store: store, digester: SHA256Digester(), clock: Clock()), ids: RandomLedgerIDGenerator(), clock: Clock())
    }
    private struct Clock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }
}

private final class LostResponseStore: InventoryStoring, @unchecked Sendable {
    let base = InMemoryInventoryStore()
    var failAfterNextCommit = false
    var lastOperation: OperationID?
    func snapshot() throws -> InventorySnapshot { try base.snapshot() }
    func commit(_ command: InventoryCommand) throws -> InventorySnapshot {
        lastOperation = command.operationID
        let result = try base.commit(command)
        if failAfterNextCommit { failAfterNextCommit = false; throw CocoaError(.fileReadUnknown) }
        return result
    }
}
