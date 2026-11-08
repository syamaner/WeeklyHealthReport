import Foundation

/// `pasted-label-text-locate-v3` (docs/pasted-label-ai-text-v1.md 4.3, D3; revision 10, v3 in revision 14, D30): a pure,
/// deterministic check of a model's answer against the text that was sent. It never produces,
/// converts or assigns a value; it says, for each value the model returned, whether that printed
/// value is found in the text exactly once where the model placed it, and which rows and columns
/// need the user's check. Offsets are counted in Unicode scalars of the sent text.
///
/// The rules, in order:
/// 1. **Headers** are the model's amount headers, each located as the one whole-word occurrence
///    of its printed text in the text (4.3 item 4). A header not located, or located more than
///    once, puts every value in its column under attention.
/// 2. **Row labels** are located as unique whole words, longest first, so `saturated fat` is
///    taken before `fat` (item 5). Model rows with the same printed label share one location (a
///    kJ row and a kcal row under one `Energy`). An occurrence of a longer label, located or
///    not, is never searched again for a shorter one. A label found more than once is ambiguous
///    and its values are under attention. So is a label whose remaining occurrence lies inside a
///    case-insensitive whole-word occurrence of a longer `pasted-label-ai-text-vocabulary-v1`
///    row label that no model row claimed (`fat` inside `Saturated fat`, review F4).
/// 3. **Blocks** run from a located label's end to the next located label's start; the last
///    block ends at the first blank line after a value token in it, or at the text's end (item
///    6). Value tokens inside a located header are not cells, but only when the vocabulary
///    agrees with that header's basis; a header it does not know, or disagrees with, never hides
///    a cell. A located header inside a block puts that block under attention (review F1).
/// 4. **Cells**: a kJ token and a kcal token next to each other, separated only by boundaries,
///    are one cell (item 8), paired left to right. `%` tokens are set aside for the
///    reference-intake column (item 7.1).
/// 5. **Columns**: when the remaining cells equal the located non-reference-intake headers in
///    number, they match in printed order; fewer or more is block attention (items 7.2 to 7.4).
/// 6. **Values**: with the columns matched, a value is found when its printed text (trailing `*`
///    and `†` ignored) equals its column's cell, or exactly one part of a kJ and kcal cell.
///    Otherwise, and for reference-intake values against the block's `%` tokens, the values of
///    the row with the same printed text are matched to equal tokens by ordinal (item 9): as
///    many tokens as values is found, none is not found, any other count is ambiguous (item 10).
/// 7. **Bounds outside a token** (review F2): a found value whose token printed no comparator,
///    but whose left neighbour (past whitespace) is a comparator word in any case (`Less than`)
///    or a math symbol (Unicode Sm, such as `≦` or `~`), is under attention, since the printed
///    bound may be lost. The closed comparator lists are unchanged.
/// 8. **Two or more reference-intake headers** put every reference-intake value under attention
///    (review F7), since `%` cells are not positioned between them; `%` tokens in a block with no
///    reference-intake header put the block under attention.
/// 10. **Brackets** (v2): a printed value wrapped in the label's own brackets (`(4.9g)`, or `1.1g)`
///    from a row printed as `(of which saturates 1.1g)`) matches the bracket-free token only where
///    the text prints those same brackets right beside it (`PastedLabelAITextValueGrammar.unbracketed`).
///    The token scan also takes the text-only kcal spellings (`588kCal`).
/// 9. **Shared header spans**: two header IDs located on one printed span put their values under
///    attention. **Omitted rows**: a vocabulary row label no model row claimed, starting its line
///    or following a value, ends the block before it.
/// 11. **Not-declared markers** (v3, D30): a dash or `Trace`/`Tr` standing alone in a block
///    (`PastedLabelTextScan.Marker`) is a printed column position: the markers fill their
///    printed positions among the columns (`columns`), so a marker in a column no longer puts its
///    row's other values under attention. A model value that is a marker is found only where the
///    same marker is printed at its row and column, by the rules above; a marker never matches a
///    number, nor a number a marker. A block with no marker matches exactly as under v2.
public enum PastedLabelTextLocator {
    public static let version = "pasted-label-text-locate-v3"
    public static let referenceIntakeBasis = "reference_intake"

    // MARK: Input

    public struct Header: Equatable, Sendable, Codable {
        public let id: String
        public let printedText: String
        /// The model's basis (`per_100g`, `per_100ml`, `per_serving` or `reference_intake`).
        public let basis: String
        public init(id: String, printedText: String, basis: String) { self.id = id; self.printedText = printedText; self.basis = basis }
    }

    public struct Value: Equatable, Sendable, Codable {
        public let headerID: String
        public let printedText: String
        public init(headerID: String, printedText: String) { self.headerID = headerID; self.printedText = printedText }
    }

    public struct Row: Equatable, Sendable, Codable {
        public let printedLabel: String
        public let values: [Value]
        public init(printedLabel: String, values: [Value]) { self.printedLabel = printedLabel; self.values = values }
    }

    // MARK: Output

    /// Where something was found: once (with its scalar range), not at all, or more than once.
    public enum Status: Equatable, Sendable, Codable {
        case found(Range<Int>)
        case notFound
        case ambiguous

        enum CodingKeys: String, CodingKey { case state, start, end }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .state) {
            case "found": self = .found(try container.decode(Int.self, forKey: .start)..<container.decode(Int.self, forKey: .end))
            case "not_found": self = .notFound
            case "ambiguous": self = .ambiguous
            case let other: throw DecodingError.dataCorruptedError(forKey: .state, in: container, debugDescription: "unknown state \(other)")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .found(range):
                try container.encode("found", forKey: .state)
                try container.encode(range.lowerBound, forKey: .start)
                try container.encode(range.upperBound, forKey: .end)
            case .notFound: try container.encode("not_found", forKey: .state)
            case .ambiguous: try container.encode("ambiguous", forKey: .state)
            }
        }

        public var range: Range<Int>? { if case let .found(range) = self { range } else { nil } }
    }

    /// Why a value's place is not certain even where its text is found, in this order on a value.
    public enum Attention: String, Sendable, Codable, CaseIterable {
        case rowLabelNotFound = "row_label_not_found"
        case rowLabelAmbiguous = "row_label_ambiguous"
        case headerUnknown = "header_unknown"
        case headerNotLocated = "header_not_located"
        case headerSpanShared = "header_span_shared"
        case multipleReferenceIntakeHeaders = "multiple_reference_intake_headers"
        case percentWithoutReferenceIntakeHeader = "percent_without_reference_intake_header"
        case headerInsideBlock = "header_inside_block"
        case fewerCellsThanHeaders = "fewer_cells_than_headers"
        case moreCellsThanHeaders = "more_cells_than_headers"
        case comparatorOutsideToken = "comparator_outside_token"
    }

    public struct HeaderResult: Equatable, Sendable, Codable {
        public let id: String
        public let status: Status
    }

    public struct RowResult: Equatable, Sendable, Codable {
        public let rowIndex: Int
        public let label: Status
        /// The row's block, when its label is located.
        public let block: Range<Int>?
        public let attention: [Attention]
    }

    public struct ValueResult: Equatable, Sendable, Codable {
        public let rowIndex: Int
        public let valueIndex: Int
        public let headerID: String
        public let status: Status
        public let attention: [Attention]
        /// Not found, ambiguous, or found with a reason its place is not certain.
        public var needsAttention: Bool { status.range == nil || !attention.isEmpty }
    }

    public struct Result: Equatable, Sendable, Codable {
        public let version: String
        public let headers: [HeaderResult]
        public let rows: [RowResult]
        public let values: [ValueResult]

        public func value(row: Int, index: Int) -> ValueResult? { values.first { $0.rowIndex == row && $0.valueIndex == index } }
    }

    // MARK: Locate

    /// A cell of a block: one token, or a kJ and kcal pair stored kJ then kcal.
    enum Cell: Equatable {
        case single(PastedLabelTextScan.Token)
        case pair(kJ: PastedLabelTextScan.Token, kcal: PastedLabelTextScan.Token)

        var parts: [PastedLabelTextScan.Token] {
            switch self {
            case let .single(token): [token]
            case let .pair(kJ, kcal): [kJ, kcal]
            }
        }
    }

    public static func locate(text: String, headers: [Header], rows: [Row]) -> Result {
        let scan = PastedLabelTextScan(text)

        // 1. Headers.
        var headerResults: [HeaderResult] = []
        var headerSpans: [String: Range<Int>] = [:]
        var seenHeaderIDs: Set<String> = []
        for header in headers {
            let occurrences = header.printedText.isEmpty ? [] : scan.wholeWordOccurrences(of: header.printedText)
            let status: Status = occurrences.count == 1 ? .found(occurrences[0]) : occurrences.isEmpty ? .notFound : .ambiguous
            // A repeated header ID is not one column: the first keeps the ID, the rest are not located.
            let unique = seenHeaderIDs.insert(header.id).inserted
            headerResults.append(HeaderResult(id: header.id, status: unique ? status : .ambiguous))
            if unique, let range = status.range { headerSpans[header.id] = range }
        }
        let headerByID = Dictionary(headers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let duplicateIDs = Set(headers.map(\.id).filter { id in headers.filter { $0.id == id }.count > 1 })
        // Qodo finding 1 on #421: distinct IDs located on one printed span are not distinct columns.
        let sharedSpanIDs = Set(headerSpans.filter { id, span in headerSpans.contains { $0.key != id && $0.value.overlaps(span) } }.keys)
        let locatedSpans = headerSpans.values.sorted { $0.lowerBound < $1.lowerBound }
        // Only a header the vocabulary agrees with may take its tokens out of the cells (F1).
        let hidingSpans = headers.filter { header in
            headerSpans[header.id] != nil && PastedLabelAITextVocabulary.checkHeader(printedText: header.printedText, basis: header.basis) == .agrees
        }.compactMap { headerSpans[$0.id] }
        let referenceHeaderCount = headers.filter { $0.basis == referenceIntakeBasis }.count
        let anyReferenceHeader = referenceHeaderCount > 0
        let amountHeaders = headers.filter { headerSpans[$0.id] != nil && !duplicateIDs.contains($0.id) && $0.basis != referenceIntakeBasis }
            .sorted { headerSpans[$0.id]!.lowerBound < headerSpans[$1.id]!.lowerBound }
        let columnOfHeader = Dictionary(uniqueKeysWithValues: amountHeaders.enumerated().map { ($0.element.id, $0.offset) })
        // v3 (D30): the located columns in printed order, `true` for the reference-intake one, when
        // exactly one reference-intake header is returned and located on its own span.
        let positionalHeaders: [Bool]? = {
            guard referenceHeaderCount == 1, let reference = headers.first(where: { $0.basis == referenceIntakeBasis }),
                  let span = headerSpans[reference.id], !duplicateIDs.contains(reference.id), !sharedSpanIDs.contains(reference.id) else { return nil }
            let starts = amountHeaders.map { (headerSpans[$0.id]!.lowerBound, false) } + [(span.lowerBound, true)]
            return starts.sorted { $0.0 < $1.0 }.map(\.1)
        }()

        // 2. Row labels, longest first; equal printed labels are one group.
        var labels: [String] = []
        for row in rows where !labels.contains(row.printedLabel) { labels.append(row.printedLabel) }
        let order = labels.enumerated().sorted {
            ($0.element.unicodeScalars.count, -$0.offset) > ($1.element.unicodeScalars.count, -$1.offset)
        }.map(\.element)
        var claimed: [Range<Int>] = []
        var labelStatus: [String: Status] = [:]
        let vocabulary = vocabularyOccurrences(scan)
        for label in order {
            let occurrences = label.isEmpty ? [] : scan.wholeWordOccurrences(of: label).filter { range in !claimed.contains { $0.overlaps(range) } }
            // F4: an occurrence inside a longer vocabulary label nobody claimed is not this row's label.
            let insideLonger = occurrences.contains { occurrence in
                vocabulary.contains { phrase in
                    phrase.count > occurrence.count && phrase.lowerBound <= occurrence.lowerBound && occurrence.upperBound <= phrase.upperBound
                        && !claimed.contains { $0.overlaps(phrase) }
                }
            }
            labelStatus[label] = insideLonger ? .ambiguous
                : occurrences.count == 1 ? .found(occurrences[0]) : occurrences.isEmpty ? .notFound : .ambiguous
            claimed.append(contentsOf: occurrences)
        }

        // 3. Blocks. A vocabulary row label the model did not return also ends a block when it
        // starts its line or follows a value (Qodo finding 2 on #421), so an omitted printed
        // row's values belong to no model row.
        let located = labels.compactMap { label in labelStatus[label]?.range.map { (label, $0) } }.sorted { $0.1.lowerBound < $1.1.lowerBound }
        let omittedRowStarts = vocabulary.filter { phrase in
            !claimed.contains { $0.overlaps(phrase) } && !locatedSpans.contains { $0.overlaps(phrase) } && startsARow(scan, phrase)
        }.map(\.lowerBound).sorted()
        var blocks: [String: Range<Int>] = [:]
        for (index, (label, span)) in located.enumerated() {
            var end = index + 1 < located.count ? located[index + 1].1.lowerBound : lastBlockEnd(scan, after: span)
            if let omitted = omittedRowStarts.first(where: { $0 >= span.upperBound }) { end = min(end, omitted) }
            blocks[label] = span.upperBound..<max(span.upperBound, end)
        }

        // 4 to 6. Cells, columns and values, per label group.
        var rowResults: [RowResult] = []
        var valueResults: [ValueResult] = []
        var groupAttention: [String: [Attention]] = [:]
        var groupStatuses: [String: [Int: [Int: Status]]] = [:]
        for label in labels {
            let members = rows.indices.filter { rows[$0].printedLabel == label }
            guard let block = blocks[label] else {
                groupAttention[label] = [labelStatus[label] == .ambiguous ? .rowLabelAmbiguous : .rowLabelNotFound]
                continue
            }
            let tokens = scan.tokens.filter { token in block.contains(token.start) && !hidingSpans.contains { $0.overlaps(token.range) } }
            let percent = tokens.filter { $0.canonicalUnit == "%" }
            let cells = pairCells(tokens.filter { $0.canonicalUnit != "%" }, scan: scan)
            let markers = scan.markers.filter { marker in block.contains(marker.start) && !hidingSpans.contains { $0.overlaps(marker.range) } }
            let layout = columns(cells: cells, percent: percent, markers: markers, amountCount: amountHeaders.count, positional: positionalHeaders)
            var attention: [Attention] = []
            if locatedSpans.contains(where: { $0.overlaps(block) }) { attention.append(.headerInsideBlock) }
            // Qodo finding 7 on #421: `%` cells are set aside only for a returned reference-intake header.
            if !anyReferenceHeader, !percent.isEmpty { attention.append(.percentWithoutReferenceIntakeHeader) }
            if layout.amounts == nil, cells.count < amountHeaders.count { attention.append(.fewerCellsThanHeaders) }
            if layout.amounts == nil, cells.count > amountHeaders.count { attention.append(.moreCellsThanHeaders) }
            groupAttention[label] = attention

            var statuses: [Int: [Int: Status]] = [:]
            // Members' values in row order, then value order.
            let entries = members.flatMap { row in rows[row].values.indices.map { (row, $0, rows[row].values[$0]) } }
            func record(_ row: Int, _ index: Int, _ status: Status) { statuses[row, default: [:]][index] = status }
            func ordinal(_ group: [(Int, Int, Value)], candidates: [Candidate]) {
                let byText = Dictionary(grouping: group, by: { matchText($0.2.printedText) })
                for (text, values) in byText {
                    let bracketed = PastedLabelAITextValueGrammar.unbracketed(text)
                    let equal = candidates.filter { $0.matches(bracketed, scan: scan) }
                    for (position, entry) in values.enumerated() {
                        let status: Status = equal.isEmpty ? .notFound : equal.count == values.count ? .found(equal[position].range) : .ambiguous
                        record(entry.0, entry.1, status)
                    }
                }
            }
            let isReference = { (value: Value) in headerByID[value.headerID]?.basis == referenceIntakeBasis }
            ordinal(entries.filter { isReference($0.2) }, candidates: percent.map(Candidate.token) + layout.referenceMarkers.map(Candidate.marker))
            let amounts = entries.filter { !isReference($0.2) }
            if let slots = layout.amounts {
                let positioned = amounts.filter { columnOfHeader[$0.2.headerID] != nil }
                for column in Set(positioned.map { columnOfHeader[$0.2.headerID]! }).sorted() {
                    ordinal(positioned.filter { columnOfHeader[$0.2.headerID] == column }, candidates: slots[column].candidates)
                }
                ordinal(amounts.filter { columnOfHeader[$0.2.headerID] == nil }, candidates: slots.flatMap(\.candidates))
            } else {
                ordinal(amounts, candidates: cells.flatMap { $0.parts }.map(Candidate.token) + markers.map(Candidate.marker))
            }
            groupStatuses[label] = statuses
        }

        for (rowIndex, row) in rows.enumerated() {
            let label = row.printedLabel
            let attention = groupAttention[label] ?? []
            rowResults.append(RowResult(rowIndex: rowIndex, label: labelStatus[label] ?? .notFound, block: blocks[label], attention: attention))
            for (valueIndex, value) in row.values.enumerated() {
                var reasons = attention
                if let header = headerByID[value.headerID] {
                    if headerSpans[header.id] == nil || duplicateIDs.contains(header.id) { reasons.append(.headerNotLocated) }
                    if sharedSpanIDs.contains(header.id) { reasons.append(.headerSpanShared) }
                } else {
                    reasons.append(.headerUnknown)
                }
                let fallback: Status = labelStatus[label] == .ambiguous ? .ambiguous : .notFound
                let status = groupStatuses[label]?[rowIndex]?[valueIndex] ?? fallback
                if headerByID[value.headerID]?.basis == referenceIntakeBasis, referenceHeaderCount > 1 {
                    reasons.append(.multipleReferenceIntakeHeaders)
                }
                if let range = status.range, let token = scan.tokens.first(where: { $0.start == range.lowerBound }),
                   scan.comparatorOutside(token) {
                    reasons.append(.comparatorOutsideToken)
                }
                valueResults.append(ValueResult(rowIndex: rowIndex, valueIndex: valueIndex, headerID: value.headerID, status: status,
                                                attention: Attention.allCases.filter(reasons.contains)))
            }
        }
        return Result(version: version, headers: headerResults, rows: rowResults, values: valueResults)
    }

    /// Whether a vocabulary label occurrence starts a printed row: on its line, only whitespace,
    /// punctuation, leading marks and the words `of which` (any case) come before it, or the last
    /// thing before it (past whitespace and punctuation) ends a value token.
    static func startsARow(_ scan: PastedLabelTextScan, _ phrase: Range<Int>) -> Bool {
        guard let line = scan.line(containing: phrase.lowerBound) else { return false }
        var index = phrase.lowerBound - 1
        while index >= line.start, scan.scalars[index].properties.isWhitespace || PastedLabelTextScan.isPunctuation(scan.scalars[index])
                || scan.scalars[index] == "•" || scan.scalars[index] == "*" {
            index -= 1
        }
        if index < line.start { return true }
        if scan.tokens.contains(where: { $0.end == index + 1 || $0.coreEnd == index + 1 }) { return true }
        let before = scan.text(line.start..<(index + 1)).lowercased()
        let stripped = String(before.unicodeScalars.filter { !$0.properties.isWhitespace && !PastedLabelTextScan.isPunctuation($0) && $0 != "•" && $0 != "*" }
            .map(Character.init))
        return stripped == "ofwhich"
    }

    /// Case-insensitive whole-word occurrences of every vocabulary row label (F4). Lower-casing is
    /// per scalar and keeps a scalar that lower-cases to more than one, so offsets are unchanged.
    static func vocabularyOccurrences(_ scan: PastedLabelTextScan) -> [Range<Int>] {
        let lowered = String(String.UnicodeScalarView(scan.scalars.map { scalar in
            let lower = String(scalar).lowercased().unicodeScalars
            return lower.count == 1 ? lower.first! : scalar
        }))
        let lowerScan = PastedLabelTextScan(lowered)
        return PastedLabelAITextVocabulary.rowLabels.keys.sorted().flatMap { lowerScan.wholeWordOccurrences(of: $0) }
    }

    /// The last block ends at the first blank line after a value token in it, else at the text's end.
    static func lastBlockEnd(_ scan: PastedLabelTextScan, after span: Range<Int>) -> Int {
        guard let labelLine = scan.lines.firstIndex(where: { $0.start <= span.lowerBound && span.upperBound <= $0.end }) else {
            return scan.scalars.count
        }
        let first = scan.lines[labelLine]
        var seenToken = scan.tokens.contains { $0.start >= span.upperBound && $0.start < first.end }
        for line in scan.lines[(labelLine + 1)...] {
            if scan.isBlank(line) {
                if seenToken { return line.start }
                continue
            }
            if scan.tokens.contains(where: { $0.start >= line.start && $0.start < line.end }) { seenToken = true }
        }
        return scan.scalars.count
    }

    /// Adjacent kJ and kcal tokens, separated only by boundaries, become one cell (kJ then kcal),
    /// paired left to right; every other token is its own cell.
    static func pairCells(_ tokens: [PastedLabelTextScan.Token], scan: PastedLabelTextScan) -> [Cell] {
        var cells: [Cell] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if index + 1 < tokens.count {
                let next = tokens[index + 1]
                let units = [token.canonicalUnit, next.canonicalUnit]
                let onlyBoundaries = (token.end..<next.start).allSatisfy { PastedLabelTextScan.isBoundary(scan.scalars, at: $0) }
                if onlyBoundaries, units == ["kJ", "kcal"] || units == ["kcal", "kJ"] {
                    cells.append(token.canonicalUnit == "kJ" ? .pair(kJ: token, kcal: next) : .pair(kJ: next, kcal: token))
                    index += 2
                    continue
                }
            }
            cells.append(.single(token))
            index += 1
        }
        return cells
    }

    // MARK: Not-declared markers as cells (v3, D30)

    /// What a model value may be matched to: a value token, or a not-declared marker. A marker
    /// matches only the same marker text, never a bracketed value, so a number never matches a
    /// marker and a marker never matches a number.
    enum Candidate: Equatable {
        case token(PastedLabelTextScan.Token)
        case marker(PastedLabelTextScan.Marker)

        var range: Range<Int> {
            switch self {
            case let .token(token): token.range
            case let .marker(marker): marker.range
            }
        }

        func matches(_ bracketed: PastedLabelAITextValueGrammar.Bracketed, scan: PastedLabelTextScan) -> Bool {
            switch self {
            case let .token(token): coreText(scan, token) == bracketed.core && hasBrackets(scan, token, bracketed)
            case let .marker(marker): !bracketed.isBracketed && marker.text == bracketed.core
            }
        }
    }

    /// One printed column position of a block: a cell, a marker, or a `%` token.
    enum Slot: Equatable {
        case cell(Cell)
        case marker(PastedLabelTextScan.Marker)
        case percent(PastedLabelTextScan.Token)

        var start: Int {
            switch self {
            case let .cell(cell): cell.parts[0].start
            case let .marker(marker): marker.start
            case let .percent(token): token.start
            }
        }

        var candidates: [Candidate] {
            switch self {
            case let .cell(cell): cell.parts.map(Candidate.token)
            case let .marker(marker): [.marker(marker)]
            case let .percent(token): [.token(token)]
            }
        }
    }

    /// A block's columns: the amount column positions when they match the located amount headers
    /// (nil otherwise, which is block attention), and the markers set aside for the
    /// reference-intake column.
    struct Layout: Equatable {
        let amounts: [Slot]?
        let referenceMarkers: [PastedLabelTextScan.Marker]
    }

    /// v3 (D30). A block with no marker matches exactly as under v2 (rule 2 or 4). With markers:
    /// 1. with one located reference-intake header, every cell, marker and `%` token equals every
    ///    located header, each in printed order, and each position holds what its header can (a
    ///    cell or marker for an amount header; a `%` token, marker or absolute cell for reference
    ///    intake, whose absolute cell is never read): the markers take their printed positions;
    /// 2. the cells alone equal the amount headers: as v2, and the block's markers are the
    ///    reference-intake column's candidates;
    /// 3. the cells and markers together equal the amount headers: markers take their positions;
    /// 4. otherwise the columns do not match.
    static func columns(cells: [Cell], percent: [PastedLabelTextScan.Token], markers: [PastedLabelTextScan.Marker], amountCount: Int,
                        positional: [Bool]?) -> Layout {
        let amountSlots = (cells.map(Slot.cell) + markers.map(Slot.marker)).sorted { $0.start < $1.start }
        if !markers.isEmpty, let positional {
            let slots = (amountSlots + percent.map(Slot.percent)).sorted { $0.start < $1.start }
            if slots.count == positional.count {
                var amounts: [Slot] = []
                var reference: [PastedLabelTextScan.Marker] = []
                var fits = true
                for (slot, isReference) in zip(slots, positional) {
                    switch (slot, isReference) {
                    case (.percent, true), (.cell, true): break
                    case let (.marker(marker), true): reference.append(marker)
                    case (.cell, false), (.marker, false): amounts.append(slot)
                    case (.percent, false): fits = false
                    }
                }
                if fits { return Layout(amounts: amounts, referenceMarkers: reference) }
            }
        }
        if cells.count == amountCount { return Layout(amounts: cells.map(Slot.cell), referenceMarkers: markers) }
        if !markers.isEmpty, amountSlots.count == amountCount { return Layout(amounts: amountSlots, referenceMarkers: []) }
        return Layout(amounts: nil, referenceMarkers: [])
    }

    /// A model's printed value as matched: trailing `*` and `†` dropped, nothing else changed.
    static func matchText(_ printed: String) -> String {
        var scalars = Array(printed.unicodeScalars)
        while let last = scalars.last, last == "*" || last == "†" { scalars.removeLast() }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars)
        return String(out)
    }

    /// Whether the text prints the brackets the model's value carried right beside the token (v2):
    /// the opener just before the token's start, the closer just after its end.
    static func hasBrackets(_ scan: PastedLabelTextScan, _ token: PastedLabelTextScan.Token,
                            _ bracketed: PastedLabelAITextValueGrammar.Bracketed) -> Bool {
        if let open = bracketed.open, !(token.start > 0 && scan.scalars[token.start - 1] == open) { return false }
        if let close = bracketed.close, !(token.end < scan.scalars.count && scan.scalars[token.end] == close) { return false }
        return true
    }

    static func coreText(_ scan: PastedLabelTextScan, _ token: PastedLabelTextScan.Token) -> String {
        scan.text(token.start..<token.coreEnd)
    }
}
