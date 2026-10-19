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

    private let read: (String) -> PastedLabelReadOutcome
    private let makeConfirm: (PastedLabelReview, PastedLabelDetails) throws -> PastedLabelSourceModel
    /// Developer tools lines for this screen's reading, cleared when it closes (test 36).
    private let recordDiagnostics: ([String]) -> Void

    public init(read: @escaping (String) -> PastedLabelReadOutcome,
                makeConfirm: @escaping (PastedLabelReview, PastedLabelDetails) throws -> PastedLabelSourceModel,
                recordDiagnostics: @escaping ([String]) -> Void = { _ in }) {
        self.read = read; self.makeConfirm = makeConfirm; self.recordDiagnostics = recordDiagnostics
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
            do {
                let model = try makeConfirm(review, details)
                phase = .editing
                confirm = model
                recordDiagnostics(["Pasted label read: \(review.reading.format), stored column \(review.storedHeaderID)",
                                   "Flags: " + (review.flags.isEmpty ? "none" : review.flags.map { "\($0.code):\($0.concerns)" }.joined(separator: ", ")),
                                   "Warnings: " + (review.warningCodes.isEmpty ? "none" : review.warningCodes.joined(separator: ", "))])
                return model
            } catch {
                phase = .declined(codes: [PastedLabelCodes.unreadableTable], reading: review.reading, text: snapshot)
                confirm = nil
                recordDiagnostics(["Pasted label declined: \(PastedLabelCodes.unreadableTable) (confirmation could not be built)"])
                return nil
            }
        }
    }

    // MARK: After a decline (section 3.3)

    /// Paste again: clears the text and the decline; the name stays.
    public func clearText() {
        text = ""
        phase = .editing
        confirm = nil
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
        asksToReplaceCorrections = false
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
