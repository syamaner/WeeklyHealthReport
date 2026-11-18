@testable import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import XCTest

/// The shared lookup contract for CoFID, USDA and TFDA and the dispatching set (estimates on
/// catalogue v2, contract section 7): a record's facts are those of the candidate `resolve` builds; a
/// corpus hash other than the pin is `corpusMismatch`, an unknown record `recordMissing`.
final class GenericRecordNutrientLookupContractTests: XCTestCase {
    private final class IDs: LedgerIDGenerating, @unchecked Sendable {
        private var value = 1
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            defer { value += 1 }
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
        }
    }

    private func recordID(_ source: any GenericFoodSearching, queries: [String]) throws -> String {
        for query in queries {
            let request = GenericFoodSearchRequest(text: try LedgerText(query), capturedAt: Date(timeIntervalSince1970: 1_794_000_000),
                                                   locale: try LedgerText("en-GB"))
            if case let .confirmation(route) = try source.search(request) { return route.matches[0].candidate.candidate.recordID.value }
        }
        throw XCTSkip("no route for \(queries)")
    }

    private typealias Adapter = any GenericRecordNutrientLookup & GenericRecordResolving & GenericFoodSearching

    @discardableResult
    private func check(_ adapter: Adapter, through lookup: (any GenericRecordNutrientLookup)? = nil,
                       source: PersonalFoodDatabaseGenericSource, pin: String, queries: [String]) throws -> GenericRecordFacts {
        let lookup = lookup ?? adapter
        let id = try recordID(adapter, queries: queries)
        let facts = try lookup.record(source: source, corpusSHA256: pin, recordID: id).get()
        // The lookup and `resolve` agree on identity, edible quantity and nutrients for the same record.
        let evidence = [try EvidenceID("00000000-0000-0000-0000-0000000000ee")]
        let resolved = try XCTUnwrap(adapter.resolve(GenericRecordReference(source: source, corpusSHA256: pin, recordID: id),
                                                     evidenceIDs: evidence, queryAlias: queries[0]))
        XCTAssertEqual(facts.identity, resolved.candidate.candidate.identity)
        XCTAssertEqual(facts.edibleQuantity, resolved.candidate.candidate.edibleQuantity)
        for key in NutrientKey.allCases {
            let value = resolved.candidate.candidate.nutrients.entries.first { $0.key == key }?.value
            if case let .augmented(exact)? = value {
                XCTAssertEqual(facts.quantified(key), exact.amount, "\(key)")
            } else {
                XCTAssertNil(facts.quantified(key), "\(key)")
            }
        }
        XCTAssertFalse(NutrientKey.allCases.allSatisfy { facts.quantified($0) == nil }, "a record with no value proves nothing")
        XCTAssertEqual(lookup.record(source: source, corpusSHA256: String(repeating: "a", count: 64), recordID: id), .failure(.corpusMismatch))
        XCTAssertEqual(lookup.record(source: source, corpusSHA256: pin, recordID: id + "-missing"), .failure(.recordMissing))
        // A mismatched pin is reported before the record is looked for.
        XCTAssertEqual(lookup.record(source: source, corpusSHA256: String(repeating: "a", count: 64), recordID: id + "-missing"),
                       .failure(.corpusMismatch))
        for other in PersonalFoodDatabaseGenericSource.allCases where other != source {
            XCTAssertEqual(adapter.record(source: other, corpusSHA256: pin, recordID: id), .failure(.corpusMismatch))
        }
        return facts
    }

    func testCoFID() throws {
        try check(CoFIDGenericFoodSearch(ids: IDs()), source: .cofid, pin: CoFIDGenericFoodSearch.corpusCanonicalSHA256,
                  queries: ["apple", "banana"])
    }

    func testUSDANeverStatesFortification() throws {
        let facts = try check(USDAGenericFoodSearch(ids: IDs()), source: .usda, pin: USDAGenericFoodSearch.corpusSHA256,
                              queries: ["apple", "banana"])
        // Contract section 3.1: the fortified-record rule cannot fire for USDA.
        XCTAssertEqual(facts.identity.fortification, .unknown)
    }

    func testTFDANeverStatesFortificationAndNeedsItsPrefix() throws {
        let tfda = try TFDAGenericFoodSearch(ids: IDs())
        let facts = try check(tfda, source: .tfda, pin: TFDAGenericFoodSearch.corpusSHA256, queries: ["tofu", "rice", "banana", "豆腐"])
        XCTAssertEqual(facts.identity.fortification, .unknown)
        let id = try recordID(tfda, queries: ["tofu", "rice", "banana", "豆腐"])
        XCTAssertTrue(id.hasPrefix("tfda:"))
        XCTAssertEqual(tfda.record(source: .tfda, corpusSHA256: TFDAGenericFoodSearch.corpusSHA256,
                                   recordID: String(id.dropFirst("tfda:".count))), .failure(.recordMissing))
    }

    func testTheSetDispatchesBySourceAndASourceWithNoLookupHasNoPin() throws {
        let cofid = try CoFIDGenericFoodSearch(ids: IDs())
        let set = GenericRecordLookupSet([.cofid: cofid])
        try check(cofid, through: set, source: .cofid, pin: CoFIDGenericFoodSearch.corpusCanonicalSHA256, queries: ["apple", "banana"])
        XCTAssertEqual(set.record(source: .usda, corpusSHA256: USDAGenericFoodSearch.corpusSHA256, recordID: "x"), .failure(.corpusMismatch))
        XCTAssertEqual(GenericRecordLookupSet([:]).record(source: .cofid, corpusSHA256: CoFIDGenericFoodSearch.corpusCanonicalSHA256,
                                                          recordID: "x"), .failure(.corpusMismatch))
    }

    func testAFortifiedCoFIDRecordSaysSo() throws {
        // What a fortified CoFID record returns is pinned: the importer's fortified rule reads it.
        let cofid = try CoFIDGenericFoodSearch(ids: IDs())
        var fortified = 0
        for query in ["cornflakes", "bran flakes", "breakfast cereal fortified", "soya drink", "margarine"] {
            let request = GenericFoodSearchRequest(text: try LedgerText(query), capturedAt: Date(timeIntervalSince1970: 1_794_000_000),
                                                   locale: try LedgerText("en-GB"))
            guard case let .confirmation(route) = try cofid.search(request) else { continue }
            for match in route.matches {
                let facts = try cofid.record(source: .cofid, corpusSHA256: CoFIDGenericFoodSearch.corpusCanonicalSHA256,
                                             recordID: match.candidate.candidate.recordID.value).get()
                XCTAssertEqual(facts.identity.fortification, match.candidate.candidate.identity.fortification)
                if facts.identity.fortification == .fortified { fortified += 1 }
            }
        }
        XCTAssertGreaterThan(fortified, 0, "no fortified CoFID record found by these queries")
    }
}
