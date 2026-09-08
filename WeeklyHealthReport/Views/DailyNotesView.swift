import SwiftUI

struct DailyNotesView: View {
    @ObservedObject var controller: DailyNotesController
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingEditor = false
    @State private var notePendingDeletion: DailyNote?

    var body: some View {
        List {
            if let recoverable = controller.recoverableDraft {
                Section("Draft from \(recoverable.dayID.reportDate)") {
                    Text(recoverable.text.isEmpty ? "Empty draft" : recoverable.text)
                        .lineLimit(3)
                    Button("Copy draft into today") {
                        if controller.copyRecoverableDraftToToday() {
                            showingEditor = true
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

            if controller.currentDraft != nil {
                Section("Unfinished draft") {
                    Button("Continue editing") { showingEditor = true }
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
                        Button {
                            if controller.beginEditing(noteID: note.id) {
                                showingEditor = true
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
                    if controller.beginNewDraft() {
                        showingEditor = true
                    }
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
                .disabled(!controller.storageAvailable || controller.recoverableDraft != nil)
            }
        }
        .navigationDestination(isPresented: $showingEditor) {
            DailyNoteEditorView(controller: controller)
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

private struct DailyNoteEditorView: View {
    @ObservedObject var controller: DailyNotesController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingDiscardConfirmation = false

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
                HStack {
                    Spacer()
                    Text("\(characterCount) / \(DailyNotesPolicy.maximumCharactersPerNote)")
                        .font(.caption)
                        .foregroundStyle(characterCount >= 1_900 ? Color.orange : Color.secondary)
                }
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
        .navigationTitle(controller.currentDraft?.editingNoteID == nil ? "New Note" : "Edit Note")
        .navigationBarTitleDisplayMode(.inline)
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
        .onDisappear { controller.flushDraft() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.flushDraft() }
        }
    }
}
