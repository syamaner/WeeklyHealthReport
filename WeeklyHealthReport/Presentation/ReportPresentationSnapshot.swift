import Foundation

struct ReportPresentationSnapshot: Equatable {
    let period: ReportPeriod
    let steps: StepsState
    let weight: MetricState<WeightTrendSummary>
    let bodyFat: MetricState<BodyFatTrendSummary>
    let waist: MetricState<WaistSummary>
    let glucose: MetricState<GlucoseSummary>
    let vo2Max: MetricState<VO2MaxSummary>
    let bloodOxygen: MetricState<BloodOxygenSummary>
    let bloodPressure: MetricState<BloodPressureSummary>
    let restingHeartRate: MetricState<HeartMetricTrendSummary>
    let hrv: MetricState<HeartMetricTrendSummary>
    let watchCoverage: MetricState<WatchCoverageSummary>
    let exercise: MetricState<Double>
    let activeEnergy: MetricState<Double>
    let workouts: MetricState<WorkoutSummary>
    let sleep: MetricState<SleepSummary>
    let medications: MetricState<MedicationSummary>
    /// Food and water (#214): the local food log, never Apple Health.
    let foodLog: MetricState<FoodLogPeriodSummary>
    let includesMedicationSection: Bool
    let showsMorningBloodPressureDetails: Bool
    let showsEveningBloodPressureDetails: Bool
}
