import FoodLedgerApplication
import Foundation

/// The one text request of the pasted label AI text route (docs/pasted-label-ai-text-v1.md 4.2,
/// 4.9, 5.2 item 1, T2, T3, T9; contract test 10). The body is exactly: the route's model, a system
/// message holding the fixed instruction (`prompt-v1`, pinned by SHA-256), one user message holding
/// the pasted text exactly as given, the fixed strict wire schema (pinned by SHA-256), the provider
/// block pinned to the one endpoint (`only` and `order`, `allow_fallbacks: false`,
/// `require_parameters: true`, `data_collection: "deny"`, `zdr: true`), `max_tokens`, the reasoning
/// limit, no streaming, no tools and the usage report. Nothing else: no name, brand, notes, food
/// log, health data, location, device or account identifier. The text is at most 8,000 Unicode
/// scalars, and the key travels only in the Authorization header; a body that contains it is refused.
public struct OpenRouterPastedLabelAITextRequest: Sendable {
    public static let endpointURL = OpenRouterLabelPhotoRequest.endpointURL
    public static let schemaName = "pasted_label_text_extraction_v1"
    public static let schemaDescription = "The nutrition table in the pasted text, transcribed as printed."
    public static let instructionVersion = "pasted-label-ai-text-instruction-v1"
    public static let promptVersion = "prompt-v1"
    public static let instructionResource = "pasted-label-ai-text-instruction-v1.txt"
    public static let wireSchemaResource = "pasted-label-ai-text-wire-schema-v1.json"
    public static let instructionSHA256 = "0773427c91e061638c85a588226f1ffaab0708901dda5d2b64456954a869cba6"
    public static let wireSchemaSHA256 = "faab102e4f40f82c651e41b06e2cd2973a1cf63e2ffbb2f2043d93790e7c26dd"
    public static let maximumTextScalars = PastedLabelManifest.maximumTextScalars

    public enum BuildError: Error, Equatable, Sendable {
        case resourceMissing, resourceChanged, keyInBody, textEmpty, textTooLong, notATextRoute
    }

    public let route: PastedLabelAITextRoute.Route
    let instruction: String
    /// The schema without `$comment`, as JSON bytes.
    let wireSchema: Data

    /// Loads the bundled instruction and schema, refusing either if its bytes are not the pinned
    /// ones, and refusing a route that is not one of the text route's own.
    public init(route: PastedLabelAITextRoute.Route, digester: any Digesting = SHA256Digester()) throws {
        guard PastedLabelAITextRoute.isAdmitted(route) else { throw BuildError.notATextRoute }
        guard let instructionData = OpenRouterLabelPhotoRequest.resource(Self.instructionResource),
              let schemaData = OpenRouterLabelPhotoRequest.resource(Self.wireSchemaResource) else {
            throw BuildError.resourceMissing
        }
        guard try digester.sha256(instructionData).value == Self.instructionSHA256,
              try digester.sha256(schemaData).value == Self.wireSchemaSHA256,
              let instruction = String(data: instructionData, encoding: .utf8),
              let schema = try? JSONSerialization.jsonObject(with: schemaData) else {
            throw BuildError.resourceChanged
        }
        self.route = route
        self.instruction = instruction
        self.wireSchema = try JSONSerialization.data(withJSONObject: OpenRouterLabelPhotoRequest.withoutComments(schema), options: [.sortedKeys])
    }

    var providerBlock: [String: Any] {
        ["only": [route.endpoint], "order": [route.endpoint], "allow_fallbacks": false, "require_parameters": true,
         "data_collection": "deny", "zdr": true]
    }

    /// Refuses an empty or all-whitespace text and one over 8,000 scalars (T9).
    public static func admit(_ text: String) throws {
        if text.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) { throw BuildError.textEmpty }
        if text.unicodeScalars.count > maximumTextScalars { throw BuildError.textTooLong }
    }

    /// The exact request body, serialised with sorted keys so the bytes are reproducible.
    public func body(_ text: String) throws -> Data {
        try Self.admit(text)
        let schema = try JSONSerialization.jsonObject(with: wireSchema)
        let body: [String: Any] = [
            "model": route.model,
            "messages": [["role": "system", "content": instruction], ["role": "user", "content": text]],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": Self.schemaName, "description": Self.schemaDescription, "strict": true, "schema": schema],
            ],
            "provider": providerBlock,
            "max_tokens": route.maxOutputTokens,
            "reasoning": ["max_tokens": route.reasoningLimit],
            "stream": false,
            "usage": ["include": true],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// The HTTP request: POST to the one destination, the key only in the Authorization header.
    public func httpRequest(_ text: String, key: String) throws -> LabelPhotoHTTPRequest {
        let body = try body(text)
        guard body.range(of: Data(key.utf8)) == nil else { throw BuildError.keyInBody }
        return LabelPhotoHTTPRequest(method: "POST", url: Self.endpointURL,
                                     headers: ["Authorization": "Bearer " + key, "Content-Type": "application/json"], body: body)
    }
}
