import FoodLedgerApplication
import FoodLedgerPresentation
import Foundation
import XCTest

@MainActor
final class FoodWebDiscoveryPresentationTests: XCTestCase {
    private let key = "synthetic-key-for-contract-tests-only"

    func testAutomaticCredentialGrantsAreExactTransientAndEditorClosePreservesValidation() async throws {
        let keys = MemoryWebKeys(key: key)
        let provider = DiscoverySpy()
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        XCTAssertThrowsError(try model.credentialForRequest())
        await model.revalidateSavedKey()
        let old = try model.credentialForRequest()
        XCTAssertTrue(model.isCurrent(old))
        XCTAssertFalse(String(describing: old).contains(key))
        XCTAssertFalse(String(reflecting: old).contains(key))
        model.closeCredentialEditor()
        XCTAssertTrue(model.keyIsUsable)
        XCTAssertFalse(model.isCurrent(old))
        let current = try model.credentialForRequest()
        XCTAssertTrue(model.isCurrent(current))
        model.reject(old)
        XCTAssertEqual(try keys.load(), key)
        let replacement = "replacement-synthetic-key-for-tests"
        try keys.save(replacement)
        model.reject(current)
        XCTAssertEqual(try keys.load(), replacement)
        XCTAssertFalse(model.keyIsUsable)
        XCTAssertThrowsError(try model.credentialForRequest())
        let counts = await provider.counts()
        XCTAssertEqual(counts, [1, 0])
    }

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

    // MARK: A failed key read is retried (#493)

    func testAFailedReadIsNotNoKeyAndARecheckAfterUnlockFindsTheSavedKey() async {
        let keys = LockableWebKeys(key: key, failingReads: 1)
        let provider = DiscoverySpy()
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        XCTAssertTrue(model.keyLoadFailed, "a read that throws is not \"no key saved\"")
        XCTAssertFalse(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable)
        XCTAssertTrue(model.keyMessage?.contains("could not be read yet") == true)
        XCTAssertThrowsError(try model.credentialForRequest())

        model.recheckSavedKey()
        XCTAssertFalse(model.keyLoadFailed)
        XCTAssertTrue(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable, "a recheck never validates or enables the key")
        XCTAssertEqual(model.keyMessage, "Revalidate the saved key before searching the web.")
        XCTAssertThrowsError(try model.credentialForRequest())
        var counts = await provider.counts()
        XCTAssertEqual(counts, [0, 0], "a recheck sends nothing")

        await model.revalidateSavedKey()
        XCTAssertTrue(model.keyIsUsable, "the recovered key can now be revalidated explicitly")
        counts = await provider.counts()
        XCTAssertEqual(counts, [1, 0])
        let reads = keys.reads
        model.recheckSavedKey()
        XCTAssertEqual(keys.reads, reads, "after a successful read a recheck does nothing")
        XCTAssertTrue(model.keyIsUsable, "a recheck never revokes a validated key")
    }

    func testAReadThatKeepsFailingStaysFailedAndNeverValid() async {
        let keys = LockableWebKeys(key: key, failingReads: .max)
        let provider = DiscoverySpy()
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        for _ in 0..<3 {
            model.recheckSavedKey()
            XCTAssertTrue(model.keyLoadFailed)
            XCTAssertFalse(model.hasSavedKey)
            XCTAssertFalse(model.keyIsUsable)
        }
        await model.revalidateSavedKey()
        XCTAssertFalse(model.keyIsUsable)
        let counts = await provider.counts()
        XCTAssertEqual(counts, [0, 0], "nothing is sent while the key cannot be read")
        XCTAssertThrowsError(try model.credentialForRequest())
    }

    func testNoSavedKeyStaysDistinctFromAFailedRead() {
        let keys = LockableWebKeys(key: nil, failingReads: 0)
        let model = FoodWebDiscoveryViewModel(provider: DiscoverySpy(), keys: keys)
        XCTAssertFalse(model.keyLoadFailed)
        XCTAssertFalse(model.hasSavedKey)
        XCTAssertNil(model.keyMessage)
        model.recheckSavedKey()
        XCTAssertEqual(keys.reads, 1, "with no failed read there is nothing to recheck")

        let locked = LockableWebKeys(key: nil, failingReads: 1)
        let recovered = FoodWebDiscoveryViewModel(provider: DiscoverySpy(), keys: locked)
        XCTAssertTrue(recovered.keyLoadFailed)
        recovered.recheckSavedKey()
        XCTAssertFalse(recovered.keyLoadFailed)
        XCTAssertFalse(recovered.hasSavedKey, "a readable store with no key is no key")
        XCTAssertNil(recovered.keyMessage, "the unreadable message clears once the store is read")
    }

    func testALockDuringValidationIsRecordedAsUnreadableAndRecheckedNotReadAsNoKey() async {
        let keys = LockableWebKeys(key: key, failingReads: 0)
        let provider = DiscoverySpy(suspended: true)
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        XCTAssertTrue(model.hasSavedKey)
        let work = Task { await model.revalidateSavedKey() }
        await provider.waitUntilPending()
        keys.locked = true
        await provider.release()
        await work.value
        XCTAssertFalse(model.keyIsUsable, "a Keychain error is never success")
        XCTAssertFalse(model.hasSavedKey)
        XCTAssertTrue(model.keyLoadFailed, "a failed read after a request is unknown, not no key")

        keys.locked = false
        model.recheckSavedKey()
        XCTAssertFalse(model.keyLoadFailed)
        XCTAssertTrue(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable)
    }

    func testSavingANewKeyWhileTheReadFailedClearsTheFailedState() async {
        let keys = LockableWebKeys(key: nil, failingReads: 1)
        let provider = DiscoverySpy()
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        XCTAssertTrue(model.keyLoadFailed)
        model.keyEntry = key
        await model.validateAndSaveKey()
        XCTAssertFalse(model.keyLoadFailed)
        XCTAssertTrue(model.hasSavedKey)
        XCTAssertTrue(model.keyIsUsable)
    }

    func testAReadFailureDuringRevalidationIsRecordedAsUnreadAndRecheckedOnUnlock() async {
        let keys = LockableWebKeys(key: key, failingReads: 0)
        let provider = DiscoverySpy()
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        XCTAssertTrue(model.hasSavedKey)
        XCTAssertFalse(model.keyLoadFailed)
        keys.locked = true
        await model.revalidateSavedKey()
        XCTAssertTrue(model.keyLoadFailed, "a later read that throws is unknown, not no key")
        XCTAssertFalse(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable)
        XCTAssertTrue(model.keyMessage?.contains("could not be read yet") == true)
        var counts = await provider.counts()
        XCTAssertEqual(counts, [0, 0], "nothing is sent when the key cannot be read")

        keys.locked = false
        model.recheckSavedKey()
        XCTAssertFalse(model.keyLoadFailed)
        XCTAssertTrue(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable, "a recheck never validates or enables the key")
        counts = await provider.counts()
        XCTAssertEqual(counts, [0, 0])
        await model.revalidateSavedKey()
        XCTAssertTrue(model.keyIsUsable)
    }

    func testAReadFailureWhenGrantingARequestIsRecordedAsUnreadAndRechecked() async {
        let keys = LockableWebKeys(key: key, failingReads: 0)
        let model = FoodWebDiscoveryViewModel(provider: DiscoverySpy(), keys: keys)
        await model.revalidateSavedKey()
        XCTAssertTrue(model.keyIsUsable)
        keys.locked = true
        XCTAssertThrowsError(try model.credentialForRequest())
        XCTAssertTrue(model.keyLoadFailed)
        XCTAssertFalse(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable)

        keys.locked = false
        model.recheckSavedKey()
        XCTAssertFalse(model.keyLoadFailed)
        XCTAssertTrue(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable, "the recovered key needs explicit revalidation")
        XCTAssertThrowsError(try model.credentialForRequest())
    }

    func testARecheckDuringValidationRunsWhenValidationFails() async {
        let keys = LockableWebKeys(key: key, failingReads: 1)
        let provider = DiscoverySpy(error: .connectionFailed, suspended: true)
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        XCTAssertTrue(model.keyLoadFailed)
        model.keyEntry = "replacement-synthetic-key-for-tests"
        let work = Task { await model.validateAndSaveKey() }
        await provider.waitUntilPending()
        model.recheckSavedKey()
        XCTAssertTrue(model.keyLoadFailed, "the recheck waits while validation runs")
        await provider.release()
        await work.value
        XCTAssertFalse(model.isValidating)
        XCTAssertFalse(model.keyLoadFailed, "the deferred recheck runs once validation fails")
        XCTAssertTrue(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable, "a recheck never validates or enables the key")
        XCTAssertTrue(model.keyMessage?.contains("The new key was not saved.") == true,
                      "the validation outcome stays visible")
        XCTAssertEqual(try keys.load(), key)
        let counts = await provider.counts()
        XCTAssertEqual(counts, [1, 0], "the recheck sends nothing")
    }

    func testARecheckDuringValidationRunsWhenValidationIsCancelled() async {
        let keys = LockableWebKeys(key: key, failingReads: 1)
        let provider = DiscoverySpy(suspended: true)
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        XCTAssertTrue(model.keyLoadFailed)
        model.keyEntry = "replacement-synthetic-key-for-tests"
        let work = Task { await model.validateAndSaveKey() }
        await provider.waitUntilPending()
        model.recheckSavedKey()
        XCTAssertTrue(model.keyLoadFailed)
        model.closeCredentialEditor()
        XCTAssertFalse(model.isValidating)
        XCTAssertFalse(model.keyLoadFailed, "the deferred recheck runs once validation is cancelled")
        XCTAssertTrue(model.hasSavedKey)
        XCTAssertFalse(model.keyIsUsable)
        await provider.release()
        await work.value
        XCTAssertFalse(model.keyIsUsable, "a cancelled validation never enables a key")
        XCTAssertEqual(try keys.load(), key, "a cancelled validation saves nothing")
        let reads = keys.reads
        model.recheckSavedKey()
        XCTAssertEqual(keys.reads, reads, "the pending recheck ran once and is not repeated")
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

    func testReplacementKeyCannotInheritEarlierValidation() async throws {
        let provider = DiscoverySpy(); let keys = MemoryWebKeys(key: key)
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        model.foodTerms = "milk"; await model.revalidateSavedKey()
        let replacement = "different-synthetic-key-for-tests"
        try keys.save(replacement)
        await model.searchTheWeb()
        XCTAssertFalse(model.keyIsUsable); XCTAssertNil(model.result)
        XCTAssertEqual(try keys.load(), replacement)
        let counts = await provider.counts(); XCTAssertEqual(counts, [1, 0])
    }

    func testLateSuccessOrFailureCannotPublishForOrDeleteReplacementKey() async throws {
        for error: FoodWebDiscoveryError? in [nil, .credentialRejected, .quotaExceeded, .permissionDenied, .serviceUnavailable] {
            let provider = DiscoverySpy(error: error, suspended: true, searchOnlyError: true, suspendOnlyOnSearch: true)
            let keys = MemoryWebKeys(key: key)
            let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
            model.foodTerms = "milk"; await model.revalidateSavedKey()
            let work = Task { await model.searchTheWeb() }
            await provider.waitUntilPending()
            let replacement = "different-synthetic-key-for-tests"
            try keys.save(replacement)
            await provider.release(); await work.value
            XCTAssertEqual(try keys.load(), replacement)
            XCTAssertTrue(model.hasSavedKey); XCTAssertFalse(model.keyIsUsable); XCTAssertNil(model.result)
        }
    }

    func testReplacementDuringRevalidationIsNotMarkedValid() async throws {
        let provider = DiscoverySpy(suspended: true); let keys = MemoryWebKeys(key: key)
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        let work = Task { await model.revalidateSavedKey() }
        await provider.waitUntilPending()
        let replacement = "different-synthetic-key-for-tests"
        try keys.save(replacement)
        await provider.release(); await work.value
        XCTAssertEqual(try keys.load(), replacement)
        XCTAssertFalse(model.keyIsUsable); XCTAssertFalse(model.isValidating)
    }

    func testLeavingRequiresFreshValidationAndInvalidReplacementDoesNotReuseOldFlag() async throws {
        let provider = DiscoverySpy(); let keys = MemoryWebKeys(key: key)
        let model = FoodWebDiscoveryViewModel(provider: provider, keys: keys)
        model.foodTerms = "milk"; await model.revalidateSavedKey()
        model.cancelPending(); await model.searchTheWeb()
        XCTAssertFalse(model.keyIsUsable)
        await model.revalidateSavedKey(); XCTAssertTrue(model.keyIsUsable)
        model.keyEntry = "bad"; await model.validateAndSaveKey()
        XCTAssertFalse(model.keyIsUsable); XCTAssertEqual(try keys.load(), key)
        let counts = await provider.counts(); XCTAssertEqual(counts, [2, 0])
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

/// A synthetic key store whose first `failingReads` reads throw, as the Keychain does before first
/// unlock (#493). Writes always succeed; the key is never a real credential.
private final class LockableWebKeys: FoodWebKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    private var failingReads: Int
    private(set) var reads = 0
    private var lockedNow = false
    /// While true every read throws, as when the device locks during a request.
    var locked: Bool {
        get { lock.withLock { lockedNow } }
        set { lock.withLock { lockedNow = newValue } }
    }
    init(key: String?, failingReads: Int) { self.key = key; self.failingReads = failingReads }
    func load() throws -> String? {
        try lock.withLock {
            reads += 1
            if lockedNow { throw CocoaError(.fileReadNoPermission) }
            if failingReads > 0 { failingReads -= 1; throw CocoaError(.fileReadNoPermission) }
            return key
        }
    }
    func save(_ key: String) throws { lock.withLock { self.key = key } }
    func delete() throws { lock.withLock { key = nil } }
}
