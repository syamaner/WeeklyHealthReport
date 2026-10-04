import Foundation
import SwiftUI
import FoodLedgerApplication
import FoodLedgerDomain

@MainActor
public final class GenericFoodProposalReviewViewModel: ObservableObject {
    @Published public var foodTerms = "" { didSet { if foodTerms != oldValue { knownSources = []; cancel() } } }
    @Published public var sourceAddress = "" { didSet { if sourceAddress != oldValue { cancel() } } }
    @Published public private(set) var isSearching = false
    @Published public private(set) var result: GenericFoodProposalReview?
    @Published public private(set) var message: String?
    @Published public private(set) var alternativeSources: [FoodWebLead] = []
    private let reviewer: any GenericFoodProposalReviewing
    private let credentials: any FoodWebCredentialAuthorizing
    private let confirmation: ReviewedFoodProposalConfirmation
    private let locale: LedgerText
    private var generation = 0
    private var task: Task<GenericFoodProposalReview, Error>?
    private var resultCredential: FoodWebRequestCredential?
    private var knownSources: [FoodWebLead] = []

    public init(reviewer: any GenericFoodProposalReviewing, credentials: any FoodWebCredentialAuthorizing,
                confirmation: ReviewedFoodProposalConfirmation, locale: LedgerText) {
        self.reviewer = reviewer; self.credentials = credentials; self.confirmation = confirmation; self.locale = locale
    }
    public var canSearch: Bool {
        let query = foodTerms.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isSearching && !query.isEmpty && query.count <= 300
    }
    public func search() async {
        guard canSearch else { return }
        cancel()
        let current = generation
        let query = foodTerms.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if value.validation.candidates.isEmpty { message = "The captured source supplied no proposal that passed the source checks. Try another food description or source." }
        } catch {
            guard generation == current else { return }
            guard credentials.isCurrent(credential) else {
                cancel(); message = "The key changed. Revalidate it and search again."; return
            }
            if error as? FoodWebDiscoveryError == .credentialRejected { credentials.reject(credential) }
            if let partial = error as? GenericFoodProposalPartialFailure { publishOtherSources(partial.discovery, attemptedURL: partial.attemptedSourceURL ?? url) }
            message = Self.message(error)
        }
        if generation == current { isSearching = false; self.task = nil }
    }
    public func prepare(_ expected: BoundFoodProposal, querySnapshot: String, scope: FoodProposalReviewScope,
                        acknowledgement: FoodProposalAcknowledgement) throws -> PopulatedFoodConfirmation {
        guard let resultCredential, credentials.isCurrent(resultCredential) else {
            cancel()
            throw GenericFoodProposalError.invalidSelection
        }
        guard let result, result.foodTerms == foodTerms.trimmingCharacters(in: .whitespacesAndNewlines),
              result.foodTerms == querySnapshot,
              let proposal = result.validation.candidates.first(where: { $0 == expected }),
              result.permitsConfirmation(of: proposal) else {
            throw GenericFoodProposalError.invalidSelection
        }
        return try confirmation.prepare(proposal, query: result.foodTerms, scope: scope, acknowledgement: acknowledgement, locale: locale)
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

public struct GenericFoodProposalReviewView: View {
    @ObservedObject private var model: GenericFoodProposalReviewViewModel
    @ObservedObject private var credentials: FoodWebDiscoveryViewModel
    private let confirm: (PopulatedFoodConfirmation) -> Void
    @State private var showsKey = false
    public init(model: GenericFoodProposalReviewViewModel, credentials: FoodWebDiscoveryViewModel,
                confirm: @escaping (PopulatedFoodConfirmation) -> Void) {
        self.model = model; self.credentials = credentials; self.confirm = confirm
    }
    public var body: some View {
        Form {
            Section("Find nutrition to review") {
                TextField("Food, product or dish", text: $model.foodTerms, axis: .vertical).autocorrectionDisabled()
                TextField("Source URL (optional)", text: $model.sourceAddress).autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                    #endif
                Text("Search public sources or supply a page. AI extracts source-backed proposals for you to check; missing values remain unknown.").font(.caption)
                Button(model.isSearching ? "Reviewing source…" : "Find and review nutrition") { Task { await model.search() } }
                    .disabled(!model.canSearch || !credentials.keyIsUsable)
                if model.isSearching {
                    ProgressView("Finding, reading and checking the source")
                    Button("Stop search") { model.cancel(clearResult: false) }
                }
            }
            Section("OpenRouter") {
                Button(credentials.keyIsUsable ? "API key and privacy" : "Add or validate API key") {
                    model.cancel(); showsKey = true
                }
                Text("Only these food terms and captured source text go to OpenRouter and its selected providers. Saved foods, diary history and HealthKit data are excluded. Search and model charges use your account.").font(.caption)
            }
            if let message = model.message { Section { Text(message) } }
            if !model.alternativeSources.isEmpty {
                Section("Other source leads") {
                    ForEach(model.alternativeSources) { lead in
                        if FoodWebLinkPolicy.isAllowed(lead.url) {
                            Button("Review \(lead.title)") {
                                model.sourceAddress = lead.url.absoluteString
                                Task { await model.search() }
                            }
                        }
                    }
                }
            }
            if let result = model.result {
                if result.rankingUnavailable {
                    Section { Text("Applicability checking was unavailable. You can inspect the source, but confirmation requires a successful check.").font(.caption) }
                }
                Section("Model suggestion") {
                    if let candidate = result.validation.candidates.first(where: { $0.id == result.suggestedChoice && $0.selectionEligible }) {
                        Text(candidate.candidate.name)
                    } else { Text(result.suggestedChoice == "clarify" ? "Clarification is needed" : "No suitable candidate suggested") }
                    if let confidence = result.selection?.rawConfidence {
                        Text("Uncalibrated model confidence: \(confidence.formatted(.percent.precision(.fractionLength(0))))").font(.caption)
                    }
                    Text("Review the source and its applicability to your food before choosing.").font(.caption)
                }
                Section("Source proposals") {
                    ForEach(result.validation.candidates) { proposal in
                        NavigationLink {
                            FoodProposalDetailView(proposal: proposal, confirmationPermitted: result.permitsConfirmation(of: proposal)) { scope, acknowledgement in
                                let input = try model.prepare(proposal, querySnapshot: result.foodTerms,
                                    scope: scope, acknowledgement: acknowledgement)
                                confirm(input)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(proposal.candidate.name)
                                Text(proposal.candidate.basis.label ?? "Serving basis missing").font(.caption)
                                if proposal.status == .conflictingCandidates { Text("Conflicting source declarations").font(.caption) }
                                else if !proposal.selectionEligible { Text("More source information is needed").font(.caption) }
                            }
                        }
                    }
                    if !result.validation.rejected.isEmpty { Text("\(result.validation.rejected.count) proposal(s) failed the source checks.").font(.caption) }
                }
                Section("Captured sources") {
                    ForEach(result.documents, id: \.id) { document in
                        if let url = URL(string: document.url) { Link(url.host ?? "Source", destination: url) }
                    }
                }
            }
        }
        .navigationTitle("Web nutrition review")
        .sheet(isPresented: $showsKey) { NavigationStack { OpenRouterFoodKeyView(model: credentials) } }
        .onReceive(credentials.$keyIsUsable) { if !$0 { model.cancel() } }
        .onDisappear { model.cancel(clearResult: false) }
    }
}

private struct FoodProposalDetailView: View {
    let proposal: BoundFoodProposal
    let confirmationPermitted: Bool
    let confirm: (FoodProposalReviewScope, FoodProposalAcknowledgement) throws -> Void
    @State private var scope: FoodProposalReviewScope?
    @State private var identityReviewed = false
    @State private var basisReviewed = false
    @State private var nutrientsReviewed = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("Food and source") {
                Text(proposal.candidate.name).font(.headline)
                if !confirmationPermitted {
                    Text("This proposal was not recommended for your request. Inspect the evidence, then refine the food description or choose another source before confirming.").font(.caption)
                }
                if proposal.status == .conflictingCandidates {
                    Text("The captured source contains conflicting declarations for this food. These values need clarification before confirmation.").font(.caption)
                } else if !proposal.selectionEligible {
                    Text("The source is missing a usable nutrition basis or declaration. You can inspect its values, but confirmation needs more source information.").font(.caption)
                }
                if let brand = proposal.candidate.brand { LabeledContent("Source brand", value: brand) }
                if let url = URL(string: proposal.document.url) { Link("Open source page", destination: url) }
                Text("The quoted text matches the captured page. Check the food, nutrient labels and serving basis yourself.").font(.caption)
                DisclosureGroup("Food identity evidence") { references(proposal.candidate.identityEvidence) }
                Picker("How does this apply?", selection: $scope) {
                    Text("Choose match type").tag(Optional<FoodProposalReviewScope>.none)
                    Text("Exact product").tag(Optional(FoodProposalReviewScope.exactProduct))
                    Text("Representative food estimate").tag(Optional(FoodProposalReviewScope.representativeEstimate))
                }.onChange(of: scope) { _, _ in identityReviewed = false }
                Toggle("I reviewed the food and match type", isOn: $identityReviewed)
            }
            Section("Source serving basis") {
                Text(proposal.candidate.basis.label ?? "Unknown")
                references(proposal.candidate.basis.evidence)
                if proposal.candidate.basis.unit == .serving { Text("One source serving has no inferred gram weight.").font(.caption) }
                Toggle("I reviewed the serving basis", isOn: $basisReviewed)
            }
            Section("Nutrition from this source") {
                ForEach(proposal.candidate.nutrients, id: \.key) { value in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(FoodNutritionReviewPresentation.label(value.key.ledgerKey),
                            value: value.value.map { $0 + " " + value.key.unit } ?? "Unknown")
                        if !value.evidence.isEmpty { DisclosureGroup("Source quotation") { references(value.evidence) } }
                    }
                }
                Toggle("I reviewed the values and unknowns", isOn: $nutrientsReviewed)
            }
            if !proposal.candidate.limitations.isEmpty {
                Section("Proposal limitations") {
                    ForEach(Array(proposal.candidate.limitations.enumerated()), id: \.offset) { _, limitation in Text(verbatim: limitation) }
                }
            }
            Section {
                Button("Continue to food confirmation") {
                    guard let scope else { return }
                    do { try confirm(scope, .init(identityAndScopeReviewed: identityReviewed, basisReviewed: basisReviewed, nutrientsAndUnknownsReviewed: nutrientsReviewed)) }
                    catch { message = "The source review changed or is incomplete. Return to the search and review it again." }
                }.disabled(!confirmationPermitted || !proposal.selectionEligible || scope == nil || !identityReviewed || !basisReviewed || !nutrientsReviewed)
                Text("Enter the amount eaten and confirm on the next screen. Exact products still need their missing identity details.").font(.caption)
                if let message { Text(message) }
            }
        }.navigationTitle("Review source proposal")
    }
    @ViewBuilder private func references(_ values: [FoodProposalReference]) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, reference in Text(verbatim: reference.quote).font(.caption) }
    }
}

private struct OpenRouterFoodKeyView: View {
    @ObservedObject var model: FoodWebDiscoveryViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Privacy and charges") {
                Text("OpenRouter finds public food sources and reads their nutrition into proposals for you to review.")
                Text("Validation sends only the key to OpenRouter. A search sends your displayed terms, and extraction sends captured public source text. Model requests require providers configured for no data collection and zero data retention; search services have their own terms.")
                Text("Your key stays in this device's Keychain, without sync or backup migration. Requests already sent cannot be recalled. Set credit limits in OpenRouter; the app has no monetary spending cap.")
                Text("Each review uses at most one search request, one source-selection request, three website connections including redirects, one extraction request, and one applicability check. Supplying a source address skips search and source selection. There are no automatic retries.")
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
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onDisappear { model.closeCredentialEditor() }
    }
}
