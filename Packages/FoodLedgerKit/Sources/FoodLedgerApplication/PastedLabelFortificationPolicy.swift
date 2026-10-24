import FoodLedgerDomain

/// Pasted label Confirm v1 (#306, `docs/pasted-label-confirm-v1.md`): fortification on a pasted
/// label is asked once on Confirm as Yes / No / Not stated. Yes and No rebuild the source with the
/// manifest answer; Not stated keeps fortification unknown and is recorded as the existing typed
/// decision `fortification: source unknown, choice not_sure`. Pure; reads only confirmation state.
public enum PastedLabelFortificationPolicy {
    /// The one scope predicate (C6a): panel admission. Inputs it matches that admission does not
    /// verify are refused at build and at save before any requirement is evaluated.
    public static func isPastedLabel(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        PanelSourceAdmission.applies(input, candidate: candidate)
    }

    /// C4: an editable pasted-label source (the transient state flag), or a reopened pasted-label
    /// entry whose current version recorded Not stated. Re-logs and favourites have neither.
    public static func applies(_ state: FoodConfirmationState) -> Bool {
        guard isPastedLabel(state.input, candidate: state.selectedCandidate) else { return false }
        if let reopened = state.reopened { return recordsNotStated(reopened) }
        return state.answersLabelFortification
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
