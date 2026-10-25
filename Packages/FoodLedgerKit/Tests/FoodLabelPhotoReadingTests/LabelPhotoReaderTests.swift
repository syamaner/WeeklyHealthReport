import FoodLabelPhotoReading
import FoodLedgerApplication
import Foundation
import NutritionLabelParsing
import XCTest

/// Contract test 2 (docs/label-photo-ai-prefill-v1.md 12.5): the photo reader runs the frozen
/// gate, checks v2 and conversions on the mapped candidate, Taiwan only, and passes the mapped
/// candidate on unchanged. Synthetic answers only.
final class LabelPhotoReaderTests: XCTestCase {
    func wire(headers: String, rows: String, serving: String = "每一份量30公克", pack: String = "本包裝含2份", language: String = "zh-Hant",
              declined: Bool = false) -> String {
        #"{"declined":\#(declined),"decline_reasons":\#(declined ? #"["not_a_label"]"# : "[]"),"language":"\#(language)","serving_size_text":"\#(serving)","servings_per_pack_text":"\#(pack)","headers":[\#(headers)],"rows":[\#(rows)]}"#
    }

    let twoColumns = #"{"header_id":"h1","printed_text":"每份","basis":"per_serving"},{"header_id":"h2","printed_text":"每100公克","basis":"per_100g"}"#

    func row(_ label: String, _ nutrient: String, _ perServing: String, _ per100: String, parent: String = "none") -> String {
        #"{"printed_label":"\#(label)","nutrient":"\#(nutrient)","parent_nutrient":"\#(parent)","values":[{"header_id":"h1","printed_text":"\#(perServing)"},{"header_id":"h2","printed_text":"\#(per100)"}]}"#
    }

    var taiwanRows: String {
        [row("熱量", "energy_kcal", "120大卡", "400大卡"), row("蛋白質", "protein", "3.5公克", "11.7公克"), row("脂肪", "fat", "4公克", "13.3公克"),
         row("飽和脂肪", "saturates", "1.2公克", "4公克", parent: "fat"), row("反式脂肪", "trans_fat", "0公克", "0公克", parent: "fat"),
         row("碳水化合物", "carbohydrate", "18公克", "60公克"), row("糖", "sugars", "1公克", "3.3公克", parent: "carbohydrate"),
         row("鈉", "sodium", "85毫克", "283毫克")].joined(separator: ",")
    }

    let sha = String(repeating: "a", count: 64)

    func testTheFrozenRulesRunOnTheMappedCandidate() throws {
        let text = wire(headers: twoColumns, rows: taiwanRows)
        let reading = try XCTUnwrap(LabelPhotoReader().reading(wireText: text, imageSHA256: sha))
        let candidate = LabelPhotoWireMapping.map(try XCTUnwrap(LabelPhotoWire.decode(text)), inputSHA256: sha)
        // Gate v2, called on the Taiwan format.
        let report = LabelDeclineGate.apply(candidate, format: .taiwan).report
        XCTAssertEqual(reading.gate?.hardDeclines, report.hardDeclineCodes)
        XCTAssertEqual(reading.gate?.skipped, report.skipped?.rawValue)
        XCTAssertEqual(reading.gate?.format, "taiwan_nutrition_labelling")
        // Checks v2 over the amount bases.
        let checks = LabelArithmeticChecksV2.check(LabelArithmeticTable(candidate, format: .taiwan), amountBases: ["per_serving", "per_100g"]).checks
        XCTAssertEqual(reading.checks.map(\.name), checks.map(\.name))
        XCTAssertEqual(reading.checks.map(\.status.rawValue), checks.map(\.status.rawValue))
        // Conversions for the stored column (per 100 g when printed).
        XCTAssertEqual(reading.storedHeaderID, "h2")
        XCTAssertEqual(reading.conversions.count, PastedLabelConversions.conversions(for: candidate, storedHeaderID: "h2").count)
        // The candidate is passed on as mapped, with route C and the image's hash.
        XCTAssertEqual(reading.candidate.route, "C")
        XCTAssertEqual(reading.candidate.inputSHA256, sha)
        XCTAssertEqual(reading.candidate.cells.count, candidate.cells.count)
        XCTAssertEqual(reading.imageSHA256, sha)
        XCTAssertEqual(reading.versions.mapping, "label-photo-wire-mapping-v1")
        XCTAssertEqual(reading.versions.gate, "label-capture-decline-gate-v2")
        XCTAssertEqual(reading.versions.arithmetic, "label-arithmetic-checks-v2")
        XCTAssertEqual(reading.versions.conversion, "pasted-label-conversions-v1")
        XCTAssertEqual(reading.inferredFormat, "taiwan_nutrition_labelling")
        XCTAssertTrue(reading.isUsable)
    }

    func testAKilojouleOnlyRowIsConvertedByTheFrozenRule() throws {
        let rows = [row("熱量", "energy_kj", "500kJ", "1675kJ"), row("蛋白質", "protein", "3.5公克", "11.7公克"),
                    row("脂肪", "fat", "4公克", "13.3公克"), row("碳水化合物", "carbohydrate", "18公克", "60公克"),
                    row("鈉", "sodium", "85毫克", "283毫克")].joined(separator: ",")
        let reading = try XCTUnwrap(LabelPhotoReader().reading(wireText: wire(headers: twoColumns, rows: rows), imageSHA256: sha))
        XCTAssertEqual(reading.conversions.map(\.rule), ["kj_to_kcal_v1"])
        XCTAssertEqual(reading.conversions.first?.sourceHeaderID, "h2")
    }

    func testAnAnswerThatIsNotSchemaValidShowsNothing() {
        XCTAssertNil(LabelPhotoReader().reading(wireText: "{}", imageSHA256: sha))
        XCTAssertNil(LabelPhotoReader().reading(wireText: wire(headers: twoColumns, rows: taiwanRows).replacingOccurrences(
            of: #""declined":false"#, with: #""declined":false,"confidence":1"#), imageSHA256: sha))
    }

    func testTheModelsDeclineAndAnyFormatButTaiwanAreDeclines() throws {
        let declined = try XCTUnwrap(LabelPhotoReader().reading(wireText: wire(headers: "", rows: "", declined: true), imageSHA256: sha))
        XCTAssertEqual(declined.hardDeclines, ["not_a_label"])
        XCTAssertNil(declined.gate)
        XCTAssertFalse(declined.isUsable)
        let english = #"{"header_id":"h1","printed_text":"Per serving","basis":"per_serving"},{"header_id":"h2","printed_text":"Per 100g","basis":"per_100g"}"#
        let ukRows = [row("Energy", "energy_kj", "500kJ", "1675kJ"), row("Fat", "fat", "4g", "13g"), row("of which saturates", "saturates", "1g", "4g", parent: "fat"),
                      row("Carbohydrate", "carbohydrate", "18g", "60g"), row("of which sugars", "sugars", "1g", "3g", parent: "carbohydrate"),
                      row("Protein", "protein", "3g", "11g"), row("Salt", "salt", "0.2g", "0.7g")].joined(separator: ",")
        let uk = try XCTUnwrap(LabelPhotoReader().reading(wireText: wire(headers: english, rows: ukRows, serving: "30g", pack: "unknown", language: "en"),
                                                          imageSHA256: sha))
        XCTAssertNotEqual(uk.inferredFormat, "taiwan_nutrition_labelling")
        XCTAssertEqual(uk.hardDeclines, ["layout_not_supported"])
        XCTAssertNil(uk.gate)
        XCTAssertTrue(uk.conversions.isEmpty)
    }

    func testGateFlagsAreFindingsNotDeclines() throws {
        // No sodium row: G3 (required row missing) is a flag on Confirm, never a decline here.
        let rows = [row("熱量", "energy_kcal", "120大卡", "400大卡"), row("蛋白質", "protein", "3.5公克", "11.7公克"),
                    row("脂肪", "fat", "4公克", "13.3公克"), row("碳水化合物", "carbohydrate", "18公克", "60公克")].joined(separator: ",")
        let reading = try XCTUnwrap(LabelPhotoReader().reading(wireText: wire(headers: twoColumns, rows: rows), imageSHA256: sha))
        XCTAssertTrue(reading.gate?.flags.contains { $0.code == LabelGateReason.requiredRowMissing.rawValue } == true)
        XCTAssertEqual(reading.candidate.cells.count, 8)
    }
}
