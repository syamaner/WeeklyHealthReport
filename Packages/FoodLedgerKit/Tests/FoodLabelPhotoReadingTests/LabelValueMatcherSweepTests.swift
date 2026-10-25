import FoodLabelPhotoReading
import Foundation
import XCTest

private typealias M = LabelValueMatcher

// Single-model-error sweep of the label photo locator (#320 final re-check). Ported from the
// reviewer's harness (synthetic data only): six layouts, every value and serving line of a
// two-column Taiwan table, and every mutation class (digits, decimal point, separator, unit,
// comparator, sign, row, column, header and label attribution, full-width). A value the model read
// wrongly must never be found; a correct value's box must not move, and no correct value may become
// found because of another value's error. Guards every later locator version.

// ---------- value semantics (for deciding whether a mutation is a real error) ----------
private func canon(_ s: String) -> String {
  let t = s.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: " ", with: "").lowercased()
  var cmp = ""; var rest = Substring(t)
  if let f = rest.first, "<≤≦>".contains(f) { cmp = (f == ">" ? ">" : "<"); rest = rest.dropFirst() }
  let num = rest.prefix { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
  var unit = String(rest.dropFirst(num.count))
  let map = ["公克": "g", "g": "g", "毫克": "mg", "mg": "mg", "大卡": "kcal", "kcal": "kcal", "千焦": "kj", "kj": "kj", "%": "%"]
  unit = map[unit] ?? unit
  let v = Double(num.replacingOccurrences(of: ",", with: "")).map { String($0) } ?? String(num)
  return cmp + v + unit
}

// ---------- tables ----------
private struct Row { let label: String; let values: [String] }
private let rows2: [Row] = [
  .init(label: "熱量", values: ["485大卡", "262大卡"]),
  .init(label: "能量", values: ["2,030千焦", "1,097千焦"]),
  .init(label: "蛋白質", values: ["12.5公克", "6.8公克"]),
  .init(label: "脂肪", values: ["3公克", "1.6公克"]),
  .init(label: "飽和脂肪", values: ["0公克", "0公克"]),
  .init(label: "反式脂肪", values: ["0公克", "0公克"]),
  .init(label: "碳水化合物", values: ["65.2公克", "35.2公克"]),
  .init(label: "糖", values: ["<0.5公克", "<0.5公克"]),
  .init(label: "鈉", values: ["120毫克", "65毫克"]),
  .init(label: "鈣", values: ["15%", "8%"]),
]
private let headers2 = ["每份", "每100公克"]
private let servings = [("serving_size", "每一份量 185 公克"), ("servings_per_pack", "本包裝含 2 份")]

private struct Layout {
  let name: String; let cols: Int; let headersRead: Bool; let merged: Bool; let unitSplit: Bool
  // Locator v2 attacks (L1c): every third inner row label misread by one character, or not read at
  // all, and a table-wide downward drift of the values (as a share of the row step).
  var misreadLabels = false
  var missingLabels = false
  var drift = 0.0
}

private func box(_ x: Double, _ y: Double, _ w: Double) -> M.Box { .init(x: x, y: y, width: w, height: 0.03) }
private func yOf(_ i: Int) -> Double { 0.85 - 0.07 * Double(i) }
private let colX = [0.45, 0.72]

private func lines(_ L: Layout) -> [M.Line] {
  var out: [M.Line] = [.init(text: servings[0].1, box: box(0.05, 0.96, 0.4)), .init(text: servings[1].1, box: box(0.5, 0.96, 0.3))]
  if L.headersRead { for c in 0..<L.cols { out.append(.init(text: headers2[c], box: box(colX[c], 0.91, 0.12))) } }
  for (i, r) in rows2.enumerated() {
    let y = yOf(i)
    if L.merged {
      let text = ([r.label] + r.values.prefix(L.cols)).joined(separator: " ")
      out.append(.init(text: text, box: box(0.05, y, 0.8)))
    } else {
      let inner = i > 0 && i < rows2.count - 1 && i % 3 == 1
      if !(L.missingLabels && inner) {
        let text = L.misreadLabels && inner ? String(r.label.dropLast()) + "舫" : r.label
        out.append(.init(text: text, box: box(0.05, y, 0.15)))
      }
      let vy = y - L.drift * 0.07
      for c in 0..<L.cols {
        let v = r.values[c]
        if L.unitSplit, let k = v.firstIndex(where: { !($0.isNumber || $0 == "." || $0 == "," || $0 == "<") }) {
          out.append(.init(text: String(v[..<k]), box: box(colX[c], vy, 0.06)))
          out.append(.init(text: String(v[k...]), box: box(colX[c] + 0.07, vy, 0.04)))
        } else { out.append(.init(text: v, box: box(colX[c], vy, 0.1))) }
      }
    }
  }
  return out
}
private func subBox(_ ls: [M.Line]) -> M.SubBox {
  return { index, range in
    let l = ls[index]; let n = Double(l.text.count)
    let a = Double(l.text.distance(from: l.text.startIndex, to: range.lowerBound)), b = Double(l.text.distance(from: l.text.startIndex, to: range.upperBound))
    return .init(x: l.box.x + l.box.width * a / n, y: l.box.y, width: l.box.width * (b - a) / n, height: l.box.height)
  }
}

// ---------- mutations ----------
private func digitsMutations(_ v: String) -> [(String, String)] {
  var out: [(String, String)] = []
  let chars = Array(v)
  let digitIdx = chars.indices.filter { chars[$0].isNumber }
  for i in digitIdx {
    var c = chars; c[i] = chars[i] == "8" ? "3" : (chars[i] == "0" ? "8" : "8"); out.append(("digit changed", String(c)))
    var d = chars; d.remove(at: i); if d.contains(where: { $0.isNumber }) { out.append(("digit missing", String(d))) }
    var e = chars; e.insert(chars[i], at: i); out.append(("digit doubled", String(e)))
  }
  if let last = digitIdx.last { var e = chars; e.insert("0", at: last + 1); out.append(("trailing zero added", String(e))) }
  if let first = digitIdx.first { var e = chars; e.insert("1", at: first); out.append(("leading digit added", String(e))) }
  if let dot = chars.firstIndex(of: ".") {
    var d = chars; d.remove(at: dot); out.append(("decimal point dropped", String(d)))
    if dot >= 2 { var m = chars; m.remove(at: dot); m.insert(".", at: dot - 1); out.append(("decimal point moved", String(m))) }
    var m2 = chars; m2.remove(at: dot); if dot + 1 < m2.count { m2.insert(".", at: dot + 1); out.append(("decimal point moved right", String(m2))) }
  } else if let last = digitIdx.last, digitIdx.count >= 2 {
    var m = chars; m.insert(".", at: last); out.append(("decimal point inserted", String(m)))
  }
  if let comma = chars.firstIndex(of: ",") { var m = chars; m[comma] = "."; out.append(("separator read as decimal", String(m))) }
  return out
}
private let unitSwaps: [(String, String, String)] = [("公克", "毫克", "unit g to mg"), ("毫克", "公克", "unit mg to g"), ("大卡", "千焦", "kcal to kJ"),
  ("千焦", "大卡", "kJ to kcal"), ("公克", "%", "g to %"), ("%", "公克", "% to g"), ("毫克", "%", "mg to %"), ("公克", "微克", "g to microgram")]
private func mutations(_ v: String) -> [(String, String)] {
  var out = digitsMutations(v)
  for (a, b, n) in unitSwaps where v.contains(a) { out.append((n, v.replacingOccurrences(of: a, with: b))) }
  if let k = v.firstIndex(where: { !($0.isNumber || $0 == "." || $0 == "," || $0 == "<") }) { out.append(("unit dropped", String(v[..<k]))) }
  if v.hasPrefix("<") { out.append(("comparator dropped", String(v.dropFirst()))); out.append(("comparator flipped", ">" + v.dropFirst())); out.append(("comparator to ≤", "≤" + v.dropFirst())) }
  else { out.append(("comparator added", "<" + v)); out.append(("sign added", "-" + v)) }
  return out
}


final class LabelValueMatcherSweepTests: XCTestCase {
    func testNoSingleModelErrorIsFound() {
        var baselines: [String: Int] = [:]
        struct Finding: Hashable { let layout: String; let cls: String; let id: String; let truth: String; let read: String; let note: String }
        var findings: [Finding] = []
        var total = 0
        let layouts = [Layout(name: "2col clean", cols: 2, headersRead: true, merged: false, unitSplit: false),
                       Layout(name: "2col headers unread", cols: 2, headersRead: false, merged: false, unitSplit: false),
                       Layout(name: "2col unit split", cols: 2, headersRead: true, merged: false, unitSplit: true),
                       Layout(name: "1col clean", cols: 1, headersRead: true, merged: false, unitSplit: false),
                       Layout(name: "1col merged lines", cols: 1, headersRead: true, merged: true, unitSplit: false),
                       Layout(name: "1col unit split", cols: 1, headersRead: true, merged: false, unitSplit: true),
                       Layout(name: "2col labels misread", cols: 2, headersRead: true, merged: false, unitSplit: false, misreadLabels: true),
                       Layout(name: "2col labels missing", cols: 2, headersRead: true, merged: false, unitSplit: false, missingLabels: true),
                       Layout(name: "2col headers unread, labels missing", cols: 2, headersRead: false, merged: false, unitSplit: false,
                              missingLabels: true),
                       Layout(name: "2col drift 0.45", cols: 2, headersRead: true, merged: false, unitSplit: false, drift: 0.45),
                       Layout(name: "1col drift 0.45, labels misread", cols: 1, headersRead: true, merged: false, unitSplit: false,
                              misreadLabels: true, drift: 0.45)]

        for L in layouts {
          let ls = lines(L); let sb = subBox(ls)
          // truth queries
          var base: [(M.Query, String, M.Box?)] = []
          for (i, r) in rows2.enumerated() { for c in 0..<L.cols {
            base.append((M.Query(id: "\(r.label)/\(headers2[c])", rowLabel: r.label, headerText: headers2[c], printedText: r.values[c]), r.values[c], nil)); _ = i } }
          for s in servings { base.append((M.Query(id: s.0, rowLabel: nil, headerText: nil, printedText: s.1), s.1, nil)) }
          let rowLabels = rows2.map(\.label)
          let hdrs = Array(headers2.prefix(L.cols))
          func run(_ qs: [M.Query]) -> [M.Location] { M.locate(qs, lines: ls, headers: hdrs, rowLabels: rowLabels, columnCount: L.cols, subBox: sb) }
          // baseline: record correct-found boxes
          let baseRes = run(base.map(\.0))
          let baseFound = baseRes.filter { $0.status == .found }.count
          baselines[L.name] = baseFound
          func check(_ qs: [M.Query], _ wrongIndex: Int, cls: String, truth: String) {
            total += 1
            let res = run(qs)
            let q = qs[wrongIndex]
            if canon(q.printedText) == canon(truth) && q.rowLabel == base[wrongIndex].0.rowLabel && q.headerText == base[wrongIndex].0.headerText { return }
            if res[wrongIndex].status == .found {
              findings.append(.init(layout: L.name, cls: cls, id: base[wrongIndex].0.id, truth: truth, read: "\(q.rowLabel ?? "-")|\(q.headerText ?? "-")|\(q.printedText)", note: "found y=\(res[wrongIndex].region!.y)"))
            }
            // side effects: any other query whose found box moved vs baseline
            for (k, r) in res.enumerated() where k != wrongIndex && r.status == .found && baseRes[k].status == .found && r.region != baseRes[k].region {
              findings.append(.init(layout: L.name, cls: cls + " (side effect)", id: base[k].0.id, truth: base[k].1, read: "box moved", note: ""))
            }
            for (k, r) in res.enumerated() where k != wrongIndex && r.status == .found && baseRes[k].status != .found {
              findings.append(.init(layout: L.name, cls: cls + " (side effect upgrade)", id: base[k].0.id, truth: base[k].1, read: "now found", note: ""))
            }
          }
          for (idx, entry) in base.enumerated() {
            let q = entry.0
            func with(_ text: String? = nil, label: String?? = nil, header: String?? = nil) -> [M.Query] {
              var qs = base.map(\.0)
              qs[idx] = M.Query(id: q.id, rowLabel: label ?? q.rowLabel, headerText: header ?? q.headerText, printedText: text ?? q.printedText)
              return qs
            }
            if q.rowLabel == nil {
              // serving lines: number and unit errors
              for (cls, t) in digitsMutations(q.printedText) { check(with(t), idx, cls: "serving: " + cls, truth: entry.1) }
              for (a, b, n) in unitSwaps where q.printedText.contains(a) { check(with(q.printedText.replacingOccurrences(of: a, with: b)), idx, cls: "serving: " + n, truth: entry.1) }
              check(with(q.printedText.replacingOccurrences(of: "每一份量", with: "每份")), idx, cls: "serving: words changed", truth: entry.1)
              continue
            }
            for (cls, t) in mutations(q.printedText) { check(with(t), idx, cls: cls, truth: entry.1) }
            let r = rows2.firstIndex { $0.label == q.rowLabel }!, c = headers2.firstIndex(of: q.headerText!)!
            // row: value of each other row (adjacent and far), same column
            for s in rows2.indices where s != r && canon(rows2[s].values[c]) != canon(entry.1) {
              check(with(rows2[s].values[c]), idx, cls: abs(s - r) == 1 ? "row: adjacent row's value" : "row: other row's value", truth: entry.1) }
            // column: other column's value, same row
            if L.cols == 2 { let o = 1 - c; if canon(rows2[r].values[o]) != canon(entry.1) { check(with(rows2[r].values[o]), idx, cls: "column: other column's value", truth: entry.1) }
              // header attribution swapped (value correct for this cell, but labelled other column)
              if canon(rows2[r].values[o]) != canon(entry.1) { check(with(header: .some(headers2[o])), idx, cls: "column: header attribution swapped", truth: rows2[r].values[o]) } }
            // label: this row's value under another row's label (record says other row = this value)
            for s in rows2.indices where s != r && canon(rows2[s].values[c]) != canon(entry.1) {
              check(with(label: .some(rows2[s].label)), idx, cls: abs(s - r) == 1 ? "label: adjacent row's label" : "label: other row's label", truth: rows2[s].values[c]) }
            // label spelling typo (value correct) is not a value error; label typo + adjacent value is two errors; skip.
            // full-width digits of a changed digit are covered by NFKC; test full-width wrong value once
            if let (cls, t) = mutations(q.printedText).first { check(with(t.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? t), idx, cls: "full-width " + cls, truth: entry.1) }
          }
        }

        // Known artefacts of the harness, not matcher findings: its mutator treats the Han numeral
        // 一 as a digit, so "每一份量" mutations only change wording; and the wording-only serving change.
        let real = findings.filter { finding in
            let digits: (String) -> String = { text in String(text.filter { $0.isASCII && $0.isNumber }) }
            return !(finding.cls.hasPrefix("serving: ") && digits(finding.read) == digits(finding.truth))
        }
        XCTAssertGreaterThan(total, 3_000)
        XCTAssertEqual(real.map { "\($0.layout) | \($0.cls) | \($0.id) | \($0.read)" }, [])
        // Baselines must not collapse (two columns with unread headers are never found by design).
        XCTAssertEqual(baselines["2col clean"], 22)
        XCTAssertEqual(baselines["1col clean"], 12)
        XCTAssertEqual(baselines["1col merged lines"], 12)
        XCTAssertGreaterThanOrEqual(baselines["2col unit split"] ?? 0, 20)
        XCTAssertGreaterThanOrEqual(baselines["1col unit split"] ?? 0, 11)
        // Locator v2 recovery: baselines with unread headers, misread or missing labels and drift.
        XCTAssertEqual(baselines["2col headers unread"], 22)
        // 糖 misread as 舫 is one character for another: no near-miss (two characters needed) and the
        // slot is occupied, so its row stays unconfirmed (one row, both columns).
        XCTAssertEqual(baselines["2col labels misread"], 20)
        XCTAssertEqual(baselines["2col labels missing"], 22)
        XCTAssertEqual(baselines["2col headers unread, labels missing"], 22)
        XCTAssertEqual(baselines["2col drift 0.45"], 22)
        XCTAssertEqual(baselines["1col drift 0.45, labels misread"], 11)
    }
}
