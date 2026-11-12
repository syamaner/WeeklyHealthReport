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

// Every value here is invented (#469).
final class GlucoseReadingsProjectionTests: XCTestCase {
    private let window = DateInterval(
        start: Date(timeIntervalSinceReferenceDate: 800_000_000),
        duration: 86_400
    )

    private func sample(
        _ offset: TimeInterval,
        _ value: Double = 5.2,
        source: String = "example.sensor.a",
        name: String = "Fixture Sensor A",
        id: UInt8 = 1,
        duration: TimeInterval = 0,
        count: Int = 1
    ) -> GlucoseReadingSample {
        let start = window.start.addingTimeInterval(offset)
        return GlucoseReadingSample(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)),
            start: start,
            end: start.addingTimeInterval(duration),
            quantityCount: count,
            millimolesPerLiter: value,
            sourceName: name,
            sourceBundleIdentifier: source
        )
    }

    private func series(_ outcome: GlucoseReadingsProjection.Outcome) throws -> [GlucoseReadingsProjection.Series] {
        guard case .available(let series) = outcome else {
            XCTFail("Expected available, got \(outcome)")
            return []
        }
        return series
    }

    func testAnEmptyReadIsNoVisibleDataNeverZeroReadings() {
        XCTAssertEqual(GlucoseReadingsProjection.project([], in: window), .noDataOrAccess)
    }

    func testReadingsAreOrderedByTimeAndGapsStayGaps() throws {
        // 08:00, 08:05, then nothing until 12:00: three readings, no filler.
        let result = try series(GlucoseReadingsProjection.project(
            [sample(43_200, 6.1, id: 3), sample(28_800, 5.0, id: 1), sample(29_100, 5.4, id: 2)],
            in: window
        ))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].readings.map(\.millimolesPerLiter), [5.0, 5.4, 6.1])
    }

    func testOverlappingSourcesStaySeparateSeriesOrderedByBundleIdentifier() throws {
        let result = try series(GlucoseReadingsProjection.project(
            [
                sample(600, 5.1, source: "example.sensor.b", name: "Fixture Sensor B", id: 1),
                sample(600, 5.3, source: "example.sensor.a", name: "Fixture Sensor A", id: 2),
                sample(900, 5.2, source: "example.sensor.b", name: "Fixture Sensor B", id: 3)
            ],
            in: window
        ))
        XCTAssertEqual(result.map(\.sourceBundleIdentifier), ["example.sensor.a", "example.sensor.b"])
        XCTAssertEqual(result.map(\.readings.count), [1, 2])
    }

    func testSameSourceAndTimeIsKeptTwiceInDeterministicOrder() throws {
        let forwards = try series(GlucoseReadingsProjection.project(
            [sample(600, 5.4, id: 2), sample(600, 5.4, id: 1), sample(600, 5.1, id: 3)], in: window
        ))
        let backwards = try series(GlucoseReadingsProjection.project(
            [sample(600, 5.1, id: 3), sample(600, 5.4, id: 1), sample(600, 5.4, id: 2)], in: window
        ))
        XCTAssertEqual(forwards, backwards)
        XCTAssertEqual(forwards[0].readings.map(\.millimolesPerLiter), [5.1, 5.4, 5.4])
        XCTAssertEqual(forwards[0].readings.map(\.id.uuid.15), [3, 1, 2])
    }

    func testWindowIncludesItsStartAndExcludesItsEnd() throws {
        let result = try series(GlucoseReadingsProjection.project(
            [sample(-1, 4.0, id: 1), sample(0, 5.0, id: 2), sample(86_399, 6.0, id: 3), sample(86_400, 7.0, id: 4)],
            in: window
        ))
        XCTAssertEqual(result[0].readings.map(\.millimolesPerLiter), [5.0, 6.0])
        // Only readings outside the window: nothing visible for this day.
        XCTAssertEqual(
            GlucoseReadingsProjection.project([sample(-1), sample(86_400)], in: window),
            .noDataOrAccess
        )
    }

    func testTheBoundIsInclusiveAndOneMoreExportsNoPartialList() throws {
        let bound = GlucoseReadingsPolicy.maximumReadingsPerDay
        let atBound = (0..<bound).map { sample(TimeInterval($0), id: UInt8($0 % 250)) }
        XCTAssertEqual(try series(GlucoseReadingsProjection.project(atBound, in: window))[0].readings.count, bound)
        XCTAssertEqual(
            GlucoseReadingsProjection.project(atBound + [sample(TimeInterval(bound))], in: window),
            .limitExceeded
        )
    }

    func testASeriesSampleOrASampleWithADurationIsNotAPointReading() {
        XCTAssertEqual(GlucoseReadingsProjection.project([sample(600), sample(900, count: 2)], in: window), .invalidEvidence)
        XCTAssertEqual(GlucoseReadingsProjection.project([sample(600), sample(900, duration: 60)], in: window), .invalidEvidence)
    }

    func testUnusableValuesAndMissingSourceIdentityAreInvalidEvidence() {
        for value in [0, -1, Double.nan, Double.infinity] {
            XCTAssertEqual(GlucoseReadingsProjection.project([sample(600, value)], in: window), .invalidEvidence)
        }
        XCTAssertEqual(GlucoseReadingsProjection.project([sample(600, source: " ")], in: window), .invalidEvidence)
        XCTAssertEqual(GlucoseReadingsProjection.project([sample(600, name: "")], in: window), .invalidEvidence)
        // A malformed sample outside the window does not affect this day.
        XCTAssertEqual(
            GlucoseReadingsProjection.project([sample(600), sample(-60, count: 2)], in: window),
            .available([.init(sourceName: "Fixture Sensor A", sourceBundleIdentifier: "example.sensor.a", readings: [sample(600)])])
        )
    }
}
