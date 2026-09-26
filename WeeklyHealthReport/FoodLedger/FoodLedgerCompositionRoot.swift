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
    private let genericFoodSearch: CoFIDGenericFoodSearch
    private let ids: RandomLedgerIDGenerator
    private var activeFoodList: FoodListImportViewModel?
    private let inventoryURL: URL
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
        store = try FoodLedgerGRDBStore(
            databaseURL: root.appendingPathComponent("food-ledger.sqlite"),
            attachmentsRoot: root.appendingPathComponent("Attachments", isDirectory: true)
        )
        ids = RandomLedgerIDGenerator()
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

    func genericFoodSearchModel(
        locale: Locale = .current, additionalEvidence: [CaptureEvidence] = []
    ) throws -> GenericFoodSearchViewModel {
        GenericFoodSearchViewModel(
            searcher: genericFoodSearch,
            locale: try LedgerText(locale.identifier),
            additionalEvidence: additionalEvidence
        )
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
        let model = try LocalInventoryViewModel(service: service, ids: ids, clock: SystemLedgerClock())
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

    func foodListModel(locale: Locale = .current) throws -> FoodListImportViewModel {
        if let activeFoodList { return activeFoodList }
        let model = FoodListImportViewModel(
            service: FoodListImportService(searcher: genericFoodSearch),
            locale: try LedgerText(locale.identifier), ids: ids
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
                Text("Scan a barcode to look for a food you have already saved. If there is no exact match, choose a food through search.")
                Button("Scan barcode") {
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
        .onDisappear { stopScanner() }
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
