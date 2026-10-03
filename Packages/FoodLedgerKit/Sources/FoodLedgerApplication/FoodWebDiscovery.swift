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
    case timedOut
    case connectionFailed
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

/// Validate header-safe input without assuming a provider key prefix or alphabet.
/// Google validates the credential itself; this only excludes whitespace and control bytes.
public enum FoodWebKeySyntax {
    public static func isValid(_ key: String) -> Bool {
        (20...512).contains(key.utf8.count) && key.utf8.allSatisfy { (33...126).contains($0) }
    }
}

public enum FoodWebLinkPolicy {
    public static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }
}

/// A string-consistency hint between a provider citation and a URL written by the model.
/// None of these states verifies that the page exists or supports the cited words.
public enum FoodWebCitationLinkRelationship: Equatable, Sendable {
    case noWrittenLink
    case matchingHost
    case conflictingHost
    case multipleWrittenHosts
    case unknownDestination
}

public enum FoodWebCitationLinkPolicy {
    public static func relationship(for lead: FoodWebLead) -> FoodWebCitationLinkRelationship {
        guard let citedText = lead.citedText else { return .noWrittenLink }
        let hosts = Set(markdownLinkHosts(in: citedText))
        guard !hosts.isEmpty else { return .noWrittenLink }
        guard hosts.count == 1, let writtenHost = hosts.first else { return .multipleWrittenHosts }
        let titleHost = domainHint(from: lead.title)
        let rawAnnotationHost = lead.url.host?.lowercased()
        let annotationHost = rawAnnotationHost.map {
            $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0
        }
        if let titleHost {
            if let annotationHost, writtenHost == annotationHost,
               !hostsMatch(titleHost, annotationHost) {
                // The written link repeats an intermediary URL, not the named source website.
                return .unknownDestination
            }
            return hostsMatch(writtenHost, titleHost) ? .matchingHost : .conflictingHost
        }
        guard let annotationHost else { return .unknownDestination }
        // A generic citation title cannot establish whether its URL redirects to the written host.
        return writtenHost == annotationHost ? .matchingHost : .unknownDestination
    }

    private static func markdownLinkHosts(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\[[^\]]+\]\((https://[^\s)]+)\)"#) else {
            return []
        }
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length))
            .compactMap { match in
                guard match.range(at: 1).location != NSNotFound else { return nil }
                return URL(string: source.substring(with: match.range(at: 1)))?.host?.lowercased()
            }
            .map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }

    private static func domainHint(from title: String) -> String? {
        let candidate = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.contains(where: \.isWhitespace), !candidate.contains("/"),
              candidate.split(separator: ".").count >= 2,
              let host = URL(string: "https://\(candidate)")?.host?.lowercased(), host == candidate else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func hostsMatch(_ first: String, _ second: String) -> Bool {
        first == second || first.hasSuffix(".\(second)") || second.hasSuffix(".\(first)")
    }
}
