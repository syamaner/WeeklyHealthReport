import SwiftUI

struct DeveloperToolsSettingsView: View {
    let toggle: SettingsToggle

    var body: some View {
        Form {
            Section("Food search") {
                SettingsToggleRow(toggle: toggle)
            }
            #if DEBUG
            Section("Health report") {
                NavigationLink(value: AppRoute.diagnostics) {
                    Label("Developer Diagnostics", systemImage: "stethoscope")
                }
            }
            #endif
        }
        .navigationTitle("Developer tools")
        .onAppear { toggle.reload() }
    }
}
