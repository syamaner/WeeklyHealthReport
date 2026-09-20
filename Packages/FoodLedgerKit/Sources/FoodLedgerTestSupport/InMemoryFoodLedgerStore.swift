import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

public final class InMemoryFoodLedgerStore: LedgerCommandCommitting, LedgerReading,
    FoodConfirmationReading, @unchecked Sendable
{
    private struct State {
        var evidence: [String: CaptureEvidence] = [:]
        var assertions: [String: UserAssertion] = [:]
        var products: [String: Product] = [:]
        var productVersions: [String: ProductVersion] = [:]
        var libraryEntries: [String: LibraryEntry] = [:]
        var libraryEntryVersions: [String: LibraryEntryVersion] = [:]
        var resolutions: [String: NutritionResolution] = [:]
        var resolutionVersions: [String: NutritionResolutionVersion] = [:]
        var logItems: [String: LogItem] = [:]
        var logItemVersions: [String: LogItemVersion] = [:]
        var quantityConversions: [String: QuantityConversionVersion] = [:]
        var plates: [String: Plate] = [:]
        var plateWeightVersions: [String: PlateWeightVersion] = [:]
        var candidateDecisions: [String: CandidateDecision] = [:]
        var conflicts: [String: LedgerConflict] = [:]
        var sourceReleases: [String: SourceRelease] = [:]
        var sourceInstallations: [String: SourceInstallation] = [:]
        var operations: [String: LedgerOperation] = [:]
        var actorHeads: [String: ActorHead] = [:]
    }

    private let lock = NSLock()
    private var state = State()
    private let verifier: OperationVerifier

    public init(
        encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
        digester: any Digesting = SHA256Digester(),
        operationRegistry: LedgerOperationRegistry = .builtInV1
    ) {
        verifier = OperationVerifier(
            encoder: encoder,
            digester: digester,
            operationRegistry: operationRegistry
        )
    }

    public func actorHead(for actorID: ActorID) throws -> ActorHead {
        withLock { state.actorHeads[actorID.rawValue] ?? ActorHead(sequence: 0, operationHash: nil) }
    }

    public func operation(id: OperationID) throws -> LedgerOperation? {
        withLock { state.operations[id.rawValue] }
    }

    public func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome {
        try withLock {
            if let existing = state.operations[transaction.operation.operationID.rawValue] {
                guard existing.operationHash == transaction.operation.operationHash else {
                    throw FoodLedgerStoreError.divergentDuplicateOperation
                }
                return .idempotent(existing)
            }
            try verifier.verify(transaction)
            let head = state.actorHeads[transaction.operation.actorID.rawValue]
                ?? ActorHead(sequence: 0, operationHash: nil)
            guard transaction.operation.actorSequence == head.sequence + 1 else {
                throw FoodLedgerStoreError.actorSequenceMismatch
            }
            guard transaction.operation.previousOperationHash == head.operationHash else {
                throw FoodLedgerStoreError.actorHashMismatch
            }

            var next = state
            try Self.apply(transaction.mutation, to: &next)
            next.operations[transaction.operation.operationID.rawValue] = transaction.operation
            next.actorHeads[transaction.operation.actorID.rawValue] = ActorHead(
                sequence: transaction.operation.actorSequence,
                operationHash: transaction.operation.operationHash
            )
            state = next
            return .committed(transaction.operation)
        }
    }

    public func counts() throws -> LedgerCounts {
        withLock {
            LedgerCounts(
                evidence: state.evidence.count,
                productVersions: state.productVersions.count,
                resolutionVersions: state.resolutionVersions.count,
                logItemVersions: state.logItemVersions.count,
                conflicts: state.conflicts.count,
                operations: state.operations.count
            )
        }
    }

    public func productVersions(productID: ProductID) throws -> [ProductVersion] {
        withLock {
            state.productVersions.values
                .filter { $0.productID == productID }
                .sorted { $0.ordinal.value < $1.ordinal.value }
        }
    }

    public func resolutionVersion(id: ResolutionVersionID) throws -> NutritionResolutionVersion? {
        withLock { state.resolutionVersions[id.rawValue] }
    }

    public func exactLibraryEntries(alias: LedgerText) throws -> [LibraryEntryVersion] {
        withLock {
            state.libraryEntryVersions.values
                .filter { $0.aliases.contains(alias) }
                .sorted { $0.libraryEntryVersionID.rawValue < $1.libraryEntryVersionID.rawValue }
        }
    }

    public func barcodeLibraryRecords(alias: LedgerText) throws -> [BarcodeLibraryRecord] {
        try withLock {
            let supersededIDs = Set(state.libraryEntryVersions.values.compactMap {
                $0.supersedesLibraryEntryVersionID
            })
            let matchingEntries = state.libraryEntryVersions.values
                .filter {
                    !supersededIDs.contains($0.libraryEntryVersionID)
                        && $0.aliases.contains(alias)
                }
                .sorted { $0.libraryEntryVersionID.rawValue < $1.libraryEntryVersionID.rawValue }
            return try matchingEntries.flatMap { entry -> [BarcodeLibraryRecord] in
                guard let product = state.productVersions[entry.productVersionID.rawValue] else {
                    throw FoodLedgerStoreError.integrityFailure("missing barcode product version")
                }
                let resolutions = state.resolutions.values
                    .filter { $0.productVersionID == product.productVersionID }
                    .sorted { $0.resolutionID.rawValue < $1.resolutionID.rawValue }
                return try resolutions.compactMap { resolution in
                    guard let version = state.resolutionVersions.values
                        .filter({ $0.resolutionID == resolution.resolutionID })
                        .max(by: { $0.ordinal.value < $1.ordinal.value }) else { return nil }
                    let releases = try version.sourceReleaseIDs.map { identifier in
                        guard let release = state.sourceReleases[identifier.value] else {
                            throw FoodLedgerStoreError.integrityFailure("missing barcode source release")
                        }
                        return release
                    }
                    return try BarcodeLibraryRecord(
                        libraryEntryVersion: entry,
                        productVersion: product,
                        resolution: resolution,
                        resolutionVersion: version,
                        sourceReleases: releases
                    )
                }
            }
        }
    }

    public func conflicts() throws -> [LedgerConflict] {
        withLock { state.conflicts.values.sorted { $0.conflictID.rawValue < $1.conflictID.rawValue } }
    }

    public func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? {
        withLock { state.sourceReleases[id.value] }
    }

    public func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? {
        try withLock {
            guard let logVersion = state.logItemVersions.values
                .filter({ $0.logItemID == logItemID })
                .max(by: { $0.ordinal.value < $1.ordinal.value }) else { return nil }
            guard let logItem = state.logItems[logItemID.rawValue],
                  case let .product(productVersionID) = logVersion.composition,
                  let productVersion = state.productVersions[productVersionID.rawValue],
                  let product = state.products[productVersion.productID.rawValue],
                  let resolutionVersion = state.resolutionVersions[
                    logVersion.effectiveResolutionVersionID.rawValue
                  ],
                  let resolution = state.resolutions[resolutionVersion.resolutionID.rawValue],
                  let decisionID = resolutionVersion.decisionIDs.first,
                  let decision = state.candidateDecisions[decisionID.rawValue] else {
                throw FoodLedgerStoreError.integrityFailure("incomplete food confirmation aggregate")
            }
            let evidence = decision.candidate.evidenceIDs.compactMap { state.evidence[$0.rawValue] }
            let releases = resolutionVersion.sourceReleaseIDs.compactMap { state.sourceReleases[$0.value] }
            let assertionIDs = Set(productVersion.assertionIDs + resolutionVersion.assertionIDs)
            let assertions = assertionIDs.compactMap { state.assertions[$0.rawValue] }
            guard evidence.count == decision.candidate.evidenceIDs.count,
                  releases.count == resolutionVersion.sourceReleaseIDs.count,
                  assertions.count == assertionIDs.count else {
                throw FoodLedgerStoreError.integrityFailure("incomplete food confirmation provenance")
            }
            let conversion = logVersion.quantityConversionVersionID.flatMap {
                state.quantityConversions[$0.rawValue]
            }
            let plateVersion = logVersion.plateWeightVersionID.flatMap {
                state.plateWeightVersions[$0.rawValue]
            }
            let plate = plateVersion.flatMap { state.plates[$0.plateID.rawValue] }
            return StoredFoodConfirmation(
                evidence: evidence,
                sourceReleases: releases,
                product: product,
                productVersion: productVersion,
                resolution: resolution,
                resolutionVersion: resolutionVersion,
                logItem: logItem,
                logItemVersion: logVersion,
                quantityConversion: conversion,
                plate: plate,
                plateWeightVersion: plateVersion,
                candidateDecision: decision,
                assertions: assertions.sorted { $0.createdAt < $1.createdAt }
            )
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static func apply(_ mutation: LedgerMutation, to state: inout State) throws {
        try insert(mutation.evidence, into: &state.evidence, key: { $0.evidenceID.rawValue })
        try insert(mutation.assertions, into: &state.assertions, key: { $0.assertionID.rawValue })
        try insert(mutation.products, into: &state.products, key: { $0.productID.rawValue })
        try insert(mutation.libraryEntries, into: &state.libraryEntries, key: { $0.libraryEntryID.rawValue })
        try insert(mutation.logItems, into: &state.logItems, key: { $0.logItemID.rawValue })
        try insert(mutation.plates, into: &state.plates, key: { $0.plateID.rawValue })
        try insert(mutation.sourceReleases, into: &state.sourceReleases, key: { $0.sourceReleaseID.value })
        for installation in mutation.sourceInstallations {
            guard state.sourceReleases[installation.sourceReleaseID.value] != nil else {
                throw FoodLedgerStoreError.missingReference(installation.sourceReleaseID.value)
            }
        }
        try insert(
            mutation.sourceInstallations,
            into: &state.sourceInstallations,
            key: { $0.sourceReleaseID.value }
        )

        for assertion in mutation.assertions {
            if let evidenceID = assertion.evidenceID,
               state.evidence[evidenceID.rawValue] == nil {
                throw FoodLedgerStoreError.missingReference(evidenceID.rawValue)
            }
            if let superseded = assertion.supersedesAssertionID,
               state.assertions[superseded.rawValue] == nil {
                throw FoodLedgerStoreError.missingReference(superseded.rawValue)
            }
        }
        for version in mutation.productVersions {
            guard state.products[version.productID.rawValue] != nil else {
                throw FoodLedgerStoreError.missingReference(version.productID.rawValue)
            }
            if let ancestor = version.supersedesProductVersionID {
                guard let predecessor = state.productVersions[ancestor.rawValue] else {
                    throw FoodLedgerStoreError.missingReference(ancestor.rawValue)
                }
                guard predecessor.productID == version.productID,
                      predecessor.ordinal.value < version.ordinal.value else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage product_version")
                }
                let competitors = state.productVersions.values.filter {
                    $0.supersedesProductVersionID == ancestor
                }
                try requireConflicts(
                    kind: .competingProductSuccessors,
                    ancestor: ancestor.rawValue,
                    newVersion: version.productVersionID.rawValue,
                    competitors: competitors.map(\.productVersionID.rawValue),
                    conflicts: mutation.conflicts
                )
            } else {
                guard version.ordinal.value == 1,
                      !state.productVersions.values.contains(where: {
                          $0.productID == version.productID
                      }) else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage product_version")
                }
            }
            guard version.evidenceIDs.allSatisfy({ state.evidence[$0.rawValue] != nil }),
                  version.assertionIDs.allSatisfy({ state.assertions[$0.rawValue] != nil }) else {
                throw FoodLedgerStoreError.missingReference(version.productVersionID.rawValue)
            }
            try insert([version], into: &state.productVersions, key: { $0.productVersionID.rawValue })
        }

        for version in mutation.quantityConversions {
            if let ancestor = version.supersedesQuantityConversionVersionID {
                guard let predecessor = state.quantityConversions[ancestor.rawValue] else {
                    throw FoodLedgerStoreError.missingReference(ancestor.rawValue)
                }
                guard predecessor.ordinal.value < version.ordinal.value else {
                    throw FoodLedgerStoreError.integrityFailure(
                        "invalid lineage quantity_conversion_version"
                    )
                }
                let competitors = state.quantityConversions.values.filter {
                    $0.supersedesQuantityConversionVersionID == ancestor
                }
                try requireConflicts(
                    kind: .competingQuantityVersions,
                    ancestor: ancestor.rawValue,
                    newVersion: version.quantityConversionVersionID.rawValue,
                    competitors: competitors.map(\.quantityConversionVersionID.rawValue),
                    conflicts: mutation.conflicts
                )
            } else if version.ordinal.value != 1 {
                throw FoodLedgerStoreError.integrityFailure(
                    "invalid lineage quantity_conversion_version"
                )
            }
            if let sourceReleaseID = version.sourceReleaseID,
               state.sourceReleases[sourceReleaseID.value] == nil {
                throw FoodLedgerStoreError.missingReference(sourceReleaseID.value)
            }
            if let evidenceID = version.evidenceID,
               state.evidence[evidenceID.rawValue] == nil {
                throw FoodLedgerStoreError.missingReference(evidenceID.rawValue)
            }
            try insert(
                [version],
                into: &state.quantityConversions,
                key: { $0.quantityConversionVersionID.rawValue }
            )
        }

        for version in mutation.libraryEntryVersions {
            guard state.libraryEntries[version.libraryEntryID.rawValue] != nil,
                  state.productVersions[version.productVersionID.rawValue] != nil else {
                throw FoodLedgerStoreError.missingReference(version.libraryEntryVersionID.rawValue)
            }
            if let conversion = version.quantityConversionVersionID,
               state.quantityConversions[conversion.rawValue] == nil {
                throw FoodLedgerStoreError.missingReference(conversion.rawValue)
            }
            if let ancestor = version.supersedesLibraryEntryVersionID {
                guard let predecessor = state.libraryEntryVersions[ancestor.rawValue] else {
                    throw FoodLedgerStoreError.missingReference(ancestor.rawValue)
                }
                guard predecessor.libraryEntryID == version.libraryEntryID,
                      predecessor.ordinal.value < version.ordinal.value else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage library_entry_version")
                }
                let competitors = state.libraryEntryVersions.values.filter {
                    $0.supersedesLibraryEntryVersionID == ancestor
                }
                try requireConflicts(
                    kind: .competingLibrarySuccessors,
                    ancestor: ancestor.rawValue,
                    newVersion: version.libraryEntryVersionID.rawValue,
                    competitors: competitors.map(\.libraryEntryVersionID.rawValue),
                    conflicts: mutation.conflicts
                )
            } else {
                guard version.ordinal.value == 1,
                      !state.libraryEntryVersions.values.contains(where: {
                          $0.libraryEntryID == version.libraryEntryID
                      }) else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage library_entry_version")
                }
            }
        }
        try insert(
            mutation.libraryEntryVersions,
            into: &state.libraryEntryVersions,
            key: { $0.libraryEntryVersionID.rawValue }
        )

        for resolution in mutation.resolutions {
            guard state.productVersions[resolution.productVersionID.rawValue] != nil else {
                throw FoodLedgerStoreError.missingReference(resolution.productVersionID.rawValue)
            }
        }
        try insert(mutation.resolutions, into: &state.resolutions, key: { $0.resolutionID.rawValue })
        for decision in mutation.candidateDecisions {
            guard state.sourceReleases[decision.candidate.sourceReleaseID.value] != nil else {
                throw FoodLedgerStoreError.missingReference(decision.candidate.sourceReleaseID.value)
            }
            guard decision.candidate.evidenceIDs.allSatisfy({ state.evidence[$0.rawValue] != nil }) else {
                throw FoodLedgerStoreError.missingReference(decision.candidateDecisionID.rawValue)
            }
            if let assertionID = decision.assertionID,
               state.assertions[assertionID.rawValue] == nil {
                throw FoodLedgerStoreError.missingReference(assertionID.rawValue)
            }
            try insert(
                [decision],
                into: &state.candidateDecisions,
                key: { $0.candidateDecisionID.rawValue }
            )
        }
        for version in mutation.resolutionVersions {
            guard state.resolutions[version.resolutionID.rawValue] != nil else {
                throw FoodLedgerStoreError.missingReference(version.resolutionID.rawValue)
            }
            if let ancestor = version.supersedesResolutionVersionID {
                guard let predecessor = state.resolutionVersions[ancestor.rawValue] else {
                    throw FoodLedgerStoreError.missingReference(ancestor.rawValue)
                }
                guard predecessor.resolutionID == version.resolutionID,
                      predecessor.ordinal.value < version.ordinal.value else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage resolution_version")
                }
                let competitors = state.resolutionVersions.values.filter {
                    $0.supersedesResolutionVersionID == ancestor
                }
                try requireConflicts(
                    kind: .competingResolutionSuccessors,
                    ancestor: ancestor.rawValue,
                    newVersion: version.resolutionVersionID.rawValue,
                    competitors: competitors.map(\.resolutionVersionID.rawValue),
                    conflicts: mutation.conflicts
                )
            } else {
                guard version.ordinal.value == 1,
                      !state.resolutionVersions.values.contains(where: {
                          $0.resolutionID == version.resolutionID
                      }) else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage resolution_version")
                }
            }
            guard version.sourceReleaseIDs.allSatisfy({ state.sourceReleases[$0.value] != nil }),
                  version.decisionIDs.allSatisfy({ state.candidateDecisions[$0.rawValue] != nil }),
                  version.assertionIDs.allSatisfy({ state.assertions[$0.rawValue] != nil }) else {
                throw FoodLedgerStoreError.missingReference(version.resolutionVersionID.rawValue)
            }
            try validateNutrientProvenance(version, state: state)
            try insert(
                [version],
                into: &state.resolutionVersions,
                key: { $0.resolutionVersionID.rawValue }
            )
        }

        for version in mutation.logItemVersions {
            guard state.logItems[version.logItemID.rawValue] != nil,
                  state.resolutionVersions[version.originalResolutionVersionID.rawValue] != nil,
                  state.resolutionVersions[version.effectiveResolutionVersionID.rawValue] != nil else {
                throw FoodLedgerStoreError.missingReference(version.logItemVersionID.rawValue)
            }
            if let ancestor = version.supersedesLogItemVersionID {
                guard let predecessor = state.logItemVersions[ancestor.rawValue] else {
                    throw FoodLedgerStoreError.missingReference(ancestor.rawValue)
                }
                guard predecessor.logItemID == version.logItemID,
                      predecessor.ordinal.value < version.ordinal.value else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage log_item_version")
                }
                let competitors = state.logItemVersions.values.filter {
                    $0.supersedesLogItemVersionID == ancestor
                }
                try requireConflicts(
                    kind: .competingLogCorrections,
                    ancestor: ancestor.rawValue,
                    newVersion: version.logItemVersionID.rawValue,
                    competitors: competitors.map(\.logItemVersionID.rawValue),
                    conflicts: mutation.conflicts
                )
            } else {
                guard version.ordinal.value == 1,
                      !state.logItemVersions.values.contains(where: {
                          $0.logItemID == version.logItemID
                      }) else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage log_item_version")
                }
            }
            switch version.composition {
            case let .product(productVersionID):
                guard state.productVersions[productVersionID.rawValue] != nil else {
                    throw FoodLedgerStoreError.missingReference(productVersionID.rawValue)
                }
            case let .mixture(componentIDs):
                guard componentIDs.allSatisfy({ state.logItemVersions[$0.rawValue] != nil }) else {
                    throw FoodLedgerStoreError.missingReference(version.logItemVersionID.rawValue)
                }
            }
            if let conversionID = version.quantityConversionVersionID,
               state.quantityConversions[conversionID.rawValue] == nil {
                throw FoodLedgerStoreError.missingReference(conversionID.rawValue)
            }
            if let plateID = version.plateWeightVersionID,
               state.plateWeightVersions[plateID.rawValue] == nil,
               !mutation.plateWeightVersions.contains(where: {
                   $0.plateWeightVersionID == plateID
               }) {
                throw FoodLedgerStoreError.missingReference(plateID.rawValue)
            }
            try insert(
                [version],
                into: &state.logItemVersions,
                key: { $0.logItemVersionID.rawValue }
            )
        }

        for version in mutation.plateWeightVersions {
            guard state.plates[version.plateID.rawValue] != nil else {
                throw FoodLedgerStoreError.missingReference(version.plateID.rawValue)
            }
            if let ancestor = version.supersedesPlateWeightVersionID {
                guard let predecessor = state.plateWeightVersions[ancestor.rawValue] else {
                    throw FoodLedgerStoreError.missingReference(ancestor.rawValue)
                }
                guard predecessor.plateID == version.plateID,
                      predecessor.ordinal.value < version.ordinal.value else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage plate_weight_version")
                }
                let competitors = state.plateWeightVersions.values.filter {
                    $0.supersedesPlateWeightVersionID == ancestor
                }
                try requireConflicts(
                    kind: .competingPlateVersions,
                    ancestor: ancestor.rawValue,
                    newVersion: version.plateWeightVersionID.rawValue,
                    competitors: competitors.map(\.plateWeightVersionID.rawValue),
                    conflicts: mutation.conflicts
                )
            } else {
                guard version.ordinal.value == 1,
                      !state.plateWeightVersions.values.contains(where: {
                          $0.plateID == version.plateID
                      }) else {
                    throw FoodLedgerStoreError.integrityFailure("invalid lineage plate_weight_version")
                }
            }
            if let evidenceID = version.evidenceID,
               state.evidence[evidenceID.rawValue] == nil {
                throw FoodLedgerStoreError.missingReference(evidenceID.rawValue)
            }
            try insert(
                [version],
                into: &state.plateWeightVersions,
                key: { $0.plateWeightVersionID.rawValue }
            )
        }
        try validateConflicts(mutation.conflicts, state: state)
        try insert(mutation.conflicts, into: &state.conflicts, key: { $0.conflictID.rawValue })
    }

    private static func validateNutrientProvenance(
        _ version: NutritionResolutionVersion,
        state: State
    ) throws {
        for entry in version.nutrients.entries {
            for value in [entry.value] + entry.conflictCandidates {
                for provenance in value.provenance {
                    guard version.sourceReleaseIDs.contains(provenance.sourceReleaseID),
                          state.sourceReleases[provenance.sourceReleaseID.value] != nil else {
                        throw FoodLedgerStoreError.missingReference(provenance.sourceReleaseID.value)
                    }
                    if let evidenceID = provenance.evidenceID,
                       state.evidence[evidenceID.rawValue] == nil {
                        throw FoodLedgerStoreError.missingReference(evidenceID.rawValue)
                    }
                    if let decisionID = provenance.decisionID,
                       state.candidateDecisions[decisionID.rawValue] == nil {
                        throw FoodLedgerStoreError.missingReference(decisionID.rawValue)
                    }
                    if let assertionID = provenance.assertionID,
                       state.assertions[assertionID.rawValue] == nil {
                        throw FoodLedgerStoreError.missingReference(assertionID.rawValue)
                    }
                    for transform in provenance.transforms {
                        if let conversionID = transform.quantityConversionVersionID,
                           state.quantityConversions[conversionID.rawValue] == nil {
                            throw FoodLedgerStoreError.missingReference(conversionID.rawValue)
                        }
                    }
                }
            }
        }
    }

    private static func validateConflicts(_ conflicts: [LedgerConflict], state: State) throws {
        for conflict in conflicts {
            let ancestors: [String: String?]
            switch conflict.kind {
            case .competingProductSuccessors:
                ancestors = state.productVersions.mapValues { $0.supersedesProductVersionID?.rawValue }
            case .competingLibrarySuccessors:
                ancestors = state.libraryEntryVersions.mapValues {
                    $0.supersedesLibraryEntryVersionID?.rawValue
                }
            case .competingResolutionSuccessors:
                ancestors = state.resolutionVersions.mapValues {
                    $0.supersedesResolutionVersionID?.rawValue
                }
            case .competingLogCorrections:
                ancestors = state.logItemVersions.mapValues { $0.supersedesLogItemVersionID?.rawValue }
            case .competingQuantityVersions:
                ancestors = state.quantityConversions.mapValues {
                    $0.supersedesQuantityConversionVersionID?.rawValue
                }
            case .competingPlateVersions:
                ancestors = state.plateWeightVersions.mapValues {
                    $0.supersedesPlateWeightVersionID?.rawValue
                }
            }
            guard ancestors[conflict.ancestorVersionID.value] != nil else {
                throw FoodLedgerStoreError.missingReference(conflict.ancestorVersionID.value)
            }
            for competitor in conflict.competingVersionIDs {
                guard ancestors[competitor.value] == conflict.ancestorVersionID.value else {
                    throw FoodLedgerStoreError.integrityFailure("invalid conflict ancestry")
                }
            }
        }
    }

    private static func insert<Value>(
        _ values: [Value],
        into dictionary: inout [String: Value],
        key: (Value) -> String
    ) throws {
        for value in values {
            let identifier = key(value)
            guard dictionary[identifier] == nil else {
                throw FoodLedgerStoreError.immutableRecord(identifier)
            }
            dictionary[identifier] = value
        }
    }

    private static func requireConflicts(
        kind: ConflictKind,
        ancestor: String,
        newVersion: String,
        competitors: [String],
        conflicts: [LedgerConflict]
    ) throws {
        for competitor in competitors where competitor != newVersion {
            let recorded = conflicts.contains { conflict in
                conflict.kind == kind
                    && conflict.ancestorVersionID.value == ancestor
                    && Set(conflict.competingVersionIDs.map(\.value))
                        .isSuperset(of: [competitor, newVersion])
            }
            guard recorded else {
                throw FoodLedgerStoreError.integrityFailure("unrecorded competing successor")
            }
        }
    }
}
