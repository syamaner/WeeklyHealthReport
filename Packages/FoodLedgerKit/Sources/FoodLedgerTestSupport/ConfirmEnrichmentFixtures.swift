import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Synthetic Confirm enrichment v1 records (no owner data): a B request body, a reply, its capture and
/// choices evidence and the provenance a kept value carries. For contract and application tests only.
public enum ConfirmEnrichmentFixtures {
    public static let model = "openai/gpt-6.1-sol"
    public static let provider = "Azure"
    /// A placeholder: fixtures never hold a real API address (O1.6 test 6).
    public static let endpoint = "https://example.invalid/v1/chat/completions"
    public static let capturedAt = Date(timeIntervalSince1970: 1_795_000_000)

    public static func id<Tag>(_ n: Int) throws -> LedgerID<Tag> {
        try LedgerID<Tag>(String(format: "00000000-0000-4000-8000-%012d", n))
    }

    public static func description() -> ConfirmEnrichmentDescription {
        ConfirmEnrichmentDescription(name: "Synthetic oat bar", brand: "Example", variant: nil, category: nil,
                                     productType: nil, state: nil, source: .openFoodFacts)
    }

    /// Known energy, protein, carbohydrate and fat; fibre and sodium asked.
    public static func inputs() -> ConfirmNutrientRequestInputs {
        ConfirmNutrientRequestInputs(
            description: description(), identity: ["preparation": "as_sold"], basis: .per100Grams,
            known: [.init(nutrient: .energyConsumed, value: 400, source: "from the product's Open Food Facts record"),
                    .init(nutrient: .protein, value: 10, source: "from the product's Open Food Facts record"),
                    .init(nutrient: .carbohydrates, value: 60, source: "from the product's Open Food Facts record"),
                    .init(nutrient: .fatTotal, value: 12, source: "from the product's Open Food Facts record")],
            eligible: [.fiber, .sodium])
    }

    /// A chat completions body whose single user message holds the canonical inputs.
    public static func requestBody(_ inputs: ConfirmNutrientRequestInputs) throws -> String {
        let content = String(decoding: try FoundationCanonicalJSONEncoder().encode(inputs), as: UTF8.self)
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": "Fixed instruction."], ["role": "user", "content": content]]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), as: UTF8.self)
    }

    /// A reply with the given rows, as OpenRouter returns a chat completion.
    public static func response(values: [[String: Any]], basis: String = "per_100_g", model: String = model,
                                provider: String = provider, finish: String = "stop") throws -> Data {
        let content = String(decoding: try JSONSerialization.data(withJSONObject: [
            "schema": ConfirmEnrichmentVersions.nutrientSchema, "basis": basis, "values": values
        ], options: [.sortedKeys]), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: [
            "id": "gen-synthetic-1", "model": model, "provider": provider,
            "choices": [["finish_reason": finish, "message": ["role": "assistant", "content": content]]],
            "usage": ["cost": 0.0012, "prompt_tokens": 410]
        ], options: [.sortedKeys])
    }

    public static func defaultValues() -> [[String: Any]] {
        [["nutrient": "fiber", "value": 6.5, "unit": "g"], ["nutrient": "sodium", "value": 120, "unit": "mg"]]
    }

    public struct Built {
        public let capture: ConfirmNutrientCapture
        public let captureEvidence: CaptureEvidence
        public let choicesEvidence: CaptureEvidence
        public let resolutionVersionID: ResolutionVersionID
    }

    /// A capture of the default reply and a choices item for the given version and left-out keys.
    public static func built(leftOut: Set<NutrientKey> = [], values: [[String: Any]]? = nil,
                             resolutionVersionID: ResolutionVersionID? = nil) throws -> Built {
        let digester = SHA256Digester(), encoder = FoundationCanonicalJSONEncoder()
        let inputs = inputs()
        let body = try requestBody(inputs)
        let bytes = try response(values: values ?? defaultValues())
        guard case let .success(parsed) = ConfirmNutrientResponseCheck.check(bytes, request: inputs, models: [model], provider: provider) else {
            throw FoodLedgerValidationError.invalidProvenance
        }
        let capture = ConfirmNutrientCapture(
            model: model, provider: provider, endpoint: endpoint, generationID: parsed.usage.generationID, requestBody: body,
            response: String(decoding: bytes, as: UTF8.self), responseSHA256: try digester.sha256(bytes).value,
            rows: ConfirmNutrientResponseCheck.captureRows(parsed, request: inputs))
        let payload = try encoder.encode(capture)
        let captureEvidence = try CaptureEvidence(
            evidenceID: id(9001), kind: .labelText, capturedAt: capturedAt, locale: LedgerText("en_GB"),
            captureMethod: LedgerText(ConfirmEnrichmentVersions.nutrientCaptureMethod),
            captureMethodVersion: LedgerText(ConfirmEnrichmentVersions.nutrientCaptureMethodVersion),
            originalPayload: .text(LedgerText(String(decoding: payload, as: UTF8.self))), byteHash: digester.sha256(payload))
        let versionID = try resolutionVersionID ?? id(9100)
        let choices = ConfirmNutrientChoices(resolutionVersionID: versionID.rawValue, captureSHA256: captureEvidence.byteHash!.value,
                                             leftOut: leftOut, layerDropped: [], mergeParentDropped: [], mergeEnergyDropped: [])
        let choicesPayload = try encoder.encode(choices)
        let choicesEvidence = try CaptureEvidence(
            evidenceID: id(9002), kind: .labelText, capturedAt: capturedAt, locale: LedgerText("en_GB"),
            captureMethod: LedgerText(ConfirmEnrichmentVersions.choicesCaptureMethod),
            captureMethodVersion: LedgerText(ConfirmEnrichmentVersions.choicesMethodVersion),
            originalPayload: .text(LedgerText(String(decoding: choicesPayload, as: UTF8.self))), byteHash: digester.sha256(choicesPayload))
        return Built(capture: capture, captureEvidence: captureEvidence, choicesEvidence: choicesEvidence, resolutionVersionID: versionID)
    }

    /// The pinned provenance of a B value cited from `capture` (phase gate section 2.1).
    public static func provenance(_ capture: CaptureEvidence, key: NutrientKey) throws -> NutrientProvenance {
        let hash = capture.byteHash!
        return NutrientProvenance(
            sourceKind: .openRouterEstimate, sourceID: try ExternalIdentifier(OpenRouterEstimateProvenance.sourceID),
            sourceReleaseID: try ExternalIdentifier(OpenRouterEstimateProvenance.sourceReleaseID(captureHash: hash)),
            recordID: try ExternalIdentifier(OpenRouterEstimateProvenance.recordID(evidenceID: capture.evidenceID)),
            evidenceID: capture.evidenceID, capturedAt: capture.capturedAt, responseHash: hash,
            manifestReference: try LedgerText(OpenRouterEstimateProvenance.manifestReference(key)))
    }

    public static func value(_ amount: Double, key: NutrientKey, provenance: NutrientProvenance) throws -> NutrientValue {
        .augmented(try ExactNutrientValue(
            amount: amount, unit: key.canonicalUnit,
            sourceValue: .exact(try SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
            provenance: [provenance]))
    }

    /// A nutrient set with the given values and every other key unknown.
    public static func nutrients(_ values: [NutrientKey: NutrientValue]) throws -> NutrientSet {
        try NutrientSet(entries: NutrientKey.allCases.map { key in
            try NutrientEntry(key: key, value: values[key] ?? .unknown(.notDeclared))
        })
    }
}
