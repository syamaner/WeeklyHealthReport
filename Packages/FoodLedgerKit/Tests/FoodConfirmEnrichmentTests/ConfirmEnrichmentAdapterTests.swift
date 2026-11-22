import FoodConfirmEnrichment
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// The file and Debug in-memory adapters of FoodConfirmEnrichment run the shared port suites, and the
/// file cache holds exactly CE1.2's value (docs/confirm-enrichment-openrouter-v1-phase.md sections 2.5,
/// 2.6, 4 and 7: G2, G5, G15). Synthetic data only.
final class ConfirmEnrichmentAdapterTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ce1-adapters-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    var cacheURL: URL { directory.appendingPathComponent(FileConfirmEnrichmentCache.fileName) }
    var ledgerURL: URL { directory.appendingPathComponent(FileConfirmEnrichmentDayLedger.fileName) }
    let now = Date(timeIntervalSince1970: 1_795_000_000.456)

    func answer(_ subject: Character, bytes: String = #"{"ok":true}"#, at date: Date? = nil) throws -> ConfirmEnrichmentCachedAnswer {
        let data = Data(bytes.utf8)
        return ConfirmEnrichmentCachedAnswer(subjectSHA256: String(repeating: subject, count: 64), part: .nutrients, response: data,
                                             responseSHA256: try SHA256Digester().sha256(data).value, model: "openai/gpt-6.1-sol",
                                             provider: "Azure", costMicroUSD: 1_100, receivedAt: ConfirmEnrichmentTime.truncated(date ?? now))
    }

    // MARK: Shared suites

    func testEveryCachePassesTheSharedSuite() {
        var index = 0
        XCTAssertEqual(ConfirmEnrichmentPortContracts.cacheViolations {
            index += 1
            return FileConfirmEnrichmentCache(url: directory.appendingPathComponent("cache-\(index).json"))
        }, [])
        XCTAssertEqual(ConfirmEnrichmentPortContracts.cacheViolations { InMemoryConfirmEnrichmentCache() }, [])
        XCTAssertEqual(ConfirmEnrichmentPortContracts.cacheViolations { ConfirmEnrichmentTestCache() }, [])
    }

    func testEveryDayLedgerPassesTheSharedSuite() throws {
        var index = 0
        let dir = directory!
        XCTAssertEqual(ConfirmEnrichmentPortContracts.ledgerViolations { stored in
            index += 1
            let url = dir.appendingPathComponent("day-\(index).json")
            if case .unreadable = stored { try? Data("not json".utf8).write(to: url) }
            return FileConfirmEnrichmentDayLedger(url: url)
        }, [])
        XCTAssertEqual(ConfirmEnrichmentPortContracts.ledgerViolations { InMemoryConfirmEnrichmentDayLedger($0) }, [])
        XCTAssertEqual(ConfirmEnrichmentPortContracts.ledgerViolations { ConfirmEnrichmentTestLedger($0) }, [])
    }

    func testTheTimingAdaptersPassTheirSuites() async {
        let delaying = await ConfirmEnrichmentPortContracts.delayingViolations(TaskConfirmEnrichmentDelaying())
        XCTAssertEqual(delaying, [])
        XCTAssertEqual(ConfirmEnrichmentPortContracts.timingViolations(ContinuousConfirmEnrichmentTiming(),
                                                                        jitter: SystemConfirmEnrichmentJitter()), [])
    }

    func testTheScriptedAdaptersAskTheGateOnEveryAttempt() async throws {
        let details = try ConfirmEnrichmentRequestGoldenTests.detailsRequest(.openFoodFactsSearch)
        let nutrients = try ConfirmEnrichmentRequestGoldenTests.nutrientRequest(.openFoodFactsSearch)
        let a = await ConfirmEnrichmentPortContracts.attemptViolations(use: .confirmEnrichmentDetails, {
            DetailsAttempting(ScriptedFoodDetailsSuggester(egress: $0))
        }, body: details.body)
        XCTAssertEqual(a, [])
        let b = await ConfirmEnrichmentPortContracts.attemptViolations(use: .confirmEnrichmentNutrients, {
            NutrientAttempting(ScriptedNutrientEstimateSuggester(egress: $0))
        }, body: nutrients.body)
        XCTAssertEqual(b, [])
    }

    // MARK: G2 Cache content

    func testTheCacheFileHoldsExactlyTheApprovedValue() throws {
        let cache = FileConfirmEnrichmentCache(url: cacheURL)
        // The request held a sentinel description, amount and key; the reply does not echo them.
        let sentinels = ["Sentinel Description Zebra", "437.5 g", "sk-or-v1-sentinel-key"]
        cache.store(try answer("a", bytes: #"{"id":"gen-1","model":"openai/gpt-6.1-sol","provider":"Azure"}"#), now: now)
        let bytes = try Data(contentsOf: cacheURL)
        let text = String(decoding: bytes, as: UTF8.self)
        for sentinel in sentinels { XCTAssertFalse(text.contains(sentinel)) }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["schema", "entries"])
        XCTAssertEqual(root["schema"] as? String, ConfirmEnrichmentCachePolicy.schema)
        let entries = try XCTUnwrap(root["entries"] as? [[String: Any]])
        XCTAssertEqual(Set(entries[0].keys), ["subject_sha256", "part", "response", "response_sha256", "model", "provider",
                                              "cost_microusd", "received_at"])
        let response = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(entries[0]["response"] as? String)))
        for sentinel in sentinels { XCTAssertFalse(String(decoding: response, as: UTF8.self).contains(sentinel)) }
        XCTAssertEqual(entries[0]["received_at"] as? String, "2026-11-18T11:06:40.456Z")
        // The time received round-trips without loss.
        XCTAssertEqual(cache.answer(subject: String(repeating: "a", count: 64), part: .nutrients, now: now)?.receivedAt,
                       ConfirmEnrichmentTime.truncated(now))
    }

    func testABrokenCacheFileIsDiscardedWhole() throws {
        let good = FileConfirmEnrichmentCache(url: cacheURL)
        good.store(try answer("a"), now: now)
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any])
        var extraKey = valid
        var entries = try XCTUnwrap(valid["entries"] as? [[String: Any]])
        entries[0]["request_body"] = "{}"
        extraKey["entries"] = entries
        var unknownSchema = valid
        unknownSchema["schema"] = "confirm-enrichment-cache-v2"
        var extraTopKey = valid
        extraTopKey["note"] = "x"
        let one = try XCTUnwrap((valid["entries"] as? [[String: Any]])?.first)
        var tooMany = valid
        tooMany["entries"] = (0..<501).map { index -> [String: Any] in
            var entry = one
            entry["subject_sha256"] = String(format: "%064x", index)
            return entry
        }
        let variants: [Data] = [
            try JSONSerialization.data(withJSONObject: extraKey), try JSONSerialization.data(withJSONObject: unknownSchema),
            try JSONSerialization.data(withJSONObject: extraTopKey), try JSONSerialization.data(withJSONObject: tooMany),
            Data("corrupt {".utf8),
        ]
        for (index, data) in variants.enumerated() {
            try data.write(to: cacheURL)
            let cache = FileConfirmEnrichmentCache(url: cacheURL)
            XCTAssertNil(cache.answer(subject: String(repeating: "a", count: 64), part: .nutrients, now: now), "variant \(index)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path), "variant \(index) was not deleted")
            // Rebuilt empty on the next write.
            cache.store(try answer("b"), now: now)
            XCTAssertNotNil(cache.answer(subject: String(repeating: "b", count: 64), part: .nutrients, now: now))
        }
    }

    func testAnOldEntryMisses() throws {
        let cache = FileConfirmEnrichmentCache(url: cacheURL)
        cache.store(try answer("a"), now: now)
        XCTAssertNil(cache.answer(subject: String(repeating: "a", count: 64), part: .nutrients, now: now.addingTimeInterval(31 * 24 * 3_600)))
    }

    func testAHitWhoseBytesDoNotMatchItsHashIsAMissAtTheSession() async throws {
        // The cache returns what it holds; the session rechecks the hash and drops the entry.
        let cache = ConfirmEnrichmentTestCache()
        let request = try ConfirmEnrichmentRequestGoldenTests.nutrientRequest(.openFoodFactsSearch)
        let tampered = ConfirmEnrichmentCachedAnswer(subjectSHA256: request.subjectSHA256, part: .nutrients,
                                                     response: Data("{}".utf8), responseSHA256: String(repeating: "0", count: 64),
                                                     model: "openai/gpt-6.1-sol", provider: "Azure", costMicroUSD: nil,
                                                     receivedAt: ConfirmEnrichmentTime.truncated(now))
        cache.store(tampered, now: now)
        let adapter = ConfirmEnrichmentTestAdapter([.transportFailed(.offline)], use: .confirmEnrichmentNutrients)
        let session = ConfirmEnrichmentSession(
            availability: ConfirmEnrichmentAvailability(details: true, nutrients: true), routes: ConfirmEnrichmentRoutes.all,
            details: adapter, nutrients: adapter, checker: ConfirmEnrichmentTestRouteChecker(), cache: cache,
            ledger: ConfirmEnrichmentTestLedger(), egress: PermittingOpenRouterEgress(), delaying: ConfirmEnrichmentTestDelaying(),
            timing: ConfirmEnrichmentTestTiming(), jitter: ConfirmEnrichmentTestJitter(), clock: ConfirmEnrichmentTestClock(now),
            timeZone: TimeZone(identifier: "Europe/London")!, ids: ConfirmEnrichmentTestIDs(), digester: SHA256Digester())
        let outcome = await session.nutrients(request, mode: .cacheOnly,
                                              preconditions: .init(openRouterOn: true, enrichmentOn: true, keyState: .valid),
                                              locale: try LedgerText("en_GB"))
        XCTAssertEqual(outcome, ConfirmEnrichmentSession.NutrientOutcome.failed(.silent))
        XCTAssertTrue(cache.answers.isEmpty)
    }

    // MARK: G15 isolation

    func testTheScriptedStoresNeverReachTheLiveFiles() throws {
        let memory = InMemoryConfirmEnrichmentCache()
        memory.store(try answer("d"), now: now)
        let file = FileConfirmEnrichmentCache(url: cacheURL)
        XCTAssertNil(file.answer(subject: String(repeating: "d", count: 64), part: .nutrients, now: now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        let liveLedger = FileConfirmEnrichmentDayLedger(url: ledgerURL)
        let scripted = InMemoryConfirmEnrichmentDayLedger()
        try scripted.update { _ in ConfirmEnrichmentSpendPolicy.Day(localDay: "2026-11-18", requests: 4, settledMicroUSD: 9_000, paused: [.nutrients]) }
        XCTAssertEqual(liveLedger.read(), .absent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ledgerURL.path))
    }

    func testAnUnreadableLedgerFileReadsUnreadable() throws {
        try Data("{\"schema\":\"confirm-enrichment-day-v1\"}".utf8).write(to: ledgerURL)
        XCTAssertEqual(FileConfirmEnrichmentDayLedger(url: ledgerURL).read(), .unreadable)
        let ledger = FileConfirmEnrichmentDayLedger(url: ledgerURL)
        let day = ConfirmEnrichmentSpendPolicy.Day(localDay: "2026-11-18", requests: 1, settledMicroUSD: 0,
                                                   openRequests: [.init(requestID: "r1", part: .details, chargedMicroUSD: 10_000, attemptsSent: 1)])
        try ledger.update { _ in day }
        XCTAssertEqual(FileConfirmEnrichmentDayLedger(url: ledgerURL).read(), .day(day))
    }

    // MARK: Scripted gate and route values

    func testTheScriptedGatePermitsOnlyTheFourUsesWithBothSwitchesOn() {
        for (openRouter, enrichment) in [(true, true), (true, false), (false, true), (false, false)] {
            let gate = ScriptedConfirmEnrichmentGate(openRouterOn: { openRouter }, enrichmentOn: { enrichment })
            for use in OpenRouterUse.allCases {
                let expected = openRouter && enrichment && ScriptedConfirmEnrichmentGate.uses.contains(use)
                XCTAssertEqual(gate.permits(use), expected, "\(use) with \(openRouter), \(enrichment)")
            }
        }
        XCTAssertEqual(ScriptedConfirmEnrichmentGate.uses, [.confirmEnrichmentDetails, .confirmEnrichmentNutrients,
                                                           .confirmEnrichmentDetailsCatalogueCheck, .confirmEnrichmentNutrientsCatalogueCheck])
        XCTAssertEqual(ScriptedConfirmEnrichmentKeySource.state, .valid)
    }

    /// CE1.4's response checks, one refusal per rule, in System One's answer shape (review of PR 566).
    func testTheDetailsCheckRefusesEveryReplyOutsideCE14() throws {
        let details = try ConfirmEnrichmentRequestGoldenTests.detailsRequest(.openFoodFactsSearch)
        let route = ConfirmEnrichmentRoutes.details
        func answer(_ choice: Any = "unknown", confidence: Any = 0.9, probabilities: Any = ["unknown": 0.9]) -> [String: Any] {
            ["type": "choice", "choice": choice, "confidence": confidence, "probabilities": probabilities]
        }
        func reply(_ change: (inout [String: Any]) -> Void = { _ in }) -> Data {
            var answers: [String: Any] = [:]
            for fact in details.inputs.asked { answers[fact.rawValue] = answer() }
            var root: [String: Any] = ["id": "gen-test", "model": route.model, "provider": route.provider, "answers": answers,
                                       "usage": ["input_tokens": 300, "output_tokens": 20, "cost": 0.00002]]
            change(&root)
            return try! JSONSerialization.data(withJSONObject: root)
        }
        func check(_ bytes: Data) -> Result<ConfirmDetailsResponseCheck.Parsed, ConfirmEnrichmentResponseFailure> {
            ConfirmDetailsResponseCheck.check(bytes, request: details.inputs, models: route.acceptedModels, provider: route.provider)
        }
        guard case let .success(parsed) = check(reply()) else { return XCTFail("the valid reply fails") }
        XCTAssertEqual(parsed.usage.promptTokens, 300, "System One reports input_tokens")
        let first = details.inputs.asked[0].rawValue
        func setting(_ value: Any) -> (inout [String: Any]) -> Void {
            { root in var answers = root["answers"] as! [String: Any]; answers[first] = value; root["answers"] = answers }
        }
        let refusals: [(String, Data, ConfirmEnrichmentResponseFailure)] = [
            ("old value key", reply(setting(["type": "choice", "value": "unknown", "confidence": 0.9, "probabilities": ["unknown": 0.9]])), .answers),
            ("choice outside the list", reply(setting(answer("fortified"))), .answers),
            ("confidence above 1", reply(setting(answer(confidence: 1.5))), .answers),
            ("boolean confidence", reply(setting(answer(confidence: true))), .answers),
            ("probability key outside the choices", reply(setting(answer(probabilities: ["fortified": 0.9]))), .answers),
            ("empty probabilities", reply(setting(answer(probabilities: [String: Double]()))), .answers),
            ("missing fact", reply { root in var a = root["answers"] as! [String: Any]; a[first] = nil; root["answers"] = a }, .answers),
            ("extra fact", reply { root in var a = root["answers"] as! [String: Any]; a["colour"] = answer(); root["answers"] = a }, .answers),
            ("wrong model", reply { $0["model"] = "typesafe/jev-0.1" }, .modelMismatch),
            ("wrong provider", reply { $0["provider"] = "Other" }, .providerMismatch),
            ("not JSON", Data("not json".utf8), .notJSON),
            ("over 50,000 bytes", reply { $0["padding"] = String(repeating: "x", count: 50_001) }, .tooLarge),
        ]
        for (name, bytes, failure) in refusals {
            guard case let .failure(found) = check(bytes) else { XCTFail("\(name) was accepted"); continue }
            XCTAssertEqual(found, failure, name)
        }
        // A null or boolean prompt count falls back to input_tokens.
        let nullPrompt = reply { $0["usage"] = ["prompt_tokens": NSNull(), "input_tokens": 5_000] }
        guard case let .success(fallback) = check(nullPrompt) else { return XCTFail("null prompt_tokens refused the reply") }
        XCTAssertEqual(fallback.usage.promptTokens, 5_000)
        guard case let .success(boolean) = check(reply { $0["usage"] = ["prompt_tokens": true] }) else { return XCTFail("refused") }
        XCTAssertNil(boolean.usage.promptTokens, "a boolean is no count")
    }

    func testScriptedAnswersAndCapturesTakeTheRouteValues() async throws {
        let gate = PermittingOpenRouterEgress()
        let details = try ConfirmEnrichmentRequestGoldenTests.detailsRequest(.openFoodFactsSearch)
        guard case let .sent(200, aBytes, _) = await ScriptedFoodDetailsSuggester(egress: gate).attempt(details.body, timeout: 30) else {
            return XCTFail("no scripted A answer")
        }
        let route = ConfirmEnrichmentRoutes.details
        guard case let .success(parsedA) = ConfirmDetailsResponseCheck.check(aBytes, request: details.inputs,
                                                                             models: route.acceptedModels, provider: route.provider) else {
            return XCTFail("the scripted A answer fails the route's checks")
        }
        XCTAssertFalse(ConfirmDetailsResponseCheck.applied(parsedA.answers).isEmpty)
        XCTAssertFalse(ConfirmDetailsResponseCheck.applied(parsedA.answers).contains("fortified"))
        let nutrients = try ConfirmEnrichmentRequestGoldenTests.nutrientRequest(.openFoodFactsSearch)
        guard case let .sent(200, bBytes, _) = await ScriptedNutrientEstimateSuggester(egress: gate).attempt(nutrients.body, timeout: 30) else {
            return XCTFail("no scripted B answer")
        }
        let bRoute = ConfirmEnrichmentRoutes.nutrients
        guard case let .success(parsedB) = ConfirmNutrientResponseCheck.check(bBytes, request: nutrients.inputs,
                                                                              models: bRoute.acceptedModels, provider: bRoute.provider) else {
            return XCTFail("the scripted B answer fails the route's checks")
        }
        let rows = ConfirmNutrientResponseCheck.captureRows(parsedB, request: nutrients.inputs)
        XCTAssertTrue(rows.contains { $0.result == ConfirmNutrientRowResult.kept.rawValue })
        let capture = try ConfirmEnrichmentCaptureBuilder.nutrients(
            request: nutrients, route: bRoute, response: bBytes, rows: rows, generationID: parsedB.usage.generationID, model: bRoute.model,
            receivedAt: now, locale: try LedgerText("en_GB"), id: try LedgerID("00000000-0000-4000-8000-000000000701"),
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let typed = try XCTUnwrap(ConfirmEnrichmentEvidence.nutrients(capture))
        XCTAssertEqual(typed.model, bRoute.model)
        XCTAssertEqual(typed.provider, bRoute.provider)
        XCTAssertEqual(typed.endpoint, ConfirmEnrichmentRoutes.nutrientURL)
        XCTAssertEqual(ConfirmEnrichmentRoutes.details.endpoint, ConfirmEnrichmentRoutes.detailsURL)
        XCTAssertEqual(ConfirmEnrichmentRoutes.details.version, ConfirmEnrichmentVersions.detailsRoute)
        XCTAssertEqual(ConfirmEnrichmentRoutes.nutrients.version, ConfirmEnrichmentVersions.nutrientRoute)
        // The ceilings the phase gate pins (section 2.6).
        XCTAssertEqual([route.promptCeilingTokens, route.completionCeilingTokens, route.reasoningLimitTokens], [8_000, 400, 0])
        XCTAssertEqual([bRoute.promptCeilingTokens, bRoute.completionCeilingTokens, bRoute.reasoningLimitTokens], [6_000, 1_200, 500])
    }
}
