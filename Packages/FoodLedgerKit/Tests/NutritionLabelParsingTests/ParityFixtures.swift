import CryptoKit
import Foundation
@testable import NutritionLabelParsing

// Parity vectors exported by `Tools/NutritionLabelCaptureEvaluation/export_swift_parity.py` from
// committed development cases, re-rendered synthetic untouched template cases and hand-built
// synthetic candidates. Expected values are the frozen Python reference's own output.

enum ParityFixtures {
    struct FixtureError: Error, CustomStringConvertible {
        let description: String
    }

    static func data(_ name: String) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let url = Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: parts[0], withExtension: parts[1]) else {
            throw FixtureError(description: "missing fixture \(name)")
        }
        return try Data(contentsOf: url)
    }

    /// JSON lines split on U+000A only (the JSON keeps U+0085 and U+2028 unescaped).
    static func lines(_ name: String) throws -> [[String: Any]] {
        try data(name).split(separator: 0x0A).map { line in
            guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw FixtureError(description: "\(name): a line is not an object")
            }
            return object
        }
    }

    static func object(_ name: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data(name)) as? [String: Any] else {
            throw FixtureError(description: "\(name) is not an object")
        }
        return object
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `parity-sha256-v1.txt`: file name to recorded SHA-256.
    static func recordedHashes() throws -> [String: String] {
        guard let text = String(data: try data("parity-sha256-v1.txt"), encoding: .utf8) else { throw FixtureError(description: "hash list") }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if fields.count == 2 { out[fields[1]] = fields[0] }
        }
        return out
    }

    static func candidate(_ object: Any?) throws -> LabelCaptureCandidate? {
        guard let object, !(object is NSNull) else { return nil }
        return try JSONDecoder().decode(LabelCaptureCandidate.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// A JSON value with every `null` member removed, so a candidate that omits an optional key and
    /// one that writes it as `null` compare equal.
    static func withoutNulls(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.filter { !($0.value is NSNull) }.mapValues(withoutNulls)
        }
        if let array = value as? [Any] { return array.map(withoutNulls) }
        return value
    }

    static func jsonObject(_ candidate: LabelCaptureCandidate) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate))
    }

    static func sameJSON(_ left: Any, _ right: Any) -> Bool {
        (withoutNulls(left) as AnyObject).isEqual(withoutNulls(right))
    }

    static func decimal(_ value: Any?) -> Decimal? {
        guard let text = value as? String else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: Gate and arithmetic in the Python reference's JSON shape

    static func reportObject(_ report: LabelGateReport) -> [String: Any] {
        [
            "gate_version": report.gateVersion,
            "label_format": report.labelFormat.rawValue,
            "declines": report.declines.map(\.rawValue),
            "blocks": report.blocks.map(\.rawValue),
            "details": report.details,
            "skipped": report.skipped?.rawValue ?? NSNull(),
        ]
    }

    static let decimalKeys: Set<String> = ["printed_kcal", "allowed_difference", "ratio", "per_serving", "expected", "slack"]

    /// Differences between a Swift check and the Python check: same keys, same strings, and
    /// numbers equal as normalised decimals.
    static func checkDifferences(_ swift: LabelCheckResult, _ python: [String: Any]) -> [String] {
        var mine: [String: Any] = ["name": swift.name, "status": swift.status.rawValue]
        if let basis = swift.basis { mine["basis"] = basis }
        if let nutrient = swift.nutrient { mine["nutrient"] = nutrient }
        if let child = swift.child { mine["child"] = child }
        if let value = swift.printedKcal { mine["printed_kcal"] = value }
        if let value = swift.allowedDifference { mine["allowed_difference"] = value }
        if let value = swift.ratio { mine["ratio"] = value }
        if let value = swift.perServing { mine["per_serving"] = value }
        if let value = swift.expected { mine["expected"] = value }
        if let value = swift.slack { mine["slack"] = value }
        if let forms = swift.forms { mine["forms"] = forms }
        var problems: [String] = []
        if Set(mine.keys) != Set(python.keys) { problems.append("keys \(mine.keys.sorted()) != \(python.keys.sorted())") }
        for (key, value) in python {
            if decimalKeys.contains(key) {
                if (mine[key] as? Decimal) != decimal(value) { problems.append("\(key): \(String(describing: mine[key])) != \(value)") }
            } else if key == "forms" {
                let theirs = value as? [[String: Any]] ?? []
                let ours = swift.forms ?? []
                if ours.count != theirs.count { problems.append("forms count") }
                for (a, b) in zip(ours, theirs) where a.form != b["form"] as? String || a.computedKcal != decimal(b["computed_kcal"]) || a.difference != decimal(b["difference"]) {
                    problems.append("form \(a) != \(b)")
                }
            } else if (mine[key] as? String) != (value as? String) {
                problems.append("\(key): \(String(describing: mine[key])) != \(value)")
            }
        }
        return problems
    }

    static func reportDifferences(_ swift: LabelArithmeticReport, _ python: [String: Any]) -> [String] {
        var problems: [String] = []
        if swift.status.rawValue != python["status"] as? String { problems.append("status \(swift.status) != \(python["status"] ?? "nil")") }
        if swift.warnings != python["warnings"] as? [String] { problems.append("warnings \(swift.warnings)") }
        let checks = python["checks"] as? [[String: Any]] ?? []
        if swift.checks.count != checks.count { problems.append("check count \(swift.checks.count) != \(checks.count)") }
        for (index, (mine, theirs)) in zip(swift.checks, checks).enumerated() {
            problems += checkDifferences(mine, theirs).map { "check \(index): \($0)" }
        }
        return problems
    }

    /// Truth (or a mutated truth) in `label-capture-truth-v1` shape as an arithmetic table.
    static func truthTable(_ truth: [String: Any], jurisdiction: String) throws -> LabelArithmeticTable {
        let cells = try (truth["cells"] as? [[String: Any]] ?? []).map { cell -> LabelArithmeticCell in
            guard let nutrient = cell["nutrient"] as? String, let basis = cell["basis"] as? String,
                  let unit = cell["canonical_unit"] as? String, let comparator = cell["comparator"] as? String,
                  let printedUnit = cell["unit"] as? String, let printed = cell["printed_text"] as? String else {
                throw FixtureError(description: "truth cell shape: \(cell)")
            }
            return LabelArithmeticCell(
                nutrient: nutrient, basis: basis, canonicalUnit: unit, comparator: comparator,
                decimalText: cell["decimal_text"] as? String, parentRowID: cell["parent_row_id"] as? String,
                unit: printedUnit, printedText: printed
            )
        }
        let serving = (truth["serving_size"] as? [String: Any]).map {
            LabelArithmeticTable.Serving(decimalText: $0["decimal_text"] as? String, canonicalUnit: $0["canonical_unit"] as? String)
        }
        let perPack = (truth["servings_per_pack"] as? [String: Any]).map {
            LabelArithmeticTable.PerPack(decimalText: $0["decimal_text"] as? String, approximate: $0["approximate"] as? Bool ?? false)
        }
        return LabelArithmeticTable(jurisdiction: jurisdiction, declined: truth["declined"] as? Bool ?? false, servingSize: serving, servingsPerPack: perPack, cells: cells)
    }
}
