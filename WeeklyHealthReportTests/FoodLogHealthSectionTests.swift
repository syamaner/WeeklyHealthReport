import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
@testable import WeeklyHealthReport

// Contract tests for docs/health-food-and-water-v1.md (#214): the section, its
// placement, Copy all, the screen wording, the tile, Developer tools, the view
// model and the composition root adapter. All values are synthetic fixtures.
@MainActor
final class FoodLogHealthSectionTests: XCTestCase {
    private typealias SectionID = ReportDocument.SectionID
    private typealias Line = FoodLogReportDiagnostics.Line

    // MARK: Copy all

    func testCopyAllGoldenWithTheSectionAfterDailyActivity() {
        let text = Self.document(foodLog: .available(Self.normalWeek())).plainText(
            generatedAt: Self.now, calendar: FoodLogFixtures.calendar, locale: FoodLogFixtures.locale
        )
        XCTAssertEqual(text, """
        Weekly Health Report
        Last 7 Completed Days
        3–9 Sep 2026
        Generated: 10/09/26 - 12:00

        DAILY ACTIVITY

        Steps
        No step data is visible, or Health access was not granted.

        Activity
        Active Energy: No data
        Exercise: No data
        Workouts: No data

        FOOD AND WATER

        Food and water
        Days Logged: 6 / 7 days
        Logged Energy: 2,010 kcal per day (5 complete days)
        Incomplete Energy Days: 1
        Plain Water: 1,750 mL per day (4 days)
        Logged in this app; not a measure of everything eaten or drunk.

        BODY

        Weight
        No weight data is visible, or Health access was not granted.

        Body Composition
        No body-fat data is visible, or Health access was not granted.
        Waist Circumference: No data

        HEART AND SLEEP

        Heart
        Resting HR Average: No data
        Resting HR Trend: No data
        HRV Average: No data
        HRV Trend: No data
        Watch Data Coverage: No data

        Blood Pressure
        No complete blood-pressure readings are visible, or Health access was not granted.
        Period averages use completed days. Morning is before 14:00; evening is from 17:00. Mid-afternoon readings are excluded from both slot summaries.

        Sleep
        Average Sleep: No data

        FITNESS AND BLOOD OXYGEN

        Cardiorespiratory
        Latest VO₂ Max: No data
        Latest Blood Oxygen: No data
        Apple Watch blood-oxygen measurements are wellness estimates, not medical measurements.

        GLUCOSE

        Glucose
        Daily Average: No data
        Observed Range: No data
        Data Coverage: No data
        """)
        // Tiles are never copied.
        XCTAssertFalse(text.contains("Logged energy"))
    }

    /// Only the Food and water block and its heading are new: every other block
    /// is the same with any food-log state.
    func testOtherBlocksAreIdenticalWhateverTheFoodLogState() {
        func otherBlocks(_ state: MetricState<FoodLogPeriodSummary>) -> [String] {
            Self.document(foodLog: state)
                .plainText(generatedAt: Self.now, calendar: FoodLogFixtures.calendar, locale: FoodLogFixtures.locale)
                .components(separatedBy: "\n\n")
                .filter { $0 != "FOOD AND WATER" && !$0.hasPrefix("Food and water\n") }
        }
        let baseline = otherBlocks(.loading)
        for state: MetricState<FoodLogPeriodSummary> in [
            .available(Self.normalWeek()), .failed("synthetic"), .available(Self.summary([]))
        ] {
            XCTAssertEqual(otherBlocks(state), baseline)
        }
    }

    func testIncompleteEnergyDayOnlyGivesInsufficientHistoryWithTheCount() {
        let dates = Self.dates
        let block = Self.copyAllBlock(.available(Self.summary([
            FoodLogFixtures.day(dates[2], energy: 640, energyIncomplete: 1, water: 500)
        ])))
        XCTAssertEqual(block, """
        Food and water
        Days Logged: 1 / 7 days
        Logged Energy: Insufficient history
        Incomplete Energy Days: 1
        Plain Water: 500 mL per day (1 day)
        Logged in this app; not a measure of everything eaten or drunk.
        """)
        XCTAssertFalse(block.contains("640"), "a known minimum is never shown as an average")
    }

    func testNoPlainWaterSaysNoDataNeverZero() {
        let block = Self.copyAllBlock(.available(Self.summary(
            Self.dates.prefix(3).map { FoodLogFixtures.day($0, energy: 1_999.6) }
        )))
        XCTAssertEqual(block, """
        Food and water
        Days Logged: 3 / 7 days
        Logged Energy: 2,000 kcal per day (3 complete days)
        Plain Water: No data
        Logged in this app; not a measure of everything eaten or drunk.
        """)
        XCTAssertFalse(block.contains("0 mL"))
        XCTAssertFalse(block.contains("Incomplete"), "the incomplete row is left out at 0")
    }

    func testNothingLoggedSaysSoAndNeverZeroKilocalories() {
        let block = Self.copyAllBlock(.available(Self.summary([])))
        XCTAssertEqual(block, """
        Food and water
        No food logged in this period.
        Logged in this app; not a measure of everything eaten or drunk.
        """)
        XCTAssertFalse(block.contains("kcal"))
    }

    /// Contract v1.1: water-only days count towards plain water but are not
    /// logged food days.
    func testWaterOnlyDaysMixedInCountOnlyTowardsPlainWater() {
        let dates = Self.dates
        let block = Self.copyAllBlock(.available(Self.summary([
            FoodLogFixtures.day(dates[0], energy: 1_800, water: 1_000),
            FoodLogFixtures.day(dates[1], energy: 2_000),
            FoodLogFixtures.day(dates[2], energy: 2_200),
            FoodLogFixtures.waterOnly(dates[3], water: 1_500),
            FoodLogFixtures.waterOnly(dates[4], water: 2_000),
            FoodLogFixtures.waterOnly(dates[5], water: 500),
            FoodLogFixtures.waterOnly(dates[6], water: 1_000)
        ])))
        XCTAssertEqual(block, """
        Food and water
        Days Logged: 3 / 7 days
        Logged Energy: 2,000 kcal per day (3 complete days)
        Plain Water: 1,200 mL per day (5 days)
        Logged in this app; not a measure of everything eaten or drunk.
        """)
    }

    func testPeriodWithOnlyPlainWaterShowsTheWaterRow() throws {
        let state = MetricState.available(Self.summary([
            FoodLogFixtures.waterOnly(Self.dates[1], water: 1_000),
            FoodLogFixtures.waterOnly(Self.dates[4], water: 2_000)
        ]))
        XCTAssertEqual(Self.copyAllBlock(state), """
        Food and water
        No food logged in this period.
        Plain Water: 1,500 mL per day (2 days)
        Logged in this app; not a measure of everything eaten or drunk.
        """)
        let display = try XCTUnwrap(Self.document(foodLog: state).forDisplay().sections.first { $0.id == .foodLog })
        XCTAssertEqual(Self.screenLines(display), [
            "No food logged in this period.",
            "Plain water: 1,500 mL per day (2 days)"
        ])
    }

    func testStateRows() {
        XCTAssertEqual(Self.section(.loading).rows.map(\.value), ["Reading the food log…"])
        XCTAssertEqual(
            Self.section(.available(FoodLogPeriodSummary.make(days: [], reportingDates: []))).rows.map(\.value),
            ["There are no completed days in this period yet."]
        )
        XCTAssertEqual(Self.section(.available(Self.summary([]))).rows.map(\.id), ["food-no-data"])
        // A failed read keeps its own sentence in Copy all and on screen; the
        // technical message stays in Developer tools.
        let failed = Self.copyAllBlock(.failed("SQLite error 11: database disk image is malformed"))
        XCTAssertEqual(failed, """
        Food and water
        Could not read the food log.
        Logged in this app; not a measure of everything eaten or drunk.
        """)
        let display = Self.document(foodLog: .failed("SQLite error 11")).forDisplay()
        let row = display.sections.first { $0.id == .foodLog }?.rows.first
        XCTAssertEqual(row?.value, "Could not read the food log.")
        XCTAssertFalse(display.searchableText.contains("SQLite"))
    }

    func testEstimatesAndIncompleteWaterAreLabelled() {
        let dates = Self.dates
        let block = Self.copyAllBlock(.available(Self.summary([
            FoodLogFixtures.day(dates[0], energy: 1_500, estimates: true, water: 1_000),
            FoodLogFixtures.day(dates[1], energy: 2_500, water: 400, waterIncomplete: 1)
        ])))
        XCTAssertTrue(block.contains("Logged Energy: 2,000 kcal per day (2 complete days), includes estimates"), block)
        XCTAssertTrue(block.contains("Plain Water: 1,000 mL per day (1 day; 1 incomplete day left out)"), block)

        let onlyIncompleteWater = Self.copyAllBlock(.available(Self.summary([
            FoodLogFixtures.day(dates[0], energy: 0, water: 400, waterIncomplete: 1)
        ])))
        XCTAssertTrue(onlyIncompleteWater.contains("Plain Water: Insufficient history (1 incomplete day left out)"))
    }

    /// Logged energy is never netted against, or shown beside, active energy (D9).
    func testNoNetBalanceOrIntakeWording() {
        let block = Self.copyAllBlock(.available(Self.normalWeek())).lowercased()
        for word in ["active", "net", "balance", "deficit", "intake", "calories eaten", "protein", "target"] {
            XCTAssertFalse(block.contains(word), word)
        }
    }

    // MARK: Placement (#216 decision 5)

    func testFoodAndWaterGroupFollowsDailyActivity() {
        XCTAssertEqual(ReportDocument.GroupID.allCases.prefix(3), [.dailyActivity, .foodAndWater, .body])
        XCTAssertEqual(ReportDocument.groups[1].heading, "Food and water")
        XCTAssertEqual(ReportDocument.groups[1].sectionIDs, [.foodLog])
        XCTAssertEqual(ReportDocument.group(for: .foodLog), .foodAndWater)
        XCTAssertFalse(ReportDocument.groups[0].sectionIDs.contains(.foodLog), "never inside Daily activity")

        let document = Self.document(foodLog: .available(Self.normalWeek()))
        XCTAssertEqual(Array(document.sections.map(\.id).prefix(4)), [.steps, .activity, .foodLog, .weight])
        let grouped = document.forDisplay().groupedSections
        XCTAssertEqual(grouped.map(\.heading).prefix(3), ["Daily activity", "Food and water", "Body"])
        XCTAssertEqual(grouped[1].sections.map(\.id), [.foodLog])
    }

    // MARK: Screen and Full Page wording

    func testScreenWordingForANormalWeek() throws {
        let display = Self.document(foodLog: .available(Self.normalWeek())).forDisplay()
        let section = try XCTUnwrap(display.sections.first { $0.id == .foodLog })
        XCTAssertEqual(section.title, "Food and water")
        XCTAssertEqual(Self.screenLines(section), [
            "Days logged: 6 / 7 days",
            "Logged energy: 2,010 kcal per day (5 complete days)",
            "Incomplete energy days: 1",
            "Plain water: 1,750 mL per day (4 days)"
        ])
        XCTAssertEqual(section.footer, ReportDocument.foodLogFooter)
        XCTAssertEqual(display.forDisplay(), display)
    }

    /// Full Page renders the expanded display document, so it has the same block.
    func testFullPageHasTheSameSection() throws {
        let snapshot = Self.snapshot(foodLog: .available(Self.normalWeek()))
        let expanded = ReportDocument.expanded(
            snapshot: snapshot, calendar: FoodLogFixtures.calendar, locale: FoodLogFixtures.locale
        ).forDisplay()
        let screen = ReportDocument(
            snapshot: snapshot, calendar: FoodLogFixtures.calendar, locale: FoodLogFixtures.locale
        ).forDisplay()
        XCTAssertEqual(
            expanded.sections.first { $0.id == .foodLog },
            screen.sections.first { $0.id == .foodLog }
        )
    }

    // MARK: Tile

    func testLoggedEnergyTileRepeatsTheSectionRows() throws {
        let display = Self.document(foodLog: .available(Self.normalWeek())).forDisplay()
        let tile = try XCTUnwrap(HealthSummaryTiles.make(from: display).first { $0.kind == .loggedEnergy })
        XCTAssertEqual(tile.title, "Logged energy")
        XCTAssertEqual(tile.primary.id, "food-energy-average")
        // The row's own label would repeat the tile title.
        XCTAssertEqual(tile.primary.label, "Average per day")
        XCTAssertNotEqual(tile.primary.label, tile.title)
        XCTAssertEqual(tile.primary.value, "2,010 kcal per day (5 complete days)")
        XCTAssertEqual(tile.detail?.label, "Days logged")
        XCTAssertEqual(tile.detail?.value, "6 / 7 days")
        XCTAssertEqual(
            display.sections.first { $0.id == .foodLog }?.rows.first { $0.id == "food-energy-average" }?.label,
            "Logged energy",
            "the section row keeps its label"
        )

        func stateTile(_ state: MetricState<FoodLogPeriodSummary>) -> String? {
            HealthSummaryTiles.make(from: Self.document(foodLog: state).forDisplay())
                .first { $0.kind == .loggedEnergy }?.primary.value
        }
        XCTAssertEqual(stateTile(.loading), MetricRowVocabulary.loading)
        XCTAssertEqual(stateTile(.failed("x")), MetricRowVocabulary.couldNotRead)
        XCTAssertEqual(
            stateTile(.available(FoodLogPeriodSummary.make(days: [], reportingDates: []))),
            MetricRowVocabulary.noCompletedDays
        )
        // Nothing logged stays distinct from "No data" and is never 0 kcal.
        XCTAssertEqual(stateTile(.available(Self.summary([]))), "No food logged in this period.")
        XCTAssertNotEqual(stateTile(.available(Self.summary([]))), MetricRowVocabulary.noData)
        XCTAssertEqual(
            stateTile(.available(Self.summary([FoodLogFixtures.waterOnly(Self.dates[0], water: 500)]))),
            "No food logged in this period."
        )
    }

    // MARK: Developer tools

    func testDeveloperToolsShowEachDaysInputsAndTheFailureMessage() {
        let lines = FoodLogReportDiagnostics.lines(.available(Self.normalWeek()))
        XCTAssertEqual(lines.first, Line(title: "Policy", detail: "health_food_log_period_v1"))
        XCTAssertEqual(lines.count, 4 + 7)
        XCTAssertEqual(lines[2].detail, "2010.08 kcal, estimates no")
        XCTAssertEqual(lines[4], Line(
            title: "2026-09-03",
            detail: "4 entries (3 food); energy 1900 kcal, 0 incomplete, estimates no; plain water 1500 mL, 0 incomplete, estimates no; energy complete, water complete"
        ))
        XCTAssertEqual(lines[6], Line(
            title: "2026-09-05",
            detail: "0 entries (0 food); energy none; plain water none; not logged, no plain water"
        ))
        XCTAssertTrue(lines[8].detail.hasSuffix("energy incomplete, water complete"), lines[8].detail)

        XCTAssertEqual(FoodLogReportDiagnostics.lines(.failed("disk I/O")), [Line(title: "Read failed", detail: "disk I/O")])
        let failures = Self.snapshot(foodLog: .failed("disk I/O")).readFailures
        XCTAssertEqual(failures.last, ReportReadFailure(metric: "Food log", message: "disk I/O"))
    }

    // MARK: View model

    func testRefreshReadsOneReportingDatePerCompletedDayAndPublishesTheSummary() async {
        let reader = FakeFoodLogReader(facts: FoodLogFixtures.normalWeekFacts(dates: Self.dates))
        let viewModel = Self.viewModel(foodLog: reader)
        await viewModel.refresh()
        let requests = await reader.requests
        XCTAssertEqual(requests, [Self.dates], "today (2026-09-10) is never requested")
        XCTAssertEqual(viewModel.foodLogState, .available(Self.normalWeek()))
        XCTAssertEqual(
            viewModel.presentationSnapshot(
                includesMedicationSection: false,
                showsMorningBloodPressureDetails: true,
                showsEveningBloodPressureDetails: true
            ).foodLog,
            viewModel.foodLogState
        )
    }

    func testFoodLogFailureNeverChangesHealthKitStates() async {
        let failing = Self.viewModel(foodLog: FakeFoodLogReader(error: FixtureError.glucoseFailure))
        let succeeding = Self.viewModel(foodLog: FakeFoodLogReader(facts: []))
        await failing.refresh()
        await succeeding.refresh()
        guard case .failed = failing.foodLogState else {
            return XCTFail("Expected a failed food log, got \(failing.foodLogState)")
        }
        XCTAssertEqual(failing.state, succeeding.state)
        XCTAssertEqual(failing.activeEnergyState, succeeding.activeEnergyState)
        XCTAssertEqual(failing.weightState, succeeding.weightState)
        XCTAssertEqual(failing.sleepState, succeeding.sleepState)
        XCTAssertEqual(failing.lastRefreshed, succeeding.lastRefreshed)
    }

    func testAppleHealthUnavailableStillReadsTheFoodLog() async {
        let viewModel = Self.viewModel(
            provider: FakeHealthDataProvider(isHealthDataAvailable: false),
            foodLog: FakeFoodLogReader(facts: FoodLogFixtures.normalWeekFacts(dates: Self.dates))
        )
        await viewModel.refresh()
        XCTAssertEqual(viewModel.state, .healthUnavailable)
        XCTAssertEqual(viewModel.foodLogState, .available(Self.normalWeek()))
    }

    func testNoFoodLogIsAReadFailure() async {
        let viewModel = Self.viewModel(foodLog: nil)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.foodLogState, .failed(WeeklyReportViewModel.foodLogUnavailableMessage))
    }

    func testNoCompletedDaysNeverReadsTheFoodLog() async {
        let reader = FakeFoodLogReader(facts: [])
        let monday = FoodLogFixtures.date(2026, 9, 7, hour: 9)
        let viewModel = Self.viewModel(foodLog: reader, dates: [monday])
        viewModel.selection = .currentWeek
        await viewModel.refresh()
        let requests = await reader.requests
        XCTAssertEqual(requests, [])
        XCTAssertEqual(viewModel.foodLogState, .available(FoodLogPeriodSummary.make(days: [], reportingDates: [])))
        XCTAssertEqual(
            Self.section(viewModel.foodLogState).rows.map(\.id),
            ["food-no-completed-days"]
        )
    }

    func testRefreshFoodLogPicksUpNewEntriesWithoutTouchingHealthKit() async {
        let reader = FakeFoodLogReader(facts: [])
        let viewModel = Self.viewModel(foodLog: reader, dates: [Self.now, Self.now])
        await viewModel.refresh()
        XCTAssertEqual(viewModel.foodLogState.value?.loggedDayCount, 0)
        let refreshed = viewModel.lastRefreshed
        await reader.setFacts([FoodLogFixtures.day(Self.dates[6], energy: 1_234)])
        await viewModel.refreshFoodLog()
        XCTAssertEqual(viewModel.foodLogState.value?.loggedDayCount, 1)
        XCTAssertEqual(viewModel.foodLogState.value?.averageEnergyKilocalories, 1_234)
        XCTAssertEqual(viewModel.lastRefreshed, refreshed)
        let requests = await reader.requests
        XCTAssertEqual(requests, [Self.dates, Self.dates])
    }

    // MARK: Port contract: a fake and the real adapter

    /// The real adapter over a synthetic ledger: backdated entries count on their
    /// stored date, removed and superseded (edited) versions never contribute,
    /// plain water is plain water entries only, and a water-only day is not a
    /// logged food day. A fake port returning the same facts gives the same summary.
    func testRealAdapterAndFakePortPassTheSameContract() async throws {
        let ledger = try makeLedger()
        let root = ledger.root
        let yesterday = try ledger.key(-1), twoDaysAgo = try ledger.key(-2), threeDaysAgo = try ledger.key(-3)
        _ = try logWater(root, on: yesterday)
        let edited = try logWater(root, on: yesterday)
        // Edit 250 mL to 400 mL: the superseded 250 mL version is left out.
        let edit = try XCTUnwrap(try root.model(reopening: edited.logItem.logItemID))
        edit.send(.setQuantity(400, .millilitres))
        edit.log()
        XCTAssertNotNil(edit.savedResult, "\(edit.state.phase)")
        _ = try logWater(root, on: twoDaysAgo)
        let removed = try logWater(root, on: threeDaysAgo)
        let outcome = await root.foodLogStore.remove(
            removed.logItem.logItemID, expected: removed.logItemVersion.logItemVersionID
        )
        XCTAssertEqual(outcome, .applied)
        _ = try logWater(root, on: nil)

        let reportingDates = [threeDaysAgo, twoDaysAgo, yesterday]
        let real = root.foodLogPeriodReader
        let realFacts = try await real.dayFacts(for: reportingDates)
        let expected = [
            FoodLogDayFacts(reportingDate: threeDaysAgo, entryCount: 0, foodEntryCount: 0, energy: nil, plainWater: nil),
            FoodLogDayFacts(
                reportingDate: twoDaysAgo, entryCount: 1, foodEntryCount: 0, energy: nil,
                plainWater: .init(knownAmount: 250, incompleteContributions: 0, includesEstimates: false)
            ),
            FoodLogDayFacts(
                reportingDate: yesterday, entryCount: 2, foodEntryCount: 0, energy: nil,
                plainWater: .init(knownAmount: 650, incompleteContributions: 0, includesEstimates: false)
            )
        ]
        XCTAssertEqual(realFacts, expected)

        for port in [real, FakeFoodLogReader(facts: expected) as any FoodLogPeriodReading] {
            let summary = FoodLogPeriodSummary.make(
                days: try await port.dayFacts(for: reportingDates), reportingDates: reportingDates
            )
            // A period with only plain water: no logged food day, water still averaged.
            XCTAssertEqual(summary.loggedDayCount, 0)
            XCTAssertEqual(summary.days.map(\.energy), [.notLogged, .notLogged, .notLogged])
            XCTAssertEqual(summary.averagePlainWaterMillilitres, 450)
            XCTAssertEqual(summary.completeWaterDayCount, 2)
            XCTAssertEqual(
                Self.section(.available(summary)).rows.map(\.id),
                ["food-no-data", "food-plain-water-average"]
            )
        }
    }

    /// Food and plain water on one day and water only on another, through the real adapter.
    func testRealAdapterMixesFoodDaysAndWaterOnlyDays() async throws {
        let ledger = try makeLedger()
        let root = ledger.root
        let yesterday = try ledger.key(-1), twoDaysAgo = try ledger.key(-2)
        let food = try savedClementine(root, entryDay: yesterday)
        _ = try logWater(root, on: yesterday)
        _ = try logWater(root, on: twoDaysAgo)

        let facts = try await root.foodLogPeriodReader.dayFacts(for: [twoDaysAgo, yesterday])
        XCTAssertEqual(facts.map(\.entryCount), [1, 2])
        XCTAssertEqual(facts.map(\.foodEntryCount), [0, 1])
        XCTAssertNil(facts[0].energy)
        let day = try root.foodLogService.day(reportingDate: yesterday)
        let foodEnergy = try XCTUnwrap(day.entries.first { $0.logItemID == food.logItem.logItemID }?.energyKcal)
        XCTAssertEqual(facts[1].energy?.knownAmount ?? -1, foodEnergy, accuracy: 1e-9)
        XCTAssertEqual(facts[1].energy?.incompleteContributions, 0)
        let summary = FoodLogPeriodSummary.make(days: facts, reportingDates: [twoDaysAgo, yesterday])
        XCTAssertEqual(summary.loggedDayCount, 1)
        XCTAssertEqual(summary.days.first?.energy, .notLogged)
        XCTAssertEqual(summary.completeEnergyDayCount, 1)
        XCTAssertEqual(summary.averagePlainWaterMillilitres, 250)
        XCTAssertEqual(summary.completeWaterDayCount, 2)
    }

    /// A food whose energy is unknown makes its day incomplete.
    func testRealAdapterFoodWithUnknownEnergyIsIncomplete() async throws {
        let ledger = try makeLedger()
        let root = ledger.root
        let saved = try saveReviewedWebEntry(root)
        let date = saved.logItemVersion.reportingDate.value
        _ = try logWater(root, on: date)
        let facts = try await root.foodLogPeriodReader.dayFacts(for: [date])
        XCTAssertEqual(facts.first?.foodEntryCount, 1)
        let energy = try XCTUnwrap(facts.first?.energy)
        XCTAssertGreaterThan(energy.incompleteContributions, 0)
        let summary = FoodLogPeriodSummary.make(days: facts, reportingDates: [date])
        XCTAssertEqual(summary.days.map(\.energy), [.incomplete])
        XCTAssertEqual(summary.incompleteEnergyDayCount, 1)
        XCTAssertNil(summary.averageEnergyKilocalories)
        XCTAssertEqual(summary.averagePlainWaterMillilitres, 250)
    }

    /// Two current heads for one entry (a removal committed against a stale view)
    /// make the read fail, and the section reports it as a food-log failure.
    func testRealAdapterCompetingHeadsGiveAFailedState() async throws {
        let ledger = try makeLedger()
        let root = ledger.root
        let yesterday = try ledger.key(-1)
        let saved = try logWater(root, on: yesterday)
        let outcome = await root.foodLogStore.remove(
            saved.logItem.logItemID, expected: saved.logItemVersion.logItemVersionID
        )
        XCTAssertEqual(outcome, .applied)

        // A second removal of the same original version, committed through a
        // separate connection as a recorded conflict (the store refuses an
        // unrecorded competing successor), leaving two current heads.
        let firstRemoval = try XCTUnwrap(root.foodLogService.day(reportingDate: yesterday).removed.first)
        let store = try FoodLedgerGRDBStore(databaseURL: ledger.databaseURL)
        // The stored original, not the in-memory one: stored dates are rounded, and the
        // store checks the removal against the stored predecessor.
        let original = try XCTUnwrap(store.archiveState().records.logItemVersions.first {
            $0.logItemVersionID == saved.logItemVersion.logItemVersionID
        })
        let ids = RandomLedgerIDGenerator()
        let competing = try LogItemVersion(
            logItemVersionID: ids.makeID(LogItemVersionTag.self),
            logItemID: original.logItemID, ordinal: VersionOrdinal(original.ordinal.value + 1),
            supersedesLogItemVersionID: original.logItemVersionID,
            occurredAt: original.occurredAt, reportingDate: original.reportingDate,
            composition: .removed(original.logItemVersionID), edibleQuantity: original.edibleQuantity,
            weightDeclaration: original.weightDeclaration,
            quantityConversionVersionID: original.quantityConversionVersionID,
            plateWeightVersionID: original.plateWeightVersionID,
            originalResolutionVersionID: original.originalResolutionVersionID,
            effectiveResolutionVersionID: original.effectiveResolutionVersionID,
            correctionReason: LedgerText("Synthetic competing removal"), createdAt: Date()
        )
        let conflict = try LedgerConflict(
            conflictID: ids.makeID(ConflictTag.self),
            kind: .competingLogCorrections,
            ancestorVersionID: VersionReference(original.logItemVersionID.rawValue),
            competingVersionIDs: [
                VersionReference(firstRemoval.logItemVersionID.rawValue),
                VersionReference(competing.logItemVersionID.rawValue)
            ],
            createdAt: Date()
        )
        let service = FoodLedgerService(
            actorID: try ActorID(UUID().uuidString.lowercased()), committer: store, clock: SystemLedgerClock(),
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()
        )
        _ = try service.commit(
            LedgerMutation(logItemVersions: [competing], conflicts: [conflict]),
            type: .preserveConflict,
            operationID: ids.makeID(OperationTag.self)
        )

        do {
            _ = try await root.foodLogPeriodReader.dayFacts(for: [yesterday])
            XCTFail("competing heads must fail the read")
        } catch {}

        let viewModel = WeeklyReportViewModel(
            healthData: FakeHealthDataProvider(),
            foodLog: root.foodLogPeriodReader,
            calendar: root.confirmationDayCalendar,
            now: { root.confirmationNow }
        )
        await viewModel.refresh()
        guard case .failed = viewModel.foodLogState else {
            return XCTFail("Expected a failed food log, got \(viewModel.foodLogState)")
        }
        XCTAssertEqual(
            Self.section(viewModel.foodLogState).rows.map(\.value),
            [ReportDocument.foodLogReadFailedMessage]
        )
    }

    /// Cancelling the caller of `refreshFoodLog()` (the Health report's `.task`)
    /// never publishes a failure.
    func testCancellingRefreshFoodLogNeverPublishesAFailure() async {
        let reader = FakeFoodLogReader(facts: [], cancellationAware: true)
        let viewModel = Self.viewModel(foodLog: reader, dates: [Self.now, Self.now])
        await viewModel.refresh()
        let caller = Task { await viewModel.refreshFoodLog() }
        caller.cancel()
        await caller.value
        XCTAssertEqual(viewModel.foodLogState, .available(Self.summary([])))
    }

    private struct Ledger {
        let root: FoodLedgerCompositionRoot
        let databaseURL: URL
        let key: (Int) throws -> String
    }

    private func makeLedger() throws -> Ledger {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let suite = "food-log-health-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let root = try FoodLedgerCompositionRoot(
            fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults
        )
        let calendar = root.confirmationDayCalendar
        let now = root.confirmationNow
        return Ledger(
            root: root,
            databaseURL: directory.appendingPathComponent("WeeklyHealthReport/FoodLedger/v1/food-ledger.sqlite"),
            key: { offset in
                FoodReportingDay.key(
                    for: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: now)), calendar: calendar
                )
            }
        )
    }

    /// Logs the 250 mL plain water preset on `day` (nil: now).
    private func logWater(_ root: FoodLedgerCompositionRoot, on day: String?) throws -> StoredFoodConfirmation {
        let sheet = root.quickAddSheetModel(try root.quickAddPreparation(.builtInWater), entryDay: day)
        sheet.log()
        let saved = try XCTUnwrap(sheet.savedResult)
        if let day { XCTAssertEqual(saved.logItemVersion.reportingDate.value, day) }
        return saved
    }

    private func savedClementine(_ root: FoodLedgerCompositionRoot, entryDay: String) throws -> StoredFoodConfirmation {
        let search = try root.genericFoodSearchModel(locale: Locale(identifier: "en_GB"))
        search.query = "clementine"
        search.search()
        guard case let .results(route) = search.phase else { throw XCTSkip("Expected offline fruit candidates") }
        let candidate = try XCTUnwrap(route.confirmation.candidates.first)
        let input = try PopulatedFoodConfirmation(
            evidence: route.confirmation.evidence, sourceReleases: route.confirmation.sourceReleases,
            candidates: [candidate], expectedIdentity: candidate.candidate.identity,
            expectedEdibleQuantity: candidate.candidate.edibleQuantity
        )
        let confirmation = root.model(for: input, entryDay: entryDay)
        let identity = try DecisiveIdentity(
            preparation: PreparationState(kind: .raw), bone: .notApplicable, skin: .skinless,
            drained: .notApplicable, packingMedium: .named(LedgerText("none (synthetic fixture)")),
            fortification: .unfortified, servingBasis: candidate.candidate.identity.servingBasis
        )
        confirmation.send(.applyCorrection(FoodCorrection(
            name: try LedgerText("Synthetic clementine flesh"), brand: nil, variant: nil,
            identity: identity, nutrients: candidate.candidate.nutrients,
            reason: try LedgerText("Explicit identity assertions for an isolated fixture")
        )))
        confirmation.send(.setQuantity(100, .grams))
        confirmation.save()
        return try XCTUnwrap(confirmation.savedResult, "\(confirmation.state.phase)")
    }

    /// A reviewed web entry that declares only protein, so its energy is unknown.
    private func saveReviewedWebEntry(_ root: FoodLedgerCompositionRoot) throws -> StoredFoodConfirmation {
        let source = try GenericFoodDocumentProjector.project(
            Data("Synthetic tofu Per 100g Protein 6g".utf8),
            url: URL(string: "https://example.com/synthetic-tofu")!, mediaType: "text/plain",
            retrievedAt: Date(timeIntervalSince1970: TimeInterval(Int(Date().timeIntervalSince1970) - 60)),
            origin: "synthetic_fixture"
        )
        let reference: [[String: Any]] = [["block_id": "b1", "quote": source.blocks[0].text]]
        let nutrients: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            ["key": key.rawValue, "state": key == .protein ? "declared" : "unknown",
             "value": key == .protein ? "6" as Any : NSNull(), "unit": key == .protein ? "g" as Any : NSNull(),
             "evidence": key == .protein ? reference : [],
             "unknown_reason": key == .protein ? NSNull() : "not_observed" as Any]
        }
        let payload: [String: Any] = ["version": FoodProposalExtraction.schemaVersion, "preferred_id": "c1", "candidates": [[
            "id": "c1", "document_id": source.id, "name": "Synthetic tofu", "brand": NSNull(), "preparation": NSNull(),
            "identity_evidence": reference, "panel_evidence": reference,
            "basis": ["amount": "100", "unit": "g", "label": "Per 100g", "evidence": reference],
            "nutrients": nutrients, "limitations": ["Synthetic source. Only protein is declared."]]]]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let extraction = try decoder.decode(
            FoodProposalExtraction.self, from: JSONSerialization.data(withJSONObject: payload)
        )
        let validation = try FoodProposalBinding.validate(extraction, documents: [source])
        let review = GenericFoodProposalReview(
            foodTerms: "Synthetic tofu", discovery: nil, documents: [source], validation: validation,
            selection: try FoodProposalSelection(unscoredChoice: "c1", validation: validation),
            attemptedSourceURL: URL(string: source.url)
        )
        let proposal = try XCTUnwrap(validation.candidates.first)
        let input = try ReviewedFoodProposalConfirmation(
            ids: RandomLedgerIDGenerator(), clock: SystemLedgerClock(),
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester()
        ).prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("en_GB"))
        let model = root.model(for: input, prefillSourceQuantity: false)
        model.send(.setQuantity(50, .grams))
        for facet in model.pendingDifferences {
            if let choice = model.offeredChoices(facet).first(where: { $0 == .notSure })
                ?? model.offeredChoices(facet).first {
                model.send(.decideDifference(facet, choice))
            }
        }
        model.log()
        return try XCTUnwrap(model.savedResult, "\(model.requirements) \(model.state.phase)")
    }

    // MARK: Fixtures

    private static let now = FoodLogFixtures.date(2026, 9, 10, hour: 12)
    private static let period = ReportPeriod.make(
        selection: .lastSevenCompletedDays, now: now, calendar: FoodLogFixtures.calendar
    )
    private static let dates = FoodLogPeriodSummary.reportingDates(for: period, calendar: FoodLogFixtures.calendar)

    private static func normalWeek() -> FoodLogPeriodSummary {
        FoodLogFixtures.normalWeek(dates: dates)
    }

    private static func summary(_ facts: [FoodLogDayFacts]) -> FoodLogPeriodSummary {
        FoodLogPeriodSummary.make(days: facts, reportingDates: dates)
    }

    private static func snapshot(foodLog: MetricState<FoodLogPeriodSummary>) -> ReportPresentationSnapshot {
        ReportPresentationSnapshot(
            period: period,
            steps: .noDataOrAccess,
            weight: .noDataOrAccess,
            bodyFat: .noDataOrAccess,
            waist: .noDataOrAccess,
            glucose: .noDataOrAccess,
            vo2Max: .noDataOrAccess,
            bloodOxygen: .noDataOrAccess,
            bloodPressure: .noDataOrAccess,
            restingHeartRate: .noDataOrAccess,
            hrv: .noDataOrAccess,
            watchCoverage: .noDataOrAccess,
            exercise: .noDataOrAccess,
            activeEnergy: .noDataOrAccess,
            workouts: .noDataOrAccess,
            sleep: .noDataOrAccess,
            medications: .noDataOrAccess,
            foodLog: foodLog,
            includesMedicationSection: false,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: true
        )
    }

    private static func document(foodLog: MetricState<FoodLogPeriodSummary>) -> ReportDocument {
        ReportDocument.expanded(
            snapshot: snapshot(foodLog: foodLog), calendar: FoodLogFixtures.calendar, locale: FoodLogFixtures.locale
        )
    }

    private static func section(_ state: MetricState<FoodLogPeriodSummary>) -> ReportDocument.Section {
        ReportDocument.foodLogSection(state, locale: FoodLogFixtures.locale)
    }

    private static func copyAllBlock(_ state: MetricState<FoodLogPeriodSummary>) -> String {
        let text = document(foodLog: state).plainText(
            generatedAt: now, calendar: FoodLogFixtures.calendar, locale: FoodLogFixtures.locale
        )
        return text.components(separatedBy: "\n\n").first { $0.hasPrefix("Food and water\n") } ?? ""
    }

    private static func screenLines(_ section: ReportDocument.Section) -> [String] {
        section.rows.map { row in row.label.map { "\($0): \(row.value)" } ?? row.value }
    }

    private static func viewModel(
        provider: FakeHealthDataProvider = FakeHealthDataProvider(),
        foodLog: (any FoodLogPeriodReading)?,
        dates: [Date] = [now]
    ) -> WeeklyReportViewModel {
        let clock = FixtureClock(dates: dates)
        return WeeklyReportViewModel(
            healthData: provider,
            foodLog: foodLog,
            calendar: FoodLogFixtures.calendar,
            now: clock.now
        )
    }
}

/// A fake food-log port: returns the facts for the requested dates and records each request.
actor FakeFoodLogReader: FoodLogPeriodReading {
    private var facts: [FoodLogDayFacts]
    private let error: (any Error)?
    private(set) var requests: [[String]] = []

    /// When set, a read in a cancelled task throws `CancellationError`, as a
    /// real cancellable read would.
    private let cancellationAware: Bool

    init(facts: [FoodLogDayFacts] = [], error: (any Error)? = nil, cancellationAware: Bool = false) {
        self.facts = facts
        self.error = error
        self.cancellationAware = cancellationAware
    }

    func setFacts(_ facts: [FoodLogDayFacts]) { self.facts = facts }

    func dayFacts(for reportingDates: [String]) async throws -> [FoodLogDayFacts] {
        requests.append(reportingDates)
        if cancellationAware { try Task.checkCancellation() }
        if let error { throw error }
        return facts.filter { reportingDates.contains($0.reportingDate) }
    }
}
