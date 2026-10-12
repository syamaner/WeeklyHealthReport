import Combine
import Foundation

/// Read authorisation as Home needs it. `HealthKitClient` already provides
/// it with the same read set and an empty `toShare`.
protocol HealthReadAuthorizationRequesting: Sendable {
    func requestReadAuthorization() async throws
}

/// Shares one in-flight read-authorisation request between callers (the
/// report and Home both ask on launch). A caller arriving while a request is
/// running awaits that request and its outcome; a later caller starts a new
/// one. The wrapped requester decides the read set; `toShare` stays empty.
actor SingleFlightReadAuthorization: HealthReadAuthorizationRequesting {
    private let base: HealthReadAuthorizationRequesting
    private var inFlight: Task<Void, Error>?
    /// Callers that joined a running request instead of starting one (for tests).
    private(set) var joinedCallers = 0

    init(base: HealthReadAuthorizationRequesting) {
        self.base = base
    }

    func requestReadAuthorization() async throws {
        if let inFlight {
            joinedCallers += 1
            return try await inFlight.value
        }
        let base = base
        let task = Task { try await base.requestReadAuthorization() }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }
}

/// Orchestrates Home's today-so-far health card (contract sections 5 and 6):
/// one injected clock and calendar, authorisation at most once per session,
/// and a generation so an older refresh never overwrites a newer one.
@MainActor
final class TodaySoFarHealthModel: ObservableObject {
    /// What caused a refresh. Views forward lifecycle events; the model owns
    /// the response, so there are no timers, observers or polling.
    enum Trigger: Equatable {
        case homeAppeared
        case becameActive
        case significantTimeChange
        case calendarDayChanged
        case pullToRefresh
        case diagnostics
    }

    @Published private(set) var projection: TodaySoFarHealthProjection?
    @Published private(set) var isRefreshing = false
    /// True when the window could not be computed for the supplied calendar.
    @Published private(set) var windowFailed = false

    private let reader: TodaySoFarHealthReading
    private let authorizer: HealthReadAuthorizationRequesting
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var hasRequestedAuthorization = false
    private var generation = 0

    init(
        reader: TodaySoFarHealthReading,
        authorizer: HealthReadAuthorizationRequesting,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .autoupdatingCurrent }
    ) {
        self.reader = reader
        self.authorizer = authorizer
        self.now = now
        self.calendar = calendar
    }

    func handle(_ trigger: Trigger) async {
        if trigger == .homeAppeared, !hasRequestedAuthorization {
            hasRequestedAuthorization = true
            // A completed sheet says nothing about read access; refresh either way.
            try? await authorizer.requestReadAuthorization()
        }
        await refresh()
    }

    private func refresh() async {
        generation += 1
        let current = generation
        guard let window = TodaySoFarWindow.capture(at: now(), calendar: calendar()) else {
            projection = nil
            windowFailed = true
            isRefreshing = false
            return
        }
        windowFailed = false
        // A value from an earlier day is never shown after rollover.
        if let shown = projection, shown.window.day.start != window.day.start
            || shown.window.calendar.timeZone != window.calendar.timeZone {
            projection = nil
        }
        isRefreshing = true
        let inputs = await reader.todaySoFarInputs(for: window)
        guard current == generation else { return }
        projection = TodaySoFarHealthProjection.make(inputs: inputs, window: window)
        isRefreshing = false
    }
}
