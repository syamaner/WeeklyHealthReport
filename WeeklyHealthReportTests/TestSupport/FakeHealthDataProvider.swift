import Foundation
@testable import WeeklyHealthReport

enum FixtureError: LocalizedError {
    case authorizationFailure
    case glucoseFailure

    var errorDescription: String? {
        switch self {
        case .authorizationFailure:
            "Synthetic authorization failure"
        case .glucoseFailure:
            "Synthetic glucose query failure"
        }
    }
}

final class FakeHealthDataProvider: HealthDataProviding {
    let isHealthDataAvailable: Bool
    let supportsMedicationData: Bool

    private let authorizationError: FixtureError?
    private let glucoseError: FixtureError?
    private let weightResponses: [[WeightMeasurement]]
    private let medicationResponses: [[MedicationDoseRecord]]
    private let control: FakeHealthDataControl

    init(
        isHealthDataAvailable: Bool = true,
        supportsMedicationData: Bool = true,
        authorizationError: FixtureError? = nil,
        glucoseError: FixtureError? = nil,
        weightResponses: [[WeightMeasurement]] = [],
        pauseFirstWeightFetch: Bool = false,
        medicationResponses: [[MedicationDoseRecord]] = [],
        pauseFirstMedicationFetch: Bool = false
    ) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.supportsMedicationData = supportsMedicationData
        self.authorizationError = authorizationError
        self.glucoseError = glucoseError
        self.weightResponses = weightResponses
        self.medicationResponses = medicationResponses
        self.control = FakeHealthDataControl(
            pauseFirstWeightFetch: pauseFirstWeightFetch,
            pauseFirstMedicationFetch: pauseFirstMedicationFetch
        )
    }

    func authorizationRequestCount() async -> Int {
        await control.authorizationRequestCount
    }

    func waitUntilFirstWeightFetchIsPaused() async {
        await control.waitUntilFirstWeightFetchIsPaused()
    }

    func resumeFirstWeightFetch() async {
        await control.resumeFirstWeightFetch()
    }

    func waitUntilFirstMedicationFetchIsPaused() async {
        await control.waitUntilFirstMedicationFetchIsPaused()
    }

    func resumeFirstMedicationFetch() async {
        await control.resumeFirstMedicationFetch()
    }

    func requestReadAuthorization() async throws {
        await control.recordAuthorizationRequest()
        if let authorizationError {
            throw authorizationError
        }
    }

    func fetchDailySteps(for period: ReportPeriod) async throws -> [DailyStepTotal] {
        period.completedDays.enumerated().map { index, day in
            DailyStepTotal(
                day: day,
                steps: Double(index + 1) * 1_000,
                sourceNames: ["Synthetic Phone", "Synthetic Watch"]
            )
        }
    }

    func fetchWeightMeasurements(asOf date: Date) async throws -> [WeightMeasurement] {
        await control.nextWeightMeasurements(
            responses: weightResponses,
            fallback: [WeightMeasurement(
                id: fixtureID,
                date: date.addingTimeInterval(-3_600),
                kilograms: 72
            )]
        )
    }

    func fetchBodyFatMeasurements(asOf date: Date) async throws -> [BodyFatMeasurement] {
        [BodyFatMeasurement(date: date.addingTimeInterval(-3_600), percentage: 21)]
    }

    func fetchWaistMeasurements(asOf date: Date) async throws -> [WaistMeasurement] {
        [WaistMeasurement(date: date.addingTimeInterval(-3_600), centimetres: 84)]
    }

    func fetchVO2MaxMeasurements(asOf date: Date) async throws -> [VO2MaxMeasurement] {
        [VO2MaxMeasurement(
            date: date.addingTimeInterval(-3_600),
            millilitresPerKilogramMinute: 35,
            sourceName: "Synthetic Watch"
        )]
    }

    func fetchOxygenSaturationMeasurements(
        for period: ReportPeriod,
        asOf date: Date
    ) async throws -> [OxygenSaturationMeasurement] {
        [OxygenSaturationMeasurement(
            date: date.addingTimeInterval(-3_600),
            percentage: 97,
            sourceName: "Synthetic Watch"
        )]
    }

    func fetchBloodPressureReadings(
        for period: ReportPeriod,
        asOf date: Date
    ) async throws -> [BloodPressureReading] {
        [BloodPressureReading(
            id: fixtureID,
            date: date.addingTimeInterval(-3_600),
            systolicMillimetresOfMercury: 120,
            diastolicMillimetresOfMercury: 80,
            sourceName: "Synthetic Monitor"
        )]
    }

    func fetchDailyBloodGlucose(for period: ReportPeriod) async throws -> [DailyGlucoseValue] {
        if let glucoseError {
            throw glucoseError
        }
        return period.completedDays.map { day in
            DailyGlucoseValue(
                day: day,
                averageMillimolesPerLiter: 5.5,
                minimumMillimolesPerLiter: 4.2,
                maximumMillimolesPerLiter: 7.1,
                sourceNames: ["Synthetic Sensor"]
            )
        }
    }

    func fetchDailyRestingHeartRate(
        for period: ReportPeriod
    ) async throws -> [DailyHeartMetricValue] {
        heartValues(for: period, value: 61)
    }

    func fetchDailyHRV(for period: ReportPeriod) async throws -> [DailyHeartMetricValue] {
        heartValues(for: period, value: 48)
    }

    func fetchAppleWatchHeartRateSampleDates(for period: ReportPeriod) async throws -> [Date] {
        guard let day = period.completedDays.first else { return [] }
        return [day.start.addingTimeInterval(3_600)]
    }

    func fetchExerciseMinutes(for period: ReportPeriod) async throws -> Double? {
        42
    }

    func fetchActiveEnergyKilocalories(for period: ReportPeriod) async throws -> Double? {
        1_200
    }

    func fetchWorkouts(for period: ReportPeriod) async throws -> [WorkoutRecord] {
        guard let day = period.completedDays.first else { return [] }
        return [WorkoutRecord(
            id: fixtureID,
            startDate: day.start.addingTimeInterval(3_600),
            duration: 1_800,
            activityName: "Synthetic Walk"
        )]
    }

    func fetchAsleepIntervals(
        for period: ReportPeriod,
        calendar: Calendar
    ) async throws -> [AsleepInterval] {
        guard let day = period.completedDays.first else { return [] }
        return [AsleepInterval(
            start: day.start.addingTimeInterval(-7 * 3_600),
            end: day.start.addingTimeInterval(-1 * 3_600)
        )]
    }

    func fetchTakenMedicationDoses(
        for period: ReportPeriod
    ) async throws -> [MedicationDoseRecord] {
        guard let day = period.completedDays.first else { return [] }
        return await control.nextMedicationDoses(
            responses: medicationResponses,
            fallback: [MedicationDoseRecord(
                id: fixtureID,
                medicationKey: "synthetic-medication",
                medicationName: "ExampleMed 10 mg",
                date: day.start.addingTimeInterval(3_600),
                quantity: 1,
                unitLabel: "dose"
            )]
        )
    }

    private func heartValues(
        for period: ReportPeriod,
        value: Double
    ) -> [DailyHeartMetricValue] {
        period.completedDays.map { day in
            DailyHeartMetricValue(
                day: day,
                value: value,
                sourceNames: ["Synthetic Watch"]
            )
        }
    }
}

actor FakeHealthDataControl {
    private let pauseFirstWeightFetch: Bool
    private let pauseFirstMedicationFetch: Bool
    private var weightFetchCount = 0
    private var medicationFetchCount = 0
    private var pausedWeightFetch: CheckedContinuation<Void, Never>?
    private var weightPauseObserver: CheckedContinuation<Void, Never>?
    private var pausedMedicationFetch: CheckedContinuation<Void, Never>?
    private var medicationPauseObserver: CheckedContinuation<Void, Never>?
    private(set) var authorizationRequestCount = 0

    init(pauseFirstWeightFetch: Bool, pauseFirstMedicationFetch: Bool) {
        self.pauseFirstWeightFetch = pauseFirstWeightFetch
        self.pauseFirstMedicationFetch = pauseFirstMedicationFetch
    }

    func recordAuthorizationRequest() {
        authorizationRequestCount += 1
    }

    func nextWeightMeasurements(
        responses: [[WeightMeasurement]],
        fallback: [WeightMeasurement]
    ) async -> [WeightMeasurement] {
        let callIndex = weightFetchCount
        weightFetchCount += 1
        let result = responses.indices.contains(callIndex) ? responses[callIndex] : fallback

        if pauseFirstWeightFetch, callIndex == 0 {
            await withCheckedContinuation { continuation in
                pausedWeightFetch = continuation
                weightPauseObserver?.resume()
                weightPauseObserver = nil
            }
        }
        return result
    }

    func waitUntilFirstWeightFetchIsPaused() async {
        guard pausedWeightFetch == nil else { return }
        await withCheckedContinuation { continuation in
            weightPauseObserver = continuation
        }
    }

    func resumeFirstWeightFetch() {
        precondition(pausedWeightFetch != nil)
        pausedWeightFetch?.resume()
        pausedWeightFetch = nil
    }

    func nextMedicationDoses(
        responses: [[MedicationDoseRecord]],
        fallback: [MedicationDoseRecord]
    ) async -> [MedicationDoseRecord] {
        let callIndex = medicationFetchCount
        medicationFetchCount += 1
        let result = responses.indices.contains(callIndex) ? responses[callIndex] : fallback

        if pauseFirstMedicationFetch, callIndex == 0 {
            await withCheckedContinuation { continuation in
                pausedMedicationFetch = continuation
                medicationPauseObserver?.resume()
                medicationPauseObserver = nil
            }
        }
        return result
    }

    func waitUntilFirstMedicationFetchIsPaused() async {
        guard pausedMedicationFetch == nil else { return }
        await withCheckedContinuation { continuation in
            medicationPauseObserver = continuation
        }
    }

    func resumeFirstMedicationFetch() {
        precondition(pausedMedicationFetch != nil)
        pausedMedicationFetch?.resume()
        pausedMedicationFetch = nil
    }
}
