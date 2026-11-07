import Foundation

/// The text programme's reservations in the photo evaluation's existing spend ledger
/// (docs/pasted-label-ai-text-v1.md 5.2 item 1, T5): the JSON file of
/// `Tools/NutritionLabelCaptureEvaluation/budget.py` (`label-capture-spend-ledger-v1`), under the
/// same `fcntl` lock on its sibling `.lock` file, so the Python stops and this tool always see one
/// file. Every member this tool does not own is kept as it is.
///
/// - **Before a call** the worst case W is reserved as an open entry charged at W (its `cost_usd`
///   holds W until it settles, as `budget.py` charges an open call at its ceiling, so the Python
///   total sees it and concurrent calls never count as unknown). The reservation is refused
///   when the cell's charges plus W would pass the $5 cell stop, the programme's would pass the
///   $25 programme stop, or the ledger's own unknown-cost stop is already reached.
/// - **After the call** the entry settles to the reported cost. With no reported cost it stays
///   unknown (`cost_usd` null) and is charged at W towards both stops, so the ledger's unknown-cost
///   stop still applies. A call that sent nothing settles to zero.
/// - A text entry is charged its reported cost, or its W when the cost is unknown or open.
/// - **The ledger's own stops apply too** (A2 gate finding 2): a W above its `per_call_usd` is
///   refused, a model or cell named in `stopped_models` is refused, and a reported cost above
///   `per_call_usd` stops the model, as `budget.py` does. A settle whose reported cost passes W, or
///   whose prompt tokens pass the request's bound, stops the cell: W was not a true bound.
///
/// The ledger records the purpose, cell, model, case ID, W and the reported cost; never a key, a
/// header, a prompt, the text or a response.
public final class EvalSpendLedger: @unchecked Sendable {
    public static let schema = "label-capture-spend-ledger-v1"
    public static let purpose = "pasted-label-ai-text-eval"
    public static let openKind = "pasted_label_ai_text_open"
    public static let settledKind = "pasted_label_ai_text_call"
    public static let unknownKind = "pasted_label_ai_text_unknown_cost"
    public static let notSentKind = "pasted_label_ai_text_not_sent"
    /// The kinds `budget.py` leaves out of its unknown-cost stop.
    static let notCountedUnknownKinds: Set<String> = ["retryable_error_unknown_cost", "rejected_no_generation_unknown_cost"]
    public static let maximumCellStop = Decimal(5)
    public static let maximumProgrammeStop = Decimal(25)

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case unknownSchema, unreadable, cellStop, programmeStop, unknownCostStop, noOpenReservation, stopsOutOfRange
        case perCallStop, modelStopped, cellStopped, promptBoundOverCeiling
        public var description: String {
            switch self {
            case .unknownSchema: "the spend ledger has an unknown schema"
            case .unreadable: "the spend ledger cannot be read"
            case .cellStop: "the $5 cell stop would be passed"
            case .programmeStop: "the $25 programme stop would be passed"
            case .unknownCostStop: "the ledger's unknown-cost stop is reached"
            case .noOpenReservation: "no open reservation with that ID"
            case .stopsOutOfRange: "the stops may not exceed $5 per cell and $25 for the programme"
            case .perCallStop: "W passes the ledger's per-call stop"
            case .modelStopped: "the model is stopped in the ledger"
            case .cellStopped: "the cell is stopped: an earlier call passed its W or its prompt bound"
            case .promptBoundOverCeiling: "the request's prompt bound passes the prompt-token ceiling"
            }
        }
    }

    public let url: URL
    let cellStop: Decimal
    let programmeStop: Decimal

    public init(url: URL, cellStop: Decimal = 5, programmeStop: Decimal = 25) throws {
        guard cellStop > 0, cellStop <= Self.maximumCellStop, programmeStop > 0, programmeStop <= Self.maximumProgrammeStop else {
            throw Refusal.stopsOutOfRange
        }
        self.url = url; self.cellStop = cellStop; self.programmeStop = programmeStop
    }

    // MARK: Locked read-modify-write

    func locked<T>(_ body: (inout [String: Any]) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockPath = url.path + ".lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw Refusal.unreadable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw Refusal.unreadable }
        defer { flock(descriptor, LOCK_UN) }
        var ledger = try load()
        let result = try body(&ledger)
        try save(ledger)
        return result
    }

    func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self.fresh() }
        guard let data = FileManager.default.contents(atPath: url.path),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Refusal.unreadable }
        guard object["schema_version"] as? String == Self.schema else { throw Refusal.unknownSchema }
        return object
    }

    /// A new ledger in `budget.py`'s shape, with its default limits and no sealed reservation.
    static func fresh() -> [String: Any] {
        ["schema_version": schema,
         "limits": ["per_call_usd": "0.20", "total_usd": "25", "unknown_cost_calls_allowed": 3, "sealed_reserved_calls": 0,
                    "sealed_reserved_per_call_usd": "0.05"],
         "reported_spend_usd": "0", "unknown_cost_calls": 0, "sealed_calls_made": 0, "sealed_reservation_remaining_calls": 0, "open_calls": 0,
         "open_sealed_calls": 0, "stopped_models": [String](), "limits_history": [Any](), "amendments": [Any](), "entries": [Any]()]
    }

    func save(_ ledger: [String: Any]) throws {
        var ledger = ledger
        Self.recount(&ledger)
        let data = try JSONSerialization.data(withJSONObject: ledger, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
        let temporary = url.appendingPathExtension("tmp")
        try data.write(to: temporary)
        guard rename(temporary.path, url.path) == 0 else { throw Refusal.unreadable }
    }

    /// `budget.py`'s `_recount` for the two counters entries change.
    static func recount(_ ledger: inout [String: Any]) {
        let entries = ledger["entries"] as? [[String: Any]] ?? []
        let reported = entries.compactMap { ($0["cost_usd"] as? String).flatMap(decimal) }.reduce(Decimal(0), +)
        ledger["reported_spend_usd"] = "\(reported)"
        ledger["unknown_cost_calls"] = unknownCount(entries)
    }

    static func unknownCount(_ entries: [[String: Any]]) -> Int {
        entries.filter { ($0["cost_usd"] == nil || $0["cost_usd"] is NSNull) && !notCountedUnknownKinds.contains($0["kind"] as? String ?? "") }.count
    }

    static func decimal(_ text: String) -> Decimal? { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) }

    /// What a text entry is charged: its reported cost, or its W.
    static func charge(_ entry: [String: Any]) -> Decimal {
        if let cost = (entry["cost_usd"] as? String).flatMap(decimal) { return cost }
        return (entry["reserved_usd"] as? String).flatMap(decimal) ?? maximumCellStop
    }

    static func textEntries(_ ledger: [String: Any]) -> [[String: Any]] {
        (ledger["entries"] as? [[String: Any]] ?? []).filter { $0["purpose"] as? String == purpose }
    }

    // MARK: Spend

    public struct Totals: Equatable, Sendable {
        public let cell: Decimal
        public let programme: Decimal
    }

    public func totals(cell: String) throws -> Totals {
        let entries = Self.textEntries(try load())
        return Totals(cell: entries.filter { $0["cell"] as? String == cell }.map(Self.charge).reduce(0, +),
                      programme: entries.map(Self.charge).reduce(0, +))
    }

    /// The `stopped_models` key of a stopped text cell (`budget.py` keeps the list as it is).
    public static func cellKey(_ cell: String) -> String { "pasted-label-ai-text-cell:" + cell }

    static func perCall(_ limits: [String: Any]) -> Decimal? {
        (limits["per_call_usd"] as? String).flatMap(decimal) ?? (limits["per_call_usd"] as? NSNumber).flatMap { decimal($0.stringValue) }
    }

    /// Reserves W for one call; returns the reservation ID, or throws the stop that refuses it.
    public func reserve(cell: String, caseID: String, model: String, worstCase: Decimal, at: String, id: String) throws -> String {
        try locked { ledger in
            let entries = ledger["entries"] as? [[String: Any]] ?? []
            let limits = ledger["limits"] as? [String: Any] ?? [:]
            let stopped = Set(ledger["stopped_models"] as? [String] ?? [])
            if stopped.contains(model) { throw Refusal.modelStopped }
            if stopped.contains(Self.cellKey(cell)) { throw Refusal.cellStopped }
            if let perCall = Self.perCall(limits), worstCase > perCall { throw Refusal.perCallStop }
            let allowed = (limits["unknown_cost_calls_allowed"] as? Int) ?? 3
            if Self.unknownCount(entries) >= allowed { throw Refusal.unknownCostStop }
            let text = Self.textEntries(ledger)
            if text.filter({ $0["cell"] as? String == cell }).map(Self.charge).reduce(0, +) + worstCase > cellStop { throw Refusal.cellStop }
            if text.map(Self.charge).reduce(0, +) + worstCase > programmeStop { throw Refusal.programmeStop }
            let entry: [String: Any] = ["at": at, "purpose": Self.purpose, "model": model, "returned_model": NSNull(), "case_id": caseID,
                                        "sealed": false, "cost_usd": "\(worstCase)", "kind": Self.openKind, "reservation_id": id, "cell": cell,
                                        "reserved_usd": "\(worstCase)"]
            ledger["entries"] = entries + [entry]
            return id
        }
    }

    public enum Settlement: Equatable, Sendable {
        case reported(Decimal)
        case unknown
        case notSent
    }

    /// Settles an open reservation in place: to the reported cost, to unknown (charged at W), or to
    /// zero when nothing was sent. `promptTokens` above `promptTokenBound`, or a reported cost above
    /// the reservation's W, stops the cell; a reported cost above `per_call_usd` stops the model.
    /// Returns whether the cell was stopped.
    @discardableResult
    public func settle(id: String, _ settlement: Settlement, returnedModel: String?, generationID: String?, at: String,
                       promptTokens: Int? = nil, promptTokenBound: Int? = nil) throws -> Bool {
        try locked { ledger in
            var entries = ledger["entries"] as? [[String: Any]] ?? []
            guard let index = entries.firstIndex(where: { $0["reservation_id"] as? String == id && $0["kind"] as? String == Self.openKind }) else {
                throw Refusal.noOpenReservation
            }
            var entry = entries[index]
            switch settlement {
            case let .reported(cost): entry["cost_usd"] = "\(cost)"; entry["kind"] = Self.settledKind
            case .unknown: entry["cost_usd"] = NSNull(); entry["kind"] = Self.unknownKind
            case .notSent: entry["cost_usd"] = "0"; entry["kind"] = Self.notSentKind
            }
            entry["returned_model"] = returnedModel ?? NSNull()
            if let generationID { entry["generation_id"] = generationID }
            entry["settled_at"] = at
            entries[index] = entry
            ledger["entries"] = entries
            var stopped = ledger["stopped_models"] as? [String] ?? []
            let reserved = (entry["reserved_usd"] as? String).flatMap(Self.decimal) ?? 0
            var stopCell = false
            if case let .reported(cost) = settlement {
                if cost > reserved { stopCell = true }
                if let perCall = Self.perCall(ledger["limits"] as? [String: Any] ?? [:]), cost > perCall,
                   let model = entry["model"] as? String, !stopped.contains(model) {
                    stopped.append(model)
                }
            }
            if let promptTokens, let promptTokenBound, promptTokens > promptTokenBound { stopCell = true }
            if stopCell, let cell = entry["cell"] as? String, !stopped.contains(Self.cellKey(cell)) { stopped.append(Self.cellKey(cell)) }
            ledger["stopped_models"] = stopped.sorted()
            return stopCell
        }
    }
}
