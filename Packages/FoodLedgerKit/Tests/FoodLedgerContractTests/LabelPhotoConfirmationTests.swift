import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// The label photo Confirm builder (docs/label-photo-ai-prefill-v1.md P12, 7.3, 8.1, 17.16 and
/// 17.18; contract test 4 as Confirm applies it). Synthetic fixtures only.
final class LabelPhotoConfirmationTests: XCTestCase {
    typealias M = LabelPhotoManifest

    final class Clock: LedgerClock, @unchecked Sendable {
        var value = Date(timeIntervalSince1970: 1_700_000_900)
        func now() -> Date { value }
    }

    let clock = Clock()
    var builder: LabelPhotoConfirmation {
        LabelPhotoConfirmation(clock: clock, encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester,
                               conversions: GoldenPastedLabelConversions())
    }

    static func reading(checks: [LabelReading.Check] = [], imageSHA: String? = nil, declined: Bool = false) throws -> LabelPhotoReading {
        let candidate = try LabelPhotoFixtures.candidate()
        let shown = declined ? PastedLabelManifest.Candidate(route: "C", inputSHA256: candidate.inputSHA256, declined: true,
            declineReasons: ["not_a_label"], wouldMarkReady: false, language: "unknown", servingSize: nil, servingsPerPack: nil,
            headers: [], cells: [], warnings: []) : candidate
        return LabelPhotoReading(imageSHA256: try imageSHA ?? LabelPhotoFixtures.imageSHA(), candidate: shown,
            inferredFormat: LabelPhotoReading.labelFormat,
            gate: LabelReading.Gate(format: LabelPhotoReading.labelFormat, skipped: nil, hardDeclines: [],
                                    flags: [LabelReading.Flag(code: "required_row_missing", concerns: "fibre")]),
            checks: checks, conversions: [PastedLabelFixtures.kcal, PastedLabelFixtures.sodium], storedHeaderID: declined ? nil : "h2",
            versions: .init(mapping: "label-photo-wire-mapping-v1", gate: "label-capture-decline-gate-v2",
                            arithmetic: "label-arithmetic-checks-v2", conversion: "pasted-label-conversions-v1"))
    }

    static func image() throws -> PreparedLabelImage {
        try PreparedLabelImageFactory.make(bytes: LabelPhotoFixtures.imageBytes, pixelWidth: 1_200, pixelHeight: 900, jpegQuality: "0.8",
                                           digester: LedgerFixtures.digester)
    }

    static func reply() throws -> LabelPhotoWireReply {
        let response = try LabelPhotoFixtures.response()
        return LabelPhotoWireReply(wireText: response.wireText, model: response.model, provider: response.provider,
                                   generationID: response.generationID, finishReason: "stop", attempts: 1, usage: response.usage,
                                   requestedAt: response.requestedAt, completedAt: response.completedAt)
    }

    func review(checks: [LabelReading.Check] = [], overriding: [String: LabelPhotoAttention.Location] = [:]) throws -> LabelPhotoReview {
        let candidate = try LabelPhotoFixtures.candidate()
        return try builder.review(reading: try Self.reading(checks: checks), image: try Self.image(), reply: try Self.reply(),
                                  request: LabelPhotoFixtures.request(), locations: LabelPhotoFixtures.locations(candidate, overriding: overriding))
    }

    let details = PastedLabelDetails(name: "Synthetic oat crackers", brand: "Synthetic Mill", fortification: .no)

    func log(_ review: LabelPhotoReview) throws -> PopulatedFoodConfirmation {
        try builder.confirmation(review, details: details, imageEvidenceID: LedgerFixtures.id(9_201, EvidenceTag.self),
                                 manifestEvidenceID: LedgerFixtures.id(9_200, EvidenceTag.self), attachment: try LabelPhotoFixtures.attachment(),
                                 locale: LedgerText("zh_TW"))
    }

    static func manifest(_ input: PopulatedFoodConfirmation) throws -> M {
        guard case let .text(payload) = input.evidence[0].originalPayload, let manifest = M.decode(Data(payload.value.utf8)) else {
            throw LabelPhotoConfirmationError.notVerified
        }
        return manifest
    }

    static func value(_ input: PopulatedFoodConfirmation, _ key: String) -> NutrientValue? {
        input.candidates[0].candidate.nutrients.entries.first { $0.key.rawValue == key }?.value
    }

    // MARK: Attention items block Log (P12)

    func testTheItemsAreTheVerifiersAndLogWaitsForEveryOne() throws {
        let review = try review()
        XCTAssertEqual(review.findings.items.map(\.id), ["蛋白質@h2", "servings_per_pack"])
        XCTAssertEqual(review.findings.items.map(\.reasons), [[.notFound], [.ambiguous]])
        XCTAssertFalse(review.canLog)
        XCTAssertThrowsError(try builder.manifest(review, details: details)) { error in
            XCTAssertEqual(error as? LabelPhotoConfirmationError, .unresolved(["蛋白質@h2", "servings_per_pack"]))
        }
        let one = try builder.check("蛋白質@h2", in: review)
        XCTAssertEqual(one.unresolved, ["servings_per_pack"])
        XCTAssertThrowsError(try log(one))
        let both = try builder.check("servings_per_pack", in: one)
        XCTAssertTrue(both.canLog)
        let input = try log(both)
        let manifest = try Self.manifest(input)
        XCTAssertEqual(manifest.attention.map(\.resolution), [.checked, .checked])
        XCTAssertEqual(manifest.attention.map(\.at), [1_700_000_900_000, 1_700_000_900_000])
        XCTAssertEqual(manifest.flagsShown, [.init(code: "required_row_missing", concerns: "fibre")])
        XCTAssertEqual(manifest.conversions, [PastedLabelFixtures.kcal, PastedLabelFixtures.sodium])
        XCTAssertTrue(LabelPhotoFixtures.verify(input))
        XCTAssertThrowsError(try builder.check("脂肪@h2", in: review), "a found value is not an item")
    }

    func testACorrectionResolvesItsItemAndIsStored() throws {
        var review = try review()
        review = try builder.correct("蛋白質@h2", value: .init(decimalText: "5.4", unit: "g", comparator: "="), in: review)
        review = try builder.check("servings_per_pack", in: review)
        let input = try log(review)
        let manifest = try Self.manifest(input)
        XCTAssertEqual(manifest.attention.map(\.resolution), [.corrected, .checked])
        XCTAssertEqual(manifest.corrections.count, 1)
        XCTAssertEqual(manifest.corrections[0].kind, .corrected)
        XCTAssertEqual(manifest.corrections[0].rowID, "蛋白質")
        guard case let .measured(protein)? = Self.value(input, "protein") else { return XCTFail() }
        XCTAssertEqual(protein.amount, 5.4)
        // A later "Matches the photo" removes the correction.
        let undone = try builder.check("蛋白質@h2", in: review)
        XCTAssertTrue(undone.corrections.isEmpty)
    }

    func testOnlyTheStoredColumnAndTheServingSizeCanBeCorrected() throws {
        let review = try review(overriding: ["蛋白質@h1": .notFound])
        let value = PastedLabelManifest.Correction.Value(decimalText: "1.7", unit: "g", comparator: "=")
        XCTAssertThrowsError(try builder.correct("蛋白質@h1", value: value, in: review)) { error in
            XCTAssertEqual(error as? LabelPhotoConfirmationError, .notCorrectable("蛋白質@h1"))
        }
        XCTAssertThrowsError(try builder.correct("servings_per_pack", value: .init(decimalText: "12", unit: "count", comparator: "="), in: review))
        XCTAssertThrowsError(try builder.correct("蛋白質@h2", value: .init(decimalText: "5.4", unit: "mg", comparator: "="), in: review)) { error in
            XCTAssertEqual(error as? LabelPhotoConfirmationError, .invalidValue("蛋白質@h2"))
        }
        // The serving size, printed with an amount, is corrected.
        let size = try builder.correct("serving_size", value: .init(decimalText: "35", unit: "g", comparator: "="), in: review)
        XCTAssertEqual(size.corrections.last?.kind, .corrected)
    }

    // MARK: Left unknown and the shown-conversions rule (17.16)

    func testLeavingAConversionSourceUnknownRemovesTheConversion() throws {
        var review = try review(overriding: ["鹽@h2": .notFound])
        XCTAssertEqual(review.findings.items.map(\.id), ["蛋白質@h2", "鹽@h2", "servings_per_pack"])
        review = try builder.check("蛋白質@h2", in: review)
        review = try builder.check("servings_per_pack", in: review)
        review = try builder.leaveUnknown("鹽@h2", in: review)
        XCTAssertEqual(review.conversionsShown, [PastedLabelFixtures.kcal])
        XCTAssertEqual(review.conversionsLeftUnknown, [PastedLabelFixtures.sodium], "the calculated sodium reads Left unknown")
        let input = try log(review)
        let manifest = try Self.manifest(input)
        XCTAssertEqual(manifest.conversions, [PastedLabelFixtures.kcal])
        XCTAssertEqual(manifest.attention.map(\.resolution), [.checked, .leftUnknown, .checked])
        guard case .unknown? = Self.value(input, "sodium") else { return XCTFail("sodium is stored unknown") }
        XCTAssertTrue(LabelPhotoFixtures.verify(input))
        // Changing the mind brings the conversion back.
        let back = try builder.check("鹽@h2", in: review)
        XCTAssertEqual(back.conversionsShown, [PastedLabelFixtures.kcal, PastedLabelFixtures.sodium])
    }

    func testLeavingAValueUnknownStoresItUnknownAndDropsItsCorrection() throws {
        var review = try review()
        review = try builder.correct("蛋白質@h2", value: .init(decimalText: "5.4", unit: "g", comparator: "="), in: review)
        review = try builder.leaveUnknown("蛋白質@h2", in: review)
        review = try builder.leaveUnknown("servings_per_pack", in: review)
        XCTAssertTrue(review.corrections.isEmpty)
        let input = try log(review)
        guard case .unknown? = Self.value(input, "protein") else { return XCTFail("protein is stored unknown") }
        XCTAssertTrue(LabelPhotoFixtures.verify(input))
    }

    // MARK: Check groups (test 4)

    func testACheckGroupResolvesItsImplicatedValuesTogether() throws {
        let failed = LabelReading.Check(name: "serving_scaling", basis: nil, nutrient: "carbohydrate", child: nil, status: .fail)
        var review = try review(checks: [failed, .init(name: "energy", basis: "per_serving", nutrient: nil, child: nil, status: .pass)])
        XCTAssertEqual(review.checksFailed, [.init(name: "serving_scaling", basis: nil, nutrient: "carbohydrate", child: nil)])
        let group = try XCTUnwrap(review.findings.checks.first)
        XCTAssertEqual(group.itemIDs, ["碳水化合物@h1", "碳水化合物@h2"])
        review = try builder.correct("碳水化合物@h2", value: .init(decimalText: "61.0", unit: "g", comparator: "="), in: review)
        review = try builder.checkGroup(group, in: review)
        XCTAssertEqual(review.resolutions["碳水化合物@h2"]?.resolution, .corrected, "a correction is kept")
        XCTAssertEqual(review.resolutions["碳水化合物@h1"]?.resolution, .checked)
        review = try builder.check("蛋白質@h2", in: review)
        review = try builder.check("servings_per_pack", in: review)
        let input = try log(review)
        XCTAssertEqual(try Self.manifest(input).warningsShown, ["serving_scaling:carbohydrate"])
        XCTAssertTrue(LabelPhotoFixtures.verify(input))
    }

    // MARK: Times, mismatches and declines

    func testResolutionTimesLieBetweenTheAnswerAndTheCapture() throws {
        clock.value = Date(timeIntervalSince1970: 1_700_000_000)   // before the answer arrived
        var review = try review()
        review = try builder.check("蛋白質@h2", in: review)
        review = try builder.check("servings_per_pack", in: review)
        let input = try log(review)
        let manifest = try Self.manifest(input)
        XCTAssertEqual(manifest.attention.map(\.at), [manifest.response.completedAt, manifest.response.completedAt])
        XCTAssertTrue(LabelPhotoFixtures.verify(input))
    }

    func testAReadingThatDoesNotMatchOrDeclinesBuildsNothing() throws {
        let candidate = try LabelPhotoFixtures.candidate()
        let locations = LabelPhotoFixtures.locations(candidate)
        XCTAssertThrowsError(try builder.review(reading: try Self.reading(imageSHA: String(repeating: "0", count: 64)), image: try Self.image(),
                                                reply: try Self.reply(), request: LabelPhotoFixtures.request(), locations: locations)) { error in
            XCTAssertEqual(error as? LabelPhotoConfirmationError, .mismatch("image"))
        }
        XCTAssertThrowsError(try builder.review(reading: try Self.reading(declined: true), image: try Self.image(), reply: try Self.reply(),
                                                request: LabelPhotoFixtures.request(), locations: locations)) { error in
            XCTAssertEqual(error as? LabelPhotoConfirmationError, .notUsable(["not_a_label"]))
        }
        // Locations that do not cover every cell are refused by the verifier's own rule.
        let partial = M.Locations(locatorVersion: locations.locatorVersion, visionRevision: 3, languages: locations.languages,
                                  records: Array(locations.records.dropFirst()))
        XCTAssertThrowsError(try builder.review(reading: try Self.reading(), image: try Self.image(), reply: try Self.reply(),
                                                request: LabelPhotoFixtures.request(), locations: partial))
        XCTAssertThrowsError(try builder.confirmation(try review(), details: PastedLabelDetails(name: "  "),
                                                      imageEvidenceID: LedgerFixtures.id(9_201, EvidenceTag.self),
                                                      manifestEvidenceID: LedgerFixtures.id(9_200, EvidenceTag.self), attachment: nil,
                                                      locale: LedgerText("zh_TW")))
    }
}
