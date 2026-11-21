import FoodConfirmEnrichment
import Foundation

/// The live connection of `send` without `--fake` (docs/confirm-enrichment-openrouter-v1-phase.md
/// section 3.3 item 5): the app's own `ConfirmEnrichmentTransport`, unchanged, for the keyless catalogue
/// GETs and the two POSTs, so its redirect refusal and destinations are the app's. This is the one file
/// in the tool allowed to name that transport (check-boundaries.sh); no tool file loads URLs itself.
public enum LiveTransport {
    public static func make() -> any ConfirmEnrichmentHTTPTransporting { ConfirmEnrichmentTransport() }
}
