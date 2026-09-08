import XCTest
@testable import WeeklyHealthReport

final class DailyNotesTests: XCTestCase {
    func testSaveTrimsEdgesPreservesUnicodeAndLineBreaksAndAllowsDuplicates() throws {
        var document = DailyNotesDocument()
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        try document.beginDraft(for: londonDay, id: firstID, now: time(8))
        try document.updateDraft(text: "  Felt energetic 🌤️\nEasy run.  ", now: time(9))
        let first = try document.saveDraft(now: time(10))

        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        try document.beginDraft(for: londonDay, id: secondID, now: time(11))
        try document.updateDraft(text: "Felt energetic 🌤️\nEasy run.", now: time(12))
        let second = try document.saveDraft(now: time(13))

        XCTAssertEqual(first.notes, ["Felt energetic 🌤️\nEasy run."])
        XCTAssertEqual(second.notes, [
            "Felt energetic 🌤️\nEasy run.",
            "Felt energetic 🌤️\nEasy run."
        ])
        XCTAssertEqual(document.savedNotes(for: londonDay).map(\.id), [firstID, secondID])
    }

    func testEditingPreservesPositionAndDeletionChangesRevision() throws {
        var document = try documentWithNotes(["First", "Second"])
        let firstID = document.savedNotes(for: londonDay)[0].id
        let originalRevision = document.snapshot(for: londonDay).revision

        try document.beginDraft(for: londonDay, editing: firstID, now: time(12))
        try document.updateDraft(text: "Edited", now: time(13))
        let edited = try document.saveDraft(now: time(14))
        XCTAssertEqual(edited.notes, ["Edited", "Second"])
        XCTAssertGreaterThan(edited.revision, originalRevision)

        let deleted = try document.deleteNote(id: firstID, from: londonDay)
        XCTAssertEqual(deleted.notes, ["Second"])
        XCTAssertGreaterThan(deleted.revision, edited.revision)
    }

    func testBlankDraftIsNotSaved() throws {
        var document = DailyNotesDocument()
        try document.beginDraft(for: londonDay, now: time(8))
        try document.updateDraft(text: " \n ", now: time(9))
        XCTAssertThrowsError(try document.saveDraft(now: time(10))) {
            XCTAssertEqual($0 as? DailyNotesError, .blankNote)
        }
        XCTAssertTrue(document.savedNotes(for: londonDay).isEmpty)
        XCTAssertNotNil(document.draft)
    }

    func testPerNoteLimitRejectsInputWithoutTruncatingDraft() throws {
        var document = DailyNotesDocument()
        try document.beginDraft(for: londonDay, now: time(8))
        let accepted = String(repeating: "a", count: 2_000)
        try document.updateDraft(text: accepted, now: time(9))
        XCTAssertThrowsError(
            try document.updateDraft(text: accepted + "b", now: time(10))
        ) {
            XCTAssertEqual($0 as? DailyNotesError, .noteTooLong)
        }
        XCTAssertEqual(document.draft?.text, accepted)
    }

    func testDailyCharacterAndNoteCountLimitsAreIndependent() throws {
        var characters = DailyNotesDocument()
        for index in 0..<10 {
            try add(String(repeating: Character(String(index)), count: 2_000), to: &characters)
        }
        try characters.beginDraft(for: londonDay, now: time(20))
        XCTAssertThrowsError(try characters.updateDraft(text: "x", now: time(21))) {
            XCTAssertEqual($0 as? DailyNotesError, .dayTooLong)
        }

        var count = DailyNotesDocument()
        for index in 0..<20 { try add("Note \(index)", to: &count) }
        try count.beginDraft(for: londonDay, now: time(20))
        try count.updateDraft(text: "One more", now: time(21))
        XCTAssertThrowsError(try count.saveDraft(now: time(22))) {
            XCTAssertEqual($0 as? DailyNotesError, .tooManyNotes)
        }
    }

    func testDraftMustBeExplicitlyCopiedAcrossDateAndLosesEditIdentity() throws {
        var document = try documentWithNotes(["Original"])
        let noteID = document.savedNotes(for: londonDay)[0].id
        try document.beginDraft(for: londonDay, editing: noteID, now: time(12))
        try document.updateDraft(text: "Edited yesterday", now: time(13))

        XCTAssertThrowsError(
            try document.beginDraft(for: tokyoDay, now: time(14))
        ) {
            XCTAssertEqual($0 as? DailyNotesError, .draftRecoveryRequired)
        }
        try document.copyRecoverableDraft(to: tokyoDay, now: time(15))
        XCTAssertEqual(document.draft?.dayID, tokyoDay)
        XCTAssertNil(document.draft?.editingNoteID)
        XCTAssertEqual(document.savedNotes(for: londonDay).map(\.text), ["Original"])
    }

    func testUnfinishedDraftMustBeResolvedBeforeEditingAnotherNote() throws {
        var document = try documentWithNotes(["First", "Second"])
        try document.beginDraft(for: londonDay, now: time(12))
        try document.updateDraft(text: "Unfinished", now: time(13))
        let secondID = document.savedNotes(for: londonDay)[1].id

        XCTAssertThrowsError(
            try document.beginDraft(for: londonDay, editing: secondID, now: time(14))
        ) {
            XCTAssertEqual($0 as? DailyNotesError, .unfinishedDraftExists)
        }
        XCTAssertEqual(document.draft?.text, "Unfinished")
    }

    func testVerifiedNotesCleanUpOnlyOnLaterDateAndKeepDraft() throws {
        var document = try documentWithNotes(["Exported"])
        let snapshot = document.snapshot(for: londonDay)
        try document.markVerified(
            snapshot: snapshot,
            payloadSHA256: "abc",
            verifiedAt: time(20)
        )
        try document.beginDraft(for: londonDay, now: time(21))
        try document.updateDraft(text: "Unfinished", now: time(22))

        XCTAssertTrue(document.cleanupVerifiedNotes(before: londonDay).isEmpty)
        XCTAssertEqual(document.savedNotes(for: londonDay).count, 1)
        XCTAssertEqual(document.cleanupVerifiedNotes(before: nextLondonDay), [londonDay])
        XCTAssertTrue(document.savedNotes(for: londonDay).isEmpty)
        XCTAssertEqual(document.draft?.text, "Unfinished")
    }

    func testPostVerificationMutationPreventsCleanup() throws {
        var document = try documentWithNotes(["Exported"])
        let snapshot = document.snapshot(for: londonDay)
        try document.markVerified(
            snapshot: snapshot,
            payloadSHA256: "abc",
            verifiedAt: time(20)
        )
        try add("Unsent", to: &document)

        XCTAssertTrue(document.cleanupVerifiedNotes(before: nextLondonDay).isEmpty)
        XCTAssertEqual(document.savedNotes(for: londonDay).map(\.text), ["Exported", "Unsent"])
    }

    func testStaleRevisionCannotBeMarkedVerified() throws {
        var document = try documentWithNotes(["First"])
        let stale = document.snapshot(for: londonDay)
        try add("Second", to: &document)
        XCTAssertThrowsError(
            try document.markVerified(
                snapshot: stale,
                payloadSHA256: "abc",
                verifiedAt: time(20)
            )
        ) {
            XCTAssertEqual($0 as? DailyNotesError, .staleRevision)
        }
    }

    private var londonDay: DailyNoteDayID {
        DailyNoteDayID(reportDate: "2026-09-08", timeZoneIdentifier: "Europe/London")
    }

    private var nextLondonDay: DailyNoteDayID {
        DailyNoteDayID(reportDate: "2026-09-09", timeZoneIdentifier: "Europe/London")
    }

    private var tokyoDay: DailyNoteDayID {
        DailyNoteDayID(reportDate: "2026-09-09", timeZoneIdentifier: "Asia/Tokyo")
    }

    private func time(_ hour: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(hour * 3_600))
    }

    private func add(_ text: String, to document: inout DailyNotesDocument) throws {
        try document.beginDraft(for: londonDay, now: time(document.savedNotes(for: londonDay).count))
        try document.updateDraft(text: text, now: time(1))
        try document.saveDraft(now: time(2))
    }

    private func documentWithNotes(_ texts: [String]) throws -> DailyNotesDocument {
        var document = DailyNotesDocument()
        for text in texts { try add(text, to: &document) }
        return document
    }
}
