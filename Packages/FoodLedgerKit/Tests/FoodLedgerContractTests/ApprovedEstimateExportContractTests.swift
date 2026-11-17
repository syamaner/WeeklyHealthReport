import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Daily export version 3 (estimates on catalogue v2, contract section 7; estimates v1 section 7),
/// built from logs saved through the confirmation service. Synthetic data only.
final class ApprovedEstimateExportContractTests: XCTestCase {
    typealias Confirm = ApprovedEstimateConfirmContractTests

    private final class SequentialIDs: LedgerIDGenerating, @unchecked Sendable {
        private var value = 0x5110000
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            defer { value += 1 }
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
        }
    }

    static let day = "2023-11-14"
    static let app = FoodDailyExportAppContext(appVersion: "0.1.1", appBuild: "42")

    /// Saves the given entries on one synthetic day and returns the snapshot's export.
    static func export(_ entries: [(title: String, leftOut: [NutrientKey])], lookup: Confirm.Lookup = .init())
        throws -> (document: FoodDailyExportDocument, saved: [StoredFoodConfirmation]) {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let ids = SequentialIDs()
        let service = try Confirm.service(harness, lookup: lookup, ids: ids)
        var saved: [StoredFoodConfirmation] = []
        for (index, entry) in entries.enumerated() {
            var state = try Confirm.state(service, [entry.title], grams: 50, ids: ids)
            for key in entry.leftOut { FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(key)) }
            saved.append(try service.save(state, operationID: try ids.makeID(OperationTag.self),
                                          idempotencyKey: try LedgerText("export-\(index)")))
        }
        let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
        let request = FoodDailyExportRequest(records: try archive.archiveState().records, reportDate: day,
            timeZone: TimeZone(identifier: "UTC")!, dataAsOf: LedgerFixtures.date.addingTimeInterval(60),
            exportedAt: LedgerFixtures.date.addingTimeInterval(120), appContext: app)
        return (try FoodDailyExportBuilder.make(request), saved)
    }

    static func value(_ document: FoodDailyExportDocument, entry: Int, _ key: NutrientKey) throws -> FoodDailyExportNutrientValue {
        try XCTUnwrap(document.entries[entry].nutrients.first { $0.key == key.rawValue })
    }

    func testADocumentWithAnApprovedEstimateIsSchemaThreeWithItsEstimateFields() throws {
        let (document, saved) = try Self.export([(Confirm.bar, []), (Confirm.fish, []), (Confirm.crisps, [])])
        XCTAssertEqual(document.foodDailySchemaVersion, 3)
        XCTAssertEqual(document.summaryVersion, "food-intake-summary-v6")
        XCTAssertNoThrow(try FoodDailyExportShape.validate(document))
        // A page estimate: state estimated, the closed tokens, the page address, and no content hash
        // when no artefact was kept.
        let fibre = try Self.value(document, entry: 0, .fiber)
        XCTAssertEqual(fibre.state, "estimated")
        XCTAssertEqual(fibre.origin, "approved_estimate")
        XCTAssertEqual(fibre.amount, 3.25, "6.5 g per 100 g at 50 g")
        let page = try XCTUnwrap(fibre.provenance?.first)
        XCTAssertEqual(page.sourceKind, "approved_estimate")
        XCTAssertEqual([page.estimateSourceType, page.estimateMethod, page.estimateStateBasis, page.estimateQuality],
                       ["manufacturer_page", "direct", "source_states_it", "high"])
        XCTAssertEqual(page.sourceURL, "https://www.example.com/products/synthetic")
        XCTAssertNil(page.contentHash, "omitted when source_digest is null")
        // A label value beside it keeps its own origin and carries no estimate field.
        let energy = try Self.value(document, entry: 0, .energyConsumed)
        XCTAssertNotEqual(energy.origin, "approved_estimate")
        XCTAssertTrue(energy.provenance?.allSatisfy { $0.estimateQuality == nil && $0.estimateMethod == nil } ?? false)
        // A composition estimate: the tokens, no page address.
        let protein = try XCTUnwrap(try Self.value(document, entry: 1, .protein).provenance?.first)
        XCTAssertEqual([protein.estimateSourceType, protein.estimateMethod, protein.estimateQuality],
                       ["national_composition", "carried_from_same_food", "high"])
        XCTAssertNil(protein.sourceURL)
        // A derived estimate is calculated; a retained artefact's digest is the content hash, never
        // the capture manifest's own hash.
        let sodium = try Self.value(document, entry: 2, .sodium)
        XCTAssertEqual(sodium.calculated, true)
        XCTAssertEqual(sodium.provenance?.first?.estimateQuality, "medium")
        let kept = try XCTUnwrap(try Self.value(document, entry: 2, .fiber).provenance?.first)
        XCTAssertEqual(kept.contentHash, String(repeating: "1", count: 64))
        XCTAssertEqual(kept.estimateStateBasis, "unknown")
        let manifestHashes = saved.flatMap(\.evidence).filter(ApprovedEstimateSource.isManifest).compactMap { $0.byteHash?.value }
        XCTAssertFalse(manifestHashes.contains(kept.contentHash ?? ""))
        // No free text leaves: no state, no assumption. Totals carry no tier.
        let text = String(decoding: try FoodDailyExportSerializer.encode(document), as: UTF8.self)
        XCTAssertFalse(text.contains("Synthetic assumption") || text.contains("as described by the record"))
        XCTAssertFalse(text.contains("\"summary\":[{\"estimate_quality"))
        let total = try XCTUnwrap(document.summary.first { $0.key == "fiber" })
        XCTAssertEqual(total.includesEstimates, true)
    }

    func testAWithheldOrLeftOutValueExportsAsUnknownAndADayWithoutAnEstimateIsSchemaTwo() throws {
        // Fibre left out by the owner; sodium stays an estimate: still schema 3, fibre unknown.
        let (partial, _) = try Self.export([(Confirm.crisps, [.fiber])])
        XCTAssertEqual(partial.foodDailySchemaVersion, 3)
        let fibre = try Self.value(partial, entry: 0, .fiber)
        XCTAssertEqual(fibre.state, "unknown")
        XCTAssertEqual(fibre.reason, "no_compatible_source")
        XCTAssertNil(fibre.amount, "unknown, never zero")
        let total = try XCTUnwrap(partial.summary.first { $0.key == "fiber" })
        XCTAssertNotEqual(total.state, "complete", "the day's total stays partial")
        // The bar's only estimate left out: label values remain, no approved estimate is held, so the
        // document is written as schema 2.
        let (plain, _) = try Self.export([(Confirm.bar, [.fiber])])
        XCTAssertEqual(plain.foodDailySchemaVersion, 2)
        XCTAssertNoThrow(try FoodDailyExportShape.validate(plain))
        XCTAssertFalse(String(decoding: try FoodDailyExportSerializer.encode(plain), as: UTF8.self).contains("estimate_"))
        // A withheld value (its record could not be read) is unknown in the same way.
        var missing = Confirm.Lookup()
        missing.preparations["cofid:cheese"] = nil
        let (withheld, _) = try Self.export([(Confirm.cheese, [])], lookup: missing)
        XCTAssertEqual(try Self.value(withheld, entry: 0, .calcium).state, "unknown")
        XCTAssertEqual(withheld.foodDailySchemaVersion, 3, "the kept protein estimate")
    }

    func testAnEstimateWhoseManifestIsMissingProducesNoFile() throws {
        let (_, saved) = try Self.export([(Confirm.bar, [])])
        let log = saved[0]
        var records = LedgerMutation(evidence: log.evidence.filter { !ApprovedEstimateSource.isManifest($0) },
            products: [log.product], productVersions: [log.productVersion], resolutions: [log.resolution],
            resolutionVersions: [log.resolutionVersion], logItems: [log.logItem], logItemVersions: [log.logItemVersion],
            candidateDecisions: [log.candidateDecision], sourceReleases: log.sourceReleases)
        records.assertions = log.assertions
        let request = FoodDailyExportRequest(records: records, reportDate: Self.day, timeZone: TimeZone(identifier: "UTC")!,
            dataAsOf: LedgerFixtures.date.addingTimeInterval(60), exportedAt: LedgerFixtures.date.addingTimeInterval(120), appContext: Self.app)
        XCTAssertThrowsError(try FoodDailyExportBuilder.make(request)) {
            XCTAssertEqual($0 as? FoodDailyExportError, .missingReference, "fail closed")
        }
    }

    /// `RECORD_FOOD_DAILY_V3_GOLDENS=1` writes only `docs/fixtures/food-daily-v3/`.
    func testTheEstimatesDayGoldenIsByteStable() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/fixtures/food-daily-v3").standardizedFileURL
        let (document, _) = try Self.export([(Confirm.bar, []), (Confirm.fish, []), (Confirm.crisps, [.fiber])])
        let bytes = try FoodDailyExportSerializer.encode(document)
        let url = directory.appendingPathComponent("food-daily-estimates-day.json")
        if ProcessInfo.processInfo.environment["RECORD_FOOD_DAILY_V3_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: url)
        }
        let golden = try Data(contentsOf: url)
        XCTAssertEqual(bytes, golden, "the estimates day drifted from its golden")
        let decoded = try FoodDailyExportSerializer.decode(golden)
        XCTAssertEqual(try FoodDailyExportSerializer.encode(decoded), golden, "re-encodes byte for byte")
        XCTAssertEqual(decoded.foodDailySchemaVersion, 3)
        XCTAssertNoThrow(try FoodDailyExportShape.validate(decoded))
        XCTAssertFalse(String(decoding: golden, as: UTF8.self).contains("\n"), "one line, no pretty printing")
    }
}
