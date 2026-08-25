import Foundation

@MainActor
final class WeeklyReportViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(StepSummary)
        case noCompletedDays
        case noDataOrAccess
        case healthUnavailable
        case failed(String)
    }

    @Published var selection: ReportPeriodSelection = .lastSevenCompletedDays
    @Published private(set) var period: ReportPeriod
    @Published private(set) var state: State = .idle
    @Published private(set) var lastRefreshed: Date?

    private let healthData: HealthDataProviding
    private let calendar: Calendar
    private let now: () -> Date
    private var refreshGeneration = 0

    init(
        healthData: HealthDataProviding = HealthKitClient(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.healthData = healthData
        self.calendar = calendar
        self.now = now
        self.period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: now(),
            calendar: calendar
        )
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        state = .loading
        period = ReportPeriod.make(selection: selection, now: now(), calendar: calendar)

        guard healthData.isHealthDataAvailable else {
            state = .healthUnavailable
            return
        }
        guard !period.completedDays.isEmpty else {
            state = .noCompletedDays
            return
        }

        do {
            try await healthData.requestReadAuthorization()
            guard generation == refreshGeneration else { return }
            let dailyTotals = try await healthData.fetchDailySteps(for: period)
            guard generation == refreshGeneration else { return }
            if let summary = StepSummary.aggregate(dailyTotals) {
                state = .loaded(summary)
                lastRefreshed = now()
            } else {
                state = .noDataOrAccess
            }
        } catch let error as HealthDataError where error == .unavailable {
            guard generation == refreshGeneration else { return }
            state = .healthUnavailable
        } catch {
            guard generation == refreshGeneration else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

extension HealthDataError: Equatable {}
