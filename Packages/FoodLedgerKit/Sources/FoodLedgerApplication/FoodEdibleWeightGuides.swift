import FoodLedgerDomain

/// Optional future adapter boundary. Empty means no evidenced guide for this record.
/// No guide adapter or portion dataset is enabled by this repair.
public protocol FoodEdibleWeightGuideProviding: Sendable {
    func guides(for candidate: PopulatedFoodCandidate) throws -> [FoodEdibleWeightGuide]
}

/// A food-specific edible mass, never a shell-on grade or a universal portion.
public struct FoodEdibleWeightGuide: Equatable, Sendable {
    public let foodRecordID: ExternalIdentifier
    public let foodSourceReleaseID: ExternalIdentifier
    public let guideID: ExternalIdentifier
    public let guideVersion: LedgerText
    public let size: LedgerText
    public let edibleGramsPerPiece: Double
    public let sourceReleaseID: ExternalIdentifier
    public let evidenceID: EvidenceID

    public init(foodRecordID: ExternalIdentifier, foodSourceReleaseID: ExternalIdentifier,
                guideID: ExternalIdentifier, guideVersion: LedgerText, size: LedgerText,
                edibleGramsPerPiece: Double, sourceReleaseID: ExternalIdentifier, evidenceID: EvidenceID) throws {
        _ = try PositiveQuantity(value: edibleGramsPerPiece, unit: .grams)
        self.foodRecordID = foodRecordID; self.foodSourceReleaseID = foodSourceReleaseID
        self.guideID = guideID; self.guideVersion = guideVersion; self.size = size
        self.edibleGramsPerPiece = edibleGramsPerPiece
        self.sourceReleaseID = sourceReleaseID; self.evidenceID = evidenceID
    }

    public func estimate(for candidate: PopulatedFoodCandidate, count: Double,
                         measuredOverride: PositiveQuantity? = nil) throws -> FoodEdibleWeightEstimate {
        guard candidate.candidate.recordID == foodRecordID,
              candidate.candidate.sourceReleaseID == foodSourceReleaseID else {
            throw FoodLedgerValidationError.invalidProvenance
        }
        let countQuantity = try PositiveQuantity(value: count, unit: .count)
        let estimate = try PositiveQuantity(value: count * edibleGramsPerPiece, unit: .grams)
        guard measuredOverride == nil || measuredOverride?.unit == .grams else {
            throw FoodLedgerValidationError.invalidBasis
        }
        return FoodEdibleWeightEstimate(count: countQuantity, guide: self,
            estimatedEdibleWeight: estimate, measuredOverride: measuredOverride)
    }
}

/// Estimate and override are separate; this preview is not a persisted conversion.
/// Enabling guides requires a versioned persistence contract and approved source.
public struct FoodEdibleWeightEstimate: Equatable, Sendable {
    public let count: PositiveQuantity
    public let guide: FoodEdibleWeightGuide
    public let estimatedEdibleWeight: PositiveQuantity
    public let measuredOverride: PositiveQuantity?
    public var finalEdibleWeight: PositiveQuantity { measuredOverride ?? estimatedEdibleWeight }
}
