import SwiftUI
import UIKit

enum WeeklyReportRoute: String, Codable, Hashable {
    case dailyExport
    case genericFoodSearch
    case foodListImport
    case barcodeFoodCapture
    case notes
    case noteEditor
    case diagnostics
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

@MainActor
final class WeeklyReportPresentationState: ObservableObject {
    @Published var showsMorningBloodPressureDetails = true
    @Published var showsEveningBloodPressureDetails = false
    @Published var showsMedicationAccessHelp = false
    @Published private(set) var isMedicationAuthorizationRequestActive = false

    var isTransientUIPresented: Bool {
        showsMedicationAccessHelp || isMedicationAuthorizationRequestActive
    }

    func beginMedicationAuthorizationRequest() {
        isMedicationAuthorizationRequestActive = true
    }

    func finishMedicationAuthorizationRequest() {
        isMedicationAuthorizationRequestActive = false
    }
}

struct WeeklyReportView: View {
    @ObservedObject var viewModel: WeeklyReportViewModel
    @ObservedObject var dailyExport: DailyDriveSessionController
    @ObservedObject var navigation: WeeklyReportNavigationController
    let medicationAccess: MedicationAccessRequest
    let foodLedger: FoodLedgerCompositionRoot?
    @StateObject private var presentationState = WeeklyReportPresentationState()
    @StateObject private var screenshotController = WeeklyReportScreenshotController()
    @State private var copied = false
    @State private var medicationAuthorizationRequest = 0
    @State private var didRestoreNavigationPath = false
    @AppStorage("hasRequestedMedicationAccess") private var hasRequestedMedicationAccess = false
    @AppStorage("weeklyReport.navigationDestination.v1") private var storedNavigationDestination = ""

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            reportContent
                .medicationAccessRequest(
                    medicationAccess,
                    trigger: medicationAuthorizationRequest
                ) { result in
                    Task { @MainActor in
                        presentationState.finishMedicationAuthorizationRequest()
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
                .sheet(isPresented: $presentationState.showsMedicationAccessHelp) {
                    medicationAccessHelp
                }
        } else {
            reportContent
        }
    }

    private var reportContent: some View {
        let document = Self.reportDocument(snapshot: viewModel.presentationSnapshot(
            includesMedicationSection: Self.includesMedicationSection,
            showsMorningBloodPressureDetails:
                presentationState.showsMorningBloodPressureDetails,
            showsEveningBloodPressureDetails:
                presentationState.showsEveningBloodPressureDetails
        ))

        return NavigationStack(path: Binding(
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

                if foodLedger != nil {
                    Section("Food logging") {
                        NavigationLink("Scan Food Barcode", value: WeeklyReportRoute.barcodeFoodCapture)
                        NavigationLink("Search Generic Foods", value: WeeklyReportRoute.genericFoodSearch)
                        NavigationLink("Paste Food List", value: WeeklyReportRoute.foodListImport)
                        Text("Searches the bundled CoFID release offline. No result is selected automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                ForEach(document.sections) { section in
                    switch section.id {
                    case .bloodPressure:
                        BloodPressureReportSection(
                            section: section,
                            showsMorningDetails:
                                $presentationState.showsMorningBloodPressureDetails,
                            showsEveningDetails:
                                $presentationState.showsEveningBloodPressureDetails
                        )
                    case .medications:
                        if #available(iOS 26.0, *) {
                            MedicationReportSection(
                                section: section,
                                requestAccess: {
                                    presentationState.showsMedicationAccessHelp = true
                                }
                            )
                        }
                    default:
                        ReportDocumentSectionView(section: section)
                    }
                }

                Section {
                    Button {
                        let document = Self.reportDocument(
                            snapshot: viewModel.presentationSnapshot(
                                includesMedicationSection: Self.includesMedicationSection,
                                showsMorningBloodPressureDetails: true,
                                showsEveningBloodPressureDetails: true
                            )
                        )
                        UIPasteboard.general.string = document.plainText(generatedAt: Date())
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
                    .disabled(viewModel.isRefreshing)
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
                    NavigationLink(value: WeeklyReportRoute.diagnostics) {
                        Label("Developer Diagnostics", systemImage: "stethoscope")
                    }
                }
                #endif
            }
            .navigationTitle("Weekly Health Report")
            .background {
                WeeklyReportScreenshotSceneRegistration(controller: screenshotController)
                    .frame(width: 0, height: 0)
            }
            .navigationDestination(for: WeeklyReportRoute.self) { route in
                switch route {
                case .dailyExport:
                    DailyExportView(session: dailyExport)
                case .genericFoodSearch:
                    if let foodLedger,
                       let flow = GenericFoodSearchFlowView(root: foodLedger) {
                        flow
                    } else {
                        ContentUnavailableView(
                            "Food search unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text("The local food ledger could not be opened.")
                        )
                    }
                case .foodListImport:
                    if let foodLedger, let flow = FoodListImportFlowView(root: foodLedger) {
                        flow
                    } else {
                        ContentUnavailableView("Food list unavailable", systemImage: "exclamationmark.triangle")
                    }
                case .barcodeFoodCapture:
                    if let foodLedger { BarcodeFoodFlowView(root: foodLedger) }
                    else { ContentUnavailableView("Food scanner unavailable", systemImage: "exclamationmark.triangle") }
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
                case .diagnostics:
                    DeveloperDiagnosticsView(viewModel: viewModel)
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
                    presentationState.beginMedicationAuthorizationRequest()
                    medicationAuthorizationRequest += 1
                }
            }
            .onAppear {
                configureScreenshotProvider()
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

    private func configureScreenshotProvider() {
        screenshotController.setRequestProvider {
            [weak viewModel, weak navigation, weak presentationState] in
            guard let viewModel,
                  let navigation,
                  let presentationState,
                  WeeklyReportScreenshotEligibility.isEligible(
                    navigationPath: navigation.path,
                    isTransientUIPresented: presentationState.isTransientUIPresented
                  ) else {
                return nil
            }

            guard let snapshot = viewModel.screenshotSnapshot(
                includesMedicationSection: Self.includesMedicationSection,
                showsMorningBloodPressureDetails:
                    presentationState.showsMorningBloodPressureDetails,
                showsEveningBloodPressureDetails:
                    presentationState.showsEveningBloodPressureDetails
            ) else {
                return nil
            }
            return Self.reportDocument(snapshot: snapshot)
        }
    }

    private static func reportDocument(
        snapshot: ReportPresentationSnapshot
    ) -> ReportDocument {
        ReportDocument(snapshot: snapshot)
    }

    private static var includesMedicationSection: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
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
        case .genericFoodSearch:
            return [.genericFoodSearch]
        case .foodListImport:
            return [.foodListImport]
        case .barcodeFoodCapture:
            return [.barcodeFoodCapture]
        case .notes:
            return [.dailyExport, .notes]
        case .noteEditor:
            return hasDraft ? [.dailyExport, .notes, .noteEditor] : [.dailyExport, .notes]
        case .diagnostics:
            return []
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
                        presentationState.showsMedicationAccessHelp = false
                    }
                }
            }
        }
    }
}
