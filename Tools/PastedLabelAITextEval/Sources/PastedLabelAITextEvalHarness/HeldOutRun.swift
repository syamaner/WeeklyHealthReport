import FoodLabelPhotoCapture
import FoodLabelTextAIReading
import FoodLedgerApplication
import Foundation
import PastedLabelAITextEvalCore

/// The single held-out run (A4, T7; docs/pasted-label-ai-text-v1.md 5.5, revision 21). Every tuning
/// path refuses the sealed set, so this is its own runner, and `run` is the only public symbol of the
/// held-out path. It changes nothing `FreezePinTests` pins: it calls the frozen converter, the
/// frozen `ScoreCommand` and the shipped request builder through `SendCommand.send(textData:_:)`.
///
/// 1. **Closed configuration (item 2).** `prompt-v2` on `gpt-6.1-sol-azure-4k` (D35), scored by
///    `ScoreCommand` (scorer v5), in the one cell `v2__gpt-6.1-sol-azure-4k__a4-heldout`. The only
///    option is the private root; every path under it is fixed.
/// 2. **Seals over the bytes used (item 3).** Every text, transcription and collection record is
///    read once through one descriptor (`O_NOFOLLOW`, a regular file, its opened path exactly inside
///    its folder); the text seal and seal 2 are recomputed from those bytes as the reader v3
///    fresh-set step computes them, and the same bytes are converted, sent and scored.
/// 3. **Once (item 4).** Every refusal comes before anything is reserved or created. Then the output
///    folder and `a4-run.json` are created exclusively: from that moment the run has happened, and a
///    partial run is never resumed or repeated.
/// 4. **Spend (item 5).** The A3 ledger, so the $25 programme stop counts A3's spend; the A4 cell's
///    $5 stop; the ledger's $0.20 per-call cap; the standard retry rule; a cache of its own.
/// 5. **Journal and results (items 6 and 7).** Labels run one at a time in ID order; each row is
///    appended to `journal.jsonl` as it finishes. `finalise` (at the end, or after a crash) turns the
///    journal into `results.json` in promptfoo's export shape, with every label not run counted as
///    failed, plus the tier A subset. Tap latency runs from the start of the send to the end of the
///    score, in process (`in_process_send_to_score_end`).
/// 6. **Privacy (item 8).** What it returns and every refusal it throws are counts and fixed reasons:
///    no product, value, text, transcription, label ID or hash. The raw records stay in the private
///    output folder.
public enum HeldOutRun {
    // MARK: The frozen configuration (D35)

    static let promptVersion = OpenRouterPastedLabelAITextRequest.PromptVersion.v2
    static let route = PastedLabelAITextRoute.gpt61SolAzure4K
    static let cell = "v2__gpt-6.1-sol-azure-4k" + SendCommand.heldOutCellSuffix
    static let cellStop = Decimal(5)
    static let programmeStop = Decimal(25)
    static let labelCount = 24
    /// The held-out set's tier split (5.1): 9 tier A labels from new sites and 15 tier B. Tier is
    /// recorded in `source.json`, which no seal covers, so the split is checked against this.
    static let tierACount = 9
    static let tierBCount = 15
    /// The ledger limits A4 runs under (D25, T5), fixed here so an edited ledger cannot widen them.
    static let perCallCap = Decimal(string: "0.20")!
    static let ledgerTotal = Decimal(25)
    static let unknownCostCallsAllowed = 3
    static let attemptsPerLabel = SendRetryPolicy.maximumAttempts
    static let latencyMethod = "in_process_send_to_score_end"
    static let runSchema = "pasted-label-ai-text-a4-run-v1"
    static let providerID = "pasted-label-ai-text-heldout"
    /// A3's p90 tap latency (5.4), which counted the `send` and `score` process start-up as well.
    static let a3P90LatencySeconds = 15.0
    static let defaultPrivateRoot = "~/WHR-label-eval-private"

    /// The private root `PastedLabelAITextHeldOut` uses when none is given.
    package static var defaultPrivateRootURL: URL {
        URL(fileURLWithPath: (defaultPrivateRoot as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// The fixed places under the private root (item 2).
    package struct Paths: Sendable {
        package let root: URL
        package init(root: URL) { self.root = root.standardizedFileURL }
        var fresh: URL { root.appendingPathComponent("uk-english-v2/fresh", isDirectory: true) }
        var ledger: URL { root.appendingPathComponent("ai-text-v1/runs/a3/run/spend-ledger.json") }
        var runs: URL { root.appendingPathComponent("ai-text-v1/runs", isDirectory: true) }
        var output: URL { runs.appendingPathComponent("a4", isDirectory: true) }
        /// The A4 cell's own response cache, beside the output folder so it is never one A3 used.
        var cache: URL { runs.appendingPathComponent("a4-response-cache", isDirectory: true) }
        var runRecord: URL { output.appendingPathComponent("a4-run.json") }
        var journal: URL { output.appendingPathComponent("journal.jsonl") }
        var results: URL { output.appendingPathComponent("results.json") }
        var resultsTierA: URL { output.appendingPathComponent("results-tier-a.json") }
        var cases: URL { output.appendingPathComponent("cases", isDirectory: true) }
        var casesTierA: URL { output.appendingPathComponent("cases-tier-a", isDirectory: true) }
    }

    // MARK: Refusals (fixed reasons only)

    package enum Refusal: Error, Equatable, CustomStringConvertible {
        case outputExists, cacheExists, ledgerMissing, ledgerUnreadable, noA3Entry, ledgerHoldsA4Cell, stoppedInLedger, unknownCostStop
        case noRoomUnderCellStop, noRoomUnderProgrammeStop, overPerCallCap, promptBoundOverCeiling
        case freshFolderUnsafe, sealsMalformed, textSealMismatch, seal2Mismatch, wrongFileCount, idsDiffer, unsafeFile, unreadableFile
        case textNotUTF8, sourceRecordInvalid, textHashMismatch, conversionFailed, roundTripFailed
        case keyMissing, catalogueFailed, linkedFixedPath, ledgerLimitsChanged, tierSplitChanged, rootInsideCheckout, ledgerNegativeCharge,
             runRecordInvalid, outputUnwritable, runRecordMissing, casesIncomplete, badCommit

        package var description: String {
            switch self {
            case .outputExists: "the A4 output folder already exists: the held-out run happens once and is never resumed or repeated"
            case .cacheExists: "the A4 response cache already exists: the held-out run happens once"
            case .ledgerMissing: "the A3 spend ledger is missing"
            case .ledgerUnreadable: "the A3 spend ledger cannot be read as the text evaluation's ledger"
            case .noA3Entry: "the A3 spend ledger holds no A3 entry"
            case .ledgerHoldsA4Cell: "the spend ledger already holds an entry for the A4 cell: the held-out run happens once"
            case .stoppedInLedger: "the frozen model or the A4 cell is stopped in the spend ledger"
            case .unknownCostStop: "the spend ledger's unknown-cost stop is already reached"
            case .noRoomUnderCellStop: "the worst case of 24 labels times W times three attempts does not fit under the $5 cell stop"
            case .noRoomUnderProgrammeStop: "the worst case of 24 labels times W times three attempts does not fit under what is left of the $25 programme stop"
            case .overPerCallCap: "a label's W passes the ledger's per-call cap"
            case .promptBoundOverCeiling: "a label's prompt bound passes the prompt-token ceiling"
            case .freshFolderUnsafe: "the held-out folder, texts/, transcription/ or collection/ is missing or is not a plain directory"
            case .sealsMalformed: "seals.txt does not hold exactly one text, seal 1 and seal 2 line"
            case .textSealMismatch: "the texts do not match the text seal over 24 files"
            case .seal2Mismatch: "the transcriptions do not match seal 2 over 24 files"
            case .wrongFileCount: "the held-out folders do not hold 24 labels"
            case .idsDiffer: "texts/, transcription/ and collection/ do not hold the same label IDs"
            case .unsafeFile: "a held-out file is a symbolic link, is not a regular file, or opens outside its folder"
            case .unreadableFile: "a held-out file could not be read"
            case .textNotUTF8: "a held-out text is not UTF-8"
            case .sourceRecordInvalid: "a collection record is not a valid source.json for its label"
            case .textHashMismatch: "a text's SHA-256 is not the one its collection record holds"
            case .conversionFailed: "a transcription did not convert to a held-out case"
            case .roundTripFailed: "a held-out case did not round-trip to its transcription"
            case .linkedFixedPath: "a folder or file on the runner's fixed paths under the private root is a symbolic link or not of its expected kind"
            case .ledgerLimitsChanged: "the spend ledger's limits are not the $0.20 per call, $25 total and three unknown-cost calls A4 runs under"
            case .tierSplitChanged: "the collection records do not give the held-out set's 9 tier A and 15 tier B labels"
            case .rootInsideCheckout: "the private root is inside a git checkout: the held-out records stay outside every repository (T6)"
            case .ledgerNegativeCharge: "the spend ledger holds a negative charge, which would widen the room under the stops"
            case .runRecordInvalid: "a4-run.json does not list the 24 held-out label IDs: finalise writes nothing"
            case .keyMissing: "no OpenRouter key is available"
            case .catalogueFailed: "the frozen route's catalogue entry could not be confirmed"
            case .outputUnwritable: "the A4 output folder could not be created or written"
            case .runRecordMissing: "a4-run.json is missing or unreadable: there is no held-out run to finalise"
            case .casesIncomplete: "the A4 cases/ folder does not hold every label of the run"
            case .badCommit: "the commit is not a 40-character lowercase hex SHA"
            }
        }
    }

    /// What the run and `finalise` report: counts only.
    package struct Counts: Equatable, Sendable {
        package var labels = 0
        package var run = 0
        package var notRun = 0
        package var reachedConfirm = 0
        package var declined = 0
        package var failed = 0
        package var tierALabels = 0

        package var dictionary: [String: Int] {
            ["labels": labels, "run": run, "not_run": notRun, "reached_confirm": reachedConfirm, "declined": declined, "failed": failed,
             "tier_a_labels": tierALabels]
        }
    }

    /// The one line `PastedLabelAITextHeldOut` prints: the counts as JSON, sorted keys.
    package static func report(_ counts: [String: Int]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: counts, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The fixed reason for any error the run or `finalise` throws: a refusal's own description,
    /// and otherwise a reason that names nothing from the data.
    package static func reason(_ error: any Error) -> String {
        if let refusal = error as? Refusal { return refusal.description }
        return "the held-out run stopped on an unexpected error; the raw records stay in the private output folder"
    }

    // MARK: The run

    /// The single held-out run over the private root (default `~/WHR-label-eval-private`), with the
    /// commit it was built from, over `connection` (the live transport in `PastedLabelAITextHeldOut`,
    /// a fake one in tests). Returns the counts of `finalise`. Throws a refusal, with nothing reserved
    /// or created, until the output folder and `a4-run.json` exist.
    public static func run(privateRoot: URL, commit: String, connection: SendCommand.Connection, retry: SendRetryPolicy = .standard,
                           now: @escaping @Sendable () -> Date = { Date() }) async throws -> [String: Int] {
        let paths = Paths(root: privateRoot)
        try checkFixedPaths(paths)
        guard commit.count == 40, commit.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else { throw Refusal.badCommit }
        // Once: the output folder and its cache must not exist (lstat, so a link counts as existing).
        if exists(paths.output) { throw Refusal.outputExists }
        if exists(paths.cache) { throw Refusal.cacheExists }
        let ledger = try checkLedger(paths)
        let sealed = try readSealedSet(paths)
        let labels = sealed.labels
        // The key and the route's catalogue entry, so an outage refuses the run before it starts.
        let (transport, keys) = connection.resolved(labelID: labels.first?.id ?? "")
        guard let key = try? keys.load(), !key.isEmpty else { throw Refusal.keyMissing }
        let checker = OpenRouterPastedLabelAITextRouteChecker(transport: transport, clock: SystemLedgerClock(), reasoningBilledSeparately: true)
        guard let check = try? await checker.check(route),
              let prompt = Decimal(string: check.promptPrice, locale: Locale(identifier: "en_US_POSIX")),
              let completion = Decimal(string: check.completionPrice, locale: Locale(identifier: "en_US_POSIX")) else {
            throw Refusal.catalogueFailed
        }
        let prices = LabelPhotoSpendPolicy.Prices(promptPerToken: prompt, completionPerToken: completion, reasoningBilledSeparately: true,
                                                  maxOutputTokens: route.maxOutputTokens)
        try checkRoom(labels, prices: prices, ledger: ledger)
        // From here the run has happened.
        try start(paths, sealed: sealed, commit: commit, now: now)
        let tap = { (id: String) in
            SendCommand.Tap(labelID: id, route: route, cell: cell, ledgerURL: paths.ledger, cacheDirectory: paths.cache, connection: connection,
                            cellStop: cellStop, programmeStop: programmeStop, reasoningBilledSeparately: true, timeout: 60, retry: retry,
                            promptVersion: promptVersion, freshRun: nil)
        }
        for label in labels {
            let row = await runLabel(label, tap: tap(label.id), now: now)
            try appendJournal(paths, row)
        }
        return try finalise(paths).dictionary
    }

    /// The refusals `run` makes before the key and the catalogue, with nothing reserved, created or
    /// sent: the output folder and cache are absent, the ledger is the A3 one with no A4 entry, and
    /// the held-out set matches its seals and converts. Returns counts only.
    package static func check(privateRoot: URL) throws -> [String: Int] {
        let paths = Paths(root: privateRoot)
        try checkFixedPaths(paths)
        if exists(paths.output) { throw Refusal.outputExists }
        if exists(paths.cache) { throw Refusal.cacheExists }
        _ = try checkLedger(paths)
        let labels = try readSealedSet(paths).labels
        return ["labels": labels.count, "tier_a_labels": labels.filter { $0.evalCase.tier == "A" }.count]
    }

    /// One label: send, then score, in process. A send or score that throws gives a row with no
    /// named scores, which the statistics script counts as failed.
    static func runLabel(_ label: SealedLabel, tap: SendCommand.Tap, now: @Sendable () -> Date) async -> [String: Any] {
        let started = now()
        var send: SendCommand.Output?
        do {
            let output = try await SendCommand.send(textData: label.text, tap)
            send = output
            let scored = try ScoreCommand.run(evalCase: label.evalCase, textData: label.text, send: output)
            var named = scored.namedScores
            named["tap_latency_seconds"] = max(0, now().timeIntervalSince(started))
            if let attempt = output.latencySeconds { named["attempt_latency_seconds"] = attempt }
            return resultRow(label.id, send: output, started: started, grading: (scored.pass, scored.f1, named), error: nil)
        } catch {
            return resultRow(label.id, send: send, started: started, grading: nil, error: send == nil ? "send_failed" : "score_failed")
        }
    }

    // MARK: Results (item 6)

    /// A row in the shape the frozen statistics script reads from promptfoo's export.
    static func resultRow(_ id: String, send: SendCommand.Output?, started: Date?, grading: (pass: Bool, f1: Double, named: [String: Double])?,
                          error: String?) -> [String: Any] {
        var row: [String: Any] = [
            "provider": ["id": providerID, "label": route.candidateID],
            "prompt": ["label": promptVersion.rawValue, "raw": "{{label_id}}"],
            "vars": ["label_id": id],
        ]
        if let send, let output = sendRecord(send, started: started) { row["response"] = ["output": output] }
        if let grading {
            row["success"] = grading.pass
            row["score"] = grading.f1
            row["namedScores"] = grading.named
            row["gradingResult"] = ["pass": grading.pass, "score": grading.f1, "namedScores": grading.named]
        } else {
            row["success"] = false
            row["score"] = 0
            row["namedScores"] = [String: Double]()
            row["gradingResult"] = NSNull()
            row["error"] = error ?? "failed"
        }
        return row
    }

    /// The send record as provider.js returns it for `response.output`: the send JSON with
    /// `tap_started_at_ms`.
    static func sendRecord(_ send: SendCommand.Output, started: Date?) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(send), var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let started { object["tap_started_at_ms"] = Int64((started.timeIntervalSince1970 * 1000).rounded(.down)) }
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    /// Builds `results.json`, `results-tier-a.json` and `cases-tier-a/` from `a4-run.json`, the
    /// journal and `cases/`, after the run or after a crash. Every label not in the journal (or whose
    /// line was cut off) is a row with no named scores, so it counts as failed. Idempotent: the same
    /// inputs give the same bytes.
    package static func finalise(_ paths: Paths) throws -> Counts {
        guard let recordData = FileManager.default.contents(atPath: paths.runRecord.path),
              let record = (try? JSONSerialization.jsonObject(with: recordData)) as? [String: Any],
              record["schema"] as? String == runSchema, let ids = record["label_ids"] as? [String], !ids.isEmpty else {
            throw Refusal.runRecordMissing
        }
        // The IDs name files, so they are checked before any path is built from them (Qodo, A4).
        guard ids.count == labelCount, Set(ids).count == ids.count, ids == ids.sorted(), ids.allSatisfy(ConvertCommand.isSafeLabelID) else {
            throw Refusal.runRecordInvalid
        }
        // The tiers the run used, recorded at its start, select tier A; a case whose tier differs is refused (Qodo, A4).
        guard let recordedTiers = record["tiers"] as? [String: String], Set(recordedTiers.keys) == Set(ids),
              recordedTiers.values.filter({ $0 == "A" }).count == tierACount, recordedTiers.values.filter({ $0 == "B" }).count == tierBCount else {
            throw Refusal.runRecordInvalid
        }
        // Every folder finalise reads or writes is a plain directory, never a link (Qodo, A4).
        try checkFixedPaths(paths)
        guard isPlainDirectory(paths.runs), isPlainDirectory(paths.output) else { throw Refusal.linkedFixedPath }
        for folder in [paths.cases, paths.casesTierA] where exists(folder) && !isPlainDirectory(folder) { throw Refusal.linkedFixedPath }
        var journal: [String: [String: Any]] = [:]
        if let data = FileManager.default.contents(atPath: paths.journal.path) {
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let row = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                      let id = (row["vars"] as? [String: Any])?["label_id"] as? String, ids.contains(id), journal[id] == nil else { continue }
                journal[id] = row
            }
        }
        var cases: [String: EvalCase] = [:]
        for id in ids {
            guard let data = try? readInside(paths.cases, "\(id).json"), let evalCase = try? EvalCase.decode(data), evalCase.labelID == id else { continue }
            cases[id] = evalCase
        }
        // A crash while `start` wrote cases/ leaves it short: the cases are rebuilt from the sealed
        // set, under every seal check, so the run can still be finalised (Qodo, A4).
        if cases.count != ids.count {
            let sealed = try readSealedSet(paths)
            guard sealed.labels.map(\.id) == ids else { throw Refusal.casesIncomplete }
            do {
                if !exists(paths.cases) { try FileManager.default.createDirectory(at: paths.cases, withIntermediateDirectories: false) }
                for label in sealed.labels where cases[label.id] == nil {
                    try label.evalCase.canonicalJSON().write(to: paths.cases.appendingPathComponent("\(label.id).json"), options: .atomic)
                    cases[label.id] = label.evalCase
                }
            } catch {
                throw Refusal.outputUnwritable
            }
        }
        let rows = ids.map { journal[$0] ?? resultRow($0, send: nil, started: nil, grading: nil, error: "not_run") }
        guard ids.allSatisfy({ cases[$0]?.tier == recordedTiers[$0] }) else { throw Refusal.tierSplitChanged }
        let tierA = ids.filter { recordedTiers[$0] == "A" }
        let tierARows = rows.filter { tierA.contains((($0["vars"] as? [String: Any])?["label_id"] as? String) ?? "") }
        do {
            try writeResults(rows, to: paths.results)
            try writeResults(tierARows, to: paths.resultsTierA)
            try FileManager.default.createDirectory(at: paths.casesTierA, withIntermediateDirectories: true)
            let wanted = Set(tierA.map { "\($0).json" })
            for name in try FileManager.default.contentsOfDirectory(atPath: paths.casesTierA.path) where !wanted.contains(name) {
                // Only a regular file this folder holds is removed; anything else stops finalise.
                var status = stat()
                let url = paths.casesTierA.appendingPathComponent(name)
                guard lstat(url.path, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { throw Refusal.linkedFixedPath }
                try FileManager.default.removeItem(at: url)
            }
            for id in tierA {
                try cases[id]!.canonicalJSON().write(to: paths.casesTierA.appendingPathComponent("\(id).json"), options: .atomic)
            }
        } catch {
            throw Refusal.outputUnwritable
        }
        var counts = Counts()
        counts.labels = ids.count
        counts.run = journal.count
        counts.notRun = ids.count - journal.count
        counts.tierALabels = tierA.count
        for row in rows {
            let named = (row["namedScores"] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
            if named["reached_confirm"] == 1 { counts.reachedConfirm += 1 } else if named["declined"] == 1 { counts.declined += 1 } else { counts.failed += 1 }
        }
        return counts
    }

    static func writeResults(_ rows: [[String: Any]], to url: URL) throws {
        let object: [String: Any] = ["results": ["results": rows],
                                     "a4": ["schema": runSchema, "latency_method": latencyMethod, "cell": cell,
                                            "latency_deviation": "in process, so lower than A3's tap latency by the send and score process start-up; A3's p90 was 15.0 s"]]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
        try data.write(to: url, options: .atomic)
    }

    static func appendJournal(_ paths: Paths, _ row: [String: Any]) throws {
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes]) else { throw Refusal.outputUnwritable }
        let descriptor = open(paths.journal.path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Refusal.outputUnwritable }
        defer { close(descriptor) }
        let line = data + Data("\n".utf8)
        let written = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == line.count, fsync(descriptor) == 0 else { throw Refusal.outputUnwritable }
    }

    // MARK: Once (item 4)

    static func exists(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0
    }

    struct LedgerState {
        let cellCharge: Decimal
        let programmeCharge: Decimal
        let perCall: Decimal?
    }

    /// The A3 ledger must exist, be the text evaluation's, hold an A3 entry and no A4 entry, and
    /// leave the frozen model and the A4 cell unstopped.
    static func checkLedger(_ paths: Paths) throws -> LedgerState {
        guard exists(paths.ledger) else { throw Refusal.ledgerMissing }
        let book: EvalSpendLedger
        let object: [String: Any]
        do {
            book = try EvalSpendLedger(url: paths.ledger, cellStop: cellStop, programmeStop: programmeStop)
            object = try book.load()
        } catch {
            throw Refusal.ledgerUnreadable
        }
        let entries = EvalSpendLedger.textEntries(object)
        if entries.contains(where: { EvalSpendLedger.charge($0) < 0 }) { throw Refusal.ledgerNegativeCharge }
        if entries.contains(where: { SendCommand.isHeldOutCell(($0["cell"] as? String) ?? "") }) { throw Refusal.ledgerHoldsA4Cell }
        guard entries.contains(where: { !(($0["cell"] as? String) ?? "").isEmpty }) else { throw Refusal.noA3Entry }
        let stopped = Set(object["stopped_models"] as? [String] ?? [])
        if stopped.contains(route.model) || stopped.contains(EvalSpendLedger.cellKey(cell)) { throw Refusal.stoppedInLedger }
        let limits = object["limits"] as? [String: Any] ?? [:]
        let total = (limits["total_usd"] as? String).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
            ?? (limits["total_usd"] as? NSNumber).flatMap { Decimal(string: $0.stringValue, locale: Locale(identifier: "en_US_POSIX")) }
        guard EvalSpendLedger.perCall(limits) == perCallCap, total == ledgerTotal,
              (limits["unknown_cost_calls_allowed"] as? Int) == unknownCostCallsAllowed else {
            throw Refusal.ledgerLimitsChanged
        }
        let allowed = unknownCostCallsAllowed
        if EvalSpendLedger.unknownCount(object["entries"] as? [[String: Any]] ?? []) >= allowed { throw Refusal.unknownCostStop }
        return LedgerState(cellCharge: entries.filter { $0["cell"] as? String == cell }.map(EvalSpendLedger.charge).reduce(0, +),
                           programmeCharge: entries.map(EvalSpendLedger.charge).reduce(0, +), perCall: EvalSpendLedger.perCall(limits))
    }

    /// The worst case, every label's W times three attempts, must fit under the $5 cell stop and
    /// what is left of the $25 programme stop, and no W may pass the per-call cap.
    static func checkRoom(_ labels: [SealedLabel], prices: LabelPhotoSpendPolicy.Prices, ledger: LedgerState) throws {
        let request: OpenRouterPastedLabelAITextRequest
        do { request = try OpenRouterPastedLabelAITextRequest(route: route, promptVersion: promptVersion) } catch { throw Refusal.catalogueFailed }
        var total = Decimal(0)
        for label in labels {
            guard let w = PastedLabelAITextSpendPolicy.worstCase(prices, reasoningLimit: route.reasoningTokenBound,
                                                                 promptTokenBound: request.promptTokenBound(label.textString)) else {
                throw Refusal.promptBoundOverCeiling
            }
            if w > perCallCap { throw Refusal.overPerCallCap }
            total += w * Decimal(attemptsPerLabel)
        }
        if ledger.cellCharge + total > cellStop { throw Refusal.noRoomUnderCellStop }
        if ledger.programmeCharge + total > programmeStop { throw Refusal.noRoomUnderProgrammeStop }
    }

    /// Creates the output folder and `a4-run.json` exclusively, then `cases/` and an empty journal.
    static func start(_ paths: Paths, sealed: SealedSet, commit: String, now: @Sendable () -> Date) throws {
        let labels = sealed.labels
        do { try FileManager.default.createDirectory(at: paths.runs, withIntermediateDirectories: true) } catch { throw Refusal.outputUnwritable }
        guard mkdir(paths.output.path, 0o700) == 0 else { throw errno == EEXIST ? Refusal.outputExists : Refusal.outputUnwritable }
        let versions = PastedLabelAITextReader.versions
        let record: [String: Any] = [
            "schema": runSchema,
            "commit": commit,
            "started_at": SendCommand.timestamp(now()),
            "latency_method": latencyMethod,
            "latency_deviation": "tap latency runs from the start of the send to the end of the score in process; A3 also counted the send and score process start-up (p90 \(a3P90LatencySeconds) s)",
            "configuration": [
                "prompt_version": promptVersion.rawValue, "instruction_version": promptVersion.instructionVersion,
                "instruction_sha256": promptVersion.instructionSHA256, "wire_schema_sha256": OpenRouterPastedLabelAITextRequest.wireSchemaSHA256,
                "route_version": route.version, "route_candidate": route.candidateID, "model": route.model, "endpoint": route.endpoint,
                "provider_name": route.providerName, "max_output_tokens": route.maxOutputTokens, "reasoning_token_bound": route.reasoningTokenBound,
                "scorer": PastedLabelAITextScorer.version, "cell": cell, "cell_stop_usd": "\(cellStop)", "programme_stop_usd": "\(programmeStop)",
                "max_attempts": attemptsPerLabel, "bar": "bar-v2.json",
                "reader_versions": ["wire_schema": versions.wireSchema, "mapping": versions.mapping, "locator": versions.locator,
                                    "vocabulary": versions.vocabulary, "detector": versions.detector, "attention": versions.attention,
                                    "format": versions.format, "gate": versions.gate, "arithmetic": versions.arithmetic,
                                    "conversion": versions.conversion],
            ] as [String: Any],
            "seals": sealed.seals.mapValues { ["sha256": $0.hash, "files": $0.files] as [String: Any] },
            "label_ids": labels.map(\.id),
            // Tier is not under a seal (5.1), so the assignment the run used is recorded with it.
            "tiers": Dictionary(uniqueKeysWithValues: labels.map { ($0.id, $0.evalCase.tier ?? "") }),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            throw Refusal.outputUnwritable
        }
        try createExclusive(paths.runRecord, data + Data("\n".utf8))
        do {
            try FileManager.default.createDirectory(at: paths.cases, withIntermediateDirectories: false)
            for label in labels { try label.evalCase.canonicalJSON().write(to: paths.cases.appendingPathComponent("\(label.id).json")) }
        } catch {
            throw Refusal.outputUnwritable
        }
        try createExclusive(paths.journal, Data())
    }

    static func createExclusive(_ url: URL, _ data: Data) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw errno == EEXIST ? Refusal.outputExists : Refusal.outputUnwritable }
        defer { close(descriptor) }
        let written = data.withUnsafeBytes { data.isEmpty ? 0 : write(descriptor, $0.baseAddress, $0.count) }
        guard written == data.count, fsync(descriptor) == 0 else { throw Refusal.outputUnwritable }
    }

    // MARK: Seals over the bytes used (item 3)

    /// One held-out label: the bytes read once, and the case converted from them.
    struct SealedLabel {
        let id: String
        let text: Data
        let textString: String
        let evalCase: EvalCase
    }

    struct SourceRecord: Decodable {
        let labelID: String
        let tier: String
        let copyMethod: String
        let textSHA256: String
        enum CodingKeys: String, CodingKey { case tier, labelID = "label_id", copyMethod = "copy_method", textSHA256 = "text_sha256" }
    }

    struct SealLine {
        let hash: String
        let files: Int
    }

    /// The labels in ID order, and the three seal lines they were checked against.
    struct SealedSet {
        let labels: [SealedLabel]
        let seals: [String: SealLine]
    }

    /// A directory that is itself a directory, not a link to one.
    /// Every folder on the fixed paths below the private root is a plain directory and the ledger a
    /// regular file, never a symbolic link, so the run reads and writes only under the root it was
    /// given (Qodo, A4). The output folder and cache must not exist at all; that is checked apart.
    static func checkFixedPaths(_ paths: Paths) throws {
        let root = paths.root
        // The private root and every ancestor, links resolved, hold no `.git` (Qodo, A4; T6).
        // Walked as path strings, which stop at "/" (a URL's parent of "/" is "/..", which never ends).
        var ancestor = SendCommand.resolved(root.path) ?? root.path
        while true {
            if exists(URL(fileURLWithPath: ancestor, isDirectory: true).appendingPathComponent(".git")) { throw Refusal.rootInsideCheckout }
            let parent = (ancestor as NSString).deletingLastPathComponent
            if parent == ancestor || parent.isEmpty { break }
            ancestor = parent
        }
        let folders = ["", "uk-english-v2", "uk-english-v2/fresh", "ai-text-v1", "ai-text-v1/runs", "ai-text-v1/runs/a3", "ai-text-v1/runs/a3/run"]
        for folder in folders where !isPlainDirectory(folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)) {
            throw Refusal.linkedFixedPath
        }
        var status = stat()
        guard lstat(paths.ledger.path, &status) == 0 else { throw Refusal.ledgerMissing }
        guard status.st_mode & S_IFMT == S_IFREG else { throw Refusal.linkedFixedPath }
    }

    static func isPlainDirectory(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0 && status.st_mode & S_IFMT == S_IFDIR
    }

    /// A file's bytes through one descriptor, refused unless its opened path is exactly `name` in
    /// the resolved `folder`.
    static func readInside(_ folder: URL, _ name: String) throws -> Data {
        guard let resolvedFolder = SendCommand.resolved(folder.path) else { throw Refusal.unsafeFile }
        let expected = resolvedFolder + "/" + name
        var status = stat()
        guard lstat(folder.appendingPathComponent(name).path, &status) == 0 else { throw Refusal.unreadableFile }
        guard status.st_mode & S_IFMT == S_IFREG else { throw Refusal.unsafeFile }
        return try SendCommand.readSingleDescriptor(atPath: expected, unreadable: Refusal.unsafeFile) { opened in
            guard opened == expected else { throw Refusal.unsafeFile }
        }
    }

    /// The listing seal of 12.2: the SHA-256 of `<sha256>  <prefix>/<name>\n` lines sorted by name.
    static func bundleSHA256(_ files: [(name: String, data: Data)], prefix: String) -> String {
        let listing = files.sorted { $0.name < $1.name }.map { "\(EvalCase.sha256($0.data))  \(prefix)/\($0.name)\n" }.joined()
        return EvalCase.sha256(Data(listing.utf8))
    }

    static func parseSeals(_ data: Data) throws -> [String: SealLine] {
        guard let text = String(data: data, encoding: .utf8) else { throw Refusal.sealsMalformed }
        var seals: [String: SealLine] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, ["text", "seal1", "seal2"].contains(parts[0]), seals[parts[0]] == nil, EvalCase.isSHA256Hex(parts[1]),
                  let files = Int(parts[2]), files > 0, !parts[3].isEmpty else {
                throw Refusal.sealsMalformed
            }
            seals[parts[0]] = SealLine(hash: parts[1], files: files)
        }
        guard seals.count == 3 else { throw Refusal.sealsMalformed }
        return seals
    }

    /// Reads the sealed set once and checks it: the seals, the IDs, the collection records, the
    /// conversion and the round trip. Returns the labels in ID order.
    static func readSealedSet(_ paths: Paths) throws -> SealedSet {
        let fresh = paths.fresh
        let texts = fresh.appendingPathComponent("texts", isDirectory: true)
        let transcription = fresh.appendingPathComponent("transcription", isDirectory: true)
        let collection = fresh.appendingPathComponent("collection", isDirectory: true)
        guard isPlainDirectory(fresh), isPlainDirectory(texts), isPlainDirectory(transcription), isPlainDirectory(collection) else {
            throw Refusal.freshFolderUnsafe
        }
        let seals = try parseSeals(try readInside(fresh, "seals.txt"))
        func names(_ folder: URL, suffix: String) throws -> [String] {
            guard let all = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { throw Refusal.unreadableFile }
            return all.filter { $0.hasSuffix(suffix) }.sorted()
        }
        let textNames = try names(texts, suffix: ".txt")
        let transcriptionNames = try names(transcription, suffix: ".json")
        // A label's collection folder is a subfolder holding a `source.json`; the collection folder
        // also keeps the skip log, search screens and recheck notes, which are not labels.
        let collectionIDs = try (FileManager.default.contentsOfDirectory(atPath: collection.path)).filter { name in
            !name.hasPrefix(".") && exists(collection.appendingPathComponent(name, isDirectory: true).appendingPathComponent("source.json"))
        }.sorted()
        let textFiles = try textNames.map { (name: $0, data: try readInside(texts, $0)) }
        let transcriptionFiles = try transcriptionNames.map { (name: $0, data: try readInside(transcription, $0)) }
        // The seals, over exactly the bytes read.
        guard let textSeal = seals["text"], let seal2 = seals["seal2"] else { throw Refusal.sealsMalformed }
        guard textFiles.count == labelCount, textSeal.files == labelCount, bundleSHA256(textFiles, prefix: "texts") == textSeal.hash else {
            throw Refusal.textSealMismatch
        }
        guard transcriptionFiles.count == labelCount, seal2.files == labelCount,
              bundleSHA256(transcriptionFiles, prefix: "transcription") == seal2.hash else {
            throw Refusal.seal2Mismatch
        }
        let textIDs = textNames.map { String($0.dropLast(".txt".count)) }
        let transcriptionIDs = transcriptionNames.map { String($0.dropLast(".json".count)) }
        guard textIDs == transcriptionIDs, textIDs == collectionIDs else { throw Refusal.idsDiffer }
        guard textIDs.count == labelCount, textIDs.allSatisfy(ConvertCommand.isSafeLabelID) else { throw Refusal.wrongFileCount }
        var labels: [SealedLabel] = []
        for (index, id) in textIDs.enumerated() {
            let text = textFiles[index].data
            let source = transcriptionFiles[index].data
            let folder = collection.appendingPathComponent(id, isDirectory: true)
            guard isPlainDirectory(folder) else { throw Refusal.unsafeFile }
            guard let record = try? JSONDecoder().decode(SourceRecord.self, from: try readInside(folder, "source.json")),
                  record.labelID == id, !record.copyMethod.isEmpty else {
                throw Refusal.sourceRecordInvalid
            }
            let textSHA = EvalCase.sha256(text)
            guard record.textSHA256 == textSHA else { throw Refusal.textHashMismatch }
            guard let textString = String(data: text, encoding: .utf8) else { throw Refusal.textNotUTF8 }
            let evalCase: EvalCase
            do {
                evalCase = try EvalCaseConverter.convert(source, metadata: .init(set: .ukV2Fresh, tier: record.tier, copyMethod: record.copyMethod,
                                                                                 textSHA256: textSHA))
            } catch {
                throw Refusal.conversionFailed
            }
            guard evalCase.labelID == id, evalCase.role == .heldOut else { throw Refusal.conversionFailed }
            do { try EvalCaseConverter.verifyRoundTrip(evalCase, source: source) } catch { throw Refusal.roundTripFailed }
            labels.append(SealedLabel(id: id, text: text, textString: textString, evalCase: evalCase))
        }
        let tierA = labels.filter { $0.evalCase.tier == "A" }.count
        let tierB = labels.filter { $0.evalCase.tier == "B" }.count
        guard tierA == tierACount, tierB == tierBCount else { throw Refusal.tierSplitChanged }
        return SealedSet(labels: labels, seals: seals)
    }
}
