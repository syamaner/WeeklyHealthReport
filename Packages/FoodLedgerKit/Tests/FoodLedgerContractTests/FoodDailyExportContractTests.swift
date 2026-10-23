import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// Food daily export contract v1 (#287), Tests: the pure builder over synthetic ledgers and real
/// saves, the closed origin rule, summary parity, the byte form and the golden files under
/// `docs/fixtures/food-daily-v1/`. Set `RECORD_FOOD_DAILY_GOLDENS=1` to rewrite the goldens.
final class FoodDailyExportContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures
    private static let day = "2023-11-14"
    private static let london = TimeZone(identifier: "Europe/London")!
    /// A past day's cutoff: the next local midnight (London is on GMT in November).
    private static let dataAsOf = Date(timeIntervalSince1970: 1_700_006_400)
    private static let exportedAt = Date(timeIntervalSince1970: 1_700_038_800.125)
    private static let app = FoodDailyExportAppContext(appVersion: "0.1.1", appBuild: "42")

    // MARK: Fixtures

    private static func request(_ records: LedgerMutation, day: String = day, exportedAt: Date = exportedAt) -> FoodDailyExportRequest {
        FoodDailyExportRequest(records: records, reportDate: day, timeZone: london, dataAsOf: dataAsOf,
                               exportedAt: exportedAt, appContext: app)
    }

    private static func id<Tag>(_ number: Int, _ tag: Tag.Type) throws -> LedgerID<Tag> { try LedgerFixtures.id(number, tag) }

    private static func provenance(_ kind: ProvenanceSourceKind, record: String? = "fixture:row") throws -> NutrientProvenance {
        if kind == .reviewedWebProposal {
            return NutrientProvenance(sourceKind: kind, sourceID: try ExternalIdentifier("reviewed-web-proposal"),
                sourceReleaseID: try ExternalIdentifier("reviewed-web:" + String(repeating: "a", count: 64)),
                recordID: try ExternalIdentifier("https://example.org/soup/nutrition?q=lentil+soup&ref=search#proposal=c1"),
                evidenceID: try id(77, EvidenceTag.self), capturedAt: LedgerFixtures.date,
                responseHash: try SHA256Digest(String(repeating: "b", count: 64)),
                manifestReference: try LedgerText("manifest-sha256=fixture;candidate=c1"))
        }
        return NutrientProvenance(sourceKind: kind, sourceID: try ExternalIdentifier("fixture"),
            sourceReleaseID: try ExternalIdentifier("fixture:v1"), recordID: try record.map { try ExternalIdentifier($0) })
    }

    private static func exact(_ amount: Double, _ key: NutrientKey, _ kind: ProvenanceSourceKind = .manualDeclaration) throws -> ExactNutrientValue {
        try ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
            sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
            provenance: [provenance(kind)])
    }

    /// A synthetic estimated soup per 100 g: energy estimated (food database), protein estimated
    /// (reviewed web), fat an estimated upper bound, carbohydrates in conflict, the rest unknown.
    private static func soupNutrients() throws -> NutrientSet {
        let fatBound = try NutrientBounds(lower: nil, upper: 0.5, lowerClosed: false, upperClosed: false, origin: .augmented,
            unit: .grams, sourceValue: .bounded(SourceBoundedNutrientValue(lower: nil, upper: 0.5, lowerClosed: false,
                upperClosed: false, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [provenance(.genericCompositionDataset)])
        return try NutrientSet(entries: NutrientKey.allCases.map { key in
            switch key {
            case .energyConsumed: try NutrientEntry(key: key, value: .augmented(exact(50, key, .genericCompositionDataset)))
            case .protein: try NutrientEntry(key: key, value: .augmented(exact(3.2, key, .reviewedWebProposal)))
            case .fatTotal: try NutrientEntry(key: key, value: .bounded(fatBound))
            case .carbohydrates:
                try NutrientEntry(key: key, value: .unknown(.conflictingEvidence), status: .conflict, conflictCandidates: [
                    .augmented(exact(6, key, .genericCompositionDataset)), .augmented(exact(7, key, .genericCompositionDataset))
                ])
            case .water: try NutrientEntry(key: key, value: .augmented(exact(85, key, .genericCompositionDataset)))
            default: try NutrientEntry(key: key, value: .unknown(.noCompatibleSource))
            }
        })
    }

    /// Appends a product, its resolution and one log version per `logs` entry (log item `item`).
    @discardableResult
    private static func append(to records: inout LedgerMutation, base: Int, name: String = "Synthetic lentil soup",
                               itemClass: ItemClass = .food, basis: ResolutionBasis = .per100Grams,
                               nutrients: NutrientSet? = nil,
                               logs: [(version: Int, quantity: PositiveQuantity, day: String, occurredAt: Date, removed: Bool)],
                               declaration: EdibleWeightDeclaration? = nil, addProduct: Bool = true) throws -> LogItemID {
        let productID: ProductID = try id(base, ProductTag.self)
        let productVersionID: ProductVersionID = try id(base + 1, ProductVersionTag.self)
        let resolutionID: ResolutionID = try id(base + 2, ResolutionTag.self)
        let resolutionVersionID: ResolutionVersionID = try id(base + 3, ResolutionVersionTag.self)
        let logItemID: LogItemID = try id(base + 4, LogItemTag.self)
        if addProduct {
            records.products.append(Product(productID: productID, createdAt: LedgerFixtures.date))
            records.productVersions.append(try ProductVersion(productVersionID: productVersionID, productID: productID,
                ordinal: VersionOrdinal(1), name: LedgerText(name), itemClass: itemClass, packFacts: PackFacts(),
                identity: LedgerFixtures.identity(), evidenceIDs: [try id(1, EvidenceTag.self)], assertionIDs: [],
                createdAt: LedgerFixtures.date))
        }
        records.resolutions.append(NutritionResolution(resolutionID: resolutionID, productVersionID: productVersionID,
                                                       basis: basis, createdAt: LedgerFixtures.date))
        records.resolutionVersions.append(try NutritionResolutionVersion(resolutionVersionID: resolutionVersionID,
            resolutionID: resolutionID, ordinal: VersionOrdinal(1), methodVersion: LedgerText("fixture_resolution_v1"),
            sourceReleaseIDs: [try ExternalIdentifier("fixture:v1")], nutrients: nutrients ?? soupNutrients(),
            createdAt: LedgerFixtures.date))
        records.logItems.append(LogItem(logItemID: logItemID, createdAt: LedgerFixtures.date))
        var previous: LogItemVersionID?
        for (ordinal, log) in logs.enumerated() {
            let versionID: LogItemVersionID = try id(log.version, LogItemVersionTag.self)
            records.logItemVersions.append(try LogItemVersion(logItemVersionID: versionID, logItemID: logItemID,
                ordinal: VersionOrdinal(ordinal + 1), supersedesLogItemVersionID: previous, occurredAt: log.occurredAt,
                reportingDate: LedgerText(log.day),
                composition: log.removed ? .removed(try XCTUnwrap(previous)) : .product(productVersionID),
                edibleQuantity: log.quantity, weightDeclaration: log.removed ? nil : declaration,
                originalResolutionVersionID: resolutionVersionID, effectiveResolutionVersionID: resolutionVersionID,
                correctionReason: previous == nil ? nil : LedgerText(log.removed ? "Removed" : "Amount corrected"),
                createdAt: log.occurredAt))
            previous = versionID
        }
        return logItemID
    }

    private static func grams(_ value: Double) throws -> PositiveQuantity { try PositiveQuantity(value: value, unit: .grams) }

    private static func soupDay(quantity: Double = 300) throws -> LedgerMutation {
        var records = LedgerMutation()
        let declaration = try EdibleWeightDeclaration(basis: .estimated, total: grams(quantity), originalInput: nil)
        try append(to: &records, base: 100, logs: [(101_0, try grams(quantity), day, LedgerFixtures.date, false)],
                   declaration: declaration)
        return records
    }

    /// Real saves on one store: a pasted label (printed, calculated, corrected, entered, bounded,
    /// unknown), an exact package entry, plain water, and an exact entry that is then removed.
    /// Deterministic IDs and clock; the synthetic soup is appended to the snapshot afterwards.
    private static func savedDay(_ harness: TestHarness) throws -> LedgerMutation {
        let context = try QuickAddContext(harness)
        let pasted = FoodConfirmationService(ledger: context.ledger, reader: harness.reader, clock: LedgerFixtures.clock,
            ids: context.ids, digester: LedgerFixtures.digester, calendar: QuickAddFixtures.london,
            pastedLabelConversions: GoldenPastedLabelConversions())
        _ = try pasted.save(F.state(F.input(F.manifest())), operationID: context.ids.makeID(OperationTag.self))
        try context.logExact(60, aliases: [], amount: 80)
        try context.logWater(250, occurredAt: LedgerFixtures.date.addingTimeInterval(-600))
        let removed = try context.logExact(61, aliases: [], amount: 40)
        try context.management.remove(logItemID: removed.logItemVersion.logItemID,
                                       expectedVersion: removed.logItemVersion.logItemVersionID,
                                       reason: LedgerText("Logged twice"), operationID: context.ids.makeID(OperationTag.self))
        var records = try context.records()
        let declaration = try EdibleWeightDeclaration(basis: .estimated, total: grams(300), originalInput: nil)
        try append(to: &records, base: 100, logs: [(101_0, try grams(300), day, LedgerFixtures.date.addingTimeInterval(-3600), false)],
                   declaration: declaration)
        return records
    }

    private static func memoryHarness() throws -> TestHarness {
        let memory = InMemoryFoodLedgerStore(encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester)
        return TestHarness(name: "memory", committer: memory, reader: memory, cleanup: {})
    }

    private static func value(_ document: FoodDailyExportDocument, entry: Int, _ key: NutrientKey) throws -> FoodDailyExportNutrientValue {
        try XCTUnwrap(document.entries[entry].nutrients.first { $0.key == key.rawValue })
    }

    private static func total(_ document: FoodDailyExportDocument, _ key: NutrientKey) throws -> FoodDailyExportTotal {
        try XCTUnwrap(document.summary.first { $0.key == key.rawValue })
    }

    // MARK: Builder

    func testEntriesAreTheReportingDaysHeadsWithScaledValuesAndEveryState() throws {
        var records = try Self.soupDay()
        try Self.append(to: &records, base: 200, logs: [(201_0, try Self.grams(100), "2023-11-13", LedgerFixtures.date, false)])
        let document = try FoodDailyExportBuilder.make(Self.request(records))
        XCTAssertEqual(document.entries.count, 1, "the entry on another reporting date is not in the file")
        let entry = document.entries[0]
        XCTAssertEqual(entry.scaleFactor, 3)
        XCTAssertEqual(entry.quantity, FoodDailyExportQuantity(amount: 300, unit: "g", weightBasis: "estimated"))
        XCTAssertEqual(entry.basis, FoodDailyExportBasis(kind: "per_100_g", name: nil, portion: nil))
        XCTAssertEqual(entry.nutrients.map(\.key), NutrientKey.allCases.map(\.rawValue))

        let energy = try Self.value(document, entry: 0, .energyConsumed)
        XCTAssertEqual(energy.state, "estimated")
        XCTAssertEqual(energy.amount, 150, "scaled to the amount eaten")
        XCTAssertEqual(energy.origin, "food_database")
        XCTAssertEqual(energy.calculated, false)
        let fat = try Self.value(document, entry: 0, .fatTotal)
        XCTAssertEqual(fat.state, "bounded")
        XCTAssertNil(fat.lower)
        XCTAssertEqual(fat.upper, 1.5, "bounds are scaled the same way")
        XCTAssertEqual(fat.upperClosed, false)
        XCTAssertEqual(fat.estimated, true)
        let carbohydrates = try Self.value(document, entry: 0, .carbohydrates)
        XCTAssertEqual(carbohydrates.state, "unknown")
        XCTAssertEqual(carbohydrates.reason, "conflicting_evidence")
        XCTAssertEqual(carbohydrates.conflict, true)
        XCTAssertEqual(carbohydrates.candidates?.map(\.amount), [18, 21], "candidates are listed, never resolved")
        XCTAssertEqual(carbohydrates.candidates?.compactMap(\.key), [], "a candidate carries no key")
        let vitaminC = try Self.value(document, entry: 0, .vitaminC)
        XCTAssertEqual(vitaminC.state, "unknown")
        XCTAssertEqual(vitaminC.reason, "no_compatible_source")
        XCTAssertEqual(vitaminC.origin, "food_database", "an unknown carries the source row's origin")
        XCTAssertNil(vitaminC.amount)
    }

    func testReviewedWebProvenanceCarriesOnlyTheSourceURLAndContentHash() throws {
        let document = try FoodDailyExportBuilder.make(Self.request(try Self.soupDay()))
        let protein = try Self.value(document, entry: 0, .protein)
        XCTAssertEqual(protein.origin, "web_review")
        let web = try XCTUnwrap(protein.provenance?.first)
        XCTAssertEqual(web.sourceURL, "https://example.org/soup/nutrition")
        XCTAssertEqual(web.contentHash, String(repeating: "b", count: 64))
        let energy = try XCTUnwrap(try Self.value(document, entry: 0, .energyConsumed).provenance?.first)
        XCTAssertNil(energy.sourceURL)
        XCTAssertNil(energy.contentHash)
        let text = String(decoding: try FoodDailyExportSerializer.encode(document), as: UTF8.self)
        XCTAssertFalse(text.contains("#proposal="), "the record's proposal suffix stays local")
        XCTAssertFalse(text.contains("lentil+soup"), "a query string (search words) never leaves")
        XCTAssertFalse(text.contains("?"), "no query string at all")
        XCTAssertFalse(text.contains("manifest-sha256"), "manifest references stay local")
    }

    func testAnUnscalableEntryIsUnknownWithMissingConversionNeverZero() throws {
        var records = LedgerMutation()
        try Self.append(to: &records, base: 300, logs: [(301_0, try PositiveQuantity(value: 2, unit: .count), Self.day, LedgerFixtures.date, false)])
        let document = try FoodDailyExportBuilder.make(Self.request(records))
        XCTAssertNil(document.entries[0].scaleFactor)
        for key in [NutrientKey.energyConsumed, .protein, .fatTotal] {
            let value = try Self.value(document, entry: 0, key)
            XCTAssertEqual(value.state, "unknown", key.rawValue)
            XCTAssertEqual(value.reason, "missing_conversion", key.rawValue)
            XCTAssertNil(value.amount)
        }
        XCTAssertEqual(try Self.total(document, .energyConsumed).state, "none_known")
        XCTAssertEqual(try Self.total(document, .energyConsumed).incompleteContributions, 1)
        let text = String(decoding: try FoodDailyExportSerializer.encode(document), as: UTF8.self)
        XCTAssertTrue(text.contains(#""scale_factor":null"#), "an unscalable entry states null")
    }

    func testSupersededVersionsAreListedForAuditAndOnlyTheHeadContributes() throws {
        var records = LedgerMutation()
        try Self.append(to: &records, base: 400, logs: [
            (401_0, try Self.grams(100), Self.day, LedgerFixtures.date, false),
            (401_1, try Self.grams(200), Self.day, LedgerFixtures.date.addingTimeInterval(60), false)
        ])
        let document = try FoodDailyExportBuilder.make(Self.request(records))
        let entry = try XCTUnwrap(document.entries.first)
        XCTAssertEqual(entry.headVersionID, try Self.id(401_1, LogItemVersionTag.self).rawValue)
        XCTAssertEqual(entry.versions.map(\.ordinal), [1, 2])
        XCTAssertEqual(entry.versions[1].supersedesVersionID, entry.versions[0].versionID)
        XCTAssertEqual(entry.versions[1].correctionReason, "Amount corrected")
        XCTAssertNil(entry.versions[0].supersedesVersionID)
        XCTAssertEqual(entry.occurredAt, "2023-11-14T22:14:20.000Z", "from the head version")
        XCTAssertEqual(try Self.total(document, .energyConsumed).knownAmount, 100, "the head's 200 g only")
        XCTAssertEqual(try Self.total(document, .energyConsumed).logItemVersionIDs, [entry.headVersionID])
    }

    func testRemovedEntriesAreOmittedFromEntriesAndTotals() throws {
        var records = try Self.soupDay()
        try Self.append(to: &records, base: 500, logs: [
            (501_0, try Self.grams(100), Self.day, LedgerFixtures.date, false),
            (501_1, try Self.grams(100), Self.day, LedgerFixtures.date, true)
        ])
        let document = try FoodDailyExportBuilder.make(Self.request(records))
        XCTAssertEqual(document.entries.map(\.logItemID), [try Self.id(104, LogItemTag.self).rawValue])
        XCTAssertEqual(try Self.total(document, .energyConsumed).knownAmount, 150)
        let text = String(decoding: try FoodDailyExportSerializer.encode(document), as: UTF8.self)
        XCTAssertFalse(text.contains(try Self.id(504, LogItemTag.self).rawValue))
    }

    func testEveryProjectionErrorProducesNoDocument() throws {
        // Two current heads for one log item on the day.
        var competing = try Self.soupDay()
        competing.logItemVersions.append(try LogItemVersion(logItemVersionID: Self.id(101_9, LogItemVersionTag.self),
            logItemID: Self.id(104, LogItemTag.self), ordinal: VersionOrdinal(1), occurredAt: LedgerFixtures.date,
            reportingDate: LedgerText(Self.day), composition: .product(Self.id(101, ProductVersionTag.self)),
            edibleQuantity: Self.grams(10), originalResolutionVersionID: Self.id(103, ResolutionVersionTag.self),
            effectiveResolutionVersionID: Self.id(103, ResolutionVersionTag.self), createdAt: LedgerFixtures.date))
        // A mixture.
        var mixture = try Self.soupDay()
        mixture.logItemVersions.append(try LogItemVersion(logItemVersionID: Self.id(601_0, LogItemVersionTag.self),
            logItemID: Self.id(604, LogItemTag.self), ordinal: VersionOrdinal(1), occurredAt: LedgerFixtures.date,
            reportingDate: LedgerText(Self.day), composition: .mixture([Self.id(101_0, LogItemVersionTag.self)]),
            edibleQuantity: Self.grams(10), originalResolutionVersionID: Self.id(103, ResolutionVersionTag.self),
            effectiveResolutionVersionID: Self.id(103, ResolutionVersionTag.self), createdAt: LedgerFixtures.date))
        // A missing product version.
        var missing = try Self.soupDay()
        missing.productVersions.removeAll()
        // Plain water's wider check: a head on another date competing with one on this day.
        var widerCompeting = try Self.soupDay()
        try Self.append(to: &widerCompeting, base: 700, logs: [(701_0, try Self.grams(10), "2023-11-13", LedgerFixtures.date, false)])
        widerCompeting.logItemVersions.append(try LogItemVersion(logItemVersionID: Self.id(701_9, LogItemVersionTag.self),
            logItemID: Self.id(704, LogItemTag.self), ordinal: VersionOrdinal(1), occurredAt: LedgerFixtures.date,
            reportingDate: LedgerText(Self.day), composition: .product(Self.id(701, ProductVersionTag.self)),
            edibleQuantity: Self.grams(10), originalResolutionVersionID: Self.id(703, ResolutionVersionTag.self),
            effectiveResolutionVersionID: Self.id(703, ResolutionVersionTag.self), createdAt: LedgerFixtures.date))
        let cases: [(String, LedgerMutation, (any Error) -> Bool)] = [
            ("competing", competing, { ($0 as? FoodIntakeProjectionError) == .competingVersions }),
            ("mixture", mixture, { ($0 as? FoodIntakeProjectionError) == .unsupportedMixture }),
            ("missing", missing, { ($0 as? FoodIntakeProjectionError) == .missingReference }),
            ("plain water wider check", widerCompeting, { ($0 as? FoodIntakeProjectionError) == .competingVersions })
        ]
        for (name, records, matches) in cases {
            XCTAssertThrowsError(try FoodDailyExportBuilder.make(Self.request(records)), name) { error in
                XCTAssertTrue(matches(error), "\(name): \(error)")
            }
        }
        // A missing resolution version is a missing reference too, never an empty or partial file.
        var noResolution = try Self.soupDay()
        noResolution.resolutionVersions.removeAll()
        XCTAssertThrowsError(try FoodDailyExportBuilder.make(Self.request(noResolution))) {
            XCTAssertEqual($0 as? FoodDailyExportError, .missingReference)
        }
    }

    func testEmptyDayIsAFileWithEveryNutrientNoneKnownNotZero() throws {
        let document = try FoodDailyExportBuilder.make(Self.request(LedgerMutation()))
        XCTAssertEqual(document.entries, [])
        XCTAssertEqual(document.summary.map(\.key), NutrientKey.allCases.map(\.rawValue))
        XCTAssertTrue(document.summary.allSatisfy { $0.state == "none_known" && $0.knownAmount == nil && $0.logItemVersionIDs.isEmpty })
        XCTAssertEqual(document.plainWater.state, "none_known")
        XCTAssertNil(document.plainWater.knownAmount)
        let text = String(decoding: try FoodDailyExportSerializer.encode(document), as: UTF8.self)
        XCTAssertTrue(text.contains(#""known_amount":null"#), "unknown is an explicit null, never 0")
        XCTAssertFalse(text.contains(#""known_amount":0"#))
    }

    func testPlainWaterIsSeparateFromWaterInFoodsAndLabelled() throws {
        let harness = try Self.memoryHarness()
        let records = try Self.savedDay(harness)
        let document = try FoodDailyExportBuilder.make(Self.request(records))
        XCTAssertEqual(document.plainWater.knownAmount, 250)
        XCTAssertEqual(document.plainWater.state, "complete")
        XCTAssertTrue(document.plainWater.includedInSummaryWater)
        let water = try Self.total(document, .water)
        XCTAssertEqual(water.knownAmount, 505, "250 mL plain water plus 255 mL in the soup")
        XCTAssertEqual(water.state, "known_minimum", "foods without a water value leave it a known minimum")
        XCTAssertEqual(try PlainWaterDayTotal.total(records: records, reportingDate: Self.day)?.knownAmount,
                       document.plainWater.knownAmount)
    }

    func testOverflowedTotalIsUnavailableWithNoAmount() throws {
        var records = LedgerMutation()
        let huge = try NutrientSet(entries: NutrientKey.allCases.map { key in
            key == .protein ? try NutrientEntry(key: key, value: .measured(Self.exact(Double.greatestFiniteMagnitude, key)))
                : try NutrientEntry(key: key, value: .unknown(.notDeclared))
        })
        try Self.append(to: &records, base: 800, nutrients: huge, logs: [(801_0, try Self.grams(100), Self.day, LedgerFixtures.date, false)])
        try Self.append(to: &records, base: 810, nutrients: huge, logs: [(811_0, try Self.grams(100), Self.day, LedgerFixtures.date, false)])
        let document = try FoodDailyExportBuilder.make(Self.request(records))
        let protein = try Self.total(document, .protein)
        XCTAssertEqual(protein.state, "unavailable")
        XCTAssertNil(protein.knownAmount, "never a clamped number")
        XCTAssertEqual(protein.incompleteContributions, 2)
        XCTAssertEqual(protein.logItemVersionIDs, [])
        XCTAssertEqual(try Self.total(document, .energyConsumed).state, "none_known")
    }

    func testExportedAtEarlierThanDataAsOfIsRejected() throws {
        XCTAssertThrowsError(try FoodDailyExportBuilder.make(Self.request(LedgerMutation(),
                                                                          exportedAt: Self.dataAsOf.addingTimeInterval(-0.001)))) {
            XCTAssertEqual($0 as? FoodDailyExportError, .exportedBeforeDataAsOf)
        }
        XCTAssertNoThrow(try FoodDailyExportBuilder.make(Self.request(LedgerMutation(), exportedAt: Self.dataAsOf)))
    }

    // MARK: Summary parity

    func testSummaryEqualsTheHomeAndHealthSummaryForTheSameSnapshot() throws {
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            let records = try Self.savedDay(harness)
            let document = try FoodDailyExportBuilder.make(Self.request(records))
            let projection = try FoodIntakeProjection(records: records, reportingDate: Self.day)
            XCTAssertEqual(document.summaryVersion, FoodIntakeSummary.version)
            XCTAssertEqual(document.summary.count, projection.summary.totals.count)
            for (exported, total) in zip(document.summary, projection.summary.totals) {
                XCTAssertEqual(exported.key, total.key.rawValue)
                XCTAssertEqual(exported.knownAmount, total.knownAmount, "\(harness.name) \(exported.key)")
                XCTAssertEqual(exported.incompleteContributions, total.incompleteContributions, exported.key)
                XCTAssertEqual(exported.includesEstimates, total.includesEstimates, exported.key)
                // Every head counts as known or incomplete exactly once.
                XCTAssertEqual(exported.logItemVersionIDs.count + exported.incompleteContributions, projection.rows.count, exported.key)
            }
            XCTAssertEqual(document.entries.map(\.headVersionID), projection.rows.map(\.logItemVersionID.rawValue))
            XCTAssertEqual(projection.removedRows.count, 1, "the removed entry is in the ledger but not in the file")
        }
    }

    // MARK: Origin rule

    func testEveryProvenanceSourceKindMapsToItsOriginAndAnUnmappedKindFailsClosed() throws {
        let expected: [ProvenanceSourceKind: String] = [
            .userVerifiedPanel: "label_checked_by_you", .manualDeclaration: "entered_by_you",
            .exactProductDataset: "product_database", .genericCompositionDataset: "food_database",
            .recipeReconstruction: "recipe", .reviewedWebProposal: "web_review", .appReferenceDefinition: "app_reference"
        ]
        XCTAssertEqual(Set(expected.keys), Set(ProvenanceSourceKind.allCases), "a new kind needs a contract revision")
        for kind in ProvenanceSourceKind.allCases {
            XCTAssertEqual(try FoodDailyExportOrigin.origin(sourceKind: kind.rawValue), expected[kind])
        }
        XCTAssertThrowsError(try FoodDailyExportOrigin.origin(sourceKind: "future_source")) {
            XCTAssertEqual($0 as? FoodDailyExportError, .unmappedSource("future_source"))
        }
    }

    func testPastedLabelValuesTakeTheirOriginFromTheStoredManifest() throws {
        let document = try FoodDailyExportBuilder.make(Self.request(try Self.savedDay(try Self.memoryHarness())))
        let label = try XCTUnwrap(document.entries.firstIndex { $0.displayName == "Synthetic oat crackers" })
        let origins = try Dictionary(uniqueKeysWithValues: [NutrientKey.energyConsumed, .sodium, .protein, .fiber, .carbohydrates,
                                                            .fatTotal, .fatSaturated, .vitaminC].map {
            ($0, try Self.value(document, entry: label, $0).origin)
        })
        XCTAssertEqual(origins, [.energyConsumed: "calculated", .sodium: "calculated", .protein: "corrected_by_you",
                                 .fiber: "entered_by_you", .carbohydrates: "printed", .fatTotal: "printed",
                                 .fatSaturated: "not_stated", .vitaminC: "not_stated"])
        XCTAssertEqual(try Self.value(document, entry: label, .energyConsumed).calculated, true)
        XCTAssertEqual(try Self.value(document, entry: label, .carbohydrates).calculated, false)
        XCTAssertNil(document.entries[label].basisOrigin, "a v1 manifest records no assisted basis choice")
        let water = try XCTUnwrap(document.entries.firstIndex { $0.itemClass == "water" })
        XCTAssertEqual(try Self.value(document, entry: water, .water).origin, "app_reference")
        XCTAssertEqual(try Self.value(document, entry: water, .calcium).origin, "app_reference")
        let exact = try XCTUnwrap(document.entries.firstIndex { $0.displayName == "Fixture food 60" })
        XCTAssertEqual(try Self.value(document, entry: exact, .protein).origin, "entered_by_you")
        // Excluded content: the pasted label text never leaves.
        let text = String(decoding: try FoodDailyExportSerializer.encode(document), as: UTF8.self)
        XCTAssertFalse(text.contains(F.pastedText.prefix(4)), "pasted label text is excluded")
    }

    func testBasisOriginIsChosenByYouExactlyWhenTheManifestRecordsAnAssistedChoice() throws {
        let harness = try Self.memoryHarness()
        let context = try QuickAddContext(harness)
        let pasted = FoodConfirmationService(ledger: context.ledger, reader: harness.reader, clock: LedgerFixtures.clock,
            ids: context.ids, digester: LedgerFixtures.digester, calendar: QuickAddFixtures.london,
            pastedLabelConversions: GoldenPastedLabelConversions())
        let input = try PastedLabelManifestV2ContractTests.input(.v2(PastedLabelManifestV2ContractTests.v2()))
        _ = try pasted.save(F.state(input), operationID: context.ids.makeID(OperationTag.self))
        _ = try pasted.save(F.state(F.input(F.manifest())), operationID: context.ids.makeID(OperationTag.self))
        let document = try FoodDailyExportBuilder.make(Self.request(try context.records()))
        let byName = Dictionary(uniqueKeysWithValues: document.entries.map { ($0.displayName, $0.basisOrigin) })
        XCTAssertEqual(byName["Synthetic chosen biscuits"], .some("chosen_by_you"))
        XCTAssertEqual(byName["Synthetic oat crackers"], .some(nil))
    }

    // MARK: Byte form and goldens

    func testTimestampsHaveMillisecondsAndTheFrozenZonesOffset() throws {
        let summer = FoodDailyExportTimestamp(timeZone: TimeZone(identifier: "Europe/London")!)
        XCTAssertEqual(summer.string(Date(timeIntervalSince1970: 1_690_000_000.5)), "2023-07-22T05:26:40.500+01:00")
        let taipei = FoodDailyExportTimestamp(timeZone: TimeZone(identifier: "Asia/Taipei")!)
        XCTAssertEqual(taipei.string(Self.dataAsOf), "2023-11-15T08:00:00.000+08:00")
        XCTAssertEqual(FoodDailyExportTimestamp.date("2023-11-15T08:00:00.000+08:00"), Self.dataAsOf)
        XCTAssertEqual(FoodDailyExportTimestamp.date("2023-11-15T00:00:00.000Z"), Self.dataAsOf)
        XCTAssertNil(FoodDailyExportTimestamp.date("2023-11-15T00:00:00Z"), "the health form without milliseconds is not this form")
    }

    func testGoldenFilesAreByteStable() throws {
        let saved = try Self.savedDay(try Self.memoryHarness())
        let waterOnly: LedgerMutation = try {
            let context = try QuickAddContext(try Self.memoryHarness())
            try context.logWater(330)
            return try context.records()
        }()
        let goldens: [(String, LedgerMutation)] = [("mixed-day", saved), ("empty-day", LedgerMutation()), ("plain-water-only", waterOnly)]
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/fixtures/food-daily-v1").standardizedFileURL
        let record = ProcessInfo.processInfo.environment["RECORD_FOOD_DAILY_GOLDENS"] == "1"
        for (name, records) in goldens {
            let bytes = try FoodDailyExportSerializer.encode(FoodDailyExportBuilder.make(Self.request(records)))
            let url = directory.appendingPathComponent("food-daily-\(name).json")
            if record { try bytes.write(to: url) }
            let golden = try Data(contentsOf: url)
            XCTAssertEqual(bytes, golden, "\(name) drifted from its golden")
            let decoded = try FoodDailyExportSerializer.decode(golden)
            XCTAssertEqual(try FoodDailyExportSerializer.encode(decoded), golden, "\(name) re-encodes byte for byte")
            let text = String(decoding: golden, as: UTF8.self)
            XCTAssertFalse(text.contains("_0"), "no synthesized associated-value keys")
            XCTAssertFalse(text.contains("\\/"), "slashes are not escaped")
            XCTAssertFalse(text.contains("\n"), "one line, no pretty printing")
        }
        // A reformatted file decodes but does not re-encode to its own bytes.
        let golden = try Data(contentsOf: directory.appendingPathComponent("food-daily-empty-day.json"))
        let spaced = Data(String(decoding: golden, as: UTF8.self).replacingOccurrences(of: #"{"app_context""#, with: #"{ "app_context""#).utf8)
        XCTAssertNotEqual(try FoodDailyExportSerializer.encode(FoodDailyExportSerializer.decode(spaced)), spaced)
    }
}

extension FoodDailyExportContractTests {
    func testPublicSourceURLKeepsOnlySchemeHostAndPath() {
        XCTAssertEqual(FoodDailyExportBuilder.publicSourceURL("https://example.org/a/b?q=soup#proposal=c1"), "https://example.org/a/b")
        XCTAssertEqual(FoodDailyExportBuilder.publicSourceURL("https://user:pw@example.org:8443/x?y=1"), "https://example.org:8443/x")
        XCTAssertEqual(FoodDailyExportBuilder.publicSourceURL("https://example.org/plain"), "https://example.org/plain")
        XCTAssertNil(FoodDailyExportBuilder.publicSourceURL("not a url"))
        XCTAssertNil(FoodDailyExportBuilder.publicSourceURL("file:///etc/hosts"))
    }
}
