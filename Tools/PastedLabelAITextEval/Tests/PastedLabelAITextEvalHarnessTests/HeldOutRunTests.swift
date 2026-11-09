import FoodLabelPhotoCapture
import FoodLabelTextAIReading
import FoodLedgerApplication
import Foundation
@testable import PastedLabelAITextEvalCore
@testable import PastedLabelAITextEvalHarness
import XCTest

/// The A4 held-out runner (docs/pasted-label-ai-text-v1.md 5.5 item 9), over synthetic folders in a
/// temporary private root and the fake transports only: nothing here reads the sealed set or makes
/// a network call. The `uk-english-v2` directory here is a temporary stand-in, never the sealed set.
final class HeldOutRunTests: XCTestCase {
    static let commit = String(repeating: "ab", count: 20)
    static let ids = (1 ... 24).map { String(format: "H%02d", $0) }
    var root: URL!
    var paths: HeldOutRun.Paths { HeldOutRun.Paths(root: root) }
    var fresh: URL { paths.fresh }
    var fake: URL { root.appendingPathComponent("fake") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("eval-heldout-\(UUID().uuidString)", isDirectory: true)
        try HeldOutFixtures.write(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    var noWait: SendRetryPolicy { SendRetryPolicy(maxAttempts: 3, sleep: { _ in }, jitter: { 0 }) }

    func run(_ connection: SendCommand.Connection? = nil) async throws -> [String: Int] {
        try await HeldOutRun.run(privateRoot: root, commit: Self.commit, connection: connection ?? .fake(directory: fake), retry: noWait)
    }

    func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func rows(_ url: URL) throws -> [[String: Any]] {
        try XCTUnwrap((json(url)["results"] as? [String: Any])?["results"] as? [[String: Any]])
    }

    static func id(_ row: [String: Any]) -> String? { (row["vars"] as? [String: Any])?["label_id"] as? String }

    // MARK: A full run

    func testAFullRunWritesResultsTheStatisticsScriptReadsWithATierASubset() async throws {
        let transport = SolTransport()
        let counts = try await run(.transport(transport, keys: FakeTransportKey()))
        XCTAssertEqual(counts["labels"], 24)
        XCTAssertEqual(counts["run"], 24)
        XCTAssertEqual(counts["not_run"], 0)
        XCTAssertEqual(counts["tier_a_labels"], 9)
        XCTAssertEqual((counts["reached_confirm"] ?? 0) + (counts["declined"] ?? 0) + (counts["failed"] ?? 0), 24)
        // The bytes sent are the bytes sealed: one POST per label, in ID order, each the prompt-v2 request over that text.
        let request = try OpenRouterPastedLabelAITextRequest(route: PastedLabelAITextRoute.gpt61SolAzure4K, promptVersion: .v2)
        XCTAssertEqual(transport.posts.map(\.body), try Self.ids.map { try request.body(HeldOutFixtures.text($0)) })
        let results = try rows(paths.results)
        XCTAssertEqual(results.map { Self.id($0) }, Self.ids)
        for row in results {
            XCTAssertEqual((row["provider"] as? [String: Any])?["label"] as? String, "gpt-6.1-sol-azure-4k")
            XCTAssertEqual((row["prompt"] as? [String: Any])?["label"] as? String, "prompt-v2")
            let named = try XCTUnwrap((row["gradingResult"] as? [String: Any])?["namedScores"] as? [String: Double])
            XCTAssertNotNil(named["tap_latency_seconds"])
            XCTAssertNotNil(named["attempt_latency_seconds"])
            let output = try XCTUnwrap((row["response"] as? [String: Any])?["output"] as? String)
            let send = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
            XCTAssertNotNil(send["tap_started_at_ms"] as? Int)
            XCTAssertEqual(send["cell"] as? String, "v2__gpt-6.1-sol-azure-4k__a4-heldout")
            XCTAssertEqual(send["prompt_version"] as? String, "prompt-v2")
        }
        XCTAssertEqual(try rows(paths.resultsTierA).map { Self.id($0) }, Array(Self.ids.prefix(9)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.cases.path).count, 24)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.casesTierA.path).sorted(), Self.ids.prefix(9).map { "\($0).json" })
        // The run record: the commit, the frozen configuration, the seals and the latency method.
        let record = try json(paths.runRecord)
        XCTAssertEqual(record["commit"] as? String, Self.commit)
        XCTAssertEqual(record["latency_method"] as? String, "in_process_send_to_score_end")
        XCTAssertEqual(record["label_ids"] as? [String], Self.ids)
        XCTAssertEqual(((record["seals"] as? [String: Any])?["text"] as? [String: Any])?["sha256"] as? String, try HeldOutFixtures.textSeal(fresh))
        let configuration = try XCTUnwrap(record["configuration"] as? [String: Any])
        XCTAssertEqual(configuration["instruction_sha256"] as? String, FreezePinTests.frozenPromptSHA256)
        XCTAssertEqual(configuration["route_candidate"] as? String, "gpt-6.1-sol-azure-4k")
        // The spend went to the A3 ledger, in the A4 cell only.
        let entries = try XCTUnwrap(json(paths.ledger)["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.filter { $0["cell"] as? String == HeldOutRun.cell }.count, 24)
        XCTAssertEqual(entries.count, 25)
        // The frozen statistics script reads both, with the tier breakdown.
        let all = try Self.statistics(paths.results, cases: paths.cases)
        let cell = try XCTUnwrap((all["cells"] as? [String: Any])?["gpt-6.1-sol-azure-4k|prompt-v2"] as? [String: Any])
        XCTAssertEqual(cell["labels"] as? Int, 24)
        XCTAssertEqual((cell["bar"] as? [String: Any])?["labels"] as? Int, 24)
        let tiers = try XCTUnwrap((cell["breakdowns"] as? [String: Any])?["tier"] as? [String: Any])
        XCTAssertEqual((tiers["A"] as? [String: Any])?["labels"] as? Int, 9)
        XCTAssertEqual((tiers["B"] as? [String: Any])?["labels"] as? Int, 15)
        let tierA = try Self.statistics(paths.resultsTierA, cases: paths.casesTierA)
        XCTAssertEqual(((tierA["cells"] as? [String: Any])?["gpt-6.1-sol-azure-4k|prompt-v2"] as? [String: Any])?["labels"] as? Int, 9)
    }

    /// `python3 -I pasted_label_ai_text_stats.py summary RESULTS --cases CASES`, the frozen script as committed.
    static func statistics(_ results: URL, cases: URL) throws -> [String: Any] {
        var script = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 { script.deleteLastPathComponent() }
        script.appendPathComponent("statistics/pasted_label_ai_text_stats.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-I", script.path, "summary", results.path, "--cases", cases.path]
        process.environment = ["PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let error = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: error, as: UTF8.self))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Refusals, each with nothing reserved

    /// Runs and asserts `expected` was thrown with nothing reserved, sent or created.
    func assertRefused(_ expected: HeldOutRun.Refusal, outputExisted: Bool = false, cacheExisted: Bool = false,
                       connection: SendCommand.Connection? = nil, file: StaticString = #filePath, line: UInt = #line) async throws {
        let ledgerBefore = FileManager.default.contents(atPath: paths.ledger.path)
        let transport = SolTransport()
        do {
            _ = try await run(connection ?? .transport(transport, keys: FakeTransportKey()))
            XCTFail("not refused: \(expected)", file: file, line: line)
        } catch let refusal as HeldOutRun.Refusal {
            XCTAssertEqual(refusal, expected, file: file, line: line)
        }
        XCTAssertEqual(transport.posts.count, 0, "nothing sent", file: file, line: line)
        XCTAssertEqual(FileManager.default.contents(atPath: paths.ledger.path), ledgerBefore, "nothing reserved", file: file, line: line)
        if !outputExisted { XCTAssertFalse(HeldOutRun.exists(paths.output), "no output folder", file: file, line: line) }
        if !cacheExisted { XCTAssertFalse(HeldOutRun.exists(paths.cache), "no cache", file: file, line: line) }
    }

    func testASecondRunIsRefused() async throws {
        _ = try await run(.transport(SolTransport(), keys: FakeTransportKey()))
        try await assertRefused(.outputExists, outputExisted: true, cacheExisted: true)
    }

    func testAnOutputFolderAloneIsRefused() async throws {
        try FileManager.default.createDirectory(at: paths.output, withIntermediateDirectories: true)
        try await assertRefused(.outputExists, outputExisted: true)
        // A link in its place counts as existing too.
        try FileManager.default.removeItem(at: paths.output)
        try FileManager.default.createSymbolicLink(at: paths.output, withDestinationURL: root.appendingPathComponent("nowhere"))
        try await assertRefused(.outputExists, outputExisted: true)
    }

    func testOnlyALedgerEntryForTheA4CellIsRefused() async throws {
        try HeldOutFixtures.ledger(paths.ledger, entries: [HeldOutFixtures.a3Entry(), HeldOutFixtures.a3Entry(cell: HeldOutRun.cell)])
        try await assertRefused(.ledgerHoldsA4Cell)
    }

    func testAnExistingCacheIsRefused() async throws {
        try FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        try await assertRefused(.cacheExists, cacheExisted: true)
    }

    func testAMissingLedgerOrOneWithoutAnA3EntryIsRefused() async throws {
        try HeldOutFixtures.ledger(paths.ledger, entries: [])
        try await assertRefused(.noA3Entry)
        try FileManager.default.removeItem(at: paths.ledger)
        try await assertRefused(.ledgerMissing)
    }

    func testNotEnoughRoomUnderTheProgrammeStopIsRefused() async throws {
        try HeldOutFixtures.ledger(paths.ledger, entries: [HeldOutFixtures.a3Entry(cost: "24.5")])
        try await assertRefused(.noRoomUnderProgrammeStop)
    }

    func testNotEnoughRoomUnderTheCellStopIsRefused() async throws {
        // Prices half again as high: each W stays under the $0.20 per-call cap, but 24 x W x 3 passes $5.
        let transport = SolTransport(priceScale: 1.5)
        try await assertRefused(.noRoomUnderCellStop, connection: .transport(transport, keys: FakeTransportKey()))
        XCTAssertEqual(transport.posts.count, 0)
    }

    func testAMissingKeyOrCatalogueEntryIsRefused() async throws {
        try await assertRefused(.keyMissing, connection: .transport(SolTransport(), keys: NoKey()))
        try await assertRefused(.catalogueFailed, connection: .transport(SolTransport(catalogueFails: true), keys: FakeTransportKey()))
    }

    func testAMissingSeal1IsRefused() async throws {
        let seals = fresh.appendingPathComponent("seals.txt")
        let lines = try String(contentsOf: seals, encoding: .utf8).split(separator: "\n").filter { !$0.hasPrefix("seal1 ") }
        try (lines.joined(separator: "\n") + "\n").write(to: seals, atomically: true, encoding: .utf8)
        try await assertRefused(.sealsMalformed)
        // A second seal 1 line is refused as well.
        try HeldOutFixtures.writeSeals(fresh, extra: "seal1 \(String(repeating: "0", count: 64)) 24 2026-11-09T00:00:00Z\n")
        try await assertRefused(.sealsMalformed)
    }

    func testAChangedTextOrTranscriptionIsRefused() async throws {
        let text = fresh.appendingPathComponent("texts/H03.txt")
        let original = try Data(contentsOf: text)
        try (original + Data(" ".utf8)).write(to: text)
        try await assertRefused(.textSealMismatch)
        try original.write(to: text)
        let transcription = fresh.appendingPathComponent("transcription/H05.json")
        try (try Data(contentsOf: transcription) + Data("\n".utf8)).write(to: transcription)
        try await assertRefused(.seal2Mismatch)
    }

    func testIDsThatDifferBetweenFoldersAreRefused() async throws {
        let collection = fresh.appendingPathComponent("collection")
        try FileManager.default.moveItem(at: collection.appendingPathComponent("H07"), to: collection.appendingPathComponent("H99"))
        try await assertRefused(.idsDiffer)
        try FileManager.default.removeItem(at: collection.appendingPathComponent("H99"))
        try await assertRefused(.idsDiffer)
    }

    /// Qodo, A4: a linked folder on the fixed paths could move the run outside its root.
    func testALinkedFixedFolderIsRefused() async throws {
        let fm = FileManager.default
        let runs = root.appendingPathComponent("ai-text-v1/runs")
        let elsewhere = root.appendingPathComponent("elsewhere-runs")
        try fm.moveItem(at: runs, to: elsewhere)
        try fm.createSymbolicLink(at: runs, withDestinationURL: elsewhere)
        try await assertRefused(.linkedFixedPath)
        XCTAssertThrowsError(try HeldOutRun.check(privateRoot: root)) { XCTAssertEqual($0 as? HeldOutRun.Refusal, .linkedFixedPath) }
    }

    /// Qodo, A4: the per-call cap, total and unknown-cost allowance are fixed by the runner, not the ledger.
    func testAWidenedLedgerLimitIsRefused() async throws {
        let url = HeldOutRun.Paths(root: root).ledger
        var ledger = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var limits = try XCTUnwrap(ledger["limits"] as? [String: Any])
        limits["per_call_usd"] = "0.50"
        ledger["limits"] = limits
        try JSONSerialization.data(withJSONObject: ledger, options: [.sortedKeys]).write(to: url)
        try await assertRefused(.ledgerLimitsChanged)
    }

    /// Qodo, A4: tier is not under a seal, so an edit that changes the 9 and 15 split is refused.
    func testAnEditedTierSplitIsRefused() async throws {
        let text = try Data(contentsOf: fresh.appendingPathComponent("texts/H20.txt"))
        try HeldOutFixtures.source(fresh, "H20", tier: "A", textSHA256: EvalCase.sha256(text))
        try await assertRefused(.tierSplitChanged)
    }

    /// The real collection folder also keeps the skip log, search screens and recheck notes: only
    /// subfolders holding a source.json are labels, and `check` creates nothing.
    func testNonLabelCollectionEntriesAreIgnoredAndCheckCreatesNothing() throws {
        let fm = FileManager.default
        let collection = fresh.appendingPathComponent("collection")
        for name in ["search-screens", "recheck", "owner-google"] {
            try fm.createDirectory(at: collection.appendingPathComponent(name), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: collection.appendingPathComponent("\(name)/note.txt"))
        }
        try Data("{}".utf8).write(to: collection.appendingPathComponent("skip-log.json"))
        let counts = try HeldOutRun.check(privateRoot: root)
        XCTAssertEqual(counts["labels"], 24)
        let paths = HeldOutRun.Paths(root: root)
        XCTAssertFalse(fm.fileExists(atPath: paths.output.path))
        XCTAssertFalse(fm.fileExists(atPath: paths.cache.path))
    }

    func testASymbolicLinkOrAPathOutsideItsFolderIsRefused() async throws {
        let fm = FileManager.default
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        // A text replaced by a link to the same bytes outside texts/: the seal still matches, the read refuses.
        let text = fresh.appendingPathComponent("texts/H02.txt")
        try fm.moveItem(at: text, to: outside.appendingPathComponent("H02.txt"))
        try fm.createSymbolicLink(at: text, withDestinationURL: outside.appendingPathComponent("H02.txt"))
        try await assertRefused(.unsafeFile)
        try fm.removeItem(at: text)
        try fm.moveItem(at: outside.appendingPathComponent("H02.txt"), to: text)
        // transcription/ as a link to a folder elsewhere.
        let transcription = fresh.appendingPathComponent("transcription")
        try fm.moveItem(at: transcription, to: outside.appendingPathComponent("transcription"))
        try fm.createSymbolicLink(at: transcription, withDestinationURL: outside.appendingPathComponent("transcription"))
        try await assertRefused(.freshFolderUnsafe)
        try fm.removeItem(at: transcription)
        try fm.moveItem(at: outside.appendingPathComponent("transcription"), to: transcription)
        // A collection record folder as a link elsewhere.
        let record = fresh.appendingPathComponent("collection/H04")
        try fm.moveItem(at: record, to: outside.appendingPathComponent("H04"))
        try fm.createSymbolicLink(at: record, withDestinationURL: outside.appendingPathComponent("H04"))
        try await assertRefused(.unsafeFile)
    }

    func testACollectionRecordWithAnotherTextHashIsRefused() async throws {
        try HeldOutFixtures.source(fresh, "H06", tier: "B", textSHA256: String(repeating: "0", count: 64))
        try await assertRefused(.textHashMismatch)
    }

    // MARK: Failures and crashes finalise to 24 rows

    func testATransportFailureFinalisesTo24RowsWithTheFailedLabelsFailed() async throws {
        // No canned reply for three labels: the fake transport fails their POST, as an unreachable host would.
        for id in ["H02", "H10", "H20"] { try FileManager.default.removeItem(at: fake.appendingPathComponent("responses/\(id).json")) }
        let counts = try await run()
        XCTAssertEqual(counts["labels"], 24)
        XCTAssertEqual(counts["run"], 24)
        XCTAssertGreaterThanOrEqual(counts["failed"] ?? 0, 3)
        let results = try rows(paths.results)
        XCTAssertEqual(results.count, 24)
        for row in results where ["H02", "H10", "H20"].contains(Self.id(row) ?? "") {
            let named = try XCTUnwrap((row["gradingResult"] as? [String: Any])?["namedScores"] as? [String: Double])
            XCTAssertEqual(named["failed"], 1)
        }
        let summary = try Self.statistics(paths.results, cases: paths.cases)
        let cell = try XCTUnwrap((summary["cells"] as? [String: Any])?["gpt-6.1-sol-azure-4k|prompt-v2"] as? [String: Any])
        XCTAssertEqual(cell["labels"] as? Int, 24)
    }

    func testARunCutOffPartWayFinalisesTo24RowsWithTheUnrunLabelsFailedAndIsIdempotent() async throws {
        _ = try await run()
        // A crash after ten labels, part-way through writing the eleventh line.
        let journal = try String(contentsOf: paths.journal, encoding: .utf8).split(separator: "\n").map(String.init)
        try (journal.prefix(10).joined(separator: "\n") + "\n" + journal[10].prefix(40)).write(to: paths.journal, atomically: true, encoding: .utf8)
        for url in [paths.results, paths.resultsTierA, paths.casesTierA] { try FileManager.default.removeItem(at: url) }
        let counts = try HeldOutRun.finalise(paths)
        XCTAssertEqual(counts.labels, 24)
        XCTAssertEqual(counts.run, 10)
        XCTAssertEqual(counts.notRun, 14)
        XCTAssertGreaterThanOrEqual(counts.failed, 14)
        let results = try rows(paths.results)
        XCTAssertEqual(results.map { Self.id($0) }, Self.ids)
        for row in results.suffix(14) {
            XCTAssertEqual(row["error"] as? String, "not_run")
            XCTAssertEqual((row["namedScores"] as? [String: Any])?.isEmpty, true)
        }
        let first = try Data(contentsOf: paths.results)
        let firstTierA = try Data(contentsOf: paths.resultsTierA)
        XCTAssertEqual(try HeldOutRun.finalise(paths), counts)
        XCTAssertEqual(try Data(contentsOf: paths.results), first, "finalise is idempotent")
        XCTAssertEqual(try Data(contentsOf: paths.resultsTierA), firstTierA)
        let summary = try Self.statistics(paths.results, cases: paths.cases)
        let bar = try XCTUnwrap(((summary["cells"] as? [String: Any])?["gpt-6.1-sol-azure-4k|prompt-v2"] as? [String: Any])?["bar"] as? [String: Any])
        XCTAssertGreaterThanOrEqual((bar["bar_3"] as? [String: Any])?["value"] as? Int ?? 0, 14, "unrun labels count as failed")
        // A partial run is never resumed or repeated.
        try await assertRefused(.outputExists, outputExisted: true, cacheExisted: true)
    }

    /// Qodo, A4: the run record's IDs name files, so a tampered list is refused before any path is built.
    func testFinaliseRefusesATamperedRunRecord() async throws {
        _ = try await run()
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: paths.runRecord)) as? [String: Any])
        var ids = try XCTUnwrap(record["label_ids"] as? [String])
        ids[0] = "../../outside"
        record["label_ids"] = ids
        try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]).write(to: paths.runRecord)
        XCTAssertThrowsError(try HeldOutRun.finalise(paths)) { XCTAssertEqual($0 as? HeldOutRun.Refusal, .runRecordInvalid) }
    }

    /// Qodo, A4: finalise selects tier A from the tiers recorded at the start, and refuses an edited case.
    func testFinaliseRefusesACaseWhoseTierWasEdited() async throws {
        _ = try await run()
        let url = paths.cases.appendingPathComponent("H20.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["tier"] as? String, "B")
        object["tier"] = "A"
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
        XCTAssertThrowsError(try HeldOutRun.finalise(paths)) { XCTAssertEqual($0 as? HeldOutRun.Refusal, .tierSplitChanged) }
    }

    /// Qodo, A4: a linked cases-tier-a folder is refused, and nothing outside the run is removed.
    func testFinaliseRefusesALinkedTierAFolder() async throws {
        _ = try await run()
        let fm = FileManager.default
        let outside = root.appendingPathComponent("outside-tier-a")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let keep = outside.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: keep)
        try fm.removeItem(at: paths.casesTierA)
        try fm.createSymbolicLink(at: paths.casesTierA, withDestinationURL: outside)
        XCTAssertThrowsError(try HeldOutRun.finalise(paths)) { XCTAssertEqual($0 as? HeldOutRun.Refusal, .linkedFixedPath) }
        XCTAssertTrue(fm.fileExists(atPath: keep.path))
    }

    /// Qodo, A4: a crash while cases/ was being written is still finalised, its cases rebuilt
    /// from the sealed set, with every label not run counted as failed.
    func testACrashWhileWritingCasesStillFinalises() async throws {
        _ = try await run()
        let fm = FileManager.default
        for url in [paths.results, paths.resultsTierA, paths.casesTierA] { try fm.removeItem(at: url) }
        for id in Self.ids.suffix(20) { try fm.removeItem(at: paths.cases.appendingPathComponent("\(id).json")) }
        try Data().write(to: paths.journal)
        let counts = try HeldOutRun.finalise(paths)
        XCTAssertEqual(counts.labels, 24)
        XCTAssertEqual(counts.notRun, 24)
        XCTAssertEqual(counts.failed, 24)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: paths.cases.path).count, 24)
    }

    /// Qodo, A4: the private root may not sit inside a git checkout (T6).
    func testAPrivateRootInsideACheckoutIsRefused() async throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try await assertRefused(.rootInsideCheckout)
        XCTAssertThrowsError(try HeldOutRun.check(privateRoot: root)) { XCTAssertEqual($0 as? HeldOutRun.Refusal, .rootInsideCheckout) }
    }

    /// Qodo, A4: a negative charge would widen the room under the stops.
    func testANegativeLedgerChargeIsRefused() async throws {
        var ledger = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: paths.ledger)) as? [String: Any])
        var entries = try XCTUnwrap(ledger["entries"] as? [[String: Any]])
        entries[0]["cost_usd"] = "-20"
        ledger["entries"] = entries
        try JSONSerialization.data(withJSONObject: ledger, options: [.sortedKeys]).write(to: paths.ledger)
        try await assertRefused(.ledgerNegativeCharge)
    }

    func testFinaliseWithoutARunIsRefused() throws {
        XCTAssertThrowsError(try HeldOutRun.finalise(paths)) { XCTAssertEqual($0 as? HeldOutRun.Refusal, .runRecordMissing) }
    }

    // MARK: The tuning paths, the configuration and the output

    func testTuningSendRefusesTheA4Cell() async throws {
        let text = root.appendingPathComponent("tuning.txt")
        try Data(Fixtures.ukText.utf8).write(to: text)
        let options = SendCommand.Options(labelID: "uk-synthetic-01", textURL: text, route: PastedLabelAITextRoute.gpt61SolAzure4K, cell: HeldOutRun.cell,
                                          ledgerURL: root.appendingPathComponent("tuning-ledger.json"), cacheDirectory: root.appendingPathComponent("tuning-cache"),
                                          connection: .transport(SolTransport(), keys: FakeTransportKey()), retry: .single)
        do {
            _ = try await SendCommand.run(options)
            XCTFail("the A4 cell was not refused")
        } catch let failure as SendCommand.Failure {
            guard case .heldOutCell = failure else { return XCTFail("\(failure)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("tuning-ledger.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("tuning-cache").path))
        XCTAssertTrue(SendCommand.isHeldOutCell("v1__anything__a4-heldout"))
        XCTAssertFalse(SendCommand.isHeldOutCell("v2__gpt-6.1-sol-azure-4k__uk-tuning"))
    }

    var sources: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Sources")
    }

    /// The tuning CLI never uses the held-out runner, and refuses the A4 cell itself.
    func testTheTuningCLIDoesNotUseTheHeldOutRunner() throws {
        let main = try String(contentsOf: sources.appendingPathComponent("PastedLabelAITextEval/main.swift"), encoding: .utf8)
        XCTAssertFalse(main.contains("HeldOutRun"))
        XCTAssertFalse(main.contains("SendCommand.send("))
        XCTAssertTrue(main.contains(#"hasSuffix("__a4-heldout")"#))
        // The held-out executable uses the runner and the shipped live transport through LiveTransport only.
        let heldOut = try String(contentsOf: sources.appendingPathComponent("PastedLabelAITextHeldOut/main.swift"), encoding: .utf8)
        XCTAssertTrue(heldOut.contains("HeldOutRun.run("))
        XCTAssertTrue(heldOut.contains("LiveTransport.connection(key:"))
    }

    /// `HeldOutRun.run` is the only public symbol of the held-out path.
    func testRunIsTheOnlyPublicHeldOutSymbol() throws {
        let source = try String(contentsOf: sources.appendingPathComponent("PastedLabelAITextEvalHarness/HeldOutRun.swift"), encoding: .utf8)
        let publics = source.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("public ") }
        XCTAssertEqual(publics.count, 2, publics.joined(separator: "\n"))
        XCTAssertTrue(publics.contains { $0.contains("public enum HeldOutRun") })
        XCTAssertTrue(publics.contains { $0.contains("public static func run(") })
    }

    func testTheConfigurationEqualsTheFreeze() throws {
        XCTAssertEqual(HeldOutRun.route, try XCTUnwrap(PastedLabelAITextRoute.candidate("gpt-6.1-sol-azure-4k")))
        XCTAssertEqual(HeldOutRun.route.model, "openai/gpt-6.1-sol")
        XCTAssertEqual(HeldOutRun.route.endpoint, "azure")
        XCTAssertEqual(HeldOutRun.route.maxOutputTokens, 4_000)
        XCTAssertEqual(HeldOutRun.route.reasoning, .budget(500))
        XCTAssertEqual(HeldOutRun.promptVersion.rawValue, "prompt-v2")
        XCTAssertEqual(HeldOutRun.promptVersion.instructionSHA256, FreezePinTests.frozenPromptSHA256)
        XCTAssertTrue(PastedLabelAITextScorer.version.hasPrefix("pasted-label-ai-text-scorer-v5 "))
        XCTAssertEqual(HeldOutRun.cell, "v2__gpt-6.1-sol-azure-4k__a4-heldout")
        XCTAssertEqual(HeldOutRun.cellStop, 5)
        XCTAssertEqual(HeldOutRun.programmeStop, 25)
        XCTAssertEqual(HeldOutRun.attemptsPerLabel, 3)
        XCTAssertEqual(HeldOutRun.labelCount, 24)
        XCTAssertEqual(HeldOutRun.latencyMethod, "in_process_send_to_score_end")
        let home = HeldOutRun.Paths(root: URL(fileURLWithPath: "/private-root"))
        XCTAssertEqual(home.fresh.path, "/private-root/uk-english-v2/fresh")
        XCTAssertEqual(home.ledger.path, "/private-root/ai-text-v1/runs/a3/run/spend-ledger.json")
        XCTAssertEqual(home.output.path, "/private-root/ai-text-v1/runs/a4")
        XCTAssertEqual(HeldOutRun.defaultPrivateRootURL.path, (("~/WHR-label-eval-private") as NSString).expandingTildeInPath)
    }

    func testOutputIsCountsOnly() async throws {
        let counts = try await run()
        let line = HeldOutRun.report(counts)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(Set(decoded.keys), ["labels", "run", "not_run", "reached_confirm", "declined", "failed", "tier_a_labels"])
        XCTAssertTrue(decoded.values.allSatisfy { $0 is Int })
        XCTAssertFalse(line.contains("H0"))
        // Every refusal, and any other error, is a fixed reason: no label ID, hash, path or value.
        let refusals: [HeldOutRun.Refusal] = [.outputExists, .cacheExists, .ledgerMissing, .ledgerUnreadable, .noA3Entry, .ledgerHoldsA4Cell,
                                              .stoppedInLedger, .unknownCostStop, .noRoomUnderCellStop, .noRoomUnderProgrammeStop, .overPerCallCap,
                                              .promptBoundOverCeiling, .freshFolderUnsafe, .sealsMalformed, .textSealMismatch, .seal2Mismatch,
                                              .wrongFileCount, .idsDiffer, .unsafeFile, .unreadableFile, .textNotUTF8, .sourceRecordInvalid,
                                              .textHashMismatch, .conversionFailed, .roundTripFailed, .keyMissing, .catalogueFailed,
                                              .outputUnwritable, .runRecordMissing, .casesIncomplete, .badCommit]
        for refusal in refusals {
            let reason = HeldOutRun.reason(refusal)
            XCTAssertNil(reason.range(of: "[0-9a-f]{16}", options: .regularExpression), reason)
            XCTAssertFalse(reason.contains("WHR-label-eval-private") || reason.contains("H0"), reason)
        }
        XCTAssertEqual(HeldOutRun.reason(EvalCaseConverter.Refused("H01: secret value 9.5g")),
                       "the held-out run stopped on an unexpected error; the raw records stay in the private output folder")
    }
}

// MARK: Synthetic held-out folders

enum HeldOutFixtures {
    static func text(_ id: String) -> String {
        // A distinct trailing run of newlines per label, so every request body (and cache key) differs.
        Fixtures.ukText + String(repeating: "\n", count: Int(id.dropFirst()) ?? 1)
    }

    static func transcription(_ id: String) throws -> Data {
        let evalCase = try Fixtures.ukCase.with(labelID: id, layoutShape: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(try EvalCaseConverter.ukTranscription(evalCase))
    }

    static func bundle(_ folder: URL, prefix: String, suffix: String) throws -> String {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(suffix) }.sorted()
        let listing = try names.map { "\(EvalCase.sha256(try Data(contentsOf: folder.appendingPathComponent($0))))  \(prefix)/\($0)\n" }.joined()
        return EvalCase.sha256(Data(listing.utf8))
    }

    static func textSeal(_ fresh: URL) throws -> String { try bundle(fresh.appendingPathComponent("texts"), prefix: "texts", suffix: ".txt") }

    static func writeSeals(_ fresh: URL, extra: String = "") throws {
        let text = try textSeal(fresh)
        let seal2 = try bundle(fresh.appendingPathComponent("transcription"), prefix: "transcription", suffix: ".json")
        let seals = "text \(text) 24 2026-11-01T10:00:00Z\nseal1 \(seal2) 24 2026-11-02T10:00:00Z\nseal2 \(seal2) 24 2026-11-03T10:00:00Z\n" + extra
        try Data(seals.utf8).write(to: fresh.appendingPathComponent("seals.txt"))
    }

    static func source(_ fresh: URL, _ id: String, tier: String, textSHA256: String) throws {
        let folder = fresh.appendingPathComponent("collection/\(id)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Fixtures.json(["label_id": id, "tier": tier, "copy_method": "scripted range", "text_sha256": textSHA256, "slot": 1,
                           "site_name": "synthetic"], folder.appendingPathComponent("source.json"))
    }

    static func a3Entry(cell: String = "v2__gpt-6.1-sol-azure-4k__uk-tuning", cost: String = "0.5") -> [String: Any] {
        ["at": "2026-11-08T10:00:00Z", "purpose": EvalSpendLedger.purpose, "model": "openai/gpt-6.1-sol", "returned_model": "openai/gpt-6.1-sol",
         "case_id": "tuning-01", "sealed": false, "cost_usd": cost, "kind": EvalSpendLedger.settledKind, "reservation_id": UUID().uuidString,
         "cell": cell, "reserved_usd": "0.06"]
    }

    static func ledger(_ url: URL, entries: [[String: Any]]) throws {
        var ledger = EvalSpendLedger.fresh()
        ledger["entries"] = entries
        EvalSpendLedger.recount(&ledger)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ledger, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    nonisolated(unsafe) static let solListing: [String: Any] = ["data": ["id": "openai/gpt-6.1-sol", "architecture": ["input_modalities": ["text", "image"]],
                                                     "endpoints": [["tag": "azure", "provider_name": "Azure", "pricing": Fixtures.pricing]]]]
    nonisolated(unsafe) static let solZDR: [String: Any] = ["data": [["model_id": "openai/gpt-6.1-sol", "tag": "azure", "provider_name": "Azure"]]]

    static func solReply(cost: String = "0.004") -> String {
        (Fixtures.reply(cost: cost)["body"] as! String).replacingOccurrences(of: "google/gemini-4-argon", with: "openai/gpt-6.1-sol")
            .replacingOccurrences(of: #""provider": "Google""#, with: #""provider": "Azure""#)
    }

    /// The private root: the stand-in held-out folder, the A3 ledger and a directory fake transport.
    static func write(root: URL) throws {
        let fm = FileManager.default
        let fresh = HeldOutRun.Paths(root: root).fresh
        for dir in ["texts", "transcription", "collection"] {
            try fm.createDirectory(at: fresh.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for (index, id) in HeldOutRunTests.ids.enumerated() {
            let text = Data(text(id).utf8)
            try text.write(to: fresh.appendingPathComponent("texts/\(id).txt"))
            try transcription(id).write(to: fresh.appendingPathComponent("transcription/\(id).json"))
            try source(fresh, id, tier: index < 9 ? "A" : "B", textSHA256: EvalCase.sha256(text))
        }
        try writeSeals(fresh)
        try ledger(HeldOutRun.Paths(root: root).ledger, entries: [a3Entry()])
        let fake = root.appendingPathComponent("fake")
        for dir in ["catalogue", "responses"] { try fm.createDirectory(at: fake.appendingPathComponent(dir), withIntermediateDirectories: true) }
        try Fixtures.json(solListing, fake.appendingPathComponent("catalogue/listing.json"))
        try Fixtures.json(solZDR, fake.appendingPathComponent("catalogue/zdr.json"))
        for id in HeldOutRunTests.ids {
            try Fixtures.json(["status": 200, "headers": [String: String](), "body": solReply()], fake.appendingPathComponent("responses/\(id).json"))
        }
    }
}

/// A fake transport for the frozen route: the catalogue GETs answer the Sol listing (prices scaled
/// as asked), and every POST gets the canned Sol answer. It records every POST. No network.
final class SolTransport: LabelPhotoHTTPTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [LabelPhotoHTTPRequest] = []
    let priceScale: Decimal
    let catalogueFails: Bool

    init(priceScale: Decimal = 1, catalogueFails: Bool = false) { self.priceScale = priceScale; self.catalogueFails = catalogueFails }

    var posts: [LabelPhotoHTTPRequest] { lock.withLock { recorded.filter { $0.method == "POST" } } }

    func send(_ request: LabelPhotoHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse {
        lock.withLock { recorded.append(request) }
        if request.method == "GET" {
            if catalogueFails { throw LabelPhotoTransportError.failed }
            var listing = HeldOutFixtures.solListing
            if priceScale != 1 {
                let scaled = Fixtures.pricing.mapValues { "\(Decimal(string: $0 as! String)! * priceScale)" }
                listing = ["data": ["id": "openai/gpt-6.1-sol", "architecture": ["input_modalities": ["text", "image"]],
                                    "endpoints": [["tag": "azure", "provider_name": "Azure", "pricing": scaled]]]]
            }
            let object = request.url == OpenRouterLabelRouteChecker.zeroDataRetentionURL ? HeldOutFixtures.solZDR : listing
            return LabelPhotoHTTPResponse(status: 200, headers: [:], body: try JSONSerialization.data(withJSONObject: object), exceededLimit: false)
        }
        return LabelPhotoHTTPResponse(status: 200, headers: [:], body: Data(HeldOutFixtures.solReply().utf8), exceededLimit: false)
    }
}

/// A key store with no key.
struct NoKey: FoodWebKeyStoring {
    func load() throws -> String? { nil }
    func save(_ key: String) throws {}
    func delete() throws {}
}
