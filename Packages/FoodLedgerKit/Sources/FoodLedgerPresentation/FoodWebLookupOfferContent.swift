import FoodLedgerApplication
import FoodLedgerDomain

/// The panel list of screen contract `web-lookup-review-v2` (#508 phase 2): everything the Web
/// lookup screen shows about the offered candidates before "Use this source". A pure function
/// of the offered candidates, the model's answer, the selected id, the document and the scope,
/// so the content rebuilt from a retained v3 manifest equals the content that was shown.
public struct FoodWebLookupOfferContent: Equatable, Sendable {
    public static let choosePanelTitle = "Choose a panel"
    public static let suggestedTitle = "Suggested source"
    public static let prompt = "This page gives more than one set of values. Choose the one that matches your food."
    public static let warning = "The check could not confirm this page matches your food. Compare the name, brand and variant before you choose."
    public static let pickRequired = "Choose a panel to use this source."
    public static let suggestedWord = "Suggested"
    public static let differentValuesWord = "Different values"

    public struct Row: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let brand: String?
        /// What tells this row apart from the other offered rows, over the offered rows only.
        public let details: String?
        public let basisLabel: String?
        public let declared: [FoodWebLookupReviewContent.DeclaredNutrient]
        public let suggested: Bool
        /// The row differs in a declared value from another offered row.
        public let differentValues: Bool
        /// For rows with different values: the nearest heading before the panel, if any.
        public let heading: String?
        /// For rows with different values: the panel's first quoted line.
        public let firstQuote: String?
        public let selected: Bool
        /// VoiceOver label naming the panel and whether it is the suggestion, with what the person
        /// chooses on: its heading and its declared values.
        public var accessibilityLabel: String {
            let values = declared.map { "\(FoodNutritionReviewPresentation.label($0.key.ledgerKey)) \($0.value) \($0.unit)" }
            return ([name, brand, details, heading, basisLabel.map { "per " + $0 }] + values
                    + [suggested ? suggestedWord : nil, differentValues ? differentValuesWord : nil]).compactMap { $0 }.joined(separator: ", ")
        }
    }

    public let title: String
    /// The warning line of answer O4, above the panels; stays after a pick.
    public let warningLine: String?
    /// Shown only when nothing is pre-selected.
    public let promptLine: String?
    public let rows: [Row]
    /// The selected row's content (details, quotes and limitations shown below the list).
    public let selected: FoodWebLookupReviewContent?
    /// Why "Use this source" is disabled, when no panel is selected.
    public let disabledReason: String?

    public init(offered: [FoodProposalCandidate], selectionChoice: String, selectedID: String?,
                document: CapturedFoodDocument, scope: FoodProposalReviewScope?) {
        let clarify = selectionChoice == "clarify"
        title = clarify ? Self.choosePanelTitle : Self.suggestedTitle
        warningLine = clarify && !offered.isEmpty ? Self.warning : nil
        promptLine = clarify && !offered.isEmpty ? Self.prompt : nil
        let details = GenericFoodProposalReviewCopy.distinguishingDetails(offered, document: document)
        rows = offered.map { candidate in
            let differs = offered.contains { $0.id != candidate.id && FoodProposalBinding.conflicting(candidate, $0) }
            let content = FoodWebLookupReviewContent(document: document, candidate: candidate, scope: scope,
                                                     presentation: FoodProposalReviewAction.webLookupReviewV2)
            return Row(id: candidate.id, name: candidate.name, brand: candidate.brand, details: details[candidate.id],
                       basisLabel: candidate.basis.label, declared: content?.declared ?? [],
                       suggested: !clarify && candidate.id == selectionChoice, differentValues: differs,
                       heading: differs ? Self.heading(before: candidate, in: document) : nil,
                       firstQuote: differs ? candidate.panelEvidence.first?.quote : nil,
                       selected: candidate.id == selectedID)
        }
        let picked = offered.first { $0.id == selectedID }
        selected = picked.flatMap { FoodWebLookupReviewContent(document: document, candidate: $0, scope: scope,
                                                               presentation: FoodProposalReviewAction.webLookupReviewV2) }
        disabledReason = picked == nil && !offered.isEmpty ? Self.pickRequired : nil
    }

    /// The live content for a review, with the person's current pick.
    public init(review: GenericFoodProposalReview, selectedID: String?, scope: FoodProposalReviewScope?) {
        let offer = review.offer
        let document = offer.candidates.first?.document ?? review.documents.first
        guard let document, let selection = review.selection else {
            self.init(empty: ())
            return
        }
        self.init(offered: offer.candidates.map(\.candidate), selectionChoice: selection.choice,
                  selectedID: offer.candidates.contains { $0.id == selectedID } ? selectedID : nil,
                  document: document, scope: scope)
    }

    /// The content a retained v3 manifest rebuilds: the selected row is the person's choice.
    public init(manifest: FoodProposalReviewManifestV3) {
        self.init(offered: manifest.offered, selectionChoice: manifest.gate.selectionChoice,
                  selectedID: manifest.gate.personChoice, document: manifest.document, scope: manifest.scope)
    }

    private init(empty: Void) {
        title = Self.suggestedTitle; warningLine = nil; promptLine = nil; rows = []; selected = nil; disabledReason = nil
    }

    /// The nearest `h1` to `h6` block before the candidate's first panel-evidence block.
    static func heading(before candidate: FoodProposalCandidate, in document: CapturedFoodDocument) -> String? {
        guard let first = candidate.panelEvidence.first,
              let index = document.blocks.firstIndex(where: { $0.id == first.blockId }) else { return nil }
        let headings: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
        return document.blocks[..<index].last { headings.contains($0.kind) }?.text
    }
}
