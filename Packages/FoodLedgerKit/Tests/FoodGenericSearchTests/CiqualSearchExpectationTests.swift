import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// FoodSearchQuality v8 expectations for the Ciqual 2025 admission (#384 C2,
/// docs/ciqual-2025-admission-v1.md sections 4 to 6), written down from the spec before the
/// searcher, `cocoa-percent-policy-v2` and `composite-generic-ranking-v11` were implemented.
/// They are not edited to fit the code; a change here needs its own spec amendment.
final class CiqualSearchExpectationTests: XCTestCase {
    private static let ciqualRelease = "ciqual:2025-11-19:sha256:3134f8dc9feb3e17e4d297fdc42f7711eff41af3210facb5d24c35194fa0d847"
    private static func ciqual(_ code: String) -> String { "\(ciqualRelease):alim:\(code)" }
    private static let usda170273 = "usda-legacy:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef:fdc:170273"

    private struct Frozen {
        let query: String
        /// The first row of the whole list, unchanged from v10 (nil: not pinned beyond the prefix rule).
        let first: String?
        /// Ciqual rows that must be present.
        let ciqualIncludes: [String]
        /// The first Ciqual row, when the spec's tier rules settle it.
        let firstCiqual: String?
        /// Words every Ciqual row's name must contain.
        let ciqualWords: Set<String>
    }

    /// Section 5: Ciqual rows follow every CoFID, USDA and TFDA row in the same preparation and
    /// fat partition (none of these queries has either), and the rows before them are v10's.
    /// Section 4: 31074 is [70, 70], 31005 is [50, 50], 31085 is `.atLeast(40)` (tier 4, reached
    /// only by full word coverage); tier keys are computed within the Ciqual group.
    private static let frozen: [Frozen] = [
        Frozen(query: "dark chocolate 70%", first: usda170273, ciqualIncludes: [ciqual("31074"), ciqual("31005"), ciqual("31085")],
               firstCiqual: ciqual("31074"), ciqualWords: ["dark", "chocolate"]),
        Frozen(query: "dark chocolate 50%", first: nil, ciqualIncludes: [ciqual("31005"), ciqual("31074"), ciqual("31085")],
               firstCiqual: ciqual("31005"), ciqualWords: ["dark", "chocolate"]),
        // No Ciqual band holds 40 and none lies below it, so 50 (distance 10) leads 70 (distance 30).
        Frozen(query: "dark chocolate 40%", first: nil, ciqualIncludes: [ciqual("31085"), ciqual("31005"), ciqual("31074")],
               firstCiqual: ciqual("31005"), ciqualWords: ["dark", "chocolate"]),
        Frozen(query: "dark chocolate", first: nil, ciqualIncludes: [ciqual("31074"), ciqual("31005"), ciqual("31085")],
               firstCiqual: nil, ciqualWords: ["dark", "chocolate"]),
        Frozen(query: "milk chocolate", first: nil, ciqualIncludes: [ciqual("31004")], firstCiqual: nil, ciqualWords: ["milk", "chocolate"]),
        Frozen(query: "white chocolate", first: nil, ciqualIncludes: [ciqual("31010")], firstCiqual: nil, ciqualWords: ["white", "chocolate"]),
        Frozen(query: "chocolate spread", first: nil, ciqualIncludes: [ciqual("31032")], firstCiqual: nil, ciqualWords: ["chocolate", "spread"])
    ]

    private func request(_ text: String) throws -> GenericFoodSearchRequest {
        GenericFoodSearchRequest(text: try LedgerText(text), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: try LedgerText("en_GB"))
    }
    private func records(_ search: any GenericFoodSearching, _ text: String) throws -> [GenericFoodMatch] {
        guard case let .confirmation(route) = try search.search(request(text)) else { return [] }
        XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided, "Nothing is selected automatically")
        return route.matches
    }

    func testFrozenV8Expectations() throws {
        let ids = ExpectationIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids), tfda = try TFDAGenericFoodSearch(ids: ids)
        let production = CompositeGenericFoodSearch(sources: [cofid, usda], regionalSources: [tfda],
                                                    referenceSources: [try CiqualGenericFoodSearch(ids: ids)], ids: ids)
        let withoutCiqual = CompositeGenericFoodSearch(sources: [cofid, usda], regionalSources: [tfda], ids: ids)
        for expected in Self.frozen {
            let rows = try records(production, expected.query)
            let ids = rows.map(\.candidate.candidate.recordID.value)
            let isCiqual = ids.map { $0.hasPrefix(Self.ciqualRelease) }
            XCTAssertEqual(isCiqual, isCiqual.sorted { !$0 && $1 }, "\(expected.query): Ciqual rows follow every other row")
            XCTAssertEqual(ids.filter { !$0.hasPrefix(Self.ciqualRelease) },
                           try records(withoutCiqual, expected.query).map(\.candidate.candidate.recordID.value), "\(expected.query): v10 prefix")
            if let first = expected.first { XCTAssertEqual(ids.first, first, expected.query) }
            let ciqualRows = rows.filter { $0.candidate.candidate.recordID.value.hasPrefix(Self.ciqualRelease) }
            for code in expected.ciqualIncludes {
                XCTAssertTrue(ciqualRows.contains { $0.candidate.candidate.recordID.value == code }, "\(expected.query): \(code)")
            }
            if let firstCiqual = expected.firstCiqual {
                XCTAssertEqual(ciqualRows.first?.candidate.candidate.recordID.value, firstCiqual, expected.query)
            }
            for row in ciqualRows {
                XCTAssertTrue(expected.ciqualWords.isSubset(of: Set(GenericFoodRankingPolicy.terms(row.candidate.name.value))),
                              "\(expected.query): \(row.candidate.name.value)")
            }
        }
    }

    /// Section 4.1 rule 4: 31085 enters "dark chocolate 40%" by word coverage, is not a cocoa
    /// match, sorts after the banded Ciqual rows and carries the open-ended note and caution.
    func testOpenEndedRowAtFortyPercent() throws {
        let ids = ExpectationIDs()
        let search = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)],
                                                referenceSources: [try CiqualGenericFoodSearch(ids: ids)], ids: ids)
        let rows = try records(search, "dark chocolate 40%")
        let codes = rows.map(\.candidate.candidate.recordID.value)
        let cooking = try XCTUnwrap(rows.first { $0.candidate.candidate.recordID.value == Self.ciqual("31085") })
        let parsed = FoodQueryParser.parse("dark chocolate 40%")
        XCTAssertFalse(CocoaPercentPolicy.isCocoaMatch(query: parsed, candidate: cooking.candidate))
        XCTAssertEqual(CocoaPercentPolicy.note(query: parsed, candidate: cooking.candidate),
                       "Source states 40% cocoa or more, with no single band; you asked for 40%.")
        XCTAssertEqual(CocoaPercentPolicy.caution(query: parsed, candidate: cooking.candidate), "40% cocoa or more")
        XCTAssertLessThan(try XCTUnwrap(codes.firstIndex(of: Self.ciqual("31074"))), try XCTUnwrap(codes.firstIndex(of: Self.ciqual("31085"))))
    }

    /// Section 6: the label estimate pool gains 31074 at 70% and 31005 at 50%, listed after the
    /// existing rows; 31085 is never offered, so 40% is unchanged.
    func testLabelEstimatePoolGainsCiqualRowsInSearchOrder() throws {
        let ids = ExpectationIDs()
        let search = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)],
                                                regionalSources: [try TFDAGenericFoodSearch(ids: ids)],
                                                referenceSources: [try CiqualGenericFoodSearch(ids: ids)], ids: ids)
        let pool = LabelEstimateCandidatePool(searcher: search, ids: ids)
        func names(_ p: Double) throws -> [String] {
            try pool.options(cocoaPercent: p, capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: try LedgerText("en_GB"))
                .map(\.generic.name.value)
        }
        let band = "Chocolate, dark, 70-85% cacao solids"
        XCTAssertEqual(try names(70), [band, "Dark chocolate, 70% cocoa, bar"])
        XCTAssertEqual(try names(50), ["Chocolate, plain", "Chocolate, dark, 45- 59% cacao solids", "Dark chocolate, 50% cocoa, bar"])
        XCTAssertEqual(try names(40), ["Chocolate, plain"])
        XCTAssertEqual(try names(90), [band])
        XCTAssertEqual(try names(100), ["Baking chocolate, unsweetened, squares"])
    }
}

private final class ExpectationIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
