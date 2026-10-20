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
        XCTAssertTrue(problems.contains("蛋白質: number 6,0 without outside_table"))
        XCTAssertTrue(problems.contains("蛋白質: unit grams without outside_table"))
        XCTAssertTrue(problems.contains("蛋白質: 1 values for 2 columns"))
    }

    func testTheUnitTableIsFixed() {
        XCTAssertEqual(FreshSet.unit("大卡"), "kcal")
        XCTAssertEqual(FreshSet.unit("公克"), "g")
        XCTAssertEqual(FreshSet.unit("毫克"), "mg")
        XCTAssertEqual(FreshSet.unit("毫升"), "ml")
        XCTAssertEqual(FreshSet.unit("kJ"), "kJ")
        XCTAssertEqual(FreshSet.units.count, 21)
        // Case-insensitive, and the listed equivalences.
        for (printed, canonical) in [("kCal", "kcal"), ("KCAL", "kcal"), ("Kj", "kJ"), ("G", "g"), ("MG", "mg"), ("Ml", "ml"),
                                     ("mL", "ml"), ("cc", "ml"), ("gr", "g"), ("gm", "g"), ("mcg", "µg"), ("微克", "µg")] {
            XCTAssertEqual(FreshSet.unit(printed), canonical, printed)
        }
        XCTAssertNil(FreshSet.unit("ｇ"), "full-width forms stay outside the table")
        XCTAssertNil(FreshSet.unit("公撮"))
        for (printed, canonical) in [("=", "="), ("<", "<"), ("＜", "<"), ("未滿", "<"), ("少於", "<"),
                                     ("<=", "<="), ("≦", "<="), ("≤", "<="), ("以下", "<=")] {
            XCTAssertEqual(FreshSet.comparator(printed), canonical, printed)
        }
        XCTAssertNil(FreshSet.comparator(">"))
    }

    func testEquivalentPrintedFormsMatchTheReader() {
        let t = Self.baseTranscription {
            $0[0] = .init(label: "熱量", nutrient: "energy_kcal", values: [Self.v("167.7", "kCal"), Self.v("419.2", "KCAL")])
            $0[4] = .init(label: "反式脂肪", nutrient: "trans_fat", values: [Self.v("0.1", "G", "未滿"), Self.v("0.1", "gm", "＜")])
            $0[6] = .init(label: "糖", nutrient: "sugars", values: [Self.v("0.5", "公克", "少於"), Self.v("0.5", "g", "<")])
        }
        XCTAssertEqual(FreshSet.problems(t, expectedID: "S01"), [], "mapped forms need no outside_table")
        XCTAssertEqual(FreshSet.score(run(SyntheticLabelTexts.base, t), t).wrong, [])
        let atMost = Self.baseTranscription { $0[4] = .init(label: "反式脂肪", nutrient: "trans_fat", values: [Self.v("0.1", "公克", "以下"), Self.v("0.1", "公克", "<")]) }
        XCTAssertEqual(FreshSet.score(run(SyntheticLabelTexts.base, atMost), atMost).wrong.count, 1, "以下 is <=, not <")
    }

    func testLabelNormalisation() {
        XCTAssertEqual(FreshSet.normalisedLabel("  ＊膳食纖維（公克）："), FreshSet.normalisedLabel("膳食纖維"))
        XCTAssertEqual(FreshSet.normalisedLabel(">> 維生素C (mg):"), "維生素c")
        XCTAssertEqual(FreshSet.normalisedLabel("• 鈣(毫克) (自願標示者)"), "鈣")
        XCTAssertEqual(FreshSet.normalisedLabel("Ｃａｌｃｉｕｍ"), "calcium")
        XCTAssertNotEqual(FreshSet.normalisedLabel("鈣(每日)"), "鈣", "a bracket that is not a unit stays")
    }

    func testADecimalCommaIsADecimalPointOnlyOffTaiwanRows() {
        XCTAssertEqual(FreshSet.rowNumber("1,5", rowLabel: "維生素C"), Decimal(string: "1.5"))
        XCTAssertEqual(FreshSet.rowNumber("1,5", rowLabel: "Vitamin C"), Decimal(string: "1.5"))
        XCTAssertNil(FreshSet.rowNumber("1,5", rowLabel: "脂肪"), "any comma on a Taiwan alias row")
        XCTAssertNil(FreshSet.rowNumber("1,500", rowLabel: "維生素C"), "three digits after the comma")
        XCTAssertNil(FreshSet.rowNumber("1,5,0", rowLabel: "維生素C"))
        XCTAssertEqual(FreshSet.rowNumber("1.5", rowLabel: "脂肪"), Decimal(string: "1.5"))
    }

    /// Parity with the reader on synthetic rows: where the scorer's rule parses a comma, the
    /// reader binds the cell with that `decimal_text`; where it does not, the reader leaves the
    /// row unread. A correct verbatim `1,5` then scores as no wrong value.
    func testTheCommaRuleMatchesTheReaderRowByRow() {
        func text(_ extra: [String], replacing prefix: String? = nil) -> String {
            let rows = SyntheticLabelTexts.rows.map { row in prefix.map { row.hasPrefix($0) } == true ? extra[0] : row }
            return SyntheticLabelTexts.taiwan(prefix == nil ? rows + extra : rows)
        }
        // An unrecognised zh-Hant row: the reader keeps 1,5 and the scorer reads it as 1.5.
        let vitamin = run(text(["維生素C  1,5 毫克  3,5 毫克"]), Self.baseTranscription())
        let cell = vitamin.candidate?.cells.first { $0.printedLabel == "維生素C" }
        XCTAssertEqual(cell?.decimalText, "1,5")
        XCTAssertEqual(FreshSet.rowNumber("1,5", rowLabel: "維生素C"), Decimal(string: "1.5"))
        let t = Self.baseTranscription { $0.append(.init(label: "維生素C", nutrient: "other",
            values: [T.Value(comparator: "=", number: "1,5", unit: "毫克"), T.Value(comparator: "=", number: "3,5", unit: "毫克")])) }
        XCTAssertEqual(FreshSet.problems(t, expectedID: "S01"), [], "a comma the rule reads needs no outside_table")
        XCTAssertEqual(FreshSet.score(vitamin, t).wrong, [])
        // A Taiwan alias row: the reader leaves it unread, and the scorer cannot parse it.
        let fat = run(text(["脂肪  1,5 公克  9,6 公克"], replacing: "脂肪"), Self.baseTranscription())
        XCTAssertFalse(fat.candidate?.cells.contains { $0.nutrient == "fat" } ?? true)
        XCTAssertNil(FreshSet.rowNumber("1,5", rowLabel: "脂肪"))
        // Three digits after the comma: ambiguous for both.
        let thousands = run(text(["維生素C  1,500 毫克  3,5 毫克"]), Self.baseTranscription())
        XCTAssertFalse(thousands.candidate?.cells.contains { $0.printedLabel == "維生素C" } ?? true)
        XCTAssertNil(FreshSet.rowNumber("1,500", rowLabel: "維生素C"))
    }

    /// The reader binds `Cal` on a row it does not recognise, in a table that reaches Confirm; an
    /// energy row in Cal is left unread (3.9). The scorer maps Cal to the reader's `cal`.
    func testACalValueOnAnUnrecognisedRowMatches() {
        let text = SyntheticLabelTexts.taiwan(SyntheticLabelTexts.rows + ["膽固醇  5 Cal  12 Cal"])
        let t = Self.baseTranscription { $0.append(.init(label: "膽固醇", nutrient: "other", values: [Self.v("5", "Cal"), Self.v("12", "Cal")])) }
        let result = run(text, t)
        XCTAssertEqual(result.candidate?.cells.filter { $0.canonicalUnit == "cal" }.count, 2)
        XCTAssertEqual(FreshSet.score(result, t).wrong, [])
        let energyInCal = run(SyntheticLabelTexts.taiwan(["熱量  167.7 Cal  419.2 Cal"] + SyntheticLabelTexts.rows.dropFirst()), t)
        XCTAssertEqual(energyInCal.candidate?.cells.filter { $0.canonicalUnit == "cal" }.count, 0)
    }

    func testALabelThatNormalisesToNothingNeverMatches() throws {
        XCTAssertEqual(FreshSet.normalisedLabel(" ＊ ："), "")
        let base = run(SyntheticLabelTexts.base, Self.baseTranscription())
        let blank = try mutate(base) { object in
            var candidate = object["candidate"] as! [String: Any]
            candidate["cells"] = (candidate["cells"] as! [[String: Any]]).map { cell in
                var cell = cell
                if (cell["nutrient"] as? String) == "fibre" { cell["nutrient"] = "unrecognised"; cell["printed_label"] = "*" }
                return cell
            }
            object["candidate"] = candidate
        }
        let t = Self.baseTranscription { $0.append(.init(label: "：", nutrient: "other", values: [Self.v("3.8", "公克"), Self.v("9.6", "公克")])) }
        XCTAssertEqual(FreshSet.score(blank, t).wrong.count, 2, "an empty label is bound but matches nothing")
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
        XCTAssertThrowsError(try FreshSet.runAll(folder, commit: "c"), "no run before seal 2")
        _ = try FreshSet.seal(.text, folder)
        XCTAssertThrowsError(try FreshSet.seal(.text, folder), "a seal is never replaced")
        _ = try FreshSet.seal(.seal1, folder)
        _ = try FreshSet.seal(.seal2, folder)
        XCTAssertEqual(try FreshSet.runAll(folder, commit: "c"), 1)
        XCTAssertEqual(try FreshSet.runAll(folder, commit: "c"), 0, "the one rerun covers only labels with no output")
        XCTAssertThrowsError(try FreshSet.runAll(folder, commit: "c"), "a third attempt is refused")
        let log = try String(contentsOf: folder.appendingPathComponent("run-log.txt"), encoding: .utf8)
        XCTAssertTrue(log.contains("commit=c attempt=1 pending=S01\nwrote S01\n"), log)
        XCTAssertTrue(log.contains("attempt=2 pending=\n"), log)
        let summary = try FreshSet.scoreAll(folder)
        XCTAssertEqual(summary.wrongValues, 0)
        XCTAssertTrue(summary.passes)
        XCTAssertEqual(summary.perValueUpperBound95, "0.150", "3/20")
        // Any transcription change after seal 2 voids the run and the score.
        try encoder.encode(Self.baseTranscription { $0.removeLast() }).write(to: folder.appendingPathComponent("transcription/S01.json"))
        XCTAssertThrowsError(try FreshSet.scoreAll(folder))
    }

    func testAFolderInsideAGitCheckoutIsRefused() throws {
        let checkout = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("checkout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: checkout) }
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let inside = checkout.appendingPathComponent("fresh/set")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        XCTAssertThrowsError(try FreshSet.privateFolder(inside.path))
        XCTAssertThrowsError(try FreshSet.privateFolder(checkout.path))
        XCTAssertThrowsError(try FreshSet.privateFolder("relative/path"))
        let outside = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("outside-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        XCTAssertNoThrow(try FreshSet.privateFolder(outside.path))
    }

    func testRunOutputsTheLogDoesNotAccountForAreRefused() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fresh-set-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["texts", "transcription", "run"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data(SyntheticLabelTexts.base.utf8).write(to: root.appendingPathComponent("texts/S01.txt"))
        try JSONEncoder().encode(Self.baseTranscription()).write(to: root.appendingPathComponent("transcription/S01.json"))
        for seal in FreshSet.Seal.allCases { _ = try FreshSet.seal(seal, root) }
        try Data("{}".utf8).write(to: root.appendingPathComponent("run/S01.json"))
        XCTAssertThrowsError(try FreshSet.runAll(root, commit: "c"))
    }

    // MARK: Review of #286 at 5340a966

    /// Re-encodes a run result with a change to its JSON, for scorer cases the Taiwan reader
    /// cannot produce from a synthetic text (a salt row).
    private func mutate(_ r: FreshSet.RunResult, _ change: (inout [String: Any]) -> Void) throws -> FreshSet.RunResult {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(FreshSet.RunResult.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testSaltToSodiumIsScoredByItsOperandInGrams() throws {
        let base = run(SyntheticLabelTexts.base, Self.baseTranscription())
        let stored = try XCTUnwrap(base.storedHeaderID)
        let salted = try mutate(base) { object in
            var candidate = object["candidate"] as! [String: Any]
            var cells = (candidate["cells"] as! [[String: Any]]).filter { ($0["nutrient"] as? String) != "sodium" }
            var salt = (candidate["cells"] as! [[String: Any]]).first { ($0["nutrient"] as? String) == "sodium" && ($0["header_id"] as? String) == stored }!
            salt["row_id"] = "row_salt"; salt["nutrient"] = "salt"; salt["printed_label"] = "鹽"
            salt["decimal_text"] = "0.63"; salt["unit"] = "公克"; salt["canonical_unit"] = "g"; salt["printed_text"] = "0.63 公克"
            cells.append(salt)
            candidate["cells"] = cells
            object["candidate"] = candidate
            object["conversions"] = [["nutrient": "sodium", "rule": "salt_to_sodium_v1", "rule_version": "pasted-label-conversions-v1",
                                      "source_header_id": stored, "source_row_id": "row_salt", "operand_text": "0.63", "operand_unit": "g_salt",
                                      "factor_text": "2.5", "intermediate_text": "252.000000", "stored_text": "252.0"]]
        }
        func transcription(sodium: [T.Value?]) -> T {
            Self.baseTranscription { rows in
                rows[8] = .init(label: "鈉", nutrient: "sodium", values: sodium)
                rows.append(.init(label: "鹽", nutrient: "salt", values: [nil, Self.v("0.63", "公克")]))
            }
        }
        XCTAssertEqual(FreshSet.score(salted, transcription(sodium: [nil, nil])).wrong, [], "operand 0.63 g of salt against 0.63 公克")
        XCTAssertEqual(FreshSet.score(salted, transcription(sodium: [nil, Self.v("252", "毫克")])).wrong, [],
                       "the calculated sodium agrees with the printed one within rounding")
        // Non-gating: a printed sodium the reader left unread, beside the calculated one, is a
        // reported discrepancy and an entry in the burden, never a wrong value.
        let differs = FreshSet.score(salted, transcription(sodium: [nil, Self.v("300", "毫克")]))
        XCTAssertEqual(differs.wrong, [])
        XCTAssertEqual(differs.calculatedDiscrepancies, ["sodium: calculated 252.0, printed =300 毫克, difference -48"])
        XCTAssertEqual(differs.correctionBurden, 1)
        XCTAssertEqual(FreshSet.score(salted, transcription(sodium: [nil, nil])).correctionBurden, 0)
        XCTAssertEqual(FreshSet.score(salted, transcription(sodium: [nil, nil])).calculatedDiscrepancies, [])
        // A printed target recorded outside the tables is never compared.
        let outside = FreshSet.score(salted, transcription(sodium: [nil, T.Value(comparator: "=", number: "２５２", unit: "毫克", outsideTable: true)]))
        XCTAssertEqual(outside.wrong, [])
        XCTAssertEqual(outside.calculatedDiscrepancies, [])
    }

    /// The reader calculates kcal from kJ when the kcal row is printed but left unread (the
    /// conversion reads the candidate, which has no kcal cell then). The scorer compares it with
    /// the printed kcal.
    func testACalculatedKcalBesideAnUnreadPrintedKcalIsComparedWithIt() {
        let kjAndKcal = Self.baseTranscription { $0.insert(.init(label: "熱量", nutrient: "energy_kj",
            values: [Self.v("701.7", "kJ"), Self.v("1754", "kJ")]), at: 0) }
        let result = run(SyntheticLabelTexts.kilojoulesOnly, kjAndKcal)
        XCTAssertFalse(result.conversions.isEmpty)
        XCTAssertEqual(FreshSet.score(result, kjAndKcal).wrong, [], "419.2 calculated, 419.2 printed")
        XCTAssertEqual(FreshSet.score(result, kjAndKcal).calculatedDiscrepancies, ["energy_kcal: calculated 419.2, printed =419.2 大卡, difference 0"])
        let differs = Self.baseTranscription {
            $0[0] = .init(label: "熱量", nutrient: "energy_kcal", values: [Self.v("167.7", "大卡"), Self.v("430", "大卡")])
            $0.insert(.init(label: "熱量", nutrient: "energy_kj", values: [Self.v("701.7", "kJ"), Self.v("1754", "kJ")]), at: 0)
        }
        let scored = FreshSet.score(result, differs)
        XCTAssertEqual(scored.wrong, [], "labels using other factors never fail the check")
        XCTAssertEqual(scored.calculatedDiscrepancies.count, 1)
        XCTAssertEqual(scored.correctionBurden, 1, "the printed kcal left unread is an entry")
        XCTAssertEqual(FreshSet.summary([scored]).calculatedVsPrintedDiscrepancies, 1)
    }

    func testAnUnrecognisedCellMatchesAnyRowByNormalisedLabel() throws {
        let base = run(SyntheticLabelTexts.base, Self.baseTranscription())
        let renamed = try mutate(base) { object in
            var candidate = object["candidate"] as! [String: Any]
            candidate["cells"] = (candidate["cells"] as! [[String: Any]]).map { cell in
                var cell = cell
                if (cell["nutrient"] as? String) == "fibre" { cell["nutrient"] = "unrecognised"; cell["printed_label"] = "膳食纖維 (自願標示者)" }
                return cell
            }
            object["candidate"] = candidate
        }
        // The transcriber wrote the label from the screenshot, with a full-width space and bracket.
        let t = Self.baseTranscription { $0[7] = .init(label: "膳食纖維　（自願標示者）", nutrient: "fibre",
            values: [Self.v("3.8", "公克"), Self.v("9.6", "公克")]) }
        let score = FreshSet.score(renamed, t)
        XCTAssertEqual(score.wrong, [], "matched by label against a row of any nutrient, with the same numbers")
        XCTAssertEqual(score.correctionBurden, 1, "an unrecognised cell never counts as reading fibre")
        XCTAssertEqual(FreshSet.normalisedLabel("Ｆｉｂｒｅ （自願標示）"), "fibre")
    }

    func testValuesOutsideTheTablesAreAcceptedAndNeverMatchByAccident() {
        let outside = Self.baseTranscription {
            $0[1] = .init(label: "蛋白質", nutrient: "protein", values: [T.Value(comparator: "=", number: "６.0", unit: "ｇ", outsideTable: true),
                                                                       T.Value(comparator: ">", number: "15.1", unit: "公克", outsideTable: true)])
        }
        XCTAssertEqual(FreshSet.problems(outside, expectedID: "S01"), [], "validate does not refuse values recorded verbatim")
        let unmarked = Self.baseTranscription { $0[1] = .init(label: "蛋白質", nutrient: "protein", values: [Self.v("6.0", "ｇ"), Self.v("15.1", "公克")]) }
        XCTAssertEqual(FreshSet.problems(unmarked, expectedID: "S01"), ["蛋白質: unit ｇ without outside_table"])
        // The reader bound 6.0 g and 15.1 g: both differ from what is printed, so both are wrong.
        XCTAssertEqual(FreshSet.score(run(SyntheticLabelTexts.base, Self.baseTranscription()), outside).wrong.count, 2)
        // A row not read is never wrong, whatever is printed.
        let noProtein = FreshSet.score(run(SyntheticLabelTexts.taiwan(SyntheticLabelTexts.rows.filter { !$0.hasPrefix("蛋白質") }), outside), outside)
        XCTAssertEqual(noProtein.wrong, [])
        let serving = Self.baseTranscription()
        let pieces = T(schema: serving.schema, labelID: "S01", servingSize: .init(number: "2", unit: "片", outsideTable: true),
                       servingsPerPack: serving.servingsPerPack, columns: serving.columns, rows: serving.rows, notes: [])
        XCTAssertEqual(FreshSet.problems(pieces, expectedID: "S01"), [])
    }

    func testAServingSizeNumberIsScoredWithoutACanonicalUnit() throws {
        let base = run(SyntheticLabelTexts.base, Self.baseTranscription())
        let noUnit = try mutate(base) { object in
            var candidate = object["candidate"] as! [String: Any]
            candidate["serving_size"] = ["printed_text": "每一份量 40 包", "decimal_text": "40", "unit": "包"]
            object["candidate"] = candidate
        }
        XCTAssertEqual(FreshSet.score(noUnit, Self.baseTranscription()).wrong, [])
        let other = Self.baseTranscription()
        let fifty = T(schema: other.schema, labelID: "S01", servingSize: .init(number: "50", unit: "公克"), servingsPerPack: other.servingsPerPack,
                      columns: other.columns, rows: other.rows, notes: [])
        XCTAssertEqual(FreshSet.score(noUnit, fifty).wrong, ["serving size read 40 "])
    }

    func testTwoColumnsWithTheSameBasisAreMatchedByPositionOrAreAmbiguous() {
        let base = Self.baseTranscription()
        let result = run(SyntheticLabelTexts.base, base)
        // The transcription prints three columns, two of them per 100 g: the reader's two columns
        // are not the transcription's three, so its per 100 g values cannot be placed.
        let three = T(schema: base.schema, labelID: "S01", servingSize: base.servingSize, servingsPerPack: base.servingsPerPack,
                      columns: base.columns + [.init(heading: "每100公克（沖泡後）", basis: "per_100g")],
                      rows: base.rows.map { .init(label: $0.label, nutrient: $0.nutrient, values: $0.values + [$0.values[1]]) }, notes: [])
        XCTAssertEqual(FreshSet.score(result, three).wrong.count, 9, "every per 100 g value is ambiguous, never firstIndex")
        // Two per 100 g columns read in full, with a printed reference-intake column on the label
        // only: positions are compared over amount columns, so the % column does not break the match.
        let twoPer100 = T(schema: base.schema, labelID: "S01", servingSize: base.servingSize, servingsPerPack: base.servingsPerPack,
                          columns: [.init(heading: "每100公克", basis: "per_100g"), .init(heading: "每100公克（沖泡後）", basis: "per_100g"),
                                    .init(heading: "每日參考值百分比", basis: "reference_intake")],
                          rows: base.rows.map { .init(label: $0.label, nutrient: $0.nutrient, values: [$0.values[0], $0.values[1], nil]) }, notes: [])
        let asPer100 = try! mutate(result) { object in
            var candidate = object["candidate"] as! [String: Any]
            candidate["headers"] = (candidate["headers"] as! [[String: Any]]).map { header in
                var header = header; header["basis"] = "per_100g"; return header
            }
            candidate["cells"] = (candidate["cells"] as! [[String: Any]]).map { cell in
                var cell = cell; cell["basis"] = "per_100g"; return cell
            }
            object["candidate"] = candidate
        }
        XCTAssertEqual(FreshSet.score(asPer100, twoPer100).wrong, [])
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
