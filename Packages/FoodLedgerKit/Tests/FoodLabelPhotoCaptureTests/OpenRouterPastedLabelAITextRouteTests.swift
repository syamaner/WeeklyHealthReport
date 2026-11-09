@testable import FoodLabelPhotoCapture
import FoodLedgerApplication
import FoodLedgerTestSupport
import Foundation
import XCTest

/// The text route's OpenRouter adapters over a fake transport (docs/pasted-label-ai-text-v1.md 4.2,
/// 4.9, 5.2 item 1, T1 to T4, T9; contract tests 10, 21 and 28). No network.
final class OpenRouterPastedLabelAITextRouteTests: XCTestCase {
    typealias Fake = OpenRouterLabelPhotoRouteTests.FakeTransport
    typealias Keys = OpenRouterLabelPhotoRouteTests.Keys
    static let key = OpenRouterLabelPhotoRouteTests.key
    static let route = PastedLabelAITextRoute.gemini4ArgonVertexUS

    func request() throws -> OpenRouterPastedLabelAITextRequest { try OpenRouterPastedLabelAITextRequest(route: Self.route) }

    // MARK: Test 10: the request golden

    func testTheResourcesAreThePinnedBytes() throws {
        let digester = SHA256Digester()
        let instruction = try XCTUnwrap(OpenRouterLabelPhotoRequest.resource(OpenRouterPastedLabelAITextRequest.instructionResource))
        let schema = try XCTUnwrap(OpenRouterLabelPhotoRequest.resource(OpenRouterPastedLabelAITextRequest.wireSchemaResource))
        XCTAssertEqual(try digester.sha256(instruction).value, OpenRouterPastedLabelAITextRequest.instructionSHA256)
        XCTAssertEqual(try digester.sha256(schema).value, OpenRouterPastedLabelAITextRequest.wireSchemaSHA256)
        XCTAssertTrue(String(decoding: instruction, as: UTF8.self).hasPrefix("pasted-label-ai-text-instruction-v1 (prompt-v1"))
    }

    /// The exact body for a fixed text, pinned by the SHA-256 of its bytes, and its structure.
    func testTheRequestBodyIsExactlyTextOnly() throws {
        let text = "Typical values Per 100g\nFat 9.5g"
        let body = try request().body(text)
        XCTAssertEqual(SHA256Digester().sha256Hex(body), "e4243be6d49953704a6e5a71d167d0ae5ced1016b54d708f5b18c3868c2fe0bf")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["model", "messages", "response_format", "provider", "max_tokens", "reasoning", "stream", "usage"])
        XCTAssertEqual(object["model"] as? String, "google/gemini-4-argon")
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertTrue((messages[0]["content"] as? String)?.hasPrefix("pasted-label-ai-text-instruction-v1") ?? false)
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, text, "the text exactly as given, and only the text")
        XCTAssertEqual(Set(messages[1].keys), ["role", "content"])
        let provider = try XCTUnwrap(object["provider"] as? [String: Any])
        XCTAssertEqual(provider["only"] as? [String], ["google-vertex/us"])
        XCTAssertEqual(provider["order"] as? [String], ["google-vertex/us"])
        XCTAssertEqual(provider["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(provider["require_parameters"] as? Bool, true)
        XCTAssertEqual(provider["data_collection"] as? String, "deny")
        XCTAssertEqual(provider["zdr"] as? Bool, true)
        XCTAssertEqual(Set(provider.keys), ["only", "order", "allow_fallbacks", "require_parameters", "data_collection", "zdr"])
        XCTAssertEqual(object["max_tokens"] as? Int, 2_400)
        XCTAssertEqual((object["reasoning"] as? [String: Any])?["max_tokens"] as? Int, 500)
        XCTAssertEqual(object["stream"] as? Bool, false)
        let format = try XCTUnwrap(object["response_format"] as? [String: Any])
        let schema = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(schema["name"] as? String, "pasted_label_text_extraction_v1")
        XCTAssertEqual(schema["strict"] as? Bool, true)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("$comment"))
        XCTAssertNil(object["tools"])
        // No key, app name or brand anywhere in the body.
        for forbidden in ["sk-or", "Bearer", "WeeklyHealthReport", "HTTP-Referer", "X-Title"] {
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(forbidden), forbidden)
        }
        XCTAssertEqual(try request().body(text), body, "reproducible bytes")
    }

    // MARK: Revision 11: the prompt version

    func testThePromptVersionsAreTheClosedPinnedSetAndV1IsTheDefault() throws {
        typealias Request = OpenRouterPastedLabelAITextRequest
        XCTAssertEqual(Request.PromptVersion.allCases.map(\.rawValue), ["prompt-v1", "prompt-v2"])
        XCTAssertEqual(Request.defaultPromptVersion, .v1)
        XCTAssertEqual(try request().promptVersion, .v1)
        // The static values are v1's, byte for byte as before revision 11.
        XCTAssertEqual(Request.promptVersion, "prompt-v1")
        XCTAssertEqual(Request.instructionVersion, "pasted-label-ai-text-instruction-v1")
        XCTAssertEqual(Request.instructionResource, "pasted-label-ai-text-instruction-v1.txt")
        XCTAssertEqual(Request.instructionSHA256, "0773427c91e061638c85a588226f1ffaab0708901dda5d2b64456954a869cba6")
        let digester = SHA256Digester()
        for version in Request.PromptVersion.allCases {
            let instruction = try XCTUnwrap(OpenRouterLabelPhotoRequest.resource(version.instructionResource), version.rawValue)
            XCTAssertEqual(try digester.sha256(instruction).value, version.instructionSHA256, version.rawValue)
            XCTAssertTrue(String(decoding: instruction, as: UTF8.self).hasPrefix("\(version.instructionVersion) (\(version.rawValue), text route"),
                          version.rawValue)
        }
        XCTAssertEqual(Request.PromptVersion.v2.instructionSHA256, "3ea63efb3f1fc1fff22402941de021c999bdead05438fe45333dc1dcc31ab513")
    }

    /// The v2 body: pinned bytes, and only the system message's content differs from v1's.
    func testTheV2BodyDiffersFromV1OnlyInTheInstruction() throws {
        let text = "Typical values Per 100g\nFat 9.5g"
        let v1 = try request().body(text)
        let v2Request = try OpenRouterPastedLabelAITextRequest(route: Self.route, promptVersion: .v2)
        XCTAssertEqual(v2Request.promptVersion, .v2)
        let v2 = try v2Request.body(text)
        XCTAssertEqual(SHA256Digester().sha256Hex(v2), "3403dae8cec7b39f19677ae35f4be3da619e7adcd0041842d08d4d546ae32f42")
        XCTAssertNotEqual(v1, v2)
        var one = try XCTUnwrap(JSONSerialization.jsonObject(with: v1) as? [String: Any])
        var two = try XCTUnwrap(JSONSerialization.jsonObject(with: v2) as? [String: Any])
        let oneMessages = try XCTUnwrap(one["messages"] as? [[String: Any]])
        let twoMessages = try XCTUnwrap(two["messages"] as? [[String: Any]])
        XCTAssertEqual(twoMessages.count, 2)
        XCTAssertEqual(twoMessages[0]["role"] as? String, "system")
        XCTAssertTrue((twoMessages[0]["content"] as? String)?.hasPrefix("pasted-label-ai-text-instruction-v2 (prompt-v2") ?? false)
        XCTAssertNotEqual(oneMessages[0]["content"] as? String, twoMessages[0]["content"] as? String)
        XCTAssertEqual(twoMessages[1] as NSDictionary, oneMessages[1] as NSDictionary, "the same user message")
        // With the instruction removed, the two bodies are identical: the schema, the provider block
        // (one endpoint, no fallbacks, data collection denied, ZDR), the limits and the usage report.
        one["messages"] = [oneMessages[1]]
        two["messages"] = [twoMessages[1]]
        XCTAssertEqual(one as NSDictionary, two as NSDictionary)
        let provider = try XCTUnwrap(two["provider"] as? [String: Any])
        XCTAssertEqual(provider["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(provider["data_collection"] as? String, "deny")
        XCTAssertEqual(provider["only"] as? [String], ["google-vertex/us"])
        XCTAssertGreaterThan(v2Request.promptTokenBound(text), try request().promptTokenBound(text), "W follows the longer instruction")
        // The key is never in a v2 body either.
        let http = try v2Request.httpRequest("Fat 5g", key: Self.key)
        XCTAssertEqual(http.headers["Authorization"], "Bearer " + Self.key)
        XCTAssertNil(try XCTUnwrap(http.body).range(of: Data(Self.key.utf8)))
        XCTAssertThrowsError(try v2Request.httpRequest("Fat 5g " + Self.key, key: Self.key)) {
            XCTAssertEqual($0 as? OpenRouterPastedLabelAITextRequest.BuildError, .keyInBody)
        }
    }

    func testTheHTTPRequestCarriesTheKeyOnlyInItsHeader() throws {
        let http = try request().httpRequest("Fat 5g", key: Self.key)
        XCTAssertEqual(http.method, "POST")
        XCTAssertEqual(http.url.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(http.headers, ["Authorization": "Bearer " + Self.key, "Content-Type": "application/json"])
        XCTAssertThrowsError(try request().httpRequest("Fat 5g " + Self.key, key: Self.key)) {
            XCTAssertEqual($0 as? OpenRouterPastedLabelAITextRequest.BuildError, .keyInBody)
        }
    }

    func testAKeyThatJSONEscapingWouldHideIsStillRefused() throws {
        for key in ["sk-or-v1-a\"b", "sk-or-v1-a\\b"] {
            XCTAssertThrowsError(try request().httpRequest("Fat 5g " + key, key: key), key) {
                XCTAssertEqual($0 as? OpenRouterPastedLabelAITextRequest.BuildError, .keyInBody)
            }
            XCTAssertNoThrow(try request().httpRequest("Fat 5g", key: key), key)
        }
    }

    func testTheEightThousandScalarCap() throws {
        XCTAssertNoThrow(try request().body(String(repeating: "鈉", count: 8_000)))
        XCTAssertThrowsError(try request().body(String(repeating: "鈉", count: 8_001))) {
            XCTAssertEqual($0 as? OpenRouterPastedLabelAITextRequest.BuildError, .textTooLong)
        }
        XCTAssertThrowsError(try request().body(" \n")) { XCTAssertEqual($0 as? OpenRouterPastedLabelAITextRequest.BuildError, .textEmpty) }
    }

    func testOnlyATextRouteBuildsARequest() {
        let photoShaped = PastedLabelAITextRoute.Route(version: LabelPhotoRoute.current.version, candidateID: "x", model: Self.route.model,
                                                       endpoint: Self.route.endpoint, providerName: Self.route.providerName,
                                                       maxOutputTokens: 2_400, reasoningLimit: 500)
        XCTAssertThrowsError(try OpenRouterPastedLabelAITextRequest(route: photoShaped)) {
            XCTAssertEqual($0 as? OpenRouterPastedLabelAITextRequest.BuildError, .notATextRoute)
        }
    }

    func testTheFourThousandTokenCandidatesDifferOnlyInIDAndOutputCap() throws {
        let pairs = [(PastedLabelAITextRoute.gemini38FlashVertexUS, PastedLabelAITextRoute.gemini38FlashVertexUS4K),
                     (PastedLabelAITextRoute.gpt6LunaAzure, PastedLabelAITextRoute.gpt6LunaAzure4K),
                     (PastedLabelAITextRoute.gpt61SolAzure, PastedLabelAITextRoute.gpt61SolAzure4K)]
        for (base, wide) in pairs {
            XCTAssertEqual(wide.candidateID, base.candidateID + "-4k")
            XCTAssertEqual(wide.maxOutputTokens, 4_000)
            XCTAssertEqual(base.maxOutputTokens, 2_400)
            XCTAssertEqual([wide.version, wide.model, wide.endpoint, wide.providerName], [base.version, base.model, base.endpoint, base.providerName])
            XCTAssertEqual(wide.reasoningLimit, base.reasoningLimit)
            XCTAssertTrue(PastedLabelAITextRoute.isAdmitted(wide))
            XCTAssertEqual(PastedLabelAITextRoute.candidate(wide.candidateID), wide)
            let body = try JSONSerialization.jsonObject(with: try OpenRouterPastedLabelAITextRequest(route: wide).body("Energy 100 kJ")) as? [String: Any]
            XCTAssertEqual(body?["max_tokens"] as? Int, 4_000)
        }
        XCTAssertEqual(Set(PastedLabelAITextRoute.candidates.map(\.candidateID)).count, PastedLabelAITextRoute.candidates.count)
        XCTAssertNil(PastedLabelAITextRoute.current)
    }

    func testTheTerraAndLunaProFourThousandTokenCandidatesAreAdmittedAzureRoutes() throws {
        let expected = [(PastedLabelAITextRoute.gpt61TerraAzure4K, "gpt-6.1-terra-azure-4k", "openai/gpt-6.1-terra"),
                        (PastedLabelAITextRoute.gpt6LunaProAzure4K, "gpt-6-luna-pro-azure-4k", "openai/gpt-6-luna-pro")]
        for (route, id, model) in expected {
            XCTAssertEqual(route.candidateID, id)
            XCTAssertEqual(route.version, PastedLabelAITextRoute.version)
            XCTAssertEqual(route.model, model)
            XCTAssertEqual(route.endpoint, "azure")
            XCTAssertEqual(route.providerName, "Azure")
            XCTAssertEqual(route.maxOutputTokens, 4_000)
            XCTAssertEqual(route.reasoningLimit, 500)
            XCTAssertTrue(PastedLabelAITextRoute.isAdmitted(route))
            XCTAssertEqual(PastedLabelAITextRoute.candidate(id), route)
            let body = try JSONSerialization.jsonObject(with: try OpenRouterPastedLabelAITextRequest(route: route).body("Energy 100 kJ")) as? [String: Any]
            XCTAssertEqual(body?["max_tokens"] as? Int, 4_000)
        }
        XCTAssertEqual(Set(PastedLabelAITextRoute.candidates.map(\.candidateID)).count, PastedLabelAITextRoute.candidates.count)
        XCTAssertNil(PastedLabelAITextRoute.current)
    }

    /// Revision 17: every route that existed before the reasoning-off candidates sends the same bytes
    /// as before, for both prompt versions (pinned from the revision 16 builder).
    func testEveryReasoningBudgetRouteBodyIsUnchanged() throws {
        let goldens: [String: [String]] = [
            "gemini-4-argon-vertex-us": ["b9aba386aaf1e61026498b18e6b5d98e54e86ea9865a414e7a0670245070a6b5",
                                         "6c0910a64b0c7dc84007fb5cf7173c6bb6992053ed709f7ee0fb9fc3cc351ccf"],
            "gemini-3.8-flash-vertex-us": ["47e32bf82d936349118ada620427cd18764cf8d96ffdc9751916f5a578a1d4a5",
                                           "39ae4a3dff939dc9aa174f282848b1ef3b5eac736237158c81857dfbdc2b82ae"],
            "mistral-large-4-zdr": ["95214cceb82d2414b34ae7cc2735bd0bfd6cc5b1e06047ac9f0daecab9f69bd5",
                                    "56679711672d1a351e75820f013453b177a618bb76f41ecca00f4654a8cad4bf"],
            "gpt-6-luna-azure": ["25b818279e923348f9964ac2297ca1c0acc54f6eb8c52c40fddc6e0a20f05e30",
                                 "a529bae16f5708efb0d150621846f9ad789cecccce22c5be48282fc4a118bd4f"],
            "gpt-6.1-sol-azure": ["960bd3d7cc51b1f32ea00b3ee39ba9c3c5a00b984e0d625570b8c542d861b8ad",
                                  "7972d658e07aa0a853c59100bf0f92b7c2ef434c23961fc6a1c59b20579113ee"],
            "claude-haiku-5.5-vertex-global": ["38cb09cbea17bb340954989f48d0742f99850eb82610e9cfc60872db35971a2f",
                                               "1d0faba64b7ac3e5f709ce30a2edaf0d96b38319aa0a6a282ae31769eefb94b7"],
            "gemini-3.8-flash-vertex-us-4k": ["c0e2bda51ab7435e9dad8861d5a1533d1932cbe99a0313ec2ea301bd48ca5739",
                                              "b4495e762216ba4f9e15c272f8583e0680fabc27710207a6ecdff57d6cebdcd4"],
            "gpt-6-luna-azure-4k": ["9b2fb27c744268b82c7c36f6e793417421c86c2489454fbb2f5aa16d1f135a94",
                                    "55468bdbe87bdb40fe536d154b1552d240fa1c363da4518819a7afa2cd0c4b1f"],
            "gpt-6.1-sol-azure-4k": ["1f45ef408fc24b465387bcf4e15c8f03c49eb446c9915ec4211bad9a5dc1b96c",
                                     "62182b8939325b259e93033bc9ac1acb91e04b7b2d78125e5be74ef1350c34c8"],
            "gpt-6.1-terra-azure-4k": ["84087d5bcc3b3b6f572df0b5efc3db30dc49b441e22b754b5878039d13b4e488",
                                       "7b0e50d32a8d8f0a6a4a0f536103637b41e6c6d5531bd68acd6bf7451e3c1e05"],
            "gpt-6-luna-pro-azure-4k": ["b33e2cfb62fb037fed5c56fb064cf1fada7a3375d1fa8e4aa8e35f2bbaa8d542",
                                        "2313fd1a002db54075749e376db83537f9c8b4d360db4764039720ecf8f32327"],
        ]
        let budgeted = PastedLabelAITextRoute.candidates.filter { $0.reasoning != .off }
        XCTAssertEqual(Set(budgeted.map(\.candidateID)), Set(goldens.keys))
        for route in budgeted {
            for (index, version) in OpenRouterPastedLabelAITextRequest.PromptVersion.allCases.enumerated() {
                let body = try OpenRouterPastedLabelAITextRequest(route: route, promptVersion: version).body("Energy 100 kJ")
                XCTAssertEqual(SHA256Digester().sha256Hex(body), goldens[route.candidateID]?[index], "\(route.candidateID) \(version.rawValue)")
            }
            XCTAssertEqual(route.reasoningTokenBound, route.reasoningLimit)
        }
    }

    /// Revision 17: the reasoning-off candidates are their 4,000-token siblings with `effort: "none"`
    /// and nothing else changed. Sol and Gemini 3.8 Flash have none (reasoning is mandatory for both).
    func testTheReasoningOffCandidatesDifferFromTheirSiblingsOnlyInReasoning() throws {
        let pairs = [(PastedLabelAITextRoute.gpt61TerraAzure4K, PastedLabelAITextRoute.gpt61TerraAzure4KNoReason),
                     (PastedLabelAITextRoute.gpt6LunaAzure4K, PastedLabelAITextRoute.gpt6LunaAzure4KNoReason)]
        for (on, off) in pairs {
            XCTAssertEqual(off.candidateID, on.candidateID + "-noreason")
            XCTAssertEqual([off.version, off.model, off.endpoint, off.providerName], [on.version, on.model, on.endpoint, on.providerName])
            XCTAssertEqual(off.maxOutputTokens, 4_000)
            XCTAssertEqual(on.reasoning, .budget(500))
            XCTAssertEqual(off.reasoning, .off)
            XCTAssertEqual(off.reasoningLimit, 0)
            XCTAssertEqual(off.reasoningTokenBound, 4_000, "W counts the whole output cap as reasoning when billed separately")
            XCTAssertTrue(PastedLabelAITextRoute.isAdmitted(off))
            XCTAssertEqual(PastedLabelAITextRoute.candidate(off.candidateID), off)
            for version in OpenRouterPastedLabelAITextRequest.PromptVersion.allCases {
                let offBody = try OpenRouterPastedLabelAITextRequest(route: off, promptVersion: version).body("Energy 100 kJ")
                let onBody = try OpenRouterPastedLabelAITextRequest(route: on, promptVersion: version).body("Energy 100 kJ")
                var offObject = try XCTUnwrap(JSONSerialization.jsonObject(with: offBody) as? [String: Any])
                var onObject = try XCTUnwrap(JSONSerialization.jsonObject(with: onBody) as? [String: Any])
                XCTAssertEqual(offObject["reasoning"] as? [String: String], ["effort": "none"])
                XCTAssertEqual(onObject["reasoning"] as? [String: Int], ["max_tokens": 500])
                XCTAssertEqual(offObject["max_tokens"] as? Int, 4_000)
                let provider = try XCTUnwrap(offObject["provider"] as? [String: Any])
                XCTAssertEqual(provider["only"] as? [String], ["azure"])
                XCTAssertEqual(provider["order"] as? [String], ["azure"])
                XCTAssertEqual(provider["allow_fallbacks"] as? Bool, false)
                XCTAssertEqual(provider["require_parameters"] as? Bool, true)
                XCTAssertEqual(provider["data_collection"] as? String, "deny")
                XCTAssertEqual(provider["zdr"] as? Bool, true)
                offObject["reasoning"] = nil; onObject["reasoning"] = nil
                XCTAssertEqual(offObject as NSDictionary, onObject as NSDictionary, "schema, messages, provider and caps are the sibling's")
                XCTAssertFalse(String(decoding: offBody, as: UTF8.self).contains(Self.key))
                let http = try OpenRouterPastedLabelAITextRequest(route: off, promptVersion: version).httpRequest("Energy 100 kJ", key: Self.key)
                XCTAssertEqual(http.body, offBody)
                XCTAssertNil(http.body?.range(of: Data(Self.key.utf8)), "the key is only in the Authorization header")
                XCTAssertEqual(http.headers["Authorization"], "Bearer " + Self.key)
            }
        }
        let ids = Set(PastedLabelAITextRoute.candidates.map(\.candidateID))
        XCTAssertFalse(ids.contains("gpt-6.1-sol-azure-4k-noreason"), "Sol's reasoning is mandatory")
        XCTAssertFalse(ids.contains("gemini-3.8-flash-vertex-us-4k-noreason"), "Gemini 3.8 Flash's reasoning is mandatory")
        XCTAssertEqual(ids.count, PastedLabelAITextRoute.candidates.count)
        XCTAssertNil(PastedLabelAITextRoute.current)
        // An off route with another field changed is not admitted: the set is closed.
        let altered = PastedLabelAITextRoute.Route(version: PastedLabelAITextRoute.version, candidateID: "gpt-6-luna-azure-4k-noreason",
                                                   model: "openai/gpt-6-luna", endpoint: "azure", providerName: "Azure", maxOutputTokens: 4_000,
                                                   reasoningLimit: 500)
        XCTAssertFalse(PastedLabelAITextRoute.isAdmitted(altered))
    }

    // MARK: Test 28: the attempt adapter passes the attempting contract

    final class CountingTransport: LabelPhotoHTTPTransporting, @unchecked Sendable {
        let body: Data
        private let lock = NSLock()
        private var count = 0
        init(body: Data) { self.body = body }
        var sends: Int { lock.withLock { count } }
        func send(_ request: LabelPhotoHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse {
            lock.withLock { count += 1 }
            return LabelPhotoHTTPResponse(status: 200, headers: [:], body: body, exceededLimit: false)
        }
    }

    func testTheAttemptPassesTheAttemptingContract() async throws {
        let body = Data(#"{"id":"gen-1","choices":[]}"#.utf8)
        let transport = CountingTransport(body: body)
        let attempt = OpenRouterPastedLabelAITextAttempt(transport: transport, keys: Keys(Self.key), request: try request())
        let violations = await PastedLabelAITextPortContracts.attempting(attempt, body: body, sends: { transport.sends })
        XCTAssertEqual(violations, [])
    }

    func testNoKeyAndTransportFailures() async throws {
        let none = OpenRouterPastedLabelAITextAttempt(transport: Fake([]), keys: Keys(nil), request: try request())
        let noKey = await none.attempt(text: "Fat 5g", timeout: 5)
        XCTAssertEqual(noKey, .notSent(.keyMissing))
        for (error, failure) in [(LabelPhotoTransportError.timedOut, PastedLabelAITextTransportFailure.timedOut), (.offline, .offline),
                                 (.cancelled, .cancelled), (.failed, .failed)] {
            let attempt = OpenRouterPastedLabelAITextAttempt(transport: Fake([.failure(error)]), keys: Keys(Self.key), request: try request())
            let result = await attempt.attempt(text: "Fat 5g", timeout: 5)
            XCTAssertEqual(result, .transportFailed(failure))
        }
    }

    // MARK: The envelope check (T3)

    static func response(status: Int = 200, _ object: [String: Any]) -> PastedLabelAITextRawResponse {
        PastedLabelAITextRawResponse(status: status, headers: [:], body: try! JSONSerialization.data(withJSONObject: object), exceededLimit: false)
    }

    func testTheEnvelopeCheck() {
        let answer = OpenRouterLabelPhotoRouteTests.answer()
        guard case let .answered(content, model, provider, generationID, usage) = PastedLabelAITextEnvelope.check(Self.response(answer), route: Self.route) else {
            return XCTFail("a valid envelope did not answer")
        }
        XCTAssertEqual(String(decoding: content, as: UTF8.self), OpenRouterLabelPhotoRouteTests.wire, "the content bytes, undecoded")
        XCTAssertEqual([model, provider, generationID], ["google/gemini-4-argon", "Google", "gen-123"])
        XCTAssertEqual(usage.costUSD, "0.0123")
        func failure(_ object: [String: Any], status: Int = 200) -> LabelImageReadingFailure? {
            if case let .failed(_, failure, _) = PastedLabelAITextEnvelope.check(Self.response(status: status, object), route: Self.route) { return failure }
            return nil
        }
        XCTAssertEqual(failure(OpenRouterLabelPhotoRouteTests.answer(model: "google/gemini-4-argon-preview")), .wrongModel)
        XCTAssertEqual(failure(OpenRouterLabelPhotoRouteTests.answer(provider: "Google AI Studio")), .wrongProvider)
        XCTAssertEqual(failure(OpenRouterLabelPhotoRouteTests.answer(finish: "length")), .truncated)
        XCTAssertEqual(failure(OpenRouterLabelPhotoRouteTests.answer(message: ["role": "assistant", "content": "x", "refusal": "no"])), .refused)
        XCTAssertEqual(failure(OpenRouterLabelPhotoRouteTests.answer(choices: 2)), .unreadableAnswer)
        XCTAssertEqual(failure(["error": ["code": 401]], status: 401), .keyRejected)
        XCTAssertEqual(failure(["error": ["code": 503]], status: 503), .providerUnavailable)
        let oversize = PastedLabelAITextRawResponse(status: 200, headers: [:], body: Data(), exceededLimit: true)
        XCTAssertEqual(PastedLabelAITextEnvelope.check(oversize, route: Self.route), .failed(.contentFailure, failure: .oversize, usage: nil))
        // An unreported cost is unknown, never zero.
        let unknown = PastedLabelAITextEnvelope.check(Self.response(OpenRouterLabelPhotoRouteTests.answer(cost: "n/a")), route: Self.route)
        XCTAssertNil(unknown.reportedCost)
    }

    /// The application-layer envelope reads usage, numbers and providers as the photo attempt does.
    func testTheEnvelopesReadingsMatchThePhotoAttempt() {
        let objects: [[String: Any]] = [
            OpenRouterLabelPhotoRouteTests.answer(), OpenRouterLabelPhotoRouteTests.answer(cost: "n/a"), OpenRouterLabelPhotoRouteTests.answer(cost: -1),
            OpenRouterLabelPhotoRouteTests.answer(cost: true), ["usage": ["prompt_tokens": 1.5, "completion_tokens": "3"]], [:],
        ]
        for object in objects {
            XCTAssertEqual(PastedLabelAITextEnvelope.usage(in: object), OpenRouterLabelPhotoAttempt.usage(in: object))
        }
        for name in ["Google", " Google Vertex ", "google-vertex", "Google AI Studio"] {
            XCTAssertEqual(PastedLabelAITextEnvelope.normalisedProvider(name), OpenRouterLabelPhotoAttempt.normalisedProvider(name))
        }
        XCTAssertEqual(PastedLabelAITextEnvelope.maximumResponseBytes, OpenRouterLabelPhotoAttempt.maximumResponseBytes)
    }

    /// A2 gate finding 2: the prompt bound counts the instruction, schema and text bytes.
    func testThePromptBoundOfAFullTraditionalChineseText() throws {
        let request = try request()
        let text = String(repeating: "鈉", count: 8_000)
        let bound = request.promptTokenBound(text)
        XCTAssertEqual(bound, request.instruction.utf8.count + request.wireSchema.count + 24_000 + PastedLabelAITextSpendPolicy.framingTokens)
        XCTAssertLessThanOrEqual(bound, PastedLabelAITextSpendPolicy.promptTokenCeiling, "a full 8,000-scalar CJK text fits the ceiling")
    }

    // MARK: Test 21: the text route checker

    func catalogue(modalities: [String] = ["text", "image"], zdr: [String: Any] = OpenRouterLabelPhotoRouteTests.zdr) -> (Data, Data) {
        var listing = OpenRouterLabelPhotoRouteTests.listing
        var data = listing["data"] as! [String: Any]
        data["architecture"] = ["input_modalities": modalities]
        listing["data"] = data
        return (try! JSONSerialization.data(withJSONObject: listing), try! JSONSerialization.data(withJSONObject: zdr))
    }

    func testTheTextCheckerMatchesThePhotoCheckersRules() throws {
        let (listing, zdr) = catalogue()
        let text = try OpenRouterPastedLabelAITextRouteChecker.parse(listing: listing, zeroDataRetention: zdr, route: Self.route, at: 1, reasoningBilledSeparately: true)
        let photo = try OpenRouterLabelRouteChecker.parse(listing: listing, zeroDataRetention: zdr, route: LabelPhotoRoute.current, at: 1, reasoningBilledSeparately: true)
        XCTAssertEqual(text, photo, "the same listing gives the same check under both checkers")
        // The photo parse admits only the closed photo route set (gate finding 13).
        XCTAssertThrowsError(try OpenRouterLabelRouteChecker.parse(listing: listing, zeroDataRetention: zdr,
                                                                   route: OpenRouterPastedLabelAITextRouteChecker.listingShape(Self.route), at: 1,
                                                                   reasoningBilledSeparately: true))
        XCTAssertThrowsError(try OpenRouterPastedLabelAITextRouteChecker.parse(listing: catalogue(modalities: ["image"]).0, zeroDataRetention: zdr,
                                                                                route: Self.route, at: 1, reasoningBilledSeparately: true))
        XCTAssertThrowsError(try OpenRouterPastedLabelAITextRouteChecker.parse(listing: listing, zeroDataRetention: catalogue(zdr: ["data": []]).1,
                                                                                route: Self.route, at: 1, reasoningBilledSeparately: true))
    }

    /// A3: tiered `overrides` above the text ceiling and cache writes above the prompt price are
    /// accepted for the text route only, with W's prompt price raised to the highest input price.
    func testTheTextCheckerAcceptsTiersAboveItsCeilingAndPricesCacheWrites() throws {
        func listing(overridesFrom start: Int) throws -> Data {
            var listing = OpenRouterLabelPhotoRouteTests.listing
            var data = listing["data"] as! [String: Any]
            data["endpoints"] = (data["endpoints"] as! [[String: Any]]).map { endpoint in
                var endpoint = endpoint
                var pricing = endpoint["pricing"] as! [String: Any]
                pricing["input_cache_write"] = "0.000003"
                pricing["input_cache_write_1h"] = "0.000004"
                pricing["overrides"] = [["min_prompt_tokens": start, "prompt": "0.000005", "completion": "0.00002"]]
                endpoint["pricing"] = pricing
                return endpoint
            }
            listing["data"] = data
            return try JSONSerialization.data(withJSONObject: listing)
        }
        let zdr = try JSONSerialization.data(withJSONObject: OpenRouterLabelPhotoRouteTests.zdr)
        let accepted = try OpenRouterPastedLabelAITextRouteChecker.parse(listing: listing(overridesFrom: 272_000), zeroDataRetention: zdr,
                                                                         route: Self.route, at: 1, reasoningBilledSeparately: true)
        XCTAssertEqual(accepted.promptPrice, "0.000004", "W prices prompt tokens at the highest input price listed")
        XCTAssertThrowsError(try OpenRouterPastedLabelAITextRouteChecker.parse(listing: listing(overridesFrom: 10_000), zeroDataRetention: zdr,
                                                                                route: Self.route, at: 1, reasoningBilledSeparately: true),
                             "a tier a bounded request could reach is refused")
        XCTAssertThrowsError(try OpenRouterLabelRouteChecker.parse(listing: listing(overridesFrom: 272_000), zeroDataRetention: zdr,
                                                                   route: LabelPhotoRoute.current, at: 1, reasoningBilledSeparately: true),
                             "the photo route's rules are unchanged")
    }

    /// Qodo finding 2 on A2: a listing for another model that happens to hold the endpoint tag never qualifies it.
    func testAListingForAnotherModelIsRefused() throws {
        var listing = OpenRouterLabelPhotoRouteTests.listing
        var data = listing["data"] as! [String: Any]
        data["id"] = "google/gemini-4-argon-lite"
        listing["data"] = data
        let other = try JSONSerialization.data(withJSONObject: listing)
        let zdr = try JSONSerialization.data(withJSONObject: OpenRouterLabelPhotoRouteTests.zdr)
        XCTAssertThrowsError(try OpenRouterPastedLabelAITextRouteChecker.parse(listing: other, zeroDataRetention: zdr, route: Self.route, at: 1,
                                                                                reasoningBilledSeparately: true))
        XCTAssertThrowsError(try OpenRouterLabelRouteChecker.parse(listing: other, zeroDataRetention: zdr, route: LabelPhotoRoute.current, at: 1,
                                                                   reasoningBilledSeparately: true))
    }

    func testTheTextCheckerRefusesPhotoRoutesAndThePhotoCheckerRefusesTextRoutes() async throws {
        let photoAsText = PastedLabelAITextRoute.Route(version: LabelPhotoRoute.current.version, candidateID: Self.route.candidateID,
                                                       model: LabelPhotoRoute.current.model, endpoint: LabelPhotoRoute.current.endpoint,
                                                       providerName: LabelPhotoRoute.current.providerName,
                                                       maxOutputTokens: LabelPhotoRoute.current.maxOutputTokens, reasoningLimit: 500)
        let textTransport = Fake([])
        do {
            _ = try await OpenRouterPastedLabelAITextRouteChecker(transport: textTransport, clock: OpenRouterLabelPhotoRouteTests.Clock()).check(photoAsText)
            XCTFail("a photo route was checked as a text route")
        } catch { XCTAssertEqual(error as? OpenRouterPastedLabelAITextRouteChecker.CheckError, .notATextRoute) }
        XCTAssertTrue(textTransport.sent.isEmpty, "nothing fetched")
        let textAsPhoto = OpenRouterPastedLabelAITextRouteChecker.listingShape(Self.route)
        let photoTransport = Fake([])
        do {
            _ = try await OpenRouterLabelRouteChecker(transport: photoTransport, clock: OpenRouterLabelPhotoRouteTests.Clock()).check(textAsPhoto)
            XCTFail("a text route was checked as a photo route")
        } catch { XCTAssertEqual(error as? OpenRouterLabelRouteChecker.CheckError, .malformed) }
        XCTAssertTrue(photoTransport.sent.isEmpty)
        // The text checker on the text route: two anonymous GETs.
        let (listing, zdr) = catalogue()
        let transport = Fake([.success(.init(status: 200, headers: [:], body: listing, exceededLimit: false)),
                              .success(.init(status: 200, headers: [:], body: zdr, exceededLimit: false))])
        let check = try await OpenRouterPastedLabelAITextRouteChecker(transport: transport, clock: OpenRouterLabelPhotoRouteTests.Clock(), reasoningBilledSeparately: true).check(Self.route)
        XCTAssertTrue(check.zeroDataRetention)
        XCTAssertEqual(transport.sent.map { $0.0.headers }, [["Accept": "application/json"], ["Accept": "application/json"]])
    }
}

extension SHA256Digester {
    func sha256Hex(_ data: Data) -> String { (try? sha256(data).value) ?? "" }
}
