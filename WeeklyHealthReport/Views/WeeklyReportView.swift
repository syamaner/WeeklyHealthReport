import SwiftUI
import UIKit
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation

enum WeeklyReportRoute: String, Codable, Hashable {
    case foodLog
    case healthReport
    case dailyExport
    case genericFoodSearch
    case foodListImport
    case barcodeFoodCapture
    case inventoryReview
    case commonFoods
    case foodReresolution
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

    private var reportForm: some View {
        let document = Self.reportDocument(snapshot: viewModel.presentationSnapshot(
            includesMedicationSection: Self.includesMedicationSection,
            showsMorningBloodPressureDetails:
                presentationState.showsMorningBloodPressureDetails,
            showsEveningBloodPressureDetails:
                presentationState.showsEveningBloodPressureDetails
        ))
        return Form {
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
                        NavigationLink("Review Receipts (Optional)", value: WeeklyReportRoute.inventoryReview)
                        NavigationLink("Common Foods & Favourites", value: WeeklyReportRoute.commonFoods)
                        NavigationLink("Review Nutrition Updates", value: WeeklyReportRoute.foodReresolution)
                        Text("Searches UK CoFID and labelled US USDA estimates offline. Review each result before saving.")
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
    }

    private var reportContent: some View {


        return NavigationStack(path: Binding(
            get: { navigation.path },
            set: { navigation.acceptPathChange($0) }
        )) {
            FoodIntakeHomeView(root: foodLedger)
            .navigationTitle("Today")
            .background {
                WeeklyReportScreenshotSceneRegistration(controller: screenshotController)
                    .frame(width: 0, height: 0)
            }
            .navigationDestination(for: WeeklyReportRoute.self) { route in
                switch route {
                case .foodLog:
                    FoodIntakeHomeView(root: foodLedger, isHome: false)
                case .healthReport:
                    reportForm.navigationTitle("Health report")
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
                case .inventoryReview:
                    if let foodLedger, let flow = LocalInventoryFlowView(root: foodLedger) { flow }
                    else { ContentUnavailableView("Receipt review unavailable", systemImage: "exclamationmark.triangle", description: Text("The local inventory store could not be opened. Food search remains separate.")) }
                case .commonFoods:
                    if let foodLedger, let flow = CommonFoodsFlowView(root: foodLedger) { flow }
                    else { ContentUnavailableView("Common foods unavailable", systemImage: "exclamationmark.triangle", description: Text("Your saved foods could not be opened. Try again after unlocking your device.")) }
                case .foodReresolution:
                    if let foodLedger, let flow = FoodReresolutionFlowView(root: foodLedger) { flow }
                    else { ContentUnavailableView("Nutrition review unavailable", systemImage: "exclamationmark.triangle") }
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
        case .foodLog, .healthReport:
            return [destination]
        case .dailyExport:
            return [.dailyExport]
        case .genericFoodSearch:
            return [.genericFoodSearch]
        case .foodListImport:
            return [.foodListImport]
        case .barcodeFoodCapture:
            return [.barcodeFoodCapture]
        case .inventoryReview:
            return [.inventoryReview]
        case .commonFoods:
            return [.commonFoods]
        case .foodReresolution:
            return [.foodReresolution]
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

/// Current-day food intake is separate from completed-day HealthKit reporting.
private struct FoodIntakeHomeView: View {
    let root: FoodLedgerCompositionRoot?
    var isHome = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Date()
    @State private var projection: FoodIntakeProjection?
    @State private var failure: String?
    @State private var editModel: FoodConfirmationViewModel?
    @State private var showsEdit = false

    var body: some View {
        Form {
            Section {
                if isHome {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                            .foregroundStyle(.secondary)
                        Text("Your intake so far").font(.title2.bold())
                    }
                } else {
                    DatePicker("Food log date", selection: $selectedDate, displayedComponents: .date)
                }
                Text("Confirmed food entries on this device.").font(.caption).foregroundStyle(.secondary)
            }
            if let failure {
                Section("Intake unavailable") {
                    Label(failure, systemImage: "exclamationmark.triangle")
                    Button("Try again") { reload() }
                }
            } else if let projection {
                Section("\(projection.summary.itemCount) food entries") {
                    if projection.rows.isEmpty {
                        ContentUnavailableView("No food logged", systemImage: "fork.knife",
                            description: Text("Add your first food to see your intake here."))
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                            ForEach([NutrientKey.energyConsumed, .protein, .carbohydrates, .fatTotal], id: \.rawValue) { key in
                                if let total = projection.summary.totals.first(where: { $0.key == key }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(Self.label(key)).font(.caption).foregroundStyle(.secondary)
                                        Text(Self.amount(total)).font(.title3.bold())
                                        if total.incompleteContributions > 0 {
                                            Text("Incomplete · \(total.incompleteContributions) entries unknown or bounded").font(.caption2)
                                        } else if total.includesEstimates {
                                            Text("Includes source estimates").font(.caption2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                if !isHome && !projection.rows.isEmpty {
                    Section("Food entries") {
                        ForEach(projection.rows, id: \.logItemID) { row in
                            Button {
                                do {
                                    editModel = try root?.model(reopening: row.logItemID)
                                    guard editModel != nil else { throw FoodIntakeProjectionError.missingReference }
                                    showsEdit = true
                                } catch { failure = "This entry could not be opened. Your saved food is unchanged." }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.name).foregroundStyle(.primary)
                                        Text(row.occurredAt, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(row.quantity.value.formatted(.number.precision(.fractionLength(0...2)))) \(row.quantity.unit.rawValue)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                Section { ProgressView("Loading intake") }
            }
            Section(isHome ? "Manage your day" : "Add food") {
                if isHome {
                    NavigationLink(value: WeeklyReportRoute.foodLog) { Label("Manage food intake", systemImage: "fork.knife") }
                } else {
                    NavigationLink("Search foods", value: WeeklyReportRoute.genericFoodSearch)
                    NavigationLink("Scan barcode", value: WeeklyReportRoute.barcodeFoodCapture)
                    NavigationLink("Paste or dictate food list", value: WeeklyReportRoute.foodListImport)
                    NavigationLink("Common foods & favourites", value: WeeklyReportRoute.commonFoods)
                    NavigationLink("Review receipts", value: WeeklyReportRoute.inventoryReview)
                    NavigationLink("Review nutrition updates", value: WeeklyReportRoute.foodReresolution)
                }
            }
            if isHome {
                Section("Health data") {
                    NavigationLink(value: WeeklyReportRoute.dailyExport) { Label("Export health data", systemImage: "square.and.arrow.up") }
                    NavigationLink(value: WeeklyReportRoute.healthReport) { Label("View health report", systemImage: "heart.text.square") }
                }
            }
        }
        .navigationTitle(isHome ? "Today" : "Food Log")
        .onAppear { reload() }
        .onChange(of: selectedDate) { reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .sheet(isPresented: $showsEdit, onDismiss: { reload() }) {
            NavigationStack {
                if let editModel {
                    FoodConfirmationView(model: editModel) { showsEdit = false }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showsEdit = false } } }
                }
            }
        }
    }

    private func reload() {
        if isHome && !Calendar.current.isDateInToday(selectedDate) { selectedDate = Date() }
        do {
            guard let root else { throw FoodIntakeProjectionError.missingReference }
            projection = try root.intakeProjection(for: selectedDate)
            failure = nil
        } catch FoodIntakeProjectionError.competingVersions {
            projection = nil; failure = "Conflicting food versions need review before an intake total can be shown."
        } catch FoodIntakeProjectionError.unsupportedMixture {
            projection = nil; failure = "This day includes a mixed meal that cannot yet be totalled safely."
        } catch {
            projection = nil; failure = "The local food log could not be read. Unlock your device and try again."
        }
    }

    private static func label(_ key: NutrientKey) -> String {
        switch key { case .energyConsumed: "Energy"; case .protein: "Protein"; case .carbohydrates: "Carbohydrates"; default: "Fat" }
    }

    private static func amount(_ total: FoodIntakeTotal) -> String {
        guard let amount = total.knownAmount else { return "Unknown" }
        let value = "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(total.key.canonicalUnit.rawValue)"
        return total.incompleteContributions == 0 ? value : value + " known"
    }
}
