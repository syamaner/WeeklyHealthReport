import XCTest
import FoodLedgerApplication
import FoodLedgerPresentation
@testable import WeeklyHealthReport

/// A gate that permits every use, for app tests that exercise web lookup with OpenRouter turned on.
struct TestOpenRouterEgress: OpenRouterEgressPermitting {
    func permits(_ use: OpenRouterUse) -> Bool { true }
}

/// docs/openrouter-single-consent-v1-amendment.md O1.6 tests 5 and 8, and the O1.3 policy split.
/// Synthetic data only; nothing is sent.
@MainActor
final class OpenRouterConsentTests: XCTestCase {
    private static var names: [ObjectIdentifier: String] = [:]

    static func suiteName(_ defaults: UserDefaults) -> String { names[ObjectIdentifier(defaults)] ?? "" }

    private func suite() -> (UserDefaults, String) {
        let name = "openrouter-consent-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        Self.names[ObjectIdentifier(defaults)] = name
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (defaults, name)
    }

    // MARK: Test 5: migration and seeding

    func testTheSwitchIsOffByDefaultAndRemovedWhenOff() {
        let (defaults, name) = suite()
        let preference = OpenRouterConsentPreference(defaults: defaults, domainName: name)
        XCTAssertEqual(OpenRouterConsentPreference.key, "openRouter.consent.v1")
        XCTAssertFalse(preference.isOn)
        defaults.set("yes", forKey: OpenRouterConsentPreference.key)
        XCTAssertFalse(preference.isOn, "a non-Boolean value reads as off")
        preference.isOn = true
        XCTAssertTrue(preference.isOn)
        XCTAssertEqual(defaults.persistentDomain(forName: name)?[OpenRouterConsentPreference.key] as? Bool, true)
        preference.isOn = false
        XCTAssertNil(defaults.persistentDomain(forName: name)?[OpenRouterConsentPreference.key], "off removes the value")
    }

    func testTheAppPermitsOnlyUsesInForceAndOnlyWhileOn() {
        let (defaults, name) = suite()
        let preference = OpenRouterConsentPreference(defaults: defaults, domainName: name)
        for use in OpenRouterUse.allCases { XCTAssertFalse(preference.permits(use), "\(use) while off") }
        preference.isOn = true
        for use in OpenRouterUse.allCases {
            XCTAssertEqual(preference.permits(use), use.isInForce, "\(use): the pasted label text uses stay refused")
        }
    }

    func testNoRetiredKeyIsReadAsConsentAndNoneIsWrittenOrRemoved() throws {
        let retired = OpenRouterConsentPreference.retiredKeys
        XCTAssertEqual(retired, ["labelPhoto.egressConsent.live.v1", "labelPhoto.egressConsent.scripted.v1", "labelPhoto.liveRoute.enabled.v1"])
        for mask in 0..<(1 << retired.count) {
            for savedKey in [nil, "sk-or-v1-synthetic"] as [String?] {
                let (defaults, name) = suite()
                let set = retired.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
                for key in set { defaults.set(true, forKey: key) }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
                let root = try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults,
                                                         openRouterKeys: SyntheticConsentKeys(key: savedKey), openRouterConsentDomain: name)
                XCTAssertFalse(root.openRouterConsent.isOn, "\(set) with key \(savedKey != nil)")
                XCTAssertEqual(root.labelPhotoMode, .off, "\(set): no route sends")
                XCTAssertNil(root.labelPhotoFlow())
                XCTAssertEqual(root.webDiscovery.blockedReason, .switchOff)
                root.openRouterConsent.isOn = true
                root.openRouterConsent.isOn = false
                for key in retired {
                    XCTAssertEqual(defaults.object(forKey: key) as? Bool, set.contains(key) ? true : nil, "\(key) is left as it was")
                }
            }
        }
    }

    func testAnArgumentDomainValueReadsAsOff() {
        let (defaults, name) = suite()
        let preference = OpenRouterConsentPreference(defaults: defaults, domainName: name)
        // As `-openRouter.consent.v1 YES` would: a value in the launch-argument domain only.
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var injected = arguments
        injected[OpenRouterConsentPreference.key] = true
        UserDefaults.standard.setVolatileDomain(injected, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        XCTAssertFalse(preference.isOn, "only the persistent domain is consent")
        let standard = OpenRouterConsentPreference(defaults: .standard)
        let persisted = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[OpenRouterConsentPreference.key] as? Bool
        XCTAssertEqual(standard.isOn, persisted ?? false, "the standard preference reads the persistent domain, never the argument")
    }

    func testTheSeedResolverWritesOnlyInDebugForOnOrOff() {
        XCTAssertEqual(OpenRouterConsentSeed.resolve(argument: "on", debugBuild: true), .write)
        XCTAssertEqual(OpenRouterConsentSeed.resolve(argument: "off", debugBuild: true), .remove)
        for argument in ["on", "off", "YES", "On", "", nil] as [String?] {
            XCTAssertEqual(OpenRouterConsentSeed.resolve(argument: argument, debugBuild: false), .none, "Release ignores \(argument ?? "nil")")
        }
        for argument in ["YES", "On", "1", "", nil] as [String?] {
            XCTAssertEqual(OpenRouterConsentSeed.resolve(argument: argument, debugBuild: true), .none, "\(argument ?? "nil")")
        }
    }

    func testTheSeedArgumentWritesAndRemovesThePersistentValue() {
        let (defaults, name) = suite()
        let preference = OpenRouterConsentPreference(defaults: defaults, domainName: name)
        defaults.set("on", forKey: OpenRouterConsentSeed.launchArgumentKey)
        OpenRouterConsentSeed.apply(defaults, preference: preference)
        XCTAssertTrue(preference.isOn)
        defaults.set("off", forKey: OpenRouterConsentSeed.launchArgumentKey)
        OpenRouterConsentSeed.apply(defaults, preference: preference)
        XCTAssertFalse(preference.isOn)
    }

    // MARK: O1.3: the sectioned policy

    func testThePolicySplitsIntoItsPinnedTitleBlockAndHeadings() throws {
        let policy = try PrivacyPolicy.bundledText()
        let split = PrivacyPolicySections.split(policy)
        XCTAssertEqual(split.titleBlock, "WeeklyHealthReport privacy policy\nEffective 22 November 2026")
        XCTAssertEqual(split.sections.map(\.heading), [
            "", "Apple Health", "Sharing and Google Drive", "Local food records and notes", "Optional online food search", "OpenRouter",
            "Voice", "Permissions, diagnostics and policy changes", "Private evaluation tooling outside the app",
            "Evaluation best-estimate amendment (8 November 2026)",
        ])
    }

    // MARK: Test 8: the policy and the engineering list agree

    func testThePolicyAndTheEgressListNameTheSameUses() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let docs = repository.appendingPathComponent("docs")
        let bundled = try PrivacyPolicy.bundledText()
        let policy = try String(contentsOf: docs.appendingPathComponent("privacy-policy.txt"), encoding: .utf8)
        XCTAssertEqual(bundled, policy, "the bundled policy is the repository's")
        let egress = try String(contentsOf: docs.appendingPathComponent("privacy-and-egress.md"), encoding: .utf8)
        let amendment = try String(contentsOf: docs.appendingPathComponent("openrouter-single-consent-v1-amendment.md"), encoding: .utf8)

        let section = try XCTUnwrap(PrivacyPolicySections.split(policy).sections.first { $0.heading == "OpenRouter" })
        // The approved text of section 3.5, as amended by CE1 PR 5 (section 3.5a), word for word.
        let amended = try XCTUnwrap(amendment.range(of: "### 3.5a Privacy policy as amended by CE1 PR 5"))
        let start = try XCTUnwrap(amendment.range(of: "```text\nOpenRouter\n\n", range: amended.upperBound..<amendment.endIndex))
        let end = try XCTUnwrap(amendment.range(of: "\n```", range: start.upperBound..<amendment.endIndex))
        XCTAssertEqual(section.body, String(amendment[start.upperBound..<end.lowerBound]))

        let paragraphs = section.body.components(separatedBy: "\n\n")
        let framing = [
            "The app uses OpenRouter only if you turn on Use OpenRouter for food lookups, label reading and Confirm suggestions in Settings › OpenRouter. It is off by default. While it is off, the app sends nothing to OpenRouter: no lookup, no label photo, no key validation and no model check.",
            "While it is on, the app uses OpenRouter only in these ways, each only when you start it or turn it on:",
            "Other uses are added to this list only in the release that starts them, after their own approval.",
            "For every use: model requests require endpoints classified by OpenRouter for zero data retention and no data collection, with no provider fallback.",
        ]
        for opening in framing {
            XCTAssertEqual(paragraphs.filter { $0.hasPrefix(opening) }.count, 1, "framing paragraph pinned: \(opening)")
        }
        let inForce = OpenRouterUse.allCases.filter(\.isInForce)
        let entries = paragraphs.filter { paragraph in !framing.contains { paragraph.hasPrefix($0) } }
        for entry in entries {
            XCTAssertTrue(inForce.contains { entry.hasPrefix($0.policyEntry ?? "\u{0}") }, "a use entry maps to an in-force use: \(entry.prefix(40))")
        }
        for use in inForce {
            let title = try XCTUnwrap(use.policyEntry)
            XCTAssertEqual(entries.filter { $0.hasPrefix(title) }.count, 1, "\(use) has its policy entry")
        }
        for use in OpenRouterUse.allCases where !use.isInForce {
            XCTAssertNil(use.policyEntry); XCTAssertNil(use.egressRow)
        }

        let rows = egress.components(separatedBy: "\n").filter { $0.hasPrefix("| OpenRouter") }
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            XCTAssertTrue(inForce.contains { Self.egressRow($0.egressRow ?? "\u{0}", matches: row) }, "an OpenRouter row maps to an in-force use")
        }
        for use in inForce {
            let mapping = try XCTUnwrap(use.egressRow)
            let matching = rows.filter { Self.egressRow(mapping, matches: $0) }
            XCTAssertEqual(matching.count, 1, "\(use) maps to exactly one egress row")
            let row = try XCTUnwrap(matching.first, "\(use) has its egress row")
            let cells = row.components(separatedBy: " | ")
            XCTAssertTrue(cells.count >= 4 && cells[2].hasPrefix("With OpenRouter turned on in Settings (O1)"), "\(use): When names the switch")
            if ConfirmEnrichmentEgress.uses.contains(use) {
                XCTAssertTrue(cells[2].hasPrefix("With OpenRouter turned on in Settings (O1) and Suggest missing food details and values on"),
                              "\(use): When names both switches")
            }
        }
        // The two kept sentences of section 3.5.
        XCTAssertTrue(policy.contains("To stay offline, keep optional database search disabled, keep OpenRouter turned off and avoid barcode-lookup actions."))
        XCTAssertTrue(policy.contains("Remove your OpenRouter key and disconnect Drive before deleting the app if you want to remove those credentials"))
    }

    /// Confirm enrichment phase gate section 6: an `egressRow` is split at its first `#`; the link part
    /// must appear as `(<link>)` in the row and, when a prefix follows, the row must start with
    /// `| <prefix>`. A mapping without `#` matches by its link alone.
    static func egressRow(_ mapping: String, matches row: String) -> Bool {
        let parts = mapping.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard row.contains("(" + parts[0] + ")") else { return false }
        return parts.count == 1 || row.hasPrefix("| " + parts[1])
    }

    func testTheEgressRowMatcherSplitsAtTheFirstHash() {
        let row = "| OpenRouter System One and its endpoint | x | With OpenRouter turned on | [c.md](c.md) |"
        XCTAssertTrue(Self.egressRow("c.md#OpenRouter System One", matches: row))
        XCTAssertTrue(Self.egressRow("c.md", matches: row), "no prefix matches by link alone")
        XCTAssertFalse(Self.egressRow("c.md#OpenRouter and its one", matches: row))
        XCTAssertFalse(Self.egressRow("d.md#OpenRouter System One", matches: row))
    }

    // MARK: Confirm enrichment G10: consent records

    /// G10 (phase gate section 7): after the wiring PR the uses not in force are the pasted label text
    /// uses only, and each in-force use maps to exactly one egress row and one policy entry.
    func testTheConfirmEnrichmentUsesAreInForceWithOneRowAndOneEntryEach() throws {
        XCTAssertEqual(OpenRouterUse.allCases.filter { !$0.isInForce }, [.pastedLabelTextRead, .pastedLabelTextCatalogueCheck])
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs")
        let egress = try String(contentsOf: docs.appendingPathComponent("privacy-and-egress.md"), encoding: .utf8)
        let policy = try String(contentsOf: docs.appendingPathComponent("privacy-policy.txt"), encoding: .utf8)
        let rows = egress.components(separatedBy: "\n").filter { $0.hasPrefix("| OpenRouter") }
        let section = try XCTUnwrap(PrivacyPolicySections.split(policy).sections.first { $0.heading == "OpenRouter" })
        let paragraphs = section.body.components(separatedBy: "\n\n")
        for use in ConfirmEnrichmentEgress.uses {
            XCTAssertTrue(use.isInForce, "\(use)")
            XCTAssertEqual(rows.filter { Self.egressRow(use.egressRow ?? "\u{0}", matches: $0) }.count, 1, "\(use): one row")
            XCTAssertEqual(paragraphs.filter { $0.hasPrefix(use.policyEntry ?? "\u{0}") }.count, 1, "\(use): one entry")
        }
        XCTAssertEqual(ConfirmEnrichmentEgress.uses, [.confirmEnrichmentDetails, .confirmEnrichmentNutrients,
                                                      .confirmEnrichmentDetailsCatalogueCheck, .confirmEnrichmentNutrientsCatalogueCheck])
    }

    // MARK: Confirm enrichment records, verbatim (CE1 sections 11.1 and 11.2)

    /// The two 11.1 rows, the Stays-on-device quote and the 11.2 entry are taken from the contract and
    /// must appear in the records word for word.
    func testTheConfirmEnrichmentPrivacyRecordsAreInForceVerbatim() throws {
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs")
        let contract = try String(contentsOf: docs.appendingPathComponent("confirm-enrichment-openrouter-v1.md"), encoding: .utf8)
        let egress = try String(contentsOf: docs.appendingPathComponent("privacy-and-egress.md"), encoding: .utf8)
        let policy = try String(contentsOf: docs.appendingPathComponent("privacy-policy.txt"), encoding: .utf8)
        let rowsStart = try XCTUnwrap(contract.range(of: "### 11.1 `docs/privacy-and-egress.md`, Allowed egress, two rows"))
        let rowsEnd = try XCTUnwrap(contract.range(of: "### 11.1a", range: rowsStart.upperBound..<contract.endIndex))
        let section = String(contract[rowsStart.upperBound..<rowsEnd.lowerBound])
        let rows = section.components(separatedBy: "\n").filter { $0.hasPrefix("+| OpenRouter") }.map { String($0.dropFirst()) }
        XCTAssertEqual(rows.count, 2)
        let egressLines = egress.components(separatedBy: "\n")
        for row in rows { XCTAssertEqual(egressLines.filter { $0 == row }.count, 1, "11.1 row: \(row.prefix(60))") }
        let quoteStart = try XCTUnwrap(section.range(of: "`Stays on the device unless the user sends it`, added: \""))
        let quoteEnd = try XCTUnwrap(section.range(of: "\"\n", range: quoteStart.upperBound..<section.endIndex))
        let quote = section[quoteStart.upperBound..<quoteEnd.lowerBound].replacingOccurrences(of: "\n", with: " ")
        XCTAssertTrue(quote.hasPrefix("**Confirm suggestions** (#549):"))
        let label = try XCTUnwrap(egressLines.firstIndex { $0.hasPrefix("- **Label photos** leave only") })
        XCTAssertEqual(egressLines[label + 1], "- " + quote, "the Stays-on-device bullet follows Label photos")
        let entryStart = try XCTUnwrap(contract.range(of: "### 11.2 Privacy policy, OpenRouter section (an entry in O1's list)\n\n```text\n"))
        let entryEnd = try XCTUnwrap(contract.range(of: "\n```", range: entryStart.upperBound..<contract.endIndex))
        let entry = String(contract[entryStart.upperBound..<entryEnd.lowerBound])
        XCTAssertTrue(entry.hasPrefix("Confirm suggestions. Only if you also turn on"))
        XCTAssertTrue(policy.contains("Avoid photographing anything other than the nutrition table.\n\n" + entry + "\n\n"),
                      "the 11.2 entry is its own paragraph after Label photo reading")
        XCTAssertTrue(policy.contains("Lookups, label reads and Confirm suggestions need your own OpenRouter API key"))
        XCTAssertFalse(policy.contains("Lookups and label reads need"))
    }
}

/// A key store for consent tests: never the device Keychain, and nothing is ever sent.
private struct SyntheticConsentKeys: FoodWebKeyStoring {
    let key: String?
    func load() throws -> String? { key }
    func save(_ key: String) throws {}
    func delete() throws {}
}
