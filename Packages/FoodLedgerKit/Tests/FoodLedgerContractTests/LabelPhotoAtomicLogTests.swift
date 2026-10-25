import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import XCTest

/// Contract test 15, atomic Log (docs/label-photo-ai-prefill-v1.md 17.3 H1): the photo is
/// persisted first and one commit holds the image evidence, the manifest evidence, the release and
/// the log records. A policy rejection, a verifier rejection and a commit failure each leave no
/// evidence row, no release and no file under the attachments root. Run on the GRDB store, whose
/// attachment directory is real.
final class LabelPhotoAtomicLogTests: XCTestCase {
    typealias F = LabelPhotoFixtures

    /// Delegates to the store, counting commits, or failing every commit.
    final class Committer: LedgerCommandCommitting, @unchecked Sendable {
        let store: FoodLedgerGRDBStore
        let fails: Bool
        var commits = 0
        init(_ store: FoodLedgerGRDBStore, fails: Bool = false) { self.store = store; self.fails = fails }
        func actorHead(for actorID: ActorID) throws -> ActorHead { try store.actorHead(for: actorID) }
        func operation(id: OperationID) throws -> LedgerOperation? { try store.operation(id: id) }
        func commit(_ transaction: LedgerTransaction) throws -> CommitOutcome {
            if fails { throw FoodLedgerStoreError.integrityFailure("synthetic commit failure") }
            commits += 1
            return try store.commit(transaction)
        }
    }

    var directory: URL!
    var store: FoodLedgerGRDBStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("label-photo-log-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try FoodLedgerGRDBStore.temporary(directory: directory, encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// Regular files anywhere under the store's directory other than the database's own.
    func attachmentFiles() -> [String] {
        let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        return (walker?.allObjects as? [URL] ?? []).filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && url.path.contains("/Attachments/")
        }.map(\.lastPathComponent)
    }

    func service(_ committer: Committer) throws -> FoodConfirmationService {
        try FoodConfirmationService(ledger: LedgerFixtures.service(committer), reader: store, clock: LedgerFixtures.clock,
            ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester, pastedLabelConversions: GoldenPastedLabelConversions())
    }

    /// The Confirm input as the builder hands it to Log: no attachment yet.
    func input() throws -> PopulatedFoodConfirmation { try F.input(try F.manifest()) }

    func assertNothingKept(_ input: PopulatedFoodConfirmation, file: StaticString = #filePath, line: UInt = #line) throws {
        for evidence in input.evidence {
            XCTAssertNil(try store.evidence(id: evidence.evidenceID), "no evidence row", file: file, line: line)
        }
        XCTAssertNil(try store.sourceRelease(id: input.sourceReleases[0].sourceReleaseID), "no release", file: file, line: line)
        XCTAssertEqual(attachmentFiles(), [], "no file under the attachments root", file: file, line: line)
    }

    func testASuccessfulLogIsOneCommitWithThePhotoBound() throws {
        let input = try input()
        let committer = Committer(store)
        let saved = try service(committer).saveLabelPhoto(PastedLabelFixtures.state(input), imageBytes: F.imageBytes, attachmentStore: store,
                                                          operationID: LedgerFixtures.operationID(9_970))
        XCTAssertEqual(committer.commits, 1)
        let image = try XCTUnwrap(try store.evidence(id: input.evidence[1].evidenceID))
        XCTAssertEqual(image.attachment?.sha256.value, try F.imageSHA())
        XCTAssertNotNil(try store.evidence(id: input.evidence[0].evidenceID))
        XCTAssertNotNil(try store.sourceRelease(id: input.sourceReleases[0].sourceReleaseID))
        XCTAssertEqual(attachmentFiles().count, 1)
        XCTAssertNotNil(try service(committer).reopen(logItemID: saved.logItem.logItemID), "reopen verifies the photo entry")
    }

    func testAPolicyRejectionKeepsNothing() throws {
        let input = try input()
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .accept)   // no quantity: Log's policy refuses
        XCTAssertThrowsError(try service(Committer(store)).saveLabelPhoto(state, imageBytes: F.imageBytes, attachmentStore: store,
                                                                         operationID: LedgerFixtures.operationID(9_971))) {
            guard case .unmetRequirements = $0 as? FoodConfirmationSaveError else { return XCTFail("\($0)") }
        }
        try assertNothingKept(input)
    }

    func testAVerifierRejectionKeepsNothing() throws {
        let input = try input()
        // A manifest changed after it was built (protein left unknown yet still corrected), with every
        // hash rebound so only the content rule can refuse it, fails the photo verifier.
        let tampered = try F.rebound(input, manifest: try F.manifest(resolutions: ["蛋白質@h2": .leftUnknown]))
        XCTAssertFalse(F.verify(tampered))
        XCTAssertThrowsError(try service(Committer(store)).saveLabelPhoto(PastedLabelFixtures.state(tampered), imageBytes: F.imageBytes,
                                                                         attachmentStore: store, operationID: LedgerFixtures.operationID(9_972))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource)
        }
        try assertNothingKept(tampered)
    }

    func testACommitFailureKeepsNothing() throws {
        let input = try input()
        XCTAssertThrowsError(try service(Committer(store, fails: true)).saveLabelPhoto(PastedLabelFixtures.state(input), imageBytes: F.imageBytes,
                                                                                      attachmentStore: store,
                                                                                      operationID: LedgerFixtures.operationID(9_973)))
        try assertNothingKept(input)
    }

    func testOtherBytesOrThePlainSaveAreRefusedBeforeAnythingIsWritten() throws {
        let input = try input()
        XCTAssertThrowsError(try service(Committer(store)).saveLabelPhoto(PastedLabelFixtures.state(input), imageBytes: Data("other".utf8),
                                                                         attachmentStore: store, operationID: LedgerFixtures.operationID(9_974))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource)
        }
        // A new photo entry never commits through the plain save, which would keep no photo.
        XCTAssertThrowsError(try service(Committer(store)).save(PastedLabelFixtures.state(input), operationID: LedgerFixtures.operationID(9_975))) {
            XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource)
        }
        try assertNothingKept(input)
    }
}
