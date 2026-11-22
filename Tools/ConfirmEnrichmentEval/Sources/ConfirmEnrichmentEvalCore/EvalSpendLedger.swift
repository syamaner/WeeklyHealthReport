import Foundation

/// The evaluation's own spend ledger (CE-T15; docs/confirm-enrichment-openrouter-v1-phase.md section 9):
/// `confirm-enrichment-eval-spend-ledger-v1`, one JSON file in the owner's private folder, never the app's
/// `confirm-enrichment-day-v1` and never another tool's ledger. Money is whole micro-dollars.
///
/// - **Before every call** the call's worst case W is reserved as an open entry. It is refused when W
///   passes the $0.05 per-call stop, or when what is charged so far plus W would pass the $25 programme stop.
/// - **After the call** the entry settles to the reported cost; with none it stays charged at W. A call
///   that sent nothing is released at zero. A reported cost above the per-call stop stops the ledger:
///   every later reservation is refused.
/// - A file that cannot be read, or holds another schema, refuses everything (fail closed).
///
/// It records the part, the case hash, W and the reported cost; never a key, a header, a body, a
/// response, a barcode or a description.
public final class EvalSpendLedger: @unchecked Sendable {
    public static let schema = "confirm-enrichment-eval-spend-ledger-v1"
    public static let programmeStopMicroUSD = 25_000_000
    public static let perCallStopMicroUSD = 50_000

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case unreadable, unknownSchema, perCallStop, programmeStop, stopped, noOpenReservation
        public var description: String {
            switch self {
            case .unreadable: "ledger_unreadable"
            case .unknownSchema: "ledger_unknown_schema"
            case .perCallStop: "per_call_stop"
            case .programmeStop: "programme_stop"
            case .stopped: "ledger_stopped"
            case .noOpenReservation: "no_open_reservation"
            }
        }
    }

    struct Entry: Codable, Equatable {
        let id: String
        let part: String
        let caseHash: String
        let worstCaseMicroUSD: Int
        var costMicroUSD: Int?
        var open: Bool

        enum CodingKeys: String, CodingKey {
            case id, part, open
            case caseHash = "case_sha256"
            case worstCaseMicroUSD = "w_microusd"
            case costMicroUSD = "cost_microusd"
        }
    }

    struct File: Codable, Equatable {
        var schema: String
        var stopped: Bool
        var entries: [Entry]
    }

    public let url: URL
    private let lock = NSLock()
    private var sequence = 0

    public init(url: URL) { self.url = url }

    private func read() throws -> File {
        guard FileManager.default.fileExists(atPath: url.path) else { return File(schema: Self.schema, stopped: false, entries: []) }
        guard let data = FileManager.default.contents(atPath: url.path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Refusal.unreadable }
        guard root["schema"] as? String == Self.schema else { throw Refusal.unknownSchema }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { throw Refusal.unreadable }
        return file
    }

    private func write(_ file: File) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    private func charged(_ file: File) -> Int {
        file.entries.reduce(0) { $0 + ($1.open ? $1.worstCaseMicroUSD : ($1.costMicroUSD ?? $1.worstCaseMicroUSD)) }
    }

    /// What every call so far is charged: reported costs, and W for open or unreported calls.
    public func chargedMicroUSD() throws -> Int { try lock.withLock { charged(try read()) } }

    /// Reserves one call at W, before it is sent. Returns the reservation's ID.
    public func reserve(part: String, caseHash: String, worstCaseMicroUSD w: Int) throws -> String {
        try lock.withLock {
            var file = try read()
            guard !file.stopped else { throw Refusal.stopped }
            // A negative W could only come from an overflow: refused, never subtracted from the total.
            guard w >= 0, w <= Self.perCallStopMicroUSD else { throw Refusal.perCallStop }
            guard charged(file) + w <= Self.programmeStopMicroUSD else { throw Refusal.programmeStop }
            sequence += 1
            let id = "\(file.entries.count + 1)-\(sequence)"
            file.entries.append(Entry(id: id, part: part, caseHash: caseHash, worstCaseMicroUSD: w, costMicroUSD: nil, open: true))
            try write(file)
            return id
        }
    }

    /// Settles a sent call to its reported cost (nil: unreported, charged at W).
    public func settle(_ id: String, reportedMicroUSD: Int?) throws {
        try lock.withLock {
            var file = try read()
            guard let index = file.entries.firstIndex(where: { $0.id == id && $0.open }) else { throw Refusal.noOpenReservation }
            file.entries[index].open = false
            // A negative reported cost is not believed: the call stays charged at W and the ledger stops.
            if let reported = reportedMicroUSD, reported < 0 {
                file.entries[index].costMicroUSD = nil
                file.stopped = true
            } else {
                file.entries[index].costMicroUSD = reportedMicroUSD
            }
            if let reported = reportedMicroUSD, reported > Self.perCallStopMicroUSD { file.stopped = true }
            try write(file)
        }
    }

    /// Releases a call that sent nothing, at zero.
    public func release(_ id: String) throws {
        try lock.withLock {
            var file = try read()
            guard let index = file.entries.firstIndex(where: { $0.id == id && $0.open }) else { throw Refusal.noOpenReservation }
            file.entries[index].open = false
            file.entries[index].costMicroUSD = 0
            try write(file)
        }
    }
}
