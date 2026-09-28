import FoodLedgerApplication
import FoodLedgerPresentation
import Foundation
import XCTest

@MainActor
final class FoodWebDiscoveryPresentationTests: XCTestCase {
    private let key = "synthetic-key-for-contract-tests-only"

    func testAbsentKeyAndTypingNeverCallProviderThenSaveAndExplicitSearch() async throws {
        let provider = DiscoverySpy()
        let keys = MemoryWebKeys()
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        model.foodTerms = "Greek yoghurt 10% fat"
        model.keyEntry = key
        await model.searchTheWeb()
        var counts = await provider.counts()
        XCTAssertEqual(counts, [0, 0])
        XCTAssertFalse(model.canSearch)
        await model.validateAndSaveKey()
        counts = await provider.counts()
        XCTAssertEqual(counts, [1, 0])
        XCTAssertTrue(model.canSearch)
        XCTAssertEqual(try keys.load(), key)
        XCTAssertEqual(model.keyEntry, "")
        await model.searchTheWeb()
        counts = await provider.counts()
        XCTAssertEqual(counts, [1, 1])
        XCTAssertEqual(model.result?.leads.count, 1)
        XCTAssertNil(model.searchMessage)
        model.foodTerms = "whole milk"
        XCTAssertNil(model.result)
        counts = await provider.counts()
        XCTAssertEqual(counts, [1, 1])
        model.removeKey()
        XCTAssertNil(try keys.load())
        XCTAssertFalse(model.canSearch)
    }

    func testRejectedValidationAndTransientValidationNeverStoreNewKey() async throws {
        for error in [FoodWebDiscoveryError.credentialRejected, .quotaExceeded, .permissionDenied, .serviceUnavailable] {
            let provider = DiscoverySpy(error: error)
            let keys = MemoryWebKeys()
            let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
            model.keyEntry = key
            await model.validateAndSaveKey()
            XCTAssertNil(try keys.load())
            XCTAssertFalse(model.keyIsUsable)
            XCTAssertTrue(model.keyMessage?.contains("not saved") == true)
            XCTAssertEqual(model.keyEntry, "")
        }
    }

    func testSearchRejectionDisablesKeyButQuotaAndNetworkPreserveIt() async {
        for error in [FoodWebDiscoveryError.credentialRejected, .quotaExceeded, .permissionDenied, .serviceUnavailable] {
            let keys = MemoryWebKeys(key: key)
            let model = FoodWebDiscoveryViewModel(provider: DiscoverySpy(error: error, searchOnlyError: true), keys: keys)
            model.foodTerms = "milk"
            XCTAssertFalse(model.canSearch)
            await model.revalidateSavedKey()
            XCTAssertTrue(model.canSearch)
            await model.searchTheWeb()
            XCTAssertEqual(model.keyIsUsable, error != .credentialRejected)
            if error == .credentialRejected { XCTAssertNil(try? keys.load()) }
            XCTAssertNil(model.result)
            XCTAssertNotNil(model.searchMessage)
        }
    }

    func testDeleteDuringValidationCannotResurrectCredential() async throws {
        let provider = DiscoverySpy(suspended: true)
        let keys = MemoryWebKeys()
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        model.keyEntry = key
        let work = Task { await model.validateAndSaveKey() }
        await provider.waitUntilPending()
        XCTAssertTrue(model.isValidating)
        model.removeKey()
        await provider.release()
        await work.value
        XCTAssertFalse(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable)
        XCTAssertNil(try keys.load())
    }

    func testEditedQueryRemovalAndLeavingDiscardEvenCancellationIgnoringProvider() async {
        for action in ["edit", "remove", "leave"] {
            let provider = DiscoverySpy(suspended: true, suspendOnlyOnSearch: true)
            let model = FoodWebDiscoveryViewModel(provider: provider, keys: MemoryWebKeys(key: key))
            model.foodTerms = "milk"
            await model.revalidateSavedKey()
            let work = Task { await model.searchTheWeb() }
            await provider.waitUntilPending()
            XCTAssertTrue(model.isSearching)
            await model.searchTheWeb() // A second tap cannot launch a concurrent request.
            if action == "edit" { model.foodTerms = "rice" }
            else if action == "remove" { model.removeKey() }
            else { model.cancelPending() }
            await provider.release()
            await work.value
            XCTAssertNil(model.result)
            XCTAssertFalse(model.isSearching)
            let counts = await provider.counts()
            XCTAssertEqual(counts, [1, 1])
        }
    }

    func testKeychainReadSaveAndDeleteFailuresRemainVisible() async {
        let keys = MemoryWebKeys(fails: true)
        let model = FoodWebDiscoveryViewModel(provider: DiscoverySpy(), keys: keys)
        XCTAssertFalse(model.keyIsUsable)
        XCTAssertNotNil(model.keyMessage)
        model.keyEntry = key
        await model.validateAndSaveKey()
        XCTAssertFalse(model.keyIsUsable)
        XCTAssertTrue(model.keyMessage?.contains("could not save") == true)
        model.removeKey()
        XCTAssertTrue(model.keyMessage?.contains("Could not remove") == true)
    }

    func testNoResultsAndQueryBounds() async {
        let model = FoodWebDiscoveryViewModel(provider: DiscoverySpy(empty: true), keys: MemoryWebKeys(key: key))
        model.foodTerms = String(repeating: "x", count: 301)
        XCTAssertFalse(model.canSearch)
        model.foodTerms = "rice"
        XCTAssertFalse(model.canSearch)
        await model.revalidateSavedKey()
        XCTAssertTrue(model.canSearch)
        await model.searchTheWeb()
        XCTAssertTrue(model.result?.leads.isEmpty == true)
        XCTAssertTrue(model.searchMessage?.contains("No cited") == true)
    }

    func testFailedRemovalCannotReactivateRetainedKeyOnReopen() async throws {
        let keys = MemoryWebKeys(key: key, deleteFails: true)
        let first = FoodWebDiscoveryViewModel(provider: DiscoverySpy(), keys: keys)
        first.foodTerms = "milk"
        XCTAssertFalse(first.canSearch)
        await first.revalidateSavedKey()
        XCTAssertTrue(first.canSearch)
        first.removeKey()
        XCTAssertFalse(first.canSearch)
        XCTAssertNotNil(try keys.load())

        let reopened = FoodWebDiscoveryViewModel(provider: DiscoverySpy(), keys: keys)
        reopened.foodTerms = "milk"
        XCTAssertTrue(reopened.hasSavedKey)
        XCTAssertFalse(reopened.keyIsUsable)
        XCTAssertFalse(reopened.canSearch)
    }

    func testSuggestionsPreserveSuppliedHTMLInsideRestrictedDocument() {
        let html = "<style>.chip{color:red}</style><a href='https://www.google.com/search?q=milk'>Milk</a>"
        let document = FoodWebSearchSuggestions.document(html)
        XCTAssertTrue(document.contains(html))
        XCTAssertTrue(document.contains("default-src 'none'"))
        XCTAssertTrue(document.contains("form-action 'none'"))
        XCTAssertFalse(FoodWebLinkPolicy.isAllowed(URL(string: "http://example.com")!))
        XCTAssertFalse(FoodWebLinkPolicy.isAllowed(URL(string: "file:///tmp/key")!))
        XCTAssertTrue(FoodWebLinkPolicy.isAllowed(URL(string: "https://example.com")!))
    }
}

private actor DiscoverySpy: FoodWebDiscovering {
    let error: FoodWebDiscoveryError?
    let suspended: Bool
    let searchOnlyError: Bool
    let suspendOnlyOnSearch: Bool
    let empty: Bool
    var validations = 0
    var searches = 0
    var continuation: CheckedContinuation<Void, Never>?
    init(error: FoodWebDiscoveryError? = nil, suspended: Bool = false, empty: Bool = false,
         searchOnlyError: Bool = false, suspendOnlyOnSearch: Bool = false) {
        self.error = error; self.suspended = suspended; self.empty = empty
        self.searchOnlyError = searchOnlyError; self.suspendOnlyOnSearch = suspendOnlyOnSearch
    }
    func counts() -> [Int] { [validations, searches] }
    func validate(key: String) async throws {
        validations += 1
        if suspended && !suspendOnlyOnSearch { await withCheckedContinuation { continuation = $0 } }
        if let error, !searchOnlyError { throw error }
    }
    func discover(foodTerms: String, key: String) async throws -> FoodWebDiscoveryResult {
        searches += 1
        if suspended { await withCheckedContinuation { continuation = $0 } }
        if let error { throw error }
        return FoodWebDiscoveryResult(leads: empty ? [] : [FoodWebLead(title: "Manufacturer", url: URL(string: "https://example.com/milk")!)], searchSuggestionsHTML: nil)
    }
    func waitUntilPending() async {
        for _ in 0..<10_000 {
            if continuation != nil { return }
            await Task.yield()
        }
        XCTFail("Provider request did not start")
    }
    func release() { continuation?.resume(); continuation = nil }
}

private final class MemoryWebKeys: FoodWebKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    private let fails: Bool
    private let deleteFails: Bool
    init(key: String? = nil, fails: Bool = false, deleteFails: Bool = false) {
        self.key = key; self.fails = fails; self.deleteFails = deleteFails
    }
    func load() throws -> String? { try lock.withLock { if fails { throw CocoaError(.fileReadNoPermission) }; return key } }
    func save(_ key: String) throws { try lock.withLock { if fails { throw CocoaError(.fileWriteNoPermission) }; self.key = key } }
    func delete() throws { try lock.withLock { if fails || deleteFails { throw CocoaError(.fileWriteNoPermission) }; key = nil } }
}
