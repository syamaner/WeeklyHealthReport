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
    @Published public var query = "" { didSet { if query != oldValue { amountOverride = nil; invalidateSearch() } } }
    @Published public private(set) var parsedQuery: ParsedFoodQuery?
    @Published public private(set) var interpretation: FoodQueryInterpretation?
    @Published public var preparationFilter: PreparationKind? { didSet { if preparationFilter != oldValue { invalidateSearch() } } }
    /// The amount chip's edited value. Cleared when the description changes.
    @Published public var amountOverride: ParsedFoodQuery.Quantity?
    /// The amount handed to Confirm and used for energy in result rows.
    public var effectiveAmount: ParsedFoodQuery.Quantity? { amountOverride ?? parsedQuery?.quantity }
    /// The preparation actually constraining results (chip or parsed text), if any.
    public var effectivePreparation: PreparationKind? { preparationFilter ?? interpretation?.preparation }
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
        let configuredStages: [FoodSearchStage] = [.local]
            + (onlineDatabaseAvailable ? [.onlineDatabase] : []) + (geminiAvailable ? [.gemini] : [])
        return FoodSearchStatusPresentation(reports: stageReports, pending: activeEnrichmentStage ?? stoppedSearchStage,
            stopped: searchWasStopped, services: services, configuredStages: configuredStages)
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
        if id == "tfda-taiwan" { return "TFDA · Taiwan · on device" }
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
        case .unavailable: return "The source page could not be loaded. No nutrition was added from it."
        case .invalidContent: return "The source page did not pass nutrition verification. No nutrition was added from it."
        case .quotaExceeded: return "The source-page request limit was reached. No retry was made."
        case .timedOut: return "The source-page check timed out. No nutrition was added from it."
        case nil: return nil
        }
    }

    public var searchRecoveryMessage: String? {
        guard activeEnrichmentStage == nil, !searchWasStopped else { return nil }
        var messages = stageReports.compactMap { report in
            report.failure.map { FoodSearchStatusPresentation.recoveryMessage($0, stage: report.stage) }
        }
        if let message = sourceReviewMessage { messages.append(message) }
        if !messages.isEmpty { return messages.joined(separator: "\n\n") }
        if stageReports.contains(where: { $0.stage == .gemini && $0.addedCandidateIDs.isEmpty && $0.hasSourceLinks }) {
            return "Web source links are available, but no extra nutrition matches were added."
        }
        return nil
    }

    public var canRetrySearch: Bool {
        guard activeEnrichmentStage == nil, !searchWasStopped else { return false }
        return stageReports.contains { report in
            if let failure = report.failure { return FoodSearchStatusPresentation.isRetryable(failure) }
            return report.sourceReviewFailure == .timedOut || report.sourceReviewFailure == .unavailable
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
            let requestedPreparation = identity?.preparation?.kind ?? preparationFilter
            if let requestedPreparation, let parsedPreparation, requestedPreparation != parsedPreparation {
                phase = .failed("The preparation in your query conflicts with the selected preparation. Please choose one.")
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
        guard case let .results(route) = phase, let snapshot = route.choosing(index) else { return nil }
        stopEnrichment()
        return snapshot
    }

    public func confirmation(id: FoodSearchCandidateID) -> PopulatedFoodConfirmation? {
        guard case let .results(route) = phase,
              let index = route.matches.firstIndex(where: { $0.searchID == id }) else { return nil }
        return confirmation(at: index)
    }

    /// Structured row facts for a match in the current results.
    public func summary(for match: GenericFoodMatch) -> FoodSearchResultSummary? {
        guard case let .results(route) = phase else { return nil }
        return FoodSearchResultSummary(candidate: match.candidate, releases: route.confirmation.sourceReleases, amount: effectiveAmount)
    }
    public var bestMatches: [GenericFoodMatch] {
        guard case let .results(route) = phase else { return [] }
        let online = Set(onlineAddedIDs)
        return route.matches.filter { !online.contains($0.searchID) }
    }
    public var onlineMatches: [GenericFoodMatch] {
        guard case let .results(route) = phase else { return [] }
        let online = Set(onlineAddedIDs)
        return route.matches.filter { online.contains($0.searchID) }
    }
    /// Developer tools lines for the last search: terms, stage details, lexical scores and
    /// identifiers. Held in memory only; contains no credential.
    public var diagnosticLines: [String] {
        var lines = ["Search terms: \(query)"]
        if let status = searchStatus { lines += status.details }
        if case let .results(route) = phase {
            for match in route.matches {
                lines.append(match.candidate.name.value)
                if let metadata = match.candidate.candidate.matchMetadata {
                    lines.append("Lexical score \(metadata.score.formatted()); not a probability.")
                    lines += metadata.materialDifferences.map(\.value)
                }
                lines.append("Source: \(match.candidate.candidate.sourceReleaseID.value)")
                lines.append("Record: \(match.candidate.candidate.recordID.value)")
            }
        }
        return lines
    }

    public func decline() {
        stopEnrichment()
        phase = .declined
    }
}

/// The developer tools preference shared by Settings and the search screen.
public enum FoodSearchDeveloperTools {
    public static let storageKey = "foodSearchDeveloperToolsEnabled"
}

public struct GenericFoodSearchView: View {
    @ObservedObject private var model: GenericFoodSearchViewModel
    @AppStorage private var developerToolsEnabled: Bool
    private let reviewWebNutrition: (() -> Void)?
    private let scanBarcode: (() -> Void)?
    private let recordDiagnostics: ([String]) -> Void
    private let review: (PopulatedFoodConfirmation) -> Void
    @State private var editsAmount = false

    /// `preferences` must be the store Settings writes the developer tools toggle to.
    public init(model: GenericFoodSearchViewModel, preferences: UserDefaults = .standard,
                reviewWebNutrition: (() -> Void)? = nil, scanBarcode: (() -> Void)? = nil,
                recordDiagnostics: @escaping ([String]) -> Void = { _ in },
                review: @escaping (PopulatedFoodConfirmation) -> Void) {
        self.model = model; self.review = review
        self.reviewWebNutrition = reviewWebNutrition
        self.scanBarcode = scanBarcode
        self.recordDiagnostics = recordDiagnostics
        _developerToolsEnabled = AppStorage(wrappedValue: false, FoodSearchDeveloperTools.storageKey, store: preferences)
    }

    public var body: some View {
        Form {
            Section {
                TextField("Food and amount, e.g. 150 g grilled chicken", text: $model.query)
                    .accessibilityLabel("Food and amount")
                    .submitLabel(.search)
                    .onSubmit { if model.activeEnrichmentStage == nil { model.search() } }
                chips
                if model.phase == .idle, model.activeEnrichmentStage == nil {
                    Button("Search") { model.search() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let line = progressLine {
                Section { line }
            }
            if let message = model.searchRecoveryMessage {
                Section("Search information") {
                    Text(message)
                    if model.canRetrySearch { Button("Search again") { model.search() } }
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
                        }.navigationTitle("Web sources")
                    }
                }
            }
            resultSection
            if showsMissOptions {
                Section("Not what you ate?") {
                    if let reviewWebNutrition {
                        Button(action: reviewWebNutrition) {
                            missRow("Look it up on the web", detail: "Finds a published nutrition source for you to check")
                        }.buttonStyle(.plain)
                    }
                    if let scanBarcode {
                        Button(action: scanBarcode) { missRow("Scan the package barcode", detail: nil) }.buttonStyle(.plain)
                    }
                }
            }
            if let footnote {
                Section { Text(footnote).font(.footnote).foregroundStyle(.secondary) }
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
        .navigationTitle("Search results")
        .sheet(isPresented: $editsAmount) {
            NavigationStack { FoodSearchAmountEditor(initial: model.effectiveAmount) { model.amountOverride = $0 } }
        }
        .onChange(of: model.diagnosticLines) { _, lines in recordDiagnostics(lines) }
        .onDisappear { model.stopEnrichment() }
    }

    @ViewBuilder private var chips: some View {
        HStack(spacing: 8) {
            Button { editsAmount = true } label: {
                Text(model.effectiveAmount.map { "Amount: " + FoodSearchResultText.amount($0) } ?? "Add amount")
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).font(.footnote)
            .accessibilityHint("Change the amount used for energy and on the confirmation")
            Menu {
                Button("Any preparation") { choosePreparation(nil) }
                Button("Raw") { choosePreparation(.raw) }
                Button("Cooked") { choosePreparation(.cooked) }
            } label: {
                Text(FoodSearchResultText.preparationChip(model.effectivePreparation))
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).font(.footnote)
            .accessibilityHint("Raw and cooked are different foods")
        }
        .frame(minHeight: 44)
    }

    private func choosePreparation(_ kind: PreparationKind?) {
        model.preparationFilter = kind
        if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.search() }
    }

    private var progressLine: AnyView? {
        if model.activeEnrichmentStage != nil {
            return AnyView(HStack {
                ProgressView().accessibilityHidden(true)
                Text(model.activeEnrichmentStage == .local ? "Searching…" : "Looking for more matches online…").font(.subheadline)
                Spacer(minLength: 8)
                Button("Stop") { model.stopEnrichment() }.frame(minHeight: 44).accessibilityLabel("Stop searching")
            }.accessibilityElement(children: .contain))
        }
        if model.searchWasStopped {
            return AnyView(Text("Stopped. These are the matches found so far.").font(.subheadline))
        }
        return nil
    }

    private var showsMissOptions: Bool {
        guard model.activeEnrichmentStage == nil, reviewWebNutrition != nil || scanBarcode != nil else { return false }
        switch model.phase {
        case .results, .noResult, .declined: return true
        case .idle, .failed: return false
        }
    }

    private var footnote: String? {
        var parts: [String] = []
        if case .results = model.phase, let preparation = model.effectivePreparation, preparation == .raw || preparation == .cooked {
            parts.append("Raw and cooked are different foods, so only \(preparation.rawValue) matches are shown.")
        }
        if developerToolsEnabled, model.phase != .idle { parts.append("Search details are in Settings › Developer tools.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func missRow(_ title: String, detail: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
        }.frame(minHeight: 44).contentShape(Rectangle())
    }

    @ViewBuilder private var resultSection: some View {
        switch model.phase {
        case .idle: EmptyView()
        case let .failed(message):
            Section(model.parsedQuery?.route == .clarify ? "Check your description" : "Search unavailable") {
                Label(message, systemImage: "exclamationmark.triangle")
            }
        case let .noResult(route):
            Section(model.activeEnrichmentStage != nil ? "No matches yet" : model.stageReports.contains(where: { $0.failure != nil }) ? "Search incomplete" : "No match found") {
                if model.activeEnrichmentStage == nil {
                    if model.searchRecoveryMessage == nil {
                        Text(route.suggestedQueries.isEmpty ? "No food matched this description." : route.guidance)
                    } else {
                        Text("Leave this entry unselected until you have a suitable nutrition match.")
                    }
                    ForEach(route.suggestedQueries, id: \.self) { query in
                        Button("Search \(query)") { model.searchSuggestion(query, from: route) }
                    }
                }
            }
        case .declined:
            Section("No food selected") { Text("Change the description to try again.") }
        case let .results(route):
            if !model.bestMatches.isEmpty {
                Section("Best matches") { ForEach(model.bestMatches, id: \.searchID) { row($0, route: route) } }
            }
            if !model.onlineMatches.isEmpty {
                Section("Added from online database") { ForEach(model.onlineMatches, id: \.searchID) { row($0, route: route) } }
            }
        }
    }

    private func row(_ match: GenericFoodMatch, route: GenericFoodConfirmationRoute) -> some View {
        Button {
            if let confirmation = model.confirmation(id: match.searchID) { review(confirmation) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(match.candidate.name.value).font(.body)
                    if let brand = match.candidate.brand { Text(brand.value).font(.subheadline) }
                    if let summary = model.summary(for: match) {
                        Text(FoodSearchResultText.summaryLine(summary)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = FoodSearchResultText.caution(query: model.parsedQuery, candidate: match.candidate,
                        requestedPreparation: model.preparationFilter,
                        isRecipe: FoodNamedServingPolicy.applies(route.confirmation, candidate: match.candidate)) {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }.foregroundStyle(.primary).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Review this food and the amount before saving")
        .id(match.searchID)
    }
}

/// Locale-aware amount text for the amount chip editor: one number style, grouping off, used
/// for both display and parsing so opening and closing the editor never changes the amount.
public enum FoodSearchAmountText {
    static func style(_ locale: Locale) -> FloatingPointFormatStyle<Double> {
        FloatingPointFormatStyle<Double>(locale: locale).grouping(.never).precision(.fractionLength(0...3))
    }
    public static func text(_ value: Double, locale: Locale) -> String { value.formatted(style(locale)) }
    public static func parse(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = try? style(locale).parseStrategy.parse(trimmed),
              value.isFinite, value > 0 else { return nil }
        return value
    }
}

/// Edits the amount chip: a positive value in grams, millilitres or pieces.
struct FoodSearchAmountEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var value: String?
    @State private var unit: String
    private let initial: ParsedFoodQuery.Quantity?
    private let apply: (ParsedFoodQuery.Quantity?) -> Void
    init(initial: ParsedFoodQuery.Quantity?, apply: @escaping (ParsedFoodQuery.Quantity?) -> Void) {
        self.initial = initial
        _unit = State(initialValue: ["g", "ml", "count"].contains(initial?.unit ?? "") ? initial!.unit : "g")
        self.apply = apply
    }
    var body: some View {
        Form {
            TextField("Amount", text: Binding(get: { value ?? initial.map { FoodSearchAmountText.text($0.value, locale: locale) } ?? "" },
                                              set: { value = $0 }))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Picker("Unit", selection: $unit) {
                Text("g").tag("g"); Text("mL").tag("ml"); Text("pieces").tag("count")
            }.pickerStyle(.segmented)
        }
        .navigationTitle("Amount")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    let text = value ?? initial.map { FoodSearchAmountText.text($0.value, locale: locale) } ?? ""
                    if let number = FoodSearchAmountText.parse(text, locale: locale) { apply(.init(value: number, unit: unit)) }
                    dismiss()
                }
            }
        }
    }
}
