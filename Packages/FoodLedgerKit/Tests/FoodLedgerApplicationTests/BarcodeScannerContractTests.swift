import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

@MainActor
final class BarcodeScannerContractTests: XCTestCase {
    func testBothScannerImplementationsPreserveTheSameCaptureContract() async throws {
        for scanner in scanners() {
            let authorization = await scanner.authorization()
            XCTAssertEqual(authorization, .authorised)
            let scan = try await scanner.scan()
            XCTAssertEqual(scan.code.value, "4006381333931")
            XCTAssertEqual(scan.originalSymbology.value, "EAN-13")
            XCTAssertEqual(scan.capturedAt, Self.date)
            XCTAssertEqual(scan.locale.value, "en_GB")
            XCTAssertFalse(scan.captureMethodVersion.value.isEmpty)
        }
    }

    func testPermissionDeniedNeverAttemptsCaptureAndReturnsAccessibleGuidance() async throws {
        let scanner = FixtureScanner(authorization: .denied, method: "fixture-a")
        let outcome = try await BarcodeCaptureCoordinator(
            search: EmptySearch(),
            ids: FixedIDs()
        ).capture(using: scanner)

        guard case let .permissionGuidance(guidance) = outcome else {
            return XCTFail("Expected permission guidance")
        }
        XCTAssertEqual(scanner.scanCalls, 0)
        XCTAssertEqual(guidance.genericSearchTitle, "Use generic search")
        XCTAssertTrue(guidance.message.contains("Nothing has been captured"))
    }

    private func scanners() -> [any BarcodeScanning] {
        [
            FixtureScanner(authorization: .authorised, method: "visionkit"),
            FixtureScanner(authorization: .authorised, method: "avfoundation")
        ]
    }

    fileprivate static let date = Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
private final class FixtureScanner: BarcodeScanning {
    let status: BarcodeCameraAuthorization
    let method: String
    private(set) var scanCalls = 0

    init(authorization: BarcodeCameraAuthorization, method: String) {
        status = authorization
        self.method = method
    }

    func authorization() async -> BarcodeCameraAuthorization { status }

    func scan() async throws -> BarcodeScan {
        scanCalls += 1
        return BarcodeScan(
            code: try LedgerText("4006381333931"),
            symbology: .ean13,
            originalSymbology: try LedgerText("EAN-13"),
            capturedAt: BarcodeScannerContractTests.date,
            locale: try LedgerText("en_GB"),
            captureMethod: try LedgerText(method),
            captureMethodVersion: try LedgerText("\(method)-v1")
        )
    }
}

private struct EmptySearch: BarcodeLibrarySearching {
    func matches(alias: LedgerText) throws -> [BarcodeLibraryMatch] { [] }
}

private struct FixedIDs: LedgerIDGenerating {
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        try LedgerID("00000000-0000-0000-0000-000000000999")
    }
}
