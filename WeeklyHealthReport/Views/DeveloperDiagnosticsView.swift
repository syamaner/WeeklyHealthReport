import SwiftUI

struct DeveloperDiagnosticsView: View {
    @ObservedObject var viewModel: WeeklyReportViewModel

    var body: some View {
        Form {
            Section("Query") {
                LabeledContent("Start", value: diagnosticDate(viewModel.period.interval.start))
                LabeledContent("End (exclusive)", value: diagnosticDate(viewModel.period.interval.end))
                LabeledContent("Time zone", value: TimeZone.autoupdatingCurrent.identifier)
            }

            if case .loaded(let summary) = viewModel.state {
                Section("Steps") {
                    LabeledContent("Denominator", value: "\(summary.reportingDayCount) completed days")
                    LabeledContent("Days with data", value: String(summary.daysWithVisibleData))
                    ForEach(summary.dailyTotals) { daily in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(
                                daily.day.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
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

            if case .available(let summary) = viewModel.weightState {
                Section("Weight") {
                    LabeledContent("Latest", value: HealthReportFormatter.weightKilograms(summary.latest.kilograms))
                    LabeledContent("Latest timestamp", value: diagnosticDate(summary.latest.date))
                    if let current = summary.currentSevenDayAverage {
                        LabeledContent("Current 7d daily mean", value: diagnosticWeight(current))
                    }
                    if let previous = summary.previousSevenDayAverage {
                        LabeledContent("Previous 7d daily mean", value: diagnosticWeight(previous))
                    }
                    ForEach(summary.dailyValues) { daily in
                        LabeledContent(
                            daily.day.formatted(.dateTime.day().month(.abbreviated)),
                            value: "\(diagnosticWeight(daily.kilograms)) (\(daily.sampleCount) sample\(daily.sampleCount == 1 ? "" : "s"))"
                        )
                    }
                }
            }

            if case .available(let summary) = viewModel.bodyFatState {
                Section("Body Fat") {
                    LabeledContent("Latest", value: diagnosticPercentage(summary.latest.percentage))
                    LabeledContent("Latest timestamp", value: diagnosticDate(summary.latest.date))
                    if let average = summary.sevenDayAverage {
                        LabeledContent("7d daily mean", value: diagnosticPercentage(average))
                    }
                    if let average = summary.current28DayAverage {
                        LabeledContent("Current 28d daily mean", value: diagnosticPercentage(average))
                    }
                    if let average = summary.previous28DayAverage {
                        LabeledContent("Previous 28d daily mean", value: diagnosticPercentage(average))
                    }

                    Text("Daily values").font(.headline)
                    ForEach(summary.dailyValues) { daily in
                        LabeledContent(
                            daily.day.formatted(.dateTime.day().month(.abbreviated).year()),
                            value: "\(diagnosticPercentage(daily.percentage)) (\(daily.sampleCount))"
                        )
                    }

                    Text("Raw samples").font(.headline)
                    ForEach(Array(summary.measurements.enumerated()), id: \.offset) { _, sample in
                        LabeledContent(
                            diagnosticDate(sample.date),
                            value: diagnosticPercentage(sample.percentage)
                        )
                    }
                }
            }

            if case .available(let summary) = viewModel.waistState {
                Section("Waist Circumference") {
                    LabeledContent(
                        "Latest in 8-week lookback",
                        value: HealthReportFormatter.waistCentimetres(summary.latest.centimetres)
                    )
                    LabeledContent("Latest timestamp", value: diagnosticDate(summary.latest.date))
                    if let comparison = summary.comparison,
                       let change = summary.fourWeekChangeCentimetres {
                        LabeledContent(
                            "4-week comparison",
                            value: "\(HealthReportFormatter.waistCentimetres(comparison.centimetres)) at \(diagnosticDate(comparison.date))"
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
                            diagnosticDate(sample.date),
                            value: HealthReportFormatter.waistCentimetres(sample.centimetres)
                        )
                    }
                }
            }

            if case .available(let summary) = viewModel.glucoseState {
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

            if case .available(let summary) = viewModel.vo2MaxState {
                Section("VO₂ Max") {
                    LabeledContent(
                        "Latest",
                        value: "\(diagnosticVO2Max(summary.latest.millilitresPerKilogramMinute)) at \(diagnosticDate(summary.latest.date))"
                    )
                    vo2Window("4-week daily-first mean", summary.fourWeek)
                    vo2Window("3-month daily-first mean", summary.threeMonth)
                    vo2Window("6-month daily-first mean", summary.sixMonth)

                    Text("Daily values").font(.headline)
                    ForEach(summary.dailyValues) { daily in
                        LabeledContent(
                            daily.day.formatted(.dateTime.day().month(.abbreviated).year()),
                            value: "\(diagnosticVO2Max(daily.average)) (\(daily.sampleCount) sample\(daily.sampleCount == 1 ? "" : "s"))"
                        )
                    }

                    Text("Raw samples").font(.headline)
                    ForEach(Array(summary.measurements.enumerated()), id: \.offset) { _, sample in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(
                                diagnosticDate(sample.date),
                                value: diagnosticVO2Max(sample.millilitresPerKilogramMinute)
                            )
                            Text(sample.sourceName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if case .available(let summary) = viewModel.bloodOxygenState {
                Section("Blood Oxygen") {
                    LabeledContent(
                        "Latest",
                        value: "\(diagnosticPercentage(summary.latest.percentage)) at \(diagnosticDate(summary.latest.date))"
                    )
                    LabeledContent(
                        "Median of daily medians",
                        value: summary.typicalPercentage.map(diagnosticPercentage) ?? "No visible period data"
                    )
                    if let minimum = summary.minimumDailyMedian,
                       let maximum = summary.maximumDailyMedian {
                        LabeledContent(
                            "Daily-median range",
                            value: "\(diagnosticPercentage(minimum))–\(diagnosticPercentage(maximum))"
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
                                value: daily.medianPercentage.map(diagnosticPercentage)
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
                                diagnosticDate(sample.date),
                                value: diagnosticPercentage(sample.percentage)
                            )
                            Text(sample.sourceName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if case .available(let summary) = viewModel.bloodPressureState {
                Section("Blood Pressure") {
                    LabeledContent(
                        "Latest complete pair",
                        value: "\(diagnosticBloodPressure(summary.latest.systolicMillimetresOfMercury, summary.latest.diastolicMillimetresOfMercury)) at \(diagnosticDate(summary.latest.date))"
                    )
                    bloodPressurePeriodDiagnostic("Morning daily-first mean", summary.morning)
                    bloodPressurePeriodDiagnostic("Evening daily-first mean", summary.evening)
                    bloodPressureBatchDiagnostic("Latest morning batch", summary.latestMorningBatch)
                    bloodPressureBatchDiagnostic("Latest evening batch", summary.latestEveningBatch)

                    Text("Completed-day batches").font(.headline)
                    ForEach(summary.dailyValues) { daily in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(daily.day.start.formatted(
                                .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                            ))
                            LabeledContent(
                                "Morning",
                                value: daily.morning.map {
                                    "\(diagnosticBloodPressure($0.averageSystolic, $0.averageDiastolic)) (\($0.readingCount))"
                                } ?? "No visible data"
                            )
                            LabeledContent(
                                "Evening",
                                value: daily.evening.map {
                                    "\(diagnosticBloodPressure($0.averageSystolic, $0.averageDiastolic)) (\($0.readingCount))"
                                } ?? "No visible data"
                            )
                        }
                    }

                    Text("Complete paired readings in 30-day lookback").font(.headline)
                    ForEach(summary.readings) { reading in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(
                                diagnosticDate(reading.date),
                                value: diagnosticBloodPressure(
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

            if case .available(let summary) = viewModel.restingHeartRateState {
                heartSection(title: "Resting Heart Rate", summary: summary, unit: "bpm")
            }

            if case .available(let summary) = viewModel.hrvState {
                heartSection(title: "HRV", summary: summary, unit: "ms")
            }

            if case .available(let summary) = viewModel.watchCoverageState {
                Section("Apple Watch Coverage") {
                    LabeledContent(
                        "Days with Watch heart-rate data",
                        value: "\(summary.daysWithWatchData) / \(summary.reportingDayCount)"
                    )
                    ForEach(summary.coveredDays, id: \.start) { day in
                        Text(day.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    }
                }
            }

            Section("Activity") {
                diagnosticMetric("Active energy exact total", state: viewModel.activeEnergyState, unit: "kcal")
                diagnosticMetric("Exercise exact total", state: viewModel.exerciseState, unit: "min")
                if case .available(let summary) = viewModel.workoutState {
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

            if case .available(let summary) = viewModel.sleepState {
                Section("Sleep") {
                    LabeledContent("Valid nights", value: String(summary.nights.count))
                    ForEach(summary.nights) { night in
                        LabeledContent(
                            night.wakeDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                            value: HealthReportFormatter.duration(night.duration)
                        )
                    }
                }
            }

            if case .available(let summary) = viewModel.medicationState {
                Section("Medication Taken Events") {
                    LabeledContent("Event count", value: String(summary.allDoses.count))
                    ForEach(summary.allDoses) { dose in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dose.medicationName)
                            LabeledContent(
                                diagnosticDate(dose.date),
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
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func heartSection(
        title: String,
        summary: HeartMetricTrendSummary,
        unit: String
    ) -> some View {
        Section(title) {
            LabeledContent("Current valid days", value: String(summary.current.validDayCount))
            if let previous = summary.previous {
                LabeledContent("Previous valid days", value: String(previous.validDayCount))
            }
            Text("Current period").font(.headline)
            heartValues(summary.current.dailyValues, unit: unit)
            if let previous = summary.previous {
                Text("Previous equivalent period").font(.headline)
                heartValues(previous.dailyValues, unit: unit)
            }
        }
    }

    @ViewBuilder
    private func heartValues(_ values: [DailyHeartMetricValue], unit: String) -> some View {
        ForEach(values) { daily in
            LabeledContent(
                daily.day.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                value: daily.value.map {
                    "\($0.formatted(.number.precision(.fractionLength(3)))) \(unit)"
                } ?? "No visible data"
            )
        }
    }

    @ViewBuilder
    private func diagnosticMetric(
        _ label: String,
        state: MetricState<Double>,
        unit: String
    ) -> some View {
        if case .available(let value) = state {
            LabeledContent(
                label,
                value: "\(value.formatted(.number.precision(.fractionLength(3)))) \(unit)"
            )
        }
    }

    private func diagnosticDate(_ date: Date) -> String {
        HealthReportFormatter.dateAndTime(date)
    }

    private func diagnosticBloodPressure(_ systolic: Double, _ diastolic: Double) -> String {
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(3))
        return "\(systolic.formatted(format))/\(diastolic.formatted(format)) mmHg"
    }

    @ViewBuilder
    private func bloodPressurePeriodDiagnostic(
        _ label: String,
        _ summary: BloodPressurePeriodSlotSummary?
    ) -> some View {
        if let summary {
            LabeledContent(
                label,
                value: "\(diagnosticBloodPressure(summary.averageSystolic, summary.averageDiastolic)); \(summary.sampledDayCount)/\(summary.reportingDayCount) days; \(summary.readingCount) readings"
            )
        } else {
            LabeledContent(label, value: "No visible period data")
        }
    }

    @ViewBuilder
    private func bloodPressureBatchDiagnostic(
        _ label: String,
        _ batch: BloodPressureBatchSummary?
    ) -> some View {
        if let batch {
            LabeledContent(
                label,
                value: "\(diagnosticBloodPressure(batch.averageSystolic, batch.averageDiastolic)); \(batch.readingCount) readings; \(diagnosticDate(batch.latestReadingDate))"
            )
        } else {
            LabeledContent(label, value: "No visible data")
        }
    }

    private func diagnosticPercentage(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3))))%"
    }

    private func diagnosticWeight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3)))) kg"
    }

    @ViewBuilder
    private func vo2Window(_ label: String, _ window: VO2MaxWindowSummary) -> some View {
        LabeledContent(
            label,
            value: window.average.map(diagnosticVO2Max)
                ?? "Insufficient data (\(window.sampledDayCount) sampled days)"
        )
    }

    private func diagnosticVO2Max(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3)))) mL/kg/min"
    }
}
