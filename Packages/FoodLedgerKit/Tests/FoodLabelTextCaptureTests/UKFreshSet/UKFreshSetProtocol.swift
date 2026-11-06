import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// The committed run harness and scorer of the UK English fresh-set release check
/// (`docs/pasted-nutrition-label-uk-english-v1-p3.md` section 2, adapting reader v3 section 12.2).
/// Frozen with the UK reader (`UKReaderFreezeTests` pins this file). It reuses the Taiwan
/// harness's infrastructure unchanged (`FreshSet.privateFolder`, the bundle hash, `seals.txt`,
/// `requireSealed`, `append`); everything that validates, reads or scores is its own. It holds no
/// label text: every real file lives in a private folder outside every git checkout.
///
/// Steps, each run by `UKFreshSetStepTests` with `WHR_UK_FRESH_SET_DIR` and `WHR_UK_FRESH_SET_STEP`:
/// `seal-texts`, `validate`, `seal-1`, `seal-2`, `run`, `score`. From UK reader v2 P3
/// (`docs/pasted-nutrition-label-uk-english-v2-p3.md` section 3) the run also writes each label's
/// set-aside file.
enum UKFreshSet {
    typealias Failure = FreshSet.Failure
    typealias Seal = FreshSet.Seal

    // MARK: Seals (reader v3 12.2.4 to 12.2.6, unchanged)

    /// `FreshSet.seal` with the UK schema: the same order, the same "a seal is never replaced"
    /// rule and the same `seals.txt` line, `<name> <sha256> <files> <UTC time>`.
    static func seal(_ seal: Seal, _ root: URL, now: Date = Date()) throws -> String {
        let existing = FreshSet.seals(root)
        guard existing[seal] == nil else { throw Failure("\(seal.rawValue) is already recorded; seals are never replaced") }
        for earlier in Seal.allCases.prefix(while: { $0 != seal }) where existing[earlier] == nil {
            throw Failure("\(earlier.rawValue) must be recorded before \(seal.rawValue)")
        }
        if seal != .text { try validateTranscriptions(root) }
        if seal == .seal1, try FreshSet.current(.text, root).hash != existing[.text] { throw Failure("the texts changed after the text seal") }
        let (hash, files) = try FreshSet.current(seal, root)
        try FreshSet.append("\(seal.rawValue) \(hash) \(files) \(ISO8601DateFormatter().string(from: now))\n",
                            to: root.appendingPathComponent("seals.txt"))
        return hash
    }

    // MARK: Transcription (section 2)

    /// The Taiwan shape plus `panel`. Markers (`Trace`, `Tr`, any dash) are first-class values,
    /// `{"comparator": "=", "number": "<as printed>", "unit": ""}` with no `outside_table`; any
    /// other non-numeric cell is recorded as Amendment 3, with `outside_table`. Row labels are
    /// recorded as printed on the line that holds the value, and a cell printing kJ and kcal
    /// together is two rows with the same label, `energy_kj` and `energy_kcal`.
    struct Transcription: Codable, Equatable {
        typealias Quantity = FreshSet.Transcription.Quantity
        typealias Pack = FreshSet.Transcription.Pack
        typealias Column = FreshSet.Transcription.Column
        typealias Value = FreshSet.Transcription.Value
        typealias Row = FreshSet.Transcription.Row
        let schema: String
        let labelID: String
        /// `uk_declaration`, `us_nutrition_facts` or `other_english`, decided by the panel's title
        /// alone; `unknown` only for a development transcription in the Taiwan schema.
        let panel: String
        let servingSize: Quantity?
        let servingsPerPack: Pack?
        let columns: [Column]
        let rows: [Row]
        let notes: [String]

        enum CodingKeys: String, CodingKey {
            case schema, panel, columns, rows, notes
            case labelID = "label_id", servingSize = "serving_size", servingsPerPack = "servings_per_pack"
        }
    }

    static let transcriptionSchema = "uk-english-v1-fresh-transcription-v1"
    static let panels: Set<String> = ["uk_declaration", "us_nutrition_facts", "other_english"]
    static let unknownPanel = "unknown"

    /// The scorer's closed comparator equivalences (section 3), looked up exactly or lowercased.
    static let comparatorTable: [String: String] = [
        "=": "=",
        "<": "<", "less than": "<",
        "<=": "<=", "≤": "<=",
    ]
    static func comparator(_ printed: String) -> String? { comparatorTable[printed] ?? comparatorTable[printed.lowercased()] }

    /// The scorer's closed unit equivalences (section 3), fixed before collection. Keys are
    /// lowercase and a printed unit is looked up exactly or, failing that, lowercased. `cal` stays
    /// apart from `kcal`, as reader v3 12.2.8.
    static let units: [String: String] = [
        "kj": "kJ", "kcal": "kcal", "cal": "cal",
        "g": "g", "gm": "g", "gms": "g", "gr": "g", "grs": "g",
        "mg": "mg",
        "µg": "µg", "μg": "µg", "mcg": "µg",
        "ml": "ml",
        "%": "%",
    ]
    static func unit(_ printed: String) -> String? { singleUnit(printed) ?? compoundUnit(printed) }

    static func singleUnit(_ printed: String) -> String? { units[printed] ?? units[printed.lowercased()] }

    /// Amendment 3, as `FreshSet.compoundUnit`, over the UK table: two units joined by `/` or `／`,
    /// or the second in brackets, map only when both parts map to the **same** canonical unit, so
    /// `kJ/kcal` never maps.
    static func compoundUnit(_ printed: String) -> String? {
        let parts: [String]
        if let slash = printed.firstIndex(where: { $0 == "/" || $0 == "／" }) {
            parts = [String(printed[..<slash]), String(printed[printed.index(after: slash)...])]
        } else if let open = printed.firstIndex(where: { $0 == "(" || $0 == "（" }), let last = printed.last, last == ")" || last == "）" {
            parts = [String(printed[..<open]), String(printed[printed.index(after: open)..<printed.index(before: printed.endIndex)])]
        } else {
            return nil
        }
        guard parts.allSatisfy({ !$0.isEmpty }), let first = singleUnit(parts[0]), let second = singleUnit(parts[1]),
              first == second else { return nil }
        return first
    }

    /// The marker class (section 3): `Trace`, `Tr` (any case) and every dash, one class, since a
    /// transcriber cannot tell the dashes apart reliably.
    static let markers = ["trace", "tr", "-", "–", "—", "−"]
    static func isMarkerText(_ text: String) -> Bool { markers.contains(text.lowercased()) }

    /// A printed marker of the class, in the transcription's first-class form.
    static func isClassMarker(_ value: Transcription.Value) -> Bool {
        value.comparator == "=" && value.unit.isEmpty && isMarkerText(value.number)
    }

    static func transcription(_ data: Data) throws -> Transcription {
        let t = try JSONDecoder().decode(Transcription.self, from: data)
        guard t.schema == transcriptionSchema else { throw Failure("schema \(t.schema) is not \(transcriptionSchema)") }
        return t
    }

    /// **Development only**: a P1 transcription in the Taiwan schema (`reader-v3-fresh-transcription-v1`)
    /// as the UK struct, with `panel` `unknown` and a marker of the class recorded with
    /// `outside_table` moved to the first-class form, so it scores as the UK scorer scores markers.
    /// A UK-schema file is returned as it is. The release steps never call this.
    static func developmentTranscription(_ data: Data) throws -> Transcription {
        if let uk = try? transcription(data) { return uk }
        let p1 = try FreshSet.transcription(data)
        guard p1.schema == FreshSet.transcriptionSchema else { throw Failure("schema \(p1.schema) is neither UK nor Taiwan") }
        func value(_ v: Transcription.Value) -> Transcription.Value {
            guard v.outsideTable == true, v.comparator == "=", v.unit.isEmpty, isMarkerText(v.number) else { return v }
            return .init(comparator: v.comparator, number: v.number, unit: v.unit)
        }
        return Transcription(schema: p1.schema, labelID: p1.labelID, panel: unknownPanel, servingSize: p1.servingSize,
                             servingsPerPack: p1.servingsPerPack, columns: p1.columns,
                             rows: p1.rows.map { .init(label: $0.label, nutrient: $0.nutrient, values: $0.values.map { $0.map(value) }) },
                             notes: p1.notes)
    }

    /// Every rule a transcription must meet before it can be sealed; returns the problems.
    static func problems(_ t: Transcription, expectedID: String) -> [String] {
        var out: [String] = []
        if t.schema != transcriptionSchema { out.append("schema") }
        if t.labelID != expectedID { out.append("label_id") }
        if !panels.contains(t.panel) { out.append("panel") }
        if let s = t.servingSize, s.outsideTable != true, FreshSet.decimal(s.number) == nil || unit(s.unit) == nil {
            out.append("serving_size: outside the table without outside_table")
        }
        if let p = t.servingsPerPack, FreshSet.decimal(p.number) == nil { out.append("servings_per_pack") }
        if t.columns.isEmpty { out.append("no columns") }
        for (i, column) in t.columns.enumerated() where column.basis.map({ !FreshSet.bases.contains($0) }) ?? false {
            out.append("column \(i + 1) basis")
        }
        for row in t.rows {
            if !FreshSet.nutrients.contains(row.nutrient) { out.append("\(row.label): nutrient") }
            if row.values.count != t.columns.count { out.append("\(row.label): \(row.values.count) values for \(t.columns.count) columns") }
            for value in row.values.compactMap({ $0 }) {
                if isClassMarker(value) {
                    if value.outsideTable == true { out.append("\(row.label): marker \(value.number) with outside_table") }
                    continue
                }
                guard value.outsideTable != true else { continue }
                if comparator(value.comparator) == nil { out.append("\(row.label): comparator \(value.comparator) without outside_table") }
                if FreshSet.rowNumber(value.number, rowLabel: row.label) == nil { out.append("\(row.label): number \(value.number) without outside_table") }
                if unit(value.unit) == nil { out.append("\(row.label): unit \(value.unit) without outside_table") }
            }
        }
        return out
    }

    static func validateTranscriptions(_ root: URL) throws {
        var report: [String] = []
        for id in try labelIDs(root) {
            let url = root.appendingPathComponent("transcription/\(id).json")
            guard let data = try? Data(contentsOf: url) else { report.append("\(id): no transcription"); continue }
            guard let t = try? transcription(data) else { report.append("\(id): does not decode as \(transcriptionSchema)"); continue }
            report += problems(t, expectedID: id).map { "\(id): \($0)" }
        }
        if !report.isEmpty { throw Failure("transcriptions not ready:\n" + report.joined(separator: "\n")) }
    }

    static func labelIDs(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("texts").path)
            .filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
    }

    // MARK: The run (reader v3 12.2.7)

    /// The Taiwan run result plus `format`, the inferred format of the reading.
    struct RunResult: Codable, Equatable {
        typealias Choice = FreshSet.RunResult.Choice
        let schema: String
        let labelID: String
        /// `usable`, `declined`
        let outcome: String
        let format: String?
        let declineCodes: [String]
        let choice: Choice?
        let candidate: PastedLabelManifest.Candidate?
        let storedHeaderID: String?
        let conversions: [PastedLabelManifest.Conversion]
        let flags: [String]
        let warningCodes: [String]
        let unreadRows: [String]

        enum CodingKeys: String, CodingKey {
            case schema, outcome, format, choice, candidate, conversions, flags
            case labelID = "label_id", declineCodes = "decline_codes", storedHeaderID = "stored_header_id"
            case warningCodes = "warning_codes", unreadRows = "unread_rows"
        }
    }

    static let runSchema = "uk-english-v1-fresh-run-v1"

    private struct SystemClock: LedgerClock { func now() -> Date { Date() } }

    /// The UK reader, read under `.ukDevelopment` (both formats, identity v3 from UK reader v2 P2).
    static let reader = PastedLabelReader(reader: UKEnglishLabelTextReader(), digester: SHA256Digester(), policy: .ukDevelopment)

    /// One label's set-aside file (`UKSetAsideRecord.fileSchema`), beside the run output so the run
    /// schema is unchanged (v2 P1 section 2, v2 P3 section 3). Written by both harnesses; read by
    /// nothing in the scorer.
    struct SetAsideFile: Codable, Equatable {
        let schema: String
        let labelID: String
        let entries: [UKSetAsideRecord]

        enum CodingKeys: String, CodingKey { case schema, labelID = "label_id", entries }

        init(labelID: String, text: String) {
            schema = UKSetAsideRecord.fileSchema
            self.labelID = labelID
            entries = UKEnglishLabelTextReader().setAside(text)
        }
    }

    /// The harness's confirmation builder, under the **same** `.ukDevelopment` policy. The run
    /// only calls `choose`; it never builds a manifest, which throws `identityNotRecordable` for
    /// this policy (P2b), so no UK record can be built before P5.
    static func builder(clock: any LedgerClock = SystemClock()) -> PastedLabelConfirmation {
        PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: clock, encoder: FoundationCanonicalJSONEncoder(),
                                digester: SHA256Digester(), conversions: NutritionLabelConversionChecker(), policy: .ukDevelopment)
    }

    /// The app's Read label decision on one text under `.ukDevelopment`, with the basis taken from
    /// the verified transcription when the sheet would be shown (12.2.7 item 2).
    static func run(labelID: String, text: String, transcription: Transcription,
                    choose: (PastedLabelBasisOptions.Arrangement, PastedLabelBasisChoiceRequest) throws -> PastedLabelReview) -> RunResult {
        func declined(_ codes: [String], _ reading: LabelReading?, choice: RunResult.Choice? = nil) -> RunResult {
            RunResult(schema: runSchema, labelID: labelID, outcome: "declined", format: reading?.format, declineCodes: codes, choice: choice,
                      candidate: reading?.candidate, storedHeaderID: nil, conversions: [], flags: [], warningCodes: [], unreadRows: [])
        }
        func usable(_ review: PastedLabelReview, choice: RunResult.Choice?) -> RunResult {
            RunResult(schema: runSchema, labelID: labelID, outcome: "usable", format: review.reading.format, declineCodes: [], choice: choice,
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
                return declined([FreshSet.basisNotSure], request.declinedReading, choice: .init(arrangement: "", offered: offered))
            }
            let identifier = amountBases.compactMap(\.basis).joined(separator: ",")
            guard offered.contains(identifier), let arrangement = PastedLabelBasisOptions.Arrangement(identifier: identifier),
                  let review = try? choose(arrangement, request) else {
                return declined([FreshSet.basisNotOffered], request.declinedReading, choice: .init(arrangement: identifier, offered: offered))
            }
            return usable(review, choice: .init(arrangement: identifier, offered: offered))
        }
    }

    /// One attempt of the run (12.2.7 item 3), as `FreshSet.runAll`. `run-log.txt` gets a start
    /// line (UTC time, commit, the labels without output) before any label is read, then one
    /// `wrote <label>` line per output. A third attempt is refused, and so is an output the log
    /// does not account for.
    static func runAll(_ root: URL, commit: String, now: Date = Date()) throws -> Int {
        try FreshSet.requireSealed(root)
        let builder = builder()
        let ids = try labelIDs(root)
        let runFolder = root.appendingPathComponent("run")
        let setAsideFolder = root.appendingPathComponent("set-aside")
        for folder in [runFolder, setAsideFolder] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
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
        try FreshSet.append("start \(ISO8601DateFormatter().string(from: now)) commit=\(commit) attempt=\(starts + 1) pending=\(pending.joined(separator: ","))\n",
                            to: logURL)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for id in pending {
            let text = try String(contentsOf: root.appendingPathComponent("texts/\(id).txt"), encoding: .utf8)
            let t = try transcription(Data(contentsOf: root.appendingPathComponent("transcription/\(id).json")))
            let result = run(labelID: id, text: text, transcription: t) { try builder.choose($0, in: $1) }
            try encoder.encode(result).write(to: runFolder.appendingPathComponent("\(id).json"))
            try encoder.encode(SetAsideFile(labelID: id, text: text)).write(to: setAsideFolder.appendingPathComponent("\(id).json"))
            try FreshSet.append("wrote \(id)\n", to: logURL)
        }
        return pending.count
    }

    // MARK: Scoring (section 3, otherwise reader v3 12.2.8)

    /// `FreshSet.Score` plus the transcription's `panel` and the reading's `format`, encoded flat.
    struct Score: Codable, Equatable {
        let score: FreshSet.Score
        let panel: String
        let format: String?

        init(score: FreshSet.Score, panel: String, format: String?) { self.score = score; self.panel = panel; self.format = format }

        enum CodingKeys: String, CodingKey { case panel, format }

        init(from decoder: any Decoder) throws {
            score = try FreshSet.Score(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            panel = try container.decode(String.self, forKey: .panel)
            format = try container.decodeIfPresent(String.self, forKey: .format)
        }

        func encode(to encoder: any Encoder) throws {
            try score.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(panel, forKey: .panel)
            try container.encodeIfPresent(format, forKey: .format)
        }
    }

    /// Leading row markers removed before matching: reader v3's, then `—`, `–` and `_`.
    static let rowMarkers = FreshSet.rowMarkers + ["—", "–", "_"]
    /// One leading `of which`, after whitespace is removed, matched in any case.
    static let ofWhich = "ofwhich"
    /// The bracket characters removed by step 4 once unit groups are gone.
    static let bracketCharacters: Set<Character> = ["(", ")", "[", "]", "{", "}"]

    /// Label normalisation for matching a cell the reader did not recognise (section 3), applied to
    /// the transcriber's label and the reader's alike: reader v3 12.2.8's steps (compatibility
    /// mapping, whitespace removed, leading markers, one trailing colon, unit bracket groups,
    /// lowercase) without the Taiwan `(自願標示)` step, and then: leading markers include `—`, `–`
    /// and `_`; one leading `of which` is removed; a unit bracket group is removed only when
    /// something else remains (so `(kcal)` normalises to `kcal`); every remaining bracket
    /// character is removed, so `(of which sugars)` and a label cut at a stray `(` both
    /// normalise to `sugars`.
    static func normalisedLabel(_ label: String) -> String {
        var text = label.precomposedStringWithCompatibilityMapping
        text = String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(Character.init))
        var ofWhichRemoved = false
        func trimLeading() {
            var trimmed = true
            while trimmed {
                trimmed = false
                for marker in rowMarkers where text.hasPrefix(marker) {
                    text = String(text.dropFirst(marker.count)); trimmed = true; break
                }
                if !trimmed, !ofWhichRemoved, text.prefix(ofWhich.count).lowercased() == ofWhich {
                    text = String(text.dropFirst(ofWhich.count)); ofWhichRemoved = true; trimmed = true
                }
            }
        }
        trimLeading()
        if text.hasSuffix(":") { text = String(text.dropLast()) }
        if let pattern = try? NSRegularExpression(pattern: #"\(([^()]*)\)"#) {
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let inner = Range(match.range(at: 1), in: text), unit(String(text[inner])) != nil,
                      let whole = Range(match.range, in: text) else { continue }
                var removed = text
                removed.removeSubrange(whole)
                if removed.contains(where: { !bracketCharacters.contains($0) }) { text = removed }
            }
        }
        text.removeAll { bracketCharacters.contains($0) }
        trimLeading()
        if text.hasSuffix(":") { text = String(text.dropLast()) }
        return text.lowercased()
    }

    typealias ColumnMatch = FreshSet.ColumnMatch

    /// `FreshSet.column`: the transcription column for a reader header, by basis, then by position
    /// among the amount columns.
    static func column(_ headerID: String, _ candidate: PastedLabelManifest.Candidate, _ t: Transcription) -> ColumnMatch {
        guard let header = candidate.headers.first(where: { $0.headerID == headerID }) else { return .ambiguous }
        let same = t.columns.indices.filter { t.columns[$0].basis == header.basis }
        switch same.count {
        case 0: return .notPrinted
        case 1: return .index(same[0])
        case _ where header.basis == "reference_intake":
            // R1 (v2 P3 section 2): of two or more reference intake columns, the one percent column.
            let percent = same.filter { isPercentColumn(t, $0) }
            return percent.count == 1 ? .index(percent[0]) : .ambiguous
        default:
            let readerAmounts = candidate.headers.filter { $0.basis != "reference_intake" }
            let printedAmounts = t.columns.indices.filter { t.columns[$0].basis != "reference_intake" }
            guard header.basis != "reference_intake", readerAmounts.count == printedAmounts.count,
                  zip(readerAmounts, printedAmounts).allSatisfy({ $0.basis == t.columns[$1].basis }),
                  let position = readerAmounts.firstIndex(where: { $0.headerID == headerID }) else { return .ambiguous }
            return .index(printedAmounts[position])
        }
    }

    typealias Expected = FreshSet.Expected

    // MARK: Scorer v2 rules R1 to R3 (`docs/pasted-nutrition-label-uk-english-v2-p3.md` section 2)

    /// The scorer's version. v1 (implicit) is the v1 P3 scorer; v2 adds R1 to R3, each of which only
    /// decides which printed cell a read value is compared with. Pinned by `UKReaderFreezeTests` pin 4.
    static let scorerVersion = "uk-fresh-scorer-v2"
    /// R2: the energy rows whose single reference intake percentage a transcriber and a reader may
    /// place on either row.
    static let energyPartners = ["energy_kj": "energy_kcal", "energy_kcal": "energy_kj"]
    /// R3: the bare last tokens of a row label that name its unit (bracket groups are read through `unit`).
    static let labelUnitTokens = ["kj", "kcal"]
    /// The canonical unit of a reference intake percentage (R1, R2).
    static let percentUnit = "%"

    /// R2: a printed dash of the marker class (not `Trace` or `Tr`).
    static func isDash(_ value: Transcription.Value) -> Bool { isClassMarker(value) && dashes.contains(value.number) }
    static let dashes = ["-", "–", "—", "−"]

    /// R3's limit: true for a reader header whose basis is `reference_intake`.
    static func isReferenceHeader(_ headerID: String, _ candidate: PastedLabelManifest.Candidate) -> Bool {
        candidate.headers.first { $0.headerID == headerID }?.basis == "reference_intake"
    }

    /// R1: a column holding at least one percentage and, apart from class markers, nothing else.
    static func isPercentColumn(_ t: Transcription, _ col: Int) -> Bool {
        let values = t.rows.compactMap { value($0, col) }.filter { !isClassMarker($0) }
        return !values.isEmpty && values.allSatisfy { unit($0.unit) == percentUnit }
    }

    /// R3: the one canonical unit a row label names, in a bracket group or as a bare last `kJ` or
    /// `kcal` token; nil when it names none or more than one.
    static func labelUnit(_ label: String) -> String? {
        let text = label.precomposedStringWithCompatibilityMapping
        var named = Set<String>()
        if let pattern = try? NSRegularExpression(pattern: #"\(([^()]*)\)"#) {
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let inner = Range(match.range(at: 1), in: text), let u = unit(String(text[inner]).trimmingCharacters(in: .whitespaces)) {
                    named.insert(u)
                }
            }
        }
        if let last = text.split(whereSeparator: { $0.isWhitespace }).last.map({ String($0).lowercased() }),
           labelUnitTokens.contains(last), let u = unit(last) {
            named.insert(u)
        }
        return named.count == 1 ? named.first : nil
    }

    static func value(_ row: Transcription.Row, _ col: Int) -> Transcription.Value? {
        row.values.indices.contains(col) ? row.values[col] : nil
    }

    /// The transcription's value for a bound cell: by nutrient for a recognised cell; for a cell
    /// the reader did not recognise, by normalised label against every transcription row,
    /// whatever its nutrient (a match never counts as reading that nutrient). When two or more
    /// rows share the label, the one whose value in the column has the cell's canonical unit is
    /// taken (section 3, disambiguation by unit); still none or more than one is ambiguous.
    static func expected(_ t: Transcription, candidate: PastedLabelManifest.Candidate, headerID: String,
                         nutrient: String, label: String, unit cellUnit: String) -> Expected {
        let col: Int
        switch column(headerID, candidate, t) {
        case .ambiguous: return .ambiguous
        case .notPrinted: return .notPrinted
        case let .index(i): col = i
        }
        // A label that normalises to nothing never matches anything.
        let key = normalisedLabel(label)
        var rows = nutrient == "unrecognised"
            ? (key.isEmpty ? [] : t.rows.filter { normalisedLabel($0.label) == key })
            : t.rows.filter { $0.nutrient == nutrient }
        if nutrient == "unrecognised" {
            // A unit the label names in brackets must agree with the cell's unit, on the reader's
            // label and on the matched row's, so removing it in normalisation never hides a mismatch.
            guard namesOnly(cellUnit, label) else { return .ambiguous }
            rows = rows.filter { namesOnly(cellUnit, $0.label) }
            if rows.count > 1 {
                rows = rows.filter { value($0, col).flatMap { unit($0.unit) }?.lowercased() == cellUnit.lowercased() }
                guard rows.count == 1 else { return .ambiguous }
            }
            guard !rows.isEmpty else { return .ambiguous }
        }
        guard rows.count == 1 else { return rows.isEmpty ? .notPrinted : .ambiguous }
        // R2: the energy reference intake percentage is one quantity, the same against kJ or kcal, so
        // when it is printed on one energy row only (the other empty or a dash), it is compared on
        // that row, whichever energy row the reader bound it to.
        if value(rows[0], col).map(isDash) ?? true, let partner = energyPartners[nutrient], t.columns[col].basis == "reference_intake",
           isPercentColumn(t, col), !candidate.cells.contains(where: { $0.headerID == headerID && $0.nutrient == partner }) {
            let partners = t.rows.filter { $0.nutrient == partner }
            if partners.count == 1, let printed = value(partners[0], col), unit(printed.unit) == percentUnit {
                return .value(printed, rowLabel: partners[0].label)
            }
        }
        return value(rows[0], col).map { Expected.value($0, rowLabel: rows[0].label) } ?? .notPrinted
    }

    /// True when every bracket group of the label that holds a unit of the table names the same
    /// canonical unit as the cell (a label naming no unit agrees with any cell).
    static func namesOnly(_ cellUnit: String, _ label: String) -> Bool {
        guard let pattern = try? NSRegularExpression(pattern: #"\(([^()]*)\)"#) else { return false }
        let text = label.precomposedStringWithCompatibilityMapping
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).allSatisfy { match in
            guard let inner = Range(match.range(at: 1), in: text),
                  let named = unit(String(text[inner]).trimmingCharacters(in: .whitespaces)) else { return true }
            return named.lowercased() == cellUnit.lowercased()
        }
    }

    /// Exact comparison (12.2.8) after the UK tables. A printed marker of the class matches only a
    /// read marker of the class (any number, `0` included, is wrong); an Amendment 3 marker
    /// matches only itself; a printed form with no mapping never matches.
    static func same(comparator read: String, number: String, unit readUnit: String, readLabel: String,
                     as value: Transcription.Value, printedLabel: String, inReferenceColumn: Bool = false) -> Bool {
        if isClassMarker(value) { return isMarkerText(number) }
        if FreshSet.isMarker(value) { return number == value.number }
        guard let printedComparator = comparator(value.comparator), read == printedComparator,
              let readNumber = FreshSet.rowNumber(number, rowLabel: readLabel),
              let printed = FreshSet.rowNumber(value.number, rowLabel: printedLabel),
              // R3: in an amount column, an empty printed unit (recorded with `outside_table`, as
              // validation requires) takes the one unit the printed row label names. Never in a
              // reference intake column, where a bare number is a percentage. Markers never reach here.
              let canonical = value.unit.isEmpty ? (inReferenceColumn ? nil : labelUnit(printedLabel)) : unit(value.unit)
        else { return false }
        return readNumber == printed && readUnit.lowercased() == canonical.lowercased()
    }

    /// `FreshSet.calculatedDifference` over the UK tables.
    static func calculatedDifference(_ conversion: PastedLabelManifest.Conversion, printed: Transcription.Value) -> Decimal? {
        guard printed.outsideTable != true, let stored = FreshSet.decimal(conversion.storedText), let value = FreshSet.decimal(printed.number),
              let printedUnit = unit(printed.unit), comparator(printed.comparator) == (conversion.comparator ?? "=") else { return nil }
        let scale: Decimal
        switch (conversion.nutrient, printedUnit) {
        case ("energy_kcal", "kcal"), ("sodium", "mg"): scale = 1
        case ("sodium", "g"): scale = 1000
        default: return nil
        }
        return stored - value * scale
    }

    static func score(_ r: RunResult, _ t: Transcription) -> Score {
        guard r.outcome == "usable", let candidate = r.candidate, let stored = r.storedHeaderID else {
            return Score(score: .init(labelID: r.labelID, outcome: "declined", declineCodes: r.declineCodes, valuesChecked: 0, wrong: [],
                                      correctionBurden: nil, unreadRows: 0, basisChoice: r.choice != nil, flags: [], warningCodes: []),
                         panel: t.panel, format: r.format)
        }
        var checked = 0
        var wrong: [String] = []
        var discrepancies: [String] = []
        // Every bound cell, in every column.
        for cell in candidate.cells {
            checked += 1
            let where_ = "\(cell.rowID) \(cell.nutrient) \(cell.headerID)"
            switch expected(t, candidate: candidate, headerID: cell.headerID, nutrient: cell.nutrient, label: cell.printedLabel,
                            unit: cell.canonicalUnit) {
            case .ambiguous: wrong.append("\(where_): no single transcribed row and column")
            case .notPrinted: wrong.append("\(where_): bound, but not printed")
            case let .value(value, printedLabel):
                if !same(comparator: cell.comparator, number: cell.decimalText, unit: cell.canonicalUnit, readLabel: cell.printedLabel,
                         as: value, printedLabel: printedLabel, inReferenceColumn: isReferenceHeader(cell.headerID, candidate)) {
                    wrong.append("\(where_): read \(cell.comparator)\(cell.decimalText) \(cell.canonicalUnit)")
                }
            }
        }
        // Calculated values (12.2.8): gated only by the operand against its printed source. When
        // the label also prints the target in that column, unread by the reader, the difference is
        // reported, never gated.
        for conversion in r.conversions {
            checked += 1
            let source = candidate.cells.first { $0.rowID == conversion.sourceRowID && $0.headerID == conversion.sourceHeaderID }
            guard let source,
                  case let .value(value, printedLabel) = expected(t, candidate: candidate, headerID: source.headerID, nutrient: source.nutrient,
                                                                  label: source.printedLabel, unit: source.canonicalUnit),
                  same(comparator: source.comparator, number: conversion.operandText, unit: FreshSet.operandUnit(conversion.operandUnit),
                       readLabel: source.printedLabel, as: value, printedLabel: printedLabel,
                       inReferenceColumn: isReferenceHeader(source.headerID, candidate))
            else { wrong.append("calculated \(conversion.nutrient): operand does not match its printed source"); continue }
            if case let .value(printed, _) = expected(t, candidate: candidate, headerID: conversion.sourceHeaderID, nutrient: conversion.nutrient,
                                                      label: "-", unit: ""),
               printed.outsideTable != true, !isClassMarker(printed) {
                discrepancies.append("\(conversion.nutrient): calculated \(conversion.storedText), printed \(printed.comparator)\(printed.number) \(printed.unit), "
                    + (calculatedDifference(conversion, printed: printed).map { "difference \($0)" } ?? "not comparable"))
            }
        }
        // Serving size (whenever a number was read) and pack count.
        if let size = candidate.servingSize, let number = size.decimalText {
            checked += 1
            let unitMatches = size.canonicalUnit.map { readUnit in t.servingSize.flatMap { unit($0.unit) } == readUnit } ?? true
            if let printed = t.servingSize, let n = FreshSet.decimal(number), n == FreshSet.decimal(printed.number), unitMatches {} else {
                wrong.append("serving size read \(number) \(size.canonicalUnit ?? "")")
            }
        }
        if let pack = candidate.servingsPerPack {
            checked += 1
            if let printed = t.servingsPerPack, FreshSet.decimal(pack.decimalText) == FreshSet.decimal(printed.number),
               pack.approximate == printed.approximate {} else {
                wrong.append("servings per pack read \(pack.decimalText)")
            }
        }
        // Correction burden, as 12.2.8: printed ledger values the stored column leaves unread,
        // plus a printed serving size or pack count not read. A match never counts as reading.
        var burden = 0
        if case let .index(col) = column(stored, candidate, t) {
            let storedConversions = r.conversions.filter { $0.sourceHeaderID == stored }
            for nutrient in FreshSet.ledgerNutrients {
                let targetPrinted = t.rows.contains { $0.nutrient == nutrient && value($0, col) != nil }
                let sourcePrinted = (nutrient == "energy_kcal" && t.rows.contains { $0.nutrient == "energy_kj" && value($0, col) != nil })
                    || (nutrient == "sodium" && t.rows.contains { $0.nutrient == "salt" && value($0, col) != nil })
                let cell = candidate.cells.contains { $0.headerID == stored && $0.nutrient == nutrient }
                let calculated = storedConversions.contains { $0.nutrient == nutrient }
                if targetPrinted && !cell { burden += 1 } else if !targetPrinted && sourcePrinted && !cell && !calculated { burden += 1 }
            }
        }
        if t.servingSize != nil, candidate.servingSize?.decimalText == nil { burden += 1 }
        if t.servingsPerPack != nil, candidate.servingsPerPack == nil { burden += 1 }
        return Score(score: .init(labelID: r.labelID, outcome: "usable", declineCodes: [], valuesChecked: checked, wrong: wrong,
                                  correctionBurden: burden, unreadRows: r.unreadRows.count, basisChoice: r.choice != nil,
                                  flags: r.flags, warningCodes: r.warningCodes, calculatedDiscrepancies: discrepancies),
                     panel: t.panel, format: r.format)
    }

    /// `FreshSet.Summary` over every label, plus the same summary for each `panel` on its own
    /// (`by_panel`), encoded flat. The check samples UK sites only, so a panel's figures describe
    /// the panels those sites print.
    struct Summary: Codable, Equatable {
        let overall: FreshSet.Summary
        let byPanel: [String: FreshSet.Summary]

        init(overall: FreshSet.Summary, byPanel: [String: FreshSet.Summary]) { self.overall = overall; self.byPanel = byPanel }

        enum CodingKeys: String, CodingKey { case byPanel = "by_panel" }

        init(from decoder: any Decoder) throws {
            overall = try FreshSet.Summary(from: decoder)
            byPanel = try decoder.container(keyedBy: CodingKeys.self).decode([String: FreshSet.Summary].self, forKey: .byPanel)
        }

        func encode(to encoder: any Encoder) throws {
            try overall.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(byPanel, forKey: .byPanel)
        }
    }

    static func summary(_ scores: [Score]) -> Summary {
        let panels = Set(scores.map(\.panel))
        return Summary(overall: FreshSet.summary(scores.map(\.score)),
                       byPanel: Dictionary(uniqueKeysWithValues: panels.map { panel in
                           (panel, FreshSet.summary(scores.filter { $0.panel == panel }.map(\.score)))
                       }))
    }

    static func scoreAll(_ root: URL) throws -> Summary {
        try FreshSet.requireSealed(root)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let results = root.appendingPathComponent("results")
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        var scores: [Score] = []
        for id in try labelIDs(root) {
            guard let data = try? Data(contentsOf: root.appendingPathComponent("run/\(id).json")) else {
                throw Failure("\(id) has no run output; rerun the infrastructure failure first (12.2.7)")
            }
            let result = try decoder.decode(RunResult.self, from: data)
            guard result.schema == runSchema else { throw Failure("\(id): run schema \(result.schema) is not \(runSchema)") }
            let s = score(result, try transcription(Data(contentsOf: root.appendingPathComponent("transcription/\(id).json"))))
            try encoder.encode(s).write(to: results.appendingPathComponent("\(id).json"))
            scores.append(s)
        }
        let summary = summary(scores)
        try encoder.encode(summary).write(to: results.appendingPathComponent("summary.json"))
        return summary
    }
}
