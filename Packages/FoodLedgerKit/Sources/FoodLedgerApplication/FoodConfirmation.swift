import Foundation
import FoodLedgerDomain

public protocol FoodConfirmationReading: Sendable {
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease?
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation?
}

public enum FoodConfirmationDecision: Codable, Equatable, Sendable {
    case undecided
    case accepted
    case acceptedClosestMatch(explanation: LedgerText)
    case declined
}

public struct FoodCorrection: Codable, Equatable, Sendable {
    public let name: LedgerText
    public let brand: LedgerText?
    public let variant: LedgerText?
    public let identity: DecisiveIdentity
    public let itemClass: ItemClass?
    public let nutrients: NutrientSet
    public let reason: LedgerText

    public init(
        name: LedgerText,
        brand: LedgerText?,
        variant: LedgerText?,
        identity: DecisiveIdentity,
        itemClass: ItemClass? = nil,
        nutrients: NutrientSet,
        reason: LedgerText
    ) {
        self.name = name
        self.brand = brand
        self.variant = variant
        self.identity = identity
        self.itemClass = itemClass
        self.nutrients = nutrients
        self.reason = reason
    }
}

public struct QuantityConversionDraft: Codable, Equatable, Sendable {
    public let convertedQuantity: PositiveQuantity
    public let methodVersion: LedgerText
    public let sourceReleaseID: ExternalIdentifier?
    public let evidenceID: EvidenceID?

    public init(
        convertedQuantity: PositiveQuantity,
        methodVersion: LedgerText,
        sourceReleaseID: ExternalIdentifier? = nil,
        evidenceID: EvidenceID? = nil
    ) {
        self.convertedQuantity = convertedQuantity
        self.methodVersion = methodVersion
        self.sourceReleaseID = sourceReleaseID
        self.evidenceID = evidenceID
    }
}

public enum PlateWeightChoice: Codable, Equatable, Sendable {
    case foodOnly
    case missing
    case saved(PlateWeightVersion)
    case new(emptyWeight: PositiveQuantity, superseding: PlateWeightVersion?)
}

public struct DirectWeightDraft: Codable, Equatable, Sendable {
    public var totalGrams: Double?
    public var basis: UserWeightBasis?
    public var needsReconfirmation: Bool
    public init(totalGrams: Double? = nil, basis: UserWeightBasis? = nil, needsReconfirmation: Bool = false) {
        self.totalGrams = totalGrams; self.basis = basis; self.needsReconfirmation = needsReconfirmation
    }
}

public struct FoodQuantityDraft: Codable, Equatable, Sendable {
    public var value: Double?
    public var unit: QuantityUnit
    public var conversion: QuantityConversionDraft?
    public var plateChoice: PlateWeightChoice
    public var directWeight: DirectWeightDraft?
    public var invalidOriginalAmountText: Bool?

    public init(
        value: Double? = nil,
        unit: QuantityUnit = .grams,
        conversion: QuantityConversionDraft? = nil,
        plateChoice: PlateWeightChoice = .foodOnly,
        directWeight: DirectWeightDraft? = nil
    ) {
        self.value = value
        self.unit = unit
        self.conversion = conversion
        self.plateChoice = plateChoice
        self.directWeight = directWeight
    }
}

public enum FoodConfirmationPhase: Codable, Equatable, Sendable {
    case editing
    case saving
    case saveFailed(message: String)
    case saved(logItemID: LogItemID)
}

public struct StoredFoodConfirmation: Codable, Equatable, Sendable {
    public let evidence: [CaptureEvidence]
    public let sourceReleases: [SourceRelease]
    public let product: Product
    public let productVersion: ProductVersion
    public let resolution: NutritionResolution
    public let resolutionVersion: NutritionResolutionVersion
    public let logItem: LogItem
    public let logItemVersion: LogItemVersion
    public let quantityConversion: QuantityConversionVersion?
    public let plate: Plate?
    public let plateWeightVersion: PlateWeightVersion?
    public let candidateDecision: CandidateDecision
    public let assertions: [UserAssertion]

    public init(
        evidence: [CaptureEvidence],
        sourceReleases: [SourceRelease],
        product: Product,
        productVersion: ProductVersion,
        resolution: NutritionResolution,
        resolutionVersion: NutritionResolutionVersion,
        logItem: LogItem,
        logItemVersion: LogItemVersion,
        quantityConversion: QuantityConversionVersion?,
        plate: Plate?,
        plateWeightVersion: PlateWeightVersion?,
        candidateDecision: CandidateDecision,
        assertions: [UserAssertion]
    ) {
        self.evidence = evidence
        self.sourceReleases = sourceReleases
        self.product = product
        self.productVersion = productVersion
        self.resolution = resolution
        self.resolutionVersion = resolutionVersion
        self.logItem = logItem
        self.logItemVersion = logItemVersion
        self.quantityConversion = quantityConversion
        self.plate = plate
        self.plateWeightVersion = plateWeightVersion
        self.candidateDecision = candidateDecision
        self.assertions = assertions
    }
}

public struct FoodConfirmationState: Codable, Equatable, Sendable {
    public let input: PopulatedFoodConfirmation
    public var selectedCandidateIndex: Int
    public var decision: FoodConfirmationDecision
    public var correction: FoodCorrection?
    public var quantity: FoodQuantityDraft
    public var phase: FoodConfirmationPhase
    public let reopened: StoredFoodConfirmation?

    public init(input: PopulatedFoodConfirmation, reopened: StoredFoodConfirmation? = nil,
                queryQuantity: ParsedFoodQuery.Quantity? = nil) {
        self.input = input
        selectedCandidateIndex = 0
        decision = .undecided
        correction = nil
        if let reopened {
            if let declaration = reopened.logItemVersion.weightDeclaration {
                quantity = FoodQuantityDraft(value: declaration.originalInput?.value,
                    unit: declaration.originalInput?.unit ?? .grams,
                    plateChoice: reopened.plateWeightVersion.map(PlateWeightChoice.saved) ?? .foodOnly,
                    directWeight: DirectWeightDraft(totalGrams: declaration.total.value, basis: declaration.basis))
            } else if let conversion = reopened.quantityConversion {
                quantity = FoodQuantityDraft(
                    value: conversion.sourceQuantity.value,
                    unit: conversion.sourceQuantity.unit,
                    conversion: QuantityConversionDraft(
                        convertedQuantity: conversion.convertedQuantity,
                        methodVersion: conversion.methodVersion,
                        sourceReleaseID: conversion.sourceReleaseID,
                        evidenceID: conversion.evidenceID
                    ),
                    plateChoice: reopened.plateWeightVersion.map(PlateWeightChoice.saved) ?? .foodOnly
                )
            } else if let plate = reopened.plateWeightVersion {
                quantity = FoodQuantityDraft(
                    value: reopened.logItemVersion.edibleQuantity.value + plate.emptyWeight.value,
                    unit: .grams,
                    plateChoice: .saved(plate)
                )
            } else {
                quantity = FoodQuantityDraft(
                    value: reopened.logItemVersion.edibleQuantity.value,
                    unit: reopened.logItemVersion.edibleQuantity.unit
                )
            }
        } else if case let .known(value, _) = input.expectedEdibleQuantity {
            quantity = FoodQuantityDraft(value: value.value, unit: value.unit)
        } else {
            quantity = FoodQuantityDraft()
        }
        // A parsed exact amount is consumed quantity, distinct from the source's 100-unit basis.
        // No conversion or portion weight is inferred here; count/cross-basis saving stays explicit.
        if reopened == nil, let queryQuantity, queryQuantity.value.isFinite, queryQuantity.value > 0,
           let unit = QuantityUnit(rawValue: queryQuantity.unit == "ml" ? "mL" : queryQuantity.unit) {
            quantity = FoodQuantityDraft(value: queryQuantity.value, unit: unit)
        }
        phase = .editing
        self.reopened = reopened
    }

    public var selectedCandidate: PopulatedFoodCandidate {
        input.candidates[selectedCandidateIndex]
    }

    public var isGenericEstimate: Bool {
        FoodConfirmationPolicy.isGenericEstimate(input, candidate: selectedCandidate)
    }

    public var unresolvedIdentity: [IdentityContradiction] {
        FoodConfirmationPolicy.unresolvedIdentity(
            correction?.identity ?? reopened?.productVersion.identity ?? selectedCandidate.candidate.identity,
            allowingEstimate: isGenericEstimate
        )
    }

    public var materialDifferences: [IdentityContradiction] {
        let differences = IdentityCompatibility.contradictions(
            between: input.expectedIdentity,
            and: selectedCandidate.candidate.identity,
            expectedEdibleQuantity: input.expectedEdibleQuantity,
            candidateEdibleQuantity: selectedCandidate.candidate.edibleQuantity
        )
        guard isGenericEstimate else { return differences }
        let expected = input.expectedIdentity, candidate = selectedCandidate.candidate.identity
        return differences.filter {
            switch $0 {
            case .preparation: expected.preparation != candidate.preparation
            case .bone: expected.bone != candidate.bone
            case .skin: expected.skin != candidate.skin
            case .drained: expected.drained != candidate.drained
            case .packingMedium: expected.packingMedium != candidate.packingMedium
            case .fortification: expected.fortification != candidate.fortification
            case .servingBasis: expected.servingBasis != candidate.servingBasis
            case .edibleQuantity: input.expectedEdibleQuantity != selectedCandidate.candidate.edibleQuantity
            }
        }
    }
}

public enum FoodConfirmationAction: Sendable {
    case selectCandidate(Int)
    case accept
    case acceptClosestMatch(LedgerText)
    case decline
    case applyCorrection(FoodCorrection)
    case beginDirectWeight
    case endDirectWeight
    case setDirectWeight(Double?)
    case setWeightBasis(UserWeightBasis?)
    case setQuantityText(String)
    case setQuantity(Double?, QuantityUnit)
    case setConversion(QuantityConversionDraft?)
    case setPlateChoice(PlateWeightChoice)
    case beginSaving
    case saveFailed(String)
    case saved(LogItemID)
}

public enum FoodConfirmationReducer {
    public static func reduce(state: inout FoodConfirmationState, action: FoodConfirmationAction) {
        switch action {
        case let .selectCandidate(index):
            guard state.input.candidates.indices.contains(index) else { return }
            if state.selectedCandidateIndex != index, state.quantity.directWeight != nil {
                state.quantity.directWeight?.needsReconfirmation = true
            }
            state.selectedCandidateIndex = index
            state.decision = .undecided
            state.correction = nil
            state.phase = .editing
        case .accept:
            state.quantity.directWeight?.needsReconfirmation = false
            state.decision = .accepted
            state.phase = .editing
        case let .acceptClosestMatch(explanation):
            state.quantity.directWeight?.needsReconfirmation = false
            state.decision = .acceptedClosestMatch(explanation: explanation)
            state.phase = .editing
        case .decline:
            state.decision = .declined
            state.phase = .editing
        case let .applyCorrection(correction):
            let previousIdentity = state.correction?.identity ?? state.reopened?.productVersion.identity ?? state.selectedCandidate.candidate.identity
            state.correction = correction
            state.decision = .accepted
            if state.quantity.directWeight != nil, previousIdentity != correction.identity {
                state.quantity.directWeight?.needsReconfirmation = true
                state.decision = .undecided
            }
            state.phase = .editing
        case .beginDirectWeight:
            if state.quantity.directWeight == nil { state.quantity.directWeight = DirectWeightDraft() }
            state.phase = .editing
        case .endDirectWeight:
            state.quantity.directWeight = nil
            state.phase = .editing
        case let .setDirectWeight(value):
            state.quantity.directWeight?.totalGrams = value
            state.phase = .editing
        case let .setWeightBasis(basis):
            state.quantity.directWeight?.basis = basis
            state.phase = .editing
        case let .setQuantityText(text):
            let value = Double(text)
            reduce(state: &state, action: .setQuantity(value, state.quantity.unit))
            state.quantity.invalidOriginalAmountText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value == nil
        case let .setQuantity(value, unit):
            state.quantity.invalidOriginalAmountText = nil
            let previousUnit = state.quantity.unit
            state.quantity.value = value
            state.quantity.unit = unit
            if unit != .count || previousUnit != unit {
                state.quantity.conversion = nil
            }
            state.phase = .editing
        case let .setConversion(conversion):
            state.quantity.conversion = conversion
            state.phase = .editing
        case let .setPlateChoice(choice):
            state.quantity.plateChoice = choice
            state.phase = .editing
        case .beginSaving:
            state.phase = .saving
        case let .saveFailed(message):
            state.phase = .saveFailed(message: message)
        case let .saved(logItemID):
            state.phase = .saved(logItemID: logItemID)
        }
    }
}

public enum FoodConfirmationSaveError: Error, Equatable, Sendable {
    case noAcceptedCandidate
    case unexplainedMaterialDifferences([IdentityContradiction])
    case unresolvedMandatoryIdentity([IdentityContradiction])
    case invalidQuantity
}

public final class FoodConfirmationService: @unchecked Sendable {
    private let ledger: FoodLedgerService
    private let reader: any FoodConfirmationReading
    private let clock: any LedgerClock
    private let ids: any LedgerIDGenerating
    private let calendar: Calendar

    public init(
        ledger: FoodLedgerService,
        reader: any FoodConfirmationReading,
        clock: any LedgerClock,
        ids: any LedgerIDGenerating,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.ledger = ledger
        self.reader = reader
        self.clock = clock
        self.ids = ids
        self.calendar = calendar
    }

    public func save(
        _ state: FoodConfirmationState,
        operationID: OperationID,
        idempotencyKey: LedgerText? = nil
    ) throws -> StoredFoodConfirmation {
        if let idempotencyKey,
           let logItemID = try ledger.confirmedLogItemID(operationID: operationID, idempotencyKey: idempotencyKey) {
            guard let stored = try reader.foodConfirmation(logItemID: logItemID) else {
                throw FoodLedgerStoreError.integrityFailure("committed confirmation could not be recovered")
            }
            try stored.logItemVersion.validateWeightDeclaration(emptyPlate: stored.plateWeightVersion)
            return stored
        }
        switch state.decision {
        case .accepted:
            guard state.reopened != nil
                || state.correction != nil
                || state.materialDifferences.isEmpty else {
                throw FoodConfirmationSaveError.unexplainedMaterialDifferences(
                    state.materialDifferences
                )
            }
        case .acceptedClosestMatch:
            break
        case .undecided, .declined:
            throw FoodConfirmationSaveError.noAcceptedCandidate
        }

        let selected = state.selectedCandidate
        // A reopened entry already has a user-confirmed product identity. The
        // retained source candidate may still contain explicitly asserted gaps.
        let identity = state.correction?.identity ?? state.reopened?.productVersion.identity ?? selected.candidate.identity
        let unresolved = state.unresolvedIdentity
        guard unresolved.isEmpty else {
            throw FoodConfirmationSaveError.unresolvedMandatoryIdentity(unresolved)
        }
        let now = clock.now()
        let previous = state.reopened
        let declaration = try state.quantity.declaration()
        let entered = try state.quantity.calculationInput()
        let conversion = declaration == nil
            ? try makeConversion(state.quantity, entered: entered, previous: previous, at: now)
            : (version: nil, isNew: false)
        let plate = try makePlate(state.quantity.plateChoice, previous: previous, at: now)
        let edibleQuantity = try state.quantity.calculatedEdibleQuantity()

        let changesProduct = previous == nil || state.correction != nil
        let assertion = changesProduct
            ? try makeAssertion(state: state, selected: selected, previous: previous, at: now)
            : nil
        let product: Product
        if let existing = previous?.product {
            product = existing
        } else {
            product = Product(productID: try ids.makeID(ProductTag.self), createdAt: now)
        }
        let productVersion: ProductVersion
        let decision: CandidateDecision
        let resolution: NutritionResolution
        let resolutionVersion: NutritionResolutionVersion
        if changesProduct {
            productVersion = try ProductVersion(
                productVersionID: ids.makeID(ProductVersionTag.self),
                productID: product.productID,
                ordinal: VersionOrdinal((previous?.productVersion.ordinal.value ?? 0) + 1),
                supersedesProductVersionID: previous?.productVersion.productVersionID,
                name: state.correction?.name ?? selected.name,
                brand: state.correction?.brand ?? selected.brand,
                variant: state.correction?.variant ?? selected.variant,
                barcode: selected.barcode,
                itemClass: state.correction?.itemClass ?? selected.itemClass,
                packFacts: selected.packFacts,
                identity: identity,
                evidenceIDs: selected.candidate.evidenceIDs,
                assertionIDs: assertion.map { [$0.assertionID] } ?? [],
                createdAt: now
            )
            decision = try CandidateDecision(
                candidateDecisionID: ids.makeID(CandidateDecisionTag.self),
                candidate: selected.candidate,
                expectedIdentity: identity,
                expectedEdibleQuantity: state.input.expectedEdibleQuantity,
                requestedOutcome: state.correction == nil && (!state.isGenericEstimate || IdentityCompatibility.contradictions(
                    between: identity, and: selected.candidate.identity,
                    expectedEdibleQuantity: state.input.expectedEdibleQuantity,
                    candidateEdibleQuantity: selected.candidate.edibleQuantity
                ).isEmpty) ? .selected : .rejected,
                assertionID: assertion?.assertionID,
                createdAt: now
            )
            resolution = NutritionResolution(
                resolutionID: try ids.makeID(ResolutionTag.self),
                productVersionID: productVersion.productVersionID,
                basis: identity.servingBasis,
                createdAt: now
            )
            resolutionVersion = try NutritionResolutionVersion(
                resolutionVersionID: ids.makeID(ResolutionVersionTag.self),
                resolutionID: resolution.resolutionID,
                ordinal: VersionOrdinal(1),
                methodVersion: LedgerText(FoodConfirmationPolicy.version),
                sourceReleaseIDs: [selected.candidate.sourceReleaseID],
                nutrients: state.correction?.nutrients ?? selected.candidate.nutrients,
                decisionIDs: [decision.candidateDecisionID],
                assertionIDs: assertion.map { [$0.assertionID] } ?? [],
                createdAt: now
            )
        } else {
            guard let previous else { throw FoodConfirmationSaveError.noAcceptedCandidate }
            productVersion = previous.productVersion
            decision = previous.candidateDecision
            resolution = previous.resolution
            resolutionVersion = previous.resolutionVersion
        }
        let logItem: LogItem
        if let existing = previous?.logItem {
            logItem = existing
        } else {
            logItem = LogItem(logItemID: try ids.makeID(LogItemTag.self), createdAt: now)
        }
        let logVersion = try LogItemVersion(
            logItemVersionID: ids.makeID(LogItemVersionTag.self),
            logItemID: logItem.logItemID,
            ordinal: VersionOrdinal((previous?.logItemVersion.ordinal.value ?? 0) + 1),
            supersedesLogItemVersionID: previous?.logItemVersion.logItemVersionID,
            occurredAt: previous?.logItemVersion.occurredAt ?? now,
            reportingDate: previous?.logItemVersion.reportingDate ?? LedgerText(FoodReportingDay.key(for: now, calendar: calendar)),
            composition: .product(productVersion.productVersionID),
            edibleQuantity: edibleQuantity,
            weightDeclaration: declaration,
            quantityConversionVersionID: conversion.version?.quantityConversionVersionID,
            plateWeightVersionID: plate.version?.plateWeightVersionID,
            originalResolutionVersionID: previous?.logItemVersion.originalResolutionVersionID ?? resolutionVersion.resolutionVersionID,
            effectiveResolutionVersionID: resolutionVersion.resolutionVersionID,
            correctionReason: previous == nil ? nil : (state.correction?.reason ?? LedgerText("Confirmation quantity or plate correction")),
            createdAt: now
        )
        let libraryRecords: (LibraryEntry?, LibraryEntryVersion?)
        if previous == nil,
           let aliases = selected.candidate.matchMetadata?.libraryAliases,
           !aliases.isEmpty {
            let entry = LibraryEntry(
                libraryEntryID: try ids.makeID(LibraryEntryTag.self),
                createdAt: now
            )
            let version = try LibraryEntryVersion(
                libraryEntryVersionID: ids.makeID(LibraryEntryVersionTag.self),
                libraryEntryID: entry.libraryEntryID,
                ordinal: VersionOrdinal(1),
                productVersionID: productVersion.productVersionID,
                aliases: aliases,
                reusableQuantity: edibleQuantity,
                quantityConversionVersionID: conversion.version?.quantityConversionVersionID,
                createdAt: now
            )
            libraryRecords = (entry, version)
        } else {
            libraryRecords = (nil, nil)
        }

        let missingReleases = try state.input.sourceReleases.filter {
            try reader.sourceRelease(id: $0.sourceReleaseID) == nil
        }
        let mutation = LedgerMutation(
            evidence: previous == nil ? state.input.evidence : [],
            assertions: assertion.map { [$0] } ?? [],
            products: previous == nil ? [product] : [],
            productVersions: changesProduct ? [productVersion] : [],
            libraryEntries: libraryRecords.0.map { [$0] } ?? [],
            libraryEntryVersions: libraryRecords.1.map { [$0] } ?? [],
            resolutions: changesProduct ? [resolution] : [],
            resolutionVersions: changesProduct ? [resolutionVersion] : [],
            logItems: previous == nil ? [logItem] : [],
            logItemVersions: [logVersion],
            quantityConversions: conversion.isNew ? conversion.version.map { [$0] } ?? [] : [],
            plates: plate.newPlate.map { [$0] } ?? [],
            plateWeightVersions: plate.isNew ? plate.version.map { [$0] } ?? [] : [],
            candidateDecisions: changesProduct ? [decision] : [],
            sourceReleases: missingReleases
        )
        _ = try ledger.commit(
            mutation,
            type: declaration == nil ? .confirmFood : .confirmFoodV2,
            operationID: operationID,
            idempotencyKey: idempotencyKey
        )
        return StoredFoodConfirmation(
            evidence: previous?.evidence ?? state.input.evidence,
            sourceReleases: previous?.sourceReleases ?? state.input.sourceReleases,
            product: product,
            productVersion: productVersion,
            resolution: resolution,
            resolutionVersion: resolutionVersion,
            logItem: logItem,
            logItemVersion: logVersion,
            quantityConversion: conversion.version,
            plate: plate.newPlate ?? previous?.plate,
            plateWeightVersion: plate.version,
            candidateDecision: decision,
            assertions: assertion.map { [$0] } ?? []
        )
    }

    public func reopen(logItemID: LogItemID) throws -> FoodConfirmationState? {
        guard let saved = try reader.foodConfirmation(logItemID: logItemID) else { return nil }
        try saved.logItemVersion.validateWeightDeclaration(emptyPlate: saved.plateWeightVersion)
        let populated = try PopulatedFoodCandidate(
            candidate: saved.candidateDecision.candidate,
            name: saved.productVersion.name,
            brand: saved.productVersion.brand,
            variant: saved.productVersion.variant,
            barcode: saved.productVersion.barcode,
            itemClass: saved.productVersion.itemClass,
            packFacts: saved.productVersion.packFacts
        )
        let input = try PopulatedFoodConfirmation(
            evidence: saved.evidence,
            sourceReleases: saved.sourceReleases,
            candidates: [populated],
            expectedIdentity: saved.productVersion.identity,
            expectedEdibleQuantity: .known(
                saved.logItemVersion.edibleQuantity,
                conversionVersionID: saved.logItemVersion.quantityConversionVersionID
            )
        )
        var state = FoodConfirmationState(input: input, reopened: saved)
        state.decision = .accepted
        return state
    }

    private func makeConversion(
        _ draft: FoodQuantityDraft,
        entered: PositiveQuantity,
        previous: StoredFoodConfirmation?,
        at date: Date
    ) throws -> (version: QuantityConversionVersion?, isNew: Bool) {
        guard let value = draft.conversion else {
            if entered.unit == .count { throw FoodQuantityValidationError.missingConversion }
            return (nil, false)
        }
        if let old = previous?.quantityConversion,
           old.sourceQuantity == entered,
           old.convertedQuantity == value.convertedQuantity,
           old.methodVersion == value.methodVersion,
           old.sourceReleaseID == value.sourceReleaseID,
           old.evidenceID == value.evidenceID {
            return (old, false)
        }
        return (try QuantityConversionVersion(
            quantityConversionVersionID: ids.makeID(QuantityConversionVersionTag.self),
            ordinal: VersionOrdinal((previous?.quantityConversion?.ordinal.value ?? 0) + 1),
            supersedesQuantityConversionVersionID: previous?.quantityConversion?.quantityConversionVersionID,
            sourceQuantity: entered,
            convertedQuantity: value.convertedQuantity,
            methodVersion: value.methodVersion,
            sourceReleaseID: value.sourceReleaseID,
            evidenceID: value.evidenceID,
            createdAt: date
        ), true)
    }

    private func makePlate(
        _ choice: PlateWeightChoice,
        previous: StoredFoodConfirmation?,
        at date: Date
    ) throws -> (newPlate: Plate?, version: PlateWeightVersion?, isNew: Bool) {
        switch choice {
        case .foodOnly:
            return (nil, nil, false)
        case .missing:
            throw FoodQuantityValidationError.missingPlateWeight
        case let .saved(version):
            return (nil, version, false)
        case let .new(emptyWeight, superseding):
            let plate: Plate
            if let existing = previous?.plate {
                plate = existing
            } else {
                plate = Plate(plateID: try ids.makeID(PlateTag.self), createdAt: date)
            }
            let version = try PlateWeightVersion(
                plateWeightVersionID: ids.makeID(PlateWeightVersionTag.self),
                plateID: plate.plateID,
                ordinal: VersionOrdinal((superseding?.ordinal.value ?? 0) + 1),
                supersedesPlateWeightVersionID: superseding?.plateWeightVersionID,
                emptyWeight: emptyWeight,
                createdAt: date
            )
            return (previous?.plate == nil ? plate : nil, version, true)
        }
    }

    private func makeAssertion(
        state: FoodConfirmationState,
        selected: PopulatedFoodCandidate,
        previous: StoredFoodConfirmation?,
        at date: Date
    ) throws -> UserAssertion? {
        let reason: LedgerText
        let claim: LedgerText
        if let correction = state.correction {
            reason = correction.reason
            claim = try LedgerText("Corrected populated confirmation for \(selected.name.value)")
        } else if case let .acceptedClosestMatch(explanation) = state.decision {
            reason = explanation
            let differences = state.materialDifferences.map(\.rawValue).joined(separator: ", ")
            claim = try LedgerText("Accepted explained closest match; differences: \(differences)")
        } else if previous != nil {
            reason = try LedgerText("Updated confirmed quantity")
            claim = try LedgerText("Created a new immutable confirmation version")
        } else if state.isGenericEstimate {
            reason = try LedgerText("Explicitly accepted generic composition estimate; unknown source details remain unknown")
            claim = try LedgerText("Accepted estimate under \(FoodConfirmationPolicy.version); not verified product identity")
        } else {
            return nil
        }
        return UserAssertion(
            assertionID: try ids.makeID(AssertionTag.self),
            evidenceID: selected.candidate.evidenceIDs.first,
            supersedesAssertionID: previous?.assertions.last?.assertionID,
            author: .user,
            createdAt: date,
            reason: reason,
            claim: claim
        )
    }

    public static func unresolvedIdentity(_ value: DecisiveIdentity) -> [IdentityContradiction] {
        FoodConfirmationPolicy.unresolvedIdentity(value, allowingEstimate: false)
    }
}
