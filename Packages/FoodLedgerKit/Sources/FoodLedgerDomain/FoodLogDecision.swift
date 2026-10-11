import Foundation

/// The source's own state for one material-difference facet, as a closed token.
/// It describes the selected source record only; it never describes what was eaten.
public struct FoodLogSourceState: Codable, Hashable, Sendable {
    public let token: String

    public init(facet: IdentityContradiction, token: String) throws {
        guard Self.tokens(for: facet).contains(token) else {
            throw FoodLedgerValidationError.invalidConfirmationDecision
        }
        self.token = token
    }

    public init(facet: IdentityContradiction, identity: DecisiveIdentity, edibleQuantity: EdibleQuantityIdentity) {
        let value: String = switch facet {
        case .preparation: identity.preparation.kind.rawValue
        case .bone: identity.bone.rawValue
        case .skin: identity.skin.rawValue
        case .drained: identity.drained.rawValue
        case .packingMedium:
            if case .named = identity.packingMedium { "named" } else { "unknown" }
        case .fortification: identity.fortification.rawValue
        case .servingBasis:
            switch identity.servingBasis {
            case .per100Grams: "per_100_g"
            case .per100Millilitres: "per_100_ml"
            case .perServing: "per_serving"
            case .perUnit: "per_unit"
            case .named: "named"
            case .unknown: "unknown"
            }
        case .edibleQuantity:
            if case .known = edibleQuantity { "known" } else { "unknown" }
        }
        token = value
    }

    public init(from decoder: any Decoder) throws {
        token = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }

    public var isKnown: Bool { token != "unknown" }

    static func tokens(for facet: IdentityContradiction) -> Set<String> {
        switch facet {
        case .preparation: ["as_sold", "raw", "cooked", "reheated", "named", "unknown"]
        case .bone: ["with_bone", "boneless", "not_applicable", "unknown"]
        case .skin: ["skin_on", "skinless", "not_applicable", "unknown"]
        case .drained: ["drained", "undrained", "not_applicable", "unknown"]
        case .packingMedium: ["named", "unknown"]
        case .fortification: ["fortified", "unfortified", "unknown"]
        case .servingBasis: ["per_100_g", "per_100_ml", "per_serving", "per_unit", "named", "unknown"]
        case .edibleQuantity: ["known", "unknown"]
        }
    }
}

/// The user's closed answer to one material difference. Encoded as a single token,
/// which is also the token used in the versioned assertion claim grammar.
public enum FoodLogDecisionChoice: Codable, Hashable, Sendable {
    case matchesSource
    case differs(String)
    case differentMediumOrNone
    case notSure
    case useSourceBasis
    case useSourceServing

    public var token: String {
        switch self {
        case .matchesSource: "matches_source"
        case let .differs(value): "differs:" + value
        case .differentMediumOrNone: "different_medium_or_none"
        case .notSure: "not_sure"
        case .useSourceBasis: "use_source_basis"
        case .useSourceServing: "use_source_serving"
        }
    }

    public init(token: String) throws {
        switch token {
        case "matches_source": self = .matchesSource
        case "different_medium_or_none": self = .differentMediumOrNone
        case "not_sure": self = .notSure
        case "use_source_basis": self = .useSourceBasis
        case "use_source_serving": self = .useSourceServing
        default:
            guard token.hasPrefix("differs:"), token.count > "differs:".count else {
                throw FoodLedgerValidationError.invalidConfirmationDecision
            }
            self = .differs(String(token.dropFirst("differs:".count)))
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do { try self.init(token: container.decode(String.self)) } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid confirmation decision choice")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }

    /// Whether this choice makes the logged intake a labelled estimate.
    public var isEstimate: Bool {
        switch self {
        case .differs, .differentMediumOrNone, .notSure: true
        case .matchesSource, .useSourceBasis, .useSourceServing: false
        }
    }
}

public struct FoodLogFacetDecision: Codable, Hashable, Sendable {
    public let facet: IdentityContradiction
    public let sourceState: FoodLogSourceState
    public let choice: FoodLogDecisionChoice

    public init(facet: IdentityContradiction, sourceState: FoodLogSourceState, choice: FoodLogDecisionChoice) throws {
        guard FoodLogSourceState.tokens(for: facet).contains(sourceState.token),
              Self.offeredChoices(facet: facet, sourceState: sourceState).contains(choice) else {
            throw FoodLedgerValidationError.invalidConfirmationDecision
        }
        self.facet = facet
        self.sourceState = sourceState
        self.choice = choice
    }

    private enum CodingKeys: String, CodingKey { case facet, sourceState, choice }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(facet: values.decode(IdentityContradiction.self, forKey: .facet),
                sourceState: values.decode(FoodLogSourceState.self, forKey: .sourceState),
                choice: values.decode(FoodLogDecisionChoice.self, forKey: .choice))
        } catch let error as FoodLedgerValidationError {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid confirmation decision: \(error)"))
        }
    }

    /// Closed answer set for a facet given the source's state. `matchesSource` needs a known
    /// source state; `differs` excludes unknown, named, not-applicable and the source's own value.
    /// Serving basis and edible quantity are acknowledgements only.
    public static func offeredChoices(facet: IdentityContradiction, sourceState: FoodLogSourceState) -> [FoodLogDecisionChoice] {
        let alternatives: [String]
        switch facet {
        case .servingBasis: return [.useSourceBasis]
        case .edibleQuantity: return [.useSourceServing]
        case .packingMedium:
            return (sourceState.isKnown ? [.matchesSource] : []) + [.differentMediumOrNone, .notSure]
        case .preparation: alternatives = ["as_sold", "raw", "cooked", "reheated"]
        case .bone: alternatives = ["with_bone", "boneless"]
        case .skin: alternatives = ["skin_on", "skinless"]
        case .drained: alternatives = ["drained", "undrained"]
        case .fortification: alternatives = ["fortified", "unfortified"]
        }
        let differs = alternatives.filter { $0 != sourceState.token }.map(FoodLogDecisionChoice.differs)
        return (sourceState.isKnown ? [.matchesSource] : []) + differs + [.notSure]
    }
}

/// Typed inline decisions recorded on the confirming user assertion (policy food_confirmation_v5).
/// No estimate flag is stored; estimate status is always derived from the choices.
public struct FoodLogDecisionRecord: Codable, Equatable, Sendable {
    public static let currentPolicyVersion = "food_confirmation_v5"
    public let policyVersion: LedgerText
    public let decisions: [FoodLogFacetDecision]

    public init(policyVersion: LedgerText, decisions: [FoodLogFacetDecision]) throws {
        let order = decisions.map { IdentityContradiction.allCases.firstIndex(of: $0.facet) ?? -1 }
        guard policyVersion.value == Self.currentPolicyVersion,
              !decisions.isEmpty,
              Set(decisions.map(\.facet)).count == decisions.count,
              order == order.sorted() else {
            throw FoodLedgerValidationError.invalidConfirmationDecision
        }
        self.policyVersion = policyVersion
        self.decisions = decisions
    }

    private enum CodingKeys: String, CodingKey { case policyVersion, decisions }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(policyVersion: values.decode(LedgerText.self, forKey: .policyVersion),
                decisions: values.decode([FoodLogFacetDecision].self, forKey: .decisions))
        } catch let error as FoodLedgerValidationError {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid confirmation decision record: \(error)"))
        }
    }

    public var isEstimate: Bool { decisions.contains { $0.choice.isEstimate } }

    /// Persisted, versioned claim grammar: `<facet>: source <state>, choice <choice>` joined by "; ".
    public var claimList: String {
        decisions.map { "\($0.facet.rawValue): source \($0.sourceState.token), choice \($0.choice.token)" }
            .joined(separator: "; ")
    }
}
