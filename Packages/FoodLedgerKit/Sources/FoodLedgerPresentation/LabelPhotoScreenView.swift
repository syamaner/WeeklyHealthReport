import FoodLedgerApplication
import SwiftUI

/// The Label photo screen (docs/label-photo-ai-prefill-v1.md 4.1 and 7.1 to 7.2). Native grouped
/// style, Dynamic Type, VoiceOver labels and 44 pt targets; states are said in words.
public struct LabelPhotoScreenView: View {
    @ObservedObject private var model: LabelPhotoScreenModel
    private let views: any LabelPhotoViewFactory
    private let openSettings: () -> Void
    private let openRouterSettings: () -> Void
    private let pasteLabel: () -> Void
    private let searchFoods: () -> Void
    private let privacyPolicy: () -> Void
    private let leave: () -> Void

    public init(model: LabelPhotoScreenModel, views: any LabelPhotoViewFactory, openSettings: @escaping () -> Void,
                openRouterSettings: @escaping () -> Void, pasteLabel: @escaping () -> Void, searchFoods: @escaping () -> Void,
                privacyPolicy: @escaping () -> Void, leave: @escaping () -> Void) {
        self.model = model; self.views = views; self.openSettings = openSettings; self.openRouterSettings = openRouterSettings
        self.pasteLabel = pasteLabel; self.searchFoods = searchFoods; self.privacyPolicy = privacyPolicy; self.leave = leave
    }

    public var body: some View {
        Form {
            photoSection
            Section {
                TextField("Name", text: $model.name).accessibilityLabel("Name, required").frame(minHeight: 44)
                    .accessibilityIdentifier("labelPhoto.name")
                TextField("Brand (optional)", text: $model.brand).frame(minHeight: 44)
            } footer: { Text("Name and brand are saved with the entry and never sent.") }
            readSection
            outcomeSection
            Section {
                Button(LabelPhotoText.leave, role: .destructive) { model.leave(); leave() }.frame(minHeight: 44)
            }
        }
        .navigationTitle(LabelPhotoText.screenTitle)
        .task { await model.refresh() }
        .labelPhotoCover(isPresented: $model.cropping) {
            if let photo = model.photo {
                NavigationStack {
                    views.crop(photo: photo, initial: model.crop, use: { model.useCrop($0) }, cancel: { model.cancelCrop() })
                        .navigationTitle(LabelPhotoText.cropTitle)
                }
            }
        }
        .sheet(isPresented: $model.showsFirstUseSheet) { firstUseSheet }
    }

    @ViewBuilder private var photoSection: some View {
        Section {
            if let prepared = model.prepared {
                views.preparedPhoto(prepared.bytes)
                    .accessibilityLabel(LabelPhotoText.photoAccessibilityLabel)
                HStack {
                    Button(LabelPhotoText.retake) { model.retake() }.frame(minHeight: 44)
                    Spacer()
                    Button(LabelPhotoText.adjustCrop) { model.cropping = true }.frame(minHeight: 44)
                        .accessibilityIdentifier("labelPhoto.adjustCrop")
                }
                .buttonStyle(.borderless)
                .disabled(model.isBusy)
            } else {
                if let failure = model.preparationFailure {
                    Label(failure, systemImage: "exclamationmark.triangle").accessibilityIdentifier("labelPhoto.preparationFailure")
                }
                if model.cameraDenied {
                    Text(LabelPhotoText.cameraDenied)
                    Button(LabelPhotoText.openSettings, action: openSettings).frame(minHeight: 44)
                }
                views.sourceButtons(photo: { model.choose($0) }, cameraDenied: { model.cameraWasDenied() })
            }
        }
    }

    @ViewBuilder private var readSection: some View {
        Section {
            if let blocker = model.blocker {
                Label(blocker.text, systemImage: "exclamationmark.circle").accessibilityIdentifier("labelPhoto.blocker")
                if let action = blocker.action {
                    Button(action) { blocker == .offline ? pasteLabel() : openRouterSettings() }.frame(minHeight: 44)
                }
            }
            // The egress statement sits directly above the button, every time (7.1).
            Text(LabelPhotoText.egressStatement).font(.subheadline).accessibilityIdentifier("labelPhoto.egress")
            if let progress = model.progressText {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(progress).accessibilityIdentifier("labelPhoto.progress")
                }
                Button(LabelPhotoText.cancel) { model.cancel() }.frame(minHeight: 44).accessibilityIdentifier("labelPhoto.cancel")
            } else {
                Button { model.readTapped() } label: {
                    Text(LabelPhotoText.readButton).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRead)
                .accessibilityIdentifier("labelPhoto.read")
            }
        } footer: {
            Text(model.underButton)
        }
    }

    @ViewBuilder private var outcomeSection: some View {
        switch model.phase {
        case let .declined(messages):
            Section {
                ForEach(messages, id: \.self) { Text($0) }
                otherRoutes
            }
            .accessibilityIdentifier("labelPhoto.declined")
        case let .failed(message):
            Section {
                Text(message).accessibilityIdentifier("labelPhoto.failure")
                Button(LabelPhotoText.tryAgain) { model.readTapped() }.frame(minHeight: 44).disabled(!model.canRead)
                otherRoutes
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var otherRoutes: some View {
        Button(LabelPhotoText.pasteLabel, action: pasteLabel).frame(minHeight: 44)
        Button(LabelPhotoText.searchFoods, action: searchFoods).frame(minHeight: 44)
    }

    private var firstUseSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // The title wraps at every text size (no truncation at AX5).
                    Text(LabelPhotoText.firstUseTitle).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LabelPhotoText.firstUseBody)
                    Button(LabelPhotoText.privacyPolicy, action: privacyPolicy).frame(minHeight: 44)
                    Button { model.firstUseAccepted() } label: {
                        Text(LabelPhotoText.firstUseSend).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("labelPhoto.firstUse.send")
                    Button { model.firstUseDeclined() } label: {
                        Text(LabelPhotoText.firstUseNotNow).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .presentationDetents([.large])
    }
}

/// Confirm's "Label photo" and "Nutrition from the photo" sections (4.2 items 4 and 5, 5, 7.3).
public struct LabelPhotoSourceSections: View {
    @ObservedObject private var model: LabelPhotoSourceModel
    private let views: any LabelPhotoViewFactory
    private let retake: (() -> Void)?
    @State private var showsFullScreen = false
    @State private var correcting: LabelPhotoSourceModel.Row?
    @State private var correctionText = ""
    @State private var correctionComparator = "="
    @State private var correctionFailure: String?
    @State private var showsPhotoAtLargeSizes = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(model: LabelPhotoSourceModel, views: any LabelPhotoViewFactory, retake: (() -> Void)?) {
        self.model = model; self.views = views; self.retake = retake
    }

    public var body: some View {
        Section(LabelPhotoText.photoSectionTitle) {
            // A compact strip with Show photo at accessibility sizes (section 5).
            if !dynamicTypeSize.isAccessibilitySize || showsPhotoAtLargeSizes {
                views.pane(model.imageBytes, focus: model.focus, fullScreen: { showsFullScreen = true })
                    .frame(height: 300)
                    .accessibilityElement(children: .contain)
            } else {
                Button(LabelPhotoText.showPhoto) { showsPhotoAtLargeSizes = true }.frame(minHeight: 44)
            }
            if let message = model.focus?.message { Text(message).accessibilityIdentifier("labelPhoto.focusMessage") }
            if let retake {
                Button(LabelPhotoText.retakeOrAdjust, action: retake).frame(minHeight: 44)
            }
        }
        .sheet(isPresented: $showsFullScreen) {
            views.fullScreenPane(model.imageBytes, focus: model.focus, done: { showsFullScreen = false })
        }
        Section {
            Text(LabelPhotoText.honestyNote).font(.subheadline).accessibilityIdentifier("labelPhoto.honesty")
            if let summary = model.attentionSummary {
                Text(summary).font(.subheadline.weight(.semibold)).accessibilityIdentifier("labelPhoto.attentionSummary")
            }
            Text(model.sourceLine).font(.footnote).foregroundStyle(.secondary)
            ForEach(model.checkItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Label(item.text, systemImage: "exclamationmark.triangle")
                    Text(item.values).font(.footnote).foregroundStyle(.secondary)
                    if !item.resolved {
                        Button(LabelPhotoText.checkedThem) { model.checkGroup(item.id) }.frame(minHeight: 44)
                    }
                }
            }
            ForEach(model.rows + model.servingRows) { row in rowView(row) }
            if let failure = model.actionFailure { Text(failure).foregroundStyle(.red) }
        } header: {
            Text(LabelPhotoText.valuesSectionTitle)
        } footer: {
            Text(LabelPhotoText.sourceFooter)
        }
        .alert(LabelPhotoText.correctTitle, isPresented: Binding(get: { correcting != nil }, set: { if !$0 { correcting = nil } })) {
            TextField(correcting?.unit ?? "", text: $correctionText).labelPhotoDecimalPad()
            Button(LabelPhotoText.correctSave) {
                if let row = correcting { correctionFailure = model.correct(row.id, text: correctionText, comparator: correctionComparator) }
                correcting = nil
            }
            Button(LabelPhotoText.cancel, role: .cancel) { correcting = nil }
        } message: {
            if let row = correcting { Text("\(row.title), \(row.column.isEmpty ? row.unit : row.column), in \(row.unit)") }
        }
        .onChange(of: model.focus) { _, focus in
            if let announcement = model.focusAnnouncement, focus != nil {
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
    }

    private func rowView(_ row: LabelPhotoSourceModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.show(row.id) } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.column.isEmpty ? row.title : "\(row.title), \(row.column)")
                        Label(row.state.text, systemImage: row.state.needsCheck ? "exclamationmark.circle.fill" : "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(row.state.needsCheck ? Color.orange : Color.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(row.value).monospacedDigit()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityHint(row.showOnPhotoLabel)
            .accessibilityIdentifier("labelPhoto.row.\(row.id)")
            if row.state.needsCheck || (!row.actions.isEmpty && row.isAttentionItem) {
                ViewThatFits {
                    HStack { actionButtons(row) }
                    VStack(alignment: .leading) { actionButtons(row) }
                }
            } else if row.actions.contains(.correct) {
                Button(LabelPhotoText.correct) { startCorrection(row) }.frame(minHeight: 44).buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder private func actionButtons(_ row: LabelPhotoSourceModel.Row) -> some View {
        if row.actions.contains(.matches) {
            Button(LabelPhotoText.matchesPhoto) { model.matches(row.id) }.frame(minHeight: 44).buttonStyle(.bordered)
                .accessibilityIdentifier("labelPhoto.matches.\(row.id)")
        }
        if row.actions.contains(.correct) {
            Button(LabelPhotoText.correct) { startCorrection(row) }.frame(minHeight: 44).buttonStyle(.bordered)
        }
        if row.actions.contains(.leaveUnknown) {
            Button(LabelPhotoText.leaveUnknown) { model.leaveUnknown(row.id) }.frame(minHeight: 44).buttonStyle(.bordered)
                .accessibilityIdentifier("labelPhoto.leaveUnknown.\(row.id)")
        }
    }

    private func startCorrection(_ row: LabelPhotoSourceModel.Row) {
        correctionText = ""; correctionComparator = "="; correcting = row
    }
}

extension View {
    /// Full screen on iOS; a sheet elsewhere (the package also builds for macOS).
    @ViewBuilder func labelPhotoCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    @ViewBuilder func labelPhotoDecimalPad() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
