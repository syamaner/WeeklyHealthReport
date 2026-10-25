import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Label photo L1b contract tests (docs/label-photo-ai-prefill-v1.md 12.5 tests 3, 5 and 6, and
/// 17.8 tests 20 and 25): the strict manifest codec, the verifier's rules in 8.2 with the
/// attention recomputation, cross-route rejections, the composite admission and serving parity
/// with the pasted policy. Synthetic fixtures only.
final class LabelPhotoContractTests: XCTestCase {
    typealias F = LabelPhotoFixtures
    typealias M = LabelPhotoManifest

    // MARK: Test 5: the strict codec

    func testManifestRoundTripsByteForByteAndIsPinned() throws {
        let manifest = try F.manifest()
        let data = try LedgerFixtures.encoder.encode(manifest)
        XCTAssertEqual(M.decode(data), manifest)
        XCTAssertEqual(try LedgerFixtures.encoder.encode(try XCTUnwrap(M.decode(data))), data)
        XCTAssertTrue(LabelPhotoSource.isCanonical(data, encoder: LedgerFixtures.encoder))
        XCTAssertEqual(try F.sha(data), Self.manifestGoldenSHA256, "a change to the manifest bytes is a new version")
        let text = String(decoding: data, as: UTF8.self)
        for member in [#""version":"label-photo-ai-v1""#, #""route_version":"label-photo-ai-route-v1""#, #""generation_id":"gen-synthetic-0001""#,
                       #""cost_usd":"0.0105""#, #""reasoning_tokens":null"#, #""basis_choices":[]"#, #""attention_version":"label-photo-attention-v1""#,
                       #""consistency_version":"label-photo-serving-consistency-v1""#, #""serving_version":"label-photo-serving-v1""#,
                       #""label_format":"taiwan_nutrition_labelling""#] {
            XCTAssertTrue(text.contains(member), member)
        }
        XCTAssertFalse(text.contains("crop"), "no crop coordinates are stored")
    }

    static let manifestGoldenSHA256 = "2dbfc1376e14ef4c02b0980187bafd51698a2644f879723053392270bddd7bb1"

    func testUnknownOrMissingMembersThrowAndUnknownCostRoundTrips() throws {
        let data = try LedgerFixtures.encoder.encode(try F.manifest())
        let text = String(decoding: data, as: UTF8.self)
        for broken in [text.replacingOccurrences(of: #""name":"#, with: #""device_id":"x","name":"#),
                       text.replacingOccurrences(of: #""generation_id":"gen-synthetic-0001","#, with: ""),
                       text.replacingOccurrences(of: #","reasoning_tokens":null"#, with: ""),
                       text.replacingOccurrences(of: #""cost_usd":"0.0105""#, with: #""cost_usd":"0""# + "x"),
                       text.replacingOccurrences(of: #""basis_choices":[]"#, with: #""basis_choices":[{"at":1,"basis":"per_100g","header_id":"h2","offered":[]}]"#),
                       text.replacingOccurrences(of: #""version":"label-photo-ai-v1""#, with: #""version":"pasted-nutrition-label-v1""#)] {
            XCTAssertNotEqual(broken, text)
            XCTAssertNil(M.decode(Data(broken.utf8)))
        }
        let unknown = try F.manifest(response: F.response(cost: "unknown"))
        let unknownData = try LedgerFixtures.encoder.encode(unknown)
        XCTAssertEqual(M.decode(unknownData)?.response.usage.costUSD, "unknown")
        XCTAssertTrue(String(decoding: unknownData, as: UTF8.self).contains(#""cost_usd":"unknown""#))
        // Re-encoded with other whitespace or key order, the bytes are not canonical.
        let pretty = try JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: data), options: [.prettyPrinted])
        XCTAssertFalse(LabelPhotoSource.isCanonical(pretty, encoder: LedgerFixtures.encoder))
    }

    // MARK: Test 6: the verifier (8.2)

    func testABuiltEntryVerifiesWithAndWithoutItsPhoto() throws {
        let withPhoto = try F.input(try F.manifest(), attachment: try F.attachment())
        XCTAssertTrue(F.verify(withPhoto))
        let restored = try F.input(try F.manifest())
        XCTAssertTrue(F.verify(restored), "a restored archive keeps no photo and still verifies on the manifest")
        let source = withPhoto.candidates[0].candidate
        XCTAssertEqual(source.evidenceIDs.count, 2)
        XCTAssertEqual(withPhoto.sourceReleases[0].sourceID.value, "label-photo-ai")
        XCTAssertEqual(withPhoto.sourceReleases[0].schemaVersion.value, "label-photo-ai-v1:taiwan_nutrition_labelling")
        XCTAssertEqual(withPhoto.sourceReleases[0].artifactHash.value, try F.imageSHA())
        XCTAssertEqual(withPhoto.evidence[0].captureMethodVersion.value, "label-photo-ai-v1")
        XCTAssertEqual(withPhoto.evidence[1].captureMethodVersion.value, "label-photo-preparation-v1")
        XCTAssertEqual(withPhoto.evidence[1].attachment?.sha256.value, try F.imageSHA())
        // Values come from the shared pasted derivation, naming this source: protein corrected,
        // kcal and sodium calculated from the stored column, fibre entered.
        let values = Dictionary(uniqueKeysWithValues: source.nutrients.entries.map { ($0.key, $0.value) })
        for key: NutrientKey in [.protein, .energyConsumed, .sodium, .fiber] {
            XCTAssertEqual(values[key]?.provenance.first?.sourceID.value, "label-photo-ai", "\(key)")
        }
        XCTAssertEqual(values[.protein]?.provenance.first?.sourceKind, .manualDeclaration)
        XCTAssertEqual(values[.energyConsumed]?.provenance.first?.sourceKind, .userVerifiedPanel)
    }

    func testTheReleaseWireAndImageAreBound() throws {
        let input = try F.input(try F.manifest(), attachment: try F.attachment())
        // The wire text must hash to its recorded digest (8.2.3).
        var response = try F.response()
        response = M.Response(model: response.model, provider: response.provider, generationID: response.generationID,
                              finishReason: response.finishReason, attempts: response.attempts, usage: response.usage,
                              requestedAt: response.requestedAt, completedAt: response.completedAt, wireText: response.wireText + " ",
                              wireSHA256: response.wireSHA256)
        XCTAssertThrowsError(try F.input(try F.manifest(response: response)))
        XCTAssertFalse(F.verify(try F.rebound(input, manifest: try F.manifest(response: response))))
        // An oversize wire text is refused.
        let long = String(repeating: "x", count: M.maximumWireBytes + 1)
        XCTAssertThrowsError(try F.input(try F.manifest(response: F.response(wire: long))))
        // A model or endpoint outside the admitted route is not an admitted pipeline (8.2.2).
        let other = M.Request(model: "openai/gpt-6.1-sol", endpoint: "azure", reasoningLimit: 500, maxOutputTokens: 1_200,
                              instructionVersion: M.instructionVersion, instructionSHA256: F.hex64, wireSchemaVersion: "label-photo-wire-schema-v1",
                              wireSchemaSHA256: F.hex64, catalogueCheck: .init(at: 1, slug: "openai/gpt-6.1-sol", endpoint: "azure",
                                                                              inputModalities: ["image"], zeroDataRetention: true,
                                                                              promptPrice: "0.000002", completionPrice: "0.00001"))
        XCTAssertThrowsError(try F.input(try F.manifest(request: other)))
        // The attachment must hold exactly the prepared bytes.
        let wrong = try AttachmentDescriptor(sha256: SHA256Digest(F.hex64), mediaKind: LedgerText("image/jpeg"), byteCount: 10,
                                             relativePath: LedgerText("label-photos/other.jpg"))
        XCTAssertThrowsError(try F.input(try F.manifest(), attachment: wrong))
    }

    func testRegionsMustBeInsideAndOnlyOnFoundValues() throws {
        let candidate = try F.candidate()
        var records = F.locations(candidate).records
        let index = try XCTUnwrap(records.firstIndex { $0.status == .found })
        let base = records[index]
        for (status, region) in [(LabelPhotoAttention.Location.found, M.Region(x: "0.9", y: "0.2", w: "0.2", h: "0.1")),
                                 (.found, nil), (.notFound, F.region), (.ambiguous, F.region),
                                 (.found, M.Region(x: "0.1", y: "0.1", w: "0", h: "0.1"))] {
            records[index] = M.Location(item: base.item, status: status, region: region)
            let locations = M.Locations(locatorVersion: "label-photo-vision-locate-v3", visionRevision: 3, languages: ["zh-Hant"], records: records)
            XCTAssertThrowsError(try F.manifest(locations: locations), "\(status) \(String(describing: region))")
        }
        // A cell with no location record, or a record for nothing, is refused.
        let missing = M.Locations(locatorVersion: "label-photo-vision-locate-v3", visionRevision: 3, languages: [],
                                  records: Array(F.locations(candidate).records.dropFirst()))
        XCTAssertThrowsError(try F.manifest(locations: missing))
        let unknownLocator = M.Locations(locatorVersion: "label-photo-vision-locate-v9", visionRevision: 3, languages: [],
                                         records: F.locations(candidate).records)
        XCTAssertThrowsError(try F.input(try F.manifest(locations: unknownLocator)))
    }

    // MARK: Test 20: attention recomputation (M2)

    func testAttentionIsRecomputedAndMustMatchExactly() throws {
        let good = try F.manifest()
        let input = try F.input(good)
        XCTAssertTrue(F.verify(input))
        XCTAssertEqual(good.attention.map(\.item), ["蛋白質@h2", "servings_per_pack"])
        let removed = Array(good.attention.dropLast())
        let added = good.attention + [M.Attention(item: "脂肪@h2", reasons: [.ambiguous], resolution: .checked, at: 1_700_000_900_000)]
        let changed = [M.Attention(item: good.attention[0].item, reasons: [.ambiguous], resolution: good.attention[0].resolution,
                                   at: good.attention[0].at)] + good.attention.dropFirst()
        for attention in [removed, added, changed] {
            let tampered = try F.manifest(attention: attention)
            XCTAssertThrowsError(try F.input(tampered))
            XCTAssertFalse(F.verify(try F.rebound(input, manifest: tampered)))
        }
        // A changed attention version is not admitted: the manifest's own member is the version.
        let data = try LedgerFixtures.encoder.encode(good)
        let renamed = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "label-photo-attention-v1", with: "label-photo-attention-v2")
        let renamedManifest = try XCTUnwrap(M.decode(Data(renamed.utf8)))
        XCTAssertThrowsError(try F.input(renamedManifest))
        // A gate flag or a failed check adds its items; a resolution must agree with the corrections.
        let flagged = try F.manifest(flags: [.init(code: "required_row_missing", concerns: "fat")])
        XCTAssertTrue(flagged.attention.contains { $0.item == "脂肪@h2" && $0.reasons == [.gateFlag] })
        XCTAssertTrue(F.verify(try F.input(flagged)))
        let failed = try F.manifest(checksFailed: [.init(name: "energy", basis: "per_100g", nutrient: nil, child: nil)])
        XCTAssertTrue(failed.attention.contains { $0.item == "蛋白質@h2" && $0.reasons == [.notFound, .checkFailed] })
        XCTAssertTrue(F.verify(try F.input(failed)))
        XCTAssertThrowsError(try F.input(try F.manifest(resolutions: ["蛋白質@h2": .checked])), "a corrected value is resolved corrected")
        XCTAssertThrowsError(try F.input(try F.manifest(resolutions: ["蛋白質@h2": .corrected, "servings_per_pack": .corrected])),
                             "corrected needs its correction record")
    }

    func testLeaveUnknownStoresUnknown() throws {
        // Protein per 100 g left unknown, with no correction: the stored protein is unknown.
        let manifest = try F.manifest(corrections: [PastedLabelFixtures.corrections[1]], resolutions: ["蛋白質@h2": .leftUnknown])
        let input = try F.input(manifest)
        XCTAssertTrue(F.verify(input))
        let protein = input.candidates[0].candidate.nutrients.entries.first { $0.key == .protein }
        guard case .unknown = protein?.value else { return XCTFail("left unknown must store unknown") }
    }

    // MARK: Test 6: cross-route rejections (8.2.8) and admission (P19)

    func testEachVerifierRejectsTheOtherRoutesEvidence() throws {
        let photo = try F.input(try F.manifest())
        let pasted = try PastedLabelFixtures.input(try PastedLabelFixtures.manifest())
        XCTAssertFalse(PastedLabelSource.verify(photo, candidate: photo.candidates[0], encoder: LedgerFixtures.encoder,
                                                digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()))
        XCTAssertFalse(F.verify(pasted))
        // A photo manifest relabelled as pasted evidence, and a pasted manifest relabelled as photo evidence.
        let photoBytes = photo.evidence[0].originalPayload
        let relabelledPhoto = try CaptureEvidence(evidenceID: pasted.evidence[0].evidenceID, kind: .labelText, capturedAt: pasted.evidence[0].capturedAt,
            locale: pasted.evidence[0].locale, captureMethod: LedgerText(PastedLabelSource.captureMethod),
            captureMethodVersion: LedgerText(PastedLabelManifest.version), originalPayload: photoBytes, byteHash: photo.evidence[0].byteHash)
        let asPasted = try PopulatedFoodConfirmation(evidence: [relabelledPhoto], sourceReleases: pasted.sourceReleases, candidates: pasted.candidates,
            expectedIdentity: pasted.candidates[0].candidate.identity, expectedEdibleQuantity: pasted.candidates[0].candidate.edibleQuantity)
        XCTAssertFalse(PastedLabelSource.verify(asPasted, candidate: asPasted.candidates[0], encoder: LedgerFixtures.encoder,
                                                digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()))
        let relabelledPasted = try CaptureEvidence(evidenceID: photo.evidence[0].evidenceID, kind: .packageImage, capturedAt: photo.evidence[0].capturedAt,
            locale: photo.evidence[0].locale, captureMethod: LedgerText(LabelPhotoSource.manifestCaptureMethod),
            captureMethodVersion: LedgerText(LabelPhotoManifest.version), originalPayload: pasted.evidence[0].originalPayload,
            byteHash: pasted.evidence[0].byteHash)
        let asPhoto = try PopulatedFoodConfirmation(evidence: [relabelledPasted, photo.evidence[1]], sourceReleases: photo.sourceReleases,
            candidates: photo.candidates, expectedIdentity: photo.candidates[0].candidate.identity,
            expectedEdibleQuantity: photo.candidates[0].candidate.edibleQuantity)
        XCTAssertFalse(F.verify(asPhoto))
    }

    func testAdmissionRoutesEachSourceAndRefusesAMixedCandidate() throws {
        let photo = try F.input(try F.manifest())
        let pasted = try PastedLabelFixtures.input(try PastedLabelFixtures.manifest())
        XCTAssertEqual(LabelSourceAdmission.route(photo, candidate: photo.candidates[0]), .photo)
        XCTAssertEqual(LabelSourceAdmission.route(pasted, candidate: pasted.candidates[0]), .pasted)
        for input in [photo, pasted] {
            XCTAssertTrue(LabelSourceAdmission.applies(input, candidate: input.candidates[0]))
            XCTAssertTrue(LabelSourceAdmission.verify(input, candidate: input.candidates[0], encoder: LedgerFixtures.encoder,
                                                      digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()))
        }
        // One value naming each source: refused.
        let source = photo.candidates[0].candidate
        let pastedValue = try XCTUnwrap(pasted.candidates[0].candidate.nutrients.entries.first { $0.key == .carbohydrates })
        let mixedEntries = source.nutrients.entries.map { $0.key == .carbohydrates ? pastedValue : $0 }
        let mixed = try ProviderNeutralCandidate(sourceReleaseID: source.sourceReleaseID, recordID: source.recordID, identity: source.identity,
            edibleQuantity: source.edibleQuantity, nutrients: try NutrientSet(entries: mixedEntries), evidenceIDs: source.evidenceIDs)
        let mixedCandidate = try PopulatedFoodCandidate(candidate: mixed, name: photo.candidates[0].name, brand: photo.candidates[0].brand,
                                                        itemClass: photo.candidates[0].itemClass)
        let mixedInput = try PopulatedFoodConfirmation(evidence: photo.evidence + pasted.evidence, sourceReleases: photo.sourceReleases + pasted.sourceReleases,
            candidates: [mixedCandidate], expectedIdentity: mixed.identity, expectedEdibleQuantity: mixed.edibleQuantity)
        XCTAssertEqual(LabelSourceAdmission.route(mixedInput, candidate: mixedCandidate), .refused)
        XCTAssertFalse(LabelSourceAdmission.verify(mixedInput, candidate: mixedCandidate, encoder: LedgerFixtures.encoder,
                                                   digester: LedgerFixtures.digester, conversions: GoldenPastedLabelConversions()))
    }

    func testAdmittedPipelinesArePinned() {
        XCTAssertEqual(LabelPhotoSource.admittedPipelines, [
            "label-photo-ai-route-v1:google/gemini-4-argon@google-vertex:label-photo-instruction-v1:label-photo-wire-mapping-v1:"
                + "label-capture-decline-gate-v2:label-arithmetic-checks-v2:label-photo-serving-consistency-v1:pasted-label-conversions-v1:"
                + "label-photo-serving-v1:label-photo-vision-locate-v3:label-photo-attention-v1"
        ])
    }

    // MARK: Test 3: serving parity with the pasted policy (P10)

    func testServingOutcomesMatchThePastedPolicy() throws {
        let lines = ["每一份量30公克", "每一份量 30 公克", "每份量30公克", "每一份量30公克，本包裝含約8份", "每一份量約30公克", "每一份量25-30公克",
                     "每一份量30公克左右", "每一份量30毫升", "Serving size 30g", "Serving size about 30g", "每一份量2片(30公克)", "每一份量30公克 / servings per container 8"]
        for line in lines {
            for basis in ["per_100g", "per_100ml"] {
                let size = PastedLabelManifest.Candidate.ServingSize(printedText: line, decimalText: line.contains("毫升") ? "30" : "30",
                    unit: line.contains("毫升") ? "毫升" : (line.contains("公克") ? "公克" : "g"), canonicalUnit: line.contains("毫升") ? "ml" : "g")
                for pack in [PastedLabelManifest.Candidate.ServingsPerPack(printedText: "本包裝含8份", decimalText: "8", approximate: false),
                             PastedLabelManifest.Candidate.ServingsPerPack(printedText: "本包裝含約8份", decimalText: "8", approximate: true)] {
                    let pasted = try PastedLabelFixtures.per100Manifest(servingSize: size, servingsPerPack: pack, basis: basis,
                                                                       parserVersion: PastedLabelSource.parserVersionV3)
                    let servingBasis: ResolutionBasis = basis == "per_100ml" ? .per100Millilitres : .per100Grams
                    try Self.assertParity(pasted, basis: servingBasis, "\(line) \(basis) \(pack.printedText)")
                }
            }
        }
        // Not vacuous: an exact printed serving gives 30 g and a whole pack of 8; "about" gives none.
        let exact = try PastedLabelFixtures.per100Manifest(servingSize: .init(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"),
            servingsPerPack: .init(printedText: "本包裝含8份", decimalText: "8", approximate: false), parserVersion: PastedLabelSource.parserVersionV3)
        let projected = LabelPhotoSource.projection(Self.photoManifest(from: exact, basis: .per100Grams))
        XCTAssertEqual(LabelPhotoServingPolicy.serving(projected, basis: .per100Grams), try PositiveQuantity(value: 30, unit: .grams))
        XCTAssertEqual(LabelPhotoServingPolicy.wholePack(projected), PastedLabelWholePack(servings: 8, origin: .printed))
        let about = try PastedLabelFixtures.per100Manifest(servingSize: .init(printedText: "每一份量約30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"),
                                                           parserVersion: PastedLabelSource.parserVersionV3)
        XCTAssertNil(LabelPhotoServingPolicy.serving(LabelPhotoSource.projection(Self.photoManifest(from: about, basis: .per100Grams)), basis: .per100Grams))
        XCTAssertEqual(LabelPhotoServingPolicy.version, "label-photo-serving-v1")
        // Per serving: case 2 (a readable serving size) and case 3 (one count).
        for readable in [true, false] {
            let pasted = try PastedLabelFixtures.perServingManifest(readableServingSize: readable, parserVersion: PastedLabelSource.parserVersionV3)
            try Self.assertParity(pasted, basis: try PastedLabelSource.storedBasis(pasted), "per serving, readable \(readable)")
        }
    }

    /// The photo policy on the same table gives the pasted policy's serving and whole pack.
    static func assertParity(_ pasted: PastedLabelManifest, basis: ResolutionBasis, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let input = try PastedLabelFixtures.input(pasted)
        let projected = LabelPhotoSource.projection(photoManifest(from: pasted, basis: basis))
        let serving = LabelPhotoServingPolicy.serving(projected, basis: basis)
        XCTAssertEqual(serving, PastedLabelServingPolicy.serving(input, candidate: input.candidates[0]), message, file: file, line: line)
        let whole = serving.flatMap { $0.unit == .count ? nil : LabelPhotoServingPolicy.wholePack(projected) }
        XCTAssertEqual(whole, PastedLabelServingPolicy.wholePack(input, candidate: input.candidates[0]), message, file: file, line: line)
    }

    /// The photo manifest carrying exactly the pasted manifest's table, lines and corrections.
    static func photoManifest(from pasted: PastedLabelManifest, basis: ResolutionBasis) -> LabelPhotoManifest {
        let c = pasted.candidate
        let candidate = PastedLabelManifest.Candidate(route: "C", inputSHA256: F.hex64, declined: false, declineReasons: [],
            wouldMarkReady: c.wouldMarkReady, language: c.language, servingSize: c.servingSize, servingsPerPack: c.servingsPerPack,
            headers: c.headers, cells: c.cells, warnings: [])
        return M(image: .init(sha256: F.hex64, byteCount: 10, pixelWidth: 10, pixelHeight: 10, jpegQuality: "0.8"), request: F.request(),
                 response: (try? F.response())!, mappingVersion: "label-photo-wire-mapping-v1", gateVersion: pasted.gateVersion,
                 arithmeticVersion: "label-arithmetic-checks-v2", conversionVersion: pasted.conversionVersion,
                 identityMapping: pasted.identityMapping, candidate: candidate, locations: F.locations(candidate), storedHeaderID: pasted.storedHeaderID,
                 conversions: pasted.conversions, flagsShown: [], checksFailed: [], warningsShown: [], corrections: pasted.corrections,
                 attention: [], name: pasted.name, brand: pasted.brand)
    }
}
