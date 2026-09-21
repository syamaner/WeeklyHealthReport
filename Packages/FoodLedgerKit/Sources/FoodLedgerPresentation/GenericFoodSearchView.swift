import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

public enum GenericFoodSearchPhase: Equatable, Sendable {
    case idle
    case results(GenericFoodConfirmationRoute)
    case noResult(GenericFoodNoResultRoute)
    case declined
    case failed(String)
}

@MainActor
public final class GenericFoodSearchViewModel: ObservableObject {
    @Published public var query = ""
    @Published public private(set) var phase: GenericFoodSearchPhase = .idle
    private let searcher: any GenericFoodSearching
    private let now: @MainActor () -> Date
    private let locale: LedgerText

    public init(
        searcher: any GenericFoodSearching,
        locale: LedgerText,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.searcher = searcher
        self.locale = locale
        self.now = now
    }

    public func search(identity: GenericFoodIdentityQuery = GenericFoodIdentityQuery()) {
        do {
            let text = try LedgerText(query, field: "generic food search")
            switch try searcher.search(GenericFoodSearchRequest(
                text: text,
                identity: identity,
                capturedAt: now(),
                locale: locale
            )) {
            case let .confirmation(route): phase = .results(route)
            case let .noResult(route): phase = .noResult(route)
            }
        } catch FoodLedgerValidationError.empty {
            phase = .failed("Enter a food name before searching.")
        } catch {
            phase = .failed("Local food search could not be completed. Nothing was selected or saved.")
        }
    }

    public func decline() {
        phase = .declined
    }
}

public struct GenericFoodSearchView: View {
    @ObservedObject private var model: GenericFoodSearchViewModel
    private let review: (PopulatedFoodConfirmation) -> Void

    public init(
        model: GenericFoodSearchViewModel,
        review: @escaping (PopulatedFoodConfirmation) -> Void
    ) {
        self.model = model
        self.review = review
    }

    public var body: some View {
        Form {
            Section("Generic food") {
                TextField("Food name", text: $model.query)
                    .submitLabel(.search)
                    .onSubmit { model.search() }
                Button("Search offline") { model.search() }
                    .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            resultSection
        }
        .navigationTitle("Search foods")
    }

    @ViewBuilder
    private var resultSection: some View {
        switch model.phase {
        case .idle:
            Section {
                Text("Searches the bundled, versioned CoFID release. Every result requires your selection.")
                    .font(.caption)
            }
        case let .failed(message):
            Section("Search unavailable") { Label(message, systemImage: "exclamationmark.triangle") }
        case let .noResult(route):
            Section(route.title) {
                Text(route.guidance)
                Text("Your typed query remains available to edit.").font(.caption)
            }
        case .declined:
            Section("No food selected") {
                Text("The candidates were declined. Nothing was saved; edit the query to search again.")
            }
        case let .results(route):
            Section("Ranked candidates") {
                ForEach(Array(route.matches.enumerated()), id: \.offset) { index, match in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(match.candidate.name.value).font(.headline)
                        if let description = match.candidate.variant {
                            Text(description.value).font(.subheadline)
                        }
                        Text(match.isExactName ? "Exact name" : "Closest lexical candidate")
                            .font(.subheadline)
                        if let metadata = match.candidate.candidate.matchMetadata {
                            Text("Score \(metadata.score, format: .number.precision(.fractionLength(3))) · explicit selection required")
                                .font(.caption)
                            ForEach(metadata.materialDifferences, id: \.value) { difference in
                                Text(Self.differenceLabel(difference.value))
                                    .font(.caption)
                            }
                        }
                        Text(match.candidate.candidate.recordID.value)
                            .font(.caption2)
                            .textSelection(.enabled)
                        Button(index == 0 ? "Review this candidate" : "Choose and review") {
                            review(Self.select(index: index, from: route.confirmation))
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
                Text("No candidate is accepted automatically. Review identity, preparation, basis, quantity and all nutrient provenance before saving.")
                    .font(.caption)
                Button("Decline all results", role: .cancel) {
                    model.decline()
                }
            }
        }
    }

    private static func select(
        index: Int,
        from confirmation: PopulatedFoodConfirmation
    ) -> PopulatedFoodConfirmation {
        guard confirmation.candidates.indices.contains(index) else { return confirmation }
        let reordered = [confirmation.candidates[index]]
            + confirmation.candidates.indices.filter { $0 != index }.map { confirmation.candidates[$0] }
        return (try? PopulatedFoodConfirmation(
            evidence: confirmation.evidence,
            sourceReleases: confirmation.sourceReleases,
            candidates: reordered,
            expectedIdentity: confirmation.candidates[index].candidate.identity,
            expectedEdibleQuantity: confirmation.candidates[index].candidate.edibleQuantity
        )) ?? confirmation
    }

    private static func differenceLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "candidate_only_token:", with: "Candidate adds: ")
            .replacingOccurrences(of: "query_only_token:", with: "Query adds: ")
    }
}
