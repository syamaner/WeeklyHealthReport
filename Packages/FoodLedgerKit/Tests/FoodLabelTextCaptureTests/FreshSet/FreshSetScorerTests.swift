import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import XCTest

/// The fresh-set harness and scorer (reader v3 section 12.2) on synthetic texts only: the unit
/// table, exact comparison, calculated values scored by their printed operand, the basis taken
/// from the transcription, the correction burden, the seals and the private-folder guard.
final class FreshSetScorerTests: XCTestCase {
    private typealias T = FreshSet.Transcription
    private struct Clock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }
    private let builder = PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: Clock(), encoder: FoundationCanonicalJSONEncoder(),
                                                  digester: SHA256Digester(), conversions: NutritionLabelConversionChecker())

    private static func v(_ number: String, _ unit: String, _ comparator: String = "=") -> T.Value {
        T.Value(comparator: comparator, number: number, unit: unit)
    }

    /// The transcription of `SyntheticLabelTexts.base`, as a careful reader of its label records it.
    private static func baseTranscription(_ edit: (inout [T.Row]) -> Void = { _ in }) -> T {
        var rows: [T.Row] = [
            .init(label: "熱量", nutrient: "energy_kcal", values: [v("167.7", "大卡"), v("419.2", "大卡")]),
            .init(label: "蛋白質", nutrient: "protein", values: [v("6.0", "公克"), v("15.1", "公克")]),
            .init(label: "脂肪", nutrient: "fat", values: [v("3.8", "公克"), v("9.6", "公克")]),
            .init(label: "飽和脂肪", nutrient: "saturates", values: [v("0.5", "公克"), v("1.3", "公克")]),
            .init(label: "反式脂肪", nutrient: "trans_fat", values: [v("0.1", "公克", "<"), v("0.1", "公克", "<")]),
            .init(label: "碳水化合物", nutrient: "carbohydrate", values: [v("29.2", "公克"), v("72.9", "公克")]),
            .init(label: "糖", nutrient: "sugars", values: [v("0.5", "公克", "<"), v("0.5", "公克", "<")]),
            .init(label: "膳食纖維", nutrient: "fibre", values: [v("3.8", "公克"), v("9.6", "公克")]),
            .init(label: "鈉", nutrient: "sodium", values: [v("101", "毫克"), v("252", "毫克")]),
        ]
        edit(&rows)
        return T(schema: FreshSet.transcriptionSchema, labelID: "S01", servingSize: .init(number: "40", unit: "公克"),
                 servingsPerPack: .init(number: "2", approximate: false),
                 columns: [.init(heading: "每份", basis: "per_serving"), .init(heading: "每100公克", basis: "per_100g")], rows: rows, notes: [])
    }

    private func run(_ text: String, _ t: T) -> FreshSet.RunResult {
        FreshSet.run(labelID: t.labelID, text: text, transcription: t) { try builder.choose($0, in: $1) }
    }

    func testAMatchingTranscriptionHasNoWrongValue() {
        let t = Self.baseTranscription()
        XCTAssertEqual(FreshSet.problems(t, expectedID: "S01"), [])
        let score = FreshSet.score(run(SyntheticLabelTexts.base, t), t)
        XCTAssertEqual(score.outcome, "usable")
        XCTAssertEqual(score.wrong, [])
        XCTAssertEqual(score.valuesChecked, 18 + 2, "every cell in both columns, the serving size and the pack count")
        XCTAssertEqual(score.correctionBurden, 0)
    }

    func testEachKindOfDifferenceIsAWrongValue() {
        let result = run(SyntheticLabelTexts.base, Self.baseTranscription())
        // A different number.
        XCTAssertEqual(FreshSet.score(result, Self.baseTranscription { $0[1] = .init(label: "蛋白質", nutrient: "protein",
            values: [Self.v("6.1", "公克"), Self.v("15.1", "公克")]) }).wrong.count, 1)
        // A different comparator: "< 0.1" transcribed as exact.
        XCTAssertEqual(FreshSet.score(result, Self.baseTranscription { $0[4] = .init(label: "反式脂肪", nutrient: "trans_fat",
            values: [Self.v("0.1", "公克"), Self.v("0.1", "公克", "<")]) }).wrong.count, 1)
        // A different unit.
        XCTAssertEqual(FreshSet.score(result, Self.baseTranscription { $0[8] = .init(label: "鈉", nutrient: "sodium",
            values: [Self.v("101", "公克"), Self.v("252", "毫克")]) }).wrong.count, 1)
        // Bound where the label prints nothing.
        XCTAssertEqual(FreshSet.score(result, Self.baseTranscription { $0[7] = .init(label: "膳食纖維", nutrient: "fibre",
            values: [nil, Self.v("9.6", "公克")]) }).wrong.count, 1)
        // Exact decimal equality: 6.0 and 6 are the same number; the unit table maps g and 公克 alike.
        XCTAssertEqual(FreshSet.score(result, Self.baseTranscription { $0[1] = .init(label: "蛋白質", nutrient: "protein",
            values: [Self.v("6", "g"), Self.v("15.10", "公克")]) }).wrong, [])
    }

    func testACalculatedValueIsScoredByItsPrintedOperand() {
        var t = Self.baseTranscription { $0[0] = .init(label: "熱量", nutrient: "energy_kj", values: [Self.v("701.7", "kJ"), Self.v("1754", "kJ")]) }
        let result = run(SyntheticLabelTexts.kilojoulesOnly, t)
        XCTAssertFalse(result.conversions.isEmpty, "kcal is calculated from the printed kJ")
        let score = FreshSet.score(result, t)
        XCTAssertEqual(score.wrong, [])
        XCTAssertEqual(score.correctionBurden, 0, "a calculated kcal is not an entry the user must make")
        t = Self.baseTranscription { $0[0] = .init(label: "熱量", nutrient: "energy_kj", values: [Self.v("701.7", "kJ"), Self.v("1755", "kJ")]) }
        XCTAssertEqual(FreshSet.score(result, t).wrong.filter { $0.hasPrefix("calculated") }.count, 1)
    }

    func testTheBasisComesFromTheVerifiedTranscription() throws {
        let rows: [T.Row] = [
            .init(label: "熱量", nutrient: "energy_kcal", values: [Self.v("120", "大卡")]),
            .init(label: "蛋白質", nutrient: "protein", values: [Self.v("3.0", "公克")]),
            .init(label: "脂肪", nutrient: "fat", values: [Self.v("4.5", "公克")]),
            .init(label: "飽和脂肪", nutrient: "saturates", values: [Self.v("1.5", "公克")]),
            .init(label: "反式脂肪", nutrient: "trans_fat", values: [Self.v("0", "公克")]),
            .init(label: "碳水化合物", nutrient: "carbohydrate", values: [Self.v("18.0", "公克")]),
            .init(label: "糖", nutrient: "sugars", values: [Self.v("6.0", "公克")]),
            .init(label: "鈉", nutrient: "sodium", values: [Self.v("60", "毫克")]),
        ]
        func transcription(_ basis: String?) -> T {
            T(schema: FreshSet.transcriptionSchema, labelID: "S02", servingSize: .init(number: "30", unit: "公克"),
              servingsPerPack: .init(number: "8", approximate: false), columns: [.init(heading: basis == nil ? nil : "每份", basis: basis)],
              rows: rows, notes: [])
        }
        let chosen = run(UnheadedTableFixtures.inline1, transcription("per_serving"))
        XCTAssertEqual(chosen.outcome, "usable")
        XCTAssertEqual(chosen.choice?.arrangement, "per_serving")
        XCTAssertEqual(FreshSet.score(chosen, transcription("per_serving")).wrong, [])
        let notSure = run(UnheadedTableFixtures.inline1, transcription(nil))
        XCTAssertEqual(notSure.declineCodes, [FreshSet.basisNotSure])
        // Two columns in an order the template never prints: not offered, so declined.
        let two = T(schema: FreshSet.transcriptionSchema, labelID: "S03", servingSize: .init(number: "30", unit: "公克"), servingsPerPack: nil,
                    columns: [.init(heading: "每100公克", basis: "per_100g"), .init(heading: "每份", basis: "per_serving")], rows: [], notes: [])
        XCTAssertEqual(run(UnheadedTableFixtures.inline2, two).declineCodes, [FreshSet.basisNotOffered])
    }

    func testTheBurdenCountsPrintedLedgerValuesTheStoredColumnLeavesUnread() {
        let t = Self.baseTranscription()
        let score = FreshSet.score(run(SyntheticLabelTexts.sodiumMissing, t), t)
        XCTAssertEqual(score.correctionBurden, 1, "sodium is printed on the label but absent from the text")
    }

    func testTranscriptionValidation() {
        let bad = Self.baseTranscription { $0[1] = .init(label: "蛋白質", nutrient: "proteins", values: [Self.v("6,0", "grams")]) }
        let problems = FreshSet.problems(bad, expectedID: "S01")
        XCTAssertTrue(problems.contains("蛋白質: nutrient"))
        XCTAssertTrue(problems.contains("蛋白質: number"))
        XCTAssertTrue(problems.contains("蛋白質: unit grams"))
        XCTAssertTrue(problems.contains("蛋白質: 1 values for 2 columns"))
    }

    func testTheUnitTableIsFixed() {
        XCTAssertEqual(FreshSet.units["大卡"], "kcal")
        XCTAssertEqual(FreshSet.units["公克"], "g")
        XCTAssertEqual(FreshSet.units["毫克"], "mg")
        XCTAssertEqual(FreshSet.units["毫升"], "ml")
        XCTAssertEqual(FreshSet.units["kJ"], "kJ")
        XCTAssertEqual(FreshSet.units.count, 22)
    }

    func testSealsAreOrderedAndAChangeAfterSeal2VoidsTheRun() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fresh-set-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try FreshSet.privateFolder(root.path)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("texts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("transcription"), withIntermediateDirectories: true)
        try Data(SyntheticLabelTexts.base.utf8).write(to: folder.appendingPathComponent("texts/S01.txt"))
        let encoder = JSONEncoder()
        try encoder.encode(Self.baseTranscription()).write(to: folder.appendingPathComponent("transcription/S01.json"))
        XCTAssertThrowsError(try FreshSet.seal(.seal1, folder), "the text seal comes first")
        XCTAssertThrowsError(try FreshSet.runAll(folder), "no run before seal 2")
        _ = try FreshSet.seal(.text, folder)
        XCTAssertThrowsError(try FreshSet.seal(.text, folder), "a seal is never replaced")
        _ = try FreshSet.seal(.seal1, folder)
        _ = try FreshSet.seal(.seal2, folder)
        XCTAssertEqual(try FreshSet.runAll(folder), 1)
        XCTAssertEqual(try FreshSet.runAll(folder), 0, "a rerun covers only labels with no output")
        let summary = try FreshSet.scoreAll(folder)
        XCTAssertEqual(summary.wrongValues, 0)
        XCTAssertTrue(summary.passes)
        XCTAssertEqual(summary.perValueUpperBound95, "0.150", "3/20")
        // Any transcription change after seal 2 voids the run and the score.
        try encoder.encode(Self.baseTranscription { $0.removeLast() }).write(to: folder.appendingPathComponent("transcription/S01.json"))
        XCTAssertThrowsError(try FreshSet.scoreAll(folder))
    }

    func testAFolderInsideAGitCheckoutIsRefused() {
        let inside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
        XCTAssertThrowsError(try FreshSet.privateFolder(inside))
        XCTAssertThrowsError(try FreshSet.privateFolder("relative/path"))
    }

    func testTheSummaryStatesTheStatisticalLimit() {
        func score(_ id: String, burden: Int, wrong: [String] = []) -> FreshSet.Score {
            .init(labelID: id, outcome: "usable", declineCodes: [], valuesChecked: 50, wrong: wrong, correctionBurden: burden,
                  unreadRows: 0, basisChoice: false, flags: [], warningCodes: [])
        }
        let declined = FreshSet.Score(labelID: "D", outcome: "declined", declineCodes: ["too_little_read"], valuesChecked: 0, wrong: [],
                                      correctionBurden: nil, unreadRows: 0, basisChoice: false, flags: [], warningCodes: [])
        let summary = FreshSet.summary([score("A", burden: 0), score("B", burden: 1), score("C", burden: 3), declined])
        XCTAssertEqual(summary.valuesChecked, 150)
        XCTAssertEqual(summary.perValueUpperBound95, "0.020")
        XCTAssertEqual(summary.perTableUpperBound95, "1.000")
        XCTAssertEqual(summary.burdenMedian, "1")
        XCTAssertEqual(summary.declinedByReason, ["too_little_read": 1])
        XCTAssertTrue(summary.passes)
        XCTAssertFalse(FreshSet.summary([score("A", burden: 0, wrong: ["x"])]).passes)
    }
}
