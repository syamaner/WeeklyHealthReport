import SwiftUI

struct DailyExportView: View {
    @ObservedObject var session: DailyDriveSessionController
    @ObservedObject private var notes: DailyNotesController
    @Environment(\.scenePhase) private var scenePhase
    @State private var exactJSON: ExactJSONInspection?
    @State private var showingTrashedDestinationConfirmation = false
    @State private var showingTrashedFileConfirmation = false

    init(session: DailyDriveSessionController) {
        self.session = session
        _notes = ObservedObject(wrappedValue: session.notes)
    }

    var body: some View {
        Form {
            daySection
            resultSection

            switch session.presentationState {
            case .preparing:
                includedSection
            case .needsGoogleConnection:
                includedSection
            case .needsNutritionSource:
                nutritionSourceSection
                includedSection
            case .readyToExport:
                includedSection
                exportSection
            case .needsAttention:
                if hasVisibleAttentionAction {
                    attentionSection
                }
                if session.presentationState.actions.contains(.authorizeNutrition) {
                    nutritionSourceSection
                }
                includedSection
            }

            driveSection

            Section {
                Text("Workouts include available heart-rate summaries, HealthKit-estimated active energy, native distance and separately evidenced accepted treadmill distance, PacePrompt execution intervals and native heart-rate zones. Missing data stays explicitly unavailable. Interval distance may cover only part of an interval. Individual associated heart-rate readings include timestamps, BPM and source identifiers when available. Gaps are retained; readings are not interpolated.")
                    .font(.caption)
            } header: {
                Text("About the file")
            }
        }
        .sheet(item: $exactJSON) { inspection in
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    Text(inspection.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("Exact JSON")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { exactJSON = nil }
                    }
                }
            }
        }
        .alert(
            "Forget trashed destination?",
            isPresented: $showingTrashedDestinationConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Forget local identity", role: .destructive) {
                Task { await session.forgetTrashedDestination() }
            }
        } message: {
            Text("This forgets the selected folder and every daily file identity tracked inside it on this installation. It does not change or delete anything in Google Drive. You can then explicitly choose an existing folder or create a fresh dedicated folder.")
        }
        .alert(
            session.fileReplacementReason?.confirmationTitle ?? "Replace daily file?",
            isPresented: $showingTrashedFileConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Forget and allow replacement", role: .destructive) {
                Task { await session.confirmFileReplacementOverride() }
            }
        } message: {
            Text(session.fileReplacementReason?.confirmationMessage ?? "")
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            session.reassertReportDay()
            Task { await session.prepareForPresentation() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                notes.activate()
                Task { await session.prepareForPresentation() }
            case .background:
                notes.flushDraft()
            default:
                break
            }
        }
    }

    private var phase: DailyExportPhase {
        DailyExportPhase.resolve(
            setup: session.presentationState.phaseSetup,
            exporting: session.exporting,
            hasPreview: session.preview != nil,
            lastExportOutcome: session.lastExportOutcome
        )
    }

    private var todayID: DailyNoteDayID? { session.availableReportDays.first }

    private var daySection: some View {
        Section {
            Picker("Day", selection: Binding(
                get: { session.selectedReportDay },
                set: { session.selectReportDay($0) }
            )) {
                Text(todayLabel).tag(Optional<DailyNoteDayID>.none)
                ForEach(Array(session.availableReportDays.dropFirst()), id: \.self) { day in
                    Text(DailyExportDayLabel.previousDay(
                        reportDate: day.reportDate,
                        locale: .autoupdatingCurrent
                    ))
                    .tag(Optional(day))
                }
            }
            .disabled(session.busy)
        } header: {
            Text("Day")
        } footer: {
            Text("Today runs from local midnight to the refresh cutoff. Earlier days include the full local day as currently visible in Apple Health. Changing the day discards the old preview, not saved notes.")
        }
    }

    /// The cutoff appears only once a snapshot of today is prepared; the
    /// clock is never read for this label.
    private var todayLabel: String {
        guard let todayID else { return "Today" }
        let summary = session.selectedReportDay == nil ? session.previewSummary : nil
        return DailyExportDayLabel.today(
            todayReportDate: todayID.reportDate,
            previewDataAsOf: summary?.reportDate == todayID.reportDate ? summary?.dataAsOf : nil
        )
    }

    private var resultSection: some View {
        Section {
            switch phase {
            case .notSetUp:
                Label("Not set up", systemImage: "exclamationmark.circle")
                if session.isConfigured {
                    NavigationLink("Set up Google Drive", value: AppRoute.exportDestination)
                }
            case .preparing:
                HStack {
                    ProgressView()
                    Text("Preparing")
                }
            case .prepared:
                Label("Ready to export", systemImage: "doc.badge.clock")
            case .attempting:
                HStack {
                    ProgressView()
                    Text("Exporting")
                }
            case .verified:
                Label("Exported and verified", systemImage: "checkmark.seal")
                if let outcome = session.lastExportOutcome {
                    LabeledContent("Day", value: DailyExportDayLabel.previousDay(
                        reportDate: outcome.reportDate,
                        locale: .autoupdatingCurrent
                    ))
                    LabeledContent("Data up to", value: DailyExportDayLabel.cutoff(
                        outcome.dataAsOf,
                        locale: .autoupdatingCurrent
                    ))
                }
            case .cancelledBeforeSending:
                Label("Cancelled before sending", systemImage: "xmark.circle")
            case .attemptedNotVerified:
                Label("Export attempted, not verified", systemImage: "exclamationmark.triangle")
            case .needsAttention:
                Label("Needs attention", systemImage: "exclamationmark.triangle")
            }
            Text(session.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Last verified", value: session.lastVerifiedLabel)
                .font(.caption)
        } header: {
            Text("Status")
        } footer: {
            Text("Opening this screen restores known choices and prepares a fresh snapshot in memory. Nothing is sent until you choose Export.")
        }
    }

    private var includedSection: some View {
        Section {
            if let summary = session.previewSummary {
                LabeledContent("Health data", value: DailyExportDayLabel.dataAsOf(
                    summary.dataAsOf,
                    reportDate: summary.reportDate,
                    todayReportDate: todayID?.reportDate,
                    locale: .autoupdatingCurrent
                ))
                LabeledContent("Nutrition", value: summary.nutritionSource)
            } else {
                LabeledContent("Health data", value: "Not prepared")
                    .foregroundStyle(.secondary)
                LabeledContent("Nutrition", value: session.nutritionSourceLabel)
            }
            NavigationLink(value: AppRoute.notes) {
                LabeledContent(
                    "Notes for \(notes.currentDayID.reportDate)",
                    value: notes.storageAvailable ? notes.noteCountLabel : "Unavailable"
                )
            }
            .disabled(!notes.storageAvailable)
            if let status = notes.storageStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.red)
                if notes.storageState == .protectedDataUnavailable {
                    Button("Retry notes access") { notes.retryStorageAccess() }
                }
            }
            LabeledContent("Exact file") {
                if let summary = session.previewSummary {
                    Text("\(summary.encodedByteCount.formatted()) bytes")
                } else {
                    Text("Not prepared")
                }
            }
            Button("Review exact JSON") {
                if let text = session.makeExactPreviewText() {
                    exactJSON = ExactJSONInspection(text: text)
                }
            }
            .disabled(session.busy || session.preview == nil)
            Text("Food-log entries are not exported yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Included")
        } footer: {
            Text("Drafts remain local. A saved-note change invalidates the prepared snapshot and disables export until refresh finishes again. The exact file is constructed only when you review it.")
        }
    }

    private var driveSection: some View {
        Section {
            NavigationLink(value: AppRoute.exportDestination) {
                LabeledContent("Google Drive", value: session.destinationLabel)
            }
        } footer: {
            Text("Account and folder are managed in Settings.")
        }
    }

    private var nutritionSourceSection: some View {
        Section("Apple Health nutrition source") {
            LabeledContent("Selected", value: session.nutritionSourceLabel)
            Button("Authorise and refresh visible sources") {
                Task { await session.refreshNutritionSources() }
            }
            .disabled(session.busy)
            if !session.nutritionSources.isEmpty {
                Picker(
                    "Source",
                    selection: Binding(
                        get: { session.selectedNutritionSourceBundleIdentifier ?? "" },
                        set: { session.selectNutritionSource(bundleIdentifier: $0) }
                    )
                ) {
                    Text("Choose a source").tag("")
                    ForEach(session.nutritionSources) { source in
                        Text("\(source.name) · \(source.bundleIdentifier)")
                            .tag(source.bundleIdentifier)
                    }
                }
            }
            if session.canRefreshPreview {
                Button("Refresh preview") {
                    Task { await session.refreshPreview() }
                }
            }
            Text("First-time access and source choice are explicit. Restoration uses only the exact saved bundle identifier and never falls back to combined nutrition.")
                .font(.caption)
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                Task { await session.exportPreview() }
            } label: {
                Text("Export")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.canExport)
            .accessibilityIdentifier("export.export")
            Button("Refresh") {
                Task { await session.refreshPreview() }
            }
            .disabled(!session.canRefreshPreview)
            Button("Cancel export", role: .cancel) {
                session.cancelExport()
            }
            .disabled(!session.exporting)
            if session.presentationState.actions.contains(.recoverCanonicalFile) {
                Button("Recover existing canonical JSON") {
                    Task { await session.recoverSelectedFile() }
                }
                .disabled(session.busy || !session.isConfigured || session.preview == nil)
            }
        } footer: {
            Text("Export preserves these frozen bytes, verifies remote metadata and exact bytes, and never queues an automatic retry.")
        }
    }

    /// Mirrors the conditions inside `attentionSection`, so the section is
    /// hidden rather than shown as an empty header.
    private var hasVisibleAttentionAction: Bool {
        let actions = session.presentationState.actions
        return !actions.isDisjoint(with: [
            .connect, .chooseDestination, .createDestination, .recoverCanonicalFile, .retry
        ]) || session.canForgetTrashedDestination || session.fileReplacementReason != nil
    }

    private var attentionSection: some View {
        Section("Needs attention") {
            if session.presentationState.actions.contains(.connect) {
                Button("Connect with Google") { Task { await session.connect() } }
                    .disabled(session.busy || !session.isConfigured)
            }
            if session.presentationState.actions.contains(.chooseDestination) {
                Button("Choose existing folder") {
                    Task { await session.chooseDestination() }
                }
                .disabled(session.busy || !session.isConfigured)
            }
            if session.presentationState.actions.contains(.createDestination) {
                Button("Create new export folder") {
                    Task { await session.createDestination() }
                }
                .disabled(session.busy || !session.isConfigured)
            }
            if session.canForgetTrashedDestination {
                Button("Forget trashed destination", role: .destructive) {
                    showingTrashedDestinationConfirmation = true
                }
                .disabled(session.busy)
            }
            if session.presentationState.actions.contains(.recoverCanonicalFile) {
                Button("Recover explicitly selected canonical JSON") {
                    Task { await session.recoverSelectedFile() }
                }
                .disabled(session.busy || session.preview == nil || !session.isConfigured)
            }
            if let reason = session.fileReplacementReason {
                Button(reason.buttonTitle, role: .destructive) {
                    showingTrashedFileConfirmation = true
                }
                .disabled(session.busy)
            }
            if session.presentationState.actions.contains(.retry) {
                Button("Retry preparation") {
                    Task { await session.prepareForPresentation() }
                }
                .disabled(session.busy)
            }
        }
    }
}

private struct ExactJSONInspection: Identifiable {
    let id = UUID()
    let text: String
}

private extension DailyDriveSessionController.FileReplacementReason {
    var buttonTitle: String {
        switch self {
        case .trashed: "Replace trashed daily file"
        case .missingOrInaccessible: "Override missing daily file"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .trashed: "Replace trashed daily file?"
        case .missingOrInaccessible: "Override missing or inaccessible file?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .trashed:
            "This forgets only the confirmed trashed file identity on this installation. It does not change or delete anything in Google Drive. Export that report date again to create a fresh canonical file."
        case .missingOrInaccessible:
            "Drive cannot distinguish permanent deletion from lost access here. Continuing forgets only this installation’s identity and may create a duplicate if the original still exists but is inaccessible. No Drive item is changed until you export again."
        }
    }
}
