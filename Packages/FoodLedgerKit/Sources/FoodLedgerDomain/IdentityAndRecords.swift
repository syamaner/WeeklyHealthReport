import Foundation

public enum ItemClass: String, Codable, Sendable {
    case food
    case fortifiedFood = "fortified_food"
    case supplement
    case drink
    case water
}

public enum PreparationKind: String, Codable, Sendable {
    case asSold = "as_sold"
    case raw
    case cooked
    case reheated
    case named
    case unknown
}

public struct PreparationState: Codable, Equatable, Sendable {
    public let kind: PreparationKind
    public let method: LedgerText?

    public init(kind: PreparationKind, method: LedgerText? = nil) throws {
        guard (kind == .named) == (method != nil) else {
            throw FoodLedgerValidationError.invalidBasis
        }
        self.kind = kind
        self.method = method
    }
}

public enum BoneState: String, Codable, Sendable {
    case withBone = "with_bone"
    case boneless
    case notApplicable = "not_applicable"
    case unknown
}

public enum SkinState: String, Codable, Sendable {
    case skinOn = "skin_on"
    case skinless
    case notApplicable = "not_applicable"
    case unknown
}

public enum DrainedState: String, Codable, Sendable {
    case drained
    case undrained
    case notApplicable = "not_applicable"
    case unknown
}

public enum FortificationState: String, Codable, Sendable {
    case fortified
    case unfortified
    case unknown
}

public enum PackingMediumState: Codable, Equatable, Sendable {
    case named(LedgerText)
    case unknown
}

public enum EdibleQuantityIdentity: Codable, Equatable, Sendable {
    case known(PositiveQuantity, conversionVersionID: QuantityConversionVersionID?)
    case unknown
}

public struct DecisiveIdentity: Codable, Equatable, Sendable {
    public let preparation: PreparationState
    public let bone: BoneState
    public let skin: SkinState
    public let drained: DrainedState
    public let packingMedium: PackingMediumState
    public let fortification: FortificationState
    public let declaredFortificants: [NutrientKey]
    public let servingBasis: ResolutionBasis

    public init(
        preparation: PreparationState,
        bone: BoneState,
        skin: SkinState,
        drained: DrainedState,
        packingMedium: PackingMediumState,
        fortification: FortificationState,
        declaredFortificants: [NutrientKey] = [],
        servingBasis: ResolutionBasis
    ) throws {
        guard fortification == .fortified || declaredFortificants.isEmpty else {
            throw FoodLedgerValidationError.invalidBasis
        }
        guard Set(declaredFortificants).count == declaredFortificants.count else {
            throw FoodLedgerValidationError.duplicateValue("declared fortificants")
        }
        self.preparation = preparation
        self.bone = bone
        self.skin = skin
        self.drained = drained
        self.packingMedium = packingMedium
        self.fortification = fortification
        self.declaredFortificants = declaredFortificants
        self.servingBasis = servingBasis
    }
}

public enum IdentityContradiction: String, Codable, CaseIterable, Sendable {
    case preparation
    case bone
    case skin
    case drained
    case packingMedium = "packing_medium"
    case fortification
    case servingBasis = "serving_basis"
    case edibleQuantity = "edible_quantity"
}

public enum IdentityCompatibility {
    public static func contradictions(
        between expected: DecisiveIdentity,
        and candidate: DecisiveIdentity,
        expectedEdibleQuantity: EdibleQuantityIdentity,
        candidateEdibleQuantity: EdibleQuantityIdentity
    ) -> [IdentityContradiction] {
        var result: [IdentityContradiction] = []
        if expected.preparation.kind == .unknown || candidate.preparation.kind == .unknown
            || expected.preparation != candidate.preparation {
            result.append(.preparation)
        }
        if expected.bone == .unknown || candidate.bone == .unknown || expected.bone != candidate.bone {
            result.append(.bone)
        }
        if expected.skin == .unknown || candidate.skin == .unknown || expected.skin != candidate.skin {
            result.append(.skin)
        }
        if expected.drained == .unknown || candidate.drained == .unknown
            || expected.drained != candidate.drained {
            result.append(.drained)
        }
        if expected.packingMedium == .unknown || candidate.packingMedium == .unknown
            || expected.packingMedium != candidate.packingMedium {
            result.append(.packingMedium)
        }
        if expected.fortification == .unknown || candidate.fortification == .unknown
            || expected.fortification != candidate.fortification {
            result.append(.fortification)
        }
        if expected.servingBasis == .unknown || candidate.servingBasis == .unknown
            || expected.servingBasis != candidate.servingBasis {
            result.append(.servingBasis)
        }
        if expectedEdibleQuantity == .unknown || candidateEdibleQuantity == .unknown
            || expectedEdibleQuantity != candidateEdibleQuantity {
            result.append(.edibleQuantity)
        }
        return result
    }
}

public struct AttachmentDescriptor: Codable, Hashable, Sendable {
    public let sha256: SHA256Digest
    public let mediaKind: LedgerText
    public let byteCount: Int
    public let relativePath: LedgerText

    public init(
        sha256: SHA256Digest,
        mediaKind: LedgerText,
        byteCount: Int,
        relativePath: LedgerText
    ) throws {
        guard byteCount > 0 else { throw FoodLedgerValidationError.nonPositive("byte count") }
        guard !relativePath.value.hasPrefix("/"),
              !relativePath.value.split(separator: "/").contains("..") else {
            throw FoodLedgerValidationError.invalidIdentifier(relativePath.value)
        }
        self.sha256 = sha256
        self.mediaKind = mediaKind
        self.byteCount = byteCount
        self.relativePath = relativePath
    }
}

public enum CaptureKind: String, Codable, Sendable {
    case barcode
    case labelText = "label_text"
    case packageImage = "package_image"
    case manual
    case synthetic
}

public enum CapturePayload: Codable, Equatable, Sendable {
    case barcode(value: LedgerText, symbology: LedgerText)
    case text(LedgerText)
    case descriptor(LedgerText)
}

public struct CaptureEvidence: Codable, Equatable, Sendable {
    public let evidenceID: EvidenceID
    public let kind: CaptureKind
    public let capturedAt: Date
    public let locale: LedgerText
    public let captureMethod: LedgerText
    public let captureMethodVersion: LedgerText
    public let originalPayload: CapturePayload
    public let byteHash: SHA256Digest?
    public let attachment: AttachmentDescriptor?

    public init(
        evidenceID: EvidenceID,
        kind: CaptureKind,
        capturedAt: Date,
        locale: LedgerText,
        captureMethod: LedgerText,
        captureMethodVersion: LedgerText,
        originalPayload: CapturePayload,
        byteHash: SHA256Digest? = nil,
        attachment: AttachmentDescriptor? = nil
    ) throws {
        guard attachment?.sha256 == byteHash || attachment == nil else {
            throw FoodLedgerValidationError.invalidDigest
        }
        self.evidenceID = evidenceID
        self.kind = kind
        self.capturedAt = capturedAt
        self.locale = locale
        self.captureMethod = captureMethod
        self.captureMethodVersion = captureMethodVersion
        self.originalPayload = originalPayload
        self.byteHash = byteHash
        self.attachment = attachment
    }
}

public enum AssertionAuthor: Codable, Equatable, Sendable {
    case user
    case process(LedgerText)
}

public struct UserAssertion: Codable, Equatable, Sendable {
    public let assertionID: AssertionID
    public let evidenceID: EvidenceID?
    public let supersedesAssertionID: AssertionID?
    public let author: AssertionAuthor
    public let createdAt: Date
    public let reason: LedgerText
    public let claim: LedgerText

    public init(
        assertionID: AssertionID,
        evidenceID: EvidenceID? = nil,
        supersedesAssertionID: AssertionID? = nil,
        author: AssertionAuthor,
        createdAt: Date,
        reason: LedgerText,
        claim: LedgerText
    ) {
        self.assertionID = assertionID
        self.evidenceID = evidenceID
        self.supersedesAssertionID = supersedesAssertionID
        self.author = author
        self.createdAt = createdAt
        self.reason = reason
        self.claim = claim
    }
}

public struct PackFacts: Codable, Equatable, Sendable {
    public let netQuantity: PositiveQuantity?
    public let drainedQuantity: PositiveQuantity?
    public let edibleQuantity: PositiveQuantity?

    public init(
        netQuantity: PositiveQuantity? = nil,
        drainedQuantity: PositiveQuantity? = nil,
        edibleQuantity: PositiveQuantity? = nil
    ) {
        self.netQuantity = netQuantity
        self.drainedQuantity = drainedQuantity
        self.edibleQuantity = edibleQuantity
    }
}

public struct Product: Codable, Equatable, Sendable {
    public let productID: ProductID
    public let createdAt: Date

    public init(productID: ProductID, createdAt: Date) {
        self.productID = productID
        self.createdAt = createdAt
    }
}

public struct ProductVersion: Codable, Equatable, Sendable {
    public let productVersionID: ProductVersionID
    public let productID: ProductID
    public let ordinal: VersionOrdinal
    public let supersedesProductVersionID: ProductVersionID?
    public let name: LedgerText
    public let brand: LedgerText?
    public let variant: LedgerText?
    public let barcode: LedgerText?
    public let itemClass: ItemClass
    public let packFacts: PackFacts
    public let identity: DecisiveIdentity
    public let evidenceIDs: [EvidenceID]
    public let assertionIDs: [AssertionID]
    public let createdAt: Date

    public init(
        productVersionID: ProductVersionID,
        productID: ProductID,
        ordinal: VersionOrdinal,
        supersedesProductVersionID: ProductVersionID? = nil,
        name: LedgerText,
        brand: LedgerText? = nil,
        variant: LedgerText? = nil,
        barcode: LedgerText? = nil,
        itemClass: ItemClass,
        packFacts: PackFacts,
        identity: DecisiveIdentity,
        evidenceIDs: [EvidenceID],
        assertionIDs: [AssertionID],
        createdAt: Date
    ) throws {
        guard !evidenceIDs.isEmpty || !assertionIDs.isEmpty else {
            throw FoodLedgerValidationError.empty("product evidence")
        }
        guard Set(evidenceIDs).count == evidenceIDs.count,
              Set(assertionIDs).count == assertionIDs.count else {
            throw FoodLedgerValidationError.duplicateValue("product references")
        }
        switch itemClass {
        case .fortifiedFood:
            guard identity.fortification == .fortified else {
                throw FoodLedgerValidationError.invalidBasis
            }
        case .food, .drink, .water:
            guard identity.fortification != .fortified else {
                throw FoodLedgerValidationError.invalidBasis
            }
        case .supplement:
            break
        }
        self.productVersionID = productVersionID
        self.productID = productID
        self.ordinal = ordinal
        self.supersedesProductVersionID = supersedesProductVersionID
        self.name = name
        self.brand = brand
        self.variant = variant
        self.barcode = barcode
        self.itemClass = itemClass
        self.packFacts = packFacts
        self.identity = identity
        self.evidenceIDs = evidenceIDs
        self.assertionIDs = assertionIDs
        self.createdAt = createdAt
    }
}

public struct LibraryEntry: Codable, Equatable, Sendable {
    public let libraryEntryID: LibraryEntryID
    public let createdAt: Date

    public init(libraryEntryID: LibraryEntryID, createdAt: Date) {
        self.libraryEntryID = libraryEntryID
        self.createdAt = createdAt
    }
}

public struct LibraryEntryVersion: Codable, Equatable, Sendable {
    public let libraryEntryVersionID: LibraryEntryVersionID
    public let libraryEntryID: LibraryEntryID
    public let ordinal: VersionOrdinal
    public let supersedesLibraryEntryVersionID: LibraryEntryVersionID?
    public let productVersionID: ProductVersionID
    public let aliases: [LedgerText]
    public let reusableQuantity: PositiveQuantity?
    public let quantityConversionVersionID: QuantityConversionVersionID?
    public let createdAt: Date

    public init(
        libraryEntryVersionID: LibraryEntryVersionID,
        libraryEntryID: LibraryEntryID,
        ordinal: VersionOrdinal,
        supersedesLibraryEntryVersionID: LibraryEntryVersionID? = nil,
        productVersionID: ProductVersionID,
        aliases: [LedgerText],
        reusableQuantity: PositiveQuantity? = nil,
        quantityConversionVersionID: QuantityConversionVersionID? = nil,
        createdAt: Date
    ) throws {
        guard !aliases.isEmpty else { throw FoodLedgerValidationError.empty("aliases") }
        guard Set(aliases).count == aliases.count else {
            throw FoodLedgerValidationError.duplicateValue("aliases")
        }
        self.libraryEntryVersionID = libraryEntryVersionID
        self.libraryEntryID = libraryEntryID
        self.ordinal = ordinal
        self.supersedesLibraryEntryVersionID = supersedesLibraryEntryVersionID
        self.productVersionID = productVersionID
        self.aliases = aliases
        self.reusableQuantity = reusableQuantity
        self.quantityConversionVersionID = quantityConversionVersionID
        self.createdAt = createdAt
    }
}

public struct NutritionResolution: Codable, Equatable, Sendable {
    public let resolutionID: ResolutionID
    public let productVersionID: ProductVersionID
    public let basis: ResolutionBasis
    public let createdAt: Date

    public init(
        resolutionID: ResolutionID,
        productVersionID: ProductVersionID,
        basis: ResolutionBasis,
        createdAt: Date
    ) {
        self.resolutionID = resolutionID
        self.productVersionID = productVersionID
        self.basis = basis
        self.createdAt = createdAt
    }
}

public struct NutritionResolutionVersion: Codable, Equatable, Sendable {
    public let resolutionVersionID: ResolutionVersionID
    public let resolutionID: ResolutionID
    public let ordinal: VersionOrdinal
    public let supersedesResolutionVersionID: ResolutionVersionID?
    public let methodVersion: LedgerText
    public let sourceReleaseIDs: [ExternalIdentifier]
    public let nutrients: NutrientSet
    public let decisionIDs: [CandidateDecisionID]
    public let assertionIDs: [AssertionID]
    public let createdAt: Date

    public init(
        resolutionVersionID: ResolutionVersionID,
        resolutionID: ResolutionID,
        ordinal: VersionOrdinal,
        supersedesResolutionVersionID: ResolutionVersionID? = nil,
        methodVersion: LedgerText,
        sourceReleaseIDs: [ExternalIdentifier],
        nutrients: NutrientSet,
        decisionIDs: [CandidateDecisionID] = [],
        assertionIDs: [AssertionID] = [],
        createdAt: Date
    ) throws {
        guard Set(sourceReleaseIDs).count == sourceReleaseIDs.count,
              Set(decisionIDs).count == decisionIDs.count,
              Set(assertionIDs).count == assertionIDs.count else {
            throw FoodLedgerValidationError.duplicateValue("resolution references")
        }
        self.resolutionVersionID = resolutionVersionID
        self.resolutionID = resolutionID
        self.ordinal = ordinal
        self.supersedesResolutionVersionID = supersedesResolutionVersionID
        self.methodVersion = methodVersion
        self.sourceReleaseIDs = sourceReleaseIDs
        self.nutrients = nutrients
        self.decisionIDs = decisionIDs
        self.assertionIDs = assertionIDs
        self.createdAt = createdAt
    }
}

public enum LogComposition: Codable, Equatable, Sendable {
    case product(ProductVersionID)
    case mixture([LogItemVersionID])
}

public struct LogItem: Codable, Equatable, Sendable {
    public let logItemID: LogItemID
    public let createdAt: Date

    public init(logItemID: LogItemID, createdAt: Date) {
        self.logItemID = logItemID
        self.createdAt = createdAt
    }
}

public struct LogItemVersion: Codable, Equatable, Sendable {
    public let logItemVersionID: LogItemVersionID
    public let logItemID: LogItemID
    public let ordinal: VersionOrdinal
    public let supersedesLogItemVersionID: LogItemVersionID?
    public let occurredAt: Date
    public let reportingDate: LedgerText
    public let composition: LogComposition
    public let edibleQuantity: PositiveQuantity
    public let quantityConversionVersionID: QuantityConversionVersionID?
    public let originalResolutionVersionID: ResolutionVersionID
    public let effectiveResolutionVersionID: ResolutionVersionID
    public let correctionReason: LedgerText?
    public let createdAt: Date

    public init(
        logItemVersionID: LogItemVersionID,
        logItemID: LogItemID,
        ordinal: VersionOrdinal,
        supersedesLogItemVersionID: LogItemVersionID? = nil,
        occurredAt: Date,
        reportingDate: LedgerText,
        composition: LogComposition,
        edibleQuantity: PositiveQuantity,
        quantityConversionVersionID: QuantityConversionVersionID? = nil,
        originalResolutionVersionID: ResolutionVersionID,
        effectiveResolutionVersionID: ResolutionVersionID,
        correctionReason: LedgerText? = nil,
        createdAt: Date
    ) throws {
        if case let .mixture(components) = composition, components.isEmpty {
            throw FoodLedgerValidationError.empty("mixture components")
        }
        if supersedesLogItemVersionID != nil, correctionReason == nil {
            throw FoodLedgerValidationError.empty("correction reason")
        }
        self.logItemVersionID = logItemVersionID
        self.logItemID = logItemID
        self.ordinal = ordinal
        self.supersedesLogItemVersionID = supersedesLogItemVersionID
        self.occurredAt = occurredAt
        self.reportingDate = reportingDate
        self.composition = composition
        self.edibleQuantity = edibleQuantity
        self.quantityConversionVersionID = quantityConversionVersionID
        self.originalResolutionVersionID = originalResolutionVersionID
        self.effectiveResolutionVersionID = effectiveResolutionVersionID
        self.correctionReason = correctionReason
        self.createdAt = createdAt
    }
}
