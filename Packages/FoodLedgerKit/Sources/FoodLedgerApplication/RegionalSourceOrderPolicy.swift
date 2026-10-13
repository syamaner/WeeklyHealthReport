import Foundation

/// Decides whether regional reference sources (Taiwan TFDA) may interleave with
/// the default UK and US sources. Order is by source, never by comparing scores.
/// This is a presentation rule only; it does not establish food identity.
public enum RegionalSourceOrderPolicy {
    public static let version = "regional-source-order-v1"

    /// Taiwan rows interleave only when the Settings market is Taiwan, the query
    /// names Taiwan, or the query contains Chinese (Han) characters.
    public static func promotesTaiwan(query: String, marketIsTaiwan: Bool) -> Bool {
        marketIsTaiwan || namesTaiwan(query) || containsHan(query)
    }

    static func namesTaiwan(_ query: String) -> Bool {
        let words = query.lowercased().split { !$0.isLetter }
        return words.contains("taiwan") || words.contains("taiwanese")
    }

    static func containsHan(_ query: String) -> Bool {
        query.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true
            default: return false
            }
        }
    }
}
