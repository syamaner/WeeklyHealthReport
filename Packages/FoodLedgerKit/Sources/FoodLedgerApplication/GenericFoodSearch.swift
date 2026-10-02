import Foundation
import FoodLedgerDomain

public struct GenericFoodIdentityQuery: Equatable, Sendable {
    // These are the affirmative cooking descriptors emitted by parser v5.
    // Translation to a broad state does not erase the method from retrieval.
    fileprivate static let parsedCookingMethods: Set<String> = ["soft-boiled", "boiled", "pan-fried", "roasted"]
    public static func preparationKind(forParsedDescriptor descriptor: String?) -> PreparationKind? {
        guard let descriptor else { return nil }
        if parsedCookingMethods.contains(descriptor) { return .cooked }
        return PreparationKind(rawValue: descriptor)
    }

    public let preparation: PreparationState?
    public let bone: BoneState?
    public let skin: SkinState?
    public let drained: DrainedState?
    public let packingMedium: PackingMediumState?
    public let fortification: FortificationState?
    public let servingBasis: ResolutionBasis?
    public let edibleQuantity: EdibleQuantityIdentity?
    public let saltState: LedgerText?
    public let formulation: LedgerText?

    public init(
        preparation: PreparationState? = nil,
        bone: BoneState? = nil,
        skin: SkinState? = nil,
        drained: DrainedState? = nil,
        packingMedium: PackingMediumState? = nil,
        fortification: FortificationState? = nil,
        servingBasis: ResolutionBasis? = nil,
        edibleQuantity: EdibleQuantityIdentity? = nil,
        saltState: LedgerText? = nil,
        formulation: LedgerText? = nil
    ) {
        self.preparation = preparation
        self.bone = bone
        self.skin = skin
        self.drained = drained
        self.packingMedium = packingMedium
        self.fortification = fortification
        self.servingBasis = servingBasis
        self.edibleQuantity = edibleQuantity
        self.saltState = saltState
        self.formulation = formulation
    }
}

public struct GenericFoodSearchRequest: Equatable, Sendable {
    public let interpretation: FoodQueryInterpretation
    public var parsedQuery: ParsedFoodQuery { interpretation.parsedQuery }
    public var retrievalText: String { interpretation.retrievalText }
    public let text: LedgerText
    public let identity: GenericFoodIdentityQuery
    public let capturedAt: Date
    public let locale: LedgerText
    public let captureEvidence: CaptureEvidence?
    public let additionalEvidence: [CaptureEvidence]

    public init(
        text: LedgerText,
        identity: GenericFoodIdentityQuery = GenericFoodIdentityQuery(),
        capturedAt: Date,
        locale: LedgerText,
        captureEvidence: CaptureEvidence? = nil,
        additionalEvidence: [CaptureEvidence] = [],
        interpretation: FoodQueryInterpretation? = nil
    ) {
        self.text = text
        // A caller cannot attach another query's interpretation.
        let interpretation = interpretation?.originalText == text.value ? interpretation! : FoodQueryInterpretation(text.value)
        self.interpretation = interpretation
        if (identity.preparation == nil || identity.preparation?.kind == .unknown),
           let kind = interpretation.preparation,
           let preparation = try? PreparationState(kind: kind) {
            self.identity = GenericFoodIdentityQuery(preparation: preparation, bone: identity.bone,
                skin: identity.skin, drained: identity.drained, packingMedium: identity.packingMedium,
                fortification: identity.fortification, servingBasis: identity.servingBasis,
                edibleQuantity: identity.edibleQuantity, saltState: identity.saltState, formulation: identity.formulation)
        } else { self.identity = identity }
        self.capturedAt = capturedAt
        self.locale = locale
        self.captureEvidence = captureEvidence
        self.additionalEvidence = additionalEvidence
    }
}

public struct GenericFoodMatch: Equatable, Sendable {
    public let candidate: PopulatedFoodCandidate
    public let isExactName: Bool

    public init(candidate: PopulatedFoodCandidate, isExactName: Bool) {
        self.candidate = candidate
        self.isExactName = isExactName
    }
}

public struct GenericFoodConfirmationRoute: Equatable, Sendable {
    public let confirmation: PopulatedFoodConfirmation
    public let matches: [GenericFoodMatch]
    public let reuse: BarcodeReuseReference?
    public let sourceDiscovery: FoodWebDiscoveryResult?
    public let sourceReviewFailure: FoodSourceReviewFailure?

    public init(
        confirmation: PopulatedFoodConfirmation,
        matches: [GenericFoodMatch],
        reuse: BarcodeReuseReference? = nil, sourceDiscovery: FoodWebDiscoveryResult? = nil, sourceReviewFailure: FoodSourceReviewFailure? = nil
    ) {
        self.confirmation = confirmation
        self.matches = matches
        self.reuse = reuse
        self.sourceDiscovery = sourceDiscovery
        self.sourceReviewFailure = sourceReviewFailure
    }
}

public struct GenericFoodNoResultRoute: Equatable, Sendable {
    public let evidence: CaptureEvidence
    public let retainedEvidence: [CaptureEvidence]
    public let title: String
    public let guidance: String
    public let suggestedQueries: [String]
    public let sourceDiscovery: FoodWebDiscoveryResult?
    public let sourceReviewFailure: FoodSourceReviewFailure?

    public init(
        evidence: CaptureEvidence, additionalEvidence: [CaptureEvidence] = [],
        guidance: String? = nil, suggestedQueries: [String] = [], sourceDiscovery: FoodWebDiscoveryResult? = nil, sourceReviewFailure: FoodSourceReviewFailure? = nil
    ) {
        self.evidence = evidence
        self.suggestedQueries = suggestedQueries
        self.sourceDiscovery = sourceDiscovery
        self.sourceReviewFailure = sourceReviewFailure
        retainedEvidence = [evidence] + additionalEvidence
        title = "No compatible generic food found"
        self.guidance = guidance ?? "Try another food name or leave this item unresolved. Nothing has been selected or saved."
    }
}

public enum GenericFoodSearchOutcome: Equatable, Sendable {
    case confirmation(GenericFoodConfirmationRoute)
    case noResult(GenericFoodNoResultRoute)
}

public protocol GenericFoodSearching: Sendable {
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome
}

public protocol GenericFoodLibrarySearching: Sendable {
    func exactMatches(alias: LedgerText) throws -> [BarcodeLibraryRecord]
}

public struct PersonalLibraryGenericFoodSearch: GenericFoodLibrarySearching, Sendable {
    private let reader: any LedgerReading

    public init(reader: any LedgerReading) {
        self.reader = reader
    }

    public func exactMatches(alias: LedgerText) throws -> [BarcodeLibraryRecord] {
        try reader.barcodeLibraryRecords(alias: alias)
    }
}
