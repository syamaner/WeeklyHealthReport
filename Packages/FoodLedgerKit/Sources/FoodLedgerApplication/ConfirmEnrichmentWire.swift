import Foundation
import FoodLedgerDomain

// Confirm enrichment v1 request inputs and response checks (docs/confirm-enrichment-openrouter-v1.md
// CE1.4, CE1.5, CE1.6 rule 1 and section 7; phase gate section 3.2). The variable part of each request
// is one canonical JSON object of a closed type, held in one fixed place: System One's `state` value for
// A, the single user message's content for B. Verification and the reopen subject decode it from a
// capture's `request_body`, never the prose. The checks are pure: the same functions run on a live
// answer, a cache hit and a reopen. No URL, header or transport type is here.

enum ConfirmEnrichmentStrictObject {
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

/// The closed source token of a description (CE1 section 7).
public enum ConfirmEnrichmentSourceToken: String, Codable, Sendable, CaseIterable {
    case openFoodFacts = "open_food_facts"
    case yourFoodDatabase = "your_food_database"
    case compositionTable = "composition_table"
}

/// The six food details A may ask, each with exactly I1.1's closed choices. Fortified is never a choice.
public enum ConfirmDetailsFact: String, Codable, Sendable, CaseIterable {
    case preparation, bone, skin, drained
    case packingMedium = "packing_medium"
    case fortification

    public var choices: [String] {
        switch self {
        case .preparation: ["as_sold", "raw", "cooked", "unknown"]
        case .bone: ["with_bone", "boneless", "not_applicable", "unknown"]
        case .skin: ["skin_on", "skinless", "not_applicable", "unknown"]
        case .drained: ["drained", "undrained", "not_applicable", "unknown"]
        case .packingMedium: ["as sold", "not applicable", "water", "brine", "oil", "olive_oil", "sauce", "unknown"]
        case .fortification: ["unfortified", "unknown"]
        }
    }
}

/// The description fields sent (CE1 section 7). Nullable fields are always written as JSON null.
public struct ConfirmEnrichmentDescription: Codable, Equatable, Sendable {
    public let name: String
    public let brand: String?
    public let variant: String?
    public let category: String?
    public let productType: String?
    public let state: String?
    public let source: ConfirmEnrichmentSourceToken

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, brand, variant, category, state, source
        case productType = "product_type"
    }

    public init(name: String, brand: String?, variant: String?, category: String?, productType: String?,
                state: String?, source: ConfirmEnrichmentSourceToken) {
        self.name = name
        self.brand = brand
        self.variant = variant
        self.category = category
        self.productType = productType
        self.state = state
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        try ConfirmEnrichmentStrictObject.require(CodingKeys.self, in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        brand = try c.decode(String?.self, forKey: .brand)
        variant = try c.decode(String?.self, forKey: .variant)
        category = try c.decode(String?.self, forKey: .category)
        productType = try c.decode(String?.self, forKey: .productType)
        state = try c.decode(String?.self, forKey: .state)
        source = try c.decode(ConfirmEnrichmentSourceToken.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(brand, forKey: .brand)
        try c.encode(variant, forKey: .variant)
        try c.encode(category, forKey: .category)
        try c.encode(productType, forKey: .productType)
        try c.encode(state, forKey: .state)
        try c.encode(source, forKey: .source)
    }
}

/// A's variable part: the description, the details already known (I1.1 tokens) and the facts asked.
public struct ConfirmDetailsRequestInputs: Codable, Equatable, Sendable {
    public let description: ConfirmEnrichmentDescription
    public let knownDetails: [String: String]
    public let asked: [ConfirmDetailsFact]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case description, asked
        case knownDetails = "known_details"
    }

    public init(description: ConfirmEnrichmentDescription, knownDetails: [String: String], asked: [ConfirmDetailsFact]) {
        self.description = description
        self.knownDetails = knownDetails
        self.asked = asked.sorted { $0.rawValue < $1.rawValue }
    }

    public init(from decoder: any Decoder) throws {
        try ConfirmEnrichmentStrictObject.require(CodingKeys.self, in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = try c.decode(ConfirmEnrichmentDescription.self, forKey: .description)
        knownDetails = try c.decode([String: String].self, forKey: .knownDetails)
        asked = try c.decode([ConfirmDetailsFact].self, forKey: .asked)
        guard asked.map(\.rawValue) == asked.map(\.rawValue).sorted(), Set(asked).count == asked.count, !asked.isEmpty,
              Set(knownDetails.keys).isDisjoint(with: asked.map(\.rawValue)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid asked facts"))
        }
    }

    /// Decodes A's inputs from a stored request body: the `state` value of the System One body.
    public static func decode(requestBody: String) -> ConfirmDetailsRequestInputs? {
        guard let root = try? JSONSerialization.jsonObject(with: Data(requestBody.utf8)) as? [String: Any],
              let state = root["state"],
              let bytes = try? JSONSerialization.data(withJSONObject: state) else { return nil }
        return try? JSONDecoder().decode(ConfirmDetailsRequestInputs.self, from: bytes)
    }
}

/// B's variable part (CE1.5 and section 7).
public struct ConfirmNutrientRequestInputs: Codable, Equatable, Sendable {
    public struct Known: Codable, Equatable, Sendable {
        public let nutrient: String
        public let value: Double
        public let unit: String
        public let source: String

        enum CodingKeys: String, CodingKey, CaseIterable { case nutrient, value, unit, source }

        public init(nutrient: NutrientKey, value: Double, source: String) {
            self.nutrient = nutrient.rawValue
            self.value = value
            unit = nutrient.canonicalUnit.rawValue
            self.source = source
        }

        public init(from decoder: any Decoder) throws {
            try ConfirmEnrichmentStrictObject.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nutrient = try c.decode(String.self, forKey: .nutrient)
            value = try c.decode(Double.self, forKey: .value)
            unit = try c.decode(String.self, forKey: .unit)
            source = try c.decode(String.self, forKey: .source)
            guard let key = NutrientKey(rawValue: nutrient), key.canonicalUnit.rawValue == unit, value.isFinite, value >= 0,
                  ConfirmNutrientRequestInputs.sourcePhrases.contains(source) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid known value"))
            }
        }
    }

    public struct Eligible: Codable, Equatable, Sendable {
        public let nutrient: String
        public let unit: String

        enum CodingKeys: String, CodingKey, CaseIterable { case nutrient, unit }

        public init(_ key: NutrientKey) {
            nutrient = key.rawValue
            unit = key.canonicalUnit.rawValue
        }

        public init(from decoder: any Decoder) throws {
            try ConfirmEnrichmentStrictObject.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nutrient = try c.decode(String.self, forKey: .nutrient)
            unit = try c.decode(String.self, forKey: .unit)
            guard let key = NutrientKey(rawValue: nutrient), key.canonicalUnit.rawValue == unit else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid eligible key"))
            }
        }
    }

    /// The closed source phrases of a known value (CE1 section 7).
    public static let sourcePhrases: Set<String> = [
        "from the label", "from the product's Open Food Facts record", "from a food composition table",
        "from your food database", "estimated in your food database"
    ]
    /// Keys never requested in v1: no CE1 section 12 bar class and no reference intake (phase gate
    /// section 9 and section 11, point 6).
    public static let unmeasuredKeys: Set<NutrientKey> = [.cholesterol, .water, .caffeine]

    public let description: ConfirmEnrichmentDescription
    public let identity: [String: String]
    public let basis: ConfirmNutrientBasis
    public let known: [Known]
    public let eligible: [Eligible]

    enum CodingKeys: String, CodingKey, CaseIterable { case description, identity, basis, known, eligible }

    public init(description: ConfirmEnrichmentDescription, identity: [String: String], basis: ConfirmNutrientBasis,
                known: [Known], eligible: [NutrientKey]) {
        self.description = description
        self.identity = identity
        self.basis = basis
        self.known = known.sorted { $0.nutrient < $1.nutrient }
        self.eligible = eligible.map(\.rawValue).sorted().compactMap(NutrientKey.init(rawValue:)).map(Eligible.init)
    }

    public init(from decoder: any Decoder) throws {
        try ConfirmEnrichmentStrictObject.require(CodingKeys.self, in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = try c.decode(ConfirmEnrichmentDescription.self, forKey: .description)
        identity = try c.decode([String: String].self, forKey: .identity)
        basis = try c.decode(ConfirmNutrientBasis.self, forKey: .basis)
        known = try c.decode([Known].self, forKey: .known)
        eligible = try c.decode([Eligible].self, forKey: .eligible)
        let knownKeys = known.map(\.nutrient), eligibleKeys = eligible.map(\.nutrient)
        guard knownKeys == knownKeys.sorted(), Set(knownKeys).count == knownKeys.count,
              eligibleKeys == eligibleKeys.sorted(), Set(eligibleKeys).count == eligibleKeys.count, !eligibleKeys.isEmpty,
              Set(knownKeys).isDisjoint(with: eligibleKeys),
              eligible.allSatisfy({ !Self.unmeasuredKeys.contains(NutrientKey(rawValue: $0.nutrient)!) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid nutrient inputs"))
        }
    }

    public var eligibleKeys: Set<NutrientKey> { Set(eligible.compactMap { NutrientKey(rawValue: $0.nutrient) }) }
    public var knownAmounts: [NutrientKey: Double] {
        Dictionary(known.compactMap { k in NutrientKey(rawValue: k.nutrient).map { ($0, k.value) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Decodes B's inputs from a stored request body: the content of its single user message.
    public static func decode(requestBody: String) -> ConfirmNutrientRequestInputs? {
        guard let root = try? JSONSerialization.jsonObject(with: Data(requestBody.utf8)) as? [String: Any],
              let messages = root["messages"] as? [[String: Any]] else { return nil }
        let user = messages.filter { $0["role"] as? String == "user" }
        guard user.count == 1, let content = user[0]["content"] as? String else { return nil }
        return try? JSONDecoder().decode(ConfirmNutrientRequestInputs.self, from: Data(content.utf8))
    }
}

/// Why a response fails as a whole (CE1 section 6: nothing is shown, nothing is cached).
public enum ConfirmEnrichmentResponseFailure: Error, Equatable, Sendable {
    case tooLarge, notJSON, shape, refusal, notStopped, modelMismatch, providerMismatch, schemaMismatch, basisMismatch, answers
}

/// What OpenRouter reports beside the answer, read from the response bytes (phase gate section 4):
/// a value the body does not carry is nil.
public struct ConfirmEnrichmentUsage: Equatable, Sendable {
    public let generationID: String?
    /// Reported cost in US dollars, as received.
    public let cost: Decimal?
    public let promptTokens: Int?
}

/// The numbers of a reply rendered as text: an integral value without a fractional part, any other in
/// Swift's shortest round-trip form, so `Double(text)` always gives the same value back.
enum ConfirmEnrichmentNumberText {
    static func render(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }
}

enum ConfirmEnrichmentUsageParse {
    static func usage(_ root: [String: Any]) -> ConfirmEnrichmentUsage {
        let usage = root["usage"] as? [String: Any]
        let cost = (usage?["cost"] as? NSNumber).map { Decimal(string: $0.stringValue) ?? $0.decimalValue }
        let prompt = (usage?["prompt_tokens"] as? NSNumber)?.intValue
        return ConfirmEnrichmentUsage(generationID: root["id"] as? String, cost: cost, promptTokens: prompt)
    }

    static func isNumber(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }
}

/// CE1.6 rule 1 for B: at most 100,000 bytes; one choice, `finish_reason` `stop`, no tool calls or
/// refusal; strict schema; `schema` and `basis` equal to the request's; model and provider as requested.
public enum ConfirmNutrientResponseCheck {
    public struct Parsed: Equatable, Sendable {
        public let rows: [ConfirmNutrientRowCheck.ReceivedRow]
        public let usage: ConfirmEnrichmentUsage
    }

    public static func check(_ bytes: Data, request: ConfirmNutrientRequestInputs, models: Set<String>,
                             provider: String) -> Result<Parsed, ConfirmEnrichmentResponseFailure> {
        guard bytes.count <= ConfirmEnrichmentVersions.nutrientResponseByteLimit else { return .failure(.tooLarge) }
        guard let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return .failure(.notJSON) }
        guard let model = root["model"] as? String, models.contains(model) else { return .failure(.modelMismatch) }
        guard root["provider"] as? String == provider else { return .failure(.providerMismatch) }
        guard let choices = root["choices"] as? [[String: Any]], choices.count == 1,
              let message = choices[0]["message"] as? [String: Any] else { return .failure(.shape) }
        guard choices[0]["finish_reason"] as? String == "stop" else { return .failure(.notStopped) }
        if let refusal = message["refusal"], !(refusal is NSNull) { return .failure(.refusal) }
        if let tools = message["tool_calls"], !(tools is NSNull) { return .failure(.shape) }
        guard let content = message["content"] as? String,
              let answer = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any],
              Set(answer.keys) == ["schema", "basis", "values"],
              let values = answer["values"] as? [[String: Any]] else { return .failure(.shape) }
        guard answer["schema"] as? String == ConfirmEnrichmentVersions.nutrientSchema else { return .failure(.schemaMismatch) }
        guard answer["basis"] as? String == request.basis.rawValue else { return .failure(.basisMismatch) }
        var rows: [ConfirmNutrientRowCheck.ReceivedRow] = []
        for value in values {
            guard Set(value.keys) == ["nutrient", "value", "unit"],
                  let nutrient = value["nutrient"] as? String, let unit = value["unit"] as? String,
                  ConfirmEnrichmentUsageParse.isNumber(value["value"]),
                  let number = (value["value"] as? NSNumber)?.doubleValue else { return .failure(.shape) }
            rows.append(.init(nutrient: nutrient, value: ConfirmEnrichmentNumberText.render(number), unit: unit))
        }
        return .success(Parsed(rows: rows, usage: ConfirmEnrichmentUsageParse.usage(root)))
    }

    /// The capture rows of a parsed reply: CE1.6 rule 2 against the request.
    public static func captureRows(_ parsed: Parsed, request: ConfirmNutrientRequestInputs) -> [ConfirmNutrientCapture.Row] {
        let results = ConfirmNutrientRowCheck.results(rows: parsed.rows, eligible: request.eligibleKeys, basis: request.basis,
                                                      known: request.knownAmounts)
        return zip(parsed.rows, results).map { .init(nutrient: $0.nutrient, value: $0.value, unit: $0.unit, result: $1) }
    }
}

/// CE1.4 for A: provider and model as requested; `answers` holds exactly the asked keys; each answer is
/// a `choice` from that question's list with a finite `confidence` and `probabilities` from 0 to 1;
/// at most 50,000 bytes.
public enum ConfirmDetailsResponseCheck {
    public struct Parsed: Equatable, Sendable {
        public let answers: [ConfirmDetailsCapture.Answer]
        public let usage: ConfirmEnrichmentUsage
    }

    public static func check(_ bytes: Data, request: ConfirmDetailsRequestInputs, models: Set<String>,
                             provider: String) -> Result<Parsed, ConfirmEnrichmentResponseFailure> {
        guard bytes.count <= ConfirmEnrichmentVersions.detailsResponseByteLimit else { return .failure(.tooLarge) }
        guard let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return .failure(.notJSON) }
        guard let model = root["model"] as? String, models.contains(model) else { return .failure(.modelMismatch) }
        guard root["provider"] as? String == provider else { return .failure(.providerMismatch) }
        guard let answers = root["answers"] as? [String: Any],
              Set(answers.keys) == Set(request.asked.map(\.rawValue)) else { return .failure(.answers) }
        var parsed: [ConfirmDetailsCapture.Answer] = []
        for fact in request.asked {
            guard let answer = answers[fact.rawValue] as? [String: Any], answer["type"] as? String == "choice",
                  let choice = answer["value"] as? String, fact.choices.contains(choice),
                  ConfirmEnrichmentUsageParse.isNumber(answer["confidence"]),
                  let confidence = (answer["confidence"] as? NSNumber)?.doubleValue, confidence.isFinite, (0...1).contains(confidence),
                  let probabilities = answer["probabilities"] as? [String: Any],
                  probabilities.values.allSatisfy({ value in
                      guard ConfirmEnrichmentUsageParse.isNumber(value), let p = (value as? NSNumber)?.doubleValue else { return false }
                      return p.isFinite && (0...1).contains(p)
                  }) else { return .failure(.answers) }
            parsed.append(.init(fact: fact.rawValue, choice: choice, confidence: confidence))
        }
        return .success(Parsed(answers: parsed, usage: ConfirmEnrichmentUsageParse.usage(root)))
    }

    /// The facts an answer pre-fills: not `unknown`, at or above the frozen threshold (CE-D3).
    public static func applied(_ answers: [ConfirmDetailsCapture.Answer]) -> [String] {
        let threshold = Double(ConfirmEnrichmentVersions.detailsThreshold)!
        return answers.filter { $0.choice != "unknown" && $0.confidence >= threshold }.map(\.fact).sorted()
    }
}
