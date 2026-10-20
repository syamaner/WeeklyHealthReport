import Foundation
import FoodLedgerDomain

/// `pasted-nutrition-label-v2` (`docs/pasted-nutrition-label-reader-v3.md` sections 5.3 and
/// 8.4.6): the retained evidence of a pasted label whose amount columns printed no basis header
/// and whose bases the user chose on the basis sheet. It is v1 plus `basis_choices`, with its own
/// strict coding keys; v1 never gains the field. It reuses v1's nested types.
public struct PastedLabelManifestV2: Codable, Equatable, Sendable {
    public static let version = "pasted-nutrition-label-v2"

    /// One record per asserted amount header, in header order (8.4.6).
    public struct BasisChoice: Codable, Equatable, Sendable {
        public let headerID: String
        /// `per_serving`, `per_100g` or `per_100ml`.
        public let basis: String
        /// The arrangement identifiers the sheet offered, in order (8.4.3).
        public let offered: [String]
        /// Whole milliseconds since 1970 from the injected clock, truncated at stamping.
        public let at: Int64

        public init(headerID: String, basis: String, offered: [String], at: Int64) {
            self.headerID = headerID; self.basis = basis; self.offered = offered; self.at = at
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case headerID = "header_id"
            case basis
            case offered
            case at
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            headerID = try container.decode(String.self, forKey: .headerID)
            basis = try container.decode(String.self, forKey: .basis)
            offered = try container.decode([String].self, forKey: .offered)
            // An integer only: a fractional number does not fit `Int64` and throws.
            at = try container.decode(Int64.self, forKey: .at)
        }
    }

    public let version: String
    public let pastedText: String
    public let pastedTextSHA256: String
    public let parserVersion: String
    public let gateVersion: String
    public let arithmeticVersion: String
    public let conversionVersion: String
    public let labelFormat: String
    public let launchScope: [String]
    public let identityMapping: PastedLabelManifest.IdentityMapping
    public let candidate: PastedLabelManifest.Candidate
    public let storedHeaderID: String
    public let conversions: [PastedLabelManifest.Conversion]
    public let flagsShown: [PastedLabelManifest.Flag]
    public let corrections: [PastedLabelManifest.Correction]
    public let warningsShown: [String]
    public let name: String
    public let brand: String?
    public let basisChoices: [BasisChoice]

    public init(pastedText: String, pastedTextSHA256: String, parserVersion: String, gateVersion: String,
                arithmeticVersion: String, conversionVersion: String, labelFormat: String, launchScope: [String],
                identityMapping: PastedLabelManifest.IdentityMapping, candidate: PastedLabelManifest.Candidate, storedHeaderID: String,
                conversions: [PastedLabelManifest.Conversion], flagsShown: [PastedLabelManifest.Flag],
                corrections: [PastedLabelManifest.Correction], warningsShown: [String], name: String, brand: String?,
                basisChoices: [BasisChoice]) {
        version = Self.version
        self.pastedText = pastedText; self.pastedTextSHA256 = pastedTextSHA256
        self.parserVersion = parserVersion; self.gateVersion = gateVersion
        self.arithmeticVersion = arithmeticVersion; self.conversionVersion = conversionVersion
        self.labelFormat = labelFormat; self.launchScope = launchScope; self.identityMapping = identityMapping
        self.candidate = candidate; self.storedHeaderID = storedHeaderID; self.conversions = conversions
        self.flagsShown = flagsShown; self.corrections = corrections; self.warningsShown = warningsShown
        self.name = name; self.brand = brand.flatMap { $0.isEmpty ? nil : $0 }
        self.basisChoices = basisChoices
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
        case basisChoices = "basis_choices"
    }

    public init(from decoder: any Decoder) throws {
        try StrictManifestKeys.require(CodingKeys.self, optional: [.brand], in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        guard version == Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "Not a pasted-label v2 manifest")
        }
        pastedText = try container.decode(String.self, forKey: .pastedText)
        pastedTextSHA256 = try container.decode(String.self, forKey: .pastedTextSHA256)
        parserVersion = try container.decode(String.self, forKey: .parserVersion)
        gateVersion = try container.decode(String.self, forKey: .gateVersion)
        arithmeticVersion = try container.decode(String.self, forKey: .arithmeticVersion)
        conversionVersion = try container.decode(String.self, forKey: .conversionVersion)
        labelFormat = try container.decode(String.self, forKey: .labelFormat)
        launchScope = try container.decode([String].self, forKey: .launchScope)
        identityMapping = try container.decode(PastedLabelManifest.IdentityMapping.self, forKey: .identityMapping)
        candidate = try container.decode(PastedLabelManifest.Candidate.self, forKey: .candidate)
        storedHeaderID = try container.decode(String.self, forKey: .storedHeaderID)
        conversions = try container.decode([PastedLabelManifest.Conversion].self, forKey: .conversions)
        flagsShown = try container.decode([PastedLabelManifest.Flag].self, forKey: .flagsShown)
        corrections = try container.decode([PastedLabelManifest.Correction].self, forKey: .corrections)
        warningsShown = try container.decode([String].self, forKey: .warningsShown)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        if brand?.isEmpty == true {
            throw DecodingError.dataCorruptedError(forKey: .brand, in: container, debugDescription: "Empty brand member")
        }
        basisChoices = try container.decode([BasisChoice].self, forKey: .basisChoices)
        // A v2 manifest exists only for a choice: never empty.
        guard !basisChoices.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .basisChoices, in: container, debugDescription: "Empty basis choices")
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
        try container.encode(basisChoices, forKey: .basisChoices)
    }
}

/// The one dispatcher over the pasted-label manifest versions (reader v3 section 8.4.6). Stored
/// bytes are decoded by their `version` member into exactly the matching strict type; any other
/// version fails closed. Every shared rule (stored basis, nutrients, corrections, servings,
/// origins, the misread report) reads a manifest through this type, so both versions have one
/// derivation.
public enum PastedLabelEvidenceManifest: Equatable, Sendable, Encodable {
    case v1(PastedLabelManifest)
    case v2(PastedLabelManifestV2)

    /// The capture-method versions this route writes and reads, in order.
    public static let versions = [PastedLabelManifest.version, PastedLabelManifestV2.version]

    public static func isVersion(_ version: String) -> Bool { versions.contains(version) }

    public static func decode(_ data: Data) -> PastedLabelEvidenceManifest? {
        struct Probe: Decodable { let version: String }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let probe = try? decoder.decode(Probe.self, from: data) else { return nil }
        switch probe.version {
        case PastedLabelManifest.version: return PastedLabelManifest.decode(data).map(Self.v1)
        case PastedLabelManifestV2.version: return (try? decoder.decode(PastedLabelManifestV2.self, from: data)).map(Self.v2)
        default: return nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case let .v1(manifest): try manifest.encode(to: encoder)
        case let .v2(manifest): try manifest.encode(to: encoder)
        }
    }

    public var version: String { switch self { case let .v1(m): m.version; case let .v2(m): m.version } }
    public var pastedText: String { switch self { case let .v1(m): m.pastedText; case let .v2(m): m.pastedText } }
    public var pastedTextSHA256: String { switch self { case let .v1(m): m.pastedTextSHA256; case let .v2(m): m.pastedTextSHA256 } }
    public var parserVersion: String { switch self { case let .v1(m): m.parserVersion; case let .v2(m): m.parserVersion } }
    public var gateVersion: String { switch self { case let .v1(m): m.gateVersion; case let .v2(m): m.gateVersion } }
    public var arithmeticVersion: String { switch self { case let .v1(m): m.arithmeticVersion; case let .v2(m): m.arithmeticVersion } }
    public var conversionVersion: String { switch self { case let .v1(m): m.conversionVersion; case let .v2(m): m.conversionVersion } }
    public var labelFormat: String { switch self { case let .v1(m): m.labelFormat; case let .v2(m): m.labelFormat } }
    public var launchScope: [String] { switch self { case let .v1(m): m.launchScope; case let .v2(m): m.launchScope } }
    public var identityMapping: PastedLabelManifest.IdentityMapping {
        switch self { case let .v1(m): m.identityMapping; case let .v2(m): m.identityMapping }
    }
    public var candidate: PastedLabelManifest.Candidate { switch self { case let .v1(m): m.candidate; case let .v2(m): m.candidate } }
    public var storedHeaderID: String { switch self { case let .v1(m): m.storedHeaderID; case let .v2(m): m.storedHeaderID } }
    public var conversions: [PastedLabelManifest.Conversion] { switch self { case let .v1(m): m.conversions; case let .v2(m): m.conversions } }
    public var flagsShown: [PastedLabelManifest.Flag] { switch self { case let .v1(m): m.flagsShown; case let .v2(m): m.flagsShown } }
    public var corrections: [PastedLabelManifest.Correction] { switch self { case let .v1(m): m.corrections; case let .v2(m): m.corrections } }
    public var warningsShown: [String] { switch self { case let .v1(m): m.warningsShown; case let .v2(m): m.warningsShown } }
    public var name: String { switch self { case let .v1(m): m.name; case let .v2(m): m.name } }
    public var brand: String? { switch self { case let .v1(m): m.brand; case let .v2(m): m.brand } }
    /// Empty for v1.
    public var basisChoices: [PastedLabelManifestV2.BasisChoice] {
        switch self { case .v1: []; case let .v2(m): m.basisChoices }
    }

    /// Where the stored column's basis came from (8.4.11): printed for v1, chosen for v2.
    public var basisOrigin: PastedLabelBasisOrigin { PastedLabelBasisOrigin(self) }
}
