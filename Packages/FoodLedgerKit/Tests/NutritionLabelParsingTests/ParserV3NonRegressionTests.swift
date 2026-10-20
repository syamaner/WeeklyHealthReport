import Foundation
import Testing
@testable import NutritionLabelParsing

// Reader v3 test 12 (`docs/pasted-nutrition-label-reader-v3.md` sections 5.5 and 7.5): there is
// no Python parser, so parity means non-regression. On every frozen evaluation case (the
// committed development cases, English and Taiwan, and the 107 untouched synthetic Taiwan cases)
// parser v3's candidate must equal parser v2's frozen candidate except for differences on the
// closed allow-list of section 5.5, each tied to a rule. Every difference is printed with its item;
// a difference with no item fails.

enum NonRegression {
    /// The allow-list of section 5.5. Item 1 (the parser version string) is not part of the
    /// candidate; it is pinned by the reader and pipeline tests.
    enum Item: String, CaseIterable, Sendable {
        case versionString = "1 parser version"
        case v2DeclinedV3Reads = "2 v2 declined, v3 reads (truth oracle)"
        case aliasNamesRow = "3 alias names an unrecognised row"
        case unitOffTemplate = "4 off-template unit left unread"
        case newWarnings = "5 new warnings"
        case otherDeclineCode = "6 different decline code"
        /// Reader v3 PR 1 review: Han text between two values is two rows on one line (3.0), so a
        /// table v2 read (and could misbind, `脂肪 10公克 其中飽和脂肪 3公克`) declines `layout_ambiguous`.
        case hanBetweenValues = "7 Han text between values declines layout_ambiguous"
        /// Reader v3 PR 1 re-review: only rows whose own span carries a bound-vocabulary token that is
        /// not a recognised bound on one of its cells (unread), cells whose printed 以下, ≦ or 未滿 now
        /// makes them a bound, serving and pack lines carrying a token (not read), and duplicate
        /// rows (both unread), where parser v2 read an exact value.
        case boundsAndDuplicates = "8 bound words, more-than marks and duplicate rows"
    }

    /// The text span of a row label in a pasted text: its line and every following line up to the
    /// next line that starts with a recognised row label (as the parser's unexplained-bound rule).
    static func span(of label: String, in text: String) -> String {
        let ws = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{3000}"))
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: ws) }
        // The label part of a line, as the parser reads it (markers removed, text before the first value).
        let heads = lines.map { line -> String in
            let head = ParseStateV3.markedRow(line) ?? line
            let first = ParseStateV3.valueMatches(head).first.map { String(head[..<$0.range.lowerBound]) } ?? head
            return first.trimmingCharacters(in: ws.union(CharacterSet(charactersIn: "\t:：-–·•")))
        }
        func compact(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        // A wrapped label: a label-only line the parser merges with the next line's label.
        func wrapped(_ j: Int) -> Bool {
            j + 1 < lines.count && !heads[j].isEmpty && ParseStateV3.valueMatches(lines[j]).isEmpty
                && !RowClassifierV3.isRowLabel(heads[j]) && RowClassifierV3.classify(heads[j] + " " + heads[j + 1]) != nil
        }
        // As the parser: a span ends only at a recognised row label, a wrapped one included.
        func boundary(_ j: Int) -> Bool { RowClassifierV3.isRowLabel(heads[j]) || wrapped(j) }
        let target = compact(label)
        guard let start = lines.indices.first(where: { compact(heads[$0]) == target
            || ($0 + 1 < lines.count && wrapped($0) && compact(heads[$0] + heads[$0 + 1]) == target) }) else { return "" }
        var out = [lines[start]]
        var next = start + 1
        if wrapped(start), compact(heads[start]) != target { out.append(lines[start + 1]); next = start + 2 }
        while next < lines.count, !boundary(next) {
            out.append(lines[next])
            next += 1
        }
        return out.joined(separator: "\n")
    }

    struct Verdict {
        var items: Set<Item> = []
        var unexplained: [String] = []
    }

    static let newWarningPrefixes = ["row_not_read: ", "serving_line_joined"]

    /// The allow-list items that explain every difference between parser v2's candidate and
    /// parser v3's, or the differences no item explains.
    static func explain(v2: LabelCaptureCandidate, v3: LabelCaptureCandidate, text: String? = nil) -> Verdict {
        var verdict = Verdict()
        if v2 == v3 { return verdict }
        switch (v2.declined, v3.declined) {
        case (true, true):
            var same = v2
            same.declineReasons = v3.declineReasons
            if same == v3 { verdict.items.insert(.otherDeclineCode) } else { verdict.unexplained.append("declined candidates differ beyond the code") }
            return verdict
        case (true, false):
            // Item 2 needs the case's truth; the frozen vectors carry none, so such a case must
            // be added to the oracle (and its truth checked) before it may pass.
            verdict.unexplained.append("v2 declined (\(v2.declineReasons)), v3 reads it: no truth oracle for this case")
            return verdict
        case (false, true):
            if v3.declineReasons == ["layout_ambiguous"], let text,
               text.components(separatedBy: "\n").contains(where: ParseStateV3.hasHanBetweenValues) {
                verdict.items.insert(.hanBetweenValues)
                return verdict
            }
            verdict.unexplained.append("v2 read it, v3 declines \(v3.declineReasons)")
            return verdict
        case (false, false):
            break
        }
        var expected = v2
        // Item 4: rows v3 leaves unread for an off-template unit.
        let offTemplate = v3.warnings.compactMap { $0.hasPrefix("row_not_read: unit_off_template: ") ? String($0.dropFirst(33)) : nil }
        for label in offTemplate {
            let removed = expected.cells.filter { $0.printedLabel == label }
            guard let entry = TaiwanRowAliases.entry(label), let template = entry.templateUnit,
                  removed.contains(where: { $0.basis != .referenceIntake && !TaiwanRowAliases.readableUnits(template: template).contains($0.canonicalUnit) }) else {
                verdict.unexplained.append("row \(label) unread without an off-template unit")
                continue
            }
            expected.cells.removeAll { $0.printedLabel == label }
            verdict.items.insert(.unitOffTemplate)
        }
        // Item 8: rows left unread for a bound token in their own span, or as duplicates; cells whose
        // printed bound (以下, ≦, 未滿) now makes them a bound; serving and pack lines with a bound token.
        for warning in v3.warnings {
            for reason in ["malformed_value", "unexplained_bound", "duplicate_row"] where warning.hasPrefix("row_not_read: \(reason): ") {
                let label = String(warning.dropFirst("row_not_read: \(reason): ".count))
                let carriesBound = text.map { !BoundVocabulary.tokens(span(of: label, in: $0)).isEmpty } ?? false
                guard reason == "duplicate_row" || carriesBound else {
                    verdict.unexplained.append("row \(label) unread with no bound token in its span")
                    continue
                }
                expected.cells.removeAll { $0.printedLabel == label }
                verdict.items.insert(.boundsAndDuplicates)
            }
        }
        expected.cells = expected.cells.map { cell in
            guard let bound = v3.cells.first(where: { $0.rowID == cell.rowID && $0.headerID == cell.headerID && $0.decimalText == cell.decimalText
                      && $0.comparator != cell.comparator }),
                  BoundVocabulary.tokens(bound.printedText).contains(where: BoundVocabulary.less.contains) else { return cell }
            verdict.items.insert(.boundsAndDuplicates)
            var changed = cell
            changed.comparator = bound.comparator
            changed.printedText = bound.printedText
            return changed
        }
        if let size = v2.servingSize, size.decimalText != nil, v3.servingSize?.decimalText == nil,
           !BoundVocabulary.tokens(size.printedText).isEmpty {
            expected.servingSize = v3.servingSize
            verdict.items.insert(.boundsAndDuplicates)
        }
        if let pack = v2.servingsPerPack, v3.servingsPerPack == nil, !BoundVocabulary.tokens(pack.printedText).isEmpty {
            expected.servingsPerPack = nil
            verdict.items.insert(.boundsAndDuplicates)
        }
        // Item 3: an unrecognised v2 row that an alias now names, with the same values.
        var renamed: [String: (key: String, parent: String?)] = [:]
        expected.cells = expected.cells.map { cell in
            guard cell.nutrient == "unrecognised", let entry = TaiwanRowAliases.entry(cell.printedLabel) else { return cell }
            var named = cell
            let key = RowClassifier.key(for: entry.row)
            if case .energy = entry.row { return cell } // energy is never unrecognised in v2
            named.rowID = key
            named.nutrient = key
            named.parentRowID = entry.parent
            renamed[cell.printedLabel] = (key, entry.parent)
            verdict.items.insert(.aliasNamesRow)
            return named
        }
        expected.warnings.removeAll { warning in renamed.keys.contains { warning == "unrecognised_row: \($0)" } }
        // Item 5: the new warnings, and the ready marker that follows from the warnings.
        let added = v3.warnings.filter { warning in newWarningPrefixes.contains { warning.hasPrefix($0) } }
        if !added.isEmpty { verdict.items.insert(.newWarnings) }
        let carried = v3.warnings.filter { warning in !newWarningPrefixes.contains { warning.hasPrefix($0) } }
        if carried != expected.warnings { verdict.unexplained.append("warnings \(expected.warnings) → \(v3.warnings)") }
        expected.warnings = v3.warnings
        expected.wouldMarkReady = v3.warnings.isEmpty
        if expected.cells != v3.cells { verdict.unexplained.append("cells differ beyond the allow-list") }
        expected.cells = v3.cells
        if expected != v3 { verdict.unexplained.append("serving lines or headers differ") }
        return verdict
    }
}

@Test func test12ParserV3DiffersFromTheFrozenV2CandidatesOnlyOnTheAllowList() throws {
    let lines = try ParityFixtures.lines("parity-cases-v1.jsonl")
    var tally: [NonRegression.Item: Int] = [:]
    var unchanged = 0
    var checked = 0
    var failures: [String] = []
    for record in lines.dropFirst() where record["kind"] as? String == "text" {
        let id = record["id"] as? String ?? "?"
        let text = try #require(record["text"] as? String)
        let hash = try #require(record["text_sha256"] as? String)
        let v2 = try #require(try ParityFixtures.candidate(record["candidate"]))
        let v3 = NutritionLabelTextParserV3().parse(text, inputSHA256: hash)
        let verdict = NonRegression.explain(v2: v2, v3: v3, text: text)
        checked += 1
        if verdict.items.isEmpty && verdict.unexplained.isEmpty { unchanged += 1 }
        for item in verdict.items {
            tally[item, default: 0] += 1
            print("non-regression \(id): \(item.rawValue)")
        }
        failures += verdict.unexplained.map { "\(id): \($0)" }
    }
    print("non-regression: \(checked) frozen cases, \(unchanged) unchanged, " + NonRegression.Item.allCases.map { "\($0.rawValue): \(tally[$0, default: 0])" }.joined(separator: "; "))
    #expect(checked == 314)
    #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
}
