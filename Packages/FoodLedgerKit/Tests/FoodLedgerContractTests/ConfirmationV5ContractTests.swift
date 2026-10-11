import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerArchive
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import Foundation
import XCTest

/// Contract tests for food_confirmation_v5 (#195) across the memory and GRDB adapters.
final class ConfirmationV5ContractTests: XCTestCase {
    // MARK: 7. Historical payloads re-encode byte for byte

    func testHistoricalAssertionPayloadsReencodeExactlyWithoutDecisionKey() throws {
        let literals = [
            #"{"assertionID":"00000000-0000-0000-0000-000000000010","author":{"user":{}},"claim":"Accepted explained closest match; differences: preparation","createdAt":1700000000000,"evidenceID":"00000000-0000-0000-0000-000000000001","reason":"Closest available match"}"#,
            #"{"assertionID":"00000000-0000-0000-0000-000000000011","author":{"user":{}},"claim":"Accepted estimate under food_confirmation_v4; not verified product identity","createdAt":1700000000000,"reason":"Explicitly accepted generic composition estimate; unknown source details remain unknown","supersedesAssertionID":"00000000-0000-0000-0000-000000000010"}"#
        ]
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        for literal in literals {
            let bytes = Data(literal.utf8)
            let decoded = try decoder.decode(UserAssertion.self, from: bytes)
            XCTAssertNil(decoded.confirmation)
            XCTAssertEqual(try LedgerFixtures.encoder.encode(decoded), bytes)
            XCTAssertEqual(try LedgerFixtures.digester.sha256(LedgerFixtures.encoder.encode(decoded)),
                           try LedgerFixtures.digester.sha256(bytes))
        }
        let record = try FoodLogDecisionRecord(policyVersion: LedgerText("food_confirmation_v5"), decisions: [
            FoodLogFacetDecision(facet: .skin, sourceState: FoodLogSourceState(facet: .skin, token: "skinless"), choice: .notSure)])
        let withDecision = UserAssertion(assertionID: try LedgerFixtures.id(12, AssertionTag.self), author: .user,
            createdAt: LedgerFixtures.date, reason: try LedgerText("r"), claim: try LedgerText("c"), confirmation: record)
        let encoded = try LedgerFixtures.encoder.encode(withDecision)
        XCTAssertEqual(try decoder.decode(UserAssertion.self, from: encoded), withDecision)
        XCTAssertEqual(try LedgerFixtures.encoder.encode(try decoder.decode(UserAssertion.self, from: encoded)), encoded)
    }

    // MARK: 8. Admission rules

    func testOperationArchiveAndContractAdmissionRejectNewInOld() throws {
        XCTAssertThrowsError(try LedgerOperationRegistry.builtInV3.requireSupported(.confirmFoodV3))
        XCTAssertNoThrow(try LedgerOperationRegistry.builtInV4.requireSupported(.confirmFoodV3))
        let decided = try decidedAssertionMutation()
        for type in [LedgerOperationType.confirmFood, .confirmFoodV2, .createProduct, .compositeV2] {
            XCTAssertThrowsError(try LedgerOperationRegistry.builtInV4.requireSupported(type, mutation: decided), type.rawValue) {
                XCTAssertEqual($0 as? FoodLedgerStoreError, .unsupportedOperation)
            }
        }
        XCTAssertNoThrow(try LedgerOperationRegistry.builtInV4.requireSupported(.confirmFoodV3, mutation: decided))
        XCTAssertTrue(LedgerOperationType.declaredQuantityTypes.contains(.confirmFoodV3))
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: decided), 4)
        XCTAssertThrowsError(try CanonicalFoodProjection(records: decided, foodContractVersion: 3)) {
            XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(3))
        }
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let ledger = try LedgerFixtures.service(harness.committer)
            XCTAssertThrowsError(try ledger.commit(decided, type: .confirmFood, operationID: LedgerFixtures.operationID(901)), harness.name)
            XCTAssertEqual(try harness.reader.counts().operations, 0, harness.name)
            // A v5 binary always exports contract 4, even without any decision record.
            _ = try ledger.commit(LedgerFixtures.baseMutation(), type: .createProduct, operationID: LedgerFixtures.operationID(902))
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let bundle = try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("v5"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.manifest.foodContractVersion, 4, harness.name)
            XCTAssertEqual(verified.manifest.migrationIdentifiers.map(\.value).last, "food-ledger-v4", harness.name)
            XCTAssertFalse((1...3).contains(verified.manifest.foodContractVersion),
                "Contract-3 admission (1...3) used by older binaries rejects every v5 archive")
        }
    }

    // MARK: 9. Retry recovery for confirm_food_v3

    func testIdempotentRetryRecoversDecidedConfirmation() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let ledger = try LedgerFixtures.service(harness.committer)
            var state = FoodConfirmationState(input: try input(evidence: 20, expected: rawIdentity()))
            FoodConfirmationReducer.reduce(state: &state, action: .decideDifference(.preparation, .notSure))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let key = try LedgerText("food-list:v5-line")
            let saved = try service(ledger, harness).save(state, operationID: LedgerFixtures.operationID(910), idempotencyKey: key)
            let committed = try XCTUnwrap(harness.committer.operation(id: LedgerFixtures.operationID(910)), harness.name)
            XCTAssertEqual(committed.operationType, LedgerOperationType.confirmFoodV3, harness.name)
            let retried = try service(ledger, harness).save(state, operationID: LedgerFixtures.operationID(910), idempotencyKey: key)
            XCTAssertEqual(retried.logItem.logItemID, saved.logItem.logItemID, harness.name)
            XCTAssertEqual(retried.assertions.first?.confirmation, saved.assertions.first?.confirmation, harness.name)
            XCTAssertEqual(try harness.reader.counts().operations, 1, harness.name)
        }
    }

    // MARK: 10. Estimate projection on both stores and after archive round trip

    func testEstimateStatusSurvivesBothStoresAndArchiveRoundTrip() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let ledger = try LedgerFixtures.service(harness.committer)
            let ids = SharedIDs()
            var cases: [(String, LogItemID, Bool)] = []
            for (name, evidence, choice) in [("matches", 30, FoodLogDecisionChoice.matchesSource), ("differs", 31, .differs("raw")), ("not sure", 32, .notSure)] {
                var state = FoodConfirmationState(input: try input(evidence: evidence, expected: rawIdentity()))
                FoodConfirmationReducer.reduce(state: &state, action: .decideDifference(.preparation, choice))
                FoodConfirmationReducer.reduce(state: &state, action: .accept)
                let saved = try service(ledger, harness, ids: ids).save(state, operationID: LedgerFixtures.operationID(920 + evidence))
                cases.append((name, saved.logItem.logItemID, choice.isEstimate))
            }
            let search = try CoFIDGenericFoodSearch(ids: ids)
            guard case let .confirmation(route) = try search.search(GenericFoodSearchRequest(text: try LedgerText("rice"),
                capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"))) else { return XCTFail("rice") }
            var generic = FoodConfirmationState(input: route.confirmation)
            FoodConfirmationReducer.reduce(state: &generic, action: .setQuantity(100, .grams))
            generic.answerPendingDifferences()
            FoodConfirmationReducer.reduce(state: &generic, action: .accept)
            let genericSaved = try service(ledger, harness, ids: ids).save(generic, operationID: LedgerFixtures.operationID(960))
            cases.append(("generic", genericSaved.logItem.logItemID, true))

            let confirmations = service(ledger, harness, ids: ids)
            for (name, id, expected) in cases {
                let stored = try XCTUnwrap(harness.reader.foodConfirmation(logItemID: id), name)
                XCTAssertEqual(try confirmations.isEstimate(stored), expected, "\(harness.name) \(name)")
            }
            // A legacy free-text closest match is not relabelled.
            let matched = try XCTUnwrap(harness.reader.foodConfirmation(logItemID: cases[0].1))
            let legacy = StoredFoodConfirmation(evidence: matched.evidence, sourceReleases: matched.sourceReleases,
                product: matched.product, productVersion: matched.productVersion, resolution: matched.resolution,
                resolutionVersion: matched.resolutionVersion, logItem: matched.logItem, logItemVersion: matched.logItemVersion,
                quantityConversion: nil, plate: nil, plateWeightVersion: nil, candidateDecision: matched.candidateDecision,
                assertions: [UserAssertion(assertionID: try LedgerFixtures.id(77, AssertionTag.self), author: .user,
                    createdAt: LedgerFixtures.date, reason: try LedgerText("Closest available"),
                    claim: try LedgerText("Accepted explained closest match; differences: preparation"))])
            XCTAssertFalse(try confirmations.isEstimate(legacy), harness.name)

            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let bundle = try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("estimate"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            XCTAssertEqual(try FoodArchiveVerifier().verify(bundle).manifest.foodContractVersion, 4)
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                let restoredService = service(try LedgerFixtures.service(destination.committer), destination)
                for (name, id, expected) in cases {
                    let stored = try XCTUnwrap(destination.reader.foodConfirmation(logItemID: id), name)
                    XCTAssertEqual(try restoredService.isEstimate(stored), expected, "\(harness.name)->\(destination.name) \(name)")
                }
            }
        }
    }

    // MARK: 11. Library alias rule (D6)

    func testEstimateSavesCreateNoExactLibraryAliases() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let ledger = try LedgerFixtures.service(harness.committer)
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let ids = SharedIDs()
            var estimate = FoodConfirmationState(input: try input(evidence: 40, expected: rawIdentity(), aliases: ["fixture alias"]))
            FoodConfirmationReducer.reduce(state: &estimate, action: .decideDifference(.preparation, .notSure))
            FoodConfirmationReducer.reduce(state: &estimate, action: .accept)
            _ = try service(ledger, harness, ids: ids).save(estimate, operationID: LedgerFixtures.operationID(940))
            XCTAssertEqual(try archive.archiveState().records.libraryEntries.count, 0, harness.name)
            var exact = FoodConfirmationState(input: try input(evidence: 41, expected: rawIdentity(), aliases: ["fixture alias two"]))
            FoodConfirmationReducer.reduce(state: &exact, action: .decideDifference(.preparation, .matchesSource))
            FoodConfirmationReducer.reduce(state: &exact, action: .accept)
            _ = try service(ledger, harness, ids: ids).save(exact, operationID: LedgerFixtures.operationID(941))
            XCTAssertEqual(try archive.archiveState().records.libraryEntries.count, 1, harness.name)
        }
    }

    // MARK: - Helpers

    private func service(_ ledger: FoodLedgerService, _ harness: TestHarness, ids: SharedIDs = SharedIDs()) -> FoodConfirmationService {
        FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock, ids: ids, digester: SHA256Digester())
    }

    private func rawIdentity() throws -> DecisiveIdentity {
        try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
    }

    private func input(evidence number: Int, expected: DecisiveIdentity, aliases: [String] = []) throws -> PopulatedFoodConfirmation {
        let evidenceID: EvidenceID = try LedgerFixtures.id(number, EvidenceTag.self)
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .synthetic, capturedAt: LedgerFixtures.date,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic_fixture"), captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("fixture \(number)")))
        let provenance = NutrientProvenance(sourceKind: .userVerifiedPanel, sourceID: try ExternalIdentifier("physical_package"),
            sourceReleaseID: try ExternalIdentifier("package:fixture-v1"), evidenceID: evidenceID, capturedAt: LedgerFixtures.date)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard key == .protein else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: 10, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: 10, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [provenance])))
        })
        let metadata = aliases.isEmpty ? nil : try CandidateMatchMetadata(methodVersion: LedgerText("fixture-match-v1"),
            score: 1, materialDifferences: [], libraryAliases: aliases.map { try LedgerText($0) })
        let quantity = try PositiveQuantity(value: 100, unit: .grams)
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(sourceReleaseID: try ExternalIdentifier("package:fixture-v1"),
                recordID: try ExternalIdentifier("fixture:row-\(number)"), identity: try LedgerFixtures.identity(),
                edibleQuantity: .known(quantity, conversionVersionID: nil), nutrients: nutrients, evidenceIDs: [evidenceID],
                matchMetadata: metadata),
            name: try LedgerText("Fixture food \(number)"), itemClass: .food)
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [try LedgerFixtures.packageSourceRelease()],
            candidates: [candidate], expectedIdentity: expected, expectedEdibleQuantity: .known(quantity, conversionVersionID: nil))
    }

    private func decidedAssertionMutation() throws -> LedgerMutation {
        var mutation = try LedgerFixtures.baseMutation()
        let record = try FoodLogDecisionRecord(policyVersion: LedgerText("food_confirmation_v5"), decisions: [
            FoodLogFacetDecision(facet: .preparation, sourceState: FoodLogSourceState(facet: .preparation, token: "as_sold"), choice: .notSure)])
        mutation.assertions = [UserAssertion(assertionID: try LedgerFixtures.id(60, AssertionTag.self),
            evidenceID: try LedgerFixtures.id(1, EvidenceTag.self), author: .user, createdAt: LedgerFixtures.date,
            reason: try LedgerText("Logged with inline decisions under food_confirmation_v5"),
            claim: try LedgerText("Logged under food_confirmation_v5; decisions: " + record.claimList), confirmation: record)]
        return mutation
    }
}

private final class SharedIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 5_000
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
