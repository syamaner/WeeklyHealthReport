import XCTest
@testable import WeeklyHealthReport

// Contract tests for docs/health-food-and-water-v1.md (#214), domain rules.
// All values are synthetic fixtures.
final class FoodLogPeriodSummaryTests: XCTestCase {
    private typealias Facts = FoodLogDayFacts

    // MARK: Classification and coverage

    func testEachDayTypeIsClassified() {
        let dates = ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"]
        let summary = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 1_800),
            FoodLogFixtures.day(dates[1], energy: 600, energyIncomplete: 1),
            FoodLogFixtures.day(dates[2], energy: nil, energyIncomplete: 2, water: 500),
            FoodLogFixtures.day(dates[3], energy: 0, water: 250, waterIncomplete: 1),
            Facts(reportingDate: dates[4], entryCount: 0, foodEntryCount: 0, energy: nil, plainWater: nil)
        ], reportingDates: dates)

        XCTAssertEqual(summary.days.map(\.energy), [
            .complete(kilocalories: 1_800), .incomplete, .incomplete, .complete(kilocalories: 0), .notLogged
        ])
        XCTAssertEqual(summary.days.map(\.water), [
            .noPlainWater, .noPlainWater, .complete(millilitres: 500), .incomplete, .noPlainWater
        ])
        XCTAssertEqual(summary.reportingDayCount, 5)
        XCTAssertEqual(summary.loggedDayCount, 4)
        XCTAssertEqual(summary.completeEnergyDayCount, 2)
        XCTAssertEqual(summary.incompleteEnergyDayCount, 2)
        XCTAssertEqual(summary.completeWaterDayCount, 1)
        XCTAssertEqual(summary.incompleteWaterDayCount, 1)
    }

    func testCoverageCountsLoggedDaysOfTheCompletedDays() {
        let dates = FoodLogFixtures.dates(count: 7)
        let summary = FoodLogPeriodSummary.make(
            days: dates.prefix(6).map { FoodLogFixtures.day($0, energy: 2_000) },
            reportingDates: dates
        )
        XCTAssertEqual(summary.loggedDayCount, 6)
        XCTAssertEqual(summary.reportingDayCount, 7)
    }

    // MARK: Values

    func testEnergyMeanWeightsCompleteDaysEquallyAndLeavesIncompleteDaysOut() throws {
        let dates = FoodLogFixtures.dates(count: 4)
        let summary = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 1_000, entries: 1),
            FoodLogFixtures.day(dates[1], energy: 3_000, entries: 9),
            // A known subtotal from an incomplete day never enters the mean.
            FoodLogFixtures.day(dates[2], energy: 50_000, energyIncomplete: 1)
        ], reportingDates: dates)
        XCTAssertEqual(try XCTUnwrap(summary.averageEnergyKilocalories), 2_000, accuracy: 1e-9)
        XCTAssertEqual(summary.incompleteEnergyDayCount, 1)
    }

    func testNoCompleteEnergyDayGivesNoAverage() {
        let dates = FoodLogFixtures.dates(count: 2)
        let summary = FoodLogPeriodSummary.make(
            days: [FoodLogFixtures.day(dates[0], energy: 400, energyIncomplete: 1)],
            reportingDates: dates
        )
        XCTAssertEqual(summary.loggedDayCount, 1)
        XCTAssertNil(summary.averageEnergyKilocalories)
    }

    /// No plain water is no data; a logged 0 mL total is a real value.
    func testNoWaterIsNotZeroMillilitres() {
        let dates = FoodLogFixtures.dates(count: 3)
        let noWater = FoodLogPeriodSummary.make(
            days: dates.map { FoodLogFixtures.day($0, energy: 1_500) },
            reportingDates: dates
        )
        XCTAssertNil(noWater.averagePlainWaterMillilitres)
        XCTAssertEqual(noWater.completeWaterDayCount, 0)
        XCTAssertTrue(noWater.days.allSatisfy { $0.water == .noPlainWater })

        let zero = FoodLogPeriodSummary.make(
            days: [FoodLogFixtures.day(dates[0], energy: 0, water: 0)],
            reportingDates: dates
        )
        XCTAssertEqual(zero.averagePlainWaterMillilitres, 0)
        XCTAssertEqual(zero.completeWaterDayCount, 1)
    }

    func testPlainWaterMeanUsesCompleteWaterDaysOnly() throws {
        let dates = FoodLogFixtures.dates(count: 4)
        let summary = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 0, water: 1_000),
            FoodLogFixtures.day(dates[1], energy: 0, water: 2_000),
            FoodLogFixtures.day(dates[2], energy: 0, water: 9_000, waterIncomplete: 1),
            FoodLogFixtures.day(dates[3], energy: 1_200)
        ], reportingDates: dates)
        XCTAssertEqual(try XCTUnwrap(summary.averagePlainWaterMillilitres), 1_500, accuracy: 1e-9)
        XCTAssertEqual(summary.completeWaterDayCount, 2)
        XCTAssertEqual(summary.incompleteWaterDayCount, 1)
    }

    func testEstimatesPropagateOnlyFromAveragedDays() {
        let dates = FoodLogFixtures.dates(count: 3)
        let estimatedButIncomplete = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 1_000),
            FoodLogFixtures.day(dates[1], energy: 500, energyIncomplete: 1, estimates: true)
        ], reportingDates: dates)
        XCTAssertFalse(estimatedButIncomplete.energyIncludesEstimates)

        let estimated = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 1_000),
            FoodLogFixtures.day(dates[1], energy: 500, estimates: true, water: 300, waterEstimates: true)
        ], reportingDates: dates)
        XCTAssertTrue(estimated.energyIncludesEstimates)
        XCTAssertTrue(estimated.waterIncludesEstimates)
    }

    // MARK: Day rules

    /// Facts for today (or any date outside the completed days) are ignored.
    func testTodayIsExcluded() throws {
        let calendar = FoodLogFixtures.calendar
        let now = FoodLogFixtures.date(2026, 9, 10, hour: 12)
        let period = ReportPeriod.make(selection: .lastSevenCompletedDays, now: now, calendar: calendar)
        let dates = FoodLogPeriodSummary.reportingDates(for: period, calendar: calendar)
        let today = FoodLogPeriodSummary.reportingDate(for: now, calendar: calendar)
        XCTAssertEqual(today, "2026-09-10")
        XCTAssertFalse(dates.contains(today))
        XCTAssertEqual(dates.last, "2026-09-09")

        let summary = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(today, energy: 9_999, water: 9_999),
            FoodLogFixtures.day("2026-09-09", energy: 1_800)
        ], reportingDates: dates)
        XCTAssertEqual(summary.loggedDayCount, 1)
        XCTAssertEqual(summary.averageEnergyKilocalories, 1_800)
        XCTAssertNil(summary.averagePlainWaterMillilitres)
        XCTAssertFalse(summary.days.contains { $0.reportingDate == today })
    }

    /// Current week on its first day has no completed days.
    func testEmptyPeriodHasNoDaysAndNoValues() {
        let calendar = FoodLogFixtures.calendar
        let monday = FoodLogFixtures.date(2026, 9, 7, hour: 9)
        let period = ReportPeriod.make(selection: .currentWeek, now: monday, calendar: calendar)
        let dates = FoodLogPeriodSummary.reportingDates(for: period, calendar: calendar)
        XCTAssertEqual(dates, [])
        let summary = FoodLogPeriodSummary.make(
            days: [FoodLogFixtures.day("2026-09-07", energy: 1_000)],
            reportingDates: dates
        )
        XCTAssertEqual(summary.reportingDayCount, 0)
        XCTAssertEqual(summary.loggedDayCount, 0)
        XCTAssertNil(summary.averageEnergyKilocalories)
        XCTAssertNil(summary.averagePlainWaterMillilitres)
    }

    func testNothingLoggedHasNoValues() {
        let dates = FoodLogFixtures.dates(count: 7)
        let summary = FoodLogPeriodSummary.make(days: [], reportingDates: dates)
        XCTAssertEqual(summary.reportingDayCount, 7)
        XCTAssertEqual(summary.loggedDayCount, 0)
        XCTAssertNil(summary.averageEnergyKilocalories)
        XCTAssertTrue(summary.days.allSatisfy { $0.energy == .notLogged && $0.facts == nil })
    }

    /// Europe/London leaves summer time on 25 October 2026: that week still maps
    /// to seven distinct, consecutive reporting dates (a 25-hour day is one date).
    func testDaylightSavingWeeksMapToSevenReportingDates() {
        let calendar = FoodLogFixtures.calendar
        let autumn = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: FoodLogFixtures.date(2026, 10, 28, hour: 0, minute: 30),
            calendar: calendar
        )
        XCTAssertEqual(FoodLogPeriodSummary.reportingDates(for: autumn, calendar: calendar), [
            "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25", "2026-10-26", "2026-10-27"
        ])
        let spring = ReportPeriod.make(
            selection: .previousWeek,
            now: FoodLogFixtures.date(2026, 4, 1, hour: 23, minute: 30),
            calendar: calendar
        )
        let springDates = FoodLogPeriodSummary.reportingDates(for: spring, calendar: calendar)
        XCTAssertEqual(springDates.count, 7)
        XCTAssertEqual(Set(springDates).count, 7)
        XCTAssertTrue(springDates.contains("2026-03-29"), "the 23-hour day is one reporting date")
    }

    /// Reporting dates use the calendar's time zone, as Confirm stores them.
    func testReportingDateUsesTheCalendarTimeZone() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let instant = Date(timeIntervalSince1970: 1_788_220_800) // 2026-09-01T00:00:00Z
        XCTAssertEqual(FoodLogPeriodSummary.reportingDate(for: instant, calendar: tokyo), "2026-09-01")
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        XCTAssertEqual(FoodLogPeriodSummary.reportingDate(for: instant, calendar: honolulu), "2026-08-31")
    }

    // MARK: Plain water only (contract v1.1, decision 7)

    func testWaterOnlyDayIsNotALoggedFoodDay() {
        let dates = FoodLogFixtures.dates(count: 2)
        let summary = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.waterOnly(dates[0], water: 750),
            // Even a water-only day whose water could not be scaled is not an
            // incomplete energy day.
            FoodLogFixtures.waterOnly(dates[1], water: 250, waterIncomplete: 1)
        ], reportingDates: dates)
        XCTAssertEqual(summary.days.map(\.energy), [.notLogged, .notLogged])
        XCTAssertEqual(summary.days.map(\.water), [.complete(millilitres: 750), .incomplete])
        XCTAssertEqual(summary.loggedDayCount, 0)
        XCTAssertEqual(summary.incompleteEnergyDayCount, 0)
        XCTAssertNil(summary.averageEnergyKilocalories)
        XCTAssertEqual(summary.averagePlainWaterMillilitres, 750)
    }

    /// The owner's example: three food days and four water-only days.
    func testMixOfWaterOnlyAndFoodDays() throws {
        let dates = FoodLogFixtures.dates(count: 7)
        let summary = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 1_800, water: 1_000),
            FoodLogFixtures.day(dates[1], energy: 2_000),
            FoodLogFixtures.day(dates[2], energy: 2_200),
            FoodLogFixtures.waterOnly(dates[3], water: 1_500),
            FoodLogFixtures.waterOnly(dates[4], water: 2_000),
            FoodLogFixtures.waterOnly(dates[5], water: 500),
            FoodLogFixtures.waterOnly(dates[6], water: 1_000)
        ], reportingDates: dates)
        XCTAssertEqual(summary.loggedDayCount, 3)
        XCTAssertEqual(summary.completeEnergyDayCount, 3)
        XCTAssertEqual(summary.incompleteEnergyDayCount, 0)
        XCTAssertEqual(try XCTUnwrap(summary.averageEnergyKilocalories), 2_000, accuracy: 1e-9)
        XCTAssertEqual(summary.completeWaterDayCount, 5)
        XCTAssertEqual(try XCTUnwrap(summary.averagePlainWaterMillilitres), 1_200, accuracy: 1e-9)
    }

    func testPeriodWithOnlyPlainWater() {
        let dates = FoodLogFixtures.dates(count: 7)
        let summary = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.waterOnly(dates[1], water: 1_000),
            FoodLogFixtures.waterOnly(dates[4], water: 2_000)
        ], reportingDates: dates)
        XCTAssertEqual(summary.loggedDayCount, 0)
        XCTAssertNil(summary.averageEnergyKilocalories)
        XCTAssertEqual(summary.averagePlainWaterMillilitres, 1_500)
        XCTAssertEqual(summary.completeWaterDayCount, 2)
    }

    // MARK: Fibre (contract v1.2, #288)

    /// Owner decision 9: the energy rule. Any unknown fibre contribution, or no
    /// known fibre, leaves the day out of the mean and counts it; never 0 g.
    func testFibreDaysAreClassifiedLikeEnergy() {
        let dates = FoodLogFixtures.dates(count: 5)
        let summary = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 1_800, fibre: 20),
            FoodLogFixtures.day(dates[1], energy: 1_800, fibre: 9, fibreIncomplete: 1),
            FoodLogFixtures.day(dates[2], energy: 1_800),
            FoodLogFixtures.waterOnly(dates[3], water: 500),
            Facts(reportingDate: dates[4], entryCount: 2, foodEntryCount: 2,
                  energy: .init(knownAmount: 100, incompleteContributions: 0, includesEstimates: false), plainWater: nil)
        ], reportingDates: dates)
        XCTAssertEqual(summary.days.map(\.fibre), [
            .complete(grams: 20), .incomplete, .incomplete, .notLogged, .incomplete
        ], "a logged day with no fibre total read is unknown, not 0 g")
        XCTAssertEqual(summary.completeFibreDayCount, 1)
        XCTAssertEqual(summary.incompleteFibreDayCount, 3, "the water-only day is outside the count")
        XCTAssertEqual(summary.averageFibreGrams, 20)
    }

    func testFibreMeanWeightsCompleteDaysEquallyAndLeavesKnownMinimumsOut() throws {
        let dates = FoodLogFixtures.dates(count: 4)
        let summary = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 1_000, entries: 1, fibre: 10),
            FoodLogFixtures.day(dates[1], energy: 3_000, entries: 9, fibre: 31.5),
            FoodLogFixtures.day(dates[2], energy: 2_000, fibre: 90, fibreIncomplete: 1),
            FoodLogFixtures.waterOnly(dates[3], water: 2_000)
        ], reportingDates: dates)
        XCTAssertEqual(try XCTUnwrap(summary.averageFibreGrams), 20.75, accuracy: 1e-9)
        XCTAssertEqual(summary.completeFibreDayCount, 2)
        XCTAssertEqual(summary.incompleteFibreDayCount, 1)
        XCTAssertFalse(summary.fibreIncludesEstimates)
    }

    func testNoKnownFibreGivesNoAverageNeverZero() {
        let dates = FoodLogFixtures.dates(count: 3)
        let summary = FoodLogPeriodSummary.make(days: dates.map { FoodLogFixtures.day($0, energy: 2_000) },
                                                reportingDates: dates)
        XCTAssertNil(summary.averageFibreGrams)
        XCTAssertEqual(summary.incompleteFibreDayCount, 3)
        XCTAssertEqual(summary.averageEnergyKilocalories, 2_000, "energy is independent of fibre")
    }

    func testFibreEstimatesPropagateOnlyFromAveragedDays() {
        let dates = FoodLogFixtures.dates(count: 2)
        let incompleteEstimate = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 1_000, fibre: 20),
            FoodLogFixtures.day(dates[1], energy: 1_000, fibre: 5, fibreIncomplete: 1, fibreEstimates: true)
        ], reportingDates: dates)
        XCTAssertFalse(incompleteEstimate.fibreIncludesEstimates)
        let completeEstimate = FoodLogPeriodSummary.make(days: [
            FoodLogFixtures.day(dates[0], energy: 1_000, fibre: 20, fibreEstimates: true)
        ], reportingDates: dates)
        XCTAssertTrue(completeEstimate.fibreIncludesEstimates)
        XCTAssertFalse(completeEstimate.energyIncludesEstimates, "fibre estimates never label energy")
    }

    func testNormalWeekFixtureMatchesTheContractExample() throws {
        let summary = FoodLogFixtures.normalWeek(dates: FoodLogFixtures.dates(count: 7))
        XCTAssertEqual(summary.loggedDayCount, 6)
        XCTAssertEqual(summary.completeEnergyDayCount, 5)
        XCTAssertEqual(summary.incompleteEnergyDayCount, 1)
        XCTAssertEqual(try XCTUnwrap(summary.averageEnergyKilocalories), 2_010.08, accuracy: 1e-9)
        XCTAssertEqual(summary.completeWaterDayCount, 4)
        XCTAssertEqual(summary.averagePlainWaterMillilitres, 1_750)
        XCTAssertEqual(summary.completeFibreDayCount, 4)
        XCTAssertEqual(summary.incompleteFibreDayCount, 2)
        XCTAssertEqual(summary.averageFibreGrams, 24)
    }
}

/// Synthetic food-log fixtures shared by the #214 tests.
enum FoodLogFixtures {
    static let locale = Locale(identifier: "en_GB")

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func dates(count: Int) -> [String] {
        (1...count).map { String(format: "2026-09-%02d", $0) }
    }

    static func day(
        _ date: String,
        energy: Double?,
        energyIncomplete: Int = 0,
        estimates: Bool = false,
        water: Double? = nil,
        waterIncomplete: Int = 0,
        waterEstimates: Bool = false,
        entries: Int = 3,
        fibre: Double? = nil,
        fibreIncomplete: Int = 0,
        fibreEstimates: Bool = false
    ) -> FoodLogDayFacts {
        FoodLogDayFacts(
            reportingDate: date,
            entryCount: entries + (water == nil ? 0 : 1),
            foodEntryCount: entries,
            energy: FoodLogDayFacts.Total(
                knownAmount: energy,
                incompleteContributions: energyIncomplete,
                includesEstimates: estimates
            ),
            plainWater: water.map {
                FoodLogDayFacts.Total(
                    knownAmount: $0,
                    incompleteContributions: waterIncomplete,
                    includesEstimates: waterEstimates
                )
            },
            // No fibre given means no entry had fibre: unknown, never 0 g.
            fibre: FoodLogDayFacts.Total(
                knownAmount: fibre,
                incompleteContributions: fibre == nil ? entries : fibreIncomplete,
                includesEstimates: fibreEstimates
            )
        )
    }

    /// A day with only plain water entries: no food entry, so no energy total.
    static func waterOnly(
        _ date: String,
        water: Double,
        waterIncomplete: Int = 0,
        entries: Int = 2
    ) -> FoodLogDayFacts {
        FoodLogDayFacts(
            reportingDate: date,
            entryCount: entries,
            foodEntryCount: 0,
            energy: nil,
            plainWater: FoodLogDayFacts.Total(
                knownAmount: water,
                incompleteContributions: waterIncomplete,
                includesEstimates: false
            )
        )
    }

    /// The contract's example week: 6 / 7 days logged, a 2,010 kcal mean over
    /// five complete days, one incomplete energy day and plain water on four days;
    /// v1.2 (#288) fibre: a 24 g mean over four complete fibre days and two
    /// incomplete ones (a known minimum and no known fibre).
    static func normalWeekFacts(dates: [String]) -> [FoodLogDayFacts] {
        [
            day(dates[0], energy: 1_900, water: 1_500, fibre: 22),
            day(dates[1], energy: 2_100, water: 2_000, fibre: 26),
            // dates[2] not logged
            day(dates[3], energy: 1_950, water: 1_750, fibre: 23),
            day(dates[4], energy: 800, energyIncomplete: 1, water: 1_750, fibre: 25),
            day(dates[5], energy: 2_050, fibre: 10, fibreIncomplete: 1),
            day(dates[6], energy: 2_050.4)
        ]
    }

    static func normalWeek(dates: [String]) -> FoodLogPeriodSummary {
        FoodLogPeriodSummary.make(days: normalWeekFacts(dates: dates), reportingDates: dates)
    }

    static func normalWeek(period: ReportPeriod, calendar: Calendar) -> FoodLogPeriodSummary {
        normalWeek(dates: FoodLogPeriodSummary.reportingDates(for: period, calendar: calendar))
    }
}
