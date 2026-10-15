import XCTest
@testable import WeeklyHealthReport

/// Contract tests for daily-export-included-summary-v1 (#217): counting rules
/// and the last export line. Synthetic fixtures only.
final class DailyExportIncludedSummaryTests: XCTestCase {
    // MARK: - Metric counts

    func testMetricOrderAndDenominatorCoverFifteenEntries() {
        var availabilities = Array(repeating: ExportAvailability.noDataOrAccess, count: 15)
        for index in availabilities.indices {
            availabilities[index] = .available
            let today = metrics(availabilities)
            XCTAssertEqual(DailyExportIncludedSummary.metricAvailabilities(today), availabilities)
            availabilities[index] = .noDataOrAccess
        }
        let summary = DailyExportIncludedSummary.make(today: metrics(availabilities))
        XCTAssertEqual(summary.metricsApplicable, 15)
        XCTAssertEqual(summary.metricsWithData, 0)
    }

    func testUnsupportedEntriesAreLeftOutOfTheDenominator() {
        var availabilities = Array(repeating: ExportAvailability.available, count: 9)
            + Array(repeating: .noDataOrAccess, count: 5)
        availabilities.append(.unsupported) // medications before iOS 26
        let summary = DailyExportIncludedSummary.make(today: metrics(availabilities, workouts: .available, workoutCount: 2))

        XCTAssertEqual(summary.metricsWithData, 9)
        XCTAssertEqual(summary.metricsApplicable, 14)
        XCTAssertEqual(summary.metricsText, "9 of 14 metrics have data")
        XCTAssertEqual(summary.line, "Health · 9 of 14 metrics have data · 2 workouts")
    }

    func testInsufficientDataIsApplicableButNotCountedAsData() {
        var availabilities = Array(repeating: ExportAvailability.available, count: 14)
        availabilities.append(.insufficientData)
        let summary = DailyExportIncludedSummary.make(today: metrics(availabilities))
        XCTAssertEqual(summary.metricsWithData, 14)
        XCTAssertEqual(summary.metricsApplicable, 15)
    }

    func testAllNoDataShowsTheNoAccessLineNotZero() {
        let summary = DailyExportIncludedSummary.make(
            today: metrics(Array(repeating: .noDataOrAccess, count: 15))
        )
        XCTAssertEqual(summary.metricsWithData, 0)
        XCTAssertEqual(summary.metricsText, "No Health data visible for this day, or no access")
        XCTAssertFalse(summary.line.contains("0 of"))
    }

    func testAllUnsupportedShowsTheNoAccessLine() {
        let summary = DailyExportIncludedSummary.make(
            today: metrics(Array(repeating: .unsupported, count: 15))
        )
        XCTAssertEqual(summary.metricsApplicable, 0)
        XCTAssertEqual(summary.metricsText, DailyExportIncludedSummary.noMetricsText)
    }

    func testNutritionNotesAndWorkoutsAreNotMetrics() {
        let today = metrics(
            Array(repeating: .noDataOrAccess, count: 15),
            workouts: .available,
            workoutCount: 3,
            notes: ["Invented note"]
        )
        let summary = DailyExportIncludedSummary.make(today: today)
        XCTAssertEqual(summary.metricsWithData, 0)
        XCTAssertEqual(summary.metricsApplicable, 15)
        XCTAssertEqual(summary.workouts, 3)
    }

    // MARK: - Workouts

    func testWorkoutCounts() {
        let base = Array(repeating: ExportAvailability.available, count: 15)
        XCTAssertEqual(
            DailyExportIncludedSummary.make(today: metrics(base, workouts: .available, workoutCount: 1)).workoutsText,
            "1 workout"
        )
        XCTAssertEqual(
            DailyExportIncludedSummary.make(today: metrics(base, workouts: .available, workoutCount: 2)).workoutsText,
            "2 workouts"
        )
    }

    func testNoWorkoutsIsNeverZeroWorkouts() {
        let base = Array(repeating: ExportAvailability.available, count: 15)
        let empty = DailyExportIncludedSummary.make(today: metrics(base, workouts: .available, workoutCount: 0))
        let noAccess = DailyExportIncludedSummary.make(today: metrics(base, workouts: .noDataOrAccess))
        XCTAssertEqual(empty.workouts, 0)
        XCTAssertNil(noAccess.workouts)
        for summary in [empty, noAccess] {
            XCTAssertEqual(summary.workoutsText, "no workouts visible")
            XCTAssertFalse(summary.line.contains("0 workouts"))
        }
        XCTAssertEqual(noAccess.line, "Health · 15 of 15 metrics have data · no workouts visible")
    }

    // MARK: - Last export line

    func testLastExportNoneSaysThisIPhone() {
        XCTAssertEqual(
            DailyExportLastExportFormatter.line(.none, calendar: london),
            "Last export of this day from this iPhone: none"
        )
    }

    func testLastExportUnknown() {
        XCTAssertEqual(
            DailyExportLastExportFormatter.line(.unknown, calendar: london),
            "Last export of this day: unknown"
        )
    }

    func testLastExportVerifiedShowsVerificationTimeAndCutoff() throws {
        let verifiedAt = try XCTUnwrap(iso("2026-10-11T13:05:00+01:00"))
        XCTAssertEqual(
            DailyExportLastExportFormatter.line(
                .verified(verifiedAt: verifiedAt, dataAsOf: "2026-10-11T13:02:00+01:00"),
                calendar: london
            ),
            "Last export of this day: 11/10/26 - 13:05, data up to 13:02"
        )
    }

    func testLastExportOfAnEarlierDayShowsTheFullCutoff() throws {
        let verifiedAt = try XCTUnwrap(iso("2026-10-12T09:00:00+01:00"))
        XCTAssertEqual(
            DailyExportLastExportFormatter.line(
                .verified(
                    verifiedAt: verifiedAt,
                    dataAsOf: "historical-v2|2026-10-12T00:00:00+01:00|2026-10-12T08:59:00+01:00"
                ),
                calendar: london
            ),
            "Last export of this day: 12/10/26 - 09:00, data up to 12/10/26 - 00:00"
        )
    }

    func testDeveloperFieldsShowRawRecordWithoutIdentifiers() throws {
        let verifiedAt = try XCTUnwrap(iso("2026-10-11T13:05:00+01:00"))
        let fields = DailyExportLastExportFormatter.developerFields(DailyExportLastExportLookup(
            reportDate: "2026-10-11",
            state: .verified(verifiedAt: verifiedAt, dataAsOf: "2026-10-11T13:02:00+01:00"),
            hasPendingOperation: true
        ))
        XCTAssertEqual(fields.map(\.label), ["Selected day", "Data as of token", "Verified at", "Pending operation"])
        XCTAssertEqual(fields.map(\.value), ["2026-10-11", "2026-10-11T13:02:00+01:00", "2026-10-11T12:05:00Z", "Yes"])
    }

    // MARK: - Fixtures

    private var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func iso(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func metric<Value>(_ availability: ExportAvailability) -> ExportMetric<Value> {
        ExportMetric(availability: availability, data: nil)
    }

    /// `availabilities` follows the contract order of the 15 entries.
    private func metrics(
        _ availabilities: [ExportAvailability],
        workouts: ExportAvailability = .noDataOrAccess,
        workoutCount: Int = 0,
        notes: [String]? = nil
    ) -> DailyHealthMetrics {
        precondition(availabilities.count == 15)
        let a = availabilities
        let workoutData = (0..<workoutCount).map {
            DailyWorkoutData(
                recordID: "invented-workout-\($0)",
                activity: "walking",
                startedAt: "2026-10-11T08:00:00+01:00",
                durationSeconds: 600
            )
        }
        return DailyHealthMetrics(
            notes: notes,
            weight: metric(a[0]),
            bodyFat: metric(a[1]),
            waist: metric(a[2]),
            bloodPressure: metric(a[3]),
            glucose: metric(a[4]),
            restingHeartRate: metric(a[5]),
            hrv: metric(a[6]),
            bloodOxygen: metric(a[7]),
            vo2Max: metric(a[8]),
            sleep: metric(a[9]),
            activity: DailyActivityData(steps: metric(a[10]), activeEnergy: metric(a[11]), exercise: metric(a[12])),
            workouts: ExportMetric(availability: workouts, data: workouts == .available ? workoutData : nil),
            watchCoverage: metric(a[13]),
            medications: metric(a[14]),
            nutrition: nil
        )
    }
}
