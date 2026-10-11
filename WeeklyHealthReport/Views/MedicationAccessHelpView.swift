import SwiftUI

/// How to change medication access in Health. The report presents it as a
/// sheet with a Done action; Settings pushes it without one, so it never
/// touches report presentation state.
struct MedicationAccessHelpView: View {
    var done: (() -> Void)?

    var body: some View {
        List {
            Section("Change existing access") {
                Text("Open Health, tap your profile picture, then Apps, WeeklyHealthReport, and change which medications the app may read.")
            }

            Section("New medications") {
                Text("When you add a medication in Health, turn on WeeklyHealthReport on the final screen before saving it.")
            }

            Section {
                Text("Apple manages medication access in Health after the initial chooser. Then tap Refresh on the Health report.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Medication access")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
    }
}
