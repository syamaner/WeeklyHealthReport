import SwiftUI

struct QueryDiagnosticsSection: View {
    let period: ReportPeriod

    var body: some View {
        Section("Query") {
            LabeledContent("Start", value: DiagnosticFormat.date(period.interval.start))
            LabeledContent("End (exclusive)", value: DiagnosticFormat.date(period.interval.end))
            LabeledContent("Time zone", value: TimeZone.autoupdatingCurrent.identifier)
        }
    }
}

struct StepsDiagnosticsSection: View {
    let state: WeeklyReportViewModel.State

    @ViewBuilder
    var body: some View {
        if case .loaded(let summary) = state {
            Section("Steps") {
                LabeledContent(
                    "Denominator",
                    value: "\(summary.reportingDayCount) completed days"
                )
                LabeledContent("Days with data", value: String(summary.daysWithVisibleData))
                ForEach(summary.dailyTotals) { daily in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(
                            daily.day.start.formatted(
                                .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                            ),
                            value: daily.steps.map {
                                $0.formatted(.number.precision(.fractionLength(0)))
                            } ?? "No visible data"
                        )
                        if !daily.sourceNames.isEmpty {
                            Text(daily.sourceNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct BodyMeasurementsDiagnosticsSections: View {
    let weightState: WeeklyReportViewModel.WeightState
    let bodyFatState: WeeklyReportViewModel.BodyFatState
    let waistState: MetricState<WaistSummary>

    @ViewBuilder
    var body: some View {
        if case .available(let summary) = weightState {
            Section("Weight") {
                LabeledContent(
                    "Latest",
                    value: HealthReportFormatter.weightKilograms(summary.latest.kilograms)
                )
                LabeledContent(
                    "Latest timestamp",
                    value: DiagnosticFormat.date(summary.latest.date)
                )
                if let current = summary.currentSevenDayAverage {
                    LabeledContent("Current 7d daily mean", value: DiagnosticFormat.weight(current))
                }
                if let previous = summary.previousSevenDayAverage {
                    LabeledContent("Previous 7d daily mean", value: DiagnosticFormat.weight(previous))
                }
                ForEach(summary.dailyValues) { daily in
                    LabeledContent(
                        daily.day.formatted(.dateTime.day().month(.abbreviated)),
                        value: "\(DiagnosticFormat.weight(daily.kilograms)) (\(daily.sampleCount) sample\(daily.sampleCount == 1 ? "" : "s"))"
                    )
                }
            }
        }

        if case .available(let summary) = bodyFatState {
            Section("Body Fat") {
                LabeledContent(
                    "Latest",
                    value: DiagnosticFormat.percentage(summary.latest.percentage)
                )
                LabeledContent(
                    "Latest timestamp",
                    value: DiagnosticFormat.date(summary.latest.date)
                )
                if let average = summary.sevenDayAverage {
                    LabeledContent("7d daily mean", value: DiagnosticFormat.percentage(average))
                }
                if let average = summary.current28DayAverage {
                    LabeledContent(
                        "Current 28d daily mean",
                        value: DiagnosticFormat.percentage(average)
                    )
                }
                if let average = summary.previous28DayAverage {
                    LabeledContent(
                        "Previous 28d daily mean",
                        value: DiagnosticFormat.percentage(average)
                    )
                }

                Text("Daily values").font(.headline)
                ForEach(summary.dailyValues) { daily in
                    LabeledContent(
                        daily.day.formatted(.dateTime.day().month(.abbreviated).year()),
                        value: "\(DiagnosticFormat.percentage(daily.percentage)) (\(daily.sampleCount))"
                    )
                }

                Text("Raw samples").font(.headline)
                ForEach(Array(summary.measurements.enumerated()), id: \.offset) { _, sample in
                    LabeledContent(
                        DiagnosticFormat.date(sample.date),
                        value: DiagnosticFormat.percentage(sample.percentage)
                    )
                }
            }
        }

        if case .available(let summary) = waistState {
            Section("Waist Circumference") {
                LabeledContent(
                    "Latest in 8-week lookback",
                    value: HealthReportFormatter.waistCentimetres(summary.latest.centimetres)
                )
                LabeledContent(
                    "Latest timestamp",
                    value: DiagnosticFormat.date(summary.latest.date)
                )
                if let comparison = summary.comparison,
                   let change = summary.fourWeekChangeCentimetres {
                    LabeledContent(
                        "4-week comparison",
                        value: "\(HealthReportFormatter.waistCentimetres(comparison.centimetres)) at \(DiagnosticFormat.date(comparison.date))"
                    )
                    LabeledContent(
                        "Signed change",
                        value: HealthReportFormatter.signedChange(
                            change,
                            unit: "cm",
                            comparison: "comparison sample"
                        )
                    )
                } else {
                    LabeledContent("4-week comparison", value: "No sample 21–35 days earlier")
                }
                Text("Visible samples in 8-week lookback").font(.headline)
                ForEach(Array(summary.measurements.enumerated()), id: \.offset) { _, sample in
                    LabeledContent(
                        DiagnosticFormat.date(sample.date),
                        value: HealthReportFormatter.waistCentimetres(sample.centimetres)
                    )
                }
            }
        }
    }
}

struct GlucoseDiagnosticsSection: View {
    let state: MetricState<GlucoseSummary>

    @ViewBuilder
    var body: some View {
        if case .available(let summary) = state {
            Section("Blood Glucose") {
                LabeledContent(
                    "Daily-first average",
                    value: HealthReportFormatter.glucose(summary.averageMillimolesPerLiter)
                )
                LabeledContent(
                    "Observed range",
                    value: HealthReportFormatter.glucoseRange(
                        minimum: summary.minimumMillimolesPerLiter,
                        maximum: summary.maximumMillimolesPerLiter
                    )
                )
                LabeledContent(
                    "Valid days",
                    value: "\(summary.validDayCount) / \(summary.reportingDayCount)"
                )
                ForEach(summary.dailyValues) { daily in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(
                            daily.day.start.formatted(
                                .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                            ),
                            value: daily.averageMillimolesPerLiter.map {
                                HealthReportFormatter.glucose($0)
                            } ?? "No visible data"
                        )
                        if let minimum = daily.minimumMillimolesPerLiter,
                           let maximum = daily.maximumMillimolesPerLiter {
                            Text("Range: \(HealthReportFormatter.glucoseRange(minimum: minimum, maximum: maximum))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !daily.sourceNames.isEmpty {
                            Text(daily.sourceNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct CardiorespiratoryDiagnosticsSections: View {
    let vo2MaxState: MetricState<VO2MaxSummary>
    let bloodOxygenState: MetricState<BloodOxygenSummary>

    @ViewBuilder
    var body: some View {
        if case .available(let summary) = vo2MaxState {
            Section("VO₂ Max") {
                LabeledContent(
                    "Latest",
                    value: "\(DiagnosticFormat.vo2Max(summary.latest.millilitresPerKilogramMinute)) at \(DiagnosticFormat.date(summary.latest.date))"
                )
                VO2WindowDiagnosticRow("4-week daily-first mean", window: summary.fourWeek)
                VO2WindowDiagnosticRow("3-month daily-first mean", window: summary.threeMonth)
                VO2WindowDiagnosticRow("6-month daily-first mean", window: summary.sixMonth)

                Text("Daily values").font(.headline)
                ForEach(summary.dailyValues) { daily in
                    LabeledContent(
                        daily.day.formatted(.dateTime.day().month(.abbreviated).year()),
                        value: "\(DiagnosticFormat.vo2Max(daily.average)) (\(daily.sampleCount) sample\(daily.sampleCount == 1 ? "" : "s"))"
                    )
                }

                Text("Raw samples").font(.headline)
                ForEach(Array(summary.measurements.enumerated()), id: \.offset) { _, sample in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(
                            DiagnosticFormat.date(sample.date),
                            value: DiagnosticFormat.vo2Max(
                                sample.millilitresPerKilogramMinute
                            )
                        )
                        Text(sample.sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if case .available(let summary) = bloodOxygenState {
            Section("Blood Oxygen") {
                LabeledContent(
                    "Latest",
                    value: "\(DiagnosticFormat.percentage(summary.latest.percentage)) at \(DiagnosticFormat.date(summary.latest.date))"
                )
                LabeledContent(
                    "Median of daily medians",
                    value: summary.typicalPercentage.map(DiagnosticFormat.percentage)
                        ?? "No visible period data"
                )
                if let minimum = summary.minimumDailyMedian,
                   let maximum = summary.maximumDailyMedian {
                    LabeledContent(
                        "Daily-median range",
                        value: "\(DiagnosticFormat.percentage(minimum))–\(DiagnosticFormat.percentage(maximum))"
                    )
                }
                LabeledContent(
                    "Valid days",
                    value: "\(summary.validDayCount) / \(summary.reportingDayCount)"
                )

                Text("Completed-day medians").font(.headline)
                ForEach(summary.dailyValues) { daily in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(
                            daily.day.start.formatted(
                                .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                            ),
                            value: daily.medianPercentage.map(DiagnosticFormat.percentage)
                                ?? "No visible data"
                        )
                        Text("\(daily.sampleCount) sample\(daily.sampleCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !daily.sourceNames.isEmpty {
                            Text(daily.sourceNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Visible samples in query lookback").font(.headline)
                ForEach(Array(summary.measurements.enumerated()), id: \.offset) { _, sample in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(
                            DiagnosticFormat.date(sample.date),
                            value: DiagnosticFormat.percentage(sample.percentage)
                        )
                        Text(sample.sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct BloodPressureDiagnosticsSection: View {
    let state: MetricState<BloodPressureSummary>

    @ViewBuilder
    var body: some View {
        if case .available(let summary) = state {
            Section("Blood Pressure") {
                LabeledContent(
                    "Latest complete pair",
                    value: "\(DiagnosticFormat.bloodPressure(summary.latest.systolicMillimetresOfMercury, summary.latest.diastolicMillimetresOfMercury)) at \(DiagnosticFormat.date(summary.latest.date))"
                )
                BloodPressurePeriodDiagnosticRow(
                    "Morning daily-first mean",
                    summary: summary.morning
                )
                BloodPressurePeriodDiagnosticRow(
                    "Evening daily-first mean",
                    summary: summary.evening
                )
                BloodPressureBatchDiagnosticRow(
                    "Latest morning batch",
                    batch: summary.latestMorningBatch
                )
                BloodPressureBatchDiagnosticRow(
                    "Latest evening batch",
                    batch: summary.latestEveningBatch
                )

                Text("Completed-day batches").font(.headline)
                ForEach(summary.dailyValues) { daily in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(daily.day.start.formatted(
                            .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                        ))
                        LabeledContent(
                            "Morning",
                            value: daily.morning.map {
                                "\(DiagnosticFormat.bloodPressure($0.averageSystolic, $0.averageDiastolic)) (\($0.readingCount))"
                            } ?? "No visible data"
                        )
                        LabeledContent(
                            "Evening",
                            value: daily.evening.map {
                                "\(DiagnosticFormat.bloodPressure($0.averageSystolic, $0.averageDiastolic)) (\($0.readingCount))"
                            } ?? "No visible data"
                        )
                    }
                }

                Text("Complete paired readings in 30-day lookback").font(.headline)
                ForEach(summary.readings) { reading in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(
                            DiagnosticFormat.date(reading.date),
                            value: DiagnosticFormat.bloodPressure(
                                reading.systolicMillimetresOfMercury,
                                reading.diastolicMillimetresOfMercury
                            )
                        )
                        let slot = BloodPressureTimeSlot.classify(reading.date)
                        Text("\(slot?.rawValue.capitalized ?? "Mid-afternoon (not in slot summaries)") · \(reading.sourceName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct HeartDiagnosticsSections: View {
    let restingHeartRateState: MetricState<HeartMetricTrendSummary>
    let hrvState: MetricState<HeartMetricTrendSummary>
    let watchCoverageState: MetricState<WatchCoverageSummary>

    @ViewBuilder
    var body: some View {
        if case .available(let summary) = restingHeartRateState {
            HeartMetricDiagnosticsSection(
                title: "Resting Heart Rate",
                summary: summary,
                unit: "bpm"
            )
        }

        if case .available(let summary) = hrvState {
            HeartMetricDiagnosticsSection(title: "HRV", summary: summary, unit: "ms")
        }

        if case .available(let summary) = watchCoverageState {
            Section("Apple Watch Coverage") {
                LabeledContent(
                    "Days with Watch heart-rate data",
                    value: "\(summary.daysWithWatchData) / \(summary.reportingDayCount)"
                )
                ForEach(summary.coveredDays, id: \.start) { day in
                    Text(day.start.formatted(
                        .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                    ))
                }
            }
        }
    }
}

struct ActivityDiagnosticsSection: View {
    let activeEnergyState: MetricState<Double>
    let exerciseState: MetricState<Double>
    let workoutState: MetricState<WorkoutSummary>

    var body: some View {
        Section("Activity") {
            DiagnosticMetricRow(
                "Active energy exact total",
                state: activeEnergyState,
                unit: "kcal"
            )
            DiagnosticMetricRow(
                "Exercise exact total",
                state: exerciseState,
                unit: "min"
            )
            if case .available(let summary) = workoutState {
                LabeledContent("Workout count", value: String(summary.count))
                LabeledContent(
                    "Workout duration",
                    value: "\((summary.totalDuration / 60).formatted(.number.precision(.fractionLength(2)))) min"
                )
                ForEach(summary.workouts) { workout in
                    LabeledContent(
                        workout.activityName,
                        value: "\(HealthReportFormatter.duration(workout.duration)) — \(HealthReportFormatter.workoutDateAndTime(workout.startDate))"
                    )
                }
            }
        }
    }
}

struct SleepDiagnosticsSection: View {
    let state: MetricState<SleepSummary>

    @ViewBuilder
    var body: some View {
        if case .available(let summary) = state {
            Section("Sleep") {
                LabeledContent("Valid nights", value: String(summary.nights.count))
                ForEach(summary.nights) { night in
                    LabeledContent(
                        night.wakeDay.formatted(
                            .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                        ),
                        value: HealthReportFormatter.duration(night.duration)
                    )
                }
            }
        }
    }
}

struct MedicationDiagnosticsSection: View {
    let state: MetricState<MedicationSummary>

    @ViewBuilder
    var body: some View {
        if case .available(let summary) = state {
            Section("Medication Taken Events") {
                LabeledContent("Event count", value: String(summary.allDoses.count))
                ForEach(summary.allDoses) { dose in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dose.medicationName)
                        LabeledContent(
                            DiagnosticFormat.date(dose.date),
                            value: HealthReportFormatter.medicationDose(
                                quantity: dose.quantity,
                                unitLabel: dose.unitLabel
                            )
                        )
                    }
                }
            }
        }
    }
}

private struct HeartMetricDiagnosticsSection: View {
    let title: String
    let summary: HeartMetricTrendSummary
    let unit: String

    var body: some View {
        Section(title) {
            LabeledContent("Current valid days", value: String(summary.current.validDayCount))
            if let previous = summary.previous {
                LabeledContent("Previous valid days", value: String(previous.validDayCount))
            }
            Text("Current period").font(.headline)
            HeartMetricDiagnosticValues(values: summary.current.dailyValues, unit: unit)
            if let previous = summary.previous {
                Text("Previous equivalent period").font(.headline)
                HeartMetricDiagnosticValues(values: previous.dailyValues, unit: unit)
            }
        }
    }
}

private struct HeartMetricDiagnosticValues: View {
    let values: [DailyHeartMetricValue]
    let unit: String

    var body: some View {
        ForEach(values) { daily in
            LabeledContent(
                daily.day.start.formatted(
                    .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                ),
                value: daily.value.map {
                    "\($0.formatted(.number.precision(.fractionLength(3)))) \(unit)"
                } ?? "No visible data"
            )
        }
    }
}

private struct DiagnosticMetricRow: View {
    let label: String
    let state: MetricState<Double>
    let unit: String

    init(_ label: String, state: MetricState<Double>, unit: String) {
        self.label = label
        self.state = state
        self.unit = unit
    }

    @ViewBuilder
    var body: some View {
        if case .available(let value) = state {
            LabeledContent(
                label,
                value: "\(value.formatted(.number.precision(.fractionLength(3)))) \(unit)"
            )
        }
    }
}

private struct BloodPressurePeriodDiagnosticRow: View {
    let label: String
    let summary: BloodPressurePeriodSlotSummary?

    init(_ label: String, summary: BloodPressurePeriodSlotSummary?) {
        self.label = label
        self.summary = summary
    }

    var body: some View {
        if let summary {
            LabeledContent(
                label,
                value: "\(DiagnosticFormat.bloodPressure(summary.averageSystolic, summary.averageDiastolic)); \(summary.sampledDayCount)/\(summary.reportingDayCount) days; \(summary.readingCount) readings"
            )
        } else {
            LabeledContent(label, value: "No visible period data")
        }
    }
}

private struct BloodPressureBatchDiagnosticRow: View {
    let label: String
    let batch: BloodPressureBatchSummary?

    init(_ label: String, batch: BloodPressureBatchSummary?) {
        self.label = label
        self.batch = batch
    }

    var body: some View {
        if let batch {
            LabeledContent(
                label,
                value: "\(DiagnosticFormat.bloodPressure(batch.averageSystolic, batch.averageDiastolic)); \(batch.readingCount) readings; \(DiagnosticFormat.date(batch.latestReadingDate))"
            )
        } else {
            LabeledContent(label, value: "No visible data")
        }
    }
}

private struct VO2WindowDiagnosticRow: View {
    let label: String
    let window: VO2MaxWindowSummary

    init(_ label: String, window: VO2MaxWindowSummary) {
        self.label = label
        self.window = window
    }

    var body: some View {
        LabeledContent(
            label,
            value: window.average.map(DiagnosticFormat.vo2Max)
                ?? "Insufficient data (\(window.sampledDayCount) sampled days)"
        )
    }
}

private enum DiagnosticFormat {
    static func date(_ date: Date) -> String {
        HealthReportFormatter.dateAndTime(date)
    }

    static func bloodPressure(_ systolic: Double, _ diastolic: Double) -> String {
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(3))
        return "\(systolic.formatted(format))/\(diastolic.formatted(format)) mmHg"
    }

    static func percentage(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3))))%"
    }

    static func weight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3)))) kg"
    }

    static func vo2Max(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3)))) mL/kg/min"
    }
}
