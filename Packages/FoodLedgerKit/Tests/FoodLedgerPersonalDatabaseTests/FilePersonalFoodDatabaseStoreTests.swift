import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPersonalDatabase
import FoodLedgerTestSupport
import Foundation
import XCTest

/// The store contract (phase 1 plan sections 3 and 3.1). The shared suite runs against the file
/// store and the in-memory store; the rest pins the file layout, crash safety and protection.
final class FilePersonalFoodDatabaseStoreTests: XCTestCase {
    final class Flags: @unchecked Sendable {
        private let lock = NSLock()
        private var lockedValue = false
        private var protectedPaths: Set<String> = []
        var locked: Bool {
            get { lock.withLock { lockedValue } }
            set { lock.withLock { lockedValue = newValue } }
        }
        var protected: Set<String> { lock.withLock { protectedPaths } }
        func record(_ url: URL) { _ = lock.withLock { protectedPaths.insert(url.standardizedFileURL.path) } }
    }

    struct Fault: Error {}

    var root: URL!
    let flags = Flags()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pfd-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func makeStore(fault: (@Sendable (FilePersonalFoodDatabaseStore.Step) throws -> Void)? = nil) -> FilePersonalFoodDatabaseStore {
        let flags = flags
        return FilePersonalFoodDatabaseStore(root: root, digester: SHA256Digester(), isProtectedDataAvailable: { !flags.locked },
                                             protect: { flags.record($0) }, fault: fault)
    }

    static func release(_ text: String, importedAt: TimeInterval = 1_794_000_000) throws -> PersonalFoodDatabaseInstalledRelease {
        let bytes = Data(text.utf8)
        let digest = try SHA256Digester().sha256(bytes)
        let manifest = PersonalFoodDatabaseManifest(
            schema: PersonalFoodDatabaseSchema.v1.rawValue, releaseID: PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest),
            fileSHA256: digest, generated: try XCTUnwrap(PersonalFoodDatabaseDate(ascii: Array("2026-11-10".utf8))),
            importedAt: Date(timeIntervalSince1970: importedAt), entryCount: 3)
        return PersonalFoodDatabaseInstalledRelease(bytes: bytes, manifest: manifest)
    }

    var base: URL { root.appendingPathComponent("Datasets/personal-food-database", isDirectory: true) }
    var staging: URL { root.appendingPathComponent("ImportStaging", isDirectory: true) }
    func folder(_ release: PersonalFoodDatabaseInstalledRelease) -> URL {
        base.appendingPathComponent("pfc-sha256-\(release.manifest.fileSHA256.value)", isDirectory: true)
    }
    func contents(_ url: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }

    func assertThrows(_ expected: PersonalFoodDatabaseStoreError, _ body: () throws -> Void, line: UInt = #line) {
        XCTAssertThrowsError(try body(), line: line) { XCTAssertEqual($0 as? PersonalFoodDatabaseStoreError, expected, line: line) }
    }

    // MARK: Shared contract

    func assertStoreContract(_ store: any PersonalFoodDatabaseStoring, setLocked: (Bool) -> Void, line: UInt = #line) throws {
        let a = try Self.release("first"), b = try Self.release("second", importedAt: 1_794_000_100)
        XCTAssertNil(try store.activeRelease(), line: line)
        try store.install(bytes: a.bytes, manifest: a.manifest)
        XCTAssertEqual(try store.activeRelease(), a, line: line)
        try store.install(bytes: b.bytes, manifest: b.manifest)
        XCTAssertEqual(try store.activeRelease(), b, line: line)
        setLocked(true)
        assertThrows(.locked, { _ = try store.activeRelease() }, line: line)
        assertThrows(.locked, { try store.install(bytes: a.bytes, manifest: a.manifest) }, line: line)
        assertThrows(.locked, { try store.remove() }, line: line)
        setLocked(false)
        XCTAssertEqual(try store.activeRelease(), b, "locked changes nothing", line: line)
        XCTAssertTrue(try store.remove(), line: line)
        XCTAssertNil(try store.activeRelease(), line: line)
        XCTAssertFalse(try store.remove(), line: line)
    }

    func testFileStorePassesTheContract() throws {
        try assertStoreContract(makeStore()) { flags.locked = $0 }
    }

    func testInMemoryStorePassesTheContract() throws {
        let store = InMemoryPersonalFoodDatabaseStore()
        try assertStoreContract(store) { store.locked = $0 }
    }

    // MARK: Layout and sweep

    func testLayoutAndSweep() throws {
        let store = makeStore(), a = try Self.release("first"), b = try Self.release("second")
        let otherFeature = staging.appendingPathComponent("food-list-123", isDirectory: true)
        try FileManager.default.createDirectory(at: otherFeature, withIntermediateDirectories: true)
        try store.install(bytes: a.bytes, manifest: a.manifest)
        XCTAssertEqual(contents(folder(a)), ["manifest.json", "personal-food-catalogue-v1.json"])
        try store.install(bytes: b.bytes, manifest: b.manifest)
        XCTAssertEqual(contents(base), ["active.json", folder(b).lastPathComponent])
        XCTAssertEqual(contents(staging), ["food-list-123"], "only this feature's staging is swept")
        try store.remove()
        XCTAssertEqual(contents(base), [])
    }

    /// Two store instances on one root, installing different releases at once, always leave the
    /// release the final pointer names on disk and readable, with only that release kept.
    func testConcurrentInstallsFromTwoStoresLeaveTheNamedReleaseIntact() throws {
        let first = makeStore(), second = makeStore()
        let a = try Self.release("first"), b = try Self.release("second")
        let failures = Flags()
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            let (store, release) = index.isMultiple(of: 2) ? (first, a) : (second, b)
            do { try store.install(bytes: release.bytes, manifest: release.manifest) } catch { failures.record(URL(fileURLWithPath: "/\(index)")) }
        }
        XCTAssertEqual(failures.protected, [], "every install succeeds")
        let active = try XCTUnwrap(try makeStore().activeRelease())
        XCTAssertTrue(active == a || active == b)
        XCTAssertEqual(contents(base), ["active.json", folder(active).lastPathComponent])
        XCTAssertEqual(contents(staging), [])
    }

    func testEveryCreatedPathIsProtected() throws {
        let store = makeStore(), a = try Self.release("first")
        try store.install(bytes: a.bytes, manifest: a.manifest)
        // The shared `ImportStaging` folder itself is left to its owners; this call's subfolder was
        // protected before it was moved into place.
        let protected = flags.protected
        XCTAssertFalse(protected.contains(staging.standardizedFileURL.path))
        XCTAssertTrue(protected.contains { $0.hasPrefix(staging.standardizedFileURL.path + "/personal-food-database-") })
        var created: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator { created.append(url.standardizedFileURL.path) }
        created.append(base.standardizedFileURL.path)
        for path in created {
            // The pointer is protected under its pending name, then renamed over `active.json`
            // (protection travels with a rename, and the rename is the commit point).
            let checked = path.hasSuffix("/active.json") ? path + ".pending" : path
            XCTAssertTrue(protected.contains(URL(fileURLWithPath: checked).standardizedFileURL.path), path)
        }
    }

    // MARK: Crash safety

    func testAFaultAtEveryStepKeepsThePreviousRelease() throws {
        let a = try Self.release("first"), b = try Self.release("second")
        for step in [FilePersonalFoodDatabaseStore.Step.staging, .rename, .pointer] {
            try makeStore().install(bytes: a.bytes, manifest: a.manifest)
            let failing = makeStore(fault: { if $0 == step { throw Fault() } })
            assertThrows(.writeFailed) { try failing.install(bytes: b.bytes, manifest: b.manifest) }
            XCTAssertEqual(try makeStore().activeRelease(), a, "\(step)")
            // The next successful install sweeps whatever the failed one left.
            try makeStore().install(bytes: b.bytes, manifest: b.manifest)
            XCTAssertEqual(contents(base), ["active.json", folder(b).lastPathComponent], "\(step)")
            XCTAssertEqual(contents(staging), [], "\(step)")
            try makeStore().remove()
        }
    }

    func testOrphanFoldersWithoutAPointerReadAsNone() throws {
        let store = makeStore(), a = try Self.release("first")
        try store.install(bytes: a.bytes, manifest: a.manifest)
        try FileManager.default.removeItem(at: base.appendingPathComponent("active.json"))
        XCTAssertNil(try store.activeRelease())
        // An orphan folder of the same release still installs.
        try store.install(bytes: a.bytes, manifest: a.manifest)
        XCTAssertEqual(try store.activeRelease(), a)
    }

    func testRemoveDeletesThePointerFirstAndNothingWhileLocked() throws {
        let store = makeStore(), a = try Self.release("first")
        try store.install(bytes: a.bytes, manifest: a.manifest)
        flags.locked = true
        assertThrows(.locked) { try store.remove() }
        flags.locked = false
        XCTAssertEqual(contents(base), ["active.json", folder(a).lastPathComponent])
        // With the folder made undeletable, remove still commits by deleting the pointer.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: folder(a).appendingPathComponent("manifest.json").path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: folder(a).appendingPathComponent("manifest.json").path) }
        XCTAssertTrue(try store.remove())
        XCTAssertNil(try store.activeRelease())
    }

    func testInstallRefusesAManifestItsReaderWouldReject() throws {
        let store = makeStore(), a = try Self.release("first")
        let m = a.manifest
        for bad in [
            PersonalFoodDatabaseManifest(schema: m.schema, releaseID: m.releaseID, fileSHA256: m.fileSHA256, generated: m.generated, importedAt: m.importedAt, entryCount: -1),
            PersonalFoodDatabaseManifest(schema: "other", releaseID: m.releaseID, fileSHA256: m.fileSHA256, generated: m.generated, importedAt: m.importedAt, entryCount: 3),
            PersonalFoodDatabaseManifest(schema: m.schema, releaseID: m.releaseID, fileSHA256: m.fileSHA256, generated: m.generated,
                                         importedAt: m.importedAt.addingTimeInterval(0.5), entryCount: 3)
        ] {
            assertThrows(.writeFailed) { try store.install(bytes: a.bytes, manifest: bad) }
        }
        XCTAssertNil(try store.activeRelease())
    }

    func testInstallRefusesBytesThatDoNotMatchTheManifest() throws {
        let store = makeStore(), a = try Self.release("first"), b = try Self.release("second")
        try store.install(bytes: a.bytes, manifest: a.manifest)
        assertThrows(.writeFailed) { try store.install(bytes: b.bytes, manifest: a.manifest) }
        XCTAssertEqual(try store.activeRelease(), a)
    }

    /// A verified folder that the pointer names is reused untouched, so neither a fault nor a later
    /// pointer failure can change or remove it.
    func testReinstallingTheActiveReleaseNeverTouchesItsFolder() throws {
        let a = try Self.release("first")
        try makeStore().install(bytes: a.bytes, manifest: a.manifest)
        let manifestURL = folder(a).appendingPathComponent("manifest.json")
        let before = try Data(contentsOf: manifestURL)
        let later = try Self.release("first", importedAt: 1_794_000_500)
        let renameFault = makeStore(fault: { if $0 == .rename { throw Fault() } })
        XCTAssertNoThrow(try renameFault.install(bytes: later.bytes, manifest: later.manifest), "no rename is needed")
        let pointerFault = makeStore(fault: { if $0 == .pointer { throw Fault() } })
        assertThrows(.writeFailed) { try pointerFault.install(bytes: later.bytes, manifest: later.manifest) }
        XCTAssertEqual(try Data(contentsOf: manifestURL), before)
        XCTAssertEqual(try makeStore().activeRelease(), a)
    }

    /// A damaged folder of the same release is replaced: a failure before the commit leaves it
    /// damaged or missing, never a different valid release.
    func testAFailedRepairLeavesTheReleaseDamagedNotReplaced() throws {
        let a = try Self.release("first")
        try makeStore().install(bytes: a.bytes, manifest: a.manifest)
        try Data("first!".utf8).write(to: folder(a).appendingPathComponent("personal-food-catalogue-v1.json"))
        let failing = makeStore(fault: { if $0 == .rename { throw Fault() } })
        assertThrows(.writeFailed) { try failing.install(bytes: a.bytes, manifest: a.manifest) }
        assertThrows(.damaged) { _ = try makeStore().activeRelease() }
        try makeStore().install(bytes: a.bytes, manifest: a.manifest)
        XCTAssertEqual(try makeStore().activeRelease(), a)
    }

    /// A same-release folder whose manifest names the wrong release is damaged, so re-importing the
    /// same bytes replaces it rather than reusing it.
    func testAWrongReleaseIDIsRepairedNotReused() throws {
        let a = try Self.release("first")
        try makeStore().install(bytes: a.bytes, manifest: a.manifest)
        let manifestURL = folder(a).appendingPathComponent("manifest.json")
        let wrong = String(decoding: try Data(contentsOf: manifestURL), as: UTF8.self)
            .replacingOccurrences(of: "pfc:sha256:", with: "pfc:sha256:0")
        try Data(wrong.utf8).write(to: manifestURL)
        assertThrows(.damaged) { _ = try makeStore().activeRelease() }
        try makeStore().install(bytes: a.bytes, manifest: a.manifest)
        XCTAssertEqual(try makeStore().activeRelease(), a)
    }

    /// A pointer that exists but cannot be read is damaged, never absent.
    func testAnUnreadablePointerIsDamagedNotNone() throws {
        let a = try Self.release("first")
        try makeStore().install(bytes: a.bytes, manifest: a.manifest)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: base.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base.path) }
        assertThrows(.damaged) { _ = try makeStore().activeRelease() }
    }

    // MARK: Damaged

    func testDamagedStates() throws {
        let a = try Self.release("first")
        let pointer = base.appendingPathComponent("active.json")
        func reinstall() throws { try makeStore().remove(); try makeStore().install(bytes: a.bytes, manifest: a.manifest) }

        try reinstall()
        try Data("first!".utf8).write(to: folder(a).appendingPathComponent("personal-food-catalogue-v1.json"))
        assertThrows(.damaged) { _ = try makeStore().activeRelease() }

        try reinstall()
        try Data("{".utf8).write(to: pointer)
        assertThrows(.damaged) { _ = try makeStore().activeRelease() }

        try reinstall()
        try Data(#"{"folder":"pfc-sha256-\#(String(repeating: "0", count: 64))","version":1}"#.utf8).write(to: pointer)
        assertThrows(.damaged, { _ = try makeStore().activeRelease() })

        try reinstall()
        try Data(#"{"folder":"\#(folder(a).lastPathComponent)","version":2}"#.utf8).write(to: pointer)
        assertThrows(.damaged) { _ = try makeStore().activeRelease() }

        // A manifest whose release ID disagrees with the file hash.
        try reinstall()
        let manifestURL = folder(a).appendingPathComponent("manifest.json")
        let wrongID = String(decoding: try Data(contentsOf: manifestURL), as: UTF8.self)
            .replacingOccurrences(of: "pfc:sha256:", with: "pfc:sha256:0")
        try Data(wrongID.utf8).write(to: manifestURL)
        assertThrows(.damaged) { _ = try makeStore().activeRelease() }

        // A folder name that disagrees with the hash.
        try reinstall()
        let renamed = base.appendingPathComponent("pfc-sha256-" + String(repeating: "a", count: 64), isDirectory: true)
        try FileManager.default.moveItem(at: folder(a), to: renamed)
        try PersonalFoodDatabaseStoredPointer(folder: renamed.lastPathComponent).encoded().write(to: pointer)
        assertThrows(.damaged) { _ = try makeStore().activeRelease() }

        // Same bytes repair a damaged release.
        try makeStore().install(bytes: a.bytes, manifest: a.manifest)
        XCTAssertEqual(try makeStore().activeRelease(), a)
    }

    // MARK: Golden on-disk JSON

    func testPointerAndManifestAreByteStable() throws {
        let a = try Self.release("first")
        let hex = a.manifest.fileSHA256.value
        let pointer = #"{"folder":"pfc-sha256-\#(hex)","version":1}"#
        let manifest = #"{"entry_count":3,"file_sha256":"\#(hex)","generated":"2026-11-10","imported_at":"2026-11-06T21:20:00Z","release_id":"pfc:sha256:\#(hex)","schema":"personal-food-catalogue-v1","version":1}"#
        XCTAssertEqual(String(decoding: try PersonalFoodDatabaseStoredPointer(folder: "pfc-sha256-\(hex)").encoded(), as: UTF8.self), pointer)
        XCTAssertEqual(String(decoding: try PersonalFoodDatabaseStoredManifest(a.manifest).encoded(), as: UTF8.self), manifest)
        let decodedPointer = try JSONDecoder().decode(PersonalFoodDatabaseStoredPointer.self, from: Data(pointer.utf8))
        XCTAssertEqual(String(decoding: try decodedPointer.encoded(), as: UTF8.self), pointer)
        let decodedManifest = try JSONDecoder().decode(PersonalFoodDatabaseStoredManifest.self, from: Data(manifest.utf8))
        XCTAssertEqual(decodedManifest.manifest, a.manifest)
        XCTAssertEqual(String(decoding: try decodedManifest.encoded(), as: UTF8.self), manifest)
        // What the store writes is exactly that form.
        try makeStore().install(bytes: a.bytes, manifest: a.manifest)
        XCTAssertEqual(String(decoding: try Data(contentsOf: base.appendingPathComponent("active.json")), as: UTF8.self), pointer)
        XCTAssertEqual(String(decoding: try Data(contentsOf: folder(a).appendingPathComponent("manifest.json")), as: UTF8.self), manifest)
    }

    func testManifestRejectsWhatTheStoreDidNotWrite() throws {
        let a = try Self.release("first")
        let good = try PersonalFoodDatabaseStoredManifest(a.manifest).encoded()
        let text = String(decoding: good, as: UTF8.self)
        for (old, new) in [("\"version\":1", "\"version\":2"), ("2026-11-10", "2026-02-30"),
                           ("2026-11-06T21:20:00Z", "2026-11-06T21:20:00.5Z"), ("personal-food-catalogue-v1", "other")] {
            let decoded = try JSONDecoder().decode(PersonalFoodDatabaseStoredManifest.self, from: Data(text.replacingOccurrences(of: old, with: new).utf8))
            XCTAssertNil(decoded.manifest, new)
        }
    }

    /// Import v2: a v2 file is stored under the same storage name with a v2 manifest; the v1
    /// manifest above keeps its bytes, and an unknown schema is still refused.
    func testV2ManifestRoundTripsAndUnknownSchemasStayRefused() throws {
        let a = try Self.release("first")
        let v2 = PersonalFoodDatabaseManifest(schema: PersonalFoodDatabaseSchema.v2.rawValue, releaseID: a.manifest.releaseID,
            fileSHA256: a.manifest.fileSHA256, generated: a.manifest.generated, importedAt: a.manifest.importedAt,
            entryCount: a.manifest.entryCount)
        let text = String(decoding: try PersonalFoodDatabaseStoredManifest(v2).encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains(#""schema":"personal-food-catalogue-v2","version":1}"#))
        let decoded = try JSONDecoder().decode(PersonalFoodDatabaseStoredManifest.self, from: Data(text.utf8))
        XCTAssertEqual(decoded.manifest, v2)
        XCTAssertEqual(String(decoding: try decoded.encoded(), as: UTF8.self), text)
        try makeStore().install(bytes: a.bytes, manifest: v2)
        XCTAssertEqual(contents(folder(a)), ["manifest.json", "personal-food-catalogue-v1.json"])
        XCTAssertEqual(try makeStore().activeRelease()?.manifest, v2)
        for schema in ["personal-food-catalogue-v3", "PERSONAL-FOOD-CATALOGUE-V2", ""] {
            let other = try JSONDecoder().decode(PersonalFoodDatabaseStoredManifest.self,
                from: Data(text.replacingOccurrences(of: "personal-food-catalogue-v2", with: schema).utf8))
            XCTAssertNil(other.manifest, schema)
        }
    }
}
