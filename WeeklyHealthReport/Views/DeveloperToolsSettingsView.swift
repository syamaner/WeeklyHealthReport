import SwiftUI

import FoodLedgerPresentation

struct DeveloperToolsSettingsView: View {
    let toggle: SettingsToggle
    var diagnostics: FoodSearchDiagnosticsLog?
    /// Whether this build has Google OAuth configuration (owner decision C moved the detail here).
    var driveExportConfigured: Bool?
    /// The session-wide verified label and the selected day's raw local export record (#217).
    var dailyExport: DailyDriveSessionController?

    var body: some View {
        Form {
            Section("Food search") {
                SettingsToggleRow(toggle: toggle)
            }
            if let diagnostics { FoodSearchDiagnosticsSection(log: diagnostics) }
            if let driveExportConfigured {
                Section("Google Drive export") {
                    LabeledContent("OAuth configuration", value: driveExportConfigured ? "Present" : "Missing")
                    Text(DriveExportAvailability.developerDetail(isConfigured: driveExportConfigured))
                        .font(.caption)
                        .textSelection(.enabled)
                    if let dailyExport { DailyExportRecordRows(session: dailyExport) }
                }
                if let dailyExport { FoodDailyExportDeveloperSection(session: dailyExport) }
            }
            #if DEBUG
            Section("Health report") {
                NavigationLink(value: AppRoute.diagnostics) {
                    Label("Developer diagnostics", systemImage: "stethoscope")
                }
            }
            #endif
        }
        .navigationTitle("Developer tools")
        .onAppear { toggle.reload() }
    }
}

/// Last search and web lookup details: scores, identifiers and stage details. Held in memory
/// for this session only; never persisted and never includes a key.
private struct FoodSearchDiagnosticsSection: View {
    @ObservedObject var log: FoodSearchDiagnosticsLog
    var body: some View {
        Section {
            if log.searchLines.isEmpty && log.webLookupLines.isEmpty && log.pastedLabelLines.isEmpty {
                Text("No search in this session yet.").foregroundStyle(.secondary)
            }
            if !log.searchLines.isEmpty {
                DisclosureGroup("Last search") {
                    ForEach(Array(log.searchLines.enumerated()), id: \.offset) { Text($0.element).font(.caption).textSelection(.enabled) }
                }
            }
            if !log.webLookupLines.isEmpty {
                DisclosureGroup("Last web lookup") {
                    ForEach(Array(log.webLookupLines.enumerated()), id: \.offset) { Text($0.element).font(.caption).textSelection(.enabled) }
                }
            }
            if !log.pastedLabelLines.isEmpty {
                // Only while the label text screen is open; cleared when it closes (#93).
                DisclosureGroup("Pasted label reader") {
                    ForEach(Array(log.pastedLabelLines.enumerated()), id: \.offset) { Text($0.element).font(.caption).textSelection(.enabled) }
                }
            }
        } header: { Text("Search details") } footer: { Text("Kept in memory for this session only.") }
    }
}

/// Raw fields of the selected day's local export record (#217). No file or
/// account identifier is shown.
private struct DailyExportRecordRows: View {
    @ObservedObject var session: DailyDriveSessionController

    var body: some View {
        LabeledContent("Last verified (session)", value: session.lastVerifiedLabel)
        if let lookup = session.lastExportOfSelectedDay {
            ForEach(DailyExportLastExportFormatter.developerFields(lookup), id: \.label) { field in
                LabeledContent(field.label, value: field.value)
                    .textSelection(.enabled)
            }
        } else {
            LabeledContent("Selected day record", value: "No account or folder")
        }
    }
}

/// The prepared food file and its Drive record (#287), so an export is reproducible on device.
private struct FoodDailyExportDeveloperSection: View {
    @ObservedObject var session: DailyDriveSessionController
    @State private var exactJSON: String?

    var body: some View {
        Section {
            let reportDate = session.foodPreparation.preview?.reportDate
                ?? session.lastFoodExportOfSelectedDay?.reportDate
            let record = reportDate.flatMap { session.foodDriveRecord(for: $0) }
            ForEach(FoodDailyExportDeveloperFields.fields(session.foodPreparation, record: record), id: \.label) { field in
                LabeledContent(field.label, value: field.value)
                    .textSelection(.enabled)
            }
            if session.foodPreparation.preview != nil {
                Button("View exact JSON") { exactJSON = session.makeExactFoodPreviewText() }
            }
        } header: {
            Text("Food daily export")
        } footer: {
            Text("The prepared food file and this iPhone's record of it in Drive. Nothing here is sent.")
        }
        .sheet(isPresented: Binding(get: { exactJSON != nil }, set: { if !$0 { exactJSON = nil } })) {
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    Text(exactJSON ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("Food daily export")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { exactJSON = nil } }
                }
            }
        }
    }
}
