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

    // MARK: send

    func testSendReservesWSettlesToTheReportedCostAndCaches() async throws {
        let first = try await SendCommand.run(options())
        XCTAssertEqual(first.attempt, "responded")
        XCTAssertFalse(first.cached)
        XCTAssertEqual(first.costUSD, "0.004")
        XCTAssertEqual(first.chargedUSD, "0.004")
        // W: 12,000 x 0.0000022 + (2,400 + 500) x 0.000011.
        XCTAssertEqual(first.reservedUSD, "0.0583")
        XCTAssertEqual(first.requestSHA256.count, 64)
        let settled = try entries()
        XCTAssertEqual(settled.count, 1)
        XCTAssertEqual(settled[0]["kind"] as? String, EvalSpendLedger.settledKind)
        XCTAssertEqual(settled[0]["cost_usd"] as? String, "0.004")
        XCTAssertEqual(settled[0]["reserved_usd"] as? String, "0.0583")
        XCTAssertEqual(settled[0]["purpose"] as? String, "pasted-label-ai-text-eval")
        XCTAssertEqual(try ledger()["reported_spend_usd"] as? String, "0.004")
        XCTAssertEqual(try ledger()["unknown_cost_calls"] as? Int, 0)
        for value in settled[0].values { XCTAssertFalse("\(value)".contains("Typical values"), "the ledger never holds the text") }
        // The second send reuses the cached response, pays nothing and keeps its original cost.
        let second = try await SendCommand.run(options())
        XCTAssertTrue(second.cached)
        XCTAssertEqual(second.costUSD, "0.004")
        XCTAssertEqual(second.response, first.response)
        XCTAssertEqual(try entries().count, 1, "a cached response is not charged again")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("cache/\(first.requestSHA256).json").path))
    }

    func testAnUnknownCostIsChargedAtWAndCountsTowardTheUnknownStop() async throws {
        let result = try await SendCommand.run(options(label: "uk-no-cost"))
        XCTAssertEqual(result.attempt, "responded")
        XCTAssertNil(result.costUSD)
        XCTAssertEqual(result.chargedUSD, "0.0583")
        let entry = try XCTUnwrap(entries().first)
        XCTAssertEqual(entry["kind"] as? String, EvalSpendLedger.unknownKind)
        XCTAssertTrue(entry["cost_usd"] is NSNull, "unknown, never zero")
        XCTAssertEqual(try ledger()["unknown_cost_calls"] as? Int, 1)
        XCTAssertEqual(try EvalSpendLedger(url: root.appendingPathComponent("ledger.json")).totals(cell: "cell-a").cell, Decimal(string: "0.0583"))
    }

    func testTheCellAndProgrammeStopsRefuseBeforeSending() async throws {
        let cell = try await SendCommand.run(options(cellStop: Decimal(string: "0.05")!))
        XCTAssertEqual(cell.attempt, "refused:the $5 cell stop would be passed")
        XCTAssertNil(cell.response)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.json").path), "nothing reserved or written")
        // Programme: one call in cell A, then cell B is refused once the programme total plus W passes the stop.
        _ = try await SendCommand.run(options(label: "uk-no-cost", programmeStop: Decimal(string: "0.1")!))
        let programme = try await SendCommand.run(options(cell: "cell-b", programmeStop: Decimal(string: "0.1")!))
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
        XCTAssertEqual(result.chargedUSD, "0.0583")
        XCTAssertEqual(try entries().first?["kind"] as? String, EvalSpendLedger.unknownKind)
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
        XCTAssertEqual(output.readerVersions["mapping"], "pasted-label-ai-text-mapping-v1")
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
    static func reply(cost: String?) -> [String: Any] {
        let content = String(decoding: try! JSONEncoder().encode(wire), as: UTF8.self)
        let usage = #""prompt_tokens": 1200, "completion_tokens": 400"# + (cost.map { #", "cost": \#($0)"# } ?? "")
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
