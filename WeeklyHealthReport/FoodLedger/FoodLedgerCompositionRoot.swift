import FoodLedgerApplication
import FoodLedgerDomain
import FoodGenericSearch
import FoodLedgerGRDB
import FoodLedgerPresentation
import Foundation
import SwiftUI

@MainActor
final class FoodLedgerCompositionRoot {
    private let store: FoodLedgerGRDBStore
    private let confirmations: FoodConfirmationService
    private let genericFoodSearch: CoFIDGenericFoodSearch
    private let ids: RandomLedgerIDGenerator

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) throws {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = applicationSupport
            .appendingPathComponent("WeeklyHealthReport", isDirectory: true)
            .appendingPathComponent("FoodLedger", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        store = try FoodLedgerGRDBStore(
            databaseURL: root.appendingPathComponent("food-ledger.sqlite"),
            attachmentsRoot: root.appendingPathComponent("Attachments", isDirectory: true)
        )
        ids = RandomLedgerIDGenerator()
        let clock = SystemLedgerClock()
        let ledger = FoodLedgerService(
            actorID: try Self.actorID(userDefaults: userDefaults),
            committer: store,
            clock: clock,
            encoder: FoundationCanonicalJSONEncoder(),
            digester: SHA256Digester()
        )
        confirmations = FoodConfirmationService(
            ledger: ledger,
            reader: store,
            clock: clock,
            ids: ids
        )
        genericFoodSearch = try CoFIDGenericFoodSearch(
            library: PersonalLibraryGenericFoodSearch(reader: store),
            ids: ids
        )
    }

    func model(for input: PopulatedFoodConfirmation) -> FoodConfirmationViewModel {
        FoodConfirmationViewModel(state: FoodConfirmationState(input: input)) { [confirmations, ids] state in
            try confirmations.save(
                state,
                operationID: ids.makeID(OperationTag.self),
                idempotencyKey: nil
            )
        }
    }

    func model(reopening logItemID: LogItemID) throws -> FoodConfirmationViewModel? {
        guard let state = try confirmations.reopen(logItemID: logItemID) else { return nil }
        return FoodConfirmationViewModel(state: state) { [confirmations, ids] state in
            try confirmations.save(
                state,
                operationID: ids.makeID(OperationTag.self),
                idempotencyKey: nil
            )
        }
    }

    func genericFoodSearchModel(locale: Locale = .current) throws -> GenericFoodSearchViewModel {
        GenericFoodSearchViewModel(
            searcher: genericFoodSearch,
            locale: try LedgerText(locale.identifier)
        )
    }

    private static func actorID(userDefaults: UserDefaults) throws -> ActorID {
        let key = "foodLedger.actorID.v1"
        if let stored = userDefaults.string(forKey: key) {
            return try ActorID(stored)
        }
        let created = try ActorID(UUID().uuidString.lowercased())
        userDefaults.set(created.rawValue, forKey: key)
        return created
    }
}

struct GenericFoodSearchFlowView: View {
    private let root: FoodLedgerCompositionRoot
    @StateObject private var searchModel: GenericFoodSearchViewModel
    @State private var confirmation: PopulatedFoodConfirmation?
    @State private var showsConfirmation = false

    init?(root: FoodLedgerCompositionRoot) {
        guard let model = try? root.genericFoodSearchModel() else { return nil }
        self.root = root
        _searchModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        GenericFoodSearchView(model: searchModel) { input in
            confirmation = input
            showsConfirmation = true
        }
        .navigationDestination(isPresented: $showsConfirmation) {
            if let confirmation {
                FoodConfirmationView(model: root.model(for: confirmation)) {
                    showsConfirmation = false
                }
            }
        }
    }
}
