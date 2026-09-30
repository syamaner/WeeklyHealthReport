import Foundation
import FoodLedgerApplication

/// Exact infrastructure host/URL policy, shared by source selection and physical HTTP attempts.
struct FoodSourceURLPolicy: Sendable {
    private let allowedHosts: Set<String>
    init(allowedHosts: Set<String>) throws {
        guard !allowedHosts.isEmpty, allowedHosts.count <= 32,
              allowedHosts.allSatisfy(Self.isAdmissibleHostName) else { throw FoodSourceAcquisitionError.hostNotAdmitted }
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
    }
    func canonicalURL(_ url: URL) throws -> URL {
        guard url.absoluteString.utf8.count <= HTTPSFoodSourcePageAcquirer.maximumURLBytes,
              url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              Self.isAdmissibleHostName(host) else { throw FoodSourceAcquisitionError.invalidURL }
        guard allowedHosts.contains(host) else { throw FoodSourceAcquisitionError.hostNotAdmitted }
        // Fragments never reach HTTP; preserve the same canonical request identity across redirects.
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw FoodSourceAcquisitionError.invalidURL }
        components.fragment = nil
        guard let canonical = components.url else { throw FoodSourceAcquisitionError.invalidURL }
        return canonical
    }

    private static func isAdmissibleHostName(_ host: String) -> Bool {
        let host = host.lowercased()
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, labels.count >= 2, let suffix = labels.last,
              suffix.count >= 2, suffix.allSatisfy({ $0 >= "a" && $0 <= "z" }),
              !["localhost", "local", "internal", "home", "lan", "test", "invalid"].contains(String(suffix)) else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                && label.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" }
        }
    }
}
