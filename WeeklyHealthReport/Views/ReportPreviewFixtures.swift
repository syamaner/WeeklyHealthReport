#if DEBUG
import Foundation
import SwiftUI

enum ReportPreviewFixtures {
    enum State: String, CaseIterable, Identifiable {
        case idle
        case loading
        case available
        case noData
        case unavailable
        case failed

        var id: String { rawValue }
    }

    static func section(
        _ id: ReportDocument.SectionID,
        state: State
    ) -> ReportDocument.Section {
        ReportDocument(
            snapshot: snapshot(state: state),
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        ).sections.first { $0.id == id }!
    }

    private static func snapshot(state: State) -> WeeklyReportScreenshotSnapshot {
        let period = ReportPeriod.make(
            selection: .lastSevenCompletedDays,
            now: date(2026, 9, 10, hour: 12),
            calendar: calendar
        )
        let measured = date(2026, 9, 9, hour: 8)
        let reading = BloodPressureReading(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000055")!,
            date: measured,
            systolicMillimetresOfMercury: 120,
            diastolicMillimetresOfMercury: 75,
            sourceName: "Synthetic Monitor"
        )
        let batch = BloodPressureBatchSummary(
            averageSystolic: 120,
            averageDiastolic: 75,
            readingCount: 1,
            firstReadingDate: measured,
            latestReadingDate: measured,
            sourceNames: ["Synthetic Monitor"]
        )
        let slot = BloodPressurePeriodSlotSummary(
            averageSystolic: 120,
            averageDiastolic: 75,
            sampledDayCount: 1,
            reportingDayCount: 7,
            readingCount: 1
        )
        let medication = MedicationSummary.aggregate([
            MedicationDoseRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000056")!,
                medicationKey: "synthetic-20",
                medicationName: "SyntheticMed 20 mg",
                date: measured,
                quantity: 1,
                unitLabel: "dose"
            )
        ])!

        return WeeklyReportScreenshotSnapshot(
            period: period,
            steps: stepsState(state, available: StepSummary(
                dailyTotals: [],
                totalSteps: 49_000,
                averageDailySteps: 7_000,
                reportingDayCount: 7,
                daysWithVisibleData: 7
            )),
            weight: metricState(state, available: WeightTrendSummary(
                latest: WeightMeasurement(date: measured, kilograms: 100.6),
                currentSevenDayAverage: 100.8,
                previousSevenDayAverage: 101.2,
                trendKilograms: -0.4,
                dailyValues: []
            )),
            bodyFat: metricState(state, available: BodyFatTrendSummary(
                latest: BodyFatMeasurement(date: measured, percentage: 26.5),
                sevenDayAverage: 26.6,
                current28DayAverage: 26.7,
                previous28DayAverage: 27.6,
                trendPercentagePoints: -0.9,
                dailyValues: [],
                measurements: []
            )),
            waist: metricState(state, available: WaistSummary(
                latest: WaistMeasurement(date: measured, centimetres: 101.4),
                comparison: WaistMeasurement(date: measured, centimetres: 103.1),
                fourWeekChangeCentimetres: -1.7,
                measurements: []
            )),
            glucose: metricState(state, available: GlucoseSummary(
                dailyValues: period.completedDays.map {
                    DailyGlucoseValue(
                        day: $0,
                        averageMillimolesPerLiter: 5.8,
                        minimumMillimolesPerLiter: 3.9,
                        maximumMillimolesPerLiter: 8.7,
                        sourceNames: ["Synthetic Sensor"]
                    )
                },
                averageMillimolesPerLiter: 5.8,
                minimumMillimolesPerLiter: 3.9,
                maximumMillimolesPerLiter: 8.7
            )),
            vo2Max: metricState(state, available: VO2MaxSummary(
                latest: VO2MaxMeasurement(
                    date: measured,
                    millilitresPerKilogramMinute: 32.1,
                    sourceName: "Synthetic Watch"
                ),
                fourWeek: VO2MaxWindowSummary(average: 31.8, sampledDayCount: 8),
                threeMonth: VO2MaxWindowSummary(average: 30.9, sampledDayCount: 24),
                sixMonth: VO2MaxWindowSummary(average: 29.7, sampledDayCount: 51),
                dailyValues: [],
                measurements: []
            )),
            bloodOxygen: metricState(state, available: BloodOxygenSummary(
                latest: OxygenSaturationMeasurement(
                    date: measured,
                    percentage: 97,
                    sourceName: "Synthetic Watch"
                ),
                dailyValues: [],
                typicalPercentage: 97,
                minimumDailyMedian: 96,
                maximumDailyMedian: 98,
                measurements: []
            )),
            bloodPressure: metricState(state, available: BloodPressureSummary(
                latest: reading,
                latestMorningBatch: batch,
                latestEveningBatch: batch,
                morning: slot,
                evening: slot,
                dailyValues: [],
                readings: [reading]
            )),
            restingHeartRate: metricState(state, available: HeartMetricTrendSummary(
                current: HeartMetricSummary(dailyValues: [], average: 73),
                previous: HeartMetricSummary(dailyValues: [], average: 70),
                trend: 3
            )),
            hrv: metricState(state, available: HeartMetricTrendSummary(
                current: HeartMetricSummary(dailyValues: [], average: 42),
                previous: HeartMetricSummary(dailyValues: [], average: 47),
                trend: -5
            )),
            watchCoverage: metricState(state, available: WatchCoverageSummary(
                reportingDayCount: 7,
                coveredDays: Array(period.completedDays.prefix(4))
            )),
            exercise: metricState(state, available: 89),
            activeEnergy: metricState(state, available: 1_974),
            workouts: metricState(state, available: WorkoutSummary(workouts: [
                WorkoutRecord(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000057")!,
                    startDate: measured,
                    duration: 1_800,
                    activityName: "Walking"
                )
            ])),
            sleep: metricState(state, available: SleepSummary(
                nights: [],
                averageDuration: 6 * 3_600 + 48 * 60
            )),
            medications: metricState(state, available: medication),
            includesMedicationSection: true,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: true
        )
    }

    private static func metricState<Value: Equatable>(
        _ state: State,
        available: @autoclosure () -> Value
    ) -> MetricState<Value> {
        switch state {
        case .idle:
            .idle
        case .loading:
            .loading
        case .available:
            .available(available())
        case .noData:
            .noDataOrAccess
        case .unavailable:
            .healthUnavailable
        case .failed:
            .failed("Synthetic failure")
        }
    }

    private static func stepsState(
        _ state: State,
        available: @autoclosure () -> StepSummary
    ) -> StepsState {
        switch state {
        case .idle:
            .idle
        case .loading:
            .loading
        case .available:
            .loaded(available())
        case .noData:
            .noDataOrAccess
        case .unavailable:
            .healthUnavailable
        case .failed:
            .failed("Synthetic failure")
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}

#Preview("Document section states") {
    Form {
        ForEach(ReportPreviewFixtures.State.allCases) { state in
            Text("Preview state: \(state.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ReportDocumentSectionView(section: ReportPreviewFixtures.section(
                .weight,
                state: state
            ))
        }
    }
}

#Preview("Blood pressure states") {
    Form {
        ForEach(ReportPreviewFixtures.State.allCases) { state in
            Text("Preview state: \(state.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            BloodPressureReportSection(
                section: ReportPreviewFixtures.section(.bloodPressure, state: state),
                showsMorningDetails: .constant(true),
                showsEveningDetails: .constant(true)
            )
        }
    }
}

#Preview("Medication states") {
    Form {
        ForEach(ReportPreviewFixtures.State.allCases) { state in
            Text("Preview state: \(state.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            MedicationReportSection(
                section: ReportPreviewFixtures.section(.medications, state: state),
                requestAccess: {}
            )
        }
    }
}
#endif
