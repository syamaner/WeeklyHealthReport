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

    func testTheHTTPRequestCarriesTheKeyOnlyInItsHeader() throws {
        let http = try request().httpRequest("Fat 5g", key: Self.key)
        XCTAssertEqual(http.method, "POST")
        XCTAssertEqual(http.url.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(http.headers, ["Authorization": "Bearer " + Self.key, "Content-Type": "application/json"])
        XCTAssertThrowsError(try request().httpRequest("Fat 5g " + Self.key, key: Self.key)) {
            XCTAssertEqual($0 as? OpenRouterPastedLabelAITextRequest.BuildError, .keyInBody)
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
        XCTAssertThrowsError(try OpenRouterPastedLabelAITextRouteChecker.parse(listing: catalogue(modalities: ["image"]).0, zeroDataRetention: zdr,
                                                                                route: Self.route, at: 1, reasoningBilledSeparately: true))
        XCTAssertThrowsError(try OpenRouterPastedLabelAITextRouteChecker.parse(listing: listing, zeroDataRetention: catalogue(zdr: ["data": []]).1,
                                                                                route: Self.route, at: 1, reasoningBilledSeparately: true))
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
