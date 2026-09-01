import Foundation

struct BloodPressureReading: Equatable, Identifiable {
    let id: UUID
    let date: Date
    let systolicMillimetresOfMercury: Double
    let diastolicMillimetresOfMercury: Double
    let sourceName: String
}

enum BloodPressureTimeSlot: String, Equatable {
    case morning
    case evening

    static func classify(
        _ date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> BloodPressureTimeSlot? {
        let hour = calendar.component(.hour, from: date)
        if hour < 14 { return .morning }
        if hour >= 17 { return .evening }
        return nil
    }
}

struct BloodPressureBatchSummary: Equatable {
    let averageSystolic: Double
    let averageDiastolic: Double
    let readingCount: Int
    let firstReadingDate: Date
    let latestReadingDate: Date
    let sourceNames: [String]
}

struct BloodPressurePeriodSlotSummary: Equatable {
    let averageSystolic: Double
    let averageDiastolic: Double
    let sampledDayCount: Int
    let reportingDayCount: Int
    let readingCount: Int
}

struct DailyBloodPressureValue: Equatable, Identifiable {
    let day: DateInterval
    let morning: BloodPressureBatchSummary?
    let evening: BloodPressureBatchSummary?

    var id: Date { day.start }
}

struct BloodPressureSummary: Equatable {
    let latest: BloodPressureReading
    let latestMorningBatch: BloodPressureBatchSummary?
    let latestEveningBatch: BloodPressureBatchSummary?
    let morning: BloodPressurePeriodSlotSummary?
    let evening: BloodPressurePeriodSlotSummary?
    let dailyValues: [DailyBloodPressureValue]
    let readings: [BloodPressureReading]

    static func calculate(
        readings: [BloodPressureReading],
        period: ReportPeriod,
        asOf: Date,
        calendar suppliedCalendar: Calendar = .autoupdatingCurrent
    ) -> BloodPressureSummary? {
        var calendar = suppliedCalendar
        calendar.timeZone = suppliedCalendar.timeZone
        guard let latestLookbackStart = calendar.date(
            byAdding: .day,
            value: -30,
            to: calendar.startOfDay(for: asOf)
        ) else { return nil }

        let visibleReadings = readings.filter {
            $0.date >= latestLookbackStart
                && $0.date <= asOf
                && $0.systolicMillimetresOfMercury.isFinite
                && $0.systolicMillimetresOfMercury > 0
                && $0.diastolicMillimetresOfMercury.isFinite
                && $0.diastolicMillimetresOfMercury > 0
        }
        guard let latest = visibleReadings.max(by: { $0.date < $1.date }) else {
            return nil
        }

        // Every input is an intact HealthKit blood-pressure correlation. Average
        // both components over exactly the same set of paired readings; never
        // construct a reading by joining independent systolic and diastolic data.
        let dailyValues = period.completedDays.map { day in
            let dayReadings = visibleReadings.filter {
                $0.date >= day.start && $0.date < day.end
            }
            return DailyBloodPressureValue(
                day: day,
                morning: batch(
                    dayReadings.filter {
                        BloodPressureTimeSlot.classify($0.date, calendar: calendar) == .morning
                    }
                ),
                evening: batch(
                    dayReadings.filter {
                        BloodPressureTimeSlot.classify($0.date, calendar: calendar) == .evening
                    }
                )
            )
        }

        return BloodPressureSummary(
            latest: latest,
            latestMorningBatch: latestBatch(
                readings: visibleReadings,
                slot: .morning,
                calendar: calendar
            ),
            latestEveningBatch: latestBatch(
                readings: visibleReadings,
                slot: .evening,
                calendar: calendar
            ),
            morning: periodSummary(
                batches: dailyValues.compactMap(\.morning),
                reportingDayCount: dailyValues.count
            ),
            evening: periodSummary(
                batches: dailyValues.compactMap(\.evening),
                reportingDayCount: dailyValues.count
            ),
            dailyValues: dailyValues,
            readings: visibleReadings.sorted { $0.date < $1.date }
        )
    }

    private static func batch(
        _ readings: [BloodPressureReading]
    ) -> BloodPressureBatchSummary? {
        guard let firstDate = readings.map(\.date).min(),
              let latestDate = readings.map(\.date).max()
        else { return nil }
        let count = Double(readings.count)
        return BloodPressureBatchSummary(
            averageSystolic: readings.map(\.systolicMillimetresOfMercury).reduce(0, +) / count,
            averageDiastolic: readings.map(\.diastolicMillimetresOfMercury).reduce(0, +) / count,
            readingCount: readings.count,
            firstReadingDate: firstDate,
            latestReadingDate: latestDate,
            sourceNames: Array(Set(readings.map(\.sourceName))).sorted()
        )
    }

    private static func latestBatch(
        readings: [BloodPressureReading],
        slot: BloodPressureTimeSlot,
        calendar: Calendar
    ) -> BloodPressureBatchSummary? {
        let slotReadings = readings.filter {
            BloodPressureTimeSlot.classify($0.date, calendar: calendar) == slot
        }
        let grouped = Dictionary(grouping: slotReadings) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.values.compactMap { batch(Array($0)) }
            .max(by: { $0.latestReadingDate < $1.latestReadingDate })
    }

    private static func periodSummary(
        batches: [BloodPressureBatchSummary],
        reportingDayCount: Int
    ) -> BloodPressurePeriodSlotSummary? {
        guard !batches.isEmpty else { return nil }
        let sampledDayCount = Double(batches.count)
        return BloodPressurePeriodSlotSummary(
            averageSystolic: batches.map(\.averageSystolic).reduce(0, +) / sampledDayCount,
            averageDiastolic: batches.map(\.averageDiastolic).reduce(0, +) / sampledDayCount,
            sampledDayCount: batches.count,
            reportingDayCount: reportingDayCount,
            readingCount: batches.map(\.readingCount).reduce(0, +)
        )
    }
}
