@testable import FoodGenericSearch
import Foundation
import Security
import XCTest

final class OpenRouterKeychainStoreTests: XCTestCase {
    func testSeparateCredentialNamespaceAndDeviceOnlyProtection() throws {
        let operations = KeychainOperations(copy: { query in
            Self.checkIdentity(query)
            return (errSecItemNotFound, nil)
        }, add: { query in
            Self.checkIdentity(query)
            XCTAssertEqual((query as NSDictionary)[kSecAttrAccessible] as? String,
                           kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            return errSecDuplicateItem
        }, update: { query, fields in
            Self.checkIdentity(query)
            XCTAssertEqual((fields as NSDictionary)[kSecAttrAccessible] as? String,
                           kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            XCTAssertEqual((fields as NSDictionary)[kSecValueData] as? Data, Data("synthetic-key".utf8))
            return errSecSuccess
        }, delete: { query in
            Self.checkIdentity(query)
            return errSecSuccess
        })
        let store = OpenRouterKeychainStore(security: operations)
        XCTAssertNil(try store.load())
        try store.save("synthetic-key")
        try store.delete()
    }

    private static func checkIdentity(_ query: CFDictionary) {
        let fields = query as NSDictionary
        XCTAssertEqual(fields[kSecAttrService] as? String, "com.sertanyamaner.WeeklyHealthReport.openrouter-user-key")
        XCTAssertEqual(fields[kSecAttrAccount] as? String, "user-supplied-key")
        XCTAssertEqual(fields[kSecAttrSynchronizable] as? Bool, false)
        XCTAssertEqual(fields[kSecUseDataProtectionKeychain] as? Bool, true)
    }
}
