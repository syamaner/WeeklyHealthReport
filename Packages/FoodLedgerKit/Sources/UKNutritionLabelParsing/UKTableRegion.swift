import Foundation

/// One line or tab cell the region stage set aside, with the rule that did it and its position
/// in the folded pasted text (0-based line index; tab-cell index for S4 and S5).
public struct UKSetAsideEntry: Equatable, Sendable {
    public enum Rule: String, Sendable {
        case packCountLine = "S1"
        case followingTable = "S2"
        case duplicateTable = "S3"
        case referenceColumn = "S4"
        case headingCountCell = "S5"
        case restatedBasisLine = "S6"
        case referenceIntakeFootnote = "S7"
    }

    public let rule: Rule
    public let line: Int
    public let cell: Int?
    public let text: String

    public init(rule: Rule, line: Int, cell: Int?, text: String) {
        self.rule = rule; self.line = line; self.cell = cell; self.text = text
    }
}

/// The region stage's result: the kept lines (whole set-aside lines removed, set-aside cells
/// emptied), the set-aside list, a decline when a declared nutrient would be dropped, and the
/// rows S2 set aside that `UKSetAsideReport` lists under "Printed but not read".
public struct UKRegion: Equatable, Sendable {
    public let kept: [String]
    public let setAside: [UKSetAsideEntry]
    public let declineCode: String?
    public let reportedRows: [String]
}

/// The UK reader's closed region rules S1 to S7 (`docs/pasted-nutrition-label-uk-english-v2-p1.md`
/// section 3 and amendment 1), run on the folded lines of an English text before normalisation, in
/// this order: S2, S3, S1, S7, S6, S5, S4.
/// They are the only UK rules that drop text, and every dropped line or cell is in the set-aside
/// list. Part of `nutrition-label-text-parser-uk-v3`.
public enum UKTableRegion {
    public static let rowsAfterTable = "uk_rows_after_table"

    public static func apply(_ lines: [String]) -> UKRegion {
        var kept: [String?] = lines
        var setAside: [UKSetAsideEntry] = []
        var reported: [String] = []
        func drop(_ index: Int, _ rule: UKSetAsideEntry.Rule) {
            guard let line = kept[index] else { return }
            setAside.append(.init(rule: rule, line: index, cell: nil, text: line))
            kept[index] = nil
        }

        guard let heading = headingIndex(lines) else { return UKRegion(kept: lines, setAside: [], declineCode: nil, reportedRows: []) }

        // S2 first: a vitamins and minerals table after a complete table ends the reading.
        if let fat = completeTableEnd(lines, heading: heading),
           let title = lines.indices.first(where: { $0 > fat && isFollowingTableTitle(lines[$0]) }) {
            if lines[(title + 1)...].contains(where: isRowLine) {
                return UKRegion(kept: lines, setAside: [], declineCode: rowsAfterTable, reportedRows: [])
            }
            reported = reportedRows(Array(lines[(title + 1)...]))
            for index in title..<lines.count { drop(index, .followingTable) }
        }

        // S3: stacked duplicate tables, one per 100 and one per serving; keep the per 100 table.
        if let duplicate = duplicateTable(lines, kept: kept) {
            for index in duplicate { drop(index, .duplicateTable) }
        }

        // S1: count lines before the heading or after the last row line.
        let lastRow = kept.indices.last(where: { kept[$0].map(isRowLine) ?? false }) ?? heading
        for index in kept.indices where index < heading || index > lastRow {
            if let line = kept[index], isCountStatement(line) { drop(index, .packCountLine) }
        }

        // S7: a reference intake footnote after the last row line (`RI= Reference intake of an
        // average adult (8400 kJ / 2000 kcal)`), which the header phrase pattern would otherwise
        // take for a second panel. It states the reference values, never a value of the food.
        for index in kept.indices where index > lastRow {
            if let line = kept[index], isReferenceIntakeFootnote(line) { drop(index, .referenceIntakeFootnote) }
        }

        // S6: a line before the heading restating the heading's single basis cell (C4 copies, whose
        // heading is a title cell on its own line with the basis on the next line).
        let c4Heading = lines.indices.first { $0 >= heading && singleBasisCell(lines, heading: $0) != nil && cells(lines[$0]).count <= 2
            && cells(lines[$0]).dropFirst().allSatisfy { trimmed($0).isEmpty } }
        if let basisHeading = c4Heading, let basis = singleBasisCell(lines, heading: basisHeading) {
            for index in 0..<basisHeading where kept[index].map({ restatesBasis($0, basis: basis) }) ?? false {
                drop(index, .restatedBasisLine)
            }
        }

        // S5: a count phrase in the heading's label column.
        if let line = kept[heading] {
            var cells = line.components(separatedBy: "\t")
            if cells.count >= 2, isCountStatement(cells[0]) {
                setAside.append(.init(rule: .headingCountCell, line: heading, cell: 0, text: cells[0]))
                cells[0] = ""
                kept[heading] = cells.joined(separator: "\t")
            }
        }

        // S4: a reference-value column, found by position.
        if let line = kept[heading] {
            let headingCells = line.components(separatedBy: "\t")
            if headingCells.count >= 3, let column = headingCells.indices.dropFirst().first(where: { isReferenceIntakeCell(headingCells[$0]) }) {
                // Every tabbed line and every row line after the heading, so a space-aligned row cannot escape the check.
                let rows = kept.indices.filter { $0 > heading && (kept[$0].map { $0.contains("\t") || isRowLine($0) } ?? false) }
                if rows.allSatisfy({ kept[$0]!.components(separatedBy: "\t").count == headingCells.count }) {
                    for index in [heading] + rows {
                        var cells = kept[index]!.components(separatedBy: "\t")
                        setAside.append(.init(rule: .referenceColumn, line: index, cell: column, text: cells[column]))
                        cells.remove(at: column)
                        kept[index] = cells.joined(separator: "\t")
                    }
                }
            }
        }

        return UKRegion(kept: kept.compactMap { $0 }, setAside: setAside.sorted { ($0.line, $0.cell ?? -1) < ($1.line, $1.cell ?? -1) },
                        declineCode: nil, reportedRows: reported)
    }

    // MARK: Line predicates

    static let headerPhrase = UKPattern(UKVocabulary.headerPhrasePattern)
    static let value = UKPattern(UKVocabulary.valuePattern)

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    }

    static func cells(_ line: String) -> [String] { line.components(separatedBy: "\t") }

    /// A closed table title, whole, case-insensitive, with an optional trailing colon.
    static func isTableTitle(_ text: String) -> Bool {
        var lowered = trimmed(text).lowercased()
        if lowered.hasSuffix(":") { lowered.removeLast() }
        return UKVocabulary.tableTitles.contains(lowered)
    }

    /// The first line matching the copied header phrase pattern, or with two or more tab cells
    /// whose first cell is a closed table title.
    static func headingIndex(_ lines: [String]) -> Int? {
        lines.indices.first { index in
            let line = lines[index]
            // A count statement (`150G PACK (3-4 SERVINGS PER PACK)`) names `per` but is not a heading.
            if isCountStatement(line) { return false }
            if headerPhrase.contains(line) { return true }
            let parts = cells(line)
            return parts.count >= 2 && isTableTitle(parts[0])
        }
    }

    /// A row line: after leading spaces, `-`, `_` or `of which`, a word of the row vocabulary.
    static func isRowLine(_ line: String) -> Bool { rowWord(line) != nil }

    static func rowWord(_ line: String) -> String? {
        var text = trimmed(line).lowercased()
        // A closed title glued to the first row (N4's shape, before N4 runs).
        if let title = UKVocabulary.tableTitles.sorted(by: { $0.count > $1.count }).first(where: { text.hasPrefix($0 + " ") }) {
            text = trimmed(String(text.dropFirst(title.count)))
        }
        while let first = text.first, first == "-" || first == "_" { text = trimmed(String(text.dropFirst())) }
        if text.hasPrefix("of which") { text = trimmed(String(text.dropFirst("of which".count))).trimmingCharacters(in: CharacterSet(charactersIn: ": ")) }
        return UKVocabulary.rowWords.first { word in text.hasPrefix(word) && text.dropFirst(word.count).first.map { !$0.isLetter } ?? true }
    }

    /// The index of the fat row line when a complete table (heading, then energy and fat rows in
    /// that order within the next 24 non-blank lines) starts at `heading`.
    static func completeTableEnd(_ lines: [String], heading: Int) -> Int? {
        var seenEnergy = false
        var nonBlank = 0
        for index in (heading + 1)..<max(heading + 1, lines.count) {
            guard !trimmed(lines[index]).isEmpty else { continue }
            nonBlank += 1
            if nonBlank > 24 { return nil }
            switch rowWord(lines[index]) {
            case "energy": seenEnergy = true
            case "fat" where seenEnergy: return index
            default: break
            }
        }
        return nil
    }

    // MARK: S1 and S5 count statements

    static let countStatement = UKPattern(UKVocabulary.countStatementPattern)

    /// Only a count statement from the closed forms, with trailing empty or `-` tab cells allowed.
    static func isCountStatement(_ line: String) -> Bool {
        var parts = cells(line)
        while parts.count > 1, let last = parts.last, ["", "-"].contains(trimmed(last)) { parts.removeLast() }
        guard parts.count == 1 else { return false }
        return countStatement.contains(trimmed(parts[0]))
    }

    // MARK: S7 a reference intake footnote

    static let referenceIntakeFootnote = UKPattern(UKVocabulary.referenceIntakeFootnotePattern)

    /// Only the footnote, with trailing empty or `-` tab cells allowed.
    static func isReferenceIntakeFootnote(_ line: String) -> Bool {
        var parts = cells(line)
        while parts.count > 1, let last = parts.last, ["", "-"].contains(trimmed(last)) { parts.removeLast() }
        guard parts.count == 1 else { return false }
        return referenceIntakeFootnote.contains(trimmed(parts[0]))
    }

    // MARK: S2 a following vitamins and minerals table

    static func isFollowingTableTitle(_ line: String) -> Bool {
        var parts = cells(line)
        while parts.count > 1, let last = parts.last, trimmed(last).isEmpty { parts.removeLast() }
        guard parts.count == 1 else { return false }
        var lowered = trimmed(parts[0]).lowercased()
        if lowered.hasSuffix(":") { lowered.removeLast() }
        return UKVocabulary.followingTableTitles.contains(lowered)
    }

    /// The rows after S2's title that `UKSetAsideReport` lists, in order: a line whose label starts
    /// with a letter and holds a value (the printed label is the trimmed text before the first
    /// value), or a label line without a value followed by a line that is only a value (the one-cell-
    /// per-line shape). A heading line (a table title first cell, or a label starting `per`, `%`,
    /// `RI` or `NRV`), a footnote and a blank line are not rows.
    static func reportedRows(_ lines: [String]) -> [String] {
        let nonBlank = lines.map(trimmed).filter { !$0.isEmpty }
        var rows: [String] = []
        var index = 0
        while index < nonBlank.count {
            let line = nonBlank[index]
            if let first = value.matches(line).first {
                let label = trimmed(String(line[..<first.range.lowerBound]))
                if isReportableLabel(label) { rows.append(label) }
                index += 1
            } else if isReportableLabel(line), index + 1 < nonBlank.count, UKTextNormalisation.valueCell.contains(nonBlank[index + 1]) {
                rows.append(line)
                index += 2
            } else {
                index += 1
            }
        }
        return rows
    }

    static func isReportableLabel(_ label: String) -> Bool {
        guard let initial = label.first, initial.isLetter, !label.contains("\t") || !cells(label)[0].isEmpty else { return false }
        if isTableTitle(cells(label)[0]) { return false }
        let lowered = label.lowercased()
        return !["per ", "per\t", "%", "ri ", "ri=", "nrv"].contains { lowered.hasPrefix($0) } && lowered != "per" && lowered != "ri"
    }

    // MARK: S3 stacked duplicate tables

    /// The lines of the per serving table to set aside, when exactly two complete tables with one-
    /// basis headings, one per 100 and one per serving, have the same rows and values.
    static func duplicateTable(_ lines: [String], kept: [String?]) -> [Int]? {
        let headings = lines.indices.filter { kept[$0] != nil && isOneBasisHeading(lines[$0]) }
        guard headings.count == 2, let first = headings.first, let second = headings.last else { return nil }
        let firstBody = Array(lines[(first + 1)..<second])
        let secondBody = (second + 1..<lines.count).filter { kept[$0] != nil }.map { lines[$0] }
        guard completeTableEnd(lines, heading: first) != nil, completeTableEnd(lines, heading: second) ?? Int.max < lines.count else { return nil }
        let firstRows = firstBody.filter { !trimmed($0).isEmpty }.map(canonicalRow)
        let secondRows = secondBody.filter { !trimmed($0).isEmpty }.map(canonicalRow)
        guard firstRows.count >= 2, firstRows == secondRows else { return nil }
        let per100First = isPer100(lines[first])
        let per100Second = isPer100(lines[second])
        guard per100First != per100Second, isPerServing(per100First ? lines[second] : lines[first]) else { return nil }
        let servingHeading = per100First ? second : first
        let servingEnd = per100First ? lines.count : second
        return Array(servingHeading..<servingEnd).filter { kept[$0] != nil }
    }

    static let per100 = UKPattern(#"(?i)\bper\s*100\s*(?:g|ml)(?![\p{L}])"#)
    static let standaloneHundred = UKPattern(#"(?<![\d.,])100(?![\d.,])"#)

    static func isOneBasisHeading(_ line: String) -> Bool {
        let parts = cells(line).map(trimmed).filter { !$0.isEmpty }
        guard parts.count == 1 else { return false }
        return isPer100(parts[0]) || isPerServing(parts[0])
    }

    static func isPer100(_ text: String) -> Bool { per100.contains(text) }

    static func isPerServing(_ text: String) -> Bool {
        let lowered = trimmed(text).lowercased()
        return lowered.hasPrefix("per") && lowered.contains("serving") && !standaloneHundred.contains(lowered)
    }

    /// A body line with its energy unit spellings folded (`kj` and `kJ`, `kCal` and `kcal`), its
    /// label case folded and its spaces collapsed. Numbers and comparators are compared as printed.
    static func canonicalRow(_ line: String) -> String {
        var out = line.lowercased()
        out = out.replacingOccurrences(of: "\t", with: " ")
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return trimmed(out)
    }

    // MARK: S4 a reference-value column

    static func isReferenceIntakeCell(_ cell: String) -> Bool {
        var lowered = trimmed(cell).lowercased()
        while lowered.hasSuffix("*") { lowered.removeLast() }
        return UKVocabulary.referenceIntakeHeadings.contains(trimmed(lowered))
    }

    // MARK: S6 a restated basis line

    /// The heading's single basis cell when the heading is a title cell, with an optional empty
    /// second cell, followed by one basis line (the C4 shape only).
    static func singleBasisCell(_ lines: [String], heading: Int) -> String? {
        let parts = cells(lines[heading]).map(trimmed)
        guard parts.count <= 2, isTableTitle(parts[0]), parts.dropFirst().allSatisfy(\.isEmpty) else { return nil }
        guard let next = lines.indices.first(where: { $0 > heading && !trimmed(lines[$0]).isEmpty }) else { return nil }
        let basis = trimmed(lines[next])
        // The basis line is a basis alone, not a title restating it (`Typical values per 100ml`).
        let lowered = basis.lowercased()
        guard !UKVocabulary.tableTitles.contains(where: { lowered.hasPrefix($0) }) else { return nil }
        return headerPhrase.contains(basis) && !basis.contains("\t") ? basis : nil
    }

    /// A tab-free line that is exactly a closed table title followed by the heading's basis, as in
    /// `Typical values per 100ml` above a heading whose basis cell is `Per 100ml`.
    static func restatesBasis(_ line: String, basis: String) -> Bool {
        guard !line.contains("\t") else { return false }
        let lowered = trimmed(line).lowercased()
        var basisLowered = basis.lowercased()
        if basisLowered.hasSuffix(":") { basisLowered.removeLast() }
        return UKVocabulary.tableTitles.contains { title in
            lowered == title + " " + basisLowered || lowered == title + " " + basisLowered + ":"
        }
    }
}
