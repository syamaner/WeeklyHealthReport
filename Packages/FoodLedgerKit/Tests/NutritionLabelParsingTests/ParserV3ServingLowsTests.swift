import Foundation
import Testing
@testable import NutritionLabelParsing

// Reader v3 section 8.4.14: the low findings of PR 3's final review, carried into PR 4's first
// code commit. Each narrows serving and pack reading on the conservative side. Every fixture is
// synthetic: invented values and names, modelled on layout shapes only.

private let hash = String(repeating: "0", count: 64)
private func parse(_ text: String) -> LabelCaptureCandidate {
    NutritionLabelTextParserV3().parse(text, inputSHA256: hash)
}
private let table = "每份\n熱量 120大卡\n蛋白質 3.0公克\n脂肪 4.5公克\n飽和脂肪 1.5公克\n反式脂肪 0公克\n碳水化合物 18.0公克\n糖 6.0公克\n鈉 60毫克\n"
private func label(_ lines: String) -> LabelCaptureCandidate { parse("營養標示\n" + lines + "\n" + table) }
private let flatRows = "每份 熱量 120大卡 蛋白質 3.0公克 脂肪 4.5公克 飽和脂肪 1.5公克 反式脂肪 0公克 碳水化合物 18.0公克 糖 6.0公克 鈉 60毫克"

/// 1. The servings-per lead is any `servings per <word>` or `servings/<word>`, with an optional
/// bracketed qualifier before the colon and serving v3's approximation words: the number after it
/// is a pack count, compared with the Chinese count.
@Test func aWiderServingsPerLeadMakesItsNumberAPackCount() {
    for english in ["Servings/container: 3 bars", "Servings per bag: 3 bars", "Servings per container (approx.): 3 bars",
                    "Servings per container: approximately 3 bars", "Servings per container: around 3 bars",
                    "Servings per container: ~3 bars", "Servings per container: ca. 3 bars"] {
        let candidate = label("每一份量 30公克 (\(english)) 本包裝含 2份")
        #expect(candidate.servingsPerPack == nil, "\(english): \(String(describing: candidate.servingsPerPack))")
        #expect(candidate.warnings.contains("bilingual_quantity_conflict: servings_per_pack"), "\(english)")
    }
    // Agreeing counts still read, and an approximation word in the lead makes them approximate.
    let agree = label("每一份量 30公克 (Servings per container: about 2) 本包裝含 2份")
    #expect(agree.servingsPerPack?.decimalText == "2")
    #expect(agree.servingsPerPack?.approximate == true)
    // A count word that does not follow a servings-per phrase is still not a pack count.
    #expect(label("每一份量 30公克 (2 pieces) 本包裝含 3份").servingsPerPack?.decimalText == "3")
}

/// 2. A second Chinese count on a pack line must equal the first; 約 in it makes the count
/// approximate.
@Test func aSecondChineseCountOnAPackLineIsCompared() {
    let differs = label("每一份量 30公克\n本包裝含 2份 (約3份)")
    #expect(differs.servingsPerPack == nil, "\(String(describing: differs.servingsPerPack))")
    #expect(differs.warnings.contains("bilingual_quantity_conflict: servings_per_pack"))
    let differsPack = label("每一份量 30公克\n本包裝含 2份 (每包裝 3份)")
    #expect(differsPack.servingsPerPack == nil)
    let same = label("每一份量 30公克\n本包裝含 3份 (每包裝 3份)")
    #expect(same.servingsPerPack?.decimalText == "3")
    #expect(same.servingsPerPack?.approximate == false)
    let about = label("每一份量 30公克\n本包裝含 3份 (約3份)")
    #expect(about.servingsPerPack?.decimalText == "3")
    #expect(about.servingsPerPack?.approximate == true)
    // On a serving line holding a pack phrase, too.
    #expect(label("每一份量 30公克 本包裝含 2份 (約3份)").servingsPerPack == nil)
    let inline = label("每一份量 30公克 本包裝含 3份 (約3份)")
    #expect(inline.servingsPerPack?.decimalText == "3")
    #expect(inline.servingsPerPack?.approximate == true)
}

/// 3. A bare ASCII bracket beside a full-width Chinese serving number is not bound.
@Test func aBareBracketBesideAFullWidthServingNumberIsNotBound() {
    for line in ["每一份量 ３０公克 (30g)", "每一份量 ３０公克（30g）", "每一份量 ３０公克"] {
        let candidate = label(line + "\n本包裝含 2份")
        #expect(candidate.servingSize?.decimalText == nil, "\(line): \(String(describing: candidate.servingSize))")
        #expect(candidate.servingSize?.printedText == line)
    }
    #expect(label("每一份量 30公克 (30g)\n本包裝含 2份").servingSize?.decimalText == "30")
}

/// 4. Approximation is scanned the same way, on the stripped text, on stand-alone pack lines and
/// on flattened lines.
@Test func approximationIsScannedOnStandAlonePackAndFlattenedLines() {
    let standAlone = label("每一份量 30公克\n本包裝含 2份 (約2份)")
    #expect(standAlone.servingsPerPack?.decimalText == "2")
    #expect(standAlone.servingsPerPack?.approximate == true)
    // On a flattened line the serving and pack segments are stripped and scanned together.
    let flattened = parse("營養標示\n每一份量 30公克 (約2份) 本包裝含 2份 " + flatRows + "\n")
    #expect(!flattened.declined, "\(flattened.declineReasons)")
    #expect(flattened.servingsPerPack?.decimalText == "2")
    #expect(flattened.servingsPerPack?.approximate == true)
    let flattenedDiffers = parse("營養標示\n每一份量 30公克 (約3份) 本包裝含 2份 " + flatRows + "\n")
    #expect(!flattenedDiffers.declined, "\(flattenedDiffers.declineReasons)")
    #expect(flattenedDiffers.servingsPerPack == nil)
    let plain = parse("營養標示\n每一份量 30公克 本包裝含 2份 " + flatRows + "\n")
    #expect(plain.servingsPerPack?.approximate == false)
    // A count word's 約 is stripped with it only when the count word goes; the pack stays exact
    // when nothing approximate is left.
    #expect(label("每一份量 30公克\n本包裝含 6份 (12 pieces)").servingsPerPack?.approximate == false)
}

/// 5. `Serving size 30g (x2)` is a multiplied serving: not read.
@Test func aBracketedMultiplierIsNotRead() {
    for line in ["Serving size 30g (x2)", "Serving size 30g (×2)", "Serving size 30g ( x 2 )"] {
        #expect(parse(line + "\nPer serving\nEnergy 120kcal\nFat 3g\n").servingSize?.decimalText == nil, "\(line)")
    }
    #expect(label("每一份量 30公克 (×2)").servingSize?.decimalText == nil)
    // A bracket that is not a multiplier still reads.
    #expect(parse("Serving size 30g (2 biscuits)\nPer serving\nEnergy 120kcal\nFat 3g\n").servingSize?.decimalText == "30")
}
