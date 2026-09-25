import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import XCTest

@MainActor
final class BarcodeCapturePresentationTests: XCTestCase {
    func testDeniedAndUnavailableDoNotInvokeScanner() async throws {
        for authorization in [BarcodeCameraAuthorization.denied, .unavailable] {
            let model = makeModel()
            let scanner = TestScanner(authorization: authorization)
            await model.capture(using: scanner)
            guard case let .result(.permissionGuidance(guidance)) = model.phase else {
                return XCTFail("Expected permission guidance")
            }
            XCTAssertEqual(guidance.title, authorization == .denied ? "Camera access is off" : "Barcode camera unavailable")
            XCTAssertEqual(scanner.scanCalls, 0)
        }
    }

    func testMissRetainsBarcodeAndMalformedScanAlsoFallsBack() async throws {
        for code in ["4006381333931", "4006381333932"] {
            let model = makeModel()
            let scanner = TestScanner(code: code)
            await model.capture(using: scanner)
            guard case let .result(.fallback(route)) = model.phase else { return XCTFail("Expected fallback") }
            XCTAssertEqual(route.evidence.originalPayload, .barcode(value: try LedgerText(code), symbology: try LedgerText("ean13")))
            model.cancel()
            XCTAssertEqual(model.phase, .result(.fallback(route)))
        }
    }

    func testRuntimeFailureCanBeRetried() async {
        let model = makeModel()
        let scanner = TestScanner(fails: true)
        await model.capture(using: scanner)
        XCTAssertEqual(model.phase, .failed)
        scanner.fails = false
        await model.capture(using: scanner)
        guard case .result(.fallback) = model.phase else { return XCTFail("Retry did not recover") }
    }

    func testCancelIgnoresLateCompletionAndRejectsOverlappingCapture() async {
        let model = makeModel()
        let slow = TestScanner(suspends: true)
        let task = Task { await model.capture(using: slow) }
        await slow.waitUntilScanning()
        let other = TestScanner()
        await model.capture(using: other)
        XCTAssertEqual(other.authorizationCalls, 0)
        model.cancel()
        slow.complete()
        await task.value
        XCTAssertEqual(model.phase, .idle)
        await model.capture(using: other)
        guard case .result(.fallback) = model.phase else { return XCTFail("Expected a new attempt") }
    }

    func testTaskCancellationDoesNotLeaveCapturingState() async {
        let model = makeModel()
        let scanner = TestScanner(suspends: true)
        let task = Task { await model.capture(using: scanner) }
        await scanner.waitUntilScanning()
        task.cancel()
        scanner.complete()
        await task.value
        XCTAssertEqual(model.phase, .idle)
        model.showUnavailable()
        XCTAssertEqual(model.phase, .result(.permissionGuidance(BarcodePermissionGuidance(unavailable: true))))
    }

    private func makeModel() -> BarcodeCaptureViewModel {
        BarcodeCaptureViewModel(coordinator: BarcodeCaptureCoordinator(search: EmptyBarcodeSearch(), ids: BarcodeIDs()))
    }
}

private struct EmptyBarcodeSearch: BarcodeLibrarySearching {
    func matches(alias: LedgerText) throws -> [BarcodeLibraryMatch] { [] }
}

private final class BarcodeIDs: LedgerIDGenerating, @unchecked Sendable {
    private var counter = 0
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        counter += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", counter))
    }
}

@MainActor
private final class TestScanner: BarcodeScanning {
    let permission: BarcodeCameraAuthorization
    let code: String
    var fails: Bool
    let suspends: Bool
    var authorizationCalls = 0
    var scanCalls = 0
    private var waiter: CheckedContinuation<Void, Never>?
    private var scanContinuation: CheckedContinuation<Void, Never>?

    init(authorization: BarcodeCameraAuthorization = .authorised, code: String = "4006381333931", fails: Bool = false, suspends: Bool = false) {
        permission = authorization
        self.code = code
        self.fails = fails
        self.suspends = suspends
    }

    func authorization() async -> BarcodeCameraAuthorization { authorizationCalls += 1; return permission }
    func scan() async throws -> BarcodeScan {
        scanCalls += 1
        if suspends {
            await withCheckedContinuation { continuation in
                scanContinuation = continuation
                waiter?.resume()
                waiter = nil
            }
        }
        if fails { throw CocoaError(.featureUnsupported) }
        return try BarcodeScan(
            code: LedgerText(code), symbology: .ean13, originalSymbology: LedgerText("ean13"),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic"), captureMethodVersion: LedgerText("1")
        )
    }
    func waitUntilScanning() async {
        guard scanContinuation == nil else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func complete() { scanContinuation?.resume(); scanContinuation = nil }
}
