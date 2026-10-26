import FoodLedgerApplication
import Foundation

/// The one image request of the label photo route (docs/label-photo-ai-prefill-v1.md E1, E2, E5,
/// 17.5; contract tests 7, 21 and 23). The body is exactly: the route's model, one user message
/// holding the fixed instruction and the prepared JPEG as a data URI, the fixed strict wire schema,
/// the provider block pinned to the one endpoint, `max_tokens` 1,200, a reasoning limit of 500,
/// no streaming and the usage report. Nothing else: no name, brand, notes, food log, health data,
/// location, device or account identifier. The key travels only in the Authorization header, and
/// a body that contains it is refused.
public struct OpenRouterLabelPhotoRequest: Sendable {
    public static let endpointURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    public static let schemaName = "label_image_extraction_v1"
    public static let schemaDescription = "The nutrition table printed in the image, transcribed as printed."
    /// The resources and their pinned SHA-256 (the evaluation's frozen contract pins the same bytes).
    public static let instructionResource = "label-photo-instruction-v1.txt"
    public static let wireSchemaResource = "label-photo-wire-schema-v1.json"
    public static let instructionSHA256 = "1839bc16b275f6f92e9d1a9af1a50d3c4a03185dd06425d5f267286b5fffc3e2"
    public static let wireSchemaSHA256 = "7e9f9cf9d3f67dbbf1cac9b70d6163e7609e7da82447e67291291a37cbad0007"

    public enum BuildError: Error, Equatable, Sendable {
        case resourceMissing, resourceChanged, keyInBody
    }

    public let route: LabelPhotoRoute.Route
    let instruction: String
    /// The schema without `$comment`, as JSON bytes (kept as bytes so the type stays Sendable).
    let wireSchema: Data

    /// Loads the bundled instruction and schema, refusing either if its bytes are not the pinned ones.
    public init(route: LabelPhotoRoute.Route = LabelPhotoRoute.current, digester: any Digesting = SHA256Digester()) throws {
        guard let instructionData = Self.resource(Self.instructionResource), let schemaData = Self.resource(Self.wireSchemaResource) else {
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
        // `$comment` is documentation only and some providers reject it (the evaluation strips it too).
        self.wireSchema = try JSONSerialization.data(withJSONObject: Self.withoutComments(schema), options: [.sortedKeys])
    }

    static func resource(_ name: String) -> Data? {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let path = Bundle.module.path(forResource: parts[0], ofType: parts[1]) else { return nil }
        return FileManager.default.contents(atPath: path)
    }

    static func withoutComments(_ node: Any) -> Any {
        if let object = node as? [String: Any] {
            return object.filter { $0.key != "$comment" }.mapValues(withoutComments)
        }
        if let array = node as? [Any] { return array.map(withoutComments) }
        return node
    }

    /// The provider block (E5): `only` and `order` the one endpoint, no fallbacks, parameters
    /// required, data collection denied and zero data retention required.
    var providerBlock: [String: Any] {
        ["only": [route.endpoint], "order": [route.endpoint], "allow_fallbacks": false, "require_parameters": true,
         "data_collection": "deny", "zdr": true]
    }

    /// The exact request body, serialised with sorted keys so the bytes are reproducible.
    public func body(_ image: PreparedLabelImage) throws -> Data {
        let schema = try JSONSerialization.jsonObject(with: wireSchema)
        let dataURI = "data:" + LabelPhotoManifest.mediaType + ";base64," + image.bytes.base64EncodedString()
        let body: [String: Any] = [
            "model": route.model,
            "messages": [[
                "role": "user",
                "content": [["type": "text", "text": instruction], ["type": "image_url", "image_url": ["url": dataURI]]],
            ]],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": Self.schemaName, "description": Self.schemaDescription, "strict": true, "schema": schema],
            ],
            "provider": providerBlock,
            "max_tokens": LabelPhotoSpendPolicy.maxTokens,
            "reasoning": ["max_tokens": LabelPhotoSpendPolicy.reasoningLimit],
            "stream": false,
            "usage": ["include": true],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// The HTTP request: POST to the one destination, the key only in the Authorization header.
    public func httpRequest(_ image: PreparedLabelImage, key: String) throws -> LabelPhotoHTTPRequest {
        let body = try body(image)
        guard body.range(of: Data(key.utf8)) == nil else { throw BuildError.keyInBody }
        return LabelPhotoHTTPRequest(method: "POST", url: Self.endpointURL,
                                     headers: ["Authorization": "Bearer " + key, "Content-Type": "application/json"], body: body)
    }

    /// The manifest's request record for this route and the session's catalogue check.
    public func manifestRequest(catalogue: LabelPhotoManifest.CatalogueCheck) -> LabelPhotoManifest.Request {
        LabelPhotoManifest.Request(model: route.model, endpoint: route.endpoint, reasoningLimit: LabelPhotoSpendPolicy.reasoningLimit,
                                   maxOutputTokens: LabelPhotoSpendPolicy.maxTokens, instructionVersion: LabelPhotoManifest.instructionVersion,
                                   instructionSHA256: Self.instructionSHA256, wireSchemaVersion: LabelPhotoSource.wireSchemaVersion,
                                   wireSchemaSHA256: Self.wireSchemaSHA256, catalogueCheck: catalogue)
    }
}
