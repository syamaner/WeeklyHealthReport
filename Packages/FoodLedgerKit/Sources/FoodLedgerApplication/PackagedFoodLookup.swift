import Foundation
import FoodLedgerDomain

public struct PackagedFoodLookupRequest: Sendable {
    public let identity: BarcodeIdentity
    public let evidence: CaptureEvidence
    public init(identity: BarcodeIdentity, evidence: CaptureEvidence) {
        self.identity = identity; self.evidence = evidence
    }
}

public enum PackagedFoodLookupOutcome: Equatable, Sendable {
    case candidate(PopulatedFoodConfirmation)
    case notFound
    case insufficientData
}

public protocol PackagedFoodCandidateLookingUp: Sendable {
    func lookup(_ request: PackagedFoodLookupRequest) async throws -> PackagedFoodLookupOutcome
}
