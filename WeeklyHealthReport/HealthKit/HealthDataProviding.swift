import Foundation

protocol HealthDataProviding {
    var isHealthDataAvailable: Bool { get }

    func requestReadAuthorization() async throws
    func fetchDailySteps(for period: ReportPeriod) async throws -> [DailyStepTotal]
    func fetchLatestWeight(asOf date: Date) async throws -> WeightMeasurement?
    func fetchBodyFatMeasurements(asOf date: Date) async throws -> [BodyFatMeasurement]
    func fetchLatestBMI(asOf date: Date) async throws -> BMIMeasurement?
}
