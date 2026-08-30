import Foundation

struct WeeklyReportSnapshot: Equatable {
    let period: ReportPeriod
    let weight: WeightTrendSummary?
    let bodyFat: BodyFatTrendSummary?
    let waist: WaistSummary?
    let glucose: GlucoseSummary?
    let steps: StepSummary?
    let restingHeartRate: HeartMetricTrendSummary?
    let hrv: HeartMetricTrendSummary?
    let watchCoverage: WatchCoverageSummary?
    let sleep: SleepSummary?
    let activeEnergyKilocalories: Double?
    let exerciseMinutes: Double?
    let workouts: WorkoutSummary?
    let medications: MedicationSummary?
}
