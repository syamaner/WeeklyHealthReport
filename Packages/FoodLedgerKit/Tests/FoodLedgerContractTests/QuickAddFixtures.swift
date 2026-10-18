import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Deterministic IDs for quick add contracts (one sequence per context).
final class QuickAddSequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    init(start: Int = 5_000) { value = start }
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}

/// One store with the services quick add uses.
struct QuickAddContext {
    let harness: TestHarness
    let ledger: FoodLedgerService
    let confirmations: FoodConfirmationService
    let favourites: FavouritesService
    let management: FoodLogManagementService
    let ids: QuickAddSequenceIDs

    init(_ harness: TestHarness, clock: any LedgerClock = LedgerFixtures.clock, calendar: Calendar = QuickAddFixtures.london,
         ids: QuickAddSequenceIDs = QuickAddSequenceIDs()) throws {
        self.harness = harness
        self.ids = ids
        ledger = try LedgerFixtures.service(harness.committer)
        confirmations = FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: clock, ids: ids,
                                                digester: SHA256Digester(), calendar: calendar)
        let reader = try XCTUnwrap(harness.committer as? any FavouriteReading)
        favourites = try FavouritesService(ledger: ledger, reader: reader, confirmations: confirmations, clock: clock,
                                           ids: ids, digester: SHA256Digester(), calendar: calendar)
        let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
        management = FoodLogManagementService(ledger: ledger, reader: ArchiveFoodLogHistoryReader(archive: archive),
                                              clock: clock, ids: ids)
    }

    var archive: any FoodArchiveLedgerAccess { harness.committer as! any FoodArchiveLedgerAccess }
    func records() throws -> LedgerMutation { try archive.archiveState().records }
    func operations() throws -> [LedgerOperation] { try archive.archiveState().operations }

    /// Logs an exact synthetic product through Confirm (150 g, Now).
    @discardableResult
    func logExact(_ number: Int, aliases: [String] = ["fixture food \(UUID().uuidString.prefix(4))"],
                  amount: Double = 150) throws -> StoredFoodConfirmation {
        var state = FoodConfirmationState(input: try QuickAddFixtures.exactInput(number, aliases: aliases), prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(amount, .grams))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return try confirmations.save(state, operationID: ids.makeID(OperationTag.self))
    }

    /// Logs plain water through the quick-add path (the built-in item), accepted at Log.
    @discardableResult
    func logWater(_ millilitres: Double, occurredAt: Date? = nil) throws -> StoredFoodConfirmation {
        var state = try favourites.prepare(.builtInWater).state
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(millilitres, .millilitres))
        if let occurredAt { FoodConfirmationReducer.reduce(state: &state, action: .setOccurredAt(occurredAt)) }
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return try confirmations.save(state, operationID: ids.makeID(OperationTag.self))
    }

    /// Logs a prepared quick-add state as the sheet's Log does.
    func log(_ preparation: QuickAddPreparation, amount: Double? = nil) throws -> StoredFoodConfirmation {
        var state = preparation.state
        if let amount { FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(amount, state.quantity.unit)) }
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return try confirmations.save(state, operationID: ids.makeID(OperationTag.self))
    }
}

enum QuickAddFixtures {
    static var london: Calendar { calendar("Europe/London") }

    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static func contexts(clock: any LedgerClock = LedgerFixtures.clock, calendar: Calendar = london) throws -> [QuickAddContext] {
        try LedgerFixtures.harnesses().map { try QuickAddContext($0, clock: clock, calendar: calendar) }
    }

    /// An exact product (user-verified panel, fully known identity, known 100 g edible quantity).
    static func exactInput(_ number: Int, aliases: [String] = [], expected: DecisiveIdentity? = nil) throws -> PopulatedFoodConfirmation {
        let evidenceID: EvidenceID = try LedgerFixtures.id(number, EvidenceTag.self)
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .synthetic, capturedAt: LedgerFixtures.date,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("synthetic_fixture"), captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("fixture \(number)")))
        let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: try ExternalIdentifier("physical_package"),
            sourceReleaseID: try ExternalIdentifier("package:fixture-v1"), evidenceID: evidenceID, capturedAt: LedgerFixtures.date)
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard [.protein, .energyConsumed].contains(key) else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            let amount = key == .protein ? 10.0 : 200.0
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [provenance])))
        })
        let metadata = aliases.isEmpty ? nil : try CandidateMatchMetadata(methodVersion: LedgerText("fixture-match-v1"),
            score: 1, materialDifferences: [], libraryAliases: aliases.map { try LedgerText($0) })
        let quantity = EdibleQuantityIdentity.known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil)
        let candidate = try PopulatedFoodCandidate(
            candidate: ProviderNeutralCandidate(sourceReleaseID: try ExternalIdentifier("package:fixture-v1"),
                recordID: try ExternalIdentifier("fixture:row-\(number)"), identity: try LedgerFixtures.identity(),
                edibleQuantity: quantity, nutrients: nutrients, evidenceIDs: [evidenceID], matchMetadata: metadata),
            name: try LedgerText("Fixture food \(number)"), itemClass: .food)
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [try LedgerFixtures.packageSourceRelease()],
            candidates: [candidate], expectedIdentity: expected ?? LedgerFixtures.identity(), expectedEdibleQuantity: quantity)
    }

    static func rawIdentity() throws -> DecisiveIdentity {
        try DecisiveIdentity(preparation: PreparationState(kind: .raw), bone: .notApplicable, skin: .notApplicable,
            drained: .notApplicable, packingMedium: .named(LedgerText("none")), fortification: .unfortified, servingBasis: .per100Grams)
    }

    static func correction(_ candidate: PopulatedFoodCandidate) throws -> FoodCorrection {
        try FoodCorrection(name: LedgerText("Corrected food"), brand: nil, variant: nil, identity: LedgerFixtures.identity(),
            itemClass: .food, nutrients: candidate.candidate.nutrients, reason: LedgerText("Synthetic identity correction"))
    }

    static func favouriteVersion(_ number: Int, favourite: Int, ordinal: Int = 1, supersedes: Int? = nil,
                                 binding: FavouriteBinding = .reference(.plainWaterV1), state: FavouriteState = .active,
                                 at offset: TimeInterval = 0) throws -> FavouriteVersion {
        try FavouriteVersion(favouriteVersionID: LedgerFixtures.id(number, FavouriteVersionTag.self),
            favouriteID: LedgerFixtures.id(favourite, FavouriteTag.self), ordinal: VersionOrdinal(ordinal),
            supersedesFavouriteVersionID: try supersedes.map { try LedgerFixtures.id($0, FavouriteVersionTag.self) },
            binding: binding, label: LedgerText("Favourite \(favourite)"),
            defaultAmount: FavouriteAmount(value: 250, unit: .millilitres), state: state,
            createdAt: LedgerFixtures.date.addingTimeInterval(offset))
    }
}
