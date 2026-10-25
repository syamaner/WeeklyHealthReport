import CoreGraphics
import CoreText
@testable import FoodLabelPhotoCapture
import FoodLabelPhotoReading
import FoodLedgerApplication
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// The Vision locator adapter (docs/label-photo-ai-prefill-v1.md 6.1 and 12.1): the queries it asks
/// the pinned matcher, the records it keeps, and one end-to-end read of a synthetic Taiwan label
/// rendered at test time (no photo, no network).
final class VisionLabelValueLocatorTests: XCTestCase {
    typealias Cell = PastedLabelManifest.Candidate.Cell

    static func cell(_ row: String, _ nutrient: String, _ label: String, _ header: String, _ printed: String, _ decimal: String,
                     _ unit: String, _ canonical: String) -> Cell {
        Cell(rowID: row, parentRowID: nil, nutrient: nutrient, printedLabel: label, headerID: header, basis: header == "h1" ? "per_serving" : "per_100g",
             printedText: printed, comparator: "=", decimalText: decimal, unit: unit, canonicalUnit: canonical,
             servingConversion: header == "h1" ? "30公克" : "not_applicable")
    }

    static let rows: [(String, String, String, String, String)] = [
        ("energy_kcal", "熱量", "120大卡", "400大卡", "kcal"), ("protein", "蛋白質", "3.5公克", "11.7公克", "g"),
        ("fat", "脂肪", "4公克", "13.3公克", "g"), ("carbohydrate", "碳水化合物", "18公克", "60公克", "g"),
        ("sodium", "鈉", "85毫克", "283毫克", "mg"),
    ]

    static func candidate(replacing: [String: String] = [:]) -> PastedLabelManifest.Candidate {
        var cells: [Cell] = []
        for (nutrient, label, serving, per100, canonical) in rows {
            let unit = String(serving.drop { $0.isNumber || $0 == "." })
            for (header, text) in [("h1", serving), ("h2", per100)] {
                let printed = replacing[nutrient + "@" + header] ?? text
                cells.append(cell(nutrient, nutrient, label, header, printed, String(printed.prefix { $0.isNumber || $0 == "." }), unit, canonical))
            }
        }
        return PastedLabelManifest.Candidate(route: "C", inputSHA256: String(repeating: "a", count: 64), declined: false, declineReasons: [],
            wouldMarkReady: true, language: "zh-Hant",
            servingSize: .init(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"),
            servingsPerPack: .init(printedText: "本包裝含2份", decimalText: "2", approximate: false),
            headers: [.init(headerID: "h1", printedText: "每份", basis: "per_serving", servingConversion: "30公克"),
                      .init(headerID: "h2", printedText: "每100公克", basis: "per_100g", servingConversion: nil)],
            cells: cells, warnings: [])
    }

    // MARK: Queries and records (pure)

    func testQueriesCoverEveryCellAndServingLineWithHeaderBases() {
        let inputs = LabelPhotoLocatorQueries.inputs(Self.candidate())
        XCTAssertEqual(inputs.queries.count, 12)
        XCTAssertEqual(inputs.queries.first?.id, "energy_kcal@h1")
        XCTAssertEqual(inputs.queries.first?.rowLabel, "熱量")
        XCTAssertEqual(inputs.queries.first?.headerText, "每份")
        XCTAssertEqual(inputs.queries.suffix(2).map(\.id), ["serving_size", "servings_per_pack"])
        XCTAssertEqual(inputs.headers, ["每份", "每100公克"])
        XCTAssertEqual(inputs.headerBases, [.amount, .amount])
        XCTAssertEqual(inputs.columnCount, 2)
    }

    func testRecordsKeepARegionOnlyOnFoundValues() {
        let queries = LabelPhotoLocatorQueries.inputs(Self.candidate()).queries
        let box = LabelValueMatcher.Box(x: 0.123456, y: 0.5, width: 0.1, height: 0.05)
        let located = LabelValueMatcherTestSupport.locations(queries.map(\.id), found: ["energy_kcal@h1": box], ambiguous: ["fat@h1": box])
        let records = LabelPhotoLocatorQueries.records(queries, located: located)
        XCTAssertEqual(records.count, queries.count)
        XCTAssertEqual(records[0].status, .found)
        XCTAssertEqual(records[0].region, .init(x: "0.1235", y: "0.5", w: "0.1", h: "0.05"))
        let fat = records.first { $0.item == "fat@h1" }
        XCTAssertEqual(fat?.status, .ambiguous)
        XCTAssertNil(fat?.region)
        XCTAssertTrue(records.filter { $0.status != .found }.allSatisfy { $0.region == nil })
        XCTAssertTrue(records.compactMap(\.region).allSatisfy(\.isInsideUnitSquare))
    }

    // MARK: End to end on a synthetic rendered label

    static func renderedLabel() -> Data {
        let width = 1_000, height = 760
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("PingFangTC-Regular" as CFString, 34, nil)
        func draw(_ text: String, x: Double, top: Double) {
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)])
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: x, y: Double(height) - top)
            CTLineDraw(line, context)
        }
        draw("營養標示", x: 40, top: 60)
        draw("每一份量30公克", x: 40, top: 115)
        draw("本包裝含2份", x: 40, top: 170)
        draw("每份", x: 470, top: 240)
        draw("每100公克", x: 700, top: 240)
        for (index, row) in rows.enumerated() {
            let top = 310 + Double(index) * 80
            draw(row.1, x: 40, top: top)
            draw(row.2, x: 450, top: top)
            draw(row.3, x: 700, top: top)
        }
        let image = context.makeImage()!
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    func testASyntheticLabelIsLocatedAndAWrongValueIsNever() async throws {
        let prepared = try ImageIOLabelImagePreparer().prepare(Self.renderedLabel(), crop: .whole)
        let locations = try await VisionLabelValueLocator().locate(prepared, candidate: Self.candidate())
        XCTAssertEqual(locations.locatorVersion, LabelValueMatcher.version)
        XCTAssertEqual(locations.visionRevision, 3)
        XCTAssertEqual(locations.records.count, 12)
        XCTAssertTrue(locations.records.compactMap(\.region).allSatisfy(\.isInsideUnitSquare))
        let found = locations.records.filter { $0.status == .found }.map(\.item)
        XCTAssertGreaterThanOrEqual(found.count, 8, "found: \(found)")
        // A value misread by the model (121 for the printed 120) is never found.
        let misread = try await VisionLabelValueLocator().locate(prepared, candidate: Self.candidate(replacing: ["energy_kcal@h1": "121大卡"]))
        XCTAssertNotEqual(misread.records.first { $0.item == "energy_kcal@h1" }?.status, .found)
    }
}

/// Builds matcher results for the record mapping test (the matcher's own initialiser is internal).
enum LabelValueMatcherTestSupport {
    static func locations(_ ids: [String], found: [String: LabelValueMatcher.Box], ambiguous: [String: LabelValueMatcher.Box])
        -> [LabelValueMatcher.Location] {
        // Run the matcher on lines that make exactly those statuses is not needed here: the mapping
        // only reads id, status and region, so use the public matcher on synthetic serving lines.
        ids.map { id in
            let lines = found[id].map { [LabelValueMatcher.Line(text: "X" + id, box: $0)] } ?? []
            let result = LabelValueMatcher.locate([.init(id: id, rowLabel: nil, headerText: nil, printedText: "X" + id)], lines: lines + (ambiguous[id].map {
                [LabelValueMatcher.Line(text: "X" + id, box: $0), LabelValueMatcher.Line(text: "X" + id, box: $0)]
            } ?? []), headers: [], rowLabels: [], columnCount: 1) { _, _ in nil }
            return result[0]
        }
    }
}
