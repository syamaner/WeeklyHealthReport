import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Concrete source composition: dispatch one page to its own admission policy, never merge panels.
public struct ManufacturerSourceCandidateAdmission: FoodSourceCandidateAdmitting {
    public static let contentHosts: Set<String> = ["www.alpro.com", "alpro.com", "www.arlafoods.co.uk", "www.oatly.com"]
    public init() { }
    public func admit(_ source: FoodReviewedSource, query: FoodSearchRemoteQuery, evidence: CaptureEvidence) throws -> GenericFoodConfirmationRoute? {
        switch source.page.finalURL.host?.lowercased() {
        case "www.alpro.com", "alpro.com": return try AlproSourceCandidateAdmission().admit(source, query: query, evidence: evidence)
        case "www.arlafoods.co.uk": return try ArlaSourceCandidateAdmission().admit(source, query: query, evidence: evidence)
        case "www.oatly.com": return try OatlySourceCandidateAdmission().admit(source, query: query, evidence: evidence)
        default: return nil
        }
    }
}
