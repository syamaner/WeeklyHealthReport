import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class BarcodeCaptureTests: XCTestCase {
    func testExactOfflineLibraryMatchPopulatesSharedConfirmationAndExactVersions() throws {
        let record = try Fixtures.record(seed: 10)
        let coordinator = BarcodeCaptureCoordinator(
            search: FixedSearch(records: [record]),
            ids: SequenceIDs()
        )

        let outcome = try coordinator.route(scan: Fixtures.gtinScan)
        guard case let .confirmation(route) = outcome else {
            return XCTFail("Expected populated confirmation")
        }
        XCTAssertEqual(route.confirmation.candidates.count, 1)
        XCTAssertEqual(route.confirmation.candidates[0].name.value, "Fixture oats")
        XCTAssertEqual(route.confirmation.evidence[0].capturedAt, Fixtures.date)
        XCTAssertEqual(
            route.confirmation.evidence[0].originalPayload,
            .barcode(value: try LedgerText("4006381333931"), symbology: try LedgerText("VNBarcodeSymbologyEAN13"))
        )
        XCTAssertEqual(route.reuse.productVersionID, record.productVersion.productVersionID)
        XCTAssertEqual(route.reuse.resolutionVersionID, record.resolutionVersion.resolutionVersionID)
    }

    func testAmbiguousReformulationsPreserveEvidenceAndRouteToFallback() throws {
        let coordinator = BarcodeCaptureCoordinator(
            search: FixedSearch(records: [try Fixtures.record(seed: 20), try Fixtures.record(seed: 30)]),
            ids: SequenceIDs()
        )

        let outcome = try coordinator.route(scan: Fixtures.gtinScan)
        guard case let .fallback(route) = outcome else { return XCTFail("Expected fallback") }
        XCTAssertEqual(route.reason, .ambiguousLocalMatches(2))
        XCTAssertEqual(route.evidence.originalPayload, .barcode(
            value: try LedgerText("4006381333931"),
            symbology: try LedgerText("VNBarcodeSymbologyEAN13")
        ))
        XCTAssertTrue(route.guidance.contains("no blank nutrient form"))
    }

    func testMissPreservesEvidenceForAvailableGenericSearchRouting() throws {
        let outcome = try BarcodeCaptureCoordinator(
            search: FixedSearch(records: []),
            ids: SequenceIDs()
        ).route(scan: Fixtures.gtinScan)

        guard case let .fallback(route) = outcome else { return XCTFail("Expected fallback") }
        XCTAssertEqual(route.reason, .noLocalMatch)
        XCTAssertEqual(route.evidence.kind, .barcode)
        XCTAssertTrue(route.guidance.contains("generic food search"))
        XCTAssertFalse(route.guidance.contains("photograph"))
    }

    func testPermissionGuidanceOffersOnlyAvailableBetaRoute() {
        for unavailable in [false, true] {
            let guidance = BarcodePermissionGuidance(unavailable: unavailable)
            XCTAssertTrue(guidance.message.contains("generic food search"))
            XCTAssertFalse(guidance.message.contains("label"))
        }
    }

    func testLookupFailureRetainsCapturedBarcodeForRecovery() throws {
        let coordinator = BarcodeCaptureCoordinator(search: UnavailableSearch(), ids: SequenceIDs())
        guard case let .fallback(route) = try coordinator.route(scan: Fixtures.gtinScan) else {
            return XCTFail("Expected recoverable lookup failure")
        }
        XCTAssertEqual(route.reason, .lookupUnavailable)
        XCTAssertEqual(route.evidence.kind, .barcode)
        XCTAssertTrue(route.guidance.contains("could not finish"))
    }

    func testWeakCandidateNeverPopulatesOrSilentlyAccepts() throws {
        let record = try Fixtures.record(seed: 40)
        let outcome = try BarcodeCaptureCoordinator(
            search: FixedSearch(matches: [BarcodeLibraryMatch(record: record, strength: .weak)]),
            ids: SequenceIDs()
        ).route(scan: Fixtures.gtinScan)

        guard case let .fallback(route) = outcome else { return XCTFail("Expected fallback") }
        XCTAssertEqual(route.reason, .weakLocalMatch)
        XCTAssertEqual(route.evidence.kind, .barcode)
    }

    func testMalformedCapturePreservesOriginalEvidenceWithoutSearching() throws {
        let search = CountingSearch()
        let malformed = BarcodeScan(
            code: try LedgerText("4006381333932"),
            symbology: .ean13,
            originalSymbology: try LedgerText("VNBarcodeSymbologyEAN13"),
            capturedAt: Fixtures.date,
            locale: try LedgerText("en_GB"),
            captureMethod: try LedgerText("visionkit"),
            captureMethodVersion: try LedgerText("visionkit-barcode-v1")
        )

        let outcome = try BarcodeCaptureCoordinator(search: search, ids: SequenceIDs()).route(scan: malformed)
        guard case let .fallback(route) = outcome else { return XCTFail("Expected fallback") }
        XCTAssertEqual(route.reason, .malformed(.invalidGTINCheckDigit))
        XCTAssertEqual(route.evidence.capturedAt, Fixtures.date)
        XCTAssertEqual(search.calls, 0)
    }

    func testNamespacedRetailerCodeUsesSeparateLocalAlias() throws {
        let search = CountingSearch()
        let scan = BarcodeScan(
            code: try LedgerText("29161201"),
            symbology: .code128,
            originalSymbology: try LedgerText("VNBarcodeSymbologyCode128"),
            capturedAt: Fixtures.date,
            locale: try LedgerText("en_GB"),
            captureMethod: try LedgerText("visionkit"),
            captureMethodVersion: try LedgerText("visionkit-barcode-v1"),
            localNamespace: try LedgerText("marks-and-spencer")
        )

        _ = try BarcodeCaptureCoordinator(search: search, ids: SequenceIDs()).route(scan: scan)
        XCTAssertEqual(search.aliases.map(\.value), ["barcode:local:marks-and-spencer:29161201"])
    }
}

private struct UnavailableSearch: BarcodeLibrarySearching {
    func matches(alias: LedgerText) throws -> [BarcodeLibraryMatch] { throw CocoaError(.fileReadUnknown) }
}

private enum Fixtures {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    static var gtinScan: BarcodeScan {
        get throws {
            BarcodeScan(
                code: try LedgerText("4006381333931"),
                symbology: .ean13,
                originalSymbology: try LedgerText("VNBarcodeSymbologyEAN13"),
                capturedAt: date,
                locale: try LedgerText("en_GB"),
                captureMethod: try LedgerText("visionkit"),
                captureMethodVersion: try LedgerText("visionkit-barcode-v1")
            )
        }
    }

    static func record(seed: Int) throws -> BarcodeLibraryRecord {
        let evidenceID: EvidenceID = try id(seed + 1)
        let productVersionID: ProductVersionID = try id(seed + 2)
        let identity = try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold),
            bone: .notApplicable,
            skin: .notApplicable,
            drained: .notApplicable,
            packingMedium: .named(LedgerText("none")),
            fortification: .unfortified,
            servingBasis: .per100Grams
        )
        let releaseID = try ExternalIdentifier("package:fixture-v1")
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map {
            try NutrientEntry(key: $0, value: .unknown(.notDeclared))
        })
        let entry = try LibraryEntryVersion(
            libraryEntryVersionID: id(seed + 3),
            libraryEntryID: id(seed + 4),
            ordinal: VersionOrdinal(1),
            productVersionID: productVersionID,
            aliases: [LedgerText("barcode:gtin:04006381333931")],
            reusableQuantity: PositiveQuantity(value: 40, unit: .grams),
            createdAt: date
        )
        let product = try ProductVersion(
            productVersionID: productVersionID,
            productID: id(seed + 5),
            ordinal: VersionOrdinal(1),
            name: LedgerText("Fixture oats"),
            barcode: LedgerText("4006381333931"),
            itemClass: .food,
            packFacts: PackFacts(),
            identity: identity,
            evidenceIDs: [evidenceID],
            assertionIDs: [],
            createdAt: date
        )
        let resolution = NutritionResolution(
            resolutionID: try id(seed + 6),
            productVersionID: productVersionID,
            basis: .per100Grams,
            createdAt: date
        )
        let version = try NutritionResolutionVersion(
            resolutionVersionID: id(seed + 7),
            resolutionID: resolution.resolutionID,
            ordinal: VersionOrdinal(1),
            methodVersion: LedgerText("fixture-v1"),
            sourceReleaseIDs: [releaseID],
            nutrients: nutrients,
            createdAt: date
        )
        let release = SourceRelease(
            sourceReleaseID: releaseID,
            sourceID: try ExternalIdentifier("physical-package"),
            releasedAt: date,
            artifactHash: try SHA256Digest(String(repeating: "a", count: 64)),
            schemaVersion: try LedgerText("food-contract-v1"),
            pipelineVersion: try LedgerText("manual-v1"),
            licence: try LedgerText("user evidence"),
            attribution: try LedgerText("fixture"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64))
        )
        return try BarcodeLibraryRecord(
            libraryEntryVersion: entry,
            productVersion: product,
            resolution: resolution,
            resolutionVersion: version,
            sourceReleases: [release]
        )
    }

    private static func id<Tag>(_ value: Int) throws -> LedgerID<Tag> {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}

private struct FixedSearch: BarcodeLibrarySearching {
    let matchesToReturn: [BarcodeLibraryMatch]
    init(records: [BarcodeLibraryRecord]) {
        matchesToReturn = records.map { BarcodeLibraryMatch(record: $0, strength: .exact) }
    }
    init(matches: [BarcodeLibraryMatch]) { matchesToReturn = matches }
    func matches(alias: LedgerText) throws -> [BarcodeLibraryMatch] { matchesToReturn }
}

private final class CountingSearch: BarcodeLibrarySearching, @unchecked Sendable {
    private(set) var aliases: [LedgerText] = []
    var calls: Int { aliases.count }
    func matches(alias: LedgerText) throws -> [BarcodeLibraryMatch] {
        aliases.append(alias)
        return []
    }
}

private final class SequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 900
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
