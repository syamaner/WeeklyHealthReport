import ConfirmEnrichmentEvalCore
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// Send and score rebuild the same plan. A case with no A questions still has review truth.
struct EvalPlan {
    struct Details {
        let hash: String
        let request: ConfirmEnrichmentPolicy.DetailsRequest?
    }

    struct Nutrients {
        let hash: String
        let request: ConfirmEnrichmentPolicy.NutrientRequest
        let base: NutrientSet
        let hidden: NutrientKey
        let declared: Double
    }

    let candidates: EvalCandidates
    let folder: URL

    func details(_ list: EvalCaseList, route: ConfirmEnrichmentRoute) throws -> [Details] {
        try list.cases.filter { $0.kind == .openFoodFacts }.map { item in
            let state = try candidates.state(for: item, privateFolder: folder)
            let request = try EvalRequests.details(state, route: route)
            return Details(hash: try EvalHashes.hash(item), request: request)
        }
    }

    func nutrients(_ list: EvalCaseList, route: ConfirmEnrichmentRoute) throws -> [Nutrients] {
        var planned: [Nutrients] = []
        for (index, item) in list.cases.enumerated() {
            let variants = try candidates.nutrientVariants(for: item, index: index, privateFolder: folder)
            guard !variants.isEmpty else { throw EvalRequestEvidence.Invalid() }
            for (variant, state, hidden, declared) in variants {
                guard let request = try EvalRequests.nutrients(state, route: route),
                      request.inputs.eligibleKeys.contains(hidden) else { throw EvalRequestEvidence.Invalid() }
                let base = state.selectedCandidate.candidate.nutrients
                let hash = try EvalHashes.hash(variant)
                planned.append(Nutrients(hash: hash, request: request, base: base, hidden: hidden, declared: declared))
            }
        }
        return planned
    }
}
