import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Nutrition label entry (#454, docs/nutrition-label-entry-v1.md section 5 and 6.2 test 9): the
/// combined entry changes no record. The pasted-label manifest (its `pasted_text`) and the label
/// photo manifest (`label-photo-ai-v1`) decode and re-encode unchanged, at their pinned bytes.
final class NutritionLabelEntryCompatibilityTests: XCTestCase {
    func testThePastedAndPhotoManifestsDecodeAndReencodeUnchanged() throws {
        let pasted = try PastedLabelFixtures.data(PastedLabelFixtures.manifest(parserVersion: PastedLabelSource.parserVersionV3))
        XCTAssertEqual(try LedgerFixtures.digester.sha256(pasted).value, PastedLabelReaderV3ContractTests.parserV3ManifestGoldenSHA256)
        let decodedPasted = try XCTUnwrap(PastedLabelManifest.decode(pasted))
        XCTAssertEqual(try PastedLabelFixtures.data(decodedPasted), pasted)
        let pastedText = String(decoding: pasted, as: UTF8.self)
        XCTAssertTrue(pastedText.contains(#""version":"pasted-nutrition-label-v1""#))
        XCTAssertTrue(pastedText.contains(#""pasted_text":"#), "the pasted text stays in the manifest")
        XCTAssertEqual(PastedLabelSource.parserVersion, PastedLabelSource.parserVersionV3, "reader v3 is unchanged")

        let photo = try LedgerFixtures.encoder.encode(try LabelPhotoFixtures.manifest())
        XCTAssertEqual(try LabelPhotoFixtures.sha(photo), LabelPhotoContractTests.manifestGoldenSHA256)
        let decodedPhoto = try XCTUnwrap(LabelPhotoManifest.decode(photo))
        XCTAssertEqual(try LedgerFixtures.encoder.encode(decodedPhoto), photo)
        XCTAssertTrue(String(decoding: photo, as: UTF8.self).contains(#""version":"label-photo-ai-v1""#))
    }
}
