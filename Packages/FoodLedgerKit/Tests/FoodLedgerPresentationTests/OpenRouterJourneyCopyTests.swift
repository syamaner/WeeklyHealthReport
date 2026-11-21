import FoodLedgerApplication
@testable import FoodLedgerPresentation
import Foundation
import XCTest

/// docs/openrouter-single-consent-v1-amendment.md O1.6 test 10: no string O1.4 removes appears in
/// the journey presentation sources, and the blocked row's copy is exact.
final class OpenRouterJourneyCopyTests: XCTestCase {
    static let removed = [
        "Read label with AI sends this cropped photo to OpenRouter",
        "Send label photos to OpenRouter?",
        "Uses your OpenRouter key and credit.",
        "The part you crop is sent to OpenRouter to be read. Nothing else is sent.",
        "Only your food terms, the market set in Settings and the captured page text are sent to OpenRouter",
        "OpenRouter finds public food sources and reads their nutrition into proposals for you to review.",
        "Validation sends only the key to OpenRouter.",
        "Web lookup needs your OpenRouter key.",
        "Add or revalidate your OpenRouter key first.",
        "Add or validate key",
        "Send photo",
        "Label photo reading is off. Turn on Read label photos with AI",
        "OpenRouter rejected this key. Add or revalidate a key.",
    ]

    func testNoRemovedStringAppearsInTheJourneySources() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FoodLedgerPresentation")
        for name in ["LabelPhotoText.swift", "LabelPhotoScreenView.swift", "LabelPhotoScreenModel.swift", "NutritionLabelEntryText.swift",
                     "GenericFoodProposalReviewView.swift", "FoodWebDiscoveryViewModel.swift"] {
            let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            for string in Self.removed { XCTAssertFalse(text.contains(string), "\(name) still holds: \(string)") }
        }
    }

    func testTheBlockedRowCopyAndOrder() {
        XCTAssertEqual(OpenRouterBlockedReason.allCases.map(OpenRouterBlockedText.text), [
            "Turn on OpenRouter in Settings to use this.",
            "Add your OpenRouter key in Settings.",
            "Validate your OpenRouter key in Settings.",
        ])
        XCTAssertEqual(OpenRouterBlockedText.link, "OpenRouter settings")
        XCTAssertEqual(NutritionLabelEntryText.photoFooter, "Taiwan labels only.")
        XCTAssertEqual(OpenRouterFoodKeyView.keychainLine, "Your key stays in this device's Keychain.")
        XCTAssertEqual(OpenRouterFoodKeyView.howTheAppUsesOpenRouter, "How the app uses OpenRouter")
    }
}
