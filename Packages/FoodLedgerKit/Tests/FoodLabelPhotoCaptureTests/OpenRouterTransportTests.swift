@testable import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
import XCTest

/// The live transport's obligations (docs/label-photo-ai-prefill-v1.md 17.18), against a stub
/// URLProtocol installed on its own configuration: nothing here reaches the network.
final class OpenRouterTransportTests: XCTestCase {
    final class Stub: URLProtocol {
        enum Reply { case ok(Int, Data, [String: String]), redirect, fail(URLError.Code), never }
        nonisolated(unsafe) static var reply: Reply = .ok(200, Data(), [:])
        nonisolated(unsafe) static var seen: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            var recorded = request
            if let stream = request.httpBodyStream {
                stream.open(); var data = Data(); var buffer = [UInt8](repeating: 0, count: 4_096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
                stream.close(); recorded.httpBody = data
            }
            Self.seen.append(recorded)
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
            case let .fail(code):
                client?.urlProtocol(self, didFailWithError: URLError(code))
            case .never:
                break
            }
        }

        override func stopLoading() {}
    }

    override func setUp() { Stub.reply = .ok(200, Data(), [:]); Stub.seen = [] }

    func transport() -> OpenRouterTransport { OpenRouterTransport { $0.protocolClasses = [Stub.self] } }

    let post = LabelPhotoHTTPRequest(method: "POST", url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                                     headers: ["Authorization": "Bearer test-key", "Content-Type": "application/json"], body: Data("{}".utf8))
    let get = LabelPhotoHTTPRequest(method: "GET", url: URL(string: "https://openrouter.ai/api/v1/endpoints/zdr")!,
                                    headers: ["Accept": "application/json"], body: nil)

    func testHeadersAreFixedAndNeutralAndTheGetIsAnonymous() async throws {
        Stub.reply = .ok(200, Data("{}".utf8), ["Set-Cookie": "id=1"])
        _ = try await transport().send(post, timeout: 5, maximumBodyBytes: 1_000)
        _ = try await transport().send(get, timeout: 5, maximumBodyBytes: 1_000)
        XCTAssertEqual(Stub.seen.count, 2)
        for request in Stub.seen {
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), OpenRouterTransport.userAgent)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "*", "never the device's languages")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"), "no cookie is stored or sent")
        }
        XCTAssertEqual(Stub.seen[0].value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(Stub.seen[0].httpBody, Data("{}".utf8))
        XCTAssertNil(Stub.seen[1].value(forHTTPHeaderField: "Authorization"), "the catalogue GET carries no key")
        XCTAssertNil(Stub.seen[1].httpBody)
    }

    func testARedirectIsRefused() async {
        Stub.reply = .redirect
        do {
            _ = try await transport().send(post, timeout: 5, maximumBodyBytes: 1_000)
            XCTFail("a redirect is never followed or answered")
        } catch {
            XCTAssertEqual(error as? LabelPhotoTransportError, .failed)
        }
        XCTAssertFalse(Stub.seen.contains { $0.url?.host == "elsewhere.example" })
    }

    func testTheReplyStopsAtTheByteCap() async throws {
        Stub.reply = .ok(200, Data(repeating: 0x41, count: 5_000), [:])
        let capped = try await transport().send(post, timeout: 5, maximumBodyBytes: 1_000)
        XCTAssertTrue(capped.exceededLimit)
        XCTAssertEqual(capped.body.count, 1_000)
        Stub.reply = .ok(200, Data(repeating: 0x41, count: 1_000), ["Retry-After": "3"])
        let exact = try await transport().send(post, timeout: 5, maximumBodyBytes: 1_000)
        XCTAssertFalse(exact.exceededLimit)
        XCTAssertEqual(exact.header("retry-after"), "3")
    }

    func testTheWholeRequestEndsAtTheTimeout() async {
        Stub.reply = .never
        let started = Date()
        do {
            _ = try await transport().send(post, timeout: 0.3, maximumBodyBytes: 1_000)
            XCTFail("no reply")
        } catch {
            XCTAssertEqual(error as? LabelPhotoTransportError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testCancellationIsOnlyTaskCancellationAndOfflineIsMapped() async {
        Stub.reply = .never
        let transport = transport()
        let request = post
        let task = Task { try await transport.send(request, timeout: 10, maximumBodyBytes: 1_000) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled") } catch {
            XCTAssertEqual(error as? LabelPhotoTransportError, .cancelled)
        }
        Stub.reply = .fail(.notConnectedToInternet)
        do { _ = try await self.transport().send(post, timeout: 5, maximumBodyBytes: 1_000); XCTFail("offline") } catch {
            XCTAssertEqual(error as? LabelPhotoTransportError, .offline)
        }
        Stub.reply = .fail(.badServerResponse)
        do { _ = try await self.transport().send(post, timeout: 5, maximumBodyBytes: 1_000); XCTFail("failed") } catch {
            XCTAssertEqual(error as? LabelPhotoTransportError, .failed)
        }
    }

    func testACatalogueTransportFailureIsNotTheRoutesFault() async {
        Stub.reply = .fail(.notConnectedToInternet)
        let checker = OpenRouterLabelRouteChecker(transport: transport(), clock: ScriptedLabelPhotoRouteTests.FixedClock())
        do { _ = try await checker.check(LabelPhotoRoute.v1); XCTFail("offline") } catch {
            XCTAssertEqual(error as? LabelPhotoRouteCheckFailure, .transport(.offline))
        }
        Stub.reply = .ok(500, Data(), [:])
        do { _ = try await checker.check(LabelPhotoRoute.v1); XCTFail("unavailable") } catch {
            XCTAssertNil(error as? LabelPhotoRouteCheckFailure, "an HTTP error is the route's: kept for the day")
        }
    }
}
