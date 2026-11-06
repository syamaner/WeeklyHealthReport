import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import NutritionLabelParsing
import XCTest

/// Contract tests 2 to 6 of `docs/pasted-nutrition-label-uk-english-v1-p3.md`: the UK schemas,
/// the steps on a scratch folder, the run under `.ukDevelopment`, and the UK scorer's positive and
/// negative cases. Every text and value here is invented.
final class UKFreshSetScorerTests: XCTestCase {
    private typealias T = UKFreshSet.Transcription
    private struct Clock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) } }
    private let builder = UKFreshSet.builder(clock: Clock())

    private static func v(_ number: String, _ unit: String, _ comparator: String = "=") -> T.Value {
        T.Value(comparator: comparator, number: number, unit: unit)
    }
    private static let trace = T.Value(comparator: "=", number: "Trace", unit: "")

    /// A synthetic UK declaration: per 100 g and per serving, a split energy cell, a `Trace`
    /// sugars row the reader leaves unbound and a `less than` salt row.
    static let declaration = "Nutrition\nTypical values Per 100g Per 30g serving\nEnergy 1550kJ / 370kcal 465kJ / 111kcal\n"
        + "Fat 3.2g 1.0g\nof which saturates 1.1g 0.3g\nCarbohydrate 60g 18g\nof which sugars Trace Trace\nFibre 7.0g 2.1g\n"
        + "Protein 10g 3.0g\nSalt less than 0.5g less than 0.2g\n"
    /// A one-column declaration whose kcal sits on a continuation line, with a row the reader does not recognise.
    static let continuation = "Nutrition\nTypical values Per 100g\nEnergy 1000kJ\n(kcal) 240kcal\nFat 3.2g\nof which saturates 1.1g\n"
        + "Carbohydrate 60g\nof which sugars 5.0g\nFibre 7.0g\nProtein 10g\nSalt 0.6g\nVitamin C 12mg\n"
    /// The same table with no basis header, so the basis sheet would be shown.
    static let unheaded = "Serving size 30g\nEnergy 1000kJ/240kcal\nFat 3.2g\nof which saturates 1.1g\nCarbohydrate 60g\n"
        + "of which sugars 5.0g\nProtein 10g\nSalt 0.6g\n"
    static let unheadedTwo = "Serving size 30g\nEnergy 1000kJ 300kJ\nFat 3.2g 1.0g\nof which saturates 1.1g 0.3g\nCarbohydrate 60g 18g\n"
        + "of which sugars 5.0g 1.5g\nProtein 10g 3.0g\nSalt 0.6g 0.2g\n"

    private static func declarationTranscription(_ edit: (inout [T.Row]) -> Void = { _ in }) -> T {
        var rows: [T.Row] = [
            .init(label: "Energy", nutrient: "energy_kj", values: [v("1550", "kJ"), v("465", "kJ")]),
            .init(label: "Energy", nutrient: "energy_kcal", values: [v("370", "kcal"), v("111", "kcal")]),
            .init(label: "Fat", nutrient: "fat", values: [v("3.2", "g"), v("1.0", "g")]),
            .init(label: "of which saturates", nutrient: "saturates", values: [v("1.1", "g"), v("0.3", "g")]),
            .init(label: "Carbohydrate", nutrient: "carbohydrate", values: [v("60", "g"), v("18", "g")]),
            .init(label: "of which sugars", nutrient: "sugars", values: [trace, trace]),
            .init(label: "Fibre", nutrient: "fibre", values: [v("7.0", "g"), v("2.1", "g")]),
            .init(label: "Protein", nutrient: "protein", values: [v("10", "g"), v("3.0", "g")]),
            .init(label: "Salt", nutrient: "salt", values: [v("0.5", "g", "less than"), v("0.2", "g", "less than")]),
        ]
        edit(&rows)
        return T(schema: UKFreshSet.transcriptionSchema, labelID: "K01", panel: "uk_declaration", servingSize: .init(number: "30", unit: "g"),
                 servingsPerPack: nil, columns: [.init(heading: "Per 100g", basis: "per_100g"), .init(heading: "Per 30g serving", basis: "per_serving")],
                 rows: rows, notes: [])
    }

    private static func continuationTranscription(_ edit: (inout [T.Row]) -> Void = { _ in }) -> T {
        var rows: [T.Row] = [
            .init(label: "Energy", nutrient: "energy_kj", values: [v("1000", "kJ")]),
            .init(label: "(kcal)", nutrient: "energy_kcal", values: [v("240", "kcal")]),
            .init(label: "Fat", nutrient: "fat", values: [v("3.2", "g")]),
            .init(label: "of which saturates", nutrient: "saturates", values: [v("1.1", "g")]),
            .init(label: "Carbohydrate", nutrient: "carbohydrate", values: [v("60", "g")]),
            .init(label: "of which sugars", nutrient: "sugars", values: [v("5.0", "g")]),
            .init(label: "Fibre", nutrient: "fibre", values: [v("7.0", "g")]),
            .init(label: "Protein", nutrient: "protein", values: [v("10", "g")]),
            .init(label: "Salt", nutrient: "salt", values: [v("0.6", "g")]),
            .init(label: "Vitamin C", nutrient: "other", values: [v("12", "mg")]),
        ]
        edit(&rows)
        return T(schema: UKFreshSet.transcriptionSchema, labelID: "K02", panel: "uk_declaration", servingSize: nil, servingsPerPack: nil,
                 columns: [.init(heading: "Per 100g", basis: "per_100g")], rows: rows, notes: [])
    }

    private func run(_ text: String, _ t: T) -> UKFreshSet.RunResult {
        UKFreshSet.run(labelID: t.labelID, text: text, transcription: t) { try builder.choose($0, in: $1) }
    }

    /// Re-encodes a run result with a change to its cells, for scorer cases a synthetic text
    /// cannot produce (a marker bound, a cell under another row).
    private func mutate(_ r: UKFreshSet.RunResult, _ change: (inout [String: Any]) -> Void) throws -> UKFreshSet.RunResult {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        var candidate = object["candidate"] as! [String: Any]
        var cells = candidate["cells"] as! [[String: Any]]
        var wrapped: [String: Any] = ["cells": cells]
        change(&wrapped)
        cells = wrapped["cells"] as! [[String: Any]]
        candidate["cells"] = cells
        object["candidate"] = candidate
        return try JSONDecoder().decode(UKFreshSet.RunResult.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// Changes every cell `matching` with `edit`.
    private func editing(_ r: UKFreshSet.RunResult, where matching: @escaping ([String: Any]) -> Bool,
                         _ edit: @escaping (inout [String: Any]) -> Void) throws -> UKFreshSet.RunResult {
        try mutate(r) { object in
            object["cells"] = (object["cells"] as! [[String: Any]]).map { cell in
                var cell = cell
                if matching(cell) { edit(&cell) }
                return cell
            }
        }
    }

    /// Adds a copy of the first cell `matching`, changed by `edit`.
    private func adding(_ r: UKFreshSet.RunResult, from matching: @escaping ([String: Any]) -> Bool,
                        _ edit: @escaping (inout [String: Any]) -> Void) throws -> UKFreshSet.RunResult {
        try mutate(r) { object in
            var cells = object["cells"] as! [[String: Any]]
            var cell = cells.first(where: matching)!
            edit(&cell)
            cells.append(cell)
            object["cells"] = cells
        }
    }

    private static func nutrient(_ name: String, _ header: String? = nil) -> ([String: Any]) -> Bool {
        { cell in (cell["nutrient"] as? String) == name && header.map { (cell["header_id"] as? String) == $0 } != false }
    }

    // MARK: Test 2, schemas

    func testAUKTranscriptionWithMarkersAPanelAndASplitEnergyCellValidates() {
        let t = Self.declarationTranscription {
            $0[3] = .init(label: "of which saturates", nutrient: "saturates", values: [Self.v("-", ""), Self.v("—", "")])
            $0.append(.init(label: "Vitamin D", nutrient: "other", values: [Self.v("Tr", ""), T.Value(comparator: "=", number: "N/A", unit: "", outsideTable: true)]))
        }
        XCTAssertEqual(UKFreshSet.problems(t, expectedID: "K01"), [])
        XCTAssertEqual(UKFreshSet.problems(Self.continuationTranscription(), expectedID: "K02"), [])
        for panel in ["uk_declaration", "us_nutrition_facts", "other_english"] {
            let p = T(schema: t.schema, labelID: "K01", panel: panel, servingSize: t.servingSize, servingsPerPack: nil, columns: t.columns,
                      rows: t.rows, notes: [])
            XCTAssertEqual(UKFreshSet.problems(p, expectedID: "K01"), [], panel)
        }
        let unknown = T(schema: t.schema, labelID: "K01", panel: UKFreshSet.unknownPanel, servingSize: t.servingSize, servingsPerPack: nil,
                        columns: t.columns, rows: t.rows, notes: [])
        XCTAssertEqual(UKFreshSet.problems(unknown, expectedID: "K01"), ["panel"], "unknown is for development transcriptions only")
    }

    func testATaiwanSchemaFileIsRefusedByTheReleaseSteps() throws {
        let taiwan = FreshSet.Transcription(schema: FreshSet.transcriptionSchema, labelID: "K01", servingSize: nil, servingsPerPack: nil,
                                            columns: [.init(heading: "Per 100g", basis: "per_100g")],
                                            rows: [.init(label: "Fat", nutrient: "fat", values: [.init(comparator: "=", number: "3.2", unit: "g")])], notes: [])
        let data = try JSONEncoder().encode(taiwan)
        XCTAssertThrowsError(try UKFreshSet.transcription(data))
        // Even with a panel, the Taiwan schema string is refused.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["panel"] = "uk_declaration"
        XCTAssertThrowsError(try UKFreshSet.transcription(JSONSerialization.data(withJSONObject: object)))
        let root = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Self.continuation, data, to: root, id: "K01")
        XCTAssertThrowsError(try UKFreshSet.validateTranscriptions(root))
        _ = try UKFreshSet.seal(.text, root)
        XCTAssertThrowsError(try UKFreshSet.seal(.seal1, root), "seal 1 validates the UK schema")
    }

    func testValuesOutsideTheTablesNeedOutsideTable() {
        let t = Self.continuationTranscription {
            $0[2] = .init(label: "Fat", nutrient: "fat", values: [Self.v("3.2", "grams")])
            $0[9] = .init(label: "Vitamin C", nutrient: "other", values: [Self.v("N/A", "")])
            $0.append(.init(label: "Iron", nutrient: "other", values: [T.Value(comparator: "=", number: "Trace", unit: "", outsideTable: true)]))
        }
        let problems = UKFreshSet.problems(t, expectedID: "K02")
        XCTAssertTrue(problems.contains("Fat: unit grams without outside_table"), "\(problems)")
        XCTAssertTrue(problems.contains("Vitamin C: number N/A without outside_table"), "\(problems)")
        XCTAssertTrue(problems.contains("Iron: marker Trace with outside_table"), "markers are first-class values")
        let marked = Self.continuationTranscription {
            $0[2] = .init(label: "Fat", nutrient: "fat", values: [T.Value(comparator: "=", number: "3.2", unit: "grams", outsideTable: true)])
            $0[9] = .init(label: "Vitamin C", nutrient: "other", values: [T.Value(comparator: "=", number: "N/A", unit: "", outsideTable: true)])
        }
        XCTAssertEqual(UKFreshSet.problems(marked, expectedID: "K02"), [])
    }

    // MARK: Test 3, steps

    private func scratchFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("uk-fresh-set-\(UUID().uuidString)")
        let folder = try FreshSet.privateFolder(root.path)
        for name in ["texts", "transcription"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        return folder
    }

    private func write(_ text: String, _ transcription: Data, to root: URL, id: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent("texts/\(id).txt"))
        try transcription.write(to: root.appendingPathComponent("transcription/\(id).json"))
    }

    func testTheScratchFolderIsAcceptedAndACheckoutIsRefused() throws {
        XCTAssertNoThrow(try FreshSet.privateFolder(FileManager.default.temporaryDirectory.path))
        let checkout = FileManager.default.temporaryDirectory.appendingPathComponent("checkout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: checkout) }
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent("uk/set"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try FreshSet.privateFolder(checkout.appendingPathComponent("uk/set").path))
        XCTAssertThrowsError(try FreshSet.privateFolder("relative/uk"))
    }

    func testSealsAreOrderedAndAChangedTextOrTranscriptionVoidsTheRunAndTheScore() throws {
        let root = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let encoder = JSONEncoder()
        try write(Self.continuation, try encoder.encode(Self.continuationTranscription()), to: root, id: "K02")
        XCTAssertThrowsError(try UKFreshSet.seal(.seal1, root), "the text seal comes first")
        XCTAssertThrowsError(try UKFreshSet.runAll(root, commit: "c"), "no run before seal 2")
        _ = try UKFreshSet.seal(.text, root)
        XCTAssertThrowsError(try UKFreshSet.seal(.text, root), "a seal is never replaced")
        XCTAssertThrowsError(try UKFreshSet.seal(.seal2, root), "seal 1 comes before seal 2")
        _ = try UKFreshSet.seal(.seal1, root)
        _ = try UKFreshSet.seal(.seal2, root)
        XCTAssertThrowsError(try UKFreshSet.seal(.seal2, root), "a seal is never replaced")
        let seals = try String(contentsOf: root.appendingPathComponent("seals.txt"), encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(seals.map { $0.split(separator: " ")[0] }, ["text", "seal1", "seal2"])
        XCTAssertTrue(seals.allSatisfy { $0.split(separator: " ").count == 4 }, "<name> <sha256> <files> <UTC time>")
        XCTAssertEqual(FreshSet.seals(root)[.seal1], try FreshSet.current(.seal1, root).hash)

        XCTAssertEqual(try UKFreshSet.runAll(root, commit: "c"), 1)
        XCTAssertEqual(try UKFreshSet.runAll(root, commit: "c"), 0, "the one rerun covers only labels with no output")
        XCTAssertThrowsError(try UKFreshSet.runAll(root, commit: "c"), "a third attempt is refused")
        let log = try String(contentsOf: root.appendingPathComponent("run-log.txt"), encoding: .utf8)
        XCTAssertTrue(log.contains("commit=c attempt=1 pending=K02\nwrote K02\n"), log)
        XCTAssertTrue(log.contains("attempt=2 pending=\n"), log)
        let output = try JSONDecoder().decode(UKFreshSet.RunResult.self, from: Data(contentsOf: root.appendingPathComponent("run/K02.json")))
        XCTAssertEqual(output.schema, UKFreshSet.runSchema)
        XCTAssertEqual(output.format, LabelFormatInference.Outcome.uk.rawValue)
        // v2 P3 section 3: the run writes each label's set-aside file, the reader's own list.
        let setAside = try JSONDecoder().decode(UKFreshSet.SetAsideFile.self, from: Data(contentsOf: root.appendingPathComponent("set-aside/K02.json")))
        XCTAssertEqual(setAside, UKFreshSet.SetAsideFile(labelID: "K02", text: Self.continuation))
        XCTAssertEqual(setAside.schema, "uk-set-aside-v1")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("set-aside").path), ["K02.json"],
                       "one file per label read, and the rerun read none")

        let summary = try UKFreshSet.scoreAll(root)
        XCTAssertEqual(summary.overall.wrongValues, 0)
        XCTAssertTrue(summary.overall.passes)
        XCTAssertEqual(summary.byPanel["uk_declaration"]?.labels, 1)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("results/summary.json"))) as? [String: Any]
        XCTAssertNotNil(written?["wrongValues"], "the summary is flat, as FreshSet.Summary")
        XCTAssertNotNil(written?["by_panel"])

        // A changed transcription voids the score; a changed text voids the run and the score.
        let original = try Data(contentsOf: root.appendingPathComponent("transcription/K02.json"))
        try encoder.encode(Self.continuationTranscription { $0.removeLast() }).write(to: root.appendingPathComponent("transcription/K02.json"))
        XCTAssertThrowsError(try UKFreshSet.scoreAll(root))
        try original.write(to: root.appendingPathComponent("transcription/K02.json"))
        XCTAssertNoThrow(try UKFreshSet.scoreAll(root))
        try Data((Self.continuation + "\n").utf8).write(to: root.appendingPathComponent("texts/K02.txt"))
        XCTAssertThrowsError(try UKFreshSet.scoreAll(root))
        XCTAssertThrowsError(try FreshSet.requireSealed(root))
    }

    /// v2 P3 section 3: the set-aside file carries the reader's entries under `label_id`, and
    /// round-trips unchanged. Synthetic text only.
    func testTheSetAsideFileCarriesTheReadersEntries() throws {
        let text = ". Contains 3 Servings\nTypical values\tPer 100g\nEnergy\t1000kJ / 240kcal\nFat\t3.2g\nof which saturates\t1.1g\n"
            + "Carbohydrate\t30.0g\nof which sugars\t5.0g\nProtein\t6.0g\nSalt\t0.40g"
        let file = UKFreshSet.SetAsideFile(labelID: "K09", text: text)
        XCTAssertEqual(file.entries, UKEnglishLabelTextReader().setAside(text))
        XCTAssertEqual(file.entries.map(\.rule), ["S1"])
        let data = try JSONEncoder().encode(file)
        let keys = (try JSONSerialization.jsonObject(with: data) as? [String: Any]).map { Set($0.keys) }
        XCTAssertEqual(keys, ["schema", "label_id", "entries"])
        XCTAssertEqual(try JSONDecoder().decode(UKFreshSet.SetAsideFile.self, from: data), file)
    }

    /// v2 P3 section 3: the set-aside file describes the same read as the run. Each S2 entry that
    /// holds a value is one `uk_set_aside` unread row of the reading, in order. Synthetic text only.
    func testSetAsideEntriesMatchTheReadingsUnreadRows() throws {
        let text = ["Typical values\tPer 100g\tPer 30g serving", "Energy\t1500kJ / 360kcal\t450kJ / 108kcal", "Fat\t12.0g\t3.6g",
                    "of which saturates\t4.0g\t1.2g", "Carbohydrate\t50.0g\t15.0g", "of which sugars\t20.0g\t6.0g", "Protein\t8.0g\t2.4g",
                    "Salt\t0.50g\t0.15g", "Vitamins and Minerals", "Vitamin C\t35mg\t10.5mg", "Iron\t4.5mg\t1.4mg",
                    "*NRV = Nutrient Reference Value"].joined(separator: "\n")
        let file = UKFreshSet.SetAsideFile(labelID: "K10", text: text)
        let unread = UKEnglishLabelTextReader().read(text, textSHA256: "h", assertedBases: nil).unreadRows
            .filter { $0.reason == "uk_set_aside" }.map(\.printedLabel)
        XCTAssertEqual(unread, ["Vitamin C", "Iron"])
        let valued = file.entries.filter { $0.rule == "S2" && $0.text.contains(where: \.isNumber) && $0.text.first?.isLetter == true }
        XCTAssertEqual(valued.map { $0.text.components(separatedBy: "\t")[0] }, unread)
    }

    func testARunOnChangedTextsOrOutputsTheLogDoesNotAccountForIsRefused() throws {
        let root = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Self.continuation, try JSONEncoder().encode(Self.continuationTranscription()), to: root, id: "K02")
        for seal in UKFreshSet.Seal.allCases { _ = try UKFreshSet.seal(seal, root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("run"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("run/K02.json"))
        XCTAssertThrowsError(try UKFreshSet.runAll(root, commit: "c"), "an output the log does not account for")
        try FileManager.default.removeItem(at: root.appendingPathComponent("run/K02.json"))
        try Data((Self.continuation + "Iron 1mg\n").utf8).write(to: root.appendingPathComponent("texts/K02.txt"))
        XCTAssertThrowsError(try UKFreshSet.runAll(root, commit: "c"), "texts that differ from the text seal")
    }

    // MARK: Test 4, the run

    func testASyntheticDeclarationIsUsableUnderTheUKPolicy() {
        let t = Self.declarationTranscription()
        let result = run(Self.declaration, t)
        XCTAssertEqual(result.outcome, "usable")
        XCTAssertEqual(result.schema, UKFreshSet.runSchema)
        XCTAssertEqual(result.format, LabelFormatInference.Outcome.uk.rawValue)
        let score = UKFreshSet.score(result, t)
        XCTAssertEqual(score.score.wrong, [])
        XCTAssertEqual(score.panel, "uk_declaration")
        XCTAssertEqual(score.format, LabelFormatInference.Outcome.uk.rawValue)
    }

    func testTheBasisComesFromTheTranscription() {
        func transcription(_ bases: [String?]) -> T {
            T(schema: UKFreshSet.transcriptionSchema, labelID: "K03", panel: "uk_declaration", servingSize: .init(number: "30", unit: "g"),
              servingsPerPack: nil, columns: bases.map { .init(heading: nil, basis: $0) },
              rows: [.init(label: "Fat", nutrient: "fat", values: bases.map { _ in Self.v("3.2", "g") })], notes: [])
        }
        let chosen = run(Self.unheaded, transcription(["per_100g"]))
        XCTAssertEqual(chosen.outcome, "usable")
        XCTAssertEqual(chosen.choice?.arrangement, "per_100g")
        XCTAssertEqual(chosen.candidate?.headers.map(\.basis), ["per_100g"])
        let serving = run(Self.unheaded, transcription(["per_serving"]))
        XCTAssertEqual(serving.candidate?.headers.map(\.basis), ["per_serving"])
        XCTAssertEqual(run(Self.unheaded, transcription([nil])).declineCodes, [FreshSet.basisNotSure])
        // Two columns in an order the sheet never offers: not offered, so declined.
        let notOffered = run(Self.unheadedTwo, transcription(["per_100g", "per_serving"]))
        XCTAssertEqual(notOffered.declineCodes, [FreshSet.basisNotOffered])
        XCTAssertEqual(notOffered.choice?.arrangement, "per_100g,per_serving")
    }

    func testTheHarnessBuilderUsesTheUKPolicyAndBuildsNoManifest() throws {
        let policy = Mirror(reflecting: builder).children.first { $0.label == "policy" }?.value as? PastedLabelReadingPolicy
        XCTAssertEqual(policy, .ukDevelopment)
        XCTAssertEqual(Mirror(reflecting: UKFreshSet.reader).children.first { $0.label == "policy" }?.value as? PastedLabelReadingPolicy,
                       .ukDevelopment)
        guard case let .usable(review) = UKFreshSet.reader.read(Self.declaration) else { return XCTFail("no UK review") }
        XCTAssertThrowsError(try builder.manifest(review, details: .init(name: "Synthetic oat bar"), corrections: [])) { error in
            XCTAssertEqual(error as? PastedLabelConfirmationError, .identityNotRecordable(PastedLabelBasisStateV3.version))
        }
    }

    // MARK: Test 5, scorer positives

    func testLessThanMatchesTheReadersComparator() {
        XCTAssertEqual(UKFreshSet.comparator("less than"), "<")
        XCTAssertEqual(UKFreshSet.comparator("Less Than"), "<")
        XCTAssertEqual(UKFreshSet.comparator("≤"), "<=")
        XCTAssertNil(UKFreshSet.comparator("under"))
        let t = Self.declarationTranscription()
        let result = run(Self.declaration, t)
        XCTAssertEqual(result.candidate?.cells.filter { $0.nutrient == "salt" }.map(\.comparator), ["<", "<"])
        XCTAssertEqual(UKFreshSet.score(result, t).score.wrong, [])
    }

    func testATraceUnboundOrBoundAsAMarkerIsNotWrong() throws {
        let t = Self.declarationTranscription()
        let result = run(Self.declaration, t)
        XCTAssertFalse(result.candidate?.cells.contains { $0.nutrient == "sugars" } ?? true, "the reader leaves Trace unbound")
        XCTAssertEqual(UKFreshSet.score(result, t).score.wrong, [])
        for marker in ["Trace", "trace", "Tr", "-", "—"] {
            let bound = try adding(result, from: Self.nutrient("saturates", "header_1")) {
                $0["nutrient"] = "sugars"; $0["printed_label"] = "of which sugars"; $0["decimal_text"] = marker
                $0["unit"] = ""; $0["canonical_unit"] = ""
            }
            XCTAssertEqual(UKFreshSet.score(bound, t).score.wrong, [], marker)
        }
    }

    func testEveryDashPairIsOneMarker() {
        for (printed, read) in [("-", "—"), ("–", "-"), ("−", "—"), ("—", "–"), ("Trace", "Tr")] {
            XCTAssertTrue(UKFreshSet.same(comparator: "=", number: read, unit: "", readLabel: "x", as: Self.v(printed, ""), printedLabel: "x"),
                          "\(printed) / \(read)")
        }
    }

    func testAP1MarkerRecordedWithOutsideTableScoresThroughTheDevelopmentDecoder() throws {
        let p1 = FreshSet.Transcription(
            schema: FreshSet.transcriptionSchema, labelID: "K02", servingSize: nil, servingsPerPack: nil,
            columns: [.init(heading: "Per 100g", basis: "per_100g")],
            rows: Self.continuationTranscription().rows.map { row in
                row.nutrient == "sugars"
                    ? .init(label: row.label, nutrient: row.nutrient, values: [.init(comparator: "=", number: "Trace", unit: "", outsideTable: true)])
                    : row
            }, notes: [])
        let data = try JSONEncoder().encode(p1)
        XCTAssertThrowsError(try UKFreshSet.transcription(data), "the release steps refuse it")
        let t = try UKFreshSet.developmentTranscription(data)
        XCTAssertEqual(t.panel, UKFreshSet.unknownPanel)
        XCTAssertEqual(t.rows.first { $0.nutrient == "sugars" }?.values, [Self.trace], "moved to the first-class form")
        XCTAssertEqual(try UKFreshSet.developmentTranscription(JSONEncoder().encode(Self.continuationTranscription())),
                       Self.continuationTranscription(), "a UK file is returned as it is")
        let result = run(Self.continuation.replacingOccurrences(of: "of which sugars 5.0g", with: "of which sugars Tr"), t)
        XCTAssertEqual(UKFreshSet.score(result, t).score.wrong, [])
        // Through the Taiwan scorer, a different marker of the class would be wrong; here it is not.
        let bound = try editing(result, where: Self.nutrient("saturates")) {
            $0["nutrient"] = "sugars"; $0["printed_label"] = "of which sugars"; $0["decimal_text"] = "Tr"; $0["canonical_unit"] = ""
        }
        let saturatesFree = UKFreshSet.Transcription(schema: t.schema, labelID: t.labelID, panel: t.panel, servingSize: nil, servingsPerPack: nil,
                                                     columns: t.columns, rows: t.rows.filter { $0.nutrient != "saturates" }, notes: [])
        XCTAssertEqual(UKFreshSet.score(bound, saturatesFree).score.wrong, [])
    }

    func testLabelNormalisation() {
        XCTAssertEqual(UKFreshSet.normalisedLabel("(kcal)"), "kcal")
        XCTAssertEqual(UKFreshSet.normalisedLabel("Energy (kJ)"), "energy")
        XCTAssertEqual(UKFreshSet.normalisedLabel("of which — sugars"), "sugars")
        XCTAssertEqual(UKFreshSet.normalisedLabel("(of which sugars)"), "sugars")
        XCTAssertEqual(UKFreshSet.normalisedLabel("Sugars ("), "sugars")
        XCTAssertEqual(UKFreshSet.normalisedLabel("_ Of Which Saturates:"), "saturates")
        XCTAssertEqual(UKFreshSet.normalisedLabel("– polyols (g)"), "polyols")
        XCTAssertEqual(UKFreshSet.normalisedLabel("Sugars (自願標示)"), "sugars自願標示", "the Taiwan step does not apply")
        XCTAssertEqual(UKFreshSet.normalisedLabel("of which of which sugars"), "ofwhichsugars", "one leading of which only")
    }

    func testAContinuationLineAndOtherPrintedLabelsMatchTheirRows() throws {
        let t = Self.continuationTranscription()
        let result = run(Self.continuation, t)
        XCTAssertEqual(result.candidate?.cells.first { $0.printedLabel == "(kcal)" }?.nutrient, "unrecognised")
        let score = UKFreshSet.score(result, t)
        XCTAssertEqual(score.score.wrong, [])
        XCTAssertEqual(score.score.calculatedDiscrepancies.count, 1, "the calculated kcal beside the printed (kcal) row is reported")
        // A reader label `of which — sugars`, `(of which sugars)` or cut at `(` matches the row as printed.
        for label in ["of which — sugars", "(of which sugars)", "of which sugars ("] {
            let unrecognised = try editing(result, where: Self.nutrient("sugars")) { $0["nutrient"] = "unrecognised"; $0["printed_label"] = label }
            XCTAssertEqual(UKFreshSet.score(unrecognised, t).score.wrong, [], label)
        }
    }

    func testAKilojouleAndKilocalorieCellRecordedAsTwoRowsMatchesByUnit() throws {
        let t = Self.declarationTranscription()
        let result = try editing(run(Self.declaration, t), where: { ($0["nutrient"] as? String)?.hasPrefix("energy") == true }) {
            $0["nutrient"] = "unrecognised"
        }
        XCTAssertEqual(result.candidate?.cells.filter { $0.nutrient == "unrecognised" }.count, 4)
        XCTAssertEqual(UKFreshSet.score(result, t).score.wrong, [])
    }

    // MARK: Test 6, scorer negatives

    func testATraceBoundAsANumberIsWrong() throws {
        let t = Self.declarationTranscription()
        for number in ["0", "0.1"] {
            let bound = try adding(run(Self.declaration, t), from: Self.nutrient("saturates", "header_1")) {
                $0["nutrient"] = "sugars"; $0["printed_label"] = "of which sugars"; $0["decimal_text"] = number
            }
            XCTAssertEqual(UKFreshSet.score(bound, t).score.wrong.count, 1, number)
        }
    }

    func testAValueBoundToTheWrongRowColumnOrUnitIsWrong() throws {
        let t = Self.continuationTranscription()
        let result = run(Self.continuation, t)
        // A sugars value bound to the saturates row.
        let misbound = try editing(result, where: Self.nutrient("sugars")) { $0["nutrient"] = "saturates" }
        XCTAssertEqual(UKFreshSet.score(misbound, t).score.wrong.count, 1)
        // A kcal value matched against a kJ-only label.
        let kJOnly = Self.continuationTranscription { $0.remove(at: 1) }
        let kcalOnEnergy = try editing(result, where: { ($0["printed_label"] as? String) == "(kcal)" }) { $0["printed_label"] = "Energy" }
        XCTAssertEqual(UKFreshSet.score(kcalOnEnergy, kJOnly).score.wrong.count, 1)
        // A kcal cell under a label naming kJ, where the rows name their units: the unit the label
        // names must agree with the cell, so disambiguation by unit cannot hide the mismatch.
        let namedRows = Self.continuationTranscription {
            $0[0] = .init(label: "Energy (kJ)", nutrient: "energy_kj", values: [Self.v("1000", "kJ")])
            $0[1] = .init(label: "Energy (kcal)", nutrient: "energy_kcal", values: [Self.v("240", "kcal")])
        }
        let named = try editing(result, where: { ($0["printed_label"] as? String) == "(kcal)" }) { $0["printed_label"] = "Energy (kJ)" }
        XCTAssertEqual(UKFreshSet.score(named, namedRows).score.wrong.count, 1)
        let agreeing = try editing(result, where: { ($0["printed_label"] as? String) == "(kcal)" }) { $0["printed_label"] = "Energy (kcal)" }
        XCTAssertEqual(UKFreshSet.score(agreeing, namedRows).score.wrong, [])
        // The right number with the wrong unit.
        let wrongUnit = Self.continuationTranscription { $0[9] = .init(label: "Vitamin C", nutrient: "other", values: [Self.v("12", "µg")]) }
        XCTAssertEqual(UKFreshSet.score(result, wrongUnit).score.wrong.count, 1)
        // A value under the wrong column basis.
        let declaration = Self.declarationTranscription()
        let column = try editing(run(Self.declaration, declaration), where: Self.nutrient("protein", "header_1")) { $0["header_id"] = "header_2" }
        XCTAssertEqual(UKFreshSet.score(column, declaration).score.wrong.count, 1)
    }

    func testRowsTheUnitCannotTellApartAreWrong() throws {
        let t = Self.declarationTranscription()
        let energy = try editing(run(Self.declaration, t), where: { ($0["nutrient"] as? String)?.hasPrefix("energy") == true }) {
            $0["nutrient"] = "unrecognised"
        }
        // Two rows with the same normalised label and unit.
        let sameUnit = Self.declarationTranscription { $0[1] = .init(label: "Energy", nutrient: "energy_kcal", values: [Self.v("370", "kJ"), Self.v("111", "kJ")]) }
        XCTAssertEqual(UKFreshSet.score(energy, sameUnit).score.wrong.count, 4)
        // On a kJ/kcal pair, a kJ-unit cell carrying the kcal number.
        let swapped = try editing(energy, where: { ($0["canonical_unit"] as? String) == "kJ" && ($0["header_id"] as? String) == "header_1" }) {
            $0["decimal_text"] = "370"
        }
        XCTAssertEqual(UKFreshSet.score(swapped, t).score.wrong.count, 1)
        // A top-level Sugars and an `of which sugars` row in the same unit, recognised or not.
        let continuation = run(Self.continuation, Self.continuationTranscription())
        let twoSugars = Self.continuationTranscription { $0.insert(.init(label: "Sugars", nutrient: "sugars", values: [Self.v("5.0", "g")]), at: 5) }
        XCTAssertEqual(UKFreshSet.score(continuation, twoSugars).score.wrong.count, 1)
        let unrecognised = try editing(continuation, where: Self.nutrient("sugars")) { $0["nutrient"] = "unrecognised"; $0["printed_label"] = "Sugars" }
        XCTAssertEqual(UKFreshSet.score(unrecognised, twoSugars).score.wrong.count, 1)
    }

    func testALabelThatNormalisesToNothingNeverMatches() throws {
        XCTAssertEqual(UKFreshSet.normalisedLabel(" — _ : "), "")
        let t = Self.continuationTranscription { $0[9] = .init(label: "–", nutrient: "other", values: [Self.v("12", "mg")]) }
        let blank = try editing(run(Self.continuation, t), where: { ($0["printed_label"] as? String) == "Vitamin C" }) { $0["printed_label"] = "—" }
        XCTAssertEqual(UKFreshSet.score(blank, t).score.wrong.count, 1)
    }

    // MARK: The unit table and the summary

    func testTheUnitTableIsFixed() {
        XCTAssertEqual(UKFreshSet.units.count, 14)
        for (printed, canonical) in [("kJ", "kJ"), ("KJ", "kJ"), ("kcal", "kcal"), ("Kcal", "kcal"), ("cal", "cal"), ("Cal", "cal"),
                                     ("g", "g"), ("gm", "g"), ("gms", "g"), ("gr", "g"), ("grs", "g"), ("G", "g"), ("mg", "mg"),
                                     ("µg", "µg"), ("μg", "µg"), ("mcg", "µg"), ("ml", "ml"), ("mL", "ml"), ("%", "%"), ("g/gm", "g")] {
            XCTAssertEqual(UKFreshSet.unit(printed), canonical, printed)
        }
        for printed in ["kJ/kcal", "grams", "大卡", "cc", "kilocalories", "l"] { XCTAssertNil(UKFreshSet.unit(printed), printed) }
    }

    func testTheSummaryCountsEachPanelOnItsOwn() throws {
        func score(_ id: String, _ panel: String, wrong: [String] = []) -> UKFreshSet.Score {
            .init(score: .init(labelID: id, outcome: "usable", declineCodes: [], valuesChecked: 10, wrong: wrong, correctionBurden: 0,
                               unreadRows: 0, basisChoice: false, flags: [], warningCodes: []), panel: panel, format: nil)
        }
        let summary = UKFreshSet.summary([score("A", "uk_declaration"), score("B", "uk_declaration"), score("C", "us_nutrition_facts", wrong: ["x"])])
        XCTAssertEqual(summary.overall.labels, 3)
        XCTAssertEqual(summary.overall.wrongValues, 1)
        XCTAssertEqual(summary.byPanel["uk_declaration"]?.labels, 2)
        XCTAssertEqual(summary.byPanel["uk_declaration"]?.wrongValues, 0)
        XCTAssertEqual(summary.byPanel["us_nutrition_facts"]?.wrongValues, 1)
        XCTAssertNil(summary.byPanel["other_english"])
        XCTAssertEqual(try JSONDecoder().decode(UKFreshSet.Summary.self, from: JSONEncoder().encode(summary)), summary)
        let one = score("A", "other_english")
        XCTAssertEqual(try JSONDecoder().decode(UKFreshSet.Score.self, from: JSONEncoder().encode(one)), one)
    }
}
