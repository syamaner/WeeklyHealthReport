import XCTest
@testable import WeeklyHealthReport

final class WeightMeasurementTests: XCTestCase {
    func testLatestSelectsMostRecentMeasurementFromUnsortedInput() {
        let oldest = WeightMeasurement(
            date: Date(timeIntervalSinceReferenceDate: 100),
            kilograms: 101.2
        )
        let latest = WeightMeasurement(
            date: Date(timeIntervalSinceReferenceDate: 300),
            kilograms: 100.6
        )
        let middle = WeightMeasurement(
            date: Date(timeIntervalSinceReferenceDate: 200),
            kilograms: 100.9
        )

        XCTAssertEqual(WeightMeasurement.latest(in: [middle, oldest, latest]), latest)
    }

    func testLatestReturnsNilForNoMeasurements() {
        XCTAssertNil(WeightMeasurement.latest(in: []))
    }

    func testWeightFormattingUsesOneDecimalPlaceAndKilograms() {
        let value = HealthReportFormatter.weightKilograms(
            100.64,
            locale: Locale(identifier: "en_GB")
        )

        XCTAssertEqual(value, "100.6 kg")
    }

    func testWeightTrendUsesDailyMeansAndPreviousSevenCompletedDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 9))!
        func sample(daysBeforeToday: Int, kilograms: Double, hour: Int = 8) -> WeightMeasurement {
            let today = calendar.startOfDay(for: asOf)
            let day = calendar.date(byAdding: .day, value: -daysBeforeToday, to: today)!
            return WeightMeasurement(
                date: calendar.date(byAdding: .hour, value: hour, to: day)!,
                kilograms: kilograms
            )
        }
        let measurements = [
            sample(daysBeforeToday: 1, kilograms: 100),
            sample(daysBeforeToday: 1, kilograms: 102, hour: 9),
            sample(daysBeforeToday: 2, kilograms: 100),
            sample(daysBeforeToday: 3, kilograms: 99),
            sample(daysBeforeToday: 8, kilograms: 102),
            sample(daysBeforeToday: 9, kilograms: 101),
            sample(daysBeforeToday: 10, kilograms: 103),
            sample(daysBeforeToday: 0, kilograms: 98)
        ]

        let summary = try XCTUnwrap(WeightTrendSummary.calculate(
            measurements: measurements,
            asOf: asOf,
            calendar: calendar
        ))
        XCTAssertEqual(summary.latest.kilograms, 98, accuracy: 0.0001)
        XCTAssertEqual(summary.currentSevenDayAverage ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(summary.previousSevenDayAverage ?? 0, 102, accuracy: 0.0001)
        XCTAssertEqual(summary.trendKilograms ?? 0, -2, accuracy: 0.0001)
    }

    func testWeightTrendRequiresThreeSampledDaysPerWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 9))!
        let summary = try XCTUnwrap(WeightTrendSummary.calculate(
            measurements: [WeightMeasurement(date: asOf, kilograms: 100)],
            asOf: asOf,
            calendar: calendar
        ))
        XCTAssertNil(summary.currentSevenDayAverage)
        XCTAssertNil(summary.trendKilograms)
    }
}
