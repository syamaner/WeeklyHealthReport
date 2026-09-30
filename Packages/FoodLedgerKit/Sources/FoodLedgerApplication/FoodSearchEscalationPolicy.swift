import Foundation

/// Match quality is assessed independently of nutrition availability and quantity.
/// These categories are not provider self-reports or lexical-score probabilities.
public struct FoodSearchCandidateCoverage: Equatable, Sendable {
    public enum Match: Equatable, Sendable { case strong, uncertain, incompatible }
    public enum Nutrition: Equatable, Sendable { case complete, incomplete, unknown }
    public enum Basis: Equatable, Sendable { case compatible, unknown, incompatible }
    public enum Quantity: Equatable, Sendable { case ready, needsUserInput }

    public let match: Match
    public let nutrition: Nutrition
    public let basis: Basis
    public let quantity: Quantity

    public init(match: Match, nutrition: Nutrition, basis: Basis, quantity: Quantity) {
        self.match = match
        self.nutrition = nutrition
        self.basis = basis
        self.quantity = quantity
    }

    /// Missing user input alone cannot be repaired by searching another service.
    public var isSufficientForSearch: Bool {
        match == .strong && nutrition == .complete && basis == .compatible
    }
}

public enum FoodSearchStage: Equatable, Sendable {
    case local, onlineDatabase, gemini
}

public struct FoodSearchServiceAvailability: Equatable, Sendable {
    /// `ready` requires enablement and any required validated credentials/access.
    /// Key presence alone is insufficient. Adapters own validation, not this policy.
    public enum Access: CaseIterable, Equatable, Sendable { case disabled, unavailable, ready }
    public let onlineDatabase: Access
    public let gemini: Access

    public init(onlineDatabase: Access, gemini: Access) {
        self.onlineDatabase = onlineDatabase
        self.gemini = gemini
    }
}

public enum FoodSearchEscalationPolicy {
    public static let version = "food_search_escalation_v1"

    public static func nextStage(
        after stage: FoodSearchStage,
        candidates: [FoodSearchCandidateCoverage],
        services: FoodSearchServiceAvailability
    ) -> FoodSearchStage? {
        guard !candidates.contains(where: \.isSufficientForSearch) else { return nil }
        switch stage {
        case .local:
            if services.onlineDatabase == .ready { return .onlineDatabase }
            return services.gemini == .ready ? .gemini : nil
        case .onlineDatabase:
            return services.gemini == .ready ? .gemini : nil
        case .gemini:
            return nil
        }
    }
}

/// A completion must return the token issued for its exact run and stage.
public struct FoodSearchStageToken: Equatable, Sendable {
    fileprivate let sessionID: UUID
    fileprivate let generation: UInt64
    public let stage: FoodSearchStage
}

public enum FoodSearchCompletion: Equatable, Sendable {
    /// Stale, cancelled or already-consumed completions must not publish results.
    case ignored
    /// Publish the accepted batch before starting the next stage, if any.
    case accepted(next: FoodSearchStageToken?)
}

/// Pure lifecycle state. The async coordinator owns transport and result batches.
/// On edits, selection, decline, navigation or service changes it must call cancel()
/// as well as cancelling transport. This guard also handles uncooperative providers.
public struct FoodSearchSession: Sendable {
    public private(set) var pending: FoodSearchStageToken?
    public private(set) var coverage: [FoodSearchCandidateCoverage] = []
    private let sessionID: UUID
    private var generation: UInt64 = 0
    private var services = FoodSearchServiceAvailability(onlineDatabase: .disabled, gemini: .disabled)

    public init(sessionID: UUID = UUID()) { self.sessionID = sessionID }

    @discardableResult
    public mutating func begin(services: FoodSearchServiceAvailability) -> FoodSearchStageToken {
        cancel()
        self.services = services
        let token = FoodSearchStageToken(sessionID: sessionID, generation: generation, stage: .local)
        pending = token
        return token
    }

    public mutating func complete(
        _ token: FoodSearchStageToken, candidates: [FoodSearchCandidateCoverage]
    ) -> FoodSearchCompletion {
        guard pending == token else { return .ignored }
        coverage.append(contentsOf: candidates)
        return advance(after: token.stage)
    }

    /// A failure adds no coverage and never removes already accepted local results.
    public mutating func fail(_ token: FoodSearchStageToken) -> FoodSearchCompletion {
        guard pending == token else { return .ignored }
        return advance(after: token.stage)
    }

    public mutating func cancel() {
        generation += 1
        pending = nil
        coverage = []
    }

    private mutating func advance(after stage: FoodSearchStage) -> FoodSearchCompletion {
        pending = FoodSearchEscalationPolicy.nextStage(after: stage, candidates: coverage, services: services)
            .map { FoodSearchStageToken(sessionID: sessionID, generation: generation, stage: $0) }
        return .accepted(next: pending)
    }
}
