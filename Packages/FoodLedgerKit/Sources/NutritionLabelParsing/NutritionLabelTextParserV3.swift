import Foundation

/// `nutrition-label-text-parser-v3` (`docs/pasted-nutrition-label-reader-v3.md`), the reader
/// behind the pasted nutrition label route. It is parser v2 (`NutritionLabelTextParser`, kept
/// unchanged as the frozen evaluation reference and the non-regression baseline of section 5.5)
/// plus, from PRs 1 and 2 of section 8:
///
/// - the lines before the table (3.1): decorated titles, rule lines, serving-label variants
///   (每1份量), split serving and pack lines joined under the conditions of rule 3, pack-line
///   variants (本包裝包含, 本包裝 N 份), serving and pack on one line, and leading row markers;
/// - the row-name alias table `taiwan-row-aliases-v1` (section 4);
/// - the Taiwan unit rule (3.9): a mandatory Taiwan row printed in a unit other than the
///   template's is not read;
/// - layout precedence (3.0, `LabelLayout`) and gate input coverage on every consumed but
///   unbound line (3.0);
/// - PR 2: partial reading (3.8), the stacked sequence rule and Taiwan template order (3.2),
///   and `too_little_read` (3.7);
/// - PR 3: one-line tables (3.4, `FlattenedLine`), the basis printed only in the energy line
///   (3.5), bilingual Chinese and English tables (3.6) and the complete-panels decline (3.7,
///   decision 8). Section 8.3 records how they were built.
///
/// The safety rule of v3 (section 2): it may leave a value, a row or the table unread; it never
/// binds a value to the wrong row, column, basis or unit. Like v2 it has no network, clock,
/// randomness or hashing dependency.
public struct NutritionLabelTextParserV3: Sendable {
    public static let version = "nutrition-label-text-parser-v3"
    public static let aliasVersion = TaiwanRowAliases.version

    public init() {}

    public func parse(_ text: String, route: String = "A", inputSHA256: String) -> LabelCaptureCandidate {
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let language = NutritionLabelTextParser.language(of: normalised)
        if NutritionLabelTextParser.hasUnsupportedScript(normalised)
            || (language == .unknown && !normalised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return .declined(route: route, inputSHA256: inputSHA256, language: language, reasons: ["unsupported_language"])
        }
        let lines = normalised.components(separatedBy: "\n")
        var state = ParseStateV3()
        for (index, rawLine) in lines.enumerated() {
            state.lineIndex = index
            state.consume(rawLine)
            if !state.declineReasons.isEmpty { break }
        }
        let candidate = state.finish(route: route, inputSHA256: inputSHA256, language: language)
        // 3.7, decision 8: when the text holds two or more complete panels (each part before and
        // after the second panel's title, header or basis phrase reads on its own), the decline
        // gets its own copy asking the user to delete the ones they did not eat. Nothing is read.
        if candidate.declineReasons == ["multiple_panels"], let found = state.panelBreak, case let split = Self.headingStart(lines, before: found), split > 0,
           Self.isCompletePanel(Array(lines[..<split]), route: route, inputSHA256: inputSHA256),
           Self.isCompletePanel(Array(lines[split...]), route: route, inputSHA256: inputSHA256) {
            return .declined(route: route, inputSHA256: inputSHA256, language: language, reasons: [Self.multipleCompletePanelsCode])
        }
        return candidate
    }

    /// A short heading line (Han only, no digit, not a row label, such as a flavour name) straight
    /// before the second panel's title or header belongs to the second panel (journey QA of #283).
    static func headingStart(_ lines: [String], before split: Int) -> Int {
        var index = split - 1
        while index >= 0, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index -= 1 }
        guard index > 0 else { return split }
        let heading = lines[index].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}-–—=【】[]")))
        guard !heading.isEmpty, heading.count <= 20, heading.allSatisfy(FlattenedLine.isHan), !RowClassifierV3.isRowLabel(heading),
              !TaiwanRowAliases.isRecognisedChinese(heading) else { return split }
        return index
    }

    /// 3.7 (decision 8): the decline when the text holds two or more complete panels.
    static let multipleCompletePanelsCode = "multiple_complete_panels"

    /// A part of the text is a complete panel when it reads on its own with at least one stored
    /// nutrient, or itself holds two or more complete panels.
    static func isCompletePanel(_ lines: [String], route: String, inputSHA256: String) -> Bool {
        let part = NutritionLabelTextParserV3().parse(lines.joined(separator: "\n"), route: route, inputSHA256: inputSHA256)
        if part.declineReasons == [multipleCompletePanelsCode] { return true }
        return !part.declined && part.cells.contains { $0.nutrient != "unrecognised" }
    }
}

// MARK: - Patterns of parser v3

enum PatternsV3 {
    /// `每[一1]?份量` (3.1 rule 3); byte-identical to `PastedLabelServingSizeGrammarV3.labelPattern`.
    static let servingSize = LabelPattern(#"(?i)^(?:serving\s+size|portion\s+size|每[一1]?份量)\s*[:：]?\s*(.+)$"#)
    /// A serving label standing alone on its line.
    static let servingLabelAlone = LabelPattern(#"(?i)^(?:serving\s+size|portion\s+size|每[一1]?份量)\s*[:：]?$"#)
    /// A serving quantity and nothing else.
    static let servingQuantityAlone = LabelPattern(#"^(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)$"#)
    /// The pack phrase inside a serving line (5.6); byte-identical to the grammar copy.
    static let packPhrase = LabelPattern(#"本包裝包?含?\s*約?\s*\d+(?:\.\d+)?\s*份|(?i:servings?\s+per\s+(?:container|pack|package))"#)
    /// Pack lines: parser v2's English forms, and 本包裝(包)?含? with an optional 約 (3.1 rule 4).
    static let servingsPerPack = [
        Patterns.servingsPerPack[0],
        Patterns.servingsPerPack[1],
        LabelPattern(#"^本包裝包?含?\s*(約)?\s*(\d+(?:\.\d+)?)\s*份"#),
    ]
    /// A pack label standing alone, and the "N份" line that may follow it.
    static let packLabelAlone = LabelPattern(#"^本包裝包?含?\s*(約)?\s*[:：]?$"#)
    static let packQuantityAlone = LabelPattern(#"^(約)?\s*(\d+(?:\.\d+)?)\s*份$"#)
    /// A pack phrase found inside a serving line: Chinese, or English with its number.
    static let chinesePackPhrase = LabelPattern(#"^本包裝包?含?\s*(約)?\s*(\d+(?:\.\d+)?)\s*份"#)
    static let chinesePackAnywhere = LabelPattern(#"本包裝包?含?\s*(約)?\s*(\d+(?:\.\d+)?)\s*份"#)
    static let number = LabelPattern(#"\d+(?:[.．]\d+)?"#)
    /// A number with a count word (pieces, not servings): never a pack count (PR 3 re-review).
    static let countQuantity = LabelPattern(
        #"(?<![\d.,，．\p{No}])\d+(?:[.．]\d+)?\s*(?:片|塊|顆|粒|包|條|枚|個|支|盒|袋|罐|瓶|杯|匙|(?i:bars?|pieces?|pcs|biscuits?|slices?|cookies?|crackers?|sticks?|tablets?|candies|candy|wafers?|rolls?|cakes?|sachets?|bags?)(?![A-Za-z]))"#)
    /// A multiplier straight before or after a serving quantity (`2x15g`, `15g × 2`): the serving
    /// size is then a product the reader does not compute, so it is not read.
    static let multipliedQuantity = LabelPattern(
        #"\d\s*[xX×*＊]\s*\d|(?<![A-Za-z])[xX×*＊]\s*\d+(?:\.\d+)?\s*(?:g|ml|mL|公克|毫升|克)(?![A-Za-z])|\d+(?:\.\d+)?\s*(?:g|ml|mL|公克|毫升|克)\s*[xX×*＊](?![A-Za-z])"#)
    /// Weight and volume units other than grams and millilitres (a closed list).
    static let otherMeasureUnits: Set<String> = ["oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "kg", "kgs", "kilogram", "kilograms",
                                                 "mg", "mcg", "l", "litre", "litres", "liter", "liters", "cl", "dl", "cup", "cups", "tbsp",
                                                 "tsp", "tablespoon", "tablespoons", "teaspoon", "teaspoons", "fl", "floz", "pint", "pints"]
    /// The per 100 basis phrase inside a bracket (its 100 is not a quantity).
    static let per100Phrase = LabelPattern(#"(?i)每\s*100\s*(?:公克|克|毫升)|per\s*100\s*(?:g|ml)\b"#)
    /// Any number followed by a unit word, Chinese or English (PR 3 re-review: `25 grams`, `1 oz`).
    static let anyQuantity = LabelPattern(#"(?<![\d.,，．\p{No}])(\d+(?:[.．]\d+)?)\s*(公克|毫升|克|[A-Za-z]+)"#)
    /// Parser v2's serving quantity with a left boundary (PR 3 re-review): a number touching a
    /// digit, a separator or another numeral (`2．5公克`, `30,5g`, `3²0公克`) is never taken.
    static let servingQuantity = LabelPattern(#"(?<![\d.,，．\p{No}])(\d+(?:\.\d+)?)\s*(g|ml|mL|公克|毫升|克)(?![\p{L}])"#)
    /// A number written in a form the reader cannot hold: a comma, full-width point or another
    /// numeral between digits. A serving or pack line holding one is not read.
    static let oddNumber = LabelPattern(#"\d[,，．]\d|\d\p{No}|\p{No}\d"#)
    /// Serving unit words of a bilingual line: grams and millilitres in their spellings; any
    /// other unit word (oz, cup) has no canonical serving unit, so it is a conflict.
    static let servingUnitWords: [String: String] = [
        "g": "g", "gm": "g", "gms": "g", "gr": "g", "grs": "g", "cc": "ml", "gram": "g", "grams": "g", "gramme": "g", "grammes": "g", "公克": "g", "克": "g",
        "ml": "ml", "millilitre": "ml", "millilitres": "ml", "milliliter": "ml", "milliliters": "ml", "毫升": "ml",
    ]
    static let englishPackPhrase = LabelPattern(#"(?i)^servings?\s+per\s+(?:container|pack|package)\s*[:：]?\s*(about\s+)?(\d+(?:\.\d+)?)"#)
    /// The Chinese title, optionally followed by an English title from the existing title words
    /// or by one bracketed group (3.1 rule 1).
    static let chineseTitle = LabelPattern(
        #"(?i)^(?:營養標示|營養成分)[:：]?\s*(?:(?:nutrition(?:al)?(?: information| facts| declaration)?|typical values?|nutrition information typical values)[:：]?|[(（]([^)）]*)[)）])?$"#)
    /// Decoration removed at either end of a title line: ★ ☆ ◎ ● ▲ ■ ◆ 【 】 [ ] = and spaces.
    static let titleDecoration = CharacterSet(charactersIn: "★☆◎●▲■◆【】[]= \u{3000}\t")
    /// A rule line: only `=`, `-`, `─`, `_`, `*` and spaces.
    static let ruleLine = LabelPattern(#"^[=\-─_*\s　]+$"#)
    /// Leading row markers (3.1 rule 5), longest first; `-` and `*` only before a Han character.
    static let rowMarkers = [">>", ">", "•", "·", "▲", "●"]
    static let hanMarkers: [Character] = ["-", "*"]
    static let hanRun = LabelPattern(#"\p{Han}+"#)
    static let leadingHan = LabelPattern(#"^(\p{Han}+)"#)
    /// "More than" before a number: the reader has no such comparator, so such a value is never
    /// read as exact (it makes its row unread).
    static let greaterThan = LabelPattern(#"(?i)(?:[>≥＞≧]|超過|大於|多於|more\s+than|greater\s+than)\s*\d"#)
    /// Parser v2's value pattern with two more bound comparators, ≦ (at most) and 未滿 (less than),
    /// and 以下 or 以上 allowed straight after the unit (`5毫克以下`).
    static let value = LabelPattern(
        #"(?<![\p{L}\p{N}.,])(less than|<=|≤|≦|＜|<|少於|未滿)?\s*(\d+(?:[.,]\d+)?)\s*(kJ|kj|KJ|Kj|kcal|Kcal|KCAL|kCal|Cal|cal|mcg|mg|µg|μg|mL|ml|g|%|大卡|千卡|公克|毫克|微克|毫升|克)?(?!(?!以[下上])\p{L})"#
    )
    /// A bound word printed after a value: 以下 (at most) or 以上 (at least, which the reader
    /// cannot hold, so the row is not read).
    static let boundSuffix = LabelPattern(#"^\s*(以下|以上)"#)
    /// A note line (註, 備註, 说明, Note): never a row, gate-scanned.
    static let noteLine = LabelPattern(#"(?i)^(?:註|備註|説明|說明|notes?\b)"#)
    /// A pack line with a "more than" mark before its count (never read as exact).
    static let packMoreThan = LabelPattern(#"(?i)^(?:本包裝包?含?|servings?\s+per\s+(?:container|pack|package))\s*[:：]?\s*(?:[>≥＞≧]|超過|大於|多於|more\s+than)"#)
    /// A leading Han run straight against a digit or a comparator (`熱量51大卡`).
    static let stuckLabel = LabelPattern(#"^(\p{Han}+)(?=[0-9<≤≦＜])"#)
    /// 3.6 rule 4: number, bracketed English unit, Chinese unit. Groups: number, bracket, English
    /// unit, Chinese unit.
    static let unitPair = LabelPattern(
        #"(\d+(?:\.\d+)?)\s*([(（]\s*(kcal|Kcal|KCAL|kJ|kj|KJ|Cal|cal|mcg|mg|µg|μg|mL|ml|g)\s*[)）])\s*(大卡|千卡|公克|毫克|微克|毫升|克)"#)
    /// Serving v3's approximation words (section 5.6, v2's closed list), scanned on a bilingual
    /// serving or pack line (3.6 rule 5).
    static let approximateWords: Set<String> = ["about", "approx", "approximate", "approximately", "around", "ca", "circa", "roughly"]
    static let approximateMarks = ["約", "约", "~", "～", "〜", "≈", "≒", "±", "左右", "上下"]
    /// A reference-intake suffix printed after a percentage value (`5% DV`, `5% Daily Value`,
    /// `5% 每日參考值百分比`): it names the cell's column, never a row.
    static let referenceSuffix = LabelPattern(
        #"(?i)(?<![a-z])(?:of\s+(?:the\s+)?)?(?:dv|daily\s+values?|ri|nrv|reference\s+intakes?)(?![a-z])|每日參考值百分比|每日參考值"#)
    /// The same marks standing at the end of a label ("鈉 >", "超過").
    static let trailingGreaterThan = LabelPattern(#"(?i)\s*(?:[>≥＞≧]+|超過|大於|多於|more\s+than|greater\s+than)$"#)
}

// MARK: - Parse state

struct RowDraftV3 {
    var label: String
    var indented: Bool
    var values: [PrintedValue]
    var labelLineHadValues: Bool
    var attachedAfterValues = false
    /// The printed lines of the row, for gate input coverage when the row is not bound.
    var lines: [String]
    /// The row's label line started with a row marker (3.1 rule 5).
    var marked = false
    /// A value of the row was printed as "more than" (`>3公克`): the row is not read.
    var malformed = false
    /// A number of the row could be read in more than one way (`1,203毫克`; a comma on a Taiwan
    /// row): the row is not read (`ambiguous_number`).
    var ambiguous = false
    /// Bilingual (3.6 rule 3): the English gloss names a different nutrient (`gloss_conflict`).
    var glossConflict = false
    /// Bilingual (3.6 rule 4): a value printed with two units of different canonical units.
    var unitPairMismatch = false
    /// The row's label as printed when the label was reduced to its Chinese part (3.6).
    var printedLabel: String?
    /// A bound mark stood on a line of its own just before this row (it qualifies both rows).
    var orphanBound = false
    /// The number of label lines merged into this row (a wrapped label has two).
    var labelLines = 1
    /// The canonical units of the values on each value-only line attached to this row, in order
    /// (the stacked sequence rule of 3.2). A `*` line standing for a mandatory row's reference
    /// intake is recorded as one `%` value; it binds nothing.
    var valueLines: [[String?]] = []
}

struct ParseStateV3 {
    enum Pending: Equatable {
        case servingLabel(String)
        case packLabel(String, approximate: Bool)
    }

    struct Join: Equatable {
        var label: String
        var quantity: String
    }

    var headers: [LabelHeader] = []
    var rows: [RowDraftV3] = []
    var servingSize: LabelServingSize?
    var servingsPerPack: LabelServingsPerPack?
    var declineReasons: [String] = []
    var lastLineWasHeader = false
    var rowsStarted = false
    /// Body lines for layout precedence.
    var body: [LabelLayout.Line] = []
    /// Every line consumed without being bound to the candidate (3.0, gate input coverage).
    var unbound: [String] = []
    /// A serving or pack label standing alone before the table, waiting for its next non-empty line.
    var pending: Pending?
    /// A label standing alone after the first row: its quantity line, if next, is consumed unbound.
    var swallowQuantity: Pending?
    /// Split lines joined before the first row, applied at the end only outside stacked tables.
    var servingJoin: Join?
    var packJoin: (join: Join, approximate: Bool, decimal: String)?
    /// A "more than" mark on a line of its own before any row: the next row is not read.
    var pendingMoreThan = false
    /// A mark-only line was consumed since the last row label: the next row is not read.
    var pendingBound = false
    /// The last row whose label is recognised (spans end only at such a row).
    var lastRecognised: Int?
    /// Whether the previous line read the serving size or the pack count.
    var previousLineRead: Set<ReadLine> = []
    /// The text span of each row: its label line, value lines and every non-row line up to the
    /// next row label (the unexplained-bound rule).
    var spans: [Int: [(line: String, valueLine: Bool)]] = [:]
    /// The line being consumed put values into a row (only such values can explain a bound).
    var lineGaveValues = false
    /// Labels printed after their values on a value-only line, never bound (printed but not read).
    var droppedLabels: [String] = []
    /// The index of the line being consumed, and the line where a second panel's title, header or
    /// basis phrase stood (3.7, decision 8: the complete-panels copy).
    var lineIndex = 0
    var panelBreak: Int?
    /// The line being consumed was a flattened table (3.4): its rows carry their own segments.
    var lineWasFlattened = false
    /// 3.6 rule 2: the line being consumed may carry Latin words (a title, header, serving or
    /// pack line, or a row whose Latin words are its gloss or bracketed), and whether any line
    /// carried Latin words elsewhere (then a `mixed` text stays `mixed`).
    var currentLineLatinAllowed = false
    var latinOutsideAllowed = false
    /// 3.5, decision 23: the basis phrase printed in the energy line's bracket, kept only as a
    /// hint for the user's basis choice (never a header).
    var basisHint: String?
    /// Warnings raised while consuming lines (a bilingual serving or pack line whose quantities
    /// disagree), added to the candidate's warnings in order.
    var extraWarnings: [String] = []

    var servingClaimed: Bool { servingSize != nil || servingJoin != nil }
    /// A panel has started once a row carries values or names a recognised row; heading lines
    /// before a title or header (a flavour name, unrecognised and without values) do not start
    /// one (journey QA of #283).
    var rowsWithValues: Bool { rows.contains { !$0.values.isEmpty || RowClassifierV3.isRowLabel($0.label) } }
    var packClaimed: Bool { servingsPerPack != nil || packJoin != nil }

    mutating func consume(_ rawLine: String) {
        let content = rawLine.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}")))
        guard !content.isEmpty else { return }
        let before = rows.count
        let labelBefore = rows.last?.label
        let servingBefore = (servingSize?.printedText, servingJoin)
        let packBefore = (servingsPerPack?.printedText, packJoin?.join)
        lineGaveValues = false
        currentLineLatinAllowed = false
        consumeLine(rawLine)
        if !currentLineLatinAllowed, Self.hasLatinWord(content) { latinOutsideAllowed = true }
        if lineWasFlattened {
            // A flattened line's rows carry their own segments (3.4); later lines join the last
            // row's span, so a bound word after the table still leaves that row unread.
            lineWasFlattened = false
            if !rows.isEmpty { lastRecognised = rows.count - 1 }
            previousLineRead = []
            return
        }
        // A span ends only at a recognised row label: every other line, including an unrecognised
        // row, belongs to the span of the last recognised row (the unexplained-bound rule).
        let newRecognised = rows.count > before && RowClassifierV3.isRowLabel(rows[rows.count - 1].label)
        // A label wrapped over two lines and merged here (`飽和` then `脂肪 1公克`, `of which` then
        // `saturates 1g`) is a span boundary too: the row's span starts at its label lines.
        let mergedRecognised = rows.count == before && !rows.isEmpty && rows[rows.count - 1].label != labelBefore
            && labelBefore.map { !RowClassifierV3.isRowLabel($0) } == true && RowClassifierV3.isRowLabel(rows[rows.count - 1].label)
        let recognisedRow = newRecognised || mergedRecognised
        if mergedRecognised, let previous = lastRecognised, previous != rows.count - 1 {
            // Move the earlier label line(s) out of the previous row's span into this row's.
            let earlier = rows[rows.count - 1].lines.dropLast()
            var moved: [(line: String, valueLine: Bool)] = []
            for line in earlier.reversed() {
                guard let last = spans[previous]?.last, last.line == line.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}"))) else { break }
                spans[previous]?.removeLast()
                moved.insert(last, at: 0)
            }
            spans[rows.count - 1] = moved
        }
        if recognisedRow { lastRecognised = rows.count - 1 }
        if let index = lastRecognised { spans[index, default: []].append((content, lineGaveValues)) }
        // A line carrying a bound token that is not a recognised bound on its own cells, and that
        // does not become a recognised row, leaves the rows on both sides unread, and a serving
        // or pack line straight before it not read. A value line of a recognised row is charged to
        // that row only (its span), never to the next row.
        let valuesForRecognisedRow = lineGaveValues && rows.count == before && rows.last.map { RowClassifierV3.isRowLabel($0.label) } == true
        if !recognisedRow, !valuesForRecognisedRow, Self.unexplainedTokens(content, valueLine: lineGaveValues) > 0 {
            pendingBound = true
            if rows.count > before { rows[rows.count - 1].orphanBound = true }
            if previousLineRead.contains(.serving) { refuseServing() }
            if previousLineRead.contains(.pack) { refusePack() }
        }
        previousLineRead = []
        if servingSize?.printedText != servingBefore.0 || servingJoin != servingBefore.1 { previousLineRead.insert(.serving) }
        if servingsPerPack?.printedText != packBefore.0 || packJoin?.join != packBefore.1 { previousLineRead.insert(.pack) }
    }

    enum ReadLine: Hashable { case serving, pack }

    /// The serving size is not read: a joined line is dropped, a printed line keeps its text only.
    mutating func refuseServing() {
        if let join = servingJoin {
            unbound += [join.label, join.quantity]
            servingJoin = nil
        } else if let size = servingSize {
            servingSize = LabelServingSize(printedText: size.printedText, decimalText: nil, unit: nil, canonicalUnit: nil)
        }
    }

    /// The pack count is not read.
    mutating func refusePack() {
        if let join = packJoin {
            unbound += [join.join.label, join.join.quantity]
            packJoin = nil
        } else if let pack = servingsPerPack {
            unbound.append(pack.printedText)
            servingsPerPack = nil
        }
    }

    /// Bound tokens on a line that are not recognised bounds on values the line gave a row (a
    /// note's or footnote's values are never cells, so they explain nothing).
    static func unexplainedTokens(_ line: String, valueLine: Bool) -> Int {
        let text = markedRow(line) ?? line
        return BoundVocabulary.tokens(text).count - (valueLine ? consumedTokens(text) : 0)
    }

    /// Bound tokens a line's values consume as recognised bounds (`<`, `≤`, `≦`, 未滿, 少於, "less
    /// than" before a value; 以下 straight after it).
    static func consumedTokens(_ text: String) -> Int {
        valueMatches(text).filter { $0.groups[1] != nil || ($0.groups.count > 4 && $0.groups[4] == "以下") }
            .map { BoundVocabulary.tokens(String(text[$0.range])).filter(BoundVocabulary.less.contains).count }
            .reduce(0, +)
    }

    mutating func consumeLine(_ rawLine: String) {
        let content = rawLine.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}")))
        guard !content.isEmpty else { return }

        if let label = pending {
            pending = nil
            if consumeJoin(label, content) { return }
            unbound.append(Self.text(of: label))
        }
        if let label = swallowQuantity {
            swallowQuantity = nil
            if Self.quantityLine(for: label, content) != nil {
                unbound.append(content)
                return
            }
        }
        if consumeFlattened(content) { return }
        if PatternsV3.ruleLine.contains(content) {
            unbound.append(content)
            return
        }
        if PatternsV3.noteLine.contains(content) {
            unbound.append(content)
            return
        }
        if content.hasPrefix("*") || content.hasPrefix("＊") || content.hasPrefix("†") {
            if !(content.hasPrefix("*") && Self.markedRow(content) != nil && !repeatsReadRow(content)) {
                // A lone `*` after a stacked row's values stands for its reference intake (3.2).
                if content == "*" || content == "＊", let last = rows.indices.last, !rows[last].labelLineHadValues,
                   !rows[last].valueLines.isEmpty {
                    rows[last].valueLines.append(["%"])
                }
                unbound.append(content)
                return
            }
        }
        if PatternsV3.packMoreThan.contains(content) {
            // "More than N servings" is not a count the reader can hold: the pack count is not read.
            unbound.append(content)
            lastLineWasHeader = false
            currentLineLatinAllowed = true
            return
        }
        for pattern in PatternsV3.servingsPerPack {
            if let groups = pattern.firstMatch(in: content), let number = groups[2] {
                currentLineLatinAllowed = true
                if !BoundVocabulary.tokens(content).isEmpty || Self.hasNonASCIIDigits(number) || PatternsV3.oddNumber.contains(content) {
                    // A bound word, or a count in full-width or other digits: not read.
                    unbound.append(content)
                    if Self.isBilingual(content), BoundVocabulary.tokens(content).isEmpty {
                        extraWarnings.append(Self.bilingualConflictWarning + "servings_per_pack")
                    }
                } else if !packClaimed {
                    // 3.6 rule 5: on a Chinese pack line, an English bracket is scanned for
                    // approximation ("about" in either language makes the count approximate),
                    // and the Chinese phrase decides the count: a line whose numbers disagree
                    // is not read (PR 3 review).
                    let approximate = groups[1] != nil || Self.bilingualApproximate(content)
                    switch Self.bilingualPackCount(content) {
                    case .some(nil):
                        servingsPerPack = LabelServingsPerPack(printedText: content, decimalText: number, approximate: approximate)
                    case let .some(.some(chinese)):
                        let chineseApproximate = approximate || PatternsV3.chinesePackAnywhere.firstMatch(in: content)?[1] != nil
                        servingsPerPack = LabelServingsPerPack(printedText: content, decimalText: chinese, approximate: chineseApproximate)
                    case .none:
                        unbound.append(content)
                        extraWarnings.append(Self.bilingualConflictWarning + "servings_per_pack")
                    }
                } else {
                    unbound.append(content)
                }
                lastLineWasHeader = false
                return
            }
        }
        if let groups = PatternsV3.packLabelAlone.firstMatch(in: content) {
            lastLineWasHeader = false
            label(.packLabel(content, approximate: groups[1] != nil))
            return
        }
        if PatternsV3.servingLabelAlone.contains(content) {
            lastLineWasHeader = false
            currentLineLatinAllowed = true
            label(.servingLabel(content))
            return
        }
        if let groups = PatternsV3.servingSize.firstMatch(in: content), let rest = groups[1] {
            currentLineLatinAllowed = true
            if !servingClaimed {
                servingSize = Self.servingSize(printed: content, value: rest)
                extraWarnings += Self.servingLineWarnings(line: content, value: rest)
                if !packClaimed, let pack = Self.packCount(inServingLine: content, value: rest) {
                    servingsPerPack = pack
                }
            } else {
                unbound.append(content)
            }
            lastLineWasHeader = false
            return
        }
        if Self.isTitle(content) {
            currentLineLatinAllowed = true
            // Only rows with values make a later title a second panel: a heading line before the
            // title (a flavour name, which binds nothing) does not (journey QA of #283).
            if rowsWithValues, content.contains("營養標示") || content.lowercased().hasPrefix("nutrition") {
                declineReasons.append("multiple_panels")
                panelBreak = lineIndex
            }
            unbound.append(content)
            return
        }
        if lastLineWasHeader, let groups = Patterns.parenthesised.firstMatch(in: content), groups[0] == content,
           let index = headers.lastIndex(where: { $0.basis == .perServing }) {
            currentLineLatinAllowed = true
            headers[index].printedText += " " + content
            if headers[index].servingConversion == nil { headers[index].servingConversion = groups[1]?.trimmingCharacters(in: .whitespaces) }
            return
        }
        if let brackets = Self.rowBasisBrackets(content) {
            consumeEnergyLineBasis(content, brackets: brackets)
            return
        }
        if Patterns.headerPhrase.contains(content) {
            currentLineLatinAllowed = true
            consumeHeader(content)
            return
        }
        lastLineWasHeader = false
        consumeRow(rawLine: rawLine, content: content)
    }

    /// A serving or pack label standing alone: before the first row it waits for its quantity
    /// line; after it, the serving line is not read and its quantity line is consumed unbound.
    mutating func label(_ label: Pending) {
        let claimed: Bool
        switch label {
        case .servingLabel: claimed = servingClaimed
        case .packLabel: claimed = packClaimed
        }
        if rowsStarted || claimed {
            unbound.append(Self.text(of: label))
            swallowQuantity = label
        } else {
            pending = label
        }
    }

    /// 3.1 rule 3 (and rule 4 for the pack line): the next non-empty line is joined only when it
    /// is that line's quantity and nothing else, and both come before the first row label. The
    /// remaining conditions (not stacked, no `stacked_sequence` row) are applied in `finish`.
    mutating func consumeJoin(_ label: Pending, _ content: String) -> Bool {
        guard !rowsStarted, !Self.hasNonASCIIDigits(content), let groups = Self.quantityLine(for: label, content) else { return false }
        switch label {
        case let .servingLabel(text):
            servingJoin = Join(label: text, quantity: content)
        case let .packLabel(text, approximate):
            guard let number = groups[2] else { return false }
            packJoin = (Join(label: text, quantity: content), approximate || groups[1] != nil, number)
        }
        lastLineWasHeader = false
        return true
    }

    static func quantityLine(for label: Pending, _ content: String) -> [String?]? {
        switch label {
        case .servingLabel: PatternsV3.servingQuantityAlone.firstMatch(in: content)
        case .packLabel: PatternsV3.packQuantityAlone.firstMatch(in: content)
        }
    }

    static func text(of label: Pending) -> String {
        switch label {
        case let .servingLabel(text): text
        case let .packLabel(text, _): text
        }
    }

    /// The joined printed text: the label line and the quantity line, each trimmed, joined by
    /// one ASCII space (3.1 rule 3; serving v3 scans exactly this string).
    static func joined(_ join: Join) -> String {
        join.label.trimmingCharacters(in: .whitespaces) + " " + join.quantity.trimmingCharacters(in: .whitespaces)
    }

    /// 3.1 rule 1: a title after removing decoration at either end. A bracket group after the
    /// Chinese title never carries a value: one with a digit or a basis phrase is not a title.
    static func isTitle(_ content: String) -> Bool {
        let stripped = content.trimmingCharacters(in: PatternsV3.titleDecoration)
        guard !stripped.isEmpty else { return false }
        if Patterns.title.contains(stripped) { return true }
        guard let groups = PatternsV3.chineseTitle.firstMatch(in: stripped) else { return false }
        if let bracket = groups[1] {
            if bracket.contains(where: \.isNumber) || ParseState.basis(of: bracket) != nil { return false }
        }
        return true
    }

    // MARK: Serving lines

    /// The serving value cut at the first pack phrase (5.6 step 3): it ends at the start of the
    /// match, with trailing spaces and `,` `，` `、` `/` `／` removed.
    static func cutAtPackPhrase(_ value: String) -> String {
        guard let match = PatternsV3.packPhrase.matchDetails(in: value).first else { return value }
        var head = String(value[..<match.range.lowerBound])
        while let last = head.last, last.isWhitespace || ",，、/／".contains(last) { head.removeLast() }
        return head
    }

    /// The serving size of a v3 serving line: the quantity located exactly as v2 does, in the
    /// value cut at the pack phrase.
    static func servingSize(printed: String, value: String) -> LabelServingSize {
        let cut = cutAtPackPhrase(value)
        // A serving size printed as "more than" (`超過30公克`, `30公克以上`) is not read.
        if !BoundVocabulary.tokens(cut).isEmpty { return LabelServingSize(printedText: printed, decimalText: nil, unit: nil, canonicalUnit: nil) }
        // A number the reader cannot hold (`2．5公克`, `30,5g`, `3²0公克`) is never cut down to the
        // digits after the separator: the serving size is not read (PR 3 re-review).
        if PatternsV3.oddNumber.contains(cut) { return LabelServingSize(printedText: printed, decimalText: nil, unit: nil, canonicalUnit: nil) }
        // A multiplied serving (`2x15g`, `2 x 15g`, `15g × 2`) is a product the reader does not
        // compute: not read, never the one factor (PR 3 re-review; parser v2 read 15 g).
        if PatternsV3.multipliedQuantity.contains(cut) { return LabelServingSize(printedText: printed, decimalText: nil, unit: nil, canonicalUnit: nil) }
        // 3.6 rule 5 (and the PR 3 review): on a serving line holding Chinese and English text,
        // in either order and bracketed or not, the quantities printed must agree; when they do
        // not (`Serving size 25g 每一份量 30公克`, `每一份量30公克 (about 25g)`) the serving size is
        // not read, never the English or the Chinese one picked. When they agree, the quantity
        // is located as serving v3 locates it (5.6 step 4), so servings stay offered.
        if bilingualQuantitiesDisagree(serving: cut, line: printed) {
            return LabelServingSize(printedText: printed, decimalText: nil, unit: nil, canonicalUnit: nil)
        }
        // An English bracket (one holding a Latin word) never supplies the number on its own
        // (3.6 rule 5): `每一份量1包 (about 30g)` is not read.
        if printed.contains(where: FlattenedLine.isHan), hasLatinWord(printed), PatternsV3.servingQuantity.contains(cut) {
            var outside = cut
            for bracket in Patterns.parenthesised.matches(in: cut) where hasLatinWord(bracket) {
                outside = outside.replacingOccurrences(of: bracket, with: " ")
            }
            if !PatternsV3.servingQuantity.contains(outside) {
                return LabelServingSize(printedText: printed, decimalText: nil, unit: nil, canonicalUnit: nil)
            }
        }
        let source = Patterns.parenthesised.firstMatch(in: cut)?[1] ?? cut
        if let groups = PatternsV3.servingQuantity.firstMatch(in: source) ?? PatternsV3.servingQuantity.firstMatch(in: cut),
           let number = groups[1], let unit = groups[2], !hasNonASCIIDigits(number) {
            // A number in full-width or other digits is never bound (PR 3 re-review).
            return LabelServingSize(printedText: printed, decimalText: number, unit: unit, canonicalUnit: LabelVocabulary.canonicalUnit(unit))
        }
        return LabelServingSize(printedText: printed, decimalText: nil, unit: nil, canonicalUnit: nil)
    }

    /// A line holding Han and a Latin word (a bilingual line, 3.6).
    static func isBilingual(_ line: String) -> Bool {
        line.contains(where: FlattenedLine.isHan) && hasLatinWord(line)
    }

    /// The conflict warnings of a bilingual serving line (with any pack phrase on it): quantities
    /// that disagree, a number that cannot be held (cut at a separator, non-ASCII digits), or pack
    /// counts that disagree. The user sees why the line was not read.
    static func servingLineWarnings(line: String, value: String) -> [String] {
        guard isBilingual(line) else { return [] }
        var warnings: [String] = []
        let cut = cutAtPackPhrase(value)
        if bilingualQuantitiesDisagree(serving: cut, line: line) || PatternsV3.oddNumber.contains(cut) || hasNonASCIIDigits(cut) {
            warnings.append(bilingualConflictWarning + "serving_size")
        }
        if PatternsV3.packPhrase.contains(value), case .none = bilingualPackCount(packRest(value)) {
            warnings.append(bilingualConflictWarning + "servings_per_pack")
        } else if PatternsV3.packPhrase.contains(value), PatternsV3.oddNumber.contains(packRest(value)) {
            warnings.append(bilingualConflictWarning + "servings_per_pack")
        }
        return warnings
    }

    /// A serving value with its weight and volume quantities removed (the text the pack rule
    /// compares on a serving line holding a pack phrase).
    static func packRest(_ value: String) -> String {
        var rest = value
        for match in PatternsV3.anyQuantity.matchDetails(in: value).reversed()
        where PatternsV3.servingUnitWords[(match.groups[2] ?? "").lowercased()] != nil {
            rest.replaceSubrange(match.range, with: " ")
        }
        // A count word is not a pack count (`1 bar`, `2 pieces`, `2片`); servings and 份 stay.
        for match in PatternsV3.countQuantity.matchDetails(in: rest).reversed() {
            rest.replaceSubrange(match.range, with: " ")
        }
        return rest
    }

    /// 3.1 rule 4: the pack count from a pack phrase on the serving line, read as printed.
    static func packCount(inServingLine line: String, value: String) -> LabelServingsPerPack? {
        guard let match = PatternsV3.packPhrase.matchDetails(in: value).first else { return nil }
        let phrase = String(value[match.range.lowerBound...])
        if !BoundVocabulary.tokens(phrase).isEmpty || PatternsV3.oddNumber.contains(phrase) { return nil }
        // PR 3 re-review: the bilingual pack rule applies to a pack phrase inside a serving line,
        // compared and scanned for approximation over the whole serving value with its serving
        // quantities removed, so an English count before the Chinese phrase is never missed.
        switch bilingualPackCount(packRest(value)) {
        case .none:
            return nil
        case let .some(.some(chinese)):
            let rest = packRest(value)
            let approximate = bilingualApproximate(rest) || PatternsV3.chinesePackAnywhere.firstMatch(in: rest)?[1] != nil
            return LabelServingsPerPack(printedText: line, decimalText: chinese, approximate: approximate)
        case .some(nil):
            break
        }
        for pattern in [PatternsV3.chinesePackPhrase, PatternsV3.englishPackPhrase] {
            if let groups = pattern.firstMatch(in: phrase), let number = groups[2] {
                if hasNonASCIIDigits(number) { return nil }
                return LabelServingsPerPack(printedText: line, decimalText: number, approximate: groups[1] != nil || bilingualApproximate(phrase))
            }
        }
        return nil
    }

    /// A "more than" mark before a number, or 以上 anywhere.
    static func hasMoreThan(_ text: String) -> Bool {
        PatternsV3.greaterThan.contains(text) || text.contains("以上")
    }

    /// The values of a line under parser v3: parser v2's pattern plus ≦ and 未滿, each extended
    /// over a 以下 or 以上 printed straight after it, so the bound stays with its value.
    static func valueMatches(_ content: String) -> [(range: Range<String.Index>, groups: [String?])] {
        PatternsV3.value.matchDetails(in: content).map { match in
            let after = String(content[match.range.upperBound...])
            guard let suffix = PatternsV3.boundSuffix.matchDetails(in: after).first else { return match }
            let end = content.index(match.range.upperBound, offsetBy: after.distance(from: after.startIndex, to: suffix.range.upperBound))
            return (match.range.lowerBound..<end, match.groups + [suffix.groups[1]])
        }
    }

    // MARK: Headers and rows

    mutating func consumeHeader(_ content: String) {
        var segments = Patterns.headerSplit.split(content).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if segments.count == 1 {
            segments = Patterns.headerBoundary.split(content).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var found: [LabelHeader] = []
        for segment in segments {
            // 3.6 rule 1: in a bilingual header the Chinese phrase decides the column's basis. An
            // English part naming a different basis is a misaligned paste and declines; an English
            // part naming none is ignored. An English segment standing after a Chinese one is that
            // column's English part.
            if Self.hasLatinWord(segment), !segment.contains(where: FlattenedLine.isHan), let last = found.last,
               last.printedText.contains(where: FlattenedLine.isHan), !Self.hasLatinWord(last.printedText) {
                if let english = ParseState.basis(of: segment), english != last.basis {
                    declineReasons.append("multiple_panels")
                    return
                }
                found[found.count - 1].printedText += " " + segment
                continue
            }
            let bilingual = Self.bilingualBasis(segment)
            if bilingual.conflict {
                declineReasons.append("multiple_panels")
                return
            }
            guard let basis = bilingual.basis ?? ParseState.basis(of: segment) else {
                unbound.append(segment)
                continue
            }
            var conversion: String?
            if basis == .perServing {
                if let quantity = ParseState.outermostParenthesised(segment) {
                    conversion = quantity
                } else if let groups = Patterns.perQuantity.firstMatch(in: segment) {
                    conversion = groups[1]
                }
            }
            found.append(LabelHeader(headerID: "", printedText: segment, basis: basis, servingConversion: conversion))
        }
        guard !found.isEmpty else { return }
        if rowsWithValues {
            let referenceOnly = found.allSatisfy { $0.basis == .referenceIntake }
            if !(referenceOnly && !headers.contains { $0.basis == .referenceIntake }) {
                declineReasons.append("multiple_panels")
                panelBreak = lineIndex
                return
            }
        }
        for header in found {
            var numbered = header
            numbered.headerID = "header_\(headers.count + 1)"
            headers.append(numbered)
        }
        lastLineWasHeader = true
    }

    /// 3.1 rule 5: a closed set of leading row markers, removed before classification; the
    /// marker counts as indentation. `-` and `*` are markers only before a Han character, and a
    /// line starting with `*` is a row only when what follows is a recognised row (otherwise it
    /// stays a footnote, as in parser v2).
    static func markedRow(_ content: String) -> String? {
        for marker in PatternsV3.rowMarkers where content.hasPrefix(marker) {
            let rest = String(content.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}")))
            // A marker is removed only when a row label follows it: `>` before a number is
            // "more than", never a marker (`>3公克` stays as printed and is never read as exact).
            return startsWithLabel(rest) ? rest : nil
        }
        guard let first = content.first, PatternsV3.hanMarkers.contains(first) else { return nil }
        let rest = String(content.dropFirst())
        guard let next = rest.first, next.unicodeScalars.first.map({ (0x4E00...0x9FFF).contains($0.value) }) == true else { return nil }
        if first == "*" {
            let label = Patterns.value.matchDetails(in: rest).first.map { String(rest[..<$0.range.lowerBound]) } ?? rest
            guard RowClassifierV3.isRowLabel(label.trimmingCharacters(in: .whitespaces)) else { return nil }
        }
        return rest
    }

    /// Whether a text starts with a row label: a letter before its first value.
    static func startsWithLabel(_ text: String) -> Bool {
        let label = Patterns.value.matchDetails(in: text).first.map { String(text[..<$0.range.lowerBound]) } ?? text
        return label.trimmingCharacters(in: .whitespaces).first?.isLetter == true
    }

    /// A `*` line naming a row that is already read (a reference footnote such as `*鈉 2000毫克`
    /// after the table) is a footnote, never a second row.
    func repeatsReadRow(_ content: String) -> Bool {
        guard let rest = Self.markedRow(content) else { return false }
        let label = (Patterns.value.matchDetails(in: rest).first.map { String(rest[..<$0.range.lowerBound]) } ?? rest)
            .trimmingCharacters(in: .whitespaces)
        guard let key = RowClassifierV3.classify(label)?.key else { return false }
        return rows.contains { RowClassifierV3.classify($0.label)?.key == key }
    }

    mutating func consumeRow(rawLine: String, content original: String) {
        var content = original
        var marked = false
        if let rest = Self.markedRow(original) {
            content = rest
            marked = true
        }
        content = Self.spacedLabel(content)
        if BoundVocabulary.isMarkOnly(content) {
            // A line holding only bound marks qualifies the row above (through its span) and the
            // next row: both are not read.
            if rows.isEmpty { pendingMoreThan = true }
            pendingBound = true
            unbound.append(original)
            return
        }
        // 3.6 rule 4: a value printed as number, bracketed English unit, Chinese unit (`4.3(g)公克`)
        // is one value only when both units have the same canonical unit; the English bracket is
        // masked so the value reads with its Chinese unit, and its printed text stays as printed.
        let pairs = Self.maskUnitPairs(content)
        let masked = pairs.masked
        let details = Self.valueMatches(masked)
        let label: String
        if let first = details.first {
            label = String(masked[masked.startIndex..<first.range.lowerBound])
        } else {
            label = masked
        }
        var cleanedLabel = label
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•")))
        // "More than" is not a value the reader can hold: its marks never stay in a label, and the
        // row that receives such a value is not read (`row_not_read: malformed_value`), whether
        // the mark is on the value's line, after the label, or on a line of its own.
        var moreThan = PatternsV3.greaterThan.contains(masked) || details.contains { $0.groups.count > 4 && $0.groups[4] == "以上" }
        if let mark = PatternsV3.trailingGreaterThan.matchDetails(in: cleanedLabel).first {
            cleanedLabel = String(cleanedLabel[..<mark.range.lowerBound])
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•")))
            moreThan = true
        }
        // A number the value pattern had to cut inside its digits (`502千焦`, read as 50 before
        // `2千焦` because 千焦 is not a unit) is not a value either: the row is not read
        // (`malformed_value`), and the rest of the number is never shown as a label. Numbers
        // separated by a space (`120 400`) keep parser v2's unit rules.
        let cutNumber = details.contains { match in
            match.groups[3] == nil && masked[..<match.range.upperBound].last.map { $0.isASCII && $0.isNumber } == true
                && masked[match.range.upperBound...].first.map { $0.isASCII && $0.isNumber } == true
        }
        if cutNumber { moreThan = true }
        // 3.6 rule 3: a bilingual label is read by its Chinese part; an English gloss naming a
        // different nutrient leaves the row unread, and an unknown gloss is ignored.
        var glossConflict = false
        var printedLabel: String?
        var gloss: String?
        if let bilingual = Self.bilingualLabel(cleanedLabel) {
            printedLabel = cleanedLabel
            gloss = bilingual.gloss
            cleanedLabel = bilingual.chinese
            glossConflict = bilingual.conflict
            unbound.append(bilingual.gloss)
        }
        // 3.6 rule 2: Latin words on a row are allowed in its gloss or inside a bracket.
        var latinRest = masked
        if let gloss { latinRest = latinRest.replacingOccurrences(of: gloss, with: " ") }
        latinRest = Patterns.parenthesised.split(latinRest).joined(separator: " ")
        if !Self.hasLatinWord(latinRest) { currentLineLatinAllowed = true }
        // A wrapped label (`碳水化` then `合物 1,5公克`) is checked under its merged label.
        let mergedLabel: String? = {
            guard !cleanedLabel.isEmpty, let last = rows.last, last.values.isEmpty, RowClassifierV3.classify(last.label) == nil,
                  RowClassifierV3.classify(cleanedLabel) == nil || RowClassifierV3.classify(last.label + " " + cleanedLabel) != nil
            else { return nil }
            return last.label + " " + cleanedLabel
        }()
        // A number whose comma may be a thousands separator (`1,203毫克`, which a decimal comma
        // would make 1.203), or any comma on a Taiwan row (the template prints a decimal point),
        // is not a value the reader can bind either: the row is not read (`ambiguous_number`).
        let rowLabel = cleanedLabel.isEmpty ? (rows.last?.label ?? "") : (mergedLabel ?? cleanedLabel)
        let ambiguous = details.contains { Self.isAmbiguousNumber($0.groups[2] ?? "", label: rowLabel) }
        if moreThan, cleanedLabel.isEmpty, details.isEmpty {
            // A line holding only the mark: it qualifies the row above, or the next row.
            if rows.isEmpty {
                pendingMoreThan = true
            } else {
                rows[rows.count - 1].malformed = true
                rows[rows.count - 1].lines.append(original)
            }
            unbound.append(original)
            return
        }
        let values = details.map { match -> PrintedValue in
            let printed = Self.slice(content, like: masked, match.range).trimmingCharacters(in: .whitespaces)
            let comparator: LabelComparator
            switch match.groups[1] {
            case "<=", "≤", "≦": comparator = .lessOrEqual
            case nil: comparator = match.groups.count > 4 && match.groups[4] == "以下" ? .lessOrEqual : .equal
            default: comparator = .less
            }
            return PrintedValue(printedText: printed, comparator: comparator, decimalText: match.groups[2] ?? "", unit: match.groups[3])
        }
        let indented = rawLine.hasPrefix("\u{3000}") || rawLine.hasPrefix("  ") || rawLine.hasPrefix(" \t")
        if !cleanedLabel.isEmpty {
            rowsStarted = true
            body.append(values.isEmpty ? .labelOnly : .labelWithValues(secondLabel: Self.hasSecondLabel(masked, values: details)))
            if mergedLabel != nil, var last = rows.last {
                last.label += " " + cleanedLabel
                last.labelLines += 1
                last.values = values
                lineGaveValues = !values.isEmpty
                last.labelLineHadValues = !values.isEmpty
                last.lines.append(original)
                last.malformed = last.malformed || moreThan
                last.ambiguous = last.ambiguous || ambiguous
                last.unitPairMismatch = last.unitPairMismatch || pairs.mismatch
                rows[rows.count - 1] = last
            } else {
                lineGaveValues = !values.isEmpty
                var row = RowDraftV3(label: cleanedLabel, indented: indented, values: values, labelLineHadValues: !values.isEmpty,
                                     lines: [original], marked: marked, malformed: moreThan || pendingMoreThan, orphanBound: pendingBound)
                row.ambiguous = ambiguous
                row.glossConflict = glossConflict
                row.unitPairMismatch = pairs.mismatch
                row.printedLabel = printedLabel
                rows.append(row)
                pendingBound = false
                pendingMoreThan = false
            }
        } else if !values.isEmpty {
            guard !rows.isEmpty else {
                declineReasons.append("values_without_row")
                return
            }
            body.append(.valuesOnly)
            // A value line carrying label text after (or between) its values (`>1公克 飽和脂肪`):
            // the values belong to that label, not to the row above, so the line is never
            // attached; the label is listed as printed but not read. A cut number (`502千焦`) is
            // not a label: the line is the row above's malformed value instead.
            if !cutNumber, let dropped = Self.labelAfterValues(masked, values: details) {
                droppedLabels.append(dropped)
                unbound.append(original)
                return
            }
            // As parser v2 (`ParseState.consumeRow`): a value-only line attaches to the last row;
            // after a label line that carried values it blocks ready unless it is the energy
            // row's kJ and kcal continuation.
            var last = rows[rows.count - 1]
            if last.labelLineHadValues, !Self.isStackedEnergy(row: last, adding: values) {
                last.attachedAfterValues = true
            }
            last.values += values
            last.valueLines.append(values.map { $0.unit.flatMap(LabelVocabulary.canonicalUnit) })
            lineGaveValues = true
            last.lines.append(original)
            last.malformed = last.malformed || moreThan
            last.ambiguous = last.ambiguous || ambiguous
            last.unitPairMismatch = last.unitPairMismatch || pairs.mismatch
            rows[rows.count - 1] = last
        } else {
            unbound.append(original)
        }
    }

    /// Whether a line holds two rows after its first value: any Han text between two values
    /// (`脂肪 10公克 其中飽和脂肪 3公克`; no substring alias matching), or a gap that names a row in
    /// the alias or English table.
    static func hasSecondLabel(_ content: String, values: [(range: Range<String.Index>, groups: [String?])]) -> Bool {
        let gaps = gaps(content, values: values)
        if gaps.dropLast().contains(where: { PatternsV3.hanRun.contains($0) }) { return true }
        let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•/,，、;；|()（）*＊†>▲●"))
        for gap in gaps {
            let text = gap.trimmingCharacters(in: trim)
            if text.isEmpty { continue }
            if RowClassifierV3.isRowLabel(text) { return true }
            if PatternsV3.hanRun.matches(in: text).contains(where: RowClassifierV3.isRowLabel) { return true }
        }
        return false
    }

    /// A printed number with a comma followed by exactly three digits (a thousands separator or
    /// a decimal comma, which cannot be told apart), or any comma on a Taiwan alias row.
    static func isAmbiguousNumber(_ number: String, label: String) -> Bool {
        guard let comma = number.firstIndex(of: ",") else { return false }
        return number[number.index(after: comma)...].count == 3 || RowClassifierV3.classify(label)?.isTaiwanAlias == true
    }

    /// The label text a value-only line carries after or between its values, once bound words
    /// and marks are removed, or nil when it carries none.
    static func labelAfterValues(_ content: String, values: [(range: Range<String.Index>, groups: [String?])]) -> String? {
        let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•/,，、;；|()（）*＊†<>＜＞▲●"))
        let texts = zip(gaps(content, values: values), values).compactMap { gap, value -> String? in
            var text = gap
            // A reference-intake suffix after a percentage (`5% DV`, `5% Daily Value`, `5%
            // 每日參考值百分比`) names the cell's column, not a row.
            if value.groups[3] == "%" {
                text = PatternsV3.referenceSuffix.split(text).joined(separator: " ")
            }
            for word in BoundVocabulary.english.matches(in: text.lowercased()) {
                text = text.replacingOccurrences(of: word, with: " ", options: .caseInsensitive)
            }
            for mark in BoundVocabulary.marks.matches(in: text) { text = text.replacingOccurrences(of: mark, with: " ") }
            guard text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
            return gap.trimmingCharacters(in: trim)
        }
        return texts.isEmpty ? nil : texts.joined(separator: " ")
    }

    /// The texts after each value of a line (the last one runs to the end of the line).
    static func gaps(_ content: String, values: [(range: Range<String.Index>, groups: [String?])]) -> [String] {
        guard let first = values.first else { return [] }
        var gaps: [String] = []
        var cursor = first.range.upperBound
        for value in values.dropFirst() {
            gaps.append(String(content[cursor..<value.range.lowerBound]))
            cursor = value.range.upperBound
        }
        gaps.append(String(content[cursor...]))
        return gaps
    }

    // MARK: 3.4: flattened lines

    /// A whole table on one line (3.4, `FlattenedLine`). Returns false when the line is not a
    /// flattened table, so the other rules read it.
    mutating func consumeFlattened(_ content: String) -> Bool {
        let outcome = FlattenedLine.read(content, existingHeaders: headers.map(\.basis))
        let table: FlattenedLine.Table
        switch outcome {
        case .notFlattened:
            return false
        case .secondPanel:
            unbound.append(content)
            declineReasons.append("multiple_panels")
            panelBreak = lineIndex
            return true
        case let .declined(code):
            // Gate input coverage still applies to a declined line: a marker declines with the
            // gate's own code first.
            unbound.append(content)
            declineReasons.append(code)
            return true
        case let .table(read):
            table = read
        }
        // A basis phrase of its own after rows that carried values is a second panel.
        if !table.headers.isEmpty, rows.contains(where: { !$0.values.isEmpty }) {
            declineReasons.append("multiple_panels")
            panelBreak = lineIndex
            return true
        }
        lineWasFlattened = true
        currentLineLatinAllowed = true
        rowsStarted = true
        lastLineWasHeader = false
        // The whole line is gate-scanned (3.0): it is consumed by a rule the gate never sees.
        unbound.append(content)
        unbound += table.unbound
        if let serving = table.serving {
            if !servingClaimed, let value = PatternsV3.servingSize.firstMatch(in: serving.printed)?[1] {
                servingSize = Self.servingSize(printed: serving.printed, value: value)
                extraWarnings += Self.servingLineWarnings(line: serving.printed, value: value).filter { $0.hasSuffix("serving_size") }
            } else {
                unbound.append(serving.printed)
            }
        }
        if let pack = table.pack {
            // PR 3 re-review: the serving and pack segments of the physical line are compared
            // together (an English count in the serving bracket counts), and scanned together
            // for approximation, as on a serving line holding a pack phrase.
            let combined = ([table.serving?.printed, pack.printed].compactMap { $0 }).joined(separator: " ")
            let bilingual = Self.bilingualPackCount(Self.packRest(combined))
            if !packClaimed, BoundVocabulary.tokens(pack.printed).isEmpty, !PatternsV3.oddNumber.contains(pack.printed),
               let groups = PatternsV3.servingsPerPack[2].firstMatch(in: pack.printed), let number = groups[2], !Self.hasNonASCIIDigits(number) {
                switch bilingual {
                case .none:
                    unbound.append(pack.printed)
                    extraWarnings.append(Self.bilingualConflictWarning + "servings_per_pack")
                case let .some(.some(chinese)):
                    let approximate = groups[1] != nil || Self.bilingualApproximate(Self.packRest(combined))
                    servingsPerPack = LabelServingsPerPack(printedText: pack.printed, decimalText: chinese, approximate: approximate)
                case .some(nil):
                    servingsPerPack = LabelServingsPerPack(printedText: pack.printed, decimalText: number, approximate: groups[1] != nil)
                }
            } else {
                unbound.append(pack.printed)
            }
        }
        for header in table.headers {
            headers.append(LabelHeader(headerID: "header_\(headers.count + 1)", printedText: header.printed, basis: header.basis, servingConversion: nil))
        }
        for row in table.rows {
            // A malformed token is kept as a value with no unit so the row reaches the malformed
            // check (it is never bound); a `*` reference mark binds nothing.
            let values = row.cells.compactMap { cell -> PrintedValue? in
                switch cell {
                case let .value(decimal, unit, comparator, printed):
                    PrintedValue(printedText: printed, comparator: comparator, decimalText: decimal, unit: unit)
                case let .malformed(printed):
                    PrintedValue(printedText: printed, comparator: .equal, decimalText: "", unit: nil)
                case .star:
                    nil
                }
            }
            rows.append(RowDraftV3(label: row.label, indented: false, values: values, labelLineHadValues: true, lines: [row.printed],
                                   marked: false, malformed: row.malformed, orphanBound: row.unexplained))
        }
        body.append(.flattened)
        return true
    }

    /// A recognised Chinese row label printed straight against its number (`熱量51大卡`, the shape
    /// of 3.5's layout): one space is put between them so the value reads as it would with a
    /// space. Only a whole leading Han run that is a recognised row label qualifies (exact match,
    /// never a prefix), so no other text is split.
    static func spacedLabel(_ text: String) -> String {
        guard let groups = PatternsV3.stuckLabel.firstMatch(in: text), let label = groups[1],
              TaiwanRowAliases.isRecognisedChinese(label) else { return text }
        return label + " " + String(text.dropFirst(label.count))
    }

    // MARK: 3.5: basis printed only in the energy line

    /// The bracket groups of a row line (a label, then a value, then the bracket) whose content is
    /// a basis phrase, or nil when the line is not such a row.
    static func rowBasisBrackets(_ content: String) -> [(range: Range<String.Index>, printed: String, basis: LabelBasis)]? {
        let text = spacedLabel(markedRow(content) ?? content)
        // The bracket may stand after the value (`熱量 45大卡(每100毫升)`) or inside the label
        // (`熱量(每100毫升) 45大卡`, PR 3 review): either way the line is a row with a value, never
        // a header line, so its value is never dropped.
        guard startsWithLabel(text), !valueMatches(text).isEmpty else { return nil }
        let brackets = Patterns.parenthesised.matchDetails(in: text).compactMap { match -> (range: Range<String.Index>, printed: String, basis: LabelBasis)? in
            guard let inner = match.groups[1], let basis = ParseState.basis(of: inner) else { return nil }
            return (match.range, String(text[match.range]), basis)
        }
        guard !brackets.isEmpty else { return nil }
        // Only a recognised row label with its brackets removed makes this a row: a header line
        // with bracketed bases (`每份(Amount Per Serving) 每100公克(100g)`) stays a header line.
        var row = text
        for bracket in brackets { row = row.replacingOccurrences(of: bracket.printed, with: " ") }
        row = spacedLabel(row.trimmingCharacters(in: .whitespaces))
        guard let first = valueMatches(row).first else { return nil }
        let label = String(row[..<first.range.lowerBound]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•")))
        return RowClassifierV3.isRowLabel(label) || bilingualLabel(label) != nil ? brackets : nil
    }

    /// 3.5 as decided (decision 23, owner, 20 October 2026: ask the user): with no header line, the
    /// energy row first and exactly one bracketed basis phrase on it, the phrase is **not** taken
    /// as the column's basis. The table has no basis header, so it declines `no_basis_header` as
    /// today, and the candidate carries the phrase as printed in the warning
    /// `basis_hint: energy_line: <bracket>` for the basis-choice sheet of PR 4, which may show it
    /// as a hint and never preselects it. A basis phrase on any other row, on a first row that is
    /// not energy, or more than one, declines `multiple_panels`.
    mutating func consumeEnergyLineBasis(_ content: String, brackets: [(range: Range<String.Index>, printed: String, basis: LabelBasis)]) {
        let text = Self.spacedLabel(Self.markedRow(content) ?? content)
        guard brackets.count == 1, let bracket = brackets.first, bracket.basis != .referenceIntake else {
            declineReasons.append("multiple_panels")
            return
        }
        var row = text
        if let range = row.range(of: bracket.printed, options: .backwards) { row.replaceSubrange(range, with: " ") }
        row = Self.spacedLabel(row.trimmingCharacters(in: .whitespaces))
        let label = Self.valueMatches(row).first.map { String(row[..<$0.range.lowerBound]) }?
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}\t:：-–·•"))) ?? ""
        let amountHeaders = headers.filter { $0.basis != .referenceIntake }
        if amountHeaders.count == 1, amountHeaders[0].basis == bracket.basis, basisHint == nil,
           bracketRepeats(bracket.printed, header: amountHeaders[0]) {
            // A printed header line already names this basis: the bracket repeats it, and the row
            // reads as a row (its value is never dropped).
            unbound.append(bracket.printed)
            consumeRow(rawLine: row, content: row)
            return
        }
        guard headers.isEmpty, !rows.contains(where: { !$0.values.isEmpty }), RowClassifierV3.classify(label)?.row == .energy,
              basisHint == nil else {
            declineReasons.append("multiple_panels")
            return
        }
        basisHint = bracket.printed
        unbound.append(bracket.printed)
        consumeRow(rawLine: row, content: row)
    }

    /// PR 3 re-review: a row's basis bracket repeats the printed header only when it adds no
    /// quantity, or, for a per-serving bracket, a quantity equal to the header's serving
    /// conversion and to the serving size read (every one of them that is known, at least one).
    /// `熱量 120大卡(每份25公克)` under `每份(30公克)` does not repeat it.
    func bracketRepeats(_ bracket: String, header: LabelHeader) -> Bool {
        let rest = PatternsV3.per100Phrase.split(bracket).joined(separator: " ")
        let quantities = PatternsV3.anyQuantity.matchDetails(in: rest).map { ($0.groups[1] ?? "", $0.groups[2] ?? "") }
        guard !quantities.isEmpty else { return true }
        guard header.basis == .perServing else { return false }
        func key(_ number: String, _ unit: String) -> String? {
            guard let decimal = Self.asciiDecimal(number), let canonical = PatternsV3.servingUnitWords[unit.lowercased()] ?? LabelVocabulary.canonicalUnit(unit)
            else { return nil }
            return "\(decimal)|\(canonical)"
        }
        var references: [String?] = []
        if let conversion = header.servingConversion {
            if let groups = PatternsV3.servingQuantity.firstMatch(in: conversion), let number = groups[1], let unit = groups[2] {
                references.append(key(number, unit))
            } else {
                references.append(nil)
            }
        }
        if let size = servingSize, let number = size.decimalText, let unit = size.unit { references.append(key(number, unit)) }
        if let join = servingJoin, let groups = PatternsV3.servingQuantity.firstMatch(in: join.quantity), let number = groups[1], let unit = groups[2] {
            references.append(key(number, unit))
        }
        guard !references.isEmpty, references.allSatisfy({ $0 != nil }) else { return false }
        let known = Set(references.compactMap { $0 })
        return known.count == 1 && quantities.allSatisfy { key($0.0, $0.1).map(known.contains) == true }
    }

    // MARK: 3.6: bilingual tables

    /// Latin words a language check counts: two or more letters that are not a unit.
    static func hasLatinWord(_ text: String) -> Bool {
        let unitWords: Set<String> = ["kj", "kcal", "cal", "mg", "mcg", "ml"]
        return Patterns.latinWord.matches(in: text).contains { !unitWords.contains($0.lowercased()) }
    }

    /// 3.6 rule 3: a label made of a recognised Chinese row label and an English gloss after it
    /// (`脂肪 Total Fat`, `脂肪(Total Fat)`). The Chinese part classifies the row; the gloss is a
    /// conflict when the English row table names a different nutrient, and is ignored when it
    /// names none.
    static func bilingualLabel(_ label: String) -> (chinese: String, gloss: String, conflict: Bool)? {
        guard let latin = label.firstIndex(where: { $0.isASCII && $0.isLetter }) else { return nil }
        let chinese = String(label[..<latin]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}(（")))
        let gloss = String(label[latin...]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ")）")))
        guard !chinese.isEmpty, TaiwanRowAliases.isRecognisedChinese(chinese), hasLatinWord(gloss),
              !gloss.contains(where: { FlattenedLine.isHan($0) || $0.isNumber }) else { return nil }
        let english = gloss.replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "（", with: " ").replacingOccurrences(of: "）", with: " ")
        let conflict: Bool
        if let alias = TaiwanRowAliases.entry(chinese), let named = RowClassifier.classify(english) {
            conflict = RowClassifier.key(for: named.row) != RowClassifier.key(for: alias.row)
        } else {
            conflict = false
        }
        return (chinese, gloss, conflict)
    }

    /// 3.6 rule 1: the basis of a header segment holding both a Chinese and an English phrase is
    /// the Chinese phrase's; an English phrase naming a different basis is a conflict.
    static func bilingualBasis(_ segment: String) -> (basis: LabelBasis?, conflict: Bool) {
        guard segment.contains(where: FlattenedLine.isHan), hasLatinWord(segment) else { return (nil, false) }
        let unitWords: Set<String> = ["kj", "kcal", "cal", "mg", "mcg", "ml"]
        var chinese = segment
        for word in Patterns.latinWord.matches(in: segment) where !unitWords.contains(word.lowercased()) {
            chinese = chinese.replacingOccurrences(of: word, with: " ")
        }
        let english = String(segment.filter { !FlattenedLine.isHan($0) })
        guard let chineseBasis = ParseState.basis(of: chinese) else { return (nil, false) }
        if let englishBasis = ParseState.basis(of: english), englishBasis != chineseBasis { return (chineseBasis, true) }
        return (chineseBasis, false)
    }

    /// 3.6 rule 4: number, bracketed English unit, Chinese unit (`4.3(g)公克`). The English bracket
    /// is replaced by spaces (so the text keeps its length and every value its printed text), and
    /// `mismatch` is true when any pair's canonical units differ.
    static func maskUnitPairs(_ content: String) -> (masked: String, mismatch: Bool) {
        let matches = PatternsV3.unitPair.matchDetails(in: content)
        guard !matches.isEmpty else { return (content, false) }
        var mismatch = false
        var masked = ""
        var cursor = content.startIndex
        for match in matches {
            guard let bracket = match.groups[2], let english = match.groups[3], let chinese = match.groups[4] else { continue }
            if LabelVocabulary.canonicalUnit(english) != LabelVocabulary.canonicalUnit(chinese) { mismatch = true }
            guard let start = content[match.range].range(of: bracket)?.lowerBound else { continue }
            masked += content[cursor..<start] + String(repeating: " ", count: bracket.count)
            cursor = content.index(start, offsetBy: bracket.count)
        }
        masked += content[cursor...]
        return (masked, mismatch)
    }

    /// The text of `original` at the character offsets `range` has in `masked` (same length).
    static func slice(_ original: String, like masked: String, _ range: Range<String.Index>) -> String {
        guard original != masked else { return String(original[range]) }
        let lower = masked.distance(from: masked.startIndex, to: range.lowerBound)
        let upper = masked.distance(from: masked.startIndex, to: range.upperBound)
        return String(original[original.index(original.startIndex, offsetBy: lower)..<original.index(original.startIndex, offsetBy: upper)])
    }

    /// A bilingual serving line (Han and a Latin word) whose quantities disagree in number or
    /// canonical unit.
    static func bilingualQuantitiesDisagree(serving cut: String, line: String) -> Bool {
        guard line.contains(where: FlattenedLine.isHan), hasLatinWord(line) else { return false }
        // Every quantity counts: full-width digits are folded first, a number that still cannot
        // be parsed is a conflict (never skipped), and an English quantity in any unit
        // (`25 grams`, `1 oz`) is one too (PR 3 re-review).
        var quantities: Set<String> = []
        for match in PatternsV3.anyQuantity.matchDetails(in: cut) {
            guard let number = match.groups[1], let unit = match.groups[2], let decimal = asciiDecimal(number) else { return true }
            let key = unit.lowercased()
            if let canonical = PatternsV3.servingUnitWords[key] {
                quantities.insert("\(decimal)|\(canonical)")
            } else if PatternsV3.otherMeasureUnits.contains(key) || LabelVocabulary.canonicalUnit(unit) != nil {
                // A weight or volume in another unit (oz, cup, mg …) can never match: not read.
                return true
            }
            // A count word (`2 pieces`, `1 bar`) is not a quantity of weight or volume.
        }
        return quantities.count > 1
    }

    /// A printed number as a decimal, with full-width digits and point folded to ASCII, or nil
    /// when it is not a plain decimal.
    static func asciiDecimal(_ text: String) -> Decimal? {
        let folded = String(text.unicodeScalars.map { scalar -> Character in
            if (0xFF10...0xFF19).contains(scalar.value) { return Character(UnicodeScalar(scalar.value - 0xFEE0)!) }
            if scalar == "．" { return "." }
            return Character(scalar)
        })
        guard folded.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        return Decimal(string: folded)
    }

    /// Whether a printed number holds anything but ASCII digits and a point (full-width or
    /// other script digits): such a number is never bound as a serving size or pack count.
    static func hasNonASCIIDigits(_ text: String) -> Bool {
        // Decimal digits outside ASCII (full-width and other scripts); Han numerals such as the
        // 一 of 每一份量 are words, not digits.
        text.unicodeScalars.contains { !$0.isASCII && $0.properties.generalCategory == .decimalNumber }
    }

    /// A bilingual pack line (Han and a Latin word): the Chinese phrase decides the count, and
    /// every number on the line must equal it (`Servings per package: 3 本包裝含 2份` is not read).
    /// Returns the Chinese count, or nil when the line is not read; `.some(nil)` when not bilingual.
    /// A number that cannot be parsed (after folding full-width digits) makes the line not read.
    static func bilingualPackCount(_ line: String) -> String?? {
        guard line.contains(where: FlattenedLine.isHan), hasLatinWord(line) else { return .some(nil) }
        guard let chinese = PatternsV3.chinesePackAnywhere.firstMatch(in: line)?[2], !hasNonASCIIDigits(chinese),
              let count = asciiDecimal(chinese) else { return nil }
        for number in PatternsV3.number.matches(in: line) {
            guard let value = asciiDecimal(number), value == count else { return nil }
        }
        return .some(chinese)
    }

    /// 3.6 rule 5: on a Chinese serving or pack line, the English words and marks of serving v3's
    /// approximation lists anywhere on the line make the count approximate (the conservative side).
    static func bilingualApproximate(_ line: String) -> Bool {
        guard line.contains(where: FlattenedLine.isHan), hasLatinWord(line) else { return false }
        if PatternsV3.approximateMarks.contains(where: line.contains) { return true }
        let words = line.lowercased().split { !($0.isASCII && $0.isLetter) }.map(String.init)
        return words.contains { PatternsV3.approximateWords.contains($0) }
    }

    /// Whether a line has Han text between two of its values (the non-regression allow-list).
    static func hasHanBetweenValues(_ line: String) -> Bool {
        gaps(line, values: valueMatches(line)).dropLast().contains { PatternsV3.hanRun.contains($0) }
    }

    static func isStackedEnergy(row: RowDraftV3, adding values: [PrintedValue]) -> Bool {
        guard RowClassifierV3.classify(row.label)?.row == .energy else { return false }
        let energyUnits = LabelVocabulary.allowedUnits(for: .energy)
        let existing = Set(row.values.compactMap { $0.unit.flatMap(LabelVocabulary.canonicalUnit) })
        let added = values.map { $0.unit.flatMap(LabelVocabulary.canonicalUnit) }
        let addsEnergy = added.contains { unit in unit.map { energyUnits.contains($0) && !existing.contains($0) } ?? false }
        let allowed = added.allSatisfy { unit in
            guard let unit else { return false }
            if unit == "%" { return !existing.contains("%") }
            return energyUnits.contains(unit) && !existing.contains(unit)
        }
        return addsEnergy && allowed
    }

    // MARK: Binding

    mutating func finish(route: String, inputSHA256: String, language textLanguage: LabelLanguage) -> LabelCaptureCandidate {
        // 3.6 rule 2: a text whose rows all start with a recognised Chinese row label is `zh-Hant`
        // even with Latin words, when every Latin word is in a gloss, a bracket, or a title,
        // header, serving or pack line.
        let language: LabelLanguage = textLanguage == .mixed && !latinOutsideAllowed && !rows.isEmpty
            && rows.allSatisfy { TaiwanRowAliases.isRecognisedChinese($0.label) } ? .traditionalChinese : textLanguage
        func decline(_ reasons: [String]) -> LabelCaptureCandidate {
            .declined(route: route, inputSHA256: inputSHA256, language: language, reasons: reasons)
        }
        if let label = pending {
            unbound.append(Self.text(of: label))
            pending = nil
        }
        // Layout precedence (3.0) on a body that carries values.
        var layout: LabelLayout?
        if declineReasons.isEmpty, body.contains(where: { $0 != .labelOnly }) {
            layout = LabelLayout.classify(body)
            if layout == nil { declineReasons.append(LabelLayout.ambiguousCode) }
        }

        var warnings: [String] = extraWarnings
        // 3.1 rules 3 and 4: a split serving or pack line is joined only outside stacked tables
        // and with no `stacked_sequence` unread row; otherwise it is not read. Such a row only
        // arises in a stacked table (3.2), so refusing every stacked table covers both conditions.
        let joinAllowed = layout != nil && layout != .stacked
        if let join = servingJoin {
            if joinAllowed {
                let printed = Self.joined(join)
                let groups = PatternsV3.servingSize.firstMatch(in: printed)
                servingSize = Self.servingSize(printed: printed, value: groups?[1] ?? join.quantity)
                warnings.append(Self.joinedWarning)
            } else {
                unbound += [join.label, join.quantity]
            }
        }
        if let (join, approximate, decimal) = packJoin {
            if joinAllowed {
                servingsPerPack = LabelServingsPerPack(printedText: Self.joined(join), decimalText: decimal, approximate: approximate)
                warnings.append(Self.joinedPackWarning)
            } else {
                unbound += [join.label, join.quantity]
            }
        }

        let amountHeaders = headers.filter { $0.basis != .referenceIntake }
        let referenceHeaders = headers.filter { $0.basis == .referenceIntake }
        var cells: [LabelCell] = []
        var lastTopLevel: String?
        // A marker counts as indentation only after a marker-free top-level row, so bullets on
        // every row never chain one row under another (3.1 rule 5).
        var lastTopLevelMarked = false
        var bindingDecline: [String]?
        var cellRows: [Int] = []
        if declineReasons.isEmpty, !rows.isEmpty, !amountHeaders.isEmpty {
            let byBasis = Dictionary(grouping: headers, by: \.basis)
            for (_, group) in byBasis where group.count > 1 {
                let texts = Set(group.map { $0.printedText.lowercased().replacingOccurrences(of: " ", with: "") })
                if texts.count < group.count { bindingDecline = ["duplicate_basis"] }
            }
        }
        // 3.2: in a stacked table, the first deviation from the regular sequence (or from the
        // Taiwan template order) and every row after it are not read.
        let firstDeviation = layout == .stacked
            ? Self.firstStackedDeviation(rows, amountColumns: amountHeaders.count, referenceColumns: referenceHeaders.count) : nil
        if declineReasons.isEmpty, bindingDecline == nil, !rows.isEmpty, !amountHeaders.isEmpty {
            rowLoop: for (index, row) in rows.enumerated() {
                if let firstDeviation, index >= firstDeviation {
                    warnings.append("row_not_read: stacked_sequence: \(row.label)")
                    unbound += row.lines
                    continue
                }
                let classified = RowClassifierV3.classify(row.label)
                // Known top-level rows stay top-level however they are marked, as on the alias path.
                let topLevel = classified.map { Self.topLevelKeys.contains($0.key) } ?? false
                let indented = row.indented || (row.marked && lastTopLevel != nil && !lastTopLevelMarked && !topLevel)
                let rowKey: String
                let parent: String?
                switch classified {
                case let .some(match):
                    rowKey = match.key
                    if let fixed = match.fixedParent {
                        parent = fixed
                    } else if match.isTaiwanAlias {
                        // The alias table names every Taiwan row's parent (section 4): a top-level
                        // row stays top-level however it is indented or marked (3.1 rule 5).
                        parent = nil
                    } else if match.ofWhich || indented {
                        parent = lastTopLevel
                    } else {
                        parent = nil
                    }
                case nil:
                    rowKey = "row_\(index + 1)"
                    parent = (RowClassifier.hasOfWhich(row.label) || indented) ? lastTopLevel : nil
                    warnings.append("unrecognised_row: \(row.label)")
                }
                if parent == nil {
                    lastTopLevel = rowKey == "energy" ? nil : rowKey
                    lastTopLevelMarked = row.marked
                }
                if row.values.isEmpty {
                    warnings.append("row_without_values: \(row.label)")
                    unbound += row.lines
                    continue
                }
                if row.malformed {
                    warnings.append("row_not_read: malformed_value: \(row.label)")
                    unbound += row.lines
                    continue
                }
                if row.ambiguous {
                    warnings.append("row_not_read: ambiguous_number: \(row.label)")
                    unbound += row.lines
                    continue
                }
                // 3.6 rules 3 and 4: a gloss naming another nutrient, or two units that disagree.
                if row.glossConflict {
                    warnings.append("row_not_read: gloss_conflict: \(row.printedLabel ?? row.label)")
                    unbound += row.lines
                    continue
                }
                if row.unitPairMismatch {
                    warnings.append("row_not_read: unit_pair_mismatch: \(row.printedLabel ?? row.label)")
                    unbound += row.lines
                    continue
                }
                // Every bound token in the row's span must be a recognised bound on one of its
                // cells (`<`, `≤`, `≦`, `以下`, `未滿` and the like); any other makes the row unread.
                // A leading row marker (`>`, `>>`) is a marker, not a bound.
                // The span's lines are tokenised joined, so a mark split over lines (`以\n上`) counts.
                let span = spans[index] ?? []
                let spanLines = span.map { Self.markedRow($0.line) ?? $0.line }
                let spanTokens = BoundVocabulary.tokens(spanLines.joined(separator: "\n")).count
                let consumed = zip(spanLines, span).filter { $0.1.valueLine }.map { Self.consumedTokens($0.0) }.reduce(0, +)
                if row.orphanBound || spanTokens > consumed {
                    warnings.append("row_not_read: unexplained_bound: \(row.label)")
                    unbound += row.lines
                    continue
                }
                if row.attachedAfterValues {
                    warnings.append("values_after_complete_row: \(row.label)")
                }
                let hint = RowClassifier.unitHint(row.label)
                var amounts: [PrintedValue] = []
                var percentages: [PrintedValue] = []
                for var value in row.values {
                    if value.unit == nil { value.unit = hint }
                    guard let unit = value.unit else {
                        bindingDecline = [classified?.row == .energy ? "energy_without_unit" : "value_without_unit"]
                        break rowLoop
                    }
                    guard let canonical = LabelVocabulary.canonicalUnit(unit) else { bindingDecline = ["unrecognised_unit"]; break rowLoop }
                    if canonical == "%" { percentages.append(value) } else { amounts.append(value) }
                }
                if let match = classified {
                    for value in amounts {
                        let canonical = LabelVocabulary.canonicalUnit(value.unit ?? "") ?? ""
                        guard LabelVocabulary.allowedUnits(for: match.row).contains(canonical) else {
                            bindingDecline = ["unrecognised_unit"]
                            break rowLoop
                        }
                    }
                    // 3.9: a mandatory Taiwan row whose unit is not the template's is not read
                    // (energy reads kcal or kJ, as under v1).
                    if let template = match.templateUnit, amounts.contains(where: { value in
                        !TaiwanRowAliases.readableUnits(template: template).contains(LabelVocabulary.canonicalUnit(value.unit ?? "") ?? "")
                    }) {
                        warnings.append("row_not_read: unit_off_template: \(row.label)")
                        unbound += row.lines
                        continue
                    }
                }
                if !percentages.isEmpty, percentages.count != referenceHeaders.count {
                    bindingDecline = ["count_mismatch"]
                    break rowLoop
                }
                var groups: [(key: String, values: [PrintedValue])] = []
                if classified?.row == .energy {
                    for value in amounts {
                        let canonical = LabelVocabulary.canonicalUnit(value.unit ?? "") ?? ""
                        let key = canonical == "kJ" ? "energy_kj" : "energy_kcal"
                        if let position = groups.firstIndex(where: { $0.key == key }) {
                            groups[position].values.append(value)
                        } else {
                            groups.append((key, [value]))
                        }
                    }
                } else {
                    groups = amounts.isEmpty ? [] : [(rowKey, amounts)]
                }
                if groups.contains(where: { $0.values.count != amountHeaders.count }) {
                    bindingDecline = ["count_mismatch"]
                    break rowLoop
                }
                let nutrientFor: (String) -> String = { key in classified == nil ? "unrecognised" : key }
                for group in groups {
                    for (header, value) in zip(amountHeaders, group.values) {
                        cellRows.append(index)
                        cells.append(ParseState.cell(rowID: group.key, parent: parent, nutrient: nutrientFor(group.key), label: row.label,
                                                     header: header, value: value, servingSize: servingSize))
                    }
                }
                let energyKeys = groups.map(\.key)
                let percentKey = classified?.row == .energy ? (energyKeys.contains("energy_kcal") ? "energy_kcal" : (energyKeys.first ?? "energy_kcal")) : rowKey
                for (header, value) in zip(referenceHeaders, percentages) {
                    cellRows.append(index)
                    cells.append(ParseState.cell(rowID: percentKey, parent: parent, nutrient: nutrientFor(percentKey), label: row.label,
                                                 header: header, value: value, servingSize: servingSize))
                }
            }
        }

        // Two rows binding the same nutrient in the same column: the reader never picks one, so
        // both rows are not read and the row's flag shows on Confirm (`row_not_read: duplicate_row`).
        // Duplicates are counted over every row with a recognised label, read or not (a row left
        // unread for a bound, a stacked deviation or a malformed value still names its nutrient),
        // so an unread row never lets a later row of the same nutrient be read in its place.
        var rowsByCell: [String: Set<Int>] = [:]
        var rowsByNutrient: [String: Set<Int>] = [:]
        for (cell, row) in zip(cells, cellRows) where cell.nutrient != "unrecognised" {
            rowsByCell[cell.nutrient + "@" + cell.headerID, default: []].insert(row)
            rowsByNutrient[cell.nutrient, default: []].insert(row)
        }
        let boundRows = Set(rowsByNutrient.values.flatMap { $0 })
        var unboundByNutrient: [String: Set<Int>] = [:]
        if bindingDecline == nil {
            for (index, row) in rows.enumerated() where !boundRows.contains(index) {
                for key in Self.duplicateKeys(row) { unboundByNutrient[key, default: []].insert(index) }
            }
        }
        var duplicated = Set(rowsByCell.values.filter { $0.count > 1 }.flatMap { $0 })
        for (key, unboundRows) in unboundByNutrient {
            let all = unboundRows.union(rowsByNutrient[key] ?? [])
            if all.count > 1 { duplicated.formUnion(all) }
        }
        let duplicatedBound = duplicated.intersection(Set(cellRows))
        if !duplicatedBound.isEmpty {
            cells = zip(cells, cellRows).filter { !duplicatedBound.contains($0.1) }.map(\.0)
            for index in duplicatedBound.sorted() {
                warnings.append("row_not_read: duplicate_row: \(rows[index].label)")
                unbound += rows[index].lines
            }
        }
        for label in droppedLabels {
            warnings.append("row_not_read: value_before_label: \(label)")
        }

        // 3.0, gate input coverage: the gate's own marker and script functions over every
        // consumed but unbound line; a hit declines with the gate's existing code.
        let coverage = Self.coverageDeclines(unbound + [servingSize?.printedText, servingsPerPack?.printedText].compactMap { $0 })
        if !coverage.isEmpty { return decline(coverage) }
        if !declineReasons.isEmpty { return decline(declineReasons) }
        if rows.isEmpty { return decline(["no_table"]) }
        if amountHeaders.isEmpty {
            // Decision 23: a basis printed only in the energy line is a hint for the user's
            // choice, carried as a warning on the declined candidate, never a header.
            var declined = decline(["no_basis_header"])
            if let basisHint { declined.warnings = [Self.basisHintPrefix + basisHint] }
            return declined
        }
        if let bindingDecline { return decline(bindingDecline) }
        if cells.isEmpty {
            // A table whose rows were all left unread is a table read too little, not a missing
            // table (in any language: the text did hold rows).
            let partly = warnings.contains { $0.hasPrefix("row_not_read: ") }
            return decline([partly ? Self.tooLittleReadCode : "no_table"])
        }
        // 3.7: fewer than 5 of the 8 Taiwan mandatory rows read in the stored column declines.
        if language == .traditionalChinese, Self.mandatoryRowsRead(cells: cells, headers: headers) < Self.tooLittleReadMinimum {
            return decline([Self.tooLittleReadCode])
        }
        return LabelCaptureCandidate(
            route: route,
            inputSHA256: inputSHA256,
            declined: false,
            declineReasons: [],
            wouldMarkReady: warnings.isEmpty,
            language: language,
            servingSize: servingSize,
            servingsPerPack: servingsPerPack,
            headers: headers,
            cells: cells,
            warnings: warnings
        )
    }

    /// 3.2: the index of the first row of a stacked table that deviates from the regular sequence
    /// (a label line, then one value per line, one per column, then the next label line) or from
    /// the Taiwan template order, or nil when every row is regular. A label followed directly by
    /// another label, a row with more or fewer values than columns, a line holding two values,
    /// values after the last label and a label at the end with no values are all deviations; so
    /// is a mandatory row that comes before a mandatory row it should follow, or repeats one.
    /// Optional rows may stand between mandatory rows. A label wrapped over two lines counts as
    /// one label line only when the merged label is a recognised row.
    static func firstStackedDeviation(_ rows: [RowDraftV3], amountColumns: Int, referenceColumns: Int) -> Int? {
        var lastTemplatePosition = -1
        for (index, row) in rows.enumerated() {
            if row.labelLines > 1, !RowClassifierV3.isRowLabel(row.label) { return index }
            if row.labelLineHadValues || !stackedValuesAreRegular(row, amountColumns: amountColumns, referenceColumns: referenceColumns) {
                return index
            }
            if let position = TaiwanRowAliases.templatePosition(row.label) {
                if position <= lastTemplatePosition { return index }
                lastTemplatePosition = position
            }
        }
        return nil
    }

    /// One value per line, exactly one amount per amount column (energy: one per column in kJ,
    /// in the other energy units, or in both, as parser v2 groups energy by unit), and either no reference-intake
    /// value or one per reference column (a `*` line counts as one). Values are bound by unit, so
    /// a `%` value can never be taken for an amount.
    static func stackedValuesAreRegular(_ row: RowDraftV3, amountColumns: Int, referenceColumns: Int) -> Bool {
        guard !row.valueLines.isEmpty, row.valueLines.allSatisfy({ $0.count == 1 }) else { return false }
        let units = row.valueLines.map { $0[0] }
        let percent = units.filter { $0 == "%" }.count
        guard percent == 0 || percent == referenceColumns else { return false }
        let amounts = units.filter { $0 != "%" }
        if RowClassifierV3.classify(row.label)?.row == .energy {
            // As parser v2 groups energy: kJ, and every other energy value (kcal, Cal) together.
            let kilojoules = amounts.filter { $0 == "kJ" }.count
            let kilocalories = amounts.count - kilojoules
            return !amounts.isEmpty && [kilojoules, kilocalories].allSatisfy { $0 == 0 || $0 == amountColumns }
        }
        return amounts.count == amountColumns
    }

    /// 3.7 (decision 3): the decline when fewer than 5 of the 8 Taiwan mandatory rows are read.
    static let tooLittleReadCode = "too_little_read"
    /// Decision 23: the warning a `no_basis_header` decline carries when the basis is printed only
    /// inside the energy line: `basis_hint: energy_line: <bracket as printed>`.
    static let basisHintPrefix = "basis_hint: energy_line: "
    /// PR 3 review: a bilingual serving or pack line whose Chinese and English quantities
    /// disagree is not read; the candidate says which line (`serving_size`, `servings_per_pack`).
    static let bilingualConflictWarning = "bilingual_quantity_conflict: "
    static let tooLittleReadMinimum = 5

    /// The Taiwan mandatory rows with a printed cell in the column that would be stored (v1
    /// section 6.3: per 100 g or ml when printed, else per serving). A calculated value is never
    /// a cell, so it does not count; energy counts in kcal or kJ.
    static func mandatoryRowsRead(cells: [LabelCell], headers: [LabelHeader]) -> Int {
        guard let stored = headers.first(where: { $0.basis == .per100g || $0.basis == .per100ml })?.headerID
                ?? headers.first(where: { $0.basis == .perServing })?.headerID else { return 0 }
        let read = Set(cells.filter { $0.headerID == stored }.map { $0.nutrient == "energy_kj" ? "energy_kcal" : $0.nutrient })
        return TaiwanRowAliases.templateKeys.filter(read.contains).count
    }

    /// The nutrients a row names for the duplicate-row rule: its label, or when the whole label is
    /// not recognised, its first word or its leading Han run (exact matches only, never a
    /// substring), so `脂肪 abc公克` still names fat. Energy names its kcal or kJ key by the units
    /// printed, or both when neither is.
    static func duplicateKeys(_ row: RowDraftV3) -> Set<String> {
        let words = row.label.split(whereSeparator: \.isWhitespace).map(String.init)
        // An English "X from Y" phrase (`Energy from fat`, `Calories from fat`) is a row of its own,
        // never the X row: its first word is not looked up.
        let fromPhrase = words.count > 2 && words[1].lowercased() == "from"
        let head = fromPhrase ? "" : (words.first ?? row.label)
        let hanHead = PatternsV3.leadingHan.firstMatch(in: row.label)?[0]
        guard let match = RowClassifierV3.classify(row.label) ?? RowClassifierV3.classify(head)
                ?? hanHead.flatMap({ RowClassifierV3.classify($0) }) else { return [] }
        guard match.row == .energy else { return [match.key] }
        let units = Set(row.values.compactMap { $0.unit.flatMap(LabelVocabulary.canonicalUnit) })
        var keys: Set<String> = []
        if units.contains("kJ") { keys.insert("energy_kj") }
        if units.contains("kcal") { keys.insert("energy_kcal") }
        return keys.isEmpty ? ["energy_kcal", "energy_kj"] : keys
    }

    /// One warning per joined line, each at most once: the serving line (3.1 rule 3, the string
    /// serving v3 relies on) and the pack line (rule 4).
    static let joinedWarning = "serving_line_joined"
    /// Rows that are top-level in every supported layout.
    static let topLevelKeys: Set<String> = ["energy", "fat", "carbohydrate", "protein", "sodium", "salt", "fibre"]
    static let joinedPackWarning = "serving_line_joined: servings_per_pack"

    /// `unsupported_script` (G1) and `not_a_food_nutrition_panel` (G2), in gate rule order, when
    /// the gate's own functions find a hit in a consumed but unbound line.
    static func coverageDeclines(_ lines: [String]) -> [String] {
        var reasons: [String] = []
        if !LabelDeclineGate.scriptFindings(lines).isEmpty { reasons.append(LabelGateReason.unsupportedScript.rawValue) }
        if lines.contains(where: { !LabelDeclineGate.supplementMarkers(in: $0).isEmpty }) {
            reasons.append(LabelGateReason.notAFoodNutritionPanel.rawValue)
        }
        return reasons
    }
}

/// The closed bound vocabulary of reader v3 (section 8.1, PR 1 re-review): more-than marks
/// (> ≥ ＞ ≧ 超過 大於 多於 以上 "more than" "over" "at least") and less-than marks (< ≤ ＜ ≦ 未滿
/// 少於 以下 "less than" "under" "up to"), matched after whitespace and brackets are removed, so
/// `以 上`, `（以上）` and `( 以下 )` match. A token that is not a recognised bound on one cell makes
/// its row (or serving or pack line) not read.
enum BoundVocabulary {
    static let english = LabelPattern(#"(?i)(?<![a-z])(more\s+than|less\s+than|at\s+least|up\s+to|or\s+more|or\s+less|over|under)(?![a-z])"#)
    static let marks = LabelPattern(#"<=|>=|超過|大於|多於|以上|未滿|少於|以下|[<>≤≥＜＞≦≧↑↓﹤﹥⩽⩾]"#)
    static let removable = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{3000}()（）[]【】"))
    static let less: Set<String> = ["less than", "up to", "under", "<", "<=", "≤", "＜", "≦", "未滿", "少於", "以下"]

    /// The bound tokens of a text, English words first, then marks with whitespace and brackets removed.
    static func tokens(_ text: String) -> [String] {
        let lower = text.lowercased()
        let words = english.matches(in: lower).map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        var rest = lower
        for word in english.matches(in: lower) { rest = rest.replacingOccurrences(of: word, with: " ") }
        let compact = String(rest.unicodeScalars.filter { !removable.contains($0) }.map(Character.init))
        return words + marks.matches(in: compact)
    }

    /// Whether a line holds bound marks and nothing else (apart from spaces, brackets and colons).
    static func isMarkOnly(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard !tokens(lower).isEmpty else { return false }
        var rest = lower
        for word in english.matches(in: lower) { rest = rest.replacingOccurrences(of: word, with: " ") }
        var compact = String(rest.unicodeScalars.filter { !removable.contains($0) && !":：".unicodeScalars.contains($0) }.map(Character.init))
        for mark in marks.matches(in: compact) { compact = compact.replacingOccurrences(of: mark, with: "") }
        return compact.isEmpty
    }
}
