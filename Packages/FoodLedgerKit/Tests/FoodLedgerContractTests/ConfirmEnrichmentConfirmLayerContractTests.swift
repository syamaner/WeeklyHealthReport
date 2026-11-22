import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Confirm enrichment v1, PR 2 (docs/confirm-enrichment-openrouter-v1-phase.md sections 2.1 to 2.4a, 7 and
/// 10): the suggestion layer on Confirm, the save-side writing of the A capture, the B capture and the
/// choices item, reopen, re-log and quick add, against the in-memory and GRDB stores. Suggestions are
/// built the way the session builds them: the policy's request builders, a synthetic response, the
/// response checks and `ConfirmEnrichmentCaptureBuilder`. Synthetic data only.
final class ConfirmEnrichmentConfirmLayerContractTests: XCTestCase {
    typealias O = OpenFoodFactsEstimateContractTests
    typealias A = ApprovedEstimateConfirmContractTests
    typealias F = ConfirmEnrichmentFixtures

    // MARK: Route values (the contract tests target does not link FoodConfirmEnrichment)

    static let detailsRoute = ConfirmEnrichmentRoute(
        part: .details, version: ConfirmEnrichmentVersions.detailsRoute, model: "typesafe/jev-1.13",
        acceptedModels: ["typesafe/jev-1.13"], provider: "TypeSafe", providerEndpoint: "typesafe",
        endpoint: "https://example.invalid/v1/systemone", promptCeilingTokens: 8_000, completionCeilingTokens: 400,
        reasoningLimitTokens: 0, reasoningBilledSeparately: false, sendsMaxTokens: true)
    static let nutrientRoute = ConfirmEnrichmentRoute(
        part: .nutrients, version: ConfirmEnrichmentVersions.nutrientRoute, model: F.model, acceptedModels: [F.model],
        provider: F.provider, providerEndpoint: "azure", endpoint: F.endpoint, promptCeilingTokens: 6_000,
        completionCeilingTokens: 1_200, reasoningLimitTokens: 500, reasoningBilledSeparately: true, sendsMaxTokens: true)

    static let encoder = FoundationCanonicalJSONEncoder()

    // MARK: Fixtures

    /// The Open Food Facts search candidate with every food detail unknown, as the projection gives.
    static func unknownInput(nutrients: NutrientSet? = nil) throws -> PopulatedFoodConfirmation {
        let base = try O.input(.search, nutrients: nutrients)
        let source = base.candidates[0]
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams)
        let candidate = try ProviderNeutralCandidate(
            sourceReleaseID: source.candidate.sourceReleaseID, recordID: source.candidate.recordID, identity: identity,
            edibleQuantity: source.candidate.edibleQuantity, nutrients: source.candidate.nutrients,
            evidenceIDs: source.candidate.evidenceIDs, matchMetadata: source.candidate.matchMetadata)
        let populated = try PopulatedFoodCandidate(candidate: candidate, name: source.name, brand: source.brand, variant: nil,
            barcode: source.barcode, itemClass: source.itemClass, packFacts: source.packFacts)
        return try PopulatedFoodConfirmation(evidence: base.evidence, sourceReleases: base.sourceReleases, candidates: [populated],
            expectedIdentity: identity, expectedEdibleQuantity: candidate.edibleQuantity)
    }

    static func locale(_ state: FoodConfirmationState) -> LedgerText {
        ConfirmEnrichmentCaptureBuilder.locale(state.selectedCandidate.candidate, evidence: state.input.evidence)
    }

    nonisolated(unsafe) static let jevChoices: [String: (String, Double)] = [
        "preparation": ("as_sold", 0.95), "bone": ("not_applicable", 0.95), "skin": ("not_applicable", 0.95),
        "drained": ("not_applicable", 0.92), "packing_medium": ("as sold", 0.9), "fortification": ("unfortified", 0.9),
    ]

    /// A checked A answer for the state, as the session gives it.
    static func details(_ state: FoodConfirmationState, choices: [String: (String, Double)] = jevChoices) throws -> ConfirmDetailsSuggestion {
        let route = try XCTUnwrap(ConfirmEnrichmentPolicy.sourceRoute(state.input, candidate: state.selectedCandidate))
        let asked = try XCTUnwrap(ConfirmEnrichmentPolicy.detailsQuestions(state, route: route, database: nil))
        let inputs = try ConfirmDetailsRequestInputs(
            description: ConfirmEnrichmentPolicy.description(route, candidate: state.selectedCandidate, database: nil),
            knownDetails: ConfirmEnrichmentPolicy.knownDetails(state.selectedCandidate.candidate.identity), asked: asked)
        let request = try ConfirmEnrichmentPolicy.detailsRequest(inputs, route: detailsRoute, encoder: encoder, digester: LedgerFixtures.digester)
        var answers: [String: Any] = [:]
        for fact in asked {
            let (choice, confidence) = choices[fact.rawValue] ?? ("unknown", 0.5)
            answers[fact.rawValue] = ["type": "choice", "choice": choice, "confidence": confidence, "probabilities": [choice: confidence]]
        }
        let bytes = try JSONSerialization.data(withJSONObject: [
            "id": "gen-synthetic-details", "model": detailsRoute.model, "provider": detailsRoute.provider, "answers": answers,
            "usage": ["cost": 0.0004, "prompt_tokens": 300]], options: [.sortedKeys])
        guard case let .success(parsed) = ConfirmDetailsResponseCheck.check(bytes, request: inputs, models: detailsRoute.acceptedModels,
                                                                            provider: detailsRoute.provider) else {
            throw FoodLedgerValidationError.invalidProvenance
        }
        let applied = ConfirmDetailsResponseCheck.applied(parsed.answers)
        let capture = try ConfirmEnrichmentCaptureBuilder.details(
            request: request, route: detailsRoute, response: bytes, parsed: parsed, applied: applied, model: detailsRoute.model,
            receivedAt: LedgerFixtures.date, locale: locale(state), id: RandomLedgerIDGenerator().makeID(EvidenceTag.self),
            encoder: encoder, digester: LedgerFixtures.digester)
        var facts: [ConfirmDetailsFact: String] = [:]
        for fact in applied {
            facts[ConfirmDetailsFact(rawValue: fact)!] = parsed.answers.first { $0.fact == fact }!.choice
        }
        return ConfirmDetailsSuggestion(subjectSHA256: request.subjectSHA256, capture: capture, applied: facts,
                                        model: detailsRoute.model, receivedAt: capture.capturedAt, fromCache: false)
    }

    /// Iron, calcium and monounsaturated fat are eligible on the Open Food Facts fixture; fibre is not
    /// (an unconvertible unit), so its row is `unknown_nutrient`.
    nonisolated(unsafe) static let defaultRows: [[String: Any]] = [
        ["nutrient": "iron", "value": 2.5, "unit": "mg"], ["nutrient": "calcium", "value": 30, "unit": "mg"],
        ["nutrient": "fat_monounsaturated", "value": 10, "unit": "g"], ["nutrient": "fiber", "value": 7, "unit": "g"],
    ]

    /// A checked B answer for the state, as the session gives it.
    static func nutrients(_ state: FoodConfirmationState, rows: [[String: Any]] = defaultRows,
                          route: ConfirmEnrichmentPolicy.SourceRoute? = nil,
                          ids: any LedgerIDGenerating = RandomLedgerIDGenerator()) throws -> ConfirmNutrientSuggestion {
        let route = try XCTUnwrap(route ?? ConfirmEnrichmentPolicy.sourceRoute(state.input, candidate: state.selectedCandidate))
        let description = ConfirmEnrichmentPolicy.description(route, candidate: state.selectedCandidate, database: nil)
        let inputs = try XCTUnwrap(ConfirmEnrichmentPolicy.nutrientInputs(state, route: route, description: description,
            identity: state.enrichedIdentity, labelLayerKeys: Set(state.enrichment.labelLayer.keys)))
        let request = try ConfirmEnrichmentPolicy.nutrientRequest(inputs, route: nutrientRoute, encoder: encoder, digester: LedgerFixtures.digester)
        let bytes = try F.response(values: rows, basis: inputs.basis.rawValue)
        guard case let .success(parsed) = ConfirmNutrientResponseCheck.check(bytes, request: inputs, models: [F.model], provider: F.provider) else {
            throw FoodLedgerValidationError.invalidProvenance
        }
        let captureRows = ConfirmNutrientResponseCheck.captureRows(parsed, request: inputs)
        let capture = try ConfirmEnrichmentCaptureBuilder.nutrients(
            request: request, route: nutrientRoute, response: bytes, rows: captureRows, generationID: parsed.usage.generationID,
            model: F.model, receivedAt: LedgerFixtures.date, locale: locale(state),
            id: ids.makeID(EvidenceTag.self), encoder: encoder, digester: LedgerFixtures.digester)
        return ConfirmNutrientSuggestion(subjectSHA256: request.subjectSHA256, capture: capture, inputs: inputs, rows: captureRows,
                                         model: F.model, receivedAt: capture.capturedAt, fromCache: false)
    }

    static func reduce(_ state: inout FoodConfirmationState, _ actions: FoodConfirmationAction...) {
        for action in actions { FoodConfirmationReducer.reduce(state: &state, action: action) }
    }

    /// A new Open Food Facts Confirm with a resolved identity, an amount and B rows applied.
    static func bState(rows: [[String: Any]] = defaultRows, leftOut: [NutrientKey] = []) throws -> FoodConfirmationState {
        var state = O.state(try O.input(.search))
        reduce(&state, .applyNutrientSuggestion(try nutrients(state, rows: rows)))
        for key in leftOut { reduce(&state, .leaveOutOpenRouterEstimate(key)) }
        reduce(&state, .accept)
        return state
    }

    static func value(_ set: NutrientSet, _ key: NutrientKey) -> NutrientValue { set.entries.first { $0.key == key }!.value }

    static func isOpenRouter(_ value: NutrientValue) -> Bool { value.provenance.contains { $0.sourceKind == .openRouterEstimate } }

    static func cited(_ saved: StoredFoodConfirmation, version: String) -> [CaptureEvidence] {
        saved.evidence.filter { saved.candidateDecision.candidate.evidenceIDs.contains($0.evidenceID) && $0.captureMethodVersion.value == version }
    }

    static var utc: Calendar { A.utc }

    // MARK: A: the fill

    func testAJevFillEnablesLogAndSavesAsACorrectionCitingItsCaptureLast() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            var state = FoodConfirmationState(input: try Self.unknownInput(), prefillSourceQuantity: false)
            Self.reduce(&state, .setQuantity(25, .grams))
            XCTAssertTrue(PackagedAsSoldPolicy.offers(state), harness.name)
            XCTAssertFalse(state.unresolvedIdentity.isEmpty)
            let suggestion = try Self.details(state)
            Self.reduce(&state, .applyDetailsSuggestion(suggestion))
            XCTAssertEqual(state.enrichment.filledFacts.count, 6)
            XCTAssertTrue(state.unresolvedIdentity.isEmpty, "the layer alone satisfies the missing details")
            XCTAssertTrue(FoodLogPolicy.pendingDifferences(state).isEmpty, "a fill raises no difference")
            XCTAssertFalse(PackagedAsSoldPolicy.offers(state), "the one tap is not offered while a fill is shown")
            XCTAssertEqual(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: Self.utc), [], harness.name)
            Self.reduce(&state, .accept)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(12_001))
            XCTAssertEqual(saved.productVersion.identity.preparation.kind, .asSold)
            XCTAssertEqual(saved.productVersion.identity.fortification, .unfortified)
            XCTAssertEqual(saved.assertions.last?.reason.value, FoodDetailsFillPolicy.suggestedByJevReason)
            XCTAssertTrue(saved.evidence.contains { $0.evidenceID == suggestion.capture.evidenceID }, "the A capture is committed")
            XCTAssertEqual(saved.candidateDecision.candidate.evidenceIDs.last, suggestion.capture.evidenceID)
            XCTAssertEqual(saved.productVersion.evidenceIDs.last, suggestion.capture.evidenceID)
            XCTAssertEqual(saved.productVersion.evidenceIDs, saved.candidateDecision.candidate.evidenceIDs)
            let stored = try XCTUnwrap(harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(stored.candidateDecision.candidate.evidenceIDs, saved.candidateDecision.candidate.evidenceIDs, harness.name)
        }
    }

    func testNotTheseBeforeLogCommitsNoACapture() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            var state = FoodConfirmationState(input: try Self.unknownInput(), prefillSourceQuantity: false)
            Self.reduce(&state, .setQuantity(25, .grams))
            let suggestion = try Self.details(state)
            Self.reduce(&state, .applyDetailsSuggestion(suggestion), .clearDetailsSuggestion)
            XCTAssertFalse(state.unresolvedIdentity.isEmpty, "every suggested fact is unknown again")
            XCTAssertTrue(PackagedAsSoldPolicy.offers(state), "Not these brings the one tap back")
            Self.reduce(&state, .applyCorrection(try PackagedAsSoldPolicy.correction(for: state, fortified: false)), .accept)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(12_002))
            XCTAssertFalse(saved.evidence.contains(where: ConfirmEnrichmentVersions.isEnrichmentEvidence), harness.name)
            XCTAssertEqual(saved.assertions.last?.reason.value, FoodDetailsFillPolicy.packagedAsSoldReason)
        }
    }

    // MARK: B: kept rows

    func testKeptRowsSaveWithThePinnedProvenanceAReleaseAndTheirOwnChoicesItem() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            let state = try Self.bState()
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(12_010))
            let nutrients = saved.resolutionVersion.nutrients
            for key in [NutrientKey.iron, .calcium, .fatMonounsaturated] {
                let value = Self.value(nutrients, key)
                guard case let .augmented(exact) = value, let provenance = exact.provenance.first else {
                    return XCTFail("\(harness.name) \(key) is augmented")
                }
                XCTAssertTrue(OpenRouterEstimateProvenance.isValid(provenance, key: key), "\(harness.name) \(key)")
                XCTAssertEqual(exact.provenance.count, 1)
            }
            XCTAssertEqual(Self.value(nutrients, .fiber), .unknown(.missingConversion), "a key that is not eligible is never written")
            XCTAssertEqual(Self.value(nutrients, .protein), Self.value(state.selectedCandidate.candidate.nutrients, .protein))
            let capture = try XCTUnwrap(Self.cited(saved, version: ConfirmEnrichmentVersions.nutrientCaptureMethodVersion).first)
            let releaseID = OpenRouterEstimateProvenance.sourceReleaseID(captureHash: try XCTUnwrap(capture.byteHash))
            XCTAssertTrue(saved.sourceReleases.contains { $0.sourceReleaseID.value == releaseID }, harness.name)
            XCTAssertTrue(saved.resolutionVersion.sourceReleaseIDs.contains { $0.value == releaseID })
            XCTAssertNotNil(try harness.reader.sourceRelease(id: ExternalIdentifier(releaseID)), "the release is committed")
            let choices = Self.cited(saved, version: ConfirmEnrichmentVersions.choicesMethodVersion)
            XCTAssertEqual(choices.count, 1)
            XCTAssertEqual(ConfirmEnrichmentEvidence.choices(choices[0])?.resolutionVersionID, saved.resolutionVersion.resolutionVersionID.rawValue)
            guard case .verified = ConfirmEnrichmentVerification.verify(
                nutrients: nutrients, resolutionVersionID: saved.resolutionVersion.resolutionVersionID,
                citedEvidenceIDs: saved.candidateDecision.candidate.evidenceIDs, evidence: saved.evidence, layer: [:],
                digester: LedgerFixtures.digester) else { return XCTFail("\(harness.name): the saved version verifies") }
            let stored = try XCTUnwrap(harness.reader.foodConfirmation(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(stored.resolutionVersion.nutrients, nutrients, harness.name)
        }
    }

    /// CE1.6 rule 4's third check (invariant review of PR 2): the save service itself refuses B values
    /// beside a correction that changed the values, even for a state the reducer would never build.
    func testSaveRefusesBValuesBesideACorrectionThatChangedTheValues() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            var state = try Self.bState()
            let candidate = state.selectedCandidate
            let changed = try NutrientSet(entries: candidate.candidate.nutrients.entries.map { entry in
                entry.key == .protein ? try NutrientEntry(key: .protein, value: .unknown(.noCompatibleSource)) : entry
            })
            XCTAssertNotEqual(changed, candidate.candidate.nutrients)
            let rows = try XCTUnwrap(state.enrichment.nutrients)
            state.correction = FoodCorrection(name: candidate.name, brand: candidate.brand, variant: candidate.variant,
                                              identity: state.enrichedIdentity, itemClass: candidate.itemClass, nutrients: changed,
                                              reason: try LedgerText("Typed values"))
            state.enrichment.nutrients = rows
            XCTAssertThrowsError(try O.service(harness).save(state, operationID: LedgerFixtures.operationID(12_019))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidOpenRouterEstimate, harness.name)
            }
            var fresh = try Self.bState()
            Self.reduce(&fresh, .clearNutrientSuggestion)
            fresh.correction = state.correction
            Self.reduce(&fresh, .applyNutrientSuggestion(rows))
            XCTAssertNil(fresh.enrichment.nutrients, "the reducer refuses B rows beside changed values")
        }
    }

    func testEveryRowLeftOutCitesNeitherBItem() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let state = try Self.bState(leftOut: [.iron, .calcium, .fatMonounsaturated])
            XCTAssertFalse(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: Self.utc).contains(.onlyEstimatedByOpenRouter))
            let saved = try O.service(harness).save(state, operationID: LedgerFixtures.operationID(12_011))
            XCTAssertFalse(ConfirmEnrichmentCitation.holdsOpenRouterEstimate(saved.resolutionVersion.nutrients), harness.name)
            XCTAssertFalse(saved.evidence.contains(where: ConfirmEnrichmentVersions.isEnrichmentEvidence), harness.name)
        }
    }

    func testOnlyOpenRouterEstimatesBlockLogUntilEveryRowIsLeftOut() throws {
        let unknown = try NutrientSet(entries: NutrientKey.allCases.map { try NutrientEntry(key: $0, value: .unknown(.notDeclared)) })
        var state = FoodConfirmationState(input: try O.input(.search, nutrients: unknown), prefillSourceQuantity: false)
        Self.reduce(&state, .setQuantity(25, .grams))
        Self.reduce(&state, .applyNutrientSuggestion(try Self.nutrients(state, rows: [["nutrient": "iron", "value": 2.5, "unit": "mg"]],
                                                                        route: .openFoodFacts)))
        XCTAssertTrue(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: Self.utc).contains(.onlyEstimatedByOpenRouter))
        Self.reduce(&state, .leaveOutOpenRouterEstimate(.iron))
        XCTAssertFalse(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: Self.utc).contains(.onlyEstimatedByOpenRouter))
        Self.reduce(&state, .restoreOpenRouterEstimate(.iron))
        XCTAssertTrue(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: Self.utc).contains(.onlyEstimatedByOpenRouter))
        // Values a chosen label layer fills are known from another source (invariant review of PR 2).
        Self.reduce(&state, .setEnrichmentLabelLayer([.fatTotal: 2]))
        XCTAssertFalse(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: Self.utc).contains(.onlyEstimatedByOpenRouter))
    }

    // MARK: Reopen

    func testReopenRebuildsTheLayerAndALeaveOutWritesTheFrozenTexts() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            let first = try service.save(try Self.bState(leftOut: [.calcium]), operationID: LedgerFixtures.operationID(12_020))
            var reopened = try XCTUnwrap(service.reopen(logItemID: first.logItem.logItemID))
            XCTAssertNotNil(reopened.enrichment.nutrients, harness.name)
            XCTAssertEqual(reopened.enrichment.seedLeftOut, [.calcium])
            XCTAssertEqual(reopened.enrichment.leftOut, [.calcium])
            XCTAssertTrue(Self.isOpenRouter(Self.value(reopened.displayNutrients, .iron)), "saved B values are shown")
            XCTAssertNotNil(reopened.openRouterEstimateRows[.calcium], "a left-out row offers Put back")
            XCTAssertFalse(Self.isOpenRouter(Self.value(reopened.displayNutrients, .calcium)))
            Self.reduce(&reopened, .leaveOutOpenRouterEstimate(.iron))
            let second = try service.save(reopened, operationID: LedgerFixtures.operationID(12_021))
            let assertion = try XCTUnwrap(second.assertions.last)
            XCTAssertEqual(assertion.reason.value, OpenRouterEstimateChoicesText.reason)
            XCTAssertEqual(assertion.claim.value, OpenRouterEstimateChoicesText.claim([.calcium, .iron]))
            XCTAssertEqual(assertion.confirmation, first.assertions.last(where: { $0.confirmation != nil })?.confirmation)
            XCTAssertEqual(second.logItemVersion.correctionReason?.value, OpenRouterEstimateChoicesText.editReason)
            XCTAssertEqual(second.candidateDecision.expectedIdentity, first.candidateDecision.expectedIdentity)
            XCTAssertEqual(second.candidateDecision.expectedEdibleQuantity, first.candidateDecision.expectedEdibleQuantity)
            XCTAssertEqual(second.candidateDecision.outcome, first.candidateDecision.outcome)
            XCTAssertFalse(Self.isOpenRouter(Self.value(second.resolutionVersion.nutrients, .iron)))
            XCTAssertTrue(Self.isOpenRouter(Self.value(second.resolutionVersion.nutrients, .fatMonounsaturated)), harness.name)
        }
    }

    /// G12: reopen, Put back, save, reopen, Leave out, save. Each version cites exactly one choices item,
    /// its own, and no earlier CE1 or leave-out ID appears twice.
    func testEachVersionCitesExactlyItsOwnChoicesItem() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            var saved = try service.save(try Self.bState(leftOut: [.iron]), operationID: LedgerFixtures.operationID(12_030))
            var versions = [saved]
            for (index, step) in [FoodConfirmationAction.restoreOpenRouterEstimate(.iron), .leaveOutOpenRouterEstimate(.calcium)].enumerated() {
                var state = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
                Self.reduce(&state, step)
                saved = try service.save(state, operationID: LedgerFixtures.operationID(12_031 + index))
                versions.append(saved)
            }
            var choiceIDs = Set<EvidenceID>()
            for version in versions {
                let ids = version.candidateDecision.candidate.evidenceIDs
                XCTAssertEqual(Set(ids).count, ids.count, "\(harness.name): no ID twice")
                let choices = Self.cited(version, version: ConfirmEnrichmentVersions.choicesMethodVersion)
                XCTAssertEqual(choices.count, 1, harness.name)
                XCTAssertEqual(ConfirmEnrichmentEvidence.choices(choices[0])?.resolutionVersionID,
                               version.resolutionVersion.resolutionVersionID.rawValue, harness.name)
                XCTAssertTrue(choiceIDs.insert(choices[0].evidenceID).inserted, "each version's choices item is new")
                XCTAssertEqual(Self.cited(version, version: ConfirmEnrichmentVersions.nutrientCaptureMethodVersion).count, 1)
            }
            XCTAssertEqual(ConfirmEnrichmentEvidence.choices(Self.cited(versions[1], version: ConfirmEnrichmentVersions.choicesMethodVersion)[0])?
                .leftOutKeys, [])
            XCTAssertEqual(ConfirmEnrichmentEvidence.choices(Self.cited(versions[2], version: ConfirmEnrichmentVersions.choicesMethodVersion)[0])?
                .leftOutKeys, [.calcium])
            XCTAssertTrue(Self.isOpenRouter(Self.value(versions[1].resolutionVersion.nutrients, .iron)), "Put back returns the value")
        }
    }

    func testAQuantityOnlyEditWritesNoNewDecisionOrVersions() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            let first = try service.save(try Self.bState(), operationID: LedgerFixtures.operationID(12_040))
            var state = try XCTUnwrap(service.reopen(logItemID: first.logItem.logItemID))
            Self.reduce(&state, .setQuantity(40, .grams))
            let second = try service.save(state, operationID: LedgerFixtures.operationID(12_041))
            XCTAssertEqual(second.candidateDecision.candidateDecisionID, first.candidateDecision.candidateDecisionID, harness.name)
            XCTAssertEqual(second.productVersion.productVersionID, first.productVersion.productVersionID)
            XCTAssertEqual(second.resolutionVersion.resolutionVersionID, first.resolutionVersion.resolutionVersionID)
            XCTAssertNotEqual(second.logItemVersion.logItemVersionID, first.logItemVersion.logItemVersionID)
        }
    }

    func testADetailsCorrectionThatChangesTheIdentityRemovesBWithItsNote() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            let first = try service.save(try Self.bState(), operationID: LedgerFixtures.operationID(12_050))
            var state = try XCTUnwrap(service.reopen(logItemID: first.logItem.logItemID))
            let selected = state.selectedCandidate
            let raw = try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .notApplicable, skin: .notApplicable,
                drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
            Self.reduce(&state, .applyCorrection(FoodCorrection(name: selected.name, brand: selected.brand, variant: selected.variant,
                identity: raw, nutrients: selected.candidate.nutrients, reason: try LedgerText("Synthetic correction"))))
            XCTAssertNil(state.enrichment.nutrients, harness.name)
            XCTAssertTrue(state.enrichment.removedBecauseDetailsChanged)
            let second = try service.save(state, operationID: LedgerFixtures.operationID(12_051))
            XCTAssertFalse(ConfirmEnrichmentCitation.holdsOpenRouterEstimate(second.resolutionVersion.nutrients), harness.name)
            XCTAssertTrue(Self.cited(second, version: ConfirmEnrichmentVersions.nutrientCaptureMethodVersion).isEmpty)
            XCTAssertTrue(Self.cited(second, version: ConfirmEnrichmentVersions.choicesMethodVersion).isEmpty)
            XCTAssertTrue(Set(second.productVersion.evidenceIDs).isDisjoint(with:
                ConfirmEnrichmentCitation.enrichmentEvidenceIDs(second.evidence)), "the product version carries no earlier B item")
        }
    }

    func testAnUnchangedSubjectCorrectionKeepsB() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            let first = try service.save(try Self.bState(), operationID: LedgerFixtures.operationID(12_055))
            var state = try XCTUnwrap(service.reopen(logItemID: first.logItem.logItemID))
            let selected = state.selectedCandidate
            Self.reduce(&state, .applyCorrection(FoodCorrection(name: try LedgerText("Renamed bar"), brand: selected.brand, variant: selected.variant,
                identity: first.productVersion.identity, nutrients: selected.candidate.nutrients, reason: try LedgerText("Synthetic rename"))))
            XCTAssertNotNil(state.enrichment.nutrients, "the source-side subject is unchanged")
            let second = try service.save(state, operationID: LedgerFixtures.operationID(12_056))
            XCTAssertTrue(Self.isOpenRouter(Self.value(second.resolutionVersion.nutrients, .iron)), harness.name)
            XCTAssertEqual(Self.cited(second, version: ConfirmEnrichmentVersions.choicesMethodVersion).count, 1)
        }
    }

    /// A read-only reader over one stored entry, so an altered copy can be reopened.
    struct OneEntry: FoodConfirmationReading {
        let stored: StoredFoodConfirmation
        func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { stored.sourceReleases.first { $0.sourceReleaseID == id } }
        func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { stored }
        func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? { stored }
        func evidence(id: EvidenceID) throws -> CaptureEvidence? { stored.evidence.first { $0.evidenceID == id } }
    }

    func testAnAlteredChoicesItemReadsEvidenceNotAvailableAndChangesNothing() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let saved = try O.service(harness).save(try Self.bState(), operationID: LedgerFixtures.operationID(12_060))
        let evidence = try saved.evidence.map { item -> CaptureEvidence in
            guard item.captureMethodVersion.value == ConfirmEnrichmentVersions.choicesMethodVersion,
                  case let .text(payload) = item.originalPayload else { return item }
            let edited = payload.value.replacingOccurrences(of: "\"left_out\":[]", with: "\"left_out\":[\"iron\"]")
            XCTAssertNotEqual(edited, payload.value)
            return try CaptureEvidence(evidenceID: item.evidenceID, kind: item.kind, capturedAt: item.capturedAt, locale: item.locale,
                captureMethod: item.captureMethod, captureMethodVersion: item.captureMethodVersion,
                originalPayload: .text(LedgerText(edited)), byteHash: item.byteHash)
        }
        let altered = StoredFoodConfirmation(evidence: evidence, sourceReleases: saved.sourceReleases, product: saved.product,
            productVersion: saved.productVersion, resolution: saved.resolution, resolutionVersion: saved.resolutionVersion,
            logItem: saved.logItem, logItemVersion: saved.logItemVersion, quantityConversion: saved.quantityConversion,
            plate: saved.plate, plateWeightVersion: saved.plateWeightVersion, candidateDecision: saved.candidateDecision,
            assertions: saved.assertions, estimate: saved.estimate)
        let service = try FoodConfirmationService(ledger: LedgerFixtures.service(InMemoryFoodLedgerStore()), reader: OneEntry(stored: altered),
            clock: LedgerFixtures.clock, ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester)
        var state = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
        XCTAssertTrue(state.enrichment.evidenceNotAvailable)
        XCTAssertNil(state.enrichment.nutrients)
        XCTAssertEqual(state.reopened?.resolutionVersion.nutrients, saved.resolutionVersion.nutrients, "no stored value changes")
        XCTAssertEqual(state.displayNutrients, saved.resolutionVersion.nutrients,
                       "the saved values are shown as saved, marked est., beside Evidence not available")
        // A save that would write them again is refused, never rewritten.
        Self.reduce(&state, .leaveOutOpenRouterEstimate(.iron))
        XCTAssertEqual(state.enrichment.leftOut, [], "no Leave out without verified evidence")
    }

    // MARK: Re-log, quick add, Your foods

    func testReLogAndQuickAddDropEveryCE1IDAndAFavouriteOpensConfirm() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            var state = FoodConfirmationState(input: try Self.unknownInput(), prefillSourceQuantity: false)
            Self.reduce(&state, .setQuantity(25, .grams))
            Self.reduce(&state, .applyDetailsSuggestion(try Self.details(state)))
            Self.reduce(&state, .applyNutrientSuggestion(try Self.nutrients(state)), .accept)
            let saved = try service.save(state, operationID: LedgerFixtures.operationID(12_070))
            XCTAssertEqual(ConfirmEnrichmentCitation.enrichmentEvidenceIDs(saved.evidence).count, 3, "A, B and the choices item")
            XCTAssertTrue(FoodDetailsFillPolicy.isStoredFill(saved), "a Jev fill with B values still carries its details")
            for input in [try service.relogInput(saved), try service.favouriteInput(saved)] {
                XCTAssertTrue(input.evidence.allSatisfy { !ConfirmEnrichmentVersions.isEnrichmentEvidence($0) }, harness.name)
                XCTAssertTrue(input.candidates[0].candidate.evidenceIDs.allSatisfy { id in
                    !saved.evidence.contains { $0.evidenceID == id && ConfirmEnrichmentVersions.isEnrichmentEvidence($0) }
                })
                XCTAssertFalse(ConfirmEnrichmentCitation.holdsOpenRouterEstimate(input.candidates[0].candidate.nutrients))
            }
            var rebuilt = FoodConfirmationState(input: try service.favouriteInput(saved), prefillSourceQuantity: false)
            Self.reduce(&rebuilt, .setQuantity(25, .grams))
            XCTAssertEqual(QuickAddPolicy.eligibility(pinned: saved, pinnedIsEstimate: false, rebuilt: rebuilt, now: LedgerFixtures.date,
                                                      calendar: Self.utc), .confirm(.openRouterEstimate), harness.name)
            let relog = try XCTUnwrap(service.relogState(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(relog.correction?.identity, saved.productVersion.identity, "the fill is carried on re-log")
            XCTAssertNil(relog.enrichment.nutrients, "B values are not carried")
        }
    }

    /// G9: both Your foods builders rebuild saved OpenRouter keys as unknown, not declared.
    func testYourFoodsRowsNeverCarryOpenRouterEstimates() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let saved = try O.service(harness).save(try Self.bState(), operationID: LedgerFixtures.operationID(12_080))
        let carried = OpenRouterEstimateCarry.sourceNutrients(saved.resolutionVersion.nutrients)
        for key in [NutrientKey.iron, .calcium, .fatMonounsaturated] {
            XCTAssertEqual(Self.value(carried, key), .unknown(.notDeclared), "\(key)")
        }
        XCTAssertEqual(Self.value(carried, .protein), Self.value(saved.resolutionVersion.nutrients, .protein))
        XCTAssertFalse(ConfirmEnrichmentCitation.holdsOpenRouterEstimate(carried))
        XCTAssertTrue(OpenFoodFactsEstimateSource.isProductCandidate(try ProviderNeutralCandidate(
            sourceReleaseID: saved.candidateDecision.candidate.sourceReleaseID, recordID: saved.candidateDecision.candidate.recordID,
            identity: saved.productVersion.identity, edibleQuantity: saved.candidateDecision.candidate.edibleQuantity,
            nutrients: carried, evidenceIDs: saved.candidateDecision.candidate.evidenceIDs)), "the row is classified by its real source")
    }

    // MARK: G8: the #464 label layer with B rows

    func testAnOpenFoodFactsEntryWithTheLabelLayerAndBRowsSavesReopensAndEdits() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let service = try O.service(harness)
            var state = O.state(try O.input(.search))
            let choice = try O.choice()
            // B answers first (iron, which the layer also fills, and calcium, which it does not).
            Self.reduce(&state, .applyNutrientSuggestion(try Self.nutrients(state, rows: [
                ["nutrient": "iron", "value": 2.5, "unit": "mg"], ["nutrient": "calcium", "value": 30, "unit": "mg"]])))
            let layer = ConfirmEnrichmentMerge.layerValues(choice, state: state)
            XCTAssertNotNil(layer[.iron], "the layer fills iron")
            Self.reduce(&state, .setEnrichmentLabelLayer(layer))
            XCTAssertNil(state.openRouterEstimateRows[.iron], "choosing the layer drops the B row it fills")
            let first = try service.save(state, operationID: LedgerFixtures.operationID(12_090), estimate: choice)
            XCTAssertNotNil(first.estimate, harness.name)
            XCTAssertFalse(Self.isOpenRouter(Self.value(first.resolutionVersion.nutrients, .iron)))
            XCTAssertTrue(Self.isOpenRouter(Self.value(first.resolutionVersion.nutrients, .calcium)), harness.name)
            let choices = try XCTUnwrap(ConfirmEnrichmentEvidence.choices(
                try XCTUnwrap(Self.cited(first, version: ConfirmEnrichmentVersions.choicesMethodVersion).first)))
            XCTAssertEqual(choices.layerDroppedKeys, [.iron])
            var reopened = try XCTUnwrap(service.reopen(logItemID: first.logItem.logItemID), harness.name)
            XCTAssertNotNil(reopened.enrichment.nutrients, "\(harness.name): the layered entry verifies on reopen")
            Self.reduce(&reopened, .leaveOutOpenRouterEstimate(.calcium))
            let second = try service.save(reopened, operationID: LedgerFixtures.operationID(12_091))
            XCTAssertNotNil(second.estimate, "\(harness.name): a B-only edit keeps the label layer")
            XCTAssertFalse(Self.isOpenRouter(Self.value(second.resolutionVersion.nutrients, .calcium)))
            XCTAssertEqual(Self.value(second.resolutionVersion.nutrients, .iron), Self.value(first.resolutionVersion.nutrients, .iron))
            XCTAssertNotNil(try service.reopen(logItemID: second.logItem.logItemID), harness.name)
        }
    }

    // MARK: Domain: a negative zero

    func testANegativeZeroIsAValueRow() {
        let results = ConfirmNutrientRowCheck.results(
            rows: [.init(nutrient: "iron", value: "-0", unit: NutrientKey.iron.canonicalUnit.rawValue),
                   .init(nutrient: "calcium", value: "-0.0", unit: NutrientKey.calcium.canonicalUnit.rawValue),
                   .init(nutrient: "zinc", value: "0", unit: NutrientKey.zinc.canonicalUnit.rawValue)],
            eligible: [.iron, .calcium, .zinc], basis: .per100Grams, known: [:])
        XCTAssertEqual(results, [.value, .value, .kept])
    }
}

/// The deferred PR 1 export items (phase gate section 2.8): a builder-level schema 7 golden for a mixed
/// day, and an unscalable OpenRouter estimate with no row origin producing no file.
final class ConfirmEnrichmentConfirmLayerExportContractTests: XCTestCase {
    typealias L = ConfirmEnrichmentConfirmLayerContractTests
    typealias A = ApprovedEstimateConfirmContractTests
    typealias O = OpenFoodFactsEstimateContractTests

    private final class SequentialIDs: LedgerIDGenerating, @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0x5490000
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            let n = lock.withLock { () -> Int in defer { value += 1 }; return value }
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", n))
        }
    }

    static let golden = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/fixtures/confirm-enrichment-v1/daily-export-schema7-mixed-day.json")

    static func request(_ records: LedgerMutation) -> FoodDailyExportRequest {
        FoodDailyExportRequest(records: records, reportDate: ApprovedEstimateExportContractTests.day, timeZone: TimeZone(identifier: "UTC")!,
            dataAsOf: LedgerFixtures.date.addingTimeInterval(60), exportedAt: LedgerFixtures.date.addingTimeInterval(120),
            appContext: ApprovedEstimateExportContractTests.app, digester: LedgerFixtures.digester)
    }

    /// One Open Food Facts entry with kept B rows and one Your food database entry with approved
    /// estimates (schema 3 content) on one day: one schema 7 file, byte for byte the golden.
    func testAMixedDayIsOneSchemaSevenFileEqualToTheGolden() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let ids = SequentialIDs()
        let service = try A.service(harness, ids: ids)
        var b = O.state(try O.input(.search))
        FoodConfirmationReducer.reduce(state: &b, action: .applyNutrientSuggestion(try L.nutrients(b, ids: ids)))
        FoodConfirmationReducer.reduce(state: &b, action: .accept)
        _ = try service.save(b, operationID: try ids.makeID(OperationTag.self), idempotencyKey: try LedgerText("ce1-mixed-b"))
        let approved = try A.state(service, [A.fish], grams: 50, ids: ids)
        _ = try service.save(approved, operationID: try ids.makeID(OperationTag.self), idempotencyKey: try LedgerText("ce1-mixed-a"))
        let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
        let document = try FoodDailyExportBuilder.make(Self.request(try archive.archiveState().records))
        XCTAssertEqual(document.foodDailySchemaVersion, 7)
        XCTAssertNoThrow(try FoodDailyExportShape.validate(document))
        XCTAssertEqual(document.entries.count, 2)
        let bytes = try FoodDailyExportSerializer.encode(document)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("\"origin\":\"openrouter_estimate\""))
        XCTAssertTrue(text.contains("\"source_kind\":\"approved_estimate\""))
        XCTAssertFalse(text.contains("request_body"), "no request or response text leaves")
        if ProcessInfo.processInfo.environment["CE1_RECORD_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: Self.golden.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: Self.golden)
        }
        let expected = try Data(contentsOf: Self.golden)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), String(decoding: expected, as: UTF8.self))
        XCTAssertEqual(try FoodDailyExportSerializer.encode(FoodDailyExportSerializer.decode(expected)), expected, "decodes and re-encodes unchanged")
    }

    /// An unscalable OpenRouter estimate in a version whose values hold no other source is unattributed:
    /// no file, never an unknown exported as `openrouter_estimate`.
    func testAnUnscalableOpenRouterEstimateWithNoRowOriginProducesNoFile() throws {
        let harness = try XCTUnwrap(try LedgerFixtures.harnesses().first)
        defer { harness.cleanup() }
        let log = try O.service(harness).save(try L.bState(), operationID: LedgerFixtures.operationID(12_100))
        let only = try NutrientSet(entries: log.resolutionVersion.nutrients.entries.map { entry in
            L.isOpenRouter(entry.value) ? entry : try NutrientEntry(key: entry.key, value: .unknown(.notDeclared))
        })
        let resolution = NutritionResolution(resolutionID: log.resolution.resolutionID, productVersionID: log.resolution.productVersionID,
                                             basis: .unknown, createdAt: log.resolution.createdAt)
        let version = try NutritionResolutionVersion(
            resolutionVersionID: log.resolutionVersion.resolutionVersionID, resolutionID: log.resolutionVersion.resolutionID,
            ordinal: log.resolutionVersion.ordinal, methodVersion: log.resolutionVersion.methodVersion,
            sourceReleaseIDs: log.resolutionVersion.sourceReleaseIDs, nutrients: only, decisionIDs: log.resolutionVersion.decisionIDs,
            assertionIDs: log.resolutionVersion.assertionIDs, createdAt: log.resolutionVersion.createdAt)
        var records = LedgerMutation(evidence: log.evidence, products: [log.product], productVersions: [log.productVersion],
            resolutions: [resolution], resolutionVersions: [version], logItems: [log.logItem], logItemVersions: [log.logItemVersion],
            candidateDecisions: [log.candidateDecision], sourceReleases: log.sourceReleases)
        records.assertions = log.assertions
        XCTAssertThrowsError(try FoodDailyExportBuilder.make(Self.request(records))) {
            XCTAssertEqual($0 as? FoodDailyExportError, .unattributedEntry)
        }
    }
}
