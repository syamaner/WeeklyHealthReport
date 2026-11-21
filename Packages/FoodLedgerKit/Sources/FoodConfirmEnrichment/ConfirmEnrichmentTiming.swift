import FoodLedgerApplication
import Foundation

/// The real timing adapters (phase gate section 4): cancellable waits, monotonic elapsed time and
/// backoff jitter. Each passes its shared suite in FoodConfirmEnrichmentTests.
public struct TaskConfirmEnrichmentDelaying: ConfirmEnrichmentDelaying {
    public init() {}
    public func wait(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

public struct ContinuousConfirmEnrichmentTiming: ConfirmEnrichmentElapsedTiming {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant
    public init() { origin = clock.now }
    public func now() -> Duration { clock.now - origin }
}

public struct SystemConfirmEnrichmentJitter: ConfirmEnrichmentJittering {
    public init() {}
    public func fraction() -> Double { Double.random(in: 0...1) }
}
