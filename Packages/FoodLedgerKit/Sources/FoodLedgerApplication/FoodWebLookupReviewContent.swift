import Foundation
import FoodLedgerDomain

/// The closed screen content of review presentations `web-lookup-review-v1` and, for one
/// offered candidate, `web-lookup-review-v2` (#508): everything the Web lookup screen shows
/// before "Use this source". A pure function of the presentation, the retained document and
/// candidate; admission never recomputes it, golden tests pin it. For a whole page the two
/// presentations give equal content; v2 adds the part-read line and label for a document read
/// in part. The panel list of several offered candidates is not part of this type yet.
public struct FoodWebLookupReviewContent: Equatable, Sendable {
    public struct DeclaredNutrient: Equatable, Sendable {
        public let key: FoodProposalNutrientKey
        public let value: String
        public let unit: String
        public init(key: FoodProposalNutrientKey, value: String, unit: String) { self.key = key; self.value = value; self.unit = unit }
    }
    public static let presentation = FoodProposalReviewAction.webLookupReviewV1
    public static let partReadLine = "Only part of this page was read."
    public static let notStatedLabel = "Not stated"
    public static let notInPartReadLabel = "Not in the part read"

    public let name: String
    public let brand: String?
    public let sourceHost: String
    public let basisLabel: String?
    public let scope: FoodProposalReviewScope?
    public let declared: [DeclaredNutrient]
    /// Not observed on the page.
    public let notStated: [FoodProposalNutrientKey]
    /// Present on the page but not usable (conflicting, unreadable or unsupported).
    public let notUsable: [FoodProposalNutrientKey]
    public let limitations: [String]
    /// Quoted source text behind one disclosure, deduplicated in first-seen order.
    public let quotes: [String]
    /// v2 only, for a document read in part: "Only part of this page was read."
    public let partRead: String?
    /// The words shown for a nutrient in `notStated`: "Not in the part read" for a part-read
    /// document under v2, otherwise "Not stated". Membership of `notStated` never changes.
    public let notStatedText: String

    public static let knownPresentations: Set<String> = [FoodProposalReviewAction.webLookupReviewV1, FoodProposalReviewAction.webLookupReviewV2]

    /// Content under `web-lookup-review-v1`.
    public init(document: CapturedFoodDocument, candidate: FoodProposalCandidate, scope: FoodProposalReviewScope?) {
        self.init(known: document, candidate: candidate, scope: scope, presentation: Self.presentation)
    }

    /// Content under a named presentation; an unknown presentation fails closed (`nil`).
    public init?(document: CapturedFoodDocument, candidate: FoodProposalCandidate, scope: FoodProposalReviewScope?,
                 presentation: String) {
        guard Self.knownPresentations.contains(presentation) else { return nil }
        self.init(known: document, candidate: candidate, scope: scope, presentation: presentation)
    }

    private init(known document: CapturedFoodDocument, candidate: FoodProposalCandidate, scope: FoodProposalReviewScope?,
                 presentation: String) {
        let partReadV2 = presentation == FoodProposalReviewAction.webLookupReviewV2 && document.partialRead != nil
        partRead = partReadV2 ? Self.partReadLine : nil
        notStatedText = partReadV2 ? Self.notInPartReadLabel : Self.notStatedLabel
        name = candidate.name
        brand = candidate.brand
        sourceHost = URL(string: document.url)?.host ?? document.url
        basisLabel = candidate.basis.label
        self.scope = scope
        let byKey = Dictionary(candidate.nutrients.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        declared = FoodProposalNutrientKey.allCases.compactMap { key in
            guard let nutrient = byKey[key], nutrient.state == .declared, let value = nutrient.value else { return nil }
            return DeclaredNutrient(key: key, value: value, unit: nutrient.unit ?? key.unit)
        }
        let declaredKeys = Set(declared.map(\.key))
        func isNotUsable(_ key: FoodProposalNutrientKey) -> Bool {
            guard let reason = byKey[key]?.unknownReason else { return false }
            return reason != .notObserved
        }
        notStated = FoodProposalNutrientKey.allCases.filter { !declaredKeys.contains($0) && !isNotUsable($0) }
        notUsable = FoodProposalNutrientKey.allCases.filter { !declaredKeys.contains($0) && isNotUsable($0) }
        limitations = candidate.limitations
        var seen: [String] = []
        for reference in candidate.identityEvidence + candidate.basis.evidence + candidate.nutrients.flatMap(\.evidence)
            where !seen.contains(reference.quote) { seen.append(reference.quote) }
        quotes = seen
    }
}

public extension FoodWebLookupReviewContent {
    /// The content a retained v3 manifest rebuilds, from the manifest alone.
    /// `nil` only if the manifest names a presentation this build does not know.
    init?(manifest: FoodProposalReviewManifestV3) {
        self.init(document: manifest.document, candidate: manifest.candidate, scope: manifest.scope,
                  presentation: manifest.review.presentation)
    }
}
