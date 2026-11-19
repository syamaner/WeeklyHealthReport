import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Gap estimates amendment G2 (docs/personal-food-catalogue-gap-estimates-v1-amendment.md): a per 100
/// ml entry's approved estimate is carried on the entry's basis, unscaled, and an entry the owner filed
/// per 100 ml with no label says "per 100 mL", not "as labelled". Synthetic fixtures only.
final class GapEstimatesAmendmentContractTests: XCTestCase {
    typealias Confirm = ApprovedEstimateConfirmContractTests
    static let drink = "Synthetic Panel Drink"

    static func accept(_ name: String) throws -> Data {
        try Data(contentsOf: Confirm.fixtures.appendingPathComponent(name))
    }

    static func built(_ data: Data, title: String = drink) throws -> PersonalFoodDatabaseCandidateBuilder.Built {
        let file = try PersonalFoodDatabaseCodec.decode(data).get(), release = try Confirm.release(file)
        let ids = RandomLedgerIDGenerator()
        let entry = try XCTUnwrap(file.entries.first { $0.title == title })
        let capture = try ApprovedEstimateManifestBuilder(ids: ids, digester: LedgerFixtures.digester)
            .capture(entry: entry, file: file, databaseRelease: release, capturedAt: LedgerFixtures.clock.now(),
                     locale: LedgerText("en_GB"))
        return try XCTUnwrap(PersonalFoodDatabaseCandidateBuilder.build(entry: entry, file: file, databaseRelease: release,
            record: nil, evidenceIDs: [ids.makeID(EvidenceTag.self)], score: 1, estimates: capture?.binding))
    }

    static func value(_ built: PersonalFoodDatabaseCandidateBuilder.Built, _ key: NutrientKey) -> ExactNutrientValue? {
        guard case let .augmented(value)? = built.candidate.candidate.nutrients.entries.first(where: { $0.key == key })?.value
        else { return nil }
        return value
    }

    func testAPer100MillilitreRecordEstimateIsCarriedUnscaledOnTheEntryBasis() throws {
        let built = try Self.built(try Self.accept("accept-per-100-ml-record-on-per-100-ml-entry.json"))
        let sugar = try XCTUnwrap(Self.value(built, .sugar))
        XCTAssertEqual(sugar.amount, 2.0)
        guard case let .exact(source) = sugar.sourceValue else { return XCTFail("exact source value expected") }
        XCTAssertEqual(source.basis, .per100Millilitres)
        XCTAssertEqual(built.candidate.candidate.identity.servingBasis, .per100Millilitres)
    }

    func testAQuantifiedZeroFromAPer100GramRecordIsZeroPer100Millilitres() throws {
        let built = try Self.built(try Self.accept("accept-zero-from-per-100-g-record-on-per-100-ml-entry.json"))
        let fibre = try XCTUnwrap(Self.value(built, .fiber))
        XCTAssertEqual(fibre.amount, 0)
        guard case let .exact(source) = fibre.sourceValue else { return XCTFail("exact source value expected") }
        XCTAssertEqual(source.basis, .per100Millilitres)
    }

    func testTheSourceLineSaysAsLabelledOnlyWhenTheEntryHasALabel() throws {
        let labelled = try Self.built(try Self.accept("accept-per-100-ml-record-on-per-100-ml-entry.json"))
        XCTAssertEqual(labelled.candidate.candidate.matchMetadata?.materialDifferences.first?.value,
                       "Your food database entry · per 100 mL as labelled")

        // The owner's basis decision (G2c): the same entry with no label value.
        var doc = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try Self.accept("accept-per-100-ml-record-on-per-100-ml-entry.json")) as? [String: Any])
        var items = try XCTUnwrap(doc["items"] as? [[String: Any]])
        let index = try XCTUnwrap(items.firstIndex { $0["title"] as? String == Self.drink })
        items[index]["label_nutrients"] = [String: Any]()
        doc["items"] = items
        let unlabelled = try Self.built(try JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]))
        XCTAssertEqual(unlabelled.candidate.candidate.matchMetadata?.materialDifferences.first?.value,
                       "Your food database entry · per 100 mL")
    }
}
