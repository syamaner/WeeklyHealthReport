import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// The pasted label's source section on Confirm (`docs/pasted-nutrition-label-v1.md` sections
/// 2.3, 3.2 and 3.5; assisted-UX principle 1.1). The app pre-fills every value it read, each
/// with its origin in words; the user checks them and can correct a value or enter one that was
/// not read. Every change rebuilds the source from a new manifest through the application's
/// confirmation builder and hands it to Confirm; nothing is saved until Log.
///
/// A stored entry (Edit, Recent foods, a favourite) shows the same rows read-only, from its
/// stored manifest: a logged label is never re-read or re-parsed.
@MainActor
public final class PastedLabelSourceModel: ObservableObject {
    /// One stored nutrient's row: the value, its origin and the printed text it came from.
    public struct Row: Equatable, Identifiable, Sendable {
        public enum Action: Equatable, Sendable { case correct, add, remove }
        /// The reader key (`protein`, `energy_kcal`).
        public let id: String
        public let key: NutrientKey
        public let title: String
        public let value: String
        public let origin: NutrientValueOrigin
        public let originText: String
        public let source: String?
        public let flag: String?
        public let actions: [Action]
        public let unit: String
        public let accessibilityLabel: String
    }

    /// A serving line: serving size or servings per pack.
    public struct Line: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let value: String
        public let flag: String?
        public let actions: [Row.Action]
        public let units: [String]
        public var accessibilityLabel: String { [title, value, flag].compactMap { $0 }.joined(separator: ", ") }
    }

    /// A printed row the ledger does not store, or a value from the other column.
    public struct Evidence: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let printedText: String
        public let note: String
    }

    @Published public private(set) var manifest: PastedLabelEvidenceManifest
    @Published public private(set) var nutrients: NutrientSet
    @Published public private(set) var corrections: [PastedLabelManifest.Correction]
    /// The input Confirm logs, rebuilt after each change. Nil for a stored entry.
    @Published public private(set) var input: PopulatedFoodConfirmation?
    @Published public private(set) var review: PastedLabelReview?
    private var details: PastedLabelDetails
    private let builder: PastedLabelConfirmation?
    private let locale: LedgerText?
    /// Called with every rebuilt input (Confirm replaces its source, keeping amount and time).
    public var onInputChange: ((PopulatedFoodConfirmation) -> Void)?

    /// Confirm for a new reading: builds the first input with no corrections.
    public init(review: PastedLabelReview, details: PastedLabelDetails, builder: PastedLabelConfirmation, locale: LedgerText) throws {
        let input = try builder.confirmation(review, details: details, corrections: [], locale: locale)
        guard let candidate = input.candidates.first,
              let manifest = PastedLabelValueOrigins.manifest(input, candidate: candidate) else {
            throw PastedLabelSourceError.invalidManifest("built input")
        }
        self.review = review; self.details = details; self.builder = builder; self.locale = locale
        self.manifest = manifest
        nutrients = candidate.candidate.nutrients
        corrections = []
        self.input = input
    }

    /// A stored v1 entry, read-only.
    public convenience init(stored manifest: PastedLabelManifest, nutrients: NutrientSet) {
        self.init(stored: .v1(manifest), nutrients: nutrients)
    }

    /// A stored entry of either manifest version, read-only.
    public init(stored manifest: PastedLabelEvidenceManifest, nutrients: NutrientSet) {
        review = nil; builder = nil; locale = nil
        details = PastedLabelDetails(name: manifest.name, brand: manifest.brand)
        self.manifest = manifest
        self.nutrients = nutrients
        corrections = manifest.corrections
        input = nil
    }

    /// The read-only model for a Confirm whose selected source is a pasted label, else nil.
    public static func stored(_ state: FoodConfirmationState) -> PastedLabelSourceModel? {
        guard let manifest = PastedLabelValueOrigins.manifest(state.input, candidate: state.selectedCandidate) else { return nil }
        return PastedLabelSourceModel(stored: manifest, nutrients: state.selectedCandidate.candidate.nutrients)
    }

    public var isEditable: Bool { review != nil && builder != nil }
    public var hasCorrections: Bool { review != nil && !corrections.isEmpty }
    public var pastedText: String { manifest.pastedText }

    // MARK: Rows

    private var storedHeader: PastedLabelManifest.Candidate.Header? {
        manifest.candidate.headers.first { $0.headerID == manifest.storedHeaderID }
    }

    private var storedColumn: [PastedLabelManifest.Candidate.Cell] {
        manifest.candidate.cells.filter { $0.headerID == manifest.storedHeaderID }
    }

    public var sourceLine: String {
        PastedLabelText.sourceLine(basis: storedHeader?.basis ?? "", format: manifest.labelFormat, origin: basisOrigin)
    }

    // MARK: The basis choice (reader v3 section 8.4)

    /// Printed, or chosen by the user (8.4.11): from the review on Confirm, from the stored
    /// manifest otherwise; the same derivation either way.
    public var basisOrigin: PastedLabelBasisOrigin { review?.basisOrigin ?? manifest.basisOrigin }

    /// "per 100 g · Chosen by you", through the one basis formatter.
    public var basisLine: String { PastedLabelText.basisLine(basis: storedHeader?.basis ?? "", origin: basisOrigin) }

    /// Decision 24: the energy line's note when it differed from the choice; never a block.
    public var basisHintNote: String? { PastedLabelText.basisHintNote(basisOrigin) }

    /// Change is offered on a new reading whose bases the user chose.
    public var canChangeBasis: Bool { isEditable && review?.basisChoice != nil && changeBasis != nil }

    /// Opens the basis sheet from Confirm (set by the label text screen's model).
    public var changeBasis: (() -> Void)?

    /// The arrangement the user chose, labelled "Current choice" on the Change sheet.
    public var currentArrangement: PastedLabelBasisOptions.Arrangement? { review?.basisChoice?.arrangement }

    public var flags: [LabelReading.Flag] { manifest.flagsShown.map { LabelReading.Flag(code: $0.code, concerns: $0.concerns) } }

    /// G5: no per 100 g or ml column was read; shown above the values.
    public var basisFlag: String? {
        flags.first { $0.code == PastedLabelCodes.requiredBasisMissing }.map { PastedLabelText.flagMessage($0, headers: manifest.candidate.headers) }
    }

    /// The stored label nutrients, in the reader's fixed order.
    public nonisolated static let rowOrder = ["energy_kcal", "fat", "saturates", "carbohydrate", "sugars", "fibre", "protein", "sodium"]

    public var rows: [Row] {
        Self.rowOrder.compactMap { nutrient -> Row? in
            guard let key = PastedLabelSource.ledgerKeys[nutrient], let value = nutrients.entries.first(where: { $0.key == key })?.value else { return nil }
            return row(nutrient: nutrient, key: key, value: value)
        }
    }

    private func row(nutrient: String, key: NutrientKey, value: NutrientValue) -> Row {
        let origin = NutrientValueOrigin.project(value, key: key, manifest: manifest)
        let title = FoodNutritionReviewPresentation.label(key)
        let amount = NutrientOriginText.amount(value, origin: origin)
        let conversion = manifest.conversions.first { $0.nutrient == nutrient }
        let printed = storedColumn.filter { $0.nutrient == nutrient }
        let correction = corrections.first { $0.nutrient == nutrient }
        var originText = NutrientOriginText.tag(origin)
        if case .calculated = origin, let conversion { originText = NutrientOriginText.calculatedSource(conversion) }
        var source: String?
        switch origin {
        case .printed:
            source = printed.first.map { "Printed: \($0.printedLabel) · \($0.printedText)" }
        case .calculated:
            source = conversion.flatMap { c in storedColumn.first { $0.rowID == c.sourceRowID } }.map { "Printed: \($0.printedLabel) · \($0.printedText)" }
        case .correctedByYou:
            source = correction?.recognised.map { recognised in
                let label = storedColumn.first { $0.rowID == correction?.rowID }?.printedLabel
                return "Read as: " + [label, recognised.printedText].compactMap { $0 }.joined(separator: " · ")
            }
            if let conversion { source = (source.map { $0 + ". " } ?? "") + NutrientOriginText.calculatedSource(conversion) }
        case .enteredByYou:
            source = "Not read from the label"
        case .unknown:
            source = printed.first.map { "Printed: \($0.printedLabel) · \($0.printedText) (not usable as it stands)" }
        }
        let flag = flags.first { $0.nutrient == nutrient && ($0.headerID == nil || $0.headerID == manifest.storedHeaderID) }
            .map { PastedLabelText.flagMessage($0, headers: manifest.candidate.headers) }
        var actions: [Row.Action] = []
        if isEditable {
            switch origin {
            case .printed, .calculated: actions = [.correct]
            case .correctedByYou, .enteredByYou: actions = [.correct, .remove]
            case .unknown(.notStated), .unknown(.notRead): actions = printed.isEmpty ? [.add] : []
            }
        }
        let spoken = [title, amount, originText, source, flag].compactMap { $0 }.joined(separator: ", ")
        return Row(id: nutrient, key: key, title: title, value: amount, origin: origin, originText: originText, source: source,
                   flag: flag, actions: actions, unit: key.canonicalUnit.rawValue, accessibilityLabel: spoken)
    }

    /// Flags for rows the app cannot store yet (trans fat, #270), and cells of the other column.
    public var otherFlags: [String] {
        flags.filter { flag in
            guard let nutrient = flag.nutrient else { return false }
            let otherColumn = flag.headerID != nil && flag.headerID != manifest.storedHeaderID
            return otherColumn || PastedLabelSource.ledgerKeys[nutrient] == nil
        }.map { flag in
            if let header = flag.headerID, header != manifest.storedHeaderID {
                let column = manifest.candidate.headers.first { $0.headerID == header }.map { PastedLabelText.basisLabel($0.basis) } ?? "another column"
                return "Not read: \(PastedLabelText.nutrientName(flag.nutrient ?? "")), \(column). The other column is evidence only."
            }
            return PastedLabelText.flagMessage(flag, headers: manifest.candidate.headers)
        }
    }

    /// The serving size edit's units, the default first: the user's earlier value's unit, else
    /// the printed serving size's, else the stored basis's (ml for per 100 ml), else grams.
    public var servingSizeUnits: [String] {
        let entered = corrections.first { $0.nutrient == PastedLabelManifest.Correction.servingSize }?.corrected.unit
        let printed = manifest.candidate.servingSize?.canonicalUnit.map { $0 == "mL" ? "ml" : $0 }
        let basis = storedHeader?.basis == "per_100ml" ? "ml" : "g"
        let first = [entered, printed].compactMap { $0 }.first { ["g", "ml"].contains($0) } ?? basis
        return [first] + ["g", "ml"].filter { $0 != first }
    }

    /// A printed serving size on a per 100 g or ml column that the manifest's per-100 method
    /// (`pasted-label-serving-v2` or `-v3`, by parser version) refuses as approximate (or whose
    /// quantity it cannot bind). A per-serving column (v1) is not affected.
    func servingSizeExactness(_ size: PastedLabelManifest.Candidate.ServingSize) -> PastedLabelServingPolicy.Exactness {
        guard ["per_100g", "per_100ml"].contains(storedHeader?.basis ?? ""), size.decimalText != nil else { return .exact }
        return PastedLabelServingPolicy.exactness(size, parserVersion: manifest.parserVersion)
    }

    /// The serving-size line's printed text names a servings-per-pack phrase on the same line, so
    /// a pack count that was not read separately is "Not read", not "Not stated".
    static let packPhrases = ["本包裝含", "servings per pack", "servings per container", "per container"]

    public var servingLines: [Line] {
        let size = manifest.candidate.servingSize
        let sizeCorrection = corrections.first { $0.nutrient == PastedLabelManifest.Correction.servingSize }
        let sizeFlag = flags.first { $0.code == PastedLabelCodes.requiredServingDeclarationMissing && $0.concerns == PastedLabelManifest.Correction.servingSize }
        let sizeValue: String
        if let sizeCorrection {
            let entered = "\(sizeCorrection.corrected.decimalText) \(PastedLabelText.unitLabel(sizeCorrection.corrected.unit))"
            sizeValue = sizeCorrection.kind == .corrected
                ? "\(entered) · \(NutrientOriginText.tag(.correctedByYou)) (read as: \(size?.printedText ?? ""))"
                : "\(entered) · \(NutrientOriginText.tag(.enteredByYou))"
        } else if let size, let decimal = size.decimalText, let unit = size.canonicalUnit {
            let shownUnit = PastedLabelText.unitLabel(unit)
            let amount: String
            switch servingSizeExactness(size) {
            case .approximate: amount = "about \(decimal) \(shownUnit)"
            // Only the serving size's own range is shown as a range; a range elsewhere on the line
            // ("2-3 biscuits (30g)", "1 bar - 30g") shows the recorded quantity, with the range note.
            case let .range(own?): amount = "\(own.low)–\(own.high) \(shownUnit)"
            case .range(nil), .exact, .unmatched: amount = "\(decimal) \(shownUnit)"
            }
            sizeValue = "\(amount) · \(NutrientOriginText.tag(.printed)) (printed: \(size.printedText))"
        } else if let size {
            sizeValue = "Printed: \(size.printedText)"
        } else {
            sizeValue = PastedLabelText.notStated
        }
        var sizeActions: [Row.Action] = []
        if isEditable && storedHeader != nil {
            sizeActions = sizeCorrection != nil ? [.correct, .remove] : (size?.decimalText != nil ? [.correct] : [.add])
        }
        let pack = manifest.candidate.servingsPerPack
        let packEntry = corrections.first { $0.nutrient == PastedLabelManifest.Correction.servingsPerPack }
        let packFlag = flags.first { $0.code == PastedLabelCodes.requiredServingDeclarationMissing && $0.concerns == PastedLabelManifest.Correction.servingsPerPack }
        let packValue: String
        if let pack {
            packValue = "\(pack.approximate ? "about " : "")\(pack.decimalText) · \(NutrientOriginText.tag(.printed)) (printed: \(pack.printedText))"
        } else if let packEntry {
            packValue = "\(packEntry.corrected.decimalText) · \(NutrientOriginText.tag(.enteredByYou))"
        } else if let size, Self.packPhrases.contains(where: { size.printedText.lowercased().contains($0) }) {
            packValue = PastedLabelText.notRead
        } else {
            packValue = PastedLabelText.notStated
        }
        let packActions: [Row.Action] = isEditable && pack == nil ? (packEntry == nil ? [.add] : [.correct, .remove]) : []
        return [
            Line(id: PastedLabelManifest.Correction.servingSize, title: "Serving size", value: sizeValue,
                 flag: sizeFlag.map { PastedLabelText.flagMessage($0, headers: manifest.candidate.headers) }
                    ?? (sizeCorrection == nil ? size.flatMap { PastedLabelText.servingSizeNote(servingSizeExactness($0)) } : nil)
                    ?? (joined(PastedLabelManifest.Correction.servingSize) ? PastedLabelText.joinedServingSize : nil),
                 actions: sizeActions, units: servingSizeUnits),
            Line(id: PastedLabelManifest.Correction.servingsPerPack, title: "Servings per pack", value: packValue,
                 flag: packFlag.map { PastedLabelText.flagMessage($0, headers: manifest.candidate.headers) }
                    ?? (pack?.approximate == true ? PastedLabelText.approximatePack
                        : (pack.map { PastedLabelText.isPrintedZero($0.decimalText) } == true ? PastedLabelText.zeroPack
                        : (joined(PastedLabelManifest.Correction.servingsPerPack) ? PastedLabelText.joinedPack : nil))),
                 actions: packActions, units: ["count"])
        ]
    }

    /// Printed rows the ledger does not store: kJ beside kcal, salt beside sodium, % columns,
    /// trans fat and unrecognised rows. Nothing printed vanishes silently (section 3.4).
    public var readButNotUsed: [Evidence] {
        let usedSources = Set(manifest.conversions.map(\.sourceRowID))
        return storedColumn.enumerated().compactMap { index, cell in
            let stored = PastedLabelSource.ledgerKeys[cell.nutrient] != nil && cell.basis != "reference_intake" && cell.canonicalUnit != "%"
            if stored || usedSources.contains(cell.rowID) { return nil }
            return Evidence(id: "\(cell.headerID)-\(index)", title: cell.printedLabel, printedText: cell.printedText, note: PastedLabelText.notUsed)
        }
    }

    /// Printed rows the reader saw but did not read (reader v3 section 3.8), from the stored
    /// candidate's warnings, so a stored entry shows the same list. Nothing printed vanishes.
    public var printedButNotRead: [Evidence] {
        LabelUnreadRow.rows(in: manifest.candidate.warnings).enumerated().map { index, row in
            Evidence(id: "unread-\(index)", title: row.printedLabel, printedText: PastedLabelText.notRead,
                     note: PastedLabelText.unreadReason(row.reason))
        }
    }

    /// The other printed column, read-only evidence; never merged into the stored column.
    public var otherColumns: [(title: String, cells: [Evidence])] {
        manifest.candidate.headers.filter { $0.headerID != manifest.storedHeaderID }.map { header in
            let cells = manifest.candidate.cells.enumerated().filter { $0.element.headerID == header.headerID }.map { index, cell in
                Evidence(id: "\(header.headerID)-\(index)", title: cell.printedLabel, printedText: cell.printedText, note: "Evidence only")
            }
            // A header with empty printed text (a chosen basis) is named by its basis label only.
            let title = header.printedText.isEmpty ? "Other column: \(PastedLabelText.basisLabel(header.basis))"
                : "Other column: \(PastedLabelText.basisLabel(header.basis)) (\(header.printedText))"
            return (title, cells)
        }
    }

    /// Ledger nutrients the label format never prints: unknown, never zero.
    public var otherNutrients: [String] {
        let shown = Set(Self.rowOrder.compactMap { PastedLabelSource.ledgerKeys[$0] })
        return nutrients.entries.filter { !shown.contains($0.key) }.map { FoodNutritionReviewPresentation.label($0.key) }
    }

    /// The warnings shown; the energy line's hint is on the basis line instead (8.4.12).
    public var warnings: [String] {
        manifest.warningsShown.filter { $0 != PastedLabelCodes.basisHintShown }.map(PastedLabelText.warningMessage)
    }

    /// Whether the serving line (`serving_size`) or the pack line (`servings_per_pack`) was read
    /// from two lines of the label and shown as such.
    func joined(_ line: String) -> Bool {
        manifest.warningsShown.contains(PastedLabelCodes.servingLineJoined + ":" + line)
    }

    // MARK: Corrections (sections 2.3 and 3.2)

    public static let invalidNumber = "Enter a number, for example 5.4."
    public static let notCorrectable = "This value cannot be changed here. Edit the label text instead."

    /// The value to prefill in the edit sheet: the current stored or entered value.
    public func editText(_ id: String) -> String {
        if let correction = corrections.first(where: { $0.nutrient == id }) { return correction.corrected.decimalText }
        if id == PastedLabelManifest.Correction.servingSize { return manifest.candidate.servingSize?.decimalText ?? "" }
        if let conversion = manifest.conversions.first(where: { $0.nutrient == id }) { return conversion.storedText }
        return storedColumn.first { $0.nutrient == id && PastedLabelSource.ledgerKeys[$0.nutrient]?.canonicalUnit.rawValue == $0.canonicalUnit }?.decimalText ?? ""
    }

    /// The comparator to prefill: the current value's, `=` when there is none.
    public func editComparator(_ id: String) -> String {
        corrections.first { $0.nutrient == id }?.corrected.comparator
            ?? storedColumn.first { $0.nutrient == id }?.comparator ?? "="
    }

    /// Records the user's value for a row or serving line, replacing any earlier one for it.
    /// Returns the copy to show when the value is not accepted; nil when it was recorded.
    @discardableResult
    public func setValue(_ id: String, text: String, unit: String, comparator: String = "=") -> String? {
        guard let review, let builder else { return Self.notCorrectable }
        let decimal = text.trimmingCharacters(in: .whitespaces)
        do {
            let correction = try builder.correction(id, value: .init(decimalText: decimal, unit: unit, comparator: comparator), in: review)
            var next = corrections.filter { $0.nutrient != id }
            next.append(correction)
            try rebuild(next)
            return nil
        } catch PastedLabelConfirmationError.notCorrectable {
            return Self.notCorrectable
        } catch {
            return Self.invalidNumber
        }
    }

    /// Removes the user's value: the recognised value (or unknown) is shown again.
    public func removeValue(_ id: String) {
        guard corrections.contains(where: { $0.nutrient == id }) else { return }
        try? rebuild(corrections.filter { $0.nutrient != id })
    }

    /// Name, brand or Fortified? changed on the label text screen without a new reading.
    public func updateDetails(_ details: PastedLabelDetails) {
        guard isEditable, details != self.details else { return }
        let previous = self.details
        self.details = details
        do { try rebuild(corrections) } catch { self.details = previous }
    }

    /// Reader v3 8.4.9: Change chose another arrangement. Confirm keeps this model (so its
    /// amount and time stay); the review is replaced and every correction cleared, which the user
    /// agreed to before this is called.
    public func replace(review newReview: PastedLabelReview) throws {
        guard review != nil, builder != nil, locale != nil else { throw PastedLabelSourceError.invalidManifest("stored entry") }
        let previous = review
        review = newReview
        do {
            try rebuild([])
        } catch {
            review = previous
            throw error
        }
    }

    private func rebuild(_ corrections: [PastedLabelManifest.Correction]) throws {
        guard let review, let builder, let locale else { return }
        let input = try builder.confirmation(review, details: details, corrections: corrections, locale: locale)
        guard let candidate = input.candidates.first,
              let manifest = PastedLabelValueOrigins.manifest(input, candidate: candidate) else {
            throw PastedLabelSourceError.invalidManifest("built input")
        }
        self.corrections = corrections
        self.manifest = manifest
        nutrients = candidate.candidate.nutrients
        self.input = input
        onInputChange?(input)
    }

    // MARK: Report a misread (section 9.1)

    /// The report preview's text: the values as read (not the user's corrections), with the
    /// pasted text, serving lines, warnings and versions. Never a name or brand.
    public var reportText: String {
        let report = review.map { PastedLabelMisreadReport(review: $0) } ?? PastedLabelMisreadReport(manifest: manifest)
        return report.text(wording: PastedLabelReportText())
    }
}
