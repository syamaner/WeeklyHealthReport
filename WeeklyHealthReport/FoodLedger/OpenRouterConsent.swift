import Combine
import FoodLedgerApplication
import FoodLedgerPresentation
import Foundation
import SwiftUI

/// The one OpenRouter consent, Settings › OpenRouter (docs/openrouter-single-consent-v1-amendment.md
/// O1.1, O1.2 and O1.5). A Boolean under `openRouter.consent.v1` in the app's persistent domain only:
/// never the launch-argument or registration domain, in every build. A missing or non-Boolean value
/// reads as off; turning it off removes the value. No record, archive or export carries it.
///
/// Retired, never read or written by this build and never to be reused: `labelPhoto.egressConsent.live.v1`,
/// `labelPhoto.egressConsent.scripted.v1` and `labelPhoto.liveRoute.enabled.v1`. They are left in place,
/// so a rollback finds them as it left them (O1.5).
struct OpenRouterConsentPreference: OpenRouterEgressPermitting, @unchecked Sendable {
    static let key = "openRouter.consent.v1"
    static let retiredKeys = ["labelPhoto.egressConsent.live.v1", "labelPhoto.egressConsent.scripted.v1", "labelPhoto.liveRoute.enabled.v1"]

    let defaults: UserDefaults
    /// The persistent domain read: the app's bundle identifier for `.standard`, or the injected
    /// suite's name in tests. With neither, the switch reads off, so a test never reads the host
    /// app's own domain by accident.
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

    /// The app permits only uses in force, and only while the switch is on; the pasted label text
    /// uses are always refused (section 6).
    func permits(_ use: OpenRouterUse) -> Bool { use.isInForce && isOn }
}

/// `-OpenRouterConsent on|off` for simulator journey checks (O1.2). In a Debug build `on` writes the
/// persistent value and `off` removes it, before the first scene; any other value, and every value in a
/// Release build, does nothing.
enum OpenRouterConsentSeed: Equatable {
    case write, remove, none

    static let launchArgumentKey = "OpenRouterConsent"

    static func resolve(argument: String?, debugBuild: Bool) -> OpenRouterConsentSeed {
        guard debugBuild else { return .none }
        switch argument {
        case "on": return .write
        case "off": return .remove
        default: return .none
        }
    }

    static func apply(_ defaults: UserDefaults, preference: OpenRouterConsentPreference) {
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

/// Settings › OpenRouter (O1.1): one section, directly after Food search.
@MainActor
enum OpenRouterSettingsContribution {
    static let title = "OpenRouter"
    static let consentTitle = "Use OpenRouter for food lookups and label reading"
    static let consentCaption = "Off by default. While it is off, the app sends nothing to OpenRouter. Uses your own key and credit."
    static let keyRow = "API key"
    static let readsRow = "Label photo reads today"
    static let howRow = "How the app uses OpenRouter"
    static let manageKeys = "Manage OpenRouter keys and limits"
    static let manageKeysURL = URL(string: "https://openrouter.ai/settings/keys")!
    static let notAvailable = "Not available"

    static func readsDetail(_ stored: LabelPhotoSpendPolicy.Stored, today: String) -> String {
        switch stored {
        case .unreadable: return notAvailable
        case .absent: return "0 of \(LabelPhotoSpendPolicy.dailyReadLimit)"
        case let .day(record):
            return "\(LabelPhotoSpendPolicy.current(today: today, stored: record).reads) of \(LabelPhotoSpendPolicy.dailyReadLimit)"
        }
    }

    /// `labelReads` reads the live spend ledger directly (O1-D1): no read session or flow, nothing sent.
    /// `readsVisible` is true while the switch is on and a key is saved.
    static func section(consent: OpenRouterConsentPreference, webLookup: FoodWebDiscoveryViewModel,
                        readsVisible: @escaping @MainActor () -> Bool,
                        labelReads: @escaping @MainActor () -> String) -> SettingsSection {
        // Quiet until a state change: the switch itself, or the saved key, changes whether the
        // label reads row shows.
        let consentChanged = PassthroughSubject<Void, Never>()
        let toggle = SettingsToggle(title: consentTitle, caption: consentCaption,
                                    read: { consent.isOn }, write: { consent.isOn = $0; consentChanged.send() })
        let readsChanges = consentChanged.merge(with: FoodSearchSettingsContribution.webLookupChanges(webLookup))
        return SettingsSection(
            id: .openRouter,
            title: title,
            footer: nil,
            footerLink: SettingsExternalLink(title: manageKeys, url: manageKeysURL),
            rows: [
                .toggle("openRouterConsent", toggle),
                .link(keyRow, route: .webLookupKey, detail: { [weak webLookup] in
                    guard let webLookup else { return nil }
                    return FoodSearchSettingsContribution.webLookupDetail(hasSavedKey: webLookup.hasSavedKey, keyIsUsable: webLookup.keyIsUsable,
                                                                          keyLoadFailed: webLookup.keyLoadFailed)
                }, changes: FoodSearchSettingsContribution.webLookupChanges(webLookup)),
                .value("labelPhotoReadsToday", readsRow, detail: { readsVisible() ? labelReads() : nil },
                       changes: readsChanges.eraseToAnyPublisher()),
                .link(howRow, route: .openRouterPrivacy)
            ]
        )
    }
}

/// Settings › OpenRouter as its own screen, for a journey's blocked row link (O1.4). It renders the
/// same section the Settings list shows.
struct OpenRouterSettingsScreen: View {
    let section: SettingsSection
    let destination: (AppRoute) -> AnyView
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        Form {
            Section {
                ForEach(section.rows) { row in
                    switch row.kind {
                    case let .toggle(toggle): SettingsToggleRow(toggle: toggle)
                    case let .link(detail, route):
                        NavigationLink { destination(route) } label: {
                            LabeledContent(row.title) { if let detail = detail() { Text(detail) } }
                        }
                        .accessibilityIdentifier("openRouterSettings." + route.rawValue)
                    case let .text(detail):
                        LabeledContent(row.title) { if let detail { Text(detail) } }
                    case let .value(detail):
                        if let value = detail() { LabeledContent(row.title, value: value) }
                    }
                }
            } footer: {
                if let link = section.footerLink { Link(link.title, destination: link.url) }
            }
        }
        .navigationTitle(section.title)
        .onAppear { refresh += 1 }
        .onReceive(Publishers.MergeMany(section.rows.compactMap(\.changes)).receive(on: RunLoop.main)) { refresh += 1 }
    }
}
