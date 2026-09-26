import SwiftUI

struct FoodVoiceInputView: View {
    @StateObject private var draft: FoodVoiceDraft
    @StateObject private var speech: DailyNoteSpeechController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmsDiscard = false
    private let vocabularyUnavailable: Bool
    private let transfer: (String) -> Bool

    init(vocabulary: [String], vocabularyUnavailable: Bool, transfer: @escaping (String) -> Bool) {
        let draft = FoodVoiceDraft()
        _draft = StateObject(wrappedValue: draft)
        _speech = StateObject(wrappedValue: DailyNoteSpeechController(
            capture: SystemOnDeviceSpeechCapture(contextualStrings: vocabulary),
            appendFinalTranscript: { draft.append($0) }
        ))
        self.vocabularyUnavailable = vocabularyUnavailable
        self.transfer = transfer
    }

    private var active: Bool {
        speech.state == .listening || speech.state == .stopping || speech.state == .requestingPermission
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("On-device food dictation") {
                    Text("Say one food and its consumed amount per capture, or edit line breaks below. Recognition can get numbers, units and brands wrong. Nothing here saves food.")
                    Text(speech.statusMessage.replacingOccurrences(of: "Typed notes", with: "Typed food entry"))
                    Button(speech.state == .listening ? "Stop" : "Start microphone") {
                        Task { await speech.toggle() }
                    }.disabled(!speech.isMicrophoneEnabled)
                    if speech.canRetryAvailability { Button("Check availability again") { speech.retryAvailability() } }
                    if speech.canOpenPermissionSettings {
                        Text("You can change microphone and Speech Recognition permission in iOS Settings, or keep typing.").font(.caption)
                    }
                    if vocabularyUnavailable {
                        Text("Saved food vocabulary could not be read. Only unit hints are available; typed input still works.").font(.caption)
                    }
                    if !speech.earlierUnfinalisedTranscript.isEmpty { Text("Earlier fragment: \(speech.earlierUnfinalisedTranscript)") }
                    if !speech.partialTranscript.isEmpty { Text("Live candidate: \(speech.partialTranscript)") }
                }
                if speech.hasReviewTranscript {
                    Section("Review interrupted or uncertain speech") {
                        TextEditor(text: Binding(get: { speech.reviewTranscript }, set: { speech.updateReviewTranscript($0) }))
                            .frame(minHeight: 100)
                        if let error = speech.reviewErrorMessage { Text(error) }
                        Button("Add corrected text to food draft") { _ = speech.acceptReviewTranscript() }
                        Button("Discard this speech candidate", role: .destructive) { speech.discardReviewTranscript() }
                    }
                }
                Section("Editable food text — not saved") {
                    TextEditor(text: $draft.text).frame(minHeight: 160).accessibilityLabel("Recognised food text")
                        .disabled(active)
                    Toggle("I checked every quantity and unit, and put each item on its own line", isOn: $draft.checkedNumbersAndUnits)
                        .disabled(active || speech.hasReviewTranscript)
                    if let error = draft.errorMessage { Text(error) }
                    Button("Use text in food review") {
                        guard draft.canTransfer, !active, !speech.hasReviewTranscript else { return }
                        if transfer(draft.text) { dismiss() }
                        else { draft.errorMessage = "The list changed or combined text exceeds its limits. Your dictation is still here; shorten it or return to the list." }
                    }.disabled(!draft.canTransfer || active || speech.hasReviewTranscript)
                    Text("The next screen still requires candidate and nutrition confirmation. Audio is not saved. Unsaved dictation is session-only.").font(.caption)
                }
            }
            .navigationTitle("Dictate food")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { confirmsDiscard = true } } }
            .confirmationDialog("Discard this unsaved dictation? Existing list text and saved foods remain unchanged.", isPresented: $confirmsDiscard) {
                Button("Discard dictation", role: .destructive) { speech.stopForLifecycle(); dismiss() }
            }
        }
        .interactiveDismissDisabled()
        .onDisappear { speech.stopForLifecycle() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { speech.stopForLifecycle() }
            else { speech.retryAvailability() }
        }
    }
}
