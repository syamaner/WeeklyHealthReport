import Foundation

protocol DailyHealthExportDataProviding {
    var isHealthDataAvailable: Bool { get }

    func requestReadAuthorization() async throws
    func requestNutritionReadAuthorization() async throws
    func fetchVisibleNutritionSources() async throws -> [NutritionSource]
    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow,
        nutritionSourceBundleIdentifier: String
    ) async throws -> DailyHealthExportInputs
}

struct DailyHealthExportResult: Equatable {
    let envelope: DailyHealthExportEnvelope
    let bytes: Data
    let notesSnapshot: DailyNotesSnapshot
}

struct DailyHealthExportService {
    private let healthData: any DailyHealthExportDataProviding
    private let notesStore: any DailyNotesPersisting
    private let calendar: Calendar
    private let now: () -> Date

    init(
        healthData: any DailyHealthExportDataProviding,
        notesStore: any DailyNotesPersisting = EmptyDailyNotesStore(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.healthData = healthData
        self.notesStore = notesStore
        self.calendar = calendar
        self.now = now
    }

    func discoverNutritionSources() async throws -> [NutritionSource] {
        guard healthData.isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        try await healthData.requestNutritionReadAuthorization()
        return try await healthData.fetchVisibleNutritionSources()
    }

    func resolveNutritionSourcesWithoutAuthorization() async throws -> [NutritionSource] {
        guard healthData.isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        return try await healthData.fetchVisibleNutritionSources()
    }

    func refresh(
        nutritionSourceBundleIdentifier: String?
    ) async throws -> DailyHealthExportResult {
        let cutoff = now()
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let notesSnapshot: DailyNotesSnapshot
        do {
            notesSnapshot = try notesStore.snapshot(for: DailyNoteDayID(window: window))
        } catch {
            throw DailyHealthExportError.notesUnavailable
        }
        guard healthData.isHealthDataAvailable else {
            throw HealthDataError.unavailable
        }
        guard let nutritionSourceBundleIdentifier,
              !nutritionSourceBundleIdentifier.isEmpty else {
            throw DailyHealthExportError.nutritionSourceRequired
        }

        let sources = try await healthData.fetchVisibleNutritionSources()
        guard sources.contains(where: {
            $0.bundleIdentifier == nutritionSourceBundleIdentifier
        }) else {
            throw DailyHealthExportError.nutritionSourceUnavailable
        }
        let inputs = try await healthData.fetchDailyHealthExportInputs(
            for: window,
            nutritionSourceBundleIdentifier: nutritionSourceBundleIdentifier
        )
        guard inputs.nutrition.source.bundleIdentifier == nutritionSourceBundleIdentifier else {
            throw DailyHealthExportError.nutritionSourceUnavailable
        }
        do {
            guard try notesStore.containsCurrent(notesSnapshot) else {
                throw DailyHealthExportError.notesChanged
            }
        } catch let error as DailyHealthExportError {
            throw error
        } catch {
            throw DailyHealthExportError.notesUnavailable
        }
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: now(),
            inputs: inputs,
            notes: notesSnapshot.notes
        )
        return DailyHealthExportResult(
            envelope: envelope,
            bytes: try DailyHealthExportSerializer.encode(envelope),
            notesSnapshot: notesSnapshot
        )
    }
}
