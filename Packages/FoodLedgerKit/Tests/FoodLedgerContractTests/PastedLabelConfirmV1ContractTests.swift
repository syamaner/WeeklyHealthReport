import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Pasted label Confirm v1 (#306, `docs/pasted-label-confirm-v1.md` section 8.5): fortification is
/// asked once on Confirm as Yes / No / Not stated. Yes and No are the manifest answer; Not stated
/// keeps fortification unknown and records the existing typed `not_sure` decision. Synthetic only.
final class PastedLabelConfirmV1ContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures

    private func input(_ answer: PastedLabelIdentity.FortificationAnswer = .unanswered,
                       evidence: Int = 9_100) throws -> PopulatedFoodConfirmation {
        try F.input(F.manifest(answer: answer, corrections: []), evidence: evidence)
    }

    /// An editable pasted-label Confirm: the paste route's flag set, 40 g entered.
    private func state(_ input: PopulatedFoodConfirmation, flagged: Bool = true) -> FoodConfirmationState {
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        state.answersLabelFortification = flagged
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(40, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return state
    }

    private func requirements(_ state: FoodConfirmationState) -> [FoodLogRequirement] {
        FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: .current)
    }

    private func notStated(_ input: PopulatedFoodConfirmation) -> FoodConfirmationState {
        var state = state(input)
        FoodConfirmationReducer.reduce(state: &state, action: .decideDifference(.fortification, .notSure))
        return state
    }

    // MARK: 1. Policy scope

    func test01AnEditablePastedLabelAsksInlineAndNeverRaisesSourceIdentityMissing() throws {
        let unanswered = try input()
        var empty = FoodConfirmationState(input: unanswered, prefillSourceQuantity: false)
        empty.answersLabelFortification = true
        XCTAssertEqual(requirements(empty), [.decideDifference(.fortification), .amountMissing])
        XCTAssertEqual(requirements(state(unanswered)), [.decideDifference(.fortification)])
        // Unflagged (a re-log or favourite): today's rule exactly.
        XCTAssertEqual(requirements(state(unanswered, flagged: false)), [.sourceIdentityMissing([.fortification])])
        // A catalogue source ignores the flag.
        var catalogue = FoodConfirmationState(input: try QuickAddFixtures.exactInput(30_100), prefillSourceQuantity: false)
        catalogue.answersLabelFortification = true
        XCTAssertFalse(PastedLabelFortificationPolicy.applies(catalogue))
    }

    // MARK: 2. Identity v1 closure

    func test02IdentityV1LeavesNothingUnresolvedOnAnEditablePastedLabel() throws {
        for answer in PastedLabelIdentity.FortificationAnswer.allCases {
            for basis: ResolutionBasis in [.per100Grams, .per100Millilitres, .perServing(try PositiveQuantity(value: 30, unit: .grams))] {
                let identity = try PastedLabelIdentity.identity(fortification: answer, servingBasis: basis)
                let missing = FoodConfirmationPolicy.unresolvedIdentity(identity, allowingEstimate: false)
                XCTAssertEqual(missing.filter { $0 != .fortification }, [], "\(answer) \(basis)")
            }
            XCTAssertEqual(state(try input(answer)).unresolvedIdentity, [], "\(answer)")
        }
    }

    // MARK: 3 and 4. Yes, No and Not stated saves

    func test03YesAndNoArePlainExactSavesWithTheManifestAnswer() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            for (index, answer) in [PastedLabelIdentity.FortificationAnswer.yes, .no].enumerated() {
                let source = try input(answer, evidence: 30_200 + index)
                let state = state(source)
                XCTAssertEqual(requirements(state), [], "\(answer)")
                XCTAssertEqual(state.materialDifferences, [])
                let saved = try F.service(harness).save(state, operationID: LedgerFixtures.operationID(30_200 + index))
                XCTAssertEqual(saved.assertions, [], "\(answer) \(harness.name)")
                XCTAssertEqual(saved.productVersion.identity.fortification, answer == .yes ? .fortified : .unfortified)
                XCTAssertEqual(saved.productVersion.itemClass, answer == .yes ? .fortifiedFood : .food)
                let manifest = try XCTUnwrap(PastedLabelValueOrigins.manifest(evidence: saved.evidence,
                    evidenceIDs: saved.candidateDecision.candidate.evidenceIDs))
                XCTAssertEqual(manifest.identityMapping.fortificationAnswer, answer)
            }
        }
    }

    func test04NotStatedRecordsOneTypedDecisionAndIsAnEstimate() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let source = try input(evidence: 30_300)
            let state = notStated(source)
            XCTAssertEqual(requirements(state), [])
            XCTAssertTrue(FoodLogPolicy.savesEstimate(state))
            let service = try F.service(harness)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(30_300))
            XCTAssertEqual(saved.assertions.count, 1, harness.name)
            let assertion = try XCTUnwrap(saved.assertions.first)
            XCTAssertEqual(assertion.reason.value, "Logged with inline decisions under food_confirmation_v5")
            XCTAssertEqual(assertion.claim.value,
                           "Logged under food_confirmation_v5; decisions: fortification: source unknown, choice not_sure")
            let record = try XCTUnwrap(assertion.confirmation)
            XCTAssertEqual(record.decisions.map(\.facet), [.fortification])
            XCTAssertEqual(record.decisions.map(\.sourceState.token), ["unknown"])
            XCTAssertEqual(record.decisions.map(\.choice), [.notSure])
            XCTAssertEqual(saved.productVersion.identity.fortification, .unknown)
            XCTAssertEqual(saved.productVersion.itemClass, .food)
            // As for a v2 unknown-identity estimate: the decision is recorded rejected, with its reason.
            XCTAssertEqual(saved.candidateDecision.outcome, .rejected)
            XCTAssertEqual(saved.candidateDecision.contradictionReasons, [.fortification])
            let manifest = try XCTUnwrap(PastedLabelValueOrigins.manifest(evidence: saved.evidence,
                evidenceIDs: saved.candidateDecision.candidate.evidenceIDs))
            XCTAssertEqual(manifest.identityMapping.fortificationAnswer, .unanswered)
            XCTAssertTrue(FoodEntryEstimateStatus.isEstimate(saved, restoredInput: source), harness.name)
            XCTAssertTrue(PastedLabelFortificationPolicy.recordsNotStated(saved))
        }
    }

    // MARK: 5. Refused direct saves

    func test05TheServiceRefusesUnansweredDiffersAndStaleDecisions() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let unanswered = try input(evidence: 30_400)
            XCTAssertThrowsError(try service.save(state(unanswered), operationID: LedgerFixtures.operationID(30_400))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .unmetRequirements([.decideDifference(.fortification)]))
            }
            for (index, value) in ["fortified", "unfortified"].enumerated() {
                var differs = state(unanswered)
                FoodConfirmationReducer.reduce(state: &differs, action: .decideDifference(.fortification, .differs(value)))
                XCTAssertThrowsError(try service.save(differs, operationID: LedgerFixtures.operationID(30_401 + index))) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .staleDecisions, value)
                }
            }
            // A Not stated left behind after the source became Yes is stale.
            var stale = state(try input(.yes, evidence: 30_405))
            FoodConfirmationReducer.reduce(state: &stale, action: .decideDifference(.fortification, .notSure))
            XCTAssertThrowsError(try service.save(stale, operationID: LedgerFixtures.operationID(30_405))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .staleDecisions)
            }
        }
    }

    // MARK: 7. Reopen

    func test07ANotStatedEntryReopensUnblockedAndAQuantityEditWritesNoAssertion() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(notStated(try input(evidence: 30_500)), operationID: LedgerFixtures.operationID(30_500))
            var reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertFalse(reopened.answersLabelFortification, "reopen never sets the flag")
            XCTAssertTrue(PastedLabelFortificationPolicy.applies(reopened))
            XCTAssertEqual(reopened.unresolvedIdentity, [])
            FoodConfirmationReducer.reduce(state: &reopened, action: .setQuantity(60, .grams))
            FoodConfirmationReducer.reduce(state: &reopened, action: .accept)
            XCTAssertEqual(requirements(reopened), [])
            XCTAssertTrue(FoodLogPolicy.savesEstimate(reopened))
            let edited = try service.save(reopened, operationID: LedgerFixtures.operationID(30_501))
            XCTAssertEqual(edited.logItemVersion.edibleQuantity.value, 60)
            XCTAssertEqual(edited.productVersion, saved.productVersion, "a quantity edit reuses the product version")
            // Reopened again, the edit still carries the original Not stated and stays an estimate.
            let again = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(again.reopened?.assertions, saved.assertions, "no new assertion (\(harness.name))")
            XCTAssertTrue(PastedLabelFortificationPolicy.applies(again))
            XCTAssertTrue(FoodLogPolicy.savesEstimate(again))
        }
    }

    // MARK: 11. One scope predicate; a forged source is refused before C4

    func test11AForgedPastedSourceIsRefusedByAdmissionBeforeAnyRequirement() throws {
        let source = try input(evidence: 30_600)
        let forged = try F.replacing(source, .protein, with: .measured(ExactNutrientValue(amount: 9, unit: .grams,
            sourceValue: .exact(SourceExactNutrientValue(amount: 9, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: source.candidates[0].candidate.nutrients.entries.first { $0.key == .protein }.flatMap {
                if case let .measured(value) = $0.value { return value.provenance } else { return nil }
            } ?? [])))
        XCTAssertTrue(PastedLabelFortificationPolicy.isPastedLabel(forged, candidate: forged.candidates[0]))
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            XCTAssertThrowsError(try F.service(harness).save(notStated(forged), operationID: LedgerFixtures.operationID(30_600))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, harness.name)
            }
        }
    }

    // MARK: 12. Unchanged callers

    func test12TheStaticRuleAndTheEstimateProjectionAreUnchanged() throws {
        let unknown = try PastedLabelIdentity.identity(fortification: .unanswered, servingBasis: .per100Grams)
        XCTAssertEqual(FoodConfirmationPolicy.unresolvedIdentity(unknown, allowingEstimate: false), [.fortification])
        XCTAssertEqual(FoodConfirmationPolicy.unresolvedIdentity(unknown, allowingEstimate: true), [])
        XCTAssertFalse(FoodEntryEstimateStatus.isEstimate(sourceIsGeneric: false, identity: unknown, decisions: []))
        XCTAssertTrue(FoodEntryEstimateStatus.isEstimate(sourceIsGeneric: true, identity: unknown, decisions: []))
        XCTAssertTrue(FoodEntryEstimateStatus.isEstimate(sourceIsGeneric: false, identity: unknown, decisions: [.notSure]))
        let catalogue = FoodConfirmationState(input: try QuickAddFixtures.exactInput(30_700), prefillSourceQuantity: false)
        XCTAssertFalse(FoodLogPolicy.savesEstimate(catalogue))
    }

    // MARK: 13. The saved-entry formatter is total

    func test13TheFortificationFormatterCoversEveryStoredCombination() {
        let rows: [(PastedLabelIdentity.FortificationAnswer, Bool, Bool, String)] = [
            (.yes, false, false, "Yes"), (.yes, true, false, "Yes"),
            (.yes, false, true, "Yes, then corrected in food details"), (.yes, true, true, "Yes, then corrected in food details"),
            (.no, false, false, "No"), (.no, true, false, "No"),
            (.no, false, true, "No, then corrected in food details"), (.no, true, true, "No, then corrected in food details"),
            (.unanswered, true, false, "Not stated"),
            (.unanswered, true, true, "Not stated, then corrected in food details"),
            (.unanswered, false, true, "Not answered (corrected in food details)"),
            (.unanswered, false, false, "Not answered")
        ]
        for (answer, notStated, corrected, expected) in rows {
            XCTAssertEqual(PastedLabelFortificationText.value(answer: answer, recordsNotStated: notStated, corrected: corrected),
                           expected, "\(answer) \(notStated) \(corrected)")
        }
        XCTAssertEqual(PastedLabelFortificationText.title, "Fortification on the label")
    }

    // MARK: 14. Offered set

    func test14TheOfferedSetIsNotSureOnlyForAnEditablePastedLabel() throws {
        let pasted = state(try input())
        XCTAssertEqual(FoodLogPolicy.offeredChoices(pasted, facet: .fortification), [.notSure])
        let unflagged = state(try input(), flagged: false)
        XCTAssertEqual(FoodLogPolicy.offeredChoices(unflagged, facet: .fortification),
                       [.differs("fortified"), .differs("unfortified"), .notSure], "the domain's set, unchanged")
        XCTAssertThrowsError(try {
            var differs = pasted
            FoodConfirmationReducer.reduce(state: &differs, action: .decideDifference(.fortification, .differs("fortified")))
            _ = try FoodLogPolicy.decisionRecord(differs)
        }()) { XCTAssertEqual($0 as? FoodConfirmationSaveError, .staleDecisions) }
        XCTAssertNotNil(try FoodLogPolicy.decisionRecord(notStated(try input())))
    }

    // MARK: 15. Re-log and favourites

    func test15ReLogsKeepTodaysRuleAndQuickAddEligibilityFollowsTheAnswer() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            func eligibility(_ saved: StoredFoodConfirmation) throws -> QuickAddEligibility {
                var rebuilt = FoodConfirmationState(input: try service.favouriteInput(saved), prefillSourceQuantity: false)
                FoodConfirmationReducer.reduce(state: &rebuilt, action: .setQuantity(40, .grams))
                let estimate = FoodEntryEstimateStatus.isEstimate(saved, restoredInput: try service.favouriteInput(saved))
                return QuickAddPolicy.eligibility(pinned: saved, pinnedIsEstimate: estimate, rebuilt: rebuilt,
                                                  now: LedgerFixtures.date, calendar: .current)
            }
            let yes = try service.save(state(try input(.yes, evidence: 30_800)), operationID: LedgerFixtures.operationID(30_800))
            let no = try service.save(state(try input(.no, evidence: 30_801)), operationID: LedgerFixtures.operationID(30_801))
            let notStated = try service.save(notStated(try input(evidence: 30_802)), operationID: LedgerFixtures.operationID(30_802))
            var legacy = state(try input(evidence: 30_803), flagged: false)
            let source = legacy.selectedCandidate
            FoodConfirmationReducer.reduce(state: &legacy, action: .applyCorrection(try FoodCorrection(name: source.name,
                brand: source.brand, variant: nil, identity: try PastedLabelIdentity.identity(fortification: .no, servingBasis: .per100Grams),
                itemClass: .food, nutrients: source.candidate.nutrients, reason: LedgerText("Synthetic: no added vitamins."))))
            FoodConfirmationReducer.reduce(state: &legacy, action: .accept)
            let corrected = try service.save(legacy, operationID: LedgerFixtures.operationID(30_803))

            XCTAssertEqual(try eligibility(yes), .sheet, harness.name)
            XCTAssertEqual(try eligibility(no), .sheet, harness.name)
            XCTAssertEqual(try eligibility(notStated), .confirm(.estimate), harness.name)
            XCTAssertEqual(try eligibility(corrected), .confirm(.corrected), harness.name)

            var relog = try XCTUnwrap(service.relogState(logItemID: notStated.logItem.logItemID))
            XCTAssertFalse(relog.answersLabelFortification)
            FoodConfirmationReducer.reduce(state: &relog, action: .accept)
            XCTAssertTrue(requirements(relog).contains(.sourceIdentityMissing([.fortification])), "a re-log keeps today's rule")
            XCTAssertEqual(PastedLabelFortificationText.value(corrected, manifest: try XCTUnwrap(PastedLabelValueOrigins.manifest(
                evidence: corrected.evidence, evidenceIDs: corrected.candidateDecision.candidate.evidenceIDs))),
                "Not answered (corrected in food details)")
        }
    }

    // MARK: 16. Daily JSON food export: no new field

    func test16ANotStatedEntryExportsWithExactlyTheExistingFields() throws {
        func entryKeys(_ answerNotStated: Bool) throws -> Set<String> {
            let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
            defer { harness.cleanup() }
            let source = try input(answerNotStated ? .unanswered : .no, evidence: 30_900)
            let saved = try F.service(harness).save(answerNotStated ? notStated(source) : state(source),
                                                    operationID: LedgerFixtures.operationID(30_900))
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let request = FoodDailyExportRequest(records: try archive.archiveState().records,
                reportDate: saved.logItemVersion.reportingDate.value, timeZone: .current, dataAsOf: LedgerFixtures.date,
                exportedAt: LedgerFixtures.date, appContext: FoodDailyExportAppContext(appVersion: "0.1.1", appBuild: "42"))
            let document = try FoodDailyExportBuilder.make(request)
            XCTAssertEqual(document.entries.count, 1)
            let data = try JSONEncoder().encode(document.entries[0])
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return Set(object.keys)
        }
        XCTAssertEqual(try entryKeys(true), try entryKeys(false))
    }

    // MARK: 17. Archive round trip of a pre-change Food details correction

    func test17APreChangeCorrectionRoundTripsByteForByteAndStillOffersFoodDetails() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            var legacy = state(try input(evidence: 31_000), flagged: false)
            let source = legacy.selectedCandidate
            FoodConfirmationReducer.reduce(state: &legacy, action: .applyCorrection(try FoodCorrection(name: source.name,
                brand: source.brand, variant: nil, identity: try PastedLabelIdentity.identity(fortification: .no, servingBasis: .per100Grams),
                itemClass: .food, nutrients: source.candidate.nutrients, reason: LedgerText("Synthetic: no added vitamins."))))
            FoodConfirmationReducer.reduce(state: &legacy, action: .accept)
            let saved = try F.service(harness).save(legacy, operationID: LedgerFixtures.operationID(31_000))
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let bundle = try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("pasted"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                let again = try FoodArchiveGenerator().generate(state: live.archiveState(), ledgerID: LedgerText("pasted"),
                    createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
                XCTAssertEqual(again, bundle, "\(harness.name)->\(destination.name)")
                let reopened = try XCTUnwrap(F.service(destination).reopen(logItemID: saved.logItem.logItemID))
                XCTAssertFalse(PastedLabelFortificationPolicy.applies(reopened), "no Not stated recorded")
                XCTAssertEqual(reopened.unresolvedIdentity, [], "the corrected identity is known")
            }
        }
    }

    // MARK: 19. The flag is never persisted

    func test19TheFlagIsAbsentFromEncodedStateAndDecodesFalse() throws {
        var state = state(try input())
        XCTAssertTrue(state.answersLabelFortification)
        let data = try JSONEncoder().encode(state)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("answersLabelFortification"))
        let decoded = try JSONDecoder().decode(FoodConfirmationState.self, from: data)
        XCTAssertFalse(decoded.answersLabelFortification)
        state.answersLabelFortification = false
        XCTAssertEqual(decoded, state)
    }

    // MARK: 20. Opening unit

    func test20TheOpeningUnitIsServingsWhenTheLabelStatesAServing() throws {
        func unit(_ input: PopulatedFoodConfirmation) -> QuantityUnit {
            FoodConfirmationState(input: input, prefillSourceQuantity: false).quantity.unit
        }
        let size = PastedLabelManifest.Candidate.ServingSize(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g")
        let cases: [(String, PastedLabelManifest, QuantityUnit)] = [
            ("per 100 g with a serving (serving v1 table)", try F.manifest(answer: .no, corrections: []),
             PastedLabelServingPolicy.serving(try input(.no), candidate: try input(.no).candidates[0]) == nil ? .grams : .count),
            ("per 100 g, exact serving, parser v3", try F.per100Manifest(servingSize: size, parserVersion: PastedLabelSource.parserVersion), .count),
            ("per 100 g, no serving size", try F.per100Manifest(servingSize: nil), .grams),
            ("per 100 mL, no serving size", try F.per100Manifest(servingSize: nil, basis: "per_100ml"), .millilitres),
            ("per serving 30 g", try F.perServingManifest(readableServingSize: true), .count),
            ("per serving, no size", try F.perServingManifest(readableServingSize: false), .count)
        ]
        for (name, manifest, expected) in cases {
            let source = try F.input(manifest)
            XCTAssertEqual(unit(source), expected, name)
            XCTAssertNil(FoodConfirmationState(input: source, prefillSourceQuantity: false).quantity.value, "no amount chosen (\(name))")
        }
        XCTAssertEqual(unit(try QuickAddFixtures.exactInput(31_100)), FoodConfirmationState(
            input: try QuickAddFixtures.exactInput(31_100), prefillSourceQuantity: false).quantity.unit)
        XCTAssertNotEqual(unit(try QuickAddFixtures.exactInput(31_100)), .count, "a catalogue source never opens on servings")
    }
}
