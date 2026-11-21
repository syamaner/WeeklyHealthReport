import FoodLedgerApplication
import Foundation

/// A gate that permits every OpenRouter use, for tests that exercise an adapter with OpenRouter
/// turned on (docs/openrouter-single-consent-v1-amendment.md section 6).
public struct PermittingOpenRouterEgress: OpenRouterEgressPermitting {
    public init() {}
    public func permits(_ use: OpenRouterUse) -> Bool { true }
}

/// A gate whose answer a test sets, recording the use each request site asks for (O1.6 test 1).
public final class RecordingOpenRouterEgress: OpenRouterEgressPermitting, @unchecked Sendable {
    private let lock = NSLock()
    private var allowed: Bool
    private var asked: [OpenRouterUse] = []
    /// Answers in order before falling back to `allowed`, so a test can refuse the second ask only.
    private var scripted: [Bool]

    public init(permits: Bool, then scripted: [Bool] = []) {
        allowed = permits; self.scripted = scripted
        if !scripted.isEmpty { self.scripted = [permits] + scripted }
    }

    public func permits(_ use: OpenRouterUse) -> Bool {
        lock.lock(); defer { lock.unlock() }
        asked.append(use)
        if !scripted.isEmpty { return scripted.removeFirst() }
        return allowed
    }

    /// Changes the answer for every later ask (the switch turned on or off mid-journey).
    public func set(_ permits: Bool) {
        lock.lock(); allowed = permits; scripted = []; lock.unlock()
    }

    public var uses: [OpenRouterUse] {
        lock.lock(); defer { lock.unlock() }
        return asked
    }
}
