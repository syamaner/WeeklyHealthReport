import Foundation

/// The closed list of ways the app can send a request to OpenRouter (docs/openrouter-single-consent-v1-amendment.md,
/// O1.2 and section 6). Every request site names the use it asks the gate for. A later route adds a
/// case in its own contract, with its policy entry, egress row and request site, in the PR that wires it.
public enum OpenRouterUse: String, CaseIterable, Sendable {
    case keyValidation
    case webLookup
    case labelPhotoRead
    case labelPhotoCatalogueCheck
    /// The pasted label text adapters exist in code but are not wired into the app (route closed by D38).
    case pastedLabelTextRead
    case pastedLabelTextCatalogueCheck

    /// Whether the use is in force in the app. The app's gate refuses every use that is not.
    public var isInForce: Bool {
        switch self {
        case .keyValidation, .webLookup, .labelPhotoRead, .labelPhotoCatalogueCheck: true
        case .pastedLabelTextRead, .pastedLabelTextCatalogueCheck: false
        }
    }

    /// The opening words of the use's paragraph in the privacy policy's OpenRouter section, or nil.
    public var policyEntry: String? {
        switch self {
        case .keyValidation: "Key validation."
        case .webLookup: "Web lookup."
        case .labelPhotoRead, .labelPhotoCatalogueCheck: "Label photo reading."
        case .pastedLabelTextRead, .pastedLabelTextCatalogueCheck: nil
        }
    }

    /// The contract link that identifies the use's OpenRouter row in `privacy-and-egress.md`, or nil.
    public var egressRow: String? {
        switch self {
        case .keyValidation, .webLookup: "generic-food-proposal-integration-v1.md"
        case .labelPhotoRead, .labelPhotoCatalogueCheck: "label-photo-ai-prefill-v1.md"
        case .pastedLabelTextRead, .pastedLabelTextCatalogueCheck: nil
        }
    }
}

/// The one consumer-owned gate every OpenRouter request site asks immediately before it sends,
/// including each retry attempt (O1.2). The app's implementation reads the Settings › OpenRouter
/// switch and permits only uses in force; tools pass a gate that permits their own uses.
public protocol OpenRouterEgressPermitting: Sendable {
    func permits(_ use: OpenRouterUse) -> Bool
}

/// The state of the user's OpenRouter key as a journey sees it.
public enum OpenRouterKeyState: Equatable, Sendable {
    case missing, notValidated, valid
}

/// Why a journey cannot send because of consent or the key (O1.4), checked in this order.
public enum OpenRouterBlockedReason: Equatable, Sendable, CaseIterable {
    case switchOff, noKey, keyNotValidated
}

public enum OpenRouterAccess {
    /// The O1.4 reason, in the order of its table, or nil when the journey may offer its send action.
    public static func blockedReason(consentOn: Bool, keyState: OpenRouterKeyState) -> OpenRouterBlockedReason? {
        guard consentOn else { return .switchOff }
        switch keyState {
        case .missing: return .noKey
        case .notValidated: return .keyNotValidated
        case .valid: return nil
        }
    }

    /// The web lookup journeys' key state: a usable key is valid, else a saved key is not validated.
    public static func keyState(hasSavedKey: Bool, keyIsUsable: Bool) -> OpenRouterKeyState {
        if keyIsUsable { return .valid }
        return hasSavedKey ? .notValidated : .missing
    }
}
