import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
final class BodyCompositionTests: XCTestCase {
    func testHealthKitBodyFatFractionConvertsToPercentagePoints() {
        XCTAssertEqual(
            BodyFatMeasurement.percentagePoints(fromHealthKitFraction: 0.30),
            30.0,
            accuracy: 0.0001
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    func testBodyFatDailyAggregationPreventsRepeatedSamplesDominatingSevenDayAverage() throws {
        let measurements = [
            bodyFat(2026, 8, 20, 8, 24.0),
            bodyFat(2026, 8, 24, 8, 25.0),
            bodyFat(2026, 8, 24, 9, 27.0)
        ]

        let summary = try XCTUnwrap(BodyFatTrendSummary.calculate(
            measurements: measurements,
            asOf: date(2026, 8, 25, 12),
            calendar: calendar
        ))

        XCTAssertEqual(summary.dailyValues.count, 2)
        XCTAssertEqual(try XCTUnwrap(summary.dailyValues.last).percentage, 26.0, accuracy: 0.0001)
        XCTAssertEqual(summary.dailyValues.last?.sampleCount, 2)
        XCTAssertEqual(try XCTUnwrap(summary.sevenDayAverage), 25.0, accuracy: 0.0001)
        XCTAssertEqual(summary.latest.percentage, 27.0, accuracy: 0.0001)
    }

    func testBodyFatCurrentAndPrevious28DayAveragesAndTrend() throws {
        let measurements = [
            bodyFat(2026, 7, 5, 8, 28.0),
            bodyFat(2026, 7, 20, 8, 27.0),
            bodyFat(2026, 8, 1, 8, 27.0),
            bodyFat(2026, 8, 20, 8, 26.0)
        ]

        let summary = try XCTUnwrap(BodyFatTrendSummary.calculate(
            measurements: measurements,
            asOf: date(2026, 8, 25, 12),
            calendar: calendar
        ))

        XCTAssertEqual(try XCTUnwrap(summary.current28DayAverage), 26.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(summary.previous28DayAverage), 27.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(summary.trendPercentagePoints), -1.0, accuracy: 0.0001)
    }

    func testBodyFatAverageRequiresTwoDistinctSampledDays() {
        let summary = BodyFatTrendSummary.calculate(
            measurements: [bodyFat(2026, 8, 24, 8, 26.4)],
            asOf: date(2026, 8, 25, 12),
            calendar: calendar
        )

        XCTAssertNotNil(summary)
        XCTAssertNil(summary?.sevenDayAverage)
        XCTAssertNil(summary?.current28DayAverage)
        XCTAssertNil(summary?.trendPercentagePoints)
    }

    func testBodyCompositionFormatting() {
        let locale = Locale(identifier: "en_GB")

        XCTAssertEqual(HealthReportFormatter.percentage(26.44, locale: locale), "26.4%")
        XCTAssertEqual(
            HealthReportFormatter.percentagePointTrend(-0.66, locale: locale),
            "↓ 0.7 pp vs previous 28d"
        )
    }

    private func bodyFat(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ percentage: Double
    ) -> BodyFatMeasurement {
        BodyFatMeasurement(date: date(year, month, day, hour), percentage: percentage)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
