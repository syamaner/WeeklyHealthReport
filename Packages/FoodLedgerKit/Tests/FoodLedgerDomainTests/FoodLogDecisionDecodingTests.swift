import FoodLedgerDomain
import Foundation
import XCTest

/// Contract test 6 (food_confirmation_v5): strict decoding of the typed decision record.
final class FoodLogDecisionDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> FoodLogDecisionRecord {
        try JSONDecoder().decode(FoodLogDecisionRecord.self, from: Data(json.utf8))
    }

    private func record(_ decisions: String, version: String = "food_confirmation_v5") -> String {
        #"{"decisions":[\#(decisions)],"policyVersion":"\#(version)"}"#
    }

    func testValidRecordRoundTripsAndDerivesEstimate() throws {
        let json = record(#"{"choice":"differs:skin_on","facet":"skin","sourceState":"skinless"},{"choice":"use_source_basis","facet":"serving_basis","sourceState":"per_100_g"}"#)
        let decoded = try decode(json)
        XCTAssertTrue(decoded.isEstimate)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try encoder.encode(decoded), as: UTF8.self), json)
        XCTAssertEqual(decoded.claimList, "skin: source skinless, choice differs:skin_on; serving_basis: source per_100_g, choice use_source_basis")
        let matching = try decode(record(#"{"choice":"matches_source","facet":"skin","sourceState":"skinless"}"#))
        XCTAssertFalse(matching.isEstimate)
    }

    func testRejectsEveryInvalidShape() {
        let invalid: [(String, String)] = [
            ("empty list", record("")),
            ("duplicate facets", record(#"{"choice":"not_sure","facet":"skin","sourceState":"skinless"},{"choice":"not_sure","facet":"skin","sourceState":"skinless"}"#)),
            ("out of order", record(#"{"choice":"not_sure","facet":"skin","sourceState":"skinless"},{"choice":"not_sure","facet":"bone","sourceState":"boneless"}"#)),
            ("matches unknown source", record(#"{"choice":"matches_source","facet":"skin","sourceState":"unknown"}"#)),
            ("differs equals source", record(#"{"choice":"differs:skinless","facet":"skin","sourceState":"skinless"}"#)),
            ("differs unknown", record(#"{"choice":"differs:unknown","facet":"skin","sourceState":"skinless"}"#)),
            ("differs not applicable", record(#"{"choice":"differs:not_applicable","facet":"skin","sourceState":"skinless"}"#)),
            ("differs named", record(#"{"choice":"differs:named","facet":"preparation","sourceState":"raw"}"#)),
            ("differs other facet value", record(#"{"choice":"differs:boneless","facet":"skin","sourceState":"skinless"}"#)),
            ("not sure on basis", record(#"{"choice":"not_sure","facet":"serving_basis","sourceState":"per_100_g"}"#)),
            ("differs on edible quantity", record(#"{"choice":"differs:known","facet":"edible_quantity","sourceState":"known"}"#)),
            ("acknowledgement on skin", record(#"{"choice":"use_source_basis","facet":"skin","sourceState":"skinless"}"#)),
            ("medium choice on skin", record(#"{"choice":"different_medium_or_none","facet":"skin","sourceState":"skinless"}"#)),
            ("unknown token", record(#"{"choice":"maybe","facet":"skin","sourceState":"skinless"}"#)),
            ("unknown source token", record(#"{"choice":"not_sure","facet":"skin","sourceState":"crispy"}"#)),
            ("unknown facet", record(#"{"choice":"not_sure","facet":"sauce","sourceState":"unknown"}"#)),
            ("wrong policy", record(#"{"choice":"not_sure","facet":"skin","sourceState":"skinless"}"#, version: "food_confirmation_v4")),
            ("stored estimate flag", #"{"decisions":[{"choice":"not_sure","facet":"skin","sourceState":"skinless","isEstimate":false}],"policyVersion":"food_confirmation_v5","isEstimate":false}"#)
        ]
        for (name, json) in invalid where name != "stored estimate flag" {
            XCTAssertThrowsError(try decode(json), name)
        }
        // No estimate flag is stored: an injected flag is ignored and status is derived from the choices.
        XCTAssertEqual(try decode(invalid.last!.1).isEstimate, true)
    }

    func testOfferedChoicesFollowTheClosedTable() throws {
        func state(_ facet: IdentityContradiction, _ token: String) throws -> FoodLogSourceState {
            try FoodLogSourceState(facet: facet, token: token)
        }
        XCTAssertEqual(FoodLogFacetDecision.offeredChoices(facet: .skin, sourceState: try state(.skin, "skinless")),
                       [.matchesSource, .differs("skin_on"), .notSure])
        XCTAssertEqual(FoodLogFacetDecision.offeredChoices(facet: .skin, sourceState: try state(.skin, "unknown")),
                       [.differs("skin_on"), .differs("skinless"), .notSure])
        XCTAssertEqual(FoodLogFacetDecision.offeredChoices(facet: .preparation, sourceState: try state(.preparation, "named")),
                       [.matchesSource, .differs("as_sold"), .differs("raw"), .differs("cooked"), .differs("reheated"), .notSure])
        XCTAssertEqual(FoodLogFacetDecision.offeredChoices(facet: .packingMedium, sourceState: try state(.packingMedium, "named")),
                       [.matchesSource, .differentMediumOrNone, .notSure])
        XCTAssertEqual(FoodLogFacetDecision.offeredChoices(facet: .packingMedium, sourceState: try state(.packingMedium, "unknown")),
                       [.differentMediumOrNone, .notSure])
        XCTAssertEqual(FoodLogFacetDecision.offeredChoices(facet: .servingBasis, sourceState: try state(.servingBasis, "per_100_g")), [.useSourceBasis])
        XCTAssertEqual(FoodLogFacetDecision.offeredChoices(facet: .edibleQuantity, sourceState: try state(.edibleQuantity, "unknown")), [.useSourceServing])
    }

    func testAssertionWithoutDecisionsOmitsTheKey() throws {
        let assertion = UserAssertion(
            assertionID: try LedgerID("00000000-0000-0000-0000-000000000001"), author: .user,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            reason: try LedgerText("reason"), claim: try LedgerText("claim"))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertFalse(String(decoding: try encoder.encode(assertion), as: UTF8.self).contains("confirmation"))
    }
}
