import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// Every string Confirm enrichment shows (docs/confirm-enrichment-openrouter-v1.md sections 6 and 8,
/// CE1.6 and CE1.7a), frozen here. Plain language, British spelling, no emoji, no health wording.
public enum ConfirmEnrichmentText {
    public static let detailsLinePrefix = "Food details suggested:"
    public static let change = "Change"
    public static let notThese = "Not these"
    public static let loading = "Looking for suggestions…"
    public static let stop = "Stop"
    public static let askAgain = "Ask again"
    public static let notAvailable = "Suggestions are not available right now."
    public static let limitReached = "Today's limit for suggestions is reached."
    public static let estimatedTag = "est."
    public static let estimatedSpoken = "estimated"
    public static let leaveOut = "Leave out"
    public static let putBack = "Put back"
    public static let onlyEstimated = "Nothing to log yet: every value here is an estimate from OpenRouter."
    public static let removedBecauseDetailsChanged = "Estimates from OpenRouter were removed because the food details changed."
    public static let notCarriedOnReresolution = "Estimates from OpenRouter are not carried over"
    public static let evidenceNotAvailable = "Evidence not available"

    /// The Source details line for a B value (CE1.6 rule 5).
    public static func estimatedBy(model: String, receivedAt: Date, locale: Locale = .current) -> String {
        let time = receivedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
        return "Estimated by \(model) through OpenRouter from the description of this food, received \(time)"
    }

    /// The one quiet note of section 6, or nil for a failure that shows nothing.
    public static func note(_ failure: ConfirmEnrichmentSession.Failure) -> String? {
        switch failure {
        case .notAvailable: notAvailable
        case .limitReached: limitReached
        case .silent, .notPermitted, .notPermittedAfterSending, .cancelled: nil
        }
    }

    /// "as sold, not applicable bone, …": the suggested facts in plain words, in a fixed order.
    public static func detailsLine(_ facts: [ConfirmDetailsFact: String]) -> String {
        let order: [ConfirmDetailsFact] = [.preparation, .bone, .skin, .drained, .packingMedium, .fortification]
        let words = order.compactMap { fact in facts[fact].map { phrase(fact, $0) } }
        return "\(detailsLinePrefix) \(words.joined(separator: ", "))"
    }

    static func phrase(_ fact: ConfirmDetailsFact, _ choice: String) -> String {
        switch (fact, choice) {
        case (.preparation, "as_sold"): "as sold"
        case (.preparation, let value): value
        case (.bone, "with_bone"): "with bone"
        case (.bone, "boneless"): "boneless"
        case (.bone, _): "no bone"
        case (.skin, "skin_on"): "skin on"
        case (.skin, "skinless"): "skinless"
        case (.skin, _): "no skin"
        case (.drained, "drained"): "drained"
        case (.drained, "undrained"): "not drained"
        case (.drained, _): "no packing liquid"
        case (.packingMedium, "as sold"): "packed as sold"
        case (.packingMedium, "not applicable"): "no packing medium"
        case (.packingMedium, "olive_oil"): "in olive oil"
        case (.packingMedium, let value): "in \(value)"
        case (.fortification, _): "not fortified"
        }
    }
}
