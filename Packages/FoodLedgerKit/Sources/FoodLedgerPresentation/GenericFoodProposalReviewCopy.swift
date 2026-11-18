import FoodLedgerApplication
import FoodLedgerDomain

/// Plain-language copy for the Web lookup screen (#196, #500). Pure functions of the review
/// result, so tests pin every wording without a view.
public enum GenericFoodProposalReviewCopy {
    public struct NoSuggestion: Equatable, Sendable {
        /// What the screen offers next. A paid re-run is offered only where the same lookup can
        /// reasonably give a different answer; an outcome that needs more detail goes back to
        /// the description instead; a settled outcome offers nothing.
        public enum Action: Equatable, Sendable { case lookUpAgain, editDescription }
        public let text: String
        public let action: Action?
        public init(text: String, action: Action?) { self.text = text; self.action = action }
        public var offersLookUpAgain: Bool { action == .lookUpAgain }
    }

    public static func summary(_ result: GenericFoodProposalReview) -> String {
        let count = max(result.discovery?.leads.count ?? 0, result.documents.count)
        let sources = count == 1 ? "Found 1 source" : "Found \(count) sources"
        let offered = result.offer.candidates
        let competing = offered.contains { member in offered.contains { $0.id != member.id && FoodProposalBinding.conflicting(member.candidate, $0.candidate) } }
        if competing { return sources + " · it gives more than one set of values" }
        if !offered.isEmpty { return sources + " · 1 suits this food" }
        return sources + (result.selectionFailure == nil ? " · none suits this food" : " · the check did not finish")
    }

    public static func noSuggestion(_ result: GenericFoodProposalReview) -> NoSuggestion {
        if let failure = result.selectionFailure {
            return NoSuggestion(text: selectionFailureText(failure), action: failure.canLookUpAgain ? .lookUpAgain : nil)
        }
        let noUsableText = "No usable source was found for this food."
        // The check is skipped when no candidate is choosable; that is not a failure, and looking
        // up again would cost a request and return the same page and values. Competing panels
        // are no longer "conflicting values that cannot be used" (#508 phase 2).
        if !result.rankingUnavailable, result.selection == nil,
           !result.validation.candidates.contains(where: \.choosable) {
            if !result.validation.candidates.isEmpty, result.validation.candidates.allSatisfy({ $0.candidate.basis.unit == nil }) {
                return NoSuggestion(text: "The source does not say what amount its values are for, such as per 100 g or per serving, so it cannot be used.",
                                    action: nil)
            }
            return NoSuggestion(text: noUsableText, action: nil)
        }
        if result.rankingUnavailable || result.selection == nil {
            return NoSuggestion(text: "Checking whether a source suits this food was unavailable, so no source can be used. You can look it up again.",
                                action: .lookUpAgain)
        }
        if result.suggestedChoice == "clarify" {
            return NoSuggestion(text: "The source does not clearly match your description. Add detail, such as the brand or how it was prepared, and look it up again.",
                                action: .editDescription)
        }
        return NoSuggestion(text: noUsableText, action: nil)
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
        if !proposal.choosable {
            return proposal.candidate.basis.label == nil ? "Needs more information · no nutrition basis" : "Needs more information"
        }
        // "Different values" only for a conflict with another choosable candidate, never from
        // `status`, which also marks a conflict with an unusable candidate (#508 phase 2).
        let peers = result?.validation.candidates ?? []
        if peers.contains(where: { $0.id != proposal.id && $0.choosable && FoodProposalBinding.conflicting(proposal.candidate, $0.candidate) }) {
            return FoodWebLookupOfferContent.differentValuesWord + (result?.rankingUnavailable == true ? " · Not checked for this food" : "")
        }
        if result?.rankingUnavailable == true { return "Not checked for this food" }
        return "Not suggested for this food"
    }

    /// For candidates that share a name, what tells them apart, keyed by candidate id: the
    /// nutrition basis, preparation, brand or source site, whichever differ within that name.
    /// When nothing on the candidates differs, their order is shown instead. Candidates with a
    /// unique name get no entry.
    public static func distinguishingDetails(_ proposals: [BoundFoodProposal]) -> [String: String] {
        details(proposals.map { ($0.id, $0.candidate, $0.document) })
    }

    /// As above, for candidates of one retained document (the offered candidates of a manifest).
    public static func distinguishingDetails(_ candidates: [FoodProposalCandidate], document: CapturedFoodDocument) -> [String: String] {
        details(candidates.map { ($0.id, $0, document) })
    }

    private struct Entry { let id: String; let candidate: FoodProposalCandidate; let document: CapturedFoodDocument }
    private static func details(_ items: [(String, FoodProposalCandidate, CapturedFoodDocument)]) -> [String: String] {
        let proposals = items.map { Entry(id: $0.0, candidate: $0.1, document: $0.2) }
        func key(_ name: String) -> String { collapsedWhitespace(name).lowercased() }
        var groups: [String: [Entry]] = [:]
        var order: [String] = []
        for proposal in proposals {
            let name = key(proposal.candidate.name)
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(proposal)
        }
        let attributes: [(Entry) -> String?] = [
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
