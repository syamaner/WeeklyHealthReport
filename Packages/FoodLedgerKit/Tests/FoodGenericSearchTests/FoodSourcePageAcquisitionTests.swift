import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

final class FoodSourcePageAcquisitionTests: XCTestCase {
    private let url = URL(string: "https://source.example.com/food")!
    private func service(_ clock: SourceClock = SourceClock(), timeout: Duration = .seconds(20),
                         pause: (@Sendable (TimeInterval) async throws -> Void)? = nil) throws -> HTTPSFoodSourcePageAcquirer {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "never-send", "x-goog-api-key": "never-send", "Cookie": "never-send"]
        return try HTTPSFoodSourcePageAcquirer(allowedHosts: ["source.example.com", "redirect.example.com"], userAgent: "Synthetic/1",
            clock: clock, configuration: configuration, timeout: timeout, pause: pause ?? { clock.advance($0) })
    }

    func testDirectUTF8ContentHasExactHashTimestampAndNoCredentials() async throws {
        let body = Data("<table>é &amp; nutrition</table>".utf8)
        SourceProtocol.store.reset([SourceReply(body: body)])
        let clock = SourceClock(); let client = try service(clock)
        let original = URL(string: url.absoluteString + "#nutrition")!
        let result = try await client.acquire(original)
        XCTAssertEqual(result.html, body); XCTAssertEqual(result.requestedURL, original); XCTAssertEqual(result.finalURL, url)
        XCTAssertEqual(result.sha256, "910826133a601f131d1ecf4e3aceca54c2852d39aa95e139b96d8c4cdb364541")
        XCTAssertEqual(result.retrievedAt, clock.now()); XCTAssertEqual(result.hops, [.init(url: url, status: 200)])
        let request = try XCTUnwrap(SourceProtocol.store.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        for header in ["Authorization", "x-goog-api-key", "Cookie"] { XCTAssertNil(request.value(forHTTPHeaderField: header)) }
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/html")
        do { _ = try await client.acquire(url); XCTFail() }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .quotaExceeded) }
        XCTAssertEqual(SourceProtocol.store.requests.count, 1)
    }

    func testTwoAdmittedRedirectsArePacedAndKeepChain() async throws {
        SourceProtocol.store.reset([.init(status: 302, headers: ["Location": "/step"]),
            .init(status: 307, headers: ["Location": "https://redirect.example.com/final"]), .init()])
        let clock = SourceClock(); let result = try await service(clock).acquire(url)
        XCTAssertEqual(result.hops.map(\.status), [302, 307, 200])
        XCTAssertEqual(result.finalURL.absoluteString, "https://redirect.example.com/final")
        XCTAssertEqual(SourceProtocol.store.requests.count, 3); XCTAssertEqual(clock.elapsed, 14, accuracy: 0.01)
    }

    func testEachRedirectDestinationRequiresExactHostAndSafeURL() async throws {
        for location in ["https://other.example.com/", "https://source.example.com.evil.com/", "http://source.example.com/",
                         "https://user:pass@source.example.com/", "https://source.example.com:8443/", "https://127.0.0.1/", "https://[::1]/"] {
            SourceProtocol.store.reset([.init(status: 302, headers: ["Location": location])])
            do { _ = try await service().acquire(url); XCTFail(location) } catch { }
            XCTAssertEqual(SourceProtocol.store.requests.count, 1, location)
        }
    }

    func testUnsafeInitialURLsNeverMakeRequestsAndHostConfigCannotAdmitLiteralLocalAddresses() async throws {
        for raw in ["http://source.example.com/", "https://localhost/", "https://127.0.0.1/", "https://[::1]/",
                    "https://source.example.com:8080/", "https://user@source.example.com/", "https://unlisted.example.com/"] {
            SourceProtocol.store.reset([])
            do { _ = try await service().acquire(try XCTUnwrap(URL(string: raw))); XCTFail(raw) } catch { }
            XCTAssertTrue(SourceProtocol.store.requests.isEmpty, raw)
        }
        for host in ["localhost", "127.0.0.1", "::1", "a.local", "*.example.com", ".example.com", "example.com.", "a.internal"] {
            XCTAssertThrowsError(try HTTPSFoodSourcePageAcquirer(allowedHosts: [host], userAgent: "Synthetic/1"))
        }
    }

    func testRedirectLoopLimitAndMissingLocationNeverRetry() async throws {
        for replies in [[SourceReply(status: 302, headers: ["Location": "/food"])],
                        [SourceReply(status: 302)],
                        [.init(status: 302, headers: ["Location": "/one"]), .init(status: 302, headers: ["Location": "/two"]), .init(status: 302, headers: ["Location": "/three"])]] {
            SourceProtocol.store.reset(replies)
            do { _ = try await service().acquire(url); XCTFail() } catch { }
            XCTAssertEqual(SourceProtocol.store.requests.count, replies.count)
        }
    }

    func testHTTPFailuresConsumeAttemptAndDoNotRetry() async throws {
        for status in [401, 403, 404, 429, 500, 503] {
            SourceProtocol.store.reset([.init(status: status)])
            let client = try service()
            do { _ = try await client.acquire(url); XCTFail() }
            catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .unavailable) }
            do { _ = try await client.acquire(url); XCTFail() }
            catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .quotaExceeded) }
            XCTAssertEqual(SourceProtocol.store.requests.count, 1)
        }
    }

    func testContentTypeEncodingEmptyAndOversizeRepliesAreRejected() async throws {
        for reply in [SourceReply(headers: ["Content-Type": "application/json"]),
                      .init(headers: ["Content-Type": "text/html; charset=iso-8859-1"]),
                      .init(body: Data([255])), .init(body: Data()),
                      .init(body: Data(repeating: 120, count: 2_000_001)),
                      .init(headers: ["Content-Type": "text/html", "Content-Length": "2000001"])] {
            SourceProtocol.store.reset([reply])
            do { _ = try await service().acquire(url); XCTFail() } catch { }
            XCTAssertEqual(SourceProtocol.store.requests.count, 1)
        }
    }

    func testRawHTMLAboveProjectionLimitIsStillBoundedAndAcquired() async throws {
        let body = Data(("<script>" + String(repeating: "x", count: 1_500_000) + "</script><table></table>").utf8)
        XCTAssertGreaterThan(body.count, FoodSourceDocumentDecoder.maximumBytes)
        SourceProtocol.store.reset([.init(body: body)])
        let page = try await service().acquire(url)
        XCTAssertEqual(page.html, body)
        XCTAssertEqual(HTTPSFoodSourcePageAcquirer.maximumBytes, 2_000_000)
        XCTAssertEqual(SourceProtocol.store.requests.count, 1)
    }

    func testCancellationDuringPacingRejectsConcurrentWorkAndLateContent() async throws {
        SourceProtocol.store.reset([.init(status: 302, headers: ["Location": "/next"])])
        let waiting = expectation(description: "pacing")
        let clock = SourceClock()
        let client = try service(clock, pause: { _ in waiting.fulfill(); try await Task.sleep(for: .seconds(10)) })
        let task = Task { [url] in try await client.acquire(url) }
        await fulfillment(of: [waiting], timeout: 2); clock.advance(8)
        do { _ = try await client.acquire(url); XCTFail() }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .quotaExceeded) }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(SourceProtocol.store.requests.count, 1)
    }

    func testCancellationDuringHTTPDoesNotPublishContent() async throws {
        let started = expectation(description: "request")
        SourceProtocol.store.reset([.init(hold: true)], onRequest: { started.fulfill() })
        let client = try service(); let task = Task { [url] in try await client.acquire(url) }
        await fulfillment(of: [started], timeout: 2); task.cancel()
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(SourceProtocol.store.requests.count, 1)
    }

    func testOversizeInitialAndRedirectURLsNeverReachTheirDestination() async throws {
        let longURL = "https://source.example.com/" + String(repeating: "a", count: 4096)
        SourceProtocol.store.reset([])
        do { _ = try await service().acquire(URL(string: longURL)!); XCTFail() }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .invalidURL) }
        XCTAssertTrue(SourceProtocol.store.requests.isEmpty)
        SourceProtocol.store.reset([.init(status: 302, headers: ["Location": longURL])])
        do { _ = try await service().acquire(url); XCTFail() }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .invalidURL) }
        XCTAssertEqual(SourceProtocol.store.requests.count, 1)
    }

    func testFetchedHTMLProjectsAndBindsAsOneSourceWithoutModelNumbers() async throws {
        let html = "<table><tr><th>Typical values</th><td>per 100 ml</td></tr>"
            + "<tr><th>Energy</th><td>175 kJ / 42 kcal</td></tr>"
            + "<tr><th>Fat<br>Saturates</th><td>1.9 g<br>0.3 g</td></tr>"
            + "<tr><th>Carbohydrate<br>Sugars</th><td>2.7 g<br>2.5 g</td></tr>"
            + "<tr><th>Protein</th><td>3.3 g</td></tr></table>"
        SourceProtocol.store.reset([.init(body: Data(html.utf8))])
        let page = try await service().acquire(url)
        let projected = try HTMLFoodSourceTableProjector.project(page.html)
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: projected) as? [String: Any])
        XCTAssertEqual(metadata["html_sha256"] as? String, page.sha256)
        let panels = try FoodSourceDocumentPanelReader.panels(projected, documentID: page.finalURL.absoluteString, recordID: "selected-source")
        XCTAssertEqual(panels.count, 1); XCTAssertTrue(panels[0].hasFourMacros)
        XCTAssertEqual(panels[0].declarations.map(\.value.amount), [42, 1.9, 2.7, 3.3])
        XCTAssertTrue(panels[0].declarations.allSatisfy { $0.value.basis == .per100Millilitres })
        XCTAssertEqual(SourceProtocol.store.requests.count, 1)
    }

    func testWholeDeadlineIncludesRedirectPacing() async throws {
        SourceProtocol.store.reset([.init(status: 302, headers: ["Location": "/next"])])
        let client = try service(timeout: .milliseconds(60), pause: { _ in try await Task.sleep(for: .seconds(10)) })
        do { _ = try await client.acquire(url); XCTFail() }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .timedOut) }
        XCTAssertEqual(SourceProtocol.store.requests.count, 1)
    }
}

private struct SourceReply: Sendable {
    var status = 200
    var headers = ["Content-Type": "text/html; charset=utf-8"]
    var body = Data("<html><body>Source</body></html>".utf8)
    var hold = false
}
private final class SourceClock: LedgerClock, @unchecked Sendable {
    private let lock = NSLock(); private var interval: TimeInterval = 0
    var elapsed: TimeInterval { lock.withLock { interval } }
    func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000 + elapsed) }
    func advance(_ seconds: TimeInterval) { lock.withLock { interval += seconds } }
}
private final class SourceStore: @unchecked Sendable {
    private let lock = NSLock(); private var pending: [SourceReply] = []; private var history: [URLRequest] = []
    private var callback: (@Sendable () -> Void)?
    var requests: [URLRequest] { lock.withLock { history } }
    func reset(_ replies: [SourceReply], onRequest: (@Sendable () -> Void)? = nil) {
        lock.withLock { pending = replies; history = []; callback = onRequest }
    }
    func receive(_ request: URLRequest) -> SourceReply {
        let (reply, callback) = lock.withLock { () -> (SourceReply, (@Sendable () -> Void)?) in
            history.append(request); return (pending.isEmpty ? SourceReply(status: 500) : pending.removeFirst(), self.callback)
        }
        callback?(); return reply
    }
}
private final class SourceProtocol: URLProtocol, @unchecked Sendable {
    static let store = SourceStore()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.store.receive(request)
        guard !reply.hold else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
