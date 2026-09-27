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
struct FoodIntakeHomeView: View {
    let root: FoodLedgerCompositionRoot?
    var isHome = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Date()
    @State private var projection: FoodIntakeProjection?
    @State private var failure: String?
    @State private var editModel: FoodConfirmationViewModel?
    @State private var showsEdit = false
    @State private var recentDays: [FoodIntakeDayPreview] = []
    @State private var pendingRemoval: FoodIntakeLogRow?
    @State private var confirmsRemoval = false
    @State private var managementFailure: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Form {
            Section {
                if isHome {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Your intake so far").font(.title2.bold())
                        Text("Logged food on this device").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                } else {
                    HStack {
                        Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Previous day")
                        DatePicker("Food log date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden().frame(maxWidth: .infinity)
                            .accessibilityLabel("Food log date")
                        Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Next day").disabled(Calendar.current.isDateInToday(selectedDate))
                    }.buttonStyle(.borderless)
                    if !Calendar.current.isDateInToday(selectedDate) {
                        Button("Return to today") { selectedDate = Date() }
                    }
                }
            }
            if !isHome {
                Section {
                    NavigationLink(value: WeeklyReportRoute.genericFoodSearch) { Label("Search foods", systemImage: "magnifyingglass") }
                    NavigationLink(value: WeeklyReportRoute.barcodeFoodCapture) { Label("Scan barcode", systemImage: "barcode.viewfinder") }
                    NavigationLink(value: WeeklyReportRoute.commonFoods) { Label("Common foods & favourites", systemImage: "star") }
                    NavigationLink(value: WeeklyReportRoute.foodListImport) { Label("Paste or dictate food list", systemImage: "list.bullet") }
                } header: { Text("Log food") } footer: {
                    if !Calendar.current.isDateInToday(selectedDate) {
                        Text("New foods are logged for today. Existing entries on this day can be reviewed below. Changes do not update an already exported snapshot.")
                    }
                }
            }
            if let failure {
                Section("Intake unavailable") {
                    Label(failure, systemImage: "exclamationmark.triangle")
                    Button("Try again") { reload() }
                }
            } else if let projection {
                Section {
                    if projection.rows.isEmpty {
                        ContentUnavailableView("No food logged", systemImage: "fork.knife",
                            description: Text("Logged intake will appear here after you confirm a food. An empty log does not mean no food was eaten."))
                    } else {
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            ForEach(summaryKeys, id: \.rawValue) { key in
                                if let total = projection.summary.totals.first(where: { $0.key == key }) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label(Self.label(key), systemImage: Self.symbol(key))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        Text(Self.amount(total)).font(.title2.weight(.semibold)).monospacedDigit()
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(total.incompleteContributions > 0 ? "\(total.incompleteContributions) entries incomplete" : total.includesEstimates ? "Includes estimates" : "Known values")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Logged intake · \(projection.summary.itemCount) entries")
                } footer: {
                    Text("Totals cover known values only. Missing or bounded nutrients are not counted as zero.")
                }
                if isHome {
                    Section {
                        NavigationLink(value: WeeklyReportRoute.foodLog) {
                            actionLabel("Manage food intake", subtitle: "Review entries, search foods or scan a barcode", symbol: "fork.knife.circle.fill")
                        }
                        NavigationLink(value: WeeklyReportRoute.dailyExport) {
                            actionLabel("Export health data", subtitle: "Prepare and review your Apple Health export", symbol: "square.and.arrow.up.circle.fill")
                        }
                    }
                }
                if !projection.rows.isEmpty {
                    Section(isHome ? "Recent food entries" : "Food entries") {
                        ForEach(displayedRows(projection), id: \.logItemID) { row in
                            entryButton(row)
                                .swipeActions(allowsFullSwipe: false) {
                                    if !isHome {
                                        Button("Remove", role: .destructive) {
                                            pendingRemoval = row; confirmsRemoval = true
                                        }
                                    }
                                }
                                .contextMenu {
                                    if !isHome {
                                        Button("Remove from log", role: .destructive) {
                                            pendingRemoval = row; confirmsRemoval = true
                                        }
                                    }
                                }
                        }
                        if isHome && projection.rows.count > 3 {
                            NavigationLink("View all \(projection.rows.count) entries", value: WeeklyReportRoute.foodLog)
                        }
                    }
                }
                if !isHome && !projection.removedRows.isEmpty {
                    Section {
                        ForEach(projection.removedRows, id: \.logItemID) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.name).font(.body.weight(.medium))
                                Text(Self.entryDetail(row)).font(.subheadline).foregroundStyle(.secondary)
                                Button("Restore entry") { changeEntry(row, restoring: true) }
                                    .frame(minHeight: 44)
                                    .accessibilityLabel("Restore \(row.name)")
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("Removed entries") } footer: {
                        Text("Excluded from this day's totals. Saved evidence and history are retained. Restoring does not change an already exported snapshot.")
                    }
                }
            } else {
                Section { ProgressView("Loading intake") }
            }
            if !isHome {
                Section("Past 7 days") {
                    ForEach(recentDays, id: \.date) { day in
                        Button { selectedDate = day.date } label: {
                            HStack {
                                Text(day.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let summary = day.summary {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(summary.itemCount == 0 ? "No entries" : "\(summary.itemCount) entries")
                                        if summary.itemCount > 0,
                                           let energy = summary.totals.first(where: { $0.key == .energyConsumed }) {
                                            Text(Self.amount(energy)).font(.caption)
                                        }
                                    }.foregroundStyle(.secondary)
                                } else {
                                    Text("Unavailable").foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                        }.accessibilityHint("Shows this day's food log")
                    }
                }
                Section("Review") {
                    NavigationLink("Receipts and food inventory", value: WeeklyReportRoute.inventoryReview)
                    NavigationLink("Nutrition updates", value: WeeklyReportRoute.foodReresolution)
                }
            } else {
                if projection == nil || failure != nil {
                    Section("Manage your day") {
                        NavigationLink("Manage food intake", value: WeeklyReportRoute.foodLog)
                        NavigationLink("Export health data", value: WeeklyReportRoute.dailyExport)
                    }
                }
                Section("Review") {
                    NavigationLink(value: WeeklyReportRoute.healthReport) { Label("View health report", systemImage: "heart.text.square") }
                }
            }
        }
        .navigationTitle(isHome ? "Today" : "Food Log")
        .onAppear { reload() }
        .onChange(of: selectedDate) { reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
        .refreshable { reload() }
        .confirmationDialog("Remove this food entry?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove entry", role: .destructive) {
                if let pendingRemoval { changeEntry(pendingRemoval, restoring: false) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("The entry will leave this day's totals. You can restore it from Removed entries; its saved evidence and history remain.")
        }
        .alert("Entry unchanged", isPresented: Binding(get: { managementFailure != nil },
                                                     set: { if !$0 { managementFailure = nil } })) {
            Button("OK") { managementFailure = nil }
        } message: { Text(managementFailure ?? "") }
        .sheet(isPresented: $showsEdit, onDismiss: { reload() }) {
            NavigationStack {
                if let editModel {
                    FoodConfirmationView(model: editModel) { showsEdit = false }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showsEdit = false } } }
                }
            }
        }
    }

    private var summaryKeys: [NutrientKey] {
        isHome ? [.energyConsumed, .protein, .carbohydrates, .fatTotal]
            : [.energyConsumed, .protein, .carbohydrates, .fatTotal, .fiber]
    }

    private func displayedRows(_ projection: FoodIntakeProjection) -> [FoodIntakeLogRow] {
        isHome ? Array(projection.rows.suffix(3)) : projection.rows
    }

    private func entryButton(_ row: FoodIntakeLogRow) -> some View {
        Button { open(row) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if let energy = row.totals.first(where: { $0.key == .energyConsumed }) {
                        Text(Self.amount(energy)).font(.subheadline).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(Self.entryDetail(row)).font(.subheadline).foregroundStyle(.secondary)
                Text(Self.sourceStatus(row)).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }.accessibilityHint("Opens the saved food confirmation")
    }

    private func changeEntry(_ row: FoodIntakeLogRow, restoring: Bool) {
        do {
            guard let root else { throw FoodIntakeProjectionError.missingReference }
            try root.changeLogEntry(row, restoring: restoring)
            reload()
        } catch {
            managementFailure = "The entry could not be changed. Refresh the log and try again."
        }
    }

    private func moveDay(_ offset: Int) {
        if let day = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate), day <= Date() { selectedDate = day }
    }

    private func open(_ row: FoodIntakeLogRow) {
        do {
            editModel = try root?.model(reopening: row.logItemID)
            guard editModel != nil else { throw FoodIntakeProjectionError.missingReference }
            showsEdit = true
        } catch { failure = "This entry could not be opened. Your saved food is unchanged." }
    }

    private func actionLabel(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        }.accessibilityElement(children: .combine)
    }

    private static func entryDetail(_ row: FoodIntakeLogRow) -> String {
        let time = row.occurredAt.formatted(date: .omitted, time: .shortened)
        let quantity = row.quantity.value.formatted(.number.precision(.fractionLength(0...2)))
        return "\(time) · \(quantity) \(row.quantity.unit.rawValue)"
    }

    private static func sourceStatus(_ row: FoodIntakeLogRow) -> String {
        let names = row.sourceIDs.map { source in
            if source == "cofid" { return "UK CoFID" }
            if source.hasPrefix("usda-") { return "USDA" }
            if source == "open-food-facts" { return "Open Food Facts" }
            return "Saved food source"
        }
        let source = Array(Set(names)).sorted().joined(separator: " · ")
        let status = row.totals.contains { $0.includesEstimates } ? "Source estimate" : "Saved nutrition"
        let incomplete = row.totals.contains { $0.incompleteContributions > 0 } ? " · Incomplete nutrients" : ""
        return (source.isEmpty ? status : source + " · " + status) + incomplete
    }

    private static func symbol(_ key: NutrientKey) -> String {
        switch key { case .energyConsumed: "flame"; case .protein: "p.circle"; case .carbohydrates: "c.circle"; default: "f.circle" }
    }

    private func reload() {
        if isHome && !Calendar.current.isDateInToday(selectedDate) { selectedDate = Date() }
        do {
            guard let root else { throw FoodIntakeProjectionError.missingReference }
            projection = try root.intakeProjection(for: selectedDate)
            if !isHome { recentDays = try root.recentIntakeDays(before: Date()) }
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
        switch key { case .energyConsumed: "Energy"; case .protein: "Protein"; case .carbohydrates: "Carbohydrates"; case .fiber: "Fibre"; default: "Fat" }
    }

    private static func amount(_ total: FoodIntakeTotal) -> String {
        guard let amount = total.knownAmount else { return "Unknown" }
        let value = "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(total.key.canonicalUnit.rawValue)"
        return total.incompleteContributions == 0 ? value : value + " known"
    }
}
