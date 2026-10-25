import Foundation

/// `label-photo-vision-locate-v2` matcher (docs/label-photo-ai-prefill-v1.md sections 6.1 and 17.11).
///
/// Pure: Foundation only, no Vision, image, clock or network. The Vision adapter supplies the
/// recognised lines and a function that returns the box of a substring of one line; the matcher
/// decides, for each printed value the model returned, whether the same comparator, number and
/// unit appear exactly once on the photo on its own row and in its own column. Being found is
/// corroboration, never verification. L0 measures this file; the package carries it unchanged and
/// pins it by SHA-256.
///
/// v2 keeps every v1 safety rule and recovers rows and columns v1 could not confirm (17.11):
/// a row label not located exactly once is placed between its located neighbours (by its text,
/// a near-miss of its text, or the reading's row order); a table-wide vertical offset estimated
/// from agreeing rows is removed before the row distance limit; and columns whose headers were
/// not located are inferred from the x-positions of value tokens when they split cleanly into the
/// reading's column count. Every recovered placement still has to pass the token rule.
public enum LabelValueMatcher {
    public static let version = "label-photo-vision-locate-v2"
    /// A value belongs to its row label only within this share of the local label spacing.
    public static let rowOffsetLimit = 1.0 / 3.0

    /// A normalised rectangle in image space (0...1 on both axes; Vision's origin, bottom left).
    public struct Box: Equatable, Sendable, Codable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }
    }

    /// One recognised line of text and its box.
    public struct Line: Equatable, Sendable {
        public let text: String
        public let box: Box
        public init(text: String, box: Box) { self.text = text; self.box = box }
    }

    /// One value to locate: its row label, its column header's printed text and its own printed
    /// text, all as the model returned them. Serving lines have no row label or header.
    public struct Query: Equatable, Sendable {
        public let id: String
        public let rowLabel: String?
        public let headerText: String?
        public let printedText: String
        public init(id: String, rowLabel: String?, headerText: String?, printedText: String) {
            self.id = id; self.rowLabel = rowLabel; self.headerText = headerText; self.printedText = printedText
        }
    }

    public enum Status: String, Sendable, Codable { case found, notFound = "not_found", ambiguous }

    /// What the photo says against a value that is not found (17.11, attention policy evidence):
    /// `elsewhere` when its token is printed only in another row or column; `conflictingInCell`
    /// when its own row and column are located and hold a different value token; `none` otherwise.
    public enum Evidence: String, Sendable, Codable { case none, elsewhere, conflictingInCell = "conflicting_in_cell" }

    public struct Location: Equatable, Sendable {
        public let id: String
        public let status: Status
        public let region: Box?
        public let evidence: Evidence
        init(id: String, status: Status, region: Box?, evidence: Evidence = .none) {
            self.id = id; self.status = status; self.region = region; self.evidence = evidence
        }
    }

    /// The box of `range` (original indices) within `lines[index]`, or the line's box.
    public typealias SubBox = (_ index: Int, _ range: Range<String.Index>) -> Box?

    /// `headers` are the reading's header texts, left to right; `rowLabels` every row label's
    /// printed text; `columnCount` the number of value columns the reading has (headers with or
    /// without printed text).
    ///
    /// Preconditions: `queries` list each column's values in the table's printed row order, top to
    /// bottom, as the reading's rows are (the order pass and row recovery check this against the
    /// labels found on the photo and place nothing when it cannot be checked); and when `headers`
    /// has one entry per column, they are in printed left-to-right order (column inference uses it).
    public static func locate(_ queries: [Query], lines: [Line], headers: [String], rowLabels: [String], columnCount: Int,
                              subBox: SubBox) -> [Location] {
        let normalised = lines.map(Normalised.init)
        func box(_ match: Match) -> Box { subBox(match.line, match.range) ?? lines[match.line].box }
        func unique(_ texts: [String], rule: Rule) -> [String: Box] {
            var boxes: [String: Box] = [:]
            for text in Set(texts) {
                let found = occurrences(of: text, in: normalised, rule: rule)
                if found.count == 1 { boxes[Normalised(text).key] = box(found[0]) }
            }
            return boxes
        }
        func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }

        // Every value token on the photo, once.
        var tokensOnPhoto: [(token: ValueToken, box: Box)] = []
        for (number, line) in normalised.enumerated() {
            for token in valueTokens(line.characters) {
                tokensOnPhoto.append((token, box(Match(line: number, range: line.origin[token.start].lowerBound..<line.origin[token.end - 1].upperBound))))
            }
        }

        // Row labels located exactly once, then recovery (17.11 a). Only rows whose own label text is
        // located on the photo (once, or once between its located neighbours) are **direct**: a value
        // can be found only on a direct row. Near-miss and row-order placements are indirect: they
        // may narrow candidates and give the region to highlight, never confirm (17.12).
        var rowBoxes = unique(rowLabels, rule: .label)
        var directRows = Set(rowBoxes.keys)
        let knownLabels = Set(rowLabels.map { Normalised($0).key }).union(rowLabelVocabulary.map { Normalised($0).key })
        var readingOrder: [String] = []
        for label in queries.compactMap({ $0.rowLabel.map { Normalised($0).key } }) where !readingOrder.contains(label) {
            readingOrder.append(label)
        }
        // A label whose values are not one contiguous run of the reading's queries (the reading
        // gives it to two places) has no single place in the reading's order.
        let queryLabels = queries.map { $0.rowLabel.map { Normalised($0).key } }
        func contiguous(_ key: String) -> Bool {
            let positions = queryLabels.indices.filter { queryLabels[$0] == key }
            guard let low = positions.first, let high = positions.last else { return false }
            return (low...high).allSatisfy { queryLabels[$0] == key || queryLabels[$0] == nil }
        }
        let locatedIndices = readingOrder.indices.filter { rowBoxes[readingOrder[$0]] != nil }
        let orderHolds = zip(locatedIndices, locatedIndices.dropFirst()).allSatisfy { rowBoxes[readingOrder[$0]]!.midY > rowBoxes[readingOrder[$1]]!.midY }
        if orderHolds, locatedIndices.count >= 2 {
            let located = locatedIndices.map { rowBoxes[readingOrder[$0]]! }
            let labelX = median(located.map(\.midX)) ?? 0, labelHeight = median(located.map(\.height)) ?? 0.03
            let perRow = zip(locatedIndices, locatedIndices.dropFirst()).map { pair -> Double in
                (rowBoxes[readingOrder[pair.0]]!.midY - rowBoxes[readingOrder[pair.1]]!.midY) / Double(pair.1 - pair.0)
            }
            let rowStep = median(perRow) ?? 0
            let labelLines = Set(locatedIndices.flatMap { index in
                occurrences(of: readingOrder[index], in: normalised, rule: .label).map(\.line)
            })
            var recovered: [String: Box] = [:]
            for index in readingOrder.indices where rowBoxes[readingOrder[index]] == nil {
                guard let above = locatedIndices.last(where: { $0 < index }), let below = locatedIndices.first(where: { $0 > index }) else { continue }
                let key = readingOrder[index]
                guard contiguous(key) else { continue }
                let high = rowBoxes[readingOrder[above]]!.midY, low = rowBoxes[readingOrder[below]]!.midY
                func between(_ value: Box) -> Bool { value.midY < high && value.midY > low }
                // Its own text, printed once between the neighbours.
                let exact = occurrences(of: key, in: normalised, rule: .label).map { box($0) }.filter(between)
                if exact.count == 1 { recovered[key] = exact[0]; directRows.insert(key); continue }
                if !exact.isEmpty { continue }
                // A near-miss of its text (one character different) in the label column.
                let similar = normalised.indices.filter { line in
                    !labelLines.contains(line) && between(lines[line].box) && abs(lines[line].box.midX - labelX) < 0.1
                        && nearMiss(normalised[line].characters, Array(key)) && !knownLabels.contains(normalised[line].key)
                }
                if similar.count == 1 { recovered[key] = lines[similar[0]].box; continue }
                if !similar.isEmpty { continue }
                // Its place in the reading's row order: only when nothing at all was read in the label
                // column between the neighbours (a line there is some other label, perhaps misread,
                // so the reading's order cannot be trusted for this slot), the label occupies one
                // run of the reading's queries, and the gap fits the table's row step.
                let occupied = normalised.indices.contains { line in
                    !labelLines.contains(line) && between(lines[line].box) && abs(lines[line].box.midX - labelX) < 0.1
                }
                if occupied { continue }
                let gap = (high - low) / Double(below - above)
                guard rowStep > 0, abs(gap - rowStep) <= 0.25 * rowStep else { continue }
                let y = high - gap * Double(index - above)
                // Every value token between the neighbours must sit on one of the expected rows (a
                // tall, wrapped label or an extra line breaks the row step).
                let slots = (above...below).map { high - gap * Double($0 - above) }
                let stray = tokensOnPhoto.contains { entry in
                    between(entry.box) && !slots.contains { abs(entry.box.midY - $0) < rowOffsetLimit * gap }
                }
                if stray { continue }
                recovered[key] = Box(x: labelX - 0.05, y: y - labelHeight / 2, width: 0.1, height: labelHeight)
            }
            for (key, value) in recovered { rowBoxes[key] = value }
        }

        func nearest(_ boxes: [String: Box], to value: Box, by distance: (Box, Box) -> Double) -> String? {
            boxes.sorted { $0.key < $1.key }.min { distance($0.value, value) < distance($1.value, value) }?.key
        }
        let rowsTopDown = rowBoxes.sorted { $0.value.midY > $1.value.midY }
        // The table's row step: the lower quartile of the gaps between adjacent located labels. A row
        // whose label was not located leaves a double gap, which a median would let inflate the step
        // (and with it the offset and the distance limit); the lower quartile does not (17.13).
        let medianStep: Double = {
            let gaps = zip(rowsTopDown, rowsTopDown.dropFirst()).map { $0.value.midY - $1.value.midY }.sorted()
            guard !gaps.isEmpty else { return 0 }
            return gaps[(gaps.count - 1) / 4]
        }()
        func spacing(_ label: String) -> Double? {
            guard let index = rowsTopDown.firstIndex(where: { $0.key == label }), rowsTopDown.count > 1 else { return nil }
            var gaps: [Double] = []
            if index > 0 { gaps.append(rowsTopDown[index - 1].value.midY - rowsTopDown[index].value.midY) }
            if index + 1 < rowsTopDown.count { gaps.append(rowsTopDown[index].value.midY - rowsTopDown[index + 1].value.midY) }
            // Never wider than the table's typical row step: a row whose label was not located
            // must not widen its neighbours' limit (17.13).
            guard let local = gaps.min() else { return nil }
            return medianStep > 0 ? min(local, medianStep) : local
        }
        func rowKey(_ query: Query) -> String? {
            guard let label = query.rowLabel.map({ Normalised($0).key }), rowBoxes[label] != nil, rowBoxes.count > 1 else { return nil }
            return label
        }

        // Headers count as located only in the header band (17.13, B6): above the top directly
        // located row label, within about two row steps of it, below any serving line printed above
        // the table, and next to a value token on a direct row. A header text printed once in a
        // footnote or a serving line elsewhere is not a header.
        let tableStep = medianStep
        let topDirect = rowsTopDown.first { directRows.contains($0.key) }?.value
        let servingTops = queries.filter { $0.rowLabel == nil }
            .flatMap { occurrences(of: $0.printedText, in: normalised, rule: .bounded).map { box($0) } }
            .filter { line in topDirect.map { line.midY > $0.midY } ?? false }
            .map(\.midY)
        let directTokens = tokensOnPhoto.filter { entry in
            rowsTopDown.contains { row in
                directRows.contains(row.key) && abs(entry.box.midY - row.value.midY) < 0.5 * max(tableStep, 0.01)
            }
        }
        let tokenWidth = median(directTokens.map(\.box.width)) ?? 0.05
        var headerBoxes: [String: Box] = [:]
        if let top = topDirect, tableStep > 0 {
            for text in Set(headers) {
                // A line that also carries a value with a unit is a serving or value line, not a
                // header line ("每份 185公克").
                // The header's own text ("每100公克") is removed first, and so are the other
                // headers, since a header line may hold them all ("每份 每100公克").
                let headerLines = occurrences(of: text, in: normalised, rule: .line).filter { match in
                    var rest = normalised[match.line].key
                    for other in headers.map({ Normalised($0).key }).sorted(by: { $0.count > $1.count }) where !other.isEmpty {
                        rest = rest.replacingOccurrences(of: other, with: " ")
                    }
                    // Nothing but the headers and punctuation may remain (C2: 每份參考值% is the
                    // reference-intake column's header, not 每份).
                    return rest.allSatisfy { $0 == " " || $0.isPunctuation || $0.isSymbol }
                }
                let inBand = headerLines.map { box($0) }.filter { header in
                    header.midY > top.midY + 0.5 * tableStep && header.midY < top.midY + 2.5 * tableStep
                        && !servingTops.contains { header.midY >= $0 }
                        && directTokens.contains { abs($0.box.midX - header.midX) < max(0.08, 1.5 * tokenWidth) }
                }
                if inBand.count == 1 { headerBoxes[Normalised(text).key] = inBand[0] }
            }
        }

        // Table-wide vertical offset (17.11 c): from values whose token is printed exactly once on
        // the photo, on their own located label's side of the neighbours; used only when at least
        // three rows agree within 0.15 of a row and the offset is at least 0.1 of a row.
        let stepForOffset = medianStep
        var offset = 0.0
        if stepForOffset > 0 {
            var ratios: [String: Double] = [:]
            for query in queries {
                guard let key = rowKey(query), ratios[key] == nil, let own = rowBoxes[key] else { continue }
                let wanted = valueTokens(Normalised(query.printedText).characters)
                guard wanted.count == 1, !wanted[0].unit.isEmpty else { continue }
                let same = tokensOnPhoto.filter { !$0.token.range && $0.token.comparator == wanted[0].comparator
                    && $0.token.number == wanted[0].number && $0.token.unit == wanted[0].unit }
                guard same.count == 1 else { continue }
                let ratio = (same[0].box.midY - own.midY) / stepForOffset
                if abs(ratio) <= 1.0 / 3.0 { ratios[key] = ratio }
            }
            if let centre = median(Array(ratios.values)) {
                let agreeing = ratios.values.filter { abs($0 - centre) <= 0.15 }
                if ratios.count >= 3, agreeing.count >= 3, Double(agreeing.count) >= 0.75 * Double(ratios.count), abs(centre) >= 0.1,
                   abs(centre) <= 1.0 / 3.0 {
                    offset = centre * stepForOffset
                }
            }
        }
        func shifted(_ value: Box) -> Box { Box(x: value.x, y: value.y - offset, width: value.width, height: value.height) }

        // Row geometry. A value belongs to a row label only when that label is its nearest and its
        // vertical offset from the label (after the table-wide offset) is under `rowOffsetLimit` of
        // the local spacing; nearest but further off has drifted and is ambiguous, never found.
        enum RowFit { case other, near, drifted }
        func rowFit(_ label: String, _ value: Box) -> RowFit {
            let adjusted = shifted(value)
            guard let own = rowBoxes[label], let gap = spacing(label),
                  nearest(rowBoxes, to: adjusted, by: { abs($0.midY - $1.midY) }) == label else { return .other }
            return abs(adjusted.midY - own.midY) < rowOffsetLimit * gap ? .near : .drifted
        }

        // Columns: located headers when they separate the columns; otherwise inferred from the
        // x-positions of unit-bearing value tokens on located rows (17.11 b), when they split into
        // exactly `columnCount` groups with clear gaps and agree with any single located header.
        let headerKeys = headers.map { Normalised($0).key }
        var clusters: [(low: Double, high: Double)]?
        if columnCount > 1, headerBoxes.count < 2 || headerKeys.contains(where: { headerBoxes[$0] == nil }), headers.count == columnCount {
            let onRows = tokensOnPhoto.filter { entry in !entry.token.unit.isEmpty && rowBoxes.keys.contains { rowFit($0, entry.box) == .near } }
            let xs = onRows.map(\.box.midX).sorted()
            let tokenWidth = median(onRows.map(\.box.width)) ?? 0
            if xs.count >= 2 * columnCount {
                let gaps = zip(xs, xs.dropFirst()).enumerated().map { (index: $0.offset, size: $0.element.1 - $0.element.0) }
                let cuts = gaps.sorted { $0.size > $1.size }.prefix(columnCount - 1).map(\.index).sorted()
                var groups: [(low: Double, high: Double)] = []
                var start = 0
                for cut in cuts + [xs.count - 1] {
                    groups.append((xs[start], xs[cut])); start = cut + 1
                }
                let smallestCut = cuts.map { gaps[$0].size }.min() ?? 0
                let widest = groups.map { $0.high - $0.low }.max() ?? 0
                var agrees = true
                for (index, key) in headerKeys.enumerated() {
                    guard let located = headerBoxes[key] else { continue }
                    let nearestGroup = groups.indices.min { abs(groups[$0].low - located.midX) + abs(groups[$0].high - located.midX)
                        < abs(groups[$1].low - located.midX) + abs(groups[$1].high - located.midX) }
                    if nearestGroup != index { agrees = false }
                }
                // No group may hold two unit tokens of the same row (an omitted column merged in), and
                // each group must be narrower than about one token.
                func groupIndex(_ x: Double) -> Int? { groups.firstIndex { x >= $0.low - 1e-9 && x <= $0.high + 1e-9 } }
                var seen = Set<String>()
                var twoInOneRow = false
                for entry in onRows {
                    guard let row = rowBoxes.keys.sorted().first(where: { rowFit($0, entry.box) == .near }),
                          let index = groupIndex(entry.box.midX) else { continue }
                    if !seen.insert("\(row)#\(index)").inserted { twoInOneRow = true }
                }
                if groups.count == columnCount, smallestCut > 0.03, smallestCut > 2 * widest, agrees, !twoInOneRow,
                   widest < max(tokenWidth, 0.01) { clusters = groups }
            }
        }
        func columnIndex(_ query: Query) -> Int? {
            guard let header = query.headerText.map({ Normalised($0).key }) else { return nil }
            return headerKeys.firstIndex(of: header)
        }
        func group(of value: Box) -> Int? {
            guard let clusters else { return nil }
            return clusters.indices.min { min(abs(clusters[$0].low - value.midX), abs(clusters[$0].high - value.midX))
                < min(abs(clusters[$1].low - value.midX), abs(clusters[$1].high - value.midX)) }
        }
        /// Found needs the column confirmed by a located header: one value column; at least two
        /// headers located with its own among them; or inferred columns that a located header agrees
        /// with (checked when the groups were accepted) and its header's position known.
        /// With two or more columns, found and evidence need every one of the reading's headers
        /// located in the band, at distinct x positions in the reading's left-to-right order (C1,
        /// C2: one header alone, or headers out of order, cannot say which column is which).
        let headersConfirmed: Bool = {
            guard columnCount > 1, headers.count == columnCount else { return false }
            let located = headerKeys.compactMap { headerBoxes[$0] }
            guard located.count == columnCount else { return false }
            return zip(located, located.dropFirst()).allSatisfy { $1.midX - $0.midX > max(tokenWidth, 0.03) }
        }()
        /// The value's own header sits directly above it (within about one token width).
        func underOwnHeader(_ query: Query, _ value: Box) -> Bool {
            guard let header = query.headerText.map({ Normalised($0).key }), let box = headerBoxes[header] else { return false }
            return abs(box.midX - value.midX) <= max(tokenWidth, 0.05)
        }
        func columnForFound(_ query: Query) -> Bool {
            if columnCount <= 1 { return true }
            guard headersConfirmed, let header = query.headerText.map({ Normalised($0).key }) else { return false }
            return headerBoxes[header] != nil
        }
        /// Evidence needs the same confirmation as found.
        func columnByHeaders(_ query: Query) -> Bool { columnForFound(query) }
        /// The value's column is known enough to narrow candidates: as for found, or inferred columns
        /// with its header's position known.
        func columnConfirmed(_ query: Query) -> Bool {
            if columnCount <= 1 { return true }
            if headerBoxes.count > 1, let header = query.headerText.map({ Normalised($0).key }), headerBoxes[header] != nil { return true }
            return clusters != nil && columnIndex(query) != nil
        }
        func inHeader(_ query: Query, _ value: Box) -> Bool {
            if headerBoxes.count > 1, let header = query.headerText.map({ Normalised($0).key }), headerBoxes[header] != nil {
                return nearest(headerBoxes, to: value) { abs($0.midX - $1.midX) } == header
            }
            if clusters != nil, let index = columnIndex(query) { return group(of: value) == index }
            return true
        }

        // Number tokens on a row, outside its label, for the unlisted column rule.
        func numberTokens(onRow label: String) -> [Box] {
            guard let own = rowBoxes[label] else { return [] }
            return tokensOnPhoto.map(\.box).filter { token in
                !(token.midX >= own.x && token.midX <= own.x + own.width) && rowFit(label, token) == .near
            }
        }
        let listedPerRow = Dictionary(grouping: queries.compactMap(rowKey), by: { $0 }).mapValues(\.count)

        // Evidence against a value that is not found (17.11, attention policy).
        func evidence(_ query: Query) -> Evidence {
            let wanted = valueTokens(Normalised(query.printedText).characters)
            // Only on a direct row with its column separated by located headers (17.12).
            guard wanted.count == 1, let label = rowKey(query), directRows.contains(label), columnByHeaders(query) else { return .none }
            let token = wanted[0]
            func equal(_ other: ValueToken) -> Bool {
                other.comparator == token.comparator && other.number == token.number && other.unit == token.unit
            }
            do {
                let inCell = tokensOnPhoto.filter { !$0.token.unit.isEmpty && rowFit(label, $0.box) == .near && inHeader(query, $0.box) }
                if !inCell.isEmpty, !inCell.contains(where: { equal($0.token) }) { return .conflictingInCell }
            }
            let same = tokensOnPhoto.filter { !$0.token.range && equal($0.token) }
            let clearlyElsewhere = same.allSatisfy { entry in
                rowFit(label, entry.box) == .other
                    && rowBoxes.keys.contains { $0 != label && directRows.contains($0) && rowFit($0, entry.box) == .near }
                    || !inHeader(query, entry.box)
            }
            if !same.isEmpty, clearlyElsewhere { return .elsewhere }
            return .none
        }

        // First pass: the row and column filters, trying each tier of matches in turn. An
        // ambiguous result keeps its candidates (after both filters) for the order pass.
        struct First { let location: Location; let candidates: [Box] }
        // R1 of the #320 sweep: a number matched alone (its unit read as a separate line) counts
        // only when a line just to its right, in the same row band, reads as the reading's unit.
        func unitBeside(_ value: Box, unit: String) -> Bool {
            lines.indices.contains { index in
                let other = lines[index].box, text = normalised[index].characters
                guard starts(text, at: 0, with: unit) else { return false }
                let next = unit.count < text.count ? text[unit.count] : nil
                if let next, next.isLetter || isDigit(next) { return false }
                return other.x >= value.x + value.width / 2 && other.x - (value.x + value.width) < 0.1
                    && abs(other.midY - value.midY) < max(other.height, value.height) / 2
            }
        }
        let first: [First] = queries.map { query in
            let isLine = query.rowLabel == nil
            let wanted = valueTokens(Normalised(query.printedText).characters)
            for (tierIndex, tier) in matchTiers(query.printedText, isLine: isLine, in: normalised).enumerated() {
                var candidates = tier.map { box($0) }.filter { inHeader(query, $0) }
                if !isLine, !candidates.isEmpty {
                    // A reading with no unit, or a value matched by its number alone without its unit
                    // beside it, is never found: it can only be ambiguous.
                    let unit = wanted.count == 1 ? wanted[0].unit : ""
                    if unit.isEmpty {
                        return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: [])
                    }
                    if tierIndex == 1 {
                        let beside = candidates.filter { unitBeside($0, unit: unit) }
                        if beside.isEmpty {
                            return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: [])
                        }
                        candidates = beside
                    }
                }
                if isLine {
                    // Serving lines carry their own words; no row or column to confirm.
                    switch candidates.count {
                    case 0: continue
                    case 1: return First(location: Location(id: query.id, status: .found, region: rounded(candidates[0])), candidates: candidates)
                    default: return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: candidates)
                    }
                }
                if candidates.isEmpty { continue }
                guard let label = rowKey(query), spacing(label) != nil else {
                    // The value's own row cannot be confirmed even after recovery: it is never found.
                    let own = query.rowLabel.map { Normalised($0).key }
                    let elsewhere = candidates.filter { candidate in
                        rowBoxes.keys.contains { $0 != own && rowFit($0, candidate) == .near }
                    }
                    let remaining = candidates.filter { !elsewhere.contains($0) }
                    return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: remaining)
                }
                let near = candidates.filter { rowFit(label, $0) == .near }
                let drifted = candidates.filter { rowFit(label, $0) == .drifted }
                if near.isEmpty && drifted.isEmpty { continue }
                let unlisted = columnCount <= 1 && numberTokens(onRow: label).count > (listedPerRow[label] ?? 0)
                if near.count == 1 && drifted.isEmpty && !unlisted && columnConfirmed(query) {
                    // Found needs direct evidence: the row's own label text and, with two or more
                    // columns, a located header agreeing with the column. Otherwise the single
                    // candidate is kept as the region to highlight, and the value is ambiguous.
                    if directRows.contains(label) && columnForFound(query) && (columnCount <= 1 || underOwnHeader(query, near[0])) {
                        return First(location: Location(id: query.id, status: .found, region: rounded(near[0])), candidates: near)
                    }
                    return First(location: Location(id: query.id, status: .ambiguous, region: rounded(near[0])), candidates: near)
                }
                return First(location: Location(id: query.id, status: .ambiguous, region: nil), candidates: near + drifted)
            }
            return First(location: Location(id: query.id, status: .notFound, region: nil), candidates: [])
        }

        // Second pass, order within the column, unchanged from v1 except that columns may be
        // inferred: it may only turn a first-pass ambiguous value into found, under the conditions
        // of 6.1 step 6. Otherwise the value stays ambiguous.
        func columnKey(_ query: Query) -> String? {
            if columnCount <= 1 { return "" }
            if headerBoxes.count > 1, let header = query.headerText.map({ Normalised($0).key }), headerBoxes[header] != nil { return header }
            if clusters != nil, let index = columnIndex(query) { return "#\(index)" }
            return nil
        }
        let placed: [Location] = queries.enumerated().map { index, query in
            let result = first[index]
            guard result.location.status == .ambiguous, query.rowLabel != nil, let key = columnKey(query) else { return result.location }
            let needle = Normalised(query.printedText).key
            let expected = queries.indices.filter { other in
                queries[other].rowLabel != nil && columnKey(queries[other]) == key
                    && Normalised(queries[other].printedText).key == needle
            }
            let labelBoxes = expected.compactMap { queries[$0].rowLabel.flatMap { rowBoxes[Normalised($0).key] } }
            let inOrder = labelBoxes.count == expected.count && zip(labelBoxes, labelBoxes.dropFirst()).allSatisfy { $0.midY > $1.midY }
            let observed = (matchTiers(query.printedText, isLine: false, in: normalised).first ?? []).map { box($0) }
                .filter { inHeader(query, $0) }
                .sorted { $0.midY > $1.midY }
            guard inOrder, expected.count > 1, expected.count == observed.count, let rank = expected.firstIndex(of: index),
                  result.candidates.contains(observed[rank]), let label = rowKey(query), rowFit(label, observed[rank]) == .near,
                  directRows.contains(label), columnForFound(query),
                  !(columnCount <= 1 && numberTokens(onRow: label).count > (listedPerRow[label] ?? 0)) else { return result.location }
            return Location(id: query.id, status: .found, region: rounded(observed[rank]))
        }
        return zip(queries, placed).map { query, location in
            guard location.status != .found, query.rowLabel != nil else { return location }
            return Location(id: location.id, status: location.status, region: location.region, evidence: evidence(query))
        }
    }

    /// Row labels of other nutrients (Taiwan 營養標示 and English tables). A line reading as one of
    /// these is a different row, never a near-miss of the wanted label (17.12).
    static let rowLabelVocabulary: [String] = [
        "熱量", "能量", "蛋白質", "脂肪", "飽和脂肪", "反式脂肪", "碳水化合物", "糖", "添加糖", "膳食纖維", "鈉", "鉀", "鈣", "鐵", "鎂", "鋅", "磷",
        "膽固醇", "維生素A", "維生素B1", "維生素B2", "維生素B6", "維生素B12", "維生素C", "維生素D", "維生素E", "維生素K", "菸鹼素", "葉酸",
        "Energy", "Protein", "Fat", "Saturates", "Carbohydrate", "Sugars", "Fibre", "Salt", "Sodium",
    ]

    /// Two label texts differ by exactly one character (a substitution, insertion or deletion),
    /// and the label has at least two characters.
    static func nearMiss(_ printed: [Character], _ label: [Character]) -> Bool {
        guard label.count >= 2, abs(printed.count - label.count) <= 1, printed != label else { return false }
        var i = 0, j = 0, edits = 0
        while i < printed.count, j < label.count {
            if printed[i] == label[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if printed.count > label.count { i += 1 } else if printed.count < label.count { j += 1 } else { i += 1; j += 1 }
        }
        return edits + (printed.count - i) + (label.count - j) == 1
    }

    // MARK: Values as tokens (#320 re-check, S1 to S4 and the same family)

    /// One printed value read from a normalised line: its comparator (`=`, `<`, `<=`, `>`, `>=`),
    /// its number (thousands separators removed), its unit from a closed list (or none), its
    /// normalised character span, whether it is part of a range, and whether it ends its line.
    struct ValueToken: Equatable {
        let comparator: String, number: String, unit: String
        let start: Int, end: Int
        let range: Bool, endsLine: Bool
    }

    /// Units, longest first; a Latin unit followed by a Latin letter is not a unit.
    static let units = ["kcal", "mcg", "大卡", "千卡", "千焦", "公克", "毫克", "微克", "毫升", "公斤", "公升", "kj", "cal", "μg", "mg", "ml", "kg",
                        "g", "l", "%", "克"]
    /// Bound words and marks before a value (after NFKC, so ＜ is <), longest first.
    static let prefixComparators: [(String, String)] = [
        ("lessthan", "<"), ("morethan", ">"), ("不超過", "<="), ("<=", "<="), (">=", ">="), ("少於", "<"), ("未滿", "<"), ("低於", "<"),
        ("小於", "<"), ("不足", "<"), ("大於", ">"), ("高於", ">"), ("超過", ">"), ("≤", "<="), ("≦", "<="), ("≥", ">="), ("≧", ">="),
        ("<", "<"), (">", ">"),
    ]
    /// Bound words straight after a value's unit.
    static let suffixComparators: [(String, String)] = [("以下", "<="), ("以上", ">="), ("以內", "<=")]
    /// Range marks between two values (after NFKC, so ～ is ~).
    static let rangeMarks: Set<Character> = ["-", "~", "〜", "至", "到", "–", "—", "‐", "−"]

    static func starts(_ characters: [Character], at index: Int, with word: String) -> Bool {
        let pattern = Array(word)
        guard index >= 0, index + pattern.count <= characters.count else { return false }
        return Array(characters[index..<(index + pattern.count)]) == pattern
    }

    /// Every value token of a normalised line. A number starts at an ASCII digit not preceded by a
    /// digit, a point or a separator between digits, and runs over digits, a point followed by a
    /// digit, and a comma between digits; "1,234" is one number, so "234" is never found inside it.
    static func valueTokens(_ c: [Character]) -> [ValueToken] {
        var tokens: [ValueToken] = []
        var index = 0
        var lastEnd = -1
        while index < c.count {
            let continues = index > 0 && (isDigit(c[index - 1]) || c[index - 1] == "." || (c[index - 1] == "," && index >= 2 && isDigit(c[index - 2])))
            guard isDigit(c[index]), !continues else { index += 1; continue }
            var end = index
            while end < c.count, isDigit(c[end]) || ((c[end] == "." || c[end] == ",") && end + 1 < c.count && isDigit(c[end + 1]) && end > index) {
                end += 1
            }
            var number = String(c[index..<end]).replacingOccurrences(of: ",", with: "")
            var start = index, comparator = "="
            if index > 0, c[index - 1] == "-" || c[index - 1] == "−", lastEnd != index - 1 {
                number = "-" + number; start = index - 1
            }
            for (word, kind) in prefixComparators where starts(c, at: start - word.count, with: word) {
                start -= word.count; comparator = kind; break
            }
            var unitEnd = end, unit = ""
            for candidate in units where starts(c, at: end, with: candidate) {
                let next = end + candidate.count < c.count ? c[end + candidate.count] : nil
                let latin = candidate.unicodeScalars.allSatisfy(\.isASCII) && candidate != "%"
                if latin, let next, next.isASCII, next.isLetter { continue }
                unit = candidate; unitEnd = end + candidate.count; break
            }
            var tokenEnd = unitEnd
            for (word, kind) in suffixComparators where starts(c, at: unitEnd, with: word) {
                if comparator == "=" { comparator = kind }
                tokenEnd = unitEnd + word.count; break
            }
            let rangeBefore = start > 0 && rangeMarks.contains(c[start - 1]) && lastEnd == start - 1
            let rangeAfter = tokenEnd + 1 < c.count && rangeMarks.contains(c[tokenEnd])
                && (isDigit(c[tokenEnd + 1]) || prefixComparators.contains { starts(c, at: tokenEnd + 1, with: $0.0) })
            tokens.append(ValueToken(comparator: comparator, number: number, unit: unit, start: start, end: tokenEnd,
                                     range: rangeBefore || rangeAfter, endsLine: tokenEnd == c.count))
            if rangeBefore, let previous = tokens.indices.dropLast().last {
                let p = tokens[previous]
                tokens[previous] = ValueToken(comparator: p.comparator, number: p.number, unit: p.unit, start: p.start, end: p.end, range: true,
                                              endsLine: p.endsLine)
            }
            lastEnd = tokenEnd
            index = tokenEnd
        }
        return tokens
    }

    /// The matches tried in order for one printed text; the first tier with any match decides.
    ///
    /// A value (one token, not a range) matches a printed token with the same comparator, number
    /// and unit (tier 1); or, when Vision read the unit on its own line, a printed token with the
    /// same comparator and number, no unit, that ends its line (tier 2). A different unit on the
    /// same line, a dropped or added comparator, a dropped or added decimal point, a number inside
    /// a longer number, and a value inside a range never match. Any other printed text (a range,
    /// several values) matches only by its whole text, bounded by non-digits.
    ///
    /// A serving line matches by its whole text, bounded by non-digits; or, when Vision split the
    /// line, by its quantity's token with a unit (tier 1 only).
    static func matchTiers(_ printed: String, isLine: Bool, in lines: [Normalised]) -> [[Match]] {
        let model = Normalised(printed)
        let modelTokens = valueTokens(model.characters)
        func tokenMatches(_ accept: (ValueToken, ValueToken) -> Bool, against wanted: ValueToken) -> [Match] {
            var found: [Match] = []
            for (number, line) in lines.enumerated() {
                for token in valueTokens(line.characters) where !token.range && accept(token, wanted) {
                    found.append(Match(line: number, range: line.origin[token.start].lowerBound..<line.origin[token.end - 1].upperBound))
                }
            }
            return found
        }
        func same(_ printed: ValueToken, _ wanted: ValueToken) -> Bool {
            printed.comparator == wanted.comparator && printed.number == wanted.number && printed.unit == wanted.unit
        }
        func unitSplit(_ printed: ValueToken, _ wanted: ValueToken) -> Bool {
            !wanted.unit.isEmpty && printed.unit.isEmpty && printed.endsLine && printed.comparator == wanted.comparator
                && printed.number == wanted.number
        }
        let whole = occurrences(of: printed, in: lines, rule: .bounded)
        if isLine {
            guard let quantity = modelTokens.first, modelTokens.count == 1, !quantity.unit.isEmpty, !quantity.range else { return [whole] }
            return [whole, tokenMatches(same, against: quantity)]
        }
        guard modelTokens.count == 1, let wanted = modelTokens.first, !wanted.range else { return [whole] }
        return [tokenMatches(same, against: wanted), tokenMatches(unitSplit, against: wanted)]
    }

    // MARK: Normalisation and occurrence rules

    /// NFKC (full-width digits and letters to half-width), whitespace removed, lower case, with a
    /// map from each normalised character back to the original indices.
    struct Normalised {
        let characters: [Character]
        let origin: [Range<String.Index>]
        init(_ line: Line) { self.init(line.text) }
        var key: String { String(characters) }
        init(_ text: String) {
            var characters: [Character] = [], origin: [Range<String.Index>] = []
            var index = text.startIndex
            while index < text.endIndex {
                let next = text.index(after: index)
                for character in String(text[index..<next]).precomposedStringWithCompatibilityMapping.lowercased()
                where !character.isWhitespace {
                    characters.append(character); origin.append(index..<next)
                }
                index = next
            }
            self.characters = characters; self.origin = origin
        }
    }

    struct Match { let line: Int; let range: Range<String.Index> }

    enum Rule {
        /// A value: not preceded or followed by a digit or decimal point ("5公克" is not in "15公克").
        case value
        /// A row label or header: not preceded by a letter or ideograph ("脂肪" is not in "飽和脂肪").
        case label
        /// A serving line: plain containment.
        case line
        /// Whole printed text: not preceded or followed by a digit, a point or a separator.
        case bounded
    }

    static func occurrences(of needle: String, in lines: [Normalised], rule: Rule) -> [Match] {
        let pattern = Normalised(needle).characters
        guard !pattern.isEmpty else { return [] }
        var found: [Match] = []
        for (number, line) in lines.enumerated() where line.characters.count >= pattern.count {
            for start in 0...(line.characters.count - pattern.count)
            where Array(line.characters[start..<(start + pattern.count)]) == pattern {
                let before = start > 0 ? line.characters[start - 1] : nil
                let after = start + pattern.count < line.characters.count ? line.characters[start + pattern.count] : nil
                guard admits(rule, before: before, after: after) else { continue }
                // A label ending in a digit or Latin letter is not found inside a longer one
                // (維生素B1 is not in 維生素B12; Fat is not in Fatty).
                if rule == .label, let last = pattern.last, let after {
                    if isDigit(last) && isDigit(after) { continue }
                    if last.isASCII && last.isLetter && after.isASCII && after.isLetter { continue }
                    // 糖 is not in 糖醇: a following ideograph continues the word, except a known
                    // non-nutrient suffix (含量, 總量) or a unit written straight after the label.
                    if isIdeograph(last) && isIdeograph(after) {
                        let rest = Array(line.characters[(start + pattern.count)...])
                        let allowed = labelWordSuffixes.contains { starts(rest, at: 0, with: $0) }
                            || labelUnitSuffixes.contains { unit in
                                guard starts(rest, at: 0, with: unit) else { return false }
                                guard unit.count < rest.count else { return true }
                                let next = rest[unit.count]
                                return isDigit(next) || next.isPunctuation || next.isSymbol
                            }
                        if !allowed { continue }
                    }
                }
                found.append(Match(line: number, range: line.origin[start].lowerBound..<line.origin[start + pattern.count - 1].upperBound))
            }
        }
        return found
    }

    static func admits(_ rule: Rule, before: Character?, after: Character?) -> Bool {
        func numeric(_ character: Character?) -> Bool { character.map { isDigit($0) || $0 == "." } ?? false }
        switch rule {
        case .value: return !numeric(before) && !numeric(after)
        case .label: return !(before.map { $0.isLetter } ?? false)
        case .line: return true
        case .bounded:
            func edge(_ character: Character?) -> Bool { character.map { isDigit($0) || $0 == "." || $0 == "," } ?? false }
            return !edge(before) && !edge(after)
        }
    }

    /// Words allowed straight after a CJK row label: non-nutrient suffixes and units.
    static let labelWordSuffixes = ["含量", "總量"]
    /// A unit straight after the label, only when the unit ends the word (糖克數 is not 糖).
    static let labelUnitSuffixes = ["大卡", "千卡", "千焦", "公克", "毫克", "微克", "毫升", "克"]

    static func isIdeograph(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    /// ASCII digits only (after NFKC): Han numerals such as 一 are words on a label, not values.
    static func isDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }

    static func rounded(_ box: Box) -> Box {
        func four(_ value: Double) -> Double { (min(max(value, 0), 1) * 10_000).rounded() / 10_000 }
        return Box(x: four(box.x), y: four(box.y), width: four(box.width), height: four(box.height))
    }
}
