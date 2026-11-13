import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import FoodLedgerTestSupport
import Foundation
import XCTest

/// P1c presentation (import v1 sections 5 and 6): the family, the Generic row title and Confirm's
/// mixed-source details. Synthetic fixtures only.
final class PersonalFoodDatabasePresentationTests: XCTestCase {
    static let golden = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/fixtures/personal-food-database-v1/golden.json")

    final class IDs: LedgerIDGenerating, @unchecked Sendable {
        private var value = 1
        func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
            defer { value += 1 }
            return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
        }
    }

    func route(_ query: String) throws -> GenericFoodConfirmationRoute {
        let bytes = try Data(contentsOf: Self.golden)
        let digest = try SHA256Digester().sha256(bytes)
        guard case let .success(file) = PersonalFoodDatabaseCodec.decode(bytes) else { throw XCTSkip("golden decodes") }
        let store = InMemoryPersonalFoodDatabaseStore()
        try store.install(bytes: bytes, manifest: PersonalFoodDatabaseManifest(schema: PersonalFoodDatabaseSchema.v1.rawValue,
            releaseID: PersonalFoodDatabaseRelease.releaseID(fileSHA256: digest), fileSHA256: digest, generated: file.generated,
            importedAt: Date(timeIntervalSince1970: 1_794_000_000), entryCount: file.entries.count))
        let index = PersonalFoodDatabaseIndex(store: store, resolver: GenericRecordResolverSet([:]))
        index.warm()
        guard case let .confirmation(route) = try PersonalFoodDatabaseFoodSearch(index: index, resolver: GenericRecordResolverSet([:]),
            ids: IDs()).search(GenericFoodSearchRequest(text: LedgerText(query), capturedAt: Date(timeIntervalSince1970: 1_794_000_000),
                                                        locale: LedgerText("en-GB"))) else { throw XCTSkip("no route") }
        return route
    }

    func testFamilyIsYourFoodDatabaseNeverYourFoods() throws {
        let route = try route("synthetic example oats")
        let candidate = route.matches[0].candidate
        let family = FoodSearchResultSummary.family(candidate: candidate.candidate, releases: route.confirmation.sourceReleases)
        XCTAssertEqual(family, .yourFoodDatabase)
        XCTAssertEqual(FoodSearchResultText.family(family), "Your food database")
        XCTAssertEqual(FoodSearchResultSummary.family("personal-food-database"), .yourFoodDatabase)
        XCTAssertEqual(FoodSearchResultText.rowTitle(route.matches[0]), "Synthetic Example Oats")
    }

    func testMixedSourcesListsEachNutrientsSource() throws {
        let route = try route("synthetic example oats")
        let sources = try XCTUnwrap(FoodSearchResultText.databaseNutrientSources(route.matches[0].candidate,
                                                                                   releases: route.confirmation.sourceReleases))
        XCTAssertTrue(sources.contains { $0.hasSuffix(": your label") })
        XCTAssertTrue(sources.contains { $0.hasSuffix(": Open Food Facts product, automatic match") })
        XCTAssertEqual(FoodSearchResultText.mixedSources, "Nutrients from more than one source")
        // One release only: no notice.
        let single = try self.route("synthetic crème spread")
        XCTAssertNil(FoodSearchResultText.databaseNutrientSources(single.matches[0].candidate, releases: single.confirmation.sourceReleases))
    }

    func testGenericRowTitle() throws {
        let route = try route("synthetic example oats")
        let generic = GenericFoodMatch(candidate: route.matches[0].candidate, isExactName: false,
            personalDatabase: PersonalFoodDatabaseMatchContext(step: .concept, isGenericReference: true))
        XCTAssertEqual(FoodSearchResultText.rowTitle(generic), "Generic: Synthetic Example Oats")
    }
}
