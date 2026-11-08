import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
@testable import PastedLabelAITextEvalHarness
import XCTest

/// `send` refuses the sealed held-out set (T7) at the point of sending, per file: a text path that
/// names `uk-english-v2`, as given or after resolving symbolic links, and, with a data directory,
/// a text that resolves outside it. A refusal reserves nothing, creates no cache and sends nothing,
/// over the fake transport and over an injected (live-shaped) transport. The `uk-english-v2`
/// directories here are temporary stand-ins, never the sealed set.
final class SealedTextPathTests: XCTestCase {
    var root: URL!
    var data: URL { root.appendingPathComponent("data") }
    var sealed: URL { root.appendingPathComponent("held/uk-english-v2") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("eval-sealed-\(UUID().uuidString)", isDirectory: true)
        try Fixtures.write(to: root)
        let fm = FileManager.default
        for dir in [data.appendingPathComponent("texts"), sealed.appendingPathComponent("texts"), root.appendingPathComponent("outside")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data(Fixtures.ukText.utf8).write(to: data.appendingPathComponent("texts/uk-synthetic-01.txt"))
        try Data(Fixtures.ukText.utf8).write(to: sealed.appendingPathComponent("texts/held-01.txt"))
        try Data(Fixtures.ukText.utf8).write(to: root.appendingPathComponent("outside/other.txt"))
        // Links inside the approved data directory: into the stand-in sealed set, and to a file outside.
        try fm.createSymbolicLink(at: data.appendingPathComponent("texts/linked-sealed.txt"),
                                  withDestinationURL: sealed.appendingPathComponent("texts/held-01.txt"))
        try fm.createSymbolicLink(at: data.appendingPathComponent("texts/linked-outside.txt"),
                                  withDestinationURL: root.appendingPathComponent("outside/other.txt"))
        try fm.createSymbolicLink(at: data.appendingPathComponent("texts/linked-inside.txt"),
                                  withDestinationURL: data.appendingPathComponent("texts/uk-synthetic-01.txt"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    enum Mode: CaseIterable { case fake, live }

    func options(_ text: URL, data: URL?, mode: Mode, transport: ScriptedTransport) throws -> SendCommand.Options {
        let connection: SendCommand.Connection = switch mode {
        case .fake: .fake(directory: root.appendingPathComponent("fake"))
        case .live: .transport(transport, keys: try EnvironmentKey(environment: [EnvironmentKey.variable: LiveModeTests.key]))
        }
        return SendCommand.Options(labelID: "uk-synthetic-01", textURL: text, route: PastedLabelAITextRoute.gemini4ArgonVertexUS, cell: "cell-a",
                                   ledgerURL: root.appendingPathComponent("ledger.json"), cacheDirectory: root.appendingPathComponent("cache"),
                                   connection: connection, retry: .single, dataDirectory: data)
    }

    /// Runs `send` and asserts it threw `expected` with nothing reserved, cached or sent.
    func assertRefused(_ text: URL, data: URL?, _ expected: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        for mode in Mode.allCases {
            let transport = ScriptedTransport([LiveModeTests.answer])
            do {
                _ = try await SendCommand.run(options(text, data: data, mode: mode, transport: transport))
                XCTFail("\(mode) \(text.lastPathComponent) was not refused", file: file, line: line)
            } catch let failure as SendCommand.Failure {
                XCTAssertEqual("\(failure)".components(separatedBy: ";").first, expected, "\(mode)", file: file, line: line)
            }
            XCTAssertTrue(transport.requests.isEmpty, "\(mode): nothing sent, not even the catalogue check", file: file, line: line)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.json").path), "\(mode): nothing reserved",
                           file: file, line: line)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cache").path), "\(mode): no cache", file: file, line: line)
        }
    }

    static let sealedRefusal = "the sealed held-out set (uk-english-v2) is never used by a tuning run (T7)"
    static let outsideRefusal = "the text file resolves outside the data directory"

    func testATextPathNamingTheSealedSetIsRefusedAsGiven() async throws {
        try await assertRefused(sealed.appendingPathComponent("texts/held-01.txt"), data: nil, Self.sealedRefusal)
        try await assertRefused(sealed.appendingPathComponent("texts/held-01.txt"), data: sealed, Self.sealedRefusal)
    }

    func testALinkIntoTheSealedSetIsRefusedWithOrWithoutADataDirectory() async throws {
        try await assertRefused(data.appendingPathComponent("texts/linked-sealed.txt"), data: nil, Self.sealedRefusal)
        try await assertRefused(data.appendingPathComponent("texts/linked-sealed.txt"), data: data, Self.sealedRefusal)
    }

    func testADataDirectoryLinkedToTheSealedSetIsRefused() async throws {
        let link = root.appendingPathComponent("innocent")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sealed)
        try await assertRefused(link.appendingPathComponent("texts/held-01.txt"), data: link, Self.sealedRefusal)
    }

    func testALinkOutsideTheDataDirectoryIsRefused() async throws {
        try await assertRefused(data.appendingPathComponent("texts/linked-outside.txt"), data: data, Self.outsideRefusal)
        try await assertRefused(root.appendingPathComponent("outside/other.txt"), data: data, Self.outsideRefusal)
    }

    func testATextInsideTheDataDirectoryIsSent() async throws {
        for name in ["uk-synthetic-01.txt", "linked-inside.txt"] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("cache"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("ledger.json"))
            let output = try await SendCommand.run(options(data.appendingPathComponent("texts/\(name)"), data: data, mode: .fake,
                                                           transport: ScriptedTransport([])))
            XCTAssertEqual(output.attempt, "responded", name)
        }
    }
}
