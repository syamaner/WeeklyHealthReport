import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodGenericSearch
import XCTest

@MainActor
final class PublicFoodSourceCaptureTests: XCTestCase {
    func testOptInAuditRetainsUnauthenticatedBodyBeforeProjectionFailure() async {
        let observed = expectation(description: "Unauthenticated body observed")
        let capture = PublicFoodSourceCapture(resolve: { _ in ["8.8.8.8"] }, fetch: { _, _ in
            Self.reply(body: "<script>unreadableSite()</script>")
        }, now: Date.init, observe: { observation in
            observed.fulfill()
            XCTAssertEqual(observation.status, 200)
            XCTAssertEqual(observation.url.absoluteString, "https://publisher.example/food")
            XCTAssertEqual(observation.body, Data("<script>unreadableSite()</script>".utf8))
        })
        do { _ = try await capture.capture(URL(string: "https://publisher.example/food")!); XCTFail("No readable blocks") }
        catch { XCTAssertEqual(error as? FoodLedgerDomain.GenericFoodProposalError, .invalidDocument) }
        await fulfillment(of: [observed], timeout: 1)
    }
    func testPublicAddressPolicyRejectsLocalReservedAndAlternativeNumericForms() {
        for address in ["127.0.0.1", "10.1.2.3", "192.168.1.1", "172.16.0.1", "172.31.255.255", "169.254.169.254",
                        "0.0.0.0", "100.64.0.1", "100.127.1.1", "192.0.0.1", "192.0.2.1", "192.88.99.1",
                        "198.18.0.1", "198.19.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255",
                        "2130706433", "0177.0.0.1", "127.1", "::1", "::ffff:127.0.0.1", "8.8.8.999"] {
            XCTAssertFalse(PublicFoodSourceCapture.isPublicIPv4(address), address)
        }
        for address in ["8.8.8.8", "1.1.1.1", "172.32.0.1", "100.128.0.1"] { XCTAssertTrue(PublicFoodSourceCapture.isPublicIPv4(address)) }
    }

    func testURLPolicyRejectsCredentialsPortsAndLocalNames() throws {
        for text in ["http://publisher.example/food", "https://user:pass@publisher.example/food", "https://publisher.example:444/food",
                     "https://127.0.0.1/food", "https://2130706433/food", "https://[::1]/food", "https://host.local/food", "https://host.home.arpa/food",
                     "https://host.internal/food", "https://localhost/food", "https://foo..example/food"] {
            XCTAssertThrowsError(try PublicFoodSourceCapture.canonicalURL(XCTUnwrap(URL(string: text))), text)
        }
        XCTAssertEqual(try PublicFoodSourceCapture.canonicalURL(URL(string: "https://PUBLISHER.example/food#part")!).absoluteString, "https://publisher.example/food")
    }

    func testCapturePinsResolvedAddressAndKeepsNoProviderCredentialCapability() async throws {
        let recorder = Calls()
        let capture = PublicFoodSourceCapture(resolve: { host in
            await recorder.append("resolve:" + host); return ["8.8.8.8"]
        }, fetch: { url, address in
            await recorder.append("fetch:" + url.absoluteString + ":" + address)
            return Self.reply(body: "<h1>Food</h1><p>Per100g: 100kcal</p>")
        }, now: { Date(timeIntervalSince1970: 0) })
        let document = try await capture.capture(URL(string: "https://publisher.example/food")!)
        XCTAssertEqual(document.captureOrigin, "publisher_http")
        XCTAssertEqual(document.blocks.count, 2)
        let calls = await recorder.values
        XCTAssertEqual(calls, ["resolve:publisher.example", "fetch:https://publisher.example/food:8.8.8.8"])
    }

    func testMixedDNSAnswersFailBeforeAnyConnection() async {
        let capture = PublicFoodSourceCapture(resolve: { _ in ["8.8.8.8", "127.0.0.1"] }, fetch: { _, _ in
            XCTFail("Private DNS answer must prevent fetch"); return Data()
        }, now: Date.init)
        do { _ = try await capture.capture(URL(string: "https://publisher.example/food")!); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .hostNotAdmitted) }
    }

    func testRedirectRevalidatesDestinationBeforeConnection() async {
        let capture = PublicFoodSourceCapture(resolve: { host in host == "publisher.example" ? ["8.8.8.8"] : ["192.168.1.1"] }, fetch: { url, _ in
            XCTAssertEqual(url.host, "publisher.example")
            return Data("HTTP/1.1 302 Found\r\nLocation: https://private.example/food\r\nContent-Length: 0\r\n\r\n".utf8)
        }, now: Date.init)
        do { _ = try await capture.capture(URL(string: "https://publisher.example/food")!); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .hostNotAdmitted) }
    }

    func testThreeAttemptLimitHasNoAutomaticRetry() async {
        let calls = Calls()
        let capture = PublicFoodSourceCapture(resolve: { _ in ["8.8.8.8"] }, fetch: { url, _ in
            await calls.append(url.absoluteString)
            return Data(("HTTP/1.1 302 Found\r\nLocation: " + url.path + "x\r\nContent-Length: 0\r\n\r\n").utf8)
        }, now: Date.init)
        do { _ = try await capture.capture(URL(string: "https://publisher.example/food")!); XCTFail("Expected limit") }
        catch { XCTAssertEqual(error as? FoodSourceAcquisitionError, .requestLimit) }
        let count = await calls.values.count; XCTAssertEqual(count, 3)
    }

    func testHTTPFramingAndChunkedDecoding() throws {
        let plain = try FoodSourceHTTPReply.decode(Self.reply(body: "豆花"))
        XCTAssertEqual(String(decoding: plain.body, as: UTF8.self), "豆花")
        let chunked = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/plain\r\n\r\n4\r\nFood\r\n3;test=x\r\n123\r\n0\r\n\r\n".utf8)
        XCTAssertEqual(try FoodSourceHTTPReply.decode(chunked).body, Data("Food123".utf8))
    }

    func testWireBodyLimitAdmitsLargerPagesButNeverTruncatesOverLimit() throws {
        let accepted = String(repeating: "x", count: GenericFoodDocumentProjector.maximumBytes)
        XCTAssertEqual(try FoodSourceHTTPReply.decode(Self.reply(body: accepted)).body.count,
                       GenericFoodDocumentProjector.maximumBytes)
        XCTAssertThrowsError(try FoodSourceHTTPReply.decode(Self.reply(body: accepted + "x"))) {
            XCTAssertEqual($0 as? FoodSourceAcquisitionError, .responseTooLarge)
        }
    }

    func testAmbiguousOrTruncatedHTTPRepliesAreRejected() {
        let replies = [
            "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nContent-Length: 5\r\n\r\nFood",
            "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nFood",
            "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\nFood",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nFood\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n-4\r\nFood\r\n0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nContent-Type: other\r\n\r\n",
            "HTTP/1.1 200 OK\r\n folded: header\r\n\r\nFood",
            "HTTP/2 200\r\n\r\nFood"
        ]
        for reply in replies { XCTAssertThrowsError(try FoodSourceHTTPReply.decode(Data(reply.utf8)), reply) }
    }

    func testCookiesAreIgnoredButDuplicateContentInterpretationIsRejected() throws {
        XCTAssertNoThrow(try FoodSourceHTTPReply.decode(Data("HTTP/1.1 200 OK\r\nSet-Cookie: a=b\r\nSet-Cookie: c=d\r\n\r\nFood".utf8)))
        XCTAssertThrowsError(try FoodSourceHTTPReply.decode(Data("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Type: text/plain\r\n\r\nFood".utf8)))
    }

    nonisolated private static func reply(body: String) -> Data {
        Data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)
    }
    private actor Calls {
        var values: [String] = []
        func append(_ value: String) { values.append(value) }
    }
}
