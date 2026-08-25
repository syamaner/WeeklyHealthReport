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

    enum WeightState: Equatable {
        case idle
        case loading
        case available(WeightMeasurement)
        case noDataOrAccess
        case healthUnavailable
        case failed(String)
    }

    enum BodyFatState: Equatable {
        case idle
        case loading
        case available(BodyFatTrendSummary)
        case noDataOrAccess
        case healthUnavailable
        case failed(String)
    }

    enum BMIState: Equatable {
        case idle
        case loading
        case available(BMIMeasurement)
        case noDataOrAccess
        case healthUnavailable
        case failed(String)
    }

    @Published var selection: ReportPeriodSelection = .lastSevenCompletedDays
    @Published private(set) var period: ReportPeriod
    @Published private(set) var state: State = .idle
    @Published private(set) var weightState: WeightState = .idle
    @Published private(set) var bodyFatState: BodyFatState = .idle
    @Published private(set) var bmiState: BMIState = .idle
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
        let refreshDate = now()
        state = .loading
        weightState = .loading
        bodyFatState = .loading
        bmiState = .loading
        period = ReportPeriod.make(selection: selection, now: refreshDate, calendar: calendar)

        guard healthData.isHealthDataAvailable else {
            state = .healthUnavailable
            weightState = .healthUnavailable
            bodyFatState = .healthUnavailable
            bmiState = .healthUnavailable
            return
        }

        do {
            try await healthData.requestReadAuthorization()
        } catch let error as HealthDataError where error == .unavailable {
            guard generation == refreshGeneration else { return }
            state = .healthUnavailable
            weightState = .healthUnavailable
            bodyFatState = .healthUnavailable
            bmiState = .healthUnavailable
            return
        } catch {
            guard generation == refreshGeneration else { return }
            state = .failed(error.localizedDescription)
            weightState = .failed(error.localizedDescription)
            bodyFatState = .failed(error.localizedDescription)
            bmiState = .failed(error.localizedDescription)
            return
        }
        guard generation == refreshGeneration else { return }

        do {
            let measurement = try await healthData.fetchLatestWeight(asOf: refreshDate)
            guard generation == refreshGeneration else { return }
            weightState = measurement.map(WeightState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            weightState = .failed(error.localizedDescription)
        }

        do {
            let measurements = try await healthData.fetchBodyFatMeasurements(asOf: refreshDate)
            guard generation == refreshGeneration else { return }
            let summary = BodyFatTrendSummary.calculate(
                measurements: measurements,
                asOf: refreshDate,
                calendar: calendar
            )
            bodyFatState = summary.map(BodyFatState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            bodyFatState = .failed(error.localizedDescription)
        }

        do {
            let measurement = try await healthData.fetchLatestBMI(asOf: refreshDate)
            guard generation == refreshGeneration else { return }
            bmiState = measurement.map(BMIState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            bmiState = .failed(error.localizedDescription)
        }

        guard !period.completedDays.isEmpty else {
            state = .noCompletedDays
            return
        }

        do {
            let dailyTotals = try await healthData.fetchDailySteps(for: period)
            guard generation == refreshGeneration else { return }
            if let summary = StepSummary.aggregate(dailyTotals) {
                state = .loaded(summary)
                lastRefreshed = refreshDate
            } else {
                state = .noDataOrAccess
            }
        } catch {
            guard generation == refreshGeneration else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

extension HealthDataError: Equatable {}
