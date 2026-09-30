import Foundation

/// Source-content correspondence only; neither a selected food nor permission to save.
public struct FoodGroundedSourceReview: Equatable, Sendable {
    public let discovery: FoodWebDiscoveryResult
    public let source: FoodReviewedSource?
    public init(discovery: FoodWebDiscoveryResult, source: FoodReviewedSource?) {
        self.discovery = discovery; self.source = source
    }
}

public struct FoodReviewedSource: Equatable, Sendable {
    public let citation: FoodWebLead
    public let page: AcquiredFoodSourcePage
    public let panels: [FoodSourceNutritionPanel]
    public init(citation: FoodWebLead, page: AcquiredFoodSourcePage, panels: [FoodSourceNutritionPanel]) {
        self.citation = citation; self.page = page; self.panels = panels
    }
}

/// Only displayed food terms and a separately validated credential cross this boundary.
public protocol FoodGroundedSourceReviewing: Sendable {
    func review(foodTerms: String, key: String) async throws -> FoodGroundedSourceReview
}

/// A completed discovery whose selected source could not be independently verified.
/// It carries no admissible page, candidate, nutrition values or credential status.
public struct FoodGroundedSourcePartialFailure: Error, Equatable, Sendable {
    public let discovery: FoodWebDiscoveryResult
    public let reason: FoodSourceReviewFailure
    public init(discovery: FoodWebDiscoveryResult, reason: FoodSourceReviewFailure) {
        self.discovery = discovery; self.reason = reason
    }
}

public enum FoodSourceReviewFailure: Equatable, Sendable {
    case unsupportedSource, unavailable, invalidContent, quotaExceeded, timedOut
}
