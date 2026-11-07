import FoodLedgerApplication
import XCTest

/// Contract test 24 (docs/pasted-label-ai-text-v1.md 4.7, D13 and D18): the pre-send detector
/// declines US, Australian and New Zealand panels on their markers, one vector per rule, and
/// never declines a UK or EU English panel. Synthetic panels only. The proof that no request is
/// built for a detected panel needs the request builder and the orchestrator (A2 and A5).
final class PastedLabelAITextPanelDetectorTests: XCTestCase {
    typealias Detector = PastedLabelAITextPanelDetector

    static let uk = """
    Nutrition
    Typical values Per 100g Per 30g serving %RI*
    Energy 1046kJ/250kcal 314kJ/75kcal 4%
    Fat 5.0g 1.5g 2%
    of which saturates 1.2g 0.4g 2%
    Carbohydrate 40g 12g
    of which sugars 3.1g 0.9g 1%
    Fibre 2.4g 0.7g
    Protein 8.0g 2.4g
    Salt 0.50g 0.15g 3%
    *Reference intake of an average adult (8400kJ/2000kcal)
    """

    static let ukWithSodium = "Per 100g\nEnergy 1046kJ/250kcal\nFat 5g\nSalt 1.0g\nSodium 0.4g"

    static let euEnglish = """
    Nutrition declaration
    Average nutritional values per 100 g
    Energy 1880 kJ / 450 kcal
    Fat 22 g
    of which saturates 13 g
    Carbohydrate 56 g
    of which sugars 50 g
    Protein 6,3 g
    Salt 0,25 g
    """

    func testUKAndEUEnglishPanelsPass() {
        for text in [Self.uk, Self.ukWithSodium, Self.euEnglish] {
            XCTAssertEqual(Detector.detect(text: text).markers, [], text)
            XCTAssertFalse(Detector.detect(text: text).declines)
        }
    }

    func testTaiwanBilingualSodiumPasses() {
        XCTAssertFalse(Detector.detect(text: "營養標示\n每份 每100公克\n鈉 Sodium 50毫克 100毫克").declines)
    }

    func testEachUSRuleDeclines() {
        XCTAssertEqual(Detector.detect(text: "Nutrition Facts\nServing size 30g\nTotal Fat 5g\nSalt 1g").markers, [.nutritionFactsTitle])
        XCTAssertEqual(Detector.detect(text: "Amount per 100g\nTotal Fat 5g 6% Daily Value\nSalt 1g").markers, [.dailyValue])
        XCTAssertEqual(Detector.detect(text: "Amount per 100g\nTotal Fat 5g 6% DV\nSalt 1g").markers, [.dailyValue])
        XCTAssertEqual(Detector.detect(text: "Amount per 100 g\nCalories 250\nTotal Fat 5g\nSodium 400mg").markers, [.sodiumWithoutSalt])
        let full = Detector.detect(text: "Nutrition Facts\nAmount per 100 g\nSodium 400mg 17%\n*The % Daily Value tells you")
        XCTAssertEqual(full.markers, [.nutritionFactsTitle, .dailyValue, .sodiumWithoutSalt])
        XCTAssertEqual(full.panels, [.us])
    }

    func testEachAustralianAndNewZealandRuleDeclines() {
        XCTAssertEqual(Detector.detect(text: "NUTRITION INFORMATION\nAvg Quantity per 100g\nEnergy 1046kJ\nSodium 400mg\nSalt 1g").markers,
                       [.averageQuantity])
        XCTAssertEqual(Detector.detect(text: "NUTRITION INFORMATION\nQuantity per Serve\nEnergy 314kJ\nSalt 1g").markers, [.perServe])
        XCTAssertEqual(Detector.detect(text: "NUTRITION INFORMATION\nServings per package: 8\nEnergy 314kJ\nSalt 1g").markers,
                       [.servingsPerPackage])
        let full = Detector.detect(text: "NUTRITION INFORMATION\nServings per package: 8\nServing size: 30g\nAverage Quantity per Serve\nSodium 120mg")
        XCTAssertEqual(full.markers, [.sodiumWithoutSalt, .averageQuantity, .perServe, .servingsPerPackage])
        XCTAssertEqual(full.panels, [.us, .australiaNewZealand])
    }

    func testCandidateIsCheckedAgain() {
        XCTAssertEqual(Detector.detect(candidateHeaders: ["Per 100g"], rowLabels: ["Energy", "Fat", "Sodium"],
                                       nutrients: ["energy_kj", "fat", "sodium"]).markers, [.sodiumWithoutSalt])
        XCTAssertEqual(Detector.detect(candidateHeaders: ["Avg Quantity per Serve"], rowLabels: ["Energy", "Salt"],
                                       nutrients: ["energy_kj", "salt"]).markers, [.averageQuantity, .perServe])
        XCTAssertFalse(Detector.detect(candidateHeaders: ["Per 100g", "%RI"], rowLabels: ["Energy", "Fat", "Salt"],
                                       nutrients: ["energy_kj", "fat", "salt"]).declines)
        XCTAssertFalse(Detector.detect(candidateHeaders: ["每份"], rowLabels: ["熱量", "鈉"], nutrients: ["energy_kcal", "sodium"]).declines)
    }

    func testVersion() { XCTAssertEqual(Detector.version, "pasted-label-ai-text-panel-detector-v1") }
}
