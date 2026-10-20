import Foundation
import Testing
@testable import NutritionLabelParsing

// Reader v3 test 2 (`docs/pasted-nutrition-label-reader-v3.md` sections 7.2 and 7.5), the
// standing mutation suite of PR 2. Paste-like transformations are applied to synthetic fixtures
// with known truth; each mutation is in exactly one class, with its own oracle:
//
// - (a) structure-breaking: the text says the same thing, laid out differently. Oracle: the
//   original truth. Every bound value equals it for row, column, basis and unit, and every row
//   the mutation touched is not read, or the table is declined.
// - (b) content-changing: the text now says something else. Oracle: the truth of the mutated
//   text, computed here. Every bound value equals it, or is not read, or the table is declined.
//
// A single wrong bound value under either oracle fails the suite. The suite also prints how many
// mutations end as "not read" and how many as declined: a measure of burden, not of safety. The
// accepted residual risk of decision 18 (a stacked exchange of two adjacent same-unit value
// lines) is pinned separately below. Every fixture is synthetic: invented values and no names.

enum MutationSuite {
    struct Value: Equatable {
        var decimal: String
        var unit: String
        var canonical: String {
            switch unit {
            case "大卡": "kcal"
            case "公克": "g"
            case "毫克": "mg"
            default: unit
            }
        }
        var printed: String { decimal + unit }
    }

    struct Row: Equatable {
        var label: String
        /// The stored nutrient key a careful reader binds the row to, or nil when it binds nothing.
        var key: String?
        var values: [Value]
    }

    struct Fixture {
        var name: String
        var header: String
        var bases: [LabelBasis]
        var rows: [Row]
    }

    enum Layout: String, CaseIterable { case inline, stacked }

    static let preamble = ["營養標示", "每一份量30公克", "本包裝含8份"]

    /// Two columns, the official template plus fibre; every value distinct, so a value bound to
    /// the wrong row or column can never match by chance.
    static let twoColumns = Fixture(name: "two columns", header: "每份 每100公克", bases: [.perServing, .per100g], rows: [
        Row(label: "熱量", key: "energy_kcal", values: [.init(decimal: "121", unit: "大卡"), .init(decimal: "403", unit: "大卡")]),
        Row(label: "蛋白質", key: "protein", values: [.init(decimal: "3.1", unit: "公克"), .init(decimal: "10.2", unit: "公克")]),
        Row(label: "脂肪", key: "fat", values: [.init(decimal: "4.3", unit: "公克"), .init(decimal: "14.4", unit: "公克")]),
        Row(label: "飽和脂肪", key: "saturates", values: [.init(decimal: "1.5", unit: "公克"), .init(decimal: "5.6", unit: "公克")]),
        Row(label: "反式脂肪", key: "trans_fat", values: [.init(decimal: "0.1", unit: "公克"), .init(decimal: "0.3", unit: "公克")]),
        Row(label: "碳水化合物", key: "carbohydrate", values: [.init(decimal: "18.7", unit: "公克"), .init(decimal: "62.3", unit: "公克")]),
        Row(label: "糖", key: "sugars", values: [.init(decimal: "6.8", unit: "公克"), .init(decimal: "22.7", unit: "公克")]),
        Row(label: "膳食纖維", key: "fibre", values: [.init(decimal: "2.9", unit: "公克"), .init(decimal: "9.7", unit: "公克")]),
        Row(label: "鈉", key: "sodium", values: [.init(decimal: "61", unit: "毫克"), .init(decimal: "1203", unit: "毫克")]),
    ])

    /// One column, fibre between two mandatory rows (optional rows may stand anywhere) and a
    /// recognised-but-not-stored row at the end.
    static let oneColumn = Fixture(name: "one column", header: "每100公克", bases: [.per100g], rows: [
        Row(label: "熱量", key: "energy_kcal", values: [.init(decimal: "389", unit: "大卡")]),
        Row(label: "蛋白質", key: "protein", values: [.init(decimal: "7.4", unit: "公克")]),
        Row(label: "脂肪", key: "fat", values: [.init(decimal: "12.6", unit: "公克")]),
        Row(label: "飽和脂肪", key: "saturates", values: [.init(decimal: "4.2", unit: "公克")]),
        Row(label: "反式脂肪", key: "trans_fat", values: [.init(decimal: "0.2", unit: "公克")]),
        Row(label: "碳水化合物", key: "carbohydrate", values: [.init(decimal: "64.1", unit: "公克")]),
        Row(label: "膳食纖維", key: "fibre", values: [.init(decimal: "5.3", unit: "公克")]),
        Row(label: "糖", key: "sugars", values: [.init(decimal: "21.8", unit: "公克")]),
        Row(label: "鈉", key: "sodium", values: [.init(decimal: "1187", unit: "毫克")]),
        Row(label: "膽固醇", key: nil, values: [.init(decimal: "13", unit: "毫克")]),
    ])

    static let fixtures = [twoColumns, oneColumn]

    /// The table's lines: the preamble, the header, then the rows in the layout.
    static func lines(_ fixture: Fixture, _ layout: Layout, rows: [Row]? = nil) -> [String] {
        let body = (rows ?? fixture.rows).flatMap { row -> [String] in
            switch layout {
            case .inline: [([row.label] + row.values.map(\.printed)).joined(separator: " ")]
            case .stacked: [row.label] + row.values.map(\.printed)
            }
        }
        return preamble + [fixture.header] + body
    }

    static func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

    /// The index of row `row`'s first line (its label line) in `lines(fixture, layout)`.
    static func lineIndex(_ fixture: Fixture, _ layout: Layout, row: Int) -> Int {
        preamble.count + 1 + (layout == .inline ? row : row * (1 + fixture.bases.count))
    }

    /// The truth as nutrient key → basis → value.
    static func truth(_ fixture: Fixture, rows: [Row]? = nil) -> [String: [LabelBasis: Value]] {
        var out: [String: [LabelBasis: Value]] = [:]
        for row in rows ?? fixture.rows {
            guard let key = row.key else { continue }
            for (basis, value) in zip(fixture.bases, row.values) { out[key, default: [:]][basis] = value }
        }
        return out
    }

    struct Mutation {
        enum Class { case structure, content }
        var name: String
        var kind: Class
        var text: String
        /// Class (a): the rows (by key) that must be unread unless the table is declined.
        var touched: Set<String> = []
        /// Class (b): the truth of the mutated text.
        var mutatedTruth: [String: [LabelBasis: Value]]?
        /// The serving size must not be read (the moved serving quantity).
        var servingMustNotBeRead = false
    }

    // MARK: Class (a)

    static func structureMutations(_ fixture: Fixture, _ layout: Layout) -> [Mutation] {
        var out: [Mutation] = []
        let base = lines(fixture, layout)
        let columns = fixture.bases.count
        func add(_ name: String, _ mutated: [String], touched: Set<String>, servingMustNotBeRead: Bool = false) {
            out.append(Mutation(name: "\(fixture.name) \(layout.rawValue) \(name)", kind: .structure, text: text(mutated), touched: touched,
                                servingMustNotBeRead: servingMustNotBeRead))
        }
        for (r, row) in fixture.rows.enumerated() {
            let key: Set<String> = row.key.map { [$0] } ?? []
            let start = lineIndex(fixture, layout, row: r)
            // Drop a value, and duplicate a value.
            var dropped = base
            var duplicated = base
            switch layout {
            case .inline:
                dropped[start] = ([row.label] + row.values.dropLast().map(\.printed)).joined(separator: " ")
                duplicated[start] = ([row.label] + row.values.map(\.printed) + [row.values.last!.printed]).joined(separator: " ")
            case .stacked:
                dropped.remove(at: start + columns)
                duplicated.insert(row.values.last!.printed, at: start + columns + 1)
            }
            add("drop a value of \(row.label)", dropped, touched: key)
            add("duplicate a value of \(row.label)", duplicated, touched: key)
            // Double a decimal point, or give a whole number one too many.
            let first = row.values[0]
            let doubled = first.decimal.contains(".") ? first.decimal + ".5" : first.decimal + ".5.5"
            add("double a decimal point in \(row.label)", base.map { $0 == base[start] || $0 == first.printed && layout == .stacked
                ? $0.replacingOccurrences(of: first.printed, with: doubled + first.unit) : $0 }, touched: key)
            // Full-width digits.
            let fullWidth = String(first.decimal.unicodeScalars.map { scalar in
                ("0"..."9").contains(Character(scalar)) ? Character(UnicodeScalar(scalar.value + 0xFEE0)!) : Character(scalar)
            })
            add("full-width digits in \(row.label)", base.map { $0 == base[start] || $0 == first.printed && layout == .stacked
                ? $0.replacingOccurrences(of: first.printed, with: fullWidth + first.unit) : $0 }, touched: key)
            // Insert a line of unrelated text with a number and unit after the row.
            let after = start + (layout == .inline ? 1 : 1 + columns)
            var unrelated = base
            unrelated.insert(layout == .inline ? "淨重 500公克" : "500公克", at: after)
            add("unrelated line after \(row.label)", unrelated, touched: layout == .inline ? [] : key)
            // Insert a second basis phrase after the row.
            var secondBasis = base
            secondBasis.insert("每100毫升", at: after)
            add("second basis after \(row.label)", secondBasis, touched: Set(fixture.rows.compactMap(\.key)))
            // Move the serving quantity line after the row (the serving label stands alone).
            var moved = base
            moved[1] = "每一份量"
            moved.insert("30公克", at: after)
            add("serving quantity after \(row.label)", moved, touched: [], servingMustNotBeRead: true)
        }
        // Thousands separators in the four-digit sodium value.
        if let r = fixture.rows.firstIndex(where: { $0.key == "sodium" }), let value = fixture.rows[r].values.last {
            let start = lineIndex(fixture, layout, row: r)
            let digits = value.decimal
            for separated in [",", "，", " "].map({ String(digits.prefix(1)) + $0 + String(digits.dropFirst()) }) {
                add("thousands separator \(separated)", base.enumerated().map { index, line in
                    index >= start && index <= start + (layout == .inline ? 0 : columns)
                        ? line.replacingOccurrences(of: value.printed, with: separated + value.unit) : line
                }, touched: ["sodium"])
            }
        }
        switch layout {
        case .stacked:
            for r in 1..<fixture.rows.count {
                let row = fixture.rows[r]
                let start = lineIndex(fixture, layout, row: r)
                // Move a label after its values: its values attach to the row above.
                var labelAfter = base
                let label = labelAfter.remove(at: start)
                labelAfter.insert(label, at: start + columns)
                add("label after its values: \(row.label)", labelAfter,
                    touched: Set([fixture.rows[r - 1].key, row.key].compactMap { $0 }))
            }
            // The last two rows: labels after all their values, and labels before all their values.
            let n = fixture.rows.count
            let lastTwo = Array(fixture.rows.suffix(2))
            let head = Array(base.prefix(lineIndex(fixture, layout, row: n - 2)))
            add("last two labels after their values", head + lastTwo.flatMap { $0.values.map(\.printed) } + lastTwo.map(\.label),
                touched: Set((fixture.rows.suffix(3)).compactMap(\.key)))
            add("last two labels before their values", head + lastTwo.map(\.label) + lastTwo.flatMap { $0.values.map(\.printed) },
                touched: Set(lastTwo.compactMap(\.key)))
            // Break the template order: exchange two adjacent mandatory rows, labels with their values.
            for r in 0..<(n - 1) where TaiwanRowAliases.templatePosition(fixture.rows[r].label) != nil
                && TaiwanRowAliases.templatePosition(fixture.rows[r + 1].label) != nil {
                var swapped = fixture.rows
                swapped.swapAt(r, r + 1)
                // The row that now stands after a row it should precede is the first deviation.
                add("template order: \(fixture.rows[r + 1].label) before \(fixture.rows[r].label)", lines(fixture, layout, rows: swapped),
                    touched: Set([fixture.rows[r].key].compactMap { $0 }))
            }
            // Mix inline and stacked rows.
            var mixed = base
            let first = lineIndex(fixture, layout, row: 1)
            mixed.replaceSubrange(first...(first + columns), with: [([fixture.rows[1].label] + fixture.rows[1].values.map(\.printed)).joined(separator: " ")])
            add("one row inline in a stacked table", mixed, touched: Set(fixture.rows.compactMap(\.key)))
        case .inline:
            var mixed = base
            let start = lineIndex(fixture, layout, row: 2)
            mixed.replaceSubrange(start...start, with: [fixture.rows[2].label] + fixture.rows[2].values.map(\.printed))
            add("one row stacked in an inline table", mixed, touched: Set(fixture.rows.compactMap(\.key)))
            // Drop the separator between two values of a row.
            if fixture.bases.count > 1 {
                for (r, row) in fixture.rows.enumerated() {
                    var joined = base
                    joined[lineIndex(fixture, layout, row: r)] = row.label + " " + row.values.map(\.printed).joined()
                    add("no separator between the values of \(row.label)", joined, touched: Set([row.key].compactMap { $0 }))
                }
            }
        }
        return out
    }

    // MARK: Class (b)

    static func contentMutations(_ fixture: Fixture, _ layout: Layout) -> [Mutation] {
        var out: [Mutation] = []
        func add(_ name: String, _ rows: [Row]) {
            out.append(Mutation(name: "\(fixture.name) \(layout.rawValue) \(name)", kind: .content, text: text(lines(fixture, layout, rows: rows)),
                                mutatedTruth: truth(fixture, rows: rows)))
        }
        for (r, row) in fixture.rows.enumerated() {
            // Swap two row labels (inline only: a stacked exchange is the pinned residual risk, or
            // a template-order break). The text now states the other row's values for each.
            if layout == .inline, r + 1 < fixture.rows.count {
                var rows = fixture.rows
                let other = rows[r + 1]
                rows[r] = Row(label: other.label, key: other.key, values: row.values)
                rows[r + 1] = Row(label: row.label, key: row.key, values: other.values)
                add("labels of \(row.label) and \(other.label) exchanged", rows)
            }
            // Change a unit to another valid unit.
            for (from, to) in [("公克", "毫克"), ("毫克", "公克"), ("大卡", "kJ")] where row.values.contains(where: { $0.unit == from }) {
                var rows = fixture.rows
                rows[r].values = row.values.map { Value(decimal: $0.decimal, unit: $0.unit == from ? to : $0.unit) }
                if to == "kJ" { rows[r].key = "energy_kj" }
                add("\(row.label) in \(to)", rows)
            }
        }
        // Substring traps: a label that contains a stored row's name is never that row.
        let traps: [(String, String, String?)] = [("飽和脂肪", "不飽和脂肪", nil), ("飽和脂肪", "單元不飽和脂肪酸", nil),
                                                  ("飽和脂肪", "多元不飽和脂肪酸", nil), ("脂肪", "不飽和脂肪", nil), ("糖", "添加糖", "added_sugars"),
                                                  ("鈉", "鈉鹽", nil), ("蛋白質", "植物蛋白質", nil)]
        for (original, trap, key) in traps {
            guard let r = fixture.rows.firstIndex(where: { $0.label == original }) else { continue }
            var rows = fixture.rows
            rows[r] = Row(label: trap, key: key, values: rows[r].values)
            add("\(original) replaced by \(trap)", rows)
        }
        // An English gloss naming another nutrient: a careful reader cannot tell which is meant,
        // so the row binds nothing (PR 3: `row_not_read: gloss_conflict`, 3.6 rule 3).
        for (original, gloss) in [("脂肪", "Protein"), ("糖", "Sodium"), ("蛋白質", "Total Fat")] {
            guard let r = fixture.rows.firstIndex(where: { $0.label == original }) else { continue }
            var rows = fixture.rows
            rows[r] = Row(label: original + " " + gloss, key: nil, values: rows[r].values)
            add("\(original) glossed \(gloss)", rows)
        }
        return out
    }

    // MARK: PR 3: the flattened and bilingual layouts (3.4, 3.6)

    /// The layouts PR 3 adds to the suite: the whole table on one line (rows separated by `，`,
    /// the basis phrases before the first row), and the bilingual template (an English gloss after
    /// each Chinese label, every value printed with a bracketed English unit and its Chinese unit).
    enum NewLayout: String, CaseIterable { case flattened, bilingual }

    static let glosses = ["熱量": "Calories", "蛋白質": "Protein", "脂肪": "Total Fat", "飽和脂肪": "Saturated Fat", "反式脂肪": "Trans Fat",
                          "碳水化合物": "Total Carbohydrate", "糖": "Sugars", "膳食纖維": "Dietary Fiber", "鈉": "Sodium", "膽固醇": "Cholesterol"]
    static let englishUnits = ["大卡": "kcal", "公克": "g", "毫克": "mg", "kJ": "kJ"]
    static let englishHeaders = ["每份": "Per Serving", "每100公克": "Per 100g"]

    static func valueText(_ value: Value, _ layout: NewLayout) -> String {
        switch layout {
        case .flattened: value.printed
        case .bilingual: value.unit == "kJ" ? value.printed : "\(value.decimal)(\(englishUnits[value.unit] ?? "g"))\(value.unit)"
        }
    }

    /// A row's tokens: its printed label (with its gloss when bilingual), then one text per value.
    static func tokens(_ row: Row, _ layout: NewLayout) -> [String] {
        let label = layout == .bilingual ? glosses[row.label].map { "\(row.label) \($0)" } ?? row.label : row.label
        return [label] + row.values.map { valueText($0, layout) }
    }

    static func header(_ fixture: Fixture, _ layout: NewLayout) -> String {
        switch layout {
        case .flattened: fixture.header
        case .bilingual: fixture.header.split(separator: " ").map { "\($0) \(englishHeaders[String($0)] ?? "")" }.joined(separator: " ")
        }
    }

    static func head(_ layout: NewLayout) -> [String] {
        switch layout {
        case .flattened: preamble
        case .bilingual: ["營養標示 Nutrition Facts", "每一份量 Serving Size 30公克", "本包裝含8份 (8 Servings Per Package)"]
        }
    }

    /// Renders rows of tokens: one line for the flattened layout, one line per row for bilingual.
    /// `extraLines` are inserted after the line of row index `at` (bilingual) or as tokens after the
    /// row (flattened).
    static func render(_ fixture: Fixture, _ layout: NewLayout, head: [String]? = nil, header headerText: String? = nil,
                       rows: [[String]]) -> String {
        let top = head ?? Self.head(layout)
        let headerLine = headerText ?? header(fixture, layout)
        switch layout {
        case .flattened: return text(top + [headerLine + " " + rows.map { $0.joined(separator: " ") }.joined(separator: "，")])
        case .bilingual: return text(top + [headerLine] + rows.map { $0.joined(separator: " ") })
        }
    }

    static func newStructureMutations(_ fixture: Fixture, _ layout: NewLayout) -> [Mutation] {
        var out: [Mutation] = []
        let base = fixture.rows.map { tokens($0, layout) }
        let all = Set(fixture.rows.compactMap(\.key))
        func add(_ name: String, _ text: String, touched: Set<String>, servingMustNotBeRead: Bool = false) {
            out.append(Mutation(name: "\(fixture.name) \(layout.rawValue) \(name)", kind: .structure, text: text, touched: touched,
                                servingMustNotBeRead: servingMustNotBeRead))
        }
        func fullWidth(_ text: String) -> String {
            String(text.unicodeScalars.map { ("0"..."9").contains(Character($0)) ? Character(UnicodeScalar($0.value + 0xFEE0)!) : Character($0) })
        }
        for (r, row) in fixture.rows.enumerated() {
            let key: Set<String> = row.key.map { [$0] } ?? []
            var dropped = base; dropped[r].removeLast()
            add("drop a value of \(row.label)", render(fixture, layout, rows: dropped), touched: key)
            var duplicated = base; duplicated[r].append(base[r].last!)
            add("duplicate a value of \(row.label)", render(fixture, layout, rows: duplicated), touched: key)
            let first = row.values[0]
            let doubledDecimal = first.decimal.contains(".") ? first.decimal + ".5" : first.decimal + ".5.5"
            var doubled = base; doubled[r][1] = valueText(Value(decimal: doubledDecimal, unit: first.unit), layout)
            add("double a decimal point in \(row.label)", render(fixture, layout, rows: doubled), touched: key)
            var wide = base; wide[r][1] = fullWidth(base[r][1])
            add("full-width digits in \(row.label)", render(fixture, layout, rows: wide), touched: key)
            if row.values.count > 1 {
                var joined = base; joined[r] = [base[r][0], base[r].dropFirst().joined()]
                add("no separator between the values of \(row.label)", render(fixture, layout, rows: joined), touched: key)
            }
            // An unrelated row with a number and a unit after the row (read but not used, or the
            // segmentation fails).
            var unrelated = base
            unrelated.insert(layout == .bilingual ? ["淨重 Net Weight", "500(g)公克"] : ["淨重", "500公克"], at: r + 1)
            add("unrelated row after \(row.label)", render(fixture, layout, rows: unrelated), touched: [])
            // A second basis phrase before the row.
            if r > 0 {
                var second = base
                second[r][0] = (layout == .bilingual ? "每100毫升 Per 100ml\n" : "每100毫升 ") + second[r][0]
                add("second basis before \(row.label)", render(fixture, layout, rows: second), touched: all)
            }
            // The serving quantity moved after the row; the serving label stands alone.
            var moved = base
            moved[r].append(layout == .bilingual ? "\n30公克" : "30公克")
            var servingHead = head(layout)
            servingHead[1] = layout == .bilingual ? "每一份量 Serving Size" : "每一份量"
            add("serving quantity after \(row.label)", render(fixture, layout, head: servingHead, rows: moved), touched: key,
                servingMustNotBeRead: true)
            // A percentage on this row only (no reference column is printed).
            var percent = base; percent[r].append("5%")
            add("percentage on \(row.label) only", render(fixture, layout, rows: percent), touched: [])
            if layout == .flattened {
                // A stray number after the row.
                var stray = base; stray[r].append("，7")
                add("stray number after \(row.label)", render(fixture, layout, rows: stray), touched: [])
                // No separator between this row and the next: a unit followed by a label is well-formed.
                if r + 1 < base.count {
                    var glued = base
                    glued[r] = [glued[r].joined(separator: " ") + glued[r + 1].joined(separator: " ")]
                    glued.remove(at: r + 1)
                    add("no separator after \(row.label)", render(fixture, layout, rows: glued), touched: [])
                }
            }
            // The label after its values.
            if r > 0 {
                var after = base; after[r] = Array(base[r].dropFirst()) + [base[r][0]]
                add("label after its values: \(row.label)", render(fixture, layout, rows: after),
                    touched: layout == .flattened ? Set([fixture.rows[r - 1].key, row.key].compactMap { $0 }) : key)
            }
        }
        // Thousands separators in the four-digit sodium value.
        if let r = fixture.rows.firstIndex(where: { $0.key == "sodium" }), let value = fixture.rows[r].values.last {
            for separator in [",", "，", " "] {
                var separated = base
                let digits = value.decimal
                separated[r][separated[r].count - 1] = valueText(Value(decimal: String(digits.prefix(1)) + separator + String(digits.dropFirst()),
                                                                        unit: value.unit), layout)
                add("thousands separator \(separator)", render(fixture, layout, rows: separated), touched: ["sodium"])
            }
        }
        // A row on a line of its own beside the flattened line, or one row stacked in a bilingual table.
        switch layout {
        case .flattened:
            var rest = base
            let moved = rest.remove(at: 1)
            add("one row inline beside the flattened line", render(fixture, layout, rows: rest) + moved.joined(separator: " ") + "\n", touched: all)
            // The basis phrases on a line of their own before the flattened line read the same.
            let separate = text(head(layout) + [fixture.header, base.map { $0.joined(separator: " ") }.joined(separator: "，")])
            add("header on its own line", separate, touched: [])
        case .bilingual:
            var stacked = base
            stacked[2] = [stacked[2].joined(separator: "\n")]
            add("one row stacked in a bilingual table", render(fixture, layout, rows: stacked), touched: all)
            // A conflicting English header: the Chinese basis and the English one disagree.
            let conflicting = fixture.header.split(separator: " ").map { "\($0) \($0 == "每份" ? "Per 100g" : "Per Serving")" }.joined(separator: " ")
            add("conflicting English header", render(fixture, layout, header: conflicting, rows: base), touched: all)
            // A value printed with its Chinese unit only reads the same.
            var single = base; single[1][1] = fixture.rows[1].values[0].printed
            add("Chinese unit only on one value", render(fixture, layout, rows: single), touched: [])
        }
        return out
    }

    static func newContentMutations(_ fixture: Fixture, _ layout: NewLayout) -> [Mutation] {
        var out: [Mutation] = []
        func add(_ name: String, _ rows: [Row], text override: String? = nil) {
            out.append(Mutation(name: "\(fixture.name) \(layout.rawValue) \(name)", kind: .content,
                                text: override ?? render(fixture, layout, rows: rows.map { tokens($0, layout) }), mutatedTruth: truth(fixture, rows: rows)))
        }
        for (r, row) in fixture.rows.enumerated() {
            // Two labels exchanged: the text now states the other row's values for each.
            if r + 1 < fixture.rows.count {
                var rows = fixture.rows
                let other = rows[r + 1]
                rows[r] = Row(label: other.label, key: other.key, values: row.values)
                rows[r + 1] = Row(label: row.label, key: row.key, values: other.values)
                add("labels of \(row.label) and \(other.label) exchanged", rows)
            }
            for (from, to) in [("公克", "毫克"), ("毫克", "公克"), ("大卡", "kJ")] where row.values.contains(where: { $0.unit == from }) {
                var rows = fixture.rows
                rows[r].values = row.values.map { Value(decimal: $0.decimal, unit: $0.unit == from ? to : $0.unit) }
                if to == "kJ" { rows[r].key = "energy_kj" }
                add("\(row.label) in \(to)", rows)
            }
            // Bilingual: the bracketed English unit disagrees with the Chinese unit, so the text
            // states two units for the value; a careful reader records nothing for the row.
            if layout == .bilingual, row.values.contains(where: { $0.unit == "公克" }) {
                var rows = fixture.rows
                rows[r].key = nil
                var tokens = fixture.rows.map { Self.tokens($0, layout) }
                tokens[r][1] = tokens[r][1].replacingOccurrences(of: "(g)", with: "(mg)")
                add("\(row.label) printed in (mg)公克", rows, text: render(fixture, layout, rows: tokens))
            }
        }
        let traps: [(String, String, String?)] = [("飽和脂肪", "不飽和脂肪", nil), ("飽和脂肪", "單元不飽和脂肪酸", nil), ("脂肪", "不飽和脂肪", nil),
                                                  ("糖", "添加糖", "added_sugars"), ("鈉", "鈉鹽", nil), ("蛋白質", "植物蛋白質", nil)]
        for (original, trap, key) in traps {
            guard let r = fixture.rows.firstIndex(where: { $0.label == original }) else { continue }
            var rows = fixture.rows
            rows[r] = Row(label: trap, key: key, values: rows[r].values)
            add("\(original) replaced by \(trap)", rows)
        }
        // An English gloss naming another nutrient: the row binds nothing.
        for (original, gloss) in [("脂肪", "Protein"), ("糖", "Sodium"), ("蛋白質", "Total Fat"), ("鈉", "Sugars")] {
            guard let r = fixture.rows.firstIndex(where: { $0.label == original }) else { continue }
            var rows = fixture.rows
            rows[r] = Row(label: original + " " + gloss, key: nil, values: rows[r].values)
            add("\(original) glossed \(gloss)", rows)
        }
        return out
    }

    // MARK: Oracle

    struct Outcome {
        var failures: [String] = []
        var declined = false
        var unread = 0
    }

    static func check(_ mutation: Mutation, truth original: [String: [LabelBasis: Value]]) -> Outcome {
        let candidate = NutritionLabelTextParserV3().parse(mutation.text, inputSHA256: String(repeating: "0", count: 64))
        var outcome = Outcome()
        // A candidate that fails the gate's schema validation (full-width digits, contract v1
        // section 1) is the hard decline `unreadable_table` in the product: nothing is bound.
        if candidate.declined || !LabelDeclineGate.validationErrors(candidate).isEmpty {
            outcome.declined = true
            return outcome
        }
        let truth = mutation.mutatedTruth ?? original
        for cell in candidate.cells where cell.nutrient != "unrecognised" && cell.basis != .referenceIntake {
            guard let expected = truth[cell.nutrient]?[cell.basis] else {
                outcome.failures.append("\(mutation.name): \(cell.nutrient) \(cell.basis.rawValue) bound to \(cell.printedText) with no truth")
                continue
            }
            if cell.decimalText != expected.decimal || cell.canonicalUnit != expected.canonical || cell.comparator != .equal {
                outcome.failures.append("\(mutation.name): \(cell.nutrient) \(cell.basis.rawValue) bound to \(cell.printedText), truth \(expected.printed)")
            }
        }
        for key in mutation.touched where candidate.cells.contains(where: { $0.nutrient == key }) {
            outcome.failures.append("\(mutation.name): touched row \(key) was read")
        }
        if mutation.servingMustNotBeRead, candidate.servingSize?.decimalText != nil {
            outcome.failures.append("\(mutation.name): the moved serving quantity was read as the serving size")
        }
        outcome.unread = candidate.warnings.filter { $0.hasPrefix("row_not_read: ") }.count
        return outcome
    }
}

@Test func test2EveryUnmutatedFixtureReadsItsTruthInBothLayouts() {
    for fixture in MutationSuite.fixtures {
        for layout in MutationSuite.Layout.allCases {
            let text = MutationSuite.text(MutationSuite.lines(fixture, layout))
            let candidate = NutritionLabelTextParserV3().parse(text, inputSHA256: String(repeating: "0", count: 64))
            #expect(!candidate.declined, "\(fixture.name) \(layout): \(candidate.declineReasons)")
            let expected = MutationSuite.truth(fixture).values.map(\.count).reduce(0, +)
            #expect(candidate.cells.filter { $0.nutrient != "unrecognised" }.count == expected, "\(fixture.name) \(layout)")
            let outcome = MutationSuite.check(MutationSuite.Mutation(name: "\(fixture.name) \(layout)", kind: .structure, text: text),
                                              truth: MutationSuite.truth(fixture))
            #expect(outcome.failures.isEmpty, "\(outcome.failures)")
            #expect(candidate.warnings.filter { $0.hasPrefix("row_not_read") }.isEmpty, "\(candidate.warnings)")
            #expect(candidate.servingSize?.decimalText == "30")
        }
    }
}

@Test func test2EveryUnmutatedFixtureReadsItsTruthInTheFlattenedAndBilingualLayouts() {
    for fixture in MutationSuite.fixtures {
        for layout in MutationSuite.NewLayout.allCases {
            let text = MutationSuite.render(fixture, layout, rows: fixture.rows.map { MutationSuite.tokens($0, layout) })
            let candidate = NutritionLabelTextParserV3().parse(text, inputSHA256: String(repeating: "0", count: 64))
            #expect(!candidate.declined, "\(fixture.name) \(layout): \(candidate.declineReasons)")
            let expected = MutationSuite.truth(fixture).values.map(\.count).reduce(0, +)
            #expect(candidate.cells.filter { $0.nutrient != "unrecognised" }.count == expected, "\(fixture.name) \(layout)")
            let outcome = MutationSuite.check(MutationSuite.Mutation(name: "\(fixture.name) \(layout)", kind: .structure, text: text),
                                              truth: MutationSuite.truth(fixture))
            #expect(outcome.failures.isEmpty, "\(outcome.failures)")
            #expect(candidate.warnings.filter { $0.hasPrefix("row_not_read") }.isEmpty, "\(candidate.warnings)")
            #expect(candidate.servingSize?.decimalText == "30")
            #expect(candidate.language == .traditionalChinese, "\(fixture.name) \(layout)")
        }
    }
}

/// The suite's tallies, pinned exactly (PR 2 review): any change in either direction is deliberate
/// and is recorded in sections 8.2 and 8.3 of the design. Keys: class, then the layouts PR 2 built
/// (inline and stacked) and those PR 3 adds (flattened and bilingual).
enum MutationTally {
    struct Entry: Equatable, CustomStringConvertible {
        var count = 0, declined = 0, withUnread = 0
        var readInFull: Int { count - declined - withUnread }
        var description: String { "\(count) mutations, \(declined) declined, \(withUnread) read with rows not read, \(readInFull) read with every row read" }
    }

    static let pinned: [String: Entry] = [
        "(a) structure-breaking, inline and stacked": Entry(count: 324, declined: 234, withUnread: 70),
        "(b) content-changing, inline and stacked": Entry(count: 95, declined: 2, withUnread: 42),
        "(a) structure-breaking, flattened and bilingual": Entry(count: 410, declined: 291, withUnread: 68),
        "(b) content-changing, flattened and bilingual": Entry(count: 126, declined: 12, withUnread: 54),
    ]
}

@Test func test2MutationSuiteBindsNoWrongValue() {
    var failures: [String] = []
    var tally: [String: MutationTally.Entry] = [:]
    func record(_ mutation: MutationSuite.Mutation, _ family: String, truth: [String: [LabelBasis: MutationSuite.Value]]) {
        let outcome = MutationSuite.check(mutation, truth: truth)
        failures += outcome.failures
        let name = (mutation.kind == .structure ? "(a) structure-breaking, " : "(b) content-changing, ") + family
        var entry = tally[name] ?? MutationTally.Entry()
        entry.count += 1
        if outcome.declined { entry.declined += 1 } else if outcome.unread > 0 { entry.withUnread += 1 }
        tally[name] = entry
    }
    for fixture in MutationSuite.fixtures {
        let truth = MutationSuite.truth(fixture)
        for layout in MutationSuite.Layout.allCases {
            for mutation in MutationSuite.structureMutations(fixture, layout) + MutationSuite.contentMutations(fixture, layout) {
                record(mutation, "inline and stacked", truth: truth)
            }
        }
        for layout in MutationSuite.NewLayout.allCases {
            for mutation in MutationSuite.newStructureMutations(fixture, layout) + MutationSuite.newContentMutations(fixture, layout) {
                record(mutation, "flattened and bilingual", truth: truth)
            }
        }
    }
    for (name, entry) in tally.sorted(by: { $0.key < $1.key }) {
        print("mutation suite \(name): \(entry)")
    }
    #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    for (name, pinned) in MutationTally.pinned {
        #expect(tally[name] == pinned, "\(name): \(tally[name].map(\.description) ?? "none"), pinned \(pinned)")
    }
}

/// Decision 18, the accepted residual risk, pinned: in a stacked table, an exchange of the value
/// lines of two adjacent rows printing the same unit, with the labels left in template order, is
/// indistinguishable from a correct table by structure. The reader binds the values in text
/// order (so they differ from the original truth), and the existing checks warn where their
/// arithmetic is violated. This test fails if that behaviour changes in either direction.
@Test func test2PinnedResidualRiskStackedSameUnitValueExchange() {
    let fixture = MutationSuite.oneColumn
    func exchanged(_ a: String, _ b: String) -> LabelCaptureCandidate {
        var rows = fixture.rows
        let i = rows.firstIndex { $0.label == a }!, j = rows.firstIndex { $0.label == b }!
        (rows[i].values, rows[j].values) = (rows[j].values, rows[i].values)
        return NutritionLabelTextParserV3().parse(MutationSuite.text(MutationSuite.lines(fixture, .stacked, rows: rows)),
                                                  inputSHA256: String(repeating: "0", count: 64))
    }
    func value(_ candidate: LabelCaptureCandidate, _ nutrient: String) -> String? {
        candidate.cells.first { $0.nutrient == nutrient }?.decimalText
    }
    func failed(_ candidate: LabelCaptureCandidate) -> Set<String> {
        Set(LabelArithmeticChecks.check(LabelArithmeticTable(candidate, format: .taiwan)).checks.filter { $0.status == .fail }.map(\.name))
    }
    // Protein and fat exchanged: both read, each with the other's value; no structural signal.
    let proteinFat = exchanged("蛋白質", "脂肪")
    #expect(!proteinFat.declined)
    #expect(value(proteinFat, "protein") == "12.6")
    #expect(value(proteinFat, "fat") == "7.4")
    #expect(!proteinFat.warnings.contains { $0.hasPrefix("row_not_read") }, "\(proteinFat.warnings)")
    // The energy check passes within its tolerance (4 × 12.6 + 9 × 7.4 + 4 × 64.1 = 373.4 against
    // 389 printed): no check sees this exchange. That is the accepted risk; the owner's real-text
    // bar (zero wrong values) still applies to every real label.
    #expect(failed(proteinFat).isEmpty, "\(failed(proteinFat))")
    // Fat and saturated fat exchanged: the sub-row check warns (saturates above fat).
    let fatSaturates = exchanged("脂肪", "飽和脂肪")
    #expect(value(fatSaturates, "fat") == "4.2")
    #expect(value(fatSaturates, "saturates") == "12.6")
    #expect(failed(fatSaturates).contains("subrow_not_above_parent"), "\(failed(fatSaturates))")
    // Fibre (optional) and sugars exchanged: both read in text order.
    let fibreSugars = exchanged("膳食纖維", "糖")
    #expect(value(fibreSugars, "fibre") == "21.8")
    #expect(value(fibreSugars, "sugars") == "5.3")
    #expect(!fibreSugars.declined)
}
