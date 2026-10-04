import Foundation
import FoodLedgerDomain

/// Conservative recognition of explicit denominators; this is not a general query parser.
public enum FoodProposalQueryPolicy {
    public static let version = "food-proposal-query-basis-v1"
    public static func hasBasisConflict(query: String, basis: FoodProposalBasis) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:\bper\s*|每\s*)([0-9]+(?:\.[0-9]+)?)\s*(grams?|g|公克|克|millilit(?:er|re)s?|mls?|毫升)(?![A-Za-z])"#,
            options: .caseInsensitive) else { return true }
        let text = query as NSString
        for match in regex.matches(in: query, range: NSRange(query.startIndex..., in: query)) {
            let amount = text.substring(with: match.range(at: 1))
            let token = text.substring(with: match.range(at: 2)).lowercased()
            let unit: FoodProposalBasis.Unit = token.hasPrefix("m") || token == "毫升" ? .ml : .g
            if basis.unit != unit || basis.amount.flatMap(FoodProposalBinding.decimal) != FoodProposalBinding.decimal(amount) { return true }
        }
        return false
    }
}
