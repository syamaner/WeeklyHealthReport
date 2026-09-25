import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

public enum FoodListLineStatus: Equatable, Sendable {
    case pending, candidates, declined, deferred, context
    case unresolved(String), failed(String), saved(LogItemID)

    public var label: String {
        switch self {
        case .pending: "Needs review"
        case .candidates: "Choose a match"
        case .declined: "Declined"
        case .deferred: "Deferred"
        case .context: "Context — not logged"
        case .unresolved: "Unresolved"
        case .failed: "Failed — retry available"
        case .saved: "Saved"
        }
    }
}

public struct FoodListReviewRow: Identifiable {
    public var id: OperationID { draft.id }
    public var draft: FoodListLineDraft
    public var status: FoodListLineStatus = .pending
    public var route: GenericFoodConfirmationRoute?
    public var isSaved: Bool { if case .saved = status { true } else { false } }
}

@MainActor
public final class FoodListImportViewModel: ObservableObject {
    @Published public var input = ""
    @Published public private(set) var rows: [FoodListReviewRow] = []
    @Published public private(set) var selectedID: OperationID?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var confirmation: FoodConfirmationViewModel?
    private let service: FoodListImportService
    private let locale: LedgerText
    private let ids: any LedgerIDGenerating
    private let now: @MainActor () -> Date
    private let saveAction: @MainActor (FoodConfirmationState, OperationID) throws -> StoredFoodConfirmation
    private var confirmationRowID: OperationID?

    public init(
        service: FoodListImportService, locale: LedgerText, ids: any LedgerIDGenerating,
        now: @escaping @MainActor () -> Date = Date.init,
        saveAction: @escaping @MainActor (FoodConfirmationState, OperationID) throws -> StoredFoodConfirmation
    ) {
        self.service = service
        self.locale = locale
        self.ids = ids
        self.now = now
        self.saveAction = saveAction
    }

    public var selectedRow: FoodListReviewRow? { rows.first { $0.id == selectedID } }
    public var savedCount: Int { rows.filter(\.isSaved).count }
    public var progress: String {
        guard !rows.isEmpty else { return "No list prepared" }
        let contextCount = rows.filter { $0.status == .context }.count
        let foodCount = rows.count - contextCount
        let remaining = foodCount - savedCount
        let summary = foodCount == 0 ? "No food lines selected" : remaining == 0 ? "All \(foodCount) items saved" : "\(savedCount) of \(foodCount) saved · \(remaining) not saved"
        return contextCount == 0 ? summary : "\(summary) · \(contextCount) context lines"
    }

    public func prepare() {
        guard rows.isEmpty else { return }
        do {
            let parsed = try FoodListParser.parse(input)
            let prepared = try parsed.map {
                FoodListReviewRow(draft: FoodListLineDraft(
                    parsed: $0, operationID: try ids.makeID(OperationTag.self),
                    evidenceID: try ids.makeID(EvidenceTag.self)
                ), status: $0.notices.contains(.contextLine) ? .context : .pending)
            }
            rows = prepared
            selectedID = rows.first(where: { $0.status != .context })?.id ?? rows.first?.id
            errorMessage = nil
        } catch FoodListParser.ParseError.empty {
            errorMessage = "Paste at least one food or drink line."
        } catch FoodListParser.ParseError.tooLarge {
            errorMessage = "Use at most 200 lines and 30,000 characters per list. Your text is still here."
        } catch {
            errorMessage = "The list could not be prepared. Your text is still here."
        }
    }

    public func select(_ id: OperationID) {
        guard confirmation == nil, rows.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    public func edit(_ draft: FoodListLineDraft) {
        guard confirmation == nil, let index = rows.firstIndex(where: { $0.id == draft.id }), !rows[index].isSaved else { return }
        rows[index].draft = draft
        rows[index].status = .pending
        rows[index].route = nil
    }

    public func search() {
        guard confirmation == nil, let index = selectedIndex, !rows[index].isSaved else { return }
        do {
            switch try service.search(rows[index].draft, at: now(), locale: locale) {
            case let .candidates(route):
                rows[index].route = route
                rows[index].status = .candidates
            case let .unresolved(message):
                rows[index].route = nil
                rows[index].status = .unresolved(message)
            }
        } catch {
            rows[index].route = nil
            rows[index].status = .failed("Search failed. Check the name and try again; the line has been kept.")
        }
    }

    public func review(candidate index: Int) {
        guard confirmation == nil, let row = selectedRow, !row.isSaved, let route = row.route else { return }
        do {
            let state = try service.confirmation(for: row.draft, route: route, candidateIndex: index)
            confirmationRowID = row.id
            confirmation = FoodConfirmationViewModel(state: state) { [weak self] state in
                guard let self else { throw FoodLedgerValidationError.empty("review session") }
                do {
                    let saved = try self.saveAction(state, row.id)
                    if let rowIndex = self.rows.firstIndex(where: { $0.id == row.id }) {
                        self.rows[rowIndex].status = .saved(saved.logItem.logItemID)
                    }
                    return saved
                } catch {
                    if let rowIndex = self.rows.firstIndex(where: { $0.id == row.id }) {
                        self.rows[rowIndex].status = .failed(FoodConfirmationViewModel.message(for: error))
                    }
                    throw error
                }
            }
        } catch { errorMessage = "That candidate could not be opened. Search the line again." }
    }

    public func finishReview() {
        if let id = confirmationRowID, let index = rows.firstIndex(where: { $0.id == id }) {
            if confirmation?.state.decision == .declined, !rows[index].isSaved {
                rows[index].status = .declined
            }
            if rows[index].isSaved || rows[index].status == .declined { selectNext(after: index) }
        }
        confirmation = nil
        confirmationRowID = nil
    }

    public func deferLine() { mark(.deferred) }
    public func declineLine() { mark(.declined) }
    public func reviewContextAsFood() {
        guard let index = selectedIndex, rows[index].status == .context else { return }
        rows[index].status = .pending
    }

    public func startNewList() {
        guard confirmation == nil else { return }
        input = ""
        rows = []
        selectedID = nil
        errorMessage = nil
    }

    private var selectedIndex: Int? { rows.firstIndex { $0.id == selectedID } }
    private func mark(_ status: FoodListLineStatus) {
        guard confirmation == nil, let index = selectedIndex, !rows[index].isSaved else { return }
        rows[index].status = status
        selectNext(after: index)
    }
    private func selectNext(after index: Int) {
        let ordered = Array(rows.indices.dropFirst(index + 1)) + Array(rows.indices.prefix(index))
        selectedID = ordered.first(where: {
            !rows[$0].isSaved && rows[$0].status != .declined && rows[$0].status != .deferred && rows[$0].status != .context
        }).map { rows[$0].id } ?? rows[index].id
    }
}

public struct FoodListImportView: View {
    @ObservedObject private var model: FoodListImportViewModel
    @State private var confirmsNewList = false
    @State private var showsAllLines = false

    public init(model: FoodListImportViewModel) { self.model = model }

    public var body: some View {
        Form {
            if model.rows.isEmpty {
                Section("Paste foods and drinks") {
                    Text("One item per line, including the amount you consumed.")
                    TextEditor(text: $model.input)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Food list")
                    Button("Prepare list") { model.prepare() }
                }
            } else {
                Section(model.progress) {
                    DisclosureGroup("All lines and their status", isExpanded: $showsAllLines) {
                        ForEach(model.rows) { row in
                            Button { model.select(row.id); showsAllLines = false } label: {
                                VStack(alignment: .leading) {
                                    Text("\(row.draft.parsed.lineNumber). \(row.draft.parsed.original)")
                                        .foregroundStyle(.primary)
                                    Text(row.status.label).font(.caption)
                                }
                            }
                            .accessibilityAddTraits(row.id == model.selectedID ? .isSelected : [])
                        }
                    }
                }
                if let row = model.selectedRow { editor(row) }
                Section {
                    Text("Saved items are kept in your local ledger. Unsaved lines remain in this session while the app is open.")
                        .font(.caption)
                    Button("Start another list") { confirmsNewList = true }
                }
            }
            if let message = model.errorMessage {
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            }
        }
        .navigationTitle("Paste food list")
        .confirmationDialog("Discard this review queue and start another list? Saved items will remain.", isPresented: $confirmsNewList) {
            Button("Start another list", role: .destructive) { model.startNewList() }
        }
        .sheet(isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.finishReview() } })) {
            if let confirmation = model.confirmation {
                NavigationStack {
                    FoodConfirmationView(
                        model: confirmation,
                        context: model.selectedRow.map { row in
                            ([row.draft.parsed.original] + row.draft.parsed.notices.map(\.message)).joined(separator: "\n")
                        },
                        completionTitle: "Next line", leave: { model.finishReview() }
                    )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Back to list") { model.finishReview() }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func editor(_ row: FoodListReviewRow) -> some View {
        if row.status == .context {
            Section("Context") {
                Text(row.draft.parsed.original)
                Text("Kept with this list. No food or quantity has been inferred.").font(.caption)
                Button("Review as food instead") { model.reviewContextAsFood() }
            }
        } else if row.isSaved {
            Section("Saved") { Text("This line has already been saved. It will not be saved again from this queue.") }
        } else {
            Section("Review line \(row.draft.parsed.lineNumber)") {
                Text(row.draft.parsed.original).textSelection(.enabled)
                ForEach(row.draft.parsed.notices, id: \.rawValue) { notice in
                    Label(notice.message, systemImage: "exclamationmark.triangle").font(.caption)
                }
                TextField("Food name and modifiers", text: binding(row, \.query))
                if let suggestion = FoodListParser.suggestedQuery(row.draft.query) {
                    Button("Use spelling: \(suggestion)") {
                        var draft = row.draft
                        draft.query = suggestion
                        model.edit(draft)
                    }
                }
                TextField("Consumed amount", text: binding(row, \.quantityText))
                Picker("Unit", selection: binding(row, \.unit)) {
                    Text("Choose unit").tag(Optional<QuantityUnit>.none)
                    Text("g").tag(Optional(QuantityUnit.grams))
                    Text("mL").tag(Optional(QuantityUnit.millilitres))
                    Text("count").tag(Optional(QuantityUnit.count))
                }
                Picker("Preparation", selection: binding(row, \.preparation)) {
                    Text("Unspecified").tag(Optional<PreparationKind>.none)
                    Text("Raw").tag(Optional(PreparationKind.raw))
                    Text("Cooked").tag(Optional(PreparationKind.cooked))
                    Text("As sold").tag(Optional(PreparationKind.asSold))
                }
                Button("Find matches") { model.search() }
                    .disabled(row.draft.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if case let .unresolved(message) = row.status { Text(message) }
                if case let .failed(message) = row.status { Text(message) }
                Button("Defer this line") { model.deferLine() }
                Button("Decline this line", role: .cancel) { model.declineLine() }
            }
            if let route = row.route {
                Section("Choose a match to review") {
                    ForEach(Array(route.matches.enumerated()), id: \.offset) { index, match in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(match.candidate.name.value).font(.headline)
                            if let variant = match.candidate.variant { Text(variant.value).font(.caption) }
                            Text(route.reuse != nil ? "Saved food" : match.isExactName ? "Exact name" : "Closest candidate")
                                .font(.caption)
                            if let metadata = match.candidate.candidate.matchMetadata {
                                ForEach(metadata.materialDifferences, id: \.value) { difference in
                                    Text(difference.value
                                        .replacingOccurrences(of: "candidate_only_token:", with: "Candidate adds: ")
                                        .replacingOccurrences(of: "query_only_token:", with: "Your entry adds: "))
                                        .font(.caption)
                                }
                            }
                            Button("Review and confirm") { model.review(candidate: index) }
                        }
                    }
                }
            }
        }
    }

    private func binding<Value>(_ row: FoodListReviewRow, _ keyPath: WritableKeyPath<FoodListLineDraft, Value>) -> Binding<Value> {
        Binding(
            get: { model.rows.first(where: { $0.id == row.id })?.draft[keyPath: keyPath] ?? row.draft[keyPath: keyPath] },
            set: { value in
                guard var draft = model.rows.first(where: { $0.id == row.id })?.draft else { return }
                draft[keyPath: keyPath] = value
                model.edit(draft)
            }
        )
    }
}
