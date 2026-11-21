import XCTest
import FoodLedgerApplication
@testable import WeeklyHealthReport

/// Confirm enrichment's feature switch and its Debug seed (docs/confirm-enrichment-openrouter-v1-phase.md
/// section 6, G16). Synthetic data only; nothing is sent.
@MainActor
final class ConfirmEnrichmentPreferenceTests: XCTestCase {
    private func suite() -> (UserDefaults, String) {
        let name = "confirm-enrichment-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (defaults, name)
    }

    func testTheSwitchIsOffByDefaultReadsThePersistentDomainOnlyAndIsRemovedWhenOff() {
        let (defaults, name) = suite()
        let preference = ConfirmEnrichmentPreference(defaults: defaults, domainName: name)
        XCTAssertEqual(ConfirmEnrichmentPreference.key, "confirmEnrichment.enabled.v1")
        XCTAssertFalse(preference.isOn)
        defaults.set("yes", forKey: ConfirmEnrichmentPreference.key)
        XCTAssertFalse(preference.isOn, "a non-Boolean value reads as off")
        preference.isOn = true
        XCTAssertTrue(preference.isOn)
        preference.isOn = false
        XCTAssertNil(defaults.persistentDomain(forName: name)?[ConfirmEnrichmentPreference.key], "off removes the value")
    }

    func testTheKeyInTheArgumentOrRegistrationDomainNeverReadsAsOn() {
        let (defaults, name) = suite()
        defaults.register(defaults: [ConfirmEnrichmentPreference.key: true])
        defaults.setVolatileDomain([ConfirmEnrichmentPreference.key: true], forName: UserDefaults.argumentDomain)
        addTeardownBlock { defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
        XCTAssertTrue(defaults.bool(forKey: ConfirmEnrichmentPreference.key), "the fixture really sets the other domains")
        XCTAssertFalse(ConfirmEnrichmentPreference(defaults: defaults, domainName: name).isOn)
        XCTAssertFalse(ConfirmEnrichmentPreference(defaults: defaults).isOn, "no domain name reads off")
    }

    func testTheSeedWritesOnlyInADebugBuild() {
        XCTAssertEqual(ConfirmEnrichmentSeed.resolve(argument: "on", debugBuild: true), .write)
        XCTAssertEqual(ConfirmEnrichmentSeed.resolve(argument: "off", debugBuild: true), .remove)
        XCTAssertEqual(ConfirmEnrichmentSeed.resolve(argument: "yes", debugBuild: true), .none)
        for argument in ["on", "off", nil] as [String?] {
            XCTAssertEqual(ConfirmEnrichmentSeed.resolve(argument: argument, debugBuild: false), .none, "ignored in Release")
        }
        XCTAssertEqual(ConfirmEnrichmentSeed.launchArgumentKey, "ConfirmEnrichment")
        XCTAssertNotEqual(ConfirmEnrichmentSeed.launchArgumentKey, ConfirmEnrichmentPreference.key, "the seed has its own key")
    }

    func testTheFourUsesStayRefusedByTheAppsGateWithBothSwitchesOn() {
        let (defaults, name) = suite()
        let consent = OpenRouterConsentPreference(defaults: defaults, domainName: name)
        consent.isOn = true
        ConfirmEnrichmentPreference(defaults: defaults, domainName: name).isOn = true
        for use in [OpenRouterUse.confirmEnrichmentDetails, .confirmEnrichmentNutrients, .confirmEnrichmentDetailsCatalogueCheck,
                    .confirmEnrichmentNutrientsCatalogueCheck] {
            XCTAssertFalse(consent.permits(use), "\(use) is not in force before the wiring PR")
        }
    }
}
