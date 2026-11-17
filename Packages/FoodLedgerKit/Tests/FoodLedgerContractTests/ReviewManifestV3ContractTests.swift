import Foundation
import FoodGenericSearch
@_spi(ReviewedWebRegression) import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import XCTest

/// Phase 1 of docs/web-lookup-part-read-pages-v1-proposal.md (#508): the larger page bounds,
/// the closed bounds of stored v1 and v2 manifests, and the complete stored format and admission
/// of manifest v3 (contract section 8.4, gate docs/web-lookup-larger-pages-phase1-gate.md section 5).
final class ReviewManifestV3ContractTests: XCTestCase {
    private let fractionalClock = FixedClock(value: Date(timeIntervalSince1970: 1_791_712_345.678_9))
    private let encoder = FoundationCanonicalJSONEncoder()
    private let line1 = "豆花 每份一碗 熱量150大卡 蛋白質6公克"
    private let line2 = "豆花 每份一碗 熱量250大卡 蛋白質6公克"

    // MARK: Versions and triples

    func testVersionsTriplesAndPoliciesArePinned() {
        XCTAssertEqual(ReviewedFoodProposalConfirmation.version1, "reviewed-web-proposal-v1")
        XCTAssertEqual(ReviewedFoodProposalConfirmation.version, "reviewed-web-proposal-v2")
        XCTAssertEqual(ReviewedFoodProposalConfirmation.version3, "reviewed-web-proposal-v3")
        XCTAssertEqual(ReviewedFoodProposalConfirmation.admittedPipelines, [
            "reviewed-web-proposal-v1": "reviewed-web-proposal-v1:food-proposal-binding-v7:reviewed-web-admission-v5",
            "reviewed-web-proposal-v2": "reviewed-web-proposal-v2:food-proposal-binding-v7:reviewed-web-admission-v6",
            "reviewed-web-proposal-v3": "reviewed-web-proposal-v3:food-proposal-binding-v7:reviewed-web-admission-v7"
        ])
        XCTAssertEqual(FoodProposalReviewGateRecord.knownChoicePolicies, ["food-proposal-review-choice-v3"])
        XCTAssertEqual(FoodProposalReviewGateRecordV3.knownChoicePolicies, ["food-proposal-review-choice-v4"])
        XCTAssertEqual(FoodProposalReviewAction.knownPresentations, ["web-lookup-review-v1"])
        XCTAssertEqual(FoodDocumentPartialRead.selectionPolicyBounds, FoodDocumentBounds(blocks: 2_048, characters: 100_000))
        XCTAssertEqual(FoodProposalReviewActionV3.knownPresentations, ["web-lookup-review-v2"])
    }

    // MARK: Golden v3 bytes and the production writer (offer row 1)

    func testGoldenV3BytesPinKeysOrderAndOneOfferedCandidate() throws {
        let (review, proposal, _) = try twoPanelReview(query: "tofu pudding [market: United Kingdom]")
        let input = try confirmation(clock: fractionalClock).prepare(review: review, proposal: proposal,
            scope: .representativeEstimate, locale: LedgerText("en_GB"))
        let text = try ReviewedWebFixtures.manifestText(input)
        let candidate = try json(proposal.candidate)
        let document = String(decoding: try encoder.encode(proposal.document), as: UTF8.self)
        let golden = #"{"candidate":"# + candidate + #","document":"# + document
            + #","gate":{"choicePolicy":"food-proposal-review-choice-v4","personChoice":"c1","rankingAvailable":true,"representativeSourceOnly":false,"selectionChoice":"c1"},"#
            + #""offered":["# + candidate + #"],"#
            + #""query":"tofu pudding [market: United Kingdom]","review":{"action":"use_this_source","presentation":"web-lookup-review-v2"},"#
            + #""reviewedAt":1791712345678.9,"scope":"representative_estimate","version":"reviewed-web-proposal-v3"}"#
        XCTAssertEqual(text, golden)
        XCTAssertFalse(document.contains("partialRead"))
        XCTAssertEqual(input.evidence[0].captureMethodVersion.value, "reviewed-web-proposal-v3")
        XCTAssertEqual(input.sourceReleases[0].schemaVersion.value, "reviewed-web-proposal-v3:representative_estimate")
        XCTAssertEqual(input.sourceReleases[0].pipelineVersion.value,
                       "reviewed-web-proposal-v3:food-proposal-binding-v7:reviewed-web-admission-v7")
        guard case let .v3(manifest) = try XCTUnwrap(FoodProposalReviewManifestRecord.decode(Data(text.utf8))) else { return XCTFail("v3") }
        XCTAssertEqual(String(decoding: try encoder.encode(manifest), as: UTF8.self), text)
        XCTAssertNil(manifest.admissionFailure)
        XCTAssertEqual(admitted(input), .representativeEstimate)
        XCTAssertTrue(FoodReviewedWebProposalPolicy.manifestDigestIsValid(evidence: input.evidence, releases: input.sourceReleases,
            candidate: input.candidates[0].candidate, digester: SHA256Digester()))
    }

    func testProductionWriterRefusesWhatTodaysRuleDoesNotPermit() throws {
        let cases: [(String, GenericFoodProposalReview, BoundFoodProposal, FoodProposalReviewScope)] = [
            try ("none", ReviewedWebFixtures.review(choice: "none").0, ReviewedWebFixtures.review().1, .representativeEstimate),
            try ("clarify", ReviewedWebFixtures.review(choice: "clarify").0, ReviewedWebFixtures.review().1, .representativeEstimate),
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
    }

    // MARK: Larger documents: v3 admits them, v1 and v2 never do

    func testWritersRefuseLargerDocumentsForV1AndV2AndV3AcceptsThem() throws {
        let (review, proposal, _) = try twoPanelReview(extraLines: 600)
        XCTAssertEqual(proposal.document.blocks.count, 602)
        XCTAssertFalse(proposal.document.fits(.reviewManifestV1V2))
        let v3 = try confirmation().prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("en_GB"))
        XCTAssertEqual(admitted(v3), .representativeEstimate)
        XCTAssertThrowsError(try confirmation().prepareVersion2(review: review, proposal: proposal, scope: .representativeEstimate,
                                                                locale: LedgerText("en_GB"))) {
            XCTAssertEqual($0 as? GenericFoodProposalError, .invalidSelection)
        }
        XCTAssertThrowsError(try confirmation().prepareVersion1(proposal, query: review.foodTerms, scope: .representativeEstimate,
            acknowledgement: .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: true),
            locale: LedgerText("en_GB"))) {
            XCTAssertEqual($0 as? GenericFoodProposalError, .invalidSelection)
        }
    }

    func testStoredV1AndV2KeepTheirBoundAndRejectPartReadDocuments() throws {
        let (review, proposal) = try ReviewedWebFixtures.review()
        let v2 = try confirmation().prepareVersion2(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("zh_TW"))
        let v1 = try ReviewedWebFixtures.v1Fixture("representative-serving").input
        let v3 = try confirmation().prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("zh_TW"))
        for input in [v1, v2, v3] { XCTAssertNotNil(admitted(input)) }
        let selected = ";projection:" + FoodDocumentPartialRead.selectedProjectionVersion
        let shapes: [(String, String)] = [
            ("513 blocks", extraBlocks(count: 512)),
            ("30,001 characters", #"{"id":"x0","kind":"p","locator":"p:x0","text":""# + String(repeating: "x", count: 30_000) + #""},"#),
            ("selected locator", #"{"id":"x0","kind":"p","locator":"p:x0"# + selected + #"","text":"x"},"#)
        ]
        for (label, input) in [("v1", v1), ("v2", v2)] {
            let text = try ReviewedWebFixtures.manifestText(input)
            XCTAssertNotNil(admitted(try ReviewedWebFixtures.rebind(input, manifest: text.replacingOccurrences(
                of: #""blocks":["#, with: #""blocks":["# + extraBlocks(count: 400)))), "\(label) within the old bound")
            for (name, blocks) in shapes {
                let rewritten = try ReviewedWebFixtures.rebind(input, manifest: text.replacingOccurrences(of: #""blocks":["#, with: #""blocks":["# + blocks))
                XCTAssertNil(admitted(rewritten), "\(label) \(name)")
                XCTAssertNil(try FoodReviewedWebProposalPolicy.restoredSourceCandidate(rewritten, candidate: rewritten.candidates[0]), "\(label) \(name)")
                XCTAssertTrue(FoodReviewedWebProposalPolicy.manifestDigestIsValid(evidence: rewritten.evidence, releases: rewritten.sourceReleases,
                    candidate: rewritten.candidates[0].candidate, digester: SHA256Digester()), "\(label) \(name): the digest alone still holds")
            }
            // A valid part-read document on a v1 or v2 manifest is rejected by the explicit
            // admission rule: the document itself validates and the candidate still binds.
            let partRead = try ReviewedWebFixtures.rebind(input, manifest: try validPartRead(text))
            guard let record = FoodProposalReviewManifestRecord.decode(Data(try ReviewedWebFixtures.manifestText(partRead).utf8)) else {
                XCTFail("\(label): the part-read manifest must decode"); continue
            }
            XCTAssertNoThrow(try record.document.validate(), label)
            XCTAssertNotNil(record.document.partialRead, label)
            XCTAssertNoThrow(try FoodProposalBinding.validate(.init(candidates: [record.candidate], preferredId: record.candidate.id),
                                                              documents: [record.document]), label)
            XCTAssertFalse(record.reviewIsAdmissible, label)
            XCTAssertNil(admitted(partRead), "\(label) partialRead")
        }
        // The same larger document is admitted under v3.
        let v3Text = try ReviewedWebFixtures.manifestText(v3)
        XCTAssertNotNil(admitted(try ReviewedWebFixtures.rebind(v3, manifest: v3Text.replacingOccurrences(
            of: #""blocks":["#, with: #""blocks":["# + extraBlocks(count: 700)))))
    }

    // MARK: v3 admission, one case per rule

    func testV3AdmitsTheFormatOfEveryOfferRow() throws {
        let (input, c1, c2, c1Duplicate) = try preparedTwoPanel()
        let c3 = c1Duplicate.replacingOccurrences(of: #""id":"c2""#, with: #""id":"c3""#)
        let offered1 = #""offered":["# + c1 + "]"
        let cases: [(String, [(String, String)])] = [
            ("row 1", []),
            ("row 2: the person picks a competing panel over the suggestion", [(offered1, #""offered":["# + c1 + "," + c2 + "]"),
                (#""selectionChoice":"c1""#, #""selectionChoice":"c2""#)]),
            ("row 2: two equal panels are both offered", [(offered1, #""offered":["# + c1 + "," + c1Duplicate + "]")]),
            ("row 3: clarify with conflicting panels", [(offered1, #""offered":["# + c1 + "," + c2 + "]"),
                (#""selectionChoice":"c1""#, #""selectionChoice":"clarify""#)]),
            ("row 3: three panels, each conflicting with another", [(offered1, #""offered":["# + [c1, c2, c3].joined(separator: ",") + "]"),
                (#""selectionChoice":"c1""#, #""selectionChoice":"clarify""#)])
        ]
        for (name, edits) in cases {
            XCTAssertNotNil(admitted(try rewrite(input, edits)), name)
        }
    }

    func testV3RejectsEachAdmissionRule() throws {
        let (input, c1, c2, c1Duplicate) = try preparedTwoPanel()
        let offered1 = #""offered":["# + c1 + "]"
        let both = #""offered":["# + c1 + "," + c2 + "]"
        let changedC1 = c1.replacingOccurrences(of: #""limitations":[]"#, with: #""limitations":["Changed after review"]"#)
        let unbound = try json(candidate("c2", block: "b2", energy: "350"))
        let otherPreparation = try json(bound(candidate("c2", block: "b2", energy: "250", preparation: "冷藏")))
        let c3Duplicate = c1Duplicate.replacingOccurrences(of: #""id":"c2""#, with: #""id":"c3""#)
        // Same identity, energy unknown: it conflicts with neither c1 nor c2.
        let c3Neutral = try json(bound(candidate("c3", block: "b1", energy: nil)))
        let record = #""partialRead":{"fullBlocks":3000,"fullCharacters":10,"keptBlocks":2,"keptCharacters":44,"policy":"food-document-block-selection-v1"},"#
        let cases: [(String, [(String, String)])] = [
            ("1 unknown key", [(#""scope":"#, #""extra":1,"scope":"#)]),
            ("1 missing offered", [(offered1 + ",", "")]),
            ("1 unknown key in gate", [(#""personChoice":"c1","#, #""personChoice":"c1","extra":true,"#)]),
            ("2 v2 choice policy", [("food-proposal-review-choice-v4", "food-proposal-review-choice-v3")]),
            ("2 v1 presentation", [("web-lookup-review-v2", "web-lookup-review-v1")]),
            ("2 unknown action", [("use_this_source", "accept_everything")]),
            ("3 ranking unavailable", [(#""rankingAvailable":true"#, #""rankingAvailable":false"#)]),
            ("3 selection none", [(#""selectionChoice":"c1""#, #""selectionChoice":"none""#)]),
            ("3 empty selection", [(#""selectionChoice":"c1""#, #""selectionChoice":"""#)]),
            ("4 person choice differs from candidate", [(offered1, both), (#""personChoice":"c1""#, #""personChoice":"c2""#)]),
            ("5 candidate not offered", [(offered1, #""offered":["# + c2 + "]")]),
            ("5 offered member differs from the candidate", [(offered1, #""offered":["# + changedC1 + "]")]),
            ("6 empty offered", [(offered1, #""offered":[]"#)]),
            ("6 repeated id", [(offered1, #""offered":["# + c1 + "," + c1 + "]")]),
            ("6 more than three", [(offered1, #""offered":["# + [c1, c2, c1Duplicate, c3Duplicate].joined(separator: ",") + "]")]),
            ("7 offered candidate does not bind", [(offered1, #""offered":["# + c1 + "," + unbound + "]")]),
            ("7 basis conflicts with the query", [(#""query":"tofu pudding""#, #""query":"tofu pudding per 100 ml""#)]),
            ("8 offered candidates of different identities", [(offered1, #""offered":["# + c1 + "," + otherPreparation + "]")]),
            ("9 selection not offered", [(#""selectionChoice":"c1""#, #""selectionChoice":"c3""#)]),
            ("9 suggestion names a candidate outside offered", [(#""selectionChoice":"c1""#, #""selectionChoice":"c2""#)]),
            ("10 clarify with one candidate", [(#""selectionChoice":"c1""#, #""selectionChoice":"clarify""#)]),
            ("10 clarify with equal panels", [(offered1, #""offered":["# + c1 + "," + c1Duplicate + "]"),
                (#""selectionChoice":"c1""#, #""selectionChoice":"clarify""#)]),
            ("10 clarify with a third panel that conflicts with neither", [(offered1, #""offered":["# + [c1, c2, c3Neutral].joined(separator: ",") + "]"),
                (#""selectionChoice":"c1""#, #""selectionChoice":"clarify""#)]),
            ("12 invalid part-read record", [(#""document":{"#, #""document":{"# + record)])
        ]
        let expected: [String: String] = [
            "3 ranking unavailable": "ranking_unavailable",
            "3 selection none": "selection_none",
            "4 person choice differs from candidate": "person_choice",
            "5 candidate not offered": "candidate_not_offered",
            "5 offered member differs from the candidate": "candidate_not_offered",
            "6 empty offered": "offered_count",
            "6 repeated id": "offered_count",
            "6 more than three": "offered_count",
            "7 offered candidate does not bind": "offered_not_choosable",
            "7 basis conflicts with the query": "offered_basis_conflict",
            "8 offered candidates of different identities": "offered_mixed_identity",
            "9 selection not offered": "selection_not_offered",
            "9 suggestion names a candidate outside offered": "selection_not_offered",
            "10 clarify with one candidate": "clarify_without_conflict",
            "10 clarify with equal panels": "clarify_without_conflict",
            "10 clarify with a third panel that conflicts with neither": "clarify_without_conflict",
            "12 invalid part-read record": "document"
        ]
        for (name, edits) in cases {
            let rewritten = try rewrite(input, edits)
            XCTAssertNil(admitted(rewritten), name)
            let record = FoodProposalReviewManifestRecord.decode(Data(try ReviewedWebFixtures.manifestText(rewritten).utf8))
            if let code = expected[name] {
                guard case let .v3(manifest) = record else { XCTFail("\(name): expected a decodable v3 manifest"); continue }
                XCTAssertEqual(manifest.admissionFailure, code, name)
            } else {
                XCTAssertNil(record, "\(name): rejected at strict decoding")
            }
        }
        // 11: a representative-only source saved as an exact product.
        let (review, proposal, _) = try twoPanelReview()
        let exact = try confirmation().prepare(review: review, proposal: proposal, scope: .exactProduct, locale: LedgerText("en_GB"))
        XCTAssertNotNil(admitted(exact))
        let restricted = try ReviewedWebFixtures.rewrite(exact, replacing: #""representativeSourceOnly":false"#,
                                                         with: #""representativeSourceOnly":true"#)
        XCTAssertNil(admitted(restricted))
        guard case let .v3(manifest) = FoodProposalReviewManifestRecord.decode(Data(try ReviewedWebFixtures.manifestText(restricted).utf8)) else {
            return XCTFail("v3")
        }
        XCTAssertEqual(manifest.admissionFailure, "representative_only")
    }

    func testV2RejectsEveryV3Shape() throws {
        let (review, proposal) = try ReviewedWebFixtures.review()
        let v2 = try confirmation().prepareVersion2(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("zh_TW"))
        let text = try ReviewedWebFixtures.manifestText(v2)
        let candidate = try json(proposal.candidate)
        let mutations: [(String, String)] = [
            ("offered key", text.replacingOccurrences(of: #""query":"#, with: #""offered":["# + candidate + #"],"query":"#)),
            ("person choice in gate", text.replacingOccurrences(of: #""rankingAvailable":"#, with: #""personChoice":"c1","rankingAvailable":"#)),
            ("v4 choice policy", text.replacingOccurrences(of: "food-proposal-review-choice-v3", with: "food-proposal-review-choice-v4")),
            ("v2 presentation", text.replacingOccurrences(of: "web-lookup-review-v1", with: "web-lookup-review-v2"))
        ]
        for (name, mutated) in mutations {
            XCTAssertNotEqual(mutated, text, name)
            XCTAssertNil(FoodProposalReviewManifestRecord.decode(Data(mutated.utf8)), name)
            XCTAssertNil(admitted(try ReviewedWebFixtures.rebind(v2, manifest: mutated)), name)
        }
    }

    // MARK: Archive contract

    func testV3EvidenceNeedsContractFiveAndTheBinaryContractIsUnchanged() throws {
        let (review, proposal) = try ReviewedWebFixtures.review()
        let v3 = try confirmation().prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("zh_TW"))
        let v2 = try confirmation().prepareVersion2(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("zh_TW"))
        var records = LedgerMutation(); records.evidence = v3.evidence
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: records), 5)
        records.evidence = v2.evidence
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: records), 5)
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: LedgerMutation()), 1)
        XCTAssertEqual(CanonicalFoodProjection.foodContractVersion, 9)
    }

    // MARK: Screen contract web-lookup-review-v2, one candidate

    func testReviewContentV2EqualsV1ForAWholePageAndIsRebuiltFromTheManifest() throws {
        let (review, proposal, _) = try twoPanelReview()
        let shown = try XCTUnwrap(FoodWebLookupReviewContent(document: proposal.document, candidate: proposal.candidate,
            scope: .representativeEstimate, presentation: FoodProposalReviewAction.webLookupReviewV2))
        XCTAssertEqual(shown, FoodWebLookupReviewContent(document: proposal.document, candidate: proposal.candidate, scope: .representativeEstimate))
        XCTAssertNil(shown.partRead)
        XCTAssertEqual(shown.notStatedText, "Not stated")
        XCTAssertEqual(shown.notStated, [.carbohydrate, .fat, .fibre, .sodium])
        let input = try confirmation().prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("en_GB"))
        guard case let .v3(manifest) = try XCTUnwrap(FoodProposalReviewManifestRecord.decode(Data(try ReviewedWebFixtures.manifestText(input).utf8))) else {
            return XCTFail("v3")
        }
        XCTAssertEqual(FoodWebLookupReviewContent(manifest: manifest), shown)
        // An unknown presentation fails closed.
        XCTAssertNil(FoodWebLookupReviewContent(document: proposal.document, candidate: proposal.candidate, scope: nil,
                                                presentation: "web-lookup-review-v9"))
    }

    func testReviewContentV2MarksAPartReadDocumentOnlyUnderV2() throws {
        let selected = ";projection:" + FoodDocumentPartialRead.selectedProjectionVersion
        let block = FoodDocumentBlock(id: "b42", kind: "tr", text: line1, locator: "tr:1" + selected)
        let document = try CapturedFoodDocument(id: "doc_part", url: "https://example.com/tofu", rawSha256: String(repeating: "a", count: 64),
            captureOrigin: "synthetic_fixture", retrievedAt: "2026-10-04T00:00:00Z", blocks: [block],
            partialRead: .init(fullBlocks: 2_600, fullCharacters: 120_000, keptBlocks: 1, keptCharacters: line1.count))
        let (_, proposal, _) = try twoPanelReview()
        let v2 = try XCTUnwrap(FoodWebLookupReviewContent(document: document, candidate: proposal.candidate, scope: nil,
                                                          presentation: FoodProposalReviewAction.webLookupReviewV2))
        XCTAssertEqual(v2.partRead, "Only part of this page was read.")
        XCTAssertEqual(v2.notStatedText, "Not in the part read")
        XCTAssertEqual(v2.notStated, [.carbohydrate, .fat, .fibre, .sodium], "Membership never changes")
        let v1 = FoodWebLookupReviewContent(document: document, candidate: proposal.candidate, scope: nil)
        XCTAssertNil(v1.partRead)
        XCTAssertEqual(v1.notStatedText, "Not stated")
        XCTAssertEqual(v1.declared, v2.declared)
    }

    // MARK: Fixtures

    private func confirmation(clock: any LedgerClock = LedgerFixtures.clock) -> ReviewedFoodProposalConfirmation {
        ReviewedFoodProposalConfirmation(ids: RandomLedgerIDGenerator(), clock: clock,
            encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
    }
    private func admitted(_ input: PopulatedFoodConfirmation) -> FoodProposalReviewScope? {
        FoodReviewedWebProposalPolicy.scope(input, candidate: input.candidates[0])
    }
    private func json(_ candidate: FoodProposalCandidate) throws -> String {
        String(decoding: try encoder.encode(candidate), as: UTF8.self)
    }
    /// Rewrites the single-document manifest text so its document is a valid part-read document:
    /// every locator carries the selected version and the record matches the kept blocks.
    private func validPartRead(_ text: String) throws -> String {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let record = try XCTUnwrap(FoodProposalReviewManifestRecord.decode(Data(text.utf8)))
        let document = record.document
        var rewritten = text
        for block in document.blocks {
            let projection = try XCTUnwrap(block.locator.range(of: ";projection:"))
            let selected = block.locator[..<projection.lowerBound] + ";projection:" + FoodDocumentPartialRead.selectedProjectionVersion
            rewritten = rewritten.replacingOccurrences(of: #""locator":""# + block.locator + #"""#, with: #""locator":""# + selected + #"""#)
        }
        let partial = #""partialRead":{"fullBlocks":3000,"fullCharacters":120000,"keptBlocks":\#(document.blocks.count),"keptCharacters":\#(document.characterCount),"policy":"food-document-block-selection-v1"},"#
        XCTAssertTrue(rewritten.contains(#""document":{"#))
        return rewritten.replacingOccurrences(of: #""document":{"#, with: #""document":{"# + partial)
    }
    private func extraBlocks(count: Int) -> String {
        (1...count).map { #"{"id":"x\#($0)","kind":"p","locator":"p:x\#($0)","text":"x"}"# }.joined(separator: ",") + ","
    }
    private func rewrite(_ input: PopulatedFoodConfirmation, _ edits: [(String, String)]) throws -> PopulatedFoodConfirmation {
        var text = try ReviewedWebFixtures.manifestText(input)
        for (from, to) in edits {
            XCTAssertTrue(text.contains(from), "Fixture must contain \(from)")
            text = text.replacingOccurrences(of: from, with: to)
        }
        return try ReviewedWebFixtures.rebind(input, manifest: text)
    }

    /// One plain-text page with two panels of one food (150 and 250 kcal per serving). The
    /// review extracts only `c1`, so today's rule permits it; `c2` and a value-equal duplicate of
    /// `c1` (id `c2`) are encoded for offered-set rewrites.
    private func preparedTwoPanel() throws -> (PopulatedFoodConfirmation, String, String, String) {
        let (review, proposal, c2) = try twoPanelReview()
        let input = try confirmation().prepare(review: review, proposal: proposal, scope: .representativeEstimate, locale: LedgerText("en_GB"))
        let c1 = try json(proposal.candidate)
        let duplicate = c1.replacingOccurrences(of: #""id":"c1""#, with: #""id":"c2""#)
        XCTAssertNotEqual(duplicate, c1)
        return (input, c1, try json(c2), duplicate)
    }

    private var document: CapturedFoodDocument {
        get throws { try page(extraLines: 0) }
    }
    private func page(extraLines: Int) throws -> CapturedFoodDocument {
        let lines = [line1, line2] + (0..<extraLines).map { "Menu item \($0)" }
        return try GenericFoodDocumentProjector.project(Data(lines.joined(separator: "\n").utf8), url: URL(string: "https://example.com/tofu")!,
            mediaType: "text/plain", retrievedAt: LedgerFixtures.date, origin: "synthetic_fixture")
    }
    private func candidate(_ id: String, block: String, energy: String?, preparation: String? = nil, documentID: String? = nil) throws -> FoodProposalCandidate {
        let quote = block == "b1" ? line1 : line2
        let ref: [[String: Any]] = [["block_id": block, "quote": quote]]
        let values: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            let known = (key == .energy && energy != nil) || key == .protein
            return ["key": key.rawValue, "state": known ? "declared" : "unknown",
                "value": known ? (key == .energy ? energy ?? "" : "6") as Any : NSNull(), "unit": known ? key.unit as Any : NSNull(),
                "evidence": known ? ref : [], "unknown_reason": known ? NSNull() : "not_observed" as Any]
        }
        let object: [String: Any] = ["id": id, "document_id": try documentID ?? document.id, "name": "豆花", "brand": NSNull(),
            "preparation": preparation.map { $0 as Any } ?? NSNull(), "identity_evidence": ref, "panel_evidence": ref,
            "basis": ["amount": "1", "unit": "serving", "label": "每份一碗", "evidence": ref],
            "nutrients": values, "limitations": []]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FoodProposalCandidate.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func bound(_ candidate: FoodProposalCandidate) throws -> FoodProposalCandidate {
        let validation = try FoodProposalBinding.validate(.init(candidates: [candidate], preferredId: candidate.id), documents: [document])
        return try XCTUnwrap(validation.candidates.first?.candidate, "\(validation.rejected)")
    }
    private func twoPanelReview(query: String = ReviewedWebFixtures.query, extraLines: Int = 0) throws
        -> (GenericFoodProposalReview, BoundFoodProposal, FoodProposalCandidate) {
        let document = try page(extraLines: extraLines)
        let c1 = try candidate("c1", block: "b1", energy: "150", documentID: document.id)
        let c2 = try candidate("c2", block: "b2", energy: "250", documentID: document.id)
        let both = try FoodProposalBinding.validate(.init(candidates: [c1, c2], preferredId: "c1"), documents: [document])
        XCTAssertEqual(both.candidates.map(\.status), [.conflictingCandidates, .conflictingCandidates])
        XCTAssertTrue(both.candidates.allSatisfy(\.choosable))
        let validation = try FoodProposalBinding.validate(.init(candidates: [c1], preferredId: "c1"), documents: [document])
        let selection = try FoodProposalSelection(unscoredChoice: "c1", validation: validation)
        let review = GenericFoodProposalReview(foodTerms: query, discovery: nil, documents: [document], validation: validation,
            selection: selection)
        return (review, try XCTUnwrap(validation.candidates.first), try XCTUnwrap(both.candidates.last?.candidate))
    }
}
