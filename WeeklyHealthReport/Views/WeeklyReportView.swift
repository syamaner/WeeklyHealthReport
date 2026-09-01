import SwiftUI
import UIKit
import HealthKit
import HealthKitUI

struct WeeklyReportView: View {
    @StateObject private var viewModel = WeeklyReportViewModel()
    @State private var copied = false
    @State private var medicationAuthorizationRequest = 0
    @State private var showsMedicationAccessHelp = false
    @State private var showsMorningBloodPressureDetails = true
    @State private var showsEveningBloodPressureDetails = false
    @AppStorage("hasRequestedMedicationAccess") private var hasRequestedMedicationAccess = false

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            reportContent
                .healthDataAccessRequest(
                    store: HealthStoreProvider.shared,
                    objectType: .userAnnotatedMedicationType(),
                    trigger: medicationAuthorizationRequest
                ) { result in
                    Task { @MainActor in
                        switch result {
                        case .success:
                            hasRequestedMedicationAccess = true
                            await viewModel.refreshMedications()
                        case .failure(let error):
                            viewModel.setMedicationAuthorizationFailure(
                                error.localizedDescription
                            )
                        }
                    }
                }
                .sheet(isPresented: $showsMedicationAccessHelp) {
                    medicationAccessHelp
                }
        } else {
            reportContent
        }
    }

    private var reportContent: some View {
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

                Section("Steps") {
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

                Section("Weight") {
                    switch viewModel.weightState {
                    case .idle, .loading:
                        HStack {
                            ProgressView()
                            Text("Reading latest weight…")
                        }

                    case .available(let summary):
                        LabeledContent(
                            "Latest Weight",
                            value: HealthReportFormatter.weightKilograms(summary.latest.kilograms)
                        )
                        LabeledContent(
                            "Measured",
                            value: HealthReportFormatter.dateAndTime(summary.latest.date)
                        )
                        if let average = summary.currentSevenDayAverage {
                            LabeledContent(
                                "7-day Average",
                                value: HealthReportFormatter.weightKilograms(average)
                            )
                        } else {
                            LabeledContent("7-day Average", value: "Insufficient history")
                                .foregroundStyle(.secondary)
                        }
                        if let trend = summary.trendKilograms {
                            LabeledContent(
                                "Weight Trend",
                                value: HealthReportFormatter.signedChange(
                                    trend,
                                    unit: "kg",
                                    comparison: "previous 7d"
                                )
                            )
                        } else {
                            LabeledContent("Weight Trend", value: "Insufficient history")
                                .foregroundStyle(.secondary)
                        }

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

                Section("Body Composition") {
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

                    metricRow(
                        "Waist Circumference",
                        state: viewModel.waistState,
                        format: { HealthReportFormatter.waistCentimetres($0.latest.centimetres) }
                    )
                    if case .available(let summary) = viewModel.waistState {
                        LabeledContent(
                            "Waist Measured",
                            value: HealthReportFormatter.dateAndTime(summary.latest.date)
                        )
                        if let change = summary.fourWeekChangeCentimetres {
                            LabeledContent(
                                "4-week Waist Trend",
                                value: HealthReportFormatter.signedChange(
                                    change,
                                    unit: "cm",
                                    comparison: "~4 weeks earlier"
                                )
                            )
                        } else {
                            LabeledContent("4-week Waist Trend", value: "Insufficient history")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Heart") {
                    metricRow(
                        "Resting HR Average",
                        state: viewModel.restingHeartRateState,
                        format: { HealthReportFormatter.heartRate($0.current.average) }
                    )
                    heartTrendRow("Resting HR Trend", state: viewModel.restingHeartRateState, unit: "bpm")
                    metricRow(
                        "HRV Average",
                        state: viewModel.hrvState,
                        format: { HealthReportFormatter.hrvMilliseconds($0.current.average) }
                    )
                    heartTrendRow("HRV Trend", state: viewModel.hrvState, unit: "ms")
                    metricRow(
                        "Watch Data Coverage",
                        state: viewModel.watchCoverageState,
                        format: { "\($0.daysWithWatchData) / \($0.reportingDayCount) days" }
                    )
                }

                Section {
                    switch viewModel.bloodPressureState {
                    case .idle, .loading:
                        HStack {
                            ProgressView()
                            Text("Reading blood pressure…")
                        }
                    case .available(let summary):
                        VStack(alignment: .leading, spacing: 5) {
                            responsiveBloodPressureLabel(
                                "Latest reading",
                                value: HealthReportFormatter.bloodPressure(
                                    systolic: summary.latest.systolicMillimetresOfMercury,
                                    diastolic: summary.latest.diastolicMillimetresOfMercury
                                )
                            )
                            Text(HealthReportFormatter.dateAndTime(summary.latest.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        bloodPressureDisclosure(
                            title: "Morning average",
                            periodSummary: summary.morning,
                            latestBatch: summary.latestMorningBatch,
                            isExpanded: $showsMorningBloodPressureDetails
                        )
                        bloodPressureDisclosure(
                            title: "Evening average",
                            periodSummary: summary.evening,
                            latestBatch: summary.latestEveningBatch,
                            isExpanded: $showsEveningBloodPressureDetails
                        )
                    case .noDataOrAccess:
                        Text("No complete blood-pressure readings are visible, or Health access was not granted.")
                            .foregroundStyle(.secondary)
                    case .healthUnavailable:
                        Text("Health data is unavailable on this device.")
                            .foregroundStyle(.secondary)
                    case .failed(let message):
                        Text("Blood-pressure query failed: \(message)")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Blood Pressure")
                } footer: {
                    Text("Period averages use completed days. Morning is before 14:00; evening is from 17:00. Mid-afternoon readings remain visible in Diagnostics.")
                }

                Section("Cardiorespiratory") {
                    metricRow(
                        "Latest VO₂ Max",
                        state: viewModel.vo2MaxState,
                        format: {
                            HealthReportFormatter.vo2Max(
                                $0.latest.millilitresPerKilogramMinute
                            )
                        }
                    )
                    if case .available(let summary) = viewModel.vo2MaxState {
                        LabeledContent(
                            "VO₂ Max Measured",
                            value: HealthReportFormatter.dateAndTime(summary.latest.date)
                        )
                        LabeledContent(
                            "4-Week Average",
                            value: HealthReportFormatter.vo2MaxWindow(summary.fourWeek)
                        )
                        LabeledContent(
                            "3-Month Average",
                            value: HealthReportFormatter.vo2MaxWindow(summary.threeMonth)
                        )
                        LabeledContent(
                            "6-Month Average",
                            value: HealthReportFormatter.vo2MaxWindow(summary.sixMonth)
                        )
                    }

                    metricRow(
                        "Latest Blood Oxygen",
                        state: viewModel.bloodOxygenState,
                        format: { HealthReportFormatter.bloodOxygen($0.latest.percentage) }
                    )
                    if case .available(let summary) = viewModel.bloodOxygenState {
                        LabeledContent(
                            "Blood Oxygen Measured",
                            value: HealthReportFormatter.dateAndTime(summary.latest.date)
                        )
                        LabeledContent(
                            "Period Typical",
                            value: summary.typicalPercentage.map {
                                HealthReportFormatter.bloodOxygen($0)
                            } ?? "No data"
                        )
                        LabeledContent(
                            "Daily Median Range",
                            value: summary.minimumDailyMedian.flatMap { minimum in
                                summary.maximumDailyMedian.map { maximum in
                                    HealthReportFormatter.bloodOxygenRange(
                                        minimum: minimum,
                                        maximum: maximum
                                    )
                                }
                            } ?? "No data"
                        )
                        LabeledContent(
                            "Blood Oxygen Coverage",
                            value: "\(summary.validDayCount) / \(summary.reportingDayCount) days"
                        )
                    }

                    Text("Apple Watch blood-oxygen measurements are wellness estimates, not medical measurements.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Glucose") {
                    metricRow(
                        "Daily Average",
                        state: viewModel.glucoseState,
                        format: { HealthReportFormatter.glucose($0.averageMillimolesPerLiter) }
                    )
                    metricRow(
                        "Observed Range",
                        state: viewModel.glucoseState,
                        format: {
                            HealthReportFormatter.glucoseRange(
                                minimum: $0.minimumMillimolesPerLiter,
                                maximum: $0.maximumMillimolesPerLiter
                            )
                        }
                    )
                    metricRow(
                        "Data Coverage",
                        state: viewModel.glucoseState,
                        format: { "\($0.validDayCount) / \($0.reportingDayCount) days" }
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
                        ForEach(summary.workouts) { workout in
                            LabeledContent(
                                workout.activityName,
                                value: "\(HealthReportFormatter.duration(workout.duration)) — \(HealthReportFormatter.workoutDateAndTime(workout.startDate))"
                            )
                        }
                    }
                }

                Section("Sleep") {
                    metricRow(
                        "Average Sleep",
                        state: viewModel.sleepState,
                        format: { HealthReportFormatter.duration($0.averageDuration) }
                    )
                }

                if #available(iOS 26.0, *) {
                    Section("Medications Taken") {
                        switch viewModel.medicationState {
                        case .idle, .loading:
                            HStack {
                                ProgressView()
                                Text("Reading authorised medication events…")
                            }
                        case .available(let summary):
                            ForEach(summary.groups) { group in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.medicationName)
                                    Text(HealthReportFormatter.medicationGroupDetail(group))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        case .noDataOrAccess:
                            Text("No taken medication events are visible for this period.")
                                .foregroundStyle(.secondary)
                        case .healthUnavailable:
                            Text("Health data is unavailable on this device.")
                                .foregroundStyle(.secondary)
                        case .failed(let message):
                            Text("Medication query failed: \(message)")
                                .foregroundStyle(.red)
                        }

                        Button("Medication Access") {
                            showsMedicationAccessHelp = true
                        }
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = HealthReportFormatter.clipboardReport(
                            viewModel.reportSnapshot,
                            generatedAt: Date()
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
                            value: HealthReportFormatter.dateAndTime(refreshed)
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                #if DEBUG
                Section {
                    NavigationLink {
                        DeveloperDiagnosticsView(viewModel: viewModel)
                    } label: {
                        Label("Developer Diagnostics", systemImage: "stethoscope")
                    }
                }
                #endif
            }
            .navigationTitle("Weekly Health Report")
            .task {
                // Hosted unit tests launch the app process. Avoid presenting the
                // Health authorization sheet before XCTest can load its bundle.
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
                    return
                }
                await viewModel.refresh()
                if #available(iOS 26.0, *), !hasRequestedMedicationAccess {
                    medicationAuthorizationRequest += 1
                }
            }
        }
    }

    private var periodText: String {
        viewModel.period.completedDays.isEmpty
            ? "No completed days"
            : HealthReportFormatter.period(viewModel.period)
    }

    @available(iOS 26.0, *)
    private var medicationAccessHelp: some View {
        NavigationStack {
            List {
                Section("Change Existing Access") {
                    Text("Open Health, tap your profile picture, then Apps, WeeklyHealthReport, and change which medications the app may read.")
                }

                Section("New Medications") {
                    Text("When you add a medication in Health, turn on WeeklyHealthReport on the final screen before saving it.")
                }

                Section {
                    Text("Apple manages medication access in Health after the initial chooser. Return here and tap Refresh after making a change.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Medication Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showsMedicationAccessHelp = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func responsiveBloodPressureLabel(_ label: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                Spacer(minLength: 8)
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func bloodPressureDisclosure(
        title: String,
        periodSummary: BloodPressurePeriodSlotSummary?,
        latestBatch: BloodPressureBatchSummary?,
        isExpanded: Binding<Bool>
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            responsiveBloodPressureLabel(
                "Latest batch",
                value: latestBatch.map {
                    HealthReportFormatter.bloodPressure(
                        systolic: $0.averageSystolic,
                        diastolic: $0.averageDiastolic
                    )
                } ?? "No data"
            )
            responsiveBloodPressureLabel(
                "Recorded",
                value: latestBatch.map {
                    let count = $0.readingCount == 1
                        ? "1 reading"
                        : "\($0.readingCount) readings"
                    return "\(HealthReportFormatter.dateAndTime($0.latestReadingDate)) · \(count)"
                } ?? "No data"
            )
            responsiveBloodPressureLabel(
                "Coverage",
                value: periodSummary.map {
                    "\($0.sampledDayCount)/\($0.reportingDayCount) days · \($0.readingCount) readings"
                }
                    ?? "No period data"
            )
        } label: {
            responsiveBloodPressureLabel(
                title,
                value: periodSummary.map {
                    HealthReportFormatter.bloodPressure(
                        systolic: $0.averageSystolic,
                        diastolic: $0.averageDiastolic
                    )
                } ?? "No data"
            )
        }
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

    @ViewBuilder
    private func heartTrendRow(
        _ label: String,
        state: MetricState<HeartMetricTrendSummary>,
        unit: String
    ) -> some View {
        switch state {
        case .available(let summary):
            if let trend = summary.trend {
                LabeledContent(
                    label,
                    value: HealthReportFormatter.signedChange(
                        trend,
                        unit: unit,
                        comparison: "previous \(viewModel.period.completedDays.count)d"
                    )
                )
            } else {
                LabeledContent(label, value: "Insufficient history")
                    .foregroundStyle(.secondary)
            }
        case .idle, .loading:
            LabeledContent(label) { ProgressView() }
        case .noDataOrAccess:
            LabeledContent(label, value: "No data").foregroundStyle(.secondary)
        case .healthUnavailable:
            LabeledContent(label, value: "Unavailable").foregroundStyle(.secondary)
        case .failed:
            LabeledContent(label, value: "Query failed").foregroundStyle(.red)
        }
    }

}
