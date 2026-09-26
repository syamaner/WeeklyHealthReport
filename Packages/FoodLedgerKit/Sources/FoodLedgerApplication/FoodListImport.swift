import Foundation
import FoodLedgerDomain

public enum FoodListInputMethod: String, Codable, Sendable {
    case pastedOrTyped = "pasted_food_list_line"
    case reviewedSpeechText = "reviewed_food_text_with_on_device_speech"
}

public struct FoodListLineDraft: Codable, Equatable, Sendable, Identifiable {
    public var id: OperationID { operationID }
    public let operationID: OperationID
    public let evidenceID: EvidenceID
    public let parsed: ParsedFoodListLine
    public let inputMethod: FoodListInputMethod
    public var query: String
    public var quantityText: String
    public var unit: QuantityUnit?
    public var preparation: PreparationKind?

    public init(parsed: ParsedFoodListLine, operationID: OperationID, evidenceID: EvidenceID, inputMethod: FoodListInputMethod = .pastedOrTyped) {
        self.parsed = parsed
        self.inputMethod = inputMethod
        self.operationID = operationID
        self.evidenceID = evidenceID
        query = parsed.query
        quantityText = parsed.quantity.map { String($0) } ?? ""
        unit = parsed.unit
        preparation = parsed.preparation
    }
}

/// A single local review queue. Candidate results are deliberately refreshed on resume.
public struct FoodListCheckpoint: Codable, Sendable {
    public static let version = 1
    public var schemaVersion = version
    public var input: String
    public var inputMethod: FoodListInputMethod
    public var drafts: [FoodListLineDraft]
    public var dispositions: [String]
    public var savedIDs: [LogItemID?]
    public var selectedID: OperationID?

    public init(input: String, inputMethod: FoodListInputMethod, drafts: [FoodListLineDraft], dispositions: [String], savedIDs: [LogItemID?], selectedID: OperationID?) {
        self.input = input; self.inputMethod = inputMethod; self.drafts = drafts
        self.dispositions = dispositions; self.savedIDs = savedIDs; self.selectedID = selectedID
    }

    public func validate() throws {
        guard schemaVersion == Self.version, input.count <= 30_000,
              drafts.count <= 200, drafts.count == dispositions.count, drafts.count == savedIDs.count,
              Set(drafts.map(\.operationID)).count == drafts.count,
              Set(drafts.map(\.evidenceID)).count == drafts.count,
              selectedID == nil || drafts.contains(where: { $0.id == selectedID }) else {
            throw FoodLedgerValidationError.invalidProvenance
        }
        for index in drafts.indices {
            _ = try OperationID(drafts[index].operationID.rawValue)
            _ = try EvidenceID(drafts[index].evidenceID.rawValue)
            if let savedID = savedIDs[index] { _ = try LogItemID(savedID.rawValue) }
            guard ["pending", "saved", "declined", "deferred", "context"].contains(dispositions[index]),
                  (dispositions[index] == "saved") == (savedIDs[index] != nil) else {
                throw FoodLedgerValidationError.invalidProvenance
            }
        }
    }
}

public protocol FoodListCheckpointStoring: Sendable {
    func load() throws -> FoodListCheckpoint?
    func save(_ checkpoint: FoodListCheckpoint) throws
}

public enum FoodListSearchResult: Equatable, Sendable {
    case candidates(GenericFoodConfirmationRoute)
    case unresolved(String)
}

public struct FoodListImportService: Sendable {
    private let searcher: any GenericFoodSearching

    public init(searcher: any GenericFoodSearching) { self.searcher = searcher }

    public func search(_ draft: FoodListLineDraft, at date: Date, locale: LedgerText) throws -> FoodListSearchResult {
        let query = try LedgerText(draft.query)
        // JSON preserves leading/trailing whitespace inside the original line despite LedgerText trimming.
        let payload = EvidencePayload(
            lineNumber: draft.parsed.lineNumber, original: draft.parsed.original,
            query: draft.query, quantity: draft.quantityText, unit: draft.unit,
            preparation: draft.preparation, notices: draft.parsed.notices
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let evidence = try CaptureEvidence(
            evidenceID: draft.evidenceID, kind: .manual, capturedAt: date, locale: locale,
            captureMethod: LedgerText(draft.inputMethod.rawValue),
            captureMethodVersion: LedgerText(FoodListParser.version),
            originalPayload: .descriptor(LedgerText(String(decoding: encoder.encode(payload), as: UTF8.self)))
        )
        let request = GenericFoodSearchRequest(
            text: query,
            identity: GenericFoodIdentityQuery(preparation: try draft.preparation.map { try PreparationState(kind: $0) }),
            capturedAt: date, locale: locale, captureEvidence: evidence
        )
        switch try searcher.search(request) {
        case .noResult:
            return .unresolved("No compatible food found. Correct the name or defer this line.")
        case let .confirmation(route):
            if draft.parsed.notices.contains(.supplement),
               route.reuse == nil || route.matches.contains(where: { $0.candidate.itemClass != .supplement }) {
                return .unresolved("This supplement needs an exact saved product with its form and dose. Defer it until those details are available.")
            }
            if draft.parsed.notices.contains(.recipe), route.reuse == nil {
                return .unresolved("This homemade mixture needs a saved recipe. Defer it or log its individual ingredients.")
            }
            return .candidates(route)
        }
    }

    public func confirmation(
        for draft: FoodListLineDraft, route: GenericFoodConfirmationRoute, candidateIndex: Int
    ) throws -> FoodConfirmationState {
        guard route.matches.indices.contains(candidateIndex) else { throw FoodLedgerValidationError.empty("candidate") }
        var state = FoodConfirmationState(input: route.confirmation)
        FoodConfirmationReducer.reduce(state: &state, action: .selectCandidate(candidateIndex))
        // Dataset and saved serving sizes are not consumed amounts. Missing input stays empty.
        state.quantity = FoodQuantityDraft(
            value: draft.unit == nil ? nil : FoodListParser.number(draft.quantityText),
            unit: draft.unit ?? .grams
        )
        return state
    }

    private struct EvidencePayload: Encodable {
        let lineNumber: Int
        let original: String
        let query: String
        let quantity: String
        let unit: QuantityUnit?
        let preparation: PreparationKind?
        let notices: [FoodListNotice]
    }
}
