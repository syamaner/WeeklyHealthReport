import ConfirmEnrichmentEvalCore
import FoodConfirmEnrichment
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// The offline plan check (`check-plan`): builds both parts' plans, as `send` would, with nothing sent
/// and no key read, so a case the plan cannot build (for example a bundled row with no measurable B
/// variant) shows before any claim or spend. Its lines hold counts and stop codes only (G11).
public enum EvalPlanCheck {
    public static func lines(_ list: EvalCaseList, set: String, privateFolder: URL,
                             candidates: EvalCandidates = EvalCandidates(),
                             routes: ConfirmEnrichmentSession.Routes = ConfirmEnrichmentRoutes.all) -> [String] {
        let plan = EvalPlan(candidates: candidates, folder: privateFolder)
        guard let details = try? plan.details(list, route: routes.details) else {
            return [EvalConsole.stopLine("plan_details_unavailable")]
        }
        guard let nutrients = try? plan.nutrients(list, route: routes.nutrients) else {
            return [EvalConsole.stopLine("plan_nutrients_unavailable")]
        }
        let asked = details.filter { $0.request != nil }.count
        guard asked > 0 else { return [EvalConsole.stopLine("plan_details_empty")] }
        guard !nutrients.isEmpty else { return [EvalConsole.stopLine("plan_nutrients_empty")] }
        return [EvalConsole.planLine(set: set, detailsRequests: asked, detailsWithoutQuestions: details.count - asked,
                                     nutrientRequests: nutrients.count)]
    }
}

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
