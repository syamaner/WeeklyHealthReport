import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Contract tests for food_confirmation_v5 (#195): one Log action, typed requirements,
/// inline decisions, explicit occurred-at and edit-only mutations.
final class FoodLogPolicyContractTests: XCTestCase {
    // MARK: 1. Requirement mapping table

    func testEveryFormerRequirementMapsToExactlyOneTypedCaseAndTheServiceAgrees() throws {
        let now = LogFixture.date
        let calendar = LogFixture.london
        let scenarios: [(String, (inout FoodConfirmationState) -> Void, [FoodLogRequirement])] = [
            ("ready", { _ in }, []),
            ("amount missing", { $0.quantity.value = nil }, [.amountMissing]),
            ("amount text invalid", { FoodConfirmationReducer.reduce(state: &$0, action: .setQuantityText("abc")) }, [.amountTextInvalid]),
            ("count without conversion", { FoodConfirmationReducer.reduce(state: &$0, action: .setQuantity(2, .count)) }, [.countNeedsMeasuredAmount]),
            ("direct weight empty", { FoodConfirmationReducer.reduce(state: &$0, action: .beginDirectWeight) }, [.measuredWeightMissing, .weightBasisMissing]),
            ("retained weight", { $0.quantity.directWeight = DirectWeightDraft(totalGrams: 90, basis: .measured, needsReconfirmation: true) }, [.retainedWeightNeedsConfirmation]),
            ("plate missing", { FoodConfirmationReducer.reduce(state: &$0, action: .setPlateChoice(.missing)) }, [.emptyPlateWeightMissing]),
            ("plate needs grams", {
                FoodConfirmationReducer.reduce(state: &$0, action: .setQuantity(200, .millilitres))
                FoodConfirmationReducer.reduce(state: &$0, action: .setPlateChoice(.new(emptyWeight: try! PositiveQuantity(value: 50, unit: .grams), superseding: nil)))
            }, [.plateNeedsGramTotal]),
            ("plate heavier", {
                FoodConfirmationReducer.reduce(state: &$0, action: .setPlateChoice(.new(emptyWeight: try! PositiveQuantity(value: 300, unit: .grams), superseding: nil)))
            }, [.plateNotLighterThanTotal]),
            ("future time", { $0.occurredAt = now.addingTimeInterval(1) }, [.occurredAtInFuture]),
            ("too early", { $0.occurredAt = FoodLogPolicy.windowStart(now: now, calendar: calendar).addingTimeInterval(-1) }, [.occurredAtTooEarly])
        ]
        for (name, mutate, expected) in scenarios {
            var state = FoodConfirmationState(input: try LogFixture.input())
            mutate(&state)
            XCTAssertEqual(FoodLogPolicy.requirements(state, now: now, calendar: calendar), expected, name)
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let store = InMemoryFoodLedgerStore()
            let service = LogFixture.service(store: store, calendar: calendar)
            if expected.isEmpty {
                XCTAssertNoThrow(try service.save(state, operationID: LogFixture.id(300, OperationTag.self)), name)
            } else {
                XCTAssertThrowsError(try service.save(state, operationID: LogFixture.id(300, OperationTag.self)), name) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .unmetRequirements(expected), name)
                }
                XCTAssertEqual(try store.counts().operations, 0, name)
            }
        }
        let difference = FoodConfirmationState(input: try LogFixture.input(expected: LogFixture.identity(preparation: .raw)))
        XCTAssertEqual(FoodLogPolicy.requirements(difference, now: now, calendar: calendar), [.decideDifference(.preparation)])
        let unknown = FoodConfirmationState(input: try LogFixture.input(candidate: LogFixture.unknownIdentity, expected: LogFixture.unknownIdentity))
        XCTAssertEqual(FoodLogPolicy.requirements(unknown, now: now, calendar: calendar),
                       [.sourceIdentityMissing([.preparation, .bone, .skin, .drained, .packingMedium, .fortification])])
    }

    // MARK: 2. Bypasses kept exactly

    func testReopenedEntriesAndCorrectionsAreNotAskedAndCannotCarryDecisions() throws {
        let store = InMemoryFoodLedgerStore()
        let service = LogFixture.service(store: store)
        var state = FoodConfirmationState(input: try LogFixture.input(expected: LogFixture.identity(preparation: .raw)))
        XCTAssertEqual(FoodLogPolicy.pendingDifferences(state), [.preparation])
        FoodConfirmationReducer.reduce(state: &state, action: .decideDifference(.preparation, .differs("raw")))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LogFixture.id(310, OperationTag.self))

        var reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
        XCTAssertEqual(FoodLogPolicy.pendingDifferences(reopened), [])
        XCTAssertEqual(FoodLogPolicy.requirements(reopened, now: LogFixture.date, calendar: LogFixture.london), [])
        reopened.decisions[.preparation] = .notSure
        XCTAssertThrowsError(try service.save(reopened, operationID: LogFixture.id(311, OperationTag.self))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .staleDecisions)
        }

        var corrected = FoodConfirmationState(input: try LogFixture.input(expected: LogFixture.identity(preparation: .raw)))
        FoodConfirmationReducer.reduce(state: &corrected, action: .decideDifference(.preparation, .notSure))
        FoodConfirmationReducer.reduce(state: &corrected, action: .applyCorrection(try LogFixture.correction(corrected)))
        XCTAssertTrue(corrected.decisions.isEmpty, "A correction clears decisions")
        XCTAssertEqual(FoodLogPolicy.pendingDifferences(corrected), [])
        XCTAssertNoThrow(try LogFixture.service(store: InMemoryFoodLedgerStore()).save(corrected, operationID: LogFixture.id(312, OperationTag.self)))
        corrected.decisions[.preparation] = .notSure
        XCTAssertThrowsError(try LogFixture.service(store: InMemoryFoodLedgerStore()).save(corrected, operationID: LogFixture.id(313, OperationTag.self))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .staleDecisions)
        }
    }

    // MARK: 3. Refused direct saves

    func testServiceRefusesUndecidedStaleExtraOrInvalidDecisionsAndBadTimes() throws {
        let store = InMemoryFoodLedgerStore()
        let service = LogFixture.service(store: store)
        var undecided = FoodConfirmationState(input: try LogFixture.input(expected: LogFixture.identity(preparation: .raw)))
        FoodConfirmationReducer.reduce(state: &undecided, action: .accept)
        XCTAssertThrowsError(try service.save(undecided, operationID: LogFixture.id(320, OperationTag.self))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .unmetRequirements([.decideDifference(.preparation)]))
        }
        var extra = undecided
        extra.decisions = [.preparation: .notSure, .skin: .notSure]
        XCTAssertThrowsError(try service.save(extra, operationID: LogFixture.id(321, OperationTag.self))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .staleDecisions)
        }
        var equalToSource = undecided
        equalToSource.decisions = [.preparation: .differs("as_sold")]
        XCTAssertThrowsError(try service.save(equalToSource, operationID: LogFixture.id(322, OperationTag.self))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .staleDecisions)
        }
        var notOffered = undecided
        notOffered.decisions = [.preparation: .useSourceBasis]
        XCTAssertThrowsError(try service.save(notOffered, operationID: LogFixture.id(323, OperationTag.self)))
        // A decision answered for one candidate is cleared when another is selected.
        var switched = FoodConfirmationState(input: try LogFixture.input(candidateCount: 2, expected: LogFixture.identity(preparation: .raw)))
        FoodConfirmationReducer.reduce(state: &switched, action: .decideDifference(.preparation, .notSure))
        FoodConfirmationReducer.reduce(state: &switched, action: .selectCandidate(1))
        XCTAssertTrue(switched.decisions.isEmpty)
        var future = FoodConfirmationState(input: try LogFixture.input())
        future.occurredAt = LogFixture.date.addingTimeInterval(60)
        future.decision = .accepted
        XCTAssertThrowsError(try service.save(future, operationID: LogFixture.id(324, OperationTag.self))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .unmetRequirements([.occurredAtInFuture]))
        }
        XCTAssertEqual(try store.counts().operations, 0)
    }

    // MARK: 4. Golden assertion strings, exactly one assertion per save

    func testGoldenReasonAndClaimStringsAndOneAssertionPerSave() throws {
        func save(_ state: FoodConfirmationState, _ number: Int) throws -> (StoredFoodConfirmation, LedgerTransaction) {
            let store = V5RecordingStore()
            var accepted = state
            FoodConfirmationReducer.reduce(state: &accepted, action: .accept)
            let saved = try LogFixture.service(store: store).save(accepted, operationID: LogFixture.id(number, OperationTag.self))
            return (saved, try XCTUnwrap(store.transaction))
        }
        let plain = try save(FoodConfirmationState(input: try LogFixture.input()), 330)
        XCTAssertEqual(plain.1.mutation.assertions, [])
        XCTAssertEqual(plain.1.operation.operationType, .confirmFood)
        XCTAssertEqual(plain.0.resolutionVersion.methodVersion.value, "food_confirmation_v5")

        var exact = FoodConfirmationState(input: try LogFixture.input(expected: try LogFixture.identity(preparation: .raw, skin: .skinOn)))
        XCTAssertEqual(FoodLogPolicy.pendingDifferences(exact), [.preparation, .skin])
        FoodConfirmationReducer.reduce(state: &exact, action: .decideDifference(.preparation, .matchesSource))
        FoodConfirmationReducer.reduce(state: &exact, action: .decideDifference(.skin, .differs("skin_on")))
        let exactSaved = try save(exact, 331)
        XCTAssertEqual(exactSaved.1.mutation.assertions.count, 1)
        let exactAssertion = try XCTUnwrap(exactSaved.1.mutation.assertions.first)
        XCTAssertEqual(exactAssertion.reason.value, "Logged with inline decisions under food_confirmation_v5")
        XCTAssertEqual(exactAssertion.claim.value, "Logged under food_confirmation_v5; decisions: preparation: source as_sold, choice matches_source; skin: source not_applicable, choice differs:skin_on")
        XCTAssertEqual(exactAssertion.confirmation?.isEstimate, true)
        XCTAssertEqual(exactSaved.1.operation.operationType, .confirmFoodV3)

        let generic = try save(FoodConfirmationState(input: try LogFixture.input(kind: .genericSearch, generic: true)), 332)
        XCTAssertEqual(generic.1.mutation.assertions.count, 1)
        XCTAssertEqual(generic.1.mutation.assertions[0].reason.value, "Explicitly accepted generic composition estimate; unknown source details remain unknown")
        XCTAssertEqual(generic.1.mutation.assertions[0].claim.value, "Accepted estimate under food_confirmation_v5; not verified product identity")
        XCTAssertNil(generic.1.mutation.assertions[0].confirmation)
        XCTAssertEqual(generic.1.operation.operationType, .confirmFood)

        var genericDecided = FoodConfirmationState(input: try LogFixture.input(kind: .genericSearch, generic: true,
            candidate: LogFixture.unknownIdentity, expected: try LogFixture.identity(preparation: .unknown, bone: .unknown, skin: .skinOn, drained: .unknown, packing: .unknown, fortification: .unknown)))
        XCTAssertTrue(genericDecided.isGenericEstimate)
        XCTAssertEqual(FoodLogPolicy.pendingDifferences(genericDecided), [.skin])
        XCTAssertEqual(FoodLogPolicy.offeredChoices(genericDecided, facet: .skin), [.differs("skin_on"), .differs("skinless"), .notSure])
        FoodConfirmationReducer.reduce(state: &genericDecided, action: .decideDifference(.skin, .notSure))
        let genericSaved = try save(genericDecided, 333)
        XCTAssertEqual(genericSaved.1.mutation.assertions.count, 1)
        XCTAssertEqual(genericSaved.1.mutation.assertions[0].reason.value, "Explicitly accepted generic composition estimate; unknown source details remain unknown")
        XCTAssertEqual(genericSaved.1.mutation.assertions[0].claim.value, "Accepted estimate under food_confirmation_v5; not verified product identity; decisions: skin: source unknown, choice not_sure")

        var corrected = FoodConfirmationState(input: try LogFixture.input(expected: LogFixture.identity(preparation: .raw)))
        FoodConfirmationReducer.reduce(state: &corrected, action: .applyCorrection(try LogFixture.correction(corrected)))
        let correctedSaved = try save(corrected, 334)
        XCTAssertEqual(correctedSaved.1.mutation.assertions.count, 1)
        XCTAssertEqual(correctedSaved.1.mutation.assertions[0].reason.value, "Corrected fixture details")
        XCTAssertEqual(correctedSaved.1.mutation.assertions[0].claim.value, "Corrected populated confirmation for LogFixture food")
        XCTAssertNil(correctedSaved.1.mutation.assertions[0].confirmation)
    }

    // MARK: 5. Edit-only mutations

    func testQuantityAndTimeEditsWriteOnlyOneLogVersion() throws {
        let store = InMemoryFoodLedgerStore()
        let service = LogFixture.service(store: store)
        var state = FoodConfirmationState(input: try LogFixture.input(expected: LogFixture.identity(preparation: .raw)))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LogFixture.id(340, OperationTag.self))
        let before = try store.archiveState().records
        for (number, edit) in [(341, FoodConfirmationAction.setQuantity(150, .grams)), (342, .setOccurredAt(LogFixture.date.addingTimeInterval(-3600)))] {
            var reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &reopened, action: edit)
            let recording = V5RecordingStore(reading: store)
            let edited = try LogFixture.service(store: recording).save(reopened, operationID: LogFixture.id(number, OperationTag.self))
            let mutation = try XCTUnwrap(recording.transaction?.mutation)
            XCTAssertEqual(mutation.logItemVersions.count, 1)
            XCTAssertTrue(mutation.assertions.isEmpty && mutation.productVersions.isEmpty && mutation.candidateDecisions.isEmpty
                && mutation.resolutionVersions.isEmpty && mutation.resolutions.isEmpty && mutation.products.isEmpty
                && mutation.logItems.isEmpty && mutation.evidence.isEmpty && mutation.libraryEntries.isEmpty)
            XCTAssertEqual(edited.productVersion, saved.productVersion)
            XCTAssertEqual(edited.resolutionVersion, saved.resolutionVersion)
            XCTAssertEqual(edited.candidateDecision, saved.candidateDecision)
            XCTAssertEqual(edited.logItemVersion.correctionReason?.value,
                number == 341 ? "Confirmation quantity or plate correction" : "Confirmation time correction")
        }
        XCTAssertEqual(try store.archiveState().records.assertions, before.assertions)
    }

    // MARK: 12. When boundaries

    func testWhenWindowNowResolutionAndDaylightSavingAcrossZones() throws {
        for zone in ["Europe/London", "Pacific/Auckland"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            for (month, day) in [(3, 29), (10, 25)] {
                let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
                let start = FoodLogPolicy.windowStart(now: now, calendar: calendar)
                XCTAssertEqual(start, calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), zone)
                XCTAssertEqual(calendar.component(.hour, from: start), 0, zone)
                func requirement(_ date: Date) -> FoodLogRequirement? {
                    var state = FoodConfirmationState(input: try! LogFixture.input())
                    state.occurredAt = date
                    return FoodLogPolicy.timeRequirement(state, now: now, calendar: calendar)
                }
                XCTAssertNil(requirement(start), zone)
                XCTAssertNil(requirement(now), zone)
                XCTAssertEqual(requirement(start.addingTimeInterval(-1)), .occurredAtTooEarly, zone)
                XCTAssertEqual(requirement(now.addingTimeInterval(1)), .occurredAtInFuture, zone)

                // A backdated entry lands on the chosen local day, including the DST change day.
                for (offset, hour) in [(0, 1), (0, 2), (-1, 23), (-7, 0)] {
                    let chosenDay = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)))
                    let chosen = try XCTUnwrap(calendar.date(bySettingHour: hour, minute: 30, second: 0, of: chosenDay))
                    var state = FoodConfirmationState(input: try LogFixture.input())
                    FoodConfirmationReducer.reduce(state: &state, action: .setOccurredAt(chosen))
                    FoodConfirmationReducer.reduce(state: &state, action: .accept)
                    let service = LogFixture.service(store: InMemoryFoodLedgerStore(), calendar: calendar, now: now)
                    let saved = try service.save(state, operationID: LogFixture.id(400 + offset * 10 + hour + month * 100, OperationTag.self))
                    XCTAssertEqual(saved.logItemVersion.occurredAt, chosen, zone)
                    XCTAssertEqual(saved.logItemVersion.reportingDate.value, FoodReportingDay.key(for: chosen, calendar: calendar), zone)
                    XCTAssertEqual(saved.logItemVersion.reportingDate.value, FoodReportingDay.key(for: chosenDay, calendar: calendar), "\(zone) \(month)/\(day) \(offset) \(hour)")
                }
            }
        }
        // Both instants of London's repeated autumn hour map to the same day.
        var london = LogFixture.london
        london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let first = Date(timeIntervalSince1970: 1_792_888_200) // 2026-10-25T00:30:00Z, 01:30 BST
        let second = first.addingTimeInterval(3600) // 01:30 GMT
        XCTAssertEqual(FoodReportingDay.key(for: first, calendar: london), "2026-10-25")
        XCTAssertEqual(FoodReportingDay.key(for: second, calendar: london), "2026-10-25")
    }

    func testNowResolvesAtCommitAndUnchangedInstantKeepsStoredDayWithBuddhistDisplayCalendar() throws {
        var london = Calendar(identifier: .buddhist)
        london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = london.timeZone
        let opened = try XCTUnwrap(gregorian.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23, minute: 58)))
        let logged = try XCTUnwrap(gregorian.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 2)))
        let store = InMemoryFoodLedgerStore()
        var state = FoodConfirmationState(input: try LogFixture.input())
        XCTAssertNil(state.occurredAt, "A new entry starts as Now")
        XCTAssertEqual(FoodLogPolicy.requirements(state, now: opened, calendar: london), [])
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try LogFixture.service(store: store, calendar: london, now: logged).save(state, operationID: LogFixture.id(500, OperationTag.self))
        XCTAssertEqual(saved.logItemVersion.occurredAt, logged)
        XCTAssertEqual(saved.logItemVersion.reportingDate.value, "2026-10-25")

        // Reopened in another zone: an unchanged instant keeps the stored day; a changed one re-derives.
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let later = logged.addingTimeInterval(3600)
        let other = LogFixture.service(store: store, calendar: auckland, now: later)
        var quantity = try XCTUnwrap(other.reopen(logItemID: saved.logItem.logItemID))
        XCTAssertEqual(quantity.occurredAt, logged)
        FoodConfirmationReducer.reduce(state: &quantity, action: .setQuantity(120, .grams))
        let kept = try other.save(quantity, operationID: LogFixture.id(501, OperationTag.self))
        XCTAssertEqual(kept.logItemVersion.reportingDate.value, "2026-10-25")
        var moved = try XCTUnwrap(other.reopen(logItemID: saved.logItem.logItemID))
        FoodConfirmationReducer.reduce(state: &moved, action: .setOccurredAt(logged.addingTimeInterval(-60)))
        let rederived = try other.save(moved, operationID: LogFixture.id(502, OperationTag.self))
        XCTAssertEqual(rederived.logItemVersion.reportingDate.value, FoodReportingDay.key(for: logged.addingTimeInterval(-60), calendar: auckland))
        XCTAssertEqual(rederived.logItemVersion.reportingDate.value, "2026-10-25")
    }

    // MARK: 13. Time edit moves the head; removal and restoration keep the edited time

    func testTimeEditMovesTheHeadWithoutCompetingVersionsAndRemovalKeepsEditedTime() throws {
        let store = InMemoryFoodLedgerStore()
        let ids = V5SequenceIDs(seed: 700)
        let service = LogFixture.service(store: store, ids: ids)
        var state = FoodConfirmationState(input: try LogFixture.input())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LogFixture.id(600, OperationTag.self))
        let originalDay = saved.logItemVersion.reportingDate.value
        var edit = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
        let yesterday = LogFixture.date.addingTimeInterval(-86_400)
        FoodConfirmationReducer.reduce(state: &edit, action: .setOccurredAt(yesterday))
        let moved = try service.save(edit, operationID: LogFixture.id(601, OperationTag.self))
        let newDay = moved.logItemVersion.reportingDate.value
        XCTAssertNotEqual(newDay, originalDay)
        let records = try store.archiveState().records
        XCTAssertEqual(try FoodIntakeProjection(records: records, reportingDate: originalDay).rows.count, 0)
        XCTAssertEqual(try FoodIntakeProjection(records: records, reportingDate: newDay).rows.count, 1)

        let ledger = FoodLedgerService(actorID: try LogFixture.id(999, ActorTag.self), committer: store,
            clock: LogFixture.Clock(value: LogFixture.date), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let management = FoodLogManagementService(ledger: ledger,
            reader: ArchiveFoodLogHistoryReader(archive: store), clock: LogFixture.Clock(value: LogFixture.date), ids: ids)
        let removed = try management.remove(logItemID: moved.logItem.logItemID,
            expectedVersion: moved.logItemVersion.logItemVersionID, reason: LedgerText("Mistake"), operationID: LogFixture.id(602, OperationTag.self))
        XCTAssertEqual(removed.occurredAt, yesterday)
        let restored = try management.restore(logItemID: moved.logItem.logItemID,
            expectedVersion: removed.logItemVersionID, reason: LedgerText("Restore"), operationID: LogFixture.id(603, OperationTag.self))
        XCTAssertEqual(restored.occurredAt, yesterday)
        XCTAssertEqual(restored.reportingDate.value, newDay)
        XCTAssertEqual(try FoodIntakeProjection(records: store.archiveState().records, reportingDate: newDay).rows.count, 1)
    }
}

// MARK: - Fixtures

enum LogFixture {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    static var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    struct Clock: LedgerClock {
        let value: Date
        func now() -> Date { value }
    }

    static func id<Tag>(_ value: Int, _ tag: Tag.Type) throws -> LedgerID<Tag> {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }

    static func service(store: some LedgerCommandCommitting & LedgerReading & FoodConfirmationReading,
                        ids: V5SequenceIDs = V5SequenceIDs(), calendar: Calendar = london, now: Date = date) -> FoodConfirmationService {
        let clock = Clock(value: now)
        let ledger = FoodLedgerService(actorID: try! id(999, ActorTag.self), committer: store, clock: clock,
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        return FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids, digester: SHA256Digester(), calendar: calendar)
    }

    static func identity(preparation: PreparationKind = .asSold, bone: BoneState = .notApplicable, skin: SkinState = .notApplicable,
                         drained: DrainedState = .notApplicable, packing: PackingMediumState? = nil,
                         fortification: FortificationState = .unfortified) throws -> DecisiveIdentity {
        try DecisiveIdentity(preparation: PreparationState(kind: preparation), bone: bone, skin: skin, drained: drained,
            packingMedium: packing ?? .named(LedgerText("none")), fortification: fortification, servingBasis: .per100Grams)
    }

    static var unknownIdentity: DecisiveIdentity {
        try! identity(preparation: .unknown, bone: .unknown, skin: .unknown, drained: .unknown, packing: .unknown, fortification: .unknown)
    }

    static func correction(_ state: FoodConfirmationState) throws -> FoodCorrection {
        FoodCorrection(name: try LedgerText("Corrected fixture"), brand: nil, variant: nil,
            identity: state.selectedCandidate.candidate.identity, nutrients: state.selectedCandidate.candidate.nutrients,
            reason: try LedgerText("Corrected fixture details"))
    }

    static func input(candidateCount: Int = 1, kind: CaptureKind = .synthetic, generic: Bool = false,
                      candidate candidateIdentity: DecisiveIdentity? = nil, expected: DecisiveIdentity? = nil,
                      aliases: [String] = []) throws -> PopulatedFoodConfirmation {
        let evidenceID: EvidenceID = try id(1, EvidenceTag.self)
        let release = SourceRelease(
            sourceReleaseID: try ExternalIdentifier("synthetic:food-v1"), sourceID: try ExternalIdentifier("synthetic"),
            releasedAt: date, artifactHash: try SHA256Digest(String(repeating: "a", count: 64)),
            schemaVersion: try LedgerText("food-v1"), pipelineVersion: try LedgerText("fixture-v1"),
            licence: try LedgerText("fixture"), attribution: try LedgerText("fixture"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64)))
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: kind, capturedAt: date, locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic_route"), captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("populated evidence")))
        let identity = try candidateIdentity ?? Self.identity()
        let quantity = try PositiveQuantity(value: 100, unit: .grams)
        let candidates = try (0..<candidateCount).map { index in
            let recordID = try ExternalIdentifier("record:\(index + 1)")
            let provenance = NutrientProvenance(
                sourceKind: generic ? .genericCompositionDataset : .exactProductDataset,
                sourceID: release.sourceID, sourceReleaseID: release.sourceReleaseID, recordID: recordID,
                evidenceID: evidenceID, capturedAt: date)
            let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
                if key == .protein || key == .energyConsumed {
                    let amount: Double = key == .protein ? 10 : 165
                    let value = try ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                        sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                        provenance: [provenance])
                    return try NutrientEntry(key: key, value: generic ? .augmented(value) : .measured(value))
                }
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            })
            let metadata = aliases.isEmpty ? nil : try CandidateMatchMetadata(
                methodVersion: LedgerText("fixture-match-v1"), score: 1, materialDifferences: [],
                libraryAliases: aliases.map { try LedgerText($0) })
            return try PopulatedFoodCandidate(
                candidate: ProviderNeutralCandidate(sourceReleaseID: release.sourceReleaseID, recordID: recordID, identity: identity,
                    edibleQuantity: .known(quantity, conversionVersionID: nil), nutrients: nutrients, evidenceIDs: [evidenceID],
                    matchMetadata: metadata),
                name: LedgerText(index == 0 ? "LogFixture food" : "Alternate fixture food"), itemClass: .food)
        }
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: candidates,
            expectedIdentity: expected ?? identity, expectedEdibleQuantity: .known(quantity, conversionVersionID: nil))
    }
}

final class V5SequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value: Int
    private let lock = NSLock()
    init(seed: Int = 100) { value = seed }
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}

/// Captures the committed transaction; reads delegate to an optional backing store.
final class V5RecordingStore: LedgerCommandCommitting, LedgerReading, FoodConfirmationReading, @unchecked Sendable {
    var transaction: LedgerTransaction?
    private let reading: InMemoryFoodLedgerStore?
    init(reading: InMemoryFoodLedgerStore? = nil) { self.reading = reading }
    func actorHead(for actorID: ActorID) throws -> ActorHead { try reading?.actorHead(for: actorID) ?? ActorHead(sequence: 0, operationHash: nil) }
    func operation(id: OperationID) throws -> LedgerOperation? { try reading?.operation(id: id) }
    func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome {
        self.transaction = transaction
        return .committed(transaction.operation)
    }
    func counts() throws -> LedgerCounts { LedgerCounts(evidence: 0, productVersions: 0, resolutionVersions: 0, logItemVersions: 0, conflicts: 0, operations: 0) }
    func productVersions(productID: ProductID) throws -> [ProductVersion] { [] }
    func resolutionVersion(id: ResolutionVersionID) throws -> NutritionResolutionVersion? { nil }
    func exactLibraryEntries(alias: LedgerText) throws -> [LibraryEntryVersion] { [] }
    func barcodeLibraryRecords(alias: LedgerText) throws -> [BarcodeLibraryRecord] { [] }
    func conflicts() throws -> [LedgerConflict] { [] }
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { try reading?.sourceRelease(id: id) }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { try reading?.foodConfirmation(logItemID: logItemID) }
}
