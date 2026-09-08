import Foundation

enum DailyNotesPolicy {
    static let maximumNotesPerDay = 20
    static let maximumCharactersPerNote = 2_000
    static let maximumCharactersPerDay = 20_000
}

enum DailyNotesError: Error, Equatable {
    case blankNote
    case noteTooLong
    case tooManyNotes
    case dayTooLong
    case noteNotFound
    case draftRecoveryRequired
    case unfinishedDraftExists
    case noDraft
    case staleRevision
    case corruptStorage
}

struct DailyNoteDayID: Codable, Equatable, Hashable {
    let reportDate: String
    let timeZoneIdentifier: String

    init(reportDate: String, timeZoneIdentifier: String) {
        self.reportDate = reportDate
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(window: DailyExportWindow) {
        reportDate = window.reportDate
        timeZoneIdentifier = window.timeZoneIdentifier
    }
}

struct DailyNote: Codable, Equatable, Identifiable {
    let id: UUID
    let dayID: DailyNoteDayID
    var text: String
    let createdAt: Date
    var updatedAt: Date
}

struct DailyNoteDraft: Codable, Equatable, Identifiable {
    let id: UUID
    var dayID: DailyNoteDayID
    var text: String
    var editingNoteID: UUID?
    let createdAt: Date
    var updatedAt: Date
}

struct VerifiedDailyNotesExport: Codable, Equatable {
    let revision: UInt64
    let payloadSHA256: String
    let verifiedAt: Date
}

struct DailyNoteDay: Codable, Equatable {
    let id: DailyNoteDayID
    var revision: UInt64
    var notes: [DailyNote]
    var verifiedExport: VerifiedDailyNotesExport?
}

struct DailyNotesSnapshot: Equatable {
    let dayID: DailyNoteDayID
    let revision: UInt64
    let notes: [String]
}

struct DailyNotesDocument: Codable, Equatable {
    static let formatVersion = 1

    let version: Int
    var nextRevision: UInt64
    var days: [DailyNoteDay]
    var draft: DailyNoteDraft?

    init(
        nextRevision: UInt64 = 1,
        days: [DailyNoteDay] = [],
        draft: DailyNoteDraft? = nil
    ) {
        version = Self.formatVersion
        self.nextRevision = nextRevision
        self.days = days
        self.draft = draft
    }

    func snapshot(for dayID: DailyNoteDayID) -> DailyNotesSnapshot {
        guard let day = days.first(where: { $0.id == dayID }) else {
            return DailyNotesSnapshot(dayID: dayID, revision: 0, notes: [])
        }
        return DailyNotesSnapshot(
            dayID: dayID,
            revision: day.revision,
            notes: day.notes.map(\.text)
        )
    }

    func savedNotes(for dayID: DailyNoteDayID) -> [DailyNote] {
        days.first(where: { $0.id == dayID })?.notes ?? []
    }

    mutating func beginDraft(
        for dayID: DailyNoteDayID,
        editing noteID: UUID? = nil,
        id: UUID = UUID(),
        now: Date
    ) throws {
        if let draft {
            guard draft.dayID == dayID else {
                throw DailyNotesError.draftRecoveryRequired
            }
            guard noteID == nil || draft.editingNoteID == noteID else {
                throw DailyNotesError.unfinishedDraftExists
            }
            return
        }

        let existing: DailyNote?
        if let noteID {
            existing = savedNotes(for: dayID).first(where: { $0.id == noteID })
            guard existing != nil else { throw DailyNotesError.noteNotFound }
        } else {
            existing = nil
        }
        draft = DailyNoteDraft(
            id: id,
            dayID: dayID,
            text: existing?.text ?? "",
            editingNoteID: existing?.id,
            createdAt: now,
            updatedAt: now
        )
    }

    mutating func updateDraft(text: String, now: Date) throws {
        guard var draft else { throw DailyNotesError.noDraft }
        guard text.count <= DailyNotesPolicy.maximumCharactersPerNote else {
            throw DailyNotesError.noteTooLong
        }
        let existingCharacters = savedNotes(for: draft.dayID)
            .filter { $0.id != draft.editingNoteID }
            .reduce(0) { $0 + $1.text.count }
        guard existingCharacters + text.count <= DailyNotesPolicy.maximumCharactersPerDay else {
            throw DailyNotesError.dayTooLong
        }
        draft.text = text
        draft.updatedAt = now
        self.draft = draft
    }

    @discardableResult
    mutating func saveDraft(now: Date) throws -> DailyNotesSnapshot {
        guard let draft else { throw DailyNotesError.noDraft }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DailyNotesError.blankNote }
        guard text.count <= DailyNotesPolicy.maximumCharactersPerNote else {
            throw DailyNotesError.noteTooLong
        }

        let index = ensureDay(draft.dayID)
        if let noteID = draft.editingNoteID {
            guard let noteIndex = days[index].notes.firstIndex(where: { $0.id == noteID }) else {
                throw DailyNotesError.noteNotFound
            }
            let otherCharacters = days[index].notes.enumerated().reduce(0) { partial, entry in
                partial + (entry.offset == noteIndex ? 0 : entry.element.text.count)
            }
            guard otherCharacters + text.count <= DailyNotesPolicy.maximumCharactersPerDay else {
                throw DailyNotesError.dayTooLong
            }
            days[index].notes[noteIndex].text = text
            days[index].notes[noteIndex].updatedAt = now
        } else {
            guard days[index].notes.count < DailyNotesPolicy.maximumNotesPerDay else {
                throw DailyNotesError.tooManyNotes
            }
            let currentCharacters = days[index].notes.reduce(0) { $0 + $1.text.count }
            guard currentCharacters + text.count <= DailyNotesPolicy.maximumCharactersPerDay else {
                throw DailyNotesError.dayTooLong
            }
            days[index].notes.append(DailyNote(
                id: draft.id,
                dayID: draft.dayID,
                text: text,
                createdAt: draft.createdAt,
                updatedAt: now
            ))
        }
        bumpRevision(at: index)
        self.draft = nil
        return snapshot(for: draft.dayID)
    }

    @discardableResult
    mutating func deleteNote(id: UUID, from dayID: DailyNoteDayID) throws -> DailyNotesSnapshot {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }),
              let noteIndex = days[dayIndex].notes.firstIndex(where: { $0.id == id }) else {
            throw DailyNotesError.noteNotFound
        }
        days[dayIndex].notes.remove(at: noteIndex)
        if draft?.editingNoteID == id {
            draft = nil
        }
        bumpRevision(at: dayIndex)
        return snapshot(for: dayID)
    }

    mutating func discardDraft() throws {
        guard draft != nil else { throw DailyNotesError.noDraft }
        draft = nil
    }

    mutating func copyRecoverableDraft(to dayID: DailyNoteDayID, now: Date) throws {
        guard var draft else { throw DailyNotesError.noDraft }
        guard draft.dayID != dayID else { return }
        draft.dayID = dayID
        draft.editingNoteID = nil
        draft.updatedAt = now
        try validateDraftCapacity(draft)
        self.draft = draft
    }

    mutating func markVerified(
        snapshot: DailyNotesSnapshot,
        payloadSHA256: String,
        verifiedAt: Date
    ) throws {
        guard let index = days.firstIndex(where: { $0.id == snapshot.dayID }) else {
            guard snapshot.revision == 0 && snapshot.notes.isEmpty else {
                throw DailyNotesError.staleRevision
            }
            return
        }
        guard days[index].revision == snapshot.revision,
              days[index].notes.map(\.text) == snapshot.notes else {
            throw DailyNotesError.staleRevision
        }
        days[index].verifiedExport = VerifiedDailyNotesExport(
            revision: snapshot.revision,
            payloadSHA256: payloadSHA256,
            verifiedAt: verifiedAt
        )
    }

    @discardableResult
    mutating func cleanupVerifiedNotes(before currentDayID: DailyNoteDayID) -> [DailyNoteDayID] {
        var cleaned: [DailyNoteDayID] = []
        for index in days.indices where days[index].id.reportDate < currentDayID.reportDate {
            guard let verified = days[index].verifiedExport,
                  verified.revision == days[index].revision else { continue }
            days[index].notes = []
            days[index].verifiedExport = nil
            bumpRevision(at: index)
            cleaned.append(days[index].id)
        }
        days.removeAll { day in
            day.notes.isEmpty && draft?.dayID != day.id
        }
        return cleaned
    }

    private mutating func ensureDay(_ id: DailyNoteDayID) -> Int {
        if let index = days.firstIndex(where: { $0.id == id }) {
            return index
        }
        days.append(DailyNoteDay(id: id, revision: 0, notes: [], verifiedExport: nil))
        return days.count - 1
    }

    private mutating func bumpRevision(at index: Int) {
        days[index].revision = nextRevision
        nextRevision += 1
        days[index].verifiedExport = nil
    }

    private func validateDraftCapacity(_ draft: DailyNoteDraft) throws {
        guard draft.text.count <= DailyNotesPolicy.maximumCharactersPerNote else {
            throw DailyNotesError.noteTooLong
        }
        let notes = savedNotes(for: draft.dayID)
        guard notes.count < DailyNotesPolicy.maximumNotesPerDay else {
            throw DailyNotesError.tooManyNotes
        }
        guard notes.reduce(0, { $0 + $1.text.count }) + draft.text.count
                <= DailyNotesPolicy.maximumCharactersPerDay else {
            throw DailyNotesError.dayTooLong
        }
    }
}
