import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
@testable import PastedLabelAITextEvalCore
@testable import PastedLabelAITextEvalHarness
import XCTest

/// Fresh runs for run-to-run noise (docs/pasted-label-ai-text-v1.md 5.2 item 1, revision 16) over a
/// scripted transport: a fresh run sends the same body again under its own cache entry, with the
/// usual reservation and ledger, and never reads or writes the default entry. No network.
final class FreshRunTests: XCTestCase {
    static let key = "sk-or-v1-synthetic-test-key-0123456789abcdef"
    static let label = "uk-synthetic-01"
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("eval-fresh-\(UUID().uuidString)", isDirectory: true)
        try Fixtures.write(to: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    var cacheDirectory: URL { root.appendingPathComponent("cache") }
    var ledgerURL: URL { root.appendingPathComponent("ledger.json") }

    func options(_ transport: ScriptedTransport, cell: String, freshRun: String? = nil) throws -> SendCommand.Options {
        let key = try EnvironmentKey(environment: [EnvironmentKey.variable: Self.key])
        let clock = TestClock()
        let policy = SendRetryPolicy(maxAttempts: 3, sleep: { clock.sleep($0) }, jitter: { 0 }, now: { clock.now })
        return SendCommand.Options(labelID: Self.label, textURL: root.appendingPathComponent("texts/\(Self.label).txt"),
                                   route: PastedLabelAITextRoute.gemini4ArgonVertexUS, cell: cell, ledgerURL: ledgerURL,
                                   cacheDirectory: cacheDirectory, connection: .transport(transport, keys: key), retry: policy,
                                   promptVersion: .v2, freshRun: freshRun)
    }

    func entries() throws -> [[String: Any]] {
        let ledger = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: ledgerURL)) as? [String: Any])
        return try XCTUnwrap(ledger["entries"] as? [[String: Any]])
    }

    func postedBodies(_ transport: ScriptedTransport) -> [Data?] { transport.requests.filter { $0.method == "POST" }.map(\.body) }

    static func answer(_ cost: String) -> ScriptedTransport.Step {
        .reply(200, [:], Fixtures.reply(cost: cost)["body"] as! String)
    }

    func testAFreshRunIgnoresTheDefaultEntrySendsTheSameBodyAndLeavesTheDefaultUntouched() async throws {
        let first = ScriptedTransport([Self.answer("0.004")])
        let original = try await SendCommand.run(try options(first, cell: "v2__cand__tuning"))
        XCTAssertFalse(original.cached)
        XCTAssertNil(original.freshRun)
        let defaultFile = cacheDirectory.appendingPathComponent("\(original.requestSHA256).json")
        let defaultBytes = try Data(contentsOf: defaultFile)

        let fresh = ScriptedTransport([Self.answer("0.003")])
        let r2 = try await SendCommand.run(try options(fresh, cell: "v2__cand__tuning-r2", freshRun: "r2"))
        XCTAssertFalse(r2.cached, "the default entry is never read by a fresh run")
        XCTAssertEqual(fresh.posts, 1)
        XCTAssertEqual(r2.attempt, "responded")
        XCTAssertEqual(r2.freshRun, "r2")
        XCTAssertEqual(r2.cell, "v2__cand__tuning-r2")
        XCTAssertEqual(r2.costUSD, "0.003")
        XCTAssertEqual(r2.requestSHA256, original.requestSHA256, "the product's request body is unchanged")
        XCTAssertEqual(postedBodies(fresh), postedBodies(first), "byte for byte the same body")

        XCTAssertEqual(try Data(contentsOf: defaultFile), defaultBytes, "the default entry is never overwritten")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent("\(original.requestSHA256).fresh-r2.json").path))
        let again = try await SendCommand.run(try options(ScriptedTransport([]), cell: "v2__cand__tuning"))
        XCTAssertTrue(again.cached)
        XCTAssertNil(again.freshRun)
        XCTAssertEqual(again.cachedCostUSD, "0.004", "the default run still reads its own answer")
    }

    func testARepeatOfTheSameFreshRunIsACacheHitAndNeverResends() async throws {
        let fresh = ScriptedTransport([Self.answer("0.003")])
        let sent = try await SendCommand.run(try options(fresh, cell: "v2__cand__tuning-r2", freshRun: "r2"))
        XCTAssertFalse(sent.cached)
        let count = try entries().count
        let repeatTransport = ScriptedTransport([])
        let repeated = try await SendCommand.run(try options(repeatTransport, cell: "v2__cand__tuning-r2", freshRun: "r2"))
        XCTAssertTrue(repeated.cached)
        XCTAssertEqual(repeated.freshRun, "r2")
        XCTAssertEqual(repeated.chargedUSD, "0")
        XCTAssertEqual(repeated.cachedCostUSD, "0.003")
        XCTAssertEqual(repeatTransport.posts, 0)
        XCTAssertEqual(try entries().count, count, "nothing is reserved again")
    }

    func testTwoFreshRunsSendSeparatelyEachUnderItsOwnReservationAndCell() async throws {
        let usual = try await SendCommand.run(try options(ScriptedTransport([Self.answer("0.004")]), cell: "v2__cand__tuning"))
        let w = try XCTUnwrap(usual.reservedWUSD)
        let r2Transport = ScriptedTransport([Self.answer("0.003")])
        let r3Transport = ScriptedTransport([Self.answer("0.002")])
        let r2 = try await SendCommand.run(try options(r2Transport, cell: "v2__cand__tuning-r2", freshRun: "r2"))
        let r3 = try await SendCommand.run(try options(r3Transport, cell: "v2__cand__tuning-r3", freshRun: "r3"))
        XCTAssertEqual([r2Transport.posts, r3Transport.posts], [1, 1])
        XCTAssertEqual([r2.cached, r3.cached], [false, false])
        XCTAssertEqual([r2.freshRun, r3.freshRun], ["r2", "r3"])
        XCTAssertEqual([r2.costUSD, r3.costUSD], ["0.003", "0.002"])
        // W is reserved and recorded as for any tap, one entry per attempt, in the fresh run's own cell.
        XCTAssertEqual([r2.reservedWUSD, r3.reservedWUSD], [w, w], "the same W as the default run's tap")
        XCTAssertEqual([r2.attempts, r3.attempts], [1, 1])
        let settled = Array(try entries().dropFirst())
        XCTAssertEqual(settled.count, 2)
        XCTAssertEqual(settled.map { $0["cell"] as? String }, ["v2__cand__tuning-r2", "v2__cand__tuning-r3"])
        XCTAssertEqual(settled.map { $0["reserved_usd"] as? String }, [w, w])
        XCTAssertEqual(settled.map { $0["kind"] as? String }, [EvalSpendLedger.settledKind, EvalSpendLedger.settledKind])
        XCTAssertEqual(settled.map { $0["cost_usd"] as? String }, ["0.003", "0.002"])
    }

    func testAFreshRunRetriesUnderAReservationPerAttempt() async throws {
        let transport = ScriptedTransport([.reply(503, [:], #"{"error": {"code": 503, "message": "synthetic"}, "usage": {"cost": 0.001}}"#),
                                           Self.answer("0.003")])
        let output = try await SendCommand.run(try options(transport, cell: "v2__cand__tuning-r2", freshRun: "r2"))
        XCTAssertEqual(output.attemptOutcomes, ["responded:503", "responded:200"])
        let w = try XCTUnwrap(Decimal(string: try XCTUnwrap(try entries().first?["reserved_usd"] as? String)))
        XCTAssertEqual(output.reservedWUSD, "\(w * 2)", "one W per attempt")
        XCTAssertEqual(output.costUSD, "0.004")
        XCTAssertEqual(try entries().count, 2)
    }

    func testAnInvalidRunNameIsRefusedBeforeAnythingIsReservedOrSent() async throws {
        for name in ["", "R2", "2r", "r_2", "r.2", "r 2", "r2-", "r--2", "-r2", "r2/..", "r12345678901234567", "r2\n"] {
            let transport = ScriptedTransport([Self.answer("0.003")])
            do {
                _ = try await SendCommand.run(try options(transport, cell: "v2__cand__tuning-x", freshRun: name))
                XCTFail("\(name.debugDescription) was accepted")
            } catch SendCommand.Failure.badFreshRun(let refused) {
                XCTAssertEqual(refused, name)
            }
            XCTAssertTrue(transport.requests.isEmpty, "\(name.debugDescription): nothing is checked or sent")
            XCTAssertFalse(FileManager.default.fileExists(atPath: ledgerURL.path), "\(name.debugDescription): nothing is reserved")
        }
        for name in ["r2", "r3", "r10", "noise-a", "a", "abcdefghijklmnop"] { XCTAssertTrue(SendCommand.isFreshRunName(name), name) }
    }

    func testTheCacheKeyGrammarIsClosed() {
        let sha = String(repeating: "a", count: 64)
        XCTAssertEqual(ResponseCache.key(sha, freshRun: nil), sha)
        XCTAssertEqual(ResponseCache.key(sha, freshRun: "r2"), "\(sha).fresh-r2")
        XCTAssertTrue(ResponseCache.isKey(sha))
        XCTAssertTrue(ResponseCache.isKey("\(sha).fresh-r2"))
        for bad in ["\(sha).r2", "\(sha).fresh-", "\(sha).fresh-R2", "\(sha).fresh-r2/../x", "\(sha).", "short.fresh-r2", "\(sha).fresh-r2.json"] {
            XCTAssertFalse(ResponseCache.isKey(bad), bad)
        }
    }

    func testARecordWithoutAFreshRunStillDecodesAndOneWithItRoundTrips() throws {
        let old = #"{"label_id":"x","cell":"c","route_candidate":"r","model":"m","endpoint":"e","prompt_version":"prompt-v1","instruction_sha256":"i","schema_sha256":"s","text_sha256":"t","request_sha256":"q","cached":false,"attempt":"responded","charged_usd":"0"}"#
        var decoded = try JSONDecoder().decode(SendCommand.Output.self, from: Data(old.utf8))
        XCTAssertNil(decoded.freshRun)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertFalse(String(decoding: try encoder.encode(decoded), as: UTF8.self).contains("fresh_run"), "absent stays absent")
        decoded.freshRun = "r2"
        let data = try encoder.encode(decoded)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""fresh_run":"r2""#))
        XCTAssertEqual(try JSONDecoder().decode(SendCommand.Output.self, from: data), decoded)
    }
}
