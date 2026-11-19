import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Own merge amendment G4 (docs/personal-food-catalogue-own-merge-amendment-v1.md) in the candidate
/// builder: an estimate from the entry's own merge record fills its key only while the record does not
/// merge, and a merged value always wins over an estimate from the same record (defence in depth, since
/// the stored file is re-read with the codec only). Synthetic fixtures only.
final class OwnMergeAmendmentContractTests: XCTestCase {
    typealias Confirm = ApprovedEstimateConfirmContractTests
    static let greens = "Synthetic Raw Greens"

    static let recordRelease = SourceRelease(
        sourceReleaseID: try! ExternalIdentifier("cofid:synthetic"), sourceID: try! ExternalIdentifier("cofid"),
        releasedAt: Date(timeIntervalSince1970: 0), artifactHash: try! SHA256Digest(String(repeating: "d", count: 64)),
        schemaVersion: try! LedgerText("synthetic"), pipelineVersion: try! LedgerText("synthetic"),
        licence: try! LedgerText("synthetic"), attribution: try! LedgerText("synthetic"),
        manifestHash: try! SHA256Digest(String(repeating: "d", count: 64)))

    /// The entry's own record as the app resolves it: per 100 g edible, unfortified, `protein` only.
    static func record(_ recordID: String, preparation: PreparationKind, protein: Double?) throws -> ResolvedGenericRecord {
        let id = try ExternalIdentifier(recordID)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard key == .protein, let protein else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: protein, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: protein, unit: LedgerText(key.canonicalUnit.rawValue),
                                                             basis: .per100Grams)),
                provenance: [NutrientProvenance(sourceKind: .genericCompositionDataset, sourceID: recordRelease.sourceID,
                                                sourceReleaseID: recordRelease.sourceReleaseID, recordID: id)])))
        })
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
            sourceReleaseID: recordRelease.sourceReleaseID, recordID: id,
            identity: DecisiveIdentity(preparation: PreparationState(kind: preparation), bone: .unknown, skin: .unknown,
                drained: .unknown, packingMedium: .unknown, fortification: .unfortified, servingBasis: .per100Grams),
            edibleQuantity: .known(PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil),
            nutrients: nutrients, evidenceIDs: [],
            matchMetadata: CandidateMatchMetadata(methodVersion: LedgerText(PersonalFoodDatabaseCandidateBuilder.methodVersion),
                                                  score: 1, materialDifferences: [])),
            name: LedgerText("Synthetic generic " + recordID), itemClass: .food)
        return ResolvedGenericRecord(candidate: candidate, release: recordRelease)
    }

    static func built(record: ResolvedGenericRecord) throws -> PersonalFoodDatabaseCandidateBuilder.Built {
        let data = try Data(contentsOf: Confirm.fixtures.appendingPathComponent("accept-own-merge-unstated-preparation-raw.json"))
        let file = try PersonalFoodDatabaseCodec.decode(data).get(), release = try Confirm.release(file)
        let ids = RandomLedgerIDGenerator()
        let entry = try XCTUnwrap(file.entries.first { $0.title == greens })
        XCTAssertEqual(entry.genericReference?.role, .merge)
        let capture = try ApprovedEstimateManifestBuilder(ids: ids, digester: LedgerFixtures.digester)
            .capture(entry: entry, file: file, databaseRelease: release, capturedAt: LedgerFixtures.clock.now(),
                     locale: LedgerText("en_GB"))
        return try XCTUnwrap(PersonalFoodDatabaseCandidateBuilder.build(entry: entry, file: file, databaseRelease: release,
            record: record, evidenceIDs: [ids.makeID(EvidenceTag.self)], score: 1, estimates: capture?.binding))
    }

    static func proteinEntry(_ built: PersonalFoodDatabaseCandidateBuilder.Built) -> NutrientEntry? {
        built.candidate.candidate.nutrients.entries.first { $0.key == .protein }
    }

    static func protein(_ built: PersonalFoodDatabaseCandidateBuilder.Built) -> Double? {
        guard case let .augmented(value)? = built.candidate.candidate.nutrients.entries.first(where: { $0.key == .protein })?.value
        else { return nil }
        return value.amount
    }

    func testAnOwnMergeEstimateFillsItsKeyWhileTheRecordDoesNotMerge() throws {
        let built = try Self.built(record: try Self.record("cofid:unstated-greens", preparation: .unknown, protein: 3.0))
        XCTAssertFalse(built.merged)
        XCTAssertEqual(Self.protein(built), 3.0)
    }

    func testAMergedValueWinsOverAnEstimateFromTheSameRecord() throws {
        // The same stored file, read by a build whose adapter now states the record's preparation.
        let built = try Self.built(record: try Self.record("cofid:unstated-greens", preparation: .raw, protein: 7.0))
        XCTAssertTrue(built.merged)
        XCTAssertEqual(Self.protein(built), 7.0)
    }

    func testAnEstimateFromAMergedRecordThatLacksTheKeyLeavesItUnknownNotZero() throws {
        let built = try Self.built(record: try Self.record("cofid:unstated-greens", preparation: .raw, protein: nil))
        XCTAssertTrue(built.merged)
        XCTAssertNil(Self.protein(built))
        guard case .unknown? = Self.proteinEntry(built)?.value else { return XCTFail("protein stays unknown") }
    }
}
