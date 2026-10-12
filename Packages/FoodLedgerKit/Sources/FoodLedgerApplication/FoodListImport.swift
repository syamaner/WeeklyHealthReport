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

    /// True while the amount is the parser's own proposal, untouched by the user.
    public var isAmountUntouched: Bool {
        guard let parsed = parsed.quantity else { return false }
        return quantityText == String(parsed)
    }

    /// The consumed amount this line proposes (food-list-lexical-v4, Q6): the untouched parse
    /// (read under the line's own convention), or typed text that presentation has already made
    /// canonical with the amount field's locale, read with the canonical amount parser. The
    /// line's convention never reinterprets typed text. A v3 line keeps the frozen v3 reading.
    public var amountValue: Double? {
        guard parsed.isV4 else { return FoodListParser.number(quantityText) }
        if isAmountUntouched { return parsed.quantity }
        return FoodAmountTextParser.parse(quantityText)
    }

    /// The amount text recorded in capture evidence. A v3 line records its text as before; a v4
    /// line records canonical text (full stop decimal, no grouping) when it reads as one amount,
    /// otherwise its text unchanged.
    public var evidenceQuantityText: String {
        guard parsed.isV4 else { return quantityText }
        return amountValue.map(FoodAmountTextParser.editableText) ?? quantityText
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
    private let ids: any LedgerIDGenerating

    public init(searcher: any GenericFoodSearching, ids: any LedgerIDGenerating = RandomLedgerIDGenerator()) {
        self.searcher = searcher
        self.ids = ids
    }

    public func search(_ draft: FoodListLineDraft, at date: Date, locale: LedgerText) throws -> FoodListSearchResult {
        let query = try LedgerText(draft.query)
        // JSON preserves leading/trailing whitespace inside the original line despite LedgerText trimming.
        let payload = EvidencePayload(
            lineNumber: draft.parsed.lineNumber, original: draft.parsed.original,
            query: draft.query, quantity: draft.evidenceQuantityText, unit: draft.unit,
            preparation: draft.preparation, notices: draft.parsed.notices,
            numeralConvention: draft.parsed.numeralConvention
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let evidence = try CaptureEvidence(
            evidenceID: draft.evidenceID, kind: .manual, capturedAt: date, locale: locale,
            captureMethod: LedgerText(draft.inputMethod.rawValue),
            // The line's own grammar: a v3 line restored from a checkpoint stays labelled v3.
            captureMethodVersion: LedgerText(draft.parsed.effectiveGrammarVersion),
            originalPayload: .descriptor(LedgerText(String(decoding: encoder.encode(payload), as: UTF8.self)))
        )
        // The reviewed line and the subsequent search are distinct evidence events.
        // Retain the manual capture first; never relabel reviewed speech as search input.
        let searchEvidence = try CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch,
            capturedAt: date, locale: locale,
            captureMethod: LedgerText("food_list_generic_search"),
            captureMethodVersion: LedgerText("v1"), originalPayload: .text(query)
        )
        guard searchEvidence.evidenceID != evidence.evidenceID else {
            throw FoodLedgerValidationError.invalidProvenance
        }
        let request = GenericFoodSearchRequest(
            text: query,
            identity: GenericFoodIdentityQuery(preparation: try draft.preparation.map { try PreparationState(kind: $0) }),
            capturedAt: date, locale: locale, captureEvidence: evidence, additionalEvidence: [searchEvidence]
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
        guard route.matches.indices.contains(candidateIndex), let input = route.choosing(candidateIndex) else {
            throw FoodLedgerValidationError.empty("candidate")
        }
        // Same snapshot as the search route: the chosen candidate's own expectations, so a
        // later candidate is not compared against the first candidate's identity.
        var state = FoodConfirmationState(input: input)
        // Dataset and saved serving sizes are not consumed amounts. Missing input stays empty.
        state.quantity = FoodQuantityDraft(
            value: draft.unit == nil ? nil : draft.amountValue,
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
        /// Present on v4 lines only, so a v3 descriptor encodes exactly as before.
        let numeralConvention: NumeralConvention?
    }
}
