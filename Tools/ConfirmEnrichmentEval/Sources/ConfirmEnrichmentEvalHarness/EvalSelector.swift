import ConfirmEnrichmentEvalCore
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// `select` (docs/confirm-enrichment-openrouter-v1-phase.md section 9 and the owner-approved case-selection
/// paragraph of docs/privacy-and-egress.md): builds the development and sealed case lists from a downloaded
/// public Open Food Facts export and the app's own bundled tables, in the owner's private folder only.
///
/// 1. A first streaming pass over the export (`.jsonl`, or `.jsonl.gz` through `/usr/bin/gzip -dc`, line by
///    line with bounded memory) keeps the products tagged for the United Kingdom or Taiwan that the app's
///    own `OpenFoodFactsProductMapping.project` admits and whose declared panel is complete.
/// 2. The seeded draw (`EvalSelection`) picks both sets; the bundled rows come from each table's public
///    `search(_:)` over a fixed word list.
/// 3. A second streaming pass extracts only the chosen records.
/// 4. Only then is anything written: the two case lists, the records, the seed and the development
///    review sheet, staged and moved into place only when all of it is written. A stop writes nothing.
///
/// The returned lines hold counts, manifests and stop codes only: never a name, brand, barcode or any
/// record text (G11).
public struct EvalSelector: Sendable {
    /// The panel a product must declare: energy, fat, saturated fat, carbohydrate, sugars, protein and
    /// sodium. Sodium may instead be declared as salt in a legacy record, which the projection does not
    /// read as sodium.
    public static let completePanel: [NutrientKey] = [.energyConsumed, .fatTotal, .fatSaturated, .carbohydrates, .sugar, .protein, .sodium]
    static let countryTags: [(String, EvalSelection.Country)] = [("en:united-kingdom", .unitedKingdom), ("en:taiwan", .taiwan)]
    /// Fixed words for harvesting bundled rows, per table, so the harvest is reproducible and each table
    /// yields at least 20 unique rows (10 per set). The three national tables take general English food
    /// words; the bundled Ciqual corpus holds only cocoa and chocolate rows (29 records), so its words are
    /// those of its own names.
    public static let harvestWords: [EvalCase.Table: [String]] = [
        .cofid: generalWords, .usda: generalWords, .tfda: generalWords,
        .ciqual: ["chocolate", "milk", "cocoa", "dark", "biscuit", "cake", "nut", "almond", "hazelnut", "sugar"],
    ]
    static let generalWords = [
        "apple", "banana", "orange", "bread", "rice", "pasta", "noodles", "oats", "potato", "carrot", "cabbage", "onion",
        "tomato", "peas", "beans", "lentils", "tofu", "chicken", "beef", "pork", "lamb", "fish", "salmon", "egg",
        "milk", "cheese", "yoghurt", "butter", "nuts", "cake", "biscuit", "soup", "corn", "spinach", "mushroom",
    ]

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case exportUnreadable, caseListsExist, writeFailed, recordMissing
        public var description: String {
            switch self {
            case .exportUnreadable: "export_unreadable"
            case .caseListsExist: "case_lists_exist"
            case .writeFailed: "write_failed"
            case .recordMissing: "record_missing"
            }
        }
    }

    let candidates: EvalCandidates
    let now: @Sendable () -> Date
    /// The bundled rows to draw from; nil harvests them from the tables (tests inject a fixed list).
    let rows: (@Sendable () throws -> [EvalSelection.Row])?

    public init(candidates: EvalCandidates = EvalCandidates(), now: @escaping @Sendable () -> Date = { Date() },
                rows: (@Sendable () throws -> [EvalSelection.Row])? = nil) {
        self.candidates = candidates; self.now = now; self.rows = rows
    }

    // MARK: Streaming the export

    /// The longest line accepted: far above any real product record, so a corrupt file without line
    /// breaks stops instead of growing the buffer without limit.
    static let maximumLineBytes = 64 << 20

    /// Calls `body` with each line (without its newline) and its 1-based number. `.gz` streams through
    /// `/usr/bin/gzip -dc`; anything else is read directly. Every chunk read and every line handled sits in
    /// its own autorelease pool: a command-line tool's main thread never drains one, so without them each
    /// chunk would stay resident until exit and memory would grow with the export. Memory stays bounded by
    /// one chunk and one line.
    static func lines(of export: URL, _ body: (Data, Int) throws -> Void) throws {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: export.path, isDirectory: &isFolder), !isFolder.boolValue else {
            throw Problem.exportUnreadable
        }
        let handle: FileHandle
        var process: Process?
        if export.pathExtension.lowercased() == "gz" {
            let gzip = Process()
            gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            gzip.arguments = ["-dc", export.path]
            let pipe = Pipe()
            gzip.standardOutput = pipe
            gzip.standardError = FileHandle.nullDevice
            do { try gzip.run() } catch { throw Problem.exportUnreadable }
            handle = pipe.fileHandleForReading
            process = gzip
        } else {
            guard let file = FileHandle(forReadingAtPath: export.path) else { throw Problem.exportUnreadable }
            handle = file
        }
        defer {
            try? handle.close()
            if let process, process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }
        var buffer = Data()
        var number = 0
        while true {
            // `read(upToCount:)` throws a Swift error on an I/O failure, where `readData` would raise an
            // Objective-C exception that ends the process without a stop line.
            let chunk: Data
            do {
                chunk = try autoreleasepool { try handle.read(upToCount: 1 << 20) ?? Data() }
            } catch {
                throw Problem.exportUnreadable
            }
            if chunk.isEmpty { break }
            buffer.append(chunk)
            var start = buffer.startIndex
            while let newline = buffer[start...].firstIndex(of: 0x0A) {
                number += 1
                let line = buffer[start..<newline]
                try autoreleasepool { try body(line, number) }
                start = buffer.index(after: newline)
            }
            buffer = Data(buffer[start...])
            if buffer.count > maximumLineBytes { throw Problem.exportUnreadable }
        }
        if !buffer.isEmpty {
            number += 1
            try autoreleasepool { try body(buffer, number) }
        }
        process?.waitUntilExit()
        if let process, process.terminationStatus != 0 { throw Problem.exportUnreadable }
    }

    // MARK: Eligibility

    public static func country(_ product: [String: Any]) -> EvalSelection.Country? {
        let tags = product["countries_tags"] as? [String] ?? []
        return countryTags.first { tags.contains($0.0) }?.1
    }

    public static func fortified(_ product: [String: Any]) -> Bool {
        !((product["vitamins_tags"] as? [Any]) ?? []).isEmpty || !((product["minerals_tags"] as? [Any]) ?? []).isEmpty
    }

    static func declaresSalt(_ product: [String: Any]) -> Bool {
        guard let number = (product["nutriments"] as? [String: Any])?["salt_100g"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return number.doubleValue.isFinite && number.doubleValue >= 0
    }

    /// The product's eligibility: a UK or Taiwan product that the app admits as a candidate, with a
    /// complete declared panel. Nil when it is not eligible.
    func eligible(_ product: [String: Any], line: Int) -> EvalSelection.Product? {
        // The code names the record file, so only a barcode of ASCII digits is admitted (never a path).
        guard let country = Self.country(product), let code = product["code"] as? String,
              !code.isEmpty, code.count <= 32, code.allSatisfy({ $0.isASCII && $0.isNumber }),
              let input = try? candidates.openFoodFactsInput(product: product, shape: .search, retrievedAt: now()),
              let candidate = input.candidates.first?.candidate else { return nil }
        for key in Self.completePanel {
            let known: Bool = switch candidate.nutrients.entries.first(where: { $0.key == key })?.value {
            case .measured?, .augmented?: true
            default: false
            }
            if !known, !(key == .sodium && Self.declaresSalt(product)) { return nil }
        }
        return EvalSelection.Product(code: code, line: line, country: country, fortified: Self.fortified(product))
    }

    /// The eligibility rule, for tests (line 1).
    public func eligibleForTesting(_ product: [String: Any]) -> EvalSelection.Product? { eligible(product, line: 1) }

    /// A cheap test on the raw line before it is parsed: only lines naming one of the two country tags
    /// can be eligible.
    static func mayBeEligible(_ line: Data) -> Bool {
        countryTags.contains { line.range(of: Data($0.0.utf8)) != nil }
    }

    // MARK: Bundled rows

    /// Every row each table's own search returns for the fixed words, with the word that reaches it.
    public func harvestRows() throws -> [EvalSelection.Row] {
        var rows: [EvalSelection.Row] = []
        for table in EvalCase.Table.allCases {
            let source: any GenericFoodSearching
            do { source = try candidates.tables(table) } catch { throw EvalCandidates.Problem.tableUnavailable }
            for word in Self.harvestWords[table] ?? [] {
                let request = GenericFoodSearchRequest(text: try LedgerText(word), capturedAt: now(), locale: EvalCandidates.locale)
                guard case let .confirmation(route) = try source.search(request) else { continue }
                for candidate in route.confirmation.candidates {
                    rows.append(.init(table: table, search: word, recordID: candidate.candidate.recordID.value))
                }
            }
        }
        return rows
    }

    // MARK: Select

    public static let developmentFile = "development-cases.json"
    public static let sealedFile = "sealed-cases.json"
    public static let seedFile = "selection-seed.txt"
    public static let reviewSheetFile = "review-sheet-development.csv"

    /// Runs the selection and returns the console lines. Writes only after every step succeeded.
    public func select(export: URL, privateFolder: URL, seed: UInt64) -> [String] {
        let files = FileManager.default
        // Refuses to overwrite: any earlier output (case lists, records, seed or sheet) stops the run.
        guard [Self.developmentFile, Self.sealedFile, Self.seedFile, Self.reviewSheetFile, "records"]
            .allSatisfy({ !files.fileExists(atPath: privateFolder.appendingPathComponent($0).path) }) else {
            return [EvalConsole.stopLine(Problem.caseListsExist.description)]
        }
        // Pass 1: the pool.
        var pool: [EvalSelection.Product] = []
        var scanned = 0
        do {
            try Self.lines(of: export) { line, number in
                scanned += 1
                guard Self.mayBeEligible(line),
                      let product = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let eligible = eligible(product, line: number) else { return }
                pool.append(eligible)
            }
        } catch {
            return [EvalConsole.stopLine(Problem.exportUnreadable.description)]
        }
        var lines = [EvalConsole.poolLine(scanned: scanned, eligible: pool.count,
                                          uk: pool.filter { $0.country == .unitedKingdom }.count,
                                          taiwan: pool.filter { $0.country == .taiwan }.count,
                                          fortified: pool.filter(\.fortified).count)]
        // The draw.
        var generator = EvalSelection.Generator(seed: seed)
        let draw: EvalSelection.Draw
        let rowDraw: EvalSelection.RowDraw
        do {
            draw = try EvalSelection.drawProducts(pool, generator: &generator)
            rowDraw = try EvalSelection.drawRows(rows?() ?? harvestRows(), generator: &generator)
        } catch let stop as EvalSelection.Stop {
            return lines + [EvalConsole.stopLine(stop.description)]
        } catch let problem as EvalCandidates.Problem {
            return lines + [EvalConsole.stopLine(problem.description)]
        } catch {
            return lines + [EvalConsole.stopLine("selection_failed")]
        }
        // Pass 2: the chosen records only. Each line must still hold the product pass 1 chose, and still
        // be eligible, so an export replaced between the passes stops instead of writing another record.
        let wanted = Dictionary(uniqueKeysWithValues: (draw.development + draw.sealed).map { ($0.line, $0) })
        var records: [Int: [String: Any]] = [:]
        var mismatch = false
        do {
            try Self.lines(of: export) { line, number in
                guard let chosen = wanted[number] else { return }
                guard let product = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      product["code"] as? String == chosen.code, eligible(product, line: number) == chosen else {
                    mismatch = true
                    return
                }
                records[number] = product
            }
        } catch {
            return lines + [EvalConsole.stopLine(Problem.exportUnreadable.description)]
        }
        guard !mismatch, records.count == wanted.count else { return lines + [EvalConsole.stopLine(Problem.recordMissing.description)] }
        // The retrieval time is the export's own modification time, so the same export and seed give the
        // same case lists, hashes and manifests on every run.
        guard let modified = (try? files.attributesOfItem(atPath: export.path))?[.modificationDate] as? Date else {
            return lines + [EvalConsole.stopLine(Problem.exportUnreadable.description)]
        }
        let retrievedAt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: modified.timeIntervalSince1970.rounded(.down)))
        func cases(_ products: [EvalSelection.Product], _ rows: [EvalSelection.Row]) -> EvalCaseList {
            EvalCaseList(cases: products.map { EvalCase(kind: .openFoodFacts, record: "records/\($0.code).json", shape: .search,
                                                        retrievedAt: retrievedAt) }
                + rows.map { EvalCase(kind: .bundledRow, table: $0.table, search: $0.search, recordID: $0.recordID, retrievedAt: retrievedAt) })
        }
        let development = cases(draw.development, rowDraw.development)
        let sealed = cases(draw.sealed, rowDraw.sealed)
        // Everything is written into a staging folder inside the private folder first and moved into place
        // only once all of it is written, so a failed write leaves no partial output to block a rerun.
        let staging = privateFolder.appendingPathComponent(".select-staging-\(seed)", isDirectory: true)
        let outputs = ["records", Self.developmentFile, Self.sealedFile, Self.seedFile, Self.reviewSheetFile]
        var moved: [String] = []
        do {
            try files.createDirectory(at: privateFolder, withIntermediateDirectories: true)
            try? files.removeItem(at: staging)
            try files.createDirectory(at: staging, withIntermediateDirectories: false)
            let encoder = FoundationCanonicalJSONEncoder()
            let recordsFolder = staging.appendingPathComponent("records", isDirectory: true)
            try files.createDirectory(at: recordsFolder, withIntermediateDirectories: false)
            for product in draw.development + draw.sealed {
                guard let record = records[product.line] else { throw Problem.recordMissing }
                try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                    .write(to: recordsFolder.appendingPathComponent("\(product.code).json"), options: .withoutOverwriting)
            }
            try encoder.encode(development).write(to: staging.appendingPathComponent(Self.developmentFile), options: .withoutOverwriting)
            try encoder.encode(sealed).write(to: staging.appendingPathComponent(Self.sealedFile), options: .withoutOverwriting)
            try Data("\(seed)\n".utf8).write(to: staging.appendingPathComponent(Self.seedFile), options: .withoutOverwriting)
            var sheet = [EvalSelection.reviewSheetNote, EvalSelection.reviewSheetHeader.map(EvalSelection.csvField).joined(separator: ",")]
            for (product, evalCase) in zip(draw.development, development.cases) {
                guard let record = records[product.line] else { throw Problem.recordMissing }
                let fields = [try EvalHashes.hash(evalCase), Self.name(record), (record["brands"] as? String) ?? "",
                              product.code, product.fortified ? "yes" : "no"] + Array(repeating: "", count: 6)
                sheet.append(fields.map(EvalSelection.csvField).joined(separator: ","))
            }
            try Data((sheet.joined(separator: "\n") + "\n").utf8)
                .write(to: staging.appendingPathComponent(Self.reviewSheetFile), options: .withoutOverwriting)
            let summary = [
                EvalConsole.selectionLine(set: "development", counts: EvalSelection.counts(products: draw.development, rows: rowDraw.development)),
                EvalConsole.selectionLine(set: "sealed", counts: EvalSelection.counts(products: draw.sealed, rows: rowDraw.sealed)),
                EvalConsole.setManifestLine(set: "development", try EvalHashes.manifest(development)),
                EvalConsole.setManifestLine(set: "sealed", try EvalHashes.manifest(sealed)),
            ]
            // `moveItem` never replaces an existing item, so a folder filled meanwhile still refuses.
            for name in outputs {
                try files.moveItem(at: staging.appendingPathComponent(name), to: privateFolder.appendingPathComponent(name))
                moved.append(name)
            }
            try files.removeItem(at: staging)
            lines += summary
        } catch {
            for name in moved { try? files.removeItem(at: privateFolder.appendingPathComponent(name)) }
            try? files.removeItem(at: staging)
            return lines + [EvalConsole.stopLine(Problem.writeFailed.description)]
        }
        return lines
    }

    /// The review sheet's name rule, for tests.
    public static func nameForTesting(_ record: [String: Any]) -> String { name(record) }

    /// The product's name for the review sheet: `product_name`, or else the first non-empty
    /// `product_name_<language>` in a fixed order (many Taiwan records carry only `product_name_zh`).
    static func name(_ record: [String: Any]) -> String {
        if let name = record["product_name"] as? String, !name.isEmpty { return name }
        return record.keys.filter { $0.hasPrefix("product_name_") }.sorted()
            .lazy.compactMap { record[$0] as? String }.first { !$0.isEmpty } ?? ""
    }
}

/// Whether a folder (or, when it does not exist yet, its nearest existing ancestor) is inside a git work
/// tree or a `.git` folder: `git rev-parse --is-inside-work-tree`, run locally with the key and every
/// `GIT_*` variable unset, so the owner's shell cannot point git elsewhere. It fails closed: only git's own
/// "not a git repository" answer counts as outside; a git that is missing, cannot start or refuses for any
/// other reason (for example dubious ownership) counts as inside.
public enum EvalWorkTree {
    public static func contains(_ folder: URL) -> Bool {
        var probe = folder.standardizedFileURL
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" { probe.deleteLastPathComponent() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", probe.path, "rev-parse", "--is-inside-work-tree"]
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment[EnvironmentKey.variable] = nil
        environment["LC_ALL"] = "C"
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { return true }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            return !(process.terminationStatus == 128 && errorText.contains("not a git repository"))
        }
        // "true" inside a work tree; "false" inside a `.git` folder, which is inside a repository too.
        return true
    }
}
