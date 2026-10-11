import SwiftUI

/// Settings > Export: the Google Drive account and folder. Opening this screen
/// sends no HealthKit, OAuth or Drive request and never prepares an export;
/// only the buttons below start work, through the same controller methods the
/// Export screen used before #200.
struct DriveDestinationSettingsView: View {
    @ObservedObject var session: DailyDriveSessionController

    var body: some View {
        Form {
            if !session.isConfigured {
                Section {
                    Text("Drive is disabled because this build has no production OAuth client configuration.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    LabeledContent("Account", value: session.accountLabel)
                    Button("Connect with Google") { Task { await session.connect() } }
                        .disabled(session.busy)
                    if session.hasStoredGoogleSession {
                        Button("Sign out locally") { session.signOut() }
                            .disabled(session.busy)
                        Button("Revoke Google access", role: .destructive) {
                            Task { await session.disconnect() }
                        }
                        .disabled(session.busy)
                    }
                } header: {
                    Text("Google account")
                } footer: {
                    Text("Connection requests drive.file only. Consent never runs merely because this screen opened. Sign-out clears this installation’s credential. Revocation also withdraws the grant. Neither deletes Drive files.")
                }

                Section {
                    LabeledContent("Folder", value: session.destinationLabel)
                    if hasValidatedAccount {
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
                } header: {
                    Text("Folder")
                } footer: {
                    if !hasValidatedAccount {
                        Text("Connect with Google, or open Export to restore the saved account, before choosing a folder. No folder is created automatically.")
                    } else {
                        Text("No folder is created automatically.")
                    }
                }

                Section {
                    Text(session.status)
                        .font(.caption)
                    if session.busy { ProgressView() }
                }
            }
        }
        .navigationTitle("Google Drive")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Folder choice needs the account the session validated this run; the
    /// screen never restores it by itself.
    private var hasValidatedAccount: Bool {
        switch session.presentationState {
        case .preparing, .needsGoogleConnection: false
        case .needsNutritionSource, .readyToExport, .needsAttention: true
        }
    }
}
