import CryptoKit
import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication

final class GeminiGroundedSourceReviewTests: XCTestCase {
    private let key = "synthetic-key-for-source-review-tests"
    private let sourceURL = URL(string: "https://source.example.com/food")!
    private let resolverURL = URL(string: "https://vertexaisearch.cloud.google.com/grounding-api-redirect/native")!
    private let html = Data("<table><tr><th>Typical values</th><td>per 100 ml</td></tr><tr><th>Energy</th><td>175 kJ / 42 kcal</td></tr><tr><th>Fat</th><td>1.9 g</td></tr><tr><th>Carbohydrate</th><td>2.7 g</td></tr><tr><th>Protein</th><td>3.3 g</td></tr></table>".utf8)

    private func page(requested: URL? = nil, final: URL? = nil, hops: [AcquiredFoodSourcePage.Hop]? = nil,
                      hash: String? = nil, body: Data? = nil) -> AcquiredFoodSourcePage {
        let body = body ?? html
        return AcquiredFoodSourcePage(requestedURL: requested ?? sourceURL, finalURL: final ?? sourceURL,
            hops: hops ?? [.init(url: sourceURL, status: 200)], html: body,
            sha256: hash ?? SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined(),
            retrievedAt: Date(timeIntervalSince1970: 1_000))
    }
    private func service(_ discovery: ReviewDiscoverySpy, _ source: ReviewAcquisitionSpy,
                         timeout: Duration = .seconds(50)) throws -> GeminiGroundedSourceReview {
        try GeminiGroundedSourceReview(discovery: discovery, acquisition: source,
            contentHosts: ["source.example.com"], timeout: timeout)
    }
    private func result(_ urls: [URL]) -> FoodWebDiscoveryResult {
        FoodWebDiscoveryResult(leads: urls.map { .init(title: "Do not trust this title", url: $0) },
            searchSuggestionsHTML: "<a>Preserved suggestion</a>", responseText: "[Wrong URL](https://other.example.com/fake) contains 999 kcal")
    }

    func testNativeCitationControlsOneAcquisitionAndValuesComeOnlyFromSource() async throws {
        let response = result([resolverURL, sourceURL])
        let discovery = ReviewDiscoverySpy(response)
        let source = ReviewAcquisitionSpy(page(requested: resolverURL,
            hops: [.init(url: resolverURL, status: 302), .init(url: sourceURL, status: 200)]))
        let review = try await service(discovery, source).review(foodTerms: "  milk  ", key: key)
        XCTAssertEqual(review.discovery, response)
        XCTAssertEqual(review.source?.citation.url, resolverURL)
        XCTAssertEqual(review.source?.panels.count, 1)
        XCTAssertEqual(review.source?.panels.first?.declarations.map(\.value.amount), [42, 1.9, 2.7, 3.3])
        XCTAssertTrue(review.source?.panels.first?.declarations.allSatisfy { $0.value.basis == .per100Millilitres } == true)
        let queries = await discovery.queries; XCTAssertEqual(queries, ["milk"])
        let urls = await source.urls; XCTAssertEqual(urls, [resolverURL])
        let validations = await discovery.validations; XCTAssertEqual(validations, 0)
    }

    func testUnadmittedAnnotationsAndModelWrittenURLsNeverBecomeSourceRequests() async throws {
        let bad = [URL(string: "https://other.example.com/page")!, URL(string: "http://source.example.com/food")!,
                   URL(string: "https://source.example.com.evil.com/page")!]
        let discovery = ReviewDiscoverySpy(result(bad)); let source = ReviewAcquisitionSpy(page())
        let review = try await service(discovery, source).review(foodTerms: "milk", key: key)
        XCTAssertNil(review.source)
        let urls = await source.urls; XCTAssertTrue(urls.isEmpty)
        let queries = await discovery.queries; XCTAssertEqual(queries.count, 1)
    }

    func testFirstEligibleAnnotationIsSelectedWithoutFollowingOtherLeads() async throws {
        let urls = [URL(string: "https://other.example.com/page")!, sourceURL, resolverURL]
        let source = ReviewAcquisitionSpy(page())
        _ = try await service(ReviewDiscoverySpy(result(urls)), source).review(foodTerms: "milk", key: key)
        let requested = await source.urls; XCTAssertEqual(requested, [sourceURL])
    }

    func testSourceFailureNeverRetriesDiscoveryOrAnotherPage() async throws {
        for error in [FoodSourceAcquisitionError.unavailable, .quotaExceeded, .timedOut, .responseTooLarge] {
            let discovery = ReviewDiscoverySpy(result([sourceURL, resolverURL]))
            let source = ReviewAcquisitionSpy(page(), error: error)
            do { _ = try await service(discovery, source).review(foodTerms: "milk", key: key); XCTFail() }
            catch let partial as FoodGroundedSourcePartialFailure {
                XCTAssertEqual(partial.discovery, result([sourceURL, resolverURL]))
                let expected: FoodSourceReviewFailure = error == .quotaExceeded ? .quotaExceeded : error == .timedOut ? .timedOut : error == .unavailable ? .unavailable : .invalidContent
                XCTAssertEqual(partial.reason, expected)
            }
            let calls = await discovery.queries; let urls = await source.urls
            XCTAssertEqual(calls.count, 1); XCTAssertEqual(urls, [sourceURL])
        }
    }

    func testProviderErrorsStayDistinctAndNeverAcquireSource() async throws {
        for error in [FoodWebDiscoveryError.credentialRejected, .permissionDenied, .quotaExceeded, .serviceUnavailable] {
            let discovery = ReviewDiscoverySpy(result([sourceURL]), error: error)
            let source = ReviewAcquisitionSpy(page())
            do { _ = try await service(discovery, source).review(foodTerms: "milk", key: key); XCTFail() }
            catch let actual as FoodWebDiscoveryError { XCTAssertEqual(actual, error) }
            let urls = await source.urls; XCTAssertTrue(urls.isEmpty)
        }
    }

    func testInvalidQueryOrKeyCannotStartDiscovery() async throws {
        for (terms, credential) in [("", key), (String(repeating: "x", count: 301), key), ("milk " + key, key), ("milk", "bad")] {
            let discovery = ReviewDiscoverySpy(result([sourceURL])); let source = ReviewAcquisitionSpy(page())
            do { _ = try await service(discovery, source).review(foodTerms: terms, key: credential); XCTFail() } catch { }
            let queries = await discovery.queries; let urls = await source.urls
            XCTAssertTrue(queries.isEmpty); XCTAssertTrue(urls.isEmpty)
        }
    }

    func testSourceEnvelopeCannotChangeSelectedURLHashOrAdmittedChain() async throws {
        let other = URL(string: "https://other.example.com/food")!
        let cases = [page(requested: other), page(hash: String(repeating: "0", count: 64)),
            page(final: other, hops: [.init(url: sourceURL, status: 302), .init(url: other, status: 200)]),
            page(hops: []), page(hops: [.init(url: sourceURL, status: 200), .init(url: sourceURL, status: 200)]),
            page(hops: [.init(url: sourceURL, status: 404)]),
            page(body: Data(repeating: 120, count: 2_000_001))]
        for captured in cases {
            do { _ = try await service(ReviewDiscoverySpy(result([sourceURL])), ReviewAcquisitionSpy(captured))
                .review(foodTerms: "milk", key: key); XCTFail() } catch { }
        }
        let resolverPage = page(requested: resolverURL, final: resolverURL,
            hops: [.init(url: resolverURL, status: 200)])
        do { _ = try await service(ReviewDiscoverySpy(result([resolverURL])), ReviewAcquisitionSpy(resolverPage))
            .review(foodTerms: "milk", key: key); XCTFail() } catch { }
    }

    func testCancellationIgnoringDiscoveryCannotStartSourceOrPublish() async throws {
        let discovery = ReviewDiscoverySpy(result([sourceURL]), suspended: true)
        let source = ReviewAcquisitionSpy(page()); let client = try service(discovery, source)
        let work = Task { [key] in try await client.review(foodTerms: "milk", key: key) }
        await discovery.waitUntilPending(); work.cancel(); await discovery.release()
        do { _ = try await work.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let urls = await source.urls; XCTAssertTrue(urls.isEmpty)
    }

    func testDeadlineAndConcurrentSubmissionCannotAddRequests() async throws {
        let discovery = ReviewDiscoverySpy(result([sourceURL]), suspended: true)
        let source = ReviewAcquisitionSpy(page()); let client = try service(discovery, source, timeout: .milliseconds(30))
        let work = Task { [key] in try await client.review(foodTerms: "milk", key: key) }
        await discovery.waitUntilPending()
        do { _ = try await client.review(foodTerms: "milk", key: key); XCTFail() }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .quotaExceeded) }
        try await Task.sleep(for: .milliseconds(70)); await discovery.release()
        do { _ = try await work.value; XCTFail() }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .timedOut) }
        let urls = await source.urls; let queries = await discovery.queries
        XCTAssertTrue(urls.isEmpty); XCTAssertEqual(queries.count, 1)
    }

    func testCancellationAndWholeDeadlineCannotPublishDiscoveryAfterSourceFailure() async throws {
        for expire in [false, true] {
            let discovery = ReviewDiscoverySpy(result([sourceURL]))
            let source = ReviewAcquisitionSpy(page(), error: .unavailable, held: true)
            let client = try service(discovery, source, timeout: expire ? .milliseconds(20) : .seconds(50))
            let work = Task { [key] in try await client.review(foodTerms: "milk", key: key) }
            await source.waitUntilPending()
            if expire { try await Task.sleep(for: .milliseconds(60)) } else { work.cancel() }
            await source.release()
            do { _ = try await work.value; XCTFail() }
            catch { XCTAssertFalse(error is FoodGroundedSourcePartialFailure) }
            let urls = await source.urls; XCTAssertEqual(urls, [sourceURL])
        }
    }

    func testSourceWithoutSupportedTableDoesNotGetModelNutrition() async throws {
        let source = ReviewAcquisitionSpy(page(body: Data("<p>No table. Generated claims cannot fill this.</p>".utf8)))
        do { _ = try await service(ReviewDiscoverySpy(result([sourceURL])), source).review(foodTerms: "milk", key: key); XCTFail() }
        catch let partial as FoodGroundedSourcePartialFailure {
            XCTAssertEqual(partial.discovery, result([sourceURL])); XCTAssertEqual(partial.reason, .invalidContent)
        }
        let urls = await source.urls; XCTAssertEqual(urls.count, 1)
    }
}

private actor ReviewDiscoverySpy: FoodWebDiscovering {
    let response: FoodWebDiscoveryResult; let error: FoodWebDiscoveryError?; let suspended: Bool
    var queries: [String] = []; var validations = 0
    private var pending: CheckedContinuation<Void, Never>?
    init(_ response: FoodWebDiscoveryResult, error: FoodWebDiscoveryError? = nil, suspended: Bool = false) {
        self.response = response; self.error = error; self.suspended = suspended
    }
    func validate(key: String) { validations += 1 }
    func discover(foodTerms: String, key: String) async throws -> FoodWebDiscoveryResult {
        queries.append(foodTerms)
        if suspended { await withCheckedContinuation { pending = $0 } }
        if let error { throw error }
        return response
    }
    func waitUntilPending() async { while pending == nil { await Task.yield() } }
    func release() { pending?.resume(); pending = nil }
}

private actor ReviewAcquisitionSpy: FoodSourcePageAcquiring {
    let page: AcquiredFoodSourcePage; let error: FoodSourceAcquisitionError?
    var urls: [URL] = []
    let held: Bool
    private var pending: CheckedContinuation<Void, Never>?
    init(_ page: AcquiredFoodSourcePage, error: FoodSourceAcquisitionError? = nil, held: Bool = false) {
        self.page = page; self.error = error; self.held = held
    }
    func acquire(_ url: URL) async throws -> AcquiredFoodSourcePage {
        urls.append(url)
        if held { await withCheckedContinuation { pending = $0 } }
        if let error { throw error }; return page
    }
    func waitUntilPending() async { while pending == nil { await Task.yield() } }
    func release() { pending?.resume(); pending = nil }

}
