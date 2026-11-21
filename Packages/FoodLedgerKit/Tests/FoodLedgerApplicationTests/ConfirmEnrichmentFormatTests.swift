import XCTest
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport

/// Confirm enrichment v1, PR 1 (formats): the provenance kind, the three captures, the request inputs,
/// the response and row checks, verification and citation (phase gate sections 2.1 to 2.4a, G4, G12
/// fixture cases and the format half of G8). Synthetic data only.
final class ConfirmEnrichmentFormatTests: XCTestCase {
    typealias F = ConfirmEnrichmentFixtures
    let digester = SHA256Digester()

    // MARK: Provenance (2.1)

    func testThePinnedProvenanceIsValidAndEachMutatedFieldIsRefused() throws {
        let built = try F.built()
        let good = try F.provenance(built.captureEvidence, key: .fiber)
        XCTAssertTrue(OpenRouterEstimateProvenance.isValid(good, key: .fiber))
        XCTAssertFalse(OpenRouterEstimateProvenance.isValid(good, key: .sodium), "manifest reference names the key")
        let other = try SHA256Digest(String(repeating: "a", count: 64))
        func with(_ change: (inout Parts) throws -> Void) throws -> NutrientProvenance {
            var p = Parts(good)
            try change(&p)
            return p.provenance
        }
        let mutations: [NutrientProvenance] = [
            try with { $0.sourceID = try ExternalIdentifier("personal-food-database") },
            try with { $0.sourceReleaseID = try ExternalIdentifier("openrouter-estimate:sha256:" + other.value) },
            try with { $0.recordID = try ExternalIdentifier("ore:other") },
            try with { $0.recordID = nil },
            try with { $0.evidenceID = nil },
            try with { $0.capturedAt = nil },
            try with { $0.responseHash = other },
            try with { $0.manifestReference = try LedgerText("confirm-nutrient-capture-v1#sodium") },
            try with { $0.decisionID = try F.id(1) },
            try with { $0.assertionID = try F.id(2) },
            try with { $0.transforms = [NutrientTransform(transformID: try LedgerText("t"), transformVersion: try LedgerText("v1"))] }
        ]
        for mutation in mutations {
            XCTAssertFalse(OpenRouterEstimateProvenance.isValid(mutation, key: .fiber))
            XCTAssertThrowsError(try F.value(6.5, key: .fiber, provenance: mutation).validatedEntry(.fiber))
        }
    }

    func testAnOpenRouterEstimateIsOnlyAugmentedAndStandsAlone() throws {
        let built = try F.built()
        let provenance = try F.provenance(built.captureEvidence, key: .fiber)
        let exact = try ExactNutrientValue(amount: 6.5, unit: .grams,
            sourceValue: .exact(try SourceExactNutrientValue(amount: 6.5, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [provenance])
        XCTAssertNoThrow(try NutrientEntry(key: .fiber, value: .augmented(exact)))
        XCTAssertThrowsError(try NutrientEntry(key: .fiber, value: .measured(exact)))
        let generic = NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: try ExternalIdentifier("cofid"),
                                         sourceReleaseID: try ExternalIdentifier("cofid-2021"), recordID: try ExternalIdentifier("r1"))
        let two = try ExactNutrientValue(amount: 6.5, unit: .grams,
            sourceValue: .exact(try SourceExactNutrientValue(amount: 6.5, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [provenance, generic])
        XCTAssertThrowsError(try NutrientEntry(key: .fiber, value: .augmented(two)))
        let bounds = try NutrientBounds(lower: 1, upper: 2, lowerClosed: true, upperClosed: true, origin: .augmented, unit: .grams,
            sourceValue: .exact(try SourceExactNutrientValue(amount: 1, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [provenance])
        XCTAssertThrowsError(try NutrientEntry(key: .fiber, value: .bounded(bounds)))
    }

    // MARK: Captures (2.2 to 2.4)

    func testCapturesRoundTripAndRefuseExtraOrMissingKeys() throws {
        let built = try F.built(leftOut: [.sodium])
        let encoder = FoundationCanonicalJSONEncoder()
        let payload = try encoder.encode(built.capture)
        XCTAssertEqual(try JSONDecoder().decode(ConfirmNutrientCapture.self, from: payload), built.capture)
        XCTAssertEqual(try encoder.encode(try JSONDecoder().decode(ConfirmNutrientCapture.self, from: payload)), payload)
        XCTAssertTrue(String(decoding: payload, as: UTF8.self).contains("\"generation_id\":\"gen-synthetic-1\""))
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        object["extra"] = 1
        XCTAssertThrowsError(try JSONDecoder().decode(ConfirmNutrientCapture.self, from: try JSONSerialization.data(withJSONObject: object)))
        object["extra"] = nil
        object["generation_id"] = nil
        XCTAssertThrowsError(try JSONDecoder().decode(ConfirmNutrientCapture.self, from: try JSONSerialization.data(withJSONObject: object)),
                             "a nullable key is still required")
        let choices = try XCTUnwrap(ConfirmEnrichmentEvidence.choices(built.choicesEvidence))
        XCTAssertEqual(choices.leftOutKeys, [.sodium])
        let details = try ConfirmDetailsCapture(model: "typesafe/jev-1.13", provider: "TypeSafe", endpoint: "https://example.invalid/v1/systemone",
            generationID: nil, requestBody: "{}", response: "{}", responseSHA256: try digester.sha256(Data("{}".utf8)).value,
            answers: [.init(fact: "preparation", choice: "as_sold", confidence: 0.9)], applied: ["preparation"])
        let detailsPayload = try encoder.encode(details)
        XCTAssertTrue(String(decoding: detailsPayload, as: UTF8.self).contains("\"generation_id\":null"))
        XCTAssertEqual(try JSONDecoder().decode(ConfirmDetailsCapture.self, from: detailsPayload), details)
    }

    /// G12 (fixture half): each reader selects by its own method version and ignores the others.
    func testReadersSelectByMethodVersion() throws {
        let built = try F.built()
        XCTAssertNotNil(ConfirmEnrichmentEvidence.nutrients(built.captureEvidence))
        XCTAssertNil(ConfirmEnrichmentEvidence.choices(built.captureEvidence))
        XCTAssertNil(ConfirmEnrichmentEvidence.details(built.captureEvidence))
        XCTAssertNotNil(ConfirmEnrichmentEvidence.choices(built.choicesEvidence))
        XCTAssertFalse(ApprovedEstimateSource.isManifest(built.captureEvidence))
        XCTAssertFalse(ApprovedEstimateSource.isLeftOut(built.choicesEvidence))
        XCTAssertTrue(ConfirmEnrichmentVersions.isEnrichmentEvidence(built.choicesEvidence))
    }

    // MARK: Request inputs, response and row checks

    func testRequestInputsDecodeFromTheStoredBody() throws {
        let inputs = try F.inputs()
        XCTAssertEqual(ConfirmNutrientRequestInputs.decode(requestBody: try F.requestBody(inputs)), inputs)
        XCTAssertNil(ConfirmNutrientRequestInputs.decode(requestBody: "{\"messages\":[]}"))
        let details = try ConfirmDetailsRequestInputs(description: F.description(), knownDetails: ["bone": "not_applicable"],
                                                  asked: [.preparation, .fortification])
        let body = "{\"model\":\"typesafe/jev-1.13\",\"state\":" + String(decoding: try FoundationCanonicalJSONEncoder().encode(details), as: UTF8.self) + "}"
        XCTAssertEqual(ConfirmDetailsRequestInputs.decode(requestBody: body), details)
        XCTAssertFalse(ConfirmDetailsFact.fortification.choices.contains("fortified"), "fortified is never a choice")
    }

    func testAShapeFailureFailsTheWholeResponse() throws {
        let inputs = try F.inputs()
        func check(_ data: Data) -> ConfirmEnrichmentResponseFailure? {
            if case let .failure(failure) = ConfirmNutrientResponseCheck.check(data, request: inputs, models: [F.model], provider: F.provider) { return failure }
            return nil
        }
        XCTAssertNil(check(try F.response(values: F.defaultValues())))
        XCTAssertEqual(check(try F.response(values: F.defaultValues(), model: "other/model")), .modelMismatch)
        XCTAssertEqual(check(try F.response(values: F.defaultValues(), provider: "Other")), .providerMismatch)
        XCTAssertEqual(check(try F.response(values: F.defaultValues(), basis: "per_100_ml")), .basisMismatch)
        XCTAssertEqual(check(try F.response(values: F.defaultValues(), finish: "length")), .notStopped)
        XCTAssertEqual(check(try F.response(values: [["nutrient": "fiber", "value": "6.5", "unit": "g"]])), .shape)
        XCTAssertEqual(check(Data(repeating: 32, count: 100_001)), .tooLarge)
    }

    func testEachRowCodeDropsItsRowOnly() {
        typealias Row = ConfirmNutrientRowCheck.ReceivedRow
        let rows = [Row(nutrient: "fiber", value: "6.5", unit: "g"), Row(nutrient: "vitamin_c", value: "1", unit: "mg"),
                    Row(nutrient: "sodium", value: "120", unit: "g"), Row(nutrient: "sugar", value: "-1", unit: "g"),
                    Row(nutrient: "fat_saturated", value: "20", unit: "g"), Row(nutrient: "protein", value: "150", unit: "g"),
                    Row(nutrient: "iron", value: "1", unit: "mg"), Row(nutrient: "iron", value: "2", unit: "mg"),
                    Row(nutrient: "energy_consumed", value: "950", unit: "kcal")]
        let eligible: Set<NutrientKey> = [.fiber, .sodium, .sugar, .fatSaturated, .protein, .iron, .energyConsumed]
        let results = ConfirmNutrientRowCheck.results(rows: rows, eligible: eligible, basis: .per100Grams, known: [.fatTotal: 12])
        XCTAssertEqual(results, [.kept, .unknownNutrient, .unit, .value, .exceedsParent, .impossibleValue,
                                 .duplicateNutrient, .duplicateNutrient, .impossibleValue])
        let zero = ConfirmNutrientRowCheck.results(rows: [Row(nutrient: "fiber", value: "0", unit: "g")], eligible: [.fiber],
                                                   basis: .per100Grams, known: [:])
        XCTAssertEqual(zero, [.kept], "a zero is kept")
    }

    func testTheEnergyCheckDropsOnlyEstimatedValues() {
        XCTAssertEqual(EstimateEnergyCheck.dropped(merged: [.energyConsumed: 400, .protein: 10, .carbohydrates: 60, .fatTotal: 12],
                                                   estimated: [.fatTotal]), [])
        XCTAssertEqual(EstimateEnergyCheck.dropped(merged: [.energyConsumed: 400, .protein: 10, .carbohydrates: 60, .fatTotal: 40],
                                                   estimated: [.fatTotal, .fiber]), [.fatTotal])
        XCTAssertEqual(EstimateEnergyCheck.dropped(merged: [.energyConsumed: 400, .protein: 10, .carbohydrates: 60, .fatTotal: 40],
                                                   estimated: [.fiber]), [], "no estimate among the four")
    }

    // MARK: Verification (2.4, the format half of G8)

    func testASavedValueThatEqualsAKeptRowVerifies() throws {
        let built = try F.built(leftOut: [.sodium])
        let nutrients = try F.nutrients([.fiber: try F.value(6.5, key: .fiber, provenance: try F.provenance(built.captureEvidence, key: .fiber))])
        let outcome = ConfirmEnrichmentVerification.verify(
            nutrients: nutrients, resolutionVersionID: built.resolutionVersionID,
            citedEvidenceIDs: [built.captureEvidence.evidenceID, built.choicesEvidence.evidenceID],
            evidence: [built.captureEvidence, built.choicesEvidence], layer: [:], digester: digester)
        guard case let .verified(verified) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(verified.values, [.fiber: 6.5])
    }

    func testTamperingWithAnyBindingIsNotAvailable() throws {
        let built = try F.built(leftOut: [.sodium])
        let provenance = try F.provenance(built.captureEvidence, key: .fiber)
        let cited = [built.captureEvidence.evidenceID, built.choicesEvidence.evidenceID]
        func verify(_ nutrients: NutrientSet, version: ResolutionVersionID? = nil, evidence: [CaptureEvidence]? = nil,
                    cited ids: [EvidenceID]? = nil) -> ConfirmEnrichmentVerification.Outcome {
            ConfirmEnrichmentVerification.verify(nutrients: nutrients, resolutionVersionID: version ?? built.resolutionVersionID,
                citedEvidenceIDs: ids ?? cited, evidence: evidence ?? [built.captureEvidence, built.choicesEvidence],
                layer: [:], digester: digester)
        }
        // A changed value, a left-out key saved, the wrong version, an uncited choices item.
        XCTAssertEqual(verify(try F.nutrients([.fiber: try F.value(7, key: .fiber, provenance: provenance)])), .notAvailable)
        XCTAssertEqual(verify(try F.nutrients([
            .fiber: try F.value(6.5, key: .fiber, provenance: provenance),
            .sodium: try F.value(120, key: .sodium, provenance: try F.provenance(built.captureEvidence, key: .sodium))
        ])), .notAvailable)
        let fiber = try F.nutrients([.fiber: try F.value(6.5, key: .fiber, provenance: provenance)])
        XCTAssertEqual(verify(fiber, version: try F.id(9999)), .notAvailable)
        XCTAssertEqual(verify(fiber, cited: [built.captureEvidence.evidenceID]), .notAvailable)
        // An altered capture payload no longer hashes to its stored hash.
        guard case let .text(payload) = built.captureEvidence.originalPayload else { return XCTFail() }
        let altered = try CaptureEvidence(evidenceID: built.captureEvidence.evidenceID, kind: .labelText,
            capturedAt: built.captureEvidence.capturedAt, locale: built.captureEvidence.locale,
            captureMethod: built.captureEvidence.captureMethod, captureMethodVersion: built.captureEvidence.captureMethodVersion,
            originalPayload: .text(LedgerText(payload.value.replacingOccurrences(of: "6.5", with: "7"))),
            byteHash: built.captureEvidence.byteHash)
        XCTAssertEqual(verify(fiber, evidence: [altered, built.choicesEvidence]), .notAvailable)
        XCTAssertEqual(verify(try F.nutrients([:]), evidence: [], cited: []), ConfirmEnrichmentVerification.Outcome.none)
    }

    func testALayerKeyMustBeRecordedAsDroppedByTheLayer() throws {
        let built = try F.built()
        let nutrients = try F.nutrients([.sodium: try F.value(120, key: .sodium, provenance: try F.provenance(built.captureEvidence, key: .sodium))])
        let outcome = ConfirmEnrichmentVerification.verify(
            nutrients: nutrients, resolutionVersionID: built.resolutionVersionID,
            citedEvidenceIDs: [built.captureEvidence.evidenceID, built.choicesEvidence.evidenceID],
            evidence: [built.captureEvidence, built.choicesEvidence], layer: [.fiber: 5], digester: digester)
        XCTAssertEqual(outcome, .notAvailable, "the layer fills fiber, but the choices item does not record it")
    }

    // MARK: Review hardening

    func testRowValuesKeepTheNumberTextAsReceived() throws {
        let inputs = try F.inputs()
        let content = #"{"basis":"per_100_g","schema":"confirm-nutrient-estimate-v1","values":[{"nutrient":"fiber","unit":"g","value":12.50},{"nutrient":"sodium","unit":"mg","value":1e2}]}"#
        let body = try JSONSerialization.data(withJSONObject: [
            "id": "gen-1", "model": F.model, "provider": F.provider,
            "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": content, "tool_calls": [Any]()]]]
        ])
        guard case let .success(parsed) = ConfirmNutrientResponseCheck.check(body, request: inputs, models: [F.model], provider: F.provider) else {
            return XCTFail("an empty tool_calls list is no tool call")
        }
        XCTAssertEqual(parsed.rows.map(\.value), ["12.50", "1e2"])
        XCTAssertEqual(ConfirmNutrientResponseCheck.captureRows(parsed, request: inputs).map(\.result), ["kept", "kept"])
    }

    func testMalformedStoredBodiesDecodeToNilWithoutTrapping() {
        for body in [#"{"state":"x"}"#, #"{"state":null}"#, #"{"state":1}"#, "not json"] {
            XCTAssertNil(ConfirmDetailsRequestInputs.decode(requestBody: body), body)
            XCTAssertNil(ConfirmNutrientRequestInputs.decode(requestBody: body), body)
        }
    }

    func testTheWriteSideRefusesWhatTheDecoderRefuses() throws {
        XCTAssertThrowsError(try ConfirmNutrientRequestInputs.Known(nutrient: .protein, value: 1, source: "from somewhere"))
        XCTAssertThrowsError(try ConfirmNutrientRequestInputs.Known(nutrient: .protein, value: -1, source: "from the label"))
        XCTAssertThrowsError(try ConfirmNutrientRequestInputs(description: F.description(), identity: [:], basis: .per100Grams,
                                                              known: [], eligible: [.caffeine]), "an unmeasured key is never requested")
        XCTAssertThrowsError(try ConfirmNutrientRequestInputs(description: F.description(), identity: [:], basis: .per100Grams,
                                                              known: [], eligible: []))
        XCTAssertThrowsError(try ConfirmDetailsRequestInputs(description: F.description(), knownDetails: ["bone": "boneless"], asked: [.bone]))
        XCTAssertThrowsError(try ConfirmDetailsCapture(model: "m", provider: "p", endpoint: "e", generationID: nil, requestBody: "{}",
            response: "{}", responseSHA256: String(repeating: "0", count: 64), answers: [], applied: ["bone"]))
    }

    /// A capture rehashed after its rows were changed no longer matches its own stored reply.
    func testARehashedCaptureWhoseRowsDisagreeIsNotAvailable() throws {
        let built = try F.built(leftOut: [.sodium])
        let encoder = FoundationCanonicalJSONEncoder()
        func evidence(_ capture: ConfirmNutrientCapture, capturedAt: Date = F.capturedAt) throws -> CaptureEvidence {
            let payload = try encoder.encode(capture)
            return try CaptureEvidence(evidenceID: built.captureEvidence.evidenceID, kind: .labelText, capturedAt: capturedAt,
                locale: LedgerText("en_GB"), captureMethod: LedgerText(ConfirmEnrichmentVersions.nutrientCaptureMethod),
                captureMethodVersion: LedgerText(ConfirmEnrichmentVersions.nutrientCaptureMethodVersion),
                originalPayload: .text(LedgerText(String(decoding: payload, as: UTF8.self))), byteHash: digester.sha256(payload))
        }
        let c = built.capture
        let changedRows = try ConfirmNutrientCapture(model: c.model, provider: c.provider, endpoint: c.endpoint, generationID: c.generationID,
            requestBody: c.requestBody, response: c.response, responseSHA256: c.responseSHA256,
            rows: c.rows.map { .init(nutrient: $0.nutrient, value: $0.nutrient == "fiber" ? "7" : $0.value, unit: $0.unit,
                                     result: ConfirmNutrientRowResult(rawValue: $0.result)!) })
        let wrongHash = try ConfirmNutrientCapture(model: c.model, provider: c.provider, endpoint: c.endpoint, generationID: c.generationID,
            requestBody: c.requestBody, response: c.response, responseSHA256: String(repeating: "d", count: 64), rows: c.rows)
        for (name, item) in [("rows", try evidence(changedRows)), ("hash", try evidence(wrongHash)),
                             ("time", try evidence(c, capturedAt: F.capturedAt.addingTimeInterval(1)))] {
            let hash = try XCTUnwrap(item.byteHash)
            let choices = ConfirmNutrientChoices(resolutionVersionID: built.resolutionVersionID.rawValue, captureSHA256: hash.value,
                                                 leftOut: [.sodium], layerDropped: [], mergeParentDropped: [], mergeEnergyDropped: [])
            let choicesPayload = try encoder.encode(choices)
            let choicesItem = try CaptureEvidence(evidenceID: built.choicesEvidence.evidenceID, kind: .labelText, capturedAt: F.capturedAt,
                locale: LedgerText("en_GB"), captureMethod: LedgerText(ConfirmEnrichmentVersions.choicesCaptureMethod),
                captureMethodVersion: LedgerText(ConfirmEnrichmentVersions.choicesMethodVersion),
                originalPayload: .text(LedgerText(String(decoding: choicesPayload, as: UTF8.self))), byteHash: digester.sha256(choicesPayload))
            // The provenance is rebuilt for the rehashed item, at the original time, so only the named binding differs.
            let provenance = NutrientProvenance(sourceKind: .openRouterEstimate, sourceID: try ExternalIdentifier(OpenRouterEstimateProvenance.sourceID),
                sourceReleaseID: try ExternalIdentifier(OpenRouterEstimateProvenance.sourceReleaseID(captureHash: hash)),
                recordID: try ExternalIdentifier(OpenRouterEstimateProvenance.recordID(evidenceID: item.evidenceID)),
                evidenceID: item.evidenceID, capturedAt: F.capturedAt, responseHash: hash,
                manifestReference: try LedgerText(OpenRouterEstimateProvenance.manifestReference(.fiber)))
            let amount: Double = name == "rows" ? 7 : 6.5
            let outcome = ConfirmEnrichmentVerification.verify(
                nutrients: try F.nutrients([.fiber: try F.value(amount, key: .fiber, provenance: provenance)]),
                resolutionVersionID: built.resolutionVersionID, citedEvidenceIDs: [item.evidenceID, choicesItem.evidenceID],
                evidence: [item, choicesItem], layer: [:], digester: digester)
            XCTAssertEqual(outcome, .notAvailable, name)
        }
    }

    func testTheFloorReadsTheMethodVersionAndStripReadsLabelTextOnly() throws {
        let other = try CaptureEvidence(evidenceID: F.id(9050), kind: .barcode, capturedAt: F.capturedAt, locale: LedgerText("en_GB"),
            captureMethod: LedgerText("scan"), captureMethodVersion: LedgerText(ConfirmEnrichmentVersions.nutrientCaptureMethodVersion),
            originalPayload: .barcode(value: try LedgerText("5000000000017"), symbology: try LedgerText("ean13")))
        var records = LedgerMutation()
        records.evidence = [other]
        // The floor stays conservative (gate 2.7: the method version alone raises it); strip and skip
        // act only on `.labelText` items.
        XCTAssertTrue(CanonicalFoodProjection.holdsConfirmEnrichment(records))
        XCTAssertFalse(ConfirmEnrichmentVersions.isEnrichmentEvidence(other))
    }

    // MARK: Citation (2.4a)

    func testOwnIDsDropEveryCE1AndLeaveOutItem() throws {
        let built = try F.built()
        let product: EvidenceID = try F.id(1)
        let candidate = try ProviderNeutralCandidate(
            sourceReleaseID: try ExternalIdentifier("off"), recordID: try ExternalIdentifier("off:gtin:1"),
            identity: try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
                drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: .per100Grams),
            edibleQuantity: .known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
            nutrients: try F.nutrients([:]), evidenceIDs: [product, built.captureEvidence.evidenceID, built.choicesEvidence.evidenceID],
            matchMetadata: nil)
        let evidence = [built.captureEvidence, built.choicesEvidence]
        XCTAssertTrue(ConfirmEnrichmentCitation.citesEnrichment(candidate, evidence: evidence))
        XCTAssertEqual(ConfirmEnrichmentCitation.ownEvidenceIDs(candidate, evidence: evidence), [product])
        XCTAssertEqual(ConfirmEnrichmentCitation.enrichmentEvidenceIDs(evidence),
                       [built.captureEvidence.evidenceID, built.choicesEvidence.evidenceID])
    }
}

/// A mutable copy of a provenance, for mutation tests.
private struct Parts {
    var sourceID, sourceReleaseID: ExternalIdentifier
    var recordID: ExternalIdentifier?
    var evidenceID: EvidenceID?
    var capturedAt: Date?
    var responseHash: SHA256Digest?
    var manifestReference: LedgerText?
    var decisionID: CandidateDecisionID?
    var assertionID: AssertionID?
    var transforms: [NutrientTransform]

    init(_ p: NutrientProvenance) {
        sourceID = p.sourceID; sourceReleaseID = p.sourceReleaseID; recordID = p.recordID; evidenceID = p.evidenceID
        capturedAt = p.capturedAt; responseHash = p.responseHash; manifestReference = p.manifestReference
        decisionID = p.decisionID; assertionID = p.assertionID; transforms = p.transforms
    }

    var provenance: NutrientProvenance {
        NutrientProvenance(sourceKind: .openRouterEstimate, sourceID: sourceID, sourceReleaseID: sourceReleaseID, recordID: recordID,
                           evidenceID: evidenceID, capturedAt: capturedAt, responseHash: responseHash,
                           manifestReference: manifestReference, decisionID: decisionID, assertionID: assertionID, transforms: transforms)
    }
}

private extension NutrientValue {
    func validatedEntry(_ key: NutrientKey) throws -> NutrientEntry { try NutrientEntry(key: key, value: self) }
}
