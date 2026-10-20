import Foundation
import FoodLedgerDomain

/// Consumer-owned port for reading nutrition-label text (`docs/pasted-nutrition-label-v1.md`
/// sections 2.4 and 8.1, decision 10). The adapter (`FoodLabelTextCapture`) runs the parser, the
/// gate, format inference, the conversions and the arithmetic checks, and maps their output to an
/// application-owned `LabelReading`; no parser type crosses the port.
///
/// Reading is pure and on device: no network, clock, randomness or hashing. The caller supplies
/// the SHA-256 of the text's UTF-8 bytes.
public protocol LabelTextReading: Sendable {
    func read(_ text: String, textSHA256: String) -> LabelReading
}

/// What the reader found, origin-neutral so a later photo route can reuse it (section 8.5).
/// It is evidence for Confirm only: nothing here saves or enables Log.
public struct LabelReading: Equatable, Sendable {
    public enum Origin: String, Sendable {
        case pastedText = "pasted_text"
    }

    /// The reader's version identifiers, recorded in the manifest and the source release.
    public struct Versions: Equatable, Sendable {
        public let parser: String
        public let gate: String
        public let arithmetic: String
        public let conversion: String
        public let formatInference: String
        public init(parser: String, gate: String, arithmetic: String, conversion: String, formatInference: String) {
            self.parser = parser; self.gate = gate; self.arithmetic = arithmetic
            self.conversion = conversion; self.formatInference = formatInference
        }
    }

    /// A G3 to G6 finding, with the row, cell or line it concerns: a nutrient (`sodium`), a
    /// nutrient and column (`sodium@h2`), `per_100` (G5), or `serving_size` / `servings_per_pack` (G6).
    public struct Flag: Equatable, Hashable, Sendable {
        public let code: String
        public let concerns: String
        public init(code: String, concerns: String) { self.code = code; self.concerns = concerns }

        /// The nutrient a row or cell flag concerns, and the column for a cell flag.
        public var nutrient: String? {
            guard code == PastedLabelCodes.requiredRowMissing || code == PastedLabelCodes.columnCountMismatch else { return nil }
            return concerns.split(separator: "@", maxSplits: 1).first.map(String.init)
        }

        public var headerID: String? {
            let parts = concerns.split(separator: "@", maxSplits: 1)
            return parts.count == 2 ? String(parts[1]) : nil
        }
    }

    /// The faithful gate's outcome, split for the product: hard declines (G1 and G2, or
    /// `unreadable_table` when the candidate failed validation or the gate tables could not be
    /// read) and flags (G3 to G6). `skipped` is gate v2's own skip reason.
    public struct Gate: Equatable, Sendable {
        public let format: String
        public let skipped: String?
        public let hardDeclines: [String]
        public let flags: [Flag]
        public init(format: String, skipped: String?, hardDeclines: [String], flags: [Flag]) {
            self.format = format; self.skipped = skipped; self.hardDeclines = hardDeclines; self.flags = flags
        }

        /// The gate evaluated the candidate and found no hard decline (`failed_candidate` is
        /// unreadable, never usable).
        public var isUsable: Bool { skipped == nil && hardDeclines.isEmpty }
    }

    /// One arithmetic or consistency check (`label-arithmetic-checks-v1`). A failure is a
    /// non-blocking warning; a pass is never shown (section 4).
    public struct Check: Equatable, Sendable {
        public enum Status: String, Sendable { case pass, fail, notCheckable = "not_checkable" }
        public let name: String
        public let basis: String?
        public let nutrient: String?
        public let child: String?
        public let status: Status
        public init(name: String, basis: String?, nutrient: String?, child: String?, status: Status) {
            self.name = name; self.basis = basis; self.nutrient = nutrient; self.child = child; self.status = status
        }

        /// The warning code shown on Confirm for a failed check, else `nil`.
        public var warningCode: String? {
            guard status == .fail else { return nil }
            return ([name] + [basis, nutrient, child].compactMap { $0 }).joined(separator: ":")
        }
    }

    public let origin: Origin
    public let textSHA256: String
    /// The parsed candidate, mirrored key for key (`label-capture-candidate-v1`).
    public let candidate: PastedLabelManifest.Candidate
    /// Format inference: `taiwan_nutrition_labelling`, `uk_nutrition_declaration`,
    /// `us_nutrition_facts` or `format_ambiguous`.
    public let format: String
    /// `nil` when the gate has no format to run under (US, ambiguous) or the parser declined
    /// before a format could be inferred from a table.
    public let gate: Gate?
    public let checks: [Check]
    /// The `pasted-label-conversions-v1` records for the stored column.
    public let conversions: [PastedLabelManifest.Conversion]
    /// The stored column under the fixed rule of section 6.3, when there is one.
    public let storedHeaderID: String?
    public let versions: Versions

    public init(origin: Origin, textSHA256: String, candidate: PastedLabelManifest.Candidate, format: String, gate: Gate?,
                checks: [Check], conversions: [PastedLabelManifest.Conversion], storedHeaderID: String?, versions: Versions) {
        self.origin = origin; self.textSHA256 = textSHA256; self.candidate = candidate; self.format = format
        self.gate = gate; self.checks = checks; self.conversions = conversions
        self.storedHeaderID = storedHeaderID; self.versions = versions
    }

    /// Warning codes for every failed check, in check order, without repeats.
    public var warningCodes: [String] {
        var seen: Set<String> = []
        return checks.compactMap(\.warningCode).filter { seen.insert($0).inserted }
    }
}

/// The launch scope (section 5, decisions 3 and 4): the gate formats the product reads. It is
/// applied after the faithful gate; a UK table that passes the gate is still declined
/// `layout_not_supported` here. Adding UK after its release gate changes only this constant
/// and the copy it feeds. The scope in force is recorded in the manifest (`launch_scope`).
public enum PastedLabelLaunchScope {
    public static let enabledFormats: [String] = ["taiwan_nutrition_labelling"]

    public static func admits(_ format: String) -> Bool { enabledFormats.contains(format) }
}

/// Identity mapping `pasted-label-identity-v1` reads values for the food as sold only (section
/// 6.5). A header (or its serving wording) for the food as prepared or drained is an identity
/// difference and declines `basis_state_not_supported`.
public enum PastedLabelBasisState {
    /// English markers, matched as whole words, case-insensitively: "unprepared" and "undrained"
    /// do not match (owner, 19 October 2026; contract section 8.8).
    public static let wordMarkers: [String] = ["prepared", "drained"]
    /// Traditional Chinese markers, matched as substrings.
    public static let substringMarkers: [String] = ["沖泡", "瀝乾"]

    public static func isAsSold(_ candidate: PastedLabelManifest.Candidate) -> Bool {
        let texts = candidate.headers.flatMap { [$0.printedText, $0.servingConversion ?? ""] }
        return !texts.contains(where: marks)
    }

    /// Whether one printed header or serving wording marks the as-prepared or drained state.
    public static func marks(_ text: String) -> Bool {
        if substringMarkers.contains(where: text.contains) { return true }
        // A word is a maximal run of letters; anything else (space, digit, punctuation) ends it.
        let words = text.lowercased().split { !$0.isLetter }
        return words.contains { wordMarkers.contains(String($0)) }
    }
}

/// Every code the reader can produce, classified as exactly one of hard decline (section 3.1)
/// or Confirm flag (section 3.2), with the copy key the presentation renders. A code with no
/// mapping renders `unreadable_table` (test 27).
public enum PastedLabelCodes {
    public static let requiredRowMissing = "required_row_missing"
    public static let columnCountMismatch = "column_count_mismatch"
    public static let requiredBasisMissing = "required_basis_missing"
    public static let requiredServingDeclarationMissing = "required_serving_declaration_missing"
    public static let textTooLong = "text_too_long"
    public static let layoutNotSupported = "layout_not_supported"
    public static let formatAmbiguous = "format_ambiguous"
    public static let noTable = "no_table"
    public static let unreadableTable = "unreadable_table"
    public static let layoutAmbiguous = "layout_ambiguous"

    public enum Kind: String, Sendable { case hardDecline = "hard_decline", flag }

    /// Copy keys. The presentation (PR 4) owns the words; the keys are closed here.
    public enum CopyKey: String, CaseIterable, Sendable {
        case supplementPanel = "supplement_panel"
        case unsupportedLanguage = "unsupported_language"
        case noTable = "no_table"
        case layoutNotSupported = "layout_not_supported"
        case basisStateNotSupported = "basis_state_not_supported"
        case valuesNotBound = "values_not_bound"
        case textTooLong = "text_too_long"
        case unreadableTable = "unreadable_table"
        case rowNotRead = "row_not_read"
        case cellNotRead = "cell_not_read"
        case noPer100Column = "no_per_100_column"
        case servingLineNotRead = "serving_line_not_read"
    }

    public struct Classification: Equatable, Sendable {
        public let kind: Kind
        public let copy: CopyKey
        public init(kind: Kind, copy: CopyKey) { self.kind = kind; self.copy = copy }
    }

    /// The closed mapping. Hard declines are exactly the section 3.1 set; flags are G3 to G6.
    public static let mapping: [String: Classification] = {
        func decline(_ copy: CopyKey) -> Classification { Classification(kind: .hardDecline, copy: copy) }
        func flag(_ copy: CopyKey) -> Classification { Classification(kind: .flag, copy: copy) }
        return [
            // Gate G2 and G1, parser language.
            "not_a_food_nutrition_panel": decline(.supplementPanel),
            "unsupported_language": decline(.unsupportedLanguage),
            "unsupported_script": decline(.unsupportedLanguage),
            noTable: decline(.noTable),
            // Launch scope and format inference.
            layoutNotSupported: decline(.layoutNotSupported),
            formatAmbiguous: decline(.layoutNotSupported),
            PastedLabelIdentity.basisStateNotSupported: decline(.basisStateNotSupported),
            // Parser v2 binding failures: no cells are returned.
            "multiple_panels": decline(.valuesNotBound),
            "no_basis_header": decline(.valuesNotBound),
            "duplicate_basis": decline(.valuesNotBound),
            "count_mismatch": decline(.valuesNotBound),
            "values_without_row": decline(.valuesNotBound),
            "energy_without_unit": decline(.valuesNotBound),
            "value_without_unit": decline(.valuesNotBound),
            "unrecognised_unit": decline(.valuesNotBound),
            // Parser v3 (reader v3 section 3.0, decision 19): a body that is not exactly one layout.
            layoutAmbiguous: decline(.unreadableTable),
            textTooLong: decline(.textTooLong),
            unreadableTable: decline(.unreadableTable),
            // Gate G3 to G6: flags on Confirm, never a decline.
            requiredRowMissing: flag(.rowNotRead),
            columnCountMismatch: flag(.cellNotRead),
            requiredBasisMissing: flag(.noPer100Column),
            requiredServingDeclarationMissing: flag(.servingLineNotRead)
        ]
    }()

    /// The classification of `code`; any code without its own mapping is the hard decline
    /// `unreadable_table`.
    public static func classify(_ code: String) -> Classification {
        mapping[code] ?? Classification(kind: .hardDecline, copy: .unreadableTable)
    }
}

/// The reader's verdict for the label text screen: a hard decline (stay on the screen, text
/// kept) or a reading that may open Confirm with its flags and warnings.
public enum PastedLabelReadOutcome: Equatable, Sendable {
    case declined(codes: [String], reading: LabelReading?)
    case usable(PastedLabelReview)

    public var declineCodes: [String] {
        if case let .declined(codes, _) = self { return codes }
        return []
    }
}

/// A usable reading on its way to Confirm (section 3.2): the flags still shown after calculated
/// values satisfy their rows, and the warning codes of failed checks.
public struct PastedLabelReview: Equatable, Sendable {
    public let pastedText: String
    public let reading: LabelReading
    public let storedHeaderID: String
    public let flags: [LabelReading.Flag]
    public let warningCodes: [String]
}

/// Read label (section 2.4): the length limit, the injected digest, the reader, then the
/// product's reading of the gate, the launch scope and the identity mapping's basis state.
/// It never saves, never hashes or keeps declined text beyond this call, and never changes a value.
public struct PastedLabelReader: Sendable {
    private let reader: any LabelTextReading
    private let digester: any Digesting

    public init(reader: any LabelTextReading, digester: any Digesting) {
        self.reader = reader; self.digester = digester
    }

    public func read(_ text: String) -> PastedLabelReadOutcome {
        // Section 6.2: Unicode scalars, checked before parsing or hashing.
        guard text.unicodeScalars.count <= PastedLabelManifest.maximumTextScalars else {
            return .declined(codes: [PastedLabelCodes.textTooLong], reading: nil)
        }
        guard let hash = try? digester.sha256(Data(text.utf8)) else {
            return .declined(codes: [PastedLabelCodes.unreadableTable], reading: nil)
        }
        let reading = reader.read(text, textSHA256: hash.value)
        return Self.classify(reading, pastedText: text)
    }

    /// The product's decision on a reading, in the section 2.4 order.
    public static func classify(_ reading: LabelReading, pastedText: String) -> PastedLabelReadOutcome {
        let candidate = reading.candidate
        if candidate.declined {
            let codes = candidate.declineReasons.isEmpty ? [PastedLabelCodes.unreadableTable] : candidate.declineReasons
            return .declined(codes: codes, reading: reading)
        }
        var codes: [String] = []
        // The faithful gate first: G1, G2, or an unreadable candidate.
        if let gate = reading.gate {
            // A skipped gate (`failed_candidate`, unreadable tables) is unreadable, never usable.
            if gate.skipped != nil, gate.hardDeclines.isEmpty { codes.append(PastedLabelCodes.unreadableTable) }
            codes.append(contentsOf: gate.hardDeclines)
        }
        // Then the launch scope: an ambiguous format, or any format not enabled (UK, US).
        if reading.format == PastedLabelCodes.formatAmbiguous {
            codes.append(PastedLabelCodes.formatAmbiguous)
        } else if !PastedLabelLaunchScope.admits(reading.format) {
            codes.append(PastedLabelCodes.layoutNotSupported)
        } else if reading.gate == nil {
            codes.append(PastedLabelCodes.unreadableTable)
        }
        if !PastedLabelBasisState.isAsSold(candidate) {
            codes.append(PastedLabelIdentity.basisStateNotSupported)
        }
        guard let stored = reading.storedHeaderID, candidate.headers.contains(where: { $0.headerID == stored }) else {
            codes.append(PastedLabelCodes.noTable)
            return .declined(codes: unique(codes), reading: reading)
        }
        guard codes.isEmpty, let gate = reading.gate else { return .declined(codes: unique(codes), reading: reading) }
        let calculated = Set(reading.conversions.map(\.nutrient))
        // A calculated value in the stored column satisfies the row's G3 (or its G4 cell there).
        let flags = gate.flags.filter { flag in
            guard let nutrient = flag.nutrient, calculated.contains(nutrient) else { return true }
            return !(flag.code == PastedLabelCodes.requiredRowMissing || flag.headerID == stored)
        }
        return .usable(PastedLabelReview(pastedText: pastedText, reading: reading, storedHeaderID: stored,
                                         flags: flags, warningCodes: reading.warningCodes))
    }

    private static func unique(_ codes: [String]) -> [String] {
        var seen: Set<String> = []
        return codes.filter { seen.insert($0).inserted }
    }
}
