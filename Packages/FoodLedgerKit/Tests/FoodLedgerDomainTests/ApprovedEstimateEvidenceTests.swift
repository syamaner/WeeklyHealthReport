@testable import FoodLedgerDomain
import Foundation
import XCTest

/// The `approved_estimate` provenance kind (estimates v1 section 5.1) and the two evidence payloads
/// (estimates on catalogue v2 sections 3.2 and 5). Synthetic values only.
final class ApprovedEstimateEvidenceTests: XCTestCase {
    static let digest = String(repeating: "a", count: 64)

    func provenance(key: NutrientKey = .fiber, sourceID: String = "personal-food-database", recordID: String? = "pfe:0123456789abcdef",
                    evidence: Bool = true, responseHash: Bool = true, reference: String? = nil,
                    dropReference: Bool = false) throws -> NutrientProvenance {
        NutrientProvenance(
            sourceKind: .approvedEstimate, sourceID: try ExternalIdentifier(sourceID),
            sourceReleaseID: try ExternalIdentifier("pfc:sha256:" + Self.digest),
            recordID: try recordID.map { try ExternalIdentifier($0) },
            evidenceID: evidence ? try EvidenceID("00000000-0000-0000-0000-0000000000aa") : nil,
            responseHash: responseHash ? try SHA256Digest(Self.digest) : nil,
            manifestReference: dropReference ? nil : try LedgerText(reference ?? ApprovedEstimateProvenance.manifestReference(key)))
    }

    func exact(_ provenance: NutrientProvenance, key: NutrientKey = .fiber) throws -> ExactNutrientValue {
        try ExactNutrientValue(amount: 6.5, unit: key.canonicalUnit,
            sourceValue: .exact(SourceExactNutrientValue(amount: 6.5, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
            provenance: [provenance])
    }

    func testAnApprovedEstimateIsAugmentedAndNeverMeasuredOrBounded() throws {
        let value = try exact(try provenance())
        XCTAssertNoThrow(try NutrientEntry(key: .fiber, value: .augmented(value)))
        XCTAssertThrowsError(try NutrientEntry(key: .fiber, value: .measured(value)))
        let source = SourceNutrientValue.exact(try SourceExactNutrientValue(amount: 1, unit: LedgerText("g"), basis: .per100Grams))
        for origin in [BoundOrigin.measured, .augmented] {
            let bounds = try NutrientBounds(lower: 1, upper: 2, lowerClosed: true, upperClosed: true, origin: origin,
                                            unit: .grams, sourceValue: source, provenance: [try provenance()])
            XCTAssertThrowsError(try NutrientEntry(key: .fiber, value: .bounded(bounds)))
        }
    }

    func testEachOfTheFiveRequiredFieldsAndTheirFormsAreEnforced() throws {
        func rejects(_ p: NutrientProvenance, _ message: String, line: UInt = #line) throws {
            XCTAssertThrowsError(try NutrientEntry(key: .fiber, value: .augmented(try exact(p))), message, line: line)
        }
        try rejects(try provenance(recordID: nil), "record")
        try rejects(try provenance(recordID: "cofid:example"), "record form")
        try rejects(try provenance(evidence: false), "evidence")
        try rejects(try provenance(responseHash: false), "manifest hash")
        try rejects(try provenance(dropReference: true), "manifest reference")
        try rejects(try provenance(reference: "pfd-estimate-capture-v1#protein"), "another nutrient's reference")
        try rejects(try provenance(reference: "pfd-estimate-capture-v2#fiber"), "another manifest version")
        try rejects(try provenance(sourceID: "open-food-facts"), "source")
        XCTAssertEqual(ProvenanceSourceKind.approvedEstimate.rawValue, "approved_estimate")
        XCTAssertEqual(ApprovedEstimateProvenance.manifestReference(.fiber), "pfd-estimate-capture-v1#fiber")
    }

    func entry() throws -> (PersonalFoodDatabaseEntry, PersonalFoodDatabaseFile) {
        let file = try PersonalFoodDatabaseCodec.decode(try PersonalFoodDatabaseCodecEstimatesTests.fixture("golden.json")).get()
        return (try XCTUnwrap(file.entries.first { $0.title == "Synthetic Crisps" }), file)
    }

    func encoded(_ manifest: ApprovedEstimateCaptureManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    func testTheManifestHoldsTheWholeEvidenceRecordAndRoundTripsByteStable() throws {
        let (crisps, file) = try entry()
        let manifest = try XCTUnwrap(ApprovedEstimateCaptureManifest(databaseReleaseID: "pfc:sha256:" + Self.digest, entry: crisps,
                                                                   corpora: file.genericCorpora))
        XCTAssertEqual(manifest.schema, "pfd-estimate-capture-v1")
        XCTAssertEqual(manifest.estimates.map(\.nutrient), ["fiber", "sodium"], "nutrient catalogue order")
        let bytes = try encoded(manifest)
        let text = String(decoding: bytes, as: UTF8.self)
        // Explicit nulls, the tier, and no time, evidence ID, path or title.
        XCTAssertTrue(text.contains(#""corpus_sha256":null"#))
        XCTAssertTrue(text.contains(#""quality":"low""#) && text.contains(#""quality":"medium""#))
        XCTAssertTrue(text.contains(#""page_access":"indexed_copy""#))
        XCTAssertFalse(text.contains("Synthetic Crisps") || text.contains("captured") || text.contains("Example Brand"))
        let decoded = try XCTUnwrap(ApprovedEstimateCaptureManifest.decode(bytes))
        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(try encoded(decoded), bytes)
        XCTAssertEqual(try encoded(try XCTUnwrap(ApprovedEstimateCaptureManifest(
            databaseReleaseID: "pfc:sha256:" + Self.digest, entry: crisps, corpora: file.genericCorpora))), bytes, "same entry, same bytes")
        for (estimate, original) in zip(decoded.estimates, crisps.estimatedNutrients.sorted { $0.key.rawValue < $1.key.rawValue }) {
            XCTAssertEqual(estimate.evidence.typed, original.evidence)
            XCTAssertEqual(estimate.value, original.value)
        }
        // A composition estimate carries its corpus hash; an entry with no estimate has no manifest.
        let fish = try XCTUnwrap(file.entries.first { $0.title == "Synthetic Tinned Fish" })
        let national = try XCTUnwrap(ApprovedEstimateCaptureManifest(databaseReleaseID: "pfc:sha256:" + Self.digest, entry: fish,
                                                                   corpora: file.genericCorpora))
        XCTAssertTrue(national.estimates.allSatisfy { $0.corpusSHA256 == file.genericCorpora[.cofid] })
        let oats = try XCTUnwrap(file.entries.first { $0.title == "Synthetic Example Oats" })
        XCTAssertNil(ApprovedEstimateCaptureManifest(databaseReleaseID: "pfc:sha256:" + Self.digest, entry: oats, corpora: file.genericCorpora))
    }

    func testManifestDecodingIsStrict() throws {
        let (crisps, file) = try entry()
        let bytes = try encoded(try XCTUnwrap(ApprovedEstimateCaptureManifest(
            databaseReleaseID: "pfc:sha256:" + Self.digest, entry: crisps, corpora: file.genericCorpora)))
        let text = String(decoding: bytes, as: UTF8.self)
        func decodes(_ edit: (String) -> String) -> Bool { ApprovedEstimateCaptureManifest.decode(Data(edit(text).utf8)) != nil }
        XCTAssertTrue(decodes { $0 })
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #""basis":"#, with: #""extra":1,"basis":"#) }, "extra top-level key")
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #""quality":"low","#, with: "") }, "missing tier")
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #""quality":"low""#, with: #""quality":"excellent""#) }, "unknown tier")
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: "pfd-estimate-capture-v1", with: "pfd-estimate-capture-v2") }, "another schema")
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #""unit":"g","#, with: #""unit":"mg","#) }, "not the canonical unit")
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #""corpus_sha256":null"#, with: #""corpus_sha256":"\#(Self.digest)""#) },
                       "a page estimate has no corpus")
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #""approved_as_estimate":true"#, with: #""approved_as_estimate":false"#) })
        XCTAssertNil(ApprovedEstimateCaptureManifest.decode(Data("{}".utf8)))
    }

    func testLeaveOutEvidenceHoldsSortedKeysAndNoValue() throws {
        let item = try XCTUnwrap(ApprovedEstimateLeftOutEvidence(resolutionVersionID: "00000000-0000-0000-0000-000000000001",
                                                                manifestSHA256: Self.digest, leftOut: [.sodium, .fiber]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(item), as: UTF8.self)
        XCTAssertEqual(text, #"{"left_out":["fiber","sodium"],"manifest_sha256":"\#(Self.digest)","resolution_version_id":"00000000-0000-0000-0000-000000000001","schema":"pfd-estimate-left-out-v1"}"#)
        XCTAssertEqual(ApprovedEstimateLeftOutEvidence.decode(Data(text.utf8)), item)
        XCTAssertEqual(item.keys, [.fiber, .sodium])
        XCTAssertNil(ApprovedEstimateLeftOutEvidence(resolutionVersionID: "x", manifestSHA256: Self.digest, leftOut: []), "no item for an empty set")
        func decodes(_ edit: (String) -> String) -> Bool { ApprovedEstimateLeftOutEvidence.decode(Data(edit(text).utf8)) != nil }
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #"["fiber","sodium"]"#, with: #"["sodium","fiber"]"#) }, "unsorted")
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #"["fiber","sodium"]"#, with: "[]") }, "empty")
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #""fiber""#, with: #""vitamin_z""#) }, "unknown nutrient")
        XCTAssertFalse(decodes { $0.replacingOccurrences(of: #""schema""#, with: #""value":1,"schema""#) }, "extra key")
    }
}
