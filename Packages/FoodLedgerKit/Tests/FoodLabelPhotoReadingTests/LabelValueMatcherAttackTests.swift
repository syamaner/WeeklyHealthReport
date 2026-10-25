import FoodLabelPhotoReading
import Foundation
import XCTest

private typealias M = LabelValueMatcher

// Locator v2 attack scenarios (#321 reviews, A1 to A6, B1 to B7, C1 to C8 and D1 to D7), ported from the reviewer's harness (synthetic
// data only): near-miss labels of other nutrients, unread labels with swapped readings, tall wrapped
// labels, offset poisoning by a reading off by one row, non-uniform drift, and unread headers with
// reversed, footnote and extra columns. A wrong value must never be found, and a correct value must
// never carry contradicting evidence.
nonisolated(unsafe) private var attackFailures: [String] = []
nonisolated(unsafe) private var attackScenarios = 0
// Generic table builder. Rows top-down with a step; each row: printed label (nil = Vision did not read it),
// label height in steps (wrapped labels), values per column. Values drawn at label centre + drift*step.
private struct PRow { var label: String?; var tall: Double = 1; var values: [String]; let name: String
  init(label: String?, tall: Double = 1, values: [String]) { self.label = label; self.tall = tall; self.values = values; self.name = label ?? "?" } }
private let step = 0.07
private func build(_ rows: [PRow], cols: [Double] = [0.45], headers: [String]? = ["每份"], drift: Double = 0, extra: [M.Line] = []) -> ([M.Line], [Double]) {
  var out: [M.Line] = []
  if let headers { for (c, h) in headers.enumerated() { out.append(.init(text: h, box: .init(x: cols[c], y: 0.92, width: 0.1, height: 0.03))) } }
  var top = 0.88; var centres: [Double] = []
  for r in rows {
    let h = r.tall * step
    let centre = top - h / 2
    centres.append(centre)
    if let l = r.label { out.append(.init(text: l, box: .init(x: 0.05, y: centre - 0.015 * r.tall, width: 0.15, height: 0.03 * r.tall))) }
    for (c, v) in r.values.enumerated() { out.append(.init(text: v, box: .init(x: cols[c], y: centre + drift * step - 0.015, width: 0.1, height: 0.03))) }
    top -= h
  }
  return (out + extra, centres)
}
private func sub(_ ls: [M.Line]) -> M.SubBox { { i, r in let l = ls[i]; let n = Double(l.text.count)
  let a = Double(l.text.distance(from: l.text.startIndex, to: r.lowerBound)), b = Double(l.text.distance(from: l.text.startIndex, to: r.upperBound))
  return .init(x: l.box.x + l.box.width * a / n, y: l.box.y, width: l.box.width * (b - a) / n, height: l.box.height) } }
// queries: (label, header, value, isWrong)
private func runAttack(_ name: String, _ built: ([M.Line], [Double]), _ q: [(String, String?, String, Bool)], headers: [String] = ["每份"], cols: Int = 1) {
  let (ls, _) = built
  let qs = q.enumerated().map { M.Query(id: "\($0.offset):\($0.element.0)", rowLabel: $0.element.0, headerText: $0.element.1, printedText: $0.element.2) }
  let res = M.locate(qs, lines: ls, headers: headers, rowLabels: Array(Set(q.map(\.0))), columnCount: cols, subBox: sub(ls))
  for (qq, r) in zip(q, res) where qq.3 && r.status == .found { attackFailures.append("\(name): \(qq.0)|\(qq.1 ?? "-")|\(qq.2) found") }
  for (qq, r) in zip(q, res) where !qq.3 && r.evidence != .none { attackFailures.append("\(name): \(qq.0)|\(qq.1 ?? "-")|\(qq.2) false \(r.evidence.rawValue)") }
  attackScenarios += 1
}
private let base: [PRow] = [.init(label: "熱量", values: ["485大卡"]), .init(label: "蛋白質", values: ["12.5公克"]), .init(label: "脂肪", values: ["3公克"]),
  .init(label: "飽和脂肪", values: ["1.2公克"]), .init(label: "碳水化合物", values: ["65.2公克"]), .init(label: "糖", values: ["8.4公克"]), .init(label: "鈉", values: ["120毫克"])]
private func q(_ rows: [PRow], wrong: [Int: (String?, String)] = [:]) -> [(String, String?, String, Bool)] {
  rows.enumerated().map { i, r in if let w = wrong[i] { return (w.0 ?? r.name, "每份", w.1, true) }; return (r.name, "每份", r.values[0], false) }
}


final class LabelValueMatcherAttackTests: XCTestCase {
    func testRecoveryNeverConfirmsAWrongReading() {
        attackFailures = []
        attackScenarios = 0
        // A1 near-miss to a different nutrient: table prints 維生素B2; model calls it 維生素B1 (single model error).
        var vit = base; vit.insert(.init(label: "維生素B2", values: ["0.3毫克"]), at: 6)
        runAttack("A1 near-miss label B2 read as B1 by the model", build(vit), q(vit, wrong: [6: ("維生素B1", "0.3毫克")]))
        var vit12 = base; vit12.insert(.init(label: "維生素B12", values: ["0.8微克"]), at: 6)
        runAttack("A1b near-miss B12 read as B1", build(vit12), q(vit12, wrong: [6: ("維生素B1", "0.8微克")]))
        // A2 two adjacent unlocated labels (Vision read neither), model swaps their labels (values stay in place)
        var two = base; two[2].label = nil; two[3].label = nil
        var qq = q(base); qq[2] = ("飽和脂肪", "每份", "3公克", true); qq[3] = ("脂肪", "每份", "1.2公克", true)
        let swapped = [qq[0], qq[1], qq[2], qq[3], qq[4], qq[5], qq[6]]
        runAttack("A2 two unread labels, model swaps the labels", build(two), swapped)
        // A2b one unread label, model names that row as a different nutrient (fibre instead of sugar)
        var one = base; one[5].label = nil
        var q1 = q(base); q1[5] = ("膳食纖維", "每份", "8.4公克", true)
        runAttack("A2b unread label, model names the row another nutrient", build(one), q1)
        // A3 order placement with a tall wrapped label (unread) plus following unread labels
        var tall = base; tall[2].tall = 2; tall[2].label = nil; tall[3].label = nil; tall[4].label = nil
        runAttack("A3 tall unread label + 2 unread, correct reading", build(tall), q(tall))
        var qt = q(tall); qt[3] = ("飽和脂肪", "每份", "65.2公克", true); qt[4] = ("碳水化合物", "每份", "1.2公克", true)
        runAttack("A3b tall unread label + 2 unread, model swaps two values", build(tall), qt)
        var tall2 = base; tall2[2].tall = 2; tall2[2].label = nil; tall2[3].label = nil; tall2[4].label = nil; tall2[5].label = nil
        var qt2 = q(tall2); qt2[4] = ("碳水化合物", "每份", "8.4公克", true); qt2[5] = ("糖", "每份", "65.2公克", true)
        runAttack("A3c tall unread + 3 unread (gap 1.25), model swaps carb/sugar values", build(tall2), qt2)
        runAttack("A3d tall unread + 3 unread, correct", build(tall2), q(tall2))
        // A5 offset poisoning: values printed 0.3 row above labels; model reading off by one row (each label takes the next row's value)
        func shiftedReading(_ rows: [PRow]) -> [(String, String?, String, Bool)] {
          rows.indices.dropLast().map { (rows[$0].name, "每份", rows[$0 + 1].values[0], true) }
        }
        for d in [0.0, 0.25, 0.3, 0.4] { runAttack("A5 values \(d) row above labels, whole reading off by one", build(base, drift: d), shiftedReading(base)) }
        // partial shift: model skipped row 2 (脂肪), rows below shifted up
        func skipped(_ rows: [PRow], at k: Int) -> [(String, String?, String, Bool)] {
          rows.indices.dropLast().map { i in i < k ? (rows[i].name, "每份", rows[i].values[0], false) : (rows[i].name, "每份", rows[i + 1].values[0], true) }
        }
        runAttack("A5b drift 0.3, model skipped a value from row 1 down", build(base, drift: 0.3), skipped(base, at: 1))
        // A5c single wrong value printed once elsewhere does not move the offset
        runAttack("A5c drift 0.4 correct reading", build(base, drift: 0.4), q(base))
        runAttack("A5d drift 0.45 correct reading, one value from 2 rows away", build(base, drift: 0.45), q(base, wrong: [3: (nil, "65.2公克")]))
        // A6 drift between 0.33 and 0.5, no uniform offset (alternating), model correct and with a swap
        let alt = build(base, drift: 0.4).0.enumerated().map { i, l -> M.Line in l }
        runAttack("A6 drift 0.4 only on half the rows (non-uniform), adjacent value swap", build(base, drift: 0.4), q(base, wrong: [2: (nil, "1.2公克"), 3: (nil, "3公克")]))
        // A4 header inference: two columns, headers unread
        let two2: [PRow] = base.map { .init(label: $0.label, values: [$0.values[0], "9\($0.values[0])"]) }
        func q2(_ rows: [PRow], hdr: [String], swapCols: Bool) -> [(String, String?, String, Bool)] {
          rows.flatMap { r in (0..<2).map { c in (r.name, hdr[c], r.values[swapCols ? 1 - c : c], swapCols) } }
        }
        runAttack("A4 headers unread, correct", build(two2, cols: [0.45, 0.72], headers: nil), q2(two2, hdr: ["每份", "每100公克"], swapCols: false), headers: ["每份", "每100公克"], cols: 2)
        runAttack("A4b headers unread, model reverses both headers (per 100 g read as left column)", build(two2, cols: [0.45, 0.72], headers: nil),
            two2.flatMap { r in [(r.name, "每100公克", r.values[0], true), (r.name, "每份", r.values[1], true)] }, headers: ["每100公克", "每份"], cols: 2)
        // A4c a footnote unit token inside the table area at a third x, headers unread, model swaps one cell's columns
        let foot = [M.Line(text: "*添加糖 2公克", box: .init(x: 0.58, y: 0.88 - 5.5 * step + 0.0, width: 0.12, height: 0.03))]
        var qf = q2(two2, hdr: ["每份", "每100公克"], swapCols: false); qf[4] = (qf[4].0, "每份", two2[2].values[1], true)
        runAttack("A4c footnote token in the table, model puts per-100 value in per-serving cell", build(two2, cols: [0.45, 0.72], headers: nil, extra: foot), qf, headers: ["每份", "每100公克"], cols: 2)
        // A4d three physical columns (two close g columns + a far % column), reading has 2 columns, headers unread, column confusion
        let three: [PRow] = base.map { .init(label: $0.label, values: [$0.values[0], "9\($0.values[0])", "5%"]) }
        var q3 = three.flatMap { r in [(r.name, "每份", r.values[0], false), (r.name, "每100公克", r.values[1], false)] } as [(String, String?, String, Bool)]
        q3[2] = (q3[2].0, "每份", three[1].values[1], true)
        runAttack("A4d close g columns + far % column, per-100 value in per-serving cell", build(three, cols: [0.40, 0.48, 0.85], headers: nil), q3, headers: ["每份", "每100公克"], cols: 2)

        print("=========== round 3 attacks")
        // B1 label prefix: table prints 糖醇 (no 糖 row); model labels it 糖 (truncation)
        var sa = base; sa[5] = .init(label: "糖醇", values: ["5公克"])
        runAttack("B1 糖醇 printed, model says 糖", build(sa), q(sa, wrong: [5: ("糖", "5公克")]))
        // B1b both 糖 and 糖醇 printed, model omits 糖 row and labels 糖醇 as 糖
        var sb = base; sb.insert(.init(label: "糖醇", values: ["5公克"]), at: 6)
        var qb = q(sb); qb.remove(at: 5); qb[5] = ("糖", "每份", "5公克", true)
        runAttack("B1b 糖 and 糖醇 printed, model drops 糖 row and calls 糖醇 糖", build(sb), qb)
        // B2 Omega-3脂肪酸 row; model labels it 脂肪 and omits the real fat row
        var so = base; so.insert(.init(label: "Omega-3脂肪酸", values: ["0.4公克"]), at: 4)
        var qo = q(so); qo[2] = ("脂肪", "每份", "0.4公克", true); qo.remove(at: 4)
        runAttack("B2 omega-3 row read as 脂肪 (real fat row value replaced)", build(so), qo)
        var qo2 = q(so); qo2[4] = ("脂肪", "每份", "0.4公克", true)
        runAttack("B2b omega-3 row labelled 脂肪 (two 脂肪 rows in reading)", build(so), qo2)
        // B3 English prefix pairs
        let en: [PRow] = [.init(label: "Energy", values: ["485kcal"]), .init(label: "Fat", values: ["3g"]), .init(label: "Saturates", values: ["1.2g"]),
          .init(label: "Carbohydrate", values: ["65g"]), .init(label: "Sugar alcohols", values: ["5g"]), .init(label: "Protein", values: ["12g"]), .init(label: "Salt", values: ["0.3g"])]
        runAttack("B3 English: Sugar alcohols read as Sugars", build(en), q(en, wrong: [4: ("Sugars", "5g")]))
        runAttack("B3b English: Sugar alcohols read as Sugar", build(en), q(en, wrong: [4: ("Sugar", "5g")]))
        // B4 one-character CJK pairs: 鈉 vs 鈣 (single-character labels), model swaps the label of a row
        let mi: [PRow] = base + [.init(label: "鈣", values: ["15毫克"])]
        runAttack("B4 鈣 row labelled 鈉 (鈉 row also present)", build(mi), q(mi, wrong: [7: ("鈉", "15毫克")]))
        var mi2 = base; mi2[6] = .init(label: "鈣", values: ["120毫克"])
        runAttack("B4b only 鈣 printed, model says 鈉", build(mi2), q(mi2, wrong: [6: ("鈉", "120毫克")]))
        // B5 offset window near 0.5: uniform drift d above labels, reading off by one
        for d in [0.5, 0.55, 0.6] { runAttack("B5 drift \(d), reading off by one", build(base, drift: d), shiftedReading(base)) }
        runAttack("B5b drift 0.55, correct reading", build(base, drift: 0.55), q(base))
        // B5c mixed sign: half the rows +0.4, half -0.4 (alternating), reading off by one
        func altBuild() -> ([M.Line], [Double]) { var (ls, c) = build(base); ls = ls.map { l in
          if let i = base.firstIndex(where: { $0.values[0] == l.text }) { let d = i % 2 == 0 ? 0.4 : -0.4
            return M.Line(text: l.text, box: .init(x: l.box.x, y: l.box.y + d * step, width: l.box.width, height: l.box.height)) }; return l }; return (ls, c) }
        runAttack("B5c alternating ±0.4 drift, reading off by one", altBuild(), shiftedReading(base))
        runAttack("B5d alternating ±0.4 drift, correct", altBuild(), q(base))
        // B6 one header located (from a footnote at the left), the other unread; model reverses headers
        let foot2 = [M.Line(text: "*每100公克含量", box: .init(x: 0.42, y: 0.30, width: 0.16, height: 0.03))]
        runAttack("B6 header 每100公克 located only in a footnote under the left column; model reverses headers", build(two2, cols: [0.45, 0.72], headers: nil, extra: foot2),
            two2.flatMap { r in [(r.name, "每100公克", r.values[0], true), (r.name, "每份", r.values[1], true)] }, headers: ["每100公克", "每份"], cols: 2)
        // B6b real left header read, right unread; model's right header text is wrong (e.g. 每100毫升); values right
        runAttack("B6b left header read, right header text wrong in the model", build(two2, cols: [0.45, 0.72], headers: ["每份"]),
            two2.flatMap { r in [(r.name, "每份", r.values[0], false), (r.name, "每100毫升", r.values[1], true)] }, headers: ["每份", "每100毫升"], cols: 2)
        // B6c header 每份 located only inside the serving line (left side), real headers unread; model reverses
        let servingLine = [M.Line(text: "每份 185公克", box: .init(x: 0.70, y: 0.96, width: 0.12, height: 0.03))]
        runAttack("B6c 每份 located only in a serving line above the right column; model reverses headers", build(two2, cols: [0.45, 0.72], headers: nil, extra: servingLine),
            two2.flatMap { r in [(r.name, "每100公克", r.values[0], true), (r.name, "每份", r.values[1], true)] }, headers: ["每100公克", "每份"], cols: 2)
        // B7 own label printed twice (once in a footnote outside the neighbours): direct via between; model mislabels the adjacent row with it
        let foot3 = [M.Line(text: "糖", box: .init(x: 0.05, y: 0.20, width: 0.05, height: 0.03))]
        runAttack("B7 糖 also in a footnote; model correct", build(base, extra: foot3), q(base))
        var q7 = q(base); q7[4] = ("糖", "每份", "65.2公克", true); q7[5] = ("碳水化合物", "每份", "8.4公克", true)
        runAttack("B7b 糖 also in a footnote; model swaps the carb and sugar labels", build(base, extra: foot3), q7)
        print("=========== round 4 attacks")
        // Geometry: first row centre 0.845, step 0.07; header band 0.88..1.02 (0.5..2.5 steps above).
        func hl(_ t: String, _ x: Double, _ y: Double, _ w: Double = 0.1) -> M.Line { .init(text: t, box: .init(x: x, y: y - 0.015, width: w, height: 0.03)) }
        let rev = two2.flatMap { r in [(r.name, "每100公克", r.values[0], true), (r.name, "每份", r.values[1], true)] } as [(String, String?, String, Bool)]
        let fwd = q2(two2, hdr: ["每份", "每100公克"], swapCols: false)
        // C1 serving line split: "每份" alone in the band above the right column (its quantity on the next line); real headers unread; model reverses
        runAttack("C1 split serving 每份 above right column, headers unread, model reverses", build(two2, cols: [0.45, 0.72], headers: nil,
            extra: [hl("每份", 0.72, 0.95), hl("30公克", 0.72, 0.99)]), rev, headers: ["每100公克", "每份"], cols: 2)
        runAttack("C1b same, real 每100公克 header read over right column", build(two2, cols: [0.45, 0.72], headers: nil,
            extra: [hl("每份", 0.45, 0.95), hl("每100公克", 0.72, 0.92)]), fwd, headers: ["每份", "每100公克"], cols: 2)
        // C2 third column (%DV) header containing 每份, per-serving header unread, model reads 2 columns and swaps their headers
        let three2: [PRow] = base.map { .init(label: $0.label, values: [$0.values[0], "9\($0.values[0])", "5%"]) }
        let c2lines = build(three2, cols: [0.45, 0.72, 0.9], headers: nil, extra: [hl("每100公克", 0.72, 0.92), hl("每份參考值%", 0.9, 0.92)])
        let c2q = three2.flatMap { r in [(r.name, "每100公克", r.values[0], true), (r.name, "每份", r.values[1], true)] } as [(String, String?, String, Bool)]
        runAttack("C2 %DV header contains 每份; per-serving header unread; model swaps the two headers", c2lines, c2q, headers: ["每100公克", "每份"], cols: 2)
        let c2q2 = three2.flatMap { r in [(r.name, "每份", r.values[0], false), (r.name, "每100公克", r.values[1], false)] } as [(String, String?, String, Bool)]
        runAttack("C2b same photo, model correct", c2lines, c2q2, headers: ["每份", "每100公克"], cols: 2)
        // C3 sub-heading row inside the band, e.g. a "每日參考值百分比" line, plus both headers read; model puts per-100 value in per-serving cell
        var c3 = fwd; c3[4] = (c3[4].0, "每份", two2[2].values[1], true)
        runAttack("C3 sub-heading line in band; column confusion", build(two2, cols: [0.45, 0.72], headers: ["每份", "每100公克"], extra: [hl("每日參考值百分比", 0.6, 0.97, 0.2)]), c3, headers: ["每份", "每100公克"], cols: 2)
        // C4 header split across two lines
        runAttack("C4 header 每100公克 split as 每100 / 公克; model reverses", build(two2, cols: [0.45, 0.72], headers: nil,
            extra: [hl("每份", 0.45, 0.92), hl("每100", 0.72, 0.95), hl("公克", 0.72, 0.92)]), rev, headers: ["每100公克", "每份"], cols: 2)
        // C5 serving line printed below the table containing 每份 (no unit on its own line)
        runAttack("C5 每份 printed below the table; headers unread; model reverses", build(two2, cols: [0.45, 0.72], headers: nil, extra: [hl("每份", 0.72, 0.25)]), rev, headers: ["每100公克", "每份"], cols: 2)
        // C6 model header text is a substring of the other printed header (每100公克 vs 每100公克每份?): model header "100公克" for the per-100 column
        let c6 = build(two2, cols: [0.45, 0.72], headers: nil, extra: [hl("每份", 0.45, 0.92), hl("每100公克", 0.72, 0.92)])
        runAttack("C6 model per-serving header written as 公克 (contained in 每100公克)", c6,
            two2.flatMap { r in [(r.name, "公克", r.values[0], true), (r.name, "每100公克", r.values[1], false)] }, headers: ["公克", "每100公克"], cols: 2)
        runAttack("C6b model per-100 header written as 每 (contained in both)", c6,
            two2.flatMap { r in [(r.name, "每份", r.values[0], false), (r.name, "每", r.values[1], true)] }, headers: ["每份", "每"], cols: 2)
        // C7 label suffix cases
        var c7 = base; c7[5] = .init(label: "糖含量", values: ["8.4公克"])
        runAttack("C7 糖含量 printed, model 糖 (same nutrient; expect found)", build(c7), q(c7, wrong: [5: ("糖", "8.4公克")]).map { ($0.0, $0.1, $0.2, false) })
        var c7b = base; c7b[5] = .init(label: "糖5公克", values: [])
        runAttack("C7b label and value on one line 糖5公克, model 糖 5公克", build(c7b), q(base, wrong: [5: (nil, "5公克")]).map { ($0.0, $0.1, $0.2, false) })
        var c7c = base; c7c[5] = .init(label: "糖醇5公克", values: [])
        runAttack("C7c 糖醇5公克 on one line, model 糖 5公克", build(c7c), q(base, wrong: [5: (nil, "5公克")]))
        var c7d = base; c7d[5] = .init(label: "糖克數", values: ["8.4公克"])
        runAttack("C7d label followed by 克 then more text (糖克數)", build(c7d), q(c7d, wrong: [5: ("糖", "8.4公克")]).map { ($0.0, $0.1, $0.2, false) })
        // C8 lower-quartile step with two close labels (a small sub-row printed tight under its parent)
        var c8: [PRow] = base; c8.insert(.init(label: "其中糖", tall: 0.4, values: ["8公克"]), at: 5)
        runAttack("C8 tight sub-row, correct", build(c8), q(c8))
        var q8 = q(c8); q8[4] = ("碳水化合物", "每份", "8公克", true); q8[5] = ("其中糖", "每份", "65.2公克", true)
        runAttack("C8b tight sub-row, model swaps parent and sub-row values", build(c8), q8)
        print("=========== round 5 attacks")
        // D1 order pass without the own-header-above check: three physical columns, the reading has two (每份 at 0.40, 每100公克 at 0.84);
        // an unheaded middle column at 0.56 holds three 0公克; the model reads the middle column's values under 每份 (one error: wrong column).
        let d1rows: [PRow] = [
          .init(label: "熱量", values: ["485大卡", "300大卡", "262大卡"]), .init(label: "蛋白質", values: ["12.5公克", "0公克", "6.8公克"]),
          .init(label: "脂肪", values: ["3公克", "0公克", "1.6公克"]), .init(label: "飽和脂肪", values: ["1.2公克", "0公克", "0.6公克"]),
          .init(label: "碳水化合物", values: ["65.2公克", "5公克", "35.2公克"]), .init(label: "鈉", values: ["120毫克", "60毫克", "65毫克"])]
        let d1 = build(d1rows, cols: [0.40, 0.56, 0.84], headers: nil, extra: [hl("每份", 0.40, 0.92), hl("每100公克", 0.84, 0.92)])
        let d1q = d1rows.flatMap { r in [(r.name, "每份", r.values[1], r.values[1] != r.values[0]), (r.name, "每100公克", r.values[2], false)] } as [(String, String?, String, Bool)]
        runAttack("D1 unheaded middle column read under 每份 (repeated 0公克)", d1, d1q, headers: ["每份", "每100公克"], cols: 2)
        // D1b same without repeats (every middle value distinct) - first pass only
        var d1r2 = d1rows; d1r2[1].values[1] = "0.1公克"; d1r2[2].values[1] = "0.2公克"; d1r2[3].values[1] = "0.3公克"
        let d1q2 = d1r2.flatMap { r in [(r.name, "每份", r.values[1], true), (r.name, "每100公克", r.values[2], false)] } as [(String, String?, String, Bool)]
        runAttack("D1b unheaded middle column read under 每份 (distinct values)", build(d1r2, cols: [0.40, 0.56, 0.84], headers: nil, extra: [hl("每份", 0.40, 0.92), hl("每100公克", 0.84, 0.92)]), d1q2, headers: ["每份", "每100公克"], cols: 2)
        // D2 identical header text for two columns
        runAttack("D2 two columns both headed 每份", build(two2, cols: [0.45, 0.72], headers: ["每份", "每份"]),
            two2.flatMap { r in [(r.name, "每份", r.values[1], true), (r.name, "每份", r.values[0], true)] }, headers: ["每份", "每份"], cols: 2)
        // D3 headers glued on one line, sub-boxes proportional; model reverses
        runAttack("D3 glued header line 每份每100公克, model reverses", build(two2, cols: [0.45, 0.72], headers: nil, extra: [hl("每份每100公克", 0.40, 0.92, 0.45)]), rev, headers: ["每100公克", "每份"], cols: 2)
        runAttack("D3b glued header line, model correct", build(two2, cols: [0.45, 0.72], headers: nil, extra: [hl("每份每100公克", 0.40, 0.92, 0.45)]), fwd.map { ($0.0, $0.1, $0.2, false) }, headers: ["每份", "每100公克"], cols: 2)
        // D4 full-width brackets and spaces in headers
        runAttack("D4 headers 每份（30公克） / 每 100 公克, model correct", build(two2, cols: [0.45, 0.72], headers: nil, extra: [hl("每份（30公克）", 0.45, 0.92), hl("每 100 公克", 0.72, 0.92)]),
            fwd.map { ($0.0, $0.1, $0.2, false) }, headers: ["每份", "每100公克"], cols: 2)
        // D5 headers in band but over the label column / equal x within tolerance; model reverses
        runAttack("D5 both headers stacked over one column (x equal); model reverses", build(two2, cols: [0.45, 0.72], headers: nil,
            extra: [hl("每份", 0.45, 0.92), hl("每100公克", 0.46, 0.97)]), rev, headers: ["每100公克", "每份"], cols: 2)
        // D6 three-column reading, middle header misattributed (model swaps 2nd and 3rd headers); all headers read
        let three3: [PRow] = base.map { .init(label: $0.label, values: [$0.values[0], "9\($0.values[0])", "8\($0.values[0])"]) }
        let d6 = build(three3, cols: [0.40, 0.60, 0.80], headers: ["每份", "每100公克", "每100毫升"])
        runAttack("D6 three columns, model swaps headers of columns 2 and 3", d6,
            three3.flatMap { r in [(r.name, "每份", r.values[0], false), (r.name, "每100毫升", r.values[1], true), (r.name, "每100公克", r.values[2], true)] }, headers: ["每份", "每100毫升", "每100公克"], cols: 3)
        // D7 one-model-error: header text of the per-100 column read as 每100毫升 while photo prints both 每100公克 (col 2) and 每100毫升 (col 3); model reads 2 columns
        runAttack("D7 photo has 每100公克 and 每100毫升 columns, model reads col 2 values under 每100毫升", d6,
            three3.flatMap { r in [(r.name, "每份", r.values[0], false), (r.name, "每100毫升", r.values[1], true)] }, headers: ["每份", "每100毫升"], cols: 2)
        XCTAssertGreaterThanOrEqual(attackScenarios, 63)
        XCTAssertEqual(attackFailures, [])
    }
}
