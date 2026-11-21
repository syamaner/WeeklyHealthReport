import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

// Test doubles of the Confirm enrichment ports (docs/confirm-enrichment-openrouter-v1-phase.md section 6,
// "Where the tests run"), as label photo's session tests use their own. Each passes the same shared
// contract suite as the production implementations (ConfirmEnrichmentPortContracts).

/// A wall clock a test moves.
public final class ConfirmEnrichmentTestClock: LedgerClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    public init(_ start: Date = Date(timeIntervalSince1970: 1_795_000_000.123)) { current = start }
    public func now() -> Date { lock.withLock { current } }
    public func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    public func set(_ date: Date) { lock.withLock { current = date } }
}

/// Sequential UUID-shaped identifiers.
public final class ConfirmEnrichmentTestIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var next: Int
    public init(start: Int = 1) { next = start }
    public func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        let n = lock.withLock { () -> Int in defer { next += 1 }; return next }
        return try LedgerID<Tag>(String(format: "00000000-0000-4000-8000-%012d", n))
    }
}

/// Waits that return at once, recording each; a test can make the next waits throw (cancellation),
/// and the elapsed timing advances by each wait.
public final class ConfirmEnrichmentTestDelaying: ConfirmEnrichmentDelaying, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []
    private var cancelling = false
    private let timing: ConfirmEnrichmentTestTiming?
    public init(timing: ConfirmEnrichmentTestTiming? = nil) { self.timing = timing }
    public func wait(seconds: TimeInterval) async throws {
        let cancel = lock.withLock { () -> Bool in recorded.append(seconds); return cancelling }
        if cancel || Task.isCancelled { throw CancellationError() }
        timing?.advance(seconds)
    }
    public func cancelWaits(_ value: Bool = true) { lock.withLock { cancelling = value } }
    public var waits: [TimeInterval] { lock.withLock { recorded } }
}

/// Monotonic time a test moves.
public final class ConfirmEnrichmentTestTiming: ConfirmEnrichmentElapsedTiming, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero
    public init() {}
    public func now() -> Duration { lock.withLock { current } }
    public func advance(_ seconds: TimeInterval) { lock.withLock { current += .milliseconds(Int64(seconds * 1_000)) } }
}

public struct ConfirmEnrichmentTestJitter: ConfirmEnrichmentJittering {
    public let value: Double
    public init(_ value: Double = 0) { self.value = value }
    public func fraction() -> Double { value }
}

/// An adapter for both parts that records every body and returns scripted results in order (the
/// last repeats). It asks the gate before each attempt with the use it is given, as every request
/// site must (G5), and advances the test timing by `latency` per attempt.
public final class ConfirmEnrichmentTestAdapter: FoodDetailsSuggesting, NutrientEstimateSuggesting, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [ConfirmEnrichmentAttemptResult]
    private var recorded: [Data] = []
    private let egress: any OpenRouterEgressPermitting
    private let use: OpenRouterUse
    private let timing: ConfirmEnrichmentTestTiming?
    private let latency: TimeInterval

    public init(_ results: [ConfirmEnrichmentAttemptResult], use: OpenRouterUse, egress: any OpenRouterEgressPermitting = PermittingOpenRouterEgress(),
                timing: ConfirmEnrichmentTestTiming? = nil, latency: TimeInterval = 1) {
        self.results = results; self.use = use; self.egress = egress; self.timing = timing; self.latency = latency
    }

    public func attempt(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult {
        guard egress.permits(use) else { return .notSent(.notPermitted) }
        timing?.advance(latency)
        return lock.withLock {
            recorded.append(body)
            return results.count > 1 ? results.removeFirst() : (results.first ?? .transportFailed(.connectionFailed))
        }
    }

    public var bodies: [Data] { lock.withLock { recorded } }
}

/// A route checker returning a scripted result, asking the gate for the catalogue use first.
public final class ConfirmEnrichmentTestRouteChecker: ConfirmEnrichmentRouteChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [ConfirmEnrichmentRouteCheckResult]
    private var count = 0
    private let egress: any OpenRouterEgressPermitting
    public static let cheap = ConfirmEnrichmentPrices(promptPerTokenUSD: Decimal(string: "0.0000002")!,
                                                      completionPerTokenUSD: Decimal(string: "0.0000008")!)

    public init(_ results: [ConfirmEnrichmentRouteCheckResult] = [.passed(cheap)], egress: any OpenRouterEgressPermitting = PermittingOpenRouterEgress()) {
        self.results = results; self.egress = egress
    }

    public func check(_ part: ConfirmEnrichmentPart, catalogueUse: OpenRouterUse) async -> ConfirmEnrichmentRouteCheckResult {
        guard egress.permits(catalogueUse) else { return .notPermitted }
        return lock.withLock {
            count += 1
            return results.count > 1 ? results.removeFirst() : (results.first ?? .unavailable)
        }
    }

    public var checks: Int { lock.withLock { count } }
}

/// The test double of the cache, under the one policy.
public final class ConfirmEnrichmentTestCache: ConfirmEnrichmentCaching, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var answers: [ConfirmEnrichmentCachedAnswer] = []
    public init() {}
    public func answer(subject: String, part: ConfirmEnrichmentPart, now: Date) -> ConfirmEnrichmentCachedAnswer? {
        lock.withLock { ConfirmEnrichmentCachePolicy.lookup(answers, subject: subject, part: part, now: now) }
    }
    public func store(_ answer: ConfirmEnrichmentCachedAnswer, now: Date) {
        lock.withLock { answers = ConfirmEnrichmentCachePolicy.storing(answer, in: answers, now: now) }
    }
    public func remove(subject: String, part: ConfirmEnrichmentPart) {
        lock.withLock { answers = ConfirmEnrichmentCachePolicy.removing(subject: subject, part: part, from: answers) }
    }
    public func clear() { lock.withLock { answers = [] } }
}

/// The test double of the day ledger, whose writes a test can make fail.
public final class ConfirmEnrichmentTestLedger: ConfirmEnrichmentSpendLedger, @unchecked Sendable {
    public struct WriteFailure: Error {}
    private let lock = NSLock()
    private var stored: ConfirmEnrichmentSpendPolicy.Stored
    private var failures = 0
    public init(_ stored: ConfirmEnrichmentSpendPolicy.Stored = .absent) { self.stored = stored }
    public func read() -> ConfirmEnrichmentSpendPolicy.Stored { lock.withLock { stored } }
    @discardableResult
    public func update(_ transform: (ConfirmEnrichmentSpendPolicy.Stored) throws -> ConfirmEnrichmentSpendPolicy.Day) throws
        -> ConfirmEnrichmentSpendPolicy.Day {
        try lock.withLock {
            if failures > 0 { failures -= 1; throw WriteFailure() }
            let day = try transform(stored)
            stored = .day(day)
            return day
        }
    }
    /// The next `count` writes throw without storing.
    public func failWrites(_ count: Int) { lock.withLock { failures = count } }
    public func set(_ value: ConfirmEnrichmentSpendPolicy.Stored) { lock.withLock { stored = value } }
    public var day: ConfirmEnrichmentSpendPolicy.Day? {
        if case let .day(day) = read() { return day }
        return nil
    }
}

/// The in-memory Your food database read port.
public struct ConfirmEnrichmentTestEntryReader: PersonalFoodDatabaseEntryReading {
    public let fields: [String: PersonalFoodDescriptionFields]
    public init(_ fields: [String: PersonalFoodDescriptionFields]) { self.fields = fields }
    public func descriptionFields(recordID: ExternalIdentifier) -> PersonalFoodDescriptionFields? { fields[recordID.value] }
}
