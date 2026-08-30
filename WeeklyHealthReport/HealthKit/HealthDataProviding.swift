import Foundation

protocol HealthDataProviding {
    var isHealthDataAvailable: Bool { get }
    var supportsMedicationData: Bool { get }

    func requestReadAuthorization() async throws
    func fetchDailySteps(for period: ReportPeriod) async throws -> [DailyStepTotal]
    func fetchWeightMeasurements(asOf date: Date) async throws -> [WeightMeasurement]
    func fetchBodyFatMeasurements(asOf date: Date) async throws -> [BodyFatMeasurement]
    func fetchWaistMeasurements(asOf date: Date) async throws -> [WaistMeasurement]
    func fetchDailyBloodGlucose(for period: ReportPeriod) async throws -> [DailyGlucoseValue]
    func fetchDailyRestingHeartRate(for period: ReportPeriod) async throws -> [DailyHeartMetricValue]
    func fetchDailyHRV(for period: ReportPeriod) async throws -> [DailyHeartMetricValue]
    func fetchAppleWatchHeartRateSampleDates(for period: ReportPeriod) async throws -> [Date]
    func fetchExerciseMinutes(for period: ReportPeriod) async throws -> Double?
    func fetchActiveEnergyKilocalories(for period: ReportPeriod) async throws -> Double?
    func fetchWorkouts(for period: ReportPeriod) async throws -> [WorkoutRecord]
    func fetchAsleepIntervals(for period: ReportPeriod, calendar: Calendar) async throws -> [AsleepInterval]
    func fetchTakenMedicationDoses(for period: ReportPeriod) async throws -> [MedicationDoseRecord]
}
