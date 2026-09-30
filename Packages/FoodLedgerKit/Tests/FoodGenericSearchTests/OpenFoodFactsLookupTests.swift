import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

final class OpenFoodFactsLookupTests: XCTestCase {
    private let clock = OFFFixedClock()
    private func request(code: String = "3274080005003") throws -> PackagedFoodLookupRequest {
        let barcode = try LedgerText(code)
        let evidence = try CaptureEvidence(evidenceID: OFFIDs().makeID(EvidenceTag.self), kind: .barcode,
            capturedAt: clock.now(), locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"),
            captureMethodVersion: LedgerText("v1"), originalPayload: .barcode(value: barcode, symbology: LedgerText("ean-13")))
        return try PackagedFoodLookupRequest(identity: BarcodeClassifier.classify(code: barcode, symbology: .ean13), evidence: evidence)
    }
    private func response(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var product: [String: Any] = ["code": "3274080005003", "product_name": "Synthetic food", "brands": "Synthetic",
            "quantity": "500 g", "nutrition_data_per": "100g", "nutriments": ["energy-kcal_100g": 120, "energy-kcal_unit": "kcal",
                "proteins_100g": 8, "proteins_unit": "g", "fat_100g": 0, "fat_unit": "g"]]
        change(&product)
        return try JSONSerialization.data(withJSONObject: ["status": "success", "product": product], options: .sortedKeys)
    }

    func testWholeRecordCandidatePreservesScanUnknownsAndSourceNotices() async throws {
        let transport = OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try response()))
        let request = try request()
        guard case let .candidate(input) = try await OpenFoodFactsLookup(transport: transport, clock: clock).lookup(request) else { return XCTFail("Expected candidate") }
        XCTAssertEqual(input.evidence, [request.evidence])
        let candidate = try XCTUnwrap(input.candidates.first)
        XCTAssertEqual(candidate.barcode?.value, "03274080005003")
        XCTAssertEqual(candidate.candidate.identity.preparation.kind, .unknown)
        XCTAssertEqual(candidate.candidate.nutrients.entries.count, 39)
        guard case let .augmented(energy) = candidate.candidate.nutrients.entries.first(where: { $0.key == .energyConsumed })?.value else { return XCTFail("Source estimate required") }
        XCTAssertEqual(energy.amount, 120)
        XCTAssertEqual(candidate.candidate.nutrients.entries.first(where: { $0.key == .sodium })?.value, .unknown(.notDeclared))
        XCTAssertTrue(input.sourceReleases[0].licence.value.contains("dbcl"))
        XCTAssertTrue(input.sourceReleases[0].attribution.value.contains("/product/3274080005003"))
        let codes = await transport.codes
        XCTAssertEqual(codes, ["3274080005003"])
    }

    func testMissingAmbiguousLiquidAndUnsupportedUnitsNeverOpenBlankConfirmation() async throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0.removeValue(forKey: "nutrition_data_per") }, { $0["nutrition_data_per"] = "serving" },
            { $0["quantity"] = "500 ml" }, { $0.removeValue(forKey: "quantity") },
            { $0["nutriments"] = [:] }, { $0["product_name"] = " " },
            { $0["nutriments"] = ["proteins_100g": true, "proteins_unit": "g"] },
            { $0["nutriments"] = ["proteins_100g": 8, "proteins_unit": "mg"] },
            { $0["categories_tags"] = ["en:dietary-supplements"] },
            { $0["nutrition"] = "invalid" },
            { $0["nutriments"] = ["proteins_100g": 8, "proteins_unit": "g", "proteins_modifier": true] }
        ]
        for change in changes {
            let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try response(change))), clock: clock)
            let outcome = try await source.lookup(request())
            XCTAssertEqual(outcome, .insufficientData)
        }
    }

    func testUnavailableRateLimitMismatchMalformedAndOversizeFailClosed() async throws {
        let cases: [(OFFProductResponse, OFFLookupError)] = [
            (OFFProductResponse(status: 503, body: Data()), .unavailable),
            (OFFProductResponse(status: 429, body: Data()), .rateLimited),
            (OFFProductResponse(status: 200, body: try response { $0["code"] = "4006381333931" }), .codeMismatch),
            (OFFProductResponse(status: 200, body: Data("{}".utf8)), .malformedResponse),
            (OFFProductResponse(status: 200, body: Data(repeating: 0, count: 500_001)), .oversizedResponse)
        ]
        for (response, expected) in cases {
            let transport = OFFFixtureTransport(response: response)
            do { _ = try await OpenFoodFactsLookup(transport: transport, clock: clock).lookup(request()); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? OFFLookupError, expected) }
            let calls = await transport.codes.count
            XCTAssertEqual(calls, 1) // No adapter retry.
        }
        let missing = try JSONSerialization.data(withJSONObject: ["status": "failure", "result": ["id": "product_not_found"]])
        let outcome = try await OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 200, body: missing)), clock: clock).lookup(request())
        XCTAssertEqual(outcome, .notFound)
        let missing404 = try await OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 404, body: missing)), clock: clock).lookup(request())
        XCTAssertEqual(missing404, .notFound)
    }

    func testCancellationBeforeLookupDoesNotReachTransport() async throws {
        let transport = OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try response()))
        let source = OpenFoodFactsLookup(transport: transport, clock: clock)
        let input = try request()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await source.lookup(input)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let calls = await transport.codes.count
        XCTAssertEqual(calls, 0)
    }

    func testInvalidAndLocalIdentitiesNeverReachTransport() async throws {
        let transport = OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try response()))
        let evidence = try request().evidence
        for identity in [try BarcodeIdentity.gtin(LedgerText("garbage")), try .local(namespace: LedgerText("store"), code: LedgerText("123"))] {
            do { _ = try await OpenFoodFactsLookup(transport: transport, clock: clock).lookup(PackagedFoodLookupRequest(identity: identity, evidence: evidence)); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? OFFLookupError, .unsupportedCode) }
        }
        let calls = await transport.codes.count
        XCTAssertEqual(calls, 0)
    }

    func testNormalizationWarningsRequireCanonicalExactCodeAndNoOtherWarnings() async throws {
        let base = try JSONSerialization.jsonObject(with: response()) as! [String: Any]
        for (message, impact, code, accepts) in [("different_normalized_product_code", "none", "3274080005003", true),
            ("different_normalized_product_code", "none", "4006381333931", false),
            ("unknown_warning", "none", "3274080005003", false),
            ("different_normalized_product_code", "warning", "3274080005003", false)] {
            var document = base; document["status"] = "success_with_warnings"
            var product = document["product"] as! [String: Any]; product["code"] = code; document["product"] = product
            document["warnings"] = [["message": ["id": message], "impact": ["id": impact]]]
            let body = try JSONSerialization.data(withJSONObject: document)
            let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 200, body: body)), clock: clock)
            do {
                let outcome = try await lookup.lookup(request())
                guard accepts, case .candidate = outcome else { return XCTFail("Unexpected warning acceptance") }
            } catch { XCTAssertFalse(accepts) }
        }
    }

    func testPublicDevelopmentReplay() async throws {
        guard let path = ProcessInfo.processInfo.environment["WHR_OFF_REPLAY"] else {
            throw XCTSkip("Explicit offline public-response replay only; no live traffic")
        }
        let directory = URL(fileURLWithPath: path)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as! [String: Any]
        let cases = manifest["cases"] as! [[String: Any]]
        var rows: [[String: Any]] = []
        for entry in cases {
            let caseID = entry["case_id"] as! String
            let file = directory.appendingPathComponent(caseID + ".json")
            var row: [String: Any] = ["caseID": caseID, "category": entry["category"]!, "exactVariant": "unadjudicated", "labelFreshness": "unknown"]
            guard FileManager.default.fileExists(atPath: file.path) else {
                row["outcome"] = "transportOrHTTPFailure"; rows.append(row); continue
            }
            let body = try Data(contentsOf: file)
            let input = try request(code: entry["gtin"] as! String)
            let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: entry["httpStatus"] as! Int, body: body)), clock: clock)
            do {
                switch try await lookup.lookup(input) {
                case let .candidate(candidate):
                    XCTAssertEqual(candidate.evidence, [input.evidence])
                    let nutrients = candidate.candidates[0].candidate.nutrients.entries
                    row["outcome"] = "candidate"
                    row["known"] = nutrients.filter { if case .augmented = $0.value { return true }; return false }.count
                    row["bounded"] = nutrients.filter { if case .bounded = $0.value { return true }; return false }.count
                    row["unknown"] = nutrients.filter { if case .unknown = $0.value { return true }; return false }.count
                case .notFound: row["outcome"] = "notFound"
                case .insufficientData: row["outcome"] = "insufficientData"
                }
            } catch { row["outcome"] = "adapterFailure"; row["error"] = String(describing: error) }
            rows.append(row)
        }
        let report: [String: Any] = ["version": "off-public-legacy-development-v2", "independentAccuracyAcceptance": false,
            "observationStartedAt": manifest["startedAt"]!, "denominator": rows.count, "rows": rows]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("adapter-report.json"))
    }

    func testModernPackagingSetPreservesBoundsAndDoesNotMixAggregate() async throws {
        let body = try response { product in
            product.removeValue(forKey: "nutrition_data_per")
            product["nutriments"] = [:]
            product["nutrition"] = ["input_sets": [["source": "packaging", "per": "100g", "preparation": "as_sold",
                "nutrients": ["proteins": ["value": 4.4, "unit": "g"],
                              "saturated-fat": ["value": 0.1, "unit": "g", "modifier": "<"],
                              "sugars": ["value": 2, "unit": "g", "modifier": "~"]]]],
                "aggregated_set": ["nutrients": ["fiber": ["value": 99, "unit": "g"]]]]
        }
        let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 200, body: body)), clock: clock)
        guard case let .candidate(input) = try await lookup.lookup(request()) else { return XCTFail("Modern source must work") }
        let entries = input.candidates[0].candidate.nutrients.entries
        guard case let .bounded(bound) = entries.first(where: { $0.key == .fatSaturated })?.value else { return XCTFail("Preserve less than") }
        XCTAssertTrue(try XCTUnwrap(bound.provenance[0].manifestReference).value.contains("nutrition/input_sets/0/nutrients/saturated-fat"))
        XCTAssertEqual(bound.upper, 0.1); XCTAssertFalse(bound.upperClosed); XCTAssertEqual(bound.origin, .augmented)
        XCTAssertEqual(entries.first(where: { $0.key == .fiber })?.value, .unknown(.notDeclared))
        XCTAssertEqual(entries.first(where: { $0.key == .sugar })?.value, .unknown(.noCompatibleSource))
        XCTAssertEqual(input.sourceReleases[0].pipelineVersion.value, "off-product-projection-v4")
    }

    func testModernAmbiguousPreparedOrVolumeSetsDeclineWithoutLegacyFallback() async throws {
        let valid: [String: Any] = ["source": "packaging", "per": "100g", "preparation": "as_sold",
            "nutrients": ["proteins": ["value": 8, "unit": "g"]]]
        var prepared = valid; prepared["preparation"] = "prepared"
        var liquid = valid; liquid["per"] = "100ml"
        var estimated = valid; estimated["source"] = "estimate"
        for sets in [[valid, valid], [prepared], [liquid], [estimated], []] {
            let body = try response { $0["nutrition"] = ["input_sets": sets] }
            let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 200, body: body)), clock: clock)
            let outcome = try await lookup.lookup(request())
            XCTAssertEqual(outcome, .insufficientData)
        }
    }

    private func sodiumResponse(_ sodium: [String: Any]) throws -> Data {
        try response { product in
            product["nutrition"] = ["input_sets": [["source": "packaging", "per": "100g", "preparation": "as_sold",
                "nutrients": ["proteins": ["value": 8, "unit": "g"], "sodium": sodium,
                              "salt": ["value": 0.13, "unit": "g"]]]],
                "aggregated_set": ["nutrients": ["sodium": ["value": 99, "unit": "mg"]]]]
        }
    }

    private func sodiumCandidate(_ sodium: [String: Any]) async throws -> PopulatedFoodConfirmation {
        let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: try sodiumResponse(sodium))), clock: clock)
        guard case let .candidate(input) = try await source.lookup(request()) else { throw OFFLookupError.malformedResponse }
        return input
    }

    func testDirectSodiumRetainsSourceUnitsAndVersionedConversion() async throws {
        for (value, unit, expected) in [(0.052, "g", 52.0), (52.0, "mg", 52.0), (0.0, "g", 0.0)] {
            let input = try await sodiumCandidate(["value": value, "unit": unit, "value_computed": 999])
            guard case let .augmented(sodium) = input.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .sodium })?.value,
                  case let .exact(original) = sodium.sourceValue else { return XCTFail("Expected declared sodium") }
            XCTAssertEqual(sodium.amount, expected, accuracy: 1e-10); XCTAssertEqual(sodium.unit, .milligrams)
            XCTAssertEqual(original.amount, value, accuracy: 1e-12); XCTAssertEqual(original.unit.value, unit)
            XCTAssertEqual(original.basis, .per100Grams)
            XCTAssertEqual(sodium.provenance[0].transforms.count, unit == "g" ? 1 : 0)
            if unit == "g" {
                XCTAssertEqual(sodium.provenance[0].transforms[0].transformID.value, "mass-g-to-mg")
                XCTAssertEqual(sodium.provenance[0].transforms[0].transformVersion.value, "v1")
            }
            XCTAssertTrue(try XCTUnwrap(sodium.provenance[0].manifestReference).value.hasSuffix("nutrition/input_sets/0/nutrients/sodium"))
            XCTAssertTrue(input.sourceReleases[0].sourceReleaseID.value.contains("projection:off-product-projection-v4:schema:off-v3.6-explicit-basis-candidates-v4:"))
            let repeated = try await sodiumCandidate(["value": value, "unit": unit, "value_computed": 999])
            XCTAssertEqual(input.sourceReleases, repeated.sourceReleases)
            XCTAssertFalse(FoodConfirmationState(input: input).unresolvedIdentity.isEmpty)
        }
    }

    func testSodiumBoundsConvertWithoutLosingOriginalEndpoints() async throws {
        for modifier in ["<", "<=", ">", ">="] {
            let input = try await sodiumCandidate(["value": 0.052, "unit": "g", "modifier": modifier])
            guard case let .bounded(bound) = input.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .sodium })?.value,
                  case let .bounded(original) = bound.sourceValue else { return XCTFail("Expected source bound") }
            if modifier.hasPrefix("<") {
                XCTAssertEqual(try XCTUnwrap(bound.upper), 52, accuracy: 1e-10); XCTAssertNil(bound.lower)
                XCTAssertEqual(try XCTUnwrap(original.upper), 0.052, accuracy: 1e-12); XCTAssertNil(original.lower)
            } else {
                XCTAssertEqual(try XCTUnwrap(bound.lower), 52, accuracy: 1e-10); XCTAssertNil(bound.upper)
                XCTAssertEqual(try XCTUnwrap(original.lower), 0.052, accuracy: 1e-12); XCTAssertNil(original.upper)
            }
            XCTAssertEqual(bound.upperClosed, modifier == "<="); XCTAssertEqual(bound.lowerClosed, modifier == ">=")
            XCTAssertEqual(original.upperClosed, bound.upperClosed); XCTAssertEqual(original.lowerClosed, bound.lowerClosed)
            XCTAssertEqual(original.unit.value, "g"); XCTAssertEqual(bound.unit, .milligrams)
            XCTAssertEqual(bound.provenance[0].transforms.count, 1)
        }
    }

    func testUnsupportedSodiumNeverFallsBackToSaltComputedOrAggregate() async throws {
        let invalid: [[String: Any]] = [[:], ["value_computed": 0.052, "unit": "g"],
            ["value": true, "unit": "g"], ["value": -0.052, "unit": "g"],
            ["value": "0.052", "unit": "g"], ["value": 0.052, "unit": "kg"],
            ["value": 0.052], ["value": 0.052, "unit": "g", "modifier": "~"],
            ["value": 0.052, "unit": "g", "modifier": true], ["value": Double.greatestFiniteMagnitude, "unit": "g"]]
        for raw in invalid {
            let input = try await sodiumCandidate(raw)
            guard case .unknown = input.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .sodium })?.value else {
                return XCTFail("Unsupported sodium admitted: \(raw)")
            }
        }
    }

    func testLegacySodiumRemainsUnknownRegardlessOfContributorUnit() async throws {
        for unit in ["g", "mg"] {
            let body = try response { $0["nutriments"] = ["proteins_100g": 8, "proteins_unit": "g", "sodium_100g": 0.052, "sodium_unit": unit] }
            let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: body)), clock: clock)
            guard case let .candidate(input) = try await source.lookup(request()) else { return XCTFail() }
            XCTAssertEqual(input.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .sodium })?.value, .unknown(.notDeclared))
        }
    }

    private func volumeResponse(pack: String = "1 l", change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        try response { product in
            product["quantity"] = pack
            let mass: [String: Any] = ["source": "packaging", "per": "100g", "preparation": "as_sold",
                "nutrients": ["fiber": ["value": 99, "unit": "g"], "fat": ["value": 99, "unit": "g"]]]
            var volume: [String: Any] = ["source": "packaging", "per": "100ml", "per_quantity": 100, "per_unit": "ml", "preparation": "as_sold",
                "nutrients": ["proteins": ["value": 3, "unit": "g"], "fat": ["value": 1.8, "unit": "g"],
                    "sodium": ["value": 0.04, "unit": "g"], "saturated-fat": ["value": 0.1, "unit": "g", "modifier": "<"]]]
            change(&volume)
            product["nutrition"] = ["input_sets": [mass, volume]]
        }
    }

    func testExplicitVolumePanelPreservesBasisWithoutMassPanelBackfill() async throws {
        for pack in ["250 ml", "25 cl", "2.5 dl", "1 l"] {
            let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: try volumeResponse(pack: pack))), clock: clock)
            guard case let .candidate(input) = try await source.lookup(request()) else { return XCTFail(pack) }
            let c = input.candidates[0].candidate
            XCTAssertEqual(c.identity.servingBasis, .per100Millilitres)
            XCTAssertEqual(c.edibleQuantity, try .known(PositiveQuantity(value: 100, unit: .millilitres), conversionVersionID: nil))
            XCTAssertTrue(input.candidates[0].variant?.value.contains("per 100 ml") == true)
            XCTAssertEqual(c.nutrients.entries.first(where: { $0.key == .fiber })?.value, .unknown(.notDeclared))
            guard case let .augmented(sodium) = c.nutrients.entries.first(where: { $0.key == .sodium })?.value,
                  case let .exact(original) = sodium.sourceValue else { return XCTFail() }
            XCTAssertEqual(sodium.amount, 40, accuracy: 1e-10); XCTAssertEqual(original.amount, 0.04, accuracy: 1e-12)
            XCTAssertEqual(original.basis, .per100Millilitres)
            XCTAssertTrue(sodium.provenance[0].manifestReference?.value.contains("input_sets/1/nutrients/sodium") == true)
            XCTAssertEqual(sodium.provenance[0].transforms.count, 1)
            guard case let .bounded(bound) = c.nutrients.entries.first(where: { $0.key == .fatSaturated })?.value,
                  case let .bounded(sourceBound) = bound.sourceValue else { return XCTFail() }
            XCTAssertEqual(sourceBound.basis, .per100Millilitres)
            XCTAssertEqual(bound.upper, 0.1); XCTAssertFalse(bound.upperClosed)
        }
    }

    func testVolumeRequiresConsistentExplicitPanelMetadataAndPackageUnit() async throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["per"] = "serving" }, { $0["per"] = "100g" }, { $0.removeValue(forKey: "per") },
            { $0["preparation"] = "prepared" }, { $0["source"] = "estimate" },
            { $0["per_quantity"] = 200 }, { $0["per_quantity"] = true }, { $0["per_quantity"] = "100" },
            { $0["per_unit"] = "g" }, { $0["per_unit"] = NSNull() }
        ]
        for change in changes {
            let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: try volumeResponse(change: change))), clock: clock)
            let result = try await source.lookup(request()); XCTAssertEqual(result, .insufficientData)
        }
        for pack in ["250ml / 250g", "one bottle", "250 ounces"] {
            let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: try volumeResponse(pack: pack))), clock: clock)
            let result = try await source.lookup(request()); XCTAssertEqual(result, .insufficientData)
        }
        var envelope = try JSONSerialization.jsonObject(with: volumeResponse()) as! [String: Any]
        var product = envelope["product"] as! [String: Any]
        var nutrition = product["nutrition"] as! [String: Any]
        let panels = nutrition["input_sets"] as! [[String: Any]]
        nutrition["input_sets"] = panels + [panels[1]]; product["nutrition"] = nutrition; envelope["product"] = product
        let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: try JSONSerialization.data(withJSONObject: envelope))), clock: clock)
        let result = try await source.lookup(request()); XCTAssertEqual(result, .insufficientData)
    }

    func testVolumeComputedSodiumDoesNotBorrowMassOrLegacyNutrition() async throws {
        let body = try volumeResponse { $0["nutrients"] = ["proteins": ["value": 3, "unit": "g"], "sodium": ["value_computed": 0.04, "unit": "g"]] }
        let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: body)), clock: clock)
        guard case let .candidate(input) = try await source.lookup(request()) else { return XCTFail() }
        let entries = input.candidates[0].candidate.nutrients.entries
        XCTAssertEqual(entries.first(where: { $0.key == .sodium })?.value, .unknown(.notDeclared))
        XCTAssertEqual(entries.first(where: { $0.key == .fatTotal })?.value, .unknown(.notDeclared))
        XCTAssertEqual(entries.first(where: { $0.key == .energyConsumed })?.value, .unknown(.notDeclared))
    }

    func testConfirmedCandidateSavesNoticesAndReusesOfflineWithoutProvider() async throws {
        for volume in [false, true] {
            let request = try request()
            let source = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: OFFProductResponse(status: 200, body: try volume ? volumeResponse() : sodiumResponse(["value": 0.052, "unit": "g"]))), clock: clock)
            guard case let .candidate(input) = try await source.lookup(request) else { return XCTFail("Expected candidate") }
            var state = FoodConfirmationState(input: input)
            let candidate = state.selectedCandidate
            let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable,
                skin: .notApplicable, drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: volume ? .per100Millilitres : .per100Grams)
            FoodConfirmationReducer.reduce(state: &state, action: .applyCorrection(FoodCorrection(name: candidate.name, brand: candidate.brand,
                variant: candidate.variant, identity: identity, nutrients: candidate.candidate.nutrients, reason: try LedgerText("Synthetic explicit package review"))))
            let ids = OFFIDs(start: 100)
            let store = InMemoryFoodLedgerStore()
            let ledger = FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store, clock: clock,
                encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
            let saved = try FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids).save(state, operationID: ids.makeID(OperationTag.self))
            let projection = try CanonicalFoodProjection(records: store.archiveState().records)
            let bytes = try FoundationCanonicalJSONEncoder().encode(projection)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let restored = try decoder.decode(CanonicalFoodProjection.self, from: bytes)
            XCTAssertEqual(restored, projection)
            XCTAssertEqual(restored.records.sourceReleases, input.sourceReleases)
            XCTAssertEqual(restored.records.evidence, [request.evidence])
            let scan = try BarcodeScan(code: LedgerText("3274080005003"), symbology: .ean13, originalSymbology: LedgerText("ean-13"),
                capturedAt: clock.now(), locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic"), captureMethodVersion: LedgerText("v1"))
            let reuse = try BarcodeCaptureCoordinator(search: PersonalLibraryBarcodeSearch(reader: store), ids: ids).route(scan: scan)
            guard case let .confirmation(route) = reuse else { return XCTFail("Expected offline exact reuse") }
            XCTAssertEqual(route.reuse.productVersionID, saved.productVersion.productVersionID)
            XCTAssertEqual(route.confirmation.sourceReleases, input.sourceReleases)
            XCTAssertEqual(route.confirmation.candidates[0].candidate.nutrients, input.candidates[0].candidate.nutrients)
        }
    }
}

private struct OFFFixedClock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) } }
private actor OFFFixtureTransport: OFFProductTransport {
    let response: OFFProductResponse
    private(set) var codes: [String] = []
    init(response: OFFProductResponse) { self.response = response }
    func product(code: String) async throws -> OFFProductResponse { codes.append(code); return response }
}
private final class OFFIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value: Int
    init(start: Int = 1) { value = start }
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
