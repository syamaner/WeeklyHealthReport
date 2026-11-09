import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import NutritionLabelParsing
import XCTest

/// Scorer v2 rules R1 to R3 of `docs/pasted-nutrition-label-uk-english-v2-p3.md` section 2, with
/// their positive and negative cases. Each rule only decides which printed cell a read value is
/// compared with; every negative here stays wrong. Every text and value is invented.
final class UKFreshSetScorerV2Tests: XCTestCase {
    private typealias T = UKFreshSet.Transcription
    private struct Clock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) } }
    private let builder = UKFreshSet.builder(clock: Clock())

    private static func v(_ number: String, _ unit: String, outside: Bool? = nil) -> T.Value {
        T.Value(comparator: "=", number: number, unit: unit, outsideTable: outside)
    }

    /// Per 100 g, per bar, a percent reference intake column and a reference amount column (which
    /// S4 sets aside); the energy percentage is printed once.
    static let riText = ["Typical Values\tPer 100g\tPer bar (15g)\t%RI*\tRI*",
                         "Energy\t2050kJ / 490kcal\t310kJ / 74kcal\t3%\t8400kJ / 2000kcal", "Fat\t20.0g\t2.6g\t4%\t70g",
                         "Saturates\t10.0g\t1.3g\t7%\t20g", "Carbohydrate\t60.0g\t7.8g\t3%\t260g", "Sugars\t25.0g\t3.3g\t4%\t90g",
                         "Protein\t6.0g\t0.8g\t2%\t50g", "Salt\t0.20g\t0.03g\t1%\t6g"].joined(separator: "\n")

    /// The transcriber's record of `riText`: the energy percentage on the kJ row, none on kcal.
    private static func riTranscription(_ edit: (inout [T.Row], inout [T.Column]) -> Void = { _, _ in }) -> T {
        var columns: [T.Column] = [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "Per bar (15g)", basis: "per_serving"),
                                   .init(heading: "%RI*", basis: "reference_intake"), .init(heading: "RI*", basis: "reference_intake")]
        var rows: [T.Row] = [
            .init(label: "Energy", nutrient: "energy_kj", values: [v("2050", "kJ"), v("310", "kJ"), v("3", "%"), v("8400", "kJ")]),
            .init(label: "Energy", nutrient: "energy_kcal", values: [v("490", "kcal"), v("74", "kcal"), nil, v("2000", "kcal")]),
            .init(label: "Fat", nutrient: "fat", values: [v("20.0", "g"), v("2.6", "g"), v("4", "%"), v("70", "g")]),
            .init(label: "Saturates", nutrient: "saturates", values: [v("10.0", "g"), v("1.3", "g"), v("7", "%"), v("20", "g")]),
            .init(label: "Carbohydrate", nutrient: "carbohydrate", values: [v("60.0", "g"), v("7.8", "g"), v("3", "%"), v("260", "g")]),
            .init(label: "Sugars", nutrient: "sugars", values: [v("25.0", "g"), v("3.3", "g"), v("4", "%"), v("90", "g")]),
            .init(label: "Protein", nutrient: "protein", values: [v("6.0", "g"), v("0.8", "g"), v("2", "%"), v("50", "g")]),
            .init(label: "Salt", nutrient: "salt", values: [v("0.20", "g"), v("0.03", "g"), v("1", "%"), v("6", "g")]),
        ]
        edit(&rows, &columns)
        return T(schema: UKFreshSet.transcriptionSchema, labelID: "K20", panel: "uk_declaration", servingSize: .init(number: "15", unit: "g"),
                 servingsPerPack: nil, columns: columns, rows: rows, notes: [])
    }

    /// One amount column whose energy kJ row prints its unit only in the label.
    static let labelUnitText = "Typical values\tPer 100ml\nEnergy kJ\t180\nEnergy kcal\t43kcal\nFat\t1.5g\nof which saturates\t1.0g\n"
        + "Carbohydrate\t4.7g\nof which sugars\t4.5g\nProtein\t0.5g\nSalt\t0.10g"

    private static func labelUnitTranscription(label: String = "Energy kJ", value: T.Value = v("180", "", outside: true)) -> T {
        T(schema: UKFreshSet.transcriptionSchema, labelID: "K21", panel: "uk_declaration", servingSize: nil, servingsPerPack: nil,
          columns: [.init(heading: "Per 100ml", basis: "per_100ml")],
          rows: [.init(label: label, nutrient: "energy_kj", values: [value]),
                 .init(label: "Energy kcal", nutrient: "energy_kcal", values: [v("43", "kcal")]),
                 .init(label: "Fat", nutrient: "fat", values: [v("1.5", "g")]),
                 .init(label: "of which saturates", nutrient: "saturates", values: [v("1.0", "g")]),
                 .init(label: "Carbohydrate", nutrient: "carbohydrate", values: [v("4.7", "g")]),
                 .init(label: "of which sugars", nutrient: "sugars", values: [v("4.5", "g")]),
                 .init(label: "Protein", nutrient: "protein", values: [v("0.5", "g")]),
                 .init(label: "Salt", nutrient: "salt", values: [v("0.10", "g")])],
          notes: [])
    }

    private func run(_ text: String, _ t: T) -> UKFreshSet.RunResult {
        UKFreshSet.run(labelID: t.labelID, text: text, transcription: t) { try builder.choose($0, in: $1) }
    }

    private func wrong(_ r: UKFreshSet.RunResult, _ t: T) -> [String] { UKFreshSet.score(r, t).score.wrong }

    /// Re-encodes a run result with its cells changed.
    private func cells(_ r: UKFreshSet.RunResult, _ change: (inout [[String: Any]]) -> Void) throws -> UKFreshSet.RunResult {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        var candidate = try XCTUnwrap(object["candidate"] as? [String: Any])
        var list = try XCTUnwrap(candidate["cells"] as? [[String: Any]])
        change(&list)
        candidate["cells"] = list
        object["candidate"] = candidate
        return try JSONDecoder().decode(UKFreshSet.RunResult.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func riHeader(_ r: UKFreshSet.RunResult) throws -> String {
        try XCTUnwrap(r.candidate?.headers.first { $0.basis == "reference_intake" }?.headerID)
    }

    private func isCell(_ nutrient: String, _ header: String) -> ([String: Any]) -> Bool {
        { ($0["nutrient"] as? String) == nutrient && ($0["header_id"] as? String) == header }
    }

    // MARK: The positive case

    func testTheReferenceColumnTableScoresCleanUnderScorerV2() throws {
        let t = Self.riTranscription()
        let r = run(Self.riText, t)
        XCTAssertEqual(r.outcome, "usable", "\(r.declineCodes)")
        let ri = try riHeader(r)
        XCTAssertEqual(r.candidate?.cells.filter { $0.headerID == ri }.count, 7, "every percentage, energy once")
        XCTAssertEqual(r.candidate?.cells.filter { $0.headerID == ri && $0.nutrient.hasPrefix("energy") }.count, 1)
        XCTAssertEqual(wrong(r, t), [])
        XCTAssertEqual(UKFreshSet.scorerVersion, "uk-fresh-scorer-v2")
    }

    // MARK: R1

    func testR1NegativesStayWrong() throws {
        let r = run(Self.riText, Self.riTranscription())
        let ri = try riHeader(r)
        // The reader's reference column holding an amount.
        let amount = try cells(r) { list in
            list = list.map { var c = $0; if self.isCell("fat", ri)(c) { c["canonical_unit"] = "g"; c["decimal_text"] = "70" }; return c }
        }
        XCTAssertEqual(wrong(amount, Self.riTranscription()).count, 1)
        // Two percent-only reference columns, or none: no single column, so every reference cell is wrong.
        let twoPercent = Self.riTranscription { rows, _ in
            rows = rows.map { T.Row(label: $0.label, nutrient: $0.nutrient, values: Array($0.values.prefix(3)) + [Self.v("1", "%")]) }
        }
        XCTAssertEqual(wrong(r, twoPercent).count, 7)
        let noPercent = Self.riTranscription { rows, _ in
            rows = rows.map { row in T.Row(label: row.label, nutrient: row.nutrient,
                                           values: row.values.enumerated().map { $0.offset == 2 ? $0.element.map { _ in Self.v("9", "g") } : $0.element }) }
        }
        XCTAssertEqual(wrong(r, noPercent).count, 7)
        // A single reference column is matched as before, by basis alone: a g column is not a match.
        let single = Self.riTranscription { rows, columns in
            columns.remove(at: 2)
            rows = rows.map { T.Row(label: $0.label, nutrient: $0.nutrient, values: $0.values.enumerated().filter { $0.offset != 2 }.map(\.element)) }
        }
        XCTAssertEqual(wrong(r, single).count, 7, "percentages against the amount column are all wrong")
    }

    // MARK: R2

    func testR2NegativesStayWrong() throws {
        let r = run(Self.riText, Self.riTranscription())
        let ri = try riHeader(r)
        let energy = try XCTUnwrap(r.candidate?.cells.first { $0.headerID == ri && $0.nutrient.hasPrefix("energy") })
        let own = energy.nutrient == "energy_kcal" ? 1 : 0
        let partner = 1 - own
        func with(_ row: Int, _ value: T.Value?) -> T {
            Self.riTranscription { rows, _ in
                var values = rows[row].values; values[2] = value
                rows[row] = T.Row(label: rows[row].label, nutrient: rows[row].nutrient, values: values)
            }
        }
        func moved() -> T {  // the percentage on the reader's own energy row, so the partner holds none
            Self.riTranscription { rows, _ in
                var a = rows[own].values, b = rows[partner].values
                a[2] = Self.v("3", "%"); b[2] = nil
                rows[own] = T.Row(label: rows[own].label, nutrient: rows[own].nutrient, values: a)
                rows[partner] = T.Row(label: rows[partner].label, nutrient: rows[partner].nutrient, values: b)
            }
        }
        XCTAssertEqual(wrong(r, moved()), [], "on its own row the percentage matches with no rule")
        // The partner holds a different percentage.
        XCTAssertEqual(wrong(r, with(partner, Self.v("5", "%"))).count, 1)
        // Both rows hold a value: only the reader's own row is compared.
        XCTAssertEqual(wrong(r, Self.riTranscription { rows, _ in
            var values = rows[own].values; values[2] = Self.v("4", "%")
            rows[own] = T.Row(label: rows[own].label, nutrient: rows[own].nutrient, values: values)
        }).count, 1)
        // A dash on the own row is not a value, whichever dash; `Trace` and `Tr` are, so they stay wrong.
        for dash in ["-", "–", "—", "−"] { XCTAssertEqual(wrong(r, with(own, Self.v(dash, ""))), [], dash) }
        for marker in ["Trace", "Tr"] { XCTAssertEqual(wrong(r, with(own, Self.v(marker, ""))).count, 1, marker) }
        // A dash on the own row and a different percentage, or none, on the partner row.
        func dashed(partner value: T.Value?) -> T {
            Self.riTranscription { rows, _ in
                var a = rows[own].values, b = rows[partner].values
                a[2] = Self.v("-", ""); b[2] = value
                rows[own] = T.Row(label: rows[own].label, nutrient: rows[own].nutrient, values: a)
                rows[partner] = T.Row(label: rows[partner].label, nutrient: rows[partner].nutrient, values: b)
            }
        }
        XCTAssertEqual(wrong(r, dashed(partner: Self.v("5", "%"))).count, 1, "a different percentage")
        XCTAssertEqual(wrong(r, dashed(partner: nil)).count, 1, "no percentage on either row")
        XCTAssertEqual(wrong(r, dashed(partner: Self.v("-", ""))).count, 1, "a dash on both rows")
        // A non-energy row has no partner.
        let fat = 2
        XCTAssertEqual(wrong(r, with(fat, nil)).count, 1)
        // An amount column: a kcal amount under no kcal value is still wrong.
        let noKcalAmount = Self.riTranscription { rows, _ in
            var values = rows[1].values; values[0] = nil
            rows[1] = T.Row(label: rows[1].label, nutrient: rows[1].nutrient, values: values)
        }
        XCTAssertEqual(wrong(r, noKcalAmount).count, 1)
        // The same percentage bound to both energy rows: the copy on the partner row is compared on
        // its own row, and the reader's own cell then has no rule, so one of the two is wrong.
        let both = try cells(r) { list in
            var copy = list.first(where: self.isCell(energy.nutrient, ri))!
            copy["nutrient"] = energy.nutrient == "energy_kcal" ? "energy_kj" : "energy_kcal"
            list.append(copy)
        }
        XCTAssertEqual(wrong(both, Self.riTranscription()).count, 1)
        // With a dash on the own row, the reader's own cell is compared with the dash and is wrong.
        XCTAssertEqual(wrong(both, with(own, Self.v("-", ""))).count, 1)
    }

    // MARK: R3

    func testR3MatchesAUnitPrintedOnlyInTheRowLabel() throws {
        let t = Self.labelUnitTranscription()
        let r = run(Self.labelUnitText, t)
        XCTAssertEqual(r.outcome, "usable", "\(r.declineCodes)")
        XCTAssertTrue(r.candidate?.cells.contains { $0.nutrient == "energy_kj" && $0.canonicalUnit == "kJ" } == true)
        XCTAssertEqual(wrong(r, t), [])
        XCTAssertEqual(UKFreshSet.labelUnit("Energy kJ"), "kJ")
        XCTAssertEqual(UKFreshSet.labelUnit("Energy (kcal)"), "kcal")
        XCTAssertNil(UKFreshSet.labelUnit("Energy kJ/kcal"))
        XCTAssertNil(UKFreshSet.labelUnit("Energy (kJ) kcal"), "two units")
        XCTAssertNil(UKFreshSet.labelUnit("Energy"))
    }

    func testR3NegativesStayWrong() throws {
        let t = Self.labelUnitTranscription()
        let r = run(Self.labelUnitText, t)
        let kcal = try cells(r) { list in
            list = list.map { var c = $0; if (c["nutrient"] as? String) == "energy_kj" { c["canonical_unit"] = "kcal" }; return c }
        }
        XCTAssertEqual(wrong(kcal, t).count, 1, "a read unit other than the one the label names")
        for label in ["Energy kJ/kcal", "Energy (kJ) kcal", "Energy"] {
            XCTAssertEqual(wrong(r, Self.labelUnitTranscription(label: label)).count, 1, label)
        }
        XCTAssertEqual(wrong(r, Self.labelUnitTranscription(value: Self.v("180", "kcal"))).count, 1, "a printed unit is never overridden")
        XCTAssertEqual(wrong(r, Self.labelUnitTranscription(value: Self.v("181", "", outside: true))).count, 1, "a different number")
    }

    /// R3 never applies in a reference intake column, where a bare number is a percentage: a read
    /// amount carrying the row label's unit there stays wrong (invariant review finding 1).
    func testR3DoesNotApplyInAReferenceColumn() throws {
        let t = Self.riTranscription { rows, columns in
            columns.remove(at: 3)
            rows = rows.map { row in
                var values = Array(row.values.prefix(3))
                if row.nutrient == "energy_kj" { values[2] = Self.v("3", "", outside: true) }
                return T.Row(label: row.nutrient == "energy_kj" ? "Energy kJ" : row.label, nutrient: row.nutrient, values: values)
            }
        }
        let r = run(Self.riText, Self.riTranscription())
        let ri = try riHeader(r)
        let misread = try cells(r) { list in
            var energy = list.first(where: { ($0["header_id"] as? String) == ri && (($0["nutrient"] as? String)?.hasPrefix("energy") ?? false) })!
            list.removeAll { ($0["header_id"] as? String) == ri && (($0["nutrient"] as? String)?.hasPrefix("energy") ?? false) }
            energy["nutrient"] = "energy_kj"; energy["canonical_unit"] = "kJ"; energy["decimal_text"] = "3"
            list.append(energy)
        }
        let energyWrong = wrong(misread, t).filter { $0.contains(" energy_kj ") }
        XCTAssertEqual(energyWrong.count, 1, "3 kJ under the reference header is not the printed 3: \(wrong(misread, t))")
        XCTAssertFalse(UKFreshSet.same(comparator: "=", number: "3", unit: "kJ", readLabel: "Energy kJ", as: Self.v("3", "", outside: true),
                                       printedLabel: "Energy kJ", inReferenceColumn: true))
        XCTAssertTrue(UKFreshSet.same(comparator: "=", number: "3", unit: "kJ", readLabel: "Energy kJ", as: Self.v("3", "", outside: true),
                                      printedLabel: "Energy kJ", inReferenceColumn: false), "in an amount column R3 applies")
    }
}
