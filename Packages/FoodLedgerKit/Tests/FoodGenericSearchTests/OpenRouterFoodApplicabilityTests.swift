import Foundation
import FoodLedgerDomain
import FoodLedgerApplication
@testable import FoodGenericSearch
import XCTest

@MainActor
final class OpenRouterFoodApplicabilityTests: XCTestCase {
    func testPartialPanelCanPassWithoutInventingConfidence() async throws {
        let (document, validation) = try fixture()
        let payload = try reply()
        let provider = OpenRouterFoodProvider(extractionRoute: .grok, selectionRoute: .applicability) { request in
            let body = try StrictFoodProposalJSON.object(XCTUnwrap(request.httpBody))
            XCTAssertEqual(body["model"] as? String, "openai/gpt-6-luna")
            XCTAssertNil(body["plugins"])
            XCTAssertEqual((body["provider"] as? [String: Any])?["allow_fallbacks"] as? Bool, false)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertTrue(messages[1]["content"]?.contains("Milk") == true)
            XCTAssertFalse(messages[1]["content"]?.contains("synthetic-provider-key") == true)
            return .init(status: 200, data: payload)
        }
        let result = try await provider.select(foodTerms: "Milk per 100ml", documents: [document], validation: validation,
            key: "synthetic-provider-key-123456789")
        XCTAssertEqual(result.choice, "c1"); XCTAssertTrue(result.probabilities.isEmpty); XCTAssertNil(result.rawConfidence)
    }

    func testAnyContradictoryOrUncertainFacetOverridesPositiveChoice() throws {
        let (_, validation) = try fixture()
        for facet in ["identity", "exclusions", "basis", "nutrient_meaning"] {
            for state in ["uncertain", "mismatch"] {
                XCTAssertEqual(try OpenRouterFoodProvider.decodeApplicability(reply(overrides: [facet: state]), validation: validation).choice, "clarify")
            }
        }
        for choice in ["none", "clarify"] {
            XCTAssertEqual(try OpenRouterFoodProvider.decodeApplicability(reply(overrides: ["choice": choice]), validation: validation).choice, choice)
        }
    }

    func testMalformedAndUnboundChoicesFailClosed() throws {
        let (_, validation) = try fixture()
        for change: [String: Any] in [["choice": "c2"], ["version": "v2"], ["identity": true], ["basis": "probably"], ["extra": "bad"]] {
            XCTAssertThrowsError(try OpenRouterFoodProvider.decodeApplicability(reply(overrides: change), validation: validation))
        }
        for field in ["identity", "exclusions", "basis", "nutrient_meaning", "choice", "version"] {
            XCTAssertThrowsError(try OpenRouterFoodProvider.decodeApplicability(reply(omitting: field), validation: validation))
        }
        for extra: [String: Any] in [["provider": "wrong"], ["model": "other"], ["choices": []]] {
            XCTAssertThrowsError(try OpenRouterFoodProvider.decodeApplicability(reply(envelope: extra), validation: validation))
        }
    }

    private func reply(overrides: [String: Any] = [:], omitting: String? = nil, envelope: [String: Any] = [:]) throws -> Data {
        var content: [String: Any] = ["version": OpenRouterFoodProvider.applicabilityVersion, "choice": "c1",
            "identity": "supported", "exclusions": "supported", "basis": "supported", "nutrient_meaning": "supported"]
        content.merge(overrides) { _, new in new }; if let omitting { content.removeValue(forKey: omitting) }
        var raw: [String: Any] = ["model": OpenRouterFoodProvider.extractionModel, "provider": "Azure",
            "choices": [["finish_reason": "stop", "message": ["content": String(decoding: try JSONSerialization.data(withJSONObject: content), as: UTF8.self)]]]]
        raw.merge(envelope) { _, new in new }; return try JSONSerialization.data(withJSONObject: raw)
    }

    private func fixture() throws -> (CapturedFoodDocument, FoodProposalValidation) {
        let text = "Milk Per 100ml Protein 3g"
        let document = try CapturedFoodDocument(id: "d1", url: "https://example.com/milk", rawSha256: String(repeating: "a", count: 64),
            captureOrigin: "synthetic", retrievedAt: "2026-10-04T00:00:00Z", blocks: [.init(id: "b1", kind: "p", text: text, locator: "p1")])
        let refs: [[String: Any]] = [["block_id": "b1", "quote": text]]
        let nutrients: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            ["key": key.rawValue, "state": key == .protein ? "declared" : "unknown",
             "value": key == .protein ? "3" as Any : NSNull(), "unit": key == .protein ? "g" as Any : NSNull(),
             "evidence": key == .protein ? refs : [], "unknown_reason": key == .protein ? NSNull() : "not_observed" as Any]
        }
        let candidate: [String: Any] = ["id": "c1", "document_id": "d1", "name": "Milk", "brand": NSNull(), "preparation": NSNull(),
            "identity_evidence": refs, "panel_evidence": refs, "basis": ["amount": "100", "unit": "ml", "label": "Per 100ml", "evidence": refs],
            "nutrients": nutrients, "limitations": []]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let extraction = try decoder.decode(FoodProposalExtraction.self, from: JSONSerialization.data(withJSONObject:
            ["version": FoodProposalExtraction.schemaVersion, "candidates": [candidate], "preferred_id": "c1"]))
        return (document, try FoodProposalBinding.validate(extraction, documents: [document]))
    }
}
