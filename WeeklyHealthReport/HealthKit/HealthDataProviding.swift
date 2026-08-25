import Foundation

protocol HealthDataProviding {
    var isHealthDataAvailable: Bool { get }

    func requestReadAuthorization() async throws
    func fetchDailySteps(for period: ReportPeriod) async throws -> [DailyStepTotal]
    func fetchLatestWeight(asOf date: Date) async throws -> WeightMeasurement?
    func fetchBodyFatMeasurements(asOf date: Date) async throws -> [BodyFatMeasurement]
    func fetchLatestBMI(asOf date: Date) async throws -> BMIMeasurement?
    func fetchDailyRestingHeartRate(for period: ReportPeriod) async throws -> [DailyHeartMetricValue]
    func fetchDailyHRV(for period: ReportPeriod) async throws -> [DailyHeartMetricValue]
    func fetchExerciseMinutes(for period: ReportPeriod) async throws -> Double?
    func fetchActiveEnergyKilocalories(for period: ReportPeriod) async throws -> Double?
    func fetchWorkouts(for period: ReportPeriod) async throws -> [WorkoutRecord]
    func fetchAsleepIntervals(for period: ReportPeriod, calendar: Calendar) async throws -> [AsleepInterval]
}
