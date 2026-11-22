import ConfirmEnrichmentEvalCore
import FoodLedgerApplication
import Foundation

public enum EvalReviewSheet {
    struct Invalid: Error {}

    static func header() -> [String] {
        [EvalSelection.reviewSheetNote, EvalSelection.reviewSheetHeader.map(EvalSelection.csvField).joined(separator: ",")]
    }

    static func row(_ item: EvalCase, product: [String: Any]) throws -> String {
        guard let code = product["code"] as? String else { throw Invalid() }
        let hash = try EvalHashes.hash(item)
        let fortified = EvalSelector.fortified(product) ? "yes" : "no"
        let fields = [hash, EvalSelector.name(product), (product["brands"] as? String) ?? "", code, fortified]
        return (fields + Array(repeating: "", count: 6)).map(EvalSelection.csvField).joined(separator: ",")
    }

    static func bytes(_ lines: [String]) -> Data {
        Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    public static func writeSealed(_ list: EvalCaseList, folder: URL) throws -> Int {
        let cases = list.cases.filter { $0.kind == .openFoodFacts }
        var lines = header()
        for item in cases {
            let product = try EvalCandidates.record(for: item, privateFolder: folder)
            lines.append(try row(item, product: product))
        }
        let path = folder.appendingPathComponent("review-sheet-sealed.csv")
        let staging = folder.appendingPathComponent(".sealed-review-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try bytes(lines).write(to: staging, options: .withoutOverwriting)
        try FileManager.default.moveItem(at: staging, to: path)
        return cases.count
    }

    /// Reads only the owner-checked columns and their case digest. Names and barcodes have no role in scoring.
    static func read(_ url: URL, expected: Set<String>) throws -> [String: [ConfirmDetailsFact: String]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var csv = text[...]
        if csv.first == "\u{FEFF}" { csv.removeFirst() }
        while csv.first == "#" {
            let note = csv.prefix { !$0.isNewline }
            csv.removeFirst(note.count)
            _ = csv.popFirst()
        }
        guard let records = rows(csv), records.first == EvalSelection.reviewSheetHeader else { throw Invalid() }
        var result: [String: [ConfirmDetailsFact: String]] = [:]
        for values in records.dropFirst() {
            guard values.count == EvalSelection.reviewSheetHeader.count,
                  expected.contains(values[0]), result[values[0]] == nil else { throw Invalid() }
            var facts: [ConfirmDetailsFact: String] = [:]
            for (fact, value) in zip(ConfirmDetailsFact.allCases, values.dropFirst(5)) {
                guard fact.choices.contains(value) || (fact == .fortification && value == "fortified") else { throw Invalid() }
                facts[fact] = value
            }
            result[values[0]] = facts
        }
        guard Set(result.keys) == expected else { throw Invalid() }
        return result
    }

    private static func rows(_ csv: Substring) -> [[String]]? {
        var rows: [[String]] = []
        var fields: [String] = []
        var input = csv
        while !input.isEmpty {
            var field = ""
            if input.first == "\"" {
                input.removeFirst()
                while true {
                    guard let char = input.popFirst() else { return nil }
                    if char != "\"" {
                        field.append(char)
                    } else if input.first == "\"" {
                        input.removeFirst()
                        field.append(char)
                    } else {
                        break
                    }
                }
            } else {
                let plain = input.prefix { $0 != "," && !$0.isNewline }
                guard !plain.contains("\"") else { return nil }
                field = String(plain)
                input.removeFirst(plain.count)
            }
            fields.append(field)
            let separator = input.popFirst()
            if separator == "," {
                if input.isEmpty { fields.append("") }
                else { continue }
            } else if separator?.isNewline == false {
                return nil
            }
            if fields != [""] { rows.append(fields) }
            fields.removeAll()
        }
        return rows
    }
}
