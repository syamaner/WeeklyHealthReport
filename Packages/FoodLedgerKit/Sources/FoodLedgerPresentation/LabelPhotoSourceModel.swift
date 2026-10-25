import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// Confirm's "Label photo" and "Nutrition from the photo" sections (docs/label-photo-ai-prefill-v1.md
/// P12, 4.2, 5 and 7.3). The app pre-fills every value the model read; the user checks each one
/// that needs attention against the photo: Matches the photo, Correct or Leave unknown. Every
/// change rebuilds Confirm's input through the application builder; nothing is saved until Log.
///
/// While any item is unresolved, Confirm shows a display-only preview (unresolved values count as
/// unknown) and `blocker` disables Log with the pinned-bar sentence. The Log path itself refuses an
/// unresolved review, so the preview can never be saved.
@MainActor
public final class LabelPhotoSourceModel: ObservableObject, LabelFortificationSource {
    public enum State: Equatable, Sendable {
        case found, notFound, flagged, checkFailed, checked, corrected, entered, leftUnknown

        public var text: String {
            switch self {
            case .found: LabelPhotoText.found
            case .notFound: LabelPhotoText.notFound
            case .flagged: LabelPhotoText.flaggedWhenRead
            case .checkFailed: LabelPhotoText.checkFailed
            case .checked: LabelPhotoText.checkedByYou
            case .corrected: LabelPhotoText.correctedByYou
            case .entered: LabelPhotoText.enteredByYou
            case .leftUnknown: LabelPhotoText.leftUnknown
            }
        }

        /// Needs the user before Log.
        public var needsCheck: Bool { [.notFound, .flagged, .checkFailed].contains(self) }
    }

    public enum Action: Equatable, Sendable { case matches, correct, leaveUnknown }

    /// One value or serving line as read, with its state in words.
    public struct Row: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        /// "per 100 g"; empty for a serving line.
        public let column: String
        /// The value as printed, or the user's correction.
        public let value: String
        public let state: State
        public let isAttentionItem: Bool
        public let actions: [Action]
        /// The unit a correction is entered in (`g`, `mg`, `kcal`, `count`).
        public let unit: String

        public var accessibilityLabel: String {
            [title, column.isEmpty ? nil : column, value, state.text].compactMap { $0 }.joined(separator: ", ")
        }
        public var showOnPhotoLabel: String { LabelPhotoText.showOnPhoto(row: title, column: column.isEmpty ? value : column) }
    }

    /// A failed check's table-level item, with its "I've checked them".
    public struct CheckItem: Equatable, Identifiable, Sendable {
        public let id: Int
        public let text: String
        public let itemIDs: [String]
        /// The values it covers, in words ("Protein, per serving; Protein, per 100 g").
        public let values: String
        public let resolved: Bool
    }

    @Published public private(set) var review: LabelPhotoReview
    @Published public private(set) var input: PopulatedFoodConfirmation
    @Published public private(set) var focus: LabelPhotoFocus?
    @Published public private(set) var details: PastedLabelDetails
    /// Why the last action could not be applied, or nil.
    @Published public private(set) var actionFailure: String?
    public let imageBytes: Data
    private let builder: LabelPhotoConfirmation
    private let imageEvidenceID: EvidenceID
    private let manifestEvidenceID: EvidenceID
    private let locale: LedgerText
    private var focusRequests = 0
    /// Called with every rebuilt input (Confirm replaces its source, keeping amount and time).
    public var onInputChange: ((PopulatedFoodConfirmation) -> Void)?
    /// Called with the pinned-bar sentence while Log must wait, or nil.
    public var onBlockerChange: ((String?) -> Void)?

    public init(review: LabelPhotoReview, imageBytes: Data, details: PastedLabelDetails, builder: LabelPhotoConfirmation,
                imageEvidenceID: EvidenceID, manifestEvidenceID: EvidenceID, locale: LedgerText) throws {
        self.review = review; self.imageBytes = imageBytes; self.details = details; self.builder = builder
        self.imageEvidenceID = imageEvidenceID; self.manifestEvidenceID = manifestEvidenceID; self.locale = locale
        input = try Self.build(review, details: details, builder: builder, imageEvidenceID: imageEvidenceID,
                               manifestEvidenceID: manifestEvidenceID, locale: locale)
    }

    static func build(_ review: LabelPhotoReview, details: PastedLabelDetails, builder: LabelPhotoConfirmation, imageEvidenceID: EvidenceID,
                      manifestEvidenceID: EvidenceID, locale: LedgerText) throws -> PopulatedFoodConfirmation {
        review.canLog
            ? try builder.confirmation(review, details: details, imageEvidenceID: imageEvidenceID, manifestEvidenceID: manifestEvidenceID,
                                       attachment: nil, locale: locale)
            : try builder.preview(review, details: details, imageEvidenceID: imageEvidenceID, manifestEvidenceID: manifestEvidenceID,
                                  locale: locale)
    }

    // MARK: What Confirm shows

    public var isEditable: Bool { true }
    public var fortificationAnswer: PastedLabelIdentity.FortificationAnswer { details.fortification }
    /// Log is enabled only when every attention item is resolved (P12).
    public var canLog: Bool { review.canLog }
    public var unresolvedCount: Int { review.unresolved.count }
    /// The pinned bar beside a disabled Log, or nil once every item is resolved.
    public var blocker: String? { review.canLog ? nil : LabelPhotoText.pinnedBar(review.unresolved.count) }
    /// The summary under the honesty note: the count still needing a check, or that every value
    /// was found; nil once the user has resolved every item (the rows say how).
    public var attentionSummary: String? {
        if review.findings.items.isEmpty { return LabelPhotoText.attentionNone }
        return review.unresolved.isEmpty ? nil : LabelPhotoText.attentionSummary(review.unresolved.count)
    }
    public var sourceLine: String {
        let stored = review.reading.candidate.headers.first { $0.headerID == review.storedHeaderID }
        return LabelPhotoText.sourceLine(basis: LabelPhotoText.column(stored?.basis ?? "per_100g"))
    }

    public var rows: [Row] {
        let candidate = review.reading.candidate
        let columns = Dictionary(candidate.headers.map { ($0.headerID, $0.basis) }, uniquingKeysWith: { first, _ in first })
        let byItem = Dictionary(review.findings.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let locations = locationsByItem
        var rows: [Row] = []
        for header in candidate.headers {
            for cell in candidate.cells where cell.headerID == header.headerID {
                let item = LabelPhotoManifest.cellItem(rowID: cell.rowID, headerID: cell.headerID)
                let correction = review.corrections.first { $0.rowID == cell.rowID && $0.headerID == cell.headerID }
                let value = correction.map { Self.text($0.corrected) } ?? cell.printedText
                let state = state(item, finding: byItem[item], location: locations[item]?.status)
                let attention = byItem[item] != nil
                var actions: [Action] = attention ? [.matches] : []
                if cell.headerID == review.storedHeaderID { actions.append(.correct) }
                if attention { actions.append(.leaveUnknown) }
                rows.append(Row(id: item, title: Self.title(cell.nutrient, printed: cell.printedLabel),
                                column: LabelPhotoText.column(columns[cell.headerID] ?? cell.basis), value: value, state: state,
                                isAttentionItem: attention, actions: actions, unit: cell.canonicalUnit))
            }
        }
        return rows
    }

    public var servingRows: [Row] {
        let candidate = review.reading.candidate
        let byItem = Dictionary(review.findings.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let locations = locationsByItem
        let lines: [(String, String, String?, String)] = [
            (PastedLabelManifest.Correction.servingSize, "Serving size", candidate.servingSize?.printedText, candidate.servingSize?.canonicalUnit ?? "g"),
            (PastedLabelManifest.Correction.servingsPerPack, "Servings per pack", candidate.servingsPerPack?.printedText, QuantityUnit.count.rawValue),
        ]
        return lines.compactMap { id, title, printed, unit in
            let correction = review.corrections.first { $0.rowID == nil && $0.nutrient == id }
            guard printed != nil || correction != nil else { return nil }
            let attention = byItem[id] != nil
            var actions: [Action] = attention ? [.matches] : []
            if id == PastedLabelManifest.Correction.servingSize || printed == nil { actions.append(.correct) }
            if attention { actions.append(.leaveUnknown) }
            return Row(id: id, title: title, column: "", value: correction.map { Self.text($0.corrected) } ?? printed ?? "",
                       state: state(id, finding: byItem[id], location: locations[id]?.status), isAttentionItem: attention,
                       actions: actions, unit: unit)
        }
    }

    public var checkItems: [CheckItem] {
        let titles = Dictionary(rows.map { ($0.id, $0.column.isEmpty ? $0.title : "\($0.title), \($0.column)") }, uniquingKeysWith: { first, _ in first })
        return review.findings.checks.enumerated().map { index, group in
            CheckItem(id: index, text: LabelPhotoText.check(group.check.name), itemIDs: group.itemIDs,
                      values: group.itemIDs.compactMap { titles[$0] }.joined(separator: "; "),
                      resolved: group.itemIDs.allSatisfy { review.resolutions[$0] != nil })
        }
    }

    var locationsByItem: [String: LabelPhotoManifest.Location] {
        Dictionary(review.locations.records.map { ($0.item, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func state(_ item: String, finding: LabelPhotoAttention.Item?, location: LabelPhotoAttention.Location?) -> State {
        if let resolution = review.resolutions[item]?.resolution {
            switch resolution {
            case .checked: return .checked
            case .corrected: return .corrected
            case .entered: return .entered
            case .leftUnknown: return .leftUnknown
            }
        }
        if review.corrections.contains(where: { correction in
            if let cell = review.reading.candidate.cells.first(where: { LabelPhotoManifest.cellItem(rowID: $0.rowID, headerID: $0.headerID) == item }) {
                return correction.rowID == cell.rowID && correction.headerID == cell.headerID
            }
            return correction.rowID == nil && correction.nutrient == item
        }) { return .corrected }
        guard let finding else { return location == .found ? .found : .notFound }
        if finding.reasons.contains(.notFound) || finding.reasons.contains(.ambiguous) { return .notFound }
        if finding.reasons.contains(.checkFailed) { return .checkFailed }
        return .flagged
    }

    static func text(_ value: PastedLabelManifest.Correction.Value) -> String {
        let comparator = value.comparator == "=" ? "" : value.comparator + " "
        return comparator + value.decimalText + (value.unit == "count" ? "" : " " + value.unit)
    }

    nonisolated static let titles: [String: String] = [
        "energy_kcal": "Energy (kcal)", "energy_kj": "Energy (kJ)", "protein": "Protein", "fat": "Fat", "saturates": "Saturated fat",
        "trans_fat": "Trans fat", "carbohydrate": "Carbohydrate", "sugars": "Sugars", "fibre": "Fibre", "sodium": "Sodium", "salt": "Salt",
    ]

    nonisolated static func title(_ nutrient: String, printed: String) -> String { titles[nutrient] ?? printed }

    // MARK: Actions

    /// "Show on photo" or a tap on the row: centre and outline its region, or say it was not found.
    public func show(_ id: String) {
        guard let row = (rows + servingRows).first(where: { $0.id == id }) else { return }
        let record = locationsByItem[id]
        let region = record?.status == .found ? LabelPhotoFocus.Rect(record?.region) : nil
        focusRequests += 1
        focus = LabelPhotoFocus(region: region, rowLabel: nil, caption: LabelPhotoText.caption(row: row.title, column: row.column.isEmpty ? row.value : row.column),
                                message: region == nil ? LabelPhotoText.notFoundOnPhoto : nil, request: focusRequests)
    }

    public var focusAnnouncement: String? {
        guard let focus else { return nil }
        return focus.message ?? "Showing \(focus.caption), on the photo"
    }

    public func matches(_ id: String) { apply { try builder.check(id, in: $0) } }
    public func leaveUnknown(_ id: String) { apply { try builder.leaveUnknown(id, in: $0) } }
    public func checkGroup(_ index: Int) {
        guard review.findings.checks.indices.contains(index) else { return }
        let group = review.findings.checks[index]
        apply { try builder.checkGroup(group, in: $0) }
    }

    /// Correct: the user's value in the row's unit. Returns the reason when it is refused.
    @discardableResult
    public func correct(_ id: String, text: String, comparator: String = "=") -> String? {
        guard let row = (rows + servingRows).first(where: { $0.id == id }) else { return LabelPhotoText.correctionRefused }
        let decimal = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let value = PastedLabelManifest.Correction.Value(decimalText: decimal, unit: row.unit, comparator: comparator)
        let printed = id == PastedLabelManifest.Correction.servingsPerPack ? review.reading.candidate.servingsPerPack != nil
            : id == PastedLabelManifest.Correction.servingSize ? review.reading.candidate.servingSize != nil : true
        apply { review in printed ? try builder.correct(id, value: value, in: review) : try builder.enter(id, value: value, in: review) }
        return actionFailure
    }

    public func answerFortification(_ answer: PastedLabelIdentity.FortificationAnswer) throws {
        let next = PastedLabelDetails(name: details.name, brand: details.brand, fortification: answer)
        let rebuilt = try Self.build(review, details: next, builder: builder, imageEvidenceID: imageEvidenceID,
                                     manifestEvidenceID: manifestEvidenceID, locale: locale)
        details = next
        publish(rebuilt)
    }

    private func apply(_ change: (LabelPhotoReview) throws -> LabelPhotoReview) {
        actionFailure = nil
        do {
            let next = try change(review)
            let rebuilt = try Self.build(next, details: details, builder: builder, imageEvidenceID: imageEvidenceID,
                                         manifestEvidenceID: manifestEvidenceID, locale: locale)
            review = next
            publish(rebuilt)
        } catch let error as LabelPhotoConfirmationError {
            actionFailure = Self.reason(error)
        } catch {
            actionFailure = LabelPhotoText.correctionRefused
        }
    }

    private func publish(_ rebuilt: PopulatedFoodConfirmation) {
        input = rebuilt
        onInputChange?(rebuilt)
        onBlockerChange?(blocker)
    }

    static func reason(_ error: LabelPhotoConfirmationError) -> String {
        switch error {
        case .invalidValue: LabelPhotoText.invalidValue
        case .notCorrectable: LabelPhotoText.notCorrectable
        default: LabelPhotoText.correctionRefused
        }
    }
}
