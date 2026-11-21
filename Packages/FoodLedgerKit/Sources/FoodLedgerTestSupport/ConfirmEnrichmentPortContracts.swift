import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Shared contract suites for the Confirm enrichment ports (docs/confirm-enrichment-openrouter-v1-phase.md
/// section 4; CE1 test 12): every implementation of a port runs the same suite. Each returns its
/// violations; an empty list passes. No XCTest here, so the suites stay inside this target's imports.
public enum ConfirmEnrichmentPortContracts {
    static let now = Date(timeIntervalSince1970: 1_795_000_000)

    static func answer(_ subject: Character, part: ConfirmEnrichmentPart = .nutrients, at date: Date = now,
                       bytes: String = #"{"ok":true}"#) -> ConfirmEnrichmentCachedAnswer {
        let data = Data(bytes.utf8)
        return ConfirmEnrichmentCachedAnswer(subjectSHA256: String(repeating: subject, count: 64), part: part, response: data,
                                             responseSHA256: (try? SHA256Digester().sha256(data).value) ?? "",
                                             model: "openai/gpt-6.1-sol", provider: "Azure", costMicroUSD: 1_200,
                                             receivedAt: ConfirmEnrichmentTime.truncated(date))
    }

    /// `ConfirmEnrichmentCaching`: a store reads back exactly CE1.2's value at millisecond precision, per
    /// subject and part; a later store for the same subject replaces it; remove and clear empty it; an
    /// entry older than 30 days misses and is dropped at the next write; above 500 entries the oldest
    /// goes first.
    public static func cacheViolations(_ make: () -> any ConfirmEnrichmentCaching) -> [String] {
        var failures: [String] = []
        let cache = make()
        let first = answer("a")
        cache.store(first, now: now)
        if cache.answer(subject: first.subjectSHA256, part: .nutrients, now: now) != first { failures.append("store: not read back exactly") }
        if cache.answer(subject: first.subjectSHA256, part: .details, now: now) != nil { failures.append("store: another part hit") }
        let replaced = answer("a", bytes: #"{"ok":false}"#)
        cache.store(replaced, now: now)
        if cache.answer(subject: first.subjectSHA256, part: .nutrients, now: now) != replaced { failures.append("store: not replaced") }
        cache.remove(subject: first.subjectSHA256, part: .nutrients)
        if cache.answer(subject: first.subjectSHA256, part: .nutrients, now: now) != nil { failures.append("remove: still a hit") }
        let old = answer("b", at: now.addingTimeInterval(-31 * 24 * 3_600))
        cache.store(old, now: now.addingTimeInterval(-31 * 24 * 3_600))
        if cache.answer(subject: old.subjectSHA256, part: .nutrients, now: now) != nil { failures.append("expiry: a 31-day entry hit") }
        cache.store(answer("c"), now: now)
        if cache.answer(subject: old.subjectSHA256, part: .nutrients, now: old.receivedAt) != nil {
            failures.append("expiry: an expired entry was kept at the next write")
        }
        cache.clear()
        if cache.answer(subject: answer("c").subjectSHA256, part: .nutrients, now: now) != nil { failures.append("clear: still a hit") }
        let filled = make()
        for index in 0..<501 {
            let subject = String(format: "%064x", index)
            let data = Data("{}".utf8)
            filled.store(ConfirmEnrichmentCachedAnswer(subjectSHA256: subject, part: .details, response: data,
                                                       responseSHA256: (try? SHA256Digester().sha256(data).value) ?? "", model: "m",
                                                       provider: "p", costMicroUSD: nil,
                                                       receivedAt: ConfirmEnrichmentTime.truncated(now.addingTimeInterval(Double(index)))),
                         now: now.addingTimeInterval(Double(index)))
        }
        if filled.answer(subject: String(format: "%064x", 0), part: .details, now: now.addingTimeInterval(600)) != nil {
            failures.append("eviction: the oldest of 501 entries was kept")
        }
        if filled.answer(subject: String(format: "%064x", 500), part: .details, now: now.addingTimeInterval(600)) == nil {
            failures.append("eviction: the newest entry was dropped")
        }
        return failures
    }

    /// `ConfirmEnrichmentSpendLedger`: a fresh ledger is absent; an update persists; a throwing
    /// transform stores nothing; `.unreadable` is passed to the transform as is.
    public static func ledgerViolations(_ make: (ConfirmEnrichmentSpendPolicy.Stored) -> any ConfirmEnrichmentSpendLedger) -> [String] {
        struct Refused: Error {}
        var failures: [String] = []
        let ledger = make(.absent)
        if ledger.read() != .absent { failures.append("fresh: not absent") }
        let day = ConfirmEnrichmentSpendPolicy.Day(localDay: "2026-11-21", requests: 3, settledMicroUSD: 4_000, paused: [.details])
        do { try ledger.update { _ in day } } catch { failures.append("update: threw") }
        if ledger.read() != .day(day) { failures.append("update: not persisted") }
        _ = try? ledger.update { _ in throw Refused() }
        if ledger.read() != .day(day) { failures.append("refusal: something was stored") }
        let unreadable = make(.unreadable)
        var seen: ConfirmEnrichmentSpendPolicy.Stored?
        _ = try? unreadable.update { stored in seen = stored; throw Refused() }
        if seen != .unreadable { failures.append("unreadable: not passed to the transform") }
        return failures
    }

    /// A single-attempt adapter (G5): it asks the gate on every attempt and records its own use, and a
    /// refusal sends nothing.
    public static func attemptViolations(use: OpenRouterUse,
                                         _ make: (any OpenRouterEgressPermitting) -> any NutrientOrDetailsAttempting,
                                         body: Data) async -> [String] {
        var failures: [String] = []
        let allowing = RecordingOpenRouterEgress(permits: true)
        let open = make(allowing)
        _ = await open.attemptOnce(body, timeout: 30)
        _ = await open.attemptOnce(body, timeout: 30)
        if allowing.uses != [use, use] { failures.append("gate: not asked once per attempt with \(use)") }
        let refusing = RecordingOpenRouterEgress(permits: false)
        if await make(refusing).attemptOnce(body, timeout: 30) != .notSent(.notPermitted) { failures.append("refusal: not notSent") }
        return failures
    }

    /// `ConfirmEnrichmentDelaying`: a short wait returns; a cancelled task throws.
    public static func delayingViolations(_ delaying: any ConfirmEnrichmentDelaying) async -> [String] {
        var failures: [String] = []
        do { try await delaying.wait(seconds: 0.01) } catch { failures.append("wait: threw") }
        let task = Task { try await delaying.wait(seconds: 5) }
        task.cancel()
        if (try? await task.value) != nil { failures.append("cancel: did not throw") }
        return failures
    }

    /// `ConfirmEnrichmentElapsedTiming`: never goes backwards. `ConfirmEnrichmentJittering`: 0 to 1.
    public static func timingViolations(_ timing: any ConfirmEnrichmentElapsedTiming, jitter: any ConfirmEnrichmentJittering) -> [String] {
        var failures: [String] = []
        let a = timing.now(), b = timing.now()
        if b < a { failures.append("timing: went backwards") }
        for _ in 0..<20 where !(0...1).contains(jitter.fraction()) { failures.append("jitter: outside 0 to 1") }
        return failures
    }
}

/// One attempt of either part, so one suite runs every adapter.
public protocol NutrientOrDetailsAttempting: Sendable {
    func attemptOnce(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult
}

public struct DetailsAttempting: NutrientOrDetailsAttempting {
    let adapter: any FoodDetailsSuggesting
    public init(_ adapter: any FoodDetailsSuggesting) { self.adapter = adapter }
    public func attemptOnce(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult { await adapter.attempt(body, timeout: timeout) }
}

public struct NutrientAttempting: NutrientOrDetailsAttempting {
    let adapter: any NutrientEstimateSuggesting
    public init(_ adapter: any NutrientEstimateSuggesting) { self.adapter = adapter }
    public func attemptOnce(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult { await adapter.attempt(body, timeout: timeout) }
}
