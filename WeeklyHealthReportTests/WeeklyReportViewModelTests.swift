import Combine
import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
@MainActor
final class WeeklyReportViewModelTests: XCTestCase {
    func testSuccessfulRefreshPublishesEveryMetricAndMatchingSnapshot() async {
        let calendar = testCalendar()
        let refreshDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let provider = FakeHealthDataProvider()
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [refreshDate]
        )

        await viewModel.refresh()

        XCTAssertEqual(
            viewModel.period,
            ReportPeriod.make(
                selection: .lastSevenCompletedDays,
                now: refreshDate,
                calendar: calendar
            )
        )
        XCTAssertEqual(viewModel.lastRefreshed, refreshDate)
        let authorizationRequestCount = await provider.authorizationRequestCount()
        XCTAssertEqual(authorizationRequestCount, 1)
        assertAllReportMetricsAvailable(viewModel)
        assertSnapshotMatchesPublishedStates(viewModel)
    }

    func testRefreshPublishesLoadingForEveryMetricWhileQueryIsInFlight() async {
        let calendar = testCalendar()
        let refreshDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let provider = FakeHealthDataProvider(pauseFirstWeightFetch: true)
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [refreshDate]
        )

        let refresh = Task { await viewModel.refresh() }
        await provider.waitUntilFirstWeightFetchIsPaused()

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertEqual(viewModel.weightState, .loading)
        XCTAssertEqual(viewModel.bodyFatState, .loading)
        XCTAssertEqual(viewModel.waistState, .loading)
        XCTAssertEqual(viewModel.glucoseState, .loading)
        XCTAssertEqual(viewModel.vo2MaxState, .loading)
        XCTAssertEqual(viewModel.bloodOxygenState, .loading)
        XCTAssertEqual(viewModel.bloodPressureState, .loading)
        XCTAssertEqual(viewModel.restingHeartRateState, .loading)
        XCTAssertEqual(viewModel.hrvState, .loading)
        XCTAssertEqual(viewModel.watchCoverageState, .loading)
        XCTAssertEqual(viewModel.exerciseState, .loading)
        XCTAssertEqual(viewModel.activeEnergyState, .loading)
        XCTAssertEqual(viewModel.workoutState, .loading)
        XCTAssertEqual(viewModel.sleepState, .loading)
        XCTAssertEqual(viewModel.medicationState, .loading)
        assertSnapshotMatchesPublishedStates(viewModel)

        await provider.resumeFirstWeightFetch()
        await refresh.value
    }

    func testScreenshotSnapshotFailsClosedThroughoutRefreshThenUsesOneStableGeneration() async throws {
        let calendar = testCalendar()
        let refreshDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let provider = FakeHealthDataProvider(pauseFirstWeightFetch: true)
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [refreshDate]
        )

        let refresh = Task { await viewModel.refresh() }
        await provider.waitUntilFirstWeightFetchIsPaused()

        XCTAssertNil(viewModel.screenshotSnapshot(
            includesMedicationSection: true,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: false
        ))

        await provider.resumeFirstWeightFetch()
        await refresh.value

        let snapshot = try XCTUnwrap(viewModel.screenshotSnapshot(
            includesMedicationSection: true,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: false
        ))
        XCTAssertEqual(snapshot.period, viewModel.period)
        XCTAssertEqual(snapshot.weight, viewModel.weightState)
        XCTAssertEqual(snapshot.steps, viewModel.state)
        XCTAssertEqual(snapshot.includesMedicationSection, true)
        XCTAssertEqual(snapshot.showsMorningBloodPressureDetails, true)
        XCTAssertEqual(snapshot.showsEveningBloodPressureDetails, false)
    }

    func testScreenshotSnapshotFailsClosedBetweenPeriodSelectionAndRefresh() {
        let calendar = testCalendar()
        let refreshDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let viewModel = makeViewModel(
            provider: FakeHealthDataProvider(),
            calendar: calendar,
            dates: [refreshDate]
        )

        viewModel.selection = .previousWeek

        XCTAssertNil(viewModel.screenshotSnapshot(
            includesMedicationSection: false,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: false
        ))
    }

    func testMetricMutationPublishesViewModelChange() {
        let calendar = testCalendar()
        let refreshDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let viewModel = makeViewModel(
            provider: FakeHealthDataProvider(),
            calendar: calendar,
            dates: [refreshDate]
        )
        let published = expectation(description: "Metric state change is published")
        let observation = viewModel.objectWillChange.sink { published.fulfill() }

        viewModel.setMedicationAuthorizationFailure("Synthetic medication failure")

        wait(for: [published], timeout: 0.1)
        withExtendedLifetime(observation) {}
    }

    func testHealthUnavailablePublishesUnavailableForEveryMetric() async {
        let calendar = testCalendar()
        let refreshDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let provider = FakeHealthDataProvider(isHealthDataAvailable: false)
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [refreshDate]
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .healthUnavailable)
        XCTAssertEqual(viewModel.weightState, .healthUnavailable)
        XCTAssertEqual(viewModel.bodyFatState, .healthUnavailable)
        XCTAssertEqual(viewModel.waistState, .healthUnavailable)
        XCTAssertEqual(viewModel.glucoseState, .healthUnavailable)
        XCTAssertEqual(viewModel.vo2MaxState, .healthUnavailable)
        XCTAssertEqual(viewModel.bloodOxygenState, .healthUnavailable)
        XCTAssertEqual(viewModel.bloodPressureState, .healthUnavailable)
        XCTAssertEqual(viewModel.restingHeartRateState, .healthUnavailable)
        XCTAssertEqual(viewModel.hrvState, .healthUnavailable)
        XCTAssertEqual(viewModel.watchCoverageState, .healthUnavailable)
        XCTAssertEqual(viewModel.exerciseState, .healthUnavailable)
        XCTAssertEqual(viewModel.activeEnergyState, .healthUnavailable)
        XCTAssertEqual(viewModel.workoutState, .healthUnavailable)
        XCTAssertEqual(viewModel.sleepState, .healthUnavailable)
        XCTAssertEqual(viewModel.medicationState, .healthUnavailable)
        XCTAssertNil(viewModel.lastRefreshed)
        let authorizationRequestCount = await provider.authorizationRequestCount()
        XCTAssertEqual(authorizationRequestCount, 0)
        assertSnapshotMatchesPublishedStates(viewModel)
    }

    func testAuthorizationFailurePublishesFailureForEveryMetric() async {
        let calendar = testCalendar()
        let refreshDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let provider = FakeHealthDataProvider(authorizationError: .authorizationFailure)
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [refreshDate]
        )
        let message = FixtureError.authorizationFailure.localizedDescription

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .failed(message))
        XCTAssertEqual(viewModel.weightState, .failed(message))
        XCTAssertEqual(viewModel.bodyFatState, .failed(message))
        XCTAssertEqual(viewModel.waistState, .failed(message))
        XCTAssertEqual(viewModel.glucoseState, .failed(message))
        XCTAssertEqual(viewModel.vo2MaxState, .failed(message))
        XCTAssertEqual(viewModel.bloodOxygenState, .failed(message))
        XCTAssertEqual(viewModel.bloodPressureState, .failed(message))
        XCTAssertEqual(viewModel.restingHeartRateState, .failed(message))
        XCTAssertEqual(viewModel.hrvState, .failed(message))
        XCTAssertEqual(viewModel.watchCoverageState, .failed(message))
        XCTAssertEqual(viewModel.exerciseState, .failed(message))
        XCTAssertEqual(viewModel.activeEnergyState, .failed(message))
        XCTAssertEqual(viewModel.workoutState, .failed(message))
        XCTAssertEqual(viewModel.sleepState, .failed(message))
        XCTAssertEqual(viewModel.medicationState, .failed(message))
        XCTAssertNil(viewModel.lastRefreshed)
        assertSnapshotMatchesPublishedStates(viewModel)
    }

    func testIsolatedMetricFailureDoesNotContaminateOtherMetricStates() async {
        let calendar = testCalendar()
        let refreshDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let provider = FakeHealthDataProvider(glucoseError: .glucoseFailure)
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [refreshDate]
        )

        await viewModel.refresh()

        XCTAssertEqual(
            viewModel.glucoseState,
            .failed(FixtureError.glucoseFailure.localizedDescription)
        )
        assertAllReportMetricsAvailable(viewModel, excludingGlucose: true)
        XCTAssertNil(viewModel.reportSnapshot.glucose)
        XCTAssertEqual(viewModel.lastRefreshed, refreshDate)
        assertSnapshotMatchesPublishedStates(viewModel)
    }

    func testOverlappingRefreshRejectsCompletionFromOlderGeneration() async throws {
        let calendar = testCalendar()
        let olderDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let newerDate = date(2026, 9, 2, hour: 12, calendar: calendar)
        let olderWeight = WeightMeasurement(
            id: fixtureID,
            date: olderDate.addingTimeInterval(-3_600),
            kilograms: 91
        )
        let newerWeight = WeightMeasurement(
            id: fixtureID,
            date: newerDate.addingTimeInterval(-3_600),
            kilograms: 72
        )
        let provider = FakeHealthDataProvider(
            weightResponses: [[olderWeight], [newerWeight]],
            pauseFirstWeightFetch: true
        )
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [olderDate, olderDate, newerDate]
        )

        let olderRefresh = Task { await viewModel.refresh() }
        await provider.waitUntilFirstWeightFetchIsPaused()

        let newerRefresh = Task { await viewModel.refresh() }
        await newerRefresh.value
        XCTAssertEqual(
            try XCTUnwrap(viewModel.weightState.value).latest.kilograms,
            72,
            accuracy: 0.000_001
        )
        XCTAssertEqual(viewModel.lastRefreshed, newerDate)

        await provider.resumeFirstWeightFetch()
        await olderRefresh.value

        XCTAssertEqual(
            try XCTUnwrap(viewModel.weightState.value).latest.kilograms,
            72,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            viewModel.period,
            ReportPeriod.make(
                selection: .lastSevenCompletedDays,
                now: newerDate,
                calendar: calendar
            )
        )
        XCTAssertEqual(viewModel.lastRefreshed, newerDate)
        assertAllReportMetricsAvailable(viewModel)
        assertSnapshotMatchesPublishedStates(viewModel)
    }

    func testMedicationOnlyRefreshRejectsOlderFullRefreshMedicationCompletion() async throws {
        let calendar = testCalendar()
        let refreshDate = date(2026, 9, 2, hour: 12, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: refreshDate,
            calendar: calendar
        )
        let provider = FakeHealthDataProvider(
            medicationResponses: [
                [medicationRecord(name: "Older Full Refresh", in: period)],
                [medicationRecord(name: "Newer Medication Refresh", in: period)]
            ],
            pauseFirstMedicationFetch: true
        )
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [refreshDate]
        )

        let olderFullRefresh = Task { await viewModel.refresh() }
        await provider.waitUntilFirstMedicationFetchIsPaused()

        await viewModel.refreshMedications()
        XCTAssertEqual(
            try XCTUnwrap(viewModel.medicationState.value).groups.first?.medicationName,
            "Newer Medication Refresh"
        )

        await provider.resumeFirstMedicationFetch()
        await olderFullRefresh.value

        XCTAssertEqual(
            try XCTUnwrap(viewModel.medicationState.value).groups.first?.medicationName,
            "Newer Medication Refresh"
        )
    }

    func testFullRefreshRejectsOlderMedicationOnlyRefreshCompletion() async throws {
        let calendar = testCalendar()
        let olderDate = date(2026, 9, 1, hour: 12, calendar: calendar)
        let newerDate = date(2026, 9, 2, hour: 12, calendar: calendar)
        let olderPeriod = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: olderDate,
            calendar: calendar
        )
        let newerPeriod = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: newerDate,
            calendar: calendar
        )
        let provider = FakeHealthDataProvider(
            medicationResponses: [
                [medicationRecord(name: "Older Medication Refresh", in: olderPeriod)],
                [medicationRecord(name: "Newer Full Refresh", in: newerPeriod)]
            ],
            pauseFirstMedicationFetch: true
        )
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [olderDate, newerDate]
        )

        let olderMedicationRefresh = Task { await viewModel.refreshMedications() }
        await provider.waitUntilFirstMedicationFetchIsPaused()

        await viewModel.refresh()
        XCTAssertEqual(
            try XCTUnwrap(viewModel.medicationState.value).groups.first?.medicationName,
            "Newer Full Refresh"
        )

        await provider.resumeFirstMedicationFetch()
        await olderMedicationRefresh.value

        XCTAssertEqual(viewModel.period, newerPeriod)
        XCTAssertEqual(
            try XCTUnwrap(viewModel.medicationState.value).groups.first?.medicationName,
            "Newer Full Refresh"
        )
    }

    func testCurrentWeekWithNoCompletedDaysKeepsContextAndEndsPeriodMetrics() async {
        let calendar = testCalendar()
        let monday = date(2026, 8, 31, hour: 12, calendar: calendar)
        let provider = FakeHealthDataProvider()
        let viewModel = makeViewModel(
            provider: provider,
            calendar: calendar,
            dates: [monday]
        )
        viewModel.selection = .currentWeek

        await viewModel.refresh()

        XCTAssertTrue(viewModel.period.completedDays.isEmpty)
        XCTAssertEqual(viewModel.state, .noCompletedDays)
        assertAvailable(viewModel.weightState)
        assertAvailable(viewModel.bodyFatState)
        assertAvailable(viewModel.waistState)
        assertAvailable(viewModel.vo2MaxState)
        assertAvailable(viewModel.bloodPressureState)
        XCTAssertEqual(viewModel.glucoseState, .noDataOrAccess)
        XCTAssertEqual(viewModel.bloodOxygenState, .noDataOrAccess)
        XCTAssertEqual(viewModel.restingHeartRateState, .noDataOrAccess)
        XCTAssertEqual(viewModel.hrvState, .noDataOrAccess)
        XCTAssertEqual(viewModel.watchCoverageState, .noDataOrAccess)
        XCTAssertEqual(viewModel.exerciseState, .noDataOrAccess)
        XCTAssertEqual(viewModel.activeEnergyState, .noDataOrAccess)
        XCTAssertEqual(viewModel.workoutState, .noDataOrAccess)
        XCTAssertEqual(viewModel.sleepState, .noDataOrAccess)
        XCTAssertEqual(viewModel.medicationState, .noDataOrAccess)
        XCTAssertEqual(viewModel.lastRefreshed, monday)
        assertSnapshotMatchesPublishedStates(viewModel)
    }

    private func makeViewModel(
        provider: FakeHealthDataProvider,
        calendar: Calendar,
        dates: [Date]
    ) -> WeeklyReportViewModel {
        let clock = FixtureClock(dates: dates)
        return WeeklyReportViewModel(
            healthData: provider,
            calendar: calendar,
            now: clock.now
        )
    }

    private func medicationRecord(
        name: String,
        in period: ReportPeriod
    ) -> MedicationDoseRecord {
        MedicationDoseRecord(
            id: UUID(),
            medicationKey: name,
            medicationName: name,
            date: period.completedDays[0].start.addingTimeInterval(3_600),
            quantity: 1,
            unitLabel: "dose"
        )
    }

    private func assertAllReportMetricsAvailable(
        _ viewModel: WeeklyReportViewModel,
        excludingGlucose: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .loaded = viewModel.state else {
            return XCTFail("Expected loaded steps, got \(viewModel.state)", file: file, line: line)
        }
        assertAvailable(viewModel.weightState, file: file, line: line)
        assertAvailable(viewModel.bodyFatState, file: file, line: line)
        assertAvailable(viewModel.waistState, file: file, line: line)
        if !excludingGlucose {
            assertAvailable(viewModel.glucoseState, file: file, line: line)
        }
        assertAvailable(viewModel.vo2MaxState, file: file, line: line)
        assertAvailable(viewModel.bloodOxygenState, file: file, line: line)
        assertAvailable(viewModel.bloodPressureState, file: file, line: line)
        assertAvailable(viewModel.restingHeartRateState, file: file, line: line)
        assertAvailable(viewModel.hrvState, file: file, line: line)
        assertAvailable(viewModel.watchCoverageState, file: file, line: line)
        assertAvailable(viewModel.exerciseState, file: file, line: line)
        assertAvailable(viewModel.activeEnergyState, file: file, line: line)
        assertAvailable(viewModel.workoutState, file: file, line: line)
        assertAvailable(viewModel.sleepState, file: file, line: line)
        assertAvailable(viewModel.medicationState, file: file, line: line)
    }

    private func assertAvailable<Value: Equatable>(
        _ state: MetricState<Value>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .available = state else {
            return XCTFail("Expected available state, got \(state)", file: file, line: line)
        }
    }

    private func assertSnapshotMatchesPublishedStates(
        _ viewModel: WeeklyReportViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let snapshot = viewModel.reportSnapshot
        let steps: StepSummary?
        if case .loaded(let summary) = viewModel.state {
            steps = summary
        } else {
            steps = nil
        }

        XCTAssertEqual(snapshot.period, viewModel.period, file: file, line: line)
        XCTAssertEqual(snapshot.weight, viewModel.weightState.value, file: file, line: line)
        XCTAssertEqual(snapshot.bodyFat, viewModel.bodyFatState.value, file: file, line: line)
        XCTAssertEqual(snapshot.waist, viewModel.waistState.value, file: file, line: line)
        XCTAssertEqual(snapshot.glucose, viewModel.glucoseState.value, file: file, line: line)
        XCTAssertEqual(snapshot.vo2Max, viewModel.vo2MaxState.value, file: file, line: line)
        XCTAssertEqual(
            snapshot.bloodOxygen,
            viewModel.bloodOxygenState.value,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.bloodPressure,
            viewModel.bloodPressureState.value,
            file: file,
            line: line
        )
        XCTAssertEqual(snapshot.steps, steps, file: file, line: line)
        XCTAssertEqual(
            snapshot.restingHeartRate,
            viewModel.restingHeartRateState.value,
            file: file,
            line: line
        )
        XCTAssertEqual(snapshot.hrv, viewModel.hrvState.value, file: file, line: line)
        XCTAssertEqual(
            snapshot.watchCoverage,
            viewModel.watchCoverageState.value,
            file: file,
            line: line
        )
        XCTAssertEqual(snapshot.sleep, viewModel.sleepState.value, file: file, line: line)
        XCTAssertEqual(
            snapshot.activeEnergyKilocalories,
            viewModel.activeEnergyState.value,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.exerciseMinutes,
            viewModel.exerciseState.value,
            file: file,
            line: line
        )
        XCTAssertEqual(snapshot.workouts, viewModel.workoutState.value, file: file, line: line)
        XCTAssertEqual(
            snapshot.medications,
            viewModel.medicationState.value,
            file: file,
            line: line
        )
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
