import Foundation
import FoodLedgerDomain

// The basis choice of `docs/pasted-nutrition-label-reader-v3.md` sections 3.3 and 8.4: a table
// whose amount columns printed no basis header is read only after the user says what the values
// are for. Every type here is application-owned; no parser type crosses the port.

/// The user's bases for amount columns printed with no basis header, in column order (8.4.2).
/// By type it holds only amount bases: a reference-intake column can never be asserted.
public struct AssertedBases: Equatable, Hashable, Sendable {
    public enum Basis: String, CaseIterable, Sendable {
        case perServing = "per_serving"
        case per100g = "per_100g"
        case per100ml = "per_100ml"
    }

    public let columns: [Basis]

    public init(_ columns: [Basis]) { self.columns = columns }
}

/// What the reader hands the application about an unheaded table (8.4.1). The adapter fills it
/// from the parser's side result, because the declined candidate carries no rows, cells, serving
/// size or pack count.
public struct UnheadedTable: Equatable, Sendable {
    public struct EnergyLineHint: Equatable, Sendable {
        /// The bracket as printed (`每100毫升`).
        public let printedText: String
        public let basis: AssertedBases.Basis
        public init(printedText: String, basis: AssertedBases.Basis) { self.printedText = printedText; self.basis = basis }
    }

    /// 1 or 2.
    public let amountColumnCount: Int
    /// The IDs the asserted headers take, in column order (`header_1`, `header_2`).
    public let amountHeaderIDs: [String]
    public let referenceColumnPrinted: Bool
    public let servingSize: PastedLabelManifest.Candidate.ServingSize?
    public let servingsPerPack: PastedLabelManifest.Candidate.ServingsPerPack?
    public let energyLineHint: EnergyLineHint?

    public init(amountColumnCount: Int, referenceColumnPrinted: Bool, servingSize: PastedLabelManifest.Candidate.ServingSize?,
                servingsPerPack: PastedLabelManifest.Candidate.ServingsPerPack?, energyLineHint: EnergyLineHint?) {
        self.amountColumnCount = amountColumnCount
        amountHeaderIDs = (0..<amountColumnCount).map { "header_\($0 + 1)" }
        self.referenceColumnPrinted = referenceColumnPrinted
        self.servingSize = servingSize; self.servingsPerPack = servingsPerPack; self.energyLineHint = energyLineHint
    }
}

/// The closed option table (8.4.3): a pure function of the amount column count and the serving
/// size's unit, computable both before the choice (from `UnheadedTable`) and from a stored v2
/// candidate, so the verifier recomputes `offered` from the stored bytes alone.
public enum PastedLabelBasisOptions {
    public enum ServingUnit: String, Sendable { case none, grams = "g", millilitres = "ml" }

    /// One option: the column bases in column order.
    public struct Arrangement: Equatable, Hashable, Sendable {
        public let bases: [AssertedBases.Basis]
        public init(_ bases: [AssertedBases.Basis]) { self.bases = bases }

        /// `per_100g`, `per_serving,per_100ml`: the `offered` encoding.
        public var identifier: String { bases.map(\.rawValue).joined(separator: ",") }
        public var assertedBases: AssertedBases { AssertedBases(bases) }

        public init?(identifier: String) {
            let parts = identifier.split(separator: ",", omittingEmptySubsequences: false).map { AssertedBases.Basis(rawValue: String($0)) }
            guard !parts.isEmpty, !parts.contains(nil) else { return nil }
            bases = parts.compactMap { $0 }
        }
    }

    /// The one serving-unit mapping (gate re-check, medium 4): a serving size with a positive
    /// `decimal_text` and canonical unit `g` or `ml` maps to that unit, whether serving v3 reads
    /// it as exact, approximate or a range; anything else is `none`.
    public static func servingUnit(_ size: PastedLabelManifest.Candidate.ServingSize?) -> ServingUnit {
        guard let quantity = PastedLabelSource.servingQuantity(size) else { return .none }
        return quantity.unit == .millilitres ? .millilitres : .grams
    }

    /// The options in order, or nil for "no sheet, decline" (two columns with no serving size, or
    /// a column count other than 1 or 2). "I'm not sure" is never an option.
    public static func options(amountColumnCount: Int, servingUnit: ServingUnit) -> [Arrangement]? {
        switch (amountColumnCount, servingUnit) {
        case (1, .none): [Arrangement([.per100g]), Arrangement([.per100ml])]
        case (1, .grams): [Arrangement([.perServing]), Arrangement([.per100g]), Arrangement([.per100ml])]
        case (1, .millilitres): [Arrangement([.perServing]), Arrangement([.per100ml]), Arrangement([.per100g])]
        case (2, .grams): [Arrangement([.perServing, .per100g]), Arrangement([.perServing, .per100ml])]
        case (2, .millilitres): [Arrangement([.perServing, .per100ml]), Arrangement([.perServing, .per100g])]
        default: nil
        }
    }

    public static func options(for table: UnheadedTable) -> [Arrangement]? {
        options(amountColumnCount: table.amountColumnCount, servingUnit: servingUnit(table.servingSize))
    }

    /// The options a stored v2 candidate was offered: its amount headers and its serving size.
    public static func options(for candidate: PastedLabelManifest.Candidate) -> [Arrangement]? {
        let amounts = candidate.headers.filter { $0.basis != "reference_intake" }.count
        return options(amountColumnCount: amounts, servingUnit: servingUnit(candidate.servingSize))
    }
}

/// The user's choice, bound to the reading it was made on (8.4.9).
public struct PastedLabelBasisChoice: Equatable, Sendable {
    public let arrangement: PastedLabelBasisOptions.Arrangement
    /// The arrangement identifiers offered, in order.
    public let offered: [String]
    /// Whole milliseconds since 1970, truncated from the injected clock at the choice.
    public let at: Int64

    public init(arrangement: PastedLabelBasisOptions.Arrangement, offered: [String], at: Int64) {
        self.arrangement = arrangement; self.offered = offered; self.at = at
    }

    /// Truncation to whole milliseconds (gate re-check, medium 3).
    /// A value within a microsecond of a whole millisecond is that millisecond, so a date that
    /// went through a millisecondsSince1970 Double round trip (and may land a hair below its
    /// millisecond) gives the same whole milliseconds on both sides of `at <= capturedAt`.
    public static func milliseconds(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1000
        let nearest = value.rounded()
        return Int64(abs(value - nearest) < 0.001 ? nearest : value.rounded(.down))
    }
}

/// The basis sheet's input (8.4.8): the declined reading, the unheaded table and every offered
/// option already read and classified as usable (8.4.7), so choosing never re-reads.
public struct PastedLabelBasisChoiceRequest: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public let arrangement: PastedLabelBasisOptions.Arrangement
        /// The option's usable review, without a choice.
        public let review: PastedLabelReview
        public init(arrangement: PastedLabelBasisOptions.Arrangement, review: PastedLabelReview) {
            self.arrangement = arrangement; self.review = review
        }

        /// The option's `basis_plausibility` warnings (8.4.4), shown beside it on the sheet.
        public var plausibilityWarnings: [String] {
            review.reading.checks.filter { $0.name == PastedLabelBasisOrigin.plausibilityCheck && $0.status == .fail }.compactMap(\.warningCode)
        }
    }

    public let pastedText: String
    public let declinedReading: LabelReading
    public let unheaded: UnheadedTable
    public let options: [Option]

    public init(pastedText: String, declinedReading: LabelReading, unheaded: UnheadedTable, options: [Option]) {
        self.pastedText = pastedText; self.declinedReading = declinedReading; self.unheaded = unheaded; self.options = options
    }

    public var textSHA256: String { declinedReading.textSHA256 }
    public var offered: [String] { options.map(\.arrangement.identifier) }
    /// One column and no serving size: Per serving is not offered, and the sheet says why.
    public var perServingUnavailable: Bool {
        unheaded.amountColumnCount == 1 && PastedLabelBasisOptions.servingUnit(unheaded.servingSize) == .none
    }

    /// Decision 24 (8.4.12): the hint differs when its basis is not one of the arrangement's bases.
    public func hintDiffers(_ arrangement: PastedLabelBasisOptions.Arrangement) -> Bool {
        guard let hint = unheaded.energyLineHint else { return false }
        return !arrangement.bases.contains(hint.basis)
    }

    /// The review of a chosen option (8.4.8): the option's review with the choice stamped `at`,
    /// and, when the hint differs, `basis_hint:energy_line` after every other warning code.
    public func review(choosing arrangement: PastedLabelBasisOptions.Arrangement, at: Int64) -> PastedLabelReview? {
        guard let option = options.first(where: { $0.arrangement == arrangement }) else { return nil }
        let review = option.review
        var codes = review.warningCodes
        if hintDiffers(arrangement) { codes.append(PastedLabelCodes.basisHintShown) }
        return PastedLabelReview(pastedText: review.pastedText, reading: review.reading, storedHeaderID: review.storedHeaderID,
                                 flags: review.flags, warningCodes: codes,
                                 basisChoice: PastedLabelBasisChoice(arrangement: arrangement, offered: offered, at: at))
    }
}

/// Where the stored column's basis came from (8.4.11), derived in one place for Confirm, the
/// saved entry, the misread report and Developer tools.
public enum PastedLabelBasisOrigin: Equatable, Sendable {
    case printed
    /// Chosen by the user. `hint` is the energy line's bracket as printed, present only when the
    /// recorded warnings show it (decision 24: it differed from the choice); never re-derived.
    case chosenByYou(hint: String?)

    static let plausibilityCheck = "basis_plausibility"

    public init(chosen: Bool, candidate: PastedLabelManifest.Candidate, warningCodes: [String]) {
        guard chosen else { self = .printed; return }
        guard warningCodes.contains(PastedLabelCodes.basisHintShown) else { self = .chosenByYou(hint: nil); return }
        let hint = candidate.warnings.first { $0.hasPrefix(PastedLabelCodes.basisHintWarningPrefix) }
            .map { String($0.dropFirst(PastedLabelCodes.basisHintWarningPrefix.count)) }
        self = .chosenByYou(hint: hint)
    }

    public init(_ manifest: PastedLabelEvidenceManifest) {
        switch manifest {
        case .v1: self = .printed
        case let .v2(m): self.init(chosen: true, candidate: m.candidate, warningCodes: m.warningsShown)
        }
    }

    public var isChosen: Bool { if case .chosenByYou = self { return true }; return false }
}
