import FoodLedgerApplication
import SwiftUI

@MainActor
public final class FoodWebDiscoveryViewModel: ObservableObject {
    @Published public var keyEntry = ""
    @Published public var foodTerms = "" { didSet { if foodTerms != oldValue { cancelSearch() } } }
    @Published public private(set) var hasSavedKey = false
    @Published public private(set) var keyIsUsable = false
    @Published public private(set) var isValidating = false
    @Published public private(set) var isSearching = false
    @Published public private(set) var keyMessage: String?
    @Published public private(set) var searchMessage: String?
    @Published public private(set) var result: FoodWebDiscoveryResult?
    private let provider: any FoodWebDiscovering
    private let keys: any FoodWebKeyStoring
    private var generation = 0
    private var searchGeneration = 0
    private var validation: Task<Void, Error>?
    private var search: Task<FoodWebDiscoveryResult, Error>?

    public init(provider: any FoodWebDiscovering, keys: any FoodWebKeyStoring) {
        self.provider = provider
        self.keys = keys
        do {
            let key = try keys.load()
            hasSavedKey = key != nil
            // A retained credential may have been rejected or could not be deleted
            // in an earlier session. Syntax alone never re-enables provider access.
            keyIsUsable = false
            if key != nil { keyMessage = "Revalidate the saved key before searching the web." }
        } catch { keyMessage = "The device Keychain is unavailable. Unlock your device and reopen this screen." }
    }

    public var canSearch: Bool {
        keyIsUsable && !isValidating && !isSearching && !outboundTerms.isEmpty && outboundTerms.count <= 300
    }
    public var outboundTerms: String { foodTerms.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Only the explicit save action calls validation. No food terms are sent.
    public func validateAndSaveKey() async {
        guard !isValidating else { return }
        let key = keyEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        keyEntry = ""
        await validate(key: key, saveNewKey: true)
    }

    /// Reopening never assumes a stored key remains valid or enabled.
    public func revalidateSavedKey() async {
        guard !isValidating, hasSavedKey else { return }
        let key: String
        do {
            guard let saved = try keys.load() else {
                hasSavedKey = false
                keyIsUsable = false
                keyMessage = "No saved key is available. Add and validate one first."
                return
            }
            key = saved
        } catch {
            keyIsUsable = false
            keyMessage = "The device Keychain is unavailable. Unlock your device and retry."
            return
        }
        await validate(key: key, saveNewKey: false)
    }

    private func validate(key: String, saveNewKey: Bool) async {
        guard !isValidating else { return }
        cancelSearch()
        guard FoodWebKeySyntax.isValid(key) else {
            keyMessage = "Enter a valid API key without spaces or line breaks. Web search remains unavailable."
            return
        }
        generation += 1
        let current = generation
        isValidating = true
        keyMessage = nil
        let task = Task { [provider] in try await provider.validate(key: key) }
        validation = task
        do {
            try await task.value
            guard generation == current else { return }
            if saveNewKey {
                do { try keys.save(key) }
                catch {
                    keyMessage = "Validation succeeded, but the device Keychain could not save the key."
                    isValidating = false
                    validation = nil
                    return
                }
            }
            hasSavedKey = true
            keyIsUsable = true
            keyMessage = saveNewKey
                ? "Key validated and saved on this device. Search access and quota are checked when you search."
                : "Saved key revalidated. Search access and quota are checked when you search."
        } catch {
            guard generation == current else { return }
            if error as? FoodWebDiscoveryError == .credentialRejected, (try? keys.load()) == key {
                invalidateRejectedKey()
            }
            keyMessage = Self.message(for: error) + (saveNewKey ? " The new key was not saved." : "")
        }
        isValidating = false
        validation = nil
    }

    /// No automatic retries, typing hooks, offline fallbacks or lifecycle calls invoke this.
    public func searchTheWeb() async {
        guard canSearch else { return }
        let key: String
        do {
            guard let saved = try keys.load(), FoodWebKeySyntax.isValid(saved) else {
                keyIsUsable = false
                searchMessage = "Add and validate your Gemini API key first."
                return
            }
            key = saved
        } catch {
            keyIsUsable = false
            searchMessage = "The device Keychain is unavailable. Offline search is still available."
            return
        }
        cancelSearch()
        let current = searchGeneration
        let terms = outboundTerms
        isSearching = true
        let task = Task { [provider] in try await provider.discover(foodTerms: terms, key: key) }
        search = task
        do {
            let reply = try await task.value
            guard searchGeneration == current else { return }
            result = reply
            if reply.leads.isEmpty { searchMessage = "No cited source leads were returned. Try different food terms or use offline search." }
        } catch {
            guard searchGeneration == current else { return }
            if error as? FoodWebDiscoveryError == .credentialRejected { invalidateRejectedKey() }
            searchMessage = Self.message(for: error)
        }
        isSearching = false
        search = nil
    }

    private func invalidateRejectedKey() {
        keyIsUsable = false
        do { try keys.delete(); hasSavedKey = false }
        catch { keyMessage = "The rejected key could not be removed. Unlock your device and retry Remove key." }
    }

    public func removeKey() {
        cancelPending()
        keyIsUsable = false
        do {
            try keys.delete()
            hasSavedKey = false
            keyMessage = "Key removed from this device. Requests already received by Google cannot be recalled. Revoke the key in AI Studio if needed."
        } catch {
            keyMessage = "Could not remove the key from Keychain. Web search is disabled here; unlock the device and retry removal."
        }
    }

    public func cancelPending() {
        generation += 1
        validation?.cancel()
        validation = nil
        isValidating = false
        keyEntry = ""
        cancelSearch()
    }

    private func cancelSearch() {
        searchGeneration += 1
        search?.cancel()
        search = nil
        isSearching = false
        result = nil
        searchMessage = nil
    }

    private static func message(for error: Error) -> String {
        switch error as? FoodWebDiscoveryError {
        case .credentialRejected: "Google rejected the API key. Replace or revalidate it."
        case .permissionDenied: "Google refused access. Check API restrictions and project permissions; this does not establish that the key is invalid."
        case .quotaExceeded: "Google reports a quota or rate limit. Check your quota and billing before trying again."
        case .requestRejected: "Google could not accept this request or model. Check provider availability before trying again."
        case .invalidQuery: "Enter between 1 and 300 characters of food terms."
        case .invalidResponse: "Google returned an unsupported or incomplete response. No food was selected or saved."
        default: "The request could not complete. Check your connection and try again. Offline search is still available."
        }
    }
}
