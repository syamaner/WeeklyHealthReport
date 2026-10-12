import XCTest
@testable import WeeklyHealthReport

// Contract tests for today_so_far_health_v1 (docs/today-so-far-projection-v1.md
// section 9). Every value here is a synthetic fixture.
final class TodaySoFarHealthTests: XCTestCase {
    // MARK: 1. Window

    func testWindowStartsAtLocalMidnightAndEndsAtAsOf() throws {
        let calendar = Fixture.calendar("Europe/London")
        let asOf = Fixture.date(2026, 10, 12, 14, 32, calendar)
        let window = try XCTUnwrap(TodaySoFarWindow.capture(at: asOf, calendar: calendar))

        XCTAssertEqual(window.day.start, Fixture.date(2026, 10, 12, 0, 0, calendar))
        XCTAssertEqual(window.day.end, asOf)
        XCTAssertEqual(window.asOf, asOf)
        XCTAssertEqual(window.sleep.start, Fixture.date(2026, 10, 11, 12, 0, calendar))
        XCTAssertEqual(window.sleep.end, Fixture.date(2026, 10, 12, 12, 0, calendar))
        XCTAssertTrue(window.sleepIsComplete)
    }

    func testWindowOnDaylightSavingDaysStartsAtLocalMidnightWithoutFixedDayLength() throws {
        for zone in ["Europe/London", "America/New_York"] {
            let calendar = Fixture.calendar(zone)
            // London: 29 March and 25 October 2026. New York: 8 March and 1 November 2026.
            // Midnight to 23:00 local is 22 elapsed hours on the 23-hour day and 24 on the 25-hour day.
            let days = zone == "Europe/London"
                ? [(3, 29, 22.0), (10, 25, 24.0)] : [(3, 8, 22.0), (11, 1, 24.0)]
            for (month, day, hours) in days {
                let asOf = Fixture.date(2026, month, day, 23, 0, calendar)
                let window = try XCTUnwrap(TodaySoFarWindow.capture(at: asOf, calendar: calendar))
                XCTAssertEqual(window.day.start, Fixture.date(2026, month, day, 0, 0, calendar), "\(zone) \(month)/\(day)")
                XCTAssertEqual(calendar.component(.hour, from: window.day.start), 0)
                XCTAssertEqual(window.day.duration, hours * 3600, "\(zone) \(month)/\(day)")
            }
        }
    }

    func testBeforeNoonSleepIsClippedToAsOfAndInProgress() throws {
        let calendar = Fixture.calendar("Europe/London")
        let asOf = Fixture.date(2026, 10, 12, 8, 15, calendar)
        let window = try XCTUnwrap(TodaySoFarWindow.capture(at: asOf, calendar: calendar))
        XCTAssertEqual(window.sleep.end, asOf)
        XCTAssertFalse(window.sleepIsComplete)
    }

    // MARK: 2. Midnight

    func testAsOfAtMidnightGivesEmptyDayAndNoCumulativeData() throws {
        let calendar = Fixture.calendar("Europe/London")
        let midnight = Fixture.date(2026, 10, 12, 0, 0, calendar)
        let window = try XCTUnwrap(TodaySoFarWindow.capture(at: midnight, calendar: calendar))
        XCTAssertTrue(window.dayIsEmpty)

        let lateYesterday = midnight.addingTimeInterval(-1)
        let projection = TodaySoFarHealthProjection.make(inputs: Fixture.inputs(
            steps: .value(DailyStepTotal(day: window.day, steps: 12, sourceNames: ["Phone"])),
            energy: .value(5),
            asleep: .value([AsleepInterval(start: lateYesterday.addingTimeInterval(-3600), end: lateYesterday)]),
            weights: .value([WeightMeasurement(id: Fixture.uuid(1), date: lateYesterday, kilograms: 70)])
        ), window: window)

        XCTAssertEqual(projection.steps, .noData)
        XCTAssertEqual(projection.activeEnergyKilocalories, .noData)
        // 23:59:59 yesterday is inside last night's bucket and the weight lookback.
        guard case .value(let sleep) = projection.sleep else { return XCTFail("sleep") }
        XCTAssertEqual(sleep.asleepSeconds, 3600)
        XCTAssertEqual(projection.latestWeight, .value(WeightMeasurement(id: Fixture.uuid(1), date: lateYesterday, kilograms: 70)))
    }

    // MARK: 3. Calendar snapshot

    func testCapturedWindowIgnoresLaterTimeZoneChange() throws {
        var calendar = Fixture.calendar("Europe/London")
        let asOf = Fixture.date(2026, 10, 12, 9, 0, calendar)
        let window = try XCTUnwrap(TodaySoFarWindow.capture(at: asOf, calendar: calendar))
        let start = window.day.start
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        XCTAssertEqual(window.calendar.timeZone.identifier, "Europe/London")
        XCTAssertEqual(window.day.start, start)
        XCTAssertNotEqual(TodaySoFarWindow.capture(at: asOf, calendar: calendar)?.day.start, start)
    }

    // MARK: 4. Rollover

    func testProjectionsEitherSideOfMidnightUseDifferentDays() throws {
        let calendar = Fixture.calendar("Europe/London")
        let before = try XCTUnwrap(TodaySoFarWindow.capture(at: Fixture.date(2026, 10, 12, 23, 59, calendar), calendar: calendar))
        let after = try XCTUnwrap(TodaySoFarWindow.capture(at: Fixture.date(2026, 10, 13, 0, 1, calendar), calendar: calendar))
        XCTAssertNotEqual(before.day.start, after.day.start)
        XCTAssertEqual(after.day.start, Fixture.date(2026, 10, 13, 0, 0, calendar))
        XCTAssertEqual(after.day.duration, 60)
    }

    // MARK: 5. Steps and energy

    func testCumulativeAbsenceIsNoDataAndZeroIsVisible() throws {
        let window = try Fixture.window()
        let absent = TodaySoFarHealthProjection.make(inputs: Fixture.inputs(
            steps: .noData, energy: .noData), window: window)
        XCTAssertEqual(absent.steps, .noData)
        XCTAssertEqual(absent.activeEnergyKilocalories, .noData)

        let zero = TodaySoFarHealthProjection.make(inputs: Fixture.inputs(
            steps: .value(DailyStepTotal(day: window.day, steps: 0, sourceNames: [])), energy: .value(0)), window: window)
        XCTAssertEqual(zero.steps, .value(.init(count: 0, sourceNames: [])))
        XCTAssertEqual(zero.activeEnergyKilocalories, .value(0))

        let positive = TodaySoFarHealthProjection.make(inputs: Fixture.inputs(
            steps: .value(DailyStepTotal(day: window.day, steps: 6412.4, sourceNames: ["Phone", "Watch"])),
            energy: .value(312.75)), window: window)
        XCTAssertEqual(positive.steps, .value(.init(count: 6412.4, sourceNames: ["Phone", "Watch"])))
        XCTAssertEqual(positive.activeEnergyKilocalories, .value(312.75))
    }

    // MARK: 6. Sleep

    func testOnlyAsleepStagesCount() {
        let counted = SleepStage.allCasesForTest.filter(\.countsAsAsleep)
        XCTAssertEqual(Set(counted), [.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM])
    }

    func testSleepMergesOverlapsClipsAndReportsProgress() throws {
        let calendar = Fixture.calendar("Europe/London")
        let morning = try XCTUnwrap(TodaySoFarWindow.capture(at: Fixture.date(2026, 10, 12, 7, 0, calendar), calendar: calendar))
        let intervals = [
            // Crosses yesterday's noon: only 12:00 to 12:30 counts.
            AsleepInterval(start: Fixture.date(2026, 10, 11, 11, 30, calendar), end: Fixture.date(2026, 10, 11, 12, 30, calendar)),
            // Watch and phone overlap: counted once, 23:00 to 06:00.
            AsleepInterval(start: Fixture.date(2026, 10, 11, 23, 0, calendar), end: Fixture.date(2026, 10, 12, 5, 0, calendar)),
            AsleepInterval(start: Fixture.date(2026, 10, 12, 1, 0, calendar), end: Fixture.date(2026, 10, 12, 6, 0, calendar)),
            // Crosses asOf: clipped to 07:00.
            AsleepInterval(start: Fixture.date(2026, 10, 12, 6, 30, calendar), end: Fixture.date(2026, 10, 12, 8, 0, calendar))
        ]
        let projection = TodaySoFarHealthProjection.make(inputs: Fixture.inputs(asleep: .value(intervals)), window: morning)
        guard case .value(let sleep) = projection.sleep else { return XCTFail("sleep") }
        XCTAssertEqual(sleep.asleepSeconds, (30 + 7 * 60 + 30) * 60)
        XCTAssertFalse(sleep.isComplete)

        let afternoon = try XCTUnwrap(TodaySoFarWindow.capture(at: Fixture.date(2026, 10, 12, 12, 0, calendar), calendar: calendar))
        guard case .value(let complete) = TodaySoFarHealthProjection.make(
            inputs: Fixture.inputs(asleep: .value(intervals)), window: afternoon).sleep else { return XCTFail("sleep") }
        XCTAssertTrue(complete.isComplete)
    }

    func testZeroMergedSleepIsNoData() throws {
        let calendar = Fixture.calendar("Europe/London")
        let window = try XCTUnwrap(TodaySoFarWindow.capture(at: Fixture.date(2026, 10, 12, 9, 0, calendar), calendar: calendar))
        let outside = AsleepInterval(start: Fixture.date(2026, 10, 10, 23, 0, calendar), end: Fixture.date(2026, 10, 11, 6, 0, calendar))
        XCTAssertEqual(TodaySoFarHealthProjection.make(inputs: Fixture.inputs(asleep: .value([outside])), window: window).sleep, .noData)
    }

    // MARK: 7. Weight

    func testWeightUsesSharedLookbackAndLatestWithIdentifierTieBreak() throws {
        let calendar = Fixture.calendar("Europe/London")
        let asOf = Fixture.date(2026, 10, 12, 9, 0, calendar)
        let window = try XCTUnwrap(TodaySoFarWindow.capture(at: asOf, calendar: calendar))
        let lookback = try XCTUnwrap(HealthReportingPolicy.weightLatestLookbackStart(asOf: asOf, calendar: calendar))
        XCTAssertEqual(window.weightLookbackStart, lookback)
        XCTAssertEqual(HealthReportingPolicy.weightLatestLookbackDays, 30)
        XCTAssertEqual(lookback, calendar.date(byAdding: .day, value: -30, to: asOf))

        let atBoundary = WeightMeasurement(id: Fixture.uuid(1), date: lookback, kilograms: 71)
        let tooOld = WeightMeasurement(id: Fixture.uuid(2), date: lookback.addingTimeInterval(-1), kilograms: 99)
        XCTAssertEqual(TodaySoFarHealthProjection.make(inputs: Fixture.inputs(weights: .value([atBoundary, tooOld])), window: window).latestWeight,
                       .value(atBoundary))
        XCTAssertEqual(TodaySoFarHealthProjection.make(inputs: Fixture.inputs(weights: .value([tooOld])), window: window).latestWeight,
                       .noData)

        let morning = Fixture.date(2026, 10, 12, 7, 5, calendar)
        let first = WeightMeasurement(id: Fixture.uuid(4), date: morning, kilograms: 72.6)
        let second = WeightMeasurement(id: Fixture.uuid(3), date: morning, kilograms: 72.4)
        XCTAssertEqual(TodaySoFarHealthProjection.make(inputs: Fixture.inputs(weights: .value([first, second, atBoundary])), window: window).latestWeight,
                       .value(second))
    }

    // MARK: 8. Blood pressure

    func testBloodPressureLatestCompletePairWithinLookback() throws {
        let calendar = Fixture.calendar("Europe/London")
        let asOf = Fixture.date(2026, 10, 12, 9, 0, calendar)
        let window = try XCTUnwrap(TodaySoFarWindow.capture(at: asOf, calendar: calendar))
        XCTAssertEqual(window.bloodPressureLookbackStart,
                       HealthReportingPolicy.bloodPressureLatestLookbackStart(asOf: asOf, calendar: calendar))

        let valid = Fixture.reading(1, Fixture.date(2026, 10, 12, 7, 10, calendar), 123, 78)
        let nonFinite = Fixture.reading(2, Fixture.date(2026, 10, 12, 8, 0, calendar), .nan, 80)
        let nonPositive = Fixture.reading(3, Fixture.date(2026, 10, 12, 8, 30, calendar), 120, 0)
        let future = Fixture.reading(4, Fixture.date(2026, 10, 12, 9, 30, calendar), 130, 85)
        let old = Fixture.reading(5, window.bloodPressureLookbackStart.addingTimeInterval(-1), 140, 90)
        let readings = [old, valid, nonFinite, nonPositive, future]

        XCTAssertEqual(TodaySoFarHealthProjection.make(inputs: Fixture.inputs(bloodPressure: .value(readings)), window: window).latestBloodPressure,
                       .value(valid))
        XCTAssertEqual(BloodPressureReading.latestValid(in: readings, lookbackStart: window.bloodPressureLookbackStart, asOf: asOf), valid)
        // The report's latest uses the same rule.
        let period = ReportPeriod.make(selection: .lastSevenCompletedDays, now: asOf, calendar: calendar)
        XCTAssertEqual(BloodPressureSummary.calculate(readings: readings, period: period, asOf: asOf, calendar: calendar)?.latest, valid)
        XCTAssertEqual(TodaySoFarHealthProjection.make(inputs: Fixture.inputs(bloodPressure: .value([old, nonFinite])), window: window).latestBloodPressure,
                       .noData)
    }

    // MARK: 9. Port error mapping

    func testHealthUnavailableMakesEveryRowUnavailable() {
        let inputs = TodaySoFarReadMapping.inputs(
            steps: .success(DailyStepTotal(day: DateInterval(), steps: 10, sourceNames: [])),
            activeEnergyKilocalories: .success(1),
            asleepIntervals: .failure(.healthUnavailable),
            weights: .success([]),
            bloodPressure: .success([])
        )
        XCTAssertEqual(inputs, .healthUnavailable)
    }

    func testOtherFailureAffectsOnlyThatRowAndEmptyIsNoData() {
        let total = DailyStepTotal(day: DateInterval(), steps: 10, sourceNames: ["Phone"])
        let inputs = TodaySoFarReadMapping.inputs(
            steps: .success(total),
            activeEnergyKilocalories: .success(nil),
            asleepIntervals: .failure(.failed),
            weights: .success([]),
            bloodPressure: .success([])
        )
        XCTAssertEqual(inputs.steps, .value(total))
        XCTAssertEqual(inputs.activeEnergyKilocalories, .noData)
        XCTAssertEqual(inputs.asleepIntervals, .failed)
        XCTAssertEqual(inputs.weights, .noData)
        XCTAssertEqual(inputs.bloodPressure, .noData)

        let absentSum = TodaySoFarReadMapping.inputs(
            steps: .success(DailyStepTotal(day: DateInterval(), steps: nil, sourceNames: [])),
            activeEnergyKilocalories: .success(0), asleepIntervals: .success([]), weights: .success([]), bloodPressure: .success([]))
        XCTAssertEqual(absentSum.steps, .noData)
        XCTAssertEqual(absentSum.activeEnergyKilocalories, .value(0))
    }

    // MARK: 10. Formatter and presentation

    func testFormatterStrings() throws {
        let gb = Locale(identifier: "en_GB")
        XCTAssertEqual(HealthReportFormatter.todaySoFarSteps(6412, locale: gb), "6,412 so far")
        XCTAssertEqual(HealthReportFormatter.todaySoFarSteps(0, locale: gb), "0 so far")
        XCTAssertEqual(HealthReportFormatter.todaySoFarActiveEnergy(312.4, locale: gb), "312 kcal so far")
        XCTAssertEqual(HealthReportFormatter.todaySoFarSleep(seconds: (7 * 60 + 12) * 60, isComplete: true), "7 h 12 min · last night")
        XCTAssertEqual(HealthReportFormatter.todaySoFarSleep(seconds: (6 * 60 + 10) * 60 + 59, isComplete: false), "6 h 10 min so far · last night")
        XCTAssertEqual(HealthReportFormatter.todaySoFarSleep(seconds: 45 * 60, isComplete: true), "45 min · last night")
    }

    func testTimesFollowSystemStyleAndRelativeDays() {
        let calendar = Fixture.calendar("Europe/London")
        let asOf = Fixture.date(2026, 10, 12, 14, 32, calendar)
        let gb = Locale(identifier: "en_GB")
        let us = Locale(identifier: "en_US")
        let today = Fixture.date(2026, 10, 12, 7, 5, calendar)
        XCTAssertEqual(HealthReportFormatter.todaySoFarTime(today, asOf: asOf, calendar: calendar, locale: gb), "07:05")
        XCTAssertEqual(Fixture.plainSpaces(HealthReportFormatter.todaySoFarTime(today, asOf: asOf, calendar: calendar, locale: us)), "7:05 AM")
        XCTAssertEqual(HealthReportFormatter.todaySoFarTime(Fixture.date(2026, 10, 11, 21, 40, calendar), asOf: asOf, calendar: calendar, locale: gb),
                       "Yesterday, 21:40")
        XCTAssertEqual(HealthReportFormatter.todaySoFarTime(Fixture.date(2026, 10, 8, 7, 5, calendar), asOf: asOf, calendar: calendar, locale: gb),
                       "8 Oct, 07:05")
        XCTAssertEqual(HealthReportFormatter.todaySoFarAsOf(asOf, calendar: calendar, locale: gb), "As of 14:32")
        XCTAssertEqual(HealthReportFormatter.todaySoFarWeight(WeightMeasurement(id: Fixture.uuid(1), date: today, kilograms: 72.44),
                                                              asOf: asOf, calendar: calendar, locale: gb), "72.4 kg · 07:05")
        XCTAssertEqual(HealthReportFormatter.todaySoFarBloodPressure(Fixture.reading(1, Fixture.date(2026, 10, 12, 7, 10, calendar), 123, 78),
                                                                     asOf: asOf, calendar: calendar, locale: gb), "123/78 mmHg · 07:10")
    }

    func testCardForEveryRowState() throws {
        let calendar = Fixture.calendar("Europe/London")
        let asOf = Fixture.date(2026, 10, 12, 14, 32, calendar)
        let window = try XCTUnwrap(TodaySoFarWindow.capture(at: asOf, calendar: calendar))
        let gb = Locale(identifier: "en_GB")

        let available = TodaySoFarHealthCard.make(projection: .make(inputs: Fixture.inputs(
            steps: .value(DailyStepTotal(day: window.day, steps: 6412, sourceNames: ["Phone"])),
            energy: .value(312),
            asleep: .value([AsleepInterval(start: Fixture.date(2026, 10, 11, 23, 0, calendar), end: Fixture.date(2026, 10, 12, 6, 12, calendar))]),
            weights: .value([WeightMeasurement(id: Fixture.uuid(1), date: Fixture.date(2026, 10, 12, 7, 5, calendar), kilograms: 72.4)]),
            bloodPressure: .value([Fixture.reading(1, Fixture.date(2026, 10, 12, 7, 10, calendar), 123, 78)])
        ), window: window), isRefreshing: false, locale: gb)
        XCTAssertEqual(available.asOf, "As of 14:32")
        XCTAssertEqual(available.footer, "Today is still in progress. Health summaries use completed days.")
        let rows = try Fixture.rows(available)
        XCTAssertEqual(rows.map(\.title), ["Steps", "Active energy", "Sleep", "Weight", "Blood pressure"])
        XCTAssertEqual(rows.map(\.value), ["6,412 so far", "312 kcal so far", "7 h 12 min · last night", "72.4 kg · 07:05", "123/78 mmHg · 07:10"])
        XCTAssertEqual(rows[0].accessibilityLabel, "Steps, 6,412 so far")
        XCTAssertEqual(rows[4].accessibilityLabel, "Blood pressure, 123 over 78 millimetres of mercury, 07:10")
        XCTAssertEqual(rows[3].accessibilityLabel, "Weight, 72.4 kilograms, 07:05")
        XCTAssertTrue(rows.allSatisfy { $0.status == .available })

        let empty = try Fixture.rows(TodaySoFarHealthCard.make(projection: .make(inputs: Fixture.inputs(
            asleep: .noData, bloodPressure: .failed), window: window), isRefreshing: false, locale: gb))
        XCTAssertEqual(empty.map(\.value), ["No data", "No data", "No sleep visible yet, or no access", "No data", "Could not read Apple Health."])
        XCTAssertEqual(empty.map(\.status), [.noData, .noData, .noData, .noData, .failed])
        XCTAssertEqual(empty[0].accessibilityLabel, "Steps, no visible data, or Health access was not granted.")
        XCTAssertEqual(empty[2].accessibilityLabel, "Sleep, no sleep visible yet, or no access")
        XCTAssertEqual(empty[4].accessibilityLabel, "Blood pressure, could not read Apple Health.")
        XCTAssertFalse(empty.contains { $0.value.hasPrefix("0") }, "absence never renders as 0")

        let loading = try Fixture.rows(TodaySoFarHealthCard.make(projection: nil, isRefreshing: true, locale: gb))
        XCTAssertTrue(loading.allSatisfy { $0.status == .loading && $0.value.isEmpty })
        XCTAssertEqual(loading[0].accessibilityLabel, "Steps, loading")

        let unavailable = TodaySoFarHealthCard.make(projection: .make(inputs: .healthUnavailable, window: window), isRefreshing: false, locale: gb)
        XCTAssertEqual(unavailable.content, .unavailable("Apple Health is not available on this device."))
    }

    // MARK: 12. Report, copied text and export never carry Home strings

    func testReportDocumentAndExportGoldensContainNoHomeStrings() {
        let homeStrings = ["so far", "last night", "As of"]
        for id in ReportDocument.SectionID.allCases {
            for state in ReportPreviewFixtures.State.allCases {
                let text = String(describing: ReportPreviewFixtures.section(id, state: state))
                for phrase in homeStrings {
                    XCTAssertFalse(text.contains(phrase), "\(id) \(state) contains \(phrase)")
                }
            }
        }
        for json in [DailyHealthExportGoldenSnapshots.populated, DailyHealthExportGoldenSnapshots.nilNotesAndNutrition] {
            for phrase in homeStrings { XCTAssertFalse(json.contains(phrase)) }
        }
    }
}

private enum Fixture {
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func window() throws -> TodaySoFarWindow {
        let calendar = calendar("Europe/London")
        return try XCTUnwrap(TodaySoFarWindow.capture(at: date(2026, 10, 12, 14, 0, calendar), calendar: calendar))
    }

    static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    static func reading(_ id: Int, _ date: Date, _ systolic: Double, _ diastolic: Double) -> BloodPressureReading {
        BloodPressureReading(id: uuid(id), date: date, systolicMillimetresOfMercury: systolic,
                             diastolicMillimetresOfMercury: diastolic, sourceName: "Synthetic cuff")
    }

    static func inputs(
        steps: TodaySoFarRead<DailyStepTotal> = .noData,
        energy: TodaySoFarRead<Double> = .noData,
        asleep: TodaySoFarRead<[AsleepInterval]> = .noData,
        weights: TodaySoFarRead<[WeightMeasurement]> = .noData,
        bloodPressure: TodaySoFarRead<[BloodPressureReading]> = .noData
    ) -> TodaySoFarHealthInputs {
        TodaySoFarHealthInputs(steps: steps, activeEnergyKilocalories: energy, asleepIntervals: asleep,
                               weights: weights, bloodPressure: bloodPressure)
    }

    static func rows(_ card: TodaySoFarHealthCard) throws -> [TodaySoFarHealthRow] {
        guard case .rows(let rows) = card.content else { throw NoRows() }
        return rows
    }

    struct NoRows: Error {}

    /// ICU uses a narrow no-break space before AM/PM.
    static func plainSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

private extension SleepStage {
    static let allCasesForTest: [SleepStage] = [.inBed, .awake, .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM, .other]
}
