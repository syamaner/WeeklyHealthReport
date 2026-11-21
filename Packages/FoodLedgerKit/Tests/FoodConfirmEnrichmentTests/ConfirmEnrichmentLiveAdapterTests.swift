@testable import FoodConfirmEnrichment
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import Foundation
import XCTest

/// The live adapters, transport and route checker of Confirm enrichment (docs/confirm-enrichment-openrouter-v1-phase.md
/// section 7: G5 for the live adapters, G6 and G14). Everything runs over a recording transport or a stub
/// URLProtocol on the transport's own configuration: nothing here reaches the network, and no real key is used.
final class ConfirmEnrichmentLiveAdapterTests: XCTestCase {
    static let key = "sk-or-v1-synthetic-test-key-0000000000"

    final class Keys: FoodWebKeyStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        private(set) var loads = 0
        init(_ key: String?) { stored = key }
        func load() throws -> String? { lock.withLock { loads += 1; return stored } }
        func save(_ key: String) throws { lock.withLock { stored = key } }
        func delete() throws { lock.withLock { stored = nil } }
    }

    /// Records every request and answers from a script.
    final class Recording: ConfirmEnrichmentHTTPTransporting, @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [Result<ConfirmEnrichmentHTTPResponse, ConfirmEnrichmentTransportError>]
        private(set) var requests: [ConfirmEnrichmentHTTPRequest] = []
        init(_ replies: [Result<ConfirmEnrichmentHTTPResponse, ConfirmEnrichmentTransportError>]) { self.replies = replies }
        func send(_ request: ConfirmEnrichmentHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws
            -> ConfirmEnrichmentHTTPResponse {
            let reply = lock.withLock { () -> Result<ConfirmEnrichmentHTTPResponse, ConfirmEnrichmentTransportError> in
                requests.append(request)
                return replies.count > 1 ? replies.removeFirst() : (replies.first ?? .failure(.failed))
            }
            return try reply.get()
        }
    }

    static func ok(_ body: String = "{}", status: Int = 200, headers: [String: String] = [:], exceeded: Bool = false)
        -> Result<ConfirmEnrichmentHTTPResponse, ConfirmEnrichmentTransportError> {
        .success(ConfirmEnrichmentHTTPResponse(status: status, headers: headers, body: Data(body.utf8), exceededLimit: exceeded))
    }

    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/fixtures/confirm-enrichment-v1/requests", isDirectory: true)
    }

    /// XCTest's assertions take autoclosures, which cannot await: this takes plain arguments.
    func eq<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, message, file: file, line: line)
    }

    // MARK: G5 for the live adapters

    func testBothLiveAdaptersPassTheSharedSingleAttemptSuite() async {
        let details = await ConfirmEnrichmentPortContracts.attemptViolations(use: .confirmEnrichmentDetails, { egress in
            DetailsAttempting(OpenRouterJevFoodDetailsAdapter(egress: egress, transport: Recording([Self.ok()]), keys: Keys(Self.key)))
        }, body: Data("{}".utf8))
        XCTAssertEqual(details, [])
        let nutrients = await ConfirmEnrichmentPortContracts.attemptViolations(use: .confirmEnrichmentNutrients, { egress in
            NutrientAttempting(OpenRouterNutrientEstimateAdapter(egress: egress, transport: Recording([Self.ok()]), keys: Keys(Self.key)))
        }, body: Data("{}".utf8))
        XCTAssertEqual(nutrients, [])
    }

    func testAUseNotInForceMakesZeroTransportCallsWithBothSwitchesOn() async {
        // The app's gate refuses every use not in force; a gate built the same way stands in for it.
        struct InForceOnly: OpenRouterEgressPermitting { func permits(_ use: OpenRouterUse) -> Bool { use.isInForce } }
        let transport = Recording([Self.ok()])
        let adapter = OpenRouterNutrientEstimateAdapter(egress: InForceOnly(), transport: transport, keys: Keys(Self.key))
        let result = await adapter.attempt(Data("{}".utf8), timeout: 30)
        XCTAssertEqual(result, .notSent(.notPermitted))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testTheKeyIsReadOnEveryAttemptAndAReplacedKeyIsSentAsItIsNow() async {
        let keys = Keys(Self.key)
        let transport = Recording([Self.ok()])
        let adapter = OpenRouterJevFoodDetailsAdapter(egress: PermittingOpenRouterEgress(), transport: transport, keys: keys)
        _ = await adapter.attempt(Data("{}".utf8), timeout: 30)
        try? keys.save("sk-or-v1-synthetic-replacement-key-000000")
        _ = await adapter.attempt(Data("{}".utf8), timeout: 30)
        XCTAssertEqual(keys.loads, 2)
        XCTAssertEqual(transport.requests.map { $0.headers["Authorization"] },
                       ["Bearer \(Self.key)", "Bearer sk-or-v1-synthetic-replacement-key-000000"])
        let refused = OpenRouterJevFoodDetailsAdapter(egress: RecordingOpenRouterEgress(permits: false), transport: transport, keys: keys)
        try? keys.save("sk-or-v1-synthetic-third-key-0000000000000")
        eq(await refused.attempt(Data("{}".utf8), timeout: 30), .notSent(.notPermitted),
                       "a key replaced while OpenRouter was off is never sent")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testNoKeyOrAKeyInTheBodySendsNothing() async {
        let transport = Recording([Self.ok()])
        let none = OpenRouterNutrientEstimateAdapter(egress: PermittingOpenRouterEgress(), transport: transport, keys: Keys(nil))
        eq(await none.attempt(Data("{}".utf8), timeout: 30), .notSent(.noKey))
        let leaking = OpenRouterNutrientEstimateAdapter(egress: PermittingOpenRouterEgress(), transport: transport, keys: Keys(Self.key))
        eq(await leaking.attempt(Data(#"{"note":"\#(Self.key)"}"#.utf8), timeout: 30), .notSent(.noKey))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testTheAdapterReportsStatusBodyRetryAfterAndTheByteLimitOnly() async {
        let transport = Recording([Self.ok("{\"error\":1}", status: 503, headers: ["retry-after": "7"]), Self.ok("x", exceeded: true),
                                   .failure(.timedOut), .failure(.offline), .failure(.failed), .failure(.cancelled)])
        let adapter = OpenRouterNutrientEstimateAdapter(egress: PermittingOpenRouterEgress(), transport: transport, keys: Keys(Self.key))
        eq(await adapter.attempt(Data("{}".utf8), timeout: 30),
                       .sent(status: 503, body: Data("{\"error\":1}".utf8), retryAfter: "7"))
        eq(await adapter.attempt(Data("{}".utf8), timeout: 30), .transportFailed(.tooLarge))
        eq(await adapter.attempt(Data("{}".utf8), timeout: 30), .transportFailed(.timedOut))
        eq(await adapter.attempt(Data("{}".utf8), timeout: 30), .transportFailed(.offline))
        eq(await adapter.attempt(Data("{}".utf8), timeout: 30), .transportFailed(.connectionFailed))
        eq(await adapter.attempt(Data("{}".utf8), timeout: 30), .transportFailed(.cancelled))
    }

    // MARK: G6 Wire bytes

    func testTheWireBytesEqualTheGoldensAndOnlyTheAuthorizationHeaderHoldsTheKey() async throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.fixtures, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let golden = try Data(contentsOf: file)
            let isDetails = file.lastPathComponent.hasSuffix("-details.json")
            let route = isDetails ? ConfirmEnrichmentRoutes.details : ConfirmEnrichmentRoutes.nutrients
            let transport = Recording([Self.ok()])
            let result: ConfirmEnrichmentAttemptResult = isDetails
                ? await OpenRouterJevFoodDetailsAdapter(egress: PermittingOpenRouterEgress(), transport: transport, keys: Keys(Self.key))
                    .attempt(golden, timeout: 30)
                : await OpenRouterNutrientEstimateAdapter(egress: PermittingOpenRouterEgress(), transport: transport, keys: Keys(Self.key))
                    .attempt(golden, timeout: 30)
            XCTAssertEqual(result, .sent(status: 200, body: Data("{}".utf8), retryAfter: nil), file.lastPathComponent)
            let request = try XCTUnwrap(transport.requests.first)
            XCTAssertEqual(request.body, golden, "\(file.lastPathComponent): the wire bytes are the golden's, unchanged")
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.url.absoluteString, route.endpoint)
            let holding = request.headers.filter { $0.value.contains(Self.key) }.map(\.key)
            XCTAssertEqual(holding, ["Authorization"], file.lastPathComponent)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: golden) as? [String: Any])
            let provider = try XCTUnwrap(body["provider"] as? [String: Any])
            XCTAssertEqual(provider["only"] as? [String], [route.providerEndpoint])
            XCTAssertEqual(provider["order"] as? [String], [route.providerEndpoint])
            XCTAssertEqual(provider["allow_fallbacks"] as? Bool, false)
            XCTAssertEqual(provider["require_parameters"] as? Bool, true)
            XCTAssertEqual(provider["data_collection"] as? String, "deny")
            XCTAssertEqual(provider["zdr"] as? Bool, true)
            XCTAssertEqual(body["model"] as? String, route.model)
        }
    }

    // MARK: The live transport (stub URLProtocol)

    final class Stub: URLProtocol {
        enum Reply { case ok(Int, Data, [String: String]), redirect }
        nonisolated(unsafe) static var reply: Reply = .ok(200, Data(), [:])
        nonisolated(unsafe) static var seen: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.seen.append(request)
            switch Self.reply {
            case let .ok(status, body, headers):
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            case .redirect:
                let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                                               headerFields: ["Location": "https://elsewhere.example/steal"])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://elsewhere.example/steal")!), redirectResponse: response)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    override func setUp() { Stub.reply = .ok(200, Data(), [:]); Stub.seen = [] }

    func stubbedTransport() -> ConfirmEnrichmentTransport { ConfirmEnrichmentTransport { $0.protocolClasses = [Stub.self] } }

    func testTheTransportRefusesEveryRedirect() async {
        Stub.reply = .redirect
        let request = ConfirmEnrichmentHTTPRequest(method: "POST", url: URL(string: ConfirmEnrichmentRoutes.nutrientURL)!,
                                                   headers: ["Authorization": "Bearer \(Self.key)"], body: Data("{}".utf8))
        do {
            _ = try await stubbedTransport().send(request, timeout: 5, maximumBodyBytes: 1_000)
            XCTFail("a redirect was followed")
        } catch {
            XCTAssertEqual(error as? ConfirmEnrichmentTransportError, .failed)
        }
        XCTAssertFalse(Stub.seen.contains { $0.url?.host == "elsewhere.example" }, "the redirect target is never requested")
    }

    func testTheTransportSendsFixedNeutralHeadersAndStopsAtTheByteLimit() async throws {
        Stub.reply = .ok(200, Data(repeating: 0x41, count: 5_000), [:])
        let request = ConfirmEnrichmentHTTPRequest(method: "GET", url: URL(string: ConfirmEnrichmentRoutes.zeroDataRetentionURL)!,
                                                   headers: ["Accept": "application/json"], body: nil)
        let response = try await stubbedTransport().send(request, timeout: 5, maximumBodyBytes: 1_000)
        XCTAssertTrue(response.exceededLimit)
        XCTAssertLessThanOrEqual(response.body.count, 1_000)
        let seen = try XCTUnwrap(Stub.seen.first)
        XCTAssertEqual(seen.value(forHTTPHeaderField: "User-Agent"), ConfirmEnrichmentTransport.userAgent)
        XCTAssertEqual(seen.value(forHTTPHeaderField: "Accept-Language"), "*")
        XCTAssertNil(seen.value(forHTTPHeaderField: "Authorization"), "a catalogue GET is keyless")
        XCTAssertNil(seen.value(forHTTPHeaderField: "Cookie"))
    }

    // MARK: G14 Route check

    static func listing(_ route: ConfirmEnrichmentRoute, prompt: String = "0.0000002", completion: String = "0.0000008",
                        extra: [String: Any] = [:], slug: String? = nil) throws -> String {
        var pricing: [String: Any] = ["prompt": prompt, "completion": completion]
        for (name, value) in extra { pricing[name] = value }
        let body: [String: Any] = ["data": ["id": slug ?? route.model,
                                            "endpoints": [["tag": route.providerEndpoint, "pricing": pricing], ["tag": "other", "pricing": pricing]]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    }

    static func retention(_ route: ConfirmEnrichmentRoute, listed: Bool = true) throws -> String {
        let entries: [[String: Any]] = listed ? [["model_id": route.model, "tag": route.providerEndpoint]] : [["model_id": "x/y", "tag": "z"]]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["data": entries]), as: UTF8.self)
    }

    func testTheCheckAsksTheGateBeforeEachFetchWithTheCallersCatalogueUse() async throws {
        for part in ConfirmEnrichmentPart.allCases {
            let route = ConfirmEnrichmentRoutes.all.route(part)
            let egress = RecordingOpenRouterEgress(permits: true)
            let transport = Recording([Self.ok(try Self.listing(route)), Self.ok(try Self.retention(route))])
            let result = await ConfirmEnrichmentRouteChecker(egress: egress, transport: transport).check(part, catalogueUse: part.catalogueUse)
            XCTAssertEqual(result, .passed(ConfirmEnrichmentPrices(promptPerTokenUSD: Decimal(string: "0.0000002")!,
                                                                   completionPerTokenUSD: Decimal(string: "0.0000008")!)))
            XCTAssertEqual(egress.uses, [part.catalogueUse, part.catalogueUse])
            XCTAssertEqual(transport.requests.map(\.url.absoluteString),
                           [ConfirmEnrichmentRouteChecker.endpointsURL(route)!.absoluteString, ConfirmEnrichmentRoutes.zeroDataRetentionURL])
            XCTAssertTrue(transport.requests.allSatisfy { $0.method == "GET" && $0.body == nil && $0.headers["Authorization"] == nil })
        }
    }

    func testARefusalBeforeEitherFetchSendsNothingMore() async throws {
        let route = ConfirmEnrichmentRoutes.nutrients
        for scripted in [[false], [true, false]] {
            let egress = RecordingOpenRouterEgress(permits: scripted[0], then: Array(scripted.dropFirst()))
            let transport = Recording([Self.ok(try Self.listing(route)), Self.ok(try Self.retention(route))])
            let result = await ConfirmEnrichmentRouteChecker(egress: egress, transport: transport)
                .check(.nutrients, catalogueUse: .confirmEnrichmentNutrientsCatalogueCheck)
            XCTAssertEqual(result, .notPermitted)
            XCTAssertEqual(transport.requests.count, scripted.count - 1)
        }
    }

    func testAConnectionFailureIsReportedAsSuchAndAnyOtherFailureMakesThePartUnavailable() async throws {
        let route = ConfirmEnrichmentRoutes.details
        let offline = Recording([.failure(.offline)])
        eq(await ConfirmEnrichmentRouteChecker(egress: PermittingOpenRouterEgress(), transport: offline)
                        .check(.details, catalogueUse: .confirmEnrichmentDetailsCatalogueCheck), .connectionFailed)
        let cases: [(String, String)] = [
            (try Self.listing(route), try Self.retention(route, listed: false)),
            (try Self.listing(route, slug: "other/model"), try Self.retention(route)),
            (try Self.listing(route, extra: ["request": "0.01"]), try Self.retention(route)),
            (try Self.listing(route, extra: ["internal_reasoning": "0.0000001"]), try Self.retention(route)),
            (try Self.listing(route, extra: ["input_cache_read": "0.001"]), try Self.retention(route)),
            ("not json", try Self.retention(route)),
        ]
        for (listing, retention) in cases {
            let transport = Recording([Self.ok(listing), Self.ok(retention)])
            eq(await ConfirmEnrichmentRouteChecker(egress: PermittingOpenRouterEgress(), transport: transport)
                            .check(.details, catalogueUse: .confirmEnrichmentDetailsCatalogueCheck), .unavailable, listing.prefix(80).description)
        }
        let notFound = Recording([Self.ok("{}", status: 404)])
        eq(await ConfirmEnrichmentRouteChecker(egress: PermittingOpenRouterEgress(), transport: notFound)
                        .check(.details, catalogueUse: .confirmEnrichmentDetailsCatalogueCheck), .unavailable)
        let wrongUse = Recording([Self.ok(try Self.listing(route))])
        eq(await ConfirmEnrichmentRouteChecker(egress: PermittingOpenRouterEgress(), transport: wrongUse)
                        .check(.details, catalogueUse: .labelPhotoCatalogueCheck), .unavailable)
        XCTAssertTrue(wrongUse.requests.isEmpty, "another feature's catalogue use is never borrowed")
    }

    func testReasoningPricedSeparatelyIsAdmittedOnlyWhereWIncludesIt() throws {
        let nutrients = ConfirmEnrichmentRoutes.nutrients
        XCTAssertTrue(nutrients.reasoningBilledSeparately)
        XCTAssertNotNil(ConfirmEnrichmentRouteChecker.parse(listing: Data(try Self.listing(nutrients, extra: ["internal_reasoning": "0.0000008"]).utf8),
                                                            zeroDataRetention: Data(try Self.retention(nutrients).utf8), route: nutrients))
        XCTAssertNil(ConfirmEnrichmentRouteChecker.parse(listing: Data(try Self.listing(nutrients, extra: ["internal_reasoning": "0.000001"]).utf8),
                                                         zeroDataRetention: Data(try Self.retention(nutrients).utf8), route: nutrients),
                     "never above the completion rate")
    }

    func testWithTheDaysPricesAboveTheCapThePartCannotRun() throws {
        let expensive = ConfirmEnrichmentPrices(promptPerTokenUSD: Decimal(string: "0.00001")!, completionPerTokenUSD: Decimal(string: "0.00001")!)
        XCTAssertFalse(ConfirmEnrichmentSpendPolicy.routeFits(ConfirmEnrichmentRoutes.details, prices: expensive))
        XCTAssertFalse(ConfirmEnrichmentSpendPolicy.routeFits(ConfirmEnrichmentRoutes.nutrients, prices: expensive))
        // The response-limit fallback when `max_tokens` is not accepted: A's completion ceiling becomes
        // the 50,000-byte response limit counted as tokens, which no plausible price fits under $0.01.
        let base = ConfirmEnrichmentRoutes.details
        let fallback = ConfirmEnrichmentRoute(
            part: .details, version: base.version, model: base.model, acceptedModels: base.acceptedModels, provider: base.provider,
            providerEndpoint: base.providerEndpoint, endpoint: base.endpoint, promptCeilingTokens: base.promptCeilingTokens,
            completionCeilingTokens: ConfirmEnrichmentVersions.detailsResponseByteLimit, reasoningLimitTokens: 0,
            reasoningBilledSeparately: false, sendsMaxTokens: false)
        XCTAssertFalse(ConfirmEnrichmentSpendPolicy.routeFits(fallback, prices: ConfirmEnrichmentTestRouteChecker.cheap))
    }
}
