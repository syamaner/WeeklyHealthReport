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

    private enum CommonReportState {
        case idle
        case loading
        case healthUnavailable
        case failed(String)

        var stepState: State {
            switch self {
            case .idle:
                .idle
            case .loading:
                .loading
            case .healthUnavailable:
                .healthUnavailable
            case .failed(let message):
                .failed(message)
            }
        }

        func metricState<Value>() -> MetricState<Value> {
            switch self {
            case .idle:
                .idle
            case .loading:
                .loading
            case .healthUnavailable:
                .healthUnavailable
            case .failed(let message):
                .failed(message)
            }
        }
    }

    private struct ReportStates: Equatable {
        var steps: State
        var weight: WeightState
        var bodyFat: BodyFatState
        var waist: MetricState<WaistSummary>
        var glucose: MetricState<GlucoseSummary>
        var vo2Max: MetricState<VO2MaxSummary>
        var bloodOxygen: MetricState<BloodOxygenSummary>
        var bloodPressure: MetricState<BloodPressureSummary>
        var restingHeartRate: MetricState<HeartMetricTrendSummary>
        var hrv: MetricState<HeartMetricTrendSummary>
        var watchCoverage: MetricState<WatchCoverageSummary>
        var exercise: MetricState<Double>
        var activeEnergy: MetricState<Double>
        var workouts: MetricState<WorkoutSummary>
        var sleep: MetricState<SleepSummary>
        var medications: MetricState<MedicationSummary>

        init(commonState: CommonReportState) {
            steps = commonState.stepState
            weight = commonState.metricState()
            bodyFat = commonState.metricState()
            waist = commonState.metricState()
            glucose = commonState.metricState()
            vo2Max = commonState.metricState()
            bloodOxygen = commonState.metricState()
            bloodPressure = commonState.metricState()
            restingHeartRate = commonState.metricState()
            hrv = commonState.metricState()
            watchCoverage = commonState.metricState()
            exercise = commonState.metricState()
            activeEnergy = commonState.metricState()
            workouts = commonState.metricState()
            sleep = commonState.metricState()
            medications = commonState.metricState()
        }

        func snapshot(period: ReportPeriod) -> WeeklyReportSnapshot {
            WeeklyReportSnapshot(
                period: period,
                weight: weight.value,
                bodyFat: bodyFat.value,
                waist: waist.value,
                glucose: glucose.value,
                vo2Max: vo2Max.value,
                bloodOxygen: bloodOxygen.value,
                bloodPressure: bloodPressure.value,
                steps: {
                    if case .loaded(let summary) = steps { return summary }
                    return nil
                }(),
                restingHeartRate: restingHeartRate.value,
                hrv: hrv.value,
                watchCoverage: watchCoverage.value,
                sleep: sleep.value,
                activeEnergyKilocalories: activeEnergy.value,
                exerciseMinutes: exercise.value,
                workouts: workouts.value,
                medications: medications.value
            )
        }
    }

    @Published var selection: ReportPeriodSelection = .lastSevenCompletedDays
    @Published private(set) var period: ReportPeriod
    @Published private var reportStates = ReportStates(commonState: .idle)
    @Published private(set) var lastRefreshed: Date?

    var state: State { reportStates.steps }
    var weightState: WeightState { reportStates.weight }
    var bodyFatState: BodyFatState { reportStates.bodyFat }
    var waistState: MetricState<WaistSummary> { reportStates.waist }
    var glucoseState: MetricState<GlucoseSummary> { reportStates.glucose }
    var vo2MaxState: MetricState<VO2MaxSummary> { reportStates.vo2Max }
    var bloodOxygenState: MetricState<BloodOxygenSummary> { reportStates.bloodOxygen }
    var bloodPressureState: MetricState<BloodPressureSummary> { reportStates.bloodPressure }
    var restingHeartRateState: MetricState<HeartMetricTrendSummary> {
        reportStates.restingHeartRate
    }
    var hrvState: MetricState<HeartMetricTrendSummary> { reportStates.hrv }
    var watchCoverageState: MetricState<WatchCoverageSummary> { reportStates.watchCoverage }
    var exerciseState: MetricState<Double> { reportStates.exercise }
    var activeEnergyState: MetricState<Double> { reportStates.activeEnergy }
    var workoutState: MetricState<WorkoutSummary> { reportStates.workouts }
    var sleepState: MetricState<SleepSummary> { reportStates.sleep }
    var medicationState: MetricState<MedicationSummary> { reportStates.medications }

    private let healthData: HealthDataProviding
    private let calendar: Calendar
    private let now: () -> Date
    private var refreshGeneration = 0
    private var activeRefreshGeneration: Int?
    private var medicationRefreshGeneration = 0
    private var activeMedicationRefreshGeneration: Int?

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
        reportStates.snapshot(period: period)
    }

    var supportsMedicationData: Bool { healthData.supportsMedicationData }

    func screenshotSnapshot(
        includesMedicationSection: Bool,
        showsMorningBloodPressureDetails: Bool,
        showsEveningBloodPressureDetails: Bool
    ) -> WeeklyReportScreenshotSnapshot? {
        guard activeRefreshGeneration == nil,
              activeMedicationRefreshGeneration == nil,
              period.selection == selection else {
            return nil
        }

        let states = reportStates
        return WeeklyReportScreenshotSnapshot(
            period: period,
            steps: states.steps,
            weight: states.weight,
            bodyFat: states.bodyFat,
            waist: states.waist,
            glucose: states.glucose,
            vo2Max: states.vo2Max,
            bloodOxygen: states.bloodOxygen,
            bloodPressure: states.bloodPressure,
            restingHeartRate: states.restingHeartRate,
            hrv: states.hrv,
            watchCoverage: states.watchCoverage,
            exercise: states.exercise,
            activeEnergy: states.activeEnergy,
            workouts: states.workouts,
            sleep: states.sleep,
            medications: states.medications,
            includesMedicationSection: includesMedicationSection,
            showsMorningBloodPressureDetails: showsMorningBloodPressureDetails,
            showsEveningBloodPressureDetails: showsEveningBloodPressureDetails
        )
    }

    func setMedicationAuthorizationFailure(_ message: String) {
        reportStates.medications = .failed(message)
    }

    func refreshMedications() async {
        medicationRefreshGeneration += 1
        let generation = medicationRefreshGeneration
        activeMedicationRefreshGeneration = generation
        defer {
            if activeMedicationRefreshGeneration == generation {
                activeMedicationRefreshGeneration = nil
            }
        }

        guard healthData.isHealthDataAvailable else {
            reportStates.medications = .healthUnavailable
            return
        }
        guard healthData.supportsMedicationData, !period.completedDays.isEmpty else {
            reportStates.medications = .noDataOrAccess
            return
        }

        let queriedPeriod = period
        reportStates.medications = .loading
        do {
            let doses = try await healthData.fetchTakenMedicationDoses(for: queriedPeriod)
            guard generation == medicationRefreshGeneration,
                  queriedPeriod == period else { return }
            reportStates.medications = MedicationSummary.aggregate(doses)
                .map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == medicationRefreshGeneration,
                  queriedPeriod == period else { return }
            reportStates.medications = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        activeRefreshGeneration = generation
        medicationRefreshGeneration += 1
        let medicationGeneration = medicationRefreshGeneration
        activeMedicationRefreshGeneration = nil
        defer {
            if activeRefreshGeneration == generation {
                activeRefreshGeneration = nil
            }
        }
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
            reportStates.steps = .noCompletedDays
            reportStates.glucose = .noDataOrAccess
            reportStates.bloodOxygen = .noDataOrAccess
            reportStates.restingHeartRate = .noDataOrAccess
            reportStates.hrv = .noDataOrAccess
            reportStates.watchCoverage = .noDataOrAccess
            reportStates.exercise = .noDataOrAccess
            reportStates.activeEnergy = .noDataOrAccess
            reportStates.workouts = .noDataOrAccess
            reportStates.sleep = .noDataOrAccess
            reportStates.medications = .noDataOrAccess
            lastRefreshed = refreshDate
            return
        }

        await loadPeriodMetrics(
            asOf: refreshDate,
            generation: generation,
            medicationGeneration: medicationGeneration
        )
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
            reportStates.weight = summary.map(WeightState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.weight = .failed(error.localizedDescription)
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
            reportStates.bodyFat = summary.map(BodyFatState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.bodyFat = .failed(error.localizedDescription)
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
            reportStates.waist = summary.map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.waist = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let measurements = try await healthData.fetchVO2MaxMeasurements(asOf: date)
            guard generation == refreshGeneration else { return }
            reportStates.vo2Max = VO2MaxSummary.calculate(
                measurements: measurements,
                asOf: date,
                calendar: calendar
            ).map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.vo2Max = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let readings = try await healthData.fetchBloodPressureReadings(
                for: period,
                asOf: date
            )
            guard generation == refreshGeneration else { return }
            reportStates.bloodPressure = BloodPressureSummary.calculate(
                readings: readings,
                period: period,
                asOf: date,
                calendar: calendar
            ).map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.bloodPressure = .failed(error.localizedDescription)
        }
    }

    private func loadPeriodMetrics(
        asOf date: Date,
        generation: Int,
        medicationGeneration: Int
    ) async {
        guard let previousPeriod = period.precedingEquivalent(calendar: calendar) else {
            reportStates.restingHeartRate = .noDataOrAccess
            reportStates.hrv = .noDataOrAccess
            return
        }

        do {
            let values = try await healthData.fetchDailySteps(for: period)
            guard generation == refreshGeneration else { return }
            reportStates.steps = StepSummary.aggregate(values).map(State.loaded) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.steps = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let dailyValues = try await healthData.fetchDailyBloodGlucose(for: period)
            guard generation == refreshGeneration else { return }
            reportStates.glucose = GlucoseSummary.aggregate(dailyValues)
                .map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.glucose = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let measurements = try await healthData.fetchOxygenSaturationMeasurements(
                for: period,
                asOf: date
            )
            guard generation == refreshGeneration else { return }
            reportStates.bloodOxygen = BloodOxygenSummary.calculate(
                measurements: measurements,
                period: period,
                asOf: date,
                calendar: calendar
            ).map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.bloodOxygen = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let currentValues = try await healthData.fetchDailyRestingHeartRate(for: period)
            let previousValues = try await healthData.fetchDailyRestingHeartRate(for: previousPeriod)
            guard generation == refreshGeneration else { return }
            reportStates.restingHeartRate = HeartMetricTrendSummary.calculate(
                currentValues: currentValues,
                previousValues: previousValues
            )
                .map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.restingHeartRate = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let currentValues = try await healthData.fetchDailyHRV(for: period)
            let previousValues = try await healthData.fetchDailyHRV(for: previousPeriod)
            guard generation == refreshGeneration else { return }
            reportStates.hrv = HeartMetricTrendSummary.calculate(
                currentValues: currentValues,
                previousValues: previousValues
            )
                .map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.hrv = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let sampleDates = try await healthData.fetchAppleWatchHeartRateSampleDates(for: period)
            guard generation == refreshGeneration else { return }
            reportStates.watchCoverage = WatchCoverageSummary.calculate(
                appleWatchSampleDates: sampleDates,
                period: period
            ).map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.watchCoverage = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let minutes = try await healthData.fetchExerciseMinutes(for: period)
            guard generation == refreshGeneration else { return }
            reportStates.exercise = minutes.map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.exercise = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let kilocalories = try await healthData.fetchActiveEnergyKilocalories(for: period)
            guard generation == refreshGeneration else { return }
            reportStates.activeEnergy = kilocalories.map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.activeEnergy = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let workouts = try await healthData.fetchWorkouts(for: period)
            guard generation == refreshGeneration else { return }
            // HealthKit does not disclose read denial. An empty result could be
            // either zero workouts or no read visibility, so do not claim zero.
            reportStates.workouts = workouts.isEmpty
                ? .noDataOrAccess
                : .available(WorkoutSummary(workouts: workouts))
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.workouts = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let intervals = try await healthData.fetchAsleepIntervals(for: period, calendar: calendar)
            guard generation == refreshGeneration else { return }
            reportStates.sleep = SleepSummary.calculate(
                asleepIntervals: intervals,
                period: period,
                calendar: calendar
            ).map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.sleep = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        guard healthData.supportsMedicationData else {
            reportStates.medications = .noDataOrAccess
            return
        }
        do {
            let doses = try await healthData.fetchTakenMedicationDoses(for: period)
            guard generation == refreshGeneration,
                  medicationGeneration == medicationRefreshGeneration else { return }
            reportStates.medications = MedicationSummary.aggregate(doses)
                .map(MetricState.available) ?? .noDataOrAccess
        } catch {
            guard generation == refreshGeneration,
                  medicationGeneration == medicationRefreshGeneration else { return }
            reportStates.medications = .failed(error.localizedDescription)
        }
    }

    private func setLoading() {
        reportStates = ReportStates(commonState: .loading)
    }

    private func setHealthUnavailable() {
        reportStates = ReportStates(commonState: .healthUnavailable)
    }

    private func setAuthorizationFailure(_ message: String) {
        reportStates = ReportStates(commonState: .failed(message))
    }
}
