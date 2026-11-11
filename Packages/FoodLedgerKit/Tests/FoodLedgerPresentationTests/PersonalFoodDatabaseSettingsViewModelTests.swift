import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import FoodLedgerTestSupport
import Foundation
import XCTest

@MainActor
final class PersonalFoodDatabaseSettingsViewModelTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/fixtures/personal-food-database-v1")

    struct Clock: LedgerClock { func now() -> Date { Date(timeIntervalSince1970: 1_794_000_000) } }
    struct NoReleases: FoodConfirmationReading {
        func sourceRelease(id: ExternalIdentifier) throws -> SourceRelease? { nil }
        func foodConfirmation(logItemID: LogItemID) throws -> StoredFoodConfirmation? { nil }
        func foodConfirmation(logItemVersionID: LogItemVersionID) throws -> StoredFoodConfirmation? { nil }
        func evidence(id: EvidenceID) throws -> CaptureEvidence? { nil }
    }

    func makeModel(_ store: InMemoryPersonalFoodDatabaseStore) -> PersonalFoodDatabaseSettingsViewModel {
        PersonalFoodDatabaseSettingsViewModel(importer: PersonalFoodDatabaseImporter(
            store: store, digester: SHA256Digester(), clock: Clock(), releases: NoReleases()))
    }

    func testStatesAndRowDetail() async throws {
        let store = InMemoryPersonalFoodDatabaseStore()
        let model = makeModel(store)
        XCTAssertEqual(model.state, .loading)
        XCTAssertNil(model.rowDetail)
        await model.load()
        XCTAssertEqual(model.rowDetail, "Not added")
        XCTAssertEqual(model.importTitle, "Import file")
        XCTAssertFalse(model.canRemove)

        await model.importFile(try Data(contentsOf: Self.fixtures.appendingPathComponent("golden.json")))
        XCTAssertEqual(model.message, "Your food database was updated.")
        XCTAssertEqual(model.rowDetail, "3 foods")
        XCTAssertEqual(model.importTitle, "Replace file")
        XCTAssertTrue(model.canRemove)

        store.damaged = true
        await model.load()
        XCTAssertEqual(model.rowDetail, "Needs replacing")
        XCTAssertTrue(model.canRemove)

        store.locked = true
        await model.load()
        XCTAssertEqual(model.rowDetail, "Locked")
        XCTAssertFalse(model.canRemove)
        store.locked = false

        await model.remove()
        XCTAssertEqual(model.message, "Your food database was removed. Saved food is kept.")
        XCTAssertEqual(model.rowDetail, "Not added")
    }

    /// Every reject fixture gives a message free of the file's content.
    func testRejectionMessagesCarryNoFileContent() async throws {
        struct Manifest: Decodable { let reject: [String: String] }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("manifest.json")))
        let model = makeModel(InMemoryPersonalFoodDatabaseStore())
        for name in manifest.reject.keys.sorted() {
            let bytes = try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
            await model.importFile(bytes)
            let message = try XCTUnwrap(model.message, name)
            XCTAssertTrue(message.hasSuffix("Your food database was not changed."), name)
            XCTAssertFalse(message.contains("pfc:"), name)
            XCTAssertFalse(message.contains("\""), name)
            // No string value of the file (titles, IDs, sources) appears in the message.
            if let object = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) {
                for value in Self.strings(in: object) where value.count >= 4 {
                    XCTAssertFalse(message.contains(value), "\(name): \(value)")
                }
            }
        }
    }

    /// A repeated outcome with the same text still changes the serial, so VoiceOver hears it again.
    func testRepeatedOutcomesAdvanceTheMessageSerial() async throws {
        let model = makeModel(InMemoryPersonalFoodDatabaseStore())
        let bytes = try Data(contentsOf: Self.fixtures.appendingPathComponent("reject-unknown-schema.json"))
        await model.importFile(bytes)
        let first = model.messageSerial
        let text = model.message
        await model.importFile(bytes)
        XCTAssertEqual(model.message, text)
        XCTAssertGreaterThan(model.messageSerial, first)
    }

    func testRuleGroups() {
        XCTAssertEqual(PersonalFoodDatabaseSettingsText.reason(for: [.json]), "This file is not readable JSON. Export it again from your Mac.")
        XCTAssertEqual(PersonalFoodDatabaseSettingsText.reason(for: [.schema]), "This file is not a food database file from your Mac.")
        XCTAssertEqual(PersonalFoodDatabaseSettingsText.reason(for: [.sourceHash]), "The file's source list could not be checked. Export it again from your Mac.")
        XCTAssertEqual(PersonalFoodDatabaseSettingsText.reason(for: [.title]), "An entry in this file could not be read. Export it again from your Mac.")
        XCTAssertEqual(PersonalFoodDatabaseSettingsText.reason(for: [.title, .count]), "This file is too large for Your food database.")
    }

    static func strings(in value: Any) -> [String] {
        switch value {
        case let string as String: [string]
        case let array as [Any]: array.flatMap { strings(in: $0) }
        case let object as [String: Any]: object.values.flatMap { strings(in: $0) }
        default: []
        }
    }
}
