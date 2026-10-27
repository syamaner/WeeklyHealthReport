import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// Copy for the Food Log and the saved entry (#197), formatted from application values.
/// British spelling, plain language, no interpretation.
public enum FoodLogText {
    /// Plain copy for a stored quantity conversion method; identifiers stay behind the Developer
    /// tools disclosure (#306 journey QA). Nil for text the user typed, which is shown as typed.
    public static func conversionMethodLabel(_ methodVersion: String) -> String? {
        if LabelServingPolicy.admittedVersions.contains(methodVersion) { return PastedLabelText.servingConversionMethod }
        switch methodVersion {
        case FoodNamedServingPolicy.version: return "From the recipe’s serving"
        case FoodSourceServingPolicy.version: return "From the source’s serving size"
        default: return nil
        }
    }

    public static let totalsFootnote = "Known values only. “+” means at least one entry has this nutrient unknown."

    /// The totals strip footnote, only when a figure actually shows "+" (a known minimum), as
    /// Home words its footnote only when needed (#308). Nil when every figure is complete or
    /// wholly unknown, so the "+" is never explained where none is shown.
    public static func totalsFootnote(_ totals: [FoodIntakeTotal], plainWater: FoodIntakeTotal?) -> String? {
        (totals + [plainWater].compactMap { $0 }).contains(where: showsPlus) ? totalsFootnote : nil
    }

    /// Whether a strip figure carries "+": a known part with at least one unknown contribution.
    public static func showsPlus(_ total: FoodIntakeTotal) -> Bool {
        total.knownAmount != nil && total.incompleteContributions > 0
    }
    public static let emptyTitle = "No food logged"
    public static let emptyMessage = "An empty log does not mean no food was eaten."
    public static let swipeFootnote = "Swipe an entry to remove it. Removed entries can be restored."
    /// Add food from a past day (owner decision D): When starts on that day at the current time.
    public static let pastDayFootnote = "New foods start on this day at the current time. You can change When before logging."
    /// A selected day older than the backdating window: When falls back to Now.
    public static let backdatingLimitNotice = "Entries can be logged up to \(FoodLogPolicy.backdatingDays) days back."
    /// Shown in place of Add food on a Food Log day older than the backdating window (owner
    /// decision, 14 October 2026); the day header's Return to today selects today.
    public static let addFoodBeyondWindow = backdatingLimitNotice

    /// Add food from a past day: list import keeps Now (confirmation v5 section 10).
    public static let listImportNowNote = "List items are logged for now."

    /// The list-route note on Add food: only when Add food carries a past day.
    public static func listImportNote(entryDay: String?) -> String? {
        entryDay == nil ? nil : listImportNowNote
    }

    /// The Add food footnote on the Food Log for the selected day, or nil for today and for a day
    /// beyond the backdating window (Add food is replaced there by `addFoodBeyondWindow`).
    public static func addFoodFootnote(_ prefill: FoodEntryWhenPrefill, isToday: Bool) -> String? {
        guard !isToday else { return nil }
        switch prefill {
        case .day: return pastDayFootnote
        case .beyondBackdatingWindow, .now: return nil
        }
    }

    /// The note beside When on Confirm and the quick-add sheet when the day could not be used.
    public static func whenNotice(_ prefill: FoodEntryWhenPrefill) -> String? {
        prefill == .beyondBackdatingWindow ? backdatingLimitNotice : nil
    }
    public static let removeAlertTitle = "Remove this entry?"
    public static let removeAlertMessage = "It leaves this day’s totals. You can restore it from Removed in the Food Log."
    public static let savedEntryFootnote = "Edit keeps the original as history. Exports already sent are not changed."
    public static let estimateNotice = "Unknown details stay unknown"

    /// A nutrient the source leaves unknown, in plain language for Source details (#308), never
    /// the raw reason identifier ("Unknown (notDeclared)").
    public static func unknownNutrient(_ reason: UnknownReason) -> String {
        switch reason {
        case .notDeclared: "Unknown, not stated by the source"
        case .noCompatibleSource: "Unknown, no matching source"
        case .missingConversion: "Unknown, could not be converted"
        case .conflictingEvidence: "Unknown, the sources disagree"
        }
    }

    // MARK: Numbers

    static func number(_ value: Double, fraction: ClosedRange<Int> = 0...1, locale: Locale) -> String {
        FoodDisplayNumber.amount(value, fraction: fraction, locale: locale)
    }

    /// kcal to the nearest whole number, half away from zero (the shared `FoodDisplayNumber`).
    public static func kcal(_ value: Double, locale: Locale = .current) -> String {
        FoodDisplayNumber.kcal(value, locale: locale)
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

    /// "1,240 kcal", "68 g", "41 g+", or "Unknown" when no entry has a known value. Energy
    /// carries its unit like every other figure (#308).
    public static func total(_ total: FoodIntakeTotal, locale: Locale = .current) -> String {
        guard let amount = total.knownAmount else { return "Unknown" }
        let value = total.key == .energyConsumed
            ? "\(kcal(amount, locale: locale)) kcal"
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

    /// "150 g", "200 mL", "2 pieces" (count-portion-estimate-v1, C8: one count word).
    public static func amount(_ quantity: PositiveQuantity, locale: Locale = .current) -> String {
        let value = number(quantity.value, fraction: 0...2, locale: locale)
        switch quantity.unit {
        case .grams: return "\(value) g"
        case .millilitres: return "\(value) mL"
        case .count: return "\(value) \(FoodAmountNoun.count(quantity.value))"
        }
    }

    /// The same text with each number kept on one line with its unit, so "168 g" never wraps as
    /// "168" / "g" at accessibility text sizes (#303). Display only: a no-break space replaces the
    /// space between a number and g, mL, kcal, piece(s) or serving(s). VoiceOver reads it the same.
    public static func keepingUnitsAttached(_ text: String) -> String {
        text.replacing(#/(\d) (?=(?:g|mL|kcal|pieces?|servings?)\b)/#) { match in "\(match.output.1)\u{00A0}" }
    }

    /// An entered count in servings: "1 serving", "2 servings".
    static func servings(_ quantity: PositiveQuantity, locale: Locale) -> String {
        "\(number(quantity.value, fraction: 0...2, locale: locale)) \(FoodAmountNoun.servings(quantity.value))"
    }

    /// The amount line (count-portion-estimate-v1, section 5): "3 pieces · about 150 g", "150 g",
    /// "200 mL · about 206 g". The edible amount reads "about" only when the quantity is an estimate.
    public static func amountLine(entered: PositiveQuantity?, edible: PositiveQuantity, isServings: Bool,
                                  method: FoodQuantityMethod, locale: Locale = .current) -> String {
        // Servings are servings even when no weight went through them ("2 servings").
        func counted(_ quantity: PositiveQuantity) -> String {
            isServings && quantity.unit == .count ? servings(quantity, locale: locale) : amount(quantity, locale: locale)
        }
        let edibleText = (method.isEstimate ? "about " : "") + counted(edible)
        guard let entered, entered != edible else { return edibleText }
        return "\(counted(entered)) · \(edibleText)"
    }

    /// A Food Log row's amount line.
    public static func entryAmount(_ entry: FoodLogDayContent.Entry, locale: Locale = .current) -> String {
        amountLine(entered: entry.enteredAmount, edible: entry.quantity, isServings: entry.amountIsServings,
                   method: entry.quantityMethod, locale: locale)
    }

    /// The method's short label (Food Log flags, saved entry, history), or nil for an amount
    /// entered directly (C7).
    public static func methodLabel(_ method: FoodQuantityMethod) -> String? {
        switch method {
        case .direct: nil
        case .weighed: "Kitchen scale"
        case .estimatedByEye: "Estimated by eye"
        case .kitchenScale: "Kitchen scale"
        case .packageWeight: "Package weight"
        case .typicalWeight: "Typical weight"
        case .wholeMilkVolume: "Whole milk volume estimate"
        case let .recorded(text): "Recorded: \(text)"
        }
    }

    /// "Small", "Medium", "Large", "Extra large": the source's US size names.
    public static func sizeName(_ size: FoodEdibleWeightGuideSize) -> String {
        switch size {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra large"
        }
    }

    /// The method as the saved entry header states it: "Typical weight, Large, about 50 g each".
    public static func methodDetail(_ method: FoodQuantityMethod, locale: Locale = .current) -> String? {
        if case let .typicalWeight(size, grams) = method {
            return "Typical weight, \(sizeName(size)), about \(number(grams, fraction: 0...1, locale: locale)) g each"
        }
        return methodLabel(method)
    }

    /// "248 kcal"; "Less than 5 kcal" (or "5 kcal or less") when the source states only an upper
    /// bound, rounded up so the shown bound still contains it; or "Energy unknown" (never blank,
    /// never zero).
    public static func entryEnergy(_ entry: FoodLogDayContent.Entry, locale: Locale = .current) -> String {
        if let value = entry.energyKcal { return "\(kcal(value, locale: locale)) kcal" }
        if let bound = entry.energyUpperBound {
            let shown = kcal(bound.kcal.rounded(.up), locale: locale)
            return bound.closed ? "\(shown) kcal or less" : "Less than \(shown) kcal"
        }
        return "Energy unknown"
    }

    /// One flags line: "Estimate" at most once, then "<Nutrient> unknown" for unknown strip
    /// nutrients other than energy (energy has its own slot). Empty when there is nothing to flag.
    public static func flags(_ entry: FoodLogDayContent.Entry) -> String {
        var parts = entry.isEstimate ? ["Estimate"] : []
        if let method = methodLabel(entry.quantityMethod) { parts.append(method) }
        parts += entry.unknownKeys.filter { $0 != .energyConsumed }.map { "\(label($0)) unknown" }
        return parts.joined(separator: " · ")
    }

    public static func entryAccessibility(_ entry: FoodLogDayContent.Entry, time: String, locale: Locale = .current) -> String {
        let flags = flags(entry)
        return [time, entry.name, entryAmount(entry, locale: locale), entryEnergy(entry, locale: locale), flags]
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

    /// "150 g", or "3 pieces · about 150 g" when the edible amount differs from what was entered;
    /// a pasted label's servings read "2 servings · 60 g".
    public static func savedAmount(_ detail: SavedFoodEntryDetail, locale: Locale = .current) -> String {
        amountLine(entered: detail.enteredAmount, edible: detail.edibleQuantity, isServings: detail.amountIsServings,
                   method: detail.quantityMethod, locale: locale)
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
        switch unit { case .grams: "g"; case .millilitres: "mL"; case .count: FoodAmountNoun.countUnitLabel }
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

    /// The header's second line, or nil (count-portion-estimate-v1, section 5): both estimate
    /// kinds once ("Estimate · Typical weight, Large, about 50 g each · Unknown details stay
    /// unknown"), or a measured method's label alone ("Kitchen scale").
    public static func headerEstimate(_ detail: SavedFoodEntryDetail, locale: Locale = .current) -> String? {
        let method = methodDetail(detail.quantityMethod, locale: locale)
        if detail.isEstimate || detail.weightIsEstimated {
            var parts = ["Estimate"]
            if detail.weightIsEstimated, let method { parts.append(method) }
            if detail.isEstimate { parts.append(estimateNotice) }
            // A measured method is still named when only the source is an estimate.
            if !detail.weightIsEstimated, let method { parts.append(method) }
            return parts.joined(separator: " · ")
        }
        return method
    }

    public static let plainWaterSourceName = "Plain water"

    /// "UK reference · per 100 g"; the app's plain water reference reads "Plain water · per 100 mL".
    /// Only the first letter of the basis is lowered, so unit symbols such as mL keep their case.
    public static func source(_ detail: SavedFoodEntryDetail) -> String {
        source(family: detail.sourceFamily, basis: detail.basis, isPlainWater: detail.isPlainWater, isLabelPhoto: detail.labelPhoto != nil)
    }

    /// The saved entry's Source row. A label photo reads as the pasted route's line does:
    /// "From a label photo · per 100 g · Traditional Chinese, Taiwan layout" (#328 journey QA).
    public static func source(family: FoodSearchResultSummary.SourceFamily, basis: ResolutionBasis, isPlainWater: Bool,
                              isLabelPhoto: Bool) -> String {
        let label = FoodNutritionReviewPresentation.basisLabel(basis)
        let basisText = label.prefix(1).lowercased() + label.dropFirst()
        if isLabelPhoto { return LabelPhotoText.savedSourceRow(basis: basisText) }
        let name = isPlainWater ? plainWaterSourceName : FoodSearchResultText.family(family)
        return "\(name) · \(basisText)"
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

    /// "Amount changed 3 pieces to 4 pieces (about 150 g to about 200 g)" when the entered amount
    /// changed; "Weight changed about 150 g to 120 g" when only the edible amount changed; with
    /// " · now Kitchen scale" (or the new size) when the method changed. Never a repeated count.
    static func amountChange(_ amount: FoodEntryHistoryEvent.AmountChange, locale: Locale) -> String {
        func counted(_ quantity: PositiveQuantity) -> String {
            amount.isServings && quantity.unit == .count ? servings(quantity, locale: locale) : self.amount(quantity, locale: locale)
        }
        func edible(_ quantity: PositiveQuantity, _ method: FoodQuantityMethod) -> String {
            (method.isEstimate ? "about " : "") + counted(quantity)
        }
        var text: String
        if amount.from != amount.to {
            text = "Amount changed \(counted(amount.from)) to \(counted(amount.to))"
            if let from = amount.edibleFrom, let to = amount.edibleTo, from != to {
                text += " (\(edible(from, amount.methodFrom)) to \(edible(to, amount.methodTo)))"
            }
        } else if let from = amount.edibleFrom, let to = amount.edibleTo, from != to {
            text = "Weight changed \(edible(from, amount.methodFrom)) to \(edible(to, amount.methodTo))"
        } else {
            text = "Weight details changed"
        }
        if amount.methodFrom != amount.methodTo {
            let now: String? = if case let .typicalWeight(size, _) = amount.methodTo,
                                  case .typicalWeight = amount.methodFrom { sizeName(size) } else { methodLabel(amount.methodTo) }
            // A direct weighed amount and a kitchen-scale conversion read the same (#318), so a
            // switch between them names no change.
            if let now, now != methodLabel(amount.methodFrom) { text += " · now \(now)" }
        }
        return text
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
            parts.append(amountChange(amount, locale: locale))
        }
        if let change {
            let (from, to) = time(change.from, change.to)
            parts.append("Time changed \(from) to \(to)")
        }
        return parts
    }
}
