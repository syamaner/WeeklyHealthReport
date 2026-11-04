import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import XCTest

/// Phase B interplay for Ciqual rows (docs/ciqual-2025-admission-v1.md section 6, #384 C2):
/// layered saves with the bundled Ciqual corpus, reopen under `label-estimate-compatibility-v1`
/// with `cocoa-percent-policy-v2`, and the refusals. Synthetic label text only.
final class CiqualLabelEstimateContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures

    private static func chocolateInput(name: String) throws -> PopulatedFoodConfirmation {
        let manifest = PastedLabelManifest(pastedText: F.pastedText, pastedTextSHA256: try F.textHash(),
            parserVersion: PastedLabelSource.parserVersionV2, gateVersion: PastedLabelSource.gateVersion,
            arithmeticVersion: PastedLabelSource.arithmeticVersion, conversionVersion: PastedLabelSource.conversionVersion,
            labelFormat: "taiwan_nutrition_labelling", launchScope: ["taiwan_nutrition_labelling"],
            identityMapping: try .init(fortificationAnswer: .no, servingBasis: .per100Grams), candidate: try F.candidate(),
            storedHeaderID: "h2", conversions: [F.kcal, F.sodium], flagsShown: [], corrections: [], warningsShown: [],
            name: name, brand: "Synthetic Mill")
        return try F.input(manifest)
    }

    private static func code(_ value: String) -> String {
        "ciqual:2025-11-19:sha256:\(CiqualGenericFoodSearch.sourceManifestSHA256):alim:\(value)"
    }

    private static func pool() throws -> LabelEstimateCandidatePool {
        let ids = RandomLedgerIDGenerator()
        return LabelEstimateCandidatePool(searcher: try CiqualGenericFoodSearch(ids: ids), ids: ids)
    }

    private static func value(_ set: NutrientSet, _ key: NutrientKey) -> NutrientValue {
        set.entries.first { $0.key == key }!.value
    }

    func testLayeredSavesWithThe70And50PercentRowsSaveAndReopen() throws {
        for (percent, record) in [(70.0, "31074"), (50.0, "31005")] {
            let option = try XCTUnwrap(try Self.pool().options(cocoaPercent: percent, capturedAt: LedgerFixtures.date,
                                                               locale: LedgerText("en_GB")).first, "\(percent)")
            XCTAssertEqual(option.id, Self.code(record))
            for harness in try LedgerFixtures.harnesses() {
                defer { harness.cleanup() }
                let service = try F.service(harness)
                let input = try Self.chocolateInput(name: "Synthetic dark chocolate \(Int(percent))%")
                let saved = try service.save(F.state(input), operationID: LedgerFixtures.operationID(9_700 + Int(percent)),
                                             estimate: option.choice(cocoaPercent: percent, origin: .name))
                let layer = try XCTUnwrap(saved.estimate, harness.name)
                XCTAssertEqual(layer.candidateDecision.candidate.recordID.value, Self.code(record), harness.name)
                XCTAssertEqual(saved.resolutionVersion.sourceReleaseIDs.last, option.sourceRelease.sourceReleaseID, harness.name)
                let asserted = try XCTUnwrap(saved.assertions.first?.labelEstimate)
                XCTAssertEqual(asserted.cocoaPercent, percent)
                XCTAssertEqual(asserted.genericVariant?.value, "Ciqual · French composition estimate · per 100 g", "no percentage in the variant")
                XCTAssertFalse(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self).contains("Chocolat noir"),
                               "the French name never reaches a saved record (\(harness.name))")
                if record == "31074" {
                    // A Ciqual "< 20" selenium fills the unprinted key as an open upper bound, never 20 or zero.
                    guard case let .bounded(bounds) = Self.value(saved.resolutionVersion.nutrients, .selenium) else {
                        return XCTFail("selenium stays a bound (\(harness.name))")
                    }
                    XCTAssertNil(bounds.lower); XCTAssertEqual(bounds.upper, 20); XCTAssertFalse(bounds.upperClosed)
                }
                XCTAssertEqual(try harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID), saved, harness.name)
                let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
                XCTAssertEqual(reopened.reopened?.estimate, layer, harness.name)
            }
        }
    }

    /// M3: the pool is `label-estimate-pool-v2` now that its source set includes Ciqual. An entry
    /// saved under v1 (CoFID, USDA and TFDA only) keeps its stamp, saves and reopens unchanged.
    func testAPoolV1StampedEstimateStillSavesAndReopens() throws {
        XCTAssertEqual(LabelEstimateCandidatePool.version, "label-estimate-pool-v2")
        let ids = RandomLedgerIDGenerator()
        let search = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)],
                                                regionalSources: [try TFDAGenericFoodSearch(ids: ids)], ids: ids)
        let current = try XCTUnwrap(try LabelEstimateCandidatePool(searcher: search, ids: ids)
            .options(cocoaPercent: 80, capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB")).first)
        XCTAssertEqual(current.evidence.map(\.captureMethodVersion.value), ["label-estimate-pool-v2"])
        // The fixture: the same row and evidence as a v1 pool would have stamped them.
        let v1Evidence = try current.evidence.map { evidence in
            try CaptureEvidence(evidenceID: evidence.evidenceID, kind: evidence.kind, capturedAt: evidence.capturedAt, locale: evidence.locale,
                                captureMethod: evidence.captureMethod, captureMethodVersion: LedgerText("label-estimate-pool-v1"),
                                originalPayload: evidence.originalPayload)
        }
        let v1 = LabelEstimateOption(generic: current.generic, evidence: v1Evidence, sourceRelease: current.sourceRelease)
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(F.state(Self.chocolateInput(name: "Synthetic dark chocolate 80%")),
                                         operationID: LedgerFixtures.operationID(9_790), estimate: v1.choice(cocoaPercent: 80, origin: .name))
            let layer = try XCTUnwrap(saved.estimate, harness.name)
            XCTAssertEqual(layer.evidence.map(\.captureMethodVersion.value), ["label-estimate-pool-v1"], harness.name)
            XCTAssertEqual(try harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID), saved, harness.name)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.reopened?.estimate, layer, harness.name)
        }
    }

    func testTheOpenEndedCookingRowIsRefusedAtSaveForAnyPercentage() throws {
        let ids = RandomLedgerIDGenerator()
        let search = try CiqualGenericFoodSearch(ids: ids)
        guard case let .confirmation(route) = try search.search(GenericFoodSearchRequest(text: LedgerText("dark chocolate 40%"),
            capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB"))) else { return XCTFail() }
        let cooking = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value == Self.code("31085") }).candidate
        let release = try XCTUnwrap(route.confirmation.sourceReleases.first)
        XCTAssertEqual(CocoaPercentPolicy.band(cooking), .atLeast(40))
        for percent in [40.0, 41, 50, 70] {
            XCTAssertFalse(LabelEstimateCompatibility.isCompatible(cooking, cocoaPercent: percent), "\(percent)")
            XCTAssertTrue(try Self.pool().options(cocoaPercent: percent, capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB"))
                .allSatisfy { $0.id != Self.code("31085") }, "never offered at \(percent)")
        }
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            for (index, percent) in [40.0, 50, 70].enumerated() {
                let choice = LabelEstimateChoice(generic: cooking, evidence: route.confirmation.evidence, sourceRelease: release,
                                                 cocoaPercent: percent, origin: .typed)
                XCTAssertThrowsError(try service.save(F.state(Self.chocolateInput(name: "Synthetic dark chocolate \(Int(percent))%")),
                                                      operationID: LedgerFixtures.operationID(9_760 + index), estimate: choice),
                                     "\(percent) (\(harness.name))") {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidLabelEstimate, harness.name)
                }
            }
        }
    }

    func testRule2PrefillsOpenEndedLabelPhrasesAsUnderV1() {
        for text in ["at least 70% cocoa", "minimum 70% cocoa", "more than 70% cocoa", "over 70% cocoa",
                     "70% cocoa or more", "70% cocoa and more", "70% cocoa minimum", "Cocoa solids: 70% minimum",
                     "Dark chocolate. At least 70% cocoa solids.", "70% cocoa; at least 70% cocoa"] {
            XCTAssertEqual(LabelEstimateCompatibility.prefill(name: "Synthetic bar", pastedText: text)?.value, 70, text)
            XCTAssertEqual(LabelEstimateCompatibility.prefill(name: "Synthetic bar", pastedText: text)?.origin, .pastedText, text)
        }
        XCTAssertEqual(LabelEstimateCompatibility.prefill(name: "Dark chocolate, at least 85% cocoa", pastedText: nil)?.value, 85)
        for text in ["at least 70% cocoa, more than 85% cocoa", "70% cocoa or more; 85% cocoa", "70-85% cocoa solids",
                     "at least 30% cocoa butter"] {
            XCTAssertNil(LabelEstimateCompatibility.prefill(name: "Synthetic bar", pastedText: text), text)
        }
    }
    /// A Ciqual search entry saves and reopens with its bounds and unknowns intact, and no
    /// re-resolution target exists for it (section 3.6): only the CoFID matcher is offered.
    func testACiqualEntrySavesReopensAndHasNoReresolutionTarget() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let ids = RandomLedgerIDGenerator()
            guard case let .confirmation(route) = try CiqualGenericFoodSearch(ids: ids).search(GenericFoodSearchRequest(
                text: LedgerText("dark chocolate 70%"), capturedAt: LedgerFixtures.clock.now(), locale: LedgerText("en_GB"))) else { return XCTFail() }
            XCTAssertEqual(route.matches.first?.candidate.candidate.recordID.value, Self.code("31074"))
            var state = FoodConfirmationState(input: route.confirmation)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(20, .grams))
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let service = FoodConfirmationService(ledger: try LedgerFixtures.service(harness.committer), reader: harness.reader,
                clock: LedgerFixtures.clock, ids: ids, digester: SHA256Digester())
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(9_780))
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.selectedCandidate.candidate.nutrients, route.matches[0].candidate.candidate.nutrients, harness.name)
            XCTAssertEqual(reopened.input.sourceReleases, route.confirmation.sourceReleases, harness.name)
            XCTAssertEqual(try service.isEstimate(saved), true, harness.name)
            let provider = try CoFIDReresolutionProvider(ids: ids)
            XCTAssertFalse(try provider.targets().contains { $0.sourceRelease.sourceID.value == "ciqual" })
            let ciqualTarget = FoodReresolutionTarget(sourceRelease: try XCTUnwrap(route.confirmation.sourceReleases.first),
                                                      methodVersion: try LedgerText(CiqualGenericFoodSearch.matcherVersion))
            XCTAssertThrowsError(try provider.candidates(for: saved, target: ciqualTarget, at: LedgerFixtures.date), harness.name) {
                XCTAssertEqual($0 as? FoodReresolutionError, .unavailableTarget, harness.name)
            }
        }
    }
}
