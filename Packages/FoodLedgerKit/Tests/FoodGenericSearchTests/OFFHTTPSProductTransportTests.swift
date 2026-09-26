import Foundation
import FoodGenericSearch
import FoodLedgerApplication

import FoodLedgerDomain
import XCTest

final class OFFHTTPSProductTransportTests: XCTestCase {
    private func transport(clock: OFFTransportClock) -> OFFHTTPSProductTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OFFTestProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "must-be-cleared", "Cookie": "must-be-cleared"]
        return OFFHTTPSProductTransport(userAgent: "SyntheticOFFTests/1 (public@example.invalid)", clock: clock, configuration: configuration)
    }

    func testBarcodeOnlyGETPrivacyCooldownAndNoRetries() async throws {
        OFFTestProtocol.store.reset(status: 200, body: Data("{}".utf8))
        let clock = OFFTransportClock()
        let transport = transport(clock: clock)
        let result = try await transport.product(code: "3274080005003")
        XCTAssertEqual(result.status, 200)
        do { _ = try await transport.product(code: "3274080005003"); XCTFail("Expected cooldown") }
        catch { XCTAssertEqual(error as? OFFLookupError, .rateLimited) }
        let requests = OFFTestProtocol.store.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://world.openfoodfacts.org/api/v3.6/product/3274080005003.json")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "SyntheticOFFTests/1 (public@example.invalid)")
        clock.advance(13)
        OFFTestProtocol.store.change(status: 503, body: Data())
        let unavailable = try await transport.product(code: "3274080005003")
        XCTAssertEqual(unavailable.status, 503)
        XCTAssertEqual(OFFTestProtocol.store.requests.count, 2)
    }

    func testStreamingSizeLimitAndTimeoutPropagateWithoutRetry() async throws {
        OFFTestProtocol.store.reset(status: 200, body: Data(repeating: 0, count: 500_001))
        let clock = OFFTransportClock()
        let transport = transport(clock: clock)
        do { _ = try await transport.product(code: "3274080005003"); XCTFail("Expected size rejection") }
        catch { XCTAssertEqual(error as? OFFLookupError, .oversizedResponse) }
        XCTAssertEqual(OFFTestProtocol.store.requests.count, 1)
        clock.advance(13)
        OFFTestProtocol.store.change(status: 200, body: Data(), error: URLError(.timedOut))
        do { _ = try await transport.product(code: "3274080005003"); XCTFail("Expected timeout") }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertEqual(OFFTestProtocol.store.requests.count, 2)
    }
}

private final class OFFTransportClock: LedgerClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: Double) { lock.withLock { date.addTimeInterval(seconds) } }
}
private final class OFFProtocolStore: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var body = Data()
    private var error: URLError?
    private var history: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { history } }
    func reset(status: Int, body: Data) { lock.withLock { self.status = status; self.body = body; error = nil; history = [] } }
    func change(status: Int, body: Data, error: URLError? = nil) { lock.withLock { self.status = status; self.body = body; self.error = error } }
    func receive(_ request: URLRequest) -> (Int, Data, URLError?) { lock.withLock { history.append(request); return (status, body, error) } }
}
private final class OFFTestProtocol: URLProtocol, @unchecked Sendable {
    static let store = OFFProtocolStore()
    override class func canInit(with request: URLRequest) -> Bool { true } // Never access the network in these tests.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body, error) = Self.store.receive(request)
        if let error { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
