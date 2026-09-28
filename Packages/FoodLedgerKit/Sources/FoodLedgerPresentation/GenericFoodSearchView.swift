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
    @Published public var query = "" { didSet { if query != oldValue { invalidateSearch() } } }
    @Published public private(set) var parsedQuery: ParsedFoodQuery?
    @Published public var preparationFilter: PreparationKind? { didSet { if preparationFilter != oldValue { invalidateSearch() } } }
    @Published public private(set) var phase: GenericFoodSearchPhase = .idle
    public var canOfferWebDiscovery: Bool {
        switch phase {
        case .results, .noResult: true
        case .idle, .declined, .failed: false
        }
    }
    private let searcher: any GenericFoodSearching
    private let now: @MainActor () -> Date
    private let locale: LedgerText
    public let additionalEvidence: [CaptureEvidence]

    public init(
        searcher: any GenericFoodSearching,
        locale: LedgerText,
        additionalEvidence: [CaptureEvidence] = [],
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.searcher = searcher
        self.locale = locale
        self.additionalEvidence = additionalEvidence
        self.now = now
    }

    private func invalidateSearch() {
        parsedQuery = nil
        phase = .idle
    }

    public func search(identity: GenericFoodIdentityQuery? = nil, retainedEvidence: [CaptureEvidence] = []) {
        do {
            let parsed = FoodQueryParser.parse(query)
            parsedQuery = parsed
            guard parsed.route == .search else {
                phase = .failed(parsed.reasons.contains("empty_query") ? "Enter a food name before searching." : parsed.route == .reject ? "Enter a valid food and a positive quantity, if supplied." : Self.clarificationMessage(parsed))
                return
            }
            let text = try LedgerText(query, field: "generic food search")
            let parsedPreparation = parsed.attributes["preparation"].flatMap(PreparationKind.init(rawValue:))
            if let preparationFilter, let parsedPreparation, preparationFilter != parsedPreparation {
                phase = .failed("The preparation in your query conflicts with the selected filter. Please choose one.")
                return
            }
            let identity = try identity ?? GenericFoodIdentityQuery(
                preparation: (preparationFilter ?? parsedPreparation).map { try PreparationState(kind: $0) }
            )
            switch try searcher.search(GenericFoodSearchRequest(
                text: text,
                identity: identity,
                capturedAt: now(),
                locale: locale,
                additionalEvidence: additionalEvidence + retainedEvidence.filter { retained in
                    !additionalEvidence.contains { $0.evidenceID == retained.evidenceID }
                }
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

    private static func clarificationMessage(_ parsed: ParsedFoodQuery) -> String {
        if parsed.reasons.contains("quantity_is_not_exact") {
            return "Enter the actual consumed amount. A bound or approximate quantity cannot prefill an exact amount. Your input is kept; nothing was saved."
        }
        if parsed.reasons.contains("grounds_are_not_drink_weight") {
            return "Enter the amount of brewed coffee separately from the dry grounds. Your input is kept; nothing was saved."
        }
        if parsed.reasons.contains("portion_requires_confirmation") || parsed.reasons.contains("fraction_requires_portion_confirmation") {
            return "Please specify the portion in grams or millilitres, or choose a food with a defined serving. Your input is kept; nothing was saved."
        }
        return "Please search one food at a time and resolve any conflicting amounts or descriptions. Your input is kept; nothing was saved."
    }

    public func searchSuggestion(_ suggestion: String, from route: GenericFoodNoResultRoute) {
        guard case let .noResult(current) = phase, current == route, route.suggestedQueries.contains(suggestion) else { return }
        query = suggestion
        search(retainedEvidence: route.retainedEvidence)
    }

    /// Snapshot the explicitly chosen candidate; invalid indices never fall back to another food.
    public func confirmation(at index: Int) -> PopulatedFoodConfirmation? {
        guard case let .results(route) = phase, route.confirmation.candidates.indices.contains(index) else { return nil }
        let input = route.confirmation
        let chosen = input.candidates[index]
        return try? PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases,
            candidates: [chosen] + input.candidates.indices.filter { $0 != index }.map { input.candidates[$0] },
            expectedIdentity: chosen.candidate.identity, expectedEdibleQuantity: chosen.candidate.edibleQuantity)
    }

    public func decline() {
        phase = .declined
    }
}

public struct GenericFoodSearchView: View {
    @ObservedObject private var model: GenericFoodSearchViewModel
    private let webDiscovery: FoodWebDiscoveryViewModel?
    private let review: (PopulatedFoodConfirmation) -> Void

    public init(
        model: GenericFoodSearchViewModel,
        webDiscovery: FoodWebDiscoveryViewModel? = nil,
        review: @escaping (PopulatedFoodConfirmation) -> Void
    ) {
        self.model = model
        self.webDiscovery = webDiscovery
        self.review = review
    }

    public var body: some View {
        Form {
            if !model.additionalEvidence.isEmpty {
                Section("Source evidence kept with this entry") {
                    ForEach(model.additionalEvidence, id: \.evidenceID) { evidence in
                        if case let .barcode(value, _) = evidence.originalPayload {
                            Text(value.value).textSelection(.enabled)
                        } else if evidence.captureMethod.value == "local-inventory-selection" {
                            Text("Selected from your reviewed local inventory. Product and pack references are retained.")
                        }
                    }
                    Text("Choose the food that matches your item. Capture or inventory evidence alone does not establish consumed quantity or nutrition.")
                        .font(.caption)
                }
            }
            Section("Generic food") {
                VStack(alignment: .leading) {
                    Text("Food name").font(.caption)
                    TextField("e.g. 200g Greek yoghurt 10% fat", text: $model.query)
                        .submitLabel(.search)
                        .onSubmit { model.search() }
                }
                Picker("Preparation", selection: $model.preparationFilter) {
                    Text("Any").tag(Optional<PreparationKind>.none)
                    Text("Raw").tag(Optional(PreparationKind.raw))
                    Text("Cooked").tag(Optional(PreparationKind.cooked))
                }
                .pickerStyle(.segmented)
                Button("Search offline") { model.search() }
                    .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            resultSection
            if let webDiscovery, model.canOfferWebDiscovery {
                Section("Beyond the bundled catalogues") {
                    NavigationLink("Search the web") {
                        FoodWebDiscoveryView(model: webDiscovery)
                            .onAppear { webDiscovery.foodTerms = model.query }
                    }
                    Text("Optional Gemini source leads with your own API key. No food is selected or saved.").font(.caption)
                }
            }
        }
        .navigationTitle("Search foods")
    }

    @ViewBuilder
    private var resultSection: some View {
        switch model.phase {
        case .idle:
            Section {
                Text("Searches bundled UK CoFID and US USDA composition estimates offline. Source records remain separate; every result requires your selection.")
                    .font(.caption)
            }
        case let .failed(message):
            Section(model.parsedQuery?.route == .clarify ? "Clarification needed" : "Search unavailable") { Label(message, systemImage: "exclamationmark.triangle") }
        case let .noResult(route):
            Section(route.title) {
                Text(route.guidance)
                ForEach(route.suggestedQueries, id: \.self) { query in
                    Button("Search \(query)") {
                        model.searchSuggestion(query, from: route)
                    }
                }
                Text("Your typed query remains available to edit.").font(.caption)
            }
        case .declined:
            Section("No food selected") {
                Text("The candidates were declined. Nothing was saved; edit the query to search again.")
            }
        case let .results(route):
            Section("Choose a food") {
                if let parsed = model.parsedQuery, !parsed.attributes.isEmpty {
                    Text("Requested: " + parsed.attributes.sorted { $0.key < $1.key }.map { $0.key.replacingOccurrences(of: "_", with: " ") + ": " + $0.value }.joined(separator: "; "))
                    Text("These are food-name candidates. The requested variant is not verified; compare the source details before accepting an alternative.").font(.caption)
                }
                ForEach(Array(route.matches.enumerated()), id: \.offset) { index, match in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(match.candidate.name.value).font(.headline)
                        if let description = match.candidate.variant {
                            Text(description.value).font(.subheadline)
                        }
                        Text(match.isExactName ? "Exact name" : "Food name match")
                            .font(.subheadline)
                        if let parsed = model.parsedQuery, let note = FoodQueryCandidateAssessment.note(query: parsed, candidate: match.candidate) {
                            Text(note).font(.caption)
                        }
                        Text("Preparation: \(match.candidate.candidate.identity.preparation.kind.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Source and matching details") {
                            if let metadata = match.candidate.candidate.matchMetadata {
                                ForEach(metadata.materialDifferences, id: \.value) { difference in
                                    Text(Self.differenceLabel(difference.value)).font(.caption)
                                }
                                Text("Lexical score \(metadata.score, format: .number.precision(.fractionLength(3))); not a probability of correctness.")
                                    .font(.caption)
                            }
                            Text("Source: \(match.candidate.candidate.sourceReleaseID.value)").font(.caption2).textSelection(.enabled)
                            Text("Record: \(match.candidate.candidate.recordID.value)").font(.caption2).textSelection(.enabled)
                        }
                        Button(index == 0 ? "Review this candidate" : "Choose and review") {
                            if let confirmation = model.confirmation(at: index) { review(confirmation) }
                        }
                        .buttonStyle(.borderless)
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

    private static func differenceLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "candidate_only_token:", with: "Candidate adds: ")
            .replacingOccurrences(of: "query_only_token:", with: "Query adds: ")
    }
}
