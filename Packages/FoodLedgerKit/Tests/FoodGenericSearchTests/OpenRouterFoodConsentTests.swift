import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodGenericSearch
import FoodLedgerTestSupport
import XCTest

/// docs/openrouter-single-consent-v1-amendment.md O1.2 and O1.6 test 1 for the web lookup adapter:
/// with the gate refusing, no request reaches the transport, every call returns `.notPermitted`,
/// and each site names its use. Synthetic data only.
final class OpenRouterFoodConsentTests: XCTestCase {
    private let key = "synthetic-test-key-never-real-12345"

    private final class Sent: @unchecked Sendable { var count = 0 }

    func testEveryAdapterCallSendsNothingWhileRefused() async throws {
        let document = try GenericFoodDocumentProjector.project(Data("<h1>Plain yoghurt</h1><p>Per 100g energy 61kcal</p>".utf8),
            url: URL(string: "https://example.com/yoghurt")!, mediaType: "text/html", retrievedAt: Date(timeIntervalSince1970: 0),
            origin: "synthetic_fixture")
        let leads = [FoodWebLead(title: "Yoghurt", url: URL(string: "https://example.com/yoghurt")!)]
        let calls: [(String, OpenRouterUse, (OpenRouterFoodProvider) async throws -> Void)] = [
            ("validate", .keyValidation, { try await $0.validate(key: self.key) }),
            ("discover", .webLookup, { _ = try await $0.discover(foodTerms: "yoghurt", key: self.key) }),
            ("chooseSource", .webLookup, { _ = try await $0.chooseSource(foodTerms: "yoghurt", leads: leads, key: self.key) }),
            ("extract", .webLookup, { _ = try await $0.extract(foodTerms: "yoghurt", documents: [document], key: self.key) }),
        ]
        for retry in [OpenRouterFoodRetry.disabled, OpenRouterFoodRetry(enabled: true, now: { Date() }, sleep: { _ in }, jitter: { 0 })] {
            for (name, use, call) in calls {
                let sent = Sent()
                let egress = RecordingOpenRouterEgress(permits: false)
                let provider = OpenRouterFoodProvider(egress: egress, retry: retry) { _ in sent.count += 1; return .init(status: 500, data: Data()) }
                do { try await call(provider); XCTFail("Expected a refusal: \(name)") }
                catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .notPermitted, name) }
                XCTAssertEqual(sent.count, 0, name)
                XCTAssertEqual(egress.uses, [use], name)
            }
        }
    }

    func testTheSelectionRoutesSendNothingWhileRefused() async throws {
        for route in [OpenRouterFoodProvider.SelectionRoute.jev, .applicability] {
            let sent = Sent()
            let egress = RecordingOpenRouterEgress(permits: false)
            let provider = OpenRouterFoodProvider(egress: egress, selectionRoute: route) { _ in sent.count += 1; return .init(status: 500, data: Data()) }
            let (document, validation) = try OpenRouterWebLookupRequestGoldenTests.milkValidation()
            do { _ = try await provider.select(foodTerms: "Milk per 100ml", documents: [document], validation: validation, key: key); XCTFail() }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .notPermitted) }
            XCTAssertEqual(sent.count, 0)
            XCTAssertEqual(egress.uses, [.webLookup])
        }
    }
}
