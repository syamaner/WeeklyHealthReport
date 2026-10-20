import CryptoKit
import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// The committed run harness and scorer of the reader v3 fresh-set release check
/// (`docs/pasted-nutrition-label-reader-v3.md` section 12.2). Frozen with the reader
/// (`ReaderV3FreezeTests` pins this file). It holds no label text: every real file lives in a
/// private folder outside every git checkout (12.3), which `FreshSet.privateFolder` enforces.
///
/// Steps, each run by `FreshSetStepTests` with `WHR_FRESH_SET_DIR` and `WHR_FRESH_SET_STEP`:
/// `seal-texts`, `validate`, `seal-1`, `seal-2`, `run`, `score`.
enum FreshSet {
    struct Failure: Error, CustomStringConvertible { let description: String; init(_ text: String) { description = text } }

    // MARK: Private folder (12.3)

    /// The folder must be absolute and outside every git checkout: no ancestor holds `.git`.
    static func privateFolder(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else { throw Failure("WHR_FRESH_SET_DIR must be an absolute path") }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var dir = url
        while true {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                throw Failure("refused: \(url.path) is inside a git checkout (\(dir.path)); the fresh set stays outside every repository")
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return url
    }

    // MARK: Seals (12.2.4 to 12.2.6)

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// A bundle's seal: the SHA-256 of a listing of `<sha256>  <relative path>` lines, one per file,
    /// sorted by path, each ending in a newline.
    static func bundleSHA256(_ folder: URL, prefix: String, suffix: String) throws -> (hash: String, files: Int) {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(suffix) }.sorted()
        guard !names.isEmpty else { throw Failure("no \(suffix) files in \(folder.lastPathComponent)") }
        let listing = try names.map { "\(sha256(try Data(contentsOf: folder.appendingPathComponent($0))))  \(prefix)/\($0)\n" }.joined()
        return (sha256(Data(listing.utf8)), names.count)
    }

    enum Seal: String, CaseIterable { case text, seal1, seal2 }

    /// `seals.txt`: one line per seal, `<name> <sha256> <files> <UTC time>`. Append-only, in order.
    static func seals(_ root: URL) -> [Seal: String] {
        guard let text = try? String(contentsOf: root.appendingPathComponent("seals.txt"), encoding: .utf8) else { return [:] }
        var out: [Seal: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            if parts.count >= 2, let seal = Seal(rawValue: parts[0]) { out[seal] = parts[1] }
        }
        return out
    }

    static func current(_ seal: Seal, _ root: URL) throws -> (hash: String, files: Int) {
        switch seal {
        case .text: try bundleSHA256(root.appendingPathComponent("texts"), prefix: "texts", suffix: ".txt")
        case .seal1, .seal2: try bundleSHA256(root.appendingPathComponent("transcription"), prefix: "transcription", suffix: ".json")
        }
    }

    static func seal(_ seal: Seal, _ root: URL, now: Date = Date()) throws -> String {
        let existing = seals(root)
        guard existing[seal] == nil else { throw Failure("\(seal.rawValue) is already recorded; seals are never replaced") }
        let order = Seal.allCases
        for earlier in order.prefix(while: { $0 != seal }) where existing[earlier] == nil {
            throw Failure("\(earlier.rawValue) must be recorded before \(seal.rawValue)")
        }
        if seal != .text { try validateTranscriptions(root) }
        if seal == .seal1, try current(.text, root).hash != existing[.text] { throw Failure("the texts changed after the text seal") }
        let (hash, files) = try current(seal, root)
        let line = "\(seal.rawValue) \(hash) \(files) \(ISO8601DateFormatter().string(from: now))\n"
        let url = root.appendingPathComponent("seals.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd(); try handle.write(contentsOf: Data(line.utf8)); try handle.close()
        } else {
            try Data(line.utf8).write(to: url)
        }
        return hash
    }

    /// The run and the score need the texts and the verified transcriptions exactly as sealed: a
    /// change after seal 2 voids the run (12.2.8).
    static func requireSealed(_ root: URL) throws {
        let recorded = seals(root)
        guard let text = recorded[.text], recorded[.seal1] != nil, let seal2 = recorded[.seal2] else {
            throw Failure("the text seal, seal 1 and seal 2 must all be recorded before the run")
        }
        guard try current(.text, root).hash == text else { throw Failure("void: the texts differ from the text seal") }
        guard try current(.seal2, root).hash == seal2 else { throw Failure("void: the transcriptions differ from seal 2") }
    }

    // MARK: Transcription (12.2.5)

    struct Transcription: Codable, Equatable {
        struct Quantity: Codable, Equatable { let number: String; let unit: String }
        struct Pack: Codable, Equatable { let number: String; let approximate: Bool }
        struct Column: Codable, Equatable { let heading: String?; let basis: String? }
        struct Value: Codable, Equatable { let comparator: String; let number: String; let unit: String }
        struct Row: Codable, Equatable { let label: String; let nutrient: String; let values: [Value?] }
        let schema: String
        let labelID: String
        let servingSize: Quantity?
        let servingsPerPack: Pack?
        let columns: [Column]
        let rows: [Row]
        let notes: [String]

        enum CodingKeys: String, CodingKey {
            case schema, columns, rows, notes
            case labelID = "label_id", servingSize = "serving_size", servingsPerPack = "servings_per_pack"
        }
    }

    static let transcriptionSchema = "reader-v3-fresh-transcription-v1"
    static let nutrients: Set<String> = ["energy_kcal", "energy_kj", "protein", "fat", "saturates", "trans_fat", "carbohydrate",
                                         "sugars", "added_sugars", "fibre", "sodium", "salt", "other"]
    static let bases: Set<String> = ["per_serving", "per_100g", "per_100ml", "reference_intake"]
    static let comparators: Set<String> = ["=", "<", "<="]

    /// The scorer's own unit table (12.2.8), fixed before collection. The printed unit, trimmed
    /// and compared exactly; anything else is a transcription error found before seal 1.
    static let units: [String: String] = [
        "大卡": "kcal", "千卡": "kcal", "kcal": "kcal", "Kcal": "kcal", "KCAL": "kcal",
        "kJ": "kJ", "KJ": "kJ", "kj": "kJ", "千焦": "kJ",
        "公克": "g", "克": "g", "g": "g",
        "毫克": "mg", "mg": "mg",
        "微克": "µg", "µg": "µg", "μg": "µg", "mcg": "µg",
        "毫升": "ml", "ml": "ml", "mL": "ml",
        "%": "%",
    ]

    static func decimal(_ text: String) -> Decimal? {
        guard text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func transcription(_ data: Data) throws -> Transcription {
        try JSONDecoder().decode(Transcription.self, from: data)
    }

    /// Every rule a transcription must meet before it can be sealed; returns the problems.
    static func problems(_ t: Transcription, expectedID: String) -> [String] {
        var out: [String] = []
        if t.schema != transcriptionSchema { out.append("schema") }
        if t.labelID != expectedID { out.append("label_id") }
        if let s = t.servingSize, decimal(s.number) == nil || units[s.unit] == nil { out.append("serving_size") }
        if let p = t.servingsPerPack, decimal(p.number) == nil { out.append("servings_per_pack") }
        if t.columns.isEmpty { out.append("no columns") }
        for (i, column) in t.columns.enumerated() where column.basis.map({ !bases.contains($0) }) ?? false { out.append("column \(i + 1) basis") }
        for row in t.rows {
            if !nutrients.contains(row.nutrient) { out.append("\(row.label): nutrient") }
            if row.values.count != t.columns.count { out.append("\(row.label): \(row.values.count) values for \(t.columns.count) columns") }
            for value in row.values.compactMap({ $0 }) {
                if !comparators.contains(value.comparator) { out.append("\(row.label): comparator") }
                if decimal(value.number) == nil { out.append("\(row.label): number") }
                if units[value.unit] == nil { out.append("\(row.label): unit \(value.unit)") }
            }
        }
        return out
    }

    static func validateTranscriptions(_ root: URL) throws {
        let texts = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("texts").path)
            .filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
        var report: [String] = []
        for id in texts {
            let url = root.appendingPathComponent("transcription/\(id).json")
            guard let data = try? Data(contentsOf: url) else { report.append("\(id): no transcription"); continue }
            guard let t = try? transcription(data) else { report.append("\(id): does not decode"); continue }
            report += problems(t, expectedID: id).map { "\(id): \($0)" }
        }
        if !report.isEmpty { throw Failure("transcriptions not ready:\n" + report.joined(separator: "\n")) }
    }

    // MARK: The run (12.2.7)

    struct RunResult: Codable, Equatable {
        struct Choice: Codable, Equatable { let arrangement: String; let offered: [String] }
        let schema: String
        let labelID: String
        /// `usable`, `declined`
        let outcome: String
        let declineCodes: [String]
        let choice: Choice?
        let candidate: PastedLabelManifest.Candidate?
        let storedHeaderID: String?
        let conversions: [PastedLabelManifest.Conversion]
        let flags: [String]
        let warningCodes: [String]
        let unreadRows: [String]

        enum CodingKeys: String, CodingKey {
            case schema, outcome, choice, candidate, conversions, flags
            case labelID = "label_id", declineCodes = "decline_codes", storedHeaderID = "stored_header_id"
            case warningCodes = "warning_codes", unreadRows = "unread_rows"
        }
    }

    static let runSchema = "reader-v3-fresh-run-v1"
    static let basisNotSure = "basis_not_sure"
    static let basisNotOffered = "basis_not_offered"

    private struct SystemClock: LedgerClock { func now() -> Date { Date() } }

    /// The app's Read label decision on one text, with the basis taken from the verified
    /// transcription when the sheet would be shown (12.2.7 item 2).
    static func run(labelID: String, text: String, transcription: Transcription,
                    choose: (PastedLabelBasisOptions.Arrangement, PastedLabelBasisChoiceRequest) throws -> PastedLabelReview) -> RunResult {
        let reader = PastedLabelReader(reader: NutritionLabelTextReader(), digester: SHA256Digester())
        func declined(_ codes: [String], _ reading: LabelReading?, choice: RunResult.Choice? = nil) -> RunResult {
            RunResult(schema: runSchema, labelID: labelID, outcome: "declined", declineCodes: codes, choice: choice,
                      candidate: reading?.candidate, storedHeaderID: nil, conversions: [], flags: [], warningCodes: [], unreadRows: [])
        }
        func usable(_ review: PastedLabelReview, choice: RunResult.Choice?) -> RunResult {
            RunResult(schema: runSchema, labelID: labelID, outcome: "usable", declineCodes: [], choice: choice,
                      candidate: review.reading.candidate, storedHeaderID: review.storedHeaderID, conversions: review.reading.conversions,
                      flags: review.flags.map { "\($0.code):\($0.concerns)" }, warningCodes: review.warningCodes,
                      unreadRows: review.reading.unreadRows.map { "\($0)" })
        }
        switch reader.read(text) {
        case let .declined(codes, reading):
            return declined(codes, reading)
        case let .usable(review):
            return usable(review, choice: nil)
        case let .needsBasisChoice(request):
            let offered = request.offered
            let amountBases = transcription.columns.compactMap { $0.basis == "reference_intake" ? nil : $0 }
            guard !amountBases.isEmpty, amountBases.allSatisfy({ $0.basis != nil }) else {
                return declined([basisNotSure], request.declinedReading, choice: .init(arrangement: "", offered: offered))
            }
            let identifier = amountBases.compactMap(\.basis).joined(separator: ",")
            guard offered.contains(identifier), let arrangement = PastedLabelBasisOptions.Arrangement(identifier: identifier),
                  let review = try? choose(arrangement, request) else {
                return declined([basisNotOffered], request.declinedReading, choice: .init(arrangement: identifier, offered: offered))
            }
            return usable(review, choice: .init(arrangement: identifier, offered: offered))
        }
    }

    static func runAll(_ root: URL) throws -> Int {
        try requireSealed(root)
        let builder = PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: SystemClock(), encoder: FoundationCanonicalJSONEncoder(),
                                              digester: SHA256Digester(), conversions: NutritionLabelConversionChecker())
        let ids = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("texts").path)
            .filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
        let runFolder = root.appendingPathComponent("run")
        try FileManager.default.createDirectory(at: runFolder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var written = 0
        for id in ids {
            let out = runFolder.appendingPathComponent("\(id).json")
            // A rerun after an infrastructure failure covers only the labels with no output (12.2.7 item 3).
            if FileManager.default.fileExists(atPath: out.path) { continue }
            let text = try String(contentsOf: root.appendingPathComponent("texts/\(id).txt"), encoding: .utf8)
            let t = try transcription(Data(contentsOf: root.appendingPathComponent("transcription/\(id).json")))
            let result = run(labelID: id, text: text, transcription: t) { try builder.choose($0, in: $1) }
            try encoder.encode(result).write(to: out)
            written += 1
        }
        let log = "run \(ISO8601DateFormatter().string(from: Date())) wrote \(written) of \(ids.count)\n"
        let logURL = root.appendingPathComponent("run-log.txt")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            try handle.seekToEnd(); try handle.write(contentsOf: Data(log.utf8)); try handle.close()
        } else { try Data(log.utf8).write(to: logURL) }
        return written
    }

    // MARK: Scoring (12.2.8)

    struct Score: Codable, Equatable {
        let labelID: String
        let outcome: String
        let declineCodes: [String]
        let valuesChecked: Int
        /// One line per wrong value (kept outside the repository with the rest of the score).
        let wrong: [String]
        let correctionBurden: Int?
        let unreadRows: Int
        let basisChoice: Bool
        let flags: [String]
        let warningCodes: [String]

        enum CodingKeys: String, CodingKey {
            case outcome, wrong, flags
            case labelID = "label_id", declineCodes = "decline_codes", valuesChecked = "values_checked"
            case correctionBurden = "correction_burden", unreadRows = "unread_rows", basisChoice = "basis_choice"
            case warningCodes = "warning_codes"
        }
    }

    /// The ledger values whose absence from the stored column costs the user an entry.
    static let ledgerNutrients = ["energy_kcal", "protein", "fat", "saturates", "carbohydrate", "sugars", "fibre", "sodium"]

    static func compact(_ label: String) -> String {
        label.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{3000}", with: "")
    }

    /// The transcription's value for a nutrient (or, for a row the reader did not recognise, a
    /// printed label) under a basis; nil when the label does not print it.
    static func expected(_ t: Transcription, nutrient: String, label: String, basis: String) -> Transcription.Value?? {
        guard let column = t.columns.firstIndex(where: { $0.basis == basis }) else { return .some(nil) }
        let matches = t.rows.filter { nutrient == "unrecognised" ? ($0.nutrient == "other" && compact($0.label) == compact(label)) : $0.nutrient == nutrient }
        guard matches.count == 1 else { return matches.isEmpty ? .some(nil) : .none }  // .none: ambiguous
        return .some(matches[0].values[column])
    }

    static func same(comparator: String, number: String, unit: String, as value: Transcription.Value) -> Bool {
        guard comparator == value.comparator, let read = decimal(number), let printed = decimal(value.number),
              let canonical = units[value.unit] else { return false }
        return read == printed && unit.lowercased() == canonical.lowercased()
    }

    static func score(_ r: RunResult, _ t: Transcription) -> Score {
        guard r.outcome == "usable", let candidate = r.candidate, let stored = r.storedHeaderID else {
            return Score(labelID: r.labelID, outcome: "declined", declineCodes: r.declineCodes, valuesChecked: 0, wrong: [],
                         correctionBurden: nil, unreadRows: 0, basisChoice: r.choice != nil, flags: [], warningCodes: [])
        }
        var checked = 0
        var wrong: [String] = []
        let basisByHeader = Dictionary(candidate.headers.map { ($0.headerID, $0.basis) }, uniquingKeysWith: { a, _ in a })
        // Every bound cell, in every column.
        for cell in candidate.cells {
            checked += 1
            switch expected(t, nutrient: cell.nutrient, label: cell.printedLabel, basis: cell.basis) {
            case .none: wrong.append("\(cell.rowID) \(cell.nutrient) \(cell.basis): more than one transcribed row")
            case .some(.none): wrong.append("\(cell.rowID) \(cell.nutrient) \(cell.basis): bound, but not printed")
            case let .some(.some(value)):
                if !same(comparator: cell.comparator, number: cell.decimalText, unit: cell.canonicalUnit, as: value) {
                    wrong.append("\(cell.rowID) \(cell.nutrient) \(cell.basis): read \(cell.comparator)\(cell.decimalText) \(cell.canonicalUnit)")
                }
            }
        }
        // Calculated values: scored by their printed operand (12.2.8, item 8).
        for conversion in r.conversions {
            checked += 1
            let source = candidate.cells.first { $0.rowID == conversion.sourceRowID && $0.headerID == conversion.sourceHeaderID }
            let basis = basisByHeader[conversion.sourceHeaderID] ?? ""
            guard let source, case let .some(.some(value)) = expected(t, nutrient: source.nutrient, label: source.printedLabel, basis: basis),
                  same(comparator: conversion.comparator ?? source.comparator, number: conversion.operandText, unit: conversion.operandUnit, as: value)
            else { wrong.append("calculated \(conversion.nutrient): operand does not match its printed source"); continue }
        }
        // Serving size and pack count.
        if let size = candidate.servingSize, let number = size.decimalText, let unit = size.canonicalUnit {
            checked += 1
            if let printed = t.servingSize, let n = decimal(number), n == decimal(printed.number), units[printed.unit] == unit {} else {
                wrong.append("serving size read \(number) \(unit)")
            }
        }
        if let pack = candidate.servingsPerPack {
            checked += 1
            if let printed = t.servingsPerPack, decimal(pack.decimalText) == decimal(printed.number), pack.approximate == printed.approximate {} else {
                wrong.append("servings per pack read \(pack.decimalText)")
            }
        }
        // Correction burden: printed ledger values the stored column leaves unread, plus a printed
        // serving size or pack count not read.
        let storedBasis = basisByHeader[stored] ?? ""
        var burden = 0
        if let column = t.columns.firstIndex(where: { $0.basis == storedBasis }) {
            for nutrient in ledgerNutrients {
                let printed = t.rows.contains { $0.nutrient == nutrient && $0.values[column] != nil }
                    || (nutrient == "energy_kcal" && t.rows.contains { $0.nutrient == "energy_kj" && $0.values[column] != nil })
                let read = candidate.cells.contains { $0.headerID == stored && $0.nutrient == nutrient }
                    || r.conversions.contains { $0.nutrient == nutrient }
                if printed && !read { burden += 1 }
            }
        }
        if t.servingSize != nil, candidate.servingSize?.decimalText == nil { burden += 1 }
        if t.servingsPerPack != nil, candidate.servingsPerPack == nil { burden += 1 }
        return Score(labelID: r.labelID, outcome: "usable", declineCodes: [], valuesChecked: checked, wrong: wrong,
                     correctionBurden: burden, unreadRows: r.unreadRows.count, basisChoice: r.choice != nil,
                     flags: r.flags, warningCodes: r.warningCodes)
    }

    struct Summary: Codable, Equatable {
        let labels: Int
        let reachedConfirm: Int
        let declined: Int
        let declinedByReason: [String: Int]
        let valuesChecked: Int
        let wrongValues: Int
        let tablesWithAWrongValue: Int
        let basisChoices: Int
        let rowsPrintedButNotRead: Int
        let burdenMean: String
        let burdenMedian: String
        let shareNeedingAny: String
        let perValueUpperBound95: String
        let perTableUpperBound95: String
        let passes: Bool
    }

    static func summary(_ scores: [Score]) -> Summary {
        let accepted = scores.filter { $0.outcome == "usable" }
        var reasons: [String: Int] = [:]
        for s in scores where s.outcome == "declined" { for code in s.declineCodes { reasons[code, default: 0] += 1 } }
        let burdens = accepted.compactMap(\.correctionBurden).sorted()
        func ratio(_ a: Int, _ b: Int) -> String { b == 0 ? "n/a" : String(format: "%.3f", Double(a) / Double(b)) }
        let median: String = burdens.isEmpty ? "n/a" : burdens.count % 2 == 1 ? "\(burdens[burdens.count / 2])"
            : String(format: "%.1f", Double(burdens[burdens.count / 2 - 1] + burdens[burdens.count / 2]) / 2)
        let checked = accepted.map(\.valuesChecked).reduce(0, +)
        let wrong = accepted.map(\.wrong.count).reduce(0, +)
        return Summary(labels: scores.count, reachedConfirm: accepted.count, declined: scores.count - accepted.count,
                       declinedByReason: reasons, valuesChecked: checked, wrongValues: wrong,
                       tablesWithAWrongValue: accepted.filter { !$0.wrong.isEmpty }.count,
                       basisChoices: scores.filter(\.basisChoice).count, rowsPrintedButNotRead: accepted.map(\.unreadRows).reduce(0, +),
                       burdenMean: ratio(burdens.reduce(0, +), burdens.count), burdenMedian: median,
                       shareNeedingAny: ratio(burdens.filter { $0 > 0 }.count, burdens.count),
                       perValueUpperBound95: ratio(3, checked), perTableUpperBound95: ratio(3, accepted.count), passes: wrong == 0)
    }

    static func scoreAll(_ root: URL) throws -> Summary {
        try requireSealed(root)
        let ids = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("texts").path)
            .filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let results = root.appendingPathComponent("results")
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        var scores: [Score] = []
        for id in ids {
            guard let data = try? Data(contentsOf: root.appendingPathComponent("run/\(id).json")) else {
                throw Failure("\(id) has no run output; rerun the infrastructure failure first (12.2.7)")
            }
            let s = score(try decoder.decode(RunResult.self, from: data),
                          try transcription(Data(contentsOf: root.appendingPathComponent("transcription/\(id).json"))))
            try encoder.encode(s).write(to: results.appendingPathComponent("\(id).json"))
            scores.append(s)
        }
        let summary = summary(scores)
        try encoder.encode(summary).write(to: results.appendingPathComponent("summary.json"))
        return summary
    }
}
