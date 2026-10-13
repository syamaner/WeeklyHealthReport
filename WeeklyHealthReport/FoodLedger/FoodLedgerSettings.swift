import FoodLedgerApplication
import FoodLedgerPresentation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The single accessor for the remembered web lookup market.
/// `.unspecified` removes the stored value rather than storing it.
struct FoodMarketPreference {
    static let key = "food.webReview.market.v1"
    let defaults: UserDefaults

    var market: FoodReviewMarket {
        get { FoodReviewMarket(rawValue: defaults.string(forKey: Self.key) ?? "") ?? .unspecified }
        nonmutating set {
            if newValue == .unspecified { defaults.removeObject(forKey: Self.key) }
            else { defaults.set(newValue.rawValue, forKey: Self.key) }
        }
    }
}

@MainActor
enum FoodSearchSettingsContribution {
    /// Reads only local key state. Opening Settings never validates a key.
    static func webLookupDetail(hasSavedKey: Bool, keyIsUsable: Bool) -> String {
        if keyIsUsable { return "Key added" }
        return hasSavedKey ? "Revalidate key" : "Key missing"
    }

    static func section(
        preferences: any FoodSearchPreferences,
        onlineDatabaseAvailable: Bool,
        webLookup: FoodWebDiscoveryViewModel,
        market: FoodMarketPreference
    ) -> SettingsSection {
        let onlineDatabase = SettingsToggle(
            title: "Online food database",
            caption: "Open Food Facts. When local matches need more evidence, a submitted search can send the displayed food terms. Changing this takes effect on your next search. Community product data can be incomplete. Compare the package and nutrition basis before choosing.",
            isEnabled: onlineDatabaseAvailable,
            read: { preferences.onlineDatabaseEnabled },
            write: { preferences.onlineDatabaseEnabled = $0 }
        )
        return SettingsSection(
            id: .foodSearch,
            title: "Food search",
            footer: "Online sources receive only the food terms you search for. Your Health data and food log stay on this device.",
            footerLink: SettingsExternalLink(
                title: "Open Food Facts terms and data licences",
                url: URL(string: "https://world.openfoodfacts.org/terms-of-use")!
            ),
            rows: [
                .toggle("onlineFoodDatabase", onlineDatabase),
                .link("Web lookup", route: .webLookupKey) { [weak webLookup] in
                    guard let webLookup else { return nil }
                    return webLookupDetail(hasSavedKey: webLookup.hasSavedKey, keyIsUsable: webLookup.keyIsUsable)
                },
                .link("Food market", route: .foodMarket) { market.market.rawValue }
            ]
        )
    }
}

enum DataSettingsContribution {
    static func section() -> SettingsSection {
        SettingsSection(
            id: .data,
            title: "Data",
            footer: nil,
            rows: [
                .link("Backup and restore", route: .dataBackup),
                .link("Receipts and food inventory", route: .inventoryReview),
                .link("Usual foods", route: .commonFoods),
                .link("Nutrition updates", route: .foodReresolution)
            ]
        )
    }
}

extension FoodLedgerCompositionRoot {
    func settingsSections() -> [SettingsSection] {
        [
            FoodSearchSettingsContribution.section(
                preferences: searchPreferencesForSettings,
                onlineDatabaseAvailable: true,
                webLookup: webDiscovery,
                market: foodMarket
            ),
            DataSettingsContribution.section()
        ]
    }
}

struct FoodMarketSelectionView: View {
    let preference: FoodMarketPreference
    @State private var selection: FoodReviewMarket = .unspecified

    var body: some View {
        Form {
            Section {
                ForEach(FoodReviewMarket.allCases) { market in
                    Button {
                        preference.market = market
                        selection = preference.market
                    } label: {
                        HStack {
                            Text(market.rawValue).foregroundStyle(.primary)
                            Spacer()
                            if market == selection {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(market == selection ? .isSelected : [])
                }
            } footer: {
                Text("Food search lists Taiwan results first when the market is Taiwan, or when your search names Taiwan or uses Chinese characters; otherwise they follow UK and US results. Web lookup sends the chosen market with your food terms. Choose Unspecified to clear the preference.")
            }
        }
        .navigationTitle("Food market")
        .onAppear { selection = preference.market }
    }
}

/// Security-scoped access and size guards for restoring an inventory backup.
enum InventoryBackupFile {
    static func validate(size: Int?) throws {
        let size = size ?? 0
        guard size > 0, size <= InventoryBackupCodec.maximumBytes else { throw InventoryStoreError.corruptStore }
    }

    static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try validate(size: try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        return try Data(contentsOf: url)
    }
}

/// Export and restore of the local inventory. `LocalInventoryViewModel` owns
/// the error message and busy state, as it did for the former toolbar menu.
struct InventoryBackupView: View {
    private let root: FoodLedgerCompositionRoot
    @ObservedObject private var model: LocalInventoryViewModel
    @State private var showsExport = false
    @State private var showsImport = false
    @State private var backup = InventoryBackupDocument()

    init?(root: FoodLedgerCompositionRoot) {
        guard let model = try? root.inventoryModel() else { return nil }
        self.root = root
        self.model = model
    }

    var body: some View {
        Form {
            Section {
                Button("Export inventory backup") {
                    do { backup = InventoryBackupDocument(data: try root.inventoryBackup()); showsExport = true }
                    catch { model.report(error) }
                }
                Button("Restore inventory backup") { showsImport = true }
            } footer: {
                Text("Includes original receipts and saved review history. Exported files are not encrypted.")
            }
            .disabled(model.pendingCommand != nil)
            if let message = model.message {
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            }
        }
        .navigationTitle("Backup and restore")
        .fileExporter(isPresented: $showsExport, document: backup, contentType: .json, defaultFilename: "inventory-backup") { result in
            if case let .failure(error) = result { model.report(error) }
        }
        .fileImporter(isPresented: $showsImport, allowedContentTypes: [.json]) { result in
            do {
                try root.restoreInventoryBackup(InventoryBackupFile.read(try result.get()))
            } catch let error as CocoaError where error.code == .userCancelled { }
            catch { model.report(error) }
        }
    }
}
