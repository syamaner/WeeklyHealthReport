import Foundation
@testable import FoodLedgerApplication
import XCTest

/// Food daily export contract v2 (#312), PR 2: readers accept schema 2 while the app still writes
/// schema 1. Contract tests 7 (shape rule, one rejection per rule), 8 (frozen v1 goldens) and 12
/// (explicit nulls); test 11 (Drive policy) is in the app target's `DailyFoodDriveExportTests`.
/// The v2 files under `docs/fixtures/food-daily-v2/` are hand-built from the frozen v1 goldens of
/// the same synthetic days; nothing here writes a fixture.
final class FoodDailyExportV2ReaderContractTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../../docs/fixtures").standardizedFileURL
    private static let v2Names = ["empty-day", "mixed-day", "plain-water-only", "typical-weight-day"]
    /// Contract 3.4, the constant sentence a v2 file carries (the writer adopts it in PR 3).
    private static let quantityEstimatesNote = "quantity.amount_method.is_estimate marks an amount that was estimated (a typical weight, the whole-milk volume rule or an estimate by eye). Every nutrient value in that entry is scaled from the estimated amount, including values whose state is measured. is_estimate false means no estimate rule was recorded for the amount, not that the amount was measured. The code recorded means the method is not described."

    private static func v1(_ file: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent("food-daily-v1/\(file)"))
    }

    private static func v2(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent("food-daily-v2/food-daily-\(name).json"))
    }

    /// A fixture as a JSON tree, changed by `edit` and decoded again. The shape rule reads the
    /// decoded document, so the tree's own number formatting does not matter here.
    private static func edited(_ data: Data, _ edit: (inout [String: Any]) throws -> Void) throws -> FoodDailyExportDocument {
        var tree = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        try edit(&tree)
        return try FoodDailyExportSerializer.decode(try JSONSerialization.data(withJSONObject: tree))
    }

    /// Replaces the `quantity` of entry `index` (or changes it in place).
    private static func editQuantity(_ tree: inout [String: Any], entry index: Int = 0,
                                     _ edit: (inout [String: Any]) -> Void) throws {
        var entries = try XCTUnwrap(tree["entries"] as? [[String: Any]])
        var quantity = try XCTUnwrap(entries[index]["quantity"] as? [String: Any])
        edit(&quantity)
        entries[index]["quantity"] = quantity
        tree["entries"] = entries
    }

    private static func method(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    /// The typical-weight v2 fixture with its one entry's `amount_method` replaced.
    private static func typicalDay(method json: String) throws -> FoodDailyExportDocument {
        let replacement = try method(json)
        return try edited(try v2("typical-weight-day")) { tree in
            try editQuantity(&tree) { $0["amount_method"] = replacement }
        }
    }

    private func assertRejected(_ document: @autoclosure () throws -> FoodDailyExportDocument,
                                _ expected: FoodDailyExportShapeError, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let document = try document()
            XCTAssertThrowsError(try FoodDailyExportShape.validate(document), file: file, line: line) {
                XCTAssertEqual($0 as? FoodDailyExportShapeError, expected, file: file, line: line)
            }
        } catch {
            XCTFail("the edited fixture did not decode: \(error)", file: file, line: line)
        }
    }

    // MARK: Test 8, frozen v1 goldens

    /// Every published v1 file is read, never written: it decodes, re-encodes byte for byte,
    /// passes the shape rule as schema 1 and carries none of the v2 fields.
    func testEveryFrozenV1GoldenStillRoundTripsAndPassesTheShapeRule() throws {
        let directory = Self.fixtures.appendingPathComponent("food-daily-v1")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertEqual(files, ["food-daily-empty-day-summary-v5.json", "food-daily-empty-day.json",
                               "food-daily-mixed-day-summary-v5.json", "food-daily-mixed-day.json",
                               "food-daily-plain-water-only-summary-v4.json", "food-daily-plain-water-only-summary-v5.json",
                               "food-daily-plain-water-only.json", "food-daily-typical-weight-day.json"],
                       "the v1 folder is frozen: no file is added or removed")
        for file in files {
            let golden = try Self.v1(file)
            let decoded = try FoodDailyExportSerializer.decode(golden)
            XCTAssertEqual(decoded.foodDailySchemaVersion, 1, file)
            XCTAssertEqual(try FoodDailyExportSerializer.encode(decoded), golden, "\(file) re-encodes byte for byte")
            XCTAssertNoThrow(try FoodDailyExportShape.validate(decoded), file)
            XCTAssertTrue(decoded.entries.allSatisfy { $0.quantity.amountMethod == nil }, file)
            XCTAssertNil(decoded.notes.quantityEstimates, file)
            let text = String(decoding: golden, as: UTF8.self)
            XCTAssertFalse(text.contains("amount_method"), file)
            XCTAssertFalse(text.contains("quantity_estimates"), file)
        }
    }

    /// PR 3: the writer emits schema 2 with the constant notes sentence; the DTO still leaves
    /// both v2 fields out when they are absent, which is what keeps a schema-1 file's bytes.
    func testTheWriterEmitsSchemaTwo() throws {
        XCTAssertEqual(FoodDailyExportDocument.schemaVersion, 2)
        XCTAssertEqual(FoodDailyExportNotes.current.quantityEstimates, Self.quantityEstimatesNote)
        XCTAssertEqual(FoodDailyExportQuantity(amount: 1, unit: "g", weightBasis: "unknown").amountMethod, nil)
        let quantity = try JSONEncoder().encode(FoodDailyExportQuantity(amount: 1, unit: "g", weightBasis: "unknown"))
        XCTAssertFalse(String(decoding: quantity, as: UTF8.self).contains("amount_method"), "absent, not null, in a v1 file")
    }

    // MARK: v2 fixtures

    func testHandBuiltV2FixturesRoundTripByteForByteAndPassTheShapeRule() throws {
        for name in Self.v2Names {
            let fixture = try Self.v2(name)
            let decoded = try FoodDailyExportSerializer.decode(fixture)
            XCTAssertEqual(decoded.foodDailySchemaVersion, 2, name)
            XCTAssertEqual(decoded.summaryVersion, "food-intake-summary-v6", name)
            XCTAssertEqual(decoded.notes.quantityEstimates, Self.quantityEstimatesNote, name)
            XCTAssertTrue(decoded.entries.allSatisfy { $0.quantity.amountMethod != nil }, name)
            XCTAssertEqual(try FoodDailyExportSerializer.encode(decoded), fixture, "\(name) re-encodes byte for byte")
            XCTAssertNoThrow(try FoodDailyExportShape.validate(decoded), name)
            let text = String(decoding: fixture, as: UTF8.self)
            XCTAssertFalse(text.contains("\n"), "one line, no pretty printing")
            XCTAssertFalse(text.contains("\\/"), "slashes are not escaped")
        }
        XCTAssertEqual(try FoodDailyExportSerializer.decode(try Self.v2("empty-day")).entries, [])
    }

    /// Each v2 fixture is its frozen v1 golden plus the v2 fields and nothing else: with
    /// `amount_method` and `quantity_estimates` removed and the schema set back to 1 it is the v1
    /// golden byte for byte. PR 3's builder therefore only has to reproduce the new fields (F3).
    func testEachV2FixtureDiffersFromItsV1GoldenOnlyInTheV2Fields() throws {
        for name in Self.v2Names {
            let v2 = try FoodDailyExportSerializer.decode(try Self.v2(name))
            let entries = v2.entries.map { entry in
                FoodDailyExportEntry(
                    logItemID: entry.logItemID, headVersionID: entry.headVersionID, occurredAt: entry.occurredAt,
                    displayName: entry.displayName, itemClass: entry.itemClass,
                    quantity: FoodDailyExportQuantity(amount: entry.quantity.amount, unit: entry.quantity.unit,
                                                      weightBasis: entry.quantity.weightBasis),
                    versions: entry.versions, basis: entry.basis, scaleFactor: entry.scaleFactor,
                    basisOrigin: entry.basisOrigin, nutrients: entry.nutrients)
            }
            let stripped = FoodDailyExportDocument(
                foodDailySchemaVersion: 1, reportDate: v2.reportDate, timeZone: v2.timeZone, dataAsOf: v2.dataAsOf,
                exportedAt: v2.exportedAt, nutrientCatalogueVersion: v2.nutrientCatalogueVersion,
                summaryVersion: v2.summaryVersion, entries: entries, summary: v2.summary, plainWater: v2.plainWater,
                notes: FoodDailyExportNotes(occurredAt: v2.notes.occurredAt, unknownValues: v2.notes.unknownValues,
                                            plainWater: v2.notes.plainWater),
                appContext: v2.appContext)
            XCTAssertEqual(try FoodDailyExportSerializer.encode(stripped), try Self.v1("food-daily-\(name).json"), name)
        }
    }

    /// Test 8 (F4): the typical-weight entry states its method while `weight_basis` keeps its v1
    /// meaning (no weight declaration, so `unknown`).
    func testTheTypicalWeightFixtureStatesItsMethodAndKeepsWeightBasisUnknown() throws {
        let document = try FoodDailyExportSerializer.decode(try Self.v2("typical-weight-day"))
        let quantity = try XCTUnwrap(document.entries.first).quantity
        XCTAssertEqual(quantity.amount, 132)
        XCTAssertEqual(quantity.unit, "g")
        XCTAssertEqual(quantity.weightBasis, "unknown")
        XCTAssertEqual(quantity.amountMethod, FoodDailyExportAmountMethod(
            code: "typical_weight", isEstimate: true,
            entered: FoodDailyExportAmountMethod.Entered(amount: 3, unit: "count"),
            source: FoodDailyExportAmountMethod.Source(
                methodVersion: "count_portion_guide_v1:usda_sr_legacy_boiled_from_171287_88378",
                sourceReleaseID: "usda-sr-legacy-portions:2018-04-01:sha256:0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef",
                size: "medium")))
        // The mixed day: an estimate by eye with no stored original input, and three direct amounts.
        let mixed = try FoodDailyExportSerializer.decode(try Self.v2("mixed-day"))
        XCTAssertEqual(mixed.entries.map { $0.quantity.amountMethod?.code }, ["estimated_by_eye", "direct", "direct", "direct"])
        XCTAssertEqual(mixed.entries.map { $0.quantity.weightBasis }, ["estimated", "unknown", "unknown", "unknown"])
        XCTAssertTrue(mixed.entries.allSatisfy { $0.quantity.amountMethod?.entered == nil && $0.quantity.amountMethod?.source == nil })
    }

    // MARK: Test 12, explicit nulls

    func testEnteredSourceAndSizeAreWrittenAsNullNeverOmitted() throws {
        let direct = FoodDailyExportAmountMethod(code: "direct", isEstimate: false, entered: nil, source: nil)
        XCTAssertEqual(String(decoding: try Self.sorted(direct), as: UTF8.self),
                       #"{"code":"direct","entered":null,"is_estimate":false,"source":null}"#)
        let milk = FoodDailyExportAmountMethod(
            code: "whole_milk_volume", isEstimate: true, entered: .init(amount: 200, unit: "mL"),
            source: .init(methodVersion: "cofid-whole-pasteurised-milk-volume-v1", sourceReleaseID: "phe-npm-2018:sha256:synthetic", size: nil))
        XCTAssertEqual(String(decoding: try Self.sorted(milk), as: UTF8.self),
                       #"{"code":"whole_milk_volume","entered":{"amount":200,"unit":"mL"},"is_estimate":true,"source":{"method_version":"cofid-whole-pasteurised-milk-volume-v1","size":null,"source_release_id":"phe-npm-2018:sha256:synthetic"}}"#)
        XCTAssertEqual(try JSONDecoder().decode(FoodDailyExportAmountMethod.self, from: try Self.sorted(milk)), milk)

        // In the fixture bytes: every amount_method object has all four keys.
        for name in Self.v2Names {
            let tree = try XCTUnwrap(try JSONSerialization.jsonObject(with: try Self.v2(name)) as? [String: Any])
            for entry in try XCTUnwrap(tree["entries"] as? [[String: Any]]) {
                let quantity = try XCTUnwrap(entry["quantity"] as? [String: Any])
                let method = try XCTUnwrap(quantity["amount_method"] as? [String: Any], name)
                XCTAssertEqual(Set(method.keys), ["code", "entered", "is_estimate", "source"], name)
                if let source = method["source"] as? [String: Any] {
                    XCTAssertEqual(Set(source.keys), ["method_version", "size", "source_release_id"], name)
                }
            }
        }
        XCTAssertTrue(String(decoding: try Self.v2("mixed-day"), as: UTF8.self)
            .contains(#""amount_method":{"code":"direct","entered":null,"is_estimate":false,"source":null}"#))
    }

    /// A missing key is not a null: a v2 object without `entered`, `source` or `source.size` does
    /// not decode at all, so it can never be read as "nothing entered" or "no size".
    func testAnAmountMethodWithAMissingKeyDoesNotDecode() throws {
        for key in ["code", "entered", "is_estimate", "source"] {
            XCTAssertThrowsError(try Self.edited(try Self.v2("typical-weight-day")) { tree in
                try Self.editQuantity(&tree) { quantity in
                    var method = quantity["amount_method"] as? [String: Any]
                    method?[key] = nil
                    quantity["amount_method"] = method
                }
            }, "amount_method without \(key)") { Self.assertKeyNotFound($0, key) }
        }
        for key in ["method_version", "size", "source_release_id"] {
            XCTAssertThrowsError(try Self.edited(try Self.v2("typical-weight-day")) { tree in
                try Self.editQuantity(&tree) { quantity in
                    var method = quantity["amount_method"] as? [String: Any]
                    var source = method?["source"] as? [String: Any]
                    source?[key] = nil
                    method?["source"] = source
                    quantity["amount_method"] = method
                }
            }, "source without \(key)") { Self.assertKeyNotFound($0, key) }
        }
        XCTAssertThrowsError(try Self.typicalDay(method: #"{"code":"direct","entered":{"unit":"g"},"is_estimate":false,"source":null}"#),
                             "entered without an amount is not zero") { Self.assertKeyNotFound($0, "amount") }
    }

    private static func assertKeyNotFound(_ error: any Error, _ key: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case let DecodingError.keyNotFound(missing, _) = error else {
            return XCTFail("expected a missing-key decode error, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(missing.stringValue, key, file: file, line: line)
    }

    private static func sorted(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    // MARK: Test 7, the shape rule

    func testThePerSchemaSummaryMap() {
        XCTAssertEqual(FoodDailyExportShape.acceptedSummaryVersions, [
            1: ["food-intake-summary-v4", "food-intake-summary-v5", "food-intake-summary-v6"],
            2: ["food-intake-summary-v6"],
            3: ["food-intake-summary-v6"],  // estimates on catalogue v2: schema 2's shape plus the estimate fields
            5: ["food-intake-summary-v6"]   // label photo estimates: schema 3's shape plus the photo token
        ])
    }

    func testSchemaOneRejectsEitherV2Field() throws {
        let method = try Self.method(#"{"code":"direct","entered":null,"is_estimate":false,"source":null}"#)
        assertRejected(try Self.edited(try Self.v1("food-daily-mixed-day.json")) { tree in
            try Self.editQuantity(&tree, entry: 2) { $0["amount_method"] = method }
        }, .unexpectedAmountMethod)
        assertRejected(try Self.edited(try Self.v1("food-daily-empty-day.json")) { tree in
            var notes = try XCTUnwrap(tree["notes"] as? [String: Any])
            notes["quantity_estimates"] = Self.quantityEstimatesNote
            tree["notes"] = notes
        }, .unexpectedQuantityEstimates)
        // A v2 file relabelled as schema 1 is a mixed file too.
        assertRejected(try Self.edited(try Self.v2("mixed-day")) { $0["food_daily_schema_version"] = 1 }, .unexpectedAmountMethod)
    }

    func testSchemaTwoRejectsAMissingV2Field() throws {
        assertRejected(try Self.edited(try Self.v2("mixed-day")) { tree in
            try Self.editQuantity(&tree, entry: 3) { $0["amount_method"] = nil }
        }, .missingAmountMethod)
        assertRejected(try Self.edited(try Self.v2("mixed-day")) { tree in
            try Self.editQuantity(&tree, entry: 0) { $0["amount_method"] = NSNull() }
        }, .missingAmountMethod)
        assertRejected(try Self.edited(try Self.v2("empty-day")) { tree in
            var notes = try XCTUnwrap(tree["notes"] as? [String: Any])
            notes["quantity_estimates"] = nil
            tree["notes"] = notes
        }, .missingQuantityEstimates)
        // A v1 file relabelled as schema 2 has neither.
        assertRejected(try Self.edited(try Self.v1("food-daily-empty-day.json")) { $0["food_daily_schema_version"] = 2 },
                       .missingQuantityEstimates)
        assertRejected(try Self.edited(try Self.v1("food-daily-typical-weight-day.json")) { $0["food_daily_schema_version"] = 2 },
                       .missingAmountMethod)
    }

    func testSummaryVersionsAreAcceptedPerSchema() throws {
        for earlier in ["food-intake-summary-v4", "food-intake-summary-v5"] {
            assertRejected(try Self.edited(try Self.v2("empty-day")) { $0["summary_version"] = earlier },
                           .summaryVersionNotAccepted(schema: 2, summaryVersion: earlier))
            XCTAssertNoThrow(try FoodDailyExportShape.validate(
                try Self.edited(try Self.v1("food-daily-empty-day.json")) { $0["summary_version"] = earlier }), earlier)
        }
        for schema in [1, 2] {
            let data = schema == 1 ? try Self.v1("food-daily-empty-day.json") : try Self.v2("empty-day")
            assertRejected(try Self.edited(data) { $0["summary_version"] = "food-intake-summary-v7" },
                           .summaryVersionNotAccepted(schema: schema, summaryVersion: "food-intake-summary-v7"))
        }
    }

    func testAnUnknownSchemaNumberIsRejected() throws {
        // Schema 3 is known but needs an approved estimate; neither fixture holds one.
        assertRejected(try Self.edited(try Self.v2("empty-day")) { $0["food_daily_schema_version"] = 3 }, .missingEstimate)
        for schema in [0, 4, -1, 20] {
            assertRejected(try Self.edited(try Self.v2("empty-day")) { $0["food_daily_schema_version"] = schema },
                           .unknownSchemaVersion(schema))
            assertRejected(try Self.edited(try Self.v1("food-daily-empty-day.json")) { $0["food_daily_schema_version"] = schema },
                           .unknownSchemaVersion(schema))
        }
    }

    /// Every row of the closed table (contract 3.2), spelt as the contract's 6.1 to 6.3 examples.
    func testEveryRowOfTheClosedTableIsAccepted() throws {
        let guideSource = #"{"method_version":"count_portion_guide_v1:synthetic","size":"SIZE","source_release_id":"usda-sr-legacy-portions:synthetic"}"#
        var rows = [
            #"{"code":"direct","entered":null,"is_estimate":false,"source":null}"#,
            #"{"code":"direct","entered":{"amount":2,"unit":"serving"},"is_estimate":false,"source":null}"#,
            #"{"code":"weighed","entered":null,"is_estimate":false,"source":null}"#,
            #"{"code":"weighed","entered":{"amount":0.17,"unit":"g"},"is_estimate":false,"source":null}"#,
            #"{"code":"estimated_by_eye","entered":null,"is_estimate":true,"source":null}"#,
            #"{"code":"estimated_by_eye","entered":{"amount":3,"unit":"count"},"is_estimate":true,"source":null}"#,
            #"{"code":"kitchen_scale","entered":{"amount":2,"unit":"count"},"is_estimate":false,"source":null}"#,
            #"{"code":"package_weight","entered":{"amount":1,"unit":"count"},"is_estimate":false,"source":null}"#,
            #"{"code":"recorded","entered":{"amount":4,"unit":"count"},"is_estimate":false,"source":null}"#,
            #"{"code":"whole_milk_volume","entered":{"amount":200,"unit":"mL"},"is_estimate":true,"source":{"method_version":"cofid-whole-pasteurised-milk-volume-v1","size":null,"source_release_id":"phe-npm-2018:synthetic"}}"#,
            #"{"code":"typical_weight","entered":{"amount":0.5,"unit":"count"},"is_estimate":true,"source":\#(guideSource.replacingOccurrences(of: "SIZE", with: "medium"))}"#
        ]
        for size in ["small", "medium", "large", "extra_large"] {
            rows.append(#"{"code":"typical_weight","entered":{"amount":3,"unit":"count"},"is_estimate":true,"source":\#(guideSource.replacingOccurrences(of: "SIZE", with: size))}"#)
        }
        for row in rows {
            let document = try Self.typicalDay(method: row)
            XCTAssertNoThrow(try FoodDailyExportShape.validate(document), row)
            // The explicit-null byte form survives a round trip for every row.
            let bytes = try FoodDailyExportSerializer.encode(document)
            XCTAssertEqual(try FoodDailyExportSerializer.encode(FoodDailyExportSerializer.decode(bytes)), bytes, row)
        }
        XCTAssertEqual(FoodDailyExportShape.codes.keys.sorted(), ["direct", "estimated_by_eye", "kitchen_scale", "package_weight",
                                                                  "recorded", "typical_weight", "weighed", "whole_milk_volume"])
    }

    func testEachClosedTableRuleRejects() throws {
        let guide = #"{"method_version":"count_portion_guide_v1:synthetic","size":"medium","source_release_id":"usda-sr-legacy-portions:synthetic"}"#
        let milk = #"{"method_version":"cofid-whole-pasteurised-milk-volume-v1","size":null,"source_release_id":"phe-npm-2018:synthetic"}"#
        // A code outside the set (including a Swift case name and different capitalisation).
        for code in ["plate", "typicalWeight", "Direct", ""] {
            assertRejected(try Self.typicalDay(method: #"{"code":"\#(code)","entered":null,"is_estimate":false,"source":null}"#),
                           .unknownCode(code))
        }
        // is_estimate differing from the table, in both directions.
        for (code, wrong) in [("direct", true), ("weighed", true), ("kitchen_scale", true), ("package_weight", true),
                              ("recorded", true), ("estimated_by_eye", false)] {
            assertRejected(try Self.typicalDay(method: #"{"code":"\#(code)","entered":null,"is_estimate":\#(wrong),"source":null}"#),
                           .estimateFlagMismatch(code: code))
        }
        assertRejected(try Self.typicalDay(method: #"{"code":"typical_weight","entered":{"amount":3,"unit":"count"},"is_estimate":false,"source":\#(guide)}"#),
                       .estimateFlagMismatch(code: "typical_weight"))
        assertRejected(try Self.typicalDay(method: #"{"code":"whole_milk_volume","entered":{"amount":200,"unit":"mL"},"is_estimate":false,"source":\#(milk)}"#),
                       .estimateFlagMismatch(code: "whole_milk_volume"))
        // source present for another code.
        for (code, estimate) in [("direct", false), ("weighed", false), ("estimated_by_eye", true), ("kitchen_scale", false),
                                 ("package_weight", false), ("recorded", false)] {
            assertRejected(try Self.typicalDay(method: #"{"code":"\#(code)","entered":null,"is_estimate":\#(estimate),"source":\#(guide)}"#),
                           .unexpectedSource(code: code))
        }
        // source missing for a source-backed estimate.
        for code in ["typical_weight", "whole_milk_volume"] {
            assertRejected(try Self.typicalDay(method: #"{"code":"\#(code)","entered":{"amount":3,"unit":"count"},"is_estimate":true,"source":null}"#),
                           .missingSource(code: code))
        }
        // size null for a typical weight; size non-null for whole milk.
        assertRejected(try Self.typicalDay(method: #"{"code":"typical_weight","entered":{"amount":3,"unit":"count"},"is_estimate":true,"source":\#(milk)}"#),
                       .missingSize)
        assertRejected(try Self.typicalDay(method: #"{"code":"whole_milk_volume","entered":{"amount":200,"unit":"mL"},"is_estimate":true,"source":\#(guide)}"#),
                       .unexpectedSize)
        // A size outside the set.
        for size in ["jumbo", "extraLarge", "Medium", ""] {
            let source = guide.replacingOccurrences(of: #""size":"medium""#, with: #""size":"\#(size)""#)
            assertRejected(try Self.typicalDay(method: #"{"code":"typical_weight","entered":{"amount":3,"unit":"count"},"is_estimate":true,"source":\#(source)}"#),
                           .unknownSize(size))
        }
        // An entered unit outside the set.
        for unit in ["ml", "kg", "servings", "piece", ""] {
            assertRejected(try Self.typicalDay(method: #"{"code":"kitchen_scale","entered":{"amount":2,"unit":"\#(unit)"},"is_estimate":false,"source":null}"#),
                           .unknownEnteredUnit(unit))
        }
    }

    /// The rule checks every entry, not the first one.
    func testTheClosedTableIsCheckedOnEveryEntry() throws {
        let bad = try Self.method(#"{"code":"direct","entered":null,"is_estimate":true,"source":null}"#)
        assertRejected(try Self.edited(try Self.v2("mixed-day")) { tree in
            try Self.editQuantity(&tree, entry: 3) { $0["amount_method"] = bad }
        }, .estimateFlagMismatch(code: "direct"))
    }
}
