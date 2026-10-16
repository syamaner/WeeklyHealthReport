import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
final class StepSummaryTests: XCTestCase {
    func testAverageUsesOnlyDaysWithVisibleTotalsAsDenominator() {
        let totals = [
            daily(offset: 0, steps: 100),
            daily(offset: 1, steps: nil),
            daily(offset: 2, steps: 200)
        ]

        let summary = StepSummary.aggregate(totals)

        XCTAssertEqual(summary?.totalSteps, 300)
        XCTAssertEqual(summary?.averageDailySteps, 150)
        XCTAssertEqual(summary?.reportingDayCount, 3)
        XCTAssertEqual(summary?.daysWithVisibleData, 2)
    }

    func testAllMissingDaysReturnNoSummaryInsteadOfZero() {
        let totals = [daily(offset: 0, steps: nil), daily(offset: 1, steps: nil)]

        XCTAssertNil(StepSummary.aggregate(totals))
    }

    func testNoCompletedDaysReturnNoSummary() {
        XCTAssertNil(StepSummary.aggregate([]))
    }

    func testSevenOfSevenDaysUseAllVisibleTotals() {
        let totals = (0 ..< 7).map { daily(offset: $0, steps: Double(($0 + 1) * 1_000)) }

        let summary = StepSummary.aggregate(totals)

        XCTAssertEqual(summary?.totalSteps, 28_000)
        XCTAssertEqual(summary?.averageDailySteps, 4_000)
        XCTAssertEqual(summary?.daysWithVisibleData, 7)
        XCTAssertEqual(summary?.reportingDayCount, 7)
    }

    func testVisibleZeroIsSampledDataRatherThanMissing() {
        let totals = [daily(offset: 0, steps: 0), daily(offset: 1, steps: nil)]

        let summary = StepSummary.aggregate(totals)

        XCTAssertEqual(summary?.totalSteps, 0)
        XCTAssertEqual(summary?.averageDailySteps, 0)
        XCTAssertEqual(summary?.daysWithVisibleData, 1)
        XCTAssertEqual(summary?.reportingDayCount, 2)
    }

    private func daily(offset: Int, steps: Double?) -> DailyStepTotal {
        let start = Date(timeIntervalSinceReferenceDate: Double(offset * 86_400))
        let end = start.addingTimeInterval(86_400)
        return DailyStepTotal(
            day: DateInterval(start: start, end: end),
            steps: steps,
            sourceNames: []
        )
    }
}

// Contract tests for docs/health-steps-trend-v1.md. All values are synthetic.
final class StepTrendSummaryTests: XCTestCase {
    func testCoverageTableForOneToSevenCompletedDays() {
        let required = (1 ... 7).map { StepTrendPolicy.requiredSampledDays(completedDayCount: $0) }
        XCTAssertEqual(required, [nil, nil, 3, 3, 4, 5, 5])
        XCTAssertEqual(StepTrendPolicy.identifier, "steps_trend_previous_equivalent_v1")
    }

    func testFullWeeksGiveUnroundedPercentage() throws {
        let trend = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals(Array(repeating: 10_600, count: 7)),
            previous: totals(Array(repeating: 10_000, count: 7)),
            completedDayCount: 7
        ))

        XCTAssertEqual(trend.current.averageDailySteps, 10_600)
        XCTAssertEqual(trend.previous?.averageDailySteps, 10_000)
        XCTAssertEqual(trend.requiredSampledDays, 5)
        XCTAssertEqual(try XCTUnwrap(trend.change), 6, accuracy: 1e-9)
    }

    func testMissingDaysAreLeftOutRatherThanCountedAsZero() throws {
        // Five sampled days on each side; the missing days do not pull either average down.
        let trend = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals([8_000, nil, 8_000, 8_000, nil, 8_000, 8_000]),
            previous: totals([10_000, 10_000, 10_000, 10_000, 10_000, nil, nil]),
            completedDayCount: 7
        ))

        XCTAssertEqual(trend.current.daysWithVisibleData, 5)
        XCTAssertEqual(trend.previous?.daysWithVisibleData, 5)
        XCTAssertEqual(trend.previousDailyTotals.count, 7)
        XCTAssertEqual(try XCTUnwrap(trend.change), -20, accuracy: 1e-9)
    }

    func testVisibleZeroStepDayIsSampledAndLowersTheAverage() throws {
        let trend = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals([7_000, 7_000, 7_000, 7_000, 7_000, 7_000, 0]),
            previous: totals(Array(repeating: 6_000, count: 7)),
            completedDayCount: 7
        ))

        XCTAssertEqual(trend.current.daysWithVisibleData, 7)
        XCTAssertEqual(trend.current.averageDailySteps, 6_000)
        XCTAssertEqual(trend.change, 0)
    }

    func testEitherSideBelowMinimumGivesNoTrend() throws {
        let fourOfSeven: [Double?] = [5_000, 5_000, 5_000, 5_000, nil, nil, nil]
        let full = Array(repeating: Double?.some(5_000), count: 7)

        let currentShort = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals(fourOfSeven), previous: totals(full), completedDayCount: 7
        ))
        let previousShort = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals(full), previous: totals(fourOfSeven), completedDayCount: 7
        ))
        let previousEmpty = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals(full), previous: totals(Array(repeating: nil, count: 7)), completedDayCount: 7
        ))

        XCTAssertNil(currentShort.change)
        XCTAssertNil(previousShort.change)
        XCTAssertNil(previousEmpty.change)
        XCTAssertNil(previousEmpty.previous)
    }

    func testThreeCompletedDaysNeedEveryDayOnEachSide() throws {
        let complete = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals([4_000, 4_000, 4_000]),
            previous: totals([2_000, 2_000, 2_000]),
            completedDayCount: 3
        ))
        let oneMissing = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals([4_000, nil, 4_000]),
            previous: totals([2_000, 2_000, 2_000]),
            completedDayCount: 3
        ))

        XCTAssertEqual(complete.requiredSampledDays, 3)
        XCTAssertEqual(try XCTUnwrap(complete.change), 100, accuracy: 1e-9)
        XCTAssertNil(oneMissing.change)
    }

    func testTwoCompletedDaysNeverGiveATrend() throws {
        let trend = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals([4_000, 4_000]),
            previous: totals([2_000, 2_000]),
            completedDayCount: 2
        ))

        XCTAssertNil(trend.requiredSampledDays)
        XCTAssertNil(trend.change)
    }

    func testPreviousAverageOfZeroGivesNoTrend() throws {
        let trend = try XCTUnwrap(StepTrendSummary.calculate(
            current: totals(Array(repeating: 3_000, count: 7)),
            previous: totals(Array(repeating: 0, count: 7)),
            completedDayCount: 7
        ))

        XCTAssertEqual(trend.previous?.averageDailySteps, 0)
        XCTAssertNil(trend.change)
    }

    func testNoCurrentDataGivesNoSummary() {
        XCTAssertNil(StepTrendSummary.calculate(
            current: totals(Array(repeating: nil, count: 7)),
            previous: totals(Array(repeating: 3_000, count: 7)),
            completedDayCount: 7
        ))
    }

    func testSignedPercentRoundsHalfAwayFromZeroAndNeverShowsMinusZero() {
        let gb = Locale(identifier: "en_GB")
        func text(_ value: Double) -> String {
            HealthReportFormatter.signedPercent(value, comparison: "previous 7d", locale: gb)
        }

        XCTAssertEqual(text(0.5), "+1% vs previous 7d")
        XCTAssertEqual(text(-0.5), "-1% vs previous 7d")
        XCTAssertEqual(text(2.5), "+3% vs previous 7d")
        XCTAssertEqual(text(-2.5), "-3% vs previous 7d")
        XCTAssertEqual(text(0.49), "0% vs previous 7d")
        XCTAssertEqual(text(-0.49), "0% vs previous 7d")
        XCTAssertEqual(text(-0.0), "0% vs previous 7d")
        XCTAssertEqual(text(0), "0% vs previous 7d")
        XCTAssertEqual(text(6.000_000_000_001), "+6% vs previous 7d")
        XCTAssertEqual(text(-3.4), "-3% vs previous 7d")
        XCTAssertEqual(text(1_250.4), "+1,250% vs previous 7d")
    }

    func testThisWeekComparesWithTheImmediatelyPrecedingDays() throws {
        let calendar = londonCalendar()
        // Wednesday 16 Sep 2026: 2 completed days; Thursday: 3; Sunday: 6.
        for (day, expectedCount) in [(16, 2), (17, 3), (20, 6)] {
            let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12)))
            let current = ReportPeriod.make(selection: .currentWeek, now: now, calendar: calendar)
            let previous = try XCTUnwrap(current.precedingEquivalent(calendar: calendar))

            XCTAssertEqual(current.completedDays.count, expectedCount)
            XCTAssertEqual(previous.completedDays.count, expectedCount)
            XCTAssertEqual(previous.interval.end, current.interval.start)
            let expectedRequired: Int? = expectedCount < 3 ? nil : expectedCount == 3 ? 3 : 5
            XCTAssertEqual(
                StepTrendPolicy.requiredSampledDays(completedDayCount: expectedCount),
                expectedRequired
            )
        }
    }

    func testDaylightSavingWeeksStillCountSevenCalendarDays() throws {
        let calendar = londonCalendar()
        // Spring: 29 Mar 2026 has 23 hours. Autumn: 25 Oct 2026 has 25 hours.
        for (month, day, hours) in [(3, 31, 23.0), (10, 27, 25.0)] {
            let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
            let current = ReportPeriod.make(selection: .lastSevenCompletedDays, now: now, calendar: calendar)
            let previous = try XCTUnwrap(current.precedingEquivalent(calendar: calendar))

            XCTAssertEqual(current.completedDays.count, 7)
            XCTAssertEqual(previous.completedDays.count, 7)
            XCTAssertTrue(current.completedDays.contains { $0.duration == hours * 3_600 })
            XCTAssertEqual(previous.interval.end, current.interval.start)
        }
    }

    private func totals(_ values: [Double?]) -> [DailyStepTotal] {
        values.enumerated().map { offset, steps in
            let start = Date(timeIntervalSinceReferenceDate: Double(offset * 86_400))
            return DailyStepTotal(
                day: DateInterval(start: start, end: start.addingTimeInterval(86_400)),
                steps: steps,
                sourceNames: []
            )
        }
    }

    private func londonCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        return calendar
    }
}
