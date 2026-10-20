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
        /// `outsideTable`: the printed number, unit or comparator is recorded verbatim and is outside
        /// the closed lists (12.2.8): a reader binding to it is scored as usual and is wrong unless
        /// it matches exactly after the unit table; not reading it is never wrong.
        struct Quantity: Codable, Equatable {
            let number: String; let unit: String; let outsideTable: Bool?
            init(number: String, unit: String, outsideTable: Bool? = nil) { self.number = number; self.unit = unit; self.outsideTable = outsideTable }
            enum CodingKeys: String, CodingKey { case number, unit, outsideTable = "outside_table" }
        }
        struct Pack: Codable, Equatable { let number: String; let approximate: Bool }
        struct Column: Codable, Equatable { let heading: String?; let basis: String? }
        struct Value: Codable, Equatable {
            let comparator: String; let number: String; let unit: String; let outsideTable: Bool?
            init(comparator: String, number: String, unit: String, outsideTable: Bool? = nil) {
                self.comparator = comparator; self.number = number; self.unit = unit; self.outsideTable = outsideTable
            }
            enum CodingKeys: String, CodingKey { case comparator, number, unit, outsideTable = "outside_table" }
        }
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

    /// The scorer's own unit table (12.2.8), fixed before collection. The printed unit, compared
    /// exactly; a unit outside it is recorded verbatim with `outside_table` (12.2.5).
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
        // Anything outside the closed lists is allowed, recorded verbatim, when it carries `outside_table`.
        if let s = t.servingSize, s.outsideTable != true, decimal(s.number) == nil || units[s.unit] == nil {
            out.append("serving_size: outside the table without outside_table")
        }
        if let p = t.servingsPerPack, decimal(p.number) == nil { out.append("servings_per_pack") }
        if t.columns.isEmpty { out.append("no columns") }
        for (i, column) in t.columns.enumerated() where column.basis.map({ !bases.contains($0) }) ?? false { out.append("column \(i + 1) basis") }
        for row in t.rows {
            if !nutrients.contains(row.nutrient) { out.append("\(row.label): nutrient") }
            if row.values.count != t.columns.count { out.append("\(row.label): \(row.values.count) values for \(t.columns.count) columns") }
            for value in row.values.compactMap({ $0 }) where value.outsideTable != true {
                if !comparators.contains(value.comparator) { out.append("\(row.label): comparator \(value.comparator) without outside_table") }
                if decimal(value.number) == nil { out.append("\(row.label): number \(value.number) without outside_table") }
                if units[value.unit] == nil { out.append("\(row.label): unit \(value.unit) without outside_table") }
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

    static func append(_ line: String, to url: URL) throws {
        if let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd(); try handle.write(contentsOf: Data(line.utf8)); try handle.close()
        } else { try Data(line.utf8).write(to: url) }
    }

    /// One attempt of the run (12.2.7 item 3). `run-log.txt` gets a start line (UTC time, commit,
    /// the labels without output) before any label is read, then one `wrote <label>` line per
    /// output. A third attempt is refused, and so is an output the log does not account for.
    static func runAll(_ root: URL, commit: String, now: Date = Date()) throws -> Int {
        try requireSealed(root)
        let builder = PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: SystemClock(), encoder: FoundationCanonicalJSONEncoder(),
                                              digester: SHA256Digester(), conversions: NutritionLabelConversionChecker())
        let ids = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("texts").path)
            .filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
        let runFolder = root.appendingPathComponent("run")
        try FileManager.default.createDirectory(at: runFolder, withIntermediateDirectories: true)
        let logURL = root.appendingPathComponent("run-log.txt")
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let lines = log.split(separator: "\n").map(String.init)
        let starts = lines.filter { $0.hasPrefix("start ") }.count
        let logged = Set(lines.filter { $0.hasPrefix("wrote ") }.map { String($0.dropFirst(6)) })
        let existing = Set(try FileManager.default.contentsOfDirectory(atPath: runFolder.path)
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
        guard existing.isSubset(of: logged) else {
            throw Failure("refused: run outputs the log does not account for: \(existing.subtracting(logged).sorted().joined(separator: ", "))")
        }
        guard starts < 2 else { throw Failure("refused: a third attempt; one unchanged rerun is the limit (12.2.7 item 3)") }
        let pending = ids.filter { !existing.contains($0) }
        try append("start \(ISO8601DateFormatter().string(from: now)) commit=\(commit) attempt=\(starts + 1) pending=\(pending.joined(separator: ","))\n", to: logURL)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for id in pending {
            let text = try String(contentsOf: root.appendingPathComponent("texts/\(id).txt"), encoding: .utf8)
            let t = try transcription(Data(contentsOf: root.appendingPathComponent("transcription/\(id).json")))
            let result = run(labelID: id, text: text, transcription: t) { try builder.choose($0, in: $1) }
            try encoder.encode(result).write(to: runFolder.appendingPathComponent("\(id).json"))
            try append("wrote \(id)\n", to: logURL)
        }
        return pending.count
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

    /// Label normalisation for matching a cell the reader did not recognise (12.2.8): Unicode
    /// compatibility mapping (full-width letters, digits and brackets to their ASCII forms),
    /// every whitespace character removed, one trailing (自願標示者) or (自願標示) group removed,
    /// Latin letters lowercased. The transcriber's label comes from a screenshot and the reader's
    /// from pasted text, so only these differences are forgiven.
    static func normalisedLabel(_ label: String) -> String {
        var text = label.precomposedStringWithCompatibilityMapping
        text = String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(Character.init))
        for suffix in ["(自願標示者)", "(自願標示)"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)); break
        }
        return text.lowercased()
    }

    enum ColumnMatch: Equatable { case index(Int), notPrinted, ambiguous }

    /// The transcription column for a reader header (12.2.8): the one column with the header's
    /// basis. Two or more with that basis (for example as sold and as prepared, both per 100 g)
    /// are matched by position only when the reader read exactly the transcription's columns,
    /// in order, with that basis at that position; otherwise the match is ambiguous and every
    /// value bound under that header is wrong.
    static func column(_ headerID: String, _ candidate: PastedLabelManifest.Candidate, _ t: Transcription) -> ColumnMatch {
        guard let position = candidate.headers.firstIndex(where: { $0.headerID == headerID }) else { return .ambiguous }
        let basis = candidate.headers[position].basis
        let same = t.columns.indices.filter { t.columns[$0].basis == basis }
        switch same.count {
        case 0: return .notPrinted
        case 1: return .index(same[0])
        default:
            let inOrder = candidate.headers.count == t.columns.count
                && zip(candidate.headers, t.columns).allSatisfy { $0.basis == $1.basis }
            return inOrder ? .index(position) : .ambiguous
        }
    }

    enum Expected: Equatable { case value(Transcription.Value), notPrinted, ambiguous }

    /// The transcription's value for a bound cell: by nutrient for a recognised cell; for a cell
    /// the reader did not recognise, by normalised label against every transcription row,
    /// whatever its nutrient (a match never counts as reading that nutrient).
    static func expected(_ t: Transcription, candidate: PastedLabelManifest.Candidate, headerID: String,
                         nutrient: String, label: String) -> Expected {
        let col: Int
        switch column(headerID, candidate, t) {
        case .ambiguous: return .ambiguous
        case .notPrinted: return .notPrinted
        case let .index(i): col = i
        }
        let rows = nutrient == "unrecognised"
            ? t.rows.filter { normalisedLabel($0.label) == normalisedLabel(label) }
            : t.rows.filter { $0.nutrient == nutrient }
        guard rows.count == 1 else { return rows.isEmpty ? .notPrinted : .ambiguous }
        return rows[0].values[col].map(Expected.value) ?? .notPrinted
    }

    /// Exact comparison (12.2.8): the same comparator, exact decimal equality of the numbers and
    /// the same canonical unit after the unit table. A transcribed value outside the table can
    /// only match when it maps through the table anyway.
    static func same(comparator: String, number: String, unit: String, as value: Transcription.Value) -> Bool {
        guard comparator == value.comparator, let read = decimal(number), let printed = decimal(value.number),
              let canonical = units[value.unit] else { return false }
        return read == printed && unit.lowercased() == canonical.lowercased()
    }

    /// Half a unit in the last printed decimal place ("419" gives 0.5, "1.30" gives 0.005).
    static func halfUnit(_ text: String) -> Decimal {
        let places = text.split(separator: ".").dropFirst().first?.count ?? 0
        var half = Decimal(5)
        for _ in 0...places { half /= 10 }
        return half
    }

    /// A calculated kcal (or sodium) against the kcal (or sodium) the label also prints in that
    /// column: the same comparator, and a difference no larger than the rounding of the stored
    /// value (0.05), of the printed value (half its last place) and of the printed operand (half
    /// its last place, times the conversion: 1/4.184 for kJ, 400 for grams of salt to mg sodium).
    static func calculatedMatchesPrinted(_ conversion: PastedLabelManifest.Conversion, operand: Transcription.Value,
                                         printed: Transcription.Value) -> Bool {
        guard (conversion.comparator ?? "=") == printed.comparator, let stored = decimal(conversion.storedText),
              let value = decimal(printed.number), let unit = units[printed.unit] else { return false }
        let scale: Decimal
        switch (conversion.nutrient, unit) {
        case ("energy_kcal", "kcal"), ("sodium", "mg"): scale = 1
        case ("sodium", "g"): scale = 1000
        default: return false
        }
        let factor: Decimal = conversion.nutrient == "sodium" ? 400 : 1 / Decimal(string: "4.184", locale: Locale(identifier: "en_US_POSIX"))!
        let tolerance = Decimal(string: "0.05", locale: Locale(identifier: "en_US_POSIX"))! + halfUnit(printed.number) * scale + halfUnit(operand.number) * factor
        let difference = stored - value * scale
        return (difference < 0 ? -difference : difference) <= tolerance
    }

    /// The canonical unit of a conversion's operand: `g_salt` is grams of salt.
    static func operandUnit(_ unit: String) -> String { unit == "g_salt" ? "g" : unit }

    static func score(_ r: RunResult, _ t: Transcription) -> Score {
        guard r.outcome == "usable", let candidate = r.candidate, let stored = r.storedHeaderID else {
            return Score(labelID: r.labelID, outcome: "declined", declineCodes: r.declineCodes, valuesChecked: 0, wrong: [],
                         correctionBurden: nil, unreadRows: 0, basisChoice: r.choice != nil, flags: [], warningCodes: [])
        }
        var checked = 0
        var wrong: [String] = []
        // Every bound cell, in every column.
        for cell in candidate.cells {
            checked += 1
            let where_ = "\(cell.rowID) \(cell.nutrient) \(cell.headerID)"
            switch expected(t, candidate: candidate, headerID: cell.headerID, nutrient: cell.nutrient, label: cell.printedLabel) {
            case .ambiguous: wrong.append("\(where_): no single transcribed row and column")
            case .notPrinted: wrong.append("\(where_): bound, but not printed")
            case let .value(value):
                if !same(comparator: cell.comparator, number: cell.decimalText, unit: cell.canonicalUnit, as: value) {
                    wrong.append("\(where_): read \(cell.comparator)\(cell.decimalText) \(cell.canonicalUnit)")
                }
            }
        }
        // Calculated values (12.2.8): the operand against its printed source; and, when the label
        // also prints the target nutrient in that column (printed but left unread, so the reader
        // calculated it), the calculated value against the printed one within the rounding of both.
        for conversion in r.conversions {
            checked += 1
            let source = candidate.cells.first { $0.rowID == conversion.sourceRowID && $0.headerID == conversion.sourceHeaderID }
            guard let source,
                  case let .value(value) = expected(t, candidate: candidate, headerID: source.headerID, nutrient: source.nutrient, label: source.printedLabel),
                  same(comparator: source.comparator, number: conversion.operandText, unit: operandUnit(conversion.operandUnit), as: value)
            else { wrong.append("calculated \(conversion.nutrient): operand does not match its printed source"); continue }
            if case let .value(printed) = expected(t, candidate: candidate, headerID: conversion.sourceHeaderID, nutrient: conversion.nutrient, label: "") {
                if !calculatedMatchesPrinted(conversion, operand: value, printed: printed) {
                    wrong.append("calculated \(conversion.nutrient): \(conversion.storedText) differs from the printed value")
                }
            }
        }
        // Serving size (whenever a number was read) and pack count.
        if let size = candidate.servingSize, let number = size.decimalText {
            checked += 1
            let unitMatches = size.canonicalUnit.map { unit in t.servingSize.flatMap { units[$0.unit] } == unit } ?? true
            if let printed = t.servingSize, let n = decimal(number), n == decimal(printed.number), unitMatches {} else {
                wrong.append("serving size read \(number) \(size.canonicalUnit ?? "")")
            }
        }
        if let pack = candidate.servingsPerPack {
            checked += 1
            if let printed = t.servingsPerPack, decimal(pack.decimalText) == decimal(printed.number), pack.approximate == printed.approximate {} else {
                wrong.append("servings per pack read \(pack.decimalText)")
            }
        }
        // Correction burden: printed ledger values the stored column leaves unread, plus a printed
        // serving size or pack count not read. Only the stored column's conversions count.
        var burden = 0
        if case let .index(col) = column(stored, candidate, t) {
            let storedConversions = r.conversions.filter { $0.sourceHeaderID == stored }
            for nutrient in ledgerNutrients {
                let printed = t.rows.contains { $0.nutrient == nutrient && $0.values[col] != nil }
                    || (nutrient == "energy_kcal" && t.rows.contains { $0.nutrient == "energy_kj" && $0.values[col] != nil })
                    || (nutrient == "sodium" && t.rows.contains { $0.nutrient == "salt" && $0.values[col] != nil })
                let read = candidate.cells.contains { $0.headerID == stored && $0.nutrient == nutrient }
                    || storedConversions.contains { $0.nutrient == nutrient }
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
