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
                    Text(Self.configurationUnavailableText)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    LabeledContent("Account", value: session.accountLabel)
                    Button("Connect with Google") { perform(.connect) }
                        .disabled(session.busy)
                    if session.hasStoredGoogleSession {
                        Button("Sign out locally") { perform(.signOut) }
                            .disabled(session.busy)
                        Button("Revoke Google access", role: .destructive) {
                            perform(.revoke)
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
                            perform(.chooseFolder)
                        }
                        .disabled(session.busy || !session.isConfigured)
                    }
                    if session.presentationState.actions.contains(.createDestination) {
                        Button("Create new export folder") {
                            perform(.createFolder)
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

    /// The one wording for a build without OAuth configuration, shared with
    /// the Export screen's status.
    static var configurationUnavailableText: String {
        DailyExportStatusCatalogue.status(
            for: .needsAttention(.configurationUnavailable),
            hasStoredSession: false
        )
    }

    private func perform(_ action: DriveDestinationAction) {
        Task { await action.perform(on: session) }
    }

    /// Folder choice needs the account the session validated this run; the
    /// screen never restores it by itself.
    private var hasValidatedAccount: Bool { session.hasValidatedAccount }
}
