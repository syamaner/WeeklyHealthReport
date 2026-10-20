import FoodLedgerApplication
import FoodLedgerDomain
import FoodGenericSearch
import FoodLedgerGRDB
import FoodLedgerPresentation
import FoodBarcodeCapture
import FoodInventoryImport
import FoodLabelTextCapture
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FoodLedgerCompositionRoot {
    private let store: FoodLedgerGRDBStore
    private let confirmations: FoodConfirmationService
    private let favourites: FavouritesService
    private let ledger: FoodLedgerService
    private let genericFoodSearch: any GenericFoodSearching
    private let milkVolumeConversion: CoFIDWholeMilkVolumeConversion
    private let offSearchTransport: OFFHTTPSearchTransport
    private let searchPreferences: FoodSearchUserDefaultsPreferences
    /// The store shared by food search preferences and Settings.
    let userDefaults: UserDefaults
    let foodMarket: FoodMarketPreference
    /// The last search and web lookup diagnostics for Settings › Developer tools. In memory only.
    let searchDiagnostics = FoodSearchDiagnosticsLog()
    let webDiscovery: FoodWebDiscoveryViewModel
    private let proposalReviewer: GenericFoodProposalReviewer
    private let proposalConfirmation: ReviewedFoodProposalConfirmation
    private let offLookup: OpenFoodFactsLookup
    private let ids: RandomLedgerIDGenerator
    private var activeFoodList: FoodListImportViewModel?
    private let inventoryURL: URL
    /// One clock and one calendar for Confirm: the view model's When bounds and the
    /// authoritative save service use the same values (food_confirmation_v5).
    private let confirmationClock: any LedgerClock
    private let confirmationCalendar: Calendar
    private let draftURL: URL
    private var activeInventory: LocalInventoryViewModel?
    private var inventoryService: LocalInventoryService?
    private var activeReresolution: FoodReresolutionViewModel?
    /// Pasted nutrition label (#93): the reader and the confirmation builder behind their
    /// application ports. The parser is reached only through the `FoodLabelTextCapture` adapter
    /// wired here; the label text screen and Confirm reach them through `pastedLabelTextModel()`.
    let pastedLabelReader: PastedLabelReader
    let pastedLabelConfirmation: PastedLabelConfirmation

    /// `confirmationClock` and `confirmationCalendar` are injectable so tests can fix the day
    /// rules (the backdating window) instead of racing the live clock.
    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        confirmationClock: any LedgerClock = SystemLedgerClock(),
        confirmationCalendar: Calendar = .autoupdatingCurrent
    ) throws {
        self.confirmationClock = confirmationClock
        self.confirmationCalendar = confirmationCalendar
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let healthDirectory = applicationSupport.appendingPathComponent("WeeklyHealthReport", isDirectory: true)
        try LocalHealthStorageDirectory.prepare(healthDirectory, fileManager: fileManager)
        let root = healthDirectory
            .appendingPathComponent("FoodLedger", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        inventoryURL = applicationSupport.appendingPathComponent("WeeklyHealthReport/Inventory/v1/inventory.sqlite")
        draftURL = root.appendingPathComponent("food-list-draft.sqlite")
        store = try FoodLedgerGRDBStore(
            databaseURL: root.appendingPathComponent("food-ledger.sqlite"),
            attachmentsRoot: root.appendingPathComponent("Attachments", isDirectory: true)
        )
        ids = RandomLedgerIDGenerator()
        offLookup = OpenFoodFactsLookup(transport: OFFHTTPSProductTransport(userAgent: "WeeklyHealthReport/0.1.1 (proxy@sertan.com)"))
        offSearchTransport = OFFHTTPSearchTransport(userAgent: "WeeklyHealthReport/0.1.1 (proxy@sertan.com)")
        searchPreferences = FoodSearchUserDefaultsPreferences(defaults: userDefaults)
        self.userDefaults = userDefaults
        foodMarket = FoodMarketPreference(defaults: userDefaults)
        let clock = SystemLedgerClock()
        let openRouter = OpenRouterFoodProvider(extractionRoute: .grok, selectionRoute: .applicability)
        webDiscovery = FoodWebDiscoveryViewModel(provider: openRouter, keys: OpenRouterKeychainStore(),
            providerName: "OpenRouter", operatorName: "OpenRouter", keyManagementName: "OpenRouter settings")
        proposalReviewer = GenericFoodProposalReviewer(discovery: openRouter, capture: PublicFoodSourceCapture(),
            extraction: openRouter, sourceSelection: openRouter, selection: openRouter)
        proposalConfirmation = ReviewedFoodProposalConfirmation(ids: ids, clock: clock,
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        ledger = FoodLedgerService(
            actorID: try Self.actorID(userDefaults: userDefaults),
            committer: store,
            clock: clock,
            encoder: FoundationCanonicalJSONEncoder(),
            digester: SHA256Digester()
        )
        // Save and reopen recompute pasted-label conversions through the adapter's checker.
        let pastedLabelConversions = NutritionLabelConversionChecker()
        pastedLabelReader = PastedLabelReader(reader: NutritionLabelTextReader(), digester: SHA256Digester())
        pastedLabelConfirmation = PastedLabelConfirmation(ids: ids, clock: confirmationClock,
            encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester(), conversions: pastedLabelConversions)
        confirmations = FoodConfirmationService(
            ledger: ledger,
            reader: store,
            clock: confirmationClock,
            ids: ids,
            digester: SHA256Digester(),
            calendar: confirmationCalendar,
            pastedLabelConversions: pastedLabelConversions
        )
        favourites = try FavouritesService(ledger: ledger, reader: store, confirmations: confirmations,
            clock: confirmationClock, ids: ids, digester: SHA256Digester(), calendar: confirmationCalendar)
        // Taiwan rows follow UK and US rows unless the Settings market is Taiwan or the
        // query names Taiwan or contains Chinese characters (composite-generic-ranking-v9).
        let market = foodMarket
        genericFoodSearch = try CompositeGenericFoodSearch(sources: [
            CoFIDGenericFoodSearch(library: PersonalLibraryGenericFoodSearch(reader: store), ids: ids),
            USDAGenericFoodSearch(ids: ids)
        ], regionalSources: [TFDAGenericFoodSearch(ids: ids)], promotesRegional: { request in
            RegionalSourceOrderPolicy.promotesTaiwan(query: request.text.value, marketIsTaiwan: market.market == .taiwan)
        }, ids: ids)
        milkVolumeConversion = try CoFIDWholeMilkVolumeConversion()
    }

    func model(for input: PopulatedFoodConfirmation, queryQuantity: ParsedFoodQuery.Quantity? = nil, searchInterpretation: FoodQueryInterpretation? = nil, prefillSourceQuantity: Bool = true, savesFavourite: Bool = false, entryDay: String? = nil) -> FoodConfirmationViewModel {
        let (prepared, offering) = withMilkVolumeSource(input)
        var state = FoodConfirmationState(input: prepared, queryQuantity: queryQuantity, prefillSourceQuantity: prefillSourceQuantity)
        let when = entryWhen(day: entryDay)
        state.occurredAt = when.occurredAt
        let clock = confirmationClock
        return FoodConfirmationViewModel(state: state, volumeConversionOffering: offering, searchInterpretation: searchInterpretation,
                                         now: { clock.now() }, calendar: confirmationCalendar,
                                         savesFavourite: savesFavourite, favouriteAction: favouriteAction,
                                         whenNotice: FoodLogText.whenNotice(when)) { [confirmations, ids] state in
            try confirmations.save(
                state,
                operationID: ids.makeID(OperationTag.self),
                idempotencyKey: nil
            )
        }
    }

    private func withMilkVolumeSource(_ input: PopulatedFoodConfirmation)
        -> (PopulatedFoodConfirmation, (any FoodVolumeConversionOffering)?) {
        var prepared = input
        var offering: (any FoodVolumeConversionOffering)?
        if input.candidates.contains(where: milkVolumeConversion.applies(to:)) {
            let release = milkVolumeConversion.sourceRelease
            let releases = input.sourceReleases.contains(where: { $0.sourceReleaseID == release.sourceReleaseID })
                ? input.sourceReleases : input.sourceReleases + [release]
            if let enriched = try? PopulatedFoodConfirmation(
                evidence: input.evidence, sourceReleases: releases, candidates: input.candidates,
                expectedIdentity: input.expectedIdentity, expectedEdibleQuantity: input.expectedEdibleQuantity
            ) {
                prepared = enriched
                offering = milkVolumeConversion
            }
        }
        return (prepared, offering)
    }

    /// When for a new entry from Add food at this moment (owner decision D): a past Food Log day
    /// at the current clock time, or Now. Read with the confirmation clock and calendar, so the
    /// prefill and the save service agree on the window.
    func entryWhen(day: String?) -> FoodEntryWhenPrefill {
        FoodEntryWhenPrefill.resolve(dayKey: day, now: confirmationClock.now(), calendar: confirmationCalendar)
    }

    /// Confirm for logging a recent food again as a new entry: source re-verified, last value
    /// and unit prefilled, nothing saved until Log.
    func model(relogging logItemID: LogItemID, entryDay: String? = nil) throws -> FoodConfirmationViewModel? {
        guard var state = try confirmations.relogState(logItemID: logItemID) else { return nil }
        let (prepared, offering) = withMilkVolumeSource(state.input)
        if prepared != state.input {
            let quantity = state.quantity
            state = FoodConfirmationState(input: prepared, prefillSourceQuantity: false)
            state.quantity = quantity
        }
        let when = entryWhen(day: entryDay)
        state.occurredAt = when.occurredAt
        let clock = confirmationClock
        return FoodConfirmationViewModel(state: state, volumeConversionOffering: offering,
                                         now: { clock.now() }, calendar: confirmationCalendar,
                                         favouriteAction: favouriteAction,
                                         whenNotice: FoodLogText.whenNotice(when)) { [confirmations, ids] state in
            try confirmations.save(state, operationID: ids.makeID(OperationTag.self), idempotencyKey: nil)
        }
    }

    // MARK: Favourites and quick add (#198)

    /// Writes `save_favourite_v1` for a logged entry version (Confirm's "Save as favourite").
    var favouriteAction: @MainActor @Sendable (LogItemVersionID) throws -> Void {
        { [favourites] versionID in _ = try favourites.saveFavourite(logItemVersionID: versionID) }
    }

    func favouritesModel() -> FavouritesViewModel { FavouritesViewModel(store: favourites) }

    /// Save as favourite from a saved entry or a recent food (owner decision A): the existing
    /// `save_favourite_v1` path, pinning the entry's current version.
    /// Recent rows re-read the entry's current product version at tap time.
    func favouriteSaveModel() -> FavouriteSaveModel {
        FavouriteSaveModel(store: favourites) { [store] logItemID in
            guard let current = try store.foodConfirmation(logItemID: logItemID),
                  case .product = current.logItemVersion.composition else { return nil }
            return current.logItemVersion.logItemVersionID
        }
    }

    /// "From what you’ve logged": recent foods within 30 days, each source re-verified. Throws when
    /// the ledger cannot be read, so a failure is never shown as an empty list.
    func loggedFoods(limit: Int = 25) throws -> [FoodRecentRelogItem] {
        let records = try store.archiveState().records
        return FoodRecentItemsService(reader: store, confirmations: confirmations)
            .items(records: records, now: confirmationClock.now(), calendar: confirmationCalendar, limit: limit)
    }

    /// Quick-add items in order (built-in water first until a water favourite exists). Nil when the
    /// favourites cannot be read or have competing versions.
    func quickAddItems() -> [QuickAddItem]? { try? favourites.projection().quickAddItems }

    /// Rebuilds a fresh confirmation for a quick-add item. Writes nothing.
    func quickAddPreparation(_ item: QuickAddItem) throws -> QuickAddPreparation { try favourites.prepare(item) }

    /// The sheet logs the same input Confirm would: the rebuilt input runs through the same
    /// volume-source enrichment as every other Confirm factory.
    func quickAddSheetModel(_ preparation: QuickAddPreparation, entryDay: String? = nil) -> QuickAddSheetModel {
        let clock = confirmationClock
        var state = withMilkVolumeSource(preparation.state).state
        let when = entryWhen(day: entryDay)
        state.occurredAt = when.occurredAt
        let prepared = preparation.replacingState(state)
        return QuickAddSheetModel(preparation: prepared, now: { clock.now() }, calendar: confirmationCalendar,
                                  whenNotice: FoodLogText.whenNotice(when)) { [confirmations, ids] state in
            try confirmations.save(state, operationID: ids.makeID(OperationTag.self), idempotencyKey: nil)
        }
    }

    /// Confirm for a quick-add state: an ineligible favourite, or the sheet's Edit. Fresh explicit
    /// confirmation through the same save path, with the offered volume source carried into Confirm.
    /// `entryDay` applies only when Confirm opens straight from a quick-add item; the sheet's Edit
    /// passes nil and keeps the When already chosen on the sheet.
    func model(quickAdd state: FoodConfirmationState, entryDay: String? = nil) -> FoodConfirmationViewModel {
        let clock = confirmationClock
        let enriched = withMilkVolumeSource(state)
        var prepared = enriched.state
        let offering = enriched.offering
        var whenNotice: String?
        if let entryDay {
            let when = entryWhen(day: entryDay)
            prepared.occurredAt = when.occurredAt
            whenNotice = FoodLogText.whenNotice(when)
        }
        return FoodConfirmationViewModel(state: prepared, volumeConversionOffering: offering, now: { clock.now() },
                                         calendar: confirmationCalendar,
                                         favouriteAction: favouriteAction, whenNotice: whenNotice) { [confirmations, ids] state in
            try confirmations.save(state, operationID: ids.makeID(OperationTag.self), idempotencyKey: nil)
        }
    }

    /// An unsaved state with its input enriched by the milk volume source, keeping amount and time.
    private func withMilkVolumeSource(_ state: FoodConfirmationState) -> (state: FoodConfirmationState, offering: (any FoodVolumeConversionOffering)?) {
        let (input, offering) = withMilkVolumeSource(state.input)
        guard input != state.input else { return (state, offering) }
        var enriched = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        enriched.quantity = state.quantity
        enriched.occurredAt = state.occurredAt
        return (enriched, offering)
    }

    /// Plain water logged today as a total, so a known minimum keeps its style (Q8).
    func plainWaterTotal(for date: Date, calendar: Calendar = .current) throws -> FoodIntakeTotal? {
        try PlainWaterDayTotal.total(records: store.archiveState().records,
                                     reportingDate: FoodReportingDay.key(for: date, calendar: calendar))
    }

    /// Recent foods for Add food: 10 items within 30 days, each source re-verified (P1, P3).
    func recentFoods() -> [FoodRecentRelogItem] {
        guard let records = try? store.archiveState().records else { return [] }
        return FoodRecentItemsService(reader: store, confirmations: confirmations)
            .items(records: records, now: confirmationClock.now(), calendar: confirmationCalendar)
    }

    /// The confirmation clock and calendar, so Add food's "today" and "yesterday" match Confirm.
    var confirmationNow: Date { confirmationClock.now() }
    var confirmationDayCalendar: Calendar { confirmationCalendar }

    func model(reopening logItemID: LogItemID) throws -> FoodConfirmationViewModel? {
        guard var state = try confirmations.reopen(logItemID: logItemID) else { return nil }
        let (prepared, offering) = withMilkVolumeSource(state.input)
        if prepared != state.input {
            state = FoodConfirmationState(input: prepared, reopened: state.reopened)
            state.decision = .accepted
        }
        let clock = confirmationClock
        return FoodConfirmationViewModel(state: state, volumeConversionOffering: offering,
                                         now: { clock.now() }, calendar: confirmationCalendar,
                                         favouriteAction: favouriteAction) { [confirmations, ids] state in
            try confirmations.save(
                state,
                operationID: ids.makeID(OperationTag.self),
                idempotencyKey: nil
            )
        }
    }

    var searchPreferencesForSettings: any FoodSearchPreferences { searchPreferences }

    func genericFoodSearchModel(
        locale: Locale = .current, additionalEvidence: [CaptureEvidence] = []
    ) throws -> GenericFoodSearchViewModel {
        GenericFoodSearchViewModel(
            searcher: genericFoodSearch,
            locale: try LedgerText(locale.identifier),
            additionalEvidence: additionalEvidence,
            database: OpenFoodFactsSearch(transport: offSearchTransport, locale: try LedgerText(locale.identifier), ids: ids),
            preferences: searchPreferences
        )
    }

    func proposalReviewModel(initialQuery: String) throws -> GenericFoodProposalReviewViewModel {
        let model = try GenericFoodProposalReviewViewModel(reviewer: proposalReviewer, credentials: webDiscovery,
            confirmation: proposalConfirmation, locale: LedgerText(Locale.current.identifier),
            initialMarket: foodMarket.market,
            saveMarket: { [foodMarket] market in foodMarket.market = market })
        model.foodTerms = initialQuery
        return model
    }

    func lookupOFF(_ route: BarcodeFallbackRoute) async throws -> PackagedFoodLookupOutcome {
        guard let identity = route.identity else { throw OFFLookupError.unsupportedCode }
        return try await offLookup.lookup(PackagedFoodLookupRequest(identity: identity, evidence: route.evidence))
    }

    func barcodeModel() -> BarcodeCaptureViewModel {
        BarcodeCaptureViewModel(coordinator: BarcodeCaptureCoordinator(
            search: PersonalLibraryBarcodeSearch(reader: store), ids: ids
        ))
    }

    func inventoryModel() throws -> LocalInventoryViewModel {
        if let activeInventory { return activeInventory }
        let service = LocalInventoryService(
            store: try LocalInventoryGRDBStore(databaseURL: inventoryURL),
            digester: SHA256Digester(), clock: SystemLedgerClock()
        )
        let model = try LocalInventoryViewModel(service: service, ids: ids, clock: SystemLedgerClock(),
            checkpointStore: InventoryReviewCheckpointGRDBStore(databaseURL: inventoryURL.deletingLastPathComponent().appendingPathComponent("review-draft.sqlite")))
        inventoryService = service
        activeInventory = model
        return model
    }

    func reresolutionModel() throws -> FoodReresolutionViewModel {
        if let activeReresolution { return activeReresolution }
        let service = FoodReresolutionService(
            ledger: ledger, reader: FoodReresolutionHistory(archive: store, confirmations: store),
            provider: try CoFIDReresolutionProvider(ids: ids), clock: SystemLedgerClock(), ids: ids
        )
        let model = FoodReresolutionViewModel(service: service)
        activeReresolution = model
        return model
    }

    func inventoryEvidence(_ product: InventoryProductVersion) throws -> CaptureEvidence {
        guard let inventoryService else { throw InventoryStoreError.invalidReference }
        return try inventoryService.selectionEvidence(for: product, evidenceID: ids.makeID(EvidenceTag.self), locale: LedgerText(Locale.current.identifier))
    }

    func inventoryBackup() throws -> Data {
        _ = try inventoryModel()
        guard let adapter = inventoryService?.store as? LocalInventoryGRDBStore else { throw InventoryStoreError.invalidReference }
        return try adapter.exportBackup()
    }

    func restoreInventoryBackup(_ data: Data) throws {
        let model = try inventoryModel()
        guard model.pendingCommand == nil, let adapter = inventoryService?.store as? LocalInventoryGRDBStore else { throw InventoryStoreError.invalidReference }
        try adapter.restoreBackup(data)
        model.reload(keepingDrafts: true)
    }

    func foodListModel(locale: Locale = .current) throws -> FoodListImportViewModel {
        if let activeFoodList { return activeFoodList }
        let model = FoodListImportViewModel(
            service: FoodListImportService(searcher: genericFoodSearch, ids: ids),
            locale: try LedgerText(locale.identifier), ids: ids,
            checkpointStore: try FoodListCheckpointGRDBStore(databaseURL: draftURL),
            recoveredLogItemID: { [ledger] operationID in
                try ledger.confirmedLogItemID(operationID: operationID, idempotencyKey: LedgerText("food-list:\(operationID.rawValue)"))
            },
            confirmationNow: { [confirmationClock] in confirmationClock.now() },
            confirmationCalendar: confirmationCalendar,
            amountLocale: locale,
            // The same whole-milk volume source and offering as the search route.
            prepareConfirmation: { [weak self] state in self?.withMilkVolumeSource(state) ?? (state: state, offering: nil) }
        ) { [confirmations] state, operationID in
            try confirmations.save(
                state, operationID: operationID,
                idempotencyKey: LedgerText("food-list:\(operationID.rawValue)")
            )
        }
        activeFoodList = model
        return model
    }

    func foodSpeechVocabulary() throws -> [String] {
        let records = try store.archiveState().records
        let superseded = Set(records.productVersions.compactMap(\.supersedesProductVersionID))
        let current = records.productVersions.filter { !superseded.contains($0.productVersionID) }
        return FoodSpeechVocabulary.make(namesAndBrands: current.flatMap { [$0.name.value] + ($0.brand.map { [$0.value] } ?? []) })
    }

    func intakeProjection(for date: Date, calendar: Calendar = .current) throws -> FoodIntakeProjection {
        try FoodIntakeProjection(records: store.archiveState().records,
            reportingDate: FoodReportingDay.key(for: date, calendar: calendar))
    }

    /// Rows whose current saved version is a labelled estimate. An unreadable entry is not labelled.
    func estimateLogItemIDs(in rows: [FoodIntakeLogRow]) -> Set<LogItemID> {
        Set(rows.compactMap { row in
            guard let stored = try? store.foodConfirmation(logItemID: row.logItemID),
                  (try? confirmations.isEstimate(stored)) == true else { return nil }
            return row.logItemID
        })
    }

    /// Food Log orchestration (#197). Built with the confirmation clock, so removal times and
    /// Confirm agree; the adapter below only forwards.
    var foodLogService: FoodLogReadingService {
        FoodLogReadingService(ledger: ledger, archive: store, confirmationReader: store,
            history: ArchiveFoodLogHistoryReader(archive: store), confirmations: confirmations,
            clock: confirmationClock, ids: ids)
    }

    var foodLogStore: any FoodLogStore { FoodLogStoreAdapter(service: foodLogService) }

    /// The Health report's Food and water reader (#214): the same Food Log read side, one
    /// reporting date at a time. No new store query and no range API.
    var foodLogPeriodReader: any FoodLogPeriodReading { FoodLogPeriodReader(service: foodLogService) }

    /// The one banner shown after Log closes Confirm (owner decision, 15 October 2026). Its Undo
    /// removes through the Food Log port, with the Food Log's fixed removal reason.
    private(set) lazy var loggedBanner = FoodLoggedBannerModel(store: foodLogStore)

    /// The label text screen's model (#93): reads on device through the application reader and
    /// builds Confirm's pasted-label source through the application builder. Its Developer tools
    /// lines live only while the screen is open.
    func pastedLabelTextModel(locale: Locale = .current) -> PastedLabelTextViewModel {
        let reader = pastedLabelReader, builder = pastedLabelConfirmation, diagnostics = searchDiagnostics
        let identifier = locale.identifier.isEmpty ? "und" : locale.identifier
        return PastedLabelTextViewModel(read: { reader.read($0) }, makeConfirm: { review, details in
            try PastedLabelSourceModel(review: review, details: details, builder: builder, locale: LedgerText(identifier))
        }, choose: { arrangement, request in
            // Reader v3 8.4.8: the choice is stamped by the confirmation clock.
            try builder.choose(arrangement, in: request)
        }, recordDiagnostics: { diagnostics.recordPastedLabel($0) })
    }

    /// Confirm for a pasted label: the same Confirm, Log and banner as every single-food route,
    /// with the editable source section. Each correction replaces Confirm's source input.
    func pastedLabelConfirmation(_ model: FoodConfirmationViewModel, source: PastedLabelSourceModel,
                                 editLabelText: @escaping () -> Void, leave: @escaping () -> Void) -> FoodConfirmationView {
        source.onInputChange = { [weak model] input in model?.replaceSourceInput(input) }
        return FoodConfirmationView(model: model, pastedLabel: source, editLabelText: editLabelText,
                                    logged: { [banner = loggedBanner] in banner.show($0) }, leave: leave)
    }

    /// Confirm for a new single food: Log saves, leaves through `leave` (the exit Done uses) and
    /// shows the banner on the destination. List import and Edit build Confirm without it.
    func singleFoodConfirmation(_ model: FoodConfirmationViewModel, leave: @escaping () -> Void) -> FoodConfirmationView {
        FoodConfirmationView(model: model, logged: { [banner = loggedBanner] in banner.show($0) }, leave: leave)
    }

    func foodLogModel() -> FoodLogViewModel {
        let clock = confirmationClock
        return FoodLogViewModel(store: foodLogStore, now: { clock.now() }, calendar: confirmationCalendar)
    }

    func savedEntryModel(_ logItemID: LogItemID) -> SavedFoodEntryViewModel {
        SavedFoodEntryViewModel(logItemID: logItemID, store: foodLogStore) { [weak self] in
            try self?.model(reopening: logItemID)
        }
    }

    func recentIntakeDays(before date: Date, calendar: Calendar = .current) throws -> [FoodIntakeDayPreview] {
        FoodIntakeDayPreview.pastWeek(records: try store.archiveState().records, now: date, calendar: calendar)
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

/// Maps `FoodLogReadingService.day(reportingDate:)` to the Health report's plain day facts
/// (docs/health-food-and-water-v1.md, section 6). Plain water is `PlainWaterDayTotal` (plain water
/// entries only, never water in foods). Energy is the day's `energyConsumed` total under
/// `food-intake-summary-v3` over its food entries: plain water entries are identified by the saved
/// entry's `isPlainWater` (the existing saved-entry read) and do not make a logged food day
/// (contract v1.1). They contribute exactly 0 kcal, so the known energy is unchanged; a plain water
/// entry that cannot be scaled is taken out of the incomplete count. Competing current versions
/// throw, so the section reports a read failure.
struct FoodLogPeriodReader: FoodLogPeriodReading {
    let service: FoodLogReadingService

    func dayFacts(for reportingDates: [String]) async throws -> [FoodLogDayFacts] {
        try reportingDates.map { date in
            try Self.facts(try service.day(reportingDate: date)) { id in
                try service.savedEntry(id)?.isPlainWater == true
            }
        }
    }

    static func facts(_ content: FoodLogDayContent, isPlainWater: (LogItemID) throws -> Bool) rethrows -> FoodLogDayFacts {
        let water = try content.entries.filter { try isPlainWater($0.logItemID) }
        let foodEntryCount = content.entries.count - water.count
        let energy = content.totals?.first { $0.key == .energyConsumed }
        let unscaledWater = water.filter { $0.energyKcal == nil }.count
        return FoodLogDayFacts(
            reportingDate: content.reportingDate,
            entryCount: content.entries.count,
            foodEntryCount: foodEntryCount,
            energy: foodEntryCount == 0 ? nil : FoodLogDayFacts.Total(
                knownAmount: energy?.knownAmount,
                incompleteContributions: energy.map { max($0.incompleteContributions - unscaledWater, 0) } ?? foodEntryCount,
                includesEstimates: energy?.includesEstimates ?? false
            ),
            plainWater: content.plainWater.map {
                FoodLogDayFacts.Total(knownAmount: $0.knownAmount, incompleteContributions: $0.incompleteContributions,
                                      includesEstimates: $0.includesEstimates)
            }
        )
    }
}

/// Forwards the Food Log port to the application service. Loading is synchronous and bounded
/// by one local archive read; the port is async so it can move off the main actor later.
struct FoodLogStoreAdapter: FoodLogStore {
    let service: FoodLogReadingService
    func day(_ reportingDate: String) async throws -> FoodLogDayContent { try service.day(reportingDate: reportingDate) }
    func savedEntry(_ id: LogItemID) async throws -> SavedFoodEntryDetail? { try service.savedEntry(id) }
    func remove(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome { service.remove(id, expected: expected) }
    func restore(_ id: LogItemID, expected: LogItemVersionID) async -> FoodLogChangeOutcome { service.restore(id, expected: expected) }
}

struct FoodListImportFlowView: View {
    @StateObject private var model: FoodListImportViewModel
    private let root: FoodLedgerCompositionRoot
    @State private var showsDictation = false
    @State private var vocabulary: [String] = []
    @State private var vocabularyUnavailable = false

    init?(root: FoodLedgerCompositionRoot) {
        guard let model = try? root.foodListModel() else { return nil }
        self.root = root
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        FoodListImportView(model: model)
            .toolbar {
                if model.rows.isEmpty {
                    Button("Dictate") {
                        do { vocabulary = try root.foodSpeechVocabulary(); vocabularyUnavailable = false }
                        catch { vocabulary = FoodSpeechVocabulary.make(namesAndBrands: []); vocabularyUnavailable = true }
                        showsDictation = true
                    }
                }
            }
            .sheet(isPresented: $showsDictation) {
                FoodVoiceInputView(vocabulary: vocabulary, vocabularyUnavailable: vocabularyUnavailable) { text in
                    model.appendReviewedSpeech(text)
                }
            }
    }
}

struct GenericFoodSearchFlowView: View {
    private let finish: FoodEntryFinish?
    /// "Create a favourite from Food search": Confirm opens with Save as favourite on (#198).
    private let savesFavourite: Bool
    private let root: FoodLedgerCompositionRoot
    private let searchesOnAppear: Bool
    private let offersBarcode: Bool
    @StateObject private var searchModel: GenericFoodSearchViewModel
    @State private var confirmationModel: FoodConfirmationViewModel?
    @State private var showsConfirmation = false
    @State private var showsWebReview = false
    @State private var showsBarcode = false
    @State private var searchedOnAppear = false

    /// `initialQuery` is searched once on appear only when the user submitted it on Add food
    /// (`searchesOnAppear`); a restored route starts empty and never searches by itself.
    init?(root: FoodLedgerCompositionRoot, additionalEvidence: [CaptureEvidence] = [], initialQuery: String = "",
          searchesOnAppear: Bool = false, offersBarcode: Bool = true, finish: FoodEntryFinish? = nil, savesFavourite: Bool = false) {
        guard let model = try? root.genericFoodSearchModel(additionalEvidence: additionalEvidence) else { return nil }
        self.root = root
        self.finish = finish
        self.savesFavourite = savesFavourite
        self.searchesOnAppear = Self.searchesOnAppear(initialQuery: initialQuery, requested: searchesOnAppear)
        self.offersBarcode = offersBarcode && additionalEvidence.isEmpty
        model.query = initialQuery
        _searchModel = StateObject(wrappedValue: model)
    }

    /// Only a query the user just submitted on Add food is searched on appear. A restored or
    /// otherwise opened Search results screen never starts a request by itself.
    static func searchesOnAppear(initialQuery: String, requested: Bool) -> Bool {
        requested && !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GenericFoodSearchView(model: searchModel, preferences: root.userDefaults,
                              reviewWebNutrition: { showsWebReview = true },
                              scanBarcode: offersBarcode ? { showsBarcode = true } : nil,
                              recordDiagnostics: { [diagnostics = root.searchDiagnostics] in diagnostics.recordSearch($0) }) { input in
            // Snapshot selection and amount once; navigation renders reuse this model.
            confirmationModel = root.model(for: input, queryQuantity: searchModel.effectiveAmount, searchInterpretation: searchModel.interpretation,
                                           prefillSourceQuantity: false, savesFavourite: savesFavourite, entryDay: finish?.entryDay)
            showsConfirmation = true
        }
        .onAppear {
            guard searchesOnAppear, !searchedOnAppear else { return }
            searchedOnAppear = true
            searchModel.search()
        }
        .navigationDestination(isPresented: $showsWebReview) {
            if let flow = OpenRouterFoodReviewFlowView(root: root, initialQuery: searchModel.query, finish: finish, savesFavourite: savesFavourite) { flow }
        }
        .navigationDestination(isPresented: $showsBarcode) { BarcodeFoodFlowView(root: root, finish: finish, savesFavourite: savesFavourite) }
        .navigationDestination(isPresented: $showsConfirmation) {
            if let confirmationModel {
                root.singleFoodConfirmation(confirmationModel) {
                    if !FoodEntryFinish.complete(finish, saved: confirmationModel.savedResult) {
                        showsConfirmation = false
                    }
                }
            }
        }
        .foodLoggedBannerScreen(root.loggedBanner)
    }
}

/// Add food (#196): one field, the other entry routes and recent foods. Every route ends on Confirm.
struct AddFoodFlowView: View {
    private let finish: FoodEntryFinish?
    private let root: FoodLedgerCompositionRoot
    @State private var recents: [FoodRecentRelogItem] = []
    @State private var submittedQuery: String?
    @State private var showsSearch = false
    @State private var showsBarcode = false
    @State private var showsList = false
    @State private var showsFavourites = false
    @State private var showsLabel = false
    @State private var confirmationModel: FoodConfirmationViewModel?
    @State private var showsConfirmation = false
    @State private var relogFailed = false
    @State private var now = Date()
    /// Nil when favourites cannot be read (shown as a failure, never as empty).
    @State private var quickAddItems: [QuickAddItem]? = []
    @State private var quickAddRequest: QuickAddItem?
    @StateObject private var favouriteSaving: FavouriteSaveModel

    init(root: FoodLedgerCompositionRoot, finish: FoodEntryFinish? = nil) {
        self.root = root; self.finish = finish
        _favouriteSaving = StateObject(wrappedValue: root.favouriteSaveModel())
    }

    var body: some View {
        AddFoodView(recents: recents, now: now, calendar: root.confirmationDayCalendar,
                    search: { submittedQuery = $0; showsSearch = true },
                    scanBarcode: { showsBarcode = true },
                    pasteOrDictate: { showsList = true },
                    pasteLabel: { showsLabel = true },
                    favourites: { showsFavourites = true },
                    favouriteItems: quickAddItems,
                    quickAdd: { quickAddRequest = $0 },
                    favouriteSaving: favouriteSaving,
                    listImportNote: FoodLogText.listImportNote(entryDay: finish?.entryDay),
                    relog: { recent in
                        if let model = try? root.model(relogging: recent.item.logItemID, entryDay: finish?.entryDay) {
                            confirmationModel = model; showsConfirmation = true
                        } else { relogFailed = true }
                    })
        .onAppear { now = root.confirmationNow; recents = root.recentFoods(); quickAddItems = root.quickAddItems() }
        .onChange(of: recents.compactMap(\.logItemVersionID), initial: true) { _, ids in favouriteSaving.refresh(ids) }
        .quickAdd(root: root, request: $quickAddRequest, finish: finish) { quickAddItems = root.quickAddItems() }
        .alert("This food could not be opened", isPresented: $relogFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Its saved source could not be verified. Search for it instead. Nothing was saved.") }
        .navigationDestination(isPresented: $showsSearch) {
            if let flow = GenericFoodSearchFlowView(root: root, initialQuery: submittedQuery ?? "", searchesOnAppear: true, finish: finish) {
                flow.id(submittedQuery)
            } else { ContentUnavailableView("Food search unavailable", systemImage: "exclamationmark.triangle") }
        }
        .navigationDestination(isPresented: $showsBarcode) { BarcodeFoodFlowView(root: root, finish: finish) }
        .navigationDestination(isPresented: $showsList) {
            if let flow = FoodListImportFlowView(root: root) { flow }
            else { ContentUnavailableView("Food list unavailable", systemImage: "exclamationmark.triangle") }
        }
        .navigationDestination(isPresented: $showsFavourites) { favouritesFlow }
        .navigationDestination(isPresented: $showsLabel) {
            PastedLabelFlowView(root: root, finish: finish) {
                showsLabel = false; now = root.confirmationNow; recents = root.recentFoods()
            }
        }
        .navigationDestination(isPresented: $showsConfirmation) {
            if let confirmationModel {
                root.singleFoodConfirmation(confirmationModel) {
                    if !FoodEntryFinish.complete(finish, saved: confirmationModel.savedResult) {
                        showsConfirmation = false; now = root.confirmationNow; recents = root.recentFoods()
                    }
                }
            }
        }
    }

    /// Favourites opened from Add food carries Add food's finish, so a favourite created there
    /// starts When on the Food Log day and Done finishes the Add food journey.
    var favouritesFlow: FavouritesFlowView { FavouritesFlowView(root: root, finish: finish) }
}

/// Paste nutrition label (#93): Label text, then the shared Confirm with one Log action. A hard
/// decline stays on the label text screen with the text kept. Leaving, or logging, clears the
/// text and the Developer tools lines; nothing is kept outside a logged entry's manifest.
struct PastedLabelFlowView: View {
    private let finish: FoodEntryFinish?
    private let root: FoodLedgerCompositionRoot
    /// Pops the flow after Log or Leave without saving when Add food carries no finish.
    private let close: () -> Void
    @StateObject private var model: PastedLabelTextViewModel
    @State private var confirmationModel: FoodConfirmationViewModel?
    @State private var sourceModel: PastedLabelSourceModel?
    @State private var showsConfirmation = false
    @State private var showsSearch = false
    @State private var showsBarcode = false

    init(root: FoodLedgerCompositionRoot, finish: FoodEntryFinish? = nil, close: @escaping () -> Void) {
        self.root = root; self.finish = finish; self.close = close
        _model = StateObject(wrappedValue: root.pastedLabelTextModel())
    }

    var body: some View {
        PastedLabelTextView(model: model, openConfirm: open,
                            search: { model.leaveForAnotherRoute(); showsSearch = true },
                            scanBarcode: { model.leaveForAnotherRoute(); showsBarcode = true },
                            leave: close)
            .navigationDestination(isPresented: $showsConfirmation) {
                if let confirmationModel, let sourceModel {
                    root.pastedLabelConfirmation(confirmationModel, source: sourceModel,
                                                 editLabelText: { showsConfirmation = false }) {
                        guard let saved = confirmationModel.savedResult else { showsConfirmation = false; return }
                        model.dismissed()
                        if !FoodEntryFinish.complete(finish, saved: saved) { close() }
                    }
                    // Torn down while still pushed (Add food swiped away, or a finish that
                    // replaced the path): the flow has ended, so nothing is kept.
                    .onDisappear { model.confirmDisappeared(stillPushed: showsConfirmation) }
                    // Reader v3 8.4.9: Change on Confirm's basis line. Dismissing keeps the
                    // choice on Confirm; "I'm not sure" drops Confirm and keeps the text.
                    .sheet(item: Binding(get: { model.basisSheet.flatMap { $0.fromChange ? $0 : nil } },
                                         set: { if $0 == nil { model.basisSheetDismissed() } })) { _ in
                        PastedLabelBasisSheetView(model: model, open: open, closeConfirm: { showsConfirmation = false })
                    }
                }
            }
            .navigationDestination(isPresented: $showsSearch) {
                if let flow = GenericFoodSearchFlowView(root: root, finish: finish) { flow }
                else { ContentUnavailableView("Food search unavailable", systemImage: "exclamationmark.triangle") }
            }
            .navigationDestination(isPresented: $showsBarcode) { BarcodeFoodFlowView(root: root, finish: finish) }
            .onDisappear {
                // Covered by Confirm, search or barcode: still open. Otherwise it closed.
                model.labelScreenDisappeared(covered: showsConfirmation || showsSearch || showsBarcode)
            }
    }

    /// Opens Confirm for a reading. "Back to Confirm" reuses the Confirm it left, so the amount
    /// and time stay; a new reading starts a new Confirm.
    private func open(_ source: PastedLabelSourceModel) {
        guard let input = source.input else { return }
        if source === sourceModel, let existing = confirmationModel, existing.savedResult == nil {
            existing.replaceSourceInput(input)
        } else {
            confirmationModel = root.model(for: input, prefillSourceQuantity: false, entryDay: finish?.entryDay)
        }
        sourceModel = source
        showsConfirmation = true
    }
}

struct OpenRouterFoodReviewFlowView: View {
    private let finish: FoodEntryFinish?
    private let savesFavourite: Bool
    private let root: FoodLedgerCompositionRoot
    @StateObject private var credentials: FoodWebDiscoveryViewModel
    @StateObject private var reviewModel: GenericFoodProposalReviewViewModel
    @State private var confirmationModel: FoodConfirmationViewModel?
    @State private var showsConfirmation = false
    init?(root: FoodLedgerCompositionRoot, initialQuery: String, finish: FoodEntryFinish? = nil, savesFavourite: Bool = false) {
        guard let model = try? root.proposalReviewModel(initialQuery: initialQuery) else { return nil }
        self.root = root
        self.finish = finish
        self.savesFavourite = savesFavourite
        _credentials = StateObject(wrappedValue: root.webDiscovery)
        _reviewModel = StateObject(wrappedValue: model)
    }
    var body: some View {
        GenericFoodProposalReviewView(model: reviewModel, credentials: credentials,
                                      recordDiagnostics: { [diagnostics = root.searchDiagnostics] in diagnostics.recordWebLookup($0) }) { input in
            confirmationModel = root.model(for: input, prefillSourceQuantity: false, savesFavourite: savesFavourite, entryDay: finish?.entryDay)
            showsConfirmation = true
        }
        .navigationDestination(isPresented: $showsConfirmation) {
            if let confirmationModel {
                root.singleFoodConfirmation(confirmationModel) {
                    if !FoodEntryFinish.complete(finish, saved: confirmationModel.savedResult) {
                        showsConfirmation = false
                    }
                }
            }
        }
        // The market is set in Settings. Re-read it whenever Web lookup appears, so a change made
        // there invalidates any open result (the view model cancels on a changed market).
        .onAppear { reviewModel.market = root.foodMarket.market }
        .foodLoggedBannerScreen(root.loggedBanner)
    }
}

struct LocalInventoryFlowView: View {
    private let root: FoodLedgerCompositionRoot
    @StateObject private var model: LocalInventoryViewModel
    @State private var showsFilePicker = false
    @State private var showsSearch = false
    @State private var query = ""
    @State private var evidence: [CaptureEvidence] = []

    init?(root: FoodLedgerCompositionRoot) {
        guard let model = try? root.inventoryModel() else { return nil }
        self.root = root
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        LocalInventoryView(model: model, chooseFile: { showsFilePicker = true }) { product in
            do {
                evidence = [try root.inventoryEvidence(product)]
                query = product.name
                showsSearch = true
            } catch { model.report(error) }
        }
        .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.plainText, .pdf]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                guard let size = values.fileSize, size > 0, size <= 5_000_000 else { throw InventoryDocumentError.tooLarge }
                let bytes = try Data(contentsOf: url)
                let isPDF = values.contentType?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf"
                let document = try LocalInventoryDocumentExtractor().extract(bytes, format: isPDF ? .pdf : .text)
                model.importDocument(document, name: url.lastPathComponent)
            } catch let error as CocoaError where error.code == .userCancelled {
                // Cancelling file selection makes no change.
            } catch { model.report(error) }
        }
        .navigationDestination(isPresented: $showsSearch) {
            if let flow = GenericFoodSearchFlowView(root: root, additionalEvidence: evidence, initialQuery: query) {
                flow.id(evidence.map(\.evidenceID))
            }
        }
    }
}

struct InventoryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw InventoryStoreError.corruptStore }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CommonFoodsFlowView: View {
    private let root: FoodLedgerCompositionRoot
    @StateObject private var model: LocalInventoryViewModel
    @State private var showsList = false
    init?(root: FoodLedgerCompositionRoot) {
        guard let model = try? root.inventoryModel() else { return nil }
        self.root = root; _model = StateObject(wrappedValue: model)
    }
    var body: some View {
        CommonFoodsView(model: model) { product in
            do {
                try root.foodListModel().addCommonFood(name: product.name, portion: product.usualPortion)
                showsList = true
            } catch { model.report(error) }
        }
        .navigationDestination(isPresented: $showsList) { if let view = FoodListImportFlowView(root: root) { view } }
    }
}

struct FoodReresolutionFlowView: View {
    @StateObject private var model: FoodReresolutionViewModel
    init?(root: FoodLedgerCompositionRoot) {
        guard let model = try? root.reresolutionModel() else { return nil }
        _model = StateObject(wrappedValue: model)
    }
    var body: some View { FoodReresolutionView(model: model) }
}

/// When the barcode route opens its scanner (#196 follow-up). The view drives every appearance
/// and scanner opening through this value, so tests replay the same sequence.
struct BarcodeFlowStart: Equatable {
    static let scanTitle = "Scan barcode"
    static let rescanTitle = "Scan again"
    private(set) var hasAppeared = false
    private(set) var hasOpenedScanner = false

    /// True only on the first appearance; returning from search or Confirm never reopens it.
    mutating func appear() -> Bool {
        defer { hasAppeared = true }
        return !hasAppeared
    }

    mutating func scannerOpened() { hasOpenedScanner = true }

    /// "Scan barcode" until a scanner has opened (an unsupported device never opens one).
    var buttonTitle: String { hasOpenedScanner ? Self.rescanTitle : Self.scanTitle }
}

struct BarcodeFoodFlowView: View {
    private let finish: FoodEntryFinish?
    private let savesFavourite: Bool
    private let root: FoodLedgerCompositionRoot
    @StateObject private var model: BarcodeCaptureViewModel
    @State private var offTask: Task<Void, Never>?
    @State private var offMessage: String?
    @State private var offIsLoading = false
    @State private var offGeneration = 0
    @State private var pendingOFFRoute: BarcodeFallbackRoute?
    @State private var showsOFFDisclosure = false
    @AppStorage("foodLedger.offBarcodeDisclosure.v1") private var hasSeenOFFDisclosure = false
    @State private var scanner: VisionKitBarcodeScanner?
    @State private var showsScanner = false
    @State private var start = BarcodeFlowStart()
    @State private var showsSearch = false
    @State private var showsConfirmation = false
    @State private var evidence: [CaptureEvidence] = []
    @State private var confirmationModel: FoodConfirmationViewModel?

    init(root: FoodLedgerCompositionRoot, finish: FoodEntryFinish? = nil, savesFavourite: Bool = false) {
        self.root = root
        self.finish = finish
        self.savesFavourite = savesFavourite
        _model = StateObject(wrappedValue: root.barcodeModel())
    }

    var body: some View {
        Form {
            Section("Food barcode") {
                Text("Checks your saved foods first. On a miss, you can optionally look up the barcode on Open Food Facts or search generic foods.")
                Button(start.buttonTitle, action: startScan)
                    .disabled(showsScanner)
            }
            resultSection
        }
        .navigationTitle("Scan food barcode")
        // Opening the route starts the scanner (#196 follow-up): no extra tap. Camera permission
        // is still explained by the system prompt, and the text above stays for a rescan.
        .task {
            if start.appear() { startScan() }
        }
        .sheet(isPresented: $showsScanner, onDismiss: stopScanner) {
            if let scanner {
                NavigationStack {
                    VisionKitBarcodeScannerView(scanner: scanner)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Scan barcode")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showsScanner = false; stopScanner() }
                            }
                        }
                        .task { await model.capture(using: scanner) }
                        .onDisappear { scanner.cancel(); model.cancel() }
                }
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase != .capturing { showsScanner = false }
        }
        .onDisappear { stopScanner(); cancelOFF() }
        .alert("Look up this barcode?", isPresented: $showsOFFDisclosure) {
            Button("Cancel", role: .cancel) { pendingOFFRoute = nil }
            Button("Send barcode and look up") {
                hasSeenOFFDisclosure = true
                if let route = pendingOFFRoute { startOFF(route) }
                pendingOFFRoute = nil
            }
        } message: {
            Text("The barcode will be sent to Open Food Facts. Your food history, quantities, photos and health data stay on this device. Returned community data needs your review. Selected source records retain attribution and licence notices in local records and exports.")
        }
        .navigationDestination(isPresented: $showsSearch) {
            if let view = GenericFoodSearchFlowView(root: root, additionalEvidence: evidence, finish: finish, savesFavourite: savesFavourite) {
                view.id(evidence.map(\.evidenceID))
            }
        }
        .navigationDestination(isPresented: $showsConfirmation) {
            if let confirmationModel {
                root.singleFoodConfirmation(confirmationModel) {
                    if !FoodEntryFinish.complete(finish, saved: confirmationModel.savedResult) {
                        showsConfirmation = false
                    }
                }
            }
        }
        .foodLoggedBannerScreen(root.loggedBanner)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch model.phase {
        case .idle, .capturing:
            EmptyView()
        case .failed:
            Section("Scan could not finish") {
                Text("Try scanning again or use food search. Nothing was saved.")
                Button("Use generic search") { openSearch(evidence: []) }
            }
        case let .result(.permissionGuidance(guidance)):
            Section {
                BarcodePermissionGuidanceView(guidance: guidance) { openSearch(evidence: []) }
            }
        case let .result(.fallback(route)):
            Section {
                BarcodeFallbackGuidanceView(route: route) { openSearch(evidence: [$0]) }
                if case .gtin = route.identity {
                    Text("Optional online lookup sends this barcode to Open Food Facts.").font(.caption)
                    if offIsLoading {
                        ProgressView("Looking up product")
                        Button("Cancel lookup") { cancelOFF() }
                    } else {
                        Button("Look up on Open Food Facts") {
                            if hasSeenOFFDisclosure { startOFF(route) }
                            else { pendingOFFRoute = route; showsOFFDisclosure = true }
                        }
                    }
                    if let offMessage { Text(offMessage).font(.caption) }
                    Link("Open Food Facts · data licence", destination: URL(string: "https://openfoodfacts.github.io/openfoodfacts-server/api/tutorials/license-be-on-the-legal-side/")!)
                        .font(.caption)
                }
            }
        case let .result(.confirmation(route)):
            Section("Saved food found") {
                Text(route.confirmation.candidates[0].name.value)
                Button("Review and confirm") {
                    confirmationModel = root.model(for: route.confirmation, savesFavourite: savesFavourite, entryDay: finish?.entryDay)
                    showsConfirmation = true
                }
            }
        }
    }

    private func startScan() {
        cancelOFF()
        offMessage = nil
        guard let next = VisionKitBarcodeScanner.makeIfSupported() else {
            model.showUnavailable()
            return
        }
        scanner = next
        start.scannerOpened()
        showsScanner = true
    }

    private func cancelOFF() {
        offGeneration += 1
        offTask?.cancel(); offTask = nil; offIsLoading = false
    }

    private func startOFF(_ route: BarcodeFallbackRoute) {
        cancelOFF()
        let generation = offGeneration
        offMessage = nil; offIsLoading = true
        offTask = Task { @MainActor in
            defer { if generation == offGeneration { offIsLoading = false; offTask = nil } }
            do {
                let outcome = try await root.lookupOFF(route)
                guard !Task.isCancelled, generation == offGeneration else { return }
                switch outcome {
                case let .candidate(confirmation):
                    confirmationModel = root.model(for: confirmation, savesFavourite: savesFavourite, entryDay: finish?.entryDay)
                    showsConfirmation = true
                case .notFound: offMessage = "No product found. Your barcode is retained; you can use generic search."
                case .insufficientData: offMessage = "The product has insufficient nutrition or an ambiguous basis. Use generic search; nothing was selected or saved."
                }
            } catch is CancellationError { }
            catch OFFLookupError.rateLimited {
                if generation == offGeneration { offMessage = "Lookup is rate-limited. Wait before trying again, or use generic search." }
            } catch {
                if !Task.isCancelled, generation == offGeneration { offMessage = "Open Food Facts is unavailable. Your barcode is retained; use generic search or try again later." }
            }
        }
    }

    private func openSearch(evidence: [CaptureEvidence]) {
        self.evidence = evidence
        showsSearch = true
    }

    private func stopScanner() {
        scanner?.cancel()
        scanner = nil
        model.cancel()
    }
}

/// Favourites (#198). Creating a favourite opens Food search, Barcode or Web lookup with "Save as
/// favourite" preset; after Log the journey returns here, or, when Favourites was opened from Add
/// food, finishes the Add food journey with Add food's day like its other routes.
struct FavouritesFlowView: View {
    private let root: FoodLedgerCompositionRoot
    /// Add food's finish (with its Food Log day), or nil when opened from Home or Settings.
    private let finish: FoodEntryFinish?
    @StateObject private var model: FavouritesViewModel
    @State private var showsSearch = false
    @State private var showsBarcode = false
    @State private var showsWebLookup = false
    @State private var showsLogged = false

    init(root: FoodLedgerCompositionRoot, finish: FoodEntryFinish? = nil) {
        self.root = root
        self.finish = finish
        _model = StateObject(wrappedValue: root.favouritesModel())
    }

    var body: some View {
        FavouritesView(model: model, createFromLogged: { showsLogged = true }, createFromSearch: { showsSearch = true },
                       createFromBarcode: { showsBarcode = true }, createFromWebLookup: { showsWebLookup = true })
        .navigationDestination(isPresented: $showsLogged) { FavouriteFromLoggedFlowView(root: root) }
        .onChange(of: showsLogged) { _, shown in if !shown { model.reload() } }
        .navigationDestination(isPresented: $showsSearch) {
            if let flow = GenericFoodSearchFlowView(root: root, finish: createFinish, savesFavourite: true) { flow }
            else { ContentUnavailableView("Food search unavailable", systemImage: "exclamationmark.triangle") }
        }
        .navigationDestination(isPresented: $showsBarcode) { BarcodeFoodFlowView(root: root, finish: createFinish, savesFavourite: true) }
        .navigationDestination(isPresented: $showsWebLookup) {
            if let flow = OpenRouterFoodReviewFlowView(root: root, initialQuery: "", finish: createFinish, savesFavourite: true) { flow }
            else { ContentUnavailableView("Web lookup unavailable", systemImage: "exclamationmark.triangle") }
        }
        .foodLoggedBannerScreen(root.loggedBanner)
    }

    /// The finish the create routes carry: Add food's when opened from there, otherwise one that
    /// returns here and logs for now.
    var createFinish: FoodEntryFinish { finish ?? returnHere }

    /// After Log (and the favourite) the create journey returns to Favourites.
    private var returnHere: FoodEntryFinish {
        FoodEntryFinish { _ in
            showsSearch = false; showsBarcode = false; showsWebLookup = false
            model.reload()
        }
    }
}

/// "From what you’ve logged" (owner decision A): recent foods with Save as favourite. Reading the
/// list writes nothing; each save pins that food's current logged version.
struct FavouriteFromLoggedFlowView: View {
    private let root: FoodLedgerCompositionRoot
    @StateObject private var saving: FavouriteSaveModel
    @State private var content: FavouriteFromLoggedView.Content = .loading

    init(root: FoodLedgerCompositionRoot) {
        self.root = root
        _saving = StateObject(wrappedValue: root.favouriteSaveModel())
    }

    var body: some View {
        FavouriteFromLoggedView(content: content, now: root.confirmationNow, calendar: root.confirmationDayCalendar,
                                model: saving, retry: load)
            .onAppear(perform: load)
    }

    private func load() {
        do {
            let items = try root.loggedFoods()
            saving.refresh(items.compactMap(\.logItemVersionID))
            content = .items(items)
        } catch {
            content = .failed
        }
    }
}

/// Presents quick add for a requested item (#198): the one-step sheet when `QuickAddPolicy` allows
/// it, otherwise the full Confirm. Requesting writes nothing; only Log saves.
struct QuickAddPresenter: ViewModifier {
    let root: FoodLedgerCompositionRoot
    @Binding var request: QuickAddItem?
    let finish: FoodEntryFinish?
    let logged: () -> Void
    @State private var sheetModel: QuickAddSheetModel?
    @State private var confirmModel: FoodConfirmationViewModel?
    @State private var showsConfirm = false
    @State private var pendingEdit: FoodConfirmationState?
    @State private var unverifiable = false

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, item in
                guard let item else { return }
                request = nil
                open(item)
            }
            .sheet(item: $sheetModel, onDismiss: {
                if let state = pendingEdit { pendingEdit = nil; openConfirm(state) }
            }) { model in
                NavigationStack {
                    QuickAddSheet(model: model, edit: {
                        guard let state = model.editState else { return }
                        pendingEdit = state; sheetModel = nil
                    }, close: { sheetModel = nil })
                }
                .presentationDetents([.medium, .large])
            }
            .navigationDestination(isPresented: $showsConfirm) {
                if let confirmModel {
                    root.singleFoodConfirmation(confirmModel) {
                        if !FoodEntryFinish.complete(finish, saved: confirmModel.savedResult) {
                            showsConfirm = false
                            if confirmModel.savedResult != nil { logged() }
                        }
                    }
                }
            }
            .alert(QuickAddText.unverifiable, isPresented: $unverifiable) {
                Button("OK", role: .cancel) {}
            } message: { Text("Its saved source could not be verified. Remove it from Favourites and create it again from a search. Nothing was saved.") }
    }

    private func open(_ item: QuickAddItem) {
        guard let preparation = try? root.quickAddPreparation(item) else { unverifiable = true; return }
        switch preparation.eligibility {
        case .sheet:
            let model = root.quickAddSheetModel(preparation, entryDay: finish?.entryDay)
            model.onLogged = QuickAddPresenter.completion(dismiss: { sheetModel = nil }, finish: finish, logged: logged,
                                                          notice: { [weak model] in model?.loggedNotice },
                                                          show: { [banner = root.loggedBanner] in banner.show($0) })
            sheetModel = model
        case .confirm: openConfirm(preparation.state, entryDay: finish?.entryDay)
        }
    }

    /// After the one successful Log: dismiss the sheet, then end the Add food journey through its
    /// single post-save exit or, elsewhere, reload the host; then show the banner there.
    static func completion(dismiss: @escaping () -> Void, finish: FoodEntryFinish?,
                           logged: @escaping () -> Void,
                           notice: @escaping () -> FoodLoggedNotice? = { nil },
                           show: ((FoodLoggedNotice) -> Void)? = nil) -> (StoredFoodConfirmation) -> Void {
        { saved in
            dismiss()
            if !FoodEntryFinish.complete(finish, saved: saved) { logged() }
            if let show, let notice = notice() { show(notice) }
        }
    }

    private func openConfirm(_ state: FoodConfirmationState, entryDay: String? = nil) {
        confirmModel = root.model(quickAdd: state, entryDay: entryDay)
        showsConfirm = true
    }
}

extension View {
    func quickAdd(root: FoodLedgerCompositionRoot, request: Binding<QuickAddItem?>, finish: FoodEntryFinish? = nil,
                  logged: @escaping () -> Void) -> some View {
        modifier(QuickAddPresenter(root: root, request: request, finish: finish, logged: logged))
    }
}
