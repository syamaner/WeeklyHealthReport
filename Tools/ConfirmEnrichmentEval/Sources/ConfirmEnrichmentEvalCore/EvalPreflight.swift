import Foundation

/// The section 11.1a preflight (docs/confirm-enrichment-openrouter-v1-phase.md section 8): the tool sends
/// nothing unless this paragraph is present, word for word, both in the checkout's
/// docs/privacy-and-egress.md and in that file on `origin/main`. The tool never runs git over the network:
/// `run.sh` fetches with the key unset, and the tool only reads `git show origin/main:…` locally.
public enum EvalPreflight {
    /// The paragraph, exactly as docs/privacy-and-egress.md holds it (a test pins the two equal).
    public static let paragraph = "Developer tooling for the Confirm enrichment evaluation ([confirm-enrichment-openrouter-v1.md](confirm-enrichment-openrouter-v1.md) section 12, #549) runs on the owner's Mac, not in the app, and is not app egress. It sends to `https://openrouter.ai/api/v1/systemone` (model `jev-1.13`) and `https://openrouter.ai/api/v1/chat/completions` (the CE-D2 route) only, plus the keyless GETs of their endpoint and zero-data-retention listings that CE-T1 includes for the app's same request shapes. Each request carries exactly the app's request shape for one evaluation case, built from public Open Food Facts product data and bundled composition rows only, never the owner's data: the description fields, the food details known, and for nutrient estimates the basis, the known values and the keys asked, with the fixed questions or instruction and schema. Every request pins a zero-data-retention endpoint with data collection denied and no fallbacks. The key is the OpenRouter key already approved for the evaluations, read into memory only and never printed or stored. Spend stops at $25 for the programme and $0.05 per call, enforced in the evaluation's own spend ledger before every call; a transient failure is retried at most twice more with backoff that honours `Retry-After`. Raw responses, the cache and the ledger stay in the owner's private evaluation folder; the repository gets counts, versions and hashes only. The sealed set is sent once, by the frozen configuration. Owner approval: 20 November 2026 (CE-T15); programme stop raised from $5 to $25 by the owner on 22 November 2026, sized from the development run's measured cost."

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case missingInCheckout, missingOnOriginMain
        public var description: String {
            switch self {
            case .missingInCheckout: "preflight: the developer tooling paragraph (11.1a) is not in this checkout's docs/privacy-and-egress.md; nothing is sent"
            case .missingOnOriginMain: "preflight: the developer tooling paragraph (11.1a) is not on origin/main; nothing is sent"
            }
        }
    }

    /// Whether `text` holds the paragraph as one line of its own.
    static func holds(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { $0 == Substring(paragraph) }
    }

    public static func check(checkout: String, originMain: String) throws {
        guard holds(checkout) else { throw Refusal.missingInCheckout }
        guard holds(originMain) else { throw Refusal.missingOnOriginMain }
    }
}
