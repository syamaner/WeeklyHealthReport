import Foundation

// Evidence a Confirm enrichment suggestion is saved with (docs/confirm-enrichment-openrouter-v1.md
// CE1.4a and CE1.7; phase gate sections 2.2 to 2.4). Each payload is canonical JSON held inline in a
// `.labelText` `CaptureEvidence`, selected by `captureMethodVersion`. Decoding is strict: an unknown or
// missing key at any level is not a capture. Nullable keys are always written (as JSON null), so the
// key set is the same for every payload of a version.

/// The frozen versions and constants of Confirm enrichment v1.
public enum ConfirmEnrichmentVersions {
    public static let contract = "confirm-enrichment-openrouter-v1"
    public static let detailsRoute = "confirm-details-route-v1"
    public static let nutrientRoute = "confirm-nutrient-route-v1"
    public static let detailsPrompt = "confirm-details-prompt-v1"
    public static let nutrientPrompt = "confirm-nutrient-prompt-v1"
    public static let nutrientSchema = "confirm-nutrient-estimate-v1"

    public static let detailsCaptureMethodVersion = "confirm-details-capture-v1"
    public static let nutrientCaptureMethodVersion = OpenRouterEstimateProvenance.captureMethodVersion
    public static let choicesMethodVersion = "confirm-nutrient-choices-v1"
    /// The three method versions every other `.labelText` reader skips (phase gate section 2.4a).
    public static let methodVersions: Set<String> = [
        detailsCaptureMethodVersion, nutrientCaptureMethodVersion, choicesMethodVersion
    ]

    public static let detailsCaptureMethod = "Food details suggested by Jev"
    public static let nutrientCaptureMethod = "Values estimated through OpenRouter"
    public static let choicesCaptureMethod = "Estimated values left out by you"

    /// CE-D3: frozen; changed only by a new version.
    public static let detailsThreshold = "0.85"
    public static let detailsResponseByteLimit = 50_000
    public static let nutrientResponseByteLimit = 100_000

    /// The per-capture source release fields (phase gate section 2.1).
    public static let releaseLicence = "Model output; no licence applies"
    public static let releaseAttribution = "Estimated through OpenRouter"

    public static func isEnrichmentEvidence(_ evidence: CaptureEvidence) -> Bool {
        evidence.kind == .labelText && methodVersions.contains(evidence.captureMethodVersion.value)
    }
}

enum ConfirmEnrichmentStrictKeys {
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    static func require<Keys: CodingKey & CaseIterable>(_ keys: Keys.Type, in decoder: any Decoder) throws {
        let present = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
        guard Set(present) == Set(Keys.allCases.map(\.stringValue)), present.count == Keys.allCases.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected or missing keys"))
        }
    }
}

/// `confirm-details-capture-v1` (A): one Jev request and its answer, committed with the Log that uses it.
public struct ConfirmDetailsCapture: Codable, Equatable, Sendable {
    public struct Answer: Codable, Equatable, Sendable {
        public let fact: String
        public let choice: String
        public let confidence: Double

        enum CodingKeys: String, CodingKey, CaseIterable { case fact, choice, confidence }

        public init(fact: String, choice: String, confidence: Double) {
            self.fact = fact
            self.choice = choice
            self.confidence = confidence
        }

        public init(from decoder: any Decoder) throws {
            try ConfirmEnrichmentStrictKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fact = try c.decode(String.self, forKey: .fact)
            choice = try c.decode(String.self, forKey: .choice)
            confidence = try c.decode(Double.self, forKey: .confidence)
        }
    }

    public let schema: String
    public let contract: String
    public let route: String
    public let prompt: String
    public let model: String
    public let provider: String
    public let endpoint: String
    public let generationID: String?
    public let requestBody: String
    public let response: String
    public let responseSHA256: String
    public let answers: [Answer]
    public let threshold: String
    public let applied: [String]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, contract, route, prompt, model, provider, endpoint, response, answers, threshold, applied
        case generationID = "generation_id"
        case requestBody = "request_body"
        case responseSHA256 = "response_sha256"
    }

    public init(model: String, provider: String, endpoint: String, generationID: String?, requestBody: String,
                response: String, responseSHA256: String, answers: [Answer], applied: [String]) throws {
        guard response.utf8.count <= ConfirmEnrichmentVersions.detailsResponseByteLimit,
              Set(applied).count == applied.count, Set(applied).isSubset(of: answers.map(\.fact)),
              Set(answers.map(\.fact)).count == answers.count else { throw FoodLedgerValidationError.invalidProvenance }
        schema = ConfirmEnrichmentVersions.detailsCaptureMethodVersion
        contract = ConfirmEnrichmentVersions.contract
        route = ConfirmEnrichmentVersions.detailsRoute
        prompt = ConfirmEnrichmentVersions.detailsPrompt
        self.model = model
        self.provider = provider
        self.endpoint = endpoint
        self.generationID = generationID
        self.requestBody = requestBody
        self.response = response
        self.responseSHA256 = responseSHA256
        self.answers = answers.sorted { $0.fact < $1.fact }
        threshold = ConfirmEnrichmentVersions.detailsThreshold
        self.applied = applied.sorted()
    }

    public init(from decoder: any Decoder) throws {
        try ConfirmEnrichmentStrictKeys.require(CodingKeys.self, in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        contract = try c.decode(String.self, forKey: .contract)
        route = try c.decode(String.self, forKey: .route)
        prompt = try c.decode(String.self, forKey: .prompt)
        model = try c.decode(String.self, forKey: .model)
        provider = try c.decode(String.self, forKey: .provider)
        endpoint = try c.decode(String.self, forKey: .endpoint)
        generationID = try c.decode(String?.self, forKey: .generationID)
        requestBody = try c.decode(String.self, forKey: .requestBody)
        response = try c.decode(String.self, forKey: .response)
        responseSHA256 = try c.decode(String.self, forKey: .responseSHA256)
        answers = try c.decode([Answer].self, forKey: .answers)
        threshold = try c.decode(String.self, forKey: .threshold)
        applied = try c.decode([String].self, forKey: .applied)
        guard schema == ConfirmEnrichmentVersions.detailsCaptureMethodVersion,
              contract == ConfirmEnrichmentVersions.contract,
              route == ConfirmEnrichmentVersions.detailsRoute,
              prompt == ConfirmEnrichmentVersions.detailsPrompt,
              threshold == ConfirmEnrichmentVersions.detailsThreshold,
              response.utf8.count <= ConfirmEnrichmentVersions.detailsResponseByteLimit,
              (try? SHA256Digest(responseSHA256)) != nil,
              answers.map(\.fact) == answers.map(\.fact).sorted(), Set(answers.map(\.fact)).count == answers.count,
              applied == applied.sorted(), Set(applied).count == applied.count,
              Set(applied).isSubset(of: answers.map(\.fact)),
              answers.allSatisfy({ $0.confidence.isFinite && (0...1).contains($0.confidence) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a confirm-details-capture-v1 payload"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(contract, forKey: .contract)
        try c.encode(route, forKey: .route)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(model, forKey: .model)
        try c.encode(provider, forKey: .provider)
        try c.encode(endpoint, forKey: .endpoint)
        try c.encode(generationID, forKey: .generationID)
        try c.encode(requestBody, forKey: .requestBody)
        try c.encode(response, forKey: .response)
        try c.encode(responseSHA256, forKey: .responseSHA256)
        try c.encode(answers, forKey: .answers)
        try c.encode(threshold, forKey: .threshold)
        try c.encode(applied, forKey: .applied)
    }
}

/// `confirm-nutrient-capture-v1` (B): one chat model request and its answer, with every row's result.
public struct ConfirmNutrientCapture: Codable, Equatable, Sendable {
    public struct Row: Codable, Equatable, Sendable {
        public let nutrient: String
        /// The number exactly as received, as text.
        public let value: String
        public let unit: String
        public let result: String

        enum CodingKeys: String, CodingKey, CaseIterable { case nutrient, value, unit, result }

        public init(nutrient: String, value: String, unit: String, result: ConfirmNutrientRowResult) {
            self.nutrient = nutrient
            self.value = value
            self.unit = unit
            self.result = result.rawValue
        }

        public init(from decoder: any Decoder) throws {
            try ConfirmEnrichmentStrictKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nutrient = try c.decode(String.self, forKey: .nutrient)
            value = try c.decode(String.self, forKey: .value)
            unit = try c.decode(String.self, forKey: .unit)
            result = try c.decode(String.self, forKey: .result)
            guard ConfirmNutrientRowResult(rawValue: result) != nil else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown row result"))
            }
        }
    }

    public let schema: String
    public let contract: String
    public let route: String
    public let prompt: String
    public let model: String
    public let provider: String
    public let endpoint: String
    public let generationID: String?
    public let requestBody: String
    public let response: String
    public let responseSHA256: String
    public let rows: [Row]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, contract, route, prompt, model, provider, endpoint, response, rows
        case generationID = "generation_id"
        case requestBody = "request_body"
        case responseSHA256 = "response_sha256"
    }

    public init(model: String, provider: String, endpoint: String, generationID: String?, requestBody: String,
                response: String, responseSHA256: String, rows: [Row]) throws {
        guard response.utf8.count <= ConfirmEnrichmentVersions.nutrientResponseByteLimit else {
            throw FoodLedgerValidationError.invalidProvenance
        }
        schema = ConfirmEnrichmentVersions.nutrientCaptureMethodVersion
        contract = ConfirmEnrichmentVersions.contract
        route = ConfirmEnrichmentVersions.nutrientRoute
        prompt = ConfirmEnrichmentVersions.nutrientPrompt
        self.model = model
        self.provider = provider
        self.endpoint = endpoint
        self.generationID = generationID
        self.requestBody = requestBody
        self.response = response
        self.responseSHA256 = responseSHA256
        self.rows = rows
    }

    public init(from decoder: any Decoder) throws {
        try ConfirmEnrichmentStrictKeys.require(CodingKeys.self, in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        contract = try c.decode(String.self, forKey: .contract)
        route = try c.decode(String.self, forKey: .route)
        prompt = try c.decode(String.self, forKey: .prompt)
        model = try c.decode(String.self, forKey: .model)
        provider = try c.decode(String.self, forKey: .provider)
        endpoint = try c.decode(String.self, forKey: .endpoint)
        generationID = try c.decode(String?.self, forKey: .generationID)
        requestBody = try c.decode(String.self, forKey: .requestBody)
        response = try c.decode(String.self, forKey: .response)
        responseSHA256 = try c.decode(String.self, forKey: .responseSHA256)
        rows = try c.decode([Row].self, forKey: .rows)
        guard schema == ConfirmEnrichmentVersions.nutrientCaptureMethodVersion,
              contract == ConfirmEnrichmentVersions.contract,
              route == ConfirmEnrichmentVersions.nutrientRoute,
              prompt == ConfirmEnrichmentVersions.nutrientPrompt,
              response.utf8.count <= ConfirmEnrichmentVersions.nutrientResponseByteLimit,
              (try? SHA256Digest(responseSHA256)) != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a confirm-nutrient-capture-v1 payload"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(contract, forKey: .contract)
        try c.encode(route, forKey: .route)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(model, forKey: .model)
        try c.encode(provider, forKey: .provider)
        try c.encode(endpoint, forKey: .endpoint)
        try c.encode(generationID, forKey: .generationID)
        try c.encode(requestBody, forKey: .requestBody)
        try c.encode(response, forKey: .response)
        try c.encode(responseSHA256, forKey: .responseSHA256)
        try c.encode(rows, forKey: .rows)
    }

    /// The nutrient keys of rows the request-and-reply checks kept.
    public var keptKeys: Set<NutrientKey> {
        Set(rows.filter { $0.result == ConfirmNutrientRowResult.kept.rawValue }.compactMap { NutrientKey(rawValue: $0.nutrient) })
    }
}

/// `confirm-nutrient-choices-v1`: which B rows one saved resolution version keeps, nutrient keys only.
public struct ConfirmNutrientChoices: Codable, Equatable, Sendable {
    public let schema: String
    public let resolutionVersionID: String
    public let captureSHA256: String
    public let leftOut: [String]
    public let layerDropped: [String]
    public let mergeParentDropped: [String]
    public let mergeEnergyDropped: [String]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema
        case resolutionVersionID = "resolution_version_id"
        case captureSHA256 = "capture_sha256"
        case leftOut = "left_out"
        case layerDropped = "layer_dropped"
        case mergeParentDropped = "merge_parent_dropped"
        case mergeEnergyDropped = "merge_energy_dropped"
    }

    public init(resolutionVersionID: String, captureSHA256: String, leftOut: Set<NutrientKey>,
                layerDropped: Set<NutrientKey>, mergeParentDropped: Set<NutrientKey>, mergeEnergyDropped: Set<NutrientKey>) {
        schema = ConfirmEnrichmentVersions.choicesMethodVersion
        self.resolutionVersionID = resolutionVersionID
        self.captureSHA256 = captureSHA256
        self.leftOut = leftOut.map(\.rawValue).sorted()
        self.layerDropped = layerDropped.map(\.rawValue).sorted()
        self.mergeParentDropped = mergeParentDropped.map(\.rawValue).sorted()
        self.mergeEnergyDropped = mergeEnergyDropped.map(\.rawValue).sorted()
    }

    public init(from decoder: any Decoder) throws {
        try ConfirmEnrichmentStrictKeys.require(CodingKeys.self, in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        resolutionVersionID = try c.decode(String.self, forKey: .resolutionVersionID)
        captureSHA256 = try c.decode(String.self, forKey: .captureSHA256)
        leftOut = try c.decode([String].self, forKey: .leftOut)
        layerDropped = try c.decode([String].self, forKey: .layerDropped)
        mergeParentDropped = try c.decode([String].self, forKey: .mergeParentDropped)
        mergeEnergyDropped = try c.decode([String].self, forKey: .mergeEnergyDropped)
        let lists = [leftOut, layerDropped, mergeParentDropped, mergeEnergyDropped]
        guard schema == ConfirmEnrichmentVersions.choicesMethodVersion,
              (try? SHA256Digest(captureSHA256)) != nil,
              lists.allSatisfy({ $0 == $0.sorted() && Set($0).count == $0.count && $0.allSatisfy { NutrientKey(rawValue: $0) != nil } }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a confirm-nutrient-choices-v1 payload"))
        }
    }

    public var leftOutKeys: Set<NutrientKey> { Set(leftOut.compactMap(NutrientKey.init(rawValue:))) }
    public var layerDroppedKeys: Set<NutrientKey> { Set(layerDropped.compactMap(NutrientKey.init(rawValue:))) }
    public var mergeParentDroppedKeys: Set<NutrientKey> { Set(mergeParentDropped.compactMap(NutrientKey.init(rawValue:))) }
    public var mergeEnergyDroppedKeys: Set<NutrientKey> { Set(mergeEnergyDropped.compactMap(NutrientKey.init(rawValue:))) }
}

/// Typed readers: nil for evidence of any other method version, or a payload that does not decode.
public enum ConfirmEnrichmentEvidence {
    public static func details(_ evidence: CaptureEvidence) -> ConfirmDetailsCapture? {
        decode(evidence, version: ConfirmEnrichmentVersions.detailsCaptureMethodVersion)
    }

    public static func nutrients(_ evidence: CaptureEvidence) -> ConfirmNutrientCapture? {
        decode(evidence, version: ConfirmEnrichmentVersions.nutrientCaptureMethodVersion)
    }

    public static func choices(_ evidence: CaptureEvidence) -> ConfirmNutrientChoices? {
        decode(evidence, version: ConfirmEnrichmentVersions.choicesMethodVersion)
    }

    private static func decode<T: Decodable>(_ evidence: CaptureEvidence, version: String) -> T? {
        guard evidence.kind == .labelText, evidence.captureMethodVersion.value == version,
              case let .text(payload) = evidence.originalPayload else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(payload.value.utf8))
    }
}
