import Foundation
import FoodLedgerDomain

public struct FoodReresolutionTarget: Equatable, Sendable {
    public let sourceRelease: SourceRelease
    public let methodVersion: LedgerText
    public var identifier: String { "\(sourceRelease.sourceReleaseID.value)|\(methodVersion.value)" }

    public init(sourceRelease: SourceRelease, methodVersion: LedgerText) {
        self.sourceRelease = sourceRelease
        self.methodVersion = methodVersion
    }
}

public enum FoodReresolutionError: Error, Equatable {
    case unavailableTarget, noCompatibleCandidate, incompatibleIdentity, identityConfirmationRequired, staleProposal, missingLog, noChange
}

public protocol FoodReresolutionProviding: Sendable {
    func targets() throws -> [FoodReresolutionTarget]
    /// Read-only candidate discovery against exactly the chosen target.
    func candidates(for record: StoredFoodConfirmation, target: FoodReresolutionTarget, at: Date) throws -> GenericFoodSearchOutcome
}

public struct FoodReresolutionProposal: Equatable, Sendable {
    public let before: StoredFoodConfirmation
    public let target: FoodReresolutionTarget
    public let input: PopulatedFoodConfirmation
    public let candidate: PopulatedFoodCandidate
    public let diff: NutritionResolutionDiff
    public let identityGaps: [IdentityContradiction]

    public init(before: StoredFoodConfirmation, target: FoodReresolutionTarget, input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) throws {
        guard candidate.candidate.sourceReleaseID == target.sourceRelease.sourceReleaseID,
              candidate.candidate.matchMetadata?.methodVersion == target.methodVersion,
              input.sourceReleases.contains(target.sourceRelease), input.candidates.contains(candidate) else {
            throw FoodReresolutionError.unavailableTarget
        }
        guard Self.hasNoKnownContradictions(before: before, candidate: candidate) else {
            throw FoodReresolutionError.incompatibleIdentity
        }
        self.before = before
        self.target = target
        self.input = input
        self.candidate = candidate
        diff = NutritionResolutionDiff(before: before.resolutionVersion.nutrients, after: candidate.candidate.nutrients)
        identityGaps = IdentityCompatibility.contradictions(
            between: before.productVersion.identity, and: candidate.candidate.identity,
            expectedEdibleQuantity: candidate.candidate.edibleQuantity,
            candidateEdibleQuantity: candidate.candidate.edibleQuantity
        )
    }

    public var isNoOp: Bool {
        diff.isUnchanged && Set(before.resolutionVersion.sourceReleaseIDs) == Set(sourceReleaseIDs)
            && before.candidateDecision.candidate.recordID == candidate.candidate.recordID
    }

    public var sourceReleaseIDs: [ExternalIdentifier] {
        Set(candidate.candidate.nutrients.entries.flatMap { [$0.value] + $0.conflictCandidates }
            .flatMap { $0.provenance.map(\.sourceReleaseID) } + [target.sourceRelease.sourceReleaseID])
            .sorted { $0.value < $1.value }
    }

    public static func hasNoKnownContradictions(before: StoredFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        let old = before.productVersion.identity
        let new = candidate.candidate.identity
        let quantity = EdibleQuantityIdentity.known(before.logItemVersion.edibleQuantity, conversionVersionID: nil)
        guard IdentityCompatibility.contradictions(between: old, and: old, expectedEdibleQuantity: quantity, candidateEdibleQuantity: quantity).isEmpty,
              candidate.itemClass == before.productVersion.itemClass,
              new.servingBasis == old.servingBasis else { return false }
        if new.preparation.kind != .unknown && new.preparation != old.preparation { return false }
        if new.bone != .unknown && new.bone != old.bone { return false }
        if new.skin != .unknown && new.skin != old.skin { return false }
        if new.drained != .unknown && new.drained != old.drained { return false }
        if new.packingMedium != .unknown && new.packingMedium != old.packingMedium { return false }
        if new.fortification != .unknown && (new.fortification != old.fortification || new.declaredFortificants != old.declaredFortificants) { return false }
        return true
    }
}
