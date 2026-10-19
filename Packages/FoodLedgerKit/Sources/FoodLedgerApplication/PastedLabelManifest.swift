import Foundation
import FoodLedgerDomain

/// The retained evidence of a logged pasted label, `pasted-nutrition-label-v1`
/// (`docs/pasted-nutrition-label-v1.md` section 6.1). Encoded once with the canonical encoder
/// (sorted keys, unescaped slashes, dates in milliseconds) and stored verbatim as the evidence
/// `.text` payload; it is never re-encoded from this struct after save.
///
/// Application-owned: the reader's `label-capture-candidate-v1` and conversion records are
/// mirrored here with byte-identical keys, so no `NutritionLabelParsing` type crosses the port
/// (decision 10). Decoding is strict at every level: an unknown or missing key throws.
public struct PastedLabelManifest: Codable, Equatable, Sendable {
    public static let version = "pasted-nutrition-label-v1"
    /// Section 6.2: the pasted text limit, counted in Unicode scalars.
    public static let maximumTextScalars = 8_000

    public let version: String
    public let pastedText: String
    public let pastedTextSHA256: String
    public let parserVersion: String
    public let gateVersion: String
    public let arithmeticVersion: String
    public let conversionVersion: String
    public let labelFormat: String
    public let launchScope: [String]
    public let identityMapping: IdentityMapping
    public let candidate: Candidate
    public let storedHeaderID: String
    public let conversions: [Conversion]
    public let flagsShown: [Flag]
    public let corrections: [Correction]
    public let warningsShown: [String]
    public let name: String
    public let brand: String?

    public init(pastedText: String, pastedTextSHA256: String, parserVersion: String, gateVersion: String,
                arithmeticVersion: String, conversionVersion: String, labelFormat: String, launchScope: [String],
                identityMapping: IdentityMapping, candidate: Candidate, storedHeaderID: String, conversions: [Conversion],
                flagsShown: [Flag], corrections: [Correction], warningsShown: [String], name: String, brand: String?) {
        version = Self.version
        self.pastedText = pastedText; self.pastedTextSHA256 = pastedTextSHA256
        self.parserVersion = parserVersion; self.gateVersion = gateVersion
        self.arithmeticVersion = arithmeticVersion; self.conversionVersion = conversionVersion
        self.labelFormat = labelFormat; self.launchScope = launchScope; self.identityMapping = identityMapping
        self.candidate = candidate; self.storedHeaderID = storedHeaderID; self.conversions = conversions
        self.flagsShown = flagsShown; self.corrections = corrections; self.warningsShown = warningsShown
        self.name = name; self.brand = brand.flatMap { $0.isEmpty ? nil : $0 }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case pastedText = "pasted_text"
        case pastedTextSHA256 = "pasted_text_sha256"
        case parserVersion = "parser_version"
        case gateVersion = "gate_version"
        case arithmeticVersion = "arithmetic_version"
        case conversionVersion = "conversion_version"
        case labelFormat = "label_format"
        case launchScope = "launch_scope"
        case identityMapping = "identity_mapping"
        case candidate
        case storedHeaderID = "stored_header_id"
        case conversions
        case flagsShown = "flags_shown"
        case corrections
        case warningsShown = "warnings_shown"
        case name
        case brand
    }

    public init(from decoder: any Decoder) throws {
        try StrictManifestKeys.require(CodingKeys.self, optional: [.brand], in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        guard version == Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "Not a pasted-label v1 manifest")
        }
        pastedText = try container.decode(String.self, forKey: .pastedText)
        pastedTextSHA256 = try container.decode(String.self, forKey: .pastedTextSHA256)
        parserVersion = try container.decode(String.self, forKey: .parserVersion)
        gateVersion = try container.decode(String.self, forKey: .gateVersion)
        arithmeticVersion = try container.decode(String.self, forKey: .arithmeticVersion)
        conversionVersion = try container.decode(String.self, forKey: .conversionVersion)
        labelFormat = try container.decode(String.self, forKey: .labelFormat)
        launchScope = try container.decode([String].self, forKey: .launchScope)
        identityMapping = try container.decode(IdentityMapping.self, forKey: .identityMapping)
        candidate = try container.decode(Candidate.self, forKey: .candidate)
        storedHeaderID = try container.decode(String.self, forKey: .storedHeaderID)
        conversions = try container.decode([Conversion].self, forKey: .conversions)
        flagsShown = try container.decode([Flag].self, forKey: .flagsShown)
        corrections = try container.decode([Correction].self, forKey: .corrections)
        warningsShown = try container.decode([String].self, forKey: .warningsShown)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        // `brand` is omitted when empty, so an explicit empty brand is not a canonical encoding.
        if brand?.isEmpty == true {
            throw DecodingError.dataCorruptedError(forKey: .brand, in: container, debugDescription: "Empty brand member")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(pastedText, forKey: .pastedText)
        try container.encode(pastedTextSHA256, forKey: .pastedTextSHA256)
        try container.encode(parserVersion, forKey: .parserVersion)
        try container.encode(gateVersion, forKey: .gateVersion)
        try container.encode(arithmeticVersion, forKey: .arithmeticVersion)
        try container.encode(conversionVersion, forKey: .conversionVersion)
        try container.encode(labelFormat, forKey: .labelFormat)
        try container.encode(launchScope, forKey: .launchScope)
        try container.encode(identityMapping, forKey: .identityMapping)
        try container.encode(candidate, forKey: .candidate)
        try container.encode(storedHeaderID, forKey: .storedHeaderID)
        try container.encode(conversions, forKey: .conversions)
        try container.encode(flagsShown, forKey: .flagsShown)
        try container.encode(corrections, forKey: .corrections)
        try container.encode(warningsShown, forKey: .warningsShown)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(brand, forKey: .brand)
    }

    /// Decodes stored manifest bytes with the canonical date strategy; `nil` when they are not
    /// a strict v1 manifest.
    public static func decode(_ data: Data) -> PastedLabelManifest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(Self.self, from: data)
    }

    // MARK: Identity mapping

    /// `pasted-label-identity-v1` and its resulting facet values, with the Fortified? answer.
    public struct IdentityMapping: Codable, Equatable, Sendable {
        public let version: String
        public let fortificationAnswer: PastedLabelIdentity.FortificationAnswer
        public let itemClass: ItemClass
        public let identity: DecisiveIdentity

        public init(fortificationAnswer: PastedLabelIdentity.FortificationAnswer, servingBasis: ResolutionBasis) throws {
            version = PastedLabelIdentity.version
            self.fortificationAnswer = fortificationAnswer
            itemClass = PastedLabelIdentity.itemClass(fortificationAnswer)
            identity = try PastedLabelIdentity.identity(fortification: fortificationAnswer, servingBasis: servingBasis)
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case version
            case fortificationAnswer = "fortification_answer"
            case itemClass = "item_class"
            case identity
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(String.self, forKey: .version)
            fortificationAnswer = try container.decode(PastedLabelIdentity.FortificationAnswer.self, forKey: .fortificationAnswer)
            itemClass = try container.decode(ItemClass.self, forKey: .itemClass)
            identity = try container.decode(DecisiveIdentity.self, forKey: .identity)
        }

        /// The recorded facets are exactly what the named mapping version yields.
        public func isCoherent(servingBasis: ResolutionBasis) -> Bool {
            version == PastedLabelIdentity.version
                && itemClass == PastedLabelIdentity.itemClass(fortificationAnswer)
                && (try? PastedLabelIdentity.identity(fortification: fortificationAnswer, servingBasis: servingBasis)) == identity
        }
    }

    // MARK: Candidate mirror (`label-capture-candidate-v1`)

    /// The reader's candidate, mirrored key for key. The constant members (`schema_version`,
    /// `status`, `ready_for_confirmation`, `automatic_save`) are written and checked, never stored.
    public struct Candidate: Codable, Equatable, Sendable {
        public static let schemaVersion = "label-capture-candidate-v1"
        public let route: String
        public let inputSHA256: String
        public let declined: Bool
        public let declineReasons: [String]
        public let wouldMarkReady: Bool
        public let language: String
        public let servingSize: ServingSize?
        public let servingsPerPack: ServingsPerPack?
        public let headers: [Header]
        public let cells: [Cell]
        public let warnings: [String]

        public init(route: String, inputSHA256: String, declined: Bool, declineReasons: [String], wouldMarkReady: Bool,
                    language: String, servingSize: ServingSize?, servingsPerPack: ServingsPerPack?, headers: [Header],
                    cells: [Cell], warnings: [String]) {
            self.route = route; self.inputSHA256 = inputSHA256; self.declined = declined
            self.declineReasons = declineReasons; self.wouldMarkReady = wouldMarkReady && !declined
            self.language = language; self.servingSize = servingSize; self.servingsPerPack = servingsPerPack
            self.headers = headers; self.cells = cells; self.warnings = warnings
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion = "schema_version"
            case route
            case inputSHA256 = "input_sha256"
            case status
            case declined
            case declineReasons = "decline_reasons"
            case readyForConfirmation = "ready_for_confirmation"
            case wouldMarkReady = "would_mark_ready"
            case automaticSave = "automatic_save"
            case language
            case servingSize = "serving_size"
            case servingsPerPack = "servings_per_pack"
            case headers
            case cells
            case warnings
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(String.self, forKey: .schemaVersion) == Self.schemaVersion,
                  try container.decode(String.self, forKey: .status) == "user_selection_only",
                  try container.decode(Bool.self, forKey: .readyForConfirmation) == false,
                  try container.decode(Bool.self, forKey: .automaticSave) == false else {
                throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Candidate violates the user-selection-only contract")
            }
            route = try container.decode(String.self, forKey: .route)
            inputSHA256 = try container.decode(String.self, forKey: .inputSHA256)
            declined = try container.decode(Bool.self, forKey: .declined)
            declineReasons = try container.decode([String].self, forKey: .declineReasons)
            wouldMarkReady = try container.decode(Bool.self, forKey: .wouldMarkReady)
            language = try container.decode(String.self, forKey: .language)
            servingSize = try Self.decodeKnown(ServingSize.self, container, .servingSize)
            servingsPerPack = try Self.decodeKnown(ServingsPerPack.self, container, .servingsPerPack)
            headers = try container.decode([Header].self, forKey: .headers)
            cells = try container.decode([Cell].self, forKey: .cells)
            warnings = try container.decode([String].self, forKey: .warnings)
            guard !(wouldMarkReady && declined) else {
                throw DecodingError.dataCorruptedError(forKey: .wouldMarkReady, in: container, debugDescription: "A declined candidate is never ready")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.schemaVersion, forKey: .schemaVersion)
            try container.encode(route, forKey: .route)
            try container.encode(inputSHA256, forKey: .inputSHA256)
            try container.encode("user_selection_only", forKey: .status)
            try container.encode(declined, forKey: .declined)
            try container.encode(declineReasons, forKey: .declineReasons)
            try container.encode(false, forKey: .readyForConfirmation)
            try container.encode(wouldMarkReady, forKey: .wouldMarkReady)
            try container.encode(false, forKey: .automaticSave)
            try container.encode(language, forKey: .language)
            if let servingSize { try container.encode(servingSize, forKey: .servingSize) } else { try container.encode("unknown", forKey: .servingSize) }
            if let servingsPerPack { try container.encode(servingsPerPack, forKey: .servingsPerPack) } else { try container.encode("unknown", forKey: .servingsPerPack) }
            try container.encode(headers, forKey: .headers)
            try container.encode(cells, forKey: .cells)
            try container.encode(warnings, forKey: .warnings)
        }

        private static func decodeKnown<T: Decodable>(_ type: T.Type, _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> T? {
            if let text = try? container.decode(String.self, forKey: key) {
                guard text == "unknown" else {
                    throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Only the explicit string unknown is allowed")
                }
                return nil
            }
            return try container.decode(T.self, forKey: key)
        }

        public struct ServingSize: Codable, Equatable, Sendable {
            public let printedText: String
            public let decimalText: String?
            public let unit: String?
            public let canonicalUnit: String?
            public init(printedText: String, decimalText: String?, unit: String?, canonicalUnit: String?) {
                self.printedText = printedText; self.decimalText = decimalText; self.unit = unit; self.canonicalUnit = canonicalUnit
            }
            enum CodingKeys: String, CodingKey, CaseIterable {
                case printedText = "printed_text"
                case decimalText = "decimal_text"
                case unit
                case canonicalUnit = "canonical_unit"
            }
            public init(from decoder: any Decoder) throws {
                try StrictManifestKeys.require(CodingKeys.self, optional: [.decimalText, .unit, .canonicalUnit], in: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                printedText = try container.decode(String.self, forKey: .printedText)
                decimalText = try container.decodeIfPresent(String.self, forKey: .decimalText)
                unit = try container.decodeIfPresent(String.self, forKey: .unit)
                canonicalUnit = try container.decodeIfPresent(String.self, forKey: .canonicalUnit)
            }
        }

        public struct ServingsPerPack: Codable, Equatable, Sendable {
            public let printedText: String
            public let decimalText: String
            public let approximate: Bool
            public init(printedText: String, decimalText: String, approximate: Bool) {
                self.printedText = printedText; self.decimalText = decimalText; self.approximate = approximate
            }
            enum CodingKeys: String, CodingKey, CaseIterable {
                case printedText = "printed_text"
                case decimalText = "decimal_text"
                case approximate
            }
            public init(from decoder: any Decoder) throws {
                try StrictManifestKeys.require(CodingKeys.self, in: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                printedText = try container.decode(String.self, forKey: .printedText)
                decimalText = try container.decode(String.self, forKey: .decimalText)
                approximate = try container.decode(Bool.self, forKey: .approximate)
            }
        }

        public struct Header: Codable, Equatable, Sendable {
            public let headerID: String
            public let printedText: String
            /// `per_100g`, `per_100ml`, `per_serving` or `reference_intake`.
            public let basis: String
            public let servingConversion: String?
            public init(headerID: String, printedText: String, basis: String, servingConversion: String?) {
                self.headerID = headerID; self.printedText = printedText; self.basis = basis; self.servingConversion = servingConversion
            }
            enum CodingKeys: String, CodingKey, CaseIterable {
                case headerID = "header_id"
                case printedText = "printed_text"
                case basis
                case servingConversion = "serving_conversion"
            }
            public init(from decoder: any Decoder) throws {
                try StrictManifestKeys.require(CodingKeys.self, optional: [.servingConversion], in: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                headerID = try container.decode(String.self, forKey: .headerID)
                printedText = try container.decode(String.self, forKey: .printedText)
                basis = try container.decode(String.self, forKey: .basis)
                servingConversion = try container.decodeIfPresent(String.self, forKey: .servingConversion)
            }
        }

        public struct Cell: Codable, Equatable, Sendable {
            public let rowID: String
            public let parentRowID: String?
            public let nutrient: String
            public let printedLabel: String
            public let headerID: String
            public let basis: String
            public let printedText: String
            /// `=`, `<` or `<=`.
            public let comparator: String
            public let decimalText: String
            public let unit: String
            public let canonicalUnit: String
            public let servingConversion: String

            public init(rowID: String, parentRowID: String?, nutrient: String, printedLabel: String, headerID: String,
                        basis: String, printedText: String, comparator: String, decimalText: String, unit: String,
                        canonicalUnit: String, servingConversion: String) {
                self.rowID = rowID; self.parentRowID = parentRowID; self.nutrient = nutrient; self.printedLabel = printedLabel
                self.headerID = headerID; self.basis = basis; self.printedText = printedText; self.comparator = comparator
                self.decimalText = decimalText; self.unit = unit; self.canonicalUnit = canonicalUnit
                self.servingConversion = servingConversion
            }

            enum CodingKeys: String, CodingKey, CaseIterable {
                case rowID = "row_id"
                case parentRowID = "parent_row_id"
                case nutrient
                case printedLabel = "printed_label"
                case headerID = "header_id"
                case basis
                case printedText = "printed_text"
                case comparator
                case decimalText = "decimal_text"
                case unit
                case canonicalUnit = "canonical_unit"
                case servingConversion = "serving_conversion"
                case persistenceAuthorized = "persistence_authorized"
                case requiresUserSelection = "requires_user_selection"
            }

            public init(from decoder: any Decoder) throws {
                try StrictManifestKeys.require(CodingKeys.self, in: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                rowID = try container.decode(String.self, forKey: .rowID)
                parentRowID = try container.decodeIfPresent(String.self, forKey: .parentRowID)
                nutrient = try container.decode(String.self, forKey: .nutrient)
                printedLabel = try container.decode(String.self, forKey: .printedLabel)
                headerID = try container.decode(String.self, forKey: .headerID)
                basis = try container.decode(String.self, forKey: .basis)
                printedText = try container.decode(String.self, forKey: .printedText)
                comparator = try container.decode(String.self, forKey: .comparator)
                decimalText = try container.decode(String.self, forKey: .decimalText)
                unit = try container.decode(String.self, forKey: .unit)
                canonicalUnit = try container.decode(String.self, forKey: .canonicalUnit)
                servingConversion = try container.decode(String.self, forKey: .servingConversion)
                guard try container.decode(Bool.self, forKey: .persistenceAuthorized) == false,
                      try container.decode(Bool.self, forKey: .requiresUserSelection) == true else {
                    throw DecodingError.dataCorruptedError(forKey: .persistenceAuthorized, in: container, debugDescription: "A label cell can never authorise persistence")
                }
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(rowID, forKey: .rowID)
                try container.encode(parentRowID, forKey: .parentRowID)
                try container.encode(nutrient, forKey: .nutrient)
                try container.encode(printedLabel, forKey: .printedLabel)
                try container.encode(headerID, forKey: .headerID)
                try container.encode(basis, forKey: .basis)
                try container.encode(printedText, forKey: .printedText)
                try container.encode(comparator, forKey: .comparator)
                try container.encode(decimalText, forKey: .decimalText)
                try container.encode(unit, forKey: .unit)
                try container.encode(canonicalUnit, forKey: .canonicalUnit)
                try container.encode(servingConversion, forKey: .servingConversion)
                try container.encode(false, forKey: .persistenceAuthorized)
                try container.encode(true, forKey: .requiresUserSelection)
            }
        }
    }

    // MARK: Conversion record mirror (section 3.5, step 5)

    public struct Conversion: Codable, Equatable, Sendable {
        public let nutrient: String
        public let rule: String
        public let ruleVersion: String
        public let sourceHeaderID: String
        public let sourceRowID: String
        public let operandText: String
        public let operandUnit: String
        public let factorText: String
        public let intermediateText: String
        public let storedText: String
        public let comparator: String?
        public let rounding: String?

        public init(nutrient: String, rule: String, ruleVersion: String, sourceHeaderID: String, sourceRowID: String,
                    operandText: String, operandUnit: String, factorText: String, intermediateText: String, storedText: String,
                    comparator: String? = nil, rounding: String? = nil) {
            self.nutrient = nutrient; self.rule = rule; self.ruleVersion = ruleVersion
            self.sourceHeaderID = sourceHeaderID; self.sourceRowID = sourceRowID; self.operandText = operandText
            self.operandUnit = operandUnit; self.factorText = factorText; self.intermediateText = intermediateText
            self.storedText = storedText; self.comparator = comparator; self.rounding = rounding
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case nutrient
            case rule
            case ruleVersion = "rule_version"
            case sourceHeaderID = "source_header_id"
            case sourceRowID = "source_row_id"
            case operandText = "operand_text"
            case operandUnit = "operand_unit"
            case factorText = "factor_text"
            case intermediateText = "intermediate_text"
            case storedText = "stored_text"
            case comparator
            case rounding
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, optional: [.comparator, .rounding], in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nutrient = try container.decode(String.self, forKey: .nutrient)
            rule = try container.decode(String.self, forKey: .rule)
            ruleVersion = try container.decode(String.self, forKey: .ruleVersion)
            sourceHeaderID = try container.decode(String.self, forKey: .sourceHeaderID)
            sourceRowID = try container.decode(String.self, forKey: .sourceRowID)
            operandText = try container.decode(String.self, forKey: .operandText)
            operandUnit = try container.decode(String.self, forKey: .operandUnit)
            factorText = try container.decode(String.self, forKey: .factorText)
            intermediateText = try container.decode(String.self, forKey: .intermediateText)
            storedText = try container.decode(String.self, forKey: .storedText)
            comparator = try container.decodeIfPresent(String.self, forKey: .comparator)
            rounding = try container.decodeIfPresent(String.self, forKey: .rounding)
        }
    }

    // MARK: Flags and corrections

    /// A G3 to G6 exception shown on Confirm at Log, with the row or line it concerns.
    public struct Flag: Codable, Equatable, Sendable {
        public let code: String
        public let concerns: String
        public init(code: String, concerns: String) { self.code = code; self.concerns = concerns }
        enum CodingKeys: String, CodingKey, CaseIterable { case code, concerns }
        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(String.self, forKey: .code)
            concerns = try container.decode(String.self, forKey: .concerns)
        }
    }

    /// One value the user corrected or entered on Confirm. `row_id` and `recognised` are encoded
    /// as explicit nulls for an entered value that was not read.
    public struct Correction: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case corrected, entered }
        /// The nutrient row the serving-size line uses (section 6.3, case 3).
        public static let servingSize = "serving_size"
        /// The servings-per-pack line (G6), entered in `count` when the label does not print it.
        /// Evidence only: it sets no nutrient and no basis (owner, 19 October 2026).
        public static let servingsPerPack = "servings_per_pack"

        public let kind: Kind
        public let nutrient: String
        public let rowID: String?
        public let headerID: String
        public let recognised: Recognised?
        public let corrected: Value
        public let at: Date

        public init(kind: Kind, nutrient: String, rowID: String?, headerID: String, recognised: Recognised?, corrected: Value, at: Date) {
            self.kind = kind; self.nutrient = nutrient; self.rowID = rowID; self.headerID = headerID
            self.recognised = recognised; self.corrected = corrected; self.at = at
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case kind, nutrient
            case rowID = "row_id"
            case headerID = "header_id"
            case recognised, corrected, at
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(Kind.self, forKey: .kind)
            nutrient = try container.decode(String.self, forKey: .nutrient)
            rowID = try container.decodeIfPresent(String.self, forKey: .rowID)
            headerID = try container.decode(String.self, forKey: .headerID)
            recognised = try container.decodeIfPresent(Recognised.self, forKey: .recognised)
            corrected = try container.decode(Value.self, forKey: .corrected)
            at = try container.decode(Date.self, forKey: .at)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(nutrient, forKey: .nutrient)
            try container.encode(rowID, forKey: .rowID)
            try container.encode(headerID, forKey: .headerID)
            try container.encode(recognised, forKey: .recognised)
            try container.encode(corrected, forKey: .corrected)
            try container.encode(at, forKey: .at)
        }

        /// The recognised cell's printed text, decimal text, unit and comparator.
        public struct Recognised: Codable, Equatable, Sendable {
            public let printedText: String
            public let decimalText: String
            public let unit: String
            public let comparator: String
            public init(printedText: String, decimalText: String, unit: String, comparator: String) {
                self.printedText = printedText; self.decimalText = decimalText; self.unit = unit; self.comparator = comparator
            }
            enum CodingKeys: String, CodingKey, CaseIterable {
                case printedText = "printed_text"
                case decimalText = "decimal_text"
                case unit, comparator
            }
            public init(from decoder: any Decoder) throws {
                try StrictManifestKeys.require(CodingKeys.self, in: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                printedText = try container.decode(String.self, forKey: .printedText)
                decimalText = try container.decode(String.self, forKey: .decimalText)
                unit = try container.decode(String.self, forKey: .unit)
                comparator = try container.decode(String.self, forKey: .comparator)
            }
        }

        /// The value as entered: decimal text, unit and comparator.
        public struct Value: Codable, Equatable, Sendable {
            public let decimalText: String
            public let unit: String
            public let comparator: String
            public init(decimalText: String, unit: String, comparator: String) {
                self.decimalText = decimalText; self.unit = unit; self.comparator = comparator
            }
            enum CodingKeys: String, CodingKey, CaseIterable {
                case decimalText = "decimal_text"
                case unit, comparator
            }
            public init(from decoder: any Decoder) throws {
                try StrictManifestKeys.require(CodingKeys.self, in: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                decimalText = try container.decode(String.self, forKey: .decimalText)
                unit = try container.decode(String.self, forKey: .unit)
                comparator = try container.decode(String.self, forKey: .comparator)
            }
        }
    }
}
