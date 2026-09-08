import SwiftUI
import UIKit
import HealthKit
import HealthKitUI

enum WeeklyReportRoute: String, Codable, Hashable {
    case dailyExport
    case notes
    case noteEditor
}

@MainActor
final class WeeklyReportNavigationController: ObservableObject {
    @Published private(set) var path: [WeeklyReportRoute] = []
    private var protectedPath: [WeeklyReportRoute]?

    func acceptPathChange(_ proposedPath: [WeeklyReportRoute]) {
        guard protectedPath == nil else { return }
        path = proposedPath
    }

    func replacePath(_ newPath: [WeeklyReportRoute]) {
        path = newPath
    }

    func append(_ route: WeeklyReportRoute) {
        path.append(route)
    }

    func protectCurrentPath() {
        guard protectedPath == nil, !path.isEmpty else { return }
        protectedPath = path
    }

    func restoreProtectedPath() {
        guard let protectedPath else { return }
        path = protectedPath
        self.protectedPath = nil
    }
}

struct WeeklyReportView: View {
    @ObservedObject var dailyExport: DailyDriveSessionController
    @ObservedObject var navigation: WeeklyReportNavigationController
    @StateObject private var viewModel = WeeklyReportViewModel()
    @State private var copied = false
    @State private var medicationAuthorizationRequest = 0
    @State private var showsMedicationAccessHelp = false
    @State private var showsMorningBloodPressureDetails = true
    @State private var showsEveningBloodPressureDetails = false
    @State private var didRestoreNavigationPath = false
    @AppStorage("hasRequestedMedicationAccess") private var hasRequestedMedicationAccess = false
    @AppStorage("weeklyReport.navigationDestination.v1") private var storedNavigationDestination = ""

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
        NavigationStack(path: Binding(
            get: { navigation.path },
            set: { navigation.acceptPathChange($0) }
        )) {
            Form {
                Section("Export") {
                    NavigationLink("Daily JSON Export", value: WeeklyReportRoute.dailyExport)
                    Text("Refresh, review and export are separate manual actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

                StepsReportSection(state: viewModel.state)
                BodyMeasurementsReportSections(
                    weightState: viewModel.weightState,
                    bodyFatState: viewModel.bodyFatState,
                    waistState: viewModel.waistState
                )
                HeartReportSection(
                    restingHeartRateState: viewModel.restingHeartRateState,
                    hrvState: viewModel.hrvState,
                    watchCoverageState: viewModel.watchCoverageState,
                    comparisonDayCount: viewModel.period.completedDays.count
                )
                BloodPressureReportSection(
                    state: viewModel.bloodPressureState,
                    showsMorningDetails: $showsMorningBloodPressureDetails,
                    showsEveningDetails: $showsEveningBloodPressureDetails
                )
                CardiorespiratoryReportSection(
                    vo2MaxState: viewModel.vo2MaxState,
                    bloodOxygenState: viewModel.bloodOxygenState
                )
                GlucoseReportSection(state: viewModel.glucoseState)
                ActivityReportSection(
                    activeEnergyState: viewModel.activeEnergyState,
                    exerciseState: viewModel.exerciseState,
                    workoutState: viewModel.workoutState
                )
                SleepReportSection(state: viewModel.sleepState)

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
                        Label(
                            copied ? "Copied" : "Copy Report",
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
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
            .navigationDestination(for: WeeklyReportRoute.self) { route in
                switch route {
                case .dailyExport:
                    DailyExportView(session: dailyExport)
                case .notes:
                    DailyNotesView(
                        controller: dailyExport.notes,
                        openEditor: { navigation.append(.noteEditor) }
                    )
                case .noteEditor:
                    DailyNoteEditorView(
                        controller: dailyExport.notes,
                        willOpenApplicationSettings: {
                            navigation.protectCurrentPath()
                        }
                    )
                }
            }
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
            .onAppear {
                guard !didRestoreNavigationPath else { return }
                didRestoreNavigationPath = true
                navigation.replacePath(Self.restoredNavigationPath(
                    from: storedNavigationDestination,
                    hasDraft: dailyExport.notes.currentDraft != nil
                ))
            }
            .onChange(of: navigation.path) { _, path in
                guard didRestoreNavigationPath else { return }
                storedNavigationDestination = path.last?.rawValue ?? ""
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification
                )
            ) { _ in
                navigation.protectCurrentPath()
                if let destination = navigation.path.last?.rawValue {
                    storedNavigationDestination = destination
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification
                )
            ) { _ in
                navigation.restoreProtectedPath()
                if navigation.path.isEmpty {
                    navigation.replacePath(Self.restoredNavigationPath(
                        from: storedNavigationDestination,
                        hasDraft: dailyExport.notes.currentDraft != nil
                    ))
                }
            }
        }
    }

    static func restoredNavigationPath(
        from storedDestination: String,
        hasDraft: Bool
    ) -> [WeeklyReportRoute] {
        guard let destination = WeeklyReportRoute(rawValue: storedDestination) else {
            return []
        }

        switch destination {
        case .dailyExport:
            return [.dailyExport]
        case .notes:
            return [.dailyExport, .notes]
        case .noteEditor:
            return hasDraft ? [.dailyExport, .notes, .noteEditor] : [.dailyExport, .notes]
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
}
