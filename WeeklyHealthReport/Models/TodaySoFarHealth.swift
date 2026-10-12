import Foundation

// Home's provisional "today so far" health values, policy
// `today_so_far_health_v1` (docs/today-so-far-projection-v1.md). A third day
// rule beside completed-day reports and the selected-day Daily JSON export:
// never stored, copied or exported.

/// The captured window for one Home refresh (contract section 2).
struct TodaySoFarWindow: Equatable, Sendable {
    /// The refresh instant; every read in one refresh uses it.
    let asOf: Date
    /// Local midnight to `asOf`, start inclusive, end exclusive.
    let day: DateInterval
    /// Noon on the previous local day to `min(noon today, asOf)`.
    let sleep: DateInterval
    /// True from local noon today, when the wake-date bucket has closed.
    let sleepIsComplete: Bool
    let weightLookbackStart: Date
    let bloodPressureLookbackStart: Date
    /// A snapshot, never `autoupdatingCurrent`, so a later time-zone change
    /// cannot move a captured window.
    let calendar: Calendar

    /// True when `asOf` is exactly local midnight, so there is nothing to sum.
    var dayIsEmpty: Bool { day.duration <= 0 }

    static func capture(at now: Date, calendar supplied: Calendar) -> TodaySoFarWindow? {
        var calendar = Calendar(identifier: supplied.identifier)
        calendar.timeZone = supplied.timeZone
        calendar.locale = supplied.locale
        calendar.firstWeekday = supplied.firstWeekday
        calendar.minimumDaysInFirstWeek = supplied.minimumDaysInFirstWeek

        let start = calendar.startOfDay(for: now)
        guard start <= now,
              let previousDay = calendar.date(byAdding: .day, value: -1, to: start),
              let previousNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: previousDay),
              let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start),
              let weightStart = HealthReportingPolicy.weightLatestLookbackStart(asOf: now, calendar: calendar),
              let bloodPressureStart = HealthReportingPolicy.bloodPressureLatestLookbackStart(
                asOf: now, calendar: calendar)
        else { return nil }

        let sleepEnd = max(previousNoon, min(noon, now))
        return TodaySoFarWindow(
            asOf: now,
            day: DateInterval(start: start, end: now),
            sleep: DateInterval(start: previousNoon, end: sleepEnd),
            sleepIsComplete: now >= noon,
            weightLookbackStart: weightStart,
            bloodPressureLookbackStart: bloodPressureStart,
            calendar: calendar
        )
    }
}

/// One row's read outcome. Never an error or framework type.
enum TodaySoFarRead<Value: Equatable>: Equatable {
    case value(Value)
    case noData
    case failed
    case healthUnavailable
}

extension TodaySoFarRead: Sendable where Value: Sendable {}

/// What the port returns for one window (contract section 4).
struct TodaySoFarHealthInputs: Equatable, Sendable {
    /// The HealthKit statistic's sum plus its source names. `.value` always
    /// carries a number; an absent sum is `.noData`.
    let steps: TodaySoFarRead<DailyStepTotal>
    let activeEnergyKilocalories: TodaySoFarRead<Double>
    let asleepIntervals: TodaySoFarRead<[AsleepInterval]>
    let weights: TodaySoFarRead<[WeightMeasurement]>
    let bloodPressure: TodaySoFarRead<[BloodPressureReading]>

    static let healthUnavailable = TodaySoFarHealthInputs(
        steps: .healthUnavailable,
        activeEnergyKilocalories: .healthUnavailable,
        asleepIntervals: .healthUnavailable,
        weights: .healthUnavailable,
        bloodPressure: .healthUnavailable
    )
}

/// The consumer-owned port Home reads through. Adapters map their errors with
/// `TodaySoFarReadMapping`.
protocol TodaySoFarHealthReading: Sendable {
    func todaySoFarInputs(for window: TodaySoFarWindow) async -> TodaySoFarHealthInputs
}

/// How an adapter classified one read's failure.
enum TodaySoFarReadFailure: Error, Equatable {
    /// The device has no Apple Health.
    case healthUnavailable
    /// Any other thrown error.
    case failed
}

/// The pure error and emptiness mapping every adapter uses (contract test 9).
enum TodaySoFarReadMapping {
    static func inputs(
        steps: Result<DailyStepTotal, TodaySoFarReadFailure>,
        activeEnergyKilocalories: Result<Double?, TodaySoFarReadFailure>,
        asleepIntervals: Result<[AsleepInterval], TodaySoFarReadFailure>,
        weights: Result<[WeightMeasurement], TodaySoFarReadFailure>,
        bloodPressure: Result<[BloodPressureReading], TodaySoFarReadFailure>
    ) -> TodaySoFarHealthInputs {
        let failures = [
            steps.failure, activeEnergyKilocalories.failure, asleepIntervals.failure,
            weights.failure, bloodPressure.failure
        ]
        if failures.contains(.healthUnavailable) { return .healthUnavailable }

        return TodaySoFarHealthInputs(
            steps: read(steps) { $0.steps == nil ? nil : $0 },
            activeEnergyKilocalories: read(activeEnergyKilocalories) { $0 },
            asleepIntervals: read(asleepIntervals) { $0.isEmpty ? nil : $0 },
            weights: read(weights) { $0.isEmpty ? nil : $0 },
            bloodPressure: read(bloodPressure) { $0.isEmpty ? nil : $0 }
        )
    }

    private static func read<Outcome, Value: Equatable>(
        _ outcome: Result<Outcome, TodaySoFarReadFailure>,
        visible: (Outcome) -> Value?
    ) -> TodaySoFarRead<Value> {
        switch outcome {
        case .success(let result):
            return visible(result).map(TodaySoFarRead.value) ?? .noData
        case .failure(.healthUnavailable):
            return .healthUnavailable
        case .failure(.failed):
            return .failed
        }
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}

/// One refresh's projected rows (contract section 3). Values are unrounded;
/// rounding happens only in presentation.
struct TodaySoFarHealthProjection: Equatable {
    struct Steps: Equatable {
        let count: Double
        let sourceNames: [String]
    }

    struct Sleep: Equatable {
        /// Merged, clipped asleep intervals; overlaps count once.
        let intervals: [AsleepInterval]
        let asleepSeconds: TimeInterval
        /// False before local noon: the row reads "so far".
        let isComplete: Bool
    }

    let window: TodaySoFarWindow
    let steps: TodaySoFarRead<Steps>
    let activeEnergyKilocalories: TodaySoFarRead<Double>
    let sleep: TodaySoFarRead<Sleep>
    let latestWeight: TodaySoFarRead<WeightMeasurement>
    let latestBloodPressure: TodaySoFarRead<BloodPressureReading>

    var isHealthUnavailable: Bool {
        steps == .healthUnavailable && activeEnergyKilocalories == .healthUnavailable
            && sleep == .healthUnavailable && latestWeight == .healthUnavailable
            && latestBloodPressure == .healthUnavailable
    }

    static func make(inputs: TodaySoFarHealthInputs, window: TodaySoFarWindow) -> TodaySoFarHealthProjection {
        TodaySoFarHealthProjection(
            window: window,
            steps: cumulative(inputs.steps, window: window) { total in
                total.steps.map { Steps(count: $0, sourceNames: total.sourceNames) }
            },
            activeEnergyKilocalories: cumulative(inputs.activeEnergyKilocalories, window: window) { $0 },
            sleep: map(inputs.asleepIntervals) { intervals in
                let clipped = intervals.compactMap { interval -> AsleepInterval? in
                    let start = max(interval.start, window.sleep.start)
                    let end = min(interval.end, window.sleep.end)
                    return start < end ? AsleepInterval(start: start, end: end) : nil
                }
                let merged = SleepSummary.mergeOverlaps(clipped)
                let seconds = merged.map(\.duration).reduce(0, +)
                guard seconds > 0 else { return nil }
                return Sleep(intervals: merged, asleepSeconds: seconds, isComplete: window.sleepIsComplete)
            },
            latestWeight: map(inputs.weights) { weights in
                WeightMeasurement.latest(in: weights.filter {
                    $0.date >= window.weightLookbackStart && $0.date < window.asOf
                })
            },
            latestBloodPressure: map(inputs.bloodPressure) { readings in
                BloodPressureReading.latestValid(
                    in: readings,
                    lookbackStart: window.bloodPressureLookbackStart,
                    asOf: window.asOf
                )
            }
        )
    }

    /// Steps and active energy: an empty day is no data without a query.
    private static func cumulative<Input, Output>(
        _ read: TodaySoFarRead<Input>,
        window: TodaySoFarWindow,
        transform: (Input) -> Output?
    ) -> TodaySoFarRead<Output> {
        if window.dayIsEmpty, case .value = read { return .noData }
        return map(read, transform: transform)
    }

    private static func map<Input, Output>(
        _ read: TodaySoFarRead<Input>,
        transform: (Input) -> Output?
    ) -> TodaySoFarRead<Output> {
        switch read {
        case .value(let input): transform(input).map(TodaySoFarRead.value) ?? .noData
        case .noData: .noData
        case .failed: .failed
        case .healthUnavailable: .healthUnavailable
        }
    }
}
