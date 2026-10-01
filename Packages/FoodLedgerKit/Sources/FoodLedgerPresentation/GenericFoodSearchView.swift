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
    @Published public private(set) var interpretation: FoodQueryInterpretation?
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
    @Published public private(set) var stageReports: [FoodSearchStageReport] = []
    @Published public private(set) var searchWasStopped = false
    private var stoppedSearchStage: FoodSearchStage?
    public var searchStatus: FoodSearchStatusPresentation? {
        if case .failed = phase { return nil }
        if case .declined = phase { return nil }
        guard activeEnrichmentStage != nil || !stageReports.isEmpty || stoppedSearchStage != nil else { return nil }
        return FoodSearchStatusPresentation(reports: stageReports, pending: activeEnrichmentStage ?? stoppedSearchStage, stopped: searchWasStopped, services: services)
    }
    /// Explain a skipped web search beside completed results, without making a call.
    public var geminiSetupMessage: String? {
        guard canOfferWebDiscovery, activeEnrichmentStage == nil, !searchWasStopped,
              !stageReports.contains(where: { $0.stage == .gemini }) else { return nil }
        if !geminiAvailable { return nil }
        switch services.gemini {
        case .disabled: return "Gemini is off."
        case .unavailable: return "Gemini needs a validated API key."
        case .ready: return nil
        }
    }

    public var onlineAddedIDs: [FoodSearchCandidateID] {
        stageReports.filter { $0.stage != .local }.flatMap(\.addedCandidateIDs)
    }
    public func sourceLabel(for match: GenericFoodMatch) -> String {
        guard case let .results(route) = phase,
              let release = route.confirmation.sourceReleases.first(where: { $0.sourceReleaseID == match.candidate.candidate.sourceReleaseID }) else { return "Food source" }
        let id = release.sourceID.value.lowercased()
        if id.contains("cofid") { return "CoFID · on device" }
        if id.contains("usda") { return "USDA · on device" }
        if id.contains("openfoodfacts") || id.contains("open-food-facts") { return "Open Food Facts · online" }
        if stageReports.contains(where: { $0.stage == .gemini && $0.addedCandidateIDs.contains(match.searchID) }) { return "Web source" }
        if stageReports.contains(where: { $0.stage == .onlineDatabase && $0.addedCandidateIDs.contains(match.searchID) }) { return "Online food database" }
        return "Saved or on-device food"
    }
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
        stageReports = []; searchWasStopped = false; stoppedSearchStage = nil
        parsedQuery = nil
        interpretation = nil
        phase = .idle
    }

    public func search(identity: GenericFoodIdentityQuery? = nil, retainedEvidence: [CaptureEvidence] = []) {
        stopEnrichment()
        phase = .idle
        enrichmentMessage = nil
        stageReports = []; searchWasStopped = false; stoppedSearchStage = nil
        do {
            let interpretation = FoodQueryInterpretation(query)
            self.interpretation = interpretation
            let parsed = interpretation.parsedQuery
            parsedQuery = parsed
            guard interpretation.allowsDiscovery else {
                phase = .failed(parsed.reasons.contains("empty_query") ? "Enter a food name before searching." : parsed.route == .reject ? "Enter a valid food and a positive quantity, if supplied." : Self.clarificationMessage(parsed))
                return
            }
            let text = try LedgerText(query, field: "generic food search")
            let parsedPreparation = interpretation.preparation
            if let preparationFilter, let parsedPreparation, preparationFilter != parsedPreparation {
                phase = .failed("The preparation in your query conflicts with the selected filter. Please choose one.")
                return
            }
            let identity = try identity ?? GenericFoodIdentityQuery(
                preparation: (preparationFilter ?? parsedPreparation).map { try PreparationState(kind: $0) }
            )
            activeEnrichmentStage = .local
            coordinator.search(GenericFoodSearchRequest(
                text: text,
                identity: identity,
                capturedAt: now(),
                locale: locale,
                additionalEvidence: additionalEvidence + retainedEvidence.filter { retained in
                    !additionalEvidence.contains { $0.evidenceID == retained.evidenceID }
                }, interpretation: interpretation
            ))
        } catch FoodLedgerValidationError.empty {
            phase = .failed("Enter a food name before searching.")
        } catch {
            phase = .failed("Local food search could not be completed. Nothing was selected or saved.")
        }
    }

    private func receive(_ snapshot: ProgressiveFoodSearchSnapshot) {
        stageReports = snapshot.reports
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
        if let activeEnrichmentStage { searchWasStopped = true; stoppedSearchStage = activeEnrichmentStage }
        coordinator.cancel()
        activeEnrichmentStage = nil
    }

    /// Settings changes stop the current run; another submitted search uses the new access.
    public func setServices(_ services: FoodSearchServiceAvailability) {
        guard self.services != services else { return }
        stopEnrichment()
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let webDiscovery: FoodWebDiscoveryViewModel?
    private let review: (PopulatedFoodConfirmation) -> Void

    public init(model: GenericFoodSearchViewModel, webDiscovery: FoodWebDiscoveryViewModel? = nil,
                review: @escaping (PopulatedFoodConfirmation) -> Void) {
        self.model = model; self.webDiscovery = webDiscovery; self.review = review
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    TextField("Food or dish, e.g. scallion pancake", text: $model.query)
                        .accessibilityLabel("Food to search")
                        .submitLabel(.search)
                        .onSubmit { if model.activeEnrichmentStage == nil { model.search() } }
                    DisclosureGroup(model.preparationFilter.map { "Preparation: \($0.rawValue.capitalized)" } ?? "Preparation") {
                        Picker("Preparation", selection: $model.preparationFilter) {
                            Text("Any").tag(Optional<PreparationKind>.none)
                            Text("Raw").tag(Optional(PreparationKind.raw))
                            Text("Cooked").tag(Optional(PreparationKind.cooked))
                        }.pickerStyle(.segmented)
                    }
                    Button("Search") { model.search() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.searchStatus?.isSearching == true)
                }
                resultSection
                if let message = model.geminiSetupMessage {
                    Section {
                        HStack {
                            Text(message).font(.subheadline)
                            Spacer()
                            Button("Search settings") { showsServices = true }.frame(minHeight: 44)
                        }
                    }
                }
                if let discovery = model.sourceDiscovery {
                    Section {
                        NavigationLink("Web sources") {
                            Form {
                                Section("Source pages") {
                                    if let message = model.sourceReviewMessage { Text(message).font(.caption) }
                                    ForEach(Array(discovery.leads.enumerated()), id: \.offset) { _, lead in
                                        if FoodWebLinkPolicy.isAllowed(lead.url) { Link(lead.title, destination: lead.url) }
                                    }
                                }
                                if let html = discovery.searchSuggestionsHTML {
                                    Section("Google Search suggestions") {
                                        FoodWebSearchSuggestions(html: html).frame(minHeight: 200, idealHeight: 240, maxHeight: 320)
                                    }
                                }
                            }.navigationTitle("Web sources")
                        }
                    }
                }
                if !model.additionalEvidence.isEmpty {
                    Section {
                        DisclosureGroup("Entry source") {
                            ForEach(model.additionalEvidence, id: \.evidenceID) { evidence in
                                if case let .barcode(value, _) = evidence.originalPayload {
                                    Text(value.value).textSelection(.enabled)
                                } else if evidence.captureMethod.value == "local-inventory-selection" {
                                    Text("Selected from your reviewed inventory.")
                                }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let status = model.searchStatus {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if status.isSearching { ProgressView().accessibilityHidden(true) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(status.title).font(.subheadline.weight(.semibold))
                                Text(status.summary).font(.caption).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine)
                            Spacer(minLength: 8)
                            if status.isSearching {
                                Button("Stop") { model.stopEnrichment() }.frame(minHeight: 44).accessibilityLabel("Stop searching more sources")
                            }
                        }
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                            : AnyLayout(HStackLayout(alignment: .top))
                        layout {
                            DisclosureGroup("Search details") {
                                ForEach(status.details, id: \.self) { Text($0).font(.caption) }
                            }.font(.caption).frame(minHeight: 44)
                            if let id = model.onlineAddedIDs.first {
                                Button("See added matches") { proxy.scrollTo(id, anchor: .center) }
                                    .font(.caption).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 10)
                    .background(.bar)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
        .navigationTitle("Find a food")
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
                        Text("Your Google account may be charged. Nutrition is added only from supported source pages. Adding a key does not enable automatic search.").font(.caption)
                        if let webDiscovery {
                            NavigationLink("Gemini API key and privacy") {
                                FoodWebDiscoveryView(model: webDiscovery, showsManualSearch: false)
                            }
                        }
                        Text(model.geminiCredentialReady ? "Validated key available for this session." : "Add or revalidate your key before automatic Gemini search is available.").font(.caption)
                    }
                    Section("Advanced") {
                        Toggle("Developer tools", isOn: $developerToolsEnabled)
                    }
                    if developerToolsEnabled {
                        Section("Developer tools") {
                            if case let .results(route) = model.phase {
                                DisclosureGroup("Search diagnostics") {
                                    ForEach(route.matches, id: \.searchID) { match in
                                        Text(match.candidate.name.value)
                                        if let metadata = match.candidate.candidate.matchMetadata {
                                            Text("Lexical score \(metadata.score.formatted()); not a probability.").font(.caption)
                                            ForEach(metadata.materialDifferences, id: \.value) { Text($0.value).font(.caption) }
                                        }
                                        Text("Source: \(match.candidate.candidate.sourceReleaseID.value)").font(.caption)
                                        Text("Record: \(match.candidate.candidate.recordID.value)").font(.caption)
                                    }
                                }
                            }
                            if let webDiscovery, model.canOfferWebDiscovery {
                                NavigationLink("Debug Gemini source discovery") {
                                    FoodWebDiscoveryView(model: webDiscovery).onAppear { webDiscovery.foodTerms = model.query }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Search settings")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsServices = false } } }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { model.stopEnrichment(); showsServices = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Search settings")
            }
        }
        .onDisappear { model.stopEnrichment() }
    }

    @ViewBuilder private var resultSection: some View {
        switch model.phase {
        case .idle: EmptyView()
        case let .failed(message):
            Section(model.parsedQuery?.route == .clarify ? "Check your description" : "Search unavailable") {
                Label(message, systemImage: "exclamationmark.triangle")
            }
        case let .noResult(route):
            Section(model.activeEnrichmentStage == nil ? "No match found" : "No matches yet") {
                if model.activeEnrichmentStage == nil {
                    Text(route.suggestedQueries.isEmpty ? "Try a different food name or leave this entry unselected." : route.guidance)
                    ForEach(route.suggestedQueries, id: \.self) { query in
                        Button("Search \(query)") { model.searchSuggestion(query, from: route) }
                    }
                }
            }
        case .declined:
            Section("No food selected") { Text("Change the description to try again.") }
        case let .results(route):
            Section("Choose a match") {
                ForEach(route.matches, id: \.searchID) { match in
                    Button {
                        if let confirmation = model.confirmation(id: match.searchID) { review(confirmation) }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.candidate.name.value).font(.headline)
                                if let brand = match.candidate.brand { Text(brand.value).font(.subheadline) }
                                Text(model.sourceLabel(for: match) + " · " + FoodSearchResultText.basisLabel(match.candidate.candidate.identity.servingBasis))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let note = FoodSearchResultText.caution(query: model.parsedQuery, candidate: match.candidate,
                                    requestedPreparation: model.preparationFilter,
                                    isRecipe: FoodNamedServingPolicy.applies(route.confirmation, candidate: match.candidate)) {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                                if model.onlineAddedIDs.contains(match.searchID) {
                                    Text("Added online").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.foregroundStyle(.primary).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Review this food and the amount before saving")
                    .id(match.searchID)
                }
                Button("None of these", role: .cancel) { model.decline() }
            }
        }
    }
}
