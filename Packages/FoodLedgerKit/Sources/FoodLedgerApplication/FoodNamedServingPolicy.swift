import FoodLedgerDomain

/// Closed exception for explicitly selected, source-declared recipe servings.
/// Ordinary counts still require a measured conversion; a named serving never supplies grams.
public enum FoodNamedServingPolicy {
    public static let version = "food-named-recipe-serving-v1"
    public static func applies(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        let source = candidate.candidate
        guard source.identity.servingBasis == FoodSourceRecipeProfile.basis,
              let release = input.sourceReleases.first(where: { $0.sourceReleaseID == source.sourceReleaseID }),
              release.schemaVersion.value == FoodSourceRecipeProfile.schema,
              input.evidence.contains(where: { source.evidenceIDs.contains($0.evidenceID) && $0.kind == .genericSearch }) else { return false }
        let provenance = source.nutrients.entries.flatMap { $0.value.provenance }
        return !provenance.isEmpty && provenance.allSatisfy {
            $0.sourceKind == .recipeReconstruction && $0.sourceReleaseID == source.sourceReleaseID
                && $0.sourceID == release.sourceID && $0.recordID == source.recordID && $0.responseHash == release.artifactHash
        }
    }
}

extension FoodConfirmationState {
    public var isSourceRecipe: Bool { FoodNamedServingPolicy.applies(input, candidate: selectedCandidate) }
    /// A source recipe serving is a user-entered fraction/count of that recipe, not food pieces.
    public func calculatedEdibleQuantity() throws -> PositiveQuantity {
        guard isSourceRecipe else { return try quantity.calculatedEdibleQuantity() }
        let basis = (correction?.identity ?? reopened?.productVersion.identity ?? selectedCandidate.candidate.identity).servingBasis
        guard basis == FoodSourceRecipeProfile.basis, quantity.unit == .count,
              quantity.directWeight == nil, quantity.conversion == nil, quantity.plateChoice == .foodOnly else {
            throw FoodLedgerValidationError.invalidUnit
        }
        return try quantity.calculationInput()
    }
}
