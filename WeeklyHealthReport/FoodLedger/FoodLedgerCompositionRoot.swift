import FoodLedgerApplication
import FoodLedgerDomain
import FoodGenericSearch
import FoodLedgerGRDB
import FoodLedgerPresentation
import FoodBarcodeCapture
import FoodInventoryImport
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FoodLedgerCompositionRoot {
    private let store: FoodLedgerGRDBStore
    private let confirmations: FoodConfirmationService
    private let ledger: FoodLedgerService
    private let genericFoodSearch: any GenericFoodSearching
    private let offLookup: OpenFoodFactsLookup
    private let ids: RandomLedgerIDGenerator
    private var activeFoodList: FoodListImportViewModel?
    private let inventoryURL: URL
    private let draftURL: URL
    private var activeInventory: LocalInventoryViewModel?
    private var inventoryService: LocalInventoryService?
    private var activeReresolution: FoodReresolutionViewModel?

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
        inventoryURL = applicationSupport.appendingPathComponent("WeeklyHealthReport/Inventory/v1/inventory.sqlite")
        draftURL = root.appendingPathComponent("food-list-draft.sqlite")
        store = try FoodLedgerGRDBStore(
            databaseURL: root.appendingPathComponent("food-ledger.sqlite"),
            attachmentsRoot: root.appendingPathComponent("Attachments", isDirectory: true)
        )
        ids = RandomLedgerIDGenerator()
        offLookup = OpenFoodFactsLookup(transport: OFFHTTPSProductTransport(userAgent: "WeeklyHealthReport/0.1.1 (proxy@sertan.com)"))
        let clock = SystemLedgerClock()
        ledger = FoodLedgerService(
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
        genericFoodSearch = try CompositeGenericFoodSearch(sources: [
            CoFIDGenericFoodSearch(library: PersonalLibraryGenericFoodSearch(reader: store), ids: ids),
            USDAGenericFoodSearch(ids: ids)
        ], ids: ids)
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

    func genericFoodSearchModel(
        locale: Locale = .current, additionalEvidence: [CaptureEvidence] = []
    ) throws -> GenericFoodSearchViewModel {
        GenericFoodSearchViewModel(
            searcher: genericFoodSearch,
            locale: try LedgerText(locale.identifier),
            additionalEvidence: additionalEvidence
        )
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
            service: FoodListImportService(searcher: genericFoodSearch),
            locale: try LedgerText(locale.identifier), ids: ids,
            checkpointStore: try FoodListCheckpointGRDBStore(databaseURL: draftURL),
            recoveredLogItemID: { [ledger] operationID in
                try ledger.confirmedLogItemID(operationID: operationID, idempotencyKey: LedgerText("food-list:\(operationID.rawValue)"))
            }
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
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return try FoodIntakeProjection(records: store.archiveState().records, reportingDate: formatter.string(from: date))
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
    private let root: FoodLedgerCompositionRoot
    @StateObject private var searchModel: GenericFoodSearchViewModel
    @State private var confirmation: PopulatedFoodConfirmation?
    @State private var showsConfirmation = false

    init?(root: FoodLedgerCompositionRoot, additionalEvidence: [CaptureEvidence] = [], initialQuery: String = "") {
        guard let model = try? root.genericFoodSearchModel(additionalEvidence: additionalEvidence) else { return nil }
        self.root = root
        model.query = initialQuery
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
        .modifier(InventoryBackupControls(root: root, model: model))
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

private struct InventoryBackupControls: ViewModifier {
    let root: FoodLedgerCompositionRoot
    @ObservedObject var model: LocalInventoryViewModel
    @State private var showsExport = false
    @State private var showsImport = false
    @State private var backup = InventoryBackupDocument()

    func body(content: Content) -> some View {
        content
            .toolbar {
                Menu("Backup") {
                    Text("Includes original receipts and saved review history. Exported files are not encrypted.")
                    Button("Export inventory backup") {
                        do { backup = InventoryBackupDocument(data: try root.inventoryBackup()); showsExport = true }
                        catch { model.report(error) }
                    }
                    Button("Restore inventory backup") { showsImport = true }
                }.disabled(model.pendingCommand != nil)
            }
            .fileExporter(isPresented: $showsExport, document: backup, contentType: .json, defaultFilename: "inventory-backup") { result in
                if case let .failure(error) = result { model.report(error) }
            }
            .fileImporter(isPresented: $showsImport, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= InventoryBackupCodec.maximumBytes else { throw InventoryStoreError.corruptStore }
                    try root.restoreInventoryBackup(Data(contentsOf: url))
                } catch let error as CocoaError where error.code == .userCancelled { }
                catch { model.report(error) }
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
        .modifier(InventoryBackupControls(root: root, model: model))
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

struct BarcodeFoodFlowView: View {
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
    @State private var showsSearch = false
    @State private var showsConfirmation = false
    @State private var evidence: [CaptureEvidence] = []
    @State private var confirmationModel: FoodConfirmationViewModel?

    init(root: FoodLedgerCompositionRoot) {
        self.root = root
        _model = StateObject(wrappedValue: root.barcodeModel())
    }

    var body: some View {
        Form {
            Section("Food barcode") {
                Text("Checks your saved foods first. On a miss, you can optionally look up the barcode on Open Food Facts or search generic foods.")
                Button("Scan barcode") {
                    cancelOFF()
                    offMessage = nil
                    guard let next = VisionKitBarcodeScanner.makeIfSupported() else {
                        model.showUnavailable()
                        return
                    }
                    scanner = next
                    showsScanner = true
                }
                .disabled(showsScanner)
            }
            resultSection
        }
        .navigationTitle("Scan food barcode")
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
            if let view = GenericFoodSearchFlowView(root: root, additionalEvidence: evidence) {
                view.id(evidence.map(\.evidenceID))
            }
        }
        .navigationDestination(isPresented: $showsConfirmation) {
            if let confirmationModel {
                FoodConfirmationView(model: confirmationModel) { showsConfirmation = false }
            }
        }
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
                    confirmationModel = root.model(for: route.confirmation)
                    showsConfirmation = true
                }
            }
        }
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
                    confirmationModel = root.model(for: confirmation)
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
