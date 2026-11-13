import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import Foundation
import XCTest

/// P1c lifecycle (import v1 sections 7 and 9; phase 1 plan sections 4 and 5.1 item 1): a database
/// log saves with every cited release, needs its identity facts on Confirm (the 12 November 2026
/// amendment), survives removal with its release records, and re-resolves only while a file holding
/// its entry is installed. Synthetic fixtures only.
final class PersonalFoodDatabaseLifecycleContractTests: XCTestCase {
    static let golden = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/fixtures/personal-food-database-v1/golden.json")

    func install(_ store: InMemoryPersonalFoodDatabaseStore, _ bytes: Data) throws {
        let digest = try SHA256Digester().sha256(bytes)
        guard case let .success(file) = PersonalFoodDatabaseCodec.decode(bytes) else { return XCTFail("golden decodes") }
        try store.install(bytes: bytes, manifest: PersonalFoodDatabaseManifest(schema: PersonalFoodDatabaseSchema.v1.rawValue,
            releaseID: PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest), fileSHA256: digest, generated: file.generated,
            importedAt: Date(timeIntervalSince1970: 1_794_000_000), entryCount: file.entries.count))
    }

    func testSaveRemoveAndReresolve() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let bytes = try Data(contentsOf: Self.golden)
            let store = InMemoryPersonalFoodDatabaseStore()
            try install(store, bytes)
            let resolver = GenericRecordResolverSet([:])
            let index = PersonalFoodDatabaseIndex(store: store, resolver: resolver)
            index.warm()
            let search = PersonalFoodDatabaseFoodSearch(index: index, resolver: resolver, ids: RandomLedgerIDGenerator())
            guard case let .confirmation(route) = try search.search(GenericFoodSearchRequest(
                text: LedgerText("synthetic crème spread"), capturedAt: LedgerFixtures.clock.now(), locale: LedgerText("en-GB")))
            else { return XCTFail("the spread entry is found") }
            let input = try XCTUnwrap(route.choosing(0))
            let candidate = input.candidates[0]
            XCTAssertEqual(candidate.candidate.sourceReleaseID.value.hasPrefix("pfc:sha256:"), true)

            var state = FoodConfirmationState(input: input)
            XCTAssertFalse(FoodConfirmationPolicy.isGenericEstimate(input, candidate: candidate))
            XCTAssertFalse(state.unresolvedIdentity.isEmpty, "Confirm asks for the unknown identity facts")
            state.correction = FoodCorrection(name: candidate.name, brand: candidate.brand, variant: candidate.variant,
                identity: try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .notApplicable, skin: .notApplicable,
                    drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified,
                    servingBasis: .per100Grams),
                itemClass: candidate.itemClass, nutrients: candidate.candidate.nutrients, reason: try LedgerText("Identity confirmed"))
            XCTAssertTrue(state.unresolvedIdentity.isEmpty)
            state.decision = .accepted
            state.quantity.value = 30

            let ledger = try LedgerFixtures.service(harness.committer)
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let record = try FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock,
                ids: RandomLedgerIDGenerator(), digester: SHA256Digester()).save(state, operationID: LedgerFixtures.operationID(700))
            let cited = Set(route.confirmation.sourceReleases.map(\.sourceReleaseID))
            for id in cited { XCTAssertNotNil(try harness.reader.sourceRelease(id: id), id.value) }
            guard case .measured? = record.resolutionVersion.nutrients.entries.first(where: { $0.key == .sodium })?.value else {
                return XCTFail("the owner value saves as measured")
            }

            // The food export carries what any saved log carries: opaque release IDs, the owner
            // value as entered by you and calculated from salt.
            let document = try FoodDailyExportBuilder.make(FoodDailyExportRequest(
                records: archive.archiveState().records, reportDate: record.logItemVersion.reportingDate.value,
                timeZone: TimeZone(identifier: "UTC")!, dataAsOf: LedgerFixtures.date.addingTimeInterval(86_400 * 2),
                exportedAt: LedgerFixtures.date.addingTimeInterval(86_400 * 2), appContext: FoodDailyExportAppContext(appVersion: "0", appBuild: "0")))
            let json = String(decoding: try FoodDailyExportSerializer.encode(document), as: UTF8.self)
            XCTAssertTrue(json.contains("entered_by_you"))
            XCTAssertTrue(json.contains("\"calculated\":true"))
            for id in cited { XCTAssertFalse(id.value.contains("Spread") || id.value.contains("Crème"), id.value) }

            let providers = FoodReresolutionProviderSet([PersonalFoodDatabaseReresolutionProvider(
                index: index, resolver: resolver, ids: RandomLedgerIDGenerator())])
            let service = FoodReresolutionService(ledger: ledger,
                reader: FoodReresolutionHistory(archive: archive, confirmations: harness.reader),
                provider: providers, clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator())
            let target = try XCTUnwrap(service.targets().first)
            XCTAssertFalse(try service.proposals(logItemID: record.logItem.logItemID, target: target).isEmpty)

            // Remove: the log and every release record stay; re-resolution has no target.
            try store.remove()
            index.invalidate(); index.warm()
            XCTAssertTrue(try service.targets().isEmpty)
            XCTAssertThrowsError(try service.proposals(logItemID: record.logItem.logItemID, target: target)) {
                XCTAssertEqual($0 as? FoodReresolutionError, .unavailableTarget)
            }
            XCTAssertEqual(try harness.reader.foodConfirmation(logItemID: record.logItem.logItemID)?.logItemVersion, record.logItemVersion)
            for id in cited { XCTAssertNotNil(try harness.reader.sourceRelease(id: id), id.value) }

            // Re-import: the same entry re-resolves again.
            try install(store, bytes)
            index.invalidate(); index.warm()
            XCTAssertFalse(try service.proposals(logItemID: record.logItem.logItemID, target: target).isEmpty)
        }
    }
}
