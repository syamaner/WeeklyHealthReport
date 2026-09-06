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
                    Text("This disposable harness requests only Google Drive’s drive.file scope and uploads only three fixed invented JSON fixtures for slice B. It never queries HealthKit.")
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

                Section("Canonical synthetic transport") {
                    Picker("Fixture set", selection: $session.fixtureSet) {
                        ForEach(DriveSessionController.FixtureSet.allCases) { fixtureSet in
                            Text(fixtureSet.rawValue).tag(fixtureSet)
                        }
                    }
                    .disabled(session.busy)
                    Button("Upload morning fixture (1)") {
                        Task { await session.exportSynthetic(revision: 1) }
                    }
                    .disabled(session.busy)
                    Button("Upload evening fixture (2)") {
                        Task { await session.exportSynthetic(revision: 2) }
                    }
                    .disabled(session.busy)
                    Button("Upload bedtime fixture (3)") {
                        Task { await session.exportSynthetic(revision: 3) }
                    }
                    .disabled(session.busy)
                    Button("Cancel active export", role: .cancel) {
                        session.cancelSyntheticExport()
                    }
                    .disabled(!session.exporting)
                    Button("Recover explicitly selected canonical JSON") {
                        Task { await session.recoverSyntheticFile() }
                    }
                    .disabled(session.busy)
                    Text("Only the three fixed invented payloads are admitted. The first release assumes one active exporting installation. Ambiguous account, destination or file recovery fails closed and never creates a replacement. There is no offline queue.")
                        .font(.caption)
                }

                Section("Build 6 adverse probes") {
                    Button("Retry adverse morning create with reserved ID") {
                        Task { await session.retryAdverseCreateWithReservedID() }
                    }
                    .disabled(session.busy)
                    Button("Cancel adverse evening before submission") {
                        Task { await session.cancelAdverseEveningBeforeSubmission() }
                    }
                    .disabled(session.busy)
                    Button("Leave adverse evening unresolved") {
                        Task { await session.leaveAdverseEveningUnresolved() }
                    }
                    .disabled(session.busy)
                    Button("Retry adverse evening after lost response") {
                        Task { await session.reconcileAdverseEveningAfterLostResponse() }
                    }
                    .disabled(session.busy)
                    Button("Cancel adverse bedtime after submission") {
                        Task { await session.cancelAdverseBedtimeAfterSubmission() }
                    }
                    .disabled(session.busy)
                    Button("Force token refresh and reverify bedtime") {
                        Task { await session.forceRefreshAndReverifyBedtime() }
                    }
                    .disabled(session.busy)
                    Button("Simulate expired credential") {
                        Task { await session.simulateCredentialFailure(.expired) }
                    }
                    .disabled(session.busy)
                    Button("Simulate denied credential") {
                        Task { await session.simulateCredentialFailure(.denied) }
                    }
                    .disabled(session.busy)
                    Button("Simulate revoked credential") {
                        Task { await session.simulateCredentialFailure(.revoked) }
                    }
                    .disabled(session.busy)
                    Button("Lose canonical registry but keep marker", role: .destructive) {
                        session.simulateMissingCanonicalIdentity()
                    }
                    .disabled(session.busy)
                    Text("Use only the Adverse 7 Sep fixture set for the ordered create/cancellation/lost-response probes. They suppress or discard bounded client requests without changing IDs or payloads. The identity-loss probe is local-only and deliberately requires explicit Picker recovery.")
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
            .task {
                if await session.runLocalOnlyLaunchProbeIfRequested() { return }
                await session.restore()
                await session.runLaunchProbeIfRequested()
            }
        }
    }
}
