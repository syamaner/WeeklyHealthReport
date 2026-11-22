import XCTest
import FoodLedgerApplication
import FoodLedgerDomain
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

    // MARK: G17: the composed gate

    /// G17 (phase gate section 7): the composed gate refuses every Confirm use with enrichment off and
    /// OpenRouter on, and with OpenRouter off; it permits them only with both on, and never permits a
    /// use of another route. The bare `OpenRouterConsentPreference` is unchanged.
    func testTheComposedGateNeedsBothSwitchesAndTheBareConsentIsUnchanged() {
        let (defaults, name) = suite()
        let consent = OpenRouterConsentPreference(defaults: defaults, domainName: name)
        let preference = ConfirmEnrichmentPreference(defaults: defaults, domainName: name)
        let gate = ConfirmEnrichmentEgress(consent: consent, preference: preference)
        let enrichment: [OpenRouterUse] = [.confirmEnrichmentDetails, .confirmEnrichmentNutrients,
                                           .confirmEnrichmentDetailsCatalogueCheck, .confirmEnrichmentNutrientsCatalogueCheck]
        XCTAssertEqual(ConfirmEnrichmentEgress.uses, Set(enrichment))
        for (openRouterOn, enrichmentOn) in [(false, false), (false, true), (true, false), (true, true)] {
            consent.isOn = openRouterOn
            preference.isOn = enrichmentOn
            for use in OpenRouterUse.allCases {
                let expected = enrichment.contains(use) && openRouterOn && enrichmentOn
                XCTAssertEqual(gate.permits(use), expected, "\(use) with OpenRouter \(openRouterOn) and enrichment \(enrichmentOn)")
                XCTAssertEqual(consent.permits(use), use.isInForce && openRouterOn, "\(use): the bare consent ignores enrichment")
            }
        }
    }

    // MARK: The root branches

    private struct NoDatabase: PersonalFoodDatabaseEntryReading {
        func descriptionFields(recordID: ExternalIdentifier) -> PersonalFoodDescriptionFields? { nil }
    }

    /// A key store that never touches the Keychain; nothing here sends.
    private struct SyntheticKeys: FoodWebKeyStoring {
        func load() throws -> String? { "sk-or-v1-synthetic-test-key-0000000000" }
        func save(_ key: String) throws {}
        func delete() throws {}
    }

    private func branch(_ defaults: UserDefaults, name: String, directory: URL,
                        keyState: OpenRouterKeyState = .valid) -> ConfirmEnrichmentRootBranch {
        ConfirmEnrichmentRootBranch.make(
            defaults: defaults, consent: OpenRouterConsentPreference(defaults: defaults, domainName: name),
            preference: ConfirmEnrichmentPreference(defaults: defaults, domainName: name), database: NoDatabase(),
            ids: RandomLedgerIDGenerator(), keys: SyntheticKeys(), directory: directory, keyState: { keyState }, diagnostics: nil)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("confirm-enrichment-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private static func detailsRequest(_ routes: ConfirmEnrichmentSession.Routes) throws -> ConfirmEnrichmentPolicy.DetailsRequest {
        let description = ConfirmEnrichmentDescription(name: "Synthetic oat biscuit", brand: nil, variant: nil, category: nil,
                                                       productType: nil, state: nil, source: .compositionTable)
        let inputs = try ConfirmDetailsRequestInputs(description: description, knownDetails: [:], asked: [.preparation])
        return try ConfirmEnrichmentPolicy.detailsRequest(inputs, route: routes.details, encoder: FoundationCanonicalJSONEncoder(),
                                                          digester: SHA256Digester())
    }

    /// PR 5 (phase gate section 10): the scripted and live branches read the same route values, so a
    /// scripted answer passes the same checks as a live one.
    func testTheScriptedAndLiveBranchesReadTheSameRouteValues() throws {
        let (defaults, name) = suite()
        let live = branch(defaults, name: name, directory: try directory())
        XCTAssertEqual(live.mode, .live)
        #if DEBUG
        defaults.set("scripted", forKey: ConfirmEnrichmentRootBranch.routeArgumentKey)
        let scripted = branch(defaults, name: name, directory: try directory())
        XCTAssertEqual(scripted.mode, .scripted)
        XCTAssertEqual(scripted.session.routeValues.details, live.session.routeValues.details)
        XCTAssertEqual(scripted.session.routeValues.nutrients, live.session.routeValues.nutrients)
        #endif
        XCTAssertEqual(live.session.routeValues.details.endpoint, "https://openrouter.ai/api/v1/systemone")
        XCTAssertEqual(live.session.routeValues.nutrients.endpoint, "https://openrouter.ai/api/v1/chat/completions")
    }

    /// G17: the live branch is built without the scripted argument, its preconditions read both
    /// switches and the key state, and its session asks the composed gate: with enrichment off and
    /// OpenRouter on, even a caller claiming both switches on is refused before anything is sent,
    /// reserved or counted.
    func testTheLiveBranchAsksTheComposedGateAndSendsNothingWithEnrichmentOff() async throws {
        let (defaults, name) = suite()
        let folder = try directory()
        let live = branch(defaults, name: name, directory: folder)
        XCTAssertEqual(live.mode, .live)
        let consent = OpenRouterConsentPreference(defaults: defaults, domainName: name)
        let preference = ConfirmEnrichmentPreference(defaults: defaults, domainName: name)
        XCTAssertEqual(live.preconditions(), .init(openRouterOn: false, enrichmentOn: false, keyState: .valid))
        consent.isOn = true
        XCTAssertEqual(live.preconditions(), .init(openRouterOn: true, enrichmentOn: false, keyState: .valid))
        preference.isOn = true
        XCTAssertEqual(live.preconditions(), .init(openRouterOn: true, enrichmentOn: true, keyState: .valid))
        preference.isOn = false
        XCTAssertEqual(branch(defaults, name: name, directory: folder, keyState: .notValidated).preconditions().keyState, .notValidated)

        let claimed = ConfirmEnrichmentSession.Preconditions(openRouterOn: true, enrichmentOn: true, keyState: .valid)
        let request = try Self.detailsRequest(live.session.routeValues), locale = try LedgerText("en-GB")
        let outcome = await live.session.details(request, mode: .askAgain, preconditions: claimed, locale: locale)
        XCTAssertEqual(outcome, .failed(.notPermitted))
        XCTAssertEqual(live.ledger.read(), .absent, "nothing reserved or counted")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], "no cache or day file written")
    }
}
