import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerPresentation
import Foundation

@MainActor
final class FoodLedgerCompositionRoot {
    private let store: FoodLedgerGRDBStore
    private let confirmations: FoodConfirmationService
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
