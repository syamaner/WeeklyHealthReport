import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// Copy for the Food Log and the saved entry (#197), formatted from application values.
/// British spelling, plain language, no interpretation.
public enum FoodLogText {
    public static let totalsFootnote = "Known values only. “+” means at least one entry has this nutrient unknown."
    public static let emptyTitle = "No food logged"
    public static let emptyMessage = "An empty log does not mean no food was eaten."
    public static let swipeFootnote = "Swipe an entry to remove it. Removed entries can be restored."
    public static let pastDayFootnote = "New foods are logged for now. To log on this day, set When on the confirm screen."
    public static let removeAlertTitle = "Remove this entry?"
    public static let removeAlertMessage = "It leaves this day’s totals. You can restore it from Removed in the Food Log."
    public static let savedEntryFootnote = "Edit keeps the original as history. Exports already sent are not changed."
    public static let estimateNotice = "Unknown details stay unknown"

    // MARK: Numbers

    static func number(_ value: Double, fraction: ClosedRange<Int> = 0...1, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(fraction)).locale(locale))
    }

    /// kcal to the nearest whole number, half away from zero.
    public static func kcal(_ value: Double, locale: Locale = .current) -> String {
        number(value.rounded(.toNearestOrAwayFromZero), fraction: 0...0, locale: locale)
    }

    public static func label(_ key: NutrientKey) -> String { FoodNutritionReviewPresentation.label(key) }

    // MARK: Totals strip

    /// "1,240", "68 g", "41 g+", or "Unknown" when no entry has a known value.
    public static func total(_ total: FoodIntakeTotal, locale: Locale = .current) -> String {
        guard let amount = total.knownAmount else { return "Unknown" }
        let value = total.key == .energyConsumed
            ? kcal(amount, locale: locale)
            : "\(number(amount, locale: locale)) \(total.key.canonicalUnit.rawValue)"
        return total.incompleteContributions > 0 ? value + "+" : value
    }

    /// Spoken form: "Fat, at least 41 grams", "Energy, 1,240 kilocalories", "Fat, unknown".
    public static func totalAccessibility(_ total: FoodIntakeTotal, locale: Locale = .current) -> String {
        let name = label(total.key)
        guard let amount = total.knownAmount else { return "\(name), unknown" }
        let value = total.key == .energyConsumed
            ? "\(kcal(amount, locale: locale)) kilocalories"
            : "\(number(amount, locale: locale)) \(spokenUnit(total.key.canonicalUnit))"
        return total.incompleteContributions > 0 ? "\(name), at least \(value)" : "\(name), \(value)"
    }

    static func spokenUnit(_ unit: NutrientUnit) -> String {
        switch unit {
        case .grams: "grams"
        case .milligrams: "milligrams"
        case .micrograms: "micrograms"
        case .millilitres: "millilitres"
        case .kilocalories: "kilocalories"
        }
    }

    // MARK: Entries

    /// "150 g", "200 mL", "2 units".
    public static func amount(_ quantity: PositiveQuantity, locale: Locale = .current) -> String {
        let value = number(quantity.value, fraction: 0...2, locale: locale)
        switch quantity.unit {
        case .grams: return "\(value) g"
        case .millilitres: return "\(value) mL"
        case .count: return quantity.value == 1 ? "1 unit" : "\(value) units"
        }
    }

    /// "248 kcal", or "Energy unknown" (never blank, never zero).
    public static func entryEnergy(_ entry: FoodLogDayContent.Entry, locale: Locale = .current) -> String {
        entry.energyKcal.map { "\(kcal($0, locale: locale)) kcal" } ?? "Energy unknown"
    }

    /// One flags line: "Estimate" at most once, then "<Nutrient> unknown" for unknown strip
    /// nutrients other than energy (energy has its own slot). Empty when there is nothing to flag.
    public static func flags(_ entry: FoodLogDayContent.Entry) -> String {
        var parts = entry.isEstimate ? ["Estimate"] : []
        parts += entry.unknownKeys.filter { $0 != .energyConsumed }.map { "\(label($0)) unknown" }
        return parts.joined(separator: " · ")
    }

    public static func entryAccessibility(_ entry: FoodLogDayContent.Entry, time: String, locale: Locale = .current) -> String {
        let flags = flags(entry)
        return [time, entry.name, amount(entry.quantity, locale: locale), entryEnergy(entry, locale: locale), flags]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// "Removed 11:02 · not in totals".
    public static func removedLine(removedAt: String?) -> String {
        removedAt.map { "Removed \($0) · not in totals" } ?? "Removed · not in totals"
    }

    public static func removedHeader(_ count: Int) -> String { count == 1 ? "Removed · 1 entry" : "Removed · \(count) entries" }

    public static func changeAlert(_ outcome: FoodLogChangeOutcome) -> String {
        switch outcome {
        case .applied: ""
        case .changedElsewhere: "This entry changed elsewhere. The log has been refreshed."
        case .notSaved: "The change could not be saved. Try again."
        }
    }

    public static func failure(_ failure: FoodLogViewModel.Failure) -> String {
        switch failure {
        case .competingVersions: "Conflicting food versions need review before an intake total can be shown."
        case .mixedMeal: "This day includes a mixed meal that cannot yet be totalled safely."
        case .unreadable: "The local food log could not be read. Unlock your device and try again."
        }
    }

    // MARK: Saved entry

    /// "150 g", or "2 units · 240 g" when the edible amount differs from what was entered.
    public static func savedAmount(_ detail: SavedFoodEntryDetail, locale: Locale = .current) -> String {
        let entered = amount(detail.enteredAmount, locale: locale)
        return detail.enteredAmount == detail.edibleQuantity ? entered : "\(entered) · \(amount(detail.edibleQuantity, locale: locale))"
    }

    public static func notCalculableTitle() -> String { "Nutrition can’t be calculated for this amount" }

    public static func notCalculableReason(_ reason: SavedFoodEntryDetail.NotCalculableReason) -> String {
        switch reason {
        case .unknownBasis:
            return "The source does not say what amount its values are for."
        case let .unitMismatch(basis, unit):
            return "The source gives values \(basisPhrase(basis)); this entry is in \(unitPhrase(unit))."
        }
    }

    static func basisPhrase(_ basis: ResolutionBasis) -> String {
        switch basis {
        case .per100Grams: "per 100 g"
        case .per100Millilitres: "per 100 mL"
        default: FoodNutritionReviewPresentation.basisLabel(basis).lowercased()
        }
    }

    static func unitPhrase(_ unit: QuantityUnit) -> String {
        switch unit { case .grams: "g"; case .millilitres: "mL"; case .count: "units" }
    }

    /// "Unknown" for unknown, bounded or unscalable values; "Estimated" beside augmented values.
    public static func nutrient(_ total: FoodIntakeTotal, locale: Locale = .current) -> String {
        guard let amount = total.knownAmount else { return "Unknown" }
        let value = total.key == .energyConsumed
            ? "\(kcal(amount, locale: locale)) kcal"
            : "\(number(amount, locale: locale)) \(total.key.canonicalUnit.rawValue)"
        return total.includesEstimates ? "\(value) · Estimated" : value
    }

    public static func source(_ detail: SavedFoodEntryDetail) -> String {
        "\(FoodSearchResultText.family(detail.sourceFamily)) · \(FoodNutritionReviewPresentation.basisLabel(detail.basis).lowercased())"
    }

    public static func facet(_ facet: IdentityContradiction) -> String {
        switch facet {
        case .preparation: "Preparation"
        case .bone: "Bone"
        case .skin: "Skin"
        case .drained: "Drained"
        case .packingMedium: "Liquid"
        case .fortification: "Fortification"
        case .servingBasis: "Nutrition basis"
        case .edibleQuantity: "Serving"
        }
    }

    public static func decision(_ decision: FoodLogFacetDecision) -> String {
        FoodLogRequirementText.choice(decision.choice, facet: decision.facet, source: decision.sourceState)
    }

    /// One history line without its time: "Logged", "Amount changed 120 g to 150 g", ...
    public static func history(_ kind: FoodEntryHistoryEvent.Kind, time: (Date) -> String, locale: Locale = .current) -> String {
        switch kind {
        case .logged: return "Logged"
        case .removed: return "Removed"
        case .restored: return "Restored"
        case .nutritionUpdated: return "Nutrition updated"
        case let .corrected(amount, change):
            return (["Food details corrected"] + changes(amount, change, time: time, locale: locale)).joined(separator: " · ")
        case let .changed(amount, change):
            let parts = changes(amount, change, time: time, locale: locale)
            return parts.isEmpty ? "Saved again without changes" : parts.joined(separator: " · ")
        }
    }

    private static func changes(_ amount: FoodEntryHistoryEvent.AmountChange?, _ change: FoodEntryHistoryEvent.TimeChange?,
                                time: (Date) -> String, locale: Locale) -> [String] {
        var parts: [String] = []
        if let amount {
            var text = "Amount changed \(self.amount(amount.from, locale: locale)) to \(self.amount(amount.to, locale: locale))"
            if let from = amount.edibleFrom, let to = amount.edibleTo, from != to {
                text += " (\(self.amount(from, locale: locale)) to \(self.amount(to, locale: locale)))"
            }
            parts.append(text)
        }
        if let change { parts.append("Time changed \(time(change.from)) to \(time(change.to))") }
        return parts
    }
}
