import XCTest
@testable import WeeklyHealthReport

final class GlucoseSummaryTests: XCTestCase {
    func testWeeklyAverageUsesOneAveragePerValidDay() throws {
        let days = reportDays()
        let summary = try XCTUnwrap(GlucoseSummary.aggregate([
            DailyGlucoseValue(
                day: days[0],
                averageMillimolesPerLiter: 4,
                minimumMillimolesPerLiter: 3.5,
                maximumMillimolesPerLiter: 5.2,
                sourceNames: ["Fixture Sensor"]
            ),
            DailyGlucoseValue(
                day: days[1],
                averageMillimolesPerLiter: 10,
                minimumMillimolesPerLiter: 6.1,
                maximumMillimolesPerLiter: 12,
                sourceNames: ["Fixture Sensor"]
            )
        ] + days.dropFirst(2).map {
            DailyGlucoseValue(
                day: $0,
                averageMillimolesPerLiter: nil,
                minimumMillimolesPerLiter: nil,
                maximumMillimolesPerLiter: nil,
                sourceNames: []
            )
        }))

        XCTAssertEqual(summary.averageMillimolesPerLiter, 7, accuracy: 0.0001)
        XCTAssertEqual(summary.minimumMillimolesPerLiter, 3.5, accuracy: 0.0001)
        XCTAssertEqual(summary.maximumMillimolesPerLiter, 12, accuracy: 0.0001)
        XCTAssertEqual(summary.validDayCount, 2)
        XCTAssertEqual(summary.reportingDayCount, 7)
    }

    func testNoValidDailyValuesReturnsNil() {
        XCTAssertNil(GlucoseSummary.aggregate(reportDays().map {
            DailyGlucoseValue(
                day: $0,
                averageMillimolesPerLiter: nil,
                minimumMillimolesPerLiter: nil,
                maximumMillimolesPerLiter: nil,
                sourceNames: []
            )
        }))
    }

    private func reportDays() -> [DateInterval] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 25,
            hour: 9
        ))!
        return ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: now,
            calendar: calendar
        ).completedDays
    }
}
