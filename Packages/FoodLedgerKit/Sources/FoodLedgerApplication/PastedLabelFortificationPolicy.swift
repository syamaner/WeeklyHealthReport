import FoodLedgerDomain

/// Pasted label Confirm v1 (#306, `docs/pasted-label-confirm-v1.md`): fortification on a pasted
/// label is asked once on Confirm as Yes / No / Not stated. Yes and No rebuild the source with the
/// manifest answer; Not stated keeps fortification unknown and is recorded as the existing typed
/// decision `fortification: source unknown, choice not_sure`. Pure; reads only confirmation state.
public enum PastedLabelFortificationPolicy {
    /// The one scope predicate (C6a): panel admission. Inputs it matches that admission does not
    /// verify are refused at build and at save before any requirement is evaluated.
    /// The label photo route asks the same question (docs/label-photo-ai-prefill-v1.md 4.2, 17.19),
    /// so the scope is the label admission composite: a photo candidate is in scope through its
    /// evidence even while every value it shows is still unknown.
    public static func isPastedLabel(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        LabelSourceAdmission.applies(input, candidate: candidate)
    }

    /// C4: every new pasted-label Confirm (a new reading, a re-log or a favourite), or a reopened
    /// pasted-label entry whose current version recorded Not stated. Never while a Food details
    /// correction is applied: a correction carries no decision, so its identity must be complete
    /// under the unchanged v5 rule. The transient `answersLabelFortification` flag no longer gates
    /// this; it marks an editable source, where Yes and No rebuild the source (C6, journey QA).
    public static func applies(_ state: FoodConfirmationState) -> Bool {
        guard state.correction == nil, isPastedLabel(state.input, candidate: state.selectedCandidate) else { return false }
        if let reopened = state.reopened { return recordsNotStated(reopened) }
        return true
    }

    /// C5: the only recorded decision admitted for the facet.
    public static let offeredChoices: [FoodLogDecisionChoice] = [.notSure]

    /// Whether the saved version's assertions record `fortification: not_sure`.
    public static func recordsNotStated(_ stored: StoredFoodConfirmation) -> Bool {
        stored.assertions.contains { assertion in
            assertion.confirmation?.decisions.contains { $0.facet == .fortification && $0.choice == .notSure } == true
        }
    }
}
