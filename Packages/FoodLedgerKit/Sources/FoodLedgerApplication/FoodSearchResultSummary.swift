import Foundation
import FoodLedgerDomain

/// Structured, plain-language facts for one search result row. Presentation formats them
/// ("UK reference · cooked · 248 kcal for 150 g"); no text is produced here.
public struct FoodSearchResultSummary: Equatable, Sendable {
    public enum SourceFamily: Equatable, Sendable {
        case ukReference, usReference, taiwanReference, packagedProduct, webSource, yourFoods, otherSource
    }
    public enum Energy: Equatable, Sendable {
        /// Energy scaled to the amount: kcal rounded to a whole number, half away from zero.
        case forAmount(kcal: Int, quantity: PositiveQuantity)
        /// No figure for the amount; the source basis is shown instead.
        case basisOnly(ResolutionBasis)
    }

    public let family: SourceFamily
    public let preparation: PreparationKind
    public let energy: Energy
    /// Energy the source states for its per 100 g or per 100 mL basis, whole kcal (half away
    /// from zero). Nil when energy is unknown, bounded or the basis is anything else, so an
    /// unknown is never shown as 0 (#308).
    public let basisEnergyKcal: Int?
    /// Raw identifiers, for Developer tools only.
    public let sourceID: String
    public let sourceReleaseID: String
    public let recordID: String

    public init(family: SourceFamily, preparation: PreparationKind, energy: Energy, basisEnergyKcal: Int? = nil,
                sourceID: String = "", sourceReleaseID: String = "", recordID: String = "") {
        self.family = family; self.preparation = preparation; self.energy = energy
        self.basisEnergyKcal = basisEnergyKcal
        self.sourceID = sourceID; self.sourceReleaseID = sourceReleaseID; self.recordID = recordID
    }

    public init(candidate: PopulatedFoodCandidate, releases: [SourceRelease], amount: ParsedFoodQuery.Quantity?) {
        let source = candidate.candidate
        let sourceID = releases.first { $0.sourceReleaseID == source.sourceReleaseID }?.sourceID.value ?? ""
        self.sourceID = sourceID
        sourceReleaseID = source.sourceReleaseID.value
        recordID = source.recordID.value
        family = Self.family(sourceID, recordID: source.recordID.value)
        preparation = source.identity.preparation.kind
        energy = Self.energy(nutrients: source.nutrients, basis: source.identity.servingBasis, amount: amount)
        basisEnergyKcal = Self.basisEnergy(nutrients: source.nutrients, basis: source.identity.servingBasis)
    }

    /// The family of the source a candidate came from, so Confirm names the source with the
    /// same words as its search result row (#308).
    public static func family(candidate: ProviderNeutralCandidate, releases: [SourceRelease]) -> SourceFamily {
        let sourceID = releases.first { $0.sourceReleaseID == candidate.sourceReleaseID }?.sourceID.value ?? ""
        return family(sourceID, recordID: candidate.recordID.value)
    }

    /// Stated energy per 100 g or per 100 mL: only an exact (measured or augmented) value on
    /// one of those two bases. Unknown, bounded and every other basis give nil, never 0.
    public static func basisEnergy(nutrients: NutrientSet, basis: ResolutionBasis) -> Int? {
        switch basis {
        case .per100Grams, .per100Millilitres: break
        default: return nil
        }
        guard let entry = nutrients.entries.first(where: { $0.key == .energyConsumed }) else { return nil }
        let amount: Double
        switch entry.value {
        case let .measured(value), let .augmented(value): amount = value.amount
        case .bounded, .unknown: return nil
        }
        let kcal = amount.rounded(.toNearestOrAwayFromZero)
        guard kcal.isFinite, kcal >= 0, kcal < Double(Int.max) else { return nil }
        return Int(kcal)
    }

    /// Closed mapping. "Your foods" is only the personal library and user-verified packages;
    /// anything unmapped or empty is a neutral "other source", never presented as the user's own.
    public static func family(_ sourceID: String, recordID: String = "") -> SourceFamily {
        if recordID.hasPrefix("personal-library:") || sourceID == "physical_package" { return .yourFoods }
        let id = sourceID.lowercased()
        if id.contains("cofid") { return .ukReference }
        if id.contains("usda") { return .usReference }
        if id == "tfda-taiwan" { return .taiwanReference }
        if id.contains("openfoodfacts") || id.contains("open-food-facts") { return .packagedProduct }
        if id == "reviewed-web-proposal" { return .webSource }
        return .otherSource
    }

    /// Energy for the amount only when energy is exact (measured or augmented) and the amount's
    /// unit matches a per 100 g or per 100 mL basis. Only mL spelling is normalised; any other
    /// unit (oz, count), named or serving bases and unknown or bounded energy are basis-only.
    public static func energy(nutrients: NutrientSet, basis: ResolutionBasis, amount: ParsedFoodQuery.Quantity?) -> Energy {
        guard let amount, amount.value.isFinite, amount.value > 0,
              let entry = nutrients.entries.first(where: { $0.key == .energyConsumed }) else { return .basisOnly(basis) }
        let exact: ExactNutrientValue
        switch entry.value {
        case let .measured(value), let .augmented(value): exact = value
        case .bounded, .unknown: return .basisOnly(basis)
        }
        let unit: QuantityUnit
        switch (basis, amount.unit) {
        case (.per100Grams, "g"): unit = .grams
        case (.per100Millilitres, let text) where text.lowercased() == "ml": unit = .millilitres
        default: return .basisOnly(basis)
        }
        guard let quantity = try? PositiveQuantity(value: amount.value, unit: unit) else { return .basisOnly(basis) }
        let kcal = (exact.amount * amount.value / 100).rounded(.toNearestOrAwayFromZero)
        guard kcal.isFinite, abs(kcal) < Double(Int.max) else { return .basisOnly(basis) }
        return .forAmount(kcal: Int(kcal), quantity: quantity)
    }
}
