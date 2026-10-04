import FoodLedgerApplication

/// Separate credential namespace: an existing Gemini key never authorises an
/// OpenRouter request. Reuses the already tested device-only Security boundary.
public struct OpenRouterKeychainStore: FoodWebKeyStoring {
    static let service = "com.sertanyamaner.WeeklyHealthReport.openrouter-user-key"
    private let store: GeminiKeychainStore
    public init() { store = GeminiKeychainStore(service: Self.service) }
    init(security: KeychainOperations) { store = GeminiKeychainStore(service: Self.service, security: security) }
    public func load() throws -> String? { try store.load() }
    public func save(_ key: String) throws { try store.save(key) }
    public func delete() throws { try store.delete() }
}
