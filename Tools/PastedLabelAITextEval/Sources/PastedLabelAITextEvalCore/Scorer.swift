import Foundation

/// The table the product would show at Confirm, as the scorer reads it: the headers, every cell
/// with whether it carries an attention item, the values the model returned that were not read,
/// and the serving lines. Built by the harness from the shipped reader's result; pure data here.
public struct ConfirmTable: Codable, Equatable, Sendable {
    public struct Header: Codable, Equatable, Sendable {
        public let id: String
        public let basis: String
        public init(id: String, basis: String) { self.id = id; self.basis = basis }
    }

    public struct Cell: Codable, Equatable, Sendable {
        public let rowID: String
        public let nutrient: String
        public let printedLabel: String
        public let headerID: String
        /// `=`, `<` or `<=`.
        public let comparator: String
        public let decimalText: String
        public let canonicalUnit: String
        public let needsAttention: Bool
        public init(rowID: String, nutrient: String, printedLabel: String, headerID: String, comparator: String, decimalText: String,
                    canonicalUnit: String, needsAttention: Bool) {
            self.rowID = rowID; self.nutrient = nutrient; self.printedLabel = printedLabel; self.headerID = headerID; self.comparator = comparator
            self.decimalText = decimalText; self.canonicalUnit = canonicalUnit; self.needsAttention = needsAttention
        }
    }

    public let headers: [Header]
    public let cells: [Cell]
    /// The serving size read (decimal text and canonical unit), nil when none was read.
    public let servingSize: [String]?
    /// The pack count read (decimal text, approximate), nil when none was read.
    public let servingsPerPack: [String]?
    /// Every attention item at Confirm (cells, not-read values to enter, serving lines).
    public let attentionItems: Int

    public init(headers: [Header], cells: [Cell], servingSize: [String]?, servingsPerPack: [String]?, attentionItems: Int) {
        self.headers = headers; self.cells = cells; self.servingSize = servingSize; self.servingsPerPack = servingsPerPack
        self.attentionItems = attentionItems
    }
}

/// One label's counts for the 5.2.1 metrics and the 5.3 bar (docs/pasted-label-ai-text-v1.md).
public struct LabelScore: Codable, Equatable, Sendable {
    public struct Counts: Codable, Equatable, Sendable {
        public var printed = 0, shown = 0, correct = 0, wrong = 0
        public init() {}
    }

    public let scorer: String
    public let labelID: String
    public let set: String
    public let tier: String?
    public let copyMethod: String
    public let format: String
    /// `reached_confirm`, `declined` or `failed`.
    public let outcome: String
    public let declineReasons: [String]
    public let failure: String?
    /// Every printed field (one nutrient under one column) of the transcription, less the values
    /// in reference-intake amount columns (scorer v3, D28).
    public let fieldsPrinted: Int
    /// Transcribed values in reference-intake amount columns, which are not printed fields (D28):
    /// `fieldsPrinted + fieldsReferenceAmounts` is every transcribed value.
    public let fieldsReferenceAmounts: Int
    /// Values on rows the transcription records as `other` (v4, D29), outside reference-intake
    /// amount columns: rows the app keeps as unrecognised and never logs, so not printed fields.
    /// `fieldsPrinted + fieldsReferenceAmounts + fieldsUnrecognisedRows` is every transcribed value.
    public let fieldsUnrecognisedRows: Int
    /// Fields shown at Confirm (cells), correct and wrong under the scorer.
    public let fieldsShown: Int
    public let fieldsCorrect: Int
    public let fieldsWrong: Int
    /// Wrong values that carry an attention item, and those that do not (silent errors).
    public let wrongFlagged: Int
    public let wrongSilent: Int
    public let attentionItems: Int
    /// Printed fields with no correct value at Confirm (not read, or read wrong).
    public let printedNotCorrect: Int
    public let exactMatch: Bool
    public let noEdit: Bool
    public let silentErrorTable: Bool
    public let byNutrient: [String: Counts]
    public let wrong: [String]

    enum CodingKeys: String, CodingKey {
        case scorer, set, tier, format, outcome, failure, wrong
        case labelID = "label_id", copyMethod = "copy_method", declineReasons = "decline_reasons", fieldsPrinted = "fields_printed"
        case fieldsReferenceAmounts = "fields_reference_amounts", fieldsUnrecognisedRows = "fields_unrecognised_rows"
        case fieldsShown = "fields_shown", fieldsCorrect = "fields_correct", fieldsWrong = "fields_wrong", wrongFlagged = "wrong_flagged"
        case wrongSilent = "wrong_silent", attentionItems = "attention_items", printedNotCorrect = "printed_not_correct"
        case exactMatch = "exact_match", noEdit = "no_edit", silentErrorTable = "silent_error_table", byNutrient = "by_nutrient"
    }

    /// The per-label named scores the promptfoo assertion returns (numbers only), with the
    /// per-nutrient counts as `nutrient.<id>.<count>` for the breakdown by nutrient.
    public var namedScores: [String: Double] {
        func b(_ value: Bool) -> Double { value ? 1 : 0 }
        var byNutrientScores: [String: Double] = [:]
        for (nutrient, counts) in byNutrient {
            for (name, value) in [("printed", counts.printed), ("shown", counts.shown), ("correct", counts.correct), ("wrong", counts.wrong)] {
                byNutrientScores["nutrient.\(nutrient).\(name)"] = Double(value)
            }
        }
        return byNutrientScores.merging([
            "reached_confirm": b(outcome == "reached_confirm"), "declined": b(outcome == "declined"), "failed": b(outcome == "failed"),
            "fields_printed": Double(fieldsPrinted), "fields_reference_amounts": Double(fieldsReferenceAmounts), "fields_unrecognised_rows": Double(fieldsUnrecognisedRows), "fields_shown": Double(fieldsShown), "fields_correct": Double(fieldsCorrect),
            "fields_wrong": Double(fieldsWrong), "wrong_flagged": Double(wrongFlagged), "wrong_silent": Double(wrongSilent),
            "attention_items": Double(attentionItems), "printed_not_correct": Double(printedNotCorrect), "exact_match": b(exactMatch),
            "no_edit": b(noEdit), "silent_error_table": b(silentErrorTable),
        ]) { first, _ in first }
    }

    /// Field F1 for this label (0 when it shows or reads nothing).
    public var fieldF1: Double {
        guard fieldsShown > 0, fieldsPrinted > 0, fieldsCorrect > 0 else { return 0 }
        let precision = Double(fieldsCorrect) / Double(fieldsShown), recall = Double(fieldsCorrect) / Double(fieldsPrinted)
        return 2 * precision * recall / (precision + recall)
    }
}

/// `pasted-label-ai-text-scorer-v4 (rules of uk-fresh-scorer-v2; RI amount columns and unrecognised rows not printed fields)`:
/// the frozen fresh-set scorer's comparison
/// (`UKFreshSet.score` and `FreshSet`, `uk-fresh-scorer-v2` rules R1 to R3, in
/// `Packages/FoodLedgerKit/Tests/FoodLabelTextCaptureTests/`), copied because this tool never
/// imports a test target. Each rule only chooses the printed cell a read value is compared with;
/// the comparison (comparator, exact number, canonical unit, column basis) is exact. A value is
/// correct only on an exact match; a value with no single transcribed row and column is wrong.
/// The UK tables apply to a UK-schema case and the Taiwan tables to a Taiwan-schema case.
///
/// Readings carried over, and so pessimistic:
/// - a number with a comma followed by exactly three digits (`1,046`, `0,500`) is unparsable, as
///   the frozen reader's rule makes it. A transcription never holds one: validation refuses it
///   (the schema writes ASCII digits with at most one decimal point, so `1046`), and a mapped
///   `1,046kJ` (decimal text `1046`) matches a transcribed `1046`;
/// - calculated values (conversions) are not fields, since a conversion is not printed.
///
/// One deliberate deviation, also pessimistic: the frozen rule makes any comma ambiguous on a
/// Taiwan alias row (`RowClassifierV3.isTaiwanAlias`, inside the frozen parser, which this tool
/// cannot import). Here any comma on a row whose label holds CJK script is ambiguous
/// (`TranscriptionRules.hasCJK`). The alias rows are Chinese labels, so this is meant to cover
/// them; a CJK row that is not an alias is made ambiguous too, where the frozen scorer could
/// match it. Validation already requires `outside_table` for such a comma (`TranscriptionRules`).
///
/// Changed in v3 (D28, docs/pasted-label-ai-text-v1.md): a reference-intake column that is not a
/// percentage column under R1 (`isPercentColumn`: at least one `%` value and, apart from class
/// markers, nothing else) is a reference-intake amount column, and its values, class markers
/// included, are not printed fields. The mapping never reads an absolute reference amount and the
/// ledger never stores one, so the user never enters it. A mixed column (percentages and amounts)
/// is excluded whole. Only the printed-field count changes: the comparison rules (R1 to R3,
/// `expected`, `column`, `same`), the columns matching reads and silent-error scoring are as in v1,
/// every cell shown at Confirm is still scored, and a cell in a reference-intake column that the
/// transcription records as amounts stays wrong, never "read, but not printed". The excluded count is
/// `fieldsReferenceAmounts`. This scorer has no v2: the number is skipped so that its version never
/// reads as `uk-fresh-scorer-v2`, whose rules it applies.
///
/// Changed in v4 (D29): values on a row the transcription records as nutrient `other` are not
/// printed fields either (a value already in a reference-intake amount column is counted there).
/// The app keeps such a row as unrecognised and never logs it, so the user never enters it. As in
/// v3, only the printed-field count changes: every cell shown at Confirm, an unrecognised cell
/// included, is still scored by the same rules, and silent-error scoring is unchanged. The
/// excluded count is `fieldsUnrecognisedRows`.
public enum PastedLabelAITextScorer {
    public static let version = "pasted-label-ai-text-scorer-v4 (rules of uk-fresh-scorer-v2; RI amount columns and unrecognised rows not printed fields)"
    /// The transcription's nutrient for a printed row the app keeps as unrecognised.
    static let unrecognisedNutrient = "other"

    enum Expected: Equatable { case value(TranscriptionShapes.Value, rowLabel: String), notPrinted, ambiguous }
    enum ColumnMatch: Equatable { case index(Int), notPrinted, ambiguous }

    public static func score(_ evalCase: EvalCase, outcome: String, declineReasons: [String], failure: String?, table: ConfirmTable?) -> LabelScore {
        // The comparison rules follow the case's scoring format, not its source schema: a UK
        // development case from a Taiwan-schema file is scored by the UK rules, as the frozen
        // harness does (Qodo finding 3 on A2).
        let schema: TranscriptionRules.Schema = evalCase.format == .uk ? .uk : .taiwan
        let amountColumns = referenceAmountColumns(evalCase.expected)
        let outsideAmountColumns = evalCase.fields.filter { !amountColumns.contains($0.columnIndex) }
        let referenceAmounts = evalCase.fields.count - outsideAmountColumns.count
        let fields = outsideAmountColumns.filter { $0.nutrient != unrecognisedNutrient }
        let unrecognisedRows = outsideAmountColumns.count - fields.count
        var byNutrient: [String: LabelScore.Counts] = [:]
        for field in fields { byNutrient[field.nutrient, default: .init()].printed += 1 }
        func ended() -> LabelScore {
            LabelScore(scorer: version, labelID: evalCase.labelID, set: evalCase.set.rawValue, tier: evalCase.tier, copyMethod: evalCase.copyMethod,
                       format: evalCase.format.rawValue, outcome: outcome, declineReasons: declineReasons, failure: failure,
                       fieldsPrinted: fields.count, fieldsReferenceAmounts: referenceAmounts, fieldsUnrecognisedRows: unrecognisedRows, fieldsShown: 0, fieldsCorrect: 0, fieldsWrong: 0, wrongFlagged: 0, wrongSilent: 0,
                       attentionItems: 0, printedNotCorrect: fields.count, exactMatch: false, noEdit: false, silentErrorTable: false,
                       byNutrient: byNutrient, wrong: [])
        }
        guard outcome == "reached_confirm", let table else { return ended() }
        var correct = 0, wrongFlagged = 0, wrongSilent = 0
        var wrong: [String] = []
        var matched: Set<[Int]> = []
        for cell in table.cells {
            byNutrient[cell.nutrient, default: .init()].shown += 1
            let place = "\(cell.rowID) \(cell.headerID)"
            var isCorrect = false
            switch expected(evalCase, table: table, cell: cell, schema: schema) {
            case .ambiguous: wrong.append("\(place): no single transcribed row and column")
            case .notPrinted: wrong.append("\(place): read, but not printed")
            case let .value(value, printedLabel):
                let reference = isReference(cell.headerID, table)
                if same(cell, as: value, printedLabel: printedLabel, inReferenceColumn: reference, schema: schema) {
                    isCorrect = true
                    if let position = position(evalCase, table: table, cell: cell, schema: schema) { matched.insert(position) }
                } else {
                    wrong.append("\(place): read \(cell.comparator)\(cell.decimalText) \(cell.canonicalUnit)")
                }
            }
            if isCorrect {
                correct += 1
                byNutrient[cell.nutrient, default: .init()].correct += 1
            } else {
                byNutrient[cell.nutrient, default: .init()].wrong += 1
                if cell.needsAttention { wrongFlagged += 1 } else { wrongSilent += 1 }
            }
        }
        let wrongCount = table.cells.count - correct
        // A kept field with no correct cell, by position, so a match in an excluded column (which
        // the comparison still allows) never offsets a kept field that was not read.
        let printedNotCorrect = fields.filter { !matched.contains([$0.rowIndex, $0.columnIndex]) }.count
        var servingEdits = 0
        if evalCase.expected.servingSize != nil, table.servingSize == nil { servingEdits += 1 }
        if let read = table.servingSize, let printed = evalCase.expected.servingSize {
            let unitMatches = TranscriptionRules.unit(printed.unit, schema)?.lowercased() == read.last?.lowercased()
            if decimal(read.first ?? "") != decimal(printed.number) || !unitMatches { servingEdits += 1 }
        }
        if evalCase.expected.servingsPerPack != nil, table.servingsPerPack == nil { servingEdits += 1 }
        // An entry at Confirm that the label does not print must be removed: an edit (Qodo finding 4 on A2).
        if evalCase.expected.servingSize == nil, table.servingSize != nil { servingEdits += 1 }
        if evalCase.expected.servingsPerPack == nil, table.servingsPerPack != nil { servingEdits += 1 }
        if let read = table.servingsPerPack, let printed = evalCase.expected.servingsPerPack,
           decimal(read.first ?? "") != decimal(printed.number) || (read.last == "true") != printed.approximate { servingEdits += 1 }
        let exact = wrongCount == 0 && printedNotCorrect == 0
        return LabelScore(scorer: version, labelID: evalCase.labelID, set: evalCase.set.rawValue, tier: evalCase.tier, copyMethod: evalCase.copyMethod,
                          format: evalCase.format.rawValue, outcome: outcome, declineReasons: declineReasons, failure: failure,
                          fieldsPrinted: fields.count, fieldsReferenceAmounts: referenceAmounts, fieldsUnrecognisedRows: unrecognisedRows, fieldsShown: table.cells.count, fieldsCorrect: correct, fieldsWrong: wrongCount,
                          wrongFlagged: wrongFlagged, wrongSilent: wrongSilent, attentionItems: table.attentionItems,
                          printedNotCorrect: printedNotCorrect, exactMatch: exact, noEdit: exact && servingEdits == 0,
                          silentErrorTable: wrongSilent > 0, byNutrient: byNutrient, wrong: wrong)
    }

    // MARK: Matching (the frozen scorer's rules)

    static func isReference(_ headerID: String, _ table: ConfirmTable) -> Bool {
        table.headers.first { $0.id == headerID }?.basis == "reference_intake"
    }

    /// The transcription column for a header: the one with its basis; two or more matched by
    /// position among the amount columns, or by R1 among reference-intake columns.
    static func column(_ headerID: String, _ table: ConfirmTable, _ e: EvalCase.Expected) -> ColumnMatch {
        guard let header = table.headers.first(where: { $0.id == headerID }) else { return .ambiguous }
        let same = e.columns.indices.filter { e.columns[$0].basis == header.basis }
        switch same.count {
        case 0: return .notPrinted
        case 1: return .index(same[0])
        case _ where header.basis == "reference_intake":
            let percent = same.filter { isPercentColumn(e, $0) }
            return percent.count == 1 ? .index(percent[0]) : .ambiguous
        default:
            let readAmounts = table.headers.filter { $0.basis != "reference_intake" }
            let printedAmounts = e.columns.indices.filter { e.columns[$0].basis != "reference_intake" }
            guard readAmounts.count == printedAmounts.count, zip(readAmounts, printedAmounts).allSatisfy({ $0.basis == e.columns[$1].basis }),
                  let position = readAmounts.firstIndex(where: { $0.id == headerID }) else { return .ambiguous }
            return .index(printedAmounts[position])
        }
    }

    static func value(_ row: TranscriptionShapes.Row, _ col: Int) -> TranscriptionShapes.Value? {
        row.values.indices.contains(col) ? row.values[col] : nil
    }

    /// v3 (D28): the reference-intake amount columns, whose values are not printed fields: every
    /// reference-intake column that is not a percentage column under R1.
    static func referenceAmountColumns(_ e: EvalCase.Expected) -> Set<Int> {
        Set(e.columns.indices.filter { e.columns[$0].basis == "reference_intake" && !isPercentColumn(e, $0) })
    }

    /// R1: a column holding at least one percentage and, apart from class markers, nothing else.
    static func isPercentColumn(_ e: EvalCase.Expected, _ col: Int) -> Bool {
        let values = e.rows.compactMap { value($0, col) }.filter { !TranscriptionRules.isClassMarker($0) }
        return !values.isEmpty && values.allSatisfy { TranscriptionRules.unit($0.unit, .uk) == "%" || TranscriptionRules.unit($0.unit, .taiwan) == "%" }
    }

    static let energyPartners = ["energy_kj": "energy_kcal", "energy_kcal": "energy_kj"]
    static let dashes = ["-", "–", "—", "−"]

    /// The frozen `UKFreshSet.expected` (`UKFreshSetProtocol.swift` lines 482 to 520), ported
    /// exactly, returning the matched printed field's position too, so the position a correct cell
    /// counts against is decided by the same code path as its comparison. A recognised cell takes the
    /// rows with its nutrient. An unrecognised cell takes the rows whose normalised label equals its
    /// own; its label's bracketed units must name only its unit (`namesOnly`), the rows are kept only
    /// when theirs do too, and two or more rows are separated by the unit of their value in the
    /// column; still none or more than one is ambiguous. R2 applies when the own value is absent or a
    /// dash, exactly as the frozen condition reads.
    static func resolve(_ evalCase: EvalCase, table: ConfirmTable, cell: ConfirmTable.Cell,
                        schema: TranscriptionRules.Schema) -> (expected: Expected, position: [Int]?) {
        let e = evalCase.expected
        let col: Int
        switch column(cell.headerID, table, e) {
        case .ambiguous: return (.ambiguous, nil)
        case .notPrinted: return (.notPrinted, nil)
        case let .index(i): col = i
        }
        let indexed = Array(e.rows.enumerated()).map { (offset: $0.offset, row: $0.element) }
        let key = normalisedLabel(cell.printedLabel)
        var rows = cell.nutrient == "unrecognised"
            ? (key.isEmpty ? [] : indexed.filter { normalisedLabel($0.row.label) == key })
            : indexed.filter { $0.row.nutrient == cell.nutrient }
        if cell.nutrient == "unrecognised" {
            guard namesOnly(cell.canonicalUnit, cell.printedLabel, schema) else { return (.ambiguous, nil) }
            rows = rows.filter { namesOnly(cell.canonicalUnit, $0.row.label, schema) }
            if rows.count > 1 {
                rows = rows.filter { candidate in
                    value(candidate.row, col).flatMap { TranscriptionRules.unit($0.unit, schema) }?.lowercased() == cell.canonicalUnit.lowercased()
                }
                guard rows.count == 1 else { return (.ambiguous, nil) }
            }
            guard !rows.isEmpty else { return (.ambiguous, nil) }
        }
        guard rows.count == 1 else { return (rows.isEmpty ? .notPrinted : .ambiguous, nil) }
        let row = rows[0]
        // R2: the energy reference intake percentage printed once, on the partner row.
        if isNilOrDash(value(row.row, col)), let partner = energyPartners[cell.nutrient], e.columns[col].basis == "reference_intake",
           isPercentColumn(e, col), !table.cells.contains(where: { $0.headerID == cell.headerID && $0.nutrient == partner }) {
            let partners = indexed.filter { $0.row.nutrient == partner }
            if partners.count == 1, let printed = value(partners[0].row, col), TranscriptionRules.unit(printed.unit, schema) == "%" {
                return (.value(printed, rowLabel: partners[0].row.label), [partners[0].offset, col])
            }
        }
        guard let printed = value(row.row, col) else { return (.notPrinted, nil) }
        return (.value(printed, rowLabel: row.row.label), [row.offset, col])
    }

    /// R2's condition, as `value(rows[0], col).map(isDash) ?? true` reads in the frozen scorer.
    static func isNilOrDash(_ value: TranscriptionShapes.Value?) -> Bool {
        guard let value else { return true }
        return TranscriptionRules.isClassMarker(value) && dashes.contains(value.number)
    }

    static func expected(_ evalCase: EvalCase, table: ConfirmTable, cell: ConfirmTable.Cell, schema: TranscriptionRules.Schema) -> Expected {
        resolve(evalCase, table: table, cell: cell, schema: schema).expected
    }

    /// The printed field a correct cell matched, as `[row, column]`, from the same path as `expected`.
    static func position(_ evalCase: EvalCase, table: ConfirmTable, cell: ConfirmTable.Cell, schema: TranscriptionRules.Schema) -> [Int]? {
        resolve(evalCase, table: table, cell: cell, schema: schema).position
    }

    /// The frozen `namesOnly`: every bracket group of the label that holds a unit of the table
    /// names the same canonical unit as the cell (a label naming no unit agrees with any cell).
    static func namesOnly(_ cellUnit: String, _ label: String, _ schema: TranscriptionRules.Schema) -> Bool {
        guard let pattern = try? NSRegularExpression(pattern: #"\(([^()]*)\)"#) else { return false }
        let text = label.precomposedStringWithCompatibilityMapping
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).allSatisfy { match in
            guard let inner = Range(match.range(at: 1), in: text),
                  let named = TranscriptionRules.unit(String(text[inner]).trimmingCharacters(in: .whitespaces), schema) else { return true }
            return named.lowercased() == cellUnit.lowercased()
        }
    }

    /// R3: the one canonical unit a row label names, in a bracket group or as a bare last `kJ` or `kcal`.
    static func labelUnit(_ label: String, _ schema: TranscriptionRules.Schema) -> String? {
        let text = label.precomposedStringWithCompatibilityMapping
        var named = Set<String>()
        if let pattern = try? NSRegularExpression(pattern: #"\(([^()]*)\)"#) {
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let inner = Range(match.range(at: 1), in: text),
                   let unit = TranscriptionRules.unit(String(text[inner]).trimmingCharacters(in: .whitespaces), schema) {
                    named.insert(unit)
                }
            }
        }
        if let last = text.split(whereSeparator: { $0.isWhitespace }).last.map({ String($0).lowercased() }), ["kj", "kcal"].contains(last),
           let unit = TranscriptionRules.unit(last, schema) {
            named.insert(unit)
        }
        return named.count == 1 ? named.first : nil
    }

    static func decimal(_ text: String) -> Decimal? {
        guard text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The frozen per-row number rule: a comma followed by exactly three digits, or any comma on a
    /// row whose label holds CJK script, is ambiguous (unparsable); any other single comma between
    /// digits is a decimal point.
    static func rowNumber(_ text: String, label: String) -> Decimal? {
        guard text.contains(",") else { return decimal(text) }
        guard text.range(of: #"^[0-9]+,[0-9]+$"#, options: .regularExpression) != nil, !TranscriptionRules.hasCJK(label),
              let comma = text.firstIndex(of: ","), text[text.index(after: comma)...].count != 3 else { return nil }
        return decimal(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Exact comparison: a class marker matches only a read marker; an `outside_table` marker only
    /// itself; otherwise comparator, number and canonical unit must all match.
    static func same(_ cell: ConfirmTable.Cell, as value: TranscriptionShapes.Value, printedLabel: String, inReferenceColumn: Bool,
                     schema: TranscriptionRules.Schema) -> Bool {
        if TranscriptionRules.isClassMarker(value) { return TranscriptionRules.ukMarkers.contains(cell.decimalText.lowercased()) }
        if value.outsideTable == true, value.comparator == "=", value.unit.isEmpty, !value.number.isEmpty, !value.number.contains(where: \.isNumber) {
            return cell.decimalText == value.number
        }
        guard let printedComparator = TranscriptionRules.comparator(value.comparator, schema), cell.comparator == printedComparator,
              let read = rowNumber(cell.decimalText, label: cell.printedLabel), let printed = rowNumber(value.number, label: printedLabel),
              let canonical = value.unit.isEmpty ? (inReferenceColumn ? nil : labelUnit(printedLabel, schema)) : TranscriptionRules.unit(value.unit, schema)
        else { return false }
        return read == printed && cell.canonicalUnit.lowercased() == canonical.lowercased()
    }

    // MARK: Label normalisation (unrecognised rows only)

    static let rowMarkers = [">>", ">", "•", "·", "▲", "●", "*", "-", "—", "–", "_"]

    /// The frozen scorer's label normalisation: compatibility mapping, whitespace removed, leading
    /// markers and one leading `of which` removed, one trailing colon, unit bracket groups removed
    /// when something else remains, remaining brackets removed, lower-cased.
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
                if !trimmed, !ofWhichRemoved, text.prefix(7).lowercased() == "ofwhich" {
                    text = String(text.dropFirst(7)); ofWhichRemoved = true; trimmed = true
                }
            }
        }
        let brackets: Set<Character> = ["(", ")", "[", "]", "{", "}"]
        trimLeading()
        if text.hasSuffix(":") { text = String(text.dropLast()) }
        if let pattern = try? NSRegularExpression(pattern: #"\(([^()]*)\)"#) {
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let inner = Range(match.range(at: 1), in: text), TranscriptionRules.unit(String(text[inner]), .uk) != nil,
                      let whole = Range(match.range, in: text) else { continue }
                var removed = text
                removed.removeSubrange(whole)
                if removed.contains(where: { !brackets.contains($0) }) { text = removed }
            }
        }
        text.removeAll { brackets.contains($0) }
        trimLeading()
        if text.hasSuffix(":") { text = String(text.dropLast()) }
        return text.lowercased()
    }
}
