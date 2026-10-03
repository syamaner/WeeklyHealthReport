import CryptoKit
import Foundation
import FoodLedgerApplication

/// One discovery call, one native-cited source job, no model-written URL or numeric admission.
public actor GeminiGroundedSourceReview: FoodGroundedSourceReviewing {
    public static let version = "gemini-grounded-source-review-v4"
    public static let deadline: Duration = .seconds(50)
    public static let citationResolverHost = "vertexaisearch.cloud.google.com"
    private let discovery: any FoodWebDiscovering
    private let acquisition: any FoodSourcePageAcquiring
    private let requestPolicy: FoodSourceURLPolicy
    private let contentPolicy: FoodSourceURLPolicy
    private let timeout: Duration
    private var active = false

    public init(discovery: any FoodWebDiscovering, acquisition: any FoodSourcePageAcquiring,
                contentHosts: Set<String>, timeout: Duration = GeminiGroundedSourceReview.deadline) throws {
        guard !contentHosts.map({ $0.lowercased() }).contains(Self.citationResolverHost) else {
            throw FoodSourceAcquisitionError.hostNotAdmitted
        }
        self.discovery = discovery; self.acquisition = acquisition
        contentPolicy = try FoodSourceURLPolicy(allowedHosts: contentHosts)
        requestPolicy = try FoodSourceURLPolicy(allowedHosts: contentHosts.union([Self.citationResolverHost]))
        self.timeout = min(max(timeout, .milliseconds(1)), Self.deadline)
    }

    public func review(foodTerms: String, key: String) async throws -> FoodGroundedSourceReview {
        try Task.checkCancellation()
        let terms = foodTerms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty, terms.count <= 300, !terms.contains(key) else { throw FoodWebDiscoveryError.invalidQuery }
        guard FoodWebKeySyntax.isValid(key) else { throw FoodWebDiscoveryError.credentialRejected }
        guard !active else { throw FoodSourceAcquisitionError.quotaExceeded }
        active = true
        defer { active = false }
        let timeout = timeout
        let expires = ContinuousClock.now.advanced(by: timeout)
        return try await withThrowingTaskGroup(of: FoodGroundedSourceReview.self) { group in
            group.addTask { try await self.run(terms: terms, key: key, expires: expires) }
            group.addTask { try await Task.sleep(for: timeout); throw FoodSourceAcquisitionError.timedOut }
            defer { group.cancelAll() }
            let result = try await group.next()!
            try Self.check(expires)
            return result
        }
    }

    private func run(terms: String, key: String, expires: ContinuousClock.Instant) async throws -> FoodGroundedSourceReview {
        let result = try await discovery.discover(foodTerms: terms, key: key)
        try Self.check(expires)
        // Provider annotations alone supply leads. Response prose, written links and titles cannot select a URL.
        guard let selected = result.leads.first(where: { (try? requestPolicy.canonicalURL($0.url)) != nil }) else {
            if !result.leads.isEmpty {
                throw FoodGroundedSourcePartialFailure(discovery: result, reason: .unsupportedSource)
            }
            return FoodGroundedSourceReview(discovery: result, source: nil)
        }
        do {
            let page = try await acquisition.acquire(selected.url)
            try Self.check(expires)
            try validate(page, selected: selected)
            let recipe = try? WPRecipeSourceParser.profile(page.html, sourceURL: page.finalURL)
            var panels: [FoodSourceNutritionPanel] = []
            do {
                let projection = try HTMLFoodSourceTableProjector.project(page.html)
                panels = try FoodSourceDocumentPanelReader.panels(projection,
                    documentID: "sha256:" + page.sha256, recordID: page.finalURL.absoluteString)
            } catch {
                if recipe == nil { throw error }
            }
            try Self.check(expires)
            return FoodGroundedSourceReview(discovery: result,
                source: FoodReviewedSource(citation: selected, page: page, panels: panels, recipes: recipe.map { [$0] } ?? []))
        } catch {
            try Self.check(expires)
            if error is CancellationError { throw error }
            let reason: FoodSourceReviewFailure
            switch error as? FoodSourceAcquisitionError {
            case .hostNotAdmitted, .invalidURL: reason = .unsupportedSource
            case .quotaExceeded, .requestLimit: reason = .quotaExceeded
            case .timedOut: reason = .timedOut
            case .unavailable: reason = .unavailable
            default: reason = .invalidContent
            }
            throw FoodGroundedSourcePartialFailure(discovery: result, reason: reason)
        }

    }

    private func validate(_ page: AcquiredFoodSourcePage, selected: FoodWebLead) throws {
        guard page.requestedURL == selected.url, !page.html.isEmpty,
              page.html.count <= HTTPSFoodSourcePageAcquirer.maximumBytes,
              page.hops.count > 0, page.hops.count <= HTTPSFoodSourcePageAcquirer.maximumRequests,
              page.sha256 == SHA256.hash(data: page.html).map({ String(format: "%02x", $0) }).joined(),
              page.hops.first?.url == (try requestPolicy.canonicalURL(selected.url)),
              page.hops.last?.url == page.finalURL, page.hops.last?.status == 200,
              Set(page.hops.map(\.url)).count == page.hops.count,
              try contentPolicy.canonicalURL(page.finalURL) == page.finalURL else {
            throw FoodSourceAcquisitionError.invalidResponse
        }
        for (index, hop) in page.hops.enumerated() {
            guard try requestPolicy.canonicalURL(hop.url) == hop.url,
                  index == page.hops.count - 1 || [301, 302, 303, 307, 308].contains(hop.status) else {
                throw FoodSourceAcquisitionError.invalidResponse
            }
        }
    }

    private static func check(_ expires: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < expires else { throw FoodSourceAcquisitionError.timedOut }
    }
}
