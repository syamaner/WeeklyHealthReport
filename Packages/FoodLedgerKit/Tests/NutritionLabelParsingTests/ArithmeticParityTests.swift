import Foundation
import Testing
@testable import NutritionLabelParsing

// Contract tests 2 and 8 (`docs/pasted-nutrition-label-v1.md` section 8.4): the Swift checks
// reproduce `arithmetic.py` per check, with numbers compared as normalised decimals, on every
// exported candidate and on the three frozen mutation families applied to every usable truth.

@Test func test2ChecksReproduceArithmeticPyOnEveryCandidate() throws {
    let lines = try ParityFixtures.lines("parity-cases-v1.jsonl")
    var compared = 0
    var problems: [String] = []
    for record in lines.dropFirst() {
        guard let python = (record["expected"] as? [String: Any])?["arithmetic"] as? [String: Any],
              let candidate = try ParityFixtures.candidate(record["candidate"]),
              let format = LabelGateFormat(rawValue: record["declared_format"] as? String ?? "") else { continue }
        let report = LabelArithmeticChecks.check(LabelArithmeticTable(candidate, format: format))
        problems += ParityFixtures.reportDifferences(report, python).map { "\(record["id"] ?? "?"): \($0)" }
        compared += 1
    }
    #expect(compared > 250)
    #expect(problems.isEmpty, "\(problems.prefix(10))")
}

@Test func test2MutationFamiliesReproduceArithmeticPyIncludingItsMisses() throws {
    let records = try ParityFixtures.lines("parity-mutations-v1.jsonl")
    var problems: [String] = []
    var tables: [String: [LabelArithmeticTable]] = [:]
    var misses: [String] = []
    var untouchedFound = Set<String>()
    for record in records {
        let id = record["id"] as? String ?? "?"
        let truth = try #require(record["truth"] as? [String: Any])
        let jurisdiction = LabelArithmeticChecks.jurisdiction(declared: truth["jurisdiction"] as? String, language: truth["language"] as? String)
        #expect(jurisdiction == record["jurisdiction"] as? String, "\(id) jurisdiction")
        let table = try ParityFixtures.truthTable(truth, jurisdiction: jurisdiction)
        tables[record["split"] as? String ?? "?", default: []].append(table)
        let original = LabelArithmeticChecks.check(table)
        problems += ParityFixtures.reportDifferences(original, record["original"] as? [String: Any] ?? [:]).map { "\(id) original: \($0)" }
        let mutations = record["mutations"] as? [String: Any] ?? [:]
        for mutation in LabelArithmeticChecks.mutations {
            let mutated = LabelArithmeticChecks.mutate(table, mutation)
            guard let python = mutations[mutation] as? [String: Any] else {
                if mutated != nil { problems.append("\(id) \(mutation): Swift applies, Python does not") }
                continue
            }
            guard let mutated else {
                problems.append("\(id) \(mutation): Python applies, Swift does not")
                continue
            }
            let changed = zip(mutated.cells, table.cells).enumerated().filter { $0.element.0 != $0.element.1 }.map { index, pair -> [String: Any] in
                ["index": index, "basis": pair.0.basis, "comparator": pair.0.comparator, "decimal_text": pair.0.decimalText ?? NSNull(), "printed_text": pair.0.printedText]
            }
            if !ParityFixtures.sameJSON(changed, python["changed_cells"] ?? []) {
                problems.append("\(id) \(mutation): mutated cells \(changed) != \(python["changed_cells"] ?? "nil")")
            }
            let checks = LabelArithmeticChecks.check(mutated)
            problems += ParityFixtures.reportDifferences(checks, python["checks"] as? [String: Any] ?? [:]).map { "\(id) \(mutation): \($0)" }
            if original.status != .fail, checks.status != .fail {
                misses.append("\(id) \(mutation)")
                if record["split"] as? String == "untouched" { untouchedFound.insert("\(id) \(mutation)") }
            }
        }
    }
    #expect(problems.isEmpty, "\(problems.prefix(10))")

    // The same detection counts and misses as the Python reference. The untouched truth is the
    // set route A ran on once (its dataset SHA-256 is checked at export), so this is the
    // evaluation's 110/116: tenfold 69/72, transposition 32/35, bound 9/9.
    let development = LabelArithmeticChecks.mutationDetection(tables["development"] ?? [])
    #expect(development["tenfold_serving"]! == (111, 108))
    #expect(development["basis_transposition"]! == (22, 20))
    #expect(development["bound_replaced_by_exact"]! == (12, 5))
    let untouched = LabelArithmeticChecks.mutationDetection(tables["untouched"] ?? [])
    #expect(untouched["tenfold_serving"]! == (72, 69))
    #expect(untouched["basis_transposition"]! == (35, 32))
    #expect(untouched["bound_replaced_by_exact"]! == (9, 9))
    #expect(untouched.values.reduce(0) { $0 + $1.applicable } == 116)
    #expect(untouched.values.reduce(0) { $0 + $1.detected } == 110)
    #expect(untouchedFound == untouchedMisses)
    #expect(misses.count == 18, "\(misses)")
}

/// The 6 planted mutations the frozen check misses on the untouched truth (contract section 1).
private let untouchedMisses: Set<String> = [
    "fda188:f97f36b40df0ebf8:single_column_serving:spaced_units tenfold_serving",
    "fda188:d31492c546833c75:single_column_serving:tab tenfold_serving",
    "fda188:736a033efaaedb29:single_column_serving:tab tenfold_serving",
    "fda188:80ac6fd0e2cf227e:two_column:one_per_line basis_transposition",
    "fda188:b141fe828520b587:two_column:spaced_units basis_transposition",
    "fda188:64df18ee3e8ee5a2:two_column:tab basis_transposition",
]

@Test func test2MuesliEnergyUsesTheTaiwanFibreForm() throws {
    let candidate = NutritionLabelTextParser().parse(muesliText, inputSHA256: String(repeating: "0", count: 64))
    let report = LabelArithmeticChecks.check(LabelArithmeticTable(candidate, format: .taiwan))
    let energy = report.checks.filter { $0.name == "energy" }
    #expect(energy.count == 2)
    for check in energy {
        #expect(check.status == .pass)
        #expect(check.printedKcal == Decimal(string: "367.2"))
        #expect(check.forms?.map(\.form) == ["taiwan"])
        #expect(check.forms?.first?.computedKcal == Decimal(string: "367.2"))
        #expect(check.forms?.first?.difference == 0)
    }
    #expect(report.status == .pass)
    #expect(report.warnings.isEmpty)
}

@Test func test2BoundsAndUnknownsAreNotCheckable() {
    let bound = LabelArithmeticCell(nutrient: "fat", basis: "per_100g", canonicalUnit: "g", comparator: "<", decimalText: "0.5", parentRowID: nil, unit: "g", printedText: "<0.5g")
    let table = LabelArithmeticTable(jurisdiction: "uk", declined: false, servingSize: nil, servingsPerPack: nil, cells: [
        LabelArithmeticCell(nutrient: "energy_kcal", basis: "per_100g", canonicalUnit: "kcal", comparator: "=", decimalText: "100", parentRowID: nil, unit: "kcal", printedText: "100kcal"),
        LabelArithmeticCell(nutrient: "protein", basis: "per_100g", canonicalUnit: "g", comparator: "=", decimalText: "5", parentRowID: nil, unit: "g", printedText: "5g"),
        LabelArithmeticCell(nutrient: "carbohydrate", basis: "per_100g", canonicalUnit: "g", comparator: "=", decimalText: "20", parentRowID: nil, unit: "g", printedText: "20g"),
        bound,
    ])
    let report = LabelArithmeticChecks.check(table)
    #expect(report.checks.first { $0.name == "energy" }?.status == .notCheckable)
    #expect(report.status == .notCheckable)
    #expect(report.warnings.isEmpty)
}

@Test func test8ChecksNeverReadACalculatedValue() throws {
    let text = """
    Nutrition information
    Typical values  Per 100g
    Energy  1550kJ
    Fat  3.2g
    of which saturates  1.1g
    Carbohydrate  70g
    of which sugars  20g
    Protein  8g
    Salt  0.6g
    """
    let candidate = NutritionLabelTextParser().parse(text, inputSHA256: String(repeating: "0", count: 64))
    #expect(!candidate.declined)
    let header = try #require(PastedLabelStoredColumn.headerID(for: candidate))
    let conversions = PastedLabelConversions.conversions(for: candidate, storedHeaderID: header)
    #expect(conversions.map(\.record.rule) == [.kjToKcal, .saltToSodium])
    // The checks run on the printed candidate only, so the calculated kcal is never an input.
    let report = LabelArithmeticChecks.check(LabelArithmeticTable(candidate, format: .uk))
    #expect(report.checks.first { $0.name == "energy" }?.status == .notCheckable)
    #expect(report.checks.first { $0.name == "kj_kcal_ratio" }?.status == .notCheckable)
}

@Test func pythonDecimalTextReproducesStrOfTheTenfoldMutation() {
    #expect(PythonDecimalText("2.5")?.timesTen().description == "25.0")
    #expect(PythonDecimalText("0.50")?.timesTen().description == "5.00")
    #expect(PythonDecimalText("007")?.timesTen().description == "70")
    #expect(PythonDecimalText("12")?.timesTen().description == "120")
    #expect(PythonDecimalText("0.0000001")?.description == "1E-7")
    #expect(PythonDecimalText("1E+1")?.description == "1E+1")
    #expect(PythonDecimalText("0.0")?.description == "0.0")
    #expect(PythonDecimalText("abc") == nil)
}

@Test func pythonContextDivisionRoundsHalfEvenToTwentyEightDigits() {
    let value = PythonDecimalContext.divide(Decimal(865), Decimal(206))
    #expect(value == Decimal(string: "4.199029126213592233009708738"))
    #expect(PythonDecimalContext.divide(Decimal(string: "418.4")!, Decimal(100)) == Decimal(string: "4.184"))
    #expect(PythonDecimalContext.divide(Decimal(2), Decimal(3)) == Decimal(string: "0.6666666666666666666666666667"))
}

let muesliText = """
營養標示
每一份量100公克
本包裝含5份
　　　　　　每份　　　每100公克
熱量　　　367.2大卡　367.2大卡
蛋白質　　11公克　　11公克
脂肪　　　8.8公克　　8.8公克
　飽和脂肪　1.2公克　　1.2公克
　反式脂肪　0公克　　0公克
碳水化合物　67公克　　67公克
　糖　　　9.1公克　　9.1公克
　膳食纖維　12公克　　12公克
鈉　　　　8毫克　　8毫克
"""
