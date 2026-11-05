import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// #399 regression: the Health report's food period read and a saved entry's history decode the
/// archive a bounded number of times, whatever the ledger size, and give the same results as the
/// earlier per-day and per-entry reads. Structural (counted reads), never wall-clock.
final class FoodLogPeriodReadCostContractTests: XCTestCase {
    static let days = 7
    static let entriesPerDay = 20

    /// One populated ledger per store serves every check, so the fixture is built once.
    func testAWeekOfTwentyEntriesADayReadsTheArchiveOncePerReadWithTheEarlierResults() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let ledger = try WeekLedger(harness)
            let dates = try ledger.populate()
            XCTAssertEqual(dates.count, Self.days, harness.name)
            let snapshot = try ledger.counting.base.archiveState().records
            // Every entry is compared on the memory store; the database store (whose full reads
            // are what #399 removes, so the earlier path is slow there) compares every seventh.
            let stride = harness.name == "memory" ? 1 : 7
            try checkPeriod(ledger, dates: dates, snapshot: snapshot, stride: stride, harness: harness.name)
            try checkHistory(ledger, dates: dates, snapshot: snapshot, stride: stride, harness: harness.name)
        }
    }

    /// The Health report period (`FoodLogPeriodReader.dayFacts`): `days(reportingDates:)` and
    /// `isPlainWater(_:)` against the earlier `day(reportingDate:)` per date and
    /// `savedEntry(_:)?.isPlainWater` per entry.
    private func checkPeriod(_ ledger: WeekLedger, dates: [String], snapshot: LedgerMutation, stride: Int,
                             harness: String) throws {
        var position = 0
        let previous = try dates.map { date in
            let content = try ledger.service.day(reportingDate: date)
            let water = try content.entries.map { entry -> Bool? in
                defer { position += 1 }
                return position % stride == 0 ? try ledger.service.savedEntry(entry.logItemID)?.isPlainWater == true : nil
            }
            return (content, water)
        }
        // Before #399 each date read the archive once and each entry's saved entry read it once
        // for its versions and again for any conversions they reference.
        let entries = previous.flatMap { $0.0.entries.map(\.logItemID) }
        let earlierReads = dates.count + entries.reduce(0) { total, id in
            total + 1 + (snapshot.logItemVersions.contains { $0.logItemID == id && $0.quantityConversionVersionID != nil } ? 1 : 0)
        }

        ledger.counting.reset()
        let contents = try ledger.service.days(reportingDates: dates)
        let water = try contents.map { try $0.entries.map { try ledger.service.isPlainWater($0.logItemID) } }
        XCTAssertEqual(ledger.counting.reads, 1, "\(harness): one archive read for the whole period")
        print("#399 \(harness): \(entries.count) entries over \(dates.count) days: period archive reads \(earlierReads) before, \(ledger.counting.reads) after")
        XCTAssertGreaterThan(earlierReads, 100, harness)

        XCTAssertEqual(contents.count, previous.count, harness)
        for (index, (old, oldWater)) in previous.enumerated() {
            let new = contents[index]
            XCTAssertEqual(new.reportingDate, old.reportingDate, harness)
            XCTAssertEqual(new.entries, old.entries, harness)
            XCTAssertEqual(new.removed, old.removed, harness)
            XCTAssertEqual(new.totals, old.totals, harness)
            XCTAssertEqual(new.plainWater, old.plainWater, harness)
            XCTAssertEqual(new.foodEntryCount, old.foodEntryCount, harness)
            for (new, old) in zip(water[index], oldWater) where old != nil { XCTAssertEqual(new, old, harness) }
        }
        XCTAssertEqual(water.flatMap { $0 }.filter { $0 }.count, Self.days * 3, "\(harness): three plain water entries a day")
        XCTAssertTrue(contents.allSatisfy { $0.removed.count == 1 }, "\(harness): one removed entry a day")

        ledger.counting.reset()
        XCTAssertTrue(try ledger.service.days(reportingDates: []).isEmpty)
        XCTAssertEqual(ledger.counting.reads, 0, "\(harness): no dates, no read")
    }

    /// `historyEvents` and `savedEntry` read the archive once, with the earlier events.
    private func checkHistory(_ ledger: WeekLedger, dates: [String], snapshot: LedgerMutation, stride: Int,
                              harness: String) throws {
        let all = try ledger.service.days(reportingDates: dates).flatMap { $0.entries.map(\.logItemID) }
        XCTAssertEqual(all.count, Self.days * (Self.entriesPerDay - 1), harness)
        let ids = all.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
        var edited = 0, converted = 0
        for id in ids {
            let earlier = [false, true].map { ledger.previousHistoryEvents(id, isServings: $0, snapshot: snapshot) }
            if snapshot.logItemVersions.contains(where: { $0.logItemID == id && $0.quantityConversionVersionID != nil }) {
                converted += 1
            }
            if earlier[0].count > 1 { edited += 1 }
            ledger.counting.reset()
            XCTAssertEqual(try ledger.service.historyEvents(id), earlier[0], harness)
            XCTAssertEqual(ledger.counting.reads, 1, "\(harness): history reads the archive once")
            ledger.counting.reset()
            let detail = try XCTUnwrap(ledger.service.savedEntry(id), harness)
            XCTAssertEqual(ledger.counting.reads, 1, "\(harness): a saved entry reads the archive once")
            XCTAssertTrue(earlier.contains(detail.history), harness)
        }
        XCTAssertGreaterThanOrEqual(edited, stride == 1 ? Self.days * 2 : 1, "\(harness): edited entries carry several versions")
        XCTAssertGreaterThanOrEqual(converted, stride == 1 ? Self.days : 1, "\(harness): entries with a quantity conversion")
    }
}

/// Seven days of twenty entries each (#399): exact foods, plain water, a pasted label and a
/// reviewed web estimate per day, two edited entries and one removed entry per day. Every save
/// goes through the shared Confirm save path; the archive read count is observed by `counting`.
private struct WeekLedger {
    let counting: CountingFoodArchive
    let service: FoodLogReadingService
    let confirmations: FoodConfirmationService
    let favourites: FavouritesService
    let management: FoodLogManagementService
    let ids: QuickAddSequenceIDs
    let eggSearch: CoFIDGenericFoodSearch
    let calendar = QuickAddFixtures.london

    init(_ harness: TestHarness) throws {
        let base = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
        counting = CountingFoodArchive(base)
        ids = QuickAddSequenceIDs(start: 20_000)
        eggSearch = try CoFIDGenericFoodSearch(ids: QuickAddSequenceIDs(start: 900_000))
        let ledger = try LedgerFixtures.service(harness.committer)
        confirmations = FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock, ids: ids,
            digester: SHA256Digester(), calendar: calendar, pastedLabelConversions: GoldenPastedLabelConversions())
        favourites = try FavouritesService(ledger: ledger, reader: try XCTUnwrap(harness.committer as? any FavouriteReading),
            confirmations: confirmations, clock: LedgerFixtures.clock, ids: ids, digester: SHA256Digester(), calendar: calendar)
        let history = ArchiveFoodLogHistoryReader(archive: counting)
        management = FoodLogManagementService(ledger: ledger, reader: history, clock: LedgerFixtures.clock, ids: ids)
        service = FoodLogReadingService(ledger: ledger, archive: counting, confirmationReader: harness.reader, history: history,
            confirmations: confirmations, clock: LedgerFixtures.clock, ids: ids)
    }

    /// The reporting dates, oldest first.
    func populate() throws -> [String] {
        let review = try PastedReadingFixtures.review(PastedReadingFixtures.reading())
        let web = try ReviewedWebFixtures.v1Fixture("representative-serving").input
        var dates: [String] = []
        for day in 0..<FoodLogPeriodReadCostContractTests.days {
            let base = LedgerFixtures.date.addingTimeInterval(-Double(FoodLogPeriodReadCostContractTests.days - 1 - day) * 86_400)
            var saved: [StoredFoodConfirmation] = []
            func at(_ index: Int) -> Date { base.addingTimeInterval(-Double(index) * 60) }
            for index in 0..<3 {
                var state = try favourites.prepare(.builtInWater).state
                FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(250, .millilitres))
                saved.append(try save(&state, at: at(index)))
            }
            var label = PastedLabelFixtures.state(try PastedReadingFixtures.input(review))
            saved.append(try save(&label, at: at(3)))
            var reviewed = FoodConfirmationState(input: web)
            FoodConfirmationReducer.reduce(state: &reviewed, action: .setQuantity(1, .count))
            reviewed.answerPendingDifferences()
            saved.append(try save(&reviewed, at: at(4)))
            var eggs = try eggsWithConversion()
            saved.append(try save(&eggs, at: at(5)))
            for index in 6..<FoodLogPeriodReadCostContractTests.entriesPerDay {
                var state = FoodConfirmationState(input: try QuickAddFixtures.exactInput(day * 100 + index), prefillSourceQuantity: false)
                FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(Double(50 + index * 5), .grams))
                saved.append(try save(&state, at: at(index)))
            }
            // Two edits (superseded versions) and one removal per day.
            for entry in [saved[6], saved[7]] {
                var state = try XCTUnwrap(try confirmations.reopen(logItemID: entry.logItem.logItemID))
                FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(321, .grams))
                FoodConfirmationReducer.reduce(state: &state, action: .accept)
                _ = try confirmations.save(state, operationID: ids.makeID(OperationTag.self))
            }
            let removed = saved[8]
            try management.remove(logItemID: removed.logItem.logItemID, expectedVersion: removed.logItemVersion.logItemVersionID,
                                   reason: LedgerText(FoodLogReadingService.removalReason), operationID: ids.makeID(OperationTag.self))
            dates.append(saved[0].logItemVersion.reportingDate.value)
        }
        XCTAssertEqual(Set(dates).count, dates.count, "one reporting date per day")
        return dates
    }

    /// Three eggs weighed at 168 g: a count amount with a stored quantity conversion.
    private func eggsWithConversion() throws -> FoodConfirmationState {
        let request = GenericFoodSearchRequest(text: try LedgerText("egg"), identity: GenericFoodIdentityQuery(),
                                               capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"))
        guard case let .confirmation(route) = try eggSearch.search(request), let egg = route.matches.first?.candidate else {
            throw XCTSkip("Expected a CoFID egg match")
        }
        let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence,
            sourceReleases: route.confirmation.sourceReleases, candidates: [egg],
            expectedIdentity: egg.candidate.identity, expectedEdibleQuantity: egg.candidate.edibleQuantity)
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(3, .count))
        FoodConfirmationReducer.reduce(state: &state, action: .setConversion(QuantityConversionDraft(
            convertedQuantity: try PositiveQuantity(value: 168, unit: .grams),
            methodVersion: try XCTUnwrap(CountConversionMethod.kitchenScale.storedCode))))
        return state
    }

    private func save(_ state: inout FoodConfirmationState, at date: Date) throws -> StoredFoodConfirmation {
        FoodConfirmationReducer.reduce(state: &state, action: .setOccurredAt(date))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return try confirmations.save(state, operationID: ids.makeID(OperationTag.self))
    }

    /// The history events as `historyEvents` built them before #399, with one unchanged snapshot
    /// standing in for both of its archive reads (the versions, then the conversions).
    func previousHistoryEvents(_ logItemID: LogItemID, isServings: Bool, snapshot: LedgerMutation) -> [FoodEntryHistoryEvent] {
        let versions = snapshot.logItemVersions.filter { $0.logItemID == logItemID }
        let referenced = Set(versions.compactMap(\.quantityConversionVersionID))
        let conversions = referenced.isEmpty ? [] : snapshot.quantityConversions
            .filter { referenced.contains($0.quantityConversionVersionID) }
        return FoodEntryHistory.events(versions: versions, conversions: conversions, isServings: isServings)
    }
}

/// Forwards every call to a real store and counts `archiveState()` reads.
final class CountingFoodArchive: FoodArchiveLedgerAccess, @unchecked Sendable {
    let base: any FoodArchiveLedgerAccess
    private let lock = NSLock()
    private var count = 0

    init(_ base: any FoodArchiveLedgerAccess) { self.base = base }

    var reads: Int { lock.withLock { count } }
    func reset() { lock.withLock { count = 0 } }

    func archiveState() throws -> FoodArchiveState {
        lock.withLock { count += 1 }
        return try base.archiveState()
    }
    func commitAtomically(_ transactions: [LedgerTransaction]) throws -> [CommitOutcome] { try base.commitAtomically(transactions) }
    func actorHead(for actorID: ActorID) throws -> ActorHead { try base.actorHead(for: actorID) }
    func operation(id: OperationID) throws -> LedgerOperation? { try base.operation(id: id) }
    func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome { try base.commit(transaction) }
    func counts() throws -> LedgerCounts { try base.counts() }
    func productVersions(productID: ProductID) throws -> [ProductVersion] { try base.productVersions(productID: productID) }
    func resolutionVersion(id: ResolutionVersionID) throws -> NutritionResolutionVersion? { try base.resolutionVersion(id: id) }
    func exactLibraryEntries(alias: LedgerText) throws -> [LibraryEntryVersion] { try base.exactLibraryEntries(alias: alias) }
    func barcodeLibraryRecords(alias: LedgerText) throws -> [BarcodeLibraryRecord] { try base.barcodeLibraryRecords(alias: alias) }
    func conflicts() throws -> [LedgerConflict] { try base.conflicts() }
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { try base.sourceRelease(id: id) }
}
