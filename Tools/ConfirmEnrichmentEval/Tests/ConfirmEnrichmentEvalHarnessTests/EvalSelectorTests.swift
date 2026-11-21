import ConfirmEnrichmentEvalCore
import ConfirmEnrichmentEvalHarness
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import XCTest

/// The deterministic case selection (`select`, docs/confirm-enrichment-openrouter-v1-phase.md section 9).
/// Synthetic export lines only, written into a temporary folder; never real export data.
final class EvalSelectorTests: XCTestCase {
    static let fixedNow = Date(timeIntervalSince1970: 1_795_000_000)

    /// One synthetic product in the modern `nutrition.input_sets` form the app's projection reads.
    static func product(_ n: Int, country: String, fortified: Bool, complete: Bool = true) -> [String: Any] {
        var nutrients: [String: Any] = [
            "energy-kcal": ["value": 100 + n % 50, "unit": "kcal"], "fat": ["value": 3, "unit": "g"],
            "saturated-fat": ["value": 1, "unit": "g"], "carbohydrates": ["value": 12, "unit": "g"],
            "proteins": ["value": 4, "unit": "g"], "sodium": ["value": 0.2, "unit": "g"],
        ]
        if complete { nutrients["sugars"] = ["value": 5, "unit": "g"] }
        var product: [String: Any] = [
            "code": String(format: "50%011d", n), "product_name": "Synthetic product \(n)", "brands": "Syntheticbrand\(n)",
            "quantity": "400 g", "countries_tags": [country],
            "nutrition": ["input_sets": [["source": "packaging", "per": "100g", "preparation": "as_sold", "nutrients": nutrients]]],
        ]
        if fortified { product["vitamins_tags"] = ["en:vitamin-d"] }
        return product
    }

    /// An export of `uk` UK and `taiwan` Taiwan eligible products, every sixth fortified, plus lines that
    /// must never be chosen: incomplete panels, another country and a broken line.
    static func export(uk: Int, taiwan: Int, in folder: URL, gzip: Bool = false) throws -> URL {
        var lines: [String] = []
        func add(_ product: [String: Any]) throws {
            lines.append(String(decoding: try JSONSerialization.data(withJSONObject: product, options: [.sortedKeys]), as: UTF8.self))
        }
        for n in 0..<uk { try add(product(n, country: "en:united-kingdom", fortified: n % 6 == 0)) }
        for n in 0..<taiwan { try add(product(1_000 + n, country: "en:taiwan", fortified: n % 6 == 0)) }
        for n in 0..<10 { try add(product(5_000 + n, country: "en:united-kingdom", fortified: true, complete: false)) }
        for n in 0..<10 { try add(product(6_000 + n, country: "en:france", fortified: true)) }
        lines.append("{not json en:united-kingdom")
        let url = folder.appendingPathComponent("export.jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        guard gzip else { return url }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-kf", url.path]
        try process.run()
        process.waitUntilExit()
        return folder.appendingPathComponent("export.jsonl.gz")
    }

    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ce1-select-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A fixed, synthetic row list (20 per table), so most tests need no table search; the candidate
    /// test below harvests the real tables once.
    static let syntheticRows: [EvalSelection.Row] = EvalCase.Table.allCases.flatMap { table in
        (0..<25).map { EvalSelection.Row(table: table, search: "word\($0 % 5)", recordID: "\(table.rawValue):row-\($0)") }
    }

    func selector() -> EvalSelector { EvalSelector(now: { Self.fixedNow }, rows: { Self.syntheticRows }) }

    func list(_ folder: URL, _ name: String) throws -> EvalCaseList {
        try EvalCaseList.decode(try Data(contentsOf: folder.appendingPathComponent(name)))
    }

    // MARK: The draw

    func testASeededRunIsDeterministicWithNoOverlapAndTheMinimums() throws {
        let work = try folder()
        let export = try Self.export(uk: 80, taiwan: 70, in: work)
        let first = work.appendingPathComponent("first"), second = work.appendingPathComponent("second")
        let lines = selector().select(export: export, privateFolder: first, seed: 42)
        XCTAssertFalse(lines.contains { $0.hasPrefix("stop ") }, "\(lines)")
        _ = selector().select(export: export, privateFolder: second, seed: 42)
        for name in [EvalSelector.developmentFile, EvalSelector.sealedFile] {
            XCTAssertEqual(try Data(contentsOf: first.appendingPathComponent(name)), try Data(contentsOf: second.appendingPathComponent(name)),
                           "\(name): the same seed gives the same set")
        }
        let development = try list(first, EvalSelector.developmentFile), sealed = try list(first, EvalSelector.sealedFile)
        for set in [development, sealed] {
            let products = set.cases.filter { $0.kind == .openFoodFacts }
            XCTAssertEqual(products.count, EvalSelection.productsPerSet)
            let codes = products.compactMap { $0.record }.map { String($0.dropFirst("records/".count).dropLast(".json".count)) }
            XCTAssertEqual(codes.filter { $0 < "5000000001000" }.count, 30, "30 UK")
            XCTAssertEqual(codes.filter { $0 >= "5000000001000" && $0 < "5000000002000" }.count, 30, "30 Taiwan")
            XCTAssertFalse(codes.contains { $0 >= "5000000005000" }, "never an incomplete panel or another country")
            let rows = set.cases.filter { $0.kind == .bundledRow }
            for table in EvalCase.Table.allCases { XCTAssertEqual(rows.filter { $0.table == table }.count, EvalSelection.rowsPerTablePerSet) }
        }
        XCTAssertTrue(Set(development.cases.compactMap(\.record)).isDisjoint(with: sealed.cases.compactMap(\.record)), "no product in both sets")
        XCTAssertTrue(Set(development.cases.compactMap(\.recordID)).isDisjoint(with: sealed.cases.compactMap(\.recordID)), "no row in both sets")
        let fortifiedLine = try XCTUnwrap(lines.first { $0.hasPrefix("selected development") })
        let fortified = try XCTUnwrap(Int(fortifiedLine.components(separatedBy: "fortified ")[1].prefix { $0.isNumber }))
        XCTAssertGreaterThanOrEqual(fortified, EvalSelection.minimumFortifiedPerSet)
        let other = work.appendingPathComponent("other")
        _ = selector().select(export: export, privateFolder: other, seed: 43)
        XCTAssertNotEqual(try Data(contentsOf: first.appendingPathComponent(EvalSelector.developmentFile)),
                          try Data(contentsOf: other.appendingPathComponent(EvalSelector.developmentFile)), "another seed, another set")
        XCTAssertEqual(try String(contentsOf: first.appendingPathComponent(EvalSelector.seedFile), encoding: .utf8), "42\n")
    }

    func testAGzippedExportGivesTheSameSetsAsThePlainOne() throws {
        let work = try folder()
        let plain = try Self.export(uk: 70, taiwan: 70, in: work)
        let zipped = try Self.export(uk: 70, taiwan: 70, in: work, gzip: true)
        let a = work.appendingPathComponent("a"), b = work.appendingPathComponent("b")
        _ = selector().select(export: plain, privateFolder: a, seed: 7)
        _ = selector().select(export: zipped, privateFolder: b, seed: 7)
        XCTAssertEqual(try Data(contentsOf: a.appendingPathComponent(EvalSelector.sealedFile)),
                       try Data(contentsOf: b.appendingPathComponent(EvalSelector.sealedFile)))
    }

    func testAShortCountryIsFilledFromTheOther() throws {
        let work = try folder()
        let export = try Self.export(uk: 110, taiwan: 20, in: work)
        let out = work.appendingPathComponent("out")
        let lines = selector().select(export: export, privateFolder: out, seed: 3)
        XCTAssertFalse(lines.contains { $0.hasPrefix("stop ") }, "\(lines)")
        let development = try list(out, EvalSelector.developmentFile)
        XCTAssertEqual(development.cases.filter { $0.kind == .openFoodFacts }.count, 60)
    }

    // MARK: Stops write nothing

    func testATooSmallPoolStopsAndWritesNothing() throws {
        let work = try folder()
        let export = try Self.export(uk: 30, taiwan: 30, in: work)
        let out = work.appendingPathComponent("out")
        let lines = selector().select(export: export, privateFolder: out, seed: 1)
        XCTAssertEqual(lines.last, "stop pool_too_small")
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "nothing is written")
    }

    func testTooFewFortifiedStopsAndWritesNothing() throws {
        let work = try folder()
        var lines: [String] = []
        for n in 0..<130 {
            lines.append(String(decoding: try JSONSerialization.data(withJSONObject: Self.product(n, country: "en:united-kingdom", fortified: n < 10),
                                                                     options: [.sortedKeys]), as: UTF8.self))
        }
        let export = work.appendingPathComponent("export.jsonl")
        try Data(lines.joined(separator: "\n").utf8).write(to: export)
        let out = work.appendingPathComponent("out")
        XCTAssertEqual(selector().select(export: export, privateFolder: out, seed: 1).last, "stop pool_too_few_fortified")
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testExistingCaseListsAreNeverOverwritten() throws {
        let work = try folder()
        let export = try Self.export(uk: 70, taiwan: 70, in: work)
        let out = work.appendingPathComponent("out")
        _ = selector().select(export: export, privateFolder: out, seed: 5)
        let before = try Data(contentsOf: out.appendingPathComponent(EvalSelector.developmentFile))
        XCTAssertEqual(selector().select(export: export, privateFolder: out, seed: 6), ["stop case_lists_exist"])
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent(EvalSelector.developmentFile)), before)
    }

    func testAPrivateFolderInsideAGitWorkTreeIsRefused() throws {
        let work = try folder()
        let repo = work.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        git.arguments = ["git", "-C", repo.path, "init", "-q"]
        try git.run()
        git.waitUntilExit()
        XCTAssertTrue(EvalWorkTree.contains(repo.appendingPathComponent("private/not-yet")))
        XCTAssertFalse(EvalWorkTree.contains(work.appendingPathComponent("outside")))
    }

    // MARK: G11 and the written lists

    func testTheConsoleHoldsNoNameBrandOrBarcode() throws {
        let work = try folder()
        let export = try Self.export(uk: 70, taiwan: 70, in: work)
        let lines = selector().select(export: export, privateFolder: work.appendingPathComponent("out"), seed: 9)
        let output = lines.joined(separator: "\n")
        XCTAssertFalse(output.contains("Synthetic"), "no name")
        XCTAssertFalse(output.contains("Syntheticbrand"), "no brand")
        XCTAssertFalse(output.contains("500000000"), "no barcode")
        XCTAssertEqual(lines.filter { $0.hasPrefix("manifest ") }.count, 2)
        for line in lines { XCTAssertTrue(line.hasPrefix("pool ") || line.hasPrefix("selected ") || line.hasPrefix("manifest "), line) }
    }

    func testTheWrittenListsBuildTheAppsCandidatesAndTheReviewSheetListsTheDevelopmentProducts() throws {
        let work = try folder()
        let export = try Self.export(uk: 70, taiwan: 70, in: work)
        let out = work.appendingPathComponent("out")
        let lines = EvalSelector(now: { Self.fixedNow }).select(export: export, privateFolder: out, seed: 11)
        XCTAssertFalse(lines.contains { $0.hasPrefix("stop ") }, "\(lines)")
        let development = try list(out, EvalSelector.developmentFile)
        let candidates = EvalCandidates()
        for evalCase in development.cases {
            let state = try candidates.state(for: evalCase, privateFolder: out)
            if evalCase.kind == .bundledRow {
                XCTAssertEqual(state.selectedCandidate.candidate.recordID.value, evalCase.recordID, "the app search's own row")
            }
        }
        let sheet = try String(contentsOf: out.appendingPathComponent(EvalSelector.reviewSheetFile), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        XCTAssertTrue(sheet[0].hasPrefix("# fortified_by_rule"))
        XCTAssertTrue(sheet[1].contains("fortification (unfortified|fortified|unknown)"))
        XCTAssertEqual(sheet.count, 2 + EvalSelection.productsPerSet, "one row per development product, none for the sealed set")
        let firstHash = try EvalHashes.hash(development.cases[0])
        XCTAssertTrue(sheet[2].hasPrefix("\"\(firstHash)\""))
    }

    func testTheFortifiedRuleReadsTheVitaminAndMineralTags() {
        XCTAssertTrue(EvalSelector.fortified(["vitamins_tags": ["en:vitamin-d"]]))
        XCTAssertTrue(EvalSelector.fortified(["minerals_tags": ["en:iron"]]))
        XCTAssertFalse(EvalSelector.fortified(["vitamins_tags": [String](), "minerals_tags": [String]()]))
        XCTAssertFalse(EvalSelector.fortified([:]))
        XCTAssertEqual(EvalSelector.country(["countries_tags": ["en:taiwan"]]), .taiwan)
        XCTAssertNil(EvalSelector.country(["countries_tags": ["en:france"]]))
    }

    func testBothSetsKeepTheFortifiedMinimumWhenFortifiedProductsAreScarce() throws {
        // Exactly 16 fortified in a pool of 130: the development set's country fill must leave 8 for sealed.
        var pool: [EvalSelection.Product] = []
        for n in 0..<130 {
            pool.append(.init(code: String(format: "%013d", n), line: n + 1, country: n % 2 == 0 ? .unitedKingdom : .taiwan, fortified: n < 16))
        }
        for seed in UInt64(0)..<50 {
            var generator = EvalSelection.Generator(seed: seed)
            let draw = try EvalSelection.drawProducts(pool, generator: &generator)
            XCTAssertEqual(draw.development.filter(\.fortified).count, 8, "seed \(seed)")
            XCTAssertEqual(draw.sealed.filter(\.fortified).count, 8, "seed \(seed)")
            XCTAssertEqual(draw.sealed.count, EvalSelection.productsPerSet)
        }
    }

    func testOnlyADigitBarcodeIsEligibleSoNoCodeBecomesAPath() {
        let product = Self.product(1, country: "en:united-kingdom", fortified: false)
        XCTAssertNotNil(selector().eligibleForTesting(product))
        for code in ["../escape", "50/1", "", "12a"] {
            var bad = product
            bad["code"] = code
            XCTAssertNil(selector().eligibleForTesting(bad), code)
        }
    }

    func testAnySpreadsheetFormulaOpeningIsDefused() {
        XCTAssertEqual(EvalSelection.csvField("=HYPERLINK(1)"), "\"'=HYPERLINK(1)\"")
        XCTAssertEqual(EvalSelection.csvField("-1"), "\"'-1\"")
        XCTAssertEqual(EvalSelection.csvField("Oat \"milk\""), "\"Oat \"\"milk\"\"\"")
    }

    func testAnEarlierRecordsFolderStopsTheRun() throws {
        let work = try folder()
        let export = try Self.export(uk: 70, taiwan: 70, in: work)
        let out = work.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out.appendingPathComponent("records"), withIntermediateDirectories: true)
        XCTAssertEqual(selector().select(export: export, privateFolder: out, seed: 5), ["stop case_lists_exist"])
    }
}
