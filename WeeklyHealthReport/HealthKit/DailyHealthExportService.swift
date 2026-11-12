import Foundation

protocol DailyHealthExportDataProviding {
    var isHealthDataAvailable: Bool { get }

    func requestReadAuthorization() async throws
    func requestNutritionReadAuthorization() async throws
    func fetchVisibleNutritionSources() async throws -> [NutritionSource]
    func fetchDailyHealthExportInputs(
        for window: DailyExportWindow,
        nutritionSourceBundleIdentifier: String,
        includeWorkoutEnrichment: Bool,
        includeGlucoseReadings: Bool
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

    func availableReportDays() -> [DailyNoteDayID] {
        DailyExportWindow.availableDays(at: now(), calendar: calendar)
    }

    func refresh(
        nutritionSourceBundleIdentifier: String?,
        selectedDay: DailyNoteDayID? = nil,
        includeWorkoutEnrichment: Bool = true,
        includeGlucoseReadings: Bool = false
    ) async throws -> DailyHealthExportResult {
        try Task.checkCancellation()
        let cutoff = now()
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar, selectedDay: selectedDay)
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
            nutritionSourceBundleIdentifier: nutritionSourceBundleIdentifier,
            includeWorkoutEnrichment: includeWorkoutEnrichment,
            includeGlucoseReadings: includeGlucoseReadings
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
            notes: notesSnapshot.notes,
            includeWorkoutEnrichment: includeWorkoutEnrichment,
            includeGlucoseReadings: includeGlucoseReadings
        )
        let bytes = try DailyHealthExportSerializer.encode(envelope)
        try Task.checkCancellation()
        return DailyHealthExportResult(
            envelope: envelope,
            bytes: bytes,
            notesSnapshot: notesSnapshot
        )
    }
}

/// Whether individual glucose readings go into the health Daily JSON (#469).
/// Off until the user switches it on; kept apart from the Food log preference
/// because this choice changes the health file's own bytes.
protocol DailyGlucoseReadingsPreferencePersisting {
    func loadGlucoseReadingsEnabled() -> Bool
    func saveGlucoseReadingsEnabled(_ enabled: Bool)
}

struct UserDefaultsDailyGlucoseReadingsPreference: DailyGlucoseReadingsPreferencePersisting {
    static let key = "daily-export.glucose-readings-enabled.v1"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadGlucoseReadingsEnabled() -> Bool {
        defaults.object(forKey: Self.key) as? Bool ?? false
    }

    func saveGlucoseReadingsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}

final class MemoryDailyGlucoseReadingsPreference: DailyGlucoseReadingsPreferencePersisting {
    private var enabled: Bool
    init(enabled: Bool = false) { self.enabled = enabled }
    func loadGlucoseReadingsEnabled() -> Bool { enabled }
    func saveGlucoseReadingsEnabled(_ enabled: Bool) { self.enabled = enabled }
}
