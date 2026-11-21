import Foundation
import FoodLedgerDomain

/// Confirm enrichment v1 eligibility, subjects, the on-device deny gate and the typed request bodies
/// (docs/confirm-enrichment-openrouter-v1.md CE1.1, CE1.4, CE1.5 and section 7; phase gate sections 3.1
/// and 3.2). Pure: the route values, the Your food database fields and the hashing come in. The request
/// body is one pure function of the Confirm inputs a subject hashes, so a capture built from a cache hit
/// rebuilds exactly the body a live answer was sent with.
public enum ConfirmEnrichmentPolicy {
    /// The route a candidate takes on Confirm (CE1 section 2). Nil for every route outside v1: web
    /// lookup, pasted label, label photo, Your foods rows, plain water and anything unclassified.
    public enum SourceRoute: Equatable, Sendable {
        case openFoodFacts
        case yourFoodDatabase
        /// A bundled table row; only CoFID's variant is the source's own text.
        case compositionTable(sendsVariant: Bool)

        var token: ConfirmEnrichmentSourceToken {
            switch self {
            case .openFoodFacts: .openFoodFacts
            case .yourFoodDatabase: .yourFoodDatabase
            case .compositionTable: .compositionTable
            }
        }
    }

    public static func sourceRoute(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> SourceRoute? {
        let source = candidate.candidate
        guard !source.recordID.value.hasPrefix(OpenFoodFactsEstimateSource.libraryRecordPrefix),
              !LabelSourceAdmission.applies(input, candidate: candidate),
              !FoodReviewedWebProposalPolicy.applies(input, candidate: candidate),
              let release = input.sourceReleases.first(where: { $0.sourceReleaseID == source.sourceReleaseID }) else { return nil }
        if release.sourceID.value == PersonalFoodDatabaseRelease.sourceID { return .yourFoodDatabase }
        if release.sourceID.value == OpenFoodFactsEstimateSource.sourceID, OpenFoodFactsEstimateSource.isProductCandidate(source),
           input.evidence.contains(where: { source.evidenceIDs.contains($0.evidenceID) && OpenFoodFactsEstimateSource.isProductEvidence($0) }) {
            return .openFoodFacts
        }
        guard FoodConfirmationPolicy.isGenericEstimate(input, candidate: candidate) else { return nil }
        switch FoodSearchResultSummary.family(release.sourceID.value, recordID: source.recordID.value) {
        case .ukReference: return .compositionTable(sendsVariant: true)
        case .usReference, .taiwanReference, .frenchReference: return .compositionTable(sendsVariant: false)
        default: return nil
        }
    }

    // MARK: Food details as I1.1 tokens

    static let detailFacts: [ConfirmDetailsFact] = [.preparation, .bone, .skin, .drained, .packingMedium, .fortification]

    static func contradiction(_ fact: ConfirmDetailsFact) -> IdentityContradiction {
        switch fact {
        case .preparation: .preparation
        case .bone: .bone
        case .skin: .skin
        case .drained: .drained
        case .packingMedium: .packingMedium
        case .fortification: .fortification
        }
    }

    /// The fact's I1.1 token on `identity`, or nil when it is unknown or has no I1.1 token.
    /// Fortified is a known fact and is described as such, but is never a choice A may answer.
    static func token(_ fact: ConfirmDetailsFact, of identity: DecisiveIdentity) -> String? {
        switch fact {
        case .preparation:
            switch identity.preparation.kind {
            case .asSold: "as_sold"
            case .raw: "raw"
            case .cooked: "cooked"
            case .reheated, .named, .unknown: nil
            }
        case .bone: identity.bone == .unknown ? nil : identity.bone.rawValue
        case .skin: identity.skin == .unknown ? nil : identity.skin.rawValue
        case .drained: identity.drained == .unknown ? nil : identity.drained.rawValue
        case .packingMedium:
            if case let .named(name) = identity.packingMedium, fact.choices.contains(name.value), name.value != "unknown" { name.value } else { nil }
        case .fortification:
            switch identity.fortification {
            case .fortified: "fortified"
            case .unfortified: "unfortified"
            case .unknown: nil
            }
        }
    }

    static func isUnknown(_ fact: ConfirmDetailsFact, in identity: DecisiveIdentity) -> Bool {
        switch fact {
        case .preparation: identity.preparation.kind == .unknown
        case .bone: identity.bone == .unknown
        case .skin: identity.skin == .unknown
        case .drained: identity.drained == .unknown
        case .packingMedium: identity.packingMedium == .unknown
        case .fortification: identity.fortification == .unknown
        }
    }

    /// The known details of `identity` as I1.1 tokens.
    public static func knownDetails(_ identity: DecisiveIdentity) -> [String: String] {
        var result: [String: String] = [:]
        for fact in detailFacts { if let value = token(fact, of: identity) { result[fact.rawValue] = value } }
        return result
    }

    /// The identity with each suggested fact applied where it is unknown, never elsewhere. Fortified is
    /// not a choice, so it can never be applied.
    public static func applying(_ facts: [ConfirmDetailsFact: String], to identity: DecisiveIdentity) throws -> DecisiveIdentity {
        func pick<T>(_ fact: ConfirmDetailsFact, _ current: T, _ map: (String) -> T?) -> T {
            guard isUnknown(fact, in: identity), let value = facts[fact], let mapped = map(value) else { return current }
            return mapped
        }
        let preparation: PreparationState = pick(.preparation, identity.preparation) { value in
            switch value {
            case "as_sold": try? PreparationState(kind: .asSold)
            case "raw": try? PreparationState(kind: .raw)
            case "cooked": try? PreparationState(kind: .cooked)
            default: nil
            }
        }
        let packing: PackingMediumState = pick(.packingMedium, identity.packingMedium) { value in
            value == "unknown" ? nil : (try? LedgerText(value)).map(PackingMediumState.named)
        }
        let fortification: FortificationState = pick(.fortification, identity.fortification) { $0 == "unfortified" ? .unfortified : nil }
        return try DecisiveIdentity(
            preparation: preparation,
            bone: pick(.bone, identity.bone) { BoneState(rawValue: $0).flatMap { $0 == .unknown ? nil : $0 } },
            skin: pick(.skin, identity.skin) { SkinState(rawValue: $0).flatMap { $0 == .unknown ? nil : $0 } },
            drained: pick(.drained, identity.drained) { DrainedState(rawValue: $0).flatMap { $0 == .unknown ? nil : $0 } },
            packingMedium: packing, fortification: fortification,
            declaredFortificants: identity.declaredFortificants, servingBasis: identity.servingBasis)
    }

    // MARK: Description and the deny gate

    /// The description of section 7, from the bound candidate's source fields only (never correction
    /// text) and, for Your food database, the entry's own fields.
    public static func description(_ route: SourceRoute, candidate: PopulatedFoodCandidate,
                                   database: PersonalFoodDescriptionFields?) -> ConfirmEnrichmentDescription {
        let variant: String?
        if case .compositionTable(sendsVariant: true) = route { variant = candidate.variant?.value } else { variant = nil }
        return ConfirmEnrichmentDescription(
            name: candidate.name.value, brand: candidate.brand?.value, variant: variant,
            category: route == .yourFoodDatabase ? database?.category : nil,
            productType: route == .yourFoodDatabase ? database?.productType : nil,
            state: route == .yourFoodDatabase ? database?.state : nil, source: route.token)
    }

    static let denyPatterns: [String] = [
        #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        #"(\+|00)\s?[0-9][0-9 ()-]{7,}[0-9]"#,
        #"\b0[0-9]{2,4}[ -]?[0-9]{3,4}[ -]?[0-9]{3,4}\b"#,
        #"\b[A-Z]{1,2}[0-9][A-Z0-9]?\s?[0-9][A-Z]{2}\b"#,
        #"[0-9]{8,}"#,
        #"[£$€¥]\s?[0-9]"#,
        #"\b[0-9]+(\.[0-9]{1,2})?\s?(GBP|USD|EUR|NTD|TWD|pence|p)\b"#,
        #"(?i)\b(order|invoice|receipt|payment|paid|card|account|iban|sort code|transaction|refund)\b"#,
    ]

    /// The on-device gate (CE1 section 7): a description holding an email address, a phone number, a UK
    /// postcode, a run of 8 or more digits, a currency amount, or order, payment or account words is
    /// not sent. A backstop, not a guarantee.
    public static func passesDenyGate(_ description: ConfirmEnrichmentDescription) -> Bool {
        let texts = [description.name, description.brand, description.variant, description.category,
                     description.productType, description.state].compactMap { $0 }
        return !texts.contains { text in denyPatterns.contains { text.range(of: $0, options: .regularExpression) != nil } }
    }

    // MARK: Which Confirm may ask

    /// Where a Confirm came from: only a fresh Confirm may send; one opened by re-log or quick add reads
    /// the cache only (CE1.7a), and a reopened log never runs either part.
    public enum Origin: Equatable, Sendable {
        case fresh
        case relogOrQuickAdd
    }

    /// The A fact questions for this state, or nil when A does not run (CE1.1 rule 1, CE1.4, CE-D5).
    public static func detailsQuestions(_ state: FoodConfirmationState, route: SourceRoute,
                                        database: PersonalFoodDescriptionFields?) -> [ConfirmDetailsFact]? {
        guard state.reopened == nil, state.correction == nil, state.decisions.isEmpty,
              route == .openFoodFacts || (route == .yourFoodDatabase && database?.hasCatalogueFacts == false),
              FoodLogPolicy.pendingDifferences(state).isEmpty else { return nil }
        let missing = Set(FoodConfirmationPolicy.unresolvedIdentity(state.selectedCandidate.candidate.identity,
                                                                     allowingEstimate: state.isGenericEstimate))
        let asked = detailFacts.filter { missing.contains(contradiction($0)) }
        return asked.isEmpty ? nil : asked
    }

    /// B's basis, when the bound candidate's is one B is offered for.
    public static func nutrientBasis(_ candidate: PopulatedFoodCandidate) -> ConfirmNutrientBasis? {
        basis(candidate.candidate.identity.servingBasis)
    }

    public static func basis(_ basis: ResolutionBasis) -> ConfirmNutrientBasis? {
        switch basis {
        case .per100Grams: .per100Grams
        case .per100Millilitres: .per100Millilitres
        default: nil
        }
    }

    /// Whether a value is one B may ask for (assistant estimates section 5.1): unknown, resolved, not
    /// declared or no compatible source; and not a key v1 never measures.
    static func isEligibleUnknown(_ entry: NutrientEntry) -> Bool {
        guard entry.status == .resolved, entry.conflictCandidates.isEmpty,
              !ConfirmNutrientRequestInputs.unmeasuredKeys.contains(entry.key) else { return false }
        if case .unknown(.notDeclared) = entry.value { return true }
        if case .unknown(.noCompatibleSource) = entry.value { return true }
        return false
    }

    /// The source phrase of a known value (CE1 section 7), or nil when the value is not sent.
    static func sourcePhrase(_ value: NutrientValue, route: SourceRoute) -> String? {
        guard let first = value.provenance.first else { return nil }
        switch first.sourceKind {
        case .approvedEstimate: return "estimated in your food database"
        case .genericCompositionDataset: return "from a food composition table"
        case .userVerifiedPanel: return "from the label"
        case .manualDeclaration: return route == .yourFoodDatabase ? "from your food database" : "from the label"
        case .exactProductDataset:
            return route == .yourFoodDatabase ? "from your food database" : "from the product's Open Food Facts record"
        case .recipeReconstruction, .reviewedWebProposal, .appReferenceDefinition, .openRouterEstimate: return nil
        }
    }

    /// The B inputs for this state, or nil when B does not run: B's route and basis, no nutrient
    /// correction, at least one eligible key, the chosen label layer's keys left out.
    public static func nutrientInputs(_ state: FoodConfirmationState, route: SourceRoute, description: ConfirmEnrichmentDescription,
                                      identity: DecisiveIdentity, labelLayerKeys: Set<NutrientKey>) -> ConfirmNutrientRequestInputs? {
        let candidate = state.selectedCandidate
        guard state.reopened == nil, let basis = nutrientBasis(candidate),
              state.correction.map({ $0.nutrients == candidate.candidate.nutrients }) ?? true else { return nil }
        let entries = candidate.candidate.nutrients.entries
        let eligible = entries.filter { isEligibleUnknown($0) && !labelLayerKeys.contains($0.key) }.map(\.key)
        guard !eligible.isEmpty else { return nil }
        let known: [ConfirmNutrientRequestInputs.Known] = entries.compactMap { entry in
            guard entry.status == .resolved, let phrase = sourcePhrase(entry.value, route: route) else { return nil }
            switch entry.value {
            case let .measured(exact), let .augmented(exact): return try? .init(nutrient: entry.key, value: exact.amount, source: phrase)
            case .bounded, .unknown: return nil
            }
        }
        return try? ConfirmNutrientRequestInputs(description: description, identity: knownDetails(identity), basis: basis,
                                                 known: known, eligible: eligible)
    }

    // MARK: Fixed texts (prompt versions)

    /// `confirm-details-prompt-v1`.
    public static let detailsInstruction = """
        You are given one food description and questions about its food details. For each question, \
        choose exactly one of the listed choices for the food exactly as described. Choose unknown \
        whenever the description does not settle the fact. Never contradict the details already known. \
        Give a confidence from 0 to 1 and probabilities for the choices.
        """

    /// `confirm-nutrient-prompt-v1`. No health, target or diet wording.
    public static let nutrientInstruction = """
        You estimate nutrient values for one food. The user message is a JSON object describing the food: \
        its description, its food details, the nutrition basis, the values already known with their \
        sources, and the nutrients wanted with their units. Answer for the food exactly as described, on \
        the stated basis only, never converting. Use exactly the unit given for each nutrient. Leave out \
        any nutrient you cannot estimate; never write 0 for an unknown value. Never change or repeat a \
        known value. Answer only with the JSON the schema allows.
        """

    // MARK: Request bodies

    /// A built request: the canonical variable part, the exact body bytes and the subject hash.
    public struct DetailsRequest: Equatable, Sendable {
        public let inputs: ConfirmDetailsRequestInputs
        public let body: Data
        public let subjectSHA256: String
    }

    public struct NutrientRequest: Equatable, Sendable {
        public let inputs: ConfirmNutrientRequestInputs
        public let body: Data
        public let subjectSHA256: String
    }

    public enum BuildFailure: Error, Equatable, Sendable {
        /// The description failed the on-device gate.
        case denied
        /// The body is longer in UTF-8 bytes than its route's prompt ceiling in tokens.
        case overPromptCeiling
    }

    struct ProviderBlock: Encodable, Sendable {
        let only: [String]
        let order: [String]
        let allowFallbacks = false
        let requireParameters = true
        let dataCollection = "deny"
        let zdr = true

        enum CodingKeys: String, CodingKey {
            case only, order, zdr
            case allowFallbacks = "allow_fallbacks"
            case requireParameters = "require_parameters"
            case dataCollection = "data_collection"
        }

        init(_ route: ConfirmEnrichmentRoute) { only = [route.providerEndpoint]; order = [route.providerEndpoint] }
    }

    struct DetailsQuestion: Encodable, Sendable {
        let key: String
        let type = "choice"
        let choices: [String]
    }

    struct DetailsBody: Encodable, Sendable {
        let model: String
        let provider: ProviderBlock
        let instructions: String
        let state: ConfirmDetailsRequestInputs
        let questions: [DetailsQuestion]
        let maxTokens: Int?

        enum CodingKeys: String, CodingKey {
            case model, provider, instructions, state, questions
            case maxTokens = "max_tokens"
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(model, forKey: .model)
            try c.encode(provider, forKey: .provider)
            try c.encode(instructions, forKey: .instructions)
            try c.encode(state, forKey: .state)
            try c.encode(questions, forKey: .questions)
            try c.encodeIfPresent(maxTokens, forKey: .maxTokens)
        }
    }

    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }

    /// A closed JSON value for the strict output schema.
    indirect enum Schema: Encodable, Sendable {
        case object([String: Schema])
        case array([Schema])
        case string(String)
        case bool(Bool)

        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case let .object(value): try c.encode(value)
            case let .array(value): try c.encode(value)
            case let .string(value): try c.encode(value)
            case let .bool(value): try c.encode(value)
            }
        }
    }

    struct NutrientBody: Encodable, Sendable {
        let model: String
        let provider: ProviderBlock
        let messages: [Message]
        let responseFormat: Schema
        let maxTokens: Int
        let reasoning: [String: Int]
        let stream = false
        let usage = ["include": true]

        enum CodingKeys: String, CodingKey {
            case model, provider, messages, reasoning, stream, usage
            case responseFormat = "response_format"
            case maxTokens = "max_tokens"
        }
    }

    /// The strict `confirm-nutrient-estimate-v1` schema for one request: `nutrient` is an enum of
    /// exactly the eligible keys and `unit` of their canonical units.
    static func nutrientSchema(_ inputs: ConfirmNutrientRequestInputs) -> Schema {
        let keys = inputs.eligible.map(\.nutrient)
        let units = Array(Set(inputs.eligible.map(\.unit))).sorted()
        let row: Schema = .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "required": .array(["nutrient", "value", "unit"].map(Schema.string)),
            "properties": .object([
                "nutrient": .object(["type": .string("string"), "enum": .array(keys.map(Schema.string))]),
                "value": .object(["type": .string("number")]),
                "unit": .object(["type": .string("string"), "enum": .array(units.map(Schema.string))]),
            ]),
        ])
        let schema: Schema = .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "required": .array(["schema", "basis", "values"].map(Schema.string)),
            "properties": .object([
                "schema": .object(["type": .string("string"), "enum": .array([.string(ConfirmEnrichmentVersions.nutrientSchema)])]),
                "basis": .object(["type": .string("string"), "enum": .array([.string(inputs.basis.rawValue)])]),
                "values": .object(["type": .string("array"), "items": row]),
            ]),
        ])
        return .object(["type": .string("json_schema"), "json_schema": .object([
            "name": .string(ConfirmEnrichmentVersions.nutrientSchema), "strict": .bool(true), "schema": schema,
        ])])
    }

    struct DetailsSubject: Encodable, Sendable {
        let contract = ConfirmEnrichmentVersions.contract
        let route: String
        let prompt = ConfirmEnrichmentVersions.detailsPrompt
        let inputs: ConfirmDetailsRequestInputs
    }

    struct NutrientSubject: Encodable, Sendable {
        let contract = ConfirmEnrichmentVersions.contract
        let route: String
        let prompt = ConfirmEnrichmentVersions.nutrientPrompt
        let description: ConfirmEnrichmentDescription
        let identity: [String: String]
        let basis: ConfirmNutrientBasis
        let eligible: [String]
        let knownSHA256: String

        enum CodingKeys: String, CodingKey {
            case contract, route, prompt, description, identity, basis, eligible
            case knownSHA256 = "known_sha256"
        }
    }

    /// A's request: the body bytes and the subject (versions, description, sorted asked keys, known details).
    public static func detailsRequest(_ inputs: ConfirmDetailsRequestInputs, route: ConfirmEnrichmentRoute,
                                      encoder: any CanonicalEncoding, digester: any Digesting) throws -> DetailsRequest {
        guard passesDenyGate(inputs.description) else { throw BuildFailure.denied }
        let body = try encoder.encode(DetailsBody(
            model: route.model, provider: ProviderBlock(route), instructions: detailsInstruction, state: inputs,
            questions: inputs.asked.map { DetailsQuestion(key: $0.rawValue, choices: $0.choices) },
            maxTokens: route.sendsMaxTokens ? route.completionCeilingTokens : nil))
        guard body.count <= route.promptCeilingTokens else { throw BuildFailure.overPromptCeiling }
        let subject = try digester.sha256(encoder.encode(DetailsSubject(route: route.version, inputs: inputs))).value
        return DetailsRequest(inputs: inputs, body: body, subjectSHA256: subject)
    }

    /// B's request: the body bytes and the subject (versions, description, identity, basis, sorted
    /// eligible keys and the SHA-256 of the canonical known values).
    public static func nutrientRequest(_ inputs: ConfirmNutrientRequestInputs, route: ConfirmEnrichmentRoute,
                                       encoder: any CanonicalEncoding, digester: any Digesting) throws -> NutrientRequest {
        guard passesDenyGate(inputs.description) else { throw BuildFailure.denied }
        let content = String(decoding: try encoder.encode(inputs), as: UTF8.self)
        let body = try encoder.encode(NutrientBody(
            model: route.model, provider: ProviderBlock(route),
            messages: [Message(role: "system", content: nutrientInstruction), Message(role: "user", content: content)],
            responseFormat: nutrientSchema(inputs), maxTokens: route.completionCeilingTokens,
            reasoning: ["max_tokens": route.reasoningLimitTokens]))
        guard body.count <= route.promptCeilingTokens else { throw BuildFailure.overPromptCeiling }
        let known = try digester.sha256(encoder.encode(inputs.known)).value
        let subject = try digester.sha256(encoder.encode(NutrientSubject(
            route: route.version, description: inputs.description, identity: inputs.identity, basis: inputs.basis,
            eligible: inputs.eligible.map(\.nutrient), knownSHA256: known))).value
        return NutrientRequest(inputs: inputs, body: body, subjectSHA256: subject)
    }

    /// The field names a request sends, for Developer tools (never their values).
    public static func sentFieldNames(_ description: ConfirmEnrichmentDescription) -> [String] {
        var names = ["name", "source"]
        if description.brand != nil { names.append("brand") }
        if description.variant != nil { names.append("variant") }
        if description.category != nil { names.append("category") }
        if description.productType != nil { names.append("product_type") }
        if description.state != nil { names.append("state") }
        return names.sorted()
    }
}
