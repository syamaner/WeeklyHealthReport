import Foundation
import FoodLedgerDomain

/// One compatible bundled generic row offered on Confirm (docs/label-estimate-merge-v1.md rule 7),
/// with the evidence and release it is saved with, as the generic search route saves a match.
public struct LabelEstimateOption: Equatable, Sendable, Identifiable {
    public let generic: PopulatedFoodCandidate
    public let evidence: [CaptureEvidence]
    public let sourceRelease: SourceRelease

    public init(generic: PopulatedFoodCandidate, evidence: [CaptureEvidence], sourceRelease: SourceRelease) {
        self.generic = generic
        self.evidence = evidence
        self.sourceRelease = sourceRelease
    }

    public var id: String { generic.candidate.recordID.value }

    public func choice(cocoaPercent: Double, origin: CocoaPercentOrigin) -> LabelEstimateChoice {
        LabelEstimateChoice(generic: generic, evidence: evidence, sourceRelease: sourceRelease,
                            cocoaPercent: cocoaPercent, origin: origin)
    }
}

/// Rule 7's candidate pool (`label-estimate-pool-v1`): the bundled generic rows reached through
/// the generic search port for the query "dark chocolate <p>%", kept where rule 3 admits them,
/// distinct by record ID, in search order. The searcher is the one the generic search route uses,
/// wired at the composition root; no other source and no network.
public struct LabelEstimateCandidatePool: Sendable {
    public static let version = "label-estimate-pool-v1"
    /// The evidence capture method of the pool search, so a saved estimate never claims a search
    /// the user typed.
    public static let captureMethod = "label_estimate_pool_search"

    private let searcher: any GenericFoodSearching
    private let ids: any LedgerIDGenerating

    public init(searcher: any GenericFoodSearching, ids: any LedgerIDGenerating) {
        self.searcher = searcher
        self.ids = ids
    }

    /// "dark chocolate 90%", "dark chocolate 85.5%".
    public static func query(cocoaPercent p: Double) -> String {
        let number = p.rounded() == p ? String(Int(p)) : String(format: "%.1f", p)
        return "dark chocolate \(number)%"
    }

    /// Empty for an invalid percentage or when no row is compatible.
    public func options(cocoaPercent p: Double, capturedAt: Date, locale: LedgerText) throws -> [LabelEstimateOption] {
        guard LabelEstimateCompatibility.isValidPercent(p) else { return [] }
        let text = try LedgerText(Self.query(cocoaPercent: p))
        let evidence = try CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch, capturedAt: capturedAt,
            locale: locale, captureMethod: LedgerText(Self.captureMethod), captureMethodVersion: LedgerText(Self.version),
            originalPayload: .text(text))
        let request = GenericFoodSearchRequest(text: text, capturedAt: capturedAt, locale: locale, captureEvidence: evidence)
        guard case let .confirmation(route) = try searcher.search(request) else { return [] }
        var seen: Set<String> = []
        return route.matches.compactMap { match -> LabelEstimateOption? in
            let row = match.candidate
            guard LabelEstimateCompatibility.isCompatible(row, cocoaPercent: p), seen.insert(row.candidate.recordID.value).inserted,
                  let release = route.confirmation.sourceReleases.first(where: { $0.sourceReleaseID == row.candidate.sourceReleaseID })
            else { return nil }
            let evidence = row.candidate.evidenceIDs.compactMap { id in route.confirmation.evidence.first { $0.evidenceID == id } }
            guard evidence.count == row.candidate.evidenceIDs.count else { return nil }
            return LabelEstimateOption(generic: row, evidence: evidence, sourceRelease: release)
        }
    }
}

/// Rule 1 with its route, for Confirm: whether the "Estimate unprinted nutrients" section is
/// offered, the pre-fill, and the merge preview. Pure; the view model and the save share it.
public enum LabelEstimateOffer {
    /// A new pasted label or label photo entry (never Open Food Facts, a reviewed manufacturer
    /// page, a re-log of another source or an edit) whose label offers an estimate under rule 1.
    public static func applies(_ state: FoodConfirmationState) -> Bool {
        guard state.reopened == nil else { return false }
        let selected = state.selectedCandidate
        switch LabelSourceAdmission.route(state.input, candidate: selected) {
        case .pasted, .photo: break
        case .refused: return false
        }
        return LabelEstimateCompatibility.offersEstimate(name: selected.name.value, basis: selected.candidate.identity.servingBasis)
    }

    /// Whether a chosen estimate can be saved now. The save refuses an estimate on a corrected
    /// entry (rule 4: the merge never changes identity), so Log passes none then.
    public static func admitsChoice(_ state: FoodConfirmationState) -> Bool {
        applies(state) && state.correction == nil
    }

    /// The pasted text of a pasted label (rule 2); nil for a label photo and every other route.
    public static func pastedText(_ state: FoodConfirmationState) -> String? {
        let selected = state.selectedCandidate
        guard LabelSourceAdmission.route(state.input, candidate: selected) == .pasted else { return nil }
        for evidence in state.input.evidence where selected.candidate.evidenceIDs.contains(evidence.evidenceID) {
            guard evidence.kind == .labelText, case let .text(payload) = evidence.originalPayload,
                  let manifest = PastedLabelEvidenceManifest.decode(Data(payload.value.utf8)) else { continue }
            return manifest.pastedText
        }
        return nil
    }

    /// Rule 2's pre-fill: the candidate name, else the pasted text of a pasted label.
    public static func prefill(_ state: FoodConfirmationState) -> (value: Double, origin: CocoaPercentOrigin)? {
        guard applies(state) else { return nil }
        return LabelEstimateCompatibility.prefill(name: state.selectedCandidate.name.value, pastedText: pastedText(state))
    }

    /// The preview for one option: the label merged with the row on the label's basis, with the
    /// keys that change. Nil when the label offers no estimate or the merge does not apply.
    public static func merge(_ state: FoodConfirmationState, option: LabelEstimateOption) -> LabelEstimateMerge.Result? {
        guard applies(state) else { return nil }
        let label = state.selectedCandidate.candidate
        return try? LabelEstimateMerge.merge(label: label.nutrients, labelBasis: label.identity.servingBasis,
                                             generic: option.generic.candidate.nutrients,
                                             genericBasis: option.generic.candidate.identity.servingBasis)
    }
}
