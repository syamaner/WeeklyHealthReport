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
        XCTAssertEqual(input.sourceReleases[0].pipelineVersion.value, "off-product-projection-v5")
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
            XCTAssertTrue(input.sourceReleases[0].sourceReleaseID.value.contains("projection:off-product-projection-v5:schema:off-v3.6-explicit-basis-candidates-v4:"))
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
        // A serving panel beside a per 100 g panel that contradicts the 1 l pack still declines:
        // v6 applies only when the record has no per 100 pack panel at all.
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

    /// off-product-projection-v5 (#458): with no pack quantity, or one that states neither a mass
    /// nor a volume, the single eligible label panel states its own basis. Synthetic products.
    func testPanelStatesItsBasisWhenThePackQuantityIsMissingOrUnrecognised() async throws {
        let massPanel: [String: Any] = ["source": "packaging", "per": "100g", "per_quantity": 100, "per_unit": "g",
            "preparation": "as_sold", "nutrients": ["energy-kcal": ["value": 579, "unit": "kcal"], "fat": ["value": 46.8, "unit": "g"]]]
        let volumePanel: [String: Any] = ["source": "packaging", "per": "100ml", "preparation": "as_sold",
            "nutrients": ["proteins": ["value": 3, "unit": "g"]]]
        let packs: [String?] = [nil, "", "3 oz", "1 bar", "250 ounces"]
        for (panel, basis) in [(massPanel, ResolutionBasis.per100Grams), (volumePanel, .per100Millilitres)] {
            for pack in packs {
                let body = try response { product in
                    if let pack { product["quantity"] = pack } else { product.removeValue(forKey: "quantity") }
                    product.removeValue(forKey: "nutrition_data_per"); product["nutriments"] = [:]
                    product["nutrition"] = ["input_sets": [panel]]
                }
                let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: body)), clock: clock)
                guard case let .candidate(input) = try await lookup.lookup(request()) else { return XCTFail("\(pack ?? "nil") \(basis)") }
                let candidate = input.candidates[0]
                XCTAssertEqual(candidate.candidate.identity.servingBasis, basis)
                let unit: QuantityUnit = basis == .per100Grams ? .grams : .millilitres
                XCTAssertEqual(candidate.candidate.edibleQuantity, try .known(PositiveQuantity(value: 100, unit: unit), conversionVersionID: nil))
                let variant = try XCTUnwrap(candidate.variant?.value)
                XCTAssertTrue(variant.hasSuffix(basis == .per100Grams ? "per 100 g" : "per 100 ml"), variant)
                XCTAssertFalse(variant.contains("·  ·"), variant)
                if let pack, !pack.isEmpty { XCTAssertTrue(variant.contains("· \(pack) · per 100"), variant) }
                XCTAssertEqual(input.sourceReleases[0].pipelineVersion.value, "off-product-projection-v5")
            }
        }
    }

    /// v5 keeps every other refusal: two eligible panels with no pack basis to choose between them,
    /// an ineligible panel, a pack that contradicts the only panel, a pack stating both, and legacy
    /// values without a mass pack. Synthetic products.
    func testPanelBasisStillRefusesAmbiguousContradictingAndLegacyRecords() async throws {
        let mass: [String: Any] = ["source": "packaging", "per": "100g", "preparation": "as_sold",
            "nutrients": ["proteins": ["value": 8, "unit": "g"]]]
        var volume = mass; volume["per"] = "100ml"
        var serving = mass; serving["per"] = "serving"
        var prepared = mass; prepared["preparation"] = "prepared"
        var estimate = mass; estimate["source"] = "estimate"
        var wrongUnit = mass; wrongUnit["per_unit"] = "ml"
        let cases: [(String?, [[String: Any]])] = [
            (nil, [mass, volume]), ("1 bar", [mass, volume]), (nil, [mass, mass]), (nil, [serving]), (nil, [prepared]),
            (nil, [estimate]), (nil, [wrongUnit]), (nil, []), ("500 ml", [mass]), ("100 g", [volume]), ("250ml / 250g", [mass])
        ]
        for (pack, sets) in cases {
            let body = try response { product in
                if let pack { product["quantity"] = pack } else { product.removeValue(forKey: "quantity") }
                product["nutrition"] = ["input_sets": sets]
            }
            let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: body)), clock: clock)
            let outcome = try await lookup.lookup(request())
            XCTAssertEqual(outcome, .insufficientData, "\(pack ?? "nil") \(sets.count)")
        }
        for pack in [nil, "3 oz"] as [String?] {
            let body = try response { product in if let pack { product["quantity"] = pack } else { product.removeValue(forKey: "quantity") } }
            let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: body)), clock: clock)
            let outcome = try await lookup.lookup(request())
            XCTAssertEqual(outcome, .insufficientData, "legacy \(pack ?? "nil")")
        }
    }

    /// v6 (off-barcode-candidate-plan-v1, 12 November 2026): a per-serving panel with a stated
    /// size scales to per 100 in proportion; the source keeps its own number and basis. The first
    /// case has the shape of the owner's declined scan (a 100 g serving). Synthetic products.
    func testPerServingPanelScalesToPer100AndKeepsTheSourceServing() async throws {
        func panel(_ quantity: Any?, _ unit: String?) -> [String: Any] {
            var panel: [String: Any] = ["source": "packaging", "per": "serving", "preparation": "as_sold",
                "nutrients": ["energy-kcal": ["value": 43, "unit": "kcal"], "proteins": ["value": 2.7, "unit": "g"],
                              "sugars": ["value": 0.5, "unit": "g", "modifier": "<"], "sodium": ["value": 0.012, "unit": "g"]]]
            if let quantity { panel["per_quantity"] = quantity }
            if let unit { panel["per_unit"] = unit }
            return panel
        }
        for (quantity, unit, pack) in [(100.0, "g", nil), (28.0, "g", "640 g"), (250.0, "ml", nil)] as [(Double, String, String?)] {
            let body = try response { product in
                if let pack { product["quantity"] = pack } else { product.removeValue(forKey: "quantity") }
                product.removeValue(forKey: "nutrition_data_per"); product["nutriments"] = [:]
                product["nutrition"] = ["input_sets": [panel(quantity, unit),
                    ["source": "estimate", "per": "100g", "preparation": "as_sold", "nutrients": ["fiber": ["value": 9, "unit": "g"]]]]]
            }
            let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: body)), clock: clock)
            guard case let .candidate(input) = try await lookup.lookup(request()) else { return XCTFail("\(quantity) \(unit)") }
            let candidate = input.candidates[0]
            let volume = unit == "ml"
            XCTAssertEqual(candidate.candidate.identity.servingBasis, volume ? .per100Millilitres : .per100Grams)
            XCTAssertEqual(input.sourceReleases[0].pipelineVersion.value, "off-product-projection-v6")
            let factor = 100 / quantity
            let entries = Dictionary(uniqueKeysWithValues: candidate.candidate.nutrients.entries.map { ($0.key, $0.value) })
            guard case let .augmented(energy) = entries[.energyConsumed], case let .augmented(sodium) = entries[.sodium],
                  case let .bounded(sugar) = entries[.sugar] else { return XCTFail("values \(quantity)") }
            XCTAssertEqual(energy.amount, 43 * factor, accuracy: 1e-9)
            XCTAssertEqual(sodium.amount, 12 * factor, accuracy: 1e-9, "g to mg, then scaled")
            XCTAssertEqual(try XCTUnwrap(sugar.upper), 0.5 * factor, accuracy: 1e-9, "a bound scales too")
            let serving = ResolutionBasis.perServing(try PositiveQuantity(value: quantity, unit: volume ? .millilitres : .grams))
            XCTAssertEqual(energy.sourceValue, .exact(try SourceExactNutrientValue(amount: 43, unit: LedgerText("kcal"), basis: serving)))
            XCTAssertTrue(energy.provenance[0].transforms.contains { $0.transformID.value == "off-serving-to-100" && $0.transformVersion.value == "v1" })
            XCTAssertEqual(entries[.fiber], .unknown(.notDeclared), "the estimate panel never backfills")
            XCTAssertFalse(NutrientDerivation.isCalculated(.augmented(energy)), "scaling is not a calculated label value")
            let variant = try XCTUnwrap(candidate.variant?.value)
            XCTAssertTrue(variant.contains("scaled from a \(Int(quantity)) \(unit) serving"), variant)
        }
    }

    /// v6 declines: no stated size, a zero, boolean or non-numeric size, an unsupported unit, two
    /// serving panels, a pack that contradicts the unit; and a per 100 panel always wins (v5 bytes).
    func testPerServingPanelDeclinesWithoutAUsableSizeAndNeverOverridesPer100() async throws {
        let base: [String: Any] = ["source": "packaging", "per": "serving", "preparation": "as_sold",
            "nutrients": ["proteins": ["value": 8, "unit": "g"]]]
        func with(_ quantity: Any?, _ unit: Any?) -> [String: Any] {
            var panel = base
            if let quantity { panel["per_quantity"] = quantity }
            if let unit { panel["per_unit"] = unit }
            return panel
        }
        let cases: [(String?, [[String: Any]])] = [
            (nil, [with(nil, "g")]), (nil, [with(30, nil)]), (nil, [with(0, "g")]), (nil, [with(true, "g")]),
            (nil, [with("30", "g")]), (nil, [with(30, "oz")]), (nil, [with(30, "g"), with(40, "g")]),
            ("500 ml", [with(30, "g")]), ("500 g", [with(250, "ml")]),
            // Implausible once scaled: 8 g protein in a 0.1 g serving is 8,000 g per 100 g.
            (nil, [with(0.1, "g")]),
            // A bound is checked too: "< 8 g" in a 0.1 g serving is a bound of 8,000 g per 100 g.
            (nil, [{ var panel = with(0.1, "g"); panel["nutrients"] = ["proteins": ["value": 8, "unit": "g", "modifier": "<"]]; return panel }()]),
            // Scaling that overflows declines the record instead of leaving the value unknown.
            (nil, [{ var panel = with(1e-300, "g"); panel["nutrients"] = ["proteins": ["value": 1e10, "unit": "g"],
                                                                          "fat": ["value": 0, "unit": "g"]]; return panel }()])
        ]
        for (pack, sets) in cases {
            let body = try response { product in
                if let pack { product["quantity"] = pack } else { product.removeValue(forKey: "quantity") }
                product["nutrition"] = ["input_sets": sets]
            }
            let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: body)), clock: clock)
            let outcome = try await lookup.lookup(request())
            XCTAssertEqual(outcome, .insufficientData, "\(pack ?? "nil") \(sets)")
        }
        let per100: [String: Any] = ["source": "packaging", "per": "100g", "preparation": "as_sold",
            "nutrients": ["proteins": ["value": 8, "unit": "g"]]]
        let body = try response { product in product["nutrition"] = ["input_sets": [with(30, "g"), per100]] }
        let lookup = OpenFoodFactsLookup(transport: OFFFixtureTransport(response: .init(status: 200, body: body)), clock: clock)
        guard case let .candidate(input) = try await lookup.lookup(request()) else { return XCTFail("per 100 panel") }
        XCTAssertEqual(input.sourceReleases[0].pipelineVersion.value, "off-product-projection-v5", "v5 records are unchanged")
        XCTAssertFalse(try XCTUnwrap(input.candidates[0].variant?.value).contains("scaled"))
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
            let saved = try FoodConfirmationService(ledger: ledger, reader: store, clock: clock, ids: ids, digester: SHA256Digester()).save(state, operationID: ids.makeID(OperationTag.self))
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
