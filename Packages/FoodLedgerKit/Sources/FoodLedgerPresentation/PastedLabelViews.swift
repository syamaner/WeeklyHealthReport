import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// The label text screen (#93, section 2.2). Native grouped style; every control is at least
/// 44 pt and labelled for VoiceOver. The app never reads the pasteboard: the user pastes with
/// the system paste control in the text field.
public struct PastedLabelTextView: View {
    @ObservedObject private var model: PastedLabelTextViewModel
    private let openConfirm: (PastedLabelSourceModel) -> Void
    private let search: (() -> Void)?
    private let scanBarcode: (() -> Void)?
    private let leave: () -> Void
    @State private var report: PastedLabelMisreadPreviewModel?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var fortifiedPicker: some View {
        Picker(PastedLabelText.fortifiedQuestion, selection: $model.fortification) {
            Text("Not answered").tag(PastedLabelIdentity.FortificationAnswer.unanswered)
            Text("Yes").tag(PastedLabelIdentity.FortificationAnswer.yes)
            Text("No").tag(PastedLabelIdentity.FortificationAnswer.no)
        }
        .frame(minHeight: 44)
        .accessibilityHint(PastedLabelText.fortifiedHelp)
    }

    public init(model: PastedLabelTextViewModel, openConfirm: @escaping (PastedLabelSourceModel) -> Void,
                search: (() -> Void)? = nil, scanBarcode: (() -> Void)? = nil, leave: @escaping () -> Void) {
        self.model = model; self.openConfirm = openConfirm
        self.search = search; self.scanBarcode = scanBarcode; self.leave = leave
    }

    public var body: some View {
        Form {
            Section {
                TextField(PastedLabelText.nameField, text: $model.name, prompt: Text(PastedLabelText.namePrompt))
                    .accessibilityLabel(PastedLabelText.nameField)
                    .frame(minHeight: 44)
                TextField(PastedLabelText.brandField, text: $model.brand)
                    .accessibilityLabel("Brand, optional")
                    .frame(minHeight: 44)
                // #282: at accessibility sizes the menu picker truncated its value ("Not a…ered");
                // the inline style lists every answer in full on its own row.
                if dynamicTypeSize.isAccessibilitySize {
                    fortifiedPicker.pickerStyle(.inline)
                } else {
                    fortifiedPicker
                }
            } header: { Text("Food") } footer: { Text(PastedLabelText.fortifiedHelp) }

            if !model.declineMessages.isEmpty {
                Section {
                    ForEach(model.declineMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
                            .accessibilityLabel("Not read. \(message)")
                    }
                    Button(PastedLabelText.clearText) { model.clearText() }.frame(minHeight: 44)
                    if let search { Button(PastedLabelText.searchInstead, action: search).frame(minHeight: 44) }
                    if let scanBarcode { Button(PastedLabelText.scanInstead, action: scanBarcode).frame(minHeight: 44) }
                    if let text = model.declineReportText {
                        Button(PastedLabelText.reportMisread) { report = PastedLabelMisreadPreviewModel(report: text) }
                            .frame(minHeight: 44)
                            .accessibilityHint("Opens a preview you can edit, share or cancel. Nothing is sent automatically.")
                    }
                } header: { Text("Not read") } footer: { Text("Your text and name are kept. Edit the text and read it again.") }
            }

            Section {
                TextEditor(text: $model.text)
                    .frame(minHeight: 180)
                    .font(.body.monospaced())
                    .accessibilityLabel(PastedLabelText.labelTextField)
                    .accessibilityHint(PastedLabelText.labelTextHelp)
            } header: { Text(PastedLabelText.labelTextField) } footer: { Text(PastedLabelText.labelTextHelp) }

            Section {
                Button {
                    if let confirm = model.readLabel() { openConfirm(confirm) }
                } label: {
                    Text(PastedLabelText.readLabel).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRead)
                .accessibilityHint(model.readBlockedReason ?? "Reads the text on this device and opens the confirmation. Nothing is saved.")
                if let reason = model.readBlockedReason {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
                if model.canReturnToConfirm {
                    Button(PastedLabelText.backToConfirm) {
                        if let confirm = model.returnToConfirm() { openConfirm(confirm) }
                    }
                    .frame(minHeight: 44)
                    .accessibilityHint("Returns to the confirmation with your corrections kept")
                }
                Button(PastedLabelText.leaveWithoutSaving, role: .cancel) {
                    model.dismissed()
                    leave()
                }
                .frame(minHeight: 44)
            } footer: { Text(PastedLabelText.nothingSaved) }
        }
        .navigationTitle(PastedLabelText.title)
        .alert(PastedLabelText.readAgainTitle, isPresented: $model.asksToReplaceCorrections) {
            Button(PastedLabelText.readAgain, role: .destructive) {
                if let confirm = model.confirmReadAgain() { openConfirm(confirm) }
            }
            Button(PastedLabelText.cancel, role: .cancel) { model.cancelReadAgain() }
        }
        .sheet(item: $report) { PastedLabelMisreadPreviewSheet(model: $0) { report = nil } }
        .alert(PastedLabelText.basisChoiceFailed, isPresented: $model.basisChoiceFailed) {
            Button("OK", role: .cancel) {}
        }
        // Reader v3 8.4.8: the basis sheet after Read label (Change presents it over Confirm).
        // A failed choice is said once the sheet has gone (onDismiss), never dropped by it.
        .sheet(item: Binding(get: { model.basisSheet.flatMap { $0.fromChange ? nil : $0 } },
                             set: { if $0 == nil { model.basisSheetDismissed() } }),
               onDismiss: { model.basisSheetDidDisappear() }) { _ in
            PastedLabelBasisSheetView(model: model, open: openConfirm, search: search, closeConfirm: {})
        }
    }
}

/// The basis sheet (reader v3 sections 3.3 and 8.4.8): "These values have no column heading.
/// What are they for?" It renders the application's options in order, each with its warning,
/// with nothing preselected; the hint is shown and never chosen. "I'm not sure" goes back to the
/// label text. Native grouped style, 44 pt targets, VoiceOver labels.
public struct PastedLabelBasisSheetView: View {
    @ObservedObject private var model: PastedLabelTextViewModel
    private let open: (PastedLabelSourceModel) -> Void
    private let search: (() -> Void)?
    /// Closes Confirm when "I'm not sure" from Change drops it.
    private let closeConfirm: () -> Void

    public init(model: PastedLabelTextViewModel, open: @escaping (PastedLabelSourceModel) -> Void,
                search: (() -> Void)? = nil, closeConfirm: @escaping () -> Void) {
        self.model = model; self.open = open; self.search = search; self.closeConfirm = closeConfirm
    }

    /// Search is offered only on the first sheet (after Read label), never on the Change sheet.
    /// The button and the footer's note use this one condition.
    public static func offersSearch(hasSearch: Bool, fromChange: Bool) -> Bool { hasSearch && !fromChange }

    /// The footer under "I'm not sure": it names Search only where Search is offered.
    public static func notSureNote(hasSearch: Bool, fromChange: Bool) -> String {
        PastedLabelText.basisNotSureNote(offersSearch: offersSearch(hasSearch: hasSearch, fromChange: fromChange))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(PastedLabelText.basisQuestion)
                    if let hint = model.basisHint {
                        Label(hint, systemImage: "info.circle").font(.subheadline)
                            .accessibilityIdentifier("pastedLabel.basisHint")
                    }
                }
                Section {
                    ForEach(model.basisOptions) { option in
                        Button {
                            if let confirm = model.chooseBasis(option.arrangement) { open(confirm) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                if option.isCurrent {
                                    // Primary, not the button's tint or secondary: readable in light and dark mode.
                                    Text(PastedLabelText.currentChoice).font(.caption.weight(.semibold)).foregroundStyle(Color.primary)
                                }
                                ForEach(option.warnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityLabel(([option.title] + (option.isCurrent ? [PastedLabelText.currentChoice] : []) + option.warnings)
                            .joined(separator: ", "))
                        .accessibilityIdentifier("pastedLabel.basis." + option.id)
                    }
                    if model.perServingUnavailable {
                        Text(PastedLabelText.perServingUnavailable).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(PastedLabelText.basisNotSure) {
                        if model.basisNotSure() { closeConfirm() }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("pastedLabel.basisNotSure")
                    if let search, Self.offersSearch(hasSearch: true, fromChange: model.basisSheet?.fromChange == true) {
                        Button(PastedLabelText.searchInstead) {
                            model.basisSheetDismissed()
                            search()
                        }
                        .frame(minHeight: 44)
                    }
                } footer: { Text(Self.notSureNote(hasSearch: search != nil, fromChange: model.basisSheet?.fromChange == true)) }
            }
            .navigationTitle(PastedLabelText.basisSheetTitle)
            .pastedLabelInlineTitle()
            .alert(PastedLabelText.replaceCorrectionsOnBasisChange, isPresented: $model.asksToReplaceCorrectionsOnBasisChange) {
                Button(PastedLabelText.changeBasisConfirm, role: .destructive) {
                    if let confirm = model.confirmBasisChange() { open(confirm) }
                }
                Button(PastedLabelText.cancel, role: .cancel) { model.cancelBasisChange() }
            }
        }
    }
}

/// The pasted label's sections on Confirm (section 2.3): disclaimer and source line, each value
/// beside its printed text and origin, the serving lines, read-but-not-used rows, the other
/// column, the pasted text, Edit label text and Report a misread.
struct PastedLabelSourceSections: View {
    @ObservedObject var model: PastedLabelSourceModel
    let editLabelText: (() -> Void)?
    @State private var editing: PastedLabelValueEdit?
    @State private var report: PastedLabelMisreadPreviewModel?

    var body: some View {
        Section {
            Label(PastedLabelText.disclaimer, systemImage: "info.circle")
                .font(.subheadline)
                .accessibilityLabel(PastedLabelText.disclaimer)
            Text(model.sourceLine).font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("pastedLabel.sourceLine")
            // Reader v3 8.4.11 and decision 24: the energy line's note when it differed from the
            // choice, never a block; Change reopens the basis sheet.
            if let note = model.basisHintNote {
                Label(note, systemImage: "info.circle").font(.caption)
            }
            if model.canChangeBasis, let changeBasis = model.changeBasis, editLabelText != nil {
                Button(PastedLabelText.changeBasis, action: changeBasis)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Change what the values are for")
                    .accessibilityIdentifier("pastedLabel.changeBasis")
            }
            if let basisFlag = model.basisFlag {
                Label(basisFlag, systemImage: "exclamationmark.triangle").font(.subheadline)
            }
            ForEach(model.rows) { row in rowView(row) }
            ForEach(model.otherFlags, id: \.self) { flag in
                Label(flag, systemImage: "exclamationmark.triangle").font(.caption)
            }
        } header: { Text(PastedLabelText.sectionTitle) } footer: {
            Text(model.isEditable ? "Correct any value that differs from the label, or add one that was not read. Unknown values stay unknown, never zero."
                 : "Values as logged from the pasted label. To change them, paste the label again.")
        }

        Section("Serving") {
            ForEach(model.servingLines) { line in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(line.title, value: line.value)
                    if let flag = line.flag { Label(flag, systemImage: "exclamationmark.triangle").font(.caption) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(line.accessibilityLabel)
                actions(line.actions, id: line.id, title: line.title, unit: line.units.first ?? "g", units: line.units)
            }
        }

        if !model.readButNotUsed.isEmpty {
            Section(PastedLabelText.readButNotUsedTitle) {
                ForEach(model.readButNotUsed) { item in
                    LabeledContent(item.title, value: "\(item.printedText) · \(item.note)")
                        .accessibilityLabel("\(item.title), \(item.printedText), \(item.note)")
                }
            }
        }

        if !model.printedButNotRead.isEmpty {
            Section {
                ForEach(model.printedButNotRead) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(item.title, value: item.printedText)
                        Text(item.note).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.title), \(item.printedText). \(item.note)")
                }
            } header: { Text(PastedLabelText.printedButNotReadTitle) } footer: { Text(PastedLabelText.printedButNotReadNote) }
        }

        Section {
            ForEach(Array(model.otherColumns.enumerated()), id: \.offset) { _, column in
                DisclosureGroup(column.title) {
                    ForEach(column.cells) { cell in
                        LabeledContent(cell.title, value: cell.printedText)
                    }
                }
            }
            if !model.otherNutrients.isEmpty {
                DisclosureGroup(PastedLabelText.otherNutrientsTitle) {
                    Text(PastedLabelText.otherNutrientsNote).font(.caption)
                    ForEach(model.otherNutrients, id: \.self) { name in
                        LabeledContent(name, value: PastedLabelText.notStated)
                    }
                }
            }
            DisclosureGroup(PastedLabelText.pastedTextTitle) {
                Text(model.pastedText).font(.caption.monospaced()).textSelection(.enabled)
            }
            if let editLabelText {
                Button(PastedLabelText.editLabelText, action: editLabelText)
                    .frame(minHeight: 44)
                    .accessibilityHint("Returns to the label text with your text and name kept")
            }
            Button(PastedLabelText.reportMisread) { report = PastedLabelMisreadPreviewModel(report: model.reportText) }
                .frame(minHeight: 44)
                .accessibilityHint("Opens a preview you can edit, share or cancel. Nothing is sent automatically.")
        }
        .sheet(item: $editing) { edit in
            PastedLabelValueEditSheet(edit: edit, model: model) { editing = nil }
        }
        .sheet(item: $report) { PastedLabelMisreadPreviewSheet(model: $0) { report = nil } }
    }

    @ViewBuilder
    private func rowView(_ row: PastedLabelSourceModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(row.title, value: row.value)
            Text(row.originText).font(.caption).fontWeight(.semibold)
            if let source = row.source { Text(source).font(.caption).foregroundStyle(.secondary) }
            if let flag = row.flag { Label(flag, systemImage: "exclamationmark.triangle").font(.caption) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        actions(row.actions, id: row.id, title: row.title, unit: row.unit, units: [row.unit])
    }

    @ViewBuilder
    private func actions(_ actions: [PastedLabelSourceModel.Row.Action], id: String, title: String, unit: String, units: [String]) -> some View {
        ForEach(actions, id: \.self) { action in
            switch action {
            case .correct, .add:
                Button(action == .add ? "Add \(title.lowercased())" : "Correct \(title.lowercased())") {
                    editing = PastedLabelValueEdit(id: id, title: title, units: units, unit: unit,
                                                   text: model.editText(id), comparator: model.editComparator(id))
                }
                .frame(minHeight: 44)
            case .remove:
                Button("Remove your \(title.lowercased())", role: .destructive) { model.removeValue(id) }
                    .frame(minHeight: 44)
                    .accessibilityHint("Shows the value read from the label again, or leaves it unknown")
            }
        }
    }
}

/// What the edit sheet is changing.
struct PastedLabelValueEdit: Identifiable {
    let id: String
    let title: String
    let units: [String]
    let unit: String
    let text: String
    let comparator: String
}

/// Correct or add one value (section 2.3). The value is recorded only through the application
/// builder; it reads "Corrected by you" or "Entered by you" afterwards.
struct PastedLabelValueEditSheet: View {
    let edit: PastedLabelValueEdit
    @ObservedObject var model: PastedLabelSourceModel
    let close: () -> Void
    @State private var text = ""
    @State private var unit = "g"
    @State private var comparator = "="
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Value", text: $text)
                        .pastedLabelDecimalKeyboard()
                        .frame(minHeight: 44)
                        .accessibilityLabel("\(edit.title) value")
                    if edit.units.count > 1 {
                        Picker("Unit", selection: $unit) {
                            ForEach(edit.units, id: \.self) { Text(PastedLabelText.unitLabel($0)).tag($0) }
                        }
                    } else {
                        LabeledContent("Unit", value: edit.unit == "count" ? "servings" : edit.unit)
                    }
                    if PastedLabelSource.ledgerKeys[edit.id] != nil {
                        Picker("Printed as", selection: $comparator) {
                            Text("Exact").tag("=")
                            Text("Less than").tag("<")
                            Text("Up to").tag("<=")
                        }
                    }
                    if let failure { Label(failure, systemImage: "exclamationmark.triangle").font(.caption) }
                } footer: {
                    Text("Your value is saved as yours, and the value read from the label is kept beside it. Nothing is logged until you choose Log.")
                }
            }
            .navigationTitle(edit.title)
            .pastedLabelInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(PastedLabelText.cancel, action: close) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this value") {
                        failure = model.setValue(edit.id, text: text, unit: unit, comparator: comparator)
                        if failure == nil { close() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { text = edit.text; unit = edit.unit; comparator = edit.comparator }
        }
    }
}

/// The misread report preview (section 9.1): an editable text, Share (the system share sheet,
/// with this text only) and Cancel.
public struct PastedLabelMisreadPreviewSheet: View {
    @ObservedObject var model: PastedLabelMisreadPreviewModel
    let close: () -> Void

    public init(model: PastedLabelMisreadPreviewModel, close: @escaping () -> Void) {
        self.model = model; self.close = close
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $model.text)
                        .frame(minHeight: 280)
                        .font(.caption.monospaced())
                        .accessibilityLabel("Report text")
                } footer: { Text(PastedLabelText.reportPreviewNote) }
            }
            .navigationTitle(PastedLabelText.reportPreviewTitle)
            .pastedLabelInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(PastedLabelText.cancel, action: close) }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: model.shareItem) { Text(PastedLabelText.share) }
                        .accessibilityHint("Opens the share sheet with this text only. You choose where it goes.")
                }
            }
        }
    }
}

extension View {
    func pastedLabelDecimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    func pastedLabelInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
