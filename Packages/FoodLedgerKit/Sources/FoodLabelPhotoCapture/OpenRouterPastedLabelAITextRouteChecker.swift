import FoodLedgerApplication
import Foundation

/// The on-the-day catalogue check for the pasted label AI text route (docs/pasted-label-ai-text-v1.md
/// 4.2, 5.4, T1, T3; contract test 21): the photo checker's two free, keyless GETs and its pricing
/// rules, called rather than copied, for a text route only. It refuses any route that is not one of
/// `PastedLabelAITextRoute`'s own (so a photo route is never checked as a text route), and it
/// requires the endpoint to be listed with zero data retention and to take text input. Any failure
/// throws, and nothing is sent.
public struct OpenRouterPastedLabelAITextRouteChecker: Sendable {
    public enum CheckError: Error, Equatable, Sendable {
        /// The route is not a text route (a photo route, or one outside the closed set).
        case notATextRoute
        /// The endpoint is not listed with zero data retention, or does not take text.
        case unavailable
    }

    let photo: OpenRouterLabelRouteChecker
    let clock: any LedgerClock
    let reasoningBilledSeparately: Bool

    public init(transport: any LabelPhotoHTTPTransporting, clock: any LedgerClock, reasoningBilledSeparately: Bool = false) {
        photo = OpenRouterLabelRouteChecker(transport: transport, clock: clock, reasoningBilledSeparately: reasoningBilledSeparately)
        self.clock = clock; self.reasoningBilledSeparately = reasoningBilledSeparately
    }

    /// The photo checker's route shape for the same model and endpoint (its listing and pricing
    /// rules read only these fields). The version stays the text version, which the photo checker refuses.
    static func listingShape(_ route: PastedLabelAITextRoute.Route) -> LabelPhotoRoute.Route {
        LabelPhotoRoute.Route(version: route.version, model: route.model, endpoint: route.endpoint, providerName: route.providerName,
                              maxOutputTokens: route.maxOutputTokens)
    }

    public func check(_ route: PastedLabelAITextRoute.Route) async throws -> LabelPhotoManifest.CatalogueCheck {
        guard PastedLabelAITextRoute.isAdmitted(route), let url = OpenRouterLabelRouteChecker.endpointsURL(Self.listingShape(route)) else {
            throw CheckError.notATextRoute
        }
        let listing = try await photo.fetch(url)
        let zeroDataRetention = try await photo.fetch(OpenRouterLabelRouteChecker.zeroDataRetentionURL)
        return try Self.parse(listing: listing, zeroDataRetention: zeroDataRetention, route: route,
                              at: PastedLabelBasisChoice.milliseconds(clock.now()), reasoningBilledSeparately: reasoningBilledSeparately)
    }

    /// Pure: the photo checker's parse over the same listings, then the text route's own rules.
    public static func parse(listing: Data, zeroDataRetention: Data, route: PastedLabelAITextRoute.Route, at: Int64,
                             reasoningBilledSeparately: Bool = false) throws -> LabelPhotoManifest.CatalogueCheck {
        guard PastedLabelAITextRoute.isAdmitted(route) else { throw CheckError.notATextRoute }
        let check = try OpenRouterLabelRouteChecker.parseListings(listing: listing, zeroDataRetention: zeroDataRetention, model: route.model,
                                                                  endpoint: route.endpoint, at: at, reasoningBilledSeparately: reasoningBilledSeparately)
        guard check.zeroDataRetention, check.inputModalities.contains("text"), check.endpoint == route.endpoint else {
            throw CheckError.unavailable
        }
        return check
    }
}
