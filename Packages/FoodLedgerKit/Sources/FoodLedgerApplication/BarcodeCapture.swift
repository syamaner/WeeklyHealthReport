import Foundation
import FoodLedgerDomain

public enum BarcodeCameraAuthorization: Equatable, Sendable {
    case authorised
    case denied
    case unavailable
}

public struct BarcodeScan: Equatable, Sendable {
    public let code: LedgerText
    public let symbology: BarcodeSymbology
    public let originalSymbology: LedgerText
    public let capturedAt: Date
    public let locale: LedgerText
    public let captureMethod: LedgerText
    public let captureMethodVersion: LedgerText
    public let localNamespace: LedgerText?

    public init(
        code: LedgerText,
        symbology: BarcodeSymbology,
        originalSymbology: LedgerText,
        capturedAt: Date,
        locale: LedgerText,
        captureMethod: LedgerText,
        captureMethodVersion: LedgerText,
        localNamespace: LedgerText? = nil
    ) {
        self.code = code
        self.symbology = symbology
        self.originalSymbology = originalSymbology
        self.capturedAt = capturedAt
        self.locale = locale
        self.captureMethod = captureMethod
        self.captureMethodVersion = captureMethodVersion
        self.localNamespace = localNamespace
    }
}

@MainActor
public protocol BarcodeScanning: AnyObject {
    func authorization() async -> BarcodeCameraAuthorization
    func scan() async throws -> BarcodeScan
}

@MainActor
public final class NamespacedBarcodeScanner: BarcodeScanning {
    private let base: any BarcodeScanning
    private let namespace: LedgerText

    public init(base: any BarcodeScanning, namespace: LedgerText) {
        self.base = base
        self.namespace = namespace
    }

    public func authorization() async -> BarcodeCameraAuthorization {
        await base.authorization()
    }

    public func scan() async throws -> BarcodeScan {
        let value = try await base.scan()
        return BarcodeScan(
            code: value.code,
            symbology: value.symbology,
            originalSymbology: value.originalSymbology,
            capturedAt: value.capturedAt,
            locale: value.locale,
            captureMethod: value.captureMethod,
            captureMethodVersion: value.captureMethodVersion,
            localNamespace: namespace
        )
    }
}

public struct BarcodeReuseReference: Equatable, Sendable {
    public let libraryEntryVersionID: LibraryEntryVersionID
    public let productVersionID: ProductVersionID
    public let resolutionVersionID: ResolutionVersionID

    public init(record: BarcodeLibraryRecord) {
        libraryEntryVersionID = record.libraryEntryVersion.libraryEntryVersionID
        productVersionID = record.productVersion.productVersionID
        resolutionVersionID = record.resolutionVersion.resolutionVersionID
    }
}

public struct BarcodeConfirmationRoute: Equatable, Sendable {
    public let confirmation: PopulatedFoodConfirmation
    public let reuse: BarcodeReuseReference
}

public enum BarcodeFallbackReason: Equatable, Sendable {
    case malformed(BarcodeClassificationError)
    case noLocalMatch
    case ambiguousLocalMatches(Int)
    case weakLocalMatch
}

public struct BarcodeFallbackRoute: Equatable, Sendable {
    public let evidence: CaptureEvidence
    public let identity: BarcodeIdentity?
    public let reason: BarcodeFallbackReason
    public let labelPhotoTitle: String
    public let guidance: String

    public init(
        evidence: CaptureEvidence,
        identity: BarcodeIdentity?,
        reason: BarcodeFallbackReason
    ) {
        self.evidence = evidence
        self.identity = identity
        self.reason = reason
        labelPhotoTitle = "Photograph the nutrition label"
        guidance = "The barcode evidence will be kept with the next populated route. You can photograph the label or use generic search; no blank nutrient form will be opened."
    }
}

public struct BarcodePermissionGuidance: Equatable, Sendable {
    public let title: String
    public let message: String
    public let labelPhotoTitle: String
    public let genericSearchTitle: String

    public init(unavailable: Bool) {
        title = unavailable ? "Barcode camera unavailable" : "Camera access is off"
        message = unavailable
            ? "This device cannot scan a barcode here. Use label photography on a supported device or continue with generic search."
            : "Enable camera access in Settings, or continue with label photography or generic search. Nothing has been captured."
        labelPhotoTitle = "Use label photography"
        genericSearchTitle = "Use generic search"
    }
}

public enum BarcodeCaptureOutcome: Equatable, Sendable {
    case confirmation(BarcodeConfirmationRoute)
    case fallback(BarcodeFallbackRoute)
    case permissionGuidance(BarcodePermissionGuidance)
}

public enum BarcodeMatchStrength: Equatable, Sendable {
    case exact
    case weak
}

public struct BarcodeLibraryMatch: Equatable, Sendable {
    public let record: BarcodeLibraryRecord
    public let strength: BarcodeMatchStrength

    public init(record: BarcodeLibraryRecord, strength: BarcodeMatchStrength) {
        self.record = record
        self.strength = strength
    }
}

public protocol BarcodeLibrarySearching: Sendable {
    func matches(alias: LedgerText) throws -> [BarcodeLibraryMatch]
}

public struct PersonalLibraryBarcodeSearch: BarcodeLibrarySearching, Sendable {
    private let reader: any LedgerReading

    public init(reader: any LedgerReading) {
        self.reader = reader
    }

    public func matches(alias: LedgerText) throws -> [BarcodeLibraryMatch] {
        try reader.barcodeLibraryRecords(alias: alias).map {
            BarcodeLibraryMatch(record: $0, strength: .exact)
        }
    }
}

public final class BarcodeCaptureCoordinator: @unchecked Sendable {
    private let search: any BarcodeLibrarySearching
    private let ids: any LedgerIDGenerating

    public init(search: any BarcodeLibrarySearching, ids: any LedgerIDGenerating) {
        self.search = search
        self.ids = ids
    }

    @MainActor
    public func capture(using scanner: any BarcodeScanning) async throws -> BarcodeCaptureOutcome {
        switch await scanner.authorization() {
        case .denied:
            return .permissionGuidance(BarcodePermissionGuidance(unavailable: false))
        case .unavailable:
            return .permissionGuidance(BarcodePermissionGuidance(unavailable: true))
        case .authorised:
            return try route(scan: try await scanner.scan())
        }
    }

    public func route(scan: BarcodeScan) throws -> BarcodeCaptureOutcome {
        let evidence = try CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self),
            kind: .barcode,
            capturedAt: scan.capturedAt,
            locale: scan.locale,
            captureMethod: scan.captureMethod,
            captureMethodVersion: scan.captureMethodVersion,
            originalPayload: .barcode(value: scan.code, symbology: scan.originalSymbology)
        )

        let identity: BarcodeIdentity
        do {
            identity = try BarcodeClassifier.classify(
                code: scan.code,
                symbology: scan.symbology,
                localNamespace: scan.localNamespace
            )
        } catch let error as BarcodeClassificationError {
            return .fallback(BarcodeFallbackRoute(
                evidence: evidence,
                identity: nil,
                reason: .malformed(error)
            ))
        }

        let matches = try search.matches(alias: identity.lookupAlias)
        let records = matches.filter { $0.strength == .exact }.map(\.record)
        if records.isEmpty, !matches.isEmpty {
            return .fallback(BarcodeFallbackRoute(
                evidence: evidence,
                identity: identity,
                reason: .weakLocalMatch
            ))
        }
        guard records.count == 1, let record = records.first else {
            return .fallback(BarcodeFallbackRoute(
                evidence: evidence,
                identity: identity,
                reason: records.isEmpty ? .noLocalMatch : .ambiguousLocalMatches(records.count)
            ))
        }

        let quantity = record.libraryEntryVersion.reusableQuantity
            .map { EdibleQuantityIdentity.known(
                $0,
                conversionVersionID: record.libraryEntryVersion.quantityConversionVersionID
            ) } ?? .unknown
        let sourceRelease = record.sourceReleases.first
        guard let sourceRelease else {
            throw FoodLedgerValidationError.missingProvenance
        }
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(
                sourceReleaseID: sourceRelease.sourceReleaseID,
                recordID: ExternalIdentifier(
                    "personal-library:\(record.libraryEntryVersion.libraryEntryVersionID.rawValue)"
                ),
                identity: record.productVersion.identity,
                edibleQuantity: quantity,
                nutrients: record.resolutionVersion.nutrients,
                evidenceIDs: [evidence.evidenceID]
            ),
            name: record.productVersion.name,
            brand: record.productVersion.brand,
            variant: record.productVersion.variant,
            barcode: record.productVersion.barcode,
            itemClass: record.productVersion.itemClass,
            packFacts: record.productVersion.packFacts
        )
        let confirmation = try PopulatedFoodConfirmation(
            evidence: [evidence],
            sourceReleases: [sourceRelease],
            candidates: [candidate],
            expectedIdentity: record.productVersion.identity,
            expectedEdibleQuantity: quantity
        )
        return .confirmation(BarcodeConfirmationRoute(
            confirmation: confirmation,
            reuse: BarcodeReuseReference(record: record)
        ))
    }
}
