import Foundation
import FoodLedgerDomain

/// The closed screen content of review presentation `web-lookup-review-v1`: everything the
/// Web lookup screen shows before "Use this source". A pure function of the retained document
/// and candidate; admission never recomputes it, golden tests pin it.
public struct FoodWebLookupReviewContent: Equatable, Sendable {
    public struct DeclaredNutrient: Equatable, Sendable {
        public let key: FoodProposalNutrientKey
        public let value: String
        public let unit: String
        public init(key: FoodProposalNutrientKey, value: String, unit: String) { self.key = key; self.value = value; self.unit = unit }
    }
    public static let presentation = FoodProposalReviewAction.webLookupReviewV1

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

    public init(document: CapturedFoodDocument, candidate: FoodProposalCandidate, scope: FoodProposalReviewScope?) {
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
