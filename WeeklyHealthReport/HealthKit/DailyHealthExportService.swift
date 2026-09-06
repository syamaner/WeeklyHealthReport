import Foundation

protocol DailyHealthExportDataProviding {
    var isHealthDataAvailable: Bool { get }

    func requestReadAuthorization() async throws
    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow
    ) async throws -> DailyHealthExportInputs
}

struct DailyHealthExportResult: Equatable {
    let envelope: DailyHealthExportEnvelope
    let bytes: Data
}

struct DailyHealthExportService {
    private let healthData: any DailyHealthExportDataProviding
    private let calendar: Calendar
    private let now: () -> Date

    init(
        healthData: any DailyHealthExportDataProviding,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.healthData = healthData
        self.calendar = calendar
        self.now = now
    }

    func refresh() async throws -> DailyHealthExportResult {
        let cutoff = now()
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        guard healthData.isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }

        try await healthData.requestReadAuthorization()
        let inputs = try await healthData.fetchDailyHealthExportInputs(for: window)
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: now(),
            inputs: inputs
        )
        return DailyHealthExportResult(
            envelope: envelope,
            bytes: try DailyHealthExportSerializer.encode(envelope)
        )
    }
}
