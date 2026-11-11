import Combine
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import Foundation
import SwiftUI
import UIKit
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
            footer: "Online sources receive only the food terms you search for. Your Health data and food log stay on this device unless you export them to Google Drive.",
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
    @MainActor
    static func section(personalFoodDatabase: PersonalFoodDatabaseSettingsViewModel? = nil) -> SettingsSection {
        var databaseRows: [SettingsRow] = []
        if let personalFoodDatabase {
            databaseRows = [.link(PersonalFoodDatabaseSettingsText.title, route: .personalFoodDatabase, detail: { [weak personalFoodDatabase] in
                personalFoodDatabase?.rowDetail
            }, changes: personalFoodDatabase.$state.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher())]
        }
        return SettingsSection(
            id: .data,
            title: "Data",
            footer: nil,
            rows: [
                .link("Backup and restore", route: .dataBackup)] + databaseRows + [
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
            DataSettingsContribution.section(personalFoodDatabase: personalFoodDatabase)
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
                Text("Food search mixes Taiwan results in with UK and US results when the market is Taiwan, or when your search names Taiwan or uses Chinese characters; otherwise Taiwan results follow UK and US results. Web lookup sends the chosen market with your food terms. Choose Unspecified to clear the preference.")
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

/// Whether protected data is readable, read live from `UIApplication` for the file stores that
/// run off the main actor (a cached value can miss the launch-time state). Constraint: off the main
/// thread it waits on the main queue, so main-thread code must never wait synchronously on a store
/// that calls it (the importer is an actor reached only with `await`).
enum ProtectedDataAvailability {
    @Sendable static func isAvailable() -> Bool {
        if Thread.isMainThread { return MainActor.assumeIsolated { UIApplication.shared.isProtectedDataAvailable } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { UIApplication.shared.isProtectedDataAvailable } }
    }
}

/// Reads a picked file within security-scoped access, refusing it before reading when it is over
/// the import v1 size limit.
enum PersonalFoodDatabasePickedFile {
    enum Failure: Error { case tooLarge, unreadable }

    static func read(_ url: URL) throws(Failure) -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw .unreadable }
        guard size <= PersonalFoodDatabaseCodec.limitBytes else { throw .tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw .unreadable }
        return data
    }
}

/// Settings, Data, Your food database (#424 P1b): import, replace and remove.
struct PersonalFoodDatabaseSettingsView: View {
    @ObservedObject var model: PersonalFoodDatabaseSettingsViewModel
    @State private var showsImport = false
    @State private var confirmsRemove = false

    private static let generatedStyle = Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC") ?? .gmt)

    var body: some View {
        Form {
            Section {
                switch model.state {
                case .loading:
                    ProgressView("Checking Your food database")
                case .none:
                    Text(PersonalFoodDatabaseSettingsText.none)
                case let .installed(summary):
                    LabeledContent("Foods", value: PersonalFoodDatabaseSettingsText.foods(summary.entryCount))
                    LabeledContent("Built", value: summary.generated.utcMidnight.formatted(Self.generatedStyle))
                    LabeledContent("Imported", value: summary.importedAt.formatted(date: .long, time: .shortened))
                case .locked:
                    Label(PersonalFoodDatabaseSettingsText.locked, systemImage: "lock")
                case .damaged:
                    Label(PersonalFoodDatabaseSettingsText.damaged, systemImage: "exclamationmark.triangle")
                }
            }
            Section {
                Button(model.importTitle) { showsImport = true }
                    .disabled(model.isWorking || model.state == .loading || model.state == .locked)
                if model.canRemove {
                    Button("Remove", role: .destructive) { confirmsRemove = true }
                }
            } footer: {
                Text(PersonalFoodDatabaseSettingsText.notSearchedYet)
            }
            if model.isWorking {
                Section { ProgressView("Working") }
            }
            if let message = model.message {
                Section { Text(message) }
            }
        }
        .navigationTitle(PersonalFoodDatabaseSettingsText.title)
        .task { await model.load() }
        .fileImporter(isPresented: $showsImport, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            // Up to 25 MB: read off the main thread.
            Task {
                let read = await Task.detached { () -> Result<Data, PersonalFoodDatabasePickedFile.Failure> in
                    do throws(PersonalFoodDatabasePickedFile.Failure) { return .success(try PersonalFoodDatabasePickedFile.read(url)) }
                    catch { return .failure(error) }
                }.value
                switch read {
                case let .success(data): await model.importFile(data)
                case let .failure(error): model.reportUnreadableFile(tooLarge: error == .tooLarge)
                }
            }
        }
        .onChange(of: model.messageSerial) {
            if let message = model.message { AccessibilityNotification.Announcement(message).post() }
        }
        .confirmationDialog(PersonalFoodDatabaseSettingsText.removeConfirmation, isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await model.remove() } }
        }
    }
}
