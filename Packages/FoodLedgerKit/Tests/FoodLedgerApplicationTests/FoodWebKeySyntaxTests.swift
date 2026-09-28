import FoodLedgerApplication
import XCTest

final class FoodWebKeySyntaxTests: XCTestCase {
    func testVisiblePunctuationPassesLocalValidation() {
        XCTAssertTrue(FoodWebKeySyntax.isValid("synthetic.key:with+visible=punctuation"))
        XCTAssertTrue(FoodWebKeySyntax.isValid(String(repeating: "a", count: 20)))
        XCTAssertTrue(FoodWebKeySyntax.isValid(String(repeating: "a", count: 512)))
    }

    func testWhitespaceControlsAndNonASCIIAreNotHeaderSafe() {
        for key in [
            String(repeating: "a", count: 19),
            String(repeating: "a", count: 513),
            "synthetic key with spaces",
            "synthetic-key-with-newline\n",
            "synthetic-key-with-return\r",
            "synthetic-key-with-tab\t",
            "synthetic-key-with-delete\u{7f}",
            "synthetic-key-with-café"
        ] {
            XCTAssertFalse(FoodWebKeySyntax.isValid(key))
        }
    }
}
