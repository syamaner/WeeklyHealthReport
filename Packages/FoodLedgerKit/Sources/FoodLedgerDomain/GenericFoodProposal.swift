import Foundation

/// A proposal is separate from an admitted ledger candidate. Binding establishes
/// literal correspondence only; a person must still review identity and meaning.
public enum GenericFoodProposalError: Error, Equatable, Sendable {
    case invalidDocument, invalidSchema, invalidReference, invalidIdentity
    case invalidBasis, invalidNutrient, invalidSelection
}

public struct FoodDocumentBlock: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let text: String
    public let locator: String
    public init(id: String, kind: String, text: String, locator: String) {
        self.id = id; self.kind = kind; self.text = text; self.locator = locator
    }
}

public struct CapturedFoodDocument: Codable, Equatable, Sendable {
    public let id: String
    public let url: String
    public let rawSha256: String
    public let captureOrigin: String
    public let retrievedAt: String
    public let blocks: [FoodDocumentBlock]
    public init(id: String, url: String, rawSha256: String, captureOrigin: String,
                retrievedAt: String, blocks: [FoodDocumentBlock]) throws {
        self.id = id; self.url = url; self.rawSha256 = rawSha256
        self.captureOrigin = captureOrigin; self.retrievedAt = retrievedAt; self.blocks = blocks
        try validate()
    }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 100, !captureOrigin.isEmpty, !retrievedAt.isEmpty,
              let address = URL(string: url), address.scheme == "https", address.host != nil,
              address.user == nil, address.password == nil, address.port == nil || address.port == 443,
              rawSha256.count == 64, rawSha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              !blocks.isEmpty, blocks.count <= 512,
              Set(blocks.map(\.id)).count == blocks.count,
              blocks.reduce(0, { $0 + $1.text.count }) <= 30_000,
              blocks.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && !$0.text.isEmpty
                  && !$0.kind.isEmpty && !$0.locator.isEmpty && $0.locator.count <= 500 }) else {
            throw GenericFoodProposalError.invalidDocument
        }
    }
}

public struct FoodProposalReference: Codable, Equatable, Sendable {
    public let blockId: String
    public let quote: String
    public init(blockId: String, quote: String) { self.blockId = blockId; self.quote = quote }
}

public enum FoodProposalNutrientKey: String, Codable, CaseIterable, Sendable {
    case energy, protein, carbohydrate, fat, fibre, sodium
    public var unit: String { self == .energy ? "kcal" : self == .sodium ? "mg" : "g" }
    public var ledgerKey: NutrientKey {
        switch self {
        case .energy: .energyConsumed
        case .protein: .protein
        case .carbohydrate: .carbohydrates
        case .fat: .fatTotal
        case .fibre: .fiber
        case .sodium: .sodium
        }
    }
}

public struct FoodProposalNutrient: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case declared, unknown }
    public enum Unknown: String, Codable, Sendable {
        case notObserved = "not_observed", conflict, unreadable
        case unsupportedRepresentation = "unsupported_representation"
    }
    public let key: FoodProposalNutrientKey
    public let state: State
    public let value: String?
    public let unit: String?
    public let evidence: [FoodProposalReference]
    public let unknownReason: Unknown?
}

public struct FoodProposalBasis: Codable, Equatable, Sendable {
    public enum Unit: String, Codable, Sendable { case g, ml, serving }
    public let amount: String?
    public let unit: Unit?
    public let label: String?
    public let evidence: [FoodProposalReference]
}

public struct FoodProposalCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let documentId: String
    public let name: String
    public let brand: String?
    public let preparation: String?
    public let identityEvidence: [FoodProposalReference]
    public let panelEvidence: [FoodProposalReference]
    public let basis: FoodProposalBasis
    public let nutrients: [FoodProposalNutrient]
    public let limitations: [String]
}

public struct FoodProposalExtraction: Codable, Equatable, Sendable {
    public static let schemaVersion = "generic-food-extraction-v1"
    public let version: String
    public let candidates: [FoodProposalCandidate]
    public let preferredId: String
    public init(version: String = Self.schemaVersion, candidates: [FoodProposalCandidate], preferredId: String) {
        self.version = version; self.candidates = candidates; self.preferredId = preferredId
    }
}

public struct BoundFoodProposal: Equatable, Sendable, Identifiable {
    public enum Status: String, Sendable { case literalBound = "literal_bound_semantics_unverified", conflictingCandidates = "conflicting_candidates" }
    public var id: String { candidate.id }
    public let candidate: FoodProposalCandidate
    public let document: CapturedFoodDocument
    public fileprivate(set) var status: Status
    public var selectionEligible: Bool {
        status == .literalBound && candidate.basis.unit != nil
            && candidate.nutrients.contains { $0.state == .declared }
            && !candidate.nutrients.contains { $0.unknownReason == .conflict }
    }
    fileprivate init(candidate: FoodProposalCandidate, document: CapturedFoodDocument) {
        self.candidate = candidate; self.document = document; status = .literalBound
    }
}

public struct FoodProposalValidation: Equatable, Sendable {
    public struct Rejection: Equatable, Sendable {
        public let id: String
        public let reason: GenericFoodProposalError
    }
    public let candidates: [BoundFoodProposal]
    public let rejected: [Rejection]
    public let extractorPreferredId: String
}

public enum FoodProposalBinding {
    public static let version = "food-proposal-binding-v7"

    public static func validate(_ extraction: FoodProposalExtraction,
                                documents: [CapturedFoodDocument]) throws -> FoodProposalValidation {
        guard extraction.version == FoodProposalExtraction.schemaVersion, extraction.candidates.count <= 3,
              Set(extraction.candidates.map(\.id)).count == extraction.candidates.count,
              extraction.candidates.allSatisfy({ ["c1", "c2", "c3"].contains($0.id) }),
              (extraction.candidates.map(\.id) + ["none", "clarify"]).contains(extraction.preferredId),
              !documents.isEmpty, documents.count <= 3,
              Set(documents.map(\.id)).count == documents.count else { throw GenericFoodProposalError.invalidSchema }
        for document in documents { try document.validate() }
        var bound: [BoundFoodProposal] = []
        var rejected: [FoodProposalValidation.Rejection] = []
        for candidate in extraction.candidates {
            do {
                guard let document = documents.first(where: { $0.id == candidate.documentId }) else {
                    throw GenericFoodProposalError.invalidDocument
                }
                try bind(candidate, document)
                bound.append(BoundFoodProposal(candidate: candidate, document: document))
            } catch let error as GenericFoodProposalError { rejected.append(.init(id: candidate.id, reason: error)) }
        }
        for i in bound.indices {
            for j in bound.indices where j > i {
                if conflicting(bound[i].candidate, bound[j].candidate) {
                    bound[i].status = .conflictingCandidates; bound[j].status = .conflictingCandidates
                }
            }
        }
        return FoodProposalValidation(candidates: bound, rejected: rejected, extractorPreferredId: extraction.preferredId)
    }

    private static func references(_ refs: [FoodProposalReference], _ document: CapturedFoodDocument,
                                   required: Bool = true) throws -> String {
        guard refs.count <= 40, !required || !refs.isEmpty else { throw GenericFoodProposalError.invalidReference }
        for ref in refs {
            guard !ref.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ref.quote.count <= 1500,
                  let block = document.blocks.first(where: { $0.id == ref.blockId }), block.text.contains(ref.quote) else {
                throw GenericFoodProposalError.invalidReference
            }
        }
        return refs.map(\.quote).joined(separator: " ")
    }

    private static func bind(_ candidate: FoodProposalCandidate, _ document: CapturedFoodDocument) throws {
        _ = try references(candidate.identityEvidence, document)
        guard !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              candidate.name.count <= 1500, candidate.identityEvidence.contains(where: { $0.quote.contains(candidate.name) }),
              candidate.brand.map({ brand in !brand.isEmpty && brand.count <= 1500
                  && candidate.identityEvidence.contains(where: { $0.quote.contains(brand) }) }) ?? true,
              candidate.preparation.map({ $0.count <= 1500 }) ?? true,
              candidate.limitations.count <= 40, candidate.limitations.allSatisfy({ $0.count <= 1500 }) else {
            throw GenericFoodProposalError.invalidIdentity
        }
        _ = try references(candidate.panelEvidence, document)
        let panelIDs = Set(candidate.panelEvidence.map(\.blockId))
        guard Set(candidate.identityEvidence.map(\.blockId)).isSubset(of: panelIDs) else {
            throw GenericFoodProposalError.invalidIdentity
        }
        let basis = candidate.basis
        if let unit = basis.unit {
            guard let amount = basis.amount, let numeric = decimal(amount), numeric > 0,
                  let label = basis.label, !label.isEmpty,
                  !(try references(basis.evidence, document)).isEmpty,
                  basis.evidence.contains(where: { $0.quote.contains(label) }),
                  Set(basis.evidence.map(\.blockId)).isSubset(of: panelIDs) else { throw GenericFoodProposalError.invalidBasis }
            if unit == .serving {
                guard amount == "1" else { throw GenericFoodProposalError.invalidBasis }
            } else {
                guard basis.evidence.contains(where: { hasLiteral($0, document: document, value: amount, unit: unit.rawValue) }) else {
                    throw GenericFoodProposalError.invalidBasis
                }
            }
        } else if basis.amount != nil || basis.label != nil || !basis.evidence.isEmpty { throw GenericFoodProposalError.invalidBasis }
        guard candidate.nutrients.count == FoodProposalNutrientKey.allCases.count,
              Set(candidate.nutrients.map(\.key)) == Set(FoodProposalNutrientKey.allCases) else { throw GenericFoodProposalError.invalidNutrient }
        for nutrient in candidate.nutrients {
            _ = try references(nutrient.evidence, document, required: nutrient.state == .declared)
            guard Set(nutrient.evidence.map(\.blockId)).isSubset(of: panelIDs) else {
                throw GenericFoodProposalError.invalidNutrient
            }
            switch nutrient.state {
            case .unknown:
                guard nutrient.value == nil, nutrient.unit == nil, nutrient.unknownReason != nil else {
                    throw GenericFoodProposalError.invalidNutrient
                }
            case .declared:
                guard nutrient.unknownReason == nil, nutrient.unit == nutrient.key.unit, let value = nutrient.value,
                      Set(nutrient.evidence.map(\.blockId)).isSubset(of: panelIDs),
                      nutrient.evidence.contains(where: { hasLiteral($0, document: document, value: value, unit: nutrient.key.unit, allowHeaderUnit: true) }) else { throw GenericFoodProposalError.invalidNutrient }
            }
        }
    }

    public static func decimal(_ text: String) -> Decimal? {
        guard text.range(of: #"^(0|[1-9][0-9]{0,7})(\.[0-9]{1,8})?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Number and unit must occur together. Bounds, approximate values, ranges,
    /// negative values and different units cannot become exact nutrition.
    public static func hasLiteral(_ text: String, value: String, unit: String) -> Bool {
        !literalRanges(text, value: value, unit: unit).isEmpty
    }

    /// Evaluate numeric boundaries and qualifiers in the original captured block.
    /// A short quotation cannot remove a less-than sign, range or leading digit.
    private static func hasLiteral(_ reference: FoodProposalReference, document: CapturedFoodDocument,
                                   value: String, unit: String, allowHeaderUnit: Bool = false) -> Bool {
        guard let block = document.blocks.first(where: { $0.id == reference.blockId }), !reference.quote.isEmpty else { return false }
        if allowHeaderUnit, reference.quote == block.text,
           hasLabelledUnitLiteral(block.text, value: value, unit: unit) { return true }
        if allowHeaderUnit, reference.quote == block.text, ["tr", "definition_row"].contains(block.kind),
           (hasHeaderUnitLiteral(block.text, value: value, unit: unit)
            || hasPairedEnergyLiteral(block.text, value: value, unit: unit)) { return true }
        let literal = literalRanges(block.text, value: value, unit: unit)
        let source = block.text as NSString
        var remaining = NSRange(location: 0, length: source.length)
        while remaining.length > 0 {
            let quote = source.range(of: reference.quote, options: [], range: remaining)
            if quote.location == NSNotFound { return false }
            if literal.contains(where: { $0.location >= quote.location && NSMaxRange($0) <= NSMaxRange(quote) }) { return true }
            let next = quote.location + 1
            remaining = NSRange(location: next, length: source.length - next)
        }
        return false
    }

    /// A complete structural row can share its explicit label unit across numeric
    /// columns. This proves literal correspondence, not column or nutrient meaning.
    /// Free text, inferred units and shortened quotations do not use this profile.
    private static func hasHeaderUnitLiteral(_ text: String, value: String, unit: String) -> Bool {
        guard let expected = decimal(value),
              let aliases = ["g": "g|公克|克", "mg": "mg|毫克", "kcal": "kcal|大卡|千卡"][unit],
              let header = try? NSRegularExpression(pattern: #"^[^|()/\r\n]{1,80}(?:\((?:"# + aliases + #")\)|\s+(?:"# + aliases + #"))\s*\|\s*(.+)$"#, options: .caseInsensitive),
              let match = header.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return false }
        let columns = (text as NSString).substring(with: match.range(at: 1)).components(separatedBy: CharacterSet(charactersIn: "|/"))
        guard !columns.isEmpty, columns.count <= 4 else { return false }
        var found = false
        for column in columns {
            let token = column.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.range(of: #"^(?:[<>≤≥]\s*)?(?:0|[1-9][0-9]{0,7})(?:\.[0-9]{1,8})?$"#, options: .regularExpression) != nil else { return false }
            if decimal(token) == expected { found = true }
        }
        return found
    }

    /// A whole scalar label can put its explicit unit before a colon. Only one
    /// exact number is accepted, so a bound, range, percentage or prose is not lost.
    private static func hasLabelledUnitLiteral(_ text: String, value: String, unit: String) -> Bool {
        guard let expected = decimal(value),
              let aliases = ["g": "g|公克|克", "mg": "mg|毫克", "kcal": "kcal|大卡|千卡"][unit],
              let regex = try? NSRegularExpression(pattern: #"^[^0-9|():：\r\n]{1,80}\s*\((?:"# + aliases + #")\)\s*[:：]\s*((?:0|[1-9][0-9]{0,7})(?:\.[0-9]{1,8})?)\s*$"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return false }
        return decimal((text as NSString).substring(with: match.range(at: 1))) == expected
    }

    /// Structural paired energy units bind only the corresponding exact column.
    /// This is representation, never a kJ conversion or free-text unit inference.
    private static func hasPairedEnergyLiteral(_ text: String, value: String, unit: String) -> Bool {
        guard unit == "kcal", let expected = decimal(value),
              let regex = try? NSRegularExpression(pattern: #"^(?:Energy|熱量|热量)\s*\(?\s*(kJ|kcal)\s*/\s*(kJ|kcal)\s*\)?\s*\|\s*(.+)$"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return false }
        let source = text as NSString
        let units = [source.substring(with: match.range(at: 1)).lowercased(), source.substring(with: match.range(at: 2)).lowercased()]
        guard Set(units) == ["kj", "kcal"], let index = units.firstIndex(of: "kcal") else { return false }
        let columns = source.substring(with: match.range(at: 3)).components(separatedBy: "|")
        guard (1...4).contains(columns.count) else { return false }
        var found = false
        for column in columns {
            let pair = column.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard pair.count == 2, pair.allSatisfy({ $0.range(of: #"^(?:[<>≤≥]\s*)?(?:0|[1-9][0-9]{0,7})(?:\.[0-9]{1,8})?$"#, options: .regularExpression) != nil }) else { return false }
            if pair.allSatisfy({ decimal($0) != nil }), decimal(pair[index]) == expected { found = true }
        }
        return found
    }

    private static func literalRanges(_ text: String, value: String, unit: String) -> [NSRange] {
        guard let expected = decimal(value),
              let aliases = ["g": "g|公克|克", "mg": "mg|毫克", "ml": "mls?|毫升", "kcal": "kcal|大卡|千卡"][unit],
              let regex = try? NSRegularExpression(pattern: #"(?<![0-9A-Za-z.,])([0-9]+(?:\.[0-9]+)?)\s*(?:"# + aliases + #")(?![A-Za-z])"#, options: .caseInsensitive) else { return [] }
        let source = text as NSString
        var ranges: [NSRange] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let prefix = source.substring(to: match.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.range(of: #"(?:[<>≤≥~≈+\-–—=±]|(?<![A-Za-z])(?:about|approximately|approx\.?|around|to|less\s+than|more\s+than|greater\s+than|at\s+least|at\s+most|under|over|minimum|maximum|min\.?|max\.?)|至|到|約|约|小於|小于|少於|少于|大於|大于|低於|低于|高於|高于|超過|超过|最多|至少|大約|大约|約莫|約略)\s*[:：]?$"#,
                            options: [.regularExpression, .caseInsensitive]) != nil { continue }
            let suffix = source.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.range(of: #"^(?:[-–—]|to\b|至|到)\s*[0-9]"#,
                            options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if suffix.range(of: #"^(?:±|以下|以上|左右|以內|以内|\bor\s+(?:less|more)\b|\(?\s*(?:approx(?:imately)?\.?|minimum|maximum|min\.?|max\.?)\b)"#,
                            options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if Decimal(string: source.substring(with: match.range(at: 1)), locale: Locale(identifier: "en_US_POSIX")) == expected { ranges.append(match.range) }
        }
        return ranges
    }

    private static func conflicting(_ left: FoodProposalCandidate, _ right: FoodProposalCandidate) -> Bool {
        guard left.documentId == right.documentId, left.name == right.name, left.brand == right.brand,
              left.preparation == right.preparation, left.basis.amount == right.basis.amount,
              left.basis.unit == right.basis.unit else { return false }
        // Wording differences in the basis label cannot hide a numeric conflict.
        return left.nutrients.contains { value in
            guard value.state == .declared, let other = right.nutrients.first(where: { $0.key == value.key }),
                  other.state == .declared, let a = value.value, let b = other.value else { return false }
            return decimal(a) != decimal(b)
        }
    }
}

public struct FoodProposalSelection: Equatable, Sendable {
    public let choice: String
    public let probabilities: [String: Double]
    public let rawConfidence: Double?
    public let calibration = "not_calibrated_for_nutrition"
    /// A categorical checker has no calibrated probabilities. Never invent them.
    public init(unscoredChoice choice: String, validation: FoodProposalValidation) throws {
        guard Set(validation.candidates.filter(\.selectionEligible).map(\.id) + ["none", "clarify"]).contains(choice) else {
            throw GenericFoodProposalError.invalidSelection
        }
        self.choice = choice; self.probabilities = [:]; self.rawConfidence = nil
    }
    public init(choice: String, probabilities: [String: Double], rawConfidence: Double?, validation: FoodProposalValidation) throws {
        let options = Set(validation.candidates.filter(\.selectionEligible).map(\.id) + ["none", "clarify"])
        guard options.contains(choice), Set(probabilities.keys) == options,
              probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              abs(probabilities.values.reduce(0, +) - 1) <= 0.02,
              rawConfidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true else { throw GenericFoodProposalError.invalidSelection }
        self.choice = choice; self.probabilities = probabilities; self.rawConfidence = rawConfidence
    }
}
