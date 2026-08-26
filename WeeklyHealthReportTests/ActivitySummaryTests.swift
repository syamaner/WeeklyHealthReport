import XCTest
@testable import WeeklyHealthReport

// All health values in this test file are synthetic fixtures.
final class ActivitySummaryTests: XCTestCase {
    func testWorkoutCountAndDurationTotal() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = WorkoutSummary(workouts: [
            WorkoutRecord(id: UUID(), startDate: start, duration: 31 * 60, activityName: "Walking"),
            WorkoutRecord(id: UUID(), startDate: start, duration: 18 * 60, activityName: "Strength"),
            WorkoutRecord(id: UUID(), startDate: start, duration: 55 * 60, activityName: "Walking")
        ])

        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.totalDuration, 104 * 60, accuracy: 0.001)
    }

    func testEmptyWorkoutSummaryHasZeroCountInternally() {
        let summary = WorkoutSummary(workouts: [])
        XCTAssertEqual(summary.count, 0)
        XCTAssertEqual(summary.totalDuration, 0)
    }
}
