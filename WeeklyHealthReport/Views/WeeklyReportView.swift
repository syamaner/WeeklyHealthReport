import SwiftUI

struct WeeklyReportView: View {
    @StateObject private var viewModel = WeeklyReportViewModel()

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
                #endif

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
        guard !viewModel.period.completedDays.isEmpty else {
            return "No completed days"
        }
        guard let lastDay = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -1,
            to: viewModel.period.interval.end
        ) else { return "Unavailable" }

        return "\(viewModel.period.interval.start.formatted(.dateTime.day().month(.abbreviated)))–\(lastDay.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func diagnosticDate(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false))
    }
}
