import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodGenericSearch
import XCTest

@MainActor
final class OpenRouterFoodProviderTests: XCTestCase {
    private let key = "synthetic-test-key-never-real-12345"
    private let empty = #"{"version":"openrouter-food-extraction-wire-v3","candidates":[],"preferred_id":"none"}"#

    func testEveryExtractorRouteUsesTheSameSchemaAndClosedResponseContract() throws {
        var schemas: [Data] = []
        for route in OpenRouterFoodExtractionRoute.allCases {
            let body = try StrictFoodProposalJSON.object(OpenRouterFoodProvider.extractionBody(
                foodTerms: "plain yoghurt", documents: [document()], route: route))
            XCTAssertEqual(body["model"] as? String, route.model)
            XCTAssertEqual(body[route.tokenParameter] as? Int, 4096)
            XCTAssertEqual((body["reasoning"] as? NSDictionary), route.reasoning as NSDictionary?)
            let routing = try XCTUnwrap(body["provider"] as? [String: Any])
            XCTAssertEqual(routing["only"] as? [String], [route.endpoint])
            XCTAssertEqual(routing["allow_fallbacks"] as? Bool, false)
            XCTAssertEqual(routing["require_parameters"] as? Bool, true)
            XCTAssertEqual(routing["data_collection"] as? String, "deny")
            XCTAssertEqual(routing["zdr"] as? Bool, true)
            XCTAssertNil(body["plugins"])
            schemas.append(try JSONSerialization.data(withJSONObject: XCTUnwrap(body["response_format"]), options: .sortedKeys))
            let valid = try reply(content: empty, provider: route.responseProvider, model: route.model)
            XCTAssertEqual(try OpenRouterFoodProvider.decodeExtraction(valid, documents: [document()], route: route).preferredId, "none")
            for invalid in [try reply(content: empty, finish: "length", provider: route.responseProvider, model: route.model),
                            try reply(content: empty, provider: "unapproved", model: route.model),
                            try reply(content: empty, provider: route.responseProvider, model: "different/model")] {
                XCTAssertThrowsError(try OpenRouterFoodProvider.decodeExtraction(invalid, documents: [document()], route: route))
            }
        }
        XCTAssertTrue(schemas.allSatisfy { $0 == schemas.first })
    }

    func testDiscoveryDoesNotInferTaiwanFromGenericDishNames() {
        XCTAssertEqual(OpenRouterFoodProvider.discoverySearchTerms("scallion pancake"),
            "scallion pancake nutrition facts calories protein serving size")
        XCTAssertEqual(OpenRouterFoodProvider.discoverySearchTerms("UK whole milk"),
            "UK whole milk nutrition facts calories protein serving size")
    }

    func testDiscoveryAddsNutritionIntentWithoutReplacingFoodOrMarket() async throws {
        let payload = try reply(content: "No sources")
        let provider = OpenRouterFoodProvider { request in
            let body = try StrictFoodProposalJSON.object(XCTUnwrap(request.httpBody))
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.last?["content"] as? String,
                "Fat Daddy fried chicken [market: Taiwan] nutrition facts calories protein serving size 營養標示 熱量 每份")
            return .init(status: 200, data: payload)
        }
        _ = try await provider.discover(foodTerms: "Fat Daddy fried chicken [market: Taiwan]", key: key)
    }

    func testExtractionRouteDoesNotChangeDiscoveryRoute() async throws {
        let payload = try reply(content: "No sources")
        for route in OpenRouterFoodExtractionRoute.allCases {
            let provider = OpenRouterFoodProvider(extractionRoute: route) { request in
                let body = try StrictFoodProposalJSON.object(XCTUnwrap(request.httpBody))
                XCTAssertEqual(body["model"] as? String, OpenRouterFoodProvider.extractionModel)
                XCTAssertEqual((body["provider"] as? [String: Any])?["only"] as? [String], ["azure"])
                return .init(status: 200, data: payload)
            }
            _ = try await provider.discover(foodTerms: "yoghurt", key: key)
        }
    }

    func testRequestUsesPinnedExtractorWithoutSearchOrCredentialsInBody() throws {
        let body = try OpenRouterFoodProvider.extractionBody(foodTerms: "plain yoghurt", documents: [document()])
        let object = try StrictFoodProposalJSON.object(body)
        XCTAssertEqual(object["model"] as? String, "openai/gpt-6-luna")
        XCTAssertNil(object["plugins"])
        let provider = try XCTUnwrap(object["provider"] as? [String: Any])
        XCTAssertEqual(provider["only"] as? [String], ["azure"])
        XCTAssertEqual(provider["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(provider["zdr"] as? Bool, true)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(key))
        let format = try XCTUnwrap(object["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
    }

    func testStrictEmptyResponseIsValidButTruncatedOrReroutedResponseIsNot() throws {
        XCTAssertEqual(try OpenRouterFoodProvider.decodeExtraction(reply(content: empty), documents: [document()]).preferredId, "none")
        XCTAssertThrowsError(try OpenRouterFoodProvider.decodeExtraction(reply(content: empty, finish: "length"), documents: [document()]))
        XCTAssertThrowsError(try OpenRouterFoodProvider.decodeExtraction(reply(content: empty, provider: "OpenAI"), documents: [document()]))
        XCTAssertThrowsError(try OpenRouterFoodProvider.decodeExtraction(reply(content: empty, model: "other/model"), documents: [document()]))
    }

    func testFixedNutrientSlotsTranslateToStableDomainSchemaAndRejectExtraOrMissingKeys() throws {
        let unknown: [String: Any] = ["state": "unknown", "value": NSNull(), "unit": NSNull(),
                                      "evidence": [], "unknown_reason": "not_observed"]
        let fields = Dictionary(uniqueKeysWithValues: FoodProposalNutrientKey.allCases.map { ($0.rawValue, unknown) })
        let candidate: [String: Any] = ["id": "c1", "document_id": try document().id, "name": "Yoghurt", "brand": NSNull(),
            "preparation": NSNull(), "identity_evidence": [], "panel_evidence": [],
            "basis": ["amount": NSNull(), "unit": NSNull(), "label": NSNull(), "evidence": []],
            "nutrients": fields, "limitations": []]
        func wire(_ nutrients: [String: [String: Any]]) throws -> Data {
            var copy = candidate; copy["nutrients"] = nutrients
            let payload: [String: Any] = ["version": OpenRouterFoodProvider.extractionWireVersion,
                                         "candidates": [copy], "preferred_id": "none"]
            return try reply(content: String(decoding: JSONSerialization.data(withJSONObject: payload), as: UTF8.self))
        }
        let decoded = try OpenRouterFoodProvider.decodeExtraction(wire(fields), documents: [document()])
        XCTAssertEqual(decoded.version, FoodProposalExtraction.schemaVersion)
        XCTAssertEqual(decoded.candidates[0].nutrients.map(\.key), FoodProposalNutrientKey.allCases)
        var missing = fields; missing.removeValue(forKey: "protein")
        XCTAssertThrowsError(try OpenRouterFoodProvider.decodeExtraction(wire(missing), documents: [document()]))
        var extra = fields; extra["extra_protein"] = unknown
        XCTAssertThrowsError(try OpenRouterFoodProvider.decodeExtraction(wire(extra), documents: [document()]))
        var injected = fields; injected["protein"]?["key"] = "fat"
        XCTAssertThrowsError(try OpenRouterFoodProvider.decodeExtraction(wire(injected), documents: [document()]))
    }

    func testDuplicateEscapedKeysAndTrailingJSONFail() {
        for raw in [#"{"a":1,"a":2}"#, #"{"a":1,"\u0061":2}"#, #"{"x":[{"a":1,"a":2}]}"#, #"{} {}"#] {
            XCTAssertThrowsError(try StrictFoodProposalJSON.object(Data(raw.utf8)), raw)
        }
    }

    func testEveryRouteAttachesCapturedTextAndCannotRepairWrongValuesOrReferences() throws {
        let source = try document()
        let unknown: [String: Any] = ["state": "unknown", "value": NSNull(), "unit": NSNull(), "evidence": [], "unknown_reason": "not_observed"]
        var fields = Dictionary(uniqueKeysWithValues: FoodProposalNutrientKey.allCases.map { ($0.rawValue, unknown) })
        fields["energy"] = ["state": "declared", "value": "61", "unit": "kcal", "evidence": ["e2"], "unknown_reason": NSNull()]
        let candidate: [String: Any] = ["id": "c1", "document_id": source.id, "name": "Plain yoghurt", "brand": NSNull(),
            "preparation": NSNull(), "identity_evidence": ["e1"], "panel_evidence": ["e1", "e2"],
            "basis": ["amount": "100", "unit": "g", "label": "Per 100g", "evidence": ["e2"]],
            "nutrients": fields, "limitations": []]
        func wire(_ candidate: [String: Any], route: OpenRouterFoodExtractionRoute) throws -> Data {
            let payload: [String: Any] = ["version": OpenRouterFoodProvider.extractionWireVersion, "candidates": [candidate], "preferred_id": "c1"]
            return try reply(content: String(decoding: JSONSerialization.data(withJSONObject: payload), as: UTF8.self),
                             provider: route.responseProvider, model: route.model)
        }
        for route in OpenRouterFoodExtractionRoute.allCases {
            let decoded = try OpenRouterFoodProvider.decodeExtraction(wire(candidate, route: route), documents: [source], route: route)
            XCTAssertEqual(decoded.candidates[0].identityEvidence[0].quote, "Plain yoghurt")
            XCTAssertEqual(decoded.candidates[0].identityEvidence[0].blockId, "b1")
            let validation = try FoodProposalBinding.validate(decoded, documents: [source])
            XCTAssertTrue(try XCTUnwrap(validation.candidates.first, "\(validation.rejected)").selectionEligible)
            for invalid: [String: Any] in [["identity_evidence": ["e999"]], ["identity_evidence": ["e1", "e1"]],
                ["document_id": "not-offered"], ["identity_evidence": [["block_id": "e1", "quote": "invented"]]]] {
                var changed = candidate; changed.merge(invalid) { _, new in new }
                XCTAssertThrowsError(try OpenRouterFoodProvider.decodeExtraction(wire(changed, route: route), documents: [source], route: route))
            }
            var wrong = candidate; var wrongFields = fields
            wrongFields["energy"]?["value"] = "62"; wrong["nutrients"] = wrongFields
            let wrongDecoded = try OpenRouterFoodProvider.decodeExtraction(wire(wrong, route: route), documents: [source], route: route)
            XCTAssertEqual(try FoodProposalBinding.validate(wrongDecoded, documents: [source]).rejected.first?.reason, .invalidNutrient)
        }
    }

    func testUnknownFieldsMissingFieldsAndWrongTypesFailBeforeDomainDecode() throws {
        let extra = #"{"version":"openrouter-food-extraction-wire-v3","candidates":[],"preferred_id":"none","save_authorised":true}"#
        let missing = #"{"version":"openrouter-food-extraction-wire-v3","candidates":[]}"#
        let wrong = #"{"version":"openrouter-food-extraction-wire-v3","candidates":{},"preferred_id":"none"}"#
        for content in [extra, missing, wrong] { XCTAssertThrowsError(try OpenRouterFoodProvider.decodeExtraction(reply(content: content), documents: [document()])) }
    }

    func testExcerptBoundaryCannotTurnASourceBoundIntoAnExactNutrient() throws {
        let text = String(repeating: "x", count: 1299) + "<61kcal " + String(repeating: " ", count: 110) + String(repeating: "tail ", count: 250)
        let source = try CapturedFoodDocument(id: "d1", url: "https://example.com/food", rawSha256: String(repeating: "a", count: 64),
            captureOrigin: "synthetic_fixture", retrievedAt: "2026-10-04T00:00:00Z", blocks: [
                .init(id: "b1", kind: "p", text: "Yoghurt Per 100g", locator: "p:1"),
                .init(id: "b2", kind: "p", text: text, locator: "p:2")])
        let catalog = try FoodProposalEvidenceCatalog(documents: [source])
        let blocks = try XCTUnwrap(catalog.requestDocuments()[0]["blocks"] as? [[String: String]])
        let clipped = try XCTUnwrap(blocks.first { $0["text"]?.hasPrefix("61kcal") == true })
        let unknown: [String: Any] = ["state": "unknown", "value": NSNull(), "unit": NSNull(), "evidence": [], "unknown_reason": "not_observed"]
        var fields = Dictionary(uniqueKeysWithValues: FoodProposalNutrientKey.allCases.map { ($0.rawValue, unknown) })
        fields["energy"] = ["state": "declared", "value": "61", "unit": "kcal", "evidence": [clipped["id"]!], "unknown_reason": NSNull()]
        let candidate: [String: Any] = ["id": "c1", "document_id": source.id, "name": "Yoghurt", "brand": NSNull(),
            "preparation": NSNull(), "identity_evidence": ["e1"], "panel_evidence": ["e1", clipped["id"]!],
            "basis": ["amount": "100", "unit": "g", "label": "Per 100g", "evidence": ["e1"]], "nutrients": fields, "limitations": []]
        let payload: [String: Any] = ["version": OpenRouterFoodProvider.extractionWireVersion, "candidates": [candidate], "preferred_id": "c1"]
        let decoded = try OpenRouterFoodProvider.decodeExtraction(reply(content: String(decoding: JSONSerialization.data(withJSONObject: payload), as: UTF8.self)), documents: [source])
        XCTAssertTrue(decoded.candidates[0].nutrients[0].evidence[0].quote.hasPrefix("61kcal"))
        XCTAssertEqual(try FoodProposalBinding.validate(decoded, documents: [source]).rejected.first?.reason, .invalidNutrient)
    }

    func test400IsRequestFailureAndDoesNotInvalidateKeyAs401Does() async throws {
        for (status, expected) in [(400, FoodWebDiscoveryError.requestRejected), (401, .credentialRejected), (402, .quotaExceeded), (403, .permissionDenied), (429, .quotaExceeded)] {
            let provider = OpenRouterFoodProvider { _ in .init(status: status, data: Data("{}".utf8)) }
            do { try await provider.validate(key: key); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, expected) }
        }
    }
    func testHTTP200UpstreamRateLimitDoesNotBecomeCredentialFailure() async {
        let provider = OpenRouterFoodProvider { _ in
            .init(status: 200, data: Data(#"{"error":{"code":429,"message":"Provider upstream details"}}"#.utf8))
        }
        do { try await provider.validate(key: key); XCTFail("Expected upstream quota classification") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .quotaExceeded) }
    }

    func testKeyValidationUsesGETAndNeverSubmitsFoodTerms() async throws {
        let provider = OpenRouterFoodProvider { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/key")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key-never-real-12345")
            return .init(status: 200, data: Data(#"{"data":{"label":"test"}}"#.utf8))
        }
        try await provider.validate(key: key)
    }

    func testEchoedKeyIsNotReturnedOrDisplayed() async throws {
        let echo = key
        let provider = OpenRouterFoodProvider { _ in .init(status: 200, data: Data(echo.utf8)) }
        do { try await provider.validate(key: key); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .invalidResponse) }
    }

    func testDiscoveryUsesNativeCitationsRatherThanModelWrittenURLs() async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["model": OpenRouterFoodProvider.extractionModel, "provider": "Azure",
            "choices": [["finish_reason": "stop", "message": ["content": "Use https://invented.example/food", "annotations": [
                ["type": "url_citation", "url_citation": ["url": "https://publisher.example/food", "title": "Food", "content": "Nutrition source"]],
                ["type": "url_citation", "url_citation": ["url": "http://insecure.example/food", "title": "Insecure"]]]]]]])
        let provider = OpenRouterFoodProvider { request in
            let body = try StrictFoodProposalJSON.object(XCTUnwrap(request.httpBody))
            let plugin = try XCTUnwrap((body["plugins"] as? [[String: Any]])?.first)
            XCTAssertEqual(plugin["engine"] as? String, "exa")
            XCTAssertEqual(plugin["max_results"] as? Int, 3)
            return .init(status: 200, data: payload)
        }
        let result = try await provider.discover(foodTerms: "rice bowl", key: key)
        XCTAssertEqual(result.leads.map(\.url.absoluteString), ["https://publisher.example/food"])
    }

    func testCredentialInQueryIsRejectedBeforeTransport() async {
        let provider = OpenRouterFoodProvider { _ in XCTFail("No transport permitted"); return .init(status: 500, data: Data()) }
        do { _ = try await provider.discover(foodTerms: key, key: key); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .invalidQuery) }
    }

    func testSelectorRejectsBooleanProbabilitiesAndConfidence() async throws {
        let validation = try FoodProposalBinding.validate(.init(version: FoodProposalExtraction.schemaVersion,
            candidates: [], preferredId: "none"), documents: [document()])
        for booleanField in ["probability", "confidence"] {
            let payload = try JSONSerialization.data(withJSONObject: ["model": OpenRouterFoodProvider.selectionModel,
                "provider": "TypeSafe", "answers": ["best_candidate": ["type": "choice", "choice": "none",
                    "probabilities": ["none": booleanField == "probability" ? true as Any : 1.0, "clarify": 0.0],
                    "confidence": booleanField == "confidence" ? true as Any : 1.0]]])
            let provider = OpenRouterFoodProvider { _ in .init(status: 200, data: payload) }
            do {
                _ = try await provider.select(foodTerms: "tofu", documents: [document()], validation: validation, key: key)
                XCTFail("JSON boolean must not become numeric confidence")
            } catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .invalidResponse) }
        }
    }

    private func reply(content: String, finish: String = "stop", provider: String = "Azure", model: String = OpenRouterFoodProvider.extractionModel) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["model": model, "provider": provider,
            "choices": [["finish_reason": finish, "message": ["content": content]]]])
    }
    private func document() throws -> CapturedFoodDocument {
        try GenericFoodDocumentProjector.project(Data("<h1>Plain yoghurt</h1><p>Per 100g energy 61kcal</p>".utf8),
            url: URL(string: "https://example.com/yoghurt")!, mediaType: "text/html", retrievedAt: Date(timeIntervalSince1970: 0), origin: "synthetic_fixture")
    }
}
