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
}
