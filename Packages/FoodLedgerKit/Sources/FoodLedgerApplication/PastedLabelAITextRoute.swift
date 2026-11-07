import Foundation

/// The routes of the pasted label AI text route (docs/pasted-label-ai-text-v1.md 4.2, 5.4 and T3):
/// its own closed set, separate from `LabelPhotoRoute`, so a photo route is never sent as a text
/// route and the reverse. A route pins one model on one zero-data-retention endpoint.
///
/// No route is shipped yet: the evaluation (A3) compares the candidates below and freezes one,
/// which then becomes `current`. Until then `current` is nil and nothing in the product can send.
/// A candidate is added only after its endpoint is confirmed in OpenRouter's catalogue on the day
/// (5.4), so the set is append-only and reviewed like any route change.
public enum PastedLabelAITextRoute {
    /// The route version every text route records (4.5). A later route (another model) is a new version.
    public static let version = "pasted-label-ai-text-route-v1"

    public struct Route: Equatable, Sendable {
        /// The text route version; never a photo route version.
        public let version: String
        /// The evaluation's name for the candidate (`gemini-4-argon-vertex-us`), recorded in each run.
        public let candidateID: String
        public let model: String
        /// The OpenRouter endpoint tag the request pins in `only` and `order`.
        public let endpoint: String
        /// The provider name OpenRouter returns for that endpoint, compared after normalisation.
        public let providerName: String
        /// The request's `max_tokens`.
        public let maxOutputTokens: Int
        /// The request's reasoning limit.
        public let reasoningLimit: Int

        public init(version: String, candidateID: String, model: String, endpoint: String, providerName: String, maxOutputTokens: Int,
                    reasoningLimit: Int) {
            self.version = version; self.candidateID = candidateID; self.model = model; self.endpoint = endpoint
            self.providerName = providerName; self.maxOutputTokens = maxOutputTokens; self.reasoningLimit = reasoningLimit
        }
    }

    /// Gemini 4 Argon on Google Vertex's US endpoint, the endpoint the photo route qualified as
    /// zero-data-retention listed (photo spec 17.21). Re-confirmed on the day before any A3 run.
    public static let gemini4ArgonVertexUS = Route(version: version, candidateID: "gemini-4-argon-vertex-us", model: "google/gemini-4-argon",
                                                   endpoint: "google-vertex/us", providerName: "Google", maxOutputTokens: 2_400,
                                                   reasoningLimit: 500)

    /// Closed and append-only: the candidates an evaluation cell may name.
    public static let candidates: [Route] = [gemini4ArgonVertexUS]

    /// The one shipped route; nil until A3 freezes one.
    public static let current: Route? = nil

    /// Whether a route is one of the text route's own (its version and its fields as listed).
    public static func isAdmitted(_ route: Route) -> Bool { route.version == version && candidates.contains(route) }

    public static func candidate(_ id: String) -> Route? { candidates.first { $0.candidateID == id } }
}
