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
    @Published public private(set) var activeEnrichmentStage: FoodSearchStage?
    @Published public private(set) var enrichmentMessage: String?
    @Published public private(set) var onlineDatabaseEnabled: Bool
    public let onlineDatabaseAvailable: Bool
    public let geminiAvailable: Bool
    @Published public private(set) var geminiEnabled: Bool
    @Published public private(set) var geminiCredentialReady: Bool
    public var sourceReviewMessage: String? {
        let failure: FoodSourceReviewFailure?
        switch phase {
        case let .results(route): failure = route.sourceReviewFailure
        case let .noResult(route): failure = route.sourceReviewFailure
        default: failure = nil
        }
        switch failure {
        case .unsupportedSource: return "The cited page is not supported for nutrition verification. You can still open its source link."
        case .unavailable: return "The source page could not be loaded. Existing food results remain available."
        case .invalidContent: return "The source page did not pass nutrition verification. No nutrition was added from it."
        case .quotaExceeded: return "The source-page request limit was reached. No retry was made."
        case .timedOut: return "The source-page check timed out. Existing food results remain available."
        case nil: return nil
        }
    }

    public var sourceDiscovery: FoodWebDiscoveryResult? {
        switch phase {
        case let .results(route): route.sourceDiscovery
        case let .noResult(route): route.sourceDiscovery
        default: nil
        }
    }
    private let preferences: (any FoodSearchPreferences)?
    private var services: FoodSearchServiceAvailability
    private let coordinator: ProgressiveFoodSearchCoordinator
    private let now: @MainActor () -> Date
    private let locale: LedgerText
    public let additionalEvidence: [CaptureEvidence]

    public init(
        searcher: any GenericFoodSearching,
        locale: LedgerText,
        additionalEvidence: [CaptureEvidence] = [],
        database: (any FoodSearchEnriching)? = nil,
        gemini: (any FoodSearchEnriching)? = nil,
        services: FoodSearchServiceAvailability = .init(onlineDatabase: .disabled, gemini: .disabled),
        preferences: (any FoodSearchPreferences)? = nil,
        geminiCredentialReady: Bool = false,
        assessment: any FoodSearchCoverageAssessing = ConservativeFoodSearchCoverageAssessment(),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.preferences = preferences
        onlineDatabaseAvailable = database != nil
        geminiAvailable = gemini != nil
        geminiEnabled = preferences?.geminiEnabled ?? (services.gemini == .ready)
        self.geminiCredentialReady = preferences == nil ? services.gemini == .ready : geminiCredentialReady
        onlineDatabaseEnabled = preferences?.onlineDatabaseEnabled ?? (services.onlineDatabase == .ready)
        let services = FoodSearchServiceAvailability(
            onlineDatabase: preferences.map { $0.onlineDatabaseEnabled ? .ready : .disabled } ?? services.onlineDatabase,
            gemini: preferences.map { $0.geminiEnabled ? (geminiCredentialReady ? .ready : .unavailable) : .disabled } ?? services.gemini)
        self.services = services
        coordinator = ProgressiveFoodSearchCoordinator(local: searcher, database: database, gemini: gemini,
            services: services, assessment: assessment)
        self.locale = locale
        self.additionalEvidence = additionalEvidence
        self.now = now
        coordinator.onUpdate = { [weak self] snapshot in self?.receive(snapshot) }
    }

    private func invalidateSearch() {
        stopEnrichment()
        enrichmentMessage = nil
        parsedQuery = nil
        phase = .idle
    }

    public func search(identity: GenericFoodIdentityQuery? = nil, retainedEvidence: [CaptureEvidence] = []) {
        stopEnrichment()
        phase = .idle
        enrichmentMessage = nil
        do {
            let parsed = FoodQueryParser.parse(query)
            parsedQuery = parsed
            guard parsed.allowsCandidateDiscovery else {
                phase = .failed(parsed.reasons.contains("empty_query") ? "Enter a food name before searching." : parsed.route == .reject ? "Enter a valid food and a positive quantity, if supplied." : Self.clarificationMessage(parsed))
                return
            }
            let text = try LedgerText(query, field: "generic food search")
            let parsedPreparation = FoodQueryPreparationPolicy.kind(for: parsed)
            if let preparationFilter, let parsedPreparation, preparationFilter != parsedPreparation {
                phase = .failed("The preparation in your query conflicts with the selected filter. Please choose one.")
                return
            }
            let identity = try identity ?? GenericFoodIdentityQuery(
                preparation: (preparationFilter ?? parsedPreparation).map { try PreparationState(kind: $0) }
            )
            coordinator.search(GenericFoodSearchRequest(
                text: text,
                identity: identity,
                capturedAt: now(),
                locale: locale,
                additionalEvidence: additionalEvidence + retainedEvidence.filter { retained in
                    !additionalEvidence.contains { $0.evidenceID == retained.evidenceID }
                }
            ))
        } catch FoodLedgerValidationError.empty {
            phase = .failed("Enter a food name before searching.")
        } catch {
            phase = .failed("Local food search could not be completed. Nothing was selected or saved.")
        }
    }

    private func receive(_ snapshot: ProgressiveFoodSearchSnapshot) {
        activeEnrichmentStage = snapshot.pending
        enrichmentMessage = snapshot.failures.isEmpty ? nil : "Some sources could not be checked. Available results are kept."
        switch snapshot.outcome {
        case let .confirmation(route): phase = .results(route)
        case let .noResult(route): phase = .noResult(route)
        case nil:
            phase = snapshot.pending == nil ? .failed("Food search could not be completed. Nothing was selected or saved.") : .idle
        }
    }

    public func stopEnrichment() {
        coordinator.cancel()
        activeEnrichmentStage = nil
    }

    /// Settings changes stop the current run; another submitted search uses the new access.
    public func setServices(_ services: FoodSearchServiceAvailability) {
        self.services = services
        coordinator.setServices(services)
    }

    public func setOnlineDatabaseEnabled(_ enabled: Bool) {
        guard enabled != onlineDatabaseEnabled else { return }
        preferences?.onlineDatabaseEnabled = enabled
        onlineDatabaseEnabled = enabled
        setServices(FoodSearchServiceAvailability(onlineDatabase: enabled ? .ready : .disabled, gemini: services.gemini))
    }

    public func setGeminiEnabled(_ enabled: Bool) {
        guard enabled != geminiEnabled else { return }
        preferences?.geminiEnabled = enabled
        geminiEnabled = enabled
        refreshGeminiAvailability()
    }

    public func setGeminiCredentialReady(_ ready: Bool) {
        guard ready != geminiCredentialReady else { return }
        geminiCredentialReady = ready
        refreshGeminiAvailability()
    }

    private func refreshGeminiAvailability() {
        setServices(.init(onlineDatabase: services.onlineDatabase,
            gemini: geminiEnabled ? (geminiCredentialReady ? .ready : .unavailable) : .disabled))
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
        guard let snapshot = try? PopulatedFoodConfirmation(evidence: input.evidence, sourceReleases: input.sourceReleases,
            candidates: [chosen] + input.candidates.indices.filter { $0 != index }.map { input.candidates[$0] },
            expectedIdentity: chosen.candidate.identity, expectedEdibleQuantity: chosen.candidate.edibleQuantity) else { return nil }
        stopEnrichment()
        return snapshot
    }

    public func confirmation(id: FoodSearchCandidateID) -> PopulatedFoodConfirmation? {
        guard case let .results(route) = phase,
              let index = route.matches.firstIndex(where: { $0.searchID == id }) else { return nil }
        return confirmation(at: index)
    }

    public func decline() {
        stopEnrichment()
        phase = .declined
    }
}

public struct GenericFoodSearchView: View {
    @ObservedObject private var model: GenericFoodSearchViewModel
    @AppStorage("foodSearchDeveloperToolsEnabled") private var developerToolsEnabled = false
    @State private var showsServices = false
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
            Section("Food search") {
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
                Button("Search") { model.search() }
                    .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message = model.parsedQuery?.discoveryReviewMessage {
                Section { Text(message).font(.caption) }
            }
            resultSection
            if activeEnrichment {
                Section {
                    ProgressView("Checking more sources…")
                    Text("You can choose an available result now.").font(.caption)
                }
            }
            if let message = model.enrichmentMessage {
                Section { Text(message).font(.caption) }
            }
            if let discovery = model.sourceDiscovery {
                Section("Web source discovery") {
                    if let message = model.sourceReviewMessage { Text(message).font(.caption) }
                    Text("These are discovery links. Nutrition is added only after a supported source page passes verification.").font(.caption)
                    DisclosureGroup("Source pages") {
                        ForEach(Array(discovery.leads.enumerated()), id: \.offset) { _, lead in
                            if FoodWebLinkPolicy.isAllowed(lead.url) { Link(lead.title, destination: lead.url) }
                        }
                    }
                    if let html = discovery.searchSuggestionsHTML {
                        FoodWebSearchSuggestions(html: html)
                            .frame(minHeight: 200, idealHeight: 240, maxHeight: 320)
                    }
                }
            }
            if developerToolsEnabled, let webDiscovery, model.canOfferWebDiscovery {
                Section("Developer tools") {
                    NavigationLink("Debug Gemini source discovery") {
                        FoodWebDiscoveryView(model: webDiscovery)
                            .onAppear { webDiscovery.foodTerms = model.query }
                    }
                    Text("Manual citation-only discovery. These leads cannot populate nutrition.").font(.caption)
                }
            }
        }
        .navigationTitle("Search foods")
        .sheet(isPresented: $showsServices) {
            NavigationStack {
                Form {
                    Section("Online food database") {
                        Toggle("Open Food Facts", isOn: Binding(get: { model.onlineDatabaseEnabled }, set: { model.setOnlineDatabaseEnabled($0) }))
                            .disabled(!model.onlineDatabaseAvailable)
                        Text("When local matches need more evidence, a submitted search can send the displayed food terms to Open Food Facts. No account or API key is needed. Your HealthKit data, food log and saved-food history are not sent.")
                        Text("Community product data can be incomplete. Compare the package and nutrition basis before choosing. Changing this setting takes effect on your next search.").font(.caption)
                        Link("Open Food Facts terms and data licences", destination: URL(string: "https://world.openfoodfacts.org/terms-of-use")!)
                    }
                    Section("Gemini") {
                        Toggle("Automatic Gemini search", isOn: Binding(get: { model.geminiEnabled }, set: { model.setGeminiEnabled($0) }))
                            .disabled(!model.geminiAvailable)
                        Text("When other results need more evidence, a submitted search can send the displayed food terms to Google and check one cited source page. Your HealthKit data, food log and saved-food history are not sent.")
                        Text("Your Google account may be charged. Verified nutrition currently supports compatible Alpro, Arla and Oatly UK product pages. Unsupported pages cannot add nutrition. Existing keys do not enable this setting.").font(.caption)
                        if let webDiscovery {
                            NavigationLink("Gemini API key and privacy") {
                                FoodWebDiscoveryView(model: webDiscovery, showsManualSearch: false)
                            }
                        }
                        Text(model.geminiCredentialReady ? "Validated key available for this session." : "Add or revalidate your key before automatic Gemini search is available.").font(.caption)
                    }
                }
                .navigationTitle("Search services")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsServices = false } } }
            }
        }
        .toolbar {
            ToolbarItem {
                ProgressView()
                    .opacity(activeEnrichment ? 1 : 0)
                    .accessibilityLabel("Checking more sources")
                    .accessibilityHidden(!activeEnrichment)
            }
            ToolbarItem {
                Menu {
                    Button("Search services") {
                        model.stopEnrichment()
                        showsServices = true
                    }
                    Toggle("Developer tools", isOn: $developerToolsEnabled)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Search options")
            }
        }
        .onDisappear { model.stopEnrichment() }
    }

    private var activeEnrichment: Bool {
        model.activeEnrichmentStage == .onlineDatabase || model.activeEnrichmentStage == .gemini
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
                ForEach(Array(route.matches.enumerated()), id: \.element.searchID) { index, match in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(match.candidate.name.value).font(.headline)
                        if let brand = match.candidate.brand { Text(brand.value).font(.subheadline) }
                        if let description = match.candidate.variant {
                            Text(description.value).font(.subheadline)
                        }
                        Text(match.isExactName ? "Exact name" : "Food name match")
                            .font(.subheadline)
                        if let parsed = model.parsedQuery, let note = FoodQueryCandidateAssessment.note(query: parsed, candidate: match.candidate, requestedPreparation: model.preparationFilter) {
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
                            if let confirmation = model.confirmation(id: match.searchID) { review(confirmation) }
                        }
                        .buttonStyle(.borderless)
                    }
                    .accessibilityElement(children: .contain)
                }
                Text("No candidate is accepted automatically. Review identity, preparation, basis, quantity and all nutrient provenance before saving.")
                    .font(.caption)
                Button("None of these", role: .cancel) {
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
