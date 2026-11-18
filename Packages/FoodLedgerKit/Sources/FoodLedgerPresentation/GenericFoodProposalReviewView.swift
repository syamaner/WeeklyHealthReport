import Foundation
import SwiftUI
import FoodLedgerApplication
import FoodLedgerDomain

public enum FoodReviewMarket: String, CaseIterable, Identifiable {
    case unspecified = "Unspecified", taiwan = "Taiwan", unitedKingdom = "United Kingdom"
    public var id: String { rawValue }
}

@MainActor
public final class GenericFoodProposalReviewViewModel: ObservableObject {
    @Published public var foodTerms = "" { didSet { if foodTerms != oldValue { knownSources = []; cancel() } } }
    @Published public var market: FoodReviewMarket { didSet {
        if market != oldValue { knownSources = []; cancel(); saveMarket(market) }
    } }
    @Published public var sourceAddress = "" { didSet { if sourceAddress != oldValue { cancel() } } }
    @Published public private(set) var isSearching = false
    @Published public private(set) var result: GenericFoodProposalReview? {
        // A new result starts at its pre-selection (none under a clarify answer), never a model pick.
        didSet { if result != oldValue { pickedID = result?.offer.preselectedID } }
    }
    /// The panel the person has selected among the offered candidates (#508 phase 2).
    @Published public private(set) var pickedID: String?
    @Published public private(set) var message: String?
    @Published public private(set) var alternativeSources: [FoodWebLead] = []
    private let saveMarket: (FoodReviewMarket) -> Void
    private let reviewer: any GenericFoodProposalReviewing
    private let credentials: any FoodWebCredentialAuthorizing
    private let confirmation: ReviewedFoodProposalConfirmation
    private let locale: LedgerText
    private var generation = 0
    private var task: Task<GenericFoodProposalReview, Error>?
    private var resultCredential: FoodWebRequestCredential?
    private var knownSources: [FoodWebLead] = []

    public init(reviewer: any GenericFoodProposalReviewing, credentials: any FoodWebCredentialAuthorizing,
                confirmation: ReviewedFoodProposalConfirmation, locale: LedgerText,
                initialMarket: FoodReviewMarket = .unspecified,
                saveMarket: @escaping (FoodReviewMarket) -> Void = { _ in }) {
        self.reviewer = reviewer; self.credentials = credentials; self.confirmation = confirmation; self.locale = locale
        self.market = initialMarket; self.saveMarket = saveMarket
    }
    public var requestTerms: String {
        let query = foodTerms.trimmingCharacters(in: .whitespacesAndNewlines)
        return market == .unspecified || query.isEmpty ? query : query + " [market: " + market.rawValue + "]"
    }
    public var canSearch: Bool {
        let query = requestTerms
        return !isSearching && !query.isEmpty && query.count <= 300
    }
    public func search() async {
        guard canSearch else { return }
        cancel()
        let current = generation
        let query = requestTerms
        let address = sourceAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = address.isEmpty ? nil : URL(string: address)
        guard address.isEmpty || url.map(FoodWebLinkPolicy.isAllowed) == true else {
            message = "Enter a public HTTPS source address, or leave it empty to search."; return
        }
        let credential: FoodWebRequestCredential
        do { credential = try credentials.credentialForRequest() }
        catch { message = "Add or revalidate your OpenRouter key first."; return }
        isSearching = true
        let task = Task { [reviewer] in try await reviewer.review(foodTerms: query, sourceURL: url, key: credential.key) }
        self.task = task
        do {
            let value = try await task.value
            guard generation == current, credentials.isCurrent(credential) else {
                if generation == current { cancel(); message = "The key changed. Revalidate it and search again." }
                return
            }
            guard value.foodTerms == query else { throw GenericFoodProposalError.invalidSchema }
            resultCredential = credential
            result = value
            publishOtherSources(value.discovery, attemptedURL: value.attemptedSourceURL ?? url)
            if value.validation.candidates.isEmpty {
                message = value.validation.rejected.isEmpty
                    ? "No nutrition proposal was extracted from the captured text. The page may lack a food-specific declaration or usable serving basis, or its nutrition may be in an image. Open the captured page to inspect it, or review another source."
                    : "Extracted proposals failed the source checks. Details are in Settings › Developer tools. Inspect the captured page before reviewing another source."
            }
        } catch {
            guard generation == current else { return }
            guard credentials.isCurrent(credential) else {
                cancel(); message = "The key changed. Revalidate it and search again."; return
            }
            if error as? FoodWebDiscoveryError == .credentialRejected { credentials.reject(credential) }
            if let partial = error as? GenericFoodProposalPartialFailure { publishOtherSources(partial.discovery, attemptedURL: partial.attemptedSourceURL ?? url) }
            message = Self.message(error)
            if let partial = error as? GenericFoodProposalPartialFailure, partial.sourceAttempts.count > 1 {
                message = "Two different source pages were attempted. " + (message ?? "")
            }
        }
        if generation == current { isSearching = false; self.task = nil }
    }
    /// The single review step. The view model keeps only the stale-query and credential checks;
    /// the applicability gate and representative-only rule are enforced by the application.
    public func prepare(_ expected: BoundFoodProposal, querySnapshot: String,
                        scope: FoodProposalReviewScope) throws -> PopulatedFoodConfirmation {
        guard let resultCredential, credentials.isCurrent(resultCredential) else {
            cancel()
            throw GenericFoodProposalError.invalidSelection
        }
        // Only the panel the person has selected can be prepared; under a clarify answer nothing is
        // selected until they pick one (#508 phase 2).
        guard let result, result.foodTerms == requestTerms, result.foodTerms == querySnapshot,
              expected.id == pickedID,
              let proposal = result.validation.candidates.first(where: { $0 == expected }) else {
            throw GenericFoodProposalError.invalidSelection
        }
        return try confirmation.prepare(review: result, proposal: proposal, scope: scope, locale: locale)
    }
    /// Selects an offered panel. Only the person's action calls this; an id outside the offer is ignored.
    public func pick(_ id: String) {
        guard let result, result.offer.candidates.contains(where: { $0.id == id }) else { return }
        pickedID = id
    }
    /// The offered panel currently selected, if any: what "Use this source" would prepare.
    public var suggestedProposal: BoundFoodProposal? {
        guard let result, let pickedID else { return nil }
        return result.offer.candidates.first { $0.id == pickedID }
    }
    /// Developer tools lines for the last web lookup: no key, no credential, no payload.
    public var diagnosticLines: [String] {
        guard let result else { return [] }
        var lines = ["Web lookup terms: \(result.foodTerms)", "Choice policy: \(GenericFoodProposalReview.choicePolicyVersion)",
                     "Review format if used: \(ReviewedFoodProposalConfirmation.version3) · \(FoodProposalReviewGateRecordV3.choicePolicyVersion) · \(FoodProposalReviewAction.webLookupReviewV2)",
                     "Suggested choice: \(result.suggestedChoice)", "Ranking available: \(!result.rankingUnavailable)"]
        if let failure = result.selectionFailure { lines.append("Ranking failure: \(failure.rawValue)") }
        if let confidence = result.selection?.rawConfidence { lines.append("Uncalibrated model confidence: \(confidence)") }
        let offer = result.offer
        lines.append("Offered: \(offer.candidates.isEmpty ? "none" : offer.candidates.map(\.id).joined(separator: ", ")) · pre-selected \(offer.preselectedID ?? "none") · pick required \(offer.requiresPick)")
        lines += result.validation.candidates.map { "Proposal \($0.id): \($0.candidate.name) · eligible \($0.selectionEligible) · choosable \($0.choosable)" }
        lines += result.validation.rejected.map { "Rejected \($0.id): \($0.reason)" }
        lines += result.sourceAttempts.map { "Source attempt: \($0.absoluteString)" }
        // A document read in part (#508 phase 3): the policy and the four counts.
        lines += result.documents.compactMap { document in
            document.partialRead.map { record in
                "Part read: \(record.policy) · full \(record.fullBlocks) blocks, \(record.fullCharacters) characters · kept \(record.keptBlocks) blocks, \(record.keptCharacters) characters"
            }
        }
        return lines
    }
    public func cancel(clearResult: Bool = true) {
        generation += 1; task?.cancel(); task = nil; isSearching = false
        if clearResult { resultCredential = nil; result = nil; message = nil; alternativeSources = [] }
    }
    private func publishOtherSources(_ discovery: FoodWebDiscoveryResult?, attemptedURL: URL?) {
        if let discovery { knownSources = discovery.leads.filter { FoodWebLinkPolicy.isAllowed($0.url) } }
        alternativeSources = knownSources.filter { $0.url != attemptedURL }
    }
    private static func message(_ error: Error) -> String {
        if let partial = error as? GenericFoodProposalPartialFailure {
            switch partial.reason {
            case let .acquisition(error): return message(error)
            case let .provider(error): return message(error)
            case .invalidProposal: return "The proposal did not pass source checks. You can review another source."
            case .sourceMarketConflict: return "The source URL indicates a different country from the market named in your request. Choose another source or clarify the food description."
            case .sourceNotSuggested: return "None of the returned sources was recommended for this request. Refine the food description or inspect the source leads below."
            }
        }
        if error is CancellationError { return "Search stopped. You can search again." }
        if let error = error as? FoodSourceAcquisitionError {
            switch error {
            case .invalidURL, .hostNotAdmitted: return "This address is not a permitted public HTTPS source. Choose another source."
            case .unsupportedContent: return "The reader supports UTF-8 web pages, text and text-based PDFs. Scans, protected PDFs and pages requiring scripts may need another source."
            case .responseTooLarge: return "The source is too large for this bounded review. Choose a more specific food page."
            case .timedOut: return "The source timed out. You can try again."
            default: return "The source page could not be captured completely. Try another source or try again later."
            }
        }
        if error as? GenericFoodProposalReviewError == .noSourceLinks { return "No usable source links were found. Try a more specific description or supply a source address." }
        switch error as? FoodWebDiscoveryError {
        case .credentialRejected: return "OpenRouter rejected this key. Add or revalidate a key."
        case .permissionDenied: return "OpenRouter refused access. Check the key's permissions."
        case .quotaExceeded: return "OpenRouter reported a rate or credit limit. Check your account before retrying."
        case .requestRejected: return "OpenRouter could not accept the request or model configuration. Your key has not been marked invalid."
        case .timedOut: return "The provider request timed out. You can try again."
        default: return "The source review did not complete its checks. Nothing was selected or saved."
        }
    }
}

/// Web lookup (#196): one suggested source with its match type, values and unknowns together,
/// quoted text behind a disclosure and one "Use this source" action. Market is read-only here
/// and set in Settings. Technical detail lives in Developer tools.
public struct GenericFoodProposalReviewView: View {
    @ObservedObject private var model: GenericFoodProposalReviewViewModel
    @ObservedObject private var credentials: FoodWebDiscoveryViewModel
    private let confirm: (PopulatedFoodConfirmation) -> Void
    private let recordDiagnostics: ([String]) -> Void
    @State private var showsKey = false
    @State private var scope: FoodProposalReviewScope?
    @State private var useMessage: String?
    @FocusState private var editsDescription: Bool
    public init(model: GenericFoodProposalReviewViewModel, credentials: FoodWebDiscoveryViewModel,
                initialScope: FoodProposalReviewScope? = nil,
                recordDiagnostics: @escaping ([String]) -> Void = { _ in },
                confirm: @escaping (PopulatedFoodConfirmation) -> Void) {
        self.model = model; self.credentials = credentials; self.confirm = confirm
        self.recordDiagnostics = recordDiagnostics
        _scope = State(initialValue: initialScope)
    }
    public var body: some View {
        Form {
            Section {
                LabeledContent("Market", value: model.market == .unspecified ? "Not set" : model.market.rawValue)
                TextField("Food, product or dish", text: $model.foodTerms, axis: .vertical).autocorrectionDisabled()
                    .focused($editsDescription)
                DisclosureGroup("Use a specific page") {
                    TextField("Source address (optional)", text: $model.sourceAddress).autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                        #endif
                }
                if credentials.keyIsUsable {
                    Button("Look up") { scope = nil; useMessage = nil; Task { await model.search() } }
                        .disabled(!model.canSearch)
                } else {
                    Text("Web lookup needs your OpenRouter key.").font(.subheadline)
                    Button("Add or validate key") { model.cancel(); showsKey = true }
                }
                if model.isSearching {
                    HStack {
                        ProgressView().accessibilityHidden(true)
                        Text("Finding and checking a source…").font(.subheadline)
                        Spacer(minLength: 8)
                        Button("Stop") { model.cancel(clearResult: false) }.frame(minHeight: 44)
                    }
                }
            } footer: {
                Text("Change the market in Settings.")
            }
            if let message = model.message { Section { Text(message) } }
            if let result = model.result {
                Section {
                    Text(GenericFoodProposalReviewCopy.summary(result)).font(.subheadline)
                }
                if !result.offer.isEmpty {
                    let offerContent = FoodWebLookupOfferContent(review: result, selectedID: model.pickedID, scope: scope)
                    if offerContent.rows.count > 1 { panelSection(offerContent) }
                    if let proposal = model.suggestedProposal {
                        suggestedSection(proposal, result: result, offer: offerContent)
                    } else {
                        Section {
                            Button("Use this source") {}.frame(maxWidth: .infinity, minHeight: 44).disabled(true)
                            if let reason = offerContent.disabledReason {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    let noSuggestion = GenericFoodProposalReviewCopy.noSuggestion(result)
                    Section {
                        Text(noSuggestion.text)
                        switch noSuggestion.action {
                        case .lookUpAgain where credentials.keyIsUsable:
                            Button("Look up again") { scope = nil; useMessage = nil; Task { await model.search() } }
                                .frame(minHeight: 44)
                                .disabled(!model.canSearch)
                        case .editDescription:
                            // Goes back to the description; nothing is sent until Look up.
                            Button("Edit the description") { editsDescription = true }
                                .frame(minHeight: 44)
                        default:
                            EmptyView()
                        }
                    }
                }
                otherSourcesSection(result)
            } else if !model.alternativeSources.isEmpty {
                otherSourcesSection(nil)
            }
            Section {
                Text("Only your food terms, the market set in Settings and the captured page text are sent to OpenRouter and its selected providers. Saved foods, your food log and Health data are never sent. Charges use your OpenRouter account.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Web lookup")
        .sheet(isPresented: $showsKey) { NavigationStack { OpenRouterFoodKeyView(model: credentials) } }
        .onReceive(credentials.$keyIsUsable) { if !$0 { model.cancel() } }
        .onChange(of: model.result) { _, _ in scope = nil; useMessage = nil; recordDiagnostics(model.diagnosticLines) }
        .onDisappear { model.cancel(clearResult: false) }
    }

    /// The offered panels (#508 phase 2): one selected at a time, by trait and checkmark, never colour alone.
    @ViewBuilder private func panelSection(_ content: FoodWebLookupOfferContent) -> some View {
        Section(content.title) {
            if let warning = content.warningLine { Text(warning).font(.subheadline) }
            if let prompt = content.promptLine { Text(prompt).font(.subheadline) }
            ForEach(content.rows) { row in
                Button { model.pick(row.id) } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).foregroundStyle(.primary)
                            if let brand = row.brand { Text(brand).font(.subheadline) }
                            if let details = row.details { Text(details).font(.subheadline) }
                            if let heading = row.heading { Text(verbatim: heading).font(.caption) }
                            if let quote = row.firstQuote { Text(verbatim: "\u{201C}" + quote + "\u{201D}").font(.caption) }
                            if let basis = row.basisLabel { Text("per " + basis).font(.caption).foregroundStyle(.secondary) }
                            Text(row.declared.map { "\(FoodNutritionReviewPresentation.label($0.key.ledgerKey)) \($0.value) \($0.unit)" }
                                .joined(separator: " · ")).font(.caption)
                            let marks = [row.suggested ? FoodWebLookupOfferContent.suggestedWord : nil,
                                         row.differentValues ? FoodWebLookupOfferContent.differentValuesWord : nil].compactMap { $0 }
                            if !marks.isEmpty { Text(marks.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if row.selected { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
                    }.frame(minHeight: 44)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityAddTraits(row.selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    @ViewBuilder private func suggestedSection(_ proposal: BoundFoodProposal, result: GenericFoodProposalReview,
                                               offer: FoodWebLookupOfferContent) -> some View {
        // New reviews are saved as manifest v3, whose screen contract is web-lookup-review-v2 (#508).
        let content = FoodWebLookupReviewContent(document: proposal.document, candidate: proposal.candidate, scope: scope,
                                                 presentation: FoodProposalReviewAction.webLookupReviewV2)
            ?? FoodWebLookupReviewContent(document: proposal.document, candidate: proposal.candidate, scope: scope)
        Section(offer.rows.count > 1 ? "Selected panel" : FoodWebLookupOfferContent.suggestedTitle) {
            VStack(alignment: .leading, spacing: 4) {
                Text(content.name).font(.headline)
                if let brand = content.brand { Text(brand).font(.subheadline) }
                if let detail = offer.rows.first(where: { $0.id == proposal.id })?.details {
                    Text(detail).font(.subheadline)
                }
                Text([content.sourceHost, content.basisLabel.map { "per " + $0 }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let url = URL(string: proposal.document.url), FoodWebLinkPolicy.isAllowed(url) {
                Link("Open source page", destination: url)
            }
        }
        Section {
            if !result.representativeSourceOnly { scopeRow(.exactProduct, title: "Exact product") }
            scopeRow(.representativeEstimate, title: "Similar food estimate")
        } header: { Text("Match type") } footer: {
            if result.representativeSourceOnly { Text("This source supports a similar food estimate, not an exact product.") }
        }
        Section("Nutrition from this source") {
            if let partRead = content.partRead { Text(partRead).font(.subheadline) }
            ForEach(content.declared, id: \.key) { nutrient in
                LabeledContent(FoodNutritionReviewPresentation.label(nutrient.key.ledgerKey), value: nutrient.value + " " + nutrient.unit)
            }
            ForEach(content.notStated, id: \.self) { key in
                LabeledContent(FoodNutritionReviewPresentation.label(key.ledgerKey), value: content.notStatedText)
            }
            ForEach(content.notUsable, id: \.self) { key in
                LabeledContent(FoodNutritionReviewPresentation.label(key.ledgerKey), value: "Not usable")
            }
            DisclosureGroup("Show the quoted text") {
                ForEach(Array(content.quotes.enumerated()), id: \.offset) { _, quote in
                    Text(verbatim: "\u{201C}" + quote + "\u{201D}").font(.caption)
                }
            }
            ForEach(Array(content.limitations.enumerated()), id: \.offset) { _, limitation in
                Text(verbatim: limitation).font(.caption)
            }
            Text("Values are copied only where the quoted text supports them. Anything missing stays unknown. Check the values against the page before you continue.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Button("Use this source") {
                guard let scope else { return }
                do { confirm(try model.prepare(proposal, querySnapshot: result.foodTerms, scope: scope)) }
                catch { useMessage = "The lookup changed. Look it up again before using this source." }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(scope == nil)
            if scope == nil { Text("Choose a match type first.").font(.caption).foregroundStyle(.secondary) }
            if let useMessage { Text(useMessage) }
        }
    }

    private func scopeRow(_ value: FoodProposalReviewScope, title: String) -> some View {
        Button { scope = value } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if scope == value { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
            }.frame(minHeight: 44)
        }
        .accessibilityAddTraits(scope == value ? .isSelected : [])
    }

    @ViewBuilder private func otherSourcesSection(_ result: GenericFoodProposalReview?) -> some View {
        // Offered panels are listed above, never again here.
        let offeredIDs = Set(result?.offer.candidates.map(\.id) ?? [])
        let others = result?.validation.candidates.filter { !offeredIDs.contains($0.id) } ?? []
        // Over every candidate, so one sharing the suggested source's name is told apart too.
        let details = GenericFoodProposalReviewCopy.distinguishingDetails(result?.validation.candidates ?? [])
        if !others.isEmpty || !model.alternativeSources.isEmpty {
            Section("Other sources") {
                ForEach(others) { proposal in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(proposal.candidate.name)
                        if let detail = details[proposal.id] { Text(detail).font(.subheadline) }
                        Text(GenericFoodProposalReviewCopy.status(proposal, in: result)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.alternativeSources) { lead in
                    if FoodWebLinkPolicy.isAllowed(lead.url) {
                        Button("Check \(GenericFoodProposalReviewCopy.leadTitle(lead))") {
                            model.sourceAddress = lead.url.absoluteString
                            Task { await model.search() }
                        }.disabled(!credentials.keyIsUsable)
                    }
                }
            }
        }
    }

}

/// Key entry and privacy terms for OpenRouter web lookup.
/// Only the explicit save and revalidate buttons contact OpenRouter; opening this screen sends nothing.
public struct OpenRouterFoodKeyView: View {
    @ObservedObject var model: FoodWebDiscoveryViewModel
    @Environment(\.dismiss) private var dismiss
    private let showsDone: Bool

    public init(model: FoodWebDiscoveryViewModel, showsDone: Bool = true) {
        self.model = model; self.showsDone = showsDone
    }

    public var body: some View {
        Form {
            Section("Privacy and charges") {
                Text("OpenRouter finds public food sources and reads their nutrition into proposals for you to review.")
                Text("Validation sends only the key to OpenRouter. A search sends your displayed terms, and extraction sends captured public source text. Model requests require providers configured for no data collection and zero data retention; search services have their own terms.")
                Text("Your key stays in this device's Keychain, without sync or backup migration. Requests already sent cannot be recalled. Set credit limits in OpenRouter; the app has no monetary spending cap.")
                Text("Each review uses at most one search request, one source-selection request, three website connections including redirects, one extraction request, and one applicability check. Supplying a source address skips search and source selection. A model request that fails for a temporary reason, such as a timeout or a busy service, is sent again unchanged at most twice; website connections are never retried.")
                Link("OpenRouter privacy", destination: URL(string: "https://openrouter.ai/privacy")!)
                Link("Manage OpenRouter keys and limits", destination: URL(string: "https://openrouter.ai/settings/keys")!)
            }
            Section("API key") {
                SecureField("Paste OpenRouter API key", text: $model.keyEntry).autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button(model.isValidating ? "Validating…" : "Save and validate key") { Task { await model.validateAndSaveKey() } }
                    .disabled(model.isValidating || model.keyEntry.isEmpty)
                if model.hasSavedKey && !model.keyIsUsable {
                    Button("Revalidate saved key") { Task { await model.revalidateSavedKey() } }.disabled(model.isValidating)
                }
                Button("Remove key", role: .destructive) { model.removeKey() }
                if let message = model.keyMessage { Text(message) }
            }
        }
        .navigationTitle("OpenRouter API key")
        .toolbar { if showsDone { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        .onDisappear { model.closeCredentialEditor() }
    }
}
