import FoodLedgerApplication
import FoodLedgerDomain

/// Aggregate release bars from CE1 section 12. No observation has any displayable case fields.
public enum EvalScoring {
    public enum Bar: String, Sendable {
        case wrongPrefills = "wrong_prefills", wrongPreparation = "wrong_preparation"
        case coverage, fortifiedPrefills = "fortified_prefills", unfortifiedOnFortified = "unfortified_on_fortified"
        case knownReplaced = "known_replaced", cost, latency, evidence
        case energy, macronutrients, fibreAndSodium = "fibre_and_sodium", micronutrients
    }

    public struct Result: Equatable, Sendable {
        public let part: ConfirmEnrichmentPart
        public let bar: Bar
        public let passed: Bool
        public let within: Int
        public let outside: Int

        public init(part: ConfirmEnrichmentPart, bar: Bar, passed: Bool, within: Int, outside: Int) {
            self.part = part
            self.bar = bar
            self.passed = passed
            self.within = within
            self.outside = outside
        }
    }

    public struct Timing: Codable, Sendable {
        public let costMicroUSD: Int?
        public let elapsedSeconds: Double

        public init(costMicroUSD: Int?, elapsedSeconds: Double) {
            self.costMicroUSD = costMicroUSD
            self.elapsedSeconds = elapsedSeconds
        }
    }

    public struct Details: Sendable {
        public let asked: Set<ConfirmDetailsFact>
        public let fills: [ConfirmDetailsFact: String]
        public let truth: [ConfirmDetailsFact: String]
        public let timing: Timing?

        public init(asked: Set<ConfirmDetailsFact>, fills: [ConfirmDetailsFact: String],
                    truth: [ConfirmDetailsFact: String], timing: Timing?) {
            self.asked = asked
            self.fills = fills
            self.truth = truth
            self.timing = timing
        }
    }

    public struct Nutrients: Sendable {
        public let requested: Set<NutrientKey>
        public let known: Set<NutrientKey>
        public let kept: [NutrientKey: Double]
        public let hidden: NutrientKey
        public let declared: Double
        public let timing: Timing?

        public init(requested: Set<NutrientKey>, known: Set<NutrientKey>, kept: [NutrientKey: Double],
                    hidden: NutrientKey, declared: Double, timing: Timing?) {
            self.requested = requested
            self.known = known
            self.kept = kept
            self.hidden = hidden
            self.declared = declared
            self.timing = timing
        }
    }

    public static func details(_ cases: [Details]) -> [Result] {
        let part = ConfirmEnrichmentPart.details
        let asked = cases.reduce(0) { $0 + $1.asked.count }
        let filled = cases.reduce(0) { $0 + $1.asked.intersection($1.fills.keys).count }
        let comparable = cases.flatMap { item in item.fills.map { item.truth[$0.key] == $0.value } }
        let preparation = cases.compactMap { item in item.fills[.preparation].map { item.truth[.preparation] == $0 } }
        let fortified = cases.filter { $0.truth[.fortification] == "fortified" }
        let fills = cases.filter { $0.fills[.fortification] == "fortified" }.count
        let falseUnfortified = fortified.count { $0.fills[.fortification] == "unfortified" }
        let fortifiedSafety = Result(part: part, bar: .unfortifiedOnFortified,
                                    passed: fortified.count >= 8 && falseUnfortified == 0,
                                    within: fortified.count - falseUnfortified, outside: falseUnfortified)
        return [
            // A is a best-effort suggestion the owner corrects on Confirm before Log (owner decision,
            // 22 November 2026): 95% of pre-fills right, 80% of preparation pre-fills right, 40% coverage.
            count(part, .wrongPrefills, comparable.filter { $0 }.count, comparable.count, minimum: 95),
            count(part, .wrongPreparation, preparation.filter { $0 }.count, preparation.count, minimum: 80, allowEmpty: true),
            count(part, .coverage, filled, asked, minimum: 40),
            count(part, .fortifiedPrefills, cases.count - fills, cases.count, minimum: 100),
            fortifiedSafety,
        ] + timing(part, cases.filter { !$0.asked.isEmpty }.map(\.timing), cost: 2_000, seconds: 10)
    }

    public static func nutrients(_ cases: [Nutrients]) -> [Result] {
        let part = ConfirmEnrichmentPart.nutrients
        let asked = cases.reduce(0) { $0 + $1.requested.count }
        let kept = cases.reduce(0) { $0 + $1.requested.intersection($1.kept.keys).count }
        let safe = cases.filter { $0.known.isDisjoint(with: $0.kept.keys) }.count
        let accuracyBars: [(EvalNutrientBars.Group, Bar)] = [
            (.energy, .energy), (.macronutrients, .macronutrients),
            (.fibreAndSodium, .fibreAndSodium), (.micronutrients, .micronutrients),
        ]
        var results = [
            count(part, .coverage, kept, asked, minimum: 70),
            count(part, .knownReplaced, safe, cases.count, minimum: 100),
        ]
        for (group, bar) in accuracyBars {
            let matching = cases.filter { EvalNutrientBars.rule($0.hidden).group == group }
            let errors = matching.map { item -> Double in
                guard let estimate = item.kept[item.hidden],
                      let error = EvalNutrientBars.relativeError(key: item.hidden, estimate: estimate, declared: item.declared)
                else { return .infinity }
                return error
            }
            results.append(median(part, bar, values: errors, limit: group.limit!, missing: 0))
        }
        // B's cost bar: $0.01 median, raised from $0.005 by the owner on 22 November 2026 after the development run
        // measured about $0.0087 per request.
        return results + timing(part, cases.map(\.timing), cost: 10_000, seconds: 20)
    }

    private static func count(_ part: ConfirmEnrichmentPart, _ bar: Bar, _ within: Int, _ total: Int,
                              minimum: Int, allowEmpty: Bool = false) -> Result {
        let passed = total > 0 ? within * 100 >= total * minimum : allowEmpty
        return Result(part: part, bar: bar, passed: passed, within: within, outside: total - within)
    }

    private static func median(_ part: ConfirmEnrichmentPart, _ bar: Bar, values: [Double], limit: Double, missing: Int) -> Result {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        let within = sorted.filter { $0 <= limit }.count
        var passed = false
        if !sorted.isEmpty {
            let value = sorted.count.isMultiple(of: 2) ? sorted[middle - 1] / 2 + sorted[middle] / 2 : sorted[middle]
            passed = value <= limit
        }
        // For accuracy, a missing estimate is an infinite error in the ordered sample.
        return Result(part: part, bar: bar, passed: passed, within: within, outside: values.count - within + missing)
    }

    private static func timing(_ part: ConfirmEnrichmentPart, _ requests: [Timing?], cost: Int, seconds: Double) -> [Result] {
        let costs = requests.compactMap { $0?.costMicroUSD }.filter { $0 >= 0 }.map(Double.init)
        let measured = median(part, .cost, values: costs, limit: Double(cost), missing: requests.count - costs.count)
        let costResult = Result(part: part, bar: .cost, passed: measured.passed && costs.count == requests.count,
                                within: measured.within, outside: measured.outside)
        let fast = requests.count { request in
            guard let elapsed = request?.elapsedSeconds else { return false }
            return elapsed.isFinite && elapsed >= 0 && elapsed <= seconds
        }
        // Nearest-rank p90 is at or below the limit iff at least 90% of the samples are within it.
        let latency = count(part, .latency, fast, requests.count, minimum: 90)
        return [costResult, latency]
    }
}
