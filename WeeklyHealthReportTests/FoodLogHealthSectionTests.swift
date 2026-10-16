import XCTest
import FoodLedgerApplication
import FoodLedgerDomain
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
        XCTAssertEqual(tile.primary.value, "2,010 kcal per day (5 complete days)")
        XCTAssertEqual(tile.detail?.label, "Days logged")
        XCTAssertEqual(tile.detail?.value, "6 / 7 days")

        func stateTile(_ state: MetricState<FoodLogPeriodSummary>) -> String? {
            HealthSummaryTiles.make(from: Self.document(foodLog: state).forDisplay())
                .first { $0.kind == .loggedEnergy }?.primary.value
        }
        // State rows are repeated verbatim; a failure uses the tiles' short term.
        XCTAssertEqual(stateTile(.loading), "Reading the food log…")
        XCTAssertEqual(stateTile(.failed("x")), MetricRowVocabulary.couldNotRead)
        XCTAssertEqual(stateTile(.available(Self.summary([]))), "No food logged in this period.")
        XCTAssertEqual(
            stateTile(.available(FoodLogPeriodSummary.make(days: [], reportingDates: []))),
            "There are no completed days in this period yet."
        )
        XCTAssertNotEqual(stateTile(.available(Self.summary([]))), "0 kcal")
    }

    // MARK: Developer tools

    func testDeveloperToolsShowEachDaysInputsAndTheFailureMessage() {
        let lines = FoodLogReportDiagnostics.lines(.available(Self.normalWeek()))
        XCTAssertEqual(lines.first, Line(title: "Policy", detail: "health_food_log_period_v1"))
        XCTAssertEqual(lines.count, 4 + 7)
        XCTAssertEqual(lines[2].detail, "2010.08 kcal, estimates no")
        XCTAssertEqual(lines[4], Line(
            title: "2026-09-03",
            detail: "3 entries; energy 1900 kcal, 0 incomplete, estimates no; plain water 1500 mL, 0 incomplete, estimates no; energy complete, water complete"
        ))
        XCTAssertEqual(lines[6], Line(
            title: "2026-09-05",
            detail: "0 entries; energy none; plain water none; not logged, no plain water"
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
    /// stored date, removed entries never contribute, today is not requested and
    /// plain water is plain water entries only. A fake port returning the same
    /// facts gives the same summary.
    func testRealAdapterAndFakePortPassTheSameContract() async throws {
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
        func key(_ offset: Int) throws -> String {
            FoodReportingDay.key(
                for: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: now)), calendar: calendar
            )
        }
        let yesterday = try key(-1), twoDaysAgo = try key(-2), threeDaysAgo = try key(-3)
        let water = try root.quickAddPreparation(.builtInWater)
        for _ in 0..<2 {
            let sheet = root.quickAddSheetModel(water, entryDay: yesterday)
            sheet.log()
            XCTAssertEqual(sheet.savedResult?.logItemVersion.reportingDate.value, yesterday)
        }
        let removedSheet = root.quickAddSheetModel(water, entryDay: twoDaysAgo)
        removedSheet.log()
        let removed = try XCTUnwrap(removedSheet.savedResult)
        let outcome = await root.foodLogStore.remove(
            removed.logItem.logItemID, expected: removed.logItemVersion.logItemVersionID
        )
        XCTAssertEqual(outcome, .applied)
        let today = root.quickAddSheetModel(water)
        today.log()
        XCTAssertNotNil(today.savedResult)

        let reportingDates = [threeDaysAgo, twoDaysAgo, yesterday]
        let real = root.foodLogPeriodReader
        let realFacts = try await real.dayFacts(for: reportingDates)
        let expected = [
            FoodLogDayFacts(reportingDate: threeDaysAgo, entryCount: 0, energy: nil, plainWater: nil),
            FoodLogDayFacts(reportingDate: twoDaysAgo, entryCount: 0, energy: nil, plainWater: nil),
            FoodLogDayFacts(
                reportingDate: yesterday,
                entryCount: 2,
                energy: .init(knownAmount: 0, incompleteContributions: 0, includesEstimates: false),
                plainWater: .init(knownAmount: 500, incompleteContributions: 0, includesEstimates: false)
            )
        ]
        XCTAssertEqual(realFacts, expected)

        for port in [real, FakeFoodLogReader(facts: expected) as any FoodLogPeriodReading] {
            let summary = FoodLogPeriodSummary.make(
                days: try await port.dayFacts(for: reportingDates), reportingDates: reportingDates
            )
            XCTAssertEqual(summary.loggedDayCount, 1)
            XCTAssertEqual(summary.days.map(\.energy), [.notLogged, .notLogged, .complete(kilocalories: 0)])
            XCTAssertEqual(summary.averagePlainWaterMillilitres, 500)
            XCTAssertEqual(summary.completeWaterDayCount, 1)
        }
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

    init(facts: [FoodLogDayFacts] = [], error: (any Error)? = nil) {
        self.facts = facts
        self.error = error
    }

    func setFacts(_ facts: [FoodLogDayFacts]) { self.facts = facts }

    func dayFacts(for reportingDates: [String]) async throws -> [FoodLogDayFacts] {
        requests.append(reportingDates)
        if let error { throw error }
        return facts.filter { reportingDates.contains($0.reportingDate) }
    }
}
