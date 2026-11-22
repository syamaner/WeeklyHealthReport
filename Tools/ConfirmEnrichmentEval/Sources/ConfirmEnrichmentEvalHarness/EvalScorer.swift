import ConfirmEnrichmentEvalCore
import FoodConfirmEnrichment
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// Local evidence reader. Outputs only typed aggregates; invalid input fails closed without echoing it.
public struct EvalScorer {
    let candidates: EvalCandidates
    let routes: ConfirmEnrichmentSession.Routes

    public init(candidates: EvalCandidates = EvalCandidates(),
                routes: ConfirmEnrichmentSession.Routes = ConfirmEnrichmentRoutes.all) {
        self.candidates = candidates
        self.routes = routes
    }

    public func score(_ list: EvalCaseList, part: ConfirmEnrichmentPart, folder: URL, reviewSheet: URL?,
                      evidenceFolder: URL? = nil, fake: Bool = false) -> [EvalScoring.Result] {
        do {
            let plan = EvalPlan(candidates: candidates, folder: folder)
            let evidence = evidenceFolder ?? folder
            let runID = try EvalCompletedRun.read(list: list, folder: evidence, part: part, fake: fake)
            switch part {
            case .details:
                guard let reviewSheet else { throw EvalReviewSheet.Invalid() }
                return try scoreDetails(plan.details(list, route: routes.details), evidence: evidence, runID: runID, reviewSheet: reviewSheet)
            case .nutrients:
                return try scoreNutrients(plan.nutrients(list, route: routes.nutrients), evidence: evidence, runID: runID)
            }
        } catch {
            return [Self.invalid(part)]
        }
    }

    public func verifyDetailsFreeze(_ list: EvalCaseList, folder: URL, expectedSHA256: String?) -> Bool {
        guard let expectedSHA256 else { return false }
        let plan = EvalPlan(candidates: candidates, folder: folder)
        guard let cases = try? plan.details(list, route: routes.details),
              let request = cases.lazy.compactMap(\.request).first else { return false }
        return (try? EvalRequestEvidence.hash(request.body)) == expectedSHA256
    }

    public static func invalid(_ part: ConfirmEnrichmentPart) -> EvalScoring.Result {
        .init(part: part, bar: .evidence, passed: false, within: 0, outside: 1)
    }

    private func scoreDetails(_ cases: [EvalPlan.Details], evidence: URL, runID: UUID,
                              reviewSheet: URL) throws -> [EvalScoring.Result] {
        let truth = try EvalReviewSheet.read(reviewSheet, expected: Set(cases.map(\.hash)))
        let route = routes.details
        let observations = try cases.map { item -> EvalScoring.Details in
            guard let reviewed = truth[item.hash] else { throw EvalReviewSheet.Invalid() }
            guard let request = item.request else {
                return .init(asked: [], fills: [:], truth: reviewed, timing: nil)
            }
            let (timing, response) = try EvalRequestEvidence.read(
                folder: evidence, hash: item.hash, part: .details, runID: runID, request: request.body)
            var fills: [ConfirmDetailsFact: String] = [:]
            if let response {
                let parsed = try ConfirmDetailsResponseCheck.check(
                    response, request: request.inputs, models: route.acceptedModels, provider: route.provider).get()
                let applied = Set(ConfirmDetailsResponseCheck.applied(parsed.answers))
                for answer in parsed.answers where applied.contains(answer.fact) {
                    if let fact = ConfirmDetailsFact(rawValue: answer.fact) { fills[fact] = answer.choice }
                }
            }
            return .init(asked: Set(request.inputs.asked), fills: fills, truth: reviewed, timing: timing)
        }
        return EvalScoring.details(observations)
    }

    private func scoreNutrients(_ cases: [EvalPlan.Nutrients], evidence: URL, runID: UUID) throws -> [EvalScoring.Result] {
        let route = routes.nutrients
        let observations = try cases.map { item -> EvalScoring.Nutrients in
            let request = item.request
            let (timing, response) = try EvalRequestEvidence.read(
                folder: evidence, hash: item.hash, part: .nutrients, runID: runID, request: request.body)
            var kept: [NutrientKey: Double] = [:]
            if let response {
                let parsed = try ConfirmNutrientResponseCheck.check(
                    response, request: request.inputs, models: route.acceptedModels, provider: route.provider).get()
                let rows = ConfirmNutrientResponseCheck.captureRows(parsed, request: request.inputs)
                for row in rows where row.result == ConfirmNutrientRowResult.kept.rawValue {
                    if let key = NutrientKey(rawValue: row.nutrient), let value = Double(row.value) { kept[key] = value }
                }
                kept = ConfirmEnrichmentMerge.merge(kept: kept, leftOut: [], base: item.base, layer: [:]).available
            }
            let requested = request.inputs.eligibleKeys
            let known = Set(request.inputs.knownAmounts.keys)
            return .init(requested: requested, known: known, kept: kept,
                         hidden: item.hidden, declared: item.declared, timing: timing)
        }
        return EvalScoring.nutrients(observations)
    }
}
