import Foundation

extension LedgerText {
    public init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(self.value)
    }
}

extension LedgerID {
    public init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(rawValue)
    }
}

extension SHA256Digest {
    public init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension VersionOrdinal {
    public init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension ExternalIdentifier {
    public init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension VersionReference {
    public init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension PositiveQuantity {
    enum CodingKeys: String, CodingKey { case value, unit }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: values.decode(Double.self, forKey: .value),
            unit: values.decode(QuantityUnit.self, forKey: .unit)
        )
    }
}

extension NonNegativeQuantity {
    enum CodingKeys: String, CodingKey { case value, unit }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: values.decode(Double.self, forKey: .value),
            unit: values.decode(QuantityUnit.self, forKey: .unit)
        )
    }
}

extension PreparationState {
    enum CodingKeys: String, CodingKey { case kind, method }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: values.decode(PreparationKind.self, forKey: .kind),
            method: values.decodeIfPresent(LedgerText.self, forKey: .method)
        )
    }
}

extension DecisiveIdentity {
    enum CodingKeys: String, CodingKey {
        case preparation, bone, skin, drained, packingMedium, fortification
        case declaredFortificants, servingBasis
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            preparation: values.decode(PreparationState.self, forKey: .preparation),
            bone: values.decode(BoneState.self, forKey: .bone),
            skin: values.decode(SkinState.self, forKey: .skin),
            drained: values.decode(DrainedState.self, forKey: .drained),
            packingMedium: values.decode(PackingMediumState.self, forKey: .packingMedium),
            fortification: values.decode(FortificationState.self, forKey: .fortification),
            declaredFortificants: values.decode([NutrientKey].self, forKey: .declaredFortificants),
            servingBasis: values.decode(ResolutionBasis.self, forKey: .servingBasis)
        )
    }
}

extension SourceExactNutrientValue {
    enum CodingKeys: String, CodingKey { case amount, unit, basis }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            amount: values.decode(Double.self, forKey: .amount),
            unit: values.decode(LedgerText.self, forKey: .unit),
            basis: values.decode(ResolutionBasis.self, forKey: .basis)
        )
    }
}

extension SourceBoundedNutrientValue {
    enum CodingKeys: String, CodingKey {
        case lower, upper, lowerClosed, upperClosed, unit, basis
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lower: values.decodeIfPresent(Double.self, forKey: .lower),
            upper: values.decodeIfPresent(Double.self, forKey: .upper),
            lowerClosed: values.decode(Bool.self, forKey: .lowerClosed),
            upperClosed: values.decode(Bool.self, forKey: .upperClosed),
            unit: values.decode(LedgerText.self, forKey: .unit),
            basis: values.decode(ResolutionBasis.self, forKey: .basis)
        )
    }
}

extension ExactNutrientValue {
    enum CodingKeys: String, CodingKey { case amount, unit, sourceValue, provenance }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            amount: values.decode(Double.self, forKey: .amount),
            unit: values.decode(NutrientUnit.self, forKey: .unit),
            sourceValue: values.decode(SourceNutrientValue.self, forKey: .sourceValue),
            provenance: values.decode([NutrientProvenance].self, forKey: .provenance)
        )
    }
}

extension NutrientBounds {
    enum CodingKeys: String, CodingKey {
        case lower, upper, lowerClosed, upperClosed, origin, unit, sourceValue, provenance
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lower: values.decodeIfPresent(Double.self, forKey: .lower),
            upper: values.decodeIfPresent(Double.self, forKey: .upper),
            lowerClosed: values.decode(Bool.self, forKey: .lowerClosed),
            upperClosed: values.decode(Bool.self, forKey: .upperClosed),
            origin: values.decode(BoundOrigin.self, forKey: .origin),
            unit: values.decode(NutrientUnit.self, forKey: .unit),
            sourceValue: values.decode(SourceNutrientValue.self, forKey: .sourceValue),
            provenance: values.decode([NutrientProvenance].self, forKey: .provenance)
        )
    }
}

extension NutrientEntry {
    enum CodingKeys: String, CodingKey { case key, value, status, conflictCandidates }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: values.decode(NutrientKey.self, forKey: .key),
            value: values.decode(NutrientValue.self, forKey: .value),
            status: values.decode(ResolutionStatus.self, forKey: .status),
            conflictCandidates: values.decode([NutrientValue].self, forKey: .conflictCandidates)
        )
    }
}

extension NutrientSet {
    enum CodingKeys: String, CodingKey { case entries }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(entries: values.decode([NutrientEntry].self, forKey: .entries))
    }
}

extension AttachmentDescriptor {
    enum CodingKeys: String, CodingKey { case sha256, mediaKind, byteCount, relativePath }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sha256: values.decode(SHA256Digest.self, forKey: .sha256),
            mediaKind: values.decode(LedgerText.self, forKey: .mediaKind),
            byteCount: values.decode(Int.self, forKey: .byteCount),
            relativePath: values.decode(LedgerText.self, forKey: .relativePath)
        )
    }
}

extension CaptureEvidence {
    enum CodingKeys: String, CodingKey {
        case evidenceID, kind, capturedAt, locale, captureMethod, captureMethodVersion
        case originalPayload, byteHash, attachment
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            evidenceID: values.decode(EvidenceID.self, forKey: .evidenceID),
            kind: values.decode(CaptureKind.self, forKey: .kind),
            capturedAt: values.decode(Date.self, forKey: .capturedAt),
            locale: values.decode(LedgerText.self, forKey: .locale),
            captureMethod: values.decode(LedgerText.self, forKey: .captureMethod),
            captureMethodVersion: values.decode(LedgerText.self, forKey: .captureMethodVersion),
            originalPayload: values.decode(CapturePayload.self, forKey: .originalPayload),
            byteHash: values.decodeIfPresent(SHA256Digest.self, forKey: .byteHash),
            attachment: values.decodeIfPresent(AttachmentDescriptor.self, forKey: .attachment)
        )
    }
}

extension ProductVersion {
    enum CodingKeys: String, CodingKey {
        case productVersionID, productID, ordinal, supersedesProductVersionID, name, brand
        case variant, barcode, itemClass, packFacts, identity, evidenceIDs, assertionIDs, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            productVersionID: values.decode(ProductVersionID.self, forKey: .productVersionID),
            productID: values.decode(ProductID.self, forKey: .productID),
            ordinal: values.decode(VersionOrdinal.self, forKey: .ordinal),
            supersedesProductVersionID: values.decodeIfPresent(ProductVersionID.self, forKey: .supersedesProductVersionID),
            name: values.decode(LedgerText.self, forKey: .name),
            brand: values.decodeIfPresent(LedgerText.self, forKey: .brand),
            variant: values.decodeIfPresent(LedgerText.self, forKey: .variant),
            barcode: values.decodeIfPresent(LedgerText.self, forKey: .barcode),
            itemClass: values.decode(ItemClass.self, forKey: .itemClass),
            packFacts: values.decode(PackFacts.self, forKey: .packFacts),
            identity: values.decode(DecisiveIdentity.self, forKey: .identity),
            evidenceIDs: values.decode([EvidenceID].self, forKey: .evidenceIDs),
            assertionIDs: values.decode([AssertionID].self, forKey: .assertionIDs),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

extension LibraryEntryVersion {
    enum CodingKeys: String, CodingKey {
        case libraryEntryVersionID, libraryEntryID, ordinal, supersedesLibraryEntryVersionID
        case productVersionID, aliases, reusableQuantity, quantityConversionVersionID, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            libraryEntryVersionID: values.decode(LibraryEntryVersionID.self, forKey: .libraryEntryVersionID),
            libraryEntryID: values.decode(LibraryEntryID.self, forKey: .libraryEntryID),
            ordinal: values.decode(VersionOrdinal.self, forKey: .ordinal),
            supersedesLibraryEntryVersionID: values.decodeIfPresent(LibraryEntryVersionID.self, forKey: .supersedesLibraryEntryVersionID),
            productVersionID: values.decode(ProductVersionID.self, forKey: .productVersionID),
            aliases: values.decode([LedgerText].self, forKey: .aliases),
            reusableQuantity: values.decodeIfPresent(PositiveQuantity.self, forKey: .reusableQuantity),
            quantityConversionVersionID: values.decodeIfPresent(QuantityConversionVersionID.self, forKey: .quantityConversionVersionID),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

extension NutritionResolutionVersion {
    enum CodingKeys: String, CodingKey {
        case resolutionVersionID, resolutionID, ordinal, supersedesResolutionVersionID
        case methodVersion, sourceReleaseIDs, nutrients, decisionIDs, assertionIDs, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            resolutionVersionID: values.decode(ResolutionVersionID.self, forKey: .resolutionVersionID),
            resolutionID: values.decode(ResolutionID.self, forKey: .resolutionID),
            ordinal: values.decode(VersionOrdinal.self, forKey: .ordinal),
            supersedesResolutionVersionID: values.decodeIfPresent(
                ResolutionVersionID.self,
                forKey: .supersedesResolutionVersionID
            ),
            methodVersion: values.decode(LedgerText.self, forKey: .methodVersion),
            sourceReleaseIDs: values.decode([ExternalIdentifier].self, forKey: .sourceReleaseIDs),
            nutrients: values.decode(NutrientSet.self, forKey: .nutrients),
            decisionIDs: values.decode([CandidateDecisionID].self, forKey: .decisionIDs),
            assertionIDs: values.decode([AssertionID].self, forKey: .assertionIDs),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

extension ProviderNeutralCandidate {
    enum CodingKeys: String, CodingKey {
        case sourceReleaseID, recordID, identity, edibleQuantity, nutrients, evidenceIDs
        case matchMetadata
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceReleaseID: values.decode(ExternalIdentifier.self, forKey: .sourceReleaseID),
            recordID: values.decode(ExternalIdentifier.self, forKey: .recordID),
            identity: values.decode(DecisiveIdentity.self, forKey: .identity),
            edibleQuantity: values.decode(EdibleQuantityIdentity.self, forKey: .edibleQuantity),
            nutrients: values.decode(NutrientSet.self, forKey: .nutrients),
            evidenceIDs: values.decode([EvidenceID].self, forKey: .evidenceIDs),
            matchMetadata: values.decodeIfPresent(CandidateMatchMetadata.self, forKey: .matchMetadata)
        )
    }
}

extension CandidateMatchMetadata {
    enum CodingKeys: String, CodingKey {
        case methodVersion, score, materialDifferences, selectionPolicy, libraryAliases
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            methodVersion: values.decode(LedgerText.self, forKey: .methodVersion),
            score: values.decode(Double.self, forKey: .score),
            materialDifferences: values.decode([LedgerText].self, forKey: .materialDifferences),
            libraryAliases: values.decodeIfPresent([LedgerText].self, forKey: .libraryAliases) ?? []
        )
        let encodedPolicy = try values.decode(LedgerText.self, forKey: .selectionPolicy)
        guard encodedPolicy == selectionPolicy else {
            throw FoodLedgerValidationError.invalidProvenance
        }
    }
}

extension LogItemVersion {
    enum CodingKeys: String, CodingKey {
        case logItemVersionID, logItemID, ordinal, supersedesLogItemVersionID, occurredAt
        case reportingDate, composition, edibleQuantity, quantityConversionVersionID
        case originalResolutionVersionID, effectiveResolutionVersionID, correctionReason, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            logItemVersionID: values.decode(LogItemVersionID.self, forKey: .logItemVersionID),
            logItemID: values.decode(LogItemID.self, forKey: .logItemID),
            ordinal: values.decode(VersionOrdinal.self, forKey: .ordinal),
            supersedesLogItemVersionID: values.decodeIfPresent(LogItemVersionID.self, forKey: .supersedesLogItemVersionID),
            occurredAt: values.decode(Date.self, forKey: .occurredAt),
            reportingDate: values.decode(LedgerText.self, forKey: .reportingDate),
            composition: values.decode(LogComposition.self, forKey: .composition),
            edibleQuantity: values.decode(PositiveQuantity.self, forKey: .edibleQuantity),
            quantityConversionVersionID: values.decodeIfPresent(QuantityConversionVersionID.self, forKey: .quantityConversionVersionID),
            originalResolutionVersionID: values.decode(ResolutionVersionID.self, forKey: .originalResolutionVersionID),
            effectiveResolutionVersionID: values.decode(ResolutionVersionID.self, forKey: .effectiveResolutionVersionID),
            correctionReason: values.decodeIfPresent(LedgerText.self, forKey: .correctionReason),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

extension QuantityConversionVersion {
    enum CodingKeys: String, CodingKey {
        case quantityConversionVersionID, ordinal, supersedesQuantityConversionVersionID
        case sourceQuantity, convertedQuantity, methodVersion, sourceReleaseID, evidenceID, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            quantityConversionVersionID: values.decode(QuantityConversionVersionID.self, forKey: .quantityConversionVersionID),
            ordinal: values.decode(VersionOrdinal.self, forKey: .ordinal),
            supersedesQuantityConversionVersionID: values.decodeIfPresent(QuantityConversionVersionID.self, forKey: .supersedesQuantityConversionVersionID),
            sourceQuantity: values.decode(PositiveQuantity.self, forKey: .sourceQuantity),
            convertedQuantity: values.decode(PositiveQuantity.self, forKey: .convertedQuantity),
            methodVersion: values.decode(LedgerText.self, forKey: .methodVersion),
            sourceReleaseID: values.decodeIfPresent(ExternalIdentifier.self, forKey: .sourceReleaseID),
            evidenceID: values.decodeIfPresent(EvidenceID.self, forKey: .evidenceID),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

extension PlateWeightVersion {
    enum CodingKeys: String, CodingKey {
        case plateWeightVersionID, plateID, ordinal, supersedesPlateWeightVersionID
        case emptyWeight, evidenceID, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            plateWeightVersionID: values.decode(PlateWeightVersionID.self, forKey: .plateWeightVersionID),
            plateID: values.decode(PlateID.self, forKey: .plateID),
            ordinal: values.decode(VersionOrdinal.self, forKey: .ordinal),
            supersedesPlateWeightVersionID: values.decodeIfPresent(PlateWeightVersionID.self, forKey: .supersedesPlateWeightVersionID),
            emptyWeight: values.decode(PositiveQuantity.self, forKey: .emptyWeight),
            evidenceID: values.decodeIfPresent(EvidenceID.self, forKey: .evidenceID),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

extension CandidateDecision {
    enum CodingKeys: String, CodingKey {
        case candidateDecisionID, candidate, expectedIdentity, expectedEdibleQuantity, outcome
        case contradictionReasons, assertionID, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let expected = try values.decode(DecisiveIdentity.self, forKey: .expectedIdentity)
        let candidate = try values.decode(ProviderNeutralCandidate.self, forKey: .candidate)
        let requested = try values.decode(CandidateOutcome.self, forKey: .outcome)
        try self.init(
            candidateDecisionID: values.decode(CandidateDecisionID.self, forKey: .candidateDecisionID),
            candidate: candidate,
            expectedIdentity: expected,
            expectedEdibleQuantity: values.decode(
                EdibleQuantityIdentity.self,
                forKey: .expectedEdibleQuantity
            ),
            requestedOutcome: requested,
            assertionID: values.decodeIfPresent(AssertionID.self, forKey: .assertionID),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
        let stored = try values.decode([IdentityContradiction].self, forKey: .contradictionReasons)
        guard stored == contradictionReasons else { throw FoodLedgerValidationError.invalidConflict }
    }
}

extension LedgerConflict {
    enum CodingKeys: String, CodingKey {
        case conflictID, kind, ancestorVersionID, competingVersionIDs, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            conflictID: values.decode(ConflictID.self, forKey: .conflictID),
            kind: values.decode(ConflictKind.self, forKey: .kind),
            ancestorVersionID: values.decode(VersionReference.self, forKey: .ancestorVersionID),
            competingVersionIDs: values.decode([VersionReference].self, forKey: .competingVersionIDs),
            createdAt: values.decode(Date.self, forKey: .createdAt)
        )
    }
}

extension SourceInstallation {
    enum CodingKeys: String, CodingKey {
        case sourceReleaseID, manifestRelativePath, recordCount, installedAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceReleaseID: values.decode(ExternalIdentifier.self, forKey: .sourceReleaseID),
            manifestRelativePath: values.decode(LedgerText.self, forKey: .manifestRelativePath),
            recordCount: values.decode(Int.self, forKey: .recordCount),
            installedAt: values.decode(Date.self, forKey: .installedAt)
        )
    }
}
