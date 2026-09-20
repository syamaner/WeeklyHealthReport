import FoodLedgerDomain
import XCTest

final class BarcodeIdentityTests: XCTestCase {
    func testValidGTINAndNamespacedRetailerCodeCannotCollide() throws {
        let gtin = try BarcodeClassifier.classify(
            code: LedgerText("4006381333931"),
            symbology: .ean13
        )
        let retailer = try BarcodeClassifier.classify(
            code: LedgerText("4006381333931"),
            symbology: .code128,
            localNamespace: LedgerText("marks-and-spencer")
        )

        XCTAssertEqual(try gtin.lookupAlias.value, "barcode:gtin:04006381333931")
        XCTAssertEqual(
            try retailer.lookupAlias.value,
            "barcode:local:marks-and-spencer:4006381333931"
        )
        XCTAssertNotEqual(try gtin.lookupAlias, try retailer.lookupAlias)
    }

    func testUPCEExpandsToTheSameCanonicalGTINAsItsUPCAIdentity() throws {
        let upce = try BarcodeClassifier.classify(
            code: LedgerText("01234558"),
            symbology: .upce
        )
        let ean13 = try BarcodeClassifier.classify(
            code: LedgerText("0012345000058"),
            symbology: .ean13
        )
        XCTAssertEqual(try upce.lookupAlias.value, "barcode:gtin:00012345000058")
        XCTAssertEqual(try upce.lookupAlias, try ean13.lookupAlias)
    }

    func testMalformedGTINFailsClosed() throws {
        XCTAssertThrowsError(try BarcodeClassifier.classify(
            code: LedgerText("4006381333932"),
            symbology: .ean13
        )) { error in
            XCTAssertEqual(error as? BarcodeClassificationError, .invalidGTINCheckDigit)
        }
    }

    func testOpaqueRetailerCodeRequiresNamespace() throws {
        XCTAssertThrowsError(try BarcodeClassifier.classify(
            code: LedgerText("29161201"),
            symbology: .code128
        )) { error in
            XCTAssertEqual(error as? BarcodeClassificationError, .missingLocalNamespace)
        }
    }
}
