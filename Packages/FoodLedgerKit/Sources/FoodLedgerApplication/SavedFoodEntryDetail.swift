import Foundation
import FoodLedgerDomain

/// Read-only content of a saved entry (#197), structured for presentation to format.
public struct SavedFoodEntryDetail: Sendable {
    public enum Nutrition: Equatable, Sendable {
        /// Totals for the amount, one per nutrient key, from the same single-contribution
        /// summary the Food Log adds up.
        case calculated([FoodIntakeTotal])
        /// The amount cannot be scaled against the source basis; no figures and never zero.
        case notCalculable(NotCalculableReason)
    }

    public enum NotCalculableReason: Equatable, Sendable {
        case unitMismatch(basis: ResolutionBasis, unit: QuantityUnit)
        case unknownBasis
    }

    public let logItemID: LogItemID
    public let logItemVersionID: LogItemVersionID
    public let name: String
    public let variant: String?
    public let occurredAt: Date
    public let reportingDate: String
    /// The amount as entered (value and unit).
    public let enteredAmount: PositiveQuantity
    /// The edible amount used for nutrition.
    public let edibleQuantity: PositiveQuantity
    public let isEstimate: Bool
    /// The whole entry is an estimate because its weight was estimated (stated once, in the header).
    public let weightIsEstimated: Bool
    /// Nutrients whose source value is augmented (estimated); marked beside that value only.
    public let augmentedKeys: Set<NutrientKey>
    public let nutrition: Nutrition
    public let basis: ResolutionBasis
    public let sourceFamily: FoodSearchResultSummary.SourceFamily
    public let decisions: [FoodLogFacetDecision]
    public let history: [FoodEntryHistoryEvent]
    /// The app's plain water reference: not offered as a favourite (it has its own quick add item).
    public let isPlainWater: Bool

    public init(stored: StoredFoodConfirmation, isEstimate: Bool, history: [FoodEntryHistoryEvent]) {
        let log = stored.logItemVersion
        logItemID = log.logItemID
        logItemVersionID = log.logItemVersionID
        name = stored.productVersion.name.value
        variant = stored.productVersion.variant?.value
        occurredAt = log.occurredAt
        reportingDate = log.reportingDate.value
        let entered = FoodConfirmationService.lastEnteredAmount(log, conversion: stored.quantityConversion)
        enteredAmount = (try? PositiveQuantity(value: entered.value, unit: entered.unit)) ?? log.edibleQuantity
        edibleQuantity = log.edibleQuantity
        self.isEstimate = isEstimate
        weightIsEstimated = log.weightDeclaration?.basis == .estimated
        augmentedKeys = Set(stored.resolutionVersion.nutrients.entries.compactMap { entry in
            if case .augmented = entry.value { return entry.key } else { return nil }
        })
        basis = stored.resolution.basis
        isPlainWater = PlainWaterReference.isPlainWater(stored.resolutionVersion)
        nutrition = Self.nutrition(quantity: log.edibleQuantity, basis: stored.resolution.basis,
                                   nutrients: stored.resolutionVersion.nutrients,
                                   quantityIsEstimate: log.weightDeclaration?.basis == .estimated)
        let release = stored.sourceReleases.first { $0.sourceReleaseID == stored.candidateDecision.candidate.sourceReleaseID }
        sourceFamily = FoodSearchResultSummary.family(release?.sourceID.value ?? "",
                                                      recordID: stored.candidateDecision.candidate.recordID.value)
        decisions = stored.assertions.flatMap { $0.confirmation?.decisions ?? [] }
        self.history = history
    }

    /// One scaling rule: `FoodIntakeContribution.isScalable`, as the summary applies it.
    public static func nutrition(quantity: PositiveQuantity, basis: ResolutionBasis, nutrients: NutrientSet?,
                                 quantityIsEstimate: Bool) -> Nutrition {
        let contribution = FoodIntakeContribution(quantity: quantity, basis: basis, nutrients: nutrients,
                                                  quantityIsEstimate: quantityIsEstimate)
        guard contribution.isScalable else {
            if case .unknown = basis { return .notCalculable(.unknownBasis) }
            return .notCalculable(.unitMismatch(basis: basis, unit: quantity.unit))
        }
        return .calculated(FoodIntakeSummary(contributions: [contribution]).totals)
    }
}
