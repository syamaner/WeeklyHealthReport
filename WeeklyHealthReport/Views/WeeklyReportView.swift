import SwiftUI
import UIKit

struct WeeklyReportView: View {
    @StateObject private var viewModel = WeeklyReportViewModel()
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reporting period", selection: $viewModel.selection) {
                        ForEach(ReportPeriodSelection.allCases) { selection in
                            Text(selection.rawValue).tag(selection)
                        }
                    }
                    .onChange(of: viewModel.selection) {
                        Task { await viewModel.refresh() }
                    }

                    LabeledContent("Period", value: periodText)
                }

                Section("Steps validation") {
                    switch viewModel.state {
                    case .idle, .loading:
                        HStack {
                            ProgressView()
                            Text("Reading Apple Health…")
                        }

                    case .loaded(let summary):
                        LabeledContent(
                            "Average Daily Steps",
                            value: summary.averageDailySteps.formatted(
                                .number.precision(.fractionLength(0))
                            )
                        )
                        LabeledContent(
                            "Weekly Total",
                            value: summary.totalSteps.formatted(
                                .number.precision(.fractionLength(0))
                            )
                        )

                    case .noCompletedDays:
                        Text("There are no completed days in this period yet.")
                            .foregroundStyle(.secondary)

                    case .noDataOrAccess:
                        Text("No step data is visible, or Health access was not granted.")
                            .foregroundStyle(.secondary)

                    case .healthUnavailable:
                        Text("Health data is unavailable on this device.")
                            .foregroundStyle(.secondary)

                    case .failed(let message):
                        Text("Step query failed: \(message)")
                            .foregroundStyle(.red)
                    }
                }

                Section("Weight validation") {
                    switch viewModel.weightState {
                    case .idle, .loading:
                        HStack {
                            ProgressView()
                            Text("Reading latest weight…")
                        }

                    case .available(let measurement):
                        LabeledContent(
                            "Latest Weight",
                            value: HealthReportFormatter.weightKilograms(measurement.kilograms)
                        )
                        LabeledContent(
                            "Measured",
                            value: measurement.date.formatted(date: .abbreviated, time: .shortened)
                        )

                    case .noDataOrAccess:
                        Text("No weight data is visible, or Health access was not granted.")
                            .foregroundStyle(.secondary)

                    case .healthUnavailable:
                        Text("Health data is unavailable on this device.")
                            .foregroundStyle(.secondary)

                    case .failed(let message):
                        Text("Weight query failed: \(message)")
                            .foregroundStyle(.red)
                    }
                }

                Section("Body composition validation") {
                    switch viewModel.bodyFatState {
                    case .idle, .loading:
                        HStack {
                            ProgressView()
                            Text("Reading body-fat history…")
                        }

                    case .available(let summary):
                        LabeledContent(
                            "Body Fat",
                            value: "\(HealthReportFormatter.percentage(summary.latest.percentage)) latest"
                        )
                        if let average = summary.sevenDayAverage {
                            LabeledContent(
                                "7-day Average",
                                value: HealthReportFormatter.percentage(average)
                            )
                        }
                        if let average = summary.current28DayAverage {
                            LabeledContent(
                                "28-day Average",
                                value: HealthReportFormatter.percentage(average)
                            )
                        } else {
                            LabeledContent("28-day Average", value: "Insufficient history")
                                .foregroundStyle(.secondary)
                        }
                        if let trend = summary.trendPercentagePoints {
                            LabeledContent(
                                "Body Fat Trend",
                                value: HealthReportFormatter.percentagePointTrend(trend)
                            )
                        } else {
                            LabeledContent("Body Fat Trend", value: "Insufficient history")
                                .foregroundStyle(.secondary)
                        }

                    case .noDataOrAccess:
                        Text("No body-fat data is visible, or Health access was not granted.")
                            .foregroundStyle(.secondary)

                    case .healthUnavailable:
                        Text("Health data is unavailable on this device.")
                            .foregroundStyle(.secondary)

                    case .failed(let message):
                        Text("Body-fat query failed: \(message)")
                            .foregroundStyle(.red)
                    }

                    switch viewModel.bmiState {
                    case .idle, .loading:
                        HStack {
                            ProgressView()
                            Text("Reading latest BMI…")
                        }
                    case .available(let measurement):
                        LabeledContent("BMI", value: HealthReportFormatter.bmi(measurement.value))
                    case .noDataOrAccess:
                        LabeledContent("BMI", value: "No data")
                            .foregroundStyle(.secondary)
                    case .healthUnavailable:
                        EmptyView()
                    case .failed(let message):
                        Text("BMI query failed: \(message)")
                            .foregroundStyle(.red)
                    }
                }

                Section("Heart") {
                    metricRow(
                        "Resting HR Average",
                        state: viewModel.restingHeartRateState,
                        format: { HealthReportFormatter.heartRate($0.average) }
                    )
                    metricRow(
                        "HRV Average",
                        state: viewModel.hrvState,
                        format: { HealthReportFormatter.hrvMilliseconds($0.average) }
                    )
                }

                Section("Activity") {
                    metricRow(
                        "Active Energy",
                        state: viewModel.activeEnergyState,
                        format: { HealthReportFormatter.energyKilocalories($0) }
                    )
                    metricRow(
                        "Exercise",
                        state: viewModel.exerciseState,
                        format: { HealthReportFormatter.minutes($0) }
                    )
                    metricRow(
                        "Workouts",
                        state: viewModel.workoutState,
                        format: { String($0.count) }
                    )
                    if case .available(let summary) = viewModel.workoutState {
                        LabeledContent(
                            "Workout Time",
                            value: HealthReportFormatter.duration(summary.totalDuration)
                        )
                    }
                }

                Section("Sleep") {
                    metricRow(
                        "Average Sleep",
                        state: viewModel.sleepState,
                        format: { HealthReportFormatter.duration($0.averageDuration) }
                    )
                }

                #if DEBUG
                if case .loaded(let summary) = viewModel.state {
                    Section("Developer diagnostics") {
                        LabeledContent("Query start", value: diagnosticDate(viewModel.period.interval.start))
                        LabeledContent("Query end (exclusive)", value: diagnosticDate(viewModel.period.interval.end))
                        LabeledContent("Time zone", value: TimeZone.autoupdatingCurrent.identifier)
                        LabeledContent("Denominator", value: "\(summary.reportingDayCount) completed days")
                        LabeledContent("Days with data", value: "\(summary.daysWithVisibleData)")

                        ForEach(summary.dailyTotals) { daily in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(daily.day.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    Spacer()
                                    if let steps = daily.steps {
                                        Text(steps.formatted(.number.precision(.fractionLength(0))))
                                            .monospacedDigit()
                                    } else {
                                        Text("No visible data")
                                            .foregroundStyle(.secondary)
                                    }
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

                if case .available(let summary) = viewModel.bodyFatState {
                    Section("Body-fat diagnostics") {
                        LabeledContent(
                            "Latest sample",
                            value: diagnosticPercentage(summary.latest.percentage)
                        )
                        LabeledContent(
                            "Latest timestamp",
                            value: diagnosticDate(summary.latest.date)
                        )
                        if let average = summary.sevenDayAverage {
                            LabeledContent("7-day daily mean", value: diagnosticPercentage(average))
                        }
                        if let average = summary.current28DayAverage {
                            LabeledContent("Current 28d daily mean", value: diagnosticPercentage(average))
                        }
                        if let average = summary.previous28DayAverage {
                            LabeledContent("Previous 28d daily mean", value: diagnosticPercentage(average))
                        }

                        Text("Daily values")
                            .font(.headline)
                        ForEach(summary.dailyValues) { daily in
                            HStack {
                                Text(daily.day.formatted(.dateTime.day().month(.abbreviated).year()))
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(diagnosticPercentage(daily.percentage))
                                        .monospacedDigit()
                                    Text("\(daily.sampleCount) sample\(daily.sampleCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Text("Raw samples")
                            .font(.headline)
                        ForEach(Array(summary.measurements.enumerated()), id: \.offset) { _, sample in
                            HStack {
                                Text(diagnosticDate(sample.date))
                                Spacer()
                                Text(diagnosticPercentage(sample.percentage))
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                if case .available(let measurement) = viewModel.bmiState {
                    Section("BMI diagnostics") {
                        LabeledContent(
                            "Latest BMI",
                            value: measurement.value.formatted(
                                .number.precision(.fractionLength(3))
                            )
                        )
                        LabeledContent(
                            "Latest timestamp",
                            value: diagnosticDate(measurement.date)
                        )
                    }
                }

                if case .available(let summary) = viewModel.restingHeartRateState {
                    heartDiagnostics(title: "Resting HR diagnostics", summary: summary, unit: "bpm")
                }

                if case .available(let summary) = viewModel.hrvState {
                    heartDiagnostics(title: "HRV diagnostics", summary: summary, unit: "ms")
                }

                Section("Activity diagnostics") {
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
                    Section("Sleep diagnostics") {
                        LabeledContent("Valid nights", value: String(summary.nights.count))
                        ForEach(summary.nights) { night in
                            LabeledContent(
                                night.wakeDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                                value: HealthReportFormatter.duration(night.duration)
                            )
                        }
                    }
                }
                #endif

                Section {
                    Button {
                        UIPasteboard.general.string = HealthReportFormatter.clipboardReport(
                            viewModel.reportSnapshot
                        )
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy Report", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.state == .loading)
                }

                Section {
                    Button("Refresh") {
                        Task { await viewModel.refresh() }
                    }
                    .disabled(viewModel.state == .loading)

                    if let refreshed = viewModel.lastRefreshed {
                        LabeledContent(
                            "Last refreshed",
                            value: refreshed.formatted(date: .abbreviated, time: .shortened)
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Weekly Health Report")
            .task {
                // Hosted unit tests launch the app process. Avoid presenting the
                // Health authorization sheet before XCTest can load its bundle.
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
                    return
                }
                await viewModel.refresh()
            }
        }
    }

    private var periodText: String {
        viewModel.period.completedDays.isEmpty
            ? "No completed days"
            : HealthReportFormatter.period(viewModel.period)
    }

    private func diagnosticDate(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false))
    }

    private func diagnosticPercentage(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3))))%"
    }

    @ViewBuilder
    private func metricRow<Value: Equatable>(
        _ label: String,
        state: MetricState<Value>,
        format: (Value) -> String
    ) -> some View {
        switch state {
        case .idle, .loading:
            LabeledContent(label) { ProgressView() }
        case .available(let value):
            LabeledContent(label, value: format(value))
        case .noDataOrAccess:
            LabeledContent(label, value: "No data")
                .foregroundStyle(.secondary)
        case .healthUnavailable:
            LabeledContent(label, value: "Unavailable")
                .foregroundStyle(.secondary)
        case .failed:
            LabeledContent(label, value: "Query failed")
                .foregroundStyle(.red)
        }
    }

    #if DEBUG
    @ViewBuilder
    private func heartDiagnostics(
        title: String,
        summary: HeartMetricSummary,
        unit: String
    ) -> some View {
        Section(title) {
            LabeledContent("Valid days", value: String(summary.validDayCount))
            ForEach(summary.dailyValues) { daily in
                LabeledContent(
                    daily.day.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                    value: daily.value.map {
                        "\($0.formatted(.number.precision(.fractionLength(3)))) \(unit)"
                    } ?? "No visible data"
                )
            }
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
    #endif
}
