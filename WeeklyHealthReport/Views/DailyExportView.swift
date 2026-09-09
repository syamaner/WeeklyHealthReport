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
            Section("Private until you export") {
                Text("Opening this screen restores known choices and prepares a fresh snapshot in memory. Nothing is sent until you choose Export.")
                Text(session.status)
                    .font(.caption)
                if session.busy { ProgressView() }
            }

            switch session.presentationState {
            case .preparing:
                EmptyView()
            case .needsGoogleConnection:
                googleConnectionSection
                notesSection
            case .needsNutritionSource:
                accountContextSection
                nutritionSourceSection
                notesSection
            case .readyToExport:
                accountContextSection
                notesSection
                snapshotSection
                exportSection
            case .needsAttention:
                accountContextSection
                attentionSection
                if session.presentationState.actions.contains(.authorizeNutrition) {
                    nutritionSourceSection
                }
                notesSection
                if session.preview != nil {
                    snapshotSection
                }
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
        .navigationTitle("Daily JSON Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
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

    private var googleConnectionSection: some View {
        Section("Google account") {
            if !session.isConfigured {
                Text("Drive is disabled because this build has no production OAuth client configuration.")
                    .foregroundStyle(.secondary)
            } else {
                Button("Connect with Google") { Task { await session.connect() } }
                    .disabled(session.busy)
                if session.hasStoredGoogleSession {
                    Menu("Stored account options") {
                        Button("Sign out locally") { session.signOut() }
                        Button("Revoke Google access", role: .destructive) {
                            Task { await session.disconnect() }
                        }
                    }
                    .disabled(session.busy)
                }
                Text("Connection requests drive.file only. Consent never runs merely because this screen opened.")
                    .font(.caption)
            }
        }
    }

    private var accountContextSection: some View {
        Section("Export destination") {
            LabeledContent("Account", value: session.accountLabel)
            LabeledContent("Folder", value: session.destinationLabel)
            Menu("Account and folder options") {
                Button("Choose existing folder") {
                    Task { await session.chooseDestination() }
                }
                if session.presentationState.actions.contains(.recoverCanonicalFile) {
                    Button("Recover existing canonical JSON") {
                        Task { await session.recoverSelectedFile() }
                    }
                    .disabled(session.preview == nil)
                }
                Button("Sign out locally") { session.signOut() }
                Button("Revoke Google access", role: .destructive) {
                    Task { await session.disconnect() }
                }
            }
            .disabled(session.busy || !session.isConfigured)
            Text("Sign-out clears this installation’s credential. Revocation also withdraws the grant. Neither deletes Drive files.")
                .font(.caption)
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
                        Text("\(source.name) — \(source.bundleIdentifier)")
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

    private var notesSection: some View {
        Section("Today’s notes") {
            LabeledContent("Saved", value: notes.noteCountLabel)
            NavigationLink("Manage notes", value: WeeklyReportRoute.notes)
                .disabled(!notes.storageAvailable)
            Text("Drafts remain local. A saved-note change invalidates the prepared snapshot and disables export until refresh finishes again.")
                .font(.caption)
            if !notes.storageAvailable {
                Text("Saved notes are unavailable. The existing file was left unchanged.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var snapshotSection: some View {
        Section("Prepared daily snapshot") {
            if let summary = session.previewSummary {
                LabeledContent("Report date", value: summary.reportDate)
                LabeledContent("Data cutoff", value: summary.dataAsOf)
                LabeledContent("Nutrition source", value: summary.nutritionSource)
                LabeledContent("Saved notes", value: summary.savedNoteCount.formatted())
                LabeledContent("Current completed days", value: summary.currentWindow)
                LabeledContent("Previous completed days", value: summary.previousWindow)
                LabeledContent(
                    "Encoded JSON",
                    value: "\(summary.encodedByteCount.formatted()) bytes"
                )
                Button("Review exact JSON") {
                    if let text = session.makeExactPreviewText() {
                        exactJSON = ExactJSONInspection(text: text)
                    }
                }
                .disabled(session.busy)
                Text("The inspector shows the exact compact canonical bytes. It is constructed only when opened.")
                    .font(.caption)
            } else {
                Text("No preview in memory.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportSection: some View {
        Section("Export") {
            Button("Export prepared snapshot") {
                Task { await session.exportPreview() }
            }
            .disabled(!session.canExport)
            Button("Refresh") {
                Task { await session.refreshPreview() }
            }
            .disabled(!session.canRefreshPreview)
            Button("Cancel active export", role: .cancel) {
                session.cancelExport()
            }
            .disabled(!session.exporting)
            LabeledContent("Last verified", value: session.lastVerifiedLabel)
            Text("Export preserves these frozen bytes, verifies remote metadata and exact bytes, and never queues an automatic retry.")
                .font(.caption)
        }
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
