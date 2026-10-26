@testable import FoodLabelPhotoCapture
import FoodLabelPhotoReading
import FoodLedgerApplication
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// The fake route used by the simulator journeys (docs/label-photo-ai-prefill-v1.md 14, 17.19):
/// it never touches the network, answers the catalogue check, and its scripted answer for the
/// synthetic label leaves exactly the two misread values not found on the photo.
final class ScriptedLabelPhotoRouteTests: XCTestCase {
    /// The synthetic label's lines drawn as the UI renderer draws them (same layout, Core Text).
    static func rendered(_ lines: [[String]]) -> Data {
        let width = 900, height = 120 + lines.count * 90
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("PingFangTC-Regular" as CFString, 44, nil)
        let columns: [Double] = [60, 400, 650]
        for (index, line) in lines.enumerated() {
            for (column, text) in line.enumerated() where column < columns.count && !text.isEmpty {
                let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)])
                context.textPosition = CGPoint(x: columns[column], y: Double(height) - 60 - Double(index) * 90 - 44)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
        }
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    func testTheScriptedAnswerLeavesExactlyTheTwoMisreadValuesNotFound() async throws {
        let prepared = try ImageIOLabelImagePreparer().prepare(Self.rendered(LabelPhotoSyntheticLabel.lines), crop: .whole)
        let reading = try XCTUnwrap(LabelPhotoReader().reading(wireText: LabelPhotoSyntheticLabel.wireText, imageSHA256: prepared.sha256))
        XCTAssertTrue(reading.isUsable, "\(reading.hardDeclines)")
        let locations = try await VisionLabelValueLocator().locate(prepared, candidate: reading.candidate)
        let notFound = locations.records.filter { $0.status != .found }.map(\.item)
        XCTAssertEqual(Set(notFound), ["protein@h2", "sodium@h1"], "\(locations.records.map { "\($0.item)=\($0.status)" })")
    }

    func testEveryScenarioAnswersWithoutTheNetwork() async throws {
        for scenario in ScriptedLabelPhotoTransport.Scenario.allCases where scenario != .slow {
            let transport = ScriptedLabelPhotoTransport(scenario: scenario)
            let check = try await OpenRouterLabelRouteChecker(transport: transport, clock: FixedClock()).check(LabelPhotoRoute.current)
            XCTAssertEqual(check.zeroDataRetention, scenario != .routeUnavailable, "\(scenario)")
        }
    }

    struct FixedClock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_792_900_000) } }
}
