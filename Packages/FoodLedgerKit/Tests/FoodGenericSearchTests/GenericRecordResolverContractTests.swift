@testable import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import XCTest

/// The shared resolver contract for CoFID, USDA and TFDA (import v1 section 9; phase 1 plan section
/// 5.1 item 8): a reference resolves to exactly the record its own search route returns, under the
/// adapter's own release; a pin mismatch, a missing record or another source is unresolved.
final class GenericRecordResolverContractTests: XCTestCase {
    private final class IDs: LedgerIDGenerating, @unchecked Sendable {
        private var value = 1
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            defer { value += 1 }
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
        }
    }

    private func firstRoute(_ source: any GenericFoodSearching, queries: [String]) throws -> GenericFoodConfirmationRoute {
        for query in queries {
            let request = GenericFoodSearchRequest(text: try LedgerText(query), capturedAt: Date(timeIntervalSince1970: 1_794_000_000),
                                                   locale: try LedgerText("en-GB"))
            if case let .confirmation(route) = try source.search(request) { return route }
        }
        throw XCTSkip("no route for \(queries)")
    }

    private func check(_ resolver: any GenericRecordResolving & GenericFoodSearching, source: PersonalFoodDatabaseGenericSource,
                       pin: String, queries: [String]) throws {
        let route = try firstRoute(resolver, queries: queries)
        let searched = route.matches[0].candidate
        let reference = GenericRecordReference(source: source, corpusSHA256: pin, recordID: searched.candidate.recordID.value)
        let evidence = [try EvidenceID("00000000-0000-0000-0000-0000000000ee")]
        let resolved = try XCTUnwrap(resolver.resolve(reference, evidenceIDs: evidence, queryAlias: queries[0]))
        XCTAssertTrue(resolver.contains(reference))
        let a = resolved.candidate, b = searched
        XCTAssertEqual(a.name, b.name); XCTAssertEqual(a.brand, b.brand); XCTAssertEqual(a.variant, b.variant)
        XCTAssertEqual(a.itemClass, b.itemClass); XCTAssertEqual(a.packFacts, b.packFacts)
        XCTAssertEqual(a.candidate.sourceReleaseID, b.candidate.sourceReleaseID)
        XCTAssertEqual(a.candidate.recordID, b.candidate.recordID)
        XCTAssertEqual(a.candidate.identity, b.candidate.identity)
        XCTAssertEqual(a.candidate.edibleQuantity, b.candidate.edibleQuantity)
        XCTAssertEqual(a.candidate.nutrients, b.candidate.nutrients)
        XCTAssertEqual(a.candidate.evidenceIDs, evidence)
        XCTAssertEqual(a.candidate.matchMetadata?.methodVersion.value, "pfc-resolution-v1")
        XCTAssertTrue(route.confirmation.sourceReleases.contains(resolved.release), "the adapter's own release")
        let mismatch = GenericRecordReference(source: source, corpusSHA256: String(repeating: "a", count: 64), recordID: reference.recordID)
        XCTAssertNil(resolver.resolve(mismatch, evidenceIDs: evidence, queryAlias: queries[0]))
        XCTAssertFalse(resolver.contains(mismatch))
        let missing = GenericRecordReference(source: source, corpusSHA256: pin, recordID: reference.recordID + "-missing")
        XCTAssertNil(resolver.resolve(missing, evidenceIDs: evidence, queryAlias: queries[0]))
        for other in PersonalFoodDatabaseGenericSource.allCases where other != source {
            XCTAssertFalse(resolver.contains(GenericRecordReference(source: other, corpusSHA256: pin, recordID: reference.recordID)))
        }
    }

    func testCoFID() throws {
        try check(CoFIDGenericFoodSearch(ids: IDs()), source: .cofid, pin: CoFIDGenericFoodSearch.corpusCanonicalSHA256,
                  queries: ["apple", "banana"])
    }

    func testUSDA() throws {
        try check(USDAGenericFoodSearch(ids: IDs()), source: .usda, pin: USDAGenericFoodSearch.corpusSHA256,
                  queries: ["apple", "banana"])
    }

    func testTFDA() throws {
        let tfda = try TFDAGenericFoodSearch(ids: IDs())
        try check(tfda, source: .tfda, pin: TFDAGenericFoodSearch.corpusSHA256, queries: ["tofu", "rice", "banana", "豆腐"])
        XCTAssertFalse(tfda.contains(GenericRecordReference(source: .tfda, corpusSHA256: TFDAGenericFoodSearch.corpusSHA256,
                                                            recordID: "D15002")), "TFDA IDs need the tfda: prefix")
    }

    func testResolverSetDispatchesBySource() throws {
        let set = GenericRecordResolverSet([.cofid: try CoFIDGenericFoodSearch(ids: IDs())])
        XCTAssertFalse(set.contains(GenericRecordReference(source: .usda, corpusSHA256: USDAGenericFoodSearch.corpusSHA256, recordID: "x")))
    }
}
