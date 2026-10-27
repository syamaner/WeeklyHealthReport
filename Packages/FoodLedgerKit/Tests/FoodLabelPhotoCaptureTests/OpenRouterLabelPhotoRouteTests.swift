@testable import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
import XCTest

/// The OpenRouter adapter over a fake transport (docs/label-photo-ai-prefill-v1.md E1, E2, E5, E7,
/// E8, E11, E12, 17.5; contract tests 7, 8, 21, 22 and the data URI part of 23). No network.
final class OpenRouterLabelPhotoRouteTests: XCTestCase {
    final class FakeTransport: LabelPhotoHTTPTransporting, @unchecked Sendable {
        var replies: [Result<LabelPhotoHTTPResponse, LabelPhotoTransportError>]
        var sent: [(LabelPhotoHTTPRequest, TimeInterval, Int)] = []
        init(_ replies: [Result<LabelPhotoHTTPResponse, LabelPhotoTransportError>]) { self.replies = replies }
        func send(_ request: LabelPhotoHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse {
            sent.append((request, timeout, maximumBodyBytes))
            return try replies.removeFirst().get()
        }
    }

    final class Keys: FoodWebKeyStoring, @unchecked Sendable {
        var key: String?
        init(_ key: String?) { self.key = key }
        func load() throws -> String? { key }
        func save(_ key: String) throws { self.key = key }
        func delete() throws { key = nil }
    }

    final class Clock: LedgerClock, @unchecked Sendable {
        func now() -> Date { Date(timeIntervalSince1970: 1_792_900_000) }
    }

    static let key = "sk-or-v1-0123456789abcdef0123456789abcdef"
    static let wire = #"{"declined":false,"decline_reasons":[],"language":"zh-Hant","serving_size_text":"unknown","servings_per_pack_text":"unknown","headers":[{"header_id":"h1","printed_text":"每份","basis":"per_serving"}],"rows":[{"printed_label":"熱量","nutrient":"energy_kcal","parent_nutrient":"none","values":[{"header_id":"h1","printed_text":"120大卡"}]}]}"#

    var image: PreparedLabelImage {
        try! PreparedLabelImageFactory.make(bytes: Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]), pixelWidth: 640, pixelHeight: 480,
                                            jpegQuality: "0.85", digester: SHA256Digester())
    }

    func request() throws -> OpenRouterLabelPhotoRequest { try OpenRouterLabelPhotoRequest() }

    static func reply(status: Int = 200, headers: [String: String] = [:], _ object: [String: Any], exceeded: Bool = false) -> LabelPhotoHTTPResponse {
        LabelPhotoHTTPResponse(status: status, headers: headers, body: try! JSONSerialization.data(withJSONObject: object), exceededLimit: exceeded)
    }

    static func answer(model: String = "google/gemini-4-argon", provider: String = "Google", finish: String = "stop",
                       message: [String: Any]? = nil, choices: Int = 1, cost: Any = 0.0123) -> [String: Any] {
        let choice: [String: Any] = ["index": 0, "finish_reason": finish, "message": message ?? ["role": "assistant", "content": wire]]
        return ["id": "gen-123", "model": model, "provider": provider, "choices": Array(repeating: choice, count: choices),
                "usage": ["prompt_tokens": 2_100, "completion_tokens": 640, "completion_tokens_details": ["reasoning_tokens": 300], "cost": cost]]
    }

    // MARK: Test 7: the request golden

    func testTheResourcesAreThePinnedBytes() throws {
        let digester = SHA256Digester()
        let instruction = try XCTUnwrap(OpenRouterLabelPhotoRequest.resource(OpenRouterLabelPhotoRequest.instructionResource))
        let schema = try XCTUnwrap(OpenRouterLabelPhotoRequest.resource(OpenRouterLabelPhotoRequest.wireSchemaResource))
        XCTAssertEqual(try digester.sha256(instruction).value, OpenRouterLabelPhotoRequest.instructionSHA256)
        XCTAssertEqual(try digester.sha256(schema).value, OpenRouterLabelPhotoRequest.wireSchemaSHA256)
    }

    func testTheRequestBodyIsExactlyE2AndE5() throws {
        let request = try request()
        let http = try request.httpRequest(image, key: Self.key)
        XCTAssertEqual(http.method, "POST")
        XCTAssertEqual(http.url.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(http.headers, ["Authorization": "Bearer " + Self.key, "Content-Type": "application/json"])
        let body = try XCTUnwrap(http.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["model", "messages", "response_format", "provider", "max_tokens", "reasoning", "stream", "usage"])
        XCTAssertEqual(object["model"] as? String, "google/gemini-4-argon")
        XCTAssertEqual(object["max_tokens"] as? Int, 2_400, "route v2 (17.21): E13 truncated two answers at 1,200")
        XCTAssertEqual(object["reasoning"] as? [String: Int], ["max_tokens": 500])
        XCTAssertEqual(object["stream"] as? Bool, false)
        XCTAssertEqual(object["usage"] as? [String: Bool], ["include": true])
        let provider = try XCTUnwrap(object["provider"] as? [String: Any])
        XCTAssertEqual(Set(provider.keys), ["only", "order", "allow_fallbacks", "require_parameters", "data_collection", "zdr"])
        XCTAssertEqual(provider["only"] as? [String], ["google-vertex/us"], "the one tag the live catalogue lists with status 0 (17.21)")
        XCTAssertEqual(provider["order"] as? [String], ["google-vertex/us"])
        XCTAssertEqual(provider["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(provider["require_parameters"] as? Bool, true)
        XCTAssertEqual(provider["data_collection"] as? String, "deny")
        XCTAssertEqual(provider["zdr"] as? Bool, true)
        // One user message: the fixed instruction and one image part.
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(Set(messages[0].keys), ["role", "content"])
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        let instruction = String(data: OpenRouterLabelPhotoRequest.resource(OpenRouterLabelPhotoRequest.instructionResource)!, encoding: .utf8)
        XCTAssertEqual(content[0] as? [String: String], ["type": "text", "text": instruction!])
        XCTAssertEqual(content[1]["type"] as? String, "image_url")
        let url = try XCTUnwrap((content[1]["image_url"] as? [String: String])?["url"])
        XCTAssertEqual(content[1]["image_url"] as? [String: String], ["url": url])
        // Test 23: the data URI decodes to exactly the prepared bytes.
        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertEqual(Data(base64Encoded: String(url.dropFirst("data:image/jpeg;base64,".count))), image.bytes)
        // The strict schema, without `$comment`.
        let format = try XCTUnwrap(object["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schemaBlock = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(Set(schemaBlock.keys), ["name", "description", "strict", "schema"])
        XCTAssertEqual(schemaBlock["name"] as? String, "label_image_extraction_v1")
        XCTAssertEqual(schemaBlock["strict"] as? Bool, true)
        let schemaText = String(data: try JSONSerialization.data(withJSONObject: schemaBlock["schema"]!), encoding: .utf8)!
        XCTAssertFalse(schemaText.contains("$comment"))
        XCTAssertTrue(schemaText.contains("decline_reasons"))
        // Nothing outside E2: the key is not in the body, and the whole body is pinned byte for byte.
        XCTAssertNil(body.range(of: Data(Self.key.utf8)))
        XCTAssertEqual(try SHA256Digester().sha256(body).value, Self.goldenBodySHA256, String(data: body, encoding: .utf8)!.prefix(400).description)
        XCTAssertEqual(try request.body(image), body, "reproducible bytes")
    }

    static let goldenBodySHA256 = "27d9558f6f1ea84d6f543a488ede5c0bc5391665ba4cbde5c49860c3d208df11"

    func testAKeyInsideTheBodyIsRefused() throws {
        // A key that happens to occur in the body (here, inside the instruction) is never sent.
        XCTAssertThrowsError(try request().httpRequest(image, key: "Copy every value exactly as printed")) { error in
            XCTAssertEqual(error as? OpenRouterLabelPhotoRequest.BuildError, .keyInBody)
        }
    }

    func testTheManifestRequestRecordsWhatWasSent() throws {
        let check = LabelPhotoManifest.CatalogueCheck(at: 1, slug: "google/gemini-4-argon", endpoint: "google-vertex/us", inputModalities: ["image"],
                                                      zeroDataRetention: true, promptPrice: "0.000002", completionPrice: "0.00001")
        let record = try request().manifestRequest(catalogue: check)
        XCTAssertEqual(record.maxOutputTokens, 2_400)
        XCTAssertEqual(record.reasoningLimit, 500)
        XCTAssertEqual(record.instructionVersion, "label-photo-instruction-v1")
        XCTAssertEqual(record.wireSchemaVersion, "label-photo-wire-schema-v1")
        XCTAssertEqual(record.instructionSHA256, OpenRouterLabelPhotoRequest.instructionSHA256)
        XCTAssertEqual(record.catalogueCheck, check)
    }

    // MARK: The attempt

    func testAnAnswerPassesEveryCheckAndCarriesItsUsage() async throws {
        let transport = FakeTransport([.success(Self.reply(Self.answer()))])
        let attempt = OpenRouterLabelPhotoAttempt(transport: transport, keys: Keys(Self.key), request: try request())
        let result = await attempt.attempt(image, timeout: 45)
        let usage = LabelPhotoManifest.Usage(promptTokens: 2_100, completionTokens: 640, reasoningTokens: 300, costUSD: "0.0123")
        XCTAssertEqual(result, .answered(wireText: Self.wire, model: "google/gemini-4-argon", provider: "Google", generationID: "gen-123",
                                         finishReason: "stop", usage: usage))
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(transport.sent[0].1, 45)
        XCTAssertEqual(transport.sent[0].2, 200_000)
    }

    func testNoKeyOrCancelBeforeSendingSendsNothing() async throws {
        let transport = FakeTransport([])
        let noKey = await OpenRouterLabelPhotoAttempt(transport: transport, keys: Keys(nil), request: try request()).attempt(image, timeout: 45)
        XCTAssertEqual(noKey, .notSent(.keyMissing))
        let attempt = OpenRouterLabelPhotoAttempt(transport: transport, keys: Keys(Self.key), request: try request())
        let prepared = image
        let task = Task { [attempt, prepared] in
            withUnsafeCurrentTask { $0?.cancel() }
            return await attempt.attempt(prepared, timeout: 45)
        }
        let cancelled = await task.value
        XCTAssertEqual(cancelled, .notSent(.cancelled))
        XCTAssertTrue(transport.sent.isEmpty)
    }

    // MARK: Test 8: response checks, each a failed read with nothing shown

    func testResponseChecks() {
        let route = LabelPhotoRoute.current
        func classify(_ response: LabelPhotoHTTPResponse) -> LabelImageReadingFailure? {
            if case let .failed(outcome, failure, _, _) = OpenRouterLabelPhotoAttempt.classify(response, route: route) {
                XCTAssertEqual(outcome, .contentFailure, "\(failure)")
                return failure
            }
            return nil
        }
        XCTAssertEqual(classify(Self.reply(Self.answer(model: "google/gemini-4-argon-mini"))), .wrongModel)
        XCTAssertEqual(classify(Self.reply(Self.answer(model: "google/gemini-4"))), .wrongModel)
        XCTAssertEqual(classify(Self.reply(Self.answer(model: "google/gemini-4-argon-20261332"))), .wrongModel, "not a calendar date")
        XCTAssertEqual(classify(Self.reply(Self.answer(provider: "Google AI Studio"))), .wrongProvider, "no prefix match")
        XCTAssertEqual(classify(Self.reply(Self.answer(provider: "Google Vertex"))), .wrongProvider, "exactly the route's provider name")
        XCTAssertNil(classify(Self.reply(Self.answer(provider: " google "))), "trimmed and lower-cased")
        var noProvider = Self.answer(); noProvider["provider"] = nil
        XCTAssertEqual(classify(Self.reply(noProvider)), .wrongProvider)
        // The catalogue's dated slug fails until E13 observes and pins it (17.21).
        XCTAssertEqual(classify(Self.reply(Self.answer(model: "google/gemini-4-argon-20261013"))), .wrongModel)
        XCTAssertEqual(classify(Self.reply(Self.answer(finish: "length"))), .truncated)
        XCTAssertEqual(classify(Self.reply(Self.answer(finish: "content_filter"))), .refused)
        XCTAssertEqual(classify(Self.reply(Self.answer(finish: "tool_calls"))), .failed)
        let toolCall: [String: Any] = ["role": "assistant", "content": Self.wire, "tool_calls": [["id": "t1", "type": "function"]]]
        XCTAssertEqual(classify(Self.reply(Self.answer(message: toolCall))), .failed)
        let refusal: [String: Any] = ["role": "assistant", "content": Self.wire, "refusal": "I cannot help with that."]
        XCTAssertEqual(classify(Self.reply(Self.answer(message: refusal))), .refused)
        XCTAssertEqual(classify(Self.reply(Self.answer(choices: 2))), .unreadableAnswer)
        XCTAssertEqual(classify(Self.reply(Self.answer(choices: 0))), .unreadableAnswer)
        let invalid: [String: Any] = ["role": "assistant", "content": Self.wire.replacingOccurrences(of: #""declined":false"#, with: #""declined":false,"confidence":1"#)]
        XCTAssertEqual(classify(Self.reply(Self.answer(message: invalid))), .unreadableAnswer, "schema-invalid")
        XCTAssertEqual(classify(Self.reply(Self.answer(), exceeded: true)), .oversize)
        XCTAssertEqual(classify(LabelPhotoHTTPResponse(status: 200, headers: [:], body: Data(repeating: 0x20, count: 200_001), exceededLimit: false)), .oversize)
        XCTAssertEqual(classify(LabelPhotoHTTPResponse(status: 200, headers: [:], body: Data("not json".utf8), exceededLimit: false)), .unreadableAnswer)
        // No pattern: a dated slug matches only once pinned at E13 (none yet).
        XCTAssertEqual(classify(Self.reply(Self.answer(model: "google/gemini-4-argon-2026-10-01"))), .wrongModel)
        XCTAssertEqual(classify(Self.reply(Self.answer(model: "google/gemini-4-argon-20261001"))), .wrongModel)
        XCTAssertEqual(OpenRouterLabelPhotoAttempt.pinnedSnapshots, ["google/gemini-4-argon": []])
    }

    func testUnknownCostIsNeverZero() {
        for cost in [NSNull(), "free", -1, true] as [Any] {
            let result = OpenRouterLabelPhotoAttempt.classify(Self.reply(Self.answer(cost: cost)), route: LabelPhotoRoute.current)
            guard case let .answered(_, _, _, _, _, usage) = result else { return XCTFail("\(cost)") }
            XCTAssertEqual(usage.costUSD, "unknown", "\(cost)")
        }
        let zero = OpenRouterLabelPhotoAttempt.classify(Self.reply(Self.answer(cost: 0)), route: LabelPhotoRoute.current)
        guard case let .answered(_, _, _, _, _, usage) = zero else { return XCTFail() }
        XCTAssertEqual(usage.costUSD, "0", "a reported zero is a reported cost")
    }

    // MARK: Retry classification (E11, 17.5) and transport failures

    func testRetryClassification() {
        func outcome(_ response: LabelPhotoHTTPResponse) -> (LabelPhotoRetryPolicy.Outcome, LabelImageReadingFailure, Decimal?)? {
            if case let .failed(outcome, failure, cost, _) = OpenRouterLabelPhotoAttempt.classify(response, route: LabelPhotoRoute.current) { return (outcome, failure, cost) }
            return nil
        }
        let busy = outcome(Self.reply(status: 503, headers: ["retry-after": "7"], ["error": ["code": 503, "message": "busy"]]))
        XCTAssertEqual(busy?.0, .providerError(code: 503, hasChoices: false, retryAfter: "7"))
        XCTAssertEqual(busy?.1, .providerUnavailable)
        for status in [408, 429, 500, 502, 504] {
            let result = outcome(Self.reply(status: status, ["error": ["code": status == 429 ? 429 : 400, "message": "x"]]))
            XCTAssertEqual(result?.0, .httpStatus(status, retryAfter: nil))
            XCTAssertTrue(LabelPhotoRetryPolicy.isRetryable(result!.0))
        }
        // The overloaded answer inside an HTTP 200 envelope, with no choices, and its reported cost.
        let envelope = outcome(Self.reply(["error": ["code": 529, "message": "overloaded"], "usage": ["cost": 0]]))
        XCTAssertEqual(envelope?.0, .providerError(code: 529, hasChoices: false, retryAfter: nil))
        XCTAssertEqual(envelope?.2, 0)
        // Not overloaded: an error object with choices, or another code, is not retried.
        let withChoices = outcome(Self.reply(Self.answer().merging(["error": ["code": 503]]) { $1 }))
        XCTAssertFalse(LabelPhotoRetryPolicy.isRetryable(withChoices!.0))
        let otherCode = outcome(Self.reply(["error": ["code": 400]]))
        XCTAssertFalse(LabelPhotoRetryPolicy.isRetryable(otherCode!.0))
        // A rejected key, and a client error, are not retried.
        XCTAssertEqual(outcome(Self.reply(status: 401, ["error": ["code": 401]]))?.1, .keyRejected)
        let badRequest = outcome(Self.reply(status: 400, ["error": ["code": 400]]))
        XCTAssertEqual(badRequest?.1, .failed)
        XCTAssertFalse(LabelPhotoRetryPolicy.isRetryable(badRequest!.0))
    }

    func testTransportFailuresAreRetryableAndCarryNoCost() async throws {
        let cases: [(LabelPhotoTransportError, LabelPhotoRetryPolicy.Outcome, LabelImageReadingFailure)] = [
            (.timedOut, .timedOut, .timedOut), (.failed, .transportError, .providerUnavailable),
            (.offline, .transportError, .offline), (.cancelled, .transportError, .cancelled),
        ]
        for (error, expected, failure) in cases {
            let attempt = OpenRouterLabelPhotoAttempt(transport: FakeTransport([.failure(error)]), keys: Keys(Self.key), request: try request())
            let result = await attempt.attempt(image, timeout: 30)
            XCTAssertEqual(result, .failed(expected, failure: failure, reportedCost: nil, promptTokens: nil))
        }
    }

    // MARK: Test 22: the catalogue check

    /// The live pricing object of 26 October 2026 at 02:54Z (17.21), field for field: three Google
    /// Vertex tags, all named "Google", reasoning at the completion rate, image at the prompt rate,
    /// cache prices below it, audio and web search prices, and a numeric discount.
    static func endpoint(_ tag: String, _ prompt: String, _ completion: String, extra: [String: Any] = [:]) -> [String: Any] {
        let p = Decimal(string: prompt)!
        var pricing: [String: Any] = ["prompt": prompt, "completion": completion, "image": prompt, "audio": prompt,
                                      "input_audio_cache": "\(p / 20)", "web_search": "0.014", "internal_reasoning": completion,
                                      "input_cache_read": "\(p / 20)", "input_cache_write": "0.0000001875", "discount": 0.5]
        pricing.merge(extra) { $1 }
        return ["tag": tag, "provider_name": "Google", "name": "Google | google/gemini-4-argon-20261013", "pricing": pricing]
    }
    static func listing(_ endpoints: [[String: Any]]) -> [String: Any] {
        ["data": ["id": "google/gemini-4-argon", "architecture": ["input_modalities": ["text", "image"]], "endpoints": endpoints]]
    }
    nonisolated(unsafe) static let listing: [String: Any] = listing([
        endpoint("google-vertex/global", "0.000002", "0.00001"),
        endpoint("google-vertex/us", "0.0000022", "0.000011"),
        endpoint("google-vertex/global/priority", "0.0000036", "0.000018"),
    ])
    nonisolated(unsafe) static let zdr: [String: Any] = ["data": ["google-vertex/global", "google-vertex/us", "google-vertex/global/priority"].map {
        ["model_id": "google/gemini-4-argon", "tag": $0, "provider_name": "Google"]
    }]

    func testTheCatalogueCheckIsTwoAnonymousGets() async throws {
        let transport = FakeTransport([.success(Self.reply(Self.listing)), .success(Self.reply(Self.zdr))])
        let check = try await OpenRouterLabelRouteChecker(transport: transport, clock: Clock(), reasoningBilledSeparately: true)
            .check(LabelPhotoRoute.current)
        XCTAssertEqual(check, LabelPhotoManifest.CatalogueCheck(at: 1_792_900_000_000, slug: "google/gemini-4-argon", endpoint: "google-vertex/us",
                                                                inputModalities: ["text", "image"], zeroDataRetention: true,
                                                                promptPrice: "0.0000022", completionPrice: "0.000011"))
        XCTAssertEqual(transport.sent.map(\.0.url.absoluteString), ["https://openrouter.ai/api/v1/models/google/gemini-4-argon/endpoints",
                                                                    "https://openrouter.ai/api/v1/endpoints/zdr"])
        for (request, _, _) in transport.sent {
            XCTAssertEqual(request.method, "GET")
            XCTAssertNil(request.body)
            XCTAssertEqual(request.headers, ["Accept": "application/json"], "no Authorization header and no user data")
        }
        let prices = try XCTUnwrap(LabelPhotoReadSession.prices(check, route: LabelPhotoRoute.current, reasoningBilledSeparately: true))
        XCTAssertEqual(LabelPhotoSpendPolicy.worstCase(prices), Decimal(string: "0.0451"), "6,000 x 2.2e-6 + (2,400 + 500) x 1.1e-5")
        XCTAssertFalse(LabelPhotoSpendPolicy.mayStartAttempt(after: [.init(reportedCost: nil, promptTokens: nil)], prices: prices),
                       "no retry after an unreported failure")
        XCTAssertTrue(LabelPhotoSpendPolicy.mayStartAttempt(after: [.init(reportedCost: 0, promptTokens: nil)], prices: prices))
    }

    // MARK: L5: the live route identity and the prices W models (17.21)

    func testOnlyTheUSEndpointPassesOnTheLiveCatalogue() async throws {
        for route in LabelPhotoRoute.admitted where route.endpoint != LabelPhotoRoute.current.endpoint {
            let transport = FakeTransport([.success(Self.reply(Self.listing)), .success(Self.reply(Self.zdr))])
            do { _ = try await OpenRouterLabelRouteChecker(transport: transport, clock: Clock(), reasoningBilledSeparately: true).check(route)
                XCTFail("\(route.endpoint) is not listed") } catch {}
        }
        XCTAssertEqual(LabelPhotoRoute.current.endpoint, "google-vertex/us")
        XCTAssertEqual(LabelPhotoRoute.current.providerName, "Google")
        // The live ZDR listing was 1,098,446 bytes on 26 October 2026: the old 1 MB cap failed every check.
        XCTAssertEqual(OpenRouterLabelRouteChecker.maximumResponseBytes, 8_000_000)
        // A ZDR entry naming the model only under `model` is not listed (17.21: `model_id` and `tag`).
        let legacy: [String: Any] = ["data": [["model": "google/gemini-4-argon", "tag": "google-vertex/us"]]]
        let check = try await OpenRouterLabelRouteChecker(transport: FakeTransport([.success(Self.reply(Self.listing)), .success(Self.reply(legacy))]),
                                                          clock: Clock(), reasoningBilledSeparately: true).check(LabelPhotoRoute.current)
        XCTAssertFalse(check.zeroDataRetention)
        // The priority endpoint's prices give a W above the tap's $0.05.
        let priority = LabelPhotoManifest.CatalogueCheck(at: 1, slug: "google/gemini-4-argon", endpoint: "google-vertex/us", inputModalities: ["image"],
                                                         zeroDataRetention: true, promptPrice: "0.0000036", completionPrice: "0.000018")
        XCTAssertNil(LabelPhotoReadSession.prices(priority, route: LabelPhotoRoute.current, reasoningBilledSeparately: true))
    }

    func testAPriceWDoesNotModelFailsClosed() async throws {
        let cases: [([String: Any], Bool)] = [
            (["internal_reasoning": "0.00002"], true),
            (["image": "0.001"], true),
            (["input_cache_read": "0.000003"], true),
            (["input_cache_write": "0.000003"], true),
            (["request": "0.0001"], true),
            (["unknown_charge": "0.01"], true),
            (["image": "free"], true),
            (["discount": 1], true),
            (["discount": -0.1], true),
            (["discount": "0.5"], true),
            (["discount": true], true),
            ([:], false),
        ]
        for (extra, separately) in cases {
            let listing = Self.listing([Self.endpoint("google-vertex/us", "0.0000022", "0.000011", extra: extra)])
            let transport = FakeTransport([.success(Self.reply(listing)), .success(Self.reply(Self.zdr))])
            do {
                _ = try await OpenRouterLabelRouteChecker(transport: transport, clock: Clock(), reasoningBilledSeparately: separately)
                    .check(LabelPhotoRoute.current)
                XCTFail("\(extra) \(separately)")
            } catch {
                XCTAssertEqual(error as? OpenRouterLabelRouteChecker.CheckError, .unavailable, "kept as route unavailable, nothing sent")
            }
        }
    }

    func testTheLivePricingObjectIsAdmitted() async throws {
        // Unknown-to-W fields that cannot raise the cost pass: cache prices below the prompt rate,
        // never-sent audio and web search prices, a zero request price and a discount under 1.
        for extra in [[:], ["request": "0"], ["web_search": "0.02"], ["discount": 0]] as [[String: Any]] {
            let listing = Self.listing([Self.endpoint("google-vertex/us", "0.0000022", "0.000011", extra: extra)])
            let transport = FakeTransport([.success(Self.reply(listing)), .success(Self.reply(Self.zdr))])
            let check = try await OpenRouterLabelRouteChecker(transport: transport, clock: Clock(), reasoningBilledSeparately: true)
                .check(LabelPhotoRoute.current)
            XCTAssertEqual(check.promptPrice, "0.0000022", "\(extra)")
        }
    }

    func testACatalogueHTTPFailureIsKeptButATimeoutIsNot() async {
        do {
            _ = try await OpenRouterLabelRouteChecker(transport: FakeTransport([.success(Self.reply(status: 503, ["error": ["code": 503]]))]),
                                                      clock: Clock()).check(LabelPhotoRoute.current)
            XCTFail("503")
        } catch {
            XCTAssertNil(error as? LabelPhotoRouteCheckFailure)
        }
        do {
            _ = try await OpenRouterLabelRouteChecker(transport: FakeTransport([.failure(.timedOut)]), clock: Clock()).check(LabelPhotoRoute.current)
            XCTFail("timed out")
        } catch {
            XCTAssertEqual(error as? LabelPhotoRouteCheckFailure, .transport(.timedOut))
        }
    }

    func testACatalogueThatDoesNotMatchFailsOrIsRejected() async throws {
        // Not on the ZDR list: the check reports it, and the session's comparison rejects it.
        let notZDR: [String: Any] = ["data": [["model_id": "google/gemini-4-argon", "tag": "google-vertex/global"]]]
        let transport = FakeTransport([.success(Self.reply(Self.listing)), .success(Self.reply(notZDR))])
        let check = try await OpenRouterLabelRouteChecker(transport: transport, clock: Clock(), reasoningBilledSeparately: true).check(LabelPhotoRoute.current)
        XCTAssertFalse(check.zeroDataRetention)
        XCTAssertNil(LabelPhotoReadSession.prices(check, route: LabelPhotoRoute.current, reasoningBilledSeparately: true))
        // An HTTP error, a transport failure, a missing endpoint or an unpriced one throws.
        let failures: [[Result<LabelPhotoHTTPResponse, LabelPhotoTransportError>]] = [
            [.success(Self.reply(status: 500, ["error": ["code": 500]]))],
            [.failure(.offline)],
            [.success(Self.reply(["data": ["id": "google/gemini-4-argon", "endpoints": []]])), .success(Self.reply(Self.zdr))],
            [.success(Self.reply(["data": ["id": "google/gemini-4-argon", "endpoints": [["tag": "google-vertex/us", "pricing": ["prompt": "-1", "completion": "1"]]]]])),
             .success(Self.reply(Self.zdr))],
            [.success(Self.reply(Self.listing, exceeded: true))],
        ]
        for replies in failures {
            do {
                _ = try await OpenRouterLabelRouteChecker(transport: FakeTransport(replies), clock: Clock()).check(LabelPhotoRoute.current)
                XCTFail("\(replies)")
            } catch {}
        }
    }
}
