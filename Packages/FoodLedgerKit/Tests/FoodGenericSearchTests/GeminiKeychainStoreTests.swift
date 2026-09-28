@testable import FoodGenericSearch
import Foundation
import Security
import XCTest

final class GeminiKeychainStoreTests: XCTestCase {
    func testRoundTripReplacementAndDeletionPreserveDeviceOnlyProtection() throws {
        let security = SyntheticSecurity()
        let keys = GeminiKeychainStore(service: "synthetic-test", security: security.operations)
        XCTAssertNil(try keys.load())
        try keys.save("synthetic-first")
        XCTAssertEqual(try keys.load(), "synthetic-first")
        try keys.save("synthetic-replacement")
        XCTAssertEqual(try keys.load(), "synthetic-replacement")
        XCTAssertEqual(security.updateCount, 1)
        try keys.delete()
        XCTAssertNil(try keys.load())
        try keys.delete()
    }

    func testSecurityErrorsAreNeverTreatedAsAbsenceOrSuccess() {
        let unavailable = KeychainOperations(copy: { _ in (errSecInteractionNotAllowed, nil) },
            add: { _ in errSecInteractionNotAllowed }, update: { _, _ in errSecInteractionNotAllowed },
            delete: { _ in errSecInteractionNotAllowed })
        let keys = GeminiKeychainStore(service: "synthetic-test", security: unavailable)
        XCTAssertThrowsError(try keys.load())
        XCTAssertThrowsError(try keys.save("synthetic-key"))
        XCTAssertThrowsError(try keys.delete())
    }
}

private final class SyntheticSecurity: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?
    private(set) var updateCount = 0
    var operations: KeychainOperations {
        KeychainOperations(copy: { [self] query in
            lock.withLock {
                checkIdentity(query)
                return value.map { (errSecSuccess, $0 as CFData) } ?? (errSecItemNotFound, nil)
            }
        }, add: { [self] query in
            lock.withLock {
                checkIdentity(query)
                let fields = query as NSDictionary
                checkProtection(fields)
                if value != nil { return errSecDuplicateItem }
                value = fields[kSecValueData] as? Data
                return errSecSuccess
            }
        }, update: { [self] query, update in
            lock.withLock {
                checkIdentity(query)
                let fields = update as NSDictionary
                checkProtection(fields)
                value = fields[kSecValueData] as? Data
                updateCount += 1
                return errSecSuccess
            }
        }, delete: { [self] query in
            lock.withLock {
                checkIdentity(query)
                let status = value == nil ? errSecItemNotFound : errSecSuccess
                value = nil
                return status
            }
        })
    }
    private func checkIdentity(_ query: CFDictionary) {
        let fields = query as NSDictionary
        XCTAssertEqual(fields[kSecAttrService] as? String, "synthetic-test")
        XCTAssertEqual(fields[kSecAttrAccount] as? String, "user-supplied-key")
        XCTAssertEqual(fields[kSecAttrSynchronizable] as? Bool, false)
        XCTAssertEqual(fields[kSecUseDataProtectionKeychain] as? Bool, true)
    }
    private func checkProtection(_ fields: NSDictionary) {
        XCTAssertEqual(fields[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }
}
