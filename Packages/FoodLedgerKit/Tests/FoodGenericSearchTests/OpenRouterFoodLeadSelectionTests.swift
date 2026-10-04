import Foundation
import CryptoKit
import FoodLedgerApplication
@testable import FoodGenericSearch
import XCTest

@MainActor
final class OpenRouterFoodLeadSelectionTests: XCTestCase {
    private let key = "synthetic-test-key-never-real-12345"

    func testSelectionAndBothAbstentionReasons() throws {
        XCTAssertEqual(try decode(content(reason: "representative_food_lead")), .selected(index: 0, purpose: .representativeEstimate, reason: "representative_food_lead"))
        XCTAssertThrowsError(try decode(content().replacingOccurrences(of: "offline-lead-selection-v2", with: "offline-lead-selection-v1")))
        XCTAssertEqual(try decode(content(index: 1), count: 2), .selected(index: 1, purpose: .primaryProduct, reason: "exact_product_primary_lead"))
        for reason in ["no_eligible_primary_lead", "insufficient_metadata"] {
            XCTAssertEqual(try decode(content(decision: "abstain", index: -1, reason: reason)), .abstain(reason: reason))
        }
    }

    func testRejectsWrongModelProviderTruncationRefusalAndToolCalls() throws {
        let value = try content()
        for raw in [try reply(value, model: "other/model"), try reply(value, provider: "OpenAI"),
                    try reply(value, finish: "length"), try reply(value, extra: ["refusal": "no"]),
                    try reply(value, extra: ["tool_calls": []])] {
            XCTAssertThrowsError(try OpenRouterFoodProvider.decodeLeadSelection(raw, leadCount: 1))
        }
    }

    func testRejectsInvalidIndicesAndDecisionReasonCombinations() throws {
        for index: Any in [-2, 3, 0.5, true, "0", NSNull()] {
            XCTAssertThrowsError(try decode(content(index: index)))
        }
        for token in ["0.0", "0e0", "-0.0"] {
            let raw = try content().replacingOccurrences(of: "\"selected_index\":0", with: "\"selected_index\":" + token)
            XCTAssertThrowsError(try decode(raw))
        }
        XCTAssertThrowsError(try decode(content(index: 1), count: 1))
        XCTAssertThrowsError(try decode(content(index: -1)))
        XCTAssertThrowsError(try decode(content(decision: "abstain", index: 0, reason: "insufficient_metadata")))
        XCTAssertThrowsError(try decode(content(decision: "abstain", index: -1)))
        XCTAssertThrowsError(try decode(content(reason: "insufficient_metadata")))
        XCTAssertThrowsError(try decode(content(decision: "invented")))
        XCTAssertThrowsError(try decode(content(reason: "invented")))
        for count in [0, 4] { XCTAssertThrowsError(try decode(content(), count: count)) }
    }

    func testRejectsDuplicateEscapedKeysUnknownFieldsMissingFieldsAndSpoofedVersion() throws {
        let good = try content()
        let duplicate = good.dropLast() + #", "\u0073elected_index": 0}"#
        for bad in [String(duplicate), good + " {}", "[]", good.replacingOccurrences(of: "offline-lead-selection-v2", with: "future-v2")] {
            XCTAssertThrowsError(try decode(bad))
        }
        var object = try StrictFoodProposalJSON.object(Data(good.utf8))
        object["url"] = "https://invented.example/product"
        XCTAssertThrowsError(try decode(json(object)))
        object.removeValue(forKey: "url")
        for field in ["version", "decision", "selected_index", "reason"] {
            var missing = object; missing.removeValue(forKey: field)
            XCTAssertThrowsError(try decode(json(missing)))
        }
        let raw = String(decoding: try reply(good), as: UTF8.self)
        let duplicateEnvelope = raw.dropLast() + #", "provider": "Azure"}"#
        XCTAssertThrowsError(try OpenRouterFoodProvider.decodeLeadSelection(Data(duplicateEnvelope.utf8), leadCount: 1))
    }

    func testRequestContainsOnlyOfferedMetadataAndPinnedQualifiedControls() async throws {
        let payload = try reply(content())
        let testKey = key
        let provider = OpenRouterFoodProvider(extractionRoute: .grok) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + testKey)
            let bytes = try XCTUnwrap(request.httpBody)
            XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(testKey))
            let body = try StrictFoodProposalJSON.object(bytes)
            XCTAssertEqual(Set(body.keys), ["model", "stream", "max_completion_tokens", "reasoning", "provider", "messages", "response_format"])
            XCTAssertEqual(body["model"] as? String, "openai/gpt-6-luna")
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 1800)
            XCTAssertEqual((body["reasoning"] as? [String: String]), ["effort": "none"])
            let routing = try XCTUnwrap(body["provider"] as? [String: Any])
            XCTAssertEqual(routing as NSDictionary, ["only": ["azure"], "order": ["azure"], "allow_fallbacks": false,
                "require_parameters": true, "data_collection": "deny", "zdr": true] as NSDictionary)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.count, 2)
            // Versioned v2 instruction; requires new evaluation before qualification.
            let instruction = try XCTUnwrap(messages[0]["content"])
            XCTAssertEqual(SHA256.hash(data: Data(instruction.utf8)).map { String(format: "%02x", $0) }.joined(), "3d747e049e6b9377dd964d2a97465cc1e6c76b3bcaf3508f7201f30f1bcbd190")
            let metadata = try StrictFoodProposalJSON.object(Data(XCTUnwrap(messages[1]["content"]).utf8))
            XCTAssertEqual(Set(metadata.keys), ["query", "leads"])
            XCTAssertEqual(metadata["query"] as? String, "豆漿")
            let leads = try XCTUnwrap(metadata["leads"] as? [[String: Any]])
            XCTAssertEqual(leads.count, 2)
            XCTAssertEqual(Set(leads[0].keys), ["index", "url", "title", "excerpt"])
            XCTAssertEqual(leads[0]["index"] as? Int, 0)
            XCTAssertEqual(leads[0]["url"] as? String, "https://brand.example/soy")
            XCTAssertEqual(leads[0]["title"] as? String, "豆漿")
            XCTAssertEqual(leads[0]["excerpt"] as? String, "Exact product excerpt")
            XCTAssertEqual(leads[1]["index"] as? Int, 1)
            XCTAssertTrue(leads[1]["excerpt"] is NSNull)
            let format = try XCTUnwrap(body["response_format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            let contract = try XCTUnwrap(format["json_schema"] as? [String: Any])
            XCTAssertEqual(contract["name"] as? String, "offline_lead_selection_v2")
            XCTAssertEqual(contract["strict"] as? Bool, true)
            let schema = try XCTUnwrap(contract["schema"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            let expectedSchema: [String: Any] = ["type": "object", "additionalProperties": false,
                "required": ["version", "decision", "selected_index", "reason"],
                "properties": ["version": ["type": "string", "enum": ["offline-lead-selection-v2"]],
                    "decision": ["type": "string", "enum": ["select", "abstain"]],
                    "selected_index": ["type": "integer", "minimum": -1, "maximum": 2],
                    "reason": ["type": "string", "enum": ["exact_product_primary_lead", "representative_food_lead", "no_eligible_primary_lead", "insufficient_metadata"]]]]
            XCTAssertEqual(schema as NSDictionary, expectedSchema as NSDictionary)
            return .init(status: 200, data: payload)
        }
        let decision = try await provider.chooseSource(foodTerms: "豆漿", leads: [lead(), lead(excerpt: nil)], key: key)
        XCTAssertEqual(decision, .selected(index: 0, purpose: .primaryProduct, reason: "exact_product_primary_lead"))
    }

    func testInvalidInputsAndCredentialInMetadataNeverReachTransport() async throws {
        let provider = OpenRouterFoodProvider { _ in
            XCTFail("Invalid input reached transport")
            return .init(status: 500, data: Data())
        }
        for leads in [[], Array(repeating: lead(), count: 4), [lead(url: "http://brand.example/soy")], [lead(excerpt: key)]] {
            do { _ = try await provider.chooseSource(foodTerms: "豆漿", leads: leads, key: key); XCTFail("Accepted invalid leads") }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .invalidQuery) }
        }
        for query in ["", "   ", String(repeating: "x", count: 301), key] {
            do { _ = try await provider.chooseSource(foodTerms: query, leads: [lead()], key: key); XCTFail("Accepted invalid query") }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .invalidQuery) }
        }
    }

    func testFrozenV2ResponseReplayWhenEnabled() async throws {
        let allowed = "/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-source-policy-v2-final-20261004"
        guard let path = ProcessInfo.processInfo.environment["FOOD_LEAD_V2_REPLAY_DIRECTORY"] else {
            throw XCTSkip("Set FOOD_LEAD_V2_REPLAY_DIRECTORY to replay the eight public v2 responses")
        }
        guard path == allowed else { return XCTFail("Unexpected replay directory") }
        let root = URL(fileURLWithPath: path)
        func read(_ name: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(name)) }
        func hash(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }
        let planData = try read("plan.json")
        XCTAssertEqual(hash(planData), try String(decoding: read("plan.sha256"), as: UTF8.self))
        let plan = try StrictFoodProposalJSON.object(planData)
        let cases = try XCTUnwrap(plan["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 8)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            guard id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { return XCTFail("Invalid case path") }
            let requestData = try read(id + "-request.json")
            XCTAssertEqual(hash(requestData), item["request_sha256"] as? String)
            let expectedBody = try StrictFoodProposalJSON.object(requestData)
            let expectedMessages = try XCTUnwrap(expectedBody["messages"] as? [[String: String]])
            let metadata = try StrictFoodProposalJSON.object(Data(XCTUnwrap(expectedMessages.last?["content"]).utf8))
            let query = try XCTUnwrap(metadata["query"] as? String)
            let rows = try XCTUnwrap(metadata["leads"] as? [[String: Any]])
            let leads = try rows.map { row in
                FoodWebLead(title: try XCTUnwrap(row["title"] as? String),
                    url: try XCTUnwrap(URL(string: XCTUnwrap(row["url"] as? String))), citedText: row["excerpt"] as? String)
            }
            let raw = try read(id + "-response.json")
            let provider = OpenRouterFoodProvider { request in
                let frozenBody = try StrictFoodProposalJSON.object(requestData)
                let frozenMessages = try XCTUnwrap(frozenBody["messages"] as? [[String: String]])
                let frozenMetadata = try StrictFoodProposalJSON.object(Data(XCTUnwrap(frozenMessages.last?["content"]).utf8))
                var body = try StrictFoodProposalJSON.object(XCTUnwrap(request.httpBody))
                var messages = try XCTUnwrap(body["messages"] as? [[String: String]])
                let actualMetadata = try StrictFoodProposalJSON.object(Data(XCTUnwrap(messages.last?["content"]).utf8))
                XCTAssertEqual(actualMetadata as NSDictionary, frozenMetadata as NSDictionary)
                messages[1]["content"] = frozenMessages[1]["content"]
                body["messages"] = messages
                XCTAssertEqual(body as NSDictionary, frozenBody as NSDictionary)
                return .init(status: 200, data: raw)
            }
            let decision = try await provider.chooseSource(foodTerms: query, leads: leads, key: key)
            // Replay verifies wire decoding and purpose mapping, separately from
            // frozen evaluation accuracy. A retained model miss must not be
            // turned into a passing gold outcome by changing the plan.
            let envelope = try StrictFoodProposalJSON.object(raw)
            let choices = try XCTUnwrap(envelope["choices"] as? [[String: Any]])
            let message = try XCTUnwrap(choices.first?["message"] as? [String: Any])
            let expected = try StrictFoodProposalJSON.object(Data(XCTUnwrap(message["content"] as? String).utf8))
            if expected["decision"] as? String == "select" {
                let reason = try XCTUnwrap(expected["reason"] as? String)
                XCTAssertEqual(decision, .selected(index: try XCTUnwrap(expected["selected_index"] as? Int),
                    purpose: reason == "representative_food_lead" ? .representativeEstimate : .primaryProduct, reason: reason))
            } else {
                guard case .abstain = decision else { return XCTFail("Unsafe source was selected") }
            }
        }
    }

    // Historical v1 live qualification stays in frozen artifacts. It cannot
    // qualify the versioned v2 source policy; old responses are rejected above.
    private func lead(url: String = "https://brand.example/soy", excerpt: String? = "Exact product excerpt") -> FoodWebLead {
        FoodWebLead(title: "豆漿", url: URL(string: url)!, citedText: excerpt)
    }
    private func content(decision: String = "select", index: Any = 0, reason: String = "exact_product_primary_lead") throws -> String {
        try json(["version": "offline-lead-selection-v2", "decision": decision, "selected_index": index, "reason": reason])
    }
    private func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self)
    }
    private func decode(_ value: String, count: Int = 1) throws -> FoodSourceLeadDecision {
        try OpenRouterFoodProvider.decodeLeadSelection(reply(value), leadCount: count)
    }
    private func reply(_ content: String, model: String = "openai/gpt-6-luna", provider: String = "Azure",
                       finish: String = "stop", extra: [String: Any] = [:]) throws -> Data {
        var message: [String: Any] = ["role": "assistant", "content": content]
        message.merge(extra) { _, value in value }
        return try JSONSerialization.data(withJSONObject: ["model": model, "provider": provider,
            "choices": [["finish_reason": finish, "message": message]]])
    }
}
