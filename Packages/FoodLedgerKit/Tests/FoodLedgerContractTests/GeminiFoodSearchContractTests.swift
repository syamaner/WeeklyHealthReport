import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

@MainActor
final class GeminiFoodSearchContractTests: XCTestCase {
    private func make(_ credentials: RuntimeCredentials, _ reviewer: RuntimeReview,
                      timeout: Duration = .seconds(50)) throws -> GeminiFoodSearch {
        try GeminiFoodSearch(credentials: credentials, reviewer: reviewer, admission: AlproSourceCandidateAdmission(),
            locale: LedgerText("en_GB"), timeout: timeout)
    }

    func testNamedDishCanReachGroundedDiscoveryWithoutAdmittingUnrelatedSourceNutrition() async throws {
        let text = "275g homemade lentil and tomato soup"
        let reviewer = RuntimeReview(source: try SourceAdmissionFixtures.source())
        let outcome = try await make(RuntimeCredentials(), reviewer).enrich(FoodSearchRemoteQuery(foodTerms: text))
        guard case let .noResult(route) = outcome else { return XCTFail("Alpro source is not soup nutrition") }
        XCTAssertNotNil(route.sourceDiscovery)
        let calls = await reviewer.calls
        XCTAssertEqual(calls, [text])
        XCTAssertNil(FoodQueryParser.parse(text).quantity)
        let blockedReviewer = RuntimeReview(source: nil)
        do {
            _ = try await make(RuntimeCredentials(), blockedReviewer).enrich(FoodSearchRemoteQuery(foodTerms: "100g soup and 50g bread"))
            XCTFail("Mixed quantities must not reach discovery")
        } catch { XCTAssertEqual(error as? FoodSearchEnrichmentError, .invalidQuery) }
        let blockedCalls = await blockedReviewer.calls
        XCTAssertTrue(blockedCalls.isEmpty)
    }

    func testUnavailableCredentialNeverCallsReview() async throws {
        let credentials = RuntimeCredentials(); credentials.available = false
        let reviewer = RuntimeReview(source: try SourceAdmissionFixtures.source())
        do { _ = try await make(credentials, reviewer).enrich(SourceAdmissionFixtures.query()); XCTFail() }
        catch { XCTAssertEqual(error as? FoodSearchEnrichmentError, .unavailable) }
        let calls = await reviewer.calls; XCTAssertTrue(calls.isEmpty)
    }

    func testVerifiedSourceValuesAndAttributionReachNormalCandidateWithoutModelNumbers() async throws {
        let reviewer = RuntimeReview(source: try SourceAdmissionFixtures.source())
        let result = try await make(RuntimeCredentials(), reviewer).enrich(SourceAdmissionFixtures.query())
        guard case let .confirmation(route) = result else { return XCTFail() }
        XCTAssertEqual(route.sourceDiscovery, RuntimeReview.discovery)
        XCTAssertEqual(route.matches.count, 1)
        XCTAssertEqual(FoodConfirmationState(input: route.confirmation).unresolvedIdentity.count, 6)
        XCTAssertFalse(FoodConfirmationState(input: route.confirmation).isGenericEstimate)
        guard case let .augmented(fat) = route.confirmation.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .fatTotal })?.value else { return XCTFail() }
        XCTAssertEqual(fat.amount, 1.9)
        let calls = await reviewer.calls; XCTAssertEqual(calls, ["Alpro Original soya drink"])
    }

    func testCitationOnlyOutcomeRetainsAttributionWhenMergedWithLocalResults() async throws {
        let remote = try await make(RuntimeCredentials(), RuntimeReview(source: nil)).enrich(SourceAdmissionFixtures.query())
        guard case let .noResult(empty) = remote else { return XCTFail() }
        XCTAssertEqual(empty.sourceDiscovery, RuntimeReview.discovery)
        let local = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()).search(
            GenericFoodSearchRequest(text: LedgerText("milk"), capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB")))
        guard case let .confirmation(before) = local,
              case let .confirmation(merged) = try FoodSearchResultMerger.merge(local, remote) else { return XCTFail() }
        XCTAssertEqual(merged.matches, before.matches)
        XCTAssertEqual(merged.sourceDiscovery, RuntimeReview.discovery)
        guard case let .confirmation(reverse) = try FoodSearchResultMerger.merge(remote, local) else { return XCTFail() }
        XCTAssertEqual(reverse.sourceDiscovery, RuntimeReview.discovery)
    }

    func testReplacementDuringReviewCannotPublishOrRejectNewCredential() async throws {
        for error: FoodWebDiscoveryError? in [nil, .credentialRejected] {
            let credentials = RuntimeCredentials()
            let reviewer = RuntimeReview(source: try SourceAdmissionFixtures.source(), error: error, held: true)
            let service = try make(credentials, reviewer)
            let task = Task { try await service.enrich(SourceAdmissionFixtures.query()) }
            await reviewer.waitUntilPending()
            credentials.generation += 1
            await reviewer.release()
            do { _ = try await task.value; XCTFail() }
            catch { XCTAssertEqual(error as? FoodSearchEnrichmentError, .unavailable) }
            XCTAssertEqual(credentials.rejections, 0)
            XCTAssertTrue(credentials.available)
        }
    }

    func testOnlyCurrentExplicitCredentialRejectionInvalidatesAuthority() async throws {
        let errors: [(FoodWebDiscoveryError, FoodSearchEnrichmentError)] = [
            (.credentialRejected, .credentialRejected), (.permissionDenied, .permissionDenied),
            (.quotaExceeded, .quotaExceeded), (.serviceUnavailable, .unavailable), (.invalidResponse, .invalidResponse)]
        for (providerError, expected) in errors {
            let credentials = RuntimeCredentials()
            do { _ = try await make(credentials, RuntimeReview(source: nil, error: providerError)).enrich(SourceAdmissionFixtures.query()); XCTFail() }
            catch { XCTAssertEqual(error as? FoodSearchEnrichmentError, expected) }
            XCTAssertEqual(credentials.rejections, providerError == .credentialRejected ? 1 : 0)
        }
    }

    func testCancellationAndExpiredReviewCannotRejectKeyOrPublish() async throws {
        for expire in [false, true] {
            let credentials = RuntimeCredentials()
            let reviewer = RuntimeReview(source: nil, error: .credentialRejected, held: true)
            let service = try make(credentials, reviewer, timeout: expire ? .milliseconds(20) : .seconds(50))
            let task = Task { try await service.enrich(SourceAdmissionFixtures.query()) }
            await reviewer.waitUntilPending()
            if expire { try await Task.sleep(for: .milliseconds(60)) } else { task.cancel() }
            await reviewer.release()
            do { _ = try await task.value; XCTFail() } catch { }
            XCTAssertEqual(credentials.rejections, 0)
            XCTAssertTrue(credentials.available)
        }
    }

    func testPartialSourceFailuresRetainAttributionAndNeverInvalidateGoogleCredential() async throws {
        for failure: FoodSourceReviewFailure in [.unsupportedSource, .unavailable, .invalidContent, .quotaExceeded, .timedOut] {
            let credentials = RuntimeCredentials()
            let remote = try await make(credentials, RuntimeReview(source: nil, partial: failure)).enrich(SourceAdmissionFixtures.query())
            guard case let .noResult(route) = remote else { return XCTFail() }
            XCTAssertEqual(route.sourceDiscovery, RuntimeReview.discovery)
            XCTAssertEqual(route.sourceReviewFailure, failure)
            XCTAssertEqual(credentials.rejections, 0); XCTAssertTrue(credentials.available)
            let local = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()).search(
                GenericFoodSearchRequest(text: LedgerText("milk"), capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB")))
            guard case let .confirmation(before) = local,
                  case let .confirmation(merged) = try FoodSearchResultMerger.merge(local, remote) else { return XCTFail() }
            XCTAssertEqual(merged.matches, before.matches)
            XCTAssertEqual(merged.sourceReviewFailure, failure)
            XCTAssertEqual(merged.sourceDiscovery, RuntimeReview.discovery)
            let success = try await make(credentials, RuntimeReview(source: nil)).enrich(SourceAdmissionFixtures.query())
            guard case let .confirmation(cleared) = try FoodSearchResultMerger.merge(.confirmation(merged), success) else { return XCTFail() }
            XCTAssertNil(cleared.sourceReviewFailure)
        }
    }

    func testSourceAdmissionExceptionCannotLoseAttributionOrAdmitNutrition() async throws {
        let html = SourceAdmissionFixtures.html.replacingOccurrences(of: "\"url\":\"https://www.alpro.com/en-gb/products/drinks/soya-original\"", with: "\"url\":\"https://www.alpro.com/en-gb/products/drinks/wrong\"")
        let reviewer = RuntimeReview(source: try SourceAdmissionFixtures.source(html: html))
        let remote = try await make(RuntimeCredentials(), reviewer).enrich(SourceAdmissionFixtures.query())
        guard case let .noResult(route) = remote else { return XCTFail() }
        XCTAssertEqual(route.sourceDiscovery, RuntimeReview.discovery)
        XCTAssertEqual(route.sourceReviewFailure, .invalidContent)
    }

    func testCoordinatorAddsSourceCandidateAfterLocalSearchWithoutSelectingIt() async throws {
        let finished = expectation(description: "Gemini stage finished")
        let reviewer = RuntimeReview(source: try SourceAdmissionFixtures.source())
        let coordinator = ProgressiveFoodSearchCoordinator(local: try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()),
            gemini: try make(RuntimeCredentials(), reviewer), services: .init(onlineDatabase: .disabled, gemini: .ready))
        coordinator.onUpdate = { if $0.pending == nil { finished.fulfill() } }
        coordinator.search(try GenericFoodSearchRequest(text: LedgerText("Alpro Original soya drink"),
            capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB")))
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertTrue(coordinator.snapshot.failures.isEmpty)
        guard case let .confirmation(route) = coordinator.snapshot.outcome else { return XCTFail() }
        XCTAssertTrue(route.matches.contains { $0.candidate.name.value == "Alpro Soya Original Drink 1L | Alpro UK" })
        XCTAssertEqual(route.sourceDiscovery, RuntimeReview.discovery)
        XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
        let calls = await reviewer.calls; XCTAssertEqual(calls.count, 1)
    }
}

@MainActor
private final class RuntimeCredentials: FoodWebCredentialAuthorizing {
    var generation = 0; var available = true; var rejections = 0
    func credentialForRequest() throws -> FoodWebRequestCredential {
        guard available else { throw FoodSearchEnrichmentError.unavailable }
        return .init(key: "synthetic-runtime-contract-test-key", generation: generation)
    }
    func isCurrent(_ credential: FoodWebRequestCredential) -> Bool { available && credential.generation == generation }
    func reject(_ credential: FoodWebRequestCredential) {
        guard isCurrent(credential) else { return }; rejections += 1; available = false
    }
}

private actor RuntimeReview: FoodGroundedSourceReviewing {
    static let discovery = FoodWebDiscoveryResult(leads: [.init(title: "Alpro", url: SourceAdmissionFixtures.url)],
        searchSuggestionsHTML: "<a>Original Google suggestion</a>", responseText: "Invented nutrition: fat 999g")
    let source: FoodReviewedSource?; let error: FoodWebDiscoveryError?; let held: Bool; let partial: FoodSourceReviewFailure?
    var calls: [String] = []
    private var pending: CheckedContinuation<Void, Never>?
    init(source: FoodReviewedSource?, error: FoodWebDiscoveryError? = nil, held: Bool = false, partial: FoodSourceReviewFailure? = nil) {
        self.source = source; self.error = error; self.held = held; self.partial = partial
    }
    func review(foodTerms: String, key: String) async throws -> FoodGroundedSourceReview {
        calls.append(foodTerms)
        if held { await withCheckedContinuation { pending = $0 } }
        if let error { throw error }
        if let partial { throw FoodGroundedSourcePartialFailure(discovery: Self.discovery, reason: partial) }
        return .init(discovery: Self.discovery, source: source)
    }
    func waitUntilPending() async { while pending == nil { await Task.yield() } }
    func release() { pending?.resume(); pending = nil }
}
