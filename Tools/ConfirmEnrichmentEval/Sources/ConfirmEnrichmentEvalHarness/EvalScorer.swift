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

    public func score(_ list: EvalCaseList, part: ConfirmEnrichmentPart, folder: URL, reviewSheet: URL?) -> [EvalScoring.Result] {
        do {
            switch part {
            case .details:
                guard let reviewSheet else { throw EvalReviewSheet.Invalid() }
                return try scoreDetails(list, folder: folder, reviewSheet: reviewSheet)
            case .nutrients:
                return try scoreNutrients(list, folder: folder)
            }
        } catch {
            return [Self.invalid(part)]
        }
    }

    public func verifyDetailsFreeze(_ list: EvalCaseList, folder: URL, expectedSHA256: String?) -> Bool {
        guard let expectedSHA256 else { return false }
        do {
            for item in list.cases where item.kind == .openFoodFacts {
                let state = try candidates.state(for: item, privateFolder: folder)
                do {
                    guard let request = try EvalRequests.details(state, route: routes.details) else { continue }
                    return try EvalRequestEvidence.hash(request.body) == expectedSHA256
                } catch is ConfirmEnrichmentPolicy.BuildFailure {
                    continue
                }
            }
        } catch {
            return false
        }
        return false
    }

    public static func invalid(_ part: ConfirmEnrichmentPart) -> EvalScoring.Result {
        .init(part: part, bar: .evidence, passed: false, within: 0, outside: 1)
    }

    private func scoreDetails(_ list: EvalCaseList, folder: URL, reviewSheet: URL) throws -> [EvalScoring.Result] {
        let cases = list.cases.filter { $0.kind == .openFoodFacts }
        let hashes = try cases.map { try EvalHashes.hash($0) }
        let truth = try EvalReviewSheet.read(reviewSheet, expected: Set(hashes))
        let route = routes.details
        let runID = try EvalCompletedRun.read(list: list, folder: folder, part: .details)
        let observations = try zip(cases, hashes).map { item, hash -> EvalScoring.Details in
            guard let reviewed = truth[hash] else { throw EvalReviewSheet.Invalid() }
            let state = try candidates.state(for: item, privateFolder: folder)
            guard let request = try EvalRequests.details(state, route: route) else {
                return .init(asked: [], fills: [:], truth: reviewed, timing: nil)
            }
            let (timing, response) = try EvalRequestEvidence.read(
                folder: folder, hash: hash, part: .details, runID: runID, request: request.body)
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

    private func scoreNutrients(_ list: EvalCaseList, folder: URL) throws -> [EvalScoring.Result] {
        let route = routes.nutrients
        let runID = try EvalCompletedRun.read(list: list, folder: folder, part: .nutrients)
        var observations: [EvalScoring.Nutrients] = []
        for (index, item) in list.cases.enumerated() {
            for (variant, declared) in try candidates.nutrientVariants(for: item, index: index, privateFolder: folder) {
                let hash = try EvalHashes.hash(variant)
                let state = try candidates.state(for: variant, privateFolder: folder)
                guard let hidden = variant.hiddenKeys.first,
                      let request = try EvalRequests.nutrients(state, route: route),
                      request.inputs.eligibleKeys.contains(hidden) else { throw EvalRequestEvidence.Invalid() }
                let (timing, response) = try EvalRequestEvidence.read(
                    folder: folder, hash: hash, part: .nutrients, runID: runID, request: request.body)
                var kept: [NutrientKey: Double] = [:]
                if let response {
                    let parsed = try ConfirmNutrientResponseCheck.check(
                        response, request: request.inputs, models: route.acceptedModels, provider: route.provider).get()
                    let rows = ConfirmNutrientResponseCheck.captureRows(parsed, request: request.inputs)
                    for row in rows where row.result == ConfirmNutrientRowResult.kept.rawValue {
                        if let key = NutrientKey(rawValue: row.nutrient), let value = Double(row.value) { kept[key] = value }
                    }
                    let base = state.selectedCandidate.candidate.nutrients
                    kept = ConfirmEnrichmentMerge.merge(kept: kept, leftOut: [], base: base, layer: [:]).available
                }
                let requested = request.inputs.eligibleKeys
                let known = Set(request.inputs.knownAmounts.keys)
                let observation = EvalScoring.Nutrients(requested: requested, known: known, kept: kept,
                                                        hidden: hidden, declared: declared, timing: timing)
                observations.append(observation)
            }
        }
        return EvalScoring.nutrients(observations)
    }
}
