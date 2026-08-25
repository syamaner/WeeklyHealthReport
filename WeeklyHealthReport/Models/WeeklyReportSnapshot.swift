import Foundation

struct WeeklyReportSnapshot: Equatable {
    let period: ReportPeriod
    let weight: WeightMeasurement?
    let bmi: BMIMeasurement?
    let bodyFat: BodyFatTrendSummary?
    let steps: StepSummary?
    let restingHeartRate: HeartMetricSummary?
    let hrv: HeartMetricSummary?
    let sleep: SleepSummary?
    let activeEnergyKilocalories: Double?
    let exerciseMinutes: Double?
    let workouts: WorkoutSummary?
}
