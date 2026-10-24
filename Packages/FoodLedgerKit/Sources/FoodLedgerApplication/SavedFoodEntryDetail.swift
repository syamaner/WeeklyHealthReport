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
    /// The whole entry is an estimate because its quantity was estimated: by eye, a typical
    /// weight or the whole-milk volume rule (count-portion-estimate-v1, C6). Stated once, in the header.
    public let weightIsEstimated: Bool
    /// How the amount was obtained (C7), shown on the header and in history.
    public let quantityMethod: FoodQuantityMethod
    /// Nutrients whose source value is augmented (estimated); marked beside that value only.
    public let augmentedKeys: Set<NutrientKey>
    public let nutrition: Nutrition
    public let basis: ResolutionBasis
    public let sourceFamily: FoodSearchResultSummary.SourceFamily
    public let decisions: [FoodLogFacetDecision]
    public let history: [FoodEntryHistoryEvent]
    /// The app's plain water reference: not offered as a favourite (it has its own quick add item).
    public let isPlainWater: Bool
    /// A pasted nutrition label's stored manifest (#93), for the per-value origins and Report a
    /// misread; nil for every other route.
    public let pastedLabel: PastedLabelEvidenceManifest?
    /// Each stored value's origin under `NutrientValueOrigin`, for a pasted label only.
    public let valueOrigins: [NutrientKey: NutrientValueOrigin]
    /// A pasted label's stored values by key, so a bound can be shown as a bound ("Less than
    /// 0.5 g per 100 g") rather than as an unknown consumed amount. Empty for other routes.
    public let pastedLabelValues: [NutrientKey: NutrientValue]
    /// The entered amount is a pasted label's servings (#93), not units.
    public let amountIsServings: Bool
    /// The serving size those servings went through and its origin; nil when they carry no
    /// weight or volume, or the amount is not in servings.
    public let servingSize: (quantity: PositiveQuantity, origin: NutrientValueOrigin)?

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
        weightIsEstimated = FoodQuantityEstimate.isEstimate(log, conversion: stored.quantityConversion)
        quantityMethod = FoodQuantityMethod.of(log, conversion: stored.quantityConversion)
        augmentedKeys = Set(stored.resolutionVersion.nutrients.entries.compactMap { entry in
            if case .augmented = entry.value { return entry.key } else { return nil }
        })
        basis = stored.resolution.basis
        isPlainWater = PlainWaterReference.isPlainWater(stored.resolutionVersion)
        nutrition = Self.nutrition(quantity: log.edibleQuantity, basis: stored.resolution.basis,
                                   nutrients: stored.resolutionVersion.nutrients,
                                   quantityIsEstimate: FoodQuantityEstimate.isEstimate(log, conversion: stored.quantityConversion))
        let release = stored.sourceReleases.first { $0.sourceReleaseID == stored.candidateDecision.candidate.sourceReleaseID }
        sourceFamily = FoodSearchResultSummary.family(release?.sourceID.value ?? "",
                                                      recordID: stored.candidateDecision.candidate.recordID.value)
        decisions = stored.assertions.flatMap { $0.confirmation?.decisions ?? [] }
        self.history = history
        let manifest = release?.sourceID.value == PastedLabelSource.sourceID
            ? PastedLabelValueOrigins.manifest(evidence: stored.evidence, evidenceIDs: stored.candidateDecision.candidate.evidenceIDs) : nil
        pastedLabel = manifest
        valueOrigins = manifest.map { PastedLabelValueOrigins.origins(stored.resolutionVersion.nutrients, manifest: $0) } ?? [:]
        pastedLabelValues = manifest == nil ? [:]
            : Dictionary(stored.resolutionVersion.nutrients.entries.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        amountIsServings = PastedLabelServingPolicy.isServingsAmount(enteredUnit: enteredAmount.unit, conversion: stored.quantityConversion,
                                                                     sourceID: release?.sourceID.value)
        servingSize = amountIsServings && stored.quantityConversion != nil
            ? manifest.flatMap { PastedLabelServingPolicy.storedServingSize($0, basis: stored.resolution.basis) } : nil
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
