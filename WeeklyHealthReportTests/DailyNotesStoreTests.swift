import XCTest
@testable import WeeklyHealthReport

@MainActor
final class DailyNotesStoreTests: XCTestCase {
    func testFileStorePersistsSavedNotesAndDraftAcrossRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WeeklyHealthReportNotesTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = FileDailyNotesStore(fileURL: directory.appending(path: "notes.json"))
        let now = londonDate(2026, 9, 8, 10)
        let first = DailyNotesController(store: store, calendar: londonCalendar, now: { now })

        XCTAssertTrue(first.beginNewDraft())
        first.updateDraftText("Saved note")
        XCTAssertTrue(first.saveDraft())
        XCTAssertTrue(first.beginNewDraft())
        first.updateDraftText("Unfinished draft")
        first.flushDraft()

        let relaunched = DailyNotesController(store: store, calendar: londonCalendar, now: { now })
        XCTAssertEqual(relaunched.notes.map(\.text), ["Saved note"])
        XCTAssertEqual(relaunched.currentDraft?.text, "Unfinished draft")
    }

    func testDebouncedDraftSavePersistsLatestText() async throws {
        let store = MemoryDailyNotesStore()
        let now = londonDate(2026, 9, 8, 10)
        let controller = DailyNotesController(store: store, calendar: londonCalendar, now: { now })
        XCTAssertTrue(controller.beginNewDraft())
        controller.updateDraftText("First")
        controller.updateDraftText("Latest")

        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(store.document?.draft?.text, "Latest")
    }

    func testDiscardRemovesPersistedDraft() throws {
        let store = MemoryDailyNotesStore()
        let now = londonDate(2026, 9, 8, 10)
        let controller = DailyNotesController(store: store, calendar: londonCalendar, now: { now })
        XCTAssertTrue(controller.beginNewDraft())
        controller.updateDraftText("Do not keep this")
        controller.flushDraft()
        XCTAssertEqual(store.document?.draft?.text, "Do not keep this")

        XCTAssertTrue(controller.discardDraft())

        let relaunched = DailyNotesController(store: store, calendar: londonCalendar, now: { now })
        XCTAssertNil(relaunched.currentDraft)
    }

    func testFailedSavedMutationPreservesPreviousGoodDocument() throws {
        let store = MemoryDailyNotesStore()
        let now = londonDate(2026, 9, 8, 10)
        let controller = DailyNotesController(store: store, calendar: londonCalendar, now: { now })
        XCTAssertTrue(controller.beginNewDraft())
        controller.updateDraftText("First")
        XCTAssertTrue(controller.saveDraft())
        let previous = try XCTUnwrap(store.document)

        store.failSaves = true
        XCTAssertTrue(controller.beginNewDraft() == false)

        XCTAssertEqual(store.document, previous)
        XCTAssertEqual(controller.notes.map(\.text), ["First"])
        XCTAssertNotNil(controller.errorMessage)
    }

    func testCorruptFileFailsClosedWithoutOverwritingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WeeklyHealthReportNotesCorrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "notes.json")
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: file)

        let controller = DailyNotesController(
            store: FileDailyNotesStore(fileURL: file),
            calendar: londonCalendar,
            now: { self.londonDate(2026, 9, 8, 10) }
        )

        XCTAssertFalse(controller.storageAvailable)
        XCTAssertFalse(controller.beginNewDraft())
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testDateAndTimeZoneChangeRequireExplicitDraftRecovery() throws {
        let store = MemoryDailyNotesStore()
        let londonNow = londonDate(2026, 9, 8, 23)
        let london = DailyNotesController(
            store: store,
            calendar: londonCalendar,
            now: { londonNow }
        )
        XCTAssertTrue(london.beginNewDraft())
        london.updateDraftText("Keep the original date")
        london.flushDraft()

        let tokyo = DailyNotesController(
            store: store,
            calendar: tokyoCalendar,
            now: { londonNow }
        )
        XCTAssertNil(tokyo.currentDraft)
        XCTAssertEqual(tokyo.recoverableDraft?.dayID.reportDate, "2026-09-08")
        XCTAssertEqual(tokyo.currentDayID.reportDate, "2026-09-09")
        XCTAssertTrue(tokyo.copyRecoverableDraftToToday())
        XCTAssertEqual(tokyo.currentDraft?.dayID, tokyo.currentDayID)
    }

    func testCleanupRunsOnlyAfterVerifiedRevisionOnLaterActivation() throws {
        let store = MemoryDailyNotesStore()
        var now = londonDate(2026, 9, 8, 20)
        let controller = DailyNotesController(
            store: store,
            calendar: londonCalendar,
            now: { now }
        )
        XCTAssertTrue(controller.beginNewDraft())
        controller.updateDraftText("Exported")
        XCTAssertTrue(controller.saveDraft())
        let snapshot = controller.document.snapshot(for: controller.currentDayID)
        XCTAssertTrue(controller.markVerified(snapshot: snapshot, payload: Data("payload".utf8)))

        controller.activate()
        XCTAssertEqual(controller.notes.count, 1)
        now = londonDate(2026, 9, 9, 8)
        controller.activate()

        XCTAssertEqual(controller.currentDayID.reportDate, "2026-09-09")
        XCTAssertTrue(store.document?.savedNotes(for: snapshot.dayID).isEmpty == true)
    }

    private var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private var tokyoCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func londonDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        londonCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}

private final class MemoryDailyNotesStore: DailyNotesPersisting {
    var document: DailyNotesDocument?
    var failSaves = false

    func load() throws -> DailyNotesDocument? { document }

    func save(_ document: DailyNotesDocument) throws {
        if failSaves { throw CocoaError(.fileWriteUnknown) }
        self.document = document
    }
}
