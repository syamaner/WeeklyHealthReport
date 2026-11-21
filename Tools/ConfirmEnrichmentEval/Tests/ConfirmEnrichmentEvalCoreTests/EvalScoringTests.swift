import ConfirmEnrichmentEvalCore
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class EvalScoringTests: XCTestCase {
    func testAllKeysBelongToExactlyOneClassAndOnlyMeasuredKeysHaveFloors() {
        let rules = NutrientKey.allCases.map(EvalNutrientBars.rule)
        let groups = EvalNutrientBars.Group.allCases.map { group in rules.filter { $0.group == group }.count }
        XCTAssertEqual(groups, [1, 7, 2, 26, 3])
        XCTAssertEqual(rules.filter { ($0.floor ?? 0) > 0 }.count, 36)
        XCTAssertEqual(EvalNutrientBars.rule(.sodium).floor, 5)
        XCTAssertEqual(EvalNutrientBars.rule(.fiber).floor, 0.5)
        XCTAssertEqual(EvalNutrientBars.rule(.vitaminB12).floor, 0.25)
        XCTAssertEqual(EvalNutrientBars.rule(.potassium).floor, 200)
        XCTAssertEqual(EvalNutrientBars.relativeError(key: .energyConsumed, estimate: 1, declared: 0), 0.20)
        XCTAssertNil(EvalNutrientBars.relativeError(key: .water, estimate: 0, declared: 0))
    }

    func testHiddenVariantsRotateOneKnownKeyPerAvailableClass() {
        let declared: Set<NutrientKey> = [.energyConsumed, .fatTotal, .protein, .fiber, .sodium, .vitaminD, .zinc, .water]
        XCTAssertEqual(EvalNutrientBars.hiddenKeys(declared: declared, caseIndex: 0),
                       [.energyConsumed, .fatTotal, .fiber, .sodium, .vitaminD])
        XCTAssertEqual(EvalNutrientBars.hiddenKeys(declared: declared, caseIndex: 1),
                       [.energyConsumed, .protein, .fiber, .sodium, .zinc])
        XCTAssertEqual(EvalNutrientBars.hiddenKeys(declared: [.protein], caseIndex: 23), [.protein])
        XCTAssertEqual(EvalNutrientBars.sodiumMilligrams(saltGrams: 1.25), 500)
        XCTAssertEqual(EvalNutrientBars.sodiumMilligrams(saltGrams: 0), 0)
        XCTAssertNil(EvalNutrientBars.sodiumMilligrams(saltGrams: -1))
        XCTAssertNil(EvalNutrientBars.sodiumMilligrams(saltGrams: .infinity))
    }

    func testDetailsAtCoverageCostAndLatencyLimitsWithFortifiedMistake() {
        let cases: [EvalScoring.Details] = (0..<10).map { index in
            let fills: [ConfirmDetailsFact: String] = index < 6 ? [.fortification: "unfortified"] : [:]
            let truth = index == 0 ? "fortified" : "unfortified"
            let timing = EvalScoring.Timing(costMicroUSD: 2_000, elapsedSeconds: index == 9 ? 11 : 10)
            return .init(asked: [.fortification], fills: fills, truth: [.fortification: truth], timing: timing)
        }
        let results = EvalScoring.details(cases)
        XCTAssertEqual(results.first { $0.bar == .coverage }?.within, 6)
        XCTAssertEqual(results.filter(\.passed).map(\.bar), [.wrongPreparation, .coverage, .fortifiedPrefills, .cost, .latency])
        XCTAssertEqual(results.first { $0.bar == .wrongPrefills }?.outside, 1)
        XCTAssertEqual(results.first { $0.bar == .unfortifiedOnFortified }?.outside, 1)
    }

    func testBUsesMedianOfKeptAndCountsMissingCoverageAndAccuracy() {
        let timing = EvalScoring.Timing(costMicroUSD: 5_000, elapsedSeconds: 20)
        let cases = [
            EvalScoring.Nutrients(requested: [.energyConsumed], known: [.protein], kept: [.energyConsumed: 90],
                                  hidden: .energyConsumed, declared: 100, timing: timing),
            EvalScoring.Nutrients(requested: [.energyConsumed], known: [.protein], kept: [.energyConsumed: 130],
                                  hidden: .energyConsumed, declared: 100, timing: timing),
            EvalScoring.Nutrients(requested: [.energyConsumed], known: [.protein], kept: [:],
                                  hidden: .energyConsumed, declared: 100, timing: timing),
        ]
        let results = EvalScoring.nutrients(cases)
        XCTAssertEqual(results.filter(\.passed).map(\.bar), [.knownReplaced, .energy, .cost, .latency])
        XCTAssertEqual(results.first { $0.bar == .energy }?.outside, 2)
        XCTAssertEqual(results.first { $0.bar == .coverage }?.within, 2)
    }
}
