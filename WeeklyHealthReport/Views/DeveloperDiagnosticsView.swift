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

            if case .available(let summary) = viewModel.restingHeartRateState {
                heartSection(title: "Resting Heart Rate", summary: summary, unit: "bpm")
            }

            if case .available(let summary) = viewModel.hrvState {
                heartSection(title: "HRV", summary: summary, unit: "ms")
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
                            value: HealthReportFormatter.duration(workout.duration)
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
        date.formatted(
            .iso8601
                .year().month().day()
                .dateSeparator(.dash)
                .time(includingFractionalSeconds: false)
        )
    }

    private func diagnosticPercentage(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3))))%"
    }

    private func diagnosticWeight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3)))) kg"
    }
}
