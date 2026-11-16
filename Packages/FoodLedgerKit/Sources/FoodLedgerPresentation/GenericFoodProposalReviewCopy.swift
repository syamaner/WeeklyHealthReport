import FoodLedgerApplication
import FoodLedgerDomain

/// Plain-language copy for the Web lookup screen (#196, #500). Pure functions of the review
/// result, so tests pin every wording without a view.
public enum GenericFoodProposalReviewCopy {
    public struct NoSuggestion: Equatable, Sendable {
        public let text: String
        /// Whether the screen offers Look up again for this result.
        public let offersLookUpAgain: Bool
        public init(text: String, offersLookUpAgain: Bool) { self.text = text; self.offersLookUpAgain = offersLookUpAgain }
    }

    public static func summary(_ result: GenericFoodProposalReview, suggested: BoundFoodProposal?) -> String {
        let count = max(result.discovery?.leads.count ?? 0, result.documents.count)
        let sources = count == 1 ? "Found 1 source" : "Found \(count) sources"
        if suggested != nil { return sources + " · 1 suits this food" }
        return sources + (result.selectionFailure == nil ? " · none suits this food" : " · the check did not finish")
    }

    public static func noSuggestion(_ result: GenericFoodProposalReview) -> NoSuggestion {
        if let failure = result.selectionFailure {
            return NoSuggestion(text: selectionFailureText(failure), offersLookUpAgain: failure.canLookUpAgain)
        }
        if result.rankingUnavailable || result.selection == nil {
            return NoSuggestion(text: "Checking whether a source suits this food was unavailable, so no source can be used. You can look it up again.",
                                offersLookUpAgain: true)
        }
        if result.validation.candidates.contains(where: { $0.status == .conflictingCandidates }) {
            return NoSuggestion(text: "The source gives conflicting values for this food, so it cannot be used.", offersLookUpAgain: false)
        }
        if result.suggestedChoice == "clarify" {
            return NoSuggestion(text: "The source does not clearly match your description. Add detail, such as the brand or how it was prepared, and look it up again.",
                                offersLookUpAgain: false)
        }
        return NoSuggestion(text: "No usable source was found for this food.", offersLookUpAgain: false)
    }

    /// Why the check of whether a source suits this food did not finish, in plain language.
    public static func selectionFailureText(_ failure: FoodProposalSelectionFailure) -> String {
        let lead = "No source can be used because "
        switch failure {
        case .transport:
            return lead + "the connection to OpenRouter failed while checking whether a source suits this food. Check your connection and look it up again."
        case .timedOut:
            return lead + "checking whether a source suits this food took too long. You can look it up again."
        case .rateLimited:
            return lead + "OpenRouter reported a rate or credit limit while checking whether a source suits this food. Wait a minute or check your OpenRouter account, then look it up again."
        case .serverError:
            return lead + "the model service was unavailable while checking whether a source suits this food. You can look it up again later."
        case .invalidResponse:
            return lead + "the answer to whether a source suits this food could not be read. You can look it up again."
        case .choiceNotOffered:
            return lead + "the answer to whether a source suits this food named something that was not offered. You can look it up again."
        case .requestRejected:
            return lead + "OpenRouter did not accept the check of whether a source suits this food. Looking it up again will not change this."
        }
    }

    public static func status(_ proposal: BoundFoodProposal, in result: GenericFoodProposalReview? = nil) -> String {
        if proposal.status == .conflictingCandidates { return "Conflicting values" }
        if !proposal.selectionEligible {
            return proposal.candidate.basis.label == nil ? "Needs more information · no nutrition basis" : "Needs more information"
        }
        if result?.rankingUnavailable == true { return "Not checked for this food" }
        return "Not suggested for this food"
    }

    /// For candidates that share a name, what tells them apart, keyed by candidate id: the
    /// nutrition basis, preparation, brand or source site, whichever differ within that name.
    /// When nothing on the candidates differs, their order is shown instead. Candidates with a
    /// unique name get no entry.
    public static func distinguishingDetails(_ proposals: [BoundFoodProposal]) -> [String: String] {
        func key(_ name: String) -> String { collapsedWhitespace(name).lowercased() }
        var groups: [String: [BoundFoodProposal]] = [:]
        var order: [String] = []
        for proposal in proposals {
            let name = key(proposal.candidate.name)
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(proposal)
        }
        let attributes: [(BoundFoodProposal) -> String?] = [
            { basisText($0.candidate.basis) },
            { $0.candidate.preparation.map(collapsedWhitespace).flatMap { $0.isEmpty ? nil : $0 } },
            { $0.candidate.brand.map(collapsedWhitespace).flatMap { $0.isEmpty ? nil : $0 } },
            { FoodWebLookupReviewContent(document: $0.document, candidate: $0.candidate, scope: nil).sourceHost }
        ]
        var details: [String: String] = [:]
        for name in order {
            guard let group = groups[name], group.count > 1 else { continue }
            let differing = attributes.filter { attribute in Set(group.map { attribute($0) ?? "" }).count > 1 }
            for (index, proposal) in group.enumerated() {
                let parts = differing.compactMap { $0(proposal) }
                details[proposal.id] = parts.isEmpty ? "Entry \(index + 1) of \(group.count)" : parts.joined(separator: " · ")
            }
        }
        return details
    }

    /// A lead title for display: runs of spaces and line breaks become one space. An empty title
    /// falls back to the page's site.
    public static func leadTitle(_ lead: FoodWebLead) -> String {
        let title = collapsedWhitespace(lead.title)
        return title.isEmpty ? (lead.url.host ?? lead.url.absoluteString) : title
    }

    static func collapsedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func basisText(_ basis: FoodProposalBasis) -> String? {
        if let label = basis.label.map(collapsedWhitespace), !label.isEmpty {
            return label.lowercased().hasPrefix("per ") ? label : "per " + label
        }
        guard let amount = basis.amount, let unit = basis.unit else { return nil }
        return unit == .serving ? "per \(amount) serving" : "per \(amount) \(unit.rawValue)"
    }
}
