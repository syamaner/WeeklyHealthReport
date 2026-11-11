import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// Confirm's "Estimate unprinted nutrients" section (docs/label-estimate-merge-v1.md rule 7): the
/// cocoa percentage field, the compatible rows and the preview of the keys an estimate fills. It
/// holds only the user's answers; every rule is the application's (`LabelEstimateOffer`,
/// `LabelEstimateCompatibility`, `LabelEstimateMerge`). Nothing is chosen or saved here: Log saves.
@MainActor
public final class LabelEstimateModel: ObservableObject {
    /// The compatible rows for a confirmed percentage, in search order (`LabelEstimateCandidatePool`).
    public typealias Lookup = @MainActor (Double) throws -> [LabelEstimateOption]

    public struct ConfirmedPercent: Equatable, Sendable {
        public let value: Double
        public let origin: CocoaPercentOrigin

        public init(value: Double, origin: CocoaPercentOrigin) {
            self.value = value
            self.origin = origin
        }
    }

    public enum Rows: Equatable {
        /// No percentage confirmed yet: no list.
        case awaitingPercent
        case options([LabelEstimateOption])
        /// "No estimate matches this cocoa percentage."
        case noMatch
        /// The bundled rows could not be searched; missing nutrients stay unknown.
        case failed
    }

    private let lookup: Lookup
    /// The label the section was last prepared for.
    private var source: PopulatedFoodCandidate?
    /// The field's text. Editing it after a confirmation withdraws the confirmation and the list.
    @Published public private(set) var percentText = ""
    @Published public private(set) var confirmed: ConfirmedPercent?
    @Published public private(set) var rows: Rows = .awaitingPercent
    @Published public private(set) var chosenID: String?
    @Published public private(set) var percentError: String?
    /// The pre-fill shown as a suggestion, with where it came from; nil when none applies.
    @Published public private(set) var suggestion: ConfirmedPercent?
    /// Set by any user edit of the field: from then on the value is typed and the suggestion
    /// caption is gone, even if the suggested value is typed back (rule 7).
    @Published public private(set) var userEdited = false
    /// The entry was corrected after the section appeared: no estimate can be saved (rule 7).
    @Published public private(set) var isUnavailableAfterCorrection = false

    public init(lookup: @escaping Lookup) {
        self.lookup = lookup
    }

    /// Follows every change of Confirm's state (the view model calls it at init and on each
    /// change). A different label resets the section; otherwise it re-reads rule 2's pre-fill, a
    /// new pre-fill withdrawing a confirmation that came from the old one; and a state that admits no
    /// choice (for example after a correction) clears the choice, so none survives it.
    public func prepare(_ state: FoodConfirmationState) {
        // A different label (a replaced paste or photo, or an edited reading) starts the section
        // afresh, typed value included, so no percentage or row chosen for another label carries
        // over to this one's save.
        if let source, source != state.selectedCandidate {
            withdrawConfirmation()
            userEdited = false
            percentError = nil
            suggestion = nil
            percentText = ""
        }
        source = state.selectedCandidate
        let unavailable = LabelEstimateOffer.applies(state) && !LabelEstimateOffer.admitsChoice(state)
        if unavailable != isUnavailableAfterCorrection { isUnavailableAfterCorrection = unavailable }
        if !LabelEstimateOffer.admitsChoice(state), chosenID != nil { chosenID = nil }
        let prefill = LabelEstimateOffer.prefill(state).map { ConfirmedPercent(value: $0.value, origin: $0.origin) }
        guard prefill != suggestion else { return }
        suggestion = prefill
        if let confirmed, confirmed.origin != .typed { withdrawConfirmation() }
        guard confirmed == nil, !userEdited else { return }
        percentText = prefill.map { Self.text($0.value) } ?? ""
    }

    public func editPercent(_ text: String) {
        guard text != percentText else { return }
        percentText = text
        userEdited = true
        percentError = nil
        if confirmed != nil { withdrawConfirmation() }
    }

    private func withdrawConfirmation() {
        confirmed = nil
        rows = .awaitingPercent
        chosenID = nil
    }

    /// The suggestion caption: the unedited pre-fill, not yet confirmed.
    public var showsSuggestion: Bool {
        suggestion != nil && confirmed == nil && !userEdited
    }

    public var canConfirmPercent: Bool {
        confirmed == nil && !percentText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The explicit confirmation of the field's value. Invalid or empty text gives no list.
    public func confirmPercent() {
        guard confirmed == nil else { return }
        guard let value = Self.parse(percentText), LabelEstimateCompatibility.isValidPercent(value) else {
            percentError = LabelEstimateText.invalidPercent
            return
        }
        percentError = nil
        let origin: CocoaPercentOrigin = !userEdited && suggestion?.value == value ? suggestion!.origin : .typed
        confirmed = ConfirmedPercent(value: value, origin: origin)
        chosenID = nil
        do {
            let found = try lookup(value)
            rows = found.isEmpty ? .noMatch : .options(found)
        } catch {
            rows = .failed
        }
    }

    public var options: [LabelEstimateOption] {
        if case let .options(options) = rows { return options } else { return [] }
    }

    public var chosen: LabelEstimateOption? { options.first { $0.id == chosenID } }

    /// Only a listed row can be chosen; choosing is the user's explicit act.
    public func choose(_ id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        chosenID = id
    }

    /// "Remove estimate": back to the label-only state.
    public func removeEstimate() {
        chosenID = nil
    }

    /// The estimate Log saves, or nil, in which case the save is exactly the label-only save.
    public func choice(for state: FoodConfirmationState) -> LabelEstimateChoice? {
        guard LabelEstimateOffer.admitsChoice(state), let confirmed, let chosen,
              LabelEstimateCompatibility.isCompatible(chosen.generic, cocoaPercent: confirmed.value),
              LabelEstimateOffer.merge(state, option: chosen) != nil else { return nil }
        return chosen.choice(cocoaPercent: confirmed.value, origin: confirmed.origin)
    }

    /// The preview of the chosen row: only the keys that change, then the source's own values.
    public func preview(for state: FoodConfirmationState) -> LabelEstimateText.Preview? {
        guard LabelEstimateOffer.admitsChoice(state), let route = LabelEstimateOffer.route(state), let chosen,
              let result = LabelEstimateOffer.merge(state, option: chosen) else { return nil }
        return LabelEstimateText.preview(result, label: state.selectedCandidate.candidate, option: chosen, route: route)
    }

    /// Accepts "72", "72.5", "72,5" and "72 %".
    nonisolated static func parse(_ text: String) -> Double? {
        let trimmed = text.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Double(trimmed)
    }

    nonisolated static func text(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// The section's copy. British spelling, no emoji; estimates are always named as estimates.
public enum LabelEstimateText {
    public static let sectionTitle = "Estimate unprinted nutrients"
    public static let fieldTitle = "Cocoa % on the pack"
    public static let confirmTitle = "Use this percentage"
    public static let removeTitle = "Remove estimate"
    public static let noMatch = "No estimate matches this cocoa percentage. Missing nutrients stay unknown."
    public static let failed = "Estimates could not be loaded. Missing nutrients stay unknown."
    public static let invalidPercent = "Enter a cocoa percentage from 1 to 100, with up to one decimal place."
    public static let unavailableAfterCorrection =
        "Estimates are not available after food details are corrected. Missing nutrients stay unknown."
    /// On an Open Food Facts product, filling in food details keeps the estimate (off-label-estimate-v1
    /// decision 6); only a changed name, brand or value withdraws it.
    public static let openFoodFactsUnavailableAfterCorrection =
        "Estimates are not available after the name, brand or values are changed, or the product is marked fortified or as something other than a food. Missing nutrients stay unknown."

    public static func unavailableAfterCorrection(_ route: LabelEstimateRoute) -> String {
        route == .openFoodFacts ? openFoodFactsUnavailableAfterCorrection : unavailableAfterCorrection
    }
    public static let footer =
        "Optional. Label values stay as they are; a generic row only fills nutrients the label does not state, as estimates."
    public static let chooseHint = "Choose a row to preview the nutrients it would add. Nothing is chosen for you."
    /// The Open Food Facts forms (docs/off-label-estimate-v1.md rule 6): true for every reason a
    /// product value is unknown, so they say "missing", never "unprinted".
    public static let openFoodFactsSectionTitle = "Estimate missing nutrients"
    public static let openFoodFactsFooter =
        "Optional. Open Food Facts values stay as they are; a generic row only fills nutrients not read from Open Food Facts, as estimates."

    public static func sectionTitle(_ route: LabelEstimateRoute) -> String {
        route == .openFoodFacts ? openFoodFactsSectionTitle : sectionTitle
    }

    public static func footer(_ route: LabelEstimateRoute) -> String {
        route == .openFoodFacts ? openFoodFactsFooter : footer
    }

    public static func suggestion(_ origin: CocoaPercentOrigin) -> String {
        switch origin {
        case .name: "Suggested from the product name. Check it against the pack."
        case .pastedText: "Suggested from the pasted label. Check it against the pack."
        case .typed: ""
        }
    }

    public static func confirmed(_ value: Double) -> String {
        "Cocoa % on the pack: \(LabelEstimateModel.text(value))%"
    }

    /// "USDA SR Legacy 2018-04-01", "CoFID 2021-03-19".
    public static func release(_ release: SourceRelease) -> String {
        let name: String = switch release.sourceID.value {
        case "usda-legacy": "USDA SR Legacy"
        case "usda-foundation": "USDA Foundation Foods"
        case "cofid": "CoFID"
        case "tfda-taiwan": "TFDA Taiwan"
        case "ciqual": "Ciqual"
        default: release.sourceID.value
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(name) \(formatter.string(from: release.releasedAt))"
    }

    /// "US reference · USDA SR Legacy 2018-04-01".
    public static func source(_ option: LabelEstimateOption) -> String {
        let family = FoodSearchResultSummary.family(option.sourceRelease.sourceID.value, recordID: option.id)
        return "\(FoodSearchResultText.family(family)) · \(release(option.sourceRelease))"
    }

    /// Phase A's note for the row at the confirmed percentage, or nil.
    public static func note(_ option: LabelEstimateOption, cocoaPercent: Double) -> String? {
        CocoaPercentPolicy.note(query: FoodQueryInterpretation(LabelEstimateCandidatePool.query(cocoaPercent: cocoaPercent)).parsedQuery,
                                candidate: option.generic)
    }

    public static func rowAccessibility(_ option: LabelEstimateOption, cocoaPercent: Double, chosen: Bool) -> String {
        var parts = ["Estimate from \(option.generic.name.value)", source(option)]
        if let note = note(option, cocoaPercent: cocoaPercent) { parts.append(note) }
        if chosen { parts.append("Chosen") }
        return parts.joined(separator: ", ")
    }

    public struct Preview: Equatable, Sendable {
        public struct Line: Equatable, Sendable {
            public let key: NutrientKey
            /// "Iron 11.9 mg · estimate · USDA SR Legacy 2018-04-01".
            public let text: String
            public let accessibilityLabel: String
        }
        /// Values on the label's basis ("Per 100 g").
        public let basis: String
        /// Only the keys that change.
        public let lines: [Line]
        /// The label's own known values, listed as unchanged.
        public let unchanged: String?
    }

    public static func preview(_ result: LabelEstimateMerge.Result, label: ProviderNeutralCandidate,
                               option: LabelEstimateOption, route: LabelEstimateRoute = .label) -> Preview {
        let release = release(option.sourceRelease)
        let lines = result.filledKeys.compactMap { key -> Preview.Line? in
            guard let entry = result.nutrients.entries.first(where: { $0.key == key }) else { return nil }
            let amount = NutrientOriginText.amount(entry.value, origin: .printed)
            let title = FoodNutritionReviewPresentation.label(key)
            return Preview.Line(key: key, text: "\(title) \(amount) · estimate · \(release)",
                                accessibilityLabel: "\(title), \(amount), estimate from \(option.generic.name.value), \(release)")
        }
        let known = label.nutrients.entries.filter { if case .unknown = $0.value { false } else { true } }
            .map { FoodNutritionReviewPresentation.label($0.key) }
        return Preview(basis: FoodNutritionReviewPresentation.basisLabel(label.identity.servingBasis), lines: lines,
                       unchanged: known.isEmpty ? nil
                           : (route == .openFoodFacts ? "Unchanged from the product: " : "Unchanged from the label: ")
                               + known.joined(separator: ", ") + ".")
    }
}

/// A saved entry's label estimate layer (section 8): which row estimated which nutrients, and,
/// for Developer tools, both releases and both decisions.
public enum LabelEstimateSavedEntryText {
    public static let sectionTitle = "Estimated nutrients"
    /// A label value left unknown that the estimate filled (photo route state lines).
    public static let estimatedState = "Not on the label · Estimated"
    /// An Open Food Facts value the estimate filled, whatever the reason it was unknown: not
    /// listed, in a unit the app cannot convert, or unreadable (docs/off-label-estimate-v1.md rule 6).
    public static let openFoodFactsEstimatedState = "Not read from Open Food Facts · Estimated"

    public static func estimatedState(_ route: LabelEstimateRoute) -> String {
        route == .openFoodFacts ? openFoodFactsEstimatedState : estimatedState
    }

    /// One line per estimated key of an Open Food Facts entry: "Fibre: Not read from Open Food
    /// Facts · Estimated". Empty for a label entry, whose photo states carry the label form.
    public static func stateLines(_ estimate: SavedFoodEntryDetail.LabelEstimateDetail) -> [String] {
        guard estimate.route == .openFoodFacts else { return [] }
        return estimate.estimatedKeys.map { "\(FoodNutritionReviewPresentation.label($0)): \(openFoodFactsEstimatedState)" }
    }

    /// An estimated bound for the amount's basis: "Less than 0.5 g per 100 g · Estimated". An
    /// exact value has its consumed amount instead; nil for anything else.
    public static func boundedValue(_ value: NutrientValue, basis: ResolutionBasis) -> String? {
        guard case .bounded = value else { return nil }
        let shown = FoodNutritionReviewPresentation.basisLabel(basis)
        return "\(NutrientOriginText.amount(value, origin: .printed)) \(shown.prefix(1).lowercased() + shown.dropFirst()) · Estimated"
    }

    /// "Chocolate, dark, 70-85% cacao solids · US reference · USDA SR Legacy 2018-04-01".
    public static func sourceLine(_ estimate: SavedFoodEntryDetail.LabelEstimateDetail) -> String {
        "\(estimate.genericName) · \(FoodSearchResultText.family(estimate.sourceFamily)) · \(LabelEstimateText.release(estimate.estimateRelease))"
    }

    /// "Cocoa % on the pack: 90%, typed by you".
    public static func cocoaLine(_ estimate: SavedFoodEntryDetail.LabelEstimateDetail) -> String {
        let origin: String = switch estimate.cocoaPercentOrigin {
        case .name: "from the product name, confirmed by you"
        case .pastedText: "from the pasted label, confirmed by you"
        case .typed: "typed by you"
        }
        return "\(LabelEstimateText.confirmed(estimate.cocoaPercent)), \(origin)"
    }

    /// "Estimates: Iron, Magnesium". Each value is also marked "Estimated" beside it.
    public static func keysLine(_ estimate: SavedFoodEntryDetail.LabelEstimateDetail) -> String? {
        estimate.estimatedKeys.isEmpty ? nil
            : "Estimates: " + estimate.estimatedKeys.map(FoodNutritionReviewPresentation.label).joined(separator: ", ")
    }

    /// Developer tools: the policy versions, then both releases and both decisions, label first.
    /// An Open Food Facts entry then lists each estimated key's original unknown reason, read from
    /// the stored product candidate (docs/off-label-estimate-v1.md rule 3).
    public static func developerLines(_ estimate: SavedFoodEntryDetail.LabelEstimateDetail) -> [String] {
        ["Policies: \(estimate.compatibilityVersion), \(estimate.mergeVersion)"]
            + estimate.releases.enumerated().map { "Release \($0.offset + 1): \($0.element.sourceReleaseID.value)" }
            + estimate.decisions.enumerated().map {
                "Decision \($0.offset + 1): \($0.element.candidateDecisionID.rawValue) · \($0.element.outcome.rawValue) · \($0.element.candidate.recordID.value)"
            }
            + (estimate.route == .openFoodFacts ? estimate.estimatedKeys.compactMap { key in
                estimate.originalReasons[key].map { "Original reason, \(FoodNutritionReviewPresentation.label(key)): \($0.rawValue)" }
            } : [])
    }
}

/// The section itself: native grouped style, 44 pt targets, state in words as well as marks.
struct LabelEstimateSection: View {
    @ObservedObject var estimate: LabelEstimateModel
    @ObservedObject var model: FoodConfirmationViewModel
    let focus: FocusState<AmountFieldFocus?>.Binding

    var body: some View {
        Section {
            if estimate.isUnavailableAfterCorrection {
                Text(LabelEstimateText.unavailableAfterCorrection(route)).font(.subheadline)
            } else {
                percentField
                rowsContent
                if let preview = estimate.preview(for: model.state) { previewContent(preview) }
            }
        } header: {
            Text(LabelEstimateText.sectionTitle(route))
        } footer: {
            Text(LabelEstimateText.footer(route))
        }
    }

    private var route: LabelEstimateRoute {
        LabelEstimateOffer.route(model.state) ?? .label
    }

    @ViewBuilder
    private var percentField: some View {
        LabeledContent(LabelEstimateText.fieldTitle) {
            TextField("Percentage", text: Binding(get: { estimate.percentText }, set: { estimate.editPercent($0) }))
                .amountKeyboard(focus, .confirmCocoaPercent)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(LabelEstimateText.fieldTitle)
        }
        .frame(minHeight: 44)
        if estimate.showsSuggestion, let suggestion = estimate.suggestion {
            Text(LabelEstimateText.suggestion(suggestion.origin)).font(.caption)
        }
        if let confirmed = estimate.confirmed {
            Label(LabelEstimateText.confirmed(confirmed.value), systemImage: "checkmark.circle")
                .accessibilityLabel(LabelEstimateText.confirmed(confirmed.value))
        } else {
            Button(LabelEstimateText.confirmTitle) { estimate.confirmPercent() }
                .frame(minHeight: 44)
                .disabled(!estimate.canConfirmPercent)
        }
        if let error = estimate.percentError {
            Label(error, systemImage: "exclamationmark.triangle").font(.caption)
        }
    }

    @ViewBuilder
    private var rowsContent: some View {
        switch estimate.rows {
        case .awaitingPercent:
            EmptyView()
        case .noMatch:
            Text(LabelEstimateText.noMatch).font(.subheadline)
        case .failed:
            Text(LabelEstimateText.failed).font(.subheadline)
        case let .options(options):
            if estimate.chosenID == nil { Text(LabelEstimateText.chooseHint).font(.caption) }
            ForEach(options) { option in
                let chosen = option.id == estimate.chosenID
                let percent = estimate.confirmed?.value ?? 0
                Button { estimate.choose(option.id) } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.generic.name.value)
                            Text(LabelEstimateText.source(option)).font(.caption).foregroundStyle(.secondary)
                            if let note = LabelEstimateText.note(option, cocoaPercent: percent) {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if chosen { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LabelEstimateText.rowAccessibility(option, cocoaPercent: percent, chosen: chosen))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: LabelEstimateText.Preview) -> some View {
        Text(preview.basis).font(.subheadline).foregroundStyle(.secondary)
        ForEach(preview.lines, id: \.key.rawValue) { line in
            Text(line.text).accessibilityLabel(line.accessibilityLabel)
        }
        if let unchanged = preview.unchanged { Text(unchanged).font(.caption) }
        Button(LabelEstimateText.removeTitle, role: .destructive) { estimate.removeEstimate() }
            .frame(minHeight: 44)
    }
}
