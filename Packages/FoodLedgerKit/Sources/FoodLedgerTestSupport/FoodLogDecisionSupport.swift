import FoodLedgerApplication
import FoodLedgerDomain

extension FoodConfirmationState {
    /// Answers every pending inline difference. Prefers "Not sure" (a labelled estimate)
    /// and falls back to the facet's acknowledgement where "Not sure" is not offered.
    public mutating func answerPendingDifferences(preferMatchingSource: Bool = false) {
        for facet in FoodLogPolicy.pendingDifferences(self) {
            let offered = FoodLogPolicy.offeredChoices(self, facet: facet)
            let choice = (preferMatchingSource ? offered.first { $0 == .matchesSource } : nil)
                ?? offered.first { $0 == .notSure } ?? offered[0]
            FoodConfirmationReducer.reduce(state: &self, action: .decideDifference(facet, choice))
        }
    }
}
