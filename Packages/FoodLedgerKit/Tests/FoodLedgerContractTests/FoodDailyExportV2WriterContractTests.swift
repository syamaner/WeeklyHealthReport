import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport
import XCTest

/// Food daily export contract v2 (#312), PR 3: the writer emits schema 2. Contract tests 1 to 6
/// (the code mapping, one entry per row of the closed table, the release rule, parity with the
/// summary, a missing conversion, a corrected entry), 9 (the two generated goldens this PR adds)
/// and the fail-closed cases the PR 3 gate asked for. Test 10 (the builder reproduces PR 2's
/// hand-built fixtures byte for byte) is `FoodDailyExportContractTests.testGoldenFilesAreByteStable`.
/// Every ledger here is synthetic.
final class FoodDailyExportV2WriterContractTests: XCTestCase {
    private typealias Method = FoodDailyExportAmountMethod
    private static let day = "2023-11-14"
    private static let london = TimeZone(identifier: "Europe/London")!
    private static let dataAsOf = Date(timeIntervalSince1970: 1_700_006_400)
    private static let exportedAt = Date(timeIntervalSince1970: 1_700_038_800.125)
    private static let app = FoodDailyExportAppContext(appVersion: "0.1.1", appBuild: "42")
    private static let guideRelease = CountPortionGuideCode.sourceReleaseID
    private static let milkRelease = "phe-npm-2018:sha256:0abf60c447ac94a075e4d2a8065061e64e8d2fd8278959b3fc284ee858510e1b"
    private static let boiledMedium = "count_portion_guide_v1:usda_sr_legacy_boiled_from_171287_88378"
    private static let typedMethod = "weighed on grandmother's brass scale"

    // MARK: Synthetic ledger

    private struct Conversion {
        var source: PositiveQuantity
        var method: String
        var release: String?
    }

    /// One log item: a product, its resolution and one log version per element of `versions`
    /// (the last one is the head). `storesConversion` false leaves a named conversion out of the
    /// snapshot, which no store allows (Q7).
    private struct Item {
        struct Version {
            var quantity: PositiveQuantity
            var declaration: EdibleWeightDeclaration?
            var conversion: Conversion?
            var storesConversion = true
            var plate = false
            var removed = false
        }
        var name: String
        var basis: ResolutionBasis = .per100Grams
        var versions: [Version]

        init(_ name: String, _ quantity: PositiveQuantity, basis: ResolutionBasis = .per100Grams,
             declaration: EdibleWeightDeclaration? = nil, conversion: Conversion? = nil, plate: Bool = false) {
            self.name = name; self.basis = basis
            versions = [Version(quantity: quantity, declaration: declaration, conversion: conversion, plate: plate)]
        }
    }

    private static func grams(_ value: Double) throws -> PositiveQuantity { try PositiveQuantity(value: value, unit: .grams) }
    private static func millilitres(_ value: Double) throws -> PositiveQuantity { try PositiveQuantity(value: value, unit: .millilitres) }
    private static func count(_ value: Double) throws -> PositiveQuantity { try PositiveQuantity(value: value, unit: .count) }

    private static func declared(_ basis: UserWeightBasis, _ total: Double, original: PositiveQuantity? = nil) throws -> EdibleWeightDeclaration {
        try EdibleWeightDeclaration(basis: basis, total: grams(total), originalInput: original)
    }

    /// Energy known (a manual declaration), everything else unknown, water included.
    private static func nutrients() throws -> NutrientSet {
        let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: try ExternalIdentifier("fixture"),
            sourceReleaseID: try ExternalIdentifier("fixture:v1"), recordID: try ExternalIdentifier("fixture:row"))
        return try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard key == .energyConsumed else { return try NutrientEntry(key: key, value: .unknown(.noCompatibleSource)) }
            return try NutrientEntry(key: key, value: .measured(try ExactNutrientValue(amount: 100, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: 100, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [provenance])))
        })
    }

    /// Deterministic records: item `n` (from 1) uses the ID block `n * 100`.
    private static func ledger(_ items: [Item]) throws -> LedgerMutation {
        var records = LedgerMutation()
        for (index, item) in items.enumerated() {
            let base = (index + 1) * 100
            let productID: ProductID = try LedgerFixtures.id(base, ProductTag.self)
            let productVersionID: ProductVersionID = try LedgerFixtures.id(base + 1, ProductVersionTag.self)
            let resolutionID: ResolutionID = try LedgerFixtures.id(base + 2, ResolutionTag.self)
            let resolutionVersionID: ResolutionVersionID = try LedgerFixtures.id(base + 3, ResolutionVersionTag.self)
            let logItemID: LogItemID = try LedgerFixtures.id(base + 4, LogItemTag.self)
            records.products.append(Product(productID: productID, createdAt: LedgerFixtures.date))
            records.productVersions.append(try ProductVersion(productVersionID: productVersionID, productID: productID,
                ordinal: VersionOrdinal(1), name: LedgerText(item.name), itemClass: .food, packFacts: PackFacts(),
                identity: LedgerFixtures.identity(), evidenceIDs: [try LedgerFixtures.id(1, EvidenceTag.self)], assertionIDs: [],
                createdAt: LedgerFixtures.date))
            records.resolutions.append(NutritionResolution(resolutionID: resolutionID, productVersionID: productVersionID,
                                                           basis: item.basis, createdAt: LedgerFixtures.date))
            records.resolutionVersions.append(try NutritionResolutionVersion(resolutionVersionID: resolutionVersionID,
                resolutionID: resolutionID, ordinal: VersionOrdinal(1), methodVersion: LedgerText("fixture_resolution_v1"),
                sourceReleaseIDs: [try ExternalIdentifier("fixture:v1")], nutrients: try nutrients(), createdAt: LedgerFixtures.date))
            records.logItems.append(LogItem(logItemID: logItemID, createdAt: LedgerFixtures.date))
            // Later items are logged later, so the file lists them in this order.
            let occurredAt = LedgerFixtures.date.addingTimeInterval(Double(index * 60) - 7_200)
            var previous: LogItemVersionID?
            // A removal repeats the removed version's amount records, as the domain requires.
            var last: (declaration: EdibleWeightDeclaration?, conversionID: QuantityConversionVersionID?, plateID: PlateWeightVersionID?)
            for (ordinal, version) in item.versions.enumerated() {
                let versionID: LogItemVersionID = try LedgerFixtures.id(base + 10 + ordinal, LogItemVersionTag.self)
                var conversionID: QuantityConversionVersionID?
                if let conversion = version.conversion {
                    let id: QuantityConversionVersionID = try LedgerFixtures.id(base + 20 + ordinal, QuantityConversionVersionTag.self)
                    conversionID = id
                    if version.storesConversion {
                        records.quantityConversions.append(try QuantityConversionVersion(quantityConversionVersionID: id,
                            ordinal: VersionOrdinal(1), sourceQuantity: conversion.source, convertedQuantity: version.quantity,
                            methodVersion: LedgerText(conversion.method),
                            sourceReleaseID: try conversion.release.map { try ExternalIdentifier($0) }, createdAt: LedgerFixtures.date))
                    }
                }
                let plateID: PlateWeightVersionID? = version.plate ? try LedgerFixtures.id(base + 30 + ordinal, PlateWeightVersionTag.self) : nil
                records.logItemVersions.append(try LogItemVersion(logItemVersionID: versionID, logItemID: logItemID,
                    ordinal: VersionOrdinal(ordinal + 1), supersedesLogItemVersionID: previous, occurredAt: occurredAt,
                    reportingDate: LedgerText(day),
                    composition: version.removed ? .removed(try XCTUnwrap(previous)) : .product(productVersionID),
                    edibleQuantity: version.quantity, weightDeclaration: version.removed ? last.declaration : version.declaration,
                    quantityConversionVersionID: version.removed ? last.conversionID : conversionID,
                    plateWeightVersionID: version.removed ? last.plateID : plateID,
                    originalResolutionVersionID: resolutionVersionID, effectiveResolutionVersionID: resolutionVersionID,
                    correctionReason: previous == nil ? nil : LedgerText(version.removed ? "Removed" : "Amount corrected"),
                    createdAt: occurredAt.addingTimeInterval(Double(ordinal))))
                previous = versionID
                if !version.removed { last = (version.declaration, conversionID, plateID) }
            }
        }
        return records
    }

    private static func request(_ records: LedgerMutation, day: String = day) -> FoodDailyExportRequest {
        FoodDailyExportRequest(records: records, reportDate: day, timeZone: london, dataAsOf: dataAsOf, exportedAt: exportedAt,
                               appContext: app)
    }

    /// The built document, checked the way every reader checks it: the shape rule and an exact
    /// byte round trip.
    private static func export(_ items: [Item], file: StaticString = #filePath, line: UInt = #line) throws -> FoodDailyExportDocument {
        try export(records: try ledger(items), file: file, line: line)
    }

    private static func export(records: LedgerMutation, day: String = day, file: StaticString = #filePath,
                               line: UInt = #line) throws -> FoodDailyExportDocument {
        let document = try FoodDailyExportBuilder.make(request(records, day: day))
        XCTAssertEqual(document.foodDailySchemaVersion, 2, file: file, line: line)
        XCTAssertNoThrow(try FoodDailyExportShape.validate(document), file: file, line: line)
        let bytes = try FoodDailyExportSerializer.encode(document)
        XCTAssertEqual(try FoodDailyExportSerializer.encode(FoodDailyExportSerializer.decode(bytes)), bytes, file: file, line: line)
        return document
    }

    private static func method(_ item: Item, file: StaticString = #filePath, line: UInt = #line) throws -> FoodDailyExportQuantity {
        try XCTUnwrap(try export([item], file: file, line: line).entries.first, file: file, line: line).quantity
    }

    private static func conversion(_ source: PositiveQuantity, _ method: String, release: String? = nil) -> Conversion {
        Conversion(source: source, method: method, release: release)
    }

    private static func guide(_ pieces: Double, code: String = boiledMedium, release: String? = guideRelease) throws -> Conversion {
        Conversion(source: try count(pieces), method: code, release: release)
    }

    /// One item per row of contract 3.2, in the table's order. Also the every-code golden day.
    private static func everyCodeDay() throws -> [Item] {
        [
            Item("Synthetic rice", try grams(150)),
            Item("Synthetic cereal bar", try grams(60), conversion: conversion(try count(2), "label-photo-serving-v1")),
            Item("Synthetic chicken", try grams(170), declaration: try declared(.measured, 170)),
            Item("Synthetic potatoes", try grams(140), declaration: try declared(.estimated, 140, original: try count(3))),
            Item("Synthetic plums", try grams(120), conversion: conversion(try count(2), "user_count_conversion_v1:kitchen_scale")),
            Item("Synthetic biscuits", try grams(36), conversion: conversion(try count(3), "user_count_conversion_v1:package_weight")),
            Item("Synthetic boiled eggs", try grams(132), conversion: try guide(3)),
            Item("Synthetic whole milk", try grams(206),
                 conversion: conversion(try millilitres(200), FoodQuantityEstimate.wholeMilkMethodVersion, release: milkRelease)),
            Item("Synthetic dumplings", try grams(200), conversion: conversion(try count(4), typedMethod))
        ]
    }

    // MARK: Test 1, the code mapping

    func testEveryQuantityMethodMapsToExactlyOneCodeAndBothEstimateRulesAgree() throws {
        let records = try Self.ledger(try Self.everyCodeDay())
        let document = try Self.export(records: records)
        let projection = try FoodIntakeProjection(records: records, reportingDate: Self.day)
        XCTAssertEqual(document.entries.count, projection.rows.count)
        var codesByMethod: [String: Set<String>] = [:]
        for (entry, row) in zip(document.entries, projection.rows) {
            XCTAssertEqual(entry.headVersionID, row.logItemVersionID.rawValue)
            let method = try XCTUnwrap(entry.quantity.amountMethod)
            let name: String
            switch row.quantityMethod {
            case .direct: name = "direct"
            case .weighed: name = "weighed"
            case .estimatedByEye: name = "estimated_by_eye"
            case .kitchenScale: name = "kitchen_scale"
            case .packageWeight: name = "package_weight"
            case .typicalWeight: name = "typical_weight"
            case .wholeMilkVolume: name = "whole_milk_volume"
            case .recorded: name = "recorded"
            }
            XCTAssertEqual(method.code, name, "the code is the spelling of the projection row's method (F6)")
            codesByMethod[name, default: []].insert(method.code)
            let head = try XCTUnwrap(records.logItemVersions.first { $0.logItemVersionID == row.logItemVersionID })
            let conversion = records.quantityConversions.first { $0.quantityConversionVersionID == head.quantityConversionVersionID }
            XCTAssertEqual(method.isEstimate, row.quantityMethod.isEstimate, name)
            XCTAssertEqual(method.isEstimate, FoodQuantityEstimate.isEstimate(head, conversion: conversion), name)
            XCTAssertEqual(method.isEstimate, FoodDailyExportShape.codes[method.code], name)
        }
        XCTAssertEqual(Set(codesByMethod.keys), Set(FoodDailyExportShape.codes.keys), "every code of the closed set is reached")
        XCTAssertEqual(document.entries.compactMap { $0.quantity.amountMethod?.code },
                       ["direct", "direct", "weighed", "estimated_by_eye", "kitchen_scale", "package_weight", "typical_weight",
                        "whole_milk_volume", "recorded"])
        // The spellings the writer can produce are the sets the readers admit (gate finding 5).
        XCTAssertEqual(Set(FoodEdibleWeightGuideSize.allCases.map(\.rawValue)), FoodDailyExportShape.sizes)
        XCTAssertEqual(Set(QuantityUnit.allCases.map(\.rawValue)).union(["serving"]), FoodDailyExportShape.enteredUnits)
    }

    // MARK: Test 2, one entry per row

    func testDirectAmountsHaveNoEnteredAmountAndNoSource() throws {
        let direct = Method(code: "direct", isEstimate: false, entered: nil, source: nil)
        let food = try Self.method(Item("Synthetic rice", try Self.grams(150)))
        XCTAssertEqual(food, FoodDailyExportQuantity(amount: 150, unit: "g", weightBasis: "unknown", amountMethod: direct))
        let drink = try Self.method(Item("Synthetic juice", try Self.millilitres(250), basis: .per100Millilitres))
        XCTAssertEqual(drink, FoodDailyExportQuantity(amount: 250, unit: "mL", weightBasis: "unknown", amountMethod: direct))
        // A count on a per-serving basis with no conversion: the exported amount is what was
        // entered, so `entered` is null (3.2 row 1); F1's `serving` unit is for label conversions.
        let serving = try Self.method(Item("Synthetic soup pot", try Self.count(2), basis: .perServing(try Self.grams(300))))
        XCTAssertEqual(serving, FoodDailyExportQuantity(amount: 2, unit: "count", weightBasis: "unknown", amountMethod: direct))
    }

    func testPlainWaterIsDirectMillilitresAndNeverAnEstimate() throws {
        let memory = InMemoryFoodLedgerStore(encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
        let context = try QuickAddContext(TestHarness(name: "memory", committer: memory, reader: memory, cleanup: {}))
        try context.logWater(330)
        let document = try Self.export(records: try context.records())
        XCTAssertEqual(document.entries.first?.quantity,
                       FoodDailyExportQuantity(amount: 330, unit: "mL", weightBasis: "unknown",
                                               amountMethod: Method(code: "direct", isEstimate: false, entered: nil, source: nil)))
        XCTAssertEqual(document.plainWater.knownAmount, 330)
        XCTAssertTrue(document.plainWater.includedInSummaryWater)
    }

    func testWeightDeclarationsExportTheOriginalInputOnlyWhenItDiffers() throws {
        func quantity(_ basis: UserWeightBasis, _ grams: Double, original: PositiveQuantity?, plate: Bool = false,
                      net: Double? = nil) throws -> FoodDailyExportQuantity {
            try Self.method(Item("Synthetic potatoes", try Self.grams(net ?? grams),
                                 declaration: try Self.declared(basis, grams, original: original), plate: plate))
        }
        // Estimated by eye: an original input that differs, one equal to (amount, unit) (F5), none.
        XCTAssertEqual(try quantity(.estimated, 140, original: try Self.count(3)),
                       FoodDailyExportQuantity(amount: 140, unit: "g", weightBasis: "estimated", amountMethod:
                           Method(code: "estimated_by_eye", isEstimate: true, entered: .init(amount: 3, unit: "count"), source: nil)))
        let byEye = Method(code: "estimated_by_eye", isEstimate: true, entered: nil, source: nil)
        XCTAssertEqual(try quantity(.estimated, 140, original: try Self.grams(140)).amountMethod, byEye)
        XCTAssertEqual(try quantity(.estimated, 140, original: nil).amountMethod, byEye, "no stored original input is null, never zero")
        // Weighed.
        let weighed = Method(code: "weighed", isEstimate: false, entered: nil, source: nil)
        XCTAssertEqual(try quantity(.measured, 170, original: nil),
                       FoodDailyExportQuantity(amount: 170, unit: "g", weightBasis: "declared", amountMethod: weighed))
        XCTAssertEqual(try quantity(.measured, 170, original: try Self.grams(170)).amountMethod, weighed)
        XCTAssertEqual(try quantity(.measured, 170, original: try Self.count(1)).amountMethod,
                       Method(code: "weighed", isEstimate: false, entered: .init(amount: 1, unit: "count"), source: nil))
        // The plate path (total minus empty plate) exports as weighed; the original input is
        // compared with the exported net amount, not with the gross total.
        XCTAssertEqual(try quantity(.measured, 500, original: try Self.grams(500), plate: true, net: 170),
                       FoodDailyExportQuantity(amount: 170, unit: "g", weightBasis: "declared", amountMethod:
                           Method(code: "weighed", isEstimate: false, entered: .init(amount: 500, unit: "g"), source: nil)))
        XCTAssertEqual(try quantity(.measured, 500, original: nil, plate: true, net: 170).amountMethod, weighed)
        XCTAssertEqual(try quantity(.measured, 500, original: try Self.grams(170), plate: true, net: 170).amountMethod, weighed)
    }

    func testCountConversionsExportTheCountAndAreNotEstimates() throws {
        for (stored, code) in [("user_count_conversion_v1:kitchen_scale", "kitchen_scale"),
                               ("user_count_conversion_v1:package_weight", "package_weight")] {
            let quantity = try Self.method(Item("Synthetic plums", try Self.grams(120),
                                                conversion: Self.conversion(try Self.count(2), stored)))
            XCTAssertEqual(quantity, FoodDailyExportQuantity(amount: 120, unit: "g", weightBasis: "unknown", amountMethod:
                Method(code: code, isEstimate: false, entered: .init(amount: 2, unit: "count"), source: nil)), code)
        }
    }

    func testEveryGuideSizeRawAndBoiledAndAHalfCountExportAsTypicalWeight() throws {
        XCTAssertEqual(CountPortionGuideCode.entries.count, 8)
        for entry in CountPortionGuideCode.entries {
            for pieces in [3.0, 0.5] {
                let quantity = try Self.method(Item("Synthetic eggs", try Self.grams(entry.grams * pieces),
                                                    conversion: try Self.guide(pieces, code: entry.code)))
                XCTAssertEqual(quantity, FoodDailyExportQuantity(amount: entry.grams * pieces, unit: "g", weightBasis: "unknown", amountMethod:
                    Method(code: "typical_weight", isEstimate: true, entered: .init(amount: pieces, unit: "count"),
                           source: .init(methodVersion: entry.code, sourceReleaseID: Self.guideRelease, size: entry.size.rawValue))),
                    "\(entry.code) x \(pieces)")
            }
        }
        XCTAssertEqual(Set(CountPortionGuideCode.entries.map(\.preparation)), [.raw, .boiled])
        XCTAssertEqual(Set(CountPortionGuideCode.entries.map(\.size)), Set(FoodEdibleWeightGuideSize.allCases))
    }

    func testWholeMilkVolumeExportsTheMillilitresAndANullSize() throws {
        let quantity = try Self.method(Item("Synthetic whole milk", try Self.grams(206), conversion:
            Self.conversion(try Self.millilitres(200), FoodQuantityEstimate.wholeMilkMethodVersion, release: Self.milkRelease)))
        XCTAssertEqual(quantity, FoodDailyExportQuantity(amount: 206, unit: "g", weightBasis: "unknown", amountMethod:
            Method(code: "whole_milk_volume", isEstimate: true, entered: .init(amount: 200, unit: "mL"),
                   source: .init(methodVersion: "cofid-whole-pasteurised-milk-volume-v1", sourceReleaseID: Self.milkRelease, size: nil))))
        let bytes = try FoodDailyExportSerializer.encode(try Self.export([Item("Synthetic whole milk", try Self.grams(206), conversion:
            Self.conversion(try Self.millilitres(200), FoodQuantityEstimate.wholeMilkMethodVersion, release: Self.milkRelease))]))
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains(#""size":null"#), "written, not omitted")
    }

    func testALegacyTypedMethodExportsRecordedWithoutItsText() throws {
        let document = try Self.export([Item("Synthetic dumplings", try Self.grams(200),
                                             conversion: Self.conversion(try Self.count(4), Self.typedMethod))])
        XCTAssertEqual(document.entries.first?.quantity.amountMethod,
                       Method(code: "recorded", isEstimate: false, entered: .init(amount: 4, unit: "count"), source: nil))
        let text = String(decoding: try FoodDailyExportSerializer.encode(document), as: UTF8.self)
        XCTAssertFalse(text.contains(Self.typedMethod), "typed method text never leaves the device")
        XCTAssertFalse(text.contains("brass"))
    }

    /// Real saves, so the `serving` unit is decided by the projection the Food Log row uses (F1).
    func testPastedLabelServingsExportTheServingsEntered() throws {
        let memory = InMemoryFoodLedgerStore(encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
        let harness = TestHarness(name: "memory", committer: memory, reader: memory, cleanup: {})
        let service = try PastedLabelFixtures.service(harness)
        var state = FoodConfirmationState(input: try PastedLabelFixtures.input(PastedLabelFixtures.manifest()), prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.save(state, operationID: LedgerFixtures.operationID(820))
        let conversion = try XCTUnwrap(saved.quantityConversion, "the fixture label states a serving weight")
        XCTAssertTrue(PastedLabelServingPolicy.admittedVersions.contains(conversion.methodVersion.value))
        let records = try (harness.committer as! any FoodArchiveLedgerAccess).archiveState().records
        let document = try Self.export(records: records, day: saved.logItemVersion.reportingDate.value)
        let quantity = try XCTUnwrap(document.entries.first).quantity
        XCTAssertEqual(quantity.amount, conversion.convertedQuantity.value)
        XCTAssertEqual(quantity.unit, "g")
        XCTAssertEqual(quantity.amountMethod, Method(code: "direct", isEstimate: false, entered: .init(amount: 2, unit: "serving"), source: nil))
        let row = try XCTUnwrap(FoodIntakeProjection(records: records, reportingDate: saved.logItemVersion.reportingDate.value).rows.first)
        XCTAssertTrue(row.amountIsServings, "the Food Log row says servings for the same entry")
    }

    func testPhotoLabelServingsExportTheServingsEntered() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("export-v2-photo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FoodLedgerGRDBStore.temporary(directory: directory, encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
        let service = try FoodConfirmationService(ledger: LedgerFixtures.service(store), reader: store, clock: LedgerFixtures.clock,
            ids: RandomLedgerIDGenerator(), digester: LedgerFixtures.digester, pastedLabelConversions: GoldenPastedLabelConversions())
        var state = FoodConfirmationState(input: try LabelPhotoFixtures.input(try LabelPhotoFixtures.manifest()), prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
        state.answerPendingDifferences()
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        let saved = try service.saveLabelPhoto(state, imageBytes: LabelPhotoFixtures.imageBytes, attachmentStore: store,
                                               operationID: LedgerFixtures.operationID(9_981))
        XCTAssertEqual(saved.quantityConversion?.methodVersion.value, "label-photo-serving-v1")
        let records = try store.archiveState().records
        let document = try Self.export(records: records, day: saved.logItemVersion.reportingDate.value)
        XCTAssertEqual(try XCTUnwrap(document.entries.first).quantity,
                       FoodDailyExportQuantity(amount: 60, unit: "g", weightBasis: "unknown", amountMethod:
                           Method(code: "direct", isEstimate: false, entered: .init(amount: 2, unit: "serving"), source: nil)))
    }

    // MARK: Test 3, a rule code without its release

    func testAnEstimateCodeWithoutItsReleaseExportsRecordedAndIsNotAnEstimate() throws {
        let recordedCount = Method(code: "recorded", isEstimate: false, entered: .init(amount: 3, unit: "count"), source: nil)
        for release in [nil, "synthetic:other"] as [String?] {
            let guide = try Self.method(Item("Synthetic eggs", try Self.grams(132), conversion: try Self.guide(3, release: release)))
            XCTAssertEqual(guide.amountMethod, recordedCount, "guide code with \(release ?? "no release")")
            let milk = try Self.method(Item("Synthetic whole milk", try Self.grams(206), conversion:
                Self.conversion(try Self.millilitres(200), FoodQuantityEstimate.wholeMilkMethodVersion, release: release)))
            XCTAssertEqual(milk.amountMethod, Method(code: "recorded", isEstimate: false, entered: .init(amount: 200, unit: "mL"), source: nil),
                           "milk rule with \(release ?? "no release")")
        }
    }

    // MARK: Test 4, parity with the summary

    func testEachEntrysEstimateFlagMatchesItsSummaryContribution() throws {
        let records = try Self.ledger(try Self.everyCodeDay())
        let document = try Self.export(records: records)
        // One entry at a time: the day total's `includes_estimates` for the one known nutrient is
        // exactly that entry's contribution flag (`quantityIsEstimate`).
        for entry in document.entries {
            var alone = records
            alone.logItemVersions.removeAll { $0.logItemVersionID.rawValue != entry.headVersionID }
            let single = try Self.export(records: alone)
            XCTAssertEqual(single.entries.count, 1)
            let energy = try XCTUnwrap(single.summary.first { $0.key == NutrientKey.energyConsumed.rawValue })
            XCTAssertEqual(entry.quantity.amountMethod?.isEstimate, energy.includesEstimates, entry.displayName)
        }
        let energy = try XCTUnwrap(document.summary.first { $0.key == NutrientKey.energyConsumed.rawValue })
        XCTAssertTrue(energy.includesEstimates)
        XCTAssertEqual(document.entries.filter { $0.quantity.amountMethod?.isEstimate == true }.map(\.displayName),
                       ["Synthetic potatoes", "Synthetic boiled eggs", "Synthetic whole milk"])

        // The v6 quirk, pinned so a later change is deliberate (Q4, #344): an estimated-quantity
        // entry whose water value is unknown still sets `includes_estimates` on a water total
        // that knows nothing. The entry-level flag now shows which entry set it.
        let eggs = try Self.export([Item("Synthetic boiled eggs", try Self.grams(132), conversion: try Self.guide(3))])
        let water = try XCTUnwrap(eggs.summary.first { $0.key == NutrientKey.water.rawValue })
        XCTAssertEqual(water.state, "none_known")
        XCTAssertNil(water.knownAmount)
        XCTAssertTrue(water.includesEstimates)
        XCTAssertEqual(eggs.entries.first?.quantity.amountMethod?.isEstimate, true)
        // The same entry weighed sets nothing.
        let weighed = try Self.export([Item("Synthetic boiled eggs", try Self.grams(132), declaration: try Self.declared(.measured, 132))])
        XCTAssertEqual(weighed.summary.first { $0.key == NutrientKey.water.rawValue }?.includesEstimates, false)
    }

    // MARK: Test 5, a missing conversion (Q7)

    func testAContributingHeadWithAMissingConversionProducesNoDocument() throws {
        var missing = Item("Synthetic eggs", try Self.grams(132), conversion: try Self.guide(3))
        missing.versions[0].storesConversion = false
        let records = try Self.ledger([Item("Synthetic rice", try Self.grams(150)), missing])
        XCTAssertThrowsError(try FoodDailyExportBuilder.make(Self.request(records))) {
            XCTAssertEqual($0 as? FoodDailyExportError, .missingReference, "never a `direct` entry in its place")
        }
        // The projection Home and Health use still reads the day (the accepted divergence).
        XCTAssertEqual(try FoodIntakeProjection(records: records, reportingDate: Self.day).rows.map(\.quantityMethod), [.direct, .direct])
    }

    func testASupersededOrRemovedVersionWithAMissingConversionDoesNotBlock() throws {
        // Superseded: the first version names a conversion that is not stored; the head is weighed.
        var corrected = Item("Synthetic eggs", try Self.grams(132), conversion: try Self.guide(3))
        corrected.versions[0].storesConversion = false
        corrected.versions.append(.init(quantity: try Self.grams(128), declaration: try Self.declared(.measured, 128)))
        // Removed: the removed entry's last product version names a conversion that is not stored.
        var removed = Item("Synthetic plums", try Self.grams(120),
                           conversion: Self.conversion(try Self.count(2), "user_count_conversion_v1:kitchen_scale"))
        removed.versions[0].storesConversion = false
        removed.versions.append(.init(quantity: try Self.grams(120), removed: true))
        let document = try Self.export([corrected, removed])
        XCTAssertEqual(document.entries.map(\.displayName), ["Synthetic eggs"], "the removed entry is omitted")
        XCTAssertEqual(document.entries.first?.quantity.amountMethod?.code, "weighed")
    }

    // MARK: Test 6, a corrected entry

    func testACorrectedEntryExportsTheHeadsMethodOnly() throws {
        var item = Item("Synthetic eggs", try Self.grams(132), conversion: try Self.guide(3))
        item.versions.append(.init(quantity: try Self.grams(141),
                                   conversion: Self.conversion(try Self.count(3), "user_count_conversion_v1:kitchen_scale")))
        let document = try Self.export([item])
        let entry = try XCTUnwrap(document.entries.first)
        XCTAssertEqual(entry.quantity, FoodDailyExportQuantity(amount: 141, unit: "g", weightBasis: "unknown", amountMethod:
            Method(code: "kitchen_scale", isEstimate: false, entered: .init(amount: 3, unit: "count"), source: nil)))
        XCTAssertEqual(entry.versions.map(\.ordinal), [1, 2], "history is listed, without per-version methods")
        let text = String(decoding: try FoodDailyExportSerializer.encode(document), as: UTF8.self)
        XCTAssertFalse(text.contains("typical_weight"))
        XCTAssertEqual(document.summary.first { $0.key == NutrientKey.energyConsumed.rawValue }?.includesEstimates, false)

        // A changed size is a new conversion version and exports the new size.
        var resized = Item("Synthetic eggs", try Self.grams(132), conversion: try Self.guide(3))
        resized.versions.append(.init(quantity: try Self.grams(150),
                                      conversion: try Self.guide(3, code: "count_portion_guide_v1:usda_sr_legacy_173424_92500")))
        XCTAssertEqual(try Self.method(resized).amountMethod?.source?.size, "large")
    }

    // MARK: Fail closed (PR 3 gate)

    /// A label servings conversion whose entered amount is not a count has no row in the closed
    /// table: no file, rather than `serving` on grams or an improvised row.
    func testALabelConversionThatIsNotInServingsProducesNoDocument() throws {
        for method in PastedLabelServingPolicy.admittedVersions + ["label-photo-serving-v1"] {
            let records = try Self.ledger([Item("Synthetic cereal bar", try Self.grams(60),
                                                conversion: Self.conversion(try Self.grams(30), method))])
            XCTAssertEqual(try FoodIntakeProjection(records: records, reportingDate: Self.day).rows.first?.quantityMethod, .direct, method)
            XCTAssertThrowsError(try FoodDailyExportBuilder.make(Self.request(records)), method) {
                XCTAssertEqual($0 as? FoodDailyExportAmountMethodError, .labelConversionNotInServings, method)
            }
        }
    }

    /// The method and the estimate rule can disagree only for a measured weight declaration that
    /// also names a source-estimate conversion. No record can hold that pair: the initialiser and
    /// the decoder both refuse it. The builder still checks its own document against the shape
    /// rule, so the pieces are pinned here: a row whose method disagrees with the estimate rule
    /// spells a row the closed table rejects. Because no record can hold the state, `make` itself
    /// cannot be driven into that check from a ledger; this test does not prove the call is there.
    func testAMethodThatDisagreesWithTheEstimateRuleIsUnrepresentableAndRejected() throws {
        let records = try Self.ledger([Item("Synthetic eggs", try Self.grams(132), conversion: try Self.guide(3))])
        let head = try XCTUnwrap(records.logItemVersions.first)
        let conversion = try XCTUnwrap(records.quantityConversions.first)
        XCTAssertThrowsError(try LogItemVersion(logItemVersionID: head.logItemVersionID, logItemID: head.logItemID, ordinal: head.ordinal,
            occurredAt: head.occurredAt, reportingDate: head.reportingDate, composition: head.composition,
            edibleQuantity: head.edibleQuantity, weightDeclaration: try Self.declared(.measured, 132),
            quantityConversionVersionID: head.quantityConversionVersionID,
            originalResolutionVersionID: head.originalResolutionVersionID, effectiveResolutionVersionID: head.effectiveResolutionVersionID,
            createdAt: head.createdAt), "no save route can store the pair")
        var tree = try XCTUnwrap(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(head)) as? [String: Any])
        tree["weightDeclaration"] = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(try Self.declared(.measured, 132)))
        XCTAssertThrowsError(try JSONDecoder().decode(LogItemVersion.self, from: try JSONSerialization.data(withJSONObject: tree)),
                             "a stored record cannot hold the pair either")

        var row = try XCTUnwrap(FoodIntakeProjection(records: records, reportingDate: Self.day).rows.first)
        XCTAssertEqual(try FoodDailyExportBuilder.amountMethod(row, head: head, conversion: conversion).code, "typical_weight")
        row.quantityMethod = .weighed
        let inconsistent = try FoodDailyExportBuilder.amountMethod(row, head: head, conversion: conversion)
        XCTAssertEqual(inconsistent, Method(code: "weighed", isEstimate: true, entered: nil, source: nil))
        XCTAssertThrowsError(try FoodDailyExportShape.validate(inconsistent)) {
            XCTAssertEqual($0 as? FoodDailyExportShapeError, .estimateFlagMismatch(code: "weighed"))
        }
        // A source-backed method read without its conversion or its release never defaults.
        row.quantityMethod = .wholeMilkVolume
        XCTAssertThrowsError(try FoodDailyExportBuilder.amountMethod(row, head: head, conversion: nil)) {
            XCTAssertEqual($0 as? FoodDailyExportAmountMethodError, .conversionNotStored)
        }
        let unreleased = try Self.ledger([Item("Synthetic eggs", try Self.grams(132), conversion: try Self.guide(3, release: nil))])
        XCTAssertThrowsError(try FoodDailyExportBuilder.amountMethod(row, head: try XCTUnwrap(unreleased.logItemVersions.first),
                                                                    conversion: unreleased.quantityConversions.first)) {
            XCTAssertEqual($0 as? FoodDailyExportAmountMethodError, .sourceReleaseNotStored)
        }
    }

    // MARK: Test 9, the goldens this PR adds

    /// Generated files, next to PR 2's four (which `testGoldenFilesAreByteStable` holds the
    /// builder to). `RECORD_FOOD_DAILY_GOLDENS=1` writes only `docs/fixtures/food-daily-v2/`.
    func testTheEveryCodeDayAndTheWholeMilkDayGoldensAreByteStable() throws {
        let milk = [Item("Synthetic whole milk", try Self.grams(206), conversion:
            Self.conversion(try Self.millilitres(200), FoodQuantityEstimate.wholeMilkMethodVersion, release: Self.milkRelease))]
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/fixtures/food-daily-v2").standardizedFileURL
        let record = ProcessInfo.processInfo.environment["RECORD_FOOD_DAILY_GOLDENS"] == "1"
        for (name, items) in [("every-code-day", try Self.everyCodeDay()), ("whole-milk-day", milk)] {
            let bytes = try FoodDailyExportSerializer.encode(try Self.export(items))
            let url = directory.appendingPathComponent("food-daily-\(name).json")
            if record { try bytes.write(to: url) }
            let golden = try Data(contentsOf: url)
            XCTAssertEqual(bytes, golden, "\(name) drifted from its golden")
            let decoded = try FoodDailyExportSerializer.decode(golden)
            XCTAssertEqual(try FoodDailyExportSerializer.encode(decoded), golden, "\(name) re-encodes byte for byte")
            XCTAssertNoThrow(try FoodDailyExportShape.validate(decoded), name)
            let text = String(decoding: golden, as: UTF8.self)
            XCTAssertFalse(text.contains("\n"), "one line, no pretty printing")
            XCTAssertFalse(text.contains(Self.typedMethod), "no typed method text")
        }
        let everyCode = try FoodDailyExportSerializer.decode(try Data(contentsOf: directory.appendingPathComponent("food-daily-every-code-day.json")))
        XCTAssertEqual(Set(everyCode.entries.compactMap { $0.quantity.amountMethod?.code }), Set(FoodDailyExportShape.codes.keys))
    }
}
