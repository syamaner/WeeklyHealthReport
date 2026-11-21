import ConfirmEnrichmentEvalCore
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// Builds the app's own Confirm state for one case (docs/confirm-enrichment-openrouter-v1-phase.md
/// section 3.3 item 5), so the evaluation sends exactly the app's request bytes:
///
/// - an Open Food Facts case goes through the public `OpenFoodFactsProductMapping.project`, the one the
///   barcode and search routes call, with `evidence:` built as each of those callers builds it from the
///   export record's bytes and the case's retrieval time;
/// - a bundled-row case goes through the table's public `search(_:)` and selects the result with the
///   case's `recordID`, failing the case when it is absent.
///
/// Hidden keys (B) are then made eligible unknowns on the selected candidate.
public struct EvalCandidates: Sendable {
    public enum Problem: Error, Equatable, CustomStringConvertible {
        case recordUnreadable, notACandidate, rowAbsent, tableUnavailable
        public var description: String {
            switch self {
            case .recordUnreadable: "record_unreadable"
            case .notACandidate: "not_a_candidate"
            case .rowAbsent: "row_absent"
            case .tableUnavailable: "table_unavailable"
            }
        }
    }

    let ids: any LedgerIDGenerating
    let tables: @Sendable (EvalCase.Table) throws -> any GenericFoodSearching

    public init(ids: any LedgerIDGenerating = RandomLedgerIDGenerator(),
                tables: (@Sendable (EvalCase.Table) throws -> any GenericFoodSearching)? = nil) {
        self.ids = ids
        self.tables = tables ?? { table in
            let ids = RandomLedgerIDGenerator()
            switch table {
            case .cofid: return try CoFIDGenericFoodSearch(ids: ids)
            case .usda: return try USDAGenericFoodSearch(ids: ids)
            case .tfda: return try TFDAGenericFoodSearch(ids: ids)
            case .ciqual: return try CiqualGenericFoodSearch(ids: ids)
            }
        }
    }

    static let locale = try! LedgerText("en_GB")

    /// The Open Food Facts candidate input of a product record, as the barcode or the search route builds it.
    public func openFoodFactsInput(product: [String: Any], shape: EvalCase.Shape, retrievedAt: Date) throws -> PopulatedFoodConfirmation {
        guard let code = product["code"] as? String, [8, 12, 13, 14].contains(code.count), code.allSatisfy(\.isNumber) else {
            throw Problem.recordUnreadable
        }
        let gtin = try LedgerText(String(repeating: "0", count: 14 - code.count) + code)
        let artifact: Data
        let evidence: CaptureEvidence
        switch shape {
        case .barcode:
            // The barcode route's artifact is the product response document; its evidence is the scan.
            artifact = try JSONSerialization.data(withJSONObject: ["status": "success", "product": product], options: [.sortedKeys])
            evidence = try CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self), kind: .barcode, capturedAt: retrievedAt,
                locale: Self.locale, captureMethod: LedgerText("visionkit"), captureMethodVersion: LedgerText("visionkit-barcode-v1"),
                originalPayload: .barcode(value: LedgerText(code), symbology: LedgerText("ean-13")))
        case .search:
            // The search route's artifact is the product object with sorted keys; its evidence is the query.
            artifact = try JSONSerialization.data(withJSONObject: product, options: [.sortedKeys])
            let query = (product["product_name"] as? String) ?? code
            evidence = try CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch, capturedAt: retrievedAt,
                locale: Self.locale, captureMethod: LedgerText("off_text_search"),
                captureMethodVersion: LedgerText("off-search-candidates-v6"), originalPayload: .text(LedgerText(query)))
        }
        guard case let .candidate(input) = try OpenFoodFactsProductMapping.project(
            product: product, artifact: artifact, gtin: gtin, evidence: evidence, retrievedAt: retrievedAt,
            searchScore: shape == .search ? 1 : nil, searchCategory: nil) else { throw Problem.notACandidate }
        return input
    }

    /// The bundled row's candidate input, selected from the table's own search by `recordID`.
    public func bundledInput(table: EvalCase.Table, search: String, recordID: String, retrievedAt: Date) throws -> PopulatedFoodConfirmation {
        let source: any GenericFoodSearching
        do { source = try tables(table) } catch { throw Problem.tableUnavailable }
        let request = GenericFoodSearchRequest(text: try LedgerText(search), capturedAt: retrievedAt, locale: Self.locale)
        guard case let .confirmation(route) = try source.search(request),
              let candidate = route.confirmation.candidates.first(where: { $0.candidate.recordID.value == recordID }) else {
            throw Problem.rowAbsent
        }
        return try PopulatedFoodConfirmation(evidence: route.confirmation.evidence, sourceReleases: route.confirmation.sourceReleases,
            candidates: [candidate], expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity)
    }

    /// The candidate with each hidden key made an eligible unknown.
    public static func hiding(_ input: PopulatedFoodConfirmation, keys: Set<NutrientKey>) throws -> PopulatedFoodConfirmation {
        guard !keys.isEmpty, let first = input.candidates.first else { return input }
        let source = first.candidate
        let hidden = try ProviderNeutralCandidate(
            sourceReleaseID: source.sourceReleaseID, recordID: source.recordID, identity: source.identity,
            edibleQuantity: source.edibleQuantity, nutrients: EvalHiding.hide(source.nutrients, keys: keys),
            evidenceIDs: source.evidenceIDs, matchMetadata: source.matchMetadata)
        let candidate = try PopulatedFoodCandidate(candidate: hidden, name: first.name, brand: first.brand, variant: first.variant,
            barcode: first.barcode, itemClass: first.itemClass, packFacts: first.packFacts)
        return try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases, candidates: [candidate],
            expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
    }

    /// The Confirm state for a case, read from the private folder.
    public func state(for evalCase: EvalCase, privateFolder: URL) throws -> FoodConfirmationState {
        guard let retrievedAt = evalCase.retrievalDate else { throw Problem.recordUnreadable }
        let input: PopulatedFoodConfirmation
        switch evalCase.kind {
        case .openFoodFacts:
            guard let record = evalCase.record, let shape = evalCase.shape,
                  let data = FileManager.default.contents(atPath: privateFolder.appendingPathComponent(record).path),
                  let product = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Problem.recordUnreadable }
            input = try openFoodFactsInput(product: product, shape: shape, retrievedAt: retrievedAt)
        case .bundledRow:
            guard let table = evalCase.table, let search = evalCase.search, let recordID = evalCase.recordID else { throw Problem.rowAbsent }
            input = try bundledInput(table: table, search: search, recordID: recordID, retrievedAt: retrievedAt)
        }
        return FoodConfirmationState(input: try Self.hiding(input, keys: evalCase.hiddenKeys), prefillSourceQuantity: false)
    }
}

/// The app's own request for a state (docs/confirm-enrichment-openrouter-v1-phase.md section 3.2).
public enum EvalRequests {
    public static func details(_ state: FoodConfirmationState, route: ConfirmEnrichmentRoute,
                               encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
                               digester: any Digesting = SHA256Digester()) throws -> ConfirmEnrichmentPolicy.DetailsRequest? {
        guard let source = ConfirmEnrichmentPolicy.sourceRoute(state.input, candidate: state.selectedCandidate),
              let asked = ConfirmEnrichmentPolicy.detailsQuestions(state, route: source, database: nil) else { return nil }
        let description = ConfirmEnrichmentPolicy.description(source, candidate: state.selectedCandidate, database: nil)
        let inputs = try ConfirmDetailsRequestInputs(
            description: description, knownDetails: ConfirmEnrichmentPolicy.knownDetails(state.selectedCandidate.candidate.identity),
            asked: asked)
        return try ConfirmEnrichmentPolicy.detailsRequest(inputs, route: route, encoder: encoder, digester: digester)
    }

    public static func nutrients(_ state: FoodConfirmationState, route: ConfirmEnrichmentRoute,
                                 encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
                                 digester: any Digesting = SHA256Digester()) throws -> ConfirmEnrichmentPolicy.NutrientRequest? {
        guard let source = ConfirmEnrichmentPolicy.sourceRoute(state.input, candidate: state.selectedCandidate) else { return nil }
        let description = ConfirmEnrichmentPolicy.description(source, candidate: state.selectedCandidate, database: nil)
        guard let inputs = ConfirmEnrichmentPolicy.nutrientInputs(state, route: source, description: description,
                                                                  identity: state.selectedCandidate.candidate.identity,
                                                                  labelLayerKeys: []) else { return nil }
        return try ConfirmEnrichmentPolicy.nutrientRequest(inputs, route: route, encoder: encoder, digester: digester)
    }
}
