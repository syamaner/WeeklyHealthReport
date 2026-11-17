import Foundation
@testable import FoodLedgerApplication
import FoodLedgerArchive
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Approved estimates on Confirm, at save and on reopen (estimates on catalogue v2 sections 3.2 and
/// 5; phase gate sections 3.3 to 3.6), against the in-memory and GRDB stores. Candidates are built
/// from the shared synthetic estimates v2 golden file.
final class ApprovedEstimateConfirmContractTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/fixtures/personal-food-database-estimates-v2")

    static func file() throws -> PersonalFoodDatabaseFile {
        try PersonalFoodDatabaseCodec.decode(try Data(contentsOf: fixtures.appendingPathComponent("golden.json"))).get()
    }

    static func release(_ file: PersonalFoodDatabaseFile) throws -> SourceRelease {
        try PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: SHA256Digest(String(repeating: "e", count: 64)),
                                                      generated: file.generated, schema: file.schema)
    }

    /// A stub lookup: each record's preparation; anything else is missing.
    struct Lookup: GenericRecordNutrientLookup {
        var preparations: [String: PreparationKind] = ["cofid:fish": .unknown, "cofid:cheese": .unknown, "cofid:other-cheese": .unknown,
                                                       "cofid:greens": .raw, "cofid:cooked-rice": .cooked]
        var pin = String(repeating: "a", count: 64)

        func record(source: PersonalFoodDatabaseGenericSource, corpusSHA256: String, recordID: String)
            -> Result<GenericRecordFacts, GenericRecordLookupFailure> {
            guard source == .cofid, corpusSHA256 == pin else { return .failure(.corpusMismatch) }
            guard let kind = preparations[recordID],
                  let identity = try? DecisiveIdentity(preparation: PreparationState(kind: kind), bone: .unknown, skin: .unknown,
                      drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams),
                  let nutrients = try? NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: .unknown(.notDeclared)) }),
                  let quantity = try? PositiveQuantity(value: 100, unit: .grams) else { return .failure(.recordMissing) }
            return .success(GenericRecordFacts(nutrients: nutrients, identity: identity,
                                               edibleQuantity: .known(quantity, conversionVersionID: nil)))
        }
    }

    /// A fixed UTC calendar, so a saved log's reporting day never depends on the machine's zone.
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func service(_ harness: TestHarness, lookup: (any GenericRecordNutrientLookup)? = Lookup(),
                        ids: any LedgerIDGenerating = RandomLedgerIDGenerator()) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: harness.reader,
            clock: LedgerFixtures.clock, ids: ids, digester: LedgerFixtures.digester, calendar: utc, estimateRecords: lookup)
    }

    /// The route's own confirmation for some entries: one search evidence item and one capture
    /// manifest per candidate with estimates, exactly as the database route builds it.
    static func input(_ titles: [String], ids: any LedgerIDGenerating = RandomLedgerIDGenerator()) throws -> PopulatedFoodConfirmation {
        let file = try file(), release = try release(file)
        let search = try CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch,
            capturedAt: LedgerFixtures.clock.now(), locale: LedgerText("en_GB"), captureMethod: LedgerText("typed_generic_food_search"),
            captureMethodVersion: LedgerText(PersonalFoodDatabaseCandidateBuilder.methodVersion), originalPayload: .text(LedgerText("synthetic")))
        let builder = ApprovedEstimateManifestBuilder(ids: ids, digester: LedgerFixtures.digester)
        var evidence = [search], candidates: [PopulatedFoodCandidate] = [], releases: [SourceRelease] = []
        for title in titles {
            let entry = try XCTUnwrap(file.entries.first { $0.title == title }, title)
            let capture = try builder.capture(entry: entry, file: file, databaseRelease: release,
                                              capturedAt: search.capturedAt, locale: search.locale)
            if let capture { evidence.append(capture.evidence) }
            let built = try XCTUnwrap(PersonalFoodDatabaseCandidateBuilder.build(entry: entry, file: file, databaseRelease: release,
                record: nil, evidenceIDs: [search.evidenceID], score: 1, estimates: capture?.binding), title)
            candidates.append(built.candidate)
            for r in built.releases where !releases.contains(where: { $0.sourceReleaseID == r.sourceReleaseID }) { releases.append(r) }
        }
        return try PopulatedFoodConfirmation(evidence: evidence, sourceReleases: releases, candidates: candidates,
            expectedIdentity: candidates[0].candidate.identity, expectedEdibleQuantity: candidates[0].candidate.edibleQuantity)
    }

    static func identity(_ kind: PreparationKind = .asSold, basis: ResolutionBasis = .per100Grams) throws -> DecisiveIdentity {
        try DecisiveIdentity(preparation: PreparationState(kind: kind), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: basis)
    }

    /// Food details filled in, as "Correct food details" does: identity only, the candidate's
    /// nutrients carried through unchanged.
    static func correct(_ state: inout FoodConfirmationState, _ kind: PreparationKind = .asSold,
                        basis: ResolutionBasis = .per100Grams) throws {
        let selected = state.selectedCandidate
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(FoodCorrection(
            name: selected.name, brand: selected.brand, variant: selected.variant, identity: try identity(kind, basis: basis),
            nutrients: selected.candidate.nutrients, reason: try LedgerText("Filled in food details"))))
    }

    /// A bound, corrected, accepted state with an amount.
    static func state(_ service: FoodConfirmationService, _ titles: [String], _ kind: PreparationKind = .asSold,
                      grams: Double = 150, ids: any LedgerIDGenerating = RandomLedgerIDGenerator()) throws -> FoodConfirmationState {
        var state = FoodConfirmationState(input: try input(titles, ids: ids), prefillSourceQuantity: false)
        service.bindEstimates(&state)
        try correct(&state, kind)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(grams, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    static func value(_ set: NutrientSet, _ key: NutrientKey) -> NutrientValue { set.entries.first { $0.key == key }!.value }

    static func isEstimate(_ value: NutrientValue) -> Bool {
        if case let .augmented(exact) = value { return exact.provenance.allSatisfy { $0.sourceKind == .approvedEstimate } }
        return false
    }

    static let fish = "Synthetic Tinned Fish", rice = "Synthetic Cooked Rice", crisps = "Synthetic Crisps"
    static let bar = "Synthetic Serving Bar", cheese = "Synthetic Soft Cheese", oats = "Synthetic Example Oats"

    // MARK: Kept

    func testAnEstimateSavesAsAugmentedApprovedEstimateAndReopensAsSaved() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try Self.service(harness)
            let state = try Self.state(service, [Self.fish])
            XCTAssertEqual(state.estimateKeys, [.protein, .fatTotal, .sugar], harness.name)
            XCTAssertEqual(state.withheldEstimates, [:], harness.name)
            XCTAssertFalse(state.isGenericEstimate, "an entry whose values are all estimates is not a generic estimate")
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_001))
            let nutrients = saved.resolutionVersion.nutrients
            for key in [NutrientKey.protein, .fatTotal, .sugar] {
                XCTAssertTrue(Self.isEstimate(Self.value(nutrients, key)), "\(harness.name) \(key)")
            }
            guard case let .augmented(sugar) = Self.value(nutrients, .sugar) else { return XCTFail("a quantified zero stays a zero") }
            XCTAssertEqual(sugar.amount, 0)
            let provenance = try XCTUnwrap(Self.value(nutrients, .protein).provenance.first)
            XCTAssertEqual(provenance.sourceID.value, "personal-food-database")
            XCTAssertEqual(provenance.manifestReference?.value, "pfd-estimate-capture-v1#protein")
            XCTAssertTrue(provenance.recordID?.value.hasPrefix("pfe:") == true)
            // The manifest is saved with the log and is the evidence the provenance names.
            let manifest = try XCTUnwrap(saved.evidence.first(where: ApprovedEstimateSource.isManifest))
            XCTAssertEqual(provenance.evidenceID, manifest.evidenceID)
            XCTAssertEqual(provenance.responseHash, manifest.byteHash)
            XCTAssertEqual(saved.evidence.filter(ApprovedEstimateSource.isLeftOut).count, 0)
            XCTAssertNil(saved.evidence.first(where: ApprovedEstimateSource.isLeftOut))

            let reopened = try XCTUnwrap(try service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.effectiveNutrients, nutrients, harness.name)
            XCTAssertEqual(reopened.estimateSeed, ApprovedEstimateSeed(), harness.name)
            XCTAssertEqual(reopened.estimateRecords, [:], "reopening alone reads no record")
            XCTAssertNotNil(reopened.estimateManifest, harness.name)
            XCTAssertFalse(FoodLogPolicy.editChanges(reopened), harness.name)
            XCTAssertEqual(reopened.evidence(of: saved), saved.evidence.map(\.evidenceID), "the returned record is what the store reads back")
        }
    }

    func testTheContractFloorIsTenForEachWayALogHoldsAnEstimate() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let service = try Self.service(harness)
        var state = try Self.state(service, [Self.crisps])
        FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.fiber))
        let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_002))
        func floor(_ records: LedgerMutation) -> Int { CanonicalFoodProjection.minimumContractVersion(for: records) }
        XCTAssertEqual(floor(LedgerMutation(resolutionVersions: [saved.resolutionVersion])), 10, "approved estimate provenance")
        XCTAssertEqual(floor(LedgerMutation(candidateDecisions: [saved.candidateDecision])), 10, "found only in a candidate decision")
        XCTAssertEqual(floor(LedgerMutation(evidence: saved.evidence.filter(ApprovedEstimateSource.isManifest))), 10, "only the manifest")
        XCTAssertEqual(floor(LedgerMutation(evidence: saved.evidence.filter(ApprovedEstimateSource.isLeftOut))), 10, "only leave-out evidence")
        XCTAssertLessThan(floor(LedgerMutation(evidence: saved.evidence.filter { $0.kind == .genericSearch })), 10)
    }

    /// Independent review, 17 November 2026: a log with an approved estimate and a leave-out makes a
    /// contract 10 archive that verifies, restores into either store byte for byte, and reopens with
    /// its estimate, its manifest and "Left out by you". An older binary's ceiling refuses it.
    func testAContractTenArchiveRoundTripsAndReopensWithItsEvidence() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            func generate(_ access: any FoodArchiveLedgerAccess) throws -> FoodArchiveBundle {
                try FoodArchiveGenerator().generate(state: access.archiveState(), ledgerID: LedgerText("approved-estimate"),
                    createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            }
            let service = try Self.service(harness)
            // Without an estimate the archive keeps the floor contract.
            _ = try service.save(try Self.state(service, [Self.oats]), operationID: LedgerFixtures.operationID(11_100))
            XCTAssertEqual(try FoodArchiveVerifier().verify(generate(archive)).manifest.foodContractVersion, 6, harness.name)
            var state = try Self.state(service, [Self.crisps])
            FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.fiber))
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_101))
            let bundle = try generate(archive)
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.manifest.foodContractVersion, 10, harness.name)
            XCTAssertEqual(verified.manifest.migrationIdentifiers.map(\.value).last, "food-ledger-v10", harness.name)
            // What a contract 9 binary would have to accept: refused.
            XCTAssertThrowsError(try CanonicalFoodProjection(records: archive.archiveState().records, foodContractVersion: 9)) {
                XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(9), harness.name)
            }
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                XCTAssertEqual(try generate(live), bundle, "\(harness.name)->\(destination.name)")
                // No database is installed at the destination: the log reads its own saved evidence.
                let reopened = try XCTUnwrap(try Self.service(destination, lookup: nil).reopen(logItemID: saved.logItem.logItemID))
                XCTAssertEqual(reopened.savedEstimateStates, [.fiber: .leftOutByYou], "\(harness.name)->\(destination.name)")
                XCTAssertTrue(Self.isEstimate(Self.value(reopened.effectiveNutrients, .sodium)))
                XCTAssertNotNil(reopened.estimateManifest, "the assumptions travel with the archive")
                XCTAssertTrue(reopened.estimateSeed.evidenceAvailable)
            }
        }
    }

    // MARK: Withheld

    func testAKnownContradictionWithholdsAndACorrectionOfDetailsBringsTheEstimateBack() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try Self.service(harness)
            // The cooked rice's estimate cites a cooked record; the details say raw.
            var state = try Self.state(service, [Self.rice, Self.bar], .raw)
            XCTAssertEqual(state.withheldEstimates, [.protein: .facet(.preparation)], harness.name)
            XCTAssertEqual(Self.value(state.effectiveNutrients, .protein), .unknown(.noCompatibleSource))
            XCTAssertEqual(FoodLogPolicy.requirements(state, now: LedgerFixtures.clock.now(), calendar: .current), [.nothingKnown],
                           "the only value is withheld: Log is blocked where the rule applies")
            XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(11_010))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .unmetRequirements([.nothingKnown]), harness.name)
            }
            // As sold against a cooked record is a contradiction like any other; unknown is not.
            try Self.correct(&state, .asSold)
            XCTAssertEqual(state.withheldEstimates, [.protein: .facet(.preparation)], harness.name)
            try Self.correct(&state, .cooked)
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            XCTAssertEqual(state.withheldEstimates, [:], harness.name)
            XCTAssertTrue(Self.isEstimate(Self.value(state.effectiveNutrients, .protein)), "back with its label")
            XCTAssertNoThrow(try service.save(state, operationID: LedgerFixtures.operationID(11_011)), harness.name)
        }
    }

    func testAWithheldValueIsSavedUnknownAndReadsAsLeftOutWhenLogged() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            // A record that cannot be read withholds, with its own reason; the page estimate stays.
            var lookup = Lookup()
            lookup.preparations["cofid:cheese"] = nil
            let service = try Self.service(harness, lookup: lookup)
            let state = try Self.state(service, [Self.cheese])
            XCTAssertEqual(state.withheldEstimates, [.calcium: .unreadableRecord], harness.name)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_020))
            XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .calcium), .unknown(.noCompatibleSource))
            XCTAssertTrue(Self.isEstimate(Self.value(saved.resolutionVersion.nutrients, .protein)))
            XCTAssertNotNil(saved.evidence.first(where: ApprovedEstimateSource.isManifest), "the manifest records what was offered")
            XCTAssertNil(saved.evidence.first(where: ApprovedEstimateSource.isLeftOut), "a withheld key writes no leave-out evidence")
            let reopened = try XCTUnwrap(try service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(reopened.savedEstimateStates, [.calcium: .leftOutWhenLogged], harness.name)
            XCTAssertEqual(reopened.effectiveNutrients, saved.resolutionVersion.nutrients)
            // Reopening reads no record and shows saved values also after the corpus pin has moved.
            var moved = Lookup()
            moved.pin = String(repeating: "9", count: 64)
            let later = try XCTUnwrap(try Self.service(harness, lookup: moved).reopen(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(later.effectiveNutrients, saved.resolutionVersion.nutrients, harness.name)
        }
    }

    func testABasisChangeWithholdsEveryEstimateAndAnUnboundStateWithholdsCompositionEstimates() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let service = try Self.service(harness)
        var state = try Self.state(service, [Self.bar])
        XCTAssertEqual(state.withheldEstimates, [:], "a page estimate needs no record")
        try Self.correct(&state, .asSold, basis: .per100Millilitres)
        XCTAssertEqual(state.withheldEstimates, [.fiber: .basis], "a value is never reinterpreted")
        // No lookup wired: closed by default.
        let bare = try Self.service(harness, lookup: nil)
        let unbound = try Self.state(bare, [Self.fish])
        XCTAssertEqual(Set(unbound.withheldEstimates.values), [.unreadableRecord])
        // A state nobody bound has no verified manifest at all.
        var never = FoodConfirmationState(input: try Self.input([Self.fish]), prefillSourceQuantity: false)
        try Self.correct(&never)
        XCTAssertEqual(Set(never.withheldEstimates.values), [.evidenceUnavailable])
    }

    // MARK: Left out

    func testALeaveOutOnANewLogIsSavedWithItsEvidenceAndReadsAsLeftOutByYou() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try Self.service(harness)
            var state = try Self.state(service, [Self.crisps])
            let offered = state.selectedCandidate.candidate
            FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.fiber))
            FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.fiber))  // repeating changes nothing
            FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.protein))  // not an estimate here
            XCTAssertEqual(state.leftOutEstimates, [.fiber], harness.name)
            XCTAssertEqual(state.decision, .accepted, "a leave-out is not a correction and selects nothing")
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_030))
            XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .fiber), .unknown(.noCompatibleSource))
            // Untouched nutrients keep their provenance byte for byte.
            XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .sodium), Self.value(offered.nutrients, .sodium))
            // The decision's embedded candidate is the bound one plus the leave-out item, nothing else.
            let item = try XCTUnwrap(saved.evidence.first(where: ApprovedEstimateSource.isLeftOut))
            XCTAssertEqual(saved.candidateDecision.candidate.evidenceIDs, offered.evidenceIDs + [item.evidenceID])
            XCTAssertEqual(saved.candidateDecision.candidate.nutrients, offered.nutrients)
            guard case let .text(payload) = item.originalPayload else { return XCTFail("inline text") }
            let decoded = try XCTUnwrap(ApprovedEstimateLeftOutEvidence.decode(Data(payload.value.utf8)))
            XCTAssertEqual(decoded.leftOut, ["fiber"])
            XCTAssertEqual(decoded.resolutionVersionID, saved.resolutionVersion.resolutionVersionID.rawValue)
            XCTAssertFalse(payload.value.contains("value") || payload.value.contains("unit"), "keys and identifiers only, never a value")
            let reopened = try XCTUnwrap(try service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.savedEstimateStates, [.fiber: .leftOutByYou], harness.name)
            XCTAssertEqual(reopened.leftOutEstimates, [.fiber])
            XCTAssertFalse(FoodLogPolicy.editChanges(reopened))
        }
    }

    func testUndoAndLeaveOutAloneOnAReopenedLogWriteANewVersionAndKeepIdentityRecordAndOutcome() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try Self.service(harness)
            var state = try Self.state(service, [Self.crisps], grams: 150)
            FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.fiber))
            let first = try service.save(state, operationID: LedgerFixtures.operationID(11_040))

            // Undo on the reopened log: the check runs for that nutrient, then a new version is written.
            var undo = try XCTUnwrap(try service.reopen(logItemID: first.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &undo, action: .restoreEstimate(.fiber))
            service.bindEstimates(&undo)
            XCTAssertTrue(FoodLogPolicy.editChanges(undo), "a leave-out or undo alone compares as edited")
            XCTAssertTrue(Self.isEstimate(Self.value(undo.effectiveNutrients, .fiber)), harness.name)
            let second = try service.save(undo, operationID: LedgerFixtures.operationID(11_041))
            XCTAssertNotEqual(second.resolutionVersion.resolutionVersionID, first.resolutionVersion.resolutionVersionID)
            XCTAssertNotEqual(second.productVersion.productVersionID, first.productVersion.productVersionID)
            XCTAssertTrue(Self.isEstimate(Self.value(second.resolutionVersion.nutrients, .fiber)))
            XCTAssertEqual(second.productVersion.identity, first.productVersion.identity)
            XCTAssertEqual(second.candidateDecision.outcome, first.candidateDecision.outcome)
            XCTAssertEqual(second.candidateDecision.expectedEdibleQuantity, first.candidateDecision.expectedEdibleQuantity,
                           "the saved decision's expectations, not the logged 150 g")
            XCTAssertEqual(second.logItemVersion.correctionReason?.value, "Estimated values left out or restored")
            XCTAssertEqual(second.assertions.last?.reason.value, "Changed left-out estimated values under pfd-estimate-left-out-v1")
            XCTAssertEqual(second.assertions.last?.claim.value, "Estimated values left out: none")
            // After undoing every leave-out the stale item is ignored: only the effective version's is read.
            let after = try XCTUnwrap(try service.reopen(logItemID: first.logItem.logItemID))
            XCTAssertEqual(after.estimateSeed.leftOut, [], harness.name)
            XCTAssertEqual(after.savedEstimateStates, [:])

            // A leave-out alone on the reopened log, and a third change: the newest version's governs.
            var again = after
            FoodConfirmationReducer.reduce(state: &again, action: .leaveOutEstimate(.sodium))
            let third = try service.save(again, operationID: LedgerFixtures.operationID(11_042))
            XCTAssertEqual(Self.value(third.resolutionVersion.nutrients, .sodium), .unknown(.noCompatibleSource))
            XCTAssertTrue(Self.isEstimate(Self.value(third.resolutionVersion.nutrients, .fiber)))
            XCTAssertEqual(third.assertions.last?.claim.value, "Estimated values left out: sodium")
            XCTAssertEqual(third.candidateDecision.outcome, first.candidateDecision.outcome)
            let last = try XCTUnwrap(try service.reopen(logItemID: first.logItem.logItemID))
            XCTAssertEqual(last.savedEstimateStates, [.sodium: .leftOutByYou], harness.name)
            XCTAssertEqual(last.evidence(of: third).count, third.evidence.count, "every listed evidence item is stored")
        }
    }

    func testTheLeaveOutTextsOfANewLogArePinned() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let service = try Self.service(harness)
        var state = try Self.state(service, [Self.crisps])
        FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.sodium))
        FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.fiber))
        FoodConfirmationReducer.reduce(state: &state, action: .restoreEstimate(.sodium))  // undo before Log
        let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_050))
        // A correction is present, so its own reason and claim stand.
        XCTAssertEqual(saved.assertions.last?.reason.value, "Filled in food details")
        XCTAssertTrue(Self.isEstimate(Self.value(saved.resolutionVersion.nutrients, .sodium)), "undo returns the captured estimate")
        XCTAssertEqual(ApprovedEstimateLeaveOutText.claim([.sodium, .fiber]), "Estimated values left out: fiber, sodium")
        XCTAssertEqual(ApprovedEstimateLeaveOutText.claimSuffix([.fiber]), "; estimated values left out: fiber")
        XCTAssertEqual(ApprovedEstimateLeaveOutText.reason, "Changed left-out estimated values under pfd-estimate-left-out-v1")
    }

    func testLeavingOutEveryValueBlocksLogWithItsReason() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let service = try Self.service(harness)
        var state = try Self.state(service, [Self.crisps])
        XCTAssertFalse(state.estimatesLeaveNothingKnown)
        for key in [NutrientKey.fiber, .sodium] { FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(key)) }
        XCTAssertEqual(FoodLogPolicy.requirements(state, now: LedgerFixtures.clock.now(), calendar: .current), [.nothingKnown])
        XCTAssertEqual(QuickAddPolicy.placement(.nothingKnown), .confirm)
        XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(11_060)))
        // A state without an estimate never gets the requirement.
        let plain = try Self.state(service, [Self.oats])
        XCTAssertFalse(plain.estimatesLeaveNothingKnown)
        XCTAssertEqual(plain.effectiveNutrients, plain.selectedCandidate.candidate.nutrients)
    }

    func testAKeyLeftOutThenWithheldThenReleasedStaysLeftOutAndWithholdingWins() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let service = try Self.service(harness)
        var state = try Self.state(service, [Self.rice, Self.bar], .cooked)
        FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.protein))
        try Self.correct(&state, .raw)  // now withheld as well
        XCTAssertEqual(state.withheldEstimates, [.protein: .facet(.preparation)])
        XCTAssertEqual(state.savedLeaveOutSet, [], "the saved leave-out evidence never lists a withheld key")
        try Self.correct(&state, .cooked)  // released
        XCTAssertEqual(state.leftOutEstimates, [.protein], "the owner's choice stands until the owner undoes it")
        XCTAssertEqual(Self.value(state.effectiveNutrients, .protein), .unknown(.noCompatibleSource))
        // A withheld value cannot be left out: only a value shown as an estimate can.
        var withheld = try Self.state(service, [Self.rice, Self.bar], .raw)
        FoodConfirmationReducer.reduce(state: &withheld, action: .leaveOutEstimate(.protein))
        XCTAssertEqual(withheld.leftOutEstimates, [])
    }

    // MARK: Evidence, quick add and re-log

    func testOnlyTheSelectedCandidatesManifestIsSavedAndACandidateWithoutEstimatesWritesNone() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try Self.service(harness)
            let state = try Self.state(service, [Self.fish, Self.cheese, Self.oats])
            XCTAssertEqual(state.input.evidence.filter(ApprovedEstimateSource.isManifest).count, 2, "one per candidate with estimates")
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_070))
            let manifests = saved.evidence.filter(ApprovedEstimateSource.isManifest)
            XCTAssertEqual(manifests.map(\.evidenceID), state.selectedCandidate.candidate.evidenceIDs.suffix(1), harness.name)
            XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            // The other entry's manifest was never stored.
            let other = try XCTUnwrap(state.input.evidence.filter(ApprovedEstimateSource.isManifest).first { $0.evidenceID != manifests[0].evidenceID })
            XCTAssertNil(try harness.reader.evidence(id: other.evidenceID), harness.name)
            // Logging the entry without estimates from the same search: the returned record lists no
            // other candidate's manifest either, as the store reads it back.
            var second = try Self.state(service, [Self.oats, Self.fish])
            FoodConfirmationReducer.reduce(state: &second, action: .accept)
            let logged = try service.save(second, operationID: LedgerFixtures.operationID(11_072))
            XCTAssertNil(logged.evidence.first(where: ApprovedEstimateSource.isManifest), harness.name)
            // A candidate with no estimate lists no manifest and keeps its contract.
            var plain = FoodConfirmationState(input: try Self.input([Self.oats]), prefillSourceQuantity: false)
            try Self.correct(&plain)
            FoodConfirmationReducer.reduce(state: &plain, action: .setQuantity(40, .grams))
            FoodConfirmationReducer.reduce(state: &plain, action: .accept)
            let oats = try service.save(plain, operationID: LedgerFixtures.operationID(11_071))
            XCTAssertNil(oats.evidence.first(where: ApprovedEstimateSource.isManifest))
            XCTAssertLessThan(CanonicalFoodProjection.minimumContractVersion(for: LedgerMutation(
                evidence: oats.evidence, resolutionVersions: [oats.resolutionVersion], candidateDecisions: [oats.candidateDecision])), 10)
        }
    }

    func testQuickAddAndRelogAlwaysGoThroughConfirmAndEarlierLeaveOutsAreNotCarried() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try Self.service(harness)
            var state = try Self.state(service, [Self.crisps])
            for key in [NutrientKey.fiber] { FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(key)) }
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_080))
            // The one-step save of a state holding a manifest is refused.
            XCTAssertThrowsError(try service.saveQuickAdd(state, operationID: LedgerFixtures.operationID(11_081))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .approvedEstimateNeedsConfirm, harness.name)
            }
            // Re-log: the manifest stays, the leave-out evidence and its ID are dropped.
            let relog = try service.relogInput(saved)
            XCTAssertNotNil(relog.evidence.first(where: ApprovedEstimateSource.isManifest))
            XCTAssertNil(relog.evidence.first(where: ApprovedEstimateSource.isLeftOut), harness.name)
            XCTAssertEqual(relog.candidates[0].candidate.evidenceIDs, state.selectedCandidate.candidate.evidenceIDs)
            var again = try XCTUnwrap(try service.relogState(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(again.leftOutEstimates, [], "values left out before are not carried over")
            service.bindEstimates(&again)
            XCTAssertTrue(Self.isEstimate(Self.value(again.effectiveNutrients, .fiber)), harness.name)
            // Quick add is detected from the restored candidate, so an entry whose estimates were all
            // left out or withheld is caught too.
            let eligibility = QuickAddPolicy.eligibility(pinned: saved, pinnedIsEstimate: false, rebuilt: again,
                                                         now: LedgerFixtures.clock.now(), calendar: .current)
            XCTAssertEqual(eligibility, .confirm(.approvedEstimate), harness.name)
            let plain = try Self.state(service, [Self.oats])
            XCTAssertNoThrow(try service.saveQuickAdd(plain, operationID: LedgerFixtures.operationID(11_082)), "other entries are unaffected")
        }
    }

    // MARK: Re-resolution (its own service) and carried details

    struct FreshProvider: FoodReresolutionProviding {
        let target: FoodReresolutionTarget
        let input: PopulatedFoodConfirmation
        func targets() throws -> [FoodReresolutionTarget] { [target] }
        func candidates(for record: StoredFoodConfirmation, target: FoodReresolutionTarget, at: Date) throws -> GenericFoodSearchOutcome {
            .confirmation(GenericFoodConfirmationRoute(confirmation: input, matches: input.candidates.map {
                GenericFoodMatch(candidate: $0, isExactName: true,
                                 personalDatabase: PersonalFoodDatabaseMatchContext(step: .titleOrAlias, isGenericReference: false))
            }))
        }
    }

    static func reresolution(_ harness: TestHarness, titles: [String], lookup: (any GenericRecordNutrientLookup)?)
        throws -> (FoodReresolutionService, FoodReresolutionTarget) {
        let fresh = try input(titles)
        let target = FoodReresolutionTarget(sourceRelease: try release(try file()),
                                            methodVersion: try LedgerText(PersonalFoodDatabaseCandidateBuilder.methodVersion))
        let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
        return (FoodReresolutionService(ledger: try LedgerFixtures.service(harness.committer),
            reader: FoodReresolutionHistory(archive: archive, confirmations: harness.reader),
            provider: FreshProvider(target: target, input: fresh), clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(),
            estimateRecords: lookup, digester: LedgerFixtures.digester), target)
    }

    func testReresolutionChecksFreshEstimatesAgainstTheSavedDetailsAndSavesTheFreshManifest() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            // Saved while the cheese record could not be read: calcium withheld, protein kept.
            var missing = Lookup()
            missing.preparations["cofid:cheese"] = nil
            let service = try Self.service(harness, lookup: missing)
            let saved = try service.save(try Self.state(service, [Self.cheese, Self.bar]), operationID: LedgerFixtures.operationID(11_090))
            XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .calcium), .unknown(.noCompatibleSource))
            let leftOut = saved

            // Re-resolved with the record readable again: nothing contradicts, so both estimates are stored.
            let (reresolve, target) = try Self.reresolution(harness, titles: [Self.cheese, Self.bar], lookup: Lookup())
            let proposals = try reresolve.proposals(logItemID: saved.logItem.logItemID, target: target)
            let proposal = try XCTUnwrap(proposals.first { $0.candidate.name.value == Self.cheese }, harness.name)
            XCTAssertEqual(proposal.withheldEstimates, [:], harness.name)
            XCTAssertTrue(Self.isEstimate(Self.value(proposal.nutrients, .protein)))
            let prepared = try reresolve.prepareAcceptance(proposal, reason: try LedgerText("Rebuilt food database"), confirmsIdentityGaps: true)
            try reresolve.accept(prepared)
            let after = try XCTUnwrap(try harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID))
            XCTAssertTrue(Self.isEstimate(Self.value(after.resolutionVersion.nutrients, .calcium)), harness.name)
            // The fresh manifest is saved with the new version; the other candidate's is not.
            let manifests = after.evidence.filter(ApprovedEstimateSource.isManifest)
            XCTAssertEqual(manifests.map(\.evidenceID), proposal.candidate.candidate.evidenceIDs.suffix(1), harness.name)
            let other = try XCTUnwrap(proposal.input.evidence.filter(ApprovedEstimateSource.isManifest).first { $0.evidenceID != manifests[0].evidenceID })
            XCTAssertNil(try harness.reader.evidence(id: other.evidenceID), harness.name)
            // The same release and entry give the same manifest bytes and hash as the first capture.
            let first = try XCTUnwrap(saved.evidence.first(where: ApprovedEstimateSource.isManifest))
            XCTAssertEqual(manifests[0].byteHash, first.byteHash)
            XCTAssertNotEqual(manifests[0].evidenceID, first.evidenceID)
            XCTAssertNotEqual(after.resolutionVersion.resolutionVersionID, leftOut.resolutionVersion.resolutionVersionID)

            // Values left out before are not carried over: the crisps' fibre was left out by the
            // owner; re-resolution stores the fresh candidate's estimate, and the saved version with
            // its left-out value stays as it is in the append-only record.
            var crisps = try Self.state(service, [Self.crisps])
            FoodConfirmationReducer.reduce(state: &crisps, action: .leaveOutEstimate(.fiber))
            let before = try service.save(crisps, operationID: LedgerFixtures.operationID(11_092))
            let (again, crispsTarget) = try Self.reresolution(harness, titles: [Self.crisps], lookup: Lookup())
            let fresh = try XCTUnwrap(try again.proposals(logItemID: before.logItem.logItemID, target: crispsTarget).first, harness.name)
            XCTAssertTrue(Self.isEstimate(Self.value(fresh.nutrients, .fiber)), harness.name)
            try again.accept(try again.prepareAcceptance(fresh, reason: try LedgerText("Rebuilt food database"), confirmsIdentityGaps: true))
            let reopened = try XCTUnwrap(try Self.service(harness).reopen(logItemID: before.logItem.logItemID))
            XCTAssertEqual(reopened.savedEstimateStates, [:], "no leave-out belongs to the effective version")
            XCTAssertTrue(Self.isEstimate(Self.value(reopened.effectiveNutrients, .fiber)), harness.name)
        }
    }

    func testAReresolutionThatWouldLeaveNothingKnownIsBlockedAndAContradictionIsStoredUnknown() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try Self.service(harness)
            // The fish holds estimates only. Saved with one left out, so a re-resolution differs.
            var state = try Self.state(service, [Self.fish])
            FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.sugar))
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_095))
            // No lookup: every composition estimate of the fresh candidate is withheld.
            let (closed, target) = try Self.reresolution(harness, titles: [Self.fish], lookup: nil)
            let withheld = try XCTUnwrap(try closed.proposals(logItemID: saved.logItem.logItemID, target: target).first)
            XCTAssertEqual(Set(withheld.withheldEstimates.keys), [.protein, .fatTotal, .sugar], harness.name)
            XCTAssertEqual(Self.value(withheld.nutrients, .protein), .unknown(.noCompatibleSource), "stored as unknown, never substituted")
            XCTAssertThrowsError(try closed.prepareAcceptance(withheld, reason: try LedgerText("Rebuilt"), confirmsIdentityGaps: true)) {
                XCTAssertEqual($0 as? FoodReresolutionError, .nothingKnown, harness.name)
            }
            // A record whose preparation contradicts the saved details withholds its estimate.
            var cooked = Lookup()
            cooked.preparations["cofid:fish"] = .cooked
            let (checked, _) = try Self.reresolution(harness, titles: [Self.fish], lookup: cooked)
            let proposal = try XCTUnwrap(try checked.proposals(logItemID: saved.logItem.logItemID, target: target).first)
            XCTAssertEqual(Set(proposal.withheldEstimates.values), [.facet(.preparation)], harness.name)
        }
    }

    func testDetailsAreStillCarriedToARelogWhenAnEstimateWasWithheldOrLeftOut() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let service = try Self.service(harness)
        var state = try Self.state(service, [Self.crisps])
        FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.fiber))
        let saved = try service.save(state, operationID: LedgerFixtures.operationID(11_097))
        XCTAssertTrue(ApprovedEstimateSource.matchesExceptHiddenEstimates(saved.resolutionVersion.nutrients,
                                                                          candidate: saved.candidateDecision.candidate))
        let relog = try XCTUnwrap(try service.relogState(logItemID: saved.logItem.logItemID))
        XCTAssertEqual(relog.correction?.identity, saved.productVersion.identity, "the saved food details are carried")
        XCTAssertEqual(relog.correctionOrigin, .carried)
        // A saved value that is neither the candidate's nor a hidden estimate is not this shape.
        let plain = try service.save(try Self.state(service, [Self.oats]), operationID: LedgerFixtures.operationID(11_098))
        XCTAssertFalse(ApprovedEstimateSource.matchesExceptHiddenEstimates(plain.resolutionVersion.nutrients,
                                                                           candidate: plain.candidateDecision.candidate))
    }

    /// Qodo (local review, 17 November 2026): the manifest must describe the candidate's own values. A
    /// candidate whose estimated amount differs from the captured one, with every identifier and
    /// hash still valid, has no verified manifest, so it cannot be saved as an approved estimate.
    func testACandidateWhoseEstimatedAmountDiffersFromItsManifestIsRefused() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let input = try Self.input([Self.crisps])
        let offered = input.candidates[0]
        let changed = try NutrientSet(entries: offered.candidate.nutrients.entries.map { entry in
            guard entry.key == .fiber, case let .augmented(exact) = entry.value else { return entry }
            return try NutrientEntry(key: entry.key, value: .augmented(ExactNutrientValue(
                amount: exact.amount * 3, unit: exact.unit, sourceValue: exact.sourceValue, provenance: exact.provenance)))
        })
        let tampered = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
            sourceReleaseID: offered.candidate.sourceReleaseID, recordID: offered.candidate.recordID,
            identity: offered.candidate.identity, edibleQuantity: offered.candidate.edibleQuantity, nutrients: changed,
            evidenceIDs: offered.candidate.evidenceIDs, matchMetadata: offered.candidate.matchMetadata),
            name: offered.name, brand: offered.brand, itemClass: offered.itemClass)
        XCTAssertNotNil(ApprovedEstimateSource.verifiedManifest(offered.candidate, evidence: input.evidence, digester: LedgerFixtures.digester))
        XCTAssertNil(ApprovedEstimateSource.verifiedManifest(tampered.candidate, evidence: input.evidence, digester: LedgerFixtures.digester))
        let service = try Self.service(harness)
        var state = FoodConfirmationState(input: try PopulatedFoodConfirmation(evidence: input.evidence,
            sourceReleases: input.sourceReleases, candidates: [tampered], expectedIdentity: tampered.candidate.identity,
            expectedEdibleQuantity: tampered.candidate.edibleQuantity), prefillSourceQuantity: false)
        service.bindEstimates(&state)
        XCTAssertEqual(Set(state.withheldEstimates.values), [.evidenceUnavailable], "nothing is shown as an estimate")
        try Self.correct(&state)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(50, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(11_099))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidApprovedEstimate)
        }
    }

    func testAlteredEvidenceIsNotAvailableAndNeverChangesAStoredValue() throws {
        let digester = LedgerFixtures.digester
        let input = try Self.input([Self.crisps])
        let candidate = input.candidates[0].candidate
        let manifest = try XCTUnwrap(ApprovedEstimateSource.verifiedManifest(candidate, evidence: input.evidence, digester: digester))
        func altered(_ evidence: CaptureEvidence, _ edit: (String) -> String) throws -> CaptureEvidence {
            guard case let .text(payload) = evidence.originalPayload else { throw XCTSkip("inline text") }
            return try CaptureEvidence(evidenceID: evidence.evidenceID, kind: evidence.kind, capturedAt: evidence.capturedAt,
                locale: evidence.locale, captureMethod: evidence.captureMethod, captureMethodVersion: evidence.captureMethodVersion,
                originalPayload: .text(LedgerText(edit(payload.value))), byteHash: evidence.byteHash)
        }
        let tampered = try altered(manifest.evidence) { $0.replacingOccurrences(of: "\"value\":3", with: "\"value\":9") }
        XCTAssertNil(ApprovedEstimateSource.verifiedManifest(candidate, evidence: [tampered], digester: digester))
        XCTAssertNil(ApprovedEstimateSource.verifiedManifest(candidate, evidence: [], digester: digester), "a missing manifest")
        // Leave-out evidence: verified against its hash and its manifest; another version's is ignored.
        let version = try ResolutionVersionID("00000000-0000-0000-0000-00000000aaaa")
        let other = try ResolutionVersionID("00000000-0000-0000-0000-00000000bbbb")
        func item(_ id: ResolutionVersionID, _ keys: Set<NutrientKey>, manifestHash: String? = nil) throws -> CaptureEvidence {
            let payload = try FoundationCanonicalJSONEncoder().encode(try XCTUnwrap(ApprovedEstimateLeftOutEvidence(
                resolutionVersionID: id.rawValue, manifestSHA256: manifestHash ?? manifest.evidence.byteHash!.value, leftOut: keys)))
            return try CaptureEvidence(evidenceID: RandomLedgerIDGenerator().makeID(EvidenceTag.self), kind: .labelText,
                capturedAt: LedgerFixtures.clock.now(), locale: LedgerText("en_GB"), captureMethod: LedgerText("left out"),
                captureMethodVersion: LedgerText("pfd-estimate-left-out-v1"),
                originalPayload: .text(LedgerText(String(decoding: payload, as: UTF8.self))), byteHash: digester.sha256(payload))
        }
        func read(_ evidence: [CaptureEvidence]) -> ApprovedEstimateSource.LeftOutReading {
            ApprovedEstimateSource.leftOut(resolutionVersionID: version, manifestHash: manifest.evidence.byteHash,
                                           evidence: evidence + [manifest.evidence], digester: digester)
        }
        XCTAssertEqual(read([]), .none)
        XCTAssertEqual(read([try item(other, [.sodium])]), .none, "an earlier version's item is ignored")
        XCTAssertEqual(read([try item(other, [.sodium]), try item(version, [.fiber])]), .keys([.fiber]))
        XCTAssertEqual(read([try altered(try item(version, [.fiber])) { $0.replacingOccurrences(of: "fiber", with: "sodium") }]), .unavailable)
        XCTAssertEqual(read([try item(version, [.fiber], manifestHash: String(repeating: "0", count: 64))]), .unavailable,
                       "the manifest it names must be the one it is read with")
        // The pasted-label reader ignores both kinds, and this reader ignores other label text.
        XCTAssertFalse(PastedLabelEvidenceManifest.isVersion("pfd-estimate-capture-v1"))
        XCTAssertFalse(PastedLabelEvidenceManifest.isVersion("pfd-estimate-left-out-v1"))
        let pasted = try CaptureEvidence(evidenceID: RandomLedgerIDGenerator().makeID(EvidenceTag.self), kind: .labelText,
            capturedAt: LedgerFixtures.clock.now(), locale: LedgerText("en_GB"), captureMethod: LedgerText("pasted"),
            captureMethodVersion: LedgerText(ReviewedFoodProposalConfirmation.version), originalPayload: .text(LedgerText("{}")))
        XCTAssertFalse(ApprovedEstimateSource.isManifest(pasted) || ApprovedEstimateSource.isLeftOut(pasted))
        // With evidence unavailable a later correction keeps the saved unknowns.
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        XCTAssertEqual(state.estimateSeed.evidenceAvailable, true)
        state.estimateSeed = ApprovedEstimateSeed(evidenceAvailable: false)
        XCTAssertEqual(state.estimateSeed.leftOut, [])
    }
}

private extension FoodConfirmationState {
    /// The evidence IDs of a stored record as the store reads them back for this reopened state.
    func evidence(of saved: StoredFoodConfirmation) -> [EvidenceID] {
        (reopened?.evidence ?? []).map(\.evidenceID)
    }
}
