import FoodLedgerApplication
import Foundation

/// The Confirm enrichment feature switch (docs/confirm-enrichment-openrouter-v1.md section 9):
/// `confirmEnrichment.enabled.v1`, a Boolean in the app's persistent domain only, never the launch
/// argument or registration domain, in every build. Missing or non-Boolean reads as off; turning it off
/// removes the value. It is a feature switch, not a consent: with OpenRouter off it does nothing.
struct ConfirmEnrichmentPreference: @unchecked Sendable {
    static let key = "confirmEnrichment.enabled.v1"

    let defaults: UserDefaults
    let domainName: String?

    init(defaults: UserDefaults, domainName: String? = nil) {
        self.defaults = defaults
        self.domainName = domainName ?? (defaults === UserDefaults.standard ? Bundle.main.bundleIdentifier : nil)
    }

    var isOn: Bool {
        get { domainName.flatMap { defaults.persistentDomain(forName: $0)?[Self.key] as? Bool } ?? false }
        nonmutating set {
            if newValue { defaults.set(true, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
        }
    }
}

/// The app's gate for every Confirm enrichment request site and its route checker (phase gate sections
/// 4 and 6, G17): a Confirm use is permitted only while the use is in force, Settings › OpenRouter is on
/// and Suggest missing food details and values on Confirm is on. Every other use is refused here; the
/// bare `OpenRouterConsentPreference` stays unchanged for the other routes.
struct ConfirmEnrichmentEgress: OpenRouterEgressPermitting {
    static let uses: Set<OpenRouterUse> = Set(ConfirmEnrichmentPart.allCases.flatMap { [$0.use, $0.catalogueUse] })

    let consent: OpenRouterConsentPreference
    let preference: ConfirmEnrichmentPreference

    func permits(_ use: OpenRouterUse) -> Bool {
        Self.uses.contains(use) && consent.permits(use) && preference.isOn
    }
}

/// `-ConfirmEnrichment on|off` for simulator journey checks (phase gate section 6), resolved like
/// `OpenRouterConsentSeed`: in a Debug build `on` writes the persistent value and `off` removes it,
/// before the first scene; any other value, and every value in a Release build, does nothing.
/// Note: `-ConfirmEnrichment on` writes the persistent switch, which stays until `off` is passed or the
/// row is turned off. Since the wiring PR a Debug launch without `-ConfirmEnrichmentRoute scripted` uses the
/// live route, so a seeded `on` with OpenRouter on and a saved key sends real requests: scripted journeys
/// end with `-ConfirmEnrichment off`.
enum ConfirmEnrichmentSeed: Equatable {
    case write, remove, none

    static let launchArgumentKey = "ConfirmEnrichment"

    static func resolve(argument: String?, debugBuild: Bool) -> ConfirmEnrichmentSeed {
        guard debugBuild else { return .none }
        switch argument {
        case "on": return .write
        case "off": return .remove
        default: return .none
        }
    }

    static func apply(_ defaults: UserDefaults, preference: ConfirmEnrichmentPreference) {
        #if DEBUG
        let debugBuild = true
        #else
        let debugBuild = false
        #endif
        switch resolve(argument: defaults.string(forKey: launchArgumentKey), debugBuild: debugBuild) {
        case .write: preference.isOn = true
        case .remove: preference.isOn = false
        case .none: break
        }
    }
}
