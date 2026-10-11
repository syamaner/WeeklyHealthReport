import Foundation
import FoodGenericSearch
@_spi(ReviewedWebRegression) import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Every reviewed-source contract runs against manifest v1 (this class, frozen shape written by
/// released builds) and manifest v2 (`ReviewedFoodProposalConfirmationV2Tests`, single review
/// action and recorded gate). Contract test 6 of generic-food-review-manifest-v2.md.
class ReviewedFoodProposalConfirmationTests: XCTestCase {
    var manifestVersion: String { ReviewedFoodProposalConfirmation.version1 }

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
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let service = try service(harness)
            XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(801))) {
                guard case let FoodConfirmationSaveError.unmetRequirements(unmet) = $0,
                      unmet.contains(where: { if case .sourceIdentityMissing = $0 { true } else { false } }) else { return XCTFail("Expected identity blocker") }
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
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(803))
            XCTAssertNil(saved.quantityConversion)
            XCTAssertEqual(saved.logItemVersion.edibleQuantity, try PositiveQuantity(value: 0.5, unit: .count))
            XCTAssertEqual(saved.resolutionVersion.methodVersion.value, "food_confirmation_v5")
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
                let manifest = try XCTUnwrap(FoodProposalReviewManifestRecord.decode(Data(text.value.utf8)))
                XCTAssertEqual(manifest.version, manifestVersion)
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
            artifactHash: release.artifactHash, schemaVersion: try LedgerText(ReviewedFoodProposalConfirmation.schema(.representativeEstimate, version: manifestVersion)),
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
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
            XCTAssertThrowsError(try service(harness).save(state, operationID: LedgerFixtures.operationID(809))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidReviewedSource)
            }
            XCTAssertEqual(try harness.reader.counts().operations, 0)
        }
    }

    /// Contract test 15: the reviewed-source integrity check runs before the v5 policy, and
    /// representative saves record food_confirmation_v5 with typed serving requirements.
    func testReviewedSourceIntegrityPrecedesPolicyAndServingRequirementIsTyped() throws {
        let original = try prepare(scope: .representativeEstimate)
        let evidence = original.evidence[0]
        guard case let .text(payload) = evidence.originalPayload else { return XCTFail("Text manifest") }
        let altered = try CaptureEvidence(evidenceID: evidence.evidenceID, kind: evidence.kind,
            capturedAt: evidence.capturedAt, locale: evidence.locale, captureMethod: evidence.captureMethod,
            captureMethodVersion: evidence.captureMethodVersion, originalPayload: .text(LedgerText(payload.value.replacingOccurrences(of: "tofu pudding", with: "altered food query"))),
            byteHash: evidence.byteHash)
        let input = try PopulatedFoodConfirmation(evidence: [altered], sourceReleases: original.sourceReleases,
            candidates: original.candidates, expectedIdentity: original.expectedIdentity, expectedEdibleQuantity: original.expectedEdibleQuantity)
        var state = FoodConfirmationState(input: input)
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        XCTAssertFalse(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: .current).isEmpty,
                       "Policy requirements are unmet, yet the integrity failure must be reported first")
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            XCTAssertThrowsError(try service(harness).save(state, operationID: LedgerFixtures.operationID(815))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidReviewedSource)
            }
            var valid = FoodConfirmationState(input: original)
            FoodConfirmationReducer.reduce(state: &valid, action: .setQuantity(150, .grams))
            XCTAssertTrue(FoodLogPolicy.requirements(valid, now: LedgerFixtures.date, calendar: .current).contains(.sourceServingsRequired))
            FoodConfirmationReducer.reduce(state: &valid, action: .setQuantity(1, .count))
            XCTAssertEqual(FoodLogPolicy.offeredChoices(valid, facet: .edibleQuantity), [.useSourceServing])
            valid.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &valid, action: .accept)
            let saved = try service(harness).save(valid, operationID: LedgerFixtures.operationID(816))
            XCTAssertEqual(saved.resolutionVersion.methodVersion.value, "food_confirmation_v5")
            XCTAssertEqual(saved.assertions.count, 1)
        }
    }

    func testAlteredStoredManifestCannotReopenOrPassIdempotentRecovery() throws {
        let harnesses = try LedgerFixtures.harnesses(); defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            let original = try prepare(scope: .representativeEstimate)
            var state = FoodConfirmationState(input: original)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(1, .count))
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
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
            state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
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
                state.answerPendingDifferences(); FoodConfirmationReducer.reduce(state: &state, action: .accept)
                XCTAssertThrowsError(try service(harness).save(state, operationID: LedgerFixtures.operationID(808))) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidReviewedSource)
                }
                XCTAssertEqual(try harness.reader.counts().operations, 0)
            }
        }
    }

    func service(_ harness: TestHarness) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(harness.committer), reader: harness.reader,
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: SHA256Digester())
    }
    func prepare(scope: FoodProposalReviewScope, serving: Bool = true,
                 acknowledgement: FoodProposalAcknowledgement = .init(identityAndScopeReviewed: true, basisReviewed: true, nutrientsAndUnknownsReviewed: true)) throws -> PopulatedFoodConfirmation {
        let (review, bound) = try ReviewedWebFixtures.review(serving: serving)
        let confirmation = ReviewedFoodProposalConfirmation(ids: RandomLedgerIDGenerator(), clock: LedgerFixtures.clock,
            encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
        if manifestVersion == ReviewedFoodProposalConfirmation.version1 {
            return try confirmation.prepareVersion1(bound, query: review.foodTerms, scope: scope,
                acknowledgement: acknowledgement, locale: LedgerText("zh_TW"))
        }
        return try confirmation.prepare(review: review, proposal: bound, scope: scope, locale: LedgerText("zh_TW"))
    }
}

final class ReviewedFoodProposalConfirmationV2Tests: ReviewedFoodProposalConfirmationTests {
    override var manifestVersion: String { ReviewedFoodProposalConfirmation.version }

    /// v2 replaces the three acknowledgements with one action: without a known
    /// "use_this_source" action (or with an unknown presentation) the record is not admissible.
    override func testEveryReviewAcknowledgementIsRequired() throws {
        let input = try prepare(scope: .representativeEstimate)
        XCTAssertNotNil(FoodReviewedWebProposalPolicy.scope(input, candidate: input.candidates[0]))
        for (from, to) in [("\"action\":\"use_this_source\"", "\"action\":\"reviewed\""),
                           ("\"presentation\":\"web-lookup-review-v1\"", "\"presentation\":\"web-lookup-review-v9\"")] {
            let tampered = try ReviewedWebFixtures.rewrite(input, replacing: from, with: to)
            XCTAssertNil(FoodReviewedWebProposalPolicy.scope(tampered, candidate: tampered.candidates[0]), to)
        }
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
