import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
final class CardiorespiratorySummaryTests: XCTestCase {
    func testVO2MaxUsesDailyFirstAveragesAcrossAllWindows() throws {
        let calendar = testCalendar()
        let asOf = date(2026, 8, 31, hour: 18, calendar: calendar)
        let measurements = [
            vo2(2026, 8, 30, 30, calendar),
            VO2MaxMeasurement(
                date: date(2026, 8, 30, hour: 10, calendar: calendar),
                millilitresPerKilogramMinute: 40,
                sourceName: "Fixture Watch"
            ),
            vo2(2026, 8, 20, 32, calendar),
            vo2(2026, 8, 10, 34, calendar),
            vo2(2026, 6, 15, 28, calendar),
            vo2(2026, 4, 1, 26, calendar)
        ]

        let summary = try XCTUnwrap(VO2MaxSummary.calculate(
            measurements: measurements,
            asOf: asOf,
            calendar: calendar
        ))

        XCTAssertEqual(summary.latest.millilitresPerKilogramMinute, 40)
        XCTAssertEqual(summary.fourWeek.sampledDayCount, 3)
        XCTAssertEqual(try XCTUnwrap(summary.fourWeek.average), 101.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(summary.threeMonth.sampledDayCount, 4)
        XCTAssertEqual(try XCTUnwrap(summary.threeMonth.average), 129.0 / 4.0, accuracy: 0.0001)
        XCTAssertEqual(summary.sixMonth.sampledDayCount, 5)
        XCTAssertEqual(try XCTUnwrap(summary.sixMonth.average), 155.0 / 5.0, accuracy: 0.0001)
    }

    func testVO2MaxRequiresThreeSampledDaysAndExcludesOlderValues() throws {
        let calendar = testCalendar()
        let asOf = date(2026, 8, 31, calendar: calendar)
        let summary = try XCTUnwrap(VO2MaxSummary.calculate(
            measurements: [
                vo2(2026, 8, 30, 31, calendar),
                vo2(2026, 8, 20, 32, calendar),
                vo2(2026, 2, 20, 99, calendar)
            ],
            asOf: asOf,
            calendar: calendar
        ))

        XCTAssertEqual(summary.fourWeek.sampledDayCount, 2)
        XCTAssertNil(summary.fourWeek.average)
        XCTAssertEqual(summary.sixMonth.sampledDayCount, 2)
        XCTAssertFalse(summary.measurements.contains { $0.millilitresPerKilogramMinute == 99 })
    }

    func testBloodOxygenConvertsHealthKitFractionToPercentagePoints() {
        XCTAssertEqual(
            OxygenSaturationMeasurement.percentagePoints(fromHealthKitFraction: 0.973),
            97.3,
            accuracy: 0.0001
        )
    }

    func testBloodOxygenUsesDailyMediansThenMedianAcrossDays() throws {
        let calendar = testCalendar()
        let asOf = date(2026, 8, 31, hour: 12, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: asOf,
            calendar: calendar
        )
        let measurements = [
            oxygen(2026, 8, 24, 95, calendar),
            oxygen(2026, 8, 24, 97, calendar),
            oxygen(2026, 8, 25, 96, calendar),
            oxygen(2026, 8, 26, 97, calendar),
            oxygen(2026, 8, 26, 98, calendar),
            oxygen(2026, 8, 26, 99, calendar),
            oxygen(2026, 8, 31, 94, calendar)
        ]

        let summary = try XCTUnwrap(BloodOxygenSummary.calculate(
            measurements: measurements,
            period: period,
            asOf: asOf
        ))

        XCTAssertEqual(summary.latest.percentage, 94)
        XCTAssertEqual(summary.validDayCount, 3)
        XCTAssertEqual(summary.reportingDayCount, 7)
        XCTAssertEqual(summary.typicalPercentage, 96)
        XCTAssertEqual(summary.minimumDailyMedian, 96)
        XCTAssertEqual(summary.maximumDailyMedian, 98)
        XCTAssertEqual(summary.dailyValues.first?.medianPercentage, 96)
        XCTAssertEqual(summary.dailyValues[2].medianPercentage, 98)
    }

    func testBloodOxygenRejectsInvalidValuesAndReturnsNilWithoutMeasurements() {
        let calendar = testCalendar()
        let asOf = date(2026, 8, 31, calendar: calendar)
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: asOf,
            calendar: calendar
        )
        XCTAssertNil(BloodOxygenSummary.calculate(
            measurements: [oxygen(2026, 8, 30, 120, calendar)],
            period: period,
            asOf: asOf
        ))
    }

    private func vo2(
        _ year: Int, _ month: Int, _ day: Int, _ value: Double, _ calendar: Calendar
    ) -> VO2MaxMeasurement {
        VO2MaxMeasurement(
            date: date(year, month, day, calendar: calendar),
            millilitresPerKilogramMinute: value,
            sourceName: "Fixture Watch"
        )
    }

    private func oxygen(
        _ year: Int, _ month: Int, _ day: Int, _ value: Double, _ calendar: Calendar
    ) -> OxygenSaturationMeasurement {
        OxygenSaturationMeasurement(
            date: date(year, month, day, calendar: calendar),
            percentage: value,
            sourceName: "Fixture Watch"
        )
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 9,
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
