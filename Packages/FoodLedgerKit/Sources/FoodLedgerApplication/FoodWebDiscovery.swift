import Foundation

/// Web citations are leads for source review, never nutrition candidates or ledger evidence.
public struct FoodWebLead: Equatable, Sendable, Identifiable {
    public let title: String
    public let url: URL
    public let citedText: String?

    public var id: String { url.absoluteString }

    public init(title: String, url: URL, citedText: String? = nil) {
        self.title = title
        self.url = url
        self.citedText = citedText
    }
}

public struct FoodWebDiscoveryResult: Equatable, Sendable {
    public let responseText: String
    public let leads: [FoodWebLead]
    public let searchSuggestionsHTML: String?

    public init(leads: [FoodWebLead], searchSuggestionsHTML: String?, responseText: String = "") {
        self.responseText = responseText
        self.leads = leads
        self.searchSuggestionsHTML = searchSuggestionsHTML
    }
}

public enum FoodWebDiscoveryError: Error, Equatable, Sendable {
    case credentialRejected
    case permissionDenied
    case quotaExceeded
    case requestRejected
    case invalidQuery
    case serviceUnavailable
    case invalidResponse
}

public protocol FoodWebDiscovering: Sendable {
    func validate(key: String) async throws
    func discover(foodTerms: String, key: String) async throws -> FoodWebDiscoveryResult
}

public protocol FoodWebKeyStoring: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

/// Validate header-safe input without assuming a provider key prefix or fixed length.
public enum FoodWebKeySyntax {
    public static func isValid(_ key: String) -> Bool {
        (20...512).contains(key.utf8.count) && key.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

public enum FoodWebLinkPolicy {
    public static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }
}
