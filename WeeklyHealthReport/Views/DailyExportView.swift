import SwiftUI

struct DailyExportView: View {
    @ObservedObject var session: DailyDriveSessionController
    @State private var showingPreview = false
    @State private var showingTrashedDestinationConfirmation = false
    @State private var showingTrashedFileConfirmation = false

    var body: some View {
        Form {
            Section("Private until you export") {
                Text("Refresh reads a new daily snapshot from Apple Health into memory. Nothing is sent until you review the preview and choose Export.")
                Text(session.status)
                    .font(.caption)
                if session.busy { ProgressView() }
            }

            Section("Google account") {
                LabeledContent("Selected", value: session.accountLabel)
                if !session.isConfigured {
                    Text("Drive is disabled because this build has no production OAuth client configuration.")
                        .foregroundStyle(.secondary)
                }
                Button("Connect with Google") { Task { await session.connect() } }
                    .disabled(session.busy || !session.isConfigured)
                Button("Restore secure session") { Task { await session.restore() } }
                    .disabled(session.busy || !session.isConfigured)
                Button("Sign out locally") { session.signOut() }
                    .disabled(session.busy)
                Button("Revoke Google access", role: .destructive) {
                    Task { await session.disconnect() }
                }
                .disabled(session.busy || !session.isConfigured)
                Text("Sign-out clears this installation’s credential. Revocation also withdraws the grant. Neither deletes Drive files.")
                    .font(.caption)
            }

            Section("Destination") {
                LabeledContent("Selected", value: session.destinationLabel)
                Button("Create WeeklyHealthReport Exports") {
                    Task { await session.createDestination() }
                }
                .disabled(session.busy || !session.isConfigured)
                Button("Choose existing folder") {
                    Task { await session.chooseDestination() }
                }
                .disabled(session.busy || !session.isConfigured)
                if session.canForgetTrashedDestination {
                    Button("Forget trashed destination", role: .destructive) {
                        showingTrashedDestinationConfirmation = true
                    }
                    .disabled(session.busy)
                }
                Text("The app binds one account and folder ID. drive.file is per-file access, not a folder sandbox; folder contents are never enumerated.")
                    .font(.caption)
            }

            Section("Apple Health nutrition source") {
                LabeledContent("Selected", value: session.nutritionSourceLabel)
                Button("Refresh visible nutrition sources") {
                    Task { await session.refreshNutritionSources() }
                }
                .disabled(session.busy)
                if !session.nutritionSources.isEmpty {
                    Picker(
                        "Source",
                        selection: Binding(
                            get: {
                                session.selectedNutritionSourceBundleIdentifier ?? ""
                            },
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
                Text("Nutrition is read only from the selected bundle identifier. Missing values remain No data; the app never falls back to totals from every source.")
                    .font(.caption)
            }

            Section("Daily snapshot") {
                Button("Refresh preview from Apple Health") {
                    Task { await session.refreshPreview() }
                }
                .disabled(!session.canRefreshPreview)
                if let preview = session.preview {
                    LabeledContent("Report date", value: preview.envelope.reportDate)
                    LabeledContent("Data as of", value: preview.envelope.dataAsOf)
                    if let todayNutrition = preview.envelope.today.nutrition,
                       let nutritionContext = preview.envelope.appContext.nutrition {
                        LabeledContent(
                            "Nutrition source",
                            value: "\(todayNutrition.source.name) — \(todayNutrition.source.bundleIdentifier)"
                        )
                        LabeledContent(
                            "Current completed days",
                            value: "\(nutritionContext.currentWindow.start) to \(nutritionContext.currentWindow.end)"
                        )
                        LabeledContent(
                            "Previous completed days",
                            value: "\(nutritionContext.previousWindow.start) to \(nutritionContext.previousWindow.end)"
                        )
                        Text("Today nutrition is partial from local midnight through Data as of. Each history window contains exactly seven completed local-calendar days.")
                            .font(.caption)
                    }
                    LabeledContent("JSON bytes", value: preview.bytes.count.formatted())
                    DisclosureGroup("Review exact JSON", isExpanded: $showingPreview) {
                        ScrollView(.horizontal) {
                            Text(session.previewText ?? "Preview unavailable")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Text("No preview in memory.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Manual export") {
                Button("Export reviewed preview") {
                    Task { await session.exportPreview() }
                }
                .disabled(!session.canExport)
                Button("Cancel active export", role: .cancel) {
                    session.cancelExport()
                }
                .disabled(!session.exporting)
                Button("Recover explicitly selected canonical JSON") {
                    Task { await session.recoverSelectedFile() }
                }
                .disabled(session.busy || session.preview == nil || !session.isConfigured)
                if let reason = session.fileReplacementReason {
                    Button(reason.buttonTitle, role: .destructive) {
                        showingTrashedFileConfirmation = true
                    }
                    .disabled(session.busy)
                }
                LabeledContent("Last verified", value: session.lastVerifiedLabel)
                Text("The first release supports one active exporting installation. Ambiguous recovery fails closed. There is no automatic or offline queue.")
                    .font(.caption)
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
            Text("This forgets the selected folder and every daily file identity tracked inside it on this installation. It does not change or delete anything in Google Drive. You can then create or choose a fresh destination.")
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
    }
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
