import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import GRDB
import XCTest

/// Food quick add contract v1 (#198), section 8: tests 1 to 11 and A to U.
final class QuickAddContractTests: XCTestCase {

    // MARK: 1. Same entry as Confirm

    func test01SheetAndConfirmSavesProduceTheSameEntry() throws {
        for kind in ["exact", "water"] {
            var payloads: [String: [Data]] = [:]
            for path in ["sheet", "confirm"] {
                for harness in try LedgerFixtures.harnesses() {
                    defer { harness.cleanup() }
                    let context = try QuickAddContext(harness)
                    let preparation: QuickAddPreparation
                    if kind == "exact" {
                        let saved = try context.logExact(40, aliases: [])
                        let favourite = try context.favourites.saveFavourite(logItemVersionID: saved.logItemVersion.logItemVersionID)
                        preparation = try context.favourites.prepare(.favourite(favourite))
                    } else {
                        preparation = try context.favourites.prepare(.builtInWater)
                    }
                    XCTAssertEqual(preparation.eligibility, .sheet, kind)
                    var state: FoodConfirmationState
                    if path == "sheet" {
                        state = preparation.state
                    } else {
                        // Confirm (the sheet's Edit) with the same input, amount and time.
                        state = FoodConfirmationState(input: preparation.state.input, prefillSourceQuantity: false)
                        state.quantity = preparation.state.quantity
                    }
                    FoodConfirmationReducer.reduce(state: &state, action: .accept)
                    let before = try context.operations().count
                    let saved = try context.confirmations.save(state, operationID: LedgerFixtures.operationID(4_000))
                    XCTAssertEqual(try context.operations().count, before + 1)
                    let operation = try XCTUnwrap(harness.committer.operation(id: LedgerFixtures.operationID(4_000)))
                    XCTAssertEqual(operation.operationType, .confirmFood, "\(kind) \(path)")
                    XCTAssertTrue(saved.assertions.isEmpty, "\(kind) \(path)")
                    XCTAssertEqual(saved.resolutionVersion.methodVersion.value, FoodConfirmationPolicy.version)
                    XCTAssertEqual(saved.logItemVersion.reportingDate.value, FoodReportingDay.key(for: LedgerFixtures.date, calendar: QuickAddFixtures.london))
                    payloads[path, default: []].append(operation.payload)
                }
            }
            XCTAssertEqual(payloads["sheet"], payloads["confirm"], "\(kind): identical mutations")
        }
    }

    // MARK: 2. No single-tap log

    func test02PreparingWritesNothingAndOneLogWritesOnce() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let saved = try context.logExact(41)
            let favourite = try context.favourites.saveFavourite(logItemVersionID: saved.logItemVersion.logItemVersionID)
            let before = try context.harness.reader.counts()
            for item in [QuickAddItem.builtInWater, .favourite(favourite)] { _ = try context.favourites.prepare(item) }
            XCTAssertEqual(try context.harness.reader.counts(), before, "Opening the sheet writes nothing")
            _ = try context.log(try context.favourites.prepare(.favourite(favourite)))
            XCTAssertEqual(try context.harness.reader.counts().operations, before.operations + 1)
            XCTAssertEqual(try context.harness.reader.counts().logItemVersions, before.logItemVersions + 1)
        }
    }

    // MARK: 3 and D. Eligibility union

    func test03EligibilityUnionOpensConfirm() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            var cases: [(String, LogItemVersionID, QuickAddIneligibility?)] = []
            // Exact: eligible.
            cases.append(("exact", try context.logExact(50).logItemVersion.logItemVersionID, nil))
            // Generic CoFID estimate.
            let search = try CoFIDGenericFoodSearch(ids: context.ids)
            guard case let .confirmation(route) = try search.search(GenericFoodSearchRequest(text: try LedgerText("rice"),
                capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"))) else { return XCTFail("rice") }
            var generic = FoodConfirmationState(input: route.confirmation)
            FoodConfirmationReducer.reduce(state: &generic, action: .setQuantity(100, .grams))
            generic.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &generic, action: .accept)
            cases.append(("generic", try context.confirmations.save(generic, operationID: context.ids.makeID(OperationTag.self)).logItemVersion.logItemVersionID, .estimate))
            // Representative web estimate.
            let web = try ReviewedWebFixtures.v1Fixture("representative-serving").input
            var representative = FoodConfirmationState(input: web)
            FoodConfirmationReducer.reduce(state: &representative, action: .setQuantity(1, .count))
            representative.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &representative, action: .accept)
            cases.append(("representative web", try context.confirmations.save(representative, operationID: context.ids.makeID(OperationTag.self)).logItemVersion.logItemVersionID, .estimate))
            // Differs and not sure decisions.
            for (offset, choice) in [(0, FoodLogDecisionChoice.differs("raw")), (1, .notSure)] {
                var state = FoodConfirmationState(input: try QuickAddFixtures.exactInput(51 + offset, expected: QuickAddFixtures.rawIdentity()),
                                                  prefillSourceQuantity: false)
                FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(100, .grams))
                FoodConfirmationReducer.reduce(state: &state, action: .decideDifference(.preparation, choice))
                FoodConfirmationReducer.reduce(state: &state, action: .accept)
                cases.append(("\(choice)", try context.confirmations.save(state, operationID: context.ids.makeID(OperationTag.self)).logItemVersion.logItemVersionID, .estimate))
            }
            // A corrected exact product (correction at first save: rejected decision, correction assertion).
            let exactInput = try QuickAddFixtures.exactInput(53)
            var corrected = FoodConfirmationState(input: exactInput, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &corrected, action: .setQuantity(100, .grams))
            FoodConfirmationReducer.reduce(state: &corrected, action: .applyCorrection(try QuickAddFixtures.correction(exactInput.candidates[0])))
            cases.append(("corrected", try context.confirmations.save(corrected, operationID: context.ids.makeID(OperationTag.self)).logItemVersion.logItemVersionID, .corrected))
            // A corrected product version (an edit with a correction: product ordinal 2).
            let edited = try context.logExact(54)
            var reopened = try XCTUnwrap(context.confirmations.reopen(logItemID: edited.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &reopened, action: .applyCorrection(try QuickAddFixtures.correction(reopened.input.candidates[0])))
            cases.append(("corrected version", try context.confirmations.save(reopened, operationID: context.ids.makeID(OperationTag.self)).logItemVersion.logItemVersionID, .corrected))

            for (name, versionID, expected) in cases {
                let favourite = try context.favourites.saveFavourite(logItemVersionID: versionID)
                let preparation = try context.favourites.prepare(.favourite(favourite))
                XCTAssertEqual(preparation.eligibility, expected.map(QuickAddEligibility.confirm) ?? .sheet, "\(context.harness.name) \(name)")
            }
            // The service still refuses unmet requirements with the view model bypassed.
            var unmet = FoodConfirmationState(input: try QuickAddFixtures.exactInput(55, expected: QuickAddFixtures.rawIdentity()), prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &unmet, action: .setQuantity(100, .grams))
            FoodConfirmationReducer.reduce(state: &unmet, action: .accept)
            XCTAssertThrowsError(try context.confirmations.save(unmet, operationID: context.ids.makeID(OperationTag.self))) {
                guard case FoodConfirmationSaveError.unmetRequirements = $0 else { return XCTFail("\($0)") }
            }
        }
    }

    func testDEachCorrectionConditionAloneOpensConfirm() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let pinned = try context.logExact(56)
            XCTAssertTrue(QuickAddPolicy.pinnedIsUncorrected(pinned))
            let log = pinned.logItemVersion
            let reresolved = try LogItemVersion(logItemVersionID: log.logItemVersionID, logItemID: log.logItemID, ordinal: log.ordinal,
                occurredAt: log.occurredAt, reportingDate: log.reportingDate, composition: log.composition, edibleQuantity: log.edibleQuantity,
                originalResolutionVersionID: LedgerFixtures.id(9_999, ResolutionVersionTag.self),
                effectiveResolutionVersionID: log.effectiveResolutionVersionID, createdAt: log.createdAt)
            let version = pinned.productVersion
            let secondVersion = try ProductVersion(productVersionID: version.productVersionID, productID: version.productID,
                ordinal: VersionOrdinal(2), supersedesProductVersionID: LedgerFixtures.id(9_998, ProductVersionTag.self), name: version.name,
                itemClass: version.itemClass, packFacts: version.packFacts, identity: version.identity, evidenceIDs: version.evidenceIDs,
                assertionIDs: [], createdAt: version.createdAt)
            let rejected = try CandidateDecision(candidateDecisionID: pinned.candidateDecision.candidateDecisionID,
                candidate: pinned.candidateDecision.candidate, expectedIdentity: pinned.candidateDecision.expectedIdentity,
                expectedEdibleQuantity: pinned.candidateDecision.expectedEdibleQuantity, requestedOutcome: .rejected, createdAt: LedgerFixtures.date)
            let assertion = UserAssertion(assertionID: try LedgerFixtures.id(9_997, AssertionTag.self), author: .user, createdAt: LedgerFixtures.date,
                reason: try LedgerText("Synthetic"), claim: try LedgerText("Corrected populated confirmation for Fixture food 56"))
            func replacing(log: LogItemVersion? = nil, product: ProductVersion? = nil, decision: CandidateDecision? = nil,
                           assertions: [UserAssertion]? = nil) -> StoredFoodConfirmation {
                StoredFoodConfirmation(evidence: pinned.evidence, sourceReleases: pinned.sourceReleases, product: pinned.product,
                    productVersion: product ?? pinned.productVersion, resolution: pinned.resolution, resolutionVersion: pinned.resolutionVersion,
                    logItem: pinned.logItem, logItemVersion: log ?? pinned.logItemVersion, quantityConversion: nil, plate: nil,
                    plateWeightVersion: nil, candidateDecision: decision ?? pinned.candidateDecision, assertions: assertions ?? pinned.assertions)
            }
            for (name, stored) in [("re-resolved", replacing(log: reresolved)), ("product version 2", replacing(product: secondVersion)),
                                   ("rejected decision", replacing(decision: rejected)), ("correction assertion", replacing(assertions: [assertion]))] {
                XCTAssertFalse(QuickAddPolicy.pinnedIsUncorrected(stored), name)
                let state = try context.favourites.prepare(.builtInWater).state
                XCTAssertEqual(QuickAddPolicy.eligibility(pinned: stored, pinnedIsEstimate: false, rebuilt: state,
                    now: LedgerFixtures.date, calendar: QuickAddFixtures.london), .confirm(.corrected), name)
            }
        }
    }

    // MARK: 4. Requirement split

    func test04EveryRequirementIsClassifiedOnce() {
        let sheet: [FoodLogRequirement] = [.amountMissing, .amountTextInvalid, .occurredAtInFuture, .occurredAtTooEarly]
        let confirm: [FoodLogRequirement] = [.decideDifference(.preparation), .sourceIdentityMissing([.bone]), .recipeServingsRequired,
            .sourceServingsRequired, .measuredWeightMissing, .weightBasisMissing, .retainedWeightNeedsConfirmation,
            .countNeedsMeasuredAmount, .emptyPlateWeightMissing, .plateNeedsGramTotal, .plateNotLighterThanTotal]
        XCTAssertEqual(sheet.count + confirm.count, 15, "Every FoodLogRequirement case is listed")
        for requirement in sheet { XCTAssertEqual(QuickAddPolicy.placement(requirement), .sheet, "\(requirement)") }
        for requirement in confirm { XCTAssertEqual(QuickAddPolicy.placement(requirement), .confirm, "\(requirement)") }
    }

    // MARK: 5. Favourite edits never rewrite entries

    func test05FavouriteEditsLeaveEveryLogRecordAndHashUnchanged() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let first = try context.favourites.saveFavourite(logItemVersionID: context.logExact(60).logItemVersion.logItemVersionID)
            let second = try context.favourites.saveFavourite(logItemVersionID: context.logExact(61).logItemVersion.logItemVersionID)
            _ = try context.logWater(250)
            let recordsBefore = try LedgerFixtures.encoder.encode(context.records())
            let operationsBefore = try context.operations().sorted { $0.actorSequence < $1.actorSequence }
            try context.favourites.rename(first.favouriteID, to: LedgerText("Morning food"))
            try context.favourites.setDefaultAmount(first.favouriteID, to: FavouriteAmount(value: 90, unit: .grams))
            try context.favourites.arrange([.favourite(second), .favourite(first)])
            try context.favourites.remove(second.favouriteID)
            XCTAssertEqual(try LedgerFixtures.encoder.encode(context.records()), recordsBefore, context.harness.name)
            let operationsAfter = try context.operations().sorted { $0.actorSequence < $1.actorSequence }
            XCTAssertEqual(Array(operationsAfter.prefix(operationsBefore.count)), operationsBefore)
            XCTAssertEqual(operationsAfter.dropFirst(operationsBefore.count).map(\.operationType),
                           [.reviseFavourite, .reviseFavourite, .arrangeFavourites, .reviseFavourite])
            let projection = try context.favourites.projection()
            XCTAssertEqual(projection.favourites.map(\.favouriteID), [first.favouriteID])
            XCTAssertEqual(projection.favourites.first?.label.value, "Morning food")
            XCTAssertEqual(projection.favourites.first?.defaultAmount, try FavouriteAmount(value: 90, unit: .grams))
        }
    }

    // MARK: 6 and B. Pinned binding

    func test06PinnedBindingSurvivesSourceRemovalRestoreCorrectionAndRetiming() throws {
        for change in ["removed", "restored", "corrected", "re-timed"] {
            for context in try QuickAddFixtures.contexts() {
                defer { context.harness.cleanup() }
                let saved = try context.logExact(70)
                let favourite = try context.favourites.saveFavourite(logItemVersionID: saved.logItemVersion.logItemVersionID)
                let inputBefore = try context.favourites.prepare(.favourite(favourite)).state.input
                let id = saved.logItem.logItemID, reason = try LedgerText("Synthetic change")
                switch change {
                case "removed", "restored":
                    let removed = try context.management.remove(logItemID: id, expectedVersion: saved.logItemVersion.logItemVersionID,
                        reason: reason, operationID: context.ids.makeID(OperationTag.self))
                    if change == "restored" {
                        _ = try context.management.restore(logItemID: id, expectedVersion: removed.logItemVersionID,
                            reason: reason, operationID: context.ids.makeID(OperationTag.self))
                    }
                case "corrected":
                    var state = try XCTUnwrap(context.confirmations.reopen(logItemID: id))
                    FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try QuickAddFixtures.correction(state.input.candidates[0])))
                    _ = try context.confirmations.save(state, operationID: context.ids.makeID(OperationTag.self))
                default:
                    var state = try XCTUnwrap(context.confirmations.reopen(logItemID: id))
                    FoodConfirmationReducer.reduce(state: &state, action: .setOccurredAt(LedgerFixtures.date.addingTimeInterval(-3_600)))
                    _ = try context.confirmations.save(state, operationID: context.ids.makeID(OperationTag.self))
                }
                let preparation = try context.favourites.prepare(.favourite(favourite))
                XCTAssertEqual(preparation.state.input, inputBefore, "\(change) \(context.harness.name)")
                XCTAssertEqual(preparation.eligibility, .sheet)
                let evidenceBefore = try context.harness.reader.counts().evidence
                let quick = try context.log(preparation)
                XCTAssertEqual(try context.harness.reader.counts().evidence, evidenceBefore, "\(change): no duplicate evidence")
                XCTAssertNotEqual(quick.logItem.logItemID, id)
                XCTAssertEqual(quick.logItemVersion.ordinal.value, 1, "Quick add creates a new log item at version 1")
            }
        }
    }

    func test06TamperedReviewedManifestMakesFavouriteUnverifiable() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            var state = FoodConfirmationState(input: try ReviewedWebFixtures.v1Fixture("representative-serving").input)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(1, .count))
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try context.confirmations.save(state, operationID: context.ids.makeID(OperationTag.self))
            XCTAssertNoThrow(try context.confirmations.favouriteInput(saved))
            guard case let .text(text) = saved.evidence[0].originalPayload else { return XCTFail("manifest") }
            let tampered = try CaptureEvidence(evidenceID: saved.evidence[0].evidenceID, kind: saved.evidence[0].kind,
                capturedAt: saved.evidence[0].capturedAt, locale: saved.evidence[0].locale, captureMethod: saved.evidence[0].captureMethod,
                captureMethodVersion: saved.evidence[0].captureMethodVersion,
                originalPayload: .text(LedgerText(text.value.replacingOccurrences(of: "150", with: "151"))), byteHash: saved.evidence[0].byteHash)
            let altered = StoredFoodConfirmation(evidence: [tampered], sourceReleases: saved.sourceReleases, product: saved.product,
                productVersion: saved.productVersion, resolution: saved.resolution, resolutionVersion: saved.resolutionVersion,
                logItem: saved.logItem, logItemVersion: saved.logItemVersion, quantityConversion: nil, plate: nil,
                plateWeightVersion: nil, candidateDecision: saved.candidateDecision, assertions: saved.assertions)
            XCTAssertThrowsError(try context.confirmations.favouriteInput(altered))
        }
    }

    // MARK: 7 and F. No alias growth

    func test07QuickAddsAndWaterLogsCreateNoLibraryAlias() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let saved = try context.logExact(80, aliases: ["fixture alias"])
            let alias = try LedgerText("fixture alias")
            XCTAssertEqual(try context.harness.reader.exactLibraryEntries(alias: alias).count, 1, "First exact confirm creates the alias")
            let favourite = try context.favourites.saveFavourite(logItemVersionID: saved.logItemVersion.logItemVersionID)
            XCTAssertTrue(try context.favourites.prepare(.favourite(favourite)).state.input.candidates[0].candidate.matchMetadata?.libraryAliases.isEmpty ?? true)
            for _ in 0..<3 {
                _ = try context.log(try context.favourites.prepare(.favourite(favourite)))
                _ = try context.logWater(250)
            }
            let records = try context.records()
            XCTAssertEqual(records.libraryEntries.count, 1, context.harness.name)
            XCTAssertEqual(records.libraryEntryVersions.count, 1)
            XCTAssertEqual(try context.harness.reader.exactLibraryEntries(alias: alias).map(\.productVersionID), [saved.productVersion.productVersionID])
            XCTAssertTrue(try context.harness.reader.exactLibraryEntries(alias: favourite.label).isEmpty, "A favourite label is never an alias")
        }
    }

    // MARK: 8 and K. Water reference

    func test08WaterReferenceGoldenBytesNutrientsAndCompleteness() throws {
        let counting = CountingDigester()
        let water = try PlainWaterReference(digester: counting)
        XCTAssertGreaterThan(counting.count, 0, "Hashes use the injected digester")
        XCTAssertEqual(water.definitionHash.value, Self.waterDefinitionSHA256)
        XCTAssertEqual(try SHA256Digester().sha256(Data(PlainWaterReference.definition.utf8)).value, Self.waterDefinitionSHA256)
        XCTAssertEqual(water.sourceRelease.artifactHash, water.definitionHash)
        XCTAssertEqual(water.sourceRelease.manifestHash, water.definitionHash)
        XCTAssertEqual(water.evidence.byteHash, water.definitionHash)
        XCTAssertEqual(water.evidence.kind.rawValue, "reference_definition")
        XCTAssertEqual(water.sourceRelease.sourceID.value, "weeklyhealthreport.reference")
        XCTAssertEqual(water.sourceRelease.pipelineVersion.value, "plain-water-v1")
        XCTAssertEqual(water.sourceRelease.releasedAt, ISO8601DateFormatter().date(from: "2026-10-11T00:00:00Z"))
        let state = water.state(millilitres: 250)
        XCTAssertTrue(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: QuickAddFixtures.london).isEmpty,
                      "Exact identity raises no requirement")
        XCTAssertFalse(state.isGenericEstimate)
        XCTAssertFalse(FoodLogPolicy.savesEstimate(state))
        XCTAssertNil(FoodReviewedWebProposalPolicy.scope(state.input, candidate: state.input.candidates[0]))
        for entry in water.candidate.candidate.nutrients.entries {
            switch (entry.key, entry.value) {
            case (.water, .measured(let value)): XCTAssertEqual(value.amount, 100)
            case (.energyConsumed, .measured(let value)), (.protein, .measured(let value)), (.carbohydrates, .measured(let value)),
                 (.fatTotal, .measured(let value)), (.fatSaturated, .measured(let value)), (.fatMonounsaturated, .measured(let value)),
                 (.fatPolyunsaturated, .measured(let value)), (.sugar, .measured(let value)), (.fiber, .measured(let value)),
                 (.cholesterol, .measured(let value)):
                XCTAssertEqual(value.amount, 0, "\(entry.key)")
            case (_, .unknown):
                XCTAssertFalse(PlainWaterReference.exactPer100Millilitres.keys.contains(entry.key), "\(entry.key)")
            default: XCTFail("\(entry.key) \(entry.value)")
            }
        }
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let saved = try context.logWater(500)
            let projection = try FoodIntakeProjection(records: context.records(), reportingDate: saved.logItemVersion.reportingDate.value)
            for key in [NutrientKey.energyConsumed, .protein, .carbohydrates, .fatTotal, .fatSaturated, .sugar, .fiber, .cholesterol] {
                let total = try XCTUnwrap(projection.summary.totals.first { $0.key == key })
                XCTAssertEqual(total.knownAmount, 0, "\(key)"); XCTAssertEqual(total.incompleteContributions, 0, "\(key)")
                XCTAssertFalse(total.includesEstimates)
            }
            XCTAssertEqual(projection.summary.totals.first { $0.key == .water }?.knownAmount, 500)
            let sodium = try XCTUnwrap(projection.summary.totals.first { $0.key == .sodium })
            XCTAssertEqual(sodium.incompleteContributions, 1, "Sodium is a known minimum on a water day")
        }
    }

    static let waterDefinitionSHA256 = "e513e5a6490b516555bee1ea3ecc92b0de844d63ec65f842a2715bf45ba2fba8"

    // MARK: 9. Water daily-first

    func test09WaterAggregatesDailyFirstAcrossBackdatingAndDST() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let day = FoodReportingDay.key(for: LedgerFixtures.date, calendar: QuickAddFixtures.london)
            XCTAssertNil(try PlainWaterDayTotal.millilitres(records: context.records(), reportingDate: day), "Empty is No data")
            let entries = try [150.0, 250, 330].map { try context.logWater($0) }
            _ = try context.logExact(90)
            XCTAssertEqual(try PlainWaterDayTotal.millilitres(records: context.records(), reportingDate: day), 730)
            _ = try context.management.remove(logItemID: entries[0].logItem.logItemID, expectedVersion: entries[0].logItemVersion.logItemVersionID,
                reason: LedgerText("Removed"), operationID: context.ids.makeID(OperationTag.self))
            var edit = try XCTUnwrap(context.confirmations.reopen(logItemID: entries[1].logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &edit, action: .setQuantity(200, .millilitres))
            _ = try context.confirmations.save(edit, operationID: context.ids.makeID(OperationTag.self))
            XCTAssertEqual(try PlainWaterDayTotal.millilitres(records: context.records(), reportingDate: day), 530,
                           "Removed and superseded versions contribute nothing")
        }
        // Backdated entries land on the derived local date, across DST changes.
        let cases: [(String, String, String)] = [
            ("Europe/London", "2026-03-29T00:30:00Z", "2026-03-29"), ("Europe/London", "2026-03-29T23:30:00Z", "2026-03-30"),
            ("Europe/London", "2026-10-25T00:30:00Z", "2026-10-25"), ("Europe/London", "2026-10-25T23:30:00Z", "2026-10-25"),
            ("Pacific/Auckland", "2026-03-28T11:30:00Z", "2026-03-29"), ("Pacific/Auckland", "2026-10-24T11:30:00Z", "2026-10-25")
        ]
        for (zone, instant, expected) in cases {
            let occurredAt = try XCTUnwrap(ISO8601DateFormatter().date(from: instant))
            let clock = FixedClock(value: occurredAt.addingTimeInterval(2 * 86_400))
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }
                let context = try QuickAddContext(harness, clock: clock, calendar: QuickAddFixtures.calendar(zone))
                let saved = try context.logWater(250, occurredAt: occurredAt)
                XCTAssertEqual(saved.logItemVersion.reportingDate.value, expected, "\(zone) \(instant)")
                XCTAssertEqual(try PlainWaterDayTotal.millilitres(records: context.records(), reportingDate: expected), 250)
            }
        }
    }

    // MARK: 10 and G. Decoding and heads

    func test10StrictDecodingRejectsEveryInvalidShape() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let valid = try LedgerFixtures.encoder.encode(QuickAddFixtures.favouriteVersion(1, favourite: 1))
        let text = try XCTUnwrap(String(data: valid, encoding: .utf8))
        XCTAssertNoThrow(try decoder.decode(FavouriteVersion.self, from: valid))
        let invalid = [
            text.replacingOccurrences(of: #""value":250"#, with: #""value":0"#),
            text.replacingOccurrences(of: #""value":250"#, with: #""value":-1"#),
            text.replacingOccurrences(of: #""label":"Favourite 1""#, with: #""label":"  ""#),
            text.replacingOccurrences(of: #""reference""#, with: #""recipe""#),
            text.replacingOccurrences(of: #""plain-water-v1""#, with: #""plain-water-v2""#),
            text.replacingOccurrences(of: #""unit":"mL""#, with: #""unit":"g""#),
            text.replacingOccurrences(of: #""state":"active""#, with: #""state":"hidden""#)
        ]
        for json in invalid {
            XCTAssertNotEqual(json, text)
            XCTAssertThrowsError(try decoder.decode(FavouriteVersion.self, from: Data(json.utf8)), json)
        }
        XCTAssertThrowsError(try FavouriteAmount(value: .nan, unit: .grams))
        XCTAssertThrowsError(try FavouriteAmount(value: .infinity, unit: .grams))
        let arrangement = try FavouriteArrangement(arrangementVersionID: LedgerFixtures.id(1, FavouriteArrangementVersionTag.self),
            ordinal: VersionOrdinal(1), order: [LedgerFixtures.id(1, FavouriteTag.self)], createdAt: LedgerFixtures.date)
        let arrangementText = try XCTUnwrap(String(data: LedgerFixtures.encoder.encode(arrangement), encoding: .utf8))
        let id = try LedgerFixtures.id(1, FavouriteTag.self).rawValue
        XCTAssertThrowsError(try decoder.decode(FavouriteArrangement.self,
            from: Data(arrangementText.replacingOccurrences(of: #"["\#(id)"]"#, with: #"["\#(id)","\#(id)"]"#).utf8)))
    }

    func test10ProjectionHeadsOrderAndFirstFour() throws {
        func id(_ n: Int) throws -> FavouriteID { try LedgerFixtures.id(n, FavouriteTag.self) }
        let entries = try (1...6).map { FavouriteEntry(favouriteID: try id($0), createdAt: LedgerFixtures.date.addingTimeInterval(Double($0))) }
        var versions = try (1...6).map { try QuickAddFixtures.favouriteVersion($0, favourite: $0, binding: .savedEntry(LedgerFixtures.id($0, LogItemVersionTag.self))) }
        versions.append(try QuickAddFixtures.favouriteVersion(7, favourite: 2, ordinal: 2, supersedes: 2,
            binding: .savedEntry(LedgerFixtures.id(2, LogItemVersionTag.self)), state: .removed))
        let arrangement = try FavouriteArrangement(arrangementVersionID: LedgerFixtures.id(1, FavouriteArrangementVersionTag.self),
            ordinal: VersionOrdinal(1), order: [try id(5), try id(2), try id(3)], createdAt: LedgerFixtures.date)
        let projection = try FavouritesProjection(records: FavouriteMutation(favourites: entries, favouriteVersions: versions, arrangements: [arrangement]))
        XCTAssertEqual(projection.favourites.map(\.favouriteID), try [5, 3, 1, 4, 6].map(id), "Removed dropped; missing appended by creation time")
        XCTAssertTrue(projection.showsBuiltInWater)
        XCTAssertEqual(projection.todayItems.count, 4)
        XCTAssertEqual(projection.todayItems.first, .builtInWater)
        XCTAssertEqual(projection.otherItems.count, 2)

        var competing = versions
        competing.append(try QuickAddFixtures.favouriteVersion(8, favourite: 3, ordinal: 2, supersedes: 3,
            binding: .savedEntry(LedgerFixtures.id(3, LogItemVersionTag.self))))
        competing.append(try QuickAddFixtures.favouriteVersion(9, favourite: 3, ordinal: 2, supersedes: 3,
            binding: .savedEntry(LedgerFixtures.id(3, LogItemVersionTag.self))))
        XCTAssertThrowsError(try FavouritesProjection(records: FavouriteMutation(favourites: entries, favouriteVersions: competing))) {
            XCTAssertEqual($0 as? FavouritesProjectionError, .competingFavouriteHeads)
        }
        let second = try FavouriteArrangement(arrangementVersionID: LedgerFixtures.id(2, FavouriteArrangementVersionTag.self),
            ordinal: VersionOrdinal(2), supersedesArrangementVersionID: arrangement.arrangementVersionID, order: [], createdAt: LedgerFixtures.date)
        let third = try FavouriteArrangement(arrangementVersionID: LedgerFixtures.id(3, FavouriteArrangementVersionTag.self),
            ordinal: VersionOrdinal(2), supersedesArrangementVersionID: arrangement.arrangementVersionID, order: [], createdAt: LedgerFixtures.date)
        XCTAssertThrowsError(try FavouritesProjection(records: FavouriteMutation(favourites: entries, favouriteVersions: versions,
                                                                                 arrangements: [arrangement, second, third]))) {
            XCTAssertEqual($0 as? FavouritesProjectionError, .competingArrangementHeads)
        }
    }

    func testGCompetingArrangementHeadsFromStoresFailTheProjection() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let favourite = try context.favourites.saveFavourite(logItemVersionID: context.logExact(95).logItemVersion.logItemVersionID)
            try context.favourites.arrange([.favourite(favourite)])
            let head = try XCTUnwrap(context.favourites.projection().arrangement)
            for n in [1, 2] {
                let competing = try FavouriteArrangement(arrangementVersionID: context.ids.makeID(FavouriteArrangementVersionTag.self),
                    ordinal: VersionOrdinal(2), supersedesArrangementVersionID: head.arrangementVersionID, order: [], createdAt: LedgerFixtures.date)
                _ = try context.ledger.commitFavourites(FavouriteMutation(arrangements: [competing]), type: .arrangeFavourites,
                    operationID: LedgerFixtures.operationID(4_100 + n))
            }
            XCTAssertThrowsError(try context.favourites.projection()) {
                XCTAssertEqual($0 as? FavouritesProjectionError, .competingArrangementHeads, context.harness.name)
            }
        }
    }

    // MARK: 11, C and Q. Compatibility

    func test11LiteralPreV6PayloadOperationAndProjectionBytesUnchanged() throws {
        let mutation = try LedgerFixtures.baseMutation()
        let transaction = try LedgerFixtures.validTransaction(mutation: mutation, operationID: LedgerFixtures.operationID(1),
            actorID: LedgerFixtures.id(900, ActorTag.self), sequence: 1, previousHash: nil)
        XCTAssertEqual(transaction.operation.payloadHash.value, "2944f0b4d1f72cc83e5ec2e3a1817162768931d549d7a3c8bb0cda67e0acf540")
        XCTAssertEqual(transaction.operation.operationHash.value, "43b6ca6371c6de02a66cfc6f7bc55a137e64cc902a2dfb648064f2b6509b7a27")
        XCTAssertEqual(try LedgerFixtures.digester.sha256(LedgerFixtures.encoder.encode(transaction.operation)).value,
                       "cb814961cd2be44edeadba6ff09ede7d8432e2b82ebcd9fe91ded72c130e8f5a")
        XCTAssertEqual(transaction.payload, .ledger(mutation))
        XCTAssertEqual(try transaction.payload.encoded(with: LedgerFixtures.encoder), try LedgerFixtures.encoder.encode(mutation))
        XCTAssertNoThrow(try OperationVerifier(encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester).verify(transaction))
        let projection = try CanonicalFoodProjection(records: mutation, foodContractVersion: 5)
        let bytes = try LedgerFixtures.encoder.encode(projection)
        XCTAssertEqual(try LedgerFixtures.digester.sha256(bytes).value, "398dd42e74efca54e4b476cce2294674d656ba8251608ea3d7c2013fde8764e1")
        XCTAssertEqual(bytes.count, 7002)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("favourites"), "A projection without favourites omits the key")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        XCTAssertEqual(try LedgerFixtures.encoder.encode(decoder.decode(CanonicalFoodProjection.self, from: bytes)), bytes)
    }

    func test11RegistryAdmissionAndDailyPin() throws {
        let favourites = FavouriteMutation(favourites: [FavouriteEntry(favouriteID: try LedgerFixtures.id(1, FavouriteTag.self), createdAt: LedgerFixtures.date)])
        for type in LedgerOperationType.favouriteTypes {
            XCTAssertThrowsError(try LedgerOperationRegistry.builtInV4.requireSupported(type), type.rawValue)
            XCTAssertNoThrow(try LedgerOperationRegistry.builtInV6.requireSupported(type, payload: .favourites(favourites)))
            XCTAssertThrowsError(try LedgerOperationRegistry.builtInV6.requireSupported(type, payload: .ledger(LedgerMutation())))
        }
        XCTAssertThrowsError(try LedgerOperationRegistry.builtInV6.requireSupported(.createProduct, payload: .favourites(favourites)))
        XCTAssertEqual(CanonicalFoodProjection.foodContractVersion, 6)
        XCTAssertEqual(FoodLedgerGRDBStore.schemaVersion, 6)
    }

    // MARK: A. Repeated water saves

    func testARepeatedWaterSavesWriteNoDuplicateEvidenceOrRelease() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            _ = try context.logWater(250)
            let afterFirst = try context.records()
            _ = try context.logWater(330)
            _ = try context.logWater(500)
            let records = try context.records()
            XCTAssertEqual(records.evidence.count, afterFirst.evidence.count, context.harness.name)
            XCTAssertEqual(records.sourceReleases.count, afterFirst.sourceReleases.count)
            XCTAssertEqual(records.evidence.filter { $0.kind == .referenceDefinition }.count, 1)
            XCTAssertEqual(records.logItems.count, 3)
        }
    }

    // MARK: E. Binding consistency

    func testEBindingsToMissingOrRemovedVersionsAreRejectedAndQuickAddsNeverReuseRecords() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let saved = try context.logExact(100)
            let removal = try context.management.remove(logItemID: saved.logItem.logItemID, expectedVersion: saved.logItemVersion.logItemVersionID,
                reason: LedgerText("Removed"), operationID: context.ids.makeID(OperationTag.self))
            for (number, target) in [(1, try LedgerFixtures.id(77_777, LogItemVersionTag.self)), (2, removal.logItemVersionID)] {
                let entry = FavouriteEntry(favouriteID: try context.ids.makeID(FavouriteTag.self), createdAt: LedgerFixtures.date)
                let version = try FavouriteVersion(favouriteVersionID: context.ids.makeID(FavouriteVersionTag.self), favouriteID: entry.favouriteID,
                    ordinal: VersionOrdinal(1), binding: .savedEntry(target), label: LedgerText("Bad"),
                    defaultAmount: FavouriteAmount(value: 1, unit: .grams), state: .active, createdAt: LedgerFixtures.date)
                XCTAssertThrowsError(try context.ledger.commitFavourites(FavouriteMutation(favourites: [entry], favouriteVersions: [version]),
                    type: .saveFavourite, operationID: LedgerFixtures.operationID(4_200 + number)), "\(context.harness.name) \(number)")
            }
            XCTAssertThrowsError(try context.favourites.saveFavourite(logItemVersionID: removal.logItemVersionID))
            let favourite = try context.favourites.saveFavourite(logItemVersionID: saved.logItemVersion.logItemVersionID)
            let quick = try context.log(try context.favourites.prepare(.favourite(favourite)))
            XCTAssertNotEqual(quick.product.productID, saved.product.productID)
            XCTAssertNotEqual(quick.productVersion.productVersionID, saved.productVersion.productVersionID)
            XCTAssertNotEqual(quick.resolution.resolutionID, saved.resolution.resolutionID)
            XCTAssertNotEqual(quick.resolutionVersion.resolutionVersionID, saved.resolutionVersion.resolutionVersionID)
        }
    }

    // MARK: H. Built-in water

    func testHBuiltInWaterShownUntilAnyWaterChainExists() throws {
        for remove in [false, true] {
            for context in try QuickAddFixtures.contexts() {
                defer { context.harness.cleanup() }
                XCTAssertEqual(try context.favourites.projection().quickAddItems, [.builtInWater])
                _ = try context.log(try context.favourites.prepare(.builtInWater))
                XCTAssertTrue(try context.favourites.projection().favourites.isEmpty, "Logging writes no favourite")
                XCTAssertTrue(try context.favourites.projection().showsBuiltInWater)
                if remove {
                    try context.favourites.removeBuiltInWater()
                    let records = try (context.harness.committer as! any FavouriteReading).favouriteRecords()
                    XCTAssertEqual(records.favourites.count, 1)
                    XCTAssertEqual(records.favouriteVersions.map(\.state), [.removed])
                    XCTAssertEqual(records.favouriteVersions.first?.binding, .reference(.plainWaterV1))
                } else {
                    try context.favourites.arrange([.builtInWater])
                    let projection = try context.favourites.projection()
                    XCTAssertEqual(projection.favourites.map(\.binding), [.reference(.plainWaterV1)])
                    XCTAssertEqual(projection.arrangement?.order, projection.favourites.map(\.favouriteID))
                }
                XCTAssertFalse(try context.favourites.projection().showsBuiltInWater, "remove \(remove)")
            }
        }
    }

    // MARK: I. save_favourite_v1 idempotency

    func testISaveFavouriteIsIdempotentPerEntryVersion() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let saved = try context.logExact(110)
            let versionID = saved.logItemVersion.logItemVersionID
            // A failure between the log and favourite operations leaves the entry logged; retry saves one.
            let first = try context.favourites.saveFavourite(logItemVersionID: versionID)
            let operations = try context.operations().count
            // Retry after a lost response, and favouriting the same version again: same favourite, no write.
            XCTAssertEqual(try context.favourites.saveFavourite(logItemVersionID: versionID), first)
            XCTAssertEqual(try context.operations().count, operations)
            let derived = try XCTUnwrap(context.operations().first { $0.operationType == .saveFavourite })
            XCTAssertEqual(derived.idempotencyKey?.value, "save_favourite_v1:\(versionID.rawValue)")
            XCTAssertEqual(try context.favourites.projection().favourites.count, 1)
            // A divergent duplicate with the same derived ID resolves to the existing favourite.
            let entry = FavouriteEntry(favouriteID: try context.ids.makeID(FavouriteTag.self), createdAt: LedgerFixtures.date)
            let other = try FavouriteVersion(favouriteVersionID: context.ids.makeID(FavouriteVersionTag.self), favouriteID: entry.favouriteID,
                ordinal: VersionOrdinal(1), binding: .savedEntry(versionID), label: LedgerText("Race"),
                defaultAmount: FavouriteAmount(value: 1, unit: .grams), state: .active, createdAt: LedgerFixtures.date)
            XCTAssertThrowsError(try context.ledger.commitFavourites(FavouriteMutation(favourites: [entry], favouriteVersions: [other]),
                type: .saveFavourite, operationID: derived.operationID, idempotencyKey: derived.idempotencyKey)) {
                XCTAssertEqual($0 as? FoodLedgerStoreError, .divergentDuplicateOperation)
            }
            // After removal, favouriting the same version writes a new favourite with a fresh operation ID.
            try context.favourites.remove(first.favouriteID)
            let again = try context.favourites.saveFavourite(logItemVersionID: versionID)
            XCTAssertNotEqual(again.favouriteID, first.favouriteID)
            let saves = try context.operations().filter { $0.operationType == .saveFavourite }
            XCTAssertEqual(saves.count, 2)
            XCTAssertEqual(Set(saves.map(\.operationID)).count, 2)
        }
    }

    // MARK: J. Classification and contract 6 admission

    func testJProvenanceAndCaptureKindsAreClassifiedAndWaterRequiresContractSix() throws {
        let water = try PlainWaterReference(digester: SHA256Digester())
        let provenance = try XCTUnwrap(water.candidate.candidate.nutrients.entries.first { $0.key == .water }?.value.provenance.first)
        let source = SourceNutrientValue.exact(try SourceExactNutrientValue(amount: 1, unit: LedgerText("mL"), basis: .per100Millilitres))
        let exact = try ExactNutrientValue(amount: 1, unit: .millilitres, sourceValue: source, provenance: [provenance])
        XCTAssertNoThrow(try NutrientEntry(key: .water, value: .measured(exact)), "Measured: admitted with a record ID")
        let unnamed = NutrientProvenance(sourceKind: .appReferenceDefinition, sourceID: provenance.sourceID, sourceReleaseID: provenance.sourceReleaseID)
        XCTAssertThrowsError(try NutrientEntry(key: .water, value: .measured(ExactNutrientValue(amount: 1, unit: .millilitres,
            sourceValue: source, provenance: [unnamed]))))
        XCTAssertThrowsError(try NutrientEntry(key: .water, value: .augmented(exact)), "Augmented: never")
        XCTAssertThrowsError(try NutrientEntry(key: .water, value: .bounded(NutrientBounds(lower: 0, upper: 1, lowerClosed: true,
            upperClosed: true, origin: .measured, unit: .millilitres, sourceValue: source, provenance: [provenance]))), "Bounded: never")
        XCTAssertEqual(ProvenanceSourceKind.appReferenceDefinition.rawValue, "app_reference_definition")
        XCTAssertEqual(CaptureKind.referenceDefinition.rawValue, "reference_definition")
        XCTAssertFalse(FoodConfirmationPolicy.isGenericEstimate(water.input, candidate: water.candidate), "Generic policy: not generic")
        XCTAssertFalse(FoodReviewedWebProposalPolicy.applies(water.input, candidate: water.candidate), "Reviewed web policy: not applicable")
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            _ = try context.logWater(250)
            let records = try context.records()
            XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: records), 6, context.harness.name)
            XCTAssertThrowsError(try CanonicalFoodProjection(records: records, foodContractVersion: 5)) {
                XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(5))
            }
            let bundle = try FoodArchiveGenerator().generate(state: context.archive.archiveState(), ledgerID: LedgerText("water"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            XCTAssertEqual(try FoodArchiveVerifier().verify(bundle).manifest.foodContractVersion, 6)
            XCTAssertFalse((1...5).contains(6), "A contract-5 importer admits 1...5 only and rejects this archive")
        }
    }

    // MARK: L. Plain water predicate

    func testLPlainWaterPredicateFollowsTheEffectiveResolution() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let water = try context.logWater(250)
            XCTAssertTrue(PlainWaterReference.isPlainWater(water.resolutionVersion))
            XCTAssertFalse(PlainWaterReference.isPlainWater(try context.logExact(120).resolutionVersion))
            var state = try XCTUnwrap(context.confirmations.reopen(logItemID: water.logItem.logItemID))
            let release = try ExternalIdentifier(PlainWaterReference.sourceReleaseID)
            let declared = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: try ExternalIdentifier("user"), sourceReleaseID: release)
            let other = try NutrientSet(entries: NutrientKey.allCases.map { key in
                guard key == .sugar else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
                return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: 4, unit: .grams,
                    sourceValue: .exact(SourceExactNutrientValue(amount: 4, unit: LedgerText("g"), basis: .per100Millilitres)), provenance: [declared])))
            })
            let correction = try FoodCorrection(name: LedgerText("Sparkling drink"), brand: nil, variant: nil,
                identity: state.input.candidates[0].candidate.identity, itemClass: .drink, nutrients: other, reason: LedgerText("Not plain water"))
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(correction))
            let corrected = try context.confirmations.save(state, operationID: context.ids.makeID(OperationTag.self))
            XCTAssertFalse(PlainWaterReference.isPlainWater(corrected.resolutionVersion), context.harness.name)
            XCTAssertNil(try PlainWaterDayTotal.millilitres(records: context.records(), reportingDate: corrected.logItemVersion.reportingDate.value))
        }
    }

    // MARK: M. Q10 bound

    func testMCustomWaterBoundIsSheetOnly() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let preparation = try context.favourites.prepare(.builtInWater)
            for (value, valid) in [(0.0, false), (5000.0001, false), (5000.0, true), (1.0, true)] {
                var state = preparation.state
                FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(value, .millilitres))
                let requirements = QuickAddPolicy.sheetRequirements(state, isPlainWater: true, now: LedgerFixtures.date, calendar: QuickAddFixtures.london)
                XCTAssertEqual(requirements.isEmpty, valid, "\(value)")
                if !valid { XCTAssertEqual(requirements, [.amountTextInvalid], "\(value)") }
            }
            var large = preparation.state
            FoodConfirmationReducer.reduce(state: &large, action: .setQuantity(5000.0001, .millilitres))
            XCTAssertTrue(FoodLogPolicy.requirements(large, now: LedgerFixtures.date, calendar: QuickAddFixtures.london).isEmpty, "Confirm is unbounded")
            FoodConfirmationReducer.reduce(state: &large, action: .accept)
            XCTAssertEqual(try context.confirmations.save(large, operationID: context.ids.makeID(OperationTag.self)).logItemVersion.edibleQuantity.value, 5000.0001)
        }
    }

    // MARK: N, O and S. Parity, archive round trip and immutability

    func testOContractSixArchiveWithEveryFavouriteOperationRoundTripsOnBothStores() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let first = try context.favourites.saveFavourite(logItemVersionID: context.logExact(130).logItemVersion.logItemVersionID)
            _ = try context.logWater(250)
            try context.favourites.rename(first.favouriteID, to: LedgerText("Renamed"))
            try context.favourites.arrange([.builtInWater, .favourite(first)])
            let state = try context.archive.archiveState()
            XCTAssertEqual(Set(state.operations.map(\.operationType)).intersection(LedgerOperationType.favouriteTypes),
                           [.saveFavourite, .reviseFavourite])
            try context.favourites.arrange(try context.favourites.projection().quickAddItems.reversed())
            let full = try context.archive.archiveState()
            XCTAssertEqual(Set(full.operations.map(\.operationType)).intersection(LedgerOperationType.favouriteTypes), LedgerOperationType.favouriteTypes)
            let bundle = try FoodArchiveGenerator().generate(state: full, ledgerID: LedgerText("favourites"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.manifest.foodContractVersion, 6)
            XCTAssertEqual(verified.document.projection.favourites.recordCount, full.favourites.recordCount)
            XCTAssertEqual(verified.manifest.recordCount, FoodArchiveGeneratorCount.count(full))
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let archive = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: archive, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                let restored = try archive.archiveState()
                XCTAssertEqual(try CanonicalFoodProjection(records: restored.records, favourites: restored.favourites),
                               verified.document.projection, "\(context.harness.name) to \(destination.name)")
                XCTAssertEqual(restored.operations.sorted { $0.actorSequence < $1.actorSequence },
                               verified.transactions.map(\.operation).sorted { $0.actorSequence < $1.actorSequence })
                let restoredProjection = try FavouritesProjection(records: restored.favourites)
                XCTAssertEqual(restoredProjection, try context.favourites.projection())
            }
        }
    }

    func testPContractFiveManifestWithAFavouriteOperationIsRejected() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            _ = try context.favourites.saveFavourite(logItemVersionID: context.logExact(140).logItemVersion.logItemVersionID)
            let state = try context.archive.archiveState()
            XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: LedgerMutation(), favourites: state.favourites), 6)
            // A contract-5 snapshot of the ledger records with every operation, including the favourite one.
            let projection = try CanonicalFoodProjection(records: state.records, foodContractVersion: 5)
            let document = try CanonicalFoodDocument(projection: projection)
            let snapshot = try LedgerFixtures.encoder.encode(document)
            let sorted = state.operations.sorted { $0.actorSequence < $1.actorSequence }
            var operations = Data()
            for operation in sorted { operations.append(try LedgerFixtures.encoder.encode(operation)); operations.append(0x0A) }
            let last = try XCTUnwrap(sorted.last)
            let manifest = try FoodArchiveManifest(ledgerID: LedgerText("contract-5"), snapshotID: document.snapshotID,
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self),
                sourceReleaseIDs: projection.records.sourceReleases.map(\.sourceReleaseID),
                watermarks: [FoodArchiveWatermark(actorID: last.actorID, endSequence: last.actorSequence, endHash: last.operationHash)],
                recordCount: FoodArchiveGeneratorCount.count(FoodArchiveState(records: state.records, operations: [])),
                operationCount: sorted.count,
                members: [FoodArchiveMember(filename: LedgerText("operations.ndjson"), bytes: operations, digester: LedgerFixtures.digester),
                          FoodArchiveMember(filename: LedgerText("snapshot.json"), bytes: snapshot, digester: LedgerFixtures.digester)],
                foodContractVersion: 5)
            let bundle = FoodArchiveBundle(manifest: try LedgerFixtures.encoder.encode(manifest), snapshot: snapshot, operations: operations)
            XCTAssertThrowsError(try FoodArchiveVerifier().verify(bundle)) {
                XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(5), context.harness.name)
            }
        }
    }

    func testRIdenticalEvidenceIsSkippedAndConflictingEvidenceFails() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let water = try PlainWaterReference(digester: SHA256Digester())
            _ = try context.logWater(250)
            let second = try context.logWater(330)
            let operation = try XCTUnwrap(context.operations().first { op in
                (try? LedgerPayload.decode(op.payload, type: op.operationType))
                    .map { if case let .ledger(m) = $0 { m.logItemVersions.contains { $0.logItemVersionID == second.logItemVersion.logItemVersionID } } else { false } } ?? false
            })
            XCTAssertFalse(operation.affectedIDs.contains(water.evidence.evidenceID.rawValue), "Skipped evidence is not affected")
            XCTAssertFalse(operation.affectedIDs.contains(water.sourceRelease.sourceReleaseID.value))
            // The same evidence ID with different bytes still fails as immutableRecord.
            for changed in [try CaptureEvidence(evidenceID: water.evidence.evidenceID, kind: water.evidence.kind,
                                capturedAt: water.evidence.capturedAt.addingTimeInterval(1), locale: water.evidence.locale,
                                captureMethod: water.evidence.captureMethod, captureMethodVersion: water.evidence.captureMethodVersion,
                                originalPayload: water.evidence.originalPayload, byteHash: water.evidence.byteHash),
                            try CaptureEvidence(evidenceID: water.evidence.evidenceID, kind: water.evidence.kind,
                                capturedAt: water.evidence.capturedAt, locale: water.evidence.locale,
                                captureMethod: water.evidence.captureMethod, captureMethodVersion: water.evidence.captureMethodVersion,
                                originalPayload: water.evidence.originalPayload, byteHash: SHA256Digest(String(repeating: "e", count: 64)))] {
                let input = try PopulatedFoodConfirmation(evidence: [changed], sourceReleases: water.input.sourceReleases,
                    candidates: water.input.candidates, expectedIdentity: water.input.expectedIdentity,
                    expectedEdibleQuantity: water.input.expectedEdibleQuantity)
                var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
                FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(100, .millilitres))
                FoodConfirmationReducer.reduce(state: &state, action: .accept)
                XCTAssertThrowsError(try context.confirmations.save(state, operationID: context.ids.makeID(OperationTag.self))) {
                    guard case FoodLedgerStoreError.immutableRecord = $0 else { return XCTFail("\(context.harness.name) \($0)") }
                }
            }
        }
    }

    func testSFavouriteTablesRefuseUpdateAndDelete() throws {
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let favourite = try context.favourites.saveFavourite(logItemVersionID: context.logExact(150).logItemVersion.logItemVersionID)
            try context.favourites.arrange([.favourite(favourite)])
            // In-memory parity: re-inserting an existing favourite record is refused.
            let duplicate = FavouriteEntry(favouriteID: favourite.favouriteID, createdAt: LedgerFixtures.date)
            XCTAssertThrowsError(try context.ledger.commitFavourites(FavouriteMutation(favourites: [duplicate]), type: .saveFavourite,
                operationID: LedgerFixtures.operationID(4_300))) {
                guard case FoodLedgerStoreError.immutableRecord = $0 else { return XCTFail("\(context.harness.name) \($0)") }
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("favourites-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FoodLedgerGRDBStore.temporary(directory: directory)
        let context = try QuickAddContext(TestHarness(name: "grdb", committer: store, reader: store, cleanup: {}))
        let favourite = try context.favourites.saveFavourite(logItemVersionID: context.logExact(151).logItemVersion.logItemVersionID)
        try context.favourites.arrange([.favourite(favourite)])
        let queue = try DatabaseQueue(path: directory.appendingPathComponent("food-ledger-v1.sqlite").path)
        for table in ["favourite", "favourite_version", "favourite_arrangement_version"] {
            XCTAssertThrowsError(try queue.write { try $0.execute(sql: "UPDATE \(table) SET payload = payload") }, table)
            XCTAssertThrowsError(try queue.write { try $0.execute(sql: "DELETE FROM \(table)") }, table)
        }
        XCTAssertThrowsError(try queue.write {
            try $0.execute(sql: "INSERT INTO favourite_version(version_id, favourite_id, ordinal, payload) VALUES ('x', ?, 9, x'00')",
                           arguments: [favourite.favouriteID.rawValue])
        }, "Exactly one binding column is set")
    }

    // MARK: T. relogSource is gone

    func testTRelogSourceIsGoneAndRecentRelogWritesNoDuplicateEvidence() throws {
        let state = FoodConfirmationState(input: try QuickAddFixtures.exactInput(160))
        XCTAssertFalse(Mirror(reflecting: state).children.contains { $0.label == "relogSource" })
        for context in try QuickAddFixtures.contexts() {
            defer { context.harness.cleanup() }
            let saved = try context.logExact(161)
            var relog = try XCTUnwrap(context.confirmations.relogState(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &relog, action: .accept)
            let before = try context.harness.reader.counts().evidence
            _ = try context.confirmations.save(relog, operationID: context.ids.makeID(OperationTag.self))
            XCTAssertEqual(try context.harness.reader.counts().evidence, before, context.harness.name)
        }
    }
}

/// The manifest record count rule (ledger records plus favourites), as the generator applies it.
enum FoodArchiveGeneratorCount {
    static func count(_ state: FoodArchiveState) -> Int {
        let r = state.records
        return state.favourites.recordCount + r.evidence.count + r.assertions.count + r.products.count + r.productVersions.count
            + r.libraryEntries.count + r.libraryEntryVersions.count + r.resolutions.count + r.resolutionVersions.count
            + r.logItems.count + r.logItemVersions.count + r.quantityConversions.count + r.plates.count
            + r.plateWeightVersions.count + r.candidateDecisions.count + r.conflicts.count + r.sourceReleases.count
            + r.sourceInstallations.count
    }
}

final class CountingDigester: Digesting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    func sha256(_ data: Data) throws -> FoodLedgerDomain.SHA256Digest {
        lock.lock(); count += 1; lock.unlock()
        return try SHA256Digester().sha256(data)
    }
}
