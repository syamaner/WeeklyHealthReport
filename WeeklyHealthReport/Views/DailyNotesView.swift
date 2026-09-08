import SwiftUI

struct DailyNotesView: View {
    @ObservedObject var controller: DailyNotesController
    let openEditor: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var notePendingDeletion: DailyNote?

    var body: some View {
        List {
            if let recoverable = controller.recoverableDraft {
                Section("Draft from \(recoverable.dayID.reportDate)") {
                    Text(recoverable.text.isEmpty ? "Empty draft" : recoverable.text)
                        .lineLimit(3)
                    Button("Copy draft into today") {
                        if controller.copyRecoverableDraftToToday() {
                            openEditor()
                        }
                    }
                    Button("Discard old draft", role: .destructive) {
                        _ = controller.discardDraft()
                    }
                    Text("The draft keeps its original reporting date until you choose one of these actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let draft = controller.currentDraft, draft.editingNoteID == nil {
                Section("Unfinished new note") {
                    Button {
                        openEditor()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.text.isEmpty ? "Empty draft" : draft.text)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                            Text("Tap to continue editing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Closing the editor keeps this draft on this device. Drafts are never exported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Saved for \(controller.currentDayID.reportDate)") {
                if controller.notes.isEmpty {
                    Text("No notes")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.notes) { note in
                        if let draft = controller.currentDraft,
                           draft.editingNoteID == note.id {
                            Button {
                                openEditor()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.text.isEmpty ? "Empty edit" : draft.text)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(3)
                                    Text("Unsaved changes — tap to continue")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        } else {
                            Button {
                                if controller.beginEditing(noteID: note.id) {
                                    openEditor()
                                }
                            } label: {
                                Text(note.text)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .swipeActions(allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    notePendingDeletion = note
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Text("Saved notes remain on this device until they are included in a refreshed preview and you explicitly export it. Verified prior-day notes are then cleaned up lazily; unfinished drafts are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Today’s Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if controller.beginOrResumeDraft() {
                        openEditor()
                    }
                } label: {
                    if controller.currentDraft == nil {
                        Label("Add Note", systemImage: "plus")
                    } else {
                        Label("Continue Draft", systemImage: "square.and.pencil")
                    }
                }
                .disabled(!controller.storageAvailable || controller.recoverableDraft != nil)
            }
        }
        .alert(
            "Delete note?",
            isPresented: Binding(
                get: { notePendingDeletion != nil },
                set: { if !$0 { notePendingDeletion = nil } }
            ),
            presenting: notePendingDeletion
        ) { note in
            Button("Cancel", role: .cancel) { notePendingDeletion = nil }
            Button("Delete note", role: .destructive) {
                _ = controller.deleteNote(id: note.id)
                notePendingDeletion = nil
            }
        } message: { _ in
            Text("This removes the note from the next refreshed export. The existing reviewed Drive file is unchanged until you export again.")
        }
        .alert(
            "Notes unavailable",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.clearError() } }
            )
        ) {
            Button("OK") { controller.clearError() }
        } message: {
            Text(controller.errorMessage ?? "")
        }
        .onAppear { controller.activate() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: controller.activate()
            case .background: controller.flushDraft()
            default: break
            }
        }
    }
}

struct DailyNoteEditorView: View {
    @ObservedObject var controller: DailyNotesController
    @StateObject private var speechController: DailyNoteSpeechController
    let willOpenApplicationSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingDiscardConfirmation = false
    @State private var isOpeningApplicationSettings = false
    @FocusState private var noteTextIsFocused: Bool

    init(
        controller: DailyNotesController,
        willOpenApplicationSettings: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.willOpenApplicationSettings = willOpenApplicationSettings
        _speechController = StateObject(wrappedValue: DailyNoteSpeechController(
            capture: SystemOnDeviceSpeechCapture(),
            appendFinalTranscript: { transcript in
                controller.appendSpeechTranscript(transcript)
                    ? nil
                    : (controller.errorMessage ?? "The transcript could not be added. Your draft was preserved.")
            }
        ))
    }

    private var text: Binding<String> {
        Binding(
            get: { controller.currentDraft?.text ?? "" },
            set: { controller.updateDraftText($0) }
        )
    }

    private var characterCount: Int {
        controller.currentDraft?.text.count ?? 0
    }

    var body: some View {
        Form {
            Section("Note") {
                TextEditor(text: text)
                    .frame(minHeight: 180)
                    .focused($noteTextIsFocused)
                HStack {
                    Spacer()
                    Text("\(characterCount) / \(DailyNotesPolicy.maximumCharactersPerNote)")
                        .font(.caption)
                        .foregroundStyle(characterCount >= 1_900 ? Color.orange : Color.secondary)
                }
            }

            Section {
                HStack {
                    Button {
                        if speechController.canOpenPermissionSettings {
                            controller.flushDraft()
                            isOpeningApplicationSettings = true
                            willOpenApplicationSettings()
                            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                                isOpeningApplicationSettings = false
                                return
                            }
                            UIApplication.shared.open(url)
                        } else {
                            Task { await speechController.toggle() }
                        }
                    } label: {
                        Label(
                            speechController.canOpenPermissionSettings
                                ? "Permission Settings"
                                : (speechController.state == .listening ? "Stop" : "Microphone"),
                            systemImage: speechController.canOpenPermissionSettings
                                ? "gear"
                                : (speechController.state == .listening
                                    ? "stop.circle.fill"
                                    : "mic.circle.fill")
                        )
                    }
                    .disabled(
                        !speechController.isMicrophoneEnabled
                            && !speechController.canOpenPermissionSettings
                    )

                    Spacer()

                    if speechController.state == .listening {
                        ProgressView()
                    }
                }

                Text(speechController.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !speechController.partialTranscript.isEmpty {
                    Text(speechController.partialTranscript)
                        .italic()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Partial transcript")
                }

                if speechController.canRetryAvailability {
                    Button("Check availability") {
                        speechController.retryAvailability()
                    }
                }
            } header: {
                Text("On-device dictation")
            } footer: {
                Text("This microphone path runs only when on-device recognition is supported. Audio is streamed only during listening and is never saved, exported or uploaded. Keyboard Dictation is controlled separately by iOS and is not covered by this guarantee.")
            }

            Section {
                Button("Save Note") {
                    if controller.saveDraft() { dismiss() }
                }
                .disabled(
                    controller.currentDraft?.text
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty != false
                )
                Button("Discard Draft", role: .destructive) {
                    showingDiscardConfirmation = true
                }
            } footer: {
                Text("Intentional line breaks are preserved. Leading and trailing whitespace is removed when you save.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(controller.currentDraft?.editingNoteID == nil ? "New Note" : "Edit Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    noteTextIsFocused = false
                }
            }
        }
        .alert("Discard this draft?", isPresented: $showingDiscardConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Discard Draft", role: .destructive) {
                if controller.discardDraft() { dismiss() }
            }
        } message: {
            Text("The unfinished text will be removed from this device.")
        }
        .alert(
            "Note not saved",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.clearError() } }
            )
        ) {
            Button("OK") { controller.clearError() }
        } message: {
            Text(controller.errorMessage ?? "")
        }
        .onDisappear {
            speechController.stopForLifecycle()
            if !isOpeningApplicationSettings,
               scenePhase == .active,
               UIApplication.shared.applicationState == .active {
                controller.finishEditorDismissal()
            } else {
                controller.flushDraft()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                speechController.stopForLifecycle()
                controller.flushDraft()
            } else if phase == .active {
                isOpeningApplicationSettings = false
                speechController.retryAvailability()
            }
        }
    }
}
