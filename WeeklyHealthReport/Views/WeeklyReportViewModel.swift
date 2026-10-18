import Foundation

/// The Health report's food-log port (docs/health-food-and-water-v1.md, section 6),
/// owned by its consumer. The composition root's adapter reads one reporting date
/// at a time through the existing Food Log read side; no store or FoodLedgerKit
/// type crosses it. A thrown error is a read failure (for example competing
/// current versions on a date).
protocol FoodLogPeriodReading: Sendable {
    func dayFacts(for reportingDates: [String]) async throws -> [FoodLogDayFacts]
}

@MainActor
final class WeeklyReportViewModel: ObservableObject {
    typealias WeightState = MetricState<WeightTrendSummary>
    typealias BodyFatState = MetricState<BodyFatTrendSummary>

    private enum CommonReportState {
        case idle
        case loading
        case healthUnavailable
        case failed(String)

        var stepState: StepsState {
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
        var steps: StepsState
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
    }

    @Published var selection: ReportPeriodSelection = .lastSevenCompletedDays
    @Published private(set) var period: ReportPeriod
    @Published private var reportStates = ReportStates(commonState: .idle)
    @Published private(set) var lastRefreshed: Date?
    /// Developer tools only: how the latest report's daily collections were
    /// bucketed (docs/healthkit-day-bucketing-v1.md decision 5).
    @Published private(set) var dailyBucketReads: [DailyBucketReadRecord] = []
    /// The intervals the latest report read, so Developer tools can list every
    /// other daily read (the Daily JSON export's context and nutrition) apart.
    private var dailyBucketReportIntervals: [DateInterval] = []

    /// Developer tools only: daily reads outside the latest report, read live
    /// because the Daily JSON export runs independently of report refreshes.
    var otherDailyBucketReads: [DailyBucketReadRecord] {
        healthData.dailyBucketReadRecords.filter {
            !dailyBucketReportIntervals.contains($0.interval)
        }
    }
    /// Food and water (#214). Kept apart from the HealthKit states: a food-log
    /// failure never changes them, and Apple Health being unavailable never
    /// hides the food log.
    @Published private(set) var foodLogState: MetricState<FoodLogPeriodSummary> = .idle

    var state: StepsState { reportStates.steps }
    var isRefreshing: Bool {
        activeRefreshGeneration != nil || activeMedicationRefreshGeneration != nil
            || activeFoodLogGeneration != nil
    }
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
    /// Nil when the food log could not be opened; the section then reports a
    /// read failure.
    private let foodLog: (any FoodLogPeriodReading)?
    /// When set, read authorisation goes through this shared requester so the
    /// report and Home never ask at the same time (#199). Same read set.
    private let readAuthorization: HealthReadAuthorizationRequesting?
    private let calendar: Calendar
    private let now: () -> Date
    private var refreshGeneration = 0
    @Published private var activeRefreshGeneration: Int?
    private var medicationRefreshGeneration = 0
    @Published private var activeMedicationRefreshGeneration: Int?
    private var foodLogGeneration = 0
    @Published private var activeFoodLogGeneration: Int?

    static let foodLogUnavailableMessage = "The food log could not be opened."

    init(
        healthData: HealthDataProviding = HealthKitClient(),
        readAuthorization: HealthReadAuthorizationRequesting? = nil,
        foodLog: (any FoodLogPeriodReading)? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.healthData = healthData
        self.foodLog = foodLog
        self.readAuthorization = readAuthorization
        self.calendar = calendar
        self.now = now
        self.period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: now(),
            calendar: calendar
        )
    }

    var supportsMedicationData: Bool { healthData.supportsMedicationData }

    func presentationSnapshot(
        includesMedicationSection: Bool,
        showsMorningBloodPressureDetails: Bool,
        showsEveningBloodPressureDetails: Bool
    ) -> ReportPresentationSnapshot {
        let states = reportStates
        return ReportPresentationSnapshot(
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
            foodLog: foodLogState,
            includesMedicationSection: includesMedicationSection,
            showsMorningBloodPressureDetails: showsMorningBloodPressureDetails,
            showsEveningBloodPressureDetails: showsEveningBloodPressureDetails
        )
    }

    func screenshotSnapshot(
        includesMedicationSection: Bool,
        showsMorningBloodPressureDetails: Bool,
        showsEveningBloodPressureDetails: Bool
    ) -> ReportPresentationSnapshot? {
        guard activeRefreshGeneration == nil,
              activeMedicationRefreshGeneration == nil,
              activeFoodLogGeneration == nil,
              period.selection == selection else {
            return nil
        }

        return presentationSnapshot(
            includesMedicationSection: includesMedicationSection,
            showsMorningBloodPressureDetails: showsMorningBloodPressureDetails,
            showsEveningBloodPressureDetails: showsEveningBloodPressureDetails
        )
    }

    func setMedicationAuthorizationFailure(_ message: String) {
        reportStates.medications = .failed(message)
    }

    /// Runs in its own unstructured task for the same reason as `refresh()`:
    /// a caller's cancellation must not publish medications as failed.
    func refreshMedications() async {
        let refresh = Task { await performMedicationRefresh() }
        await refresh.value
    }

    private func performMedicationRefresh() async {
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

    /// Runs the refresh in its own unstructured task so a caller's cancellation
    /// (for example Home's `.task` ending when Health is pushed) cannot abandon
    /// it half way and leave a cancellation reported as "Query failed". A newer
    /// refresh still supersedes this one through the generation checks.
    func refresh() async {
        let refresh = Task { await performRefresh() }
        await refresh.value
    }

    private func performRefresh() async {
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
        foodLogState = .loading

        // The food log is local and independent of Apple Health, so it is read
        // first, under this refresh's generation, whatever HealthKit reports.
        await loadFoodLog(for: period)
        guard generation == refreshGeneration else { return }

        guard healthData.isHealthDataAvailable else {
            setHealthUnavailable()
            return
        }

        do {
            if let readAuthorization {
                try await readAuthorization.requestReadAuthorization()
            } else {
                try await healthData.requestReadAuthorization()
            }
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

    /// Re-reads only the food log for the current period, for example when the
    /// Health report appears after food was logged. Skipped while a full
    /// refresh runs, because that refresh reads the food log itself. Runs in
    /// its own unstructured task, like `refresh()`, so cancelling the caller's
    /// `.task` can never publish a cancellation as "Could not read the food log."
    func refreshFoodLog() async {
        guard activeRefreshGeneration == nil else { return }
        let refresh = Task { await loadFoodLog(for: period) }
        await refresh.value
    }

    /// Food and water (docs/health-food-and-water-v1.md): one reporting date per
    /// completed day; today is never one. A newer read or period supersedes this one.
    private func loadFoodLog(for queriedPeriod: ReportPeriod) async {
        foodLogGeneration += 1
        let generation = foodLogGeneration
        activeFoodLogGeneration = generation
        defer {
            if activeFoodLogGeneration == generation {
                activeFoodLogGeneration = nil
            }
        }
        let reportingDates = FoodLogPeriodSummary.reportingDates(for: queriedPeriod, calendar: calendar)
        guard !reportingDates.isEmpty else {
            foodLogState = .available(.make(days: [], reportingDates: []))
            return
        }
        guard let foodLog else {
            foodLogState = .failed(Self.foodLogUnavailableMessage)
            return
        }
        do {
            let facts = try await foodLog.dayFacts(for: reportingDates)
            guard generation == foodLogGeneration, queriedPeriod == period else { return }
            foodLogState = .available(.make(days: facts, reportingDates: reportingDates))
        } catch {
            guard generation == foodLogGeneration, queriedPeriod == period else { return }
            foodLogState = .failed(error.localizedDescription)
        }
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
        // Drop the previous outcome for these intervals first, so a read that
        // fails or is skipped can never leave a stale line in Developer tools.
        let previousPeriodIfAny = period.precedingEquivalent(calendar: calendar)
        dailyBucketReportIntervals = [period.interval] + (previousPeriodIfAny.map { [$0.interval] } ?? [])
        healthData.clearDailyBucketReadRecords(for: dailyBucketReportIntervals)
        dailyBucketReads = []
        guard let previousPeriod = previousPeriodIfAny else {
            reportStates.restingHeartRate = .noDataOrAccess
            reportStates.hrv = .noDataOrAccess
            return
        }

        do {
            let values = try await healthData.fetchDailySteps(for: period, calendar: calendar)
            guard generation == refreshGeneration else { return }
            if let summary = StepSummary.aggregate(values) {
                // The trend's previous read is separate, so its failure leaves
                // the current rows unchanged (docs/health-steps-trend-v1.md 6).
                let trend: StepTrendRead
                if StepTrendPolicy.requiredSampledDays(
                    completedDayCount: period.completedDays.count
                ) == nil {
                    // Below three completed days no trend is possible; skip the read.
                    trend = .notRead
                } else {
                    do {
                        let previousValues = try await healthData.fetchDailySteps(
                            for: previousPeriod,
                            calendar: calendar
                        )
                        trend = StepTrendSummary.calculate(
                            current: values,
                            previous: previousValues,
                            completedDayCount: period.completedDays.count
                        ).map(StepTrendRead.calculated) ?? .notRead
                    } catch {
                        trend = .previousFailed(error.localizedDescription)
                    }
                }
                guard generation == refreshGeneration else { return }
                reportStates.steps = .loaded(summary, trend: trend)
            } else {
                reportStates.steps = .noDataOrAccess
            }
        } catch {
            guard generation == refreshGeneration else { return }
            reportStates.steps = .failed(error.localizedDescription)
        }
        guard generation == refreshGeneration else { return }

        do {
            let dailyValues = try await healthData.fetchDailyBloodGlucose(
                for: period,
                calendar: calendar
            )
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
            let currentValues = try await healthData.fetchDailyRestingHeartRate(
                for: period,
                calendar: calendar
            )
            let previousValues = try await healthData.fetchDailyRestingHeartRate(
                for: previousPeriod,
                calendar: calendar
            )
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
            let currentValues = try await healthData.fetchDailyHRV(for: period, calendar: calendar)
            let previousValues = try await healthData.fetchDailyHRV(
                for: previousPeriod,
                calendar: calendar
            )
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
        dailyBucketReads = healthData.dailyBucketReadRecords.filter {
            dailyBucketReportIntervals.contains($0.interval)
        }

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
            let period = period
            let workouts = try await WorkoutQueryDiagnostics.labelled(
                "healthReport generation=\(generation)"
            ) {
                try await healthData.fetchWorkouts(for: period)
            }
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
