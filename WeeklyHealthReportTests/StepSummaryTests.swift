import XCTest
@testable import WeeklyHealthReport

final class StepSummaryTests: XCTestCase {
    func testAverageUsesEveryCompletedDayAsDenominator() {
        let totals = [
            daily(offset: 0, steps: 100),
            daily(offset: 1, steps: nil),
            daily(offset: 2, steps: 200)
        ]

        let summary = StepSummary.aggregate(totals)

        XCTAssertEqual(summary?.totalSteps, 300)
        XCTAssertEqual(summary?.averageDailySteps, 100)
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
