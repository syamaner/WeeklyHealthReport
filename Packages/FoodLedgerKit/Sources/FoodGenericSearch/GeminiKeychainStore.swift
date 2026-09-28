import FoodLedgerApplication
import Foundation
import Security

public struct GeminiKeychainStore: FoodWebKeyStoring {
    private let service: String
    private let security: KeychainOperations

    public init(service: String = "com.sertanyamaner.WeeklyHealthReport.gemini-user-key") {
        self.service = service
        self.security = .live
    }

    init(service: String, security: KeychainOperations) {
        self.service = service
        self.security = security
    }

    public func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = security.copy(query as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeychainError.unavailable(status) }
        return key
    }

    public func save(_ key: String) throws {
        let data = Data(key.utf8)
        var query = baseQuery
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecValueData as String] = data
        let status = security.add(query as CFDictionary)
        if status == errSecDuplicateItem {
            let update = security.update(baseQuery as CFDictionary, [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary)
            guard update == errSecSuccess else { throw KeychainError.unavailable(update) }
        } else if status != errSecSuccess { throw KeychainError.unavailable(status) }
    }

    public func delete() throws {
        let status = security.delete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unavailable(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "user-supplied-key",
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }

    public enum KeychainError: Error { case unavailable(OSStatus) }
}

/// Internal Security boundary permits deterministic verification without reading
/// an actual user keychain or depending on the test runner's signing entitlements.
struct KeychainOperations: Sendable {
    let copy: @Sendable (CFDictionary) -> (OSStatus, CFTypeRef?)
    let add: @Sendable (CFDictionary) -> OSStatus
    let update: @Sendable (CFDictionary, CFDictionary) -> OSStatus
    let delete: @Sendable (CFDictionary) -> OSStatus

    static let live = Self(copy: { query in
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)
        return (status, result)
    }, add: { SecItemAdd($0, nil) }, update: { SecItemUpdate($0, $1) }, delete: { SecItemDelete($0) })
}
