import FoodLedgerApplication
import SwiftUI

@MainActor
public final class FoodWebDiscoveryViewModel: ObservableObject, FoodWebCredentialAuthorizing {
    @Published public var keyEntry = ""
    @Published public var foodTerms = "" { didSet { if foodTerms != oldValue { cancelSearch() } } }
    @Published public private(set) var hasSavedKey = false
    /// True while the last read of the saved key failed (for example before first unlock), so whether
    /// a key is saved is unknown. It is never a saved or usable key: `hasSavedKey` stays false and
    /// nothing is sent until a later read succeeds and the key is validated (#493).
    @Published public private(set) var keyLoadFailed = false
    @Published public private(set) var keyIsUsable = false
    @Published public private(set) var isValidating = false
    @Published public private(set) var isSearching = false
    @Published public private(set) var keyMessage: String?
    @Published public private(set) var searchMessage: String?
    @Published public private(set) var result: FoodWebDiscoveryResult?
    private let provider: any FoodWebDiscovering
    private let keys: any FoodWebKeyStoring
    /// The Settings › OpenRouter gate (docs/openrouter-single-consent-v1-amendment.md O1.2, O1-D2):
    /// asked before validation, so Revalidate with the switch off keeps the session's validation.
    private let egress: any OpenRouterEgressPermitting
    public let providerName: String
    private let operatorName: String
    private let keyManagementName: String
    // Transient identity of the credential that actually passed validation; never persisted or displayed.
    private var validatedKey: String?
    private var generation = 0
    private var searchGeneration = 0
    private var validation: Task<Void, Error>?
    private var search: Task<FoodWebDiscoveryResult, Error>?
    /// A recheck asked for while validation was running; it runs once validation finishes, fails
    /// or is cancelled, and only if the key is still unread (#493).
    private var recheckPending = false

    public init(egress: any OpenRouterEgressPermitting, provider: any FoodWebDiscovering, keys: any FoodWebKeyStoring,
                providerName: String = "Gemini", operatorName: String = "Google", keyManagementName: String = "AI Studio") {
        self.egress = egress
        self.provider = provider
        self.keys = keys
        self.providerName = providerName; self.operatorName = operatorName; self.keyManagementName = keyManagementName
        loadSavedKeyState()
    }

    /// Reads the saved key again after a failed read, when the composition root reports that
    /// protected data became available or the app returned to the foreground (#493). It only
    /// updates whether a key is saved; it never validates, enables or sends the key. While
    /// validation runs it is deferred until validation ends, never dropped.
    public func recheckSavedKey() {
        guard !isValidating else { recheckPending = true; return }
        guard keyLoadFailed else { return }
        loadSavedKeyState()
    }

    /// Runs a recheck deferred by validation once validation has ended, keeping the validation
    /// outcome message when the key can now be read.
    private func runPendingRecheck() {
        guard recheckPending, !isValidating else { return }
        recheckPending = false
        guard keyLoadFailed else { return }
        let outcome = keyMessage
        loadSavedKeyState()
        if !keyLoadFailed, let outcome { keyMessage = outcome }
    }

    private func loadSavedKeyState() {
        // A retained credential may have been rejected or could not be deleted
        // in an earlier session. Syntax alone never re-enables provider access.
        invalidateUsability()
        do {
            let key = try keys.load()
            keyLoadFailed = false
            hasSavedKey = key != nil
            keyMessage = key != nil ? "Revalidate the saved key before searching the web." : nil
        } catch {
            markKeyUnread()
            keyMessage = Self.unreadKeyMessage
        }
    }

    private static let unreadKeyMessage = "The device Keychain is unavailable, so the saved key could not be read yet. It is checked again when you unlock your device or return to the app."

    /// The key as a journey sees it (section 6): a usable key is valid, else a saved key is not validated.
    public var keyState: OpenRouterKeyState { OpenRouterAccess.keyState(hasSavedKey: hasSavedKey, keyIsUsable: keyIsUsable) }

    /// Whether Settings › OpenRouter permits key validation now. Read on demand, never stored.
    public var validationPermitted: Bool { egress.permits(.keyValidation) }

    /// The O1.4 blocked row's reason for web lookup, or nil when Look up may be offered.
    public var blockedReason: OpenRouterBlockedReason? {
        OpenRouterAccess.blockedReason(consentOn: egress.permits(.webLookup), keyState: keyState)
    }

    /// The key screen's save button (O1-D2): with the switch off it saves the key without validating it.
    public var saveButtonTitle: String {
        if !validationPermitted { return "Save key" }
        return isValidating ? "Validating…" : "Save and validate key"
    }

    /// Settings › OpenRouter changed: redraw what reads the switch on demand.
    public func consentChanged() { objectWillChange.send() }

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
            guard let saved = try loadKey() else {
                hasSavedKey = false
                invalidateUsability()
                keyMessage = "No saved key is available. Add and validate one first."
                return
            }
            key = saved
        } catch {
            keyMessage = Self.unreadKeyMessage
            return
        }
        await validate(key: key, saveNewKey: false)
    }

    private func validate(key: String, saveNewKey: Bool) async {
        guard !isValidating else { return }
        // Asked first, before usability is cleared: a refusal never changes key state (O1.2).
        guard egress.permits(.keyValidation) else {
            if saveNewKey { saveWithoutValidating(key) } else { keyMessage = message(for: FoodWebDiscoveryError.notPermitted) }
            return
        }
        cancelSearch()
        // Kept so a refusal that races this validation (the switch turned off after the check above,
        // refused by the provider's own gate) restores the session's earlier validation (O1.2).
        let priorKey = validatedKey, priorUsable = keyIsUsable
        invalidateUsability()
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
                    runPendingRecheck()
                    return
                }
            }
            guard (try? keys.load()) == key else {
                refreshSavedKeyPresence()
                keyMessage = "The saved key changed during validation. Revalidate the current key before searching."
                isValidating = false
                validation = nil
                runPendingRecheck()
                return
            }
            hasSavedKey = true
            keyLoadFailed = false
            validatedKey = key
            keyIsUsable = true
            keyMessage = saveNewKey
                ? "Key validated and saved on this device. Search access and quota are checked when you search."
                : "Saved key revalidated. Search access and quota are checked when you search."
        } catch {
            guard generation == current else { return }
            if error as? FoodWebDiscoveryError == .notPermitted {
                // A refusal is never a rejected key and never changes key state: nothing was sent.
                isValidating = false
                validation = nil
                if saveNewKey {
                    saveWithoutValidating(key)
                } else {
                    validatedKey = priorKey
                    keyIsUsable = priorUsable
                    keyMessage = message(for: error)
                }
                runPendingRecheck()
                return
            }
            if error as? FoodWebDiscoveryError == .credentialRejected, (try? loadKey()) == key {
                invalidateRejectedKey(expectedKey: key)
            }
            keyMessage = message(for: error) + (saveNewKey ? " The new key was not saved." : "")
        }
        isValidating = false
        validation = nil
        runPendingRecheck()
    }

    /// O1-D2: with Settings › OpenRouter off, Save key stores the key unvalidated and sends nothing.
    /// It clears the session's validated key and bumps the credential generation, exactly as saving
    /// a new key does, so a key validated earlier is never sent in place of this one.
    private func saveWithoutValidating(_ key: String) {
        guard FoodWebKeySyntax.isValid(key) else {
            keyMessage = "Enter a valid API key without spaces or line breaks. Web search remains unavailable."
            return
        }
        cancelSearch()
        invalidateUsability()
        generation += 1
        do { try keys.save(key) } catch {
            keyMessage = "The device Keychain could not save the key."
            return
        }
        hasSavedKey = true
        keyLoadFailed = false
        keyMessage = "Key saved. Turn on OpenRouter in Settings to validate it."
    }

    /// No automatic retries, typing hooks, offline fallbacks or lifecycle calls invoke this.
    public func searchTheWeb() async {
        guard canSearch else { return }
        let key: String
        do {
            guard let saved = try loadKey(), FoodWebKeySyntax.isValid(saved) else {
                invalidateUsability()
                searchMessage = "Add and validate your \(providerName) API key first."
                return
            }
            guard saved == validatedKey else {
                cancelSearch()
                invalidateUsability()
                hasSavedKey = true
                searchMessage = "The saved key changed. Revalidate it before searching the web."
                return
            }
            key = saved
        } catch {
            invalidateUsability()
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
            guard (try? keys.load()) == key else {
                invalidateUsability()
                refreshSavedKeyPresence()
                searchMessage = "The saved key changed during the request. Revalidate it before searching again."
                isSearching = false
                search = nil
                return
            }
            result = reply
            if reply.leads.isEmpty { searchMessage = "No cited source leads were returned. Try different food terms or use offline search." }
        } catch {
            guard searchGeneration == current else { return }
            if error as? FoodWebDiscoveryError == .credentialRejected {
                invalidateRejectedKey(expectedKey: key)
            } else if (try? keys.load()) != key {
                invalidateUsability()
                refreshSavedKeyPresence()
            }
            searchMessage = message(for: error)
        }
        isSearching = false
        search = nil
    }

    public func credentialForRequest() throws -> FoodWebRequestCredential {
        guard keyIsUsable, !isValidating, let key = validatedKey else { throw FoodSearchEnrichmentError.unavailable }
        guard (try? loadKey()) == key else {
            invalidateUsability()
            keyMessage = "The saved key changed or is unavailable. Revalidate it before searching."
            throw FoodSearchEnrichmentError.unavailable
        }
        return FoodWebRequestCredential(key: key, generation: generation)
    }

    public func isCurrent(_ credential: FoodWebRequestCredential) -> Bool {
        guard generation == credential.generation, keyIsUsable, !isValidating else { return false }
        guard validatedKey == credential.key, (try? loadKey()) == credential.key else {
            invalidateUsability()
            keyMessage = "The saved key changed or is unavailable. Revalidate it before searching."
            return false
        }
        return true
    }

    public func reject(_ credential: FoodWebRequestCredential) {
        guard generation == credential.generation else { return }
        invalidateRejectedKey(expectedKey: credential.key)
    }

    /// Leaving normal key settings keeps completed validation for this in-memory search session.
    /// Unfinished validation/discovery is cancelled and earlier request grants become stale.
    public func closeCredentialEditor() {
        generation += 1
        validation?.cancel(); validation = nil; isValidating = false
        keyEntry = ""
        cancelSearch()
        runPendingRecheck()
    }

    /// Whether a key is still saved after the key changed during a request. A failed read is
    /// recorded as unknown, so the unlock and foreground recheck reads it again (#493).
    private func refreshSavedKeyPresence() {
        do {
            hasSavedKey = try loadKey() != nil
            keyLoadFailed = false
        } catch {}
    }

    /// Every read of the saved key goes through here. A read that throws is recorded as unknown,
    /// never as "no key": the key is not saved or usable until a later read succeeds, and the
    /// unlock and foreground recheck reads it again (#493). A definite empty result is returned.
    private func loadKey() throws -> String? {
        do { return try keys.load() }
        catch { markKeyUnread(); throw error }
    }

    private func markKeyUnread() {
        invalidateUsability()
        hasSavedKey = false
        keyLoadFailed = true
    }

    private func invalidateUsability() {
        validatedKey = nil
        keyIsUsable = false
    }

    private func invalidateRejectedKey(expectedKey: String) {
        invalidateUsability()
        let current: String?
        do { current = try loadKey() } catch {
            keyMessage = Self.unreadKeyMessage
            return
        }
        do {
            keyLoadFailed = false
            guard current == expectedKey else {
                hasSavedKey = current != nil
                keyMessage = "The saved key changed. Revalidate the current key before searching."
                return
            }
            try keys.delete()
            hasSavedKey = false
            keyLoadFailed = false
        } catch { keyMessage = "The rejected key could not be removed. Unlock your device and retry Remove key." }
    }

    public func removeKey() {
        cancelPending()
        keyIsUsable = false
        do {
            try keys.delete()
            hasSavedKey = false
            keyLoadFailed = false
            keyMessage = "Key removed from this device. Requests already received by \(operatorName) cannot be recalled. Revoke the key in \(keyManagementName) if needed."
        } catch {
            keyMessage = "Could not remove the key from Keychain. Web search is disabled here; unlock the device and retry removal."
        }
    }

    public func cancelPending() {
        invalidateUsability()
        generation += 1
        validation?.cancel()
        validation = nil
        isValidating = false
        keyEntry = ""
        cancelSearch()
        runPendingRecheck()
    }

    private func cancelSearch() {
        searchGeneration += 1
        search?.cancel()
        search = nil
        isSearching = false
        result = nil
        searchMessage = nil
    }

    private func message(for error: Error) -> String {
        switch error as? FoodWebDiscoveryError {
        case .credentialRejected: "\(operatorName) rejected the API key. Replace or revalidate it."
        case .permissionDenied: "\(operatorName) refused access. Check API restrictions and project permissions; this does not establish that the key is invalid."
        case .quotaExceeded: "\(operatorName) reports a quota or rate limit. Check your quota and billing before trying again."
        case .timedOut: "The web search timed out. You can try again."
        case .connectionFailed: "The web search could not connect. Check your connection and try again."
        case .requestRejected: "\(operatorName) could not accept this request or model. Check provider availability before trying again."
        case .invalidQuery: "Enter between 1 and 300 characters of food terms."
        case .invalidResponse: "\(operatorName) returned an unsupported or incomplete response. No food was selected or saved."
        case .notPermitted: OpenRouterBlockedText.switchOff
        default: "The request could not complete. Check your connection and try again. Offline search is still available."
        }
    }
}
