import FoodLedgerApplication
import SwiftUI

public struct FoodWebDiscoveryView: View {
    @ObservedObject private var model: FoodWebDiscoveryViewModel
    public init(model: FoodWebDiscoveryViewModel) { self.model = model }

    public var body: some View {
        Form {
            Section("Optional Gemini web discovery") {
                Text("Find unverified source leads with your own Gemini API key. Web leads cannot be selected or saved as food, and contain no admitted nutrition data.")
                Text("Offline food search remains available without a key.").font(.caption)
            }
            Section("Before adding a key") {
                Text("Save and validate sends only your key to Google to check model access. Search the web sends the food terms you enter below, with a fixed source-finding instruction. HealthKit data, saved foods, diary history and capture evidence are not attached.")
                Text("Google may charge your account for model use and each search query; one tap can cause several queries. Set quota and billing controls in your Google project. There is no app-enforced spending cap.")
                Text("Your key is stored only in this device’s Keychain, without sync or backup migration. A compromised device or instrumented app can still expose it. Remove it here and revoke it in Google AI Studio if needed.")
                Text("Interaction storage is disabled, but Google retains grounding prompts, context and outputs for 30 days. Unpaid services may use content for training and human review; paid-service terms differ. UK, EEA and Swiss users must use a project with active billing. Avoid private or sensitive information in food terms.")
                Link("Google API terms", destination: URL(string: "https://ai.google.dev/gemini-api/terms")!)
                Link("Google pricing and quota", destination: URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!)
                Link("Manage your API keys", destination: URL(string: "https://aistudio.google.com/api-keys")!)
            }
            Section("Your Gemini API key") {
                Text(model.keyIsUsable ? "Saved key validated" : model.hasSavedKey ? "Saved key needs revalidation" : "Web search needs a validated key")
                SecureField("Paste API key", text: $model.keyEntry)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityIdentifier("gemini-key")
                Button(model.isValidating ? "Validating…" : "Save and validate key") {
                    Task { await model.validateAndSaveKey() }
                }
                .disabled(model.isValidating || model.keyEntry.isEmpty)
                if model.hasSavedKey && !model.keyIsUsable {
                    Button("Revalidate saved key") { Task { await model.revalidateSavedKey() } }
                        .disabled(model.isValidating)
                }
                if model.isValidating { ProgressView("Checking model access") }
                if model.hasSavedKey || model.isValidating || !model.keyIsUsable {
                    Button("Remove key", role: .destructive) { model.removeKey() }
                }
                if let message = model.keyMessage { Text(message).font(.caption) }
            }
            Section("Food terms to send to Google") {
                TextField("e.g. Greek yoghurt 10% fat", text: $model.foodTerms, axis: .vertical)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("gemini-food-terms")
                Text("Only these terms and the source-finding instruction are sent. Maximum 300 characters.").font(.caption)
                Button("Search the web") { Task { await model.searchTheWeb() } }
                    .disabled(!model.canSearch)
                if model.isSearching { ProgressView("Finding source leads") }
                if let message = model.searchMessage { Text(message) }
            }
            if let result = model.result {
                Section("Google-cited pages (unverified)") {
                    Text("These links come from Google's citation annotations. Gemini may write different links or claims in its answer. Check each page's food, preparation and quantity basis yourself; a citation does not verify nutrition.")
                        .font(.caption)
                    if result.leads.isEmpty { Text("Google supplied no cited pages for this answer.") }
                    ForEach(Array(result.leads.enumerated()), id: \.offset) { _, lead in
                        if FoodWebLinkPolicy.isAllowed(lead.url) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(lead.title).font(.headline)
                                Text("Google citation URL: \(lead.url.host ?? "Source website")")
                                    .font(.caption)
                                Link("Open Google-cited page", destination: lead.url)
                                switch FoodWebCitationLinkPolicy.relationship(for: lead) {
                                case .conflictingHost:
                                    Text("Gemini wrote a link to a different website in this cited passage. Check Google's citation page directly.")
                                        .font(.caption)
                                case .multipleWrittenHosts:
                                    Text("This citation spans links to more than one website. Check Google's citation page directly.")
                                        .font(.caption)
                                case .unknownDestination:
                                    Text("The written link uses an opaque redirect or has no comparable source host. Check Google's citation page directly.")
                                        .font(.caption)
                                case .matchingHost, .noWrittenLink:
                                    EmptyView()
                                }
                                if let citedText = lead.citedText {
                                    DisclosureGroup("Gemini text attached to this citation") {
                                        Text(verbatim: citedText).font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
                if !result.responseText.isEmpty {
                    Section("Gemini's generated answer") {
                        Text("This is unverified model-written text. Its links and claims may differ from Google's citations; it cannot be used to save nutrition.")
                            .font(.caption)
                        DisclosureGroup("Read full unverified answer") {
                            Text(verbatim: result.responseText)
                        }
                    }
                }
                if let html = result.searchSuggestionsHTML {
                    Section("Google Search suggestions") {
                        FoodWebSearchSuggestions(html: html)
                            .frame(minHeight: 200, idealHeight: 240, maxHeight: 320)
                        Text("Scroll within the suggestions if needed. Links open in your browser.").font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Search the web")
        .onDisappear { model.cancelPending() }
    }
}
