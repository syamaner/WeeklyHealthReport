import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// count-portion-estimate-v1 (#307) on both stores: the bundled egg guide, its closed per-size
/// codes, the service resolving sizes through its own port, reopen and withdrawn guides, the one
/// estimate rule and the v6 day summary. Synthetic ledgers only.
final class CountPortionEstimateContractTests: XCTestCase {
    private static let boiledLarge = "count_portion_guide_v1:usda_sr_legacy_173424_92500"
    private static let boiledMedium = "count_portion_guide_v1:usda_sr_legacy_boiled_from_171287_88378"
    private static let rawLarge = "count_portion_guide_v1:usda_sr_legacy_171287_88374"

    // MARK: 1, 17. Manifest, allow-list and frozen table

    func testManifestEqualsTheFrozenTableAndAllowsExactlyFourRecords() throws {
        let guides = try USDACountPortionGuides()
        XCTAssertEqual(guides.sourceRelease.sourceReleaseID.value, CountPortionGuideCode.sourceReleaseID)
        XCTAssertEqual(guides.sourceRelease.artifactHash.value, "0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef")
        XCTAssertEqual(guides.sourceRelease.licence.value, "CC0 1.0")
        let boiled = try eggCandidate("Eggs, chicken, whole, boiled")
        let raw = try eggCandidate("Eggs, chicken, whole, raw")
        let boiledSet = try XCTUnwrap(guides.guide(for: boiled))
        let rawSet = try XCTUnwrap(guides.guide(for: raw))
        XCTAssertEqual(boiledSet.entries.map(\.size), [.small, .medium, .large, .extraLarge])
        XCTAssertEqual(boiledSet.entries.map(\.edibleGramsPerPiece), [38, 44, 50, 56])
        XCTAssertEqual(boiledSet.defaultCode.value, Self.boiledLarge)
        XCTAssertEqual(boiledSet.entries.map(\.isDerived), [true, true, false, true])
        XCTAssertEqual(rawSet.defaultCode.value, Self.rawLarge)
        XCTAssertEqual(rawSet.entries.map(\.isDerived), [false, false, false, false])
        // Every frozen code is offered by exactly the record family it names, with the table's values.
        let offered = (boiledSet.entries + rawSet.entries)
        XCTAssertEqual(Set(offered.map(\.code.value)), Set(CountPortionGuideCode.entries.map(\.code)))
        for entry in offered {
            let frozen = try XCTUnwrap(CountPortionGuideCode.entry(entry.code))
            XCTAssertEqual(frozen.grams, entry.edibleGramsPerPiece)
            XCTAssertEqual(frozen.size, entry.size)
            XCTAssertEqual(frozen.isDerived, entry.isDerived)
        }
        // Whites, yolks, fried, poached, duck and quail rows of the same release: no guide.
        for row in ["row:1088:7e05033c04d487a1", "row:1098:3f2d3ae9fca8be02", "row:1093:3f2445790cf140d2",
                    "row:1094:53167078fa6bcd73", "row:1095:2214c6e8dac487dc", "row:1101:f9ed3ed89daff271",
                    "row:1102:fdb9e333a3d7e0b1"] {
            let other = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
                sourceReleaseID: boiled.candidate.sourceReleaseID,
                recordID: ExternalIdentifier(boiled.candidate.sourceReleaseID.value + ":" + row),
                identity: boiled.candidate.identity, edibleQuantity: boiled.candidate.edibleQuantity,
                nutrients: boiled.candidate.nutrients, evidenceIDs: boiled.candidate.evidenceIDs), name: boiled.name, itemClass: .food)
            XCTAssertNil(try guides.guide(for: other), row)
        }
        XCTAssertEqual(boiled.candidate.recordID.value, boiled.candidate.sourceReleaseID.value + ":row:1091:0fe190b81c244ccf")
        // A different release with the same row never inherits a guide.
        let otherRelease = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(
            sourceReleaseID: ExternalIdentifier("cofid:2022:sha256:" + String(repeating: "c", count: 64)),
            recordID: boiled.candidate.recordID, identity: boiled.candidate.identity, edibleQuantity: boiled.candidate.edibleQuantity,
            nutrients: boiled.candidate.nutrients, evidenceIDs: boiled.candidate.evidenceIDs), name: boiled.name, itemClass: .food)
        XCTAssertNil(try guides.guide(for: otherRelease))
    }

    func testTamperedManifestBytesAreRefused() throws {
        let data = try manifestData()
        XCTAssertNoThrow(try USDACountPortionGuides(data: data, expectedSHA256: USDACountPortionGuides.manifestSHA256))
        var tampered = data
        tampered.append(0x20)
        XCTAssertThrowsError(try USDACountPortionGuides(data: tampered, expectedSHA256: USDACountPortionGuides.manifestSHA256)) {
            XCTAssertEqual($0 as? USDACountPortionGuidesError, .manifestHashMismatch)
        }
        // A re-pinned manifest whose grams differ from the frozen table is still refused (gate G3).
        let changed = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"grams\": 44.0", with: "\"grams\": 45.0").utf8)
        XCTAssertNotEqual(changed, data)
        XCTAssertThrowsError(try USDACountPortionGuides(data: changed, expectedSHA256: Self.sha256(changed))) {
            XCTAssertEqual($0 as? USDACountPortionGuidesError, .malformedManifest)
        }
        // A manifest missing a frozen code is refused.
        let missing = Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "usda_sr_legacy_boiled_from_171287_88375", with: "usda_sr_legacy_boiled_from_171287_99999").utf8)
        XCTAssertThrowsError(try USDACountPortionGuides(data: missing, expectedSHA256: Self.sha256(missing)))
    }

    // MARK: 2. Calculation

    func testTheTotalIsCountTimesTheSelectedSize() throws {
        let cases: [(String, Double, Double?)] = [
            (Self.boiledLarge, 3, 150), (Self.boiledMedium, 3, 132),
            ("count_portion_guide_v1:usda_sr_legacy_boiled_from_171287_88379", 3, 114),
            ("count_portion_guide_v1:usda_sr_legacy_boiled_from_171287_88375", 3, 168),
            (Self.boiledLarge, 0.5, 25), (Self.boiledLarge, 0, nil), (Self.boiledLarge, .infinity, nil), (Self.boiledLarge, -1, nil),
            ("count_portion_guide_v1:unknown", 3, nil),
        ]
        for (code, count, expected) in cases {
            XCTAssertEqual(CountPortionGuidePolicy.grams(code: try LedgerText(code), count: count), expected, "\(code) × \(count)")
        }
    }

    // MARK: 3, 20. Applicability through the serving policies (gate G6)

    func testAGuideNeverAppliesToServingsGramsOrMillilitres() throws {
        let everything = AnyRecordGuides(real: try USDACountPortionGuides())
        // A source recipe serving and pasted-label servings, even with a provider claiming them.
        let recipe = try XCTUnwrap(RecipeAdmissionFixtures.route()).confirmation
        let servingsOnly = try PastedLabelFixtures.input(PastedLabelFixtures.perServingManifest(readableServingSize: false))
        let per100Serving = try PastedLabelFixtures.input(PastedLabelFixtures.per100Manifest(servingSize:
            .init(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g")))
        for (name, input) in [("recipe", recipe), ("pasted servings only", servingsOnly), ("pasted per 100 g servings", per100Serving)] {
            var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(2, .count))
            XCTAssertNotNil(try everything.guide(for: state.selectedCandidate), name)
            XCTAssertFalse(CountPortionGuidePolicy.admitsRecord(state), name)
            XCTAssertFalse(CountPortionGuidePolicy.applies(state), name)
            FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(Self.rawLarge)))
            XCTAssertNil(state.quantity.portionGuideCode, "the reducer refuses a size on a servings record (\(name))")
            // Forced past the reducer, the service still refuses it.
            state.quantity.portionGuideCode = try LedgerText(Self.rawLarge)
            state.answerPendingDifferences()
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            try forEachStore(guides: everything) { harness, service in
                XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(700)), "\(name) \(harness.name)")
            }
        }
        // Grams and millilitres on an allow-listed record: no guide.
        for unit in [QuantityUnit.grams, .millilitres] {
            var state = try eggsState("Eggs, chicken, whole, boiled", count: 150)
            FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(150, unit))
            XCTAssertFalse(CountPortionGuidePolicy.applies(state))
            FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(Self.boiledLarge)))
            XCTAssertNil(state.quantity.portionGuideCode, unit.rawValue)
        }
        // A candidate switch clears the size; the record's own sizes are offered again by Confirm.
        var state = try eggsState("Eggs, chicken, whole, boiled", count: 3)
        FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(Self.boiledLarge)))
        XCTAssertNotNil(state.quantity.portionGuideCode)
        let unit = state.quantity.unit
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantityUnit(.grams))
        XCTAssertNil(state.quantity.portionGuideCode)
        XCTAssertEqual(unit, .count)
    }

    // MARK: 4, 5, 6, 19. Save, reopen and edit on both stores

    func testEachSizeSavesItsCodeAndReleaseAndReopensSelected() throws {
        let guides = try USDACountPortionGuides()
        try forEachStore(guides: guides) { harness, service in
            for (index, entry) in try XCTUnwrap(guides.guide(for: try eggCandidate("Eggs, chicken, whole, boiled"))).entries.enumerated() {
                var state = try eggsState("Eggs, chicken, whole, boiled", count: 3, guides: guides)
                FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(entry.code))
                XCTAssertTrue(FoodLogPolicy.requirements(state, now: LedgerFixtures.date, calendar: .current).isEmpty, harness.name)
                FoodConfirmationReducer.reduce(state: &state, action: .accept)
                let saved = try service.save(state, operationID: LedgerFixtures.operationID(710 + index))
                let conversion = try XCTUnwrap(saved.quantityConversion, harness.name)
                XCTAssertEqual(conversion.methodVersion, entry.code, harness.name)
                XCTAssertEqual(conversion.sourceQuantity, try PositiveQuantity(value: 3, unit: .count))
                XCTAssertEqual(conversion.convertedQuantity, try PositiveQuantity(value: 3 * entry.edibleGramsPerPiece, unit: .grams))
                XCTAssertEqual(conversion.sourceReleaseID?.value, CountPortionGuideCode.sourceReleaseID)
                XCTAssertNil(conversion.evidenceID)
                XCTAssertEqual(saved.logItemVersion.edibleQuantity, conversion.convertedQuantity)
                XCTAssertNil(saved.logItemVersion.weightDeclaration)
                XCTAssertNotNil(try harness.reader.sourceRelease(id: guides.sourceRelease.sourceReleaseID), "release stored (\(harness.name))")
                let reopened = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
                XCTAssertEqual(reopened.quantity.portionGuideCode, entry.code, harness.name)
                XCTAssertNil(reopened.quantity.conversion)
                XCTAssertFalse(FoodLogPolicy.editChanges(reopened), "an unchanged reopen has no changes (\(harness.name))")
                // Byte stability: the stored conversion decodes and re-encodes unchanged.
                let bytes = try LedgerFixtures.encoder.encode(conversion)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                XCTAssertEqual(try LedgerFixtures.encoder.encode(decoder.decode(QuantityConversionVersion.self, from: bytes)), bytes)
            }
        }
    }

    func testUnchangedResaveReusesTheConversionAndASizeChangeWritesANewVersion() throws {
        let guides = try USDACountPortionGuides()
        try forEachStore(guides: guides) { harness, service in
            let saved = try saveBoiled(service: service, guides: guides, code: Self.boiledLarge, operation: 720)
            var edit = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &edit, action: .setOccurredAt(LedgerFixtures.date.addingTimeInterval(-60)))
            let timeOnly = try service.save(edit, operationID: LedgerFixtures.operationID(721))
            XCTAssertEqual(timeOnly.quantityConversion?.quantityConversionVersionID, saved.quantityConversion?.quantityConversionVersionID,
                           "an unchanged amount reuses the stored conversion (\(harness.name))")
            var resize = try XCTUnwrap(service.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &resize, action: .setPortionGuide(try LedgerText(Self.boiledMedium)))
            let resized = try service.save(resize, operationID: LedgerFixtures.operationID(722))
            XCTAssertEqual(resized.quantityConversion?.methodVersion.value, Self.boiledMedium)
            XCTAssertEqual(resized.quantityConversion?.ordinal.value, 2)
            XCTAssertEqual(resized.quantityConversion?.supersedesQuantityConversionVersionID, saved.quantityConversion?.quantityConversionVersionID)
            XCTAssertEqual(resized.logItemVersion.edibleQuantity, try PositiveQuantity(value: 132, unit: .grams))
        }
    }

    func testAWithdrawnGuideKeepsAnUnchangedEntryButRefusesANewTotal() throws {
        let guides = try USDACountPortionGuides()
        let harnesses = try LedgerFixtures.harnesses()
        defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            let ledger = try LedgerFixtures.service(harness.committer)
            let current = FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock,
                                                  ids: GuideSequenceIDs(), digester: SHA256Digester(), portionGuides: guides)
            let saved = try saveBoiled(service: current, guides: guides, code: Self.boiledLarge, operation: 730)
            let withdrawn = FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock,
                                                    ids: GuideSequenceIDs(seed: 9_000), digester: SHA256Digester(),
                                                    portionGuides: NoGuides(release: guides.sourceRelease))
            var unchanged = try XCTUnwrap(withdrawn.reopen(logItemID: saved.logItem.logItemID))
            XCTAssertEqual(unchanged.quantity.portionGuideCode?.value, Self.boiledLarge)
            FoodConfirmationReducer.reduce(state: &unchanged, action: .setOccurredAt(LedgerFixtures.date.addingTimeInterval(-120)))
            let kept = try withdrawn.save(unchanged, operationID: LedgerFixtures.operationID(731))
            XCTAssertEqual(kept.quantityConversion?.quantityConversionVersionID, saved.quantityConversion?.quantityConversionVersionID, harness.name)
            var recount = try XCTUnwrap(withdrawn.reopen(logItemID: saved.logItem.logItemID))
            FoodConfirmationReducer.reduce(state: &recount, action: .setQuantity(4, .count))
            XCTAssertThrowsError(try withdrawn.save(recount, operationID: LedgerFixtures.operationID(732))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidQuantity, harness.name)
            }
        }
    }

    // MARK: 4. Service closed set (C9), with the view model bypassed

    func testTheServiceRefusesAnyGuideSaveItDidNotResolveItself() throws {
        let guides = try USDACountPortionGuides()
        try forEachStore(guides: guides) { harness, service in
            // A raw code on a boiled record.
            var raw = try eggsState("Eggs, chicken, whole, boiled", count: 3, guides: guides)
            raw.quantity.portionGuideCode = try LedgerText(Self.rawLarge)
            FoodConfirmationReducer.reduce(state: &raw, action: .accept)
            XCTAssertThrowsError(try service.save(raw, operationID: LedgerFixtures.operationID(740))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidQuantity, harness.name)
            }
            // An unknown code under the prefix is not a selected guide: the count still needs an amount.
            var unknown = try eggsState("Eggs, chicken, whole, boiled", count: 3, guides: guides)
            unknown.quantity.portionGuideCode = try LedgerText("count_portion_guide_v1:usda_sr_legacy_173424_99999")
            FoodConfirmationReducer.reduce(state: &unknown, action: .accept)
            XCTAssertThrowsError(try service.save(unknown, operationID: LedgerFixtures.operationID(741))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .unmetRequirements([.countNeedsMeasuredAmount]), harness.name)
            }
            // A conversion draft naming a guide code, with any grams, is refused.
            var drafted = try eggsState("Eggs, chicken, whole, boiled", count: 3, guides: guides)
            FoodConfirmationReducer.reduce(state: &drafted, action: .setConversion(QuantityConversionDraft(
                convertedQuantity: try PositiveQuantity(value: 150, unit: .grams), methodVersion: try LedgerText(Self.boiledLarge),
                sourceReleaseID: guides.sourceRelease.sourceReleaseID)))
            FoodConfirmationReducer.reduce(state: &drafted, action: .accept)
            XCTAssertThrowsError(try service.save(drafted, operationID: LedgerFixtures.operationID(742))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidQuantity, harness.name)
            }
            XCTAssertEqual(try harness.reader.counts().logItemVersions, 0, harness.name)
        }
        // Port grams that differ from the frozen table, and a service with no port.
        for (name, provider) in [("altered grams", AlteredGuides(real: guides) as (any FoodEdibleWeightGuideProviding)?),
                                 ("no port", nil)] {
            try forEachStore(guides: provider) { harness, service in
                var state = try eggsState("Eggs, chicken, whole, boiled", count: 3, guides: guides)
                FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(Self.boiledLarge)))
                FoodConfirmationReducer.reduce(state: &state, action: .accept)
                XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(743))) {
                    XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidQuantity, "\(name) \(harness.name)")
                }
            }
        }
    }

    func testAGuideSaveWithoutItsReleaseInTheInputOrStoreFailsClosed() throws {
        let guides = try USDACountPortionGuides()
        try forEachStore(guides: guides) { harness, service in
            var state = try eggsState("Eggs, chicken, whole, boiled", count: 3, guides: nil)
            XCTAssertFalse(state.input.sourceReleases.contains { $0.sourceReleaseID == guides.sourceRelease.sourceReleaseID })
            FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(Self.boiledLarge)))
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            XCTAssertThrowsError(try service.save(state, operationID: LedgerFixtures.operationID(750))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidQuantity, harness.name)
            }
        }
    }

    // MARK: 8, 9. One estimate rule and the v6 summary

    func testEstimateRuleNeedsTheMethodAndItsReleaseTogether() throws {
        func conversion(_ method: String, _ release: String?) throws -> QuantityConversionVersion {
            try QuantityConversionVersion(quantityConversionVersionID: LedgerFixtures.id(1, QuantityConversionVersionTag.self),
                ordinal: VersionOrdinal(1), sourceQuantity: PositiveQuantity(value: 3, unit: .count),
                convertedQuantity: PositiveQuantity(value: 150, unit: .grams), methodVersion: LedgerText(method),
                sourceReleaseID: try release.map { try ExternalIdentifier($0) }, createdAt: LedgerFixtures.date)
        }
        let milkRelease = "phe-npm-2018:sha256:0abf60c447ac94a075e4d2a8065061e64e8d2fd8278959b3fc284ee858510e1b"
        let cases: [(String, String?, Bool)] = [
            (Self.boiledLarge, CountPortionGuideCode.sourceReleaseID, true),
            (Self.boiledLarge, nil, false),
            (Self.boiledLarge, "synthetic:other", false),
            (FoodQuantityEstimate.wholeMilkMethodVersion, milkRelease, true),
            (FoodQuantityEstimate.wholeMilkMethodVersion, nil, false),
            ("user_count_conversion_v1:kitchen_scale", nil, false),
            ("user_count_conversion_v1:package_weight", nil, false),
            ("weighed on the kitchen scale", nil, false),
            ("estimated", CountPortionGuideCode.sourceReleaseID, false),
        ]
        for (method, release, expected) in cases {
            XCTAssertEqual(FoodQuantityEstimate.isEstimate(declaration: nil, conversion: try conversion(method, release)), expected,
                           "\(method) with \(release ?? "no release")")
        }
        let estimated = try EdibleWeightDeclaration(basis: .estimated, total: PositiveQuantity(value: 150, unit: .grams), originalInput: nil)
        let measured = try EdibleWeightDeclaration(basis: .measured, total: PositiveQuantity(value: 150, unit: .grams), originalInput: nil)
        XCTAssertTrue(FoodQuantityEstimate.isEstimate(declaration: estimated, conversion: nil))
        XCTAssertFalse(FoodQuantityEstimate.isEstimate(declaration: measured, conversion: nil))
        XCTAssertFalse(FoodQuantityEstimate.isEstimate(declaration: nil, conversion: nil))
    }

    func testAGuideDayIncludesEstimatesUnderSummaryV6() throws {
        XCTAssertEqual(FoodIntakeSummary.version, "food-intake-summary-v6")
        let guides = try USDACountPortionGuides()
        try forEachStore(guides: guides) { harness, service in
            let saved = try saveBoiled(service: service, guides: guides, code: Self.boiledMedium, operation: 760)
            let archive = try XCTUnwrap(harness.committer as? any FoodArchiveLedgerAccess)
            let records = try archive.archiveState().records
            let projection = try FoodIntakeProjection(records: records, reportingDate: saved.logItemVersion.reportingDate.value)
            let energy = try XCTUnwrap(projection.summary.totals.first { $0.key == .energyConsumed })
            XCTAssertTrue(energy.includesEstimates, harness.name)
            let row = try XCTUnwrap(projection.rows.first)
            XCTAssertEqual(row.quantityMethod, .typicalWeight(size: .medium, gramsEach: 44))
            XCTAssertEqual(row.enteredAmount, try PositiveQuantity(value: 3, unit: .count))
            XCTAssertEqual(row.quantity, try PositiveQuantity(value: 132, unit: .grams))
            XCTAssertFalse(row.amountIsServings)
        }
    }

    // MARK: - Fixtures

    private func saveBoiled(service: FoodConfirmationService, guides: USDACountPortionGuides, code: String,
                            operation: Int) throws -> StoredFoodConfirmation {
        var state = try eggsState("Eggs, chicken, whole, boiled", count: 3, guides: guides)
        FoodConfirmationReducer.reduce(state: &state, action: .setPortionGuide(try LedgerText(code)))
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        return try service.save(state, operationID: LedgerFixtures.operationID(operation))
    }

    private func eggCandidate(_ name: String) throws -> PopulatedFoodCandidate {
        let search = try CoFIDGenericFoodSearch(ids: GuideSequenceIDs(seed: 60_000))
        let words = name.replacingOccurrences(of: ",", with: "").split(separator: " ")
        let queries = [words.joined(separator: " "), "\(words.last ?? "") egg", "\(words.last ?? "") eggs", "egg \(words.last ?? "")"]
        for query in queries {
            let request = GenericFoodSearchRequest(text: try LedgerText(query), identity: GenericFoodIdentityQuery(),
                                                   capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"))
            if case let .confirmation(route) = try search.search(request),
               let match = route.matches.first(where: { $0.candidate.name.value == name }) {
                return match.candidate
            }
        }
        XCTFail("Expected the CoFID record \(name)")
        throw FoodLedgerValidationError.invalidProvenance
    }

    /// A Confirm state for one CoFID egg record, with the guide release added as the composition
    /// root adds it (or not, when `guides` is nil).
    private func eggsState(_ name: String, count: Double, guides: USDACountPortionGuides? = nil) throws -> FoodConfirmationState {
        let search = try CoFIDGenericFoodSearch(ids: GuideSequenceIDs(seed: 70_000))
        let request = GenericFoodSearchRequest(text: try LedgerText(name.replacingOccurrences(of: ",", with: "")),
                                               identity: GenericFoodIdentityQuery(),
                                               capturedAt: LedgerFixtures.date, locale: try LedgerText("en_GB"))
        guard case let .confirmation(route) = try search.search(request),
              let egg = route.matches.first(where: { $0.candidate.name.value == name })?.candidate else {
            throw XCTSkip("Expected the CoFID record \(name)")
        }
        let releases = route.confirmation.sourceReleases + (guides.map { [$0.sourceRelease] } ?? [])
        let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence, sourceReleases: releases, candidates: [egg],
            expectedIdentity: egg.candidate.identity, expectedEdibleQuantity: egg.candidate.edibleQuantity)
        var state = FoodConfirmationState(input: input, prefillSourceQuantity: false)
        FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(count, .count))
        return state
    }

    private func manifestData() throws -> Data {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "count-portion-guides-v1", withExtension: "json")
            ?? Self.repositoryManifestURL())
        return try Data(contentsOf: url)
    }

    private static func repositoryManifestURL() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let manifest = url.appendingPathComponent("Sources/FoodGenericSearch/Resources/count-portion-guides-v1.json")
        return FileManager.default.fileExists(atPath: manifest.path) ? manifest : nil
    }

    private static func sha256(_ data: Data) -> String {
        (try? SHA256Digester().sha256(data).value) ?? ""
    }

    private func forEachStore(guides: (any FoodEdibleWeightGuideProviding)?,
                              _ body: (TestHarness, FoodConfirmationService) throws -> Void) throws {
        let harnesses = try LedgerFixtures.harnesses()
        defer { harnesses.forEach { $0.cleanup() } }
        for harness in harnesses {
            let ledger = try LedgerFixtures.service(harness.committer)
            let service = FoodConfirmationService(ledger: ledger, reader: harness.reader, clock: LedgerFixtures.clock,
                                                  ids: GuideSequenceIDs(), digester: SHA256Digester(), portionGuides: guides)
            try body(harness, service)
        }
    }
}

/// Claims every record, to prove the serving policies (not the provider) decide applicability.
private struct AnyRecordGuides: FoodEdibleWeightGuideProviding {
    let real: USDACountPortionGuides
    var sourceRelease: SourceRelease { real.sourceRelease }
    func guide(for candidate: PopulatedFoodCandidate) throws -> FoodEdibleWeightGuideSet? {
        let entries = try CountPortionGuideCode.entries.filter { $0.preparation == .raw }.map {
            try FoodEdibleWeightGuide(code: LedgerText($0.code), size: $0.size, sourceDescriptor: LedgerText($0.sourceDescriptor),
                                      edibleGramsPerPiece: $0.grams, isDerived: $0.isDerived)
        }
        return try FoodEdibleWeightGuideSet(foodRecordID: candidate.candidate.recordID, foodSourceReleaseID: candidate.candidate.sourceReleaseID,
            entries: entries, defaultCode: LedgerText("count_portion_guide_v1:usda_sr_legacy_171287_88374"))
    }
}

/// The real sets with every weight 10 g heavier than the frozen table.
private struct AlteredGuides: FoodEdibleWeightGuideProviding {
    let real: USDACountPortionGuides
    var sourceRelease: SourceRelease { real.sourceRelease }
    func guide(for candidate: PopulatedFoodCandidate) throws -> FoodEdibleWeightGuideSet? {
        guard let set = try real.guide(for: candidate) else { return nil }
        return try FoodEdibleWeightGuideSet(foodRecordID: set.foodRecordID, foodSourceReleaseID: set.foodSourceReleaseID,
            entries: set.entries.map { try FoodEdibleWeightGuide(code: $0.code, size: $0.size, sourceDescriptor: $0.sourceDescriptor,
                                                                 edibleGramsPerPiece: $0.edibleGramsPerPiece + 10, isDerived: $0.isDerived) },
            defaultCode: set.defaultCode)
    }
}

/// A later manifest that withdrew every guide.
private struct NoGuides: FoodEdibleWeightGuideProviding {
    let release: SourceRelease
    var sourceRelease: SourceRelease { release }
    func guide(for candidate: PopulatedFoodCandidate) throws -> FoodEdibleWeightGuideSet? { nil }
}

private final class GuideSequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    init(seed: Int = 8_000) { value = seed }
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
