import Foundation

protocol HealthDataProviding: Sendable {
    var isHealthDataAvailable: Bool { get }
    var supportsMedicationData: Bool { get }
    var dailyBucketReadRecords: [DailyBucketReadRecord] { get }

    func requestReadAuthorization() async throws
    /// Daily collections take the calendar that built `period`, so HealthKit's
    /// buckets are checked against the same local days (docs/healthkit-day-bucketing-v1.md).
    func fetchDailySteps(for period: ReportPeriod, calendar: Calendar) async throws -> [DailyStepTotal]
    func fetchWeightMeasurements(asOf date: Date) async throws -> [WeightMeasurement]
    func fetchBodyFatMeasurements(asOf date: Date) async throws -> [BodyFatMeasurement]
    func fetchWaistMeasurements(asOf date: Date) async throws -> [WaistMeasurement]
    func fetchVO2MaxMeasurements(asOf date: Date) async throws -> [VO2MaxMeasurement]
    func fetchOxygenSaturationMeasurements(
        for period: ReportPeriod,
        asOf date: Date
    ) async throws -> [OxygenSaturationMeasurement]
    func fetchBloodPressureReadings(
        for period: ReportPeriod,
        asOf date: Date
    ) async throws -> [BloodPressureReading]
    func fetchDailyBloodGlucose(
        for period: ReportPeriod,
        calendar: Calendar
    ) async throws -> [DailyGlucoseValue]
    func fetchDailyRestingHeartRate(
        for period: ReportPeriod,
        calendar: Calendar
    ) async throws -> [DailyHeartMetricValue]
    func fetchDailyHRV(for period: ReportPeriod, calendar: Calendar) async throws -> [DailyHeartMetricValue]
    func fetchAppleWatchHeartRateSampleDates(for period: ReportPeriod) async throws -> [Date]
    func fetchExerciseMinutes(for period: ReportPeriod) async throws -> Double?
    func fetchActiveEnergyKilocalories(for period: ReportPeriod) async throws -> Double?
    func fetchWorkouts(for period: ReportPeriod) async throws -> [WorkoutRecord]
    func fetchAsleepIntervals(for period: ReportPeriod, calendar: Calendar) async throws -> [AsleepInterval]
    func fetchTakenMedicationDoses(for period: ReportPeriod) async throws -> [MedicationDoseRecord]
}

extension HealthDataProviding {
    /// Developer tools only: recent daily-bucket read outcomes. Providers
    /// without a collection query have none.
    var dailyBucketReadRecords: [DailyBucketReadRecord] { [] }
}
