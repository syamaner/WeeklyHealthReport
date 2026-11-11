import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// Copy for Your food database in Settings (phase 1 plan section 3). No message carries an entry
/// ID, title, value or source field: rejections are grouped by rule code.
public enum PersonalFoodDatabaseSettingsText {
    public static let title = "Your food database"
    public static let notChanged = "Your food database was not changed."
    public static let lockedDetail = "Locked"
    public static let damagedDetail = "Needs replacing"
    public static let noneDetail = "Not added"
    public static let locked = "Your food database is locked until you unlock your iPhone."
    public static let damaged = "Your food database could not be read. Import the file again to replace it. Saved food is not affected."
    public static let none = "Add the file built on your Mac with the personal food catalogue. It stays on this iPhone and is not backed up or sent anywhere."
    public static let notSearchedYet = "Food search does not use this file yet."
    public static let removeConfirmation = "Remove Your food database? Saved food and its sources are kept."
    public static let removed = "Your food database was removed. Saved food is kept."

    public static func foods(_ count: Int) -> String { count == 1 ? "1 food" : "\(count) foods" }

    public static func message(for outcome: PersonalFoodDatabaseImportOutcome) -> String {
        switch outcome {
        case .installed: "Your food database was updated."
        case .unchanged: "This file is already your food database."
        case let .rejected(codes): "\(reason(for: codes)) \(notChanged)"
        case .releaseConflict: "A source in this file disagrees with one already saved. \(notChanged)"
        case .locked: "Unlock your iPhone and try again. \(notChanged)"
        case .writeFailed: "The file could not be saved. \(notChanged)"
        case .tooLarge: "This file is too large for Your food database. \(notChanged)"
        case .ledgerUnavailable: "Saved sources could not be read, so the file was not checked. \(notChanged)"
        }
    }

    public static func message(for outcome: PersonalFoodDatabaseRemoveOutcome) -> String? {
        switch outcome {
        case .removed: removed
        case .nothingToRemove: nil
        case .locked: "Unlock your iPhone and try again. Nothing was removed."
        case .writeFailed: "Your food database could not be removed. Try again."
        }
    }

    /// One short reason for the first rule group present, never file content.
    static func reason(for codes: [PersonalFoodDatabaseRuleCode]) -> String {
        let set = Set(codes)
        if !set.isDisjoint(with: [.size, .count]) { return "This file is too large for Your food database." }
        if !set.isDisjoint(with: [.bom, .encoding, .json, .duplicateKey]) { return "This file is not readable JSON. Export it again from your Mac." }
        if !set.isDisjoint(with: [.schema, .topKeys]) { return "This file is not a food database file from your Mac." }
        if !set.isDisjoint(with: [.generated, .sources, .sourceFields, .sourceForm, .sourceHash, .sourceDate, .sourcePins,
                                  .sourceDuplicate, .corpus, .undeclaredRelease, .releaseKind]) {
            return "The file's source list could not be checked. Export it again from your Mac."
        }
        return "An entry in this file could not be read. Export it again from your Mac."
    }
}

@MainActor
public final class PersonalFoodDatabaseSettingsViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case none
        case installed(PersonalFoodDatabaseSummary)
        case locked
        case damaged
    }

    @Published public private(set) var state: State = .loading
    @Published public private(set) var isWorking = false
    @Published public private(set) var message: String? {
        didSet { messageSerial += 1 }
    }
    /// Changes with every outcome, even when its text repeats, so each one can be announced.
    @Published public private(set) var messageSerial = 0
    private let importer: any PersonalFoodDatabaseImporting

    public init(importer: any PersonalFoodDatabaseImporting) { self.importer = importer }

    /// The Settings row's detail.
    public var rowDetail: String? {
        switch state {
        case .loading: nil
        case .none: PersonalFoodDatabaseSettingsText.noneDetail
        case let .installed(summary): PersonalFoodDatabaseSettingsText.foods(summary.entryCount)
        case .locked: PersonalFoodDatabaseSettingsText.lockedDetail
        case .damaged: PersonalFoodDatabaseSettingsText.damagedDetail
        }
    }

    public var importTitle: String {
        if case .none = state { return "Import file" }
        return "Replace file"
    }

    public var canRemove: Bool {
        switch state {
        case .installed, .damaged: !isWorking
        case .loading, .none, .locked: false
        }
    }

    public func load() async {
        state = Self.state(await importer.status())
    }

    public func importFile(_ bytes: Data) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        message = PersonalFoodDatabaseSettingsText.message(for: await importer.importFile(bytes))
        await load()
    }

    public func remove() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        message = PersonalFoodDatabaseSettingsText.message(for: await importer.remove())
        await load()
    }

    /// A picked file that could not be read or is over the size limit, before any import.
    public func reportUnreadableFile(tooLarge: Bool) {
        message = PersonalFoodDatabaseSettingsText.message(for: tooLarge ? .tooLarge : .writeFailed)
        if !tooLarge { message = "The file could not be opened. \(PersonalFoodDatabaseSettingsText.notChanged)" }
    }

    static func state(_ status: PersonalFoodDatabaseStatus) -> State {
        switch status {
        case .none: .none
        case let .installed(summary): .installed(summary)
        case .locked: .locked
        case .damaged: .damaged
        }
    }
}
