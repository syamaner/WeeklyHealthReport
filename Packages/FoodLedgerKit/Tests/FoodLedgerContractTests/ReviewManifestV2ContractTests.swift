import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import XCTest

/// Contract tests 1 to 12 of docs/generic-food-review-manifest-v2.md section 7 (test 6 is
/// `ReviewedFoodProposalConfirmationTests` run for v1 and v2; test 13 lives with the view-model
/// fakes in FoodLedgerPresentationTests). Numbers in test names follow the document.
final class ReviewManifestV2ContractTests: XCTestCase {
    private let fractionalClock = FixedClock(value: Date(timeIntervalSince1970: 1_791_712_345.678_9))

    // MARK: 1. Literal v1 bytes from a real build

    func test01LiteralV1BytesRehashSaveReopenAndRecoverOnBothStores() throws {
        for (name, scope) in [("representative-serving", FoodProposalReviewScope.representativeEstimate), ("exact-per-100g", .exactProduct)] {
            let fixture = try ReviewedWebFixtures.v1Fixture(name)
            let text = try ReviewedWebFixtures.manifestText(fixture.input)
            XCTAssertEqual(Data(text.utf8), fixture.manifest, name)
            XCTAssertTrue(text.contains("\"reviewedAt\":1791712345678.9"), "Fractional milliseconds are part of the stored bytes")
            let hash = try SHA256Digester().sha256(fixture.manifest)
            XCTAssertEqual(hash, fixture.input.evidence[0].byteHash, name)
            XCTAssertEqual(hash, fixture.input.sourceReleases[0].manifestHash, name)
            XCTAssertEqual(fixture.input.sourceReleases[0].pipelineVersion.value,
                           "reviewed-web-proposal-v1:food-proposal-binding-v7:reviewed-web-admission-v5")
            guard case let .v1(manifest) = try XCTUnwrap(FoodProposalReviewManifestRecord.decode(fixture.manifest)) else {
                return XCTFail("Expected a v1 manifest")
            }
            // Test-only property: the frozen v1 struct re-encodes the stored bytes exactly.
            XCTAssertEqual(try FoundationCanonicalJSONEncoder().encode(manifest), fixture.manifest, name)
            XCTAssertEqual(FoodReviewedWebProposalPolicy.scope(fixture.input, candidate: fixture.input.candidates[0]), scope, name)
        }
        let fixture = try ReviewedWebFixtures.v1Fixture("representative-serving")
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            var state = FoodConfirmationState(input: fixture.input)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(1, .count))
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let key = try LedgerText("v1-fixture-retry")
            let service = try confirmationService(harness)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(1101), idempotencyKey: key)
            XCTAssertEqual(saved.evidence, fixture.input.evidence, harness.name)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.reviewedWebProposalScope, .representativeEstimate, harness.name)
            XCTAssertEqual(reopened.input.evidence, fixture.input.evidence, harness.name)
            let retried = try service.save(state, operationID: LedgerFixtures.operationID(1101), idempotencyKey: key)
            XCTAssertEqual(retried.logItem.logItemID, saved.logItem.logItemID, harness.name)
            XCTAssertEqual(try harness.reader.counts().operations, 1, harness.name)
        }
    }

    // MARK: 2. Golden v2 bytes

    func test02GoldenV2BytesPinKeysOrderMarketSuffixAndGateBlock() throws {
        let (review, proposal) = try ReviewedWebFixtures.review(query: "tofu pudding [market: United Kingdom]")
        let input = try confirmation(clock: fractionalClock).prepare(review: review, proposal: proposal,
            scope: .representativeEstimate, locale: LedgerText("en_GB"))
        let text = try ReviewedWebFixtures.manifestText(input)
        let encoder = FoundationCanonicalJSONEncoder()
        let candidate = String(decoding: try encoder.encode(proposal.candidate), as: UTF8.self)
        let document = String(decoding: try encoder.encode(proposal.document), as: UTF8.self)
        let golden = #"{"candidate":"# + candidate + #","document":"# + document
            + #","gate":{"choicePolicy":"food-proposal-review-choice-v3","rankingAvailable":true,"representativeSourceOnly":false,"selectionChoice":"c1"},"#
            + #""query":"tofu pudding [market: United Kingdom]","review":{"action":"use_this_source","presentation":"web-lookup-review-v1"},"#
            + #""reviewedAt":1791712345678.9,"scope":"representative_estimate","version":"reviewed-web-proposal-v2"}"#
        XCTAssertEqual(text, golden)
        XCTAssertEqual(input.evidence[0].captureMethodVersion.value, "reviewed-web-proposal-v2")
        XCTAssertEqual(input.sourceReleases[0].schemaVersion.value, "reviewed-web-proposal-v2:representative_estimate")
        XCTAssertEqual(input.sourceReleases[0].pipelineVersion.value,
                       "reviewed-web-proposal-v2:food-proposal-binding-v7:reviewed-web-admission-v6")
        guard case let .v2(manifest) = try XCTUnwrap(FoodProposalReviewManifestRecord.decode(Data(text.utf8))) else { return XCTFail("v2") }
        XCTAssertEqual(String(decoding: try encoder.encode(manifest), as: UTF8.self), text)
        XCTAssertEqual(FoodReviewedWebProposalPolicy.scope(input, candidate: input.candidates[0]), .representativeEstimate)
    }

    // MARK: 3. Cross-version rejection

    func test03CrossVersionRecordsAreRejected() throws {
        let v2 = try preparedV2(.representativeEstimate)
        let v1 = try ReviewedWebFixtures.v1Fixture("representative-serving").input
        XCTAssertNotNil(admitted(v2)); XCTAssertNotNil(admitted(v1))
        let text = try ReviewedWebFixtures.manifestText(v2)
        let v1Text = try ReviewedWebFixtures.manifestText(v1)
        let v2Pipeline = "reviewed-web-proposal-v2:food-proposal-binding-v7:reviewed-web-admission-v6"
        let cases: [(String, PopulatedFoodConfirmation)] = [
            ("captureMethodVersion", try ReviewedWebFixtures.rebind(v2, manifest: text, captureMethodVersion: "reviewed-web-proposal-v1")),
            ("schemaVersion", try ReviewedWebFixtures.rebind(v2, manifest: text, schemaVersion: "reviewed-web-proposal-v1:representative_estimate")),
            ("manifest version", try ReviewedWebFixtures.rewrite(v2, replacing: #""version":"reviewed-web-proposal-v2""#,
                                                                   with: #""version":"reviewed-web-proposal-v1""#)),
            ("unknown triple", try ReviewedWebFixtures.rebind(v2, manifest: text,
                pipelineVersion: "reviewed-web-proposal-v2:food-proposal-binding-v6:reviewed-web-admission-v6")),
            ("admission-v4 triple", try ReviewedWebFixtures.rebind(v1, manifest: v1Text,
                pipelineVersion: "reviewed-web-proposal-v1:food-proposal-binding-v7:reviewed-web-admission-v4")),
            ("v1 relabelled v2", try ReviewedWebFixtures.rebind(v1,
                manifest: v1Text.replacingOccurrences(of: #""version":"reviewed-web-proposal-v1""#, with: #""version":"reviewed-web-proposal-v2""#),
                schemaVersion: "reviewed-web-proposal-v2:representative_estimate", pipelineVersion: v2Pipeline,
                captureMethodVersion: "reviewed-web-proposal-v2")),
            ("v2 with acknowledgement", try ReviewedWebFixtures.rewrite(v2, replacing: #"{"candidate":"#,
                with: #"{"acknowledgement":{"basisReviewed":true,"identityAndScopeReviewed":true,"nutrientsAndUnknownsReviewed":true},"candidate":"#))
        ]
        for (name, input) in cases {
            XCTAssertNil(admitted(input), name)
            XCTAssertFalse(FoodReviewedWebProposalPolicy.manifestDigestIsValid(evidence: input.evidence, releases: input.sourceReleases,
                candidate: input.candidates[0].candidate, digester: SHA256Digester()) && admitted(input) != nil, name)
        }
    }

    // MARK: 4. Strict v2 decoding

    func test04StrictV2DecodingRejectsEachShape() throws {
        let text = try ReviewedWebFixtures.manifestText(try preparedV2(.representativeEstimate))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        XCTAssertNoThrow(try decoder.decode(FoodProposalReviewManifestV2.self, from: Data(text.utf8)))
        let gate = #""gate":{"choicePolicy":"food-proposal-review-choice-v3","rankingAvailable":true,"representativeSourceOnly":false,"selectionChoice":"c1"},"#
        let review = #""review":{"action":"use_this_source","presentation":"web-lookup-review-v1"},"#
        XCTAssertTrue(text.contains(gate) && text.contains(review))
        let mutations: [(String, String)] = [
            ("unknown key", text.replacingOccurrences(of: #""scope":"#, with: #""extra":1,"scope":"#)),
            ("missing review", text.replacingOccurrences(of: review, with: "")),
            ("missing gate", text.replacingOccurrences(of: gate, with: "")),
            ("unknown key in review", text.replacingOccurrences(of: #""presentation":"web-lookup-review-v1"}"#,
                                                                 with: #""presentation":"web-lookup-review-v1","extra":true}"#)),
            ("unknown key in gate", text.replacingOccurrences(of: #""selectionChoice":"c1"}"#, with: #""selectionChoice":"c1","extra":true}"#)),
            ("missing key in gate", text.replacingOccurrences(of: #""representativeSourceOnly":false,"#, with: "")),
            ("unknown action", text.replacingOccurrences(of: "use_this_source", with: "accept_everything")),
            ("unknown presentation", text.replacingOccurrences(of: "web-lookup-review-v1", with: "web-lookup-review-v2")),
            ("unknown policy", text.replacingOccurrences(of: "food-proposal-review-choice-v3", with: "food-proposal-review-choice-v9")),
            ("empty choice", text.replacingOccurrences(of: #""selectionChoice":"c1""#, with: #""selectionChoice":"""#))
        ]
        for (name, mutated) in mutations {
            XCTAssertNotEqual(mutated, text, name)
            XCTAssertThrowsError(try decoder.decode(FoodProposalReviewManifestV2.self, from: Data(mutated.utf8)), name)
            XCTAssertNil(FoodProposalReviewManifestRecord.decode(Data(mutated.utf8)), name)
        }
    }

    // MARK: 5. Gate at preparation and from the record

    func test05GateRefusesPreparationForEveryBlockingOutcome() throws {
        let other = try ReviewedWebFixtures.review(serving: false).1
        let cases: [(String, GenericFoodProposalReview, BoundFoodProposal, FoodProposalReviewScope)] = [
            try ("none", ReviewedWebFixtures.review(choice: "none").0, ReviewedWebFixtures.review().1, .representativeEstimate),
            try ("clarify", ReviewedWebFixtures.review(choice: "clarify").0, ReviewedWebFixtures.review().1, .representativeEstimate),
            try ("rejected or foreign ID", ReviewedWebFixtures.review().0, other, .representativeEstimate),
            try nonPreferred(),
            try ("ranking unavailable", ReviewedWebFixtures.review(rankingUnavailable: true).0, ReviewedWebFixtures.review().1, .representativeEstimate),
            try ("no selection", ReviewedWebFixtures.review(choice: nil).0, ReviewedWebFixtures.review().1, .representativeEstimate),
            try ("basis conflict", ReviewedWebFixtures.review(query: "tofu pudding per 100 ml").0, ReviewedWebFixtures.review().1, .representativeEstimate),
            try ("representative-only exact", ReviewedWebFixtures.review(representativeOnly: true).0, ReviewedWebFixtures.review().1, .exactProduct)
        ]
        for (name, review, proposal, scope) in cases {
            XCTAssertThrowsError(try confirmation().prepare(review: review, proposal: proposal, scope: scope, locale: LedgerText("en_GB")), name) {
                XCTAssertEqual($0 as? GenericFoodProposalError, .invalidSelection, name)
            }
        }
        let (review, proposal) = try ReviewedWebFixtures.review()
        XCTAssertNoThrow(try confirmation().prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("en_GB")))
        let (restricted, restrictedProposal) = try ReviewedWebFixtures.review(representativeOnly: true)
        XCTAssertNoThrow(try confirmation().prepare(review: restricted, proposal: restrictedProposal, scope: .representativeEstimate, locale: LedgerText("en_GB")))
    }

    func test05RecordedGateIsRecheckedAtSaveAndReopen() throws {
        let representative = try preparedV2(.representativeEstimate)
        let exact = try preparedV2(.exactProduct, serving: false)
        let records: [(String, PopulatedFoodConfirmation)] = [
            ("ranking unavailable", try ReviewedWebFixtures.rewrite(representative, replacing: #""rankingAvailable":true"#, with: #""rankingAvailable":false"#)),
            ("choice not the candidate", try ReviewedWebFixtures.rewrite(representative, replacing: #""selectionChoice":"c1""#, with: #""selectionChoice":"c2""#)),
            ("none", try ReviewedWebFixtures.rewrite(representative, replacing: #""selectionChoice":"c1""#, with: #""selectionChoice":"none""#)),
            ("clarify", try ReviewedWebFixtures.rewrite(representative, replacing: #""selectionChoice":"c1""#, with: #""selectionChoice":"clarify""#)),
            ("representative-only exact", try ReviewedWebFixtures.rewrite(exact, replacing: #""representativeSourceOnly":false"#, with: #""representativeSourceOnly":true"#))
        ]
        for (name, input) in records {
            XCTAssertTrue(FoodReviewedWebProposalPolicy.manifestDigestIsValid(evidence: input.evidence, releases: input.sourceReleases,
                candidate: input.candidates[0].candidate, digester: SHA256Digester()), "Digest must stay valid: \(name)")
            XCTAssertNil(admitted(input), name)
        }
        // A control rewrite of an unchecked field stays admissible, so the gate alone rejects above.
        XCTAssertNotNil(admitted(try ReviewedWebFixtures.rewrite(representative, replacing: #""query":"tofu pudding""#, with: #""query":"tofu puddings""#)))

        let tampered = records[0].1
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            var state = FoodConfirmationState(input: tampered)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(1, .count))
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
            XCTAssertThrowsError(try confirmationService(harness).save(state, operationID: LedgerFixtures.operationID(1150))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidReviewedSource, harness.name)
            }
            XCTAssertEqual(try harness.reader.counts().operations, 0, harness.name)

            let saved = try saveRepresentative(representative, harness, operation: 1151)
            for (fragment, replacement, admissible) in [(#""rankingAvailable":true"#, #""rankingAvailable":false"#, false),
                                                        (#""query":"tofu pudding""#, #""query":"tofu puddings""#, true)] {
                let altered = try rewriteStored(saved, replacing: fragment, with: replacement)
                let service = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer),
                    reader: StoredReader(saved: altered), clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
                if admissible {
                    XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID), "control \(harness.name)")
                } else {
                    XCTAssertThrowsError(try service.reopen(logItemID: saved.logItem.logItemID), harness.name) {
                        guard case FoodLedgerStoreError.integrityFailure = $0 else { return XCTFail("Expected integrity failure") }
                    }
                }
            }
        }
    }

    // MARK: 7. v5 composition

    func test07V2ComposesWithConfirmationV5() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try confirmationService(harness)
            let saved = try saveRepresentative(try preparedV2(.representativeEstimate), harness, operation: 1170)
            XCTAssertEqual(saved.resolutionVersion.methodVersion.value, "food_confirmation_v5")
            XCTAssertEqual(saved.assertions.count, 1, harness.name)
            XCTAssertEqual(saved.assertions.first?.reason.value, "Explicitly accepted generic composition estimate; unknown source details remain unknown")
            XCTAssertTrue(try service.isEstimate(saved), harness.name)

            let exact = try preparedV2(.exactProduct, serving: false)
            var state = FoodConfirmationState(input: exact, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(150, .grams))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(1171))) {
                guard case let FoodConfirmationSaveError.unmetRequirements(unmet) = $0,
                      unmet.contains(where: { if case .sourceIdentityMissing = $0 { true } else { false } }) else {
                    return XCTFail("Expected identity blocker, got \($0)")
                }
            }
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try correction(exact.candidates[0])))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let corrected = try service.save(state, operationID: LedgerFixtures.operationID(1172))
            XCTAssertEqual(corrected.resolutionVersion.methodVersion.value, "food_confirmation_v5")
            XCTAssertEqual(corrected.assertions.count, 1, "The correction assertion only")
            XCTAssertFalse(try service.isEstimate(corrected))
        }
    }

    // MARK: 8. Admission and storage

    func test08ContractFiveSchemaFiveAndDailyPinBoundaries() throws {
        // Contracts 6 (favourites, #198) and 7 (pasted label, #93) followed; contract 5 conditions are unchanged.
        XCTAssertEqual(CanonicalFoodProjection.foodContractVersion, 7)
        XCTAssertEqual(FoodLedgerGRDBStore.schemaVersion, 7)
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            _ = try saveRepresentative(try ReviewedWebFixtures.v1Fixture("representative-serving").input, harness, operation: 1180)
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            XCTAssertLessThanOrEqual(CanonicalFoodProjection.minimumContractVersion(for: try archive.archiveState().records), 4, harness.name)
            _ = try saveRepresentative(try preparedV2(.representativeEstimate), harness, operation: 1181)
            let records = try archive.archiveState().records
            XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: records), 5, harness.name)
            XCTAssertThrowsError(try CanonicalFoodProjection(records: records, foodContractVersion: 4)) {
                XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(4))
            }
            let bundle = try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("manifest-v2"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.manifest.foodContractVersion, 6, harness.name)
            XCTAssertEqual(verified.manifest.migrationIdentifiers.map(\.value).last, "food-ledger-v6", harness.name)
            XCTAssertFalse((1...4).contains(verified.manifest.foodContractVersion), "A contract-4 build admits 1...4 only")
        }
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: try LedgerFixtures.baseMutation()), 1)
    }

    // MARK: 9. Re-log reuses evidence

    func test09RelogReusesV1AndV2EvidenceWithoutDuplicatesOnBothStores() throws {
        for (version, input) in [("v1", try ReviewedWebFixtures.v1Fixture("representative-serving").input),
                                 ("v2", try preparedV2(.representativeEstimate))] {
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }
                let service = try confirmationService(harness)
                let saved = try saveRepresentative(input, harness, operation: 1190)
                let before = try harness.reader.counts()
                var state = try XCTUnwrap(service.relogState(logItemID: saved.logItem.logItemID))
                XCTAssertEqual(try harness.reader.counts(), before, "Building a re-log never saves")
                state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
                let relogged = try service.save(state, operationID: LedgerFixtures.operationID(1191))
                XCTAssertNotEqual(relogged.logItem.logItemID, saved.logItem.logItemID)
                let after = try harness.reader.counts()
                XCTAssertEqual(after.evidence, before.evidence, "\(version) \(harness.name)")
                XCTAssertEqual(after.operations, before.operations + 1)
                let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
                let records = try archive.archiveState().records
                XCTAssertEqual(records.sourceReleases.filter { $0.sourceID.value == "reviewed-web-proposal" }.count, 1, "\(version) \(harness.name)")
                XCTAssertEqual(records.evidence.filter { $0.captureMethodVersion.value.hasPrefix("reviewed-web-proposal") }.count, 1)
                if version == "v1" { XCTAssertLessThanOrEqual(CanonicalFoodProjection.minimumContractVersion(for: records), 4) }
                let reopened = try XCTUnwrap(service.reopen(logItemID: relogged.logItem.logItemID))
                XCTAssertEqual(reopened.reviewedWebProposalScope, .representativeEstimate)
            }
        }
    }

    // MARK: 10. Re-log builder

    func test10RelogCarriesNoCorrectionDecisionsOrEdibleQuantity() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try confirmationService(harness)
            let exact = try preparedV2(.exactProduct, serving: false)
            var state = FoodConfirmationState(input: exact, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(try correction(exact.candidates[0])))
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(150, .grams))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(1200))
            let before = try harness.reader.counts()
            let relog = try XCTUnwrap(service.relogState(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(try harness.reader.counts(), before, "A tap never saves")
            XCTAssertNil(relog.reopened); XCTAssertNil(relog.correction); XCTAssertTrue(relog.decisions.isEmpty)
            XCTAssertEqual(relog.decision, .undecided)
            XCTAssertNil(relog.occurredAt)
            XCTAssertEqual(relog.quantity, FoodQuantityDraft(value: 150, unit: .grams))
            XCTAssertEqual(relog.input.expectedEdibleQuantity, .unknown)
            XCTAssertEqual(relog.input.expectedIdentity, exact.candidates[0].candidate.identity)
            XCTAssertNotEqual(relog.input.expectedIdentity, saved.productVersion.identity)
            XCTAssertTrue(FoodLogPolicy.requirements(relog, now: LedgerFixtures.date, calendar: .current).contains {
                if case .sourceIdentityMissing = $0 { true } else { false }
            })
            var unaccepted = relog; FoodConfirmationReducer.reduce(state: &unaccepted, action: .accept)
            XCTAssertThrowsError(try service.save(unaccepted, operationID: LedgerFixtures.operationID(1201)))

            // An unrestorable manifest is omitted from recent foods, never shown with partial data.
            let altered = try rewriteStored(saved, replacing: #""rankingAvailable":true"#, with: #""rankingAvailable":false"#)
            let reader = StoredReader(saved: altered)
            let alteredService = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer),
                reader: reader, clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
            XCTAssertThrowsError(try alteredService.relogInput(altered))
            let records = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess).archiveState().records
            XCTAssertEqual(FoodRecentItemsProjection.items(records: records, now: LedgerFixtures.date, calendar: .current).count, 1)
            XCTAssertTrue(FoodRecentItemsService(reader: reader, confirmations: alteredService)
                .items(records: records, now: LedgerFixtures.date, calendar: .current).isEmpty)
            XCTAssertEqual(FoodRecentItemsService(reader: harness.reader, confirmations: service)
                .items(records: records, now: LedgerFixtures.date, calendar: .current).map(\.name), ["豆花"])
        }
    }

    // MARK: 11. Recent projection

    func test11RecentProjectionHeadsDeduplicationOrderWindowAndLimit() throws {
        var london = Calendar(identifier: .gregorian); london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        func instant(_ text: String) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: text)) }
        let now = try instant("2026-10-27T12:00:00Z")
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let ledger = try LedgerFixtures.service(harness.committer)
            let current = FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: FixedClock(value: now),
                ids: RandomLedgerIDGenerator(), digester: SHA256Digester(), calendar: london)
            let earlier = FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: FixedClock(value: try instant("2026-09-25T12:00:00Z")),
                ids: RandomLedgerIDGenerator(), digester: SHA256Digester(), calendar: london)
            func log(_ service: FoodConfirmationService, food: Int, at: String, grams: Double, op: Int) throws -> StoredFoodConfirmation {
                var state = FoodConfirmationState(input: try syntheticInput(food, evidence: op))
                FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(grams, .grams))
                state.occurredAt = try instant(at)
                state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
                return try service.save(state, operationID: LedgerFixtures.operationID(op))
            }
            _ = try log(earlier, food: 1, at: "2026-09-24T09:00:00Z", grams: 10, op: 1300)            // outside 30 days
            _ = try log(current, food: 2, at: "2026-10-24T23:30:00Z", grams: 20, op: 1301)            // 00:30 BST, DST day
            let older = try log(current, food: 3, at: "2026-10-25T01:30:00Z", grams: 30, op: 1302)    // 01:30 GMT after fall-back
            let newer = try log(current, food: 3, at: "2026-10-26T23:59:00Z", grams: 35, op: 1303)    // same record, later
            let removed = try log(current, food: 4, at: "2026-10-27T00:01:00Z", grams: 40, op: 1304)  // just after midnight
            let restored = try log(current, food: 5, at: "2026-10-26T08:00:00Z", grams: 50, op: 1305)
            let edited = try log(current, food: 6, at: "2026-10-26T07:00:00Z", grams: 60, op: 1306)
            let management = FoodLogManagementService(ledger: ledger,
                reader: ArchiveFoodLogHistoryReader(archive: try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)),
                clock: FixedClock(value: now), ids: RandomLedgerIDGenerator())
            try management.remove(logItemID: removed.logItem.logItemID, expectedVersion: removed.logItemVersion.logItemVersionID,
                                  reason: LedgerText("synthetic removal"), operationID: LedgerFixtures.operationID(1307))
            let gone = try management.remove(logItemID: restored.logItem.logItemID, expectedVersion: restored.logItemVersion.logItemVersionID,
                                             reason: LedgerText("synthetic removal"), operationID: LedgerFixtures.operationID(1308))
            try management.restore(logItemID: restored.logItem.logItemID, expectedVersion: gone.logItemVersionID,
                                   reason: LedgerText("synthetic restore"), operationID: LedgerFixtures.operationID(1309))
            var reopened = try XCTUnwrap(current.reopen(logItemID: edited.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &reopened, action: .setQuantity(65, .grams))
            _ = try current.save(reopened, operationID: LedgerFixtures.operationID(1310))
            // A true estimate: a representative reviewed web source logged now.
            var web = FoodConfirmationState(input: try preparedV2(.representativeEstimate))
            FoodConfirmationReducer.reduce(state: &web, action: .setQuantity(1, .count))
            web.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &web, action: .accept)
            let webSaved = try current.save(web, operationID: LedgerFixtures.operationID(1311))

            let records = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess).archiveState().records
            let items = FoodRecentItemsProjection.items(records: records, now: now, calendar: london)
            XCTAssertEqual(items.map(\.recordID.value), ["https://example.com/tofu#proposal=c1", "fixture:row-3", "fixture:row-5", "fixture:row-6", "fixture:row-2"], harness.name)
            XCTAssertEqual(items[0].logItemID, webSaved.logItem.logItemID)
            XCTAssertEqual(items[1].logItemID, newer.logItem.logItemID, "The most recent use of a record wins")
            XCTAssertNotEqual(items[1].logItemID, older.logItem.logItemID)
            XCTAssertEqual(items.map(\.lastAmount.value), [1, 35, 50, 65, 20], "Superseded versions are replaced by the head")
            XCTAssertEqual(items[0].energyKcal, 150, "One source serving of 150 kcal")
            XCTAssertNil(items[1].energyKcal, "Synthetic food declares no energy")
            XCTAssertEqual(FoodRecentItemsProjection.items(records: records, now: now, calendar: london, limit: 2).count, 2)
            // Window: one day back from local midnight of 27 October excludes the DST-day entry.
            let oneDay = FoodRecentItemsProjection.items(records: records, now: now, calendar: london, windowDays: 1)
            XCTAssertEqual(Set(oneDay.map(\.recordID.value)), ["https://example.com/tofu#proposal=c1", "fixture:row-3", "fixture:row-5", "fixture:row-6"])
            let twoDays = FoodRecentItemsProjection.items(records: records, now: now, calendar: london, windowDays: 2)
            XCTAssertTrue(twoDays.contains { $0.recordID.value == "fixture:row-2" }, "00:30 BST on 25 October is inside two local days")
            let estimates = FoodRecentItemsService(reader: harness.reader, confirmations: current).items(records: records, now: now, calendar: london)
            XCTAssertEqual(estimates.map(\.isEstimate), [true, false, false, false, false], "Estimate status survives the projection")
            XCTAssertEqual(estimates.first?.name, "豆花")
        }
    }

    // MARK: 12. Energy for the amount

    func test12EnergyForTheAmountOnlyForMatchingBases() throws {
        let per100g = try preparedV2(.representativeEstimate, serving: false).candidates[0].candidate
        let nutrients = per100g.nutrients
        typealias Q = ParsedFoodQuery.Quantity
        XCTAssertEqual(FoodSearchResultSummary.energy(nutrients: nutrients, basis: .per100Grams, amount: Q(value: 150, unit: "g")),
                       .forAmount(kcal: 225, quantity: try PositiveQuantity(value: 150, unit: .grams)))
        XCTAssertEqual(FoodSearchResultSummary.energy(nutrients: nutrients, basis: .per100Grams, amount: Q(value: 101, unit: "g")),
                       .forAmount(kcal: 152, quantity: try PositiveQuantity(value: 101, unit: .grams)), "151.5 rounds half away from zero")
        XCTAssertEqual(FoodSearchResultSummary.energy(nutrients: nutrients, basis: .per100Grams, amount: Q(value: 0.3, unit: "g")),
                       .forAmount(kcal: 0, quantity: try PositiveQuantity(value: 0.3, unit: .grams)))
        for unit in ["ml", "mL"] {
            XCTAssertEqual(FoodSearchResultSummary.energy(nutrients: nutrients, basis: .per100Millilitres, amount: Q(value: 200, unit: unit)),
                           .forAmount(kcal: 300, quantity: try PositiveQuantity(value: 200, unit: .millilitres)))
        }
        let named = ResolutionBasis.named(try LedgerText("bowl"), try PositiveQuantity(value: 1, unit: .count))
        let unknownEnergy = try NutrientSet(entries: nutrients.entries.map {
            $0.key == .energyConsumed ? try NutrientEntry(key: .energyConsumed, value: .unknown(.notDeclared)) : $0
        })
        let basisOnly: [(String, NutrientSet, ResolutionBasis, Q?)] = [
            ("oz", nutrients, .per100Grams, Q(value: 5, unit: "oz")),
            ("count", nutrients, .per100Grams, Q(value: 2, unit: "count")),
            ("named serving", nutrients, named, Q(value: 1, unit: "count")),
            ("unknown energy", unknownEnergy, .per100Grams, Q(value: 150, unit: "g")),
            ("mL against per 100 g", nutrients, .per100Grams, Q(value: 150, unit: "ml")),
            ("g against per 100 mL", nutrients, .per100Millilitres, Q(value: 150, unit: "g")),
            ("no amount", nutrients, .per100Grams, nil)
        ]
        for (name, set, basis, amount) in basisOnly {
            XCTAssertEqual(FoodSearchResultSummary.energy(nutrients: set, basis: basis, amount: amount), .basisOnly(basis), name)
        }
        // #308: the stated per 100 g / per 100 mL energy for a row without an amount; unknown is nil, never 0.
        XCTAssertEqual(FoodSearchResultSummary.basisEnergy(nutrients: nutrients, basis: .per100Grams), 150)
        XCTAssertEqual(FoodSearchResultSummary.basisEnergy(nutrients: nutrients, basis: .per100Millilitres), 150)
        XCTAssertNil(FoodSearchResultSummary.basisEnergy(nutrients: nutrients, basis: named))
        XCTAssertNil(FoodSearchResultSummary.basisEnergy(nutrients: nutrients, basis: .unknown))
        XCTAssertNil(FoodSearchResultSummary.basisEnergy(nutrients: unknownEnergy, basis: .per100Grams))
    }

    // MARK: Presentation contract web-lookup-review-v1 (pinned by golden output, never recomputed at admission)

    func testWebLookupReviewContentGoldenForServingAndPer100GramPanels() throws {
        for (serving, basis, quote) in [(true, "每份一碗", "豆花 每份一碗 熱量150大卡 蛋白質6公克"), (false, "每100g", "豆花 每100g 熱量150大卡 蛋白質6公克")] {
            let (_, proposal) = try ReviewedWebFixtures.review(serving: serving)
            let content = FoodWebLookupReviewContent(document: proposal.document, candidate: proposal.candidate, scope: .representativeEstimate)
            XCTAssertEqual(FoodWebLookupReviewContent.presentation, "web-lookup-review-v1")
            XCTAssertEqual(content.name, "豆花"); XCTAssertNil(content.brand)
            XCTAssertEqual(content.sourceHost, "example.com")
            XCTAssertEqual(content.basisLabel, basis)
            XCTAssertEqual(content.declared, [.init(key: .energy, value: "150", unit: "kcal"), .init(key: .protein, value: "6", unit: "g")])
            XCTAssertEqual(content.notStated, [.carbohydrate, .fat, .fibre, .sodium])
            XCTAssertEqual(content.quotes, [quote])
            XCTAssertEqual(content.limitations, [])
            XCTAssertEqual(content.notUsable, [])
        }
        // A key present on the page but unreadable is "not usable", not "not stated".
        let (_, proposal) = try ReviewedWebFixtures.review(serving: false)
        let encoded = String(decoding: try LedgerFixtures.encoder.encode(proposal.candidate), as: UTF8.self)
        let fat = #"{"evidence":[],"key":"fat","state":"unknown","unknownReason":"not_observed"}"#
        XCTAssertTrue(encoded.contains(fat))
        let unreadable = try JSONDecoder().decode(FoodProposalCandidate.self, from: Data(encoded.replacingOccurrences(of: fat,
            with: #"{"evidence":[],"key":"fat","state":"unknown","unknownReason":"unreadable"}"#).utf8))
        let content = FoodWebLookupReviewContent(document: proposal.document, candidate: unreadable, scope: nil)
        XCTAssertEqual(content.notUsable, [.fat])
        XCTAssertEqual(content.notStated, [.carbohydrate, .fibre, .sodium])
    }

    // MARK: Helpers

    private func confirmation(clock: any LedgerClock = LedgerFixtures.clock) -> ReviewedFoodProposalConfirmation {
        ReviewedFoodProposalConfirmation(ids: RandomLedgerIDGenerator(), clock: clock,
            encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
    }
    private func preparedV2(_ scope: FoodProposalReviewScope, serving: Bool = true) throws -> PopulatedFoodConfirmation {
        let (review, proposal) = try ReviewedWebFixtures.review(serving: serving)
        return try confirmation().prepare(review: review, proposal: proposal, scope: scope, locale: LedgerText("zh_TW"))
    }
    private func nonPreferred() throws -> (String, GenericFoodProposalReview, BoundFoodProposal, FoodProposalReviewScope) {
        let (review, _) = try ReviewedWebFixtures.review(second: true)
        let alternative = try XCTUnwrap(review.validation.candidates.first { $0.id == "c2" && $0.selectionEligible })
        return ("non-preferred alternative", review, alternative, .representativeEstimate)
    }
    private func admitted(_ input: PopulatedFoodConfirmation) -> FoodProposalReviewScope? {
        FoodReviewedWebProposalPolicy.scope(input, candidate: input.candidates[0])
    }
    private func confirmationService(_ harness: TestHarness) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: harness.reader,
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
    }
    private func saveRepresentative(_ input: PopulatedFoodConfirmation, _ harness: TestHarness, operation: Int) throws -> StoredFoodConfirmation {
        var state = FoodConfirmationState(input: input)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(1, .count))
        state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return try confirmationService(harness).save(state, operationID: LedgerFixtures.operationID(operation))
    }
    private func correction(_ candidate: PopulatedFoodCandidate) throws -> FoodCorrection {
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable,
            skin: .notApplicable, drained: .notApplicable, packingMedium: .named(LedgerText("none")),
            fortification: .unfortified, servingBasis: candidate.candidate.identity.servingBasis)
        return try FoodCorrection(name: candidate.name, brand: candidate.brand, variant: candidate.variant,
            identity: identity, itemClass: .food, nutrients: candidate.candidate.nutrients,
            reason: LedgerText("Synthetic inspection resolved the product identity; source nutrients are unchanged."))
    }
    /// Rewrite the retained manifest of a saved entry and rebind every digest-derived identifier.
    private func rewriteStored(_ saved: StoredFoodConfirmation, replacing: String, with replacement: String) throws -> StoredFoodConfirmation {
        guard case let .text(payload) = saved.evidence[0].originalPayload else { throw GenericFoodProposalError.invalidDocument }
        let oldHash = try XCTUnwrap(saved.evidence[0].byteHash).value
        let newText = payload.value.replacingOccurrences(of: replacing, with: replacement)
        XCTAssertNotEqual(newText, payload.value)
        let newHash = try SHA256Digester().sha256(Data(newText.utf8)).value
        var json = String(decoding: try LedgerFixtures.encoder.encode(saved), as: UTF8.self)
        func escaped(_ value: String) throws -> String {
            let quoted = String(decoding: try LedgerFixtures.encoder.encode([value]), as: UTF8.self)
            return String(quoted.dropFirst(2).dropLast(2))
        }
        let from = try escaped(replacing), to = try escaped(replacement)
        XCTAssertTrue(json.contains(from))
        json = json.replacingOccurrences(of: from, with: to).replacingOccurrences(of: oldHash, with: newHash)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(StoredFoodConfirmation.self, from: Data(json.utf8))
    }
    private func syntheticInput(_ number: Int, evidence evidenceNumber: Int) throws -> PopulatedFoodConfirmation {
        let evidenceID: EvidenceID = try LedgerFixtures.id(7_000 + evidenceNumber, EvidenceTag.self)
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .synthetic, capturedAt: LedgerFixtures.date,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic_fixture"), captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("recent fixture \(number) evidence \(evidenceNumber)")))
        let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: try ExternalIdentifier("physical_package"),
            sourceReleaseID: try ExternalIdentifier("package:fixture-v1"), evidenceID: evidenceID, capturedAt: LedgerFixtures.date)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard key == .protein else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: 10, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: 10, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [provenance])))
        })
        let identity = try LedgerFixtures.identity()
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(sourceReleaseID: try ExternalIdentifier("package:fixture-v1"),
                recordID: try ExternalIdentifier("fixture:row-\(number)"), identity: identity,
                edibleQuantity: .known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
                nutrients: nutrients, evidenceIDs: [evidenceID]),
            name: try LedgerText("Fixture food \(number)"), itemClass: .food)
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [try LedgerFixtures.packageSourceRelease()],
            candidates: [candidate], expectedIdentity: identity,
            expectedEdibleQuantity: .known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil))
    }
}

private struct StoredReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { saved.sourceReleases.first { $0.sourceReleaseID == id } }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { logItemID == saved.logItem.logItemID ? saved : nil }
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        logItemVersionID == saved.logItemVersion.logItemVersionID ? saved : nil
    }
    func evidence(id: EvidenceID) throws -> CaptureEvidence? { saved.evidence.first { $0.evidenceID == id } }
}
