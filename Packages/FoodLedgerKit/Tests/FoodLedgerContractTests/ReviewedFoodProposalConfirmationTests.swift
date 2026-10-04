import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class ReviewedFoodProposalConfirmationTests: XCTestCase {
    func testEveryReviewAcknowledgementIsRequired() throws {
        for acknowledgement in [FoodProposalAcknowledgement(identityAndScopeReviewed: false, basisReviewed: true, nutrientsAndUnknownsReviewed: true),
                                .init(identityAndScopeReviewed: true, basisReviewed: false, nutrientsAndUnknownsReviewed: true),
                                .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: false)] {
            XCTAssertThrowsError(try prepare(scope: .representativeEstimate, acknowledgement: acknowledgement))
        }
    }

    func testUnresolvedExactProductStillCannotSaveDespiteFullReview() throws {
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            let input = try prepare(scope: .exactProduct, serving: false)
            var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            XCTAssertFalse(state.isGenericEstimate)
            XCTAssertEqual(state.unresolvedIdentity.count, 6)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(150, .grams))
            FoodConfirmationReducer.reduce(state: &state, action: .acceptClosestMatch(try LedgerText("I reviewed the source, but have not resolved the product identity.")))
            let service = try service(harness)
            XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(801))) {
                guard case FoodConfirmationSaveError.unresolvedMandatoryIdentity = $0 else { return XCTFail("Expected identity blocker") }
            }
            XCTAssertEqual(try harness.reader.counts().operations, 0)
        }
    }

    func testReviewedEstimateKeepsOriginalDocumentAndUnknownsAcrossBothStores() throws {
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            let input = try prepare(scope: .representativeEstimate)
            var state = FoodConfirmationState(input: input)
            XCTAssertTrue(state.isGenericEstimate)
            XCTAssertFalse(state.isSourceRecipe)
            XCTAssertTrue(state.usesSourceDeclaredServing)
            XCTAssertEqual(state.quantity.unit, .count); XCTAssertNil(state.quantity.value)
            let service = try service(harness)
            XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(802)))
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(0.5, .count))
            FoodConfirmationReducer.reduce(state: &state, action: .acceptClosestMatch(try LedgerText("Half the source bowl is a representative estimate for my tofu pudding.")))
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(803))
            XCTAssertNil(saved.quantityConversion)
            XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 0.5, unit: .count))
            XCTAssertEqual(saved.resolutionVersion.methodVersion.value, "food_confirmation_v4")
            XCTAssertFalse(saved.assertions.isEmpty)
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertTrue(reopened.usesSourceDeclaredServing)
            XCTAssertTrue(reopened.isGenericEstimate)
            XCTAssertEqual(reopened.input.evidence, input.evidence)
            XCTAssertEqual(reopened.input.sourceReleases, input.sourceReleases)
            XCTAssertEqual(reopened.selectedCandidate.candidate.nutrients, input.candidates[0].candidate.nutrients)
            XCTAssertEqual(reopened.selectedCandidate.candidate.nutrients.entries.filter { if case .unknown = $0.value { true } else { false } }.count, 37)
            let totals = FoodIntakeSummary(contributions: [.init(quantity: try reopened.calculatedEdibleQuantity(),
                basis: reopened.selectedCandidate.candidate.identity.servingBasis, nutrients: reopened.selectedCandidate.candidate.nutrients)])
            XCTAssertEqual(totals.totals.first { $0.key == .energyConsumed }?.knownAmount, 75)
            XCTAssertEqual(totals.totals.first { $0.key == .protein }?.knownAmount, 3)
            XCTAssertNil(totals.totals.first { $0.key == .sodium }?.knownAmount)
            XCTAssertTrue(totals.totals.first { $0.key == .energyConsumed }?.includesEstimates == true)
            if case let .text(text) = input.evidence[0].originalPayload {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
                let manifest = try decoder.decode(FoodProposalReviewManifest.self, from: Data(text.value.utf8))
                XCTAssertEqual(manifest.scope, .representativeEstimate)
                XCTAssertEqual(manifest.document.blocks.first?.text, "豆花 每份一碗 熱量150大卡 蛋白質6公克")
                XCTAssertEqual(manifest.candidate.basis.label, "每份一碗")
                XCTAssertEqual(try SHA256Digester().sha256(Data(text.value.utf8)), input.evidence[0].byteHash)
            } else { XCTFail("Missing retained review manifest") }
        }
    }

    func testExplicitProductIdentityCorrectionCanSaveWithoutChangingSourceFacts() throws {
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            let input = try prepare(scope: .exactProduct, serving: false)
            let candidate = input.candidates[0]
            var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable,
                skin: .notApplicable, drained: .notApplicable, packingMedium: .named(LedgerText("none")),
                fortification: .unfortified, servingBasis: candidate.candidate.identity.servingBasis)
            let correction = try FoodCorrection(name: candidate.name, brand: candidate.brand, variant: candidate.variant,
                identity: identity, itemClass: .food, nutrients: candidate.candidate.nutrients,
                reason: LedgerText("Synthetic user inspection resolved the product identity; source nutrients are unchanged."))
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(correction))
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(150, .grams))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            XCTAssertTrue(state.unresolvedIdentity.isEmpty)
            let service = try service(harness)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(804))
            let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertFalse(reopened.isGenericEstimate)
            XCTAssertEqual(reopened.input.evidence, input.evidence)
            XCTAssertEqual(reopened.input.sourceReleases, input.sourceReleases)
            XCTAssertEqual(reopened.selectedCandidate.candidate.nutrients, candidate.candidate.nutrients)
            XCTAssertEqual(reopened.selectedCandidate.candidate.identity.preparation.kind, .unknown)
            XCTAssertEqual(reopened.reopened?.productVersion.identity, identity)
            XCTAssertFalse(saved.assertions.isEmpty)
        }
    }

    func testSourceServingCannotBeReinterpretedAsWeightOrVolume() throws {
        let input = try prepare(scope: .representativeEstimate)
        for unit in [QuantityUnit.grams, .millilitres] {
            var state = FoodConfirmationState(input: input)
            state.quantity.value = 150; state.quantity.unit = unit
            XCTAssertThrowsError(try state.calculatedEdibleQuantity())
        }
        var state = FoodConfirmationState(input: input)
        state.quantity.value = 1; state.quantity.directWeight = .init(totalGrams: 150, basis: .estimated)
        XCTAssertThrowsError(try state.calculatedEdibleQuantity())
        XCTAssertThrowsError(try FoodQuantityDraft(value: 1, unit: .count).calculatedEdibleQuantity())
    }

    func testCorrectionsCannotChangeReviewedNutrientsOrTheirDenominator() throws {
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            for mutation in ["nutrients", "basis"] {
                let input = try prepare(scope: .representativeEstimate, serving: false)
                let candidate = input.candidates[0]
                let original = candidate.candidate.identity
                let identity = try DecisiveIdentity(preparation: original.preparation, bone: original.bone,
                    skin: original.skin, drained: original.drained, packingMedium: original.packingMedium,
                    fortification: original.fortification, servingBasis: mutation == "basis" ? .per100Millilitres : original.servingBasis)
                let nutrients = try NutrientSet(entries: candidate.candidate.nutrients.entries.map { entry in
                    mutation == "nutrients" && entry.key == .protein ? try NutrientEntry(key: .protein, value: .unknown(.notDeclared)) : entry
                })
                var state = FoodConfirmationState(input: input)
                let correction = try FoodCorrection(name: candidate.name, brand: candidate.brand, variant: candidate.variant,
                    identity: identity, nutrients: nutrients, reason: LedgerText("A correction cannot reuse source provenance for changed nutrition."))
                FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(correction))
                FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(150, mutation == "basis" ? .millilitres : .grams))
                XCTAssertThrowsError(try service(harness).save(state, operationID: LedgerFixtures.operationID(805))) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidReviewedSource)
                }
                XCTAssertEqual(try harness.reader.counts().operations, 0)
            }
        }
    }

    func testRenamedEstimateReopensWithSeparateSourceIdentityAndSupportsQuantityEdit() throws {
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            let input = try prepare(scope: .representativeEstimate)
            let candidate = input.candidates[0]
            var state = FoodConfirmationState(input: input)
            let correction = try FoodCorrection(name: LedgerText("My synthetic pudding description"), brand: LedgerText("User-observed brand"),
                variant: candidate.variant, identity: candidate.candidate.identity, nutrients: candidate.candidate.nutrients,
                reason: LedgerText("The source is a representative estimate; this is my observed product name."))
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(correction))
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(0.5, .count))
            let service = try service(harness)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(806))
            var reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertTrue(reopened.isGenericEstimate); XCTAssertTrue(reopened.usesSourceDeclaredServing)
            XCTAssertEqual(reopened.selectedCandidate.name, candidate.name)
            XCTAssertNil(reopened.selectedCandidate.brand)
            XCTAssertEqual(reopened.reopened?.productVersion.name, correction.name)
            XCTAssertEqual(reopened.reopened?.productVersion.brand, correction.brand)
            XCTAssertEqual(reopened.input.evidence, input.evidence)
            FoodConfirmationReducer.reduce(state: &reopened, action: .setQuantity(1, .count))
            let edited = try service.save(reopened, operationID: LedgerFixtures.operationID(807))
            XCTAssertEqual(edited.productVersion.name, correction.name)
            XCTAssertEqual(edited.resolutionVersion.nutrients, candidate.candidate.nutrients)
            XCTAssertEqual(edited.logItemVersion.edibleQuantity.value, 1)
        }
    }

    func testQueryPieceCountDoesNotPrefillSourceServing() throws {
        let state = FoodConfirmationState(input: try prepare(scope: .representativeEstimate), queryQuantity: FoodQueryParser.parse("2 tofu puddings").quantity)
        XCTAssertNil(state.quantity.value)
        XCTAssertEqual(state.quantity.unit, .count)
    }

    func testReviewProvenanceCannotBecomeMeasuredNutrition() throws {
        let input = try prepare(scope: .representativeEstimate)
        let entry = try XCTUnwrap(input.candidates[0].candidate.nutrients.entries.first { $0.key == .protein })
        guard case let .augmented(value) = entry.value else { return XCTFail("Expected augmentation") }
        XCTAssertEqual(value.provenance.first?.sourceKind, .reviewedWebProposal)
        XCTAssertThrowsError(try NutrientEntry(key: .protein, value: .measured(value)))
    }

    func testSchemaChangeCannotPromoteAnExactProductToAnEstimate() throws {
        let input = try prepare(scope: .exactProduct)
        let release = input.sourceReleases[0]
        let tampered = SourceRelease(sourceReleaseID: release.sourceReleaseID, sourceID: release.sourceID, releasedAt: release.releasedAt,
            artifactHash: release.artifactHash, schemaVersion: try LedgerText(ReviewedFoodProposalConfirmation.schema(.representativeEstimate)),
            pipelineVersion: release.pipelineVersion, licence: release.licence, attribution: release.attribution, manifestHash: release.manifestHash)
        let changed = try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: [tampered], candidates: input.candidates,
            expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
        XCTAssertNil(FoodReviewedWebProposalPolicy.scope(changed, candidate: input.candidates[0]))
        XCTAssertFalse(FoodConfirmationState(input: changed).isGenericEstimate)
    }

    func testAlteredManifestBytesCannotKeepTheirOriginalHashAtSave() throws {
        let original = try prepare(scope: .representativeEstimate)
        let evidence = original.evidence[0]
        guard case let .text(payload) = evidence.originalPayload else { return XCTFail("Text manifest") }
        // JSON remains valid and describes the same bound facts. Hash integrity is
        // independent of semantic binding and must still reject the changed bytes.
        let altered = try CaptureEvidence(evidenceID: evidence.evidenceID, kind: evidence.kind,
            capturedAt: evidence.capturedAt, locale: evidence.locale, captureMethod: evidence.captureMethod,
            captureMethodVersion: evidence.captureMethodVersion, originalPayload: .text(LedgerText(payload.value.replacingOccurrences(of: "tofu pudding", with: "altered food query"))),
            byteHash: evidence.byteHash)
        let input = try PopulatedFoodConfirmation(evidence: [altered], sourceReleases: original.sourceReleases,
            candidates: original.candidates, expectedIdentity: original.expectedIdentity, expectedEdibleQuantity: original.expectedEdibleQuantity)
        XCTAssertNotEqual(try SHA256Digester().sha256(Data({
            if case let .text(text) = altered.originalPayload { return text.value }; return ""
        }().utf8)), evidence.byteHash)
        XCTAssertNotNil(FoodReviewedWebProposalPolicy.scope(input, candidate: input.candidates[0]),
            "Semantic rebinding alone cannot establish the retained byte hash")
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            var state = FoodConfirmationState(input: input)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(1, .count))
            FoodConfirmationReducer.reduce(state: &state, action: .acceptClosestMatch(try LedgerText("I reviewed this representative source serving.")))
            XCTAssertThrowsError(try service(harness).save(state, operationID: LedgerFixtures.operationID(809))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidReviewedSource)
            }
            XCTAssertEqual(try harness.reader.counts().operations, 0)
        }
    }

    func testAlteredStoredManifestCannotReopenOrPassIdempotentRecovery() throws {
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            let original = try prepare(scope: .representativeEstimate)
            var state = FoodConfirmationState(input: original)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(1, .count))
            FoodConfirmationReducer.reduce(state: &state, action: .acceptClosestMatch(try LedgerText("A reviewed source serving estimate.")))
            let operation = try LedgerFixtures.operationID(810)
            let retryKey = try LedgerText("reviewed-manifest-hash")
            let saved = try service(harness).save(state, operationID: operation, idempotencyKey: retryKey)
            let evidence = saved.evidence[0]
            guard case let .text(payload) = evidence.originalPayload else { return XCTFail("Text manifest") }
            let altered = try CaptureEvidence(evidenceID: evidence.evidenceID, kind: evidence.kind,
                capturedAt: evidence.capturedAt, locale: evidence.locale, captureMethod: evidence.captureMethod,
                captureMethodVersion: evidence.captureMethodVersion,
                originalPayload: .text(LedgerText(payload.value.replacingOccurrences(of: "tofu pudding", with: "altered food query"))),
                byteHash: evidence.byteHash)
            let changed = StoredFoodConfirmation(evidence: [altered], sourceReleases: saved.sourceReleases,
                product: saved.product, productVersion: saved.productVersion, resolution: saved.resolution,
                resolutionVersion: saved.resolutionVersion, logItem: saved.logItem, logItemVersion: saved.logItemVersion,
                quantityConversion: saved.quantityConversion, plate: saved.plate, plateWeightVersion: saved.plateWeightVersion,
                candidateDecision: saved.candidateDecision, assertions: saved.assertions)
            let service = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer),
                reader: AlteredManifestReader(saved: changed), clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
            XCTAssertThrowsError(try service.reopen(logItemID: saved.logItem.logItemID)) {
                guard case FoodLedgerStoreError.integrityFailure = $0 else { return XCTFail("Expected integrity failure") }
            }
            XCTAssertThrowsError(try service.save(state, operationID: operation, idempotencyKey: retryKey)) {
                guard case FoodLedgerStoreError.integrityFailure = $0 else { return XCTFail("Expected integrity failure") }
            }
            XCTAssertEqual(try harness.reader.counts().operations, 1)
        }
    }

    func testValidManifestCannotHideAlteredStoredNutrientsDuringRecovery() throws {
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            var state = FoodConfirmationState(input: try prepare(scope: .representativeEstimate))
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(1, .count))
            FoodConfirmationReducer.reduce(state: &state, action: .acceptClosestMatch(try LedgerText("Reviewed representative serving.")))
            let operation = try LedgerFixtures.operationID(811)
            let retryKey = try LedgerText("reviewed-semantic-recovery")
            let validService = try service(harness)
            let saved = try validService.save(state, operationID: operation, idempotencyKey: retryKey)
            XCTAssertEqual(try validService.save(state, operationID: operation, idempotencyKey: retryKey), saved)
            for mutation in ["candidate_number", "wrong_reference", "wrong_capture_time", "resolution_number"] {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerFixtures.encoder.encode(saved)) as? [String: Any])
                let target = mutation == "resolution_number" ? "resolutionVersion" : "candidateDecision"
                func change(_ value: Any) -> Any {
                    if let values = value as? [Any] { return values.map(change) }
                    guard var values = value as? [String: Any] else { return value }
                    for (key, value) in values {
                        if mutation.hasSuffix("number"), key == "amount", (value as? NSNumber)?.doubleValue == 6 {
                            values[key] = 99
                        } else if mutation == "wrong_reference", key == "manifestReference" {
                            values[key] = "wrong nutrient reference"
                        } else if mutation == "wrong_capture_time", key == "capturedAt" {
                            values[key] = 0
                        } else { values[key] = change(value) }
                    }
                    return values
                }
                object[target] = change(try XCTUnwrap(object[target]))
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
                let altered = try decoder.decode(StoredFoodConfirmation.self, from: JSONSerialization.data(withJSONObject: object))
                XCTAssertNotEqual(altered, saved, mutation)
                XCTAssertEqual(altered.evidence, saved.evidence, "The original manifest and hash remain unchanged")
                let service = try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer),
                    reader: AlteredManifestReader(saved: altered), clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
                for operation in [ { try service.reopen(logItemID: saved.logItem.logItemID).map { _ in () } },
                                   { _ = try service.save(state, operationID: operation, idempotencyKey: retryKey); return Optional(()) } ] {
                    XCTAssertThrowsError(try operation(), mutation) {
                        guard case FoodLedgerStoreError.integrityFailure = $0 else { return XCTFail("Expected integrity failure") }
                    }
                }
                XCTAssertEqual(try harness.reader.counts().operations, 1)
            }
        }
    }

    func testRetainedManifestCannotAuthoriseChangedNumbersUnknownsOrIdentity() throws {
        let input = try prepare(scope: .representativeEstimate)
        let original = input.candidates[0]
        for mutation in ["declared_number", "unknown_to_zero", "name", "wrong_reference", "wrong_capture_time"] {
            let entries = try original.candidate.nutrients.entries.map { entry -> NutrientEntry in
                if ["wrong_reference", "wrong_capture_time"].contains(mutation), entry.key == .protein,
                   case let .augmented(value) = entry.value, let provenance = value.provenance.first {
                    let changed = NutrientProvenance(sourceKind: provenance.sourceKind, sourceID: provenance.sourceID,
                        sourceReleaseID: provenance.sourceReleaseID, recordID: provenance.recordID, evidenceID: provenance.evidenceID,
                        capturedAt: mutation == "wrong_capture_time" ? Date(timeIntervalSince1970: 0) : provenance.capturedAt,
                        responseHash: provenance.responseHash,
                        manifestReference: mutation == "wrong_reference" ? try LedgerText("wrong nutrient and block reference") : provenance.manifestReference)
                    return try NutrientEntry(key: entry.key, value: .augmented(ExactNutrientValue(amount: value.amount,
                        unit: value.unit, sourceValue: value.sourceValue, provenance: [changed])))
                }
                guard mutation == "declared_number" && entry.key == .protein || mutation == "unknown_to_zero" && entry.key == .sodium else { return entry }
                let template = original.candidate.nutrients.entries.first { $0.key == .protein }!
                guard case let .augmented(value) = template.value else { throw GenericFoodProposalError.invalidNutrient }
                let amount = mutation == "declared_number" ? 99.0 : 0.0
                let sourceValue = try SourceExactNutrientValue(amount: amount, unit: LedgerText(entry.key.canonicalUnit.rawValue),
                                                             basis: original.candidate.identity.servingBasis)
                return try NutrientEntry(key: entry.key, value: .augmented(ExactNutrientValue(amount: amount,
                    unit: entry.key.canonicalUnit, sourceValue: .exact(sourceValue), provenance: value.provenance)))
            }
            let changedCandidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
                sourceReleaseID: original.candidate.sourceReleaseID, recordID: original.candidate.recordID,
                identity: original.candidate.identity, edibleQuantity: original.candidate.edibleQuantity,
                nutrients: NutrientSet(entries: entries), evidenceIDs: original.candidate.evidenceIDs,
                matchMetadata: original.candidate.matchMetadata),
                name: mutation == "name" ? LedgerText("Different food") : original.name,
                brand: original.brand, variant: original.variant, itemClass: original.itemClass)
            let changed = try PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases,
                candidates: [changedCandidate], expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity)
            XCTAssertNil(FoodReviewedWebProposalPolicy.scope(changed, candidate: changedCandidate), mutation)
            XCTAssertFalse(FoodConfirmationState(input: changed).isGenericEstimate, mutation)
            let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
            for harness in harnesses {
                var state = FoodConfirmationState(input: changed)
                FoodConfirmationReducer.reduce(state: &state, action: .acceptClosestMatch(try LedgerText("A review acknowledgement cannot repair altered source facts.")))
                XCTAssertThrowsError(try service(harness).save(state, operationID: LedgerFixtures.operationID(808))) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidReviewedSource)
                }
                XCTAssertEqual(try harness.reader.counts().operations, 0)
            }
        }
    }

    private func service(_ harness: TestHarness) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: harness.reader,
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
    }
    private func prepare(scope: FoodProposalReviewScope, serving: Bool = true,
                         acknowledgement: FoodProposalAcknowledgement = .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: true)) throws -> PopulatedFoodConfirmation {
        let text = serving ? "豆花 每份一碗 熱量150大卡 蛋白質6公克" : "豆花 每100g 熱量150大卡 蛋白質6公克"
        let document = try GenericFoodDocumentProjector.project(Data(text.utf8), url: URL(string: "https://example.com/tofu")!, mediaType: "text/plain", retrievedAt: LedgerFixtures.date, origin: "synthetic_fixture")
        let ref: [[String: Any]] = [["block_id": "b1", "quote": text]]
        let values: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            let known = key == .energy || key == .protein
            return ["key": key.rawValue, "state": known ? "declared" : "unknown",
                "value": known ? (key == .energy ? "150" : "6") as Any : NSNull(), "unit": known ? key.unit as Any : NSNull(),
                "evidence": known ? ref : [], "unknown_reason": known ? NSNull() : "not_observed" as Any]
        }
        let candidate: [String: Any] = ["id": "c1", "document_id": document.id, "name": "豆花", "brand": NSNull(), "preparation": NSNull(),
            "identity_evidence": ref, "panel_evidence": ref,
            "basis": ["amount": serving ? "1" : "100", "unit": serving ? "serving" : "g", "label": serving ? "每份一碗" : "每100g", "evidence": ref],
            "nutrients": values, "limitations": []]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = try JSONSerialization.data(withJSONObject: ["version": FoodProposalExtraction.schemaVersion, "candidates": [candidate], "preferred_id": "c1"])
        let result = try FoodProposalBinding.validate(decoder.decode(FoodProposalExtraction.self, from: data), documents: [document])
        let bound = try XCTUnwrap(result.candidates.first)
        return try ReviewedFoodProposalConfirmation(ids: RandomLedgerIDGenerator(), clock: LedgerFixtures.clock,
            encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester).prepare(bound, query: "tofu pudding", scope: scope,
                acknowledgement: acknowledgement, locale: LedgerText("zh_TW"))
    }
}

private struct AlteredManifestReader: FoodConfirmationReading {
    let saved: StoredFoodConfirmation
    func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? {
        saved.sourceReleases.first { $0.sourceReleaseID == id }
    }
    func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? {
        saved.logItem.logItemID == logItemID ? saved : nil
    }
}
