import XCTest
import FoodLedgerApplication
@testable import WeeklyHealthReport

/// The label photo route at the composition root (docs/label-photo-ai-prefill-v1.md 17.8 L2 and
/// 17.18; contract test 24): off by default, one read session per ledger per process, and the
/// attachments root and spend ledger under the backup-excluded health-data directory.
@MainActor
final class LabelPhotoCompositionTests: XCTestCase {
    func makeRoot(route: String?) throws -> (FoodLedgerCompositionRoot, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "label-photo-\(UUID().uuidString)"))
        if let route { defaults.set(route, forKey: "LabelPhotoRoute") }
        return (try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults), directory)
    }

    func testTheRouteIsOffByDefault() throws {
        let (root, _) = try makeRoot(route: nil)
        XCTAssertFalse(root.labelPhotoEnabled)
        XCTAssertNil(root.labelPhotoFlow())
        XCTAssertNil(root.labelPhotoScreenModel())
        let (unknown, _) = try makeRoot(route: "Live")
        XCTAssertFalse(unknown.labelPhotoEnabled, "only a scripted scenario or exactly `live` enables it")
    }

    func testTheLiveRouteIsALaunchArgumentWithItsOwnConsentLedgerAndNoSample() throws {
        let (root, _) = try makeRoot(route: "live")
        XCTAssertEqual(root.labelPhotoMode, .live)
        XCTAssertEqual(root.labelPhotoActiveConsentKey, "labelPhoto.egressConsent.live.v1")
        XCTAssertNotEqual(root.labelPhotoActiveSpendLedgerURL, root.labelPhotoSpendLedgerURL, "scripted reads never touch the real allowance")
        XCTAssertTrue(root.labelPhotoActiveSpendLedgerURL.standardizedFileURL.path.hasPrefix(root.healthDirectory.standardizedFileURL.path + "/"))
        XCTAssertNil(root.labelPhotoSample, "the live route reads only real photos")
        let (fake, _) = try makeRoot(route: "answer")
        XCTAssertEqual(fake.labelPhotoActiveConsentKey, "labelPhoto.egressConsent.scripted.v1")
        XCTAssertEqual(fake.labelPhotoActiveSpendLedgerURL, fake.labelPhotoSpendLedgerURL)
        XCTAssertNotNil(fake.labelPhotoSample)
    }

    func testTheSpendLedgerAndAttachmentsSitUnderTheBackupExcludedDirectory() throws {
        let (root, _) = try makeRoot(route: "answer")
        let health = root.healthDirectory.standardizedFileURL.path
        XCTAssertTrue(root.labelPhotoSpendLedgerURL.standardizedFileURL.path.hasPrefix(health + "/"))
        XCTAssertTrue(root.attachmentsRoot.standardizedFileURL.path.hasPrefix(health + "/"))
        XCTAssertEqual(try root.healthDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testOneReadSessionPerLedgerPerProcess() throws {
        let (root, _) = try makeRoot(route: "answer")
        let first = try XCTUnwrap(root.labelPhotoFlow())
        let second = try XCTUnwrap(root.labelPhotoFlow())
        XCTAssertTrue(first.session === second.session, "every screen and scene shares the session")
        XCTAssertNotNil(root.labelPhotoScreenModel())
        XCTAssertNotNil(root.labelPhotoScreenModel())
        XCTAssertTrue(try XCTUnwrap(root.labelPhotoFlow()).session === first.session)
    }

    func testTheScriptedRoutesConsentIsItsOwn() {
        // A consent given to the scripted transport never stands for live egress (L5 uses a fresh key).
        XCTAssertEqual(FoodLedgerCompositionRoot.labelPhotoConsentKey, "labelPhoto.egressConsent.scripted.v1")
    }
}
