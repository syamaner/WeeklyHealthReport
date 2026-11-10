import SwiftUI

/// The Nutrition label screen (docs/nutrition-label-entry-v1.md 3.2): a native grouped list with
/// the photo section when the photo route is not off, then Paste and Type or paste text. States
/// are said in words; Dynamic Type, VoiceOver labels and 44 pt targets.
public struct NutritionLabelEntryView: View {
    @ObservedObject private var model: NutritionLabelEntryModel
    private let controls: any NutritionLabelControlFactory
    /// The label photo source buttons; asked for only when the photo route is not off.
    private let photoViews: (any LabelPhotoViewFactory)?
    private let openSettings: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    public init(model: NutritionLabelEntryModel, controls: any NutritionLabelControlFactory, photoViews: (any LabelPhotoViewFactory)?,
                openSettings: @escaping () -> Void) {
        self.model = model; self.controls = controls; self.photoViews = photoViews; self.openSettings = openSettings
    }

    public var body: some View {
        Form {
            if model.showsPhotoSection, let photoViews {
                Section {
                    if model.cameraDenied {
                        Text(LabelPhotoText.cameraDenied)
                        Button(LabelPhotoText.openSettings, action: openSettings).frame(minHeight: 44)
                    }
                    photoViews.sourceButtons(photo: { model.photoChosen($0) }, cameraDenied: { model.cameraWasDenied() })
                        .disabled(model.isLoading)
                } header: {
                    Text(NutritionLabelEntryText.photoSectionTitle)
                } footer: {
                    Text(model.photoFooter)
                }
            }
            Section {
                controls.pasteControl(acceptsImages: model.acceptsImages, events: { model.handle($0) })
                    .disabled(model.pasteDisabled)
                Button { model.typeOrPaste() } label: {
                    Label(NutritionLabelEntryText.typeOrPaste, systemImage: "character.cursor.ibeam")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(model.typeOrPasteDisabled)
                .accessibilityIdentifier("nutritionLabel.typeOrPaste")
                stateRows
            } header: {
                Text(NutritionLabelEntryText.pasteSectionTitle)
            } footer: {
                Text(model.pasteFooter)
            }
        }
        .navigationTitle(NutritionLabelEntryText.title)
        .onDisappear { model.leave() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.leave() }
        }
    }

    @ViewBuilder private var stateRows: some View {
        switch model.pasteState {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView().accessibilityHidden(true)
                Text(NutritionLabelEntryText.loading).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NutritionLabelEntryText.loading)
            .accessibilityIdentifier("nutritionLabel.loading")
        case let .failed(offersText):
            Label(NutritionLabelEntryText.imageFailed, systemImage: "exclamationmark.triangle")
                .frame(minHeight: 44)
                .accessibilityIdentifier("nutritionLabel.imageFailed")
            if offersText { choiceButton(NutritionLabelEntryText.readText, id: "nutritionLabel.readText") { model.readText() } }
        case .both:
            choiceButton(NutritionLabelEntryText.readImage, id: "nutritionLabel.readImage") { model.readImage() }
            choiceButton(NutritionLabelEntryText.readText, id: "nutritionLabel.readText") { model.readText() }
        case .nothing:
            Label(NutritionLabelEntryText.nothing, systemImage: "doc.on.clipboard")
                .frame(minHeight: 44)
                .accessibilityIdentifier("nutritionLabel.nothing")
        }
    }

    private func choiceButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
    }
}
