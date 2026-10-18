import Foundation

/// The label format a gate run is for (gate v2 knows exactly these two).
public enum LabelGateFormat: String, Codable, CaseIterable, Sendable {
    case taiwan = "taiwan_nutrition_labelling"
    case uk = "uk_nutrition_declaration"
}

/// Gate v2's reasons, G1 to G6. G1 and G2 are hard declines in the product; G3 to G6 become
/// flags on Confirm (`docs/pasted-nutrition-label-v1.md` sections 2.4, 3.1 and 3.2). The raw gate
/// still reports G3 and G4 as declines and G5 and G6 as ready blocks, exactly as gate v2 does.
public enum LabelGateReason: String, Codable, CaseIterable, Sendable {
    case unsupportedScript = "unsupported_script"
    case notAFoodNutritionPanel = "not_a_food_nutrition_panel"
    case requiredRowMissing = "required_row_missing"
    case columnCountMismatch = "column_count_mismatch"
    case requiredBasisMissing = "required_basis_missing"
    case requiredServingDeclarationMissing = "required_serving_declaration_missing"

    public var rule: String {
        switch self {
        case .unsupportedScript: "G1"
        case .notAFoodNutritionPanel: "G2"
        case .requiredRowMissing: "G3"
        case .columnCountMismatch: "G4"
        case .requiredBasisMissing: "G5"
        case .requiredServingDeclarationMissing: "G6"
        }
    }

    /// True for G1 and G2, the only gate findings that stop the reader in the product.
    public var isHardDecline: Bool { self == .unsupportedScript || self == .notAFoodNutritionPanel }
}

/// Why gate v2 did not evaluate a candidate.
public enum LabelGateSkip: String, Codable, Sendable {
    case failedCandidate = "failed_candidate"
    case alreadyDeclined = "already_declined"
}

/// Gate v2's report for one candidate. `declines`, `blocks` and `details` are the raw gate v2
/// output, in rule order; `hardDeclines` and `flags` are the product's reading of them.
public struct LabelGateReport: Equatable, Sendable {
    public var gateVersion: String
    public var labelFormat: LabelGateFormat
    public var declines: [LabelGateReason]
    public var blocks: [LabelGateReason]
    public var details: [String]
    public var skipped: LabelGateSkip?

    /// G1 and G2: the input cannot be used (section 3.1).
    public var hardDeclines: [LabelGateReason] { (declines + blocks).filter(\.isHardDecline) }
    /// G3 to G6: shown on Confirm as exceptions, never a decline (section 3.2).
    public var flags: [LabelGateReason] { (declines + blocks).filter { !$0.isHardDecline } }
}

/// Swift port of `label-capture-decline-gate-v2` (`Tools/NutritionLabelCaptureEvaluation/decline_gate.py`).
///
/// Pure and Foundation only. It reads the candidate and the declared or inferred format, never
/// changes a value, and reads gate v2's Simplified-only set and Python character classes from the
/// frozen tables (`LabelGateTables`). Parity with the Python gate is tested on every development
/// and untouched pasted-text vector and exhaustively over every code point in `HAN_RANGES` and
/// `UNSUPPORTED_RANGES` (contract tests 1 and 25).
public enum LabelDeclineGate {
    public static let version = "label-capture-decline-gate-v2"

    // Version block: the frozen tables and their SHA-256 (checked by the package tests).
    public static let simplifiedOnlyTableResource = "gate-v2-simplified-only-v1.txt"
    public static let simplifiedOnlyTableSHA256 = "a75bd032fb24c234686bc808ab1926cc502380f8421d2ba833bdceffb9dfafa5"
    public static let markerClassesTableResource = "gate-v2-marker-classes-v1.txt"
    public static let markerClassesTableSHA256 = "65761772f268b4c7ec41d096ebd4ac9f01f10a1fe5e8bf7144898781f7855109"

    public static let requiredRows: [LabelGateFormat: [String]] = [
        .uk: ["energy_kj", "energy_kcal", "fat", "saturates", "carbohydrate", "sugars", "protein", "salt"],
        .taiwan: ["energy_kcal", "protein", "fat", "saturates", "trans_fat", "carbohydrate", "sugars", "sodium"],
    ]

    /// Hiragana, Katakana (less U+30FB and U+30FC), Katakana phonetic extensions, halfwidth
    /// Katakana, and every Hangul block.
    public static let unsupportedRanges: [ClosedRange<UInt32>] = [
        0x3040...0x309F,
        0x30A0...0x30FA,
        0x30FD...0x30FF,
        0x31F0...0x31FF,
        0xFF66...0xFF9F,
        0x1100...0x11FF,
        0x3130...0x318F,
        0xA960...0xA97F,
        0xAC00...0xD7AF,
        0xD7B0...0xD7FF,
        0xFFA0...0xFFDC,
    ]
    public static let hanRanges: [ClosedRange<UInt32>] = [0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF]
    /// Shared variant code points, never counted as Simplified (gate v2).
    public static let sharedVariants: Set<Character> = ["内", "温", "黄", "户", "着", "奥", "吴", "吕", "没", "别", "强", "兑", "虚", "册"]

    // MARK: Classification

    public static func isSimplifiedOnly(_ scalar: Unicode.Scalar) -> Bool {
        // The frozen table already leaves out shared variants and anything outside HAN_RANGES.
        LabelGateTables.shared.simplifiedOnly.contains(scalar.value)
    }

    public static func isUnsupportedScript(_ scalar: Unicode.Scalar) -> Bool {
        unsupportedRanges.contains { $0.contains(scalar.value) }
    }

    /// Supplement markers in one printed string, lowered, in match order (Python `finditer`).
    public static func supplementMarkers(in text: String) -> [String] {
        SupplementMarkerMatcher(tables: LabelGateTables.shared).loweredMatches(in: text)
    }

    // MARK: Gate

    /// Gate v2's findings for one candidate, without changing it (Python `evaluate`).
    public static func evaluate(_ candidate: LabelCaptureCandidate, format: LabelGateFormat) -> LabelGateReport {
        var declines: [LabelGateReason] = []
        var blocks: [LabelGateReason] = []
        var details: [String] = []

        let found = scriptFindings(printedTexts(candidate))
        if !found.isEmpty {
            declines.append(.unsupportedScript)
            details.append(contentsOf: found)
        }

        var markerTexts = candidate.headers.map(\.printedText) + candidate.cells.map(\.printedLabel)
        if let serving = candidate.servingSize { markerTexts.append(serving.printedText) }
        let markers = Set(markerTexts.flatMap(supplementMarkers(in:))).sorted(by: pythonStringPrecedes)
        if !markers.isEmpty {
            declines.append(.notAFoodNutritionPanel)
            details.append("supplement_markers: " + markers.joined(separator: ", "))
        }

        let per100Headers = candidate.headers.filter { $0.basis == .per100g || $0.basis == .per100ml }.map(\.headerID)
        var byNutrient: [String: Set<String>] = [:]
        for cell in candidate.cells where cell.basis != .referenceIntake {
            byNutrient[cell.nutrient, default: []].insert(cell.headerID)
        }
        let required = requiredRows[format] ?? []
        let missing = required.filter { byNutrient[$0] == nil }
        if !missing.isEmpty {
            declines.append(.requiredRowMissing)
            details.append("required_rows_without_amount: " + missing.joined(separator: ", "))
        }
        let short = required.filter { row in
            guard let headers = byNutrient[row] else { return false }
            return per100Headers.contains { !headers.contains($0) }
        }
        if !short.isEmpty {
            declines.append(.columnCountMismatch)
            details.append("required_rows_missing_a_column: " + short.joined(separator: ", "))
        }

        switch format {
        case .uk:
            if !candidate.headers.contains(where: { $0.basis == .per100g || $0.basis == .per100ml }) {
                blocks.append(.requiredBasisMissing)
            }
        case .taiwan:
            if candidate.servingSize == nil || candidate.servingsPerPack == nil {
                blocks.append(.requiredServingDeclarationMissing)
            }
        }
        return LabelGateReport(gateVersion: version, labelFormat: format, declines: declines, blocks: blocks, details: details, skipped: nil)
    }

    /// Python `apply_gate`: the gated candidate and the report. It never changes a value; it only
    /// declines (withholding every cell) or blocks ready. A `nil` or schema-invalid candidate and
    /// one the parser already declined pass through untouched.
    public static func apply(_ candidate: LabelCaptureCandidate?, format: LabelGateFormat) -> (candidate: LabelCaptureCandidate?, report: LabelGateReport) {
        let skipped = LabelGateReport(gateVersion: version, labelFormat: format, declines: [], blocks: [], details: [], skipped: nil)
        guard let candidate, validationErrors(candidate).isEmpty else {
            var report = skipped
            report.skipped = .failedCandidate
            return (candidate, report)
        }
        if candidate.declined {
            var report = skipped
            report.skipped = .alreadyDeclined
            return (candidate, report)
        }
        let report = evaluate(candidate, format: format)
        if !report.declines.isEmpty {
            var gated = candidate
            gated.declined = true
            gated.declineReasons = candidate.declineReasons + report.declines.map { "gate:" + $0.rawValue }
            gated.wouldMarkReady = false
            gated.servingSize = nil
            gated.servingsPerPack = nil
            gated.headers = []
            gated.cells = []
            gated.warnings = candidate.warnings + report.details.map { "\(version): \($0)" }
            return (gated, report)
        }
        if !report.blocks.isEmpty, candidate.wouldMarkReady {
            var gated = candidate
            gated.wouldMarkReady = false
            gated.warnings = candidate.warnings + report.blocks.map { "\(version): blocks ready: \($0.rawValue)" }
            return (gated, report)
        }
        return (candidate, report)
    }

    // MARK: Helpers (Python `printed_texts`, `script_findings`, `validate_candidate`)

    static func printedTexts(_ candidate: LabelCaptureCandidate) -> [String] {
        var texts = candidate.headers.map(\.printedText)
        for cell in candidate.cells {
            texts.append(cell.printedLabel)
            texts.append(cell.printedText)
        }
        if let serving = candidate.servingSize { texts.append(serving.printedText) }
        if let perPack = candidate.servingsPerPack { texts.append(perPack.printedText) }
        return texts
    }

    /// Details list each offending character once, sorted by Unicode scalar (Python `sorted` of a set of `str`).
    static func scriptFindings(_ texts: [String]) -> [String] {
        var simplified = Set<UInt32>()
        var other = Set<UInt32>()
        for text in texts {
            for scalar in text.unicodeScalars {
                if isSimplifiedOnly(scalar) { simplified.insert(scalar.value) }
                if isUnsupportedScript(scalar) { other.insert(scalar.value) }
            }
        }
        var findings: [String] = []
        if !simplified.isEmpty { findings.append("simplified_only_characters: " + joined(simplified)) }
        if !other.isEmpty { findings.append("kana_or_hangul: " + joined(other)) }
        return findings
    }

    private static func joined(_ values: Set<UInt32>) -> String {
        var view = String.UnicodeScalarView()
        for value in values.sorted() {
            if let scalar = Unicode.Scalar(value) { view.append(scalar) }
        }
        return String(view)
    }

    static let routes: Set<String> = ["A", "B", "C"]
    static let nutrients: Set<String> = [
        "energy_kj", "energy_kcal", "fat", "saturates", "trans_fat", "carbohydrate", "sugars",
        "added_sugars", "fibre", "protein", "salt", "sodium", "unrecognised",
    ]
    static let canonicalUnits: Set<String> = ["kJ", "kcal", "cal", "g", "mg", "µg", "ml", "%"]

    /// The schema and policy errors of `candidate.validate_candidate` that a typed candidate can
    /// still have. Typing already rules out wrong JSON types, unknown enum values for basis,
    /// comparator and language, missing keys and extra keys. Patterns follow Python `re.search`,
    /// where `$` also matches before one final newline.
    public static func validationErrors(_ candidate: LabelCaptureCandidate) -> [String] {
        var errors: [String] = []
        if !routes.contains(candidate.route) { errors.append("$.route: not in enum") }
        if !pythonFullMatch(candidate.inputSHA256, allowed: { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }, count: 64) {
            errors.append("$.input_sha256: does not match pattern")
        }
        for (index, cell) in candidate.cells.enumerated() {
            if !nutrients.contains(cell.nutrient) { errors.append("$.cells[\(index)].nutrient: not in enum") }
            if !canonicalUnits.contains(cell.canonicalUnit) { errors.append("$.cells[\(index)].canonical_unit: not in enum") }
            if !isPythonDecimalText(cell.decimalText) { errors.append("$.cells[\(index)].decimal_text: does not match pattern") }
        }
        if candidate.declined, !candidate.cells.isEmpty { errors.append("$.cells: a declined candidate keeps every cell unknown (no cells)") }
        if candidate.declined, candidate.declineReasons.isEmpty { errors.append("$.decline_reasons: a decline must list its reasons") }
        if candidate.declined, candidate.wouldMarkReady { errors.append("$.would_mark_ready: a declined table can never be ready") }
        var headerBases: [String: LabelBasis] = [:]
        for header in candidate.headers { headerBases[header.headerID] = header.basis }
        for (index, cell) in candidate.cells.enumerated() {
            if headerBases[cell.headerID] != cell.basis { errors.append("$.cells[\(index)]: header and basis do not agree") }
            if cell.basis == .referenceIntake, cell.canonicalUnit != "%" {
                errors.append("$.cells[\(index)]: a reference-intake cell is never a product amount")
            }
            if cell.basis != .perServing, !["not_applicable", "unknown"].contains(cell.servingConversion) {
                errors.append("$.cells[\(index)]: only per-serving cells carry a serving conversion")
            }
        }
        return errors
    }

    /// Python `re.search("^[class]{count}$", text)`: one final `\n` is allowed after the match.
    private static func pythonFullMatch(_ text: String, allowed: (UInt32) -> Bool, count: Int) -> Bool {
        var scalars = Array(text.unicodeScalars.map(\.value))
        if scalars.last == 0x0A { scalars.removeLast() }
        return scalars.count == count && scalars.allSatisfy(allowed)
    }

    /// Python `re.search("^[0-9]+([.,][0-9]+)?$", text)`, ASCII digits only, one final `\n` allowed.
    static func isPythonDecimalText(_ text: String) -> Bool {
        var scalars = Array(text.unicodeScalars.map(\.value))
        if scalars.last == 0x0A { scalars.removeLast() }
        let isDigit: (UInt32) -> Bool = { (0x30...0x39).contains($0) }
        guard let separator = scalars.firstIndex(where: { !isDigit($0) }) else { return !scalars.isEmpty }
        guard separator > 0, scalars[separator] == 0x2E || scalars[separator] == 0x2C else { return false }
        let fraction = scalars[(separator + 1)...]
        return !fraction.isEmpty && fraction.allSatisfy(isDigit)
    }
}
