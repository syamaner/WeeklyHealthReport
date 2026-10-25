import Foundation
import FoodLedgerDomain

/// `label-photo-ai-v1` (docs/label-photo-ai-prefill-v1.md 8.1): the retained evidence of a label
/// photo read by AI, stored verbatim as canonical JSON and verified against itself (8.2). Every
/// member is required, no other member is admitted, and an absent optional value is an explicit
/// `null` (`brand` alone is omitted when empty, as in the pasted manifests). It reuses the pasted
/// manifest's candidate, identity mapping, conversion, flag and correction types (17.1). It holds
/// no key, no device or account identifier, no original image and no crop coordinates.
public struct LabelPhotoManifest: Codable, Equatable, Sendable {
    public static let version = "label-photo-ai-v1"
    public static let routeVersion = "label-photo-ai-route-v1"
    public static let preparationVersion = "label-photo-preparation-v1"
    public static let instructionVersion = "label-photo-instruction-v1"
    public static let servingVersion = "label-photo-serving-v1"
    public static let consistencyVersion = "label-photo-serving-consistency-v1"
    public static let mediaType = "image/jpeg"
    /// The longest `wire_text` kept (8.1).
    public static let maximumWireBytes = 65_536

    // MARK: Nested records

    public struct Image: Codable, Equatable, Sendable {
        public let sha256: String
        public let byteCount: Int
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let mediaType: String
        public let preparationVersion: String
        /// Decimal text, for example `0.8`.
        public let jpegQuality: String

        public init(sha256: String, byteCount: Int, pixelWidth: Int, pixelHeight: Int, mediaType: String = LabelPhotoManifest.mediaType,
                    preparationVersion: String = LabelPhotoManifest.preparationVersion, jpegQuality: String) {
            self.sha256 = sha256; self.byteCount = byteCount; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
            self.mediaType = mediaType; self.preparationVersion = preparationVersion; self.jpegQuality = jpegQuality
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case sha256, byteCount = "byte_count", pixelWidth = "pixel_width", pixelHeight = "pixel_height", mediaType = "media_type"
            case preparationVersion = "preparation_version", jpegQuality = "jpeg_quality"
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sha256 = try c.decode(String.self, forKey: .sha256); byteCount = try c.decode(Int.self, forKey: .byteCount)
            pixelWidth = try c.decode(Int.self, forKey: .pixelWidth); pixelHeight = try c.decode(Int.self, forKey: .pixelHeight)
            mediaType = try c.decode(String.self, forKey: .mediaType)
            preparationVersion = try c.decode(String.self, forKey: .preparationVersion)
            jpegQuality = try c.decode(String.self, forKey: .jpegQuality)
        }
    }

    /// What the free catalogue request showed on the day (E7, 17.5).
    public struct CatalogueCheck: Codable, Equatable, Sendable {
        /// Whole milliseconds since 1970 from the injected clock.
        public let at: Int64
        public let slug: String
        public let endpoint: String
        public let inputModalities: [String]
        public let zeroDataRetention: Bool
        /// Decimal text in USD per token, as listed.
        public let promptPrice: String
        public let completionPrice: String

        public init(at: Int64, slug: String, endpoint: String, inputModalities: [String], zeroDataRetention: Bool, promptPrice: String,
                    completionPrice: String) {
            self.at = at; self.slug = slug; self.endpoint = endpoint; self.inputModalities = inputModalities
            self.zeroDataRetention = zeroDataRetention; self.promptPrice = promptPrice; self.completionPrice = completionPrice
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case at, slug, endpoint, inputModalities = "input_modalities", zeroDataRetention = "zero_data_retention"
            case promptPrice = "prompt_price", completionPrice = "completion_price"
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            at = try c.decode(Int64.self, forKey: .at); slug = try c.decode(String.self, forKey: .slug)
            endpoint = try c.decode(String.self, forKey: .endpoint)
            inputModalities = try c.decode([String].self, forKey: .inputModalities)
            zeroDataRetention = try c.decode(Bool.self, forKey: .zeroDataRetention)
            promptPrice = try c.decode(String.self, forKey: .promptPrice)
            completionPrice = try c.decode(String.self, forKey: .completionPrice)
        }
    }

    public struct Request: Codable, Equatable, Sendable {
        public let model: String
        public let endpoint: String
        /// The reasoning token limit as sent (17.5).
        public let reasoningLimit: Int
        public let maxOutputTokens: Int
        public let instructionVersion: String
        public let instructionSHA256: String
        public let wireSchemaVersion: String
        public let wireSchemaSHA256: String
        public let catalogueCheck: CatalogueCheck

        public init(model: String, endpoint: String, reasoningLimit: Int, maxOutputTokens: Int, instructionVersion: String,
                    instructionSHA256: String, wireSchemaVersion: String, wireSchemaSHA256: String, catalogueCheck: CatalogueCheck) {
            self.model = model; self.endpoint = endpoint; self.reasoningLimit = reasoningLimit; self.maxOutputTokens = maxOutputTokens
            self.instructionVersion = instructionVersion; self.instructionSHA256 = instructionSHA256
            self.wireSchemaVersion = wireSchemaVersion; self.wireSchemaSHA256 = wireSchemaSHA256; self.catalogueCheck = catalogueCheck
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case model, endpoint, reasoningLimit = "reasoning_limit", maxOutputTokens = "max_output_tokens"
            case instructionVersion = "instruction_version", instructionSHA256 = "instruction_sha256"
            case wireSchemaVersion = "wire_schema_version", wireSchemaSHA256 = "wire_schema_sha256", catalogueCheck = "catalogue_check"
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            model = try c.decode(String.self, forKey: .model); endpoint = try c.decode(String.self, forKey: .endpoint)
            reasoningLimit = try c.decode(Int.self, forKey: .reasoningLimit); maxOutputTokens = try c.decode(Int.self, forKey: .maxOutputTokens)
            instructionVersion = try c.decode(String.self, forKey: .instructionVersion)
            instructionSHA256 = try c.decode(String.self, forKey: .instructionSHA256)
            wireSchemaVersion = try c.decode(String.self, forKey: .wireSchemaVersion)
            wireSchemaSHA256 = try c.decode(String.self, forKey: .wireSchemaSHA256)
            catalogueCheck = try c.decode(CatalogueCheck.self, forKey: .catalogueCheck)
        }
    }

    public struct Usage: Codable, Equatable, Sendable {
        public static let unknownCost = "unknown"
        public let promptTokens: Int?
        public let completionTokens: Int?
        public let reasoningTokens: Int?
        /// Decimal text in USD, or `unknown`; never zero for an unreported cost (invariant 11).
        public let costUSD: String

        public init(promptTokens: Int?, completionTokens: Int?, reasoningTokens: Int?, costUSD: String) {
            self.promptTokens = promptTokens; self.completionTokens = completionTokens; self.reasoningTokens = reasoningTokens
            self.costUSD = costUSD
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case promptTokens = "prompt_tokens", completionTokens = "completion_tokens", reasoningTokens = "reasoning_tokens"
            case costUSD = "cost_usd"
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            promptTokens = try c.decodeIfPresent(Int.self, forKey: .promptTokens)
            completionTokens = try c.decodeIfPresent(Int.self, forKey: .completionTokens)
            reasoningTokens = try c.decodeIfPresent(Int.self, forKey: .reasoningTokens)
            costUSD = try c.decode(String.self, forKey: .costUSD)
            guard costUSD == Self.unknownCost || LabelPhotoManifest.isDecimalText(costUSD) else {
                throw DecodingError.dataCorruptedError(forKey: .costUSD, in: c, debugDescription: "Cost is decimal text or unknown")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(promptTokens, forKey: .promptTokens); try c.encode(completionTokens, forKey: .completionTokens)
            try c.encode(reasoningTokens, forKey: .reasoningTokens); try c.encode(costUSD, forKey: .costUSD)
        }
    }

    public struct Response: Codable, Equatable, Sendable {
        public let model: String
        public let provider: String
        public let generationID: String
        public let finishReason: String
        public let attempts: Int
        public let usage: Usage
        /// Whole milliseconds since 1970 from the injected clock.
        public let requestedAt: Int64
        public let completedAt: Int64
        /// The model's JSON answer, verbatim.
        public let wireText: String
        public let wireSHA256: String

        public init(model: String, provider: String, generationID: String, finishReason: String, attempts: Int, usage: Usage,
                    requestedAt: Int64, completedAt: Int64, wireText: String, wireSHA256: String) {
            self.model = model; self.provider = provider; self.generationID = generationID; self.finishReason = finishReason
            self.attempts = attempts; self.usage = usage; self.requestedAt = requestedAt; self.completedAt = completedAt
            self.wireText = wireText; self.wireSHA256 = wireSHA256
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case model, provider, generationID = "generation_id", finishReason = "finish_reason", attempts, usage
            case requestedAt = "requested_at", completedAt = "completed_at", wireText = "wire_text", wireSHA256 = "wire_sha256"
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            model = try c.decode(String.self, forKey: .model); provider = try c.decode(String.self, forKey: .provider)
            generationID = try c.decode(String.self, forKey: .generationID); finishReason = try c.decode(String.self, forKey: .finishReason)
            attempts = try c.decode(Int.self, forKey: .attempts); usage = try c.decode(Usage.self, forKey: .usage)
            requestedAt = try c.decode(Int64.self, forKey: .requestedAt); completedAt = try c.decode(Int64.self, forKey: .completedAt)
            wireText = try c.decode(String.self, forKey: .wireText); wireSHA256 = try c.decode(String.self, forKey: .wireSHA256)
        }
    }

    /// A normalised rectangle on the prepared image, as decimal text (8.1).
    public struct Region: Codable, Equatable, Sendable {
        public let x: String, y: String, w: String, h: String
        public init(x: String, y: String, w: String, h: String) { self.x = x; self.y = y; self.w = w; self.h = h }
        enum CodingKeys: String, CodingKey, CaseIterable { case x, y, w, h }
        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            x = try c.decode(String.self, forKey: .x); y = try c.decode(String.self, forKey: .y)
            w = try c.decode(String.self, forKey: .w); h = try c.decode(String.self, forKey: .h)
        }

        /// Inside the unit square, with a positive width and height.
        public var isInsideUnitSquare: Bool {
            guard let x = LabelPhotoManifest.decimal(x), let y = LabelPhotoManifest.decimal(y), let w = LabelPhotoManifest.decimal(w),
                  let h = LabelPhotoManifest.decimal(h) else { return false }
            return x >= 0 && y >= 0 && w > 0 && h > 0 && x + w <= 1 && y + h <= 1
        }
    }

    public struct Location: Codable, Equatable, Sendable {
        /// `<row_id>@<header_id>` for a cell, or `serving_size` / `servings_per_pack`.
        public let item: String
        public let status: LabelPhotoAttention.Location
        public let region: Region?

        public init(item: String, status: LabelPhotoAttention.Location, region: Region?) {
            self.item = item; self.status = status; self.region = region
        }

        enum CodingKeys: String, CodingKey, CaseIterable { case item, status, region }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            item = try c.decode(String.self, forKey: .item); status = try c.decode(LabelPhotoAttention.Location.self, forKey: .status)
            region = try c.decodeIfPresent(Region.self, forKey: .region)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(item, forKey: .item); try c.encode(status, forKey: .status); try c.encode(region, forKey: .region)
        }
    }

    public struct Locations: Codable, Equatable, Sendable {
        public let locatorVersion: String
        public let visionRevision: Int
        public let languages: [String]
        public let records: [Location]

        public init(locatorVersion: String, visionRevision: Int, languages: [String], records: [Location]) {
            self.locatorVersion = locatorVersion; self.visionRevision = visionRevision; self.languages = languages; self.records = records
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case locatorVersion = "locator_version", visionRevision = "vision_revision", languages, records
        }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            locatorVersion = try c.decode(String.self, forKey: .locatorVersion); visionRevision = try c.decode(Int.self, forKey: .visionRevision)
            languages = try c.decode([String].self, forKey: .languages); records = try c.decode([Location].self, forKey: .records)
        }
    }

    /// A check that failed when Confirm showed the reading (`label-arithmetic-checks-v2` or the
    /// serving consistency check), recorded so attention can be recomputed without re-running it.
    public struct FailedCheck: Codable, Equatable, Sendable {
        public let name: String, basis: String?, nutrient: String?, child: String?
        public init(name: String, basis: String?, nutrient: String?, child: String?) {
            self.name = name; self.basis = basis; self.nutrient = nutrient; self.child = child
        }
        enum CodingKeys: String, CodingKey, CaseIterable { case name, basis, nutrient, child }
        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name); basis = try c.decodeIfPresent(String.self, forKey: .basis)
            nutrient = try c.decodeIfPresent(String.self, forKey: .nutrient); child = try c.decodeIfPresent(String.self, forKey: .child)
        }
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name); try c.encode(basis, forKey: .basis)
            try c.encode(nutrient, forKey: .nutrient); try c.encode(child, forKey: .child)
        }
        /// The code Confirm shows (`LabelReading.Check.warningCode`).
        public var warningCode: String { ([name] + [basis, nutrient, child].compactMap { $0 }).joined(separator: ":") }
    }

    public struct Attention: Codable, Equatable, Sendable {
        public let item: String
        public let reasons: [LabelPhotoAttention.Reason]
        public let resolution: LabelPhotoAttention.Resolution
        /// Whole milliseconds since 1970 from the injected clock.
        public let at: Int64

        public init(item: String, reasons: [LabelPhotoAttention.Reason], resolution: LabelPhotoAttention.Resolution, at: Int64) {
            self.item = item; self.reasons = reasons; self.resolution = resolution; self.at = at
        }

        enum CodingKeys: String, CodingKey, CaseIterable { case item, reasons, resolution, at }

        public init(from decoder: any Decoder) throws {
            try StrictManifestKeys.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            item = try c.decode(String.self, forKey: .item); reasons = try c.decode([LabelPhotoAttention.Reason].self, forKey: .reasons)
            resolution = try c.decode(LabelPhotoAttention.Resolution.self, forKey: .resolution); at = try c.decode(Int64.self, forKey: .at)
        }
    }

    // MARK: Members

    public let version: String
    public let routeVersion: String
    public let image: Image
    public let request: Request
    public let response: Response
    public let mappingVersion: String
    public let gateVersion: String
    public let arithmeticVersion: String
    public let conversionVersion: String
    public let servingVersion: String
    public let labelFormat: String
    public let launchScope: [String]
    public let identityMapping: PastedLabelManifest.IdentityMapping
    public let candidate: PastedLabelManifest.Candidate
    public let locations: Locations
    public let storedHeaderID: String
    public let basisChoices: [PastedLabelManifestV2.BasisChoice]
    public let conversions: [PastedLabelManifest.Conversion]
    public let flagsShown: [PastedLabelManifest.Flag]
    public let checksFailed: [FailedCheck]
    public let warningsShown: [String]
    public let corrections: [PastedLabelManifest.Correction]
    public let attention: [Attention]
    public let attentionVersion: String
    public let consistencyVersion: String
    public let name: String
    public let brand: String?

    public init(image: Image, request: Request, response: Response, mappingVersion: String, gateVersion: String, arithmeticVersion: String,
                conversionVersion: String, identityMapping: PastedLabelManifest.IdentityMapping, candidate: PastedLabelManifest.Candidate,
                locations: Locations, storedHeaderID: String, conversions: [PastedLabelManifest.Conversion],
                flagsShown: [PastedLabelManifest.Flag], checksFailed: [FailedCheck], warningsShown: [String],
                corrections: [PastedLabelManifest.Correction], attention: [Attention], name: String, brand: String?) {
        version = Self.version; routeVersion = Self.routeVersion
        self.image = image; self.request = request; self.response = response
        self.mappingVersion = mappingVersion; self.gateVersion = gateVersion; self.arithmeticVersion = arithmeticVersion
        self.conversionVersion = conversionVersion; servingVersion = Self.servingVersion
        labelFormat = LabelPhotoReading.labelFormat; launchScope = LabelPhotoReading.launchScope
        self.identityMapping = identityMapping; self.candidate = candidate; self.locations = locations
        self.storedHeaderID = storedHeaderID; basisChoices = []; self.conversions = conversions; self.flagsShown = flagsShown
        self.checksFailed = checksFailed; self.warningsShown = warningsShown; self.corrections = corrections; self.attention = attention
        attentionVersion = LabelPhotoAttention.version; consistencyVersion = Self.consistencyVersion
        self.name = name; self.brand = brand.flatMap { $0.isEmpty ? nil : $0 }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, routeVersion = "route_version", image, request, response
        case mappingVersion = "mapping_version", gateVersion = "gate_version", arithmeticVersion = "arithmetic_version"
        case conversionVersion = "conversion_version", servingVersion = "serving_version"
        case labelFormat = "label_format", launchScope = "launch_scope", identityMapping = "identity_mapping", candidate, locations
        case storedHeaderID = "stored_header_id", basisChoices = "basis_choices", conversions, flagsShown = "flags_shown"
        case checksFailed = "checks_failed", warningsShown = "warnings_shown", corrections, attention
        case attentionVersion = "attention_version", consistencyVersion = "consistency_version", name, brand
    }

    public init(from decoder: any Decoder) throws {
        try StrictManifestKeys.require(CodingKeys.self, optional: [.brand], in: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        guard version == Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "Not a label photo manifest")
        }
        routeVersion = try c.decode(String.self, forKey: .routeVersion)
        image = try c.decode(Image.self, forKey: .image); request = try c.decode(Request.self, forKey: .request)
        response = try c.decode(Response.self, forKey: .response)
        mappingVersion = try c.decode(String.self, forKey: .mappingVersion); gateVersion = try c.decode(String.self, forKey: .gateVersion)
        arithmeticVersion = try c.decode(String.self, forKey: .arithmeticVersion)
        conversionVersion = try c.decode(String.self, forKey: .conversionVersion)
        servingVersion = try c.decode(String.self, forKey: .servingVersion)
        labelFormat = try c.decode(String.self, forKey: .labelFormat); launchScope = try c.decode([String].self, forKey: .launchScope)
        identityMapping = try c.decode(PastedLabelManifest.IdentityMapping.self, forKey: .identityMapping)
        candidate = try c.decode(PastedLabelManifest.Candidate.self, forKey: .candidate)
        locations = try c.decode(Locations.self, forKey: .locations)
        storedHeaderID = try c.decode(String.self, forKey: .storedHeaderID)
        basisChoices = try c.decode([PastedLabelManifestV2.BasisChoice].self, forKey: .basisChoices)
        conversions = try c.decode([PastedLabelManifest.Conversion].self, forKey: .conversions)
        flagsShown = try c.decode([PastedLabelManifest.Flag].self, forKey: .flagsShown)
        checksFailed = try c.decode([FailedCheck].self, forKey: .checksFailed)
        warningsShown = try c.decode([String].self, forKey: .warningsShown)
        corrections = try c.decode([PastedLabelManifest.Correction].self, forKey: .corrections)
        attention = try c.decode([Attention].self, forKey: .attention)
        attentionVersion = try c.decode(String.self, forKey: .attentionVersion)
        consistencyVersion = try c.decode(String.self, forKey: .consistencyVersion)
        name = try c.decode(String.self, forKey: .name); brand = try c.decodeIfPresent(String.self, forKey: .brand)
        if brand?.isEmpty == true {
            throw DecodingError.dataCorruptedError(forKey: .brand, in: c, debugDescription: "Empty brand member")
        }
        // v1 never stores a chosen basis: a photo reading prints its bases (8.1).
        guard basisChoices.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .basisChoices, in: c, debugDescription: "Basis choices on a photo manifest")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version); try c.encode(routeVersion, forKey: .routeVersion)
        try c.encode(image, forKey: .image); try c.encode(request, forKey: .request); try c.encode(response, forKey: .response)
        try c.encode(mappingVersion, forKey: .mappingVersion); try c.encode(gateVersion, forKey: .gateVersion)
        try c.encode(arithmeticVersion, forKey: .arithmeticVersion); try c.encode(conversionVersion, forKey: .conversionVersion)
        try c.encode(servingVersion, forKey: .servingVersion); try c.encode(labelFormat, forKey: .labelFormat)
        try c.encode(launchScope, forKey: .launchScope); try c.encode(identityMapping, forKey: .identityMapping)
        try c.encode(candidate, forKey: .candidate); try c.encode(locations, forKey: .locations)
        try c.encode(storedHeaderID, forKey: .storedHeaderID); try c.encode(basisChoices, forKey: .basisChoices)
        try c.encode(conversions, forKey: .conversions); try c.encode(flagsShown, forKey: .flagsShown)
        try c.encode(checksFailed, forKey: .checksFailed); try c.encode(warningsShown, forKey: .warningsShown)
        try c.encode(corrections, forKey: .corrections); try c.encode(attention, forKey: .attention)
        try c.encode(attentionVersion, forKey: .attentionVersion); try c.encode(consistencyVersion, forKey: .consistencyVersion)
        try c.encode(name, forKey: .name); try c.encodeIfPresent(brand, forKey: .brand)
    }

    /// Stored manifest bytes decoded strictly, with the canonical date strategy; nil otherwise.
    public static func decode(_ data: Data) -> LabelPhotoManifest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(Self.self, from: data)
    }

    // MARK: Decimal text

    /// Plain decimal text: ASCII digits with at most one point, not starting or ending with it.
    static func isDecimalText(_ text: String) -> Bool { decimal(text) != nil }

    static func decimal(_ text: String) -> Double? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), text.filter({ $0 == "." }).count <= 1,
              text.first?.isNumber == true, text.last?.isNumber == true, let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// The attention identifier of a cell.
    public static func cellItem(rowID: String, headerID: String) -> String { rowID + "@" + headerID }
}
