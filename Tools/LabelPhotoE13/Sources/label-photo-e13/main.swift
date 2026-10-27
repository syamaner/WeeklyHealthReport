import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation

// E13 qualification runner (docs/label-photo-ai-prefill-v1.md E13 and 17.21).
//
// Every photo goes through exactly what the app does after the user taps Read label with AI:
// `ImageIOLabelImagePreparer` on the whole photo (E3; the evaluation photos are already panel
// photos), then `LabelPhotoReadSession` over `OpenRouterLabelPhotoAttempt`,
// `OpenRouterLabelRouteChecker` and the live `OpenRouterTransport`, with the app's retry policy
// (E11, `Retry-After` honoured), per-tap $0.05 limit and catalogue check. The only difference is
// the spend ledger: an in-memory one that starts each photo on a fresh day, because the run reads
// more photos than the app's 30-a-day limit. The run's own limits replace it: a hard total stop,
// and a pause point at which the run stops for a report.
//
// The OpenRouter key is read from `--env-file` (only the `OPENROUTER_API_KEY` line) into this
// process's memory. It is never printed, logged or written. Outputs, including the model's
// answers, go only to `--out`, which must be outside the repository.
//
//     swift run --package-path Tools/LabelPhotoE13 label-photo-e13 --cases <cases.json> \
//         --out ~/WHR-label-eval-private/runs/e13-v1 --env-file ~/git/PacePrompt/.env --stop-usd 10 --pause-usd 5
//
// `--only ID,ID,...` re-runs just those case ids, and then `--records NAME.jsonl` is required and
// must not be the full run's `e13-records.jsonl` (compared ignoring case, and by file identity once
// resolved), so the full run's records stay intact. `--stop-usd` and `--pause-usd` count the full
// run's charges as well as this file's, so the stop is a true total.

struct Arguments {
    var cases: URL?
    var out: URL?
    var envFile: URL?
    var stopUSD = Decimal(10)
    var pauseUSD = Decimal(5)
    var limit = Int.max
    var only: Set<String>?
    var records = "e13-records.jsonl"

    static func parse(_ list: [String]) -> Arguments? {
        var arguments = Arguments()
        var iterator = list.makeIterator()
        while let name = iterator.next() {
            guard let value = iterator.next() else { return nil }
            switch name {
            case "--cases": arguments.cases = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            case "--out": arguments.out = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            case "--env-file": arguments.envFile = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            case "--stop-usd": guard let v = Decimal(string: value), v > 0, v <= 10 else { return nil }; arguments.stopUSD = v
            case "--pause-usd": guard let v = Decimal(string: value), v > 0 else { return nil }; arguments.pauseUSD = v
            case "--limit": guard let v = Int(value), v > 0 else { return nil }; arguments.limit = v
            case "--only":
                let ids = Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                guard !ids.isEmpty else { return nil }
                arguments.only = ids
            case "--records":
                guard value.hasSuffix(".jsonl"), !value.contains("/"), !value.hasPrefix(".") else { return nil }
                arguments.records = value
            default: return nil
            }
        }
        // A partial re-run never writes into the full run's records.
        if arguments.only != nil, arguments.records.lowercased() == fullRunRecords { return nil }
        return arguments.cases != nil && arguments.out != nil && arguments.envFile != nil ? arguments : nil
    }
}

let fullRunRecords = "e13-records.jsonl"

/// Whether two paths name the same file: by file identity when both exist (a case-insensitive
/// volume, a symbolic or hard link), otherwise by resolved path ignoring case.
func sameFile(_ a: URL, _ b: URL) -> Bool {
    let ra = a.resolvingSymlinksInPath(), rb = b.resolvingSymlinksInPath()
    if let ia = try? ra.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
       let ib = try? rb.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier {
        return ia.isEqual(ib)
    }
    return ra.standardizedFileURL.path.lowercased() == rb.standardizedFileURL.path.lowercased()
}

struct Case: Codable {
    let id: String
    let split: String
    let path: String
    let sha256: String
}

/// The key from one dotenv line, held in memory only.
struct EnvironmentKey: FoodWebKeyStoring {
    let key: String?
    init(file: URL) {
        var found: String?
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            for raw in text.split(whereSeparator: \.isNewline) {
                var line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
                guard line.hasPrefix("OPENROUTER_API_KEY=") else { continue }
                var value = String(line.dropFirst("OPENROUTER_API_KEY=".count)).trimmingCharacters(in: .whitespaces)
                if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                    value = String(value.dropFirst().dropLast())
                }
                found = value
            }
        }
        key = found
    }
    func load() throws -> String? { key }
    func save(_ key: String) throws {}
    func delete() throws {}
}

/// The app's ledger semantics for one photo at a time: each photo starts on a fresh day.
final class PerPhotoLedger: LabelPhotoSpendLedger, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LabelPhotoSpendPolicy.Stored = .absent
    func reset() { lock.withLock { stored = .absent } }
    func load() -> LabelPhotoSpendPolicy.Stored { lock.withLock { stored } }
    @discardableResult
    func update(_ transform: (LabelPhotoSpendPolicy.Stored) throws -> LabelPhotoSpendPolicy.Day) throws -> LabelPhotoSpendPolicy.Day {
        try lock.withLock {
            let day = try transform(stored)
            stored = .day(day)
            return day
        }
    }
}

/// Wraps the live transport and keeps, per POST, only the reply's identity, usage, status and
/// timing (never the content), so dated slugs and per-attempt cost are visible even when the
/// attempt's own checks reject the reply.
final class RecordingTransport: LabelPhotoHTTPTransporting, @unchecked Sendable {
    struct Attempt: Codable {
        var seconds: Double
        var status: Int?
        var error: String?
        var model: String?
        var provider: String?
        var generationID: String?
        var finishReason: String?
        var costUSD: String?
        var promptTokens: Int?
        var completionTokens: Int?
        var reasoningTokens: Int?
        var retryAfter: String?
        var exceededLimit: Bool?
    }

    private let inner: OpenRouterTransport
    private let lock = NSLock()
    private var attempts: [Attempt] = []
    private(set) var catalogueGets = 0

    init(_ inner: OpenRouterTransport) { self.inner = inner }

    func take() -> [Attempt] { lock.withLock { defer { attempts = [] }; return attempts } }

    func send(_ request: LabelPhotoHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse {
        guard request.method == "POST" else {
            lock.withLock { catalogueGets += 1 }
            return try await inner.send(request, timeout: timeout, maximumBodyBytes: maximumBodyBytes)
        }
        let started = Date()
        do {
            let response = try await inner.send(request, timeout: timeout, maximumBodyBytes: maximumBodyBytes)
            var record = Attempt(seconds: Date().timeIntervalSince(started), status: response.status)
            record.retryAfter = response.header("retry-after")
            record.exceededLimit = response.exceededLimit
            if let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] {
                record.model = object["model"] as? String
                record.provider = object["provider"] as? String
                record.generationID = object["id"] as? String
                record.finishReason = ((object["choices"] as? [[String: Any]])?.first)?["finish_reason"] as? String
                if let usage = object["usage"] as? [String: Any] {
                    record.costUSD = (usage["cost"] as? NSNumber).map { $0.stringValue }
                    record.promptTokens = (usage["prompt_tokens"] as? NSNumber)?.intValue
                    record.completionTokens = (usage["completion_tokens"] as? NSNumber)?.intValue
                    record.reasoningTokens = ((usage["completion_tokens_details"] as? [String: Any])?["reasoning_tokens"] as? NSNumber)?.intValue
                }
            }
            lock.withLock { attempts.append(record) }
            return response
        } catch {
            var record = Attempt(seconds: Date().timeIntervalSince(started))
            record.error = "\(error)"
            lock.withLock { attempts.append(record) }
            throw error
        }
    }
}

struct Record: Codable {
    let id: String
    let split: String
    let sourceSHA256: String
    var preparedWidth: Int?
    var preparedHeight: Int?
    var preparedBytes: Int?
    var preparedSHA256: String?
    var prepareError: String?
    var outcome: String
    var failure: String?
    var wireText: String?
    var model: String?
    var provider: String?
    var generationID: String?
    var finishReason: String?
    var attemptsReported: Int?
    var costUSD: String?
    var promptTokens: Int?
    var completionTokens: Int?
    var reasoningTokens: Int?
    var tapSeconds: Double?
    var chargedUSD: String
    var attempts: [RecordingTransport.Attempt]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func decimal(_ text: String?) -> Decimal? { text.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }

guard let arguments = Arguments.parse(Array(CommandLine.arguments.dropFirst())) else {
    fail("usage: label-photo-e13 --cases FILE --out DIR --env-file FILE [--stop-usd N<=10] [--pause-usd N] [--limit N] "
        + "[--only ID,ID,... --records NAME.jsonl (not e13-records.jsonl)]")
}
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path
let outDirectory = arguments.out!.standardizedFileURL
guard !outDirectory.path.hasPrefix(repository + "/") else { fail("--out must be outside the repository") }
try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
let recordsURL = outDirectory.appendingPathComponent(arguments.records)
let fullRunURL = outDirectory.appendingPathComponent(fullRunRecords)
let separateRecords = !sameFile(recordsURL, fullRunURL)
if arguments.only != nil, !separateRecords { fail("--records resolves to the full run's \(fullRunRecords); choose another file") }

let keys = EnvironmentKey(file: arguments.envFile!)
guard let key = keys.key, FoodWebKeySyntax.isValid(key) else { fail("no well-formed OPENROUTER_API_KEY in --env-file") }

let allCases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: arguments.cases!))
if let only = arguments.only {
    let unknown = only.subtracting(allCases.map(\.id))
    guard unknown.isEmpty else { fail("--only names \(unknown.count) id(s) not in --cases: \(unknown.sorted().joined(separator: ", "))") }
}
let cases = arguments.only.map { only in allCases.filter { only.contains($0.id) } } ?? allCases
var done = Set<String>()
var spent = Decimal(0)
if let existing = try? String(contentsOf: recordsURL, encoding: .utf8) {
    for line in existing.split(whereSeparator: \.isNewline) {
        guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)) else { fail("unreadable existing record; refusing to continue") }
        done.insert(record.id)
        spent += decimal(record.chargedUSD) ?? LabelPhotoSpendPolicy.perTapLimit
    }
}
// A partial re-run's stops count the full run's charges too (invariant review of #329).
if separateRecords, let full = try? String(contentsOf: fullRunURL, encoding: .utf8) {
    for line in full.split(whereSeparator: \.isNewline) {
        guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)) else { fail("unreadable full-run record; refusing to continue") }
        spent += decimal(record.chargedUSD) ?? LabelPhotoSpendPolicy.perTapLimit
    }
}

let clock = SystemLedgerClock()
let live = OpenRouterTransport()
let transport = RecordingTransport(live)
let checker = OpenRouterLabelRouteChecker(transport: transport, clock: clock, reasoningBilledSeparately: true)

// The free, keyless catalogue check first: the route must be admitted and W known before any spend.
let check: LabelPhotoManifest.CatalogueCheck
do { check = try await checker.check(LabelPhotoRoute.current) } catch { fail("catalogue check failed: \(error); nothing sent") }
guard let prices = LabelPhotoReadSession.prices(check, route: LabelPhotoRoute.current, reasoningBilledSeparately: true) else {
    fail("the catalogue does not admit the route; nothing sent")
}
let worstCase = LabelPhotoSpendPolicy.worstCase(prices)
FileHandle.standardError.write(Data("route \(LabelPhotoRoute.current.endpoint) admitted; W \(worstCase) USD; spent so far \(spent) USD; \(done.count) done\n".utf8))

let ledger = PerPhotoLedger()
let session = LabelPhotoReadSession(checker: checker, attempter: OpenRouterLabelPhotoAttempt(transport: transport, keys: keys,
                                                                                           request: try OpenRouterLabelPhotoRequest()),
                                    ledger: ledger, keys: keys, clock: clock, calendar: Calendar(identifier: .gregorian),
                                    sleeper: TaskLabelPhotoSleeper(), jitter: { Double.random(in: 0...1) }, tapIDs: { UUID().uuidString },
                                    reasoningBilledSeparately: true)
let preparer = ImageIOLabelImagePreparer()
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
let handle: FileHandle
if !FileManager.default.fileExists(atPath: recordsURL.path) { FileManager.default.createFile(atPath: recordsURL.path, contents: nil) }
handle = try FileHandle(forWritingTo: recordsURL)
try handle.seekToEnd()

var ran = 0
var stopReason = "complete"
for item in cases where !done.contains(item.id) {
    if ran >= arguments.limit { stopReason = "limit"; break }
    if spent + LabelPhotoSpendPolicy.perTapLimit > arguments.stopUSD { stopReason = "total stop"; break }
    if spent >= arguments.pauseUSD { stopReason = "pause point"; break }
    let source = try Data(contentsOf: URL(fileURLWithPath: (item.path as NSString).expandingTildeInPath))
    guard (try? SHA256Digester().sha256(source).value) == item.sha256 else { fail("\(item.id): photo bytes do not match the recorded SHA-256") }
    var record = Record(id: item.id, split: item.split, sourceSHA256: item.sha256, outcome: "not_sent", chargedUSD: "0", attempts: [])
    let prepared: PreparedLabelImage
    do {
        prepared = try preparer.prepare(source, crop: .whole)
    } catch {
        record.prepareError = "\(error)"
        try handle.write(contentsOf: encoder.encode(record) + Data("\n".utf8))
        ran += 1
        continue
    }
    record.preparedWidth = prepared.pixelWidth; record.preparedHeight = prepared.pixelHeight
    record.preparedBytes = prepared.bytes.count; record.preparedSHA256 = prepared.sha256
    ledger.reset()
    let started = Date()
    let outcome = await session.read(prepared)
    record.tapSeconds = Date().timeIntervalSince(started)
    record.attempts = transport.take()
    switch outcome {
    case let .answered(reply, _):
        record.outcome = "answered"
        record.wireText = reply.wireText; record.model = reply.model; record.provider = reply.provider
        record.generationID = reply.generationID; record.finishReason = reply.finishReason; record.attemptsReported = reply.attempts
        record.costUSD = reply.usage.costUSD; record.promptTokens = reply.usage.promptTokens
        record.completionTokens = reply.usage.completionTokens; record.reasoningTokens = reply.usage.reasoningTokens
    case let .failed(failure):
        record.outcome = "failed"
        record.failure = "\(failure)"
    }
    // Charged: each attempt's reported cost, or W when it reported none (never zero for unknown).
    let charged = record.attempts.reduce(Decimal(0)) { $0 + (decimal($1.costUSD) ?? worstCase) }
    record.chargedUSD = "\(charged)"
    spent += charged
    try handle.write(contentsOf: encoder.encode(record) + Data("\n".utf8))
    ran += 1
    FileHandle.standardError.write(Data("\(done.count + ran)/\(cases.count) \(record.outcome) \(record.failure ?? "") \(String(format: "%.1f", record.tapSeconds ?? 0)) s, spent \(spent) USD\n".utf8))
    if record.failure == "routeUnavailable" || record.failure == "keyMissing" || record.failure == "keyRejected" {
        stopReason = "route or key failure: \(record.failure!)"
        break
    }
}
try handle.close()
FileHandle.standardError.write(Data("stopped: \(stopReason); ran \(ran); total charged \(spent) USD; catalogue GETs \(transport.catalogueGets)\n".utf8))
