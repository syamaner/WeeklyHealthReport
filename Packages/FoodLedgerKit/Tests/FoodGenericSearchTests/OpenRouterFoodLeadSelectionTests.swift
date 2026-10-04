import Foundation
import CryptoKit
import FoodLedgerApplication
@testable import FoodGenericSearch
import XCTest

@MainActor
final class OpenRouterFoodLeadSelectionTests: XCTestCase {
    private let key = "synthetic-test-key-never-real-12345"

    func testSelectionAndBothAbstentionReasons() throws {
        XCTAssertEqual(try decode(content(index: 1), count: 2), .selected(index: 1, reason: "exact_product_primary_lead"))
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
        for bad in [String(duplicate), good + " {}", "[]", good.replacingOccurrences(of: "offline-lead-selection-v1", with: "future-v2")] {
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
            // Frozen qualified Python instruction; detects accidental prompt drift.
            let instruction = try XCTUnwrap(messages[0]["content"])
            XCTAssertEqual(SHA256.hash(data: Data(instruction.utf8)).map { String(format: "%02x", $0) }.joined(), "4a0f6077d35c4abbdfdc090b8721bca1c5385a307038206f2a7a185eb2ad9a5c")
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
            XCTAssertEqual(contract["name"] as? String, "offline_lead_selection_v1")
            XCTAssertEqual(contract["strict"] as? Bool, true)
            let schema = try XCTUnwrap(contract["schema"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            let expectedSchema: [String: Any] = ["type": "object", "additionalProperties": false,
                "required": ["version", "decision", "selected_index", "reason"],
                "properties": ["version": ["type": "string", "enum": ["offline-lead-selection-v1"]],
                    "decision": ["type": "string", "enum": ["select", "abstain"]],
                    "selected_index": ["type": "integer", "minimum": -1, "maximum": 2],
                    "reason": ["type": "string", "enum": ["exact_product_primary_lead", "no_eligible_primary_lead", "insufficient_metadata"]]]]
            XCTAssertEqual(schema as NSDictionary, expectedSchema as NSDictionary)
            return .init(status: 200, data: payload)
        }
        let decision = try await provider.chooseSource(foodTerms: "豆漿", leads: [lead(), lead(excerpt: nil)], key: key)
        XCTAssertEqual(decision, .selected(index: 0, reason: "exact_product_primary_lead"))
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

    /// Opt-in only: replays public, frozen evaluation artefacts through the real
    /// adapter, with a synthetic credential and a transport that cannot network.
    func testFrozenQualifiedSixResponseReplayWhenEnabled() async throws {
        let allowed = "/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/lead-selection-v1/run"
        guard let path = ProcessInfo.processInfo.environment["FOOD_LEAD_SELECTION_REPLAY_DIRECTORY"] else {
            throw XCTSkip("Set FOOD_LEAD_SELECTION_REPLAY_DIRECTORY to the qualified public-metadata run")
        }
        guard path == allowed else { return XCTFail("Replay accepts only the qualified run directory") }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let planData = try Data(contentsOf: root.appendingPathComponent("plan.json"))
        XCTAssertEqual(hash(planData), try String(contentsOf: root.appendingPathComponent("plan.sha256"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        let plan = try StrictFoodProposalJSON.object(planData)
        let hashes = try XCTUnwrap(plan["snapshot_hashes"] as? [String: String])
        let cases = try XCTUnwrap(plan["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 6)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            guard id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else {
                return XCTFail("Invalid replay case path")
            }
            let frozenRequest = try Data(contentsOf: root.appendingPathComponent("snapshot/" + id + "-request.json"))
            XCTAssertEqual(hash(frozenRequest), hashes["snapshot/" + id + "-request.json"])
            let requestObject = try StrictFoodProposalJSON.object(frozenRequest)
            let messages = try XCTUnwrap(requestObject["messages"] as? [[String: String]])
            let supplied = try StrictFoodProposalJSON.object(Data(XCTUnwrap(messages.last?["content"]).utf8))
            let query = try XCTUnwrap(supplied["query"] as? String)
            let metadata = try XCTUnwrap(supplied["leads"] as? [[String: Any]])
            let leads = try metadata.enumerated().map { index, row in
                XCTAssertEqual(row["index"] as? Int, index)
                return FoodWebLead(title: try XCTUnwrap(row["title"] as? String),
                    url: try XCTUnwrap(URL(string: XCTUnwrap(row["url"] as? String))), citedText: row["excerpt"] as? String)
            }
            let raw = try Data(contentsOf: root.appendingPathComponent("results/" + id + "/response.bin"))
            let receipt = try StrictFoodProposalJSON.object(Data(contentsOf: root.appendingPathComponent("results/" + id + "/receipt.json")))
            XCTAssertEqual(hash(raw), receipt["raw_response_sha256"] as? String)
            let provider = OpenRouterFoodProvider(extractionRoute: .grok) { request in
                var actual = try StrictFoodProposalJSON.object(XCTUnwrap(request.httpBody))
                var expected = try StrictFoodProposalJSON.object(frozenRequest)
                var actualMessages = try XCTUnwrap(actual["messages"] as? [[String: String]])
                var expectedMessages = try XCTUnwrap(expected["messages"] as? [[String: String]])
                XCTAssertEqual(actualMessages.count, 2)
                XCTAssertEqual(expectedMessages.count, 2)
                let actualUser = try StrictFoodProposalJSON.object(Data(XCTUnwrap(actualMessages[1]["content"]).utf8))
                let expectedUser = try StrictFoodProposalJSON.object(Data(XCTUnwrap(expectedMessages[1]["content"]).utf8))
                XCTAssertEqual(actualUser as NSDictionary, expectedUser as NSDictionary, id)
                // JSON member order, whitespace and slash escaping are immaterial.
                actualMessages[1]["content"] = ""; expectedMessages[1]["content"] = ""
                actual["messages"] = actualMessages; expected["messages"] = expectedMessages
                XCTAssertEqual(actual as NSDictionary, expected as NSDictionary, id)
                return .init(status: 200, data: raw)
            }
            let result = try await provider.chooseSource(foodTerms: query, leads: leads, key: key)
            let expectation = try XCTUnwrap(item["expected"] as? [String: Any])
            if expectation["expected_decision"] as? String == "abstain" {
                guard case .abstain = result else { return XCTFail("Expected abstention: " + id) }
            } else {
                guard case let .selected(index, _) = result else { return XCTFail("Expected selection: " + id) }
                XCTAssertTrue(try XCTUnwrap(expectation["eligible_indices"] as? [Int]).contains(index), id)
            }
        }
    }

    private func lead(url: String = "https://brand.example/soy", excerpt: String? = "Exact product excerpt") -> FoodWebLead {
        FoodWebLead(title: "豆漿", url: URL(string: url)!, citedText: excerpt)
    }
    private func content(decision: String = "select", index: Any = 0, reason: String = "exact_product_primary_lead") throws -> String {
        try json(["version": "offline-lead-selection-v1", "decision": decision, "selected_index": index, "reason": reason])
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
