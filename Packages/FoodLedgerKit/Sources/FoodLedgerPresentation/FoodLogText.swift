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

    /// The narrow totals strip abbreviates carbohydrates; VoiceOver keeps the full word.
    public static func stripLabel(_ key: NutrientKey) -> String { key == .carbohydrates ? "Carbs" : label(key) }

    // MARK: Totals strip

    /// Plain water logged (#198, Q8): the same label and figure on Home and in the Food Log.
    public static let plainWaterLabel = "Plain water logged"
    public static let plainWaterNoData = "No data"

    /// "730 mL", "730 mL+" (a known minimum), or "No data" when no plain water is logged (never 0 mL).
    public static func plainWater(_ total: FoodIntakeTotal?, locale: Locale = .current) -> String {
        guard let total else { return plainWaterNoData }
        guard let amount = total.knownAmount else { return "Unknown" }
        let value = "\(number(amount, locale: locale)) mL"
        return total.incompleteContributions > 0 ? value + "+" : value
    }

    public static func plainWaterAccessibility(_ total: FoodIntakeTotal?, locale: Locale = .current) -> String {
        guard let total else { return "\(plainWaterLabel), no data" }
        guard let amount = total.knownAmount else { return "\(plainWaterLabel), unknown" }
        let value = "\(number(amount, locale: locale)) millilitres"
        return total.incompleteContributions > 0 ? "\(plainWaterLabel), at least \(value)" : "\(plainWaterLabel), \(value)"
    }

    /// "1,240", "68 g", "41 g+", or "Unknown" when no entry has a known value.
    public static func total(_ total: FoodIntakeTotal, locale: Locale = .current) -> String {
        guard let amount = total.knownAmount else { return "Unknown" }
        let value = total.key == .energyConsumed
            ? kcal(amount, locale: locale)
            : "\(number(amount, locale: locale)) \(total.key.canonicalUnit.rawValue)"
        return total.incompleteContributions > 0 ? value + "+" : value
    }

    /// A caption under a strip total whose known values include estimates (augmented values or an
    /// estimated weight); nil otherwise.
    public static func totalCaption(_ total: FoodIntakeTotal) -> String? {
        total.knownAmount != nil && total.includesEstimates ? "Includes estimates" : nil
    }

    /// Spoken form: "Fat, at least 41 grams", "Energy, 1,240 kilocalories", "Fat, unknown".
    public static func totalAccessibility(_ total: FoodIntakeTotal, locale: Locale = .current) -> String {
        let name = label(total.key)
        guard let amount = total.knownAmount else { return "\(name), unknown" }
        let value = total.key == .energyConsumed
            ? "\(kcal(amount, locale: locale)) kilocalories"
            : "\(number(amount, locale: locale)) \(spokenUnit(total.key.canonicalUnit))"
        let spoken = total.incompleteContributions > 0 ? "\(name), at least \(value)" : "\(name), \(value)"
        return totalCaption(total) == nil ? spoken : "\(spoken), includes estimates"
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

    /// "Removed 11:02 · not in totals" on the day shown, otherwise "Removed yesterday, 11:02 · …".
    public static func removedLine(removedAt: String?) -> String {
        removedAt.map { "Removed \($0) · not in totals" } ?? "Removed · not in totals"
    }

    public static func removedLine(_ entry: FoodLogDayContent.RemovedEntry, now: Date, calendar: Calendar,
                                   locale: Locale = .current) -> String {
        guard let removedAt = entry.removedAt else { return removedLine(removedAt: nil) }
        let sameDay = calendar.isDate(removedAt, inSameDayAs: entry.occurredAt)
        return removedLine(removedAt: sameDay ? time(removedAt, calendar: calendar, locale: locale)
                                              : when(removedAt, now: now, calendar: calendar, locale: locale))
    }

    // MARK: Times

    /// "00:18" (two-digit hour, as Confirm's time picker shows it) in the calendar's time zone;
    /// 12-hour locales keep their AM/PM marker. One formatter for the Food Log, history and Home.
    public static func time(_ date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits))
    }

    /// "today, 12:40", "yesterday, 08:00" or "9 Oct, 12:40".
    public static func when(_ date: Date, now: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let day: String
        if calendar.isDate(date, inSameDayAs: now) { day = "today" }
        else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { day = "yesterday" }
        else {
            day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated))
        }
        return "\(day), \(time(date, calendar: calendar, locale: locale))"
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

    /// "Unknown" for unknown, bounded or unscalable values; "Estimated" only beside a value the
    /// source augmented. A whole-entry estimate (an estimated weight) is stated once in the header.
    public static func nutrient(_ total: FoodIntakeTotal, augmented: Bool = false, locale: Locale = .current) -> String {
        guard let amount = total.knownAmount else { return "Unknown" }
        let value = total.key == .energyConsumed
            ? "\(kcal(amount, locale: locale)) kcal"
            : "\(number(amount, locale: locale)) \(total.key.canonicalUnit.rawValue)"
        return augmented ? "\(value) · Estimated" : value
    }

    /// The header's estimate line, or nil: "Estimate · Unknown details stay unknown".
    public static func headerEstimate(_ detail: SavedFoodEntryDetail) -> String? {
        if detail.isEstimate { return "Estimate · \(estimateNotice)" }
        if detail.weightIsEstimated { return "Estimate · The weight was estimated" }
        return nil
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

    /// One history line without its time: "Logged", "Amount changed 120 g to 150 g", ... A time
    /// change across days names both days ("yesterday, 12:40 to today, 12:40").
    public static func history(_ kind: FoodEntryHistoryEvent.Kind, now: Date, calendar: Calendar,
                               locale: Locale = .current) -> String {
        history(kind, time: { [calendar] from, to in
            calendar.isDate(from, inSameDayAs: to)
                ? (time(from, calendar: calendar, locale: locale), time(to, calendar: calendar, locale: locale))
                : (when(from, now: now, calendar: calendar, locale: locale), when(to, now: now, calendar: calendar, locale: locale))
        }, locale: locale)
    }

    static func history(_ kind: FoodEntryHistoryEvent.Kind, time: (Date, Date) -> (String, String), locale: Locale) -> String {
        switch kind {
        case .logged: return "Logged"
        case .removed: return "Removed"
        case .restored: return "Restored"
        case .nutritionUpdated: return "Nutrition updated"
        case .weightDetailsChanged: return "Weight details changed"
        case let .corrected(amount, change):
            return (["Food details corrected"] + changes(amount, change, time: time, locale: locale)).joined(separator: " · ")
        case let .changed(amount, change):
            let parts = changes(amount, change, time: time, locale: locale)
            return parts.isEmpty ? "Saved again without changes" : parts.joined(separator: " · ")
        }
    }

    private static func changes(_ amount: FoodEntryHistoryEvent.AmountChange?, _ change: FoodEntryHistoryEvent.TimeChange?,
                                time: (Date, Date) -> (String, String), locale: Locale) -> [String] {
        var parts: [String] = []
        if let amount {
            var text = "Amount changed \(self.amount(amount.from, locale: locale)) to \(self.amount(amount.to, locale: locale))"
            if let from = amount.edibleFrom, let to = amount.edibleTo, from != to {
                text += " (\(self.amount(from, locale: locale)) to \(self.amount(to, locale: locale)))"
            }
            parts.append(text)
        }
        if let change {
            let (from, to) = time(change.from, change.to)
            parts.append("Time changed \(from) to \(to)")
        }
        return parts
    }
}
