import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import FoodLedgerTestSupport
import Foundation
import XCTest

/// How approved estimates read on Confirm and the re-resolution screen (estimates on catalogue v2
/// sections 3.3 and 5): the closed label list, the tier in words, notices and details. Built from
/// the shared synthetic estimates v2 golden through the database search route.
@MainActor
final class ApprovedEstimatePresentationTests: XCTestCase {
    static let golden = PersonalFoodDatabasePresentationTests.golden.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("personal-food-database-estimates-v2/golden.json")

    /// The route's confirmation for one entry, with its estimates bound.
    func state(_ query: String) throws -> FoodConfirmationState {
        let bytes = try Data(contentsOf: Self.golden)
        let digest = try SHA256Digester().sha256(bytes)
        let file = try PersonalFoodDatabaseCodec.decode(bytes).get()
        let store = InMemoryPersonalFoodDatabaseStore()
        try store.install(bytes: bytes, manifest: PersonalFoodDatabaseManifest(schema: file.schema.rawValue,
            releaseID: PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest), fileSHA256: digest, generated: file.generated,
            importedAt: Date(timeIntervalSince1970: 1_794_000_000), entryCount: file.entries.count))
        let index = PersonalFoodDatabaseIndex(store: store, resolver: GenericRecordResolverSet([:]))
        index.warm()
        let ids = PersonalFoodDatabasePresentationTests.IDs()
        let search = PersonalFoodDatabaseFoodSearch(index: index, resolver: GenericRecordResolverSet([:]), ids: ids,
            estimates: ApprovedEstimateManifestBuilder(ids: ids, digester: SHA256Digester()))
        guard case let .confirmation(route) = try search.search(GenericFoodSearchRequest(
            text: LedgerText(query), capturedAt: Date(timeIntervalSince1970: 1_794_000_000), locale: LedgerText("en-GB"))) else {
            throw XCTSkip("no route")
        }
        return FoodConfirmationState(input: route.confirmation, prefillSourceQuantity: false)
    }

    /// What `FoodConfirmationService.bindEstimates` does, without a ledger: verified manifests, and
    /// every cited record readable with nothing known about it.
    static func bind(_ state: inout FoodConfirmationState) {
        for candidate in state.input.candidates {
            guard let verified = ApprovedEstimateSource.verifiedManifest(candidate.candidate, evidence: state.input.evidence,
                                                                         digester: SHA256Digester()) else { continue }
            state.estimateManifests[verified.evidence.evidenceID] = verified.manifest
            for estimate in verified.manifest.estimates {
                guard let key = ApprovedEstimateRecordKey(estimate),
                      let identity = try? DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
                          drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams) else { continue }
                state.estimateRecords[key] = .identity(identity)
            }
        }
    }

    func testTheLabelListIsClosedAndNoSimilarFoodEstimateIsShownAsHigh() {
        var seen: Set<String> = []
        for method in PersonalFoodDatabaseEstimateMethod.allCases {
            for quality in PersonalFoodDatabaseEstimateQuality.allCases {
                let label = ApprovedEstimateText.label(method: method, quality: quality)
                if method == .carriedFromSimilarFood, quality == .high {
                    XCTAssertNil(label, "no label exists for a similar-food estimate at high")
                } else {
                    let text = try? XCTUnwrap(label)
                    XCTAssertTrue(text.map(ApprovedEstimateText.labels.contains) ?? false)
                    // A similar food is never shown as the food's own, and the tier is in the words.
                    XCTAssertEqual(text?.contains("similar food"), method == .carriedFromSimilarFood)
                    XCTAssertTrue(text?.hasSuffix(ApprovedEstimateText.tier(quality)) ?? false)
                    if let text { seen.insert(text) }
                }
            }
        }
        XCTAssertEqual(seen, Set(ApprovedEstimateText.labels))
        XCTAssertEqual(ApprovedEstimateText.labels.count, 5)
        XCTAssertEqual(PersonalFoodDatabaseEstimateQuality.allCases.map(ApprovedEstimateText.tier), ["good match", "some doubt", "rough"])
        // No medical wording, target or classification appears with an estimate.
        for text in ApprovedEstimateText.labels + [ApprovedEstimateText.sectionNote] {
            for word in ["healthy", "unhealthy", "target", "recommended", "risk", "should"] {
                XCTAssertFalse(text.lowercased().contains(word), text)
            }
        }
    }

    func testRowsShowTheLabelWithTheTierInWordsAndDetailsBehindIt() throws {
        var state = try state("synthetic crisps")
        Self.bind(&state)
        let rows = ApprovedEstimatePresentation.rows(state)
        XCTAssertEqual(rows.map(\.key), [.fiber, .sodium], "nutrient catalogue order")
        let fibre = rows[0], sodium = rows[1]
        XCTAssertEqual(fibre.label, "Estimated, rough")
        XCTAssertEqual(sodium.label, "Estimated, some doubt")
        XCTAssertEqual(fibre.value, "3 g")
        XCTAssertEqual(sodium.value, "500 mg")
        XCTAssertTrue(fibre.canLeaveOut && !fibre.canPutBack)
        XCTAssertNil(fibre.notice)
        // VoiceOver reads the label's text: the colour never stands alone.
        XCTAssertEqual(sodium.accessibilityLabel, "Sodium, 500 mg, Estimated, some doubt")
        XCTAssertEqual(sodium.details.first, "Food database website")
        XCTAssertTrue(sodium.details.contains("Page not read directly"))
        XCTAssertTrue(sodium.details.contains("Source describes: as sold"))
        XCTAssertTrue(sodium.details.contains("Synthetic assumption for a fixture."))
        XCTAssertEqual(sodium.details.last, "Page: https://www.example.com/products/synthetic", "identifiers last, behind details")
        XCTAssertFalse(fibre.details.contains("Page not read directly"))
        // A similar-food estimate says so in its label and its details.
        var cheese = try self.state("synthetic soft cheese")
        Self.bind(&cheese)
        let calcium = try XCTUnwrap(ApprovedEstimatePresentation.rows(cheese).first { $0.key == .calcium })
        XCTAssertEqual(calcium.label, "Estimated from a similar food, some doubt")
        XCTAssertTrue(calcium.details.contains("Estimated from a similar food"))
        XCTAssertEqual(calcium.details.first, "Food composition table")
        XCTAssertEqual(calcium.details.last, "Record: cofid cofid:cheese")
        // A candidate without an estimate has no rows.
        XCTAssertEqual(ApprovedEstimatePresentation.rows(try self.state("synthetic example oats")), [])
    }

    func testLeftOutWithheldAndUnboundRowsEachHaveTheirNotice() throws {
        var state = try state("synthetic crisps")
        Self.bind(&state)
        FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.fiber))
        var rows = ApprovedEstimatePresentation.rows(state)
        XCTAssertEqual(rows[0].status, .leftOut)
        XCTAssertEqual(rows[0].notice, "Left out by you")
        XCTAssertNil(rows[0].value, "a left-out value is not shown as a value")
        XCTAssertTrue(rows[0].canPutBack && !rows[0].canLeaveOut)
        XCTAssertEqual(rows[1].status, .offered)
        FoodConfirmationReducer.reduce(state: &state, action: .restoreEstimate(.fiber))
        XCTAssertEqual(ApprovedEstimatePresentation.rows(state)[0].status, .offered)
        // A basis change withholds every estimate, with the plain notice and the detail for Developer tools.
        let selected = state.selectedCandidate
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Millilitres)
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(FoodCorrection(name: selected.name, brand: selected.brand,
            variant: selected.variant, identity: identity, nutrients: selected.candidate.nutrients, reason: try LedgerText("details"))))
        rows = ApprovedEstimatePresentation.rows(state)
        XCTAssertEqual(rows.map(\.notice), Array(repeating: "Estimate left out: it does not match these details", count: 2))
        XCTAssertEqual(rows[0].details.last, "Left out because of: serving basis")
        XCTAssertFalse(rows[0].canLeaveOut || rows[0].canPutBack, "a withheld value offers no action")
        XCTAssertEqual(ApprovedEstimateText.notice(.unreadableRecord), "Estimate left out: its source record could not be read")
        XCTAssertEqual(ApprovedEstimateText.notice(.facet(.preparation)), "Estimate left out: it does not match these details")
        XCTAssertEqual(ApprovedEstimateText.withholdingDetail(.facet(.packingMedium)), "Left out because of: packing medium")
        // A state nobody bound has no verified manifest: nothing is shown as an estimate.
        let unbound = ApprovedEstimatePresentation.rows(try self.state("synthetic crisps"))
        XCTAssertEqual(unbound.map(\.notice), ["Evidence not available", "Evidence not available"])
        XCTAssertEqual(unbound.compactMap(\.value), [])
    }

    func testTheViewModelBindsOnOpenAndOffersOnlyLeaveOutAndPutBack() throws {
        var bound = 0
        let model = FoodConfirmationViewModel(state: try state("synthetic crisps"), estimateBinder: { state in
            bound += 1
            Self.bind(&state)
        }, saveAction: { _ in throw FoodLedgerValidationError.invalidBasis })
        XCTAssertEqual(bound, 1, "a new log's estimates are checked when it is bound to Confirm")
        XCTAssertEqual(model.estimateRows.map(\.label), ["Estimated, rough", "Estimated, some doubt"])
        model.send(.setQuantity(30, .grams))
        XCTAssertEqual(bound, 1, "a change of quantity alone is not a correction of details")
        model.send(.leaveOutEstimate(.sodium))
        XCTAssertEqual(model.state.leftOutEstimates, [.sodium])
        XCTAssertEqual(model.estimateRows[1].notice, ApprovedEstimateText.leftOutByYou)
        // The source reference section never shows a left-out value as a value.
        XCTAssertEqual(model.sourceReferenceEntries.first { $0.key == .sodium }?.value, .unknown(.noCompatibleSource))
        model.send(.restoreEstimate(.sodium))
        XCTAssertEqual(bound, 2, "undo runs the check again")
        XCTAssertEqual(model.estimateRows[1].status, .offered)
        // Both left out: Log is blocked where the rule applies, with its reason.
        model.send(.leaveOutEstimate(.sodium)); model.send(.leaveOutEstimate(.fiber))
        XCTAssertTrue(FoodLogPolicy.requirements(model.state, now: Date(), calendar: .current).contains(.nothingKnown))
        XCTAssertEqual(FoodLogRequirementText.text(.nothingKnown), "Nothing to log: every value was left out")
        // A candidate with no estimate never calls the binder again and shows no section.
        let plain = FoodConfirmationViewModel(state: try state("synthetic example oats"), estimateBinder: { _ in bound += 100 },
                                              saveAction: { _ in throw FoodLedgerValidationError.invalidBasis })
        plain.send(.setQuantity(10, .grams))
        XCTAssertEqual(plain.estimateRows, [])
        XCTAssertEqual(plain.sourceReferenceEntries, plain.state.selectedCandidate.candidate.nutrients.entries)
    }

    func testMixedSourcesNamesAnApprovedEstimateAndSettingsCountsThem() throws {
        var state = try state("synthetic serving bar")
        Self.bind(&state)
        let sources = try XCTUnwrap(FoodSearchResultText.databaseNutrientSources(state.selectedCandidate, releases: state.input.sourceReleases))
        XCTAssertTrue(sources.contains("Fibre: estimate you approved") || sources.contains("Fiber: estimate you approved"), "\(sources)")
        XCTAssertEqual(PersonalFoodDatabaseSettingsText.estimatedValues(1), "1 estimated value")
        XCTAssertEqual(PersonalFoodDatabaseSettingsText.estimatedValues(11), "11 estimated values")
        XCTAssertEqual(PersonalFoodDatabaseCodec.estimatedValueCount(try Data(contentsOf: Self.golden)), 11)
        XCTAssertEqual(PersonalFoodDatabaseCodec.estimatedValueCount(try Data(contentsOf: PersonalFoodDatabasePresentationTests.goldenV2)), 0)
    }

    private struct Clock: LedgerClock {
        func now() -> Date { Date(timeIntervalSince1970: 1_794_000_000) }
    }

    /// Invariant review, 17 November 2026: a saved estimate whose capture manifest no longer verifies
    /// is never a bare value under "Estimated values". Logged through the real save path, reopened,
    /// then read without its verified manifest.
    func testASavedEstimateWithoutVerifiedEvidenceSaysEvidenceNotAvailable() throws {
        let store = InMemoryFoodLedgerStore(encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let ledger = FoodLedgerService(actorID: try LedgerID("00000000-0000-0000-0000-00000000a511"), committer: store,
            clock: Clock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: Clock(), ids: RandomLedgerIDGenerator(),
                                              digester: SHA256Digester())
        var state = try state("synthetic crisps")
        service.bindEstimates(&state)
        let selected = state.selectedCandidate
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
        FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(FoodCorrection(name: selected.name, brand: selected.brand,
            variant: selected.variant, identity: identity, nutrients: selected.candidate.nutrients, reason: try LedgerText("details"))))
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(40, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .leaveOutEstimate(.fiber))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: try LedgerID("00000000-0000-0000-0000-00000000b511"))
        var reopened = try XCTUnwrap(try service.reopen(logItemID: saved.logItem.logItemID))
        // As saved: the kept estimate with its label, the left-out one with "Left out by you".
        var rows = ApprovedEstimatePresentation.rows(reopened)
        XCTAssertEqual(rows.map(\.label), ["Estimated, rough", "Estimated, some doubt"])
        XCTAssertEqual(rows.map(\.notice), ["Left out by you", nil])
        XCTAssertEqual(rows.map(\.value), [nil, "500 mg"])
        XCTAssertTrue(rows[0].canPutBack)
        // Without verified evidence nothing is shown as a labelled estimate, and every row says why.
        reopened.estimateManifests = [:]
        reopened.estimateSeed = ApprovedEstimateSeed(evidenceAvailable: false)
        reopened.leftOutEstimates = []
        rows = ApprovedEstimatePresentation.rows(reopened)
        XCTAssertEqual(rows.map(\.label), [nil, nil])
        XCTAssertEqual(rows.map(\.notice), ["Evidence not available", "Evidence not available"])
        XCTAssertEqual(reopened.effectiveNutrients, saved.resolutionVersion.nutrients, "no stored value changes")
    }
}
