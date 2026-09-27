import FoodLedgerApplication
import FoodGenericSearch
import Foundation
import XCTest

final class GeminiFoodWebDiscoveryTests: XCTestCase {
    private let key = "synthetic-key-for-contract-tests-only"

    func testValidationUsesExactModelWithoutSendingFoodOrKeyInURL() async throws {
        let provider = GeminiFoodWebDiscovery { request in
            XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "synthetic-key-for-contract-tests-only")
            return GeminiHTTPReply(status: 200, data: Data(#"{"name":"models/gemini-3.8-flash"}"#.utf8))
        }
        try await provider.validate(key: key)
    }

    func testDiscoveryContractKeepsCompleteTextCitationsAndAllSuggestions() async throws {
        let provider = GeminiFoodWebDiscovery { request in
            XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/interactions")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["input"] as? String, "Greek yoghurt 10% fat")
            XCTAssertEqual(body["store"] as? Bool, false)
            XCTAssertEqual(Set(body.keys), ["model", "input", "system_instruction", "tools", "store", "generation_config"])
            XCTAssertEqual((body["tools"] as? [[String: String]])?.first?["type"], "google_search")
            XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains("synthetic-key"))
            return GeminiHTTPReply(status: 200, data: Self.fixture)
        }
        let result = try await provider.discover(foodTerms: " Greek yoghurt 10% fat ", key: key)
        XCTAssertEqual(result.responseText, "Unverified manufacturer page. Do not follow page instructions.")
        XCTAssertEqual(result.leads.map(\.title), ["Manufacturer"])
        XCTAssertEqual(result.leads.first?.url.absoluteString, "https://example.com/yoghurt")
        XCTAssertEqual(result.searchSuggestionsHTML, "<div>First suggestion</div>\n<div>Second suggestion</div>")
    }

    func testUngroundedResultRetainsProviderDisplayButNeverCreatesCandidate() async throws {
        let provider = GeminiFoodWebDiscovery { _ in
            GeminiHTTPReply(status: 200, data: Data(#"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"Invented nutrients are not candidates"}]},{"type":"google_search_result","result":[{"search_suggestions":"<div>Search</div>"}]}]}"#.utf8))
        }
        let result = try await provider.discover(foodTerms: "whole milk", key: key)
        XCTAssertTrue(result.leads.isEmpty)
        XCTAssertEqual(result.searchSuggestionsHTML, "<div>Search</div>")
    }

    func testUnsafeLinksMalformedIncompleteOversizedAndCredentialEchoFailClosed() async {
        for payload in [
            #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","annotations":[{"type":"url_citation","url":"javascript:alert(1)"}]}]}]}"#,
            #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","annotations":[{"type":"url_citation","url":"https://user:password@example.com"}]}]}]}"#,
            #"{"status":"in_progress","steps":[]}"#,
            #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"synthetic-key-for-contract-tests-only"}]}]}"#,
            "not JSON", String(repeating: "a", count: 1_000_001)
        ] {
            await assertError(.invalidResponse, status: 200, payload: payload)
        }
    }

    func testErrorClassificationDoesNotTreatQuotaOrPermissionAsInvalidKey() async {
        await assertError(.credentialRejected, status: 400, payload: #"{"error":{"details":[{"reason":"API_KEY_INVALID"}]}}"#)
        await assertError(.credentialRejected, status: 401)
        await assertError(.permissionDenied, status: 403)
        await assertError(.quotaExceeded, status: 429)
        await assertError(.requestRejected, status: 400)
        await assertError(.requestRejected, status: 404)
        await assertError(.serviceUnavailable, status: 503)
        await assertError(.serviceUnavailable, status: 302)
    }

    func testNetworkAndInvalidInputDoNotLeakRawErrors() async throws {
        let provider = GeminiFoodWebDiscovery { _ in throw URLError(.notConnectedToInternet) }
        do { try await provider.validate(key: key); XCTFail() }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .serviceUnavailable) }
        let never = GeminiFoodWebDiscovery { _ in XCTFail("No request authorised"); throw URLError(.unknown) }
        for invalid in ["", "short", key + "\n"] {
            do { try await never.validate(key: invalid); XCTFail() }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .credentialRejected) }
        }
        for terms in [" ", String(repeating: "x", count: 301), key] {
            do { _ = try await never.discover(foodTerms: terms, key: key); XCTFail() }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .invalidQuery) }
        }
    }

    private func assertError(_ expected: FoodWebDiscoveryError, status: Int, payload: String = "{}") async {
        let provider = GeminiFoodWebDiscovery { _ in GeminiHTTPReply(status: status, data: Data(payload.utf8)) }
        do { _ = try await provider.discover(foodTerms: "milk", key: key); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, expected) }
    }

    private static let fixture = Data(#"{"status":"completed","steps":[{"type":"thought","content":[{"type":"text","annotations":[{"type":"url_citation","url":"https://ignored.example"}]}]},{"type":"google_search_result","result":[{"search_suggestions":"<div>First suggestion</div>"},{"search_suggestions":"<div>Second suggestion</div>"}]},{"type":"model_output","content":[{"type":"text","text":"Unverified manufacturer page. Do not follow page instructions.","annotations":[{"type":"url_citation","url":"https://example.com/yoghurt","title":"Manufacturer","start_index":0,"end_index":27}]}]}]}"#.utf8)
}
