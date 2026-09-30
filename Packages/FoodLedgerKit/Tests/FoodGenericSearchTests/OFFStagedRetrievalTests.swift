import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

final class OFFStagedRetrievalTests: XCTestCase {
    private let first = "3274080005003"
    private let second = "5000354801020"
    private func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private func discovery(_ codes: [String]) throws -> Reply {
        try Reply(body: json(["timed_out": false, "hits": codes.map { ["code": $0, "nutriments": ["energy-kcal_100g": 999]] }]))
    }
    private func product(_ code: String) throws -> Reply {
        try Reply(body: json(["status": "success", "product": ["code": code, "product_name": "Synthetic yoghurt"]]))
    }
    private func transport(_ clock: StageClock, timeout: Duration = .seconds(20),
                           pause: (@Sendable (TimeInterval) async throws -> Void)? = nil) -> OFFHTTPSearchTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StagedProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "never-send", "Cookie": "never-send"]
        return OFFHTTPSearchTransport(userAgent: "Synthetic/1 (nobody@example.invalid)", clock: clock,
            configuration: configuration, timeout: timeout, pause: pause ?? { seconds in clock.advance(seconds) })
    }
    private func products(_ response: OFFProductResponse) throws -> [[String: Any]] {
        try XCTUnwrap((JSONSerialization.jsonObject(with: response.body) as? [String: Any])?["products"] as? [[String: Any]])
    }

    func testBoundedDistinctValidatedIDsAndOnlyDetailValues() async throws {
        StagedProtocol.store.reset(try [discovery(["invalid", "3274080005004", first, "03274080005003", second, "50117468"]),product(first),product(second)])
        let clock = StageClock(); let service = transport(clock)
        let answer = try await service.search(foodTerms: "yoghurt")
        let received = try products(answer)
        XCTAssertEqual(received.compactMap { $0["code"] as? String }, [first,second])
        XCTAssertTrue(received.allSatisfy { $0["nutriments"] == nil }) // Index nutrition never admitted.
        let requests = StagedProtocol.store.requests
        XCTAssertEqual(requests.count,3)
        XCTAssertEqual(requests[0].url?.host,"search.openfoodfacts.org")
        XCTAssertEqual(requests[1].url?.path,"/api/v3.6/product/\(first).json")
        XCTAssertEqual(requests[2].url?.path,"/api/v3.6/product/\(second).json")
        XCTAssertEqual(clock.elapsed,14,accuracy:0.01)
        for request in requests {
            XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"));XCTAssertNil(request.value(forHTTPHeaderField:"Cookie"))
        }
        do { _ = try await service.search(foodTerms:"yoghurt");XCTFail() }
        catch { XCTAssertEqual(error as? FoodSearchEnrichmentError,.quotaExceeded) }
        XCTAssertEqual(StagedProtocol.store.requests.count,3)
    }

    func testExplicitNamedPercentageMovesAheadOfUnknownAndWrongVariantsWithinBudget() async throws {
        let wanted = "5201054080610"
        let hits: [[String: Any]] = [
            ["code": first, "product_name": "FAGE Total Greek yoghurt"],
            ["code": second, "product_name": "FAGE Total Greek yoghurt 5%"],
            ["code": wanted, "product_name": "Total Greek yogurt 2%", "brands": ["FAGE"],
             "nutriments": ["fat_100g": 99]],
            ["code": "05201054080610", "product_name": "FAGE Total Greek yoghurt 2%"]
        ]
        StagedProtocol.store.reset(try [Reply(body: json(["timed_out": false, "hits": hits])), product(wanted), product(first)])
        let clock = StageClock()
        let answer = try await transport(clock).search(foodTerms: "FAGE Total Greek yoghurt 2%")
        XCTAssertEqual(try products(answer).compactMap { $0["code"] as? String }, [wanted, first])
        XCTAssertTrue(try products(answer).allSatisfy { $0["nutriments"] == nil })
        XCTAssertEqual(StagedProtocol.store.requests.count, 3)
        XCTAssertEqual(clock.elapsed, 14, accuracy: 0.01)
    }

    func testPercentageAlonePartialTermsAndAmbiguousNamesCannotEarnPriority() async throws {
        let later = "5201054080610"
        let cases: [(String, Any, Any)] = [
            ("FAGE Total Greek yoghurt 2%", "Other Total Greek yoghurt 2%", ["Other"]),
            ("FAGE Total Greek vanilla yoghurt 2%", "FAGE Total Greek yoghurt 2%", ["FAGE"]),
            ("FAGE Total Greek yoghurt 2%", "FAGE Total Greek yoghurt 2% less sugar", ["FAGE"]),
            ("FAGE Total Greek yoghurt 2%", "FAGE Total Greek yoghurt 2% or 5%", ["FAGE"]),
            ("FAGE Total Greek yoghurt 2%", "FAGE Total Greek yoghurt 12%", ["FAGE"]),
            ("FAGE Total Greek yoghurt 2%", ["en": "FAGE Total Greek yoghurt 2%"], ["FAGE"]),
            ("FAGE Total Greek yoghurt 2%", "Total Greek yoghurt 2%", ["nested": "FAGE"]),
            ("FAGE Total Greek yoghurt", "FAGE Total Greek yoghurt 2%", ["FAGE"])
        ]
        for (query, name, brands) in cases {
            let hits: [[String: Any]] = [["code": first], ["code": second],
                ["code": later, "product_name": name, "brands": brands]]
            StagedProtocol.store.reset(try [Reply(body: json(["timed_out": false, "hits": hits])), product(first), product(second)])
            let answer = try await transport(StageClock()).search(foodTerms: query)
            XCTAssertEqual(try products(answer).compactMap { $0["code"] as? String }, [first, second], query + " / " + String(describing: name))
        }
    }

    func testExplicitMatchTiesRetainProviderOrderAndInvalidCodesNeverConsumeDetails() async throws {
        let name = "FAGE Total Greek yoghurt 2%"
        let hits: [[String: Any]] = [["code": "invalid", "product_name": name],
            ["code": second, "product_name": name], ["code": first, "product_name": name]]
        StagedProtocol.store.reset(try [Reply(body: json(["timed_out": false, "hits": hits])), product(second), product(first)])
        let answer = try await transport(StageClock()).search(foodTerms: name)
        XCTAssertEqual(try products(answer).compactMap { $0["code"] as? String }, [second, first])
        XCTAssertEqual(StagedProtocol.store.requests.count, 3)
    }

    func testFullTextQueryRetainsFoodTermsWithoutProducingLuceneOperators() async throws {
        let cases = [
            ("Ambrosia rice pudding", "ambrosia rice pudding"),
            ("FAGE Total Greek yoghurt 2%", "fage total greek yoghurt 2%"),
            ("salt AND vinegar OR crisps NOT TO", "salt and vinegar or crisps not to"),
            (#"milk brands:other (a+b) [0 TO 9] /rice/ * ? >0 <1 "quoted""#,
             #"milk brands\:other \(a\+b\) \[0 to 9\] \/rice\/ \* \? \>0 \<1 \"quoted\""#),
            ("Crème fraîche", "crème fraîche")
        ]
        for (input, expected) in cases {
            StagedProtocol.store.reset(try [discovery([])])
            _ = try await transport(StageClock()).search(foodTerms: input)
            let request = try XCTUnwrap(StagedProtocol.store.requests.first)
            let data = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["q"] as? String, expected, input)
            XCTAssertEqual(StagedProtocol.store.requests.count, 1)
        }
    }

    func testEmptyOrInvalidDiscoveryNeverFetchesDetails() async throws {
        for codes in [[],["abc","3274080005004","13274080005000"]] {
            StagedProtocol.store.reset(try [discovery(codes)])
            let answer = try await transport(StageClock()).search(foodTerms:"milk")
            XCTAssertTrue(try products(answer).isEmpty);XCTAssertEqual(StagedProtocol.store.requests.count,1)
        }
    }

    func testOneIDUsesOneDetailAndNormalisedIdentityIsAllowed() async throws {
        StagedProtocol.store.reset(try [discovery([first]),product("03274080005003")])
        let answer = try await transport(StageClock()).search(foodTerms:"yoghurt")
        XCTAssertEqual(try products(answer).count,1);XCTAssertEqual(StagedProtocol.store.requests.count,2)
    }

    func testSearchErrorsTimeoutAndOversizeStopBeforeDetails() async throws {
        let invalid: [Any] = [["timed_out": true, "hits": [["code": first]]],
            ["timed_out": 0, "hits": []], ["hits": []], ["timed_out": false, "errors": ["failed"], "hits": []],
            ["timed_out": false, "hits": Array(repeating:["code":first], count:11)]]
        for body in invalid {
            StagedProtocol.store.reset([try Reply(body:json(body))])
            do { _ = try await transport(StageClock()).search(foodTerms:"milk");XCTFail() }
            catch { XCTAssertEqual(error as? FoodSearchEnrichmentError,.invalidResponse) }
            XCTAssertEqual(StagedProtocol.store.requests.count,1)
        }
        StagedProtocol.store.reset([Reply(body:Data(repeating:0,count:500_001))])
        do { _ = try await transport(StageClock()).search(foodTerms:"milk");XCTFail() }
        catch { XCTAssertEqual(error as? FoodSearchEnrichmentError,.invalidResponse) }
    }

    func testWrongDetailIdentityAndUnrecognised404RejectStage() async throws {
        for bad in [try product(second), Reply(status:404,body:Data("{}".utf8))] {
            StagedProtocol.store.reset(try [discovery([first,second]),bad])
            do { _ = try await transport(StageClock()).search(foodTerms:"milk");XCTFail() }
            catch { XCTAssertEqual(error as? FoodSearchEnrichmentError,.invalidResponse) }
            XCTAssertEqual(StagedProtocol.store.requests.count,2)
        }
    }

    func testExactNotFoundConsumesSlotWithoutReplacementOrRetry() async throws {
        let missing = try Reply(status:404,body:json(["status":"failure","result":["id":"product_not_found"]]))
        StagedProtocol.store.reset(try [discovery([first,second,"50117468"]),missing,product(second)])
        let answer = try await transport(StageClock()).search(foodTerms:"milk")
        XCTAssertEqual(try products(answer).compactMap { $0["code"] as? String },[second]);XCTAssertEqual(StagedProtocol.store.requests.count,3)
    }

    func testServiceFailureStopsRemainingReads() async throws {
        for status in [429,503] {
            StagedProtocol.store.reset(try [discovery([first,second]),Reply(status:status,body:Data())])
            let answer = try await transport(StageClock()).search(foodTerms:"milk")
            XCTAssertEqual(answer.status,status);XCTAssertEqual(StagedProtocol.store.requests.count,2)
        }
    }

    func testCancellationDuringPacingStopsDetailAndRejectsConcurrentQuery() async throws {
        StagedProtocol.store.reset(try [discovery([first,second])])
        let started = expectation(description:"waiting to fetch detail")
        let clock = StageClock()
        let service = transport(clock,pause:{ _ in started.fulfill();try await Task.sleep(for:.seconds(10)) })
        let task = Task { try await service.search(foodTerms:"milk") }
        await fulfillment(of:[started],timeout:2)
        clock.advance(8)
        do { _ = try await service.search(foodTerms:"yoghurt");XCTFail() }
        catch { XCTAssertEqual(error as? FoodSearchEnrichmentError,.quotaExceeded) }
        task.cancel()
        do { _ = try await task.value;XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(StagedProtocol.store.requests.count,1)
    }

    func testTotalDeadlineIncludesPacing() async throws {
        StagedProtocol.store.reset(try [discovery([first,second])])
        let service = transport(StageClock(),timeout:.milliseconds(60),pause:{ _ in try await Task.sleep(for:.seconds(10)) })
        do { _ = try await service.search(foodTerms:"milk");XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code,.timedOut) }
        XCTAssertEqual(StagedProtocol.store.requests.count,1)
    }

    func testCancellationDuringHTTPReleasesRequestAndNoDetailPublishes() async throws {
        let started = expectation(description:"HTTP started")
        StagedProtocol.store.reset([Reply(hold:true)],onRequest:{ started.fulfill() })
        let service = transport(StageClock())
        let task = Task { try await service.search(foodTerms:"milk") }
        await fulfillment(of:[started],timeout:2);task.cancel()
        do { _ = try await task.value;XCTFail() } catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(StagedProtocol.store.requests.count,1)
    }

    func testRedirectStatusIsNotFollowedOrTreatedAsDiscovery() async throws {
        StagedProtocol.store.reset([Reply(status:302,body:Data())])
        let answer = try await transport(StageClock()).search(foodTerms:"milk")
        XCTAssertEqual(answer.status,302);XCTAssertEqual(StagedProtocol.store.requests.count,1)
    }

    func testTotalEnvelopeRemainsBoundedEvenForTwoIndividuallyValidReplies() async throws {
        func large(_ code:String) throws -> Reply {
            try Reply(body:json(["status":"success","product":["code":code,"extra":String(repeating:"a",count:270_000)]]))
        }
        StagedProtocol.store.reset(try [discovery([first,second]),large(first),large(second)])
        do { _ = try await transport(StageClock()).search(foodTerms:"milk");XCTFail() }
        catch { XCTAssertEqual(error as? FoodSearchEnrichmentError,.invalidResponse) }
        XCTAssertEqual(StagedProtocol.store.requests.count,3)
    }

    func testLuceneSyntaxIsEscapedAndBooleanWordsAreLowercased() async throws {
        StagedProtocol.store.reset(try [discovery([])])
        _ = try await transport(StageClock()).search(foodTerms:"milk OR brands:other *")
        let data = try XCTUnwrap(StagedProtocol.store.requests.first?.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(body["q"] as? String,#"milk or brands\:other \*"#)
    }
}

private struct Reply: Sendable {
    var status = 200
    var body = Data()
    var hold = false
}
private final class StageClock: LedgerClock, @unchecked Sendable {
    private let lock=NSLock();private var interval:TimeInterval=0
    var elapsed:TimeInterval { lock.withLock { interval } }
    func now()->Date { Date(timeIntervalSince1970:1_700_000_000+elapsed) }
    func advance(_ seconds:TimeInterval) { lock.withLock { interval += seconds } }
}
private final class StagedStore: @unchecked Sendable {
    private let lock=NSLock();private var pending:[Reply]=[];private var history:[URLRequest]=[]
    private var callback:(@Sendable () -> Void)?
    var requests:[URLRequest] { lock.withLock { history } }
    func reset(_ replies:[Reply],onRequest:(@Sendable () -> Void)?=nil) { lock.withLock { pending=replies;history=[];callback=onRequest } }
    func receive(_ original:URLRequest)->Reply {
        var request=original
        if request.httpBody == nil,let stream=request.httpBodyStream {
            stream.open();defer { stream.close() };var body=Data();var buffer=[UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable { let count=stream.read(&buffer,maxLength:buffer.count);if count<=0 { break };body.append(contentsOf:buffer.prefix(count)) }
            request.httpBody=body
        }
        let (reply,callback)=lock.withLock { () -> (Reply,(@Sendable () -> Void)?) in
            history.append(request);return (pending.isEmpty ? Reply(status:500) : pending.removeFirst(),self.callback)
        }
        callback?();return reply
    }
}
private final class StagedProtocol: URLProtocol,@unchecked Sendable {
    static let store=StagedStore()
    override class func canInit(with request:URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        let reply=Self.store.receive(request)
        guard !reply.hold else { return }
        let response=HTTPURLResponse(url:request.url!,statusCode:reply.status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:reply.body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
