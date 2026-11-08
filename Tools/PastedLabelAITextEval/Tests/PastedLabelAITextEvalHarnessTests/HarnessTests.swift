import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
@testable import PastedLabelAITextEvalCore
@testable import PastedLabelAITextEvalHarness
import XCTest

/// The A2 harness over the fake transport (docs/pasted-label-ai-text-v1.md 5.2 items 1 to 3, T5):
/// the shipped builder, the spend reservation and its stops, the response cache, and the scorer
/// run over the shipped reader, on synthetic labels only.
final class HarnessTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("eval-\(UUID().uuidString)", isDirectory: true)
        try Fixtures.write(to: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func options(label: String = "uk-synthetic-01", cell: String = "cell-a", cellStop: Decimal = 5, programmeStop: Decimal = 25) -> SendCommand.Options {
        SendCommand.Options(labelID: label, textURL: root.appendingPathComponent("texts/\(label).txt"), route: PastedLabelAITextRoute.gemini4ArgonVertexUS,
                            cell: cell, ledgerURL: root.appendingPathComponent("ledger.json"), cacheDirectory: root.appendingPathComponent("cache"),
                            fakeTransportDirectory: root.appendingPathComponent("fake"), cellStop: cellStop, programmeStop: programmeStop)
    }

    func ledger() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("ledger.json"))) as? [String: Any])
    }

    func entries() throws -> [[String: Any]] { try XCTUnwrap(ledger()["entries"] as? [[String: Any]]) }

    /// W for a text, from the request's own prompt bound (gate finding 2): the bound at the fixture's
    /// prompt price, plus 2,400 completion and 500 reasoning tokens at its completion price.
    static func w(_ text: String) throws -> Decimal {
        let bound = try OpenRouterPastedLabelAITextRequest(route: PastedLabelAITextRoute.gemini4ArgonVertexUS).promptTokenBound(text)
        return Decimal(bound) * Decimal(string: "0.0000022")! + Decimal(2_900) * Decimal(string: "0.000011")!
    }
    static var ukW: Decimal { try! w(Fixtures.ukText) }
    static var noCostW: Decimal { try! w(Fixtures.ukText + "\n") }

    // MARK: send

    func testSendReservesWSettlesToTheReportedCostAndCaches() async throws {
        let first = try await SendCommand.run(options())
        XCTAssertEqual(first.attempt, "responded")
        XCTAssertFalse(first.cached)
        XCTAssertEqual(first.costUSD, "0.004")
        XCTAssertEqual(first.chargedUSD, "0.004")
        XCTAssertEqual(first.reservedUSD, "\(Self.ukW)")
        XCTAssertLessThan(Self.ukW, Decimal(string: "0.05")!, "W prices this request's bound, not the ceiling")
        XCTAssertEqual(first.requestSHA256.count, 64)
        let settled = try entries()
        XCTAssertEqual(settled.count, 1)
        XCTAssertEqual(settled[0]["kind"] as? String, EvalSpendLedger.settledKind)
        XCTAssertEqual(settled[0]["cost_usd"] as? String, "0.004")
        XCTAssertEqual(settled[0]["reserved_usd"] as? String, "\(Self.ukW)")
        XCTAssertEqual(settled[0]["purpose"] as? String, "pasted-label-ai-text-eval")
        XCTAssertEqual(try ledger()["reported_spend_usd"] as? String, "0.004")
        XCTAssertEqual(try ledger()["unknown_cost_calls"] as? Int, 0)
        for value in settled[0].values { XCTAssertFalse("\(value)".contains("Typical values"), "the ledger never holds the text") }
        // The second send reuses the cached response, pays nothing and keeps its original cost.
        let second = try await SendCommand.run(options())
        XCTAssertTrue(second.cached)
        XCTAssertNil(second.costUSD, "no call was made this time")
        XCTAssertEqual(second.chargedUSD, "0", "a cached tap is not charged again (Qodo finding 7)")
        XCTAssertEqual(second.cachedCostUSD, "0.004", "the original tap's cost, kept apart")
        XCTAssertEqual(second.response, first.response)
        XCTAssertEqual(try entries().count, 1, "a cached response is not charged again")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("cache/\(first.requestSHA256).json").path))
    }

    /// Revision 11: the prompt version is recorded, and each version has its own cache key.
    func testThePromptVersionIsRecordedAndKeysItsOwnCacheEntry() async throws {
        typealias Request = OpenRouterPastedLabelAITextRequest
        let v1 = try await SendCommand.run(options())
        XCTAssertEqual(v1.promptVersion, "prompt-v1", "the default")
        XCTAssertEqual(v1.instructionSHA256, Request.PromptVersion.v1.instructionSHA256)
        let base = options()
        let v2Options = SendCommand.Options(labelID: base.labelID, textURL: base.textURL, route: base.route, cell: "cell-v2",
                                            ledgerURL: base.ledgerURL, cacheDirectory: base.cacheDirectory,
                                            fakeTransportDirectory: root.appendingPathComponent("fake"), promptVersion: .v2)
        let v2 = try await SendCommand.run(v2Options)
        XCTAssertEqual(v2.promptVersion, "prompt-v2")
        XCTAssertEqual(v2.instructionSHA256, Request.PromptVersion.v2.instructionSHA256)
        XCTAssertEqual(v2.schemaSHA256, v1.schemaSHA256)
        XCTAssertNotEqual(v2.requestSHA256, v1.requestSHA256, "the instruction is in the body, so the cache key differs")
        XCTAssertFalse(v2.cached, "a v1 answer is never served for v2")
        XCTAssertEqual(try entries().count, 2, "v2 reserved and settled its own call")
        let again = try await SendCommand.run(v2Options)
        XCTAssertTrue(again.cached)
        XCTAssertEqual(again.promptVersion, "prompt-v2")
        XCTAssertEqual(again.requestSHA256, v2.requestSHA256)
        XCTAssertGreaterThan(Decimal(string: try XCTUnwrap(v2.reservedUSD))!, Decimal(string: try XCTUnwrap(v1.reservedUSD))!,
                             "W follows the longer instruction")
    }

    func testAnUnknownCostIsChargedAtWAndCountsTowardTheUnknownStop() async throws {
        let result = try await SendCommand.run(options(label: "uk-no-cost"))
        XCTAssertEqual(result.attempt, "responded")
        XCTAssertNil(result.costUSD)
        XCTAssertEqual(result.chargedUSD, "\(Self.noCostW)")
        let entry = try XCTUnwrap(entries().first)
        XCTAssertEqual(entry["kind"] as? String, EvalSpendLedger.unknownKind)
        XCTAssertTrue(entry["cost_usd"] is NSNull, "unknown, never zero")
        XCTAssertEqual(try ledger()["unknown_cost_calls"] as? Int, 1)
        XCTAssertEqual(try EvalSpendLedger(url: root.appendingPathComponent("ledger.json")).totals(cell: "cell-a").cell, Self.noCostW)
    }

    func testTheCellAndProgrammeStopsRefuseBeforeSending() async throws {
        let cell = try await SendCommand.run(options(cellStop: Self.ukW - Decimal(string: "0.001")!))
        XCTAssertEqual(cell.attempt, "refused:the $5 cell stop would be passed")
        XCTAssertNil(cell.response)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.json").path), "nothing reserved or written")
        // Programme: one call in cell A, then cell B is refused once the programme total plus W passes the stop.
        let programmeStop = Self.noCostW + Self.ukW - Decimal(string: "0.001")!
        _ = try await SendCommand.run(options(label: "uk-no-cost", programmeStop: programmeStop))
        let programme = try await SendCommand.run(options(cell: "cell-b", programmeStop: programmeStop))
        XCTAssertEqual(programme.attempt, "refused:the $25 programme stop would be passed")
        XCTAssertEqual(try entries().count, 1)
        XCTAssertThrowsError(try EvalSpendLedger(url: root.appendingPathComponent("x.json"), cellStop: 6))
        XCTAssertThrowsError(try EvalSpendLedger(url: root.appendingPathComponent("x.json"), programmeStop: 26))
    }

    func testTheLedgersOwnUnknownCostStopStillApplies() async throws {
        var existing = EvalSpendLedger.fresh()
        existing["entries"] = (0..<3).map { _ in ["purpose": "route-c", "cost_usd": NSNull(), "kind": "answer"] as [String: Any] }
        existing["route_c_extra"] = "kept"
        try JSONSerialization.data(withJSONObject: existing).write(to: root.appendingPathComponent("ledger.json"))
        let refused = try await SendCommand.run(options())
        XCTAssertEqual(refused.attempt, "refused:the ledger's unknown-cost stop is reached")
        XCTAssertEqual(try ledger()["route_c_extra"] as? String, "kept", "a refused reservation writes nothing")
    }

    func testTheLedgerKeepsMembersItDoesNotOwnAndRefusesAnUnknownSchema() async throws {
        var existing = EvalSpendLedger.fresh()
        existing["stopped_models"] = ["x/y"]
        existing["entries"] = [["purpose": "route-c", "cost_usd": "0.1", "kind": "answer", "model": "x/y"]]
        try JSONSerialization.data(withJSONObject: existing).write(to: root.appendingPathComponent("ledger.json"))
        _ = try await SendCommand.run(options())
        XCTAssertEqual(try ledger()["stopped_models"] as? [String], ["x/y"])
        XCTAssertEqual(try entries().count, 2)
        XCTAssertEqual(try ledger()["reported_spend_usd"] as? String, "0.104")
        try Data(#"{"schema_version": "something-else"}"#.utf8).write(to: root.appendingPathComponent("ledger.json"))
        let refused = try await SendCommand.run(options(label: "uk-no-cost"))
        XCTAssertEqual(refused.attempt, "refused:the spend ledger has an unknown schema")
        XCTAssertNil(refused.response)
    }

    func testThePhotoLedgerIsRefusedAndAFreshLedgerIsTheTextSchema() async throws {
        // #426 Qodo findings: the text and photo routes never share a ledger file, so neither reader
        // applies its rules to the other's entries.
        XCTAssertNotEqual(EvalSpendLedger.schema, EvalSpendLedger.photoSchema)
        try Data(#"{"schema_version": "label-capture-spend-ledger-v1", "entries": []}"#.utf8).write(to: root.appendingPathComponent("ledger.json"))
        let refused = try await SendCommand.run(options())
        XCTAssertEqual(refused.attempt, "refused:the spend ledger is the photo evaluation's; the text evaluation keeps its own")
        XCTAssertNil(refused.response)
        try FileManager.default.removeItem(at: root.appendingPathComponent("ledger.json"))
        _ = try await SendCommand.run(options(label: "uk-no-cost"))
        XCTAssertEqual(try ledger()["schema_version"] as? String, "pasted-label-ai-text-spend-ledger-v1")
        XCTAssertEqual(try ledger()["limits"] as? [String: AnyHashable], ["per_call_usd": "0.20", "total_usd": "25", "unknown_cost_calls_allowed": 3])
    }

    func testTheFileStatesTheChargeIncludingWForUnknownCosts() async throws {
        _ = try await SendCommand.run(options())
        _ = try await SendCommand.run(options(label: "uk-no-cost"))
        XCTAssertEqual(try ledger()["reported_spend_usd"] as? String, "0.004", "an unknown cost is never zero")
        XCTAssertEqual(try ledger()["charged_usd"] as? String, "\(Decimal(string: "0.004")! + Self.noCostW)")
        XCTAssertEqual(try ledger()["open_calls"] as? Int, 0)
        XCTAssertEqual(try ledger()["unknown_cost_calls"] as? Int, 1)
    }

    func testANotSentAttemptSettlesToZero() async throws {
        let ledger = try EvalSpendLedger(url: root.appendingPathComponent("ledger.json"))
        let id = try ledger.reserve(cell: "c", caseID: "x", model: "m", worstCase: Decimal(string: "0.02")!, at: "t", id: "r1")
        XCTAssertEqual(try ledger.totals(cell: "c").cell, Decimal(string: "0.02"), "an open reservation is charged at W")
        try ledger.settle(id: id, .notSent, returnedModel: nil, generationID: nil, at: "t")
        XCTAssertEqual(try ledger.totals(cell: "c").cell, 0)
        XCTAssertThrowsError(try ledger.settle(id: id, .notSent, returnedModel: nil, generationID: nil, at: "t"), "settles once")
    }

    func testAMissingCannedReplyIsATransportFailureChargedAtW() async throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent("fake/responses/uk-synthetic-01.json"))
        let result = try await SendCommand.run(options())
        XCTAssertEqual(result.attempt, "transport_failed:failed")
        XCTAssertEqual(result.chargedUSD, "\(Self.ukW)")
        XCTAssertEqual(try entries().first?["kind"] as? String, EvalSpendLedger.noGenerationKind)
    }

    func testAPanelTheDetectorDeclinesIsNeverSent() async throws {
        try Data("Nutrition Facts\nPer 100g\nSodium 100mg".utf8).write(to: root.appendingPathComponent("texts/us-synthetic.txt"))
        let send = try await SendCommand.run(options(label: "us-synthetic"))
        XCTAssertEqual(send.attempt, "declined_before_send:nutrition_facts_title,sodium_without_salt")
        XCTAssertEqual(send.chargedUSD, "0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.json").path), "nothing reserved")
        let usText = Data("Nutrition Facts\nPer 100g\nSodium 100mg".utf8)
        let usCase = try EvalCase(labelID: "us-synthetic", set: .ukV1Fresh, tier: "A", copyMethod: "synthetic", textSHA256: EvalCase.sha256(usText),
                                  expected: .init(panel: "us_nutrition_facts", servingSize: nil, servingsPerPack: nil,
                                                  columns: [.init(heading: "Per 100g", basis: "per_100g")],
                                                  rows: [.init(label: "Sodium", nutrient: "sodium", values: [.init(comparator: "=", number: "100", unit: "mg")])],
                                                  notes: []),
                                  source: .init(schema: TranscriptionShapes.UKTranscription.schema, sha256: String(repeating: "ab", count: 32)))
        let output = try ScoreCommand.run(evalCase: usCase, textData: usText, send: send)
        XCTAssertEqual(output.score.outcome, "declined")
        XCTAssertEqual(output.score.declineReasons, ["detector:nutrition_facts_title", "detector:sodium_without_salt"])
    }

    // MARK: Gate findings 2 and 8: W from the request, overruns, the ledger's own stops, the cache

    func testAFull8000ScalarTraditionalChineseTextIsReservedAtItsOwnBound() async throws {
        let text = String(repeating: "鈉", count: 8_000)
        try Data(text.utf8).write(to: root.appendingPathComponent("texts/tw-full.txt"))
        try Fixtures.json(Fixtures.reply(cost: "0.03"), root.appendingPathComponent("fake/responses/tw-full.json"))
        let send = try await SendCommand.run(options(label: "tw-full"))
        XCTAssertEqual(send.attempt, "responded")
        XCTAssertEqual(send.reservedUSD, "\(try Self.w(text))")
        XCTAssertGreaterThan(try Self.w(text), Self.ukW)
    }

    /// Revision 17: a reasoning-off cell reserves W with the whole output cap counted again as
    /// reasoning (the session bills reasoning separately), and its body sends `effort: "none"`.
    func testAReasoningOffCellReservesItsOutputCapAsReasoning() async throws {
        let route = PastedLabelAITextRoute.gpt6LunaAzure4KNoReason
        let listing: [String: Any] = ["data": ["id": route.model, "architecture": ["input_modalities": ["text", "image"]],
                                               "endpoints": [["tag": "azure", "provider_name": "Azure", "pricing": Fixtures.pricing]]]]
        try Fixtures.json(listing, root.appendingPathComponent("fake/catalogue/listing.json"))
        try Fixtures.json(["data": [["model_id": route.model, "tag": "azure", "provider_name": "Azure"]]], root.appendingPathComponent("fake/catalogue/zdr.json"))
        var reply = Fixtures.reply(cost: "0.004")
        reply["body"] = (reply["body"] as! String).replacingOccurrences(of: "google/gemini-4-argon", with: route.model)
            .replacingOccurrences(of: #""provider": "Google""#, with: #""provider": "Azure""#)
        try Fixtures.json(reply, root.appendingPathComponent("fake/responses/uk-synthetic-01.json"))
        let base = options()
        let off = SendCommand.Options(labelID: base.labelID, textURL: base.textURL, route: route, cell: "cell-off", ledgerURL: base.ledgerURL,
                                      cacheDirectory: base.cacheDirectory, fakeTransportDirectory: root.appendingPathComponent("fake"))
        let send = try await SendCommand.run(off)
        XCTAssertEqual(send.attempt, "responded")
        let bound = try OpenRouterPastedLabelAITextRequest(route: route).promptTokenBound(Fixtures.ukText)
        let w = Decimal(bound) * Decimal(string: "0.0000022")! + Decimal(8_000) * Decimal(string: "0.000011")!
        XCTAssertEqual(send.reservedUSD, "\(w)")
        let body = try OpenRouterPastedLabelAITextRequest(route: route).body(Fixtures.ukText)
        XCTAssertEqual(send.requestSHA256, EvalCase.sha256(body))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["reasoning"] as? [String: String], ["effort": "none"])
    }

    func testAnOverrunStopsTheCell() async throws {
        // Prompt tokens above the request's bound: W was not a true bound, so the cell stops.
        try Fixtures.json(Fixtures.reply(cost: "0.004", promptTokens: 999_999), root.appendingPathComponent("fake/responses/uk-synthetic-01.json"))
        let first = try await SendCommand.run(options())
        XCTAssertEqual(first.attempt, "responded")
        XCTAssertTrue((try ledger()["stopped_models"] as? [String] ?? []).contains(EvalSpendLedger.cellKey("cell-a")))
        let next = try await SendCommand.run(options(label: "uk-no-cost"))
        XCTAssertEqual(next.attempt, "refused:the cell is stopped: an earlier call passed its W or its prompt bound")
        let other = try await SendCommand.run(options(label: "uk-no-cost", cell: "cell-b"))
        XCTAssertEqual(other.attempt, "responded", "another cell is not stopped")
    }

    func testAReportedCostAboveWStopsTheCell() async throws {
        try Fixtures.json(Fixtures.reply(cost: "0.5"), root.appendingPathComponent("fake/responses/uk-synthetic-01.json"))
        _ = try await SendCommand.run(options())
        let stopped = try ledger()["stopped_models"] as? [String] ?? []
        XCTAssertTrue(stopped.contains(EvalSpendLedger.cellKey("cell-a")))
        XCTAssertTrue(stopped.contains("google/gemini-4-argon"), "above the ledger's per-call stop, the model stops too")
        let next = try await SendCommand.run(options(label: "uk-no-cost", cell: "cell-b"))
        XCTAssertEqual(next.attempt, "refused:the model is stopped in the ledger")
    }

    func testTheLedgersPerCallStopAndStoppedModelsAreHonoured() async throws {
        var existing = EvalSpendLedger.fresh()
        existing["limits"] = ["per_call_usd": "0.01", "total_usd": "65", "unknown_cost_calls_allowed": 3]
        try JSONSerialization.data(withJSONObject: existing).write(to: root.appendingPathComponent("ledger.json"))
        let perCall = try await SendCommand.run(options())
        XCTAssertEqual(perCall.attempt, "refused:W passes the ledger's per-call stop")
        existing["limits"] = ["per_call_usd": "0.20", "total_usd": "65", "unknown_cost_calls_allowed": 3]
        existing["stopped_models"] = ["google/gemini-4-argon"]
        try JSONSerialization.data(withJSONObject: existing).write(to: root.appendingPathComponent("ledger.json"))
        let stopped = try await SendCommand.run(options())
        XCTAssertEqual(stopped.attempt, "refused:the model is stopped in the ledger")
    }

    func testOnlyAnAnsweringHTTP200ReplyIsCached() async throws {
        try Fixtures.json(["status": 503, "headers": [String: String](), "body": #"{"error": {"code": 503}, "usage": {"cost": 0.001}}"#],
                          root.appendingPathComponent("fake/responses/uk-synthetic-01.json"))
        let first = try await SendCommand.run(options())
        XCTAssertEqual(first.status, 503)
        let second = try await SendCommand.run(options())
        XCTAssertFalse(second.cached, "a failed reply is sent again, never replayed from the cache")
        XCTAssertEqual(try entries().count, 2)
    }

    /// Qodo finding 6: concurrent identical sends make one call; the other reads its cache entry.
    func testConcurrentIdenticalSendsMakeOneCall() async throws {
        let opts = options()
        async let first = SendCommand.run(opts)
        async let second = SendCommand.run(opts)
        let results = try await [first, second]
        XCTAssertEqual(results.filter(\.cached).count, 1)
        XCTAssertEqual(results.map(\.chargedUSD).sorted(), ["0", "0.004"])
        XCTAssertEqual(try entries().count, 1, "one reservation, one call")
    }

    func testScoreReportsACachedTapAtItsOriginalCost() async throws {
        _ = try await SendCommand.run(options())
        let cached = try await SendCommand.run(options())
        let output = try ScoreCommand.run(evalCase: Fixtures.ukCase, textData: Data(Fixtures.ukText.utf8), send: cached)
        XCTAssertEqual(output.costUSD, "0.004")
        XCTAssertEqual(output.chargedUSD, "0")
        XCTAssertTrue(output.cached)
    }

    /// Qodo re-review findings 1 and 3: a tap records the W it reserved (kept on a cache hit), and a
    /// catalogue failure is a structured record that reserved and sent nothing.
    func testTheReservedWIsRecordedAndACatalogueFailureIsStructured() async throws {
        let first = try await SendCommand.run(options())
        XCTAssertEqual(first.reservedWUSD, "\(Self.ukW)")
        let cached = try await SendCommand.run(options())
        XCTAssertTrue(cached.cached)
        XCTAssertEqual(cached.reservedWUSD, "\(Self.ukW)", "the original tap's W")
        let refused = try await SendCommand.run(options(label: "uk-no-cost", cellStop: Decimal(string: "0.001")!))
        XCTAssertTrue(refused.attempt.hasPrefix("refused:"))
        XCTAssertNil(refused.reservedWUSD, "a refused tap reserved nothing")
        try FileManager.default.removeItem(at: root.appendingPathComponent("fake/catalogue/listing.json"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("ledger.json"))
        let failed = try await SendCommand.run(options(label: "uk-no-cost"))
        XCTAssertTrue(failed.attempt.hasPrefix("catalogue_failed:"), failed.attempt)
        XCTAssertEqual(failed.chargedUSD, "0")
        XCTAssertNil(failed.reservedWUSD)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.json").path), "nothing reserved")
        let scored = try ScoreCommand.run(evalCase: Fixtures.ukCase, textData: Data(Fixtures.ukText.utf8),
                                          send: try await SendCommand.run(options()))
        XCTAssertEqual(scored.score.outcome, "reached_confirm", "the cached answer still scores")
    }

    func testScoreRefusesASendRecordForAnotherText() async throws {
        var send = try await SendCommand.run(options())
        send.textSHA256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try ScoreCommand.run(evalCase: Fixtures.ukCase, textData: Data(Fixtures.ukText.utf8), send: send))
    }

    // MARK: score

    func testScoreRunsTheShippedStepsAndCountsTheFields() async throws {
        let send = try await SendCommand.run(options())
        let output = try ScoreCommand.run(evalCase: Fixtures.ukCase, textData: Data(Fixtures.ukText.utf8), send: send)
        XCTAssertEqual(output.score.outcome, "reached_confirm")
        XCTAssertEqual(output.score.fieldsPrinted, 8)
        XCTAssertEqual(output.score.fieldsShown, 9, "the fabricated fibre value is shown, under attention")
        XCTAssertEqual(output.score.fieldsCorrect, 8)
        XCTAssertEqual(output.score.fieldsWrong, 1)
        XCTAssertEqual(output.score.wrongFlagged, 1)
        XCTAssertEqual(output.score.wrongSilent, 0)
        XCTAssertFalse(output.score.silentErrorTable)
        XCTAssertFalse(output.score.exactMatch)
        XCTAssertEqual(output.score.printedNotCorrect, 0)
        XCTAssertTrue(output.pass)
        XCTAssertEqual(output.namedScores["fields_correct"], 8)
        XCTAssertEqual(output.f1, 2 * (8.0 / 9) * 1 / (8.0 / 9 + 1), accuracy: 1e-12)
        XCTAssertEqual(output.readerVersions["mapping"], "pasted-label-ai-text-mapping-v4")
        XCTAssertEqual(output.readerVersions["format"], "pasted-label-ai-text-format-v1")
        XCTAssertEqual(output.readerVersions["scorer"], "pasted-label-ai-text-scorer-v5 (rules of uk-fresh-scorer-v2; RI amount columns and unrecognised rows not printed fields; two or more %RI columns paired in printed order; a lone * a class marker)")
        XCTAssertEqual(output.score.fieldsReferenceAmounts, 0)
        XCTAssertEqual(output.score.fieldsUnrecognisedRows, 0)
    }

    func testAWrongModelFailsTheLabel() async throws {
        var send = try await SendCommand.run(options())
        send.response = send.response?.replacingOccurrences(of: "google/gemini-4-argon", with: "google/gemini-4-argon-lite")
        let output = try ScoreCommand.run(evalCase: Fixtures.ukCase, textData: Data(Fixtures.ukText.utf8), send: send)
        XCTAssertEqual(output.score.outcome, "failed")
        XCTAssertEqual(output.score.failure, "envelope:wrongModel")
        XCTAssertFalse(output.pass)
        var refused = send
        refused.attempt = "refused:the $5 cell stop would be passed"
        XCTAssertEqual(try ScoreCommand.run(evalCase: Fixtures.ukCase, textData: Data(Fixtures.ukText.utf8), send: refused).score.outcome, "failed")
        XCTAssertThrowsError(try ScoreCommand.run(evalCase: Fixtures.ukCase, textData: Data("other".utf8), send: send))
    }
}

/// Synthetic fixtures: a UK-format label, its case and the fake transport's directory.
enum Fixtures {
    static let ukText = """
    Nutrition
    Typical values\tPer 100g
    Energy\t1046kJ / 250kcal
    Fat\t9.5g
    of which saturates\t3.2g
    Carbohydrate\t30g
    of which sugars\t12g
    Protein\t8.1g
    Salt\t0.75g
    """

    static let wire = #"{"declined": false, "decline_reasons": [], "language": "en", "serving_size_text": "unknown", "servings_per_pack_text": "unknown", "headers": [{"header_id": "h1", "printed_text": "Per 100g", "basis": "per_100g"}], "rows": [{"printed_label": "Energy", "nutrient": "energy_kj", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "1046kJ", "unit": ""}]}, {"printed_label": "Energy", "nutrient": "energy_kcal", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "250kcal", "unit": ""}]}, {"printed_label": "Fat", "nutrient": "fat", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "9.5g", "unit": ""}]}, {"printed_label": "of which saturates", "nutrient": "saturates", "parent_nutrient": "fat", "values": [{"header_id": "h1", "printed_text": "3.2g", "unit": ""}]}, {"printed_label": "Carbohydrate", "nutrient": "carbohydrate", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "30g", "unit": ""}]}, {"printed_label": "of which sugars", "nutrient": "sugars", "parent_nutrient": "carbohydrate", "values": [{"header_id": "h1", "printed_text": "12g", "unit": ""}]}, {"printed_label": "Fibre", "nutrient": "fibre", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "3g", "unit": ""}]}, {"printed_label": "Protein", "nutrient": "protein", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "8.1g", "unit": ""}]}, {"printed_label": "Salt", "nutrient": "salt", "parent_nutrient": "none", "values": [{"header_id": "h1", "printed_text": "0.75g", "unit": ""}]}]}"#

    /// The canned reply, with its body as the exact bytes OpenRouter would print (a cost literal as written).
    static func reply(cost: String?, promptTokens: Int = 1_200) -> [String: Any] {
        let content = String(decoding: try! JSONEncoder().encode(wire), as: UTF8.self)
        let usage = #""prompt_tokens": \#(promptTokens), "completion_tokens": 400"# + (cost.map { #", "cost": \#($0)"# } ?? "")
        let body = #"{"id": "gen-1", "model": "google/gemini-4-argon", "provider": "Google", "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": \#(content)}}], "usage": {\#(usage)}}"#
        return ["status": 200, "headers": [String: String](), "body": body]
    }

    nonisolated(unsafe) static let pricing: [String: Any] = ["prompt": "0.0000022", "completion": "0.000011", "internal_reasoning": "0.000011"]
    nonisolated(unsafe) static let listing: [String: Any] = ["data": ["id": "google/gemini-4-argon", "architecture": ["input_modalities": ["text", "image"]],
                                                  "endpoints": [["tag": "google-vertex/us", "provider_name": "Google", "pricing": pricing]]]]
    nonisolated(unsafe) static let zdr: [String: Any] = ["data": [["model_id": "google/gemini-4-argon", "tag": "google-vertex/us", "provider_name": "Google"]]]

    static var ukCase: EvalCase {
        let row = { (label: String, nutrient: String, number: String, unit: String) in
            TranscriptionShapes.Row(label: label, nutrient: nutrient, values: [.init(comparator: "=", number: number, unit: unit)])
        }
        return try! EvalCase(labelID: "uk-synthetic-01", set: .ukV1Fresh, tier: "A", copyMethod: "scripted range", textSHA256: EvalCase.sha256(Data(ukText.utf8)),
                             expected: .init(panel: "uk_declaration", servingSize: nil, servingsPerPack: nil, columns: [.init(heading: "Per 100g", basis: "per_100g")],
                                             rows: [row("Energy", "energy_kj", "1046", "kJ"), row("Energy", "energy_kcal", "250", "kcal"), row("Fat", "fat", "9.5", "g"),
                                                    row("of which saturates", "saturates", "3.2", "g"), row("Carbohydrate", "carbohydrate", "30", "g"),
                                                    row("of which sugars", "sugars", "12", "g"), row("Protein", "protein", "8.1", "g"), row("Salt", "salt", "0.75", "g")],
                                             notes: []),
                             source: .init(schema: TranscriptionShapes.UKTranscription.schema, sha256: String(repeating: "ab", count: 32)))
    }

    static func json(_ object: Any, _ url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }

    static func write(to root: URL) throws {
        let fm = FileManager.default
        for dir in ["fake/catalogue", "fake/responses", "texts", "cases"] {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        func json(_ object: Any, _ path: String) throws {
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: root.appendingPathComponent(path))
        }
        try json(listing, "fake/catalogue/listing.json")
        try json(zdr, "fake/catalogue/zdr.json")
        try json(reply(cost: "0.004"), "fake/responses/uk-synthetic-01.json")
        try json(reply(cost: nil), "fake/responses/uk-no-cost.json")
        // A different text for the no-cost label, so its request body (and cache key) differs.
        try Data(ukText.utf8).write(to: root.appendingPathComponent("texts/uk-synthetic-01.txt"))
        try Data((ukText + "\n").utf8).write(to: root.appendingPathComponent("texts/uk-no-cost.txt"))
        try ukCase.canonicalJSON().write(to: root.appendingPathComponent("cases/uk-synthetic-01.json"))
    }
}
