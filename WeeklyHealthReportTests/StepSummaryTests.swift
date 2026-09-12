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
