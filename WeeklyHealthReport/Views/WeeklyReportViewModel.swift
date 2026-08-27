import Foundation

enum MetricState<Value: Equatable>: Equatable {
    case idle
    case loading
    case available(Value)
    case noDataOrAccess
    case healthUnavailable
    case failed(String)

    var value: Value? {
        if case .available(let value) = self { return value }
        return nil
    }
}

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

    typealias WeightState = MetricState<WeightTrendSummary>
    typealias BodyFatState = MetricState<BodyFatTrendSummary>

    @Published var selection: ReportPeriodSelection = .lastSevenCompletedDays
    @Published private(set) var period: ReportPeriod
    @Published private(set) var state: State = .idle
    @Published private(set) var weightState: WeightState = .idle
    @Published private(set) var bodyFatState: BodyFatState = .idle
    @Published private(set) var waistState: MetricState<WaistSummary> = .idle
    @Published private(set) var glucoseState: MetricState<GlucoseSummary> = .idle
    @Published private(set) var restingHeartRateState: MetricState<HeartMetricTrendSummary> = .idle
    @Published private(set) var hrvState: MetricState<HeartMetricTrendSummary> = .idle
    @Published private(set) var watchCoverageState: MetricState<WatchCoverageSummary> = .idle
    @Published private(set) var exerciseState: MetricState<Double> = .idle
    @Published private(set) var activeEnergyState: MetricState<Double> = .idle
    @Published private(set) var workoutState: MetricState<WorkoutSummary> = .idle
    @Published private(set) var sleepState: MetricState<SleepSummary> = .idle
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

    var reportSnapshot: WeeklyReportSnapshot {
        WeeklyReportSnapshot(
            period: period,
            weight: weightState.value,
            bodyFat: bodyFatState.value,
            waist: waistState.value,
            glucose: glucoseState.value,
            steps: {
                if case .loaded(let summary) = state { return summary }
                return nil
            }(),
            restingHeartRate: restingHeartRateState.value,
            hrv: hrvState.value,
            watchCoverage: watchCoverageState.value,
            sleep: sleepState.value,
            activeEnergyKilocalories: activeEnergyState.value,
            exerciseMinutes: exerciseState.value,
            workouts: workoutState.value
        )
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let refreshDate = now()
        period = ReportPeriod.make(selection: selection, now: refreshDate, calendar: calendar)
        setLoading()

        guard healthData.isHealthDataAvailable else {
            setHealthUnavailable()
            return
        }

        do {
            try await healthData.requestReadAuthorization()
        } catch let error as HealthDataError where error == .unavailable {
            guard generation == refreshGeneration else { return }
            setHealthUnavailable()
            return
        } catch {
            guard generation == refreshGeneration else { return }
            setAuthorizationFailure(error.localizedDescription)
            return
        }
        guard generation == refreshGeneration else { return }

        await loadContextMetrics(asOf: refreshDate, generation: generation)
        guard generation == refreshGeneration else { return }

        guard !period.completedDays.isEmpty else {
            state = .noCompletedDays
            glucoseState = .noDataOrAccess
            restingHeartRateState = .noDataOrAccess
            hrvState = .noDataOrAccess
            watchCoverageState = .noDataOrAccess
            exerciseState = .noDataOrAccess
            activeEnergyState = .noDataOrAccess
            workoutState = .noDataOrAccess
            sleepState = .noDataOrAccess
            lastRefreshed = refreshDate
            return
        }

        await loadPeriodMetrics(generation: generation)
        guard generation == refreshGeneration else { return }
        lastRefreshed = refreshDate
    }

    private func loadContextMetrics(asOf date: Date, generation: Int) async {
        do {
            let measurements = try await healthData.fetchWeightMeasurements(asOf: date)
            guard generation == refreshGeneration else { return }
            let summary = WeightTrendSummary.calculate(
                measurements: measurements,
                asOf: date,
                calendar: calendar
            )
            weightState = summary.map(WeightState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            weightState = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let measurements = try await healthData.fetchBodyFatMeasurements(asOf: date)
            guard generation == refreshGeneration else { return }
            let summary = BodyFatTrendSummary.calculate(
                measurements: measurements,
                asOf: date,
                calendar: calendar
            )
            bodyFatState = summary.map(BodyFatState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            bodyFatState = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let measurements = try await healthData.fetchWaistMeasurements(asOf: date)
            guard generation == refreshGeneration else { return }
            let summary = WaistSummary.calculate(
                measurements: measurements,
                asOf: date,
                calendar: calendar
            )
            waistState = summary.map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            waistState = .failed(error.localizedDescription)
        }
    }

    private func loadPeriodMetrics(generation: Int) async {
        guard let previousPeriod = period.precedingEquivalent(calendar: calendar) else {
            restingHeartRateState = .noDataOrAccess
            hrvState = .noDataOrAccess
            return
        }

        do {
            let values = try await healthData.fetchDailySteps(for: period)
            guard generation == refreshGeneration else { return }
            state = StepSummary.aggregate(values).map(State.loaded) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            state = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let dailyValues = try await healthData.fetchDailyBloodGlucose(for: period)
            guard generation == refreshGeneration else { return }
            glucoseState = GlucoseSummary.aggregate(dailyValues)
                .map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            glucoseState = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let currentValues = try await healthData.fetchDailyRestingHeartRate(for: period)
            let previousValues = try await healthData.fetchDailyRestingHeartRate(for: previousPeriod)
            guard generation == refreshGeneration else { return }
            restingHeartRateState = HeartMetricTrendSummary.calculate(
                currentValues: currentValues,
                previousValues: previousValues
            )
                .map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            restingHeartRateState = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let currentValues = try await healthData.fetchDailyHRV(for: period)
            let previousValues = try await healthData.fetchDailyHRV(for: previousPeriod)
            guard generation == refreshGeneration else { return }
            hrvState = HeartMetricTrendSummary.calculate(
                currentValues: currentValues,
                previousValues: previousValues
            )
                .map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            hrvState = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let sampleDates = try await healthData.fetchAppleWatchHeartRateSampleDates(for: period)
            guard generation == refreshGeneration else { return }
            watchCoverageState = WatchCoverageSummary.calculate(
                appleWatchSampleDates: sampleDates,
                period: period
            ).map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            watchCoverageState = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let minutes = try await healthData.fetchExerciseMinutes(for: period)
            guard generation == refreshGeneration else { return }
            exerciseState = minutes.map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            exerciseState = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let kilocalories = try await healthData.fetchActiveEnergyKilocalories(for: period)
            guard generation == refreshGeneration else { return }
            activeEnergyState = kilocalories.map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            activeEnergyState = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let workouts = try await healthData.fetchWorkouts(for: period)
            guard generation == refreshGeneration else { return }
            // HealthKit does not disclose read denial. An empty result could be
            // either zero workouts or no read visibility, so do not claim zero.
            workoutState = workouts.isEmpty
                ? .noDataOrAccess
                : .available(WorkoutSummary(workouts: workouts))
        } catch {
            guard generation == refreshGeneration else { return }
            workoutState = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let intervals = try await healthData.fetchAsleepIntervals(for: period, calendar: calendar)
            guard generation == refreshGeneration else { return }
            sleepState = SleepSummary.calculate(
                asleepIntervals: intervals,
                period: period,
                calendar: calendar
            ).map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            sleepState = .failed(error.localizedDescription)
        }
    }

    private func setLoading() {
        state = .loading
        weightState = .loading
        bodyFatState = .loading
        waistState = .loading
        glucoseState = .loading
        restingHeartRateState = .loading
        hrvState = .loading
        watchCoverageState = .loading
        exerciseState = .loading
        activeEnergyState = .loading
        workoutState = .loading
        sleepState = .loading
    }

    private func setHealthUnavailable() {
        state = .healthUnavailable
        weightState = .healthUnavailable
        bodyFatState = .healthUnavailable
        waistState = .healthUnavailable
        glucoseState = .healthUnavailable
        restingHeartRateState = .healthUnavailable
        hrvState = .healthUnavailable
        watchCoverageState = .healthUnavailable
        exerciseState = .healthUnavailable
        activeEnergyState = .healthUnavailable
        workoutState = .healthUnavailable
        sleepState = .healthUnavailable
    }

    private func setAuthorizationFailure(_ message: String) {
        state = .failed(message)
        weightState = .failed(message)
        bodyFatState = .failed(message)
        waistState = .failed(message)
        glucoseState = .failed(message)
        restingHeartRateState = .failed(message)
        hrvState = .failed(message)
        watchCoverageState = .failed(message)
        exerciseState = .failed(message)
        activeEnergyState = .failed(message)
        workoutState = .failed(message)
        sleepState = .failed(message)
    }
}
