import Foundation
import Testing
@testable import NutritionLabelParsing

// All fixtures are synthetic. The muesli table reproduces the owner's hand-checked values
// (docs/nutrition-label-capture-evaluation-v1.md section 3.4) in Traditional Chinese.

private let hash = String(repeating: "0", count: 64)
private func parse(_ text: String) -> LabelCaptureCandidate {
    NutritionLabelTextParser().parse(text, inputSHA256: hash)
}
private func cell(_ candidate: LabelCaptureCandidate, _ nutrient: String, _ basis: LabelBasis) -> LabelCell? {
    candidate.cells.first { $0.nutrient == nutrient && $0.basis == basis }
}

private let muesli = """
營養標示
每一份量100公克
本包裝含5份
　　　　　　每份　　　每100公克
熱量　　　367.2大卡　367.2大卡
蛋白質　　11公克　　11公克
脂肪　　　8.8公克　　8.8公克
　飽和脂肪　1.2公克　　1.2公克
　反式脂肪　0公克　　0公克
碳水化合物　67公克　　67公克
　糖　　　9.1公克　　9.1公克
　膳食纖維　12公克　　12公克
鈉　　　　8毫克　　8毫克
"""

@Test func taiwanTwoColumnTableBindsEveryRowAndColumn() {
    let candidate = parse(muesli)
    #expect(!candidate.declined)
    #expect(candidate.language == .traditionalChinese)
    #expect(candidate.headers.map(\.basis) == [.perServing, .per100g])
    #expect(candidate.cells.count == 18)
    #expect(candidate.servingSize == LabelServingSize(printedText: "每一份量100公克", decimalText: "100", unit: "公克", canonicalUnit: "g"))
    #expect(candidate.servingsPerPack == LabelServingsPerPack(printedText: "本包裝含5份", decimalText: "5", approximate: false))
    let energy = cell(candidate, "energy_kcal", .perServing)
    #expect(energy?.decimalText == "367.2")
    #expect(energy?.unit == "大卡")
    #expect(energy?.canonicalUnit == "kcal")
    #expect(energy?.servingConversion == "100公克")
    #expect(cell(candidate, "fibre", .per100g)?.parentRowID == "carbohydrate")
    #expect(cell(candidate, "saturates", .per100g)?.parentRowID == "fat")
    #expect(cell(candidate, "trans_fat", .perServing)?.decimalText == "0")
    #expect(cell(candidate, "sodium", .per100g)?.canonicalUnit == "mg")
    #expect(cell(candidate, "sodium", .per100g)?.servingConversion == "not_applicable")
    #expect(candidate.wouldMarkReady)
}

@Test func candidateNeverAuthorisesPersistence() throws {
    let data = try JSONEncoder().encode(parse(muesli))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["ready_for_confirmation"] as? Bool == false)
    #expect(object["automatic_save"] as? Bool == false)
    #expect(object["status"] as? String == "user_selection_only")
    let cells = try #require(object["cells"] as? [[String: Any]])
    #expect(cells.allSatisfy { $0["persistence_authorized"] as? Bool == false && $0["requires_user_selection"] as? Bool == true })
    let decoded = try JSONDecoder().decode(LabelCaptureCandidate.self, from: data)
    #expect(decoded == parse(muesli))
}

@Test func unknownServingFieldsStayExplicit() throws {
    let candidate = parse("Typical values\tPer 100g\nEnergy\t1500kJ\nFat\t3.0g")
    let data = try JSONEncoder().encode(candidate)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["serving_size"] as? String == "unknown")
    #expect(object["servings_per_pack"] as? String == "unknown")
}

@Test func taiwanOneValuePerLineWithSpacedUnits() {
    let text = """
    營養標示
    每一份量 30 公克
    本包裝含 2.5 份
    每份
    每100公克
    熱量
    120 大卡
    400 大卡
    蛋白質
    3 公克
    10 公克
    脂肪
    < 0.5 公克
    1.2 公克
    碳水化合物
    25 公克
    83.3 公克
    鈉
    50 毫克
    166 毫克
    """
    let candidate = parse(text)
    #expect(!candidate.declined)
    #expect(candidate.servingsPerPack?.decimalText == "2.5")
    #expect(candidate.servingSize?.decimalText == "30")
    let fat = cell(candidate, "fat", .perServing)
    #expect(fat?.comparator == .less)
    #expect(fat?.decimalText == "0.5")
    #expect(fat?.printedText == "< 0.5 公克")
    #expect(cell(candidate, "sodium", .per100g)?.decimalText == "166")
}

@Test func taiwanReferenceIntakeColumnIsNeverAnAmount() {
    let text = """
    營養標示
    每一份量50公克
    本包裝含4份
    \t每份\t每日參考值百分比
    熱量\t200大卡\t10%
    蛋白質\t5公克\t8%
    鈉\t100毫克\t5%
    """
    let candidate = parse(text)
    #expect(!candidate.declined)
    let reference = cell(candidate, "protein", .referenceIntake)
    #expect(reference?.canonicalUnit == "%")
    #expect(reference?.decimalText == "8")
    #expect(cell(candidate, "energy_kcal", .referenceIntake)?.decimalText == "10")
}

@Test func ukTabSeparatedTableWithEnergyContinuationLine() {
    let text = """
    Typical values\tPer 100g\tPer serving (30g)\t%RI*
    Energy\t1500kJ\t450kJ
    \t355kcal\t106kcal\t5%
    Fat\t3.4g\t1.0g\t1%
    of which saturates\t<0.1g\t<0.1g\t1%
    Carbohydrate\t60g\t18g
    of which sugars\t6.7g\t2.0g\t2%
    Fibre\t8.0g\t2.4g
    Protein\t11g\t3.3g
    Salt\t0.55g\t0.17g\t3%
    *Reference intake of an average adult (8400kJ/2000kcal)
    """
    let candidate = parse(text)
    #expect(!candidate.declined)
    #expect(candidate.language == .english)
    #expect(cell(candidate, "energy_kj", .perServing)?.decimalText == "450")
    #expect(cell(candidate, "energy_kcal", .per100g)?.decimalText == "355")
    #expect(cell(candidate, "energy_kcal", .referenceIntake)?.decimalText == "5")
    #expect(cell(candidate, "saturates", .per100g)?.comparator == .less)
    #expect(cell(candidate, "saturates", .per100g)?.parentRowID == "fat")
    #expect(cell(candidate, "sugars", .per100g)?.parentRowID == "carbohydrate")
    #expect(cell(candidate, "fibre", .per100g)?.parentRowID == nil)
    #expect(cell(candidate, "salt", .perServing)?.servingConversion == "30g")
    #expect(cell(candidate, "sodium", .perServing) == nil)
}

@Test func ukSpaceAlignedSlashEnergyAndWrappedLabel() {
    let text = """
    Nutrition
    Typical values    Per 100ml    Per 250ml serving
    Energy    180kJ/43kcal    450kJ/108kcal
    Fat    0g    0g
    of which
    saturates    0g    0g
    Carbohydrate    10.6g    26.5g
    of which sugars    10.6g    26.5g
    Protein    0g    0g
    Salt    0.01g    0.03g
    """
    let candidate = parse(text)
    #expect(!candidate.declined)
    #expect(candidate.headers.map(\.basis) == [.per100ml, .perServing])
    #expect(cell(candidate, "saturates", .per100ml)?.parentRowID == "fat")
    #expect(cell(candidate, "energy_kcal", .perServing)?.decimalText == "108")
    #expect(cell(candidate, "salt", .perServing)?.servingConversion == "250ml")
}

// US-style rows are parsed, but `Calories 230` has no printed energy unit, so a real US
// panel declines (plan section 6); this fixture omits the calories line to test binding.
@Test func usStyleTableWithDailyValueColumn() {
    let text = """
    Nutrition Facts
    Servings per container about 8
    Serving size 2/3 cup (55g)
    Amount per serving
    % Daily Value*
    Total Fat 8g 10%
      Saturated Fat 1g 5%
      Trans Fat 0g
    Sodium 160mg 7%
    Total Carbohydrate 37g 13%
      Dietary Fiber 4g 14%
      Total Sugars 12g
    Protein 3g
    """
    let candidate = parse(text)
    #expect(!candidate.declined)
    #expect(candidate.servingsPerPack == LabelServingsPerPack(printedText: "Servings per container about 8", decimalText: "8", approximate: true))
    #expect(candidate.servingSize?.decimalText == "55")
    #expect(cell(candidate, "saturates", .perServing)?.parentRowID == "fat")
    #expect(cell(candidate, "fibre", .perServing)?.parentRowID == "carbohydrate")
    #expect(cell(candidate, "sodium", .referenceIntake)?.decimalText == "7")
    #expect(candidate.declined == false)
}

@Test func caloriesWithoutUnitDeclines() {
    let candidate = parse("Amount per serving\nCalories 230\nFat 8g")
    #expect(candidate.declined)
    #expect(candidate.declineReasons == ["energy_without_unit"])
    #expect(candidate.cells.isEmpty)
}

@Test func saltAndSodiumAreNeverConverted() {
    let candidate = parse("\tPer 100g\nSalt\t1.2g\nSodium\t480mg")
    #expect(cell(candidate, "salt", .per100g)?.decimalText == "1.2")
    #expect(cell(candidate, "sodium", .per100g)?.decimalText == "480")
    #expect(candidate.cells.count == 2)
}

@Test func lessThanWordIsABound() {
    let candidate = parse("\tPer 100g\nSugars\tless than 1g")
    let sugars = cell(candidate, "sugars", .per100g)
    #expect(sugars?.comparator == .less)
    #expect(sugars?.decimalText == "1")
}

@Test(arguments: [
    ("Fat 3g\nProtein 2g", "no_basis_header"),
    ("Per 100g\nFat 3g 4g\nProtein 2g", "count_mismatch"),
    ("\tPer 100g\tPer serving\nFat\t3g\nProtein\t2g\t1g", "count_mismatch"),
    ("\tPer 100g\nFat\t3\nProtein\t2g", "value_without_unit"),
    ("\tPer 100g\nEnergy\t400\nFat\t2g", "energy_without_unit"),
    ("\tPer 100g\tPer 100g\nFat\t3g\t3g", "duplicate_basis"),
    ("营养成分表\n项目\t每100克\n能量\t1500千焦", "unsupported_language"),
    ("栄養成分表示\nエネルギー 100kcal", "unsupported_language"),
    ("영양정보\n\t100g당\n열량\t250kcal", "unsupported_language"),
    ("營養標示\n每份\t每100公克\n熱量\t100大卡\t200大卡\nㅇ", "unsupported_language"),
    ("營養標示\n每份\t每100公克\n熱量\t100大卡\t200大卡\n\u{A960}", "unsupported_language"),
    ("營養標示\n每份\t每100公克\n熱量\t100大卡\t200大卡\n\u{D7B0}", "unsupported_language"),
    ("營養標示\n每份\t每100公克\n熱量\t100大卡\t200大卡\n\u{FFA1}", "unsupported_language"),
    ("1500\n3.0g\n0.5g", "unsupported_language"),
    ("Ingredients: oats, raisins", "no_basis_header"),
    ("", "no_table"),
    ("營養標示\n每份\t每100公克\n熱量\t100大卡\t200大卡\n營養標示\n每份\t每100公克\n熱量\t50大卡\t100大卡", "multiple_panels"),
    ("\tPer 100g\nFat\t3 IU", "value_without_unit"),
])
func declinesInsteadOfGuessing(text: String, reason: String) {
    let candidate = parse(text)
    #expect(candidate.declined)
    #expect(candidate.declineReasons == [reason])
    #expect(candidate.cells.isEmpty)
    #expect(!candidate.wouldMarkReady)
}

@Test func unrecognisedRowsAreKeptAndBlockReady() {
    let candidate = parse("\tPer 100g\nEnergy\t1500kJ\nCalcium\t120mg\n of which starch\t30g")
    #expect(!candidate.declined)
    let calcium = candidate.cells.first { $0.printedLabel == "Calcium" }
    #expect(calcium?.nutrient == "unrecognised")
    #expect(calcium?.decimalText == "120")
    #expect(!candidate.wouldMarkReady)
    #expect(candidate.warnings.contains("unrecognised_row: Calcium"))
}

@Test func valueOnlyLineAfterACompleteRowBlocksReady() {
    // A % cell whose own row label was not captured lands after a complete row: the counts
    // still match, so only the attachment rule stops a silent misbinding.
    let candidate = parse("\tPer 100g\t%RI\nFat\t3g\n4%\nProtein\t2g\t4%")
    #expect(!candidate.declined)
    #expect(!candidate.wouldMarkReady)
    #expect(candidate.warnings.contains("values_after_complete_row: Fat"))
}

@Test func valueOnlyLineAfterACompleteRowWithMismatchedCountDeclines() {
    let candidate = parse("\tPer 100g\nFat\t3g\n2g\nProtein\t2g")
    #expect(candidate.declined)
    #expect(candidate.declineReasons == ["count_mismatch"])
}

@Test func provablySafeValueOnlyLinesStillAttach() {
    let stacked = parse("\tPer 100g\nEnergy\t1500kJ\n355kcal\nFat\t3g")
    #expect(stacked.wouldMarkReady)
    #expect(stacked.cells.contains { $0.nutrient == "energy_kcal" && $0.decimalText == "355" })
    let separate = parse("\tPer 100g\nFat\n3g\nProtein\t2g")
    #expect(separate.wouldMarkReady)
    #expect(separate.warnings.isEmpty)
    let repeatedUnit = parse("\tPer 100g\nEnergy\t1500kJ\n1500kJ")
    #expect(!repeatedUnit.wouldMarkReady)
}

@Test func partialRowWithoutValuesIsNeverReady() {
    let candidate = parse("\tPer 100g\nEnergy\t1500kJ\nFibre\nProtein\t3g")
    #expect(!candidate.declined)
    #expect(candidate.warnings.contains("row_without_values: Fibre"))
    #expect(!candidate.wouldMarkReady)
}

@Test func perServingWithoutPrintedQuantityStaysUnknown() {
    let candidate = parse("\tPer serving\nFat\t3g")
    #expect(cell(candidate, "fat", .perServing)?.servingConversion == "unknown")
}

@Test func wrappedServingHeaderTakesItsQuantity() {
    let candidate = parse("Per 100g\nPer serving\n(45g)\nFat\n3g\n1.4g")
    #expect(cell(candidate, "fat", .perServing)?.servingConversion == "45g")
    #expect(cell(candidate, "fat", .perServing)?.decimalText == "1.4")
}

@Test func mixedLanguageIsRecorded() {
    let candidate = parse("營養標示 Nutrition\n每份\t每100公克\n熱量\t100大卡\t200大卡")
    #expect(candidate.language == .mixed)
}
