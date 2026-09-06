import SwiftUI

@main
struct SyntheticDriveExportApp: App {
    @StateObject private var session = DriveSessionController()

    var body: some Scene {
        WindowGroup {
            ConsentDestinationView(session: session)
        }
    }
}

struct ConsentDestinationView: View {
    @ObservedObject var session: DriveSessionController

    var body: some View {
        NavigationStack {
            List {
                Section("Synthetic consent — no HealthKit") {
                    Text("This disposable harness requests only Google Drive’s drive.file scope. It never uploads a daily JSON file in slice A.")
                    Text(session.status).font(.caption)
                    if session.busy { ProgressView() }
                }

                Section("Account") {
                    LabeledContent("Selected", value: session.accountLabel)
                    Button("Restore secure session") { Task { await session.restore() } }
                        .disabled(session.busy)
                    Button("Sign out locally") { session.signOut() }
                        .disabled(session.busy)
                    Button("Revoke Google access", role: .destructive) {
                        Task { await session.disconnect() }
                    }
                    .disabled(session.busy)
                    Text("Sign-out removes this installation’s Keychain credential. Revocation also withdraws the Google grant. Neither action deletes Drive folders or exports.")
                        .font(.caption)
                }

                Section("Destination") {
                    LabeledContent("Selected", value: session.destinationLabel)
                    Button("Create WeeklyHealthReport Exports") {
                        Task { await session.createDestination() }
                    }
                    .disabled(session.busy)
                    Button("Choose existing folder") {
                        Task { await session.chooseDestination() }
                    }
                    .disabled(session.busy)
                    Text("The selected account and folder ID are bound in application state. drive.file is per-file/app-created access, not a Google-enforced folder sandbox. This harness does not enumerate the folder or claim that a limited listing proves it empty.")
                        .font(.caption)
                }

                Section("Least-privilege check") {
                    TextField("Unrelated synthetic Drive file ID", text: $session.unrelatedSyntheticFileID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                    Button("Confirm unrelated file is denied") {
                        Task { await session.checkUnrelatedFileDenied() }
                    }
                    .disabled(session.busy)
                    Text("Use only a disposable file created outside this OAuth client and not selected in Picker. The ID is cleared after a successful denial and is never logged.")
                        .font(.caption)
                }
            }
            .navigationTitle("Drive Consent Test")
            .task { await session.restore() }
        }
    }
}
