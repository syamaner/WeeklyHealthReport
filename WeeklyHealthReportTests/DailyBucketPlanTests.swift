import XCTest
@testable import WeeklyHealthReport

// Contract tests for docs/healthkit-day-bucketing-v1.md section 6. All values
// are synthetic. The report calendar is Europe/London; the simulated HealthKit
// calendar is a different zone (or a fixed 24 hour step), which is the case
// production cannot observe directly.
final class DailyBucketPlanTests: XCTestCase {
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400

    // MARK: 1. Plan, autumn DST

    func testPlanForAutumnChangeWeekHasOneTwentyFiveHourDay() throws {
        let london = calendar("Europe/London")
        // Wednesday 28 October 2026: the previous week is Monday 19 to Monday
        // 26 October and contains Sunday 25 October (clocks go back).
        let period = ReportPeriod.make(
            selection: .previousWeek,
            now: date(2026, 10, 28, 12, london),
            calendar: london
        )
        let plan = try XCTUnwrap(DailyBucketPlan(period: period, calendar: london))

        XCTAssertEqual(plan.days, period.completedDays)
        XCTAssertEqual(plan.days.count, 7)
        XCTAssertEqual(plan.anchorDate, date(2026, 10, 19, 0, london))
        XCTAssertEqual(plan.anchorDate, period.interval.start)
        XCTAssertEqual(plan.intervalComponents, DateComponents(day: 1))
        XCTAssertEqual(plan.queryInterval, period.interval)
        XCTAssertEqual(plan.days.map(\.duration), [day, day, day, day, day, day, day + hour])
        XCTAssertEqual(plan.days[6].start, date(2026, 10, 25, 0, london))
        assertConsecutive(plan.days)
    }

    // MARK: 2. Plan, spring DST

    func testPlanForSpringChangeWeekHasOneTwentyThreeHourDay() throws {
        let london = calendar("Europe/London")
        // Wednesday 1 April 2026: previous week Monday 23 to Monday 30 March,
        // containing Sunday 29 March (clocks go forward).
        let period = ReportPeriod.make(
            selection: .previousWeek,
            now: date(2026, 4, 1, 12, london),
            calendar: london
        )
        let plan = try XCTUnwrap(DailyBucketPlan(period: period, calendar: london))

        XCTAssertEqual(plan.days.count, 7)
        XCTAssertEqual(plan.anchorDate, date(2026, 3, 23, 0, london))
        XCTAssertEqual(plan.days.map(\.duration), [day, day, day, day, day, day, day - hour])
        assertConsecutive(plan.days)
    }

    // MARK: 3. Previous equivalent across DST, and the steps trend

    func testStepsTrendReadsAcrossTheChangeAlignSevenPlusSevenDays() async throws {
        let london = calendar("Europe/London")
        // Monday 2 November 2026: current 26 October to 1 November (GMT),
        // previous 19 to 25 October (BST, ending with the 25 hour day).
        let current = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 11, 2, 9, london),
            calendar: london
        )
        let previous = try XCTUnwrap(current.precedingEquivalent(calendar: london))
        let currentPlan = try XCTUnwrap(DailyBucketPlan(period: current, calendar: london))
        let previousPlan = try XCTUnwrap(DailyBucketPlan(period: previous, calendar: london))
        XCTAssertEqual(previousPlan.days.last?.duration, day + hour)
        XCTAssertEqual(previousPlan.days.last?.end, currentPlan.anchorDate)
        assertConsecutive(previousPlan.days + currentPlan.days)

        let currentRead = try await readSteps(
            plan: currentPlan,
            bucketStarts: calendarDayStarts(from: currentPlan.anchorDate, count: 7, in: london)
        )
        let previousRead = try await readSteps(
            plan: previousPlan,
            bucketStarts: calendarDayStarts(from: previousPlan.anchorDate, count: 7, in: london)
        )
        XCTAssertEqual(currentRead.outcome, .aligned)
        XCTAssertEqual(previousRead.outcome, .aligned)
        XCTAssertEqual(currentRead.values.compactMap { $0 }.count, 7)
        XCTAssertEqual(previousRead.values.compactMap { $0 }.count, 7)

        let trend = try XCTUnwrap(StepTrendSummary.calculate(
            current: stepTotals(current.completedDays, currentRead.values),
            previous: stepTotals(previous.completedDays, previousRead.values),
            completedDayCount: 7
        ))
        XCTAssertEqual(trend.current.daysWithVisibleData, 7)
        XCTAssertEqual(trend.previous?.daysWithVisibleData, 7)
        XCTAssertEqual(trend.change, 0)
    }

    // MARK: 4. Alignment, matching buckets

    func testBucketsFromTheSameCalendarMatchEveryDayWithoutFallback() throws {
        let london = calendar("Europe/London")
        let period = ReportPeriod.make(
            selection: .previousWeek,
            now: date(2026, 10, 28, 12, london),
            calendar: london
        )
        let match = DailyBucketAlignment.match(
            bucketStarts: calendarDayStarts(from: period.interval.start, count: 7, in: london),
            days: period.completedDays
        )
        XCTAssertFalse(match.requiresFallback)
        XCTAssertEqual(match.mismatchedBucketStarts, [])
        XCTAssertEqual(match.values.compactMap { $0 }.count, 7)
    }

    // MARK: 5. Alignment, mismatched zone (fixed 24 hour steps)

    func testTwentyFourHourBucketsAcrossTheChangeMismatchAndRequestFallback() async throws {
        let london = calendar("Europe/London")
        // Thursday 29 October 2026: last seven days 22 to 28 October; the
        // change is early on Sunday 25 October.
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 10, 29, 9, london),
            calendar: london
        )
        let plan = try XCTUnwrap(DailyBucketPlan(period: period, calendar: london))
        let starts = (0..<7).map { plan.anchorDate.addingTimeInterval(Double($0) * day) }
        let buckets = starts.enumerated().map { DailyBucket(start: $1, value: Double($0)) }

        let match = DailyBucketAlignment.match(buckets, days: plan.days)
        // 22 to 25 October start at London midnight; the 24 hour step then
        // lands at 23:00 GMT on 25, 26 and 27 October.
        XCTAssertEqual(match.values, [0, 1, 2, 3, nil, nil, nil])
        XCTAssertEqual(match.mismatchedBucketStarts, Array(starts[4...]))
        XCTAssertEqual(match.mismatchedBucketStarts.first, date(2026, 10, 25, 23, london))
        XCTAssertTrue(match.requiresFallback)

        var reread: [DateInterval] = []
        let result = try await DailyBucketReader.read(
            days: plan.days,
            plan: plan,
            collection: { _ in buckets },
            perDay: { interval -> Double? in
                reread.append(interval)
                return 100
            }
        )
        XCTAssertEqual(reread, plan.days)
        XCTAssertEqual(result.values, Array(repeating: 100, count: 7))
        XCTAssertEqual(
            result.outcome,
            .perDayFallback(reason: .bucketMismatch, mismatchedBucketCount: 3)
        )
    }

    // MARK: 6. Alignment, time-zone change

    func testBucketsFromAnotherZoneAllMismatchAndRequestFallback() async throws {
        let london = calendar("Europe/London")
        let tokyo = calendar("Asia/Tokyo")
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 9, 10, 12, london),
            calendar: london
        )
        let tokyoStarts = calendarDayStarts(
            from: tokyo.startOfDay(for: period.interval.start),
            count: 8,
            in: tokyo
        )
        let match = DailyBucketAlignment.match(bucketStarts: tokyoStarts, days: period.completedDays)
        XCTAssertEqual(match.mismatchedBucketStarts.count, tokyoStarts.count)
        XCTAssertTrue(match.values.allSatisfy { $0 == nil })
        XCTAssertTrue(match.requiresFallback)

        // A period built in London is not a plan in Tokyo's calendar either:
        // the adapter skips the collection and reads each London day exactly.
        XCTAssertNil(DailyBucketPlan(period: period, calendar: tokyo))
        var collectionCalls = 0
        var reread: [DateInterval] = []
        let result = try await DailyBucketReader.read(
            days: period.completedDays,
            plan: DailyBucketPlan(period: period, calendar: tokyo),
            collection: { _ -> [DailyBucket<Double>] in
                collectionCalls += 1
                return []
            },
            perDay: { interval -> Double? in
                reread.append(interval)
                return 1
            }
        )
        XCTAssertEqual(collectionCalls, 0)
        XCTAssertEqual(reread, period.completedDays)
        XCTAssertEqual(
            result.outcome,
            .perDayFallback(reason: .planRejected, mismatchedBucketCount: 0)
        )
    }

    // MARK: 7. Midnight boundary

    func testRefreshAtMidnightAndJustBeforeKeepsTodayOmittedAndEndExclusive() throws {
        let london = calendar("Europe/London")
        for now in [date(2026, 10, 26, 0, london), date(2026, 10, 26, 0, london) - 1] {
            let period = ReportPeriod.make(
                selection: .lastSevenCompletedDays,
                now: now,
                calendar: london
            )
            let plan = try XCTUnwrap(DailyBucketPlan(period: period, calendar: london))
            let today = london.startOfDay(for: now)
            XCTAssertEqual(plan.queryInterval.end, today)
            XCTAssertEqual(plan.days.last?.end, today)
            XCTAssertFalse(plan.days.contains { $0.start == today }, "today is omitted")
            XCTAssertTrue(plan.days.allSatisfy { $0.end <= today })
            XCTAssertEqual(plan.days.count, 7)
            assertConsecutive(plan.days)
        }
    }

    // MARK: 8. No samples

    func testDayWithoutBucketStaysMissingAndIsNotAMismatch() async throws {
        let london = calendar("Europe/London")
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 10, 29, 9, london),
            calendar: london
        )
        let plan = try XCTUnwrap(DailyBucketPlan(period: period, calendar: london))
        let starts = calendarDayStarts(from: plan.anchorDate, count: 7, in: london)
        // Days 2 and 5 have no samples, so HealthKit returns no statistic.
        let buckets = starts.enumerated()
            .filter { ![2, 5].contains($0.offset) }
            .map { DailyBucket(start: $0.element, value: 1_000.0) }
        var perDayCalls = 0
        let result = try await DailyBucketReader.read(
            days: plan.days,
            plan: plan,
            collection: { _ in buckets },
            perDay: { _ -> Double? in
                perDayCalls += 1
                return 0
            }
        )
        XCTAssertEqual(result.outcome, .aligned)
        XCTAssertEqual(perDayCalls, 0)
        XCTAssertNil(result.values[2])
        XCTAssertNil(result.values[5])
        let summary = try XCTUnwrap(StepSummary.aggregate(stepTotals(plan.days, result.values)))
        XCTAssertEqual(summary.daysWithVisibleData, 5)
        XCTAssertEqual(summary.reportingDayCount, 7)
        XCTAssertEqual(summary.averageDailySteps, 1_000)
    }

    // MARK: 9. Fake adapter contract

    func testMisalignedCollectionsRecoverPerDayValuesForEveryDailyMetric() async throws {
        let london = calendar("Europe/London")
        let current = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 10, 29, 9, london),
            calendar: london
        )
        let previous = try XCTUnwrap(current.precedingEquivalent(calendar: london))
        let store = MisalignedDailyStore(calendar: london, hour: hour)

        // Steps and the steps trend.
        let stepsCurrent = try await store.read(current) { 4_000 + $0 * 100 }
        let stepsPrevious = try await store.read(previous) { 3_000 + $0 * 100 }
        XCTAssertEqual(
            StepSummary.aggregate(stepTotals(current.completedDays, stepsCurrent.values)),
            StepSummary.aggregate(stepTotals(current.completedDays, store.truth(current) { 4_000 + $0 * 100 }))
        )
        XCTAssertEqual(
            StepTrendSummary.calculate(
                current: stepTotals(current.completedDays, stepsCurrent.values),
                previous: stepTotals(previous.completedDays, stepsPrevious.values),
                completedDayCount: 7
            ),
            StepTrendSummary.calculate(
                current: stepTotals(current.completedDays, store.truth(current) { 4_000 + $0 * 100 }),
                previous: stepTotals(previous.completedDays, store.truth(previous) { 3_000 + $0 * 100 }),
                completedDayCount: 7
            )
        )

        // Blood glucose.
        let glucose = try await store.read(current) { 5 + $0 / 10 }
        XCTAssertEqual(
            GlucoseSummary.aggregate(glucoseValues(current.completedDays, glucose.values)),
            GlucoseSummary.aggregate(glucoseValues(current.completedDays, store.truth(current) { 5 + $0 / 10 }))
        )

        // Resting heart rate and HRV with their trends.
        for (base, previousBase) in [(60.0, 58.0), (42.0, 40.0)] {
            let currentRead = try await store.read(current) { base + $0 }
            let previousRead = try await store.read(previous) { previousBase + $0 }
            XCTAssertEqual(
                HeartMetricTrendSummary.calculate(
                    currentValues: heartValues(current.completedDays, currentRead.values),
                    previousValues: heartValues(previous.completedDays, previousRead.values)
                ),
                HeartMetricTrendSummary.calculate(
                    currentValues: heartValues(current.completedDays, store.truth(current) { base + $0 }),
                    previousValues: heartValues(previous.completedDays, store.truth(previous) { previousBase + $0 })
                )
            )
            XCTAssertEqual(
                currentRead.outcome,
                .perDayFallback(reason: .bucketMismatch, mismatchedBucketCount: 3)
            )
        }
        XCTAssertEqual(stepsCurrent.values, store.truth(current) { 4_000 + $0 * 100 })
        XCTAssertEqual(stepsPrevious.outcome, .aligned, "15 to 21 October has no change")
    }

    @MainActor
    func testHealthReportPassesItsCalendarToEveryDailyCollection() async {
        let london = calendar("Europe/London")
        let refreshDate = date(2026, 10, 29, 9, london)
        let period = ReportPeriod.make(selection: .lastSevenCompletedDays, now: refreshDate, calendar: london)
        let foreign = DailyBucketReadRecord(
            metric: "Steps",
            interval: DateInterval(start: refreshDate, duration: 60),
            timeZoneIdentifier: "Asia/Tokyo",
            dayCount: 1,
            outcome: .aligned
        )
        let fallback = DailyBucketReadRecord(
            metric: "HRV",
            interval: period.interval,
            timeZoneIdentifier: "Europe/London",
            dayCount: 7,
            outcome: .perDayFallback(reason: .bucketMismatch, mismatchedBucketCount: 3)
        )
        let provider = FakeHealthDataProvider(dailyBucketReadRecords: [fallback, foreign])
        let viewModel = WeeklyReportViewModel(
            healthData: provider,
            calendar: london,
            now: { refreshDate }
        )

        await viewModel.refresh()

        let zones = provider.dailyCollectionTimeZones()
        // Steps, steps trend, glucose, resting heart rate x2 and HRV x2.
        XCTAssertEqual(zones.count, 7)
        XCTAssertEqual(Set(zones), ["Europe/London"])
        XCTAssertEqual(viewModel.dailyBucketReads, [fallback])
        XCTAssertEqual(
            DailyBucketDiagnostics.lines(viewModel.dailyBucketReads).map(\.title).prefix(2),
            ["Policy", "Per-day fallbacks"]
        )
        XCTAssertEqual(
            DailyBucketDiagnostics.lines(viewModel.dailyBucketReads)[1].detail,
            "1 of 1 reads"
        )
        XCTAssertEqual(
            DailyBucketDiagnostics.lines(viewModel.dailyBucketReads).last?.detail,
            "Per-day fallback: 3 buckets did not start at a report day; 7 days re-read"
        )
    }

    func testDiagnosticsReportNoFallbackInTheAlignedCase() {
        let lines = DailyBucketDiagnostics.lines([
            DailyBucketReadRecord(
                metric: "Steps",
                interval: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 7 * day),
                timeZoneIdentifier: "Europe/London",
                dayCount: 7,
                outcome: .aligned
            )
        ])
        XCTAssertEqual(lines[0], .init(title: "Policy", detail: "healthkit_day_buckets_injected_calendar_v1"))
        XCTAssertEqual(lines[1], .init(title: "Per-day fallbacks", detail: "None"))
        XCTAssertEqual(lines[2].detail, "Collection aligned, 7 days")
        XCTAssertEqual(
            DailyBucketDiagnostics.lines([]).last,
            .init(title: "Daily reads", detail: "Not read yet")
        )
    }

    func testReadLogKeepsTheLatestOutcomePerMetricAndInterval() {
        let log = DailyBucketReadLog(capacity: 2)
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), duration: day)
        func record(_ metric: String, _ outcome: DailyBucketReadOutcome) -> DailyBucketReadRecord {
            DailyBucketReadRecord(
                metric: metric,
                interval: interval,
                timeZoneIdentifier: "Europe/London",
                dayCount: 1,
                outcome: outcome
            )
        }
        log.record(record("Steps", .aligned))
        log.record(record("Steps", .perDayFallback(reason: .bucketMismatch, mismatchedBucketCount: 1)))
        XCTAssertEqual(log.records().count, 1)
        log.record(record("HRV", .aligned))
        log.record(record("Blood glucose", .aligned))
        XCTAssertEqual(log.records().map(\.metric), ["Blood glucose", "HRV"])
    }

    // MARK: 10. Nutrition

    func testMisalignedNutritionCollectionNeverOverwritesANeighbouringDay() async throws {
        let london = calendar("Europe/London")
        // Friday 30 October 2026, 20:00: the previous seven days start 16
        // October, so the collection spans the change on 25 October.
        let window = try DailyExportWindow.capture(at: date(2026, 10, 30, 20, london), calendar: london)
        let previous = try XCTUnwrap(window.context.precedingEquivalent(calendar: window.calendar))
        let days = NutritionNutrientTotals.collectionDays(window: window, previous: previous)
        XCTAssertEqual(days.count, 15)
        let queryInterval = DateInterval(start: previous.interval.start, end: window.cutoff)
        let plan = try XCTUnwrap(DailyBucketPlan(interval: queryInterval, days: days, calendar: london))
        XCTAssertEqual(plan.days.last, window.day)

        // A non-DST calendar steps 24 hours: after the change each bucket starts
        // at 23:00 GMT the evening before. The old re-keying by startOfDay filed
        // those under the previous day and overwrote its total.
        let starts = (0..<15).map { plan.anchorDate.addingTimeInterval(Double($0) * day) }
        let decoys = starts.enumerated().map { DailyBucket(start: $1, value: 9_000 + Double($0)) }
        let match = DailyBucketAlignment.match(decoys, days: plan.days)
        let changeIndex = try XCTUnwrap(days.firstIndex { $0.start == date(2026, 10, 25, 0, london) })
        XCTAssertEqual(match.values[changeIndex], 9_000 + Double(changeIndex))
        XCTAssertTrue(match.values[(changeIndex + 1)...].allSatisfy { $0 == nil })
        XCTAssertTrue(match.requiresFallback)

        let truth: [Date: Double] = Dictionary(uniqueKeysWithValues: days.enumerated().map {
            ($1.start, Double($0) * 10)
        })
        let result = try await DailyBucketReader.read(
            days: days,
            plan: plan,
            collection: { _ in decoys },
            perDay: { interval -> Double? in
                XCTAssertTrue(days.contains(interval), "fallback reads exact report days")
                return truth[interval.start]
            }
        )
        let totals = NutritionNutrientTotals(
            key: "energy",
            window: window,
            previous: previous,
            days: days,
            values: result.values
        )
        XCTAssertEqual(totals.today, truth[window.day.start])
        XCTAssertEqual(totals.currentDays.map(\.value), window.context.completedDays.map { truth[$0.start] })
        XCTAssertEqual(totals.previousDays.map(\.value), previous.completedDays.map { truth[$0.start] })
        XCTAssertFalse(totals.currentDays.contains { ($0.value ?? 0) >= 9_000 })
    }

    func testNutritionCollectionDaysOmitAnEmptyToday() throws {
        let london = calendar("Europe/London")
        let window = try DailyExportWindow.capture(at: date(2026, 10, 30, 0, london), calendar: london)
        let previous = try XCTUnwrap(window.context.precedingEquivalent(calendar: window.calendar))
        let days = NutritionNutrientTotals.collectionDays(window: window, previous: previous)
        XCTAssertEqual(days.count, 14)
        let totals = NutritionNutrientTotals(
            key: "energy",
            window: window,
            previous: previous,
            days: days,
            values: Array(repeating: 1, count: 14)
        )
        XCTAssertNil(totals.today)
        XCTAssertNotNil(DailyBucketPlan(
            interval: DateInterval(start: previous.interval.start, end: window.cutoff),
            days: days,
            calendar: london
        ))
    }

    // MARK: Helpers

    private func readSteps(
        plan: DailyBucketPlan,
        bucketStarts: [Date]
    ) async throws -> DailyBucketReader.Result<Double> {
        try await DailyBucketReader.read(
            days: plan.days,
            plan: plan,
            collection: { _ in bucketStarts.map { DailyBucket(start: $0, value: 5_000) } },
            perDay: { _ in XCTFail("aligned buckets need no fallback"); return nil }
        )
    }

    private func stepTotals(_ days: [DateInterval], _ values: [Double?]) -> [DailyStepTotal] {
        zip(days, values).map { DailyStepTotal(day: $0, steps: $1, sourceNames: []) }
    }

    private func glucoseValues(_ days: [DateInterval], _ values: [Double?]) -> [DailyGlucoseValue] {
        zip(days, values).map {
            DailyGlucoseValue(
                day: $0,
                averageMillimolesPerLiter: $1,
                minimumMillimolesPerLiter: $1.map { $0 - 1 },
                maximumMillimolesPerLiter: $1.map { $0 + 1 },
                sourceNames: []
            )
        }
    }

    private func heartValues(_ days: [DateInterval], _ values: [Double?]) -> [DailyHeartMetricValue] {
        zip(days, values).map { DailyHeartMetricValue(day: $0, value: $1, sourceNames: []) }
    }

    private func calendarDayStarts(from start: Date, count: Int, in calendar: Calendar) -> [Date] {
        (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func assertConsecutive(_ days: [DateInterval], file: StaticString = #filePath, line: UInt = #line) {
        for (left, right) in zip(days, days.dropFirst()) {
            XCTAssertEqual(left.end, right.start, file: file, line: line)
        }
    }

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

/// A fake HealthKit adapter: its collections step a fixed 24 hours from the
/// anchor (what a calendar without DST produces across the London change). A
/// bucket that happens to start at a London day carries that day's true value;
/// any other bucket mixes two days and carries a decoy. Per-day statistics
/// return the true value for an exact London day only.
private struct MisalignedDailyStore {
    let calendar: Calendar
    let hour: TimeInterval

    func truth(_ period: ReportPeriod, value: (Double) -> Double) -> [Double?] {
        period.completedDays.indices.map { value(Double($0)) }
    }

    func read(
        _ period: ReportPeriod,
        value: (Double) -> Double
    ) async throws -> DailyBucketReader.Result<Double> {
        let truth = Dictionary(uniqueKeysWithValues: zip(
            period.completedDays.map(\.start),
            self.truth(period, value: value)
        ))
        return try await DailyBucketReader.read(
            days: period.completedDays,
            plan: DailyBucketPlan(period: period, calendar: calendar),
            collection: { plan in
                plan.days.indices.map {
                    let start = plan.anchorDate.addingTimeInterval(Double($0) * 24 * hour)
                    return DailyBucket(start: start, value: truth[start].flatMap { $0 } ?? -1)
                }
            },
            perDay: { interval in
                guard period.completedDays.contains(interval) else { return nil }
                return truth[interval.start] ?? nil
            }
        )
    }
}
