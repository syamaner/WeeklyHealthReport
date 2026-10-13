import XCTest
@testable import WeeklyHealthReport

// View-model tests for today_so_far_health_v1 (contract sections 5, 6 and 9).
@MainActor
final class TodaySoFarHealthModelTests: XCTestCase {
    func testAuthorisationIsRequestedOnceAcrossAppearancesAndRefreshFollows() async {
        let reader = FakeTodaySoFarReader()
        let authorizer = FakeReadAuthorizer(error: SyntheticError())
        let model = makeModel(reader: reader, authorizer: authorizer, dates: [at(9, 0), at(9, 5), at(9, 10)])

        await model.handle(.homeAppeared)
        await model.handle(.homeAppeared)
        await model.handle(.pullToRefresh)

        XCTAssertEqual(authorizer.requestCount, 1)
        XCTAssertEqual(reader.windows.count, 3, "a refresh follows even when authorisation throws")
        XCTAssertEqual(model.projection?.window.asOf, at(9, 10))
    }

    func testEveryTriggerRefreshesWithTheInjectedClock() async {
        let reader = FakeTodaySoFarReader()
        let dates = [at(9, 0), at(10, 0), at(11, 0), at(12, 0), at(13, 0)]
        let model = makeModel(reader: reader, dates: dates)

        for trigger: TodaySoFarHealthModel.Trigger in [.becameActive, .significantTimeChange, .calendarDayChanged, .pullToRefresh, .diagnostics] {
            await model.handle(trigger)
        }

        XCTAssertEqual(reader.windows.map(\.asOf), dates)
        XCTAssertEqual(model.projection?.window.asOf, at(13, 0))
        XCTAssertFalse(model.isRefreshing)
    }

    func testStaleGenerationIsDiscarded() async {
        let reader = FakeTodaySoFarReader()
        reader.suspendFirstRead = true
        let model = makeModel(reader: reader, dates: [at(9, 0), at(9, 30)])

        let first = Task { await model.handle(.pullToRefresh) }
        await reader.waitForSuspendedRead()
        await model.handle(.pullToRefresh)
        XCTAssertEqual(model.projection?.window.asOf, at(9, 30))

        reader.resumeSuspendedRead()
        await first.value
        XCTAssertEqual(model.projection?.window.asOf, at(9, 30), "the older refresh never overwrites the newer one")
    }

    /// Same failure mode as the report (#229): pull to refresh and the
    /// diagnostics `.task` are cancelled when their view goes away. A read that
    /// observes that cancellation must not be shown as failed.
    func testCallerCancellationMidReadIsNotShownAsFailed() async {
        let reader = FakeTodaySoFarReader()
        reader.inputs = TodaySoFarHealthInputs(
            steps: .value(DailyStepTotal(day: DateInterval(), steps: 4200, sourceNames: [])),
            activeEnergyKilocalories: .noData, asleepIntervals: .noData, weights: .noData, bloodPressure: .noData)
        reader.suspendFirstRead = true
        let model = makeModel(reader: reader, dates: [at(9, 0)])

        let caller = Task { await model.handle(.pullToRefresh) }
        await reader.waitForSuspendedRead()
        caller.cancel()
        reader.resumeSuspendedRead()
        await caller.value

        XCTAssertEqual(reader.cancelledReads, 0, "the read ran outside the cancelled caller")
        XCTAssertEqual(model.projection?.steps, .value(.init(count: 4200, sourceNames: [])))
        XCTAssertEqual(model.projection?.sleep, .noData)
        XCTAssertFalse(model.isRefreshing)
    }

    func testRolloverClearsThePreviousDayBeforeTheNewRead() async {
        let reader = FakeTodaySoFarReader()
        reader.inputs = TodaySoFarHealthInputs(
            steps: .value(DailyStepTotal(day: DateInterval(), steps: 9000, sourceNames: [])),
            activeEnergyKilocalories: .noData, asleepIntervals: .noData, weights: .noData, bloodPressure: .noData)
        let model = makeModel(reader: reader, dates: [at(23, 59), at(24, 1)])
        await model.handle(.becameActive)
        XCTAssertNotNil(model.projection)

        reader.suspendFirstRead = true
        reader.didSuspend = false
        let next = Task { await model.handle(.calendarDayChanged) }
        await reader.waitForSuspendedRead()
        XCTAssertNil(model.projection, "yesterday's values are not shown after midnight")
        XCTAssertTrue(model.isRefreshing)
        XCTAssertEqual(TodaySoFarHealthCard.make(projection: model.projection, windowFailed: model.windowFailed).content,
                       TodaySoFarHealthCard.make(projection: nil).content)
        reader.resumeSuspendedRead()
        await next.value
        XCTAssertEqual(model.projection?.window.day.start, at(24, 0))
    }

    /// Review fix: the report and Home asking at launch share one request.
    func testConcurrentCallersShareOneAuthorisationRequest() async throws {
        let base = SuspendingAuthorizer()
        let shared = SingleFlightReadAuthorization(base: base)
        let first = Task { try await shared.requestReadAuthorization() }
        await base.waitUntilRequested()
        let second = Task { try await shared.requestReadAuthorization() }
        while await shared.joinedCallers < 1 { await Task.yield() }
        base.finish()
        try await first.value
        try await second.value
        XCTAssertEqual(base.requestCount, 1)

        // A later caller starts a new request once the first has finished.
        let third = Task { try await shared.requestReadAuthorization() }
        await base.waitUntilRequested(count: 2)
        base.finish()
        try await third.value
        XCTAssertEqual(base.requestCount, 2)
    }

    func testSharedRequestPassesErrorsToEveryCaller() async {
        let shared = SingleFlightReadAuthorization(base: FakeReadAuthorizer(error: SyntheticError()))
        do {
            try await shared.requestReadAuthorization()
            XCTFail("Expected the synthetic error")
        } catch {
            XCTAssertTrue(error is SyntheticError)
        }
    }

    func testReportUsesTheSharedRequesterWhenGiven() async {
        let authorizer = FakeReadAuthorizer()
        let report = WeeklyReportViewModel(healthData: FakeHealthDataProvider(), readAuthorization: authorizer,
                                           calendar: calendar, now: { self.at(9, 0) })
        await report.refresh()
        XCTAssertEqual(authorizer.requestCount, 1)
    }

    // MARK: Helpers

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// 12 October 2026 at the given local time; hour 24 is the next day.
    private func at(_ hour: Int, _ minute: Int) -> Date {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: midnight)!
    }

    private func makeModel(
        reader: FakeTodaySoFarReader,
        authorizer: FakeReadAuthorizer = FakeReadAuthorizer(),
        dates: [Date]
    ) -> TodaySoFarHealthModel {
        let clock = FixtureClock(dates: dates)
        let calendar = calendar
        return TodaySoFarHealthModel(reader: reader, authorizer: authorizer, now: clock.now, calendar: { calendar })
    }
}

private struct SyntheticError: Error {}

/// A scripted today-so-far port, confined to the main actor like the model.
@MainActor
final class FakeTodaySoFarReader: TodaySoFarHealthReading {
    var inputs = TodaySoFarHealthInputs(
        steps: .noData, activeEnergyKilocalories: .noData, asleepIntervals: .noData, weights: .noData, bloodPressure: .noData)
    private(set) var windows: [TodaySoFarWindow] = []
    /// Reads that observed task cancellation and so returned every metric as
    /// failed, as `HealthKitClient.todaySoFarOutcome` maps a thrown error.
    private(set) var cancelledReads = 0
    var suspendFirstRead = false
    var didSuspend = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var suspendedWaiters: [CheckedContinuation<Void, Never>] = []

    func todaySoFarInputs(for window: TodaySoFarWindow) async -> TodaySoFarHealthInputs {
        windows.append(window)
        if suspendFirstRead, !didSuspend {
            didSuspend = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                suspendedWaiters.forEach { $0.resume() }
                suspendedWaiters = []
            }
        }
        if Task.isCancelled {
            cancelledReads += 1
            return TodaySoFarHealthInputs(
                steps: .failed, activeEnergyKilocalories: .failed, asleepIntervals: .failed,
                weights: .failed, bloodPressure: .failed)
        }
        return inputs
    }

    func waitForSuspendedRead() async {
        if continuation != nil { return }
        await withCheckedContinuation { suspendedWaiters.append($0) }
    }

    func resumeSuspendedRead() {
        continuation?.resume()
        continuation = nil
        suspendFirstRead = false
    }
}

/// Holds each request open until `finish()`, so concurrent callers overlap.
@MainActor
final class SuspendingAuthorizer: HealthReadAuthorizationRequesting {
    private(set) var requestCount = 0
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    nonisolated init() {}

    func requestReadAuthorization() async throws {
        requestCount += 1
        let ready = waiters.filter { $0.0 <= requestCount }
        waiters.removeAll { $0.0 <= requestCount }
        ready.forEach { $0.1.resume() }
        await withCheckedContinuation { pending.append($0) }
    }

    func waitUntilRequested(count: Int = 1) async {
        if requestCount >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func finish() {
        let resumed = pending
        pending = []
        resumed.forEach { $0.resume() }
    }
}

@MainActor
final class FakeReadAuthorizer: HealthReadAuthorizationRequesting {
    private let error: Error?
    private(set) var requestCount = 0

    nonisolated init(error: Error? = nil) { self.error = error }

    func requestReadAuthorization() async throws {
        requestCount += 1
        if let error { throw error }
    }
}
