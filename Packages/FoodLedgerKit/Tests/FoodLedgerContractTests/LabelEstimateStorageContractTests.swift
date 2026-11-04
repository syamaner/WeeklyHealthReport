import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import GRDB
import XCTest

/// Stored label estimate layer (label-estimate-merge-v1, #383 slice B2): save, reopen, registry,
/// archive contract 8, GRDB reader and migration v8, re-resolution. Synthetic fixtures only.
final class LabelEstimateStorageContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures

    // MARK: Fixtures

    /// The synthetic pasted label renamed as a plain dark chocolate bar (rule 1).
    private static func chocolateInput(name: String = "Synthetic dark chocolate 80%",
                                       answer: PastedLabelIdentity.FortificationAnswer = .no,
                                       evidence: Int = 9_100) throws -> PopulatedFoodConfirmation {
        let manifest = PastedLabelManifest(pastedText: F.pastedText, pastedTextSHA256: try F.textHash(),
            parserVersion: PastedLabelSource.parserVersionV2, gateVersion: PastedLabelSource.gateVersion,
            arithmeticVersion: PastedLabelSource.arithmeticVersion, conversionVersion: PastedLabelSource.conversionVersion,
            labelFormat: "taiwan_nutrition_labelling", launchScope: ["taiwan_nutrition_labelling"],
            identityMapping: try .init(fortificationAnswer: answer, servingBasis: .per100Grams), candidate: try F.candidate(),
            storedHeaderID: "h2", conversions: [F.kcal, F.sodium], flagsShown: [], corrections: [], warningsShown: [],
            name: name, brand: "Synthetic Mill")
        return try F.input(manifest, evidence: evidence)
    }

    private static let genericReleaseID = "usda-synthetic:2018-04-01"
    private static let genericRecordID = "usda-synthetic:fdc:1"

    private static func genericRelease(id: String = genericReleaseID) throws -> SourceRelease {
        SourceRelease(sourceReleaseID: try ExternalIdentifier(id), sourceID: try ExternalIdentifier("usda"),
            releasedAt: LedgerFixtures.date, artifactHash: try SHA256Digest(String(repeating: "e", count: 64)),
            schemaVersion: try LedgerText("synthetic-generic-v1"), pipelineVersion: try LedgerText("synthetic-projection-v1"),
            licence: try LedgerText("synthetic"), attribution: try LedgerText("synthetic fixture"),
            manifestHash: try SHA256Digest(String(repeating: "f", count: 64)))
    }

    private static func genericEvidence() throws -> CaptureEvidence {
        try CaptureEvidence(evidenceID: LedgerFixtures.id(9_900, EvidenceTag.self), kind: .genericSearch,
            capturedAt: LedgerFixtures.date, locale: LedgerText("en_GB"), captureMethod: LedgerText("typed_generic_food_search"),
            captureMethodVersion: LedgerText("synthetic-matcher-v1"), originalPayload: .text(LedgerText("dark chocolate 80%")))
    }

    /// A bundled generic row (`generic_composition_dataset`) with a 70 to 85% band.
    private static func genericCandidate(iron: Double = 11.9, provenanceRecordID: String = genericRecordID,
                                         name: String = "Chocolate, dark, 70-85% cacao solids") throws -> PopulatedFoodCandidate {
        func augmented(_ key: NutrientKey, _ amount: Double) throws -> NutrientValue {
            .augmented(try ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: ExternalIdentifier("usda"),
                    sourceReleaseID: ExternalIdentifier(genericReleaseID), recordID: ExternalIdentifier(provenanceRecordID))]))
        }
        let values: [NutrientKey: Double] = [.energyConsumed: 598, .protein: 7.8, .iron: iron, .magnesium: 228]
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            try NutrientEntry(key: key, value: values[key].map { try augmented(key, $0) } ?? .unknown(.notDeclared))
        })
        return try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: ExternalIdentifier(genericReleaseID),
            recordID: ExternalIdentifier(genericRecordID), identity: LedgerFixtures.identity(), edibleQuantity: .unknown,
            nutrients: nutrients, evidenceIDs: [genericEvidence().evidenceID]), name: LedgerText(name), itemClass: .food)
    }

    private static func choice(percent: Double = 80, generic: PopulatedFoodCandidate? = nil) throws -> LabelEstimateChoice {
        LabelEstimateChoice(generic: try generic ?? genericCandidate(), evidence: [try genericEvidence()],
                            sourceRelease: try genericRelease(), cocoaPercent: percent, origin: .typed)
    }

    private static func value(_ set: NutrientSet, _ key: NutrientKey) -> NutrientValue {
        set.entries.first { $0.key == key }!.value
    }

    private static func operationType(_ harness: TestHarness, _ number: Int) throws -> LedgerOperationType? {
        try harness.committer.operation(id: LedgerFixtures.operationID(number))?.operationType
    }

    // MARK: Save and reopen

    func testAV4SaveStoresBothDecisionsTheMergeAndOneCocoaAssertionAndReopens() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let input = try Self.chocolateInput()
            let label = input.candidates[0].candidate
            let service = try F.service(harness)
            let saved = try service.save(F.state(input), operationID: LedgerFixtures.operationID(9_910), estimate: Self.choice())
            XCTAssertEqual(try Self.operationType(harness, 9_910), .confirmFoodV4, harness.name)
            let layer = try XCTUnwrap(saved.estimate, harness.name)
            XCTAssertEqual(saved.resolutionVersion.decisionIDs, [saved.candidateDecision.candidateDecisionID, layer.candidateDecision.candidateDecisionID],
                           "label first (\(harness.name))")
            XCTAssertEqual(saved.resolutionVersion.sourceReleaseIDs.map(\.value), [label.sourceReleaseID.value, Self.genericReleaseID], harness.name)
            XCTAssertEqual(layer.candidateDecision.outcome, .selectedForEstimate, harness.name)
            XCTAssertEqual(saved.candidateDecision.candidate, label, "the label decision is stored unchanged (\(harness.name))")
            // Label values win; unprinted values come from the generic row with its provenance.
            XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .protein), Self.value(label.nutrients, .protein), harness.name)
            XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .iron), Self.value(try Self.genericCandidate().candidate.nutrients, .iron), harness.name)
            XCTAssertEqual(Self.value(saved.resolutionVersion.nutrients, .zinc), Self.value(label.nutrients, .zinc), "unknown stays unknown")
            XCTAssertEqual(saved.assertions.count, 1, "one assertion per save (\(harness.name))")
            let asserted = try XCTUnwrap(saved.assertions.first?.labelEstimate)
            XCTAssertEqual(asserted.cocoaPercent, 80)
            XCTAssertEqual(asserted.cocoaPercentOrigin, .typed)
            XCTAssertEqual(asserted.compatibilityVersion.value, LabelEstimateCompatibility.version)
            XCTAssertEqual(asserted.mergeVersion.value, LabelEstimateMerge.version)
            XCTAssertEqual(asserted.genericName.value, "Chocolate, dark, 70-85% cacao solids")
            XCTAssertNil(asserted.genericVariant)
            // The reader assembles the same aggregate, all decisions in position order with their evidence.
            XCTAssertEqual(try harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID), saved, harness.name)
            XCTAssertEqual(saved.sourceReleases.map(\.sourceReleaseID), [label.sourceReleaseID], "the label's releases (\(harness.name))")
            XCTAssertEqual(layer.evidence, [try Self.genericEvidence()], harness.name)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID), harness.name)
            XCTAssertEqual(reopened.input.candidates, input.candidates, harness.name)
            XCTAssertEqual(reopened.reopened?.estimate, layer, harness.name)
            // Section 8: the layered entry is "partly estimated"; its estimate status is unchanged.
            XCTAssertTrue(FoodEntryEstimateStatus.isPartlyEstimated(saved), harness.name)
            XCTAssertEqual(try service.isEstimate(saved), false, "a label source is not a generic estimate (\(harness.name))")
            let detail = try XCTUnwrap(SavedFoodEntryDetail(stored: saved, isEstimate: false, history: []).labelEstimate, harness.name)
            XCTAssertEqual(detail.releases.map(\.sourceReleaseID.value), [label.sourceReleaseID.value, Self.genericReleaseID], "both releases")
            XCTAssertEqual(detail.decisions.map(\.outcome), [saved.candidateDecision.outcome, .selectedForEstimate], "both decisions")
            XCTAssertEqual(detail.estimatedKeys, [.iron, .magnesium], "the keys the generic row filled, in catalogue order")
        }
    }

    func testEntriesWithoutALayerWriteTheirEarlierOperationTypeAndAssertionBytes() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let saved = try F.service(harness).save(F.state(Self.chocolateInput()), operationID: LedgerFixtures.operationID(9_920))
            XCTAssertEqual(try Self.operationType(harness, 9_920), .confirmFood, harness.name)
            XCTAssertNil(saved.estimate, harness.name)
            XCTAssertEqual(saved.resolutionVersion.decisionIDs.count, 1, harness.name)
            XCTAssertEqual(saved.assertions, [], harness.name)
            // Section 8: a label-only entry is never "partly estimated" and keeps its estimate status.
            XCTAssertFalse(FoodEntryEstimateStatus.isPartlyEstimated(saved), harness.name)
            XCTAssertNil(SavedFoodEntryDetail(stored: saved, isEstimate: false, history: []).labelEstimate, harness.name)
        }
        // An assertion without a layer encodes no estimate key and re-encodes byte for byte.
        let assertion = UserAssertion(assertionID: try LedgerFixtures.id(61, AssertionTag.self), author: .user,
            createdAt: LedgerFixtures.date, reason: try LedgerText("Synthetic"), claim: try LedgerText("Synthetic claim"))
        let bytes = try LedgerFixtures.encoder.encode(assertion)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("labelEstimate"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        XCTAssertEqual(try LedgerFixtures.encoder.encode(decoder.decode(UserAssertion.self, from: bytes)), bytes)
        // A stored cocoa percentage outside rule 2 never decodes.
        let layered = try UserAssertion(assertionID: LedgerFixtures.id(62, AssertionTag.self), author: .user, createdAt: LedgerFixtures.date,
            reason: LedgerText("Synthetic"), claim: LedgerText("Synthetic claim"),
            labelEstimate: LabelEstimateAssertion(cocoaPercent: 80, cocoaPercentOrigin: .name,
                compatibilityVersion: LedgerText(LabelEstimateCompatibility.version), mergeVersion: LedgerText(LabelEstimateMerge.version),
                genericName: LedgerText("Chocolate, dark, 70-85% cacao solids")))
        let text = String(decoding: try LedgerFixtures.encoder.encode(layered), as: UTF8.self)
        XCTAssertEqual(try LedgerFixtures.encoder.encode(decoder.decode(UserAssertion.self, from: Data(text.utf8))), Data(text.utf8))
        XCTAssertThrowsError(try decoder.decode(UserAssertion.self, from: Data(text.replacingOccurrences(of: #""cocoaPercent":80"#, with: #""cocoaPercent":101"#).utf8)))
        XCTAssertThrowsError(try decoder.decode(UserAssertion.self, from: Data(text.replacingOccurrences(of: #""genericName":"Chocolate, dark, 70-85% cacao solids""#, with: #""genericName":"  ""#).utf8)),
                             "the stored row name is validated like the other fields")
        for invalid in [0, 100.5, 85.55, .infinity] {
            XCTAssertThrowsError(try LabelEstimateAssertion(cocoaPercent: invalid, cocoaPercentOrigin: .typed,
                compatibilityVersion: LedgerText(LabelEstimateCompatibility.version), mergeVersion: LedgerText(LabelEstimateMerge.version),
                genericName: LedgerText("Chocolate, dark"))) {
                XCTAssertEqual($0 as? FoodLedgerValidationError, .invalidCocoaPercent, "\(invalid)")
            }
            XCTAssertFalse(LabelEstimateCompatibility.isValidPercent(invalid), "one rule (\(invalid))")
        }
    }

    func testDeclarationsAndInlineDecisionsKeepTheirTypesWithoutALayerAndRideAlongUnderV4() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            func declared() throws -> FoodConfirmationState {
                var state = F.state(try Self.chocolateInput())
                state.quantity.directWeight = DirectWeightDraft(totalGrams: 40, basis: .measured)
                return state
            }
            func decided() throws -> FoodConfirmationState { F.state(try Self.chocolateInput(answer: .unanswered, evidence: 9_101)) }
            let cases: [(String, () throws -> FoodConfirmationState, LedgerOperationType)] = [
                ("declaration", declared, .confirmFoodV2), ("inline decisions", decided, .confirmFoodV3)]
            for (offset, (name, make, plainType)) in cases.enumerated() {
                let plain = try service.save(make(), operationID: LedgerFixtures.operationID(9_920 + 2 * offset + 100))
                XCTAssertEqual(try Self.operationType(harness, 9_920 + 2 * offset + 100), plainType, "\(name) (\(harness.name))")
                XCTAssertNil(plain.estimate)
                let layered = try service.save(make(), operationID: LedgerFixtures.operationID(9_921 + 2 * offset + 100), estimate: Self.choice())
                XCTAssertEqual(try Self.operationType(harness, 9_921 + 2 * offset + 100), .confirmFoodV4, "\(name) (\(harness.name))")
                if plainType == .confirmFoodV2 {
                    XCTAssertNotNil(layered.logItemVersion.weightDeclaration, harness.name)
                } else {
                    XCTAssertNotNil(layered.assertions.first?.confirmation, harness.name)
                    XCTAssertEqual(layered.assertions.count, 1, "one assertion carries decisions and cocoa (\(harness.name))")
                }
                XCTAssertEqual(try harness.reader.foodConfirmation(logItemID: layered.logItem.logItemID), layered, "\(name) (\(harness.name))")
                let reopened = try XCTUnwrap(service.reopen(logItemID: layered.logItem.logItemID), "\(name) (\(harness.name))")
                XCTAssertEqual(reopened.reopened?.estimate, layered.estimate, "\(name) (\(harness.name))")
                XCTAssertEqual(try service.save(reopened, operationID: LedgerFixtures.operationID(9_930 + offset + 100)).estimate,
                               layered.estimate, "an unchanged re-save keeps the layer (\(name), \(harness.name))")
            }
            // Round trip: the store holding both cases exports contract 8 and restores byte for byte.
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let bundle = try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("estimate-cases"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            XCTAssertEqual(try FoodArchiveVerifier().verify(bundle).manifest.foodContractVersion, 8, harness.name)
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                XCTAssertEqual(try FoodArchiveGenerator().generate(state: live.archiveState(), ledgerID: LedgerText("estimate-cases"),
                    createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self)), bundle,
                    "\(harness.name)->\(destination.name)")
            }
        }
    }

    func testRetryingAV4SaveReturnsTheStoredEntry() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let state = F.state(try Self.chocolateInput())
            let key = try LedgerText("label-estimate-retry")
            let first = try service.save(state, operationID: LedgerFixtures.operationID(9_930), idempotencyKey: key, estimate: Self.choice())
            let again = try service.save(state, operationID: LedgerFixtures.operationID(9_930), idempotencyKey: key, estimate: Self.choice())
            XCTAssertEqual(again, first, harness.name)
        }
    }

    func testSaveRefusesAnEstimateThatRulesOneOrThreeDoNotAdmit() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let state = F.state(try Self.chocolateInput())
            let refused: [(String, FoodConfirmationState, LabelEstimateChoice)] = [
                ("outside the row's band", state, try Self.choice(percent: 60)),
                ("a milk chocolate row", state, try Self.choice(generic: Self.genericCandidate(name: "Chocolate, milk, 70-85% cacao solids"))),
                ("a milk chocolate label", F.state(try Self.chocolateInput(name: "Synthetic milk chocolate 80%")), try Self.choice()),
                ("a copied value naming another record", state, try Self.choice(generic: Self.genericCandidate(provenanceRecordID: "usda-synthetic:fdc:2")))
            ]
            for (index, (name, candidateState, choice)) in refused.enumerated() {
                XCTAssertThrowsError(try service.save(candidateState, operationID: LedgerFixtures.operationID(9_940 + index), estimate: choice),
                                     "\(name) (\(harness.name))") {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidLabelEstimate, "\(name) (\(harness.name))")
                }
            }
            // A reopened entry cannot gain an estimate (re-estimating saved entries is out of scope).
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(9_948))
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertThrowsError(try service.save(reopened, operationID: LedgerFixtures.operationID(9_949), estimate: Self.choice())) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidLabelEstimate, harness.name)
            }
        }
    }

    func testAnEditKeepsTheLayerAsV4AndACorrectionDropsIt() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try F.service(harness)
            let saved = try service.save(F.state(Self.chocolateInput()), operationID: LedgerFixtures.operationID(9_950), estimate: Self.choice())
            var edit = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &edit, action: .setQuantity(100, .grams))
            let edited = try service.save(edit, operationID: LedgerFixtures.operationID(9_951))
            XCTAssertEqual(try Self.operationType(harness, 9_951), .confirmFoodV4, harness.name)
            XCTAssertEqual(edited.estimate, saved.estimate, harness.name)
            XCTAssertEqual(try harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID), edited, harness.name)
            var corrected = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            let source = corrected.input.candidates[0]
            FoodConfirmationReducer.reduce(state: &corrected, action: .applyCorrection(try FoodCorrection(name: LedgerText("Renamed bar"),
                brand: nil, variant: nil, identity: source.candidate.identity, itemClass: .food, nutrients: source.candidate.nutrients,
                reason: LedgerText("Synthetic rename; the label values are unchanged."))))
            let dropped = try service.save(corrected, operationID: LedgerFixtures.operationID(9_952))
            XCTAssertEqual(try Self.operationType(harness, 9_952), .confirmFood, harness.name)
            XCTAssertNil(dropped.estimate, harness.name)
            XCTAssertEqual(dropped.resolutionVersion.nutrients, source.candidate.nutrients, harness.name)
            XCTAssertNotNil(try service.reopen(logItemID: saved.logItem.logItemID), harness.name)
        }
    }

    func testAlteredLabelGenericDecisionMergedEntryOrCocoaAssertionFailsReopen() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let saved = try F.service(harness).save(F.state(Self.chocolateInput()), operationID: LedgerFixtures.operationID(9_960),
                                                    estimate: Self.choice())
            let layer = try XCTUnwrap(saved.estimate)
            let label = try Self.chocolateInput().candidates[0]
            func decision(_ generic: PopulatedFoodCandidate) throws -> CandidateDecision {
                try CandidateDecision(candidateDecisionID: layer.candidateDecision.candidateDecisionID, candidate: generic.candidate,
                    expectedIdentity: layer.candidateDecision.expectedIdentity, expectedEdibleQuantity: layer.candidateDecision.expectedEdibleQuantity,
                    requestedOutcome: .selectedForEstimate, assertionID: layer.candidateDecision.assertionID, createdAt: layer.candidateDecision.createdAt)
            }
            func merged(_ generic: PopulatedFoodCandidate) throws -> NutrientSet {
                try XCTUnwrap(LabelEstimateMerge.merge(label: label.candidate.nutrients, labelBasis: .per100Grams,
                                                       generic: generic.candidate.nutrients, genericBasis: .per100Grams)).nutrients
            }
            let otherRecord = try Self.genericCandidate(provenanceRecordID: "usda-synthetic:fdc:2")
            let asserted = try XCTUnwrap(saved.assertions.first?.labelEstimate)
            let staleVersion = try LabelEstimateAssertion(cocoaPercent: asserted.cocoaPercent, cocoaPercentOrigin: asserted.cocoaPercentOrigin,
                compatibilityVersion: LedgerText("label-estimate-compatibility-v0"), mergeVersion: asserted.mergeVersion,
                genericName: asserted.genericName, genericVariant: asserted.genericVariant)
            let tampered: [(String, StoredFoodConfirmation)] = [
                ("altered label manifest", try PastedLabelContractTests.rewriteStored(saved, replacing: "60.1公克", with: "61.0公克")),
                ("altered generic decision", try Self.rebuilt(saved, estimate: StoredLabelEstimate(candidateDecision: decision(Self.genericCandidate(iron: 12.5)),
                    evidence: layer.evidence, sourceRelease: layer.sourceRelease))),
                ("copied entry naming another record", try Self.rebuilt(saved, nutrients: merged(otherRecord),
                    estimate: StoredLabelEstimate(candidateDecision: decision(otherRecord), evidence: layer.evidence, sourceRelease: layer.sourceRelease))),
                ("altered merged entry", try Self.rebuilt(saved, nutrients: merged(Self.genericCandidate(iron: 12.5)))),
                ("another release", try Self.rebuilt(saved, estimate: StoredLabelEstimate(candidateDecision: layer.candidateDecision,
                    evidence: layer.evidence, sourceRelease: Self.genericRelease(id: "usda-synthetic:other")))),
                ("cocoa assertion removed", try Self.rebuilt(saved, assertions: [])),
                ("cocoa assertion version altered", try Self.rebuilt(saved, assertions: [Self.reasserted(saved.assertions[0], staleVersion)])),
                ("layer removed, assertion kept", try Self.rebuilt(saved, estimate: .some(nil)))
            ]
            for (name, stored) in tampered {
                XCTAssertThrowsError(try Self.service(harness, stored).reopen(logItemID: saved.logItem.logItemID), "\(name) (\(harness.name))") {
                    guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\(name): \($0)") }
                }
            }
            // Control, and a withdrawn generic release: reopen never consults the bundle or the installed releases.
            XCTAssertNotNil(try Self.service(harness, saved, withdrawn: true).reopen(logItemID: saved.logItem.logItemID), harness.name)
        }
    }

    func testAStoredPercentageOrRowNameThatRuleThreeDoesNotAdmitFailsReopen() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let saved = try F.service(harness).save(F.state(Self.chocolateInput()), operationID: LedgerFixtures.operationID(9_965),
                                                    estimate: Self.choice())
            let asserted = try XCTUnwrap(saved.assertions.first?.labelEstimate)
            func stored(percent: Double = 80, name: String = "Chocolate, dark, 70-85% cacao solids") throws -> StoredFoodConfirmation {
                try Self.rebuilt(saved, assertions: [Self.reasserted(saved.assertions[0], LabelEstimateAssertion(cocoaPercent: percent,
                    cocoaPercentOrigin: asserted.cocoaPercentOrigin, compatibilityVersion: asserted.compatibilityVersion,
                    mergeVersion: asserted.mergeVersion, genericName: LedgerText(name), genericVariant: asserted.genericVariant))])
            }
            let refused: [(String, StoredFoodConfirmation)] = [
                ("a 70 to 85% row stored with 60%", try stored(percent: 60)),
                ("an altered stored name outside the band", try stored(name: "Chocolate, dark, 45-59% cacao solids")),
                ("an altered stored name naming milk chocolate", try stored(name: "Chocolate, milk, 70-85% cacao solids")),
                ("an altered stored name with no band", try stored(name: "Chocolate, dark"))
            ]
            for (name, record) in refused {
                XCTAssertThrowsError(try Self.service(harness, record).reopen(logItemID: saved.logItem.logItemID), "\(name) (\(harness.name))") {
                    guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\(name): \($0)") }
                }
            }
            // Control: another percentage inside the stored row's band still reopens.
            XCTAssertNotNil(try Self.service(harness, stored(percent: 75)).reopen(logItemID: saved.logItem.logItemID), harness.name)
        }
    }

    // MARK: Registry

    func testBuiltInV8AdmitsV4AndOlderRegistriesRejectIt() throws {
        var mutation = try LedgerFixtures.baseMutation()
        let record = try FoodLogDecisionRecord(policyVersion: LedgerText("food_confirmation_v5"), decisions: [
            FoodLogFacetDecision(facet: .preparation, sourceState: FoodLogSourceState(facet: .preparation, token: "as_sold"), choice: .notSure)])
        let estimate = try LabelEstimateAssertion(cocoaPercent: 85.5, cocoaPercentOrigin: .pastedText,
            compatibilityVersion: LedgerText(LabelEstimateCompatibility.version), mergeVersion: LedgerText(LabelEstimateMerge.version),
            genericName: LedgerText("Chocolate, dark, 70-85% cacao solids"))
        mutation.assertions = [UserAssertion(assertionID: try LedgerFixtures.id(63, AssertionTag.self), author: .user,
            createdAt: LedgerFixtures.date, reason: try LedgerText("Synthetic"), claim: try LedgerText("Synthetic claim"),
            confirmation: record, labelEstimate: estimate)]
        let resolutionVersionID = try XCTUnwrap(mutation.resolutionVersions.first?.resolutionVersionID)
        mutation.logItemVersions = [try LogItemVersion(logItemVersionID: LedgerFixtures.id(64, LogItemVersionTag.self),
            logItemID: LedgerFixtures.id(65, LogItemTag.self), ordinal: VersionOrdinal(1), occurredAt: LedgerFixtures.date,
            reportingDate: LedgerText("2023-11-14"), composition: .product(LedgerFixtures.id(3, ProductVersionTag.self)),
            edibleQuantity: PositiveQuantity(value: 40, unit: .grams),
            weightDeclaration: EdibleWeightDeclaration(basis: .measured, total: PositiveQuantity(value: 40, unit: .grams), originalInput: nil),
            originalResolutionVersionID: resolutionVersionID, effectiveResolutionVersionID: resolutionVersionID, createdAt: LedgerFixtures.date)]
        let plain = mutation
        let label = try Self.decision(71, .rejected), estimateDecision = try Self.decision(72, .selectedForEstimate)
        mutation = try Self.withDecisions(mutation, [label, estimateDecision])
        XCTAssertTrue(LedgerOperationType.declaredQuantityTypes.contains(.confirmFoodV4))
        XCTAssertEqual(LedgerOperationType.confirmFoodV4.rawValue, "confirm_food_v4")
        XCTAssertNoThrow(try LedgerOperationRegistry.builtInV8.requireSupported(.confirmFoodV4, mutation: mutation))
        for registry in [LedgerOperationRegistry.builtInV3, .builtInV4, .builtInV6] {
            XCTAssertThrowsError(try registry.requireSupported(.confirmFoodV4))
        }
        // A cocoa assertion is carried only by V4; V3 rules are unchanged.
        for type in [LedgerOperationType.confirmFood, .confirmFoodV2, .confirmFoodV3, .createProduct] {
            XCTAssertThrowsError(try LedgerOperationRegistry.builtInV8.requireSupported(type, mutation: mutation), type.rawValue)
        }
        var decidedOnly = plain
        decidedOnly.assertions = [UserAssertion(assertionID: try LedgerFixtures.id(66, AssertionTag.self), author: .user,
            createdAt: LedgerFixtures.date, reason: try LedgerText("Synthetic"), claim: try LedgerText("Synthetic claim"), confirmation: record)]
        XCTAssertNoThrow(try LedgerOperationRegistry.builtInV8.requireSupported(.confirmFoodV3, mutation: decidedOnly))
        XCTAssertNoThrow(try LedgerOperationRegistry.builtInV4.requireSupported(.confirmFoodV3, mutation: decidedOnly))
        // V4 that writes a resolution must carry its cocoa assertion; an edit that keeps the layer writes none.
        XCTAssertThrowsError(try LedgerOperationRegistry.builtInV8.requireSupported(.confirmFoodV4, mutation: decidedOnly))
        XCTAssertNoThrow(try LedgerOperationRegistry.builtInV8.requireSupported(.confirmFoodV4,
            mutation: LedgerMutation(logItemVersions: mutation.logItemVersions)))
        XCTAssertEqual(CanonicalFoodProjection.minimumContractVersion(for: mutation), 8)
    }

    func testTheRegistryAdmitsTwoDecisionsAndAnEstimateDecisionOnlyAsAV4Layer() throws {
        let v8 = LedgerOperationRegistry.builtInV8
        let estimate = try LabelEstimateAssertion(cocoaPercent: 80, cocoaPercentOrigin: .typed,
            compatibilityVersion: LedgerText(LabelEstimateCompatibility.version), mergeVersion: LedgerText(LabelEstimateMerge.version),
            genericName: LedgerText("Chocolate, dark, 70-85% cacao solids"))
        func cocoa(_ number: Int) throws -> UserAssertion {
            UserAssertion(assertionID: try LedgerFixtures.id(number, AssertionTag.self), author: .user, createdAt: LedgerFixtures.date,
                reason: try LedgerText("Synthetic"), claim: try LedgerText("Synthetic claim"), labelEstimate: estimate)
        }
        let label = try Self.decision(73, .rejected), generic = try Self.decision(74, .selectedForEstimate)
        var layered = try Self.withDecisions(LedgerFixtures.baseMutation(), [label, generic])
        layered.assertions = [try cocoa(75)]
        XCTAssertNoThrow(try v8.requireSupported(.confirmFoodV4, mutation: layered))
        // A two-decision resolution, or an estimate decision, outside V4.
        var noCocoa = layered
        noCocoa.assertions = []
        for type in [LedgerOperationType.confirmFood, .confirmFoodV2, .createProduct, .correctResolution] {
            XCTAssertThrowsError(try v8.requireSupported(type, mutation: noCocoa), type.rawValue)
        }
        // A V4 cocoa assertion with a single-decision resolution, or without the estimate decision second.
        var single = try Self.withDecisions(LedgerFixtures.baseMutation(), [label])
        single.assertions = [try cocoa(76)]
        XCTAssertThrowsError(try v8.requireSupported(.confirmFoodV4, mutation: single))
        var reversed = try Self.withDecisions(LedgerFixtures.baseMutation(), [generic, label])
        reversed.assertions = [try cocoa(77)]
        XCTAssertThrowsError(try v8.requireSupported(.confirmFoodV4, mutation: reversed), "estimate decision first")
        var twoLabels = try Self.withDecisions(LedgerFixtures.baseMutation(), [label, try Self.decision(78, .rejected)])
        twoLabels.assertions = [try cocoa(79)]
        XCTAssertThrowsError(try v8.requireSupported(.confirmFoodV4, mutation: twoLabels), "second decision not an estimate")
        var twoCocoa = layered
        twoCocoa.assertions = [try cocoa(80), try cocoa(81)]
        XCTAssertThrowsError(try v8.requireSupported(.confirmFoodV4, mutation: twoCocoa), "exactly one cocoa assertion")
        XCTAssertThrowsError(try v8.requireSupported(.confirmFoodV4, mutation: noCocoa), "a V4 layer needs its cocoa assertion")
    }

    func testALoneOrLeadingEstimateDecisionFailsToAssemble() throws {
        let label = try Self.decision(82, .rejected), generic = try Self.decision(83, .selectedForEstimate)
        var releases = [try Self.genericRelease()]
        XCTAssertNil(try StoredLabelEstimate.assembled(decisions: [label], evidence: [[]], releases: &releases))
        for decisions in [[generic], [generic, label]] {
            var releases = [try Self.genericRelease()]
            XCTAssertThrowsError(try StoredLabelEstimate.assembled(decisions: decisions, evidence: decisions.map { _ in [] },
                                                                   releases: &releases)) {
                guard case .integrityFailure = $0 as? FoodLedgerStoreError else { return XCTFail("\($0)") }
            }
        }
    }

    // MARK: Archive

    func testContractEightArchiveRoundTripsAndOlderReadersRejectIt() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            _ = try F.service(harness).save(F.state(Self.chocolateInput()), operationID: LedgerFixtures.operationID(9_970))
            let labelOnly = try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("estimate"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            XCTAssertEqual(try FoodArchiveVerifier().verify(labelOnly).manifest.foodContractVersion, 7, "no layer: contract 7 (\(harness.name))")
            let saved = try F.service(harness).save(F.state(Self.chocolateInput()), operationID: LedgerFixtures.operationID(9_971),
                                                    estimate: Self.choice())
            let bundle = try FoodArchiveGenerator().generate(state: archive.archiveState(), ledgerID: LedgerText("estimate"),
                createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
            let verified = try FoodArchiveVerifier().verify(bundle)
            XCTAssertEqual(verified.manifest.foodContractVersion, 8, harness.name)
            XCTAssertEqual(verified.manifest.migrationIdentifiers.map(\.value).last, "food-ledger-v8", harness.name)
            // A contract-7 binary admits no V4 operation and cannot carry the layer.
            XCTAssertThrowsError(try FoodArchiveVerifier(operationRegistry: .builtInV6).verify(bundle), harness.name)
            XCTAssertThrowsError(try CanonicalFoodProjection(records: archive.archiveState().records, foodContractVersion: 7)) {
                XCTAssertEqual($0 as? FoodArchiveError, .unsupportedFoodContract(7))
            }
            for destination in try LedgerFixtures.harnesses() {
                defer { destination.cleanup() }
                let live = try XCTUnwrap(destination.committer as? any FoodArchiveLedgerAccess)
                let importer = FoodArchiveImportService(live: live, staging: InMemoryFoodArchiveStaging())
                _ = try importer.apply(importer.dryRun(bundle))
                let again = try FoodArchiveGenerator().generate(state: live.archiveState(), ledgerID: LedgerText("estimate"),
                    createdAt: LedgerFixtures.date, creatingActorID: LedgerFixtures.id(900, ActorTag.self))
                XCTAssertEqual(again, bundle, "\(harness.name)->\(destination.name)")
                let reopened = try XCTUnwrap(F.service(destination).reopen(logItemID: saved.logItem.logItemID))
                XCTAssertEqual(reopened.reopened?.estimate, saved.estimate, "\(harness.name)->\(destination.name)")
            }
        }
    }

    // MARK: GRDB

    func testMigrationFromAPopulatedV7StoreChangesOnlyLedgerMetadata() throws {
        XCTAssertEqual(FoodLedgerGRDBStore.schemaVersion, 8)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("estimate-v8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("food-ledger-v1.sqlite")
        do {
            let store = try FoodLedgerGRDBStore.temporary(directory: directory)
            _ = try F.service(TestHarness(name: "grdb", committer: store, reader: store, cleanup: {}))
                .save(F.state(Self.chocolateInput()), operationID: LedgerFixtures.operationID(9_980))
        }
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v8_label_estimate'")
            try db.execute(sql: "UPDATE ledger_metadata SET value = 'food-ledger-v7' WHERE key = 'schema_identity'")
            try db.execute(sql: "PRAGMA user_version = 7")
        }
        let before = try Self.tableRows(queue)
        let schemaBefore = try queue.read { try String.fetchAll($0, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name") }
        try queue.close()
        let migrated = try FoodLedgerGRDBStore.temporary(directory: directory)
        try migrated.verifyIntegrity()
        let check = try DatabaseQueue(path: database.path)
        let after = try Self.tableRows(check)
        XCTAssertEqual(Set(before.keys.filter { before[$0] != after[$0] }), ["ledger_metadata"], "Only ledger_metadata may change")
        XCTAssertEqual(try check.read { try String.fetchAll($0, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name") },
                       schemaBefore, "No table, index or trigger definition changes")
        try check.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version"), 8)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM ledger_metadata WHERE key = 'schema_identity'"), "food-ledger-v8")
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid").last, "v8_label_estimate")
        }
    }

    // MARK: Re-resolution

    func testReresolutionIsRefusedForALayeredEntry() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let saved = try F.service(harness).save(F.state(Self.chocolateInput()), operationID: LedgerFixtures.operationID(9_990),
                                                    estimate: Self.choice())
            let target = FoodReresolutionTarget(sourceRelease: try Self.genericRelease(), methodVersion: try LedgerText("synthetic-v2"))
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let service = FoodReresolutionService(ledger: try LedgerFixtures.service(harness.committer),
                reader: FoodReresolutionHistory(archive: archive, confirmations: harness.reader),
                provider: UnreachableReresolutionProvider(target: target), clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator())
            XCTAssertThrowsError(try service.proposals(logItemID: saved.logItem.logItemID, target: target), harness.name) {
                XCTAssertEqual($0 as? FoodReresolutionError, .labelEstimateLayer, harness.name)
            }
        }
    }

    // MARK: Helpers

    /// A decision on a synthetic row with no evidence (registry and assembly checks only).
    private static func decision(_ number: Int, _ outcome: CandidateOutcome) throws -> CandidateDecision {
        let generic = try genericCandidate().candidate
        let candidate = try ProviderNeutralCandidate(sourceReleaseID: ExternalIdentifier(outcome == .selectedForEstimate ? genericReleaseID : "package:fixture-v1"),
            recordID: generic.recordID, identity: generic.identity, edibleQuantity: generic.edibleQuantity, nutrients: generic.nutrients)
        return try CandidateDecision(candidateDecisionID: LedgerFixtures.id(number, CandidateDecisionTag.self), candidate: candidate,
            expectedIdentity: LedgerFixtures.identity(), expectedEdibleQuantity: .unknown, requestedOutcome: outcome, createdAt: LedgerFixtures.date)
    }

    /// The base mutation with its resolution version citing `decisions` in order.
    private static func withDecisions(_ base: LedgerMutation, _ decisions: [CandidateDecision]) throws -> LedgerMutation {
        var mutation = base
        mutation.resolutionVersions = try base.resolutionVersions.map { version in
            try NutritionResolutionVersion(resolutionVersionID: version.resolutionVersionID, resolutionID: version.resolutionID,
                ordinal: version.ordinal, methodVersion: version.methodVersion, sourceReleaseIDs: version.sourceReleaseIDs,
                nutrients: version.nutrients, decisionIDs: decisions.map(\.candidateDecisionID), assertionIDs: version.assertionIDs,
                createdAt: version.createdAt)
        }
        mutation.candidateDecisions = decisions
        return mutation
    }

    private static func service(_ harness: TestHarness, _ stored: StoredFoodConfirmation, withdrawn: Bool = false) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: LayeredReader(saved: stored, withdrawn: withdrawn),
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester,
            pastedLabelConversions: GoldenPastedLabelConversions())
    }

    private static func rebuilt(_ saved: StoredFoodConfirmation, nutrients: NutrientSet? = nil, assertions: [UserAssertion]? = nil,
                                estimate: StoredLabelEstimate?? = .none) throws -> StoredFoodConfirmation {
        let version = saved.resolutionVersion
        let resolutionVersion = try NutritionResolutionVersion(resolutionVersionID: version.resolutionVersionID, resolutionID: version.resolutionID,
            ordinal: version.ordinal, methodVersion: version.methodVersion, sourceReleaseIDs: version.sourceReleaseIDs,
            nutrients: nutrients ?? version.nutrients, decisionIDs: version.decisionIDs, assertionIDs: version.assertionIDs, createdAt: version.createdAt)
        return StoredFoodConfirmation(evidence: saved.evidence, sourceReleases: saved.sourceReleases, product: saved.product,
            productVersion: saved.productVersion, resolution: saved.resolution, resolutionVersion: resolutionVersion, logItem: saved.logItem,
            logItemVersion: saved.logItemVersion, quantityConversion: saved.quantityConversion, plate: saved.plate,
            plateWeightVersion: saved.plateWeightVersion, candidateDecision: saved.candidateDecision,
            assertions: assertions ?? saved.assertions, estimate: estimate ?? saved.estimate)
    }

    private static func reasserted(_ assertion: UserAssertion, _ estimate: LabelEstimateAssertion) -> UserAssertion {
        UserAssertion(assertionID: assertion.assertionID, evidenceID: assertion.evidenceID, supersedesAssertionID: assertion.supersedesAssertionID,
            author: assertion.author, createdAt: assertion.createdAt, reason: assertion.reason, claim: assertion.claim,
            confirmation: assertion.confirmation, labelEstimate: estimate)
    }

    private static func tableRows(_ queue: DatabaseQueue) throws -> [String: [String]] {
        try queue.read { db in
            var result: [String: [String]] = [:]
            for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'") {
                result[table] = try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"").map { row in
                    row.columnNames.map { "\($0)=\(row[$0] as DatabaseValue)" }.joined(separator: "|")
                }.sorted()
            }
            return result
        }
    }
}

/// Serves one stored aggregate. `withdrawn` hides the generic release, as if it were no longer installed.
private struct LayeredReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    let withdrawn: Bool
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? {
        (saved.sourceReleases + (withdrawn ? [] : saved.estimate.map { [$0.sourceRelease] } ?? [])).first { $0.sourceReleaseID == id }
    }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { logItemID == saved.logItem.logItemID ? saved : nil }
    func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? {
        logItemVersionID == saved.logItemVersion.logItemVersionID ? saved : nil
    }
    func evidence(id: EvidenceID) throws -> CaptureEvidence? { saved.evidence.first { $0.evidenceID == id } }
}

private struct UnreachableReresolutionProvider: FoodReresolutionProviding {
    let target: FoodReresolutionTarget
    func targets() throws -> [FoodReresolutionTarget] { [target] }
    func candidates(for record: StoredFoodConfirmation, target: FoodReresolutionTarget, at: Date) throws -> GenericFoodSearchOutcome {
        XCTFail("a layered entry never reaches candidate discovery")
        throw FoodReresolutionError.unavailableTarget
    }
}
