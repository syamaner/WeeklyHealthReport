import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// The label text screen (`docs/pasted-nutrition-label-v1.md` sections 2.2, 3.1 and 3.3): Name,
/// optional Brand, optional Fortified?, and the pasted text. Read label runs the on-device
/// reader through the application's `PastedLabelReader`; a hard decline keeps the user here with
/// the text and name kept and a plain reason above the field. Nothing is saved here, and the
/// text lives only in this model: never in scene or app storage, never read from the pasteboard
/// by the app, and cleared when the screen closes.
@MainActor
public final class PastedLabelTextViewModel: ObservableObject {
    public enum Phase: Equatable {
        case editing
        /// A hard decline with its reason codes (Developer tools only) and the reading, if any.
        case declined(codes: [String], reading: LabelReading?, text: String)
    }

    @Published public var name = ""
    @Published public var brand = ""
    @Published public var fortification: PastedLabelIdentity.FortificationAnswer = .unanswered
    @Published public var text = ""
    @Published public private(set) var phase: Phase = .editing
    /// Confirm for the current reading, kept while the user edits the text so Cancel on the
    /// "Read again" question keeps every correction.
    @Published public private(set) var confirm: PastedLabelSourceModel?
    /// The "Reading the text again replaces your corrections." question is showing.
    @Published public var asksToReplaceCorrections = false

    /// The basis sheet (reader v3 sections 3.3 and 8.4.9): after Read label for an unheaded
    /// table, or from Change on Confirm. Nil when it is not showing.
    public struct BasisSheet: Identifiable, Equatable {
        public let id = UUID()
        public let request: PastedLabelBasisChoiceRequest
        /// Opened from Change on Confirm: nothing is preselected and the current choice is
        /// labelled; dismissing keeps it.
        public let fromChange: Bool
        public let current: PastedLabelBasisOptions.Arrangement?
    }

    /// One option as the sheet renders it, in the application's order, with no logic of its own.
    public struct BasisOption: Identifiable, Equatable {
        public var id: String { arrangement.identifier }
        public let arrangement: PastedLabelBasisOptions.Arrangement
        public let title: String
        public let warnings: [String]
        public let isCurrent: Bool
    }

    @Published public var basisSheet: BasisSheet?
    /// "Changing what the values are for replaces your corrections." is showing (from Change).
    @Published public var asksToReplaceCorrectionsOnBasisChange = false
    /// Change chose an option whose source could not be built: Confirm keeps the earlier choice.
    /// Set once the sheet has gone (`basisSheetDidDisappear`), so the sheet's own dismissal never
    /// drops the alert.
    @Published public var basisChangeFailed = false
    /// The first choice could not be applied: nothing was written and the text is kept. Set once
    /// the sheet has gone, as above.
    @Published public var basisChoiceFailed = false
    /// A failed choice waiting for the sheet to finish dismissing (carried from the final review
    /// of #284): `apply` clears the sheet first, and an alert raised on the presenting screen
    /// while its sheet is still dismissing can be dropped.
    private enum PendingFailure { case choice, change }
    private var pendingFailure: PendingFailure?
    private var pendingArrangement: PastedLabelBasisOptions.Arrangement?
    /// The request the current Confirm's choice was made on, bound to its text (8.4.9).
    private var confirmRequest: PastedLabelBasisChoiceRequest?

    private let read: (String) -> PastedLabelReadOutcome
    private let makeConfirm: (PastedLabelReview, PastedLabelDetails) throws -> PastedLabelSourceModel
    private let choose: ((PastedLabelBasisOptions.Arrangement, PastedLabelBasisChoiceRequest) throws -> PastedLabelReview)?
    /// Developer tools lines for this screen's reading, cleared when it closes (test 36).
    private let recordDiagnostics: ([String]) -> Void

    public init(read: @escaping (String) -> PastedLabelReadOutcome,
                makeConfirm: @escaping (PastedLabelReview, PastedLabelDetails) throws -> PastedLabelSourceModel,
                choose: ((PastedLabelBasisOptions.Arrangement, PastedLabelBasisChoiceRequest) throws -> PastedLabelReview)? = nil,
                recordDiagnostics: @escaping ([String]) -> Void = { _ in }) {
        self.read = read; self.makeConfirm = makeConfirm; self.choose = choose; self.recordDiagnostics = recordDiagnostics
    }

    public var details: PastedLabelDetails {
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return PastedLabelDetails(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  brand: trimmedBrand.isEmpty ? nil : trimmedBrand, fortification: fortification)
    }

    // MARK: Read label (section 2.2)

    private var nameMissing: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var textMissing: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// The length limit in Unicode scalars (section 6.2): 8,000 is accepted, 8,001 is not.
    public var isTooLong: Bool { text.unicodeScalars.count > PastedLabelManifest.maximumTextScalars }

    /// Disabled while Name or Label text is empty, or the text is over the length limit.
    public var canRead: Bool { readBlockedReason == nil }

    public var readBlockedReason: String? {
        PastedLabelText.readBlockedReason(nameMissing: nameMissing, textMissing: textMissing, tooLong: isTooLong)
    }

    /// The decline reasons shown above the field, or empty.
    public var declineMessages: [String] {
        if case let .declined(codes, _, _) = phase { return PastedLabelText.declineMessages(codes) }
        return []
    }

    /// Back to Confirm without reading again: only while the text is the text that was read.
    public var canReturnToConfirm: Bool { confirm != nil && confirm?.pastedText == text }

    /// Read label. With corrections on the current Confirm it first asks (section 2.3); otherwise
    /// it reads. Returns the Confirm model to open, or nil for a decline or the question.
    @discardableResult
    public func readLabel() -> PastedLabelSourceModel? {
        guard canRead else { return nil }
        if confirm?.hasCorrections == true {
            asksToReplaceCorrections = true
            return nil
        }
        return performRead()
    }

    /// "Read again" on the question: the corrections are cleared and the text read again.
    @discardableResult
    public func confirmReadAgain() -> PastedLabelSourceModel? {
        asksToReplaceCorrections = false
        guard canRead else { return nil }
        confirm = nil
        confirmRequest = nil
        return performRead()
    }

    /// "Cancel" on the question: every correction is kept.
    public func cancelReadAgain() { asksToReplaceCorrections = false }

    /// "Back to Confirm": the kept Confirm, with any new name, brand or Fortified? answer.
    public func returnToConfirm() -> PastedLabelSourceModel? {
        guard canReturnToConfirm, let confirm else { return nil }
        confirm.updateDetails(details)
        return confirm
    }

    private func performRead() -> PastedLabelSourceModel? {
        let snapshot = text
        switch read(snapshot) {
        case let .declined(codes, reading):
            phase = .declined(codes: codes, reading: reading, text: snapshot)
            confirm = nil
            recordDiagnostics(["Pasted label declined: " + codes.joined(separator: ", ")]
                + (reading.map { ["Format: \($0.format)"] } ?? []))
            return nil
        case let .usable(review):
            confirmRequest = nil
            return openConfirm(review, text: snapshot)
        case let .needsBasisChoice(request):
            // 8.4.9: a new reading clears any earlier choice and shows the sheet again.
            phase = .editing
            confirm = nil
            confirmRequest = nil
            basisSheet = BasisSheet(request: request, fromChange: false, current: nil)
            recordDiagnostics(["Pasted label needs a basis choice: offered " + request.offered.joined(separator: " | ")])
            return nil
        }
    }

    private func openConfirm(_ review: PastedLabelReview, text snapshot: String) -> PastedLabelSourceModel? {
        do {
            let model = try makeConfirm(review, details)
            phase = .editing
            confirm = model
            if review.basisChoice != nil { model.changeBasis = { [weak self] in self?.changeBasis() } }
            let basis = review.reading.candidate.headers.first { $0.headerID == review.storedHeaderID }?.basis ?? ""
            recordDiagnostics(["Pasted label read: \(review.reading.format), stored column \(review.storedHeaderID)",
                               "Basis: " + PastedLabelText.basisLine(basis: basis, origin: review.basisOrigin)
                                + (PastedLabelText.basisHintNote(review.basisOrigin).map { " " + $0 } ?? ""),
                               "Flags: " + (review.flags.isEmpty ? "none" : review.flags.map { "\($0.code):\($0.concerns)" }.joined(separator: ", ")),
                               "Warnings: " + (review.warningCodes.isEmpty ? "none" : review.warningCodes.joined(separator: ", "))])
            return model
        } catch {
            phase = .declined(codes: [PastedLabelCodes.unreadableTable], reading: review.reading, text: snapshot)
            confirm = nil
            confirmRequest = nil
            recordDiagnostics(["Pasted label declined: \(PastedLabelCodes.unreadableTable) (confirmation could not be built)"])
            return nil
        }
    }

    // MARK: The basis sheet (reader v3 sections 3.3 and 8.4.9)

    /// The sheet's options in order, each with its plausibility warnings; on the Change sheet
    /// the current choice is labelled, never selected.
    public var basisOptions: [BasisOption] {
        guard let sheet = basisSheet else { return [] }
        return sheet.request.options.map { option in
            BasisOption(arrangement: option.arrangement,
                        title: PastedLabelText.basisOptionTitle(option.arrangement, servingSize: sheet.request.unheaded.servingSize),
                        warnings: option.plausibilityWarnings.map(PastedLabelText.warningMessage),
                        isCurrent: sheet.fromChange && sheet.current == option.arrangement)
        }
    }

    /// The energy line's hint on the sheet: shown, never preselected, never reordering.
    public var basisHint: String? { basisSheet?.request.unheaded.energyLineHint.map { PastedLabelText.energyLineSays($0.printedText) } }

    public var perServingUnavailable: Bool { basisSheet?.request.perServingUnavailable ?? false }

    /// The user chose an option. Returns the Confirm to open, or nil while the corrections
    /// question is showing (a different arrangement from Change with corrections) or when
    /// nothing changes (the current arrangement again).
    @discardableResult
    public func chooseBasis(_ arrangement: PastedLabelBasisOptions.Arrangement) -> PastedLabelSourceModel? {
        guard let sheet = basisSheet else { return nil }
        if sheet.fromChange {
            if arrangement == sheet.current {
                basisSheet = nil
                return nil
            }
            if confirm?.hasCorrections == true {
                pendingArrangement = arrangement
                asksToReplaceCorrectionsOnBasisChange = true
                return nil
            }
        }
        return apply(arrangement, sheet: sheet)
    }

    /// "Change and replace" on the question: the corrections go with the old choice.
    @discardableResult
    public func confirmBasisChange() -> PastedLabelSourceModel? {
        asksToReplaceCorrectionsOnBasisChange = false
        guard let arrangement = pendingArrangement, let sheet = basisSheet else { return nil }
        pendingArrangement = nil
        return apply(arrangement, sheet: sheet)
    }

    /// Cancel on the question: the choice and every correction are kept.
    public func cancelBasisChange() {
        asksToReplaceCorrectionsOnBasisChange = false
        pendingArrangement = nil
    }

    private func apply(_ arrangement: PastedLabelBasisOptions.Arrangement, sheet: BasisSheet) -> PastedLabelSourceModel? {
        basisSheet = nil
        let request = sheet.request
        guard let choose, let review = try? choose(arrangement, request) else {
            // Never silent (final review of #284): from Change the earlier choice is kept and
            // said so; after Read label nothing was written and the text stays.
            pendingFailure = sheet.fromChange ? .change : .choice
            return nil
        }
        // From Change, Confirm keeps its model (amount and time stay) with the new review. If the
        // new source cannot be built, Confirm and its earlier choice stay and the user is told;
        // a new Confirm is never opened in its place (review of #284).
        if sheet.fromChange, let confirm {
            do {
                try confirm.replace(review: review)
            } catch {
                pendingFailure = .change
                return nil
            }
            recordDiagnostics(["Pasted label basis changed: " + arrangement.identifier])
            return confirm
        }
        let model = openConfirm(review, text: request.pastedText)
        confirmRequest = model == nil ? nil : request
        return model
    }

    /// "I'm not sure" (8.4.9). After Read label: nothing is written and the text screen stays
    /// with the text kept. From Change: the choice is cleared, Confirm is dropped and the text
    /// is kept. Returns true when Confirm must close.
    @discardableResult
    public func basisNotSure() -> Bool {
        let fromChange = basisSheet?.fromChange == true
        basisSheet = nil
        pendingArrangement = nil
        guard fromChange else { return false }
        confirm = nil
        confirmRequest = nil
        return true
    }

    /// The sheet was swiped away: after Read label it is "I'm not sure" (nothing written, text
    /// kept); from Change the current choice stays and Confirm stays.
    public func basisSheetDismissed() {
        basisSheet = nil
        pendingArrangement = nil
        asksToReplaceCorrectionsOnBasisChange = false
    }

    /// The sheet has finished dismissing (its `onDismiss`, however it closed): a failed choice is
    /// now said, on the screen that presented the sheet.
    public func basisSheetDidDisappear() {
        guard basisSheet == nil, let failure = pendingFailure else { return }
        pendingFailure = nil
        switch failure {
        case .choice: basisChoiceFailed = true
        case .change: basisChangeFailed = true
        }
    }

    /// Change on Confirm's basis line: the sheet with nothing preselected and the current choice
    /// labelled. Only for the Confirm of the unchanged text it was chosen on.
    public func changeBasis() {
        guard let request = confirmRequest, let confirm, confirm.pastedText == request.pastedText else { return }
        basisSheet = BasisSheet(request: request, fromChange: true, current: confirm.currentArrangement)
    }

    // MARK: After a decline (section 3.3)

    /// Paste again: clears the text and the decline; the name stays.
    public func clearText() {
        text = ""
        phase = .editing
        confirm = nil
        confirmRequest = nil
        recordDiagnostics([])
    }

    /// The misread report for a decline (section 9.1): the pasted text, the reasons and versions.
    public var declineReportText: String? {
        guard case let .declined(codes, reading, read) = phase else { return nil }
        return PastedLabelMisreadReport(pastedText: read, reading: reading, declineCodes: codes, warningCodes: [])  // a decline shows no warnings (section 9.1)
            .text(wording: PastedLabelReportText())
    }

    /// The user left for Search or Barcode instead: this screen's reading is no longer what
    /// the user is acting on, so its Developer tools lines are cleared (the text stays, in case
    /// they come back). Whatever that route logs, no pasted-label line outlives it.
    public func leaveForAnotherRoute() {
        asksToReplaceCorrections = false
        recordDiagnostics([])
    }

    /// Confirm left the screen. `stillPushed` means the flow ended underneath it (Add food swiped
    /// away, or a finish that replaced the path), so nothing is kept; otherwise it was Back or
    /// Edit label text to this screen, which keeps the text, name and reading.
    public func confirmDisappeared(stillPushed: Bool) {
        if stillPushed { dismissed() }
    }

    /// This screen left view. `covered` when Confirm, Search or Barcode is pushed over it (still
    /// open); otherwise it closed and nothing is kept.
    public func labelScreenDisappeared(covered: Bool) {
        if !covered { dismissed() }
    }

    /// The screen closed ("Leave without saving", back, or after Log): nothing is kept.
    public func dismissed() {
        text = ""; name = ""; brand = ""; fortification = .unanswered
        phase = .editing
        confirm = nil
        confirmRequest = nil
        basisSheet = nil
        pendingArrangement = nil
        pendingFailure = nil
        asksToReplaceCorrections = false
        asksToReplaceCorrectionsOnBasisChange = false
        recordDiagnostics([])
    }
}

/// The misread report preview (section 9.1): the user edits or trims the text, then Share opens
/// the system share sheet with that text only, or Cancel closes it. Nothing is written, queued
/// or recorded, and there is no destination of the app's own.
@MainActor
public final class PastedLabelMisreadPreviewModel: ObservableObject, Identifiable {
    public nonisolated let id = UUID()
    @Published public var text: String

    public init(report: String) { text = report }

    /// The only thing Share passes to the share sheet: the previewed, possibly edited, text.
    public var shareItem: String { text }
}
