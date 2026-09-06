import SwiftUI

struct DailyExportView: View {
    @ObservedObject var session: DailyDriveSessionController
    @State private var showingPreview = false

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
                Text("The app binds one account and folder ID. drive.file is per-file access, not a folder sandbox; folder contents are never enumerated.")
                    .font(.caption)
            }

            Section("Daily snapshot") {
                Button("Refresh preview from Apple Health") {
                    Task { await session.refreshPreview() }
                }
                .disabled(session.busy)
                if let preview = session.preview {
                    LabeledContent("Report date", value: preview.envelope.reportDate)
                    LabeledContent("Data as of", value: preview.envelope.dataAsOf)
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
                LabeledContent("Last verified", value: session.lastVerifiedLabel)
                Text("The first release supports one active exporting installation. Ambiguous recovery fails closed. There is no automatic or offline queue.")
                    .font(.caption)
            }
        }
        .navigationTitle("Daily JSON Export")
        .navigationBarTitleDisplayMode(.inline)
    }
}
