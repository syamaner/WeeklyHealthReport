import CryptoKit
import Combine
import Foundation

@MainActor
final class DailyNotesController: ObservableObject {
    @Published private(set) var document = DailyNotesDocument()
    @Published private(set) var currentDayID: DailyNoteDayID
    @Published private(set) var errorMessage: String?
    @Published private(set) var storageAvailable = true

    var onSavedNotesMutation: ((DailyNotesSnapshot) -> Void)?

    var notes: [DailyNote] { document.savedNotes(for: currentDayID) }
    var currentDraft: DailyNoteDraft? {
        guard document.draft?.dayID == currentDayID else { return nil }
        return document.draft
    }
    var recoverableDraft: DailyNoteDraft? {
        guard document.draft?.dayID != currentDayID else { return nil }
        return document.draft
    }
    var noteCountLabel: String {
        switch notes.count {
        case 0: "No notes"
        case 1: "1 note"
        default: "\(notes.count) notes"
        }
    }

    private let store: any DailyNotesPersisting
    private var calendar: Calendar
    private let now: () -> Date
    private var draftSaveTask: Task<Void, Never>?

    init(
        store: any DailyNotesPersisting,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.calendar = calendar
        self.now = now
        currentDayID = Self.dayID(at: now(), calendar: calendar)
        loadAndCleanUp()
    }

    deinit {
        draftSaveTask?.cancel()
    }

    func activate() {
        flushDraft()
        let previousDayID = currentDayID
        currentDayID = Self.dayID(at: now(), calendar: calendar)
        cleanUpVerifiedPriorDays()
        if previousDayID != currentDayID {
            onSavedNotesMutation?(document.snapshot(for: currentDayID))
        }
    }

    @discardableResult
    func beginNewDraft() -> Bool {
        mutateAndPersistDraft { document in
            try document.beginDraft(for: currentDayID, now: now())
        }
    }

    @discardableResult
    func beginOrResumeDraft() -> Bool {
        guard storageAvailable else { return false }
        if currentDraft != nil {
            errorMessage = nil
            return true
        }
        return beginNewDraft()
    }

    @discardableResult
    func beginEditing(noteID: UUID) -> Bool {
        mutateAndPersistDraft { document in
            try document.beginDraft(for: currentDayID, editing: noteID, now: now())
        }
    }

    @discardableResult
    func updateDraftText(_ text: String) -> Bool {
        guard storageAvailable else { return false }
        var candidate = document
        do {
            try candidate.updateDraft(text: text, now: now())
            document = candidate
            errorMessage = nil
            scheduleDraftSave()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    @discardableResult
    func appendSpeechTranscript(_ transcript: String) -> Bool {
        guard let draft = currentDraft else {
            errorMessage = Self.message(for: DailyNotesError.noDraft)
            return false
        }
        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTranscript.isEmpty else { return true }

        let separator = draft.text.isEmpty || draft.text.last?.isWhitespace == true ? "" : " "
        return updateDraftText(draft.text + separator + finalTranscript)
    }

    @discardableResult
    func saveDraft() -> Bool {
        mutateSavedNotes { document in
            try document.saveDraft(now: now())
        }
    }

    @discardableResult
    func deleteNote(id: UUID) -> Bool {
        mutateSavedNotes { document in
            try document.deleteNote(id: id, from: currentDayID)
        }
    }

    @discardableResult
    func discardDraft() -> Bool {
        mutateAndPersistDraft { document in
            try document.discardDraft()
        }
    }

    @discardableResult
    func copyRecoverableDraftToToday() -> Bool {
        mutateAndPersistDraft { document in
            try document.copyRecoverableDraft(to: currentDayID, now: now())
        }
    }

    func flushDraft() {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        guard storageAvailable, document.draft != nil else { return }
        do {
            try store.save(document)
            errorMessage = nil
        } catch {
            errorMessage = "Draft could not be saved. The previous saved notes file was preserved."
        }
    }

    func finishEditorDismissal() {
        guard let draft = currentDraft,
              let editingNoteID = draft.editingNoteID,
              notes.first(where: { $0.id == editingNoteID })?.text == draft.text else {
            flushDraft()
            return
        }
        _ = discardDraft()
    }

    @discardableResult
    func markVerified(snapshot: DailyNotesSnapshot, payload: Data) -> Bool {
        guard storageAvailable else { return false }
        var candidate = document
        do {
            try candidate.markVerified(
                snapshot: snapshot,
                payloadSHA256: Self.sha256(payload),
                verifiedAt: now()
            )
            try store.save(candidate)
            document = candidate
            errorMessage = nil
            return true
        } catch DailyNotesError.staleRevision {
            errorMessage = "Drive verified an earlier note revision. Current notes were kept for another preview."
            return false
        } catch {
            errorMessage = "Drive verified the export, but its note-cleanup marker could not be saved. Notes were kept."
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func mutateAndPersistDraft(
        _ mutation: (inout DailyNotesDocument) throws -> Void
    ) -> Bool {
        guard storageAvailable else { return false }
        draftSaveTask?.cancel()
        var candidate = document
        do {
            try mutation(&candidate)
            try store.save(candidate)
            document = candidate
            errorMessage = nil
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private func mutateSavedNotes(
        _ mutation: (inout DailyNotesDocument) throws -> DailyNotesSnapshot
    ) -> Bool {
        guard storageAvailable else { return false }
        draftSaveTask?.cancel()
        var candidate = document
        do {
            let snapshot = try mutation(&candidate)
            try store.save(candidate)
            document = candidate
            errorMessage = nil
            onSavedNotesMutation?(snapshot)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flushDraft()
        }
    }

    private func loadAndCleanUp() {
        do {
            let loaded = try store.load() ?? DailyNotesDocument()
            guard loaded.version == DailyNotesDocument.formatVersion else {
                throw DailyNotesError.corruptStorage
            }
            document = loaded
            cleanUpVerifiedPriorDays()
        } catch {
            storageAvailable = false
            errorMessage = "Saved notes could not be opened. The file was left unchanged."
        }
    }

    private func cleanUpVerifiedPriorDays() {
        guard storageAvailable else { return }
        var candidate = document
        let cleaned = candidate.cleanupVerifiedNotes(before: currentDayID)
        guard !cleaned.isEmpty else { return }
        do {
            try store.save(candidate)
            document = candidate
        } catch {
            errorMessage = "Verified prior-day notes could not be cleaned up and were kept."
        }
    }

    private static func dayID(at date: Date, calendar: Calendar) -> DailyNoteDayID {
        let window = try? DailyExportWindow.capture(at: date, calendar: calendar)
        return window.map(DailyNoteDayID.init) ?? DailyNoteDayID(
            reportDate: "unavailable",
            timeZoneIdentifier: calendar.timeZone.identifier
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func message(for error: Error) -> String {
        switch error as? DailyNotesError {
        case .blankNote: "Enter some text before saving."
        case .noteTooLong: "A note can contain at most 2,000 characters."
        case .tooManyNotes: "Today already has the maximum of 20 saved notes."
        case .dayTooLong: "Today’s saved notes can contain at most 20,000 characters in total."
        case .noteNotFound: "That saved note is no longer available."
        case .draftRecoveryRequired: "Resolve the draft from another reporting date first."
        case .unfinishedDraftExists: "Save or discard the unfinished draft before editing another note."
        case .noDraft: "There is no unfinished draft."
        case .staleRevision: "The saved notes changed. Refresh and review them again."
        case .corruptStorage: "Saved notes could not be opened. The file was left unchanged."
        case nil: "Notes could not be saved. The previous saved notes file was preserved."
        }
    }
}
