import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
import PastedLabelAITextEvalCore
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

    /// The text is opened with O_NOFOLLOW: a symbolic link standing where the checked, resolved path
    /// was (a swap after the check) is refused, not followed, even when its target is inside the
    /// data directory. Nothing is read through it.
    func testASymbolicLinkInPlaceOfTheResolvedPathIsRefusedByONoFollow() throws {
        for link in ["linked-inside.txt", "linked-sealed.txt", "linked-outside.txt"] {
            XCTAssertThrowsError(try SendCommand.readCheckedText(atResolvedPath: data.appendingPathComponent("texts/\(link)").path,
                                                                 dataDirectory: data), link) { error in
                XCTAssertEqual("\(error)", "the text file could not be read as a regular UTF-8 file", link)
            }
        }
    }

    /// The opened file's own path, from its descriptor, gets the sealed-set and data-directory checks.
    func testTheOpenedFileIsCheckedThroughItsDescriptor() throws {
        let resolvedData = try XCTUnwrap(SendCommand.resolved(data.path))
        let inside = try SendCommand.readCheckedText(atResolvedPath: resolvedData + "/texts/uk-synthetic-01.txt", dataDirectory: data)
        XCTAssertEqual(inside, Data(Fixtures.ukText.utf8))
        let resolvedSealed = try XCTUnwrap(SendCommand.resolved(sealed.path))
        XCTAssertThrowsError(try SendCommand.readCheckedText(atResolvedPath: resolvedSealed + "/texts/held-01.txt", dataDirectory: nil)) {
            XCTAssertEqual("\($0)".components(separatedBy: ";").first, Self.sealedRefusal)
        }
        let resolvedRoot = try XCTUnwrap(SendCommand.resolved(root.path))
        XCTAssertThrowsError(try SendCommand.readCheckedText(atResolvedPath: resolvedRoot + "/outside/other.txt", dataDirectory: data)) {
            XCTAssertEqual("\($0)".components(separatedBy: ";").first, Self.outsideRefusal)
        }
    }

    /// Only a regular file is read: a directory or a FIFO is refused, and the FIFO does not hang the open.
    func testOnlyARegularFileIsRead() throws {
        let resolvedData = try XCTUnwrap(SendCommand.resolved(data.path))
        XCTAssertThrowsError(try SendCommand.readCheckedText(atResolvedPath: resolvedData + "/texts", dataDirectory: nil))
        let fifo = resolvedData + "/texts/fifo.txt"
        XCTAssertEqual(mkfifo(fifo, 0o600), 0)
        XCTAssertThrowsError(try SendCommand.readCheckedText(atResolvedPath: fifo, dataDirectory: data))
    }

    /// The bytes sent are the bytes checked: the POST body is the request built from exactly the
    /// file's bytes, and the record's text SHA-256 is theirs.
    func testTheBytesSentAreTheBytesChecked() async throws {
        let bytes = Data("Nutrition per 100g\nEnergy 1046kJ / 250kcal\nFat 9.0g\nof which saturates 3.1g\n".utf8)
        let file = data.appendingPathComponent("texts/uk-bytes-01.txt")
        try bytes.write(to: file)
        let transport = ScriptedTransport([LiveModeTests.answer])
        let output = try await SendCommand.run(options(file, data: data, mode: .live, transport: transport))
        let posts = transport.requests.filter { $0.method == "POST" }
        XCTAssertEqual(posts.count, 1)
        let sent = try XCTUnwrap(posts.first?.body)
        let request = try OpenRouterPastedLabelAITextRequest(route: PastedLabelAITextRoute.gemini4ArgonVertexUS, promptVersion: .v1)
        XCTAssertEqual(sent, try request.body(try XCTUnwrap(String(data: bytes, encoding: .utf8))))
        XCTAssertEqual(output.requestSHA256, EvalCase.sha256(sent))
        XCTAssertEqual(output.textSHA256, EvalCase.sha256(bytes))
    }
}
