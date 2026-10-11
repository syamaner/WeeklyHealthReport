import SwiftUI

/// How to change medication access in Health. The report presents it as a
/// sheet with a Done action; Settings pushes it without one, so it never
/// touches report presentation state.
struct MedicationAccessHelpView: View {
    var done: (() -> Void)?

    var body: some View {
        List {
            Section("Change Existing Access") {
                Text("Open Health, tap your profile picture, then Apps, WeeklyHealthReport, and change which medications the app may read.")
            }

            Section("New Medications") {
                Text("When you add a medication in Health, turn on WeeklyHealthReport on the final screen before saving it.")
            }

            Section {
                Text("Apple manages medication access in Health after the initial chooser. Return here and tap Refresh after making a change.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Medication Access")
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
