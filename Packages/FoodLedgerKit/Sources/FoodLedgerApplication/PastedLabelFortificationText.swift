import FoodLedgerDomain

/// Pasted label Confirm v1 (#306) section 4.5: the saved entry's "Fortification on the label"
/// value. Total over every stored combination, so it never fails; table-tested.
public enum PastedLabelFortificationText {
    public static let title = "Fortification on the label"

    /// The value for a manifest answer, whether the version recorded Not stated, and whether the
    /// current version is a Food details correction.
    public static func value(answer: PastedLabelIdentity.FortificationAnswer, recordsNotStated: Bool, corrected: Bool) -> String {
        let suffix = ", then corrected in food details"
        switch answer {
        case .yes: return corrected ? "Yes" + suffix : "Yes"
        case .no: return corrected ? "No" + suffix : "No"
        case .unanswered:
            // A correction's version carries only the correction assertion, so an earlier Not
            // stated cannot be read from it; the corrected row says so (spec section 14).
            if corrected { return "Not stated or not answered" + suffix }
            return recordsNotStated ? "Not stated" : "Not answered"
        }
    }

    /// The value for a stored pasted-label entry.
    public static func value(_ stored: StoredFoodConfirmation, manifest: PastedLabelEvidenceManifest) -> String {
        value(answer: manifest.identityMapping.fortificationAnswer,
              recordsNotStated: PastedLabelFortificationPolicy.recordsNotStated(stored),
              corrected: stored.assertions.contains { $0.claim.value.hasPrefix(QuickAddPolicy.correctionClaimPrefix) })
    }
}
